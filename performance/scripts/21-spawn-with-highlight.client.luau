--!optimize 2
-- SPAWNING AND DESPAWNING ENEMIES THAT CARRY A HIGHLIGHT.
--
-- Doc 13 settled that a Highlight bound permanently into an enemy is free to FLASH. It says nothing about what
-- that highlight costs to CREATE and DESTROY, which is the cost you actually pay if enemies are spawned on
-- demand instead of pooled. A wave that drops 26 enemies at once pays 26 of whatever this is, on one frame.
--
-- Four construction orders, all ending with the same live enemy:
--
--   PLAIN        clone, configure, parent to Workspace. No highlight - the floor.
--   TEMPLATE     clone a template that ALREADY contains the Highlight, parent to Workspace. One hierarchy event.
--   ADD BEFORE   clone plain, parent the Highlight into the model while the model is still detached, THEN parent
--                the model to Workspace. Still one hierarchy event as far as Workspace is concerned.
--   ADD AFTER    clone plain, parent the model to Workspace, THEN parent a Highlight into it. Two events, and
--                the second one adds a Highlight to something already being rendered - which is exactly what
--                Roblox's docs say "can cause a geometry rebuilding step".
--
-- If ADD AFTER is the expensive one, the fix is free: build the highlight in before the model goes live.
--
-- SPLIT TIMING. Every spawn is timed in four parts - Clone, configure, Parent, and the after-the-fact highlight
-- add - because they suggest different fixes. If Clone dominates, cloning ahead of time into a detached queue
-- helps. If Parent dominates, nothing helps except spreading spawns across frames, which is the question being
-- asked.
--
-- DESPAWN. :Destroy() returns before the work is done (METHODOLOGY trap 7), so the destroy frame is reported
-- alongside the six frames that follow it, as excess over the quiet baseline. Timing the call alone gets this
-- backwards.
--
-- SWEEP. Block B walks M from 1 to 26 so the answer to "how many can I spawn in one frame" is a curve rather
-- than a single number.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local SLIME = ReplicatedStorage:WaitForChild("Models"):WaitForChild("Enemies"):WaitForChild("Slime")

local LIVE_TARGET = 60 -- steady population, sized for the "fewer, stronger enemies" direction
local SLOTS = 120
local BURST_PERIOD = 30 -- frames between spawn events
local DESTROY_OFFSET = 15 -- frames after the spawn that the despawn happens
local TAIL_FRAMES = 6 -- frames after a despawn watched for deferred cleanup

local SETTLE_WINDOW = 1.0
local SETTLE_TOLERANCE = 0.10
local SETTLE_MAX_SECONDS = 20
local SAMPLE_SECONDS = 6.0
local TEARDOWN_SECONDS = 3.0

local AREA_WIDTH = 260
local AREA_HEIGHT = 140
local AREA_DEPTH = 40
local CAM_DISTANCE = 155
local ORBIT_RADIUS = 3
local ORBIT_SPEED = 1.7

local WHITE = Color3.new(1, 1, 1)

local slotX = table.create(SLOTS)
local slotY = table.create(SLOTS)
local slotZ = table.create(SLOTS)
local phase = table.create(SLOTS)

-- Live enemies as a deque: entries [head, tail]. Spawns push the tail, despawns pop the head, so the ones that
-- die are the oldest, which is what a real wave does.
local liveModel = {}
local liveMesh = {}
local liveSlot = {}
local head = 1
local tail = 0
local nextSlot = 0

local clockStart = 0
local focusLost = false
UserInputService.WindowFocusReleased:Connect(function()
	focusLost = true
end)

local root = nil
local templateWithHighlight = nil

local spawnM = 0
local mode = "plain"
local frameIndex = 0
local eventTag = 0
local tailRemaining = 0
local armed = false

local cloneTotal, configTotal, parentTotal, addTotal, destroyTotal = 0, 0, 0, 0, 0
local spawnedCount, destroyedCount = 0, 0

local function buildSlots()
	local columns = math.ceil(math.sqrt(SLOTS * (AREA_WIDTH / AREA_HEIGHT)))
	local rows = math.ceil(SLOTS / columns)
	local stepX = AREA_WIDTH / columns
	local stepY = AREA_HEIGHT / math.max(rows, 1)
	for i = 1, SLOTS do
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

local function newHighlight()
	local highlight = Instance.new("Highlight")
	highlight.FillColor = WHITE
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Enabled = true
	return highlight
end

