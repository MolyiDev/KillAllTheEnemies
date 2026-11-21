--!optimize 2
-- The same three properties, on SKINNED meshes this time.
--
-- The transparency stall was measured on slug rigs: Parts wearing SpecialMeshes, no skinned mesh, no Humanoid.
-- Roblox staff say buildSkeleton applies to "models that contain skinned meshes or Humanoid", so that result is
-- on a path the announcement is not about. This closes the matrix by running all three properties against the
-- Skeleton, which IS a skinned mesh with a bone hierarchy, so every cell has been measured on the path the post
-- actually describes:
--
--                        slug rig (not skinned)      skeleton (skinned)
--   SurfaceApp.Color     n/a (no SurfaceAppearance)  HERE
--   Part.Color           measured: +4.8ms            HERE
--   Part.Transparency    measured: ~1000ms stall     HERE   <- the one that matters
--
-- Two counts, because the slug stall turned out to be a threshold rather than a slope (free at 4500 parts,
-- ~1s at 9000). If skinned meshes have a cliff too it should move with the count.
--
-- NOTE ON THE n=4800 BLOCK: in practice its transparency rows are unusable - CROSS catches one sample and quiet
-- frames reach a 219ms median, so the change/quiet distinction breaks down. The colour rows there still hold.
--
-- Engine time is isolated as before: frameTimes[N+1] - updateTimes[N].

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local SKELETON = ReplicatedStorage:WaitForChild("Models"):WaitForChild("Skeleton")

local COUNTS = { 2400, 4800 }
local SETTLE_SECONDS = 2.0
local SAMPLE_SECONDS = 6.0
local TEARDOWN_SECONDS = 2.5
local BURST_PERIOD = 30

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
local meshes = table.create(8192)
local surfaces = table.create(8192)

local clockStart = 0
local focusLost = false
UserInputService.WindowFocusReleased:Connect(function()
	focusLost = true
end)

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

local function moveBones(t)
	for i = 1, count do
		bones[i].Transform = slotCFrame(i, t)
	end
end

local function isBurstFrame()
	return frameIndex % BURST_PERIOD == 0
end

local function updateQuiet()
	didChange = false
	moveBones(os.clock() - clockStart)
end

local function updatePartColor()
	moveBones(os.clock() - clockStart)
	if not isBurstFrame() then
		didChange = false
		return
	end
	local k = frameIndex / BURST_PERIOD
	local colour = Color3.new((k % 5) / 5, (k % 7) / 7, (k % 3) / 3)
	for i = 1, count do
		meshes[i].Color = colour
	end
	didChange = true
end

local function updateSurfaceColor()
	moveBones(os.clock() - clockStart)
	if not isBurstFrame() then
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

local function updateCross()
	moveBones(os.clock() - clockStart)
	if not isBurstFrame() then
		didChange = false
		return
	end
	local alpha = if (frameIndex / BURST_PERIOD) % 2 == 0 then 0 else 0.5
	for i = 1, count do
		meshes[i].Transparency = alpha
	end
	didChange = true
end

local function updateWithin()
	moveBones(os.clock() - clockStart)
	if not isBurstFrame() then
		didChange = false
		return
	end
	local alpha = if (frameIndex / BURST_PERIOD) % 2 == 0 then 0.5 else 0.6
	for i = 1, count do
		meshes[i].Transparency = alpha
	end
	didChange = true
end

local root = nil

local function buildSkeletons(n, startTransparency)
	local folder = Instance.new("Folder")
	folder.Name = "SkinnedDiag"
	for i = 1, n do
		local model = SKELETON:Clone()
		local mesh = model:FindFirstChildWhichIsA("MeshPart")
		mesh.Anchored = true
		mesh.CanCollide = false
		mesh.CanQuery = false
		mesh.CanTouch = false
		mesh.CFrame = CFrame.new(0, 0, 0)
		mesh.Transparency = startTransparency
		meshes[i] = mesh
		bones[i] = mesh:FindFirstChildWhichIsA("Bone")
		surfaces[i] = mesh:FindFirstChildWhichIsA("SurfaceAppearance")
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
	table.clear(bones)
	table.clear(meshes)
	table.clear(surfaces)
	task.wait(TEARDOWN_SECONDS)
end

local frameCount = 0
local frameTimes = table.create(16384)
local updateTimes = table.create(16384)
local changedAt = table.create(16384)
local activeUpdate = nil

local function onFrame(dt)
	local update = activeUpdate
	local cost = 0
	if update then
		local s = os.clock()
		frameIndex += 1
		update()
		cost = os.clock() - s
	end
	frameCount += 1
	frameTimes[frameCount] = dt
	updateTimes[frameCount] = cost
	changedAt[frameCount] = didChange
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

local function sample(label, n, startTransparency, update)
	buildSkeletons(n, startTransparency)
	clockStart = os.clock()
	frameIndex = 0
	activeUpdate = update
	local connection = RunService.PreRender:Connect(onFrame)

	task.wait(SETTLE_SECONDS)

	focusLost = false
	frameCount = 0
	table.clear(frameTimes)
	table.clear(updateTimes)
	table.clear(changedAt)
	task.wait(SAMPLE_SECONDS)

	connection:Disconnect()
	activeUpdate = nil

	local changeEngine, quietEngine = {}, {}
	for i = 1, frameCount - 1 do
		local engine = frameTimes[i + 1] - updateTimes[i]
		local target = if changedAt[i] then changeEngine else quietEngine
		target[#target + 1] = engine
	end

	local ceMean, ceMed, ceMax = stats(changeEngine)
	local qeMean, qeMed, qeMax = stats(quietEngine)

	print(
		string.format(
			"[SKIN] %-26s n=%-5d | ENGINE change n=%-3d mean=%8.2f med=%8.2f max=%8.2f | quiet n=%-4d mean=%6.2f med=%6.2f max=%7.2f | delta=%+9.2fms%s",
			label,
			n,
			#changeEngine,
			ceMean,
			ceMed,
			ceMax,
			#quietEngine,
			qeMean,
			qeMed,
			qeMax,
			ceMean - qeMean,
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

	-- Confirm Transparency actually takes on a MeshPart wearing a SurfaceAppearance before trusting the rows.
	local probe = SKELETON:Clone()
	local probeMesh = probe:FindFirstChildWhichIsA("MeshPart")
	probe.Parent = workspace
	probeMesh.Transparency = 0.5
	print(
		string.format(
			"[BENCH] MeshPart.Transparency readback=%.2f (SurfaceAppearance present=%s)",
			probeMesh.Transparency,
			tostring(probeMesh:FindFirstChildWhichIsA("SurfaceAppearance") ~= nil)
		)
	)
	probe:Destroy()
	task.wait(1)

	print("[BENCH] ===== SKINNED mesh: Part.Color / Part.Transparency / SurfaceAppearance.Color =====")
	for _, n in COUNTS do
		buildSlots(n)
		sample("control: no change", n, 0, updateQuiet)
		sample("Part.Color", n, 0, updatePartColor)
		sample("SurfaceAppearance.Color", n, 0, updateSurfaceColor)
		sample("Transparency WITHIN .5<->.6", n, 0.5, updateWithin)
		sample("Transparency CROSS 0<->0.5", n, 0, updateCross)
	end

	print("[BENCH] ===== done =====")
end)
