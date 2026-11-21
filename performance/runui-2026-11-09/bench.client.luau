-- BALLARC_BENCH probe (client): injected into StarterPlayerScripts by run.py, never in src. Never publish.
-- While the server says capture, counts every property change on the run's UI (PlayerGui and world guis), per frame,
-- by gui, element and property, and takes a census of what each gui holds.
local R = game:GetService("ReplicatedStorage")
local RS = game:GetService("RunService")
local H = game:GetService("HttpService")
local P = game:GetService("Players")
local W = workspace
task.wait(4)
local function log(v)
	v.label = "__LABEL__"
	print("[BALLARC_BENCH_CLIENT] " .. H:JSONEncode(v))
end
log({ phase = "boot" })
R:WaitForChild("BallarcBenchReady"):FireServer()
local playerGui = P.LocalPlayer:WaitForChild("PlayerGui")

local function rootOf(inst: Instance): Instance?
	local node = inst
	while node do
		if node:IsA("LayerCollector") then return node end
		node = node.Parent
	end
	return nil
end

local function shortName(inst: Instance): string
	local parts = {}
	local node = inst
	while node and node ~= playerGui and node ~= W and #parts < 7 do
		table.insert(parts, 1, node.Name)
		node = node.Parent
	end
	return table.concat(parts, ".")
end

local capturing = false
local frameCount = 0
local byProp, byRoot, byElement = {}, {}, {}
local dirtyRootsThisFrame = {}
local dirtyRootsTotal = 0
local dirtyContainers = {}
local shownByRoot, shownDirtyByRoot, shownDirtyTotal = {}, {}, 0
local siblingWork = {}
local siblingTotal = 0
local layoutWrites = 0
local conns = {}
-- Properties that move or resize a box (the ones that can make a layout pass redo work).
local LAYOUT_PROPS = {
	Size = true, Position = true, AnchorPoint = true, Scale = true, Visible = true, Text = true, TextSize = true,
	Rotation = true, AbsoluteSize = false, AbsolutePosition = false, Parent = true, Thickness = true,
}

-- Choice screens left open from before the bench stopped the choices: hidden and not counted.
local SKIP = { AugmentGui = true, UpgradeGui = true, RewardConfettiGui = true }
local function watch(inst: Instance)
	if not (inst:IsA("GuiBase") or inst:IsA("UIBase")) then return end
	local root = rootOf(inst)
	if root and SKIP[root.Name] then return end
	local rootName = if root then shortName(root) else "?"
	conns[#conns + 1] = inst.Changed:Connect(function(prop)
		if not capturing then return end
		if prop == "AbsoluteSize" or prop == "AbsolutePosition" or prop == "AbsoluteRotation" or prop == "AbsoluteCanvasSize" or prop == "AbsoluteWindowSize" or prop == "TextBounds" or prop == "TextFits" or prop == "GuiState" or prop == "AbsoluteContentSize" then return end
		byProp[prop] = (byProp[prop] or 0) + 1
		byRoot[rootName] = (byRoot[rootName] or 0) + 1
		local key = shortName(inst) .. ":" .. prop
		byElement[key] = (byElement[key] or 0) + 1
		if LAYOUT_PROPS[prop] then layoutWrites += 1 end
		-- The element a write dirties (a modifier dirties its GuiObject), and the parent whose children get re-laid out.
		local element = if inst:IsA("GuiObject") or inst:IsA("LayerCollector") then inst else inst.Parent
		local container = element and element.Parent
		if container then dirtyContainers[container] = true end
		if not dirtyRootsThisFrame[rootName] then
			dirtyRootsThisFrame[rootName] = true
			dirtyRootsTotal += 1
			local shown = shownByRoot[rootName] or 0
			shownDirtyTotal += shown
			shownDirtyByRoot[rootName] = (shownDirtyByRoot[rootName] or 0) + shown
		end
	end)
end

local function shownIn(root: Instance): number
	local count = 0
	for _, d in root:GetDescendants() do
		if d:IsA("GuiObject") then
			local shown = d.Visible
			local node = d.Parent
			while shown and node and node ~= root do
				if node:IsA("GuiObject") and not node.Visible then shown = false end
				node = node.Parent
			end
			if shown then count += 1 end
		end
	end
	return count
