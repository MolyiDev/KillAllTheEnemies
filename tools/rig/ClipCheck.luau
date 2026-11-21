--[[
Plays an R6 clip and its retargeted twin side by side in ree, and measures how far apart they pose: the proof that
tools/lune/retarget_r6.luau keeps a clip's motion on the enemy rig's bones.

	ree record --harness tools/rig/ClipCheck.luau --animations <dir> --seconds <s> --out <out> \
		--context '{"Original":<id>,"Retargeted":<id>,"Speed":<retargeted clip's time scale>}'
	ror video <out>/scene.rbxm --playback <out>/playback.json --duration <s>

<dir> holds both clips as <id>.rbxm. Left: an R6 rig with the old Game place's Motor6D frames playing the original.
Right: the shipped enemy rig's bones (read off ReplicatedStorage.Models.Enemies.Walker), facing the same way, played
by the retargeted clip, with R6-sized boxes laid on its bones every frame. Both face the camera on -Z, and a dark nose
on each head shows its front. Each frame prints the largest angle between an R6 part and its bone's matching box.
]]
local RunService = game:GetService("RunService")

-- The R6 parts, their sizes, and the Motor6D that drives each (C0 and C1 as the old skins hold them).
local R6_PARTS = {
	Torso = Vector3.new(2, 2, 1),
	Head = Vector3.new(2, 1, 1),
	["Left Arm"] = Vector3.new(1, 2, 1),
	["Right Arm"] = Vector3.new(1, 2, 1),
	["Left Leg"] = Vector3.new(1, 2, 1),
	["Right Leg"] = Vector3.new(1, 2, 1),
}
local SPINE = CFrame.fromMatrix(Vector3.zero, Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 1, 0))
local RIGHT = CFrame.fromMatrix(Vector3.zero, Vector3.new(0, 0, -1), Vector3.new(0, 1, 0), Vector3.new(1, 0, 0))
local LEFT = CFrame.fromMatrix(Vector3.zero, Vector3.new(0, 0, 1), Vector3.new(0, 1, 0), Vector3.new(-1, 0, 0))
local MOTORS = {
	{ "RootJoint", "HumanoidRootPart", "Torso", SPINE, SPINE },
	{ "Neck", "Torso", "Head", CFrame.new(0, 1, 0) * SPINE, CFrame.new(0, -0.5, 0) * SPINE },
	{ "Right Shoulder", "Torso", "Right Arm", CFrame.new(1, 0.5, 0) * RIGHT, CFrame.new(-0.5, 0.5, 0) * RIGHT },
	{ "Left Shoulder", "Torso", "Left Arm", CFrame.new(-1, 0.5, 0) * LEFT, CFrame.new(0.5, 0.5, 0) * LEFT },
	{ "Right Hip", "Torso", "Right Leg", CFrame.new(1, -1, 0) * RIGHT, CFrame.new(0.5, 1, 0) * RIGHT },
	{ "Left Hip", "Torso", "Left Leg", CFrame.new(-1, -1, 0) * LEFT, CFrame.new(-0.5, 1, 0) * LEFT },
}

-- The enemy rig's bones as the shipped Walker holds them (feet at Root, studs), and each bone's box: the R6 part it
-- stands for and that part's centre in the bone's frame.
local BONES = {
	{ "Root", nil, Vector3.zero },
	{ "Torso", "Root", Vector3.new(0, 2, 0), "Torso", Vector3.new(0, 1, 0) },
	{ "Head", "Torso", Vector3.new(0, 2, -0.15), "Head", Vector3.new(0, 0.5, 0.15) },
	{ "ArmLeft", "Torso", Vector3.new(1.5, 1.5, 0), "Left Arm", Vector3.new(0, -0.5, 0) },
	{ "ArmRight", "Torso", Vector3.new(-1.5, 1.5, 0), "Right Arm", Vector3.new(0, -0.5, 0) },
	{ "LegLeft", "Torso", Vector3.new(0.5, -0.125, 0), "Left Leg", Vector3.new(0, -0.875, 0) },
	{ "LegRight", "Torso", Vector3.new(-0.5, -0.125, 0), "Right Leg", Vector3.new(0, -0.875, 0) },
}

