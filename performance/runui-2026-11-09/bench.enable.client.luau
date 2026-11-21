-- BALLARC_BENCH probe (client, enable lab): injected by run.py, never in src. Never publish.
-- What a ScreenGui's Enabled does to its contents' AbsoluteSize, and when a Visible-driven re-enable lands.
local R = game:GetService("ReplicatedStorage")
local RS = game:GetService("RunService")
local H = game:GetService("HttpService")
local P = game:GetService("Players")
task.wait(4)
local function log(v) v.label = "__LABEL__"; print("[BALLARC_BENCH_CLIENT] " .. H:JSONEncode(v)) end
R:WaitForChild("BallarcBenchReady"):FireServer()
local playerGui = P.LocalPlayer:WaitForChild("PlayerGui")

local g = Instance.new("ScreenGui"); g.ResetOnSpawn = false; g.Name = "EnableLab"; g.Parent = playerGui
local panel = Instance.new("Frame"); panel.Size = UDim2.fromScale(0.5, 0.25); panel.Parent = g
local inner = Instance.new("Frame"); inner.Size = UDim2.fromScale(0.5, 0.5); inner.Parent = panel
task.wait(0.2)
local sizeChanges = 0
inner:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() sizeChanges += 1 end)
local a = inner.AbsoluteSize
g.Enabled = false
local b = inner.AbsoluteSize
task.wait(0.2)
local c = inner.AbsoluteSize
-- Resized while disabled: does it update?
panel.Size = UDim2.fromScale(0.6, 0.25)
local d = inner.AbsoluteSize
task.wait(0.2)
local e = inner.AbsoluteSize
g.Enabled = true
local f = inner.AbsoluteSize
task.wait(0.2)
local h = inner.AbsoluteSize
log({ phase = "size", before = tostring(a), disabledNow = tostring(b), disabledLater = tostring(c), resizedWhileOffNow = tostring(d), resizedWhileOffLater = tostring(e), enabledNow = tostring(f), enabledLater = tostring(h), sizeSignals = sizeChanges })

-- Visible-driven Enabled: open in PreRender, see where Enabled is by the last render step of that frame.
panel.Visible = false
g.Enabled = false
panel:GetPropertyChangedSignal("Visible"):Connect(function() g.Enabled = panel.Visible end)
local opened, seenAtLast = false, nil
RS:BindToRenderStep("EnableLabLast", Enum.RenderPriority.Last.Value + 50, function()
	if opened and seenAtLast == nil then seenAtLast = g.Enabled end
end)
local conn
conn = RS.PreRender:Connect(function()
	conn:Disconnect()
	panel.Visible = true
	opened = true
end)
task.wait(0.5)
RS:UnbindFromRenderStep("EnableLabLast")
log({ phase = "order", enabledByLastRenderStep = seenAtLast, enabledLater = g.Enabled })
log({ phase = "done" })
