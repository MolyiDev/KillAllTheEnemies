local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EEnemiesIds = require(ReplicatedStorage.Types.Enums.Data.EEnemiesIds)
local TData = require(ReplicatedStorage.Types.TData)

-- GDD 11: the same rule, faster. Punishes standing still and gaps in the defenses.
local data: TData.TEnemy = {
	Id = EEnemiesIds.Fast,
	Name = "Fast Zombie",
	Description = "Sprints straight at you and hits fast. Fragile, so drop it before it gets close.",
	ModelName = "Runner",
	AnimationSet = "MonsterR6",
	Sounds = { Group = "Enemies.Zombie", Idle = "Idle", Attack = "Attack", Death = "Death" },
	Colors = {
		Skin = Color3.fromRGB(255, 255, 0),
		Top = Color3.fromRGB(28, 28, 27),
		Legs = Color3.fromRGB(70, 70, 44),
	},
	CollisionSize = Vector3.new(1.6, 5.5, 1.2),
	Mass = 0.7,
	BaseMaxHealth = 12,
	BaseDamage = 6,
	BaseMovementSpeed = 20,
	Attacks = {
		{ Kind = "Melee", Range = 1.5, Delay = 0.35, Cooldown = 0.7, DamageScale = 1 },
	},
	HitStunTime = 0.2,
	IntroRound = 3,
	SpawnWeight = 4,
	GoldDrop = 3,
}

return table.freeze(data)
