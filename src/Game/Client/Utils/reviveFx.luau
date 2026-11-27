-- A player's body going down and coming back, drawn the same on every client (the look is Assets/effects/death's).
-- Crumble bursts the downed body into white-hot bricks of its parts' colours, wearing their windows of its clothes,
-- that tumble and bounce like debris and settle into a pile where it fell, never inside each other; Rebuild lifts
-- that pile, swirls it round where the new body stands, lands it a row at a time from the feet up in the new body's
-- shape (a square ring snapping round each row), squashes the cubic body and pops it into the real one. The templates
-- are a place instance, not Rojo: ReplicatedStorage.Effects.ReviveFx (Assets/effects/death/make_revive_effects_*).
--
-- The bricks are this client's own anchored parts that nothing collides with or queries. The bodies' parts are hidden
-- here by their Transparency: the downed one is frozen and replaced on revive (CharacterService), and the new one is
-- shown again with the morph.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local fxBudget = require(script.Parent.Parent.Parent.GlobalClient.Utils.fxBudget)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)

local reviveFx = {}

local KIT = "ReviveFx"
local UP = Vector3.yAxis
local FLAT = Vector3.new(1, 0, 1)
local WHITE = Color3.new(1, 1, 1)
local PINK = Color3.fromRGB(255, 46, 139)

local Tune = table.freeze({
	-- Each part's box is cut into bricks about BRICK in size: the debris bricks' stud plate (one stud square, a plate
	-- tall), at most MAX_CELLS along any side (a big accessory). The rows of the rebuild are a plate apart.
	BRICK = Vector3.new(1, 0.4, 1),
	MAX_CELLS = 6,
	-- The burst into a pile, thrown as the debris bricks are (GlobalClient/Utils/thrownPieces' fall): any way across
	-- the floor, leaning BURST_AWAY of the way off the body's middle (straight off it, a torso's bricks only go left
	-- and right), tumbling about one axis, two bounces (BOUNCE of the speed back up, FRICTION of it along), then
	-- settling flat on its studs over SETTLE. Bricks are born white-hot, held HOT_HOLD, cooling to their colours over
	-- HOT: a slow cool reads as washed out, not hot.
	BURST_OUT = NumberRange.new(4, 10),
	BURST_UP = NumberRange.new(10, 19),
	BURST_AWAY = 0.45,
	SPIN = NumberRange.new(7, 16),
	GRAVITY = 85,
	BOUNCE = 0.42,
	FRICTION = 0.55,
	BOUNCES = 2,
	-- Slower than this off the floor and the next touch is its last.
	REST_SPEED = 3,
	SETTLE = 0.18,
	SETTLE_HOP = 0.3,
	HOT_HOLD = 0.06,
	HOT = 0.16,
	-- Hot bricks glow (Neon) until they are this white.
	HOT_GLOW = 0.4,
	-- The longest frame the pile falls by: a hitch is not a leap.
	STEP_MAX = 1 / 20,
	-- Where a brick settles: the nearest spot within SPACE_SEARCH of where it came down whose floor it has to itself
	-- (rings SPACE_STEP apart, SPACE_TURNS spots a ring, the first facing out of the pile); with none, on top of what
	-- is there, a heap. Footprints are shrunk by SPACE_SLACK so bricks may touch edge to edge.
	SPACE_STEP = 0.45,
	SPACE_SEARCH = 1.8,
	SPACE_TURNS = 8,
	SPACE_SLACK = 0.04,
	-- The pile's bricks heard landing at most this often (a debris brick's bag, SoundsCore merging closer ones too).
	LAND_SOUND_GAP = 0.045,
	-- How far under the body its floor is looked for, and the R6 root's centre over its feet.
	FLOOR_PROBE = 40,
	-- A falling brick looks for its floor again each FLOOR_RELOOK studs it moves across (off a ledge, over a step), from
	-- BRICK_LOOK_UP over it: a step that high is stood on, a deck over it is not. It slides only to a spot over the
	-- floor it came down on (within FLOOR_SAME) with nothing in the way at SLIDE_PROBE over it.
	FLOOR_RELOOK = 0.5,
	BRICK_LOOK_UP = 1.2,
	FLOOR_SAME = 0.1,
	SLIDE_PROBE = 0.2,
	ROOT_HEIGHT = 3,
	-- The rebuild, in seconds from its start, over by MORPH_AT + MORPH: inside CharacterService's
	-- REVIVE_HOLD_SECONDS (with a margin for the new body reaching this client late), which holds the body still and
	-- unhurt that long. Change both.
	ANTICIPATE = 0.12,
	LAUNCH = 0.32,
	ROWS = { 0.62, 1.42 },
	-- Gaps closing: a row's share of the way is (row share) ^ ROWS_EASE turned over.
	ROWS_EASE = 1.7,
	ROW_JITTER = 0.035,
	PULL = 0.3,
	PULL_BOW = 1.1,
	LAND = 0.14,
	LAND_PUNCH = 0.4,
	SQUASH = 0.1,
	SQUASH_Y = 0.86,
	SQUASH_XZ = 1.07,
	MORPH_AT = 1.62,
	MORPH = 0.16,
	FLASH = 0.4,
	-- The swirl round the standing spot: radius, height over the feet, turn speed (radians a second); it rises and
	-- tightens as it goes.
	ORBIT_RADIUS = NumberRange.new(2.2, 3.8),
	ORBIT_HEIGHT = NumberRange.new(0.6, 5.2),
	ORBIT_SPEED = NumberRange.new(2.4, 3.6),
	ORBIT_RISE = 0.6,
	-- The swirl draws in to ORBIT_TIGHTEN of its radius off over ORBIT_TIGHTEN_SECONDS; each brick tumbles at its own
	-- spin plus SWIRL_SPIN (radians a second about each axis).
	ORBIT_TIGHTEN = 0.5,
	ORBIT_TIGHTEN_SECONDS = 1.5,
	SWIRL_SPIN = Vector3.new(4, 5.2, 2.8),
	SWIRL_RATE = 34,
	-- The light under it: growing with the rows, flaring as it stands, stepping out.
	LIGHT_RANGE = 14,
	LIGHT_BUILT = 3,
	LIGHT_STAND = 6,
	LIGHT_OUT = 0.8,
	-- Pixels left by the outer bricks as they shrink away, at most.
	POPS = 60,
	-- Particles a burst throws (fxBudget thins them).
	BREAK_PIXELS = 18,
	BREAK_FLECKS = 12,
	ROW_SPIT = 4,
	STAND_RISE = 16,
	STAND_FLECKS = 16,
})

