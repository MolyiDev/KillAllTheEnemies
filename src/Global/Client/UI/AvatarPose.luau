-- The poses the HUD's copies of the avatar hold. The copy is never in the Workspace, so no joint moves it: each limb's
-- parts (and the hats welded to them) are turned as one piece about the limb's joint.
local AvatarPose = {}

-- A limb: its part, its turn in the body's own frame (deg): X tips it forward, Z swings it out sideways (the right arm
-- out on a positive turn), and how far it is then moved in that frame, in studs (-Z is forward).
type TLimb = { Part: string, Turn: Vector3, Shift: Vector3? }
export type TPose = { TLimb }

-- The Decoy's card: the doll's pose, one arm up and waving, the other off the body, feet apart and the head cocked.
AvatarPose.DOLL = table.freeze({
	{
		Part = "Right Arm",
		Turn = Vector3.new(-10, 0, 126),
	},
	{
		Part = "Left Arm",
		Turn = Vector3.new(10, 0, -24),
	},
	{
		Part = "Right Leg",
		Turn = Vector3.new(0, 0, 12),
	},
	{
		Part = "Left Leg",
		Turn = Vector3.new(0, 0, -12),
	},
	{
		Part = "Head",
		Turn = Vector3.new(0, -8, -9),
	},
}) :: TPose

-- The results: arms folded across the chest, feet planted apart, chin up. A blocky arm turns only at the shoulder, so
-- each is laid across the front of the chest and moved out of the torso it would otherwise lie inside, the left over
-- the right.
AvatarPose.CROSSED = table.freeze({
	{
		Part = "Right Arm",
		Turn = Vector3.new(0, 0, -68),
		Shift = Vector3.new(-0.35, -0.4, -1),
	},
	{
		Part = "Left Arm",
		Turn = Vector3.new(0, 0, 68),
		Shift = Vector3.new(0.35, -0.4, -1.2),
	},
	{
		Part = "Right Leg",
		Turn = Vector3.new(0, 0, 7),
	},
	{
		Part = "Left Leg",
		Turn = Vector3.new(0, 0, -7),
	},
	{
		Part = "Head",
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
		local part = avatar:FindFirstChild(limb.Part)
		if not part or not part:IsA("BasePart") then continue end

		-- An R6 limb has no rig attachment: its joint is the middle of its top, half a stud down.
		local pivot = part.CFrame * Vector3.new(0, part.Size.Y / 2 - 0.5, 0)
		local turn = limb.Turn
		local swing = CFrame.new(pivot)
			* body
			* CFrame.Angles(math.rad(turn.X), math.rad(turn.Y), math.rad(turn.Z))
			* body:Inverse()
			* CFrame.new(-pivot)
		if limb.Shift then swing = CFrame.new(body * limb.Shift) * swing end
		part.CFrame = swing * part.CFrame
		for handle, wornPart in worn do
			if wornPart == part then handle.CFrame = swing * handle.CFrame end
		end
	end
end

return AvatarPose
