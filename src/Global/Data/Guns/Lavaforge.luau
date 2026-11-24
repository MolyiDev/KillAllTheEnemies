local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EGunsIds = require(ReplicatedStorage.Types.Enums.Data.EGunsIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TGun = {
	Id = EGunsIds.Lavaforge,
	Name = "Lavaforge",
	ModelName = "Lavaforge",
	Rarity = "Mythic",
	Tier = 4,
	Price = 25000,
	Damage = 32,
	FireInterval = 0.11,
	Pellets = 1,
	SpreadDeg = 1.2,
	Range = 300,
	Pierce = 1,
	HitRadius = 0.45,
	Length = 3.6,
	Hold = "Rifle",
	Hands = { Right = Vector2.new(0.25, 0.42), Left = Vector2.new(0.65, 0.64) },
	Barrel = 0.78,
	Sound = "Rifle",
	RecoilDeg = 1.07,
}

return table.freeze(data)