type TBrick = {
	Part: BasePart,
	Key: string,
	Color: Color3,
	Size: Vector3,
	-- What the body wore on this brick's faces: drawn over its colour, faded out where the brick goes white.
	Decals: { Decal },
	White: number,
	-- The pile: falling with Velocity and turned from Pose by Angle about Axis until it settles from SettleFrom at
	-- SettleAt into Rest, where its footprint lies along RestX (flat) and RestZ, Half its half lengths shrunk by
	-- SPACE_SLACK and Reach their length.
	Position: Vector3,
	Velocity: Vector3,
	Axis: Vector3,
	Angle: number,
	Spin: number,
	Pose: CFrame,
	Born: number,
	-- The floor under it, looked for at LookedAt; nil until it first comes down.
	Floor: number?,
	LookedAt: Vector3,
	Bounces: number,
	Rest: CFrame?,
	RestX: Vector3,
	RestZ: Vector3,
	Half: Vector2,
	Reach: number,
	SettleFrom: CFrame?,
	SettleAt: number,
	IsSettled: boolean,
}

type TGoal = {
	Brick: TBrick,
	Source: BasePart,
	Offset: CFrame,
	Row: number,
	IsOuter: boolean,
	Lands: number,
	-- Landed and done punching: nothing to write until the squash.
	IsSettled: boolean,
	Angle: number,
	Radius: number,
	Height: number,
	Speed: number,
	-- Where it was as the rebuild took it (the pile, or the stand for a brick the pile did not have).
	From: CFrame,
}

type TRebuild = {
	Root: BasePart,
	-- Under the pile: where the body stands up (the server stands it there, maybe a moment after it reaches us).
	Feet: Vector3,
	StartedAt: number,
	Goals: { TGoal },
	Leftovers: { TBrick },
	Rows: number,
	RowsFired: number,
	Hidden: { [Instance]: number },
	Colors: { [BasePart]: Color3 },
	HiddenConnection: RBXScriptConnection?,
	Swirl: Attachment?,
	Light: PointLight?,
	Glow: BasePart?,
	IsStood: boolean,
	OnStand: (() -> ())?,
}

type TPile = {
	Bricks: { TBrick },
	-- How many of them are still falling, and those that have a resting place, whose footprints the rest keep off.
	Falling: number,
	Rested: { TBrick },
	-- os.clock of the last brick heard landing.
	LandHeardAt: number,
	Center: Vector3,
	FloorY: number,
	Rebuild: TRebuild?,
}

local random = Random.new()
local piles: { [Player]: TPile } = {}
local folder: Folder? = nil
-- What a brick's floor is looked for in: the arena, set again when it changes.
local floorParams = RaycastParams.new()
floorParams.FilterType = Enum.RaycastFilterType.Include
local floorArena: Instance? = nil
local kit: { [string]: Attachment }? = nil
local hasWarned = false

-- The kit's templates by name; nil (said once) while they are not in the place, when nothing is emitted. A miss is
-- asked again, so templates that reach the client late are still found.
local function kitOf(): { [string]: Attachment }?
	if kit then return kit end
	local effects = ReplicatedStorage:FindFirstChild("Effects")
	local templates = if effects then effects:FindFirstChild(KIT) else nil
	if not templates then
		if not hasWarned then
			hasWarned = true
			warn(`[reviveFx] no ReplicatedStorage.Effects.{KIT}; bodies go down and come back with no light`)
		end
		return nil
	end

	local found = {}
	for _, child in templates:GetChildren() do
		if child:IsA("Attachment") then found[child.Name] = child end
	end
	kit = found
	return found
end

-- A burst of `layer`s from the kit's `name`, at `at`, +Y up.
local function burst(name: string, at: Vector3, counts: { [string]: number })
	local found = kitOf()
	local template = if found then found[name] else nil
	if not template then return end
	local attachment = template:Clone()
	attachment.WorldCFrame = CFrame.new(at)
	attachment.Parent = Workspace.Terrain
	for layer, count in counts do
		local emitter = attachment:FindFirstChild(layer)
		if emitter and emitter:IsA("ParticleEmitter") then fxBudget.Emit(emitter, count, at) end
	end
	task.delay(3, attachment.Destroy, attachment)
end

local function bricksFolder(): Folder
	local existing = folder
	if existing and existing.Parent then return existing end
	local created = Instance.new("Folder")
	created.Name = "ReviveBricks"
	created.Parent = Workspace
	folder = created
	return created
end

-- A brick in the debris bricks' look (Assets/effects/pistol's stud plates): plastic, studs on top, an inlet under.
local function newBrick(size: Vector3, cframe: CFrame, color: Color3): BasePart
	local part = Instance.new("Part")
	part.Name = "Brick"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Plastic
	part.TopSurface = Enum.SurfaceType.Studs
	part.BottomSurface = Enum.SurfaceType.Inlet
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Parent = bricksFolder()
	return part
end

-- The arena's floor under `at`, looked for from `lookUp` over it (over a step, under a deck), or `fallback` with none.
local function floorUnder(at: Vector3, lookUp: number, fallback: number): number
	local arena = Workspace:FindFirstChild("Arena")
	if not arena then return fallback end
	if arena ~= floorArena then
		floorArena = arena
		floorParams.FilterDescendantsInstances = { arena }
	end

	local hit = Workspace:Raycast(at + UP * lookUp, UP * -Tune.FLOOR_PROBE, floorParams)
	return if hit then hit.Position.Y else fallback
end

-- What a body wears is drawn over its parts, not in their colours: a Shirt or Pants is one image on the classic
-- template, a T-shirt and a face are decals. Each brick carries its own window of them as Decals (UVScale / UVOffset
-- pick the window out of the whole image), so a blue shirt comes apart in blue bricks with its print on them.
--
-- A face of a box seen from outside: S runs along it as the image goes left to right, T as it goes down.
type TFace = { Id: Enum.NormalId, Normal: Vector3, S: Vector3, T: Vector3 }

