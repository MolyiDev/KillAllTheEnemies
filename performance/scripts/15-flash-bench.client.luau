--!optimize 2
-- DAMAGE FLASH: SurfaceAppearance tint vs five ways of driving a Highlight.
--
-- The question is which mechanism to use for the white "I got hit" flash on enemies. Six candidates:
--
--   TINT        write SurfaceAppearance.Color = white, write it back on flash end
--   POOL->MODEL take a Highlight from a pool and parent it to the enemy Model, return it on flash end
--   POOL->MESH  same, parented to the MeshPart instead
--   POOL ADORNEE keep the Highlight parked in the pool and only point Adornee at the target (extra row, not
--               asked for, but it is the same pooled highlight without paying the reparent)
--   PRE MODEL   one Highlight already sitting in every enemy Model, flash = Enabled true/false
--   PRE MESH    same, sitting in the MeshPart
--
-- SCENE. 2400 slimes on a deterministic grid, every one inside the frustum, each moved every frame by writing
-- MeshPart.CFrame. That movement costs ~6.6ms of Luau per frame, which is the point: it lifts the whole scene
-- clear of the 240 FPS cap (atCap 0.0% in calibration) so a flash costing 0.3ms is visible instead of being
-- swallowed by a floored 4.167ms frame (METHODOLOGY trap 2). Static ballast could not do this (trap 3).
--
-- TARGETS. Only 240 of the 2400 slimes are flash targets, spread every 10th slot so they cover the whole grid.
-- 240 is not an arbitrary number: the engine allows 255 Highlight instances in the DataModel, full stop, so a
-- one-Highlight-per-enemy scheme cannot be tested - or shipped - above that. The pooled variants only ever
-- allocate as many highlights as flash simultaneously.
--
-- BURST. Every 30 frames K targets flash together; 6 frames later they all unflash. Frames are tagged ON, OFF
-- or QUIET and reported separately, shifted by one frame because PreRender's dt bills frame N's work to N+1.
-- A geometry rebuild shows up as a spike on exactly the ON/OFF frames and nowhere else. Both K=24 (a plausible
-- number of enemies taking damage at once) and K=240 (all of them, worst case) are run.
--
-- CONTROLS. A move-only sentinel runs at the start and end of every block (trap 5), block B is repeated in
-- reverse order, and the two most expensive variants are re-run with the camera turned away (trap 9).

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Stats = game:GetService("Stats")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local SLIME = ReplicatedStorage:WaitForChild("Models"):WaitForChild("Enemies"):WaitForChild("Slime")

local SCENE_N = 2400
local TARGET_COUNT = 240
local CHUNK = 120

local BURST_PERIOD = 30 -- frames between flashes
local FLASH_FRAMES = 6 -- how long a flash stays up

local SETTLE_WINDOW = 1.0
local SETTLE_TOLERANCE = 0.10
local SETTLE_MAX_SECONDS = 20
local SAMPLE_SECONDS = 5.0
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
local owned = table.create(TARGET_COUNT) -- highlight living inside target j, when the variant pre-parents them
local targets = table.create(TARGET_COUNT) -- scene index of target j
local pool = table.create(TARGET_COUNT)
local flashed = table.create(TARGET_COUNT) -- target slots lit by the current burst
local lent = table.create(TARGET_COUNT) -- highlight handed to flashed[j]

local clockStart = 0
local focusLost = false
UserInputService.WindowFocusReleased:Connect(function()
	focusLost = true
end)

local poolFolder = nil
local root = nil

local burstK = 0
local burstStart = 0
local frameIndex = 0
local eventTag = 0 -- 0 quiet, 1 flash on, 2 flash off
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

-- preMode: nil | "model" | "mesh" - where a per-target Highlight is pre-parented, and how it starts.
local function buildScene(preMode, preEnabled)
	local folder = Instance.new("Folder")
	folder.Name = "FlashDiag"
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
			local idx = targets[j]
			local highlight = newHighlight()
			highlight.Enabled = preEnabled
			highlight.Parent = if preMode == "model" then models[idx] else meshes[idx]
			owned[j] = highlight
		end
	end

	folder.Parent = workspace
	root = folder
end

local function buildPool(size)
	local folder = Instance.new("Folder")
	folder.Name = "FlashPool"
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

-- Pick this burst's K targets, deterministically rotating through the population.
local function selectBurst()
	for j = 1, burstK do
		flashed[j] = (burstStart + j - 1) % TARGET_COUNT + 1
	end
end

local function tintOn()
	selectBurst()
	for j = 1, burstK do
		surfaces[targets[flashed[j]]].Color = WHITE
	end
end

local function tintOff()
	for j = 1, burstK do
		surfaces[targets[flashed[j]]].Color = BASE_TINT
	end
end

local function poolModelOn()
	selectBurst()
	for j = 1, burstK do
		local highlight = pool[j]
		lent[j] = highlight
		highlight.Parent = models[targets[flashed[j]]]
	end
