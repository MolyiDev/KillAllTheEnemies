-- A shot's look for a gun whose data names an effect kit (TGun.Fx), toy style: the flash and casing at the muzzle, the
-- bullet (a Neon bar shedding glowing pixels that taper behind it, the Comet), and where it lands, timed to the bullet's arrival (a flash, a square ring, glowing
-- pixels and a puff of the wall's own colour, and its stud bricks thrown off, bouncing and sinking away). Purely a
-- picture: hits are WeaponService's, and the enemy's own burst comes from its damage events. A kit's look is its
-- templates at ReplicatedStorage.Effects.<kit>, a place instance made by Assets/effects/pistol and Assets/effects/guns
-- (their READMEs); this module clones them and says how many each layer throws (LOOKS). Step is the owner's to call
-- once a frame (WeaponController).
--
-- Bullets are Client/Utils/motorParts, bricks and casings Client/Utils/thrownPieces: nothing here is simulated by the
-- engine; Step works out where each one is and writes its joint. Multi-part bullets, Orbit parts and streaks are drawn
-- only by the benches' losing looks (SetBullet, pistolBenchLooks) and go with them.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local motorParts = require(script.Parent.motorParts)
local thrownPieces = require(script.Parent.thrownPieces)

local Effects = ReplicatedStorage:WaitForChild("Effects")

local gunFx = {}

-- What thrown bricks and casings land on; nil is Workspace.Arena. The bench sets its own while it stands.
gunFx.FloorParams = nil :: RaycastParams?

-- Shown a frame ahead, so a point-blank shot still draws once before it lands.
local LEAD = 1 / 60
-- The impact layers that take the hit surface's colour.
local TINTED = table.freeze({ Puffs = true, Pixels = true })
local WHITE = Color3.new(1, 1, 1)
local ONE = NumberRange.new(1)
-- What a look that names none throws and where its casing leaves.
local DEFAULT_DEBRIS = NumberRange.new(3)
local DEFAULT_PORT = Vector3.new(0.1, 0.15, 0.7)

local Tune = table.freeze({
	LIGHT_RANGE = 10,
	LIGHT_BRIGHTNESS = 4,
	LIGHT_BRIGHTNESS_CLOSE = 1.2,
	LIGHT_SECONDS = 0.05,
	-- A landing lights the wall round it too, near the camera only: a light is the dearest thing a shot draws.
	IMPACT_LIGHT_RANGE = 9,
	IMPACT_LIGHT_BRIGHTNESS = 3,
	IMPACT_LIGHT_NEAR = 90,
	-- First person: the muzzle sits a hand from the eye, so its rig is drawn this much smaller and slower, and the
	-- bullet starts this far out (with a streak this share as wide).
	CLOSE_SCALE = 0.45,
	CLOSE_SKIP = 6,
	CLOSE_WIDTH = 0.5,
	-- Studs out of the muzzle a bullet's trail drops its first pixel: the muzzle has its own flash.
	TRAIL_START = 1.5,
	-- Copies of each impact template in turn; a copy's emitters are recoloured per hit, which would recolour the
	-- particles still flying from its last one.
	BURST_SLOTS = 6,
	MAX_BURSTS_PER_FRAME = 8,
	BURST_RANGE = 250,
	-- Budgets, sized for four players on the fastest guns (four miniguns are 67 shots a second, four shotguns fired
	-- together 72 pellets): a bullet is one part for ~0.3 s; thrown bricks are capped by count (and
	-- by distance, and a hit throws fewer of them as the cap fills: thrownPieces.Allowed). Casings have a cap of
	-- their own, so a minigun's brass never takes a wall's bricks.
	FLIGHT_PARTS = 256,
	PIECE_PARTS = 48,
	CASING_PARTS = 48,
	-- How far toward white a hit surface's colour goes for the dust and pixels knocked off it.
	PUFF_LIGHTEN = 0.2,
	DEBRIS_SPEED_MIN = 9,
	DEBRIS_SPEED_MAX = 16,
	DEBRIS_SCATTER = 8,
	DEBRIS_LIFT = 10,
	DEBRIS_OUT = 0.5,
	-- The casing leaves the port up and to the gun's right (the muzzle's space: -Z out of the barrel).
	CASING_DIRECTION = Vector3.new(0.8, 0.65, 0.2).Unit,
	CASING_SPEED_MIN = 9,
	CASING_SPEED_MAX = 13,
})