local SIDES: { TFace } = {
	{ Id = Enum.NormalId.Front, Normal = -Vector3.zAxis, S = -Vector3.xAxis, T = -UP },
	{ Id = Enum.NormalId.Back, Normal = Vector3.zAxis, S = Vector3.xAxis, T = -UP },
	{ Id = Enum.NormalId.Right, Normal = Vector3.xAxis, S = -Vector3.zAxis, T = -UP },
	{ Id = Enum.NormalId.Left, Normal = -Vector3.xAxis, S = Vector3.zAxis, T = -UP },
}
-- The top as the template lays it out (its front edge at the bottom). A Decal draws a top face turned half round from
-- that, so each brick's window lands in the right place with its print turned within it (ror, preview/clothing).
local TOP: TFace = { Id = Enum.NormalId.Top, Normal = UP, S = -Vector3.xAxis, T = -Vector3.zAxis }
local BOTTOM: TFace = { Id = Enum.NormalId.Bottom, Normal = -UP, S = -Vector3.xAxis, T = Vector3.zAxis }
-- The faces a brick is dressed on: never its bottom, which lies on the floor.
local DRESSED: { TFace } = { SIDES[1], SIDES[2], SIDES[3], SIDES[4], TOP }

-- The classic template's rectangles (x, y, width, height in pixels) for each R6 part's faces by NormalId name. Pants
-- put their legs where a shirt puts its arms.
local TEMPLATE_SIZE = Vector2.new(585, 559)
local TORSO_REGIONS = {
	Front = { 231, 74, 128, 128 },
	Back = { 427, 74, 128, 128 },
	Right = { 165, 74, 64, 128 },
	Left = { 361, 74, 64, 128 },
	Top = { 231, 8, 128, 64 },
}
local RIGHT_REGIONS = {
	Front = { 217, 355, 64, 128 },
	Back = { 85, 355, 64, 128 },
	Right = { 151, 355, 64, 128 },
	Left = { 19, 355, 64, 128 },
	Top = { 217, 289, 64, 64 },
}
local LEFT_REGIONS = {
	Front = { 308, 355, 64, 128 },
	Back = { 440, 355, 64, 128 },
	Right = { 506, 355, 64, 128 },
	Left = { 374, 355, 64, 128 },
	Top = { 308, 289, 64, 64 },
}
local SHIRT_REGIONS = { Torso = TORSO_REGIONS, ["Right Arm"] = RIGHT_REGIONS, ["Left Arm"] = LEFT_REGIONS }
local PANTS_REGIONS = { Torso = TORSO_REGIONS, ["Right Leg"] = RIGHT_REGIONS, ["Left Leg"] = LEFT_REGIONS }
-- An accessory's own texture has no layout to cut by: each brick shows a window this share of it.
local PATCH = 0.3

-- One image worn on a part. A template (Regions) dresses every face, a face its cell does not reach borrowing the
-- nearest side's window (a brick from inside a sleeve is the sleeve's colour); an image on one face (Face) dresses
-- only that face, the whole image across it; a patch dresses every face with a random window of the image.
type TLayer = {
	Image: string,
	Tint: Color3,
	ZIndex: number,
	Regions: { [string]: { number } }?,
	Face: TFace?,
	IsPatch: boolean,
}

local function faceById(id: Enum.NormalId): TFace
	if id == Enum.NormalId.Top then return TOP end
	if id == Enum.NormalId.Bottom then return BOTTOM end
	for _, face in SIDES do
		if face.Id == id then return face end
	end
	return SIDES[1]
end

local function addLayer(wear: { [BasePart]: { TLayer } }, part: BasePart, layer: TLayer)
	local layers = wear[part]
	if not layers then
		layers = {}
		wear[part] = layers
	end
	table.insert(layers, layer)
end

-- What `character` wears on each of `parts`, bottom layer first.
local function wearOf(character: Model, parts: { BasePart }): { [BasePart]: { TLayer } }
	local pants = character:FindFirstChildOfClass("Pants")
	local shirt = character:FindFirstChildOfClass("Shirt")
	local graphic = character:FindFirstChildOfClass("ShirtGraphic")
	local wear = {}
	for _, part in parts do
		if pants and pants.PantsTemplate ~= "" and PANTS_REGIONS[part.Name] then
			addLayer(wear, part, {
				Image = pants.PantsTemplate,
				Tint = pants.Color3,
				ZIndex = 1,
				Regions = PANTS_REGIONS[part.Name],
				IsPatch = false,
			})
		end
		if shirt and shirt.ShirtTemplate ~= "" and SHIRT_REGIONS[part.Name] then
			addLayer(wear, part, {
				Image = shirt.ShirtTemplate,
				Tint = shirt.Color3,
				ZIndex = 2,
				Regions = SHIRT_REGIONS[part.Name],
				IsPatch = false,
			})
		end
		if graphic and graphic.Graphic ~= "" and part.Name == "Torso" then
			addLayer(
				wear,
				part,
				{ Image = graphic.Graphic, Tint = graphic.Color3, ZIndex = 3, Face = SIDES[1], IsPatch = false }
			)
		end

		for _, child in part:GetChildren() do
			if child:IsA("Decal") and child.Texture ~= "" and child.Transparency < 0.99 then
				addLayer(wear, part, {
					Image = child.Texture,
					Tint = child.Color3,
					ZIndex = 4 + child.ZIndex,
					Face = faceById(child.Face),
					IsPatch = false,
				})
			elseif child:IsA("SpecialMesh") and child.TextureId ~= "" then
				addLayer(wear, part, { Image = child.TextureId, Tint = WHITE, ZIndex = 1, IsPatch = true })
			elseif child:IsA("SurfaceAppearance") and child.ColorMap ~= "" then
				addLayer(wear, part, { Image = child.ColorMap, Tint = child.Color, ZIndex = 1, IsPatch = true })
			end
		end
		if part:IsA("MeshPart") and part.TextureID ~= "" then
			addLayer(wear, part, { Image = part.TextureID, Tint = WHITE, ZIndex = 1, IsPatch = true })
		end
	end

	return wear
end

-- Where a cell of `size` at `offset` in a part of `partSize` runs along `axis`: its start and length as shares of the
-- part's side.
local function span(axis: Vector3, offset: Vector3, size: Vector3, partSize: Vector3): (number, number)
	local side = math.abs(axis:Dot(partSize))
	local length = math.abs(axis:Dot(size))
	return (axis:Dot(offset) - length / 2) / side + 0.5, length / side
end

