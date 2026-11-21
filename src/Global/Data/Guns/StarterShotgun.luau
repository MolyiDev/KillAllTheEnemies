local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EGunsIds = require(ReplicatedStorage.Types.Enums.Data.EGunsIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TGun = {
	Id = EGunsIds.StarterShotgun,
	Name = "Starter Sniper",
	ModelName = "3",
	Rarity = "Starter",
	Tier = 3,
	Price = 0,
	Damage = 60,
	FireInterval = 1.2,
	Pellets = 1,
	SpreadDeg = 0,
	Range = 500,
	HitRadius = 0.15,
	Length = 3.8,
	Hold = "Rifle",
	Sound = "StarterSniper",
	CycleSound = "Bolt",
	Fx = "SniperFx",
}

return table.freeze(data)
