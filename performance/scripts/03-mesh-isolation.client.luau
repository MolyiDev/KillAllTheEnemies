--!optimize 2
-- WHY does Motor6D + the Test mesh collapse when Motor6D + a cube part does not?
--
-- The first attempt at this could not answer it: the three mesh variants got monotonically worse in the order
-- they ran (46.8 -> 4.0 -> 3.2 fps), which tracks RUN ORDER, not the variable being tested. Building and
-- destroying 4800 MeshParts per run degrades the session, so any single-pass comparison is measuring drift.
--
-- So this version is built to detect its own drift instead of trusting itself:
--   * a SENTINEL (the cube-part variant) runs at the start, twice in the middle and at the end. If the sentinel
--     is stable, the differences between variants are real; if the sentinel decays, nothing else here means
--     anything and the run says so.
--   * pass 2 runs every variant in REVERSE order, so an ordering bias shows up as a disagreement between passes.
--   * teardown waits long enough for the engine to actually reclaim the instances.
--
-- What is isolated, one variable at a time, all at n=4800:
--   bone present or not -> the skinned/deformable render path
--   CastShadow on/off   -> re-rendering each instance into the shadow map
--   joint or no joint   -> anchored MeshPart written straight to .CFrame uses no Motor6D and no assembly.
--                          If that is fast, the joint/assembly is the culprit; if it collapses too, it is the
--                          MeshPart itself and the joint is innocent.
-- (CollisionFidelity is not testable here - a LocalScript lacks the Plugin capability to write it.)

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local TEMPLATE = ReplicatedStorage:WaitForChild("Models"):WaitForChild("Test")
local MESH_TEMPLATE = TEMPLATE:FindFirstChildWhichIsA("MeshPart")

local N = 4800
local SETTLE_SECONDS = 1.5
local SAMPLE_SECONDS = 3.5
local TEARDOWN_SECONDS = 3.0

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
local parts = table.create(8192)

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

local function updateMotor()
	local t = os.clock() - clockStart
	for i = 1, count do
		joints[i].Transform = slotCFrame(i, t)
	end
end

local function updateBone()
	local t = os.clock() - clockStart
	for i = 1, count do
		bones[i].Transform = slotCFrame(i, t)
	end
end

local function updateCFrame()
	local t = os.clock() - clockStart
	for i = 1, count do
		parts[i].CFrame = slotCFrame(i, t)
	end
end

local root = nil

local function newFolder()
	local folder = Instance.new("Folder")
	folder.Name = "MeshDiag"
	return folder
end

local function makeBase()
	local base = Instance.new("Part")
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

local function buildMotorMesh(n, keepBone, castShadow)
	local folder = newFolder()
	for i = 1, n do
		local base = makeBase()
		local mesh = MESH_TEMPLATE:Clone()
		mesh.Anchored = false
		mesh.CanCollide = false
		mesh.CanQuery = false
		mesh.CanTouch = false
		mesh.Massless = true
		mesh.CastShadow = castShadow
		if not keepBone then
			local bone = mesh:FindFirstChildWhichIsA("Bone")
			if bone then bone:Destroy() end
		end
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

-- No joint, no assembly: an anchored MeshPart written straight to .CFrame.
local function buildCFrameMesh(n, keepBone)
	local folder = newFolder()
	for i = 1, n do
		local mesh = MESH_TEMPLATE:Clone()
		mesh.Anchored = true
		mesh.CanCollide = false
		mesh.CanQuery = false
		mesh.CanTouch = false
		if not keepBone then
			local bone = mesh:FindFirstChildWhichIsA("Bone")
			if bone then bone:Destroy() end
		end
		parts[i] = mesh
		mesh.Parent = folder
	end
	folder.Parent = workspace
	root = folder
end

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
	table.clear(parts)
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

local function sample(label, pass, build, update)
	build(N)
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

	log[#log + 1] = { Label = label, Pass = pass, Fps = fps, MedianMs = medianMs, P95Ms = p95Ms }

	print(
		string.format(
			"[DIAG] pass%d %-32s fps=%6.1f med=%7.2fms p95=%8.2fms upd=%7.1fus%s",
			pass,
			label,
			fps,
			medianMs,
			p95Ms,
			(updateTotal / math.max(frameCount, 1)) * 1e6,
			if focusLost then "  *** FOCUS LOST ***" else ""
		)
	)

	teardown()
end

local SENTINEL = { Label = "SENTINEL cube Part", Build = buildMotorPart, Update = updateMotor }

local VARIANTS = {
	{
		Label = "M6D + Mesh (bone, shadow)",
		Update = updateMotor,
		Build = function(n)
			buildMotorMesh(n, true, true)
		end,
	},
	{
		Label = "M6D + Mesh (NO bone, shadow)",
		Update = updateMotor,
		Build = function(n)
			buildMotorMesh(n, false, true)
		end,
	},
	{
		Label = "M6D + Mesh (bone, NO shadow)",
		Update = updateMotor,
		Build = function(n)
			buildMotorMesh(n, true, false)
		end,
	},
	{
		Label = "CFrame + Mesh (bone, NO joint)",
		Update = updateCFrame,
		Build = function(n)
			buildCFrameMesh(n, true)
		end,
	},
	{
		Label = "CFrame + Mesh (NO bone, NO joint)",
		Update = updateCFrame,
		Build = function(n)
			buildCFrameMesh(n, false)
		end,
	},
	{ Label = "Bone.Transform (Ballarc)", Build = buildBone, Update = updateBone },
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

	buildSlots(N)
	print("[BENCH] ===== isolation @ n=" .. N .. ", sentinel between every variant =====")

	-- Pass 1 forward, pass 2 reversed, sentinel before each variant so drift is visible at every step.
	for pass = 1, 2 do
		sample(SENTINEL.Label, pass, SENTINEL.Build, SENTINEL.Update)
		local order = {}
		for i = 1, #VARIANTS do
			order[i] = if pass == 1 then VARIANTS[i] else VARIANTS[#VARIANTS - i + 1]
		end
		for _, v in order do
			sample(v.Label, pass, v.Build, v.Update)
			sample(SENTINEL.Label, pass, SENTINEL.Build, SENTINEL.Update)
		end
	end

	print("[BENCH] ===== SENTINEL DRIFT (must stay flat for the rest to mean anything) =====")
	for _, entry in log do
		if entry.Label == SENTINEL.Label then
			print(string.format("[SENT] pass%d fps=%6.1f med=%7.2fms", entry.Pass, entry.Fps, entry.MedianMs))
		end
	end

	print("[BENCH] ===== VARIANTS =====")
	for _, entry in log do
		if entry.Label ~= SENTINEL.Label then
			print(
				string.format(
					"[VAR ] pass%d %-32s fps=%6.1f med=%7.2fms p95=%8.2fms",
					entry.Pass,
					entry.Label,
					entry.Fps,
					entry.MedianMs,
					entry.P95Ms
				)
			)
		end
	end
	print("[BENCH] ===== done =====")
end)
