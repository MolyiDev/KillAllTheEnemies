--!optimize 2
-- THE SHELL RIPPLE, AS IT WILL ACTUALLY LOOK. No numbers come out of this file.
--
-- The first pass at judging the two mechanisms was run in daylight against an empty sky with the crystal
-- missing, and a ForceField shell in daylight is very close to invisible - the material is a rim glow, and
-- a rim glow needs something dark behind it. So this is the same eight combinations staged the way the
-- game stages them: night (WaveController parks Lighting.ClockTime at 0 for a wave), the crystal on its
-- corner inside turning the other way, its PointLight, and ground ten studs under it, because the Core
-- floats at AwakeningCore.FLOAT_HEIGHT and a shell with nothing beneath it reads as a prop in a void.
--
-- Every colour, size and rate below is read from the game's own modules rather than picked here, so what
-- is on screen is the shipped Core with the ripple added and nothing else changed.
--
-- The camera orbits slowly, because the thing being judged is how a wavefront crosses a CORNER, and a
-- fixed camera only ever shows that on the corner it happens to face.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetService = game:GetService("AssetService")

local AwakeningCore = require(ReplicatedStorage.Shared.Core.AwakeningCore)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- ── the real Core's numbers ──────────────────────────────────────────────────
local CORE_SIZE = AwakeningCore.CORE_SIZE
local SHELL_SIZE = AwakeningCore.SHIELD_SIZE
local FLOAT_HEIGHT = AwakeningCore.FLOAT_HEIGHT
local DIAMOND = AwakeningCore.DIAMOND
local SPIN_RATE = AwakeningCore.SPIN_RATE
local LIGHT_COLOR = AwakeningCore.LIGHT_COLOR
local SHELL_PITCH_RATE = AwakeningCore.SHIELD_PITCH_RATE
local SHELL_YAW_RATE = AwakeningCore.SHIELD_YAW_RATE
local SHELL_ROLL_RATE = AwakeningCore.SHIELD_ROLL_RATE

-- CoreController's Tune, for the two the shell is actually drawn with.
local REST_LEVEL = 0.72
local SHELL_ALPHA_FULL = 0.4 -- a shield at full strength
local LIGHT_RANGE = 40
local LIGHT_BRIGHTNESS = 1.1
local SHELL_COLOR = Color3.fromRGB(120, 220, 255) -- CoreService's authored shield colour
local CRYSTAL_COLOR = Color3.new(LIGHT_COLOR.R * REST_LEVEL, LIGHT_COLOR.G * REST_LEVEL, LIGHT_COLOR.B * REST_LEVEL)

-- ── the look ─────────────────────────────────────────────────────────────────
local RESOLUTIONS = { 6, 8, 10, 12 }
local CLIP_SECONDS = 9
local PANEL_GAP = 0.06
local PANEL_THICKNESS = 0.12

-- Slower than the benchmark's 0.7: the benchmark wanted a ripple in every sampled frame, this wants one
-- ripple you can watch leave, cross and die before the next arrives.
local HIT_PERIOD = 1.8
local RIPPLE_SPEED = 26
local RIPPLE_WAVELENGTH = 3.2
local RIPPLE_AMPLITUDE = 0.55
local RIPPLE_DECAY = 0.16

local CAM_DISTANCE = 19
local CAM_HEIGHT = 6
local CAM_ORBIT_RATE = 0.22

local FACES = table.freeze({
	table.freeze({ Vector3.new(1, 0, 0), Vector3.new(0, 1, 0), Vector3.new(0, 0, 1) }),
	table.freeze({ Vector3.new(1, 0, 0), Vector3.new(0, 1, 0), Vector3.new(0, 0, -1) }),
	table.freeze({ Vector3.new(0, 0, 1), Vector3.new(1, 0, 0), Vector3.new(0, 1, 0) }),
	table.freeze({ Vector3.new(0, 0, 1), Vector3.new(1, 0, 0), Vector3.new(0, -1, 0) }),
	table.freeze({ Vector3.new(0, 1, 0), Vector3.new(0, 0, 1), Vector3.new(1, 0, 0) }),
	table.freeze({ Vector3.new(0, 1, 0), Vector3.new(0, 0, 1), Vector3.new(-1, 0, 0) }),
})

local function hitPoint(k)
	local h = (k * 7919) % 1000
	local face = FACES[(h % 6) + 1]
	local a = (((h * 31) % 1000) / 1000) * 2 - 1
	local b = (((h * 17) % 1000) / 1000) * 2 - 1
	local half = SHELL_SIZE * 0.5
	return face[1] * (a * half) + face[2] * (b * half) + face[3] * half
end

local function rippleAt(px, py, pz, hit, age)
	local dx, dy, dz = px - hit.X, py - hit.Y, pz - hit.Z
	local d = math.sqrt(dx * dx + dy * dy + dz * dz)
	local front = age * RIPPLE_SPEED
	if d > front then return 0 end
	local behind = front - d
	if behind > RIPPLE_WAVELENGTH * 2 then return 0 end
	return RIPPLE_AMPLITUDE * math.sin(behind * (math.pi * 2 / RIPPLE_WAVELENGTH)) * math.exp(-d * RIPPLE_DECAY)