-- How far a cell's outside is in from a face of the part: 0 on it.
local function depthUnder(face: TFace, offset: Vector3, size: Vector3, partSize: Vector3): number
	return (math.abs(face.Normal:Dot(partSize)) - math.abs(face.Normal:Dot(size))) / 2 - face.Normal:Dot(offset)
end

local function newDecal(brick: BasePart, layer: TLayer, face: TFace, offset: Vector2, scale: Vector2): Decal
	local decal = Instance.new("Decal")
	decal.Face = face.Id
	decal.Texture = layer.Image
	decal.Color3 = layer.Tint
	decal.ZIndex = layer.ZIndex
	decal.UVOffset = offset
	decal.UVScale = scale
	decal.Parent = brick
	return decal
end

-- Dresses `brick`, cut from `part` at `offset` in `size`, in what `layers` put there.
local function dress(brick: BasePart, layers: { TLayer }, part: BasePart, offset: Vector3, size: Vector3): { Decal }
	local partSize = part.Size
	local decals = {}
	for _, layer in layers do
		if layer.IsPatch then
			local at = Vector2.new(random:NextNumber(0, 1 - PATCH), random:NextNumber(0, 1 - PATCH))
			for _, face in DRESSED do
				table.insert(decals, newDecal(brick, layer, face, at, Vector2.one * PATCH))
			end
			continue
		end

		local only = layer.Face
		if only then
			if depthUnder(only, offset, size, partSize) > 0.01 then continue end
			local s, sLength = span(only.S, offset, size, partSize)
			local t, tLength = span(only.T, offset, size, partSize)
			table.insert(decals, newDecal(brick, layer, only, Vector2.new(s, t), Vector2.new(sLength, tLength)))
			continue
		end

		local regions = layer.Regions :: { [string]: { number } }
		for _, face in DRESSED do
			-- A face inside the part shows the window of the nearest side the cell reaches out to.
			local source = face
			if depthUnder(face, offset, size, partSize) > 0.01 then
				local nearest = math.huge
				for _, side in SIDES do
					if math.abs(side.Normal:Dot(face.Normal)) > 0.5 then continue end
					local depth = depthUnder(side, offset, size, partSize)
					if depth < nearest then
						nearest = depth
						source = side
					end
				end
			end
			local region = regions[source.Id.Name]
			if not region then continue end
			local s, sLength = span(source.S, offset, size, partSize)
			local t, tLength = span(source.T, offset, size, partSize)
			local at = Vector2.new(region[1] + s * region[3], region[2] + t * region[4]) / TEMPLATE_SIZE
			local scale = Vector2.new(sLength * region[3], tLength * region[4]) / TEMPLATE_SIZE
			table.insert(decals, newDecal(brick, layer, face, at, scale))
		end
	end

	return decals
end

-- `brick` in its colour, `white` of the way to white: what it wears fades out as it whitens, since a decal's colour
-- only darkens what it is drawn with.
local function paint(brick: TBrick, white: number)
	brick.Part.Color = brick.Color:Lerp(WHITE, white)
	if brick.White == white then return end
	brick.White = white
	for _, decal in brick.Decals do
		decal.Transparency = white
	end
end

-- A body's parts as bricks are cut from them: the body's own parts first, then what it wears, so a cell inside a part
-- already cut (the lower half of a hat is the head) is that part's. The root is no part of the look.
local function lookParts(character: Model): { BasePart }
	local parts = {}
	for _, child in character:GetChildren() do
		if child:IsA("BasePart") and child.Name ~= "HumanoidRootPart" and child.Transparency < 0.99 then
			table.insert(parts, child)
		end
	end
	for _, child in character:GetChildren() do
		if not child:IsA("Accessory") then continue end
		local handle = child:FindFirstChild("Handle")
		if handle and handle:IsA("BasePart") and handle.Transparency < 0.99 then table.insert(parts, handle) end
	end

	return parts
end

local function keyOf(part: BasePart): string
	local parent = part.Parent
	return if parent and parent:IsA("Accessory") then parent.Name else part.Name
end

-- Each cell of each part: its key (part and index), its offset in the part, its size, whether it is on the outside.
type TCell = { Part: BasePart, Key: string, Offset: CFrame, Size: Vector3, IsOuter: boolean }

local function cellsOf(parts: { BasePart }): { TCell }
	local cells = {}
	for index, part in parts do
		local size = part.Size
		local counts = Vector3.new(
			math.clamp(math.round(size.X / Tune.BRICK.X), 1, Tune.MAX_CELLS),
			math.clamp(math.round(size.Y / Tune.BRICK.Y), 1, Tune.MAX_CELLS),
			math.clamp(math.round(size.Z / Tune.BRICK.Z), 1, Tune.MAX_CELLS)
		)
		local cell = size / counts
		local edge = size / 2 - cell * 0.6
		local key = keyOf(part)
		local n = 0
		for x = 1, counts.X do
			for y = 1, counts.Y do
				for z = 1, counts.Z do
					n += 1
					local offset = (Vector3.new(x, y, z) - Vector3.one * 0.5) * cell - size / 2
					local world = part.CFrame:PointToWorldSpace(offset)
					local isTaken = false
					for earlier = 1, index - 1 do
						local other = parts[earlier]
						local inOther = other.CFrame:PointToObjectSpace(world)
						local half = other.Size / 2
						if
							math.abs(inOther.X) < half.X
							and math.abs(inOther.Y) < half.Y
							and math.abs(inOther.Z) < half.Z
						then
							isTaken = true
							break
						end
					end
					if isTaken then continue end
					table.insert(cells, {
						Part = part,
						Key = `{key}/{n}`,
						Offset = CFrame.new(offset),
						Size = cell,
						IsOuter = math.abs(offset.X) > edge.X
							or math.abs(offset.Y) > edge.Y
							or math.abs(offset.Z) > edge.Z,
					})
				end
			end
		end
	end

	return cells
end

-- Hides `character`'s look on this client, keeping what each piece's Transparency was in `hidden`.
local function hide(instance: Instance, hidden: { [Instance]: number })
	if instance:IsA("BasePart") or instance:IsA("Decal") then
		local piece = instance :: any
		if hidden[instance] == nil then hidden[instance] = piece.Transparency end
		piece.Transparency = 1
	end
end

local function hideAll(character: Model, hidden: { [Instance]: number })
	for _, instance in character:GetDescendants() do
		hide(instance, hidden)
	end
