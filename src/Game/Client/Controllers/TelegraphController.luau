-- Ground warnings (GDD 11, 14): exactly the area an enemy attack will hit, drawn for its whole wind-up and then its
-- hit. The server sends the hitbox itself (EnemyAttacksService); draw that and nothing else.
--
-- A warning lies on the floors it covers (TelegraphCore's footprint, flooded on this client's own bake of the nav
-- grid), cut into flat pieces, one per run of floor at one height, each showing its slice of the shape's texture. A
-- Texture tiles, so no piece is ever wider than the picture it shows. Never a Highlight: those are the enemies'
-- budget (EnemiesCore.MAX_ALIVE). What it throws besides (pixels, bricks, light) is Client/Utils/telegraphFx, at
-- points picked on those pieces, so nothing is drawn past the floor the hit covers.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local Network = require(StarterPlayer.StarterPlayerScripts.GlobalClient.Network)
-- Through PlayerScripts, the copy that runs (see HudController).
local CameraController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.CameraController)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local ArenaCore = require(ReplicatedStorage.Shared.Core.ArenaCore)
local TelegraphCore = require(ReplicatedStorage.Shared.Core.TelegraphCore)
local TimeCore = require(ReplicatedStorage.Shared.Core.TimeCore)
local sightCast = require(ReplicatedStorage.Shared.Utils.sightCast)
local telegraphFx = require(script.Parent.Parent.Utils.telegraphFx)
local ETelegraphs = require(ReplicatedStorage.Types.Enums.ETelegraphs)
local TCharacter = require(ReplicatedStorage.Types.TCharacter)
local TCharacterEvents = require(ReplicatedStorage.Types.Events.TCharacterEvents)

local ServerNetworkEnemies = Network.Server.Enemies

local TelegraphsFolder = Workspace:WaitForChild("Telegraphs")

local TelegraphController = {}

-- Assets/effects/telegraphs/make_telegraph_textures.py draws these, white, so COLOR tints them; Assets/effects/telegraphs/images.json keeps the ids.
local IMAGES = table.freeze({
	CircleSmall = "rbxassetid://103123062302794",
	CircleLarge = "rbxassetid://84445301207309",
	CircleSweep = "rbxassetid://79598482597984",
	Ring = "rbxassetid://107320257798324",
	Line = "rbxassetid://128972503311697",
	LineSweep = "rbxassetid://86619857890807",
	Cone60 = "rbxassetid://103577175411207",
	Cone60Sweep = "rbxassetid://105703064062891",
	Cone90 = "rbxassetid://97734448046535",
	Cone90Sweep = "rbxassetid://118915750595600",
	Cone120 = "rbxassetid://76348409855757",
	Cone120Sweep = "rbxassetid://140206132477481",
})
-- The share of its picture's half-width a shape fills (make_telegraph_textures.py FILL): the rest is the rim's stroke and glow.
local IMAGE_FILL = 0.94
-- From this radius a circle takes the thinner rim: a texture's rim grows with its shape.
local LARGE_RADIUS = 16
-- Measured against the map's floors (VFX.md section 15): red vanishes on the track, and violet is the hits' colour.
-- Above 1 brightens a Texture, the way a Decal's Color3 does.
-- selene: allow(roblox_incorrect_color3_new_bounds)
local COLOR = Color3.new(1.5, 0.18, 0.65)
-- A boss's: purple, so a player tells the heavier hit apart at a glance. Measured the same way: it reads on every floor
-- better than COLOR does, and apart from COLOR by a deltaE of 30 at the sweep's density.
-- selene: allow(roblox_incorrect_color3_new_bounds)
local BOSS_COLOR = Color3.new(0.6, 0.15, 1.5)
-- selene: allow(roblox_incorrect_color3_new_bounds)
local WHITE_HOT = Color3.new(2.4, 2.1, 2.3)
local CANCEL_COLOR = Color3.new(0.55, 0.5, 0.55)

