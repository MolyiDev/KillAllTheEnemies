local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EGunsIds = require(ReplicatedStorage.Types.Enums.Data.EGunsIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TGun = {
	Id = EGunsIds.AwpThePrince,
	Name = "AWP The Prince",
	ModelName = "AWP The Prince",
	Rarity = "Rare",
	Tier = 2,
	Price = 2600,
	Damage = 90,
	FireInterval = 1.2,
	Pellets = 1,
	SpreadDeg = 0,
	Range = 500,
	Pierce = 8,
	HitRadius = 1.4,
	Length = 4.4,
	Hold = "Rifle",
	Hands = { Right = Vector2.new(0.25, 0.23), Left = Vector2.new(0.55, 0.42) },
	Barrel = 0.61,
	Sound = "Sniper",
	CycleSound = "Bolt",
	RecoilDeg = 2.9,
}

return table.freeze(data)
