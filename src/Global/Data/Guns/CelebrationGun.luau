local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EGunsIds = require(ReplicatedStorage.Types.Enums.Data.EGunsIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TGun = {
	Id = EGunsIds.CelebrationGun,
	Name = "Celebration Gun",
	ModelName = "Celebration Gun",
	Rarity = "Rare",
	Tier = 2,
	Price = 2000,
	Damage = 13,
	FireInterval = 0.1,
	Pellets = 1,
	SpreadDeg = 1.4,
	Range = 300,
	HitRadius = 0.45,
	Length = 3.4,
	Hold = "Rifle",
	Hands = { Right = Vector2.new(0.25, 0.5), Left = Vector2.new(0.58, 0.59) },
	Barrel = 0.82,
	Sound = "Rifle",
	RecoilDeg = 0.62,
}

return table.freeze(data)
