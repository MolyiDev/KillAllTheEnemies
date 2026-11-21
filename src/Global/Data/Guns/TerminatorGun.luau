local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EGunsIds = require(ReplicatedStorage.Types.Enums.Data.EGunsIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TGun = {
	Id = EGunsIds.TerminatorGun,
	Name = "Terminator Gun",
	ModelName = "TerminatorGun",
	Rarity = "Epic",
	Tier = 3,
	Price = 5600,
	Damage = 88,
	FireInterval = 0.75,
	Pellets = 8,
	SpreadDeg = 8,
	Range = 100,
	Pierce = 1,
	Knockback = 7,
	HitRadius = 0.3,
	Length = 3.6,
	IsFlipped = true,
	Hold = "Rifle",
	Sound = "Shotgun",
	CycleSound = "Pump",
	Fx = "ShotgunFx",
	-- Named so the kick is not worked out from Damage: at 88 that would be 3 degrees, a blast's.
	RecoilDeg = 1.8,
	PoseKick = 3.2,
}

return table.freeze(data)
