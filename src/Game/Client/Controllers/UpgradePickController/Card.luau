--!nonstrict
-- One upgrade card as the designer drew it (UIMatt.md, Upgrade Selection), built into the SurfaceGui of the part that
-- carries it (Stage): his rects in px at 1080 from the card's corner, on a canvas MARGIN bigger on every side for the
-- glow and the brackets. The canvas never moves or scales: every bit of the card's motion is the part's. The back is
-- ours (he drew no face-down card): his frame with nothing told, so the rarity is news as it turns over.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Ribbon = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Ribbon)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local UpgradesCore = require(ReplicatedStorage.Shared.Core.UpgradesCore)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local Palette = Theme.Palette
local Font = Theme.Font
local UPGRADES = DataCore.Upgrades.ById
local RARITIES = Theme.RaritiesByNumber

local Card = {}

-- His card's drawn rect, and the room round it on the canvas.
Card.SIZE = Vector2.new(373, 452)
Card.MARGIN = 60
Card.CANVAS = Card.SIZE + Vector2.new(2 * Card.MARGIN, 2 * Card.MARGIN)

local Layout = table.freeze({
	KEY = Vector2.new(25, 24),
	KEY_SIZE = 44,
	-- NEW or the level, on a ribbon across the top right corner where he drew its tag.
	RIBBON_ALONG = 100,
	RIBBON_THICKNESS = 28,
	TAG_TEXT = 16,
	-- The picture's frame and the picture's longer side.
	ICON = Vector2.new(113, 92),
	ICON_SIZE = 148,
	PICTURE = 108,
	NAME_Y = 271,
	NAME_TEXT = 29,
	DESCRIPTION = Vector2.new(30, 312),
	DESCRIPTION_SIZE = Vector2.new(313, 46),
	DESCRIPTION_TEXT = 21,
	RARITY_Y = 390,
	RARITY_HEIGHT = 30,
	RARITY_PAD = 15,
	-- How far the bottom of the face warms toward the rarity, measured off his three.
	TINT = 0.45,
	-- The light that follows the hand across the face: how wide a share of the card its band is, and its strength.
	GLARE_BAND = 0.22,
	GLARE_PEAK = 0.16,
})

local BACK_ACCENT = Color3.fromRGB(120, 108, 150)

-- What a card is told (UpgradePickController writes them). Hover, Shade and Flash are 0 to 1; GlareAt is where the
-- hand is across the card, -1 at its left edge to 1 at its right.
export type TCardState = {
	Key: Enum.KeyCode,
	Id: vide.Source<number>,
	Level: vide.Source<number>,
	Rarity: vide.Source<number>,
	IsFaceUp: vide.Source<boolean>,
	-- Turned up for this hand: its ribbon slaps in as it is first turned up and goes as it is turned down to be redealt.
	IsRevealed: vide.Source<boolean>,
	Hover: vide.Source<number>,
	GlareAt: vide.Source<number>,
	Shade: vide.Source<number>,
	Flash: vide.Source<number>,
}

function Card.RarityColor(rarity: number): Color3
	return RARITIES[rarity].Accent
end

local function text(props: { [any]: any }): TextLabel
	return create("TextLabel")({
		BackgroundTransparency = 1,
		FontFace = Font.Display,
		TextColor3 = Palette.White,
		ZIndex = 3,
		props,
	})
end

-- A small tag in the rarity's colour (the rarity's name): as wide as its word.
local function tag(state: TCardState, label: () -> string, props: { [any]: any }): Frame
	return create("Frame")({
		BorderSizePixel = 0,
		ZIndex = 3,
		BackgroundColor3 = function()
			return Card.RarityColor(state.Rarity())
		end,
		create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
		text({
			Size = UDim2.fromScale(1, 1),
			TextSize = Layout.TAG_TEXT,
			Text = label,
			TextColor3 = function()
				return if RARITIES[state.Rarity()].IsInk then Palette.Ink else Palette.White
			end,
		}),
		props,
	})
end

-- A white light across the face, standing where the hand is. One gradient on one frame: only its Offset moves.
local function glare(state: TCardState): Frame
	local half = Layout.GLARE_BAND / 2
	return create("Frame")({
		Name = "Glare",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Palette.White,
		BorderSizePixel = 0,
		ZIndex = 5,
		BackgroundTransparency = function()
			return 1 - state.Hover()
		end,
		create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
		create("UIGradient")({
			Rotation = 24,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5 - half, 1),
				NumberSequenceKeypoint.new(0.5, 1 - Layout.GLARE_PEAK),
				NumberSequenceKeypoint.new(0.5 + half, 1),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Offset = function()
				return Vector2.new(state.GlareAt() * 0.5, 0)
			end,
		}),
	})
end

