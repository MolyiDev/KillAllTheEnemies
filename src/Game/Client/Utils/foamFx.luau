-- The Foam Cannon as it is seen, in the house look (VFX.md 30 and 37): the spray leaving the nozzle in a few pulses,
-- the foam setting on each body it catches as cream stud blocks that push out of it and stay on it, and those
-- blocks cracking off when the body dies or the foam lets go (GlobalClient/Utils/thrownPieces).
-- AbilityController says when and steps it. The look is on templates at ReplicatedStorage.Effects.HumanFx, a place
-- instance, not Rojo, made by Assets/effects/abilities (its README.md). No --!native: this is engine calls end to end.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local motorParts = require(script.Parent.Parent.Parent.GlobalClient.Utils.motorParts)
local thrownPieces = require(script.Parent.Parent.Parent.GlobalClient.Utils.thrownPieces)
local burstLayers = require(script.Parent.burstLayers)
local TimeCore = require(ReplicatedStorage.Shared.Core.TimeCore)

local foamFx = {}

type TLayers = burstLayers.TLayers

local layersOf = burstLayers.Clone
local emit = burstLayers.Emit
local roll = burstLayers.Roll
local between = burstLayers.Between

local KIT = "HumanFx"

local Tune = table.freeze({
	-- The spray: this many pulses, this far apart, each thrown from this far ahead of the caster and this far up.
	PULSES = 4,
	PULSE_SECONDS = 0.08,
	NOZZLE_AHEAD = 2.2,
	NOZZLE_UP = 0.4,
	BLOBS = NumberRange.new(8, 11),
	PIXELS = NumberRange.new(5, 8),
	FLECKS = NumberRange.new(2, 4),
	-- Nothing is drawn on a body further than this from the camera.
	RANGE = 220,
	-- The blocks on a body: this many on one REFERENCE_HEIGHT tall, between these for any, standing this share of
	-- its half width out from its middle and up to this share of its height.
	BLOCKS = 4,
	BLOCKS_MIN = 2,
	BLOCKS_MAX = 6,
	REFERENCE_HEIGHT = 5,
	BLOCK_OUT = 0.9,
	BLOCK_TOP = 0.8,
	BLOCK_TILT = math.rad(16),
	-- A block pushes out of the body's middle to its place over this long, past it and back (the foam expanding),
	-- each starting this long after the one before.
	POP_SECONDS = 0.24,
	POP_STAGGER = 0.035,
	POP_OVERSHOOT = 2.2,
	-- Blocks standing on bodies at once. A body gets fewer as this fills.
	BLOCK_PARTS = 160,
	SET_PUFFS = NumberRange.new(3, 5),
	-- A body that dies throws its blocks hard, with a burst; foam that lets go drops them, with dust.
	BREAK_PIXELS = NumberRange.new(9, 13),
	BREAK_PUFFS = NumberRange.new(4, 6),
	SHATTER_OUT = NumberRange.new(9, 18),
	SHATTER_LIFT = NumberRange.new(10, 22),
	CRUMBLE_OUT = NumberRange.new(1, 5),
	CRUMBLE_LIFT = NumberRange.new(2, 6),
	CRUMBLE_PUFFS = NumberRange.new(2, 3),
	-- Blocks in the air at once.
	PIECE_PARTS = 72,
})

-- The kit's templates, each attachment cloned once under Workspace.Terrain (where an attachment's CFrame is its
-- world CFrame): it is moved to each burst and emits there.
type TKit = { Blocks: { BasePart }, Spray: TLayers, Set: TLayers, Break: TLayers }

-- A block on a body: where it stands in the body's ground frame, and the point on the body's middle it pushes out of.
type TBlock = { Mover: motorParts.TMover, Place: CFrame, Core: CFrame, Delay: number }

-- A foamed body: its ground CFrame as last given, when the foam set on it, and whether its blocks have yet to be
-- written at that CFrame.
type TEncased = { Blocks: { TBlock }, Ground: CFrame, Chest: number, SetAt: number, IsDirty: boolean }

type TSpray = { Root: BasePart, Direction: Vector3, Left: number, NextAt: number }

local random = Random.new()
local blockParts = motorParts.NewPool("FoamBlocks", Tune.BLOCK_PARTS)
local blocksOut = 0
local pieces = thrownPieces.NewPool("FoamPieces", Tune.PIECE_PARTS)
local kit: TKit? = nil
local hasWarned = false
local encased: { [number]: TEncased } = {}
local sprays: { TSpray } = {}

