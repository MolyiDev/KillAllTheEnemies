-- TelegraphCore.Footprint now vs the HEAD copy (stood in as TelegraphCoreBefore): same node sets and floor, and cost.
return function(Context)
	local RS = game:GetService("ReplicatedStorage")
	local ArenaCore = require(RS.Shared.Core.ArenaCore)
	local Now = require(RS.Shared.Core.TelegraphCore)
	local holder = Instance.new("ModuleScript"); holder.Name = "TelegraphCoreBefore"; holder.Parent = RS.Shared.Core
	Context.StandIn(holder, Context.Before)
	local Before = require(holder)
	local ETelegraphs = require(RS.Types.Enums.ETelegraphs)
	local W, D, CELL = 210, 200, 2
	local floors = {}
	for z = 0, D - 1 do
		for x = 0, W - 1 do
			local col = { 0 }
			if x > 60 and x < 110 and z > 60 and z < 100 then col = { 8, 0 } end
			if x >= 100 and x < 104 and z >= 50 and z <= 60 then col = { (z - 50) * 0.8 } end
			if z % 40 == 20 and x % 50 > 6 then col = { 12 } end
			floors[z * W + x + 1] = col
		end
	end
	local nav = ArenaCore.Build(W, D, CELL, -W, -D, floors)
	local bad, cases = 0, 0
	local tNow, tBefore = 0, 0
	local a, b = {}, {}
	local rng = Random.new(9)
	for i = 1, 300 do
		local kind = ({ ETelegraphs.Circle, ETelegraphs.Ring, ETelegraphs.Line, ETelegraphs.Cone })[i % 4 + 1]
		local size = rng:NextNumber(4, 60)
		local width = if kind == ETelegraphs.Line then rng:NextNumber(3, 15) elseif kind == ETelegraphs.Cone then ({ 60, 90, 120 })[i % 3 + 1] else 0
		local center = vector.create(rng:NextNumber(-200, 200), if i % 5 == 0 then 8 else 0, rng:NextNumber(-200, 200))
		local yaw = rng:NextNumber(-math.pi, math.pi)
		table.clear(a); table.clear(b)
		local w0 = Context.WorkSeconds()
		local fa = Now.Footprint(nav, kind, center, yaw, size, width, a)
		tNow += Context.WorkSeconds() - w0
		w0 = Context.WorkSeconds()
		local fb = Before.Footprint(nav, kind, center, yaw, size, width, b)
		tBefore += Context.WorkSeconds() - w0
		cases += 1
		local same = fa == fb
		for k in a do if not b[k] then same = false end end
		for k in b do if not a[k] then same = false end end
		if not same then bad += 1 end
	end
	print(string.format("%d footprints: %d differ | before %.3f ms, now %.3f ms in all", cases, bad, tBefore * 1000, tNow * 1000))
	print("@done")
end
