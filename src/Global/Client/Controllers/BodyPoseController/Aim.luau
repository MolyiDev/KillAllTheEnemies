-- Where a body aims and how its hands hold the gun there: the smoothed pitch and yaw, the shot's kick spring, and the
-- arms (the gun placed by its hold and turned onto the target, then both arms on its own grips, TGun.Hands). Plain
-- functions over a rig; init owns the rigs and calls these once a frame.
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
	local blade = if rig.Hold then rig.Hold.Blade else 0
	rig.Twist += (math.clamp(rig.Yaw, -Tune.TWIST_TORSO, Tune.TWIST_TORSO) - blade - rig.Twist) * twistAlpha

	local omega = Tune.KICK_SPEED
	rig.KickVelocity += (-omega * omega * rig.Kick - 2 * Tune.KICK_DAMPER * omega * rig.KickVelocity) * dt
	rig.Kick += rig.KickVelocity * dt
end

-- What aiming an arm needs from its shoulder, read once per body: the joint's C0 and inverted C1 (which the pose never
-- writes), and the hand (its grip attachment, else the arm's end) as an offset from the joint at rest.
function Aim.Shoulder(joint: Motor6D, gripName: string): Types.TShoulder
	local arm = joint.Part1
	local attachment = if arm then arm:FindFirstChild(gripName) else nil
	local hand = if attachment and attachment:IsA("Attachment")
		then attachment.Position
		else Vector3.new(0, -(if arm then arm.Size.Y else 2) / 2, 0)
	local c1Inverse = joint.C1:Inverse()
	local offset = c1Inverse * hand
	return table.freeze({ C0 = joint.C0, C1Inverse = c1Inverse, Hand = offset, Length = offset.Magnitude })
end

-- Turns the shoulder so the hand points at `target`, rolls the arm about that line so its front face is toward `up`
-- (a block left on its corner pokes through the gun), and slides it along itself (out of the shoulder at
-- most ARM_SLIDE_OUT, into it at most `slideIn`) for the distance a rigid arm cannot make. Returns its new frame.
local function reach(
	joint: Motor6D,
	shoulder: Types.TShoulder,
	frame: CFrame,
	target: Vector3,
	up: Vector3,
	slideIn: number
): CFrame
	local to = frame:PointToObjectSpace(target)
	if shoulder.Length < 1e-3 or to.Magnitude < 1e-3 then
		joint.Transform = CFrame.identity
		return frame * shoulder.C1Inverse
	end

	local hand = shoulder.Hand.Unit
	local line = to.Unit
	local axis = hand:Cross(line)
	local angle = math.acos(math.clamp(hand:Dot(line), -1, 1))
	local rotation = if axis.Magnitude > 1e-5 then CFrame.fromAxisAngle(axis.Unit, angle) else CFrame.identity
	-- Always the arm's front face, the one a straight reach forward already turns up: picking the nearest face would
	-- swap faces mid-aim, and the shirt's sleeve with them.
	local face = (rotation * shoulder.C1Inverse).LookVector
	local toward = frame:VectorToObjectSpace(up)
	toward -= line * line:Dot(toward)
	face -= line * line:Dot(face)
	if toward.Magnitude > 1e-3 and face.Magnitude > 1e-3 then
		rotation = CFrame.fromAxisAngle(line, math.atan2(line:Dot(face:Cross(toward)), face:Dot(toward))) * rotation
	end

	local slide = line * math.clamp(to.Magnitude - shoulder.Length, -slideIn, Tune.ARM_SLIDE_OUT)
	local transform = CFrame.new(slide) * rotation
	joint.Transform = transform
	return frame * transform * shoulder.C1Inverse
end

-- Where a hand's end goes for its grip: HAND_INSET past it along the arm, and `drop` under it across the arm (along
-- the gun's up, as far as it is square to the arm), so the gun rests on the hand's face rather than running through
-- the middle of its block. A negative drop puts the hand over its grip (a handle on top).
local function handPoint(grip: Vector3, shoulderAt: Vector3, up: Vector3, drop: number): Vector3
	local along = (grip - shoulderAt).Unit
	return grip + along * Tune.HAND_INSET - (up - along * along:Dot(up)) * drop
end

-- Moves `shift` so `point` sits within its arm's reach of `shoulderAt`: `length`, give or take the slides.
local function pull(shift: Vector3, shoulderAt: Vector3, point: Vector3, length: number, slideIn: number): Vector3
	local span = point + shift - shoulderAt
	local distance = span.Magnitude
	if distance < 1e-4 then return shift end
	local wanted = math.clamp(distance, length - slideIn, length + Tune.ARM_SLIDE_OUT)
	return shift + span * ((wanted - distance) / distance)
end

-- The gun placed by its hold and aimed at `target` (the local body's, or along the smoothed aim when nil), then both
-- arms on its grips. The grip weld's C0 is rewritten every frame, so the gun is where the solve put it whatever hand
-- frame it was welded at.
function Aim.Hold(rig: Types.TRig, target: Vector3?, isFirstPerson: boolean)
	local grips = rig.Grips
	local hold = rig.Hold
	if not grips or not hold then return end

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

	-- The raise comes up from low and pointing down, carrying a little past the hold; the kick shoves the gun back
	-- along its barrel and tips the muzzle up.
	local back = 1 - rig.Raise
	local lowered = (Tune.RAISE_OVERSHOOT + 1) * back ^ 3 - Tune.RAISE_OVERSHOOT * back ^ 2
	local grip = if isFirstPerson then Tune.HOLD_FIRST_PERSON else hold.Grip
	local barrel = frame * (grip + Vector3.new(0, -lowered * Tune.RAISE_DROP, rig.Kick * Tune.KICK_BACK))
	local aimed = CFrame.lookAt(barrel, aimPoint, frame.UpVector)
		* CFrame.Angles(rig.Kick * Tune.KICK_MUZZLE - lowered * Tune.RAISE_TILT, 0, 0)
	local gun = aimed * CFrame.new(-grips.Barrel)

	-- The gun stays where the hold puts it while both hands can reach it with their arms slid out of (or into) the
	-- shoulders; past that it is moved the least that brings them in, the left pulled first and the right last, since
	-- the right hand carries the gun.
	local right = rig.RightShoulder
	local left = rig.LeftShoulder
	local rightFrame = torsoCFrame * right.C0
	local leftFrame = torsoCFrame * left.C0
	local slideIn = Tune.ARM_SLIDE_IN + math.max(rig.Kick, 0) * Tune.KICK_SLIDE
	local rightPoint = handPoint(gun * grips.Right, rightFrame.Position, gun.UpVector, hold.Drop.X)
	local leftPoint = handPoint(gun * grips.Left, leftFrame.Position, gun.UpVector, hold.Drop.Y)
	local shift = Vector3.zero
	if not isFirstPerson then
		for _ = 1, Tune.SETTLE_ROUNDS do
			shift = pull(shift, leftFrame.Position, leftPoint, left.Length, slideIn)
			shift = pull(shift, rightFrame.Position, rightPoint, right.Length, slideIn)
		end
	end

	gun += shift
	local rightArmFrame = reach(rig.Right, right, rightFrame, rightPoint + shift, gun.UpVector, slideIn)
	reach(rig.Left, left, leftFrame, leftPoint + shift, gun.UpVector, slideIn)

	-- The Tool's weld into the hand, looked up once per gun (it can arrive a frame after the Tool).
	local weld = rig.GripWeld
	if not weld then
		local arm = rig.Right.Part1
		local found = if arm then arm:FindFirstChild("RightGrip") else nil
		if not found or not found:IsA("Weld") then return end
		weld = found
		rig.GripWeld = found
	end

	weld.C0 = rightArmFrame:Inverse() * gun * weld.C1
end

return Aim
