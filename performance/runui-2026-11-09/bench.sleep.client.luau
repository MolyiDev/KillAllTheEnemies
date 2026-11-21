-- BALLARC_BENCH probe (client, sleep check): injected by run.py, never in src. Never publish.
-- Which closed screens are off, and frame by frame how the Info screen's Enabled follows its open and close.
local R = game:GetService("ReplicatedStorage")
local RS = game:GetService("RunService")
local H = game:GetService("HttpService")
local P = game:GetService("Players")
task.wait(4)
local function log(v) v.label = "__LABEL__"; print("[BALLARC_BENCH_CLIENT] " .. H:JSONEncode(v)) end
R:WaitForChild("BallarcBenchReady"):FireServer()
task.wait(12)
local playerGui = P.LocalPlayer:WaitForChild("PlayerGui")
local states = {}
for _, child in playerGui:GetChildren() do
	if child:IsA("LayerCollector") then states[#states + 1] = child.Name .. "=" .. tostring(child.Enabled) end
end
table.sort(states)
log({ phase = "rest", states = states })

local Info = require(P.LocalPlayer.PlayerScripts.Client.Controllers.InfoController)
local gui = playerGui:WaitForChild("InfoGui")
local root = gui:WaitForChild("InfoScreen")
local trace = {}
local frameIndex = 0
local conn = RS:BindToRenderStep("SleepTrace", Enum.RenderPriority.Last.Value + 60, function()
	frameIndex += 1
	trace[#trace + 1] = string.format("%d:%s/%s", frameIndex, if root.Visible then "V" else "-", if gui.Enabled then "E" else "-")
end)
task.wait(0.1)
log({ phase = "mark", at = frameIndex, what = "appear" })
Info.Appear()
task.wait(1.5)
log({ phase = "mark", at = frameIndex, what = "disappear" })
Info.Disappear()
task.wait(3.5)
RS:UnbindFromRenderStep("SleepTrace")
-- Collapse runs of the same state.
local runs, last, count, from = {}, nil, 0, 0
for _, entry in trace do
	local index, state = string.match(entry, "^(%d+):(.+)$")
	if state ~= last then
		if last then runs[#runs + 1] = string.format("%s x%d (from %d)", last, count, from) end
		last, count, from = state, 0, tonumber(index)
	end
	count += 1
end
runs[#runs + 1] = string.format("%s x%d (from %d)", last, count, from)
log({ phase = "trace", runs = runs })
log({ phase = "done" })
