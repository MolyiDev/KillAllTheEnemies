-- The starting class: no powers, so its power is gadgets. Decoy clumps the crowd, Foam Cannon locks it, Orbital Cannon
-- deletes it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EClassesIds = require(ReplicatedStorage.Types.Enums.Data.EClassesIds)
local TData = require(ReplicatedStorage.Types.TData)

local data: TData.TClass = {
	Id = EClassesIds.Human,
	Name = "Human",
	Abilities = {
		{
			Kind = "Decoy",
			Name = "Decoy",
			Cost = 40,
			Cooldown = 14,
			Range = 45,
			Radius = 32,
			Duration = 6,
			Blows = 12,
			FlightSeconds = 0.5,
			Damage = 60,
			BlastRadius = 12,
		},
		{
			Kind = "FoamCannon",
			Name = "Foam Cannon",
			Cost = 50,
			Cooldown = 11,
			Range = 30,
			Radius = 0,
			Duration = 4.5,
			AngleDeg = 60,
			DamageTaken = 1.6,
		},
	},
	Ultimate = {
		Kind = "OrbitalCannon",
		Name = "Orbital Cannon",
		ChargeKills = 80,
		Range = 140,
		Radius = 8,
		Duration = 6,
		TargetSeconds = 1,
		Speed = 16,
		TickSeconds = 0.2,
		BossShare = 0.012,
	},
}

return table.freeze(data)
