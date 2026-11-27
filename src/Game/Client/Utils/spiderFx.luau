-- The Giant Spider as it is seen, placeholders in the house look until its own kit is made: red neon gashes its blades
-- cut in the floor, sparks off steel, web globs that splat into sticky patches, the silk line it hangs from, its egg
-- sacs bursting, the daze after its drop. What comes off the floor is the T-Rex's kit (trexFx), already the floor's
-- own dust and bricks. BossController and BossIntroController say when and where and step it once a frame; the
-- camera's shake stays theirs. No --!native: this is engine calls end to end.
local Workspace = game:GetService("Workspace")
local fxBudget = require(script.Parent.Parent.Parent.GlobalClient.Utils.fxBudget)

local spiderFx = {}

local UP = Vector3.yAxis
local RED = Color3.fromRGB(255, 58, 42)
local HOT = Color3.fromRGB(255, 214, 180)
local SILK = Color3.fromRGB(240, 240, 246)
local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

local Tune = table.freeze({
	-- Past this from the camera nothing is drawn.
	RANGE = 300,
	-- A gash: its glow this wide, cut along its line over CUT seconds, white-hot for HOT, gone by FADE.
	GASH_WIDTH = 0.5,
	GASH_CUT = 0.12,
	GASH_HOT = 0.1,
	GASH_FADE = 1.6,
	-- Sparks thrown where steel hits the floor, and where blade scrapes blade.
	SPARKS_HIT = 26,
	SPARKS_SCRAPE = 4,
	-- A glob: this big, its arc this high a stud of flight, its splat this many shreds.
	GLOB_SIZE = 1.6,
	GLOB_ARC = 0.35,
	SPLAT_SHREDS = 18,
	-- A patch: its disc fades in over IN and out over OUT, its strands breathing.
	PATCH_IN = 0.15,
	PATCH_OUT = 0.6,
	PATCH_STRANDS = 6,
	-- The silk line: this wide, its sky end this far over where it hangs.
	THREAD_WIDTH = 0.35,
	THREAD_TRANSPARENCY = 0.15,
	THREAD_SKY = 220,
	-- A hatch: shreds of silk and red motes thrown out.
	HATCH_SHREDS = 30,
	HATCH_MOTES = 24,
	-- The daze: this many motes circling its head, this far out, this fast (turns a second).
	DAZE_MOTES = 5,
	DAZE_RADIUS = 3.2,
	DAZE_TURNS = 0.9,
	-- It fades in over IN and out over its last OUT seconds.
	DAZE_IN = 0.2,
	DAZE_OUT = 0.4,
	-- Its boss killed: a glob in the air and its line fade out over this long (spiderFx.LetGo), its daze over its OUT.
	LET_GO = 0.3,
})

type TGash = { Part: Part, From: Vector3, To: Vector3, Age: number }
-- LetGoAge: its age when its boss died (spiderFx.LetGo), from when it fades instead of landing.
type TGlob = {
	Part: Part,
	Trail: Trail,
	From: Vector3,
	To: Vector3,
	Flight: number,
	Age: number,
	OnLand: (Vector3) -> (),
	LetGoAge: number?,
}
type TPatch = { Disc: Part, Strands: { Part }, Center: Vector3, Radius: number, Seconds: number, Age: number }
-- Faded: how far it has faded since its boss died (spiderFx.LetGo), held where it last was.
type TThread = { Beam: Beam, Sky: Attachment, Body: Attachment, Ends: () -> (Vector3?, Vector3?), Faded: number? }
type TDaze = { Motes: { Part }, Head: () -> Vector3?, Seconds: number, Age: number }

local gashes: { TGash } = {}
local globs: { TGlob } = {}
local patches: { TPatch } = {}
local threads: { TThread } = {}
local dazes: { TDaze } = {}
-- The one attachment every burst is thrown from (moved to each) and its emitters by layer, made on the first burst.
type TBursts = { Attachment: Attachment, Sparks: ParticleEmitter, Shreds: ParticleEmitter, Motes: ParticleEmitter }
type TLayer = "Sparks" | "Shreds" | "Motes"

