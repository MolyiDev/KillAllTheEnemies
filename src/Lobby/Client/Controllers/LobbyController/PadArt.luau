-- What a pad looks like round its Part: a neon rim on the pad's edge and a glow rising from it, both in one colour
-- that says whether this player can step on (green) or not (red). Built on the client, so each player sees his own
-- answer; the pad Part itself is the server's zone and is never changed.
--
-- No two faces share a plane (Models.md, "No two faces on one plane"): the rim's bars sink 0.1 into the pad and
-- stand 0.06 / 0.04 out from its sides, the X bars run inside the Z bars' ends and sit inside their height (0.02 up
-- from the bottom, 0.03 down from the top, so the corners where they cross share no face), and the glow starts
-- above the rim on Parts that draw nothing but their SurfaceGuis.
local TweenService = game:GetService("TweenService")

local RIM_WIDTH = 0.62
local RIM_SINK = 0.1
local RIM_RISE = 0.2
-- The bars along X stand out this far past the pad's sides, those along Z a little less, so their ends sit inside.
local Z_BAR_OUT = 0.06
local X_BAR_OUT = 0.04
local X_BAR_LIFT = 0.02
local X_BAR_DROP = 0.03
local GLOW_HEIGHT = 5
local GLOW_GAP = 0.05
-- The glow's alpha at its foot; it fades to nothing at its top.
local GLOW_FOOT_TRANSPARENCY = 0.35
local GLOW_PIXELS_PER_STUD = 16
local TINT_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

export type TPadArt = {
	Rims: { BasePart },
	Glows: { Frame },
	Color: Color3?,
}

local PadArt = {}

local function bar(parent: Instance, size: Vector3, cframe: CFrame): BasePart
	local part = Instance.new("Part")
	part.Name = "Rim"
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Size = size
	part.CFrame = cframe
	part.Parent = parent
	return part
end

-- One side of the glow: a Part that is never drawn, with a gradient on both of its faces.
local function wall(parent: Instance, size: Vector3, cframe: CFrame, glows: { Frame })
	local part = Instance.new("Part")
	part.Name = "Glow"
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = size
	part.CFrame = cframe
	part.Parent = parent

	-- The wall's thin side faces outward along its local Z, so its broad faces are Front and Back.
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.LightInfluence = 0
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = GLOW_PIXELS_PER_STUD
		gui.Adornee = part
		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromScale(1, 1)
		frame.BorderSizePixel = 0
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = -90
		gradient.Transparency = NumberSequence.new(GLOW_FOOT_TRANSPARENCY, 1)
		gradient.Parent = frame
		frame.Parent = gui
		gui.Parent = part
		glows[#glows + 1] = frame
	end
end

function PadArt.Build(pad: BasePart, parent: Instance): TPadArt
	local model = Instance.new("Model")
	model.Name = pad.Name
	local half = pad.Size / 2
	local frame = pad.CFrame
	local rims: { BasePart } = {}
	local glows: { Frame } = {}

	local rimBottom = half.Y - RIM_SINK
	local rimHeight = RIM_SINK + RIM_RISE
	local zBarLength = pad.Size.X + 2 * Z_BAR_OUT
	local xBarLength = pad.Size.Z + 2 * X_BAR_OUT
	local xBarHeight = rimHeight - X_BAR_LIFT - X_BAR_DROP
	for _, side in { -1, 1 } do
		local zCentre = side * (half.Z + Z_BAR_OUT - RIM_WIDTH / 2)
		rims[#rims + 1] = bar(
			model,
			Vector3.new(zBarLength, rimHeight, RIM_WIDTH),
			frame * CFrame.new(0, rimBottom + rimHeight / 2, zCentre)
		)
		local xCentre = side * (half.X + X_BAR_OUT - RIM_WIDTH / 2)
		rims[#rims + 1] = bar(
			model,
			Vector3.new(RIM_WIDTH, xBarHeight, xBarLength),
			frame * CFrame.new(xCentre, rimBottom + X_BAR_LIFT + xBarHeight / 2, 0)
		)
	end

	local glowY = half.Y + RIM_RISE + GLOW_GAP + GLOW_HEIGHT / 2
	for _, side in { -1, 1 } do
		wall(model, Vector3.new(pad.Size.X, GLOW_HEIGHT, 0.05), frame * CFrame.new(0, glowY, side * half.Z), glows)
		wall(
			model,
			Vector3.new(pad.Size.Z, GLOW_HEIGHT, 0.05),
			frame * CFrame.new(side * half.X, glowY, 0) * CFrame.Angles(0, math.pi / 2, 0),
			glows
		)
	end

	model.Parent = parent
	return { Rims = rims, Glows = glows, Color = nil }
end

-- Eases to `color`; the first tint is immediate, so a pad never fades in from white.
function PadArt.Tint(art: TPadArt, color: Color3)
	if art.Color == color then return end
	local isFirst = art.Color == nil
	art.Color = color

	for _, rim in art.Rims do
		if isFirst then
			rim.Color = color
		else
			TweenService:Create(rim, TINT_INFO, { Color = color }):Play()
		end
	end

	for _, glow in art.Glows do
		if isFirst then
			glow.BackgroundColor3 = color
		else
			TweenService:Create(glow, TINT_INFO, { BackgroundColor3 = color }):Play()
		end
	end
end

return PadArt