end

local function census()
	local guis = {}
	local function add(root: Instance)
		local c = { enabled = true, desc = 0, gui = 0, shown = 0, autoSize = 0, textScaled = 0, layouts = 0, strokes = 0, canvas = 0, aspect = 0, gradients = 0, scales = 0, text = 0 }
		if root:IsA("LayerCollector") then c.enabled = root.Enabled end
		for _, d in root:GetDescendants() do
			c.desc += 1
			if d:IsA("GuiObject") then
				c.gui += 1
				local shown = d.Visible
				local node = d.Parent
				while shown and node and node ~= root do
					if node:IsA("GuiObject") and not node.Visible then shown = false end
					node = node.Parent
				end
				if shown then c.shown += 1 end
				if d.AutomaticSize ~= Enum.AutomaticSize.None then c.autoSize += 1 end
				if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
					c.text += 1
					if d.TextScaled then c.textScaled += 1 end
				end
				if d:IsA("CanvasGroup") then c.canvas += 1 end
			elseif d:IsA("UIGridStyleLayout") then
				c.layouts += 1
			elseif d:IsA("UIStroke") then
				c.strokes += 1
			elseif d:IsA("UIAspectRatioConstraint") then
				c.aspect += 1
			elseif d:IsA("UIGradient") then
				c.gradients += 1
			elseif d:IsA("UIScale") then
				c.scales += 1
			end
		end
		guis[shortName(root) .. ":" .. root.ClassName] = c
	end
	for _, child in playerGui:GetChildren() do
		if child:IsA("LayerCollector") then add(child) end
	end
	local world = 0
	for _, d in W:GetDescendants() do
		if d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
			world += 1
			if world <= 40 then add(d) end
		end
	end
	return guis, world
end

