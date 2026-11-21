local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EGunsIds = require(ReplicatedStorage.Types.Enums.Data.EGunsIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TGun = {
	Id = EGunsIds.FreezePistol,
	Name = "Freeze Pistol",
	ModelName = "FreezePistol",
	Rarity = "Common",
	Tier = 1,
	Price = 750,
	Damage = 14,
	FireInterval = 0.35,
	Pellets = 1,
	SpreadDeg = 0.8,
	Range = 300,
	HitRadius = 0.35,
	Length = 2,
	IsFlipped = true,
	Hold = "Pistol",
	Sound = "Pistol",
}

return table.freeze(data)
