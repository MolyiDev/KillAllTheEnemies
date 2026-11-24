-- The local camera on top of the PlayerModule: the mouse lock (Left Shift, and always in first person), the dot drawn
-- in place of the mouse pointer, cosmetic layers (shake, recoil, first-person motion) laid on whatever it framed
-- this frame, and held shots (HoldShot) that take the view off it for a while and give it back.
--
-- COSMETIC LAYERS ONLY TRANSLATE AND ROLL: the PlayerModule seeds each frame's aim from the camera's LookVector, so a
-- pitch or yaw laid on here would come back as real aim and walk the view away. AimCFrame is the camera before them,
-- for what must not shake.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local TCharacterEvents = require(ReplicatedStorage.Types.Events.TCharacterEvents)

local LocalPlayer = Players.LocalPlayer
local UserGameSettings = UserSettings():GetService("UserGameSettings")
local ZoomController = require(
	LocalPlayer:WaitForChild("PlayerScripts")
		:WaitForChild("PlayerModule")
		:WaitForChild("CameraModule")
		:WaitForChild("ZoomController") :: ModuleScript
) :: any

local clamp = math.clamp
local sin = math.sin
local sqrt = math.sqrt
local rad = math.rad

local LOCK_KEY = Enum.KeyCode.LeftShift

local Tune = table.freeze({
	-- Where the locked view sits off the head, and how fast it slides there and back (per second).
	SHOULDER_OFFSET = Vector3.new(3, 0.5, 0),
	LOCK_BLEND_SPEED = 10,
	-- Inside this camera distance the shoulder eases onto the head, and at or under FIRST_PERSON_ZOOM of dialed zoom
	-- the view is first person and the first-person motion fades in.
	HEAD_FADE_DISTANCE = 10,
	FIRST_PERSON_OFFSET = Vector3.new(0, 0.5, 0),
	FIRST_PERSON_ZOOM = 0.75,
	FIRST_PERSON_BLEND_SPEED = 8,
	-- The springs below are explicit Euler and blow up past dt ~2/omega; an alt-tab's first frame would fling the
	-- camera, so a frame advances them at most this much.
	MAX_FRAME_DT = 1 / 30,
	-- Shake: seconds per SHAKE_ROUGH_SCALE swings is `roughness`; the swings over a shake's length are held to
	-- [MIN, MAX], under which it is a shove and over which a buzz (tuned by ear).
	SHAKE_DEFAULT_POS = Vector3.new(0.5, 0.5, 0.5),
	SHAKE_ROUGH_SCALE = 4,
	SHAKE_ROLL = rad(0.05),
	SHAKE_SWINGS_MIN = 2.6,
	SHAKE_SWINGS_MAX = 5.5,
	-- Shakes landing together add up to at most a blast's: a pack of exploders going off at once is one blow.
	SHAKE_MAX_MAGNITUDE = 4,
	RECOIL_REST = 1e-7,
	-- The dot's width at 1920x1080, and its floor in pixels. Kept even: the dot is centred on the mouse, and an odd
	-- width would put its edges on half pixels.
	DOT_PIXELS = 6,
	MIN_DOT_PIXELS = 4,
	DESIGN_SIZE = Vector2.new(1920, 1080),
})

-- A held shot: how fast the eye and the point it looks at chase the shot (critically damped, rad/s; the look is
-- quicker, so the view swings onto the subject and then glides in), the field of view with the eye, the lean into a
-- sideways swing (radians per stud a second, its most, how fast it follows), the shot's slow drift while it holds
-- (studs side to side, rad/s, and its rise as a share of both, off a clean ratio so the loop never visibly repeats),
-- and how long the way back to the player takes.
local ShotMotion = table.freeze({
	EYE_FREQUENCY = 4.2,
	LOOK_FREQUENCY = 6.5,
	FOV_FREQUENCY = 4.2,
	BANK_PER_SPEED = rad(0.12),
	BANK_MAX = rad(4),
	BANK_RESPONSE = 6,
	SWAY = 0.18,
	SWAY_RATE = 0.45,
	SWAY_RISE = 0.5,
	SWAY_RISE_RATE = 0.71,
	RETURN_SECONDS = 0.85,
})

