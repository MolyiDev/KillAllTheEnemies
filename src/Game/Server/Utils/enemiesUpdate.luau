--!native
--!optimize 2
-- One fixed step of every enemy, on the main thread. Called by EnemyMovementService at TimeCore.FIXED_DT.
--
-- SERIAL ON PURPOSE: at 255 enemies a parallel pipeline (Actors, snapshots, a decoder per worker) costs more in
-- serialisation than the math it carries (performance/audit-2026-10-21/REPORT.md), so this reads the live spatial
-- hash, ECS and flowfields directly and writes straight back.
--
-- Everything that reaches outside EnemyWorld's columns is deferred to after the loop. Writes inside the loop are
-- column stores on components the entity already has, which jecs allows mid-query.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local NavService = require(ServerScriptService.Server.Services.NavService)
local ArenaCore = require(ReplicatedStorage.Shared.Core.ArenaCore)
local EnemiesCore = require(ReplicatedStorage.Shared.Core.EnemiesCore)
local TelegraphCore = require(ReplicatedStorage.Shared.Core.TelegraphCore)
local Components = require(ReplicatedStorage.GlobalShared.ECS.Components)
local EnemyWorld = require(ReplicatedStorage.GlobalShared.ECS.Worlds.EnemyWorld)
local SpatialHash = require(ReplicatedStorage.GlobalShared.Utils.SpatialHash)
local TData = require(ReplicatedStorage.Types.TData)

local clamp = math.clamp
local abs = math.abs
local sqrt = math.sqrt
local max = math.max
local min = math.min
local floor = math.floor
local atan2 = math.atan2
local vectorCreate = vector.create
local readu8 = buffer.readu8
local readu32 = buffer.readu32
local readi32 = buffer.readi32
local readf32 = buffer.readf32

local EnemiesSpatialHash = EnemiesCore.EnemiesSpatialHash
local HashRecords = EnemiesSpatialHash.Records

local K_FORCE = 100
local SPEED_CAP = 50
local VEL_ALPHA = 0.165
local MAX_FALL_SPEED = -75
local GRAVITY = Workspace.Gravity
-- A body pressed against a player stops at this radius around him. Melee reach is measured from it (sweepSwing).
local PLAYER_COLLISION_RADIUS = 2
local WALL_RADIUS_SCALE = 0.5
-- A neighbour floor this much lower is a ledge (walls below). Under the shortest stair riser, 0.6.
local LEDGE_DROP = 0.5
-- Bodies that fall this far under the lowest floor are gone (thrown off the map).
local FALL_OUT_DEPTH = 40

-- Separation steering (Fieldrunners-style): a soft push from neighbours in a ring past hard contact,
-- plus a sidestep from the ones ahead, so a column slides apart instead of stacking. Budgeted to a fraction of the
-- walk so it shapes the crowd without overpowering the chase.
local SEP_RANGE = 1.6
local SEP_STRENGTH = 0.5
local SEP_MAX_FRAC = 0.8
local SEP_PERP_FRAC = 0.5
-- Air kept between two bodies' edges before they push: room to see a ground warning between them.
local CROWD_GAP = 1

-- Targeting. Path cost is inflated by how many enemies already claimed a player this tick (the tally fills as the
-- loop hands targets out), which spreads a crowd across a party. Point-blank on the same level is self-defense: it
-- ignores the tally and steers straight.
local POINT_BLANK = 8
local POINT_BLANK_SQ = POINT_BLANK * POINT_BLANK
local AGGRO_SPREAD = 0.15
-- A lure's path cost is cut to this share, so a body in its reach goes for it ahead of any player in sight.
local LURE_PULL = 0.05
local SAME_LEVEL = ArenaCore.MAX_STEP + 1

local SWING_UNDERREACH = 2
local NO_NODE = ArenaCore.NO_NODE
local NAV_INF = NavService.INF
local MAX_STEP = ArenaCore.MAX_STEP
local CLEARANCE = ArenaCore.CLEARANCE
local DIR_DX = ArenaCore.DX
local DIR_DZ = ArenaCore.DZ
local COST_TO_STUDS = ArenaCore.CELL_SIZE / ArenaCore.COST_ORTHOGONAL
local INV_SQRT2 = 1 / sqrt(2)

