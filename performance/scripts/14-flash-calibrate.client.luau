--!optimize 2
-- CALIBRATION PASS for the damage-flash benchmark (doc 13).
--
-- Three jobs, none of them a result on their own:
--
--   1. WHERE DOES THE SCENE LEAVE THE 240 FPS CAP? A flash that costs 2ms is invisible in a scene pinned at
--      4.167ms (METHODOLOGY trap 2). Sweep slime counts on movement alone and find the count whose settled
--      median is comfortably above the cap but not yet thrashing.
--
--   2. IS EVERY MECHANISM WRITABLE FROM A LOCALSCRIPT AND DOES IT STICK? Trap 10 - a property that turns out to
--      need Plugin capability kills a run silently.
--
--   3. WHAT DOES ONE WRITE COST IN RAW LUAU? The frame-based burst analysis in the main run measures the ENGINE
--      side; this measures the instruction side, so the two can be separated later. Note these writes happen
--      outside PreRender, so any deferred render work is NOT counted here - that is the point.
--
-- The highlight cap is the constraint that shapes the whole benchmark: only 255 Highlight instances may exist in
-- the DataModel, so any "one highlight per enemy" scheme is bounded at 255 enemies no matter what it costs.
-- Nothing here can exceed 240 highlights at once.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local SLIME = ReplicatedStorage:WaitForChild("Models"):WaitForChild("Enemies"):WaitForChild("Slime")

local COUNTS = { 240, 600, 1200, 2400, 3600 }
local CHUNK = 120
local SETTLE_WINDOW = 1.0
local SETTLE_TOLERANCE = 0.10
local SETTLE_MAX_SECONDS = 30
local SAMPLE_SECONDS = 4.0
local TEARDOWN_SECONDS = 3.0

local AREA_WIDTH = 260
local AREA_HEIGHT = 140
local AREA_DEPTH = 40
local CAM_DISTANCE = 155
local ORBIT_RADIUS = 3
local ORBIT_SPEED = 1.7

local MICRO_ENTITIES = 100
local MICRO_ITERATIONS = 2000

local WHITE = Color3.new(1, 1, 1)

local count = 0
local slotX = table.create(8192)
local slotY = table.create(8192)
local slotZ = table.create(8192)
local phase = table.create(8192)
local meshes = table.create(8192)

local clockStart = 0
local focusLost = false
UserInputService.WindowFocusReleased:Connect(function()
	focusLost = true
end)

local function buildSlots(n)
	count = n
	local columns = math.ceil(math.sqrt(n * (AREA_WIDTH / AREA_HEIGHT)))
	local rows = math.ceil(n / columns)
	local stepX = AREA_WIDTH / columns
	local stepY = AREA_HEIGHT / math.max(rows, 1)
	for i = 1, n do
		local col = (i - 1) % columns
		local row = math.floor((i - 1) / columns)
		slotX[i] = -AREA_WIDTH * 0.5 + (col + 0.5) * stepX
		slotY[i] = -AREA_HEIGHT * 0.5 + (row + 0.5) * stepY
		slotZ[i] = ((i * 7919) % 1000) / 1000 * AREA_DEPTH - AREA_DEPTH * 0.5
		phase[i] = ((i * 4409) % 1000) / 1000 * math.pi * 2
	end
end

local function slotCFrame(i, t)
	local a = t * ORBIT_SPEED + phase[i]
	return CFrame.new(slotX[i] + math.cos(a) * ORBIT_RADIUS, slotY[i] + math.sin(a) * ORBIT_RADIUS, slotZ[i])
		* CFrame.fromEulerAnglesYXZ(0, a, 0)
end

local recDt = table.create(65536)
local recAt = table.create(65536)
local recording = false
local activeUpdate = nil
local updateTotal = 0
local updateFrames = 0

RunService.PreRender:Connect(function(dt)
	local update = activeUpdate
	if update then
		local s = os.clock()
		update()
		updateTotal += os.clock() - s
		updateFrames += 1
	end
	if not recording then return end
	local n = #recDt + 1
	recDt[n] = dt
	recAt[n] = os.clock()
end)

