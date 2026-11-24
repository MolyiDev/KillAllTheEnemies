--!nonstrict
-- The shop on his 1920 x 1080 (UIMatt.md, Robux Shop): the lobby dimmed, his panel with the section tabs
-- (his pink slab gliding under the lit one) over one scroll of sections (FEATURED, BUNDLES, GEMS, GAMEPASSES, each
-- under his header), EXIT, and the gift list over it all. A tab glides the scroll to its section; scrolling lights the
-- tab of the section in view. The HUD's Gems pill stays up over it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Scrollbar = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Scrollbar)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local ShopCore = require(ReplicatedStorage.GlobalShared.Core.ShopCore)
local Cards = require(script.Parent.Cards)
local Gift = require(script.Parent.Gift)
local Parts = require(script.Parent.Parts)
local panelTop = require(script.Parent.Parent.Parent.Utils.panelTop)
local Types = require(script.Parent.Types)

local create = vide.create
local derive = vide.derive
local source = vide.source
local Palette = Theme.Palette
local Label = Parts.Label
local CardLayout = Cards.Layout

-- His drawn rects in px at 1080, from the screen's top left.
local Layout = table.freeze({
	PANEL = Vector2.new(40, 160),
	PANEL_SIZE = Vector2.new(1840, 780),
	-- Four tabs where his five stood, centred, 237 wide and 23 apart (the bracket check, as the equipment tabs).
	TAB_LEFTS = { 452, 712, 972, 1232 },
	TAB_TOP = 186,
	TAB_SIZE = Vector2.new(237, 60),
	TAB_GLYPH = 24,
	TAB_GLYPH_GAP = 12,
	TAB_TEXT = 24,
	TAB_BRACKET_LENGTH = 16,
	-- The scroll, under the tabs, and the content's left inside it (room for a card's brackets).
	WINDOW = Vector2.new(48, 264),
	WINDOW_SIZE = Vector2.new(1824, 664),
	LEFT = 16,
	-- 16 px under the window's room, for the scrollbar right of the cards.
	WIDTH = 1776,
	-- A header, then 24 px to its cards; 24 px between cards; 40 under a section.
	HEADER = 48,
	UNDER_HEADER = 24,
	GAP = 24,
	SECTION_GAP = 40,
	-- The scrollbar right of the cards, on the screen (8 px clear of a lit card's brackets), and its length.
	SCROLLBAR = Vector2.new(1860, 272),
	SCROLLBAR_LENGTH = 648,
	-- A tab's glide puts its header this far under the window's top.
	SCROLL_MARGIN = 6,
	MESSAGE = Vector2.new(470, 1005),
	MESSAGE_TEXT = 20,
})

local Timing = table.freeze({
	-- His lobby screens dim the world this much (UIMatt.md section 2: 0.7 transparent).
	DIM = 0.3,
	PANEL_DELAY = 0.02,
	PANEL_FROM = 0.96,
	TABS = 0.1,
	TABS_STAGGER = 0.05,
	TABS_DROP = 18,
	-- The cards deal in by section, one after another; past the fold they are all in by then anyway.
	CARDS = 0.2,
	CARDS_STAGGER = 0.06,
	CARDS_MAX = 0.8,
	EXIT_DELAY = 0.28,
	PICK_PERIOD = 0.3,
	PICK_DAMPING = 0.75,
	MESSAGE_IN = 0.25,
	MESSAGE_HOLD = 3.2,
})

-- The panel is raised to just under the top bar, its bottom staying put: the tabs ride up with its top, and the scroll
-- grows into the room.
local lift = panelTop.Lift(Layout.PANEL.Y)
local function windowHeight(): number
	return Layout.WINDOW_SIZE.Y + lift()
end

local Screen = {}

