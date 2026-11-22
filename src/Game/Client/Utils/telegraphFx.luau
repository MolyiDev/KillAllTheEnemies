-- What a ground warning throws besides its floor pieces, in the house look (VFX.md 30): glowing pixels rising off it
-- while it winds up, a square ring as it appears, and where it lands a square shock, a pool of light, pixels shooting
-- out of the floor and the floor's own stud bricks knocked loose (GlobalClient/Utils/thrownPieces). TelegraphController says
-- where, from points it picks on the warning's own floor, so nothing is drawn past what the hit covers. The look is on
-- templates at ReplicatedStorage.Effects.TelegraphFx, a place instance, not Rojo, made by Assets/effects/telegraphs
-- (its README.md). No --!native: this is engine calls end to end.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local thrownPieces = require(script.Parent.Parent.Parent.GlobalClient.Utils.thrownPieces)

local Effects = ReplicatedStorage:WaitForChild("Effects")

local telegraphFx = {}

-- The pixels' colours: an ordinary enemy's warning and a boss's (TelegraphController's COLOR and BOSS_COLOR, which
-- are brightened past 1 for a Texture; a particle's colour stops at 1, so the brightening is the emitter's).
telegraphFx.ORDINARY = 1
telegraphFx.BOSS = 2

local KIT = "TelegraphFx"
local PALETTES = table.freeze({ Color3.fromRGB(255, 40, 125), Color3.fromRGB(150, 50, 255) })
-- The layers each template draws in the warning's colour, which a copy takes from its palette.
local RECOLORED: { [string]: { string } } = table.freeze({
	Mote = { "Pixels" },
	Ping = { "Frame" },
	Ground = { "Shock" },
	Blast = { "Core" },
	Spray = { "Pixels" },
})

local Tune = table.freeze({
	-- Pixels a frame over every warning (motes, sprays, fizzles): past it the rest are not drawn this frame.
	EMITS_PER_FRAME = 64,
	-- Landings a frame, each a few layers and a light.
	LANDS_PER_FRAME = 6,
	-- Everything is drawn in full this near the camera, thinning to nothing at RANGE.
	NEAR = 90,
	RANGE = 220,
	-- Pieces in the air at once over every warning. A landing throws fewer as this fills.
	PIECE_PARTS = 72,
	-- Pieces fly up at LIFT and out from where the blow came from at OUT, studs a second.
	LIFT_MIN = 14,
	LIFT_MAX = 26,
	OUT_MIN = 2,
	OUT_MAX = 9,
	-- A landing lights the floor round it, near the camera only, and fades so it never blinks off.
	LIGHT_NEAR = 120,
	LIGHT_SECONDS = 0.18,
	LIGHT_BRIGHTNESS = 4,
	LIGHT_RANGE_PER_RADIUS = 1.6,
	LIGHT_RANGE_MAX = 40,
	LIGHT_LIFT = 2,
	LIGHTS = 4,
	-- Copies of each scaled or recoloured template, taken in turn: a copy's new size or colour is also what still
	-- flies from its last throw.
	SLOTS = 4,
	-- A scaled layer is sized for a radius rounded to this, so a crowd of one size never rebuilds a sequence.
	RADIUS_STEP = 0.5,
	-- An explosion's bloom and heart, and a warning's opening ring, stop growing past these radii: GPU fill is the
	-- screen covered (VFX.md 5), and the boss's 40-stud shockwave opened a square ring as wide as the arena.
	BLAST_RADIUS_MAX = 14,
	PING_RADIUS_MAX = 12,
	-- Over the floor, an explosion's heart, and the white flecks it throws all round.
	BLAST_LIFT = 1.5,
	FLECKS_MIN = 12,
	FLECKS_MAX = 18,
	-- Pixels are born white-hot for this share of their life, then the warning's colour.
	HOT = Color3.fromRGB(255, 248, 215),
	HOT_SHARE = 0.12,
	-- Dust is the floor's colour this far toward white: paint, not light.
	DUST_LIGHTEN = 0.35,
	-- Every this many spray points throws a puff of dust as well.
	DUST_EVERY = 2,
})

