-- The rounds of a run (GDD 5, 14, 21): prepare, fight, clear, pay, prepare the next. MatchService owns the run around
-- them (arrival, the wipe, the return to the lobby).
--
-- A CLEARED ROUND PAYS ONCE (GDD 23), in one profile write per player, when the clear happens and never on a skip. A
-- wave skipped by vote stays open beside the next one, its bodies counted as its own, and the open waves clear oldest
-- first, so a round is paid only once it and every round before it are actually cleared (GDD 21).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local Signal = require(ReplicatedStorage.Packages.Signal)
local jecs = require(ReplicatedStorage.Packages.jecs)
local Network = require(ServerScriptService.GlobalServer.Network)
local DatabaseService = require(ServerScriptService.GlobalServer.Services.DatabaseService)
local EquipmentService = require(ServerScriptService.GlobalServer.Services.EquipmentService)
local BossIntroService = require(script.Parent.BossIntroService)
local EconomyService = require(script.Parent.EconomyService)
local EnemiesService = require(script.Parent.EnemiesService)
local NavService = require(script.Parent.NavService)
local upgradeStats = require(script.Parent.Parent.Utils.upgradeStats)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local MapsCore = require(ReplicatedStorage.GlobalShared.Core.MapsCore)
local ShopCore = require(ReplicatedStorage.GlobalShared.Core.ShopCore)
local ArenaCore = require(ReplicatedStorage.Shared.Core.ArenaCore)
local EnemiesCore = require(ReplicatedStorage.Shared.Core.EnemiesCore)
local RoundCore = require(ReplicatedStorage.Shared.Core.RoundCore)
local TimeCore = require(ReplicatedStorage.Shared.Core.TimeCore)
local Components = require(ReplicatedStorage.GlobalShared.ECS.Components)
local Tags = require(ReplicatedStorage.GlobalShared.ECS.Tags)
local World = require(ReplicatedStorage.GlobalShared.ECS.Worlds.World)
local EUpgradesIds = require(ReplicatedStorage.Types.Enums.Data.EUpgradesIds)
local TData = require(ReplicatedStorage.Types.TData)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)
local TProfile = require(ReplicatedStorage.Types.TProfile)

local ServerNetworkRounds = Network.Server.Rounds
local ServerNetworkEconomy = Network.Server.Economy
local ClientNetworkRounds = Network.Client.Rounds

local ALL_ENEMIES = DataCore.Enemies.All
local ENEMIES = DataCore.Enemies.ById
-- The players bodies enter round: standing, and not picking an upgrade, whom the crowd would only walk away from.
-- With nobody left, the spawns wait.
local CharactersQuery = World:query(Components.HumanoidRootPart, Components.InstanceId)
	:with(Tags.Character, Tags.Alive)
	:without(Tags.Picking)
	:cached()

local Tune = table.freeze({
	-- Bodies enter on a ring around a random living player.
	RING_MIN_RADIUS = 60,
	RING_MAX_RADIUS = 85,
	SPAWN_TRIES = 6,
	-- The HUD's enemies-left count goes out at most this often; a volley that kills thirty is one message.
	REMAINING_INTERVAL = 0.1,
})

local ERoundState = table.freeze({
	Idle = 0,
	Preparing = 1,
	Fighting = 2,
})

-- A round being fought: what it still has to spawn, and how many of its bodies are alive.
type TOpenRound = {
	Round: number,
	ToSpawn: number,
	IsBossPending: boolean,
	-- TimeCore.GameClock its boss comes on, once the kills reach its way's end (bringBoss); math.huge until then.
	BossAt: number,
	Alive: number,
	HealthScale: number,
	DamageScale: number,
	SpeedScale: number,
	Pool: { TData.TEnemy },
	PoolWeight: number,
}

-- A round opened whose worth of kills is not reached yet: its bodies and its boss.
type TUncountedRound = {
	Round: number,
	Size: number,
}

local RoundService = {}

RoundService.ERoundState = ERoundState
RoundService.State = ERoundState.Idle
-- The newest round opened.
RoundService.Round = 0
-- The highest round cleared together with every round before it, this run.
RoundService.LastCleared = 0
-- The record key the run's clears go under ("Baseplate:Solo") and the map its waves are drawn for, set by
-- MatchService at the start of the run.
RoundService.RecordKey = "Baseplate:Solo"
RoundService.MapName = MapsCore.DEFAULT
-- Set from the console. The wave being fought stays open, since what it has still to spawn is not cleared.
RoundService.IsSpawningPaused = false

