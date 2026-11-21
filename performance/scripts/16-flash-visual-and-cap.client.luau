--!optimize 2
-- DOES EACH FLASH METHOD ACTUALLY LOOK LIKE A FLASH, AND WHERE DOES THE HIGHLIGHT CAP BITE?
--
-- The timing benchmark (15-flash-bench) says what each mechanism costs. It cannot say whether the result is
-- visible, and two of these can silently do nothing:
--
--   SurfaceAppearance.Color is a MULTIPLY over the ColorMap, not a paint. Writing white removes the tint, it
--   does not add light. On this slime the authored tint is a dark blue (0.055, 0.624, 0.812), so white should
--   read as a bright flash - but that is a property of THIS asset, not of the technique.
--
--   Highlight has a hard engine cap. Past it, highlights simply do not render, with no error. A one-per-enemy
--   scheme therefore has a maximum enemy count baked into it.
--
-- Stages are driven by an attribute on Workspace so each state can be held still and screenshotted:
--     workspace:SetAttribute("FlashProbeStage", n)   -- from the server
--
--   1  six slimes side by side: reference, tint, pool->Model, pool->MeshPart, pre-in-Model, Adornee
--   2  300 slimes, ONE HIGHLIGHT EACH, all enabled - how many actually render?
--   3  300 slimes, 250 highlights - the control, all of these should render
--   4  300 slimes, SurfaceAppearance white on every one - the tint has no cap

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local SLIME = ReplicatedStorage:WaitForChild("Models"):WaitForChild("Enemies"):WaitForChild("Slime")
local WHITE = Color3.new(1, 1, 1)
local BASE_TINT = SLIME:FindFirstChildWhichIsA("MeshPart"):FindFirstChildWhichIsA("SurfaceAppearance").Color

local GRID_N = 300
local GRID_HIGHLIGHTS = 250
local AREA_WIDTH = 260
local AREA_HEIGHT = 140
local CAM_DISTANCE = 155

local root = nil

local function newHighlight()
	local highlight = Instance.new("Highlight")
	highlight.FillColor = WHITE
	highlight.FillTransparency = 0
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Enabled = true
	return highlight
end

local function spawnSlime(parent, cf)
	local model = SLIME:Clone()
	local mesh = model:FindFirstChildWhichIsA("MeshPart")
	mesh.Anchored = true
	mesh.CanCollide = false
	mesh.CanQuery = false
	mesh.CanTouch = false
	mesh.CFrame = cf
	model.Parent = parent
	return model, mesh
end

local function clear()
	if root then
		root:Destroy()
		root = nil
	end
end

-- Stage 1: one slime per technique, in a row, close up.
local function stageSideBySide()
	clear()
	local folder = Instance.new("Folder")
	folder.Name = "FlashProbe"

	local pool = Instance.new("Folder")
	pool.Name = "ProbePool"
	pool.Parent = folder

	-- Highlight-in-Model is deliberately only one slot: pool->Model and pre-in-Model differ in WHEN the highlight
	-- gets there, not in what ends up on screen, so drawing both would just be the same picture twice. The sixth
	-- slot spends itself on something the timing run does not cover instead - what DepthMode actually looks like.
	local labels =
		{ "reference", "tint white", "highlight in Model", "highlight in MeshPart", "Adornee", "AlwaysOnTop" }
	for i = 1, 6 do
		local model, mesh = spawnSlime(folder, CFrame.new((i - 3.5) * 6, 0, 0))
		local surface = mesh:FindFirstChildWhichIsA("SurfaceAppearance")

		if i == 2 then
			surface.Color = WHITE
		elseif i == 3 then
			newHighlight().Parent = model
		elseif i == 4 then
			newHighlight().Parent = mesh
		elseif i == 5 then
			local highlight = newHighlight()
			highlight.Parent = pool
			highlight.Adornee = model
		elseif i == 6 then
			local highlight = newHighlight()
			highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			highlight.Parent = model
		end
	end

	folder.Parent = workspace
	root = folder
	camera.CFrame = CFrame.new(Vector3.new(0, 2, 22), Vector3.new(0, 0, 0))
	print(string.format("[VIS] stage 1  left to right: %s", table.concat(labels, " | ")))
end

-- Stages 2-4: a countable grid. highlights = how many slimes get their own Highlight; tintAll paints every
-- slime with the SurfaceAppearance instead.
local function stageGrid(stage, highlights, tintAll)
	clear()
	local folder = Instance.new("Folder")
	folder.Name = "FlashProbe"

	local columns = math.ceil(math.sqrt(GRID_N * (AREA_WIDTH / AREA_HEIGHT)))
	local rows = math.ceil(GRID_N / columns)
	local stepX = AREA_WIDTH / columns
	local stepY = AREA_HEIGHT / math.max(rows, 1)

	local made = 0
	for i = 1, GRID_N do
		local col = (i - 1) % columns
		local row = math.floor((i - 1) / columns)
		local cf = CFrame.new(-AREA_WIDTH * 0.5 + (col + 0.5) * stepX, -AREA_HEIGHT * 0.5 + (row + 0.5) * stepY, 0)
		local model, mesh = spawnSlime(folder, cf)
		if tintAll then
			mesh:FindFirstChildWhichIsA("SurfaceAppearance").Color = WHITE
		elseif i <= highlights then
			newHighlight().Parent = model
			made += 1
		end
	end

	folder.Parent = workspace
	root = folder
	camera.CFrame = CFrame.new(Vector3.new(0, 0, CAM_DISTANCE), Vector3.zero)

	local live = 0
	for _, descendant in workspace:GetDescendants() do
		if descendant:IsA("Highlight") then
			live += 1
		end
	end
	print(
		string.format(
			"[VIS] stage %d  slimes=%d highlightsCreated=%d liveInWorkspace=%d tintAll=%s",
			stage,
			GRID_N,
			made,
			live,
			tostring(tintAll == true)
		)
	)
end

local function applyStage(stage)
	if stage == 1 then
		stageSideBySide()
	elseif stage == 2 then
		stageGrid(2, GRID_N, false)
	elseif stage == 3 then
		stageGrid(3, GRID_HIGHLIGHTS, false)
	elseif stage == 4 then
		stageGrid(4, 0, true)
	elseif stage == 0 then
		clear()
		print("[VIS] cleared")
	end
end

task.spawn(function()
	task.wait(3)
	local character = player.Character or player.CharacterAdded:Wait()
	local hrp = character:WaitForChild("HumanoidRootPart", 10)
	if hrp then
		hrp.Anchored = true
		hrp.CFrame = CFrame.new(0, 500, 0)
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 70

	print(
		string.format("[VIS] ready. baseTint=%s  set workspace attribute FlashProbeStage to 1..4", tostring(BASE_TINT))
	)

	workspace:GetAttributeChangedSignal("FlashProbeStage"):Connect(function()
		local stage = workspace:GetAttribute("FlashProbeStage")
		if typeof(stage) == "number" then applyStage(stage) end
	end)

	applyStage(1)
end)
