-- SpatialHash's shape-aware queries against brute force, with crowds, large boxes and circles, adds and removes.
return function(Context)
	local SpatialHash = require(game:GetService("ReplicatedStorage").GlobalShared.Utils.SpatialHash)
	local rng = Random.new(5)
	local bad, queries = 0, 0
	for trial = 1, 40 do
		local hash = SpatialHash.new()
		local shapes = {}
		local n = rng:NextInteger(0, 300)
		for e = 1, n do
			local p = vector.create(rng:NextNumber(-80, 80), 0, rng:NextNumber(-80, 80))
			local roll = rng:NextNumber()
			if roll < 0.03 then
				local h = vector.create(rng:NextNumber(3, 12), 6, rng:NextNumber(3, 12))
				hash:AddAABB(e, p, h); shapes[e] = { "box", p, h }
			elseif roll < 0.05 then
				local r = rng:NextNumber(3, 10)
				hash:AddCircle(e, p, r); shapes[e] = { "circle", p, r }
			elseif roll < 0.1 then
				hash:AddPoint(e, p); shapes[e] = { "point", p }
			else
				local h = vector.create(rng:NextNumber(0.5, 1.75), 2, rng:NextNumber(0.5, 1.75))
				hash:AddAABB(e, p, h); shapes[e] = { "box", p, h }
			end
		end
		-- remove a few, move a few
		for e = 1, n do
			if shapes[e] and rng:NextNumber() < 0.1 then hash:Remove(e); shapes[e] = nil
			elseif shapes[e] and rng:NextNumber() < 0.2 then
				local p = vector.create(rng:NextNumber(-80, 80), 0, rng:NextNumber(-80, 80))
				hash:Update(e, p); shapes[e][2] = p
			end
		end
		for q = 1, 60 do
			queries += 1
			local cx, cz = rng:NextNumber(-90, 90), rng:NextNumber(-90, 90)
			local useRadius = q % 2 == 0
			local r = rng:NextNumber(0.5, 30)
			local minX, minZ, maxX, maxZ = cx - r, cz - r * 0.6, cx + r * 0.7, cz + r
			local got = {}
			if useRadius then hash:QueryRadius(cx, cz, r, function(e) got[e] = (got[e] or 0) + 1 end)
			else hash:QueryAABB(minX, minZ, maxX, maxZ, function(e) got[e] = (got[e] or 0) + 1 end) end
			for e, s in shapes do
				local p = s[2]
				local hit
				if s[1] == "point" then
					hit = if useRadius then (p.x - cx) ^ 2 + (p.z - cz) ^ 2 <= r * r else p.x >= minX and p.x <= maxX and p.z >= minZ and p.z <= maxZ
				elseif s[1] == "circle" then
					local qx = math.clamp(p.x, if useRadius then cx else minX, if useRadius then cx else maxX)
					local qz = math.clamp(p.z, if useRadius then cz else minZ, if useRadius then cz else maxZ)
					local d = math.sqrt((p.x - qx) ^ 2 + (p.z - qz) ^ 2)
					hit = if useRadius then d <= s[3] + r else d * d <= s[3] * s[3]
				else
					local h = s[3]
					if useRadius then
						local dx = math.max(0, math.abs(cx - p.x) - h.x)
						local dz = math.max(0, math.abs(cz - p.z) - h.z)
						hit = dx * dx + dz * dz <= r * r
					else
						hit = not (p.x + h.x < minX or p.x - h.x > maxX or p.z + h.z < minZ or p.z - h.z > maxZ)
					end
				end
				local c = got[e] or 0
				-- borderline float ties ignored
				if (hit and c ~= 1) or (not hit and c ~= 0) then bad += 1; if bad < 6 then print("mismatch", trial, q, e, s[1], hit, c) end end
				got[e] = nil
			end
			for e in got do bad += 1; if bad < 6 then print("stray", e) end end
		end
	end
	print(string.format("queries %d, mismatches %d", queries, bad))
	print("@done")
end
