-- Where a body aims and how its hands hold the gun there: the smoothed pitch and yaw, the shot's kick spring, and the
-- arms (the right hand to the grip, the gun turned onto the target, the left hand to the barrel). Plain functions
-- over a rig; init owns the rigs and calls these once a frame.
local Tune = require(script.Parent.Tune)
local Types = require(script.Parent.Types)

local TAU = math.pi * 2
-- Past half a turn plus this, the short way round is taken the other way, so a target crossing behind does not flip.
local OVER = math.pi + math.rad(45)

local Aim = {}

local function unwrap(from: number, to: number): number
	local near = from + (to - from + math.pi) % TAU - math.pi
	if near > OVER then
		near -= TAU
	elseif near < -OVER then
		near += TAU
	end

	return near
end

-- The pitch and the body-relative yaw this rig wants now: toward `target` for the local body (or along `look` when
-- it has none), toward the server's relayed angles for anyone else.
local function wanted(rig: Types.TRig, isLocal: boolean, target: Vector3?, look: Vector3): (number, number)
	local direction = look
	if isLocal then
		local fromHead = if target then target - rig.Head.Position else nil
		if fromHead and fromHead.Magnitude > Tune.MIN_TARGET_DISTANCE then direction = fromHead.Unit end
	else
		local cosPitch = math.cos(rig.WantedPitch)
		direction = Vector3.new(
			-math.sin(rig.WantedYaw) * cosPitch,
			math.sin(rig.WantedPitch),
			-math.cos(rig.WantedYaw) * cosPitch
		)
	end

	local pitch = math.clamp(math.asin(math.clamp(direction.Y, -1, 1)), Tune.PITCH_MIN, Tune.PITCH_MAX)
	if not rig.Handle then return pitch, 0 end
	local flat = rig.Root.CFrame:VectorToObjectSpace(direction)
	if flat.X * flat.X + flat.Z * flat.Z < 1e-6 then return pitch, 0 end
	return pitch, math.atan2(-flat.X, -flat.Z)
end

-- The smoothed aim and the kick spring, one frame. `alpha` and `twistAlpha` are the frame's follow fractions.
function Aim.Step(
	rig: Types.TRig,
	isLocal: boolean,
	target: Vector3?,
	look: Vector3,
	alpha: number,
	twistAlpha: number,
	dt: number
)
	local pitch, yaw = wanted(rig, isLocal, target, look)
	rig.Pitch += (pitch - rig.Pitch) * alpha
	rig.Yaw += (unwrap(rig.Yaw, yaw) - rig.Yaw) * alpha
	rig.Twist += (math.clamp(rig.Yaw, -Tune.TWIST_TORSO, Tune.TWIST_TORSO) - rig.Twist) * twistAlpha

	local omega = Tune.KICK_SPEED
	rig.KickVelocity += (-omega * omega * rig.Kick - 2 * Tune.KICK_DAMPER * omega * rig.KickVelocity) * dt
	rig.Kick += rig.KickVelocity * dt
end

-- Turns the shoulder so the arm's hand (its grip attachment) points at `target`. Returns the arm's new frame.
local function reach(joint: Motor6D, arm: BasePart, torsoCFrame: CFrame, target: Vector3, gripName: string): CFrame
	local frame = torsoCFrame * joint.C0
	local attachment = arm:FindFirstChild(gripName)
	local hand = if attachment and attachment:IsA("Attachment")
		then attachment.Position
		else Vector3.new(0, -arm.Size.Y / 2, 0)
	local from = joint.C1:Inverse() * hand
	local to = frame:PointToObjectSpace(target)
	local rotation = CFrame.identity
	if from.Magnitude > 1e-3 and to.Magnitude > 1e-3 then
		local axis = from.Unit:Cross(to.Unit)
		local angle = math.acos(math.clamp(from.Unit:Dot(to.Unit), -1, 1))
		if axis.Magnitude > 1e-5 then rotation = CFrame.fromAxisAngle(axis.Unit, angle) end
	end

	joint.Transform = rotation
	return frame * rotation * joint.C1:Inverse()
end

-- Both arms on the gun, aimed at `target` (the local body's), or along the smoothed aim when nil. `gripBases` keeps
-- each grip weld's rest C0, which this re-aims every frame.
function Aim.Hold(
	rig: Types.TRig,
	handle: BasePart,
	target: Vector3?,
	isFirstPerson: boolean,
	gripBases: { [Weld]: CFrame }
)
	local rightArm = rig.Right.Part1
	local leftArm = rig.Left.Part1
	if not rightArm or not leftArm then return end

	local from = rig.Head.Position
	local aimPoint = if target and (target - from).Magnitude > Tune.MIN_TARGET_DISTANCE
		then target
		else from + (rig.Root.CFrame * CFrame.Angles(0, rig.Yaw, 0) * CFrame.Angles(rig.Pitch, 0, 0)).LookVector * 100

	-- The aim frame off the root, written from the torso: its twist and lean undone (in reverse of Motion.Pose's
	-- order), then the aim's yaw and pitch. So the gun stays on the aim line while the body tips under it.
	local torsoCFrame = rig.Torso.CFrame
	local frame = torsoCFrame
		* Tune.PIVOT_CFRAME
		* CFrame.Angles(0, -rig.Twist, 0)
		* CFrame.Angles(0, 0, rig.LeanRoll)
		* CFrame.Angles(rig.LeanPitch, 0, 0)
		* CFrame.Angles(0, rig.Yaw, 0)
		* CFrame.Angles(rig.Pitch + rig.Kick, 0, 0)
		* Tune.UNPIVOT_CFRAME
	local grip = if isFirstPerson then Tune.HOLD_FIRST_PERSON else Tune.HOLD
	local rightFrame = reach(
		rig.Right,
		rightArm,
		torsoCFrame,
		frame * (grip + Vector3.new(0, 0, rig.Kick * Tune.KICK_BACK)),
		"RightGripAttachment"
	)

	local support = frame * grip
	local weld = rightArm:FindFirstChild("RightGrip")
	if weld and weld:IsA("Weld") then
		local base = gripBases[weld]
		if not base then
			base = weld.C0
			gripBases[weld] = base
			weld.Destroying:Once(function()
				gripBases[weld] = nil
			end)
		end

		local current = rightFrame * (base :: CFrame) * weld.C1:Inverse()
		local aimed = CFrame.lookAt(current.Position, aimPoint, frame.UpVector)
			* CFrame.Angles(rig.Kick * Tune.KICK_MUZZLE, 0, 0)
		local muzzle = handle:FindFirstChild("Muzzle")
		local length = if muzzle and muzzle:IsA("Attachment") then -muzzle.Position.Z else 0
		weld.C0 = rightFrame:Inverse() * aimed * weld.C1
		support = if length < Tune.PISTOL_LENGTH
			then aimed * Tune.SUPPORT
			else aimed * Vector3.new(0, -Tune.UNDER, -length * Tune.FORE)
	end

	reach(rig.Left, leftArm, torsoCFrame, support, "LeftGripAttachment")
end

return Aim
