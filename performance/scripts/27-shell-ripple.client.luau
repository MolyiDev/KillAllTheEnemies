--!optimize 2
-- THE CORE SHELL'S IMPACT RIPPLE: PANEL LATTICE vs EDITABLE MESH.
--
-- Roblox has no GPU shaders, so "the whole forcefield reacts outward from the hit" has to be faked with
-- geometry. Two ways to fake it, measured here against each other at four lattice resolutions:
--
--   LATTICE - the shell stops being one solid Part and becomes N x N flat panels a face, each joined to an
--   anchored hub by a Motor6D. The tumble is ONE write to the hub and every panel rides it; only the ripple
--   costs anything, and it costs one Motor6D.Transform a panel. Doc 01/02 establish Transform as the cheap
--   way to move a part, which is why the joints are here rather than CFrame writes.
--
--   EDITABLE - the shell is one MeshPart whose geometry is a subdivided cube held in an EditableMesh, and
--   the ripple is real vertex displacement. MeshPart.MeshContent points at the EditableMesh BY REFERENCE
--   (verified: Content{SourceType=Object}), so edits land without rebuilding the part. BatchSetValues is
--   present on the class but throws "EditableMesh API function not available" in this engine version, so
--   every vertex goes through SetPosition, measured at ~100ns each.
--
-- Both variants run the SAME ripple: a wavefront leaving the hit point at RIPPLE_SPEED, displacing along
-- the face normal, amplitude decaying with distance travelled. Same hit points, same timing, no RNG, so the
-- only thing that differs between a lattice row and an editable row is the mechanism.
--
-- WHY TWO SHELL COUNTS. The game has ONE Core, and one shell of any resolution sits under the 240 FPS cap
-- where every variant reads 4.167ms and nothing can be compared (METHODOLOGY trap 2). So each resolution is
-- run twice: at SHELLS=1 for the number that actually ships (where only the `script` column means anything,
-- since Luau cost is cap-independent) and at SHELLS=8 to push the scene over budget and let engine time
-- separate. 8 shells puts 12x12 at 6912 panels, inside the 4800-9600 window docs 09 and 11 map out.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local AssetService = game:GetService("AssetService")
local Stats = game:GetService("Stats")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local RESOLUTIONS = { 6, 8, 10, 12 }
local SHELL_COUNTS = { 1, 8 }
local SHELL_SIZE = 10 -- AwakeningCore.SHIELD_SIZE
local PANEL_GAP = 0.06 -- fraction of a cell left as a seam between panels
local PANEL_THICKNESS = 0.12

local SETTLE_WINDOW = 1.0
local SETTLE_TOLERANCE = 0.10
local SETTLE_MAX_SECONDS = 20
local SAMPLE_SECONDS = 5.0
local TEARDOWN_SECONDS = 2.0
local BUILD_CHUNK = 200

-- The ripple itself. One hit every HIT_PERIOD so the sampled window always contains live ripples rather
-- than a resting shell; the phase is a hash of the shell index, never RNG.
local RIPPLE_SPEED = 26 -- studs/sec the wavefront leaves the hit point at
local RIPPLE_WAVELENGTH = 3.2
local RIPPLE_AMPLITUDE = 0.55
local RIPPLE_DECAY = 0.16 -- per stud of travel
local HIT_PERIOD = 0.7

local SHELL_PITCH_RATE = 0.23 -- AwakeningCore.SHIELD_*_RATE, so the tumble load is the real one
local SHELL_YAW_RATE = -0.31
local SHELL_ROLL_RATE = 0.17

local AREA_WIDTH = 200
local AREA_HEIGHT = 110
local CAM_DISTANCE = 150
-- The look phase is the half of this run a human judges, and it needs the shell to FILL the frame: at the
-- sweep's 150 studs a 10-stud cube is a speck and the four resolutions are indistinguishable. 16 studs puts
-- it edge to edge at FOV 70.
local LOOK_DISTANCE = 16
local LOOK_SECONDS = 6
-- Off for a re-run whose look phase has already been watched: it costs a minute and, more importantly,
-- it builds and tears down eight scenes before the first timed row, which is exactly the session drift
-- METHODOLOGY trap 5 warns about.
local RUN_LOOK = false

