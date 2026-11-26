-- Where the results are shown: the elevator in the lobby's map (Workspace.Lobby.Map.ResultsElevator, far from the
-- plaza), its car going down a shaft that never ends. The car stands still; on this client only, the shaft is lifted
-- and wrapped every SHAFT_PERIOD studs so its landings and red lights keep sweeping past, the hoist turns, the arrow and
-- the warning lights pulse, the panel's buttons run and the lamps flicker. Everything moved is put back by End.
--
-- The camera is taken while it shows (written after CameraController, which only lays offsets on what it finds) and
-- dollies in; the squad drop onto their spots one by one, each landing a bump of the camera, and every frame each head
-- is projected to the screen for its tag (TMember.HeadAt).
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local InertialBlend = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Utils.inertialBlend)
local avatarClips = require(script.Parent.Parent.Parent.Utils.avatarClips)
local Types = require(script.Parent.Types)

local LocalPlayer = Players.LocalPlayer

local Tune = table.freeze({
	-- The shaft's travel: how fast it goes by and the length of one of its repeats (studs).
	SHAFT_SPEED = 14,
	SHAFT_PERIOD = 48,
	-- The camera, in the elevator's Origin frame: where it rests and looks (off to the right of the dais, so the squad
	-- stands left of the match stats), where its dolly starts and how long it takes.
	EYE = Vector3.new(2, 5.6, 17),
	TARGET = Vector3.new(2, 4.4, 0),
	EYE_FROM = Vector3.new(4, 8.8, 25),
	DOLLY = 1.3,
	FOV = 70,
	-- The car shakes a little as it goes down (studs, how fast), and a landing kicks it.
	RUMBLE = 0.035,
	RUMBLE_SPEED = 9,
	LAND_KICK = 0.22,
	MVP_KICK = 0.45,
	KICK_DECAY = 0.12,
	-- A body falls this far onto its spot, in this long.
	DROP_STUDS = 9,
	DROP = 0.42,
	-- The tag floats this far over the top of the head (studs).
	TAG_OVER = 0.7,
	-- How far a squad member's head stands over their feet before their avatar has loaded (studs).
	DEFAULT_HEAD = 5.2,
	CHEER_DELAY = 0.3,
	-- The cheer is blended in from the idle and out of its last frame back into it over this long (inertialBlend).
	CHEER_BLEND = 0.3,
	-- The car's moving parts: the hoist turns as fast as the cables run (RADIUS), the arrow's neon and the shaft's warning
	-- lights pulse (LOW is how far they dim), the panel's buttons light one after another, now and then a lamp dips.
	RADIUS = 3,
	ARROW_RATE = 1.4,
	ARROW_LOW = 0.8,
	BEACON_RATE = 1.1,
	BEACON_LOW = 0.6,
	PANEL_RATE = 2.5,
	PANEL_LOW = 0.7,
	FLICKER_CHANCE = 0.5,
	FLICKER_DIP = 0.45,
	FLICKER_LENGTH = 0.09,
})

-- Where each one stands, by slot (Squad.Arrange: the MVP is 1, on the dais), in the Origin frame, turned toward the
-- camera's side of the car.
local SPOTS = table.freeze({
	CFrame.new(0, 0.8, 0),
	CFrame.new(-8, 0, -3) * CFrame.Angles(0, math.rad(12), 0),
	CFrame.new(8, 0, -3) * CFrame.Angles(0, math.rad(-12), 0),
	CFrame.new(-12, 0, 1) * CFrame.Angles(0, math.rad(18), 0),
})
local ELEVATOR_PATH = { "Lobby", "Map", "ResultsElevator" }

type TGlow = { Part: BasePart, Transparency: number, Lights: { [Light]: number } }
-- A body on the stage: where it stands and how far its pivot is over its feet, and its clips once it is in.
type TBody = {
	Spot: CFrame,
	Lift: number,
	IsIn: boolean,
	HasLanded: boolean,
	Cheer: AnimationTrack?,
	Blend: InertialBlend.TInertialBlend?,
}

