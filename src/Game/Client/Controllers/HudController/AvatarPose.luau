-- The poses the HUD's copies of the avatar hold. The copy is never in the Workspace, so no joint moves it: each limb's
-- parts (and the hats welded to them) are turned as one piece about the limb's joint.
local AvatarPose = {}

-- A limb: its parts from the joint down (an R15 body's, then an R6 one's), the attachment on its first part that
-- marks the joint, its turn in the body's own frame (deg): X tips it forward, Z swings it out sideways (the right arm
-- out on a positive turn), and how far it is then moved in that frame, in studs (-Z is forward).
type TLimb = { Parts: { string }, Joint: string, Turn: Vector3, Shift: Vector3? }
export type TPose = { TLimb }

-- The Decoy's card: the doll's pose, one arm up and waving, the other off the body, feet apart and the head cocked.
AvatarPose.DOLL = table.freeze({
	{
		Parts = { "RightUpperArm", "RightLowerArm", "RightHand", "Right Arm" },
		Joint = "RightShoulderRigAttachment",
		Turn = Vector3.new(-10, 0, 126),
	},
	{
		Parts = { "LeftUpperArm", "LeftLowerArm", "LeftHand", "Left Arm" },
		Joint = "LeftShoulderRigAttachment",
		Turn = Vector3.new(10, 0, -24),
	},
	{
		Parts = { "RightUpperLeg", "RightLowerLeg", "RightFoot", "Right Leg" },
		Joint = "RightHipRigAttachment",
		Turn = Vector3.new(0, 0, 12),
	},
	{
		Parts = { "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "Left Leg" },
		Joint = "LeftHipRigAttachment",
		Turn = Vector3.new(0, 0, -12),
	},
	{
		Parts = { "Head" },
		Joint = "NeckRigAttachment",
		Turn = Vector3.new(0, -8, -9),
	},
}) :: TPose

-- The results: arms folded across the chest, feet planted apart, chin up. A blocky arm turns only at the shoulder, so
-- each is laid across the front of the chest and moved out of the torso it would otherwise lie inside, the left over
-- the right.
AvatarPose.CROSSED = table.freeze({
	{
		Parts = { "RightUpperArm", "RightLowerArm", "RightHand", "Right Arm" },
		Joint = "RightShoulderRigAttachment",
		Turn = Vector3.new(0, 0, -68),
		Shift = Vector3.new(-0.35, -0.4, -1),
	},
	{
		Parts = { "LeftUpperArm", "LeftLowerArm", "LeftHand", "Left Arm" },
		Joint = "LeftShoulderRigAttachment",
		Turn = Vector3.new(0, 0, 68),
		Shift = Vector3.new(0.35, -0.4, -1.2),
	},
	{
		Parts = { "RightUpperLeg", "RightLowerLeg", "RightFoot", "Right Leg" },
		Joint = "RightHipRigAttachment",
		Turn = Vector3.new(0, 0, 7),
	},
	{
		Parts = { "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "Left Leg" },
		Joint = "LeftHipRigAttachment",
		Turn = Vector3.new(0, 0, -7),
	},
	{
		Parts = { "Head" },
		Joint = "NeckRigAttachment",
		Turn = Vector3.new(-7, 0, 0),
	},
}) :: TPose

-- The part an accessory's handle is welded to, or nil.
local function wornOn(handle: BasePart): BasePart?
	for _, child in handle:GetChildren() do
		if not child:IsA("Weld") and not child:IsA("WeldConstraint") then continue end
		local other = if child.Part0 == handle then child.Part1 else child.Part0
		if other then return other end
	end

	return nil
end

-- Puts `avatar`, an unparented copy of a character standing as it loaded, in `pose`. A body with no root is left as
-- it is.
function AvatarPose.Apply(avatar: Model, pose: TPose)
	local root = avatar:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then return end

	-- Each hat's handle and the part it is worn on.
	local worn: { [BasePart]: BasePart } = {}
	for _, child in avatar:GetChildren() do
		local handle = if child:IsA("Accessory") then child:FindFirstChild("Handle") else nil
		if handle and handle:IsA("BasePart") then worn[handle] = wornOn(handle) end
	end

	local body = root.CFrame.Rotation
	for _, limb in pose do
		local moved: { [BasePart]: boolean } = {}
		local first: BasePart? = nil
		for _, name in limb.Parts do
			local part = avatar:FindFirstChild(name)
			if not part or not part:IsA("BasePart") then continue end
			moved[part] = true
			first = first or part
		end

		if not first then continue end
		for handle, part in worn do
			if moved[part] then moved[handle] = true end
		end

		-- An R6 limb has no rig attachment: its joint is the middle of its top, half a stud down.
		local joint = first:FindFirstChild(limb.Joint)
		local pivot = if joint and joint:IsA("Attachment")
			then first.CFrame * joint.CFrame.Position
			else first.CFrame * Vector3.new(0, first.Size.Y / 2 - 0.5, 0)
		local turn = limb.Turn
		local swing = CFrame.new(pivot)
			* body
			* CFrame.Angles(math.rad(turn.X), math.rad(turn.Y), math.rad(turn.Z))
			* body:Inverse()
			* CFrame.new(-pivot)
		if limb.Shift then swing = CFrame.new(body * limb.Shift) * swing end
		for part in moved do
			part.CFrame = swing * part.CFrame
		end
	end
end

return AvatarPose