end

-- ── the stage ────────────────────────────────────────────────────────────────
-- Built once and left standing for the whole reel: ground, crystal, light. Only the shell is torn down and
-- rebuilt between clips, so what changes on screen is the thing under test and nothing else.
local CENTRE = Vector3.new(0, 0, 0)

local crystal = nil

local function buildStage()
	local folder = Instance.new("Folder")
	folder.Name = "RippleLookStage"

	local ground = Instance.new("Part")
	ground.Name = "Ground"
	ground.Size = Vector3.new(220, 2, 220)
	ground.Position = CENTRE - Vector3.new(0, FLOAT_HEIGHT + 1, 0)
	ground.Anchored = true
	ground.CanCollide = false
	ground.Material = Enum.Material.Slate
	ground.Color = Color3.fromRGB(38, 42, 46)
	ground.Parent = folder

	local part = Instance.new("Part")
	part.Name = "Crystal"
	part.Shape = Enum.PartType.Block
	part.Material = Enum.Material.Neon
	part.Color = CRYSTAL_COLOR
	part.Size = Vector3.new(CORE_SIZE, CORE_SIZE, CORE_SIZE)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CFrame = CFrame.new(CENTRE) * DIAMOND
	part.Parent = folder

	local light = Instance.new("PointLight")
	light.Color = LIGHT_COLOR
	light.Range = LIGHT_RANGE
	light.Brightness = LIGHT_BRIGHTNESS
	light.Parent = part

	folder.Parent = workspace
	crystal = part
end

-- ── variant: panel lattice on Motor6D ────────────────────────────────────────
local shell = nil

local function buildLattice(n)
	local folder = Instance.new("Folder")
	folder.Name = "Lattice"

	local hub = Instance.new("Part")
	hub.Name = "Hub"
	hub.Size = Vector3.new(0.2, 0.2, 0.2)
	hub.Transparency = 1
	hub.Anchored = true
	hub.CanCollide = false
	hub.CanQuery = false
	hub.CanTouch = false
	hub.CastShadow = false
	hub.CFrame = CFrame.new(CENTRE)
	hub.Parent = folder

	local cell = SHELL_SIZE / n
	local panelSide = cell * (1 - PANEL_GAP)
	local half = SHELL_SIZE * 0.5
	local motors = table.create(n * n * 6)
	local rest = table.create(n * n * 6)
	local locals = table.create(n * n * 6)
	local dirs = table.create(n * n * 6)
	local count = 0
	local built = 0

	for _, face in FACES do
		local u, v = face[1], face[2]
		for i = 0, n - 1 do
			for j = 0, n - 1 do
				local a = ((i + 0.5) / n) * 2 - 1
				local b = ((j + 0.5) / n) * 2 - 1
				local at = u * (a * half) + v * (b * half) + face[3] * half

				local panel = Instance.new("Part")
				panel.Name = "Panel"
				panel.Size = Vector3.new(panelSide, panelSide, PANEL_THICKNESS)
				panel.Material = Enum.Material.ForceField
				panel.Color = SHELL_COLOR
				panel.Transparency = SHELL_ALPHA_FULL
				panel.Anchored = false
				panel.CanCollide = false
				panel.CanQuery = false
				panel.CanTouch = false
				panel.CastShadow = false
				panel.Massless = true
				panel.CFrame = hub.CFrame
				panel.Parent = hub

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
				if built % 200 == 0 then task.wait() end
			end
		end
	end

	folder.Parent = workspace
	shell = {
		Kind = "lattice",
		Folder = folder,
		Hub = hub,
		Motors = motors,
		Rest = rest,
		Locals = locals,
		Dirs = dirs,
		Count = count,
	}
	return count
end

-- ── variant: EditableMesh vertex displacement ────────────────────────────────
local function buildEditable(n)
	local ok, em = pcall(function()
		return AssetService:CreateEditableMesh({ FixedSize = false })
	end)
	if not ok or not em then return 0, if ok then "memory budget" else tostring(em) end

	local half = SHELL_SIZE * 0.5
	local ids = table.create((n + 1) * (n + 1) * 6)
	local base = table.create((n + 1) * (n + 1) * 6)
	local dirs = table.create((n + 1) * (n + 1) * 6)
	local count = 0

	for _, face in FACES do
		local u, v = face[1], face[2]
		local grid = table.create((n + 1) * (n + 1))
		for i = 0, n do
			for j = 0, n do
				local a = (i / n) * 2 - 1
				local b = (j / n) * 2 - 1
				local p = u * (a * half) + v * (b * half) + face[3] * half
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
	if not okPart or not mp then return 0, "CreateMeshPartAsync failed" end

	local folder = Instance.new("Folder")
	folder.Name = "Editable"
	mp.Name = "Shell"
	mp.Anchored = true
	mp.CanCollide = false
	mp.CanQuery = false
	mp.CanTouch = false
	mp.CastShadow = false
	mp.Material = Enum.Material.ForceField
	mp.Color = SHELL_COLOR
	mp.Transparency = SHELL_ALPHA_FULL
	mp.Size = Vector3.new(SHELL_SIZE, SHELL_SIZE, SHELL_SIZE)
	mp.CFrame = CFrame.new(CENTRE)
	mp.Parent = folder
	folder.Parent = workspace

	shell =
		{ Kind = "editable", Folder = folder, Mesh = em, Part = mp, Ids = ids, Base = base, Dirs = dirs, Count = count }
	return count