local Tune = table.freeze({
	-- Above the floor, and the sweep above the body, so neither fights the surface under it.
	LIFT = 0.05,
	SWEEP_LIFT = 0.03,
	-- Trim: a part this thin or thinner, lying flat, whose top is at most SKIN_REACH above a floor. The pitch's grass,
	-- stripes and lines stand 0.1-0.4 above the slab enemies walk on.
	SKIN_MAX_THICKNESS = 1,
	SKIN_REACH = 1,
	THICKNESS = 0.05,
	-- A rotated shape samples the floor finer, since its cells cross the grid's.
	FINE_STEP = 1,
	-- Floors this close in height are one piece, at the highest of them: the map's slabs differ by tenths.
	MERGE_HEIGHT = 0.3,
	-- Lands slightly too big and settles: the eye catches a thing that moves when it appears.
	POP_SECONDS = 0.14,
	POP_SCALE = 1.18,
	-- The glow pulses faster as the hit nears.
	PULSE_HZ_START = 1.5,
	PULSE_HZ_END = 7,
	GLOW_BASE = 1,
	GLOW_PULSE = 0.35,
	-- A boss's throbs deeper.
	BOSS_GLOW_PULSE = 0.6,
	-- The last stretch of the wind-up heats toward white.
	WARN_SECONDS = 0.18,
	WARN_HEAT = 0.55,
	-- The hit: a white-hot flash that swells a little and fades.
	IMPACT_SECONDS = 0.32,
	IMPACT_SWELL = 0.07,
	-- An ended warning still this far from its hit was taken back (its exploder died).
	CANCEL_MARGIN = 0.12,
	CANCEL_SECONDS = 0.22,
	-- A rolling shockwave dims its area so the front is what reads.
	ROLL_BODY_TRANSPARENCY = 0.6,
	ROLL_FADE_SECONDS = 0.2,
	-- The blast shake: SHAKE at its centre, falling off with the square of the distance to nothing FELT_RADII radii
	-- out, so only a blast the player stood in or beside is felt, and a crowd going off across the arena is not.
	SHAKE = 3,
	SHAKE_ROUGHNESS = 0.4,
	SHAKE_SECONDS = 0.3,
	FELT_RADII = 2.5,
	-- The blow's sound: a bag of takes under Sounds.Enemies.Attacks. An explosion this wide or wider is the big one.
	BLOW_GROUP = "Enemies.Attacks",
	BIG_BLAST_SIZE = 15,
	-- Pieces kept for reuse.
	POOL_SIZE = 256,
	-- Glowing pixels rising off the rim through the wind-up, a second per stud of outline: from START to END as the hit
	-- nears, so the edge stands up out of the floor (read over a crowd) and boils faster as it comes. A burst of them
	-- as it appears.
	RIM_MOTES_START = 0.35,
	RIM_MOTES_END = 1.4,
	RIM_MOTES_POP = 0.3,
	-- Pixels kicked up by the fill's front, a second per stud of front: the timer drawn in the air too.
	FRONT_MOTES = 0.7,
	-- Rim pixels sit this far inside the outline, on its bright band.
	RIM_INSET = 0.3,
	-- The landing: pixels out of the floor and stud bricks knocked loose, per square stud of what it covers, within a
	-- range; a shockwave does it along its front as it rolls, per stud of front a second.
	SPRAY_PER_AREA = 0.12,
	SPRAY_MIN = 8,
	SPRAY_MAX = 28,
	BRICKS_PER_AREA = 0.05,
	BRICKS_MIN = 3,
	BRICKS_MAX = 12,
	-- An explosion throws this many times what a slam does: the biggest moment an ordinary enemy has.
	BLAST_SHARE = 1.6,
	FRONT_SPRAY = 2,
	FRONT_BRICKS = 0.25,
	-- A shockwave's slam where it starts, before its front rolls out.
	RING_SLAM_RADIUS = 5,
	-- Grey pixels off the rim of a warning taken back, per stud of outline.
	FIZZLE_PER_STUD = 0.3,
	FIZZLE_MAX = 20,
	-- A point on a floor is looked for this many times its count before giving up (off a wall, past a ledge).
	TRIES = 2,
	-- The floor's colour where it cannot be found.
	NO_FLOOR_COLOR = Color3.fromRGB(160, 160, 160),
})

local EState = table.freeze({
	WindUp = 1,
	Impact = 2,
	Rolling = 3,
	Cancelled = 4,
})

-- What its part and texture were last given, so a frame that changes nothing writes nothing (a property write is an
-- engine call; the pulse rewrites only the colour).
type TPiece = {
	Part: Part,
	Texture: Texture,
	IsShown: boolean,
	Size: Vector3,
	CFrame: CFrame,
	Transparency: number,
}

type TTelegraph = {
	Kind: number,
	Color: Color3,
	GlowPulse: number,
	Frame: CFrame,
	Size: number,
	Width: number,
	Duration: number,
	Speed: number,
	Blow: string,
	IsExplosion: boolean,
	Palette: number,
	-- The length of its outline, and what is owed to its rim and its front (a fraction carries over): pixels, and a
	-- rolling shockwave's bricks.
	Perimeter: number,
	RimDebt: number,
	FrontDebt: number,
	BrickDebt: number,
	-- The floor's colour at its centre, read as it lands: its dust.
	Dust: Color3,
	Elapsed: number,
	Phase: number,
	State: number,
	StateElapsed: number,
	-- Per piece, flat: x0, x1, z0, z1 in the warning's frame, and its height above the centre.
	Rects: { number },
	Bodies: { TPiece },
	Sweeps: { TPiece },
	SweepImage: string,
}

local active: { [number]: TTelegraph } = {}
local pool: { TPiece } = {}
local selfRoot: BasePart? = nil
-- Per nav node, the top of the trim lying on it, where that is above the floor: what a warning must lie on to be seen.
local skin: { [number]: number } = {}
-- Per nav node, the colour of what lies on top there (its trim, stamped at the bake, else what a ray down met the
-- first time a brick was knocked out of it): the map never changes, so a node is looked at once.
local floorColors: { [number]: Color3 } = {}
local random = Random.new()

-- Reused by every build.
local reusableFootprint: { [number]: boolean } = {}
local reusableXs: { number } = {}
local reusableZs: { number } = {}
local reusableCounts: { number } = {}
local reusableHeights: { number } = {}
local reusableUsed: { boolean } = {}
local reusableOutside: { boolean } = {}
-- Points on a warning's floor handed to telegraphFx, with the floor's height and colour under each.
local reusablePoints: { Vector3 } = {}
local reusableFloors: { number } = {}
local reusableColors: { Color3 } = {}

-- ============================== Pieces ==============================

local function takePiece(image: string): TPiece
	local piece = table.remove(pool)
	if not piece then
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Transparency = 1
		local texture = Instance.new("Texture")
		texture.Face = Enum.NormalId.Top
		texture.Parent = part
		piece = {
			Part = part,
			Texture = texture,
			IsShown = false,
			Size = part.Size,
			CFrame = part.CFrame,
			Transparency = texture.Transparency,
		}
	end

	local taken = piece :: TPiece
	taken.Texture.Texture = image
	if taken.Transparency ~= 0 then
		taken.Transparency = 0
		taken.Texture.Transparency = 0
	end
	return taken
end

local function showPiece(piece: TPiece, isShown: boolean)
	if piece.IsShown == isShown then return end
	piece.IsShown = isShown
	piece.Part.Parent = if isShown then TelegraphsFolder else nil
end

local function releasePiece(piece: TPiece)
	showPiece(piece, false)
	if #pool >= Tune.POOL_SIZE then
		piece.Part:Destroy()
		return
	end

	table.insert(pool, piece)
end