-- (round), after its rewards are paid.
RoundService.OnRoundCleared = Signal.new()
-- (round), once the run's kills reach that round's size added to every size before it, whichever bodies fell: a
-- count, not a clear. Never after OnRoundCleared for the same round.
RoundService.OnRoundKilled = Signal.new()
-- (round)
RoundService.OnRoundStarted = Signal.new()

local prepareEndsAt = 0
-- Seconds the next countdown is held over its own length (HoldNextPrepare).
local prepareHoldSeconds = 0
-- TimeCore.GameClock the newest round's SKIP WAVE vote opens at.
local skipOpensAt = 0
-- Whether the newest wave could be skipped when last looked at, so the moment it can is a count of its own.
local wasSkippable = false
local votes: { [Player]: boolean } = {}
-- Oldest first. More than one only after a skip.
local openRounds: { TOpenRound } = {}
local roundOf: { [jecs.Entity<any>]: TOpenRound } = {}
local bosses: { [jecs.Entity<any>]: boolean } = {}
-- Bosses up outside any round (the console's `boss`): no round counts them, so no clear waits on them (HoldForBoss).
local loneBosses: { [jecs.Entity<any>]: boolean } = {}
local spawnAccumulator = 0
local random = Random.new()
local reusableRoots: { BasePart } = {}
local reusableRootIds: { number } = {}
local sentRemaining = 0
local nextRemainingAt = 0
-- Oldest first, and the kills counted since the last round was reached (OnRoundKilled).
local uncountedRounds: { TUncountedRound } = {}
local uncountedKills = 0
-- The HUD's way to the next boss: the kills counted on each boss's way (by its round, RoundCore.BossRoundOf), each
-- round's size once it has opened (the rest are worked out for the party here), and what was last sent.
local wayKills: { [number]: number } = {}
local roundSizes: { [number]: number } = {}
local sentWayRound, sentWayKills, sentWayNeeded = -1, -1, -1
local nextWayAt = 0
-- The newest boss round whose boss has fallen (or that had none): the way runs to the boss after it. A boss round can
-- stay open past its boss's fall, its own bodies still about after a skip.
local wayDoneRound = 0

local function isAutoSkip(player: Player): boolean
	local profile = DatabaseService.Get(player)
	return profile ~= nil and profile.Settings.IsAutoSkip
end

-- A boss on its way (the kills of its way are made) or up: no wave is skipped and no upgrade hand dealt until it falls.
-- Its wave is skipped like any other before then.
function RoundService.IsBossTime(): boolean
	if next(bosses) ~= nil or next(loneBosses) ~= nil then return true end
	for _, open in openRounds do
		if open.IsBossPending and open.BossAt ~= math.huge then return true end
	end

	return false
end

local function canSkip(): boolean
	return RoundService.State == ERoundState.Fighting
		and TimeCore.GameClock >= skipOpensAt
		and not RoundService.IsBossTime()
end

-- Players counted toward SKIP WAVE: a vote, or auto-skip, which votes as soon as it opens. There is no vote during a
-- countdown: it always plays out.
local function countVotes(): (number, number)
	local isAutoCounted = canSkip()
	local count, needed = 0, 0
	for _, player in Players:GetPlayers() do
		needed += 1
		if votes[player] or (isAutoCounted and isAutoSkip(player)) then
			count += 1
		end
	end

	return count, needed
end

-- Bodies still to kill across the open rounds, spawned or still to come, bosses included.
local function countRemaining(): number
	local remaining = 0
	for _, open in openRounds do
		remaining += open.ToSpawn + open.Alive + (if open.IsBossPending then 1 else 0)
	end

	return remaining
end

local function getBoss(round: number): TData.TEnemy?
	return RoundCore.GetBoss(round, RoundService.MapName, ENEMIES, EnemiesCore.HasModel)
end

-- Skips the wave being fought into the next one's countdown once everyone counts; otherwise tells everyone the count.
local function checkVotes()
	if RoundService.State == ERoundState.Idle then return end
	local count, needed = countVotes()
	if needed == 0 or count < needed or not canSkip() then
		ServerNetworkRounds.Votes.FireAll(count, needed)
		return
	end

	RoundService.Prepare(RoundService.Round + 1)
end

-- Opens the fight for RoundService.Round, beside any round a skip left open.
local function fight()
	local round = RoundService.Round
	RoundService.State = ERoundState.Fighting
	local healthScale, damageScale, speedScale = RoundCore.GetScales(round)
	local pool: { TData.TEnemy } = {}
	-- A boss round on a map with no boss is an ordinary one.
	local hasBoss = RoundCore.IsBossRound(round) and getBoss(round) ~= nil
	local toSpawn = RoundCore.GetCount(round, #Players:GetPlayers())
	uncountedRounds[#uncountedRounds + 1] = { Round = round, Size = toSpawn }
	roundSizes[round] = toSpawn
	openRounds[#openRounds + 1] = {
		Round = round,
		ToSpawn = toSpawn,
		IsBossPending = hasBoss,
		BossAt = math.huge,
		Alive = 0,
		HealthScale = healthScale,
		DamageScale = damageScale,
		SpeedScale = speedScale,
		Pool = pool,
		PoolWeight = RoundCore.GetPool(round, RoundService.MapName, ALL_ENEMIES, pool),
	}
	skipOpensAt = TimeCore.GameClock + RoundCore.GetSkipAfterSeconds(round)
	wasSkippable = canSkip()
	table.clear(votes)

	-- Reaching a round is recorded too: the hard map's gate may be set on reaching rather than clearing (GDD 8).
	local key = RoundService.RecordKey
	for _, player in Players:GetPlayers() do
		DatabaseService.Update(player, function(profile)
			local record: TProfile.TRecord = profile.Records[key] or { HighestReached = 0, HighestCompleted = 0 }
			if record.HighestReached >= round then return false end
			record.HighestReached = round
			profile.Records[key] = record
			return true
		end)
	end

	sentRemaining = countRemaining()
	ServerNetworkRounds.Started.FireAll(round, sentRemaining)
	RoundService.OnRoundStarted:Fire(round)
	-- A wave everyone skips as it opens (an early one, on auto-skip) goes into the next countdown on this frame: both
	-- events reach clients in one packet, so the HUD never drops the boss strip in for a wave gone a frame later.
	checkVotes()
end

-- Opens the preparation before `round`: its countdown, after a clear or a skip alike. None with a boss coming or up
-- (a console boss, as a wave clears): one frame of countdown would tuck the boss strip away and drop it back in.
function RoundService.Prepare(round: number)
	RoundService.Round = round
	if RoundService.IsBossTime() then
		fight()
		return
	end

	RoundService.State = ERoundState.Preparing
	table.clear(votes)
	spawnAccumulator = 0
	local seconds = RoundCore.PREPARE_SECONDS + prepareHoldSeconds
	prepareHoldSeconds = 0
	prepareEndsAt = TimeCore.GameClock + seconds
	ServerNetworkRounds.Preparing.FireAll(round, seconds, RoundCore.IsBossRound(round))
	checkVotes()
end

-- The next countdown waits `seconds` longer than its own length, for whatever a clear's listener has put in front of
-- the players (their upgrade cards). Called from an OnRoundCleared listener, which runs before that countdown opens.
function RoundService.HoldNextPrepare(seconds: number)
	prepareHoldSeconds = math.max(prepareHoldSeconds, seconds)
end

-- What was holding the countdown is over: a countdown still in its held time is cut to its own length.
function RoundService.ReleasePrepare()
	prepareHoldSeconds = 0
	if RoundService.State ~= ERoundState.Preparing then return end
	if prepareEndsAt - TimeCore.GameClock <= RoundCore.PREPARE_SECONDS then return end
	prepareEndsAt = TimeCore.GameClock + RoundCore.PREPARE_SECONDS
	ServerNetworkRounds.Preparing.FireAll(
		RoundService.Round,
		RoundCore.PREPARE_SECONDS,
		RoundCore.IsBossRound(RoundService.Round)
	)
end

-- A boss up outside any round holds the run as a boss wave does: no bodies pour in and no wave is skipped until it
-- falls.
function RoundService.HoldForBoss(enemyEntity: jecs.Entity<any>)
	loneBosses[enemyEntity] = true
end

-- Catches a late joiner up on the way to the next boss, which is otherwise sent only as it moves.
function RoundService.SendWay(player: Player)
	if sentWayNeeded < 0 then return end
	ServerNetworkRounds.BossWay.Fire(player, sentWayRound, sentWayKills, sentWayNeeded)
end

-- A new run, from round 1.
function RoundService.Begin()
	RoundService.LastCleared = 0
	RoundService.Prepare(1)
end

function RoundService.Stop()
	RoundService.State = ERoundState.Idle
	table.clear(openRounds)
	table.clear(roundOf)
	table.clear(bosses)
	table.clear(loneBosses)
	table.clear(votes)
	table.clear(uncountedRounds)
	uncountedKills = 0
	table.clear(wayKills)
	table.clear(roundSizes)
	sentWayRound, sentWayKills, sentWayNeeded = -1, -1, -1
	wayDoneRound = 0
	prepareHoldSeconds = 0
end

-- The highest floor at (x, z) the player's field reaches: a roof, a canopy or a ledge nothing climbs to would hold the
-- body there for the whole wave. Before the field's first flood, the highest floor.
local function pickReachableFloor(nav: ArenaCore.TNavGrid, field: NavService.TNavField?, x: number, z: number): number?
	local node = ArenaCore.NodeAt(nav, x, math.huge, z, 0)
	while node ~= ArenaCore.NO_NODE do
		local y = ArenaCore.NodeHeight(nav, node)
		if not field or not field.IsReady or buffer.readu32(field.Dist, node * 4) ~= NavService.INF then return y end
		node = ArenaCore.NodeAt(nav, x, y - 0.01, z, 0)
	end

	return nil
end

-- On a ring around one living player, on a floor that leads to them: enemies come to the players, wherever they are,
-- and drop in where they land (EnemiesController's arrival).
local function pickSpawnPosition(): vector?
	table.clear(reusableRoots)
	table.clear(reusableRootIds)
	for _, rootPart, instanceId in CharactersQuery do
		reusableRoots[#reusableRoots + 1] = rootPart
		reusableRootIds[#reusableRootIds + 1] = instanceId
	end

	if #reusableRoots == 0 then return nil end
	local pick = random:NextInteger(1, #reusableRoots)
	local center = reusableRoots[pick].Position
	local field = NavService.CharacterFields[reusableRootIds[pick]]
	local nav = ArenaCore.Nav

	for _ = 1, Tune.SPAWN_TRIES do
		local angle = random:NextNumber(0, 2 * math.pi)
		local radius = random:NextNumber(Tune.RING_MIN_RADIUS, Tune.RING_MAX_RADIUS)
		local x = center.X + math.cos(angle) * radius
		local z = center.Z + math.sin(angle) * radius
		local floorY = if nav then pickReachableFloor(nav, field, x, z) else ArenaCore.FlatY
		if floorY then return vector.create(x, floorY, z) end
	end

	return nil
end

local function track(open: TOpenRound, enemyEntity: jecs.Entity<any>?)
	if not enemyEntity then return end
	open.Alive += 1
	roundOf[enemyEntity] = open
end

-- A boss comes once its wave's kills are made and the HUD has let it in (bringBoss), then plays its intro
-- (BossIntroService). The hands up are put away for it (UpgradesService); it waits while every player is still
-- watching the card they took.
local function spawnBosses()
	if TimeCore.IsHeld then return end
	for _, open in openRounds do
		if not open.IsBossPending or TimeCore.GameClock < open.BossAt then continue end
		if not EnemiesService.HasRoom() then return end
		local boss = getBoss(open.Round)
		if not boss then
			open.IsBossPending = false
			continue
		end

		local bossHealth = RoundCore.GetBossHealthScale(open.Round, #Players:GetPlayers())
		local enemyEntity = BossIntroService.Arrive(boss.Id, bossHealth, open.DamageScale)
		if not enemyEntity then
			-- Nowhere to stage it (nobody standing): the old way in, on the spawn ring.
			local position = pickSpawnPosition()
			if not position then continue end
			local _, entity = EnemiesService.Spawn(boss.Id, position, bossHealth, open.DamageScale, 1)
			enemyEntity = entity
		end

		track(open, enemyEntity)
		if enemyEntity then bosses[enemyEntity] = true end
		open.IsBossPending = false
	end
end

-- Oldest round first, so a skipped wave finishes pouring in before the next one starts.
local function spawnBodies(dt: number)
	local toSpawn = 0
	for _, open in openRounds do
		toSpawn += open.ToSpawn
	end

	-- Nothing to pour: no banked burst for the next wave either.
	if toSpawn == 0 then
		spawnAccumulator = 0
		return
	end

	spawnAccumulator += TimeCore.GetDeltaTime(dt) * RoundCore.SPAWNS_PER_SECOND
	for _, open in openRounds do
		while spawnAccumulator >= 1 and open.ToSpawn > 0 and EnemiesService.HasRoom() do
			local enemyData = RoundCore.Draw(open.Pool, open.PoolWeight, random:NextNumber())
			local position = pickSpawnPosition()
			if not enemyData or not position then break end
			local _, enemyEntity =
				EnemiesService.Spawn(enemyData.Id, position, open.HealthScale, open.DamageScale, open.SpeedScale)
			track(open, enemyEntity)
			spawnAccumulator -= 1
			open.ToSpawn -= 1
		end
	end

	-- Held at the cap: no banked burst for the moment room opens.
	if not EnemiesService.HasRoom() then spawnAccumulator = math.min(spawnAccumulator, 1) end
end

local function payClear(round: number)
	local gold, gems, xpPercent = RoundCore.GetClearRewards(round)
	local key = RoundService.RecordKey

	for _, player in Players:GetPlayers() do
		local paidGold = math.floor(gold * (1 + upgradeStats.Get(player, EUpgradesIds.Greed)) + 0.5)
		EconomyService.AddGold(player, paidGold)
		local paidGems = EconomyService.AddGameplayGems(player, gems)
		local paidXp = xpPercent
		DatabaseService.Update(player, function(profile)
			paidXp = xpPercent * ShopCore.RunXpScale(profile)
			profile.Xp += paidXp
			while profile.Xp >= 100 do
				profile.Xp -= 100
				profile.Level += 1
			end

			local record: TProfile.TRecord = profile.Records[key] or { HighestReached = 0, HighestCompleted = 0 }
			record.HighestCompleted = math.max(record.HighestCompleted, round)
			record.HighestReached = math.max(record.HighestReached, round)
			profile.Records[key] = record
			return true
		end)

		DatabaseService.SaveAsync(player)
		ServerNetworkRounds.Rewards.Fire(player, round, paidGold, paidGems, paidXp)
	end
end

-- Pays every finished round at the front of the queue; a round behind an unfinished one waits for it. With none
-- left open, the next preparation.
local function clearFinished()
	while openRounds[1] do
		local open = openRounds[1]
		if open.ToSpawn > 0 or open.IsBossPending or open.Alive > 0 then return end
		table.remove(openRounds, 1)
		RoundService.LastCleared = open.Round
		payClear(open.Round)
		ServerNetworkRounds.Cleared.FireAll(open.Round)
		RoundService.OnRoundCleared:Fire(open.Round)
	end

	-- A clear's listeners may have ended the run.
	if RoundService.State == ERoundState.Fighting then RoundService.Prepare(RoundService.Round + 1) end
end

EnemiesService.OnEnemyDied:Connect(function(position: vector, enemyData: TData.TEnemy, killer: Player?)
	-- Not only while Fighting: a skipped wave keeps pouring in through the next countdown, and its kills pay too.
	if not killer or RoundService.State == ERoundState.Idle then return end
	local greed = 1 + upgradeStats.Get(killer, EUpgradesIds.Greed) + EquipmentService.StatOf(killer, "KillGold")
	local amount = math.floor(RoundCore.GetKillGold(enemyData, RoundService.Round) * greed + 0.5)
	EconomyService.AddGold(killer, amount)
	-- The coins are a picture of Gold already credited (GDD 17): they fly to the killer whatever happens to them.
	ServerNetworkEconomy.Coins.Fire(killer, position :: any, amount)
end)

-- The kills on boss round `round`'s way are made: its boss is on its way. Before OnRoundKilled is told, so its
-- listeners already see the boss coming (IsBossTime). A boss round with no boss (a map without one) is its way done.
local function bringBoss(round: number)
	for _, open in openRounds do
		if open.Round == round and open.IsBossPending then
			open.BossAt = TimeCore.GameClock + RoundCore.BOSS_ARRIVE_SECONDS
			return
		end
	end

	wayDoneRound = math.max(wayDoneRound, round)
end

-- The way to the next boss for the HUD, at most REMAINING_INTERVAL apart: the kills on it and how many it takes, the
-- waves not opened yet worked out for the party as it stands.
local function sendWay()
	if TimeCore.GameClock < nextWayAt then return end
	nextWayAt = TimeCore.GameClock + Tune.REMAINING_INTERVAL
	local bossRound = RoundCore.BossRoundOf(wayDoneRound + 1)
	local playerCount = #Players:GetPlayers()
	local needed = 0
	for round = bossRound - RoundCore.BOSS_EVERY + 1, bossRound do
		needed += roundSizes[round] or RoundCore.GetCount(round, playerCount)
	end

	local kills = math.min(wayKills[bossRound] or 0, needed)
	if bossRound == sentWayRound and kills == sentWayKills and needed == sentWayNeeded then return end
	sentWayRound, sentWayKills, sentWayNeeded = bossRound, kills, needed
	ServerNetworkRounds.BossWay.FireAll(bossRound, kills, needed)
end

-- A kill and a removal alike: a body that fell out of the map is no longer one to kill.
EnemiesService.OnEnemyRemoving:Connect(function(enemyEntity: jecs.Entity<any>)
	loneBosses[enemyEntity] = nil
	local open = roundOf[enemyEntity]
	if not open then return end
	roundOf[enemyEntity] = nil
	open.Alive -= 1
	-- A boss is what its way's kills bring on, not one of them. Its fall ends the way.
	if bosses[enemyEntity] then
		bosses[enemyEntity] = nil
		wayDoneRound = math.max(wayDoneRound, open.Round)
		return
	end

	-- Any round's body counts toward the oldest round not yet reached, and toward that round's boss's way. Told here,
	-- before the Heartbeat's clear, so a listener can still hold the countdown that clear opens (HoldNextPrepare).
	local oldest = uncountedRounds[1]
	if oldest then
		local bossRound = RoundCore.BossRoundOf(oldest.Round)
		wayKills[bossRound] = (wayKills[bossRound] or 0) + 1
	end
	uncountedKills += 1
	while oldest and uncountedKills >= oldest.Size do
		table.remove(uncountedRounds, 1)
		uncountedKills -= oldest.Size
		if RoundCore.IsBossRound(oldest.Round) then bringBoss(oldest.Round) end
		RoundService.OnRoundKilled:Fire(oldest.Round)
		oldest = uncountedRounds[1]
	end
end)

RoundService.OnPlayerDisconnected = function(player: Player)
	votes[player] = nil
	-- Leaving can be what makes the rest of the party "everyone".
	task.defer(checkVotes)
end :: TPlayerEvents.OnPlayerDisconnected

-- Needs no character: a downed player votes too. A wave can be skipped once it has run GetSkipAfterSeconds; never
-- during a countdown.
ClientNetworkRounds.VoteStart.On(function(player: Player)
	if votes[player] or not canSkip() then return end
	votes[player] = true
	checkVotes()
end)

ClientNetworkRounds.SetAutoSkip.On(function(player: Player, isOn: boolean)
	DatabaseService.Update(player, function(profile)
		if profile.Settings.IsAutoSkip == isOn then return false end
		profile.Settings.IsAutoSkip = isOn
		return true
	end)

	checkVotes()
end)

RunService.Heartbeat:Connect(function(dt: number)
	if TimeCore.IsPaused then return end
	local state = RoundService.State
	if state ~= ERoundState.Idle then sendWay() end

	if state == ERoundState.Preparing then
		-- A boss coming or up ends the countdown, which keeps the boss strip tucked away. The wave opened under it pours
		-- in once it falls.
		if TimeCore.GameClock >= prepareEndsAt or RoundService.IsBossTime() then
			fight()
			return
		end
		-- A skipped wave is still open through the next one's countdown: it goes on pouring in and can be cleared.
		if not openRounds[1] then return end
	elseif state == ERoundState.Fighting then
		-- The skip opening, or reopening when a boss falls, is a count of its own: everyone on auto-skip skips with
		-- nobody pressing anything.
		local isSkippable = canSkip()
		if isSkippable ~= wasSkippable then
			wasSkippable = isSkippable
			checkVotes()
		end
		-- A skip moved the run into the next countdown.
		if RoundService.State ~= ERoundState.Fighting then return end
	else
		return
	end

	-- Bodies stop pouring in once a boss is up, and pour again once it falls.
	if not RoundService.IsSpawningPaused and next(loneBosses) == nil then
		spawnBosses()
		if next(bosses) == nil then spawnBodies(dt) end
	end

	local remaining = countRemaining()
	if remaining ~= sentRemaining and TimeCore.GameClock >= nextRemainingAt then
		sentRemaining = remaining
		nextRemainingAt = TimeCore.GameClock + Tune.REMAINING_INTERVAL
		ServerNetworkRounds.Remaining.FireAll(remaining)
	end

	-- The last few are shown to everyone wherever they are, so the HUD's outline can lead the party to them.
	if remaining > 0 and remaining <= RoundCore.LAST_SHOWN then EnemiesService.ShowToEveryone() end
	clearFinished()
end)

return Ignis.Register(RoundService)
