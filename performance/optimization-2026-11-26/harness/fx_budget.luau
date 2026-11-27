-- A heavy fight's bursts through fxBudget at each tier against a raw Emit: particles drawn a second, and the cost.
return function(Context)
	local RS = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")
	local GQ = require(RS.Fx.GlobalClient.Controllers.GraphicsQualityController)
	local fxBudget = require(RS.Fx.GlobalClient.Utils.fxBudget)
	local camera = workspace.CurrentCamera
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 40, 50), Vector3.zero)
	camera.Focus = CFrame.new(0, 0, 0)
	local emitted = 0
	local fake = { Emit = function(_, n) emitted += n end, Parent = nil }
	local rng = Random.new(4)
	local points = {}
	for i = 1, 3000 do
		local roll = rng:NextNumber()
		local d = if roll < 0.6 then rng:NextNumber(0, 60) elseif roll < 0.85 then rng:NextNumber(60, 150) else rng:NextNumber(150, 300)
		local a = rng:NextNumber(0, math.pi * 2)
		points[i] = Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
	end
	local tiers = { "raw", "HIGH", "MEDIUM", "LOW" }
	local values = { raw = 0, HIGH = GQ.HIGH, MEDIUM = GQ.MEDIUM, LOW = GQ.LOW }
	for _, name in tiers do
		if name ~= "raw" then GQ.Tier = function() return values[name] end end
		emitted = 0
		local work = 0
		-- 10 s at 60 fps: 5 bursts a frame
		for f = 1, 600 do
			local w0 = Context.WorkSeconds()
			for b = 1, 5 do
				local at = points[(f * 5 + b) % 3000 + 1]
				if name == "raw" then fake:Emit(10) else fxBudget.Emit(fake :: any, 10, at) end
			end
			work += Context.WorkSeconds() - w0
			RunService.Heartbeat:Wait()
		end
		print(string.format("%-6s %6.0f particles/s emitted, %.2f us a burst", name, emitted / 10, work / 3000 * 1e6))
	end
	print("@done")
end
