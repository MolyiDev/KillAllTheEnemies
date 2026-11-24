--!nonstrict
-- The shop's cards, each his accent card at a size that sells what it shows: the featured gun and the class bundle
-- across the row, the two bundles side by side, the Gem packs two by two with the biggest across the row, and the
-- passes (VIP across the row). Every offer stands in a Showcase look of its own (never his plain rings), clipped to
-- the card's face. A card lights and opens its brackets under the hand without growing (only its price and gift are
-- pressed), deals in through a group of its own while it fades, and cheers when what it sells becomes the player's.
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
	BUNDLE = Vector2.new(876, 440),
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
})

local Timing = table.freeze({
	DEAL = 0.42,
	DEAL_RISE = 36,
	DEAL_FROM = 0.94,
	HOVER_PERIOD = 0.25,
	GLINT = 0.55,
	-- How far a gun on a card turns toward the viewer under the hand, in degrees.
	HOVER_YAW = 28,
})

local LOOKS = Parts.LOOKS

export type TCardSpec = {
	-- The card's top left in the scroll.
	Position: Vector2,
	-- 0 to 1 as it deals in; 1 for a card that was out of view as the screen opened.
	Deal: () -> number,
	-- Whether its art is drawn moving: the screen is up and the card is in the window.
	IsActive: () -> boolean,
	IsWide: boolean?,
}

local Cards = {}

Cards.Layout = Layout

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
-- arrives, and the events for its frame. A card is not a button, so it has no press.
local function hover(state: Types.TShopState, actions: Types.TShopActions)
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
		end,
		MouseLeave = function()
			isHovered(false)
		end,
	}

	return { Events = events, Light = light, Glint = glint }
end

-- The card's frame: his accent card, lit by `hand` (its hover), with its cheer over it, in a group that fades it in as
-- it deals (and only then: at rest it is drawn straight). `children` go on the face.
local function card(
	state: Types.TShopState,
	hand,
	offer: ShopCore.TOffer,
	accent: Color3,
	size: Vector2,
	spec: TCardSpec,
	children: { any }
): Frame
	local light, glint = hand.Light, hand.Glint
	local cheer = Parts.Cheer(state, offer.Name)
	local deal = spec.Deal
	local margin = Layout.FADE_MARGIN

	local face = Components.Card({
		Accent = accent,
		Tint = 0.4,
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
		Name = offer.Name,
		Position = UDim2.fromOffset(margin, margin),
		Size = UDim2.fromOffset(size.X, size.Y),
		hand.Events,
		Components.Sheen(glint, 7),
		Parts.CheerLayers(cheer, 3, 8),
		children,
	})

	return create("Frame")({
		Name = `{offer.Name}Card`,
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
		Components.FadeGroup(offer.Name, deal, { Size = UDim2.fromScale(1, 1) }, { face }),
	})
end

