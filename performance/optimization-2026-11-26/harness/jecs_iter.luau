return function(Context)
	local RS = game:GetService("ReplicatedStorage")
	local jecs = require(RS.Packages.jecs)
	local Components = require(RS.GlobalShared.ECS.Components)
	local Tags = require(RS.GlobalShared.ECS.Tags)
	local W = require(RS.GlobalShared.ECS.Worlds.EnemyWorld)
	for i = 1, 255 do
		local e = W:entity()
		W:set(e, Components.CFrame, CFrame.new(i, 0, 0)); W:set(e, Components.Bone, i); W:set(e, Components.InstanceId, i)
		W:set(e, Components.Data, { Id = i % 7 }); W:set(e, Components.Model, i); W:add(e, Tags.Enemy)
	end
	local Q = W:query(Components.CFrame, Components.Bone, Components.InstanceId, Components.Data):with(Tags.Enemy):cached()
	local N = 200
	local move = CFrame.new(0, 0.01, 0)
	local t0 = Context.WorkSeconds()
	for _ = 1, N do
		for entity, cf, bone, id, data in Q do
			W:set(entity, Components.CFrame, cf * move)
		end
	end
	local a = (Context.WorkSeconds() - t0) / N * 1e6
	t0 = Context.WorkSeconds()
	for _ = 1, N do
		for _, archetype in Q:archetypes() do
			local columns = archetype.columns_map
			local cfs, bones, ids, datas = columns[Components.CFrame], columns[Components.Bone], columns[Components.InstanceId], columns[Components.Data]
			local entities = archetype.entities
			for row = #entities, 1, -1 do
				local cf, bone, id, data = cfs[row], bones[row], ids[row], datas[row]
				cfs[row] = cf * move
			end
		end
	end
	local b = (Context.WorkSeconds() - t0) / N * 1e6
	print(string.format("255 bodies: query+set %.1f us/frame, columns %.1f us/frame", a, b))
	print("@done")
end
