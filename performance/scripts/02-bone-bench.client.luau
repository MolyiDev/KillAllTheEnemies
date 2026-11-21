--!optimize 2
-- Motor6D vs Bone.Transform.
--
-- Three variants. The first is the plain-part reference. The other two are the SAME
-- ReplicatedStorage.Models.Test skinned mesh, identical geometry, identical layout, differing only in what
-- moves it: a Motor6D joint's Transform, or the Root bone's Transform written exactly the way Ballarc's
-- EnemiesController writes it (mesh parked at the origin, the bone carrying the world CFrame).
--
-- Because 2 and 3 are the same mesh, the gap between them IS the mechanism and nothing else.
--
-- A camera-away control runs at n=2400: turning the camera off the cluster must recover frame time, otherwise
-- the geometry is not being drawn where the layout says it is and every number here is measuring the wrong thing.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local TEMPLATE = ReplicatedStorage:WaitForChild("Models"):WaitForChild("Test")

local COUNTS = { 1200, 2400, 4800 }
local REPS = 3
local SETTLE_SECONDS = 1.5
local SAMPLE_SECONDS = 4.0

local AREA_WIDTH = 260
local AREA_HEIGHT = 140
local AREA_DEPTH = 40
local CAM_DISTANCE = 155
local ORBIT_RADIUS = 3
local ORBIT_SPEED = 1.7

local count = 0
local slotX = table.create(8192)
local slotY = table.create(8192)
local slotZ = table.create(8192)
local phase = table.create(8192)

local joints = table.create(8192)
local bones = table.create(8192)

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

-- Identical math in both, so the only thing the timer can be seeing is the write itself.
local function updateMotor()
	local t = os.clock() - clockStart
	for i = 1, count do
		local a = t * ORBIT_SPEED + phase[i]
		joints[i].Transform = CFrame.new(
			slotX[i] + math.cos(a) * ORBIT_RADIUS,
			slotY[i] + math.sin(a) * ORBIT_RADIUS,
			slotZ[i]
		) * CFrame.fromEulerAnglesYXZ(0, a, 0)
	end
end

local function updateBone()
	local t = os.clock() - clockStart
	for i = 1, count do
		local a = t * ORBIT_SPEED + phase[i]
		bones[i].Transform = CFrame.new(
			slotX[i] + math.cos(a) * ORBIT_RADIUS,
			slotY[i] + math.sin(a) * ORBIT_RADIUS,
			slotZ[i]
		) * CFrame.fromEulerAnglesYXZ(0, a, 0)
	end
end

local root = nil

local function newFolder()
	local folder = Instance.new("Folder")
	folder.Name = "BoneBench"
	return folder
end

local function makeBase()
	local base = Instance.new("Part")
	base.Name = "MoveBase"
	base.Anchored = true
	base.CanCollide = false
	base.CanQuery = false
	base.CanTouch = false
	base.Transparency = 1
	base.Size = Vector3.one
	base.CFrame = CFrame.new(0, 0, 0)
	return base
end

local function buildMotorPart(n)
	local folder = newFolder()
	for i = 1, n do
		local base = makeBase()

		local body = Instance.new("Part")
		body.Anchored = false
		body.CanCollide = false
		body.CanQuery = false
		body.CanTouch = false
		body.Massless = true
		body.Size = Vector3.new(2, 2, 2)
		body.Color = Color3.fromRGB(120, 80, 40)
		body.Parent = base

		local joint = Instance.new("Motor6D")
		joint.Part0 = base
		joint.Part1 = body
		joint.Parent = base
		joints[i] = joint

		base.Parent = folder
	end
	folder.Parent = workspace
	root = folder
end

