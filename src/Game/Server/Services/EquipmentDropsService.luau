-- The equipment a boss drops (TData.TEquipment.Drop): as one dies, every player in the match rolls each piece it drops
-- that they do not own yet, on its own chance. A piece won is theirs at once (EquipmentService.Grant saves it) and
-- shown to them where they stand (Equipment.Dropped).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local NetworkMeta = require(ServerScriptService.GlobalServer.NetworkMeta)
local EquipmentService = require(ServerScriptService.GlobalServer.Services.EquipmentService)
local EnemiesService = require(script.Parent.EnemiesService)
local EquipmentCore = require(ReplicatedStorage.GlobalShared.Core.EquipmentCore)
local TData = require(ReplicatedStorage.Types.TData)

local ServerNetworkEquipment = NetworkMeta.Server.Equipment

local EquipmentDropsService = {}

local random = Random.new()

-- Every piece some boss drops, by the boss's data Id.
local dropsByEnemy: { [number]: { TData.TEquipment } } = {}
for _, item in EquipmentCore.All do
	local drop = item.Drop
	if not drop then continue end
	local list = dropsByEnemy[drop.Enemy]
	if not list then
		list = {}
		dropsByEnemy[drop.Enemy] = list
	end
	table.insert(list, item)
end

-- Rolls each of `drops` for `player`. A piece they own already is won for nothing: there is no second copy.
local function roll(player: Player, drops: { TData.TEquipment })
	for _, item in drops do
		local drop = item.Drop
		if not drop or random:NextNumber() >= drop.Chance then continue end
		if EquipmentService.Grant(player, item) then ServerNetworkEquipment.Dropped.Fire(player, item.Id) end
	end
end

EnemiesService.OnEnemyDied:Connect(function(_, enemyData: TData.TEnemy)
	local drops = dropsByEnemy[enemyData.Id]
	if not drops then return end
	for _, player in Players:GetPlayers() do
		roll(player, drops)
	end
end)

return Ignis.Register(EquipmentDropsService)
