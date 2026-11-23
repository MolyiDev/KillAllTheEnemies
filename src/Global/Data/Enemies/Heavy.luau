local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EEnemiesIds = require(ReplicatedStorage.Types.Enums.Data.EEnemiesIds)
local TData = require(ReplicatedStorage.Types.TData)

-- GDD 11: more health and a slower, readable strike. Not staggered by every hit.
local data: TData.TEnemy = {
	Id = EEnemiesIds.Heavy,
	Name = "Heavy Zombie",
	Description = "A wall of muscle that soaks up bullets and hits hard. Keep your distance.",
	ModelName = "Brute",
	AnimationSet = "MonsterR6",
	Sounds = { Group = "Enemies.Troll", Idle = "Idle", Attack = "Attack", Death = "Death" },
	Colors = {
		Skin = Color3.fromRGB(124, 0, 121),
		Top = Color3.fromRGB(66, 65, 64),
		Legs = Color3.fromRGB(47, 52, 58),
	},
	CollisionSize = Vector3.new(3.5, 6, 2.4),
	Mass = 4,
	BaseMaxHealth = 120,
	BaseDamage = 20,
	BaseMovementSpeed = 8,
	Attacks = {
		{ Kind = "Melee", Range = 3, Delay = 1, Cooldown = 1.6, DamageScale = 1 },
	},
	IntroRound = 5,
	SpawnWeight = 2,
	GoldDrop = 10,
}

return table.freeze(data)
