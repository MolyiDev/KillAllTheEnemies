local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EGunsIds = require(ReplicatedStorage.Types.Enums.Data.EGunsIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TGun = {
	Id = EGunsIds.AwpPrintstream,
	Name = "AWP Printstream",
	ModelName = "AWP Printstream",
	Rarity = "Common",
	Tier = 1,
	Price = 900,
	Damage = 60,
	FireInterval = 1.2,
	Pellets = 1,
	SpreadDeg = 0,
	Range = 500,
	Pierce = 2,
	HitRadius = 1.0,
	Length = 4.4,
	Hold = "Rifle",
	Hands = { Right = Vector2.new(0.25, 0.23), Left = Vector2.new(0.55, 0.44) },
	Barrel = 0.56,
	Sound = "Sniper",
	CycleSound = "Bolt",
}

return table.freeze(data)
