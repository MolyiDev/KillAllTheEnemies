local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EGunsIds = require(ReplicatedStorage.Types.Enums.Data.EGunsIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TGun = {
	Id = EGunsIds.FreezePistol,
	Name = "Freeze Pistol",
	ModelName = "FreezePistol",
	Rarity = "Uncommon",
	Tier = 1,
	Price = 750,
	Damage = 25,
	FireInterval = 0.35,
	Pellets = 1,
	SpreadDeg = 0.8,
	Range = 300,
	HitRadius = 0.35,
	Length = 2,
	Hold = "Pistol",
	Hands = { Right = Vector2.new(0.2, 0.34), Left = Vector2.new(0.21, 0.24) },
	Barrel = 0.73,
	Sound = "Pistol",
	RecoilDeg = 0.77,
}

return table.freeze(data)
