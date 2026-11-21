--!optimize 2
-- ANIMATED: a bug rig walking on its procedural gait vs a skinned mesh playing an AnimationTrack.
--
-- Matched on joint count. The Skeleton mesh has 5 bones (Root + Arm_L, Arm_R, Leg_L, Leg_R), so the bug side is
-- the Slug: MoveBase + Body + Goo + AntennaL + AntennaR + Tail, which is 5 Motor6Ds (one root and four limbs).
--
-- The bug side runs the REAL BugGait module, not an imitation of it - same LUT, same Apply, same one-index-and-
-- a-property-write per joint the shipping render loop does. How many joints BugGait actually animates is
-- measured off the rig and printed, because it classifies limbs by geometry and leaves wings at rest, so it may
-- animate fewer than four. A parity variant covers that: it drives ALL four limb joints off a shared 128-step
-- LUT, which is BugGait's exact runtime shape with the joint count pinned to the Skeleton's four.
--
-- Both sides also get a no-animation row. Animation cost is the difference between the two rows on the same
-- side; comparing a walking bug against a sliding skeleton would just be measuring the animator's existence.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local BugGait = require(script.Parent:WaitForChild("Client"):WaitForChild("Utils"):WaitForChild("BugGait"))

local Models = ReplicatedStorage:WaitForChild("Models")
local SKELETON = Models:WaitForChild("Skeleton")
local SLUG = Models:WaitForChild("Bugs"):WaitForChild("Slug")
local WALK_ANIM = ReplicatedStorage:WaitForChild("Animations"):WaitForChild("SkeletonWalk")

local COUNTS = { 1200, 2400 }
local SETTLE_SECONDS = 1.5
local SAMPLE_SECONDS = 3.5
local TEARDOWN_SECONDS = 2.5

local AREA_WIDTH = 260
local AREA_HEIGHT = 140
local AREA_DEPTH = 40
local CAM_DISTANCE = 155
local ORBIT_RADIUS = 3
local ORBIT_SPEED = 1.7

local GAIT_STEPS = 128

local count = 0
local slotX = table.create(8192)
local slotY = table.create(8192)
local slotZ = table.create(8192)
local phase = table.create(8192)

local joints = table.create(8192) -- root movement joint per entity
local bones = table.create(8192) -- root movement bone per entity
local gaitRigs = table.create(8192) -- TGaitRig per entity
local limbJoints = table.create(8192) -- { Motor6D } per entity, for the parity variant

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

-- One shared 128-step pose table, the same bargain BugGait makes: the trigonometry is paid once for the session
-- and what is left per joint per frame is an index and a property write.
local PARITY_LUT = table.create(GAIT_STEPS)
for s = 1, GAIT_STEPS do
	local t = (s - 1) / GAIT_STEPS * math.pi * 2
	PARITY_LUT[s] = CFrame.Angles(math.cos(t) * 0.5, 0, 0)
end

local function updateMotorOnly()
	local t = os.clock() - clockStart
	for i = 1, count do
		joints[i].Transform = slotCFrame(i, t)
	end
end

local function updateBoneOnly()
	local t = os.clock() - clockStart
	for i = 1, count do
		bones[i].Transform = slotCFrame(i, t)
	end
end

-- Movement plus the real gait, which is what a walking bug costs.
local function updateGait()
	local t = os.clock() - clockStart
	local step = math.floor(t / BugGait.PeriodSeconds * GAIT_STEPS)
	for i = 1, count do
		joints[i].Transform = slotCFrame(i, t)
		local rig = gaitRigs[i]
		if rig then BugGait.Apply(rig, step + i, 0) end
	end
end

-- Movement plus four limb joints, pinned to the Skeleton's four animated bones.
local function updateParity()
	local t = os.clock() - clockStart
	local step = math.floor(t / BugGait.PeriodSeconds * GAIT_STEPS)
	for i = 1, count do
		joints[i].Transform = slotCFrame(i, t)
		local limbs = limbJoints[i]
		local pose = PARITY_LUT[(step + i) % GAIT_STEPS + 1]
		for k = 1, #limbs do
			limbs[k].Transform = pose
		end
	end
end

local root = nil

local function newFolder()
	local folder = Instance.new("Folder")
	folder.Name = "AnimDiag"
	return folder
end

local function buildCubePart(n)
	local folder = newFolder()
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

local gaitJointCount = -1

