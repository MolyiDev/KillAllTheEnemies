--!native
--!optimize 2
-- The arena as enemies see it: a LAYERED walk grid baked once per match by raycasting the map (up to MAX_LAYERS
-- floors a cell, for stairs, bridges and platforms you can walk under), and the graph NavService floods. No enemy
-- raycasts during a fight: floor, walls and routes are reads.
--
-- Authoring contract (Studio), all under a map's Model in ServerStorage.Maps, which arenaMap moves to Workspace.Arena:
--   * the map itself. Parts players cannot collide with (water sheets, foliage) are neither floor nor wall;
--   * Blockers: Parts that are never floor and hide everything under them (the invisible walls around the play area,
--     void planes). When there are any, the grid covers only their footprint, so scenery past them costs nothing;
--   * Caps: invisible collision for players only, on top of whatever enemies cannot climb (a canopy, a roof), so
--     no player stands where no enemy can follow. Never floor, never a wall to enemies;
--   * Backdrop: the scenery outside the walls, moved out of the arena when it is placed (arenaMap).
-- With no Workspace.Arena the floor is flat at y = 0 and enemies chase in straight lines.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Signal = require(ReplicatedStorage.Packages.Signal)

local floor = math.floor
local readu8 = buffer.readu8
local readu32 = buffer.readu32
local readf32 = buffer.readf32
local readi32 = buffer.readi32

local ArenaCore = {}

