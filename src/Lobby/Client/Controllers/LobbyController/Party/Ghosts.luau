-- The places still open in the party, as the players on its pad see them: a black R6 body on each free spot with a
-- white outline and a plus on its chest, which lights under the pointer and opens the invite list. Each rises in from
-- the pad as the party opens; a player arriving on its spot lifts it off in a white flash, as if they stepped into it.
-- Built on this client only, out of the server's sight, and drawn over the pad's rails so the whole body is a target.
--
-- A plain module: LobbyController keeps each ghost and steps it every frame while it is on show. The outline is a
-- Highlight: the lobby has no enemies, so it takes nothing from the match's 255 (CLAUDE.md, "The cap is 255 alive").
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local PadsCore = require(ReplicatedStorage.Shared.Core.PadsCore)

local Palette = Theme.Palette
local Progress = Motion.Progress

local Tune = table.freeze({
	-- The body: an R6's parts in studs, feet on the spot. The arms hang a little out from the sides, so the silhouette
	-- reads as a body waiting, not a mannequin.
	ARM_FLARE = math.rad(7),
	-- The box a press or the pointer must cross, in the spot's space: its middle's height and half its size.
	HIT_MIDDLE = 2.6,
	HIT_HALF = Vector3.new(1.8, 2.8, 0.9),
	-- Rising in: from this far under its spot, over ARRIVE, each spot STAGGER after the one before.
	ARRIVE = 0.5,
	ARRIVE_STAGGER = 0.09,
	ARRIVE_DROP = 1.6,
	LEAVE = 0.22,
	-- A player landing on its spot: a white flash that lifts off and fades.
	FILL = 0.42,
	FILL_RISE = 2.2,
	-- Standing: a slow breath up and down, each body out of step with the next.
	BOB_STUDS = 0.07,
	BOB_PERIOD = 2.8,
	-- Under the pointer: lifted, its outline gold, its plus bigger. The light lands on the frame,
	-- the lift a little behind it (UI.md 5f, "The rise and the light are two different speeds").
	HOVER_LIFT = 0.32,
	HOVER_PLUS = 0.18,
	LIGHT_RATE = 30,
	LIFT_RATE = 14,
	-- A press: it sinks a little and comes back, the plus punches and the fill flashes.
	PRESS = 0.32,
	PRESS_DIP = 0.28,
	PRESS_PUNCH = 0.3,
	PRESS_FLASH = 0.5,
	-- The one ring the plus throws as it lands.
	RING = 0.55,
	-- The plus, in studs across the billboard on the chest, and its ring's reach as a share of it.
	BOARD_STUDS = 3.4,
	PLUS_SHARE = 0.42,
	BAR_SHARE = 0.2,
	RING_REACH = 0.9,
	RING_THICKNESS = 2.5,
	-- The fill's dark: his ink, a hint of violet in the black. Under the pointer it warms a little toward his violet.
	INK = Color3.fromRGB(10, 7, 21),
	INK_LIT = Color3.fromRGB(46, 28, 84),
})

export type TGhost = {
	Spot: number,
	Model: Model,
	-- The feet on the spot, facing the front.
	Base: CFrame,
	Highlight: Highlight,
	PlusScale: UIScale,
	Ring: Frame,
	RingStroke: UIStroke,
	-- Offered to the hand now, and when that last changed; whether it closed because a player landed on it.
	IsOpen: boolean,
	ChangedAt: number,
	IsFilled: boolean,
	-- The hand's light and lift, 0 to 1, eased toward whether it is under the pointer.
	Light: number,
	Lift: number,
	PressedAt: number,
	-- What was last written to the Highlight (how much is shown, lit and whitened), the plus's scale and its ring's
	-- Visible, so a body standing still writes none of it again.
	Shown: number,
	Lit: number,
	Whiten: number,
	Scale: number,
	IsRinging: boolean,
	-- Out of the renderer: closed and done fading. Put back under Folder as it opens again.
	IsGone: boolean,
	Folder: Instance,
}

local Ghosts = {}

local function part(model: Model, name: string, size: Vector3, offset: CFrame, base: CFrame): BasePart
	local piece = Instance.new("Part")
	piece.Name = name
	piece.Anchored = true
	piece.CanCollide = false
	piece.CanQuery = false
	piece.CanTouch = false
	piece.CastShadow = false
	piece.Material = Enum.Material.SmoothPlastic
	piece.Color = Tune.INK
	piece.Size = size
	piece.CFrame = base * offset
	piece.Parent = model
	return piece
end

-- One bar of the plus, a share of the billboard each way.
local function bar(width: number, height: number): Frame
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(width, height)
	frame.BackgroundColor3 = Palette.White
	frame.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.18, 0)
	corner.Parent = frame
	return frame
end

