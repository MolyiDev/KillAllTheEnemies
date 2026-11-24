-- A gun from its right side with a measuring grid over it, for picking and checking its data's `Hands` (where each
-- hand closes, as shares of the gun's length from its back and of its height from its bottom): the Tool the server
-- builds (buildGunTool), a line every tenth of the box (white at 0 and 1, yellow at the half, grey between), a red
-- ball on the right hand's point, a blue one on the left's and a green line along its `Barrel` height.
--   tools/ree/gunsheet.sh "<gun Name>" <model file> <out dir> <folder of the model's meshes, each named by its id>
-- Context: Gun, Model (absolute path). Prints `MESHPART <part name> <mesh id>` for gunsheet.sh to point at local files.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CORNERS = {
	Vector3.new(-1, -1, -1),
	Vector3.new(-1, -1, 1),
	Vector3.new(-1, 1, -1),
	Vector3.new(-1, 1, 1),
	Vector3.new(1, -1, -1),
	Vector3.new(1, -1, 1),
	Vector3.new(1, 1, -1),
	Vector3.new(1, 1, 1),
}

local function mark(
	name: string,
	size: Vector3,
	position: Vector3,
	color: Color3,
	shape: Enum.PartType?,
	parent: Instance
)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Shape = shape or Enum.PartType.Block
	part.Parent = parent
end

return function(Context)
	local GunsCore = require(ReplicatedStorage.GlobalShared.Core.GunsCore)
	local gun = GunsCore.FromToolName(Context.Gun)
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

	local buildGunTool = require(ReplicatedStorage.ServerUtils.buildGunTool)
	local tool = buildGunTool(gun)
	local handle = tool.Handle

	-- Every part flat under one folder, the Handle at the origin looking down -Z, each named for its index.
	local sheet = Instance.new("Folder")
	sheet.Name = "Sheet"
	sheet.Parent = Workspace
	local toOrigin = handle.CFrame:Inverse()
	local low, high = Vector3.one * math.huge, Vector3.one * -math.huge
	local index = 0
	for _, part in tool:GetDescendants() do
		if not part:IsA("BasePart") or part == handle then continue end
		index += 1
		part.Anchored = true
		part.CFrame = toOrigin * part.CFrame
		part.Name = `p{index}`
		part.Parent = sheet
		if part:IsA("MeshPart") then print(`MESHPART {part.Name} {part.MeshId}`) end
		for _, corner in CORNERS do
			local point = part.CFrame * (part.Size / 2 * corner)
			low = low:Min(point)
			high = high:Max(point)
		end
	end

	-- Back is +Z (the Handle looks out of the barrel), so `along` runs from high.Z to low.Z.
	local length = high.Z - low.Z
	local height = high.Y - low.Y
	local face = high.X + 0.02
	local line = length * 0.004
	for tenth = 0, 10 do
		local color = if tenth == 0 or tenth == 10
			then Color3.new(1, 1, 1)
			elseif tenth == 5 then Color3.new(1, 0.9, 0)
			else Color3.new(0.45, 0.45, 0.45)
		local z = high.Z - length * tenth / 10
		local y = low.Y + height * tenth / 10
		mark(
			`Along{tenth}`,
			Vector3.new(line, height, line),
			Vector3.new(face, low.Y + height / 2, z),
			color,
			nil,
			sheet
		)
		mark(`Up{tenth}`, Vector3.new(line, line, length), Vector3.new(face, y, low.Z + length / 2), color, nil, sheet)
	end

	mark(
		"Barrel",
		Vector3.new(line, line * 2, length),
		Vector3.new(face + 0.01, low.Y + height * gun.Barrel, low.Z + length / 2),
		Color3.new(0, 1, 0.2),
		nil,
		sheet
	)

	local hands = gun.Hands
	if hands then
		local ball = Vector3.one * length * 0.035
		local function at(hand: Vector2): Vector3
			return Vector3.new(face + 0.02, low.Y + height * hand.Y, high.Z - length * hand.X)
		end
		mark("Right", ball, at(hands.Right), Color3.new(1, 0, 0), Enum.PartType.Ball, sheet)
		mark("Left", ball, at(hands.Left), Color3.new(0, 0.3, 1), Enum.PartType.Ball, sheet)
	end

	local camera = Workspace.CurrentCamera
	local centre = Vector3.new(0, low.Y + height / 2, low.Z + length / 2)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 20
	camera.CFrame = CFrame.lookAt(centre + Vector3.xAxis * math.max(length, height * 2) * 2.1, centre)
end
