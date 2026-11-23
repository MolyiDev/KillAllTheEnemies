-- The Decoy as it is seen, in the house look (VFX.md 30 and 37): an inflatable copy of the thrower's own avatar,
-- thrown small in an arc, blowing itself up where it lands, swaying and calling while it stands, knocked about and
-- squeaking on every blow, swelling as its time runs out and bursting into scraps of its own colours
-- (GlobalClient/Utils/thrownPieces) with a blast across the floor as wide as the blow it deals.
-- AbilityController says when and steps it. The look is on templates at ReplicatedStorage.Effects.HumanFx, a place
-- instance, not Rojo, made by Assets/effects/abilities (its README.md). The beats it draws (a blow, the call, the
-- pop) play their sounds here, so they land on the beat. No --!native: this is engine calls end to end.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local thrownPieces = require(script.Parent.Parent.Parent.GlobalClient.Utils.thrownPieces)
local burstLayers = require(script.Parent.burstLayers)
local copyCharacter = require(script.Parent.Parent.Parent.GlobalClient.Utils.copyCharacter)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local TimeCore = require(ReplicatedStorage.Shared.Core.TimeCore)

local decoyFx = {}

type TLayers = burstLayers.TLayers

local layersOf = burstLayers.Clone
local emit = burstLayers.Emit
local roll = burstLayers.Roll
local between = burstLayers.Between

local KIT = "HumanFx"

local Tune = table.freeze({
	-- Its sounds, under ReplicatedStorage.Sounds.Abilities: DecoySqueak (a blow), DecoyCall (the ping), DecoyPop.
	SOUND_GROUP = "Abilities",
	-- The doll stands this much bigger than the avatar, so it is seen over a crowd, and flies this small.
	SCALE = 1.2,
	FLIGHT_SCALE = 0.34,
	-- The throw: its top is this far over the higher end plus this share of its length, and it tumbles this many
	-- turns on the way.
	ARC_HEIGHT = 7,
	ARC_SHARE = 0.16,
	TUMBLES = 1.5,
	-- Landed, it blows up to full size over this long, past it and back.
	INFLATE_SECONDS = 0.3,
	INFLATE_OVERSHOOT = 2.6,
	-- It sways on its feet: two slow swings at different rates (degrees and radians a second), so it never repeats.
	SWAY = math.rad(4),
	SWAY_RATE = 2.3,
	SWAY_RATE_SIDE = 1.7,
	-- A blow knocks it over this far (radians a second into its lean) on this spring, and squeezes it this much for
	-- this long: the squeak.
	KNOCK = 5.5,
	KNOCK_FREQUENCY = 17,
	KNOCK_DAMPING = 0.22,
	SQUEEZE = 0.16,
	SQUEEZE_SECONDS = 0.2,
	-- The call: a ring on the floor this often.
	PING_SECONDS = 0.85,
	-- About to burst (the last of its time): it swells this much more over this long, shaking this far (radians) at
	-- this rate, and calls this often. One popped early by blows skips it.
	SWELL_SECONDS = 0.5,
	SWELL = 0.3,
	SWELL_SHAKE = math.rad(3.5),
	SWELL_SHAKE_RATE = 58,
	SWELL_PING_SECONDS = 0.16,
	-- Nothing but the doll is drawn further than this from the camera.
	RANGE = 220,
	LAND_PIXELS = NumberRange.new(8, 11),
	LAND_PUFFS = NumberRange.new(5, 7),
	SQUEAK_PIXELS = NumberRange.new(3, 5),
	POP_PIXELS = NumberRange.new(18, 24),
	POP_FLECKS = NumberRange.new(8, 12),
	POP_PUFFS = NumberRange.new(5, 7),
	-- The blast under a standing doll's pop (DecoyBlast, on the floor): its rings are drawn as wide as the Decoy's
	-- BlastRadius in Data/Classes/Human, so what is seen is what is struck.
	BLAST_PILLAR = NumberRange.new(10, 14),
	BLAST_PIXELS = NumberRange.new(26, 34),
	BLAST_FLECKS = NumberRange.new(14, 20),
	BLAST_PUFFS = NumberRange.new(10, 14),
	-- The scraps it pops into: this many, thrown this fast across the floor and up.
	SCRAPS = NumberRange.new(14, 18),
	SCRAP_SIDE = NumberRange.new(8, 26),
	SCRAP_LIFT = NumberRange.new(12, 30),
	PIECE_PARTS = 40,
	-- A doll whose pop never came is taken down this long after it should have gone.
	LATE_SECONDS = 1.5,
	-- The block doll's skin: an inflatable's. A copied avatar keeps its own (buildDoll).
	MATERIAL = Enum.Material.SmoothPlastic,
	REFLECTANCE = 0.18,
	-- An avatar with no body to copy: these, as an R6 shape (the block doll).
	SKIN = Color3.fromRGB(245, 205, 48),
	TOP = Color3.fromRGB(255, 110, 185),
	LEGS = Color3.fromRGB(60, 90, 200),
})