-- First-person motion: a stride bob, a lean into strafing, breathing when still, and a landing dip on a spring.
local ViewMotion = table.freeze({
	BobReferenceSpeed = 4,
	BobFrequency = 0.4,
	BobAmplitudeX = 0.03,
	BobAmplitudeY = 0.045,
	BobRoll = rad(0.6),
	BobResponse = 8,
	StrafeReferenceSpeed = 16,
	StrafeRoll = rad(4),
	StrafeRollResponse = 7,
	BreatheFrequency = 1,
	BreatheAmplitude = 0.01,
	BreatheSwayRatio = 0.8,
	BreatheSwayAmplitude = 0.01,
	BreatheRoll = rad(0.2),
	LandStiffness = 80,
	LandDamping = 8,
	LandVelocityScale = 0.25,
	LandMaxImpactSpeed = 100,
	JumpImpulse = 4,
})

type TShake = {
	Magnitude: number,
	SwingsPerSecond: number,
	Duration: number,
	PosInf: Vector3,
	StartTime: number,
	Seed: number,
}

local CameraController = {}

-- Left Shift's toggle. First person locks the mouse too, whatever this says.
CameraController.IsLocked = false
-- The body is turned to face the aim (the mouse is locked and the body alive), so a walk is a strafe.
CameraController.IsFacingAim = false
-- Scales every shake (0 turns them off), for the Reduce Camera Shake setting. A weapon's kick is not a shake: it stays.
CameraController.ShakeMultiplier = 1
-- A menu that needs the cursor is up: nothing here locks the mouse while this is true.
CameraController.IsMouseFreed = false
-- The camera as framed, before the cosmetic layers: where the player is actually looking.
CameraController.AimCFrame = CFrame.identity

local accumulatedTime = 0
local activeShakes: { TShake } = {}
local lockBlend = 0
local firstPersonBlend = 0

-- The recoil spring, per axis (studs; +Y up). Generic until a caller sets its own shape.
local recoilK = 25 * 25
local recoilC = 2 * 0.6 * 25
local recoilRollCoupling = 0.25
local recoilX, recoilXVel, recoilY, recoilYVel = 0, 0, 0, 0

local isMouseLocked = false
-- A place with no guns (UseRobloxMouse): Roblox's own pointer and no Shift lock.
local isRobloxMouse = false
-- The dot, and what was last written to it. Off once a place draws its own crosshair on the mouse (HideDot).
local isDotWanted = true
local dot: Frame? = nil
local isDotVisible = true
local dotMouse = Vector2.zero

local selfRoot: BasePart? = nil
local selfHumanoid: Humanoid? = nil
local isBodyDead = false
local isGrounded = true
local bobDistance = 0
local bobAmount = 0
local currentRoll = 0
local breathePhase = 0
local landPos, landVel = 0, 0
-- The deepest fall speed of this airborne stretch: the touchdown snap zeroes velocity before the state fires.
local airborneFallSpeed = 0
local pendingLookAt: Vector3? = nil
local stateConnection: RBXScriptConnection? = nil

-- The held shot. While Active the camera is Scriptable and built here alone: turning it while the PlayerModule still
-- drives it would be two writers pulling every frame, which shakes. Goal is the shot asked for (nil once given back);
-- Eye, Look and Fov chase it. What the PlayerModule had when it was taken (where it frames from off the root, how far
-- back, along what look, at what field of view) is kept to build its own camera again on the way back.
local held = {
	Goal = nil :: { Eye: Vector3, Look: Vector3, Fov: number, Right: Vector3 }?,
	IsActive = false,
	ReleasedAt = nil :: number?,
	Eye = Vector3.zero,
	EyeVelocity = Vector3.zero,
	Look = Vector3.zero,
	LookVelocity = Vector3.zero,
	Fov = 70,
	FovVelocity = 0,
	Roll = 0,
	SwayClock = 0,
	-- What was drawn last frame, before the layers: where a shot taken back mid-return starts from.
	ShownEye = Vector3.zero,
	ShownLook = Vector3.zero,
	ShownFov = 70,
	SubjectOffset = Vector3.zero,
	Zoom = 0,
	ReturnLook = -Vector3.zAxis,
	ReturnFov = 70,
}