end

local function poolModelOff()
	for j = 1, burstK do
		lent[j].Parent = poolFolder
	end
end

local function poolMeshOn()
	selectBurst()
	for j = 1, burstK do
		local highlight = pool[j]
		lent[j] = highlight
		highlight.Parent = meshes[targets[flashed[j]]]
	end
end

local function poolMeshOff()
	for j = 1, burstK do
		lent[j].Parent = poolFolder
	end
end

local function poolAdorneeOn()
	selectBurst()
	for j = 1, burstK do
		local highlight = pool[j]
		lent[j] = highlight
		highlight.Adornee = models[targets[flashed[j]]]
	end
end

local function poolAdorneeOff()
	for j = 1, burstK do
		lent[j].Adornee = nil
	end
end

local function preOn()
	selectBurst()
	for j = 1, burstK do
		owned[flashed[j]].Enabled = true
	end
end

local function preOff()
	for j = 1, burstK do
		owned[flashed[j]].Enabled = false
	end
end

local function noop() end

local function updateFlash()
	local t = os.clock() - clockStart
	moveAll(t)

	local slot = frameIndex % BURST_PERIOD
	if slot == 0 then
		flashOnFn()
		eventTag = 1
	elseif slot == FLASH_FRAMES then
		flashOffFn()
		burstStart += burstK
		eventTag = 2
	else
		eventTag = 0
	end
	frameIndex += 1
end

local recDt = table.create(8192)
local recUpd = table.create(8192)
local recTag = table.create(8192)
local recAt = table.create(8192)
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
	recAt[n] = os.clock()
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
		table.clear(recAt)
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
	local visibleAll, visibleTargets = 0, 0
	for i = 1, SCENE_N do
		local _, onScreen = camera:WorldToViewportPoint(meshes[i].Position)
		if onScreen then
			visibleAll += 1
		end
	end
	for j = 1, TARGET_COUNT do
		local _, onScreen = camera:WorldToViewportPoint(meshes[targets[j]].Position)
		if onScreen then
			visibleTargets += 1
		end
	end
	return visibleAll, visibleTargets
end

local CAM_AT = CFrame.new(Vector3.new(0, 0, CAM_DISTANCE), Vector3.zero)
local CAM_AWAY = CFrame.new(Vector3.new(0, 0, CAM_DISTANCE), Vector3.new(0, 0, CAM_DISTANCE * 3))

