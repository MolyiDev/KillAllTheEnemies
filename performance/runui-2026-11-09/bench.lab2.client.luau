-- BALLARC_BENCH probe (client, lab 2): injected by run.py (CLIENT=bench.lab2.client.luau), never in src. Never publish.
-- The frame's own layout pass, not a forced read: an 8 ms busy wait each frame drops the client under the 240 FPS cap,
-- so frame time shows what each synthetic tree adds when one thing in it is written every frame.
local R = game:GetService("ReplicatedStorage")
local RS = game:GetService("RunService")
local H = game:GetService("HttpService")
local P = game:GetService("Players")
task.wait(4)
local function log(v) v.label = "__LABEL__"; print("[BALLARC_BENCH_CLIENT] " .. H:JSONEncode(v)) end
R:WaitForChild("BallarcBenchReady"):FireServer()
local playerGui = P.LocalPlayer:WaitForChild("PlayerGui")
local BUSY = 0.008
local SECONDS = 2.5
local ROUNDS = 4

local function gui(name)
	local g = Instance.new("ScreenGui")
	g.Name = name
	g.ResetOnSpawn = false
	g.Parent = playerGui
	return g
end
local function frame(parent, visible)
	local f = Instance.new("Frame")
	f.Size = UDim2.fromOffset(20, 20)
	f.BackgroundTransparency = 0.5
	f.Visible = visible
	f.Parent = parent
	return f
end
-- A nested tree of `count` frames, four children per frame, like a HUD's slabs.
local function tree(parent, count, visible)
	local queue, made = { parent }, 0
	local head = 1
	while made < count do
		local node = queue[head]
		head += 1
		for _ = 1, 4 do
			if made >= count then break end
			local f = frame(node, visible)
			f.Size = UDim2.fromScale(0.9, 0.9)
			made += 1
			queue[#queue + 1] = f
		end
	end
end

local function smallRoots(count)
	return function(g)
		local hots = {}
		for i = 1, count do
			local r = if i == 1 then g else gui("LabRoot")
			if i > 1 then g.Destroying:Connect(function() r:Destroy() end) end
			hots[i] = frame(r, true)
		end
		return hots, "Position"
	end
end
local function sized(visible)
	return function(g)
		local hot = frame(g, true)
		for _ = 1, visible do frame(g, true).Position = UDim2.fromOffset(math.random(0, 800), math.random(0, 600)) end
		return { hot }, "Position"
	end
end
local function sizedStatic(visible)
	return function(g)
		local hot = frame(g, true)
		local other = gui("LabOther")
		g.Destroying:Connect(function() other:Destroy() end)
		for _ = 1, visible do frame(other, true).Position = UDim2.fromOffset(math.random(0, 800), math.random(0, 600)) end
		return { hot }, "Position"
	end
end
local pixelSlab = require(game:GetService("StarterPlayer").StarterPlayerScripts.GlobalClient.UI.Components.pixelSlab)
-- The slab as it was before the strips: shadow, outline, bezel, light, shade, well, well shade under one body.
local function oldSlab(parent, x, y)
	local body = frame(parent, true); body.BackgroundTransparency = 1; body.Size = UDim2.fromOffset(120, 40); body.Position = UDim2.fromOffset(x, y)
	local shadow = frame(body, true); shadow.Size = UDim2.fromOffset(120, 40); shadow.Position = UDim2.fromOffset(3, 3)
	local outline = frame(body, true); outline.Size = UDim2.fromScale(1, 1)
	local bezel = frame(outline, true); bezel.Size = UDim2.fromOffset(114, 34); bezel.Position = UDim2.fromOffset(3, 3)
	frame(bezel, true).Size = UDim2.fromOffset(114, 6)
	frame(bezel, true).Size = UDim2.fromOffset(114, 6)
	local well = frame(bezel, true); well.Size = UDim2.fromOffset(102, 22)
	frame(well, true).Size = UDim2.fromOffset(102, 3)
end
local function slabs(isNew, count)
	return function(g)
		local hot = frame(g, true)
		for i = 1, count do
			local x, y = (i % 5) * 130, (i // 5) * 50
			if isNew then
				local slab = pixelSlab.Body(pixelSlab.Palettes.Magenta)
				slab.Layout(120, 40, 3, 2)
				slab.Body.Position = UDim2.fromOffset(x, y)
				slab.Body.Parent = g
			else
				oldSlab(g, x, y)
			end
		end
		return { hot }, "Position"
	end
end
local function transparent(count)
	return function(g)
		local hot = frame(g, true)
		for _ = 1, count do local f = frame(g, true); f.BackgroundTransparency = 1 end
		return { hot }, "Position"
	end
end
local function big(prop)
	return function(g)
		local hot = frame(g, true)
		local holder = frame(g, true); holder.Size = UDim2.fromOffset(400, 400)
		tree(holder, 2000, true)
		return { hot }, prop
	end
end
local cases = {
	{ "empty", function(g) return { frame(g, true) }, "Same" end },
	{ "2000 visible, hot written a new value", big("Position") },
	{ "2000 visible, hot written its same value", big("Same") },
	{ "2000 visible, nothing written", big("None") },
}

local function write(target, prop, flip)
	if prop == "None" then
		return
	elseif prop == "Same" then
		target.Position = UDim2.fromOffset(100, 100)
	elseif prop == "Position" then
		target.Position = UDim2.fromOffset(100 + flip, 100)
	elseif prop == "BackgroundTransparency" then
		target.BackgroundTransparency = 0.4 + flip * 0.1
	elseif prop == "Scale" then
		target.Scale = 1 + flip * 0.01
	elseif prop == "Size" then
		target.Size = UDim2.fromOffset(400 + flip, 400)
	end
end

local sums = {}
for round = 1, ROUNDS do
	for _, case in cases do
		local g = gui("Lab")
		local targets, prop = case[2](g)
		task.wait(0.5)
		local flip, total, n, started = 0, 0, 0, os.clock()
		local done = false
		local conn = RS.PreRender:Connect(function(dt)
			local t = os.clock()
			while os.clock() - t < BUSY do end
			flip = 1 - flip
			for _, target in targets do write(target, prop, flip) end
			if os.clock() - started > 0.5 then
				total += dt
				n += 1
			end
			if os.clock() - started > SECONDS then done = true end
		end)
		repeat task.wait() until done
		conn:Disconnect()
		g:Destroy()
		local entry = sums[case[1]] or { 0, 0 }
		entry[1] += total
		entry[2] += n
		sums[case[1]] = entry
		log({ phase = "lab", round = round, case = case[1], meanMs = total / math.max(1, n) * 1000, frames = n })
		task.wait(0.3)
	end
end
local base = sums.empty[1] / sums.empty[2]
for _, case in cases do
	local s = sums[case[1]]
	local mean = s[1] / s[2]
	log({ phase = "result", line = string.format("%7.3f ms  %+7.1f us  %s", mean * 1000, (mean - base) * 1e6, case[1]) })
end
log({ phase = "done" })
