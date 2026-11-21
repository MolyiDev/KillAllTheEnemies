-- BALLARC_BENCH probe (client, ambient story check): injected by run.py, never in src. Never publish.
-- Mounts Stories/Ambient and counts, per side, the frames on which anything in it was written.
local R = game:GetService("ReplicatedStorage")
local RS = game:GetService("RunService")
local H = game:GetService("HttpService")
local P = game:GetService("Players")
task.wait(4)
local function log(v) v.label = "__LABEL__"; print("[BALLARC_BENCH_CLIENT] " .. H:JSONEncode(v)) end
R:WaitForChild("BallarcBenchReady"):FireServer()
task.wait(8)
local playerGui = P.LocalPlayer:WaitForChild("PlayerGui")
local story = require(P.LocalPlayer.PlayerScripts.Client.UI.Stories:WaitForChild("Ambient.story"))
local g = Instance.new("ScreenGui"); g.Name = "AmbientCheck"; g.ResetOnSpawn = false; g.DisplayOrder = 5000; g.Parent = playerGui
local target = Instance.new("Frame"); target.Size = UDim2.fromScale(1, 1); target.Parent = g
local ok, stop = pcall(story.render, { target = target, controls = { Rate = "12 Hz", ["Time scale"] = 1 }, subscribe = function() return function() end end })
log({ phase = "mounted", ok = ok, err = if ok then nil else tostring(stop) })
task.wait(2.5)
local bench = target:FindFirstChild("AmbientBench")
local sides = {}
for _, child in (if bench then bench:GetChildren() else {}) do sides[child.Name] = child end
local dirty, frames = {}, 0
local conns = {}
for name, root in sides do
	dirty[name] = { frames = 0, writes = 0, now = false }
	for _, d in root:GetDescendants() do
		conns[#conns + 1] = d.Changed:Connect(function(prop)
			if string.sub(prop, 1, 8) == "Absolute" then return end
			local s = dirty[name]
			s.writes += 1
			s.now = true
		end)
	end
end
local c = RS.PreRender:Connect(function()
	frames += 1
	for _, s in dirty do
		if s.now then s.frames += 1; s.now = false end
	end
end)
task.wait(6)
c:Disconnect()
for _, x in conns do x:Disconnect() end
local out = {}
for name, s in dirty do out[name] = string.format("%d of %d frames written, %d writes", s.frames, frames, s.writes) end
log({ phase = "sides", sides = out })
if ok and stop then stop() end
g:Destroy()
log({ phase = "done" })
