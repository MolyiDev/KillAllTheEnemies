-- Headless check of the weapon ladder (GunsCore.LADDER): how fast each step kills, so every step up is one. Shots
-- are resolved as WeaponService resolves them (GunsCore's pellets against the bodies' aim shapes, the head figure,
-- the pierce), from a player standing still who aims at the chest of the nearest body, as the aim assist does. A
-- shove is only a step back here: the second a shoved body then takes to get back up to speed (enemiesUpdate) is
-- not modelled, so a shoving gun holds a crowd off better than this shows. Two readings:
--   * one Basic alone at a distance: seconds to put it down;
--   * a crowd of the round's own mix walking in from the spawn ring, kept at a count: kills a second.
-- Run from the repo root:
--   lune run tools/lune/guns.luau "$PWD" [overrides.luau]
-- `overrides.luau` returns { [gun Name] = { field = value } }, to try numbers before they go into Data/Guns.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local H = require("./harness")(process.args[1])

local Vector3 = roblox.Vector3
local DataCore = H.require("ReplicatedStorage/GlobalShared/Core/DataCore")
local GunsCore = H.require("ReplicatedStorage/GlobalShared/Core/GunsCore")
local EnemiesCore = H.require("ReplicatedStorage/Shared/Core/EnemiesCore")
local RoundCore = H.require("ReplicatedStorage/Shared/Core/RoundCore")

-- WeaponService's Tune.LAG_PAD and KNOCKBACK_MIN_SHARE, and EnemiesService's OVERKILL_DAMAGE_RATIO: keep them in step.
local LAG_PAD = 0.75
local KNOCKBACK_MIN_SHARE = 0.25
local OVERKILL_RATIO = 4
-- An R6 body's root over its feet: the shot leaves EYE_HEIGHT above it.
local ROOT_HEIGHT = 3
-- RoundService's spawn ring.
local RING_MIN, RING_MAX = 60, 85
local ARC = math.rad(120)
local REACH = 3
local SPACING = 2.6
local DT = 0.05
local SECONDS = 60
local SEEDS = 4

local overrides = {}
if process.args[2] then overrides = luau.load(luau.compile(fs.readFile(process.args[2])))() end

local function gunOf(step)
	local gun = table.clone(DataCore.Guns.ById[step.Gun])
	for field, value in overrides[gun.Name] or {} do
		gun[field] = value
	end
	return gun
end

local EYE = Vector3.new(0, ROOT_HEIGHT + GunsCore.Tune.EYE_HEIGHT, 0)
local bodies = GunsCore.NewBodies()
local directions = {}

-- One shot at `aim` against `crowd` (bodies with x, z, hp): the damage each body takes, as WeaponService.shoot adds it
-- up. Returns the map body -> damage and the shot's direction.
local function resolve(gun, crowd, aim, seed)
	bodies.Count = 0
	for _, body in crowd do
		GunsCore.AddBody(bodies, Vector3.new(body.x, 0, body.z), body.aim.z, body.aim.y)
	end

	local direction = (aim - EYE).Unit
	local pellets = math.min(gun.Pellets, GunsCore.Tune.MAX_PELLETS)
	local pelletDamage = gun.Damage / gun.Pellets
	local pad = gun.HitRadius + LAG_PAD
	local pierce = gun.Pierce or 0
	local damage = {}
	GunsCore.PelletDirections(direction, seed, gun.SpreadDeg, pellets, directions)
	for pellet = 1, pellets do
		local unit = directions[pellet]
		local index, distance = GunsCore.CastBodies(bodies, EYE, unit, gun.Range, pad, -1)
		local piercesLeft = pierce
		while index > 0 do
			local body = crowd[index]
			local isHead = EYE.Y + unit.Y * distance >= body.aim.y * GunsCore.Tune.HEAD_FRACTION
			local figure = if isHead then pelletDamage * GunsCore.Tune.HEADSHOT_MULTIPLIER else pelletDamage
			damage[body] = (damage[body] or 0) + figure
			if piercesLeft == 0 then break end
			piercesLeft -= 1
			index, distance = GunsCore.CastBodies(bodies, EYE, unit, gun.Range, pad, distance)
		end
	end

	return damage, direction
end

local function newBody(enemyData, healthScale, speedScale, x, z)
	local health = enemyData.BaseMaxHealth * healthScale
	return {
		x = x,
		z = z,
		hp = health,
		max = health,
		speed = enemyData.BaseMovementSpeed * speedScale,
		mass = enemyData.Mass,
		aim = EnemiesCore.AimShape(enemyData),
	}
end

local function chestOf(body)
	return Vector3.new(body.x, body.aim.x, body.z)
end

-- Seconds to kill one Basic standing `distance` away in `round`, averaged.
local function timeToKill(gun, round, distance)
	local basic = DataCore.Enemies.ById[1]
	local healthScale = RoundCore.GetScales(round)
	local total, trials = 0, 300
	for trial = 1, trials do
		local body = newBody(basic, healthScale, 1, 0, -distance)
		local crowd = { body }
		local shots = 0
		while body.hp > 0 and shots < 200 do
			shots += 1
			local damage = resolve(gun, crowd, chestOf(body), trial * 977 + shots)
			body.hp -= damage[body] or 0
		end
		total += (shots - 1) * gun.FireInterval
	end

	return total / trials
