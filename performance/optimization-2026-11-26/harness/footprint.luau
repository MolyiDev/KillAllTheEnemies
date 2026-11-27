return function(Context)
	local RS = game:GetService("ReplicatedStorage")
	local ArenaCore = require(RS.Shared.Core.ArenaCore)
	local NavService = require(game:GetService("ServerScriptService").Server.Services.NavService)
	local W, D, CELL = 210, 200, 2
	local floors = {}
	for z = 0, D - 1 do
		for x = 0, W - 1 do
			-- ground, with a deck over a fifth of it and some walls
			local col = { 0 }
			if x > 60 and x < 110 and z > 60 and z < 100 then col = { 8, 0 } end
			if z % 40 == 20 and x % 50 > 6 then col = { 12 } end
			floors[z * W + x + 1] = col
		end
	end
	ArenaCore.Nav = ArenaCore.Build(W, D, CELL, -W, -D, floors)
	local nav = ArenaCore.Nav
	NavService.Reset()
	NavService.SetCharacterNode(1, ArenaCore.NodeAt(nav, 0, 0, 0, 0.75))
	local field = NavService.CharacterFields[1]
	NavService.Flood(nav, field)
	local t0 = Context.WorkSeconds()
	for i = 1, 20 do NavService.Flood(nav, field) end
	print(string.format("nodes %d: flood %.2f ms", nav.NodeCount, (Context.WorkSeconds() - t0) * 1000 / 20))
	local TelegraphCore = require(RS.Shared.Core.TelegraphCore)
	local ETelegraphs = require(RS.Types.Enums.ETelegraphs)
	local out = {}
	for _, case in { { "Circle r6", ETelegraphs.Circle, 6, 0 }, { "Circle r20", ETelegraphs.Circle, 20, 0 }, { "Ring r30", ETelegraphs.Ring, 30, 0 }, { "Ring r60", ETelegraphs.Ring, 60, 0 }, { "Line 60x13", ETelegraphs.Line, 60, 13 } } do
		local w0 = Context.WorkSeconds()
		for _ = 1, 20 do table.clear(out); TelegraphCore.Footprint(nav, case[2], vector.create(10, 0, 10), 0.3, case[3], case[4], out) end
		local n = 0; for _ in out do n += 1 end
		print(string.format("footprint %s: %.3f ms, %d nodes", case[1], (Context.WorkSeconds() - w0) * 1000 / 20, n))
	end
	print("@done")
end