local function top(map, n)
	local list = {}
	for k, v in map do list[#list + 1] = { k, v } end
	table.sort(list, function(a, b) return a[2] > b[2] end)
	local out = {}
	for i = 1, math.min(n, #list) do out[i] = string.format("%.2f %s", list[i][2] / math.max(1, frameCount), list[i][1]) end
	return out
end

-- One invalidation per root: move a probe frame (or a deep existing element) and time the forced layout on reading
-- AbsolutePosition. Median of REPS, per root, so the roots can be ranked by what one dirtying costs.
local REPS = 41
local function layoutCost()
	local out = {}
	local roots = {}
	for _, child in playerGui:GetChildren() do
		if child:IsA("LayerCollector") and child.Enabled then roots[#roots + 1] = child end
	end
	for _, root in roots do
		local probe = Instance.new("Frame")
		probe.Size = UDim2.fromOffset(1, 1)
		probe.BackgroundTransparency = 1
		probe.Parent = root
		local _ = probe.AbsolutePosition
		local times = {}
		for i = 1, REPS do
			probe.Position = UDim2.fromOffset(i % 2, 0)
			local t = os.clock()
			local _ = probe.AbsolutePosition
			times[i] = (os.clock() - t) * 1e6
		end
		probe:Destroy()
		table.sort(times)
		-- A deep element: the most nested GuiObject in the root, nudged and read the same way.
		local deep, depth = nil, -1
		for _, d in root:GetDescendants() do
			if d:IsA("GuiObject") then
				local n, node = 0, d
				while node ~= root do n += 1; node = node.Parent end
				if n > depth then deep, depth = d, n end
			end
		end
		local deepMedian = -1
		if deep then
			local original = deep.Position
			local deepTimes = {}
			for i = 1, REPS do
				deep.Position = original + UDim2.fromOffset(i % 2, 0)
				local t = os.clock()
				local _ = deep.AbsolutePosition
				deepTimes[i] = (os.clock() - t) * 1e6
			end
			deep.Position = original
			table.sort(deepTimes)
			deepMedian = deepTimes[(REPS + 1) // 2]
		end
		out[root.Name] = { top = times[(REPS + 1) // 2], deep = deepMedian, depth = depth, n = #root:GetDescendants() }
	end
	return out
end

local GC = require(R.Shared.Core.GeneratorCore)
local walkClock = 0
local function walk(dt)
	-- Three straight strips across the map, so the explored area has long fog edges like a late run.
	local char = P.LocalPlayer.Character
	if not char or not char.PrimaryPart then return end
	walkClock += dt
	local grid = GC.Grid
	local span = GC.GRID_WIDTH * GC.CELL_SIZE
	local leg = (walkClock * 120) % (span * 3)
	local strip = leg // span
	local along = leg % span
	local x = grid.OriginX + (if strip == 1 then span - along else along)
	local z = grid.OriginZ + (strip * 10 + 4) * GC.CELL_SIZE
	local cell = grid:GetCellFromWorldPos(vector.create(x, 0, z))
	local y = if cell then cell.Height + 4 else char.PrimaryPart.Position.Y
	char.PrimaryPart.Anchored = true
	char:PivotTo(CFrame.new(x, y, z))
end
local armText = nil
RS.PreRender:Connect(function(dt)
	local text = W:GetAttribute("BallarcBenchArm")
	if text ~= armText then armText = text end
	local capture = W:GetAttribute("BallarcBenchCapture")
	if armText and string.find(armText, '"walk":true', 1, true) and not capture then walk(dt) end
	if capture and not capturing then
		for name in SKIP do
			local gui = playerGui:FindFirstChild(name)
			if gui then gui.Enabled = false end
		end
		for _, d in playerGui:GetDescendants() do watch(d) end
		for _, d in W:GetDescendants() do
			if d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
				watch(d)
				for _, x in d:GetDescendants() do watch(x) end
			end
		end
		conns[#conns + 1] = playerGui.DescendantAdded:Connect(watch)
		byProp, byRoot, byElement = {}, {}, {}
		frameCount, dirtyRootsTotal, layoutWrites = 0, 0, 0
		shownByRoot, shownDirtyByRoot, shownDirtyTotal = {}, {}, 0
		for _, child in playerGui:GetChildren() do
			if child:IsA("LayerCollector") then shownByRoot[shortName(child)] = if child.Enabled then shownIn(child) else 0 end
		end
		siblingWork, siblingTotal = {}, 0
		table.clear(dirtyContainers)
		capturing = true
	elseif capture then
		frameCount += 1
		table.clear(dirtyRootsThisFrame)
		for container in dirtyContainers do
			local n = #container:GetChildren()
			siblingTotal += n
			local key = shortName(container) .. " [" .. n .. "]"
			siblingWork[key] = (siblingWork[key] or 0) + n
		end
		table.clear(dirtyContainers)
	elseif capturing then
		capturing = false
		for _, c in conns do c:Disconnect() end
		table.clear(conns)
		local guis, world = census()
		log({ phase = "layout", arm = H:JSONDecode(armText), cost = layoutCost() })
		local arm = H:JSONDecode(armText)
		log({ phase = "arm", arm = arm, frames = frameCount, dirtyRootsPerFrame = dirtyRootsTotal / math.max(1, frameCount), layoutWritesPerFrame = layoutWrites / math.max(1, frameCount), byProp = top(byProp, 25), byRoot = top(byRoot, 25), worldGuis = world, siblingsPerFrame = siblingTotal / math.max(1, frameCount), siblingTop = top(siblingWork, 25), shownDirtyPerFrame = shownDirtyTotal / math.max(1, frameCount), shownDirtyTop = (function() local out = {} for k, v in shownDirtyByRoot do out[k] = v end local list = top(out, 20) for i, x in list do local name = string.match(x, "^%S+ (.+)$") list[i] = x .. " (shown " .. tostring(shownByRoot[name]) .. ")" end return list end)() })
		local elements = top(byElement, 120)
		for i = 1, #elements, 30 do
			log({ phase = "elements", arm = arm, part = i, list = table.move(elements, i, math.min(i + 29, #elements), 1, {}) })
		end
		local names = {}
		for k in guis do names[#names + 1] = k end
		table.sort(names)
		for i = 1, #names, 12 do
			local chunk = {}
			for j = i, math.min(i + 11, #names) do chunk[names[j]] = guis[names[j]] end
			log({ phase = "census", arm = arm, guis = chunk })
		end
	end
end)
