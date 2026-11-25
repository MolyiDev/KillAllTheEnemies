--!nonstrict
-- The shop's cards, each his accent card at a size that sells what it shows: the hero across the row turning through
-- the featured offers, the two bundles side by side, the Gem packs two by two with the biggest across the row, and the
-- passes (VIP across the row). Every offer stands in a Showcase look of its own (never his plain rings), clipped to
-- the card's face, with ONE kind of thing on show: its own picture, or guns' models, never the two together. A card
-- lights and opens its brackets under the hand without growing (only its price and gift are pressed), deals in through
-- a group of its own while it fades, strikes its worth through and punches its chips as it is first seen, and cheers
-- when what it sells becomes the player's.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local GunPicture = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.GunPicture)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Ribbon = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Ribbon)
local Showcase = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Showcase)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local LoadoutCore = require(ReplicatedStorage.GlobalShared.Core.LoadoutCore)
local ShopCore = require(ReplicatedStorage.GlobalShared.Core.ShopCore)
local Parts = require(script.Parent.Parts)
local Types = require(script.Parent.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
local source = vide.source
local Palette = Theme.Palette
local Font = Theme.Font
local Label = Parts.Label
local Progress = Motion.Progress

-- Sizes in design px.
local Layout = table.freeze({
	FEATURED = Vector2.new(1776, 440),
	-- Taller than his 440 for the arsenal's four guns across the card over the price's row.
	BUNDLE = Vector2.new(876, 520),
	PACK = Vector2.new(876, 230),
	MEGA = Vector2.new(1776, 260),
	PASS = Vector2.new(876, 240),
	PASS_WIDE = Vector2.new(1776, 280),
	-- Inside a card: the left margin, and the price's from the right and bottom edges.
	LEFT = 40,
	RIGHT = 40,
	BOTTOM = 34,
	BIG_TITLE = 72,
	-- The text column of the cards across the row, top to bottom: the tag, the title's two lines, the tags, then up to
	-- three chips, the last ending level with the price's bottom.
	WIDE_TAG = 28,
	WIDE_TITLE = 72,
	WIDE_TAGS = 226,
	WIDE_CHIPS = 276,
	TITLE = 60,
	-- The prices: on the cards across the row, and on the rest.
	BIG_PRICE = Vector2.new(300, 80),
	BIG_PRICE_TEXT = 40,
	PRICE = Vector2.new(240, 66),
	PRICE_TEXT = 32,
	TAG = 36,
	CHIP = 38,
	CHIP_STEP = 46,
	-- VIP's perks: the second column's left from the first's (its longest chip is 413 px).
	PERK_COLUMN = 440,
	RIBBON_ALONG = 104,
	RIBBON_THICKNESS = 36,
	RIBBON_TEXT = 20,
	-- Room round a card in its fading group for its glow (Look.GLOW_BLUR and GLOW_DROP) and its brackets: a group
	-- clips what it draws, and the glow cut off while it fades would pop out whole as it lands.
	FADE_MARGIN = 32,
	-- The card's edge: the art is clipped inside it.
	EDGE = 3,
	-- A title is shrunk to fit this width (a long gun's name), never run under the thing on show.
	TITLE_WIDTH = 640,
	-- The struck worth: over the price on the cards across the row, left of the gift on the rest (out of reach of the
	-- gift's brackets at the peak of a press).
	WAS_TEXT = 26,
	WAS_SMALL_TEXT = 22,
	WAS_OVER = 34,
	WAS_GAP = 20,
	-- The hero: the thing on show and its controls under it (the arrows either side of the pips).
	HERO_X = 1000,
	HERO_Y = 200,
	PIPS_Y = 398,
	PIP = 20,
	PIP_LIT = 64,
	PIP_HEIGHT = 6,
	PIP_HIT = Vector2.new(14, 28),
	ARROW = 44,
	ARROW_GLYPH = 20,
	ARROW_GAP = 16,
	-- The arsenal's guns, two by two across the card.
	CELL = Vector2.new(391, 116),
	CELL_GAP = Vector2.new(14, 12),
	CELLS_TOP = 150,
	-- The gun is fitted to the box's height (about 1/1.2 of it long), so the box stands far past the cell: transparent,
	-- and the cell does not clip. A turn of CELL_TILT keeps a long gun's barrel under the rarity tag.
	CELL_GUN = Vector2.new(360, 312),
	CELL_GUN_AT = Vector2.new(166, 50),
	CELL_TILT = -4,
	-- How far a Gem pack's face warms toward its accent (the other cards' 0.4): the packs are the colour of what they
	-- give.
	PACK_TINT = 0.55,
})

local Timing = table.freeze({
	DEAL = 0.42,
	DEAL_RISE = 36,
	DEAL_FROM = 0.94,
	HOVER_PERIOD = 0.25,
	GLINT = 0.55,
	-- How far a gun on a card turns toward the viewer under the hand, in degrees, and how far a picture lifts.
	HOVER_YAW = 28,
	HOVER_LIFT = 8,
	-- Once a card is first seen: its worth is struck through, its chips punched one after another.
	STRIKE_DELAY = 0.45,
	STRIKE = 0.28,
	CHIPS_DELAY = 0.3,
	CHIPS_STAGGER = 0.07,
	CHIP_POP = 0.3,
	-- A hero page's turn: both pages on one decelerating slide, the title a beat behind and a shorter way, the
	-- accent following the slide.
	PAGE_SLIDE = 0.5,
	TITLE_DELAY = 0.06,
	TITLE_PX = 40,
	PIP_PERIOD = 0.3,
	-- The light crosses a waiting price every CALL_EVERY seconds of the shop's idle clock, CALL_AT into each.
	CALL_EVERY = 3.5,
	CALL_AT = 1.1,
	CALL = 0.6,
})

local LOOKS = Parts.LOOKS

export type TCardSpec = {
	-- The card's top left in the scroll.
	Position: Vector2,
	-- 0 to 1 as it deals in; 1 for a card that was out of view as the screen opened.
	Deal: () -> number,
	-- Whether its art is drawn moving: the screen is up and the card is in the window.
	IsActive: () -> boolean,
	-- os.clock when it was first seen this visit (its deal starting, or scrolled into the window); math.huge before.
	Seen: () -> number,
	IsWide: boolean?,
}

local Cards = {}

Cards.Layout = Layout

-- Seconds since a card was first seen, held once its gestures are over.
local function sinceSeen(state: Types.TShopState, spec: TCardSpec): () -> number
	return derive(function(): number
		return math.clamp(state.Now() - spec.Seen(), 0, 2)
	end)
end

-- The light's travel across a waiting price, off the shop's idle clock (1 between crossings).
local function call(state: Types.TShopState): () -> number
	return derive(function(): number
		local t = (state.PageShown() % Timing.CALL_EVERY - Timing.CALL_AT) / Timing.CALL
		return if t > 0 and t < 1 then t else 1
	end)
end

-- 0 to 1 as a card deals in, `delay` after the screen opens; whole while it shuts (the screen's content fades it).
function Cards.Dealt(state: Types.TShopState, elapsed: () -> number, delay: number): () -> number
	return derive(function(): number
		if not state.IsOpen() then return 1 end
		return Motion.Decelerate(Progress(elapsed(), delay, Timing.DEAL))
	end)
end

-- Between a price and its gift: the price's brackets' reach at the peak of a press (Take, 1.085) with the gift's at
-- rest and 2 px of air (UI.md, "Brackets, picked and side by side"). The gift's own reach is smaller.
local function giftGap(priceWidth: number): number
	return math.ceil(priceWidth / 2 * 0.085 + 6 * 1.085 + 4 + 2)
end

-- What a card's hand does: its light (0 to 1, the brackets open by it), a glint across it each time the hand
-- arrives, and the events for its frame. A card is not a button, so it has no press. `onHover` hears the hand come
-- and go.
local function hover(state: Types.TShopState, actions: Types.TShopActions, onHover: ((boolean) -> ())?)
	local isHovered = source(false)
	local glintAt = source(-math.huge)
	local light = Hand.Spring(function(): number
		return if isHovered() then 1 else 0
	end, Timing.HOVER_PERIOD)
	local glint = derive(function(): number
		return Progress(state.Now(), glintAt(), Timing.GLINT)
	end)
	local events = {
		MouseEnter = function()
			isHovered(true)
			glintAt(os.clock())
			actions.Stir(Timing.GLINT + 0.1)
			if onHover then onHover(true) end
		end,
		MouseLeave = function()
			isHovered(false)
			if onHover then onHover(false) end
		end,
	}

	return { Events = events, Light = light, Glint = glint }
end

-- The card's frame: his accent card, lit by `hand` (its hover), with `cheer` over it, in a group that fades it in as
-- it deals (and only then: at rest it is drawn straight). `children` go on the face; `tint` warms it (0.4 if nil).
local function card(
	state: Types.TShopState,
	hand,
	name: string,
	cheer,
	accent: Color3 | () -> Color3,
	size: Vector2,
	spec: TCardSpec,
	children: { any },
	tint: number?
): Frame
	local light, glint = hand.Light, hand.Glint
	local deal = spec.Deal
	local margin = Layout.FADE_MARGIN

	local face = Components.Card({
		Accent = accent,
		Tint = tint or 0.4,
		Marks = true,
		Wide = size.X > 600,
		Tall = size.Y > 300,
		Brackets = light,
		BracketLength = 30,
		BracketTransparency = function()
			return 0.65 - 0.35 * light()
		end,
		GlowTransparency = function()
			return math.min(0.72 - 0.22 * light() - 0.3 * cheer.Flash(), 1)
		end,
	}, {
		Name = name,
		Position = UDim2.fromOffset(margin, margin),
		Size = UDim2.fromOffset(size.X, size.Y),
		hand.Events,
		Components.Sheen(glint, 7),
		Parts.CheerLayers(cheer, 3, 8),
		children,
	})

	return create("Frame")({
		Name = `{name}Card`,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			return UDim2.fromOffset(
				spec.Position.X + size.X / 2,
				spec.Position.Y + size.Y / 2 + math.round(Timing.DEAL_RISE * (1 - deal()))
			)
		end,
		Size = UDim2.fromOffset(size.X + 2 * margin, size.Y + 2 * margin),
		BackgroundTransparency = 1,
		create("UIScale")({
			Scale = function()
				return (Timing.DEAL_FROM + (1 - Timing.DEAL_FROM) * deal()) * (1 + 0.012 * cheer.Punch())
			end,
		}),
		Components.FadeGroup(name, deal, { Size = UDim2.fromScale(1, 1) }, { face }),
	})
end

-- The Showcase look an offer stands in, its middle at `center` on the card, in two layers clipped to the face: behind
-- the picture, and its particles over it. It comes in as the card deals and cheers as the offer is granted.
local function art(
	state: Types.TShopState,
	spec: { Deal: () -> number, IsActive: () -> boolean },
	offer: ShopCore.TOffer,
	size: Vector2,
	look: {
		Art: string,
		Accent: () -> Color3,
		Center: Vector2,
		Diameter: number,
		Floor: number,
		FloorSize: Vector2?,
	}
): { Instance }
	local edge = Layout.EDGE
	local at = UDim2.fromOffset(look.Center.X - edge, look.Center.Y - edge)
	local back, front = Showcase.Build({
		Look = look.Art,
		Diameter = look.Diameter,
		Floor = look.Floor,
		FloorSize = look.FloorSize,
		Accent = look.Accent,
		Shown = spec.Deal,
		CheeredAt = function(): number
			return state.GrantedAt()[offer.Name] or -math.huge
		end,
		IsActive = spec.IsActive,
	}, { Position = at }, { Position = at })

	local function clipped(name: string, child: Frame?, zIndex: number): Frame?
		if not child then return nil end
		return create("Frame")({
			Name = name,
			Position = UDim2.fromOffset(edge, edge),
			Size = UDim2.fromOffset(size.X - 2 * edge, size.Y - 2 * edge),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = zIndex,
			child,
		})
	end

	return { clipped("Art", back, 2), clipped("ArtFront", front, 4) }
end

-- An offer's own picture, its middle at `center`, `longest` px, lifting and swelling under the hand and punching as it
-- cheers.
local function picture(name: string, center: Vector2, longest: number, light: () -> number, cheer): ImageLabel
	return Components.Picture(name, {
		Name = "Picture",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			return UDim2.fromOffset(center.X, center.Y - math.round(Timing.HOVER_LIFT * light()))
		end,
		Size = Components.PictureBox(longest),
		ZIndex = 3,
		create("UIScale")({
			Scale = function()
				return 1 + 0.06 * light() + 0.12 * cheer.Punch()
			end,
		}),
	})
end

-- A gun's own model in a box, the barrel to the right, turning a little toward the viewer under the hand. The model
-- is fitted to the box's HEIGHT whatever its width (GunPicture's camera), so a long gun drawn big needs a tall box.
-- `tilt` turns it in its plane (GunPicture.CARD_TILT if nil).
local function gun(
	gunName: () -> string,
	light: () -> number,
	center: Vector2,
	size: Vector2,
	zIndex: number,
	tilt: number?
): Frame
	return GunPicture.Build(function()
		local data = LoadoutCore.ByName[gunName()]
		return if data then GunPicture.FromGun(data.Id) else nil
	end, {
		Rotation = tilt or GunPicture.CARD_TILT,
		Yaw = function()
			return Timing.HOVER_YAW * light()
		end,
	}, {
		Name = "Gun",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(center.X, center.Y),
		Size = UDim2.fromOffset(size.X, size.Y),
		ZIndex = zIndex,
		create("UIScale")({
			Scale = function()
				return 1 + 0.06 * light()
			end,
		}),
	})
end

-- The saving sticker across the top right corner, while the offer is not the player's (and, on the hero, while its
-- page is on show: `isOn`).
local function sticker(state: Types.TShopState, offer: ShopCore.TOffer, isOn: (() -> boolean)?): Frame?
	local saving = ShopCore.Saving(offer, os.time())
	if saving < 0.05 then return nil end

	return Ribbon.Build({
		Corner = "TopRight",
		Text = `-{math.floor(saving * 100)}%`,
		Color = Palette.Pink,
		IsShown = function()
			return state.IsOpen() and not Parts.IsOwned(state, offer) and (isOn == nil or isOn())
		end,
		Along = Layout.RIBBON_ALONG,
		Thickness = Layout.RIBBON_THICKNESS,
		TextSize = Layout.RIBBON_TEXT,
		Delay = 0.5,
		CallOrder = 1,
		ZIndex = 7,
	})
end

-- The price in the card's bottom right corner and the gift left of it; `isBig` for the cards across the row. An offer
-- worth more than it costs has its worth struck through (over the price on a big card, left of the gift on the rest),
-- drawn once `since` (seconds since the card or its page came on show) reaches the strike. `called` crosses the price
-- with the shop's call while it waits.
local function buy(
	state: Types.TShopState,
	actions: Types.TShopActions,
	offer: ShopCore.TOffer,
	size: Vector2,
	isBig: boolean,
	since: () -> number,
	called: (() -> number)?
): { Instance }
	local priceSize = if isBig then Layout.BIG_PRICE else Layout.PRICE
	local center = Vector2.new(size.X - Layout.RIGHT - priceSize.X / 2, size.Y - Layout.BOTTOM - priceSize.Y / 2)
	local gift = priceSize.Y
	local giftX = center.X - priceSize.X / 2 - giftGap(priceSize.X) - gift / 2
	local worth = ShopCore.WorthRobux(offer, os.time())

	-- A Gem pack says its bonus in its own tag instead.
	local was = nil
	if offer.Section ~= "Gems" and ShopCore.Saving(offer, os.time()) >= 0.05 then
		local strike = derive(function(): number
			return Motion.Decelerate(Progress(since(), Timing.STRIKE_DELAY, Timing.STRIKE))
		end)
		was = Parts.Was(math.floor(worth), if isBig then Layout.WAS_TEXT else Layout.WAS_SMALL_TEXT, strike, {
			AnchorPoint = if isBig then Vector2.new(0.5, 1) else Vector2.new(1, 0.5),
			Position = if isBig
				then UDim2.fromOffset(center.X, center.Y - priceSize.Y / 2 - Layout.WAS_OVER + Layout.WAS_TEXT)
				else UDim2.fromOffset(giftX - gift / 2 - Layout.WAS_GAP, center.Y),
			Visible = function()
				return not Parts.IsOwned(state, offer)
			end,
		})
	end

	return {
		Parts.Price(
			state,
			actions,
			offer,
			priceSize,
			if isBig then Layout.BIG_PRICE_TEXT else Layout.PRICE_TEXT,
			{ Position = UDim2.fromOffset(center.X, center.Y) },
			called
		),
		Parts.Gift(actions, offer, gift, {
			Position = UDim2.fromOffset(giftX, center.Y),
		}),
		was,
	}
end

-- What an offer gives, one line each, in the order it lists them: a gun with its rarity, a class, its Gems.
local function contents(
	offer: ShopCore.TOffer,
	now: number
): { { Text: string, Kind: string, Color: Color3, IsInk: boolean } }
	local items = {}
	for _, content in offer.Contents do
		if content.Kind == "Gun" or content.Kind == "FeaturedGun" then
			local name = if content.Kind == "Gun" then content.Name :: string else ShopCore.FeaturedGun(now)
			local rarity = Parts.RARITIES[LoadoutCore.ByName[name].Rarity]
			table.insert(items, {
				Text = `+ {string.upper(name)}`,
				Kind = rarity.Text,
				Color = rarity.Accent,
				IsInk = rarity.IsInk,
			})
		elseif content.Kind == "Class" then
			table.insert(items, { Text = "+ HUMAN", Kind = "CLASS", Color = Palette.Pink, IsInk = false })
		elseif content.Kind == "Gems" then
			table.insert(items, {
				Text = `+ {Components.Commas(content.Amount :: number)}`,
				Kind = "GEMS",
				Color = Theme.Color.Gem,
				IsInk = true,
			})
		end
	end

	return items
end

-- A column of what an offer gives from `top`, punched one after another as the card (or its page) comes on show
-- (`since`) and again as it cheers.
local function chips(cheer, since: () -> number, items: { any }, top: number): { Instance }
	local built = {}
	for index, item in items do
		local pop = derive(function(): number
			local stagger = Timing.CHIPS_STAGGER * (index - 1)
			local arrive = Motion.Bump((since() - Timing.CHIPS_DELAY - stagger) / Timing.CHIP_POP)
			local cheered = Motion.Bump((cheer.Since() - 0.1 - stagger) / Timing.CHIP_POP)
			return math.max(arrive, cheered)
		end)
		built[index] = Parts.Pair(item.Text, item.Kind, item.Color, item.IsInk, pop, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(Layout.LEFT, top + Layout.CHIP_STEP * (index - 1) + Layout.CHIP / 2),
		}, Layout.CHIP)
	end

	return built
