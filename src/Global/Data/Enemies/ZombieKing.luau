local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EEnemiesIds = require(ReplicatedStorage.Types.Enums.Data.EEnemiesIds)
local TData = require(ReplicatedStorage.Types.TData)

-- GDD 14: the proposed boss, every tenth round alongside the ordinary round. A marked ground slam at where its target
-- stood, then an expanding shockwave you jump or run out of. Never staggered; its health bar is the round's.
local data: TData.TEnemy = {
	Id = EEnemiesIds.ZombieKing,
	Name = "Zombie King",
	Description = "Slams the spot you stood on, then sends out a shockwave. Jump over it or run clear.",
	ModelName = "Goliath",
	AnimationSet = "MonsterR6",
	Sounds = { Group = "Enemies.Troll", Idle = "Idle", Attack = "Attack", Death = "Death" },
	Colors = {
		Skin = Color3.fromRGB(148, 83, 78),
		Top = Color3.fromRGB(66, 65, 64),
		Legs = Color3.fromRGB(40, 47, 54),
	},
	CollisionSize = Vector3.new(6, 12, 4),
	Mass = 50,
	BaseMaxHealth = 2500,
	BaseDamage = 35,
	BaseMovementSpeed = 9,
	Attacks = {
		{
			Kind = "Slam",
			Range = 30,
			Delay = 1.6,
			Cooldown = 2,
			DamageScale = 1,
			Radius = 12,
			AtTarget = true,
			AnimationName = "Slam",
		},
		{ Kind = "Melee", Range = 4, Delay = 0.9, Cooldown = 1.2, DamageScale = 0.8 },
		{
			Kind = "Shockwave",
			Range = 18,
			Delay = 1.2,
			Cooldown = 3,
			DamageScale = 0.6,
			Radius = 40,
			Speed = 28,
			AnimationName = "Slam",
		},
	},
	IntroRound = 15,
	SpawnWeight = 0,
	IsBoss = true,
	GoldDrop = 250,
}

return table.freeze(data)
