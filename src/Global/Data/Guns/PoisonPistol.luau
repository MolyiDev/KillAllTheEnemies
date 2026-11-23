local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EGunsIds = require(ReplicatedStorage.Types.Enums.Data.EGunsIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TGun = {
	Id = EGunsIds.PoisonPistol,
	Name = "Poison Pistol",
	ModelName = "Poison Pistol",
	Rarity = "Epic",
	Tier = 3,
	Price = 6000,
	Damage = 48,
	FireInterval = 0.4,
	Pellets = 1,
	SpreadDeg = 0.8,
	Range = 300,
	Pierce = 3,
	HitRadius = 0.35,
	Length = 2.2,
	Hold = "Pistol",
	Hands = { Right = Vector2.new(0.16, 0.33), Left = Vector2.new(0.18, 0.22) },
	Barrel = 0.55,
	Sound = "Pistol",
	RecoilDeg = 1.61,
}

return table.freeze(data)