-- The Test mesh, moved by a Motor6D instead of by its bone. The bone is left at rest, so the geometry drawn is
-- byte-identical to the bone variant's.
local function buildMotorMesh(n)
	local folder = newFolder()
	local meshTemplate = TEMPLATE:FindFirstChildWhichIsA("MeshPart")

	for i = 1, n do
		local base = makeBase()

		local mesh = meshTemplate:Clone()
		mesh.Anchored = false
		mesh.CanCollide = false
		mesh.CanQuery = false
		mesh.CanTouch = false
		mesh.Massless = true
		mesh.Parent = base

		local joint = Instance.new("Motor6D")
		joint.Part0 = base
		joint.Part1 = mesh
		joint.Parent = base
		joints[i] = joint

		base.Parent = folder
	end
	folder.Parent = workspace
	root = folder
end

-- Ballarc's shape: the MeshPart stays anchored at the origin and the Root bone's Transform is the world CFrame.
local function buildBone(n)
	local folder = newFolder()

	for i = 1, n do
		local model = TEMPLATE:Clone()
		local mesh = model:FindFirstChildWhichIsA("MeshPart")
		mesh.Anchored = true
		mesh.CanCollide = false
		mesh.CanQuery = false
		mesh.CanTouch = false
		mesh.CFrame = CFrame.new(0, 0, 0)
		bones[i] = mesh:FindFirstChildWhichIsA("Bone")
		model.Parent = folder
	end

	folder.Parent = workspace
	root = folder
end

local function teardown()
	if root then
		root:Destroy()
		root = nil
	end
	table.clear(joints)
	table.clear(bones)
	task.wait(0.6)
end

local frameCount = 0
local frameTimes = table.create(8192)
local updateTotal = 0
local activeUpdate = nil

local function onFrame(dt)
	local update = activeUpdate
	if update then
		local s = os.clock()
		update()
		updateTotal += os.clock() - s
	end
	frameCount += 1
	frameTimes[frameCount] = dt
end

local function percentile(sorted, p)
	local n = #sorted
	if n == 0 then return 0 end
	return sorted[math.clamp(math.ceil(p * n), 1, n)]
end

-- Counts the LAYOUT slots inside the frustum. Identical for every variant by construction, which is the point:
-- it certifies the three are being asked to draw the same thing in the same place.
local function onScreenSlots()
	local visible = 0
	local viewport = camera.ViewportSize
	for i = 1, count do
		local point, inFront = camera:WorldToViewportPoint(Vector3.new(slotX[i], slotY[i], slotZ[i]))
		if inFront and point.X >= 0 and point.X <= viewport.X and point.Y >= 0 and point.Y <= viewport.Y then
			visible += 1
		end
	end
	return visible
end

local best = {}

