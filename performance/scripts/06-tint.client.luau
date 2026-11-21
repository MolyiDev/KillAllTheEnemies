--!optimize 2
-- Does writing SurfaceAppearance.Color trigger the expensive rebuild?
--
-- A rebuild would not show up as a slightly higher average - it would show up as a SPIKE on exactly the frames
-- that changed and nowhere else. So the burst variant changes every tint on one frame in sixty and reports the
-- frames that followed a change SEPARATELY from the frames that did not. If tinting is free, those two numbers
-- are the same number. If it rebuilds, the change frames stand out and the others stay flat.
--
-- CAREFUL ABOUT WHICH FRAME PAYS. PreRender's dt is the time since the LAST render, so work done during frame N
-- lands in the dt reported at frame N+1. Every measurement here is shifted by one frame to account for that;
-- reading it off the same index would credit the cost to the frame before the one that caused it.
--
-- The same-value variant is the control for engine early-out: if the engine compares before dirtying, writing
-- white over white costs nothing and only genuinely NEW colours can be expensive.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local SKELETON = ReplicatedStorage:WaitForChild("Models"):WaitForChild("Skeleton")

local COUNTS = { 1200, 2400 }
local SETTLE_SECONDS = 1.5
local SAMPLE_SECONDS = 5.0
local TEARDOWN_SECONDS = 2.5
local BURST_PERIOD = 60 -- frames between mass tint changes

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

local bones = table.create(8192)
local surfaces = table.create(8192)
local joints = table.create(8192)

local clockStart = 0
local focusLost = false
UserInputService.WindowFocusReleased:Connect(function()
	focusLost = true
end)

-- Set by whichever update ran, read by onFrame: did THIS frame change any tints.
local didChange = false
local frameIndex = 0

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

local WHITE = Color3.new(1, 1, 1)

local function moveAll(t)
	for i = 1, count do
		bones[i].Transform = slotCFrame(i, t)
	end
end

-- Control: movement only, tints never touched.
local function updateMoveOnly()
	didChange = false
	moveAll(os.clock() - clockStart)
end

-- Every tint, every frame, a genuinely new colour.
local function updateColorEveryFrame()
	local t = os.clock() - clockStart
	moveAll(t)
	local r = (math.sin(t * 3) + 1) * 0.5
	local g = (math.sin(t * 3 + 2) + 1) * 0.5
	local b = (math.sin(t * 3 + 4) + 1) * 0.5
	local colour = Color3.new(r, g, b)
	for i = 1, count do
		surfaces[i].Color = colour
	end
	didChange = true
end

-- Every tint, every frame, the SAME value. Isolates the engine's early-out from the cost of a real change.
local function updateColorSameValue()
	local t = os.clock() - clockStart
	moveAll(t)
	for i = 1, count do
		surfaces[i].Color = WHITE
	end
	didChange = true
end

-- One frame in sixty changes everything. This is the one that would expose a rebuild.
local function updateColorBurst()
	local t = os.clock() - clockStart
	moveAll(t)
	if frameIndex % BURST_PERIOD ~= 0 then
		didChange = false
		return
	end
	local k = frameIndex / BURST_PERIOD
	local colour = Color3.new((k % 5) / 5, (k % 7) / 7, (k % 3) / 3)
	for i = 1, count do
		surfaces[i].Color = colour
	end
	didChange = true
end

local root = nil

local function buildSkeletons(n)
	local folder = Instance.new("Folder")
	folder.Name = "TintDiag"
	for i = 1, n do
		local model = SKELETON:Clone()
		local mesh = model:FindFirstChildWhichIsA("MeshPart")
		mesh.Anchored = true
		mesh.CanCollide = false
		mesh.CanQuery = false
		mesh.CanTouch = false
		mesh.CFrame = CFrame.new(0, 0, 0)
		bones[i] = mesh:FindFirstChildWhichIsA("Bone")
		surfaces[i] = mesh:FindFirstChildWhichIsA("SurfaceAppearance")
		model.Parent = folder
	end
	folder.Parent = workspace
	root = folder
end

local function buildCubePart(n)
	local folder = Instance.new("Folder")
	folder.Name = "TintDiag"
	for i = 1, n do
		local base = Instance.new("Part")
		base.Anchored = true
		base.CanCollide = false
		base.CanQuery = false
		base.CanTouch = false
		base.Transparency = 1
		base.Size = Vector3.one
		base.CFrame = CFrame.new(0, 0, 0)
		local body = Instance.new("Part")
		body.Anchored = false
		body.CanCollide = false
		body.CanQuery = false
		body.CanTouch = false
		body.Massless = true
		body.Size = Vector3.new(2, 2, 2)
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