end

-- A row of tags from (`left`, `top`), left to right.
local function tagRow(left: number, top: number, tags: { Frame }): Frame
	for index, tag in tags do
		tag.LayoutOrder = index
	end

	return create("Frame")({
		Name = "Tags",
		Position = UDim2.fromOffset(left, top),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, Layout.TAG),
		BackgroundTransparency = 1,
		ZIndex = 4,
		create("UIListLayout")({
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 10),
		}),
		tags,
	})
end

-- His two-line title: the first line white, the second in the accent, each shrunk to fit TITLE_WIDTH. `shift` (px)
-- slides both across, for a hero page's title following its page.
local function title(
	first: string | () -> string,
	second: string | () -> string,
	accent: Color3,
	top: number,
	textSize: number,
	shift: (() -> number)?
): { Instance }
	local function line(name: string, y: number, text: string | () -> string, color: Color3): TextLabel
		return Label({
			Name = name,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = if shift
				then function()
					return UDim2.fromOffset(Layout.LEFT - 2 + shift(), y + textSize / 2)
				end
				else UDim2.fromOffset(Layout.LEFT - 2, y + textSize / 2),
			Size = UDim2.fromOffset(Layout.TITLE_WIDTH, textSize),
			TextScaled = true,
			TextColor3 = color,
			Text = text,
			create("UITextSizeConstraint")({ MaxTextSize = textSize }),
		})
	end

	return {
		line("Title1", top, first, Palette.White),
		line("Title2", top + textSize, second, accent),
	}
