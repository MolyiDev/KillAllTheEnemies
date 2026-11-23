-- The lobby's shooting range, as both sides see it: the hall off the plaza (Workspace.Lobby.Map.Range), the box a
-- player is in it inside, the booths TRY takes a player to, and its dummies: one per Model under Range.Targets,
-- numbered by the number in their names, which is what lets the network name one with a byte. A dummy is a first-wave
-- monster's stand-in (its health, its sounds, its bursts in the dummy's own colours), swaying on its rail by the
-- server's clock so both sides have it in the same place, and down for a moment once killed.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local EEnemiesIds = require(ReplicatedStorage.Types.Enums.Data.EEnemiesIds)
local TData = require(ReplicatedStorage.Types.TData)

export type TDummy = {
	Index: number,
	Model: Model,
	-- Every part, its rest offset from Home, and whether it is the body (which falls) or the stand (which only sways).
	Parts: { BasePart },
	Offsets: { CFrame },
	IsBody: { boolean },
	-- On the stand's top, its -Z toward the firing line.
	Home: CFrame,
	SwayStuds: number,
	SwayPeriod: number,
	-- (chest height, height, half width) over the feet, as an enemy's (EnemiesCore.AimShape).
	Aim: vector,
}

local RangeCore = {}

-- The middle of the hall: the plaza is down its -X, the targets up its +X. The box takes in the entrance (x -5..40),
-- narrower than the hall past it; the walls keep players out of the rest.
local ORIGIN = CFrame.new(97.5, 0, 1)
local BOUNDS_MIN = Vector3.new(-102.5, -4, -45)
local BOUNDS_MAX = Vector3.new(102.5, 30, 45)
-- An enemy's chest share of its height (EnemiesCore's AIM_CHEST_FRACTION).
local AIM_CHEST_FRACTION = 0.65
local CORNERS = table.freeze({
	Vector3.new(-1, -1, -1),
	Vector3.new(-1, -1, 1),
	Vector3.new(-1, 1, -1),
	Vector3.new(-1, 1, 1),
	Vector3.new(1, -1, -1),
	Vector3.new(1, -1, 1),
	Vector3.new(1, 1, -1),
	Vector3.new(1, 1, 1),
})

-- The monster a dummy stands in for: a first wave's body takes as many shots here as in a match.
RangeCore.STAND_IN = DataCore.Enemies.ById[EEnemiesIds.Basic]
RangeCore.HEALTH = RangeCore.STAND_IN.BaseMaxHealth
-- A blow worth this many times a body's health bursts it (EnemiesService's OVERKILL_DAMAGE_RATIO).
RangeCore.OVERKILL_RATIO = 4

-- A killed dummy goes over in FALL, lies for HOLD and is back up after RISE; hits pass through it all that time.
RangeCore.FALL_SECONDS = 0.18
RangeCore.HOLD_SECONDS = 1.6
RangeCore.RISE_SECONDS = 0.45
RangeCore.DOWN_SECONDS = RangeCore.FALL_SECONDS + RangeCore.HOLD_SECONDS + RangeCore.RISE_SECONDS

-- Where TRY stands a player: a booth behind the counter (between its dividers), root height, facing the targets. The
-- two in the middle first: the first free one is taken.
RangeCore.BOOTHS = table.freeze({
	CFrame.lookAlong(Vector3.new(48.5, 3, -6.5), Vector3.xAxis),
	CFrame.lookAlong(Vector3.new(48.5, 3, 8.5), Vector3.xAxis),
	CFrame.lookAlong(Vector3.new(48.5, 3, -21.5), Vector3.xAxis),
	CFrame.lookAlong(Vector3.new(48.5, 3, 23.5), Vector3.xAxis),
})

-- The dummies on rails, by Model name: how far each side of home and seconds a full swing.
local SWAYS: { [string]: { Studs: number, Period: number } } = table.freeze({
	Target3 = { Studs = 5, Period = 3.2 },
	Target6 = { Studs = 5, Period = 4.4 },
	Target9 = { Studs = 4.5, Period = 2.8 },
	Target12 = { Studs = 5, Period = 5 },
})

local sightParams = RaycastParams.new()
sightParams.FilterType = Enum.RaycastFilterType.Include

local function findRange(): Instance?
	local lobby = Workspace:FindFirstChild("Lobby")
	local map = if lobby then lobby:FindFirstChild("Map") else nil
	return if map then map:FindFirstChild("Range") else nil
end

