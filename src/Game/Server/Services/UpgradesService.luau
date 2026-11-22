-- The run upgrades: every wave's worth of kills (RoundService.OnRoundKilled) owes each player a hand of three cards (UpgradesCore.Deal), one of which they
-- keep for the run. Hands owed are queued and dealt one at a time; the next wave's countdown is held while anybody is
-- still picking, and a hand nobody picks from in time is picked for them, since the others are waiting on it. What
-- the picks add up to is in Utils/upgradeStats, read by the services whose numbers they change.
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
	-- os.clock until which the card just taken is still on the player's screen.
	ShownUntil: number,
	IsPicking: boolean,
}

local UpgradesService = {}

local runs: { [Player]: TRun } = {}
local random = Random.new()

-- Deals the oldest hand `player` is owed, unless one is already up. A player with every upgrade at its last level is
-- owed nothing more.
local function dealNext(player: Player)
	local run = runs[player]
	if not run or run.Hand or not run.Owed[1] then return end
	if RoundService.State == RoundService.ERoundState.Idle then return end
	local cards = UpgradesCore.Deal(ALL_UPGRADES, run.Levels, nil, random)
	if #cards == 0 then
		table.clear(run.Owed)
		return
	end

	local round = table.remove(run.Owed, 1) :: number
	run.Hand = {
		Cards = cards,
		Round = round,
		Rerolls = 0,
		PickAt = os.clock() + UpgradesCore.AUTO_PICK_SECONDS,
	}
	ServerNetworkUpgrades.Offer.Fire(player, {
		Cards = cards,
		Round = round,
		RerollPrice = UpgradesCore.RerollPrice(0),
		Seconds = UpgradesCore.AUTO_PICK_SECONDS,
		IsReroll = false,
	})
end

-- The countdown to the next wave runs again once nobody has a hand up.
local function releaseRoundIfDone()
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

-- A new run: every level and every hand owed is gone.
function UpgradesService.ResetRun()
	upgradeStats.ClearAll()
	for player, run in runs do
		table.clear(run.Levels)
		table.clear(run.Owed)
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

-- On the kill count reaching the round, not its clear: which bodies fell does not matter.
RoundService.OnRoundKilled:Connect(function(round: number)
	local isDealt = false
	for _, player in Players:GetPlayers() do
		UpgradesService.Grant(player, round)
		local run = runs[player]
		if run and run.Hand then isDealt = true end
	end

	if isDealt then RoundService.HoldNextPrepare(UpgradesCore.AUTO_PICK_SECONDS) end
end)

-- Lifesteal: a kill of his own heals the killer.
EnemiesService.OnEnemyDied:Connect(function(_, _, killer: Player?)
	if not killer then return end
	local heal = upgradeStats.Get(killer, EUpgradesIds.Lifesteal)
	if heal <= 0 then return end
	local characterEntity = getCharacterEntityFromPlayer(killer)
	if characterEntity then CharacterService.Heal(characterEntity, heal) end
end)

-- A body revived mid-pick is as safe as the one it replaces.
CharacterService.OnCharacterReady:Connect(function(characterEntity, player: Player)
	local run = runs[player]
	if run and run.IsPicking then benchForPick(characterEntity) end
end)

UpgradesService.OnPlayerConnected = function(player: Player)
	runs[player] = { Levels = {}, Owed = {}, Hand = nil, ShownUntil = 0, IsPicking = false }
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
	hand.PickAt = os.clock() + UpgradesCore.AUTO_PICK_SECONDS
	ServerNetworkUpgrades.Offer.Fire(player, {
		Cards = hand.Cards,
		Round = hand.Round,
		RerollPrice = UpgradesCore.RerollPrice(hand.Rerolls),
		Seconds = UpgradesCore.AUTO_PICK_SECONDS,
		IsReroll = true,
	})
end)

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	local isRunOver = RoundService.State == RoundService.ERoundState.Idle
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