end

-- Two lines over a wide card's price, centred on it: a small lavender word and a big gold one.
local function overPrice(size: Vector2, small: string, big: string | () -> string): Frame
	local priceX = size.X - Layout.RIGHT - Layout.BIG_PRICE.X / 2
	return create("Frame")({
		Name = "OverPrice",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(priceX, 180),
		Size = UDim2.fromOffset(420, 96),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Label({
			Size = UDim2.fromOffset(420, 22),
			FontFace = Font.DisplayBold,
			TextSize = 22,
			TextColor3 = Palette.Lavender,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = small,
		}),
		Label({
			Position = UDim2.fromOffset(0, 30),
			Size = UDim2.fromOffset(420, 52),
			TextSize = 52,
			TextColor3 = Palette.Gold,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = big,
		}),
	})
end

local function gemsOf(offer: ShopCore.TOffer): number
	for _, content in offer.Contents do
		if content.Kind == "Gems" then return content.Amount end
	end

	return 0
end

local function fixed(color: Color3): () -> Color3
	return function(): Color3
		return color
	end
end

-- ============================== FEATURED ==============================

-- What a hero page is handed: the card's deal (its art comes in with it), seconds since it came on show (the open, or
-- its turn), how far its title trails its page, whether its art moves, the hand's light on the card, and the call
-- across its price.
type TPage = {
	Deal: () -> number,
	Since: () -> number,
	Shift: () -> number,
	IsActive: () -> boolean,
	Light: () -> number,
	Called: () -> number,
}

