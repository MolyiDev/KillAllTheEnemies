--!native
--!optimize 2
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local GeneratorCore = require(ReplicatedStorage.Shared.Core.GeneratorCore)
local EntityPacker = require(ReplicatedStorage.Shared.Packers.EntityPacker)
local Grid = require(ReplicatedStorage.GlobalShared.Utils.Grid)
local SpatialHash = require(ReplicatedStorage.GlobalShared.Utils.SpatialHash)
local ECardinals = require(ReplicatedStorage.Types.Enums.ECardinals)
local nearestCharacter = require(ServerScriptService.Server.Utils.nearestCharacter)
local resolveCircleAABB = require(ServerScriptService.Server.Utils.resolveCircleAABB)

local clamp = math.clamp
local abs = math.abs
local sqrt = math.sqrt
local max = math.max
local min = math.min
local tableClear = table.clear
local magnitude = vector.magnitude
local vectorCreate = vector.create

local math_cos = math.cos
local math_rad = math.rad

-- Physics
local MAX_FALL_SPEED = -75
local K_FORCE = 100
local SPEED_CAP = 50
local VEL_ALPHA = 0.165
local GRAVITY = Workspace.Gravity
local CLIMB_BOOST = 30 -- The upward velocity impulse applied each frame when climbing.
local CLIMB_GRACE = 0.15
local BUMP_UP_VEL = 50 -- The vertical velocity of the "vault"
local BUMP_FORWARD_VEL = 20
local PUSH_ANGLE_COS = -math_cos(math_rad(45))
local SIDE_SLOPE_NORMAL_THRESHOLD = math_cos(math_rad(45))
local ENEMY_CLIMB_FORWARD_COS = math_cos(math_rad(30)) -- neighbor must be within 30° of directly ahead
local ENEMY_CLIMB_COOLDOWN = 0.7 -- seconds; must exceed full arc time of BUMP_UP_VEL (~0.51s)
-- `radius` is the model's full extent (max of X/Z) used everywhere as a collision
-- radius, so the enemy's true footprint is half of it. Holding enemies off walls
-- by the FULL extent floated their center a half-body-width past where the wall
-- actually is, so in a corner the stand-off exceeded the contact-damage reach
-- (radius * 0.55) and the player took no damage. Use the true half-extent so
-- enemies hug walls and can still reach a cornered player.
local WALL_RADIUS_SCALE = 0.4

local entityTable: EntityPacker.TEntityServerMap = {}
-- Reused per-entity info tables. entityTable maps entity -> one of these slot
-- tables each frame; the pool grows only to this worker's peak per-frame enemy
-- count and is never freed, so steady-state packing allocates nothing.
local infoSlots: { EntityPacker.TEntityServerInfo } = {}
local slotCount = 0
local unpackedBuckets: SpatialHash.Buckets = {}
local unpackedRecords: SpatialHash.Records = {}


-- Temporary lifecycle-safe decoder reuse experiment.
local auditEpoch=0
local auditRecordEpochs,auditBucketEpochs={},{}
local function auditDecode(rb,bb)
 auditEpoch+=1
 local off=2
 for _=1,buffer.readu16(rb,0) do
  local id=buffer.readu16(rb,off)
  local rec=unpackedRecords[id]
  if not rec then rec={};unpackedRecords[id]=rec end
  rec.x=buffer.readf32(rb,off+2);rec.z=buffer.readf32(rb,off+6);rec.y=buffer.readf32(rb,off+10)
  rec.shape=buffer.readu8(rb,off+14)
  if rec.shape==2 then
   rec.halfx=buffer.readu16(rb,off+15)*0.05;rec.halfy=buffer.readu16(rb,off+17)*0.05;rec.halfz=buffer.readu16(rb,off+19)*0.05
   off+=21
  elseif rec.shape==1 then rec.radius=buffer.readu16(rb,off+15)*0.05;off+=17
  else off+=15 end
  auditRecordEpochs[id]=auditEpoch
 end
 for id in unpackedRecords do if auditRecordEpochs[id]~=auditEpoch then unpackedRecords[id]=nil;auditRecordEpochs[id]=nil end end
 off=2
 for _=1,buffer.readu16(bb,0) do
  local key=buffer.readu32(bb,off);local n=buffer.readu16(bb,off+4)
  local bucket=unpackedBuckets[key]
  if bucket then table.clear(bucket) else bucket=table.create(n);unpackedBuckets[key]=bucket end
  off+=6
  for i=1,n do bucket[i]=buffer.readu16(bb,off);off+=2 end
  auditBucketEpochs[key]=auditEpoch
 end
 for key in unpackedBuckets do if auditBucketEpochs[key]~=auditEpoch then unpackedBuckets[key]=nil;auditBucketEpochs[key]=nil end end
