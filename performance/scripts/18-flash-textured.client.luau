--!optimize 2
-- HOW DO YOU FLASH AN ENEMY WHITE WHEN ITS TEXTURE ALREADY NEEDS A WHITE TINT?
--
-- SurfaceAppearance.Color is a MULTIPLY over the ColorMap. The result is bounded above by the raw texture, so
-- the tint can darken or shift hue but can never brighten past what the ColorMap already is. An enemy authored
-- with a white tint has nowhere to go.
--
-- 13-damage-flash-tint-vs-highlight settled the Highlight question: free to toggle if it is permanently bound to
-- one mesh (+0.03ms), catastrophic if it is ever re-aimed (+17ms), and hard-capped at 255 instances in the whole
-- DataModel. Feed the Core's wave curve (BASE_COUNT 22, +4 per wave, x2.5 for a full party) crosses 255 alive, so a
-- highlight per enemy is not an architecture, it is a ceiling.
--
-- That leaves the candidates that are uncapped AND texture-agnostic:
--
--   SURFACE DETACH  set SurfaceAppearance.Parent = nil so the mesh falls back to MeshPart.Color / Material,
--                   pre-set to white Neon. Reattach to unflash. This is a hierarchy change, which is the same
--                   category of operation that made re-parenting a Highlight cost 17ms - so it is either the
--                   answer or it is disqualified, and one run settles which.
--   MATERIAL SWAP   set MeshPart.Material = Neon with the SurfaceAppearance still attached. Cheap for certain,
--                   but the SurfaceAppearance probably overrides it entirely, which would make it free and
--                   invisible. The visual probe decides that half; this measures the cost half.
--
-- TINT and PRE-BOUND HIGHLIGHT are carried over as references so the numbers sit on the same scale as doc 13.
-- Same scene as 15/17: 2400 slimes, all in frustum, 240 flash targets, burst every 30 frames for 6.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local SLIME = ReplicatedStorage:WaitForChild("Models"):WaitForChild("Enemies"):WaitForChild("Slime")

local SCENE_N = 2400
local TARGET_COUNT = 240
local CHUNK = 120

local BURST_PERIOD = 30
local FLASH_FRAMES = 6

local SETTLE_WINDOW = 1.0
local SETTLE_TOLERANCE = 0.10
local SETTLE_MAX_SECONDS = 20
local SAMPLE_SECONDS = 6.0
local TEARDOWN_SECONDS = 3.0

local AREA_WIDTH = 260
local AREA_HEIGHT = 140
local AREA_DEPTH = 40
local CAM_DISTANCE = 155
local ORBIT_RADIUS = 3
local ORBIT_SPEED = 1.7

local WHITE = Color3.new(1, 1, 1)
local BASE_TINT = SLIME:FindFirstChildWhichIsA("MeshPart"):FindFirstChildWhichIsA("SurfaceAppearance").Color

local slotX = table.create(SCENE_N)
local slotY = table.create(SCENE_N)
local slotZ = table.create(SCENE_N)
local phase = table.create(SCENE_N)

local meshes = table.create(SCENE_N)
local models = table.create(SCENE_N)
local surfaces = table.create(SCENE_N)
local owned = table.create(TARGET_COUNT)
local targets = table.create(TARGET_COUNT)

local clockStart = 0
local focusLost = false
UserInputService.WindowFocusReleased:Connect(function()
	focusLost = true
end)

local root = nil

local burstK = 0
local burstIndex = 0
local frameIndex = 0
local eventTag = 0
local armed = false
local flashOnFn = nil
local flashOffFn = nil

local function buildSlots()
	local columns = math.ceil(math.sqrt(SCENE_N * (AREA_WIDTH / AREA_HEIGHT)))
	local stepX = AREA_WIDTH / columns
	local rows = math.ceil(SCENE_N / columns)
	local stepY = AREA_HEIGHT / math.max(rows, 1)
	for i = 1, SCENE_N do
		local col = (i - 1) % columns
		local row = math.floor((i - 1) / columns)
		slotX[i] = -AREA_WIDTH * 0.5 + (col + 0.5) * stepX
		slotY[i] = -AREA_HEIGHT * 0.5 + (row + 0.5) * stepY
		slotZ[i] = ((i * 7919) % 1000) / 1000 * AREA_DEPTH - AREA_DEPTH * 0.5
		phase[i] = ((i * 4409) % 1000) / 1000 * math.pi * 2
	end
	local stride = math.floor(SCENE_N / TARGET_COUNT)
	for j = 1, TARGET_COUNT do
		targets[j] = (j - 1) * stride + 1
	end
end