-- One copy of a template under Workspace.Terrain, where an attachment's CFrame is its world CFrame: its emitters by
-- layer name, and the radius and dust it was last sized and coloured for.
type TCopy = {
	Attachment: Attachment,
	Emitters: { [string]: ParticleEmitter },
	Radius: number,
	Dust: number,
}

-- Copies of one template in one palette, taken in turn, made on first use. Sizes holds each layer's Size sequence
-- per radius (the template's are for radius 1).
type TPool = {
	Template: Attachment,
	Color: ColorSequence,
	Copies: { TCopy },
	Next: number,
	Sizes: { [number]: { [string]: NumberSequence } },
}

type TLight = { Attachment: Attachment, Light: PointLight, OffAt: number }

type TKit = {
	Bricks: { BasePart },
	-- Template name -> palette -> pool.
	Pools: { [string]: { TPool } },
}

local random = Random.new()
local pieces = thrownPieces.NewPool("TelegraphPieces", Tune.PIECE_PARTS)
local kit: TKit? = nil
local hasWarned = false
local lights: { TLight } = {}
local nextLight = 1
local dustColors: { [number]: ColorSequence } = {}
-- Read once a frame (BeginFrame).
local cameraPosition = Vector3.zero
local now = 0
local emitsLeft = 0
local landsLeft = 0

-- The kit's templates; nil (said once) while they are not in the place, when the warnings are drawn without them. A
-- miss is asked again, so templates that reach the client late are still found.
local function kitOf(): TKit?
	if kit then return kit end

	local templates = Effects:FindFirstChild(KIT)
	if not templates then
		if not hasWarned then
			hasWarned = true
			warn(`[telegraphFx] no ReplicatedStorage.Effects.{KIT}; ground warnings throw no pixels or bricks`)
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

	local pools = {}
	for _, template in templates:GetChildren() do
		if not template:IsA("Attachment") then continue end
		local byPalette = table.create(#PALETTES)
		for palette, color in PALETTES do
			byPalette[palette] = {
				Template = template,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Tune.HOT),
					ColorSequenceKeypoint.new(Tune.HOT_SHARE, color),
					ColorSequenceKeypoint.new(1, color),
				}),
				Copies = {},
				Next = 1,
				Sizes = {},
			}
		end
		pools[template.Name] = byPalette
	end

	local found = { Bricks = bricks, Pools = pools }
	kit = found
	return found
end

local function newCopy(pool: TPool): TCopy
	local attachment = pool.Template:Clone()
	local emitters = {}
	for _, child in attachment:GetChildren() do
		if child:IsA("ParticleEmitter") then emitters[child.Name] = child end
	end

	local recolored = RECOLORED[attachment.Name]
	if recolored then
		for _, name in recolored do
			local emitter = emitters[name]
			if emitter then emitter.Color = pool.Color end
		end
	end

	attachment.Parent = Workspace.Terrain
	return { Attachment = attachment, Emitters = emitters, Radius = 1, Dust = -1 }
end

-- The pool's next copy (one only, when nothing it draws is scaled or recoloured per throw).
local function take(pool: TPool, slots: number): TCopy
	local slot = pool.Next
	pool.Next = slot % slots + 1
	local copy = pool.Copies[slot]
	if not copy then
		copy = newCopy(pool)
		pool.Copies[slot] = copy
	end

	return copy
end

local function poolOf(name: string, palette: number): TPool?
	local found = kitOf()
	if not found then return nil end
	local byPalette = found.Pools[name]
	return if byPalette then byPalette[palette] else nil
end

-- Every layer of `copy` sized for `radius` (rounded to RADIUS_STEP), the sequences kept on the pool.
local function sizeFor(pool: TPool, copy: TCopy, radius: number)
	local rounded = math.max(math.round(radius / Tune.RADIUS_STEP), 1) * Tune.RADIUS_STEP
	if copy.Radius == rounded then return end
	copy.Radius = rounded

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
end

