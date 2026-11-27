local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EEnemiesIds = require(ReplicatedStorage.Types.Enums.Data.EEnemiesIds)
local TData = require(ReplicatedStorage.Types.TData)

-- The Giant Spider's young, out of every egg sac left whole when its Brood ends: its own rig at a fifth of the size,
-- legs on the same IK, the blades' chop as a quick bite. Fast and fragile. Never drawn into a wave.
local data: TData.TEnemy = {
	Id = EEnemiesIds.Spiderling,
	Name = "Spiderling",
	Description = "A Giant Spider's hatchling, quick on its blade legs and hungry from the start.",
	ModelName = "GiantSpider",
	ModelScale = 0.22,
	AnimationSet = "Spider",
	HasLegIK = true,
	Colors = {
		Skin = Color3.fromRGB(233, 213, 170),
		Top = Color3.fromRGB(255, 58, 42),
		Legs = Color3.fromRGB(229, 232, 237),
	},
	CollisionSize = Vector3.new(3.5, 2.5, 3.5),
	AimPieces = {
		{ Ahead = 0, Bottom = 0, Height = 3.2, Radius = 2.3 },
	},
	Mass = 2,
	BaseMaxHealth = 140,
	BaseDamage = 12,
	BaseMovementSpeed = 19,
	Attacks = {
		{
			Kind = "Melee",
			Range = 3,
			Delay = 0.55,
			Cooldown = 1,
			DamageScale = 1,
			AnimationName = "ScytheCross",
			ClipImpact = 0.85,
		},
	},
	HitStunTime = 0.3,
	IntroRound = 15,
	SpawnWeight = 0,
	GoldDrop = 8,
}

return table.freeze(data)
