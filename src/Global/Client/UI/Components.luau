--!nonstrict
-- The UI's building blocks, all in Theme's look: square, opaque, edged in their own colour. Plain functions that
-- return vide trees: a reactive property is passed as a source (a function), a static one as a value. `props` is
-- applied after the defaults (vide defers nested property tables), so a caller overrides any default by naming it.
--
-- The view files are nonstrict: a vide tree mixes properties and children in one table, which strict mode reads as
-- an array of whatever its first child is and rejects. The state they read is typed in Types.luau, strictly.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local vide = require(ReplicatedStorage.Packages.vide)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local KeyImages = require(ReplicatedStorage.GlobalShared.Utils.KeyImages)
local Hand = require(script.Parent.Hand)
local Icons = require(script.Parent.Icons)
local Theme = require(script.Parent.Theme)

local create = vide.create
local action = vide.action
local Color = Theme.Color
local Font = Theme.Font
local Palette = Theme.Palette

type TProps = { [any]: any }

local NO_PROPS = table.freeze({})
-- The designer's look, measured off his art (UIMatt.md, In-Game HUD; drawn at twice 1080, so his 2 px are 1 here).
-- Every size handed to these is his OUTER drawn rect, stroke included, so his rects can be used as they are.
local Look = table.freeze({
	-- Dark panels: a 2 px pink edge, lighter along the top than the bottom, a darker lip under the top edge and a
	-- lighter line inside the bottom one; his drop shadow 4 down.
	PANEL_EDGE = 2,
	PANEL_CORNER = 3,
	EDGE_BOTTOM = 0.82,
	LIP = Color3.fromRGB(11, 9, 23),
	FACE = Color3.fromRGB(19, 13, 39),
	FACE_TOP = Color3.fromRGB(24, 19, 44),
	SHINE = Color3.fromRGB(122, 50, 93),
	SHADE_BLUR = 20,
	SHADE_DROP = 4,
	SHADE_TRANSPARENCY = 0.6,
	-- Cards: a 3 px edge of their accent, a dark face warming toward the accent at the bottom, a name band, an accent
	-- glow.
	CARD_EDGE = 3,
	CARD_FACE = Color3.fromRGB(19, 19, 40),
	CARD_BAND = Color3.fromRGB(14, 20, 32),
	CARD_TINT_MID = 0.08,
	GLOW_BLUR = 20,
	GLOW_DROP = 4,
	GLOW_TRANSPARENCY = 0.7,
	-- Slabs (SKIP WAVE, the countdown, the money packs): a 1 px dark rim, a 2 px hot pink edge, a glossy face.
	SLAB_RIM = Color3.fromRGB(60, 11, 33),
	SLAB_EDGE = 2,
	SLAB_GLOW_TRANSPARENCY = 0.6,
	-- Plaques (keys, the vote count): a grey edge round an ink square.
	PLAQUE_EDGE = Color3.fromRGB(122, 120, 130),
	PLAQUE_FACE = Color3.fromRGB(13, 10, 28),
	-- Corner brackets: white, a rounded bend.
	BRACKET_THICKNESS = 1.5,
	BRACKET_RADIUS = 3,
	BRACKET_LENGTH = 20,
	BRACKET_TRANSPARENCY = 0.6,
	BRACKET_SLACK = 2,
	-- How far every set stands off what it frames, and how much more under the hand: one distance on every screen.
	BRACKET_OUTSET = 4,
	BRACKET_OPEN = 2,
	-- Brackets closed round what is picked: one whole outline, as bright as the weapons screen's ring was.
	BRACKET_CLOSED_TRANSPARENCY = 0.05,
	-- The lobby's flat slabs (UIMatt.md, Lobby HUD): the face's share left under the top edge, how far down the face
	-- that shade holds and where it is gone, the marks' share of the face and their leg, the brackets' leg.
	FLAT_SHADE = 0.45,
	FLAT_SHADE_DEPTH = 0.035,
	FLAT_SHADE_END = 0.065,
	FLAT_MARK = 0.5,
	FLAT_MARK_LEG = 21,
	FLAT_BRACKET_LENGTH = 20,
	-- The lobby's currency pills: shares of the face for the rim, the sides, the bottom edge, the shade under the lip
	-- and the marks; the marks' leg, the brackets' leg, and how faint his gold glow under them is.
	PILL_RIM = 0.35,
	PILL_SIDE = 0.82,
	PILL_BOTTOM = 0.5,
	PILL_SHADE = 0.45,
	PILL_MARK = 0.6,
	PILL_MARK_LEG = 12,
	PILL_BRACKET_LENGTH = 12,
	PILL_GLOW_TRANSPARENCY = 0.62,
})
-- Brackets closing round what is picked (Components.Brackets' `isClosed`): the legs run along the edges and meet in
-- the middle of each side on a spring that carries past the meeting, and the carry is the seal: the outline swells,
-- thickens and flashes at the four joins, then settles. At these numbers the legs meet 0.2 s in and the carry peaks
-- 12% past at 0.28 s (lune).
local Merge = table.freeze({
	PERIOD = 0.48,
	DAMPING = 0.55,
	OVERSHOOT = 0.12,
	SWELL = 4,
	THICKEN = 1.5,
	WELD_LENGTH = 38,
	WELD_THICKNESS = 3,
})
-- His pink edge, top to bottom (a slab's is brighter at the top and deeper at the bottom). Gradients here are lists of
-- { position, colour } for gradientOf.
local SLAB_EDGE = table.freeze({
	{ 0, Color3.fromRGB(255, 46, 139) },
	{ 0.5, Color3.fromRGB(223, 32, 117) },
	{ 1, Color3.fromRGB(190, 18, 95) },
})
local SLAB_EDGE_OFF = table.freeze({
	{ 0, Color3.fromRGB(130, 126, 150) },
	{ 1, Color3.fromRGB(90, 86, 110) },
})
-- A slab's face by kind: a dark line under the edge, a light band, then down to the deep colour.
local SLAB_FACES = table.freeze({
	Go = table.freeze({
		{ 0, Color3.fromRGB(49, 96, 77) },
		{ 0.04, Color3.fromRGB(76, 165, 129) },
		{ 0.12, Color3.fromRGB(75, 182, 138) },
		{ 0.5, Color3.fromRGB(16, 154, 97) },
		{ 1, Color3.fromRGB(9, 93, 59) },
	}),
	Gold = table.freeze({
		{ 0, Color3.fromRGB(115, 97, 63) },
		{ 0.06, Color3.fromRGB(203, 167, 103) },
		{ 0.14, Color3.fromRGB(227, 184, 107) },
		{ 0.48, Color3.fromRGB(215, 158, 55) },
		{ 1, Color3.fromRGB(130, 96, 34) },
	}),
	-- The squad screen's header and its close button.
	Pink = table.freeze({
		{ 0, Color3.fromRGB(150, 56, 98) },
		{ 0.03, Color3.fromRGB(133, 58, 92) },
		{ 0.09, Color3.fromRGB(255, 103, 170) },
		{ 0.46, Color3.fromRGB(254, 46, 139) },
		{ 1, Color3.fromRGB(150, 28, 82) },
	}),
	-- The results' Robux button.
	Violet = table.freeze({
		{ 0, Color3.fromRGB(90, 74, 128) },
		{ 0.05, Color3.fromRGB(126, 102, 185) },
		{ 0.08, Color3.fromRGB(153, 125, 226) },
		{ 0.16, Color3.fromRGB(165, 128, 255) },
		{ 0.46, Color3.fromRGB(137, 91, 251) },
		{ 1, Color3.fromRGB(82, 54, 150) },
	}),
	-- The results' WATCH AD button.
	Steel = table.freeze({
		{ 0, Color3.fromRGB(96, 105, 115) },
		{ 0.05, Color3.fromRGB(137, 149, 166) },
		{ 0.08, Color3.fromRGB(166, 184, 203) },
		{ 0.16, Color3.fromRGB(179, 201, 225) },
		{ 0.46, Color3.fromRGB(151, 178, 207) },
		{ 1, Color3.fromRGB(93, 110, 127) },
	}),
	-- The settings' RESET ALL and the confirm's RESET.
	Red = table.freeze({
		{ 0, Color3.fromRGB(121, 61, 65) },
		{ 0.04, Color3.fromRGB(130, 64, 68) },
		{ 0.1, Color3.fromRGB(235, 101, 110) },
		{ 0.45, Color3.fromRGB(230, 60, 72) },
		{ 1, Color3.fromRGB(139, 31, 39) },
	}),
	-- Not in his set: a slab that cannot be pressed yet, the same gloss in grey violet.
	Off = table.freeze({
		{ 0, Color3.fromRGB(40, 36, 58) },
		{ 0.04, Color3.fromRGB(78, 72, 104) },
		{ 0.12, Color3.fromRGB(84, 78, 112) },
		{ 0.5, Color3.fromRGB(56, 50, 82) },
		{ 1, Color3.fromRGB(32, 28, 50) },
	}),
})
local PANEL_FACE = table.freeze({
	{ 0, Look.LIP },
	{ 0.04, Look.LIP },
	{ 0.1, Look.FACE_TOP },
	{ 0.18, Look.FACE },
	{ 1, Look.FACE },
})
-- The same lip on a panel hundreds of px tall, where a share of its height would be a dark band.
local PANEL_FACE_TALL = table.freeze({
	{ 0, Look.LIP },
	{ 0.006, Look.LIP },
	{ 0.02, Look.FACE_TOP },
	{ 0.035, Look.FACE },
	{ 1, Look.FACE },
})
-- The corner marks inside a slab, in the face's deep colour.
local SLAB_MARKS = table.freeze({
	Go = Color3.fromRGB(10, 62, 40),
	Gold = Color3.fromRGB(96, 62, 18),
	Pink = Color3.fromRGB(110, 18, 60),
	Violet = Color3.fromRGB(58, 38, 108),
	Steel = Color3.fromRGB(64, 76, 90),
	Red = Color3.fromRGB(104, 22, 32),
	Off = Color3.fromRGB(24, 20, 40),
})
local TEXTURE_TRANSPARENCY = 1 - Icons.PANEL_TEXTURE_PEAK
-- How far into the texture a panel's window may start, so a panel up to this size never runs off its edge.
local TEXTURE_PHASES = Icons.PANEL_TEXTURE_SIZE // 2

local Components = {}

-- Counts the panels built, so each looks into the streak texture at a different place.
local texturesMade = 0

-- A block's edge: a lighter tint of its own colour. `color` and `transparency` may be sources.
function Components.Edge(color: any?, transparency: any?): UIStroke
	return create("UIStroke")({
		Color = color or Color.Edge,
		Transparency = transparency or 0,
		Thickness = Theme.EDGE_THICKNESS,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Miter,
	})
end

-- Ink round a letter of `size`, for text that sits straight on the arena or on a colour it could lose against. `floor`
-- is the thinnest it may be, in design px, for small letters on screens drawn smaller than 1080.
function Components.Ink(size: number, floor: number?): UIStroke
	return create("UIStroke")({
		Color = Color.Ink,
		Thickness = math.max(floor or 1, math.round(size * Theme.INK_SHARE)),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Miter,
	})
end

-- An opaque ink block with an edge. Pass an Edge in `props` for a coloured one, or `hasEdge = false` for none.
function Components.Block(props: TProps, hasEdge: boolean?): Frame
	return create("Frame")({
		BackgroundColor3 = Color.Ink,
		BorderSizePixel = 0,
		if hasEdge ~= false then Components.Edge() else nil,
		props,
	})
end

-- Every button's hover and click sound (bags of takes under Sounds.UI). Connected in an action rather than as event
-- properties, which the caller's own MouseEnter / Activated would replace; the connections go with the button. Button
-- puts it on its own; a button made without Button takes it as a child.
Components.ButtonSounds = action(function(instance: Instance)
	local button = instance :: GuiButton
	button.MouseEnter:Connect(function()
		if not Hand.IsReachable(button) then return end
		SoundsCore.PlayHover()
	end)
	button.Activated:Connect(function()
		SoundsCore.PlayClick()
	end)
end)

-- A Block that can be clicked. No AutoButtonColor: the caller decides what a hover looks like.
function Components.Button(props: TProps): TextButton
	return create("TextButton")({
		BackgroundColor3 = Color.Ink,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Components.ButtonSounds,
		props,
	})
end

function Components.Text(props: TProps): TextLabel
	return create("TextLabel")({
		BackgroundTransparency = 1,
		FontFace = Font.Bold,
		TextColor3 = Color.Text,
		TextSize = 18,
		props,
	})
end

-- The key that does it, as its keycap picture (KeyImages). `keyCode` is an Enum.KeyCode, or a
-- source of one or nil; nil draws nothing.
function Components.KeyCap(keyCode: any, size: number, props: TProps?): ImageLabel
	local image = if type(keyCode) == "function"
		then function(): string
			local current = keyCode()
			return if current then KeyImages.GetForKeyCode(current) else ""
		end
		else KeyImages.GetForKeyCode(keyCode)
	return create("ImageLabel")({
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		Image = image,
		ImageColor3 = Color.Text,
		ScaleType = Enum.ScaleType.Fit,
		props or NO_PROPS,
	})
end

-- A fill bar. `fraction` is a 0..1 source; `trail`, when given, draws a pale chip behind the fill for what was just
-- lost, so a hit reads as a bite out of the bar rather than a jump.
function Components.Bar(props: TProps, fraction: () -> number, color: any, trail: (() -> number)?): Frame
	return create("Frame")({
		BackgroundColor3 = Color.Surface,
		BorderSizePixel = 0,
		if trail
			then create("Frame")({
				Name = "Trail",
				BackgroundColor3 = Color.Trail,
				BorderSizePixel = 0,
				Size = function()
					return UDim2.fromScale(math.clamp(trail(), 0, 1), 1)
				end,
			})
			else nil,
		create("Frame")({
			Name = "Fill",
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Size = function()
				return UDim2.fromScale(math.clamp(fraction(), 0, 1), 1)
			end,
		}),
		props,
	})
end

-- A gem drawn as a turned square: no art to load, and it reads as a gem at 16 pixels. Small, unclipped and never
-- hit-tested, so none of UI.md's rotation traps apply.
function Components.GemMark(props: TProps): Frame
	return create("Frame")({
		Size = UDim2.fromOffset(16, 16),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = 45,
		BackgroundColor3 = Color.Ink,
		BorderSizePixel = 0,
		props,
	})
end

-- ============================== The designer's look (UIMatt.md) ==============================

-- Reads a spec field that may be a source.
local function read(value: any): any
	return if type(value) == "function" then value() else value
end

-- The frame colour and the keys that scale it down to `keys` (see Components.Gradient).
local function split(keys: { { any } }): (Color3, ColorSequence)
	local r, g, b = 1 / 255, 1 / 255, 1 / 255
	for _, key in keys do
		local color: Color3 = key[2]
		r, g, b = math.max(r, color.R), math.max(g, color.G), math.max(b, color.B)
	end

	local points = table.create(#keys)
	for index, key in keys do
		local color: Color3 = key[2]
		points[index] = ColorSequenceKeypoint.new(key[1], Color3.new(color.R / r, color.G / g, color.B / b))
	end

	return Color3.new(r, g, b), ColorSequence.new(points)
end

-- A vertical colour ramp, `keys` a list of { position, Color3 } (or a source of one): the frame's BackgroundColor3
-- and its UIGradient, to be put among the frame's props. A gradient multiplies the frame's colour, and Roblox blends
-- gradient keys in squared space at 8 bits, which crushes a dark key's channels (11 renders as 0, rur's images.md).
-- So the frame takes the brightest of each channel and the keys only scale it down, where 8 bits are plenty.
function Components.Gradient(keys: any): { any }
	if type(keys) ~= "function" then
		local color, sequence = split(keys)
		return {
			BackgroundColor3 = color,
			create("UIGradient")({ Rotation = 90, Color = sequence }),
		}
	end

	local parts = vide.derive(function()
		local color, sequence = split(keys())
		return { Color = color, Sequence = sequence }
	end)
	return {
		BackgroundColor3 = function()
			return parts().Color
		end,
		create("UIGradient")({
			Rotation = 90,
			Color = function()
				return parts().Sequence
			end,
		}),
	}
end

-- `content` laid in a frame of `props`, drawn straight while it stands still and through a CanvasGroup only while
-- `shown` is under 1: a group re-renders its whole texture on any change inside it, so at rest every hover and punch
-- would redraw the panel. Returns both frames, for the caller to place.
function Components.FadeGroup(name: string, shown: () -> number, props: TProps, content: { any }): { Instance }
	local isFading = vide.derive(function(): boolean
		return shown() < 1
	end)
	local still = create("Frame")({
		Name = `{name}Still`,
		BackgroundTransparency = 1,
		props,
	})
	local fading = create("CanvasGroup")({
		Name = `{name}Fading`,
		BackgroundTransparency = 1,
		Visible = isFading,
		GroupTransparency = function()
			return 1 - shown()
		end,
		props,
	})
	create("Frame")({
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = function()
			return if isFading() then fading else still
		end,
		content,
	})

	return { still, fading }
end

-- A band of white light swept once across its parent as `travel` runs 0 to 1: a surface catching the light as it comes
-- alive. Its strength rides an envelope over the sweep, nothing at either end, so it never sits at a flat alpha and pops
-- off when the sweep settles (UI.md, "A SWEPT band's travel"). A UIGradient turns in its frame's 0-1 space, so on a
-- wide face its 20 degrees lie almost flat: `aspect` (width / height) turns it back to lean 20 degrees on the screen.
function Components.Sheen(travel: () -> number, zIndex: number, aspect: number?): Frame
	-- Out of the renderer while it is not crossing (it is invisible at both ends anyway): a layer at full transparency
	-- is still drawn (UI.md 5g). Derived, so it is written only as it starts and ends.
	local isCrossing = vide.derive(function(): boolean
		local t = travel()
		return t > 0 and t < 1
	end)

	return create("Frame")({
		Name = "Sheen",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Palette.White,
		BorderSizePixel = 0,
		ZIndex = zIndex,
		Visible = isCrossing,
		BackgroundTransparency = function()
			return 1 - 0.65 * math.sin(math.pi * travel())
		end,
		create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
		create("UIGradient")({
			Rotation = if aspect then math.deg(math.atan(math.tan(math.rad(20)) / aspect)) else 20,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.42, 1),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(0.58, 1),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Offset = function()
				local t = travel()
				return Vector2.new(-1 + 2 * (1 - (1 - t) * (1 - t)), 0)
			end,
		}),
	})
end

-- A flat glyph from the atlas (Icons.Cells), white, tinted by `ImageColor3` in `props`. Only Robux is drawn this way,
-- as Roblox draws it; every other icon is a Picture.
function Components.Icon(name: string, props: TProps): ImageLabel
	return create("ImageLabel")({
		BackgroundTransparency = 1,
		Image = Icons.IMAGE,
		ImageRectOffset = Icons.Cells[name],
		ImageRectSize = Icons.CELL_SIZE,
		ScaleType = Enum.ScaleType.Fit,
		props,
	})
end

-- The square an Icon is drawn in so that its glyph's longer side comes out `longest` px (icons.py pads each cell).
function Components.GlyphBox(longest: number): UDim2
	local side = math.round(longest / Icons.GLYPH_SHARE)
	return UDim2.fromOffset(side, side)
end

-- A rendered icon (an EIcons name), drawn in its own colours. ImageColor3 multiplies them, so it is only for the white
-- marks (Check, Arrow, Replay, Skip), which take a colour as a flat glyph did, and for darkening a picture that is off.
-- `name` may be a source, for a spot whose picture changes; the pictures span several atlases, so the Image follows it.
function Components.Picture(name: string | () -> string, props: TProps): ImageLabel
	if type(name) == "string" then
		local picture = Icons.Pictures[name]
		return create("ImageLabel")({
			BackgroundTransparency = 1,
			Image = picture.Image,
			ImageRectOffset = picture.Offset,
			ImageRectSize = Icons.PICTURE_CELL_SIZE,
			ScaleType = Enum.ScaleType.Fit,
			props,
		})
	end

	local picture = vide.derive(function()
		return Icons.Pictures[name()]
	end)

	return create("ImageLabel")({
		BackgroundTransparency = 1,
		Image = function()
			return picture().Image
		end,
		ImageRectOffset = function()
			return picture().Offset
		end,
		ImageRectSize = Icons.PICTURE_CELL_SIZE,
		ScaleType = Enum.ScaleType.Fit,
		props,
	})
end

-- The square a Picture is drawn in so that its longer side comes out `longest` px.
function Components.PictureBox(longest: number): UDim2
	local side = math.round(longest / Icons.PICTURE_SHARE)
	return UDim2.fromOffset(side, side)
end

-- How far brackets have closed round what is picked: `share` 0 (corners) to 1 (the legs met), `seal` the carry past
-- the meeting as 0 to 1 and back, and `isSealed` from the meeting until it is let go. Sealed it holds at 1, so the
-- spring ringing round 1 never parts the legs again.
local function merge(isClosed: () -> boolean): (() -> number, () -> number, () -> boolean)
	local closed = Hand.Spring(function(): number
		return if isClosed() then 1 else 0
	end, Merge.PERIOD, Merge.DAMPING)
	local isSealed = vide.source(false)
	vide.effect(function()
		local value = closed()
		local goal = isClosed()
		vide.untrack(function()
			local sealed = goal and (isSealed() or value >= 0.999)
			if sealed ~= isSealed() then isSealed(sealed) end
		end)
	end)

	local share = vide.derive(function(): number
		if isSealed() then return 1 end
		return math.clamp(closed(), 0, 1)
	end)
	local seal = vide.derive(function(): number
		if not isSealed() then return 0 end
		return math.clamp((closed() - 1) / Merge.OVERSHOOT, 0, 1)
	end)

	return share, seal, isSealed
end

-- A bright run of light on the middle of one side, where two legs meet as the brackets seal: `side` 0 top, 1 bottom, 2
-- left, 3 right. Tapered at both ends, so it reads as light and not as a bar.
local function weld(side: number, seal: () -> number, thickness: number): Frame
	local isAcross = side < 2
	local far = side % 2
	local inward = if far == 1 then -thickness / 2 else thickness / 2
	local length = vide.derive(function(): number
		return math.round(Merge.WELD_LENGTH * (0.4 + 0.6 * seal()))
	end)

	return create("Frame")({
		Name = "Weld",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = if isAcross
			then UDim2.new(0.5, 0, far, math.round(inward))
			else UDim2.new(far, math.round(inward), 0.5, 0),
		Size = function()
			return if isAcross
				then UDim2.fromOffset(length(), Merge.WELD_THICKNESS)
				else UDim2.fromOffset(Merge.WELD_THICKNESS, length())
		end,
		BackgroundColor3 = Palette.White,
		BackgroundTransparency = function()
			return 1 - seal()
		end,
		BorderSizePixel = 0,
		create("UICorner")({ CornerRadius = UDim.new(0, 1) }),
		-- Rotated, a gradient's ramp spans the frame's height (UI.md), which is a standing weld's length.
		create("UIGradient")({
			Rotation = if isAcross then 0 else 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})
end

-- The four corner brackets standing off a panel: a frame BRACKET_OUTSET px bigger than its parent on every side, with an
-- L at each corner whose bend is rounded, as his are. Each L is the corner of a rounded outline twice its leg, seen
-- through a window one leg square. `rise` (a source, 0 to 1: the hand's rise, nil for none) opens them BRACKET_OPEN
-- more. Every set in both places stands the same distance off what it frames, so no caller picks one. `transparency`
-- may be a source; `length` is each leg's, in px.
--
-- `isClosed` (a source) closes them round what is picked: each window grows to a quarter of the frame, so the four
-- legs run along the edges and meet in the middle of each side as one whole outline, which then seals (`merge`).
-- Let go, the outline parts at the same four places and the legs run back to the corners.
function Components.Brackets(
	rise: (() -> number)?,
	transparency: any?,
	length: number?,
	isClosed: (() -> boolean)?
): Frame
	local alpha = transparency or Look.BRACKET_TRANSPARENCY
	local leg = length or Look.BRACKET_LENGTH
	local thickness = Look.BRACKET_THICKNESS
	local slack = Look.BRACKET_SLACK
	local share, seal, isSealed
	if isClosed then
		share, seal, isSealed = merge(isClosed)
	end
	-- What the four corners share while they close, worked out once rather than once a corner: the window (half the
	-- frame and the slack at the end, so the four tile it and meet in the middle), the outline seen through it (twice
	-- the window less its slack, so its far corners stay out of the window however far it has grown, and once the
	-- window is a quarter of the frame the four outlines are one outline the frame's size), and the stroke, brightening
	-- toward the picked look.
	local window, outline, strokeAlpha
	if share then
		window = vide.derive(function(): UDim2
			local t = share()
			local px = leg * (1 - t) + slack
			return UDim2.new(0.5 * t, px, 0.5 * t, px)
		end)
		outline = vide.derive(function(): UDim2
			local px = -2 * slack - 2 * thickness * share()
			return UDim2.new(2, px, 2, px)
		end)
		strokeAlpha = vide.derive(function(): number
			local t = share()
			return read(alpha) * (1 - t) + Look.BRACKET_CLOSED_TRANSPARENCY * t
		end)
	end
	-- Whole px off the frame, derived so a hover's spring writes the size only as it crosses a pixel.
	local outset = if rise or seal
		then vide.derive(function(): number
			local open = if rise then Look.BRACKET_OPEN * rise() else 0
			return math.round(Look.BRACKET_OUTSET + open + (if seal then Merge.SWELL * seal() else 0))
		end)
		else nil

	local corners = table.create(4)
	for corner = 0, 3 do
		local right = corner % 2
		local bottom = corner // 2
		local anchor = Vector2.new(right, bottom)
		local outward = Vector2.new(if right == 1 then 1 else -1, if bottom == 1 then 1 else -1)
		-- The outline sits a stroke in from the bracket's corner, so the stroke drawn outside it lands on that corner.
		-- The window reaches BRACKET_SLACK past it: a stroke ending on the window's edge is shaved off whenever a
		-- screen scaled under 1080 puts that edge on a fraction of a pixel (the top legs went at 720).
		local inset = UDim2.fromOffset(-outward.X * (thickness + slack), -outward.Y * (thickness + slack))
		corners[corner + 1] = create("Frame")({
			AnchorPoint = anchor,
			Position = UDim2.new(right, outward.X * slack, bottom, outward.Y * slack),
			Size = window or UDim2.fromOffset(leg + slack, leg + slack),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			Visible = if isSealed
				then function()
					return not isSealed()
				end
				else nil,
			create("Frame")({
				AnchorPoint = anchor,
				Position = UDim2.fromScale(right, bottom) + inset,
				Size = outline or UDim2.fromOffset(2 * leg, 2 * leg),
				BackgroundTransparency = 1,
				create("UICorner")({ CornerRadius = UDim.new(0, Look.BRACKET_RADIUS) }),
				create("UIStroke")({
					Color = Palette.White,
					Thickness = thickness,
					Transparency = strokeAlpha or alpha,
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				}),
			}),
		})
	end

	-- Sealed, one outline instead of four quarters, so no join is ever drawn; it thickens as it seals, and the joins
	-- flash where the legs met.
	local whole = nil
	if seal and isSealed then
		local isWelding = vide.derive(function(): boolean
			return seal() > 0.01
		end)
		whole = {
			create("Frame")({
				Name = "Whole",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(1, -2 * thickness, 1, -2 * thickness),
				BackgroundTransparency = 1,
				Visible = isSealed,
				create("UICorner")({ CornerRadius = UDim.new(0, Look.BRACKET_RADIUS) }),
				create("UIStroke")({
					Color = Palette.White,
					Thickness = function()
						return thickness + Merge.THICKEN * seal()
					end,
					Transparency = Look.BRACKET_CLOSED_TRANSPARENCY,
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				}),
			}),
			create("Frame")({
				Name = "Welds",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Visible = isWelding,
				weld(0, seal, thickness),
				weld(1, seal, thickness),
				weld(2, seal, thickness),
				weld(3, seal, thickness),
			}),
		}
	end

	return create("Frame")({
		Name = "Brackets",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = if outset
			then function()
				local px = outset()
				return UDim2.new(1, px * 2, 1, px * 2)
			end
			else UDim2.new(1, Look.BRACKET_OUTSET * 2, 1, Look.BRACKET_OUTSET * 2),
		BackgroundTransparency = 1,
		ZIndex = 0,
		corners,
		whole,
	})
end

-- A spec's Brackets as Components.Brackets takes them: true for still brackets, or a source of the hand's rise that
-- opens them.
local function riseOf(brackets: any): (() -> number)?
	return if type(brackets) == "function" then brackets else nil
end

-- Two rounded Ls in the bottom corners of a face (`isTop` adds the top two), `inset` px in: the marks his slabs and
-- tinted cards carry.
local function marks(color: any, transparency: number, inset: number, leg: number, isTop: boolean): Frame
	local bars = {}
	local count = 0
	for corner = if isTop then 0 else 2, 3 do
		local right = corner % 2
		local bottom = corner // 2
		local anchor = Vector2.new(right, bottom)
		local at = UDim2.new(right, if right == 1 then -inset else inset, bottom, if bottom == 1 then -inset else inset)
		for _, size in { UDim2.fromOffset(leg, 2), UDim2.fromOffset(2, leg) } do
			count += 1
			bars[count] = create("Frame")({
				AnchorPoint = anchor,
				Position = at,
				Size = size,
				BackgroundColor3 = color,
				BackgroundTransparency = transparency,
				BorderSizePixel = 0,
				create("UICorner")({ CornerRadius = UDim.new(0, 1) }),
			})
		end
	end

	return create("Frame")({
		Name = "Marks",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		bars,
	})
end

-- The streaks across a face (Icons.PANEL_TEXTURE), clipped to it. `phase` is where in the texture the window starts.
-- `isWide` is a face longer than the texture: it is tiled across it.
local function streaks(phase: Vector2?, isWide: boolean?): Frame
	texturesMade += 1
	local at = phase or Vector2.new((texturesMade * 389) % TEXTURE_PHASES, (texturesMade * 211) % TEXTURE_PHASES)
	local side = Icons.PANEL_TEXTURE_SIZE
	return create("Frame")({
		Name = "Streaks",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		create("ImageLabel")({
			Position = UDim2.fromOffset(-at.X, -at.Y),
			Size = if isWide then UDim2.new(1, at.X, 1, at.Y) else UDim2.fromOffset(side, side),
			BackgroundTransparency = 1,
			Image = Icons.PANEL_TEXTURE,
			ScaleType = if isWide then Enum.ScaleType.Tile else Enum.ScaleType.Stretch,
			TileSize = UDim2.fromOffset(side, side),
			ImageColor3 = Palette.Lavender,
			ImageTransparency = TEXTURE_TRANSPARENCY,
		}),
	})
end

local function shadow(spec: TProps): UIShadow
	if spec.Glow then
		return create("UIShadow")({
			Name = "Glow",
			BlurRadius = UDim.new(0, Look.GLOW_BLUR),
			Color = spec.Glow,
			Offset = UDim2.fromOffset(0, Look.GLOW_DROP),
			Spread = UDim2.new(),
			Transparency = spec.GlowTransparency or Look.GLOW_TRANSPARENCY,
			ZIndex = -1,
		})
	end

	return create("UIShadow")({
		Name = "Shade",
		BlurRadius = UDim.new(0, Look.SHADE_BLUR),
		Color = Color3.new(),
		Offset = UDim2.fromOffset(0, Look.SHADE_DROP),
		Spread = UDim2.new(),
		Transparency = Look.SHADE_TRANSPARENCY,
		ZIndex = -1,
	})
end

-- The edge as the frame's own background, the face inset by `edge` over it: a UIStroke is drawn outside the frame,
-- and his rects include the edge.
local function face(edge: number, corner: number, keys: any, props: TProps): Frame
	return create("Frame")({
		Name = "Face",
		Position = UDim2.fromOffset(edge, edge),
		Size = UDim2.new(1, -2 * edge, 1, -2 * edge),
		BorderSizePixel = 0,
		create("UICorner")({ CornerRadius = UDim.new(0, math.max(corner - edge, 1)) }),
		Components.Gradient(keys),
		props,
	})
end

-- His dark panel (the WAVE plate, the boss strip, AUTO-SKIP, the money plate, Squad, Settings). `spec` fields may be
-- sources: Stroke (the edge's colour), Glow (a colour, nil for his dark shadow), GlowTransparency, Brackets (true, or
-- the hand's rise to open them by; nil for none), BracketLength, BracketsClosed (true while it is picked: the brackets close into one outline),
-- TexturePhase (a Vector2 for a panel wider than half the texture), Wide (true for one longer than the texture), Tall
-- (true for one hundreds of px high). `props` is the outer Frame's, sized to his drawn rect; children are placed
-- against it.
function Components.Panel(spec: TProps, props: TProps): Frame
	local edge = Look.PANEL_EDGE
	return create("Frame")({
		BackgroundColor3 = spec.Stroke or Palette.EdgePink,
		BorderSizePixel = 0,
		create("UICorner")({ CornerRadius = UDim.new(0, Look.PANEL_CORNER) }),
		create("UIGradient")({
			Rotation = 90,
			Color = ColorSequence.new(Palette.White, Color3.new(Look.EDGE_BOTTOM, Look.EDGE_BOTTOM, Look.EDGE_BOTTOM)),
		}),
		shadow(spec),
		face(edge, Look.PANEL_CORNER, if spec.Tall then PANEL_FACE_TALL else PANEL_FACE, {
			streaks(spec.TexturePhase, spec.Wide),
			create("Frame")({
				Name = "Shine",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(1, 0, 0, 1),
				BackgroundColor3 = Look.SHINE,
				BorderSizePixel = 0,
			}),
		}),
		if spec.Brackets
			then Components.Brackets(riseOf(spec.Brackets), nil, spec.BracketLength, spec.BracketsClosed)
			else nil,
		props,
	})
end

-- His accent card (HEAL ALL, the upgrade and ability cards, the hotbar slots). `spec` fields may be sources: Accent,
-- Tint (how far the bottom warms toward the accent, 0 to 1), Band (px of dark name band at the bottom, nil for none),
-- Marks (the faint corner marks low in the face), Glow / GlowTransparency (the accent's glow by default), Brackets,
-- BracketLength, BracketTransparency, BracketsClosed, Edge (px, where his is not the cards' 3), Wide (true for a face
-- longer than the streak texture), Tall (true for one hundreds of px high), Face (the dark of the face, where his is
-- not the cards' own). `props` is the outer Frame's, sized to his drawn rect.
function Components.Card(spec: TProps, props: TProps): Frame
	local edge = spec.Edge or Look.CARD_EDGE
	local band = spec.Band
	return create("Frame")({
		BackgroundColor3 = spec.Accent,
		BorderSizePixel = 0,
		create("UICorner")({ CornerRadius = UDim.new(0, Look.PANEL_CORNER) }),
		-- His edge is a little darker at the top than the bottom.
		create("UIGradient")({
			Rotation = 90,
			Color = ColorSequence.new(Color3.new(0.88, 0.88, 0.88), Palette.White),
		}),
		shadow({
			Glow = spec.Glow or spec.Accent,
			GlowTransparency = spec.GlowTransparency,
		}),
		face(edge, Look.PANEL_CORNER, function()
			local accent = read(spec.Accent)
			local dark = spec.Face or Look.CARD_FACE
			local warm = dark:Lerp(accent, read(spec.Tint) or 0.25)
			-- The lip is a few px whatever the card's height: on one hundreds of px tall a share of it is a band.
			local lip = if spec.Tall then 0.25 else 1
			return {
				{ 0, Look.LIP },
				{ 0.03 * lip, Look.LIP },
				{ 0.06 * lip, Look.FACE_TOP },
				{ 0.15 * lip, dark },
				{ 0.45, dark:Lerp(accent, Look.CARD_TINT_MID) },
				{ if band then 0.74 else 0.99, warm },
				{ 1, warm },
			}
		end, {
			streaks(nil, spec.Wide),
			if band
				then create("Frame")({
					Name = "Band",
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.fromScale(0, 1),
					Size = UDim2.new(1, 0, 0, band),
					BorderSizePixel = 0,
					BackgroundColor3 = function()
						return Look.CARD_BAND:Lerp(read(spec.Accent), 0.03)
					end,
				})
				else nil,
			if spec.Marks
				then marks(function()
					return Look.CARD_FACE:Lerp(read(spec.Accent), 0.2)
				end, 0.4, 3, 22, false)
				else nil,
		}),
		if spec.Brackets
			then Components.Brackets(
				riseOf(spec.Brackets),
				spec.BracketTransparency or 0.65,
				spec.BracketLength or 23,
				spec.BracketsClosed
			)
			else nil,
		props,
	})
end

-- His glossy slab (SKIP WAVE, the countdown, the money packs, the squad screen's header): a dark rim, a hot pink edge
-- and a green, gold or pink face. `spec` fields may be sources: Kind ("Go", "Gold", "Pink", "Violet", "Steel", "Red" or "Off"), Marks (the corner
-- marks inside), GlowTransparency, Brackets, BracketsClosed. `props` is the outer Frame's, sized to his drawn rect.
function Components.Slab(spec: TProps, props: TProps): Frame
	local kind = function(): string
		return read(spec.Kind) or "Go"
	end

	return create("Frame")({
		BackgroundColor3 = Look.SLAB_RIM,
		BorderSizePixel = 0,
		create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
		create("UIShadow")({
			Name = "Glow",
			BlurRadius = UDim.new(0, Look.GLOW_BLUR),
			Color = function()
				return if kind() == "Off" then Color3.new() else Palette.Pink
			end,
			Offset = UDim2.fromOffset(0, Look.GLOW_DROP),
			Spread = UDim2.new(),
			Transparency = spec.GlowTransparency or Look.SLAB_GLOW_TRANSPARENCY,
			ZIndex = -1,
		}),
		create("Frame")({
			Name = "Edge",
			Position = UDim2.fromOffset(1, 1),
			Size = UDim2.new(1, -2, 1, -2),
			BorderSizePixel = 0,
			create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
			Components.Gradient(function()
				return if kind() == "Off" then SLAB_EDGE_OFF else SLAB_EDGE
			end),
			face(Look.SLAB_EDGE, 3, function()
				return SLAB_FACES[kind()]
			end, {
				if spec.Marks
					then marks(function()
						return SLAB_MARKS[kind()]
					end, 0.25, 3, 16, true)
					else nil,
			}),
		}),
		if spec.Brackets then Components.Brackets(riseOf(spec.Brackets), 0.45, 21, spec.BracketsClosed) else nil,
		props,
	})
end

-- A colour toward black: `share` of it kept.
local function shade(color: Color3, share: number): Color3
	return Color3.new(color.R * share, color.G * share, color.B * share)
end

-- His lobby slab (WEAPONS, PLAY, CLASSES): the glossy slab's dark rim and hot pink edge round a FLAT face of `spec.Face`,
-- shaded for a few px under the top edge, dark corner marks in all four corners, and a glow in the face's own colour.
-- `spec` fields may be sources: GlowTransparency, Brackets (true, or the hand's rise), BracketTransparency,
-- BracketsClosed. `props` is the outer Frame's, sized to his drawn rect.
function Components.FlatSlab(spec: TProps, props: TProps): Frame
	local color: Color3 = spec.Face
	local under = shade(color, Look.FLAT_SHADE)
	return create("Frame")({
		BackgroundColor3 = Look.SLAB_RIM,
		BorderSizePixel = 0,
		create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
		create("UIShadow")({
			Name = "Glow",
			BlurRadius = UDim.new(0, Look.GLOW_BLUR),
			Color = color,
			Offset = UDim2.fromOffset(0, Look.GLOW_DROP),
			Spread = UDim2.new(),
			Transparency = spec.GlowTransparency or Look.GLOW_TRANSPARENCY,
			ZIndex = -1,
		}),
		create("Frame")({
			Name = "Edge",
			Position = UDim2.fromOffset(1, 1),
			Size = UDim2.new(1, -2, 1, -2),
			BorderSizePixel = 0,
			create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
			Components.Gradient(SLAB_EDGE),
			face(Look.SLAB_EDGE, 3, {
				{ 0, under },
				{ Look.FLAT_SHADE_DEPTH, under },
				{ Look.FLAT_SHADE_END, color },
				{ 1, color },
			}, {
				marks(shade(color, Look.FLAT_MARK), 0.25, 3, Look.FLAT_MARK_LEG, true),
			}),
		}),
		if spec.Brackets
			then Components.Brackets(
				riseOf(spec.Brackets),
				spec.BracketTransparency,
				Look.FLAT_BRACKET_LENGTH,
				spec.BracketsClosed
			)
			else nil,
		props,
	})
end

-- His currency pill (the lobby's coins and energy): a dark rim, a bright lip along the top of `spec.Lip` and darker
-- sides and bottom round a face of `spec.Face` shaded under the top, faint corner marks, and his gold glow under it.
-- `spec` fields: Brackets (true, or the hand's rise), BracketsClosed, GlowTransparency (may be a source). `props` is the outer
-- Frame's, sized to his drawn rect.
function Components.Pill(spec: TProps, props: TProps): Frame
	local color: Color3 = spec.Face
	local under = shade(color, Look.PILL_SHADE)
	return create("Frame")({
		BackgroundColor3 = shade(color, Look.PILL_RIM),
		BorderSizePixel = 0,
		create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
		create("UIShadow")({
			Name = "Glow",
			BlurRadius = UDim.new(0, Look.GLOW_BLUR),
			Color = Palette.Gold,
			Offset = UDim2.fromOffset(0, Look.GLOW_DROP),
			Spread = UDim2.new(),
			Transparency = spec.GlowTransparency or Look.PILL_GLOW_TRANSPARENCY,
			ZIndex = -1,
		}),
		create("Frame")({
			Name = "Edge",
			Position = UDim2.fromOffset(1, 1),
			Size = UDim2.new(1, -2, 1, -2),
			BorderSizePixel = 0,
			create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			Components.Gradient({
				{ 0, spec.Lip },
				{ 0.04, spec.Lip },
				{ 0.06, shade(color, Look.PILL_SIDE) },
				{ 0.9, shade(color, Look.PILL_SIDE) },
				{ 1, shade(color, Look.PILL_BOTTOM) },
			}),
			face(2, 2, {
				{ 0, under },
				{ 0.035, under },
				{ 0.075, color },
				{ 1, color },
			}, {
				marks(shade(color, Look.PILL_MARK), 0.55, 2, Look.PILL_MARK_LEG, true),
			}),
		}),
		if spec.Brackets
			then Components.Brackets(riseOf(spec.Brackets), nil, Look.PILL_BRACKET_LENGTH, spec.BracketsClosed)
			else nil,
		props,
	})
end

-- His grey-edged ink square (the vote count, the keybind badges). `props` is the outer Frame's.
function Components.Plaque(props: TProps): Frame
	return create("Frame")({
		BackgroundColor3 = Look.PLAQUE_EDGE,
		BorderSizePixel = 0,
		create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
		create("Frame")({
			Name = "Face",
			Position = UDim2.fromOffset(1, 1),
			Size = UDim2.new(1, -2, 1, -2),
			BackgroundColor3 = Look.PLAQUE_FACE,
			BorderSizePixel = 0,
			create("UICorner")({ CornerRadius = UDim.new(0, 1) }),
		}),
		props,
	})
end

-- The number row by its digit, whatever the board prints for it.
local DIGITS = table.freeze({
	[Enum.KeyCode.One] = "1",
	[Enum.KeyCode.Two] = "2",
	[Enum.KeyCode.Three] = "3",
	[Enum.KeyCode.Four] = "4",
	[Enum.KeyCode.Five] = "5",
})

-- The letter the player's board prints on the key (AZERTY's A for KeyCode.Q), or the key's name.
local function keyLabel(keyCode: Enum.KeyCode): string
	local digit = DIGITS[keyCode]
	if digit then return digit end
	local printed = UserInputService:GetStringForKeyCode(keyCode)
	return string.upper(if printed ~= "" then printed else keyCode.Name)
end

-- A keybind badge, his grey-edged ink square with the key's letter. `key` is an Enum.KeyCode or a source of one or
-- nil; nil hides it.
function Components.KeyBadge(key: any, size: number, props: TProps?): Frame
	local name = if type(key) == "function"
		then function(): string
			local current = key()
			return if current then keyLabel(current) else ""
		end
		elseif key then keyLabel(key)
		else ""
	return Components.Plaque({
		Size = UDim2.fromOffset(size, size),
		Visible = if type(key) == "function"
			then function()
				return key() ~= nil
			end
			else key ~= nil,
		create("TextLabel")({
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			FontFace = Font.Display,
			TextSize = math.round(size * 0.63),
			TextColor3 = Palette.White,
			Text = name,
			ZIndex = 2,
		}),
		props or NO_PROPS,
	})
end

-- A word with its letters spaced `tracking` px further apart than the font sets them, as his slab words are. The
-- letters are white; `props` is the row's (a TextColor3 there colours nothing: pass `Color`, a Color3 or a source, and
-- `TextTransparency`). The row sits at ZIndex 4, over a slab's face, unless `props` says otherwise.
function Components.Tracked(text: string, size: number, tracking: number, font: Font, props: TProps): Frame
	local color = props.Color or Palette.White
	local transparency = props.TextTransparency or 0
	local letters = {}
	local count = 0
	-- By character, not byte: a letter may be more than one.
	for _, code in utf8.codes(text) do
		count += 1
		letters[count] = create("TextLabel")({
			LayoutOrder = count,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, size),
			BackgroundTransparency = 1,
			FontFace = font,
			TextSize = size,
			TextColor3 = color,
			TextTransparency = transparency,
			TextYAlignment = Enum.TextYAlignment.Top,
			Text = utf8.char(code),
		})
	end

	local rest = table.clone(props)
	rest.Color = nil
	rest.TextTransparency = nil
	return create("Frame")({
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, size),
		BackgroundTransparency = 1,
		ZIndex = 4,
		create("UIListLayout")({
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, tracking),
		}),
		letters,
		rest,
	})
end

-- His pink EXIT on his 1920 x 1080: its middle, size and word, and how far under its place it starts.
local EXIT = table.freeze({
	MIDDLE = Vector2.new(960, 1005),
	SIZE = Vector2.new(302, 72),
	TEXT = 32,
	RISE = 24,
})

-- The one way out of every lobby screen, in one place on all of them (UI.md, "One way out, in one place"), for a
-- parent laid out on his 1920 x 1080. `gone` is how far it still has to come, 1 to 0: it rises in from under its place
-- as it grows, and shrinks away. It grows rather than fading under a group: it moves under the hand, and a group
-- redraws its whole canvas for every frame of that.
function Components.Exit(gone: () -> number, onPress: () -> (), props: TProps?): TextButton
	local hand = Hand.React("Operate")

	return Components.Button({
		Name = "Exit",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			return UDim2.fromOffset(EXIT.MIDDLE.X, EXIT.MIDDLE.Y + math.round(EXIT.RISE * gone()))
		end,
		Size = UDim2.fromOffset(EXIT.SIZE.X, EXIT.SIZE.Y),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Activated = function()
			hand.Commit()
			onPress()
		end,
		hand.Events,
		create("UIScale")({
			Scale = function()
				return (1 - gone()) * hand.Scale()
			end,
		}),
		Components.Slab({
			Kind = "Pink",
			Marks = true,
			Brackets = hand.Rise,
			GlowTransparency = function()
				return 0.6 - 0.3 * hand.Light()
			end,
		}, {
			Name = "Slab",
			Size = UDim2.fromScale(1, 1),
			Hand.WashLayer(hand, 3, 3),
			Components.Sheen(hand.Glint, 3, EXIT.SIZE.X / EXIT.SIZE.Y),
			Components.Tracked("EXIT", EXIT.TEXT, 2, Font.Display, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
			}),
		}),
		props or NO_PROPS,
	}) :: TextButton
end

-- 12345 -> "12,345".
function Components.Commas(value: number): string
	local text = tostring(math.floor(value))
	local formatted, count = string.gsub(text, "^(-?%d+)(%d%d%d)", "%1,%2")

	while count > 0 do
		formatted, count = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
	end

	return formatted
end

return Components