-- The Showcase look an offer stands in, its middle at `center` on the card, in two layers clipped to the face: behind
-- the picture, and its particles over it. It comes in as the card deals and cheers as the offer is granted.
local function art(
	state: Types.TShopState,
	spec: TCardSpec,
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

-- An offer's own picture, its middle at `center`, `longest` px, swelling under the hand and punching as it cheers.
local function picture(name: string, center: Vector2, longest: number, light: () -> number, cheer): ImageLabel
	return Components.Picture(name, {
		Name = "Picture",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(center.X, center.Y),
		Size = Components.PictureBox(longest),
		ZIndex = 3,
		create("UIScale")({
			Scale = function()
				return 1 + 0.06 * light() + 0.12 * cheer.Punch()
			end,
		}),
	})
end

-- A gun's own model in a box, the barrel to the right, turning a little toward the viewer under the hand.
local function gun(gunName: () -> string, light: () -> number, center: Vector2, size: Vector2, zIndex: number): Frame
	return GunPicture.Build(function()
		local data = LoadoutCore.ByName[gunName()]
		return if data then GunPicture.FromGun(data.Id) else nil
	end, {
		Rotation = GunPicture.CARD_TILT,
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

-- The saving sticker across the top right corner, while the offer is not the player's.
local function sticker(state: Types.TShopState, offer: ShopCore.TOffer): Frame?
	local saving = ShopCore.Saving(offer, os.time())
	if saving < 0.05 then return nil end

	return Ribbon.Build({
		Corner = "TopRight",
		Text = `-{math.floor(saving * 100)}%`,
		Color = Palette.Pink,
		IsShown = function()
			return state.IsOpen() and not Parts.IsOwned(state, offer)
		end,
		Along = Layout.RIBBON_ALONG,
		Thickness = Layout.RIBBON_THICKNESS,
		TextSize = Layout.RIBBON_TEXT,
		Delay = 0.5,
		CallOrder = 1,
		ZIndex = 7,
	})
end

-- The price in the card's bottom right corner and the gift left of it; `isBig` for the cards across the row.
local function buy(
	state: Types.TShopState,
	actions: Types.TShopActions,
	offer: ShopCore.TOffer,
	size: Vector2,
	isBig: boolean
): { Instance }
	local priceSize = if isBig then Layout.BIG_PRICE else Layout.PRICE
	local center = Vector2.new(size.X - Layout.RIGHT - priceSize.X / 2, size.Y - Layout.BOTTOM - priceSize.Y / 2)
	local gift = priceSize.Y

	return {
		Parts.Price(
			state,
			actions,
			offer,
			priceSize,
			if isBig then Layout.BIG_PRICE_TEXT else Layout.PRICE_TEXT,
			{ Position = UDim2.fromOffset(center.X, center.Y) }
		),
		Parts.Gift(actions, offer, gift, {
			Position = UDim2.fromOffset(center.X - priceSize.X / 2 - giftGap(priceSize.X) - gift / 2, center.Y),
		}),
	}
end

-- A column of "+ ITEM" chips from `top`, each punched in turn as the card cheers.
local function chips(cheer, items: { { Text: string, Color: Color3 } }, top: number): { Instance }
	local built = {}
	for index, item in items do
		local pop = derive(function(): number
			return Motion.Bump((cheer.Since() - 0.1 - 0.07 * (index - 1)) / 0.3)
		end)
		built[index] = Parts.Chip(item.Text, item.Color, pop, {
			Position = UDim2.fromOffset(Layout.LEFT, top + Layout.CHIP_STEP * (index - 1)),
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

-- His two-line title: the first line white, the second in the accent.
local function title(
	first: string | () -> string,
	second: string | () -> string,
	accent: Color3,
	top: number,
	textSize: number
): { Instance }
	return {
		Label({
			Name = "Title1",
			Position = UDim2.fromOffset(Layout.LEFT - 2, top),
			Size = UDim2.fromOffset(760, textSize),
			TextSize = textSize,
			Text = first,
		}),
		Label({
			Name = "Title2",
			Position = UDim2.fromOffset(Layout.LEFT - 2, top + textSize),
			Size = UDim2.fromOffset(760, textSize),
			TextSize = textSize,
			TextColor3 = accent,
			Text = second,
		}),
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

-- His GRAVITY HAMMER card across the row: the featured gun of these three days, its name over two lines, its rarity
-- and tier, what comes with it, the gun big in the weapons stage's look (in its rarity's colour) and the price. Its
-- product is the one of the gun's rarity, so the card reads the offer as the gun changes.
function Cards.FeaturedGun(state: Types.TShopState, actions: Types.TShopActions, spec: TCardSpec): Frame
	local size = Layout.FEATURED
	local accent = Palette.Pink
	local gunName = derive(function(): string
		state.FeaturedEndsAt()
		return ShopCore.FeaturedGun(os.time())
	end)
	local offer = ShopCore.FeaturedOffer(os.time())
	local hand = hover(state, actions)
	local light = hand.Light
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
	local center = Vector2.new(1010, 206)

	local shown = gun(gunName, light, center, Vector2.new(640, 340), 3)
	return card(state, hand, offer, accent, size, spec, {
		art(state, spec, offer, size, {
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
		end, accent, Layout.WIDE_TITLE, Layout.BIG_TITLE),
		tagRow(Layout.LEFT, Layout.WIDE_TAGS, {
			Parts.Tag(rarity().Text, rarity().Accent, rarity().IsInk, false, nil, Layout.TAG),
			Parts.Tag(`TIER {if data then data.Tier else 4} WEAPON`, Palette.Gold, false, true, nil, Layout.TAG),
		}),
		chips(cheer, {
			{ Text = `+ {Components.Commas(gemsOf(offer))} GEMS`, Color = accent },
		}, Layout.WIDE_CHIPS),
		shown,
		overPrice(size, "LEAVES THE SHOP IN", function(): string
			state.Clock()
			return Parts.Countdown(state.FeaturedEndsAt() - os.time())
		end),
		buy(state, actions, offer, size, true),
	})
end

-- His GUNSLINGER BUNDLE card across the row: the class bundle, its vest in the classes stage's spotlight and the gun
-- leaning beside it.
function Cards.ClassBundle(state: Types.TShopState, actions: Types.TShopActions, spec: TCardSpec): Frame
	local offer = ShopCore.ByName.SurvivorBundle
	local look = LOOKS[offer.Name]
	local size = Layout.FEATURED
	local accent = look.Accent
	local hand = hover(state, actions)
	local light = hand.Light
	local cheer = Parts.Cheer(state, offer.Name)
	local center = Vector2.new(1010, 214)
	local items = {}
	local gunName = "Sandan Gun"
	for _, content in offer.Contents do
		if content.Kind == "Class" then
			table.insert(items, { Text = "+ HUMAN CLASS", Color = accent })
		elseif content.Kind == "Gun" then
			gunName = content.Name
			table.insert(items, { Text = `+ {string.upper(content.Name)}`, Color = accent })
		elseif content.Kind == "Gems" then
			table.insert(items, { Text = `+ {Components.Commas(content.Amount)} GEMS`, Color = accent })
		end
	end

	local vest = picture(look.Picture, center + Vector2.new(-70, -14), 290, light, cheer)
	return card(state, hand, offer, accent, size, spec, {
		art(state, spec, offer, size, {
			Art = look.Art,
			Accent = fixed(accent),
			Center = center,
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
		title("SURVIVOR", "BUNDLE", accent, Layout.WIDE_TITLE, Layout.BIG_TITLE),
		tagRow(Layout.LEFT, Layout.WIDE_TAGS, {
			Parts.Tag("CLASS", Palette.Pink, false, false, nil, Layout.TAG),
			Parts.Tag(`{#offer.Contents} ITEMS`, accent, false, true, nil, Layout.TAG),
		}),
		chips(cheer, items, Layout.WIDE_CHIPS),
		vest,
		gun(function()
			return gunName
		end, light, center + Vector2.new(120, 70), Vector2.new(400, 190), 4),
		overPrice(size, "WORTH", `{Components.Commas(ShopCore.GemsWorth(offer, os.time()))} GEMS`),
		buy(state, actions, offer, size, true),
		sticker(state, offer),
	})
end

-- ============================== BUNDLES ==============================

-- STARTER PACK: once only, a gun and Gems, its crate in the prize's rays and the gun in front of it.
function Cards.StarterPack(state: Types.TShopState, actions: Types.TShopActions, spec: TCardSpec): Frame
	local offer = ShopCore.ByName.StarterPack
	local look = LOOKS[offer.Name]
	local size = Layout.BUNDLE
	local accent = look.Accent
	local hand = hover(state, actions)
	local light = hand.Light
	local cheer = Parts.Cheer(state, offer.Name)
	local center = Vector2.new(650, 186)
	local items, gunName = {}, "Desert Eagle"
	for _, content in offer.Contents do
		if content.Kind == "Gun" then
			gunName = content.Name
			table.insert(items, { Text = `+ {string.upper(content.Name)}`, Color = accent })
		elseif content.Kind == "Gems" then
			table.insert(items, { Text = `+ {Components.Commas(content.Amount)} GEMS`, Color = Palette.Pink })
		end
	end

	local crate = picture(look.Picture, center, 270, light, cheer)
	return card(state, hand, offer, accent, size, spec, {
		art(state, spec, offer, size, {
			Art = look.Art,
			Accent = fixed(accent),
			Center = center,
			Diameter = 460,
			Floor = 130,
		}),
		Parts.Tag("ONE TIME OFFER", accent, true, false, { Position = UDim2.fromOffset(Layout.LEFT, 36) }, Layout.TAG),
		title("STARTER", "PACK", accent, 86, Layout.TITLE),
		chips(cheer, items, 226),
		crate,
		gun(function()
			return gunName
		end, light, center + Vector2.new(-40, 80), Vector2.new(260, 120), 4),
		buy(state, actions, offer, size, false),
		sticker(state, offer),
	})
end

-- ARSENAL BUNDLE: a gun of every tier, each in a cell of its own with its name and rarity (the reference's four), and
-- the case they come in.
function Cards.Arsenal(state: Types.TShopState, actions: Types.TShopActions, spec: TCardSpec): Frame
	local offer = ShopCore.ByName.ArsenalBundle
	local look = LOOKS[offer.Name]
	local size = Layout.BUNDLE
	local accent = look.Accent
	local hand = hover(state, actions)
	local light = hand.Light
	local cheer = Parts.Cheer(state, offer.Name)
	local cellSize = Vector2.new(220, 122)
	local cellsTop = 150
	local center = Vector2.new(690, 190)
	local cells = {}
	for index, content in offer.Contents do
		if content.Kind ~= "Gun" then continue end
		local data = LoadoutCore.ByName[content.Name]
		local rarity = Parts.RARITIES[data.Rarity]
		local column, row = (index - 1) % 2, (index - 1) // 2
		local pop = derive(function(): number
			return Motion.Bump((cheer.Since() - 0.08 * (index - 1)) / 0.32)
		end)
		cells[index] = Components.Card({
			Accent = rarity.Accent,
			Tint = 0.3,
			Edge = 2,
			GlowTransparency = 1,
		}, {
			Name = content.Name,
			Position = UDim2.fromOffset(Layout.LEFT + column * (cellSize.X + 12), cellsTop + row * (cellSize.Y + 12)),
			Size = UDim2.fromOffset(cellSize.X, cellSize.Y),
			ZIndex = 3,
			create("UIScale")({
				Scale = function()
					return 1 + 0.06 * pop()
				end,
			}),
			gun(function()
				return content.Name
			end, light, Vector2.new(cellSize.X / 2, 50), Vector2.new(190, 84), 4),
			Label({
				Position = UDim2.fromOffset(10, cellSize.Y - 28),
				Size = UDim2.fromOffset(cellSize.X - 20, 18),
				TextSize = 17,
				Text = string.upper(content.Name),
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 5,
			}),
			Parts.Tag(rarity.Text, rarity.Accent, rarity.IsInk, false, {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -6, 0, 6),
				ZIndex = 5,
			}, 20),
		})
	end

	local case = picture(look.Picture, center, 250, light, cheer)
	return card(state, hand, offer, accent, size, spec, {
		art(state, spec, offer, size, {
			Art = look.Art,
			Accent = fixed(accent),
			Center = center,
			Diameter = 380,
			Floor = 120,
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
		case,
		buy(state, actions, offer, size, false),
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
	local bonus = ShopCore.GemsBonus(offer)
	local center = Vector2.new(170, size.Y / 2)

	local shown = picture(look.Picture, center, 180, light, cheer)
	return card(state, hand, offer, look.Accent, size, spec, {
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
		buy(state, actions, offer, size, false),
	})
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
	local bonus = ShopCore.GemsBonus(offer)
	local center = Vector2.new(260, size.Y / 2)

	local shown = picture(look.Picture, center, 250, light, cheer)
	return card(state, hand, offer, look.Accent, size, spec, {
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
		buy(state, actions, offer, size, true),
	})
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
			local place = UDim2.fromOffset(column * Layout.PERK_COLUMN, ((index - 1) % 2) * Layout.CHIP_STEP)
			row[index] = Parts.Chip(perk.Text, perk.Color, pop, { Position = place }, Layout.CHIP)
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

	return card(state, hand, offer, look.Accent, size, spec, {
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
		buy(state, actions, offer, size, isWide),
	})
end

return Cards