-- ── recording ────────────────────────────────────────────────────────────────
local recDt = table.create(65536)
local recAt = table.create(65536)
local recording = false
local activeUpdate = nil
local updateTotal = 0
local updateFrames = 0

local focusLost = false
UserInputService.WindowFocusReleased:Connect(function()
	focusLost = true
end)

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

-- ── the scene ────────────────────────────────────────────────────────────────
-- Shell slots on a deterministic grid, phases from integer hashes so every variant gets a byte-identical
-- layout (METHODOLOGY, shared conventions).
local shells = {}
local root = nil
local clockStart = 0

local function slotPosition(i, n)
	if n == 1 then return Vector3.zero end
	local columns = math.ceil(math.sqrt(n * (AREA_WIDTH / AREA_HEIGHT)))
	local rows = math.ceil(n / columns)
	local col = (i - 1) % columns
	local row = math.floor((i - 1) / columns)
	local stepX = AREA_WIDTH / columns
	local stepY = AREA_HEIGHT / math.max(rows, 1)
	return Vector3.new(-AREA_WIDTH * 0.5 + (col + 0.5) * stepX, -AREA_HEIGHT * 0.5 + (row + 0.5) * stepY, 0)
end

-- The six faces, as (u, v, normal). Same order for both variants so the two builds agree face for face.
local FACES = table.freeze({
	table.freeze({ Vector3.new(1, 0, 0), Vector3.new(0, 1, 0), Vector3.new(0, 0, 1) }),
	table.freeze({ Vector3.new(1, 0, 0), Vector3.new(0, 1, 0), Vector3.new(0, 0, -1) }),
	table.freeze({ Vector3.new(0, 0, 1), Vector3.new(1, 0, 0), Vector3.new(0, 1, 0) }),
	table.freeze({ Vector3.new(0, 0, 1), Vector3.new(1, 0, 0), Vector3.new(0, -1, 0) }),
	table.freeze({ Vector3.new(0, 1, 0), Vector3.new(0, 0, 1), Vector3.new(1, 0, 0) }),
	table.freeze({ Vector3.new(0, 1, 0), Vector3.new(0, 0, 1), Vector3.new(-1, 0, 0) }),
})

-- Where the hit lands on shell `i` for the `k`th strike. A hash, not RNG, and deliberately walked around
-- the body so no run ever measures the same face twice running.
local function hitPoint(i, k)
	local h = (i * 7919 + k * 4409) % 1000
	local face = FACES[(h % 6) + 1]
	local a = (((h * 31) % 1000) / 1000) * 2 - 1
	local b = (((h * 17) % 1000) / 1000) * 2 - 1
	local half = SHELL_SIZE * 0.5
	return face[1] * (a * half) + face[2] * (b * half) + face[3] * half
end

-- The displacement a point at `local position` gets at time `t`, given the shell's current hit. Shared by
-- both variants verbatim, so the mechanism is the only difference between them.
local function rippleAt(px, py, pz, hit, age)
	local dx, dy, dz = px - hit.X, py - hit.Y, pz - hit.Z
	local d = math.sqrt(dx * dx + dy * dy + dz * dz)
	local front = age * RIPPLE_SPEED
	if d > front then return 0 end
	local behind = front - d
	if behind > RIPPLE_WAVELENGTH * 2 then return 0 end
	return RIPPLE_AMPLITUDE * math.sin(behind * (math.pi * 2 / RIPPLE_WAVELENGTH)) * math.exp(-d * RIPPLE_DECAY)
end

