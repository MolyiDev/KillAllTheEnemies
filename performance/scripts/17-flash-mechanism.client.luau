--!optimize 2
-- WHY DOES A POOLED HIGHLIGHT COST ~17ms AND A PRE-PARENTED ONE COST NOTHING?
--
-- 15-flash-bench found a 300x gap between two things that look like the same operation:
--
--     POOL -> Model / POOL -> MeshPart / POOL Adornee swap     +15 to +17ms on the flash frame
--     PRE in Model .Enabled / PRE in MeshPart .Enabled         +0.03 to +0.06ms
--
-- Adornee-swapping cost the same as reparenting, so the reparent is not the expensive part. The remaining
-- difference is WHICH MESH the highlight points at: a pool hands its highlight to whichever enemy needs one, so
-- the adornee is a different mesh every burst, while a pre-parented highlight adorns the same mesh forever.
--
-- HYPOTHESIS: the engine builds highlight geometry per (highlight, adornee) pair and caches it. Pointing a
-- highlight at a mesh it has not adorned before pays the build; toggling one that has already built is free.
--
-- If that is right then a pool is not inherently slow - a pool with a FIXED 1:1 mapping (highlight j always
-- serves enemy j) should be as cheap as the pre-parented case, and the pre-parented case should pay the same
-- build once, on its FIRST enable.
--
-- So this run:
--   * holds all flashing until the sample window opens, so burst #1 is genuinely COLD for every variant
--   * reports burst #1, #2, #3 separately from the median of #4 onwards
--   * adds POOL FIXED (same target every time) and PRE WARMED (enabled once at build, then disabled)
--   * adds FillTransparency 1<->0 as an alternative to .Enabled on an always-enabled highlight

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
local pool = table.create(TARGET_COUNT)
local flashed = table.create(TARGET_COUNT)
local lent = table.create(TARGET_COUNT)

local clockStart = 0
local focusLost = false
UserInputService.WindowFocusReleased:Connect(function()
	focusLost = true
end)

local poolFolder = nil
local root = nil

local burstK = 0
local burstStart = 0
local burstIndex = 0
local frameIndex = 0
local eventTag = 0
local armed = false -- bursts only fire once the sample window is open, so burst #1 is cold
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
	highlight.Enabled = true
	return highlight
end

-- preWarm: create the highlights enabled, let them render for a moment, then disable. If the build really is
-- cached per (highlight, adornee), this pays it up front and the sample never sees it.
local function buildScene(preMode, preWarm, hiddenBy)
	local folder = Instance.new("Folder")
	folder.Name = "MechDiag"
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

	if preMode then
		for j = 1, TARGET_COUNT do
			local highlight = newHighlight()
			highlight.Enabled = preWarm
			highlight.Parent = if preMode == "model" then models[targets[j]] else meshes[targets[j]]
			owned[j] = highlight
		end
	end

	folder.Parent = workspace

	if preMode and preWarm then
		task.wait(0.75) -- let them actually render before hiding them again
		for j = 1, TARGET_COUNT do
			if hiddenBy == "fill" then
				owned[j].FillTransparency = 1
			else
				owned[j].Enabled = false
			end
		end
	end

	root = folder
end

local function buildPool(size)
	local folder = Instance.new("Folder")
	folder.Name = "MechPool"
	folder.Parent = workspace
	for j = 1, size do
		local highlight = newHighlight()
		highlight.Adornee = nil
		highlight.Parent = folder
		pool[j] = highlight
	end
	poolFolder = folder
end

local function teardown()
	if root then
		root:Destroy()
		root = nil
	end
	if poolFolder then
		poolFolder:Destroy()
		poolFolder = nil
	end
	table.clear(meshes)
	table.clear(models)
	table.clear(surfaces)
	table.clear(owned)
	table.clear(pool)
	table.clear(flashed)
	table.clear(lent)
	task.wait(TEARDOWN_SECONDS)
end

local function moveAll(t)
	for i = 1, SCENE_N do
		meshes[i].CFrame = slotCFrame(i, t)
	end
end

-- Rotating: the PAIRING shifts every burst, so highlight j serves a different enemy each time. Shifting the
-- pairing rather than the target set matters - block B of 15-flash-bench used K = TARGET_COUNT, where the
-- rotation wrapped and every highlight silently landed back on its own target. That accidental fixed mapping is
-- why its Adornee row read +0.56ms while the K=24 rotating one read +15.38ms.
local function selectRotating()
	for j = 1, burstK do
		flashed[j] = (burstIndex + j - 2) % TARGET_COUNT + 1
	end
end

-- Fixed: highlight j always serves target j, burst after burst.
local function selectFixed()
	for j = 1, burstK do
		flashed[j] = j
	end
end

local function poolRotatingAdorneeOn()
	selectRotating()
	for j = 1, burstK do
		local highlight = pool[j]
		lent[j] = highlight
		highlight.Adornee = models[targets[flashed[j]]]
	end
end

local function poolFixedAdorneeOn()
	selectFixed()
	for j = 1, burstK do
		local highlight = pool[j]
		lent[j] = highlight
		highlight.Adornee = models[targets[j]]
	end
end

local function poolAdorneeOff()
	for j = 1, burstK do
		lent[j].Adornee = nil
	end
end

local function poolFixedParentOn()
	selectFixed()
	for j = 1, burstK do
		local highlight = pool[j]
		lent[j] = highlight
		highlight.Parent = models[targets[j]]
	end
end

local function poolParentOff()
	for j = 1, burstK do
		lent[j].Parent = poolFolder
	end
