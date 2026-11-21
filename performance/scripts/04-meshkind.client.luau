--!optimize 2
-- Does a Part wearing a SpecialMesh hit the Motor6D+MeshPart cliff, or dodge it?
--
-- One part against one part. The bug side is Roach.Body exactly as authored - a Part with a SpecialMesh - with
-- its child joints and sound stripped off so it is a single part and nothing else. The other side is the Test
-- MeshPart, which is the thing that collapsed.
--
-- Roach.Body is 0.4 x 0.2 x 0.9 and the Test mesh is 2 x 2 x 2, so a bare win for the SpecialMesh could always
-- be waved away as "it is just smaller on screen". Hence the scaled variant: the same Part+SpecialMesh grown to
-- roughly the Test mesh's footprint. If both SpecialMesh rows stay flat, footprint is not the explanation.
--
-- The sentinel (cube Part on a Motor6D) runs between every variant. If it drifts, nothing here is trustworthy.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local Models = ReplicatedStorage:WaitForChild("Models")
local TEST_MODEL = Models:WaitForChild("Test")
local TEST_MESH = TEST_MODEL:FindFirstChildWhichIsA("MeshPart")
local ROACH_BODY = Models:WaitForChild("Bugs"):WaitForChild("Roach"):WaitForChild("Body")

local N = 4800
local SETTLE_SECONDS = 1.5
local SAMPLE_SECONDS = 3.0
local TEARDOWN_SECONDS = 2.5

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

local root = nil

local function newFolder()
	local folder = Instance.new("Folder")
	folder.Name = "MeshKindDiag"
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

local function attach(base, body, i, folder)
	body.Anchored = false
	body.CanCollide = false
	body.CanQuery = false
	body.CanTouch = false
	body.Massless = true
	body.Parent = base

	local joint = Instance.new("Motor6D")
	joint.Part0 = base
	joint.Part1 = body
	joint.Parent = base
	joints[i] = joint
	base.Parent = folder
end

local function buildCubePart(n)
	local folder = newFolder()
	for i = 1, n do
		local base = makeBase()
		local body = Instance.new("Part")
		body.Size = Vector3.new(2, 2, 2)
		attach(base, body, i, folder)
	end
	folder.Parent = workspace
	root = folder
end

-- Roach.Body as authored: a Part with a SpecialMesh, everything else stripped so it is ONE part.
local function buildSpecialMesh(n, scale)
	local folder = newFolder()
	for i = 1, n do
		local base = makeBase()
		local body = ROACH_BODY:Clone()

		for _, child in body:GetChildren() do
			if not child:IsA("SpecialMesh") then child:Destroy() end
		end

		if scale then
			body.Size = body.Size * scale
			local mesh = body:FindFirstChildWhichIsA("SpecialMesh")
			if mesh then mesh.Scale = mesh.Scale * scale end
		end

		attach(base, body, i, folder)
	end
	folder.Parent = workspace
	root = folder
end

-- The known collapse, as a positive control: if this does NOT collapse, the run is broken.
local function buildMeshPart(n)
	local folder = newFolder()
	for i = 1, n do
		local base = makeBase()
		attach(base, TEST_MESH:Clone(), i, folder)
	end
	folder.Parent = workspace
	root = folder
end

local function buildBone(n)
	local folder = newFolder()
	for i = 1, n do
		local model = TEST_MODEL:Clone()
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
	local worstMs = (sorted[#sorted] or 0) * 1000
	local fps = frameCount / wall

	log[#log + 1] = { Label = label, Pass = pass, Fps = fps, MedianMs = medianMs, P95Ms = p95Ms, WorstMs = worstMs }

	print(
		string.format(
			"[DIAG] pass%d %-38s fps=%6.1f med=%7.2fms p95=%8.2fms worst=%8.2fms%s",
			pass,
			label,
			fps,
			medianMs,
			p95Ms,
			worstMs,
			if focusLost then "  *** FOCUS LOST ***" else ""
		)
	)

	teardown()
end

local SENTINEL = { Label = "SENTINEL cube Part", Build = buildCubePart, Update = updateMotor }

local VARIANTS = {
	{
		Label = "M6D + Part+SpecialMesh (as authored)",
		Update = updateMotor,
		Build = function(n)
			buildSpecialMesh(n, nil)
		end,
	},
	{
		Label = "M6D + Part+SpecialMesh (scaled x2.2)",
		Update = updateMotor,
		Build = function(n)
			buildSpecialMesh(n, 2.2)
		end,
	},
	{ Label = "M6D + MeshPart (control, collapses)", Build = buildMeshPart, Update = updateMotor },
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

	local roachMesh = ROACH_BODY:FindFirstChildWhichIsA("SpecialMesh")
	print(
		string.format(
			"[BENCH] Roach.Body size=%s  mesh.Scale=%s  MeshType=%s",
			tostring(ROACH_BODY.Size),
			if roachMesh then tostring(roachMesh.Scale) else "nil",
			if roachMesh then tostring(roachMesh.MeshType) else "nil"
		)
	)
	print("[BENCH] ===== 1 part vs 1 part @ n=" .. N .. " =====")

	buildSlots(N)
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

	print("[BENCH] ===== SENTINEL DRIFT =====")
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
					"[VAR ] pass%d %-38s fps=%6.1f med=%7.2fms p95=%8.2fms worst=%8.2fms",
					entry.Pass,
					entry.Label,
					entry.Fps,
					entry.MedianMs,
					entry.P95Ms,
					entry.WorstMs
				)
			)
		end
	end
	print("[BENCH] ===== done =====")
end)
