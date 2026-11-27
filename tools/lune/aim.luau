-- Headless check of where a shot goes: how many bodies a gun's bullet goes into when the player puts the crosshair on
-- the first body of a crowd, aimed as the crosshair alone sends it (the point it is on, shot from the head) and lined
-- up (GunsCore.LineUp). Scenes on flat ground, on slopes up and down, from a deck over the crowd and from the ground
-- at a crowd up stairs, in a queue and in a loose crowd, with the camera free and locked to the shoulder, and the
-- crosshair from the body's knees to its head. Hits are counted as WeaponService counts them (the gun's HitRadius plus
-- LAG_PAD, the floor in the way). "possible" is the best of a fine sweep of lines from the head into that body: the
-- ceiling a lined-up shot is measured against. "worse" counts shots the line-up made go into fewer bodies (keep 0).
-- Run from the repo root (SEEDS=n for fewer crowds a scene, SCENE=text for only the scenes named so):
--   lune run tools/lune/aim.luau "$PWD" ["Gun Name"]
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local H = require("./harness")(process.args[1])

local Vector3 = roblox.Vector3
local DataCore = H.require("ReplicatedStorage/GlobalShared/Core/DataCore")
local GunsCore = H.require("ReplicatedStorage/GlobalShared/Core/GunsCore")
local EnemiesCore = H.require("ReplicatedStorage/Shared/Core/EnemiesCore")

local LAG_PAD = GunsCore.Tune.LAG_PAD
-- CameraController's SHOULDER_OFFSET; the PlayerModule's default zoom.
local SHOULDER = Vector3.new(3, 0.5, 0)
local ZOOM = 12.5
-- An R6 body's root over its feet.
local ROOT_HEIGHT = 3
local MARCH = 0.2
-- Every scene is within this of the head: past it a ray is clear.
local REACH = 80
local SEEDS = tonumber(process.env.SEEDS) or 40

local gunName = process.args[2] or "AWP The Prince"
local gun
for _, candidate in DataCore.Guns.All do
	if candidate.Name == gunName then gun = candidate end
end
assert(gun, "no gun named " .. gunName)