-- ── variant: panel lattice on Motor6D ────────────────────────────────────────
local function buildLattice(n, shellCount)
	local folder = Instance.new("Folder")
	folder.Name = "RippleLattice"
	local built = 0

	for s = 1, shellCount do
		local hub = Instance.new("Part")
		hub.Name = "Hub"
		hub.Size = Vector3.new(0.2, 0.2, 0.2)
		hub.Transparency = 1
		hub.Anchored = true
		hub.CanCollide = false
		hub.CanQuery = false
		hub.CanTouch = false
		hub.CastShadow = false
		hub.CFrame = CFrame.new(slotPosition(s, shellCount))
		hub.Parent = folder

		local cell = SHELL_SIZE / n
		local panelSide = cell * (1 - PANEL_GAP)
		local half = SHELL_SIZE * 0.5
		local motors = table.create(n * n * 6)
		local rest = table.create(n * n * 6)
		local locals = table.create(n * n * 6)
		-- The outward direction a panel is pushed along, normalized ONCE at build. The first pass of this
		-- benchmark computed `at.Unit` inside the per-frame loop, which is a square root per panel per
		-- frame charged to both variants; hoisting it is the difference between measuring the mechanism
		-- and measuring a normalize.
		local dirs = table.create(n * n * 6)
		local count = 0

		for _, face in FACES do
			local u, v, w = face[1], face[2], face[3]
			for i = 0, n - 1 do
				for j = 0, n - 1 do
					local a = ((i + 0.5) / n) * 2 - 1
					local b = ((j + 0.5) / n) * 2 - 1
					local at = u * (a * half) + v * (b * half) + w * half

					local panel = Instance.new("Part")
					panel.Name = "Panel"
					panel.Size = Vector3.new(panelSide, panelSide, PANEL_THICKNESS)
					panel.Material = Enum.Material.ForceField
					panel.Color = Color3.fromRGB(120, 220, 255)
					panel.Anchored = false
					panel.CanCollide = false
					panel.CanQuery = false
					panel.CanTouch = false
					panel.CastShadow = false
					panel.Massless = true
					panel.CFrame = hub.CFrame
					panel.Parent = hub

					-- fromMatrix rather than lookAlong: the +Y and -Y faces have a normal parallel to
					-- lookAlong's default up and come out degenerate. u and v are orthonormal by
					-- construction, so the panel's thin Z axis lands on the face normal either way (the
					-- two faces whose (u, v, w) set is left-handed get a panel facing inward, which is
					-- invisible on a symmetric box).
					local restCf = CFrame.fromMatrix(at, u, v)
					local motor = Instance.new("Motor6D")
					motor.Part0 = hub
					motor.Part1 = panel
					motor.C0 = CFrame.identity
					motor.C1 = CFrame.identity
					motor.Transform = restCf
					motor.Parent = hub

					count += 1
					motors[count] = motor
					rest[count] = restCf
					locals[count] = at
					dirs[count] = at.Unit
					built += 1
					-- Chunked so the builder never trips "Script timeout: exhausted allowed execution
					-- time" (METHODOLOGY trap 11). 8 shells at 12x12 is 6912 parts in one unbroken loop
					-- without this.
					if built % BUILD_CHUNK == 0 then task.wait() end
				end
			end
		end

		shells[s] = {
			Hub = hub,
			Motors = motors,
			Rest = rest,
			Locals = locals,
			Dirs = dirs,
			Count = count,
			Origin = hub.CFrame.Position,
			Phase = ((s * 4409) % 1000) / 1000,
		}
	end

	folder.Parent = workspace
	root = folder
	return built
end

local function updateLattice()
	local t = os.clock() - clockStart
	local pitch = t * SHELL_PITCH_RATE
	local yaw = t * SHELL_YAW_RATE
	local roll = t * SHELL_ROLL_RATE

	for s = 1, #shells do
		local shell = shells[s]
		-- The tumble is ONE write and every panel rides it. This is the whole architectural argument for
		-- the lattice: only the ripple is per-panel work.
		shell.Hub.CFrame = CFrame.new(shell.Origin) * CFrame.fromEulerAnglesYXZ(pitch, yaw, roll)

		local phased = t + shell.Phase * HIT_PERIOD
		local strike = math.floor(phased / HIT_PERIOD)
		local age = phased - strike * HIT_PERIOD
		local hit = hitPoint(s, strike)

		local motors = shell.Motors
		local rest = shell.Rest
		local locals = shell.Locals
		local dirs = shell.Dirs
		for k = 1, shell.Count do
			local at = locals[k]
			local push = rippleAt(at.X, at.Y, at.Z, hit, age)
			if push ~= 0 then
				motors[k].Transform = rest[k] + dirs[k] * push
			else
				motors[k].Transform = rest[k]
			end
		end
	end
