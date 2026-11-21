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
local ESoundsIds = require(ReplicatedStorage.Types.Enums.Sounds.ESoundsIds)
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
-- The corner marks inside a slab, in the face's deep colour.
local SLAB_MARKS = table.freeze({
	Go = Color3.fromRGB(10, 62, 40),
	Gold = Color3.fromRGB(96, 62, 18),
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

-- Ink round a letter of `size`, for text that sits straight on the arena or on a colour it could lose against.
function Components.Ink(size: number): UIStroke
	return create("UIStroke")({
		Color = Color.Ink,
		Thickness = math.max(1, math.round(size * Theme.INK_SHARE)),
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

-- Every button's hover and click sound. Connected in an action rather than as event properties, which the caller's
-- own MouseEnter / Activated would replace; the connections go with the button.
local buttonSounds = action(function(instance: Instance)
	local button = instance :: GuiButton
	button.MouseEnter:Connect(function()
		SoundsCore.PlayUISound(ESoundsIds.HoverHud)
	end)
	button.Activated:Connect(function()
		SoundsCore.PlayUISound(ESoundsIds.ClickHud)
	end)
end)

-- A Block that can be clicked. No AutoButtonColor: the caller decides what a hover looks like.
function Components.Button(props: TProps): TextButton
	return create("TextButton")({
		BackgroundColor3 = Color.Ink,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		buttonSounds,
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

-- A band of white light swept once across its parent as `travel` runs 0 to 1: a surface catching the light as it comes
-- alive. Its strength rides an envelope over the sweep, nothing at either end, so it never sits at a flat alpha and pops
-- off when the sweep settles (UI.md, "A SWEPT band's travel").
function Components.Sheen(travel: () -> number, zIndex: number): Frame
	return create("Frame")({
		Name = "Sheen",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Palette.White,
		BorderSizePixel = 0,
		ZIndex = zIndex,
		BackgroundTransparency = function()
			return 1 - 0.65 * math.sin(math.pi * travel())
		end,
		create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
		create("UIGradient")({
			Rotation = 20,
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

-- An icon from the atlas (Icons), white, tinted by `ImageColor3` in `props`.
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

-- The four corner brackets standing off a panel: a frame `outset` px bigger than its parent on every side, with an L
-- at each corner whose bend is rounded, as his are. Each L is the corner of a rounded outline twice its leg, seen
-- through a window one leg square. `transparency` may be a source; `length` is each leg's, in px.
function Components.Brackets(outset: number, transparency: any?, length: number?): Frame
	local alpha = transparency or Look.BRACKET_TRANSPARENCY
	local leg = length or Look.BRACKET_LENGTH
	local thickness = Look.BRACKET_THICKNESS
	local corners = table.create(4)
	for corner = 0, 3 do
		local right = corner % 2
		local bottom = corner // 2
		local anchor = Vector2.new(right, bottom)
		-- The outline sits a stroke in from the window's corner, so the stroke drawn outside it lands on that corner.
		local inset = UDim2.fromOffset(
			if right == 1 then -thickness else thickness,
			if bottom == 1 then -thickness else thickness
		)
		corners[corner + 1] = create("Frame")({
			AnchorPoint = anchor,
			Position = UDim2.fromScale(right, bottom),
			Size = UDim2.fromOffset(leg, leg),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			create("Frame")({
				AnchorPoint = anchor,
				Position = UDim2.fromScale(right, bottom) + inset,
				Size = UDim2.fromOffset(2 * leg, 2 * leg),
				BackgroundTransparency = 1,
				create("UICorner")({ CornerRadius = UDim.new(0, Look.BRACKET_RADIUS) }),
				create("UIStroke")({
					Color = Palette.White,
					Thickness = thickness,
					Transparency = alpha,
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				}),
			}),
		})
	end

	return create("Frame")({
		Name = "Brackets",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, outset * 2, 1, outset * 2),
		BackgroundTransparency = 1,
		ZIndex = 0,
		corners,
	})
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
local function streaks(phase: Vector2?): Frame
	texturesMade += 1
	local at = phase or Vector2.new((texturesMade * 389) % TEXTURE_PHASES, (texturesMade * 211) % TEXTURE_PHASES)
	return create("Frame")({
		Name = "Streaks",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		create("ImageLabel")({
			Position = UDim2.fromOffset(-at.X, -at.Y),
			Size = UDim2.fromOffset(Icons.PANEL_TEXTURE_SIZE, Icons.PANEL_TEXTURE_SIZE),
			BackgroundTransparency = 1,
			Image = Icons.PANEL_TEXTURE,
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
-- sources: Stroke (the edge's colour), Glow (a colour, nil for his dark shadow), GlowTransparency, Brackets (outset
-- px, nil for none), BracketLength, TexturePhase (a Vector2 for a panel wider than half the texture). `props` is the
-- outer Frame's, sized to his drawn rect; children are placed against it.
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
		face(edge, Look.PANEL_CORNER, PANEL_FACE, {
			streaks(spec.TexturePhase),
			create("Frame")({
				Name = "Shine",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(1, 0, 0, 1),
				BackgroundColor3 = Look.SHINE,
				BorderSizePixel = 0,
			}),
		}),
		if spec.Brackets then Components.Brackets(spec.Brackets, nil, spec.BracketLength) else nil,
		props,
	})
end

-- His accent card (HEAL ALL, the upgrade and ability cards, the hotbar slots). `spec` fields may be sources: Accent,
-- Tint (how far the bottom warms toward the accent, 0 to 1), Band (px of dark name band at the bottom, nil for none),
-- Marks (the faint corner marks low in the face), Glow / GlowTransparency (the accent's glow by default), Brackets,
-- BracketLength, BracketTransparency. `props` is the outer Frame's, sized to his drawn rect.
function Components.Card(spec: TProps, props: TProps): Frame
	local edge = Look.CARD_EDGE
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
			local warm = Look.CARD_FACE:Lerp(accent, read(spec.Tint) or 0.25)
			return {
				{ 0, Look.LIP },
				{ 0.03, Look.LIP },
				{ 0.06, Look.FACE_TOP },
				{ 0.15, Look.CARD_FACE },
				{ 0.45, Look.CARD_FACE:Lerp(accent, Look.CARD_TINT_MID) },
				{ if band then 0.74 else 0.99, warm },
				{ 1, warm },
			}
		end, {
			streaks(nil),
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
			then Components.Brackets(spec.Brackets, spec.BracketTransparency or 0.65, spec.BracketLength or 23)
			else nil,
		props,
	})
end

-- His glossy slab (SKIP WAVE, the countdown, the money packs): a dark rim, a hot pink edge and a green or gold face.
-- `spec` fields may be sources: Kind ("Go", "Gold" or "Off"), Marks (the corner marks inside), GlowTransparency,
-- Brackets. `props` is the outer Frame's, sized to his drawn rect.
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
		if spec.Brackets then Components.Brackets(spec.Brackets, 0.45, 21) else nil,
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
