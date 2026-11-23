local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EGunsIds = require(ReplicatedStorage.Types.Enums.Data.EGunsIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TGun = {
	Id = EGunsIds.TerminatorGun,
	Name = "Terminator Gun",
	ModelName = "TerminatorGun",
	Rarity = "Starter",
	Tier = 2,
	Price = 0,
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
	Hands = { Right = Vector2.new(0.34, 0.36), Left = Vector2.new(0.78, 0.52) },
	Barrel = 0.72,
	Sound = "TerminatorGun",
	CycleSound = "TerminatorGunPump",
	Fx = "ShotgunFx",
	-- Named so the kick is not worked out from Damage: at 88 that would be 3 degrees, a blast's.
	RecoilDeg = 1.8,
	PoseKick = 3.2,
}

return table.freeze(data)
