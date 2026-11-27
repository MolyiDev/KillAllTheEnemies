-- The run upgrades: every wave's worth of kills (RoundService.OnRoundKilled) owes each player a hand of three cards (UpgradesCore.Deal), one of which they
-- keep for the run. Hands owed are queued and dealt one at a time; the next wave's countdown is held while anybody is
-- still picking, and a hand nobody picks from in time is picked for them, since the others are waiting on it. What
-- the picks add up to is in Utils/upgradeStats, read by the services whose numbers they change.
--
-- Nothing is dealt while a boss is coming or up (RoundService.IsBossTime): a hand up as it comes is put away as it
-- stands (its cards, its redeals, its seconds left) and offered again as it was once the boss's fall has been seen.
--
-- A player down as the wave's kills are done is revived then (MatchService) and dealt once their body is built
-- (CharacterService.OnStood), so the hand does not cover the rebuild; the countdown waits for them as for a hand up.
--
-- A player is picking from the deal until the card they took has left their screen (UpgradesCore.SHOW_SECONDS).
-- Meanwhile they are out of the fight (Tags.Picking): no blow lands on them, the crowd ignores them and no body enters
-- round them. Everybody is told so, and while every player is picking the match eases to a stop (TimeService). Alone
-- that is every pick; in a party the others play on round the picker.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local Network = require(ServerScriptService.GlobalServer.Network)
local CharacterService = require(script.Parent.CharacterService)
local EconomyService = require(script.Parent.EconomyService)
local EnemiesService = require(script.Parent.EnemiesService)
local EquipmentDropsService = require(script.Parent.EquipmentDropsService)
local NavService = require(script.Parent.NavService)
local RoundService = require(script.Parent.RoundService)
local TimeService = require(script.Parent.TimeService)
local upgradeStats = require(script.Parent.Parent.Utils.upgradeStats)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local UpgradesCore = require(ReplicatedStorage.Shared.Core.UpgradesCore)
local Components = require(ReplicatedStorage.GlobalShared.ECS.Components)
local Tags = require(ReplicatedStorage.GlobalShared.ECS.Tags)
local World = require(ReplicatedStorage.GlobalShared.ECS.Worlds.World)
local getCharacterEntityFromPlayer =
	require(ReplicatedStorage.GlobalShared.Utils.Functions.getCharacterEntityFromPlayer)
local EUpgradesIds = require(ReplicatedStorage.Types.Enums.Data.EUpgradesIds)
local TData = require(ReplicatedStorage.Types.TData)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)

local ServerNetworkUpgrades = Network.Server.Upgrades
local ClientNetworkUpgrades = Network.Client.Upgrades

local UPGRADES = DataCore.Upgrades.ById
local ALL_UPGRADES = DataCore.Upgrades.All

type THand = {
	Cards: { UpgradesCore.TCard },
	Round: number,
	Rerolls: number,
	-- os.clock the server picks at. Real time: nothing about a pick runs on the game clock, which a pause holds.
	PickAt: number,
}

type TRun = {
	Levels: { [number]: number },
	-- The waves whose hands are still owed, oldest first (0 for one given from the console).
	Owed: { number },
	Hand: THand?,
	-- The hand put away for a boss, and the seconds it had left; offered again before anything owed.
	Stashed: THand?,
	StashedSeconds: number,
	-- os.clock until which the card just taken is still on the player's screen.
	ShownUntil: number,
	IsPicking: boolean,
}

