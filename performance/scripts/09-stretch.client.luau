--!optimize 2
-- THE VACUUM STRETCH, ON A SKINNED MESH.
--
-- BugsController deforms a gripped bug by writing SpecialMesh.Scale and SpecialMesh.Offset - pure render
-- properties that cost no physics, which is the stated reason bug parts are authored as Parts wearing meshes
-- rather than as MeshParts. A skinned MeshPart has no SpecialMesh, so the only equivalent is writing
-- MeshPart.Size, and Size is not a render property: it is geometry the engine has to react to.
--
-- So this measures the two deformation paths side by side, one part against one part, same count, same motion:
--
--   Skeleton   MeshPart.Size            <- what a skinned rig would have to do
--   RoachBody  SpecialMesh.Scale+Offset <- what the shipping stretch actually does
--
-- Both at TWO populations, because the vacuum does not stretch the room:
--   ALL    every instance deforming every frame - the worst case
--   GRIP   40 instances deforming, the rest only moving, roughly what a cone actually holds
--
-- The volume-preserving shape is the real one: the axis along the pull grows and the two across it shrink by
-- the square root, so the two paths are asked for the same deformation and not just the same number of writes.
--
-- A burst variant runs Size on one frame in thirty, split into change frames and quiet frames, because if Size
-- rebuilds anything the cost shows up as a spike on exactly the frames that wrote it.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local Models = ReplicatedStorage:WaitForChild("Models")
local SKELETON = Models:WaitForChild("Skeleton")
local ROACH_BODY = Models:WaitForChild("Bugs"):WaitForChild("Roach"):WaitForChild("Body")

local N = 2400
local GRIP = 40
local SETTLE_SECONDS = 2.0
local SAMPLE_SECONDS = 5.0
local TEARDOWN_SECONDS = 2.5
local BURST_PERIOD = 30

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
local meshParts = table.create(4096)
local joints = table.create(4096)
local specialMeshes = table.create(4096)

local BASE_SIZE = Vector3.new(2, 2, 2)

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

-- Volume preserving: what the axis along the pull gains, the two across it give back as a square root.
local function stretchFactors(t, i)
	local s = (math.sin(t * 2 + i * 0.017) + 1) * 0.5
	local along = 1 + s * 1.5
	return along, 1 / math.sqrt(along), s
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

local function updateBonesOnly()
	didChange = false
	moveBones(os.clock() - clockStart)
end

local function sizeRange(t, from, to)
	for i = from, to do
		local along, across = stretchFactors(t, i)
		meshParts[i].Size = Vector3.new(BASE_SIZE.X * across, BASE_SIZE.Y * across, BASE_SIZE.Z * along)
	end
end

local function updateSizeAll()
	local t = os.clock() - clockStart
	moveBones(t)
	sizeRange(t, 1, count)
	didChange = true
end

local function updateSizeGrip()
	local t = os.clock() - clockStart
	moveBones(t)
	sizeRange(t, 1, math.min(GRIP, count))
	didChange = true
end

local function updateSizeBurst()
	local t = os.clock() - clockStart
	moveBones(t)
	if frameIndex % BURST_PERIOD ~= 0 then
		didChange = false
		return
	end
	sizeRange(t, 1, count)
	didChange = true
end

local function updateJointsOnly()
	didChange = false
	moveJoints(os.clock() - clockStart)
end

local function scaleRange(t, from, to)
	for i = from, to do
		local along, across, s = stretchFactors(t, i)
		local mesh = specialMeshes[i]
		mesh.Scale = Vector3.new(across, across, along)
		-- Spend the growth out of the end the nozzle has hold of, the way the shipping stretch does.
		mesh.Offset = Vector3.new(0, 0, -s * 0.45)
	end
end

local function updateScaleAll()
	local t = os.clock() - clockStart
	moveJoints(t)
	scaleRange(t, 1, count)
	didChange = true
end

local function updateScaleGrip()
	local t = os.clock() - clockStart
	moveJoints(t)
	scaleRange(t, 1, math.min(GRIP, count))
	didChange = true
end

local root = nil