ArenaCore.CELL_SIZE = 2
ArenaCore.MAX_LAYERS = 4
-- How far above its feet an enemy steps up without treating it as a wall. A stair tread is 1; a crate is 3+.
ArenaCore.MAX_STEP = 2.5
-- How far down an enemy will hop off a ledge when routing: a second-floor walkway or roof (7) is a drop, so a crowd
-- takes the short way down instead of queueing for the stairs. Higher ledges are walls to the router; knockback can
-- still throw a body off one, and gravity lands it on whatever is below.
ArenaCore.MAX_DROP = 8
-- Open air a floor needs above it: an enemy's height, so nothing routes under a low beam.
ArenaCore.CLEARANCE = 5
ArenaCore.FLOOR_NORMAL_Y = 0.6
ArenaCore.NO_NODE = -1
-- Integer link costs (Dial's algorithm needs integers): straight 10, diagonal 14.
ArenaCore.COST_ORTHOGONAL = 10
ArenaCore.COST_DIAGONAL = 14

-- Neighbour order: four straight, then four diagonal. Diagonal d (5..8) cuts past straight DIAG_SIDES[d].
ArenaCore.DX = table.freeze({ 1, -1, 0, 0, 1, 1, -1, -1 })
ArenaCore.DZ = table.freeze({ 0, 0, 1, -1, 1, -1, 1, -1 })
ArenaCore.OPPOSITE = table.freeze({ 2, 1, 4, 3, 8, 7, 6, 5 })
local DIAG_SIDE_A = { 0, 0, 0, 0, 1, 1, 2, 2 }
local DIAG_SIDE_B = { 0, 0, 0, 0, 3, 4, 3, 4 }

local RAYS_PER_YIELD = 4096

export type TNavGrid = {
	Width: number,
	Depth: number,
	CellSize: number,
	OriginX: number,
	OriginZ: number,
	MinY: number,
	NodeCount: number,
	-- Per cell: first node index (u32) and how many floors (u8).
	CellFirstNode: buffer,
	CellLayerCount: buffer,
	-- Per node: floor height (f32), owning cell (u32), and its 8 outgoing links (i32, NO_NODE when blocked).
	NodeHeight: buffer,
	NodeCell: buffer,
	NodeLinks: buffer,
	-- The same links reversed, packed: node n's incoming links are entries IncomingStart[n] .. IncomingStart[n + 1] - 1
	-- of IncomingNode (i32, the node the link comes from) and IncomingCost (u8). Flowfields flood over these.
	IncomingStart: buffer,
	IncomingNode: buffer,
	IncomingCost: buffer,
}

-- nil until Bake runs, and nil for good in a place with no arena.
ArenaCore.Nav = nil :: TNavGrid?
ArenaCore.FlatY = 0
-- Fired once Bake has published a new grid.
ArenaCore.OnBaked = Signal.new()

local function getChild(arena: Instance, name: string): Instance?
	return arena:FindFirstChild(name)
end

-- The world-axis XZ box around every part under `folder`, or nil when it holds none.
local function getFootprint(folder: Instance): (number?, number, number, number)
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, part in folder:GetDescendants() do
		if not part:IsA("BasePart") then continue end
		local cframe = part.CFrame
		local half = part.Size / 2
		-- A rotated box's world half extents: each local axis's half length, projected.
		local extentX = math.abs(cframe.RightVector.X) * half.X
			+ math.abs(cframe.UpVector.X) * half.Y
			+ math.abs(cframe.LookVector.X) * half.Z
		local extentZ = math.abs(cframe.RightVector.Z) * half.X
			+ math.abs(cframe.UpVector.Z) * half.Y
			+ math.abs(cframe.LookVector.Z) * half.Z
		local position = cframe.Position
		minX = math.min(minX, position.X - extentX)
		maxX = math.max(maxX, position.X + extentX)
		minZ = math.min(minZ, position.Z - extentZ)
		maxZ = math.max(maxZ, position.Z + extentZ)
	end

	if minX > maxX then return nil, 0, 0, 0 end
	return minX, maxX, minZ, maxZ
end

-- Bakes Workspace.Arena into ArenaCore.Nav. Yields (a few frames on a big map). Call before enemies spawn.
-- Each cell is rays straight down, the next starting just under the last hit: inside the part, which a raycast
-- ignores, so it finds what is under a bridge. A hit on Blockers ends the column.
function ArenaCore.Bake()
	local arena = Workspace:FindFirstChild("Arena")
	if not arena or not arena:IsA("Model") then
		ArenaCore.Nav = nil
		return
	end

	local caps = getChild(arena, "Caps")
	local blockers = getChild(arena, "Blockers")
	local include = {}

	for _, child in arena:GetChildren() do
		if child ~= caps then include[#include + 1] = child end
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = include
	rayParams.IgnoreWater = false
	rayParams.RespectCanCollide = true
	local boxParams = OverlapParams.new()
	boxParams.FilterType = Enum.RaycastFilterType.Include
	boxParams.FilterDescendantsInstances = include
	boxParams.MaxParts = 1
	boxParams.RespectCanCollide = true

	-- Height from the whole arena; the ground plan from the Blockers' footprint when there are any.
	local boundsCFrame, boundsSize = arena:GetBoundingBox()
	local center = boundsCFrame.Position
	local minX, maxX, minZ, maxZ =
		center.X - boundsSize.X / 2,
		center.X + boundsSize.X / 2,
		center.Z - boundsSize.Z / 2,
		center.Z + boundsSize.Z / 2
	if blockers then
		local footMinX, footMaxX, footMinZ, footMaxZ = getFootprint(blockers)
		if footMinX then
			minX, maxX, minZ, maxZ = footMinX, footMaxX, footMinZ, footMaxZ
		end
	end

	local cellSize = ArenaCore.CELL_SIZE
	local maxLayers = ArenaCore.MAX_LAYERS
	local clearance = ArenaCore.CLEARANCE
	local width = math.ceil((maxX - minX) / cellSize) + 1
	local depth = math.ceil((maxZ - minZ) / cellSize) + 1
	local originX = (minX + maxX) / 2 - (width - 1) * cellSize / 2
	local originZ = (minZ + maxZ) / 2 - (depth - 1) * cellSize / 2
	local topY = center.Y + boundsSize.Y / 2 + 1
	local bottomY = center.Y - boundsSize.Y / 2 - 1
	-- Floors per cell, highest first, by raycasting.
	local floors: { { number } } = table.create(width * depth)
	local rays = 0
	local clearBox = Vector3.new(cellSize * 0.8, clearance - 0.6, cellSize * 0.8)

	for z = 0, depth - 1 do
		for x = 0, width - 1 do
			local worldX = originX + x * cellSize
			local worldZ = originZ + z * cellSize
			local column = {}
			local fromY = topY
			local ceilingY = math.huge
			while #column < maxLayers and fromY > bottomY do
				local origin = Vector3.new(worldX, fromY, worldZ)
				local hit = Workspace:Raycast(origin, Vector3.new(0, bottomY - fromY, 0), rayParams)
				rays += 1
				if rays % RAYS_PER_YIELD == 0 then task.wait() end
				if not hit then break end
				if blockers and hit.Instance:IsDescendantOf(blockers) then break end
				if hit.Material == Enum.Material.Water then break end
				local y = hit.Position.Y
				local isFloor = hit.Normal.Y >= ArenaCore.FLOOR_NORMAL_Y and ceilingY - y >= clearance
				-- Under another floor, the air between may still be solid (a cliff sitting on the ground).
				if isFloor and ceilingY ~= math.huge then
					local box = CFrame.new(worldX, y + 0.3 + (clearance - 0.6) / 2, worldZ)
					isFloor = #Workspace:GetPartBoundsInBox(box, clearBox, boxParams) == 0
				end

				if isFloor then table.insert(column, y) end
				ceilingY = y
				fromY = y - 0.05
			end

			floors[z * width + x + 1] = column
		end
	end

	local nav = ArenaCore.Build(width, depth, cellSize, originX, originZ, floors)
	ArenaCore.Nav = nav
	ArenaCore.OnBaked:Fire(nav)
end

-- Builds the nav graph from sampled floors: `floors[z * width + x + 1]` is cell (x, z)'s floor heights, highest first.
-- Pure, so a synthetic map can be built and flooded in tests without a place. A link is one-way where a drop is
-- allowed and the climb back is not.
function ArenaCore.Build(
	width: number,
	depth: number,
	cellSize: number,
	originX: number,
	originZ: number,
	floors: { { number } }
): TNavGrid
	local cellCount = width * depth
	local cellFirst = buffer.create(cellCount * 4)
	local cellLayers = buffer.create(cellCount)
	local nodeCount = 0

	for cell = 0, cellCount - 1 do
		local column = floors[cell + 1] or {}
		buffer.writeu32(cellFirst, cell * 4, nodeCount)
		buffer.writeu8(cellLayers, cell, math.min(#column, ArenaCore.MAX_LAYERS))
		nodeCount += math.min(#column, ArenaCore.MAX_LAYERS)
	end

	local nodeHeight = buffer.create(math.max(nodeCount, 1) * 4)
	local nodeCell = buffer.create(math.max(nodeCount, 1) * 4)
	local nodeLinks = buffer.create(math.max(nodeCount, 1) * 32)
	local minY = math.huge
	local node = 0

	for cell = 0, cellCount - 1 do
		local column = floors[cell + 1] or {}
		for i = 1, math.min(#column, ArenaCore.MAX_LAYERS) do
			buffer.writef32(nodeHeight, node * 4, column[i])
			buffer.writeu32(nodeCell, node * 4, cell)
			if column[i] < minY then minY = column[i] end
			node += 1
		end
	end

	local nav: TNavGrid = {
		Width = width,
		Depth = depth,
		CellSize = cellSize,
		OriginX = originX,
		OriginZ = originZ,
		MinY = if nodeCount > 0 then minY else ArenaCore.FlatY,
		NodeCount = nodeCount,
		CellFirstNode = cellFirst,
		CellLayerCount = cellLayers,
		NodeHeight = nodeHeight,
		NodeCell = nodeCell,
		NodeLinks = nodeLinks,
		IncomingStart = buffer.create(4),
		IncomingNode = buffer.create(4),
		IncomingCost = buffer.create(1),
	}

	local dx, dz = ArenaCore.DX, ArenaCore.DZ
	for from = 0, nodeCount - 1 do
		local cell = readu32(nodeCell, from * 4)
		local cx = cell % width
		local cz = cell // width
		local h = readf32(nodeHeight, from * 4)
		for d = 1, 8 do
			local target = ArenaCore.StepTarget(nav, cx + dx[d], cz + dz[d], h)
			if target ~= ArenaCore.NO_NODE and d > 4 then
				-- No cutting a wall's corner: both straight cells beside the diagonal must be walkable too.
				local sideA, sideB = DIAG_SIDE_A[d], DIAG_SIDE_B[d]
				if
					ArenaCore.StepTarget(nav, cx + dx[sideA], cz + dz[sideA], h) == ArenaCore.NO_NODE
					or ArenaCore.StepTarget(nav, cx + dx[sideB], cz + dz[sideB], h) == ArenaCore.NO_NODE
				then
					target = ArenaCore.NO_NODE
				end
			end

			buffer.writei32(nodeLinks, from * 32 + (d - 1) * 4, target)
		end
	end

	-- Reverse the links into packed incoming lists: count, prefix-sum, fill.
	local incomingCount = table.create(nodeCount, 0)
	local total = 0

	for from = 0, nodeCount - 1 do
		for d = 1, 8 do
			local to = buffer.readi32(nodeLinks, from * 32 + (d - 1) * 4)
			if to == ArenaCore.NO_NODE then continue end
			incomingCount[to + 1] += 1
			total += 1
		end
	end

	local incomingStart = buffer.create((nodeCount + 1) * 4)
	local cursor = table.create(nodeCount, 0)
	local running = 0

	for n = 0, nodeCount - 1 do
		buffer.writeu32(incomingStart, n * 4, running)
		cursor[n + 1] = running
		running += incomingCount[n + 1]
	end

	buffer.writeu32(incomingStart, nodeCount * 4, running)
	local incomingNode = buffer.create(math.max(total, 1) * 4)
	local incomingCost = buffer.create(math.max(total, 1))

	for from = 0, nodeCount - 1 do
		for d = 1, 8 do
			local to = buffer.readi32(nodeLinks, from * 32 + (d - 1) * 4)
			if to == ArenaCore.NO_NODE then continue end
			local at = cursor[to + 1]
			cursor[to + 1] = at + 1
			buffer.writei32(incomingNode, at * 4, from)
			buffer.writeu8(incomingCost, at, if d > 4 then ArenaCore.COST_DIAGONAL else ArenaCore.COST_ORTHOGONAL)
		end
	end

	nav.IncomingStart = incomingStart
	nav.IncomingNode = incomingNode
	nav.IncomingCost = incomingCost
	return nav
end

-- The floor in cell (cx, cz) a body standing at height `fromY` would step onto: the highest one at most MAX_STEP
-- above and at most MAX_DROP below. NO_NODE when there is none (a wall, a cliff, off the map), or when a floor too
-- high to step onto stands below head height: that is a parapet in the way, not a floor overhead, and the ground
-- under it would otherwise read as a drop straight through it.
function ArenaCore.StepTarget(nav: TNavGrid, cx: number, cz: number, fromY: number): number
	if cx < 0 or cx >= nav.Width or cz < 0 or cz >= nav.Depth then return ArenaCore.NO_NODE end

	local cell = cz * nav.Width + cx
	local first = readu32(nav.CellFirstNode, cell * 4)
	local count = readu8(nav.CellLayerCount, cell)
	local maxY = fromY + ArenaCore.MAX_STEP
	local minY = fromY - ArenaCore.MAX_DROP

	local headY = fromY + ArenaCore.CLEARANCE

	for i = 0, count - 1 do
		local h = readf32(nav.NodeHeight, (first + i) * 4)
		if h > maxY then
			if h < headY then return ArenaCore.NO_NODE end
			continue
		end

		if h < minY then return ArenaCore.NO_NODE end
		return first + i
	end

	return ArenaCore.NO_NODE
end

-- The node a body at (x, feetY, z) stands on or is falling toward: the highest floor of its cell no more than
-- `tolerance` above its feet. A walking body passes MAX_STEP, which is what carries it up a stair; a character's
-- position passes a small one. NO_NODE off the grid or over nothing.
function ArenaCore.NodeAt(nav: TNavGrid, x: number, feetY: number, z: number, tolerance: number): number
	local cx = floor((x - nav.OriginX) / nav.CellSize + 0.5)
	local cz = floor((z - nav.OriginZ) / nav.CellSize + 0.5)
	if cx < 0 or cx >= nav.Width or cz < 0 or cz >= nav.Depth then return ArenaCore.NO_NODE end

	local cell = cz * nav.Width + cx
	local first = readu32(nav.CellFirstNode, cell * 4)
	local count = readu8(nav.CellLayerCount, cell)
	local maxY = feetY + tolerance

	for i = 0, count - 1 do
		if readf32(nav.NodeHeight, (first + i) * 4) <= maxY then return first + i end
	end

	return ArenaCore.NO_NODE
end

function ArenaCore.NodeHeight(nav: TNavGrid, node: number): number
	return readf32(nav.NodeHeight, node * 4)
end

-- The node's outgoing link in direction d (1..8), or NO_NODE.
function ArenaCore.Link(nav: TNavGrid, node: number, d: number): number
	return readi32(nav.NodeLinks, node * 32 + (d - 1) * 4)
end

-- World XZ of a node's cell centre.
function ArenaCore.NodeXZ(nav: TNavGrid, node: number): (number, number)
	local cell = readu32(nav.NodeCell, node * 4)
	return nav.OriginX + (cell % nav.Width) * nav.CellSize, nav.OriginZ + (cell // nav.Width) * nav.CellSize
end

-- The floor height under a point, for code outside the hot loop (spawning, placing). Flat ground without an arena.
function ArenaCore.GetFloorY(x: number, z: number, fromY: number?): number?
	local nav = ArenaCore.Nav
	if not nav then return ArenaCore.FlatY end
	local node = ArenaCore.NodeAt(nav, x, fromY or math.huge, z, 0)
	if node == ArenaCore.NO_NODE then return nil end
	return readf32(nav.NodeHeight, node * 4)
end

return ArenaCore