local function sample(key, label, n, rep, build, update, facingAway)
	build(n)

	camera.CFrame = if facingAway
		then CFrame.new(Vector3.new(0, 0, CAM_DISTANCE), Vector3.new(0, 0, CAM_DISTANCE * 2))
		else CFrame.new(Vector3.new(0, 0, CAM_DISTANCE), Vector3.zero)

	clockStart = os.clock()
	activeUpdate = update
	local connection = RunService.PreRender:Connect(onFrame)

	task.wait(SETTLE_SECONDS)

	local visible = if facingAway then 0 else onScreenSlots()

	focusLost = false
	frameCount = 0
	table.clear(frameTimes)
	updateTotal = 0
	local wall = os.clock()
	task.wait(SAMPLE_SECONDS)
	wall = os.clock() - wall

	connection:Disconnect()
	activeUpdate = nil

	local sorted = table.clone(frameTimes)
	table.sort(sorted)

	local sum = 0
	local capped = 0
	for i = 1, frameCount do
		sum += frameTimes[i]
		if frameTimes[i] < 0.00435 then
			capped += 1
		end
	end

	local meanMs = (sum / math.max(frameCount, 1)) * 1000
	local entry = {
		Label = label,
		Count = n,
		Visible = visible,
		Fps = frameCount / wall,
		MeanMs = meanMs,
		MedianMs = percentile(sorted, 0.5) * 1000,
		P95Ms = percentile(sorted, 0.95) * 1000,
		WorstMs = (sorted[#sorted] or 0) * 1000,
		UpdateUs = (updateTotal / math.max(frameCount, 1)) * 1e6,
		AtCapPct = capped / math.max(frameCount, 1) * 100,
		Throttled = focusLost,
	}

	print(
		string.format(
			"[%s] %-20s n=%-5d rep=%d fps=%6.1f mean=%6.2fms med=%6.2fms p95=%6.2fms upd=%7.1fus atcap=%5.1f%% vis=%d/%d%s",
			facingAway and "CTRL" or "REP",
			label,
			n,
			rep,
			entry.Fps,
			meanMs,
			entry.MedianMs,
			entry.P95Ms,
			entry.UpdateUs,
			entry.AtCapPct,
			visible,
			n,
			if entry.Throttled then "  *** FOCUS LOST ***" else ""
		)
	)

	if not facingAway then
		local bucket = key .. "|" .. n
		local current = best[bucket]
		if (not entry.Throttled and (not current or meanMs < current.MeanMs)) or not current then
			best[bucket] = entry
		end
	end

	teardown()
	return entry
end

local function microBench()
	local N = 2000
	local ITERATIONS = 200
	local cf = CFrame.new(1, 2, 3) * CFrame.fromEulerAnglesYXZ(0, 0.5, 0)
	buildSlots(N)

	buildMotorPart(N)
	task.wait(1)
	local t0 = os.clock()
	for _ = 1, ITERATIONS do
		for i = 1, N do
			joints[i].Transform = cf
		end
	end
	local motorNs = (os.clock() - t0) / (ITERATIONS * N) * 1e9
	teardown()

	buildBone(N)
	task.wait(1)
	t0 = os.clock()
	for _ = 1, ITERATIONS do
		for i = 1, N do
			bones[i].Transform = cf
		end
	end
	local boneNs = (os.clock() - t0) / (ITERATIONS * N) * 1e9
	teardown()

	print(
		string.format(
			"[BENCH] RAW WRITE (ns/write, rendering excluded): Motor6D.Transform=%.0f  Bone.Transform=%.0f",
			motorNs,
			boneNs
		)
	)
end

local VARIANTS = {
	{ Key = "motor_part", Label = "Motor6D + Part", Build = buildMotorPart, Update = updateMotor },
	{ Key = "motor_mesh", Label = "Motor6D + TestMesh", Build = buildMotorMesh, Update = updateMotor },
	{ Key = "bone", Label = "Bone.Transform", Build = buildBone, Update = updateBone },
}

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

	print("[BENCH] ===== start ===== viewport=" .. tostring(camera.ViewportSize))
	microBench()

	-- Camera-away control: proves the geometry is actually on screen and costing something.
	buildSlots(2400)
	for _, variant in VARIANTS do
		sample(variant.Key, variant.Label, 2400, 0, variant.Build, variant.Update, true)
	end

	for _, n in COUNTS do
		buildSlots(n)
		for rep = 1, REPS do
			for _, variant in VARIANTS do
				sample(variant.Key, variant.Label, n, rep, variant.Build, variant.Update, false)
			end
		end
	end

	print("[BENCH] ===== BEST OF " .. REPS .. " REPS =====")
	for _, n in COUNTS do
		for _, variant in VARIANTS do
			local entry = best[variant.Key .. "|" .. n]
			if entry then
				print(
					string.format(
						"[BEST] %-20s n=%-5d fps=%6.1f mean=%6.2fms med=%6.2fms p95=%6.2fms worst=%6.2fms upd=%7.1fus atcap=%5.1f%% vis=%d/%d",
						entry.Label,
						n,
						entry.Fps,
						entry.MeanMs,
						entry.MedianMs,
						entry.P95Ms,
						entry.WorstMs,
						entry.UpdateUs,
						entry.AtCapPct,
						entry.Visible,
						n
					)
				)
			end
		end
	end
	print("[BENCH] ===== done =====")
end)