-- The plus on the chest and its ring: one billboard over everything, sized in studs so it grows and shrinks with the
-- body.
local function board(ghost: TGhost, torso: BasePart)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Plus"
	gui.Adornee = torso
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Size = UDim2.fromScale(Tune.BOARD_STUDS, Tune.BOARD_STUDS)
	gui.StudsOffset = Vector3.new(0, -0.35, 0)
	gui.ResetOnSpawn = false

	local plus = Instance.new("Frame")
	plus.Name = "Mark"
	plus.AnchorPoint = Vector2.new(0.5, 0.5)
	plus.Position = UDim2.fromScale(0.5, 0.4)
	plus.Size = UDim2.fromScale(Tune.PLUS_SHARE, Tune.PLUS_SHARE)
	plus.BackgroundTransparency = 1
	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = plus
	bar(Tune.BAR_SHARE, 1).Parent = plus
	bar(1, Tune.BAR_SHARE).Parent = plus
	plus.Parent = gui

	-- One ring, growing off the plus by pixels at one weight.
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.4)
	ring.Size = UDim2.fromScale(Tune.PLUS_SHARE, Tune.PLUS_SHARE)
	ring.BackgroundTransparency = 1
	ring.Visible = false
	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(0.5, 0)
	ringCorner.Parent = ring
	local stroke = Instance.new("UIStroke")
	stroke.Color = Palette.White
	stroke.Thickness = Tune.RING_THICKNESS
	stroke.Parent = ring
	ring.Parent = gui

	gui.Parent = ghost.Model
	ghost.PlusScale = scale
	ghost.Ring = ring
	ghost.RingStroke = stroke
end

-- The body for spot `spot` of `pad`, under `parent`, closed: it rises in once Open says so.
function Ghosts.Build(pad: BasePart, spot: number, parent: Instance): TGhost
	local base = PadsCore.SpotAt(pad, spot)
	local model = Instance.new("Model")
	model.Name = `Spot{spot}`

	part(model, "LeftLeg", Vector3.new(1, 2, 1), CFrame.new(-0.5, 1, 0), base)
	part(model, "RightLeg", Vector3.new(1, 2, 1), CFrame.new(0.5, 1, 0), base)
	local torso = part(model, "Torso", Vector3.new(2, 2, 1), CFrame.new(0, 3, 0), base)
	part(
		model,
		"LeftArm",
		Vector3.new(1, 2, 1),
		CFrame.new(-1.5, 4, 0) * CFrame.Angles(0, 0, -Tune.ARM_FLARE) * CFrame.new(0, -1, 0),
		base
	)
	part(
		model,
		"RightArm",
		Vector3.new(1, 2, 1),
		CFrame.new(1.5, 4, 0) * CFrame.Angles(0, 0, Tune.ARM_FLARE) * CFrame.new(0, -1, 0),
		base
	)
	local head = part(model, "Head", Vector3.new(2, 1, 1), CFrame.new(0, 4.5, 0), base)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head
	mesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	mesh.Parent = head
	model.WorldPivot = base

	-- Over the pad's rails and everything else, so the whole body stands out and is a target.
	local highlight = Instance.new("Highlight")
	highlight.Adornee = model
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = Tune.INK
	highlight.OutlineColor = Palette.White
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.Parent = model

	local ghost = {
		Spot = spot,
		Model = model,
		Base = base,
		Highlight = highlight,
		IsOpen = false,
		ChangedAt = -math.huge,
		IsFilled = false,
		Light = 0,
		Lift = 0,
		PressedAt = -math.huge,
		Shown = 0,
		Lit = 0,
		Whiten = 0,
		Scale = 0,
		IsRinging = false,
		IsGone = true,
		Folder = parent,
	} :: TGhost
	board(ghost, torso)
	return ghost
end

-- Offers the spot (it rises in) or takes it back: `isFilled` when a player landed on it, so it lifts off in a flash
-- rather than sinking away. Nothing while it already is so.
function Ghosts.Open(ghost: TGhost, isOpen: boolean, isFilled: boolean, now: number)
	if ghost.IsOpen == isOpen then return end
	ghost.IsOpen = isOpen
	ghost.IsFilled = not isOpen and isFilled
	ghost.ChangedAt = now
	if isOpen then
		ghost.IsGone = false
		ghost.PressedAt = -math.huge
		ghost.Model.Parent = ghost.Folder
	end
end

-- Pressed: it sinks and punches as the invite list opens.
function Ghosts.Press(ghost: TGhost, now: number)
	ghost.PressedAt = now
end

-- How far along `ray` it is hit (in studs), or nil: the box a body fills, in its spot's space. Only an open body is a
-- target.
function Ghosts.Hit(ghost: TGhost, ray: Ray): number?
	if not ghost.IsOpen then return nil end
	local middle = ghost.Base * CFrame.new(0, Tune.HIT_MIDDLE, 0)
	local origin = middle:PointToObjectSpace(ray.Origin)
	local inverse = Vector3.one / middle:VectorToObjectSpace(ray.Direction)
	-- The slab test on all three axes at once. A direction flat along an axis divides to an infinity, which keeps an
	-- origin outside that slab out (both ends land on one side) and one inside it in.
	local a = (-Tune.HIT_HALF - origin) * inverse
	local b = (Tune.HIT_HALF - origin) * inverse
	local near, far = a:Min(b), a:Max(b)
	local enter = math.max(near.X, near.Y, near.Z)
	local leave = math.min(far.X, far.Y, far.Z)
	if enter > leave or leave < 0 then return nil end
	return math.max(enter, 0) * ray.Direction.Magnitude
