local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EGunsIds = require(ReplicatedStorage.Types.Enums.Data.EGunsIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TGun = {
	Id = EGunsIds.SandanGun,
	Name = "Sandan Gun",
	ModelName = "SANDAN Gun",
	Rarity = "Legendary",
	Tier = 4,
	Price = 12000,
	Damage = 70,
	FireInterval = 0.7,
	Pellets = 1,
	SpreadDeg = 0.3,
	Range = 500,
	HitRadius = 0.15,
	Length = 4.2,
	Hold = "Rifle",
	Sound = "Sniper",
}

return table.freeze(data)
