--!nonstrict
-- The results (UIMatt.md, Round Results), up while a wiped run is held: the world dims, the panel rises, and its
-- cards are dealt in the order they matter. The wave counts up and lands with a punch, NEW BEST is stamped on it, the
-- run's Gems fly out of their card into the total, and a bought doubling pours as many again into them. Under the
-- hand a button swells and its glow comes up; REVIVE's heart beats for as long as the screen is up. The player's own
-- avatar stands on the wave card with its arms folded (ours, not his: his card is empty there). UPGRADES AVAILABLE
-- is drawn as he drew it and does nothing: there are no lobby upgrades yet.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local GunPicture = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.GunPicture)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Types = require(script.Parent.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
local source = vide.source
local spring = vide.spring
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress
local Lerp = Motion.Lerp

-- His drawn rects in px at 1080: a piece's corner is from the corner of what holds it (the panel, or its card).
local Layout = table.freeze({
	SIZE = Vector2.new(1239, 719),
	-- Where the panel's middle sits: px left of the screen's (his art is not centred in its box), and the share of
	-- the screen down.
	CENTER_X = -4,
	CENTER_Y = 0.4903,

	-- The header: the skull's middle and longer side, the title, the countdown's words, badge and bar, the line under
	-- them all.
	SKULL = Vector2.new(61, 47),
	SKULL_SIZE = 47,
	TITLE = Vector2.new(103, 20),
	TITLE_SIZE = 56,
	RETURN = Vector2.new(1018, 26),
	RETURN_SIZE = 20,
	BADGE = Vector2.new(1171, 16),
	BADGE_SIZE = 40,
	BADGE_TEXT = 24,
	BAR = Vector2.new(1017, 70),
	BAR_SIZE = Vector2.new(193, 9),
	RULE = Vector2.new(31, 101),
	RULE_SIZE = Vector2.new(1178, 2),

	WAVE = Vector2.new(35, 126),
	WAVE_CARD = Vector2.new(520, 420),
	WAVE_LABEL = Vector2.new(157, 28),
	WAVE_LABEL_SIZE = 23,
	WAVE_VALUE = Vector2.new(162, 49),
	WAVE_VALUE_SIZE = 100,
	-- The avatar standing on the card's left: the middle and side of its picture, where the camera stands round it
	-- from its front and over it (deg).
	AVATAR = Vector2.new(80, 172),
	AVATAR_SIZE = 252,
	AVATAR_YAW = -24,
	AVATAR_PITCH = 4,
	BEST = Vector2.new(203, 262),
	BEST_TAG = Vector2.new(114, 32),
	BEST_TEXT = 16,
	-- The two stats under the wave: their corners, and inside each the glyph's middle, the caption and the number.
	KILLS = Vector2.new(24, 316),
	TIME = Vector2.new(268, 316),
	STAT = Vector2.new(228, 80),
	STAT_ICON = Vector2.new(32, 40),
	STAT_ICON_SIZE = 32,
	STAT_LABEL = Vector2.new(62, 16),
	STAT_LABEL_SIZE = 13,
	STAT_VALUE = Vector2.new(62, 34),
	STAT_VALUE_SIZE = 34,

	GEMS = Vector2.new(579, 126),
	GEMS_CARD = Vector2.new(632, 190),
	GEMS_LABEL = Vector2.new(28, 24),
	GEMS_LABEL_SIZE = 22,
	GEM = Vector2.new(65, 109),
	GEM_SIZE = 67,
	GEMS_VALUE = Vector2.new(122, 60),
	GEMS_VALUE_SIZE = 94,
	-- TOTAL and its number end at this x.
	TOTAL_RIGHT = 607,
	TOTAL_LABEL_Y = 68,
	TOTAL_LABEL_SIZE = 15,
	TOTAL_VALUE_Y = 89,
	TOTAL_VALUE_SIZE = 36,

	DOUBLE = Vector2.new(579, 336),
	DOUBLE_CARD = Vector2.new(632, 210),
	BONUS = Vector2.new(28, 20),
	BONUS_TAG = Vector2.new(78, 26),
	BONUS_TEXT = 15,
	DOUBLE_LABEL = Vector2.new(28, 56),
	DOUBLE_LABEL_SIZE = 36,
	-- The doubled amount ends at this x, its gem standing before it.
	DOUBLE_RIGHT = 604,
	DOUBLE_VALUE_Y = 51,
	DOUBLE_VALUE_SIZE = 48,
	DOUBLE_GEM_SIZE = 33,
	DOUBLE_GEM_GAP = 13,
	-- The two offers 3 px narrower than his and 20 apart (his 14): under a press one's brackets reach 13 px out.
	ROBUX = Vector2.new(27, 117),
	ROBUX_ALONE = Vector2.new(176, 117),
	ADVERT = Vector2.new(326, 117),
	OFFER = Vector2.new(279, 72),

	LOBBY = Vector2.new(35, 576),
	LOBBY_SIZE = Vector2.new(290, 112),
	-- The bottom row over his span, 22 between any two pieces (his 15 and 7): under a press PLAY AGAIN's and REVIVE's
	-- brackets reach 15 px out, so both are narrower than his 382 and 358.
	AGAIN = Vector2.new(347, 575),
	AGAIN_SIZE = Vector2.new(364, 114),
	VOTES = Vector2.new(733, 576),
	VOTES_SIZE = Vector2.new(110, 112),
	VOTES_VALUE_Y = 27,
	VOTES_VALUE_SIZE = 37,
	VOTES_LABEL_Y = 71,
	VOTES_LABEL_SIZE = 13,
	REVIVE = Vector2.new(865, 575),
	REVIVE_SIZE = Vector2.new(347, 114),

	UPGRADES = Vector2.new(58, 746),
	UPGRADES_TAG = Vector2.new(244, 42),
	UPGRADES_TEXT = 19,

	-- The room round a piece inside the group that fades it, for its glow and brackets (a CanvasGroup clips).
	MARGIN = 48,
	-- Where the Gems fly, from the panel's corner: out of the big gem into the total, and out of the doubled amount's
	-- gem into the big one.
	GEM_AT = Vector2.new(644, 235),
	TOTAL_AT = Vector2.new(1135, 233),
	DOUBLE_GEM_AT = Vector2.new(1052, 413),
})

local Timing = table.freeze({
	-- The panel decelerates up into place and accelerates down out of it, its fade on the clock (a fade tied to a
	-- decelerate reads as a pop).
	OPEN = 0.38,
	FADE = 0.3,
	RISE = 26,
	CLOSE = 0.22,
	SINK = 14,
	DIM = 0.5,
	-- The header: the skull is stamped down, the title slides out from behind it, the countdown fades in.
	SKULL_DELAY = 0.08,
	SKULL = 0.3,
	SKULL_SCALE = 0.6,
	TITLE_DELAY = 0.12,
	TITLE = 0.34,
	TITLE_SLIDE = 26,
	RETURN_DELAY = 0.3,
	RETURN = 0.3,
	-- Each piece rises into place a beat after the one before it, in the order the screen is read.
	DEAL = 0.4,
	DEAL_FADE = 0.3,
	DEAL_RISE = 20,
	WAVE_DELAY = 0.16,
	GEMS_DELAY = 0.25,
	DOUBLE_DELAY = 0.34,
	LOBBY_DELAY = 0.46,
	AGAIN_DELAY = 0.52,
	VOTES_DELAY = 0.58,
	REVIVE_DELAY = 0.64,
	UPGRADES_DELAY = 0.8,
	-- The avatar steps in with its card, from a little big.
	AVATAR_DELAY = 0.3,
	AVATAR = 0.45,
	AVATAR_SCALE = 0.1,
	-- The wave counts up, lands with a swell that falls straight back, and the light crosses its card.
	WAVE_COUNT_DELAY = 0.4,
	WAVE_COUNT = 0.9,
	WAVE_PUNCH = 0.34,
	WAVE_PUNCH_SCALE = 0.16,
	WAVE_SHEEN = 0.7,
	-- NEW BEST is stamped on a beat after the wave lands: it comes down from bigger, goes white for a moment, and
	-- throws a few motes off its edges.
	BEST_DELAY = 0.12,
	BEST = 0.26,
	BEST_SCALE = 0.55,
	BEST_FLASH = 0.45,
	MOTES_DELAY = 0.18,
	MOTES = 0.75,
	MOTES_REACH = 46,
	MOTES_FALL = 16,
	STATS_COUNT_DELAY = 0.6,
	STATS_COUNT = 0.8,
	-- The Gems count up as their card lands, then fly to the total.
	GEMS_COUNT_DELAY = 0.5,
	GEMS_COUNT = 0.9,
	GEMS_FLY_DELAY = 1.0,
	GEMS_SHEEN_DELAY = 0.45,
	-- A flight: thrown out of the gem against drag, hung, then pulled into its target faster and faster. The first
	-- lands FIRST_LAND after the throw and the rest over SPREAD, in a shuffled order.
	THROW = 0.42,
	PULL_AT = 0.3,
	FIRST_LAND = 0.78,
	SPREAD = 0.62,
	FLIGHT_IN = 0.08,
	FLIGHT_OUT = 0.09,
	-- What the Gems land in swells with how fast they are landing, not once a gem, and flashes on the last.
	LAND_DECAY = 0.14,
	LAND_SWELL = 0.045,
	LAND_FLASH = 0.5,
	-- A doubling: the card goes white and falls back as its Gems leave.
	DOUBLED_FLASH = 0.5,
	-- The countdown: each second drops into the badge, and the last few swell it.
	TICK = 0.2,
	TICK_DROP = 6,
	LAST_SECONDS = 5,
	LAST_SWELL = 0.14,
	-- A count that changed swells its number.
	VOTE = 0.3,
	VOTE_SCALE = 0.2,
	-- A button under the hand, and one pressed.
	HOVER_SCALE = 1.03,
	PRESS_SCALE = 0.96,
	HOVER_GLOW = 0.38,
	-- The buttons that are bought catch the light in turn, and REVIVE's heart beats twice a cycle.
	ASK_EVERY = 3.4,
	ASK_SHEEN = 0.8,
	BEAT_EVERY = 1.3,
	BEAT = 0.2,
	BEAT_SCALE = 0.16,
})

-- How see-through his stat plates are: the ink face and the edge round it.
local Look = table.freeze({
	PLATE_FACE = 0.3,
	PLATE_EDGE = 0.165,
})

local Colors = table.freeze({
	-- His cards' edges: the wave's pink, the Gems' blue, the doubling's violet.
	WAVE = Color3.fromRGB(228, 42, 128),
	-- The wave card's face is plum where the other cards' is navy.
	WAVE_FACE = Color3.fromRGB(27, 13, 42),
	GEMS = Color3.fromRGB(80, 166, 225),
	DOUBLE = Color3.fromRGB(124, 82, 228),
	GEM = Color3.fromRGB(89, 191, 255),
	KILLS_EDGE = Color3.fromRGB(144, 73, 34),
	TIME_EDGE = Color3.fromRGB(144, 109, 45),
	BONUS = Color3.fromRGB(139, 92, 255),
	BADGE_EDGE = Color3.fromRGB(143, 234, 185),
	RULE = Color3.fromRGB(48, 38, 79),
})

type TFlight = {
	-- The throw's direction and reach, the seconds after the batch starts that it leaves and lands, how far its pull
	-- carries on along the throw (a share of the trip), and its size in px.
	Direction: Vector2,
	Reach: number,
	LeaveAt: number,
	LandAt: number,
	Carry: number,
	Size: number,
}

-- One batch of flying Gems, the same for every flight of them: the paths are a picture, not a roll.
local FLIGHTS: { TFlight } = table.create(12)
do
	local random = Random.new(11)
	local count = 12
	local order = table.create(count)
	for index = 1, count do
		order[index] = index
	end
	random:Shuffle(order)

	for index = 1, count do
		-- Spread round the circle, each a little off its slot.
		local angle = (index + random:NextNumber(-0.35, 0.35)) / count * 2 * math.pi
		FLIGHTS[index] = table.freeze({
			Direction = Vector2.new(math.cos(angle), math.sin(angle)),
			Reach = random:NextNumber(52, 104),
			LeaveAt = random:NextNumber(0, 0.1),
			LandAt = Timing.FIRST_LAND + (order[index] - 1) / (count - 1) * Timing.SPREAD,
			Carry = random:NextNumber(0.22, 0.5),
			Size = random:NextInteger(17, 25),
		})
	end

	table.freeze(FLIGHTS)
end

type TMote = { Direction: Vector2, Start: Vector2, Reach: number, Size: number, Delay: number }

-- NEW BEST's motes: each starts just outside the tag's edge and leaves along the line from its middle.
local MOTES: { TMote } = table.create(12)
do
	local random = Random.new(5)
	local half = Layout.BEST_TAG / 2
	for index = 1, 12 do
		local angle = (index + random:NextNumber(-0.3, 0.3)) / 12 * 2 * math.pi
		local direction = Vector2.new(math.cos(angle), math.sin(angle))
		-- Where the ray from the middle leaves the tag, and a few px past it.
		local toEdge =
			math.min(half.X / math.max(math.abs(direction.X), 1e-3), half.Y / math.max(math.abs(direction.Y), 1e-3))
		MOTES[index] = table.freeze({
			Direction = direction,
			Start = half + direction * (toEdge + 5),
			Reach = Timing.MOTES_REACH * random:NextNumber(0.55, 1),
			Size = random:NextInteger(3, 6),
			Delay = random:NextNumber(0, 0.08),
		})
	end

	table.freeze(MOTES)
end

local Results = {}

-- How long the screen's one-off gestures run, for whoever drives its clock (Types.TResults.Clock): everything that
-- follows its going up, a doubling, and a tick of the countdown or a change of the count.
Results.Seconds = table.freeze({
	OPEN = Timing.GEMS_FLY_DELAY + Timing.FIRST_LAND + Timing.SPREAD + Timing.LAND_FLASH + 0.1,
	DOUBLED = Timing.FIRST_LAND + Timing.SPREAD + Timing.LAND_FLASH + 0.1,
	GESTURE = math.max(Timing.TICK, Timing.VOTE) + 0.05,
})

local function label(props: { [any]: any }): TextLabel
	return create("TextLabel")({
		BackgroundTransparency = 1,
		FontFace = Font.Display,
		TextColor3 = Palette.White,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2,
		props,
	})
end

-- 7550 -> "7.6K", as his big numbers are written (his 15.1K is twice his 7.6K, so they are rounded, not cut).
local function compact(value: number): string
	if value < 1000 then return tostring(value) end
	-- 999,950 and up would round to "1000K".
	local unit, size = "K", 1000
	if value >= 999950 then
		unit, size = "M", 1000000
	end

	local tenths = math.floor(value / size * 10 + 0.5)
	return if tenths % 10 == 0 then `{tenths // 10}{unit}` else `{tenths // 10}.{tenths % 10}{unit}`
end

-- Where flight `flight` is `t` seconds into a batch flying `from` to `to`, and how much of it is there (0 to 1).
local function flightAt(flight: TFlight, t: number, from: Vector2, to: Vector2): (Vector2, number)
	local since = t - flight.LeaveAt
	if since <= 0 or t >= flight.LandAt then return from, 0 end

	-- Thrown against drag: fast away, slowing to a hang.
	local thrown = 1 - (1 - math.min(since / Timing.THROW, 1)) ^ 3
	local hang = from + flight.Direction * flight.Reach
	local at = from + flight.Direction * flight.Reach * thrown

	-- The pull starts before the throw has died and carries on along it before turning in, so the path bends by a
	-- share of the trip rather than by a fixed bow.
	local pullAt = flight.LeaveAt + Timing.PULL_AT
	local pulled = math.clamp((t - pullAt) / (flight.LandAt - pullAt), 0, 1)
	pulled *= pulled
	local trip = (to - hang).Magnitude
	local control = hang + flight.Direction * trip * flight.Carry
	local curve = hang:Lerp(control, pulled):Lerp(control:Lerp(to, pulled), pulled)

	local there = math.min(since / Timing.FLIGHT_IN, (flight.LandAt - t) / Timing.FLIGHT_OUT, 1)
	return at + (curve - hang), there
end

-- The share of a batch of `count` flights that has landed `t` seconds in, and how hard they are landing right now
-- (each landing adds 1 and dies away).
local function landed(t: number, count: number): (number, number)
	if count <= 0 then return 1, 0 end
	local down, rate = 0, 0
	for index = 1, count do
		local since = t - FLIGHTS[index].LandAt
		if since < 0 then continue end
		down += 1
		rate += math.exp(-since / Timing.LAND_DECAY)
	end

	return down / count, rate
end

-- When the last of a batch of `count` flights lands, in seconds after it starts, by `count`.
local LAST_LANDING: { number } = table.create(#FLIGHTS)
do
	local last = 0
	for index, flight in FLIGHTS do
		last = math.max(last, flight.LandAt)
		LAST_LANDING[index] = last
	end

	table.freeze(LAST_LANDING)
end

-- 0 to 1 and back, twice in the first part of each BEAT_EVERY: a heart.
local function heartbeat(clock: number): number
	local into = clock % Timing.BEAT_EVERY
	return Motion.Bump(into / Timing.BEAT) + 0.6 * Motion.Bump((into - Timing.BEAT * 1.15) / Timing.BEAT)
end

-- What every piece of the screen times itself off.
type TClock = {
	-- Seconds since the screen went up or came down.
	Elapsed: () -> number,
	-- How much of it is there, 0 to 1.
	Shown: () -> number,
	-- 0 to 1 as a gesture `seconds` long runs from `delay` after the screen went up; done while it comes down.
	Since: (delay: number, seconds: number) -> number,
}

-- A piece dealt in at (x, y) of the panel: it rises into place and fades in from `delay`, and goes with the screen.
local function dealt(
	state: Types.THudState,
	clock: TClock,
	name: string,
	at: Vector2,
	size: Vector2,
	delay: number,
	child: Instance
): CanvasGroup
	local margin = Layout.MARGIN
	return create("CanvasGroup")({
		Name = name,
		Position = function()
			local rise = Timing.DEAL_RISE * (1 - Motion.Decelerate(clock.Since(delay, Timing.DEAL)))
			return UDim2.fromOffset(at.X - margin, at.Y - margin + math.round(rise))
		end,
		Size = UDim2.fromOffset(size.X + margin * 2, size.Y + margin * 2),
		BackgroundTransparency = 1,
		ZIndex = 2,
		GroupTransparency = function()
			if not state.Results.IsOpen() then return 1 - clock.Shown() end
			return 1 - Motion.Out(clock.Since(delay, Timing.DEAL_FADE))
		end,
		create("Frame")({
			Name = "Holder",
			Position = UDim2.fromOffset(margin, margin),
			Size = UDim2.fromOffset(size.X, size.Y),
			BackgroundTransparency = 1,
			child,
		}),
	})
end

-- His brackets round a card, fainter than a button's.
local function cardBrackets(): Frame
	return Components.Brackets(nil, 0.65, 22)
end

-- A light crossing its parent's face as `travel` runs 0 to 1, cut to the face.
local function sheen(travel: () -> number): Frame
	return create("Frame")({
		Name = "SheenWindow",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = 3,
		Components.Sheen(travel, 3),
	})
end

-- A glyph and a word side by side in the middle of a button, as he sets them.
local function caption(spec: { [string]: any }): Frame
	return create("Frame")({
		Name = "Caption",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 4,
		create("UIListLayout")({
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, spec.Gap),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		-- In a holder of its own, so a picture that swells (IconChild, a UIScale) does not push the word about. Robux
		-- is the flat glyph (Glyph), as Roblox draws it.
		if spec.Icon
			then create("Frame")({
				LayoutOrder = 1,
				Size = Components.PictureBox(spec.IconSize),
				BackgroundTransparency = 1,
				Visible = spec.IsIconShown,
				Components.Picture(spec.Icon, {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromScale(1, 1),
					spec.IconChild,
				}),
			})
			elseif spec.Glyph then create("Frame")({
				LayoutOrder = 1,
				Size = Components.GlyphBox(spec.IconSize),
				BackgroundTransparency = 1,
				Visible = spec.IsIconShown,
				Components.Icon(spec.Glyph, {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromScale(1, 1),
					ImageColor3 = Palette.White,
				}),
			})
			else nil,
		label({
			LayoutOrder = 2,
			Size = UDim2.fromOffset(0, spec.TextSize),
			AutomaticSize = Enum.AutomaticSize.X,
			TextSize = spec.TextSize,
			Text = spec.Text,
		}),
	})
end

-- One of his glossy buttons at `at` of what holds it. `spec`: Name, At (may be a source), IsShown (a source, or nil
-- for always), Size, Kind (may be a source), Icon, IconSize,
-- IconChild, IsIconShown, Text (may be a source), TextSize, Gap, Activated (nil for one that does nothing), IsLive (a
-- source: it answers the hand), Light (a source of a sheen's travel, or nil).
local function slabButton(spec: { [string]: any }): TextButton
	local isLive = spec.IsLive or function()
		return spec.Activated ~= nil
	end
	local hand = Hand.React("Operate", isLive)

	return Components.Button({
		Name = spec.Name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			local at = if type(spec.At) == "function" then spec.At() else spec.At
			return UDim2.fromOffset(at.X + spec.Size.X / 2, at.Y + spec.Size.Y / 2)
		end,
		Size = UDim2.fromOffset(spec.Size.X, spec.Size.Y),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Visible = spec.IsShown,
		Active = isLive,
		Activated = function()
			if not spec.Activated or not isLive() then return end
			hand.Commit()
			spec.Activated()
		end,
		hand.Events,
		create("UIScale")({ Scale = hand.Scale }),
		Components.Slab({
			Kind = spec.Kind,
			Marks = true,
			Brackets = hand.Rise,
			GlowTransparency = function()
				return Lerp(0.6, Timing.HOVER_GLOW, hand.Light())
			end,
		}, {
			Name = "Face",
			Size = UDim2.fromScale(1, 1),
			caption(spec),
			Hand.WashLayer(hand, 3, 4),
			sheen(if spec.Light then Hand.Sheen(hand, spec.Light) else hand.Glint),
		}),
	}) :: TextButton
end

-- The header: SQUAD WIPED under its skull, and the countdown to the lobby at the other end.
local function header(state: Types.THudState, clock: TClock): { Instance }
	local results = state.Results
	local away = function(): number
		return 1 - Motion.Decelerate(clock.Since(Timing.TITLE_DELAY, Timing.TITLE))
	end
	local counted = function(): number
		return Motion.Out(clock.Since(Timing.RETURN_DELAY, Timing.RETURN))
	end
	-- 1 as a second ticks over, falling to 0.
	local tick = function(): number
		return Motion.Fade(results.Clock(), results.ReturnTickAt(), Timing.TICK)
	end

	return {
		Components.Picture(EIcons.Skull, {
			Name = "Skull",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(Layout.SKULL.X, Layout.SKULL.Y),
			Size = Components.PictureBox(Layout.SKULL_SIZE),
			ZIndex = 2,
			ImageTransparency = function()
				return 1 - Motion.Out(clock.Since(Timing.SKULL_DELAY, Timing.SKULL * 0.6))
			end,
			create("UIScale")({
				Scale = function()
					local down = Motion.Decelerate(clock.Since(Timing.SKULL_DELAY, Timing.SKULL))
					return 1 + Timing.SKULL_SCALE * (1 - down)
				end,
			}),
		}),
		create("Frame")({
			Name = "TitleWindow",
			Position = UDim2.fromOffset(Layout.TITLE.X, Layout.TITLE.Y),
			Size = UDim2.fromOffset(620, Layout.TITLE_SIZE),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = 2,
			label({
				Name = "Title",
				Position = function()
					return UDim2.fromOffset(-math.round(Timing.TITLE_SLIDE * away()), 0)
				end,
				Size = UDim2.fromScale(1, 1),
				TextSize = Layout.TITLE_SIZE,
				TextTransparency = away,
				Text = "SQUAD WIPED",
			}),
		}),
		label({
			Name = "Returning",
			Position = UDim2.fromOffset(Layout.RETURN.X, Layout.RETURN.Y),
			Size = UDim2.fromOffset(150, Layout.RETURN_SIZE),
			TextSize = Layout.RETURN_SIZE,
			TextColor3 = Palette.Lavender,
			TextTransparency = function()
				return 1 - counted()
			end,
			Text = "RETURNING IN",
		}),
		create("Frame")({
			Name = "Badge",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(Layout.BADGE.X + Layout.BADGE_SIZE / 2, Layout.BADGE.Y + Layout.BADGE_SIZE / 2),
			Size = UDim2.fromOffset(Layout.BADGE_SIZE, Layout.BADGE_SIZE),
			BackgroundColor3 = Colors.BADGE_EDGE,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			ZIndex = 2,
			BackgroundTransparency = function()
				return 1 - counted()
			end,
			create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
			create("UIScale")({
				Scale = function()
					if results.ReturnIn() > Timing.LAST_SECONDS then return 1 end
					local swell = tick()
					return 1 + Timing.LAST_SWELL * swell * swell
				end,
			}),
			create("Frame")({
				Name = "Face",
				Position = UDim2.fromOffset(1, 1),
				Size = UDim2.new(1, -2, 1, -2),
				BackgroundColor3 = Palette.Green,
				BorderSizePixel = 0,
				BackgroundTransparency = function()
					return 1 - counted()
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			}),
			label({
				Name = "Seconds",
				Position = function()
					return UDim2.fromOffset(0, -math.round(Timing.TICK_DROP * tick()))
				end,
				Size = UDim2.fromScale(1, 1),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextSize = Layout.BADGE_TEXT,
				TextColor3 = Palette.Ink,
				TextTransparency = function()
					return math.max(1 - counted(), 0.6 * tick())
				end,
				Text = function()
					return tostring(results.ReturnIn())
				end,
			}),
		}),
		create("Frame")({
			Name = "Bar",
			Position = UDim2.fromOffset(Layout.BAR.X, Layout.BAR.Y),
			Size = UDim2.fromOffset(Layout.BAR_SIZE.X, Layout.BAR_SIZE.Y),
			BackgroundColor3 = Palette.White,
			BorderSizePixel = 0,
			ZIndex = 2,
			BackgroundTransparency = function()
				return 1 - 0.12 * counted()
			end,
			create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			create("Frame")({
				Name = "Fill",
				Size = function()
					return UDim2.fromScale(results.ReturnShare(), 1)
				end,
				BackgroundColor3 = Palette.Green,
				BorderSizePixel = 0,
				BackgroundTransparency = function()
					-- Waiting on a purchase, the bar holds still and breathes.
					local held = if results.IsReturnHeld() then 0.35 + 0.25 * math.sin(results.Beat() * 5) else 0
					return math.max(1 - counted(), held)
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			}),
		}),
		create("Frame")({
			Name = "Rule",
			Position = UDim2.fromOffset(Layout.RULE.X, Layout.RULE.Y),
			Size = UDim2.fromOffset(Layout.RULE_SIZE.X, Layout.RULE_SIZE.Y),
			BackgroundColor3 = Colors.RULE,
			BorderSizePixel = 0,
			ZIndex = 2,
		}),
	}
end

-- One of the two stats under the wave: an ink plate edged in its colour, its picture, caption and number.
local function stat(spec: { [string]: any }): Frame
	return create("Frame")({
		Name = spec.Name,
		Position = UDim2.fromOffset(spec.At.X, spec.At.Y),
		Size = UDim2.fromOffset(Layout.STAT.X, Layout.STAT.Y),
		BackgroundTransparency = 1,
		ZIndex = 2,
		-- The card shows through his plate and, less, through its edge: a stroke, since an edge drawn as a frame
		-- behind the face would show through it too.
		create("Frame")({
			Name = "Face",
			Position = UDim2.fromOffset(2, 2),
			Size = UDim2.new(1, -4, 1, -4),
			BackgroundColor3 = Palette.Ink,
			BackgroundTransparency = Look.PLATE_FACE,
			BorderSizePixel = 0,
			create("UICorner")({ CornerRadius = UDim.new(0, 1) }),
			create("UIStroke")({
				Color = spec.Edge,
				Thickness = 1.5,
				Transparency = Look.PLATE_EDGE,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
		}),
		Components.Picture(spec.Icon, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(Layout.STAT_ICON.X, Layout.STAT_ICON.Y),
			Size = Components.PictureBox(Layout.STAT_ICON_SIZE),
			ZIndex = 2,
		}),
		label({
			Position = UDim2.fromOffset(Layout.STAT_LABEL.X, Layout.STAT_LABEL.Y),
			Size = UDim2.fromOffset(150, Layout.STAT_LABEL_SIZE),
			TextSize = Layout.STAT_LABEL_SIZE,
			TextColor3 = Palette.Lavender,
			Text = spec.Label,
		}),
		label({
			Position = UDim2.fromOffset(Layout.STAT_VALUE.X, Layout.STAT_VALUE.Y),
			Size = UDim2.fromOffset(160, Layout.STAT_VALUE_SIZE),
			TextSize = Layout.STAT_VALUE_SIZE,
			Text = spec.Value,
		}),
	})
end

-- NEW BEST: his gold tag, stamped on once the wave has landed, and the motes it throws.
local function newBest(state: Types.THudState, clock: TClock): Frame
	local results = state.Results
	local at = Timing.WAVE_COUNT_DELAY + Timing.WAVE_COUNT + Timing.BEST_DELAY
	local stamped = function(): number
		return Motion.Decelerate(clock.Since(at, Timing.BEST))
	end
	local there = function(): number
		return Motion.Out(clock.Since(at, Timing.BEST * 0.6))
	end
	local flash = function(): number
		if not results.IsOpen() then return 0 end
		local since = clock.Elapsed() - at - Timing.BEST * 0.5
		if since < 0 then return 0 end
		local left = math.clamp(1 - since / Timing.BEST_FLASH, 0, 1)
		return left * left
	end

	local motes = table.create(#MOTES)
	for index, mote in MOTES do
		-- 0 to 1 over the mote's life; nothing before it or after.
		local life = function(): number
			if not results.IsOpen() then return 1 end
			return Progress(clock.Elapsed(), at + Timing.MOTES_DELAY + mote.Delay, Timing.MOTES)
		end
		motes[index] = create("Frame")({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				local t = life()
				local out = mote.Reach * (1 - (1 - t) ^ 3)
				local where = mote.Start + mote.Direction * out
				return UDim2.fromOffset(math.round(where.X), math.round(where.Y + Timing.MOTES_FALL * t * t))
			end,
			Size = UDim2.fromOffset(mote.Size, mote.Size),
			BackgroundColor3 = if index % 3 == 0 then Palette.White else Palette.Gold,
			BorderSizePixel = 0,
			-- In at once, out slowly: it thins as it slows, and is gone before it stops.
			BackgroundTransparency = function()
				local t = life()
				if t <= 0 or t >= 1 then return 1 end
				return 1 - math.min(t / 0.08, 1) * (1 - t) ^ 1.5
			end,
		})
	end

	return create("Frame")({
		Name = "NewBest",
		Position = UDim2.fromOffset(Layout.BEST.X, Layout.BEST.Y),
		Size = UDim2.fromOffset(Layout.BEST_TAG.X, Layout.BEST_TAG.Y),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Visible = results.IsNewBest,
		create("Frame")({
			Name = "Motes",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			motes,
		}),
		create("Frame")({
			Name = "Tag",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BorderSizePixel = 0,
			BackgroundColor3 = function()
				return Palette.Gold:Lerp(Palette.White, flash())
			end,
			BackgroundTransparency = function()
				return 1 - there()
			end,
			create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			create("UIScale")({
				Scale = function()
					return 1 + Timing.BEST_SCALE * (1 - stamped())
				end,
			}),
			label({
				Size = UDim2.fromScale(1, 1),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextSize = Layout.BEST_TEXT,
				TextColor3 = Palette.Ink,
				TextTransparency = function()
					return 1 - there()
				end,
				Text = "NEW BEST",
			}),
		}),
	})
end

-- The picture of `avatar` (a copy of a character, which faces down its root's -Z), seen from a little to one side.
local function avatarPicture(avatar: Model): GunPicture.TPicture?
	local root = avatar:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then return nil end
	local frame = root.CFrame.Rotation
		* CFrame.Angles(0, math.pi - math.rad(Layout.AVATAR_YAW), 0)
		* CFrame.Angles(-math.rad(Layout.AVATAR_PITCH), 0, 0)
	return { Model = avatar, Origin = avatar:GetBoundingBox().Position, Barrel = frame.XVector, Up = frame.YVector }
end

local function waveCard(state: Types.THudState, clock: TClock): Frame
	local results = state.Results
	local landsAt = Timing.WAVE_COUNT_DELAY + Timing.WAVE_COUNT
	local counted = function(): number
		return Motion.Out(clock.Since(Timing.WAVE_COUNT_DELAY, Timing.WAVE_COUNT))
	end
	local stats = function(): number
		return Motion.Out(clock.Since(Timing.STATS_COUNT_DELAY, Timing.STATS_COUNT))
	end
	-- 1 as the count lands, falling to 0; nothing before it.
	local punch = function(): number
		if not results.IsOpen() then return 0 end
		local since = clock.Elapsed() - landsAt
		if since < 0 then return 0 end
		return math.clamp(1 - since / Timing.WAVE_PUNCH, 0, 1)
	end

	return Components.Card({
		Accent = Colors.WAVE,
		Tint = 0.56,
		Edge = 2,
		Tall = true,
		Face = Colors.WAVE_FACE,
		Marks = true,
		GlowTransparency = function()
			local lit = punch()
			return Lerp(0.7, 0.35, lit * lit)
		end,
	}, {
		Name = "Wave",
		Size = UDim2.fromScale(1, 1),
		cardBrackets(),
		label({
			Position = UDim2.fromOffset(Layout.WAVE_LABEL.X, Layout.WAVE_LABEL.Y),
			Size = UDim2.fromOffset(240, Layout.WAVE_LABEL_SIZE),
			TextSize = Layout.WAVE_LABEL_SIZE,
			TextColor3 = Palette.Pink,
			Text = "WAVE REACHED",
		}),
		label({
			Name = "Value",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(Layout.WAVE_VALUE.X, Layout.WAVE_VALUE.Y + Layout.WAVE_VALUE_SIZE / 2),
			Size = UDim2.fromOffset(330, Layout.WAVE_VALUE_SIZE),
			TextSize = Layout.WAVE_VALUE_SIZE,
			Text = function()
				return tostring(math.round(results.Wave() * counted()))
			end,
			create("UIScale")({
				Scale = function()
					local swell = punch()
					return 1 + Timing.WAVE_PUNCH_SCALE * swell * swell
				end,
			}),
		}),
		GunPicture.Build(function()
			local avatar = results.Avatar()
			return if avatar then avatarPicture(avatar) else nil
		end, {
			Transparency = function()
				return 1 - Motion.Out(clock.Since(Timing.AVATAR_DELAY, Timing.AVATAR * 0.6))
			end,
			Ambient = GunPicture.FLAT_AMBIENT,
			Light = GunPicture.FLAT_LIGHT,
		}, {
			Name = "Avatar",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(Layout.AVATAR.X, Layout.AVATAR.Y),
			Size = UDim2.fromOffset(Layout.AVATAR_SIZE, Layout.AVATAR_SIZE),
			ZIndex = 2,
			create("UIScale")({
				Scale = function()
					local arrived = Motion.Decelerate(clock.Since(Timing.AVATAR_DELAY, Timing.AVATAR))
					return 1 + Timing.AVATAR_SCALE * (1 - arrived)
				end,
			}),
		}),
		newBest(state, clock),
		stat({
			Name = "Kills",
			At = Layout.KILLS,
			Edge = Colors.KILLS_EDGE,
			Icon = EIcons.Skull,
			Label = "SQUAD KILLS",
			Value = function()
				return Components.Commas(math.round(results.SquadKills() * stats()))
			end,
		}),
		stat({
			Name = "Time",
			At = Layout.TIME,
			Edge = Colors.TIME_EDGE,
			Icon = EIcons.Stopwatch,
			Label = "TIME SURVIVED",
			Value = function()
				local seconds = math.round(results.Seconds() * stats())
				return `{seconds // 60}:{string.format("%02d", seconds % 60)}`
			end,
		}),
		sheen(function()
			return clock.Since(landsAt, Timing.WAVE_SHEEN)
		end),
	})
end

-- What the two batches of flying Gems have done so far. The first carries the run's Gems into the total; the second,
-- a bought doubling into the run's Gems and the total with them.
type TGems = {
	-- How many fly in each batch, and seconds into each.
	Count: () -> number,
	FirstAt: () -> number,
	SecondAt: () -> number,
	Earned: () -> number,
	Total: () -> number,
	-- How hard the Gems are landing in the total and in the earned amount, and 1 falling to 0 from the last landing.
	TotalRate: () -> number,
	EarnedRate: () -> number,
	TotalFlash: () -> number,
	EarnedFlash: () -> number,
}

local function gemsMaths(state: Types.THudState, clock: TClock): TGems
	local results = state.Results
	local count = function(): number
		return math.min(results.Gems(), #FLIGHTS)
	end
	local firstAt = function(): number
		return if results.IsOpen() then clock.Elapsed() - Timing.GEMS_FLY_DELAY else math.huge
	end
	local secondAt = function(): number
		return if results.Doubled() > 0 then results.Clock() - results.DoubledAt() else -math.huge
	end
	local first = derive(function()
		local share, rate = landed(firstAt(), count())
		return { Share = share, Rate = rate }
	end)
	local second = derive(function()
		local share, rate = landed(secondAt(), count())
		return { Share = share, Rate = rate }
	end)
	-- 1 falling to 0 from the last landing of the batch `at` seconds in.
	local function flash(at: () -> number): () -> number
		return function(): number
			local flying = count()
			if flying == 0 then return 0 end
			local since = at() - LAST_LANDING[flying]
			if since < 0 then return 0 end
			local left = math.clamp(1 - since / Timing.LAND_FLASH, 0, 1)
			return left * left
		end
	end

	local firstFlash = flash(firstAt)
	local secondFlash = flash(secondAt)

	return {
		Count = count,
		FirstAt = firstAt,
		SecondAt = secondAt,
		Earned = function(): number
			local counted = Motion.Out(clock.Since(Timing.GEMS_COUNT_DELAY, Timing.GEMS_COUNT))
			return math.round(results.Gems() * counted + results.Doubled() * second().Share)
		end,
		Total = function(): number
			local waiting = results.Gems() * (1 - first().Share)
			return math.round(results.TotalGems() - waiting + results.Doubled() * second().Share)
		end,
		TotalRate = function(): number
			return first().Rate + second().Rate
		end,
		EarnedRate = function(): number
			return second().Rate
		end,
		TotalFlash = function(): number
			return math.max(firstFlash(), secondFlash())
		end,
		EarnedFlash = secondFlash,
	}
end

local function gemsCard(clock: TClock, gems: TGems): Frame
	return Components.Card({ Accent = Colors.GEMS, Tint = 0.5, Edge = 2, Wide = true, Marks = true }, {
		Name = "Gems",
		Size = UDim2.fromScale(1, 1),
		cardBrackets(),
		label({
			Position = UDim2.fromOffset(Layout.GEMS_LABEL.X, Layout.GEMS_LABEL.Y),
			Size = UDim2.fromOffset(240, Layout.GEMS_LABEL_SIZE),
			TextSize = Layout.GEMS_LABEL_SIZE,
			TextColor3 = Colors.GEM,
			Text = "GEMS EARNED",
		}),
		Components.Picture(EIcons.Gem, {
			Name = "Gem",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(Layout.GEM.X, Layout.GEM.Y),
			Size = Components.PictureBox(Layout.GEM_SIZE),
			ZIndex = 2,
			create("UIScale")({
				Scale = function()
					return 1 + Timing.LAND_SWELL * math.min(gems.EarnedRate(), 3)
				end,
			}),
		}),
		label({
			Name = "Value",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(Layout.GEMS_VALUE.X, Layout.GEMS_VALUE.Y + Layout.GEMS_VALUE_SIZE / 2),
			Size = UDim2.fromOffset(330, Layout.GEMS_VALUE_SIZE),
			TextSize = Layout.GEMS_VALUE_SIZE,
			TextColor3 = function()
				return Palette.White:Lerp(Colors.GEM, 0.6 * gems.EarnedFlash())
			end,
			Text = function()
				return compact(gems.Earned())
			end,
			create("UIScale")({
				Scale = function()
					return 1 + Timing.LAND_SWELL * math.min(gems.EarnedRate(), 3)
				end,
			}),
		}),
		label({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromOffset(Layout.TOTAL_RIGHT, Layout.TOTAL_LABEL_Y),
			Size = UDim2.fromOffset(120, Layout.TOTAL_LABEL_SIZE),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextSize = Layout.TOTAL_LABEL_SIZE,
			TextColor3 = Palette.Lavender,
			Text = "TOTAL",
		}),
		label({
			Name = "Total",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromOffset(Layout.TOTAL_RIGHT, Layout.TOTAL_VALUE_Y + Layout.TOTAL_VALUE_SIZE / 2),
			Size = UDim2.fromOffset(240, Layout.TOTAL_VALUE_SIZE),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextSize = Layout.TOTAL_VALUE_SIZE,
			TextColor3 = function()
				return Palette.White:Lerp(Colors.GEM, 0.8 * gems.TotalFlash())
			end,
			Text = function()
				return Components.Commas(gems.Total())
			end,
			create("UIScale")({
				Scale = function()
					return 1 + Timing.LAND_SWELL * math.min(gems.TotalRate(), 3)
				end,
			}),
		}),
		sheen(function()
			return clock.Since(Timing.GEMS_DELAY + Timing.GEMS_SHEEN_DELAY, Timing.WAVE_SHEEN)
		end),
	})
end

local function doubleCard(state: Types.THudState, actions: Types.TActions): Frame
	local results = state.Results
	local isOffered = function(): boolean
		return results.DoubleRobux() > 0
	end
	local isDone = function(): boolean
		return results.Doubled() > 0
	end
	-- 1 as the doubling arrives, falling to 0.
	local flash = function(): number
		if not isDone() then return 0 end
		local left = Motion.Fade(results.Clock(), results.DoubledAt(), Timing.DOUBLED_FLASH)
		return left * left
	end

	return Components.Card({
		Accent = Colors.DOUBLE,
		Tint = 0.55,
		Edge = 2,
		Wide = true,
		Marks = true,
		GlowTransparency = function()
			return Lerp(0.7, 0.3, flash())
		end,
	}, {
		Name = "Double",
		Size = UDim2.fromScale(1, 1),
		cardBrackets(),
		create("Frame")({
			Name = "Bonus",
			Position = UDim2.fromOffset(Layout.BONUS.X, Layout.BONUS.Y),
			Size = UDim2.fromOffset(Layout.BONUS_TAG.X, Layout.BONUS_TAG.Y),
			BackgroundColor3 = Colors.BONUS,
			BorderSizePixel = 0,
			ZIndex = 2,
			create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			label({
				Size = UDim2.fromScale(1, 1),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextSize = Layout.BONUS_TEXT,
				Text = "BONUS",
			}),
		}),
		label({
			Position = UDim2.fromOffset(Layout.DOUBLE_LABEL.X, Layout.DOUBLE_LABEL.Y),
			Size = UDim2.fromOffset(380, Layout.DOUBLE_LABEL_SIZE),
			TextSize = Layout.DOUBLE_LABEL_SIZE,
			Text = function()
				return if isDone() then "GEMS DOUBLED" else "DOUBLE YOUR GEMS"
			end,
		}),
		create("Frame")({
			Name = "Doubled",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromOffset(Layout.DOUBLE_RIGHT, Layout.DOUBLE_VALUE_Y),
			Size = UDim2.fromOffset(300, Layout.DOUBLE_VALUE_SIZE),
			BackgroundTransparency = 1,
			ZIndex = 2,
			create("UIListLayout")({
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, Layout.DOUBLE_GEM_GAP),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Components.Picture(EIcons.Gem, {
				LayoutOrder = 1,
				Size = Components.PictureBox(Layout.DOUBLE_GEM_SIZE),
			}),
			label({
				LayoutOrder = 2,
				Size = UDim2.fromOffset(0, Layout.DOUBLE_VALUE_SIZE),
				AutomaticSize = Enum.AutomaticSize.X,
				TextSize = Layout.DOUBLE_VALUE_SIZE,
				Text = function()
					return compact(if isDone() then results.Gems() + results.Doubled() else results.Gems() * 2)
				end,
			}),
		}),
		slabButton({
			Name = "Robux",
			-- Alone in the middle of the card until there is an ad to stand beside.
			At = function()
				return if results.CanWatchAd() then Layout.ROBUX else Layout.ROBUX_ALONE
			end,
			Size = Layout.OFFER,
			Kind = function()
				return if isOffered() then "Violet" else "Off"
			end,
			Glyph = "Robux",
			IconSize = 24,
			IsIconShown = isOffered,
			Text = function()
				if isDone() then return "DOUBLED" end
				return if isOffered() then tostring(results.DoubleRobux()) else "NO GEMS YET"
			end,
			TextSize = 26,
			Gap = 16,
			Activated = actions.DoubleGems,
			IsLive = isOffered,
			Light = function()
				if not isOffered() then return 1 end
				return math.clamp((results.Beat() % Timing.ASK_EVERY) / Timing.ASK_SHEEN, 0, 1)
			end,
		}),
		slabButton({
			Name = "Advert",
			At = Layout.ADVERT,
			Size = Layout.OFFER,
			-- There only while an ad can be shown for the doubling.
			IsShown = results.CanWatchAd,
			Kind = "Steel",
			Icon = EIcons.Advert,
			IconSize = 21,
			Text = "WATCH AD",
			TextSize = 23,
			Gap = 14,
			Activated = actions.WatchAd,
			IsLive = results.CanWatchAd,
		}),
		create("Frame")({
			Name = "Flash",
			Position = UDim2.fromOffset(2, 2),
			Size = UDim2.new(1, -4, 1, -4),
			BackgroundColor3 = Palette.White,
			BorderSizePixel = 0,
			ZIndex = 5,
			Interactable = false,
			BackgroundTransparency = function()
				return 1 - 0.55 * flash()
			end,
			create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
		}),
	})
end

-- LOBBY: his dark panel. Under the hand it swells as the slabs do and its edge lights.
local function lobbyButton(actions: Types.TActions): TextButton
	local isHovered = source(false)
	local isPressed = source(false)
	local hover = Hand.Spring(function()
		return if isHovered() then 1 else 0
	end, 0.2, 0.9)
	local scale = spring(function()
		return if isPressed() then Timing.PRESS_SCALE elseif isHovered() then Timing.HOVER_SCALE else 1
	end, 0.16, 0.9)

	return Components.Button({
		Name = "Lobby",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Activated = actions.LeaveToLobby,
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
		create("UIScale")({ Scale = scale }),
		Components.Panel({
			Brackets = true,
			Stroke = function()
				return Palette.EdgePink:Lerp(Palette.Pink, 0.7 * hover())
			end,
		}, {
			Name = "Face",
			Size = UDim2.fromScale(1, 1),
			caption({
				Icon = EIcons.Arrow,
				IconSize = 17,
				Text = "LOBBY",
				TextSize = 25,
				Gap = 18,
			}),
		}),
	}) :: TextButton
end

-- The PLAY AGAIN count: his dark plate. The number swells as it changes.
local function votes(state: Types.THudState): Frame
	local results = state.Results
	return Components.Panel({ Brackets = true }, {
		Name = "Votes",
		Size = UDim2.fromScale(1, 1),
		label({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, Layout.VOTES_VALUE_Y + Layout.VOTES_VALUE_SIZE / 2),
			Size = UDim2.new(1, 0, 0, Layout.VOTES_VALUE_SIZE),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextSize = Layout.VOTES_VALUE_SIZE,
			Text = function()
				return `{results.Votes()}/{results.VotesNeeded()}`
			end,
			create("UIScale")({
				Scale = function()
					local swell = Motion.Fade(results.Clock(), results.VotesAt(), Timing.VOTE)
					return 1 + Timing.VOTE_SCALE * swell * swell
				end,
			}),
		}),
		label({
			Position = UDim2.fromOffset(0, Layout.VOTES_LABEL_Y),
			Size = UDim2.new(1, 0, 0, Layout.VOTES_LABEL_SIZE),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextSize = Layout.VOTES_LABEL_SIZE,
			TextColor3 = Palette.Lavender,
			Text = "VOTED",
		}),
	})
end

-- The Gems in flight, over everything else on the panel.
local function flights(gems: TGems): Frame
	local sprites = table.create(#FLIGHTS * 2)
	local function batch(at: () -> number, from: Vector2, to: Vector2)
		for index, flight in FLIGHTS do
			local where = derive(function()
				if index > gems.Count() then return { At = from, There = 0 } end
				local point, there = flightAt(flight, at(), from, to)
				return { At = point, There = there }
			end)
			table.insert(
				sprites,
				Components.Picture(EIcons.Gem, {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = function()
						local point = where().At
						return UDim2.fromOffset(math.round(point.X), math.round(point.Y))
					end,
					-- It grows in as it leaves and shrinks into what it lands in, so neither end is a pop.
					Size = function()
						local side = math.round(flight.Size * (0.5 + 0.5 * where().There))
						return UDim2.fromOffset(side, side)
					end,
					ImageTransparency = function()
						return 1 - where().There
					end,
					Visible = function()
						return where().There > 0
					end,
				})
			)
		end
	end

	batch(gems.FirstAt, Layout.GEM_AT, Layout.TOTAL_AT)
	batch(gems.SecondAt, Layout.DOUBLE_GEM_AT, Layout.GEM_AT)
	return create("Frame")({
		Name = "Flights",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Interactable = false,
		sprites,
	})
end

function Results.Build(state: Types.THudState, actions: Types.TActions): Frame
	local results = state.Results
	local elapsed = derive(function(): number
		return results.Clock() - results.ToggledAt()
	end)
	local shown = function(): number
		if results.IsOpen() then return Motion.Out(Progress(elapsed(), 0, Timing.FADE)) end
		return 1 - Progress(elapsed(), 0, Timing.CLOSE)
	end
	local clock: TClock = {
		Elapsed = elapsed,
		Shown = shown,
		Since = function(delay: number, seconds: number): number
			if not results.IsOpen() then return 1 end
			return Progress(elapsed(), delay, seconds)
		end,
	}
	-- How far under its place the panel is, in px.
	local drop = function(): number
		if results.IsOpen() then return Timing.RISE * (1 - Motion.Decelerate(Progress(elapsed(), 0, Timing.OPEN))) end
		return Timing.SINK * Motion.Accelerate(Progress(elapsed(), 0, Timing.CLOSE))
	end
	local gems = gemsMaths(state, clock)
	local hasVoted = results.HasVoted

	return create("Frame")({
		Name = "Results",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 10,
		Visible = function()
			return shown() > 0.001
		end,
		-- A button, so a press on the dim stops here instead of reaching the HUD under it.
		create("TextButton")({
			Name = "Dim",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(),
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			BackgroundTransparency = function()
				return 1 - Timing.DIM * shown()
			end,
		}),
		create("Frame")({
			Name = "Window",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				return UDim2.new(0.5, Layout.CENTER_X, Layout.CENTER_Y, math.round(drop()))
			end,
			Size = UDim2.fromOffset(Layout.SIZE.X, Layout.SIZE.Y),
			BackgroundTransparency = 1,
			ZIndex = 2,
			create("CanvasGroup")({
				Name = "Chrome",
				Position = UDim2.fromOffset(-Layout.MARGIN, -Layout.MARGIN),
				Size = UDim2.new(1, Layout.MARGIN * 2, 1, Layout.MARGIN * 2),
				BackgroundTransparency = 1,
				GroupTransparency = function()
					return 1 - shown()
				end,
				-- Longer than the streak texture: its window starts at the corner and it is tiled across.
				Components.Panel({ Brackets = true, TexturePhase = Vector2.zero, Wide = true, Tall = true }, {
					Name = "Panel",
					Position = UDim2.fromOffset(Layout.MARGIN, Layout.MARGIN),
					Size = UDim2.new(1, -Layout.MARGIN * 2, 1, -Layout.MARGIN * 2),
					header(state, clock),
				}),
			}),
			dealt(state, clock, "WaveCard", Layout.WAVE, Layout.WAVE_CARD, Timing.WAVE_DELAY, waveCard(state, clock)),
			dealt(state, clock, "GemsCard", Layout.GEMS, Layout.GEMS_CARD, Timing.GEMS_DELAY, gemsCard(clock, gems)),
			dealt(
				state,
				clock,
				"DoubleCard",
				Layout.DOUBLE,
				Layout.DOUBLE_CARD,
				Timing.DOUBLE_DELAY,
				doubleCard(state, actions)
			),
			dealt(
				state,
				clock,
				"LobbyButton",
				Layout.LOBBY,
				Layout.LOBBY_SIZE,
				Timing.LOBBY_DELAY,
				lobbyButton(actions)
			),
			dealt(
				state,
				clock,
				"AgainButton",
				Layout.AGAIN,
				Layout.AGAIN_SIZE,
				Timing.AGAIN_DELAY,
				slabButton({
					Name = "PlayAgain",
					At = Vector2.zero,
					Size = Layout.AGAIN_SIZE,
					Kind = function()
						return if hasVoted() then "Off" else "Go"
					end,
					Icon = EIcons.Replay,
					IconSize = 25,
					Text = "PLAY AGAIN",
					TextSize = 29,
					Gap = 19,
					Activated = actions.PlayAgain,
					IsLive = function()
						return not hasVoted()
					end,
				})
			),
			dealt(state, clock, "VotesPlate", Layout.VOTES, Layout.VOTES_SIZE, Timing.VOTES_DELAY, votes(state)),
			dealt(
				state,
				clock,
				"ReviveButton",
				Layout.REVIVE,
				Layout.REVIVE_SIZE,
				Timing.REVIVE_DELAY,
				slabButton({
					Name = "Revive",
					At = Vector2.zero,
					Size = Layout.REVIVE_SIZE,
					Kind = function()
						return if results.CanRevive() then "Pink" else "Off"
					end,
					Icon = EIcons.Revive,
					IconSize = 31,
					IconChild = create("UIScale")({
						Scale = function()
							return 1 + Timing.BEAT_SCALE * heartbeat(results.Beat())
						end,
					}),
					Text = "REVIVE",
					TextSize = 31,
					Gap = 16,
					Activated = actions.Revive,
					IsLive = results.CanRevive,
					-- Half a cycle after the doubling's light, so the two ask in turn.
					Light = function()
						if not results.CanRevive() then return 1 end
						local into = (results.Beat() + Timing.ASK_EVERY / 2) % Timing.ASK_EVERY
						return math.clamp(into / Timing.ASK_SHEEN, 0, 1)
					end,
				})
			),
			dealt(
				state,
				clock,
				"UpgradesTag",
				Layout.UPGRADES,
				Layout.UPGRADES_TAG,
				Timing.UPGRADES_DELAY,
				create("Frame")({
					Name = "Upgrades",
					Size = UDim2.fromScale(1, 1),
					BackgroundColor3 = Palette.Gold,
					BorderSizePixel = 0,
					create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
					label({
						Position = UDim2.fromOffset(14, 0),
						Size = UDim2.new(1, -14, 1, 0),
						TextSize = Layout.UPGRADES_TEXT,
						TextColor3 = Palette.Ink,
						Text = "UPGRADES AVAILABLE",
					}),
				})
			),
			flights(gems),
		}),
	})
end

return Results