-- Returns the spawn cost split into its phases. `timed` is false while pre-populating, so warm-up spawns do not
-- pollute the per-spawn averages.
local function spawnOne(timed)
	nextSlot = nextSlot % SLOTS + 1
	local slot = nextSlot

	local t0 = os.clock()
	local model = if mode == "template" then templateWithHighlight:Clone() else SLIME:Clone()
	local t1 = os.clock()

	local mesh = model:FindFirstChildWhichIsA("MeshPart")
	mesh.Anchored = true
	mesh.CanCollide = false
	mesh.CanQuery = false
	mesh.CanTouch = false
	mesh.CFrame = slotCFrame(slot, os.clock() - clockStart)
	if mode == "addBefore" then newHighlight().Parent = model end
	local t2 = os.clock()

	model.Parent = root
	local t3 = os.clock()

	if mode == "addAfter" then newHighlight().Parent = model end
	local t4 = os.clock()

	if timed then
		cloneTotal += t1 - t0
		configTotal += t2 - t1
		parentTotal += t3 - t2
		addTotal += t4 - t3
		spawnedCount += 1
	end

	tail += 1
	liveModel[tail] = model
	liveMesh[tail] = mesh
	liveSlot[tail] = slot
end

local function destroyOne(timed)
	if head > tail then return end
	local model = liveModel[head]
	liveModel[head] = nil
	liveMesh[head] = nil
	liveSlot[head] = nil
	head += 1

	local t0 = os.clock()
	model:Destroy()
	if timed then
		destroyTotal += os.clock() - t0
		destroyedCount += 1
	end
end

local function moveAll(t)
	for i = head, tail do
		local mesh = liveMesh[i]
		if mesh then mesh.CFrame = slotCFrame(liveSlot[i], t) end
	end
end

local function update()
	local t = os.clock() - clockStart
	moveAll(t)

	eventTag = 0
	if not armed then return end

	local slot = frameIndex % BURST_PERIOD
	if slot == 0 then
		for _ = 1, spawnM do
			spawnOne(true)
		end
		eventTag = 1
	elseif slot == DESTROY_OFFSET then
		for _ = 1, spawnM do
			destroyOne(true)
		end
		eventTag = 2
		tailRemaining = TAIL_FRAMES
	elseif tailRemaining > 0 then
		eventTag = 3
		tailRemaining -= 1
	end
	frameIndex += 1
end

local recDt = table.create(8192)
local recUpd = table.create(8192)
local recTag = table.create(8192)
local recording = false
local activeUpdate = nil

RunService.PreRender:Connect(function(dt)
	local fn = activeUpdate
	local cost = 0
	if fn then
		local s = os.clock()
		fn()
		cost = os.clock() - s
	end
	if not recording then return end
	local n = #recDt + 1
	recDt[n] = dt
	recUpd[n] = cost
	recTag[n] = eventTag
end)

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
	return sum / n * 1000,
		sorted[math.max(math.floor(n * 0.5), 1)] * 1000,
		sorted[math.clamp(math.ceil(0.95 * n), 1, n)] * 1000,
		worst * 1000
end

local function settleUntilStable()
	local start = os.clock()
	local prevMed, agreements = nil, 0
	while os.clock() - start < SETTLE_MAX_SECONDS do
		table.clear(recDt)
		table.clear(recUpd)
		table.clear(recTag)
		recording = true
		task.wait(SETTLE_WINDOW)
		recording = false
		local _, med = stats(recDt)
		if med > 0 and prevMed and prevMed > 0 then
			if math.abs(med - prevMed) / prevMed < SETTLE_TOLERANCE then
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

local function countVisible()
	local visible, total = 0, 0
	for i = head, tail do
		local mesh = liveMesh[i]
		if mesh then
			total += 1
			local _, onScreen = camera:WorldToViewportPoint(mesh.Position)
			if onScreen then
				visible += 1
			end
		end
	end
	return visible, total
end

local CAM_AT = CFrame.new(Vector3.new(0, 0, CAM_DISTANCE), Vector3.zero)

local function parkCharacter()
	local character = player.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.Anchored = true
		hrp.CFrame = CFrame.new(0, 500, 0)
	end
end

local function aimCamera()
	parkCharacter()
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 70
	camera.CFrame = CAM_AT
end

local function teardown()
	if root then
		root:Destroy()
		root = nil
	end
	table.clear(liveModel)
	table.clear(liveMesh)
	table.clear(liveSlot)
	head, tail, nextSlot = 1, 0, 0
	task.wait(TEARDOWN_SECONDS)
end