-- Puts a piece over [x0, x1] x [z0, z1] of the warning's frame, `dy` above its centre. The part's axes are the
-- frame's, which is what mapTexture assumes.
-- A sweep growing round its centre keeps its pieces' centres, so CFrame and Size are written apart.
local function placePiece(piece: TPiece, frame: CFrame, x0: number, x1: number, z0: number, z1: number, dy: number)
	local size = Vector3.new(x1 - x0, Tune.THICKNESS, z1 - z0)
	if size ~= piece.Size then
		piece.Size = size
		piece.Part.Size = size
	end
	local cframe = frame * CFrame.new((x0 + x1) / 2, dy, (z0 + z1) / 2)
	if cframe ~= piece.CFrame then
		piece.CFrame = cframe
		piece.Part.CFrame = cframe
	end
end

-- Lays the picture that covers [ix0, ix1] x [iz0, iz1] of the warning's frame onto a piece whose +X edge is at x1
-- and +Z edge at z1. On a Top face a Texture is anchored at the part's +X +Z corner, U runs toward -X and V toward -Z,
-- and an offset adds; so the picture's top is the part's +Z, the warning's forward. No document says so: it was read
-- off a calibration row in play (2026-10-24), after two guesses each drew every piece's slice flipped.
local function mapTexture(texture: Texture, x1: number, z1: number, ix0: number, ix1: number, iz0: number, iz1: number)
	texture.StudsPerTileU = ix1 - ix0
	texture.StudsPerTileV = iz1 - iz0
	texture.OffsetStudsU = ix1 - x1
	texture.OffsetStudsV = iz1 - z1
end

-- ============================== Shapes ==============================

-- The picture's extent in the warning's frame at `scale`, scaled from the shape's anchor (its centre, or a line's
-- start), which is the frame's origin.
local function imageRect(kind: number, size: number, width: number, scale: number): (number, number, number, number)
	if kind == ETelegraphs.Line then
		local halfX, halfZ = width / 2 / IMAGE_FILL, size / 2 / IMAGE_FILL
		return -halfX * scale, halfX * scale, (size / 2 - halfZ) * scale, (size / 2 + halfZ) * scale
	end

	local half = size / IMAGE_FILL * scale
	return -half, half, -half, half
end

local function bodyImage(kind: number, size: number, width: number): string
	if kind == ETelegraphs.Line then return IMAGES.Line end
	if kind == ETelegraphs.Cone then return IMAGES[`Cone{width}`] end
	return if size >= LARGE_RADIUS then IMAGES.CircleLarge else IMAGES.CircleSmall
end

local function sweepImage(kind: number, width: number): string
	if kind == ETelegraphs.Line then return IMAGES.LineSweep end
	if kind == ETelegraphs.Cone then return IMAGES[`Cone{width}Sweep`] end
	return IMAGES.CircleSweep
end

-- Grid lines over [min, max] every `step`, on the lattice `phase + k * step`, clipped to the ends.
local function gridLines(out: { number }, min: number, max: number, step: number, phase: number): number
	table.clear(out)
	out[1] = min
	local count = 1
	local line = phase + (math.floor((min - phase) / step) + 1) * step
	while line < max - 1e-3 do
		count += 1
		out[count] = line
		line += step
	end

	count += 1
	out[count] = max
	return count
end

-- The slot of an unused floor in cell `c` at `height`, 0 when the cell is outside the shape (its picture is clear
-- there, so any piece may cover it), nil when neither.
local function findHeight(c: number, height: number): number?
	if reusableOutside[c] then return 0 end
	local base = (c - 1) * ArenaCore.MAX_LAYERS
	for k = 1, reusableCounts[c] do
		if not reusableUsed[base + k] and math.abs(reusableHeights[base + k] - height) <= Tune.MERGE_HEIGHT then
			return base + k
		end
	end

	return nil
end

-- Whether every cell of columns i0..i1 x rows j0..j1 takes a piece at `height`.
local function isBlockFree(nx: number, i0: number, i1: number, j0: number, j1: number, height: number): boolean
	for j = j0, j1 do
		for i = i0, i1 do
			if not findHeight((j - 1) * nx + i, height) then return false end
		end
	end

	return true
end

-- Takes the floors of a block at `height` for one piece, and returns the highest of them.
local function claimBlock(
	nx: number,
	i0: number,
	i1: number,
	j0: number,
	j1: number,
	height: number,
	top: number
): number
	for j = j0, j1 do
		for i = i0, i1 do
			local slot = findHeight((j - 1) * nx + i, height) :: number
			if slot == 0 then continue end
			reusableUsed[slot] = true
			top = math.max(top, reusableHeights[slot])
		end
	end

	return top
end

