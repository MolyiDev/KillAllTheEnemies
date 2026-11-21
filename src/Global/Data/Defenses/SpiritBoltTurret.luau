local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EDefensesIds = require(ReplicatedStorage.Types.Enums.Data.EDefensesIds)
local TData = require(ReplicatedStorage.Types.TData)

-- GDD 15: an automatic projectile turret. Shoots the nearest enemy in range; Gold upgrades raise its damage.
local data: TData.TDefense = {
	Id = EDefensesIds.SpiritBoltTurret,
	Name = "Spirit Bolt Turret",
	Kind = "Turret",
	ModelName = "SpiritBoltTurret",
	Cost = 150,
	UpgradeCosts = { 120, 240, 480 },
	Footprint = Vector2.new(4, 4),
	MaxHealth = 200,
	MaxPerPlayer = 4,
	Range = 40,
	FireInterval = 0.5,
	Damage = 8,
	DamagePerLevel = 4,
}

return table.freeze(data)