-- One tab: his dark plate, its brackets closed while its section is lit, and its word with the section's glyph grown in
-- beside it while lit, lavender alone while not. Returns its pieces and its hand's scale, for the glider on it.
local function tab(state: Types.TShopState, actions: Types.TShopActions, elapsed: () -> number, index: number)
	local section = Parts.SECTIONS[index]
	local away = Parts.Away(state, elapsed, Timing.TABS + Timing.TABS_STAGGER * (index - 1))
	local isLit = derive(function(): boolean
		return state.Section() == section.Key
	end)
	local hand = Hand.React("Take", function(): boolean
		return not isLit()
	end)
	local picked = Hand.Spring(function(): number
		return if isLit() then 1 else 0
	end, Timing.PICK_PERIOD)
	local lit = function(): number
		return math.clamp(picked(), 0, 1)
	end
	local position = derive(function(): UDim2
		return UDim2.fromOffset(
			Layout.TAB_LEFTS[index] + Layout.TAB_SIZE.X / 2,
			Layout.TAB_TOP - lift() + Layout.TAB_SIZE.Y / 2 - math.round(Timing.TABS_DROP * away())
		)
	end)
	local scale = function(): number
		return hand.Scale() * (1 - 0.4 * away())
	end

	local word = create("Frame")({
		Name = `{section.Word}Word`,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(Layout.TAB_SIZE.X, Layout.TAB_SIZE.Y),
		BackgroundTransparency = 1,
		ZIndex = 5,
		create("UIScale")({ Scale = scale }),
		create("UIListLayout")({
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		-- The glyph's box opens as the tab lights, so the word slides over to make room.
		create("Frame")({
			Name = "GlyphBox",
			LayoutOrder = 1,
			Size = function()
				return UDim2.fromOffset(math.round((Layout.TAB_GLYPH + Layout.TAB_GLYPH_GAP) * lit()), Layout.TAB_GLYPH)
			end,
			BackgroundTransparency = 1,
			Components.Picture(section.Glyph, {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromScale(0, 0.5),
				Size = Components.PictureBox(Layout.TAB_GLYPH),
				ImageTransparency = function()
					return 1 - lit()
				end,
				create("UIScale")({
					Scale = function()
						return lit() * (1 + 0.12 * hand.Rise())
					end,
				}),
			}),
		}),
		Label({
			LayoutOrder = 2,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, Layout.TAB_TEXT),
			TextSize = Layout.TAB_TEXT,
			TextColor3 = function()
				return Palette.Lavender:Lerp(Palette.White, lit())
			end,
			TextTransparency = away,
			Text = section.Word,
		}),
	})

	local button = Components.Button({
		Name = `{section.Word}Tab`,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(Layout.TAB_SIZE.X, Layout.TAB_SIZE.Y),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Activated = function()
			hand.Commit()
			actions.PickSection(section.Key)
		end,
		hand.Events,
		create("UIScale")({ Scale = scale }),
		Components.Panel({
			Glow = function()
				return Color3.new():Lerp(Palette.Pink, hand.Light())
			end,
			GlowTransparency = function()
				return 0.6 - 0.3 * hand.Light()
			end,
		}, {
			Name = "Plate",
			Size = UDim2.fromScale(1, 1),
			Hand.WashLayer(hand, 3, 2),
			Components.Sheen(hand.Glint, 3),
			create("Frame")({
				Name = "BracketsHolder",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Components.Brackets(hand.Rise, function()
					return 0.65 - 0.35 * hand.Light()
				end, Layout.TAB_BRACKET_LENGTH, isLit),
			}),
		}),
	}) :: TextButton

	return { button, word }, scale
end

-- The tabs and his pink slab under the lit one, gliding between them, growing and pressing with the tab it lies on.
local function tabs(state: Types.TShopState, actions: Types.TShopActions, elapsed: () -> number): { Instance }
	local away = Parts.Away(state, elapsed, Timing.TABS)
	local pieces, scales = {}, {}
	for index in Parts.SECTIONS do
		local own, scale = tab(state, actions, elapsed, index)
		table.move(own, 1, #own, #pieces + 1, pieces)
		scales[index] = scale
	end
	local litIndex = function(): number
		for index, section in Parts.SECTIONS do
			if section.Key == state.Section() then return index end
		end
		return 1
	end
	local x = Hand.Spring(function(): number
		return Layout.TAB_LEFTS[litIndex()]
	end, Timing.PICK_PERIOD, Timing.PICK_DAMPING)

	table.insert(
		pieces,
		Components.Slab({ Kind = "Pink", Marks = true }, {
			Name = "Glider",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				return UDim2.fromOffset(
					math.round(x()) + Layout.TAB_SIZE.X / 2,
					Layout.TAB_TOP - lift() + Layout.TAB_SIZE.Y / 2 - math.round(Timing.TABS_DROP * away())
				)
			end,
			Size = UDim2.fromOffset(Layout.TAB_SIZE.X + 2, Layout.TAB_SIZE.Y + 2),
			ZIndex = 4,
			create("UIScale")({
				Scale = function()
					return scales[litIndex()]()
				end,
			}),
		})
	)

	return pieces
end

-- The offers on show, by section, in the catalog's order: one featured product (the gun's rarity's), and no paid
-- random items where they are restricted.
local function offersOf(state: Types.TShopState, section: ShopCore.TSection): { ShopCore.TOffer }
	local featured = ShopCore.FeaturedOffer(os.time())
	local list = {}
	for _, offer in ShopCore.OFFERS do
		if offer.Section ~= section then continue end
		-- Not created on Roblox yet (EGamePasses / EProducts at 0): nothing to sell it with.
		if offer.GamePassId == 0 and offer.ProductId == 0 then continue end
		if offer.Rarity and offer ~= featured then continue end
		if offer.IsRandomItem and state.IsRestricted() then continue end
		table.insert(list, offer)
	end

	return list
end

-- Where everything in the scroll goes, top to bottom: each section's header and its cards (what builds each, and
-- where). Returns them, each section's top and the content's height.
local function layout(state: Types.TShopState, actions: Types.TShopActions)
	local headers, placed = {}, {}
	local tops = {}
	local y = 8
	local half = (Layout.WIDTH - Layout.GAP) / 2
	local function header(index: number, info: (() -> string)?)
		local section = Parts.SECTIONS[index]
		tops[section.Key] = y
		table.insert(headers, { Section = section, Top = y, Info = info })
		y += Layout.HEADER + Layout.UNDER_HEADER
	end
	local function place(
		build: (Cards.TCardSpec) -> Frame,
		x: number,
		top: number,
		size: Vector2,
		extra: { [string]: any }?
	)
		table.insert(placed, { Build = build, X = x, Top = top, Size = size, Extra = extra })
	end

	-- FEATURED: the gun of these three days, then the class bundle, each across the row.
	header(1, function(): string
		state.Clock()
		return `ENDS IN {Parts.Countdown(state.FeaturedEndsAt() - os.time())}`
	end)
	place(function(spec)
		return Cards.FeaturedGun(state, actions, spec)
	end, 0, y, CardLayout.FEATURED)
	y += CardLayout.FEATURED.Y + Layout.GAP
	place(function(spec)
		return Cards.ClassBundle(state, actions, spec)
	end, 0, y, CardLayout.FEATURED)
	y += CardLayout.FEATURED.Y + Layout.SECTION_GAP

	-- BUNDLES.
	local bestSaving = 0
	for _, offer in offersOf(state, "Bundles") do
		bestSaving = math.max(bestSaving, ShopCore.Saving(offer, os.time()))
	end
	header(2, function(): string
		return `SAVE UP TO {math.floor(bestSaving * 100)}%`
	end)
	place(function(spec)
		return Cards.StarterPack(state, actions, spec)
	end, 0, y, CardLayout.BUNDLE)
	place(function(spec)
		return Cards.Arsenal(state, actions, spec)
	end, half + Layout.GAP, y, CardLayout.BUNDLE)
	y += CardLayout.BUNDLE.Y + Layout.SECTION_GAP

	-- GEMS: two packs to a row, the biggest across the row under them.
	local packs = offersOf(state, "Gems")
	local bestBonus = 0
	for _, offer in packs do
		bestBonus = math.max(bestBonus, ShopCore.GemsBonus(offer))
	end
	header(3, function(): string
		return `UP TO +{math.floor(bestBonus * 100)}% MORE GEMS`
	end)
	for index, offer in packs do
		if index == #packs and index > 4 then
			place(function(spec)
				return Cards.MegaPack(state, actions, offer, spec)
			end, 0, y, CardLayout.MEGA)
			y += CardLayout.MEGA.Y + Layout.GAP
			continue
		end
		local column = (index - 1) % 2
		place(function(spec)
			return Cards.GemPack(state, actions, offer, spec)
		end, column * (half + Layout.GAP), y, CardLayout.PACK)
		if column == 1 or index == #packs then
			y += CardLayout.PACK.Y + Layout.GAP
		end
	end
	y += Layout.SECTION_GAP - Layout.GAP

	-- GAMEPASSES: VIP across the row, then the rest two by two.
	header(4, function(): string
		return "YOURS FOREVER"
	end)
	local column = 0
	for _, offer in offersOf(state, "Passes") do
		if offer.Name == "Vip" then
			place(function(spec)
				return Cards.Pass(state, actions, offer, spec)
			end, 0, y, CardLayout.PASS_WIDE, { IsWide = true })
			y += CardLayout.PASS_WIDE.Y + Layout.GAP
			continue
		end
		place(function(spec)
			return Cards.Pass(state, actions, offer, spec)
		end, column * (half + Layout.GAP), y, CardLayout.PASS)
		column += 1
		if column == 2 then
			column = 0
			y += CardLayout.PASS.Y + Layout.GAP
		end
	end
	if column > 0 then
		y += CardLayout.PASS.Y + Layout.GAP
	end

	return headers, placed, tops, y + 16
end

local function window(state: Types.TShopState, actions: Types.TShopActions, elapsed: () -> number): { Instance }
	local headers, placed, tops, height = layout(state, actions)
	local function most(): number
		return math.max(height - windowHeight(), 0)
	end
	-- Where the scroll opens: the section the screen was opened on.
	local startY = vide.untrack(function(): number
		local top = tops[state.Section()] or 0
		return math.clamp(top - Layout.SCROLL_MARGIN, 0, most())
	end)
	local openHeight = vide.untrack(windowHeight)
	local canvasY = source(startY)

	local pieces = {}
	for _, header in headers do
		table.insert(
			pieces,
			Parts.Header(header.Section, Layout.WIDTH, header.Info, {
				Position = UDim2.fromOffset(Layout.LEFT, header.Top),
				ZIndex = 3,
			})
		)
	end
	-- Only the cards in the window as it opens deal in, one after another; the rest are in already, and nothing deals
	-- where it is not seen.
	local dealing = 0
	for _, entry in placed do
		local top, bottom = entry.Top, entry.Top + entry.Size.Y
		local isSeen = bottom > startY and top < startY + openHeight
		local deal = function(): number
			return 1
		end
		if isSeen then
			deal =
				Cards.Dealt(state, elapsed, math.min(Timing.CARDS + Timing.CARDS_STAGGER * dealing, Timing.CARDS_MAX))
			dealing += 1
		end
		local spec = {
			Position = Vector2.new(Layout.LEFT + entry.X, top),
			Deal = deal,
			-- Its art moves only while the screen is up and the card is in the window, give or take a little.
			IsActive = vide.derive(function(): boolean
				if not state.IsOpen() then return false end
				local y = canvasY()
				return bottom > y - 40 and top < y + windowHeight() + 40
			end),
		}
		for key, value in entry.Extra or {} do
			spec[key] = value
		end
		table.insert(pieces, entry.Build(spec))
	end

	-- The lit tab follows the scroll: the last section whose header is above a third of the window.
	vide.effect(function()
		local y = canvasY() + windowHeight() / 3
		local lit = "Featured"
		for _, section in Parts.SECTIONS do
			local top = tops[section.Key]
			if top and top <= y then lit = section.Key end
		end
		-- At the bottom the last section is lit, however short it is.
		if canvasY() >= most() - 4 then lit = Parts.SECTIONS[#Parts.SECTIONS].Key end
		vide.untrack(function()
			if state.Section() ~= lit then state.Section(lit) end
		end)
	end)

	local frame = create("ScrollingFrame")({
		Name = "Sections",
		Position = function()
			return UDim2.fromOffset(Layout.WINDOW.X, Layout.WINDOW.Y - lift())
		end,
		Size = function()
			return UDim2.fromOffset(Layout.WINDOW_SIZE.X, windowHeight())
		end,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(0, height),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 0,
		ElasticBehavior = Enum.ElasticBehavior.Never,
		ZIndex = 3,
		vide.changed("CanvasPosition", function(position: Vector2)
			canvasY(position.Y)
		end),
		pieces,
	}) :: ScrollingFrame
	-- After the canvas has its size, or the position is clamped to an empty one; set on the frame it is built, so it
	-- never draws a frame at the top first.
	frame.CanvasPosition = Vector2.new(0, startY)

	local scrollTops = {}
	for key, top in tops do
		scrollTops[key] = math.max(top - Layout.SCROLL_MARGIN, 0)
	end
	actions.MarkScroll(frame, scrollTops)
	return {
		frame,
		Scrollbar.Build(frame, {
			Length = function(): number
				return Layout.SCROLLBAR_LENGTH + lift()
			end,
		}, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = function()
				return UDim2.fromOffset(Layout.SCROLLBAR.X, Layout.SCROLLBAR.Y - lift())
			end,
			ZIndex = 4,
		}),
	}
end

-- His dark panel holding the tabs and the scroll, growing in from a little under its size.
local function panel(state: Types.TShopState, elapsed: () -> number): Frame
	local away = Parts.Away(state, elapsed, Timing.PANEL_DELAY)
	local faded = Parts.Faded(state, elapsed, Timing.PANEL_DELAY)
	local shown = function(): number
		return 1 - faded()
	end
	return create("Frame")({
		Name = "PanelHolder",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			return UDim2.fromOffset(
				Layout.PANEL.X + Layout.PANEL_SIZE.X / 2,
				Layout.PANEL.Y - lift() + (Layout.PANEL_SIZE.Y + lift()) / 2
			)
		end,
		Size = function()
			return UDim2.fromOffset(Layout.PANEL_SIZE.X, Layout.PANEL_SIZE.Y + lift())
		end,
		BackgroundTransparency = 1,
		ZIndex = 2,
		create("UIScale")({
			Scale = function()
				return 1 - (1 - Timing.PANEL_FROM) * away()
			end,
		}),
		Components.FadeGroup("Back", shown, { Size = UDim2.fromScale(1, 1) }, {
			Components.Panel({ Brackets = true, Tall = true, Wide = true }, {
				Name = "Panel",
				Size = UDim2.fromScale(1, 1),
			}),
		}),
	})
end

-- It stands over the gift list's dim and goes back one step: with the gift list up, it shuts that.
local function exit(state: Types.TShopState, actions: Types.TShopActions, elapsed: () -> number): TextButton
	return Components.Exit(Parts.Away(state, elapsed, Timing.EXIT_DELAY), function()
		if state.GiftOffer() then
			actions.CloseGift()
		else
			actions.Close()
		end
	end, { ZIndex = 22 })
end

-- The line left of EXIT: a gift sent, refused or received. It rises in, holds, and fades.
local function message(state: Types.TShopState): TextLabel
	local shown = derive(function(): number
		local t = state.Now() - state.MessageAt()
		if t < Timing.MESSAGE_IN then return Motion.Out(math.clamp(t / Timing.MESSAGE_IN, 0, 1)) end
		return 1 - math.clamp((t - Timing.MESSAGE_HOLD) / Timing.MESSAGE_IN, 0, 1)
	end)

	return Label({
		Name = "Message",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			return UDim2.fromOffset(Layout.MESSAGE.X, Layout.MESSAGE.Y + math.round(10 * (1 - shown())))
		end,
		Size = UDim2.fromOffset(640, Layout.MESSAGE_TEXT),
		TextSize = Layout.MESSAGE_TEXT,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = state.MessageColor,
		TextTransparency = function()
			return 1 - shown()
		end,
		Visible = function()
			return shown() > 0
		end,
		Text = state.Message,
		ZIndex = 4,
	})
end

function Screen.Build(state: Types.TShopState, actions: Types.TShopActions): { any }
	local elapsed = Parts.Elapsed(state)
	local dimFaded = Parts.Faded(state, elapsed, 0)
	local panelFaded = Parts.Faded(state, elapsed, Timing.PANEL_DELAY)

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
		panel(state, elapsed),
		-- The tabs and the scroll fade with the panel, in and out, as one: each card's own fade is only its deal.
		Components.FadeGroup("Content", function(): number
			return 1 - panelFaded()
		end, { Size = UDim2.fromScale(1, 1), ZIndex = 3 }, {
			tabs(state, actions, elapsed),
			window(state, actions, elapsed),
		}),
		exit(state, actions, elapsed),
		message(state),
		Gift.Build(state, actions),
	}
end

return Screen