-- How much of what a warning throws is drawn at `position`: all of it near the camera, none past RANGE.
function telegraphFx.Share(position: Vector3): number
	local distance = (position - cameraPosition).Magnitude
	if distance <= Tune.NEAR then return 1 end
	return math.max(1 - (distance - Tune.NEAR) / (Tune.RANGE - Tune.NEAR), 0)
end

-- One rising pixel at each of the first `count` of `points`, while this frame's pixels last.
function telegraphFx.Motes(palette: number, points: { Vector3 }, count: number)
	local pool = poolOf("Mote", palette)
	if not pool or count <= 0 or emitsLeft <= 0 then return end

	local copy = take(pool, 1)
	local attachment, emitter = copy.Attachment, copy.Emitters.Pixels
	local drawn = math.min(count, emitsLeft)
	for i = 1, drawn do
		attachment.Position = points[i]
		emitter:Emit(1)
	end
	emitsLeft -= drawn
end

-- A warning appears: a square ring opening flat on the floor at `center`, sized to stay inside a circle of `radius`.
function telegraphFx.Ping(palette: number, center: Vector3, radius: number)
	local pool = poolOf("Ping", palette)
	if not pool or telegraphFx.Share(center) <= 0 then return end

	local copy = take(pool, Tune.SLOTS)
	sizeFor(pool, copy, math.min(radius, Tune.PING_RADIUS_MAX))
	copy.Attachment.Position = center
	copy.Emitters.Frame:Emit(1)
end

local function flashLight(color: Color3, position: Vector3, radius: number)
	if (position - cameraPosition).Magnitude > Tune.LIGHT_NEAR then return end

	local slot = lights[nextLight]
	if not slot then
		local attachment = Instance.new("Attachment")
		attachment.Name = "TelegraphLight"
		local light = Instance.new("PointLight")
		light.Shadows = false
		light.Enabled = false
		light.Parent = attachment
		attachment.Parent = Workspace.Terrain
		slot = { Attachment = attachment, Light = light, OffAt = 0 }
		lights[nextLight] = slot
	end
	nextLight = nextLight % Tune.LIGHTS + 1

	local light = slot.Light
	slot.Attachment.Position = position + Vector3.new(0, Tune.LIGHT_LIFT, 0)
	light.Color = color
	light.Range = math.min(radius * Tune.LIGHT_RANGE_PER_RADIUS, Tune.LIGHT_RANGE_MAX)
	light.Brightness = Tune.LIGHT_BRIGHTNESS
	light.Enabled = true
	slot.OffAt = now + Tune.LIGHT_SECONDS
end

-- A warning lands at `center`: the floor lit for a moment and, when `hasShock`, a fat square shock and a pool of
-- light flat on it inside a circle of `radius`; an explosion's white-hot heart over it. Returns whether it was
-- drawn: past this frame's landings, or out of sight, the sprays and bricks that go with it are skipped too.
function telegraphFx.Land(palette: number, center: Vector3, radius: number, hasShock: boolean, isExplosion: boolean)
	if landsLeft <= 0 or telegraphFx.Share(center) <= 0 then return false end
	landsLeft -= 1

	flashLight(PALETTES[palette], center, radius)
	local ground = if hasShock then poolOf("Ground", palette) else nil
	if ground then
		local copy = take(ground, Tune.SLOTS)
		sizeFor(ground, copy, radius)
		copy.Attachment.Position = center
		copy.Emitters.Wash:Emit(1)
		copy.Emitters.Shock:Emit(1)
	end

	local blast = if isExplosion then poolOf("Blast", palette) else nil
	if blast then
		local copy = take(blast, Tune.SLOTS)
		sizeFor(blast, copy, math.min(radius, Tune.BLAST_RADIUS_MAX))
		copy.Attachment.Position = center + Vector3.new(0, Tune.BLAST_LIFT, 0)
		local emitters = copy.Emitters
		emitters.Bloom:Emit(1)
		emitters.Core:Emit(1)
		emitters.Flecks:Emit(random:NextInteger(Tune.FLECKS_MIN, Tune.FLECKS_MAX))
	end
	return true
end