local function sample(variant)
	aimCamera()
	mode = variant.Mode
	spawnM = variant.M

	root = Instance.new("Folder")
	root.Name = "SpawnDiag"
	root.Parent = workspace

	clockStart = os.clock()
	-- Pre-populate untimed and in chunks so the build itself never trips the script timeout (trap 11).
	for i = 1, LIVE_TARGET do
		spawnOne(false)
		if i % 20 == 0 then task.wait() end
	end

	cloneTotal, configTotal, parentTotal, addTotal, destroyTotal = 0, 0, 0, 0, 0
	spawnedCount, destroyedCount = 0, 0
	frameIndex = 0
	eventTag = 0
	tailRemaining = 0
	armed = false
	focusLost = false
	activeUpdate = update

	local settleSeconds, converged = settleUntilStable()

	table.clear(recDt)
	table.clear(recUpd)
	table.clear(recTag)
	recording = true
	armed = true
	local t0 = os.clock()
	task.wait(SAMPLE_SECONDS)
	recording = false
	armed = false
	local wall = os.clock() - t0

	local frames = #recDt
	local _, med, p95, worst = stats(recDt)
	local visible, alive = countVisible()
	local viewport = camera.ViewportSize
	activeUpdate = nil

	local quiet, spawnFrames, destroyFrames, tailF = {}, {}, {}, {}
	for i = 1, frames - 1 do
		local engine = recDt[i + 1] - recUpd[i]
		local tag = recTag[i]
		if tag == 1 then
			spawnFrames[#spawnFrames + 1] = engine
		elseif tag == 2 then
			destroyFrames[#destroyFrames + 1] = engine
		elseif tag == 3 then
			tailF[#tailF + 1] = engine
		else
			quiet[#quiet + 1] = engine
		end
	end

	local _, quietMed = stats(quiet)
	local _, spawnMed, _, spawnWorst = stats(spawnFrames)
	local _, destroyMed, _, destroyWorst = stats(destroyFrames)
	local tailMean, _, _, tailWorst = stats(tailF)

	local perSpawn = math.max(spawnedCount, 1)
	local perDestroy = math.max(destroyedCount, 1)

	print(
		string.format(
			"[SPAWN] %-22s M=%-3d | quiet=%6.2f  SPAWN frame=%8.2f (d=%+8.2f n=%-3d max=%8.2f)  DESTROY frame=%7.2f (d=%+7.2f max=%7.2f)  tail mean=%6.2f (excess %+6.2f max=%7.2f)",
			variant.Label,
			variant.M,
			quietMed,
			spawnMed,
			spawnMed - quietMed,
			#spawnFrames,
			spawnWorst,
			destroyMed,
			destroyMed - quietMed,
			destroyWorst,
			tailMean,
			tailMean - quietMed,
			tailWorst
		)
	)
	print(
		string.format(
			"         luau/spawn: clone=%7.1fus config=%7.1fus parent=%7.1fus addHL=%7.1fus  total=%7.1fus | luau/destroy=%7.1fus | med=%6.2f p95=%6.2f worst=%8.2f settle=%4.1fs%s alive=%d vis=%d vp=%dx%d fps=%5.1f%s",
			cloneTotal / perSpawn * 1e6,
			configTotal / perSpawn * 1e6,
			parentTotal / perSpawn * 1e6,
			addTotal / perSpawn * 1e6,
			(cloneTotal + configTotal + parentTotal + addTotal) / perSpawn * 1e6,
			destroyTotal / perDestroy * 1e6,
			med,
			p95,
			worst,
			settleSeconds,
			if converged then " ok" else " NO",
			alive,
			visible,
			viewport.X,
			viewport.Y,
			frames / wall,
			if focusLost then "  *** FOCUS LOST ***" else ""
		)
	)

	teardown()
end

task.spawn(function()
	task.wait(3)
	local character = player.Character or player.CharacterAdded:Wait()
	character:WaitForChild("HumanoidRootPart", 10)
	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		parkCharacter()
	end)
	aimCamera()

	buildSlots()

	-- The template that already carries its Highlight. Kept detached; cloning from a nil-parented model works.
	templateWithHighlight = SLIME:Clone()
	newHighlight().Parent = templateWithHighlight

	print("[BENCH] ===== spawn / despawn cost of an enemy that carries a Highlight =====")
	print(
		string.format("[BENCH] steady population %d, spawn M then destroy M every %d frames", LIVE_TARGET, BURST_PERIOD)
	)

	print("[BENCH] --- block A: construction order, M=26 ---")
	sample({ Label = "SENTINEL no churn", M = 0, Mode = "plain" })
	sample({ Label = "PLAIN no highlight", M = 26, Mode = "plain" })
	sample({ Label = "TEMPLATE has highlight", M = 26, Mode = "template" })
	sample({ Label = "ADD BEFORE parenting", M = 26, Mode = "addBefore" })
	sample({ Label = "ADD AFTER parenting", M = 26, Mode = "addAfter" })

	print("[BENCH] --- block B: how many fit in one frame ---")
	for _, m in { 1, 4, 8, 13, 26 } do
		sample({ Label = "PLAIN no highlight", M = m, Mode = "plain" })
		sample({ Label = "TEMPLATE has highlight", M = m, Mode = "template" })
	end

	print("[BENCH] ===== done =====")
end)