-- Cuts the warning into as few pieces as its floors allow: the picture's extent in cells (the nav grid's own cells
-- when it is not turned, finer when it is), each cell kept at every covered floor under it; then from each unused
-- floor a rectangle grows in all four directions while every cell it takes is a floor at that height or outside the
-- shape. Every seam is a place where a wall, a step or a ledge really is: on open ground a warning is ONE piece.
-- Fills `rects` (x0, x1, z0, z1, dy per piece).
local function buildRects(kind: number, center: Vector3, yaw: number, size: number, width: number, rects: { number })
	local nav = ArenaCore.Nav
	local maxLayers = ArenaCore.MAX_LAYERS
	local x0, x1, z0, z1 = imageRect(kind, size, width, 1)
	table.clear(reusableFootprint)
	local floorY = TelegraphCore.Footprint(nav, kind, center :: any, yaw, size, width, reusableFootprint)
	local isAligned = yaw == 0
	local step = if isAligned then ArenaCore.CELL_SIZE else Tune.FINE_STEP
	local phaseX = if nav and isAligned then nav.OriginX - nav.CellSize / 2 - center.X else x0
	local phaseZ = if nav and isAligned then nav.OriginZ - nav.CellSize / 2 - center.Z else z0
	local nx = gridLines(reusableXs, x0, x1, step, phaseX) - 1
	local nz = gridLines(reusableZs, z0, z1, step, phaseZ) - 1
	local reach = step * 0.7072
	local c, s = math.cos(yaw), math.sin(yaw)

	table.clear(reusableCounts)
	table.clear(reusableHeights)
	table.clear(reusableUsed)
	table.clear(reusableOutside)
	for j = 1, nz do
		local z = (reusableZs[j] + reusableZs[j + 1]) / 2
		for i = 1, nx do
			local cell = (j - 1) * nx + i
			local base = (cell - 1) * maxLayers
			local x = (reusableXs[i] + reusableXs[i + 1]) / 2
			reusableCounts[cell] = 0
			reusableOutside[cell] = TelegraphCore.Distance(kind, size, width, x, z) > reach
			if reusableOutside[cell] then continue end
			if not nav or not floorY then
				reusableCounts[cell] = 1
				reusableHeights[base + 1] = center.Y
				continue
			end

			-- The frame's local (x, z) in the world, then the nav cell under it.
			local wx, wz = center.X + x * c + z * s, center.Z - x * s + z * c
			local cx = math.floor((wx - nav.OriginX) / nav.CellSize + 0.5)
			local cz = math.floor((wz - nav.OriginZ) / nav.CellSize + 0.5)
			if cx < 0 or cx >= nav.Width or cz < 0 or cz >= nav.Depth then continue end
			local navCell = cz * nav.Width + cx
			local first = buffer.readu32(nav.CellFirstNode, navCell * 4)
			local count = 0
			for node = first, first + buffer.readu8(nav.CellLayerCount, navCell) - 1 do
				if not reusableFootprint[node] then continue end
				count += 1
				reusableHeights[base + count] = skin[node] or ArenaCore.NodeHeight(nav, node)
			end

			reusableCounts[cell] = count
		end
	end

	table.clear(rects)
	local written = 0
	for j = 1, nz do
		for i = 1, nx do
			local cell = (j - 1) * nx + i
			local base = (cell - 1) * maxLayers
			for k = 1, reusableCounts[cell] do
				if reusableUsed[base + k] then continue end
				reusableUsed[base + k] = true
				local height = reusableHeights[base + k]
				local top = height
				local i0, i1, j0, j1 = i, i, j, j
				local isGrowing = true
				while isGrowing do
					isGrowing = false
					if i1 < nx and isBlockFree(nx, i1 + 1, i1 + 1, j0, j1, height) then
						top = claimBlock(nx, i1 + 1, i1 + 1, j0, j1, height, top)
						i1 += 1
						isGrowing = true
					end
					if i0 > 1 and isBlockFree(nx, i0 - 1, i0 - 1, j0, j1, height) then
						top = claimBlock(nx, i0 - 1, i0 - 1, j0, j1, height, top)
						i0 -= 1
						isGrowing = true
					end
					if j1 < nz and isBlockFree(nx, i0, i1, j1 + 1, j1 + 1, height) then
						top = claimBlock(nx, i0, i1, j1 + 1, j1 + 1, height, top)
						j1 += 1
						isGrowing = true
					end
					if j0 > 1 and isBlockFree(nx, i0, i1, j0 - 1, j0 - 1, height) then
						top = claimBlock(nx, i0, i1, j0 - 1, j0 - 1, height, top)
						j0 -= 1
						isGrowing = true
					end
				end

				rects[written + 1] = reusableXs[i0]
				rects[written + 2] = reusableXs[i1 + 1]
				rects[written + 3] = reusableZs[j0]
				rects[written + 4] = reusableZs[j1 + 1]
				rects[written + 5] = top - center.Y + Tune.LIFT
				written += 5
			end
		end
	end
end

-- ============================== Points ==============================

-- The length of a shape's outline.
local function perimeterOf(kind: number, size: number, width: number): number
	if kind == ETelegraphs.Line then return 2 * (size + width) end
	if kind == ETelegraphs.Cone then return size * (math.rad(width) + 2) end
	return 2 * math.pi * size
end

-- How much floor a shape covers, in square studs.
local function areaOf(kind: number, size: number, width: number): number
	if kind == ETelegraphs.Line then return size * width end
	if kind == ETelegraphs.Cone then return size * size * math.rad(width) / 2 end
	return math.pi * size * size
end

-- A random point (local x, z) on the outline of the shape grown to `reach` from its anchor. The whole outline when
-- `isFront` is false; when it is true, only the edge its fill leads with (a cone's arc, a line's far end).
local function outlinePoint(kind: number, width: number, reach: number, isFront: boolean): (number, number)
	if kind == ETelegraphs.Line then
		local halfWidth = width / 2
		if isFront then return random:NextNumber(-halfWidth, halfWidth), reach end
		local along = random:NextNumber(0, 2 * (reach + width))
		if along < 2 * reach then return if along < reach then -halfWidth else halfWidth, along % reach end
		along -= 2 * reach
		return along % width - halfWidth, if along < width then 0 else reach
	end

	local half = if kind == ETelegraphs.Cone then math.rad(width / 2) else math.pi
	-- A cone's arc against its two straight sides, by length.
	if kind == ETelegraphs.Cone and not isFront and random:NextNumber(0, 2 * half + 2) >= 2 * half then
		local along = random:NextNumber(0, reach)
		local side = if random:NextNumber() < 0.5 then -1 else 1
		return side * math.sin(half) * along, math.cos(half) * along
	end
	local angle = random:NextNumber(-half, half)
	return math.sin(angle) * reach, math.cos(angle) * reach
end

-- A random point (local x, z) spread evenly over the shape.
local function areaPoint(kind: number, size: number, width: number): (number, number)
	if kind == ETelegraphs.Line then return random:NextNumber(-width / 2, width / 2), random:NextNumber(0, size) end
	local reach = size * math.sqrt(random:NextNumber())
	local half = if kind == ETelegraphs.Cone then math.rad(width / 2) else math.pi
	local angle = random:NextNumber(-half, half)
	return math.sin(angle) * reach, math.cos(angle) * reach
