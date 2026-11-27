-- What both sides agree on about classes and their abilities: which class a player has, which ability a slot is, its
-- level and what each level costs and sets, and the maths the server decides by and the caster's own client draws
-- ahead with. The profile keeps levels by class and ability Name (TProfile.AbilityLevels); the wire carries slots.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local LoadoutCore = require(ReplicatedStorage.GlobalShared.Core.LoadoutCore)
local EClassesIds = require(ReplicatedStorage.Types.Enums.Data.EClassesIds)
local TData = require(ReplicatedStorage.Types.TData)

local CLASSES = DataCore.Classes.ById

local AbilitiesCore = {}

-- The class every player has until they pick another.
AbilitiesCore.DEFAULT_CLASS = EClassesIds.Human
AbilitiesCore.MAX_LEVEL = 5

-- Each ability's copy at each level above the first, made on first ask.
local leveled: { [TData.TAbility]: { [number]: TData.TAbility } } = {}

-- The class `classId` names, or the default for an id with no class (a profile saved before classes: 0).
function AbilitiesCore.ClassOf(classId: number?): TData.TClass
	return CLASSES[classId or 0] or CLASSES[AbilitiesCore.DEFAULT_CLASS]
end

-- The ultimate's slot: the one after the abilities.
function AbilitiesCore.UltimateSlot(class: TData.TClass): number
	return #class.Abilities + 1
end

function AbilitiesCore.AbilityAt(class: TData.TClass, slot: number): TData.TAbility?
	if slot == #class.Abilities + 1 then return class.Ultimate end
	return class.Abilities[slot]
end

-- The profile's key for `ability`'s level.
function AbilitiesCore.LevelKey(class: TData.TClass, ability: TData.TAbility): string
	return `{class.Name}.{ability.Name}`
end

-- `ability`'s level. `levels` is the profile's AbilityLevels, nil until the first upgrade; an ability never upgraded
-- is not in it and is level 1.
function AbilitiesCore.LevelOf(levels: { [string]: number }?, class: TData.TClass, ability: TData.TAbility): number
	if not levels then return 1 end
	return levels[AbilitiesCore.LevelKey(class, ability)] or 1
end

-- Each slot's level, the ultimate last.
function AbilitiesCore.SlotLevels(levels: { [string]: number }?, class: TData.TClass): { number }
	local count = #class.Abilities + 1
	local slotLevels = table.create(count)
	for slot = 1, count do
		slotLevels[slot] = AbilitiesCore.LevelOf(levels, class, AbilitiesCore.AbilityAt(class, slot) :: TData.TAbility)
	end

	return slotLevels
end

-- Gems from `level` to the next one, nil at the top. A class has no price yet (Human is free), so its abilities are
-- priced as a starter gun.
function AbilitiesCore.UpgradeCost(level: number): number?
	if level >= AbilitiesCore.MAX_LEVEL then return nil end
	return LoadoutCore.LevelCost(0, level)
end

-- Run Gold `ability`'s next cast costs after `casts` paid ones this run, before Discount: each cast adds its step, and
-- each adds CostStepGrowth to the step (50, step 20, growth 5: 50, 70, 95, 125, 160).
function AbilitiesCore.CastCost(ability: TData.TAbility, casts: number): number
	local step = ability.CostStep or 0
	local growth = ability.CostStepGrowth or 0
	return (ability.Cost or 0) + casts * step + growth * casts * (casts - 1) / 2
end

-- `ability` as it is at `level`: every stat its levels up to that one set, over its own. Frozen and shared.
function AbilitiesCore.AtLevel(ability: TData.TAbility, level: number): TData.TAbility
	if level <= 1 then return ability end
	local byLevel = leveled[ability]
	if not byLevel then
		byLevel = {}
		leveled[ability] = byLevel
	end
	local cached = byLevel[level]
	if cached then return cached end

	local copy = table.clone(ability) :: any
	for index = 1, math.min(level - 1, #ability.Levels) do
		for _, step in ability.Levels[index] do
			copy[step.Stat] = step.Value
		end
	end

	local made: TData.TAbility = table.freeze(copy)
	byLevel[level] = made
	return made
end

-- `aim` brought within `range` flat studs of `origin`, at its own height.
function AbilitiesCore.ClampAim(origin: Vector3, aim: Vector3, range: number): Vector3
	local flat = Vector3.new(aim.X - origin.X, 0, aim.Z - origin.Z)
	local distance = flat.Magnitude
	if distance <= range then return aim end

	local reached = origin + flat * (range / distance)
	return Vector3.new(reached.X, aim.Y, reached.Z)
end

-- One step of a beam: from `position` toward `aim` across the floor, no faster than `speed`. It takes the
-- aim's height, since it stands on whatever floor is under it.
function AbilitiesCore.Chase(position: Vector3, aim: Vector3, speed: number, dt: number): Vector3
	local flat = Vector3.new(aim.X - position.X, 0, aim.Z - position.Z)
	local distance = flat.Magnitude
	local step = speed * dt
	if distance <= step then return aim end

	local reached = position + flat * (step / distance)
	return Vector3.new(reached.X, aim.Y, reached.Z)
end

return AbilitiesCore