end

local function clearPile(pile: TPile)
	local rebuild = pile.Rebuild
	if rebuild then
		if rebuild.HiddenConnection then rebuild.HiddenConnection:Disconnect() end
		if rebuild.Swirl then rebuild.Swirl:Destroy() end
		if rebuild.Glow then rebuild.Glow:Destroy() end
		for _, goal in rebuild.Goals do
			goal.Brick.Part:Destroy()
		end
		for _, brick in rebuild.Leftovers do
			brick.Part:Destroy()
		end
	end
	for _, brick in pile.Bricks do
		brick.Part:Destroy()
	end
	table.clear(pile.Bricks)
end

-- A brick cut from `cell`, at `cframe`, dressed in what `wear` puts there; still, until it is thrown. A hot one is born
-- white and glowing.
local function brickOf(cell: TCell, cframe: CFrame, wear: { [BasePart]: { TLayer } }, isHot: boolean): TBrick
	local part = newBrick(cell.Size, cframe, cell.Part.Color)
	local layers = wear[cell.Part]
	local brick: TBrick = {
		Part = part,
		Key = cell.Key,
		Color = cell.Part.Color,
		Size = cell.Size,
		Decals = if layers then dress(part, layers, cell.Part, cell.Offset.Position, cell.Size) else {},
		White = 0,
		Position = cframe.Position,
		Velocity = Vector3.zero,
		Axis = UP,
		Angle = 0,
		Spin = 0,
		Pose = cframe.Rotation,
		Born = os.clock(),
		Floor = nil,
		LookedAt = cframe.Position,
		Bounces = 0,
		Rest = nil,
		RestX = Vector3.xAxis,
		RestZ = Vector3.zAxis,
		Half = Vector2.zero,
		Reach = 0,
		SettleFrom = nil,
		SettleAt = 0,
		IsSettled = false,
	}
	if isHot then
		paint(brick, 1)
		part.Material = Enum.Material.Neon
	end

	return brick
end

-- `player`'s body just went down: it bursts into bricks that fall into a pile where it fell. Its own parts are hidden.
function reviveFx.Crumble(player: Player, character: Model)
	local old = piles[player]
	if old then clearPile(old) end
	local parts = lookParts(character)
	if #parts == 0 then return end

	local pivot = character:GetPivot().Position
	local floorY = floorUnder(pivot, 2, pivot.Y - Tune.ROOT_HEIGHT)
	local center = Vector3.new(pivot.X, floorY + Tune.ROOT_HEIGHT, pivot.Z)
	local wear = wearOf(character, parts)
	local bricks = {}
	for _, cell in cellsOf(parts) do
		local cframe = cell.Part.CFrame * cell.Offset
		local brick = brickOf(cell, cframe, wear, true)
		local turn = random:NextNumber(0, math.pi * 2)
		local direction = Vector3.new(math.cos(turn), 0, math.sin(turn))
		local away = (cframe.Position - center) * FLAT
		if away.Magnitude > 0.05 then direction = (direction + away.Unit * Tune.BURST_AWAY).Unit end
		brick.Velocity = direction * random:NextNumber(Tune.BURST_OUT.Min, Tune.BURST_OUT.Max)
			+ UP * random:NextNumber(Tune.BURST_UP.Min, Tune.BURST_UP.Max)
		brick.Axis = random:NextUnitVector()
		brick.Spin = random:NextNumber(Tune.SPIN.Min, Tune.SPIN.Max)
		table.insert(bricks, brick)
	end
	hideAll(character, {})

	piles[player] = {
		Bricks = bricks,
		Falling = #bricks,
		Rested = {},
		LandHeardAt = -math.huge,
		Center = center,
		FloorY = floorY,
		Rebuild = nil,
	}
	burst("Break", Vector3.new(center.X, floorY + 0.05, center.Z), { Wash = 1, Shock = 1 })
	burst("Break", center, { Core = 1, Pixels = Tune.BREAK_PIXELS, Flecks = Tune.BREAK_FLECKS })
	SoundsCore.PlayWorldRandom("Revive", "Spill", center)
end

-- When row `row` of `rows` lands, in seconds from the rebuild's start: from the feet up, the gaps closing.
local function rowLandsAt(row: number, rows: number): number
	local share = row / math.max(rows - 1, 1)
	return Tune.ROWS[1] + (Tune.ROWS[2] - Tune.ROWS[1]) * (1 - (1 - share) ^ Tune.ROWS_EASE)
end