end

-- `value` eased toward `goal` at `rate` a second, landing on it once it is within a thousandth, so a body left alone
-- stops writing.
local function ease(value: number, goal: number, rate: number, dt: number): number
	local eased = value + (goal - value) * (1 - math.exp(-rate * dt))
	return if math.abs(goal - eased) < 1e-3 then goal else eased
end

-- One frame of it: `isHovered` while the pointer is on it. Writes only while it is on show; done fading out, it is
-- taken out of the renderer.
function Ghosts.Step(ghost: TGhost, now: number, dt: number, isHovered: boolean)
	if ghost.IsGone then return end
	local since = now - ghost.ChangedAt
	local delay = Tune.ARRIVE_STAGGER * (ghost.Spot - 1)
	-- How much of it is there, and how far its open has come.
	local shown, risen, flash, lifted
	if ghost.IsOpen then
		risen = Motion.Decelerate(Progress(since, 0, Tune.ARRIVE, delay))
		shown = Motion.Out(Progress(since, 0, Tune.ARRIVE * 0.6, delay))
		flash = 0
		lifted = 0
	elseif ghost.IsFilled then
		local t = Progress(since, 0, Tune.FILL)
		risen = 1
		shown = 1 - Motion.Accelerate(t)
		flash = 1 - Motion.Out(t)
		lifted = Tune.FILL_RISE * Motion.Decelerate(t)
	else
		local t = Progress(since, 0, Tune.LEAVE)
		risen = 1 - Motion.Accelerate(t)
		shown = 1 - t
		flash = 0
		lifted = 0
	end
	if shown <= 0 and not ghost.IsOpen then
		ghost.IsGone = true
		ghost.Model.Parent = nil
		return
	end

	local goal = if isHovered and ghost.IsOpen then 1 else 0
	local light = ease(ghost.Light, goal, Tune.LIGHT_RATE, dt)
	local lift = ease(ghost.Lift, goal, Tune.LIFT_RATE, dt)
	ghost.Light, ghost.Lift = light, lift
	local pressed = Motion.Bump(Progress(now, ghost.PressedAt, Tune.PRESS))
	local bob = Tune.BOB_STUDS * math.sin(2 * math.pi * (now / Tune.BOB_PERIOD + ghost.Spot * 0.31))

	-- Its one ring is thrown as it lands, its plus popping in with it.
	local landed = Tune.ARRIVE + delay
	local ring = if ghost.IsOpen then Progress(since, 0, Tune.RING, landed * 0.7) else 1

	local height = -Tune.ARRIVE_DROP * (1 - risen) + bob + Tune.HOVER_LIFT * lift - Tune.PRESS_DIP * pressed + lifted
	ghost.Model:PivotTo(ghost.Base * CFrame.new(0, height, 0))

	-- Every property write is an engine call, and a standing body changes nothing but its height: the rest is written
	-- only while it moves.
	local whiten = math.max(flash, Tune.PRESS_FLASH * pressed)
	if shown ~= ghost.Shown or light ~= ghost.Lit or whiten ~= ghost.Whiten then
		ghost.Shown, ghost.Lit, ghost.Whiten = shown, light, whiten
		local highlight = ghost.Highlight
		highlight.FillTransparency = 1 - shown
		highlight.OutlineTransparency = 1 - shown
		highlight.FillColor = Tune.INK:Lerp(Tune.INK_LIT, light):Lerp(Palette.White, whiten)
		highlight.OutlineColor = Palette.White:Lerp(Palette.Gold, light)
	end

	local pop = if ghost.IsOpen then Motion.Decelerate(Progress(since, 0, Tune.ARRIVE * 0.8, landed * 0.6)) else 1
	local scale = shown * pop * (1 + Tune.HOVER_PLUS * light + Tune.PRESS_PUNCH * pressed)
	if scale ~= ghost.Scale then
		ghost.Scale = scale
		ghost.PlusScale.Scale = scale
	end
	local isRinging = ring < 1 and shown > 0
	if isRinging ~= ghost.IsRinging then
		ghost.IsRinging = isRinging
		ghost.Ring.Visible = isRinging
	end
	if isRinging then
		local reach = 1 + Tune.RING_REACH * Motion.Decelerate(ring)
		ghost.Ring.Size = UDim2.fromScale(Tune.PLUS_SHARE * reach, Tune.PLUS_SHARE * reach)
		ghost.RingStroke.Transparency = ring
		ghost.RingStroke.Color = Palette.White:Lerp(Palette.Gold, light)
	end
end

return Ghosts
