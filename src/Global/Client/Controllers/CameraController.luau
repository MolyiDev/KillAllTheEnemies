-- The local camera on top of the PlayerModule: the mouse lock (Left Shift, and always in first person), the dot drawn
-- in place of the mouse pointer, and cosmetic layers (shake, recoil, first-person motion) laid on whatever it framed
-- this frame.
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
	local shouldLockMouse = (CameraController.IsLocked or isFirstPerson) and not CameraController.IsMouseFreed
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

	local isFirstPerson = isFirstPersonZoom()
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
	if lockBlend > 1e-3 or headAlpha < 1 then
		aimCFrame *= CFrame.new(Tune.FIRST_PERSON_OFFSET:Lerp(Tune.SHOULDER_OFFSET * lockBlend, headAlpha))
	end
	CameraController.AimCFrame = aimCFrame
	faceAim(aimCFrame.LookVector)

	local render = aimCFrame
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
