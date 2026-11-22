-- What a character's feet do to the floor, in the house look (VFX.md 30 and 35): a puff of the floor's dust and a
-- pixel of it on every footstep, dust thrown on the way the body was going when it turns hard, a square ring and dust
-- pushed out on a takeoff, and on a touchdown a square shock, dust rolling out all round, pixels thrown up and the
-- floor's own stud bricks knocked loose (Utils/thrownPieces).
-- FootstepsController says when and where. The look is on templates at ReplicatedStorage.Effects.StepFx, a place
-- instance, not Rojo, made by Assets/effects/steps (its README.md). No --!native: this is engine calls end to end.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local thrownPieces = require(script.Parent.thrownPieces)

local stepFx = {}

local KIT = "StepFx"
-- Which of a floor's colours each layer is drawn in; a layer not named keeps its template's.
local RECOLORED: { [string]: { [string]: string } } = table.freeze({
	Step = { Puffs = "Dust", Pixels = "Tint" },
	Skid = { Puffs = "Dust", Pixels = "Tint" },
	Jump = { Frame = "Hot", Puffs = "Dust", Pixels = "Tint" },
	Land = { Shock = "Hot", Echo = "Tint", Puffs = "Dust", Pixels = "Hot" },
})

local Tune = table.freeze({
	-- Footsteps a frame over every body, and takeoffs and touchdowns: past it the rest are not drawn this frame.
	STEPS_PER_FRAME = 6,
	BURSTS_PER_FRAME = 4,
	-- Nothing is drawn further than this from the camera: a footstep is a few pixels across long before a landing.
	STEP_RANGE = 80,
	BURST_RANGE = 160,
	-- Pieces in the air at once over every body. A landing throws fewer as this fills.
	PIECE_PARTS = 24,
	-- Copies of each template, taken in turn: a copy's new colour or size is also what still flies from its last
	-- throw.
	SLOTS = 6,
	-- Over the floor, so a flat ring never fights it for depth.
	LIFT = 0.06,
	-- A footstep's kick: this much up for one back along the floor.
	STEP_KICK_UP = 0.9,
	STEP_PUFFS = NumberRange.new(1, 2),
	STEP_PIXELS = NumberRange.new(0, 1),
	RUN_PUFFS = NumberRange.new(2, 3),
	RUN_PIXELS = NumberRange.new(1, 2),
	-- A hard turn at its sharpest (straight back); a gentler one throws SKID_LEAST of it. The dust leaves in a fan
	-- this wide (radians) about the way the body was going, from this far ahead of the feet.
	SKID_PUFFS = NumberRange.new(6, 8),
	SKID_PIXELS = NumberRange.new(6, 9),
	SKID_LEAST = 0.6,
	SKID_ARC = 1.3,
	SKID_AHEAD = 0.5,
	SKID_KICK_UP = 0.35,
	JUMP_PUFFS = NumberRange.new(5, 6),
	JUMP_PIXELS = NumberRange.new(4, 6),
	-- A touchdown at strength 0 (a jump on the flat); at 1 everything is this many times as large and as many.
	LAND_PUFFS = NumberRange.new(8, 10),
	LAND_PIXELS = NumberRange.new(9, 13),
	LAND_BRICKS = NumberRange.new(2, 3),
	LAND_HEAVY_SCALE = 1.5,
	LAND_HEAVY_BRICKS = 2.2,
	-- A layer is sized for a scale rounded to this, so the sequences are built a few times, not once a landing.
	SCALE_STEP = 0.25,
	-- Dust leaves the feet along the floor tilted up by this (the tangent of the angle), from this far out.
	DUST_TILT = 0.22,
	DUST_RING = 0.5,
	-- Bricks fly out along the floor at OUT and up at LIFT, studs a second, from this far out from the feet.
	BRICK_RING = 0.9,
	BRICK_OUT_MIN = 5,
	BRICK_OUT_MAX = 11,
	BRICK_LIFT_MIN = 13,
	BRICK_LIFT_MAX = 21,
	-- A ring or a touchdown's pixels are born white-hot for this share of their life, then the floor's colour.
	HOT = Color3.fromRGB(255, 248, 215),
	HOT_SHARE = 0.12,
	-- What glows is the floor's colour this far toward white, and its dust further: paint, not light.
	TINT_LIGHTEN = 0.2,
	DUST_LIGHTEN = 0.35,
})

-- One copy of a template under Workspace.Terrain, where an attachment's CFrame is its world CFrame: its emitters by
-- layer name, and the floor colour and scale it was last recoloured and sized for.
type TCopy = {
	Attachment: Attachment,
	Emitters: { [string]: ParticleEmitter },
	Color: number,
	Scale: number,
}

