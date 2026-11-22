-- The client's half of the match clock: TimeCore follows the server's scale (TimeService), eased the same way, and the
-- local body is slowed with it. The body is the one thing this side leaves to the engine's physics, so its slow
-- motion is made here: gravity goes with the square of the scale and its speeds with the scale, which keeps every
-- fall and jump the same shape, only slower. While the upgrade cards cover the screen it neither walks nor jumps.
--
-- This is the only writer of the local Humanoid's WalkSpeed, JumpPower and JumpHeight, and of Workspace.Gravity.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local Network = require(StarterPlayer.StarterPlayerScripts.GlobalClient.Network)
local UpgradePickController = require(script.Parent.UpgradePickController)
local TimeCore = require(ReplicatedStorage.Shared.Core.TimeCore)
local TCharacter = require(ReplicatedStorage.Types.TCharacter)
local TCharacterEvents = require(ReplicatedStorage.Types.Events.TCharacterEvents)

local ServerNetworkGame = Network.Server.Game

-- Under this scale the body's vertical speed is too small to read its full-speed fall back from (contact noise
-- divided by almost nothing), so the last one read is kept until the clock runs again.
local READABLE_SCALE = 0.05

local TimeController = {}

local humanoid: Humanoid? = nil
local root: BasePart? = nil
-- The body's own walk and jump at full speed, read as it spawns. The jump is its JumpPower or its JumpHeight, as it
-- uses: a JumpPower is a speed, so it scales with the clock, while a JumpHeight is kept by the scaled gravity alone.
local baseWalkSpeed = 0
local baseJump = 0
local isJumpPower = false
-- What was last written, so a body at rest writes nothing.
local writtenWalkScale = 1
local writtenJumpScale = 1
-- The scale the body was last stepped at, and its vertical speed at full speed.
local steppedScale = 1
local fullFallSpeed = 0

local function stepBody()
	local body, part = humanoid, root
	if not body or not part then return end
	local scale = TimeCore.TimeScale
	local isStill = UpgradePickController.IsCovering()

	local walkScale = if isStill then 0 else scale
	if walkScale ~= writtenWalkScale then
		writtenWalkScale = walkScale
		body.WalkSpeed = baseWalkSpeed * walkScale
	end
	local jumpScale = if isStill then 0 elseif isJumpPower then scale else 1
	if jumpScale ~= writtenJumpScale then
		writtenJumpScale = jumpScale
		if isJumpPower then
			body.JumpPower = baseJump * jumpScale
		else
			body.JumpHeight = baseJump * jumpScale
		end
	end

	if scale == 1 and steppedScale == 1 then return end
	local velocity = part.AssemblyLinearVelocity
	if steppedScale >= READABLE_SCALE then fullFallSpeed = velocity.Y / steppedScale end
	part.AssemblyLinearVelocity = Vector3.new(velocity.X, fullFallSpeed * scale, velocity.Z)
	steppedScale = scale
end

TimeController.OnSelfCharacterAdded = function(character: TCharacter.TCharacter)
	local body = character.Humanoid
	humanoid = body
	root = character.HumanoidRootPart
	baseWalkSpeed = body.WalkSpeed
	isJumpPower = body.UseJumpPower
	baseJump = if isJumpPower then body.JumpPower else body.JumpHeight
	writtenWalkScale = 1
	writtenJumpScale = 1
	steppedScale = 1
	fullFallSpeed = 0
end :: TCharacterEvents.OnCharacterAdded

TimeController.OnSelfCharacterRemoving = function()
	humanoid = nil
	root = nil
end :: TCharacterEvents.OnCharacterRemoving

ServerNetworkGame.TimeScale.On(function(scale: number, seconds: number, enemyScale: number)
	TimeCore.SetEnemyTimeScale(enemyScale)
	TimeCore.TweenTimeScale(scale, seconds)
end)

TimeCore.OnTimeScaleChange:Connect(function(scale: number)
	Workspace.Gravity = TimeCore.GRAVITY * scale * scale
end)

TimeController.OnStart = function()
	-- Before the physics step, so the speeds written are the ones it moves the body by.
	RunService.PreSimulation:Connect(stepBody)
end

return Ignis.Register(TimeController)
