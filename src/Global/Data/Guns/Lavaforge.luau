local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EGunsIds = require(ReplicatedStorage.Types.Enums.Data.EGunsIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TGun = {
	Id = EGunsIds.Lavaforge,
	Name = "Lavaforge",
	ModelName = "Lavaforge",
	Rarity = "BlackMarket",
	Tier = 4,
	Price = 25000,
	Damage = 24,
	FireInterval = 0.11,
	Pellets = 1,
	SpreadDeg = 1.2,
	Range = 300,
	HitRadius = 0.45,
	Length = 3.6,
	Hold = "Rifle",
	Sound = "Rifle",
}

return table.freeze(data)