-- What a hero page shows: its accent, its offer, and its pieces in the card's coordinates.
type TPageBuilt = { Accent: Color3, Offer: ShopCore.TOffer, Pieces: { any } }

-- His GRAVITY HAMMER card: the featured gun of these three days, its name over two lines, its rarity and tier, what
-- comes with it, the gun big in the weapons stage's look (in its rarity's colour) and how long it stays. Its product
-- is the one of the gun's rarity, so the page reads the offer as the gun changes.
local function featuredPage(state: Types.TShopState, actions: Types.TShopActions, page: TPage): TPageBuilt
	local size = Layout.FEATURED
	local accent = Palette.Pink
	local gunName = derive(function(): string
		state.FeaturedEndsAt()
		return ShopCore.FeaturedGun(os.time())
	end)
	local offer = ShopCore.FeaturedOffer(os.time())
	local cheer = Parts.Cheer(state, offer.Name)
	local words = function(): (string, string)
		local name = string.upper(gunName())
		local first, last = string.match(name, "^(.*) (%S+)$")
		if first then return first, last end
		return "FEATURED", name
	end
	local rarity = derive(function()
		local data = LoadoutCore.ByName[gunName()]
		return Parts.RARITIES[if data then data.Rarity else "Legendary"]
	end)
	local data = LoadoutCore.ByName[gunName()]
	local center = Vector2.new(Layout.HERO_X, Layout.HERO_Y)
	local items = contents(offer, os.time())
	-- The gun is the title: its line is not listed again.
	table.remove(items, 1)

	return {
		Accent = accent,
		Offer = offer,
		Pieces = {
			art(state, page, offer, size, {
				Art = "Orbit",
				Accent = function(): Color3
					return rarity().Accent
				end,
				Center = center,
				Diameter = 600,
				Floor = 150,
			}),
			Parts.Tag(
				"FEATURED WEAPON",
				accent,
				false,
				false,
				{ Position = UDim2.fromOffset(Layout.LEFT, Layout.WIDE_TAG) },
				Layout.TAG
			),
			title(function()
				return (words())
			end, function()
				local _, second = words()
				return second
			end, accent, Layout.WIDE_TITLE, Layout.BIG_TITLE, page.Shift),
			tagRow(Layout.LEFT, Layout.WIDE_TAGS, {
				Parts.Tag(rarity().Text, rarity().Accent, rarity().IsInk, false, nil, Layout.TAG),
				Parts.Tag(`TIER {if data then data.Tier else 4} WEAPON`, Palette.Gold, false, true, nil, Layout.TAG),
			}),
			chips(cheer, page.Since, items, Layout.WIDE_CHIPS),
			gun(gunName, page.Light, center, Vector2.new(640, 340), 3),
			overPrice(size, "LEAVES THE SHOP IN", function(): string
				state.Clock()
				return Parts.Countdown(state.FeaturedEndsAt() - os.time())
			end),
			buy(state, actions, offer, size, true, page.Since, page.Called),
		},
	}
