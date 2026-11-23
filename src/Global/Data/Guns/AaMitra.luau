local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EGunsIds = require(ReplicatedStorage.Types.Enums.Data.EGunsIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TGun = {
	Id = EGunsIds.AaMitra,
	Name = "AA Mitra",
	ModelName = "AAMitra",
	Rarity = "Common",
	Tier = 1,
	Price = 700,
	Damage = 5,
	FireInterval = 0.09,
	Pellets = 1,
	SpreadDeg = 1.4,
	Range = 300,
	HitRadius = 0.45,
	Length = 3.2,
	Hold = "Rifle",
	Hands = { Right = Vector2.new(0.32, 0.27), Left = Vector2.new(0.63, 0.2) },
	Barrel = 0.63,
	Sound = "SMG",
}

return table.freeze(data)
