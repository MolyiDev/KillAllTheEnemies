--!nonstrict
-- One head tag (UIMatt.md, Player Head Tag), on his drawn rect of 448 x 178 px scaled to the billboard: the class's
-- square and tag, the username, and three chips: the level, the trophies (runs that set a new best wave) and the
-- deaths. A figure that changes punches its chip; the tag pops in as it is made.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)

local create = vide.create
local Palette = Theme.Palette
local Font = Theme.Font

-- What a tag shows of a player, from Profile.Public.
export type TPublic = {
	Level: number,
	ClassId: number,
	Trophies: number,
	Deaths: number,
}

-- His drawn rects in px: the tag, the class square, the name, the class tag, the chips.
local Layout = table.freeze({
	SIZE = Vector2.new(448, 178),
	-- Round the tag inside the billboard, for its brackets and glow.
	ROOM = 24,
	SQUARE = Vector2.new(22, 22),
	SQUARE_SIZE = 96,
	SQUARE_GLYPH = 54,
	NAME = Vector2.new(136, 24),
	NAME_SIZE = Vector2.new(296, 40),
	NAME_TEXT = 36,
	CLASS = Vector2.new(136, 76),
	CLASS_HEIGHT = 28,
	CLASS_PADDING = 14,
	CLASS_TEXT = 15,
	CHIP_Y = 128,
	CHIP_LEFTS = { 22, 158, 294 },
	CHIP_SIZE = Vector2.new(128, 34),
	CHIP_GLYPH = Vector2.new(21, 17),
	CHIP_GLYPH_SIZE = 18,
	CHIP_TEXT_LEFT = 42,
	CHIP_TEXT = 21,
})

local Timing = table.freeze({
	ARRIVE_PERIOD = 0.4,
	ARRIVE_DAMPING = 0.45,
	ARRIVE_FROM = -0.3,
	POP_PERIOD = 0.26,
	POP_DAMPING = 0.4,
	POP = 0.25,
})

-- His chips' edges and how see-through their face is; the class square and tag in his SURVIVOR grey.
local Colors = table.freeze({
	GOLD_EDGE = Color3.fromRGB(144, 109, 45),
	PINK_EDGE = Color3.fromRGB(150, 34, 92),
	CHIP_FACE = 0.3,
	CLASS = Palette.Grey,
})

local Tag = {}

-- The tag's whole box with its room, in px: what the billboard's UIScale fits into it.
Tag.BOX = Layout.SIZE + Vector2.new(2 * Layout.ROOM, 2 * Layout.ROOM)

local function label(props: { [any]: any }): TextLabel
	return create("TextLabel")({
		BackgroundTransparency = 1,
		FontFace = Font.Display,
		TextColor3 = Palette.White,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
		props,
	})
end

-- A chip along the bottom: its glyph and its figure, punched as the figure changes.
local function chip(
	left: number,
	glyph: string,
	glyphColor: Color3,
	edge: Color3,
	textColor: Color3,
	text: () -> string
)
	local pop, strike = Hand.Kick(Timing.POP_PERIOD, Timing.POP_DAMPING)
	local last: string? = nil
	vide.effect(function()
		local current = text()
		vide.untrack(function()
			if last and current ~= last then strike(1) end
			last = current
		end)
	end)

	return create("Frame")({
		Name = glyph,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(left + Layout.CHIP_SIZE.X / 2, Layout.CHIP_Y + Layout.CHIP_SIZE.Y / 2),
		Size = UDim2.fromOffset(Layout.CHIP_SIZE.X, Layout.CHIP_SIZE.Y),
		BackgroundColor3 = Palette.Ink,
		BackgroundTransparency = Colors.CHIP_FACE,
		BorderSizePixel = 0,
		ZIndex = 3,
		create("UIStroke")({
			Color = edge,
			Thickness = 1.5,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		create("UIScale")({
			Scale = function()
				return 1 + Timing.POP * pop()
			end,
		}),
		Components.Icon(glyph, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(Layout.CHIP_GLYPH.X, Layout.CHIP_GLYPH.Y),
			Size = Components.GlyphBox(Layout.CHIP_GLYPH_SIZE),
			ImageColor3 = glyphColor,
			ZIndex = 4,
		}),
		label({
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, Layout.CHIP_TEXT_LEFT, 0.5, 0),
			Size = UDim2.fromOffset(Layout.CHIP_SIZE.X - Layout.CHIP_TEXT_LEFT - 6, Layout.CHIP_TEXT),
			TextSize = Layout.CHIP_TEXT,
			TextColor3 = textColor,
			Text = text,
		}),
	})
