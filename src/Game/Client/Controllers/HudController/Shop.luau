--!nonstrict
-- The ABILITIES column on the right (UIMatt.md, Abilities), his cards on his drawn rects: the class's two abilities,
-- then his ULT card with its charge bar beside it, for the class's ultimate, and CHARGE NOW under them. The run's
-- defenses are not offered for now.
-- Each card draws its ability as AbilityPicture does, as the lobby's classes screen does.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local AbilityPicture = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.AbilityPicture)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local GemPayout = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.GemPayout)
local Upgrades = require(script.Parent.Upgrades)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)
local EProducts = require(ReplicatedStorage.Types.Enums.EProducts)
local Types = require(script.Parent.Types)

local create = vide.create
local Palette = Theme.Palette
local Font = Theme.Font

-- His drawn rects at 1080: the cards' left edge from the screen's right, the first card's top and the step down, the
-- title's right edge and top; inside a card the key, price, name, band and glyph; the charge bar beside the ULT card.
local RIGHT = 190
local TOP = 336
local CARD = 150
-- 169, not his 166: under a press a card's brackets reach 13 px out, and at his they crossed the next card's.
local STEP = 169
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
-- An ability's model on its card: the box it is fitted to (its centre is the glyph's).
local PICTURE = 100
-- What the model does on its card: grown with the card's rise under the pointer, punched and swung as the ability is
-- used and as it comes ready (shares of its size, deg), and on the ULT card breathing while it waits to be fired.
local Gesture = table.freeze({
	HOVER = 0.08,
	USED_POP = 0.26,
	USED_SPIN = -16,
	READY_POP = 0.3,
	READY_SPIN = 14,
	BREATH = 0.06,
	BREATH_SPIN = 4,
})
-- 10 px further out than his 234: at his, the ULT card under the hand grew into the gold tag.
local CHARGE_RIGHT = 244
local CHARGE_BAR = Vector2.new(6, 32)
local CHARGE_BAR_SIZE = Vector2.new(26, 118)
local CHARGE_TAG = Vector2.new(38, 26)
local CHARGE_TEXT = 16
local CHARGE_EDGE = Color3.fromRGB(144, 109, 44)
-- A bolt landing whitens the bar's fill and its tag this much, falling off over LANDED_SECONDS: landings 30 to 70 ms
-- apart keep it hot for the whole stream, a colour and never a kick.
local LANDED_SECONDS = 0.22
local LANDED_FILL = 0.75
local LANDED_TAG = 0.55
-- CHARGE NOW, a gold slab under the ULT card and its bar, from the bar's left edge to the card's right. Its top stands
-- 24 under the card: the card's brackets reach 13 px at a press, the price tag rises 9 over the slab, and 2 px of air
-- (UI.md, "Brackets, picked and side by side").
local BUY_RIGHT = RIGHT - CARD
local BUY_GAP = 24
local BUY = Vector2.new(CHARGE_RIGHT - BUY_RIGHT, 56)
local BUY_BOLT = Vector2.new(25, 28)
local BUY_BOLT_SIZE = 38
local BUY_TEXT_LEFT = 46
local BUY_TEXT = 20
-- Offered from this round on.
local BUY_FROM_ROUND = 11
local BUY_PRICE = "R$ 19"
local BUY_TAG_WIDTH = 60
-- Room round the slab for its glow, brackets and tag while it fades in a group that clips.
local BUY_MARGIN = 32
-- In and out of the way (before its round, once the meter is full or the beam is out): faded, grown from this and
-- risen this far on a calm spring, never past the mark.
local BUY_AWAY_SCALE = 0.75
local BUY_AWAY_DROP = 10
local BUY_PERIOD = 0.45
-- The slab as a bought fill arrives: it swells, goes white, and the light crosses it as its bolt flares and throws.
local BOUGHT_SECONDS = 0.5
local BOUGHT_POP = 0.12
local BOUGHT_FLASH = 0.8
local BOUGHT_BOLT_POP = 0.45
-- Under the hand: how much the bolt grows with the slab's rise.
local BOLT_RISE = 0.18
-- A bought fill's flight is counted in thousandths of the meter: its pieces are 4 + the root of the amount
-- (GemPayout), so a fill from 60% up flies the most (24) and even the last tenth flies 14.
local FLIGHT_UNITS = 1000
-- A refused click shakes the card this far to each side (Motion.Shake).
local JOLT = 7
local JOLT_SECONDS = 0.16
local PLACED_SECONDS = 0.4
local PLACING_HZ = 1.6
-- The ULT card as its meter fills: the pop, the light across it.
local CHARGED_SECONDS = 0.5
-- An ability's card as it is used and as it comes ready, and how dark its cooldown's shade is.
local USED_SECONDS = 0.3
local USED_DIP = 0.1
local READY_POP = 0.14
local SHADE = 0.3

