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
	Damage = 18,
	FireInterval = 0.1,
	Pellets = 1,
	SpreadDeg = 1,
	Range = 300,
	HitRadius = 0.45,
	Length = 3.6,
	Hold = "Rifle",
	Sound = "Rifle",
}

return table.freeze(data)
