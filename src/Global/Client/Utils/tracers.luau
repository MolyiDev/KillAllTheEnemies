-- Bullet tracers and muzzle sparks: pooled neon parts flown along their line and moved together each frame with one
-- BulkMoveTo. Purely a picture: hits are the server's (WeaponService), and the enemy's flash and numbers come from its
-- damage events. Step is the owner's to call once a frame (WeaponController).
local Workspace = game:GetService("Workspace")
local EnemyImpacts = require(script.Parent.Parent.Parent.GlobalClient.Utils.enemyImpacts)

local PARK = CFrame.new(0, -10000, 0)
local MOVE_MODE = Enum.BulkMoveMode.FireCFrameChanged
-- Shown a frame ahead, so a point-blank shot still draws once before it lands.
local LEAD = 1 / 60
local TAU = math.pi * 2

local Tune = table.freeze({
	WIDTH = 0.5,
	SPEED = 600,
	LENGTH = 8,
	POOL = 48,
	LIMIT = 160,
	COLOR = Color3.fromRGB(255, 214, 20),
	SPARK_COUNT = 14,
	SPARK_SPREAD_DEG = 34,
	SPARK_SPEED_MIN = 30,
	SPARK_SPEED_MAX = 62,
	SPARK_LIFE_MIN = 0.1,
	SPARK_LIFE_MAX = 0.24,
	SPARK_THICKNESS = 0.18,
	SPARK_STRETCH = 0.045,
	SPARK_GRAVITY = 55,
	SPARK_POOL = 60,
	SPARK_LIMIT = 240,
	SPARK_COLOR = Color3.fromRGB(255, 175, 20),
	-- First person: the barrel sits a hand from the eye, so a full tracer would fill the screen. It starts this far
	-- out, thin, and the muzzle throws fewer, finer sparks.
	CLOSE_SKIP = 16,
	CLOSE_WIDTH = 0.08,
	CLOSE_SPARKS = 0,
	CLOSE_THICKNESS = 0.06,
})

type TShot = {
	Part: BasePart,
	From: Vector3,
	Unit: Vector3,
	Facing: CFrame,
	Length: number,
	Half: number,
	Born: number,
	-- A boss it goes into: its light there as the tip passes BossAlong studs down the line (EnemyImpacts.EmitBossHit),
	-- then nil.
	BossHit: EnemyImpacts.TBossHit?,
	BossAlong: number,
}

type TSpark = {
	Part: BasePart,
	Mesh: SpecialMesh,
	From: Vector3,
	Velocity: Vector3,
	Born: number,
	Life: number,
	Thickness: number,
}

local tracers = {}

local gravity = Vector3.new(0, -Tune.SPARK_GRAVITY, 0)
local random = Random.new()
local folder: Instance? = nil
local pool: { BasePart } = {}
local sparkPool: { BasePart } = {}
-- Each spark part's mesh: a spark is stretched every frame of its life, and a Part.Size write costs ~5x a
-- SpecialMesh.Scale write (performance/optimization-2026-11-26).
local sparkMeshes: { [BasePart]: SpecialMesh } = {}
local flying: { TShot } = {}
local sparking: { TSpark } = {}
local madeCount = 0
local sparksMadeCount = 0
-- BulkMoveTo's two lists, refilled every frame.
local movedParts: { BasePart } = {}
local movedFrames: { CFrame } = {}

local function newPart(name: string, color: Color3, size: Vector3): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Size = size
	part.CFrame = PARK
	part.Parent = folder
	return part
end

local function takeTracer(): BasePart?
	local free = table.remove(pool)
	if free then return free end
	if madeCount >= Tune.LIMIT then return nil end
	madeCount += 1
	return newPart("Tracer", Tune.COLOR, Vector3.new(Tune.WIDTH, Tune.WIDTH, Tune.LENGTH))
end

local function newSpark(): BasePart
	local part = newPart("Spark", Tune.SPARK_COLOR, Vector3.one)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Brick
	mesh.Parent = part
	sparkMeshes[part] = mesh
	return part
end

local function takeSpark(): BasePart?
	local free = table.remove(sparkPool)
	if free then return free end
	if sparksMadeCount >= Tune.SPARK_LIMIT then return nil end
	sparksMadeCount += 1
	return newSpark()
end

