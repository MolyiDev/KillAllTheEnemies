-- The third-person hold run offline, for ror to film: the real BodyPoseController on a stand-in R6 body (the joints
-- an avatar has) holding a real gun built by the server's buildGunTool, through a script: the raise, aiming round,
-- a burst.
--   tools/ree/bodypose.sh "<gun Name>" <model file> <out dir>
-- Context: Gun (a gun's Name), Model (the absolute path of its model file), Debug (print each hand's distance from
-- its grip twice a second). Prints `MESHPART <part name> <mesh id>` for
-- bodypose.sh to point at local files.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

local SKIN = Color3.fromRGB(245, 205, 150)
local SHIRT = Color3.fromRGB(40, 110, 200)
local PANTS = Color3.fromRGB(50, 50, 70)
-- The root's centre: legs 0 to 2, torso 2 to 4, head 4 to 5.
local ROOT = Vector3.new(0, 3, 0)

local function block(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.Plastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = false
	part.Parent = parent
	return part
end

local function joint(name: string, part0: BasePart, part1: BasePart, c0: CFrame, c1: CFrame)
	local motor = Instance.new("Motor6D")
	motor.Name = name
	motor.Part0 = part0
	motor.Part1 = part1
	motor.C0 = c0
	motor.C1 = c1
	motor.Parent = part0
end

local function grip(name: string, arm: BasePart)
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.CFrame = CFrame.new(0, -1, 0) * CFrame.Angles(-math.pi / 2, 0, 0)
	attachment.Parent = arm
end

-- An R6 body with the C0s and C1s every avatar's joints have.
local function buildBody(): Model
	local character = Instance.new("Model")
	character.Name = "Character"
	local root = block("HumanoidRootPart", Vector3.new(2, 2, 1), CFrame.new(ROOT), SHIRT, character)
	root.Anchored = true
	root.Transparency = 1
	local torso = block("Torso", Vector3.new(2, 2, 1), CFrame.new(ROOT), SHIRT, character)
	-- An avatar's head mesh is about 1.25 across, not its 2 x 1 x 1 part.
	local head = block("Head", Vector3.one * 1.25, CFrame.new(ROOT + Vector3.new(0, 1.6, 0)), SKIN, character)
	local face = block("Face", Vector3.new(0.6, 0.15, 0.05), CFrame.new(), Color3.new(0.1, 0.1, 0.1), character)
	local rightArm =
		block("Right Arm", Vector3.new(1, 2, 1), CFrame.new(ROOT + Vector3.new(1.5, 0, 0)), SKIN, character)
	local leftArm = block("Left Arm", Vector3.new(1, 2, 1), CFrame.new(ROOT + Vector3.new(-1.5, 0, 0)), SKIN, character)
	local rightLeg =
		block("Right Leg", Vector3.new(1, 2, 1), CFrame.new(ROOT + Vector3.new(0.5, -2, 0)), PANTS, character)
	local leftLeg =
		block("Left Leg", Vector3.new(1, 2, 1), CFrame.new(ROOT + Vector3.new(-0.5, -2, 0)), PANTS, character)
	local faceWeld = Instance.new("Weld")
	faceWeld.Part0 = head
	faceWeld.Part1 = face
	faceWeld.C0 = CFrame.new(0, 0.1, -0.63)
	faceWeld.Parent = face

	local turned = CFrame.fromMatrix(Vector3.zero, Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 1, 0))
	local right = CFrame.fromMatrix(Vector3.zero, Vector3.new(0, 0, -1), Vector3.yAxis, Vector3.new(1, 0, 0))
	local left = CFrame.fromMatrix(Vector3.zero, Vector3.new(0, 0, 1), Vector3.yAxis, Vector3.new(-1, 0, 0))
	joint("RootJoint", root, torso, turned, turned)
	joint("Neck", torso, head, CFrame.new(0, 1, 0) * turned, CFrame.new(0, -0.5, 0) * turned)
	joint("Right Shoulder", torso, rightArm, CFrame.new(1, 0.5, 0) * right, CFrame.new(-0.5, 0.5, 0) * right)
	joint("Left Shoulder", torso, leftArm, CFrame.new(-1, 0.5, 0) * left, CFrame.new(0.5, 0.5, 0) * left)
	joint("Right Hip", torso, rightLeg, CFrame.new(1, -1, 0) * right, CFrame.new(0.5, 1, 0) * right)
	joint("Left Hip", torso, leftLeg, CFrame.new(-1, -1, 0) * left, CFrame.new(-0.5, 1, 0) * left)
	grip("RightGripAttachment", rightArm)
	grip("LeftGripAttachment", leftArm)
	character.Parent = Workspace
	return character
end