local Stage = {}

local elevator: Model? = nil
local origin = CFrame.identity
local shaft: Model? = nil
local shaftRest = CFrame.identity
local travelled = 0
local clock = 0
local kick = 0
local folder: Folder? = nil
local saved: { Type: Enum.CameraType, Fov: number }? = nil
local bodies: { [Model]: TBody } = {}
-- The turning parts with their rest, the glowing ones by kind, and the lamps dipped until a moment.
local turning: { { Part: BasePart, Rest: CFrame } } = {}
local glows: { [string]: { TGlow } } = {}
local dips: { [TGlow]: number } = {}

local function findElevator(): Model?
	local node: Instance? = Workspace
	for _, name in ELEVATOR_PATH do
		node = if node then node:FindFirstChild(name) else nil
	end
	return if node and node:IsA("Model") then node else nil
end

local function named(root: Instance, name: string): { BasePart }
	local found = {}
	for _, item in root:GetDescendants() do
		if item.Name == name and item:IsA("BasePart") then found[#found + 1] = item end
	end
	return found
end

local function glowing(parts: { BasePart }): { TGlow }
	local list = table.create(#parts)
	for index, part in parts do
		local lights = {}
		for _, light in part:GetDescendants() do
			if light:IsA("Light") then lights[light] = light.Brightness end
		end
		list[index] = { Part = part, Transparency = part.Transparency, Lights = lights }
	end
	return list
end

-- A glowing part at level 1 is as it was, at 0 as dim as `low` lets it get.
local function shine(entry: TGlow, level: number, low: number)
	local dim = (1 - level) * low
	entry.Part.Transparency = entry.Transparency + (1 - entry.Transparency) * dim
	for light, brightness in entry.Lights do
		light.Brightness = brightness * (1 - dim)
	end
end

local function gather(model: Model)
	for _, name in { "Sheave", "Hub" } do
		for _, part in named(model, name) do
			turning[#turning + 1] = { Part = part, Rest = part.CFrame }
		end
	end

	local neon = {}
	local arrow = model:FindFirstChild("Arrow", true)
	if arrow then
		for _, part in arrow:GetDescendants() do
			if part:IsA("BasePart") and part.Material == Enum.Material.Neon then neon[#neon + 1] = part end
		end
	end

	local panel = model:FindFirstChild("Panel", true)
	glows.Arrow = glowing(neon)
	glows.Beacon = glowing(named(model, "Warning"))
	glows.Panel = glowing(if panel then named(panel, "Button") else {})
	glows.Flicker = glowing(named(model, "Lamp"))
end

local function animateCar(dt: number)
	local angle = clock * Tune.SHAFT_SPEED / Tune.RADIUS
	for _, entry in turning do
		entry.Part.CFrame = entry.Rest * CFrame.Angles(angle, 0, 0)
	end

	for _, entry in glows.Arrow do
		shine(entry, 0.5 + 0.5 * math.cos(clock * Tune.ARROW_RATE * math.pi * 2), Tune.ARROW_LOW)
	end

	-- The warning lights one after another down the shaft.
	local beacons = glows.Beacon
	for index, entry in beacons do
		local phase = clock * Tune.BEACON_RATE + index / #beacons
		shine(entry, 0.5 + 0.5 * math.cos(phase * math.pi * 2), Tune.BEACON_LOW)
	end

	local buttons = glows.Panel
	local lit = math.floor(clock * Tune.PANEL_RATE) % math.max(#buttons, 1) + 1
	for index, entry in buttons do
		shine(entry, if index == lit then 1 else 0, Tune.PANEL_LOW)
	end

	for _, entry in glows.Flicker do
		local ends = dips[entry]
		if ends and clock >= ends then dips[entry] = nil end
		if not dips[entry] and math.random() < Tune.FLICKER_CHANCE * dt then
			dips[entry] = clock + Tune.FLICKER_LENGTH
		end
		shine(entry, if dips[entry] then 0 else 1, Tune.FLICKER_DIP)
	end
end

-- Every moving part back as it was.
local function settle()
	for _, entry in turning do
		entry.Part.CFrame = entry.Rest
	end
	for _, list in glows do
		for _, entry in list do
			shine(entry, 1, 0)
		end
	end
	if shaft then shaft:PivotTo(shaftRest) end
	table.clear(turning)
	table.clear(glows)
	table.clear(dips)
end

local function load(animator: Animator, id: string, isLooped: boolean): AnimationTrack
	local clip = Instance.new("Animation")
	clip.AnimationId = id
	local track = animator:LoadAnimation(clip)
	track.Looped = isLooped
	return track
end

-- How far `model`'s pivot stands over its feet, standing at the origin. Only the body's own parts count: an accessory's
-- handle stays where the description built it until the model is in the Workspace and its weld puts it on the head,
-- so a hat still under the feet would lift the body out of the shot.
local function liftOf(model: Model): number
	model:PivotTo(CFrame.identity)

	local lowest = 0
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then lowest = math.min(lowest, part.Position.Y - part.Size.Y / 2) end
	end

	return -lowest
end

local function bodyOf(model: Model, slot: number): TBody
	local body = bodies[model]
	if body then return body end
	local spot = SPOTS[slot] or SPOTS[#SPOTS]
	body = {
		-- Facing the camera: the body looks down its -Z, the camera is at +Z.
		Spot = origin * spot * CFrame.Angles(0, math.pi, 0),
		Lift = liftOf(model),
		IsIn = false,
		HasLanded = false,
		Cheer = nil,
		Blend = nil,
	}
	bodies[model] = body
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then root.Anchored = true end
	return body
end

-- The body steps in: parented, idling, each a little out of step.
local function bringIn(model: Model, body: TBody, member: Types.TMember)
	body.IsIn = true
	model.Parent = folder
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = if humanoid then humanoid:FindFirstChildOfClass("Animator") else nil
	if not animator then return end
	local idle = load(animator, avatarClips.IDLE, true)
	idle:Play(0)
	idle.TimePosition = member.Order * 0.37
	if member.IsMvp then
		local cheer = load(animator, avatarClips.CHEER, false)
		cheer.Priority = Enum.AnimationPriority.Action
		body.Cheer = cheer
		body.Blend = InertialBlend.new(InertialBlend.JointsOf(model), false)
	end
end

-- Places `member`'s body for this moment and gives where its tag goes on the screen.
local function placeBody(
	state: Types.TState,
	times: Types.TClock,
	member: Types.TMember,
	arriveAt: number,
	camera: Camera
): Vector3
	local spot = origin * (SPOTS[member.Slot] or SPOTS[#SPOTS]) * CFrame.Angles(0, math.pi, 0)
	local model = member.Avatar()
	local head = spot.Position + Vector3.new(0, Tune.DEFAULT_HEAD + Tune.TAG_OVER, 0)

	if model then
		local body = bodyOf(model, member.Slot)
		local isDue = times.Elapsed() >= arriveAt or not state.IsOpen()
		if isDue and not body.IsIn then bringIn(model, body, member) end
		if body.IsIn then
			local t = times.Since(arriveAt, Tune.DROP)
			local height = Tune.DROP_STUDS * (1 - t * t)
			if not body.HasLanded or height > 0 then
				model:PivotTo(body.Spot + Vector3.new(0, body.Lift + height, 0))
			end
			if t >= 1 and not body.HasLanded then
				body.HasLanded = true
				kick = math.max(kick, if member.IsMvp then Tune.MVP_KICK else Tune.LAND_KICK)
			end
			if body.Cheer and body.HasLanded and times.Elapsed() >= arriveAt + Tune.DROP + Tune.CHEER_DELAY then
				local blend = body.Blend
				if blend then blend:PlayOneShot(body.Cheer, Tune.CHEER_BLEND) end
				body.Cheer = nil
			end
			local headPart = model:FindFirstChild("Head")
			if headPart and headPart:IsA("BasePart") then
				head = headPart.Position + Vector3.new(0, headPart.Size.Y / 2 + Tune.TAG_OVER, 0)
			end
		end
	end

	local point = camera:WorldToViewportPoint(head)
	return point
end

-- Takes the camera into the elevator. False when the elevator is not in the map (or not streamed in yet).
function Stage.Begin(): boolean
	Stage.End()
	local model = findElevator()
	local originPart = if model then model:FindFirstChild("Origin") else nil
	if not model or not originPart or not originPart:IsA("BasePart") then
		warn("[LobbyEnteringController] no ResultsElevator in Workspace.Lobby.Map: the squad has nowhere to stand")
		return false
	end

	elevator = model
	origin = originPart.CFrame
	local foundShaft = model:FindFirstChild("Shaft")
	shaft = if foundShaft and foundShaft:IsA("Model") then foundShaft else nil
	shaftRest = if shaft then shaft:GetPivot() else CFrame.identity
	travelled = 0
	clock = 0
	kick = 0
	gather(model)

	local squad = Instance.new("Folder")
	squad.Name = "Squad"
	squad.Parent = model
	folder = squad

	local camera = Workspace.CurrentCamera
	saved = { Type = camera.CameraType, Fov = camera.FieldOfView }
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = Tune.FOV
	return true
end

-- One frame of the scene: the shaft, the car, the camera and the bodies. Writes each member's HeadAt.
function Stage.Step(state: Types.TState, times: Types.TClock, dt: number, arriveAt: (Types.TMember) -> number)
	if not elevator then return end
	clock += dt
	travelled = (travelled + Tune.SHAFT_SPEED * dt) % Tune.SHAFT_PERIOD
	if shaft then shaft:PivotTo(shaftRest + Vector3.new(0, travelled, 0)) end
	animateCar(dt)

	local camera = Workspace.CurrentCamera
	local dolly = 1 - (1 - times.Since(0, Tune.DOLLY)) ^ 3
	local eye = Tune.EYE_FROM:Lerp(Tune.EYE, dolly)
	kick *= math.exp(-dt / Tune.KICK_DECAY)
	local amount = Tune.RUMBLE + kick
	local wobble = Vector3.new(
		math.noise(clock * Tune.RUMBLE_SPEED, 0.3),
		math.noise(0.7, clock * Tune.RUMBLE_SPEED),
		0
	) * amount
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(origin * eye + wobble, origin * Tune.TARGET)

	local scale = state.Scale()
	for _, member in state.Members() do
		local point = placeBody(state, times, member, arriveAt(member), camera)
		member.HeadAt(Vector3.new(point.X / scale, point.Y / scale, point.Z))
	end
end

-- Gives the camera back and puts the elevator as it was.
function Stage.End()
	if folder then folder:Destroy() end
	folder = nil
	table.clear(bodies)
	if elevator then settle() end
	elevator = nil
	shaft = nil

	if saved then
		local camera = Workspace.CurrentCamera
		camera.CameraType = if saved.Type == Enum.CameraType.Scriptable then Enum.CameraType.Custom else saved.Type
		camera.FieldOfView = saved.Fov
		saved = nil
	end
end

-- Asks the engine for the elevator's parts, in case the place streams: they are far from where the player stands.
-- Yields.
function Stage.StreamInAsync()
	if not Workspace.StreamingEnabled then return end
	local model = findElevator()
	local at = if model then model:GetPivot().Position else nil
	if at then pcall(LocalPlayer.RequestStreamAroundAsync, LocalPlayer, at) end
end

return Stage