local function slotCFrame(i, t)
	local a = t * ORBIT_SPEED + phase[i]
	return CFrame.new(slotX[i] + math.cos(a) * ORBIT_RADIUS, slotY[i] + math.sin(a) * ORBIT_RADIUS, slotZ[i])
		* CFrame.fromEulerAnglesYXZ(0, a, 0)
end

local function newHighlight()
	local highlight = Instance.new("Highlight")
	highlight.FillColor = WHITE
	highlight.FillTransparency = 0
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Enabled = false
	return highlight
end

-- underlay: paint the target MeshParts white Neon underneath the SurfaceAppearance, so detaching it reveals a
-- glowing white silhouette rather than the default grey.
local function buildScene(preHighlight, underlay)
	local folder = Instance.new("Folder")
	folder.Name = "TexDiag"
	local i = 1
	while i <= SCENE_N do
		local last = math.min(i + CHUNK - 1, SCENE_N)
		for k = i, last do
			local model = SLIME:Clone()
			local mesh = model:FindFirstChildWhichIsA("MeshPart")
			mesh.Anchored = true
			mesh.CanCollide = false
			mesh.CanQuery = false
			mesh.CanTouch = false
			mesh.CFrame = slotCFrame(k, 0)
			meshes[k] = mesh
			models[k] = model
			surfaces[k] = mesh:FindFirstChildWhichIsA("SurfaceAppearance")
			model.Parent = folder
		end
		i = last + 1
		task.wait()
	end

	if underlay then
		for j = 1, TARGET_COUNT do
			local mesh = meshes[targets[j]]
			mesh.Color = WHITE
			mesh.Material = Enum.Material.Neon
		end
	end

	if preHighlight then
		for j = 1, TARGET_COUNT do
			local highlight = newHighlight()
			highlight.Parent = models[targets[j]]
			owned[j] = highlight
		end
	end

	folder.Parent = workspace
	root = folder
end

local function teardown()
	if root then
		root:Destroy()
		root = nil
	end
	table.clear(meshes)
	table.clear(models)
	table.clear(surfaces)
	table.clear(owned)
	task.wait(TEARDOWN_SECONDS)
end

local function moveAll(t)
	for i = 1, SCENE_N do
		meshes[i].CFrame = slotCFrame(i, t)
	end
end

local function tintOn()
	for j = 1, burstK do
		surfaces[targets[j]].Color = WHITE
	end
end

local function tintOff()
	for j = 1, burstK do
		surfaces[targets[j]].Color = BASE_TINT
	end
end

local function detachOn()
	for j = 1, burstK do
		surfaces[targets[j]].Parent = nil
	end
end

local function detachOff()
	for j = 1, burstK do
		local idx = targets[j]
		surfaces[idx].Parent = meshes[idx]
	end
end

local function materialOn()
	for j = 1, burstK do
		meshes[targets[j]].Material = Enum.Material.Neon
	end
end

local function materialOff()
	for j = 1, burstK do
		meshes[targets[j]].Material = Enum.Material.Plastic
	end
end

local function highlightOn()
	for j = 1, burstK do
		owned[j].Enabled = true
	end
end

local function highlightOff()
	for j = 1, burstK do
		owned[j].Enabled = false
	end
end

local function noop() end

local function updateFlash()
	local t = os.clock() - clockStart
	moveAll(t)

	eventTag = 0
	if not armed then return end

	local slot = frameIndex % BURST_PERIOD
	if slot == 0 then
		burstIndex += 1
		flashOnFn()
		eventTag = 1
	elseif slot == FLASH_FRAMES then
		flashOffFn()
		eventTag = 2
	end
	frameIndex += 1
end

local recDt = table.create(8192)
local recUpd = table.create(8192)
local recTag = table.create(8192)
local recBurst = table.create(8192)
local recording = false
local activeUpdate = nil

RunService.PreRender:Connect(function(dt)
	local update = activeUpdate
	local cost = 0
	if update then
		local s = os.clock()
		update()
		cost = os.clock() - s
	end
	if not recording then return end
	local n = #recDt + 1
	recDt[n] = dt
	recUpd[n] = cost
	recTag[n] = eventTag
	recBurst[n] = burstIndex
end)

local function stats(list)
	local n = #list
	if n == 0 then return 0, 0, 0, 0 end
	local sum, worst = 0, 0
	for i = 1, n do
		sum += list[i]
		if list[i] > worst then worst = list[i] end
	end
	local sorted = table.clone(list)
	table.sort(sorted)
	return sum / n * 1000,
		sorted[math.max(math.floor(n * 0.5), 1)] * 1000,
		sorted[math.clamp(math.ceil(0.95 * n), 1, n)] * 1000,
		worst * 1000