-- Blast is nil in a place saved before the kit had it: the doll then goes with its pop alone.
type TKit = { Bricks: { BasePart }, Land: TLayers, Ping: TLayers, Squeak: TLayers, Pop: TLayers, Blast: TLayers? }

-- The doll: its parts with where each sits from its feet and how big it is at the avatar's own size, so any size is
-- a write of each part's Size and CFrame (and its mesh's Scale, for a hat's).
type TDoll = {
	Model: Model,
	Parts: { BasePart },
	Offsets: { CFrame },
	Sizes: { Vector3 },
	Meshes: { [number]: SpecialMesh },
	MeshScales: { [number]: Vector3 },
	-- Scratch for BulkMoveTo, and the size it was last written at.
	CFrames: { CFrame },
	Scale: number,
	Height: number,
	Colors: { Color3 },
}

type TDecoy = {
	Doll: TDoll,
	From: Vector3,
	To: Vector3,
	-- Where its feet are now.
	At: Vector3,
	Facing: CFrame,
	ThrownAt: number,
	LandsAt: number,
	EndsAt: number,
	HasLanded: boolean,
	NextPingAt: number,
	-- The lean a blow gave it (radians, about X and Z) and how fast it is going, and the GameClock of its last squeak.
	LeanX: number,
	LeanZ: number,
	LeanVelocityX: number,
	LeanVelocityZ: number,
	SqueakedAt: number,
	SwayPhase: number,
}

local random = Random.new()
local pieces = thrownPieces.NewPool("DecoyPieces", Tune.PIECE_PARTS)
local kit: TKit? = nil
local hasWarned = false
local decoys: { [number]: TDecoy } = {}
local folder: Folder? = nil

-- The kit's templates; nil (said once) while they are not in the place, when the doll stands and goes with no burst.
-- A miss is asked again, so templates that reach the client late are still found.
local function kitOf(): TKit?
	if kit then return kit end

	local effects = ReplicatedStorage:FindFirstChild("Effects")
	local templates = if effects then effects:FindFirstChild(KIT) else nil
	local land = if templates then layersOf(templates:FindFirstChild("DecoyLand")) else nil
	local ping = if templates then layersOf(templates:FindFirstChild("DecoyPing")) else nil
	local squeak = if templates then layersOf(templates:FindFirstChild("DecoySqueak")) else nil
	local pop = if templates then layersOf(templates:FindFirstChild("DecoyPop")) else nil
	if not templates or not land or not ping or not squeak or not pop then
		if not hasWarned then
			hasWarned = true
			warn(`[decoyFx] no ReplicatedStorage.Effects.{KIT}; the decoy's bursts are not drawn`)
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

	local found = {
		Bricks = bricks,
		Land = land,
		Ping = ping,
		Squeak = squeak,
		Pop = pop,
		Blast = layersOf(templates:FindFirstChild("DecoyBlast")),
	}
	kit = found
	return found
end

local function isNear(position: Vector3): boolean
	return (Workspace.CurrentCamera.CFrame.Position - position).Magnitude <= Tune.RANGE
end

local function folderOf(): Folder
	local found = folder
	if found then return found end
	local made = Instance.new("Folder")
	made.Name = "Decoys"
	made.Parent = Workspace
	folder = made
	return made
end

-- An R6 shape in the block doll's colours, feet at the origin, for a thrower whose avatar cannot be copied.
local function blockBody(): Model
	local model = Instance.new("Model")
	local function limb(name: string, size: Vector3, at: Vector3, color: Color3)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.CFrame = CFrame.new(at)
		part.Color = color
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = model
	end

	limb("Left Leg", Vector3.new(1, 2, 1), Vector3.new(-0.5, 1, 0), Tune.LEGS)
	limb("Right Leg", Vector3.new(1, 2, 1), Vector3.new(0.5, 1, 0), Tune.LEGS)
	limb("Torso", Vector3.new(2, 2, 1), Vector3.new(0, 3, 0), Tune.TOP)
	limb("Left Arm", Vector3.new(1, 2, 1), Vector3.new(-1.5, 3, 0), Tune.SKIN)
	limb("Right Arm", Vector3.new(1, 2, 1), Vector3.new(1.5, 3, 0), Tune.SKIN)
	limb("Head", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 4.6, 0), Tune.SKIN)
	return model
