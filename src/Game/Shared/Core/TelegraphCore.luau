-- The ground warnings' shapes and the floor they cover, on both sides: EnemyAttacksService hits with these and
-- TelegraphController draws them, so the warning drawn is the area that hurts.
--
-- A warning covers the FLOOR it was cast on and what that floor runs into without a wall or a ledge between: it
-- floods out over ArenaCore's links from the floor under its centre, through stairs, never through a wall, never up
-- onto a deck or down off one. Both sides flood the same nav grid (the client bakes its own copy), so they agree.
--
-- Local coordinates: x to the right, z forward (CFrame.Angles(0, yaw, 0) of +Z), from the warning's centre.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ArenaCore = require(ReplicatedStorage.Shared.Core.ArenaCore)
local ETelegraphs = require(ReplicatedStorage.Types.Enums.ETelegraphs)
local TData = require(ReplicatedStorage.Types.TData)

local NO_NODE = ArenaCore.NO_NODE

local TelegraphCore = {}

-- A warning in its wind-up, as the server holds it while it waits to land. A boss's and an ordinary enemy's warnings
-- are two classes: they may lie on each other, two of one class may not.
export type TWarning = {
	IsBoss: boolean,
	Kind: number,
	Center: vector,
	Yaw: number,
	Size: number,
	Width: number,
}

