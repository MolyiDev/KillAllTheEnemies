-- The Skeleton T-Rex as it is seen, in the house look (VFX.md 30 and 40): the weight of every foot, its bite, its tail,
-- its charge, its spines, its dive, its roar, its shield and guards, and its fall. Its light is a toxic green born
-- white-hot; what comes off the floor is the floor (dust, stud bricks thrown and slabs of it pushed up, in what lies
-- there); what comes off its body is bone. BossController and BossIntroController say when and where (bones, floors,
-- directions) and step it once a frame; the camera's shake stays theirs.
-- The look is on templates at ReplicatedStorage.Effects.TRexFx, a place instance, not Rojo, made by
-- Assets/effects/trex (its README.md). No --!native: this is engine calls end to end.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local brokenFloor = require(script.Parent.Parent.Parent.GlobalClient.Utils.brokenFloor)
local motorParts = require(script.Parent.Parent.Parent.GlobalClient.Utils.motorParts)
local thrownPieces = require(script.Parent.Parent.Parent.GlobalClient.Utils.thrownPieces)
local burstLayers = require(script.Parent.burstLayers)
local sightCast = require(ReplicatedStorage.GlobalShared.Utils.sightCast)
local fxBudget = require(script.Parent.Parent.Parent.GlobalClient.Utils.fxBudget)

local trexFx = {}

type TLayers = burstLayers.TLayers

local emit = burstLayers.Emit
local roll = burstLayers.Roll
local between = burstLayers.Between

local KIT = "TRexFx"
local UP = Vector3.yAxis
local WHITE = Color3.new(1, 1, 1)
-- The templates a kit is complete with; one missing is the kit not in the place.
local LAYERS = {
	"Step",
	"Stomp",
	"Front",
	"Scrape",
	"Bite",
	"BiteFloor",
	"Tail",
	"TailFloor",
	"Snort",
	"Launch",
	"SpineTrail",
	"SpineLand",
	"Sink",
	"Crack",
	"Rise",
	"Rattle",
	"Roar",
	"RoarFloor",
	"ShieldUp",
	"ShieldHit",
	"ShieldRim",
	"ShieldBreak",
	"Beam",
	"Snap",
	"Fall",
	"Soul",
}
-- The intro's hunt, drawn when the place has them: templates pasted before them still draw the fight.
local HUNT_LAYERS = { "Glare", "Glint", "Click", "Shake", "Inhale", "InhaleFloor" }
-- Layers recoloured per throw to the floor under them: the colour each is pulled toward, and how far. Dust goes to an
-- earth midtone, so it reads darker on sand and paler on grass (pulled toward white it vanished on sand); pixels are
-- light, a little paler than the floor.
local EARTH = Color3.fromRGB(150, 135, 115)
local FLOOR_LAYERS = {
	Dust = { To = EARTH, Share = 0.35 },
	FloorPixels = { To = WHITE, Share = 0.2 },
	Pixels = { To = WHITE, Share = 0.2 },
}
-- Of those, the ones a template has whose `Pixels` is its own green, not the floor's.
local OWN_PIXELS = { Stomp = true, Launch = true, Bite = true, Rise = true, Rattle = true, Fall = true, Snap = true }

