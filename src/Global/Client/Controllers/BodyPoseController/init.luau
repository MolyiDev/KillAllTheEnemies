-- Every R6 body's procedural pose, laid over its walk (Motion: the lean and the legs; Aim: the aim and the hands).
-- The local body aims at Target (WeaponController); everybody else at the pitch and yaw the server relays
-- (Weapons.Aims). C0s are written before the Animator (PreRender) and the arms' Transforms after it (PreSimulation),
-- so the walk still plays under the pose and the arms are the last word on the shoulders.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local Network = require(StarterPlayer.StarterPlayerScripts.GlobalClient.Network)
local Aim = require(script.Aim)
local Motion = require(script.Motion)
local Tune = require(script.Tune)
local Types = require(script.Types)
local gunGrips = require(script.Parent.Parent.Utils.gunGrips)
local CharacterCore = require(ReplicatedStorage.GlobalShared.Core.CharacterCore)
local GunsCore = require(ReplicatedStorage.GlobalShared.Core.GunsCore)
local Components = require(ReplicatedStorage.GlobalShared.ECS.Components)
local World = require(ReplicatedStorage.GlobalShared.ECS.Worlds.World)
local TCharacterEvents = require(ReplicatedStorage.Types.Events.TCharacterEvents)

local ServerNetworkWeapons = Network.Server.Weapons

local LocalPlayer = Players.LocalPlayer

local ANGLE_SCALE = math.pi / 32767
-- The springs are explicit Euler: an alt-tab's long first frame is advanced as this much, never more.
local MAX_DT = 1 / 30
-- The default Animate's walk clips (R6), whose speed is turned negative while backpedalling.
local WALK_CLIP_NAMES = table.freeze({ WalkAnim = true, RunAnim = true })

local BodyPoseController = {}

-- The local body's aim point, set every frame by WeaponController while it holds a gun.
BodyPoseController.Target = nil :: Vector3?
-- The local view is first person: the hand sits where the viewmodel's does, out of the camera.
BodyPoseController.IsFirstPerson = false

local rigs: { [Model]: Types.TRig } = {}
-- The local body's playing walk clip (the default Animate's), to turn backwards while backpedalling.
local walkTrack: AnimationTrack? = nil
local walkConnection: RBXScriptConnection? = nil

-- A jolt up the arms and chest for one shot, `scale` times the base.
function BodyPoseController.Kick(model: Model?, scale: number)
	local rig = if model then rigs[model] else nil
	if not rig then return end
	rig.KickVelocity += Tune.KICK_ANGLE * Tune.KICK_SPEED * math.exp(1) * scale
end

-- Puts `copy`, a clone of `model`, back at rest: the clone took the pose's C0s (the lean, the hips' turn, the head's
-- aim) with it, frozen mid-motion.
function BodyPoseController.Unpose(model: Model, copy: Model)
	local rig = rigs[model]
	if not rig then return end
	for joint, base in rig.Bases do
		local part = joint.Parent
		local twinPart = if part then copy:FindFirstChild(part.Name) else nil
		local twin = if twinPart then twinPart:FindFirstChild(joint.Name) else nil
		if twin and twin:IsA("Motor6D") then twin.C0 = base end
	end
end

local function motor(part: Instance?, name: string): Motor6D?
	local found = if part then part:FindFirstChild(name) else nil
	return if found and found:IsA("Motor6D") then found else nil
end

local function buildRig(model: Model, humanoid: Humanoid): Types.TRig?
	local torso = model:FindFirstChild("Torso")
	local root = model:FindFirstChild("HumanoidRootPart")
	local head = model:FindFirstChild("Head")
	if not torso or not torso:IsA("BasePart") or not root or not root:IsA("BasePart") then return nil end
	if not head or not head:IsA("BasePart") then return nil end
	local neck = motor(torso, "Neck")
	local rootJoint = motor(root, "RootJoint")
	local right = motor(torso, "Right Shoulder")
	local left = motor(torso, "Left Shoulder")
	if not neck or not rootJoint or not right or not left then return nil end

	local hips = {}
	for _, name in { "Right Hip", "Left Hip" } do
		local hip = motor(torso, name)
		if hip then hips[#hips + 1] = hip end
	end

	local bases = {}
	for _, joint in { neck, rootJoint, right, left } do
		bases[joint] = joint.C0
	end

	for _, hip in hips do
		bases[hip] = hip.C0
	end

	return {
		Model = model,
		Humanoid = humanoid,
		Torso = torso,
		Root = root,
		Head = head,
		Neck = neck,
		RootJoint = rootJoint,
		Right = right,
		Left = left,
		RightShoulder = Aim.Shoulder(right, "RightGripAttachment"),
		LeftShoulder = Aim.Shoulder(left, "LeftGripAttachment"),
		Hips = hips,
		Bases = bases,
		Handle = nil,
		Grips = nil,
		GripsHandle = nil,
		GripWeld = nil,
		Hold = nil,
		Raise = 1,
		Pitch = 0,
		Yaw = 0,
		Twist = 0,
		WantedPitch = 0,
		WantedYaw = 0,
		Kick = 0,
		KickVelocity = 0,
		LeanPitch = 0,
		LeanPitchVelocity = 0,
		LeanRoll = 0,
		LeanRollVelocity = 0,
		LastVelocity = Vector3.zero,
		Accel = Vector3.zero,
		WasAirborne = false,
		FallSpeed = 0,
		LegYaw = 0,
		IsBackpedalling = false,
	}
end

-- A held gun's handle: a Tool with a Muzzle under its Handle (buildGunTool's shape).
local function findHandle(model: Model): BasePart?
	local tool = model:FindFirstChildOfClass("Tool")
	local handle = if tool then tool:FindFirstChild("Handle") else nil
	if not handle or not handle:IsA("BasePart") or not handle:FindFirstChild("Muzzle") then return nil end
	return handle
