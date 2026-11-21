--!nonstrict
-- The ABILITIES column on the right (UIMatt.md, Abilities), his cards on his drawn rects: the run's defenses, then his
-- ULT card with its charge bar beside it (no ultimate exists yet: it is drawn and does nothing). A defense's card is
-- green when it can be bought and steel when it cannot, as his are; it turns gold and pulses while being placed, jolts
-- on a click the purse refuses and punches when one goes down.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local Motion = require(script.Parent.Motion)
local Types = require(script.Parent.Types)
local EDefensesIds = require(ReplicatedStorage.Types.Enums.Data.EDefensesIds)

local create = vide.create
local source = vide.source
local spring = vide.spring
local Palette = Theme.Palette
local Font = Theme.Font

-- His drawn rects at 1080: the cards' left edge from the screen's right, the first card's top and the step down, the
-- title's right edge and top; inside a card the key, price, name, band and glyph; the charge bar beside the ULT card.
local RIGHT = 190
local TOP = 336
local CARD = 150
local STEP = 166
local TITLE_RIGHT = 32
local TITLE_TOP = 302
local TITLE_TEXT = 19
local KEY = Vector2.new(112, 8)
local KEY_SIZE = 30
local PRICE = Vector2.new(12, 81)
local PRICE_TEXT = 28
local NAME = Vector2.new(12, 120)
local NAME_TEXT = 19
local BAND = 35
local GLYPH = Vector2.new(75, 58)
local GLYPH_SIZE = 72
local CHARGE_RIGHT = 234
local CHARGE_BAR = Vector2.new(6, 32)
local CHARGE_BAR_SIZE = Vector2.new(26, 118)
local CHARGE_TAG = Vector2.new(38, 26)
local CHARGE_TEXT = 16
local CHARGE_EDGE = Color3.fromRGB(144, 109, 44)
-- A refused click knocks the card sideways this far and stops dead (UI.md 5c: a jolt, not a swing).
local JOLT = 7
local JOLT_SECONDS = 0.16
local PLACED_SECONDS = 0.4
local PLACING_HZ = 1.6

-- The picture on each defense's card. One with no picture yet shows its price and name only.
local ICONS: { [number]: string } = {
	[EDefensesIds.EnergyBarricade] = "Barricade",
}

local Shop = {}

