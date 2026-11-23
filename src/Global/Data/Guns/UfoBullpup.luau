local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EGunsIds = require(ReplicatedStorage.Types.Enums.Data.EGunsIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TGun = {
	Id = EGunsIds.UfoBullpup,
	Name = "UFO Bullpup",
	ModelName = "UFO Bullpup",
	Rarity = "Legendary",
	Tier = 4,
	Price = 12500,
	Damage = 46,
	FireInterval = 0.1,
	Pellets = 1,
	SpreadDeg = 1,
	Range = 300,
	HitRadius = 0.45,
	Length = 3.6,
	Hold = "Rifle",
	Hands = { Right = Vector2.new(0.42, 0.28), Left = Vector2.new(0.7, 0.47) },
	Barrel = 0.57,
	Sound = "Rifle",
	RecoilDeg = 0.89,
}

return table.freeze(data)
