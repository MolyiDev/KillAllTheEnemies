-- What both sides agree on about a shot: where each pellet goes for a seed, how a ray meets an enemy's aim shape, and
-- the tuning every gun shares. The server decides hits with these; the client draws the same pellets.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local LoadoutCore = require(ReplicatedStorage.GlobalShared.Core.LoadoutCore)
local TData = require(ReplicatedStorage.Types.TData)

local EPSILON = 1e-6
-- A lean toward one end this small, as a share of the gun's length, is no lean: a model of one mesh, or of meshes on
-- one centre, weighs the same both ways, and the engine's float noise would pick an end differently for each copy
-- and scale (a picture facing back while the hand holds it right). The nearest real lean is 3.4e-4 (Starter Rifle).
local TIE_LEAN = 1e-4

-- One step of the run's weapon upgrade: the gun, its Gold, and the word on the upgrade card.
export type TLadderStep = {
	Gun: number,
	Price: number,
	Label: string,
}

local GunsCore = {}

-- Scratch for LineUp: the bodies a line into the target can meet, one bearing's slope spans, the cuts between them,
-- the owners counted, the bearings, the lines worth a cast, and a cast's hits.
local wedge: TBodies = { Count = 0, X = {}, Z = {}, FloorY = {}, Radius = {}, Height = {} }
local wedgeOwners: { unknown } = {}
local spanLow: { number } = {}
local spanHigh: { number } = {}
local spanBody: { number } = {}
local spanSeen: { [unknown]: boolean } = {}
local cuts: { number } = {}
-- Each bearing's flat direction, and how far along it the target's middle is.
local bearingX: { number } = {}
local bearingZ: { number } = {}
local bearingAlong: { number } = {}
local candidateBearings: { number } = {}
local candidateSlopes: { number } = {}
local candidateHits: { number } = {}
local candidateFacings: { number } = {}
local lineIndices: { number } = {}
local lineDistances: { number } = {}

-- The Gold of each step of the run's weapon upgrades, one step per loadout tier. Every run starts on the first; each
-- buy moves one step on.
GunsCore.LADDER_PRICES = table.freeze({ 0, 150, 450, 1000 })

-- Step `index` of a ladder, holding `gun`.
function GunsCore.LadderStep(gun: TData.TGun, index: number): TLadderStep
	return table.freeze({ Gun = gun.Id, Price = GunsCore.LADDER_PRICES[index], Label = string.upper(gun.Name) })
end