local function updateSentinel()
	didChange = false
	local t = os.clock() - clockStart
	for i = 1, count do
		joints[i].Transform = slotCFrame(i, t)
	end
end

local function teardown()
	if root then
		root:Destroy()
		root = nil
	end
	table.clear(bones)
	table.clear(surfaces)
	table.clear(joints)
	task.wait(TEARDOWN_SECONDS)
end

local frameCount = 0
local frameTimes = table.create(16384)
local changedAt = table.create(16384)
local updateTotal = 0
local activeUpdate = nil

local function onFrame(dt)
	local update = activeUpdate
	if update then
		local s = os.clock()
		frameIndex += 1
		update()
		updateTotal += os.clock() - s
	end
	frameCount += 1
	frameTimes[frameCount] = dt
	changedAt[frameCount] = didChange
end

local function percentile(sorted, p)
	local n = #sorted
	if n == 0 then return 0 end
	return sorted[math.clamp(math.ceil(p * n), 1, n)]
end

local log = {}

local function sample(label, n, build, update)
	build(n)
	clockStart = os.clock()
	frameIndex = 0
	activeUpdate = update
	local connection = RunService.PreRender:Connect(onFrame)

	task.wait(SETTLE_SECONDS)

	focusLost = false
	frameCount = 0
	table.clear(frameTimes)
	table.clear(changedAt)
	updateTotal = 0
	local wall = os.clock()
	task.wait(SAMPLE_SECONDS)
	wall = os.clock() - wall

	connection:Disconnect()
	activeUpdate = nil

	local sorted = table.clone(frameTimes)
	table.sort(sorted)

	-- Shifted by one: the frame AFTER a change is the one that pays for it.
	local afterChange, afterQuiet = {}, {}
	for i = 1, frameCount - 1 do
		local target = if changedAt[i] then afterChange else afterQuiet
		target[#target + 1] = frameTimes[i + 1]
	end

	local function stats(list)
		if #list == 0 then return 0, 0 end
		local sum, worst = 0, 0
		for i = 1, #list do
			sum += list[i]
			if list[i] > worst then worst = list[i] end
		end
		return sum / #list * 1000, worst * 1000
	end

	local changeMean, changeWorst = stats(afterChange)
	local quietMean, quietWorst = stats(afterQuiet)

	log[#log + 1] = { Label = label, Count = n }

	print(
		string.format(
			"[TINT] %-30s n=%-5d fps=%6.1f med=%6.2fms p95=%7.2fms worst=%7.2fms upd=%7.1fus | afterChange n=%-4d mean=%6.2fms max=%7.2fms | quiet n=%-4d mean=%6.2fms max=%7.2fms%s",
			label,
			n,
			frameCount / wall,
			percentile(sorted, 0.5) * 1000,
			percentile(sorted, 0.95) * 1000,
			(sorted[#sorted] or 0) * 1000,
			(updateTotal / math.max(frameCount, 1)) * 1e6,
			#afterChange,
			changeMean,
			changeWorst,
			#afterQuiet,
			quietMean,
			quietWorst,
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
	camera.CFrame = CFrame.new(Vector3.new(0, 0, CAM_DISTANCE), Vector3.zero)

	-- Is the property even writable from a LocalScript, and does it stick?
	local probe = SKELETON:Clone()
	local probeMesh = probe:FindFirstChildWhichIsA("MeshPart")
	local probeSurface = probeMesh:FindFirstChildWhichIsA("SurfaceAppearance")
	probe.Parent = workspace
	local ok, err = pcall(function()
		probeSurface.Color = Color3.new(0.25, 0.5, 0.75)
	end)
	print(
		string.format(
			"[BENCH] SurfaceAppearance.Color writable=%s readback=%s %s",
			tostring(ok),
			tostring(probeSurface.Color),
			if ok then "" else tostring(err)
		)
	)
	probe:Destroy()
	task.wait(1)

	print("[BENCH] ===== SurfaceAppearance tint cost =====")
	for _, n in COUNTS do
		buildSlots(n)
		sample("SENTINEL cube Part", n, buildCubePart, updateSentinel)
		sample("Skeleton move only", n, buildSkeletons, updateMoveOnly)
		sample("Tint EVERY frame (new value)", n, buildSkeletons, updateColorEveryFrame)
		sample("Tint every frame (same value)", n, buildSkeletons, updateColorSameValue)
		sample("Tint BURST every 60 frames", n, buildSkeletons, updateColorBurst)
	end
	print("[BENCH] ===== done =====")
end)
