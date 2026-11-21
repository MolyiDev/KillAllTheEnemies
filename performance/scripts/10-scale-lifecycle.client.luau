--!optimize 2
-- 1. Does Model:ScaleTo dodge the MeshPart.Size rebuild? (Skinned: no - 43.45ms vs 43.62ms for Size, identical,
--    because ScaleTo writes Size underneath. Remaining question answered here: a PART rig pays only +1.5ms
--    engine, so the rebuild is specific to MeshPart geometry rather than to scaling itself.)
--
--    There is no Model.Scale property in this engine version - reading it throws. The API is Model:ScaleTo(n)
--    and Model:GetScale(), which is what getPool already calls on pool templates. Note ScaleTo is not one
--    property write: it walks the model scaling parts, joints and attachments.
--
-- 2. Spawn and despawn cost, skinned mesh vs Part rig - the pooling decision.
--    :Destroy() RETURNS BEFORE THE WORK IS DONE, so each phase is measured twice: the wall clock of the call,
--    and the frames after it until they settle, reported as excess ms over baseline and worst single frame.
--
-- BUILDS ARE CHUNKED AND YIELD. A previous run died on "Script timeout: exhausted allowed execution time"
-- building 2400 slug rigs in one unbroken loop. Chunking fixes that, and the build cost stays honest because
-- only the time INSIDE the chunks is accumulated - the yields between them are not counted.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local Models = ReplicatedStorage:WaitForChild("Models")
local SKELETON = Models:WaitForChild("Skeleton")
local SLUG = Models:WaitForChild("Bugs"):WaitForChild("Slug")

local SCALE_N = 1800
local GRIP = 40
local LIFE_COUNTS = { 1200, 2400 }
local CHUNK = 200
local SETTLE_SECONDS = 2.0
local SAMPLE_SECONDS = 4.0
local WATCH_SECONDS = 2.5

local AREA_WIDTH = 260
local AREA_HEIGHT = 140
local AREA_DEPTH = 40
local CAM_DISTANCE = 155
local ORBIT_RADIUS = 3
local ORBIT_SPEED = 1.7

local count = 0
local slotX = table.create(4096)
local slotY = table.create(4096)
local slotZ = table.create(4096)
local phase = table.create(4096)

local bones = table.create(4096)
local joints = table.create(4096)
local models = table.create(4096)

local clockStart = 0

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

local recDt = table.create(32768)
local recAt = table.create(32768)
local recording = false
local activeUpdate = nil
local updateTotal = 0
local frameCount = 0

