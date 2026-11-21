--!optimize 2
-- Motor6D-part vs BillboardGui-on-Attachment: raw render benchmark.
--
-- One entity is ONE THING in both cases. Motor6D side: an anchored base part, one plain part, one Motor6D,
-- moved by writing the joint's Transform. Billboard side: an Attachment on a shared anchored host, a
-- BillboardGui with one ImageLabel, moved by writing the attachment's Position. No meshes, no rigs, no bug
-- models - the point is what the representation itself costs.
--
-- Variants are INTERLEAVED inside each repetition and the best repetition is what gets reported, so a stray
-- background spike lands on one rep of one variant instead of deciding the answer. Window focus is watched
-- throughout: Studio throttles to 60 when it loses focus, which silently floors every number in the run.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Stats = game:GetService("Stats")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local COUNTS = { 600, 1200, 2400, 4800 }
local REPS = 3
local SETTLE_SECONDS = 1.5
local SAMPLE_SECONDS = 4.0

local AREA_WIDTH = 260
local AREA_HEIGHT = 140
local AREA_DEPTH = 40
local CAM_DISTANCE = 155
local ORBIT_RADIUS = 3
local ORBIT_SPEED = 1.7
local ENTITY_SIZE = 2.6

local BILLBOARD_IMAGE = "rbxasset://textures/face.png"

local count = 0
local slotX = table.create(8192)
local slotY = table.create(8192)
local slotZ = table.create(8192)
local phase = table.create(8192)

local joints = table.create(8192)
local attachments = table.create(8192)

local clockStart = 0

-- Studio renders at 60 while unfocused. Tracked rather than assumed, because a throttled sample looks exactly
-- like a slow one.
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

-- Each writes what its representation actually needs to move: the part gets a placed AND turned CFrame because
-- a part has a facing, the billboard gets a position because a billboard has none to write.
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

local function updateBillboard()
	local t = os.clock() - clockStart
	for i = 1, count do
		local a = t * ORBIT_SPEED + phase[i]
		attachments[i].Position =
			Vector3.new(slotX[i] + math.cos(a) * ORBIT_RADIUS, slotY[i] + math.sin(a) * ORBIT_RADIUS, slotZ[i])
	end
end

local root = nil

local function buildMotor(n)
	local folder = Instance.new("Folder")
	folder.Name = "RenderBench"

	for i = 1, n do
		local base = Instance.new("Part")
		base.Name = "MoveBase"
		base.Anchored = true
		base.CanCollide = false
		base.CanQuery = false
		base.CanTouch = false
		base.Transparency = 1
		base.Size = Vector3.one
		base.CFrame = CFrame.new(0, 0, 0)

		local body = Instance.new("Part")
		body.Name = "Body"
		body.Anchored = false
		body.CanCollide = false
		body.CanQuery = false
		body.CanTouch = false
		body.Massless = true
		body.Size = Vector3.new(ENTITY_SIZE, ENTITY_SIZE, ENTITY_SIZE)
		body.Color = Color3.fromRGB(120, 80, 40)
		body.Parent = base

		local joint = Instance.new("Motor6D")
		joint.Name = "MoveJoint"
		joint.Part0 = base
		joint.Part1 = body
		joint.Parent = base
		joints[i] = joint

		base.Parent = folder
	end

	folder.Parent = workspace
	root = folder
	return n * 3
end

local function buildBillboards(n, alwaysOnTop)
	local folder = Instance.new("Folder")
	folder.Name = "RenderBench"

	-- One shared anchored host: attachments carry no physics of their own, so N of them on one part is N
	-- transforms and one assembly, and moving one cannot wake anything.
	local host = Instance.new("Part")
	host.Name = "Host"
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CanTouch = false
	host.Transparency = 1
	host.Size = Vector3.one
	host.CFrame = CFrame.new(0, 0, 0)

	for i = 1, n do
		local attachment = Instance.new("Attachment")
		attachment.Parent = host
		attachments[i] = attachment

		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromScale(ENTITY_SIZE, ENTITY_SIZE)
		billboard.AlwaysOnTop = alwaysOnTop
		billboard.LightInfluence = 0
		billboard.ResetOnSpawn = false

		local image = Instance.new("ImageLabel")
		image.Size = UDim2.fromScale(1, 1)
		image.BackgroundTransparency = 1
		image.Image = BILLBOARD_IMAGE
		image.Parent = billboard

		billboard.Parent = attachment
	end

	host.Parent = folder
	folder.Parent = workspace
	root = folder
	return n * 3 + 1
end

local function teardown()
	if root then
		root:Destroy()
		root = nil
	end
	table.clear(joints)
	table.clear(attachments)
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

local function onScreenCount(positionOf)
	local visible = 0
	local viewport = camera.ViewportSize
	for i = 1, count do
		local point, inFront = camera:WorldToViewportPoint(positionOf(i))
		if inFront and point.X >= 0 and point.X <= viewport.X and point.Y >= 0 and point.Y <= viewport.Y then
			visible += 1
		end
	end
	return visible
end

local function motorPosition(i)
	return joints[i].Part1.Position
end

local function billboardPosition(i)
	return attachments[i].WorldPosition
end

-- variant key -> best (lowest mean frame time) sample seen across reps
local best = {}

