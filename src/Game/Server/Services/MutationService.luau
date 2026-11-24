-- The Mutation Lab's part of a match (PotionsCore): the energy kills drop, and the potions each player drinks as a run
-- starts. A kill drops its kind's energy for its killer on its kind's chance; a boss's drops for everybody in the match,
-- each on their own roll. A drop is told to its player at once (Mutation.EnergyDropped) and gathered in memory, written
-- every FLUSH_SECONDS and once more as the player leaves, since a nuke can drop a dozen in one frame and a profile
-- write clones the whole profile.
--
-- A potion drunk adds its effects to the run upgrades' sums (upgradeStats), so every service that reads an upgrade
-- reads the potion too, and is used up by one match (a Mythic by two).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local NetworkMeta = require(ServerScriptService.GlobalServer.NetworkMeta)
local DatabaseService = require(ServerScriptService.GlobalServer.Services.DatabaseService)
local EnemiesService = require(script.Parent.EnemiesService)
local upgradeStats = require(script.Parent.Parent.Utils.upgradeStats)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local PotionsCore = require(ReplicatedStorage.GlobalShared.Core.PotionsCore)
local ERarities = require(ReplicatedStorage.Types.Enums.ERarities)
local TData = require(ReplicatedStorage.Types.TData)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)

local ServerNetworkMutation = NetworkMeta.Server.Mutation

local FLUSH_SECONDS = 3

local MutationService = {}

local random = Random.new()
-- Per player: energy dropped and not written yet, by enemy data Name.
local pending: { [Player]: { [string]: number } } = {}
local nextFlushAt = 0
local potionsByName: { [string]: TData.TPotion } = {}
for _, potion in DataCore.Potions.All do
	potionsByName[potion.Name] = potion
end

-- Each player drinks what is in their slots: its effects go on the run's sums, it loses a match, and one with none
-- left goes from the lab. Called as a run starts, after the run upgrades are cleared.
function MutationService.DrinkAll(players: { Player })
	for _, player in players do
		local drunk: { { Data: TData.TPotion, Rarity: number } } = {}
		DatabaseService.Update(player, function(profile)
			local mutation = profile.Mutation
			if not mutation or #mutation.Equipped == 0 then return false end
			for index = #mutation.Potions, 1, -1 do
				local potion = mutation.Potions[index]
				local slot = table.find(mutation.Equipped, potion.Id)
				local data = potionsByName[potion.Name]
				if not slot or not data then continue end
				table.insert(drunk, 1, { Data = data, Rarity = (ERarities :: any)[potion.Rarity] or ERarities.Common })
				potion.Matches -= 1
				if potion.Matches > 0 then continue end
				table.remove(mutation.Potions, index)
				table.remove(mutation.Equipped, slot)
			end
			return #drunk > 0
		end)
		if #drunk == 0 then continue end

		local recipeIds, rarities = table.create(#drunk), table.create(#drunk)
		for index, entry in drunk do
			for _, effect in PotionsCore.Effects(entry.Data, entry.Rarity) do
				upgradeStats.Add(player, effect.Upgrade, effect.Amount)
			end
			recipeIds[index] = entry.Data.Id
			rarities[index] = entry.Rarity
		end
		ServerNetworkMutation.Drunk.Fire(player, recipeIds, rarities)
		DatabaseService.SaveAsync(player)
	end
end

local function drop(player: Player, enemy: TData.TEnemy)
	local counts = pending[player]
	if not counts then
		counts = {}
		pending[player] = counts
	end
	counts[enemy.Name] = (counts[enemy.Name] or 0) + 1
	ServerNetworkMutation.EnergyDropped.Fire(player, enemy.Id)
end

-- Kept when the profile is not open, so it goes in with the next flush.
local function flush(player: Player)
	local counts = pending[player]
	if not counts then return end
	local isWritten = DatabaseService.Update(player, function(profile)
		local mutation = profile.Mutation or PotionsCore.Empty()
		for name, amount in counts do
			mutation.Energy[name] = (mutation.Energy[name] or 0) + amount
		end
		profile.Mutation = mutation
		return true
	end)

	if isWritten then pending[player] = nil end
end

MutationService.OnPlayerDisconnected = function(player: Player)
	flush(player)
	pending[player] = nil
end :: TPlayerEvents.OnPlayerDisconnected

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if now < nextFlushAt or next(pending) == nil then return end
	nextFlushAt = now + FLUSH_SECONDS
	for player in pending do
		flush(player)
	end
end)

EnemiesService.OnEnemyDied:Connect(function(_, enemy: TData.TEnemy, killer: Player?)
	local energy = enemy.Energy
	if not energy then return end
	if not enemy.IsBoss then
		if killer and random:NextNumber() < energy.Chance then drop(killer, enemy) end
		return
	end

	for _, player in Players:GetPlayers() do
		if random:NextNumber() < energy.Chance then drop(player, enemy) end
	end
end)

return Ignis.Register(MutationService)