-- Copies of one template, taken in turn, made on first use. Sizes holds each layer's Size sequence per scale (the
-- template's are for scale 1).
type TPool = {
	Template: Attachment,
	Recolored: { [string]: string }?,
	Copies: { TCopy },
	Next: number,
	Sizes: { [number]: { [string]: NumberSequence } },
}

-- Skid is nil in a place whose templates were pasted before there was one: the rest still draws.
type TKit = { Bricks: { BasePart }, Step: TPool, Skid: TPool?, Jump: TPool, Land: TPool }

-- A floor's colours as emitters take them, by the name RECOLORED gives a layer.
type TColors = { [string]: ColorSequence }

local random = Random.new()
local pieces = thrownPieces.NewPool("StepPieces", Tune.PIECE_PARTS)
local kit: TKit? = nil
local hasWarned = false
local floorColors: { [number]: TColors } = {}
-- What the lobby's pieces land on: its map. The arena is thrownPieces' own default.
local lobbyParams: RaycastParams? = nil
-- Read once a frame (BeginFrame).
local cameraPosition = Vector3.zero
local stepsLeft = 0
local burstsLeft = 0

local function newPool(template: Instance?): TPool?
	if not template or not template:IsA("Attachment") then return nil end
	return { Template = template, Recolored = RECOLORED[template.Name], Copies = {}, Next = 1, Sizes = {} }
end

-- The kit's templates; nil (said once) while they are not in the place, when feet draw nothing. A miss is asked
-- again, so templates that reach the client late are still found.
local function kitOf(): TKit?
	if kit then return kit end

	local effects = ReplicatedStorage:FindFirstChild("Effects")
	local templates = if effects then effects:FindFirstChild(KIT) else nil
	local step = if templates then newPool(templates:FindFirstChild("Step")) else nil
	local jump = if templates then newPool(templates:FindFirstChild("Jump")) else nil
	local land = if templates then newPool(templates:FindFirstChild("Land")) else nil
	if not templates or not step or not jump or not land then
		if not hasWarned then
			hasWarned = true
			warn(`[stepFx] no ReplicatedStorage.Effects.{KIT}; footsteps, jumps and landings draw nothing`)
		end
		return nil
	end

	local bricks = {}
	local debris = templates:FindFirstChild("Debris")
	if debris then
		for _, child in debris:GetChildren() do
			if child:IsA("BasePart") then bricks[#bricks + 1] = child end
		end
	end

	local found =
		{ Bricks = bricks, Step = step, Skid = newPool(templates:FindFirstChild("Skid")), Jump = jump, Land = land }
	kit = found
	return found
end

-- The pool's next copy.
local function take(pool: TPool): TCopy
	local slot = pool.Next
	pool.Next = slot % Tune.SLOTS + 1
	local copy = pool.Copies[slot]
	if copy then return copy end

	local attachment = pool.Template:Clone()
	local emitters = {}
	for _, child in attachment:GetChildren() do
		if child:IsA("ParticleEmitter") then emitters[child.Name] = child end
	end
	attachment.Parent = Workspace.Terrain

	local made = { Attachment = attachment, Emitters = emitters, Color = -1, Scale = 1 }
	pool.Copies[slot] = made
	return made
end

-- `copy` in the colours of a floor of `color`. Kept by the colour's bytes: a Color3 is no table key (VFX.md 30).
local function colorFor(pool: TPool, copy: TCopy, color: Color3)
	local key = math.round(color.R * 255) * 65536 + math.round(color.G * 255) * 256 + math.round(color.B * 255)
	if copy.Color == key then return end
	copy.Color = key
	local recolored = pool.Recolored
	if not recolored then return end

	local colors = floorColors[key]
	if not colors then
		local white = Color3.new(1, 1, 1)
		local tint = color:Lerp(white, Tune.TINT_LIGHTEN)
		colors = {
			Dust = ColorSequence.new(color:Lerp(white, Tune.DUST_LIGHTEN)),
			Tint = ColorSequence.new(tint),
			Hot = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Tune.HOT),
				ColorSequenceKeypoint.new(Tune.HOT_SHARE, tint),
				ColorSequenceKeypoint.new(1, tint),
			}),
		}
		floorColors[key] = colors
	end

	for name, emitter in copy.Emitters do
		local which = recolored[name]
		if which then emitter.Color = colors[which] end
	end
end