local function window(t0, t1)
	local out = {}
	for i = 1, #recDt do
		local at = recAt[i]
		if at >= t0 and at <= t1 then out[#out + 1] = recDt[i] end
	end
	return out
end

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
	local med = sorted[math.max(math.floor(n * 0.5), 1)] * 1000
	local p95 = sorted[math.clamp(math.ceil(0.95 * n), 1, n)] * 1000
	return sum / n * 1000, med, p95, worst * 1000
end

local root = nil

local function buildSlimes(n)
	local folder = Instance.new("Folder")
	folder.Name = "FlashCalib"
	local i = 1
	while i <= n do
		local last = math.min(i + CHUNK - 1, n)
		for k = i, last do
			local model = SLIME:Clone()
			local mesh = model:FindFirstChildWhichIsA("MeshPart")
			mesh.Anchored = true
			mesh.CanCollide = false
			mesh.CanQuery = false
			mesh.CanTouch = false
			mesh.CFrame = slotCFrame(k, 0)
			meshes[k] = mesh
			model.Parent = folder
		end
		i = last + 1
		task.wait()
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
	task.wait(TEARDOWN_SECONDS)
end

local function updateMove()
	local t = os.clock() - clockStart
	for i = 1, count do
		meshes[i].CFrame = slotCFrame(i, t)
	end
end

-- How many of the slimes are actually inside the frustum. A benchmark rendering half its scene off screen is
-- measuring the update loop and calling it a frame time (METHODOLOGY trap 9).
local function countVisible(n)
	local visible = 0
	for i = 1, n do
		local mesh = meshes[i]
		if mesh then
			local _, onScreen = camera:WorldToViewportPoint(mesh.Position)
			if onScreen then
				visible += 1
			end
		end
	end
	return visible
end

local function settleUntilStable()
	local start = os.clock()
	local prevMed = nil
	local agreements = 0

	while os.clock() - start < SETTLE_MAX_SECONDS do
		table.clear(recDt)
		table.clear(recAt)
		recording = true
		local t0 = os.clock()
		task.wait(SETTLE_WINDOW)
		recording = false
		local _, med = stats(window(t0, os.clock()))

		if med > 0 and prevMed and prevMed > 0 then
			local drift = math.abs(med - prevMed) / prevMed
			if drift < SETTLE_TOLERANCE then
				agreements += 1
				if agreements >= 2 then return os.clock() - start, true, med end
			else
				agreements = 0
			end
		end
		prevMed = med
	end

	return os.clock() - start, false, prevMed or 0
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
	camera.CFrame = CFrame.new(Vector3.new(0, 0, CAM_DISTANCE), Vector3.zero)

	print("[BENCH] ===== damage flash CALIBRATION =====")

	-- ---------------------------------------------------------------- capability probes
	do
		local probe = SLIME:Clone()
		local probeMesh = probe:FindFirstChildWhichIsA("MeshPart")
		local probeSurface = probeMesh:FindFirstChildWhichIsA("SurfaceAppearance")
		probeMesh.Anchored = true
		probe.Parent = workspace

		print(
			string.format(
				"[PROBE] slime parts=%d surface=%s baseTint=%s",
				#probe:GetDescendants(),
				tostring(probeSurface ~= nil),
				tostring(probeSurface and probeSurface.Color)
			)
		)

		local ok, err = pcall(function()
			probeSurface.Color = WHITE
		end)
		print(
			string.format(
				"[PROBE] SurfaceAppearance.Color writable=%s readback=%s %s",
				tostring(ok),
				tostring(probeSurface.Color),
				if ok then "" else tostring(err)
			)
		)

		local okModel, errModel = pcall(function()
			local h = newHighlight()
			h.Parent = probe
		end)
		print(
			string.format(
				"[PROBE] Highlight under Model  ok=%s %s",
				tostring(okModel),
				if okModel then "" else tostring(errModel)
			)
		)

		local okMesh, errMesh = pcall(function()
			local h = newHighlight()
			h.Parent = probeMesh
		end)
		print(
			string.format(
				"[PROBE] Highlight under MeshPart ok=%s %s",
				tostring(okMesh),
				if okMesh then "" else tostring(errMesh)
			)
		)

		probe:Destroy()
		task.wait(1)
	end

	-- ---------------------------------------------------------------- raw write cost
	do
		buildSlots(MICRO_ENTITIES)
		buildSlimes(MICRO_ENTITIES)

		local models = table.create(MICRO_ENTITIES)
		local surfaces = table.create(MICRO_ENTITIES)
		local baseColor = nil
		for i = 1, MICRO_ENTITIES do
			models[i] = meshes[i].Parent
			surfaces[i] = meshes[i]:FindFirstChildWhichIsA("SurfaceAppearance")
			baseColor = baseColor or surfaces[i].Color
		end

		local pool = Instance.new("Folder")
		pool.Name = "FlashCalibPool"
		pool.Parent = workspace
		local highlights = table.create(MICRO_ENTITIES)
		for i = 1, MICRO_ENTITIES do
			local h = newHighlight()
			h.Parent = pool
			highlights[i] = h
		end

		task.wait(1.5)

		local function micro(label, ops, fn)
			fn(1) -- warm
			local s = os.clock()
			for i = 1, MICRO_ITERATIONS do
				fn(i)
			end
			local elapsed = os.clock() - s
			print(
				string.format(
					"[MICRO] %-42s %8.1f ns/op  (%d ops, %.1fms total)",
					label,
					elapsed / (MICRO_ITERATIONS * ops) * 1e9,
					MICRO_ITERATIONS * ops,
					elapsed * 1000
				)
			)
		end

		local flip = false
		micro("SurfaceAppearance.Color = NEW value", 1, function(i)
			surfaces[(i - 1) % MICRO_ENTITIES + 1].Color = if flip then WHITE else baseColor
			flip = not flip
		end)
		micro("SurfaceAppearance.Color = SAME value", 1, function(i)
			surfaces[(i - 1) % MICRO_ENTITIES + 1].Color = WHITE
		end)
		for i = 1, MICRO_ENTITIES do
			surfaces[i].Color = baseColor
		end

		micro("Highlight.Parent  model <-> pool", 2, function(i)
			local k = (i - 1) % MICRO_ENTITIES + 1
			highlights[k].Parent = models[k]
			highlights[k].Parent = pool
		end)
		micro("Highlight.Parent  mesh  <-> pool", 2, function(i)
			local k = (i - 1) % MICRO_ENTITIES + 1
			highlights[k].Parent = meshes[k]
			highlights[k].Parent = pool
		end)
		micro("Highlight.Enabled true <-> false", 2, function(i)
			local k = (i - 1) % MICRO_ENTITIES + 1
			highlights[k].Enabled = false
			highlights[k].Enabled = true
		end)
		micro("Highlight.Adornee model <-> nil", 2, function(i)
			local k = (i - 1) % MICRO_ENTITIES + 1
			highlights[k].Adornee = models[k]
			highlights[k].Adornee = nil
		end)
		micro("Instance.new Highlight + config + Destroy", 1, function(i)
			local h = newHighlight()
			h.Parent = models[(i - 1) % MICRO_ENTITIES + 1]
			h:Destroy()
		end)

		pool:Destroy()
		teardown()
	end

	-- ---------------------------------------------------------------- where does the cap stop flattening
	print("[BENCH] --- count sweep, movement only (find the count that clears the 240fps cap) ---")
	for _, n in COUNTS do
		buildSlots(n)

		local buildStart = os.clock()
		buildSlimes(n)
		local buildWall = (os.clock() - buildStart) * 1000

		clockStart = os.clock()
		activeUpdate = updateMove
		focusLost = false

		local settleSeconds, converged = settleUntilStable()

		updateTotal = 0
		updateFrames = 0
		table.clear(recDt)
		table.clear(recAt)
		recording = true
		local t0 = os.clock()
		task.wait(SAMPLE_SECONDS)
		recording = false
		local wall = os.clock() - t0

		local frames = window(t0, os.clock())
		local mean, med, p95, worst = stats(frames)
		local upd = updateTotal / math.max(updateFrames, 1) * 1e6
		local visible = countVisible(n)
		activeUpdate = nil

		local capped = 0
		for i = 1, #frames do
			if frames[i] < 0.00435 then
				capped += 1
			end
		end

		print(
			string.format(
				"[CAL] n=%-5d build=%7.0fms settle=%4.1fs%s | fps=%6.1f mean=%7.2f med=%7.2f p95=%7.2f worst=%8.2f | script=%7.1fus atCap=%5.1f%% vis=%d/%d%s",
				n,
				buildWall,
				settleSeconds,
				if converged then " ok " else " NOT",
				#frames / wall,
				mean,
				med,
				p95,
				worst,
				upd,
				capped / math.max(#frames, 1) * 100,
				visible,
				n,
				if focusLost then "  *** FOCUS LOST ***" else ""
			)
		)

		teardown()
	end

	print("[BENCH] ===== done =====")
end)