local Tune = table.freeze({
	-- Past this from the camera nothing is thrown; the body itself is still drawn.
	RANGE = 300,
	-- The floor under a point is looked for from this far over it to this far under.
	FLOOR_LOOK_UP = 6,
	FLOOR_SEARCH = 40,
	LIFT = 0.1,
	-- A footfall: walking, and at a run (strength 1.5). Everything scales with strength.
	STEP_DUST = NumberRange.new(7, 9),
	STEP_PIXELS = NumberRange.new(3, 5),
	STEP_BRICKS = NumberRange.new(0, 2),
	-- A stamp at size 1 (the Stomp); bigger or smaller (a Quake's beats) throws that many times as much.
	STOMP_PILLAR = NumberRange.new(14, 18),
	STOMP_PIXELS = NumberRange.new(22, 28),
	STOMP_FLECKS = NumberRange.new(10, 14),
	STOMP_DUST = NumberRange.new(12, 15),
	STOMP_FLOOR_PIXELS = NumberRange.new(12, 16),
	STOMP_BRICKS = NumberRange.new(8, 11),
	-- The reach its template is baked to (the Stomp's circle), its crater out to this share of it, standing this long;
	-- a stamp this big or more blinks the screen.
	STOMP_RADIUS = 13.75,
	STOMP_CRATER = 0.7,
	STOMP_CRATER_HOLD = 2.2,
	STOMP_BLINK = 1.3,
	-- A wave rolling out: points a second on its front (a ray each, at most FRONT_RAYS a frame).
	FRONT_RATE = 90,
	FRONT_RAYS = 14,
	FRONT_BRICK_CHANCE = 0.3,
	FRONT_DUST_CHANCE = 0.6,
	-- A slab of floor lifted where it passes, at this chance a point (times its strength), facing its middle.
	FRONT_SLAB_CHANCE = 0.3,
	FRONT_SLAB_HOLD = 0.3,
	-- The bite and what it throws.
	BITE_SPRAY = NumberRange.new(18, 24),
	BITE_FLECKS = NumberRange.new(10, 14),
	BITE_DUST = NumberRange.new(9, 12),
	BITE_BRICKS = NumberRange.new(4, 6),
	BITE_CRATER = 5,
	-- The maw: its jaws hinged this far behind where it bites (half the template's MAW_LENGTH, so the bite is the
	-- middle of the U), this far apart at the hinge. It fades in over IN, opens to ANGLE (the lower jaw LOWER of
	-- it), the last SNAP share of its MAW_OPEN seconds the snap shut, drawn back LUNGE studs and thrown forward with
	-- it; then bitten PAST degrees through, chewed back, and after LET_GO it lets go RELEASE degrees a second as it
	-- fades over FADE. White-hot for FLASH seconds as it shuts.
	MAW_HINGE_BACK = 4.5,
	MAW_HINGE_GAP = 0.25,
	MAW_IN = 0.06,
	MAW_OPEN = 0.32,
	MAW_ANGLE = 44,
	MAW_LOWER = 0.6,
	MAW_SNAP = 0.3,
	MAW_LUNGE = 2.5,
	MAW_PAST = 5,
	MAW_LET_GO = 0.12,
	MAW_RELEASE = 40,
	MAW_FADE = 0.3,
	MAW_FLASH = 0.07,
	MAW_GREEN = Color3.fromRGB(60, 230, 100),
	MAW_HOT = Color3.fromRGB(240, 255, 232),
	-- The tail: thrown a second while it sweeps, and dust under the tip when it is this near the floor.
	TAIL_TRAIL_RATE = 140,
	TAIL_FLECKS_RATE = 40,
	TAIL_DUST_RATE = 34,
	TAIL_FLOOR = 7,
	-- A scrape, and a snort.
	SCRAPE_DUST = NumberRange.new(4, 6),
	SCRAPE_PIXELS = NumberRange.new(4, 7),
	SCRAPE_SPARKS = NumberRange.new(3, 5),
	SCRAPE_BRICKS = NumberRange.new(0, 2),
	SNORT_BREATH = NumberRange.new(5, 7),
	SNORT_PIXELS = NumberRange.new(5, 8),
	-- A volley's launch off its back, and a spine.
	LAUNCH_PIXELS = NumberRange.new(14, 18),
	LAUNCH_BONE = NumberRange.new(6, 9),
	SPINES = 24,
	SPINE_ARC = 14,
	-- It rolls about its length as it flies, then quivers where it sticks.
	SPINE_ROLL = 14,
	SPINE_QUIVER = 0.3,
	SPINE_QUIVER_RATE = 55,
	SPINE_QUIVER_DECAY = 11,
	SPINE_STUCK = 0.7,
	SPINE_SINK = 6.5,
	-- Its boss killed while it flies: it fades out on its way over this long, never landing.
	SPINE_LET_GO = 0.3,
	SPINE_CRATER = 3.4,
	SPINE_CRATER_HOLD = 1.2,
	SPINE_PIXELS = NumberRange.new(12, 16),
	SPINE_DUST = NumberRange.new(6, 8),
	SPINE_FLOOR_PIXELS = NumberRange.new(6, 9),
	SPINE_BRICKS = NumberRange.new(2, 3),
	-- The dive.
	SINK_WELL = NumberRange.new(16, 22),
	SINK_DUST = NumberRange.new(10, 13),
	SINK_FLOOR_PIXELS = NumberRange.new(10, 14),
	SINK_BRICKS = NumberRange.new(6, 9),
	CRACK_RISE = NumberRange.new(2, 4),
	CRACK_BRICK_CHANCE = 0.35,
	-- Each step of the crack pushes a slab up either side of it (at this chance), this far out, facing it.
	CRACK_SLAB_CHANCE = 0.75,
	CRACK_SLAB_OUT = 1.3,
	CRACK_SLAB_HOLD = 1.2,
	-- The crack's head shouldering through the floor: green welling and dust, stud bricks thrown up and aside like a
	-- bow wave (out this share along its way), a slab shoved up just ahead of it, and its light riding along.
	BURROW_WELL = NumberRange.new(3, 5),
	BURROW_DUST = NumberRange.new(2, 3),
	BURROW_BRICKS = NumberRange.new(1, 3),
	BURROW_FORWARD = NumberRange.new(0.2, 0.9),
	BURROW_OUT = NumberRange.new(6, 14),
	BURROW_LIFT = NumberRange.new(14, 26),
	BURROW_AHEAD = 1.6,
	BURROW_SLAB_HOLD = 0.5,
	BURROW_LIGHT = 2.2,
	BURROW_LIGHT_RANGE = 16,
	BURROW_LIGHT_SECONDS = 0.3,
	-- Craters: as it sinks (times each heave's size), where it bursts out.
	SINK_CRATER = 10,
	SINK_CRATER_HOLD = 1.2,
	RISE_CRATER = 15,
	RISE_CRATER_HOLD = 3,
	-- A foot landing this hard (running, catching itself) breaks a little of the floor round it.
	CATCH_STRENGTH = 1.3,
	CATCH_CRATER = 4.5,
	CATCH_CRATER_HOLD = 1.2,
	RISE_PILLAR = NumberRange.new(40, 48),
	RISE_PIXELS = NumberRange.new(34, 42),
	RISE_FLECKS = NumberRange.new(16, 22),
	RISE_BONE = NumberRange.new(14, 18),
	RISE_DUST = NumberRange.new(16, 20),
	RISE_FLOOR_PIXELS = NumberRange.new(18, 24),
	RISE_BRICKS = NumberRange.new(16, 20),
	RISE_BONES = NumberRange.new(6, 8),
	RATTLE_BONE = NumberRange.new(10, 14),
	RATTLE_PIXELS = NumberRange.new(8, 12),
	-- The roar: a ring of its sound every this often, breath and steam a second.
	ROAR_WAVE_SECONDS = 0.13,
	ROAR_BREATH_RATE = 120,
	ROAR_FLECKS_RATE = 40,
	ROAR_STEAM_RATE = 20,
	ROAR_DUST = NumberRange.new(16, 20),
	-- The shield: motes a second round its foot, a glint this often, a burst as it rises and as it breaks.
	RIM_RATE = 26,
	RIM_GLINT_SECONDS = 0.35,
	SHIELD_UP_PIXELS = NumberRange.new(30, 36),
	SHIELD_HIT_PIXELS = NumberRange.new(5, 8),
	BREAK_PIXELS = NumberRange.new(44, 52),
	BREAK_FLECKS = NumberRange.new(20, 26),
	BREAK_SHARDS = NumberRange.new(22, 28),
	-- A beam's motes a second, flowing from the guard to the boss at this many lengths a second.
	BEAM_RATE = 34,
	BEAM_FLOW = 1.6,
	SNAP_PIXELS = NumberRange.new(14, 18),
	SNAP_BONE = NumberRange.new(8, 10),
	SNAP_BONES = NumberRange.new(3, 4),
	-- The fall.
	FALL_PILLAR = NumberRange.new(36, 44),
	FALL_PIXELS = NumberRange.new(36, 44),
	FALL_FLECKS = NumberRange.new(18, 24),
	FALL_BONE = NumberRange.new(20, 26),
	FALL_DUST = NumberRange.new(20, 24),
	FALL_FLOOR_PIXELS = NumberRange.new(20, 26),
	FALL_BRICKS = NumberRange.new(16, 20),
	FALL_BONES = NumberRange.new(18, 22),
	SOUL_RATE = 22,
	SOUL_GLINT_SECONDS = 0.5,
	-- The hunt. A socket's light and pupil at a glare of 1 (their Brightness), easing out over GLARE_OUT once let go;
	-- its streak a pixel every TRAIL_SPACING studs the socket moves at 1 (sparser as it dims), at most TRAIL_MAX a
	-- frame; embers a second.
	GLARE_GLOW = 1.6,
	GLARE_PUPIL = 1.8,
	GLARE_OUT = 0.25,
	TRAIL_SPACING = 0.3,
	TRAIL_MAX = 16,
	EMBER_RATE = 16,
	GLINT_PIXELS = NumberRange.new(6, 9),
	CLICK_BONE = NumberRange.new(3, 5),
	-- A shake at size 1 (the whip), at each point along the neck, thrown from this far out of it toward the swing and
	-- up (from the bone's middle it is hidden in the bone): dust, flecks and stud bricks the colour of its bones (the
	-- kit's BONE) flung on along the swing, falling.
	SHAKE_OUT_OF = 1.2,
	SHAKE_DUST = NumberRange.new(5, 7),
	SHAKE_BONE = NumberRange.new(6, 9),
	SHAKE_BRICKS = NumberRange.new(1, 3),
	SHAKE_OUT = NumberRange.new(8, 18),
	SHAKE_LIFT = NumberRange.new(4, 12),
	BONE = Color3.fromRGB(232, 212, 172),
	-- The breath in: each layer a second, drawn from this far round the jaws (ahead of them, or the dust and pixels
	-- off the floor at FLOOR_SHARE), never from nearer the camera than CLEAR of the jaws' own distance, so nothing
	-- flies through the lens; aimed where the jaws will be, led by this share of their movement over a flight, and none
	-- set off later than this share of a flight before the breath ends, so nothing is left hanging when the jaws move
	-- on. The floor's rings at these shares of its seconds.
	INHALE_RATES = table.freeze({ Dust = 45, Pixels = 70, Air = 30, Mote = 45 }),
	INHALE_REACH = NumberRange.new(6, 12),
	INHALE_AHEAD = 0.6,
	INHALE_FLOOR_SHARE = 0.4,
	INHALE_CLEAR = 0.85,
	INHALE_LEAD = 0.7,
	INHALE_LAST = 0.6,
	INHALE_RINGS = table.freeze({ 0, 0.4 }),
	-- Pieces in the air at once, and how they fly: floor bricks low and out, bones higher. Slabs of floor standing at
	-- once.
	PIECES = 96,
	SLABS = 320,
	SLAB_RANGE = 160,
	BRICK_OUT = NumberRange.new(8, 20),
	BRICK_LIFT = NumberRange.new(16, 32),
	BONE_OUT = NumberRange.new(10, 26),
	BONE_LIFT = NumberRange.new(24, 46),
	-- The light it throws on the world, flashed at a big moment and gone in its seconds, eased out.
	LIGHT_COLOR = Color3.fromRGB(140, 255, 120),
	LIGHT_REACH = 200,
	-- The view washed green-white for a blink at its biggest moments, in full this near, nothing past FAR.
	SCREEN_TINT = Color3.fromRGB(225, 255, 215),
	SCREEN_NEAR = 30,
	SCREEN_FAR = 120,
})

-- How long before a bite its maw has to be said (Maw), so it snaps shut on the bite.
trexFx.MawOpenSeconds = Tune.MAW_OPEN

-- A wave rolling out along the floor.
-- HasPassed once its front has gone under the body Update is told of.
type TWave = {
	Center: Vector3,
	Radius: number,
	Max: number,
	Speed: number,
	Owed: number,
	Strength: number,
	HasPassed: boolean,
}
-- An emitter riding something for a while: `Where` says where (and which way) every frame, nil when it is gone.
type TRide = {
	Layers: TLayers,
	Where: () -> (Vector3?, Vector3?),
	Rates: { [string]: number },
	Owed: { [string]: number },
	EndsAt: number,
	Floor: TLayers?,
	FloorRate: number,
}
type TSpine = {
	-- One mover a piece of the Spine template, in its order.
	Movers: { motorParts.TMover },
	From: Vector3,
	To: Vector3,
	LaunchedAt: number,
	Flight: number,
	-- 0 in the air; the clock it landed at once stuck in the floor.
	LandedAt: number,
	-- The clock its boss died at while it flew (trexFx.LetGo).
	LetGoAt: number?,
	Stuck: CFrame,
	Roll: number,
}
-- The maw: where it bites and the way it bites, when it opened, and the colour and see-through its parts were last
-- given (written only when they change), and the clock its boss died at, if it did before it faded (trexFx.LetGo).
type TMaw = {
	At: Vector3,
	Forward: Vector3,
	OpenedAt: number,
	Color: Color3?,
	Transparency: number,
	LetGoAt: number?,
}
-- Its eye sockets burning: `Eyes` says where both are and how bright every frame until it lets go; each socket's last
-- place and what is owed of its streak.
type TGlare = {
	Eyes: () -> (Vector3?, Vector3?, number),
	IsLetGo: boolean,
	Strength: number,
	Was: { Vector3 },
	TrailOwed: { number },
	EmberOwed: number,
}
-- A breath in: `Mouth` says where the jaws are and which way they face; the floor under them and its colour.
type TInhale = {
	Mouth: () -> (Vector3?, Vector3?),
	StartedAt: number,
	Seconds: number,
	Floor: Vector3?,
	Was: Vector3?,
	Owed: { [string]: number },
	Rings: number,
}

local random = Random.new()
local pieces = thrownPieces.NewPool("TRexPieces", Tune.PIECES)
pieces.Landed = thrownPieces.BrickLanded
-- A spine is five parts (the Spine template's pyramid of four and its root).
local spineParts = motorParts.NewPool("TRexSpines", Tune.SPINES * 5)
local slabs = brokenFloor.NewPool("TRexSlabs", Tune.SLABS)
local templates: Instance? = nil
local layers: { [string]: TLayers } = {}
local bricks: { BasePart } = {}
local boneBricks: { BasePart } = {}
local shardBricks: { BasePart } = {}
-- The Spine's pieces and where each sits in the spine's frame; the Rubble's slabs, narrowest first.
-- Each piece's authored see-through too, given back after a spine faded in the air (trexFx.LetGo).
local spinePieces: { { Template: BasePart, Offset: CFrame, Transparency: number } } = {}
local rubble: { BasePart } = {}
-- Copies of a template grown or shrunk (a Quake's beats), by name and size.
local scaled: { [string]: TLayers } = {}
local maw: TMaw? = nil
-- The Maw's pieces (which jaw, where each sits in its jaw's frame) and their movers, taken the first time it opens and
-- kept: one maw at a time.
local mawPieces: { { Template: BasePart, Offset: CFrame, IsUpper: boolean } } = {}
local mawMovers: { motorParts.TMover } = {}
local mawParts = motorParts.NewPool("TRexMaw", 64)
local isMawShown = false
-- The Glare template twice, a socket each.
local glareLayers: { TLayers } = {}
local glare: TGlare? = nil
local inhale: TInhale? = nil
-- Each Inhale emitter's lifetime and Drag as a decay rate (Drag halves the speed every 1 / Drag seconds), read once.
local pulls: { [ParticleEmitter]: { Life: number, Rate: number } } = {}
local hasWarned = false
local waves: { TWave } = {}
local rides: { TRide } = {}
local spines: { TSpine } = {}
-- Each floor layer's emitter, and the colour key it was last tinted to.
local tinted: { [ParticleEmitter]: number } = {}
local sequences: { [number]: ColorSequence } = {}
-- Every emitter of the kit and its authored TimeScale, which the clock's scale is laid over.
local authoredScales: { [ParticleEmitter]: number } = {}
local timeScale = 1
local light: PointLight? = nil
local lightHolder: Attachment? = nil
local lightPeak, lightFrom, lightSeconds = 0, 0, 1
local screen: ColorCorrectionEffect? = nil
local screenPeak, screenFrom, screenSeconds = 0, 0, 1
local rimOwed, nextRimGlint = 0, 0
local clock = 0
local cameraPosition = Vector3.zero

-- A copy of a template ready to throw. Not burstLayers.Clone: those copies all run on the match's time scale, which is
-- held at 0 through the boss's intro, and this kit plays through it (Update's own scale).
-- `size` grows or shrinks the copy: the layers lying on the floor (its rings and light) by `size`, the rest thrown
-- `size` times as fast and as wide (square root of it as big), so a stamp twice the size reaches twice as far.
local FLOOR_SIZED = { Wash = true, Bloom = true, Core = true, Shock = true, Echo = true }
local function layersOf(template: Instance, size: number?): TLayers
	local attachment = template:Clone() :: Attachment
	local emitters = {}
	for _, child in attachment:GetChildren() do
		if not child:IsA("ParticleEmitter") then continue end
		emitters[child.Name] = child
		authoredScales[child] = child.TimeScale
		child.TimeScale = child.TimeScale * timeScale
		if not size or size == 1 then continue end
		local grow = if FLOOR_SIZED[child.Name] then size else math.sqrt(size)
		local keys = {}
		for i, key in child.Size.Keypoints do
			keys[i] = NumberSequenceKeypoint.new(key.Time, key.Value * grow, key.Envelope * grow)
		end
		child.Size = NumberSequence.new(keys)
		if not FLOOR_SIZED[child.Name] then
			child.Speed = NumberRange.new(child.Speed.Min * size, child.Speed.Max * size)
		end
	end
	attachment.Parent = Workspace.Terrain
	return { Attachment = attachment, Emitters = emitters }
end

local function children(folder: Instance?, into: { BasePart })
	if not folder then return end
	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") then into[#into + 1] = child end
	end
end

-- The kit's layers; false (said once) while they are not in the place, when the T-Rex draws nothing of its own. A
-- miss is asked again, so templates that reach the client late are still found.
local function ready(): boolean
	if templates then return true end

	local effects = ReplicatedStorage:FindFirstChild("Effects")
	local found = if effects then effects:FindFirstChild(KIT) else nil
	local isComplete = found ~= nil
	if found then
		for _, name in LAYERS do
			if not found:FindFirstChild(name) then isComplete = false end
		end
	end
	if not found or not isComplete then
		if not hasWarned then
			hasWarned = true
			warn(`[trexFx] no ReplicatedStorage.Effects.{KIT}; the T-Rex draws no effects`)
		end
		return false
	end

	for _, name in LAYERS do
		layers[name] = layersOf(found:FindFirstChild(name) :: Instance)
	end
	for _, name in HUNT_LAYERS do
		local template = found:FindFirstChild(name)
		if template then layers[name] = layersOf(template) end
	end
	local glareTemplate = found:FindFirstChild("Glare")
	if glareTemplate then glareLayers = { layers.Glare, layersOf(glareTemplate) } end
	local breath = layers.Inhale
	if breath then
		for _, emitter in breath.Emitters do
			pulls[emitter] = { Life = emitter.Lifetime.Min, Rate = emitter.Drag * math.log(2) }
		end
	end
	children(found:FindFirstChild("Debris"), bricks)
	children(found:FindFirstChild("Bones"), boneBricks)
	children(found:FindFirstChild("Shards"), shardBricks)
	children(found:FindFirstChild("Rubble"), rubble)
	table.sort(rubble, function(a, b)
		return a.Size.X < b.Size.X
	end)
	local mawFolder = found:FindFirstChild("Maw")
	if mawFolder then
		for _, piece in mawFolder:GetChildren() do
			if not piece:IsA("BasePart") then continue end
			mawPieces[#mawPieces + 1] =
				{ Template = piece, Offset = piece.CFrame, IsUpper = string.sub(piece.Name, 1, 5) == "Upper" }
		end
	end
	local spineFolder = found:FindFirstChild("Spine")
	if spineFolder then
		for _, piece in spineFolder:GetChildren() do
			if piece:IsA("BasePart") then
				spinePieces[#spinePieces + 1] =
					{ Template = piece, Offset = piece.CFrame, Transparency = piece.Transparency }
			end
		end
	end

	local holder = Instance.new("Attachment")
	holder.Name = "TRexFxLight"
	holder.Parent = Workspace.Terrain
	lightHolder = holder
	local made = Instance.new("PointLight")
	made.Name = "TRexFxLight"
	made.Color = Tune.LIGHT_COLOR
	made.Shadows = false
	made.Enabled = false
	made.Parent = holder
	light = made
	templates = found
	return true
end

-- `at` with +Y along `up` (any turn round it).
local function aimed(at: Vector3, up: Vector3): CFrame
	local y = if up.Magnitude > 1e-4 then up.Unit else UP
	local side = if math.abs(y.Y) < 0.95 then UP else Vector3.xAxis
	local x = y:Cross(side).Unit
	return CFrame.fromMatrix(at, x, y, x:Cross(y))
end

local function place(name: string, at: Vector3, up: Vector3?): TLayers
	local found = layers[name]
	found.Attachment.CFrame = if up then aimed(at, up) else CFrame.new(at)
	return found
end

-- `place` of a copy grown to `size`, made the first time that size is asked for.
local function placeSized(name: string, size: number, at: Vector3, up: Vector3?): TLayers
	if size == 1 then return place(name, at, up) end
	local key = `{name}{size}`
	local found = scaled[key]
	if not found then
		found = layersOf((templates :: Instance):FindFirstChild(name) :: Instance, size)
		scaled[key] = found
	end
	found.Attachment.CFrame = if up then aimed(at, up) else CFrame.new(at)
	return found
end

local function colorKey(color: Color3): number
	return math.floor(color.R * 255 + 0.5) * 65536
		+ math.floor(color.G * 255 + 0.5) * 256
		+ math.floor(color.B * 255 + 0.5)
end

-- Recolours a template's floor layers to `color`, each lightened its own share toward white; skipped when unchanged.
local function tint(name: string, found: TLayers, color: Color3)
	for layer, pull in FLOOR_LAYERS do
		if layer == "Pixels" and OWN_PIXELS[name] then continue end
		local emitter = found.Emitters[layer]
		if not emitter then continue end
		local shade = color:Lerp(pull.To, pull.Share)
		local key = colorKey(shade)
		if tinted[emitter] == key then continue end
		tinted[emitter] = key
		local sequence = sequences[key]
		if not sequence then
			sequence = ColorSequence.new(shade)
			sequences[key] = sequence
		end
		emitter.Color = sequence
	end
end

local function near(at: Vector3, reach: number): boolean
	return (at - cameraPosition).Magnitude <= reach
end

-- Throws `count` of `from` out of `at` over a floor at `floorY`, in `color` (or their own).
local function throw(
	from: { BasePart },
	color: Color3?,
	at: Vector3,
	floorY: number,
	count: number,
	out: NumberRange,
	lift: NumberRange,
	spread: number
)
	if #from == 0 then return end
	for _ = 1, thrownPieces.Allowed(pieces, count, (at - cameraPosition).Magnitude) do
		local turn = random:NextNumber(0, math.pi * 2)
		local direction = Vector3.new(math.cos(turn), 0, math.sin(turn))
		thrownPieces.Throw(
			pieces,
			from[random:NextInteger(1, #from)],
			color,
			at + direction * random:NextNumber(0, spread) + UP * 0.6,
			direction * between(out) + UP * between(lift),
			floorY
		)
	end
end

-- The floor round `center` broken into a crater out to `radius`, in `color`.
local function crater(center: Vector3, color: Color3, radius: number, hold: number)
	if not near(center, Tune.SLAB_RANGE) then return end
	brokenFloor.Crater(slabs, rubble, center, color, radius, hold)
end

local function flashLight(at: Vector3, brightness: number, range: number, seconds: number)
	local made, holder = light, lightHolder
	if not made or not holder or not near(at, Tune.LIGHT_REACH) then return end
	holder.WorldPosition = at + UP * 3
	made.Range = range
	made.Brightness = brightness
	made.Enabled = true
	lightPeak, lightFrom, lightSeconds = brightness, clock, seconds
end

local function flashScreen(at: Vector3, strength: number, seconds: number)
	local distance = (at - cameraPosition).Magnitude
	local share = if distance <= Tune.SCREEN_NEAR
		then 1
		else math.max(1 - (distance - Tune.SCREEN_NEAR) / (Tune.SCREEN_FAR - Tune.SCREEN_NEAR), 0)
	if share <= 0 then return end
	local effect = screen
	if not effect then
		effect = Instance.new("ColorCorrectionEffect")
		effect.Name = "TRexFxScreen"
		effect.TintColor = Tune.SCREEN_TINT
		effect.Parent = Lighting
		screen = effect
	end
	screenPeak, screenFrom, screenSeconds = strength * share, clock, seconds
end

-- ============================== Floor ==============================

-- The floor under `at`: (where, its normal, its colour), or nil over nothing.
function trexFx.FloorUnder(at: Vector3): (Vector3?, Vector3, Color3)
	local result = sightCast(at + UP * Tune.FLOOR_LOOK_UP, -UP * (Tune.FLOOR_LOOK_UP + Tune.FLOOR_SEARCH))
	if not result then return nil, UP, Color3.new(0.6, 0.6, 0.6) end
	local part = result.Instance
	local color = if part:IsA("BasePart") and not part:IsA("Terrain") then part.Color else Color3.new(0.55, 0.5, 0.42)
	return result.Position, result.Normal, color
end

-- ============================== Its weight ==============================

-- A foot coming down on `floor`: walking at strength 1, running at 1.5.
function trexFx.Footfall(floor: Vector3, normal: Vector3, color: Color3, strength: number)
	if not ready() or not near(floor, Tune.RANGE) then return end
	local found = place("Step", floor + normal * Tune.LIFT, normal)
	tint("Step", found, color)
	emit(found, "Ring", 1)
	emit(found, "Dust", math.round(roll(Tune.STEP_DUST) * strength))
	emit(found, "Pixels", math.round(roll(Tune.STEP_PIXELS) * strength))
	throw(
		bricks,
		color,
		floor,
		floor.Y,
		math.round(roll(Tune.STEP_BRICKS) * strength),
		Tune.BRICK_OUT,
		Tune.BRICK_LIFT,
		2
	)
	if strength >= Tune.CATCH_STRENGTH then crater(floor, color, Tune.CATCH_CRATER, Tune.CATCH_CRATER_HOLD) end
end

-- A stamp on `floor`: `size` 1 is the Stomp, its shock out to the Stomp's reach; a Quake's beats grow to its last.
function trexFx.Stomp(floor: Vector3, normal: Vector3, color: Color3, size: number)
	if not ready() or not near(floor, Tune.RANGE) then return end
	local more = size
	local found = placeSized("Stomp", size, floor + normal * Tune.LIFT, normal)
	tint("Stomp", found, color)
	emit(found, "Wash", 1)
	emit(found, "Bloom", 1)
	emit(found, "Core", 1)
	emit(found, "Shock", 1)
	emit(found, "Echo", 1)
	emit(found, "Pillar", math.round(roll(Tune.STOMP_PILLAR) * more))
	emit(found, "Pixels", math.round(roll(Tune.STOMP_PIXELS) * more))
	emit(found, "Flecks", math.round(roll(Tune.STOMP_FLECKS) * more))
	emit(found, "Dust", math.round(roll(Tune.STOMP_DUST) * more))
	emit(found, "FloorPixels", math.round(roll(Tune.STOMP_FLOOR_PIXELS) * more))
	throw(bricks, color, floor, floor.Y, math.round(roll(Tune.STOMP_BRICKS) * more), Tune.BRICK_OUT, Tune.BRICK_LIFT, 5)
	crater(floor, color, Tune.STOMP_RADIUS * Tune.STOMP_CRATER * size, Tune.STOMP_CRATER_HOLD)
	flashLight(floor, 6 * size, 40 * size, 0.3)
	if size >= Tune.STOMP_BLINK then flashScreen(floor, 0.25, 0.3) end
end

-- A wave rolling out along the floor from `center` to `radius` at `speed`, tearing it up as it goes; `strength`
-- thins or thickens it.
function trexFx.Wave(center: Vector3, radius: number, speed: number, strength: number?)
	if not ready() or not near(center, Tune.RANGE + radius) then return end
	waves[#waves + 1] = {
		Center = center,
		Radius = 2,
		Max = radius,
		Speed = speed,
		Owed = 0,
		Strength = strength or 1,
		HasPassed = false,
	}
end

-- A foot dragged along the floor, sliding `along`.
function trexFx.Scrape(floor: Vector3, normal: Vector3, color: Color3, along: Vector3)
	if not ready() or not near(floor, Tune.RANGE) then return end
	local ahead = Vector3.new(along.X, 0, along.Z)
	local found = place("Scrape", floor + normal * 0.4, ahead + UP * 0.35)
	tint("Scrape", found, color)
	emit(found, "Dust", roll(Tune.SCRAPE_DUST))
	emit(found, "Pixels", roll(Tune.SCRAPE_PIXELS))
	emit(found, "Sparks", roll(Tune.SCRAPE_SPARKS))
	throw(bricks, color, floor, floor.Y, roll(Tune.SCRAPE_BRICKS), Tune.BRICK_OUT, Tune.BRICK_LIFT, 1.5)
end

-- ============================== Its moves ==============================

-- The bite snapping shut at `jaw`, facing `forward`, over the floor in front.
function trexFx.Bite(jaw: Vector3, forward: Vector3)
	if not ready() or not near(jaw, Tune.RANGE) then return end
	-- The spray goes ahead of the jaws; the rings lie level at them, closing like the jaws do (standing across the bite
	-- they read as a pane of glass in front of its face).
	local found = place("Bite", jaw, forward)
	emit(found, "Spray", roll(Tune.BITE_SPRAY))
	emit(found, "Flecks", roll(Tune.BITE_FLECKS))
	place("Bite", jaw)
	emit(found, "Bloom", 1)
	emit(found, "Core", 1)
	emit(found, "Snap", 1)
	emit(place("Bite", if maw then maw.At else jaw), "Bar", 1)
	flashLight(jaw, 5, 30, 0.2)

	local floor, normal, color = trexFx.FloorUnder(jaw)
	if not floor or jaw.Y - floor.Y > 8 then return end
	local under = place("BiteFloor", floor + normal * Tune.LIFT, normal)
	tint("BiteFloor", under, color)
	emit(under, "Ring", 1)
	emit(under, "Dust", roll(Tune.BITE_DUST))
	emit(under, "FloorPixels", roll(Tune.BITE_DUST))
	throw(bricks, color, floor, floor.Y, roll(Tune.BITE_BRICKS), Tune.BRICK_OUT, Tune.BRICK_LIFT, 3)
	crater(floor, color, Tune.BITE_CRATER, Tune.CATCH_CRATER_HOLD)
end

-- Its maw, two jaws of fangs biting along `forward`, opening on `at` (where the bite lands, held still while the head
-- swings down onto it) and snapping shut MAW_OPEN seconds later, on the bite: said that long before the bite lands.
function trexFx.Maw(at: Vector3, forward: Vector3)
	if not ready() or #mawPieces == 0 or not near(at, Tune.RANGE) then return end
	if #mawMovers == 0 then
		for i, piece in mawPieces do
			local mover = motorParts.Take(mawParts, piece.Template)
			if not mover then
				for _, taken in mawMovers do
					motorParts.Release(mawParts, taken)
				end
				table.clear(mawMovers)
				return
			end
			mawMovers[i] = mover
		end
	end
	local flat = Vector3.new(forward.X, 0, forward.Z)
	maw = {
		At = at,
		Forward = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zAxis,
		OpenedAt = clock,
		Color = nil,
		Transparency = -1,
		LetGoAt = nil,
	}
end

local function ride(
	name: string,
	where: () -> (Vector3?, Vector3?),
	seconds: number,
	rates: { [string]: number },
	floorName: string?,
	floorRate: number?
)
	local floorLayers = if floorName then layers[floorName] else nil
	rides[#rides + 1] = {
		Layers = layers[name],
		Where = where,
		Rates = rates,
		Owed = {},
		EndsAt = clock + seconds,
		Floor = floorLayers,
		FloorRate = floorRate or 0,
	}
end

-- The tail tip sweeping for `seconds`: its arc drawn in hanging pixels, the floor torn up under it where it is low.
function trexFx.Sweep(tip: () -> Vector3?, seconds: number)
	if not ready() then return end
	ride("Tail", function()
		return tip(), nil
	end, seconds, { Trail = Tune.TAIL_TRAIL_RATE, Flecks = Tune.TAIL_FLECKS_RATE }, "TailFloor", Tune.TAIL_DUST_RATE)
end

-- Breath snorted out of `nose`, `forward` the way it blows.
function trexFx.Snort(nose: Vector3, forward: Vector3)
	if not ready() or not near(nose, Tune.RANGE) then return end
	local found = place("Snort", nose, forward - UP * 0.4)
	emit(found, "Breath", roll(Tune.SNORT_BREATH))
	emit(found, "Pixels", roll(Tune.SNORT_PIXELS))
end

-- A volley shaken off its back at `back`.
function trexFx.Launch(back: Vector3)
	if not ready() or not near(back, Tune.RANGE) then return end
	local found = place("Launch", back)
	emit(found, "Bloom", 1)
	emit(found, "Core", 1)
	emit(found, "Ring", 1)
	emit(found, "Pixels", roll(Tune.LAUNCH_PIXELS))
	emit(found, "Bone", roll(Tune.LAUNCH_BONE))
	flashLight(back, 4, 30, 0.18)
end

-- A spine thrown from `from` now, landing on `to` `flight` seconds later.
function trexFx.Spine(from: Vector3, to: Vector3, flight: number)
	if not ready() or #spinePieces == 0 then return end
	local movers = table.create(#spinePieces)
	for i, piece in spinePieces do
		local mover = motorParts.Take(spineParts, piece.Template)
		if not mover then
			for _, taken in movers do
				motorParts.Release(spineParts, taken)
			end
			return
		end
		movers[i] = mover
	end
	spines[#spines + 1] = {
		Movers = movers,
		From = from,
		To = to,
		LaunchedAt = clock,
		Flight = math.max(flight, 0.05),
		LandedAt = 0,
		LetGoAt = nil,
		Stuck = CFrame.identity,
		Roll = random:NextNumber(0, math.pi * 2),
	}
end

-- The floor at `floor` taking its weight as it sinks, each heave `size` of the last.
function trexFx.Sink(floor: Vector3, normal: Vector3, color: Color3, size: number)
	if not ready() or not near(floor, Tune.RANGE) then return end
	local found = place("Sink", floor + normal * Tune.LIFT, normal)
	tint("Sink", found, color)
	emit(found, "Wash", 1)
	emit(found, "Ring", 1)
	emit(found, "Well", roll(Tune.SINK_WELL))
	emit(found, "Dust", roll(Tune.SINK_DUST))
	emit(found, "FloorPixels", roll(Tune.SINK_FLOOR_PIXELS))
	throw(bricks, color, floor, floor.Y, roll(Tune.SINK_BRICKS), Tune.BRICK_OUT, Tune.BRICK_LIFT, 6)
	crater(floor, color, Tune.SINK_CRATER * size, Tune.SINK_CRATER_HOLD)
end

-- One step of the crack it runs under the floor, running `along`: the floor glowing through, and pushed up either
-- side of it.
function trexFx.Crack(floor: Vector3, normal: Vector3, color: Color3, along: Vector3)
	if not ready() or not near(floor, Tune.RANGE) then return end
	local found = place("Crack", floor + normal * 0.06, normal)
	tint("Crack", found, color)
	emit(found, "Glow", 1)
	emit(found, "Rise", roll(Tune.CRACK_RISE))
	emit(found, "Dust", 1)
	if random:NextNumber() < Tune.CRACK_BRICK_CHANCE then
		throw(bricks, color, floor, floor.Y, 1, Tune.BRICK_OUT, Tune.BRICK_LIFT, 0.5)
	end
	if #rubble == 0 or not near(floor, Tune.SLAB_RANGE) then return end
	local side = along:Cross(normal)
	side = if side.Magnitude > 1e-3 then side.Unit else Vector3.xAxis
	for _, sign in { -1, 1 } do
		if random:NextNumber() > Tune.CRACK_SLAB_CHANCE then continue end
		local out = side * sign
		brokenFloor.Push(
			slabs,
			rubble[random:NextInteger(1, math.min(2, #rubble))],
			color,
			floor + out * Tune.CRACK_SLAB_OUT * random:NextNumber(0.8, 1.3),
			floor + normal,
			0,
			Tune.CRACK_SLAB_HOLD
		)
	end
end

-- The head of the crack shouldering through the floor at `floor`, running `along`: called every few steps of it.
function trexFx.Burrow(floor: Vector3, normal: Vector3, color: Color3, along: Vector3)
	if not ready() or not near(floor, Tune.RANGE) then return end
	local found = place("Sink", floor + normal * Tune.LIFT, normal)
	tint("Sink", found, color)
	emit(found, "Well", roll(Tune.BURROW_WELL))
	emit(found, "Dust", roll(Tune.BURROW_DUST))
	flashLight(floor, Tune.BURROW_LIGHT, Tune.BURROW_LIGHT_RANGE, Tune.BURROW_LIGHT_SECONDS)

	if #bricks > 0 then
		local side = along:Cross(normal)
		side = if side.Magnitude > 1e-3 then side.Unit else Vector3.xAxis
		local count = thrownPieces.Allowed(pieces, roll(Tune.BURROW_BRICKS), (floor - cameraPosition).Magnitude)
		for _ = 1, count do
			local out = (side * (if random:NextNumber() < 0.5 then -1 else 1) + along * between(Tune.BURROW_FORWARD)).Unit
			thrownPieces.Throw(
				pieces,
				bricks[random:NextInteger(1, #bricks)],
				color,
				floor + UP * 0.6,
				out * between(Tune.BURROW_OUT) + UP * between(Tune.BURROW_LIFT),
				floor.Y
			)
		end
	end

	-- Leaning back over the head, the floor it is pushing.
	if #rubble == 0 or not near(floor, Tune.SLAB_RANGE) then return end
	brokenFloor.Push(
		slabs,
		rubble[random:NextInteger(1, #rubble)],
		color,
		floor + along * Tune.BURROW_AHEAD,
		floor + normal * 2,
		0,
		Tune.BURROW_SLAB_HOLD
	)
end

-- Bursting up through `floor`.
function trexFx.Rise(floor: Vector3, normal: Vector3, color: Color3)
	if not ready() or not near(floor, Tune.RANGE) then return end
	local found = place("Rise", floor + normal * Tune.LIFT, normal)
	tint("Rise", found, color)
	emit(found, "Wash", 1)
	emit(found, "Bloom", 1)
	emit(found, "Core", 1)
	emit(found, "Shock", 1)
	emit(found, "Echo", 1)
	emit(found, "Pillar", roll(Tune.RISE_PILLAR))
	emit(found, "Pixels", roll(Tune.RISE_PIXELS))
	emit(found, "Flecks", roll(Tune.RISE_FLECKS))
	emit(found, "Bone", roll(Tune.RISE_BONE))
	emit(found, "Dust", roll(Tune.RISE_DUST))
	emit(found, "FloorPixels", roll(Tune.RISE_FLOOR_PIXELS))
	throw(bricks, color, floor, floor.Y, roll(Tune.RISE_BRICKS), Tune.BRICK_OUT, Tune.BONE_LIFT, 7)
	throw(boneBricks, nil, floor, floor.Y, roll(Tune.RISE_BONES), Tune.BONE_OUT, Tune.BONE_LIFT, 4)
	crater(floor, color, Tune.RISE_CRATER, Tune.RISE_CRATER_HOLD)
	flashLight(floor, 7, 50, 0.4)
	flashScreen(floor, 0.3, 0.35)
	trexFx.Wave(floor, 26, 45, 0.8)
end

-- Its bones knocking back together at `chest`.
function trexFx.Rattle(chest: Vector3)
	if not ready() or not near(chest, Tune.RANGE) then return end
	local found = place("Rattle", chest)
	emit(found, "Ring", 1)
	emit(found, "Bone", roll(Tune.RATTLE_BONE))
	emit(found, "Pixels", roll(Tune.RATTLE_PIXELS))
end

-- The roar for `seconds`: rings of its sound and breath out of the jaws (`mouth` says where they are and which way
-- they face), the ground under it struck once at `floor` and a wave rolled out to `reach`.
function trexFx.Roar(mouth: () -> (Vector3?, Vector3?), seconds: number, floor: Vector3?, color: Color3?, reach: number)
	if not ready() then return end
	local nextWave = 0
	ride("Roar", function()
		local at, forward = mouth()
		if at and forward and clock >= nextWave then
			nextWave = clock + Tune.ROAR_WAVE_SECONDS
			emit(place("Roar", at, forward), "Wave", 1)
		end
		return at, forward
	end, seconds, { Breath = Tune.ROAR_BREATH_RATE, Flecks = Tune.ROAR_FLECKS_RATE, Steam = Tune.ROAR_STEAM_RATE })
	if not floor then return end

	local found = place("RoarFloor", floor + UP * Tune.LIFT)
	tint("RoarFloor", found, color or WHITE)
	emit(found, "Wash", 1)
	emit(found, "Shock", 1)
	emit(found, "Echo", 1)
	emit(found, "Dust", roll(Tune.ROAR_DUST))
	flashLight(floor, 8, 60, 0.6)
	flashScreen(floor, 0.2, 0.45)
	trexFx.Wave(floor, reach, 55, 1)
end

-- ============================== Its hunt ==============================

-- Its eye sockets burning while it stares, for as long as `eyes` answers where both are and how bright (0 out, 1 the
-- stare, more as it flares); answering nil lets go, and the light eases out where it was. A socket on the move leaves
-- a streak of its light, and embers rise off it.
function trexFx.Glare(eyes: () -> (Vector3?, Vector3?, number))
	if not ready() or #glareLayers < 2 then return end
	local held = glare
	if held then held.IsLetGo = true end
	glare = { Eyes = eyes, IsLetGo = false, Strength = 0, Was = {}, TrailOwed = { 0, 0 }, EmberOwed = 0 }
end

-- The stare locking on at both sockets: a white-hot heart and a bar of light across each eye, and a light on the
-- skull round them.
function trexFx.Glint(left: Vector3, right: Vector3)
	local found = layers.Glint
	if not ready() or not found or not near(left, Tune.RANGE) then return end
	for _, at in { left, right } do
		found.Attachment.CFrame = CFrame.new(at)
		emit(found, "Core", 1)
		emit(found, "Bar", 1)
		emit(found, "Pixels", roll(Tune.GLINT_PIXELS))
	end
	flashLight((left + right) / 2 - UP * 3, 4, 14, 0.35)
end

-- Its teeth shutting at `at`, `forward` out of the jaws.
function trexFx.Click(at: Vector3, forward: Vector3)
	local found = layers.Click
	if not ready() or not found or not near(at, Tune.RANGE) then return end
	place("Click", at, forward)
	emit(found, "Core", 1)
	emit(found, "Bar", 1)
	emit(found, "Bone", roll(Tune.CLICK_BONE))
end

-- Dust and bone shaken off its neck at `points` as it swings `along`, `size` 1 the hardest.
function trexFx.Shake(points: { Vector3 }, along: Vector3, size: number)
	local found = layers.Shake
	if not ready() or not found or #points == 0 or #bricks == 0 or not near(points[1], Tune.RANGE) then return end
	local way = if along.Magnitude > 1e-3 then along.Unit else UP
	local floorY = thrownPieces.FloorUnder(points[1])
	for _, bonePoint in points do
		local at = bonePoint + (way + UP) * Tune.SHAKE_OUT_OF
		place("Shake", at, way + UP * 0.3)
		emit(found, "Powder", math.round(roll(Tune.SHAKE_DUST) * size))
		emit(found, "Bone", math.round(roll(Tune.SHAKE_BONE) * size))
		local count = math.round(roll(Tune.SHAKE_BRICKS) * size)
		for _ = 1, thrownPieces.Allowed(pieces, count, (at - cameraPosition).Magnitude) do
			thrownPieces.Throw(
				pieces,
				bricks[random:NextInteger(1, #bricks)],
				Tune.BONE,
				at + random:NextUnitVector() * 0.6,
				way * between(Tune.SHAKE_OUT) + UP * between(Tune.SHAKE_LIFT) + random:NextUnitVector() * 3,
				floorY
			)
		end
	end
end

-- A breath in for `seconds`: the floor's dust and pixels, air and motes of its green pulled into the jaws (`mouth` says
-- where they are and which way they face), a ring closing in on the `floor` under them, in its `color`.
function trexFx.Inhale(mouth: () -> (Vector3?, Vector3?), seconds: number, floor: Vector3?, color: Color3)
	local found = layers.Inhale
	if not ready() or not found then return end
	tint("Inhale", found, color)
	inhale = {
		Mouth = mouth,
		StartedAt = clock,
		Seconds = seconds,
		Floor = floor,
		Was = nil,
		Owed = {},
		Rings = 0,
	}
end

-- ============================== Its shield and guards ==============================

function trexFx.ShieldUp(center: Vector3)
	if not ready() or not near(center, Tune.RANGE) then return end
	local found = place("ShieldUp", center)
	emit(found, "Bloom", 1)
	emit(found, "Core", 1)
	emit(found, "Ring", 1)
	emit(found, "Pixels", roll(Tune.SHIELD_UP_PIXELS))
	flashLight(center, 7, 50, 0.4)
end

-- A blow on the bubble round `center` (`radius` across half), on the side facing `from`.
function trexFx.ShieldHit(center: Vector3, radius: number, from: Vector3)
	if not ready() or not near(center, Tune.RANGE) then return end
	local out = from - center
	out = if out.Magnitude > 1e-3 then out.Unit else UP
	out = (out + random:NextUnitVector() * 0.25).Unit
	local found = place("ShieldHit", center + out * radius, out)
	emit(found, "Core", 1)
	emit(found, "Ring", 1)
	emit(found, "Pixels", roll(Tune.SHIELD_HIT_PIXELS))
end

-- The bubble shattering round `center`.
function trexFx.ShieldBreak(center: Vector3, radius: number)
	if not ready() or not near(center, Tune.RANGE) then return end
	local found = place("ShieldBreak", center)
	emit(found, "Bloom", 1)
	emit(found, "Core", 1)
	emit(found, "Ring", 1)
	emit(found, "Pixels", roll(Tune.BREAK_PIXELS))
	emit(found, "Flecks", roll(Tune.BREAK_FLECKS))
	local floorY = thrownPieces.FloorUnder(center)
	for _ = 1, thrownPieces.Allowed(pieces, roll(Tune.BREAK_SHARDS), (center - cameraPosition).Magnitude) do
		if #shardBricks == 0 then break end
		local out = random:NextUnitVector()
		thrownPieces.Throw(
			pieces,
			shardBricks[random:NextInteger(1, #shardBricks)],
			nil,
			center + out * radius * 0.85,
			out * random:NextNumber(14, 30) + UP * random:NextNumber(10, 26),
			floorY
		)
	end
	flashLight(center, 10, 60, 0.45)
	flashScreen(center, 0.3, 0.35)
end

-- One frame of the bubble standing round `center` on `floor`: motes welling up round its foot, a glint now and then.
function trexFx.ShieldRim(floor: Vector3, radius: number, dt: number)
	if not ready() or not near(floor, Tune.RANGE) then return end
	rimOwed += Tune.RIM_RATE * dt
	local count = math.floor(rimOwed)
	rimOwed -= count
	local found = layers.ShieldRim
	for _ = 1, count do
		local turn = random:NextNumber(0, math.pi * 2)
		found.Attachment.CFrame = CFrame.new(floor + Vector3.new(math.cos(turn), 0, math.sin(turn)) * radius * 0.92)
		emit(found, "Mote", 1)
	end
	if clock < nextRimGlint then return end
	nextRimGlint = clock + Tune.RIM_GLINT_SECONDS
	local turn = random:NextNumber(0, math.pi * 2)
	found.Attachment.CFrame = CFrame.new(floor + Vector3.new(math.cos(turn), 0.1, math.sin(turn)) * radius * 0.9)
	emit(found, "Glint", 1)
end

-- One frame of a guard's beam from `from` to `to`: motes flowing along it into the boss. `phase` is the beam's own
-- (0 to 1), carried by the caller so beams do not pulse together.
function trexFx.BeamFlow(from: Vector3, to: Vector3, phase: number, dt: number, owed: number): number
	if not ready() or not near(to, Tune.RANGE) then return owed end
	owed += Tune.BEAM_RATE * dt
	local count = math.floor(owed)
	local found = layers.Beam
	for i = 1, count do
		local u = (phase * Tune.BEAM_FLOW + i / math.max(count, 1) * 0.12 + random:NextNumber() * 0.9) % 1
		found.Attachment.CFrame = CFrame.new(from:Lerp(to, u))
		emit(found, "Mote", 1)
	end
	return owed - count
end

-- Its boss is dead: what is left of its moves lets go where it is. What rides its body stops pouring out (what is out
-- lives out its life), the maw fades holding its bite, and a spine in the air fades on its way, as its warning is
-- taken back (EnemyAttacksService). Landed things (a spine stuck in the floor, a wave rolling) run on. Kit-wide: one
-- boss at a time, as with the maw.
function trexFx.LetGo()
	for _, entry in rides do
		entry.EndsAt = math.min(entry.EndsAt, clock)
	end
	local open = maw
	if open and not open.LetGoAt then open.LetGoAt = clock end
	for _, spine in spines do
		if spine.LandedAt == 0 and not spine.LetGoAt then spine.LetGoAt = clock end
	end
end

-- Spines still in the air (the debug readout's): a stuck one is no longer a projectile.
function trexFx.SpinesInAir(): number
	local count = 0
	for _, spine in spines do
		if spine.LandedAt == 0 then
			count += 1
		end
	end
	return count
end

-- A guard falling breaks its beam at `at`.
function trexFx.Snap(at: Vector3)
	if not ready() or not near(at, Tune.RANGE) then return end
	local found = place("Snap", at)
	emit(found, "Bloom", 1)
	emit(found, "Core", 1)
	emit(found, "Ring", 1)
	emit(found, "Pixels", roll(Tune.SNAP_PIXELS))
	emit(found, "Bone", roll(Tune.SNAP_BONE))
	throw(boneBricks, nil, at, thrownPieces.FloorUnder(at), roll(Tune.SNAP_BONES), Tune.BRICK_OUT, Tune.BRICK_LIFT, 1)
end

-- ============================== Its end ==============================

-- Its bones bursting off it as the killing blow lands at `chest`.
function trexFx.Shatter(chest: Vector3)
	if not ready() or not near(chest, Tune.RANGE) then return end
	trexFx.Rattle(chest)
	throw(
		boneBricks,
		nil,
		chest,
		thrownPieces.FloorUnder(chest),
		roll(Tune.RISE_BONES),
		Tune.BONE_OUT,
		Tune.BONE_LIFT,
		3
	)
	flashScreen(chest, 0.2, 0.25)
end

-- The pile coming down on `floor` (its body's frame `body`), then its soul leaving it for `soulSeconds`.
function trexFx.Fall(floor: Vector3, normal: Vector3, color: Color3, body: CFrame, soulSeconds: number)
	if not ready() or not near(floor, Tune.RANGE) then return end
	local found = place("Fall", floor + normal * Tune.LIFT, normal)
	tint("Fall", found, color)
	emit(found, "Wash", 1)
	emit(found, "Bloom", 1)
	emit(found, "Core", 1)
	emit(found, "Shock", 1)
	emit(found, "Echo", 1)
	emit(found, "Pillar", roll(Tune.FALL_PILLAR))
	emit(found, "Pixels", roll(Tune.FALL_PIXELS))
	emit(found, "Flecks", roll(Tune.FALL_FLECKS))
	emit(found, "Bone", roll(Tune.FALL_BONE))
	emit(found, "Dust", roll(Tune.FALL_DUST))
	emit(found, "FloorPixels", roll(Tune.FALL_FLOOR_PIXELS))
	throw(bricks, color, floor, floor.Y, roll(Tune.FALL_BRICKS), Tune.BRICK_OUT, Tune.BONE_LIFT, 10)
	throw(boneBricks, nil, floor + UP * 2, floor.Y, roll(Tune.FALL_BONES), Tune.BONE_OUT, Tune.BONE_LIFT, 10)
	flashLight(floor, 12, 70, 0.7)
	flashScreen(floor, 0.4, 0.5)
	trexFx.Wave(floor, 44, 50, 1.3)

	-- Its soul, off the length of the pile: from the hips to the tail and the skull.
	local nextGlint = 0
	ride("Soul", function()
		local along = random:NextNumber(-14, 22)
		local at = body:PointToWorldSpace(Vector3.new(random:NextNumber(-3, 3), 0, along))
		at = Vector3.new(at.X, floor.Y + random:NextNumber(0.5, 3), at.Z)
		if clock >= nextGlint then
			nextGlint = clock + Tune.SOUL_GLINT_SECONDS
			emit(place("Soul", Vector3.new(at.X, floor.Y + 0.15, at.Z)), "Glint", 1)
		end
		return at, nil
	end, soulSeconds, { Mote = Tune.SOUL_RATE })
end

-- ============================== Each frame ==============================

-- Rolls each wave on; answers where and how strong one went under `body` this frame, if one did.
local function stepWaves(dt: number, body: Vector3?): (Vector3?, number)
	local found = layers.Front
	local rays = Tune.FRONT_RAYS
	local passedAt, passedStrength = nil, 0
	for i = #waves, 1, -1 do
		local wave = waves[i]
		wave.Radius = math.min(wave.Radius + wave.Speed * dt, wave.Max)
		if body and not wave.HasPassed then
			local flat = Vector3.new(body.X - wave.Center.X, 0, body.Z - wave.Center.Z)
			if flat.Magnitude <= wave.Radius then
				wave.HasPassed = true
				if wave.Radius < wave.Max and wave.Strength > passedStrength then
					passedAt, passedStrength = body, wave.Strength
				end
			end
		end
		wave.Owed += Tune.FRONT_RATE * wave.Strength * (wave.Radius / wave.Max + 0.3) * dt
		local count = math.min(math.floor(wave.Owed), rays)
		wave.Owed -= count
		rays -= count
		for _ = 1, count do
			local turn = random:NextNumber(0, math.pi * 2)
			local point = wave.Center + Vector3.new(math.cos(turn), 0, math.sin(turn)) * wave.Radius
			local floor, normal, color = trexFx.FloorUnder(point)
			if not floor then continue end
			found.Attachment.CFrame = aimed(floor + normal * Tune.LIFT, normal)
			tint("Front", found, color)
			emit(found, "Lick", 1)
			emit(found, "Stand", random:NextInteger(1, 2))
			emit(found, "FloorPixels", 1)
			if random:NextNumber() < Tune.FRONT_DUST_CHANCE then emit(found, "Dust", 1) end
			if random:NextNumber() < Tune.FRONT_BRICK_CHANCE * wave.Strength then
				throw(bricks, color, floor, floor.Y, 1, Tune.BRICK_OUT, Tune.BRICK_LIFT, 0.5)
			end
			if #rubble > 0 and random:NextNumber() < Tune.FRONT_SLAB_CHANCE * wave.Strength then
				brokenFloor.Push(
					slabs,
					rubble[random:NextInteger(1, math.min(2, #rubble))],
					color,
					floor,
					wave.Center + UP * (wave.Radius / 3),
					0,
					Tune.FRONT_SLAB_HOLD
				)
			end
		end
		if wave.Radius < wave.Max then continue end
		waves[i] = waves[#waves]
		waves[#waves] = nil
	end

	return passedAt, passedStrength
end

local function stepRides(dt: number)
	for i = #rides, 1, -1 do
		local entry = rides[i]
		local at, forward = entry.Where()
		if at and clock < entry.EndsAt then
			local found = entry.Layers
			found.Attachment.CFrame = if forward then aimed(at, forward) else CFrame.new(at)
			for layer, rate in entry.Rates do
				local total = (entry.Owed[layer] or 0) + rate * dt
				local count = math.floor(total)
				entry.Owed[layer] = total - count
				emit(found, layer, count)
			end

			local floorLayers = entry.Floor
			if floorLayers then
				local total = (entry.Owed.Floor or 0) + entry.FloorRate * dt
				local count = math.floor(total)
				entry.Owed.Floor = total - count
				local floor, normal, color = nil, UP, WHITE
				if count > 0 then
					floor, normal, color = trexFx.FloorUnder(at)
				end
				if floor and at.Y - floor.Y <= Tune.TAIL_FLOOR then
					floorLayers.Attachment.CFrame = aimed(floor + normal * 0.3, normal)
					tint("TailFloor", floorLayers, color)
					emit(floorLayers, "Dust", count)
					emit(floorLayers, "FloorPixels", count)
				end
			end
			continue
		end
		rides[i] = rides[#rides]
		rides[#rides] = nil
	end
end

-- Every piece of a spine to where it sits in `cframe`.
local function pose(spine: TSpine, cframe: CFrame)
	for i, mover in spine.Movers do
		mover.Joint.Transform = cframe * spinePieces[i].Offset
	end
end

local function stepSpines(now: number)
	for i = #spines, 1, -1 do
		local spine = spines[i]
		if spine.LandedAt == 0 then
			local u = math.clamp((now - spine.LaunchedAt) / spine.Flight, 0, 1)
			local arc = Tune.SPINE_ARC
			local point = spine.From:Lerp(spine.To, u) + UP * (4 * arc * u * (1 - u))
			local ahead = spine.From:Lerp(spine.To, math.min(u + 0.04, 1)) + UP * (4 * arc * (u + 0.04) * (0.96 - u))
			if (ahead - point).Magnitude > 1e-3 then
				local spin = spine.Roll + Tune.SPINE_ROLL * (now - spine.LaunchedAt)
				pose(spine, CFrame.lookAt(point, ahead) * CFrame.Angles(0, 0, spin))
			end
			local letGoAt = spine.LetGoAt
			if letGoAt then
				local faded = (now - letGoAt) / Tune.SPINE_LET_GO
				if faded < 1 then
					for k, mover in spine.Movers do
						local authored = spinePieces[k].Transparency
						mover.Part.Transparency = authored + (1 - authored) * faded
					end
					continue
				end
				for k, mover in spine.Movers do
					mover.Part.Transparency = spinePieces[k].Transparency
					motorParts.Release(spineParts, mover)
				end
				spines[i] = spines[#spines]
				spines[#spines] = nil
				continue
			end
			if u > 0 then emit(place("SpineTrail", point), "Trail", 1) end
			if u < 1 then continue end

			-- Stuck in the floor nose first, leaning the way it flew, and its circle bursts.
			spine.LandedAt = now
			local flat = Vector3.new(spine.To.X - spine.From.X, 0, spine.To.Z - spine.From.Z)
			local lean = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zAxis
			spine.Stuck = CFrame.lookAt(spine.To + UP * 1.2, spine.To - UP * 2 + lean)
			pose(spine, spine.Stuck)
			local floor, normal, color = trexFx.FloorUnder(spine.To)
			if floor then
				local found = place("SpineLand", floor + normal * Tune.LIFT, normal)
				tint("SpineLand", found, color)
				emit(found, "Wash", 1)
				emit(found, "Core", 1)
				emit(found, "Shock", 1)
				emit(found, "Pixels", roll(Tune.SPINE_PIXELS))
				emit(found, "Dust", roll(Tune.SPINE_DUST))
				emit(found, "FloorPixels", roll(Tune.SPINE_FLOOR_PIXELS))
				throw(bricks, color, floor, floor.Y, roll(Tune.SPINE_BRICKS), Tune.BRICK_OUT, Tune.BRICK_LIFT, 1.5)
				crater(floor, color, Tune.SPINE_CRATER, Tune.SPINE_CRATER_HOLD)
			end
			continue
		end

		-- Then it quivers where it stuck, sinks into the floor, slowly and then all at once, and goes.
		local held = now - spine.LandedAt
		if held < Tune.SPINE_STUCK then
			local u = held / Tune.SPINE_STUCK
			local quiver = Tune.SPINE_QUIVER
				* math.exp(-held * Tune.SPINE_QUIVER_DECAY)
				* math.sin(held * Tune.SPINE_QUIVER_RATE)
			pose(spine, (spine.Stuck - UP * (Tune.SPINE_SINK * u * u * u)) * CFrame.Angles(quiver, 0, 0))
			continue
		end
		for _, mover in spine.Movers do
			motorParts.Release(spineParts, mover)
		end
		spines[i] = spines[#spines]
		spines[#spines] = nil
	end
end

-- The maw's angle (degrees, the upper jaw's), how far drawn back it is, and how see-through, `age` seconds in: opening
-- wider, a cubic snap shut at MAW_OPEN thrown forward, bitten past, chewed back, then letting go as it fades.
local function mawPose(age: number): (number, number, number)
	local snapFrom = Tune.MAW_OPEN * (1 - Tune.MAW_SNAP)
	local shown = math.min(age / Tune.MAW_IN, 1)
	if age < snapFrom then
		local u = age / snapFrom
		return Tune.MAW_ANGLE * (0.45 + 0.55 * math.sin(u * math.pi / 2)), u, 1 - shown
	elseif age < Tune.MAW_OPEN then
		local u = (age - snapFrom) / (Tune.MAW_OPEN - snapFrom)
		return Tune.MAW_ANGLE * (1 - u * u * u), 1 - u * u, 0
	end
	local after = age - Tune.MAW_OPEN
	if after < Tune.MAW_LET_GO then return -Tune.MAW_PAST * math.exp(-after * 30) * math.cos(after * 45), 0, 0 end
	local letGo = after - Tune.MAW_LET_GO
	return letGo * Tune.MAW_RELEASE, 0, math.min(letGo / Tune.MAW_FADE, 1)
end

-- The maw's two jaws swung about their hinges and laid in the T-Rex's frame; put away once it has faded.
local function stepMaw()
	local open = maw
	if not open then
		if not isMawShown then return end
		isMawShown = false
		for _, mover in mawMovers do
			mover.Joint.Transform = motorParts.PARK
		end
		return
	end
	-- Let go, it holds the pose it had and fades over MAW_FADE.
	local letGoAt = open.LetGoAt
	local age = (if letGoAt then letGoAt else clock) - open.OpenedAt
	local angle, back, fade = mawPose(age)
	if letGoAt then fade = math.max(fade, math.min((clock - letGoAt) / Tune.MAW_FADE, 1)) end
	if fade >= 1 then
		maw = nil
		return
	end
	isMawShown = true

	local forward = open.Forward
	local hinge = open.At - forward * (Tune.MAW_HINGE_BACK + Tune.MAW_LUNGE * back)
	local base = CFrame.lookAt(hinge, hinge + forward)
	local upper = base * CFrame.new(0, Tune.MAW_HINGE_GAP, 0) * CFrame.Angles(math.rad(angle), 0, 0)
	local lower = base * CFrame.new(0, -Tune.MAW_HINGE_GAP, 0) * CFrame.Angles(-math.rad(angle * Tune.MAW_LOWER), 0, 0)
	for i, piece in mawPieces do
		mawMovers[i].Joint.Transform = (if piece.IsUpper then upper else lower) * piece.Offset
	end

	local after = age - Tune.MAW_OPEN
	local color = if after >= 0 and after < Tune.MAW_FLASH then Tune.MAW_HOT else Tune.MAW_GREEN
	if color ~= open.Color or fade ~= open.Transparency then
		open.Color = color
		open.Transparency = fade
		for _, mover in mawMovers do
			mover.Part.Color = color
			mover.Part.Transparency = fade
		end
	end
end

-- One socket of the glare this frame: its light and pupil laid on it (held there from its first frame), the streak
-- along the way it moved, its embers.
local function glareSocket(entry: TGlare, i: number, at: Vector3?, shown: number, embers: number)
	local found = glareLayers[i]
	local was = entry.Was[i]
	local here = at or was
	if not here then return end
	if not was then
		found.Attachment.CFrame = CFrame.new(here)
		emit(found, "Glow", 1)
		emit(found, "Pupil", 1)
		was = here
	end

	local owed = entry.TrailOwed[i] + (here - was).Magnitude * shown / Tune.TRAIL_SPACING
	local count = math.floor(owed)
	entry.TrailOwed[i] = owed - count
	count = math.min(count, Tune.TRAIL_MAX)
	for k = 1, count do
		found.Attachment.CFrame = CFrame.new(was:Lerp(here, k / count))
		emit(found, "Trail", 1)
	end

	found.Attachment.CFrame = CFrame.new(here)
	emit(found, "Ember", embers)
	found.Emitters.Glow.Brightness = shown * Tune.GLARE_GLOW
	found.Emitters.Pupil.Brightness = shown * Tune.GLARE_PUPIL
	entry.Was[i] = here
end

local function stepGlare(dt: number)
	local entry = glare
	if not entry then return end
	local left, right, strength = nil, nil, 0
	if not entry.IsLetGo then
		left, right, strength = entry.Eyes()
	end
	if left and right then
		entry.Strength = math.max(strength, 0)
	else
		-- Let go: it eases out where it was, never snapping off.
		entry.IsLetGo = true
		entry.Strength = math.max(entry.Strength - dt / Tune.GLARE_OUT, 0)
	end
	local shown = entry.Strength
	if entry.IsLetGo and shown <= 0 then
		for _, found in glareLayers do
			found.Emitters.Glow:Clear()
			found.Emitters.Pupil:Clear()
		end
		if glare == entry then glare = nil end
		return
	end

	entry.EmberOwed += Tune.EMBER_RATE * shown * dt
	local embers = math.floor(entry.EmberOwed)
	entry.EmberOwed -= embers
	glareSocket(entry, 1, left, shown, embers)
	glareSocket(entry, 2, right, shown, embers)
end

-- Where one thing breathed in starts: round the jaws at `at` (more ahead of them, along `facing`), or off the floor
-- under them; nil when every try came from nearer the camera than the jaws are.
local function inhaleSource(at: Vector3, facing: Vector3, floor: Vector3?, isOffFloor: boolean): Vector3?
	local clear = (at - cameraPosition).Magnitude * Tune.INHALE_CLEAR
	for _ = 1, 3 do
		local from: Vector3
		if isOffFloor and floor and random:NextNumber() < Tune.INHALE_FLOOR_SHARE then
			local turn = random:NextNumber(0, math.pi * 2)
			from = Vector3.new(at.X, floor.Y + 0.4, at.Z)
				+ Vector3.new(math.cos(turn), 0, math.sin(turn)) * between(Tune.INHALE_REACH)
		else
			from = at + (random:NextUnitVector() + facing * Tune.INHALE_AHEAD).Unit * between(Tune.INHALE_REACH)
			if floor and from.Y < floor.Y + 0.5 then from = Vector3.new(from.X, floor.Y + 0.5, from.Z) end
		end
		if (from - cameraPosition).Magnitude >= clear then return from end
	end

	return nil
end

local function stepInhale(dt: number)
	local entry = inhale
	if not entry then return end
	local at, facing = entry.Mouth()
	if not at or not facing or clock >= entry.StartedAt + entry.Seconds then
		inhale = nil
		return
	end
	local was = entry.Was or at
	entry.Was = at
	local velocity = if dt > 0 then (at - was) / dt else Vector3.zero

	local floor = entry.Floor
	local rings = layers.InhaleFloor
	if floor and rings then
		local share = (clock - entry.StartedAt) / entry.Seconds
		while entry.Rings < #Tune.INHALE_RINGS and share >= Tune.INHALE_RINGS[entry.Rings + 1] do
			entry.Rings += 1
			rings.Attachment.CFrame = CFrame.new(Vector3.new(at.X, floor.Y + Tune.LIFT, at.Z))
			emit(rings, "Ring", 1)
		end
	end

	-- Each aimed at where the jaws will be as it dies, its speed set so it gets there then (gaining on a negative Drag).
	local found = layers.Inhale
	for layer, rate in Tune.INHALE_RATES do
		local total = (entry.Owed[layer] or 0) + rate * dt
		local count = math.floor(total)
		entry.Owed[layer] = total - count
		local emitter = found.Emitters[layer]
		local pull = if emitter then pulls[emitter] else nil
		if not emitter or not pull then continue end
		if clock + pull.Life * Tune.INHALE_LAST > entry.StartedAt + entry.Seconds then continue end
		local to = at + velocity * pull.Life * Tune.INHALE_LEAD
		local isOffFloor = layer == "Dust" or layer == "Pixels"
		for _ = 1, count do
			local from = inhaleSource(at, facing, floor, isOffFloor)
			if not from then continue end
			local way = to - from
			local distance = way.Magnitude
			local k = pull.Rate
			found.Attachment.CFrame = aimed(from, way)
			emitter.Speed = NumberRange.new(
				if math.abs(k) < 1e-4 then distance / pull.Life else distance * k / (1 - math.exp(-k * pull.Life))
			)
			fxBudget.Emit(emitter, 1, from)
		end
	end
end

local function stepFlashes()
	local made = light
	if made and made.Enabled then
		local u = (clock - lightFrom) / lightSeconds
		if u >= 1 then
			made.Enabled = false
		else
			made.Brightness = lightPeak * (1 - u) * (1 - u)
		end
	end

	local effect = screen
	if not effect then return end
	local u = math.min((clock - screenFrom) / screenSeconds, 1)
	local strength = screenPeak * (1 - u) * (1 - u)
	effect.Brightness = strength * 0.2
	effect.Contrast = strength * 0.25
	effect.Enabled = strength > 0.005
end

-- Once a frame, on the clock the caller keeps (the fight's, or real time through the intro): `dt` since the last,
-- `now`, and `scale` that clock's speed, which particles and pieces already in the air run at (0 holds them). `body`
-- is the local player's: answers where and how strong a wave rolling along the floor went under it this frame.
function trexFx.Update(dt: number, now: number, scale: number, body: Vector3?): (Vector3?, number)
	thrownPieces.Step(pieces, scale)
	brokenFloor.Step(slabs, scale)
	clock = now
	local clamped = math.clamp(scale, 0, 1)
	if clamped ~= timeScale then
		timeScale = clamped
		for emitter, authored in authoredScales do
			emitter.TimeScale = authored * clamped
		end
	end
	cameraPosition = Workspace.CurrentCamera.CFrame.Position
	if not templates then return nil, 0 end
	local passedAt, passedStrength = stepWaves(dt, body)
	stepRides(dt)
	stepGlare(dt)
	stepInhale(dt)
	stepSpines(now)
	stepMaw()
	stepFlashes()

	return passedAt, passedStrength
end

return trexFx