-- The Slug rig, exactly as authored. Its own MoveBase is anchored and its root MoveJoint carries the world
-- CFrame, which is how BugsController drives every bug.
local function buildSlug(n, measureGait, collectLimbs)
	local folder = newFolder()
	for i = 1, n do
		local model = SLUG:Clone()
		local base = model:FindFirstChild("MoveBase")
		local body = model:FindFirstChild("Body")
		base.Anchored = true
		base.CanCollide = false
		base.CanQuery = false
		base.CanTouch = false
		base.CFrame = CFrame.new(0, 0, 0)

		local rootJoint
		local limbs = {}
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.CanCollide = false
				descendant.CanQuery = false
				descendant.CanTouch = false
				if descendant ~= base then
					descendant.Anchored = false
					descendant.Massless = true
				end
			elseif descendant:IsA("Motor6D") then
				if descendant.Part1 == body then
					rootJoint = descendant
				else
					limbs[#limbs + 1] = descendant
				end
			elseif descendant:IsA("Sound") then
				descendant:Destroy()
			end
		end

		joints[i] = rootJoint
		if collectLimbs then limbJoints[i] = limbs end
		if measureGait then
			local rig = BugGait.Measure(model)
			gaitRigs[i] = rig
			if i == 1 then gaitJointCount = if rig then #rig.Joints else 0 end
		end

		model.Parent = folder
	end
	folder.Parent = workspace
	root = folder
end

-- The Skeleton, Ballarc-style: MeshPart anchored at the origin, Root bone carrying the world CFrame. With
-- `animate`, each one gets its own Animator playing SkeletonWalk, which is the per-entity object the procedural
-- gait exists to avoid.
local function buildSkeleton(n, animate)
	local folder = newFolder()
	local tracks = table.create(n)
	for i = 1, n do
		local model = SKELETON:Clone()
		local mesh = model:FindFirstChildWhichIsA("MeshPart")
		mesh.Anchored = true
		mesh.CanCollide = false
		mesh.CanQuery = false
		mesh.CanTouch = false
		mesh.CFrame = CFrame.new(0, 0, 0)
		bones[i] = mesh:FindFirstChildWhichIsA("Bone")

		if animate then
			local controller = model:FindFirstChildWhichIsA("AnimationController")
			local animator = controller:FindFirstChildWhichIsA("Animator")
			if not animator then
				animator = Instance.new("Animator")
				animator.Parent = controller
			end
			model.Parent = folder
			local ok, track = pcall(animator.LoadAnimation, animator, WALK_ANIM)
			if ok and track then
				track.Looped = true
				track:Play(0)
				-- Spread the phase so they are not one synchronised block, the way a room of bugs is not.
				track.TimePosition = (i % 100) / 100 * math.max(track.Length, 0.01)
				tracks[#tracks + 1] = track
			end
		else
			model.Parent = folder
		end
	end
	folder.Parent = workspace
	root = folder
	return #tracks
end

local function teardown()
	if root then
		root:Destroy()
		root = nil
	end
	table.clear(joints)
	table.clear(bones)
	table.clear(gaitRigs)
	table.clear(limbJoints)
	task.wait(TEARDOWN_SECONDS)
end

local frameCount = 0
local frameTimes = table.create(16384)
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

local log = {}

local function sample(label, n, build, update, note)
	local extra = build(n) or ""
	clockStart = os.clock()
	activeUpdate = update
	local connection = RunService.PreRender:Connect(onFrame)

	task.wait(SETTLE_SECONDS)

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
	local medianMs = percentile(sorted, 0.5) * 1000
	local p95Ms = percentile(sorted, 0.95) * 1000
	local fps = frameCount / wall
	local updUs = (updateTotal / math.max(frameCount, 1)) * 1e6

	log[#log + 1] = { Label = label, Count = n, Fps = fps, MedianMs = medianMs, P95Ms = p95Ms, UpdUs = updUs }

	print(
		string.format(
			"[DIAG] %-34s n=%-5d fps=%6.1f med=%7.2fms p95=%8.2fms upd=%8.1fus %s%s%s",
			label,
			n,
			fps,
			medianMs,
			p95Ms,
			updUs,
			note or "",
			tostring(extra),
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

	print("[BENCH] ===== animated: bug gait vs skinned AnimationTrack =====")

	for _, n in COUNTS do
		buildSlots(n)
		sample("SENTINEL cube Part", n, buildCubePart, updateMotorOnly)

		sample("Slug root only (no anim)", n, function(c)
			buildSlug(c, false, false)
		end, updateMotorOnly)
		sample("Slug + BugGait (real)", n, function(c)
			buildSlug(c, true, false)
		end, updateGait, "gaitJoints=")
		sample("Slug + LUT anim (all 4 limbs)", n, function(c)
			buildSlug(c, false, true)
		end, updateParity)

		sample("Skeleton bone only (no anim)", n, function(c)
			buildSkeleton(c, false)
		end, updateBoneOnly)
		sample("Skeleton + AnimationTrack", n, function(c)
			buildSkeleton(c, true)
		end, updateBoneOnly, "tracksPlaying=")

		sample("SENTINEL cube Part", n, buildCubePart, updateMotorOnly)
	end

	print("[BENCH] BugGait animated joints per Slug rig = " .. gaitJointCount)
	print("[BENCH] ===== SUMMARY =====")
	for _, e in log do
		print(
			string.format(
				"[SUM ] %-34s n=%-5d fps=%6.1f med=%7.2fms p95=%8.2fms upd=%8.1fus",
				e.Label,
				e.Count,
				e.Fps,
				e.MedianMs,
				e.P95Ms,
				e.UpdUs
			)
		)
	end
	print("[BENCH] ===== done =====")
end)