-- How far above or below its centre a warning reaches at most, flood or not (and the whole rule with no nav grid).
TelegraphCore.HEIGHT = 6
-- A feet position is over the floor it stands on within this (a step's lip, a landing).
TelegraphCore.FEET_TOLERANCE = 0.75
-- A shockwave's band, and how high above its floor a jump clears it.
TelegraphCore.RING_BAND = 2.5
TelegraphCore.RING_CLEARANCE = 2.5
-- The full angles a cone may have: each is its own texture (Assets/effects/telegraphs/make_telegraph_textures.py).
TelegraphCore.CONE_ANGLES = table.freeze({ 60, 90, 120 })

-- A cell is part of a warning when its centre is this close to the shape: half a cell's diagonal, so every cell the
-- shape touches is in.
local CELL_REACH = ArenaCore.CELL_SIZE * 0.7072

-- The supported cone angle nearest `degrees`: both sides snap to it, so a typo in data still draws what hits.
function TelegraphCore.ConeAngle(degrees: number): number
	local best = TelegraphCore.CONE_ANGLES[1]
	for _, angle in TelegraphCore.CONE_ANGLES do
		if math.abs(angle - degrees) < math.abs(best - degrees) then best = angle end
	end

	return best
end

-- The warning an attack shows: (ETelegraphs kind, size, width) as Distance takes them.
function TelegraphCore.ShapeOf(attack: TData.TEnemyAttack): (number, number, number)
	local kind = attack.Kind
	if kind == "Shockwave" or kind == "Summon" then return ETelegraphs.Ring, attack.Radius or 30, 0 end
	if kind == "Charge" then return ETelegraphs.Line, attack.Radius or 12, attack.Width or 4 end
	if kind ~= "Slam" or attack.Shape == nil or attack.Shape == "Circle" then
		return ETelegraphs.Circle, attack.Radius or 6, 0
	end

	if attack.Shape == "Cone" then
		return ETelegraphs.Cone, attack.Radius or 8, TelegraphCore.ConeAngle(attack.Angle or 90)
	end
	return ETelegraphs.Line, attack.Radius or 12, attack.Width or 4
end

-- The warning's frame: its centre, turned to face `yaw`.
function TelegraphCore.Frame(center: Vector3, yaw: number): CFrame
	return CFrame.new(center) * CFrame.Angles(0, yaw, 0)
end

-- A world point in the warning's local coordinates.
function TelegraphCore.ToLocal(center: vector, yaw: number, point: vector): (number, number)
	local dx, dz = point.x - center.x, point.z - center.z
	local c, s = math.cos(yaw), math.sin(yaw)
	return dx * c - dz * s, dx * s + dz * c
end

-- Signed distance from local (x, z) to the shape, negative inside. Exact for the circle and the line, and close enough
-- near a cone's edges to decide which cells it touches. `size` is the radius (the length for a line), `width` the cone's
-- full angle in degrees or the line's width.
function TelegraphCore.Distance(kind: number, size: number, width: number, x: number, z: number): number
	if kind == ETelegraphs.Line then return math.max(math.abs(x) - width / 2, math.abs(z - size / 2) - size / 2) end

	local radial = math.sqrt(x * x + z * z) - size
	if kind ~= ETelegraphs.Cone then return radial end

	local half = math.rad(width / 2)
	return math.max(radial, math.abs(x) * math.cos(half) - z * math.sin(half))
end

-- The shape's own bounds in local coordinates: (minX, maxX, minZ, maxZ).
function TelegraphCore.Bounds(kind: number, size: number, width: number): (number, number, number, number)
	if kind == ETelegraphs.Line then return -width / 2, width / 2, 0, size end
	if kind ~= ETelegraphs.Cone then return -size, size, -size, size end

	local half = math.rad(width / 2)
	local reachX = size * math.sin(math.min(half, math.pi / 2))
	local backZ = if half > math.pi / 2 then size * math.cos(half) else 0
	return -reachX, reachX, backZ, size
end

-- Whether a new warning (kind, centre, yaw, size, width) would land on `other`, so that the two read as one: its
-- centre or `aim` (where its target stands) is inside `other`, or `other`'s centre is inside it, on the same level.
-- Measured flat, without footprints: a warning on a deck right over another is the one case it gets wrong, and that
-- one only waits.
function TelegraphCore.IsOnTopOf(
	kind: number,
	center: vector,
	yaw: number,
	size: number,
	width: number,
	aim: vector,
	other: TWarning
): boolean
	if math.abs(other.Center.y - center.y) > TelegraphCore.HEIGHT then return false end
	local otherKind, otherCenter, otherYaw = other.Kind, other.Center, other.Yaw
	local otherSize, otherWidth = other.Size, other.Width

	local x, z = TelegraphCore.ToLocal(otherCenter, otherYaw, center)
	if TelegraphCore.Distance(otherKind, otherSize, otherWidth, x, z) <= 0 then return true end
	x, z = TelegraphCore.ToLocal(otherCenter, otherYaw, aim)
	if TelegraphCore.Distance(otherKind, otherSize, otherWidth, x, z) <= 0 then return true end
	x, z = TelegraphCore.ToLocal(center, yaw, otherCenter)
	return TelegraphCore.Distance(kind, size, width, x, z) <= 0
end

-- Fills `out` with the nav nodes the warning covers (node -> true) and returns the height of the floor it was cast
-- on. nil when there is no nav grid or no floor under the centre: then the warning is flat at its centre and
-- reaches HEIGHT up and down.
function TelegraphCore.Footprint(
	nav: ArenaCore.TNavGrid?,
	kind: number,
	center: vector,
	yaw: number,
	size: number,
	width: number,
	out: { [number]: boolean }
): number?
	if not nav then return nil end
	local start = ArenaCore.NodeAt(nav, center.x, center.y, center.z, TelegraphCore.FEET_TOLERANCE)
	if start == NO_NODE then return nil end

	local floorY = ArenaCore.NodeHeight(nav, start)
	local maxStep = ArenaCore.MAX_STEP
	local height = TelegraphCore.HEIGHT
	local c, s = math.cos(yaw), math.sin(yaw)
	local queue = { start }
	local head = 1
	out[start] = true

	while head <= #queue do
		local node = queue[head]
		head += 1
		local nodeY = ArenaCore.NodeHeight(nav, node)
		for d = 1, 8 do
			local next = ArenaCore.Link(nav, node, d)
			if next == NO_NODE or out[next] then continue end
			local nextY = ArenaCore.NodeHeight(nav, next)
			-- A step carries it on; a drop off a ledge or a climb onto a deck does not.
			if math.abs(nextY - nodeY) > maxStep or math.abs(nextY - floorY) > height then continue end
			local wx, wz = ArenaCore.NodeXZ(nav, next)
			local dx, dz = wx - center.x, wz - center.z
			if TelegraphCore.Distance(kind, size, width, dx * c - dz * s, dx * s + dz * c) > CELL_REACH then
				continue
			end
			out[next] = true
			queue[#queue + 1] = next
		end
	end

	return floorY
end

-- Whether a character's feet are in the warning: inside the shape, and on a floor it covers (or within HEIGHT of
-- its centre when it has no footprint).
function TelegraphCore.IsInside(
	nav: ArenaCore.TNavGrid?,
	footprint: { [number]: boolean }?,
	kind: number,
	center: vector,
	yaw: number,
	size: number,
	width: number,
	feet: vector
): boolean
	local x, z = TelegraphCore.ToLocal(center, yaw, feet)
	if TelegraphCore.Distance(kind, size, width, x, z) > 0 then return false end
	if not nav or not footprint then return math.abs(feet.y - center.y) <= TelegraphCore.HEIGHT end

	local node = ArenaCore.NodeAt(nav, feet.x, feet.y, feet.z, TelegraphCore.FEET_TOLERANCE)
	return node ~= NO_NODE and footprint[node] == true
end

-- The floor under the feet a shockwave measures its jump from: the covered node's height, or the centre's without a
-- footprint. nil when the feet are on a floor the warning does not cover.
function TelegraphCore.FloorUnder(
	nav: ArenaCore.TNavGrid?,
	footprint: { [number]: boolean }?,
	center: vector,
	feet: vector
): number?
	if not nav or not footprint then
		return if math.abs(feet.y - center.y) <= TelegraphCore.HEIGHT then center.y else nil
	end

	local node = ArenaCore.NodeAt(nav, feet.x, feet.y, feet.z, TelegraphCore.FEET_TOLERANCE)
	if node == NO_NODE or not footprint[node] then return nil end
	return ArenaCore.NodeHeight(nav, node)
end

return TelegraphCore