end

-- ── variant: EditableMesh vertex displacement ────────────────────────────────
local editableSupported = true
local editableError = nil

local function buildEditable(n, shellCount)
	local folder = Instance.new("Folder")
	folder.Name = "RippleEditable"
	local built = 0

	for s = 1, shellCount do
		local ok, em = pcall(function()
			return AssetService:CreateEditableMesh({ FixedSize = false })
		end)
		-- `not em` is the load-bearing half. Past the EditableMesh memory budget this call does NOT throw:
		-- it warns ("Failed to create empty EditableMesh that was requested due to reaching memory budget
		-- limits") and returns nil, so a pcall alone reports success and the next AddVertex indexes nil and
		-- takes the whole driver thread with it (METHODOLOGY trap 10).
		if not ok or not em then
			editableSupported = false
			editableError = if ok then "CreateEditableMesh returned nil (memory budget)" else tostring(em)
			folder:Destroy()
			return 0
		end

		local half = SHELL_SIZE * 0.5
		local ids = table.create((n + 1) * (n + 1) * 6)
		local base = table.create((n + 1) * (n + 1) * 6)
		local dirs = table.create((n + 1) * (n + 1) * 6)
		local count = 0

		for _, face in FACES do
			local u, v, w = face[1], face[2], face[3]
			local grid = table.create((n + 1) * (n + 1))
			for i = 0, n do
				for j = 0, n do
					local a = (i / n) * 2 - 1
					local b = (j / n) * 2 - 1
					local p = u * (a * half) + v * (b * half) + w * half
					local id = em:AddVertex(p)
					grid[i * (n + 1) + j] = id
					count += 1
					ids[count] = id
					base[count] = p
					dirs[count] = p.Unit
				end
			end
			for i = 0, n - 1 do
				for j = 0, n - 1 do
					local v00 = grid[i * (n + 1) + j]
					local v10 = grid[(i + 1) * (n + 1) + j]
					local v01 = grid[i * (n + 1) + j + 1]
					local v11 = grid[(i + 1) * (n + 1) + j + 1]
					em:AddTriangle(v00, v10, v11)
					em:AddTriangle(v00, v11, v01)
				end
			end
		end

		local okPart, mp = pcall(function()
			return AssetService:CreateMeshPartAsync(Content.fromObject(em))
		end)
		if not okPart then
			editableSupported = false
			editableError = tostring(mp)
			folder:Destroy()
			return 0
		end

		mp.Name = "Shell"
		mp.Anchored = true
		mp.CanCollide = false
		mp.CanQuery = false
		mp.CanTouch = false
		mp.CastShadow = false
		mp.Material = Enum.Material.ForceField
		mp.Color = Color3.fromRGB(120, 220, 255)
		mp.Size = Vector3.new(SHELL_SIZE, SHELL_SIZE, SHELL_SIZE)
		mp.CFrame = CFrame.new(slotPosition(s, shellCount))
		mp.Parent = folder

		shells[s] = {
			Mesh = em,
			Part = mp,
			Ids = ids,
			Base = base,
			Dirs = dirs,
			Count = count,
			Origin = mp.CFrame.Position,
			Phase = ((s * 4409) % 1000) / 1000,
		}
		built += count
		task.wait()
	end

	folder.Parent = workspace
	root = folder
	return built
end

local function updateEditable()
	local t = os.clock() - clockStart
	local pitch = t * SHELL_PITCH_RATE
	local yaw = t * SHELL_YAW_RATE
	local roll = t * SHELL_ROLL_RATE

	for s = 1, #shells do
		local shell = shells[s]
		shell.Part.CFrame = CFrame.new(shell.Origin) * CFrame.fromEulerAnglesYXZ(pitch, yaw, roll)

		local phased = t + shell.Phase * HIT_PERIOD
		local strike = math.floor(phased / HIT_PERIOD)
		local age = phased - strike * HIT_PERIOD
		local hit = hitPoint(s, strike)

		local em = shell.Mesh
		local ids = shell.Ids
		local base = shell.Base
		local dirs = shell.Dirs
		for k = 1, shell.Count do
			local p = base[k]
			local push = rippleAt(p.X, p.Y, p.Z, hit, age)
			if push ~= 0 then
				em:SetPosition(ids[k], p + dirs[k] * push)
			else
				em:SetPosition(ids[k], p)
			end
		end
	end
end

-- ── camera, visibility, teardown ─────────────────────────────────────────────
local function aimCamera(distance)
	local character = player.Character
	if character then
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp then
			hrp.Anchored = true
			hrp.CFrame = CFrame.new(0, 500, 0)
		end
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 70
	-- Off-axis rather than straight on, so a corner of the cube faces the viewer and three faces are in
	-- frame at once. Head on, a ripple crossing a corner is the one thing you cannot see, and crossing the
	-- corner is exactly where the two mechanisms differ.
	camera.CFrame = CFrame.lookAt(Vector3.new(distance * 0.55, distance * 0.42, distance * 0.72), Vector3.zero)
end

local function countVisible()
	local visible = 0
	for s = 1, #shells do
		local at = shells[s].Origin
		local _, onScreen = camera:WorldToViewportPoint(at)
		if onScreen then
			visible += 1
		end
	end
	return visible
end

local function teardown()
	if root then
		root:Destroy()
		root = nil
	end
	table.clear(shells)
	task.wait(TEARDOWN_SECONDS)
end

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
				if agreements >= 2 then return os.clock() - start, true end
			else
				agreements = 0
			end
		end
		prevMed = med
	end
	return os.clock() - start, false
end

-- ── one row ──────────────────────────────────────────────────────────────────
local function sample(variant, n, shellCount, tag)
	aimCamera(CAM_DISTANCE)

	local memBefore = Stats:GetTotalMemoryUsageMb()
	local buildStart = os.clock()
	local moved = if variant == "lattice" then buildLattice(n, shellCount) else buildEditable(n, shellCount)
	local buildWall = (os.clock() - buildStart) * 1000

	if moved == 0 then
		print(string.format("[RIPPLE] %s n=%d shells=%d SKIPPED: %s", variant, n, shellCount, tostring(editableError)))
		teardown()
		return
	end

	clockStart = os.clock()
	activeUpdate = if variant == "lattice" then updateLattice else updateEditable
	focusLost = false

	local settleSeconds, converged = settleUntilStable()

	aimCamera(CAM_DISTANCE)
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
	local _, med, p95, worst = stats(frames)
	local upd = updateTotal / math.max(updateFrames, 1) * 1e6
	local memMb = Stats:GetTotalMemoryUsageMb() - memBefore
	local vis = countVisible()

	local capped = 0
	for i = 1, #frames do
		if frames[i] < 0.00435 then
			capped += 1
		end
	end

	activeUpdate = nil

	print(
		string.format(
			"[RIPPLE] %-8s n=%2dx%-2d shells=%-2d moved=%-5d | build=%7.0fms settle=%4.1fs%s | fps=%6.1f med=%7.2f p95=%7.2f worst=%8.2f | script=%8.1fus per=%6.0fns atCap=%5.1f%% mem=%5.0fMB vis=%d/%d cam=%s %s%s",
			variant,
			n,
			n,
			shellCount,
			moved,
			buildWall,
			settleSeconds,
			if converged then " ok " else " NOT",
			#frames / wall,
			med,
			p95,
			worst,
			upd,
			upd * 1000 / math.max(moved, 1),
			capped / math.max(#frames, 1) * 100,
			memMb,
			vis,
			shellCount,
			tostring(camera.CameraType),
			tag,
			if focusLost then "  *** FOCUS LOST ***" else ""
		)
	)

	teardown()
end

-- ── the look phase ───────────────────────────────────────────────────────────
-- The half a human judges. One shell, filling the frame, held for LOOK_SECONDS with the variant and
-- resolution captioned on screen, so the eight combinations can be told apart while they play. No numbers
-- come out of this; it runs BEFORE the sweep so the scene a person watches is never one the timings depend
-- on (METHODOLOGY trap 5 - anything watched is anything touched).
local function look(variant, n)
	local gui = Instance.new("ScreenGui")
	gui.Name = "RippleLook"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 60)
	label.Position = UDim2.fromOffset(0, 20)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Code
	label.TextSize = 34
	label.TextColor3 = Color3.fromRGB(235, 245, 255)
	label.TextStrokeTransparency = 0.4
	label.Text = string.format("%s   %dx%d", string.upper(variant), n, n)
	label.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")

	aimCamera(LOOK_DISTANCE)
	local moved = if variant == "lattice" then buildLattice(n, 1) else buildEditable(n, 1)
	if moved == 0 then
		gui:Destroy()
		teardown()
		return
	end

	label.Text = string.format("%s   %dx%d   %d moved", string.upper(variant), n, n, moved)
	clockStart = os.clock()
	activeUpdate = if variant == "lattice" then updateLattice else updateEditable
	task.wait(LOOK_SECONDS)
	activeUpdate = nil

	gui:Destroy()
	teardown()
end

-- ── driver ───────────────────────────────────────────────────────────────────
task.spawn(function()
	task.wait(3)
	local character = player.Character or player.CharacterAdded:Wait()
	character:WaitForChild("HumanoidRootPart", 10)
	aimCamera(CAM_DISTANCE)

	print("[BENCH] ===== shell impact ripple: panel lattice (Motor6D) vs EditableMesh vertices =====")
	print(string.format("[BENCH] viewport=%s cap=240fps shell=%d studs", tostring(camera.ViewportSize), SHELL_SIZE))
	print("[BENCH] `per` is Luau nanoseconds per moved element (panel or vertex) and is cap-independent.")

	-- Capability probe up front, so a missing API is a printed line rather than a silently dead pass
	-- (METHODOLOGY trap 10).
	local okProbe, probeErr = pcall(function()
		local em = AssetService:CreateEditableMesh({ FixedSize = false })
		local a = em:AddVertex(Vector3.zero)
		local b = em:AddVertex(Vector3.xAxis)
		local c = em:AddVertex(Vector3.yAxis)
		em:AddTriangle(a, b, c)
		em:SetPosition(a, Vector3.zero)
	end)
	print(
		string.format(
			"[BENCH] EditableMesh on client: %s%s",
			tostring(okProbe),
			if okProbe then "" else " - " .. tostring(probeErr)
		)
	)
	if not okProbe then
		editableSupported = false
		editableError = tostring(probeErr)
	end

	if RUN_LOOK then
		print(string.format("[BENCH] --- look phase: 8 combinations, %ds each, watch the viewport ---", LOOK_SECONDS))
		for _, n in RESOLUTIONS do
			look("lattice", n)
			if editableSupported then look("editable", n) end
		end
		print("[BENCH] --- look phase over, timing starts (do not touch Studio) ---")
	end

	for _, shellCount in SHELL_COUNTS do
		for _, n in RESOLUTIONS do
			sample("lattice", n, shellCount, "")
			if editableSupported then sample("editable", n, shellCount, "") end
		end
	end

	-- Reversed pass, for ordering drift (METHODOLOGY trap 5). Only the SHELLS=8 rows, which are the ones
	-- that carry engine time.
	print("[BENCH] --- reversed pass, shells=8 ---")
	for i = #RESOLUTIONS, 1, -1 do
		local n = RESOLUTIONS[i]
		if editableSupported then sample("editable", n, 8, "rev") end
		sample("lattice", n, 8, "rev")
	end

	print("[BENCH] ===== done =====")
end)