end

-- His GUNSLINGER BUNDLE card: the class bundle, its vest in the classes stage's spotlight (its gun is a line of what
-- it gives, never a model beside the picture), and what it is all worth.
local function bundlePage(state: Types.TShopState, actions: Types.TShopActions, page: TPage): TPageBuilt
	local offer = ShopCore.ByName.SurvivorBundle
	local look = LOOKS[offer.Name]
	local size = Layout.FEATURED
	local accent = look.Accent
	local cheer = Parts.Cheer(state, offer.Name)
	local center = Vector2.new(Layout.HERO_X, Layout.HERO_Y)

	return {
		Accent = accent,
		Offer = offer,
		Pieces = {
			art(state, page, offer, size, {
				Art = look.Art,
				Accent = fixed(accent),
				Center = center + Vector2.new(0, 14),
				Diameter = 560,
				Floor = 150,
				FloorSize = Vector2.new(460, 84),
			}),
			Parts.Tag(
				"LIMITED BUNDLE",
				accent,
				true,
				false,
				{ Position = UDim2.fromOffset(Layout.LEFT, Layout.WIDE_TAG) },
				Layout.TAG
			),
			title("SURVIVOR", "BUNDLE", accent, Layout.WIDE_TITLE, Layout.BIG_TITLE, page.Shift),
			tagRow(Layout.LEFT, Layout.WIDE_TAGS, {
				Parts.Tag("CLASS", Palette.Pink, false, false, nil, Layout.TAG),
				Parts.Tag(`{#offer.Contents} ITEMS`, accent, false, true, nil, Layout.TAG),
			}),
			chips(cheer, page.Since, contents(offer, os.time()), Layout.WIDE_CHIPS),
			picture(look.Picture, center, 300, page.Light, cheer),
			overPrice(size, "WORTH", `{Components.Commas(ShopCore.GemsWorth(offer, os.time()))} GEMS`),
			buy(state, actions, offer, size, true, page.Since, page.Called),
		},
	}
end

local PAGES = table.freeze({ Featured = featuredPage, SurvivorBundle = bundlePage })

-- His arrow plaque under the thing on show: `step` -1 turns back, 1 on. The glyph leans the way it goes under the hand.
local function arrow(actions: Types.TShopActions, step: number, x: number): TextButton
	local hand = Hand.React("Operate")
	return Components.Button({
		Name = if step < 0 then "Back" else "On",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x, Layout.PIPS_Y),
		Size = UDim2.fromOffset(Layout.ARROW, Layout.ARROW),
		BackgroundTransparency = 1,
		ZIndex = 9,
		Activated = function()
			hand.Commit()
			actions.TurnPage(step)
		end,
		hand.Events,
		create("UIScale")({ Scale = hand.Scale }),
		Components.Plaque({
			Name = "Plaque",
			Size = UDim2.fromScale(1, 1),
			ZIndex = 9,
			Components.Brackets(hand.Rise, function()
				return 0.6 - 0.3 * hand.Light()
			end, 12),
			Hand.WashLayer(hand, 10, 2),
			Components.Picture(EIcons.Arrow, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = function()
					return UDim2.new(0.5, math.round(step * 4 * hand.Rise()), 0.5, 0)
				end,
				Size = Components.PictureBox(Layout.ARROW_GLYPH),
				Rotation = if step < 0 then 180 else 0,
				ImageColor3 = Palette.White,
				ZIndex = 11,
			}),
		}),
	}) :: TextButton
end