local function front(state: TCardState): Frame
	local accent = function(): Color3
		return Card.RarityColor(state.Rarity())
	end
	local data = function()
		return UPGRADES[state.Id()]
	end

	return Components.Card({
		Accent = accent,
		Tint = Layout.TINT,
		Tall = true,
		Marks = true,
		Brackets = true,
		-- His chosen card wears a white frame where the brackets stand: they close into it.
		BracketsClosed = function()
			return state.Hover() > 0.5
		end,
		GlowTransparency = function()
			return 0.7 - 0.35 * state.Hover() - 0.3 * state.Flash()
		end,
	}, {
		Name = "Front",
		Position = UDim2.fromOffset(Card.MARGIN, Card.MARGIN),
		Size = UDim2.fromOffset(Card.SIZE.X, Card.SIZE.Y),
		Visible = state.IsFaceUp,
		Components.KeyBadge(state.Key, Layout.KEY_SIZE, {
			Position = UDim2.fromOffset(Layout.KEY.X, Layout.KEY.Y),
			ZIndex = 3,
		}),
		Ribbon.Build({
			Corner = "TopRight",
			Text = function()
				local level = state.Level()
				return if level > 1 then `LV {level}` else "NEW"
			end,
			Color = accent,
			IsInk = function()
				return RARITIES[state.Rarity()].IsInk
			end,
			IsShown = state.IsRevealed,
			Along = Layout.RIBBON_ALONG,
			Thickness = Layout.RIBBON_THICKNESS,
			TextSize = Layout.TAG_TEXT,
			ZIndex = 4,
		}),
		Components.Card({
			Accent = accent,
			Tint = 0.3,
			Brackets = true,
			BracketLength = 18,
		}, {
			Name = "Picture",
			Position = UDim2.fromOffset(Layout.ICON.X, Layout.ICON.Y),
			Size = UDim2.fromOffset(Layout.ICON_SIZE, Layout.ICON_SIZE),
			ZIndex = 3,
			Components.Picture(function()
				local upgrade = data()
				return if upgrade then upgrade.Icon else EIcons.GoldCoin
			end, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = Components.PictureBox(Layout.PICTURE),
				ZIndex = 3,
			}),
		}),
		text({
			Name = "Name",
			Position = UDim2.fromOffset(0, Layout.NAME_Y),
			Size = UDim2.new(1, 0, 0, Layout.NAME_TEXT),
			TextSize = Layout.NAME_TEXT,
			Text = function()
				local upgrade = data()
				return if upgrade then string.upper(upgrade.Name) else ""
			end,
		}),
		text({
			Name = "Description",
			Position = UDim2.fromOffset(Layout.DESCRIPTION.X, Layout.DESCRIPTION.Y),
			Size = UDim2.fromOffset(Layout.DESCRIPTION_SIZE.X, Layout.DESCRIPTION_SIZE.Y),
			FontFace = Font.DisplayBold,
			TextSize = Layout.DESCRIPTION_TEXT,
			TextColor3 = Palette.Lavender,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			Text = function()
				local upgrade = data()
				return if upgrade then UpgradesCore.Describe(upgrade, state.Rarity()) else ""
			end,
		}),
		tag(state, function()
			return RARITIES[state.Rarity()].Text
		end, {
			Name = "Rarity",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, Layout.RARITY_Y),
			Size = UDim2.fromOffset(0, Layout.RARITY_HEIGHT),
			AutomaticSize = Enum.AutomaticSize.X,
			create("UIPadding")({
				PaddingLeft = UDim.new(0, Layout.RARITY_PAD),
				PaddingRight = UDim.new(0, Layout.RARITY_PAD),
			}),
		}),
		glare(state),
		create("Frame")({
			Name = "Shade",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Palette.Ink,
			BorderSizePixel = 0,
			ZIndex = 6,
			BackgroundTransparency = function()
				return 1 - 0.62 * state.Shade()
			end,
			create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
		}),
		create("Frame")({
			Name = "Flash",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Palette.White,
			BorderSizePixel = 0,
			ZIndex = 7,
			BackgroundTransparency = function()
				return 1 - 0.85 * state.Flash()
			end,
			create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
		}),
	})
end

local function back(state: TCardState): Frame
	return Components.Card({
		Accent = BACK_ACCENT,
		Tint = 0.3,
		Tall = true,
		Marks = true,
		Brackets = true,
	}, {
		Name = "Back",
		Position = UDim2.fromOffset(Card.MARGIN, Card.MARGIN),
		Size = UDim2.fromOffset(Card.SIZE.X, Card.SIZE.Y),
		Visible = function()
			return not state.IsFaceUp()
		end,
		Components.Card({
			Accent = BACK_ACCENT,
			Tint = 0.3,
			Brackets = true,
			BracketLength = 18,
		}, {
			Name = "Picture",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(Layout.ICON_SIZE, Layout.ICON_SIZE),
			ZIndex = 3,
			text({
				Size = UDim2.fromScale(1, 1),
				TextSize = 96,
				TextColor3 = Palette.Lavender,
				Text = "?",
			}),
		}),
	})
end

-- The card's two faces, for the root of its SurfaceGui (a frame Card.CANVAS big).
function Card.Build(state: TCardState): { Frame }
	return { front(state), back(state) }
end

return Card
