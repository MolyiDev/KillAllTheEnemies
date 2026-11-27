-- WeaponService.gatherBodies + its pellet casts, old (box only) vs new (box, then a flat tube on Position), on 255 real
-- enemies standing round the shooter, through the real ECS, hash, EnemiesCore and GunsCore.
return function(Context)
	local RS = game:GetService("ReplicatedStorage")
	local jecs = require(RS.Packages.jecs)
	local Components = require(RS.GlobalShared.ECS.Components)
	local Tags = require(RS.GlobalShared.ECS.Tags)
	local EnemyWorld = require(RS.GlobalShared.ECS.Worlds.EnemyWorld)
	local EnemiesCore = require(RS.Shared.Core.EnemiesCore)
	local GunsCore = require(RS.GlobalShared.Core.GunsCore)
	local DataCore = require(RS.GlobalShared.Core.DataCore)
	local Hash = EnemiesCore.EnemiesSpatialHash
	local roster = {}
	for _, e in DataCore.Enemies.All do if not e.IsBoss and not e.AimPieces then table.insert(roster, e) end end
	local rng = Random.new(3)
	for i = 1, 255 do
		local data = roster[(i % #roster) + 1]
		local a, r = rng:NextNumber(0, math.pi * 2), rng:NextNumber(8, 70)
		local pos = vector.create(math.cos(a) * r, 0, math.sin(a) * r)
		local e = EnemyWorld:entity()
		EnemyWorld:set(e, Components.Position, pos); EnemyWorld:set(e, Components.Data, data); EnemyWorld:add(e, Tags.Enemy)
		local cs = data.CollisionSize
		Hash:AddAABB(e, pos, vector.create(cs.X / 2, cs.Y / 2, cs.Z / 2))
	end
	local MAX_BODY_RADIUS, LAG_PAD = 4, 0.75
	local bodies = GunsCore.NewBodies()
	local bodyEntities = {}
	local cands = {}
	local ci, cd = {}, {}
	local function collect(e) cands[#cands + 1] = e end
	local function gather(origin, direction, range, spreadDeg, pad, isNew)
		local finish = origin + direction * range
		local reach = range * math.tan(math.rad(spreadDeg))
		local margin = reach + MAX_BODY_RADIUS
		table.clear(cands)
		Hash:QueryAABBAsPoints(math.min(origin.X, finish.X) - margin, math.min(origin.Z, finish.Z) - margin,
			math.max(origin.X, finish.X) + margin, math.max(origin.Z, finish.Z) + margin, collect)
		bodies.Count = 0
		local ox, oz = origin.X, origin.Z
		local dx, dz = finish.X - ox, finish.Z - oz
		local lengthSq = dx * dx + dz * dz
		local tube = reach + MAX_BODY_RADIUS + pad
		local tubeSq = tube * tube
		for _, e in cands do
			local position = EnemyWorld:get(e, Components.Position)
			if not position then continue end
			if isNew then
				local px, pz = position.x - ox, position.z - oz
				local t = if lengthSq > 0 then math.clamp((px * dx + pz * dz) / lengthSq, 0, 1) else 0
				local qx, qz = px - dx * t, pz - dz * t
				if qx * qx + qz * qz > tubeSq then continue end
			end
			local data = EnemyWorld:get(e, Components.Data)
			if not data or data.AimPieces then continue end
			local aim = EnemiesCore.AimShape(data)
			GunsCore.AddBody(bodies, position :: any, aim.z, aim.y)
			bodyEntities[bodies.Count] = e
		end
	end
	local guns = {
		{ name = "smg", range = 300, spread = 3, pellets = 1, pad = 0.45 + LAG_PAD, pierce = 0 },
		{ name = "shotgun", range = 120, spread = 9, pellets = 8, pad = 1.0 + LAG_PAD, pierce = 4 },
		{ name = "sniper", range = 500, spread = 0, pellets = 1, pad = 0.3 + LAG_PAD, pierce = 10 },
	}
	local dirs = {}
	for k = 1, 400 do
		local a = k * 2.399
		dirs[k] = Vector3.new(math.cos(a), (k % 7 - 3) * 0.03, math.sin(a)).Unit
	end
	for _, gun in guns do
		local res = {}
		for pass = 1, 3 do
			local isNew = pass >= 2
			local isAll = pass == 3
			local hits = {}
			local w0 = Context.WorkSeconds()
			local pelletDirs = {}
			for k, dir in dirs do
				local origin = Vector3.new(0, 4.5, 0)
				gather(origin, dir, gun.range, gun.spread, gun.pad, isNew)
				GunsCore.PelletDirections(dir, k, gun.spread, gun.pellets, pelletDirs)
				for p = 1, gun.pellets do
					local unit = pelletDirs[p]
					if isAll then
						local n = GunsCore.CastBodiesAll(bodies, origin, unit, gun.range, gun.pad, ci, cd)
						local left = gun.pierce
						for h = 1, n do
							hits[#hits + 1] = k * 1e6 + p * 1e4 + tonumber(tostring(bodyEntities[ci[h]]):match("%d+"))
							if left == 0 then break end
							left -= 1
						end
					else
					local index, distance = GunsCore.CastBodies(bodies, origin, unit, gun.range, gun.pad, -1)
					local left = gun.pierce
					while index > 0 do
						hits[#hits + 1] = k * 1e6 + p * 1e4 + tonumber(tostring(bodyEntities[index]):match("%d+"))
						if left == 0 then break end
						left -= 1
						index, distance = GunsCore.CastBodies(bodies, origin, unit, gun.range, gun.pad, distance)
					end
					end
				end
			end
			local us = (Context.WorkSeconds() - w0) / #dirs * 1e6
			table.sort(hits)
			res[pass] = { us = us, hits = table.concat(hits, ","), n = #hits }
		end
		print(string.format("%s: old %.1f, tube %.1f, tube+single-pass %.1f us/shot | hits %d/%d/%d identical %s", gun.name, res[1].us, res[2].us, res[3].us, res[1].n, res[2].n, res[3].n, tostring(res[1].hits == res[2].hits and res[2].hits == res[3].hits)))
	end
	print("@done")
end