-- The hero's pips: one per page, the one on show long and filling in the page's accent as its time runs out, the rest
-- short; a press turns straight to its page. Between the two arrows.
local function pips(state: Types.TShopState, actions: Types.TShopActions, accent: () -> Color3): { Instance }
	local row = {}
	for index in Parts.HERO do
		local isLit = derive(function(): boolean
			return state.Page() == index
		end)
		local hand = Hand.React("Operate", function(): boolean
			return not isLit()
		end)
		local width = Hand.Spring(function(): number
			return if isLit() then Layout.PIP_LIT else Layout.PIP
		end, Timing.PIP_PERIOD)
		-- In whole px, so the clock ticking every frame writes the bar only when it grows a pixel.
		local filled = derive(function(): number
			if not isLit() then return 0 end
			return math.round(Layout.PIP_LIT * math.clamp(state.PageShown() / Parts.PAGE_SECONDS, 0, 1))
		end)
		row[index] = Components.Button({
			Name = `Pip{index}`,
			LayoutOrder = index,
			Size = function()
				return UDim2.fromOffset(math.round(width()) + Layout.PIP_HIT.X, Layout.PIP_HIT.Y)
			end,
			BackgroundTransparency = 1,
			ZIndex = 9,
			Activated = function()
				hand.Commit()
				actions.PickPage(index)
			end,
			hand.Events,
			create("Frame")({
				Name = "Track",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = function()
					return UDim2.fromOffset(math.round(width()), Layout.PIP_HEIGHT)
				end,
				BackgroundColor3 = Palette.White,
				BackgroundTransparency = function()
					return if isLit() then 0.75 else 0.55 - 0.4 * hand.Light()
				end,
				BorderSizePixel = 0,
				ZIndex = 9,
				create("UICorner")({ CornerRadius = UDim.new(0, Layout.PIP_HEIGHT / 2) }),
				create("Frame")({
					Name = "Fill",
					Size = function()
						return UDim2.fromOffset(filled(), Layout.PIP_HEIGHT)
					end,
					BackgroundColor3 = accent,
					BorderSizePixel = 0,
					ZIndex = 10,
					create("UICorner")({ CornerRadius = UDim.new(0, Layout.PIP_HEIGHT / 2) }),
				}),
			}),
		})
	end

	local half = (Layout.PIP_LIT + Layout.PIP * (#Parts.HERO - 1) + Layout.PIP_HIT.X * #Parts.HERO) / 2
	local reach = half + Layout.ARROW_GAP + Layout.ARROW / 2
	return {
		create("Frame")({
			Name = "Pips",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(Layout.HERO_X, Layout.PIPS_Y),
			Size = UDim2.fromOffset(2 * half, Layout.PIP_HIT.Y),
			BackgroundTransparency = 1,
			ZIndex = 9,
			create("UIListLayout")({
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			row,
		}),
		arrow(actions, -1, Layout.HERO_X - reach),
		arrow(actions, 1, Layout.HERO_X + reach),
	}
end

-- The hero across the row (the reference's bundle carousel in his FEATURED card): one card turning through the featured
-- offers, each a page of his GRAVITY HAMMER / GUNSLINGER card. A turn slides both pages on one curve, the title a
-- beat behind, the edge warming to the coming page's accent, its chips punched, its worth struck again,
-- its ribbon slapping on as the last one is pulled off. It turns on by itself every PAGE_SECONDS, never while the
-- hand is on it.
function Cards.Hero(state: Types.TShopState, actions: Types.TShopActions, spec: TCardSpec): Frame
	local size = Layout.FEATURED
	local hand = hover(state, actions, function(isOn: boolean)
		state.IsHeroHeld(isOn)
	end)
	local travel = derive(function(): number
		return Motion.Decelerate(Progress(state.Now(), state.PageAt(), Timing.PAGE_SLIDE))
	end)
	local turned = derive(function(): number
		return Motion.Decelerate(Progress(state.Now(), state.PageAt() + Timing.TITLE_DELAY, Timing.PAGE_SLIDE))
	end)
	local called = call(state)

	local names, accents, pages, ribbons = {}, {}, {}, {}
	for index, key in Parts.HERO do
		local isOn = derive(function(): boolean
			return state.Page() == index
		end)
		-- Where it is across the card: 0 on show, sliding in or out, else parked off the card (never hidden with
		-- Visible: UI.md, the reel).
		local x = derive(function(): number
			if isOn() then return math.round(state.PageStep() * size.X * (1 - travel())) end
			if state.PagePrev() == index then return math.round(-state.PageStep() * size.X * travel()) end
			return 2 * size.X
		end)
		local page: TPage = {
			Deal = spec.Deal,
			Since = derive(function(): number
				local at = spec.Seen()
				if isOn() then at = math.max(at, state.PageAt()) end
				return math.clamp(state.Now() - at, 0, 2)
			end),
			Shift = derive(function(): number
				if not isOn() then return 0 end
				return math.round(state.PageStep() * Timing.TITLE_PX * (1 - turned()))
			end),
			IsActive = derive(function(): boolean
				return isOn() and spec.IsActive()
			end),
			Light = hand.Light,
			Called = derive(function(): number
				return if isOn() then called() else 1
			end),
		}
		local made = PAGES[key](state, actions, page)
		names[index] = made.Offer.Name
		accents[index] = made.Accent
		pages[index] = create("Frame")({
			Name = `Page{index}`,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				return UDim2.fromOffset(x() - Layout.EDGE + size.X / 2, size.Y / 2 - Layout.EDGE)
			end,
			Size = UDim2.fromOffset(size.X, size.Y),
			BackgroundTransparency = 1,
			ZIndex = 3,
			made.Pieces,
		})
		ribbons[index] = sticker(state, made.Offer, isOn)
	end

	-- The edge and glow follow the slide from the page going to the page coming.
	local accent = derive(function(): Color3
		return accents[state.PagePrev()]:Lerp(accents[state.Page()], travel())
	end)
	local cheer = Parts.Cheer(state, names)

	return card(state, hand, "Hero", cheer, accent, size, spec, {
		create("Frame")({
			Name = "Pages",
			Position = UDim2.fromOffset(Layout.EDGE, Layout.EDGE),
			Size = UDim2.fromOffset(size.X - 2 * Layout.EDGE, size.Y - 2 * Layout.EDGE),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = 3,
			pages,
		}),
		ribbons,
		pips(state, actions, accent),
	})
end

-- ============================== BUNDLES ==============================

-- STARTER PACK: once only, a gun and Gems, its crate (the gun and the Gems inside it) in the prize's rays.
function Cards.StarterPack(state: Types.TShopState, actions: Types.TShopActions, spec: TCardSpec): Frame
	local offer = ShopCore.ByName.StarterPack
	local look = LOOKS[offer.Name]
	local size = Layout.BUNDLE
	local accent = look.Accent
	local hand = hover(state, actions)
	local light = hand.Light
	local cheer = Parts.Cheer(state, offer.Name)
	local since = sinceSeen(state, spec)
	local center = Vector2.new(650, 196)

	return card(state, hand, offer.Name, cheer, accent, size, spec, {
		art(state, spec, offer, size, {
			Art = look.Art,
			Accent = fixed(accent),
			Center = center,
			Diameter = 480,
			Floor = 130,
		}),
		Parts.Tag("ONE TIME OFFER", accent, true, false, { Position = UDim2.fromOffset(Layout.LEFT, 36) }, Layout.TAG),
		title("STARTER", "PACK", accent, 86, Layout.TITLE),
		chips(cheer, since, contents(offer, os.time()), 226),
		picture(look.Picture, center, 300, light, cheer),
		buy(state, actions, offer, size, false, since),
		sticker(state, offer),
	})
end

-- ARSENAL BUNDLE: a gun of every tier, each in a cell of its own across the card with its name and rarity (the
-- reference's four). The guns are the picture: no case is drawn beside their models.
function Cards.Arsenal(state: Types.TShopState, actions: Types.TShopActions, spec: TCardSpec): Frame
	local offer = ShopCore.ByName.ArsenalBundle
	local look = LOOKS[offer.Name]
	local size = Layout.BUNDLE
	local accent = look.Accent
	local hand = hover(state, actions)
	local light = hand.Light
	local cheer = Parts.Cheer(state, offer.Name)
	local since = sinceSeen(state, spec)
	local cellSize = Layout.CELL
	local cells = {}
	for index, content in offer.Contents do
		if content.Kind ~= "Gun" then continue end
		local data = LoadoutCore.ByName[content.Name]
		local rarity = Parts.RARITIES[data.Rarity]
		local column, row = (index - 1) % 2, (index - 1) // 2
		-- Dealt in one after another as the card is first seen, and punched again as it cheers.
		local pop = derive(function(): number
			local stagger = Timing.CHIPS_STAGGER * (index - 1)
			local arrive = Motion.Bump((since() - Timing.CHIPS_DELAY - stagger) / Timing.CHIP_POP)
			return math.max(arrive, Motion.Bump((cheer.Since() - 0.08 * (index - 1)) / 0.32))
		end)
		cells[index] = Components.Card({
			Accent = rarity.Accent,
			Tint = 0.3,
			Edge = 2,
			GlowTransparency = 1,
		}, {
			Name = content.Name,
			-- From its middle, so its punch grows it evenly.
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(
				Layout.LEFT + column * (cellSize.X + Layout.CELL_GAP.X) + cellSize.X / 2,
				Layout.CELLS_TOP + row * (cellSize.Y + Layout.CELL_GAP.Y) + cellSize.Y / 2
			),
			Size = UDim2.fromOffset(cellSize.X, cellSize.Y),
			ZIndex = 3,
			create("UIScale")({
				Scale = function()
					return 1 + 0.05 * pop()
				end,
			}),
			gun(function()
				return content.Name
			end, light, Layout.CELL_GUN_AT, Layout.CELL_GUN, 4, Layout.CELL_TILT),
			Label({
				Position = UDim2.fromOffset(12, cellSize.Y - 28),
				Size = UDim2.fromOffset(cellSize.X - 24, 18),
				TextSize = 18,
				Text = string.upper(content.Name),
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 5,
			}),
			Parts.Tag(rarity.Text, rarity.Accent, rarity.IsInk, false, {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -6, 0, 6),
				ZIndex = 5,
			}, 22),
		})
	end

	return card(state, hand, offer.Name, cheer, accent, size, spec, {
		art(state, spec, offer, size, {
			Art = look.Art,
			Accent = fixed(accent),
			Center = Vector2.new(size.X / 2, 260),
			Diameter = 700,
			Floor = 150,
		}),
		Label({
			Name = "Title",
			Position = UDim2.fromOffset(Layout.LEFT - 2, 34),
			Size = UDim2.fromOffset(600, Layout.TITLE),
			TextSize = Layout.TITLE,
			Text = "ARSENAL BUNDLE",
		}),
		Parts.Tag(`{#offer.Contents} GUNS, ONE EVERY TIER`, accent, false, true, {
			Position = UDim2.fromOffset(Layout.LEFT, 98),
		}, Layout.TAG),
		cells,
		buy(state, actions, offer, size, false, since),
		sticker(state, offer),
	})
end

-- ============================== GEMS ==============================

-- A Gem pack, two to a row: its own picture big in its look on the left, the amount and GEMS over its bonus, the price
-- and gift under them.
function Cards.GemPack(
	state: Types.TShopState,
	actions: Types.TShopActions,
	offer: ShopCore.TOffer,
	spec: TCardSpec
): Frame
	local look = LOOKS[offer.Name]
	local size = Layout.PACK
	local hand = hover(state, actions)
	local light = hand.Light
	local cheer = Parts.Cheer(state, offer.Name)
	local since = sinceSeen(state, spec)
	local bonus = ShopCore.GemsBonus(offer)
	local center = Vector2.new(170, size.Y / 2)

	local shown = picture(look.Picture, center, 180, light, cheer)
	return card(state, hand, offer.Name, cheer, look.Accent, size, spec, {
		art(state, spec, offer, size, {
			Art = look.Art,
			Accent = fixed(look.Accent),
			Center = center,
			Diameter = 340,
			Floor = 90,
		}),
		shown,
		Label({
			Name = "Amount",
			Position = UDim2.fromOffset(330, 30),
			Size = UDim2.fromOffset(520, 56),
			TextSize = 56,
			Text = `+{Components.Commas(gemsOf(offer))}`,
		}),
		Label({
			Name = "Gems",
			Position = UDim2.fromOffset(332, 88),
			Size = UDim2.fromOffset(200, 26),
			TextSize = 26,
			TextColor3 = look.Accent,
			Text = "GEMS",
		}),
		if bonus > 0.05
			then Parts.Tag(`+{math.floor(bonus * 100)}% MORE`, Palette.Gold, true, false, {
				Position = UDim2.fromOffset(426, 86),
			}, 30)
			else nil,
		buy(state, actions, offer, size, false, since),
	}, Layout.PACK_TINT)
end

-- The biggest pack, across the whole row: its picture huge, the amount big, BEST VALUE and its bonus.
function Cards.MegaPack(
	state: Types.TShopState,
	actions: Types.TShopActions,
	offer: ShopCore.TOffer,
	spec: TCardSpec
): Frame
	local look = LOOKS[offer.Name]
	local size = Layout.MEGA
	local hand = hover(state, actions)
	local light = hand.Light
	local cheer = Parts.Cheer(state, offer.Name)
	local since = sinceSeen(state, spec)
	local bonus = ShopCore.GemsBonus(offer)
	local center = Vector2.new(260, size.Y / 2)

	local shown = picture(look.Picture, center, 250, light, cheer)
	return card(state, hand, offer.Name, cheer, look.Accent, size, spec, {
		art(state, spec, offer, size, {
			Art = look.Art,
			Accent = fixed(look.Accent),
			Center = center,
			Diameter = 520,
			Floor = 100,
		}),
		shown,
		Label({
			Name = "Amount",
			Position = UDim2.fromOffset(500, 42),
			Size = UDim2.fromOffset(900, 84),
			TextSize = 84,
			Text = `+{Components.Commas(gemsOf(offer))} GEMS`,
		}),
		tagRow(504, 150, {
			Parts.Tag("BEST VALUE", Palette.Gold, true, false, nil, Layout.TAG),
			Parts.Tag(`+{math.floor(bonus * 100)}% MORE GEMS`, look.Accent, false, true, nil, Layout.TAG),
		}),
		buy(state, actions, offer, size, true, since, call(state)),
	}, Layout.PACK_TINT)
end

-- ============================== PASSES ==============================

-- A pass: its own picture in its look on the left, its name, what it does, the price and the gift. `IsWide` lays VIP
-- across the row with its perks as chips.
function Cards.Pass(
	state: Types.TShopState,
	actions: Types.TShopActions,
	offer: ShopCore.TOffer,
	spec: TCardSpec
): Frame
	local look = LOOKS[offer.Name]
	local isWide = spec.IsWide == true
	local size = if isWide then Layout.PASS_WIDE else Layout.PASS
	local hand = hover(state, actions)
	local light = hand.Light
	local cheer = Parts.Cheer(state, offer.Name)
	local since = sinceSeen(state, spec)
	local center = Vector2.new(if isWide then 190 else 150, size.Y / 2)
	local left = if isWide then 380 else 300

	local shown = picture(look.Picture, center, if isWide then 200 else 170, light, cheer)

	local body
	if isWide then
		local perks = {
			{ Text = "+ VIP TAG IN CHAT AND OVER YOUR HEAD", Color = look.Accent },
			{ Text = `+ {math.floor(ShopCore.VIP_GEMS * 100)}% MORE GEMS FROM EVERY RUN`, Color = look.Accent },
		}
		if not state.IsRestricted() then
			table.insert(perks, { Text = "+ 1 MORE FREE DAILY SPIN", Color = look.Accent })
			table.insert(perks, { Text = "+ 1 MORE DAILY BREW IN THE LAB", Color = look.Accent })
		end
		local row = {}
		for index, perk in perks do
			local pop = derive(function(): number
				return Motion.Bump((cheer.Since() - 0.1 - 0.07 * (index - 1)) / 0.3)
			end)
			-- Two to a column, the columns side by side: four stacked ran out past the card's bottom.
			local column = (index - 1) // 2
			local place =
				UDim2.fromOffset(column * Layout.PERK_COLUMN, ((index - 1) % 2) * Layout.CHIP_STEP + Layout.CHIP / 2)
			row[index] = Parts.Chip(perk.Text, perk.Color, pop, {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = place,
			}, Layout.CHIP)
		end
		body = create("Frame")({
			Name = "Perks",
			Position = UDim2.fromOffset(left, 124),
			Size = UDim2.fromOffset(900, 2 * Layout.CHIP_STEP),
			BackgroundTransparency = 1,
			ZIndex = 4,
			row,
		})
	else
		body = Label({
			Name = "Description",
			Position = UDim2.fromOffset(left, 88),
			Size = UDim2.fromOffset(size.X - left - Layout.RIGHT, 50),
			FontFace = Font.DisplayBold,
			TextSize = 20,
			TextWrapped = true,
			TextColor3 = Palette.Lavender,
			Text = offer.Description,
		})
	end

	return card(state, hand, offer.Name, cheer, look.Accent, size, spec, {
		art(state, spec, offer, size, {
			Art = look.Art,
			Accent = fixed(look.Accent),
			Center = center,
			Diameter = if isWide then 420 else 260,
			Floor = 80,
		}),
		shown,
		Label({
			Name = "Name",
			Position = UDim2.fromOffset(left, if isWide then 36 else 34),
			Size = UDim2.fromOffset(900, if isWide then 72 else 46),
			TextSize = if isWide then 72 else 46,
			TextColor3 = if isWide then look.Accent else Palette.White,
			Text = offer.Title,
		}),
		body,
		buy(state, actions, offer, size, isWide, since),
	})
end

return Cards