local function box(name, size, color, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Anchored = true
	part.CanCollide = false
	part.Parent = parent
	return part
end

local function animator(model)
	local controller = Instance.new("AnimationController")
	controller.Parent = model
	local result = Instance.new("Animator")
	result.Parent = controller
	return result
end

local function play(target, id, speed)
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. id
	local track = target:LoadAnimation(animation)
	track:Play(0, 1, speed)
	return track
end

local function buildR6(at)
	local model = Instance.new("Model")
	model.Name = "R6Original"
	local parts = {}
	local root = box("HumanoidRootPart", Vector3.new(2, 2, 1), Color3.new(1, 1, 1), model)
	root.Transparency = 1
	root.CFrame = CFrame.new(at + Vector3.new(0, 3, 0))
	parts.HumanoidRootPart = root
	for name, size in R6_PARTS do
		parts[name] = box(name, size, Color3.fromRGB(90, 150, 230), model)
	end
	local motors = {}
	for _, spec in MOTORS do
		local motor = Instance.new("Motor6D")
		motor.Name = spec[1]
		motor.Part0, motor.Part1, motor.C0, motor.C1 = parts[spec[2]], parts[spec[3]], spec[4], spec[5]
		motor.Parent = parts[spec[2]]
		table.insert(motors, motor)
	end
	model.PrimaryPart = root
	model.Parent = workspace
	return model, parts, motors
end

-- ree simulates no physics, so the parts are posed here from what the Animator wrote, as the engine solves a joint.
-- MOTORS lists every parent before its children.
local function poseR6(motors)
	for _, motor in motors do
		motor.Part1.CFrame = motor.Part0.CFrame * motor.C0 * motor.Transform * motor.C1:Inverse()
	end
end

local function buildBones(at)
	local model = Instance.new("Model")
	model.Name = "BoneRetargeted"
	local body = box("Body", Vector3.new(0.2, 0.2, 0.2), Color3.new(1, 1, 1), model)
	body.Transparency = 1
	-- The rig faces its own +Z: turned half round, it faces the camera on -Z like the R6 beside it.
	body.CFrame = CFrame.new(at) * CFrame.Angles(0, math.pi, 0)
	local bones, boxes = {}, {}
	for _, spec in BONES do
		local bone = Instance.new("Bone")
		bone.Name = spec[1]
		bone.CFrame = CFrame.new(spec[3])
		bone.Parent = if spec[2] then bones[spec[2]] else body
		bones[spec[1]] = bone
		if spec[4] then
			boxes[spec[1]] = { box(spec[4], R6_PARTS[spec[4]], Color3.fromRGB(230, 120, 70), model), spec[5], spec[4] }
		end
	end
	model.PrimaryPart = body
	model.Parent = workspace
	return model, bones, boxes
end

return function(Context)
	local r6, parts, motors = buildR6(Vector3.new(-3, 0, 0))
	local rig, bones, boxes = buildBones(Vector3.new(3, 0, 0))
	local r6Nose = box("Nose", Vector3.new(0.4, 0.3, 0.4), Color3.fromRGB(20, 20, 30), r6)
	local rigNose = box("Nose", Vector3.new(0.4, 0.3, 0.4), Color3.fromRGB(20, 20, 30), rig)
	local halfTurn = CFrame.Angles(0, math.pi, 0)

	play(animator(r6), Context.Original, 1)
	play(animator(rig), Context.Retargeted, Context.Speed or 1)

	local worst = 0
	RunService.Heartbeat:Connect(function()
		poseR6(motors)
		local frameWorst, at = 0, ""
		for name, entry in boxes do
			local part, offset, r6Name = entry[1], entry[2], entry[3]
			part.CFrame = bones[name].TransformedWorldCFrame * CFrame.new(offset)
			-- Each body's turn in its own frame: the rig's frame is R6's turned half round, so R6's turn is carried
			-- into it by conjugation. Equal bodies give the identity between them.
			local mine = rig.PrimaryPart.CFrame:ToObjectSpace(part.CFrame).Rotation
			local theirs = parts.HumanoidRootPart.CFrame:ToObjectSpace(parts[r6Name].CFrame).Rotation
			local _, angle = (mine:Inverse() * halfTurn * theirs * halfTurn:Inverse()):ToAxisAngle()
			local degrees = math.deg(math.abs(angle))
			if degrees > frameWorst then
				frameWorst, at = degrees, name
			end
		end
		r6Nose.CFrame = parts.Head.CFrame * CFrame.new(0, 0, -0.6)
		rigNose.CFrame = boxes.Head[1].CFrame * CFrame.new(0, 0, 0.6)
		worst = math.max(worst, frameWorst)
		-- Where each right arm hangs, in its body's own frame with -Z its front (R6's), so the numbers can be read.
		local r6Arm = parts.HumanoidRootPart.CFrame:VectorToObjectSpace(-parts["Right Arm"].CFrame.UpVector)
		local rigArm =
			halfTurn:VectorToWorldSpace(rig.PrimaryPart.CFrame:VectorToObjectSpace(-boxes.ArmRight[1].CFrame.UpVector))
		print(
			string.format(
				"@pose worst %.1f deg (%s), clip so far %.1f; right arm R6 (%.2f %.2f %.2f) rig (%.2f %.2f %.2f)",
				frameWorst,
				at,
				worst,
				r6Arm.X,
				r6Arm.Y,
				r6Arm.Z,
				rigArm.X,
				rigArm.Y,
				rigArm.Z
			)
		)
	end)
end