end

-- Module-level state for the enemy-collision callback (avoids per-enemy closure allocation)
local cbEntity: any = nil
local cbPos = vectorCreate(0, 0)
local cbRadius = 0
local cbKForce = 0
local cbWalkDir = vectorCreate(0, 0)
local cbEffectiveHeight = 0
local cbWalkVel = vectorCreate(0, 0)
local cbClimbGrace = 0
local cbJustStartedEnemyClimb = false

-- Module-level grid fields (pre-bound once per update call, avoids repeated table lookups in hot loops)
local gridOriginX = 0
local gridOriginZ = 0
local gridCellSize = 0
local gridGrid: { any } = {}
local gridLevelHeight = 0

-- Module-level state for the grid neighbor (terrain wall) callback
local terrainCell: any = nil
local terrainPos = vectorCreate(0, 0, 0)
local terrainHeight = 0
local terrainRadius = 0
local terrainKForce = 0
local terrainWalkDir = vectorCreate(0, 0)
local terrainClimbGrace = 0
local terrainWalkVel = vectorCreate(0, 0)

local function gridNeighborCallback(ncx: number, ncy: number, visitedIndex: number)
	local neighborCell = gridGrid[visitedIndex]
	if not neighborCell then return end
	if terrainCell and terrainCell.IsSlope and terrainCell.NextCellIndex == visitedIndex then return end

	local deltaHeight = neighborCell.Height - terrainHeight

	local neighborActualHeight = neighborCell.Height
	if neighborCell.IsSlope then
		local baseHeight = neighborCell.Height
		local topHeight = baseHeight + gridLevelHeight

		local cellCenterX = gridOriginX + ncx * gridCellSize
		local cellCenterZ = gridOriginZ + ncy * gridCellSize

		local relativeX = terrainPos.x - cellCenterX
		local relativeZ = terrainPos.z - cellCenterZ

		local t = 0
		local slopeCardinal = neighborCell.SlopeCardinal

		if slopeCardinal == ECardinals.North then
			t = (relativeX + (gridCellSize / 2)) / gridCellSize
		elseif slopeCardinal == ECardinals.South then
			t = 1 - (relativeX + (gridCellSize / 2)) / gridCellSize
		elseif slopeCardinal == ECardinals.East then
			t = (relativeZ + (gridCellSize / 2)) / gridCellSize
		elseif slopeCardinal == ECardinals.West then
			t = 1 - (relativeZ + (gridCellSize / 2)) / gridCellSize
		end

		t = clamp(t, 0, 1)
		neighborActualHeight = baseHeight + (topHeight - baseHeight) * t
	end

	if terrainPos.y > neighborActualHeight then return end

	local wx = gridOriginX + ncx * gridCellSize
	local wz = gridOriginZ + ncy * gridCellSize
	local halfSize = gridCellSize / 2

	local nx, nz, pen = resolveCircleAABB(terrainPos.x, terrainPos.z, terrainRadius, wx, wz, halfSize, halfSize)

	if pen <= 0 then return end

	local isSideOfSlope = false
	if neighborCell.IsSlope then
		local slopeCardinal = neighborCell.SlopeCardinal
		local isNorthSouth = slopeCardinal == ECardinals.North or slopeCardinal == ECardinals.South
		local isEastWest = slopeCardinal == ECardinals.East or slopeCardinal == ECardinals.West
		isSideOfSlope = (isNorthSouth and abs(nz) > SIDE_SLOPE_NORMAL_THRESHOLD)
			or (isEastWest and abs(nx) > SIDE_SLOPE_NORMAL_THRESHOLD)
	end

	local isWall = deltaHeight > 0

	if not isWall and not isSideOfSlope then return end

	local walkVelMag = magnitude(terrainWalkVel)
	local dotWalk = 0
	if walkVelMag > 1e-6 then dotWalk = (terrainWalkVel.x * nx + terrainWalkVel.y * nz) / walkVelMag end

	local dotDesire = terrainWalkDir.x * nx + terrainWalkDir.y * nz

	if dotDesire < 0 or (isSideOfSlope and dotWalk < PUSH_ANGLE_COS) then
		terrainClimbGrace = CLIMB_GRACE
	elseif dotWalk < PUSH_ANGLE_COS then
		local fx = terrainKForce * nx * pen / 2
		local fz = terrainKForce * nz * pen / 2
		terrainWalkVel = vectorCreate(terrainWalkVel.x + fx, terrainWalkVel.y + fz)
	end
