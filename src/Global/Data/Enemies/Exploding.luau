local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EEnemiesIds = require(ReplicatedStorage.Types.Enums.Data.EEnemiesIds)
local EUpgradesIds = require(ReplicatedStorage.Types.Enums.Data.EUpgradesIds)
local TData = require(ReplicatedStorage.Types.TData)

-- GDD 11, required: runs in and blows up. The fuse shows its blast circle on the ground for its whole length, and
-- killing it during the fuse cancels the blast (the GDD leaves the trigger open; proximity, cancellable, is the pick
-- here). The blast hurts barricades too.
local data: TData.TEnemy = {
	Id = EEnemiesIds.Exploding,
	Name = "Exploding Zombie",
	Description = "Carries its own fuse. Once it gets close, it lights up and takes everything nearby with it.",
	ModelName = "Bomber",
	AnimationSet = "MonsterR6",
	Sounds = { Group = "Enemies.Zombie", Idle = "Idle", Attack = "Attack", Death = "Death" },
	Colors = {
		Skin = Color3.fromRGB(219, 221, 226),
		Top = Color3.fromRGB(31, 49, 102),
		Legs = Color3.fromRGB(17, 26, 55),
	},
	CollisionSize = Vector3.new(2.6, 5, 2),
	Mass = 1.5,
	BaseMaxHealth = 30,
	BaseDamage = 30,
	BaseMovementSpeed = 13,
	Attacks = {
		{
			Kind = "Explode",
			Range = 6,
			Delay = 1.2,
			Cooldown = 0,
			DamageScale = 1,
			Radius = 10,
			AnimationName = "Fuse",
		},
	},
	HitStunTime = nil,
	IntroRound = 4,
	SpawnWeight = 2,
	GoldDrop = 5,
	Energy = { Upgrade = EUpgradesIds.Damage, Cost = 4, Chance = 0.05, Color = Color3.fromRGB(255, 46, 139) },
}

return table.freeze(data)
