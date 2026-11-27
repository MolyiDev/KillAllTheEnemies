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
	print("@done")
end