-- The kit's templates; nil (said once) while they are not in the place, when the foam draws nothing. A miss is asked
-- again, so templates that reach the client late are still found.
local function kitOf(): TKit?
	if kit then return kit end

	local effects = ReplicatedStorage:FindFirstChild("Effects")
	local templates = if effects then effects:FindFirstChild(KIT) else nil
	local spray = if templates then layersOf(templates:FindFirstChild("FoamSpray")) else nil
	local set = if templates then layersOf(templates:FindFirstChild("FoamSet")) else nil
	local broken = if templates then layersOf(templates:FindFirstChild("FoamBreak")) else nil
	if not templates or not spray or not set or not broken then
		if not hasWarned then
			hasWarned = true
			warn(`[foamFx] no ReplicatedStorage.Effects.{KIT}; the foam draws nothing`)
		end
		return nil
	end

	local blocks = {}
	local folder = templates:FindFirstChild("Foam")
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("BasePart") then blocks[#blocks + 1] = child end
		end
	end

	local found = { Blocks = blocks, Spray = spray, Set = set, Break = broken }
	kit = found
	return found
end

-- A frame at `position` with +Y along `up`.
local function facing(position: Vector3, up: Vector3): CFrame
	local side = if math.abs(up.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis
	return CFrame.fromMatrix(position, side:Cross(up).Unit, up)
end

local function isNear(position: Vector3): boolean
	return (Workspace.CurrentCamera.CFrame.Position - position).Magnitude <= Tune.RANGE
end

-- Sprays from `root` (the caster's) along `direction` across the floor: a few pulses, each from where the caster is
-- by then.
function foamFx.Spray(root: BasePart, direction: Vector3)
	if not kitOf() then return end
	sprays[#sprays + 1] = { Root = root, Direction = direction, Left = Tune.PULSES, NextAt = 0 }
end

-- The foam sets on a body: `key` names it (its instance id), `ground` is its feet's CFrame and `aim` its shape
-- (EnemiesCore.AimShape: chest height, height, half width). Blocks push out of it and stand on it until Shatter or
-- Crumble; Follow keeps them on it.
function foamFx.Encase(key: number, ground: CFrame, aim: vector)
	local found = kitOf()
	if not found or encased[key] or not isNear(ground.Position) then return end

	local set = found.Set
	set.Attachment.CFrame = CFrame.new(ground.Position + Vector3.new(0, aim.x, 0))
	emit(set, "Core", 1)
	emit(set, "Frame", 1)
	emit(set, "Puffs", roll(Tune.SET_PUFFS))

	-- Fewer as the pool fills, so a whole wave foamed keeps some on every body rather than all on the first.
	local wanted = math.clamp(math.round(Tune.BLOCKS * aim.y / Tune.REFERENCE_HEIGHT), Tune.BLOCKS_MIN, Tune.BLOCKS_MAX)
	local count = math.min(wanted, math.ceil(wanted * (Tune.BLOCK_PARTS - blocksOut) / Tune.BLOCK_PARTS))
	local templates = found.Blocks
	local blocks = table.create(count)
	local turn = random:NextNumber(0, math.pi * 2)
	for i = 1, if #templates > 0 then count else 0 do
		local mover = motorParts.Take(blockParts, templates[random:NextInteger(1, #templates)])
		if not mover then break end
		blocksOut += 1

		-- Round the body, evenly from a random start, one a slice of its height: it is covered, never stacked.
		local angle = turn + (i + random:NextNumber(-0.25, 0.25)) / count * math.pi * 2
		local height = (i - random:NextNumber(0.2, 0.8)) / count * aim.y * Tune.BLOCK_TOP
		local core = CFrame.new(0, height, 0) * CFrame.Angles(0, angle, 0)
		blocks[i] = {
			Mover = mover,
			Core = core,
			Place = core * CFrame.new(0, 0, -aim.z * Tune.BLOCK_OUT) * CFrame.Angles(
				random:NextNumber(-Tune.BLOCK_TILT, Tune.BLOCK_TILT),
				random:NextNumber(0, math.pi * 2),
				random:NextNumber(-Tune.BLOCK_TILT, Tune.BLOCK_TILT)
			),
			Delay = (i - 1) * Tune.POP_STAGGER,
		}
	end

	encased[key] = { Blocks = blocks, Ground = ground, Chest = aim.x, SetAt = TimeCore.GameClock, IsDirty = true }
end

-- The body's ground CFrame this frame: its blocks go with it when it is shoved.
function foamFx.Follow(key: number, ground: CFrame)
	local body = encased[key]
	if not body or body.Ground == ground then return end
	body.Ground = ground
	body.IsDirty = true
end

-- Takes the blocks off a body and throws each from where it stood, `out` from the body's middle and `lift` up.
local function throwOff(key: number, out: NumberRange, lift: NumberRange): TEncased?
	local body = encased[key]
	if not body then return nil end
	encased[key] = nil

	local ground = body.Ground
	local floor = ground.Position.Y
	for _, block in body.Blocks do
		local at = (ground * block.Place).Position
		local away = Vector3.new(at.X - ground.Position.X, 0, at.Z - ground.Position.Z)
		local velocity = (if away.Magnitude > 0.05 then away.Unit else Vector3.xAxis) * between(out)
			+ Vector3.new(0, between(lift), 0)
		local mover = block.Mover
		motorParts.Release(blockParts, mover)
		blocksOut -= 1
		thrownPieces.Throw(pieces, mover.Template, nil, at, velocity, floor)
	end

	return body
end

-- The body died in its foam: the blocks are thrown hard off it under a burst.
function foamFx.Shatter(key: number)
	local body = throwOff(key, Tune.SHATTER_OUT, Tune.SHATTER_LIFT)
	local found = kit
	if not body or not found then return end

	local broken = found.Break
	broken.Attachment.CFrame = CFrame.new(body.Ground.Position + Vector3.new(0, body.Chest, 0))
	emit(broken, "Core", 1)
	emit(broken, "Frame", 1)
	emit(broken, "Pixels", roll(Tune.BREAK_PIXELS))
	emit(broken, "Puffs", roll(Tune.BREAK_PUFFS))
end

-- The foam let go: the blocks drop off the body in a little dust.
function foamFx.Crumble(key: number)
	local body = throwOff(key, Tune.CRUMBLE_OUT, Tune.CRUMBLE_LIFT)
	local found = kit
	if not body or not found then return end

	local broken = found.Break
	broken.Attachment.CFrame = CFrame.new(body.Ground.Position + Vector3.new(0, body.Chest, 0))
	emit(broken, "Puffs", roll(Tune.CRUMBLE_PUFFS))
end

-- One pulse of a spray, from where its caster is now.
local function pulse(found: TKit, spray: TSpray)
	local direction = spray.Direction
	local nozzle = spray.Root.Position + direction * Tune.NOZZLE_AHEAD + Vector3.new(0, Tune.NOZZLE_UP, 0)
	local layers = found.Spray
	layers.Attachment.CFrame = facing(nozzle, direction)
	if spray.Left == Tune.PULSES then emit(layers, "Core", 1) end
	emit(layers, "Blobs", roll(Tune.BLOBS))
	emit(layers, "Pixels", roll(Tune.PIXELS))
	emit(layers, "Flecks", roll(Tune.FLECKS))
end

-- A block's place `elapsed` seconds after its body was foamed: at the body's middle, then out past its place and
-- back onto it.
local function popped(block: TBlock, elapsed: number): CFrame
	local t = math.clamp((elapsed - block.Delay) / Tune.POP_SECONDS, 0, 1)
	if t >= 1 then return block.Place end
	local u = t - 1
	local eased = 1 + (Tune.POP_OVERSHOOT + 1) * u * u * u + Tune.POP_OVERSHOOT * u * u
	return block.Core:Lerp(block.Place, eased)
end

-- Once a frame: the sprays' pulses, the blocks pushing out of fresh bodies and following shoved ones, and the blocks
-- in the air.
function foamFx.Step()
	thrownPieces.Step(pieces, TimeCore.TimeScale)
	local found = kit
	if not found then return end

	local now = TimeCore.GameClock
	for index = #sprays, 1, -1 do
		local spray = sprays[index]
		if now < spray.NextAt then continue end
		if spray.Root.Parent then pulse(found, spray) end
		spray.Left -= 1
		spray.NextAt = now + Tune.PULSE_SECONDS
		if spray.Left > 0 and spray.Root.Parent then continue end
		sprays[index] = sprays[#sprays]
		sprays[#sprays] = nil
	end

	for _, body in encased do
		local elapsed = now - body.SetAt
		local blocks = body.Blocks
		local isPopping = elapsed < Tune.POP_SECONDS + #blocks * Tune.POP_STAGGER
		if not isPopping and not body.IsDirty then continue end
		-- The frame the last block lands is written once more at rest, then never again until the body moves.
		body.IsDirty = isPopping
		local ground = body.Ground
		for _, block in blocks do
			block.Mover.Joint.Transform = ground * popped(block, elapsed)
		end
	end
end

return foamFx
