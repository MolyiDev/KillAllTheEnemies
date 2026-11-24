-- The run, start to finish: wait for the party, run rounds until everybody is down, hold it under the results (a
-- revive picks it back up, PLAY AGAIN starts it over), send them back to the lobby.
-- The first round waits for every player the pad sent (JoinData) to be loaded and known to every client, or until
-- WAIT_FOR_PARTY_SECONDS. A join with no token (Studio, a follow) is a party of one on the easy map. The first
-- arrival's token picks the map (arenaMap), so every map is played in this one place.
local AdService = game:GetService("AdService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TeleportService = game:GetService("TeleportService")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local Network = require(ServerScriptService.GlobalServer.Network)
local DatabaseService = require(ServerScriptService.GlobalServer.Services.DatabaseService)
local PurchasesService = require(ServerScriptService.GlobalServer.Services.PurchasesService)
local JoinData = require(ServerScriptService.GlobalServer.Utils.JoinData)
local AbilityService = require(script.Parent.AbilityService)
local CharacterService = require(script.Parent.CharacterService)
local DefenseService = require(script.Parent.DefenseService)
local EconomyService = require(script.Parent.EconomyService)
local EnemiesService = require(script.Parent.EnemiesService)
local EnemyAttacksService = require(script.Parent.EnemyAttacksService)
local EnemyMovementService = require(script.Parent.EnemyMovementService)
local MutationService = require(script.Parent.MutationService)
local RoundService = require(script.Parent.RoundService)
local TimeService = require(script.Parent.TimeService)
local UpgradesService = require(script.Parent.UpgradesService)
local WeaponService = require(script.Parent.WeaponService)
local arenaMap = require(ServerScriptService.Server.Utils.arenaMap)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local MapsCore = require(ReplicatedStorage.GlobalShared.Core.MapsCore)
local ShopCore = require(ReplicatedStorage.GlobalShared.Core.ShopCore)
local ArenaCore = require(ReplicatedStorage.Shared.Core.ArenaCore)
local RoundCore = require(ReplicatedStorage.Shared.Core.RoundCore)
local TimeCore = require(ReplicatedStorage.Shared.Core.TimeCore)
local doubleGems = require(ReplicatedStorage.Shared.Utils.doubleGems)
local Components = require(ReplicatedStorage.GlobalShared.ECS.Components)
local Tags = require(ReplicatedStorage.GlobalShared.ECS.Tags)
local World = require(ReplicatedStorage.GlobalShared.ECS.Worlds.World)
local getCharacterEntityFromPlayer =
	require(ReplicatedStorage.GlobalShared.Utils.Functions.getCharacterEntityFromPlayer)
local getCharacterIdFromPlayer = require(ReplicatedStorage.GlobalShared.Utils.Functions.getCharacterIdFromPlayer)
local EPlaceIds = require(ReplicatedStorage.Types.Enums.EPlaceIds)
local EProducts = require(ReplicatedStorage.Types.Enums.EProducts)
local TData = require(ReplicatedStorage.Types.TData)
local TJoinData = require(ReplicatedStorage.Types.TJoinData)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)
local TProfile = require(ReplicatedStorage.Types.TProfile)

local ServerNetworkGame = Network.Server.Game
local ServerNetworkEnemies = Network.Server.Enemies
local ServerNetworkRounds = Network.Server.Rounds
local ClientNetworkGame = Network.Client.Game

local Tune = table.freeze({
	WAIT_FOR_PARTY_SECONDS = 15,
	-- Once the whole party is in, a beat before the first round so nobody spawns into a fight.
	ALL_JOINED_SECONDS = 3,
	-- The results' countdown.
	RETURN_TO_LOBBY_SECONDS = 20,
	-- The countdown waits while a purchase prompt opened from the results is up, this long in all: a client only
	-- says its prompt is open, so one that never says it closed cannot keep the squad here.
	BUYING_HOLD_SECONDS = 60,
	-- Once the prompt closes there is at least this much countdown left, for the receipt to arrive.
	AFTER_BUYING_SECONDS = 3,
	-- A revived body that never becomes ready stops holding off the wipe check after this long.
	REVIVE_SETTLE_SECONDS = 10,
	RETURN_RETRIES = 3,
	RETURN_RETRY_SECONDS = 2,
	-- Each player's line on the squad screen goes out at most this often, and only when it has changed.
	SCORE_INTERVAL = 0.25,
})