end

local function enemyCollisionCallback(neighbor: any)
	if neighbor == cbEntity then return end
	local info = unpackedRecords[neighbor]
	if not info then return end
	local dx = cbPos.x - info.x
	local dz = cbPos.z - info.z
	local dist2 = dx * dx + dz * dz
	local neighborRadius = max((info :: SpatialHash.RecordAABB).halfx, (info :: SpatialHash.RecordAABB).halfz)
	local minDist = cbRadius + neighborRadius
	if dist2 >= minDist * minDist then return end
	local dist = sqrt(dist2)
	if dist <= 0 then return end

	local penetration = minDist - dist
	local neighborTop = (info :: SpatialHash.RecordAABB).y + (info :: SpatialHash.RecordAABB).halfy * 2

	-- If already on top of this neighbor, treat it as a floor and skip all collision
	if cbPos.y >= neighborTop - 0.5 then
		if neighborTop > cbEffectiveHeight then cbEffectiveHeight = neighborTop end
		return
	end

	-- If neighbor is entirely above us (e.g. a flying enemy), skip horizontal collision
	if (info :: SpatialHash.RecordAABB).y > cbPos.y + cbRadius * 2 then return end

	local nx = dx / dist
	local nz = dz / dist
	local dotDesire = cbWalkDir.x * nx + cbWalkDir.y * nz
	local heightDiff = (info :: SpatialHash.RecordAABB).y - cbPos.y
	local isLower = heightDiff > 0.1
	local isTiebreaker = heightDiff > -0.1 and cbEntity < neighbor

	-- climbGrace == 0: not wall-climbing and not in cooldown from a previous enemy climb
	if
		dotDesire < -ENEMY_CLIMB_FORWARD_COS
		and heightDiff <= cbRadius * 2
		and (isLower or isTiebreaker)
		and cbClimbGrace == 0
	then
		cbJustStartedEnemyClimb = true
		cbClimbGrace = -ENEMY_CLIMB_COOLDOWN
		local scale = cbKForce * penetration / dist * 0.5
		cbWalkVel = vectorCreate(cbWalkVel.x + scale * dx, cbWalkVel.y + scale * dz)
	else
		local scale = cbKForce * penetration / dist
		cbWalkVel = vectorCreate(cbWalkVel.x + scale * dx, cbWalkVel.y + scale * dz)
	end
end

