-- How a body moves under the aim: the lean from the feet (toward its acceleration, and a little toward its speed, on
-- springs that overshoot once), the hips turned toward the walk (a backpedal past BACKPEDAL_ANGLE), and every
-- C0 of the torso, hips and head. Plain functions over a rig; init owns the rigs and calls these once a frame.
local Tune = require(script.Parent.Tune)
local Types = require(script.Parent.Types)

local TAU = math.pi * 2

local Motion = {}

local function wrap(angle: number): number
	return (angle + math.pi) % TAU - math.pi
end

-- One damped spring step toward `target` (explicit Euler; the caller holds dt under 1/30, well inside its stability).
local function spring(position: number, velocity: number, target: number, dt: number): (number, number)
	local omega = Tune.LEAN_FREQUENCY
	velocity += (omega * omega * (target - position) - 2 * Tune.LEAN_DAMPING * omega * velocity) * dt
	return position + velocity * dt, velocity
end

-- The lean springs and the hips' turn, from how the root moves.
function Motion.Step(rig: Types.TRig, dt: number)
	local velocity = rig.Root.AssemblyLinearVelocity
	local flatVelocity = Vector3.new(velocity.X, 0, velocity.Z)
	local rawAccel = (flatVelocity - rig.LastVelocity) / dt
	rig.LastVelocity = flatVelocity
	rig.Accel = rig.Accel:Lerp(rawAccel, 1 - math.exp(-dt / Tune.ACCEL_SMOOTHING))

	local isAirborne = math.abs(velocity.Y) > Tune.AIRBORNE_SPEED
	if isAirborne then
		rig.FallSpeed = math.max(rig.FallSpeed, -velocity.Y)
	elseif rig.WasAirborne then
		rig.LeanPitchVelocity += math.min(rig.FallSpeed * Tune.LAND_KICK_PER_SPEED, Tune.LAND_KICK_MAX)
		rig.FallSpeed = 0
	end
	rig.WasAirborne = isAirborne

	-- In the body's frame: forward is -Z, right is +X.
	local rootCFrame = rig.Root.CFrame
	local localVelocity = rootCFrame:VectorToObjectSpace(flatVelocity)
	local localAccel = rootCFrame:VectorToObjectSpace(rig.Accel)
	local share = if isAirborne then Tune.LEAN_AIR_SHARE else 1
	local speedRef, accelRef = Tune.LEAN_SPEED_REFERENCE, Tune.LEAN_ACCEL_REFERENCE
	local targetPitch = (
		math.clamp(-localVelocity.Z / speedRef, -1, 1) * Tune.LEAN_SPEED_PITCH
		+ math.clamp(-localAccel.Z / accelRef, -1, 1) * Tune.LEAN_ACCEL_PITCH
	) * share
	local targetRoll = (
		math.clamp(localVelocity.X / speedRef, -1, 1) * Tune.LEAN_SPEED_ROLL
		+ math.clamp(localAccel.X / accelRef, -1, 1) * Tune.LEAN_ACCEL_ROLL
	) * share
	targetPitch = math.clamp(targetPitch, -Tune.LEAN_MAX, Tune.LEAN_MAX)
	targetRoll = math.clamp(targetRoll, -Tune.LEAN_MAX, Tune.LEAN_MAX)
	rig.LeanPitch, rig.LeanPitchVelocity = spring(rig.LeanPitch, rig.LeanPitchVelocity, targetPitch, dt)
	rig.LeanRoll, rig.LeanRollVelocity = spring(rig.LeanRoll, rig.LeanRollVelocity, targetRoll, dt)
	-- The overshoot may pass LEAN_MAX, but a landing on a lean never folds the body in half.
	rig.LeanPitch = math.clamp(rig.LeanPitch, -Tune.LEAN_MAX * 1.5, Tune.LEAN_MAX * 1.5)
	rig.LeanRoll = math.clamp(rig.LeanRoll, -Tune.LEAN_MAX * 1.5, Tune.LEAN_MAX * 1.5)

	-- The walk's angle off the facing: 0 ahead, + to the right. Backpedalling flips at BACKPEDAL_ANGLE, held there by
	-- the hysteresis so a sideways walk does not flicker between the two.
	local speed = flatVelocity.Magnitude
	local legTarget = 0
	if speed >= Tune.LEG_MIN_SPEED and not isAirborne then
		local angle = math.atan2(localVelocity.X, -localVelocity.Z)
		local threshold = Tune.BACKPEDAL_ANGLE
			+ (if rig.IsBackpedalling then -Tune.BACKPEDAL_HYSTERESIS else Tune.BACKPEDAL_HYSTERESIS)
		rig.IsBackpedalling = math.abs(angle) > threshold
		local facing = if rig.IsBackpedalling then wrap(angle - math.pi) else angle
		legTarget = math.clamp(facing, -Tune.LEG_MAX, Tune.LEG_MAX)
	elseif speed < Tune.LEG_MIN_SPEED then
		rig.IsBackpedalling = false
	end

	rig.LegYaw += (legTarget - rig.LegYaw) * (1 - math.exp(-Tune.LEG_RATE * dt))
end

-- Lean (from the feet), the torso's twist and kick (about the hips), the hips turned back under it to where the legs
-- walk, and the head: the aim's pitch, held level through the lean.
function Motion.Pose(rig: Types.TRig)
	local lean = Tune.UNFEET_CFRAME
		* CFrame.Angles(-rig.LeanPitch, 0, 0)
		* CFrame.Angles(0, 0, -rig.LeanRoll)
		* Tune.FEET_CFRAME
	local rootJoint = rig.RootJoint
	local base = rig.Bases[rootJoint]
	rootJoint.C0 = lean
		* Tune.HIP_CFRAME
		* CFrame.fromAxisAngle(Vector3.yAxis, rig.Twist)
		* CFrame.fromAxisAngle(Vector3.xAxis, rig.Kick * Tune.KICK_CHEST)
		* Tune.UNHIP_CFRAME
		* base

	-- The legs keep the lean but not the twist or kick, and turn about the torso's centre toward the walk.
	local rest = rootJoint.Transform * rootJoint.C1:Inverse()
	local hipFrame = (rootJoint.C0 * rest):Inverse() * (lean * base * rest) * CFrame.Angles(0, -rig.LegYaw, 0)
	for _, hip in rig.Hips do
		hip.C0 = hipFrame * rig.Bases[hip]
	end

	local neckBase = rig.Bases[rig.Neck]
	local turn = math.clamp(rig.Yaw - rig.Twist, -Tune.TWIST_HEAD, Tune.TWIST_HEAD)
	rig.Neck.C0 = CFrame.new(neckBase.Position)
		* CFrame.fromAxisAngle(Vector3.yAxis, turn)
		* CFrame.fromAxisAngle(
			Vector3.xAxis,
			rig.Pitch * Tune.HEAD_SHARE + rig.Kick * Tune.KICK_HEAD + rig.LeanPitch * Tune.HEAD_LEVEL
		)
		* CFrame.fromAxisAngle(Vector3.zAxis, rig.LeanRoll * Tune.HEAD_LEVEL)
		* neckBase.Rotation
end

return Motion
