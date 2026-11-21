local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EGunsIds = require(ReplicatedStorage.Types.Enums.Data.EGunsIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TGun = {
	Id = EGunsIds.CorruptedRunesAk,
	Name = "Corrupted Runes AK",
	ModelName = "Corrupted Runes AK",
	Rarity = "BlackMarket",
	Tier = 4,
	Price = 28000,
	Damage = 26,
	FireInterval = 0.1,
	Pellets = 1,
	SpreadDeg = 1.2,
	Range = 300,
	HitRadius = 0.45,
	Length = 3.6,
	Hold = "Rifle",
	Sound = "Rifle",
}

return table.freeze(data)