end

-- The doll of `source`, parked out of sight: every part anchored and out of every query. A copied avatar keeps its
-- parts' own Material and Reflectance: the engine paints the face and the clothes onto a body through its Humanoid
-- only while the parts are as the avatar loaded them, and a head repainted shows its face's texture black.
local function buildDoll(source: Model?): TDoll
	local copy = if source then copyCharacter(source) else nil
	local model = copy or blockBody()
	model.Name = "Decoy"

	local bounds, extents = model:GetBoundingBox()
	local root = model:FindFirstChild("HumanoidRootPart")
	local turn = if root and root:IsA("BasePart") then root.CFrame.Rotation else CFrame.identity
	local feet = CFrame.new(bounds.Position - Vector3.new(0, extents.Y / 2, 0)) * turn
	local parts, offsets, sizes, meshes, meshScales, colors = {}, {}, {}, {}, {}, {}
	for _, child in model:GetDescendants() do
		if not child:IsA("BasePart") then continue end
		child.Anchored = true
		child.CanCollide = false
		child.CanQuery = false
		child.CanTouch = false
		child.CastShadow = false
		if not copy then
			child.Material = Tune.MATERIAL
			child.Reflectance = Tune.REFLECTANCE
		end

		local index = #parts + 1
		parts[index] = child
		offsets[index] = feet:ToObjectSpace(child.CFrame)
		sizes[index] = child.Size
		local mesh = child:FindFirstChildOfClass("SpecialMesh")
		if mesh and mesh.MeshType == Enum.MeshType.FileMesh then
			meshes[index] = mesh
			meshScales[index] = mesh.Scale
		end
		if child.Transparency < 1 then colors[#colors + 1] = child.Color end
	end

	if #colors == 0 then colors[1] = Tune.TOP end
	model.Parent = folderOf()
	return {
		Model = model,
		Parts = parts,
		Offsets = offsets,
		Sizes = sizes,
		Meshes = meshes,
		MeshScales = meshScales,
		CFrames = table.create(#parts),
		Scale = 0,
		Height = extents.Y,
		Colors = colors,
	}
end

-- Stands the doll with its feet at `feet`, `scale` times the avatar. A change of size rewrites every part's Size; the
-- rest is one BulkMoveTo.
local function place(doll: TDoll, feet: CFrame, scale: number)
	local parts, cframes = doll.Parts, doll.CFrames
	local isResized = scale ~= doll.Scale
	doll.Scale = scale
	for index, offset in doll.Offsets do
		cframes[index] = feet * (offset.Rotation + offset.Position * scale)
		if not isResized then continue end
		parts[index].Size = doll.Sizes[index] * scale
		local mesh = doll.Meshes[index]
		if mesh then mesh.Scale = doll.MeshScales[index] * scale end
	end

	Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

-- Throws a decoy: `key` names it, `source` is the thrower's character to copy (nil for the block doll), and it goes
-- from `from` to the floor at `to` in `flightSeconds`, then stands for `lifeSeconds`.
function decoyFx.Throw(
	key: number,
	source: Model?,
	from: Vector3,
	to: Vector3,
	flightSeconds: number,
	lifeSeconds: number
)
	if decoys[key] then decoyFx.Pop(key) end

	local now = TimeCore.GameClock
	local back = Vector3.new(from.X - to.X, 0, from.Z - to.Z)
	decoys[key] = {
		Doll = buildDoll(source),
		From = from,
		To = to,
		At = from,
		-- It lands looking back at whoever threw it.
		Facing = if back.Magnitude > 0.1 then CFrame.lookAt(Vector3.zero, back) else CFrame.identity,
		ThrownAt = now,
		LandsAt = now + flightSeconds,
		EndsAt = now + flightSeconds + lifeSeconds,
		HasLanded = false,
		NextPingAt = 0,
		LeanX = 0,
		LeanZ = 0,
		LeanVelocityX = 0,
		LeanVelocityZ = 0,
		SqueakedAt = -math.huge,
		SwayPhase = random:NextNumber(0, math.pi * 2),
	}
end

-- A blow landed on it: it is knocked over a way, squeezed, and throws a ring and a few pixels.
function decoyFx.Squeak(key: number)
	local decoy = decoys[key]
	if not decoy or not decoy.HasLanded then return end

	local turn = random:NextNumber(0, math.pi * 2)
	decoy.LeanVelocityX += math.cos(turn) * Tune.KNOCK
	decoy.LeanVelocityZ += math.sin(turn) * Tune.KNOCK
	decoy.SqueakedAt = TimeCore.GameClock

	local chest = decoy.To + Vector3.new(0, decoy.Doll.Height * Tune.SCALE * 0.6, 0)
	SoundsCore.PlayWorldNamed(Tune.SOUND_GROUP, "DecoySqueak", chest)

	local found = kitOf()
	if not found or not isNear(chest) then return end
	local squeak = found.Squeak
	squeak.Attachment.CFrame = CFrame.new(chest)
	emit(squeak, "Frame", 1)
	emit(squeak, "Pixels", roll(Tune.SQUEAK_PIXELS))
end

-- It goes: a burst where its chest was and scraps in its own colours. One that was standing blasts the floor round
-- it too, and its feet are returned for whoever shakes the view; nil for one caught in the air.
function decoyFx.Pop(key: number): Vector3?
	local decoy = decoys[key]
	if not decoy then return nil end
	decoys[key] = nil

	local doll = decoy.Doll
	local chest = decoy.At + Vector3.new(0, doll.Height * doll.Scale * 0.6, 0)
	local blastAt = if decoy.HasLanded then decoy.To else nil
	doll.Model:Destroy()
	SoundsCore.PlayWorldNamed(Tune.SOUND_GROUP, "DecoyPop", chest)

	local found = kitOf()
	if not found or not isNear(chest) then return blastAt end
	local pop = found.Pop
	pop.Attachment.CFrame = CFrame.new(chest)
	emit(pop, "Bloom", 1)
	emit(pop, "Core", 1)
	emit(pop, "Frame", 1)
	emit(pop, "Pixels", roll(Tune.POP_PIXELS))
	emit(pop, "Flecks", roll(Tune.POP_FLECKS))
	emit(pop, "Puffs", roll(Tune.POP_PUFFS))

	local blast = found.Blast
	if blast and blastAt then
		blast.Attachment.CFrame = CFrame.new(blastAt + Vector3.new(0, 0.08, 0))
		emit(blast, "Wash", 1)
		emit(blast, "Shock", 1)
		emit(blast, "Echo", 1)
		emit(blast, "Pillar", roll(Tune.BLAST_PILLAR))
		emit(blast, "Pixels", roll(Tune.BLAST_PIXELS))
		emit(blast, "Flecks", roll(Tune.BLAST_FLECKS))
		emit(blast, "Puffs", roll(Tune.BLAST_PUFFS))
	end

	local bricks = found.Bricks
	local distance = (Workspace.CurrentCamera.CFrame.Position - chest).Magnitude
	local count = thrownPieces.Allowed(pieces, roll(Tune.SCRAPS), distance)
	local colors = doll.Colors
	local floor = thrownPieces.FloorUnder(chest)
	for _ = 1, if #bricks > 0 then count else 0 do
		local turn = random:NextNumber(0, math.pi * 2)
		local velocity = Vector3.new(math.cos(turn), 0, math.sin(turn)) * between(Tune.SCRAP_SIDE)
			+ Vector3.new(0, between(Tune.SCRAP_LIFT), 0)
		thrownPieces.Throw(
			pieces,
			bricks[random:NextInteger(1, #bricks)],
			colors[random:NextInteger(1, #colors)],
			chest + random:NextUnitVector() * (doll.Height * 0.25),
			velocity,
			floor
		)
	end

	return blastAt
end

-- Where a thrown doll is `share` of the way through its flight: up over the higher end and down, tumbling.
local function inFlight(decoy: TDecoy, share: number): CFrame
	local from, to = decoy.From, decoy.To
	local top = math.max(from.Y, to.Y) + Tune.ARC_HEIGHT + (to - from).Magnitude * Tune.ARC_SHARE
	local position = from:Lerp(to, share)
	local lift = top - (from.Y + (to.Y - from.Y) * share)
	local height = position.Y + lift * 4 * share * (1 - share)
	return CFrame.new(position.X, height, position.Z)
		* decoy.Facing
		* CFrame.Angles(-share * Tune.TUMBLES * math.pi * 2, 0, 0)
end

local function land(decoy: TDecoy)
	decoy.HasLanded = true
	decoy.At = decoy.To
	local found = kitOf()
	if not found or not isNear(decoy.To) then return end
	local layers = found.Land
	layers.Attachment.CFrame = CFrame.new(decoy.To + Vector3.new(0, 0.08, 0))
	emit(layers, "Wash", 1)
	emit(layers, "Frame", 1)
	emit(layers, "Pixels", roll(Tune.LAND_PIXELS))
	emit(layers, "Puffs", roll(Tune.LAND_PUFFS))
end

-- A standing doll this frame: blown up (past full size and back as it lands), swaying, leaning from its last blows
-- on a spring, squeezed by a squeak, and calling; in the last of its time swelling, shaking and calling faster. The
-- pop is the server's word, so one whose word is late stays swollen.
local function stand(decoy: TDecoy, now: number, dt: number)
	local frequency = Tune.KNOCK_FREQUENCY
	local damping = 2 * Tune.KNOCK_DAMPING * frequency
	decoy.LeanVelocityX += (-frequency * frequency * decoy.LeanX - damping * decoy.LeanVelocityX) * dt
	decoy.LeanVelocityZ += (-frequency * frequency * decoy.LeanZ - damping * decoy.LeanVelocityZ) * dt
	decoy.LeanX += decoy.LeanVelocityX * dt
	decoy.LeanZ += decoy.LeanVelocityZ * dt

	local t = math.clamp((now - decoy.LandsAt) / Tune.INFLATE_SECONDS, 0, 1)
	local u = t - 1
	local inflated = 1 + (Tune.INFLATE_OVERSHOOT + 1) * u * u * u + Tune.INFLATE_OVERSHOOT * u * u
	local squeeze = math.clamp((now - decoy.SqueakedAt) / Tune.SQUEEZE_SECONDS, 0, 1)
	local swell = math.clamp(1 - (decoy.EndsAt - now) / Tune.SWELL_SECONDS, 0, 1)
	local scale = (Tune.FLIGHT_SCALE + (Tune.SCALE - Tune.FLIGHT_SCALE) * inflated)
		* (1 - Tune.SQUEEZE * math.sin(squeeze * math.pi))
		* (1 + Tune.SWELL * swell * swell)
	local phase = now + decoy.SwayPhase
	local shake = Tune.SWELL_SHAKE * swell * math.sin(now * Tune.SWELL_SHAKE_RATE)
	local feet = CFrame.new(decoy.To)
		* decoy.Facing
		* CFrame.Angles(
			decoy.LeanX + Tune.SWAY * math.sin(phase * Tune.SWAY_RATE),
			0,
			decoy.LeanZ + Tune.SWAY * math.sin(phase * Tune.SWAY_RATE_SIDE) + shake
		)
	-- Sizes are written in steps of a hundredth: a doll at rest rewrites none.
	place(decoy.Doll, feet, math.round(scale * 100) / 100)

	if now < decoy.NextPingAt then return end
	decoy.NextPingAt = now + (if swell > 0 then Tune.SWELL_PING_SECONDS else Tune.PING_SECONDS)
	-- The first ping is on the landing, which DecoyThrow already carries.
	if now - decoy.LandsAt >= Tune.PING_SECONDS then
		SoundsCore.PlayWorldNamed(Tune.SOUND_GROUP, "DecoyCall", decoy.To)
	end

	local found = kit
	if not found or not isNear(decoy.To) then return end
	found.Ping.Attachment.CFrame = CFrame.new(decoy.To + Vector3.new(0, 0.08, 0))
	emit(found.Ping, "Ping", 1)
end

-- Once a frame: every doll in the air or standing, and the scraps.
function decoyFx.Step(dt: number)
	thrownPieces.Step(pieces, TimeCore.TimeScale)
	local now = TimeCore.GameClock
	for key, decoy in decoys do
		if now >= decoy.EndsAt + Tune.LATE_SECONDS then
			decoyFx.Pop(key)
			continue
		end

		if now < decoy.LandsAt then
			local share = (now - decoy.ThrownAt) / math.max(decoy.LandsAt - decoy.ThrownAt, 1e-3)
			local feet = inFlight(decoy, share)
			decoy.At = feet.Position
			place(decoy.Doll, feet, Tune.FLIGHT_SCALE)
			continue
		end

		if not decoy.HasLanded then land(decoy) end
		stand(decoy, now, dt)
	end
end

return decoyFx