-- A player's run ladder (the HUD's weapon card, WeaponService's upgrade): the gun each lobby loadout tier holds, in
-- tier order. `equipped` is the profile's Loadout.Equipped, where a tier never picked holds its starter.
-- Each step is a step up only while every gun kills faster than the cheaper guns of its tier and every gun of the
-- tiers below, measured rather than read off damage a second: run tools/lune/guns.luau after changing a gun.
function GunsCore.Ladder(equipped: { [string]: string }): { TLadderStep }
	local ladder = table.create(#GunsCore.LADDER_PRICES)
	for tier in GunsCore.LADDER_PRICES do
		ladder[tier] = GunsCore.LadderStep(LoadoutCore.EquippedOf(equipped, tier), tier)
	end

	return table.freeze(ladder)
end

-- The ladder of a loadout never touched: what the client shows until the server sends its own.
GunsCore.STARTER_LADDER = GunsCore.Ladder({})

GunsCore.Tune = table.freeze({
	-- The head's centre over the root on an R6 body: where the server shoots from, so where sight is tested from.
	EYE_HEIGHT = 1.5,
	-- What a blast does to everything in its radius but the body it hit, as a share of the pellet's damage.
	SPLASH_SHARE = 0.75,
	-- A shotgun's pellet count is the data's; past this a shot is refused as malformed data, not drawn.
	MAX_PELLETS = 24,
	-- The camera kick, degrees: from a gun's damage when it names none.
	KICK_BASE_DEG = 0.35,
	KICK_PER_DAMAGE_DEG = 0.03,
	KICK_MIN_DEG = 0.4,
	KICK_MAX_DEG = 3.5,
	-- Added to every gun's HitRadius when the server decides a hit: the client aims at bodies drawn a little behind
	-- where the server has them (one 10 Hz movement tick plus the trip), and there is no rewind yet.
	LAG_PAD = 0.75,
	-- Lining a shot up (LineUp): the bearings tried across the body aimed at, spread over this share of its width;
	-- studs kept inside its top and bottom; how many lines are cast for floors and walls; and how near the head a
	-- body is all round it, where any line goes into it.
	LINE_UP_BEARINGS = 5,
	LINE_UP_WIDTH = 0.7,
	LINE_UP_EDGE = 0.5,
	LINE_UP_CHECKS = 12,
	LINE_UP_NEAREST = 0.5,
})

local byName: { [string]: TData.TGun } = {}
for _, gun in DataCore.Guns.All do
	byName[gun.Name] = gun
end

-- The gun a Tool was built from: tools are named after their gun (buildGunTool).
function GunsCore.FromToolName(name: string): TData.TGun?
	return byName[name]
end

-- A model sits in the folder named for its gun's rarity: ReplicatedStorage.Models.Guns.<Rarity>.<ModelName>.
function GunsCore.GetModel(gun: TData.TGun): Model?
	local models = ReplicatedStorage:FindFirstChild("Models")
	local guns = if models then models:FindFirstChild("Guns") else nil
	local folder = if guns then guns:FindFirstChild(gun.Rarity) else nil
	local model = if folder then folder:FindFirstChild(gun.ModelName) else nil
	return if model and model:IsA("Model") then model else nil
end

-- A gun model's frame: X out of the barrel, Y up, at the model's centre. The models are the old Game place's as they
-- were (no handle, any orientation), so the barrel is found from the parts: the biggest part's long axis, pointing
-- away from where most of the volume sits (the stock). A gun this reads wrongly is fixed in its data (IsFlipped,
-- PitchDeg).
function GunsCore.FindAxes(model: Model, gun: TData.TGun): CFrame
	local parts = {}
	local biggest: BasePart? = nil
	local biggestVolume = 0
	for _, descendant in model:GetDescendants() do
		if not descendant:IsA("BasePart") then continue end
		parts[#parts + 1] = descendant
		local size = descendant.Size
		local volume = size.X * size.Y * size.Z
		if volume > biggestVolume or not biggest then
			biggest = descendant
			biggestVolume = volume
		end
	end

	local pivot = model:GetPivot()
	if not biggest then return pivot end

	local size = biggest.Size
	local side = Vector3.xAxis
	if size.Y > size.X and size.Y >= size.Z then
		side = Vector3.yAxis
	elseif size.Z > size.X and size.Z > size.Y then
		side = Vector3.zAxis
	end

	local axis = biggest.CFrame:VectorToWorldSpace(side)
	local center = model:GetBoundingBox().Position
	local total, weighted = 0, 0
	for _, part in parts do
		local volume = part.Size.X * part.Size.Y * part.Size.Z
		total += volume
		weighted += volume * (part.Position - center):Dot(axis)
	end

	-- The heavier end is the stock, so the barrel points the other way. A tie keeps the biggest part's own axis.
	local isStockAlongAxis = total > 0 and weighted / total > TIE_LEAN * size:Dot(side)
	local forward = if isStockAlongAxis then -axis else axis
	if gun.IsFlipped then forward = -forward end

	local up = pivot.UpVector
	if math.abs(up:Dot(forward)) > 0.9 then up = pivot.LookVector end
	up = (up - forward * up:Dot(forward)).Unit

	local frame = CFrame.fromMatrix(center, forward, up, forward:Cross(up))
	return if gun.PitchDeg then frame * CFrame.Angles(0, 0, math.rad(gun.PitchDeg)) else frame
end

-- Degrees the camera kicks for one shot of `gun`.
function GunsCore.KickDeg(gun: TData.TGun): number
	local tune = GunsCore.Tune
	return gun.RecoilDeg
		or math.clamp(tune.KICK_BASE_DEG + gun.Damage * tune.KICK_PER_DAMAGE_DEG, tune.KICK_MIN_DEG, tune.KICK_MAX_DEG)
end

-- The `count` pellets of the shot seeded `seed` into `out[1..count]`: `direction` turned a random way by up to
-- `spreadDeg`, thick in the middle of the cone and thin at its rim (the angle is drawn evenly, not the disc's area):
-- evenly over the disc, a shotgun put too few pellets on the body aimed at past 35 studs and killed slower than the
-- pistol (tools/lune/guns.luau). One generator a shot, drawn in pellet order, so the same seed gives the same pattern
-- on every machine.
function GunsCore.PelletDirections(direction: Vector3, seed: number, spreadDeg: number, count: number, out: { Vector3 })
	local unit = direction.Unit
	if spreadDeg <= 0 then
		for pellet = 1, count do
			out[pellet] = unit
		end
		return
	end

	local random = Random.new(seed)
	local maxCone = math.rad(spreadDeg)
	local side = if math.abs(unit.Y) < 0.99 then unit:Cross(Vector3.yAxis).Unit else unit:Cross(Vector3.xAxis).Unit
	for pellet = 1, count do
		local turn = random:NextNumber(0, math.pi * 2)
		local cone = maxCone * random:NextNumber()
		local axis = CFrame.fromAxisAngle(unit, turn):VectorToWorldSpace(side)
		out[pellet] = CFrame.fromAxisAngle(axis, cone):VectorToWorldSpace(unit)
	end
end

-- Distance along `unit` from `origin` to where the ray first is inside an upright cylinder (centre x/z, `radius`,
-- from `floorY` up `height`), or nil when it misses it: through its side, its top or its bottom, and 0 from inside
-- it. A ray from under a body aimed up at it, or from inside a long one, hits: only the side and the top, it went
-- into the air.
local function rayCylinder(
	origin: Vector3,
	unit: Vector3,
	centerX: number,
	centerZ: number,
	radius: number,
	floorY: number,
	height: number
): number?
	local fx = origin.X - centerX
	local fz = origin.Z - centerZ
	local dx, dy, dz = unit.X, unit.Y, unit.Z
	local topY = floorY + height
	local a = dx * dx + dz * dz
	local c = fx * fx + fz * fz - radius * radius

	-- The stretch of the ray within the radius, seen from above.
	local enter, leave = 0, math.huge
	if a > EPSILON then
		local b = 2 * (fx * dx + fz * dz)
		local discriminant = b * b - 4 * a * c
		if discriminant < 0 then return nil end
		local root = math.sqrt(discriminant)
		enter = (-b - root) / (2 * a)
		leave = (-b + root) / (2 * a)
	elseif c > 0 then
		return nil
	end

	-- And within its height.
	if math.abs(dy) > EPSILON then
		local toFloor = (floorY - origin.Y) / dy
		local toTop = (topY - origin.Y) / dy
		enter = math.max(enter, math.min(toFloor, toTop))
		leave = math.min(leave, math.max(toFloor, toTop))
	elseif origin.Y < floorY or origin.Y > topY then
		return nil
	end

	enter = math.max(enter, 0)
	return if enter <= leave then enter else nil
end

GunsCore.RayCylinder = rayCylinder

-- The bodies a shot can hit, gathered once a shot (each side from its own source) so every pellet tests plain arrays:
-- no ECS read and no call into another module per pellet per body.
export type TBodies = {
	Count: number,
	X: { number },
	Z: { number },
	FloorY: { number },
	Radius: { number },
	Height: { number },
}

function GunsCore.NewBodies(): TBodies
	return { Count = 0, X = {}, Z = {}, FloorY = {}, Radius = {}, Height = {} }
end

function GunsCore.AddBody(bodies: TBodies, feet: Vector3, radius: number, height: number)
	local index = bodies.Count + 1
	bodies.Count = index
	bodies.X[index] = feet.X
	bodies.Z[index] = feet.Z
	bodies.FloorY[index] = feet.Y
	bodies.Radius[index] = radius
	bodies.Height[index] = height
end

-- A long body's pieces (TEnemy.AimPieces) for a body standing at `feet` facing `forward` (flat unit), each as one
-- more body. Returns the index of the first; the caller maps every index from it to the body's entity.
function GunsCore.AddPieces(bodies: TBodies, feet: Vector3, forward: Vector3, pieces: { TData.TEnemyAimPiece }): number
	local first = bodies.Count + 1
	for _, piece in pieces do
		local index = bodies.Count + 1
		bodies.Count = index
		bodies.X[index] = feet.X + forward.X * piece.Ahead
		bodies.Z[index] = feet.Z + forward.Z * piece.Ahead
		bodies.FloorY[index] = feet.Y + piece.Bottom
		bodies.Radius[index] = piece.Radius
		bodies.Height[index] = piece.Height
	end

	return first
end

-- The nearest body the ray meets within `length` (each widened by `pad`) and further than `beyond`: its index and
-- distance, or 0 and `length`. `beyond` is -1 for the first body, then the last hit's distance for a bullet that
-- goes on through it (TGun.Pierce).
function GunsCore.CastBodies(
	bodies: TBodies,
	origin: Vector3,
	unit: Vector3,
	length: number,
	pad: number,
	beyond: number
): (number, number)
	local xs, zs, floors, radii, heights = bodies.X, bodies.Z, bodies.FloorY, bodies.Radius, bodies.Height
	local best, bestDistance = 0, length
	for index = 1, bodies.Count do
		local t = rayCylinder(origin, unit, xs[index], zs[index], radii[index] + pad, floors[index], heights[index])
		if t and t < bestDistance and t > beyond then
			best, bestDistance = index, t
		end
	end

	return best, bestDistance
end

-- Every body the ray meets within `length` (each widened by `pad`), nearest first, into `outIndices` / `outDistances`;
-- returns the count. The same bodies in the same order as CastBodies called again from each hit's distance, a body
-- exactly as far as the one before it passed over, in one walk of the bodies instead of one per body a bullet goes
-- through (performance/optimization-2026-11-26).
function GunsCore.CastBodiesAll(
	bodies: TBodies,
	origin: Vector3,
	unit: Vector3,
	length: number,
	pad: number,
	outIndices: { number },
	outDistances: { number }
): number
	local xs, zs, floors, radii, heights = bodies.X, bodies.Z, bodies.FloorY, bodies.Radius, bodies.Height
	local count = 0
	for index = 1, bodies.Count do
		local t = rayCylinder(origin, unit, xs[index], zs[index], radii[index] + pad, floors[index], heights[index])
		if not t or t >= length then continue end
		-- Insertion after any as far: of equal ones, the lowest index comes first, as CastBodies' strict `<` picks it.
		local at = count
		while at > 0 and outDistances[at] > t do
			outIndices[at + 1] = outIndices[at]
			outDistances[at + 1] = outDistances[at]
			at -= 1
		end
		outIndices[at + 1] = index
		outDistances[at + 1] = t
		count += 1
	end

	-- CastBodies' strict `> beyond` skips every body as far as the last hit.
	local kept = math.min(count, 1)
	for k = 2, count do
		if outDistances[k] == outDistances[kept] then continue end
		kept += 1
		outIndices[kept] = outIndices[k]
		outDistances[kept] = outDistances[k]
	end

	return kept
end

-- What LineUp works from, in one table the caller keeps and fills for each shot: the gathered bodies and the owner of
-- each (a long body's pieces share one), the head the shot leaves from, the point it was aimed at in body `Body`
-- (the crosshair's or the assist's), the gun's Pierce and Range, `Pad` widening the other bodies as the server does
-- (the gun's HitRadius plus LAG_PAD), and `CastWall`, sightCast's length along a ray.
export type TLineUpShot = {
	Bodies: TBodies,
	Owners: { unknown },
	Origin: Vector3,
	Target: Vector3,
	Body: number,
	Pierce: number,
	Range: number,
	Pad: number,
	CastWall: (Vector3, Vector3) -> number,
}

-- The bodies a bullet with `pierce` goes into along a ray, as WeaponService counts them (a long body's pieces in a row
-- are one body): how many, and whether the body `target` owns is one.
local function countLine(
	bodies: TBodies,
	owners: { unknown },
	origin: Vector3,
	unit: Vector3,
	length: number,
	pad: number,
	pierce: number,
	target: unknown
): (number, boolean)
	local hitCount = GunsCore.CastBodiesAll(bodies, origin, unit, length, pad, lineIndices, lineDistances)
	local count, hasTarget, piercesLeft = 0, false, pierce
	local lastOwner = nil
	for hit = 1, hitCount do
		local owner = owners[lineIndices[hit]]
		if owner == lastOwner then continue end
		lastOwner = owner
		count += 1
		if owner == target then hasTarget = true end
		if piercesLeft == 0 then break end
		piercesLeft -= 1
	end

	return count, hasTarget
end

-- How many owners' slope spans hold `slope` (each owner once), up to `cap`.
local function countSpans(owners: { unknown }, spanCount: number, slope: number, cap: number): number
	local count = 0
	for span = 1, spanCount do
		if slope <= spanLow[span] or slope >= spanHigh[span] then continue end
		local owner = owners[spanBody[span]]
		if spanSeen[owner] then continue end
		spanSeen[owner] = true
		count += 1
		if count >= cap then break end
	end

	table.clear(spanSeen)
	return count
end

-- Puts body `index` of `bodies` into the wedge as its body `at`.
local function copyToWedge(bodies: TBodies, owners: { unknown }, index: number, at: number)
	wedge.X[at], wedge.Z[at], wedge.FloorY[at] = bodies.X[index], bodies.Z[index], bodies.FloorY[index]
	wedge.Radius[at], wedge.Height[at] = bodies.Radius[index], bodies.Height[index]
	wedgeOwners[at] = owners[index]
end

-- Every line LineUp tries goes into the target, so it stays within the target's half width of its bearing (seen from
-- above): only the bodies in that wedge can be on one. Gathered once into `wedge`, the target first. Returns the
-- tangent of that half width.
local function gatherWedge(shot: TLineUpShot, flatDistance: number): number
	local bodies, owners, body = shot.Bodies, shot.Owners, shot.Body
	local xs, zs, radii = bodies.X, bodies.Z, bodies.Radius
	local originX, originZ = shot.Origin.X, shot.Origin.Z
	local pad, nearest = shot.Pad, GunsCore.Tune.LINE_UP_NEAREST
	local centerX, centerZ = (xs[body] - originX) / flatDistance, (zs[body] - originZ) / flatDistance
	local across = math.sqrt(flatDistance * flatDistance - radii[body] * radii[body])
	local spread = radii[body] / across
	-- A line turned the whole half width off the bearing meets a body this much wider than its radius, across it.
	local widen = flatDistance / across

	copyToWedge(bodies, owners, body, 1)
	local count = 1
	for index = 1, bodies.Count do
		if index == body then continue end
		local offsetX, offsetZ = xs[index] - originX, zs[index] - originZ
		local along = offsetX * centerX + offsetZ * centerZ
		local radius = radii[index] + pad
		if along + radius <= nearest then continue end
		local beside = math.abs(offsetX * centerZ - offsetZ * centerX)
		if beside > radius * widen + math.max(along, 0) * spread then continue end
		count += 1
		copyToWedge(bodies, owners, index, count)
	end
	wedge.Count = count

	return spread
end

-- The lines through the target on bearing `step` worth a cast: their slopes, each in the middle of a stretch of slopes
-- the same bodies' spans hold, if more than `aimedCount` of them. Returns how far along the bearing the target's
-- middle is (nil when the bearing misses it) and the new candidate count.
local function addCandidates(
	shot: TLineUpShot,
	step: number,
	aimedCount: number,
	candidateCount: number
): (number?, number)
	local tune = GunsCore.Tune
	local dirX, dirZ = bearingX[step], bearingZ[step]
	local xs, zs, floors, radii, heights = wedge.X, wedge.Z, wedge.FloorY, wedge.Radius, wedge.Height
	local origin = shot.Origin
	local originX, originY, originZ = origin.X, origin.Y, origin.Z
	local pad, range, nearest = shot.Pad, shot.Range, tune.LINE_UP_NEAREST
	local cap = shot.Pierce + 1
	-- Kept inside the target's top and bottom, at most a quarter of its height each.
	local edge = math.min(tune.LINE_UP_EDGE, heights[1] * 0.25)

	-- A body's span: the slopes of the lines from the head on this bearing that go into it, from the bottom of its near
	-- side or far side to the top of the other.
	local spanCount = 0
	local low, high, targetAlong = 0, 0, nil
	for index = 1, wedge.Count do
		local offsetX, offsetZ = xs[index] - originX, zs[index] - originZ
		local along = offsetX * dirX + offsetZ * dirZ
		local isTarget = index == 1
		local radius = if isTarget then radii[index] else radii[index] + pad
		local besideSq = offsetX * offsetX + offsetZ * offsetZ - along * along
		if besideSq >= radius * radius then continue end
		local half = math.sqrt(radius * radius - besideSq)
		local far = math.min(along + half, range)
		if far <= nearest then continue end
		local near = math.max(along - half, nearest)
		local bottom = floors[index] - originY + (if isTarget then edge else 0)
		local top = floors[index] + heights[index] - originY - (if isTarget then edge else 0)
		spanCount += 1
		spanLow[spanCount] = math.min(bottom / near, bottom / far)
		spanHigh[spanCount] = math.max(top / near, top / far)
		spanBody[spanCount] = index
		if isTarget then
			low, high, targetAlong = spanLow[spanCount], spanHigh[spanCount], along
		end
	end
	if not targetAlong or low >= high then return nil, candidateCount end

	-- Every span's ends inside the target's: between two, the count is the same all the way.
	local cutCount = 2
	cuts[1], cuts[2] = low, high
	for span = 1, spanCount do
		local spanStart, spanEnd = spanLow[span], spanHigh[span]
		if spanStart > low and spanStart < high then
			cutCount += 1
			cuts[cutCount] = spanStart
		end
		if spanEnd > low and spanEnd < high then
			cutCount += 1
			cuts[cutCount] = spanEnd
		end
	end
	table.sort(cuts)

	for cut = 1, cutCount - 1 do
		local from, to = cuts[cut], cuts[cut + 1]
		if to - from < EPSILON then continue end
		local slope = (from + to) * 0.5
		local count = countSpans(wedgeOwners, spanCount, slope, cap)
		if count <= aimedCount then continue end
		candidateCount += 1
		candidateBearings[candidateCount] = step
		candidateSlopes[candidateCount] = slope
		candidateHits[candidateCount] = count
	end
	table.clear(cuts)

	return targetAlong, candidateCount
end

-- Where to send `shot` so it goes into as many bodies as its pierce allows: still into its body, by that body's
-- middle part (LINE_UP_WIDTH, LINE_UP_EDGE), and never into fewer than through its Target. A shot is a line from the
-- head and the view is not: from a camera above and behind the head, the line through the point the crosshair is on
-- climbs over the bodies behind, or digs into the floor before them, with every step of a slope or floor between
-- them. A gun that does not pierce gains too where the head's line to that point is blocked (a ledge or a slope the
-- camera sees over).
--
-- Seen from above, the line runs on one of a few bearings across the body. On each, a body is a span of slopes the
-- line can take and still go into it (exact for an upright cylinder: its cut by the line's upright plane is a
-- rectangle), so the slopes holding the most spans are found without a cast; the best few are then cast for floors
-- and walls in the way (tools/lune/aim.luau measures it).
function GunsCore.LineUp(shot: TLineUpShot): Vector3
	local tune = GunsCore.Tune
	local bodies, body, origin, target = shot.Bodies, shot.Body, shot.Origin, shot.Target
	local toX, toZ = bodies.X[body] - origin.X, bodies.Z[body] - origin.Z
	local flatDistance = math.sqrt(toX * toX + toZ * toZ)
	if flatDistance <= bodies.Radius[body] + tune.LINE_UP_NEAREST then return target end

	local spread = gatherWedge(shot, flatDistance)
	local targetOwner = wedgeOwners[1]
	local pierce, range, pad, castWall = shot.Pierce, shot.Range, shot.Pad, shot.CastWall
	local aimed = (target - origin).Unit
	local aimedLength = castWall(origin, aimed * range)
	local aimedCount = countLine(wedge, wedgeOwners, origin, aimed, aimedLength, pad, pierce, targetOwner)

	local candidateCount = 0
	if aimedCount <= pierce then
		local bearing = math.atan2(toZ, toX)
		local halfWidth = math.atan(spread) * tune.LINE_UP_WIDTH
		local bearings = tune.LINE_UP_BEARINGS
		for step = 1, bearings do
			local angle = bearing + halfWidth * ((step - 1) / (bearings - 1) * 2 - 1)
			bearingX[step], bearingZ[step] = math.cos(angle), math.sin(angle)
			local along
			along, candidateCount = addCandidates(shot, step, aimedCount, candidateCount)
			bearingAlong[step] = along or 0
		end
	end

	-- How near each is to where the player aimed: the tie-break between lines into as many bodies.
	for candidate = 1, candidateCount do
		local step, slope = candidateBearings[candidate], candidateSlopes[candidate]
		local facing = bearingX[step] * aimed.X + slope * aimed.Y + bearingZ[step] * aimed.Z
		candidateFacings[candidate] = facing / math.sqrt(1 + slope * slope)
	end

	-- The best few by count, then facing, cast for what is in their way.
	local best, bestCount = target, aimedCount
	for _ = 1, tune.LINE_UP_CHECKS do
		local pick, pickCount, pickFacing = 0, bestCount + 1, -math.huge
		for candidate = 1, candidateCount do
			local count, facing = candidateHits[candidate], candidateFacings[candidate]
			if count < pickCount or (count == pickCount and facing <= pickFacing) then continue end
			pick, pickCount, pickFacing = candidate, count, facing
		end
		if pick == 0 then break end

		candidateHits[pick] = 0
		local step = candidateBearings[pick]
		local through = Vector3.new(bearingX[step], candidateSlopes[pick], bearingZ[step])
		local unit = through.Unit
		local length = castWall(origin, unit * range)
		local count, hasTarget = countLine(wedge, wedgeOwners, origin, unit, length, pad, pierce, targetOwner)
		if hasTarget and count > bestCount then
			best, bestCount = origin + through * bearingAlong[step], count
		end
	end

	wedge.Count = 0
	table.clear(wedgeOwners)
	return best
end

return table.freeze(GunsCore)
