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
	Damage = 36,
	FireInterval = 0.08,
	Pellets = 1,
	SpreadDeg = 1.4,
	Range = 300,
	HitRadius = 0.7,
	Length = 3.6,
	IsFlipped = true,
	Hold = "Rifle",
	Hands = { Right = Vector2.new(0.43, 0.42), Left = Vector2.new(0.69, 0.5) },
	Barrel = 0.77,
	Sound = "Rifle",
	RecoilDeg = 0.65,
}

return table.freeze(data)