-- One shake impulse that fades over `duration`. `roughness` runs backward to its name: SMALLER is faster.
function CameraController.Shake(magnitude: number, roughness: number, duration: number, positionInfluence: Vector3?)
	if CameraController.ShakeMultiplier <= 0 then return end
	local rate = Tune.SHAKE_ROUGH_SCALE / math.max(roughness, 0.01)
	if duration > 0 then rate = clamp(rate, Tune.SHAKE_SWINGS_MIN / duration, Tune.SHAKE_SWINGS_MAX / duration) end
	activeShakes[#activeShakes + 1] = {
		Magnitude = magnitude,
		SwingsPerSecond = rate,
		Duration = duration,
		PosInf = positionInfluence or Tune.SHAKE_DEFAULT_POS,
		StartTime = accumulatedTime,
		Seed = math.random() * 1000,
	}
end

-- The recoil spring's shape: `freq` (snappier return), `damp` (< 1 overshoots a little), and radians of roll per
-- stud of sideways kick.
function CameraController.SetRecoilSpring(freq: number, damp: number, rollCoupling: number)
	recoilK = freq * freq
	recoilC = 2 * damp * freq
	recoilRollCoupling = rollCoupling
end

-- A recoil spring's peak displacement per unit of impulse, so a kick can be asked for in studs:
-- peak = v0 / wd * exp(-z / sqrt(1 - z^2) * atan2(sqrt(1 - z^2), z)), wd = w * sqrt(1 - z^2). The Euler step falls
-- short of it (44% at freq 25 / damp 0.6 at 60 fps), so compare kicks on one spring.
function CameraController.RecoilPeakPerImpulse(freq: number, damp: number): number
	local root = sqrt(1 - damp * damp)
	return math.exp(-damp / root * math.atan2(root, damp)) / (freq * root)
end

-- Kicks the view up by `upImpulse` and sideways by `sideImpulse` (studs a second); it springs back on its own.
function CameraController.AddRecoil(upImpulse: number, sideImpulse: number)
	recoilYVel += upImpulse
	recoilXVel += sideImpulse
end

-- Takes the dot away for good, for a place that draws its own crosshair where the dot would be. Safe before or after
-- this controller's OnStart.
function CameraController.HideDot()
	isDotWanted = false
	local frame = dot
	dot = nil
	if frame and frame.Parent then frame.Parent:Destroy() end
end

-- For a place with no guns: Roblox's own pointer instead of the dot, and no Shift lock. First person still locks the
-- mouse, or the view would not turn. Safe before or after this controller's OnStart.
function CameraController.UseRobloxMouse()
	isRobloxMouse = true
	CameraController.IsLocked = false
	ContextActionService:UnbindAction("CameraLock")
	CameraController.HideDot()
	UserInputService.MouseIconEnabled = true
end

-- With Roblox's pointer (UseRobloxMouse), hides it while the place draws a crosshair on the mouse in its place (the
-- lobby's shooting range), and brings it back after.
function CameraController.SetPointerHidden(isHidden: boolean)
	if not isRobloxMouse then return end
	UserInputService.MouseIconEnabled = not isHidden
end

-- Turns the view to face `target` on the next frame; the PlayerModule carries on from there.
function CameraController.LookAt(target: Vector3)
	pendingLookAt = target
end

-- Takes the view onto a shot from `eye` looking at `look`: from the next frame the camera glides there from wherever
-- it is and stays, drifting a little, until ReleaseShot. Called again, it glides on to the new shot.
function CameraController.HoldShot(eye: Vector3, look: Vector3, fov: number)
	local right = (look - eye):Cross(Vector3.yAxis)
	held.Goal = {
		Eye = eye,
		Look = look,
		Fov = fov,
		Right = if right.Magnitude > 1e-3 then right.Unit else Vector3.xAxis,
	}
	if not held.ReleasedAt then return end

	-- Taken back on the way to the player: the springs go on from what is on screen.
	held.ReleasedAt = nil
	held.Eye, held.Look, held.Fov = held.ShownEye, held.ShownLook, held.ShownFov
	held.EyeVelocity, held.LookVelocity, held.FovVelocity = Vector3.zero, Vector3.zero, 0
end