end

-- The height above its centre of the piece a warning lies on at local (x, z), nil off its pieces: past a wall or a
-- ledge, or on a deck the hit does not reach.
local function surfaceAt(rects: { number }, x: number, z: number): number?
	for r = 0, #rects - 5, 5 do
		if x >= rects[r + 1] and x <= rects[r + 2] and z >= rects[r + 3] and z <= rects[r + 4] then
			return rects[r + 5]
		end
	end

	return nil
end

-- The colour of the floor at `position`, kept per nav node (floorColors).
local function floorColorAt(position: Vector3): Color3
	local nav = ArenaCore.Nav
	local node = if nav then ArenaCore.NodeAt(nav, position.X, position.Y, position.Z, Tune.SKIN_REACH) else nil
	local known = if node then floorColors[node] else nil
	if known then return known end

	local result = sightCast(position + Vector3.new(0, 1, 0), Vector3.new(0, -3, 0))
	local color = if result then result.Instance.Color else Tune.NO_FLOOR_COLOR
	if node and node ~= ArenaCore.NO_NODE then floorColors[node] = color end
	return color
end

-- Keeps the `found`-th point (local x, z) when it is on the warning's own floor, into reusablePoints, and for the
-- first `bricks` the floor's height and colour there into reusableFloors and reusableColors. Returns whether it was.
local function keepPoint(telegraph: TTelegraph, found: number, bricks: number, x: number, z: number): boolean
	local dy = surfaceAt(telegraph.Rects, x, z)
	if not dy then return false end

	local point = telegraph.Frame * Vector3.new(x, dy, z)
	reusablePoints[found] = point
	if found <= bricks then
		reusableFloors[found] = point.Y - Tune.LIFT
		reusableColors[found] = floorColorAt(point)
	end
	return true
end

-- Up to `count` points on the warning's outline grown to `reach` (`isFront` as outlinePoint takes it), kept as
-- keepPoint keeps them. Returns how many.
local function gatherOutline(
	telegraph: TTelegraph,
	count: number,
	bricks: number,
	reach: number,
	isFront: boolean
): number
	local kind, width = telegraph.Kind, telegraph.Width
	local found = 0
	for _ = 1, count * Tune.TRIES do
		if found >= count then break end
		local x, z = outlinePoint(kind, width, reach, isFront)
		if keepPoint(telegraph, found + 1, bricks, x, z) then
			found += 1
		end
	end

	return found
end

-- Up to `count` points spread over the warning, kept as keepPoint keeps them. Returns how many.
local function gatherArea(telegraph: TTelegraph, count: number, bricks: number): number
	local kind, size, width = telegraph.Kind, telegraph.Size, telegraph.Width
	local found = 0
	for _ = 1, count * Tune.TRIES do
		if found >= count then break end
		local x, z = areaPoint(kind, size, width)
		if keepPoint(telegraph, found + 1, bricks, x, z) then
			found += 1
		end
	end

	return found
end

-- Pixels owed to `debt` after `seconds` at `perSecond`, thinned by distance; the fraction carries to the next frame.
local function owed(debt: number, perSecond: number, seconds: number, share: number): (number, number)
	debt += perSecond * seconds * share
	local whole = math.floor(debt)
	return whole, debt - whole
end

-- ============================== Juice ==============================

-- A warning appears: its rim's pixels pop up all round, and a round one opens a square ring from its centre.
local function appear(telegraph: TTelegraph)
	local center = telegraph.Frame.Position
	local share = telegraphFx.Share(center)
	if share <= 0 then return end

	local kind = telegraph.Kind
	if kind == ETelegraphs.Circle or kind == ETelegraphs.Ring then
		telegraphFx.Ping(telegraph.Palette, center, telegraph.Size)
	end
	local count = math.floor(telegraph.Perimeter * Tune.RIM_MOTES_POP * share)
	local found = gatherOutline(telegraph, count, 0, telegraph.Size - Tune.RIM_INSET, false)
	telegraphFx.Motes(telegraph.Palette, reusablePoints, found)
end

-- One wind-up frame's pixels: off the rim, faster as the hit nears, and off the fill's front.
local function charge(telegraph: TTelegraph, progress: number, dt: number)
	local share = telegraphFx.Share(telegraph.Frame.Position)
	if share <= 0 then return end

	local kind, size = telegraph.Kind, telegraph.Size
	local perSecond = telegraph.Perimeter
		* (Tune.RIM_MOTES_START + (Tune.RIM_MOTES_END - Tune.RIM_MOTES_START) * progress * progress)
	local count
	count, telegraph.RimDebt = owed(telegraph.RimDebt, perSecond, dt, share)
	if count > 0 then
		local found = gatherOutline(telegraph, count, 0, size - Tune.RIM_INSET, false)
		telegraphFx.Motes(telegraph.Palette, reusablePoints, found)
	end

	-- A shockwave's fill is its front rolling out after the wind-up (Rolling).
	if kind == ETelegraphs.Ring then return end
	local front = if kind == ETelegraphs.Line
		then telegraph.Width
		elseif kind == ETelegraphs.Cone then size * progress * math.rad(telegraph.Width)
		else 2 * math.pi * size * progress
	count, telegraph.FrontDebt = owed(telegraph.FrontDebt, front * Tune.FRONT_MOTES, dt, share)
	if count > 0 then
		local found = gatherOutline(telegraph, count, 0, size * progress, true)
		telegraphFx.Motes(telegraph.Palette, reusablePoints, found)
	end
end