end

-- ── the solid shell as it ships today, for reference ─────────────────────────
local function buildSolid()
	local folder = Instance.new("Folder")
	folder.Name = "Solid"
	local part = Instance.new("Part")
	part.Name = "Shell"
	part.Shape = Enum.PartType.Block
	part.Material = Enum.Material.ForceField
	part.Color = SHELL_COLOR
	part.Transparency = SHELL_ALPHA_FULL
	part.Size = Vector3.one * SHELL_SIZE
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.CFrame = CFrame.new(CENTRE)
	part.Parent = folder
	folder.Parent = workspace
	shell = { Kind = "solid", Folder = folder, Part = part, Count = 0 }
	return 1
end

local function clearShell()
	if shell then
		shell.Folder:Destroy()
		shell = nil
	end
end

-- ── the frame ────────────────────────────────────────────────────────────────
local clockStart = 0

local function step()
	local t = os.clock() - clockStart
	local pitch = t * SHELL_PITCH_RATE
	local yaw = t * SHELL_YAW_RATE
	local roll = t * SHELL_ROLL_RATE
	local tumble = CFrame.new(CENTRE) * CFrame.fromEulerAnglesYXZ(pitch, yaw, roll)

	crystal.CFrame = CFrame.new(CENTRE) * CFrame.Angles(0, t * SPIN_RATE, 0) * DIAMOND

	camera.CFrame = CFrame.lookAt(
		CENTRE
			+ Vector3.new(
				math.cos(t * CAM_ORBIT_RATE) * CAM_DISTANCE,
				CAM_HEIGHT,
				math.sin(t * CAM_ORBIT_RATE) * CAM_DISTANCE
			),
		CENTRE
	)

	if not shell then return end

	local strike = math.floor(t / HIT_PERIOD)
	local age = t - strike * HIT_PERIOD
	local hit = hitPoint(strike)

	if shell.Kind == "solid" then
		shell.Part.CFrame = tumble
		return
	end

	if shell.Kind == "lattice" then
		shell.Hub.CFrame = tumble
		local motors, rest, locals, dirs = shell.Motors, shell.Rest, shell.Locals, shell.Dirs
		for k = 1, shell.Count do
			local at = locals[k]
			local push = rippleAt(at.X, at.Y, at.Z, hit, age)
			if push ~= 0 then
				motors[k].Transform = rest[k] + dirs[k] * push
			else
				motors[k].Transform = rest[k]
			end
		end
		return
	end

	shell.Part.CFrame = tumble
	local em, ids, base, dirs = shell.Mesh, shell.Ids, shell.Base, shell.Dirs
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

-- ── driver ───────────────────────────────────────────────────────────────────
local label = nil

local function caption(text)
	label.Text = text
	print("[LOOK] " .. text)
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

	-- Night, which is what a wave is fought in: WaveController parks ClockTime at 0 for the fight and 14
	-- for camp. A ForceField is a rim glow and needs the dark to read at all.
	Lighting.ClockTime = 0
	Lighting.Brightness = 1
	Lighting.Ambient = Color3.fromRGB(12, 14, 20)
	Lighting.OutdoorAmbient = Color3.fromRGB(20, 24, 34)
	Lighting.FogEnd = 260
	Lighting.FogColor = Color3.fromRGB(10, 12, 18)

	local gui = Instance.new("ScreenGui")
	gui.Name = "RippleLookHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 56)
	label.Position = UDim2.fromOffset(0, 18)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Code
	label.TextSize = 32
	label.TextColor3 = Color3.fromRGB(235, 245, 255)
	label.TextStrokeTransparency = 0.35
	label.Text = ""
	label.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")

	buildStage()
	clockStart = os.clock()
	RunService.PreRender:Connect(step)

	print("[LOOK] ===== shell ripple, staged as in game: night, crystal, ground =====")

	caption("SOLID  -  the shell as it ships today, no ripple")
	buildSolid()
	task.wait(CLIP_SECONDS)
	clearShell()

	for _, n in RESOLUTIONS do
		local count = buildLattice(n)
		caption(string.format("LATTICE  %dx%d  -  %d panels", n, n, count))
		task.wait(CLIP_SECONDS)
		clearShell()

		local vcount, why = buildEditable(n)
		if vcount == 0 then
			caption(string.format("EDITABLE %dx%d  -  UNAVAILABLE (%s)", n, n, tostring(why)))
			task.wait(2)
		else
			caption(string.format("EDITABLE %dx%d  -  %d vertices", n, n, vcount))
			task.wait(CLIP_SECONDS)
		end
		clearShell()
	end

	caption("done")
	print("[LOOK] ===== done =====")
end)
