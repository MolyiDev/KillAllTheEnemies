-- PERF_PROBE (throwaway, never in src): per HUD piece, visible elements and frames written, in a scripted fight.
local RS = game:GetService("RunService")
local H = game:GetService("HttpService")
local P = game:GetService("Players")
local playerGui = P.LocalPlayer:WaitForChild("PlayerGui")
local function log(t) warn("[PERF_PROBE] " .. H:JSONEncode(t)) end
local ugs = UserSettings():GetService("UserGameSettings")
local okG, g = pcall(function() return ugs.GraphicsQualityLevel end)
log({ phase = "quality", saved = tostring(ugs.SavedQualityLevel), graphicsReadable = okG, graphics = if okG then g else tostring(g) })
local enemies = workspace:WaitForChild("Enemies", 120)
while #enemies:GetChildren() < 100 do task.wait(0.25) end
task.wait(4)
local SKIP = { AbsoluteSize = true, AbsolutePosition = true, AbsoluteRotation = true, AbsoluteCanvasSize = true, AbsoluteWindowSize = true, TextBounds = true, TextFits = true, GuiState = true, AbsoluteContentSize = true }
local function isShown(g)
	local node = g
	while node and node ~= playerGui do
		if node:IsA("GuiObject") and not node.Visible then return false end
		if node:IsA("LayerCollector") and not node.Enabled then return false end
		node = node.Parent
	end
	return true
end
local function pieceOf(inst)
	local node, child = inst, nil
	while node and node ~= playerGui do
		if node.Name == "Root" and node:FindFirstAncestorOfClass("ScreenGui") and string.sub(node:FindFirstAncestorOfClass("ScreenGui").Name, 1, 3) == "Hud" then return node:FindFirstAncestorOfClass("ScreenGui").Name .. "/" .. (if child then child.Name else "Root") end
		if node:IsA("LayerCollector") then return "[" .. node.Name .. "]" end
		child = node
		node = node.Parent
	end
	return "?"
end
for window = 1, 2 do
	local frames, written, shown, dirty, writes, conns, top = 0, {}, {}, {}, {}, {}, {}
	for _, inst in playerGui:GetDescendants() do
		if inst:IsA("GuiBase") or inst:IsA("UIBase") then
			local piece = pieceOf(inst)
			if inst:IsA("GuiObject") and isShown(inst) then shown[piece] = (shown[piece] or 0) + 1 end
			conns[#conns + 1] = inst.Changed:Connect(function(prop)
				if SKIP[prop] then return end
				dirty[piece] = true
				writes[piece] = (writes[piece] or 0) + 1
				local key = piece .. ":" .. inst.Name .. ":" .. prop
				top[key] = (top[key] or 0) + 1
			end)
		end
	end
	local dts = {}
	local done = false
	local conn
	conn = RS.PreRender:Connect(function(dt)
		frames += 1
		dts[frames] = dt * 1000
		for piece in dirty do written[piece] = (written[piece] or 0) + 1 end
		table.clear(dirty)
		if frames < 300 then return end
		conn:Disconnect()
		for _, c in conns do c:Disconnect() end
		done = true
	end)
	while not done do task.wait(0.1) end
	local rows = {}
	for piece, n in shown do table.insert(rows, { piece = piece, shown = n, framesWritten = written[piece] or 0, writes = writes[piece] or 0 }) end
	for piece, n in written do if not shown[piece] then table.insert(rows, { piece = piece, shown = 0, framesWritten = n, writes = writes[piece] }) end end
	table.sort(rows, function(a, b) return a.framesWritten * a.shown > b.framesWritten * b.shown end)
	local t = {}
	for k, v in top do table.insert(t, { k, v }) end
	table.sort(t, function(a, b) return a[2] > b[2] end)
	local tt = {}
	for i = 1, math.min(25, #t) do tt[i] = t[i][1] .. "=" .. t[i][2] end
	log({ phase = "hud", window = window, frames = frames, enemies = #enemies:GetChildren(), rows = rows, top = tt })
	task.wait(2)
end
