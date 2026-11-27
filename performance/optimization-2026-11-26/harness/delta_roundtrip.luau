-- EnemyPacker's delta stream, server to client, 6,000 ticks: every decoded position must equal what the server
-- quantized, through tiers, forgetting (sentAt cleared), recycled ids, big jumps and the u16 wrap.
return function(Context)
	local RS = game:GetService("ReplicatedStorage")
	local P = require(RS.Shared.Packers.EnemyPacker)
	local rng = Random.new(11)
	local N = 255
	local ids, pos, yaws, views, every = {}, {}, {}, {}, {}
	for i = 1, N do
		ids[i] = i * 3 + 100
		-- some bodies near the u16 wrap at +-1638.4 studs
		local wrap = i % 17 == 0
		pos[i] = vector.create(if wrap then 1637 else rng:NextNumber(-200, 200), rng:NextNumber(0, 20), rng:NextNumber(-200, 200))
		yaws[i] = rng:NextNumber(-math.pi, math.pi)
		views[i] = vector.create(2, 3, 0)
		every[i] = i % 50 == 0
	end
	local sentAt, sentQ = {}, P.CreateBaseline()
	local netBase = P.CreateBaseline()
	local cPos, cYaw, cMoving, cLast = {}, {}, {}, {}
	local bad, records, bytes, absolute = 0, 0, 0, 0
	local function q(v) return (math.floor(v * 20 + 0.5) % 65536) end
	for t = 1, 6000 do
		for i = 1, N do
			local p = pos[i]
			local step = if rng:NextNumber() < 0.01 then 30 else 1.3
			local nx = p.x + rng:NextNumber(-step, step)
			if nx > 1638 then nx -= 3276.7 end -- crosses the wrap
			pos[i] = vector.create(nx, p.y, p.z + rng:NextNumber(-step, step))
			yaws[i] += rng:NextNumber(-0.3, 0.3)
			-- AOI forgets a body now and then, and an id is recycled for a new body elsewhere
			if rng:NextNumber() < 0.002 then
				sentAt[ids[i]] = nil
				if rng:NextNumber() < 0.5 then pos[i] = vector.create(rng:NextNumber(-200, 200), 0, rng:NextNumber(-200, 200)) end
			end
		end
		table.clear(cLast)
		local pkt = P.PackFiltered(ids, pos, yaws, views, N, 0, 30, 0, 0, 0, 1, -1, 0, 1e12, sentAt, sentQ, every, t * 0.1)
		if pkt then
			bytes += buffer.len(pkt)
			absolute += buffer.readu16(pkt, 0)
			P.UnpackInto(pkt, netBase, cPos, cYaw, cMoving, cLast, t)
			for i = 1, N do
				local id = ids[i]
				if cLast[id] ~= t then continue end
				records += 1
				local p, c = pos[i], cPos[id]
				local sx, sy, sz = q(p.x), q(p.y), q(p.z)
				local cx, cy, cz = q(c.X), q(c.Y), q(c.Z)
				if sx ~= cx or sy ~= cy or sz ~= cz then
					bad += 1
					if bad < 5 then print("mismatch", t, id, p, c) end
				end
			end
		end
	end
	print(string.format("records %d, mismatches %d, absolute %.1f%%, %.0f bytes a tick", records, bad, absolute / records * 100, bytes / 6000))
	print("@done")
end