-- `player`'s new body, `character`, stands where the pile lies: the pile builds it. `onStand` runs as the real body
-- shows. False when there is no pile to build from (the body is shown as it is).
function reviveFx.Rebuild(player: Player, character: Model, root: BasePart, onStand: (() -> ())?): boolean
	local pile = piles[player]
	if not pile or pile.Rebuild then return false end

	-- Measured before it is hidden: a hidden part is no part of the look.
	local parts = lookParts(character)
	local cells = cellsOf(parts)
	local wear = wearOf(character, parts)
	local hidden = {}
	hideAll(character, hidden)
	local rebuild: TRebuild = {
		Root = root,
		Feet = Vector3.new(pile.Center.X, pile.FloorY, pile.Center.Z),
		StartedAt = os.clock(),
		Goals = {},
		Leftovers = {},
		Rows = 0,
		RowsFired = 0,
		Hidden = hidden,
		Colors = {},
		HiddenConnection = character.DescendantAdded:Connect(function(instance)
			-- What the body is still putting on (accessories load after it) stays hidden until the morph too.
			hide(instance, hidden)
		end),
		Swirl = nil,
		Light = nil,
		Glow = nil,
		IsStood = false,
		OnStand = onStand,
	}
	pile.Rebuild = rebuild

	-- Each cell of the new body takes the pile's brick of the same piece, or a new one from the middle of the pile.
	local byKey = {}
	for _, brick in pile.Bricks do
		byKey[brick.Key] = brick
	end
	-- Rows are counted off the body's own root, wherever it is yet.
	local rootFeet = root.Position - UP * Tune.ROOT_HEIGHT
	local feet = rebuild.Feet
	local rows = 0
	for _, cell in cells do
		local brick = byKey[cell.Key]
		if brick then
			byKey[cell.Key] = nil
			brick.Part.Material = Enum.Material.Plastic
		else
			brick = brickOf(cell, CFrame.new(pile.Center), wear, false)
		end
		local goal = cell.Part.CFrame * cell.Offset
		local row = math.max(math.floor((goal.Position.Y - rootFeet.Y) / Tune.BRICK.Y), 0)
		rows = math.max(rows, row + 1)
		local fromStand = brick.Part.Position - feet
		table.insert(rebuild.Goals, {
			Brick = brick,
			Source = cell.Part,
			Offset = cell.Offset,
			Row = row,
			IsOuter = cell.IsOuter,
			Lands = 0,
			IsSettled = false,
			Angle = math.atan2(fromStand.Z, fromStand.X),
			Radius = random:NextNumber(Tune.ORBIT_RADIUS.Min, Tune.ORBIT_RADIUS.Max),
			Height = random:NextNumber(Tune.ORBIT_HEIGHT.Min, Tune.ORBIT_HEIGHT.Max),
			Speed = random:NextNumber(Tune.ORBIT_SPEED.Min, Tune.ORBIT_SPEED.Max),
			From = brick.Part.CFrame,
		})
	end
	for _, brick in byKey do
		table.insert(rebuild.Leftovers, brick)
	end
	table.clear(pile.Bricks)

	rebuild.Rows = rows
	for _, goal in rebuild.Goals do
		goal.Lands = rowLandsAt(goal.Row, rows) + random:NextNumber() * Tune.ROW_JITTER
	end

	local found = kitOf()
	local swirl = if found and found.Swirl then found.Swirl:Clone() else nil
	if swirl then
		swirl.WorldCFrame = CFrame.new(feet)
		swirl.Parent = Workspace.Terrain
		local rise = swirl:FindFirstChild("Rise")
		if rise and rise:IsA("ParticleEmitter") then
			rise.Rate = Tune.SWIRL_RATE
			rise.Enabled = true
		end
	end
	rebuild.Swirl = swirl
	local glow = newBrick(Vector3.one * 0.1, CFrame.new(feet + UP * 3), PINK)
	glow.Transparency = 1
	local light = Instance.new("PointLight")
	light.Color = PINK
	light.Range = Tune.LIGHT_RANGE
	light.Brightness = 0
	light.Parent = glow
	rebuild.Glow = glow
	rebuild.Light = light
	SoundsCore.PlayWorldRandom("Revive", "Rattle", feet + UP * 3)
	return true
end

-- The pile of a player who left, or a run that ended: gone.
function reviveFx.Clear(player: Player)
	local pile = piles[player]
	if not pile then return end
	piles[player] = nil
	clearPile(pile)
end

local function decelerate(t: number): number
	t = math.clamp(t, 0, 1)
	return 1 - (1 - t) ^ 3
end