local Shop = {}

-- How far from the screen's right edge the column reaches at the bottom (its charge bar and CHARGE NOW), for what
-- shares the corner (the debug readout) to stand clear of.
Shop.CORNER = CHARGE_RIGHT

-- The model of ability `kind` where a card's glyph sits (AbilityPicture). `spec` holds sources: Rotation (a turn in
-- the card's plane, deg), Transparency and Scale. The Decoy is the player's own avatar once `doll` has one.
local function modelPicture(kind: string, spec: { [string]: any }, doll: (() -> Model?)?): Frame
	return AbilityPicture.Build(kind, spec, doll, {
		Position = UDim2.fromOffset(GLYPH.X, GLYPH.Y),
		Size = UDim2.fromOffset(PICTURE, PICTURE),
		ZIndex = 3,
	})
end

-- An ability's card: in its own colour with its price in Gold while it can be used; steel when the Gold is short, and
-- under a shade that drains off the top with the seconds left while it cools. A use punches it down and flashes it, the moment it is ready again it pops
-- with a light across its face, and a press it refuses knocks it sideways.
local function abilityCard(state: Types.THudState, actions: Types.TActions, index: number): TextButton
	local ability = state.Abilities[index]
	local isCooling = function(): boolean
		return ability.Cooling() > 0
	end

	local canUse = function(): boolean
		return not isCooling() and state.Gold() >= ability.Cost()
	end
	local hand = Hand.React("Take", canUse)

	local used = function(): number
		local k = Motion.Fade(state.Now(), ability.UsedAt(), USED_SECONDS)
		return k * k
	end

	-- 0 to 1 through the moment it comes ready; 1 at rest.
	local ready = function(): number
		return Motion.Progress(state.Now(), ability.ReadyAt(), CHARGED_SECONDS)
	end

	local jolt = function(): number
		local at = ability.DeniedAt()
		return JOLT * Motion.Shake(Motion.Progress(state.Now(), at, JOLT_SECONDS), at)
	end

	return Components.Button({
		Name = `Ability{index}`,
		Position = UDim2.new(1, -RIGHT, 0, TOP + STEP * (index - 1)),
		Size = UDim2.fromOffset(CARD, CARD),
		BackgroundTransparency = 1,
		Activated = function()
			hand.Commit()
			actions.CastAbility(ability.Slot)
		end,
		hand.Events,
		Components.Card({
			Accent = function()
				return if canUse() then ability.Accent else Palette.Steel
			end,
			Band = BAND,
			Brackets = hand.Rise,
			BracketTransparency = function()
				return 0.65 - 0.35 * hand.Light()
			end,
			GlowTransparency = function()
				if not canUse() then return 0.9 end
				local pop = 1 - ready()
				return 0.7 - math.max(0.5 * pop * pop, 0.4 * hand.Light())
			end,
		}, {
			Name = "Card",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			Position = function()
				return UDim2.new(0.5, math.round(jolt()), 0.5, 0)
			end,
			create("UIScale")({
				Scale = function()
					local pop = 1 - ready()
					return hand.Scale() - USED_DIP * used() + READY_POP * pop * pop
				end,
			}),
			modelPicture(ability.Kind, {
				Transparency = function()
					return if isCooling() then 0.3 elseif canUse() then 0 else 0.25
				end,
				Rotation = function()
					return Gesture.USED_SPIN
							* Motion.Swing(Motion.Progress(state.Now(), ability.UsedAt(), CHARGED_SECONDS))
						+ Gesture.READY_SPIN * Motion.Swing(ready())
				end,
				Scale = function()
					local pop = 1 - ready()
					return 1 + Gesture.HOVER * hand.Rise() + Gesture.USED_POP * used() + Gesture.READY_POP * pop * pop
				end,
			}, if ability.Kind == "Decoy" then state.Avatar else nil),
			create("TextLabel")({
				Name = "State",
				Position = UDim2.fromOffset(PRICE.X, PRICE.Y),
				Size = UDim2.new(1, -PRICE.X, 0, PRICE_TEXT),
				BackgroundTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				FontFace = Font.Display,
				TextSize = PRICE_TEXT,
				ZIndex = 4,
				TextColor3 = function()
					if isCooling() then return Palette.White end
					return Palette.Gold:Lerp(Palette.Pink, Motion.Fade(state.Now(), ability.DeniedAt(), 0.5))
				end,
				TextTransparency = function()
					return if isCooling() or canUse() then 0 else 0.35
				end,
				AutoLocalize = false,
				Text = function()
					return if isCooling() then `{ability.Seconds()}s` else `${Components.Commas(ability.Cost())}`
				end,
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
				ZIndex = 4,
				Text = string.upper(ability.Name),
				create("UITextSizeConstraint")({ MaxTextSize = NAME_TEXT }),
			}),
			-- The cooldown, behind the model and over the rest of the picture's ground, not the name band: full as the
			-- ability is used, draining off the top.
			create("Frame")({
				Name = "Shade",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 0, 1, -BAND),
				BackgroundColor3 = Palette.Ink,
				BackgroundTransparency = SHADE,
				BorderSizePixel = 0,
				ZIndex = 2,
				Visible = isCooling,
				Size = function()
					return UDim2.new(1, 0, 0, math.round((CARD - BAND) * ability.Cooling()))
				end,
			}),
			Components.KeyBadge(ability.Key, KEY_SIZE, {
				Position = UDim2.fromOffset(KEY.X, KEY.Y),
				ZIndex = 5,
			}),
			Components.Sheen(Hand.Sheen(hand, ready), 4),
			create("Frame")({
				Name = "Flash",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Palette.White,
				BorderSizePixel = 0,
				ZIndex = 5,
				BackgroundTransparency = function()
					local pop = 1 - ready()
					return 1 - math.max(0.6 * used(), 0.45 * pop * pop, hand.Wash())
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
			}),
		}),
	}) :: TextButton