export type TTick = {
	Dt: number,
	-- Living characters' feet, keyed by character id. A lure's feet are in here too, under its own id.
	CharacterFeet: { [number]: vector },
	-- Which of those are lures (EnemyMovementService.SetLure), by the square of how far each draws bodies from.
	Lures: { [number]: number },
	-- Barricades, parallel arrays: id, centre (feet level), half-size (x, height, z).
	BarricadeIds: { number },
	BarricadeCenters: { vector },
	BarricadeHalves: { vector },
	BarricadeCount: number,
	-- Ground warnings still winding up (EnemyAttacksService.GetWarnings). Read only.
	Warnings: { TelegraphCore.TWarning },
	-- Out: what moved, for the position stream.
	OutIds: { number },
	OutPositions: { vector },
	OutYaws: { number },
	-- Deferred effects. A target id > 0 is a character, < 0 is -barricadeId.
	OnAttackStarted: (
		enemy: any,
		attackIndex: number,
		attack: TData.TEnemyAttack,
		center: vector,
		targetId: number
	) -> (),
	OnSwingLanded: (enemy: any, targetId: number, damageScale: number) -> (),
	OnFellOut: (enemy: any) -> (),
}

-- Nav, bound once per tick.
local nav: ArenaCore.TNavGrid? = nil
local navLinks = buffer.create(1)
local navHeights = buffer.create(1)
local navCellFirst = buffer.create(1)
local navCellLayers = buffer.create(1)
local navBlocked = buffer.create(1)
local navWidth, navDepth = 0, 0
local navOriginX, navOriginZ, navCell, navHalfCell = 0, 0, 1, 0.5

-- Neighbour-collision callback state. Module-level so the callback is one function, not a closure per enemy.
local cbEntity: any = nil
local cbPos = vector.zero
local cbRadius = 0
local cbKForce = 0
local cbWalkDirX, cbWalkDirZ = 0, 0
local cbWalkVelX, cbWalkVelZ = 0, 0
local cbSepX, cbSepZ = 0, 0
local cbStandOn = 0

-- Deferred effects, parallel arrays reused across ticks.
local startEntity: { any } = {}
local startIndex: { number } = {}
local startAttack: { TData.TEnemyAttack } = {}
local startCenter: { vector } = {}
local startTarget: { number } = {}
-- The warnings started this tick, which the ones after them must keep off too.
local startWarnings: { TelegraphCore.TWarning } = {}
local startCount = 0
local startWarningCount = 0
local landedEntity: { any } = {}
local landedTarget: { number } = {}
local landedScale: { number } = {}
local landedCount = 0
local fellEntity: { any } = {}
local fellCount = 0

-- Characters and barricades in a body's swing at `at` facing (dirX, dirZ). Fills swingHits, returns the count.
local swingHits: { number } = {}

local function enemyCollisionCallback(neighbor: any)
	if neighbor == cbEntity then return end
	local info = HashRecords[neighbor] :: SpatialHash.RecordAABB
	if not info then return end
	if info.y > cbPos.y + cbRadius * 2 then return end
	local dx = cbPos.x - info.x
	local dz = cbPos.z - info.z
	local dist2 = dx * dx + dz * dz
	local minDist = cbRadius + max(info.halfx, info.halfz) + CROWD_GAP
	if dist2 >= minDist * minDist then
		local sepReach = minDist * SEP_RANGE
		if dist2 >= sepReach * sepReach or dist2 <= 1e-6 then return end
		local sdist = sqrt(dist2)
		local nx = dx / sdist
		local nz = dz / sdist
		local strength = (sepReach - sdist) / (sepReach - minDist)
		cbSepX += nx * strength
		cbSepZ += nz * strength
		local ahead = -(nx * cbWalkDirX + nz * cbWalkDirZ)
		if ahead > 0 then
			local cross = cbWalkDirZ * nx - cbWalkDirX * nz
			local sign = if cross >= 0 then 1 else -1
			local perp = strength * ahead * SEP_PERP_FRAC
			cbSepX += -cbWalkDirZ * sign * perp
			cbSepZ += cbWalkDirX * sign * perp
		end
		return
	end

	local dist = sqrt(dist2)
	if dist <= 0 then return end
	local top = info.y + info.halfy * 2
	if cbPos.y >= top - 0.5 then
		if top > cbStandOn then cbStandOn = top end
		return
	end

	local scale = cbKForce * (minDist - dist) / dist
	cbWalkVelX += scale * dx
	cbWalkVelZ += scale * dz
