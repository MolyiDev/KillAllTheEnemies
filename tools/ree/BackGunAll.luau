-- Every gun worn on the back at once, for ror to check the fit (backGunModel): a blocky R15 body a gun, and the camera
-- calling on each in turn, a second each.
--   tools/ree/backgunall.sh Assets/models/Guns/preview/backgun-all
-- Context: Files (each gun's ModelName -> the absolute path of its model file).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

local SKIN = Color3.fromRGB(245, 205, 150)
local SHIRT = Color3.fromRGB(70, 120, 210)
local PANTS = Color3.fromRGB(50, 50, 70)
-- The default blocky R15 torso the lobby's avatars wear: UpperTorso over a thin LowerTorso.
local UPPER = Vector3.new(2, 1.6, 1)
local SPACING = 20

local function block(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.Plastic
	part.Parent = parent
	return part
end

return function(Context)
	local client = StarterPlayer.StarterPlayerScripts.Client
	local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
	local backGunModel = require(client.Utils.backGunModel)

	local floor =
		block("Floor", Vector3.new(900, 1, 60), CFrame.new(400, -0.5, 0), Color3.fromRGB(110, 110, 135), Workspace)
	floor.Name = "Floor"

	local models = Instance.new("Folder")
	models.Name = "Models"
	models.Parent = ReplicatedStorage
	local guns = Instance.new("Folder")
	guns.Name = "Guns"
	guns.Parent = models
	local folders = {}

	local order = table.clone(DataCore.Guns.All)
	table.sort(order, function(a, b)
		return a.Id < b.Id
	end)
	for index, gun in order do
		local folderName = gun.Rarity
		local folder = folders[folderName]
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = folderName
			folder.Parent = guns
			folders[folderName] = folder
		end
		local mounted = Context.Mount(`ReplicatedStorage/Source{index}`, Context.Files[gun.ModelName])
		local model = if mounted:IsA("Model") then mounted else mounted:FindFirstChildWhichIsA("Model", true)
		model.Name = gun.ModelName
		model.Parent = folder
		-- The guns' meshes are private: each MeshPart goes flat under the model with a name of its own, and is printed
		-- with its id, so backgunall.sh can point it at a local file.
		local meshes = 0
		for _, part in model:GetDescendants() do
			if not part:IsA("MeshPart") then continue end
			meshes += 1
			part.Name = `m{meshes}`
			part.Parent = model
			print(`MESHPART Body{index}.BackGun.{part.Name} {part.MeshId}`)
		end

		local x = (index - 1) * SPACING
		local body = Instance.new("Model")
		body.Name = `Body{index}`
		block("Head", Vector3.new(1.2, 1.2, 1.2), CFrame.new(x, 4.6, 0), SKIN, body)
		local torso = block("UpperTorso", UPPER, CFrame.new(x, 3.2, 0), SHIRT, body)
		block("LowerTorso", Vector3.new(2, 0.4, 1), CFrame.new(x, 2.2, 0), SHIRT, body)
		block("LeftArm", Vector3.new(1, 2, 1), CFrame.new(x - 1.5, 3, 0), SKIN, body)
		block("RightArm", Vector3.new(1, 2, 1), CFrame.new(x + 1.5, 3, 0), SKIN, body)
		block("LeftLeg", Vector3.new(1, 2, 1), CFrame.new(x - 0.5, 1, 0), PANTS, body)
		block("RightLeg", Vector3.new(1, 2, 1), CFrame.new(x + 0.5, 1, 0), PANTS, body)
		body.Parent = Workspace

		local built, fit = backGunModel.Build(gun)
		assert(built and fit, `no model for {gun.Name}`)
		for _, part in built:GetDescendants() do
			if part:IsA("BasePart") then part.Anchored = true end
		end
		built:PivotTo(torso.CFrame * backGunModel.Slot(fit, torso))
		built.Parent = body
		print(`GUN {index} {gun.Name}`)
	end

	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 40
	-- A gun a second: from behind (is it centred?), from straight side on (is it on the back?) and from straight
	-- above (does it lie flat, or tilt off the back?).
	local clock = 0
	RunService:BindToRenderStep("Bench", Enum.RenderPriority.Camera.Value, function(dt: number)
		clock += dt
		local index = math.floor(clock)
		local third = math.floor((clock - index) * 3)
		local target = Vector3.new(index * SPACING, 3.2, 0.5)
		if third == 0 then
			camera.CFrame = CFrame.lookAt(target + Vector3.new(0, 0.4, 8), target)
		elseif third == 1 then
			camera.CFrame = CFrame.lookAt(target + Vector3.new(8, 0, 0), target)
		else
			camera.CFrame = CFrame.lookAt(target + Vector3.new(0, 9, 0.01), target)
		end
	end)
end
