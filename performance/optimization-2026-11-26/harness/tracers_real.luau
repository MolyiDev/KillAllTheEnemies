-- The real tracers module: 4 SMG-like players' worth of sparks (14 a shot, ~13 shots/s each), stepped per frame.
return function(Context)
	local RS = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")
	if Context.Before then Context.StandIn(RS.Fx.GlobalClient.Utils.tracers, Context.Before) end
	local tracers = require(RS.Fx.GlobalClient.Utils.tracers)
	local folder = Instance.new("Folder"); folder.Parent = workspace
	tracers.Init(folder)
	local frame = 0
	local alive = 0
	local t0
	RunService.PreRender:Connect(function()
		frame += 1
		if frame % 5 == 0 then
			for p = 1, 4 do
				tracers.Sparks(CFrame.new(p * 10, 5, 0) * CFrame.Angles(0, p, 0), false)
				tracers.Fire(Vector3.new(p * 10, 5, 0), Vector3.new(p * 10, 5, -200), false)
			end
		end
		if frame == 60 then t0 = Context.WorkSeconds(); Context.ProfilePhase("steady") end
		tracers.Step()
		if frame == 360 then
			print(string.format("%s: %.4f ms/frame (spark/tracer step+fire)", Context.Label or "?", (Context.WorkSeconds() - t0) * 1000 / 300))
			print("@done")
		end
	end)
end
