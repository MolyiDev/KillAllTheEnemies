local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EGunsIds = require(ReplicatedStorage.Types.Enums.Data.EGunsIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TGun = {
	Id = EGunsIds.HackerDrum,
	Name = "Hacker Drum",
	ModelName = "HackerDrum",
	Rarity = "Legendary",
	Tier = 4,
	Price = 13000,
	Damage = 10,
	FireInterval = 0.08,
	Pellets = 1,
	SpreadDeg = 1.4,
	Range = 300,
	HitRadius = 0.7,
	Length = 3.6,
	IsFlipped = true,
	Hold = "Rifle",
	Sound = "Rifle",
}

return table.freeze(data)