local bursts: TBursts? = nil
local cameraPosition = Vector3.zero

-- ============================== Helpers ==============================

local function near(at: Vector3, reach: number): boolean
	return (at - cameraPosition).Magnitude <= reach
end

local function part(shape: Enum.PartType, material: Enum.Material, color: Color3): Part
	local made = Instance.new("Part")
	made.Shape = shape
	made.Material = material
	made.Color = color
	made.Anchored = true
	made.CanCollide = false
	made.CanQuery = false
	made.CanTouch = false
	made.CastShadow = false
	made.TopSurface = Enum.SurfaceType.Smooth
	made.BottomSurface = Enum.SurfaceType.Smooth
	return made
end

local function emitter(name: string, texture: string, color: ColorSequence, size: NumberSequence): ParticleEmitter
	local made = Instance.new("ParticleEmitter")
	made.Name = name
	made.Texture = texture
	made.Color = color
	made.Size = size
	made.LightEmission = 1
	made.LightInfluence = 0
	made.Enabled = false
	made.SpreadAngle = Vector2.new(180, 180)
	return made
end

local function makeBursts(): TBursts
	local made = Instance.new("Attachment")
	made.Name = "SpiderFx"
	made.Parent = Workspace.Terrain

	local spark = emitter(
		"Sparks",
		SPARK_TEXTURE,
		ColorSequence.new(HOT, RED),
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	)
	spark.Lifetime = NumberRange.new(0.25, 0.55)
	spark.Speed = NumberRange.new(18, 38)
	spark.Acceleration = Vector3.new(0, -60, 0)
	spark.Drag = 2
	spark.Parent = made

	local shred = emitter(
		"Shreds",
		SMOKE_TEXTURE,
		ColorSequence.new(SILK),
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 2.6) })
	)
	shred.LightEmission = 0.3
	shred.LightInfluence = 0.6
	shred.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	shred.Lifetime = NumberRange.new(0.5, 0.9)
	shred.Speed = NumberRange.new(8, 22)
	shred.Drag = 4
	shred.Acceleration = Vector3.new(0, -12, 0)
	shred.Rotation = NumberRange.new(0, 360)
	shred.RotSpeed = NumberRange.new(-180, 180)
	shred.Parent = made

	local mote = emitter(
		"Motes",
		SPARK_TEXTURE,
		ColorSequence.new(RED),
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
	)
	mote.Lifetime = NumberRange.new(0.5, 1)
	mote.Speed = NumberRange.new(6, 16)
	mote.Drag = 3
	mote.Parent = made

	return { Attachment = made, Sparks = spark, Shreds = shred, Motes = mote }
end

-- `count` particles of `layer` thrown at `at`, as this client can afford (fxBudget).
local function burst(layer: TLayer, at: Vector3, count: number)
	if not near(at, Tune.RANGE) then return end
	local made = bursts or makeBursts()
	bursts = made
	made.Attachment.WorldPosition = at
	fxBudget.Emit(made[layer], count, at)
end

-- ============================== Its blades ==============================

-- A blade come down on the floor along `from` to `to` (both on it): a red gash cut along the line, sparks and a flash
-- where it bit.
function spiderFx.Gash(from: Vector3, to: Vector3)
	if not near(from, Tune.RANGE) then return end
	local gash = part(Enum.PartType.Block, Enum.Material.Neon, HOT)
	gash.Size = Vector3.new(Tune.GASH_WIDTH, 0.08, 0.05)
	gash.CFrame = CFrame.lookAt(from + UP * 0.06, to + UP * 0.06)
	gash.Parent = Workspace
	table.insert(gashes, { Part = gash, From = from, To = to, Age = 0 })
	burst("Sparks", from + UP * 0.3, Tune.SPARKS_HIT)