-- `dust` lightened, as an emitter's Color. Kept by the colour's bytes: a Color3 is no table key (VFX.md 30).
local function dustOf(dust: Color3): (ColorSequence, number)
	local key = math.round(dust.R * 255) * 65536 + math.round(dust.G * 255) * 256 + math.round(dust.B * 255)
	local sequence = dustColors[key]
	if not sequence then
		sequence = ColorSequence.new(dust:Lerp(Color3.new(1, 1, 1), Tune.DUST_LIGHTEN))
		dustColors[key] = sequence
	end

	return sequence, key
end

-- Pixels shooting up out of the floor at each of the first `count` of `points`, and the floor's dust (`dust`) at
-- every DUST_EVERY-th, while this frame's pixels last.
function telegraphFx.Spray(palette: number, points: { Vector3 }, count: number, dust: Color3)
	local pool = poolOf("Spray", palette)
	if not pool or count <= 0 or emitsLeft <= 0 then return end

	local copy = take(pool, Tune.SLOTS)
	local sequence, key = dustOf(dust)
	local pixels, puffs = copy.Emitters.Pixels, copy.Emitters.Puffs
	if copy.Dust ~= key then
		copy.Dust = key
		puffs.Color = sequence
	end

	local attachment = copy.Attachment
	local drawn = math.min(count, emitsLeft)
	for i = 1, drawn do
		attachment.Position = points[i]
		pixels:Emit(1)
		if i % Tune.DUST_EVERY == 0 then puffs:Emit(1) end
	end
	emitsLeft -= drawn
end

-- Grey pixels sinking off the first `count` of `points`: a warning taken back.
function telegraphFx.Fizzle(points: { Vector3 }, count: number)
	local pool = poolOf("Fizzle", telegraphFx.ORDINARY)
	if not pool or count <= 0 or emitsLeft <= 0 then return end

	local copy = take(pool, 1)
	local attachment, emitter = copy.Attachment, copy.Emitters.Pixels
	local drawn = math.min(count, emitsLeft)
	for i = 1, drawn do
		attachment.Position = points[i]
		emitter:Emit(1)
	end
	emitsLeft -= drawn
end

-- A stud brick knocked out of the floor at each of the first `count` of `points` (on a floor at `floors[i]`, in
-- `colors[i]`), thrown up and away from `from`. Fewer as the pool fills, none far from the camera.
function telegraphFx.Bricks(points: { Vector3 }, floors: { number }, colors: { Color3 }, count: number, from: Vector3)
	local found = kitOf()
	if not found or count == 0 then return end
	local bricks = found.Bricks
	local allowed = thrownPieces.Allowed(pieces, count, (from - cameraPosition).Magnitude)
	if allowed == 0 or #bricks == 0 then return end

	for i = 1, allowed do
		local point = points[i]
		local flat = Vector3.new(point.X - from.X, 0, point.Z - from.Z)
		-- A brick right under where the blow came from (a rare draw) flies out along +X: in a burst nobody sees which.
		local out = if flat.Magnitude > 0.1 then flat.Unit else Vector3.xAxis
		local velocity = out * random:NextNumber(Tune.OUT_MIN, Tune.OUT_MAX)
			+ Vector3.new(0, random:NextNumber(Tune.LIFT_MIN, Tune.LIFT_MAX), 0)
		thrownPieces.Throw(pieces, bricks[random:NextInteger(1, #bricks)], colors[i], point, velocity, floors[i])
	end
end

-- At the top of the frame: the camera, this frame's budgets, the pieces in the air and the lights fading.
function telegraphFx.BeginFrame()
	cameraPosition = Workspace.CurrentCamera.CFrame.Position
	now = os.clock()
	emitsLeft = Tune.EMITS_PER_FRAME
	landsLeft = Tune.LANDS_PER_FRAME
	thrownPieces.Step(pieces)

	for _, slot in lights do
		local light = slot.Light
		if not light.Enabled then continue end
		local left = slot.OffAt - now
		if left <= 0 then
			light.Enabled = false
			continue
		end
		light.Brightness = Tune.LIGHT_BRIGHTNESS * left / Tune.LIGHT_SECONDS
	end
end

return telegraphFx