end

local function settleUntilStable()
	local start = os.clock()
	local prevMed, agreements = nil, 0
	while os.clock() - start < SETTLE_MAX_SECONDS do
		table.clear(recDt)
		table.clear(recUpd)
		table.clear(recTag)
		table.clear(recBurst)
		recording = true
		task.wait(SETTLE_WINDOW)
		recording = false
		local _, med = stats(recDt)
		if med > 0 and prevMed and prevMed > 0 then
			if math.abs(med - prevMed) / prevMed < SETTLE_TOLERANCE then
				agreements += 1
				if agreements >= 2 then return os.clock() - start, true end
			else
				agreements = 0
			end
		end
		prevMed = med
	end
	return os.clock() - start, false
end

local function countVisible()
	local visible = 0
	for i = 1, SCENE_N do
		local _, onScreen = camera:WorldToViewportPoint(meshes[i].Position)
		if onScreen then
			visible += 1
		end
	end
	return visible
end

local CAM_AT = CFrame.new(Vector3.new(0, 0, CAM_DISTANCE), Vector3.zero)

local function sample(variant)
	camera.CFrame = CAM_AT
	buildScene(variant.PreHighlight, variant.Underlay)

	burstK = variant.K or 0
	burstIndex = 0
	frameIndex = 0
	eventTag = 0
	armed = false
	flashOnFn = variant.On or noop
	flashOffFn = variant.Off or noop
	clockStart = os.clock()
	focusLost = false
	activeUpdate = updateFlash

	local settleSeconds, converged = settleUntilStable()

	table.clear(recDt)
	table.clear(recUpd)
	table.clear(recTag)
	table.clear(recBurst)
	recording = true
	armed = true
	local t0 = os.clock()
	task.wait(SAMPLE_SECONDS)
	recording = false
	armed = false
	local wall = os.clock() - t0

	local frames = #recDt
	local _, med, p95, worst = stats(recDt)
	local visible = countVisible()
	activeUpdate = nil

	local quiet, warmOn, warmOff = {}, {}, {}
	local coldOn = {}
	for i = 1, frames - 1 do
		local engine = recDt[i + 1] - recUpd[i]
		local tag = recTag[i]
		if tag == 1 then
			local b = recBurst[i]
			if b <= 2 then
				coldOn[b] = engine * 1000
			else
				warmOn[#warmOn + 1] = engine
			end
		elseif tag == 2 then
			warmOff[#warmOff + 1] = engine
		else
			quiet[#quiet + 1] = engine
		end
	end

	local _, quietMed = stats(quiet)
	local _, onMed, _, onWorst = stats(warmOn)
	local _, offMed, _, offWorst = stats(warmOff)

	print(
		string.format(
			"[TEX] %-26s K=%-4d | med=%7.2f p95=%7.2f worst=%8.2f | quiet=%6.2f ON#1=%8.2f ON#2=%7.2f ON=%7.2f (n=%-3d d=%+8.2f max=%8.2f) OFF=%7.2f (d=%+8.2f max=%8.2f) | settle=%4.1fs%s vis=%d/%d fps=%5.1f%s",
			variant.Label,
			variant.K or 0,
			med,
			p95,
			worst,
			quietMed,
			coldOn[1] or -1,
			coldOn[2] or -1,
			onMed,
			#warmOn,
			onMed - quietMed,
			onWorst,
			offMed,
			offMed - quietMed,
			offWorst,
			settleSeconds,
			if converged then " ok" else " NO",
			visible,
			SCENE_N,
			frames / wall,
			if focusLost then "  *** FOCUS LOST ***" else ""
		)
	)

	teardown()
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
	camera.CFrame = CAM_AT

	buildSlots()

	print("[BENCH] ===== texture-safe white flash: what is uncapped AND cheap? =====")

	for _, k in { 24, 240 } do
		print(string.format("[BENCH] --- K=%d ---", k))
		sample({ Label = "SENTINEL move only", K = k })
		sample({ Label = "TINT white (reference)", K = k, On = tintOn, Off = tintOff })
		sample({ Label = "SURFACE detach / reattach", K = k, Underlay = true, On = detachOn, Off = detachOff })
		sample({ Label = "MATERIAL Neon swap", K = k, On = materialOn, Off = materialOff })
		sample({
			Label = "HIGHLIGHT bound (reference)",
			K = k,
			PreHighlight = true,
			On = highlightOn,
			Off = highlightOff,
		})
	end

	print("[BENCH] ===== done =====")
end)
