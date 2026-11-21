-- Headless check of the enemy pipeline through the real modules (jecs, SpatialHash, ArenaCore's nav graph,
-- NavService's flowfields, enemiesUpdate, EnemyPacker), on a synthetic map built with ArenaCore.Build:
--   * flat ground, 80 x 80 cells (160 studs);
--   * a deck 8 studs up on posts in the middle, walkable on top AND underneath, reached only by a stair on its
--     south side (eight 1-stud steps);
--   * a 12-stud wall across the south of the map with one gap, so the ground route bends.
-- One player stands on the deck, one on the ground far away. Run from the repo root:
--   lune run tools/lune/sim.luau "$PWD"
-- Timings are lune interpreter numbers, not Roblox ones.
local process = require("@lune/process")
local H = require("./harness")(process.args[1])

local jecs = H.require("ReplicatedStorage/Packages/jecs")
local Components = H.require("ReplicatedStorage/GlobalShared/ECS/Components")
local Tags = H.require("ReplicatedStorage/GlobalShared/ECS/Tags")
local EnemyWorld = H.require("ReplicatedStorage/GlobalShared/ECS/Worlds/EnemyWorld")
local EnemiesCore = H.require("ReplicatedStorage/Shared/Core/EnemiesCore")
local ArenaCore = H.require("ReplicatedStorage/Shared/Core/ArenaCore")
local DataCore = H.require("ReplicatedStorage/GlobalShared/Core/DataCore")
local RoundCore = H.require("ReplicatedStorage/Shared/Core/RoundCore")
local EnemyPacker = H.require("ReplicatedStorage/Shared/Packers/EnemyPacker")
local NavService = H.require("ServerScriptService/Server/Services/NavService")
local enemiesUpdate = H.require("ServerScriptService/Server/Utils/enemiesUpdate")

-- Rounds
for _, r in { 1, 5, 10, 20, 40 } do
	local h, d, s = RoundCore.GetScales(r)
	local gold, gems = RoundCore.GetClearRewards(r)
	print(
		string.format(
			"round %2d: solo %3d, 4p %3d | hp x%.2f dmg x%.2f spd x%.2f | boss %s | clear $%d %d gems",
			r,
			RoundCore.GetCount(r, 1),
			RoundCore.GetCount(r, 4),
			h,
			d,
			s,
			tostring(RoundCore.IsBossRound(r)),
			gold,
			gems
		)
	)
end

-- The map.
local W, D, CELL = 80, 80, 2
local floors = {}
for z = 0, D - 1 do
	for x = 0, W - 1 do
		local column
		local onDeck = x >= 30 and x <= 49 and z >= 30 and z <= 49
		local isPost = onDeck and (x % 6 == 0) and (z % 6 == 0)
		if isPost then
			column = { 8 }
		elseif onDeck then
			column = { 8, 0 }
		elseif x >= 38 and x <= 41 and z >= 22 and z <= 29 then
			column = { z - 21 } -- stair: 1 at z=22 up to 8 at z=29
		elseif z == 15 and not (x >= 34 and x <= 38) then
			column = { 12 }
		else
			column = { 0 }
		end
		floors[z * W + x + 1] = column
	end
end
local originX, originZ = -(W - 1) * CELL / 2, -(D - 1) * CELL / 2
local t0 = os.clock()
ArenaCore.Nav = ArenaCore.Build(W, D, CELL, originX, originZ, floors)
local nav = ArenaCore.Nav
NavService.Reset()
print(string.format("nav: %d nodes, built in %.1f ms", nav.NodeCount, (os.clock() - t0) * 1000))
local function cellCenter(x, z)
	return originX + x * CELL, originZ + z * CELL
end

-- Two players: on the deck, and on the ground far north-west.
local deckX, deckZ = cellCenter(40, 40)
local groundX, groundZ = cellCenter(8, 70)
local feet = { [1] = vector.create(deckX, 8, deckZ), [2] = vector.create(groundX, 0, groundZ) }
for id, at in feet do
	NavService.SetCharacterNode(id, ArenaCore.NodeAt(nav, at.x, at.y, at.z, 0.75))
	local f0 = os.clock()
	NavService.Flood(nav, NavService.CharacterFields[id])
	print(string.format("flowfield %d flooded in %.1f ms", id, (os.clock() - f0) * 1000))
end
-- A barricade on the ground east of the deck.
local bx, bz = cellCenter(60, 40)
local barricadeNodes = {}
for x = 58, 62 do
	table.insert(barricadeNodes, ArenaCore.NodeAt(nav, originX + x * CELL, 0, bz, 0.75))
end
NavService.SetBlocked(barricadeNodes, true)
local ring = {}
for _, n in barricadeNodes do
	for d = 1, 8 do
		local l = ArenaCore.Link(nav, n, d)
		if l ~= -1 and buffer.readu8(NavService.Blocked, l) == 0 then table.insert(ring, l) end
	end
end
NavService.SetBarricadeSources(ring)
for _, f in NavService.CharacterFields do
	NavService.Flood(nav, f)
end
NavService.Flood(nav, NavService.BarricadeField)

-- Path costs: from just south of the wall, the deck player is far further by path than by line.
local probe = ArenaCore.NodeAt(nav, cellCenter(40, 10), 0, ({ cellCenter(40, 10) })[2], 0.75)
local d1 = buffer.readu32(NavService.CharacterFields[1].Dist, probe * 4) * CELL / 10
local px, pz = cellCenter(40, 10)
print(
	string.format(
		"probe south of wall: deck player %.0f studs by path vs %.0f by line",
		d1,
		math.sqrt((px - deckX) ^ 2 + (pz - deckZ) ^ 2)
	)
)

-- 255 enemies on the south strip, below the wall.
local query = EnemyWorld:query(
	Components.Position,
	Components.Velocity,
	Components.Force,
	Components.Radius,
	Components.HalfExtents,
	Components.Mass,
	Components.AttackWindup,
	Components.AttackCount,
	Components.MovementSpeed,
	Components.Yaw,
	Components.InstanceId,
	Components.Data
)
	:with(Tags.Enemy)
	:cached()
local roster = {}
for _, e in DataCore.Enemies.All do
	if not e.IsBoss then table.insert(roster, e) end
end
local seed = 7
local rng = {
	NextInteger = function(_, lo, hi)
		seed = (seed * 1103515245 + 12345) % 2147483648
		return lo + seed % (hi - lo + 1)
	end,
}
for i = 1, EnemiesCore.MAX_ALIVE do
	local data = roster[(i % #roster) + 1]
	local x, z = cellCenter(rng:NextInteger(2, 77), rng:NextInteger(1, 12))
	local pos = vector.create(x, 0, z)
	local cs = data.CollisionSize
	local half = vector.create(cs.X / 2, cs.Y / 2, cs.Z / 2)
	local e = EnemyWorld:entity()
	jecs.bulk_insert(EnemyWorld, e, {
		Components.Position,
		Components.Velocity,
		Components.Force,
		Components.Radius,
		Components.HalfExtents,
		Components.Mass,
		Components.AttackWindup,
		Components.AttackIndex,
		Components.AttackCount,
		Components.MovementSpeed,
		Components.Yaw,
		Components.InstanceId,
		Components.Data,
		Components.Damage,
		Tags.Enemy,
	}, {
		pos,
		vector.zero,
		vector.zero,
		math.max(cs.X, cs.Z),
		half,
		data.Mass,
		0,
		1,
		0,
		data.BaseMovementSpeed,
		0,
		i,
		data,
		data.BaseDamage,
	})
	EnemiesCore.EnemiesSpatialHash:AddAABB(e, pos, half)
end

local started, landed, fell = {}, { chars = 0, barricade = 0 }, 0
-- EnemyAttacksService's pending warnings, each dropped when its wind-up runs out; `stacked` counts a warning started
-- on top of one of its class, which enemiesUpdate must never do.
local TelegraphCoreSim = H.require("ReplicatedStorage/Shared/Core/TelegraphCore")
local warnings, warningEnds, simClock, stacked = {}, {}, 0, 0
local tick
tick = {
	Dt = 0.1,
	CharacterFeet = feet,
	BarricadeIds = { 7 },
	BarricadeCenters = { vector.create(bx, 0, bz) },
	BarricadeHalves = { vector.create(5, 2.5, 1) },
	BarricadeCount = 1,
	Warnings = warnings,
	OutIds = {},
	OutPositions = {},
	OutYaws = {},
	OnAttackStarted = function(enemy, _, attack, center, target)
		started[attack.Kind] = (started[attack.Kind] or 0) + 1
		if attack.Kind == "Melee" then return end
		local kind, size, width = TelegraphCoreSim.ShapeOf(attack)
		local yaw = EnemyWorld:get(enemy, Components.Yaw)
		local aim = tick.CharacterFeet[target] or center
		local warning = { IsBoss = false, Kind = kind, Center = center, Yaw = yaw, Size = size, Width = width }
		for _, other in warnings do
			if TelegraphCoreSim.IsOnTopOf(kind, center, yaw, size, width, aim, other) then
				stacked += 1
				break
			end
		end
		table.insert(warnings, warning)
		table.insert(warningEnds, simClock + attack.Delay)
	end,
	OnSwingLanded = function(_, target)
		if target < 0 then
			landed.barricade += 1
		else
			landed.chars += 1
		end
	end,
	OnFellOut = function()
		fell += 1
	end,
}
-- One tick of the clock the pending warnings run on.
local function expireWarnings()
	simClock += tick.Dt
	for i = #warnings, 1, -1 do
		if simClock < warningEnds[i] then continue end
		table.remove(warnings, i)
		table.remove(warningEnds, i)
	end
end
local aggro = {}
local times = {}
for t = 1, 600 do
	table.clear(aggro)
	local c0 = os.clock()
	expireWarnings()
	local n = enemiesUpdate(query, tick, aggro)
	times[t] = os.clock() - c0
	assert(n == EnemiesCore.MAX_ALIVE)
end
table.sort(times)
print(
	string.format(
		"update ms over 60 s: median %.2f p95 %.2f (lune; not a Roblox number)",
		times[300] * 1000,
		times[570] * 1000
	)
)

local onDeck, underDeck, nearGround, nan, stuckSouth = 0, 0, 0, 0, 0
for _, pos in query do
	if pos.x ~= pos.x then
		nan += 1
	end
	local inDeckXZ = pos.x >= cellCenter(30, 0) - 1
		and pos.x <= cellCenter(49, 0) + 1
		and pos.z >= ({ cellCenter(0, 30) })[2] - 1
		and pos.z <= ({ cellCenter(0, 49) })[2] + 1
	if inDeckXZ and pos.y > 7 then
		onDeck += 1
	elseif inDeckXZ then
		underDeck += 1
	end
	if math.sqrt((pos.x - groundX) ^ 2 + (pos.z - groundZ) ^ 2) < 15 then
		nearGround += 1
	end
	if pos.z < ({ cellCenter(0, 15) })[2] then
		stuckSouth += 1
	end
end
print(
	string.format(
		"after 60 s: %d on the deck, %d under it, %d at the ground player, %d still south of the wall, NaN %d, fell %d",
		onDeck,
		underDeck,
		nearGround,
		stuckSouth,
		nan,
		fell
	)
)
local kinds = {}
for k, v in started do
	table.insert(kinds, k .. "=" .. v)
end
print(
	"attacks started:",
	table.concat(kinds, " "),
	"| started on another's warning:",
	stacked,
	"| melee landed on players:",
	landed.chars,
	"on the barricade:",
	landed.barricade
)

-- Phase 2: the barricade goes. The deck player is reachable only by the stair, the ground player by the wall's gap.
NavService.SetBlocked(barricadeNodes, false)
NavService.SetBarricadeSources({})
for _, f in NavService.CharacterFields do
	NavService.Flood(nav, f)
end
tick.BarricadeCount = 0
for _ = 1, 600 do
	table.clear(aggro)
	expireWarnings()
	enemiesUpdate(query, tick, aggro)
end
local deck2, under2, stair2, ground2 = 0, 0, 0, 0
local stairX0, stairX1 = cellCenter(38, 0) - 1, cellCenter(41, 0) + 1
for _, pos in query do
	local inDeckXZ = pos.x >= cellCenter(30, 0) - 1
		and pos.x <= cellCenter(49, 0) + 1
		and pos.z >= ({ cellCenter(0, 30) })[2] - 1
		and pos.z <= ({ cellCenter(0, 49) })[2] + 1
	if inDeckXZ and pos.y > 7 then
		deck2 += 1
	elseif inDeckXZ then
		under2 += 1
	end
	if pos.x >= stairX0 and pos.x <= stairX1 and pos.y > 0.5 and pos.y < 7.5 then
		stair2 += 1
	end
	if math.sqrt((pos.x - groundX) ^ 2 + (pos.z - groundZ) ^ 2) < 20 then
		ground2 += 1
	end
end
local below = 0
for _, pos in query do
	if pos.y < -0.5 then
		below += 1
	end
end
print(
	string.format(
		"phase 2 (no barricade), 60 s more: %d on the deck, %d climbing the stair, %d under the deck, %d at the ground player, %d below the floor, fell %d",
		deck2,
		stair2,
		under2,
		ground2,
		below,
		fell
	)
)

-- Crowd spacing: each body's distance to its nearest neighbour on its own level, centre to centre. A Basic body is 2
-- wide, so 3 is touching edge to edge.
local positions = {}
for _, pos in query do
	positions[#positions + 1] = pos
end
local nearest = {}
for i, a in positions do
	local best = math.huge
	for j, b in positions do
		if i ~= j and math.abs(a.y - b.y) < 2 then best = math.min(best, vector.magnitude(a - b)) end
	end
	if best < math.huge then nearest[#nearest + 1] = best end
end
table.sort(nearest)
print(
	string.format(
		"crowd spacing (nearest neighbour, centre to centre): p10 %.2f median %.2f p90 %.2f studs",
		nearest[math.max(1, math.floor(#nearest * 0.1))],
		nearest[math.max(1, math.floor(#nearest * 0.5))],
		nearest[math.max(1, math.floor(#nearest * 0.9))]
	)
)

-- Packer round trip on the last tick's output.
local count = #tick.OutIds
local pkt = EnemyPacker.PackFiltered(tick.OutIds, tick.OutPositions, tick.OutYaws, count, 0, 50, 0, 0, 0, 1, -1, 1e9)
local P, Y, M, L = {}, {}, {}, {}
EnemyPacker.UnpackInto(pkt, P, Y, M, L, 1)
local maxErr = 0
for i, id in tick.OutIds do
	local p = tick.OutPositions[i]
	maxErr = math.max(maxErr, math.abs(P[id].X - p.x), math.abs(P[id].Y - p.y), math.abs(P[id].Z - p.z))
end
print(string.format("packet %d bytes for %d; max position error %.3f studs", buffer.len(pkt), count, maxErr))

-- Telegraph footprints: a warning covers the floor it was cast on and what that floor steps onto, never the deck
-- over it, never past a wall.
local TelegraphCore = H.require("ReplicatedStorage/Shared/Core/TelegraphCore")
local ETelegraphs = H.require("ReplicatedStorage/Types/Enums/ETelegraphs")
local function footprint(kind, cx, cz, y, yaw, size, width)
	local x, z = cellCenter(cx, cz)
	local covered = {}
	local floorY = TelegraphCore.Footprint(nav, kind, vector.create(x, y, z), yaw, size, width, covered)
	return covered, floorY, vector.create(x, floorY or y, z)
end
local function inside(covered, kind, center, yaw, size, width, cx, cz, y)
	local x, z = cellCenter(cx, cz)
	return TelegraphCore.IsInside(nav, covered, kind, center, yaw, size, width, vector.create(x, y, z))
end
local C, L, R = ETelegraphs.Circle, ETelegraphs.Line, ETelegraphs.Ring
-- Under the deck: the ground under it, not the deck overhead.
local underDeck, _, underCenter = footprint(C, 37, 37, 0, 0, 10, 0)
-- At the stair's foot: the ground and the treads within HEIGHT, not the deck.
local stairFoot, _, stairCenter = footprint(C, 40, 21, 0, 0, 14, 0)
-- South of the wall: the wall stops it.
local byWall, _, wallCenter = footprint(C, 20, 13, 0, 0, 10, 0)
-- A line north from the same spot, into the wall.
local line, _, lineCenter = footprint(L, 20, 10, 0, 0, 20, 4)
print(
	string.format(
		"telegraphs: under deck %s/%s (ground/deck), stair foot %s/%s/%s/%s (tread 3/tread 6/tread 7/deck), wall %s/%s (south/north), line %s/%s (before/past wall), floor under a deck player %s",
		tostring(inside(underDeck, C, underCenter, 0, 10, 0, 38, 38, 0)),
		tostring(inside(underDeck, C, underCenter, 0, 10, 0, 38, 38, 8)),
		tostring(inside(stairFoot, C, stairCenter, 0, 14, 0, 40, 24, 3)),
		tostring(inside(stairFoot, C, stairCenter, 0, 14, 0, 40, 27, 6)),
		tostring(inside(stairFoot, C, stairCenter, 0, 14, 0, 40, 28, 7)),
		tostring(inside(stairFoot, C, stairCenter, 0, 14, 0, 40, 30, 8)),
		tostring(inside(byWall, C, wallCenter, 0, 10, 0, 20, 11, 0)),
		tostring(inside(byWall, C, wallCenter, 0, 10, 0, 20, 17, 0)),
		tostring(inside(line, L, lineCenter, 0, 20, 4, 20, 13, 0)),
		tostring(inside(line, L, lineCenter, 0, 20, 4, 20, 18, 0)),
		tostring(TelegraphCore.FloorUnder(nav, underDeck, underCenter, vector.create(deckX, 8, deckZ)))
	)
)