end

-- Circle (cx, cz, r) against the square at (wx, wz) with half-size h: outward normal and penetration, 0 when apart.
local function resolveCircleSquare(cx: number, cz: number, r: number, wx: number, wz: number, h: number)
	local dx = cx - wx
	local dz = cz - wz
	local qx = clamp(dx, -h, h)
	local qz = clamp(dz, -h, h)
	local vx = dx - qx
	local vz = dz - qz
	local d2 = vx * vx + vz * vz
	if d2 > 0 then
		local dist = sqrt(d2)
		if dist >= r then return 0, 0, 0 end
		return vx / dist, vz / dist, r - dist
	end

	local px = h - abs(dx)
	local pz = h - abs(dz)
	if px < pz then return if dx >= 0 then 1 else -1, 0, r + px end
	return 0, if dz >= 0 then 1 else -1, r + pz
end

-- The floor node under a body: the highest floor of its cell it can step onto. A floor too high to step onto below
-- head height is in the way (ArenaCore.StepTarget), so nothing under it counts.
local function floorNode(x: number, feetY: number, z: number): number
	local cx = floor((x - navOriginX) / navCell + 0.5)
	local cz = floor((z - navOriginZ) / navCell + 0.5)
	if cx < 0 or cx >= navWidth or cz < 0 or cz >= navDepth then return NO_NODE end
	local cell = cz * navWidth + cx
	local first = readu32(navCellFirst, cell * 4)
	local maxY = feetY + MAX_STEP
	local headY = feetY + CLEARANCE

	for i = 0, readu8(navCellLayers, cell) - 1 do
		local h = readf32(navHeights, (first + i) * 4)
		if h <= maxY then return first + i end
		if h < headY then return NO_NODE end
	end

	return NO_NODE
end

-- The field's downhill direction at `node`: every lower neighbour pulls, weighted by how much lower per stud. A
-- weighted sum rather than the single best neighbour, so the walk rotates smoothly between cells instead of
-- snapping to the eight grid directions, which funnels a crowd into lanes.
local function fieldDirection(dist: buffer, node: number): (number, number, number)
	local here = readu32(dist, node * 4)
	if here == NAV_INF then return 0, 0, here end

	local sumX, sumZ = 0, 0
	for d = 1, 8 do
		local neighbor = readi32(navLinks, node * 32 + (d - 1) * 4)
		if neighbor == NO_NODE or readu8(navBlocked, neighbor) ~= 0 then continue end
		local there = readu32(dist, neighbor * 4)
		if there >= here then continue end
		local drop = here - there
		if d > 4 then
			drop *= INV_SQRT2
			sumX += DIR_DX[d] * INV_SQRT2 * drop
			sumZ += DIR_DZ[d] * INV_SQRT2 * drop
		else
			sumX += DIR_DX[d] * drop
			sumZ += DIR_DZ[d] * drop
		end
	end

	local len = sqrt(sumX * sumX + sumZ * sumZ)
	if len < 1e-6 then return 0, 0, here end
	return sumX / len, sumZ / len, here
end