-- The blow lands: the floor lit, a square shock on a round one, an explosion's heart, pixels shooting out of the
-- whole area and the floor's own bricks knocked loose. A shockwave slams only where it starts; its front does the
-- rest as it rolls (roll).
local function burst(telegraph: TTelegraph)
	local center = telegraph.Frame.Position
	local kind = telegraph.Kind
	local isRing = kind == ETelegraphs.Ring
	local radius = if isRing then math.min(telegraph.Size, Tune.RING_SLAM_RADIUS) else telegraph.Size
	local hasShock = isRing or kind == ETelegraphs.Circle
	telegraph.Dust = floorColorAt(center)
	if not telegraphFx.Land(telegraph.Palette, center, radius, hasShock, telegraph.IsExplosion) then return end
	if isRing then return end

	local share = telegraphFx.Share(center) * (if telegraph.IsExplosion then Tune.BLAST_SHARE else 1)
	local area = areaOf(kind, telegraph.Size, telegraph.Width)
	local sprays = math.ceil(math.clamp(area * Tune.SPRAY_PER_AREA, Tune.SPRAY_MIN, Tune.SPRAY_MAX) * share)
	local bricks = math.ceil(math.clamp(area * Tune.BRICKS_PER_AREA, Tune.BRICKS_MIN, Tune.BRICKS_MAX) * share)
	local found = gatherArea(telegraph, math.max(sprays, bricks), bricks)
	telegraphFx.Bricks(reusablePoints, reusableFloors, reusableColors, math.min(bricks, found), center)
	telegraphFx.Spray(telegraph.Palette, reusablePoints, math.min(sprays, found), telegraph.Dust)
end

-- One frame of a shockwave's front at `reach` from its centre: pixels and dust kicked up all along it, and bricks
-- torn out of the floor it rolls over.
local function roll(telegraph: TTelegraph, reach: number, dt: number)
	local center = telegraph.Frame.Position
	local share = telegraphFx.Share(center)
	if share <= 0 or reach <= 0 then return end

	local front = 2 * math.pi * reach
	local sprays
	sprays, telegraph.FrontDebt = owed(telegraph.FrontDebt, front * Tune.FRONT_SPRAY, dt, share)
	local bricks
	bricks, telegraph.BrickDebt = owed(telegraph.BrickDebt, front * Tune.FRONT_BRICKS, dt, share)
	local count = math.max(sprays, bricks)
	if count == 0 then return end

	local found = gatherOutline(telegraph, count, bricks, reach, false)
	telegraphFx.Bricks(reusablePoints, reusableFloors, reusableColors, math.min(bricks, found), center)
	telegraphFx.Spray(telegraph.Palette, reusablePoints, math.min(sprays, found), telegraph.Dust)
end

-- A warning taken back: its rim's pixels go grey and sink.
local function fizzle(telegraph: TTelegraph)
	local share = telegraphFx.Share(telegraph.Frame.Position)
	if share <= 0 then return end

	local count = math.ceil(math.min(telegraph.Perimeter * Tune.FIZZLE_PER_STUD, Tune.FIZZLE_MAX) * share)
	local found = gatherOutline(telegraph, count, 0, telegraph.Size - Tune.RIM_INSET, false)
	telegraphFx.Fizzle(reusablePoints, found)
end

-- ============================== Telegraphs ==============================

-- Lays the body's picture at `scale` on every body piece.
local function mapBodies(telegraph: TTelegraph, scale: number)
	local ix0, ix1, iz0, iz1 = imageRect(telegraph.Kind, telegraph.Size, telegraph.Width, scale)
	local rects = telegraph.Rects
	for index, piece in telegraph.Bodies do
		local r = (index - 1) * 5
		mapTexture(piece.Texture, rects[r + 2], rects[r + 4], ix0, ix1, iz0, iz1)
	end
end

-- Shows the sweep's picture over [ix0, ix1] x [iz0, iz1]: each sweep piece is its body piece cut to the picture, so
-- the picture never tiles, and hidden where they do not meet.
local function mapSweeps(telegraph: TTelegraph, ix0: number, ix1: number, iz0: number, iz1: number)
	local rects = telegraph.Rects
	local isEmpty = ix1 - ix0 < 0.05 or iz1 - iz0 < 0.05
	for index, piece in telegraph.Sweeps do
		local r = (index - 1) * 5
		local x0, x1 = math.max(rects[r + 1], ix0), math.min(rects[r + 2], ix1)
		local z0, z1 = math.max(rects[r + 3], iz0), math.min(rects[r + 4], iz1)
		if isEmpty or x1 - x0 < 0.02 or z1 - z0 < 0.02 then
			showPiece(piece, false)
			continue
		end

		placePiece(piece, telegraph.Frame, x0, x1, z0, z1, rects[r + 5] + Tune.SWEEP_LIFT)
		mapTexture(piece.Texture, x1, z1, ix0, ix1, iz0, iz1)
		showPiece(piece, true)
	end
end

local function paint(pieces: { TPiece }, color: Color3, transparency: number)
	for _, piece in pieces do
		local texture = piece.Texture
		texture.Color3 = color
		if piece.Transparency == transparency then continue end
		piece.Transparency = transparency
		texture.Transparency = transparency
	end
end

local function finish(id: number)
	local telegraph = active[id]
	if not telegraph then return end
	active[id] = nil
	for _, piece in telegraph.Bodies do
		releasePiece(piece)
	end

	for _, piece in telegraph.Sweeps do
		releasePiece(piece)
	end
end

local function shakeForBlast(telegraph: TTelegraph)
	local root = selfRoot
	if not root then return end
	local distance = (root.Position - telegraph.Frame.Position).Magnitude
	local felt = 1 - distance / (telegraph.Size * Tune.FELT_RADII)
	if felt <= 0 then return end
	CameraController.Shake(Tune.SHAKE * felt * felt, Tune.SHAKE_ROUGHNESS, Tune.SHAKE_SECONDS)
end

