-- The first-person gun run offline, for ror to film: the real ViewmodelController on a stand-in body holding a real
-- gun built by the server's buildGunTool, through a script of the things it answers (the raise, looking round, shots,
-- a walk, a jump, a free cursor's aim swinging off the crosshair, an upgrade's flourish).
--   tools/ree/viewmodel.sh "Starter Pistol" Assets/models/Guns/preview/pistol
-- Context: Gun (a gun's Name), Model (the absolute path of its model file), Only (one act's name, for a closer look).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

local EYE = Vector3.new(0, 5.5, 0)
local SKIN = Color3.fromRGB(245, 205, 150)
local SHIRT = Color3.fromRGB(245, 205, 150)

local function block(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.Plastic
	part.TopSurface = Enum.SurfaceType.Studs
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- A zombie-sized stand-in to aim at.
local function target(position: Vector3, parent: Instance)
	local green = Color3.fromRGB(110, 150, 90)
	block(
		"Torso",
		Vector3.new(2, 2, 1),
		CFrame.new(position + Vector3.new(0, 3, 0)),
		Color3.fromRGB(90, 80, 70),
		parent
	)
	block("Head", Vector3.new(1.2, 1.2, 1.2), CFrame.new(position + Vector3.new(0, 4.6, 0)), green, parent)
	block("Legs", Vector3.new(2, 2, 1), CFrame.new(position + Vector3.new(0, 1, 0)), Color3.fromRGB(60, 60, 90), parent)
	block("ArmL", Vector3.new(1, 2, 1), CFrame.new(position + Vector3.new(-1.5, 3, 0)), green, parent)
	block("ArmR", Vector3.new(1, 2, 1), CFrame.new(position + Vector3.new(1.5, 3, 0)), green, parent)
end

return function(Context)
	local scripts = StarterPlayer.StarterPlayerScripts
	Context.StandIn(ReplicatedStorage.Packages.Ignis, "return { Register = function(module) return module end }")
	-- The camera's controller, stood in: the script below is the camera, and writes the view it would publish.
	local playerScripts = Players.LocalPlayer:FindFirstChild("PlayerScripts") or Instance.new("Folder")
	playerScripts.Name = "PlayerScripts"
	playerScripts.Parent = Players.LocalPlayer
	local running = scripts.GlobalClient:Clone()
	running.Parent = playerScripts
	Context.StandIn(running.Controllers.CameraController, "return { AimCFrame = CFrame.identity }")
	local CameraController = require(running.Controllers.CameraController)

	-- The arena: a stud floor, a wall, a few bodies.
	local scene = Instance.new("Folder")
	scene.Name = "Scene"
	scene.Parent = Workspace
	block("Floor", Vector3.new(200, 1, 200), CFrame.new(0, -0.5, 0), Color3.fromRGB(110, 110, 135), scene)
	block("Wall", Vector3.new(200, 14, 2), CFrame.new(0, 7, -70), Color3.fromRGB(200, 110, 80), scene)
	block("Crate", Vector3.new(8, 6, 8), CFrame.new(-14, 3, -30), Color3.fromRGB(60, 200, 90), scene)
	target(Vector3.new(-6, 0, -22), scene)
	target(Vector3.new(3, 0, -26), scene)
	target(Vector3.new(11, 0, -18), scene)

	-- The gun's model where GunsCore.GetModel looks for it.
	local GunsCore = require(ReplicatedStorage.GlobalShared.Core.GunsCore)
	local gun = GunsCore.FromToolName(Context.Gun or "Starter Pistol")
	assert(gun, "no such gun")
	local models = Instance.new("Folder")
	models.Name = "Models"
	models.Parent = ReplicatedStorage
	local guns = Instance.new("Folder")
	guns.Name = "Guns"
	guns.Parent = models
	local rarity = Instance.new("Folder")
	rarity.Name = gun.Rarity
	rarity.Parent = guns
	local mounted = Context.Mount("ReplicatedStorage/GunSource", Context.Model)
	local model = if mounted:IsA("Model") then mounted else mounted:FindFirstChildWhichIsA("Model", true)
	model.Name = gun.ModelName
	model.Parent = rarity
	-- The guns' meshes are private: each MeshPart goes flat under the model with a name of its own, and its id is
	-- printed, so viewmodel.sh can point it at a local copy.
	local meshes = 0
	for _, part in model:GetDescendants() do
		if not part:IsA("MeshPart") then continue end
		meshes += 1
		part.Name = `m{meshes}`
		part.Parent = model
		print(`MESHPART {part.Name} {part.MeshId}`)
	end

	-- The body: what the controller reads off a character (the arms it copies, the Tool, the root's speed).
	local character = Instance.new("Model")
	character.Name = "Character"
	local head = block("Head", Vector3.new(2, 1, 1), CFrame.new(EYE), SKIN, character)
	local root =
		block("HumanoidRootPart", Vector3.new(2, 2, 1), CFrame.new(EYE - Vector3.new(0, 1.5, 0)), SKIN, character)
	block("Right Arm", Vector3.new(1, 2, 1), CFrame.new(EYE + Vector3.new(1.5, -1.5, 0)), SHIRT, character)
	block("Left Arm", Vector3.new(1, 2, 1), CFrame.new(EYE + Vector3.new(-1.5, -1.5, 0)), SHIRT, character)
	head.Transparency = 1
	root.Transparency = 1
	character.Parent = Workspace

	-- The emulator has no floor under a Humanoid, so the controller is handed a body whose Humanoid is the script's.
	local humanoid = { FloorMaterial = Enum.Material.Plastic, Health = 100 }
	local body = { Head = head, HumanoidRootPart = root, Humanoid = humanoid }
	function body:FindFirstChildOfClass(className: string)
		return character:FindFirstChildOfClass(className)
	end
	function body:FindFirstChild(name: string)
		return character:FindFirstChild(name)
	end

	local buildGunTool = require(ReplicatedStorage.ServerUtils.buildGunTool)
	local tool = buildGunTool(gun)
	for _, part in tool:GetDescendants() do
		if part:IsA("BasePart") then part.Anchored = true end
	end

	-- The gun's box in its Handle's space, at the Tool's own size: what a hold's hand points are picked against.
	local low, high = Vector3.one * math.huge, Vector3.one * -math.huge
	for _, part in tool:GetDescendants() do
		if not part:IsA("BasePart") or part == tool.Handle then continue end
		local centre = tool.Handle.CFrame:PointToObjectSpace(part.Position)
		local reach = part.Size.Magnitude / 2
		low = low:Min(centre - Vector3.one * reach)
		high = high:Max(centre + Vector3.one * reach)
	end
	print(`{gun.Name} ({gun.Hold}) box, Handle space: {low} to {high}; muzzle {tool.Handle.Muzzle.Position}`)

	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 70
	camera.CFrame = CFrame.new(EYE)

	local Viewmodel = require(running.Controllers.ViewmodelController)
	Viewmodel.OnSelfCharacterAdded(body)
	Viewmodel.OnStart()

	-- The script: each act is { from, to, step(share 0..1, seconds in) }.
	local yaw, pitch = 0, 0
	local aim: Vector3? = nil
	local shots = { 2.2, 2.6, 3.0, 3.4 }
	local fired = 0
	local acts = {
		Raise = { 0, 0.9, function() end },
		Look = {
			0.9,
			2.1,
			function(share: number)
				yaw = math.sin(share * math.pi * 2) * math.rad(35)
				pitch = math.sin(share * math.pi * 4) * math.rad(10)
			end,
		},
		Shoot = { 2.1, 4.0, function() end },
		Walk = {
			4.0,
			5.4,
			function(share: number)
				local speed = if share < 0.8 then 16 else 0
				root.AssemblyLinearVelocity =
					Vector3.new(if share > 0.4 then speed else 0, 0, if share <= 0.4 then -speed else 0)
			end,
		},
		Jump = {
			5.4,
			6.4,
			function(share: number)
				local isUp = share < 0.6
				humanoid.FloorMaterial = if isUp then Enum.Material.Air else Enum.Material.Plastic
				root.AssemblyLinearVelocity = Vector3.new(0, if isUp then 50 - share / 0.6 * 100 else 0, 0)
			end,
		},
		Aim = {
			6.4,
			8.2,
			function(share: number)
				local swing = math.sin(share * math.pi * 2)
				aim = Vector3.new(swing * 26, 4 + math.sin(share * math.pi * 3) * 5, -24)
			end,
		},
		Flourish = { 8.4, 9.6, function() end },
	}

	local only = Context.Only
	local clock = 0
	local hasFlourished = false
	tool.Parent = character
	RunService:BindToRenderStep("Bench", Enum.RenderPriority.Camera.Value, function(dt: number)
		clock += dt
		yaw, pitch, aim = 0, 0, nil
		root.AssemblyLinearVelocity = Vector3.zero
		humanoid.FloorMaterial = Enum.Material.Plastic
		for name, act in acts do
			if only and only ~= name then continue end
			if clock >= act[1] and clock < act[2] then act[3]((clock - act[1]) / (act[2] - act[1]), clock - act[1]) end
		end

		camera.CFrame = CFrame.new(EYE) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
		CameraController.AimCFrame = camera.CFrame
		Viewmodel.Target = aim or camera.CFrame * Vector3.new(0, 0, -60)
		if (not only or only == "Shoot") and shots[fired + 1] and clock >= shots[fired + 1] then
			fired += 1
			Viewmodel.Kick(Context.Kick or 1)
		end

		if (not only or only == "Flourish") and not hasFlourished and clock >= acts.Flourish[1] then
			hasFlourished = true
			tool.Parent = nil
			Viewmodel.Flourish()
			tool.Parent = character
		end
	end)
end
