--!nonstrict
-- What a code paid, as the spins screen's prize cards (gold for Gems, blue for XP): dealt up into the panel's new room a
-- beat apart, each landing with a flash while its number counts up from nothing. Only the kinds the code paid are dealt,
-- centred under the field.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local Types = require(script.Parent.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress

-- The spins screen's card, px at 1080 from its top left.
local Layout = table.freeze({
	CARD = Vector2.new(150, 164),
	PITCH = 166,
	-- 6 out, so two cards 16 apart keep their corners apart (his 8 met).
	BRACKET_LENGTH = 22,
	GLYPH_Y = 37,
	GLYPH = 36,
	VALUE_Y = 72,
	VALUE_TEXT = 38,
	WORD_Y = 114,
	WORD_TEXT = 14,
	BAR_Y = 143,
	BAR = Vector2.new(90, 4),
	-- Room round a card inside the group that fades it, for its glow and brackets.
	MARGIN = 40,
})

local Timing = table.freeze({
	DEAL_STAGGER = 0.1,
	DEAL = 0.42,
	DEAL_RISE = 40,
	DEAL_GROW = 0.14,
	-- When it reads as landed, from its deal: its flash goes off then.
	LANDED = 0.25,
	-- The flash as it lands, and its number running up.
	FLASH = 0.35,
	FLASH_STRENGTH = 0.6,
	COUNT_DELAY = 0.12,
	COUNT = 0.6,
})

-- The spins screen's card colours and how they are worn.
local GEMS = Palette.Gold
local XP = Color3.fromRGB(89, 191, 255)
local EDGE_SHARE = 0.85
local TINT = 0.4
local GLOW_TRANSPARENCY = 0.7

local Rewards = {}

-- When the first card's number has run up, from its deal, and how much later each card after it is dealt.
Rewards.COUNTED_SECONDS = Timing.COUNT_DELAY + Timing.COUNT
Rewards.DEAL_STAGGER = Timing.DEAL_STAGGER

local function label(props: { [any]: any }): TextLabel
	return create("TextLabel")({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		FontFace = Font.Display,
		TextColor3 = Palette.White,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 4,
		props,
	})
end

-- Which cards are dealt and in what order: Gems first.
local function order(state: Types.TCodesState): { string }
	local kinds = {}
	if state.Gems() > 0 then table.insert(kinds, "Gems") end
	if state.Xp() > 0 then table.insert(kinds, "Xp") end
	return kinds
end

-- The card for `kind`, on the row whose middle is `center` (px in its parent). `shown` fades it with the screen.
local function card(
	state: Types.TCodesState,
	kind: string,
	center: Vector2,
	shown: () -> number
): (CanvasGroup, ImageLabel)
	local accent = if kind == "Gems" then GEMS else XP
	local edge = Color3.new(accent.R * EDGE_SHARE, accent.G * EDGE_SHARE, accent.B * EDGE_SHARE)
	local amount = if kind == "Gems" then state.Gems else state.Xp
	-- Its place in the deal: 0 for the first, nil when the code did not pay it.
	local rank = derive(function(): number?
		local index = table.find(order(state), kind)
		return if index then index - 1 else nil
	end)
	local dealAt = derive(function(): number
		local at = rank()
		return if at then state.RewardsAt() + Timing.DEAL_STAGGER * at else math.huge
	end)
	local dealt = derive(function(): number
		return Progress(state.Now(), dealAt(), Timing.DEAL)
	end)
	-- Nothing before it lands: Fade reads a moment still to come as its peak.
	local flash = derive(function(): number
		local landAt = dealAt() + Timing.LANDED
		local now = state.Now()
		return if now < landAt then 0 else Motion.Fade(now, landAt, Timing.FLASH)
	end)
	local counted = derive(function(): number
		return math.round(amount() * Motion.Out(Progress(state.Now(), dealAt(), Timing.COUNT, Timing.COUNT_DELAY)))
	end)
	-- Where it stands along the row: the row is centred on the cards dealt.
	local offset = derive(function(): number
		local count = #order(state)
		return Layout.PITCH * ((rank() or 0) - (count - 1) / 2)
	end)

	local glyph = Components.Picture(if kind == "Gems" then EIcons.Gem else EIcons.Rank, {
		Name = "Glyph",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(Layout.CARD.X / 2, Layout.GLYPH_Y),
		Size = Components.PictureBox(Layout.GLYPH),
		ZIndex = 4,
	})

	local group = create("CanvasGroup")({
		Name = kind,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			local rise = Timing.DEAL_RISE * (1 - Motion.Decelerate(dealt()))
			return UDim2.fromOffset(math.round(center.X + offset()), math.round(center.Y + rise))
		end,
		Size = UDim2.fromOffset(Layout.CARD.X + 2 * Layout.MARGIN, Layout.CARD.Y + 2 * Layout.MARGIN),
		BackgroundTransparency = 1,
		ZIndex = 4,
		-- Out of the renderer when the code did not pay it: a group at full transparency is still drawn.
		Visible = function()
			return rank() ~= nil
		end,
		GroupTransparency = function()
			return 1 - Motion.Out(dealt()) * shown()
		end,
		create("UIScale")({
			Scale = function()
				return 1 - Timing.DEAL_GROW * (1 - Motion.Decelerate(dealt()))
			end,
		}),
		Components.Card({
			Accent = edge,
			Glow = accent,
			GlowTransparency = function()
				return GLOW_TRANSPARENCY - 0.3 * flash()
			end,
			Tint = TINT,
			Marks = true,
			Brackets = true,
			BracketLength = Layout.BRACKET_LENGTH,
			BracketTransparency = 0.65,
		}, {
			Name = "Card",
			Position = UDim2.fromOffset(Layout.MARGIN, Layout.MARGIN),
			Size = UDim2.fromOffset(Layout.CARD.X, Layout.CARD.Y),
			glyph,
			label({
				Name = "Value",
				Position = UDim2.fromOffset(Layout.CARD.X / 2, Layout.VALUE_Y),
				Size = UDim2.fromOffset(Layout.CARD.X, Layout.VALUE_TEXT),
				TextSize = Layout.VALUE_TEXT,
				TextColor3 = accent,
				Text = function()
					return Components.Commas(counted())
				end,
			}),
			label({
				Name = "Word",
				Position = UDim2.fromOffset(Layout.CARD.X / 2, Layout.WORD_Y),
				Size = UDim2.fromOffset(Layout.CARD.X, Layout.WORD_TEXT),
				TextSize = Layout.WORD_TEXT,
				Text = if kind == "Gems" then "GEMS" else "XP",
			}),
			create("Frame")({
				Name = "Bar",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromOffset(Layout.CARD.X / 2, Layout.BAR_Y),
				Size = UDim2.fromOffset(Layout.BAR.X, Layout.BAR.Y),
				BackgroundColor3 = accent,
				BorderSizePixel = 0,
				ZIndex = 4,
			}),
			create("Frame")({
				Name = "Flash",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Palette.White,
				BorderSizePixel = 0,
				ZIndex = 7,
				Visible = function()
					return flash() > 0.004
				end,
				BackgroundTransparency = function()
					return 1 - Timing.FLASH_STRENGTH * flash()
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
			}),
		}),
	})

	return group, glyph
end

-- The row of cards, centred on `center`. Returns them and the cards' glyphs, where their Gems and XP fly from.
function Rewards.Build(
	state: Types.TCodesState,
	center: Vector2,
	shown: () -> number
): ({ Instance }, ImageLabel, ImageLabel)
	local gems, gemGlyph = card(state, "Gems", center, shown)
	local xp, xpGlyph = card(state, "Xp", center, shown)
	return { gems, xp }, gemGlyph, xpGlyph
end

return Rewards
