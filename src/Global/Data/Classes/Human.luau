-- The starting class: no powers, so its power is gadgets. Decoy clumps the crowd, Foam Cannon locks it, Orbital Cannon
-- deletes it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EClassesIds = require(ReplicatedStorage.Types.Enums.Data.EClassesIds)
local TData = require(ReplicatedStorage.Types.TData)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local data: TData.TClass = {
	Id = EClassesIds.Human,
	Name = "Human",
	Rarity = "Common",
	Icon = EIcons.ClassHuman,
	Abilities = {
		{
			Kind = "Decoy",
			Name = "Decoy",
			Description = "Throw a blow-up copy of yourself. Nearby enemies swarm it, and it pops in their faces.",
			Cost = 40,
			Cooldown = 14,
			Range = 45,
			Radius = 32,
			Duration = 6,
			Blows = 12,
			FlightSeconds = 0.5,
			Damage = 60,
			BlastRadius = 12,
			Levels = {
				{ { Stat = "Damage", Label = "POP DAMAGE", Value = 90 } },
				{
					{ Stat = "Radius", Label = "LURE RANGE", Value = 40 },
					{ Stat = "Blows", Label = "BLOWS", Value = 18 },
				},
				{
					{ Stat = "Damage", Label = "POP DAMAGE", Value = 130 },
					{ Stat = "BlastRadius", Label = "BLAST SIZE", Value = 16 },
				},
				{ { Stat = "Cooldown", Label = "COOLDOWN", Value = 10 } },
			},
		},
		{
			Kind = "FoamCannon",
			Name = "Foam Cannon",
			Description = "Spray a cone of foam that locks enemies in place. Foamed enemies take more damage.",
			Cost = 50,
			Cooldown = 11,
			Range = 30,
			Radius = 0,
			Duration = 4.5,
			AngleDeg = 60,
			DamageTaken = 1.6,
			Levels = {
				{ { Stat = "Duration", Label = "HOLD", Value = 5.5 } },
				{
					{ Stat = "AngleDeg", Label = "SPRAY WIDTH", Value = 80 },
					{ Stat = "Range", Label = "RANGE", Value = 36 },
				},
				{ { Stat = "DamageTaken", Label = "EXTRA DAMAGE", Value = 1.8 } },
				{
					{ Stat = "Duration", Label = "HOLD", Value = 7 },
					{ Stat = "Cooldown", Label = "COOLDOWN", Value = 9 },
				},
			},
		},
	},
	Ultimate = {
		Kind = "OrbitalCannon",
		Name = "Orbital Cannon",
		Description = "Call down a beam from orbit. It burns through the crowd and hunts down bosses.",
		ChargeKills = 80,
		Range = 140,
		Radius = 8,
		Duration = 6,
		TargetSeconds = 1,
		Speed = 16,
		TickSeconds = 0.2,
		BossShare = 0.002,
		Levels = {
			{ { Stat = "Duration", Label = "LASTS", Value = 7.5 } },
			{ { Stat = "Radius", Label = "BEAM SIZE", Value = 10 } },
			{ { Stat = "ChargeKills", Label = "CHARGE", Value = 65 } },
			{
				{ Stat = "Duration", Label = "LASTS", Value = 9 },
				{ Stat = "BossShare", Label = "BOSS DAMAGE", Value = 0.003 },
			},
		},
	},
}

return table.freeze(data)