-- Whether `position` is in the range.
function RangeCore.IsInside(position: Vector3): boolean
	local at = ORIGIN:PointToObjectSpace(position)
	return at.X >= BOUNDS_MIN.X
		and at.X <= BOUNDS_MAX.X
		and at.Y >= BOUNDS_MIN.Y
		and at.Y <= BOUNDS_MAX.Y
		and at.Z >= BOUNDS_MIN.Z
		and at.Z <= BOUNDS_MAX.Z
end

-- What a shot in the range stops on (sightCast): the hall and its door, never a dummy, which is shot by its aim
-- shape. Nil until the hall is in the place.
function RangeCore.SightParams(): RaycastParams?
	local range = findRange()
	local hall = if range then range:FindFirstChild("Hall") else nil
	local door = if range then range:FindFirstChild("Door") else nil
	if not hall then return nil end
	sightParams.FilterDescendantsInstances = if door then { hall, door } else { hall }
	return sightParams
end

local function numberOf(model: Instance): number
	return tonumber(string.match(model.Name, "%d+")) or 0
end

local function measureAim(parts: { BasePart }, isBody: { boolean }, home: CFrame): vector
	local low = Vector3.one * math.huge
	local high = -low
	for index, part in parts do
		if not isBody[index] then continue end
		local half = part.Size / 2
		for _, corner in CORNERS do
			local point = home:PointToObjectSpace(part.CFrame * (half * corner))
			low = low:Min(point)
			high = high:Max(point)
		end
	end

	local height = high.Y
	return vector.create(height * AIM_CHEST_FRACTION, height, math.max(high.X - low.X, high.Z - low.Z) * 0.5)
end

-- The dummies, numbered, each at its rest pose: read before anything has moved them. Empty until the range is in the
-- place.
function RangeCore.GatherDummies(): { TDummy }
	local range = findRange()
	local holder = if range then range:FindFirstChild("Targets") else nil
	if not holder then return {} end

	local models = {}
	for _, child in holder:GetChildren() do
		if child:IsA("Model") and child:FindFirstChild("Stand") and child:FindFirstChild("Torso") then
			table.insert(models, child)
		end
	end
	table.sort(models, function(a: Model, b: Model): boolean
		return numberOf(a) < numberOf(b)
	end)

	local dummies = table.create(#models)
	for index, model in models do
		local stand = model:FindFirstChild("Stand") :: BasePart
		local torso = model:FindFirstChild("Torso") :: BasePart
		local feet = stand.Position + Vector3.new(0, stand.Size.Y / 2, 0)
		local facing = torso.CFrame.LookVector * Vector3.new(1, 0, 1)
		local home = CFrame.lookAt(feet, feet + facing)
		local sway = SWAYS[model.Name]
		local parts, offsets, isBody = {}, {}, {}
		for _, descendant in model:GetDescendants() do
			if not descendant:IsA("BasePart") then continue end
			table.insert(parts, descendant)
			table.insert(offsets, home:ToObjectSpace(descendant.CFrame))
			table.insert(isBody, descendant ~= stand)
		end

		dummies[index] = {
			Index = index,
			Model = model,
			Parts = parts,
			Offsets = offsets,
			IsBody = isBody,
			Home = home,
			SwayStuds = if sway then sway.Studs else 0,
			SwayPeriod = if sway then sway.Period else 1,
			Aim = measureAim(parts, isBody, home),
		}
	end

	return dummies
end

-- Where a dummy's feet are at `serverTime` (Workspace:GetServerTimeNow()), swayed along its rail.
function RangeCore.Feet(dummy: TDummy, serverTime: number): CFrame
	if dummy.SwayStuds == 0 then return dummy.Home end
	local swing = math.sin(serverTime * 2 * math.pi / dummy.SwayPeriod) * dummy.SwayStuds
	return dummy.Home * CFrame.new(swing, 0, 0)
end

-- The stand-in's data in the dummy's own colours, for its bursts and sounds (EnemyImpacts).
function RangeCore.LookOf(dummy: TDummy): TData.TEnemy
	local model = dummy.Model
	-- Every dummy has a Torso (GatherDummies); a missing head or leg wears the torso's colour.
	local torso = (model:FindFirstChild("Torso") :: BasePart).Color
	local head = model:FindFirstChild("Head") :: BasePart?
	local leg = model:FindFirstChild("Left Leg") :: BasePart?
	local look = table.clone(RangeCore.STAND_IN)
	look.Colors = {
		Skin = if head then head.Color else torso,
		Top = torso,
		Legs = if leg then leg.Color else torso,
	}
	return table.freeze(look)
end

return table.freeze(RangeCore)
