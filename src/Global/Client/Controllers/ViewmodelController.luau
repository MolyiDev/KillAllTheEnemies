-- The gun in first person: the body's own arms and gun are hidden from this client, and a copy of the gun with two
-- arms (sleeves from the character's Shirt) is drawn in front of the camera. Gun and shoulders hang off one frame (the
-- rig) that turns to the aim, lags the look, bobs, leans and lands; the kick and the raise move the gun in the hands.
-- A picture only: shots leave from the head on the server whatever this draws.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local CameraController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.CameraController)
local gunGrips = require(script.Parent.Parent.Utils.gunGrips)
local gunSlide = require(script.Parent.Parent.Utils.gunSlide)
local GunsCore = require(ReplicatedStorage.GlobalShared.Core.GunsCore)
local TCharacterEvents = require(ReplicatedStorage.Types.Events.TCharacterEvents)
local TData = require(ReplicatedStorage.Types.TData)

-- The view this close to the camera's focus is first person.
local FIRST_PERSON_DISTANCE = 1.2
local ARM_PARTS = table.freeze({ "Right Arm", "Left Arm" })

type THoldShape = {
	Scale: number,
	Grip: Vector3,
	Right: Vector3,
	Left: Vector3,
	LeftDrop: number,
	LeftSide: number,
	LeftRoll: number,
	Cant: Vector3,
	Back: number,
	Climb: number,
}

-- Per hold: the copy's scale, where the gun's barrel line passes at its right hand's depth (Grip, off the camera:
-- under the eye and a little right, so the barrel runs along the view to just under the crosshair), where each
-- shoulder is (behind and under the camera, so an arm runs forward to its hand and its cut end never shows), the
-- gun's resting cant, and how far the kick pushes back and up. LeftDrop lowers the left hand's point and LeftSide
-- moves it left of the gun's middle, for a hand that carries the gun from under or beside it rather than closing
-- round a grip. LeftRoll turns the left arm about its own length, so a hand cupping from beside shows a corner;
-- negative rolls it inward, its top edge rising toward the gun.
local HOLDS: { [TData.TGunHold]: THoldShape } = table.freeze({
	Rifle = {
		Scale = 0.62,
		Grip = Vector3.new(0.26, -0.4, -0.63),
		Right = Vector3.new(0.2, -1.2, 0.4),
		Left = Vector3.new(-0.64, -0.8, 0.5),
		LeftDrop = 0.13,
		LeftSide = 0.06,
		LeftRoll = 0,
		Cant = Vector3.new(0.05, 0.0, 0.0),
		Back = 0.097,
		Climb = 0.05,
	},
	Pistol = {
		Scale = 0.6,
		Grip = Vector3.new(0.34, -0.6, -1.65),
		Right = Vector3.new(0.6, -0.8, 0.3),
		Left = Vector3.new(0.2, -0.9, 0.3),
		LeftDrop = 0.06,
		LeftSide = 0.2,
		LeftRoll = -0.45,
		Cant = Vector3.new(0.06, 0.05, 0.0),
		Back = 0.06,
		Climb = 0.09,
	},
	Heavy = {
		Scale = 0.62,
		Grip = Vector3.new(0.34, -0.8, -0.7),
		Right = Vector3.new(0.5, -1.2, 0.3),
		Left = Vector3.new(-0.45, -1.0, 0.4),
		LeftDrop = 0,
		LeftSide = 0.16,
		LeftRoll = 0,
		Cant = Vector3.new(0.18, 0.08, 0.0),
		Back = 0.06,
		Climb = 0.02,
	},
	Launcher = {
		Scale = 0.75,
		Grip = Vector3.new(0.4, -0.49, -1.2),
		Right = Vector3.new(0.75, -1.2, 0.4),
		Left = Vector3.new(0.1, -1.2, 0.4),
		LeftDrop = 0,
		LeftSide = 0,
		LeftRoll = 0,
		Cant = Vector3.new(0.03, 0.03, 0.0),
		Back = 0.17,
		Climb = 0.07,
	},
})