-- The wind-up has run out: a shockwave starts rolling, anything else lands.
local function strike(telegraph: TTelegraph)
	shakeForBlast(telegraph)
	SoundsCore.PlayWorldRandom(Tune.BLOW_GROUP, telegraph.Blow, telegraph.Frame.Position)
	burst(telegraph)
	telegraph.StateElapsed = 0
	if telegraph.Kind == ETelegraphs.Ring then
		telegraph.State = EState.Rolling
		telegraph.FrontDebt = 0
		for _, piece in telegraph.Sweeps do
			piece.Texture.Texture = IMAGES.Ring
		end
		return
	end

	telegraph.State = EState.Impact
	mapSweeps(telegraph, 0, 0, 0, 0)
end

-- Draws a warning: `size` and `width` as TelegraphCore.Distance takes them, `center` on the floor it was cast on,
-- in the boss's colour when a boss cast it, sounding as a blast when it is an explosion's. Replaces any warning
-- already shown under `id`.
function TelegraphController.Show(
	id: number,
	kind: number,
	center: Vector3,
	yaw: number,
	size: number,
	width: number,
	seconds: number,
	speed: number,
	isBoss: boolean,
	isExplosion: boolean
)
	finish(id)
	if kind == ETelegraphs.Cone then width = TelegraphCore.ConeAngle(width) end

	local rects = {}
	buildRects(kind, center, yaw, size, width, rects)
	local count = #rects // 5
	local telegraph: TTelegraph = {
		Kind = kind,
		Color = if isBoss then BOSS_COLOR else COLOR,
		GlowPulse = if isBoss then Tune.BOSS_GLOW_PULSE else Tune.GLOW_PULSE,
		Frame = TelegraphCore.Frame(center, yaw),
		Size = size,
		Width = width,
		Duration = math.max(seconds, 0.05),
		Speed = speed,
		IsExplosion = isExplosion,
		Palette = if isBoss then telegraphFx.BOSS else telegraphFx.ORDINARY,
		Perimeter = perimeterOf(kind, size, width),
		RimDebt = 0,
		FrontDebt = 0,
		BrickDebt = 0,
		Dust = Tune.NO_FLOOR_COLOR,
		Blow = if kind == ETelegraphs.Ring
			then "Shockwave"
			elseif not isExplosion then "Slam"
			elseif size >= Tune.BIG_BLAST_SIZE then "ExplodeBig"
			else "ExplodeSmall",
		Elapsed = 0,
		Phase = 0,
		State = EState.WindUp,
		StateElapsed = 0,
		Rects = rects,
		Bodies = table.create(count),
		Sweeps = table.create(count),
		SweepImage = sweepImage(kind, width),
	}

	local body = bodyImage(kind, size, width)
	for index = 1, count do
		local r = (index - 1) * 5
		local piece = takePiece(body)
		placePiece(piece, telegraph.Frame, rects[r + 1], rects[r + 2], rects[r + 3], rects[r + 4], rects[r + 5])
		telegraph.Bodies[index] = piece
		telegraph.Sweeps[index] = takePiece(telegraph.SweepImage)
	end

	mapBodies(telegraph, Tune.POP_SCALE)
	paint(telegraph.Bodies, telegraph.Color, 1)
	for _, piece in telegraph.Bodies do
		showPiece(piece, true)
	end

	active[id] = telegraph
	appear(telegraph)
end

-- The server says a warning is over. Far from its hit it was taken back and greys out; near it, it lands now if it
-- has not already. A rolling shockwave runs out on its own.
function TelegraphController.End(id: number)
	local telegraph = active[id]
	if not telegraph or telegraph.State ~= EState.WindUp then return end
	if telegraph.Elapsed < telegraph.Duration - Tune.CANCEL_MARGIN then
		telegraph.State = EState.Cancelled
		telegraph.StateElapsed = 0
		mapSweeps(telegraph, 0, 0, 0, 0)
		fizzle(telegraph)
		return
	end

	strike(telegraph)
end

local function easeOutCubic(t: number): number
	return 1 - (1 - t) ^ 3
end

-- One frame of one warning. Returns false once it is done.
local function step(telegraph: TTelegraph, dt: number): boolean
	telegraph.Elapsed += dt
	telegraph.StateElapsed += dt
	local state = telegraph.State

	if state == EState.WindUp then
		local elapsed, duration = telegraph.Elapsed, telegraph.Duration
		local progress = math.clamp(elapsed / duration, 0, 1)
		local pop = math.clamp(elapsed / Tune.POP_SECONDS, 0, 1)
		if pop < 1 or elapsed - dt < Tune.POP_SECONDS then
			mapBodies(telegraph, Tune.POP_SCALE + (1 - Tune.POP_SCALE) * easeOutCubic(pop))
		end

		local hz = Tune.PULSE_HZ_START + (Tune.PULSE_HZ_END - Tune.PULSE_HZ_START) * progress * progress
		telegraph.Phase += 2 * math.pi * hz * dt
		local glow = Tune.GLOW_BASE + telegraph.GlowPulse * (0.5 + 0.5 * math.cos(telegraph.Phase))
		local heat = math.clamp((elapsed - (duration - Tune.WARN_SECONDS)) / Tune.WARN_SECONDS, 0, 1) * Tune.WARN_HEAT
		local color = telegraph.Color
		local tint = Color3.new(color.R * glow, color.G * glow, color.B * glow):Lerp(WHITE_HOT, heat)
		paint(telegraph.Bodies, tint, 1 - pop)
		paint(telegraph.Sweeps, tint:Lerp(WHITE_HOT, 0.25), 0)

		-- A fill means "this lands when it is full", and a shockwave does not land then: it starts rolling, and only its
		-- front hurts. So its wind-up is the outline alone, and the fill is the front itself (Rolling).
		if telegraph.Kind ~= ETelegraphs.Ring then
			local ix0, ix1, iz0, iz1 = imageRect(telegraph.Kind, telegraph.Size, telegraph.Width, progress)
			mapSweeps(telegraph, ix0, ix1, iz0, iz1)
		end
		charge(telegraph, progress, dt)
		if elapsed >= duration then strike(telegraph) end
		return true
	end

	if state == EState.Impact then
		local t = math.clamp(telegraph.StateElapsed / Tune.IMPACT_SECONDS, 0, 1)
		mapBodies(telegraph, 1 + Tune.IMPACT_SWELL * easeOutCubic(t))
		paint(telegraph.Bodies, WHITE_HOT:Lerp(telegraph.Color, t), easeOutCubic(t))
		return t < 1
	end

	if state == EState.Rolling then
		local travelled = telegraph.StateElapsed * telegraph.Speed
		local reach = math.min(travelled, telegraph.Size)
		local ix0, ix1, iz0, iz1 = imageRect(ETelegraphs.Ring, reach, 0, 1)
		mapSweeps(telegraph, ix0, ix1, iz0, iz1)
		if travelled < telegraph.Size then roll(telegraph, reach - Tune.RIM_INSET, dt) end
		local fade = math.clamp((travelled - telegraph.Size) / (telegraph.Speed * Tune.ROLL_FADE_SECONDS), 0, 1)
		paint(telegraph.Bodies, telegraph.Color, Tune.ROLL_BODY_TRANSPARENCY + (1 - Tune.ROLL_BODY_TRANSPARENCY) * fade)
		paint(telegraph.Sweeps, WHITE_HOT:Lerp(telegraph.Color, 0.5), fade)
		return fade < 1
	end

	local t = math.clamp(telegraph.StateElapsed / Tune.CANCEL_SECONDS, 0, 1)
	paint(telegraph.Bodies, CANCEL_COLOR, t)
	paint(telegraph.Sweeps, CANCEL_COLOR, t)
	return t < 1