end

-- The tag of `name`, showing `public` (a source; nil until the server has said). Sized SIZE plus ROOM all round, held
-- by its middle so its arrival grows from there.
function Tag.Build(name: string, public: () -> TPublic?): Frame
	local arrive, strikeArrive = Hand.Kick(Timing.ARRIVE_PERIOD, Timing.ARRIVE_DAMPING)
	strikeArrive(Timing.ARRIVE_FROM)
	local class = function()
		local figures = public()
		return if figures then DataCore.Classes.ById[figures.ClassId] else nil
	end
	local function figure(key: string): () -> string
		return function(): string
			local figures = public()
			return if figures then Components.Commas(figures[key]) else "-"
		end
	end

	return create("Frame")({
		Name = "Tag",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(Layout.SIZE.X + 2 * Layout.ROOM, Layout.SIZE.Y + 2 * Layout.ROOM),
		BackgroundTransparency = 1,
		create("UIScale")({
			Scale = function()
				return 1 + arrive()
			end,
		}),
		Components.Panel({ Brackets = 5 }, {
			Name = "Panel",
			Position = UDim2.fromOffset(Layout.ROOM, Layout.ROOM),
			Size = UDim2.fromOffset(Layout.SIZE.X, Layout.SIZE.Y),
			Components.Card({
				Accent = Colors.CLASS,
				Tint = 0.5,
				Edge = 3,
				Marks = true,
				Brackets = 4,
				BracketLength = 16,
			}, {
				Name = "ClassSquare",
				Position = UDim2.fromOffset(Layout.SQUARE.X, Layout.SQUARE.Y),
				Size = UDim2.fromOffset(Layout.SQUARE_SIZE, Layout.SQUARE_SIZE),
				ZIndex = 3,
				Components.Icon("Helmet", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = Components.GlyphBox(Layout.SQUARE_GLYPH),
					ImageColor3 = Palette.White,
					ZIndex = 4,
				}),
			}),
			label({
				Name = "Name",
				Position = UDim2.fromOffset(Layout.NAME.X, Layout.NAME.Y),
				Size = UDim2.fromOffset(Layout.NAME_SIZE.X, Layout.NAME_SIZE.Y),
				TextScaled = true,
				TextYAlignment = Enum.TextYAlignment.Center,
				Text = string.upper(name),
				create("UITextSizeConstraint")({ MaxTextSize = Layout.NAME_TEXT }),
			}),
			create("Frame")({
				Name = "ClassTag",
				Position = UDim2.fromOffset(Layout.CLASS.X, Layout.CLASS.Y),
				Size = UDim2.fromOffset(0, Layout.CLASS_HEIGHT),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundColor3 = Colors.CLASS,
				BorderSizePixel = 0,
				ZIndex = 3,
				Visible = function()
					return class() ~= nil
				end,
				create("UIPadding")({
					PaddingLeft = UDim.new(0, Layout.CLASS_PADDING),
					PaddingRight = UDim.new(0, Layout.CLASS_PADDING),
				}),
				label({
					Size = UDim2.fromScale(0, 1),
					AutomaticSize = Enum.AutomaticSize.X,
					TextSize = Layout.CLASS_TEXT,
					TextColor3 = Palette.Ink,
					Text = function()
						local current = class()
						return if current then string.upper(current.Name) else ""
					end,
				}),
			}),
			chip(Layout.CHIP_LEFTS[1], "Rank", Palette.Gold, Colors.GOLD_EDGE, Palette.Gold, function(): string
				local figures = public()
				return if figures then `LV {figures.Level}` else "LV -"
			end),
			chip(Layout.CHIP_LEFTS[2], "Star", Palette.Gold, Colors.GOLD_EDGE, Palette.Gold, figure("Trophies")),
			chip(Layout.CHIP_LEFTS[3], "Skull", Palette.Pink, Colors.PINK_EDGE, Palette.White, figure("Deaths")),
		}),
	})
end

return Tag