return function(
	actor: Actor,
	charPositions: { [number]: vector },
	bubbleCenters: { vector },
	bubbleRadii: { number },
	buckets: buffer,
	records: buffer,
	dt: number,
	grid: Grid.Grid<GeneratorCore.GridCell>,
	query: () -> (number, vector, vector, number, vector, number, number, number)
): buffer
	debug.profilebegin("Update")
	tableClear(entityTable)
	slotCount = 0
	if Workspace:GetAttribute("BallarcAuditReuse") then
 auditDecode(records,buckets)
else
 tableClear(unpackedBuckets);tableClear(unpackedRecords)
 tableClear(auditRecordEpochs);tableClear(auditBucketEpochs)
 SpatialHash.UnpackBucketsInto(buckets,unpackedBuckets);SpatialHash.UnpackRecordsInto(records,unpackedRecords)
end

	gridOriginX = grid.OriginX
	gridOriginZ = grid.OriginZ
	gridCellSize = grid.CellSize
	gridGrid = grid.Grid
	gridLevelHeight = GeneratorCore.LEVEL_HEIGHT

	local gravity = GRAVITY * dt
	local kForce = K_FORCE * dt

	for entity, pos, velocity, radius, force, speed, climbGrace, explosionRadius in query do
		-- Walk
		local targetId, targetPos = nearestCharacter(pos, charPositions)
		local toTargetLen = magnitude(targetPos)

		local isTelegraphing = false
		if explosionRadius > 0 then
			local actualPos = charPositions[targetId]
			if actualPos then
				local dx = pos.x - actualPos.x
				local dy = pos.y - actualPos.y
				local dz = pos.z - actualPos.z
				-- 3D check so a target far above (e.g. on a high ledge) is outside the
				-- explosion sphere and the enemy never starts its telegraph.
				if dx * dx + dy * dy + dz * dz <= explosionRadius * explosionRadius then
					actor:SendMessage("Telegraph", entity)
					isTelegraphing = true
				end
			end
		end

		local walkDir = if toTargetLen > 1e-6 then targetPos / toTargetLen else vectorCreate(1, 0, 0)
		local walkVel = if isTelegraphing then vectorCreate(0, 0, 0) else (walkDir * speed)

		-- Collisions
		cbEntity = entity
		cbPos = pos
		cbRadius = radius
		cbKForce = kForce
		cbWalkDir = walkDir
		cbEffectiveHeight = 0
		cbWalkVel = walkVel
		cbClimbGrace = climbGrace
		cbJustStartedEnemyClimb = false
		SpatialHash.QueryRadius(pos.x, pos.z, radius, 5, enemyCollisionCallback, unpackedBuckets, unpackedRecords)
		local effectiveHeight = cbEffectiveHeight
		walkVel = cbWalkVel
		climbGrace = cbClimbGrace
		local justStartedEnemyClimb = cbJustStartedEnemyClimb

		-- NOTE: This can be used for props.

		-- WallsService.WallsSpatialHash:QueryRadius(pos.x, pos.z, radius, function(wall)
		-- 	local info = WallsService.WallsSpatialHash.Records[wall]
		-- 	if not info then return end
		-- 	local nx, nz, pen =
		-- 		resolveCircleAABB(pos.x, pos.z, radius, info.x, info.z, (info :: any).halfx, (info :: any).halfz)
		-- 	if pen > 0 then
		-- 		-- same force model: quadratic in penetration
		-- 		local p2 = pen * pen
		-- 		local fx = kForce * nx * p2
		-- 		local fz = kForce * nz * p2
		-- 		walkVel = vector.create(walkVel.x + fx, walkVel.y + fz)
		-- 	end
		-- end)

		-- Smooth natural walking against the previous velocity along walkDir. Done
		-- before external forces are added so magnet pulls/knockbacks aren't
		-- damped against an unrelated direction (walkDir is toward the player,
		-- not toward the pull target).
		local forward = max(0, velocity.x * walkDir.x + velocity.z * walkDir.y)
		-- Cap persisted forward momentum to the enemy's own speed when no force
		-- is active, so collision pushes can't snowball walkVel toward the player
		-- across frames. Force-driven momentum is preserved untouched.
		if force.x == 0 and force.y == 0 and force.z == 0 then forward = min(forward, speed) end
		local alongPrev = walkDir * forward
		walkVel = alongPrev * (1 - VEL_ALPHA) + walkVel * VEL_ALPHA

		-- Pre-force cap so collision-induced speed stays close to the enemy's
		-- walking speed. Applied before force so magnet pulls aren't limited.
		local preForceCap = speed * 1.5
		local mag = magnitude(walkVel)
		if mag > preForceCap then
			walkVel *= preForceCap / mag
		end

		-- Apply external forces (e.g. BlackHole pull) on top of the smoothed
		-- walk so they directly contribute to velocity rather than being lerped
		-- against the toward-player projection.
		if force.x ~= 0 or force.y ~= 0 or force.z ~= 0 then
			walkVel = vectorCreate(walkVel.x + force.x, walkVel.y + force.z)
		end

		mag = magnitude(walkVel)
		if mag > SPEED_CAP then
			walkVel *= SPEED_CAP / mag
		end

		local cellX, cellY = grid.GetCellXYFromWorldPos(grid, pos)
		local height = 0
		local cell: GeneratorCore.GridCell?

		if cellX and cellY then
			cell = grid.GetCell(grid, cellX, cellY)
			if cell then
				-- First, calculate the current height based on the cell we are in
				if cell.IsSlope then
					local baseHeight = cell.Height
					local topHeight = baseHeight + gridLevelHeight

					local cellCenterX = gridOriginX + cellX * gridCellSize
					local cellCenterZ = gridOriginZ + cellY * gridCellSize

					local relativeX = pos.x - cellCenterX
					local relativeZ = pos.z - cellCenterZ

					local t = 0
					local slopeCardinal = cell.SlopeCardinal

					if slopeCardinal == ECardinals.North then
						t = (relativeX + (gridCellSize / 2)) / gridCellSize
					elseif slopeCardinal == ECardinals.South then
						t = 1 - (relativeX + (gridCellSize / 2)) / gridCellSize
					elseif slopeCardinal == ECardinals.East then
						t = (relativeZ + (gridCellSize / 2)) / gridCellSize
					elseif slopeCardinal == ECardinals.West then
						t = 1 - (relativeZ + (gridCellSize / 2)) / gridCellSize
					else
						height = cell.Height
					end

					t = clamp(t, 0, 1)
					height = baseHeight + (topHeight - baseHeight) * t
				else
					height = cell.Height
				end

				if height > effectiveHeight then effectiveHeight = height end

				-- Now, check neighbors for wall collisions
				local cellIndex = grid.GetCellIndex(grid, cellX, cellY)
				terrainCell = cell
				terrainPos = pos
				terrainHeight = height
				terrainRadius = radius * WALL_RADIUS_SCALE
				terrainKForce = kForce
				terrainWalkDir = walkDir
				terrainClimbGrace = climbGrace
				terrainWalkVel = walkVel
				grid.ForNeighbors(grid, cellIndex, Grid.ADJACENT, gridNeighborCallback)
				climbGrace = terrainClimbGrace
				walkVel = terrainWalkVel
			end
		end

		-- Chest-protection bubble repulsion (XZ-only, treated as a cylinder for
		-- ground enemies). Linear scan is fine because #bubbleCenters is 0–3 in
		-- practice. Re-cap afterward: the spring force blows up for enemies near
		-- the bubble center, which would otherwise teleport them out of bounds.
		local inBubble = false
		for i = 1, #bubbleCenters do
			local bc = bubbleCenters[i]
			local bx = pos.x - bc.x
			local bz = pos.z - bc.z
			local bdist2 = bx * bx + bz * bz
			local bMinDist = bubbleRadii[i] + radius
			if bdist2 < bMinDist * bMinDist and bdist2 > 1e-6 then
				inBubble = true
				local bdist = sqrt(bdist2)
				local bpen = bMinDist - bdist
				local bScale = kForce * bpen * bpen / bdist
				walkVel = vectorCreate(walkVel.x + bScale * bx, walkVel.y + bScale * bz)
			end
		end
		if inBubble then
			local bubbleMag = magnitude(walkVel)
			if bubbleMag > SPEED_CAP then
				walkVel *= SPEED_CAP / bubbleMag
			end
		end

		-- Gravity or Climbing
		if justStartedEnemyClimb then
			-- One-time upward impulse; climbGrace is now negative (cooldown), preventing repeats
			velocity = vectorCreate(walkVel.x, BUMP_UP_VEL, walkVel.y)
		elseif climbGrace > 0 then
			climbGrace = max(climbGrace - dt, 0)

			if climbGrace == 0 then
				velocity = vectorCreate(
					walkDir.x * BUMP_FORWARD_VEL, -- Forward bump
					BUMP_UP_VEL, -- Upward bump
					walkDir.y * BUMP_FORWARD_VEL -- Forward bump
				)
			else
				velocity = vectorCreate(0, CLIMB_BOOST, 0)
			end
		elseif climbGrace < 0 then
			-- Enemy-climb cooldown: count toward 0, apply only gravity
			climbGrace = min(climbGrace + dt, 0)
			velocity = vectorCreate(walkVel.x, max(velocity.y - gravity, MAX_FALL_SPEED), walkVel.y)
		else
			velocity = vectorCreate(walkVel.x, max(velocity.y - gravity, MAX_FALL_SPEED), walkVel.y)
		end

		if force.y ~= 0 then velocity = vectorCreate(velocity.x, velocity.y + force.y, velocity.z) end

		-- Final
		local finalPos = vectorCreate(
			pos.x + velocity.x * dt,
			max(pos.y + velocity.y * dt, effectiveHeight),
			pos.z + velocity.z * dt
		)

		-- Damage
		local touchingTarget = false

		local actualPos = charPositions[targetId]
		if actualPos then
			-- 1. Calculate Horizontal Distance (X and Z only)
			local dx = finalPos.x - actualPos.x
			local dz = finalPos.z - actualPos.z

			local distSquared2D = dx * dx + dz * dz

			local reachThreshold = radius * 0.55

			-- 2. Check Horizontal proximity first (Cheap check)
			if distSquared2D <= (reachThreshold * reachThreshold) then
				-- 3. Check Vertical Height (The "Tall" part)
				-- dy is the difference between Target Middle and Enemy Feet
				local dy = actualPos.y - finalPos.y

				-- BEAN LOGIC:
				-- Min: -2 (Allows hitting target if target is slightly below enemy)
				-- Max: radius * 4 (The enemy is tall, so the hit range extends upwards)
				local enemyHeight = radius * 4

				if dy >= -2 and dy <= enemyHeight then touchingTarget = true end
			end
		end

		if touchingTarget and not isTelegraphing then
			local targetInBubble = false
			local actualPos2 = charPositions[targetId]
			if actualPos2 then
				for i = 1, #bubbleCenters do
					local bc = bubbleCenters[i]
					local br = bubbleRadii[i]
					local bx = actualPos2.x - bc.x
					local bz = actualPos2.z - bc.z
					if bx * bx + bz * bz <= br * br then
						targetInBubble = true
						break
					end
				end
			end
			if not targetInBubble then actor:SendMessage("Damage", targetId, entity) end
		end

		slotCount += 1
		local info = infoSlots[slotCount]
		if info then
			info.pos = finalPos
			info.velocity = velocity
			info.climbGrace = climbGrace
		else
			info = {
				pos = finalPos,
				velocity = velocity,
				climbGrace = climbGrace,
			} :: EntityPacker.TEntityServerInfo
			infoSlots[slotCount] = info
		end
		entityTable[entity] = info
	end

	debug.profilebegin("Pack")
	local packed = EntityPacker.PackServer(entityTable)
	debug.profileend()
	debug.profileend()
	return packed
end