return function(Context)
	local scripts = StarterPlayer.StarterPlayerScripts
	Context.StandIn(ReplicatedStorage.Packages.Ignis, "return { Register = function(module) return module end }")
	Context.StandIn(
		scripts.GlobalClient.Network,
		"return { Server = { Weapons = { Aims = { On = function() end } } } }"
	)
	Context.StandIn(ReplicatedStorage.GlobalShared.Core.CharacterCore, "return {}")
	Context.StandIn(ReplicatedStorage.GlobalShared.ECS.Components, "return {}")
	Context.StandIn(ReplicatedStorage.GlobalShared.ECS.Worlds.World, "return {}")
	local playerScripts = Players.LocalPlayer:FindFirstChild("PlayerScripts") or Instance.new("Folder")
	playerScripts.Name = "PlayerScripts"
	playerScripts.Parent = Players.LocalPlayer
	local running = scripts.GlobalClient:Clone()
	running.Parent = playerScripts

	local scene = Instance.new("Folder")
	scene.Name = "Scene"
	scene.Parent = Workspace
	local floor = block("Floor", Vector3.new(80, 1, 80), CFrame.new(0, -0.5, 0), Color3.fromRGB(110, 110, 135), scene)
	floor.Anchored = true
	floor.TopSurface = Enum.SurfaceType.Studs

	-- The gun's model where GunsCore.GetModel looks for it, its MeshParts flat under it with names of their own.
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
	local meshes = 0
	for _, part in model:GetDescendants() do
		if not part:IsA("MeshPart") then continue end
		meshes += 1
		part.Name = `m{meshes}`
		part.Parent = model
		print(`MESHPART {part.Name} {part.MeshId}`)
	end

	local character = buildBody()
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = character
	Players.LocalPlayer.Character = character

	local buildGunTool = require(ReplicatedStorage.ServerUtils.buildGunTool)
	local tool = buildGunTool(gun)
	assert(tool, "no tool")
	local BodyPose = require(running.Controllers.BodyPoseController)
	BodyPose.OnCharacterAdded(character)
	BodyPose.OnStart()

	-- A red ball on the right hand's grip and a blue one on the left's: a hand on its grip hides its ball.
	local grips = require(running.Utils.gunGrips)(gun, tool.Handle, tool)
	for name, point in { Right = grips.Right, Left = grips.Left } do
		local ball = block(
			`{name}Mark`,
			Vector3.one * 0.3,
			tool.Handle.CFrame * CFrame.new(point),
			Color3.new(1, 0, 0),
			character
		)
		ball.Shape = Enum.PartType.Ball
		ball.Color = if name == "Right" then Color3.new(1, 0, 0) else Color3.new(0, 0.3, 1)
		ball.Material = Enum.Material.Neon
		ball.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = tool.Handle
		weld.Part1 = ball
		weld.Parent = ball
	end

	-- What equipping does: the Tool under the body, its Handle welded into the right hand.
	local function equip()
		tool.Parent = character
		local weld = Instance.new("Weld")
		weld.Name = "RightGrip"
		weld.Part0 = character["Right Arm"]
		weld.Part1 = tool.Handle
		weld.C0 = character["Right Arm"].RightGripAttachment.CFrame
		weld.C1 = tool.Grip
		weld.Parent = character["Right Arm"]
	end

	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 40
	camera.CFrame = CFrame.lookAt(Vector3.new(7, 5, -6), Vector3.new(0, 3.6, -0.5))

	-- The script: rest, aim round (yaw and pitch), a burst.
	local head = character.Head
	local clock = 0
	local shots = 0
	local isEquipped = false
	RunService:BindToRenderStep("Bench", Enum.RenderPriority.Camera.Value, function(dt: number)
		clock += dt
		if not isEquipped and clock > 0.1 then
			isEquipped = true
			equip()
		end

		local yaw, pitch = 0, 0
		if clock > 1.6 and clock < 3.6 then
			local share = (clock - 1.6) / 2
			yaw = math.sin(share * math.pi * 2) * math.rad(35)
			pitch = math.sin(share * math.pi * 4) * math.rad(30)
		end
		local look = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
		BodyPose.Target = head.Position + look.LookVector * 60

		if Context.Debug and isEquipped and math.floor(clock * 2) ~= math.floor((clock - dt) * 2) then
			local function at(name: string): Vector3
				return (character:FindFirstChild(name) :: BasePart).Position
			end
			local rightHand = character["Right Arm"].RightGripAttachment.WorldPosition
			local leftHand = character["Left Arm"].LeftGripAttachment.WorldPosition
			print(
				`DEBUG t={string.format("%.1f", clock)} right hand {rightHand} grip {at("RightMark")} off {(
					rightHand - at("RightMark")
				).Magnitude}`
					.. ` | left hand {leftHand} grip {at("LeftMark")} off {(leftHand - at("LeftMark")).Magnitude}`
					.. ` | slides {character.Torso["Right Shoulder"].Transform.Position.Magnitude} {character.Torso["Left Shoulder"].Transform.Position.Magnitude}`
			)
		end

		if clock > 3.8 and clock < 5.0 then
			local next = 3.8 + shots * gun.FireInterval
			if clock >= next then
				shots += 1
				BodyPose.Kick(character, Context.Kick or 1.2)
			end
		end
	end)
end
