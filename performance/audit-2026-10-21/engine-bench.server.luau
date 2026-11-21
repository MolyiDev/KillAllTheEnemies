--!native
-- Temporary, read-only Ballarc hot-path benchmark. No live ECS or gameplay mutations.
local R = game:GetService("ReplicatedStorage")
local H = game:GetService("HttpService")
local S = require(R.GlobalShared.Utils.SpatialHash)
local counts = { 1500, 5000 }
local results = {}
local checksum = 0
local function measure(name, n, fn)
	for _ = 1, 3 do fn() end
	local samples = table.create(21)
	for rep = 1, 21 do
		local t = os.clock()
		for _ = 1, 3 do fn() end
		samples[rep] = (os.clock() - t) * 1000 / 3
		task.wait()
	end
	table.sort(samples)
	local row = { name = name, n = n, medianMs = samples[11], p95Ms = samples[20], minMs = samples[1] }
	results[#results + 1] = row
	print("[BALLARC_AUDIT] " .. H:JSONEncode(row))
end
local function reuseRecords(buf, out)
	local off = 2
	for _ = 1, buffer.readu16(buf, 0) do
		local id = buffer.readu16(buf, off)
		local rec = out[id]
		if not rec then rec = {}; out[id] = rec end
		rec.x = buffer.readf32(buf, off + 2)
		rec.z = buffer.readf32(buf, off + 6)
		rec.y = buffer.readf32(buf, off + 10)
		rec.shape = buffer.readu8(buf, off + 14)
		if rec.shape == 2 then
			rec.halfx = buffer.readu16(buf, off + 15) * 0.05
			rec.halfy = buffer.readu16(buf, off + 17) * 0.05
			rec.halfz = buffer.readu16(buf, off + 19) * 0.05
			off += 21
		elseif rec.shape == 1 then
			rec.radius = buffer.readu16(buf, off + 15) * 0.05
			off += 17
		else off += 15 end
	end
end
local function reuseBuckets(buf, out)
	local off = 2
	for _ = 1, buffer.readu16(buf, 0) do
		local key = buffer.readu32(buf, off)
		local count = buffer.readu16(buf, off + 4)
		local arr = out[key]
		if arr then table.clear(arr) else arr = table.create(count); out[key] = arr end
		off += 6
		for i = 1, count do arr[i] = buffer.readu16(buf, off); off += 2 end
	end
end
task.wait(5)
print("[BALLARC_AUDIT] " .. H:JSONEncode({phase="begin", placeId=game.PlaceId, mode="Studio server F8", hashSource="identical in Ballarc and BeACastleLord", reusingDecoder="stable population prototype; lifecycle cleanup excluded"}))
do
	local test = S.new(5)
	test:AddAABB(1, vector.create(1, 0, 1), vector.create(1, 2, 1))
	test:Update(1, vector.create(6, 3, 1))
	local crossing = { x = test.Records[1].x, y = test.Records[1].y, z = test.Records[1].z }
	test:Update(1, vector.create(6, 3, 1))
	print("[BALLARC_AUDIT] " .. H:JSONEncode({phase="cross-cell Update reproduction", requestedX=6, afterCrossing=crossing, afterSecondUpdateX=test.Records[1].x}))
	local edge = S.new(5)
	edge:AddAABB(1, vector.create(5.1, 0, 1), vector.create(1, 2, 1))
	local found = 0
	edge:QueryRadius(4, 1, 0.2, function() found += 1 end)
	print("[BALLARC_AUDIT] " .. H:JSONEncode({phase="center-bucket extent reproduction", geometricallyOverlaps=true, returned=found, boxCenterX=5.1, boxHalfX=1, queryCenterX=4, queryRadius=0.2}))
end
for _, n in counts do
	local hash = S.new(5)
	local width = math.ceil(math.sqrt(n))
	for i = 1, n do
		local x = ((i - 1) % width) * 3
		local z = math.floor((i - 1) / width) * 3
		hash:AddAABB(i, vector.create(x, 0, z), vector.create(1, 2, 1))
	end
	local records = S.PackRecords(hash.Records)
	local buckets = S.PackBuckets(hash.FineBuckets)
	local bucketCount = buffer.readu16(buckets, 0)
	print("[BALLARC_AUDIT] " .. H:JSONEncode({phase="layout", n=n, recordBytes=buffer.len(records), bucketBytes=buffer.len(buckets), buckets=bucketCount}))
	measure("pack spatial snapshot", n, function()
		checksum += buffer.len(S.PackRecords(hash.Records)) + buffer.len(S.PackBuckets(hash.FineBuckets))
	end)
	local oldRecords, oldBuckets = {}, {}
	measure("current worker full decode", n, function()
		table.clear(oldRecords); table.clear(oldBuckets)
		S.UnpackRecordsInto(records, oldRecords); S.UnpackBucketsInto(buckets, oldBuckets)
		checksum += oldRecords[n].x
	end)
	local reusedRecords, reusedBuckets = {}, {}
	measure("persistent worker decode prototype", n, function()
		reuseRecords(records, reusedRecords); reuseBuckets(buckets, reusedBuckets)
		checksum += reusedRecords[n].x
	end)
	for i = 1, n do
		local a, b = oldRecords[i], reusedRecords[i]
		assert(a.x == b.x and a.y == b.y and a.z == b.z and a.shape == b.shape and a.halfx == b.halfx and a.halfy == b.halfy and a.halfz == b.halfz)
	end
	for key, arr in oldBuckets do
		assert(#arr == #reusedBuckets[key])
		for i, id in arr do assert(reusedBuckets[key][i] == id) end
	end
	local pairsCurrent, pairsReuse = {}, {}
	for rep = 1, 31 do
		local function current()
			local t = os.clock()
			for _ = 1, 8 do
				table.clear(oldRecords); table.clear(oldBuckets)
				S.UnpackRecordsInto(records, oldRecords); S.UnpackBucketsInto(buckets, oldBuckets)
			end
			pairsCurrent[#pairsCurrent+1] = (os.clock()-t)*1000/8
		end
		local function reuse()
			local t = os.clock()
			for _ = 1, 8 do reuseRecords(records, reusedRecords); reuseBuckets(buckets, reusedBuckets) end
			pairsReuse[#pairsReuse+1] = (os.clock()-t)*1000/8
		end
		if rep % 2 == 1 then current(); reuse() else reuse(); current() end
		task.wait()
	end
	table.sort(pairsCurrent); table.sort(pairsReuse)
	print("[BALLARC_AUDIT] " .. H:JSONEncode({phase="alternating decoder comparison", n=n, currentMedianMs=pairsCurrent[16], reusedMedianMs=pairsReuse[16], speedup=pairsCurrent[16]/pairsReuse[16], currentP95Ms=pairsCurrent[30], reusedP95Ms=pairsReuse[30]}))
	measure("16 current worker decodes serial equivalent", n, function()
		for _ = 1, 16 do
			table.clear(oldRecords); table.clear(oldBuckets)
			S.UnpackRecordsInto(records, oldRecords); S.UnpackBucketsInto(buckets, oldBuckets)
		end
		checksum += oldRecords[n].x
	end)
	local hits = 0
	local function hit() hits += 1 end
	measure("200 ordinary radius queries", n, function()
		hits = 0
		for i = 1, 200 do
			local p = hash.Records[((i * 7) % n) + 1]
			S.QueryRadius(p.x, p.z, 2, 5, hit, hash.FineBuckets, hash.Records)
		end
		checksum += hits
	end)
	local ordinaryHits = hits
	hash = S.new(5)
	for i = 1, n do hash:AddAABB(i, vector.create(1, 0, 1), vector.create(1, 2, 1)) end
	measure("200 fully crowded radius queries", n, function()
		hits = 0
		for _ = 1, 200 do S.QueryRadius(1, 1, 2, 5, hit, hash.FineBuckets, hash.Records) end
		checksum += hits
	end)
	print("[BALLARC_AUDIT] " .. H:JSONEncode({phase="query counts", n=n, ordinaryCandidates=ordinaryHits, crowdedCandidates=hits}))
end
print("[BALLARC_AUDIT] " .. H:JSONEncode({phase="done", checksum=checksum, results=results}))