-- How many particles each layer throws a shot: a range, so no two shots are the same.
export type TLayerCounts = { [string]: NumberRange }
export type TLook = {
	Light: Color3,
	-- Studs a second the bullet flies.
	Speed: number,
	-- The share of Speed a bullet may be faster or slower by, so a shotgun's pellets land over a few frames.
	SpeedJitter: number?,
	-- The muzzle's and the landing's lights reach this many times as far.
	LightScale: number?,
	-- First person, the muzzle's rig is drawn this share of its size (Tune.CLOSE_SCALE without): a big flash a hand
	-- from the eye hides what was shot at.
	CloseScale: number?,
	-- Stud bricks a wall throws a hit, in its colour (3 without).
	Debris: NumberRange?,
	-- Where the casing leaves the gun, in the muzzle's space (+Z is back along the barrel), and how long after the
	-- shot: a bolt or a pump throws it when it is worked.
	Port: Vector3?,
	CasingDelay: number?,
	-- The bullet turns about this axis of its own (Z is its flight) at this many radians a second; 0 flies straight.
	SpinAxis: Vector3,
	SpinSpeed: number,
	-- How long a bullet's streak runs behind it at most, studs between the pixels its trail drops, and radians a second
	-- its Orbit parts turn round its flight line (a bullet with no such parts ignores them).
	Length: number?,
	TrailEvery: number?,
	OrbitSpeed: number?,
	Muzzle: TLayerCounts,
	Impact: TLayerCounts,
	Hit: TLayerCounts,
}

-- What each kit throws a shot. Every other number is on its templates.
local LOOKS: { [string]: TLook } = {
	PistolFx = {
		Port = Vector3.new(0.14, 0.11, 0.8),
		Light = Color3.fromRGB(255, 214, 20),
		Speed = 320,
		TrailEvery = 1.6,
		SpinAxis = Vector3.zAxis,
		SpinSpeed = 0,
		Muzzle = {
			Bloom = ONE,
			Core = ONE,
			RingA = ONE,
			RingB = ONE,
			Pixels = NumberRange.new(6, 9),
			Puffs = NumberRange.new(1, 2),
		},
		Impact = {
			Wash = ONE,
			Core = ONE,
			Frame = ONE,
			Pixels = NumberRange.new(7, 10),
			Puffs = NumberRange.new(2, 3),
		},
		Hit = { Core = ONE, Frame = ONE, Pixels = NumberRange.new(5, 7) },
	},
	-- Crisp and pointed: three rings in a row down the shot, a tight spray, a ring and its echo on the wall.
	RifleFx = {
		Light = Color3.fromRGB(40, 205, 255),
		Speed = 420,
		TrailEvery = 2,
		SpinAxis = Vector3.zAxis,
		SpinSpeed = 0,
		Port = Vector3.new(0.1, 0.15, 1.7),
		Muzzle = {
			Bloom = ONE,
			Core = ONE,
			RingA = ONE,
			RingB = ONE,
			RingC = ONE,
			Pixels = NumberRange.new(5, 7),
			Puffs = NumberRange.new(1, 2),
		},
		Impact = {
			Wash = ONE,
			Core = ONE,
			Frame = ONE,
			Echo = ONE,
			Pixels = NumberRange.new(8, 11),
			Puffs = NumberRange.new(2, 3),
		},
		Hit = { Core = ONE, Frame = ONE, Pixels = NumberRange.new(5, 7) },
	},
	-- One big shot: gates left hanging along its line, the widest landing, the casing thrown with the bolt.
	SniperFx = {
		Light = Color3.fromRGB(178, 96, 255),
		Speed = 700,
		TrailEvery = 2.6,
		SpinAxis = Vector3.zAxis,
		SpinSpeed = 0,
		LightScale = 1.8,
		CloseScale = 0.28,
		Debris = NumberRange.new(5, 6),
		Port = Vector3.new(0.1, 0.2, 1.9),
		CasingDelay = 0.42,
		Muzzle = {
			Bloom = ONE,
			Core = ONE,
			GateA = ONE,
			GateB = ONE,
			GateC = ONE,
			GateD = ONE,
			Pixels = NumberRange.new(12, 16),
			Puffs = NumberRange.new(3, 4),
		},
		Impact = {
			Wash = ONE,
			Core = ONE,
			Frame = ONE,
			Echo = ONE,
			Slab = ONE,
			Pixels = NumberRange.new(14, 18),
			Puffs = NumberRange.new(4, 5),
		},
		Hit = { Core = ONE, Frame = ONE, Slab = ONE, Pixels = NumberRange.new(9, 12) },
	},
	-- A hose, 17 shots a second: most layers are thrown only some shots, so the stream flickers instead of strobing.
	MinigunFx = {
		Light = Color3.fromRGB(255, 62, 30),
		Speed = 380,
		TrailEvery = 1.8,
		SpinAxis = Vector3.zAxis,
		SpinSpeed = 0,
		SpeedJitter = 0.1,
		LightScale = 0.8,
		Debris = NumberRange.new(0, 1),
		Port = Vector3.new(0.15, 0.1, 1.5),
		Muzzle = {
			Bloom = ONE,
			Core = ONE,
			Ring = NumberRange.new(0, 1),
			Pixels = NumberRange.new(1, 3),
			Puffs = NumberRange.new(0, 1),
		},
		Impact = {
			Wash = ONE,
			Core = ONE,
			Frame = NumberRange.new(0, 1),
			Pixels = NumberRange.new(3, 5),
			Puffs = NumberRange.new(0, 1),
		},
		Hit = { Core = ONE, Frame = NumberRange.new(0, 1), Pixels = NumberRange.new(2, 4) },
	},
	-- A blast: everything at the muzzle; a pellet's landing is a small pop, because eighteen land together.
	ShotgunFx = {
		Light = Color3.fromRGB(255, 70, 150),
		Speed = 250,
		TrailEvery = 3,
		SpinAxis = Vector3.zAxis,
		SpinSpeed = 0,
		SpeedJitter = 0.18,
		LightScale = 1.6,
		CloseScale = 0.28,
		Debris = NumberRange.new(0, 1),
		Port = Vector3.new(0.1, 0.15, 1.6),
		CasingDelay = 0.32,
		Muzzle = {
			Bloom = ONE,
			Core = ONE,
			RingA = ONE,
			RingB = ONE,
			Pixels = NumberRange.new(16, 22),
			Puffs = NumberRange.new(4, 6),
		},
		Impact = {
			Core = ONE,
			Frame = NumberRange.new(0, 1),
			Pixels = NumberRange.new(2, 3),
			Puffs = NumberRange.new(0, 1),
		},
		Hit = { Core = ONE, Pixels = NumberRange.new(2, 3) },
	},
}