local kinds = {}
for _, enemyData in DataCore.Enemies.All do
	if not enemyData.Boss then kinds[#kinds + 1] = EnemiesCore.AimShape(enemyData) end
end

-- The floor under (x, z) in a scene: the player faces -z.
local function flat()
	return 0
end
local function slopeUp(_, z)
	return if z < -8 then (-z - 8) * 0.27 else 0
end
local function slopeDown(_, z)
	return if z < -8 then (z + 8) * 0.27 else 0
end
local function deck(_, z)
	return if z > -4 then 8 else 0
end
local function stairsUp(_, z)
	return if z < -14 then 7 else math.max(0, (-z - 6) / 8 * 7)
end

-- How far along `vector` from `origin` the ray stays over the floor (sightCast's length).
local function wallOf(floor)
	return function(origin, vector)
		local length = vector.Magnitude
		local unit = vector.Unit
		local t = 0
		while t < math.min(length, REACH) do
			local point = origin + unit * t
			if point.Y < floor(point.X, point.Z) then return t end
			t += MARCH
		end
		return length
	end
end

-- A queue straight out from the player, or a loose crowd, each body on its floor.
local function placeQueue(random, floor)
	local crowd = {}
	local z = -random:NextNumber(14, 22)
	for _ = 1, 9 do
		local aim = kinds[random:NextInteger(1, #kinds)]
		local x = random:NextNumber(-0.9, 0.9)
		crowd[#crowd + 1] = { feet = Vector3.new(x, floor(x, z), z), aim = aim }
		z -= aim.z * 2 + random:NextNumber(0.6, 2.5)
	end
	return crowd
end
local function placeCrowd(random, floor)
	local crowd = {}
	for _ = 1, 24 do
		local aim = kinds[random:NextInteger(1, #kinds)]
		local x, z = random:NextNumber(-6, 6), -random:NextNumber(14, 60)
		local isClear = true
		for _, other in crowd do
			local dx, dz = other.feet.X - x, other.feet.Z - z
			if dx * dx + dz * dz < (other.aim.z + aim.z) ^ 2 then isClear = false end
		end
		if isClear then crowd[#crowd + 1] = { feet = Vector3.new(x, floor(x, z), z), aim = aim } end
	end
	return crowd
end

local function gather(crowd, bodies, owners)
	bodies.Count = 0
	for index, body in crowd do
		GunsCore.AddBody(bodies, body.feet, body.aim.z, body.aim.y)
		owners[index] = index
	end
end

-- The camera's eye framing `point` on the crosshair, from the head (the PlayerModule's focus), free or shouldered.
local function cameraEye(head, point, isLocked)
	local look = (point - head).Unit
	local eye = head
	for _ = 1, 30 do
		local right = look:Cross(Vector3.yAxis).Unit
		local up = right:Cross(look)
		local focusEye = head - look * ZOOM
		eye = if isLocked then focusEye + right * SHOULDER.X + up * SHOULDER.Y else focusEye
		look = (point - eye).Unit
	end
	return eye, look
end

local bodies = GunsCore.NewBodies()
local owners = {}
local hitIndices, hitDistances = {}, {}

-- The bodies the server's bullet from `head` through `aimPoint` goes into.
local function serverHits(head, aimPoint, wall)
	local unit = (aimPoint - head).Unit
	local length = wall(head, unit * gun.Range)
	local hits = GunsCore.CastBodiesAll(bodies, head, unit, length, gun.HitRadius + LAG_PAD, hitIndices, hitDistances)
	return math.min(hits, (gun.Pierce or 0) + 1)
end

-- The best any line from the head into `body` does.
local function bestHits(head, body, wall)
	local best = 0
	for u = 0, 8 do
		for v = 0, 14 do
			local x = body.feet.X + (u / 4 - 1) * body.aim.z * 0.9
			local point = Vector3.new(x, body.feet.Y + body.aim.y * v / 14, body.feet.Z)
			best = math.max(best, serverHits(head, point, wall))
		end
	end
	return best
end

local scenes = {
	{ "flat, queue", flat, placeQueue, 0 },
	{ "flat, crowd", flat, placeCrowd, 0 },
	{ "slope up, queue", slopeUp, placeQueue, 0 },
	{ "slope up, crowd", slopeUp, placeCrowd, 0 },
	{ "slope down, queue", slopeDown, placeQueue, 0 },
	{ "slope down, crowd", slopeDown, placeCrowd, 0 },
	{ "from a deck, queue", deck, placeQueue, 8 },
	{ "from a deck, crowd", deck, placeCrowd, 8 },
	{ "up stairs, queue", stairsUp, placeQueue, 0 },
	{ "up stairs, crowd", stairsUp, placeCrowd, 0 },
}
local SHARES = { 0.25, 0.45, 0.65, 0.85 }

-- One scene seen through one camera: the averages of possible, aimed and lined-up hits, and the shots made worse.
-- `bests` keeps each crowd's ceiling across the cameras.
local function measure(scene, isLocked, bests)
	local _, floor, place, standY = table.unpack(scene)
	local wall = wallOf(floor)
	local head = Vector3.new(0, standY + ROOT_HEIGHT + GunsCore.Tune.EYE_HEIGHT, 0)
	local shot = {
		Bodies = bodies,
		Owners = owners,
		Origin = head,
		Pierce = gun.Pierce or 0,
		Range = gun.Range,
		Pad = gun.HitRadius + LAG_PAD,
		CastWall = wall,
	}

	local aimedSum, linedSum, bestSum, worse, trials = 0, 0, 0, 0, 0
	for seed = 1, SEEDS do
		local crowd = place(H.Random.new(seed), floor)
		gather(crowd, bodies, owners)
		-- The first body of the crowd the player sees: the nearest.
		local first, firstDistance = 0, math.huge
		for index, body in crowd do
			local distance = (body.feet - head).Magnitude
			if distance < firstDistance then
				first, firstDistance = index, distance
			end
		end
		local body = crowd[first]
		bests[seed] = bests[seed] or bestHits(head, body, wall)

		for _, share in SHARES do
			local mark = body.feet + Vector3.yAxis * body.aim.y * share
			local eye, look = cameraEye(head, mark, isLocked)
			-- Where the crosshair's ray first goes into a body (WeaponController's findAim).
			local index, distance = GunsCore.CastBodies(bodies, eye, look, 1000, 0, -1)
			if index == 0 then continue end
			shot.Target = eye + look * distance
			shot.Body = index
			local aimed = serverHits(head, shot.Target, wall)
			local lined = serverHits(head, GunsCore.LineUp(shot), wall)
			aimedSum += aimed
			linedSum += lined
			bestSum += bests[seed]
			trials += 1
			if lined < aimed then
				worse += 1
			end
		end
	end

	return bestSum / trials, aimedSum / trials, linedSum / trials, worse
end

print(string.format("%s: pierce %d, HitRadius %.2f", gun.Name, gun.Pierce or 0, gun.HitRadius))
print(string.format("%-20s %-8s %8s %8s %8s %8s", "scene", "camera", "possible", "aimed", "lined up", "worse"))
for _, scene in scenes do
	local name = scene[1]
	if process.env.SCENE and not string.find(name, process.env.SCENE, 1, true) then continue end
	local bests = {}
	for _, isLocked in { false, true } do
		local best, aimed, lined, worse = measure(scene, isLocked, bests)
		local camera = if isLocked then "shoulder" else "free"
		print(string.format("%-20s %-8s %8.2f %8.2f %8.2f %8d", name, camera, best, aimed, lined, worse))
	end
end
