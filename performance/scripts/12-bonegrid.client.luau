--!optimize 2
-- MANY ENTITIES PER MESH: does the skinned ceiling move when you stop giving each entity its own MeshPart?
--
-- Measured previously: skinned meshes top out at ~4800 INSTANCES (clean to 4800, tail breaks at 6000, median
-- breaks at 7200), while a bone write costs 79ns. If the binding constraint is the number of MeshParts rather
-- than the number of moving things, packing 100 entities into one mesh should push that ceiling a long way.
--
-- BoneGrid100 is one skinned MeshPart holding 100 cubes, each bound 1:1 to its own bone at weight 1.0. So:
--
--     4800 entities as Skeletons  = 4800 MeshParts + 4800 Bones
--     4800 entities as BoneGrid   =   48 MeshParts + 4800 Bones
--
-- The bone count is IDENTICAL and the MeshPart count is 100x smaller. Same update loop shape as every earlier
-- run - one flat array, one Transform write per entity per frame - so the Luau cost per entity is directly
-- comparable to the numbers in 09-skinned-ceiling.md.
--
-- Adaptive settle throughout - fixed waits were what produced the wrong 7200 answer the first time.
--
-- NOTE: this script's own camera-away control is CAP-MASKED at 4800 and proves nothing. The real validity check
-- lives in 13-bonegrid-validity, which runs at uncapped counts and adds a camera-independent control.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Stats = game:GetService("Stats")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local TEMPLATE = ReplicatedStorage:WaitForChild("Models"):WaitForChild("BoneGrid100")

local COUNTS = { 2400, 4800, 9600, 19200, 38400, 76800 }
local CONTROL_COUNT = 4800
local CHUNK = 25 -- instances per build chunk; each clone carries ~101 instances
local SETTLE_WINDOW = 1.0
local SETTLE_TOLERANCE = 0.10
local SETTLE_MAX_SECONDS = 40
local SAMPLE_SECONDS = 5.0
local TEARDOWN_SECONDS = 4.0
local COLLAPSE_MS = 50

local AREA_WIDTH = 260
local AREA_HEIGHT = 140
local AREA_DEPTH = 40
local CAM_DISTANCE = 155
local ORBIT_RADIUS = 3
local ORBIT_SPEED = 1.7

local count = 0
local slotX = table.create(80000)
local slotY = table.create(80000)
local slotZ = table.create(80000)
local phase = table.create(80000)
local bones = table.create(80000)

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

-- How many bones the template actually carries, discovered rather than assumed.
local function elementsPerMesh()
	local mesh = TEMPLATE:FindFirstChildWhichIsA("MeshPart")
	local n = 0
	for _, child in mesh:GetChildren() do
		if child:IsA("Bone") then
			n += 1
		end
	end
	return n, mesh
end

local ELEMENTS, TEMPLATE_MESH = elementsPerMesh()

-- Builds ceil(total / ELEMENTS) instances and flattens every bone into one array, so the update loop is the
-- same single linear pass as every other benchmark here.
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
	return instances, written
end

local function teardown()
	if root then
		root:Destroy()
		root = nil
	end
	table.clear(bones)
	task.wait(TEARDOWN_SECONDS)
end

local function updateBones()
	local t = os.clock() - clockStart
	for i = 1, count do
		bones[i].Transform = slotCFrame(i, t)
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

local function measure(total, facingAway)
	buildSlots(total)

	local memBefore = Stats:GetTotalMemoryUsageMb()
	local buildStart = os.clock()
	local instances, wired = buildChunked(total)
	local buildWall = (os.clock() - buildStart) * 1000

	camera.CFrame = if facingAway
		then CFrame.new(Vector3.new(0, 0, CAM_DISTANCE), Vector3.new(0, 0, CAM_DISTANCE * 2))
		else CFrame.new(Vector3.new(0, 0, CAM_DISTANCE), Vector3.zero)

	clockStart = os.clock()
	activeUpdate = updateBones
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
	local memMb = Stats:GetTotalMemoryUsageMb() - memBefore

	local capped = 0
	for i = 1, #frames do
		if frames[i] < 0.00435 then
			capped += 1
		end
	end

	activeUpdate = nil

	print(
		string.format(
			"[GRID] %s n=%-6d meshes=%-5d bones=%-6d build=%7.0fms settle=%4.1fs%s | fps=%7.1f mean=%7.2f med=%7.2f p95=%7.2f worst=%8.2f | script=%7.1fus engine(med)=%7.2f atCap=%5.1f%% mem=%5.0fMB%s",
			if facingAway then "AWAY" else "LOOK",
			total,
			instances,
			wired,
			buildWall,
			settleSeconds,
			if converged then " ok" else " NO",
			#frames / wall,
			mean,
			med,
			p95,
			worst,
			upd,
			med - upd / 1000,
			capped / math.max(#frames, 1) * 100,
			memMb,
			if focusLost then "  *** FOCUS LOST ***" else ""
		)
	)

	teardown()
	return med
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
		string.format(
			"[BENCH] ===== BoneGrid: %d elements per MeshPart, template size=%s =====",
			ELEMENTS,
			tostring(TEMPLATE_MESH.Size)
		)
	)
	print("[BENCH] reference (one MeshPart per entity, from 09-skinned-ceiling): 4800 -> 5.60ms med / 6.80ms p95")
	print("[BENCH]                                                              7200 -> 44.77ms med (broken)")

	measure(CONTROL_COUNT, true)
	measure(CONTROL_COUNT, false)

	for _, total in COUNTS do
		if total ~= CONTROL_COUNT then
			local med = measure(total, false)
			if med > COLLAPSE_MS then
				print(string.format("[BENCH] collapsed at n=%d (settled median %.1fms) - stopping sweep", total, med))
				break
			end
		end
	end

	print("[BENCH] ===== done =====")
end)
