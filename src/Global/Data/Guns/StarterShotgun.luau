local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EGunsIds = require(ReplicatedStorage.Types.Enums.Data.EGunsIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TGun = {
	Id = EGunsIds.StarterShotgun,
	Name = "Starter Sniper",
	ModelName = "3",
	Rarity = "Rare",
	Tier = 2,
	Price = 1800,
	Damage = 70,
	FireInterval = 1.2,
	Pellets = 1,
	SpreadDeg = 0,
	Range = 500,
	Pierce = 4,
	HitRadius = 1.0,
	Length = 3.8,
	Hold = "Rifle",
	Hands = { Right = Vector2.new(0.24, 0.25), Left = Vector2.new(0.52, 0.38) },
	Barrel = 0.38,
	Sound = "StarterSniper",
	CycleSound = "Bolt",
	Fx = "SniperFx",
	RecoilDeg = 2.15,
}

return table.freeze(data)