local Tune = table.freeze({
	-- An arm is one block: its hand end closes round the grip, the rest runs back to the shoulder, where its cut
	-- end is off the screen.
	ARM_WIDTH = 0.3,
	ARM_RESIZE = 0.03,
	-- The hand end sits this far past the hand point, so the grip is inside the block rather than on its face.
	ARM_REACH = 0.1,
	-- A spring stepped over more than this flies off (the first frame back from an unfocused window).
	MAX_DT = 1 / 30,
	-- Closer than CONVERGE the rig points along the view; the turn to the target comes in over the same distance
	-- again, so a body walking through it never snaps the gun.
	CONVERGE = 8,
	-- The rig turns to the aim about a point this far behind the grip (the wrists), at most this far, at this rate.
	-- Turned about the chest instead, a free cursor at the screen's edge carried the gun off the screen.
	AIM_PIVOT_BEHIND = 0.35,
	AIM_SHOULDER_SHARE = 0.3,
	AIM_YAW_MAX = math.rad(40),
	AIM_PITCH_MAX = math.rad(35),
	AIM_RATE = 16,
	RAISE_TIME = 0.3,
	RAISE_DROP = 0.55,
	RAISE_TILT = 0.5,
	RAISE_ROLL = 0.35,
	-- How far the raise carries past the hold before it settles (the easing's back term).
	RAISE_OVERSHOOT = 1.4,
	-- A bought upgrade comes up slower, from lower and the right, rolling once round its barrel; it is the first view
	-- built within FLOURISH_WINDOW of Flourish (the new Tool replicates a little after the server's word).
	FLOURISH_TIME = 0.62,
	FLOURISH_DROP = 0.85,
	FLOURISH_SIDE = 0.38,
	FLOURISH_SPIN = math.pi * 2,
	FLOURISH_WINDOW = 1,
	FLOURISH_TAKEOVER = 0.5,
	-- The look sway is a spring kicked by each frame's turn: it trails the view and swings a little past rest when
	-- the turn stops. A steady turn of 1 rad/s holds it SWAY_IMPULSE / SWAY_FREQUENCY ^ 2 off rest.
	SWAY_IMPULSE = 1.6,
	SWAY_FREQUENCY = 10,
	SWAY_DAMPING = 0.6,
	SWAY_TURN_MAX = 0.12,
	SWAY_MAX = 0.1,
	SWAY_MOVE = 0.55,
	SWAY_ROLL = 0.9,
	-- Walking leans the rig: off the way it strafes, back and down as it runs forward.
	LEAN_RATE = 7,
	LEAN_SIDE = 0.02,
	LEAN_ROLL = 0.04,
	LEAN_BACK = 0.035,
	LEAN_DROP = 0.012,
	-- BOB_STRIDE is the camera's own step rate (CameraController's ViewMotion.BobFrequency): at any other rate the
	-- gun's bob beats against the view's and the hands shake.
	BOB_SIDE = 0.012,
	BOB_LIFT = 0.012,
	BOB_ROLL = 0.008,
	BOB_YAW = 0.004,
	BOB_STRIDE = 0.4,
	BOB_FULL_SPEED = 16,
	BOB_RATE = 8,
	-- Two rates that never line up, so the idle hold drifts in a loop instead of pumping up and down.
	BREATH_LIFT = 0.006,
	BREATH_SIDE = 0.004,
	BREATH_ROLL = 0.008,
	BREATH_RATE = 1.6,
	BREATH_SIDE_RATIO = 0.63,
	KICK_IMPULSE = 40,
	KICK_STIFFNESS = 320,
	KICK_DAMPING = 26,
	KICK_ROLL = 0.05,
	KICK_YAW = 0.03,
	-- Share of the kick's push back that also lifts the gun.
	KICK_LIFT = 0.4,
	KICK_TWIST_RATE = 10,
	LAND_DROP = 0.06,
	LAND_STIFFNESS = 140,
	LAND_DAMPING = 14,
	LAND_FALL_MAX = 60,
	-- Leaving the floor upward dips the gun (the view rises, the gun trails it); in the air it floats against the
	-- fall; the dip and the float tip the muzzle with them.
	-- Slower than JUMP_MIN_SPEED upward it is a step or a bump under the feet, not a jump.
	JUMP_DROP = 1.2,
	JUMP_MIN_SPEED = 20,
	AIR_FLOAT = 0.0015,
	AIR_FLOAT_MAX = 0.05,
	AIR_RATE = 6,
	LAND_PITCH = 0.8,
})

type TView = {
	Tool: Tool,
	Model: Model,
	Parts: { BasePart },
	Offsets: { CFrame },
	-- Parts from this index on are the slide's (past the last when the gun has none), and how far it runs back.
	SlideFrom: number,
	SlideTravel: number,
	Muzzle: Attachment?,
	Hold: THoldShape,
	-- Where each hand closes, in the Handle's space, and the Handle off the point the hold's Grip places: on the
	-- barrel's axis (TGun.Barrel) at the right hand's depth. So every gun sits at the same depth by its own grip,
	-- and its barrel on the same line whatever hangs under it or stands on top.
	Mount: CFrame,
	-- The hold's cant and the left arm's roll as rotations, and the point the rig turns to the aim about.
	Cant: CFrame,
	LeftRoll: CFrame,
	Pivot: Vector3,
	RightHand: Vector3,
	LeftHand: Vector3,
	RightLength: number,
	LeftLength: number,
	RightArm: BasePart?,
	LeftArm: BasePart?,
}

local ViewmodelController = {}

-- Where the gun points (WeaponController sets it every frame it is armed).
ViewmodelController.Target = nil :: Vector3?
-- Drawn this frame: the body's arms and gun are hidden and the copy is shown.
ViewmodelController.IsActive = false

local SWAY_STIFFNESS = Tune.SWAY_FREQUENCY * Tune.SWAY_FREQUENCY
local SWAY_DRAG = 2 * Tune.SWAY_DAMPING * Tune.SWAY_FREQUENCY

local random = Random.new()
local view: TView? = nil
local hiddenTool: Tool? = nil
local selfCharacter: Model? = nil
local selfHumanoid: Humanoid? = nil
local selfRoot: BasePart? = nil
local raise = 1
-- os.clock of the last Flourish, and whether the view on screen is coming up with one.
local flourishAt = -math.huge
local isFlourishing = false
-- Yaw and pitch, radians: the rig's turn to the aim, and the look sway's spring.
local aim = Vector2.zero
local sway, swayVelocity = Vector2.zero, Vector2.zero
-- Strafe and forward speed as shares of full speed, eased.
local lean = Vector2.zero
local stride, bobAmount = 0, 0
local kick, kickVelocity = 0, 0
-- A shot's own yaw and roll, picked per shot and let go.
local twist = Vector2.zero
local slideAt = -math.huge
local land, landVelocity = 0, 0
local isAirborne = false
local fallSpeed, float = 0, 0
local lastCamera: CFrame? = nil
-- BulkMoveTo's lists, sized once per view and rewritten in place every frame.
local movedParts: { BasePart } = {}
local movedFrames: { CFrame } = {}

function ViewmodelController.Kick(scale: number)
	kickVelocity += Tune.KICK_IMPULSE * scale
	slideAt = os.clock()
	twist = Vector2.new(random:NextNumber(-1, 1) * Tune.KICK_YAW, random:NextNumber(-1, 1) * Tune.KICK_ROLL) * scale
end

-- The next gun drawn comes up with the upgrade's flourish rather than the plain raise. The new Tool and the server's
-- word arrive in either order, so a view still in its first moments of raising takes it over from the start.
function ViewmodelController.Flourish()
	if view and raise < Tune.FLOURISH_TAKEOVER then
		raise = 0
		isFlourishing = true
		return
	end

	flourishAt = os.clock()
end

-- The copy's muzzle while it is drawn, for tracers that leave the gun the player sees.
function ViewmodelController.GetMuzzle(): Attachment?
	local current = view
	return if ViewmodelController.IsActive and current then current.Muzzle else nil
end

local function quiet(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
end

local function strip(root: Instance)
	for _, item in root:GetDescendants() do
		if item:IsA("JointInstance") or item:IsA("WeldConstraint") or item:IsA("Sound") then item:Destroy() end
	end
end

local function buildArm(character: Model, name: string, length: number, parent: Model): BasePart?
	local source = character:FindFirstChild(name)
	if not source or not source:IsA("BasePart") then return nil end
	local arm = source:Clone()
	strip(arm)
	quiet(arm)
	for _, item in arm:GetChildren() do
		if item:IsA("Attachment") then item:Destroy() end
	end

	arm.Size = Vector3.new(Tune.ARM_WIDTH, length, Tune.ARM_WIDTH)
	arm.LocalTransparencyModifier = 0
	arm.Parent = parent
	return arm
end

local function build(character: Model, tool: Tool): TView?
	local handle = tool:FindFirstChild("Handle")
	local gun = GunsCore.FromToolName(tool.Name)
	if not handle or not handle:IsA("BasePart") or not gun then return nil end

	local hold = HOLDS[gun.Hold]
	local model = Instance.new("Model")
	model.Name = "Viewmodel"
	local copy = tool:Clone()
	strip(copy)
	for _, child in copy:GetChildren() do
		child.Parent = model
	end

	copy:Destroy()
	local copyHandle = model:FindFirstChild("Handle") :: BasePart
	model.PrimaryPart = copyHandle
	model:ScaleTo(hold.Scale)

	-- The slide's parts go last, so placing them is one more loop rather than a test per part.
	local slide = model:FindFirstChild("Slide", true)
	local slideBody = if slide and slide:IsA("Model") then slide.PrimaryPart else nil
	local parts, slideParts = {}, {}
	for _, part in model:GetDescendants() do
		if not part:IsA("BasePart") then continue end
		quiet(part)
		if slideBody and part:IsDescendantOf(slide) then
			slideParts[#slideParts + 1] = part
		else
			parts[#parts + 1] = part
		end
	end

	local slideFrom = #parts + 1
	table.move(slideParts, 1, #slideParts, slideFrom, parts)

	local offsets = table.create(#parts)
	for index, part in parts do
		offsets[index] = copyHandle.CFrame:ToObjectSpace(part.CFrame)
	end

	-- Measured before the arms and the Humanoid go in, so the box is the gun's alone.
	local grips = gunGrips(gun, copyHandle, model)

	-- A Humanoid so the cloned Shirt dresses the arms.
	local humanoid = Instance.new("Humanoid")
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.RequiresNeck = false
	humanoid.Parent = model
	for _, className in { "Shirt", "BodyColors" } do
		local found = character:FindFirstChildOfClass(className)
		if found then found:Clone().Parent = model end
	end

	local muzzle = copyHandle:FindFirstChild("Muzzle") :: Attachment?
	local rightHand = grips.Right
	local leftHand = grips.Left - Vector3.new(hold.LeftSide, hold.LeftDrop, 0)
	local cant = CFrame.Angles(hold.Cant.X, hold.Cant.Y, hold.Cant.Z)
	local rest = CFrame.new(hold.Grip) * cant
	local anchor = grips.Barrel
	local rightLength = (hold.Right - rest * (rightHand - anchor)).Magnitude + Tune.ARM_REACH
	local leftLength = (hold.Left - rest * (leftHand - anchor)).Magnitude + Tune.ARM_REACH
	local rightArm = buildArm(character, "Right Arm", rightLength, model)
	local leftArm = buildArm(character, "Left Arm", leftLength, model)
	model.Parent = Workspace.CurrentCamera

	table.clear(movedParts)
	table.clear(movedFrames)
	for index, part in parts do
		movedParts[index] = part
		movedFrames[index] = CFrame.identity
	end

	if rightArm then
		movedParts[#movedParts + 1] = rightArm
		movedFrames[#movedFrames + 1] = CFrame.identity
	end

	if leftArm then
		movedParts[#movedParts + 1] = leftArm
		movedFrames[#movedFrames + 1] = CFrame.identity
	end

	return {
		Tool = tool,
		Model = model,
		Parts = parts,
		Offsets = offsets,
		SlideFrom = slideFrom,
		SlideTravel = if slideBody then gunSlide.Travel(slideBody) else 0,
		Muzzle = muzzle,
		Hold = hold,
		Mount = CFrame.new(-anchor),
		Cant = cant,
		LeftRoll = CFrame.Angles(0, hold.LeftRoll, 0),
		Pivot = hold.Grip + Vector3.zAxis * Tune.AIM_PIVOT_BEHIND,
		RightHand = rightHand,
		LeftHand = leftHand,
		RightLength = rightLength,
		LeftLength = leftLength,
		RightArm = rightArm,
		LeftArm = leftArm,
	}
end

local function setHidden(character: Model, tool: Tool?, amount: number)
	for _, name in ARM_PARTS do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then part.LocalTransparencyModifier = amount end
	end

	if not tool then return end
	for _, part in tool:GetDescendants() do
		if part:IsA("BasePart") then part.LocalTransparencyModifier = amount end
	end
end

local function release()
	local tool = hiddenTool
	if tool and tool.Parent then setHidden(tool.Parent :: Model, tool, 0) end
	hiddenTool = nil
	local current = view
	view = nil
	if current then current.Model:Destroy() end
end

-- An arm's block: its hand end round `hand`, the rest running back to `shoulder`, its faces square to `frame` and
-- then turned by `roll` about its length. It is resized only when the span has changed by ARM_RESIZE (a turn to the
-- aim, a kick), never every frame. Returns its frame and the length it now has.
local function armFrame(
	arm: BasePart,
	hand: Vector3,
	shoulder: Vector3,
	length: number,
	frame: CFrame,
	roll: CFrame
): (CFrame, number)
	local along = shoulder - hand
	local span = along.Magnitude
	local up = if span > 1e-3 then along / span else frame.UpVector
	local wanted = span + Tune.ARM_REACH
	if math.abs(wanted - length) > Tune.ARM_RESIZE then
		length = wanted
		arm.Size = Vector3.new(Tune.ARM_WIDTH, length, Tune.ARM_WIDTH)
	end

	local flat = frame.RightVector - up * up:Dot(frame.RightVector)
	local side = if flat.Magnitude > 1e-3 then flat.Unit else frame.UpVector
	return CFrame.fromMatrix(hand + up * (length / 2 - Tune.ARM_REACH), side, up) * roll, length
end

-- The look sway: each frame's turn kicks the spring, which trails the view and swings back past rest. `aimed` is the
-- view before its bob, recoil and shake: fed those, the spring rattles the gun against every step and shot.
local function stepSway(aimed: CFrame, dt: number)
	local last = lastCamera
	lastCamera = aimed
	if last then
		local pitch, yaw = last.Rotation:ToObjectSpace(aimed.Rotation):ToEulerAnglesYXZ()
		local max = Tune.SWAY_TURN_MAX
		swayVelocity += Vector2.new(math.clamp(-yaw, -max, max), math.clamp(-pitch, -max, max)) * Tune.SWAY_IMPULSE
	end

	swayVelocity += (sway * -SWAY_STIFFNESS - swayVelocity * SWAY_DRAG) * dt
	sway += swayVelocity * dt
end

-- The walk: the bob's stride and strength, and the lean off the body's speed in the view's own axes.
local function stepWalk(base: CFrame, velocity: Vector3, isGrounded: boolean, dt: number)
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	local speed = flat.Magnitude
	local wanted = if isGrounded then math.clamp(speed / Tune.BOB_FULL_SPEED, 0, 1) else 0
	bobAmount += (wanted - bobAmount) * (1 - math.exp(-Tune.BOB_RATE * dt))
	stride += dt * speed * Tune.BOB_STRIDE

	-- A shove (a blast, a knockback) is faster than any walk: the lean stops at a full walk's.
	local moved = base:VectorToObjectSpace(flat) / math.max(speed, Tune.BOB_FULL_SPEED)
	lean = lean:Lerp(Vector2.new(moved.X, -moved.Z), 1 - math.exp(-Tune.LEAN_RATE * dt))
end

-- Leaving the floor and coming back to it kick one spring; between them the gun floats against the fall. The fall's
-- speed is kept from the air: by the frame the floor is under the feet again it is already zero.
local function stepLand(velocity: Vector3, isGrounded: boolean, dt: number)
	if isGrounded and isAirborne then
		landVelocity -= fallSpeed * Tune.LAND_DROP
		fallSpeed = 0
	elseif not isGrounded and not isAirborne and velocity.Y > Tune.JUMP_MIN_SPEED then
		landVelocity -= Tune.JUMP_DROP
	end

	isAirborne = not isGrounded
	if isAirborne then fallSpeed = math.clamp(-velocity.Y, fallSpeed, Tune.LAND_FALL_MAX) end
	landVelocity += (-land * Tune.LAND_STIFFNESS - landVelocity * Tune.LAND_DAMPING) * dt
	land += landVelocity * dt

	local wanted = if isAirborne
		then math.clamp(-velocity.Y * Tune.AIR_FLOAT, -Tune.AIR_FLOAT_MAX, Tune.AIR_FLOAT_MAX)
		else 0
	float += (wanted - float) * (1 - math.exp(-Tune.AIR_RATE * dt))
end

-- The rig's turn to the target, as yaw and pitch off the view: none up close, where the gun would cross the screen.
local function stepAim(base: CFrame, grip: Vector3, dt: number)
	local wanted = Vector2.zero
	local target = ViewmodelController.Target
	if target then
		local toTarget = base:PointToObjectSpace(target) - grip
		local distance = toTarget.Magnitude
		local share = math.clamp(distance / Tune.CONVERGE - 1, 0, 1)
		if share > 0 then
			local yaw = math.atan2(-toTarget.X, -toTarget.Z)
			local pitch = math.asin(toTarget.Y / distance)
			wanted = Vector2.new(
				math.clamp(yaw, -Tune.AIM_YAW_MAX, Tune.AIM_YAW_MAX),
				math.clamp(pitch, -Tune.AIM_PITCH_MAX, Tune.AIM_PITCH_MAX)
			) * share
		end
	end

	aim = aim:Lerp(wanted, 1 - math.exp(-Tune.AIM_RATE * dt))
end

local function place(current: TView, camera: Camera, root: BasePart, humanoid: Humanoid, frameDt: number)
	local dt = math.min(frameDt, Tune.MAX_DT)
	local base = camera.CFrame
	local hold = current.Hold
	local now = os.clock()
	local velocity = root.AssemblyLinearVelocity
	local isGrounded = humanoid.FloorMaterial ~= Enum.Material.Air

	stepSway(CameraController.AimCFrame, dt)
	stepWalk(base, velocity, isGrounded, dt)
	stepLand(velocity, isGrounded, dt)
	stepAim(base, hold.Grip, dt)
	kickVelocity += (-kick * Tune.KICK_STIFFNESS - kickVelocity * Tune.KICK_DAMPING) * dt
	kick += kickVelocity * dt
	twist *= math.exp(-Tune.KICK_TWIST_RATE * dt)
	raise = math.min(1, raise + dt / (if isFlourishing then Tune.FLOURISH_TIME else Tune.RAISE_TIME))

	-- The rig: the view, shifted by what the body does, then turned about the wrists. The gun takes the whole turn
	-- to the aim; the shoulders are the body's, so they take a share of it and the arms swing after the gun
	-- without sweeping across the screen.
	local swayX = math.clamp(sway.X, -Tune.SWAY_MAX, Tune.SWAY_MAX)
	local swayY = math.clamp(sway.Y, -Tune.SWAY_MAX, Tune.SWAY_MAX)
	local step = math.sin(stride) * bobAmount
	local breath = now * Tune.BREATH_RATE
	local drift = math.sin(breath * Tune.BREATH_SIDE_RATIO) * (1 - bobAmount)
	local heave = land + float
	local offset = Vector3.new(
		step * Tune.BOB_SIDE + drift * Tune.BREATH_SIDE + swayX * Tune.SWAY_MOVE - lean.X * Tune.LEAN_SIDE,
		math.sin(stride * 2) * Tune.BOB_LIFT * bobAmount
			+ math.sin(breath) * Tune.BREATH_LIFT
			+ swayY * Tune.SWAY_MOVE
			- math.abs(lean.Y) * Tune.LEAN_DROP
			+ heave,
		lean.Y * Tune.LEAN_BACK
	)
	local pivot = current.Pivot
	local pitch = swayY + heave * Tune.LAND_PITCH
	local yaw = swayX + step * Tune.BOB_YAW
	local roll = step * Tune.BOB_ROLL + drift * Tune.BREATH_ROLL + lean.X * Tune.LEAN_ROLL - swayX * Tune.SWAY_ROLL
	local carried = base * CFrame.new(offset) * CFrame.new(pivot)
	local unpivot = CFrame.new(-pivot)
	local rig = carried * CFrame.fromEulerAnglesYXZ(pitch + aim.Y, yaw + aim.X, roll) * unpivot
	local shoulders = carried
		* CFrame.fromEulerAnglesYXZ(
			pitch + aim.Y * Tune.AIM_SHOULDER_SHARE,
			yaw + aim.X * Tune.AIM_SHOULDER_SHARE,
			roll
		)
		* unpivot

	-- The gun in the hands: the raise brings it up from below (a plain one carries a little past the hold and
	-- settles), the kick shoves it back and tips it up about the grip.
	local back = 1 - raise
	local left = if isFlourishing
		then back ^ 3
		else (Tune.RAISE_OVERSHOOT + 1) * back ^ 3 - Tune.RAISE_OVERSHOOT * back ^ 2
	local drop = if isFlourishing then Tune.FLOURISH_DROP else Tune.RAISE_DROP
	local side = if isFlourishing then left * Tune.FLOURISH_SIDE else 0
	local spin = if isFlourishing then left * Tune.FLOURISH_SPIN else left * Tune.RAISE_ROLL
	local shove = kick * hold.Back
	local handle = rig
		* CFrame.new(hold.Grip + Vector3.new(side, shove * Tune.KICK_LIFT - left * drop, shove))
		* current.Cant
		* CFrame.Angles(kick * hold.Climb - left * Tune.RAISE_TILT, twist.X, twist.Y + spin)
		* current.Mount

	local offsets = current.Offsets
	local count = #offsets
	local slideFrom = current.SlideFrom
	for index = 1, slideFrom - 1 do
		movedFrames[index] = handle * offsets[index]
	end

	-- The Handle looks out of the barrel, so back is its +Z.
	local slideHandle = handle * CFrame.new(0, 0, current.SlideTravel * gunSlide.Offset(now - slideAt))
	for index = slideFrom, count do
		movedFrames[index] = slideHandle * offsets[index]
	end

	-- The hands are on the gun and the shoulders are not, so a kick slides the arms back under the view instead of
	-- turning them.
	local rightArm = current.RightArm
	if rightArm then
		count += 1
		movedFrames[count], current.RightLength = armFrame(
			rightArm,
			handle * current.RightHand,
			shoulders * hold.Right,
			current.RightLength,
			handle,
			CFrame.identity
		)
	end

	local leftArm = current.LeftArm
	if leftArm then
		count += 1
		movedFrames[count], current.LeftLength = armFrame(
			leftArm,
			handle * current.LeftHand,
			shoulders * hold.Left,
			current.LeftLength,
			handle,
			current.LeftRoll
		)
	end

	Workspace:BulkMoveTo(movedParts, movedFrames, Enum.BulkMoveMode.FireCFrameChanged)
end

local function step(dt: number)
	local camera = Workspace.CurrentCamera
	local character = selfCharacter
	local humanoid = selfHumanoid
	local root = selfRoot
	if not character or not humanoid then
		ViewmodelController.IsActive = false
		release()
		return
	end

	-- The view before recoil and shake, to the focus, which no pose moves. To the head, a heavy shot's jolt tipped it
	-- back out of first person for a frame, and the gun was built and raised again on every shot.
	local fromFocus = CameraController.AimCFrame.Position - camera.Focus.Position
	local isFirstPerson = fromFocus.Magnitude < FIRST_PERSON_DISTANCE
	local tool = character:FindFirstChildOfClass("Tool")
	local isArmed = tool ~= nil and tool:FindFirstChild("Handle") ~= nil and humanoid.Health > 0
	ViewmodelController.IsActive = isFirstPerson and isArmed
	if not ViewmodelController.IsActive then
		if hiddenTool or view then release() end
		lastCamera = nil
		return
	end

	-- Hidden once a view, not every frame: nothing else writes the gun's parts (the camera's own fade leaves Tools
	-- alone), and the arms are hidden by it in first person anyway.
	local held = tool :: Tool
	if not view or view.Tool ~= held or not view.Model.Parent then
		release()
		view = build(character, held)
		raise, kick, kickVelocity = 0, 0, 0
		isFlourishing = os.clock() - flourishAt < Tune.FLOURISH_WINDOW
		flourishAt = -math.huge
		hiddenTool = held
		setHidden(character, held, 1)
	end

	local current = view
	if current and root then place(current, camera, root, humanoid, dt) end
end

ViewmodelController.OnSelfCharacterAdded = function(character)
	selfCharacter = character
	selfHumanoid = character.Humanoid
	selfRoot = character.HumanoidRootPart
end :: TCharacterEvents.OnCharacterAdded

ViewmodelController.OnSelfCharacterRemoving = function()
	selfCharacter = nil
	selfHumanoid = nil
	selfRoot = nil
	ViewmodelController.IsActive = false
	release()
end :: TCharacterEvents.OnCharacterRemoving

ViewmodelController.OnStart = function()
	-- After CameraController, which is bound to the render step and so runs before every PreRender: the gun rides
	-- the view as shown, shake and recoil included.
	RunService.PreRender:Connect(step)
end

return Ignis.Register(ViewmodelController)
