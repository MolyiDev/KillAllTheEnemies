--!nonstrict
-- The lobby's classes screen (UIMatt.md, Classes), on the designer's drawn rects at 1080: the CLASSES / EQUIPMENT tabs
-- along the top, ALL CLASSES on the left, the class on its stage in the middle, ABILITIES on the right, EXIT at the
-- bottom. The HUD's currency stays where it is and the rest of the HUD steps aside (Hud).
-- Our content in his style: Human is the only class and everybody's, the stage holds the player's own avatar (Stage),
-- and the abilities are drawn as the run's cards draw them (AbilityPicture). An ability's levels are bought here with
-- Gems (ClassesService decides).
--
-- Two pages, one screen: the tabs and EXIT are the screen's; the rest is the CLASSES page, and EQUIPMENT is
-- EquipmentController's page (handed to Build), laid over it on the same panels' rects. It fades in and out over this one, so a tab
-- swaps what is in the panels and the panels stay; under it, this page's pieces deal in again as it comes back.
--
-- Every gesture timed from a stamp reads state.Now, which init ticks only while one runs, through a derive, so it is
-- written only while it moves; the hand's reactions are vide springs.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local TextService = game:GetService("TextService")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local AbilityPicture = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.AbilityPicture)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local ItemCard = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.ItemCard)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local AbilitiesCore = require(ReplicatedStorage.GlobalShared.Core.AbilitiesCore)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local EClassesIds = require(ReplicatedStorage.Types.Enums.Data.EClassesIds)
local TData = require(ReplicatedStorage.Types.TData)
local Flight = require(script.Flight)
local Stage = require(script.Stage)
local panelTop = require(script.Parent.Parent.Parent.Utils.panelTop)
local Types = require(script.Parent.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress

-- His drawn rects (outer, edge included) in px at 1920 x 1080. The list from the frame's top left, the tabs from its
-- top middle, the info panel's right edge from the frame's right.
local Layout = table.freeze({
	-- The tabs, each one's left from the middle, over his span: 237 wide and 23 apart rather than his 240 and 15, as a
	-- Take tab's brackets reach 17 px out under a press (UI.md, "Brackets, picked and side by side"). The glider is a px
	-- bigger all round than the plate it lies on; the picked tab's glyph stands GLYPH_GAP before its word.
	TAB_LEFTS = { -249, 12 },
	TAB_TOP = 52,
	TAB_SIZE = Vector2.new(237, 64),
	TAB_BRACKET_LENGTH = 16,
	TAB_GLYPH = 22,
	TAB_GLYPH_GAP = 12,
	TAB_TEXT = 26,
	-- The two side panels; the info panel's right edge is INFO_RIGHT from the screen's.
	LIST = Vector2.new(40, 190),
	INFO_RIGHT = 40,
	-- Where each panel looks into the streak texture: it is 1024 px square, and the panels up to about 940 tall once
	-- grown under the top bar.
	LIST_TEXTURE = Vector2.new(120, 60),
	INFO_TEXTURE = Vector2.new(380, 80),
	PANEL_SIZE = Vector2.new(440, 850),
	PANEL_BRACKET_LENGTH = 24,
	-- A panel's header, from its corner: the glyph's middle, the title, the count's right edge, the rule.
	HEADER_GLYPH = Vector2.new(35, 39),
	HEADER_HELMET = 20,
	HEADER_STAR = 20,
	HEADER_TITLE = Vector2.new(56, 24),
	HEADER_TEXT = 29,
	HEADER_INFO_RIGHT = 418,
	HEADER_INFO_Y = 30,
	HEADER_INFO_TEXT = 18,
	RULE = Vector2.new(24, 64),
	RULE_WIDTH = 392,
	-- A class card in the list, and inside it the glyph's box, the rarity, the name and the EQUIPPED tag.
	CLASS_CARD = Vector2.new(24, 84),
	CLASS_CARD_SIZE = Vector2.new(392, 88),
	CLASS_CARD_STEP = 98,
	GLYPH_BOX = Vector2.new(12, 12),
	GLYPH_BOX_SIZE = Vector2.new(63, 64),
	CLASS_GLYPH = 44,
	RARITY = Vector2.new(92, 20),
	RARITY_TEXT = 15,
	CLASS_NAME = Vector2.new(92, 45),
	CLASS_NAME_TEXT = 26,
	TAG = Vector2.new(285, 10),
	TAG_SIZE = Vector2.new(95, 24),
	TAG_TEXT = 13,
	-- The ability cards, from the info panel's corner, and inside one its picture's box.
	-- 117 wide and 21 apart rather than his 123 and 12, over the same span: two cards' brackets crossed at his.
	ABILITY_LEFTS = { 23, 161, 299 },
	ABILITY_TOP = 88,
	ABILITY_SIZE = Vector2.new(117, 128),
	PICTURE_SIZE = 84,
	-- The picked ability's name, ?, stars, stat rows and the two slabs, from the info panel's corner.
	ABILITY_NAME = Vector2.new(24, 240),
	ABILITY_NAME_TEXT = 48,
	HELP = Vector2.new(376, 244),
	HELP_SIZE = 40,
	HELP_TEXT = 26,
	STARS = Vector2.new(35, 310),
	STAR_STEP = 33,
	STAR_GLYPH = 20,
	STAT_X = 24,
	STAT_TOPS = { 342, 418 },
	STAT_SIZE = Vector2.new(392, 64),
	STAT_LABEL = Vector2.new(18, 23),
	STAT_LABEL_TEXT = 18,
	STAT_VALUE_RIGHT = 378,
	STAT_VALUE_Y = 16,
	STAT_VALUE_TEXT = 32,
	-- The arrow between a stat's value and the next level's (his is the font's own), and the room either side of it.
	STAT_ARROW_TEXT = 24,
	STAT_ARROW_GAP = 8,
	-- The next level's price over UPGRADE: its row's top (51 over the slab, as he drew it), the glyph's longer side,
	-- the gap and the number's size.
	COST_Y = 601,
	COST_GLYPH = 27,
	COST_GAP = 10,
	COST_TEXT = 34,
	DESCRIPTION = Vector2.new(24, 296),
	DESCRIPTION_WIDTH = 392,
	DESCRIPTION_TEXT = 18,
	DESCRIPTION_PAD = 16,
	UPGRADE = Vector2.new(22, 652),
	EQUIP = Vector2.new(22, 749),
	SLAB_SIZE = Vector2.new(394, 78),
	UPGRADE_TEXT = 29,
	UPGRADE_TRACKING = 1,
	EQUIP_TEXT = 35,
	EQUIP_TRACKING = 0,
	EQUIP_TEXT_LEFT = 135,
	-- The check on EQUIPPED: its middle from the slab's corner, and its longer side.
	CHECK = Vector2.new(106, 39),
	CHECK_GLYPH = 31,
})
-- The side panels are raised to just under the top bar, their bottoms staying put: what is written on them rides up
-- with the top, and ABILITIES' price and its two slabs keep their place.
local lift = panelTop.Lift(Layout.LIST.Y)

-- His colours that are not in the Palette, sampled off his art: the rules, the glyph box's face, a stat row's edge
-- and face, an unlit star, the price tag's edge, the ULT tag.
local Colors = table.freeze({
	RULE = Color3.fromRGB(140, 111, 211),
	RULE_TRANSPARENCY = 0.55,
	GLYPH_BOX_FACE = Color3.fromRGB(40, 35, 60),
	STAT_EDGE = Color3.fromRGB(67, 53, 106),
	STAT_FACE = Color3.fromRGB(29, 23, 52),
	STAR_OFF = Color3.fromRGB(60, 55, 76),
	ULT = Color3.fromRGB(232, 176, 56),
	-- His cards' edge is their accent this much darker, the glyph box's edge more; how far a card's face warms toward
	-- its accent at the bottom.
	CARD_EDGE = 0.77,
	GLYPH_BOX_EDGE = 0.65,
	CLASS_TINT = 0.12,
	DIM_TRANSPARENCY = 0.7,
})

-- What each ability's card wears, by kind (the HUD's colours for the same abilities, his gold for the ultimate).
local ACCENTS = table.freeze({
	Decoy = Palette.Pink,
	FoamCannon = Palette.Steel,
	OrbitalCannon = Palette.Gold,
})
local MAX_LEVEL = AbilitiesCore.MAX_LEVEL
-- The profile's SelectedClass is not sent to the client, and Human is the only class: everybody's is equipped.
local EQUIPPED_CLASS = EClassesIds.Human

-- Seconds after the screen opens (or an ability is picked): when each piece starts in, how long it takes, how far it
-- comes from. Everything decelerates in and accelerates out, no overshoot; the pieces come in the order the screen is
-- read, the stage first. The way out is quicker and all at once.
local Timing = table.freeze({
	IN = 0.42,
	OUT = 0.22,
	DIM = 0.3,
	SHEEN = 0.6,
	SHEEN_LEAD = 0.12,
	-- The stage's rings and floor, then its name, its avatar and its tag.
	STAGE = 0,
	STAGE_NAME = 0.12,
	AVATAR = 0.18,
	STAGE_TAG = 0.22,
	TABS = 0.07,
	TABS_STAGGER = 0.05,
	-- A tab picked: the slab glides under it on a spring that carries a little past (a movement), its glyph grows in
	-- and its word turns white.
	PICK_PERIOD = 0.3,
	PICK_DAMPING = 0.72,
	LIST = 0.06,
	INFO = 0.1,
	EXIT = 0.12,
	CLASS_CARD = 0.24,
	CLASS_STEP = 0.05,
	-- EQUIPPED is stamped on this long after its card starts in.
	TAG_DELAY = 0.25,
	TAG = 0.3,
	ABILITY_CARDS = { 0.26, 0.31, 0.36 },
	-- The details under the cards come in this long after the screen opens, and from the moment an ability is picked.
	DETAILS = 0.36,
	NAME = 0,
	STARS = 0.08,
	STAR_STEP = 0.06,
	STAR = 0.3,
	STATS = { 0.12, 0.18 },
	-- A stat's number counts up from a beat after its row, showing in the first share of the count.
	COUNT_DELAY = 0.08,
	COUNT = 0.45,
	COUNT_FADE = 1 / 3,
	-- How fast the ?'s description comes and goes.
	HELP = 0.14,
	SLABS = { 0.3, 0.36 },
	COST = 0.26,
	-- A level bought: as its Gems land its star is struck in on a spring and throws one gold ring (the weapons screen's).
	STAR_POP_PERIOD = 0.26,
	STAR_POP_DAMPING = 0.58,
	STAR_POP = 0.35,
	STAR_RING = 0.5,
	STAR_RING_REACH = 16,
	-- A press refused: the price flashes and shakes this long, this many px.
	REFUSED = 0.5,
	JOLT = 7,
	JOLT_SECONDS = 0.16,
	FROM_LEFT = 520,
	FROM_RIGHT = 520,
	FROM_TOP = 150,
	NAME_FROM = 18,
	DETAIL_FROM = 26,
	-- Every gesture of an open, a shut or a pick is over by now.
	SETTLE = 1.6,
})

-- What a card and a picture do under the hand: the picture grows this share with the rise, and a pick swings it (deg) and pops it.
local Gesture = table.freeze({
	-- A class card's glow at rest (the ?'s description's as the ability cards' was), and how much the hand lights it.
	CARD_GLOW = 0.85,
	ABILITY_GLOW = 0.8,
	GLOW_LIT = 0.35,
	-- His brackets at rest and how much the hand lights them.
	BRACKETS_REST = 0.65,
	BRACKETS_LIT = 0.35,
	-- EQUIPPED stamps down from this much bigger.
	STAMP = 0.6,
	PICTURE_RISE = 0.1,
	PICK_SWING = 18,
	PICK_POP = 0.18,
	PICK_SECONDS = 0.5,
})

local Classes = {}

-- How long Now must keep ticking after the screen opens or shuts, or an ability is picked.
Classes.SETTLE_SECONDS = Timing.SETTLE
-- How long a level's Gems fly before it is shown.
Classes.FLIGHT_SECONDS = Flight.SECONDS

-- ============================== Pieces ==============================

local function label(props: { [any]: any }): TextLabel
	return create("TextLabel")({
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		FontFace = Font.Display,
		TextColor3 = Palette.White,
		ZIndex = 4,
		props,
	})
end

local function shade(color: Color3, share: number): Color3
	return Color3.new(color.R * share, color.G * share, color.B * share)
end

-- Whether the CLASSES page is on show: the screen up, on its tab.
local function isPageShown(state: Types.TLobbyState): boolean
	return state.IsClassesOpen() and state.ClassesPage() == "Classes"
end

-- When the CLASSES page last came or went: the screen opening or shutting, or a tab picked since.
local function pageAt(state: Types.TLobbyState): number
	return math.max(state.ClassesToggledAt(), state.ClassesPageAt())
end

-- Whether this page's pieces are drawn: on show, or still under EQUIPMENT while it fades in over them (`coverSeconds`).
-- Covered, they are hidden, so nothing under EQUIPMENT's panels takes the hand.
local function isPageDrawn(state: Types.TLobbyState, coverSeconds: number): boolean
	if state.ClassesPage() == "Classes" then return true end
	return state.Now() - state.ClassesPageAt() < coverSeconds
end

-- 0 away, 1 in place: a piece's way in `delay` after the screen opens, and its way out as it shuts. Derived, so it is
-- written only while it moves.
local function presence(state: Types.TLobbyState, delay: number): () -> number
	return derive(function(): number
		local now, at = state.Now(), state.ClassesToggledAt()
		if state.IsClassesOpen() then return Motion.Decelerate(Progress(now, at, Timing.IN, delay)) end
		return 1 - Motion.Accelerate(Progress(now, at, Timing.OUT))
	end)
end

-- The same for a piece of the CLASSES page that is not under a panel (the stage): it comes and goes with the page.
local function pagePresence(state: Types.TLobbyState, delay: number): () -> number
	return derive(function(): number
		local now, at = state.Now(), pageAt(state)
		if isPageShown(state) then return Motion.Decelerate(Progress(now, at, Timing.IN, delay)) end
		return 1 - Motion.Accelerate(Progress(now, at, Timing.OUT))
	end)
end

-- 0 to 1: a piece inside a panel coming in, `delay` after its page comes up, over `seconds`. 1 while it goes: it
-- leaves with its panel, or stays under EQUIPMENT.
local function arrival(state: Types.TLobbyState, delay: number, seconds: number): () -> number
	return derive(function(): number
		if not isPageShown(state) then return 1 end
		return Motion.Decelerate(Progress(state.Now(), pageAt(state), seconds, delay))
	end)
end

-- 0 to 1: a detail of the picked ability coming in, `delay` into the details, both when the page comes up and when
-- another ability is picked, and from the moment `again` stamps if it is given. 1 while the page goes: the details
-- leave with their panel.
local function dealt(state: Types.TLobbyState, delay: number, seconds: number, again: (() -> number)?): () -> number
	return derive(function(): number
		if not isPageShown(state) then return 1 end
		local now = state.Now()
		local opened = Progress(now, pageAt(state), seconds, Timing.DETAILS + delay)
		local picked = Progress(now, state.AbilityPickedAt(), seconds, delay)
		-- A stamp still to come (a level whose Gems are flying) leaves the details as they stand until it arrives.
		local stamp = if again then again() else -math.huge
		local redealt = if now >= stamp then Progress(now, stamp, seconds, delay) else 1
		return math.min(opened, picked, redealt)
	end)
end

-- The light crossing a piece as it lands: 0 to 1, and 1 at rest. A piece of the screen's lands as it opens, one inside
-- the CLASSES page (`isPage`) each time the page comes up.
local function landing(state: Types.TLobbyState, delay: number, isPage: boolean?): () -> number
	return derive(function(): number
		local isUp = if isPage then isPageShown(state) else state.IsClassesOpen()
		if not isUp then return 1 end
		local at = if isPage then pageAt(state) else state.ClassesToggledAt()
		return Progress(state.Now(), at, Timing.SHEEN, delay + Timing.IN - Timing.SHEEN_LEAD)
	end)
end

-- A thin rule `width` px long, his lavender.
local function rule(position: UDim2, width: number): Frame
	return create("Frame")({
		Name = "Rule",
		Position = position,
		Size = UDim2.fromOffset(width, 1),
		BackgroundColor3 = Colors.RULE,
		BackgroundTransparency = Colors.RULE_TRANSPARENCY,
		BorderSizePixel = 0,
		ZIndex = 4,
	})
end

-- A dark side panel with its header: the glyph, the title, the count on the right (if any) and the rule under them.
local function panel(name: string, phase: Vector2, glyph: Instance, title: string, info: string?, props: { [any]: any })
	return Components.Panel({
		Tall = true,
		Brackets = true,
		BracketLength = Layout.PANEL_BRACKET_LENGTH,
		TexturePhase = phase,
	}, {
		Name = name,
		Size = function()
			return UDim2.fromOffset(Layout.PANEL_SIZE.X, Layout.PANEL_SIZE.Y + lift())
		end,
		glyph,
		label({
			Name = "Title",
			Position = UDim2.fromOffset(Layout.HEADER_TITLE.X, Layout.HEADER_TITLE.Y),
			Size = UDim2.fromOffset(300, Layout.HEADER_TEXT),
			TextSize = Layout.HEADER_TEXT,
			Text = title,
		}),
		if info
			then label({
				Name = "Info",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromOffset(Layout.HEADER_INFO_RIGHT, Layout.HEADER_INFO_Y),
				Size = UDim2.fromOffset(200, Layout.HEADER_INFO_TEXT),
				TextXAlignment = Enum.TextXAlignment.Right,
				FontFace = Font.DisplayBold,
				TextSize = Layout.HEADER_INFO_TEXT,
				TextColor3 = Palette.Gold,
				Text = info,
			})
			else nil,
		rule(UDim2.fromOffset(Layout.RULE.X, Layout.RULE.Y), Layout.RULE_WIDTH),
		props,
	})
end

-- A star of his rating row: gold up to the level, darkened after it.
local function star(isLit: () -> boolean, props: { [any]: any }): ImageLabel
	return Components.Picture(EIcons.Star, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = Components.PictureBox(Layout.STAR_GLYPH),
		ImageColor3 = function()
			return if isLit() then Palette.White else Colors.STAR_OFF
		end,
		ZIndex = 4,
		props,
	})