-- Every layer of `copy` sized `scale` times its template's (rounded to SCALE_STEP), the sequences kept on the pool.
local function sizeFor(pool: TPool, copy: TCopy, scale: number): number
	local rounded = math.max(math.round(scale / Tune.SCALE_STEP), 1) * Tune.SCALE_STEP
	if copy.Scale == rounded then return rounded end
	copy.Scale = rounded

	local sizes = pool.Sizes[rounded]
	if not sizes then
		sizes = {}
		for _, emitter in pool.Template:GetChildren() do
			if not emitter:IsA("ParticleEmitter") then continue end
			local keypoints = emitter.Size.Keypoints
			local scaled = table.create(#keypoints)
			for i, key in keypoints do
				scaled[i] = NumberSequenceKeypoint.new(key.Time, key.Value * rounded, key.Envelope * rounded)
			end
			sizes[emitter.Name] = NumberSequence.new(scaled)
		end
		pool.Sizes[rounded] = sizes
	end

	for name, emitter in copy.Emitters do
		local size = sizes[name]
		if size then emitter.Size = size end
	end

	return rounded
end

-- A CFrame at `position` whose +Y, the way an emitter throws and the axis a flat ring lies across, is `up`.
local function facing(position: Vector3, up: Vector3): CFrame
	local side = if math.abs(up.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis
	return CFrame.fromMatrix(position, side:Cross(up).Unit, up)
end

local function roll(range: NumberRange, scale: number): number
	return math.round(random:NextNumber(range.Min, range.Max) * scale)
end

-- Two unit vectors along a floor whose normal is `normal`, square to each other.
local function floorAxes(normal: Vector3): (Vector3, Vector3)
	local side = if math.abs(normal.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis
	local across = side:Cross(normal).Unit
	return across, normal:Cross(across)
end

-- `count` puffs leaving `center` along the floor, evenly spaced over `arc` radians from `start` (measured from
-- `ahead` toward `side`, two unit vectors along the floor), each aimed by the attachment: an emitter's own spread
-- cannot be flattened onto a floor.
local function dustFan(
	copy: TCopy,
	center: Vector3,
	normal: Vector3,
	ahead: Vector3,
	side: Vector3,
	start: number,
	arc: number,
	count: number,
	radius: number
)
	local puffs = copy.Emitters.Puffs
	if not puffs or count <= 0 then return end

	local attachment = copy.Attachment
	local lean = normal * Tune.DUST_TILT
	for i = 1, count do
		local angle = start + (i - 0.5 + random:NextNumber(-0.3, 0.3)) / count * arc
		local out = ahead * math.cos(angle) + side * math.sin(angle)
		attachment.CFrame = facing(center + out * radius, (out + lean).Unit)
		puffs:Emit(1)
	end
end

-- Puffs all round `center`, from a random start.
local function dustRing(copy: TCopy, center: Vector3, normal: Vector3, count: number, radius: number)
	local across, along = floorAxes(normal)
	dustFan(copy, center, normal, across, along, random:NextNumber(0, math.pi * 2), math.pi * 2, count, radius)
end

local function emit(copy: TCopy, layer: string, count: number)
	local emitter = copy.Emitters[layer]
	if emitter and count > 0 then emitter:Emit(count) end
end

local function landParams(): RaycastParams?
	if Workspace:FindFirstChild("Arena") then return nil end
	if lobbyParams then return lobbyParams end
	local lobby = Workspace:FindFirstChild("Lobby")
	if not lobby then return nil end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { lobby }
	lobbyParams = params
	return params
end

-- A foot pushes off the floor (`color`, its normal `normal`) at `position`: its dust and a pixel of it, kicked along
-- `back` (flat, a unit vector or zero for a scuff on the spot). A run kicks up more.
function stepFx.Step(position: Vector3, normal: Vector3, color: Color3, back: Vector3, isRun: boolean)
	if stepsLeft <= 0 or (position - cameraPosition).Magnitude > Tune.STEP_RANGE then return end
	local found = kitOf()
	if not found then return end
	stepsLeft -= 1

	local pool = found.Step
	local copy = take(pool)
	colorFor(pool, copy, color)
	copy.Attachment.CFrame = facing(position + normal * Tune.LIFT, (normal * Tune.STEP_KICK_UP + back).Unit)
	emit(copy, "Puffs", roll(if isRun then Tune.RUN_PUFFS else Tune.STEP_PUFFS, 1))
	emit(copy, "Pixels", roll(if isRun then Tune.RUN_PIXELS else Tune.STEP_PIXELS, 1))
end

-- A body going `along` (flat, a unit vector) turns hard at `position`: the dust and pixels its feet tear off the
-- floor keep going the way it was, low, in a fan. `sharpness` is 0 for the gentlest turn that counts, 1 for straight
-- back.
function stepFx.Skid(position: Vector3, normal: Vector3, color: Color3, along: Vector3, sharpness: number)
	if burstsLeft <= 0 or (position - cameraPosition).Magnitude > Tune.BURST_RANGE then return end
	-- Along the floor, so on a slope the fan lies on it.
	local flat = along - normal * along:Dot(normal)
	if flat.Magnitude < 0.01 then return end
	local found = kitOf()
	local pool = if found then found.Skid else nil
	if not pool then return end
	burstsLeft -= 1

	local ahead = flat.Unit
	local copy = take(pool)
	local center = position + normal * Tune.LIFT + ahead * Tune.SKID_AHEAD
	local amount = Tune.SKID_LEAST + (1 - Tune.SKID_LEAST) * sharpness
	colorFor(pool, copy, color)
	dustFan(
		copy,
		center,
		normal,
		ahead,
		normal:Cross(ahead),
		-Tune.SKID_ARC / 2,
		Tune.SKID_ARC,
		roll(Tune.SKID_PUFFS, amount),
		0
	)
	copy.Attachment.CFrame = facing(center, (ahead + normal * Tune.SKID_KICK_UP).Unit)
	emit(copy, "Pixels", roll(Tune.SKID_PIXELS, amount))
end

-- A body leaves the floor at `position`: a square ring snapping open under it, dust pushed out all round, and pixels
-- pulled up after it.
function stepFx.Jump(position: Vector3, normal: Vector3, color: Color3)
	if burstsLeft <= 0 or (position - cameraPosition).Magnitude > Tune.BURST_RANGE then return end
	local found = kitOf()
	if not found then return end
	burstsLeft -= 1

	local pool = found.Jump
	local copy = take(pool)
	local center = position + normal * Tune.LIFT
	colorFor(pool, copy, color)
	dustRing(copy, center, normal, roll(Tune.JUMP_PUFFS, 1), Tune.DUST_RING)
	copy.Attachment.CFrame = facing(center, normal)
	emit(copy, "Frame", 1)
	emit(copy, "Pixels", roll(Tune.JUMP_PIXELS, 1))
end

-- A body comes down on the floor at `position`: a pool of light and a fat square shock under it, a wider ring after,
-- dust rolling out all round, pixels thrown up and the floor's stud bricks knocked loose. `strength` is how hard,
-- from 0 (a jump on the flat) to 1 (a long fall): everything grows and more is thrown.
function stepFx.Land(position: Vector3, normal: Vector3, color: Color3, strength: number)
	local distance = (position - cameraPosition).Magnitude
	if burstsLeft <= 0 or distance > Tune.BURST_RANGE then return end
	local found = kitOf()
	if not found then return end
	burstsLeft -= 1

	local pool = found.Land
	local copy = take(pool)
	local center = position + normal * Tune.LIFT
	colorFor(pool, copy, color)
	local scale = sizeFor(pool, copy, 1 + (Tune.LAND_HEAVY_SCALE - 1) * strength)
	dustRing(copy, center, normal, roll(Tune.LAND_PUFFS, scale), Tune.DUST_RING * scale)
	copy.Attachment.CFrame = facing(center, normal)
	emit(copy, "Wash", 1)
	emit(copy, "Shock", 1)
	emit(copy, "Echo", 1)
	emit(copy, "Pixels", roll(Tune.LAND_PIXELS, scale))

	local bricks = found.Bricks
	local wanted = roll(Tune.LAND_BRICKS, 1 + (Tune.LAND_HEAVY_BRICKS - 1) * strength)
	local count = thrownPieces.Allowed(pieces, wanted, distance)
	if count == 0 or #bricks == 0 then return end

	pieces.FloorParams = landParams()
	local across, along = floorAxes(normal)
	local turn = random:NextNumber(0, math.pi * 2)
	for i = 1, count do
		local angle = turn + (i + random:NextNumber(-0.3, 0.3)) / count * math.pi * 2
		local out = across * math.cos(angle) + along * math.sin(angle)
		local velocity = out * random:NextNumber(Tune.BRICK_OUT_MIN, Tune.BRICK_OUT_MAX)
			+ Vector3.new(0, random:NextNumber(Tune.BRICK_LIFT_MIN, Tune.BRICK_LIFT_MAX), 0)
		local brick = bricks[random:NextInteger(1, #bricks)]
		thrownPieces.Throw(pieces, brick, color, center + out * Tune.BRICK_RING, velocity, position.Y)
	end
end

-- At the top of the frame: the camera, this frame's budgets and the pieces in the air.
function stepFx.BeginFrame()
	cameraPosition = Workspace.CurrentCamera.CFrame.Position
	stepsLeft = Tune.STEPS_PER_FRAME
	burstsLeft = Tune.BURSTS_PER_FRAME
	thrownPieces.Step(pieces)
end

return stepFx