end

-- His ULT card and the charge bar beside it, for the class's ultimate, and the bar's well. Steel while the meter fills (the bar climbing
-- with every kill, the tag counting the percent); gold, breathing and reading READY once it is full; a flash as it is
-- used, and the bar then drains with what is left of it. A press it refuses knocks the card sideways.
local function ultimate(state: Types.THudState, actions: Types.TActions, top: number): ({ Frame }, Frame)
	local ult = state.Ultimate
	local hand = Hand.React("Take", ult.IsReady)

	local isLit = function(): boolean
		return ult.IsReady() or ult.Burning() > 0
	end

	local breath = function(): number
		if not ult.IsReady() then return 0 end
		return 0.5 + 0.5 * math.sin(state.Breath() * math.pi * 2 * PLACING_HZ)
	end

	local used = function(): number
		local k = Motion.Fade(state.Now(), ult.UsedAt(), PLACED_SECONDS)
		return k * k
	end

	-- The moment the meter fills: 0 to 1 over the gesture, 1 at rest.
	local charged = function(): number
		return Motion.Progress(state.Now(), ult.ChargedAt(), CHARGED_SECONDS)
	end

	local jolt = function(): number
		local at = ult.DeniedAt()
		return JOLT * Motion.Shake(Motion.Progress(state.Now(), at, JOLT_SECONDS), at)
	end

	local fill = function(): number
		local burning = ult.Burning()
		return if burning > 0 then burning else ult.Charge()
	end

	-- 1 as a bought bolt lands in the bar, falling off.
	local landed = function(): number
		local k = Motion.Fade(state.Now(), ult.LandedAt(), LANDED_SECONDS)
		return k * k
	end

	local card = Components.Button({
		Name = "Ultimate",
		Position = UDim2.new(1, -RIGHT, 0, top),
		Size = UDim2.fromOffset(CARD, CARD),
		BackgroundTransparency = 1,
		Activated = function()
			hand.Commit()
			actions.CastAbility(ult.Slot)
		end,
		hand.Events,
		Components.Card({
			Accent = function()
				return if isLit() then Palette.Gold else Palette.Steel
			end,
			Band = BAND,
			Brackets = hand.Rise,
			BracketTransparency = function()
				return 0.65 - 0.35 * hand.Light()
			end,
			GlowTransparency = function()
				if not isLit() then return 0.9 end
				return 0.7 - math.max(0.35 * breath(), 0.5 * used(), 0.5 * (1 - charged()), 0.4 * hand.Light())
			end,
		}, {
			Name = "Card",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			Position = function()
				return UDim2.new(0.5, math.round(jolt()), 0.5, 0)
			end,
			create("UIScale")({
				Scale = function()
					local pop = 1 - charged()
					return hand.Scale() + 0.1 * used() + 0.14 * pop * pop
				end,
			}),
			modelPicture(ult.Kind, {
				Transparency = function()
					return if isLit() then 0 else 0.2
				end,
				Rotation = function()
					return Gesture.BREATH_SPIN * (2 * breath() - 1) * (if ult.IsReady() then 1 else 0)
						+ Gesture.READY_SPIN * Motion.Swing(charged())
						+ Gesture.USED_SPIN
							* Motion.Swing(Motion.Progress(state.Now(), ult.UsedAt(), CHARGED_SECONDS))
				end,
				Scale = function()
					local pop = 1 - charged()
					return 1
						+ Gesture.HOVER * hand.Rise()
						+ Gesture.BREATH * breath()
						+ Gesture.USED_POP * used()
						+ Gesture.READY_POP * pop * pop
				end,
			}),
			create("TextLabel")({
				Name = "State",
				Position = UDim2.fromOffset(PRICE.X, PRICE.Y),
				Size = UDim2.new(1, -PRICE.X, 0, PRICE_TEXT),
				BackgroundTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				FontFace = Font.Display,
				TextSize = PRICE_TEXT,
				ZIndex = 3,
				TextColor3 = function()
					return if isLit() then Palette.Gold else Palette.Lavender
				end,
				Text = function()
					return if ult.IsReady() then "READY" else "ULT"
				end,
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
				Text = string.upper(ult.Name),
				create("UITextSizeConstraint")({ MaxTextSize = NAME_TEXT }),
			}),
			Components.KeyBadge(ult.Key, KEY_SIZE, {
				Position = UDim2.fromOffset(KEY.X, KEY.Y),
				ZIndex = 3,
			}),
			Components.Sheen(Hand.Sheen(hand, charged), 4),
			create("Frame")({
				Name = "Flash",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Palette.White,
				BorderSizePixel = 0,
				ZIndex = 4,
				BackgroundTransparency = function()
					local pop = 1 - charged()
					return 1 - math.max(0.6 * used(), 0.5 * pop * pop, hand.Wash())
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
			}),
		}),
	})

	-- Inside the bar's edge, where the fill climbs (and a bought fill's bolts land).
	local well = create("Frame")({
		Name = "Well",
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(1, -4, 1, -4),
		BackgroundColor3 = Palette.Ink,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		create("Frame")({
			Name = "Fill",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			BorderSizePixel = 0,
			Size = function()
				return UDim2.fromScale(1, fill())
			end,
			BackgroundColor3 = function()
				return Palette.Gold:Lerp(Palette.White, math.max(0.5 * breath(), 1 - charged(), LANDED_FILL * landed()))
			end,
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
			well,
		}),
		create("Frame")({
			Name = "Tag",
			Size = UDim2.fromOffset(CHARGE_TAG.X, CHARGE_TAG.Y),
			BackgroundColor3 = function()
				return Palette.Gold:Lerp(Palette.White, LANDED_TAG * landed())
			end,
			BorderSizePixel = 0,
			ZIndex = 2,
			create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			create("TextLabel")({
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				FontFace = Font.Display,
				TextSize = CHARGE_TEXT,
				TextColor3 = Palette.Ink,
				AutoLocalize = false,
				Text = function()
					return tostring(math.floor(ult.Charge() * 100))
				end,
			}),
		}),
	})

	return { card, charge }, well