end

-- The client floods warnings over its own copy of the nav grid, baked from the same map the server baked.
-- Stamps one trim part onto the nav nodes under it whose floor it lies on.
local function stampTrim(nav: ArenaCore.TNavGrid, part: BasePart)
	local frame = part.CFrame
	local size = part.Size
	local top = frame.Position.Y + size.Y / 2
	local right, look = frame.RightVector, frame.LookVector
	local reachX = math.abs(right.X) * size.X / 2 + math.abs(look.X) * size.Z / 2
	local reachZ = math.abs(right.Z) * size.X / 2 + math.abs(look.Z) * size.Z / 2
	local cellSize = nav.CellSize
	local cx0 = math.max(math.ceil((frame.Position.X - reachX - nav.OriginX) / cellSize), 0)
	local cx1 = math.min(math.floor((frame.Position.X + reachX - nav.OriginX) / cellSize), nav.Width - 1)
	local cz0 = math.max(math.ceil((frame.Position.Z - reachZ - nav.OriginZ) / cellSize), 0)
	local cz1 = math.min(math.floor((frame.Position.Z + reachZ - nav.OriginZ) / cellSize), nav.Depth - 1)

	for cz = cz0, cz1 do
		for cx = cx0, cx1 do
			local at = Vector3.new(nav.OriginX + cx * cellSize, frame.Position.Y, nav.OriginZ + cz * cellSize)
			local offset = frame:PointToObjectSpace(at)
			if math.abs(offset.X) > size.X / 2 or math.abs(offset.Z) > size.Z / 2 then continue end
			local cell = cz * nav.Width + cx
			local first = buffer.readu32(nav.CellFirstNode, cell * 4)
			for node = first, first + buffer.readu8(nav.CellLayerCount, cell) - 1 do
				local floorY = ArenaCore.NodeHeight(nav, node)
				if top <= floorY or top - floorY > Tune.SKIN_REACH or top < (skin[node] or floorY) then continue end
				skin[node] = top
				floorColors[node] = part.Color
			end
		end
	end
end

-- The client floods warnings over its own copy of the nav grid, baked from the same map the server baked. The bake
-- sees only what can be queried, so trim lying on a floor (CanQuery off, so its curves never touch the grid) is
-- stamped on top of it here: a warning on the floor under the pitch's grass is drawn under the grass.
local function bakeArena()
	local arena = Workspace:WaitForChild("Arena", math.huge)
	if not arena then return end
	ArenaCore.Bake()
	local nav = ArenaCore.Nav
	if not nav then return end

	table.clear(skin)
	table.clear(floorColors)
	for _, part in arena:GetDescendants() do
		if not part:IsA("BasePart") or part.CanQuery or part.Transparency >= 1 then continue end
		if part.Size.Y > Tune.SKIN_MAX_THICKNESS or math.abs(part.CFrame.UpVector.Y) < 0.99 then continue end
		stampTrim(nav, part)
	end
end

ServerNetworkEnemies.Telegraph.On(
	function(
		id: number,
		kind: number,
		center: Vector3,
		yaw: number,
		size: number,
		width: number,
		seconds: number,
		speed: number,
		isBoss: boolean,
		isExplosion: boolean
	)
		TelegraphController.Show(id, kind, center, yaw, size, width, seconds, speed, isBoss, isExplosion)
	end
)

ServerNetworkEnemies.TelegraphEnded.On(TelegraphController.End)

TelegraphController.OnStart = function()
	task.spawn(bakeArena)

	RunService.PreRender:Connect(function(dt: number)
		telegraphFx.BeginFrame()
		local enemyDt = TimeCore.GetEnemyDeltaTime(dt)
		for id, telegraph in active do
			if not step(telegraph, enemyDt) then finish(id) end
		end
	end)
end

TelegraphController.OnSelfCharacterAdded = function(character: TCharacter.TCharacter)
	selfRoot = character.HumanoidRootPart
end :: TCharacterEvents.OnCharacterAdded

TelegraphController.OnSelfCharacterRemoving = function()
	selfRoot = nil
end :: TCharacterEvents.OnCharacterRemoving

return Ignis.Register(TelegraphController)
