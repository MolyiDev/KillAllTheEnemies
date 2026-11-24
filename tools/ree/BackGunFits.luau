-- Every gun as backGunModel builds it, three copies each, for backgunfits.sh to photograph and measure: turned so that
-- a camera at +Z looking down -Z sees it side on (Side), from its top (Top) and down its barrel from the muzzle
-- (Barrel). Copy k of gun i has its Handle at (i * SPACING, BASE + k * SPACING, 0).
-- Context: Files (each gun's ModelName -> the absolute path of its model file).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

local SPACING = 20
local BASE = 100
-- Each view's turn: the Handle's axes (X barrel, Y top, Z side) into the world, with the camera at +Z.
local VIEWS = {
	CFrame.identity,
	CFrame.fromMatrix(Vector3.zero, Vector3.xAxis, Vector3.zAxis),
	CFrame.fromMatrix(Vector3.zero, Vector3.zAxis, Vector3.yAxis),
}

return function(Context)
	local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
	local GunsCore = require(ReplicatedStorage.GlobalShared.Core.GunsCore)
	local backGunModel = require(StarterPlayer.StarterPlayerScripts.Client.Utils.backGunModel)

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
		local source = if mounted:IsA("Model") then mounted else mounted:FindFirstChildWhichIsA("Model", true)
		source.Name = gun.ModelName
		source.Parent = folder
		local meshes = {}
		for _, part in source:GetDescendants() do
			if not part:IsA("MeshPart") then continue end
			table.insert(meshes, part)
			part.Name = `m{#meshes}`
			part.Parent = source
		end

		-- The Handle's axes in FindAxes's frame as they are built now: the measure corrects them from there.
		local frame = GunsCore.FindAxes(source, gun)
		local built = backGunModel.Build(gun)
		assert(built, `no model for {gun.Name}`)
		local handle = built.PrimaryPart :: BasePart
		local barrel = frame:VectorToObjectSpace(handle.CFrame.XVector)
		local top = frame:VectorToObjectSpace(handle.CFrame.YVector)
		print(`AXES {index}|{gun.Name}|{barrel.X},{barrel.Y},{barrel.Z}|{top.X},{top.Y},{top.Z}`)

		for view, turn in VIEWS do
			local copy = built:Clone()
			copy.Name = `Fit{index}_{view}`
			for _, part in copy:GetDescendants() do
				if part:IsA("BasePart") then part.Anchored = true end
				-- Light and effects are not the gun's shape.
				if part:IsA("ParticleEmitter") or part:IsA("Beam") or part:IsA("Trail") or part:IsA("Light") then
					part:Destroy()
				end
			end
			copy:PivotTo(CFrame.new((index - 1) * SPACING, BASE + (view - 1) * SPACING, 0) * turn)
			copy.Parent = Workspace
			for _, part in meshes do
				print(`MESHPART {copy.Name}.{part.Name} {part.MeshId}`)
			end
		end
		built:Destroy()
	end
end