-- Gives the view back: the camera glides to where the PlayerModule would have it now and hands it over there.
function CameraController.ReleaseShot()
	if not held.Goal then return end
	if not held.IsActive then
		held.Goal = nil
		return
	end
	if not held.ReleasedAt then held.ReleasedAt = accumulatedTime end
end

-- Pushes a held shot's eye along its view at `speed` studs a second; its spring brings it back.
function CameraController.NudgeShot(speed: number)
	if not held.IsActive or held.ReleasedAt then return end
	local along = held.Look - held.Eye
	if along.Magnitude < 1e-3 then return end
	held.EyeVelocity += along.Unit * speed
end

local function computeShakeOffset(): CFrame
	local now = accumulatedTime
	local totalPos = Vector3.zero
	local totalRoll = 0
	local totalMagnitude = 0
	local multiplier = CameraController.ShakeMultiplier

	for i = #activeShakes, 1, -1 do
		local shake = activeShakes[i]
		local elapsed = now - shake.StartTime
		if elapsed >= shake.Duration then
			table.remove(activeShakes, i)
			continue
		end

		local magnitude = shake.Magnitude * (1 - elapsed / shake.Duration) * multiplier
		totalMagnitude += magnitude
		local t = now * shake.SwingsPerSecond
		local seed = shake.Seed
		-- The third argument picks an independent layer of the noise per axis; the values are the authored ones.
		local wobble = Vector3.new(math.noise(t, seed, 4), math.noise(t, seed, 5), math.noise(t, seed, 6)) * 2
		totalPos += wobble * shake.PosInf * magnitude
		totalRoll += math.noise(t, seed, 3) * 2 * Tune.SHAKE_ROLL * magnitude
	end

	local cap = Tune.SHAKE_MAX_MAGNITUDE * multiplier
	if totalMagnitude > cap then
		local scale = cap / totalMagnitude
		totalPos *= scale
		totalRoll *= scale
	end

	return CFrame.new(totalPos) * CFrame.Angles(0, 0, totalRoll)
end

local function computeRecoilOffset(dt: number): CFrame
	recoilYVel += (-recoilK * recoilY - recoilC * recoilYVel) * dt
	recoilY += recoilYVel * dt
	recoilXVel += (-recoilK * recoilX - recoilC * recoilXVel) * dt
	recoilX += recoilXVel * dt
	if recoilY * recoilY + recoilYVel * recoilYVel < Tune.RECOIL_REST then
		recoilY, recoilYVel = 0, 0
	end

	if recoilX * recoilX + recoilXVel * recoilXVel < Tune.RECOIL_REST then
		recoilX, recoilXVel = 0, 0
	end

	if recoilX == 0 and recoilY == 0 then return CFrame.identity end
	return CFrame.new(recoilX, recoilY, 0) * CFrame.Angles(0, 0, recoilX * recoilRollCoupling)
end

local function computeFirstPersonOffset(dt: number, blend: number, cameraCFrame: CFrame): CFrame
	local root = selfRoot
	if not root then return CFrame.identity end
	local velocity = root.AssemblyLinearVelocity
	local horizontalSpeed = sqrt(velocity.X * velocity.X + velocity.Z * velocity.Z)
	if not isGrounded then
		airborneFallSpeed = math.max(airborneFallSpeed, clamp(-velocity.Y, 0, ViewMotion.LandMaxImpactSpeed))
	end

	-- The step phase advances by distance, so the bob keeps step with the feet at any framerate.
	local targetBob = if isGrounded then clamp(horizontalSpeed / ViewMotion.BobReferenceSpeed, 0, 1) else 0
	bobAmount += (targetBob - bobAmount) * clamp(dt * ViewMotion.BobResponse, 0, 1)
	bobDistance += horizontalSpeed * dt
	local phase = bobDistance * ViewMotion.BobFrequency
	local stride = sin(phase)
	local bobX = stride * ViewMotion.BobAmplitudeX * bobAmount
	local bobY = sin(phase * 2) * ViewMotion.BobAmplitudeY * bobAmount
	local bobRoll = stride * ViewMotion.BobRoll * bobAmount

	local right = cameraCFrame.RightVector
	local lateralSpeed = velocity.X * right.X + velocity.Z * right.Z
	local targetRoll = -clamp(lateralSpeed / ViewMotion.StrafeReferenceSpeed, -1, 1) * ViewMotion.StrafeRoll
	currentRoll += (targetRoll - currentRoll) * clamp(dt * ViewMotion.StrafeRollResponse, 0, 1)

	-- Breathing weaves (a sway off a clean ratio of the rise) so the loop never visibly repeats.
	breathePhase += dt * ViewMotion.BreatheFrequency
	local idle = 1 - bobAmount
	local breatheSway = sin(breathePhase * ViewMotion.BreatheSwayRatio)
	local breatheX = breatheSway * ViewMotion.BreatheSwayAmplitude * idle
	local breatheY = sin(breathePhase) * ViewMotion.BreatheAmplitude * idle
	local breatheRoll = breatheSway * ViewMotion.BreatheRoll * idle

	landVel += (-ViewMotion.LandStiffness * landPos - ViewMotion.LandDamping * landVel) * dt
	landPos += landVel * dt

	local x = (bobX + breatheX) * blend
	local y = (bobY + breatheY + landPos) * blend
	local roll = (bobRoll + currentRoll + breatheRoll) * blend
	return CFrame.new(x, y, 0) * CFrame.Angles(0, 0, roll)