local function accelerate(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * t
end

local function progress(now: number, from: number, seconds: number): number
	return math.clamp((now - from) / seconds, 0, 1)
end

-- How far a box of `size` turned by `rotation` reaches below its centre.
local function reachDown(rotation: CFrame, size: Vector3): number
	return (
		math.abs(rotation.RightVector.Y) * size.X
		+ math.abs(rotation.UpVector.Y) * size.Y
		+ math.abs(rotation.LookVector.Y) * size.Z
	) / 2
end

-- Whether `axis` parts two flat footprints `between` apart, each along its x and z with half lengths `half`.
local function isApartAlong(
	axis: Vector3,
	between: Vector3,
	xA: Vector3,
	zA: Vector3,
	halfA: Vector2,
	xB: Vector3,
	zB: Vector3,
	halfB: Vector2
): boolean
	local reachA = halfA.X * math.abs(xA:Dot(axis)) + halfA.Y * math.abs(zA:Dot(axis))
	local reachB = halfB.X * math.abs(xB:Dot(axis)) + halfB.Y * math.abs(zB:Dot(axis))
	return math.abs(between:Dot(axis)) >= reachA + reachB
end

-- The top of the highest brick resting under a footprint at `at` (along `x` and `z`, `half` its half lengths, `reach`
-- their length), or nil when its floor is clear. Separating axes, after a cheap test of the two reaches.
local function topUnder(pile: TPile, at: Vector3, x: Vector3, z: Vector3, half: Vector2, reach: number): number?
	local top = nil
	for _, other in pile.Rested do
		local rest = other.Rest :: CFrame
		local between = (rest.Position - at) * FLAT
		if between.Magnitude >= reach + other.Reach then continue end
		local otherX, otherZ, otherHalf = other.RestX, other.RestZ, other.Half
		if
			isApartAlong(x, between, x, z, half, otherX, otherZ, otherHalf)
			or isApartAlong(z, between, x, z, half, otherX, otherZ, otherHalf)
			or isApartAlong(otherX, between, x, z, half, otherX, otherZ, otherHalf)
			or isApartAlong(otherZ, between, x, z, half, otherX, otherZ, otherHalf)
		then
			continue
		end
		local otherTop = rest.Position.Y + other.Size.Y / 2
		if not top or otherTop > top then top = otherTop end
	end

	return top
end

-- Whether a brick that came down on `floor` at `landing` can slide to `at`: the same floor there, nothing in between.
local function canSlide(landing: Vector3, at: Vector3, floor: number): boolean
	if math.abs(floorUnder(at, Tune.BRICK_LOOK_UP, floor) - floor) > Tune.FLOOR_SAME then return false end
	local from = landing + UP * Tune.SLIDE_PROBE
	return Workspace:Raycast(from, at - landing, floorParams) == nil
end

-- `brick` has touched down for the last time at `position`, turned by `rotation`: it rolls flat onto its studs, keeping
-- the way it faced, carried `slide` on where the floor allows, and slides to the nearest spot of floor no other brick
-- lies on, or onto the heap where none is near.
local function settle(pile: TPile, brick: TBrick, position: Vector3, rotation: CFrame, slide: Vector3, now: number)
	local x = rotation.RightVector * FLAT
	if x.Magnitude < 0.1 then x = rotation.UpVector * FLAT end
	x = if x.Magnitude > 0.01 then x.Unit else Vector3.xAxis
	local z = x:Cross(UP)
	local half = Vector2.new(brick.Size.X, brick.Size.Z) / 2 - Vector2.one * Tune.SPACE_SLACK
	local reach = half.Magnitude
	local floor = position.Y - reachDown(rotation, brick.Size)
	local landing = Vector3.new(position.X, floor, position.Z)
	if canSlide(landing, landing + slide, floor) then
		landing += slide
	end

	local out = (landing - pile.Center) * FLAT
	local outTurn = if out.Magnitude > 0.01 then math.atan2(out.Z, out.X) else random:NextNumber(0, math.pi * 2)
	local spot = nil
	if not topUnder(pile, landing, x, z, half, reach) then spot = landing end
	local ring = 1
	while not spot and ring * Tune.SPACE_STEP <= Tune.SPACE_SEARCH do
		local radius = ring * Tune.SPACE_STEP
		for step = 0, Tune.SPACE_TURNS - 1 do
			local turn = outTurn + step * math.pi * 2 / Tune.SPACE_TURNS
			local at = landing + Vector3.new(math.cos(turn), 0, math.sin(turn)) * radius
			if topUnder(pile, at, x, z, half, reach) or not canSlide(landing, at, floor) then continue end
			spot = at
			break
		end
		ring += 1
	end
	if not spot then spot = landing + UP * ((topUnder(pile, landing, x, z, half, reach) :: number) - floor) end

	brick.Rest = CFrame.fromMatrix(spot + UP * (brick.Size.Y / 2), x, UP)
	brick.RestX = x
	brick.RestZ = z
	brick.Half = half
	brick.Reach = reach
	brick.SettleFrom = CFrame.new(position) * rotation
	brick.SettleAt = now
	table.insert(pile.Rested, brick)
end

-- One frame of a brick of the burst: tumbling down, two bounces, then settling. True on the frame it first touches the
-- floor.
local function stepFalling(pile: TPile, brick: TBrick, dt: number, now: number): boolean
	local part = brick.Part
	if brick.White > 0 then
		local wasGlowing = brick.White >= Tune.HOT_GLOW
		paint(brick, 1 - decelerate(progress(now, brick.Born + Tune.HOT_HOLD, Tune.HOT)))
		if wasGlowing and brick.White < Tune.HOT_GLOW then part.Material = Enum.Material.Plastic end
	end

	local from = brick.SettleFrom
	if from then
		local rest = brick.Rest :: CFrame
		local t = progress(now, brick.SettleAt, Tune.SETTLE)
		local hop = Tune.SETTLE_HOP * math.min((rest.Position - from.Position).Magnitude, 1)
		part.CFrame = from:Lerp(rest, decelerate(t)) + UP * (math.sin(t * math.pi) * hop)
		brick.IsSettled = t >= 1
		if brick.IsSettled and brick.White > 0 then
			paint(brick, 0)
			part.Material = Enum.Material.Plastic
		end
		return false
	end

	local velocity = brick.Velocity - UP * (Tune.GRAVITY * dt)
	local position = brick.Position + velocity * dt
	brick.Angle += brick.Spin * dt
	local rotation = brick.Pose * CFrame.fromAxisAngle(brick.Axis, brick.Angle)
	-- Only coming down does the floor matter, looked for again as it moves across.
	local isLooked = false
	if velocity.Y < 0 and (not brick.Floor or ((position - brick.LookedAt) * FLAT).Magnitude > Tune.FLOOR_RELOOK) then
		isLooked = true
		brick.Floor = floorUnder(position, Tune.BRICK_LOOK_UP, pile.FloorY)
		brick.LookedAt = position
	end
	local floor = brick.Floor or pile.FloorY
	local reach = reachDown(rotation, brick.Size)
	local isTouch = velocity.Y < 0 and position.Y - reach <= floor
	if isTouch and not isLooked then
		-- Right under it, again: it may have just gone over an edge (and falls on) or onto a step (and stands on it).
		floor = floorUnder(position, Tune.BRICK_LOOK_UP, floor)
		brick.Floor = floor
		brick.LookedAt = position
		isTouch = position.Y - reach <= floor
	end
	if isTouch then
		position = Vector3.new(position.X, floor + reach, position.Z)
		brick.Bounces += 1
		local rebound = -velocity.Y * Tune.BOUNCE
		velocity = Vector3.new(velocity.X * Tune.FRICTION, rebound, velocity.Z * Tune.FRICTION)
		brick.Spin *= 0.5
		if brick.Bounces >= Tune.BOUNCES or rebound < Tune.REST_SPEED then
			-- What it still slides along the floor, carried into where it settles.
			settle(pile, brick, position, rotation, velocity * FLAT * (Tune.SETTLE / 2), now)
		end
	end
	brick.Velocity = velocity
	brick.Position = position
	part.CFrame = CFrame.new(position) * rotation

	return isTouch and brick.Bounces == 1
end

local function orbitAt(goal: TGoal, feet: Vector3, since: number): Vector3
	local angle = goal.Angle + goal.Speed * since
	local radius = goal.Radius * (1 - Tune.ORBIT_TIGHTEN * math.clamp(since / Tune.ORBIT_TIGHTEN_SECONDS, 0, 1))
	local height = goal.Height + Tune.ORBIT_RISE * since
	return feet + Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)
end

local function stand(rebuild: TRebuild)
	rebuild.IsStood = true
	if rebuild.HiddenConnection then rebuild.HiddenConnection:Disconnect() end
	rebuild.HiddenConnection = nil
	for instance, transparency in rebuild.Hidden do
		if instance.Parent then (instance :: any).Transparency = transparency end
		if instance:IsA("BasePart") then rebuild.Colors[instance] = instance.Color end
	end
	if rebuild.Swirl then
		local rise = rebuild.Swirl:FindFirstChild("Rise")
		if rise and rise:IsA("ParticleEmitter") then rise.Enabled = false end
	end

	local pops = 0
	for _, goal in rebuild.Goals do
		if goal.IsOuter and pops < Tune.POPS and random:NextNumber() < 0.5 then
			pops += 1
			burst("Pop", goal.Brick.Part.Position, { Pixel = 1 })
		end
	end
	local feet = rebuild.Feet
	burst("Feet", feet + UP * 0.05, { Wash = 1, Frame = 1, Shock = 1, Rise = Tune.STAND_RISE })
	burst("Chest", feet + UP * 3, { Bloom = 1, Core = 1, Flecks = Tune.STAND_FLECKS })
	SoundsCore.PlayWorldRandom("Revive", "Merge", feet + UP * 3)
	SoundsCore.PlayWorldNamed("Items", "Heal", feet + UP * 3)
	local onStand = rebuild.OnStand
	if onStand then task.spawn(onStand) end
