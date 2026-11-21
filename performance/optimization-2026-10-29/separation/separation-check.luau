-- Fix 1 equivalence: Bee separation with the old 18-stud query vs the bounded query must
-- produce the same contributing neighbours and the same push for every Bee.
local S = require("./SpatialHash")
local V = vector.create
math.randomseed(4242)
local SEP = 18
local function separation(hash, entity, rec, queryRadius)
	local sx, sz = 0, 0
	local touched = {}
	local cbRadius = math.max(rec.halfx, rec.halfz) * 2 -- worker radius = full extent
	S.QueryRadius(rec.x, rec.z, queryRadius, hash.CELL_SIZE, function(neighbor)
		if neighbor == entity then return end
		local info = hash.Records[neighbor]
		local dx, dz = rec.x - info.x, rec.z - info.z
		local dist2 = dx * dx + dz * dz
		local neighborRadius = math.max(info.halfx, info.halfz)
		local minDist = cbRadius + neighborRadius
		if dist2 >= minDist * minDist then return end
		local neighborHalfY = math.max(info.halfy, neighborRadius)
		if rec.y >= info.y + neighborHalfY * 2 - 0.5 then return end
		if info.y > rec.y + cbRadius * 2 then return end
		local dist = math.sqrt(dist2)
		if dist <= 0 then return end
		local scale = (minDist - dist) / dist
		sx += scale * dx; sz += scale * dz
		touched[neighbor] = true
	end, hash.FineBuckets, hash.Records)
	return sx, sz, touched
end
local checked, contributing = 0, 0
for trial = 1, 20 do
	local hash = S.new()
	local maxHalf = 0
	local n = 3000
	-- Mixed sizes: Bees ~1.5-2.5 half, Slimes ~1-2, a few big (up to 7) like large enemy types.
	for id = 1, n do
		local hx = if id % 97 == 0 then 4 + math.random() * 3 else 1 + math.random() * 1.5
		local hz = if id % 3 == 0 then hx * (0.5 + math.random()) else hx
		maxHalf = math.max(maxHalf, hx, hz)
		local spread = if trial % 2 == 0 then 60 else 200
		hash:AddAABB(id, V((math.random() - 0.5) * spread, math.random() * 20, (math.random() - 0.5) * spread), V(hx, 1 + math.random() * 2, hz))
	end
	for id = 1, n, 3 do
		local rec = hash.Records[id]
		local radius = math.max(rec.halfx, rec.halfz) * 2
		local ax, az, at = separation(hash, id, rec, SEP)
		local bx, bz, bt = separation(hash, id, rec, math.min(SEP, radius + maxHalf))
		for k in at do assert(bt[k], `trial {trial} id {id}: neighbour {k} lost`) end
		for k in bt do assert(at[k], `trial {trial} id {id}: extra neighbour {k}`) end
		assert(math.abs(ax - bx) < 1e-9 and math.abs(az - bz) < 1e-9, `trial {trial} id {id}: push differs`)
		checked += 1
		for _ in at do contributing += 1 end
	end
end
print(`ok bees={checked} contributingNeighbours={contributing} (identical sets and pushes)`)
