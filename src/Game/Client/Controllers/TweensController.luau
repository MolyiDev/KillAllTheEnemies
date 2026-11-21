-- The camera's field of view: a boost with the character's speed, and punches. This module is the only writer of
-- FieldOfView: it writes it every frame, so a second writer would fight it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local TCharacter = require(ReplicatedStorage.Types.TCharacter)
local TCharacterEvents = require(ReplicatedStorage.Types.Events.TCharacterEvents)

local Tune = table.freeze({
	BASE_FOV = 70,
	-- Horizontal root speed (studs/s) at which the speed boost starts and where it is full. It starts above a walk, so
	-- walking leaves the view still.
	FOV_BOOST_FROM_SPEED = 20,
	FOV_BOOST_FULL_SPEED = 60,
	FOV_BOOST = 8,
	-- How fast the boost eases toward its target (per second).
	FOV_BOOST_RESPONSE = 6,
})

local TweensController = {}

local root: BasePart? = nil
local fovBoost = 0
-- The last FieldOfView written: standing still, the view does not change, and a write is a reflection call.
local fovWritten = 0
local fovPunch = 0
-- Seconds the punch eases back over, set per punch by the caller.
local fovPunchReturn = 0.18

-- Punch the FOV out by `degrees` and ease it back over `returnSeconds`. The larger of the running punch and the new
-- one wins rather than their sum: two hits a frame apart must not stack into a lurch.
function TweensController.PunchFov(degrees: number, returnSeconds: number)
	if degrees <= 0 then return end
	if degrees > fovPunch then fovPunch = degrees end
	if returnSeconds > 0 then fovPunchReturn = returnSeconds end
end

local function updateFov(dt: number)
	local boost = 0
	if root then
		local velocity = root.AssemblyLinearVelocity
		local speed = math.sqrt(velocity.X * velocity.X + velocity.Z * velocity.Z)
		local ramp = Tune.FOV_BOOST_FULL_SPEED - Tune.FOV_BOOST_FROM_SPEED
		boost = math.clamp((speed - Tune.FOV_BOOST_FROM_SPEED) / ramp, 0, 1) * Tune.FOV_BOOST
	end
	fovBoost += (boost - fovBoost) * math.clamp(dt * Tune.FOV_BOOST_RESPONSE, 0, 1)

	-- Snapped to zero at the tail rather than left creeping toward it, so an ordinary frame skips it.
	if fovPunch ~= 0 then
		fovPunch -= fovPunch * math.clamp(dt / fovPunchReturn, 0, 1)
		if fovPunch < 0.01 then fovPunch = 0 end
	end

	local fov = Tune.BASE_FOV + fovBoost + fovPunch
	if fov == fovWritten then return end
	fovWritten = fov
	Workspace.CurrentCamera.FieldOfView = fov
end

TweensController.OnSelfCharacterAdded = function(character: TCharacter.TCharacter)
	root = character.HumanoidRootPart
end :: TCharacterEvents.OnCharacterAdded

TweensController.OnSelfCharacterRemoving = function()
	root = nil
end :: TCharacterEvents.OnCharacterRemoving

TweensController.OnStart = function()
	RunService.PreSimulation:Connect(function(dt: number)
		debug.profilebegin("TweensController")
		updateFov(dt)
		debug.profileend()
	end)
end

return Ignis.Register(TweensController)