-- Builds the pools under `parent`. Once, before the first shot.
function tracers.Init(parent: Instance)
	folder = parent
	for _ = 1, Tune.POOL do
		madeCount += 1
		pool[#pool + 1] = newPart("Tracer", Tune.COLOR, Vector3.new(Tune.WIDTH, Tune.WIDTH, Tune.LENGTH))
	end

	for _ = 1, Tune.SPARK_POOL do
		sparksMadeCount += 1
		sparkPool[#sparkPool + 1] = newSpark()
	end
end

-- Tracers in flight now (the debug readout's).
function tracers.Flying(): number
	return #flying
end

-- A burst of sparks out of a muzzle facing along `muzzle`'s look.
function tracers.Sparks(muzzle: CFrame, isClose: boolean)
	local now = os.clock()
	local cone = math.rad(Tune.SPARK_SPREAD_DEG)
	local thickness = if isClose then Tune.CLOSE_THICKNESS else Tune.SPARK_THICKNESS
	for _ = 1, if isClose then Tune.CLOSE_SPARKS else Tune.SPARK_COUNT do
		local part = takeSpark()
		if not part then return end
		local aim = muzzle.Rotation
			* CFrame.Angles(0, 0, random:NextNumber(0, TAU))
			* CFrame.Angles(random:NextNumber(0, cone), 0, 0)
		sparking[#sparking + 1] = {
			Part = part,
			Mesh = sparkMeshes[part],
			From = muzzle.Position,
			Velocity = aim.LookVector * random:NextNumber(Tune.SPARK_SPEED_MIN, Tune.SPARK_SPEED_MAX),
			Born = now,
			Life = random:NextNumber(Tune.SPARK_LIFE_MIN, Tune.SPARK_LIFE_MAX),
			Thickness = thickness,
		}
	end
end

-- One tracer from `from` to `to`, going into a boss for `bossHit`. Past the pool's limit the shot draws nothing but
-- the boss's light.
function tracers.Fire(from: Vector3, to: Vector3, isClose: boolean, bossHit: EnemyImpacts.TBossHit?)
	local whole = to - from
	if isClose and whole.Magnitude > Tune.CLOSE_SKIP + 0.5 then
		from += whole.Unit * Tune.CLOSE_SKIP
	end

	local offset = to - from
	local length = offset.Magnitude
	if length < 0.5 then return end
	local part = takeTracer()
	if not part then
		if bossHit then EnemyImpacts.EmitBossHit(bossHit, -offset / length) end
		return
	end

	local unit = offset / length
	local size = math.min(Tune.LENGTH, length)
	local width = if isClose then Tune.CLOSE_WIDTH else Tune.WIDTH
	if part.Size.Z ~= size or part.Size.X ~= width then part.Size = Vector3.new(width, width, size) end
	flying[#flying + 1] = {
		Part = part,
		From = from,
		Unit = unit,
		Facing = CFrame.lookAt(Vector3.zero, unit),
		Length = length,
		Half = size / 2,
		Born = os.clock() - LEAD,
		BossHit = bossHit,
		-- Capped: a bullet stopping in the boss goes in where it ends, and rounding must not put that past the end.
		BossAlong = if bossHit then math.min((bossHit.At - from):Dot(unit), length) else 0,
	}
end

local function stepSparks(now: number, count: number): number
	for index = #sparking, 1, -1 do
		local spark = sparking[index]
		local age = now - spark.Born
		count += 1
		movedParts[count] = spark.Part
		if age >= spark.Life then
			movedFrames[count] = PARK
			sparkPool[#sparkPool + 1] = spark.Part
			sparking[index] = sparking[#sparking]
			sparking[#sparking] = nil
			continue
		end

		local velocity = spark.Velocity + gravity * age
		local at = spark.From + spark.Velocity * age + gravity * (age * age / 2)
		local left = 1 - age / spark.Life
		local thick = spark.Thickness * (0.4 + 0.6 * left)
		local long = math.max(thick, velocity.Magnitude * Tune.SPARK_STRETCH * left)
		spark.Mesh.Scale = Vector3.new(thick, thick, long)
		movedFrames[count] = CFrame.lookAt(at, at + velocity) * CFrame.new(0, 0, long / 2)
	end

	return count
end

function tracers.Step()
	if #flying == 0 and #sparking == 0 then return end
	local now = os.clock()
	local count = stepSparks(now, 0)

	for index = #flying, 1, -1 do
		local shot = flying[index]
		local tip = (now - shot.Born) * Tune.SPEED
		count += 1
		movedParts[count] = shot.Part
		local bossHit = shot.BossHit
		if bossHit and tip >= shot.BossAlong then
			shot.BossHit = nil
			EnemyImpacts.EmitBossHit(bossHit, -shot.Unit)
		end
		if tip >= shot.Length then
			movedFrames[count] = PARK
			pool[#pool + 1] = shot.Part
			flying[index] = flying[#flying]
			flying[#flying] = nil
			continue
		end

		movedFrames[count] = shot.Facing + (shot.From + shot.Unit * math.max(tip - shot.Half, shot.Half))
	end

	-- Trim what last frame left past this frame's count, so the two lists stay the same length.
	for i = count + 1, #movedParts do
		movedParts[i] = nil
		movedFrames[i] = nil
	end

	Workspace:BulkMoveTo(movedParts, movedFrames, MOVE_MODE)
end

return tracers