type TScore = {
	Kills: number,
	Deaths: number,
	-- The line as every client last heard it; -1 kills is "send it again".
	SentClassId: number,
	SentKills: number,
	SentDeaths: number,
	SentGold: number,
}

local SCORE_STUB: TScore = table.freeze({
	Kills = 0,
	Deaths = 0,
	SentClassId = 0,
	SentKills = -1,
	SentDeaths = 0,
	SentGold = 0,
})

-- A player's run, for the record the lobby shows (TProfile.LastMatch): where they stood as it began (level, Xp, best
-- time on its map), the Xp it has earned them by source, and whether it has counted its trophy yet.
type TRun = {
	LevelBefore: number,
	XpBefore: number,
	BestSecondsBefore: number,
	XpWaves: number,
	XpBosses: number,
	HasTrophy: boolean,
}

local RUN_STUB: TRun = table.freeze({
	LevelBefore = 1,
	XpBefore = 0,
	BestSecondsBefore = 0,
	XpWaves = 0,
	XpBosses = 0,
	HasTrophy = false,
})

local EMatchState = table.freeze({
	Waiting = 0,
	Running = 1,
	-- Everybody is down: the run is held as it stands and the results are up.
	Ended = 2,
	-- The results' countdown ran out and the party is being sent back.
	Returning = 3,
})

local MatchService = {}

MatchService.EMatchState = EMatchState
MatchService.State = EMatchState.Waiting
MatchService.SupposedPlayers = 0
MatchService.MapName = MapsCore.DEFAULT
-- The difficulty the party's host picked (MapsCore.DIFFICULTIES).
MatchService.Difficulty = MapsCore.DIFFICULTIES[1]

local isArenaPlaced = false
local isArenaBaked = false
local isWaitOver = false
local waitThread: thread? = nil
local loadedPlayers: { [Player]: boolean } = {}
local fetchedPlayers: { [Player]: boolean } = {}
local dataPlayers: { [Player]: boolean } = {}
local readyPlayers: { [Player]: boolean } = {}
local takenTokens: { [string]: TJoinData.TMessage } = {}
local teleportTries: { [Player]: number } = {}
local scores: { [Player]: TScore } = {}
-- TimeCore.GameClock the squad screen's lines next go out at.
local nextScoresAt = 0
-- This run: each player's best wave on its map before it began, and the Gems a bought doubling has added on top of
-- what their play earned.
local bestAtStart: { [Player]: number } = {}
local bonusGems: { [Player]: number } = {}
local runs: { [Player]: TRun } = {}
-- The results: seconds left on the countdown and of its waiting for prompts, who has a prompt up, who voted to play
-- again, and whether the countdown was waiting last frame.
local returnLeft = 0
local holdLeft = 0
local buying: { [Player]: boolean } = {}
local playAgainVotes: { [Player]: boolean } = {}
local wasHeld = false
-- Players bought back up whose new body is not ready yet: nobody stands, and it is not a wipe.
local reviving: { [Player]: boolean } = {}

