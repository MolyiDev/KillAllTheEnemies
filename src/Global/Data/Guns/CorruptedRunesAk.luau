local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EGunsIds = require(ReplicatedStorage.Types.Enums.Data.EGunsIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TGun = {
	Id = EGunsIds.CorruptedRunesAk,
	Name = "Corrupted Runes AK",
	ModelName = "Corrupted Runes AK",
	Rarity = "BlackMarket",
	Tier = 4,
	Price = 28000,
	Damage = 34,
	FireInterval = 0.1,
	Pellets = 1,
	SpreadDeg = 1.2,
	Range = 300,
	Pierce = 1,
	HitRadius = 0.45,
	Length = 3.6,
	Hold = "Rifle",
	Hands = { Right = Vector2.new(0.28, 0.4), Left = Vector2.new(0.67, 0.68) },
	Barrel = 0.75,
	Sound = "Rifle",
	RecoilDeg = 1.13,
}

return table.freeze(data)
