local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EEnemiesIds = require(ReplicatedStorage.Types.Enums.Data.EEnemiesIds)
local EUpgradesIds = require(ReplicatedStorage.Types.Enums.Data.EUpgradesIds)
local TData = require(ReplicatedStorage.Types.TData)

-- GDD 11: runs at the nearest player or barricade and hits at melee range. The main horde unit.
local data: TData.TEnemy = {
	Id = EEnemiesIds.Basic,
	Name = "Basic Zombie",
	Description = "The bulk of every horde. Weak alone, but they never stop coming.",
	ModelName = "Walker",
	AnimationSet = "MonsterR6",
	Sounds = { Group = "Enemies.Zombie", Idle = "Idle", Attack = "Attack", Death = "Death" },
	Colors = {
		Skin = Color3.fromRGB(127, 127, 127),
		Top = Color3.fromRGB(116, 107, 100),
		Legs = Color3.fromRGB(77, 67, 61),
	},
	CollisionSize = Vector3.new(2, 5, 1.4),
	Mass = 1,
	BaseMaxHealth = 20,
	BaseDamage = 8,
	BaseMovementSpeed = 12,
	Attacks = {
		{ Kind = "Melee", Range = 2, Delay = 0.6, Cooldown = 1, DamageScale = 1 },
	},
	HitStunTime = 0.3,
	IntroRound = 1,
	SpawnWeight = 10,
	GoldDrop = 2,
	Energy = { Upgrade = EUpgradesIds.Regeneration, Cost = 10, Chance = 0.03, Color = Color3.fromRGB(51, 217, 128) },
}

return table.freeze(data)
