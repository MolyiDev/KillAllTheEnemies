-- The gun in first person: the body's own arms and gun are hidden from this client, and a copy of the gun with two
-- arms (sleeves from the character's Shirt) is drawn in front of the camera, with sway, a walking bob, a landing
-- dip and a kick per shot. A picture only: shots leave from the head on the server whatever this draws.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local gunSlide = require(script.Parent.Parent.Utils.gunSlide)
local GunsCore = require(ReplicatedStorage.GlobalShared.Core.GunsCore)
local TCharacterEvents = require(ReplicatedStorage.Types.Events.TCharacterEvents)
local TData = require(ReplicatedStorage.Types.TData)

-- The camera this close to the head is first person.
local FIRST_PERSON_DISTANCE = 1.2
local ARM_PARTS = table.freeze({ "Right Arm", "Left Arm" })

type THoldShape = {
	Scale: number,
	Grip: Vector3,
	Fore: number,
	Under: number,
	Right: Vector3,
	Left: Vector3,
	Cant: Vector3,
	Back: number,
	Climb: number,
}

-- Per hold: the copy's scale, where the grip sits off the camera, the left hand along the barrel (share of its
-- length) and under it, where each shoulder is, the gun's resting cant, and how far the kick pushes back and up.
local HOLDS: { [TData.TGunHold]: THoldShape } = table.freeze({
	Rifle = {
		Scale = 0.42,
		Grip = Vector3.new(0.32, -0.37, -0.95),
		Fore = 0.5,
		Under = 0.1,
		Right = Vector3.new(0.75, -1.15, -0.45),
		Left = Vector3.new(-0.42, -1.2, -0.65),
		Cant = Vector3.new(0.02, 0.06, -0.05),
		Back = 0.07,
		Climb = 0.05,
	},
	Pistol = {
		Scale = 0.4,
		Grip = Vector3.new(0.3, -0.4, -1.15),
		Fore = 0,
		Under = 0.04,
		Right = Vector3.new(0.62, -1.25, -0.5),
		Left = Vector3.new(0.12, -1.3, -0.55),
		Cant = Vector3.new(0.02, 0.24, -0.1),
		Back = 0.06,
		Climb = 0.09,
	},
	Heavy = {
		Scale = 0.36,
		Grip = Vector3.new(0.28, -0.46, -0.9),
		Fore = 0.38,
		Under = -0.14,
		Right = Vector3.new(0.6, -1.2, -0.45),
		Left = Vector3.new(-0.3, -1.2, -0.6),
		Cant = Vector3.new(0.05, 0.08, -0.03),
		Back = 0.035,
		Climb = 0.02,
	},
	Launcher = {
		Scale = 0.36,
		Grip = Vector3.new(0.36, -0.22, -0.7),
		Fore = 0.32,
		Under = 0.12,
		Right = Vector3.new(0.65, -1.1, -0.35),
		Left = Vector3.new(-0.3, -1.15, -0.55),
		Cant = Vector3.new(0, 0.04, -0.02),
		Back = 0.1,
		Climb = 0.07,
	},
})

