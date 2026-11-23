--!nonstrict
-- The lobby's HUD (UIMatt.md, Lobby HUD), on the designer's drawn rects at 1080: the level plate top left, the rail of
-- five cards on the left and WEAPONS / MENU / CLASSES along the bottom, and the Gems counter (BuildGems, a gui of its
-- own over the lobby's screens) top centre, docked in his coin slot on the classes and weapons pages. The screens not
-- built yet (and the counter's +) are drawn and answer the hand but do nothing; INVITE FRIENDS opens Roblox's invite,
-- and DAILY REWARDS its screen (shaking now and then while today's reward waits).
--
-- The pieces slide in from their nearest edge when the lobby opens, the action row first, each catching the light as
-- it lands; then the XP bar and the Gems roll up to the profile. Every gesture timed from a stamp reads state.Now,
-- which init ticks only while one runs; the hand's reactions are vide springs.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local Types = require(script.Parent.Types)

local create = vide.create
local derive = vide.derive
local spring = vide.spring
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress

-- His drawn rects (outer, edge included) in px at 1920 x 1080, each from the edge it hangs on. The HUD stands under
-- Roblox's top bar, so the top row is lifted 35 from his (the plate was at 47): it keeps the gap the bar's own buttons
-- keep from the screen's top.
local Layout = table.freeze({
	-- The level plate, from the top left; inside it the rank glyph's middle, LV, the rule, XP, the count's right edge
	-- and the bar.
	LEVEL = Vector2.new(38, 12),
	LEVEL_SIZE = Vector2.new(474, 82),
	LEVEL_BRACKETS = 5,
	RANK = Vector2.new(36, 41),
	RANK_GLYPH = 30,
	LV = Vector2.new(67, 19),
	LV_TEXT = 44,
	RULE = Vector2.new(200, 15),
	RULE_HEIGHT = 53,
	XP = Vector2.new(233, 16),
	XP_TEXT = 23,
	COUNT_RIGHT = 459,
	BAR = Vector2.new(233, 48),
	BAR_SIZE = Vector2.new(226, 12),
	-- The Gems counter, in its own gui from the SCREEN's top (it stands up in Roblox's top bar strip): its middle,
	-- centred across the top, and DOCKED at the right of his currency on the classes and weapons pages, our + on his +
	-- (its left 853 right of the middle and its top 52 down, measured off his renders) and the pill beside it; his coin
	-- pill, its glyph's middle and its number's left; his + square, PLUS_GAP right of the pill, and its cross.
	COUNTER_MIDDLE = 44,
	DOCKED_PLUS = Vector2.new(853, 52),
	PILL_SIZE = Vector2.new(225, 62),
	PILL_BRACKETS = 3,
	GEM = Vector2.new(55, 31),
	GEM_GLYPH = 36,
	GEMS_TEXT_LEFT = 91,
	PILL_TEXT_TOP = 16,
	PILL_TEXT = 28,
	PLUS_GAP = 16,
	PLUS_SIZE = 67,
	PLUS_ARM = Vector2.new(24, 8),
	-- The rail: each card's left and its drawn top from the screen's middle; inside a card the key and the label's top.
	-- His four stood 175 apart at 119 px; QUESTS and INDEX make six, so each is drawn at CARD_SCALE of his (the card
	-- is laid out at his size inside) and they stand 142 apart about the same middle, a label clearing the next card.
	CARD_LEFT = 48,
	CARD = 119,
	CARD_SCALE = 0.875,
	CARD_TOPS = { -421, -279, -137, 5, 147, 289 },
	CARD_BRACKETS = 7,
	CARD_BRACKET_LENGTH = 22,
	KEY = Vector2.new(78, 7),
	KEY_SIZE = Vector2.new(33, 28),
	-- KeyBadge's letter is 0.63 of this: his is 20.
	KEY_BADGE = 32,
	CARD_LABEL_TOP = 130,
	CARD_LABEL_TEXT = 21,
	-- The action row: each slab's left from the screen's middle, their bottom from the screen's bottom.
	SLAB_LEFTS = { -593, -195, 211 },
	SLAB_BOTTOM = 70,
	SLAB_SIZE = Vector2.new(366, 101),
	SLAB_BRACKETS = 5,
	SLAB_TEXT = 34,
	MENU_TEXT = 42,
	-- MENU's bars, by their top left.
	HAMBURGER = Vector2.new(97, 41),
	HAMBURGER_BAR = Vector2.new(28, 4),
	HAMBURGER_STEP = 8,
})

-- His colours that are not in the Palette: the slabs' flat faces, the rule, the bar's track, +'s edge and face, and
-- his pill's glow at rest.
local SLAB_GOLD = Color3.fromRGB(217, 160, 56)
local SLAB_GREEN = Color3.fromRGB(15, 157, 99)
local RULE = Color3.fromRGB(140, 111, 211)
local RULE_TRANSPARENCY = 0.55
local TRACK_TRANSPARENCY = 0.88
local PLUS_EDGE = Color3.fromRGB(75, 58, 117)
local PLUS_FACE = Color3.fromRGB(21, 15, 40)
local PILL_GLOW = 0.62
-- The chips a gain throws: the game's gem blue (the colour of the Gems that fly into the pill), a lifted shade of it
-- and white.
local GEM_BLUE = Theme.Color.Gem
local GEM_LIGHT = Color3.fromRGB(190, 238, 255)
-- The INDEX card, a sixth colour after his five: his red slab's face.
local INDEX_RED = Color3.fromRGB(230, 60, 72)
-- How faint the cards' and slabs' glow is at rest, as his.
local GLOW_TRANSPARENCY = 0.7
local SLAB_GLOW_TRANSPARENCY = 0.55
-- His cards' edge is their accent a little darker; the glow is the accent itself.
local CARD_EDGE = 0.85
local CARD_TINT = 0.5

-- A rail card: its word, its glyph, the glyph's longest side and middle in the card, its key, its accent (and its glow
-- where his is not the accent), the action's name in TLobbyActions (nil: nothing to open yet), and what it calls (in
-- light) for: Daily while today's daily reward waits, Index while a type found in a run is still to be shown.
type TCardSpec = {
	Name: string,
	Icon: string,
	Glyph: number,
	At: Vector2,
	Key: Enum.KeyCode,
	Accent: Color3,
	Glow: Color3?,
	Action: string?,
	Calls: ("Daily" | "Index")?,
}
-- A slab: its word, its face, its glyph (nil: MENU's drawn bars) with the glyph's longest side and middle, where the
-- word starts, its size and its letters' tracking (his are spaced out), IsLight for his lighter weight, and the
-- action's name in TLobbyActions (nil: nothing to open yet).
type TSlabSpec = {
	Name: string,
	Face: Color3,
	Icon: string?,
	Glyph: number?,
	At: Vector2?,
	TextLeft: number,
	TextSize: number,
	Tracking: number,
	IsLight: boolean?,
	Action: string?,
}

-- The rail, top to bottom.
local CARDS: { TCardSpec } = table.freeze({
	{ Name = "SHOP", Icon = "Shop", Glyph = 46, At = Vector2.new(60, 57), Key = Enum.KeyCode.B, Accent = Palette.Gold },
	{
		Name = "DAILY REWARDS",
		Icon = "Gift",
		Glyph = 40,
		At = Vector2.new(60, 59),
		Key = Enum.KeyCode.R,
		Accent = Palette.Pink,
		Action = "OpenDailyRewards",
		Calls = "Daily",
	},
	{
		Name = "DAILY SPINS",
		Icon = "Spin",
		Glyph = 43,
		At = Vector2.new(60, 57),
		Key = Enum.KeyCode.T,
		Accent = Palette.Violet,
		Action = "OpenSpins",
	},
	{
		Name = "QUESTS",
		Icon = "Scroll",
		Glyph = 46,
		At = Vector2.new(60, 59),
		Key = Enum.KeyCode.Q,
		Accent = Palette.Steel,
		Action = "OpenQuests",
	},
	{
		Name = "INDEX",
		Icon = "Skull",
		Glyph = 44,
		At = Vector2.new(60, 58),
		-- Not I: Roblox's camera zooms in on it.
		Key = Enum.KeyCode.X,
		Accent = INDEX_RED,
		Action = "OpenIndex",
		Calls = "Index",
	},
	{
		Name = "INVITE FRIENDS",
		Icon = "Friends",
		Glyph = 46,
		At = Vector2.new(60, 57),
		Key = Enum.KeyCode.F,
		Accent = Palette.Green,
		-- His invite card glows pink, not green.
		Glow = Palette.Pink,
		Action = "InviteFriends",
	},
})
-- The row, left to right.
local SLABS: { TSlabSpec } = table.freeze({
	{
		Name = "WEAPONS",
		Face = SLAB_GOLD,
		Icon = "Rifle",
		Glyph = 45,
		At = Vector2.new(84, 50),
		TextLeft = 119,
		TextSize = Layout.SLAB_TEXT,
		Tracking = 3,
		Action = "OpenWeapons",
	},
	-- His MENU is the lighter weight.
	{ Name = "MENU", Face = Palette.Pink, TextLeft = 145, TextSize = Layout.MENU_TEXT, Tracking = 5, IsLight = true },
	{
		Name = "CLASSES",
		Face = SLAB_GREEN,
		Icon = "Helmet",
		Glyph = 41,
		At = Vector2.new(83, 48),
		TextLeft = 118,
		TextSize = Layout.SLAB_TEXT,
		Tracking = 4,
		Action = "OpenClasses",
	},
})

-- Seconds from the lobby opening: each piece's start, how long it slides, and the light crossing it as it lands. The
-- row leads, since PLAY lives behind MENU; the plates and the rail follow.
local Arrive = table.freeze({
	SLIDE = 0.5,
	SHEEN = 0.6,
	-- The sheen starts this far before the slide lands, so it is crossing as the piece settles.
	SHEEN_LEAD = 0.12,
	SLABS = { 0.08, 0, 0.08 },
	LEVEL = 0.12,
	-- The counter, and its gem tumbling in after it.
	COUNTER = 0.2,
	GLYPH = 0.3,
	CARDS = { 0.18, 0.25, 0.32, 0.39, 0.46, 0.53 },
	-- How far each piece starts past its rest, in px: off the screen's edge, glow included.
	FROM_BOTTOM = 220,
	FROM_TOP = 190,
	FROM_LEFT = 230,
	-- A screen opening over the HUD sends the pieces it covers off the way they came, accelerating, LEAVE_STAGGER of
	-- their entrance delays apart. Once it starts to shut they come back decelerating, after its own pieces have cleared
	-- the edges, RETURN_STAGGER apart: the player is waiting on them, so the return is quicker than the entrance.
	LEAVE = 0.24,
	LEAVE_STAGGER = 0.3,
	RETURN_DELAY = 0.08,
	RETURN = 0.3,
	RETURN_STAGGER = 0.4,
})
-- The rolls (XP and Gems): how long they run, and how much of their pace is kept to the landing (0.35t + 0.65t²
-- arrives at 1.65 of its average speed, so the numbers are pulled into the landing rather than crawling onto it).
local Roll = table.freeze({
	SECONDS = 1.1,
	LINEAR = 0.35,
})
-- The XP bar: the light riding the fill's end while it rolls, and a level up's flash and ring.
local XpBar = table.freeze({
	HEAD = 18,
	FLASH_PERIOD = 0.5,
	RING_LINE = 3,
	RING_REACH = 22,
	RING_PERIOD = 0.5,
})
-- What a card, a slab and their glyph do under the hand: the brackets open this many px, the glyph grows this share
-- with the rise; a press that goes through pops the glyph and throws it up this far, the spin card's wheel turns once,
-- WEAPONS's rifle kicks back.
local Gesture = table.freeze({
	BRACKETS_OPEN = 4,
	GLYPH_RISE = 0.12,
	GLOW_LIT = 0.35,
	HOP = 7,
	HOP_PERIOD = 0.32,
	HOP_DAMPING = 0.45,
	SPIN_PERIOD = 0.9,
	SPIN_DAMPING = 0.85,
	KICK = Vector2.new(-9, 2),
	KICK_TURN = 14,
	KICK_PERIOD = 0.3,
	KICK_DAMPING = 0.5,
	-- The daily rewards card's call while today's reward waits, in light only (nothing on a control moves at rest): its
	-- glow is lit this much and the light crosses it in CALL_SHEEN seconds each time init calls.
	CALL_GLOW = 0.3,
	CALL_SHEEN = 0.6,
})
-- The Gems counter's life. The pill swells PILL_SWELL while Gems land in it and the gem GLYPH_SWELL, and its glow
-- climbs; a roll that lands punches it (the gem harder, it is what was paid), and a gain also flashes the pill white,
-- rattles the gem, sends one ring off the pill and throws CHIPS chips out of the gem. Gems spent squeeze the gem as the
-- count starts down. Every few seconds the light catches the gem (a twinkle at its top right).
local Counter = table.freeze({
	FED_PERIOD = 0.12,
	-- The glide between the top centre and his coin slot as the classes or weapons page opens or shuts: critically
	-- damped, so it settles onto the slot with no overshoot.
	DOCK_PERIOD = 0.5,
	PILL_SWELL = 0.06,
	GLYPH_SWELL = 0.2,
	-- The gem falls in from this far above, turned this far back, at this share of its size.
	GLYPH_DROP = 30,
	GLYPH_SPIN = -140,
	GLYPH_FROM = 0.4,
	-- How much brighter the pill's glow is while Gems pour in.
	GLOW_LIT = 0.4,
	FLASH_PERIOD = 0.35,
	FLASH = 0.55,
	RATTLE = 16,
	RATTLE_PERIOD = 0.42,
	RATTLE_DAMPING = 0.3,
	SQUEEZE = 0.22,
	SQUEEZE_PERIOD = 0.28,
	SQUEEZE_DAMPING = 0.5,
	-- The burst's clock: a critically damped spring thrown from 0 toward BURST_END at BURST_SPEED, read until it passes
	-- 1 (0.69 s, half its travel in the first 0.2).
	BURST_PERIOD = 2,
	BURST_END = 1.2,
	BURST_SPEED = 3,
	-- The ring: the pill's own shape growing RING_REACH px, RING_LINE px, gone by RING_LIFE of the burst.
	RING_REACH = 22,
	RING_LIFE = 0.6,
	RING_LINE = 3,
	-- Chips: CHIPS of them across a fan in degrees clockwise from the right (from down and a little right, round the
	-- left, to up), born this far from the gem's middle (past its edge), thrown REACH_MIN to REACH_MAX further, falling
	-- FALL px by the end; CHIP_MIN to CHIP_MAX px, spun up to CHIP_SPIN degrees over the life.
	CHIPS = 9,
	FAN_FROM = 60,
	FAN_TO = 265,
	CHIP_BORN = 24,
	REACH_MIN = 30,
	REACH_MAX = 62,
	FALL = 14,
	CHIP_MIN = 8,
	CHIP_MAX = 13,
	CHIP_SPIN = 240,
	-- The twinkle: where on the gem's box (its top right), its arms' length and width, its spring's period, and the
	-- amount under which it is put out.
	TWINKLE_AT = Vector2.new(0.78, 0.2),
	TWINKLE_ARM = 34,
	TWINKLE_WIDTH = 3,
	TWINKLE_PERIOD = 0.55,
	TWINKLE_FLOOR = 0.12,
})

local Hud = {}

-- Where a roll from `from` to `to` stamped at `at` stands at `now`.
function Hud.Rolled(from: number, to: number, at: number, now: number): number
	local t = Progress(now, at, Roll.SECONDS)
	return from + (to - from) * (Roll.LINEAR * t + (1 - Roll.LINEAR) * t * t)
end

-- How long a roll and the entrance take, so init keeps the clock ticking for them.
Hud.ROLL_SECONDS = Roll.SECONDS
Hud.ARRIVE_SECONDS = Arrive.CARDS[#Arrive.CARDS] + Arrive.SLIDE + Arrive.SHEEN

-- A piece's slide in from `from` (px past its rest) starting `delay` after the lobby opens: an offset to add to its
-- Position, nothing once it has landed. `isCovered` is a piece a screen over the lobby sends away while it is up;
-- `isBareOnly` one only a screen that takes the whole view sends away. Derived, so it is written only while it moves.
local function arrival(
	state: Types.TLobbyState,
	delay: number,
	from: Vector2,
	isCovered: boolean?,
	isBareOnly: boolean?
): () -> UDim2
	local leaveDelay = delay * Arrive.LEAVE_STAGGER
	local returnDelay = Arrive.RETURN_DELAY + delay * Arrive.RETURN_STAGGER

	return derive(function(): UDim2
		local now = state.Now()
		local away = 1 - Motion.Decelerate(Progress(now, state.EnteredAt(), Arrive.SLIDE, delay))
		if isCovered or isBareOnly then
			local at = if isBareOnly then state.BareAt() else state.CoveredAt()
			local isAside = if isBareOnly then state.IsBare() else state.IsCovered()
			local aside = if isAside
				then Motion.Accelerate(Progress(now, at, Arrive.LEAVE, leaveDelay))
				else 1 - Motion.Decelerate(Progress(now, at, Arrive.RETURN, returnDelay))
			away = math.max(away, aside)
		end

		return UDim2.fromOffset(math.round(from.X * away), math.round(from.Y * away))
	end)
end

-- The light crossing a piece as it lands: 0 to 1, and 1 at rest.
local function landing(state: Types.TLobbyState, delay: number): () -> number
	return derive(function(): number
		return Progress(state.Now(), state.EnteredAt(), Arrive.SHEEN, delay + Arrive.SLIDE - Arrive.SHEEN_LEAD)
	end)
end

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

-- Presses the button by its key: down while the key is held, through as it is let go.
local function bindKey(state: Types.TLobbyState, key: Enum.KeyCode, hand: Hand.TReaction, activate: () -> ())
	local isHeld = derive(function(): boolean
		return state.HeldKey() == key
	end)
	local wasHeld = false
	vide.effect(function()
		local held = isHeld()
		vide.untrack(function()
			hand.IsPressed(held)
			if wasHeld and not held then activate() end
			wasHeld = held
		end)
	end)
end

-- ============================== The level plate ==============================

-- The plate's level, its bar's share and its count, rolled toward the profile's.
local function levelPlate(state: Types.TLobbyState): Frame
	local arrive = arrival(state, Arrive.LEVEL, Vector2.new(0, -Arrive.FROM_TOP), true)
	local landed = landing(state, Arrive.LEVEL)
	local shown = derive(function(): number
		return Hud.Rolled(state.XpFrom(), state.XpTo(), state.XpAt(), state.Now())
	end)
	local level = derive(function(): number
		return math.floor(shown() + 1e-6)
	end)
	-- The bar's fill in whole px, and its share of a level in whole percents: a roll writes each step once.
	local fillPx = derive(function(): number
		return math.round((shown() - level()) * Layout.BAR_SIZE.X)
	end)
	local percent = derive(function(): number
		return math.floor((shown() - level()) * 100 + 1e-6)
	end)
	local rolled = derive(function(): number
		return Progress(state.Now(), state.XpAt(), Roll.SECONDS)
	end)
	local isRolling = derive(function(): boolean
		local t = rolled()
		return t > 0 and t < 1
	end)

	-- A level crossed while rolling: the plate is punched out, LV pops, the bar flashes and a ring leaves the plate.
	local punch = Hand.React("Take")
	local flash, strikeFlash = Hand.Kick(XpBar.FLASH_PERIOD, 1)
	local ring, configureRing = spring(function()
		return 1
	end, XpBar.RING_PERIOD, 1)
	local lastLevel = nil
	vide.effect(function()
		local current = level()
		vide.untrack(function()
			-- Before the roll starts the plate takes the profile's level as it is: only a crossing is celebrated.
			if lastLevel and current > lastLevel and rolled() > 0 then
				punch.Commit()
				strikeFlash(1)
				configureRing({ position = 0, velocity = 0 })
			end
			lastLevel = current
		end)
	end)

	local isRinging = derive(function(): boolean
		return ring() < 0.995
	end)

	return create("Frame")({
		Name = "Level",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			return UDim2.fromOffset(Layout.LEVEL.X + Layout.LEVEL_SIZE.X / 2, Layout.LEVEL.Y + Layout.LEVEL_SIZE.Y / 2)
				+ arrive()
		end,
		Size = UDim2.fromOffset(Layout.LEVEL_SIZE.X, Layout.LEVEL_SIZE.Y),
		BackgroundTransparency = 1,
		-- The ring is the plate's, not carried by its punch.
		create("Frame")({
			Name = "Ring",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = function()
				local grow = math.round(XpBar.RING_REACH * Motion.Out(ring()))
				return UDim2.new(1, 2 * grow, 1, 2 * grow)
			end,
			BackgroundTransparency = 1,
			Visible = isRinging,
			create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
			create("UIStroke")({
				Color = Palette.Pink,
				Thickness = XpBar.RING_LINE,
				Transparency = ring,
				LineJoinMode = Enum.LineJoinMode.Miter,
			}),
		}),
		Components.Panel({ Brackets = Layout.LEVEL_BRACKETS }, {
			Name = "Plate",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			create("UIScale")({ Scale = punch.Scale }),
			Components.Sheen(Hand.Sheen(punch, landed), 3),
			Components.Icon("Rank", {
				Name = "Rank",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(Layout.RANK.X, Layout.RANK.Y),
				Size = Components.GlyphBox(Layout.RANK_GLYPH),
				ImageColor3 = Palette.Gold,
				ZIndex = 4,
				create("UIScale")({
					Scale = function()
						return 1 + 0.4 * (punch.Scale() - 1)
					end,
				}),
			}),
			label({
				Name = "LV",
				Position = UDim2.fromOffset(Layout.LV.X, Layout.LV.Y),
				Size = UDim2.fromOffset(Layout.RULE.X - Layout.LV.X - 8, Layout.LV_TEXT),
				FontFace = Font.DisplayBold,
				TextSize = Layout.LV_TEXT,
				TextColor3 = Palette.Gold,
				Text = function()
					return `LV {level()}`
				end,
			}),
			create("Frame")({
				Name = "Rule",
				Position = UDim2.fromOffset(Layout.RULE.X, Layout.RULE.Y),
				Size = UDim2.fromOffset(1, Layout.RULE_HEIGHT),
				BackgroundColor3 = RULE,
				BackgroundTransparency = RULE_TRANSPARENCY,
				BorderSizePixel = 0,
				ZIndex = 4,
			}),
			label({
				Name = "Caption",
				Position = UDim2.fromOffset(Layout.XP.X, Layout.XP.Y),
				Size = UDim2.fromOffset(60, Layout.XP_TEXT),
				FontFace = Font.DisplayBold,
				TextSize = Layout.XP_TEXT,
				TextColor3 = Palette.Gold,
				Text = "XP",
			}),
			label({
				Name = "Count",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromOffset(Layout.COUNT_RIGHT, Layout.XP.Y),
				Size = UDim2.fromOffset(180, Layout.XP_TEXT),
				TextXAlignment = Enum.TextXAlignment.Right,
				FontFace = Font.DisplayBold,
				TextSize = Layout.XP_TEXT,
				Text = function()
					return `{percent()} / 100`
				end,
			}),
			create("Frame")({
				Name = "Track",
				Position = UDim2.fromOffset(Layout.BAR.X, Layout.BAR.Y),
				Size = UDim2.fromOffset(Layout.BAR_SIZE.X, Layout.BAR_SIZE.Y),
				BackgroundColor3 = Palette.White,
				BackgroundTransparency = TRACK_TRANSPARENCY,
				BorderSizePixel = 0,
				ZIndex = 4,
				create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
				create("Frame")({
					Name = "Fill",
					Size = function()
						return UDim2.new(0, fillPx(), 1, 0)
					end,
					BackgroundColor3 = Palette.Pink,
					BorderSizePixel = 0,
					Visible = function()
						return fillPx() > 0
					end,
					create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
					-- The light at the fill's end while it rolls: a white head fading back down the fill.
					create("Frame")({
						Name = "Head",
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.fromScale(1, 0),
						-- Never longer than the fill, or it pokes out of the track's start.
						Size = function()
							return UDim2.new(0, math.min(XpBar.HEAD, fillPx()), 1, 0)
						end,
						BackgroundColor3 = Palette.White,
						BorderSizePixel = 0,
						Visible = isRolling,
						create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
						create("UIGradient")({
							Transparency = NumberSequence.new(1, 0.1),
						}),
					}),
				}),
				-- A level filled: the whole track flashes, since the fill has just gone back to the start.
				create("Frame")({
					Name = "Flash",
					Size = UDim2.fromScale(1, 1),
					BackgroundColor3 = Palette.White,
					BorderSizePixel = 0,
					ZIndex = 2,
					Visible = function()
						return flash() > 0.01
					end,
					BackgroundTransparency = function()
						return 1 - 0.85 * flash()
					end,
					create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
				}),
			}),
		}),
	})
end

-- ============================== The Gems counter ==============================

-- The same throw for the same chip every time: 0 to 1.
local function scatter(index: number, salt: number): number
	local x = math.sin(index * 12.9898 + salt * 78.233) * 43758.5453
	return x - math.floor(x)
end

-- A gain's chips, thrown off the gem glyph (its middle at `from` in the pill) as `travel` runs 0 to 1 and drawn only
-- while it does: born past the glyph's edge, flying out against drag and falling a little, spinning, shrinking and
-- fading to nothing (never a blink). Thrown across a fan on the gem's open side, never over the count as it lands.
local function chips(travel: () -> number, isBursting: () -> boolean, from: Vector2): { Frame }
	local pieces = table.create(Counter.CHIPS)
	for index = 1, Counter.CHIPS do
		local share = (index - 1 + (scatter(index, 1) - 0.5) * 0.8) / (Counter.CHIPS - 1)
		local angle = math.rad(Motion.Lerp(Counter.FAN_FROM, Counter.FAN_TO, share))
		local out = Vector2.new(math.cos(angle), math.sin(angle))
		local reach = Motion.Lerp(Counter.REACH_MIN, Counter.REACH_MAX, scatter(index, 2))
		local side = Motion.Lerp(Counter.CHIP_MIN, Counter.CHIP_MAX, scatter(index, 3))
		local spin = Counter.CHIP_SPIN * (2 * scatter(index, 4) - 1)
		local color = if index % 3 == 0 then Palette.White elseif index % 3 == 1 then GEM_BLUE else GEM_LIGHT
		pieces[index] = create("Frame")({
			Name = "Chip",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				local t = travel()
				local at = from
					+ out * (Counter.CHIP_BORN + reach * Motion.Out(t))
					+ Vector2.new(0, Counter.FALL * t * t)
				return UDim2.fromOffset(at.X, at.Y)
			end,
			Size = function()
				local shown = math.round(side * (1 - 0.5 * travel()))
				return UDim2.fromOffset(shown, shown)
			end,
			Rotation = function()
				return 45 + spin * travel()
			end,
			BackgroundColor3 = color,
			BackgroundTransparency = function()
				local t = travel()
				return t * t
			end,
			BorderSizePixel = 0,
			Visible = isBursting,
			ZIndex = 6,
		})
	end

	return pieces
end

-- The light catching the gem: a four-point twinkle at its top right, `amount` 0 to 1. Its arms taper to nothing at both
-- ends and thin as they shorten, so it goes out as a line and never as a dot.
local function twinkle(amount: () -> number): Frame
	local taper = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	local arms = table.create(2)
	for index = 1, 2 do
		local isAcross = index == 1
		arms[index] = create("Frame")({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = function()
				local shown = amount()
				local length = math.round(Counter.TWINKLE_ARM * shown)
				local width = math.max(1, math.round(Counter.TWINKLE_WIDTH * shown))
				return if isAcross then UDim2.fromOffset(length, width) else UDim2.fromOffset(width, length)
			end,
			BackgroundColor3 = Palette.White,
			BorderSizePixel = 0,
			create("UIGradient")({ Rotation = if isAcross then 0 else 90, Transparency = taper }),
		})
	end

	return create("Frame")({
		Name = "Twinkle",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(Counter.TWINKLE_AT.X, Counter.TWINKLE_AT.Y),
		Size = UDim2.fromOffset(Counter.TWINKLE_ARM, Counter.TWINKLE_ARM),
		BackgroundTransparency = 1,
		Visible = function()
			return amount() > 0
		end,
		ZIndex = 2,
		arms,
	})
end

-- +: his violet-edged ink square with a white cross, beside the pill. Nothing to open yet.
local function plusButton(): TextButton
	local hand = Hand.React("Operate")
	local arms = table.create(2)
	for index, size in { Layout.PLUS_ARM, Vector2.new(Layout.PLUS_ARM.Y, Layout.PLUS_ARM.X) } do
		arms[index] = create("Frame")({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(size.X, size.Y),
			BackgroundColor3 = Palette.White,
			BorderSizePixel = 0,
			ZIndex = 3,
			create("UICorner")({ CornerRadius = UDim.new(0, 1) }),
		})
	end

	return Components.Button({
		Name = "Add",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(Layout.PLUS_SIZE, Layout.PLUS_SIZE),
		BackgroundTransparency = 1,
		Activated = hand.Commit,
		hand.Events,
		create("Frame")({
			Name = "Body",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = function()
				return PLUS_EDGE:Lerp(Palette.Violet, hand.Light())
			end,
			BorderSizePixel = 0,
			create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			create("UIScale")({ Scale = hand.Scale }),
			create("UIShadow")({
				BlurRadius = UDim.new(0, 20),
				Color = Palette.Violet,
				Offset = UDim2.fromOffset(0, 4),
				Spread = UDim2.new(),
				Transparency = function()
					return 1 - 0.5 * hand.Light()
				end,
				ZIndex = -1,
			}),
			create("Frame")({
				Name = "Face",
				Position = UDim2.fromOffset(2, 2),
				Size = UDim2.new(1, -4, 1, -4),
				BackgroundColor3 = PLUS_FACE,
				BorderSizePixel = 0,
				create("UICorner")({ CornerRadius = UDim.new(0, 1) }),
				Hand.WashLayer(hand, 2, 1),
				Components.Sheen(hand.Glint, 2),
				arms,
			}),
		}),
	})
end

-- The Gems counter: his coin pill with our Gems and his + beside it, alone at the top centre, up in the middle of
-- Roblox's top bar strip (only its left corner and the icons on its right are taken), gliding into his coin slot while
-- the classes or weapons page is up (init puts the top bar's icons away meanwhile). The count rolls up to the profile; Gems flown into it (state.GemsHeld) land a slice at a time while it swells and its glow climbs; a roll or the
-- last slice landing punches it, and a gain also flashes it, rattles the gem, sends one ring off it and throws chips out
-- of the gem. Gems spent squeeze the gem as the count starts down; every few seconds the light catches the gem.
local function gemsCounter(state: Types.TLobbyState, actions: Types.TLobbyActions): Frame
	local pill = Layout.PILL_SIZE
	local width = pill.X + Layout.PLUS_GAP + Layout.PLUS_SIZE
	-- The counter's middle when docked: the + on his +, the pill to its left. The + is odd-sized, so its middle is on a
	-- half pixel; floored, the drawn edge lands on his (rounded, it came out a pixel low).
	local docked = Layout.DOCKED_PLUS + Vector2.new(Layout.PLUS_SIZE - width / 2, Layout.PLUS_SIZE // 2)

	local dock = Hand.Spring(function()
		return if state.IsGemsDocked() then 1 else 0
	end, Counter.DOCK_PERIOD)
	local arrive = arrival(state, Arrive.COUNTER, Vector2.new(0, -Arrive.FROM_TOP), false, true)
	local landed = landing(state, Arrive.COUNTER)
	local glyphAway = derive(function(): number
		return 1 - Motion.Decelerate(Progress(state.Now(), state.EnteredAt(), Arrive.SLIDE, Arrive.GLYPH))
	end)
	local count = derive(function(): number
		return math.floor(Hud.Rolled(state.GemsFrom(), state.GemsTo(), state.GemsAt(), state.Now()) + 0.5)
	end)
	local rolled = derive(function(): number
		return Progress(state.Now(), state.GemsAt(), Roll.SECONDS)
	end)
	local isRolling = derive(function(): boolean
		return rolled() < 1
	end)
	-- A gain's roll lights the glow up and back down as it runs.
	local rollLight = derive(function(): number
		if state.GemsTo() <= state.GemsFrom() then return 0 end
		return Motion.Bump(rolled())
	end)
	local fed = Hand.Spring(function()
		return if state.IsGemsFed() then 1 else 0
	end, Counter.FED_PERIOD)

	local punch = Hand.React("Take")
	local flash, strikeFlash = Hand.Kick(Counter.FLASH_PERIOD, 1)
	local rattle, strikeRattle = Hand.Kick(Counter.RATTLE_PERIOD, Counter.RATTLE_DAMPING)
	local squeeze, strikeSqueeze = Hand.Kick(Counter.SQUEEZE_PERIOD, Counter.SQUEEZE_DAMPING)
	local glint, strikeGlint = Hand.Kick(Counter.TWINKLE_PERIOD, 1)
	local burstTravel, throwBurst = spring(function()
		return Counter.BURST_END
	end, Counter.BURST_PERIOD, 1)
	-- Derived, so the spring's slow last stretch toward BURST_END redraws nothing once the burst is over.
	local travel = derive(function(): number
		return math.min(burstTravel(), 1)
	end)
	local isBursting = derive(function(): boolean
		local t = travel()
		return t > 0 and t < 1
	end)
	local ringed = derive(function(): number
		return math.min(travel() / Counter.RING_LIFE, 1)
	end)
	-- 0 to 1 and back as the glint spring falls from 1 to rest, cut at TWINKLE_FLOOR: the spring's long tail would
	-- otherwise keep a sliver lit and rewriting for a second.
	local twinkled = derive(function(): number
		local amount = Motion.Bump(1 - glint())
		return if amount < Counter.TWINKLE_FLOOR then 0 else amount
	end)

	local function land(isGain: boolean)
		punch.Commit()
		if not isGain then return end
		strikeFlash(1)
		strikeRattle(if math.random() < 0.5 then 1 else -1)
		strikeGlint(1)
		throwBurst({ position = 0, velocity = Counter.BURST_SPEED })
	end

	local wasRolling = false
	vide.effect(function()
		local rolling = isRolling()
		vide.untrack(function()
			if wasRolling and not rolling then land(state.GemsTo() > state.GemsFrom()) end
			wasRolling = rolling
		end)
	end)
	local wasFed = false
	vide.effect(function()
		local isFed = state.IsGemsFed()
		vide.untrack(function()
			if wasFed and not isFed then land(true) end
			wasFed = isFed
		end)
	end)
	-- Gems spent: the gem gives them up as the count starts down.
	vide.effect(function()
		local at = state.GemsAt()
		vide.untrack(function()
			if at > -math.huge and state.GemsTo() < state.GemsFrom() then strikeSqueeze(1) end
		end)
	end)
	-- The light catches the gem as it lands (before the lobby opens it is still away), and whenever init calls for it.
	local hasGlyphLanded = false
	vide.effect(function()
		local isDown = glyphAway() == 0
		vide.untrack(function()
			if isDown and not hasGlyphLanded then strikeGlint(1) end
			hasGlyphLanded = isDown
		end)
	end)
	vide.effect(function()
		local at = state.GemGlintAt()
		vide.untrack(function()
			if at > -math.huge then strikeGlint(1) end
		end)
	end)

	return create("Frame")({
		Name = "Gems",
		AnchorPoint = Vector2.new(0.5, 0.5),
		-- Glides between the top centre and his coin slot.
		Position = function()
			local at = Vector2.new(0, Layout.COUNTER_MIDDLE):Lerp(docked, dock())
			return UDim2.new(0.5, math.round(at.X), 0, math.round(at.Y)) + arrive()
		end,
		Size = UDim2.fromOffset(width, Layout.PLUS_SIZE),
		BackgroundTransparency = 1,
		-- One ring off the pill, its own shape growing by px; not carried by its punch.
		create("Frame")({
			Name = "Ring",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, pill.X / 2, 0.5, 0),
			Size = function()
				local grow = math.round(Counter.RING_REACH * Motion.Out(ringed()))
				return UDim2.fromOffset(pill.X + 2 * grow, pill.Y + 2 * grow)
			end,
			BackgroundTransparency = 1,
			Visible = isBursting,
			create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
			create("UIStroke")({
				Color = Palette.Gold,
				Thickness = Counter.RING_LINE,
				Transparency = ringed,
				LineJoinMode = Enum.LineJoinMode.Miter,
			}),
		}),
		Components.Pill({
			Face = Palette.Gold,
			Lip = Palette.Gold,
			Brackets = Layout.PILL_BRACKETS,
			GlowTransparency = function()
				return PILL_GLOW - Counter.GLOW_LIT * math.max(fed(), rollLight())
			end,
		}, {
			Name = "Pill",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, pill.X / 2, 0.5, 0),
			Size = UDim2.fromOffset(pill.X, pill.Y),
			create("UIScale")({
				Scale = function()
					return punch.Scale() * (1 + Counter.PILL_SWELL * fed())
				end,
			}),
			Components.Sheen(Hand.Sheen(punch, landed), 3),
			-- A gain lands white across the pill.
			create("Frame")({
				Name = "Flash",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Palette.White,
				BorderSizePixel = 0,
				ZIndex = 3,
				Visible = function()
					return flash() > 0.01
				end,
				BackgroundTransparency = function()
					return 1 - Counter.FLASH * flash()
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
			}),
			chips(travel, isBursting, Layout.GEM),
			Components.Icon("Gem", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = function()
					return UDim2.fromOffset(Layout.GEM.X, Layout.GEM.Y - math.round(Counter.GLYPH_DROP * glyphAway()))
				end,
				Rotation = function()
					return Counter.GLYPH_SPIN * glyphAway() + Counter.RATTLE * rattle()
				end,
				Size = Components.GlyphBox(Layout.GEM_GLYPH),
				ImageColor3 = Palette.White,
				ZIndex = 5,
				vide.action(function(instance: Instance)
					actions.MarkGemsGlyph(instance :: GuiObject)
				end),
				-- On top of the pill's own: the gem pops harder than the pill it sits on.
				create("UIScale")({
					Scale = function()
						return punch.Scale()
							* (1 + Counter.GLYPH_SWELL * fed())
							* (1 - Counter.SQUEEZE * squeeze())
							* Motion.Lerp(1, Counter.GLYPH_FROM, glyphAway())
					end,
				}),
				twinkle(twinkled),
			}),
			label({
				Name = "Count",
				Position = UDim2.fromOffset(Layout.GEMS_TEXT_LEFT, Layout.PILL_TEXT_TOP),
				Size = UDim2.fromOffset(pill.X - Layout.GEMS_TEXT_LEFT - 8, Layout.PILL_TEXT),
				TextSize = Layout.PILL_TEXT,
				Text = function()
					return Components.Commas(count())
				end,
			}),
		}),
		plusButton(),
	})
end

-- ============================== The rail ==============================

-- One of the rail's cards: his tinted card, the glyph in its accent, the key, the word under it.
local function railCard(
	state: Types.TLobbyState,
	actions: Types.TLobbyActions,
	index: number,
	spec: TCardSpec
): TextButton
	local delay = Arrive.CARDS[index]
	local arrive = arrival(state, delay, Vector2.new(-Arrive.FROM_LEFT, 0), true)
	local landed = landing(state, delay)
	local hand = Hand.React("Operate")
	local hop, strikeHop = Hand.Kick(Gesture.HOP_PERIOD, Gesture.HOP_DAMPING)
	local turn, strikeTurn = Hand.Kick(Gesture.SPIN_PERIOD, Gesture.SPIN_DAMPING)
	local action = if spec.Action then (actions :: any)[spec.Action] else nil
	local isCalling = derive(function(): boolean
		if spec.Calls == "Daily" then return state.IsDailyReady() end
		if spec.Calls == "Index" then return state.IsIndexNew() end
		return false
	end)
	local called = derive(function(): number
		if not isCalling() then return 1 end
		return Progress(state.Now(), state.CallAt(), Gesture.CALL_SHEEN)
	end)

	local function activate()
		hand.Commit()
		strikeHop(-Gesture.HOP)
		if spec.Icon == "Spin" then strikeTurn(-360) end
		if action then action() end
	end
	bindKey(state, spec.Key, hand, activate)

	local edge = Color3.new(spec.Accent.R * CARD_EDGE, spec.Accent.G * CARD_EDGE, spec.Accent.B * CARD_EDGE)
	local half = Layout.CARD / 2
	local drawnHalf = Layout.CARD * Layout.CARD_SCALE / 2

	return Components.Button({
		Name = spec.Icon,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			return UDim2.new(0, Layout.CARD_LEFT + drawnHalf, 0.5, Layout.CARD_TOPS[index] + drawnHalf) + arrive()
		end,
		Size = UDim2.fromOffset(Layout.CARD, Layout.CARD),
		BackgroundTransparency = 1,
		Activated = activate,
		hand.Events,
		create("UIScale")({ Scale = Layout.CARD_SCALE }),
		Components.Card({
			Accent = edge,
			Glow = spec.Glow or spec.Accent,
			GlowTransparency = function()
				return GLOW_TRANSPARENCY
					- Gesture.GLOW_LIT * hand.Light()
					- (if isCalling() then Gesture.CALL_GLOW else 0)
			end,
			Tint = CARD_TINT,
			Marks = true,
			Brackets = function()
				return Layout.CARD_BRACKETS + Gesture.BRACKETS_OPEN * hand.Rise()
			end,
			BracketLength = Layout.CARD_BRACKET_LENGTH,
			BracketTransparency = function()
				return 0.6 - 0.3 * hand.Light()
			end,
		}, {
			Name = "Card",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			create("UIScale")({ Scale = hand.Scale }),
			Hand.WashLayer(hand, 3, 2),
			Components.Sheen(
				Hand.Sheen(hand, function(): number
					local light = landed()
					return if light < 1 then light else called()
				end),
				3
			),
			Components.Icon(spec.Icon, {
				Name = "Glyph",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = function()
					return UDim2.fromOffset(spec.At.X, spec.At.Y + math.round(hop()))
				end,
				Size = Components.GlyphBox(spec.Glyph),
				ImageColor3 = spec.Accent,
				Rotation = turn,
				ZIndex = 4,
				create("UIScale")({
					Scale = function()
						return 1 + Gesture.GLYPH_RISE * hand.Rise()
					end,
				}),
			}),
			Components.KeyBadge(spec.Key, Layout.KEY_BADGE, {
				Position = UDim2.fromOffset(Layout.KEY.X, Layout.KEY.Y),
				Size = UDim2.fromOffset(Layout.KEY_SIZE.X, Layout.KEY_SIZE.Y),
				ZIndex = 5,
			}),
			label({
				Name = "Label",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromOffset(half, Layout.CARD_LABEL_TOP),
				Size = UDim2.fromOffset(220, Layout.CARD_LABEL_TEXT),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextSize = Layout.CARD_LABEL_TEXT,
				TextColor3 = Palette.Lavender,
				Text = spec.Name,
				-- Under the card, so straight on the world: his lavender is lost on the lobby's bright floors. 2 px, or at
				-- a phone's scale the ink thins under a pixel and goes.
				Components.Ink(Layout.CARD_LABEL_TEXT, 2),
			}),
		}),
	})
end

-- ============================== The action row ==============================

-- His MENU glyph: three white bars.
local function hamburger(): Frame
	local bars = table.create(3)
	for index = 1, 3 do
		bars[index] = create("Frame")({
			Position = UDim2.fromOffset(0, (index - 1) * Layout.HAMBURGER_STEP),
			Size = UDim2.fromOffset(Layout.HAMBURGER_BAR.X, Layout.HAMBURGER_BAR.Y),
			BackgroundColor3 = Palette.White,
			BorderSizePixel = 0,
			create("UICorner")({ CornerRadius = UDim.new(0, 1) }),
		})
	end

	return create("Frame")({
		Name = "Glyph",
		Position = UDim2.fromOffset(Layout.HAMBURGER.X, Layout.HAMBURGER.Y),
		Size = UDim2.fromOffset(Layout.HAMBURGER_BAR.X, 2 * Layout.HAMBURGER_STEP + Layout.HAMBURGER_BAR.Y),
		BackgroundTransparency = 1,
		ZIndex = 4,
		bars,
	})
end

-- One of the row's slabs: his flat slab in its colour, its glyph and its spaced-out word.
local function slab(state: Types.TLobbyState, actions: Types.TLobbyActions, index: number, spec: TSlabSpec): TextButton
	local delay = Arrive.SLABS[index]
	local arrive = arrival(state, delay, Vector2.new(0, Arrive.FROM_BOTTOM), true)
	local landed = landing(state, delay)
	local hand = Hand.React("Operate")
	local hop, strikeHop = Hand.Kick(Gesture.HOP_PERIOD, Gesture.HOP_DAMPING)
	local recoil, strikeRecoil = Hand.Kick(Gesture.KICK_PERIOD, Gesture.KICK_DAMPING)
	local action = if spec.Action then (actions :: any)[spec.Action] else nil
	local size = Layout.SLAB_SIZE

	local glyph = if spec.Icon
		then Components.Icon(spec.Icon, {
			Name = "Glyph",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				local back = recoil()
				return UDim2.fromOffset(
					spec.At.X + math.round(Gesture.KICK.X * back),
					spec.At.Y + math.round(Gesture.KICK.Y * back + hop())
				)
			end,
			Rotation = function()
				return Gesture.KICK_TURN * recoil()
			end,
			Size = Components.GlyphBox(spec.Glyph),
			ImageColor3 = Palette.White,
			ZIndex = 4,
			create("UIScale")({
				Scale = function()
					return 1 + Gesture.GLYPH_RISE * hand.Rise()
				end,
			}),
		})
		else hamburger()

	return Components.Button({
		Name = spec.Name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			return UDim2.new(0.5, Layout.SLAB_LEFTS[index] + size.X / 2, 1, -Layout.SLAB_BOTTOM - size.Y / 2) + arrive()
		end,
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundTransparency = 1,
		Activated = function()
			hand.Commit()
			if spec.Icon == "Rifle" then
				strikeRecoil(1)
			else
				strikeHop(-Gesture.HOP)
			end
			if action then action() end
		end,
		hand.Events,
		Components.FlatSlab({
			Face = spec.Face,
			Brackets = function()
				return Layout.SLAB_BRACKETS + Gesture.BRACKETS_OPEN * hand.Rise()
			end,
			BracketTransparency = function()
				return 0.6 - 0.3 * hand.Light()
			end,
			GlowTransparency = function()
				return SLAB_GLOW_TRANSPARENCY - Gesture.GLOW_LIT * hand.Light()
			end,
		}, {
			Name = "Slab",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			create("UIScale")({ Scale = hand.Scale }),
			Hand.WashLayer(hand, 3, 3),
			Components.Sheen(Hand.Sheen(hand, landed), 3),
			glyph,
			Components.Tracked(
				spec.Name,
				spec.TextSize,
				spec.Tracking,
				if spec.IsLight then Font.DisplayBold else Font.Display,
				{
					Position = UDim2.fromOffset(spec.TextLeft, math.round((size.Y - spec.TextSize) / 2)),
				}
			),
		}),
	})
end

-- The Gems counter, for a gui of its own laid from the screen's top, over the lobby's screens and their dims.
function Hud.BuildGems(state: Types.TLobbyState, actions: Types.TLobbyActions): Frame
	return gemsCounter(state, actions)
end

function Hud.Build(state: Types.TLobbyState, actions: Types.TLobbyActions): { Instance }
	local children = { levelPlate(state) }
	local count = #children
	for index, spec in CARDS do
		count += 1
		children[count] = railCard(state, actions, index, spec)
	end
	for index, spec in SLABS do
		count += 1
		children[count] = slab(state, actions, index, spec)
	end

	return children
end

return Hud
