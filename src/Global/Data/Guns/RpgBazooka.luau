local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EGunsIds = require(ReplicatedStorage.Types.Enums.Data.EGunsIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TGun = {
	Id = EGunsIds.RpgBazooka,
	Name = "RPG Bazooka",
	ModelName = "RPG BAZOOKA",
	Rarity = "Epic",
	Tier = 3,
	Price = 7000,
	Damage = 150,
	FireInterval = 1.2,
	Pellets = 1,
	SpreadDeg = 0,
	Range = 300,
	HitRadius = 1.2,
	Length = 3.8,
	PitchDeg = 35,
	SplashRadius = 18,
	Hold = "Launcher",
	Hands = { Right = Vector2.new(0.515, 0.34), Left = Vector2.new(0.415, 0.38) },
	Barrel = 0.46,
	Sound = "Launcher",
	RecoilDeg = 5,
}

return table.freeze(data)
