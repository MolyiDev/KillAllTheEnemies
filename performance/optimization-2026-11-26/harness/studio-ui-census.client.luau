-- PERF_PROBE (throwaway, never in src): UI writes per root per frame in a fight, and frame times.
local RS = game:GetService("RunService")
local H = game:GetService("HttpService")
local P = game:GetService("Players")
local RepS = game:GetService("ReplicatedStorage")
local playerGui = P.LocalPlayer:WaitForChild("PlayerGui")
local function log(t) print("[PERF_PROBE] " .. H:JSONEncode(t)) end
local ok, gc = pcall(function() return require(RepS:WaitForChild("GlobalShared", 30).Core.GunsCore) end)
log({ phase = "boot", newGunsCore = ok and gc.CastBodiesAll ~= nil })
local enemies = workspace:WaitForChild("Enemies", 120)
while #enemies:GetChildren() < 100 do task.wait(0.25) end
task.wait(1)
local function rootOf(inst)
	local node = inst
	while node do
		if node:IsA("LayerCollector") then return node end
		node = node.Parent
	end
end
local function isShown(g)
	local node = g
	while node and node ~= playerGui do
		if node:IsA("GuiObject") and not node.Visible then return false end
		if node:IsA("LayerCollector") and not node.Enabled then return false end
		node = node.Parent
	end
	return true
end
local SKIP = { AbsoluteSize = true, AbsolutePosition = true, AbsoluteRotation = true, AbsoluteCanvasSize = true, AbsoluteWindowSize = true, TextBounds = true, TextFits = true, GuiState = true, AbsoluteContentSize = true }
local capturing, frames = false, 0
local writtenFrames, writes, byElement, shownCount = {}, {}, {}, {}
local dirty = {}
local conns = {}
local function shortName(inst)
	local parts, node = {}, inst
	while node and node ~= playerGui and #parts < 6 do table.insert(parts, 1, node.Name); node = node.Parent end
	return table.concat(parts, ".")
end
for _, inst in playerGui:GetDescendants() do
	if inst:IsA("GuiBase") or inst:IsA("UIBase") then
		local root = rootOf(inst)
		local rootName = if root then root.Name else "?"
		if inst:IsA("GuiObject") and isShown(inst) then shownCount[rootName] = (shownCount[rootName] or 0) + 1 end
		conns[#conns + 1] = inst.Changed:Connect(function(prop)
			if not capturing or SKIP[prop] then return end
			writes[rootName] = (writes[rootName] or 0) + 1
			dirty[rootName] = true
			local key = shortName(inst) .. ":" .. prop
			byElement[key] = (byElement[key] or 0) + 1
		end)
	end
end
local dts = {}
capturing = true
local conn
conn = RS.PreRender:Connect(function(dt)
	frames += 1
	dts[frames] = dt
	for name in dirty do writtenFrames[name] = (writtenFrames[name] or 0) + 1 end
	table.clear(dirty)
	if frames >= 600 then
		capturing = false
		conn:Disconnect()
		for _, c in conns do c:Disconnect() end
		table.sort(dts)
		local roots = {}
		for name, n in writtenFrames do
			table.insert(roots, { root = name, framesWritten = n, share = n / frames, writes = writes[name], shown = shownCount[name] or 0 })
		end
		table.sort(roots, function(a, b) return a.framesWritten * a.shown > b.framesWritten * b.shown end)
		local top = {}
		for k, v in byElement do table.insert(top, { k, v }) end
		table.sort(top, function(a, b) return a[2] > b[2] end)
		local topOut = {}
		for i = 1, math.min(25, #top) do topOut[i] = top[i][1] .. "=" .. top[i][2] end
		log({ phase = "ui", frames = frames, dtMedianMs = dts[300] * 1000, dtP95Ms = dts[570] * 1000, enemies = #enemies:GetChildren(), viewport = tostring(workspace.CurrentCamera.ViewportSize), roots = roots, top = topOut })
	end
end)
