--!optimize 2
-- WHERE IS THE REAL CEILING FOR SKINNED MESHES?
--
-- An earlier run measured 7200 skeletons at 164ms median engine time and concluded they "collapse" somewhere
-- between 4800 and 7200. That conclusion was suspect: skeleton spawn cost is ~1.4ms per entity, so 7200 of them
-- is roughly TEN SECONDS of build CPU, and that run allowed a 2 second settle. It was largely measuring the
-- tail of the build.
--
-- So this run fixes both problems:
--
--   CHUNKED BUILD - 200 at a time with a yield between, so the builder never blocks for 10s and never trips
--   "Script timeout: exhausted allowed execution time". Build wall time is reported per count.
--
--   ADAPTIVE SETTLE - instead of a fixed wait, sample the frame time in 1 second windows and only start
--   measuring once two consecutive windows agree within 10%. The time it actually took to settle is REPORTED,
--   which is the number that decides whether the old result was a build artefact.
--
--   ESCALATING SWEEP - keeps climbing until the settled median is genuinely bad (>50ms), then stops and says
--   where it broke. Only bone movement runs, no property writes, so this is the cheapest possible steady state.
--
-- RESULT: every count needed 4.3-6.2s to settle, including n=2400. The 7200 median improved from 164ms to
-- 44.77ms once settled - so the old number was inflated - but 7200 is still broken. The real ceiling is ~4800,
-- with the TAIL going first at 6000 (median 6.68ms but p95 212ms) and the median going at 7200.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Stats = game:GetService("Stats")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local SKELETON = ReplicatedStorage:WaitForChild("Models"):WaitForChild("Skeleton")

local COUNTS = { 2400, 4800, 6000, 7200, 8400, 9600, 12000 }
local CHUNK = 200
local SETTLE_WINDOW = 1.0
local SETTLE_TOLERANCE = 0.10
local SETTLE_MAX_SECONDS = 40
local SAMPLE_SECONDS = 5.0
local TEARDOWN_SECONDS = 4.0
local COLLAPSE_MS = 50 -- settled median above this counts as broken; stop climbing

local AREA_WIDTH = 260
local AREA_HEIGHT = 140
local AREA_DEPTH = 40
local CAM_DISTANCE = 155
local ORBIT_RADIUS = 3
local ORBIT_SPEED = 1.7

local count = 0
local slotX = table.create(16384)
local slotY = table.create(16384)
local slotZ = table.create(16384)
local phase = table.create(16384)
local bones = table.create(16384)

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

local recDt = table.create(65536)
local recAt = table.create(65536)
local recording = false
local activeUpdate = nil
local updateTotal = 0
local updateFrames = 0

RunService.PreRender:Connect(function(dt)
	local update = activeUpdate
	if update then
		local s = os.clock()
		update()
		updateTotal += os.clock() - s
		updateFrames += 1
	end
	if not recording then return end
	local n = #recDt + 1
	recDt[n] = dt
	recAt[n] = os.clock()
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
	if n == 0 then return 0, 0, 0, 0 end
	local sum, worst = 0, 0
	for i = 1, n do
		sum += list[i]
		if list[i] > worst then worst = list[i] end
	end
	local sorted = table.clone(list)
	table.sort(sorted)
	local med = sorted[math.max(math.floor(n * 0.5), 1)] * 1000
	local p95 = sorted[math.clamp(math.ceil(0.95 * n), 1, n)] * 1000
	return sum / n * 1000, med, p95, worst * 1000
end

local root = nil

local function buildChunked(n)
	local folder = Instance.new("Folder")
	folder.Name = "CeilingDiag"
	local i = 1
	while i <= n do
		local last = math.min(i + CHUNK - 1, n)
		for k = i, last do
			local model = SKELETON:Clone()
			local mesh = model:FindFirstChildWhichIsA("MeshPart")
			mesh.Anchored = true
			mesh.CanCollide = false
			mesh.CanQuery = false
			mesh.CanTouch = false
			mesh.CFrame = CFrame.new(0, 0, 0)
			bones[k] = mesh:FindFirstChildWhichIsA("Bone")
			model.Parent = folder
		end
		i = last + 1
		task.wait()
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
	task.wait(TEARDOWN_SECONDS)
end

local function updateBones()
	local t = os.clock() - clockStart
	for i = 1, count do
		bones[i].Transform = slotCFrame(i, t)
	end
end

-- Wait until two consecutive one-second windows agree within SETTLE_TOLERANCE. Returns how long that took and
-- whether it actually converged, because a count that never settles is itself the answer.
local function settleUntilStable()
	local start = os.clock()
	local prevMed = nil
	local agreements = 0

	while os.clock() - start < SETTLE_MAX_SECONDS do
		table.clear(recDt)
		table.clear(recAt)
		recording = true
		local t0 = os.clock()
		task.wait(SETTLE_WINDOW)
		recording = false
		local _, med = stats(window(t0, os.clock()))

		if med > 0 and prevMed and prevMed > 0 then
			local drift = math.abs(med - prevMed) / prevMed
			if drift < SETTLE_TOLERANCE then
				agreements += 1
				if agreements >= 2 then return os.clock() - start, true, med end
			else
				agreements = 0
			end
		end
		prevMed = med
	end

	return os.clock() - start, false, prevMed or 0
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

	print("[BENCH] ===== skinned mesh ceiling: chunked build, adaptive settle =====")
	print("[BENCH] bone movement only, no property writes. settle = 2 consecutive 1s windows within 10%.")

	for _, n in COUNTS do
		buildSlots(n)

		local memBefore = Stats:GetTotalMemoryUsageMb()
		local buildStart = os.clock()
		buildChunked(n)
		local buildWall = (os.clock() - buildStart) * 1000

		clockStart = os.clock()
		activeUpdate = updateBones
		focusLost = false

		local settleSeconds, converged, _ = settleUntilStable()

		updateTotal = 0
		updateFrames = 0
		table.clear(recDt)
		table.clear(recAt)
		recording = true
		local t0 = os.clock()
		task.wait(SAMPLE_SECONDS)
		recording = false
		local wall = os.clock() - t0

		local frames = window(t0, os.clock())
		local mean, med, p95, worst = stats(frames)
		local upd = updateTotal / math.max(updateFrames, 1) * 1e6
		local memMb = Stats:GetTotalMemoryUsageMb() - memBefore

		local capped = 0
		for i = 1, #frames do
			if frames[i] < 0.00435 then
				capped += 1
			end
		end

		activeUpdate = nil

		print(
			string.format(
				"[CEIL] n=%-6d build=%8.0fms settle=%5.1fs%s | fps=%7.1f mean=%8.2f med=%8.2f p95=%8.2f worst=%9.2f | script=%8.1fus atCap=%5.1f%% mem=%6.0fMB%s",
				n,
				buildWall,
				settleSeconds,
				if converged then " ok " else " NOT",
				#frames / wall,
				mean,
				med,
				p95,
				worst,
				upd,
				capped / math.max(#frames, 1) * 100,
				memMb,
				if focusLost then "  *** FOCUS LOST ***" else ""
			)
		)

		teardown()

		if med > COLLAPSE_MS then
			print(
				string.format(
					"[BENCH] collapsed at n=%d (settled median %.1fms > %dms) - stopping sweep",
					n,
					med,
					COLLAPSE_MS
				)
			)
			break
		end
		if not converged then
			print(
				string.format(
					"[BENCH] n=%d never settled within %ds - treat its numbers as a floor, not a value",
					n,
					SETTLE_MAX_SECONDS
				)
			)
		end
	end

	print("[BENCH] ===== done =====")
end)