end

-- ============================== The top ==============================

-- What each page's tab says, and the glyph it wears.
local PAGES = table.freeze({
	Classes = table.freeze({ Glyph = EIcons.Helmet, Title = "CLASSES" }),
	Equipment = table.freeze({ Glyph = EIcons.UpgradeArmor, Title = "EQUIPMENT" }),
})
local TAB_PAGES = table.freeze({ "Classes", "Equipment" } :: { Types.TClassesPage })

-- One tab: his dark plate whose brackets close round it while its page is on show, and its word over the slab, white
-- with the page's glyph grown in beside it while picked, lavender alone while not. Returns its pieces and its hand's
-- scale, for the slab lying on it.
local function tab(state: Types.TLobbyState, actions: Types.TLobbyActions, index: number): ({ Instance }, () -> number)
	local page = TAB_PAGES[index]
	local drop = presence(state, Timing.TABS + Timing.TABS_STAGGER * (index - 1))
	local landed = landing(state, Timing.TABS + Timing.TABS_STAGGER * (index - 1))
	local isPicked = derive(function(): boolean
		return state.ClassesPage() == page
	end)
	local hand = Hand.React("Take", function(): boolean
		return not isPicked()
	end)
	-- 1 on the page on show, gliding to 0 as the other is picked: the glyph grows in and the word whitens with it.
	local picked = Hand.Spring(function(): number
		return if isPicked() then 1 else 0
	end, Timing.PICK_PERIOD)
	local lit = function(): number
		return math.clamp(picked(), 0, 1)
	end
	local ink = function(): Color3
		return Palette.Lavender:Lerp(Palette.White, lit())
	end
	local position = derive(function(): UDim2
		return UDim2.new(
			0.5,
			Layout.TAB_LEFTS[index] + Layout.TAB_SIZE.X / 2,
			0,
			Layout.TAB_TOP + Layout.TAB_SIZE.Y / 2 - math.round(Timing.FROM_TOP * (1 - drop()))
		)
	end)

	local word = create("Frame")({
		Name = `{page}TabWord`,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(Layout.TAB_SIZE.X, Layout.TAB_SIZE.Y),
		BackgroundTransparency = 1,
		ZIndex = 5,
		create("UIScale")({ Scale = hand.Scale }),
		create("UIListLayout")({
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		-- The glyph's box opens as the tab is picked, so the word slides over to make room, as his two tabs set it.
		create("Frame")({
			Name = "GlyphBox",
			LayoutOrder = 1,
			Size = function()
				return UDim2.fromOffset(math.round((Layout.TAB_GLYPH + Layout.TAB_GLYPH_GAP) * lit()), Layout.TAB_GLYPH)
			end,
			BackgroundTransparency = 1,
			Components.Picture(PAGES[page].Glyph, {
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
		label({
			LayoutOrder = 2,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, Layout.TAB_TEXT),
			TextSize = Layout.TAB_TEXT,
			TextColor3 = ink,
			Text = PAGES[page].Title,
		}),
	})

	local button = Components.Button({
		Name = `{page}Tab`,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(Layout.TAB_SIZE.X, Layout.TAB_SIZE.Y),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Activated = function()
			if isPicked() then return end
			hand.Commit()
			actions.PickClassesPage(page)
		end,
		hand.Events,
		create("UIScale")({ Scale = hand.Scale }),
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
			Components.Sheen(Hand.Sheen(hand, landed), 3),
			create("Frame")({
				Name = "BracketsHolder",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Components.Brackets(hand.Rise, function()
					return Gesture.BRACKETS_REST - Gesture.BRACKETS_LIT * hand.Light()
				end, Layout.TAB_BRACKET_LENGTH, isPicked),
			}),
		}),
	}) :: TextButton

	return { button, word }, hand.Scale
end

-- The two tabs and his pink slab under the one on show, gliding from one to the other. The slab grows and presses with
-- the tab it lies on, and has no brackets of its own: the plate's, under it, answer the hand (UI.md).
local function tabs(state: Types.TLobbyState, actions: Types.TLobbyActions): { Instance }
	local drop = presence(state, Timing.TABS)
	local pieces, scales = {}, {}
	for index in TAB_PAGES do
		local own, scale = tab(state, actions, index)
		table.move(own, 1, #own, #pieces + 1, pieces)
		scales[index] = scale
	end
	local pickedIndex = function(): number
		return if state.ClassesPage() == "Equipment" then 2 else 1
	end
	local x = Hand.Spring(function(): number
		return Layout.TAB_LEFTS[pickedIndex()]
	end, Timing.PICK_PERIOD, Timing.PICK_DAMPING)

	table.insert(
		pieces,
		Components.Slab({ Kind = "Pink", Marks = true }, {
			Name = "Glider",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				return UDim2.new(
					0.5,
					math.round(x()) + Layout.TAB_SIZE.X / 2,
					0,
					Layout.TAB_TOP + Layout.TAB_SIZE.Y / 2 - math.round(Timing.FROM_TOP * (1 - drop()))
				)
			end,
			Size = UDim2.fromOffset(Layout.TAB_SIZE.X + 2, Layout.TAB_SIZE.Y + 2),
			ZIndex = 4,
			create("UIScale")({
				Scale = function()
					return scales[pickedIndex()]()
				end,
			}),
		})
	)

	return pieces
end

-- ============================== ALL CLASSES ==============================

-- A class's card in the list: his tinted card in the rarity's colour, the class's glyph in its box, the rarity, the
-- name, and EQUIPPED on the one worn.
local function classCard(state: Types.TLobbyState, index: number, class: TData.TClass, celebrate: () -> ()): TextButton
	local delay = Timing.CLASS_CARD + Timing.CLASS_STEP * (index - 1)
	-- Operate: a Take card this wide grew 12 px a side under the hand and its ring reached the panel's edge.
	local hand = Hand.React("Operate")
	local dealIn = arrival(state, delay, Timing.IN)
	local landed = landing(state, delay, true)
	local tag = arrival(state, delay + Timing.TAG_DELAY, Timing.TAG)
	local isEquipped = class.Id == EQUIPPED_CLASS
	local rarityLook = Stage.RARITIES[class.Rarity]
	local rarity = rarityLook.Accent
	local size = Layout.CLASS_CARD_SIZE

	return Components.Button({
		Name = class.Name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(
			Layout.CLASS_CARD.X + size.X / 2,
			Layout.CLASS_CARD.Y + Layout.CLASS_CARD_STEP * (index - 1) + size.Y / 2
		),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Activated = function()
			hand.Commit()
			celebrate()
		end,
		hand.Events,
		create("UIScale")({
			Scale = function()
				return dealIn() * hand.Scale()
			end,
		}),
		-- Picked, as every class here is: its brackets stand closed round it.
		Components.Brackets(hand.Rise, nil, nil, function()
			return true
		end),
		Components.Card({
			Accent = shade(rarity, Colors.CARD_EDGE),
			Glow = rarity,
			GlowTransparency = function()
				return Gesture.CARD_GLOW - Gesture.GLOW_LIT * hand.Light()
			end,
			Tint = Colors.CLASS_TINT,
			Marks = true,
			Edge = 3,
		}, {
			Name = "Card",
			Size = UDim2.fromScale(1, 1),
			Hand.WashLayer(hand, 3, 2),
			Components.Sheen(Hand.Sheen(hand, landed), 3),
			create("Frame")({
				Name = "GlyphBox",
				Position = UDim2.fromOffset(Layout.GLYPH_BOX.X, Layout.GLYPH_BOX.Y),
				Size = UDim2.fromOffset(Layout.GLYPH_BOX_SIZE.X, Layout.GLYPH_BOX_SIZE.Y),
				BackgroundColor3 = shade(rarity, Colors.GLYPH_BOX_EDGE),
				BorderSizePixel = 0,
				ZIndex = 4,
				create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
				create("Frame")({
					Name = "Face",
					Position = UDim2.fromOffset(2, 2),
					Size = UDim2.new(1, -4, 1, -4),
					BackgroundColor3 = Colors.GLYPH_BOX_FACE,
					BorderSizePixel = 0,
					create("UICorner")({ CornerRadius = UDim.new(0, 1) }),
					Components.Picture(class.Icon, {
						Name = "Glyph",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.5),
						Size = Components.PictureBox(Layout.CLASS_GLYPH),
						create("UIScale")({
							Scale = function()
								return 1 + Gesture.PICTURE_RISE * hand.Rise()
							end,
						}),
					}),
				}),
			}),
			label({
				Name = "Rarity",
				Position = UDim2.fromOffset(Layout.RARITY.X, Layout.RARITY.Y),
				Size = UDim2.fromOffset(200, Layout.RARITY_TEXT),
				TextSize = Layout.RARITY_TEXT,
				TextColor3 = rarity,
				Text = rarityLook.Text,
			}),
			label({
				Name = "ClassName",
				Position = UDim2.fromOffset(Layout.CLASS_NAME.X, Layout.CLASS_NAME.Y),
				Size = UDim2.fromOffset(260, Layout.CLASS_NAME_TEXT),
				TextSize = Layout.CLASS_NAME_TEXT,
				Text = string.upper(class.Name),
			}),
			if isEquipped
				then create("Frame")({
					Name = "Equipped",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(
						Layout.TAG.X + Layout.TAG_SIZE.X / 2,
						Layout.TAG.Y + Layout.TAG_SIZE.Y / 2
					),
					Size = UDim2.fromOffset(Layout.TAG_SIZE.X, Layout.TAG_SIZE.Y),
					BackgroundColor3 = Palette.Green,
					BorderSizePixel = 0,
					ZIndex = 5,
					create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
					-- Stamped on once the card has landed: it comes down from a little bigger.
					create("UIScale")({
						Scale = function()
							local t = tag()
							return if t <= 0 then 0 else 1 + Gesture.STAMP * (1 - t)
						end,
					}),
					label({
						Size = UDim2.fromScale(1, 1),
						TextXAlignment = Enum.TextXAlignment.Center,
						TextYAlignment = Enum.TextYAlignment.Center,
						TextSize = Layout.TAG_TEXT,
						TextColor3 = Palette.Ink,
						Text = "EQUIPPED",
					}),
				})
				else nil,
		}),
	})
end

local function classList(state: Types.TLobbyState, celebrate: () -> ()): Frame
	local shown = presence(state, Timing.LIST)
	local landed = landing(state, Timing.LIST)
	local all = DataCore.Classes.All
	local cards = table.create(#all)
	for index, class in all do
		cards[index] = classCard(state, index, class, celebrate)
	end

	return panel(
		"ClassList",
		Layout.LIST_TEXTURE,
		Components.Picture(EIcons.Helmet, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(Layout.HEADER_GLYPH.X, Layout.HEADER_GLYPH.Y),
			Size = Components.PictureBox(Layout.HEADER_HELMET),
			ZIndex = 4,
		}),
		"ALL CLASSES",
		-- Every class here is owned by everybody (DatabaseService's default).
		`{#all} / {#all} OWNED`,
		{
			Position = function()
				return UDim2.fromOffset(
					Layout.LIST.X - math.round(Timing.FROM_LEFT * (1 - shown())),
					Layout.LIST.Y - lift()
				)
			end,
			Components.Sheen(landed, 3),
			cards,
		}
	)
end

-- ============================== ABILITIES ==============================

-- An ability's card: his card in the ability's colour, its price (or ULT) in the corner, its model and its name. A
-- pick swings the model and pops it.
local function abilityCard(
	state: Types.TLobbyState,
	actions: Types.TLobbyActions,
	index: number,
	ability: TData.TAbility,
	isUltimate: boolean
): TextButton
	local delay = Timing.ABILITY_CARDS[index]
	local hand = Hand.React("Take")
	local accent = ACCENTS[ability.Kind] or Palette.Steel
	local dealIn = arrival(state, delay, Timing.IN)
	local landed = landing(state, delay, true)
	local isPicked = derive(function(): boolean
		return state.ShownAbility() == index
	end)
	local picked = derive(function(): number
		if not isPicked() then return 1 end
		return Progress(state.Now(), state.AbilityPickedAt(), Gesture.PICK_SECONDS)
	end)
	local size = Layout.ABILITY_SIZE

	return ItemCard.Build({
		Name = ability.Kind,
		Size = size,
		Position = UDim2.fromOffset(Layout.ABILITY_LEFTS[index] + size.X / 2, Layout.ABILITY_TOP + size.Y / 2),
		ZIndex = 2,
		Hand = hand,
		Accent = accent,
		Title = string.upper(ability.Name),
		IsSelected = isPicked,
		Grown = dealIn,
		Sheen = landed,
		Picture = AbilityPicture.Build(
			ability.Kind,
			{
				Rotation = function(): number
					return Gesture.PICK_SWING * Motion.Swing(picked())
				end,
				Scale = function(): number
					return 1 + Gesture.PICK_POP * Motion.Bump(picked())
				end,
			},
			state.Doll,
			{
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(Layout.PICTURE_SIZE, Layout.PICTURE_SIZE),
			}
		),
		Children = {
			if isUltimate
				then ItemCard.Chip("ULT", Colors.ULT, true)
				else ItemCard.Chip(`${ability.Cost or 0}`, Palette.Green),
		},
		Activated = function()
			actions.PickAbility(index)
		end,
	})
end

local function seconds(number: string): string
	return `{number}s`
end

-- A stat as the rows write it: the number shown (a share as a percentage; the value itself when absent), and the
-- words round it.
local SHOWN: { [TData.TAbilityStat]: (value: number) -> number } = table.freeze({
	DamageTaken = function(value: number): number
		return (value - 1) * 100
	end,
	BossShare = function(value: number): number
		return value * 100
	end,
})
local WORDS: { [TData.TAbilityStat]: (number: string) -> string } = table.freeze({
	Cooldown = seconds,
	Duration = seconds,
	ChargeKills = function(number: string): string
		return `{number} KILLS`
	end,
	AngleDeg = function(number: string): string
		return `{number}°`
	end,
	DamageTaken = function(number: string): string
		return `+{number}%`
	end,
	BossShare = function(number: string): string
		return `{number}%`
	end,
})

type TStatLine = { Label: string, Stat: TData.TAbilityStat, Current: number, Next: number? }

-- `ability`'s rows at `level`: what the next level raises, from what to what. At the top, what the last level raised,
-- as it stands.
local function statsOf(ability: TData.TAbility, level: number): { TStatLine }
	local isMax = level >= MAX_LEVEL
	local step = ability.Levels[if isMax then #ability.Levels else level]
	if not step then return {} end
	local leveled = AbilitiesCore.AtLevel(ability, level) :: any

	local lines = table.create(#step)
	for index, change in step do
		lines[index] = {
			Label = change.Label,
			Stat = change.Stat,
			Current = leveled[change.Stat] or 0,
			Next = if isMax then nil else change.Value,
		}
	end

	return lines
end

-- `value` of `stat` written `share` of the way up its count, in the steps its whole value is written in: whole
-- numbers, or tenths for one that has them.
local function statText(stat: TData.TAbilityStat, value: number, share: number): string
	local toShown = SHOWN[stat]
	local shown = if toShown then toShown(value) else value
	local isWhole = math.abs(shown - math.round(shown)) < 1e-6
	local counted = shown * share
	local number = if isWhole then tostring(math.round(counted)) else string.format("%.1f", counted)
	local words = WORDS[stat]
	return if words then words(number) else number
end

-- A stat row: his violet-edged row, unrolling from its left end, its caption fading in and its numbers counting up:
-- the value now, and his green arrow to the next level's.
local function statRow(
	state: Types.TLobbyState,
	abilities: { TData.TAbility },
	shownLevel: () -> number,
	index: number
): Frame
	local delay = Timing.STATS[index]
	local unrolled = dealt(state, delay, Timing.IN, state.UpgradedAt)
	local counted = dealt(state, delay + Timing.COUNT_DELAY, Timing.COUNT, state.UpgradedAt)
	local stat = derive(function(): TStatLine?
		local ability = abilities[state.ShownAbility()]
		return if ability then statsOf(ability, shownLevel())[index] else nil
	end)
	local hasNext = derive(function(): boolean
		local current = stat()
		return current ~= nil and current.Next ~= nil
	end)
	local countFade = derive(function(): number
		return 1 - Motion.Out(math.min(counted() / Timing.COUNT_FADE, 1))
	end)
	-- Derived, so a count writes its text only when the number it shows moves on.
	local function countedText(field: "Current" | "Next"): () -> string
		return derive(function(): string
			local current = stat()
			local value = if current then current[field] else nil
			if not current or not value then return "" end
			local t = counted()
			return statText(current.Stat, value, 1 - (1 - t) * (1 - t))
		end)
	end

	return create("Frame")({
		Name = `Stat{index}`,
		Position = UDim2.fromOffset(Layout.STAT_X, Layout.STAT_TOPS[index]),
		Size = function()
			return UDim2.fromOffset(math.round(Layout.STAT_SIZE.X * Motion.Decelerate(unrolled())), Layout.STAT_SIZE.Y)
		end,
		-- A level that raises one stat has one row.
		Visible = function()
			return stat() ~= nil
		end,
		BackgroundColor3 = Colors.STAT_EDGE,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 4,
		create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
		create("Frame")({
			Name = "Face",
			Position = UDim2.fromOffset(1, 1),
			Size = UDim2.new(1, -2, 1, -2),
			BackgroundColor3 = Colors.STAT_FACE,
			BorderSizePixel = 0,
			create("UICorner")({ CornerRadius = UDim.new(0, 1) }),
		}),
		label({
			Name = "Caption",
			Position = UDim2.fromOffset(Layout.STAT_LABEL.X, Layout.STAT_LABEL.Y),
			Size = UDim2.fromOffset(200, Layout.STAT_LABEL_TEXT),
			FontFace = Font.DisplayBold,
			TextSize = Layout.STAT_LABEL_TEXT,
			TextColor3 = Palette.Lavender,
			TextTransparency = function()
				return 1 - Motion.Out(unrolled())
			end,
			Text = function()
				local current = stat()
				return if current then current.Label else ""
			end,
			ZIndex = 2,
		}),
		create("Frame")({
			Name = "Values",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromOffset(Layout.STAT_VALUE_RIGHT, Layout.STAT_VALUE_Y),
			Size = UDim2.fromOffset(240, Layout.STAT_VALUE_TEXT),
			BackgroundTransparency = 1,
			ZIndex = 2,
			create("UIListLayout")({
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, Layout.STAT_ARROW_GAP),
			}),
			label({
				Name = "Value",
				LayoutOrder = 1,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, Layout.STAT_VALUE_TEXT),
				TextSize = Layout.STAT_VALUE_TEXT,
				TextTransparency = countFade,
				Text = countedText("Current"),
			}),
			label({
				Name = "Arrow",
				LayoutOrder = 2,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, Layout.STAT_ARROW_TEXT),
				TextSize = Layout.STAT_ARROW_TEXT,
				TextColor3 = Palette.Green,
				TextTransparency = countFade,
				Text = "→",
				Visible = hasNext,
			}),
			label({
				Name = "Next",
				LayoutOrder = 3,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, Layout.STAT_VALUE_TEXT),
				TextSize = Layout.STAT_VALUE_TEXT,
				TextColor3 = Palette.Green,
				TextTransparency = countFade,
				Text = countedText("Next"),
				Visible = hasNext,
			}),
		}),
	})
end

-- Each ability's description wrapped to its box, in px high, by index: empty until measured. Not the label's TextBounds:
-- that comes back under the screen's UIScale.
local function descriptionHeights(abilities: { TData.TAbility }): () -> { number }
	local heights = vide.source({})
	task.spawn(function()
		local params = Instance.new("GetTextBoundsParams")
		params.Font = Font.DisplayBold
		params.Size = Layout.DESCRIPTION_TEXT
		params.Width = Layout.DESCRIPTION_WIDTH - 2 * Layout.DESCRIPTION_PAD

		local measured = table.create(#abilities)
		for index, ability in abilities do
			params.Text = ability.Description or ""
			local isMeasured, bounds = pcall(TextService.GetTextBoundsAsync, TextService, params)
			if isMeasured then measured[index] = math.ceil(bounds.Y) end
		end

		heights(measured)
	end)
	return heights
end

-- The picked ability's details: its name and ?, its stars, its two stat rows, and the description the ? opens.
-- The stars are built into `marks`, where the Gems a level is paid with find the one they land on.
local function details(
	state: Types.TLobbyState,
	abilities: { TData.TAbility },
	shownLevel: () -> number,
	marks: { GuiObject }
): { Instance }
	local named = dealt(state, Timing.NAME, Timing.IN)
	local help = Hand.React("Operate")
	local isHelpOpen = vide.source(false)
	local helpShown = Hand.Spring(function()
		return if isHelpOpen() then 1 else 0
	end, Timing.HELP)
	-- Derived so Visible is written when it flips, not every frame of the spring.
	local isHelpVisible = derive(function(): boolean
		return helpShown() > 0.01
	end)
	local textHeights = descriptionHeights(abilities)
	local shownAbility = derive(function()
		return abilities[state.ShownAbility()]
	end)

	for index = 1, MAX_LEVEL do
		local popped = dealt(state, Timing.STARS + Timing.STAR_STEP * (index - 1), Timing.STAR)
		local isLit = derive(function(): boolean
			return index <= shownLevel()
		end)
		-- The star a level just bought, as its Gems land: struck in on a spring, throwing one gold ring.
		local isStruck = derive(function(): boolean
			local now, at = state.Now(), state.UpgradedAt()
			return index == shownLevel() and now >= at and now < at + Timing.STAR_RING
		end)
		local pop, strike = Hand.Kick(Timing.STAR_POP_PERIOD, Timing.STAR_POP_DAMPING)
		vide.effect(function()
			if not isStruck() then return end
			vide.untrack(function()
				strike(Timing.STAR_POP)
			end)
		end)
		local ring = derive(function(): number
			if not isStruck() then return 1 end
			return Progress(state.Now(), state.UpgradedAt(), Timing.STAR_RING)
		end)

		marks[index] = create("Frame")({
			Name = `Star{index}`,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(Layout.STARS.X + Layout.STAR_STEP * (index - 1), Layout.STARS.Y),
			Size = Components.PictureBox(Layout.STAR_GLYPH),
			BackgroundTransparency = 1,
			ZIndex = 4,
			create("UIScale")({
				Scale = function()
					return Motion.Decelerate(popped()) + pop()
				end,
			}),
			create("Frame")({
				Name = "Ring",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = function()
					local grow = math.round(Timing.STAR_RING_REACH * Motion.Out(ring()))
					return UDim2.new(1, 2 * grow, 1, 2 * grow)
				end,
				BackgroundTransparency = 1,
				Visible = function()
					return ring() < 1
				end,
				create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
				create("UIStroke")({ Color = Palette.Gold, Thickness = 2, Transparency = ring }),
			}),
			star(isLit, { Position = UDim2.fromScale(0.5, 0.5) }),
		})
	end

	return {
		label({
			Name = "AbilityName",
			Position = function()
				return UDim2.fromOffset(
					Layout.ABILITY_NAME.X + math.round(Timing.NAME_FROM * (1 - Motion.Decelerate(named()))),
					Layout.ABILITY_NAME.Y
				)
			end,
			Size = UDim2.fromOffset(Layout.HELP.X - Layout.ABILITY_NAME.X - 16, Layout.ABILITY_NAME_TEXT),
			TextSize = Layout.ABILITY_NAME_TEXT,
			TextScaled = true,
			TextTransparency = function()
				return 1 - Motion.Out(named())
			end,
			Text = function()
				local ability = shownAbility()
				return if ability then string.upper(ability.Name) else ""
			end,
			create("UITextSizeConstraint")({ MaxTextSize = Layout.ABILITY_NAME_TEXT }),
		}),
		Components.Button({
			Name = "Help",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(Layout.HELP.X + Layout.HELP_SIZE / 2, Layout.HELP.Y + Layout.HELP_SIZE / 2),
			Size = UDim2.fromOffset(Layout.HELP_SIZE, Layout.HELP_SIZE),
			BackgroundTransparency = 1,
			ZIndex = 5,
			Activated = function()
				help.Commit()
				isHelpOpen(not isHelpOpen())
			end,
			help.Events,
			Components.Plaque({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(1, 1),
				create("UIScale")({ Scale = help.Scale }),
				create("TextLabel")({
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					FontFace = Font.Display,
					TextSize = Layout.HELP_TEXT,
					TextColor3 = Palette.Green,
					Text = "?",
					ZIndex = 2,
				}),
			}),
		}),
		create("Frame")({
			Name = "Stars",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 4,
			marks,
		}),
		statRow(state, abilities, shownLevel, 1),
		statRow(state, abilities, shownLevel, 2),
		Components.Panel({ Glow = Palette.Green, GlowTransparency = Gesture.ABILITY_GLOW }, {
			Name = "Description",
			-- It grows down from the middle of its top edge and shrinks back there: the panel has no transparency to fade.
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(Layout.DESCRIPTION.X + Layout.DESCRIPTION_WIDTH / 2, Layout.DESCRIPTION.Y),
			Size = function()
				local textHeight = textHeights()[state.ShownAbility()] or Layout.DESCRIPTION_TEXT
				return UDim2.fromOffset(Layout.DESCRIPTION_WIDTH, textHeight + 2 * Layout.DESCRIPTION_PAD)
			end,
			Visible = isHelpVisible,
			ZIndex = 6,
			create("UIScale")({ Scale = helpShown }),
			label({
				Position = UDim2.fromOffset(Layout.DESCRIPTION_PAD, Layout.DESCRIPTION_PAD),
				Size = UDim2.new(1, -2 * Layout.DESCRIPTION_PAD, 1, -2 * Layout.DESCRIPTION_PAD),
				FontFace = Font.DisplayBold,
				TextSize = Layout.DESCRIPTION_TEXT,
				TextWrapped = true,
				TextTransparency = function()
					return 1 - helpShown()
				end,
				Text = function()
					local ability = shownAbility()
					return if ability then ability.Description or "" else ""
				end,
			}),
		}),
	}
end

type TInfoSlab = {
	-- Its place in the foot's order of arrival, and its top left corner.
	Index: number,
	At: Vector2,
	-- Components.Slab's Kind, or a source of one.
	Kind: any,
	Content: { Instance },
	-- Whether the hand lights it; without OnPress it answers the hand and does nothing.
	IsLive: () -> boolean,
	OnPress: (() -> ())?,
}

-- A slab of the info panel's foot.
local function infoSlab(state: Types.TLobbyState, spec: TInfoSlab): TextButton
	local at = spec.At
	local delay = Timing.DETAILS + Timing.SLABS[spec.Index]
	local hand = Hand.React("Operate", spec.IsLive)
	local shown = arrival(state, delay, Timing.IN)
	local landed = landing(state, delay, true)
	local size = Layout.SLAB_SIZE
	local onPress = spec.OnPress

	return Components.Button({
		Name = `Slab{spec.Index}`,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			return UDim2.fromOffset(
				at.X + size.X / 2,
				at.Y + size.Y / 2 + math.round(Timing.DETAIL_FROM * (1 - shown()))
			)
		end,
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Activated = function()
			hand.Commit()
			if onPress then onPress() end
		end,
		hand.Events,
		create("UIScale")({
			Scale = function()
				return shown() * hand.Scale()
			end,
		}),
		Components.Slab({ Kind = spec.Kind, Marks = true, Brackets = true }, {
			Name = "Slab",
			Size = UDim2.fromScale(1, 1),
			Hand.WashLayer(hand, 3, 3),
			Components.Sheen(landed, 3),
			spec.Content,
		}),
	})
end

-- The next level's price over UPGRADE, his gold: it flashes pink and shakes its head when a press is refused. Nothing
-- at the top level.
local function costLine(state: Types.TLobbyState, cost: () -> number?): Frame
	local shown = dealt(state, Timing.COST, Timing.IN)
	local refused = derive(function(): number
		return Motion.Fade(state.Now(), state.UpgradeRefusedAt(), Timing.REFUSED)
	end)
	local color = derive(function(): Color3
		return Palette.Gold:Lerp(Palette.Pink, refused())
	end)
	local fade = derive(function(): number
		return 1 - Motion.Out(shown())
	end)
	-- In whole px, so it is written only while it shakes.
	local jolt = derive(function(): number
		local at = state.UpgradeRefusedAt()
		return math.round(Timing.JOLT * Motion.Shake(Progress(state.Now(), at, Timing.JOLT_SECONDS), at))
	end)

	return create("Frame")({
		Name = "Cost",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = function()
			return UDim2.fromOffset(Layout.PANEL_SIZE.X / 2 + jolt(), Layout.COST_Y)
		end,
		Size = UDim2.fromOffset(Layout.SLAB_SIZE.X, Layout.COST_TEXT),
		BackgroundTransparency = 1,
		Visible = function()
			return cost() ~= nil
		end,
		ZIndex = 4,
		create("UIListLayout")({
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, Layout.COST_GAP),
		}),
		Components.Picture(EIcons.Gem, {
			Name = "Gem",
			LayoutOrder = 1,
			Size = Components.PictureBox(Layout.COST_GLYPH),
			ImageTransparency = fade,
			ZIndex = 4,
		}),
		label({
			Name = "Price",
			LayoutOrder = 2,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, Layout.COST_TEXT),
			TextSize = Layout.COST_TEXT,
			TextColor3 = color,
			TextTransparency = fade,
			Text = function()
				local price = cost()
				return if price then Components.Commas(price) else ""
			end,
		}),
	})
end

-- UPGRADE's word, laid out again when it changes: a word's letters are laid out once. vide unparents the old row
-- itself, and it holds no connections, so it is not destroyed here (a row destroyed in a cleanup is then unparented by
-- vide, which errors on its locked Parent).
local function upgradeWord(word: () -> string): Frame
	return create("Frame")({
		Name = "Word",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 4,
		derive(function()
			local text = word()
			return vide.untrack(function()
				return Components.Tracked(text, Layout.UPGRADE_TEXT, Layout.UPGRADE_TRACKING, Font.Display, {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
				})
			end)
		end),
	})
end

-- The middle of `guiObject` on the screen, nil when it is not on it.
local function centreOf(guiObject: GuiObject?): Vector2?
	if not guiObject or not guiObject.Parent then return nil end
	return guiObject.AbsolutePosition + guiObject.AbsoluteSize / 2
end

local function infoPanel(state: Types.TLobbyState, actions: Types.TLobbyActions, class: TData.TClass): Frame
	local shown = presence(state, Timing.INFO)
	local landed = landing(state, Timing.INFO)
	local abilities = table.clone(class.Abilities)
	table.insert(abilities, class.Ultimate)

	local cards = table.create(#abilities)
	for index, ability in abilities do
		cards[index] = abilityCard(state, actions, index, ability, ability == class.Ultimate)
	end

	local shownLevel = derive(function(): number
		local levels = state.ClassLevels()[class.Id]
		return if levels then levels[state.ShownAbility()] or 1 else 1
	end)
	local cost = derive(function(): number?
		return AbilitiesCore.UpgradeCost(shownLevel())
	end)
	local canPay = derive(function(): boolean
		local price = cost()
		return price ~= nil and state.Gems() >= price and not state.IsUpgrading()
	end)
	-- His gold while it can be bought; past what the Gems reach, or at the top, the slab no press can use.
	local upgradeKind = derive(function(): string
		return if canPay() then "Gold" else "Off"
	end)
	local word = derive(function(): string
		local level = shownLevel()
		return if level >= MAX_LEVEL then "MAX LEVEL" else `UPGRADE TO LV {level + 1}`
	end)
	-- A level's Gems fly from the counter into the star it lights: the one after the level shown, which is still the
	-- old one while they fly.
	local marks: { GuiObject } = {}
	local flight = Flight.Build(state, {
		From = function(): Vector2?
			return centreOf(state.GemsGlyph())
		end,
		To = function(): Vector2?
			return centreOf(marks[math.min(shownLevel() + 1, MAX_LEVEL)])
		end,
	})

	return panel(
		"ClassInfo",
		Layout.INFO_TEXTURE,
		Components.Picture(EIcons.Star, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(Layout.HEADER_GLYPH.X, Layout.HEADER_GLYPH.Y),
			Size = Components.PictureBox(Layout.HEADER_STAR),
			ZIndex = 4,
		}),
		"ABILITIES",
		nil,
		{
			AnchorPoint = Vector2.new(1, 0),
			Position = function()
				return UDim2.new(
					1,
					-Layout.INFO_RIGHT + math.round(Timing.FROM_RIGHT * (1 - shown())),
					0,
					Layout.LIST.Y - lift()
				)
			end,
			Components.Sheen(landed, 3),
			cards,
			details(state, abilities, shownLevel, marks),
			flight,
			-- His rect, so the price and the slabs keep their place as the panel grows over them.
			create("Frame")({
				Name = "Bottom",
				Position = function()
					return UDim2.fromOffset(0, lift())
				end,
				Size = UDim2.fromOffset(Layout.PANEL_SIZE.X, Layout.PANEL_SIZE.Y),
				BackgroundTransparency = 1,
				ZIndex = 4,
				costLine(state, cost),
				infoSlab(state, {
					Index = 1,
					At = Layout.UPGRADE,
					Kind = upgradeKind,
					Content = { upgradeWord(word) },
					IsLive = canPay,
					OnPress = function()
						actions.UpgradeAbility(class.Id, state.ShownAbility())
					end,
				}),
				infoSlab(state, {
					Index = 2,
					At = Layout.EQUIP,
					Kind = "Go",
					Content = {
						Components.Picture(EIcons.Check, {
							AnchorPoint = Vector2.new(0.5, 0.5),
							Position = UDim2.fromOffset(Layout.CHECK.X, Layout.CHECK.Y),
							Size = Components.PictureBox(Layout.CHECK_GLYPH),
							ZIndex = 4,
						}),
						Components.Tracked("EQUIPPED", Layout.EQUIP_TEXT, Layout.EQUIP_TRACKING, Font.Display, {
							AnchorPoint = Vector2.new(0, 0.5),
							Position = UDim2.new(0, Layout.EQUIP_TEXT_LEFT, 0.5, 0),
						}),
					},
					-- The class is equipped already (there is one).
					IsLive = function()
						return false
					end,
				}),
			}),
		}
	)
end

-- ============================== EXIT and the dim ==============================

local function exitButton(state: Types.TLobbyState, actions: Types.TLobbyActions): TextButton
	local shown = presence(state, Timing.EXIT)
	return Components.Exit(function(): number
		return 1 - shown()
	end, actions.CloseClasses, { ZIndex = 5 })
end

-- The world behind the screen, darkened as his lobby screens darken it. The dim takes every click, so nothing behind
-- the screen is pressed through it.
local function backdrop(state: Types.TLobbyState): Frame
	local shown = derive(function(): number
		local now, at = state.Now(), state.ClassesToggledAt()
		if state.IsClassesOpen() then return Motion.Out(Progress(now, at, Timing.DIM)) end
		return 1 - Progress(now, at, Timing.OUT)
	end)

	return create("Frame")({
		Name = "Dim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(),
		BackgroundTransparency = function()
			return 1 - (1 - Colors.DIM_TRANSPARENCY) * shown()
		end,
		BorderSizePixel = 0,
		Active = true,
		ZIndex = 0,
	})
end

-- The EQUIPMENT page as the screen holds it: its pieces, and how long it takes to fade in over this page.
export type TOtherPage = {
	Pieces: { Instance },
	FadeSeconds: number,
}

-- The screen, built once; it is drawn only while it is up or leaving. `equipment` is the EQUIPMENT tab's page, nil
-- where there is none (a story of this page alone).
function Classes.Build(state: Types.TLobbyState, actions: Types.TLobbyActions, equipment: TOtherPage?): ScreenGui
	local coverSeconds = if equipment then equipment.FadeSeconds else 0
	local class = DataCore.Classes.ById[EQUIPPED_CLASS] or DataCore.Classes.All[1]
	local isDrawn = derive(function(): boolean
		if state.IsClassesOpen() then return true end
		return Progress(state.Now(), state.ClassesToggledAt(), Timing.OUT) < 1
	end)
	local stageFrame, celebrate = Stage.Build(state, class, {
		Rings = pagePresence(state, Timing.STAGE),
		Name = pagePresence(state, Timing.STAGE_NAME),
		Tag = pagePresence(state, Timing.STAGE_TAG),
		Body = pagePresence(state, Timing.AVATAR),
	}, function(): boolean
		return isPageShown(state)
	end)

	return create("ScreenGui")({
		Name = "Classes",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		-- Over the lobby's screen, under the settings.
		DisplayOrder = 5,
		Enabled = isDrawn,
		backdrop(state),
		-- His 1920 x 1080 fitted to the window and centred, as the weapons page is, so the two pages' panels and EXIT
		-- stand in one place.
		create("Frame")({
			Name = "Root",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(1920, 1080),
			BackgroundTransparency = 1,
			ZIndex = 2,
			create("UIScale")({ Scale = state.PageScale }),
			create("Frame")({
				Name = "ClassesPage",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Visible = function()
					return isPageDrawn(state, coverSeconds)
				end,
				ZIndex = 2,
				stageFrame,
				classList(state, celebrate),
				infoPanel(state, actions, class),
			}),
			create("Frame")({
				Name = "EquipmentPage",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ZIndex = 3,
				if equipment then equipment.Pieces else nil,
			}),
			tabs(state, actions),
			exitButton(state, actions),
		}),
	})
end

return Classes
