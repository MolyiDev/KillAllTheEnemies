--!optimize 2
-- IS FillTransparency ON A BOUND HIGHLIGHT AS CHEAP AS .Enabled?
--
-- Every devforum answer to "how do I flash white" is the same: park a Highlight inside the part and tween
-- FillTransparency. Doc 13 measured the .Enabled toggle on a bound highlight (free, -0.06 to +0.23ms) but never
-- measured FillTransparency - the variant existed in 17-flash-mechanism and that run died before reaching it.
--
-- It is not safe to assume they are the same. Roblox's own docs say "highlights that are not visible on the
-- screen (whether disabled or fully transparent) incur no performance cost", which means a highlight at
-- FillTransparency = 1 is culled exactly like a disabled one. If the cost of a highlight appearing is paid when
-- it stops being culled, then 1 -> 0 pays whatever false -> true pays. And 06-color-transparency-fastcluster
-- found precisely that shape for Part.Transparency on skinned meshes: crossing the opaque/transparent boundary
-- cost ~15-19us each, while changing transparency WITHIN the transparent range was free.
--
-- So this run splits it the same way doc 06 did:
--
--   CROSS   1 <-> 0    the real thing - invisible to fully opaque and back
--   WITHIN  0.5 <-> 0  never fully invisible, so the highlight is always being drawn and never culled
--
-- If CROSS costs and WITHIN does not, the cost is the culling threshold, and the fix is to park the flash at
-- 0.99 instead of 1. If both are free, tweening FillTransparency is simply fine.
--
-- Same scene as 15/18/19: 2400 slimes, all in frustum, 240 targets, burst every 30 frames for 6. Nothing flashes
-- until the sample window opens, so ON#1 is a cold transition and is reported separately.

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
local restTransparency = 1

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

-- mode: "enabled" starts disabled and flashes with .Enabled; "fill" stays enabled forever and flashes with
-- FillTransparency, resting at `rest` (1 = culled, 0.5 = always drawn).
local function newHighlight(mode, rest)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = WHITE
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	if mode == "fill" then
		highlight.FillTransparency = rest
		highlight.Enabled = true
	else
		highlight.FillTransparency = 0
		highlight.Enabled = false
	end
	return highlight
end

local function buildScene(preMode, mode, rest)
	local folder = Instance.new("Folder")
	folder.Name = "FillDiag"
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
			local highlight = newHighlight(mode, rest)
			highlight.Parent = if preMode == "model" then models[targets[j]] else meshes[targets[j]]
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

local function enabledOn()
	for j = 1, burstK do
		owned[j].Enabled = true
	end
end

local function enabledOff()
	for j = 1, burstK do
		owned[j].Enabled = false
	end
end

local function fillOn()
	for j = 1, burstK do
		owned[j].FillTransparency = 0
	end
end

local function fillOff()
	for j = 1, burstK do
		owned[j].FillTransparency = restTransparency
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

-- Re-asserted before every sample, not once at startup. A respawn resets CameraType to Custom and hands the
-- camera back to the default camera script, which then follows the character and points at empty sky - the
-- harness keeps measuring and every row reads vis=0/2400 with a suspiciously good frame time.
local function parkCharacter()
	local character = player.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.Anchored = true
		hrp.CFrame = CFrame.new(0, 500, 0)
	end
end

local function aimCamera()
	parkCharacter()
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 70
	camera.CFrame = CAM_AT
end

local function sample(variant)
	aimCamera()
	restTransparency = variant.Rest or 1
	buildScene(variant.PreMode, variant.Mode, restTransparency)

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
	local viewport = camera.ViewportSize
	local camPos = camera.CFrame.Position
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
			"[FILL] %-30s K=%-4d | med=%7.2f p95=%7.2f worst=%8.2f | quiet=%6.2f ON#1=%7.2f ON#2=%7.2f ON=%7.2f (n=%-3d d=%+7.2f max=%7.2f) OFF=%7.2f (d=%+7.2f max=%7.2f) | settle=%4.1fs%s vis=%d/%d fps=%5.1f cam=(%.0f,%.0f,%.0f)/%s vp=%dx%d%s",
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
			camPos.X,
			camPos.Y,
			camPos.Z,
			tostring(camera.CameraType),
			viewport.X,
			viewport.Y,
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
	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		parkCharacter()
	end)
	aimCamera()

	buildSlots()

	print("[BENCH] ===== FillTransparency on a bound Highlight, CROSS vs WITHIN =====")

	for _, k in { 24, 240 } do
		print(string.format("[BENCH] --- K=%d ---", k))
		sample({ Label = "SENTINEL move only", K = k })
		sample({ Label = "TINT white (reference)", K = k, On = tintOn, Off = tintOff })
		sample({
			Label = "Model .Enabled (reference)",
			K = k,
			PreMode = "model",
			Mode = "enabled",
			On = enabledOn,
			Off = enabledOff,
		})
		sample({
			Label = "Model Fill CROSS 1 <-> 0",
			K = k,
			PreMode = "model",
			Mode = "fill",
			Rest = 1,
			On = fillOn,
			Off = fillOff,
		})
		sample({
			Label = "Model Fill WITHIN 0.5 <-> 0",
			K = k,
			PreMode = "model",
			Mode = "fill",
			Rest = 0.5,
			On = fillOn,
			Off = fillOff,
		})
		sample({
			Label = "Mesh Fill CROSS 1 <-> 0",
			K = k,
			PreMode = "mesh",
			Mode = "fill",
			Rest = 1,
			On = fillOn,
			Off = fillOff,
		})
	end

	print("[BENCH] ===== done =====")
end)
