local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EEnemiesIds = require(ReplicatedStorage.Types.Enums.Data.EEnemiesIds)
local TData = require(ReplicatedStorage.Types.TData)

-- The Skeleton T-Rex's guards (its Summon): four rise round the arena at each quarter of its
-- health gone and hold its shield up until they fall.
-- Never drawn into a wave. Tough enough that killing them is the party's job for a while, never a chore.
local data: TData.TEnemy = {
	Id = EEnemiesIds.FossilGuard,
	Name = "Fossil Guard",
	Description = "Old bones the Skeleton T-Rex calls up from the ground. While they stand, its shield holds.",
	ModelName = "Revenant",
	AnimationSet = "MonsterR6",
	Sounds = { Group = "Enemies.Zombie", Idle = "Idle", Attack = "Attack", Death = "Death" },
	Colors = {
		Skin = Color3.fromRGB(232, 212, 172),
		Top = Color3.fromRGB(40, 127, 71),
		Legs = Color3.fromRGB(232, 212, 172),
	},
	Glow = Color3.fromRGB(90, 255, 140),
	CollisionSize = Vector3.new(2.6, 6, 2),
	Mass = 3,
	BaseMaxHealth = 300,
	BaseDamage = 18,
	BaseMovementSpeed = 11,
	Attacks = {
		{ Kind = "Melee", Range = 3, Delay = 0.8, Cooldown = 1.2, DamageScale = 1 },
	},
	IntroRound = 15,
	SpawnWeight = 0,
	GoldDrop = 15,
}

return table.freeze(data)
