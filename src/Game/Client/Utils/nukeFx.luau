-- NUKE ALL as it is seen, in the house look (VFX.md 30 and 36): where it is set off, a flash, a square shock, a
-- pillar of pixels and, a beat later, the head of the mushroom over it; then the blast's front rolling out along the
-- floor at the speed the server kills by, so the bodies come apart as it reaches them (their bursts are
-- Utils/enemyImpacts' overkill, off the kill events). The front is a ring of light and standing pixels that tears the
-- floor's own stud bricks loose (GlobalClient/Utils/thrownPieces).
-- ItemsController says when and steps it. The look is on templates at ReplicatedStorage.Effects.NukeFx, a place
-- instance, not Rojo, made by Assets/effects/items (its README.md). No --!native: this is engine calls end to end.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local sightCast = require(ReplicatedStorage.GlobalShared.Utils.sightCast)
local thrownPieces = require(script.Parent.Parent.Parent.GlobalClient.Utils.thrownPieces)
local fxBudget = require(script.Parent.Parent.Parent.GlobalClient.Utils.fxBudget)

local nukeFx = {}

local KIT = "NukeFx"

local Tune = table.freeze({
	-- Over the floor, so a flat ring never fights it for depth.
	LIFT = 0.08,
	-- How far under where it was set off (a character's root) the floor is looked for.
	FLOOR_SEARCH = 30,
	-- What the blast throws, a layer (an emitter has no burst count).
	PILLAR = NumberRange.new(44, 52),
	PIXELS = NumberRange.new(38, 46),
	FLECKS = NumberRange.new(18, 24),
	PUFFS = NumberRange.new(12, 15),
	-- The head of the mushroom: this far over the blast (where the pillar's fastest pixels stop), this long after it.
	CAP_HEIGHT = 30,
	CAP_SECONDS = 0.24,
	CAP_PIXELS = NumberRange.new(44, 52),
	CAP_PUFFS = NumberRange.new(11, 14),
	-- The light the blast throws on the world, a blink; only near the camera, where it is seen to land.
	LIGHT_COLOR = Color3.fromRGB(255, 214, 120),
	LIGHT_RANGE = 60,
	LIGHT_BRIGHTNESS = 8,
	LIGHT_SECONDS = 0.14,
	LIGHT_REACH = 160,
	-- The front, a frame: a point every FRONT_SPACING studs round it (between the two counts), each looked for on the
	-- floor from this far over the blast to this far down, none further than this from the camera.
	FRONT_SPACING = 16,
	FRONT_POINTS_MIN = 8,
	FRONT_POINTS_MAX = 22,
	FRONT_LOOK_UP = 14,
	FRONT_SEARCH = 44,
	FRONT_RANGE = 190,
	FRONT_FENCE = NumberRange.new(1, 2),
	FRONT_PUFF_CHANCE = 0.4,
	-- A point throws one of the floor's bricks this often, out along the front's way and up, studs a second.
	BRICK_CHANCE = 0.3,
	BRICK_OUT = NumberRange.new(4, 14),
	BRICK_LIFT = NumberRange.new(16, 30),
	BRICK_RISE = 0.6,
	-- Bricks in the air at once. A front throws fewer as this fills.
	PIECE_PARTS = 64,
})

type TLayers = { Attachment: Attachment, Emitters: { [string]: ParticleEmitter } }

-- The kit's templates, each cloned once under Workspace.Terrain (where an attachment's CFrame is its world CFrame):
-- one blast rolls at a time, and a second starts the first over.
type TKit = { Bricks: { BasePart }, Blast: TLayers, Cap: TLayers, Front: TLayers, Light: PointLight }

local random = Random.new()
local pieces = thrownPieces.NewPool("NukePieces", Tune.PIECE_PARTS)
pieces.Landed = thrownPieces.BrickLanded
local kit: TKit? = nil
local hasWarned = false
-- The blast rolling: the point on the floor it was set off at, the os.clock it started, its speed (studs a second),
-- how long it rolls, and how far it had reached on the last frame.
local frontOrigin: Vector3? = nil
local frontStartedAt = 0
local frontSpeed = 0
local frontSeconds = 0
local frontReach = 0
-- os.clock the mushroom's head goes off at and the light goes out at, or 0.
local capAt = 0
local lightOffAt = 0

local function layersOf(template: Instance?): TLayers?
	if not template or not template:IsA("Attachment") then return nil end
	local attachment = template:Clone()
	local emitters = {}
	for _, child in attachment:GetChildren() do
		if child:IsA("ParticleEmitter") then emitters[child.Name] = child end
	end

	attachment.Parent = Workspace.Terrain
	return { Attachment = attachment, Emitters = emitters }
end

-- The kit's templates; nil (said once) while they are not in the place, when the nuke draws nothing. A miss is asked
-- again, so templates that reach the client late are still found.
local function kitOf(): TKit?
	if kit then return kit end

	local effects = ReplicatedStorage:FindFirstChild("Effects")
	local templates = if effects then effects:FindFirstChild(KIT) else nil
	if
		not templates
		or not templates:FindFirstChild("Blast")
		or not templates:FindFirstChild("Cap")
		or not templates:FindFirstChild("Front")
	then
		if not hasWarned then
			hasWarned = true
			warn(`[nukeFx] no ReplicatedStorage.Effects.{KIT}; the nuke draws nothing`)
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

	local blast = layersOf(templates:FindFirstChild("Blast")) :: TLayers
	local light = Instance.new("PointLight")
	light.Name = "NukeFxLight"
	light.Color = Tune.LIGHT_COLOR
	light.Range = Tune.LIGHT_RANGE
	light.Brightness = Tune.LIGHT_BRIGHTNESS
	light.Shadows = false
	light.Enabled = false
	light.Parent = blast.Attachment

	local found = {
		Bricks = bricks,
		Blast = blast,
		Cap = layersOf(templates:FindFirstChild("Cap")) :: TLayers,
		Front = layersOf(templates:FindFirstChild("Front")) :: TLayers,
		Light = light,
	}
	kit = found
	return found
end

local function emit(layers: TLayers, layer: string, count: number)
	local emitter = layers.Emitters[layer]
	if emitter and count > 0 then fxBudget.Emit(emitter, count) end
end

local function roll(range: NumberRange): number
	return random:NextInteger(range.Min, range.Max)
end

-- The nuke goes off at `origin` (a point over the floor, the buyer's root): the blast there, and its front rolling out
-- from it at `speed` studs a second for `seconds`.
function nukeFx.Blast(origin: Vector3, speed: number, seconds: number)
	local found = kitOf()
	if not found then return end

	local floor = sightCast(origin, Vector3.new(0, -Tune.FLOOR_SEARCH, 0))
	local ground = if floor then floor.Position else origin
	local now = os.clock()
	local blast = found.Blast
	blast.Attachment.CFrame = CFrame.new(ground + Vector3.new(0, Tune.LIFT, 0))
	emit(blast, "Wash", 1)
	emit(blast, "Bloom", 1)
	emit(blast, "Core", 1)
	emit(blast, "Shock", 1)
	emit(blast, "Echo", 1)
	emit(blast, "Pillar", roll(Tune.PILLAR))
	emit(blast, "Pixels", roll(Tune.PIXELS))
	emit(blast, "Flecks", roll(Tune.FLECKS))
	emit(blast, "Puffs", roll(Tune.PUFFS))

	if (Workspace.CurrentCamera.CFrame.Position - ground).Magnitude <= Tune.LIGHT_REACH then
		found.Light.Enabled = true
		lightOffAt = now + Tune.LIGHT_SECONDS
	end

	found.Cap.Attachment.CFrame = CFrame.new(ground + Vector3.new(0, Tune.CAP_HEIGHT, 0))
	capAt = now + Tune.CAP_SECONDS
	frontOrigin = ground
	frontStartedAt = now
	frontSpeed = speed
	frontSeconds = seconds
	frontReach = 0
end

-- One frame of the front: points round the ring it crossed since the last frame, each put on the floor that is really
-- there (a point over a drop or past the map's edge draws nothing).
local function stepFront(found: TKit, origin: Vector3, now: number)
	local elapsed = now - frontStartedAt
	if elapsed >= frontSeconds then
		frontOrigin = nil
		return
	end

	local reach = elapsed * frontSpeed
	local last = frontReach
	frontReach = reach
	local count =
		math.clamp(math.round(reach * 2 * math.pi / Tune.FRONT_SPACING), Tune.FRONT_POINTS_MIN, Tune.FRONT_POINTS_MAX)
	local cameraPosition = Workspace.CurrentCamera.CFrame.Position
	local front = found.Front
	local attachment = front.Attachment
	-- Each is thrown at every point: found once a frame, not once a point.
	local emitters = front.Emitters
	local flash, fence, puffs = emitters.Flash, emitters.Fence, emitters.Puffs
	local fenceLeast, fenceMost = Tune.FRONT_FENCE.Min, Tune.FRONT_FENCE.Max
	local brickOut, brickLift = Tune.BRICK_OUT, Tune.BRICK_LIFT
	local outLeast, outMost, liftLeast, liftMost = brickOut.Min, brickOut.Max, brickLift.Min, brickLift.Max
	local rise = Vector3.new(0, Tune.BRICK_RISE, 0)
	local bricks = found.Bricks
	local turn = random:NextNumber(0, math.pi * 2)
	local over = Vector3.new(0, Tune.FRONT_LOOK_UP, 0)
	local down = Vector3.new(0, -Tune.FRONT_SEARCH, 0)
	local lift = Vector3.new(0, Tune.LIFT, 0)

	for i = 1, count do
		local angle = turn + (i + random:NextNumber(-0.4, 0.4)) / count * math.pi * 2
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local at = origin + out * random:NextNumber(last, reach)
		local distance = (at - cameraPosition).Magnitude
		if distance > Tune.FRONT_RANGE then continue end
		local floor = sightCast(at + over, down)
		if not floor then continue end

		local ground = floor.Position
		attachment.CFrame = CFrame.new(ground + lift)
		if flash then fxBudget.Emit(flash, 1, ground) end
		if fence then fxBudget.Emit(fence, random:NextInteger(fenceLeast, fenceMost), ground) end
		if puffs and random:NextNumber() < Tune.FRONT_PUFF_CHANCE then fxBudget.Emit(puffs, 1, ground) end

		if #bricks == 0 or random:NextNumber() > Tune.BRICK_CHANCE then continue end
		if thrownPieces.Allowed(pieces, 1, distance) == 0 then continue end
		local velocity = out * random:NextNumber(outLeast, outMost)
			+ Vector3.new(0, random:NextNumber(liftLeast, liftMost), 0)
		local brick = bricks[random:NextInteger(1, #bricks)]
		thrownPieces.Throw(pieces, brick, floor.Instance.Color, ground + rise, velocity, ground.Y)
	end
end

-- Once a frame: the mushroom's head when its beat comes, the light going out, the front, and the bricks in the air.
function nukeFx.Step()
	thrownPieces.Step(pieces)
	local found = kit
	if not found then return end

	local now = os.clock()
	if capAt > 0 and now >= capAt then
		capAt = 0
		local cap = found.Cap
		emit(cap, "Core", 1)
		emit(cap, "Halo", 1)
		emit(cap, "Pixels", roll(Tune.CAP_PIXELS))
		emit(cap, "Puffs", roll(Tune.CAP_PUFFS))
	end

	if lightOffAt > 0 and now >= lightOffAt then
		lightOffAt = 0
		found.Light.Enabled = false
	end

	local origin = frontOrigin
	if origin then stepFront(found, origin, now) end
end

return nukeFx