local Tune = table.freeze({
	ARM_WIDTH = 0.44,
	ARM_SCALE = 0.55,
	-- The arm runs this far past the shoulder point, so its top never shows as a cut end.
	ARM_EXTRA = 0.25,
	-- Closer than this, the gun points along the view instead of at the target.
	CONVERGE = 8,
	RAISE_TIME = 0.3,
	RAISE_DROP = 0.55,
	RAISE_TILT = 0.5,
	-- A bought upgrade comes up slower, from lower and the right, rolling once round its barrel; it is the first view
	-- built within FLOURISH_WINDOW of Flourish (the new Tool replicates a little after the server's word).
	FLOURISH_TIME = 0.62,
	FLOURISH_DROP = 0.85,
	FLOURISH_SIDE = 0.38,
	FLOURISH_SPIN = math.pi * 2,
	FLOURISH_WINDOW = 1,
	FLOURISH_TAKEOVER = 0.5,
	SWAY_GAIN = 0.016,
	SWAY_MAX = 0.1,
	SWAY_RATE = 9,
	SWAY_MOVE = 0.55,
	BOB_SIDE = 0.022,
	BOB_LIFT = 0.028,
	BOB_ROLL = 0.02,
	BOB_STRIDE = 0.85,
	BOB_FULL_SPEED = 16,
	BREATH_LIFT = 0.006,
	BREATH_RATE = 1.6,
	KICK_IMPULSE = 40,
	KICK_STIFFNESS = 320,
	KICK_DAMPING = 26,
	KICK_ROLL = 0.05,
	LAND_DROP = 0.06,
	LAND_STIFFNESS = 140,
	LAND_DAMPING = 14,
	LAND_AIR = 0.03,
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
	Length: number,
	Hold: THoldShape,
	RightArm: BasePart?,
	LeftArm: BasePart?,
}

local ViewmodelController = {}

-- Where the gun points (WeaponController sets it every frame it is armed).
ViewmodelController.Target = nil :: Vector3?
-- Drawn this frame: the body's arms and gun are hidden and the copy is shown.
ViewmodelController.IsActive = false

local random = Random.new()
local view: TView? = nil
local hiddenTool: Tool? = nil
local selfCharacter: Model? = nil
local selfHead: BasePart? = nil
local selfHumanoid: Humanoid? = nil
local selfRoot: BasePart? = nil
local raise = 1
-- os.clock of the last Flourish, and whether the view on screen is coming up with one.
local flourishAt = -math.huge
local isFlourishing = false
local sway = Vector2.zero
local stride = 0
local kick, kickVelocity, roll = 0, 0, 0
local slideAt = -math.huge
local land, landVelocity = 0, 0
local isAirborne = false
local lastCamera: CFrame? = nil
-- BulkMoveTo's lists, sized once per view and rewritten in place every frame.
local movedParts: { BasePart } = {}
local movedFrames: { CFrame } = {}

function ViewmodelController.Kick(scale: number)
	kickVelocity += Tune.KICK_IMPULSE * scale
	slideAt = os.clock()
	roll = (random:NextNumber() * 2 - 1) * Tune.KICK_ROLL * scale
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

local function buildArm(character: Model, name: string, parent: Model): BasePart?
	local source = character:FindFirstChild(name)
	if not source or not source:IsA("BasePart") then return nil end
	local arm = source:Clone()
	strip(arm)
	quiet(arm)
	for _, item in arm:GetChildren() do
		if item:IsA("Attachment") then item:Destroy() end
	end

	arm.Size = Vector3.new(Tune.ARM_WIDTH, source.Size.Y, Tune.ARM_WIDTH) * Tune.ARM_SCALE
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

	local rightArm = buildArm(character, "Right Arm", model)
	local leftArm = buildArm(character, "Left Arm", model)
	model.Parent = Workspace.CurrentCamera

	local muzzle = copyHandle:FindFirstChild("Muzzle") :: Attachment?
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
		Length = if muzzle then math.max(-muzzle.Position.Z, 0.4) else 1,
		Hold = hold,
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

-- An arm from the hand to the shoulder, stretched to reach.
local function armFrame(arm: BasePart, hand: Vector3, shoulder: Vector3, base: CFrame): CFrame
	local along = shoulder - hand
	local up = if along.Magnitude > 1e-3 then along.Unit else base.UpVector
	local length = along.Magnitude + Tune.ARM_EXTRA
	if math.abs(arm.Size.Y - length) > 0.02 then arm.Size = Vector3.new(arm.Size.X, length, arm.Size.Z) end
	local flat = base.RightVector - up * up:Dot(base.RightVector)
	local side = if flat.Magnitude > 1e-3 then flat.Unit else base.RightVector
	return CFrame.fromMatrix(hand + up * length / 2, side, up)
end

local function place(current: TView, camera: Camera, root: BasePart, humanoid: Humanoid, dt: number)
	local base = camera.CFrame
	local hold = current.Hold
	local now = os.clock()

	if lastCamera then
		local pitch, yaw = lastCamera.Rotation:ToObjectSpace(base.Rotation):ToEulerAnglesYXZ()
		local wanted = Vector2.new(-yaw, -pitch) / math.max(dt, 1 / 240) * Tune.SWAY_GAIN
		local clamped = Vector2.new(
			math.clamp(wanted.X, -Tune.SWAY_MAX, Tune.SWAY_MAX),
			math.clamp(wanted.Y, -Tune.SWAY_MAX, Tune.SWAY_MAX)
		)
		sway = sway:Lerp(clamped, 1 - math.exp(-Tune.SWAY_RATE * dt))
	end

	lastCamera = base

	local velocity = root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local isGrounded = humanoid.FloorMaterial ~= Enum.Material.Air
	local amount = if isGrounded then math.clamp(speed / Tune.BOB_FULL_SPEED, 0, 1) else 0
	stride += dt * speed * Tune.BOB_STRIDE
	local bob = Vector3.new(
		math.sin(stride) * Tune.BOB_SIDE * amount,
		-math.abs(math.cos(stride)) * Tune.BOB_LIFT * amount + math.sin(now * Tune.BREATH_RATE) * Tune.BREATH_LIFT,
		0
	)

	if isAirborne and isGrounded then
		landVelocity -= math.clamp(-velocity.Y, 0, 60) * Tune.LAND_DROP
	end
	isAirborne = not isGrounded
	landVelocity += (-land * Tune.LAND_STIFFNESS - landVelocity * Tune.LAND_DAMPING) * dt
	land += landVelocity * dt
	kickVelocity += (-kick * Tune.KICK_STIFFNESS - kickVelocity * Tune.KICK_DAMPING) * dt
	kick += kickVelocity * dt
	roll += (0 - roll) * math.min(1, dt * 10)
	raise = math.min(1, raise + dt / (if isFlourishing then Tune.FLOURISH_TIME else Tune.RAISE_TIME))

	local eased = 1 - (1 - raise) ^ 3
	local left = 1 - eased
	local drop = if isFlourishing then Tune.FLOURISH_DROP else Tune.RAISE_DROP
	local side = if isFlourishing then left * Tune.FLOURISH_SIDE else 0
	local spin = if isFlourishing then left * Tune.FLOURISH_SPIN else 0
	local offset = hold.Grip
		+ bob
		+ Vector3.new(sway.X * Tune.SWAY_MOVE, sway.Y * Tune.SWAY_MOVE, 0)
		+ Vector3.new(side, -left * drop + land + (if isAirborne then Tune.LAND_AIR else 0), kick * hold.Back)
	local grip = base * CFrame.new(offset)
	local target = ViewmodelController.Target
	local aimed = base.Rotation
	if target and (target - base.Position).Magnitude > Tune.CONVERGE then
		aimed = CFrame.lookAt(grip.Position, target, base.UpVector).Rotation
	end

	local handle = CFrame.new(grip.Position)
		* aimed
		* CFrame.Angles(hold.Cant.X, hold.Cant.Y, hold.Cant.Z)
		* CFrame.Angles(
			kick * hold.Climb - left * Tune.RAISE_TILT + sway.Y,
			sway.X,
			roll + spin + math.sin(stride) * Tune.BOB_ROLL * amount
		)

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

	local rightArm = current.RightArm
	if rightArm then
		count += 1
		movedFrames[count] = armFrame(rightArm, handle.Position, base * hold.Right, base)
	end

	local leftArm = current.LeftArm
	if leftArm then
		count += 1
		local fore = handle * Vector3.new(0, -hold.Under, -current.Length * hold.Fore)
		movedFrames[count] = armFrame(leftArm, fore, base * hold.Left, base)
	end

	Workspace:BulkMoveTo(movedParts, movedFrames, Enum.BulkMoveMode.FireCFrameChanged)
end

local function step(dt: number)
	local camera = Workspace.CurrentCamera
	local character = selfCharacter
	local head = selfHead
	local humanoid = selfHumanoid
	local root = selfRoot
	if not character or not head or not humanoid then
		ViewmodelController.IsActive = false
		release()
		return
	end

	local isFirstPerson = (camera.CFrame.Position - head.Position).Magnitude < FIRST_PERSON_DISTANCE
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
	selfHead = character.Head
	selfHumanoid = character.Humanoid
	selfRoot = character.HumanoidRootPart
end :: TCharacterEvents.OnCharacterAdded

ViewmodelController.OnSelfCharacterRemoving = function()
	selfCharacter = nil
	selfHead = nil
	selfHumanoid = nil
	selfRoot = nil
	ViewmodelController.IsActive = false
	release()
end :: TCharacterEvents.OnCharacterRemoving

ViewmodelController.OnStart = function()
	-- After CameraController's PreRender (the global controllers start first), so the gun rides the view as shown,
	-- shake and recoil included.
	RunService.PreRender:Connect(step)
end

return Ignis.Register(ViewmodelController)
