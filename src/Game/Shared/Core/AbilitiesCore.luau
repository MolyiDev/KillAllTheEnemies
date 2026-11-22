-- What both sides agree on about classes and their abilities: which class a player has, which ability a slot is, and
-- the maths the server decides by and the caster's own client draws ahead with.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local EClassesIds = require(ReplicatedStorage.Types.Enums.Data.EClassesIds)
local TData = require(ReplicatedStorage.Types.TData)

local CLASSES = DataCore.Classes.ById

local AbilitiesCore = {}

-- The class every player has until they pick another.
AbilitiesCore.DEFAULT_CLASS = EClassesIds.Human

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