local function defenseCard(state: Types.THudState, actions: Types.TActions, index: number): TextButton
	local defense = state.Defenses[index]
	local isHovered = source(false)
	local isPressed = source(false)
	local isFull = function()
		return defense.Count() >= defense.Limit
	end

	local canPlace = function()
		return state.Gold() >= defense.Cost and not isFull()
	end

	local lift = spring(function()
		if isPressed() then return 0.95 end
		return if isHovered() then 1.04 else 1
	end, 0.17, 0.82)

	local jolt = function(): number
		local t = Motion.Progress(state.Now(), defense.DeniedAt(), JOLT_SECONDS)
		if t >= 1 then return 0 end
		-- One knock out and back, damped hard.
		return JOLT * math.sin(t * math.pi * 2) * (1 - t)
	end

	local placed = function(): number
		local k = Motion.Fade(state.Now(), defense.PlacedAt(), PLACED_SECONDS)
		return k * k
	end

	local pulse = function(): number
		if not defense.IsPlacing() then return 0 end
		return 0.5 + 0.5 * math.sin(state.Now() * math.pi * 2 * PLACING_HZ)
	end

	local accent = function(): Color3
		if defense.IsPlacing() then return Palette.Gold end
		return if canPlace() then Palette.Green else Palette.Steel
	end

	local denied = function(): number
		return Motion.Fade(state.Now(), defense.DeniedAt(), 0.5)
	end

	local icon = ICONS[defense.DataId]
	return Components.Button({
		Name = `Defense{defense.DataId}`,
		Position = UDim2.new(1, -RIGHT, 0, TOP + STEP * (index - 1)),
		Size = UDim2.fromOffset(CARD, CARD),
		BackgroundTransparency = 1,
		Activated = function()
			actions.PlaceDefense(defense.DataId)
		end,
		MouseEnter = function()
			isHovered(true)
		end,
		MouseLeave = function()
			isHovered(false)
			isPressed(false)
		end,
		MouseButton1Down = function()
			isPressed(true)
		end,
		MouseButton1Up = function()
			isPressed(false)
		end,
		Components.Card({
			Accent = accent,
			Band = BAND,
			GlowTransparency = function()
				if defense.IsPlacing() then return 0.7 - 0.3 * pulse() end
				return 0.7 - 0.4 * placed()
			end,
			Brackets = 8,
		}, {
			Name = "Card",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			Position = function()
				return UDim2.new(0.5, math.round(jolt()), 0.5, 0)
			end,
			create("UIScale")({
				Scale = function()
					return lift() + 0.08 * placed()
				end,
			}),
			if icon
				then Components.Icon(icon, {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(GLYPH.X, GLYPH.Y),
					Size = Components.GlyphBox(GLYPH_SIZE),
					ZIndex = 2,
					ImageTransparency = function()
						return if canPlace() or defense.IsPlacing() then 0 else 0.4
					end,
				})
				else nil,
			create("TextLabel")({
				Name = "Count",
				Position = UDim2.fromOffset(12, 10),
				Size = UDim2.fromOffset(60, 16),
				BackgroundTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Left,
				FontFace = Font.Display,
				TextSize = 14,
				ZIndex = 3,
				TextColor3 = function()
					return if isFull() then Palette.Pink else Palette.Lavender
				end,
				Text = function()
					return if isFull() then "MAX" else `{defense.Count()}/{defense.Limit}`
				end,
			}),
			create("TextLabel")({
				Name = "Price",
				Position = UDim2.fromOffset(PRICE.X, PRICE.Y),
				Size = UDim2.new(1, -PRICE.X, 0, PRICE_TEXT),
				BackgroundTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				FontFace = Font.Display,
				TextSize = PRICE_TEXT,
				ZIndex = 3,
				TextColor3 = function()
					return Palette.Gold:Lerp(Palette.Pink, denied())
				end,
				TextTransparency = function()
					return if defense.IsPlacing() then 1 elseif canPlace() then 0 else 0.35
				end,
				Text = `${Components.Commas(defense.Cost)}`,
			}),
			create("TextLabel")({
				Name = "Placing",
				Position = UDim2.fromOffset(PRICE.X, PRICE.Y + 6),
				Size = UDim2.new(1, -PRICE.X, 0, 16),
				BackgroundTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Left,
				FontFace = Font.Display,
				TextSize = 14,
				TextColor3 = Palette.Gold,
				ZIndex = 3,
				Visible = defense.IsPlacing,
				Text = `CLICK · {state.Keys.Turn.Name} TURN`,
			}),
			create("TextLabel")({
				Name = "Name",
				Position = UDim2.fromOffset(NAME.X, NAME.Y),
				Size = UDim2.new(1, -NAME.X - 6, 0, NAME_TEXT),
				BackgroundTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				FontFace = Font.Display,
				TextScaled = true,
				TextColor3 = Palette.White,
				ZIndex = 3,
				Text = string.upper(defense.Name),
				create("UITextSizeConstraint")({ MaxTextSize = NAME_TEXT }),
			}),
			Components.KeyBadge(defense.Key, KEY_SIZE, {
				Position = UDim2.fromOffset(KEY.X, KEY.Y),
				ZIndex = 3,
			}),
			-- A flash over the card as one goes down.
			create("Frame")({
				Name = "Flash",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Palette.White,
				BorderSizePixel = 0,
				ZIndex = 4,
				BackgroundTransparency = function()
					return 1 - 0.55 * placed()
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
			}),
		}),
	}) :: TextButton
end

