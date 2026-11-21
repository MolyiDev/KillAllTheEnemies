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
	Damage = 85,
	FireInterval = 1.2,
	Pellets = 1,
	SpreadDeg = 0,
	Range = 500,
	HitRadius = 0.15,
	Length = 4.4,
	Hold = "Rifle",
	Sound = "Sniper",
	CycleSound = "Bolt",
}

return table.freeze(data)