local function getAllEnemyIds(): { number }
	local ids = table.create(#DataCore.Enemies.All)
	for i, enemyData in DataCore.Enemies.All do
		ids[i] = enemyData.Id
	end

	return ids
end

-- Every line goes out again on the next send: a client whose listeners just came up has heard none of them.
local function resendScores()
	for _, score in scores do
		score.SentKills = -1
	end
end

-- The squad screen's lines that changed since they were last sent, to everybody.
local function sendScores()
	for player, score in scores do
		local classId = AbilityService.GetClass(player).Id
		local gold = EconomyService.GetGold(player)
		if
			score.SentKills == score.Kills
			and score.SentDeaths == score.Deaths
			and score.SentGold == gold
			and score.SentClassId == classId
		then
			continue
		end

		score.SentClassId = classId
		score.SentKills = score.Kills
		score.SentDeaths = score.Deaths
		score.SentGold = gold
		ServerNetworkGame.Score.FireAll(player, classId, score.Kills, score.Deaths, gold)
	end
end

-- Where the player stands as this run begins: their best wave on its map, which the results' NEW BEST is measured
-- against, and the rest of what the lobby's record compares the run with.
local function beginRun(player: Player)
	local profile = DatabaseService.Get(player)
	local record = if profile then profile.Records[RoundService.RecordKey] else nil
	bestAtStart[player] = if record then record.HighestReached else 0

	local run = table.clone(RUN_STUB)
	if profile then
		run.LevelBefore = profile.Level
		run.XpBefore = profile.Xp
	end
	run.BestSecondsBefore = if record then record.BestSeconds or 0 else 0
	runs[player] = run
end

local function startMatch()
	MatchService.State = EMatchState.Running
	if waitThread and coroutine.running() ~= waitThread then task.cancel(waitThread) end
	waitThread = nil

	local players = Players:GetPlayers()
	RoundService.RecordKey = MapsCore.RecordKey(MatchService.MapName, #players)
	RoundService.MapName = MatchService.MapName
	table.clear(bonusGems)
	table.clear(bestAtStart)
	table.clear(runs)
	for _, player in players do
		beginRun(player)
	end

	TimeService.Reset()
	EconomyService.ResetRun()
	WeaponService.ResetRun()
	AbilityService.ResetRun()
	CharacterService.ResetRun()
	UpgradesService.ResetRun()
	-- After the run upgrades are cleared: a potion adds to their sums.
	MutationService.DrinkAll(players)
	-- The game clock starts over with the run, and so does everybody's line.
	nextScoresAt = 0
	for _, score in scores do
		score.Kills = 0
		score.Deaths = 0
		score.SentKills = -1
	end

	ServerNetworkEnemies.TypesForMatch.FireAll(getAllEnemyIds())
	ServerNetworkGame.MatchStarted.FireAll(MapsCore.INDEX[MatchService.MapName] or 0)
	EnemyMovementService.IsRunning = true
	RoundService.Begin()
end

local function tryStart()
	if MatchService.State ~= EMatchState.Waiting or not isArenaBaked then return end
	local present = 0
	for _, player in Players:GetPlayers() do
		-- Everyone here must have loaded, had his token read and profile opened, and have a character every client
		-- knows.
		if not loadedPlayers[player] or not fetchedPlayers[player] or not dataPlayers[player] then return end
		if not readyPlayers[player] then return end
		present += 1
	end

	if present == 0 then return end

	-- Before the timeout, the whole party; after it, whoever made it.
	if not isWaitOver and present < math.max(MatchService.SupposedPlayers, 1) then return end
	if isWaitOver then
		startMatch()
		return
	end

	if waitThread then task.cancel(waitThread) end
	waitThread = task.delay(Tune.ALL_JOINED_SECONDS, startMatch)
end

local function resetRun()
	table.clear(buying)
	table.clear(playAgainVotes)
	table.clear(reviving)
	RoundService.Stop()
	EnemyMovementService.IsRunning = false
	EnemyAttacksService.Reset()
	EnemiesService.ClearAll()
	DefenseService.ClearAll()
end

-- Studio's loop, and the fallback when there is no lobby: clear the arena, bring everyone back, play again.
function MatchService.Restart()
	resetRun()
	MatchService.State = EMatchState.Waiting

	-- Only a character still standing with an id counts as ready; the revived register again through
	-- OnCharacterReady, which calls tryStart.
	for player in readyPlayers do
		if not getCharacterIdFromPlayer(player) or not CharacterService.IsAlive(player) then
			readyPlayers[player] = nil
		end
	end

	-- The results held the clock: the revived are spawned under a running one.
	TimeService.SetTimeScale(1)
	CharacterService.ReviveDead()
	isWaitOver = true
	tryStart()
end

-- A bought Gold pack: `amount` run Gold to `player`, and the show of it arriving to everybody. Both go out in one
-- flush, so the buyer's counter never sees the Gold without the coins that carry it in.
function MatchService.GrantGold(player: Player, amount: number)
	EconomyService.AddGold(player, amount)
	ServerNetworkGame.GoldBought.FireAll(player, amount)
end

-- One player at a time, so one who cannot be teleported does not hold back the rest.
local function teleportToLobby(player: Player)
	if not player.Parent then return end
	local ok, err = pcall(TeleportService.TeleportAsync, TeleportService, EPlaceIds.Lobby, { player })
	if not ok then warn(`[MatchService] return of {player.Name} to the lobby failed: {err}`) end
end

local function returnToLobby()
	local players = Players:GetPlayers()
	if #players == 0 then return end

	-- Studio cannot teleport, and a place with no lobby yet has nowhere to go: run it again instead.
	if RunService:IsStudio() or EPlaceIds.Lobby == 0 then
		MatchService.Restart()
		return
	end

	for _, player in players do
		task.spawn(teleportToLobby, player)
	end
end

local function sendReturnTimer()
	ServerNetworkGame.ReturnTimer.FireAll(math.max(returnLeft, 0), wasHeld)
end

-- The last wave reached: one still in its countdown was not (RoundService records one as it opens).
local function getWaveReached(): number
	local isPreparing = RoundService.State == RoundService.ERoundState.Preparing
	return if isPreparing then RoundService.Round - 1 else RoundService.Round
end

-- Writes `player`'s run as it stands into their profile for the lobby to show (TProfile.LastMatch), with the longest
-- run on the map, and a trophy the first time this run beats their best wave. As the run ends, and as they leave it.
local function saveRun(player: Player, wave: number, seconds: number)
	local run = runs[player]
	local score = scores[player]
	if not run or not score then return end

	local squad: { TProfile.TMatchMember } = {}
	local squadKills = 0
	for member, memberScore in scores do
		squadKills += memberScore.Kills
		squad[#squad + 1] = {
			UserId = member.UserId,
			Name = member.Name,
			ClassId = AbilityService.GetClass(member).Id,
			Kills = memberScore.Kills,
		}
	end

	local isTrophy = not run.HasTrophy and wave > (bestAtStart[player] or 0)
	if isTrophy then run.HasTrophy = true end
	local gems = EconomyService.GetRunGems(player) + (bonusGems[player] or 0)
	local key = RoundService.RecordKey
	DatabaseService.Update(player, function(profile)
		profile.LastMatch = {
			MapName = MatchService.MapName,
			Wave = wave,
			BestWaveBefore = bestAtStart[player] or 0,
			Seconds = seconds,
			BestSecondsBefore = run.BestSecondsBefore,
			Gems = gems,
			Kills = score.Kills,
			SquadKills = squadKills,
			LevelBefore = run.LevelBefore,
			XpBefore = run.XpBefore,
			XpWaves = run.XpWaves,
			XpBosses = run.XpBosses,
			Squad = squad,
		}

		local record: TProfile.TRecord = profile.Records[key] or { HighestReached = 0, HighestCompleted = 0 }
		record.BestSeconds = math.max(record.BestSeconds or 0, seconds)
		profile.Records[key] = record

		if isTrophy then
			local stats = profile.Stats or { Deaths = 0, Trophies = 0 }
			stats.Trophies += 1
			profile.Stats = stats
		end

		return true
	end)
end

-- Everybody is down. The run is held, not cleared: the clock stops with every body where it stands, so a revive
-- bought on the results goes on from here.
local function endMatch()
	if MatchService.State ~= EMatchState.Running then return end
	MatchService.State = EMatchState.Ended
	-- The last kills and the last death are on the squad screen behind the results.
	sendScores()
	TimeService.SetTimeScale(0)
	returnLeft = Tune.RETURN_TO_LOBBY_SECONDS
	holdLeft = Tune.BUYING_HOLD_SECONDS
	wasHeld = false

	local squadKills = 0
	for _, score in scores do
		squadKills += score.Kills
	end

	local wave = getWaveReached()
	local seconds = math.floor(TimeCore.GameClock)
	local players = Players:GetPlayers()
	for _, player in players do
		saveRun(player, wave, seconds)
		local bonus = bonusGems[player] or 0
		local earned = EconomyService.GetRunGems(player)
		local tier = doubleGems.GetTier(earned - bonus)
		ServerNetworkGame.MatchEnded.Fire(player, {
			Wave = wave,
			IsNewBest = wave > (bestAtStart[player] or 0),
			SquadKills = squadKills,
			SecondsSurvived = seconds,
			Gems = earned + bonus,
			DoubleProductId = if tier then tier.ProductId else 0,
			ReviveProductId = EProducts.Revive,
			ReturnSeconds = returnLeft,
		})
	end

	ServerNetworkGame.PlayAgainVotes.FireAll(0, #players)
end

local function checkWiped()
	if MatchService.State ~= EMatchState.Running or next(reviving) ~= nil then return end
	if CharacterService.CountAlive() > 0 then return end
	endMatch()
end

-- Starts the run over once everybody here has voted and nobody is in the middle of buying something from this one;
-- otherwise tells everyone the count.
local function checkPlayAgain()
	if MatchService.State ~= EMatchState.Ended then return end
	local count, needed = 0, 0
	for _, player in Players:GetPlayers() do
		needed += 1
		if playAgainVotes[player] then
			count += 1
		end
	end

	if needed > 0 and count >= needed and next(buying) == nil then
		MatchService.Restart()
		return
	end

	ServerNetworkGame.PlayAgainVotes.FireAll(count, needed)
end

-- A revive bought on the results: the held run goes on, with `player` on the way back up.
local function resumeMatch(player: Player)
	MatchService.State = EMatchState.Running
	table.clear(buying)
	table.clear(playAgainVotes)
	reviving[player] = true
	TimeService.SetTimeScale(1)
	ServerNetworkGame.MatchResumed.FireAll(player)
	task.delay(Tune.REVIVE_SETTLE_SECONDS, function()
		if not reviving[player] then return end
		reviving[player] = nil
		checkWiped()
	end)
end

-- The results' countdown ran out.
local function leaveResults()
	MatchService.State = EMatchState.Returning
	resetRun()
	returnToLobby()
end

-- Yields while it bakes.
local function placeArena()
	if isArenaPlaced then return end
	isArenaPlaced = true
	arenaMap.Place(MatchService.MapName)
	ArenaCore.Bake()
	isArenaBaked = true
	tryStart()
end

MatchService.OnStart = function()
	waitThread = task.delay(Tune.WAIT_FOR_PARTY_SECONDS, function()
		waitThread = nil
		isWaitOver = true
		-- A token nobody could read (expired, or the store failed) plays the default map.
		task.spawn(placeArena)
		tryStart()
	end)
end

MatchService.OnPlayerConnected = function(player: Player)
	scores[player] = table.clone(SCORE_STUB)
	local token = JoinData.GetToken(player)
	if token then
		-- A party shares one token; the first of them to arrive reads it for all. A second arrival reading it at the
		-- same time finds it deleted, so only a read message places the map, never a missing one.
		local message = takenTokens[token] or JoinData.TakeAsync(token)
		if message then
			takenTokens[token] = message
			MatchService.SupposedPlayers = math.max(MatchService.SupposedPlayers, message.SupposedPlayers)
			if MapsCore.MAPS[message.MapName] and not isArenaPlaced then MatchService.MapName = message.MapName end
			local difficulty = message.Difficulty
			if difficulty and table.find(MapsCore.DIFFICULTIES, difficulty) then
				MatchService.Difficulty = difficulty
			end
			task.spawn(placeArena)
		end
	else
		task.spawn(placeArena)
	end

	if not player.Parent then return end
	fetchedPlayers[player] = true
	tryStart()
end :: TPlayerEvents.OnPlayerConnected

-- Their profile is open. A late joiner into a running match is caught up on the round.
MatchService.OnDataLoaded = function(player: Player)
	dataPlayers[player] = true
	if MatchService.State == EMatchState.Running then
		beginRun(player)
		ServerNetworkEnemies.TypesForMatch.Fire(player, getAllEnemyIds())
		ServerNetworkGame.MatchStarted.Fire(player, MapsCore.INDEX[MatchService.MapName] or 0)
		ServerNetworkRounds.Started.Fire(player, RoundService.Round, 0)
	end

	tryStart()
end :: TPlayerEvents.OnDataLoaded

MatchService.OnPlayerDisconnected = function(player: Player)
	-- Walking out of a run ends it for them: the lobby shows it as it stood. A run already over was saved as it ended.
	if MatchService.State == EMatchState.Running then
		saveRun(player, getWaveReached(), math.floor(TimeCore.GameClock))
	end

	loadedPlayers[player] = nil
	fetchedPlayers[player] = nil
	dataPlayers[player] = nil
	readyPlayers[player] = nil
	teleportTries[player] = nil
	scores[player] = nil
	bestAtStart[player] = nil
	bonusGems[player] = nil
	runs[player] = nil
	buying[player] = nil
	playAgainVotes[player] = nil
	reviving[player] = nil
	-- Leaving can be what makes the rest of the party "everyone", or what leaves nobody standing.
	task.defer(tryStart)
	task.defer(checkWiped)
	task.defer(checkPlayAgain)
end :: TPlayerEvents.OnPlayerDisconnected

CharacterService.OnCharacterReady:Connect(function(_, player: Player)
	readyPlayers[player] = true
	reviving[player] = nil
	tryStart()
end)

CharacterService.OnCharacterDied:Connect(function(_, player: Player?)
	local score = if player then scores[player] else nil
	if player and score and MatchService.State == EMatchState.Running then
		score.Deaths += 1
		DatabaseService.Update(player, function(profile)
			local stats = profile.Stats or { Deaths = 0, Trophies = 0 }
			stats.Deaths += 1
			profile.Stats = stats
			return true
		end)
	end
	checkWiped()
end)

EnemiesService.OnEnemyKilled:Connect(function(killerPlayer: Player?, count: number)
	local score = if killerPlayer then scores[killerPlayer] else nil
	if score then
		score.Kills += count
	end
end)

-- A boss put down counts for everybody in the run, the downed too: the map after this one opens on these (MapsCore).
EnemiesService.OnEnemyDied:Connect(function(_, enemyData: TData.TEnemy)
	if not enemyData.IsBoss or MatchService.State ~= EMatchState.Running then return end
	local mapName = MatchService.MapName
	for player in runs do
		DatabaseService.Update(player, function(profile)
			local kills = profile.BossKills or {}
			kills[mapName] = (kills[mapName] or 0) + 1
			profile.BossKills = kills
			return true
		end)
		DatabaseService.SaveAsync(player)
	end
end)

-- After a clear, every player who is down is offered a revive for the next round, and every player here has earned
-- its Xp (RoundService pays all of them), a boss wave's as BOSSES on the lobby's record.
RoundService.OnRoundCleared:Connect(function(round: number)
	local _, _, xpPercent = RoundCore.GetClearRewards(round)
	local isBoss = RoundCore.IsBossRound(round)
	for _, player in Players:GetPlayers() do
		local run = runs[player]
		local profile = DatabaseService.Get(player)
		local paidXp = if profile then xpPercent * ShopCore.RunXpScale(profile) else xpPercent
		if run and isBoss then
			run.XpBosses += paidXp
		elseif run then
			run.XpWaves += paidXp
		end

		if EProducts.Revive ~= 0 and not CharacterService.IsAlive(player) then
			ServerNetworkRounds.ReviveOffer.Fire(player, EProducts.Revive)
		end
	end
end)

-- Charged only when it can be fulfilled: the buyer is down, in a running match or under the results, where it
-- picks the held run back up.
PurchasesService.Register(EProducts.Revive, function(player: Player)
	local state = MatchService.State
	if state ~= EMatchState.Running and state ~= EMatchState.Ended then return false, nil end
	if CharacterService.IsAlive(player) then return false, nil end
	return true,
		function()
			if MatchService.State == EMatchState.Ended then resumeMatch(player) end
			CharacterService.Spawn(player)
		end
end)

-- DOUBLE YOUR GEMS: as many Gems again as the buyer's play has earned this run and not doubled yet. Charged only
-- under the results, and only for the product that amount is priced at.
local function registerDoubleGems(productId: number)
	PurchasesService.Register(productId, function(player: Player, profile)
		local state = MatchService.State
		if state ~= EMatchState.Ended and state ~= EMatchState.Returning then return false, nil end
		local bonus = bonusGems[player] or 0
		local gems = EconomyService.GetRunGems(player) - bonus
		local tier = doubleGems.GetTier(gems)
		if not tier or tier.ProductId ~= productId then return false, nil end
		profile.Gems += gems
		-- The run's record was written as it ended, before this doubling.
		if profile.LastMatch then
			profile.LastMatch.Gems += gems
		end
		bonusGems[player] = bonus + gems
		return true, function()
			ServerNetworkGame.GemsDoubled.Fire(player, gems)
		end
	end)
end

registerDoubleGems(EProducts.DoubleGemsSmall)
registerDoubleGems(EProducts.DoubleGemsMedium)
registerDoubleGems(EProducts.DoubleGemsLarge)

-- Charged only with something to kill. The buyer is the killer, so the kills pay their Gold. The blast starts at the
-- buyer, or at a squad mate when the buyer is down.
PurchasesService.Register(EProducts.NukeAll, function(player: Player)
	if MatchService.State ~= EMatchState.Running or EnemiesService.GetCount() == 0 then return false, nil end
	return true,
		function()
			local buyerEntity = getCharacterEntityFromPlayer(player)
			local root = if buyerEntity then World:get(buyerEntity, Components.HumanoidRootPart) else nil
			if not root then
				for _, standing in World:query(Components.HumanoidRootPart):with(Tags.Character, Tags.Alive) do
					root = standing
					break
				end
			end

			local origin = if root then root.Position else Vector3.zero
			ServerNetworkGame.NukedAll.FireAll(player, origin, EnemiesService.GetCount())
			EnemiesService.KillAll(buyerEntity, origin)
		end
end)

PurchasesService.Register(EProducts.HealAll, function(player: Player)
	if MatchService.State ~= EMatchState.Running then return false, nil end
	return true, function()
		ServerNetworkGame.HealedAll.FireAll(player)
		CharacterService.HealAll()
	end
end)

-- Run Gold, so only during a run: before it starts, ResetRun would wipe it.
local function registerGoldPack(productId: number, amount: number)
	PurchasesService.Register(productId, function(player: Player)
		if MatchService.State ~= EMatchState.Running then return false, nil end
		return true, function()
			MatchService.GrantGold(player, amount)
		end
	end)
end

registerGoldPack(EProducts.GoldPackSmall, 1000)
registerGoldPack(EProducts.GoldPackLarge, 99999)

-- The client's listeners are up. Nothing to validate: it only gates the start for this player.
ClientNetworkGame.GameLoaded.On(function(player: Player)
	loadedPlayers[player] = true
	resendScores()
	tryStart()
end)

RunService.Heartbeat:Connect(function()
	if MatchService.State ~= EMatchState.Running or TimeCore.GameClock < nextScoresAt then return end
	nextScoresAt = TimeCore.GameClock + Tune.SCORE_INTERVAL
	sendScores()
end)

-- WATCH AD: a rewarded video whose reward is the doubling the buyer's Gems are priced at. The ad pays through the
-- same receipt a purchase does (registerDoubleGems), so nothing is granted here. The countdown waits for the ad as
-- it does for a prompt. Only under the results, with Gems to double, and one ad at a time.
ClientNetworkGame.WatchAd.On(function(player: Player)
	if MatchService.State ~= EMatchState.Ended or buying[player] then return end
	local tier = doubleGems.GetTier(EconomyService.GetRunGems(player) - (bonusGems[player] or 0))
	if not tier then return end

	buying[player] = true
	local ok, result = pcall(function()
		return AdService:ShowRewardedVideoAdAsync(player, AdService:CreateAdRewardFromDevProductId(tier.ProductId))
	end)
	if not ok then warn(`[MatchService] the ad for {player.Name} failed: {result}`) end
	-- The results may have gone while it played (a revive, the run started over).
	if MatchService.State ~= EMatchState.Ended or not buying[player] then return end
	buying[player] = nil
	returnLeft = math.max(returnLeft, Tune.AFTER_BUYING_SECONDS)
	wasHeld = holdLeft > 0 and next(buying) ~= nil
	sendReturnTimer()
	checkPlayAgain()
end)

-- Needs no character: everybody is down. Counted once, and only under the results.
ClientNetworkGame.VotePlayAgain.On(function(player: Player)
	if MatchService.State ~= EMatchState.Ended or playAgainVotes[player] then return end
	playAgainVotes[player] = true
	checkPlayAgain()
end)

-- Only under the results, where there is no run left to walk out of. Studio cannot teleport, and a place with no
-- lobby yet has nowhere to go.
ClientNetworkGame.LeaveToLobby.On(function(player: Player)
	if MatchService.State ~= EMatchState.Ended then return end
	if RunService:IsStudio() or EPlaceIds.Lobby == 0 then return end
	task.spawn(teleportToLobby, player)
end)

-- A claim nothing can check, so it buys only a wait: the countdown holds for at most BUYING_HOLD_SECONDS in all.
ClientNetworkGame.SetBuying.On(function(player: Player, isBuying: boolean)
	if MatchService.State ~= EMatchState.Ended then return end
	if (buying[player] == true) == isBuying then return end
	buying[player] = if isBuying then true else nil
	if isBuying then return end
	returnLeft = math.max(returnLeft, Tune.AFTER_BUYING_SECONDS)
	wasHeld = holdLeft > 0 and next(buying) ~= nil
	sendReturnTimer()
	checkPlayAgain()
end)

-- The results' countdown, in real seconds: the match's own clock is stopped under them.
RunService.Heartbeat:Connect(function(dt: number)
	if MatchService.State ~= EMatchState.Ended then return end
	local isHeld = holdLeft > 0 and next(buying) ~= nil
	if isHeld then
		holdLeft -= dt
	else
		returnLeft -= dt
	end

	if isHeld ~= wasHeld then
		wasHeld = isHeld
		sendReturnTimer()
	end

	if returnLeft <= 0 then leaveResults() end
end)

-- A teleport can fail after the call returns (the lobby busy, a flaky hop). A run that is over has nothing to keep
-- the player for, so it tries again, a few times, a moment later.
TeleportService.TeleportInitFailed:Connect(function(player: Player, result: Enum.TeleportResult, message: string)
	warn(`[MatchService] teleport of {player.Name} failed: {result.Name} {message}`)
	if MatchService.State ~= EMatchState.Ended and MatchService.State ~= EMatchState.Returning then return end
	local tries = (teleportTries[player] or 0) + 1
	teleportTries[player] = tries
	if tries > Tune.RETURN_RETRIES then return end
	task.delay(Tune.RETURN_RETRY_SECONDS, teleportToLobby, player)
end)

return Ignis.Register(MatchService)
