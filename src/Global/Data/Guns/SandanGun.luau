local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EGunsIds = require(ReplicatedStorage.Types.Enums.Data.EGunsIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TGun = {
	Id = EGunsIds.SandanGun,
	Name = "Sandan Gun",
	ModelName = "SANDAN Gun",
	Rarity = "Legendary",
	Tier = 4,
	Price = 12000,
	Damage = 110,
	FireInterval = 0.4,
	Pellets = 1,
	SpreadDeg = 0.3,
	Range = 500,
	Pierce = 10,
	HitRadius = 2.0,
	Length = 4.2,
	Hold = "Rifle",
	Hands = { Right = Vector2.new(0.28, 0.45), Left = Vector2.new(0.6, 0.7) },
	Barrel = 0.84,
	Sound = "Sniper",
	RecoilDeg = 2.45,
}

return table.freeze(data)
