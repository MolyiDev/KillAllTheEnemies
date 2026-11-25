-- The floor broken up by a blow: stud chunks of it pushed up out of the ground, standing a while, then sinking
-- slowly back. Each stands nearly upright, its studded face turned to a point a third of its ring's radius over the
-- blow's middle (so it leans back off it), with a few smaller ones stuck on it. A crater is rings of them opening
-- outward with the blow's shock, the inner ring the biggest; a single slab is a crack's edge or a wave lifting the
-- floor as it passes. Pooled GlobalClient/Utils/motorParts, never simulated: Step writes each joint. An owner makes
-- its own pool, which is its cap, and steps it once a frame on its own clock.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local motorParts = require(script.Parent.motorParts)
local sightCast = require(ReplicatedStorage.GlobalShared.Utils.sightCast)

local brokenFloor = {}

local Tune = table.freeze({
	-- Up out of the floor this fast, past where it rests and back (a back-out ease, this much overshoot).
	RISE = 0.25,
	OVERSHOOT = 1.7,
	-- Back down into it this slowly, eased both ways. At rest its middle stands this share of its height over the
	-- floor, less BURY and LEAN_SINK of its depth (leaning back lifts its front foot by about that): most of it shows,
	-- its foot in the ground.
	SINK = 1.4,
	SHOW = 0.3,
	BURY = 0.3,
	LEAN_SINK = 0.2,
	-- A crater's rings open outward at this many studs a second, about as fast as its shock ring grows.
	RIPPLE = 70,
	-- Its rings: one every this many studs of its radius, at most RINGS_MAX, each this much smaller than the last.
	RING_EVERY = 7,
	RINGS_MAX = 3,
	RING_SHRINK = 0.15,
	-- How big its slabs are for its radius, and how many a ring for its radius. At a size of 1 each is WIDTH across,
	-- DEPTH deep and HEIGHT tall, each drawn on its own: many come out as deep as they are wide, which is what makes
	-- a ring read as thick rock and not a fence of plates.
	SIZE_RADIUS = 14,
	SIZE_MIN = 0.4,
	SIZE_MAX = 1.1,
	WIDTH = NumberRange.new(4, 8),
	DEPTH = NumberRange.new(3, 6),
	HEIGHT = NumberRange.new(3, 6),
	ROCKS_BASE = 6,
	ROCKS_PER_STUD = 0.85,
	-- Each slab's spot is jittered this many studs (times its size). Up to SUB_ROCKS smaller ones (SUB_* sized) are
	-- stuck on it, each off its middle by -1, 0 or 1 plus SUB_SHIFT studs (times its size) along each world axis,
	-- turned with it and rising and sinking with it: a clump, not a slab.
	IRREGULAR = 1,
	SUB_ROCKS = 3,
	SUB_WIDTH = NumberRange.new(3, 5),
	SUB_DEPTH = NumberRange.new(2, 4),
	SUB_HEIGHT = NumberRange.new(2, 3),
	SUB_SHIFT = 0.2,
	-- Turned this much off its face (degrees), and standing up to HOLD_JITTER seconds longer than asked.
	TURN_JITTER = 8,
	HOLD_JITTER = 0.8,
	-- Each slab's floor is looked for from this far over its spot to this far under it.
	FLOOR_LOOK_UP = 4,
	FLOOR_SEARCH = 14,
	STEP_MAX = 1 / 20,
})

