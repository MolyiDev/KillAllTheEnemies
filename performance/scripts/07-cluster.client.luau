--!optimize 2
-- Does the ~1000ms transparency spike reproduce, and is it the transparency or the run order?
--
-- THIS IS ALSO THE ROBLOX REPRO CASE. Roblox staff asked for one: "if you are still getting significant
-- FastCluster rebuild time for transparency/color changes, please submit a reproducible case for us to debug."
-- Run it and read the ORIGINAL / WITHIN / CROSS rows against the control and COLOR rows.
--
-- At 1800 slug rigs, Part.Transparency measured +749ms of engine time per change (median 998ms). At 900 rigs the
-- same test measured NOTHING - CROSS came back at -0.07ms with a 4.94ms max. A 2x count difference cannot
-- produce a 200x effect, so one of those two runs is not measuring what it says.
--
-- The suspect is run order. In the 1800 run, transparency ran LAST, after four previous variants had each built
-- and destroyed a scene of thousands of instances, so it saw the session at its most fragmented - and it only
-- caught FOUR change samples, because each one ate about a second.
--
-- So: same count as the run that showed the spike, and CROSS runs BOTH first and last. If the spike is
-- transparency, both CROSS runs show it. If it is accumulated session state, only the last one does. If neither
-- does, the original number was an artefact and should be withdrawn.
--
-- (Result: it reproduces first AND last, and WITHIN - which never touches zero - is the worst row of all. So it
-- is neither run order nor the opaque/transparent boundary. On Part rigs it is a count threshold.)

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local SLUG = ReplicatedStorage:WaitForChild("Models"):WaitForChild("Bugs"):WaitForChild("Slug")

local SLUG_COUNT = 1800
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

local joints = table.create(8192)
local rigParts = table.create(8192)

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

local function moveJoints(t)
	for i = 1, count do
		joints[i].Transform = slotCFrame(i, t)
	end
end

local function isBurstFrame()
	return frameIndex % BURST_PERIOD == 0
end

local function writeTransparency(alpha)
	for i = 1, count do
		local parts = rigParts[i]
		for k = 1, #parts do
			parts[k].Transparency = alpha
		end
	end
end

local function updateQuiet()
	didChange = false
	moveJoints(os.clock() - clockStart)
end

-- Crosses the opaque/transparent boundary every time.
local function updateCross()
	moveJoints(os.clock() - clockStart)
	if not isBurstFrame() then
		didChange = false
		return
	end
	writeTransparency(if (frameIndex / BURST_PERIOD) % 2 == 0 then 0 else 0.5)
	didChange = true
end

-- Always transparent, never touches the boundary.
local function updateWithin()
	moveJoints(os.clock() - clockStart)
	if not isBurstFrame() then
		didChange = false
		return
	end
	writeTransparency(if (frameIndex / BURST_PERIOD) % 2 == 0 then 0.5 else 0.6)
	didChange = true
end

-- The exact cycle the original 1800 run used: four distinct values, one of which is 0.
local function updateOriginalCycle()
	moveJoints(os.clock() - clockStart)
	if not isBurstFrame() then
		didChange = false
		return
	end
	writeTransparency((frameIndex / BURST_PERIOD % 4) * 0.2)
	didChange = true
end

local function updateColor()
	moveJoints(os.clock() - clockStart)
	if not isBurstFrame() then
		didChange = false
		return
	end
	local k = frameIndex / BURST_PERIOD
	local colour = Color3.new((k % 5) / 5, (k % 7) / 7, (k % 3) / 3)
	for i = 1, count do
		local parts = rigParts[i]
		for j = 1, #parts do
			parts[j].Color = colour
		end
	end
	didChange = true
end

local root = nil

local function buildSlugs(n, startTransparency)
	local folder = Instance.new("Folder")
	folder.Name = "ClusterDiag"
	for i = 1, n do
		local model = SLUG:Clone()
		local base = model:FindFirstChild("MoveBase")
		local body = model:FindFirstChild("Body")
		base.Anchored = true
		base.CanCollide = false
		base.CanQuery = false
		base.CanTouch = false
		base.CFrame = CFrame.new(0, 0, 0)

		local parts = {}
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.CanCollide = false
				descendant.CanQuery = false
				descendant.CanTouch = false
				if descendant ~= base then
					descendant.Anchored = false
					descendant.Massless = true
					descendant.Transparency = startTransparency
					parts[#parts + 1] = descendant
				end
			elseif descendant:IsA("Motor6D") then
				if descendant.Part1 == body then joints[i] = descendant end
			elseif descendant:IsA("Sound") then
				descendant:Destroy()
			end
		end
		rigParts[i] = parts
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
	table.clear(rigParts)
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

local function sample(label, startTransparency, update)
	buildSlugs(SLUG_COUNT, startTransparency)
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

	-- Engine time for frame i = the duration of the frame that CONTAINED update i, minus update i's own cost.
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
			"[CLUS] %-28s | ENGINE change n=%-3d mean=%8.2f med=%8.2f max=%8.2f | quiet n=%-4d mean=%6.2f med=%6.2f max=%7.2f | delta=%+9.2fms%s",
			label,
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

	buildSlots(SLUG_COUNT)
	print("[BENCH] ===== reproduce @ " .. SLUG_COUNT .. " rigs (" .. SLUG_COUNT * 5 .. " parts) =====")

	sample("CROSS 0<->0.5 (FIRST)", 0, updateCross)
	sample("ORIGINAL cycle 0/.2/.4/.6", 0, updateOriginalCycle)
	sample("control: no change", 0, updateQuiet)
	sample("COLOR: Part.Color", 0, updateColor)
	sample("WITHIN 0.5<->0.6", 0.5, updateWithin)
	sample("CROSS 0<->0.5 (LAST)", 0, updateCross)

	print("[BENCH] ===== done =====")
end)