end

-- Roblox's own shift lock is off (EnableMouseLockOption in the project files), so Shift is this one only. First person
-- is always locked: the PlayerModule turns the view only while the mouse is captured or right-dragged. The mouse is
-- handed back only on the frame the lock ends, so a right-drag's capture is left alone.
--
-- RotationType is set every frame: the PlayerModule saves and restores it around first person and right-drag
-- rotation, and would otherwise hand back a stale one. While locked the body is turned by faceAim, not by it.
local function applyLock()
	local isFirstPerson = firstPersonBlend > 0.5
	-- A held shot frames something to look at, usually with a screen over it: the pointer is free.
	local shouldLockMouse = (CameraController.IsLocked or isFirstPerson)
		and not CameraController.IsMouseFreed
		and not held.IsActive
	if shouldLockMouse then
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		end
	elseif isMouseLocked then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
	isMouseLocked = shouldLockMouse

	-- First person sets CameraRelative itself every frame (BaseCamera); writing over it would flip it twice a frame.
	if isFirstPerson then return end
	if UserGameSettings.RotationType ~= Enum.RotationType.MovementRelative then
		UserGameSettings.RotationType = Enum.RotationType.MovementRelative
	end
end

-- Locked, the body faces along the aim. CameraRelative rotation, with the camera off to one side, left the body facing
-- away from the aim, further left the more the view tipped down.
local function faceAim(look: Vector3)
	local humanoid = selfHumanoid
	local root = selfRoot
	if not humanoid or not root then return end

	local shouldFaceAim = isMouseLocked and not isBodyDead
	if shouldFaceAim ~= CameraController.IsFacingAim then
		CameraController.IsFacingAim = shouldFaceAim
		humanoid.AutoRotate = not shouldFaceAim
	end
	if not shouldFaceAim then return end

	-- The view's pitch is clamped short of straight down, so the flat look never vanishes.
	root.CFrame = CFrame.lookAlong(root.Position, Vector3.new(look.X, 0, look.Z))
end

-- The dot sits on the mouse, which a lock holds at the centre. A touch screen has no mouse to follow, so it shows the
-- dot only while locked.
local function moveDot()
	local frame = dot
	if not frame then return end
	local isVisible = isMouseLocked or UserInputService.MouseEnabled
	if isVisible ~= isDotVisible then
		isDotVisible = isVisible
		frame.Visible = isVisible
	end
	if not isVisible then return end

	local mouse = UserInputService:GetMouseLocation()
	if mouse == dotMouse then return end
	dotMouse = mouse
	frame.Position = UDim2.fromOffset(mouse.X, mouse.Y)
end

local function resetMotion()
	isGrounded = true
	bobDistance, bobAmount, currentRoll, breathePhase = 0, 0, 0, 0
	landPos, landVel, airborneFallSpeed = 0, 0, 0
	recoilX, recoilXVel, recoilY, recoilYVel = 0, 0, 0, 0
end

