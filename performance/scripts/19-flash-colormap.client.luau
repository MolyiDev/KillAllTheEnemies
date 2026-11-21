--!optimize 2
-- CAN YOU FLASH BY CLEARING THE TEXTURE INSTEAD OF MOVING AN INSTANCE?
--
-- 18-flash-textured killed both texture-agnostic candidates, and killed them for the same reason:
--
--     SurfaceAppearance detach / reattach   +21.41ms on, +21.75ms off
--     MeshPart.Material = Neon swap         +19.75ms on, +19.21ms off
--
-- Detaching is a hierarchy change, which was expected to be expensive. The material swap was not - it is a plain
-- property write on a property the SurfaceAppearance overrides anyway - and it still cost 20ms. So the trigger is
-- not "hierarchy change", it is "anything that invalidates how this mesh is shaded".
--
-- That leaves one idea in the same family that has not been tried: leave the SurfaceAppearance exactly where it
-- is and blank its ColorMap, then put the texture back. No instance moves, no material changes. If the shading
-- invalidation is keyed on the instance graph rather than on the texture binding, this could be the uncapped,
-- texture-agnostic white flash. If it is keyed on the material at all, it will cost 20ms like the other two.
--
-- Doc 06 recorded that ColorMap / NormalMap / RoughnessMap are "not script-assignable at runtime", but that note
-- predates the January 2026 EditableImage-for-SurfaceAppearance work, so this probes the property before
-- trusting it and skips the variant honestly if it turns out to be read-only.
--
-- Also folded in: the K=1 case left over from 17-flash-mechanism. Re-aiming 24 pooled highlights costs ~17ms and
-- re-aiming 240 costs ~11.5ms, which does not scale per highlight and looks like a fixed rebuild triggered by
-- any rebind in the frame. If ONE rebind costs the same, a single enemy taking a single hit is a 15ms hitch and
-- pooled highlights are finished as an idea.

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
local HOLD_SECONDS = 14.0

local AREA_WIDTH = 260
local AREA_HEIGHT = 140
local AREA_DEPTH = 40
local CAM_DISTANCE = 155
local ORBIT_RADIUS = 3
local ORBIT_SPEED = 1.7

local WHITE = Color3.new(1, 1, 1)
local TEMPLATE_SURFACE = SLIME:FindFirstChildWhichIsA("MeshPart"):FindFirstChildWhichIsA("SurfaceAppearance")
local BASE_TINT = TEMPLATE_SURFACE.Color

-- Filled by the capability probe.
local colorMapOriginal = nil
local colorMapBlank = nil
local colorMapWritable = false

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

local clockStart = 0
local focusLost = false
UserInputService.WindowFocusReleased:Connect(function()
	focusLost = true
end)

local root = nil
local poolFolder = nil

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

