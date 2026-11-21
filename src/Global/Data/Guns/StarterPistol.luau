local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EGunsIds = require(ReplicatedStorage.Types.Enums.Data.EGunsIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TGun = {
	Id = EGunsIds.StarterPistol,
	Name = "Starter Pistol",
	ModelName = "1",
	Rarity = "Starter",
	Tier = 1,
	Price = 0,
	Damage = 12,
	FireInterval = 0.4,
	Pellets = 1,
	SpreadDeg = 0.8,
	Range = 300,
	HitRadius = 0.35,
	Length = 1.9,
	Hold = "Pistol",
	Sound = "Starter",
	Fx = "PistolFx",
}

return table.freeze(data)
