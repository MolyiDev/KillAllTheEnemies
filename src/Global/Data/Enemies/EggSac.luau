local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EEnemiesIds = require(ReplicatedStorage.Types.Enums.Data.EEnemiesIds)
local TData = require(ReplicatedStorage.Types.TData)

-- The Giant Spider's egg sacs (its Brood): four laid round the arena while it hangs out of reach. Each still whole when
-- it drops bursts into Spiderlings. They never move or strike; they are the party's targets for a while.
-- Never drawn into a wave.
local data: TData.TEnemy = {
	Id = EEnemiesIds.EggSac,
	Name = "Egg Sac",
	Description = "A pulsing sac the Giant Spider leaves behind. Whatever is still inside when it comes down hatches.",
	ModelName = "SpiderEggSac",
	AnimationSet = "EggSac",
	Colors = {
		Skin = Color3.fromRGB(236, 233, 222),
		Top = Color3.fromRGB(255, 58, 42),
		Legs = Color3.fromRGB(200, 200, 206),
	},
	Glow = Color3.fromRGB(255, 70, 50),
	CollisionSize = Vector3.new(4, 5.2, 4),
	Mass = 50,
	BaseMaxHealth = 450,
	BaseDamage = 0,
	BaseMovementSpeed = 0,
	Attacks = {},
	IntroRound = 15,
	SpawnWeight = 0,
	GoldDrop = 12,
}

return table.freeze(data)
