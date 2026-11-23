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
	Damage = 70,
	FireInterval = 0.5,
	Pellets = 1,
	SpreadDeg = 0.4,
	Range = 300,
	Pierce = 5,
	HitRadius = 0.7,
	Length = 3.8,
	Hold = "Rifle",
	Hands = { Right = Vector2.new(0.33, 0.36), Left = Vector2.new(0.7, 0.58) },
	Barrel = 0.7,
	Sound = "Rifle",
	RecoilDeg = 2.0,
}

return table.freeze(data)
