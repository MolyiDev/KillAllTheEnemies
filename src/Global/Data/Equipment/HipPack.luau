local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EEnemiesIds = require(ReplicatedStorage.Types.Enums.Data.EEnemiesIds)
local EEquipmentIds = require(ReplicatedStorage.Types.Enums.Data.EEquipmentIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TEquipment = {
	Id = EEquipmentIds.HipPack,
	Name = "Hip Pack",
	Slot = "Legs",
	Rarity = "Epic",
	Description = "A pouch on the belt with room for every coin a monster drops.",
	Stats = { { Stat = "KillGold", Value = 0.2 } },
	ModelName = "HipPack",
	Drop = { Enemy = EEnemiesIds.TRex, Chance = 0.05 },
}

return table.freeze(data)