local Tune = table.freeze({
	-- Real seconds after a boss falls before the hands it held back come, so its whole fall and DEFEATED are seen first
	-- (the T-Rex's Death clip runs 4 s and its soul leaves the pile by 5.1 s of game time, which the fall's slow
	-- motion puts about 0.7 s later in real time, TimeService.SlowMotion; a hand up holds the game clock, which stops
	-- the fall where it is); and after the last piece it dropped has left a player's screen, which a card dealt over
	-- it would hide.
	AFTER_BOSS_SECONDS = 6.2,
	AFTER_DROP_SECONDS = 0.4,
	-- Real seconds after NUKE ALL is set off before a hand comes, so the blast, the bodies coming apart and its banner
	-- are seen whole first (the banner is up HudController/Announce.SECONDS from the blast's start).
	AFTER_NUKE_SECONDS = 3.6,
})

local UpgradesService = {}

local runs: { [Player]: TRun } = {}
local random = Random.new()
-- Whether a boss was coming or up last frame, and the os.clock the hands a fallen boss or a nuke held back are dealt
-- at (0 for none).
local wasBossTime = false
local resumeAt = 0

-- Puts `hand` up on `player`'s screen, to be picked for them `seconds` from now.
local function offer(player: Player, hand: THand, seconds: number, isReroll: boolean)
	hand.PickAt = os.clock() + seconds
	ServerNetworkUpgrades.Offer.Fire(player, {
		Cards = hand.Cards,
		Round = hand.Round,
		RerollPrice = UpgradesCore.RerollPrice(hand.Rerolls),
		Seconds = seconds,
		IsReroll = isReroll,
	})
end

-- Deals the hand put away for a boss, else the oldest hand `player` is owed, unless one is already up. A player with
-- every upgrade at its last level is owed nothing more.
local function dealNext(player: Player)
	local run = runs[player]
	if not run or run.Hand or not CharacterService.IsStanding(player) then return end
	if RoundService.State == RoundService.ERoundState.Idle or RoundService.IsBossTime() or resumeAt > 0 then return end
	-- A round finished by a kill on the boss's own frame comes before the Heartbeat sets resumeAt.
	if wasBossTime then return end
	local stashed = run.Stashed
	if stashed then
		run.Stashed = nil
		run.Hand = stashed
		offer(player, stashed, run.StashedSeconds, false)
		return
	end

	if not run.Owed[1] then return end
	local cards = UpgradesCore.Deal(ALL_UPGRADES, run.Levels, nil, random)
	if #cards == 0 then
		table.clear(run.Owed)
		return
	end

	local hand: THand = { Cards = cards, Round = table.remove(run.Owed, 1) :: number, Rerolls = 0, PickAt = 0 }
	run.Hand = hand
	offer(player, hand, UpgradesCore.AUTO_PICK_SECONDS, false)
end

-- The countdown to the next wave runs again once nobody has a hand up, or is about to be dealt one.
local function releaseRoundIfDone()
	if resumeAt > 0 then return end
	for _, run in runs do
		if run.Hand then return end
	end

	RoundService.ReleasePrepare()
end

-- Owes `player` one more hand, for the clear of `round` (0 for none), and deals it if none is up.
function UpgradesService.Grant(player: Player, round: number)
	local run = runs[player]
	if not run then return end
	run.Owed[#run.Owed + 1] = round
	dealNext(player)
end

-- NUKE ALL was set off: no hand is dealt until it has played out. Called before its first kill, so the wave it
-- finishes is owed, not dealt; a hand already up stays.
function UpgradesService.HoldForNuke()
	resumeAt = math.max(resumeAt, os.clock() + Tune.AFTER_NUKE_SECONDS)
end

-- A new run: every level and every hand owed is gone.
function UpgradesService.ResetRun()
	upgradeStats.ClearAll()
	resumeAt = 0
	for player, run in runs do
		table.clear(run.Levels)
		table.clear(run.Owed)
		run.Stashed = nil
		run.ShownUntil = 0
		if run.Hand then
			run.Hand = nil
			ServerNetworkUpgrades.Picked.Fire(player, 0, false)
		end
		ServerNetworkUpgrades.Reset.Fire(player)
	end
end

-- Keeps card `index` of the hand that is up, closes it and deals the next one owed.
local function pick(player: Player, run: TRun, hand: THand, index: number, isAuto: boolean)
	local card = hand.Cards[index]
	local data: TData.TUpgrade = UPGRADES[card.Id]
	run.Hand = nil
	run.Levels[card.Id] = card.Level
	run.ShownUntil = os.clock() + UpgradesCore.SHOW_SECONDS
	upgradeStats.Add(player, card.Id, UpgradesCore.Amount(data, card.Rarity))
	ServerNetworkUpgrades.Picked.Fire(player, index, isAuto)
	-- Still picking while the card is shown: this tells the others what was taken.
	ServerNetworkUpgrades.Picking.FireAll(player, true, card.Rarity)
	dealNext(player)
	releaseRoundIfDone()
end

-- Takes a body out of the fight for a pick. Its flowfield goes too: nothing walks to it meanwhile, and a barricade
-- placed under the pick would flood it for nothing. It is built again from where the body stands once it is back.
local function benchForPick(characterEntity: any)
	World:add(characterEntity, Tags.Picking)
	local instanceId = World:get(characterEntity, Components.InstanceId)
	if instanceId then NavService.RemoveCharacter(instanceId) end
end

-- Starts or ends `player`'s pick, and tells everybody.
local function setPicking(player: Player, run: TRun, isPicking: boolean)
	run.IsPicking = isPicking
	local characterEntity = getCharacterEntityFromPlayer(player)
	if characterEntity and isPicking then
		benchForPick(characterEntity)
	elseif characterEntity then
		World:remove(characterEntity, Tags.Picking)
	end
	ServerNetworkUpgrades.Picking.FireAll(player, isPicking, 0)
end

-- Every player's pick starts and ends here, once a frame, and the match is held while nobody is left playing.
local function updatePicking(now: number)
	local isEverybodyPicking = next(runs) ~= nil
	for player, run in runs do
		local isPicking = run.Hand ~= nil or now < run.ShownUntil
		if isPicking ~= run.IsPicking then setPicking(player, run, isPicking) end
		if not isPicking then isEverybodyPicking = false end
	end

	TimeService.SetHeld(isEverybodyPicking)
end

-- Real seconds from `now` until the hands a fallen boss held back are dealt.
local function getAfterBossSeconds(now: number): number
	local seconds = Tune.AFTER_BOSS_SECONDS
	for player in runs do
		seconds = math.max(seconds, EquipmentDropsService.ShownUntil(player) + Tune.AFTER_DROP_SECONDS - now)
	end

	return seconds
end

-- A boss is coming: every hand up is put away as it stands, its auto-pick stopped where it was. The players see it
-- leave as it came.
local function stashHands(now: number)
	for player, run in runs do
		local hand = run.Hand
		if not hand then continue end
		run.Hand = nil
		run.Stashed = hand
		run.StashedSeconds = math.max(hand.PickAt - now, 0)
		ServerNetworkUpgrades.Picked.Fire(player, 0, false)
	end
end

-- The boss's fall has been seen: the hands it held back are dealt, and the countdown it holds runs on once nobody has
-- one up.
local function resumeHands()
	resumeAt = 0
	for player in runs do
		dealNext(player)
	end

	releaseRoundIfDone()
end

-- On the kill count reaching the round, not its clear: which bodies fell does not matter.
RoundService.OnRoundKilled:Connect(function(round: number)
	local isDealt = false
	for _, player in Players:GetPlayers() do
		UpgradesService.Grant(player, round)
		local run = runs[player]
		if run and (run.Hand or not CharacterService.IsStanding(player)) then isDealt = true end
	end

	if isDealt then RoundService.HoldNextPrepare(UpgradesCore.AUTO_PICK_SECONDS) end
end)

-- A clear while a boss or a nuke holds hands back (a boss coming or up, its fall or the blast still being seen): the
-- countdown it opens waits for them. Told before that countdown opens.
RoundService.OnRoundCleared:Connect(function()
	for _, run in runs do
		if run.Stashed or (run.Owed[1] and not run.Hand) then
			RoundService.HoldNextPrepare(getAfterBossSeconds(os.clock()) + UpgradesCore.AUTO_PICK_SECONDS)
			return
		end
	end
end)

-- Lifesteal: a kill of his own heals the killer.
EnemiesService.OnEnemyDied:Connect(function(_, _, killer: Player?)
	if not killer then return end
	local heal = upgradeStats.Get(killer, EUpgradesIds.Lifesteal)
	if heal <= 0 then return end
	local characterEntity = getCharacterEntityFromPlayer(killer)
	if characterEntity then CharacterService.Heal(characterEntity, heal) end
end)

-- A revived body built: the hand it is owed, and the countdown let go if that was all it waited for.
CharacterService.OnStood:Connect(function(player: Player)
	dealNext(player)
	releaseRoundIfDone()
end)

-- A body revived mid-pick is as safe as the one it replaces.
CharacterService.OnCharacterReady:Connect(function(characterEntity, player: Player)
	local run = runs[player]
	if run and run.IsPicking then benchForPick(characterEntity) end
end)

UpgradesService.OnPlayerConnected = function(player: Player)
	runs[player] = {
		Levels = {},
		Owed = {},
		Hand = nil,
		Stashed = nil,
		StashedSeconds = 0,
		ShownUntil = 0,
		IsPicking = false,
	}
	for other, run in runs do
		if run.IsPicking then ServerNetworkUpgrades.Picking.Fire(player, other, true, 0) end
	end
end :: TPlayerEvents.OnPlayerConnected

UpgradesService.OnPlayerDisconnected = function(player: Player)
	runs[player] = nil
	upgradeStats.Clear(player)
	-- The leaver may have been the last one picking.
	releaseRoundIfDone()
end :: TPlayerEvents.OnPlayerDisconnected

-- Needs no character: a downed player picks too. The index is only a place in the hand this side dealt, so a client
-- can name nothing it was not offered.
ClientNetworkUpgrades.Pick.On(function(player: Player, index: number)
	local run = runs[player]
	local hand = if run then run.Hand else nil
	if not run or not hand or not hand.Cards[index] then return end
	pick(player, run, hand, index, false)
end)

-- The guards are the hand's and the purse's: a hand up, and the Gold its next redeal costs, taken in the same step.
ClientNetworkUpgrades.Reroll.On(function(player: Player)
	local run = runs[player]
	local hand = if run then run.Hand else nil
	if not run or not hand then return end
	if not EconomyService.TrySpendGold(player, UpgradesCore.RerollPrice(hand.Rerolls)) then return end

	hand.Rerolls += 1
	hand.Cards = UpgradesCore.Deal(ALL_UPGRADES, run.Levels, hand.Cards, random)
	offer(player, hand, UpgradesCore.AUTO_PICK_SECONDS, true)
end)

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	local isRunOver = RoundService.State == RoundService.ERoundState.Idle
	local isBossTime = RoundService.IsBossTime()
	if isBossTime and not wasBossTime then
		resumeAt = 0
		stashHands(now)
	elseif wasBossTime and not isBossTime then
		resumeAt = now + getAfterBossSeconds(now)
	end
	wasBossTime = isBossTime
	if resumeAt > 0 and now >= resumeAt then resumeHands() end
	for player, run in runs do
		local hand = run.Hand
		if not hand then continue end
		-- The run ended under an open hand: it is taken back, and stays owed if the run is picked up again.
		if isRunOver then
			run.Hand = nil
			table.insert(run.Owed, 1, hand.Round)
			ServerNetworkUpgrades.Picked.Fire(player, 0, false)
		elseif now >= hand.PickAt then
			pick(player, run, hand, random:NextInteger(1, #hand.Cards), true)
		end
	end

	updatePicking(now)
end)

return Ignis.Register(UpgradesService)
