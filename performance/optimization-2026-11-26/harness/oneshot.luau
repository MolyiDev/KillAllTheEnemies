return function(Context)
	local RS = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")
	local SoundsCore = require(RS.GlobalShared.Core.SoundsCore)
	local src = Instance.new("Sound"); src.SoundId = "rbxassetid://1"; src.Volume = 0.5; src.RollOffMaxDistance = 120
	RunService.Heartbeat:Wait()
	local N = 2000
	local t0 = Context.WorkSeconds()
	for i = 1, N do SoundsCore.PlayWorldSound(src, Vector3.new(i % 50, 0, 0)) end
	local per = (Context.WorkSeconds() - t0) / N * 1e6
	print(string.format("PlayWorldSound: %.2f us a call (creation side; Ended/Destroy later)", per))
	print("@done")
end