local function sweepSwing(
	tick: TTick,
	at: vector,
	dirX: number,
	dirZ: number,
	halfExtents: vector,
	reach: number
): number
	local count = 0
	-- Reach is measured to the player's SURFACE: contact holds a body exactly halfExtents.z + PLAYER_COLLISION_RADIUS
	-- from him, so a reach from his centre put every swing on the edge of whiffing.
	local frontReach = halfExtents.z + PLAYER_COLLISION_RADIUS + reach
	local sideReach = halfExtents.x + PLAYER_COLLISION_RADIUS + reach
	local topReach = halfExtents.y * 2 + reach

	for id, feet in tick.CharacterFeet do
		local dx = feet.x - at.x
		local dz = feet.z - at.z
		local fwd = dx * dirX + dz * dirZ
		local side = dz * dirX - dx * dirZ
		if abs(fwd) > frontReach or abs(side) > sideReach then continue end
		local dy = feet.y - at.y
		if dy < -SWING_UNDERREACH or dy > topReach then continue end
		count += 1
		swingHits[count] = id
	end

	-- Barricades are boxes on a spot: their whole face is reachable by the row stood along it.
	local bodyReach = max(halfExtents.x, halfExtents.z) + reach
	for i = 1, tick.BarricadeCount do
		local center = tick.BarricadeCenters[i]
		local half = tick.BarricadeHalves[i]
		if abs(center.x - at.x) > half.x + bodyReach or abs(center.z - at.z) > half.z + bodyReach then continue end
		local dy = center.y - at.y
		if dy < -half.y * 2 - SWING_UNDERREACH or dy > topReach then continue end
		count += 1
		swingHits[count] = -tick.BarricadeIds[i]
	end

	return count
end

-- Whether a warning started here would land on one of its own class still winding up (TelegraphCore.IsOnTopOf). Two
-- on one spot read as one, so the second waits until its target steps out of the first. A boss's and an ordinary
-- enemy's are told apart by colour, so neither keeps the other off.
local function isAreaTaken(
	tick: TTick,
	isBoss: boolean,
	kind: number,
	center: vector,
	yaw: number,
	size: number,
	width: number,
	aim: vector
): boolean
	for _, warning in tick.Warnings do
		if warning.IsBoss ~= isBoss then continue end
		if TelegraphCore.IsOnTopOf(kind, center, yaw, size, width, aim, warning) then return true end
	end

	for i = 1, startWarningCount do
		local warning = startWarnings[i]
		if warning.IsBoss ~= isBoss then continue end
		if TelegraphCore.IsOnTopOf(kind, center, yaw, size, width, aim, warning) then return true end
	end

	return false
end

-- Keeps a warning started this tick for the ones after it to keep off.
local function addStartWarning(isBoss: boolean, kind: number, center: vector, yaw: number, size: number, width: number)
	startWarningCount += 1
	local warning = startWarnings[startWarningCount]
	if not warning then
		warning = { IsBoss = isBoss, Kind = kind, Center = center, Yaw = yaw, Size = size, Width = width }
		startWarnings[startWarningCount] = warning
		return
	end

	warning.IsBoss = isBoss
	warning.Kind = kind
	warning.Center = center
	warning.Yaw = yaw
	warning.Size = size
	warning.Width = width
end

local function bindNav()
	nav = ArenaCore.Nav
	local grid = nav
	if not grid then return end

	navLinks = grid.NodeLinks
	navHeights = grid.NodeHeight
	navCellFirst = grid.CellFirstNode
	navCellLayers = grid.CellLayerCount
	navBlocked = NavService.Blocked
	navWidth = grid.Width
	navDepth = grid.Depth
	navOriginX = grid.OriginX
	navOriginZ = grid.OriginZ
	navCell = grid.CellSize
	navHalfCell = grid.CellSize * 0.5
end