end

-- A gun newly in the hands: its grips and hold, measured once, and the raise from the start.
local function equip(rig: Types.TRig, handle: BasePart?)
	if handle == rig.GripsHandle then return end
	rig.GripsHandle = handle
	rig.GripWeld = nil
	local tool = if handle then handle.Parent else nil
	local gun = if tool then GunsCore.FromToolName(tool.Name) else nil
	rig.Grips = if gun and handle and tool then gunGrips(gun, handle, tool) else nil
	rig.Hold = if gun then Tune.HOLDS[gun.Hold] else nil
	rig.Raise = 0
end

-- The walk clip runs backwards while the local body backpedals. The default Animate re-sets its speed (always
-- forward) whenever the walking speed changes, so this re-asserts the sign every frame rather than once.
local function steerWalkClip(rig: Types.TRig?)
	local track = walkTrack
	if not track or not rig or not track.IsPlaying then return end
	local speed = track.Speed
	local wanted = if rig.IsBackpedalling then -math.abs(speed) else math.abs(speed)
	if wanted ~= speed then track:AdjustSpeed(wanted) end
end

local function render(dt: number)
	dt = math.min(dt, MAX_DT)
	local alpha = 1 - math.exp(-Tune.RATE * dt)
	local twistAlpha = 1 - math.exp(-Tune.TWIST_RATE * dt)
	local localCharacter = LocalPlayer.Character
	local target = BodyPoseController.Target
	local look = Workspace.CurrentCamera.CFrame.LookVector

	for model, rig in rigs do
		if rig.Humanoid.Health <= 0 then continue end
		rig.Handle = findHandle(model)
		equip(rig, rig.Handle)
		rig.Raise = math.min(1, rig.Raise + dt / Tune.RAISE_TIME)
		Aim.Step(rig, model == localCharacter, target, look, alpha, twistAlpha, dt)
		Motion.Step(rig, dt)
		Motion.Pose(rig)
	end

	steerWalkClip(if localCharacter then rigs[localCharacter] else nil)
end

local function animate()
	local localCharacter = LocalPlayer.Character
	local target = BodyPoseController.Target
	local isFirstPerson = BodyPoseController.IsFirstPerson
	for model, rig in rigs do
		local handle = rig.Handle
		if not handle or not handle.Parent or rig.Humanoid.Health <= 0 then continue end
		local isLocal = model == localCharacter
		Aim.Hold(rig, if isLocal then target else nil, isLocal and isFirstPerson)
	end
end

ServerNetworkWeapons.Aims.On(function(aims)
	for _, aim in aims do
		local entity = CharacterCore.GetCharacterByInstanceId(aim.Character)
		local model = if entity then World:get(entity, Components.Model) else nil
		local rig = if model then rigs[model] else nil
		if not rig or model == LocalPlayer.Character then continue end
		rig.WantedPitch = aim.Pitch * ANGLE_SCALE
		-- Relayed as a world yaw; Aim turns it into the body's frame each frame.
		rig.WantedYaw = aim.Yaw * ANGLE_SCALE
	end
end)

BodyPoseController.OnCharacterAdded = function(character)
	local rig = buildRig(character, character.Humanoid)
	if rig then rigs[character] = rig end
end :: TCharacterEvents.OnCharacterAdded

BodyPoseController.OnCharacterRemoving = function(character)
	rigs[character] = nil
end :: TCharacterEvents.OnCharacterRemoving

BodyPoseController.OnSelfCharacterAdded = function(character)
	if walkConnection then walkConnection:Disconnect() end
	walkTrack = nil
	walkConnection = character.Humanoid.Animator.AnimationPlayed:Connect(function(track: AnimationTrack)
		local animation = track.Animation
		if animation and WALK_CLIP_NAMES[animation.Name] then walkTrack = track end
	end)
end :: TCharacterEvents.OnCharacterAdded

BodyPoseController.OnSelfCharacterRemoving = function()
	if walkConnection then walkConnection:Disconnect() end
	walkConnection = nil
	walkTrack = nil
end :: TCharacterEvents.OnCharacterRemoving

BodyPoseController.OnStart = function()
	RunService.PreRender:Connect(render)
	RunService.PreSimulation:Connect(animate)
end

return Ignis.Register(BodyPoseController)
