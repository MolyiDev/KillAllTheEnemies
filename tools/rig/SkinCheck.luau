--[[
Shows enemy rigs as the game draws them, offline: copies of one rig in a row, each wearing a texture, all playing a clip.

	ree record --harness tools/rig/SkinCheck.luau --animations <dir> --seconds <s> --out <out> --context \
		'{"Rig":"<rig.rbxm>","Clip":<id>,"Textures":[["Walker","<abs path>.png"], ...]}'
	ror video <out>/scene.rbxm --playback <out>/playback.json --duration <s>

The rig is a group-owned upload, which neither tool can download without a key: take the rig model and its mesh out of
Studio's cache (rbx-storage, each file a 37-byte RBXH header before the asset) and point the MeshPart's MeshContent at
the mesh file on disk. Textures are the local PNGs that were uploaded. Every body faces the camera on -Z.
]]
local SPACING = 5

return function(Context)
	local source = Context.Mount("ReplicatedStorage/SkinCheckRig", Context.Rig)
	local template = source:FindFirstChildWhichIsA("Model", true) or source
	local body = template:FindFirstChildWhichIsA("MeshPart", true)
	assert(body, "no MeshPart in " .. Context.Rig)

	local count = #Context.Textures
	for i, entry in Context.Textures do
		local model = Instance.new("Model")
		model.Name = entry[1]
		local part = body:Clone()
		part.TextureID = entry[2]
		part.Anchored = true
		-- The rig faces its own +Z: turned half round, it faces the camera.
		part.CFrame = CFrame.new((i - (count + 1) / 2) * SPACING, part.Size.Y / 2, 0) * CFrame.Angles(0, math.pi, 0)
		part.Parent = model
		local controller = Instance.new("AnimationController")
		controller.Parent = model
		local animator = Instance.new("Animator")
		animator.Parent = controller
		model.PrimaryPart = part
		model.Parent = workspace

		if Context.Clip then
			local animation = Instance.new("Animation")
			animation.AnimationId = "rbxassetid://" .. Context.Clip
			animator:LoadAnimation(animation):Play(0, 1, Context.Speed or 1)
		end
	end
end
