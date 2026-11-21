-- BALLARC_BENCH probe (client, lab): injected by run.py (CLIENT=bench.lab.client.luau), never in src. Never publish.
-- Synthetic layout tests in a throwaway ScreenGui: what one write + forced layout costs against how the tree is built.
local R = game:GetService("ReplicatedStorage")
local H = game:GetService("HttpService")
local P = game:GetService("Players")
task.wait(4)
local function log(v) v.label = "__LABEL__"; print("[BALLARC_BENCH_CLIENT] " .. H:JSONEncode(v)) end
R:WaitForChild("BallarcBenchReady"):FireServer()
local playerGui = P.LocalPlayer:WaitForChild("PlayerGui")
local REPS = 61

local function newGui(name)
	local g = Instance.new("ScreenGui")
	g.Name = name
	g.ResetOnSpawn = false
	g.Parent = playerGui
	return g
end
local function label(parent, visible)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromOffset(200, 26)
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.BackgroundTransparency = 1
	l.Text = "123.4"
	l.TextSize = 26
	l.Visible = visible
	l.Parent = parent
	return l
end
-- Median us of writing `targets` (Position) and reading the first one's AbsolutePosition.
local function time(targets)
	local first = targets[1]
	local _ = first.AbsolutePosition
	local t = {}
	for i = 1, REPS do
		local c = os.clock()
		for j, x in targets do x.Position = UDim2.fromOffset(100 + i % 2 + j, 100) end
		local _ = first.AbsolutePosition
		t[i] = (os.clock() - c) * 1e6
	end
	table.sort(t)
	return t[(REPS + 1) // 2]
end

local results = {}
local function case(name, build)
	local g = newGui("Lab")
	local targets = build(g)
	results[#results + 1] = string.format("%8.1f  %s", time(targets), name)
	g:Destroy()
	task.wait()
end

for _, n in { 0, 50, 200, 800 } do
	case(`flat {n} hidden siblings, write 1`, function(g)
		local t = label(g, true)
		for _ = 1, n do label(g, false) end
		return { t }
	end)
	case(`flat {n} visible siblings, write 1`, function(g)
		local t = label(g, true)
		for _ = 1, n do label(g, true) end
		return { t }
	end)
end
case("200 hidden in a sibling holder Frame, write 1", function(g)
	local t = label(g, true)
	local holder = Instance.new("Frame"); holder.Size = UDim2.fromScale(1, 1); holder.BackgroundTransparency = 1; holder.Parent = g
	for _ = 1, 200 do label(holder, false) end
	return { t }
end)
case("200 hidden in a holder with Visible=false, write 1", function(g)
	local t = label(g, true)
	local holder = Instance.new("Frame"); holder.Size = UDim2.fromScale(1, 1); holder.Visible = false; holder.Parent = g
	for _ = 1, 200 do label(holder, false) end
	return { t }
end)
case("200 hidden in another ScreenGui, write 1", function(g)
	local t = label(g, true)
	local other = newGui("LabOther")
	for _ = 1, 200 do label(other, false) end
	task.delay(0, function() end)
	g.Destroying:Connect(function() other:Destroy() end)
	return { t }
end)
case("200 hidden siblings, target inside its own Frame, write 1", function(g)
	local box = Instance.new("Frame"); box.Size = UDim2.fromScale(1, 1); box.BackgroundTransparency = 1; box.Parent = g
	local t = label(box, true)
	for _ = 1, 200 do label(g, false) end
	return { t }
end)
case("200 in 14 groups of ~14 (hidden), write 1", function(g)
	local groups = {}
	for i = 1, 14 do local f = Instance.new("Frame"); f.Size = UDim2.fromScale(1, 1); f.BackgroundTransparency = 1; f.Parent = g; groups[i] = f end
	local t = label(groups[1], true)
	for i = 1, 200 do label(groups[i % 14 + 1], false) end
	return { t }
end)
case("flat 200 visible, write 20 then read once", function(g)
	local list = {}
	for i = 1, 200 do list[i] = label(g, true) end
	return table.move(list, 1, 20, 1, {})
end)
case("flat 20 visible only, write 20 then read once", function(g)
	local list = {}
	for i = 1, 20 do list[i] = label(g, true) end
	return list
end)
case("200 Frames (not text) hidden siblings, write 1", function(g)
	local t = label(g, true)
	for _ = 1, 200 do local f = Instance.new("Frame"); f.Visible = false; f.Parent = g end
	return { t }
end)
case("reparent 1 label from a hidden holder to the gui and back (200 hidden in holder)", function(g)
	local holder = Instance.new("Frame"); holder.Visible = false; holder.Parent = g
	for _ = 1, 200 do label(holder, false) end
	local t = label(g, true)
	local proxy = setmetatable({}, { __index = function(_, k) return t[k] end, __newindex = function(_, k, v) t.Parent = if t.Parent == g then holder else g end end })
	return { t, proxy }
end)
for _, line in results do log({ phase = "lab", line = line }) end
log({ phase = "done" })
