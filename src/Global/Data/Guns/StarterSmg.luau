local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EGunsIds = require(ReplicatedStorage.Types.Enums.Data.EGunsIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TGun = {
	Id = EGunsIds.StarterSmg,
	Name = "Starter Minigun",
	ModelName = "4",
	Rarity = "Starter",
	Tier = 4,
	Price = 0,
	Damage = 10,
	FireInterval = 0.05,
	Pellets = 1,
	SpreadDeg = 2.2,
	Range = 300,
	Pierce = 1,
	HitRadius = 0.45,
	Length = 3.6,
	IsFlipped = true,
	Hold = "Heavy",
	Hands = { Right = Vector2.new(0.09, 0.82), Left = Vector2.new(0.42, 0.74) },
	Barrel = 0.54,
	Sound = "StarterMinigun",
	ReleaseSound = "StarterMinigunRelease",
	Fx = "MinigunFx",
	RecoilDeg = 0.25,
}

return table.freeze(data)
