local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EGunsIds = require(ReplicatedStorage.Types.Enums.Data.EGunsIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TGun = {
	Id = EGunsIds.FlameGatling,
	Name = "Flame Gatling",
	ModelName = "FlameGatling",
	Rarity = "Rare",
	Tier = 2,
	Price = 2200,
	Damage = 9.5,
	FireInterval = 0.07,
	Pellets = 1,
	SpreadDeg = 3,
	Range = 70,
	HitRadius = 1.4,
	Length = 3.6,
	IsFlipped = true,
	Hold = "Heavy",
	Hands = { Right = Vector2.new(0.17, 0.8), Left = Vector2.new(0.43, 0.84) },
	Barrel = 0.61,
	Sound = "Minigun",
	RecoilDeg = 0.25,
}

return table.freeze(data)