RunService.PreRender:Connect(function(dt)
	local update = activeUpdate
	if update then
		local s = os.clock()
		update()
		updateTotal += os.clock() - s
	end
	if not recording then return end
	local n = #recDt + 1
	recDt[n] = dt
	recAt[n] = os.clock()
	frameCount += 1
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
	if n == 0 then return 0, 0, 0 end
	local sum, worst = 0, 0
	for i = 1, n do
		sum += list[i]
		if list[i] > worst then worst = list[i] end
	end
	local sorted = table.clone(list)
	table.sort(sorted)
	return sum / n * 1000, sorted[math.max(math.floor(n * 0.5), 1)] * 1000, worst * 1000
end

local root = nil

-- One skinned entity.
local function makeSkeleton(i, folder)
	local model = SKELETON:Clone()
	local mesh = model:FindFirstChildWhichIsA("MeshPart")
	mesh.Anchored = true
	mesh.CanCollide = false
	mesh.CanQuery = false
	mesh.CanTouch = false
	mesh.CFrame = CFrame.new(0, 0, 0)
	bones[i] = mesh:FindFirstChildWhichIsA("Bone")
	models[i] = model
	model.Parent = folder
end

-- One Part rig.
local function makeSlug(i, folder)
	local model = SLUG:Clone()
	local base = model:FindFirstChild("MoveBase")
	local body = model:FindFirstChild("Body")
	base.Anchored = true
	base.CanCollide = false
	base.CanQuery = false
	base.CanTouch = false
	base.CFrame = CFrame.new(0, 0, 0)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			if d ~= base then
				d.Anchored = false
				d.Massless = true
			end
		elseif d:IsA("Motor6D") then
			if d.Part1 == body then joints[i] = d end
		elseif d:IsA("Sound") then
			d:Destroy()
		end
	end
	models[i] = model
	model.Parent = folder
end

-- Chunked so the builder yields; returns only the time spent INSIDE the chunks.
local function buildChunked(maker, n)
	local folder = Instance.new("Folder")
	folder.Name = "ScaleLifeDiag"
	local spent = 0
	local i = 1
	while i <= n do
		local last = math.min(i + CHUNK - 1, n)
		local t0 = os.clock()
		for k = i, last do
			maker(k, folder)
		end
		spent += os.clock() - t0
		i = last + 1
		task.wait()
	end
	local t0 = os.clock()
	folder.Parent = workspace
	spent += os.clock() - t0
	root = folder
	return spent * 1000
end

local function clearRefs()
	table.clear(bones)
	table.clear(joints)
	table.clear(models)
end

local function teardown()
	if root then
		root:Destroy()
		root = nil
	end
	clearRefs()
	task.wait(2.5)
end

local function moveBones(t)
	for i = 1, count do
		bones[i].Transform = slotCFrame(i, t)
	end
end

local function moveJoints(t)
	for i = 1, count do
		joints[i].Transform = slotCFrame(i, t)
	end
end

local scaleUpTo = 0
local mover = nil

local function updateWithScale()
	local t = os.clock() - clockStart
	mover(t)
	for i = 1, scaleUpTo do
		models[i]:ScaleTo(1 + (math.sin(t * 2 + i * 0.017) + 1) * 0.35)
	end
end

local function updateMoveOnly()
	mover(os.clock() - clockStart)
end

local function runScale(label, maker, moveFn, upTo)
	buildChunked(maker, SCALE_N)
	mover = moveFn
	scaleUpTo = upTo
	clockStart = os.clock()
	activeUpdate = if upTo > 0 then updateWithScale else updateMoveOnly

	task.wait(SETTLE_SECONDS)
	table.clear(recDt)
	table.clear(recAt)
	updateTotal = 0
	frameCount = 0
	recording = true
	local t0 = os.clock()
	task.wait(SAMPLE_SECONDS)
	recording = false
	local wall = os.clock() - t0

	activeUpdate = nil
	local fMean, fMed, fMax = stats(window(0, math.huge))
	local upd = updateTotal / math.max(frameCount, 1) * 1e6

	print(
		string.format(
			"[SCALE] %-34s fps=%6.1f frame mean=%7.2f med=%7.2f max=%8.2f | script=%8.1fus | engine med=%7.2f",
			label,
			frameCount / wall,
			fMean,
			fMed,
			fMax,
			upd,
			fMed - upd / 1000
		)
	)
	teardown()
end

local function runLifecycle(label, maker, n)
	table.clear(recDt)
	table.clear(recAt)
	recording = true
	task.wait(1.5)
	local _, baseMed = stats(window(0, math.huge))
	recording = false

	table.clear(recDt)
	table.clear(recAt)
	recording = true
	local spawnStart = os.clock()
	local spawnCpu = buildChunked(maker, n)
	task.wait(WATCH_SECONDS)
	local spawnFrames = window(spawnStart, os.clock())
	local _, spawnMed, spawnMax = stats(spawnFrames)
	local spawnExcess = 0
	for i = 1, #spawnFrames do
		local over = spawnFrames[i] * 1000 - baseMed
		if over > 0 then
			spawnExcess += over
		end
	end
	recording = false

	table.clear(recDt)
	table.clear(recAt)
	recording = true
	local t0 = os.clock()
	if root then
		root:Destroy()
		root = nil
	end
	local destroyWall = (os.clock() - t0) * 1000
	local destroyStart = os.clock()
	task.wait(WATCH_SECONDS)
	local destroyFrames = window(destroyStart, os.clock())
	local _, _, destroyMax = stats(destroyFrames)
	local destroyExcess = 0
	for i = 1, #destroyFrames do
		local over = destroyFrames[i] * 1000 - baseMed
		if over > 0 then
			destroyExcess += over
		end
	end
	recording = false
	clearRefs()

	print(
		string.format(
			"[LIFE ] %-18s n=%-5d base=%5.2fms | SPAWN cpu=%8.2fms med=%6.2f worst=%8.2f excess=%8.2f (%6.1fus/entity) | DESTROY call=%7.2fms worst=%7.2f excess=%8.2f",
			label,
			n,
			baseMed,
			spawnCpu,
			spawnMed,
			spawnMax,
			spawnExcess,
			spawnCpu / n * 1000,
			destroyWall,
			destroyMax,
			destroyExcess
		)
	)
	task.wait(2.0)
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

	print("[BENCH] ===== part 1: Model:ScaleTo on a PART rig @ n=" .. SCALE_N .. " =====")
	buildSlots(SCALE_N)
	runScale("SLUG: move only (control)", makeSlug, moveJoints, 0)
	runScale("SLUG: ScaleTo GRIP 40", makeSlug, moveJoints, GRIP)
	runScale("SKINNED: move only (control)", makeSkeleton, moveBones, 0)
	runScale("SKINNED: ScaleTo GRIP 40", makeSkeleton, moveBones, GRIP)

	print("[BENCH] ===== part 2: spawn / despawn =====")
	for _, n in LIFE_COUNTS do
		buildSlots(n)
		runLifecycle("SKELETON (skinned)", makeSkeleton, n)
		runLifecycle("SLUG (part rig)", makeSlug, n)
	end

	print("[BENCH] ===== done =====")
end)
