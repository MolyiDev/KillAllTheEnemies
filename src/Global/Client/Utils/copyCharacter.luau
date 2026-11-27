-- A copy of a character with everything but its looks taken out, standing at rest with its root at the origin, or nil
-- when it cannot be copied: the Decoy's doll and card, and the avatar on the stages and the results. The copy's parts
-- stay as the avatar loaded them (the engine paints the face and the clothes onto a body through its Humanoid only
-- while they are), so nothing here repaints one.
local Players = game:GetService("Players")

-- By the PlayerScripts path: this module is also required from the StarterPlayerScripts copy (the UI's path), where a
-- script.Parent chain would load a second BodyPoseController and register it twice.
local BodyPoseController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.BodyPoseController)

-- Adds `joint` to `part`'s list of joints.
local function link(joints: { [BasePart]: { any } }, part: BasePart?, joint: Instance)
	if not part then return end
	local list = joints[part]
	if not list then
		list = {}
		joints[part] = list
	end
	table.insert(list, joint)
end

-- Sets every part hanging on `part` from it, and on out along the joints. A Motor6D's Transform (the clip) is left
-- out: that is the rest. A WeldConstraint keeps the offset it was made with (`was`).
local function hang(
	part: BasePart,
	joints: { [BasePart]: { any } },
	was: { [BasePart]: CFrame },
	placed: { [BasePart]: boolean }
)
	placed[part] = true
	for _, joint in joints[part] or {} do
		local isPart0 = joint.Part0 == part
		local other = if isPart0 then joint.Part1 else joint.Part0
		if not other or placed[other] then continue end
		if not joint:IsA("JointInstance") then
			other.CFrame = part.CFrame * was[part]:ToObjectSpace(was[other])
		elseif isPart0 then
			other.CFrame = part.CFrame * joint.C0 * joint.C1:Inverse()
		else
			other.CFrame = part.CFrame * joint.C1 * joint.C0:Inverse()
		end
		hang(other, joints, was, placed)
	end
end

-- Stands `copy` as its joints hold it at rest, its root at the origin. A clone keeps every part where the live body
-- had it that frame (mid-step, mid-idle, aiming), and nothing moves a copy out of the Workspace, so two copies taken at
-- different moments would hold different poses.
local function rest(copy: Model)
	local root = copy:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then return end

	local joints = {}
	local was = {}

	for _, child in copy:GetDescendants() do
		if child:IsA("BasePart") then was[child] = child.CFrame end
		if not child:IsA("JointInstance") and not child:IsA("WeldConstraint") then continue end
		link(joints, child.Part0, child)
		link(joints, child.Part1, child)
	end

	root.CFrame = CFrame.identity
	hang(root, joints, was, {})
end

return function(source: Model): Model?
	local wasArchivable = source.Archivable
	source.Archivable = true
	local copy = source:Clone()
	source.Archivable = wasArchivable
	if not copy then return nil end

	for _, child in copy:GetDescendants() do
		if
			child:IsA("LuaSourceContainer")
			or child:IsA("Tool")
			or child:IsA("Sound")
			or child:IsA("ForceField")
			or child:IsA("BillboardGui")
			or child:IsA("ParticleEmitter")
			or child:IsA("Light")
		then
			child:Destroy()
		end
	end

	-- The Humanoid stays, since clothes are drawn through it, but shows no name or bar and runs nothing.
	local humanoid = copy:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.BreakJointsOnDeath = false
		humanoid.RequiresNeck = false
	end

	-- Back at the rig's own C0s first: the copy took the pose's, and stands on them.
	BodyPoseController.Unpose(source, copy)
	rest(copy)

	return copy
end