local function buildSkeletons(n)
	local folder = Instance.new("Folder")
	folder.Name = "StretchDiag"
	for i = 1, n do
		local model = SKELETON:Clone()
		local mesh = model:FindFirstChildWhichIsA("MeshPart")
		mesh.Anchored = true
		mesh.CanCollide = false
		mesh.CanQuery = false
		mesh.CanTouch = false
		mesh.CFrame = CFrame.new(0, 0, 0)
		mesh.Size = BASE_SIZE
		meshParts[i] = mesh
		bones[i] = mesh:FindFirstChildWhichIsA("Bone")
		model.Parent = folder
	end
	folder.Parent = workspace
	root = folder
end

local function buildRoachBodies(n)
	local folder = Instance.new("Folder")
	folder.Name = "StretchDiag"
	for i = 1, n do
		local base = Instance.new("Part")
		base.Anchored = true
		base.CanCollide = false
		base.CanQuery = false
		base.CanTouch = false
		base.Transparency = 1
		base.Size = Vector3.one
		base.CFrame = CFrame.new(0, 0, 0)

		local body = ROACH_BODY:Clone()
		for _, child in body:GetChildren() do
			if not child:IsA("SpecialMesh") then child:Destroy() end
		end
		body.Anchored = false
		body.CanCollide = false
		body.CanQuery = false
		body.CanTouch = false
		body.Massless = true
		body.Parent = base
		specialMeshes[i] = body:FindFirstChildWhichIsA("SpecialMesh")

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

local function teardown()
	if root then
		root:Destroy()
		root = nil
	end
	table.clear(bones)
	table.clear(meshParts)
	table.clear(joints)
	table.clear(specialMeshes)
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

local function sample(label, build, update, splitOnChange)
	build(N)
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
	local wall = os.clock()
	task.wait(SAMPLE_SECONDS)
	wall = os.clock() - wall

	connection:Disconnect()
	activeUpdate = nil

	if splitOnChange then
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
				"[STR ] %-34s BURST | ENGINE change n=%-3d mean=%7.2f med=%7.2f max=%8.2f | quiet med=%6.2f max=%7.2f | delta=%+8.2fms%s",
				label,
				#changeEngine,
				ceMean,
				ceMed,
				ceMax,
				qeMed,
				qeMax,
				ceMean - qeMean,
				if focusLost then "  *** FOCUS LOST ***" else ""
			)
		)
		teardown()
		return
	end

	local all, engine = {}, {}
	for i = 1, frameCount - 1 do
		all[#all + 1] = frameTimes[i + 1]
		engine[#engine + 1] = frameTimes[i + 1] - updateTimes[i]
	end
	local fMean, fMed, fMax = stats(all)
	local eMean, eMed = stats(engine)
	local uMean = 0
	for i = 1, frameCount do
		uMean += updateTimes[i]
	end
	uMean = uMean / math.max(frameCount, 1) * 1e6

	print(
		string.format(
			"[STR ] %-34s fps=%6.1f frame mean=%7.2f med=%7.2f max=%8.2f | script=%8.1fus | engine mean=%7.2f med=%7.2f%s",
			label,
			frameCount / wall,
			fMean,
			fMed,
			fMax,
			uMean,
			eMean,
			eMed,
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

	buildSlots(N)
	print(
		"[BENCH] ===== vacuum stretch: MeshPart.Size vs SpecialMesh.Scale+Offset, n="
			.. N
			.. ", grip="
			.. GRIP
			.. " ====="
	)

	sample("SKINNED: move only (control)", buildSkeletons, updateBonesOnly, false)
	sample("SKINNED: MeshPart.Size GRIP 40", buildSkeletons, updateSizeGrip, false)
	sample("SKINNED: MeshPart.Size ALL", buildSkeletons, updateSizeAll, false)
	sample("SKINNED: MeshPart.Size burst ALL", buildSkeletons, updateSizeBurst, true)

	sample("TODAY: move only (control)", buildRoachBodies, updateJointsOnly, false)
	sample("TODAY: Scale+Offset GRIP 40", buildRoachBodies, updateScaleGrip, false)
	sample("TODAY: Scale+Offset ALL", buildRoachBodies, updateScaleAll, false)

	print("[BENCH] ===== done =====")
end)
