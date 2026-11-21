--[[
Retargets R6 Motor6D clips (KeyframeSequence .rbxm, poses HumanoidRootPart > Torso > Head / Left Arm / ...) onto the
enemy rig's bones (Root > Torso > Head, ArmLeft, ArmRight, LegLeft, LegRight; Models.md section 7), so a clip made for
a Humanoid plays on a skinned enemy.

	lune run tools/lune/retarget_r6.luau <in.rbxm> <out.rbxm> <Name> [impactSeconds]

A Pose's CFrame is its Motor6D's Transform, expressed in the joint's frame (C0's rotation, which R6's C1 shares). A
bone rests unrotated, so the same turn as a bone Transform is J * R * J^-1, with J the joint frame seen from the rig.

THE RIG FACES ITS OWN +Z with ArmLeft at +X (Animations.md section 2), where R6 faces -Z with its left arm at -X: the
rig is R6 turned half round about Y, so every joint frame is turned with it. Without the turn a clip plays mirrored
front to back and side to side: the first upload swung the attack's arm backwards (2026-11-20).

ROTATIONS ONLY: the enemy clips are one set for every body size (0.72 to 1.93 times R6), and a translation in studs
would be right for one size only, so translations are dropped (CLAUDE.md, Enemies). The Torso turns about the bone's
pivot at the hips rather than R6's torso centre, which keeps the legs under the body.

impactSeconds: where the clip's blow lands. Keyframe times are scaled so it lands at EnemiesCore.ATTACK_CLIP_IMPACT
(0.6), the moment the renderer times every attack clip to.
]]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Instance = roblox.Instance
local CFrame = roblox.CFrame

local ATTACK_CLIP_IMPACT = 0.6

local inPath, outPath, name, impact = process.args[1], process.args[2], process.args[3], tonumber(process.args[4])
assert(inPath and outPath and name, "usage: lune run tools/lune/retarget_r6.luau <in.rbxm> <out.rbxm> <Name> [impact]")
local timeScale = if impact then ATTACK_CLIP_IMPACT / impact else 1

-- R6's joint frames (the rotation of each Motor6D's C0), seen from the rig: the root joint and the neck share one, and
-- each side's shoulder and hip share one.
local HALF_TURN = CFrame.Angles(0, math.pi, 0)
local SPINE_FRAME = HALF_TURN * CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
local RIGHT_FRAME = HALF_TURN * CFrame.new(0, 0, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0)
local LEFT_FRAME = HALF_TURN * CFrame.new(0, 0, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0)
-- Each R6 part's joint frame, and the bone it drives.
local JOINTS = {
	Torso = { Bone = "Torso", Frame = SPINE_FRAME },
	Head = { Bone = "Head", Frame = SPINE_FRAME },
	["Right Arm"] = { Bone = "ArmRight", Frame = RIGHT_FRAME },
	["Left Arm"] = { Bone = "ArmLeft", Frame = LEFT_FRAME },
	["Right Leg"] = { Bone = "LegRight", Frame = RIGHT_FRAME },
	["Left Leg"] = { Bone = "LegLeft", Frame = LEFT_FRAME },
}
local LIMBS = { "Head", "Right Arm", "Left Arm", "Right Leg", "Left Leg" }

local function bonePose(source)
	local joint = JOINTS[source.Name]
	local pose = Instance.new("Pose")
	pose.Name = joint.Bone
	pose.Weight = source.Weight
	pose.EasingStyle = source.EasingStyle
	pose.EasingDirection = source.EasingDirection
	pose.CFrame = joint.Frame * source.CFrame.Rotation * joint.Frame:Inverse()
	return pose
end

local source = roblox.deserializeModel(fs.readFile(inPath))[1]
assert(source and source.ClassName == "KeyframeSequence", inPath .. " holds no KeyframeSequence")

local sequence = Instance.new("KeyframeSequence")
sequence.Name = name
sequence.Loop = source.Loop
sequence.Priority = source.Priority

local count = 0
for _, sourceKeyframe in source:GetChildren() do
	if not sourceKeyframe:IsA("Keyframe") then continue end

	local keyframe = Instance.new("Keyframe")
	keyframe.Name = sourceKeyframe.Name
	keyframe.Time = sourceKeyframe.Time * timeScale
	for _, marker in sourceKeyframe:GetChildren() do
		if marker:IsA("KeyframeMarker") then marker:Clone().Parent = keyframe end
	end

	-- Every keyframe carries the whole bone tree: a pose missing from its parent's chain is not applied.
	local root = Instance.new("Pose")
	root.Name = "Root"
	root.Weight = 0
	root.Parent = keyframe
	local hrp = sourceKeyframe:FindFirstChild("HumanoidRootPart")
	local torsoSource = if hrp then hrp:FindFirstChild("Torso") else nil
	local torso
	if torsoSource then
		torso = bonePose(torsoSource)
	else
		torso = Instance.new("Pose")
		torso.Name = "Torso"
		torso.Weight = 0
	end
	torso.Parent = root
	for _, limb in LIMBS do
		local limbSource = if torsoSource then torsoSource:FindFirstChild(limb) else nil
		if limbSource then bonePose(limbSource).Parent = torso end
	end

	keyframe.Parent = sequence
	count += 1
end

fs.writeFile(outPath, roblox.serializeModel({ sequence }))
print(string.format("[RETARGET] %s: %d keyframes, x%.3f time -> %s", name, count, timeScale, outPath))
