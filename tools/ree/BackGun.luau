-- The gun worn on the back run offline, for ror to film: the real BackGunController on a blocky stand-in body, told a
-- gun is worn and not as Loadout.Worn would tell it, and the gun drawn into the hand and put back.
--   tools/ree/backgun.sh "SNOWYRIFLE" "Assets/models/Guns/Epic/SNOWYRIFLE.rbxm" Assets/models/Guns/preview/backgun
-- Context: Gun (a gun's Name), Model (the absolute path of its model file).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

local SKIN = Color3.fromRGB(245, 205, 150)
local SHIRT = Color3.fromRGB(70, 120, 210)
local PANTS = Color3.fromRGB(50, 50, 70)

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

return function(Context)
	local client = StarterPlayer.StarterPlayerScripts.GlobalClient
	Context.StandIn(ReplicatedStorage.Packages.Ignis, "return { Register = function(module) return module end }")
	-- The network, stood in: the script below is the server, and calls what the controller hands Worn.On.
	Context.StandIn(
		client.NetworkMeta,
		"local t = {} t.Server = { Loadout = { Worn = { On = function(f) t.Worn = f end } } } return t"
	)
	local sounds = Instance.new("Folder")
	sounds.Name = "Sounds"
	sounds.Parent = ReplicatedStorage

	local scene = Instance.new("Folder")
	scene.Name = "Scene"
	scene.Parent = Workspace
	block("Floor", Vector3.new(80, 1, 80), CFrame.new(0, -0.5, 0), Color3.fromRGB(110, 110, 135), scene)
	block("Wall", Vector3.new(80, 14, 2), CFrame.new(0, 7, -20), Color3.fromRGB(200, 110, 80), scene)

	-- The gun's model where GunsCore.GetModel looks for it.
	local GunsCore = require(ReplicatedStorage.GlobalShared.Core.GunsCore)
	local gun = GunsCore.FromToolName(Context.Gun or "SNOWYRIFLE")
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
	-- printed, so backgun.sh can point each copy's at a local file wherever the recording holds it (COPIES).
	local meshes = 0
	for _, part in model:GetDescendants() do
		if not part:IsA("MeshPart") then continue end
		meshes += 1
		part.Name = `m{meshes}`
		part.Parent = model
		print(`MESHPART {part.Name} {part.MeshId}`)
	end

	-- The body, facing -Z, its back to the camera's side of the floor.
	local character = Instance.new("Model")
	character.Name = "Character"
	block("Head", Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, 4.6, 0), SKIN, character)
	block("UpperTorso", Vector3.new(2, 2, 1), CFrame.new(0, 3, 0), SHIRT, character)
	block("HumanoidRootPart", Vector3.new(2, 2, 1), CFrame.new(0, 3, 0), SHIRT, character).Transparency = 1
	block("LeftUpperArm", Vector3.new(1, 2, 1), CFrame.new(-1.5, 3, 0), SKIN, character)
	block("RightUpperArm", Vector3.new(1, 2, 1), CFrame.new(1.5, 3, 0), SKIN, character)
	block("LeftUpperLeg", Vector3.new(1, 2, 1), CFrame.new(-0.5, 1, 0), PANTS, character)
	block("RightUpperLeg", Vector3.new(1, 2, 1), CFrame.new(0.5, 1, 0), PANTS, character)
	character.Parent = Workspace
	Players.LocalPlayer.Character = character

	local BackGun = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.BackGunController)
	local network = require(client.NetworkMeta)
	BackGun.OnStart()
	BackGun.OnCharacterAdded(character)

	-- Behind the body and off its right shoulder, turning slowly round it.
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 50

	local tool = Instance.new("Tool")
	tool.Name = gun.Name
	-- { at, what }: on, off, on again, drawn into the hand, put back. A copy is made at 0.4, 2.8 and 5.0 and no two are
	-- ever drawn at once.
	local beats = {
		{
			0.4,
			function()
				network.Worn(Players.LocalPlayer, gun.Id)
			end,
		},
		{
			1.9,
			function()
				network.Worn(Players.LocalPlayer, 0)
			end,
		},
		{
			2.8,
			function()
				network.Worn(Players.LocalPlayer, gun.Id)
			end,
		},
		{
			4.3,
			function()
				tool.Parent = character
			end,
		},
		{
			5.0,
			function()
				tool.Parent = nil
			end,
		},
	}
	local clock = 0
	local next = 1
	RunService:BindToRenderStep("Bench", Enum.RenderPriority.Camera.Value, function(dt: number)
		clock += dt
		while beats[next] and clock >= beats[next][1] do
			beats[next][2]()
			next += 1
		end

		local yaw = math.rad(25 + 10 * math.sin(clock * 0.6))
		local eye = Vector3.new(math.sin(yaw) * 7.5, 4.6, math.cos(yaw) * 7.5)
		camera.CFrame = CFrame.lookAt(eye, Vector3.new(0, 3.3, 0))
	end)
end
