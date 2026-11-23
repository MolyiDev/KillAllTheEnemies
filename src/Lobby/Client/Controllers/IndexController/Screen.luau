--!nonstrict
-- The index screen on his 1920 x 1080: the lobby dimmed as his lobby screens dim it, the title, the categories
-- (Categories), the enemy grid (Grid), the picked enemy's stage and info (Info) and EXIT. The HUD's pills stay up over
-- it. Pieces arrive staged by what the screen is for: the grid, then the categories and the stage, the info, the
-- title, and EXIT last.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local Categories = require(script.Parent.Categories)
local Grid = require(script.Parent.Grid)
local Info = require(script.Parent.Info)
local Parts = require(script.Parent.Parts)
local Types = require(script.Parent.Types)

local create = vide.create
local Palette = Theme.Palette
local Font = Theme.Font
local Label = Parts.Label

-- His drawn rects in px at 1080, from the screen's top left.
local Layout = table.freeze({
	TITLE_GLYPH = Vector2.new(63, 68),
	TITLE_GLYPH_SIZE = 34,
	TITLE = Vector2.new(96, 40),
	TITLE_TEXT = 55,
	SUBTITLE_GLYPH = Vector2.new(105.5, 110),
	SUBTITLE_GLYPH_TEXT = 17,
	SUBTITLE = Vector2.new(120, 101),
	SUBTITLE_TEXT = 17,
	EXIT = Vector2.new(809, 969),
	EXIT_SIZE = Vector2.new(302, 72),
	EXIT_TEXT = 32,
})

local Timing = table.freeze({
	-- His lobby screens dim the world this much (UIMatt.md section 2: 0.7 transparent).
	DIM = 0.3,
	TITLE_DELAY = 0.14,
	TITLE_SLIDE = 22,
	EXIT_DELAY = 0.28,
	EXIT_RISE = 24,
})

local Screen = {}

local function title(state: Types.TIndexState, elapsed: () -> number): Frame
	local away = Parts.Away(state, elapsed, Timing.TITLE_DELAY)
	local faded = Parts.Faded(state, elapsed, Timing.TITLE_DELAY)

	return create("Frame")({
		Name = "Title",
		Position = function()
			return UDim2.fromOffset(-math.round(Timing.TITLE_SLIDE * away()), 0)
		end,
		Size = UDim2.fromOffset(420, 130),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Components.Icon("Skull", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(Layout.TITLE_GLYPH.X, Layout.TITLE_GLYPH.Y),
			Size = Components.GlyphBox(Layout.TITLE_GLYPH_SIZE),
			ImageColor3 = Palette.Pink,
			ImageTransparency = faded,
		}),
		Label({
			Position = UDim2.fromOffset(Layout.TITLE.X, Layout.TITLE.Y),
			Size = UDim2.fromOffset(320, Layout.TITLE_TEXT),
			TextSize = Layout.TITLE_TEXT,
			TextTransparency = faded,
			Text = "INDEX",
		}),
		Label({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(Layout.SUBTITLE_GLYPH.X, Layout.SUBTITLE_GLYPH.Y),
			Size = UDim2.fromOffset(Layout.SUBTITLE_GLYPH_TEXT, Layout.SUBTITLE_GLYPH_TEXT),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextSize = Layout.SUBTITLE_GLYPH_TEXT,
			TextColor3 = Palette.Gold,
			TextTransparency = faded,
			Text = "?",
		}),
		Label({
			Position = UDim2.fromOffset(Layout.SUBTITLE.X, Layout.SUBTITLE.Y),
			Size = UDim2.fromOffset(300, Layout.SUBTITLE_TEXT),
			FontFace = Font.DisplayBold,
			TextSize = Layout.SUBTITLE_TEXT,
			TextColor3 = Palette.Gold,
			TextTransparency = faded,
			Text = "DISCOVER EVERY ENEMY",
		}),
	})
end

-- EXIT grows in rather than fading under a group: it moves under the hand, and a group redraws its whole canvas for
-- every frame of that.
local function exit(state: Types.TIndexState, actions: Types.TIndexActions, elapsed: () -> number): TextButton
	local hand = Hand.React("Operate")
	local away = Parts.Away(state, elapsed, Timing.EXIT_DELAY)

	return Components.Button({
		Name = "Exit",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			return UDim2.fromOffset(
				Layout.EXIT.X + Layout.EXIT_SIZE.X / 2,
				Layout.EXIT.Y + Layout.EXIT_SIZE.Y / 2 + math.round(Timing.EXIT_RISE * away())
			)
		end,
		Size = UDim2.fromOffset(Layout.EXIT_SIZE.X, Layout.EXIT_SIZE.Y),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Activated = function()
			hand.Commit()
			actions.Close()
		end,
		hand.Events,
		create("UIScale")({
			Scale = function()
				return (1 - away()) * hand.Scale()
			end,
		}),
		Components.Slab({
			Kind = "Pink",
			Marks = true,
			Brackets = function()
				return 5 + 3 * hand.Rise()
			end,
			GlowTransparency = function()
				return 0.6 - 0.3 * hand.Light()
			end,
		}, {
			Name = "Slab",
			Size = UDim2.fromScale(1, 1),
			Hand.WashLayer(hand, 3, 3),
			Components.Sheen(hand.Glint, 3),
			Components.Tracked("EXIT", Layout.EXIT_TEXT, 2, Font.Display, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				ZIndex = 4,
			}),
		}),
	}) :: TextButton
end

function Screen.Build(state: Types.TIndexState, actions: Types.TIndexActions): { any }
	local elapsed = Parts.Elapsed(state)
	local dimFaded = Parts.Faded(state, elapsed, 0)

	return {
		-- Past the screen's edges whatever its shape, and it takes the clicks the pieces do not: this is a page, so a
		-- click on nothing shuts nothing.
		create("TextButton")({
			Name = "Dim",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(4, 4),
			BackgroundColor3 = Color3.new(),
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			BackgroundTransparency = function()
				return 1 - Timing.DIM * (1 - dimFaded())
			end,
		}),
		title(state, elapsed),
		Categories.Build(state, actions, elapsed),
		Grid.Build(state, actions, elapsed),
		Info.Build(state, actions, elapsed),
		exit(state, actions, elapsed),
	}
end

return Screen