local function isFirstPersonZoom(): boolean
	return ZoomController.GetTargetZoom() <= Tune.FIRST_PERSON_ZOOM
end

-- One step of a critically damped spring toward `goal`, in closed form: exact at any dt, so a long frame neither
-- overshoots nor flings, and a goal that moves mid-flight is chased on with no break in speed.
local function chase(
	value: Vector3,
	velocity: Vector3,
	goal: Vector3,
	frequency: number,
	dt: number
): (Vector3, Vector3)
	local offset = value - goal
	local decay = math.exp(-frequency * dt)
	local lead = (velocity + offset * frequency) * dt
	return goal + (offset + lead) * decay, (velocity - lead * frequency) * decay
end

local function chaseNumber(
	value: number,
	velocity: number,
	goal: number,
	frequency: number,
	dt: number
): (number, number)
	local offset = value - goal
	local decay = math.exp(-frequency * dt)
	local lead = (velocity + offset * frequency) * dt
	return goal + (offset + lead) * decay, (velocity - lead * frequency) * decay
end

local function smootherStep(t: number): number
	t = clamp(t, 0, 1)
	return t * t * t * (t * (t * 6 - 15) + 10)
end

-- Takes the camera off the PlayerModule, starting from the frame it made this frame (so taking it is never a jump),
-- and keeps what it needs to make that camera again.
local function takeShot(camera: Camera, framed: CFrame)
	local subject = camera.Focus.Position
	local root = selfRoot
	held.SubjectOffset = if root then subject - root.Position else Vector3.zero
	held.Zoom = (subject - framed.Position).Magnitude
	held.ReturnLook = framed.LookVector
	held.ReturnFov = camera.FieldOfView
	held.Eye = framed.Position
	held.Look = framed.Position + framed.LookVector * math.max(held.Zoom, 1)
	held.Fov = camera.FieldOfView
	held.EyeVelocity, held.LookVelocity, held.FovVelocity = Vector3.zero, Vector3.zero, 0
	held.ShownEye, held.ShownFov = held.Eye, held.Fov
	held.Roll = 0
	held.SwayClock = 0
	held.IsActive = true
	camera.CameraType = Enum.CameraType.Scriptable
end

-- Back to the PlayerModule, on the camera it would make itself: the eye the zoom behind the subject along the look it
-- had, Focus on the subject. It rebuilds its aim from that look, so it carries on from exactly this frame.
local function handBack(camera: Camera, eye: Vector3, subject: Vector3): CFrame
	held.Goal = nil
	held.IsActive = false
	held.ReleasedAt = nil
	held.Roll = 0
	local cframe = if (subject - eye).Magnitude > 1e-3 then CFrame.lookAt(eye, subject) else camera.CFrame
	camera.CFrame = cframe
	camera.Focus = CFrame.new(subject)
	camera.FieldOfView = held.ReturnFov
	camera.CameraType = Enum.CameraType.Custom
	return cframe
end