end

-- A few sparks where steel scrapes steel (the intro's sharpening), every frame of the draw.
function spiderFx.Scrape(at: Vector3)
	burst("Sparks", at, Tune.SPARKS_SCRAPE)
end

-- ============================== Its web ==============================

-- A glob of web spat from `from` arcing onto `to` over `flight` seconds; `onLand` runs where it lands.
function spiderFx.Glob(from: Vector3, to: Vector3, flight: number, onLand: (Vector3) -> ())
	local glob = part(Enum.PartType.Ball, Enum.Material.SmoothPlastic, SILK)
	glob.Size = Vector3.one * Tune.GLOB_SIZE
	glob.CFrame = CFrame.new(from)
	local front = Instance.new("Attachment")
	front.Position = Vector3.new(0, Tune.GLOB_SIZE * 0.3, 0)
	front.Parent = glob
	local back = Instance.new("Attachment")
	back.Position = Vector3.new(0, -Tune.GLOB_SIZE * 0.3, 0)
	back.Parent = glob
	local trail = Instance.new("Trail")
	trail.Attachment0 = front
	trail.Attachment1 = back
	trail.Color = ColorSequence.new(SILK)
	trail.Transparency = NumberSequence.new(0.3, 1)
	trail.Lifetime = 0.25
	trail.FaceCamera = true
	trail.Parent = glob
	glob.Parent = Workspace
	table.insert(globs, {
		Part = glob,
		Trail = trail,
		From = from,
		To = to,
		Flight = math.max(flight, 0.05),
		Age = 0,
		OnLand = onLand,
		LetGoAge = nil,
	})
end

-- A glob's splat on `floor`.
function spiderFx.Splat(floor: Vector3)
	burst("Shreds", floor + UP * 0.5, Tune.SPLAT_SHREDS)
end

-- A sticky web patch `radius` wide on `floor` for `seconds`: a disc and a star of strands.
function spiderFx.Patch(floor: Vector3, normal: Vector3, radius: number, seconds: number)
	local base = CFrame.lookAt(floor + normal * 0.07, floor + normal * 0.07 + normal)
		* CFrame.Angles(-math.pi / 2, 0, 0)
	local disc = part(Enum.PartType.Cylinder, Enum.Material.SmoothPlastic, SILK)
	disc.Size = Vector3.new(0.05, radius * 2, radius * 2)
	disc.CFrame = base * CFrame.Angles(0, 0, math.pi / 2)
	disc.Transparency = 1
	disc.Parent = Workspace
	local strands = {}
	for i = 1, Tune.PATCH_STRANDS do
		local strand = part(Enum.PartType.Block, Enum.Material.SmoothPlastic, Color3.new(1, 1, 1))
		strand.Size = Vector3.new(0.18, 0.06, radius * 2.1)
		strand.CFrame = base * CFrame.new(0, 0.03, 0) * CFrame.Angles(0, i / Tune.PATCH_STRANDS * math.pi, 0)
		strand.Transparency = 1
		strand.Parent = Workspace
		strands[i] = strand
	end
	table.insert(
		patches,
		{ Disc = disc, Strands = strands, Center = floor, Radius = radius, Seconds = seconds, Age = 0 }
	)
end

-- Whether `feet` stand in a web patch (TimeController slows the body there): on its disc, at its floor's height.
function spiderFx.IsInWeb(feet: Vector3): boolean
	for _, patch in patches do
		local offset = feet - patch.Center
		if math.abs(offset.Y) > 3 then continue end
		if offset.X * offset.X + offset.Z * offset.Z <= patch.Radius * patch.Radius then return true end
	end

	return false
end

-- The silk line, held between what `ends` answers each frame (its sky end, where it holds the body) until it answers
-- nil; then it snaps.
function spiderFx.Thread(ends: () -> (Vector3?, Vector3?))
	local sky = Instance.new("Attachment")
	sky.Name = "SpiderThreadSky"
	sky.Parent = Workspace.Terrain
	local body = Instance.new("Attachment")
	body.Name = "SpiderThreadBody"
	body.Parent = Workspace.Terrain
	local beam = Instance.new("Beam")
	beam.Attachment0 = sky
	beam.Attachment1 = body
	beam.Color = ColorSequence.new(SILK)
	beam.Transparency = NumberSequence.new(Tune.THREAD_TRANSPARENCY)
	beam.Width0 = Tune.THREAD_WIDTH
	beam.Width1 = Tune.THREAD_WIDTH
	beam.FaceCamera = true
	beam.LightEmission = 0.4
	beam.Segments = 1
	beam.Parent = sky
	table.insert(threads, { Beam = beam, Sky = sky, Body = body, Ends = ends, Faded = nil })
end

-- How far over a hanging body its line's sky end is (the silk runs up out of sight).
spiderFx.THREAD_SKY = Tune.THREAD_SKY

-- ============================== Its brood ==============================

-- A sac bursting open at `at` and its young spilling out.
function spiderFx.Hatch(at: Vector3)
	burst("Shreds", at + UP * 2, Tune.HATCH_SHREDS)
	burst("Motes", at + UP * 2, Tune.HATCH_MOTES)
	burst("Sparks", at + UP * 1.5, 10)
end

-- Red motes and silk where a sac was popped.
function spiderFx.Pop(at: Vector3)
	burst("Motes", at, Tune.HATCH_MOTES)
	burst("Shreds", at, 12)
end

-- Motes circling its head (what `head` answers) for `seconds`: dazed after its drop.
function spiderFx.Daze(head: () -> Vector3?, seconds: number)
	local list = {}
	for i = 1, Tune.DAZE_MOTES do
		local mote = part(Enum.PartType.Ball, Enum.Material.Neon, if i % 2 == 0 then HOT else RED)
		mote.Size = Vector3.one * 0.7
		mote.Transparency = 1
		mote.Parent = Workspace
		list[i] = mote
	end
	table.insert(dazes, { Motes = list, Head = head, Seconds = seconds, Age = 0 })
end

-- Its boss is dead: a glob in the air fades on its way, never landing (its warning is taken back:
-- EnemyAttacksService), and its line and its daze fade where they are. Kit-wide: one boss at a time.
function spiderFx.LetGo()
	for _, glob in globs do
		if glob.LetGoAge then continue end
		glob.LetGoAge = glob.Age
		glob.Trail.Enabled = false
	end
	for _, thread in threads do
		thread.Faded = thread.Faded or 0
	end
	for _, daze in dazes do
		daze.Seconds = math.min(daze.Seconds, daze.Age + Tune.DAZE_OUT)
	end
end

-- ============================== Stepping ==============================

local function stepGashes(dt: number)
	for i = #gashes, 1, -1 do
		local gash = gashes[i]
		gash.Age += dt
		local age = gash.Age
		if age >= Tune.GASH_FADE then
			gash.Part:Destroy()
			table.remove(gashes, i)
			continue
		end
		local length = (gash.To - gash.From).Magnitude
		local cut = math.min(age / Tune.GASH_CUT, 1)
		local shown = length * (1 - (1 - cut) ^ 3)
		local look = CFrame.lookAt(gash.From + UP * 0.06, gash.To + UP * 0.06)
		gash.Part.Size = Vector3.new(Tune.GASH_WIDTH * (1 + 0.6 * (1 - cut)), 0.08, math.max(shown, 0.05))
		gash.Part.CFrame = look * CFrame.new(0, 0, -shown / 2)
		gash.Part.Color = if age < Tune.GASH_HOT then HOT else RED
		gash.Part.Transparency = math.clamp((age - Tune.GASH_HOT) / (Tune.GASH_FADE - Tune.GASH_HOT), 0, 1) ^ 1.5
	end
end

local function stepGlobs(dt: number)
	for i = #globs, 1, -1 do
		local glob = globs[i]
		glob.Age += dt
		local u = math.min(glob.Age / glob.Flight, 1)
		local flat = glob.From:Lerp(glob.To, u)
		local arc = (glob.To - glob.From).Magnitude * Tune.GLOB_ARC * 4 * u * (1 - u)
		glob.Part.CFrame = CFrame.new(flat + UP * arc)
		local letGoAge = glob.LetGoAge
		if letGoAge then
			local faded = (glob.Age - letGoAge) / Tune.LET_GO
			if faded < 1 then
				glob.Part.Transparency = faded
				continue
			end
			glob.Part:Destroy()
			table.remove(globs, i)
			continue
		end
		if u < 1 then continue end
		glob.Part:Destroy()
		table.remove(globs, i)
		glob.OnLand(glob.To)
	end
end

local function stepPatches(dt: number, now: number)
	for i = #patches, 1, -1 do
		local patch = patches[i]
		patch.Age += dt
		local age = patch.Age
		if age >= patch.Seconds then
			patch.Disc:Destroy()
			for _, strand in patch.Strands do
				strand:Destroy()
			end
			table.remove(patches, i)
			continue
		end
		local shown = math.min(age / Tune.PATCH_IN, 1) * math.clamp((patch.Seconds - age) / Tune.PATCH_OUT, 0, 1)
		patch.Disc.Transparency = 1 - 0.55 * shown
		local breathe = 0.5 + 0.5 * math.sin(now * 3 + i)
		for _, strand in patch.Strands do
			strand.Transparency = 1 - (0.6 + 0.25 * breathe) * shown
		end
	end
end

local function stepThreads(dt: number)
	for i = #threads, 1, -1 do
		local thread = threads[i]
		local faded = thread.Faded
		local sky, body = nil, nil
		if faded then
			faded += dt / Tune.LET_GO
			thread.Faded = faded
			if faded < 1 then
				thread.Beam.Transparency =
					NumberSequence.new(Tune.THREAD_TRANSPARENCY + (1 - Tune.THREAD_TRANSPARENCY) * faded)
				continue
			end
		else
			sky, body = thread.Ends()
		end
		if not sky or not body then
			thread.Sky:Destroy()
			thread.Body:Destroy()
			table.remove(threads, i)
			continue
		end
		thread.Sky.WorldPosition = sky
		thread.Body.WorldPosition = body
	end
end

local function stepDazes(dt: number)
	for i = #dazes, 1, -1 do
		local daze = dazes[i]
		daze.Age += dt
		local head = daze.Head()
		if daze.Age >= daze.Seconds or not head then
			for _, mote in daze.Motes do
				mote:Destroy()
			end
			table.remove(dazes, i)
			continue
		end
		local shown = math.min(daze.Age / Tune.DAZE_IN, 1) * math.clamp((daze.Seconds - daze.Age) / Tune.DAZE_OUT, 0, 1)
		local count = #daze.Motes
		for n, mote in daze.Motes do
			local angle = (daze.Age * Tune.DAZE_TURNS + n / count) * 2 * math.pi
			local bob = math.sin(daze.Age * 6 + n) * 0.3
			mote.CFrame = CFrame.new(
				head + Vector3.new(math.cos(angle) * Tune.DAZE_RADIUS, 2.2 + bob, math.sin(angle) * Tune.DAZE_RADIUS)
			)
			mote.Transparency = 1 - shown
		end
	end
end

-- One frame on the fight's clock (`dt` 0 holds what is in the air); `camera` is where distance is judged from.
function spiderFx.Update(dt: number, now: number, camera: Vector3)
	cameraPosition = camera
	stepGashes(dt)
	stepGlobs(dt)
	stepPatches(dt, now)
	stepThreads(dt)
	stepDazes(dt)
end

return spiderFx