-- Moves every enemy in `query` one step. Returns how many it wrote to tick.Out*.
return function(query: any, tick: TTick, aggroCounts: { [number]: number }): number
	debug.profilebegin("EnemiesUpdate")
	startCount = 0
	startWarningCount = 0
	landedCount = 0
	fellCount = 0
	bindNav()
	local grid = nav
	local characterFields = NavService.CharacterFields
	local barricadeField = NavService.BarricadeField
	local hasBarricadeField = barricadeField ~= nil and barricadeField.IsReady
	local charFeet = tick.CharacterFeet
	local lures = tick.Lures
	local barricadeCount = tick.BarricadeCount
	local barricadeCenters = tick.BarricadeCenters
	local dt = tick.Dt
	local gravityStep = GRAVITY * dt
	local kForce = K_FORCE * dt
	local fallOutY = (if grid then grid.MinY else ArenaCore.FlatY) - FALL_OUT_DEPTH
	local outIds, outPositions, outYaws = tick.OutIds, tick.OutPositions, tick.OutYaws
	local written = 0
	local hasTargets = next(charFeet) ~= nil or barricadeCount > 0

	for
		entity,
		pos,
		velocity,
		force,
		radius,
		halfExtents,
		mass,
		attackWindup,
		attackCount,
		speed,
		yaw,
		instanceId,
		enemyData
	in query do
		local data = enemyData :: TData.TEnemy
		local node = if grid then floorNode(pos.x, pos.y, pos.z) else NO_NODE

		-- 1. Target. Path cost where the field can answer, flat distance where it cannot.
		local targetId = 0
		local targetX, targetY, targetZ = pos.x, pos.y, pos.z
		local bestScore = math.huge
		local fallbackId = 0
		local fallbackSq = math.huge
		local fbX, fbY, fbZ = 0, 0, 0
		for id, feet in charFeet do
			local dx, dz = feet.x - pos.x, feet.z - pos.z
			local flatSq = dx * dx + dz * dz
			-- A lure is nothing to a body out of its reach.
			local lureSq = lures[id]
			if lureSq and flatSq > lureSq then continue end
			if flatSq < fallbackSq then
				fallbackSq = flatSq
				fallbackId = id
				fbX, fbY, fbZ = feet.x, feet.y, feet.z
			end

			local cost: number
			if flatSq <= POINT_BLANK_SQ and abs(feet.y - pos.y) <= SAME_LEVEL then
				cost = sqrt(flatSq)
			else
				local field = characterFields[id]
				if field and field.IsReady and node ~= NO_NODE then
					local d = readu32(field.Dist, node * 4)
					if d == NAV_INF then continue end
					cost = d * COST_TO_STUDS
				else
					cost = sqrt(flatSq)
				end
			end

			local score = if lureSq then cost * LURE_PULL else cost * (1 + AGGRO_SPREAD * (aggroCounts[id] or 0))
			if score < bestScore then
				bestScore = score
				targetId = id
				targetX, targetY, targetZ = feet.x, feet.y, feet.z
			end
		end

		if barricadeCount > 0 then
			-- The field says how far the nearest barricade is by path; the nearest by line is the one to face.
			local nearestI, nearestSq = 0, math.huge
			for i = 1, barricadeCount do
				local center = barricadeCenters[i]
				local dx, dz = center.x - pos.x, center.z - pos.z
				local sq = dx * dx + dz * dz
				if sq < nearestSq then
					nearestSq = sq
					nearestI = i
				end
			end

			local cost = sqrt(nearestSq)
			if hasBarricadeField and node ~= NO_NODE then
				local d = readu32((barricadeField :: NavService.TNavField).Dist, node * 4)
				cost = if d == NAV_INF then math.huge else d * COST_TO_STUDS
			end

			if cost < bestScore then
				bestScore = cost
				targetId = -tick.BarricadeIds[nearestI]
				local center = barricadeCenters[nearestI]
				targetX, targetY, targetZ = center.x, center.y, center.z
			end
		end

		-- Nothing reachable: walk at the nearest player in a straight line and press against whatever is between.
		if targetId == 0 and fallbackId ~= 0 then
			targetId = fallbackId
			targetX, targetY, targetZ = fbX, fbY, fbZ
		end

		if targetId > 0 then aggroCounts[targetId] = (aggroCounts[targetId] or 0) + 1 end

		-- 2. Steer.
		local toX, toZ = targetX - pos.x, targetZ - pos.z
		local toLen = sqrt(toX * toX + toZ * toZ)
		local walkDirX, walkDirZ
		if toLen > 1e-6 then
			walkDirX, walkDirZ = toX / toLen, toZ / toLen
		else
			walkDirX, walkDirZ = math.sin(yaw), math.cos(yaw)
		end

		local isPointBlank = toLen <= POINT_BLANK and abs(targetY - pos.y) <= SAME_LEVEL
		-- The route's field and this node's cost on it, kept for the walls below even when walking straight.
		local routeDist: buffer? = nil
		local routeHere = NAV_INF
		if grid and node ~= NO_NODE and targetId ~= 0 then
			local field = if targetId > 0 then characterFields[targetId] else barricadeField
			local dist = if field and field.IsReady then field.Dist else nil
			local here = if dist then readu32(dist, node * 4) else NAV_INF
			if dist and here ~= NAV_INF then
				routeDist = dist
				routeHere = here
				if not isPointBlank then
					local fx, fz = fieldDirection(dist, node)
					if fx ~= 0 or fz ~= 0 then
						walkDirX, walkDirZ = fx, fz
					end
				end
			end
		end

		local isWindingUp = attackWindup > 0
		local windingUp = if isWindingUp
			then data.Attacks[EnemyWorld:get(entity, Components.AttackIndex) :: number]
			else nil
		-- A ground warning stays where it was shown, so a body winding one up holds still on it: no momentum, crowd,
		-- wall or shove moves it, and it keeps the facing it aimed with.
		local isHeld = windingUp ~= nil and windingUp.Kind ~= "Melee"
		local walkSpeed = if hasTargets and not isWindingUp then speed else 0
		local walkVelX = walkDirX * walkSpeed
		local walkVelZ = walkDirZ * walkSpeed

		-- 3. Collide: other enemies, in one hash query that feeds both contact and separation.
		cbEntity = entity
		cbPos = pos
		cbRadius = radius
		cbKForce = kForce
		cbWalkDirX, cbWalkDirZ = walkDirX, walkDirZ
		cbWalkVelX, cbWalkVelZ = walkVelX, walkVelZ
		cbSepX, cbSepZ = 0, 0
		cbStandOn = -math.huge
		-- Short of the separation ring's outer edge, where its push is weakest: reaching all of it cost 10% of the update
		-- and moved the crowd's spacing by nothing measurable (tools/lune/sim.luau, 2026-10-24).
		EnemiesSpatialHash:QueryRadius(pos.x, pos.z, (radius + CROWD_GAP) * SEP_RANGE, enemyCollisionCallback)
		walkVelX, walkVelZ = cbWalkVelX, cbWalkVelZ
		local sepMag2 = cbSepX * cbSepX + cbSepZ * cbSepZ
		if sepMag2 > 1e-8 then
			local sepMag = sqrt(sepMag2)
			local s = min(sepMag * SEP_STRENGTH, speed * SEP_MAX_FRAC) / sepMag
			walkVelX += cbSepX * s
			walkVelZ += cbSepZ * s
		end

		-- Smooth against last tick's velocity along the walk, before external forces, so a knockback is not damped
		-- against the chase; persisted forward momentum is capped to the body's own speed when no force acts.
		local hasForce = force.x ~= 0 or force.y ~= 0 or force.z ~= 0
		local forward = max(0, velocity.x * walkDirX + velocity.z * walkDirZ)
		if not hasForce then forward = min(forward, speed) end
		walkVelX = walkDirX * forward * (1 - VEL_ALPHA) + walkVelX * VEL_ALPHA
		walkVelZ = walkDirZ * forward * (1 - VEL_ALPHA) + walkVelZ * VEL_ALPHA
		local preCap = speed * 1.5
		local preMag = sqrt(walkVelX * walkVelX + walkVelZ * walkVelZ)
		if preMag > preCap then
			walkVelX *= preCap / preMag
			walkVelZ *= preCap / preMag
		end

		local invMass = if mass > 0 then 1 / mass else 1
		if hasForce then
			walkVelX += force.x * invMass
			walkVelZ += force.z * invMass
		end

		-- Players' bodies: stack against them instead of walking inside.
		local pMin = halfExtents.z + PLAYER_COLLISION_RADIUS
		for _, feet in charFeet do
			local pdx = pos.x - feet.x
			local pdz = pos.z - feet.z
			local pdist2 = pdx * pdx + pdz * pdz
			if pdist2 >= pMin * pMin or pdist2 <= 1e-6 then continue end
			if abs(feet.y - pos.y) > SAME_LEVEL then continue end
			local pdist = sqrt(pdist2)
			local pen = pMin - pdist
			local pScale = kForce * pen * pen / pdist
			walkVelX += pScale * pdx
			walkVelZ += pScale * pdz
		end

		-- Walls: a neighbour cell this floor has no open link into (a cliff, a post, a ledge too high to drop, a
		-- barricade) is a square to slide along. The into-wall part of the velocity is projected out.
		-- A ledge the route does not drop off is one too, unless a force is shoving the body: an open-sided stair
		-- otherwise sheds its climbers into the pit beside it, pushed off by the crowd or walking straight off its side
		-- at a player on the rim, and they climb and fall in a loop.
		if grid and node ~= NO_NODE then
			local wallRadius = radius * WALL_RADIUS_SCALE
			local cell = readu32(grid.NodeCell, node * 4)
			local cellX = cell % navWidth
			local cellZ = cell // navWidth
			local ledgeY = readf32(navHeights, node * 4) - LEDGE_DROP
			local holdsLedges = routeDist ~= nil and not hasForce
			for d = 1, 8 do
				local link = readi32(navLinks, node * 32 + (d - 1) * 4)
				if link ~= NO_NODE and readu8(navBlocked, link) == 0 then
					if not holdsLedges or readf32(navHeights, link * 4) >= ledgeY then continue end
					if readu32(routeDist :: buffer, link * 4) < routeHere then continue end
				end
				local wx = navOriginX + (cellX + DIR_DX[d]) * navCell
				local wz = navOriginZ + (cellZ + DIR_DZ[d]) * navCell
				local wnx, wnz, pen = resolveCircleSquare(pos.x, pos.z, wallRadius, wx, wz, navHalfCell)
				if pen <= 0 then continue end
				local into = walkVelX * wnx + walkVelZ * wnz
				if into < 0 then
					walkVelX -= into * wnx
					walkVelZ -= into * wnz
				end

				walkVelX += kForce * wnx * pen * 0.5
				walkVelZ += kForce * wnz * pen * 0.5
			end
		end

		local mag = sqrt(walkVelX * walkVelX + walkVelZ * walkVelZ)
		if mag > SPEED_CAP then
			walkVelX *= SPEED_CAP / mag
			walkVelZ *= SPEED_CAP / mag
		end

		if isHeld then
			walkVelX, walkVelZ = 0, 0
		end

		-- 4. Gravity onto whichever is higher: the floor it can step onto here, or a body it stands on.
		local groundY = cbStandOn
		if grid then
			if node ~= NO_NODE then groundY = max(groundY, readf32(navHeights, node * 4)) end
		else
			groundY = max(groundY, ArenaCore.FlatY)
		end

		local vy = max(velocity.y - gravityStep, MAX_FALL_SPEED)
		if force.y ~= 0 then
			vy += force.y * invMass
		end

		local newY = pos.y + vy * dt
		if newY <= groundY then
			newY = groundY
			vy = 0
		end

		local newX, newZ = pos.x + walkVelX * dt, pos.z + walkVelZ * dt
		-- The walls above are a spring, and a crowd can shove a body through one: into the side of a stair, a post,
		-- off the map's edge into water. So a step that would end over no floor this body can stand on is refused
		-- outright. Measured from the floor it stands on, not its feet, so a jump or a knock-up cannot carry it in.
		if grid and node ~= NO_NODE then
			local standY = readf32(navHeights, node * 4)
			if floorNode(newX, standY, newZ) == NO_NODE then
				newX, newZ = pos.x, pos.z
				walkVelX, walkVelZ = 0, 0
			end
		end

		local newPos = vectorCreate(newX, newY, newZ)
		if newY < fallOutY then
			fellCount += 1
			fellEntity[fellCount] = entity
		end

		-- 5. Attacks.
		local attacks = data.Attacks
		local newWindup = attackWindup
		local newCount = attackCount
		if attackWindup > 0 then
			newWindup = attackWindup - dt
			if newWindup <= 0 then
				if windingUp and windingUp.Kind == "Melee" then
					local hits = sweepSwing(tick, newPos, walkDirX, walkDirZ, halfExtents, windingUp.Range)
					for i = 1, hits do
						landedCount += 1
						landedEntity[landedCount] = entity
						landedTarget[landedCount] = swingHits[i]
						landedScale[landedCount] = windingUp.DamageScale
					end
				end

				newWindup = -(if windingUp then windingUp.Cooldown else 1)
			end
		elseif attackWindup < 0 then
			newWindup = min(attackWindup + dt, 0)
		elseif targetId ~= 0 then
			-- The next attack in the pattern whose condition holds now.
			local count = #attacks
			local isSameLevel = abs(targetY - pos.y) <= SAME_LEVEL
			for offset = 0, count - 1 do
				local index = (attackCount + offset) % count + 1
				local attack = attacks[index]
				local isReady = if attack.Kind == "Melee"
					then sweepSwing(tick, newPos, walkDirX, walkDirZ, halfExtents, attack.Range) > 0
					else isSameLevel and toLen <= attack.Range
				if not isReady then continue end
				local center = if attack.AtTarget then vectorCreate(targetX, targetY, targetZ) else newPos
				if attack.Kind ~= "Melee" then
					-- Aimed as it will face once started: at its target.
					local aimYaw = if toLen > 1e-6 then atan2(toX, toZ) else atan2(walkDirX, walkDirZ)
					local isBoss = data.IsBoss == true
					local kind, size, width = TelegraphCore.ShapeOf(attack)
					local aim = vectorCreate(targetX, targetY, targetZ)
					if isAreaTaken(tick, isBoss, kind, center, aimYaw, size, width, aim) then continue end
					addStartWarning(isBoss, kind, center, aimYaw, size, width)
				end

				newWindup = attack.Delay
				newCount = attackCount + offset + 1
				EnemyWorld:set(entity, Components.AttackIndex, index)
				startCount += 1
				startEntity[startCount] = entity
				startIndex[startCount] = index
				startAttack[startCount] = attack
				startCenter[startCount] = center
				startTarget[startCount] = targetId

				-- Face what it is attacking from the first frame of the wind-up.
				if toLen > 1e-6 then
					walkDirX, walkDirZ = toX / toLen, toZ / toLen
				end

				break
			end
		end

		-- Facing is where it WANTS to go, not its position delta: a knocked-back body keeps facing its target.
		local newYaw = if isHeld then yaw else atan2(walkDirX, walkDirZ)

		EnemyWorld:set(entity, Components.Position, newPos)
		EnemyWorld:set(entity, Components.Velocity, vectorCreate(walkVelX, vy, walkVelZ))
		EnemyWorld:set(entity, Components.AttackWindup, newWindup)
		if newCount ~= attackCount then EnemyWorld:set(entity, Components.AttackCount, newCount) end
		EnemyWorld:set(entity, Components.Yaw, newYaw)
		EnemiesSpatialHash:Update(entity, newPos)

		written += 1
		outIds[written] = instanceId
		outPositions[written] = newPos
		outYaws[written] = newYaw
	end

	for i = 1, startCount do
		tick.OnAttackStarted(startEntity[i], startIndex[i], startAttack[i], startCenter[i], startTarget[i])
		startEntity[i] = nil
	end

	for i = 1, landedCount do
		tick.OnSwingLanded(landedEntity[i], landedTarget[i], landedScale[i])
		landedEntity[i] = nil
	end

	for i = 1, fellCount do
		tick.OnFellOut(fellEntity[i])
		fellEntity[i] = nil
	end

	debug.profileend()
	return written
end