-- Emitters and the fewest and most each throws, in parallel arrays, so a burst is a plain loop of Emit calls.
type TBurst = {
	Attachment: Attachment,
	Emitters: { ParticleEmitter },
	Least: { number },
	Most: { number },
	Tinted: { ParticleEmitter },
	Light: PointLight,
}

-- Copies of one impact template, taken in turn.
type TBurstPool = { Template: Attachment, Counts: TLayerCounts, Slots: { TBurst }, Next: number }

type TMuzzleRig = {
	Emitters: { ParticleEmitter },
	Least: { number },
	Most: { number },
	Light: PointLight,
	IsClose: boolean,
}

-- The numbers of a bullet that are not on its templates (TLook's).
export type TBulletNumbers = { Length: number?, TrailEvery: number?, OrbitSpeed: number? }

-- What flies: a kit's `Bullet`, one Part, or a Folder of Parts each placed by its CFrame in the bullet's frame (-Z
-- ahead, the head at the origin), with an optional `Trail` Attachment whose emitters drop a pixel every TrailEvery
-- studs and an optional `Streak` (or the kit's own beside it). A part named Orbit... turns round the flight line.
type TBullet = {
	Pool: motorParts.TPool,
	Parts: { BasePart },
	Offsets: { CFrame },
	-- Studs each part sits behind the head: until the bullet has flown that far it waits at the muzzle.
	Behind: { number },
	IsOrbit: { boolean },
	OrbitSpeed: number,
	Streak: BasePart?,
	StreakLength: number,
	-- In name order, each for pixels dropped a step further behind the head (dropTrail).
	Trails: { ParticleEmitter },
	TrailAt: Attachment?,
	-- The first emitter's longest life: a pixel dropped at the head lasts this long.
	TrailLife: number,
	TrailEvery: number,
}

-- A kit's templates, found once: looking one up by name is an engine call, and a shot needs eight.
type TKit = {
	Look: TLook,
	SpeedLeast: number,
	SpeedMost: number,
	LightScale: number,
	CloseScale: number,
	BricksLeast: number,
	BricksMost: number,
	Port: Vector3,
	CasingDelay: number,
	Bullet: TBullet,
	Casing: BasePart?,
	Bricks: { BasePart },
	Muzzle: Attachment?,
	Impact: TBurstPool?,
	Hit: TBurstPool?,
}

type TFlight = {
	Kit: TKit,
	Shape: TBullet,
	-- One a bullet part, in its order; nil once landed, or when the pool could not give them all.
	Movers: { motorParts.TMover }?,
	Streak: motorParts.TMover?,
	-- Studs down the line where the trail's next pixel drops; math.huge with no trail or too far to see.
	NextTrail: number,
	StreakWidth: number,
	-- The streak's length as last written to its mesh.
	Span: number,
	From: Vector3,
	Unit: Vector3,
	Facing: CFrame,
	Length: number,
	Speed: number,
	Born: number,
	Normal: Vector3?,
	Surface: Color3?,
	IsBody: boolean,
	HasLanded: boolean,
	FloorParams: RaycastParams?,
}

local random = Random.new()
local flightParts = motorParts.NewPool("GunFxShots", Tune.FLIGHT_PARTS)
-- A bench's bullets: a pool never frees a part for another template, so a bench sharing the game's would leave the
-- game's guns nothing to draw with.
local benchParts = motorParts.NewPool("GunFxBenchShots", Tune.FLIGHT_PARTS)
local pieces = thrownPieces.NewPool("GunFxBits", Tune.PIECE_PARTS)
local casings = thrownPieces.NewPool("GunFxCasings", Tune.CASING_PARTS)
-- Casings a bolt or a pump has still to throw, in no order: each kit waits its own time.
local dueCasings: { { At: number, Muzzle: Attachment, Kit: TKit } } = {}
local kits: { [string]: TKit } = {}
-- A muzzle is one gun's, and a gun has one kit.
local rigs: { [Attachment]: TMuzzleRig } = {}
local flights: { TFlight } = {}
local lightOffAt: { [PointLight]: number } = {}
local tints: { [number]: ColorSequence } = {}
local burstsThisFrame = 0
local warned: { [string]: boolean } = {}

-- Stands `look` for `kit` (its templates at ReplicatedStorage.Effects.<kit>): a bench showing a look the game does
-- not draw.
function gunFx.SetLook(kit: string, look: TLook)
	-- The same look again keeps the kit and the bursts it has made.
	if LOOKS[kit] == look then return end
	LOOKS[kit] = look
	kits[kit] = nil
end

local function partNamed(templates: Instance, name: string): BasePart?
	local child = templates:FindFirstChild(name)
	return if child and child:IsA("BasePart") then child else nil
end

local function attachmentNamed(templates: Instance, name: string): Attachment?
	local child = templates:FindFirstChild(name)
	return if child and child:IsA("Attachment") then child else nil
end

local function newPool(templates: Instance, name: string, counts: TLayerCounts): TBurstPool?
	local template = attachmentNamed(templates, name)
	return if template then { Template = template, Counts = counts, Slots = {}, Next = 1 } else nil
end

-- A bullet Folder's parts, streak and trail into `shape`.
local function readParts(shape: TBullet, bullet: Instance)
	local count = 0
	for _, child in bullet:GetChildren() do
		if child:IsA("BasePart") and child.Name == "Streak" then
			shape.Streak = child
		elseif child:IsA("BasePart") then
			count += 1
			local offset = child.CFrame
			shape.Parts[count] = child
			shape.Offsets[count] = offset
			shape.Behind[count] = math.max(offset.Position.Z, 0)
			shape.IsOrbit[count] = string.sub(child.Name, 1, 5) == "Orbit"
		elseif child:IsA("Attachment") and child.Name == "Trail" then
			-- One attachment a bullet shape, moved to each pixel's spot before an emitter throws it there.
			local at = child:Clone()
			at.Parent = Workspace.Terrain
			shape.TrailAt = at
			local trails = shape.Trails
			for _, emitter in at:GetChildren() do
				if emitter:IsA("ParticleEmitter") then trails[#trails + 1] = emitter end
			end
			table.sort(trails, function(a, b)
				return a.Name < b.Name
			end)
			if trails[1] then shape.TrailLife = trails[1].Lifetime.Max end
		end
	end
end

local function readBullet(
	bullet: Instance?,
	streak: BasePart?,
	pool: motorParts.TPool,
	numbers: TBulletNumbers
): TBullet
	local shape: TBullet = {
		Pool = pool,
		Parts = {},
		Offsets = {},
		Behind = {},
		IsOrbit = {},
		OrbitSpeed = numbers.OrbitSpeed or 0,
		Streak = streak,
		StreakLength = 0,
		Trails = {},
		TrailAt = nil,
		TrailLife = 0,
		TrailEvery = numbers.TrailEvery or math.huge,
	}
	if bullet and bullet:IsA("BasePart") then
		shape.Parts[1], shape.Offsets[1], shape.Behind[1], shape.IsOrbit[1] = bullet, CFrame.identity, 0, false
	elseif bullet then
		readParts(shape, bullet)
	end
	-- With no streak the flight ends where the bullet lands.
	if shape.Streak then shape.StreakLength = numbers.Length or 0 end

	return shape
end

-- The kit named `name`; nil (said once) while its templates or its look are missing. A miss is asked again next shot,
-- so templates that reach the client late are still found.
local function kitOf(name: string): TKit?
	local kit = kits[name]
	if kit then return kit end

	local look = LOOKS[name]
	local templates = Effects:FindFirstChild(name)
	if not look or not templates then
		if not warned[name] then
			warned[name] = true
			warn(`[gunFx] no ReplicatedStorage.Effects.{name} or no look for it; this gun draws the plain tracers`)
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

	local jitter = look.SpeedJitter or 0
	local debrisCount = look.Debris or DEFAULT_DEBRIS
	local numbers = { Length = look.Length, TrailEvery = look.TrailEvery, OrbitSpeed = look.OrbitSpeed }
	kit = {
		Look = look,
		SpeedLeast = look.Speed * (1 - jitter),
		SpeedMost = look.Speed * (1 + jitter),
		LightScale = look.LightScale or 1,
		CloseScale = look.CloseScale or Tune.CLOSE_SCALE,
		BricksLeast = debrisCount.Min,
		BricksMost = debrisCount.Max,
		Port = look.Port or DEFAULT_PORT,
		CasingDelay = look.CasingDelay or 0,
		Bullet = readBullet(templates:FindFirstChild("Bullet"), partNamed(templates, "Streak"), flightParts, numbers),
		Casing = partNamed(templates, "Casing"),
		Bricks = bricks,
		Muzzle = attachmentNamed(templates, "Muzzle"),
		Impact = newPool(templates, "Impact", look.Impact),
		Hit = newPool(templates, "Hit", look.Hit),
	}
	kits[name] = kit
	return kit
end

-- Bench only (VFX.md 1): the kit `name`, drawn as `baseName`'s with its bullet read from `bullet` (a Folder laid out
-- like a kit's `Bullet`) and `numbers`. Put up again, a bench keeps what it read: a trail's attachment is a clone.
function gunFx.SetBullet(name: string, baseName: string, bullet: Instance, numbers: TBulletNumbers)
	if kits[name] then return end
	local base = kitOf(baseName)
	if not base then return end

	local kit = table.clone(base)
	kit.Bullet = readBullet(bullet, nil, benchParts, numbers)
	kits[name] = kit
end

local function distanceFromCamera(at: Vector3): number
	return (Workspace.CurrentCamera.CFrame.Position - at).Magnitude
end

-- `surface`, lightened, as an emitter's Color. Kept by the colour's bytes: a Color3 used as a table key is its
-- identity, so two equal colours would be two keys and nothing would ever be found again.
local function tintOf(surface: Color3): ColorSequence
	local key = math.round(surface.R * 255) * 65536 + math.round(surface.G * 255) * 256 + math.round(surface.B * 255)
	local sequence = tints[key]
	if not sequence then
		sequence = ColorSequence.new(surface:Lerp(WHITE, Tune.PUFF_LIGHTEN))
		tints[key] = sequence
	end

	return sequence
end

local function scaleSequence(sequence: NumberSequence, scale: number): NumberSequence
	local keys = table.create(#sequence.Keypoints)
	for i, key in sequence.Keypoints do
		keys[i] = NumberSequenceKeypoint.new(key.Time, key.Value * scale, key.Envelope * scale)
	end

	return NumberSequence.new(keys)
end

-- Every emitter under `attachment` whose layer `counts` names, with the fewest and most it throws.
local function collect(
	attachment: Attachment,
	counts: TLayerCounts,
	emitters: { ParticleEmitter },
	least: { number },
	most: { number }
)
	for _, child in attachment:GetChildren() do
		local count = counts[child.Name]
		if not count or not child:IsA("ParticleEmitter") then continue end
		emitters[#emitters + 1] = child
		least[#least + 1] = count.Min
		most[#most + 1] = count.Max
	end
end

local function emit(emitters: { ParticleEmitter }, least: { number }, most: { number })
	for i, emitter in emitters do
		local low, high = least[i], most[i]
		local count = if low == high then low else random:NextInteger(low, high)
		if count > 0 then emitter:Emit(count) end
	end
end

local function newLight(color: Color3, range: number, parent: Instance): PointLight
	local light = Instance.new("PointLight")
	light.Name = "GunFxLight"
	light.Color = color
	light.Range = range
	light.Shadows = false
	light.Enabled = false
	light.Parent = parent
	return light
end

local function flashLight(light: PointLight, brightness: number, now: number)
	light.Brightness = brightness
	light.Enabled = true
	lightOffAt[light] = now + Tune.LIGHT_SECONDS
end

-- The kit's Muzzle attachment cloned onto the gun beside `muzzle`, built once a muzzle.
local function buildRig(muzzle: Attachment, template: Attachment, kit: TKit, isClose: boolean): TMuzzleRig
	local copy = template:Clone()
	copy.CFrame = muzzle.CFrame * template.CFrame
	if isClose then
		local scale = kit.CloseScale
		for _, emitter in copy:GetChildren() do
			if not emitter:IsA("ParticleEmitter") then continue end
			emitter.Size = scaleSequence(emitter.Size, scale)
			emitter.Speed = NumberRange.new(emitter.Speed.Min * scale, emitter.Speed.Max * scale)
			emitter.Acceleration *= scale
		end
	end
	copy.Parent = muzzle.Parent

	local emitters, least, most = {}, {}, {}
	collect(copy, kit.Look.Muzzle, emitters, least, most)
	return {
		Emitters = emitters,
		Least = least,
		Most = most,
		Light = newLight(kit.Look.Light, Tune.LIGHT_RANGE * kit.LightScale, muzzle),
		IsClose = isClose,
	}
end

local function ejectCasing(muzzle: Attachment, kit: TKit)
	local template = kit.Casing
	if not template then return end
	local frame = muzzle.WorldCFrame
	local position = frame * kit.Port
	if thrownPieces.Allowed(casings, 1, distanceFromCamera(position)) == 0 then return end

	local velocity = frame:VectorToWorldSpace(Tune.CASING_DIRECTION)
		* random:NextNumber(Tune.CASING_SPEED_MIN, Tune.CASING_SPEED_MAX)
	thrownPieces.Throw(casings, template, nil, position, velocity, thrownPieces.FloorUnder(position, gunFx.FloorParams))
end

-- A muzzle that is gone has no rig: its casing is dropped.
local function ejectDueCasings(now: number)
	for index = #dueCasings, 1, -1 do
		local due = dueCasings[index]
		if due.At > now then continue end
		dueCasings[index] = dueCasings[#dueCasings]
		dueCasings[#dueCasings] = nil
		if rigs[due.Muzzle] then ejectCasing(due.Muzzle, due.Kit) end
	end
end

-- The flash, light and casing of one shot out of `muzzle`. False when the kit's templates are not in the place.
function gunFx.Muzzle(kitName: string, muzzle: Attachment, isClose: boolean): boolean
	local kit = kitOf(kitName)
	local template = if kit then kit.Muzzle else nil
	if not kit or not template then return false end

	local rig = rigs[muzzle]
	if not rig then
		rig = buildRig(muzzle, template, kit, isClose)
		rigs[muzzle] = rig
		muzzle.Destroying:Once(function()
			rigs[muzzle] = nil
		end)
	end

	local now = os.clock()
	emit(rig.Emitters, rig.Least, rig.Most)
	flashLight(rig.Light, if rig.IsClose then Tune.LIGHT_BRIGHTNESS_CLOSE else Tune.LIGHT_BRIGHTNESS, now)
	if isClose then return true end

	if kit.CasingDelay > 0 then
		dueCasings[#dueCasings + 1] = { At = now + kit.CasingDelay, Muzzle = muzzle, Kit = kit }
	else
		ejectCasing(muzzle, kit)
	end

	return true
end

-- What a ray hit, as a colour: a part's own, or a terrain material's.
function gunFx.SurfaceColor(result: RaycastResult): Color3
	local hit = result.Instance
	if hit:IsA("Terrain") then return hit:GetMaterialColor(result.Material) end
	return if hit:IsA("BasePart") then hit.Color else Color3.new(0.7, 0.7, 0.7)
end

local function newBurst(pool: TBurstPool, kit: TKit): TBurst
	local copy = pool.Template:Clone()
	local emitters, least, most, tinted = {}, {}, {}, {}
	collect(copy, pool.Counts, emitters, least, most)
	for _, emitter in emitters do
		if TINTED[emitter.Name] then tinted[#tinted + 1] = emitter end
	end

	copy.Parent = Workspace.Terrain
	return {
		Attachment = copy,
		Emitters = emitters,
		Least = least,
		Most = most,
		Tinted = tinted,
		Light = newLight(kit.Look.Light, Tune.IMPACT_LIGHT_RANGE * kit.LightScale, copy),
	}
end

-- The pool's next copy in turn, made on its first use.
local function takeBurst(pool: TBurstPool, kit: TKit): TBurst
	local slot = pool.Next
	pool.Next = slot % Tune.BURST_SLOTS + 1
	local burst = pool.Slots[slot]
	if not burst then
		burst = newBurst(pool, kit)
		pool.Slots[slot] = burst
	end

	return burst
end

-- A burst's frame: +Y on `up`, the way its layers throw.
local function facing(position: Vector3, up: Vector3): CFrame
	local side = if math.abs(up.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis
	local right = side:Cross(up).Unit
	return CFrame.fromMatrix(position, right, up)
end

-- `count` of `bricks`, in `color`, thrown out along `out` from `at`.
local function scatter(
	bricks: { BasePart },
	count: number,
	color: Color3,
	at: Vector3,
	out: Vector3,
	params: RaycastParams?
)
	if count == 0 or #bricks == 0 then return end

	local from = at + out * Tune.DEBRIS_OUT
	local floor = thrownPieces.FloorUnder(from, params)
	for _ = 1, count do
		local side = random:NextUnitVector()
		side -= out * side:Dot(out)
		local velocity = out * random:NextNumber(Tune.DEBRIS_SPEED_MIN, Tune.DEBRIS_SPEED_MAX)
			+ side * random:NextNumber(0, Tune.DEBRIS_SCATTER)
			+ Vector3.yAxis * Tune.DEBRIS_LIFT
		thrownPieces.Throw(pieces, bricks[random:NextInteger(1, #bricks)], color, from, velocity, floor)
	end
end

local function land(flight: TFlight, now: number)
	if burstsThisFrame >= Tune.MAX_BURSTS_PER_FRAME then return end
	local kit = flight.Kit
	local pool = if flight.IsBody then kit.Hit else kit.Impact
	local out = if flight.IsBody then -flight.Unit else flight.Normal
	if not pool or not out then return end
	local at = flight.From + flight.Unit * flight.Length
	local distance = distanceFromCamera(at)
	if distance > Tune.BURST_RANGE then return end

	burstsThisFrame += 1
	local burst = takeBurst(pool, kit)
	burst.Attachment.CFrame = facing(at, out)
	local surface = flight.Surface
	if surface then
		local tint = tintOf(surface)
		for _, emitter in burst.Tinted do
			emitter.Color = tint
		end
	end
	emit(burst.Emitters, burst.Least, burst.Most)
	if distance <= Tune.IMPACT_LIGHT_NEAR then flashLight(burst.Light, Tune.IMPACT_LIGHT_BRIGHTNESS, now) end
	if flight.IsBody or not surface then return end

	local wanted = random:NextInteger(kit.BricksLeast, kit.BricksMost)
	local count = thrownPieces.Allowed(pieces, wanted, distance)
	scatter(kit.Bricks, count, surface, at, out, flight.FloorParams)
end

-- Every part of `shape` from the pool, or none: a bullet missing a piece reads as a different bullet.
local function takeMovers(shape: TBullet): { motorParts.TMover }?
	local parts = shape.Parts
	if #parts == 0 then return nil end

	local pool = shape.Pool
	local movers = table.create(#parts)
	for i, part in parts do
		local mover = motorParts.Take(pool, part)
		if not mover then
			for _, taken in movers do
				motorParts.Release(pool, taken)
			end
			return nil
		end
		movers[i] = mover
	end

	return movers
end

-- One bullet from `from` to `to`: its parts and streak, and when it gets there, an impact on a surface with `normal`
-- (and `surface`'s colour), a burst on a body, or nothing at the end of its range. False when the kit's templates are
-- not in the place.
function gunFx.Shot(
	kitName: string,
	from: Vector3,
	to: Vector3,
	normal: Vector3?,
	surface: Color3?,
	isBody: boolean,
	isClose: boolean
): boolean
	local kit = kitOf(kitName)
	if not kit then return false end

	local whole = to - from
	if isClose and whole.Magnitude > Tune.CLOSE_SKIP + 0.5 then
		from += whole.Unit * Tune.CLOSE_SKIP
	end
	local offset = to - from
	local length = offset.Magnitude
	if length < 0.05 then return true end

	local shape = kit.Bullet
	local streak = if shape.Streak then motorParts.Take(shape.Pool, shape.Streak) else nil
	local unit = offset / length
	local hasTrail = shape.TrailLife > 0 and distanceFromCamera(from) <= Tune.BURST_RANGE
	flights[#flights + 1] = {
		Kit = kit,
		Shape = shape,
		Movers = takeMovers(shape),
		Streak = streak,
		NextTrail = if hasTrail then Tune.TRAIL_START else math.huge,
		StreakWidth = if streak then streak.Width * (if isClose then Tune.CLOSE_WIDTH else 1) else 0,
		Span = 0,
		From = from,
		Unit = unit,
		Facing = CFrame.lookAt(Vector3.zero, unit),
		Length = length,
		Speed = random:NextNumber(kit.SpeedLeast, kit.SpeedMost),
		Born = os.clock() - LEAD,
		Normal = normal,
		Surface = surface,
		IsBody = isBody,
		HasLanded = false,
		FloorParams = gunFx.FloorParams,
	}
	return true
end

-- The trail's pixels the bullet has passed since last frame, each left where it dropped.
local function dropTrail(flight: TFlight, shape: TBullet, head: number)
	local nextAt = flight.NextTrail
	if nextAt > head then return end
	local trails, at = shape.Trails, shape.TrailAt
	local count = #trails
	if count == 0 or not at then return end

	-- A frame drops several pixels at once, all born the same age, so a trail that shrank only with age would taper
	-- in steps. A pixel dropped further behind the head goes to an emitter that starts it as small and lives as
	-- little as one dropped that much earlier would: the taper is by distance, like the Train's squares.
	local from, unit, every = flight.From, flight.Unit, shape.TrailEvery
	local perStud = count / (flight.Speed * shape.TrailLife)
	while nextAt <= head do
		at.Position = from + unit * nextAt
		trails[math.min(math.floor((head - nextAt) * perStud) + 1, count)]:Emit(1)
		nextAt += every
	end
	flight.NextTrail = nextAt
end

-- The bullet goes to where it lands and the streak runs on into that point, so it closes rather than vanishing.
local function stepFlights(now: number)
	for index = #flights, 1, -1 do
		local flight = flights[index]
		local look = flight.Kit.Look
		local age = now - flight.Born
		local tip = age * flight.Speed
		local length = flight.Length
		local shape = flight.Shape
		local from, unit = flight.From, flight.Unit
		local head = math.min(tip, length)
		dropTrail(flight, shape, head)
		if not flight.HasLanded and tip >= length then
			flight.HasLanded = true
			local movers = flight.Movers
			if movers then
				for _, mover in movers do
					motorParts.Release(shape.Pool, mover)
				end
				flight.Movers = nil
			end
			land(flight, now)
		end

		local tail = tip - shape.StreakLength
		if tail >= length then
			if flight.Streak then motorParts.Release(shape.Pool, flight.Streak) end
			flights[index] = flights[#flights]
			flights[#flights] = nil
			continue
		end

		local movers = flight.Movers
		if movers then
			local facingNow = if look.SpinSpeed ~= 0
				then flight.Facing * CFrame.fromAxisAngle(look.SpinAxis, age * look.SpinSpeed)
				else flight.Facing
			local at = from + unit * head
			local offsets, behind, isOrbit = shape.Offsets, shape.Behind, shape.IsOrbit
			local orbit = if shape.OrbitSpeed ~= 0
				then CFrame.fromAxisAngle(Vector3.zAxis, age * shape.OrbitSpeed)
				else CFrame.identity
			for i, mover in movers do
				local offset = if isOrbit[i] then orbit * offsets[i] else offsets[i]
				-- A part further back than the bullet has flown waits at the muzzle, not behind the gun.
				local held = math.max(behind[i] - head, 0)
				mover.Joint.Transform = facingNow * offset + (at + unit * held)
			end
		end

		local streak = flight.Streak
		local mesh = if streak then streak.Mesh else nil
		if streak and mesh then
			local back = math.max(tail, 0)
			local span = math.max(head - back, 0.01)
			-- Mid flight the streak holds its length: only its ends write the mesh.
			if span ~= flight.Span then
				flight.Span = span
				mesh.Scale = Vector3.new(flight.StreakWidth, flight.StreakWidth, span)
			end
			streak.Joint.Transform = flight.Facing + (from + unit * (back + span / 2))
		end
	end
end

function gunFx.Step()
	burstsThisFrame = 0
	local now = os.clock()
	for light, offAt in lightOffAt do
		if now < offAt then continue end
		light.Enabled = false
		lightOffAt[light] = nil
	end

	stepFlights(now)
	ejectDueCasings(now)
	-- Read each frame: a bench swaps the floor while it stands.
	pieces.FloorParams = gunFx.FloorParams
	casings.FloorParams = gunFx.FloorParams
	thrownPieces.Step(pieces)
	thrownPieces.Step(casings)
end

return gunFx
