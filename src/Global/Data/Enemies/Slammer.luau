local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EEnemiesIds = require(ReplicatedStorage.Types.Enums.Data.EEnemiesIds)
local TData = require(ReplicatedStorage.Types.TData)

-- GDD 11, required: an ordinary zombie with a charged area attack. It plants, shows its circle, and slams.
local data: TData.TEnemy = {
	Id = EEnemiesIds.Slammer,
	Name = "AoE Zombie",
	ModelName = "Abomination",
	AnimationSet = "MonsterR6",
	Sounds = { Group = "Enemies.Troll", Idle = "Idle", Attack = "Attack", Death = "Death" },
	Colors = {
		Skin = Color3.fromRGB(110, 140, 90),
		Top = Color3.fromRGB(66, 65, 64),
		Legs = Color3.fromRGB(40, 47, 54),
	},
	CollisionSize = Vector3.new(2.6, 6, 2),
	Mass = 2,
	BaseMaxHealth = 60,
	BaseDamage = 18,
	BaseMovementSpeed = 10,
	Attacks = {
		{ Kind = "Slam", Range = 9, Delay = 1.4, Cooldown = 3, DamageScale = 1, Radius = 8, AnimationName = "Slam" },
	},
	IntroRound = 6,
	SpawnWeight = 2,
	GoldDrop = 8,
}

return table.freeze(data)
