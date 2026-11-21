local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EGunsIds = require(ReplicatedStorage.Types.Enums.Data.EGunsIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TGun = {
	Id = EGunsIds.DesertEagle,
	Name = "Desert Eagle",
	ModelName = "RemakedDeagle2",
	Rarity = "Common",
	Tier = 1,
	Price = 850,
	Damage = 30,
	FireInterval = 0.55,
	Pellets = 1,
	SpreadDeg = 0.8,
	Range = 300,
	HitRadius = 0.35,
	Length = 2,
	Hold = "Pistol",
	Sound = "Magnum",
}

return table.freeze(data)
