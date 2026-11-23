local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EGunsIds = require(ReplicatedStorage.Types.Enums.Data.EGunsIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TGun = {
	Id = EGunsIds.StarterRifle,
	Name = "Starter Rifle",
	ModelName = "2",
	Rarity = "Starter",
	Tier = 3,
	Price = 0,
	Damage = 18,
	FireInterval = 0.15,
	Pellets = 1,
	SpreadDeg = 0.6,
	Range = 300,
	Pierce = 1,
	HitRadius = 0.45,
	Length = 3.6,
	IsFlipped = true,
	Hold = "Rifle",
	Hands = { Right = Vector2.new(0.3, 0.45), Left = Vector2.new(0.66, 0.72) },
	Barrel = 0.79,
	Sound = "StarterRifle",
	Fx = "RifleFx",
}

return table.freeze(data)