-- One frame of a held shot: the whole camera, since on Scriptable nothing else makes one. Returns it level; the lean
-- comes back separately, to go on the rendered camera only.
local function stepShot(dt: number, camera: Camera, framed: CFrame): (CFrame, number)
	local goal = held.Goal :: { Eye: Vector3, Look: Vector3, Fov: number, Right: Vector3 }
	if not held.IsActive then takeShot(camera, framed) end

	-- Its drift rides the goal, not the camera, so the springs smooth it in as the shot is taken.
	held.SwayClock += dt
	local phase = held.SwayClock * ShotMotion.SWAY_RATE
	local across = math.sin(phase) * ShotMotion.SWAY
	local rise = math.sin(phase * ShotMotion.SWAY_RISE_RATE) * ShotMotion.SWAY * ShotMotion.SWAY_RISE
	local sway = goal.Right * across + Vector3.yAxis * rise
	held.Eye, held.EyeVelocity = chase(held.Eye, held.EyeVelocity, goal.Eye + sway, ShotMotion.EYE_FREQUENCY, dt)
	held.Look, held.LookVelocity = chase(held.Look, held.LookVelocity, goal.Look, ShotMotion.LOOK_FREQUENCY, dt)
	held.Fov, held.FovVelocity = chaseNumber(held.Fov, held.FovVelocity, goal.Fov, ShotMotion.FOV_FREQUENCY, dt)

	-- On the way back, a blend from the shot to the PlayerModule's camera made live off the root, so a player who
	-- walks off meanwhile is followed, and the blend ends exactly on it.
	local eye, look, fov = held.Eye, held.Look, held.Fov
	local back = 0
	local releasedAt = held.ReleasedAt
	if releasedAt then
		local root = selfRoot
		if not root then return handBack(camera, eye, look), 0 end
		local subject = root.Position + held.SubjectOffset
		local returnEye = subject - held.ReturnLook * held.Zoom
		back = smootherStep((accumulatedTime - releasedAt) / ShotMotion.RETURN_SECONDS)
		if back >= 1 then return handBack(camera, returnEye, subject), 0 end
		eye = eye:Lerp(returnEye, back)
		look = look:Lerp(subject, back)
		fov += (held.ReturnFov - fov) * back
	end

	-- The lean follows how fast the eye crosses the view, and dies away with the return so it is level when handed back.
	-- Straight up or down has no level frame to look along: the last frame's turn stands in.
	local toLook = look - eye
	local length = toLook.Magnitude
	local cframe = if length > 1e-3 and math.abs(toLook.Y) < length * 0.999
		then CFrame.lookAt(eye, look)
		else CFrame.new(eye) * camera.CFrame.Rotation
	local sideways = (eye - held.ShownEye):Dot(cframe.RightVector) / math.max(dt, 1e-3)
	local bank = clamp(-sideways * ShotMotion.BANK_PER_SPEED, -ShotMotion.BANK_MAX, ShotMotion.BANK_MAX) * (1 - back)
	held.Roll += (bank - held.Roll) * (1 - math.exp(-ShotMotion.BANK_RESPONSE * dt))

	-- Engine writes only when the value moves: FieldOfView is still once the shot has settled.
	if math.abs(held.ShownFov - fov) > 1e-3 then camera.FieldOfView = fov end
	held.ShownEye, held.ShownLook, held.ShownFov = eye, look, fov
	camera.Focus = CFrame.new(look)
	return cframe, held.Roll
end

local function update(dt: number)
	dt = math.min(dt, Tune.MAX_FRAME_DT)
	accumulatedTime += dt
	local camera = Workspace.CurrentCamera
	local framed = camera.CFrame
	local cameraCFrame = framed

	local lookAt = pendingLookAt
	if lookAt then
		pendingLookAt = nil
		local eye = cameraCFrame.Position
		if (lookAt - eye).Magnitude > 1e-3 then cameraCFrame = CFrame.lookAt(eye, lookAt) end
	end

	-- A held shot builds the whole camera; nothing below moves what it frames (no shoulder, no first person). On the
	-- frame it is handed back, what it returns is the PlayerModule's own camera, which the rest treats as usual.
	local shotRoll = 0
	if held.Goal then
		cameraCFrame, shotRoll = stepShot(dt, camera, framed)
	end
	local isShot = held.IsActive

	local isFirstPerson = isFirstPersonZoom() and not isShot
	local targetFirstPerson = if isFirstPerson then 1 else 0
	firstPersonBlend += (targetFirstPerson - firstPersonBlend) * clamp(dt * Tune.FIRST_PERSON_BLEND_SPEED, 0, 1)
	-- The head fade never reaches zero, so a lock left on in first person would still nudge the view to the shoulder.
	local targetLock = if CameraController.IsLocked and not isFirstPerson then 1 else 0
	lockBlend += (targetLock - lockBlend) * clamp(dt * Tune.LOCK_BLEND_SPEED, 0, 1)
	applyLock()
	moveDot()

	-- The shoulder slides in with the lock, and onto the head as the camera closes in on it.
	local zoomDistance = (camera.Focus.Position - cameraCFrame.Position).Magnitude
	local headAlpha = clamp(zoomDistance / Tune.HEAD_FADE_DISTANCE, 0, 1)
	-- Unlocked at a normal distance there is no offset at all, and no CFrame is built for it.
	local aimCFrame = cameraCFrame
	if not isShot and (lockBlend > 1e-3 or headAlpha < 1) then
		aimCFrame *= CFrame.new(Tune.FIRST_PERSON_OFFSET:Lerp(Tune.SHOULDER_OFFSET * lockBlend, headAlpha))
	end
	CameraController.AimCFrame = aimCFrame
	faceAim(aimCFrame.LookVector)

	local render = aimCFrame
	if shotRoll ~= 0 then
		render *= CFrame.Angles(0, 0, shotRoll)
	end

	if firstPersonBlend > 0.001 then
		render *= computeFirstPersonOffset(dt, firstPersonBlend, aimCFrame)
	end

	if recoilX ~= 0 or recoilY ~= 0 or recoilXVel ~= 0 or recoilYVel ~= 0 then
		render *= computeRecoilOffset(dt)
	end

	if #activeShakes > 0 then
		render *= computeShakeOffset()
	end

	-- A frame with nothing laid on is left as the PlayerModule framed it: no write to the Instance.
	if render ~= framed then camera.CFrame = render end