type TSlab = {
	Mover: motorParts.TMover,
	-- Where it rests, and the way down out of sight from there (the floor's normal times its depth).
	Rest: CFrame,
	Down: Vector3,
	StartsAt: number,
	SinksAt: number,
	IsSettled: boolean,
}

export type TPool = {
	Parts: motorParts.TPool,
	Slabs: { TSlab },
	Limit: number,
	LastStep: number,
	-- The pool's own clock: real seconds, run at the scale each Step is given.
	Clock: number,
}

local random = Random.new()
-- Each template's size, read once: a property read is an engine call, and a crater asks for every slab.
local sizes: { [BasePart]: Vector3 } = {}
-- A clump's stuck-on pieces while it is laid out, reused.
local clumpTemplates: { BasePart } = {}
local clumpShifts: { Vector3 } = {}

-- A pool of at most `limit` slabs, their parts under a Folder `name` in Workspace.
function brokenFloor.NewPool(name: string, limit: number): TPool
	return { Parts = motorParts.NewPool(name, limit), Slabs = {}, Limit = limit, LastStep = os.clock(), Clock = 0 }
end

-- The floor under `at`: where and its normal, or nil.
local function floorAt(at: Vector3): (Vector3?, Vector3)
	local result =
		sightCast(at + Vector3.yAxis * Tune.FLOOR_LOOK_UP, -Vector3.yAxis * (Tune.FLOOR_LOOK_UP + Tune.FLOOR_SEARCH))
	if not result then return nil, Vector3.yAxis end
	return result.Position, result.Normal
end

local function sizeOf(template: BasePart): Vector3
	local size = sizes[template]
	if size then return size end
	size = template.Size
	sizes[template] = size
	return size
end

-- Where a piece of `size` rests on the floor under `at`, its studded top (+Y) turned to `facing` and its Z standing
-- up, and the floor's normal; nil over no floor.
local function restOn(at: Vector3, facing: Vector3, size: Vector3): (CFrame?, Vector3)
	local floor, normal = floorAt(at)
	if not floor or (facing - floor).Magnitude < 1e-3 then return nil, normal end
	local jitter = math.rad(Tune.TURN_JITTER)
	local turned = CFrame.lookAt(floor, facing)
		* CFrame.Angles(-math.pi / 2, 0, 0)
		* CFrame.Angles(
			random:NextNumber(-jitter, jitter),
			random:NextNumber(-jitter, jitter),
			random:NextNumber(-jitter, jitter)
		)

	return turned + normal * (size.Z * Tune.SHOW - size.Y * Tune.LEAN_SINK - Tune.BURY), normal
end

-- How far a piece of `size` sinks from its rest to be out of sight.
local function depthOf(size: Vector3): number
	return math.max(size.X, size.Y, size.Z) * (0.6 + Tune.SHOW) + Tune.BURY
end

-- A copy of `template` (in `color`) standing at `rest` from `startsAt` to `sinksAt` on the pool's clock, sinking
-- along `down`; false with no copy of it to spare.
local function stand(
	pool: TPool,
	template: BasePart,
	color: Color3,
	rest: CFrame,
	down: Vector3,
	startsAt: number,
	sinksAt: number
): boolean
	local mover = motorParts.Take(pool.Parts, template)
	if not mover then return false end
	mover.Part.Color = color

	local slabs = pool.Slabs
	slabs[#slabs + 1] =
		{ Mover = mover, Rest = rest, Down = down, StartsAt = startsAt, SinksAt = sinksAt, IsSettled = false }
	return true
end

-- Pushes a copy of `template` (in `color`) up out of the floor under `at` after `delay` seconds, its studded top (+Y)
-- turned to `facing` and its Z standing up, standing `hold` seconds. Nothing over no floor or with the pool out.
function brokenFloor.Push(
	pool: TPool,
	template: BasePart,
	color: Color3,
	at: Vector3,
	facing: Vector3,
	delay: number,
	hold: number
)
	local size = sizeOf(template)
	local rest, normal = restOn(at, facing, size)
	if not rest then return end

	local startsAt = pool.Clock + delay
	stand(pool, template, color, rest, normal * depthOf(size), startsAt, startsAt + Tune.RISE + hold)
end

-- The one of `templates` nearest `want` in size (X across, Y deep, Z tall).
local function nearest(templates: { BasePart }, want: Vector3): BasePart
	local best, bestOff = templates[1], math.huge
	for _, template in templates do
		local off = (sizeOf(template) - want).Magnitude
		if off < bestOff then
			best, bestOff = template, off
		end
	end
	return best
end

-- A size drawn from `width`, `depth` and `height` (each on its own), times `scale`.
local function drawSize(width: NumberRange, depth: NumberRange, height: NumberRange, scale: number): Vector3
	return Vector3.new(
		random:NextNumber(width.Min, width.Max),
		random:NextNumber(depth.Min, depth.Max),
		random:NextNumber(height.Min, height.Max)
	) * scale
end

-- A crater of rings of `templates` (narrowest first) round `center`, out to `radius`, in `color`, each ring rising as
-- the blow's shock passes it and standing about `hold` seconds.
function brokenFloor.Crater(
	pool: TPool,
	templates: { BasePart },
	center: Vector3,
	color: Color3,
	radius: number,
	hold: number
)
	if #templates == 0 then return end
	local rings = math.clamp(math.round(radius / Tune.RING_EVERY), 1, Tune.RINGS_MAX)
	local size = math.clamp(radius / Tune.SIZE_RADIUS, Tune.SIZE_MIN, Tune.SIZE_MAX)

	for ring = 1, rings do
		local ringRadius = radius * ring / rings
		local ringSize = size * (1 - Tune.RING_SHRINK * (ring - 1))
		local count = math.round(Tune.ROCKS_BASE + Tune.ROCKS_PER_STUD * ringRadius)
		local step = 2 * math.pi / count
		local offset = random:NextNumber(0, step)
		local facing = center + Vector3.yAxis * (ringRadius / 3)
		local delay = ringRadius / Tune.RIPPLE
		local irregular = Tune.IRREGULAR * ringSize
		for i = 1, count do
			if #pool.Slabs >= pool.Limit then return end
			local turn = offset + i * step
			local at = center
				+ Vector3.new(math.cos(turn), 0, math.sin(turn)) * ringRadius
				+ Vector3.new(random:NextNumber(-irregular, irregular), 0, random:NextNumber(-irregular, irregular))
			local template = nearest(templates, drawSize(Tune.WIDTH, Tune.DEPTH, Tune.HEIGHT, ringSize))
			local templateSize = sizeOf(template)
			local rest, normal = restOn(at, facing, templateSize)
			if not rest then continue end
			local depth = depthOf(templateSize)

			-- The clump sinks as one, so it sinks as deep as its highest piece needs.
			local pieces = random:NextInteger(0, Tune.SUB_ROCKS)
			for k = 1, pieces do
				local piece = nearest(templates, drawSize(Tune.SUB_WIDTH, Tune.SUB_DEPTH, Tune.SUB_HEIGHT, ringSize))
				local shift = Vector3.new(
					random:NextInteger(-1, 1) + Tune.SUB_SHIFT,
					random:NextInteger(-1, 1) + Tune.SUB_SHIFT,
					random:NextInteger(-1, 1) + Tune.SUB_SHIFT
				) * ringSize
				clumpTemplates[k] = piece
				clumpShifts[k] = shift
				depth = math.max(depth, depthOf(sizeOf(piece)) + math.max(0, shift:Dot(normal)))
			end

			local down = normal * depth
			local startsAt = pool.Clock + delay
			local sinksAt = startsAt + Tune.RISE + hold + random:NextNumber(0, Tune.HOLD_JITTER)
			-- A part pool caps its parts, not each template's: one template can be out while others are free.
			if not stand(pool, template, color, rest, down, startsAt, sinksAt) then continue end
			for k = 1, pieces do
				stand(pool, clumpTemplates[k], color, rest + clumpShifts[k], down, startsAt, sinksAt)
			end
		end
	end
end

local function overshoot(u: number): number
	local t = u - 1
	return 1 + (Tune.OVERSHOOT + 1) * t * t * t + Tune.OVERSHOOT * t * t
end

-- `timeScale` runs the slabs slower (a match's clock: 0 holds them where they are); nil is real time.
function brokenFloor.Step(pool: TPool, timeScale: number?)
	local realNow = os.clock()
	local dt = math.min(realNow - pool.LastStep, Tune.STEP_MAX) * (timeScale or 1)
	pool.LastStep = realNow
	pool.Clock += dt
	local now = pool.Clock
	local slabs = pool.Slabs
	if #slabs == 0 then return end

	for index = #slabs, 1, -1 do
		local slab = slabs[index]
		local age = now - slab.StartsAt
		if age < 0 then continue end
		local drop
		if age < Tune.RISE then
			drop = 1 - overshoot(age / Tune.RISE)
		elseif now < slab.SinksAt then
			if slab.IsSettled then continue end
			slab.IsSettled = true
			drop = 0
		else
			local u = (now - slab.SinksAt) / Tune.SINK
			if u >= 1 then
				motorParts.Release(pool.Parts, slab.Mover)
				slabs[index] = slabs[#slabs]
				slabs[#slabs] = nil
				continue
			end
			drop = (1 - math.cos(math.pi * u)) / 2
		end
		slab.Mover.Joint.Transform = slab.Rest - slab.Down * drop
	end
end

return brokenFloor