end

local function preEnabledOn()
	selectFixed()
	for j = 1, burstK do
		owned[j].Enabled = true
	end
end

local function preEnabledOff()
	for j = 1, burstK do
		owned[j].Enabled = false
	end
end

local function preFillOn()
	selectFixed()
	for j = 1, burstK do
		owned[j].FillTransparency = 0
	end
end

local function preFillOff()
	for j = 1, burstK do
		owned[j].FillTransparency = 1
	end
end

local function tintOn()
	selectRotating()
	for j = 1, burstK do
		surfaces[targets[flashed[j]]].Color = WHITE
	end
end

local function tintOff()
	for j = 1, burstK do
		surfaces[targets[flashed[j]]].Color = BASE_TINT
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
		burstStart += burstK
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
local CAM_AWAY = CFrame.new(Vector3.new(0, 0, CAM_DISTANCE), Vector3.new(0, 0, CAM_DISTANCE * 3))

local function sample(variant)
	camera.CFrame = if variant.CameraAway then CAM_AWAY else CAM_AT
	buildScene(variant.PreMode, variant.PreWarm == true, variant.HiddenBy)
	if variant.PoolSize then buildPool(variant.PoolSize) end

	burstK = variant.K or 0
	burstStart = 0
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
	armed = true -- first burst inside the window is the cold one
	local t0 = os.clock()
	task.wait(SAMPLE_SECONDS)
	recording = false
	armed = false
	local wall = os.clock() - t0

	local frames = #recDt
	local _, med, p95, worst = stats(recDt)
	local visible = countVisible()
	activeUpdate = nil

	-- Shifted by one, Luau stripped: engine cost of frame i shows up in dt at i+1.
	local quiet, warmOn, warmOff = {}, {}, {}
	local coldOn = {}
	for i = 1, frames - 1 do
		local engine = recDt[i + 1] - recUpd[i]
		local tag = recTag[i]
		if tag == 1 then
			local b = recBurst[i]
			if b <= 3 then
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
	local _, warmOnMed, _, warmOnWorst = stats(warmOn)
	local _, warmOffMed = stats(warmOff)

	print(
		string.format(
			"[MECH] %-28s K=%-4d | med=%7.2f p95=%7.2f worst=%8.2f | quiet=%6.2f  ON#1=%8.2f ON#2=%7.2f ON#3=%7.2f  ON#4+=%7.2f (n=%-3d d=%+7.2f max=%7.2f)  OFF=%6.2f (d=%+6.2f) | settle=%4.1fs%s vis=%d/%d fps=%5.1f%s",
			variant.Label,
			variant.K or 0,
			med,
			p95,
			worst,
			quietMed,
			coldOn[1] or -1,
			coldOn[2] or -1,
			coldOn[3] or -1,
			warmOnMed,
			#warmOn,
			warmOnMed - quietMed,
			warmOnWorst,
			warmOffMed,
			warmOffMed - quietMed,
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

	print("[BENCH] ===== flash mechanism: is the cost per (highlight, adornee) pair? =====")
	print("[BENCH] nothing flashes until the sample window opens, so ON#1 is a COLD build for every variant")

	-- K=1 is the load-bearing one: if rebinding a SINGLE highlight still costs ~15ms then the cost is a fixed
	-- global rebuild rather than per-highlight work, and no amount of budgeting makes a retargeting pool viable.
	for _, k in { 1, 24, 240 } do
		print(string.format("[BENCH] --- K=%d ---", k))
		sample({ Label = "SENTINEL move only", K = k })
		sample({ Label = "TINT SurfaceAppearance", K = k, On = tintOn, Off = tintOff })
		sample({
			Label = "POOL rotating Adornee",
			K = k,
			PoolSize = k,
			On = poolRotatingAdorneeOn,
			Off = poolAdorneeOff,
		})
		sample({ Label = "POOL FIXED Adornee", K = k, PoolSize = k, On = poolFixedAdorneeOn, Off = poolAdorneeOff })
		sample({ Label = "PRE Model .Enabled cold", K = k, PreMode = "model", On = preEnabledOn, Off = preEnabledOff })
		if k > 1 then
			sample({ Label = "POOL FIXED -> Model", K = k, PoolSize = k, On = poolFixedParentOn, Off = poolParentOff })
			sample({
				Label = "PRE Model .Enabled WARMED",
				K = k,
				PreMode = "model",
				PreWarm = true,
				On = preEnabledOn,
				Off = preEnabledOff,
			})
			sample({
				Label = "PRE Model FillTransparency",
				K = k,
				PreMode = "model",
				PreWarm = true,
				HiddenBy = "fill",
				On = preFillOn,
				Off = preFillOff,
			})
		end
	end

	-- Trap 9: if the rebind cost is render work it has to fall away when nothing is on screen. If it does not,
	-- it is CPU-side bookkeeping that happens whether the enemy is visible or not - which is worse.
	print("[BENCH] --- camera away ---")
	sample({ Label = "SENTINEL move only AWAY", K = 24, CameraAway = true })
	sample({
		Label = "POOL rotating Adornee AWAY",
		K = 24,
		PoolSize = 24,
		On = poolRotatingAdorneeOn,
		Off = poolAdorneeOff,
		CameraAway = true,
	})
	sample({
		Label = "PRE Model .Enabled AWAY",
		K = 24,
		PreMode = "model",
		On = preEnabledOn,
		Off = preEnabledOff,
		CameraAway = true,
	})

	print("[BENCH] ===== done =====")
end)