end

local function sizeDot()
	local frame = dot
	if not frame then return end
	local scale = Workspace.CurrentCamera.ViewportSize / Tune.DESIGN_SIZE
	local pixels = math.max(Tune.MIN_DOT_PIXELS, math.round(Tune.DOT_PIXELS * math.min(scale.X, scale.Y) * 0.5) * 2)
	frame.Size = UDim2.fromOffset(pixels, pixels)
end

local function createDot()
	if not isDotWanted then return end
	local gui = Instance.new("ScreenGui")
	gui.Name = "Cursor"
	-- The mouse location counts from the window's top, under the top bar.
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 1000

	local frame = Instance.new("Frame")
	frame.Name = "Dot"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame

	dot = frame
	sizeDot()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	-- HideDot while waiting for the PlayerGui has already destroyed it.
	if dot ~= frame then return end
	gui.Parent = playerGui
end

CameraController.OnSelfCharacterAdded = function(character)
	if stateConnection then stateConnection:Disconnect() end
	selfRoot = character.HumanoidRootPart
	selfHumanoid = character.Humanoid
	isBodyDead = false
	CameraController.IsFacingAim = false
	firstPersonBlend = 0
	resetMotion()

	-- The landing dip is kicked only in first person, so a jump in third person cannot jolt the next entry.
	stateConnection = character.Humanoid.StateChanged:Connect(function(_, newState: Enum.HumanoidStateType)
		if newState == Enum.HumanoidStateType.Jumping then
			if firstPersonBlend > 0.001 then
				landVel += ViewMotion.JumpImpulse
			end
			isGrounded = false
		elseif newState == Enum.HumanoidStateType.Freefall then
			isGrounded = false
		elseif newState == Enum.HumanoidStateType.Running or newState == Enum.HumanoidStateType.RunningNoPhysics then
			if not isGrounded and firstPersonBlend > 0.001 then
				landVel -= airborneFallSpeed * ViewMotion.LandVelocityScale
			end
			airborneFallSpeed = 0
			isGrounded = true
		elseif newState == Enum.HumanoidStateType.Dead then
			-- A downed body lies until a revive brings a new one, so it is never turned again.
			isBodyDead = true
		end
	end)
end :: TCharacterEvents.OnCharacterAdded

CameraController.OnSelfCharacterRemoving = function()
	if stateConnection then stateConnection:Disconnect() end
	stateConnection = nil
	selfRoot = nil
	selfHumanoid = nil
end :: TCharacterEvents.OnCharacterRemoving

CameraController.OnStart = function()
	if not isRobloxMouse then
		ContextActionService:BindAction("CameraLock", function(_, state)
			-- First person is always locked, so Shift there does nothing.
			if state == Enum.UserInputState.Begin and not isFirstPersonZoom() then
				CameraController.IsLocked = not CameraController.IsLocked
			end
			return Enum.ContextActionResult.Sink
		end, false, LOCK_KEY)
		createDot()
		UserInputService.MouseIconEnabled = false
	end

	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(sizeDot)
	-- Just after the PlayerModule's camera (bound at Camera), whose framing it lays its layers on, and before every
	-- PreRender connection, so whatever reads the view there sees it as it is drawn.
	RunService:BindToRenderStep("CameraController", Enum.RenderPriority.Camera.Value + 1, update)
end

return Ignis.Register(CameraController)