end

-- CHARGE NOW: a gold slab like the Gold packs, its bolt and its price, prompting the product. It comes in from
-- BUY_FROM_ROUND while the meter fills and goes once it is full or the beam is out. A bought fill punches it white with
-- a light across it, its bolt flares, and the bolts thrown from it (chargeFlight) fill the bar. Returns its fading
-- pair (Components.FadeGroup) and the bolt, where the flight sets off.
local function chargeNow(state: Types.THudState, actions: Types.TActions, top: number): ({ Instance }, GuiObject)
	local ult = state.Ultimate
	-- Derived: Burning moves every step of a beam, and what hangs off this should wake only when the answer flips.
	local isOffered = vide.derive(function(): boolean
		local phase = state.Phase()
		if phase ~= "Preparing" and phase ~= "Fighting" then return false end
		if state.Round() < BUY_FROM_ROUND then return false end
		return not ult.IsReady() and ult.Burning() == 0
	end)
	local shown = Hand.Spring(function()
		return if isOffered() then 1 else 0
	end, BUY_PERIOD, 1)
	local hand = Hand.React("Take", isOffered)

	-- 0 to 1 through the moment a bought fill arrives; 1 at rest. Derived, so the frames it is not moving redraw nothing.
	local bought = vide.derive(function(): number
		return Motion.Progress(state.Now(), ult.BoughtAt(), BOUGHT_SECONDS)
	end)
	local pop = function(): number
		local k = 1 - bought()
		return k * k
	end

	local bolt = Components.Picture(EIcons.EnergyBolt, {
		Name = "Bolt",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(BUY_BOLT.X, BUY_BOLT.Y),
		Size = Components.PictureBox(BUY_BOLT_SIZE),
		ZIndex = 3,
		create("UIScale")({
			Scale = function()
				return 1 + BOLT_RISE * hand.Rise() + BOUGHT_BOLT_POP * pop()
			end,
		}),
	})

	local slab = Components.Button({
		Name = "ChargeNow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			local drop = math.round(BUY_AWAY_DROP * (1 - shown()))
			return UDim2.fromOffset(BUY_MARGIN + BUY.X / 2, BUY_MARGIN + BUY.Y / 2 + drop)
		end,
		Size = UDim2.fromOffset(BUY.X, BUY.Y),
		BackgroundTransparency = 1,
		Activated = function()
			if not isOffered() then return end
			hand.Commit()
			actions.BuyProduct(EProducts.ChargeUltimate)
		end,
		hand.Events,
		create("UIScale")({
			Scale = function()
				return Motion.Lerp(BUY_AWAY_SCALE, 1, shown()) * hand.Scale() + BOUGHT_POP * pop()
			end,
		}),
		Components.Slab({
			Kind = "Gold",
			Marks = true,
			Brackets = hand.Rise,
			GlowTransparency = function()
				return 0.6 - math.max(0.35 * hand.Light(), 0.4 * pop())
			end,
		}, {
			Size = UDim2.fromScale(1, 1),
			create("Frame")({
				Name = "Flash",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Palette.White,
				BorderSizePixel = 0,
				ZIndex = 5,
				BackgroundTransparency = function()
					return 1 - math.max(BOUGHT_FLASH * pop(), hand.Wash())
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
			}),
			create("Frame")({
				Name = "SheenWindow",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ClipsDescendants = true,
				ZIndex = 5,
				Components.Sheen(Hand.Sheen(hand, bought), 5),
			}),
			bolt,
			create("TextLabel")({
				Name = "Label",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, BUY_TEXT_LEFT, 0.5, 0),
				Size = UDim2.new(1, -BUY_TEXT_LEFT, 0, BUY_TEXT),
				BackgroundTransparency = 1,
				FontFace = Font.Display,
				TextSize = BUY_TEXT,
				TextColor3 = Palette.White,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 3,
				Text = "CHARGE NOW",
			}),
			Upgrades.PriceTag(BUY_TAG_WIDTH, BUY_PRICE),
		}),
	})

	local group = Components.FadeGroup("ChargeNow", shown, {
		Position = UDim2.new(1, -BUY_RIGHT - BUY.X - BUY_MARGIN, 0, top - BUY_MARGIN),
		Size = UDim2.fromOffset(BUY.X + 2 * BUY_MARGIN, BUY.Y + 2 * BUY_MARGIN),
		Visible = function()
			return shown() > 0.01
		end,
	}, { slab })

	return group, bolt
