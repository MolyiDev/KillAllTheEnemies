-- BALLARC_BENCH probe: copied into src/Lobby/Client for a run and deleted after. Never publish.
-- Opens each lobby screen through shared.BallarcBenchOpen, samples Stats per frame, and measures overdraw: the
-- canvas area every drawn layer covers, over the canvas area.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local SETTLE = 3
local SAMPLE = 4
local LABEL = script:GetAttribute("Label") or "run"

local function rectClip(ax, ay, bx, by, clip)
	if not clip then return ax, ay, bx, by end
	return math.max(ax, clip[1]), math.max(ay, clip[2]), math.min(bx, clip[3]), math.min(by, clip[4])
end

local function keyOf(inst: Instance, root: Instance): string
	local parts = {}
	local node = inst
	while node and node ~= root do
		table.insert(parts, 1, node.Name)
		node = node.Parent
	end
	-- Keep the outer levels that say which page and component, and the layer's own name.
	if #parts > 7 then
		local short = { parts[1], parts[2], parts[3], parts[4], "..", parts[#parts - 1], parts[#parts] }
		parts = short
	end
	return table.concat(parts, "/")
end

local function measure(root: GuiBase2d)
	local size = root.AbsoluteSize
	local canvas = size.X * size.Y
	local byKey: { [string]: number } = {}
	local byKind: { [string]: number } = {}
	local total, layers = 0, 0
	local viewports, canvasGroups = 0, 0

	local function add(inst, kind, area)
		if area <= 0 then return end
		total += area
		layers += 1
		byKind[kind] = (byKind[kind] or 0) + area
		local key = keyOf(inst, root)
		byKey[key] = (byKey[key] or 0) + area
	end

	local function walk(inst: Instance, clip)
		for _, child in inst:GetChildren() do
			if child:IsA("GuiObject") then
				if not child.Visible then continue end
				if child:IsA("CanvasGroup") and child.GroupTransparency >= 1 then continue end
				local p, s = child.AbsolutePosition, child.AbsoluteSize
				local ax, ay, bx, by = rectClip(p.X, p.Y, p.X + s.X, p.Y + s.Y, clip)
				-- The canvas itself clips.
				ax, ay, bx, by = math.max(ax, 0), math.max(ay, 0), math.min(bx, size.X), math.min(by, size.Y)
				local area = math.max(0, bx - ax) * math.max(0, by - ay)
				if area > 0 then
					if child.BackgroundTransparency < 1 then add(child, "background", area) end
					if (child:IsA("ImageLabel") or child:IsA("ImageButton")) and child.Image ~= "" and child.ImageTransparency < 1 then
						add(child, if child.ScaleType == Enum.ScaleType.Tile then "image-tile" else "image", area)
					end
					if child:IsA("ViewportFrame") then
						viewports += 1
						add(child, "viewport", area)
					end
					if child:IsA("CanvasGroup") then
						canvasGroups += 1
						add(child, "canvasgroup", area)
					end
					if (child:IsA("TextLabel") or child:IsA("TextButton") or child:IsA("TextBox")) and child.Text ~= "" and child.TextTransparency < 1 then
						local tb = child.TextBounds
						local textArea = math.min(area, tb.X * tb.Y)
						add(child, "text", textArea)
						for _, stroke in child:GetChildren() do
							if stroke:IsA("UIStroke") and stroke.Enabled and stroke.Transparency < 1 then
								add(child, "text-stroke", textArea)
							end
						end
					end
					for _, deco in child:GetChildren() do
						if deco:IsA("UIGradient") and deco.Enabled then byKind.gradientLayers = (byKind.gradientLayers or 0) + area end
					end
				end
				local nextClip = clip
				if child.ClipsDescendants or child:IsA("ScrollingFrame") or child:IsA("CanvasGroup") then
					nextClip = { ax, ay, math.max(ax, bx), math.max(ay, by) }
				end
				walk(child, nextClip)
			elseif child:IsA("Folder") then
				walk(child, clip)
			end
		end
	end
	walk(root, nil)

	local top = {}
	for key, area in byKey do
		table.insert(top, { key, area / canvas })
	end
	table.sort(top, function(a, b)
		return a[2] > b[2]
	end)
	local kinds = {}
	for kind, area in byKind do
		kinds[kind] = math.round(area / canvas * 100) / 100
	end
	local trimmed = {}
	for index = 1, math.min(30, #top) do
		trimmed[index] = string.format("%.3f %s", top[index][2], top[index][1])
	end
	return {
		Overdraw = math.round(total / canvas * 100) / 100,
		Layers = layers,
		Viewports = viewports,
		CanvasGroups = canvasGroups,
		Kinds = kinds,
		Top = trimmed,
		Instances = #root:GetDescendants(),
	}
end

local function sample(seconds: number, onFrame: ((t: number) -> ())?)
	local acc = { Gpu = 0, RenderCpu = 0, Frame = 0, Dt = 0, UI3DDraw = 0, UI3DTri = 0, UI2DDraw = 0, UI2DTri = 0 }
	local worst = 0
	local frames = 0
	local start = os.clock()
	while os.clock() - start < seconds do
		local dt = RunService.RenderStepped:Wait()
		if onFrame then onFrame(os.clock() - start) end
		frames += 1
		acc.Gpu += Stats.RenderGPUFrameTime
		acc.RenderCpu += Stats.RenderCPUFrameTime
		acc.Frame += Stats.FrameTime
		acc.Dt += dt
		worst = math.max(worst, dt)
		acc.UI3DDraw += Stats.UI3DDrawcallCount
		acc.UI3DTri += Stats.UI3DTriangleCount
		acc.UI2DDraw += Stats.UI2DDrawcallCount
		acc.UI2DTri += Stats.UI2DTriangleCount
	end
	local out = { Frames = frames, WorstDtMs = math.round(worst * 1e5) / 100 }
	for key, value in acc do
		local mean = value / frames
		out[key] = if key == "Gpu" or key == "RenderCpu" or key == "Frame" or key == "Dt"
			then math.round(mean * 1e5) / 100
			else math.round(mean)
	end
	return out
end

local player = Players.LocalPlayer
local open
repeat
	task.wait(0.5)
	open = shared.BallarcBenchOpen
until open
-- Past the loading screen and the opening tweens.
task.wait(12)
local menu = player.PlayerGui:FindFirstChild("MenuUI", true) :: SurfaceGui

local scenes = {
	{ Name = "Lobby" },
	{ Name = "ShopBoxes", Page = "Shop", Category = 0 },
	{ Name = "ShopBundles", Page = "Shop", Category = "Bundles" },
	{ Name = "ShopDeals", Page = "Shop", Category = 4 },
	{ Name = "ShopTools", Page = "Shop", Category = 2 },
	{ Name = "ShopPremium", Page = "Shop", Category = 1 },
	{ Name = "SkillTree", Page = "SkillTree" },
	{ Name = "SkillTreeZoom", Page = "SkillTree", Zoom = true },
}

for _, scene in scenes do
	open(scene.Page, scene.Category)
	task.wait(SETTLE)
	local draw = measure(menu)
	local onFrame = nil
	if scene.Zoom then
		onFrame = function(t: number)
			local zoom = shared.BallarcBenchZoom
			if zoom then zoom(if math.floor(t / 0.8) % 2 == 0 then 3 else 0.5) end
		end
	end
	local perf = sample(SAMPLE, onFrame)
	if scene.Zoom and shared.BallarcBenchZoom then shared.BallarcBenchZoom(1) end
	print("BENCH|" .. HttpService:JSONEncode({ Label = LABEL, Scene = scene.Name, Perf = perf, Draw = draw }))
end
open(nil)
print("BENCH|DONE|" .. LABEL)