end

-- Kills a second against `alive` bodies of `round`'s mix, each replaced at the ring when it dies.
local function killRate(gun, round, alive, seed)
	local random = H.Random.new(seed)
	local healthScale, _, speedScale = RoundCore.GetScales(round)
	local pool = {}
	local weight = RoundCore.GetPool(round, DataCore.Enemies.All, pool)
	local function spawn(minRadius)
		local enemyData = RoundCore.Draw(pool, weight, random:NextNumber())
		local radius = random:NextNumber(minRadius, RING_MAX)
		local angle = random:NextNumber(-ARC / 2, ARC / 2)
		return newBody(enemyData, healthScale, speedScale, math.sin(angle) * radius, -math.cos(angle) * radius)
	end

	local crowd = {}
	for index = 1, alive do
		crowd[index] = spawn(12)
	end

	local kills, overkills, shots, nextShotAt = 0, 0, 0, 0
	for step = 1, SECONDS / DT do
		local now = step * DT
		-- Walk in, queueing behind whoever is already in the way.
		for _, body in crowd do
			local distance = math.sqrt(body.x * body.x + body.z * body.z)
			if distance <= REACH then continue end
			local move = math.min(body.speed * DT, distance - REACH)
			local nx, nz = body.x - body.x / distance * move, body.z - body.z / distance * move
			local isBlocked = false
			for _, other in crowd do
				if other == body then continue end
				local dx, dz = other.x - nx, other.z - nz
				if
					dx * dx + dz * dz < SPACING * SPACING
					and other.x * other.x + other.z * other.z < distance * distance
				then
					isBlocked = true
					break
				end
			end
			if not isBlocked then
				body.x, body.z = nx, nz
			end
		end

		if now < nextShotAt then continue end
		nextShotAt = now + gun.FireInterval
		shots += 1

		local target, best = nil, math.huge
		for _, body in crowd do
			local distanceSq = body.x * body.x + body.z * body.z
			if distanceSq < best then
				target, best = body, distanceSq
			end
		end

		local damage, direction = resolve(gun, crowd, chestOf(target), seed * 7919 + shots)
		for index = #crowd, 1, -1 do
			local body = crowd[index]
			local taken = damage[body]
			if not taken then continue end
			body.hp -= taken
			if body.hp <= 0 then
				kills += 1
				if taken >= body.max * OVERKILL_RATIO then
					overkills += 1
				end
				crowd[index] = spawn(RING_MIN)
			elseif gun.Knockback and taken >= gun.Damage * KNOCKBACK_MIN_SHARE then
				local push = gun.Knockback * math.min(taken / gun.Damage, 1) / body.mass
				body.x += direction.X * push
				body.z += direction.Z * push
			end
		end
	end

	return kills / SECONDS, overkills / SECONDS
end

local ladder = {}
for index, step in GunsCore.LADDER do
	ladder[index] = { Label = step.Label, Price = step.Price, Gun = gunOf(step) }
end

print("gun        dmg  x  pellets  every   spread  range  pierce  shove   dps (all hit)")
for _, entry in ladder do
	local gun = entry.Gun
	print(
		string.format(
			"%-9s %5.1f  x  %2d      %.2f s  %4.1f    %3d    %d       %-4s    %.0f",
			entry.Label,
			gun.Damage / gun.Pellets,
			gun.Pellets,
			gun.FireInterval,
			gun.SpreadDeg,
			gun.Range,
			gun.Pierce or 0,
			tostring(gun.Knockback or "-"),
			gun.Damage / gun.FireInterval
		)
	)
end

print("\nseconds to kill one Basic alone (0 = the first shot)")
print("round  studs   " .. (function()
	local names = {}
	for _, entry in ladder do
		names[#names + 1] = string.format("%-8s", entry.Label)
	end
	return table.concat(names, " ")
end)())
for _, round in { 1, 4, 8 } do
	for _, distance in { 8, 20, 35, 50, 70 } do
		local cells = {}
		for _, entry in ladder do
			cells[#cells + 1] = string.format("%-8.2f", timeToKill(entry.Gun, round, distance))
		end
		print(string.format("%-6d %-7d %s", round, distance, table.concat(cells, " ")))
	end
end

print("\nkills a second against the round's mix (overkills a second), and the step up from the gun before")
for _, round in { 1, 4, 8, 12 } do
	for _, alive in { 6, 20, 45 } do
		local cells = {}
		local previous = nil
		for _, entry in ladder do
			local kills, overkills = 0, 0
			for seed = 1, SEEDS do
				local k, o = killRate(entry.Gun, round, alive, seed)
				kills += k / SEEDS
				overkills += o / SEEDS
			end
			local stepUp = if previous then string.format("x%.2f", kills / previous) else "     "
			cells[#cells + 1] = string.format("%-8s %4.2f (%4.2f) %s", entry.Label, kills, overkills, stepUp)
			previous = kills
		end
		print(string.format("round %-2d alive %-2d | %s", round, alive, table.concat(cells, " | ")))
	end
end