-- variant = { Label, K, PreMode, PreEnabled, PoolSize, On, Off, CameraAway }
local function sample(variant)
	camera.CFrame = if variant.CameraAway then CAM_AWAY else CAM_AT

	local memBefore = Stats:GetTotalMemoryUsageMb()
	local buildStart = os.clock()
	buildScene(variant.PreMode, variant.PreEnabled == true)
	if variant.PoolSize then buildPool(variant.PoolSize) end
	local buildWall = (os.clock() - buildStart) * 1000

	burstK = variant.K or 0
	burstStart = 0
	frameIndex = 0
	eventTag = 0
	flashOnFn = variant.On or noop
	flashOffFn = variant.Off or noop
	clockStart = os.clock()
	focusLost = false
	activeUpdate = updateFlash

	local settleSeconds, converged = settleUntilStable()

	table.clear(recDt)
	table.clear(recUpd)
	table.clear(recTag)
	table.clear(recAt)
	recording = true
	local t0 = os.clock()
	task.wait(SAMPLE_SECONDS)
	recording = false
	local wall = os.clock() - t0

	local frames = #recDt
	local mean, med, p95, worst = stats(recDt)
	local memMb = Stats:GetTotalMemoryUsageMb() - memBefore
	local visibleAll, visibleTargets = countVisible()
	activeUpdate = nil

	local capped, updSum = 0, 0
	for i = 1, frames do
		if recDt[i] < 0.00435 then
			capped += 1
		end
		updSum += recUpd[i]
	end

	-- Shifted by one: frame N's work is billed to the dt reported at N+1. Engine time strips the Luau cost.
	local onEngine, offEngine, quietEngine = {}, {}, {}
	local onFrame, offFrame, quietFrame = {}, {}, {}
	for i = 1, frames - 1 do
		local engine = recDt[i + 1] - recUpd[i]
		local tag = recTag[i]
		if tag == 1 then
			onEngine[#onEngine + 1] = engine
			onFrame[#onFrame + 1] = recDt[i + 1]
		elseif tag == 2 then
			offEngine[#offEngine + 1] = engine
			offFrame[#offFrame + 1] = recDt[i + 1]
		else
			quietEngine[#quietEngine + 1] = engine
			quietFrame[#quietFrame + 1] = recDt[i + 1]
		end
	end

	local _, onMed, _, onWorst = stats(onEngine)
	local _, offMed, _, offWorst = stats(offEngine)
	local _, quietMed = stats(quietEngine)
	local _, onFrameMed = stats(onFrame)
	local _, offFrameMed = stats(offFrame)
	local _, quietFrameMed = stats(quietFrame)

	print(
		string.format(
			"[FLASH] %-26s K=%-4d | fps=%6.1f mean=%7.2f med=%7.2f p95=%7.2f worst=%8.2f script=%7.0fus atCap=%4.0f%% mem=%5.0fMB build=%5.0fms settle=%4.1fs%s vis=%d/%d t=%d/%d",
			variant.Label,
			variant.K or 0,
			frames / wall,
			mean,
			med,
			p95,
			worst,
			updSum / math.max(frames, 1) * 1e6,
			capped / math.max(frames, 1) * 100,
			memMb,
			buildWall,
			settleSeconds,
			if converged then " ok" else " NO",
			visibleAll,
			SCENE_N,
			visibleTargets,
			TARGET_COUNT
		)
	)

	print(
		string.format(
			"        engine  quiet=%7.2f  ON=%7.2f (n=%-3d d=%+7.2f max=%8.2f)  OFF=%7.2f (n=%-3d d=%+7.2f max=%8.2f) | frame quiet=%7.2f ON=%7.2f OFF=%7.2f%s",
			quietMed,
			onMed,
			#onEngine,
			onMed - quietMed,
			onWorst,
			offMed,
			#offEngine,
			offMed - quietMed,
			offWorst,
			quietFrameMed,
			onFrameMed,
			offFrameMed,
			if focusLost then "  *** FOCUS LOST ***" else ""
		)
	)

	teardown()
end

local function moveOnly(label)
	return { Label = label, K = 0 }
end

local function tint(k)
	return { Label = "TINT SurfaceAppearance", K = k, On = tintOn, Off = tintOff }
end

local function poolModel(k, away)
	return { Label = "POOL -> Model", K = k, PoolSize = k, On = poolModelOn, Off = poolModelOff, CameraAway = away }
end

local function poolMesh(k)
	return { Label = "POOL -> MeshPart", K = k, PoolSize = k, On = poolMeshOn, Off = poolMeshOff }
end

local function poolAdornee(k)
	return { Label = "POOL Adornee swap", K = k, PoolSize = k, On = poolAdorneeOn, Off = poolAdorneeOff }
end

local function preModel(k, away)
	return { Label = "PRE in Model .Enabled", K = k, PreMode = "model", On = preOn, Off = preOff, CameraAway = away }
end

local function preMesh(k)
	return { Label = "PRE in MeshPart .Enabled", K = k, PreMode = "mesh", On = preOn, Off = preOff }
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

	print(
		string.format(
			"[BENCH] ===== damage flash: tint vs highlight ===== scene=%d targets=%d burst=every %df for %df baseTint=%s",
			SCENE_N,
			TARGET_COUNT,
			BURST_PERIOD,
			FLASH_FRAMES,
			tostring(BASE_TINT)
		)
	)

	print("[BENCH] --- block A: K=24 flashing at once ---")
	sample(moveOnly("SENTINEL move only"))
	sample(tint(24))
	sample(poolModel(24))
	sample(poolMesh(24))
	sample(poolAdornee(24))
	sample(preModel(24))
	sample(preMesh(24))
	sample(moveOnly("SENTINEL move only"))

	print("[BENCH] --- block B: K=240 flashing at once (all targets) ---")
	sample(tint(240))
	sample(poolModel(240))
	sample(poolMesh(240))
	sample(poolAdornee(240))
	sample(preModel(240))
	sample(preMesh(240))
	sample(moveOnly("SENTINEL move only"))

	print("[BENCH] --- block C: standing cost of 240 highlight instances, never toggled ---")
	sample({ Label = "PRE Model, all DISABLED", K = 0, PreMode = "model", PreEnabled = false })
	sample({ Label = "PRE Model, all ENABLED", K = 0, PreMode = "model", PreEnabled = true })
	sample({ Label = "PRE Mesh, all ENABLED", K = 0, PreMode = "mesh", PreEnabled = true })
	sample({ Label = "POOL 240 idle in workspace", K = 0, PoolSize = 240 })
	sample(moveOnly("SENTINEL move only"))

	print("[BENCH] --- block D: block B again, reversed (drift check) ---")
	sample(preMesh(240))
	sample(preModel(240))
	sample(poolAdornee(240))
	sample(poolMesh(240))
	sample(poolModel(240))
	sample(tint(240))
	sample(moveOnly("SENTINEL move only"))

	print("[BENCH] --- block E: camera away (is any of this render cost at all?) ---")
	sample(poolModel(240, true))
	sample(preModel(240, true))
	sample({ Label = "SENTINEL move only AWAY", K = 0, CameraAway = true })

	print("[BENCH] ===== done =====")
end)