end

-- One frame of a rebuild; true once it is over.
local function stepRebuild(rebuild: TRebuild, now: number): boolean
	local since = now - rebuild.StartedAt
	local feet = rebuild.Feet

	-- The pile flashes white a beat before it lifts; what the new body has no place for shrinks away as it lifts.
	if since < Tune.ANTICIPATE then
		local flash = progress(since, 0, Tune.ANTICIPATE)
		for _, goal in rebuild.Goals do
			paint(goal.Brick, flash * flash)
		end
		return false
	end
	local lifted = since - Tune.ANTICIPATE
	local leftover = 1 - decelerate(progress(lifted, 0, Tune.LAUNCH))
	for _, brick in rebuild.Leftovers do
		brick.Part.Size = brick.Size * math.max(leftover, 0.01)
	end

	-- The rows: a ring snapping round each as it lands, and a snap.
	local fired = rebuild.RowsFired
	while fired < rebuild.Rows do
		if since < rowLandsAt(fired, rebuild.Rows) then break end
		local height = feet + UP * ((fired + 0.5) * Tune.BRICK.Y)
		fired += 1
		burst("Row", height, { Ring = 1, Spit = Tune.ROW_SPIT })
		SoundsCore.PlayWorldRandom("Revive", "Snap", height)
	end
	rebuild.RowsFired = fired
	if rebuild.Light then
		local built = fired / math.max(rebuild.Rows, 1)
		rebuild.Light.Brightness = if rebuild.IsStood
			then Tune.LIGHT_STAND * (1 - progress(since, Tune.MORPH_AT, Tune.LIGHT_OUT))
			else Tune.LIGHT_BUILT * built
		if rebuild.Glow then rebuild.Glow.CFrame = CFrame.new(feet + UP * 3) end
	end

	if not rebuild.IsStood and since >= Tune.MORPH_AT then stand(rebuild) end
	local squash = progress(since, Tune.MORPH_AT - Tune.SQUASH, Tune.SQUASH)
	local morph = progress(since, Tune.MORPH_AT, Tune.MORPH)
	local isWhole = squash > 0 or morph > 0
	for _, goal in rebuild.Goals do
		if goal.IsSettled and not isWhole then continue end
		local brick = goal.Brick
		local target = goal.Source.CFrame * goal.Offset
		local position, rotation
		local size = brick.Size
		local white = 0
		local pullFrom = goal.Lands - Tune.PULL
		if since < pullFrom then
			local launch = decelerate(progress(lifted, 0, Tune.LAUNCH))
			position = goal.From.Position:Lerp(orbitAt(goal, feet, lifted), launch)
			local turn = (brick.Axis * brick.Spin + Tune.SWIRL_SPIN) * lifted
			rotation = goal.From.Rotation * CFrame.Angles(turn.X, turn.Y, turn.Z)
		elseif since < goal.Lands then
			local t = accelerate(progress(since, pullFrom, Tune.PULL))
			local heldAt = pullFrom - Tune.ANTICIPATE
			local held = orbitAt(goal, feet, heldAt)
			local turn = (brick.Axis * brick.Spin + Tune.SWIRL_SPIN) * heldAt
			local heldRotation = goal.From.Rotation * CFrame.Angles(turn.X, turn.Y, turn.Z)
			local mid = held:Lerp(target.Position, 0.5) + UP * Tune.PULL_BOW
			position = held:Lerp(mid, t):Lerp(mid:Lerp(target.Position, t), t)
			rotation = heldRotation:Lerp(target.Rotation, decelerate(t))
		else
			local landed = decelerate(progress(since, goal.Lands, Tune.LAND))
			goal.IsSettled = landed >= 1
			position = target.Position
			rotation = target.Rotation
			size = size * (1 + Tune.LAND_PUNCH * (1 - landed))
			white = 1 - landed
		end
		if squash > 0 then
			local bump = math.sin(squash * math.pi / 2)
			local scale = Vector3.new(
				1 + (Tune.SQUASH_XZ - 1) * bump,
				1 + (Tune.SQUASH_Y - 1) * bump,
				1 + (Tune.SQUASH_XZ - 1) * bump
			)
			position = feet + (position - feet) * scale
			white += (1 - white) * bump * 0.6
		end
		if morph > 0 then
			size = size * math.max(1 - decelerate(morph), 0.01)
			white = 1
		end
		brick.Part.CFrame = CFrame.new(position) * rotation
		brick.Part.Size = size
		paint(brick, white)
	end

	-- The real body: white as it shows, back to its own colours.
	if rebuild.IsStood then
		local flash = 1 - decelerate(progress(since, Tune.MORPH_AT, Tune.FLASH))
		for part, original in rebuild.Colors do
			part.Color = original:Lerp(WHITE, flash)
		end
	end

	return since >= Tune.MORPH_AT + math.max(Tune.MORPH, Tune.FLASH, Tune.LIGHT_OUT)
end

-- Once a frame: the falling piles and the rebuilds.
function reviveFx.Step(dt: number)
	if next(piles) == nil then return end
	local now = os.clock()
	local step = math.min(dt, Tune.STEP_MAX)
	for player, pile in piles do
		local rebuild = pile.Rebuild
		if rebuild then
			if not rebuild.Root.Parent or stepRebuild(rebuild, now) then
				piles[player] = nil
				if not rebuild.IsStood then
					for instance, transparency in rebuild.Hidden do
						if instance.Parent then (instance :: any).Transparency = transparency end
					end
				end
				for part, original in rebuild.Colors do
					part.Color = original
				end
				clearPile(pile)
			end
			continue
		end
		if pile.Falling == 0 then continue end
		for _, brick in pile.Bricks do
			if brick.IsSettled then continue end
			local isFirstTouch = stepFalling(pile, brick, step, now)
			if brick.IsSettled then
				pile.Falling -= 1
			end
			if not isFirstTouch then continue end
			-- Each brick is heard as it first touches the floor, as the debris bricks are (their bag, through
			-- SoundsCore's merge), but never two within LAND_SOUND_GAP: a pile lands as a clatter, not a buzz.
			if now - pile.LandHeardAt < Tune.LAND_SOUND_GAP then continue end
			pile.LandHeardAt = now
			SoundsCore.PlayWorldRandom("Debris", "Land", brick.Part.Position)
		end
	end
end

return reviveFx
