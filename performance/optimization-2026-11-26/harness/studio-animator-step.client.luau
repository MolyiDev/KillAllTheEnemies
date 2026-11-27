-- PERF_PROBE (throwaway, never in src): the Animator step (PreAnimation -> PreSimulation), frame time and how many
-- enemy tracks play, in 3 windows of 300 frames once the crowd is in.
local RS = game:GetService("RunService")
local H = game:GetService("HttpService")
local function log(t) warn("[PERF_PROBE] " .. H:JSONEncode(t)) end
local enemies = workspace:WaitForChild("Enemies", 120)
while #enemies:GetChildren() < 60 do task.wait(0.25) end
task.wait(3)
local animAt = 0
local steps, dts = {}, {}
local n = 0
local capturing = false
RS.PreAnimation:Connect(function() animAt = os.clock() end)
RS.PreSimulation:Connect(function()
	if capturing then n += 1; steps[n] = (os.clock() - animAt) * 1000 end
end)
RS.PreRender:Connect(function(dt) if capturing then dts[#dts + 1] = dt * 1000 end end)
local function countPlaying()
	local tracks, bodies, playingBodies = 0, 0, 0
	for _, model in enemies:GetChildren() do
		local ac = model:FindFirstChild("AnimationController")
		local animator = ac and ac:FindFirstChildOfClass("Animator")
		if animator then
			bodies += 1
			local k = #animator:GetPlayingAnimationTracks()
			tracks += k
			if k > 0 then playingBodies += 1 end
		end
	end
	return tracks, bodies, playingBodies
end
for w = 1, 3 do
	table.clear(steps); table.clear(dts); n = 0
	capturing = true
	while n < 300 do task.wait() end
	capturing = false
	table.sort(steps); table.sort(dts)
	local tracks, bodies, playingBodies = countPlaying()
	log({ window = w, animStepMedianMs = steps[150], animStepP90Ms = steps[270], frameMedianMs = dts[math.floor(#dts / 2)], frameP90Ms = dts[math.floor(#dts * 0.9)], bodies = bodies, playingBodies = playingBodies, playingTracks = tracks, label = "__LABEL__" })
	task.wait(1)
end
