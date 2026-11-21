local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EGunsIds = require(ReplicatedStorage.Types.Enums.Data.EGunsIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TGun = {
	Id = EGunsIds.SnowyRifle,
	Name = "Snowy Rifle",
	ModelName = "SNOWYRIFLE",
	Rarity = "Epic",
	Tier = 3,
	Price = 6500,
	Damage = 55,
	FireInterval = 0.5,
	Pellets = 1,
	SpreadDeg = 0.4,
	Range = 300,
	HitRadius = 0.225,
	Length = 3.8,
	Hold = "Rifle",
	Sound = "Rifle",
}

return table.freeze(data)
