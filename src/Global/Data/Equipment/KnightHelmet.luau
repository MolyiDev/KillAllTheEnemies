local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EEquipmentIds = require(ReplicatedStorage.Types.Enums.Data.EEquipmentIds)
local TData = require(ReplicatedStorage.Types.TData)

-- Every new player's first piece, worn from their first visit.
local data: TData.TEquipment = {
	Id = EEquipmentIds.KnightHelmet,
	Name = "Knight Helmet",
	Slot = "Head",
	Rarity = "Common",
	Description = "A dented steel helm. Ugly, heavy, and it keeps your head where it belongs.",
	Stats = { { Stat = "MaxHealth", Value = 20 } },
	ModelName = "KnightHelmet",
	EarlyUnlock = true,
}

return table.freeze(data)
