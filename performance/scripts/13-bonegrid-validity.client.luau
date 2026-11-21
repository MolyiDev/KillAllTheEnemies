--!optimize 2
-- VALIDITY CHECK for the BoneGrid result.
--
-- The sweep says 19200 entities across 192 MeshParts runs at 13.55ms median, where one-MeshPart-per-entity was
-- already dead at 8400. That is only meaningful if the geometry is actually being DRAWN. Every cube rests on
-- the origin, so each MeshPart's bounding box is one 2x2x2 cube while its bones fling geometry across the whole
-- screen - if Roblox culls the displaced geometry against that box, nothing renders and the sweep measured
-- nothing but the cost of writing bone Transforms.
--
-- The first attempt at this control ran at 4800, where 63% of frames were pinned at the 240 cap, so LOOK and
-- AWAY were identical for a trivial reason. This runs the control at counts that are genuinely uncapped.
--
-- THREE CONDITIONS, same count, same scene, same bone writes every frame:
--
--   LOOK    camera on the cluster, bones spread across the screen
--   AWAY    camera turned 180 degrees away, bones spread exactly the same
--   PARKED  camera on the cluster, but every bone written to 2^24 - the geometry is off in the void
--
-- PARKED is the stronger of the two controls because it does not depend on the camera or on frustum culling at
-- all: identical instance count, identical number of property writes, only the resulting geometry is elsewhere.
--
-- If LOOK is materially more expensive than both AWAY and PARKED, the cubes are being drawn and the sweep
-- stands. If all three agree, nothing is being rendered and the whole BoneGrid result must be thrown out.
--
-- RESULT: LOOK cost 2.17-4.24x AWAY and 2.55-2.67x PARKED. Drawing confirmed.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local TEMPLATE = ReplicatedStorage:WaitForChild("Models"):WaitForChild("BoneGrid100")

local COUNTS = { 9600, 19200 }
local CHUNK = 25
local SETTLE_WINDOW = 1.0
local SETTLE_TOLERANCE = 0.10
local SETTLE_MAX_SECONDS = 40
local SAMPLE_SECONDS = 5.0
local TEARDOWN_SECONDS = 4.0

local AREA_WIDTH = 260
local AREA_HEIGHT = 140
local AREA_DEPTH = 40
local CAM_DISTANCE = 155
local ORBIT_RADIUS = 3
local ORBIT_SPEED = 1.7

local FAR_AWAY = CFrame.new(2 ^ 24, 2 ^ 24, 2 ^ 24)

local count = 0
local slotX = table.create(32768)
local slotY = table.create(32768)
local slotZ = table.create(32768)
local phase = table.create(32768)
local bones = table.create(32768)

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

local function elementsPerMesh()
	local mesh = TEMPLATE:FindFirstChildWhichIsA("MeshPart")
	local n = 0
	for _, child in mesh:GetChildren() do
		if child:IsA("Bone") then
			n += 1
		end
	end
	return n
end

local ELEMENTS = elementsPerMesh()

local function buildChunked(total)
	local folder = Instance.new("Folder")
	folder.Name = "BoneGridDiag"
	local instances = math.ceil(total / ELEMENTS)
	local written = 0
	local made = 0

	while made < instances do
		local target = math.min(made + CHUNK, instances)
		while made < target do
			made += 1
			local model = TEMPLATE:Clone()
			local mesh = model:FindFirstChildWhichIsA("MeshPart")
			mesh.Anchored = true
			mesh.CanCollide = false
			mesh.CanQuery = false
			mesh.CanTouch = false
			mesh.CFrame = CFrame.new(0, 0, 0)
			for _, child in mesh:GetChildren() do
				if child:IsA("Bone") and written < total then
					written += 1
					bones[written] = child
				end
			end
			model.Parent = folder
		end
		task.wait()
	end

	folder.Parent = workspace
	root = folder
	return instances
end

local function teardown()
	if root then
		root:Destroy()
		root = nil
	end
	table.clear(bones)
	task.wait(TEARDOWN_SECONDS)
end

-- Spread across the screen.
local function updateSpread()
	local t = os.clock() - clockStart
	for i = 1, count do
		bones[i].Transform = slotCFrame(i, t)
	end
end

-- Same instance count, same number of writes, geometry sent to the void.
local function updateParked()
	for i = 1, count do
		bones[i].Transform = FAR_AWAY
	end
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
				if agreements >= 2 then return os.clock() - start, true end
			else
				agreements = 0
			end
		end
		prevMed = med
	end

	return os.clock() - start, false
end

local function measure(label, total, update, facingAway)
	buildSlots(total)
	local instances = buildChunked(total)

	camera.CFrame = if facingAway
		then CFrame.new(Vector3.new(0, 0, CAM_DISTANCE), Vector3.new(0, 0, CAM_DISTANCE * 2))
		else CFrame.new(Vector3.new(0, 0, CAM_DISTANCE), Vector3.zero)

	clockStart = os.clock()
	activeUpdate = update
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
	local mean, med, p95, _ = stats(frames)
	local upd = updateTotal / math.max(updateFrames, 1) * 1e6

	local capped = 0
	for i = 1, #frames do
		if frames[i] < 0.00435 then
			capped += 1
		end
	end

	activeUpdate = nil

	print(
		string.format(
			"[VALID] %-7s n=%-6d meshes=%-4d settle=%4.1fs%s | fps=%7.1f mean=%7.2f med=%7.2f p95=%7.2f | script=%7.1fus engine(med)=%7.2f atCap=%5.1f%%%s",
			label,
			total,
			instances,
			settleSeconds,
			if converged then " ok" else " NO",
			#frames / wall,
			mean,
			med,
			p95,
			upd,
			med - upd / 1000,
			capped / math.max(#frames, 1) * 100,
			if focusLost then "  *** FOCUS LOST ***" else ""
		)
	)

	teardown()
	return med - upd / 1000
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

	print("[BENCH] ===== BoneGrid validity: is the geometry actually drawn? =====")
	print("[BENCH] engine(med) = frame median minus our own Luau cost. Compare LOOK against AWAY and PARKED.")

	for _, total in COUNTS do
		local look = measure("LOOK", total, updateSpread, false)
		local away = measure("AWAY", total, updateSpread, true)
		local parked = measure("PARKED", total, updateParked, false)

		print(
			string.format(
				"[BENCH] n=%d -> engine LOOK=%.2fms AWAY=%.2fms PARKED=%.2fms | LOOK is %.2fx AWAY, %.2fx PARKED",
				total,
				look,
				away,
				parked,
				look / math.max(away, 0.001),
				look / math.max(parked, 0.001)
			)
		)
	end

	print("[BENCH] ===== done =====")
end)
