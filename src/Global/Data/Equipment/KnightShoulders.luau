local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EEnemiesIds = require(ReplicatedStorage.Types.Enums.Data.EEnemiesIds)
local EEquipmentIds = require(ReplicatedStorage.Types.Enums.Data.EEquipmentIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TEquipment = {
	Id = EEquipmentIds.KnightShoulders,
	Name = "Knight Shoulders",
	Slot = "Torso",
	Rarity = "Rare",
	Description = "Steel plates bolted over both shoulders. Claws skid right off them.",
	Stats = { { Stat = "Armor", Value = 0.1 } },
	ModelName = "KnightShoulders",
	Drop = { Enemy = EEnemiesIds.TRex, Chance = 0.15 },
}

return table.freeze(data)