-- Work out whether ColorMap can be written at all, and by what spelling. Returns a blank value that assigns
-- cleanly, or nil if the property is read-only from a LocalScript (trap 10).
local function probeColorMap()
	local probe = SLIME:Clone()
	local mesh = probe:FindFirstChildWhichIsA("MeshPart")
	local surface = mesh:FindFirstChildWhichIsA("SurfaceAppearance")
	mesh.Anchored = true
	probe.Parent = workspace

	local readOk, original = pcall(function()
		return surface.ColorMap
	end)
	print(
		string.format(
			"[PROBE] ColorMap readable=%s type=%s value=%s",
			tostring(readOk),
			if readOk then typeof(original) else "n/a",
			if readOk then tostring(original) else "n/a"
		)
	)

	if not readOk then
		probe:Destroy()
		return nil, nil
	end

	local candidates = { { "empty string", "" } }
	if Content ~= nil then
		local noneOk, none = pcall(function()
			return Content.none
		end)
		if noneOk and none ~= nil then candidates[#candidates + 1] = { "Content.none", none } end
	end

	for _, candidate in candidates do
		local label, value = candidate[1], candidate[2]
		local ok, err = pcall(function()
			surface.ColorMap = value
		end)
		if ok then
			local back = tostring(surface.ColorMap)
			print(string.format("[PROBE] ColorMap writable via %s, readback=%s", label, back))
			surface.ColorMap = original
			print(string.format("[PROBE] ColorMap restored, readback=%s", tostring(surface.ColorMap)))
			probe:Destroy()
			return original, value
		end
		print(string.format("[PROBE] ColorMap NOT writable via %s: %s", label, tostring(err)))
	end

	probe:Destroy()
	return original, nil
end

local function buildScene(preHighlight, whiteUnderlay)
	local folder = Instance.new("Folder")
	folder.Name = "MapDiag"
	local i = 1
	while i <= SCENE_N do
		local last = math.min(i + CHUNK - 1, SCENE_N)
		for k = i, last do
			local model, mesh = spawnSlime(folder, slotCFrame(k, 0))
			meshes[k] = mesh
			models[k] = model
			surfaces[k] = mesh:FindFirstChildWhichIsA("SurfaceAppearance")
		end
		i = last + 1
		task.wait()
	end

	if whiteUnderlay then
		for j = 1, TARGET_COUNT do
			meshes[targets[j]].Color = WHITE
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

local function buildPool(size)
	local folder = Instance.new("Folder")
	folder.Name = "MapPool"
	folder.Parent = workspace
	for j = 1, size do
		local highlight = newHighlight()
		highlight.Enabled = true
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

local function colorMapOn()
	for j = 1, burstK do
		surfaces[targets[j]].ColorMap = colorMapBlank
	end
end

local function colorMapOff()
	for j = 1, burstK do
		surfaces[targets[j]].ColorMap = colorMapOriginal
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

-- One pooled highlight, aimed at a different enemy every burst. The whole question at K=1.
local function poolRotatingOn()
	for j = 1, burstK do
		pool[j].Adornee = models[targets[(burstIndex + j - 2) % TARGET_COUNT + 1]]
	end
end

local function poolRotatingOff()
	for j = 1, burstK do
		pool[j].Adornee = nil
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
	buildScene(variant.PreHighlight, variant.WhiteUnderlay)
	if variant.PoolSize then buildPool(variant.PoolSize) end

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
			"[MAP] %-26s K=%-4d | med=%7.2f p95=%7.2f worst=%8.2f | quiet=%6.2f ON#1=%8.2f ON#2=%7.2f ON=%7.2f (n=%-3d d=%+8.2f max=%8.2f) OFF=%7.2f (d=%+8.2f max=%8.2f) | settle=%4.1fs%s vis=%d/%d fps=%5.1f%s",
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

-- Six slimes close up, one per state, held still so a human can look at them. This is the half the timing run
-- cannot answer: whether the flash reads as a flash at all.
local function visualHold()
	local folder = Instance.new("Folder")
	folder.Name = "MapVisual"

	local labels = {
		"1 reference",
		"2 tint WHITE",
		"3 ColorMap blank",
		"4 ColorMap blank + part white",
		"5 highlight Occluded",
		"6 highlight AlwaysOnTop",
	}

	for i = 1, 6 do
		local model, mesh = spawnSlime(folder, CFrame.new((i - 3.5) * 6, 0, 0))
		local surface = mesh:FindFirstChildWhichIsA("SurfaceAppearance")

		if i == 2 then
			surface.Color = WHITE
		elseif i == 3 and colorMapWritable then
			surface.ColorMap = colorMapBlank
		elseif i == 4 and colorMapWritable then
			mesh.Color = WHITE
			surface.ColorMap = colorMapBlank
		elseif i == 5 then
			local highlight = newHighlight()
			highlight.Enabled = true
			highlight.Parent = model
		elseif i == 6 then
			local highlight = newHighlight()
			highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			highlight.Enabled = true
			highlight.Parent = model
		end
	end

	folder.Parent = workspace
	camera.CFrame = CFrame.new(Vector3.new(0, 2, 22), Vector3.new(0, 0, 0))
	print(string.format("[VIS] holding %ds, left to right: %s", HOLD_SECONDS, table.concat(labels, " | ")))
	if not colorMapWritable then
		print("[VIS] slots 3 and 4 are UNCHANGED references - ColorMap is not writable from a LocalScript")
	end
	task.wait(HOLD_SECONDS)
	print("[VIS] hold over")
	folder:Destroy()
	task.wait(TEARDOWN_SECONDS)
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

	print("[BENCH] ===== blank the ColorMap instead of moving an instance =====")

	colorMapOriginal, colorMapBlank = probeColorMap()
	colorMapWritable = colorMapBlank ~= nil
	task.wait(1)

	visualHold()

	print("[BENCH] --- K=1: does ONE rebind cost as much as 24? ---")
	sample({ Label = "SENTINEL move only", K = 1 })
	sample({ Label = "POOL rotating Adornee", K = 1, PoolSize = 1, On = poolRotatingOn, Off = poolRotatingOff })

	for _, k in { 24, 240 } do
		print(string.format("[BENCH] --- K=%d ---", k))
		sample({ Label = "SENTINEL move only", K = k })
		sample({ Label = "TINT white (reference)", K = k, On = tintOn, Off = tintOff })
		if colorMapWritable then
			sample({
				Label = "COLORMAP blank / restore",
				K = k,
				WhiteUnderlay = true,
				On = colorMapOn,
				Off = colorMapOff,
			})
		else
			print("[BENCH] COLORMAP variant SKIPPED - property is not writable from a LocalScript")
		end
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
