-- BALLARC_BENCH probe (client): injected into StarterPlayerScripts by run.py, never in src. Never publish.
-- Applies each arm's settings, then times frames while the server says capture.
local R = game:GetService("ReplicatedStorage")
local RS = game:GetService("RunService")
local H = game:GetService("HttpService")
local P = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local Stats = game:GetService("Stats")
local W = workspace
task.wait(4)
print("[BALLARC_BENCH_CLIENT] {\"phase\":\"boot\"}")
local C = require(R.GlobalShared.ECS.Components)
local EW = require(R.GlobalShared.ECS.Worlds.EnemyWorld)
local ESettings = require(R.Types.Enums.Settings.ESettings)
local ESettingsVisual = require(R.Types.Enums.Settings.ESettingsVisual)
local Settings = require(P.LocalPlayer.PlayerScripts.GlobalClient.Controllers.SettingsController)
local GC = require(R.Shared.Core.GeneratorCore)
local q = EW:query(C.CFrame, C.WalkAnimation):cached()
local function log(v) v.label = "__LABEL__"; print("[BALLARC_BENCH_CLIENT] " .. H:JSONEncode(v)) end
local function percentile(a, p) table.sort(a); return a[math.max(1, math.ceil(#a * p))] or 0 end
local frames, animated, visible = {}, {}, {}
local animGaps, renderCpu = {}, {}
local capOk = pcall(function() UserSettings():GetService("UserGameSettings").FramerateCap = 1000 end)
print("[BALLARC_BENCH_CLIENT] " .. H:JSONEncode({ phase = "cap", ok = capOk }))
local animStart = 0
RS.PreAnimation:Connect(function() animStart = os.clock() end)
RS.PreSimulation:Connect(function()
	if W:GetAttribute("BallarcBenchCapture") then animGaps[#animGaps + 1] = (os.clock() - animStart) * 1000 end
end)
local lostFocus = false
UIS.WindowFocusReleased:Connect(function() lostFocus = true end)
local armText = nil
local capturing = false
R:WaitForChild("BallarcBenchReady"):FireServer()
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
RS.PreRender:Connect(function(dt)
	local text = W:GetAttribute("BallarcBenchArm")
	if text ~= armText then
		armText = text
		if text and text ~= "done" then
			local arm = H:JSONDecode(text)
			if arm.anim then
				Settings.OnNumberChanged:Fire(ESettings.Visual, ESettingsVisual.AnimationDistance, arm.anim)
			end
			if arm.max then
				Settings.OnNumberChanged:Fire(ESettings.Visual, ESettingsVisual.MaxAnimatedEnemies, arm.max)
			end
			if arm.minimapAnim ~= nil then
				Settings.OnBoolChanged:Fire(ESettings.Visual, ESettingsVisual.MinimapAnimations, arm.minimapAnim)
			end
		end
	end
	local capture = W:GetAttribute("BallarcBenchCapture")
	if armText and armText ~= "done" and string.find(armText, '"walk":true', 1, true) and not capture then walk(dt) end
	if capture and not capturing then shared.BenchShimmerMs = 0; shared.BenchMotionMs = 0; shared.BenchMotionBy = {} end
	if capture then
		capturing = true
		frames[#frames + 1] = dt * 1000
		renderCpu[#renderCpu + 1] = Stats.RenderCPUFrameTime
		if #frames % 30 == 0 then
			local a, v = 0, 0
			for _, cf, track in q do
				if cf.Position.X ~= 2 ^ 24 then v += 1 end
				if track.IsPlaying then a += 1 end
			end
			animated[#animated + 1] = a
			visible[#visible + 1] = v
		end
	elseif capturing then
		capturing = false
		local sum = 0
		for _, f in frames do sum += f end
		local gapSum = 0
		for _, g in animGaps do gapSum += g end
		local gapMean = gapSum / math.max(1, #animGaps)
		local animMedian, animP95, renderMedian = percentile(animGaps, 0.5), percentile(animGaps, 0.95), percentile(renderCpu, 0.5)
		local char = P.LocalPlayer.Character
		local camDist = if char and char.PrimaryPart then (W.CurrentCamera.CFrame.Position - char.PrimaryPart.Position).Magnitude else -1
		local census = {}
		for _, child in W:GetChildren() do
			local parts, moving = 0, 0
			for _, d in child:GetDescendants() do
				if d:IsA("BasePart") then
					parts += 1
					if d.Transparency < 1 and d.Position.Magnitude < 1e6 then moving += 1 end
				end
			end
			if child:IsA("BasePart") then parts += 1 end
			if parts > 0 then census[child.Name .. ":" .. child.ClassName] = { parts, moving } end
		end
		local map = W:FindFirstChild("Map")
		local mapCensus = {}
		if map then
			for _, child in map:GetChildren() do
				local key = child.Name .. ":" .. child.ClassName
				local entry = mapCensus[key] or { 0, 0, 0 }
				entry[1] += 1
				for _, d in child:GetDescendants() do
					if d:IsA("BasePart") then entry[2] += 1; if d:IsA("MeshPart") then entry[3] += 1 end end
				end
				if child:IsA("BasePart") then entry[2] += 1 end
				mapCensus[key] = entry
			end
		end
		local statsDump = {}
		local function dump(node, prefix, depth)
			for _, child in node:GetChildren() do
				local name = prefix .. child.Name
				local ok, value = pcall(function() return child:GetValueString() end)
				statsDump[#statsDump + 1] = name .. "=" .. (if ok then tostring(value) else child.ClassName)
				if depth < 3 and child.Name ~= "Memory" then dump(child, name .. "/", depth + 1) end
			end
		end
		dump(Stats, "", 0)
		print("[BALLARC_BENCH_STATS] " .. table.concat(statsDump, " | "))
		local borderCells, heights = 0, {}
		for _, cell in GC.Grid.Grid do
			if cell.IsFilled and cell.IsBorder then borderCells += 1; heights[tostring(cell.Height)] = (heights[tostring(cell.Height)] or 0) + 1 end
		end
		log({ phase = "census", census = census, map = mapCensus, borderCells = borderCells, borderHeights = heights })
		log({ phase = "arm", arm = H:JSONDecode(armText), frames = #frames, meanMs = sum / math.max(1, #frames),
			medianMs = percentile(frames, 0.5), p95Ms = percentile(frames, 0.95),
			animated = percentile(animated, 0.5), visible = percentile(visible, 0.5),
			focusLost = lostFocus, animStepMeanMs = gapMean, x_shimmerMsPerFrame = (shared.BenchShimmerMs or 0) / math.max(1, #frames), x_edgeCells = shared.BenchShimmerCells, x_joinMax = Settings.GetNumber(ESettings.Visual, ESettingsVisual.MaxAnimatedEnemies), x_motionMsPerFrame = (shared.BenchMotionMs or 0) / math.max(1, #frames), x_motionTop = (function() local list = {} for k, v in shared.BenchMotionBy or {} do list[#list + 1] = { k, v * 1000 / math.max(1, #frames) } end table.sort(list, function(a, b) return a[2] > b[2] end) local out = {} for i = 1, math.min(6, #list) do out[i] = string.format('%.3f %s', list[i][2], list[i][1]) end return out end)(), animStepMedianMs = animMedian, animStepP95Ms = animP95, renderCpuMedianMs = renderMedian, camDist = camDist, viewport = { W.CurrentCamera.ViewportSize.X, W.CurrentCamera.ViewportSize.Y } })
		frames, animated, visible = {}, {}, {}
		animGaps, renderCpu = {}, {}
		lostFocus = false
	end
end)