end

-- What carries a bought fill into the bar: `Layer` goes in a full-screen frame with no scale of its own (GemPayout),
-- `Step` moves it each frame, `Throw` sets it off from CHARGE NOW's bolt with the meter's share before the buy,
-- calling `onLand` with the share of the meter still in the air at each landing (0 on the last).
export type TChargeFlight = {
	Layer: Frame,
	Step: (now: number) -> boolean,
	Throw: (fromShare: number, now: number, onLand: (owed: number) -> ()) -> (),
}

-- The bolts land up the bar's well from where the fill stood to its top, one after another, so the bar climbs to full
-- as they arrive.
local function chargeFlight(state: Types.THudState, bolt: GuiObject, well: GuiObject): TChargeFlight
	local fromShare = 0
	local payout = GemPayout.Build(state.Scale, function(share: number): Vector2?
		if not well.Parent then return nil end
		local head = fromShare + (1 - fromShare) * share
		local at, size = well.AbsolutePosition, well.AbsoluteSize
		return at + Vector2.new(size.X / 2, size.Y * (1 - head))
	end, EIcons.EnergyBolt, "Reel")

	return {
		Layer = payout.Layer,
		Step = payout.Step,
		Throw = function(share: number, now: number, onLand: (owed: number) -> ())
			fromShare = share
			local units = math.max(math.round((1 - share) * FLIGHT_UNITS), 1)
			payout.Burst(bolt.AbsolutePosition + bolt.AbsoluteSize / 2, units, now, function(owed: number)
				onLand(owed / FLIGHT_UNITS)
			end)
		end,
	}
end

-- The column, and the flight a bought fill takes into the ULT card's bar (nil with no CHARGE NOW product).
function Shop.Abilities(state: Types.THudState, actions: Types.TActions): (Frame, TChargeFlight?)
	local cards = table.create(#state.Abilities)
	for index in state.Abilities do
		cards[index] = abilityCard(state, actions, index)
	end

	local ultTop = TOP + STEP * #state.Abilities
	local ultimateCard, well = ultimate(state, actions, ultTop)
	local buy, flight = nil, nil
	if state.Ultimate.CanBuy then
		local bolt
		buy, bolt = chargeNow(state, actions, ultTop + CARD + BUY_GAP)
		flight = chargeFlight(state, bolt, well)
	end

	local column = create("Frame")({
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
		ultimateCard,
		buy,
	})

	return column, flight
end

return Shop
