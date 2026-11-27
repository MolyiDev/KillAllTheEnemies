return function(Context)
local jecs = require(game:GetService("ReplicatedStorage").Packages.jecs)
local Components = require(game:GetService("ReplicatedStorage").GlobalShared.ECS.Components)
local Tags = require(game:GetService("ReplicatedStorage").GlobalShared.ECS.Tags)
local EnemyWorld = require(game:GetService("ReplicatedStorage").GlobalShared.ECS.Worlds.EnemyWorld)
local EnemiesCore = require(game:GetService("ReplicatedStorage").Shared.Core.EnemiesCore)
local ArenaCore = require(game:GetService("ReplicatedStorage").Shared.Core.ArenaCore)
local DataCore = require(game:GetService("ReplicatedStorage").GlobalShared.Core.DataCore)
local RoundCore = require(game:GetService("ReplicatedStorage").Shared.Core.RoundCore)
local EnemyPacker = require(game:GetService("ReplicatedStorage").Shared.Packers.EnemyPacker)
local NavService = require(game:GetService("ServerScriptService").Server.Services.NavService)
local enemiesUpdate = require(game:GetService("ServerScriptService").Server.Utils.enemiesUpdate)


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
local t0 = Context.WorkSeconds()
ArenaCore.Nav = ArenaCore.Build(W, D, CELL, originX, originZ, floors)
local nav = ArenaCore.Nav
NavService.Reset()
print(string.format("nav: %d nodes, built in %.1f ms", nav.NodeCount, (Context.WorkSeconds() - t0) * 1000))
local function cellCenter(x, z)
	return originX + x * CELL, originZ + z * CELL
end

-- Two players: on the deck, and on the ground far north-west.
local deckX, deckZ = cellCenter(40, 40)
local groundX, groundZ = cellCenter(8, 70)
local feet = { [1] = vector.create(deckX, 8, deckZ), [2] = vector.create(groundX, 0, groundZ) }
for id, at in feet do
	NavService.SetCharacterNode(id, ArenaCore.NodeAt(nav, at.x, at.y, at.z, 0.75))
	local f0 = Context.WorkSeconds()
	NavService.Flood(nav, NavService.CharacterFields[id])
	print(string.format("flowfield %d flooded in %.1f ms", id, (Context.WorkSeconds() - f0) * 1000))
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

if Context.Boss then
	-- A T-Rex-sized record far off the crowd: only its extent matters.
	local bossE = EnemyWorld:entity()
	EnemiesCore.EnemiesSpatialHash:AddAABB(bossE, vector.create(1000, 0, 1000), vector.create(5.625, 6, 5.625))
end
local started, landed, fell = {}, { chars = 0, barricade = 0 }, 0
-- EnemyAttacksService's pending warnings, each dropped when its wind-up runs out; `stacked` counts a warning started
-- on top of one of its class, which enemiesUpdate must never do.
local TelegraphCoreSim = require(game:GetService("ReplicatedStorage").Shared.Core.TelegraphCore)
local warnings, warningEnds, simClock, stacked = {}, {}, 0, 0
-- The body each warning blows up, false for any other kind. The game's blast removes it; here it stays to keep the
-- crowd at the cap but never fuses again, or it would stand still on a warning for the whole run.
local warningBlasts = {}
local tick
tick = {
	Dt = 0.1,
	CharacterFeet = feet,
	Lures = {},
	BarricadeIds = { 7 },
	BarricadeCenters = { vector.create(bx, 0, bz) },
	BarricadeHalves = { vector.create(5, 2.5, 1) },
	BarricadeCount = 1,
	Warnings = warnings,
	OutIds = {},
	OutPositions = {},
	OutYaws = {},
	OutViews = {},
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
		table.insert(warningBlasts, if attack.Kind == "Explode" then enemy else false)
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
		local blasted = warningBlasts[i]
		if blasted then EnemyWorld:set(blasted, Components.AttackWindup, -math.huge) end
		table.remove(warnings, i)
		table.remove(warningEnds, i)
		table.remove(warningBlasts, i)
	end
end
local aggro = {}
local times = {}
Context.ProfilePhase("steady")
for t = 1, 600 do
	table.clear(aggro)
	local c0 = Context.WorkSeconds()
	expireWarnings()
	local n = enemiesUpdate(query, tick, aggro)
	times[t] = Context.WorkSeconds() - c0
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


	print("@done")
end