-- His ULT card and the charge bar beside it. There is no ultimate yet, so it is drawn empty and does nothing.
local function ultimate(top: number): { Frame }
	local card = Components.Card({ Accent = Palette.Gold, Band = BAND, Brackets = 8 }, {
		Name = "Ultimate",
		Position = UDim2.new(1, -RIGHT, 0, top),
		Size = UDim2.fromOffset(CARD, CARD),
		Components.Icon("Airstrike", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(GLYPH.X, GLYPH.Y),
			Size = Components.GlyphBox(GLYPH_SIZE),
			ZIndex = 2,
		}),
		create("TextLabel")({
			Position = UDim2.fromOffset(PRICE.X, PRICE.Y),
			Size = UDim2.new(1, -PRICE.X, 0, PRICE_TEXT),
			BackgroundTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			FontFace = Font.Display,
			TextSize = PRICE_TEXT,
			TextColor3 = Palette.Gold,
			ZIndex = 3,
			Text = "ULT",
		}),
		create("TextLabel")({
			Position = UDim2.fromOffset(NAME.X, NAME.Y),
			Size = UDim2.new(1, -NAME.X, 0, NAME_TEXT),
			BackgroundTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			FontFace = Font.Display,
			TextSize = NAME_TEXT,
			TextColor3 = Palette.White,
			ZIndex = 3,
			Text = "AIRSTRIKE",
		}),
		Components.KeyBadge(Enum.KeyCode.Q, KEY_SIZE, {
			Position = UDim2.fromOffset(KEY.X, KEY.Y),
			ZIndex = 3,
		}),
	})

	local charge = create("Frame")({
		Name = "Charge",
		Position = UDim2.new(1, -CHARGE_RIGHT, 0, top),
		Size = UDim2.fromOffset(CHARGE_TAG.X, CHARGE_BAR.Y + CHARGE_BAR_SIZE.Y),
		BackgroundTransparency = 1,
		create("Frame")({
			Name = "Bar",
			Position = UDim2.fromOffset(CHARGE_BAR.X, CHARGE_BAR.Y),
			Size = UDim2.fromOffset(CHARGE_BAR_SIZE.X, CHARGE_BAR_SIZE.Y),
			BackgroundColor3 = CHARGE_EDGE,
			BorderSizePixel = 0,
			create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			create("Frame")({
				Position = UDim2.fromOffset(2, 2),
				Size = UDim2.new(1, -4, 1, -4),
				BackgroundColor3 = Palette.Ink,
				BackgroundTransparency = 0.15,
				BorderSizePixel = 0,
			}),
		}),
		create("Frame")({
			Name = "Tag",
			Size = UDim2.fromOffset(CHARGE_TAG.X, CHARGE_TAG.Y),
			BackgroundColor3 = Palette.Gold,
			BorderSizePixel = 0,
			ZIndex = 2,
			create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			create("TextLabel")({
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				FontFace = Font.Display,
				TextSize = CHARGE_TEXT,
				TextColor3 = Palette.Ink,
				Text = "0",
			}),
		}),
	})

	return { card, charge }
end

function Shop.Defenses(state: Types.THudState, actions: Types.TActions): Frame
	local cards = table.create(#state.Defenses)
	for index in state.Defenses do
		cards[index] = defenseCard(state, actions, index)
	end

	return create("Frame")({
		Name = "Abilities",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = function()
			return state.Phase() ~= "Ended"
		end,
		create("TextLabel")({
			Name = "Title",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -TITLE_RIGHT, 0, TITLE_TOP),
			Size = UDim2.fromOffset(CARD, TITLE_TEXT),
			BackgroundTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextYAlignment = Enum.TextYAlignment.Top,
			FontFace = Font.Display,
			TextSize = TITLE_TEXT,
			TextColor3 = Palette.Lavender,
			Text = "ABILITIES",
		}),
		cards,
		ultimate(TOP + STEP * #state.Defenses),
	})
end

return Shop