local function run(key, label, n, rep, build, update, positionOf)
	local memoryBefore = Stats:GetTotalMemoryUsageMb()
	local instances = build()

	clockStart = os.clock()
	activeUpdate = update
	local connection = RunService.PreRender:Connect(onFrame)

	task.wait(SETTLE_SECONDS)

	local visible = onScreenCount(positionOf)
	local memoryMb = Stats:GetTotalMemoryUsageMb() - memoryBefore

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
	local sample = {
		Label = label,
		Count = n,
		Instances = instances,
		Visible = visible,
		Fps = frameCount / wall,
		MeanMs = meanMs,
		MedianMs = percentile(sorted, 0.5) * 1000,
		P95Ms = percentile(sorted, 0.95) * 1000,
		WorstMs = (sorted[#sorted] or 0) * 1000,
		UpdateUs = (updateTotal / math.max(frameCount, 1)) * 1e6,
		AtCapPct = capped / math.max(frameCount, 1) * 100,
		MemoryMb = memoryMb,
		Throttled = focusLost,
	}

	print(
		string.format(
			"[REP] %-24s n=%-5d rep=%d fps=%6.1f mean=%6.2fms med=%6.2fms p95=%6.2fms upd=%7.1fus atcap=%5.1f%% mem=%6.1fMB vis=%d/%d%s",
			label,
			n,
			rep,
			sample.Fps,
			meanMs,
			sample.MedianMs,
			sample.P95Ms,
			sample.UpdateUs,
			sample.AtCapPct,
			memoryMb,
			visible,
			n,
			if sample.Throttled then "  *** FOCUS LOST ***" else ""
		)
	)

	local bucket = key .. "|" .. n
	local current = best[bucket]
	-- Best-of-reps on mean frame time: a rep that lost focus, or caught a background spike, is noise and the
	-- lowest one is the closest thing to the cost of this representation alone. The second clause is the
	-- first-sample case: take a throttled rep rather than report nothing at all.
	if (not sample.Throttled and (not current or meanMs < current.MeanMs)) or not current then best[bucket] = sample end

	teardown()
end

local function microBench()
	local N = 2000
	local ITERATIONS = 200
	buildSlots(N)

	buildMotor(N)
	task.wait(1)
	local cf = CFrame.new(1, 2, 3) * CFrame.fromEulerAnglesYXZ(0, 0.5, 0)
	local t0 = os.clock()
	for _ = 1, ITERATIONS do
		for i = 1, N do
			joints[i].Transform = cf
		end
	end
	local motorNs = (os.clock() - t0) / (ITERATIONS * N) * 1e9
	teardown()

	buildBillboards(N, false)
	task.wait(1)
	t0 = os.clock()
	for _ = 1, ITERATIONS do
		for i = 1, N do
			attachments[i].CFrame = cf
		end
	end
	local attachmentCFrameNs = (os.clock() - t0) / (ITERATIONS * N) * 1e9

	local v3 = Vector3.new(1, 2, 3)
	t0 = os.clock()
	for _ = 1, ITERATIONS do
		for i = 1, N do
			attachments[i].Position = v3
		end
	end
	local attachmentPositionNs = (os.clock() - t0) / (ITERATIONS * N) * 1e9
	teardown()

	print(
		string.format(
			"[BENCH] RAW WRITE (ns/write, rendering excluded): Motor6D.Transform=%.0f  Attachment.CFrame=%.0f  Attachment.Position=%.0f",
			motorNs,
			attachmentCFrameNs,
			attachmentPositionNs
		)
	)
end

local function setupScene()
	local character = player.Character or player.CharacterAdded:Wait()
	local hrp = character:WaitForChild("HumanoidRootPart", 10)
	if hrp then
		hrp.Anchored = true
		hrp.CFrame = CFrame.new(0, 500, 0)
	end

	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 70
	camera.CFrame = CFrame.new(Vector3.new(0, 0, CAM_DISTANCE), Vector3.zero)
end

local function baseline()
	count = 0
	activeUpdate = nil
	local connection = RunService.PreRender:Connect(onFrame)
	task.wait(1.5)
	focusLost = false
	frameCount = 0
	local wall = os.clock()
	task.wait(3)
	wall = os.clock() - wall
	connection:Disconnect()
	print(
		string.format(
			"[BENCH] BASELINE (empty scene) fps=%.1f%s",
			frameCount / wall,
			if focusLost then "  *** FOCUS LOST - Studio throttles to 60 unfocused ***" else ""
		)
	)
end

task.spawn(function()
	task.wait(3)
	setupScene()
	print("[BENCH] ===== start ===== viewport=" .. tostring(camera.ViewportSize))
	baseline()
	microBench()

	for _, n in COUNTS do
		buildSlots(n)
		for rep = 1, REPS do
			run("motor", "Motor6D + part", n, rep, function()
				return buildMotor(n)
			end, updateMotor, motorPosition)

			run("bb_false", "Billboard AOT=false", n, rep, function()
				return buildBillboards(n, false)
			end, updateBillboard, billboardPosition)

			run("bb_true", "Billboard AOT=true", n, rep, function()
				return buildBillboards(n, true)
			end, updateBillboard, billboardPosition)
		end
	end

	print("[BENCH] ===== BEST OF " .. REPS .. " REPS =====")
	for _, n in COUNTS do
		for _, key in { "motor", "bb_false", "bb_true" } do
			local sample = best[key .. "|" .. n]
			if sample then
				print(
					string.format(
						"[BEST] %-22s n=%-5d fps=%6.1f mean=%6.2fms med=%6.2fms p95=%6.2fms worst=%6.2fms upd=%7.1fus atcap=%5.1f%% mem=%6.1fMB inst=%d vis=%d/%d",
						sample.Label,
						n,
						sample.Fps,
						sample.MeanMs,
						sample.MedianMs,
						sample.P95Ms,
						sample.WorstMs,
						sample.UpdateUs,
						sample.AtCapPct,
						sample.MemoryMb,
						sample.Instances,
						sample.Visible,
						n
					)
				)
			end
		end
	end
	print("[BENCH] ===== done =====")
end)
