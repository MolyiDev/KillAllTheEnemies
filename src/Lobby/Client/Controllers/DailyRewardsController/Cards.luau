--!nonstrict
-- The week's seven day cards (UIMatt.md, Daily Rewards): six of Gems in his grid and the big day 7 card on the right,
-- each claimed (his CLAIMED stamp over a dimmed gem), today's (green, ringed in white, CLAIM NOW) or still to come.
--
-- A claim plays on today's card in beats: it winds up while the server is asked (squeezed in, the gem rattling), lets
-- go on the answer (a flash of its own shape, one ring, the gem bursting into the Gems that fly to the pill, GemPayout),
-- then the stamp slams down and the card settles into claimed: the colour drains back to the day's own, the ring goes,
-- CLAIM NOW turns back into GEMS. A gun day spins its gun round instead of bursting.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local GunPicture = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.GunPicture)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local DailyRewardsCore = require(ReplicatedStorage.Shared.Core.DailyRewardsCore)
local WeaponParts = require(script.Parent.Parent.WeaponsController.Parts)
local Parts = require(script.Parent.Parts)
local Types = require(script.Parent.Types)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Progress = Motion.Progress
local Label = Parts.Label
local WEEK = DailyRewardsCore.WEEK

-- His drawn rects in px at 1080: the cards' corners on the screen, then each piece from its card's top left.
local Layout = table.freeze({
	CARD = Vector2.new(256, 250),
	CARD_XS = { 349, 623, 897 },
	CARD_YS = { 300, 568 },
	PRIZE = Vector2.new(1171, 300),
	PRIZE_SIZE = Vector2.new(400, 518),
	-- The room round a card inside the group that fades it, for its glow, brackets and pop (a CanvasGroup clips).
	MARGIN = 34,
	BAND = 43,
	PRIZE_BAND = 52,
	BRACKETS = 6,
	BRACKET_LENGTH = 20,
	RING = 6,
	DAY_TOP = 14,
	DAY_TEXT = 24,
	PRIZE_DAY_TEXT = 31,
	GEM = Vector2.new(128, 106.5),
	GEM_GLYPH = 77,
	VALUE_TOP = 156,
	VALUE_TEXT = 39,
	-- Both tags are centred on this line: his GEMS tag 204 down and 26 tall, his CLAIM NOW 202 and 30.
	TAG_MIDDLE = 217,
	STAMP = Vector2.new(129.5, 120.5),
	STAMP_SIZE = Vector2.new(154, 43),
	STAMP_TURN = -8,
	STAMP_TEXT = 29,
	STAMP_CHECK = 22,
	-- The day 7 card: the disc and the gun on it, the PERMANENT tag, the name and the rarity tag under it, the stamp.
	DISC = Vector2.new(200, 270),
	DISC_RADIUS = 150,
	DISC_LINE = 2,
	GUN_BOX = 280,
	GUN_LEAN = 38,
	PRIZE_GEM_GLYPH = 150,
	PERMANENT = Vector2.new(198, 108),
	PERMANENT_SIZE = Vector2.new(174, 43),
	PERMANENT_TURN = 4,
	PERMANENT_TEXT = 27,
	NAME_TOP = 380,
	NAME_SIZE = Vector2.new(340, 88),
	RARITY_TOP = 468,
	RARITY_HEIGHT = 32,
	RARITY_TEXT = 16,
	RARITY_PAD = 14,
	PRIZE_TAG_MIDDLE = 484,
	PRIZE_STAMP = Vector2.new(200, 300),
	PRIZE_STAMP_SCALE = 1.35,
})

-- The day's own colour (his: the small days gold, the big two pink, the gun violet), by its place in the week.
local ACCENTS = table.freeze({
	Palette.Gold,
	Palette.Gold,
	Palette.Gold,
	Palette.Gold,
	Palette.Pink,
	Palette.Pink,
	Palette.Violet,
})
-- His claimed gem: the glyph, dimmed into the face.
local CLAIMED_GEM = 0.72
local CLAIMED_VALUE = 0.7
local DISC_FILL = 0.9
local DISC_LINE = 0.45

local Timing = table.freeze({
	-- The cards are dealt in reading order, the gun last; each rises, the light crosses it as it lands and its number
	-- runs up.
	DEAL_DELAY = 0.18,
	DEAL_STAGGER = 0.045,
	DEAL_RISE = 34,
	SHEEN_DELAY = 0.26,
	SHEEN = 0.6,
	COUNT_DELAY = 0.14,
	COUNT = 0.55,
	-- A week switched: each card leaves the way the week went and the new one comes in from the other side.
	WEEK = 0.4,
	WEEK_STAGGER = 0.035,
	WEEK_SLIDE = 70,
	-- The claim, from the moment it lets go (the controller's ClaimedAt). The wind-up squeezes the card this much.
	WIND_UP = 0.14,
	SQUASH = 0.05,
	RELEASE = 0.1,
	POP = 0.12,
	-- Day 7 is the week's big one, so its thump is harder.
	PRIZE_POP = 0.17,
	POP_SECONDS = 0.5,
	FLASH = 0.24,
	-- In px each side, not a share: on day 7's big card a share runs out past the panel.
	FLASH_GROW = 36,
	FLASH_PEAK = 0.7,
	RING = 0.5,
	RING_REACH = 70,
	RING_LINE = 3,
	BURST = 0.14,
	BURST_GROW = 0.6,
	RATTLE = 2,
	STAMP_DELAY = 0.3,
	STAMP = 0.14,
	STAMP_FROM = 1.9,
	STAMP_SPIN = 12,
	SETTLE = 0.32,
	JOLT = 6,
	JOLT_SECONDS = 0.18,
	GUN_SPIN = 1,
	REFUSE = 0.42,
	REFUSE_SHAKE = 10,
	-- Today's card calls while it waits, in light only (nothing on a control moves at rest): its glow is lit, and the
	-- light crosses it each time the controller calls (CallAt).
	CALL_GLOW = 0.28,
	CALL_SHEEN = 0.65,
	-- Today's card pings once it is in place (the screen opening, or midnight while it is up): a light flash, a small
	-- thump and a green ring.
	PING_POP = 0.04,
	PING_POP_SECONDS = 0.25,
	PING_FLASH = 0.22,
	PING_FLASH_PEAK = 0.35,
	PING_RING = 0.45,
	PING_REACH = 40,
	-- Tomorrow's card winks once a claim has settled (after the week has turned, when the claim ended one): the light
	-- crosses it and it nods.
	WINK_DELAY = 0.9,
	WINK_AFTER_TURN = 0.75,
	WINK = 0.6,
	WINK_POP = 0.03,
	GLOW = 0.7,
	GLOW_LIT = 0.35,
	HOVER_BRACKETS = 3,
})

local Cards = {}

-- The controller times these: the least the wind-up shows, however fast the answer comes (a release with no wind-up
-- is a pop), and how long a call's light takes to cross today's card.
Cards.WIND_UP_SECONDS = Timing.WIND_UP
Cards.CALL_SECONDS = Timing.CALL_SHEEN
-- When a claim's stamp lands, from its let-go: what the controller times the stamp's sound on.
Cards.IMPACT_SECONDS = Timing.STAMP_DELAY + Timing.STAMP
-- How long every beat of a claim takes, so the controller keeps the clock ticking for it.
Cards.CLAIM_SECONDS = Timing.STAMP_DELAY + Timing.STAMP + Timing.SETTLE + Timing.GUN_SPIN
-- When a week's last day claimed turns the screen to the next week, from its let-go: once the card has settled.
Cards.TURN_SECONDS = Timing.STAMP_DELAY + Timing.STAMP + Timing.SETTLE + 0.5

local function lerp2(a: Vector2, b: Vector2, t: number): Vector2
	return a + (b - a) * t
end

-- His CLAIMED stamp: a green slip turned a little, a tick and the word in ink.
local function stamp(props: { [any]: any }): Frame
	return create("Frame")({
		Name = "Stamp",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(Layout.STAMP_SIZE.X, Layout.STAMP_SIZE.Y),
		BackgroundColor3 = Palette.Green,
		BorderSizePixel = 0,
		ZIndex = 8,
		create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
		create("Frame")({
			Name = "Words",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			create("UIListLayout")({
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 5),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Components.Icon("Check", {
				LayoutOrder = 1,
				Size = Components.GlyphBox(Layout.STAMP_CHECK),
				ImageColor3 = Palette.Ink,
			}),
			Label({
				LayoutOrder = 2,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, Layout.STAMP_TEXT),
				TextSize = Layout.STAMP_TEXT,
				TextColor3 = Palette.Ink,
				Text = "CLAIMED",
			}),
		}),
		props,
	})
end

-- ============================== A card's state ==============================

-- What one card shows and where each of its gestures stands, as sources. Every builder below reads from this.
type TCard = {
	Slot: number,
	IsPrize: boolean,
	Size: Vector2,
	Corner: Vector2,
	DealDelay: number,
	Hand: Hand.TReaction,
	-- The day it shows (the old week's until the card is out of sight in a week switch), and that day's reward.
	Day: () -> number,
	Reward: () -> DailyRewardsCore.TReward,
	-- "Claimed", "Claimable" or "Future".
	Status: () -> string,
	IsClaimable: () -> boolean,
	-- The claim being shown is this card's; today's card waiting, untouched.
	IsOwnClaim: () -> boolean,
	IsCalling: () -> boolean,
	-- 0 to 1 of a beat `delay` after the claim let go, `seconds` long: 1 on every card but the one claiming.
	ClaimShare: (delay: number, seconds: number) -> number,
	SinceRelease: () -> number,
	Charge: () -> number,
	-- 0 to 1 as the card settles into claimed after its stamp; 1 for any card claimed before.
	Settled: () -> number,
	-- How green it is (today's, until its stamp has landed), and its colour then.
	Greenness: () -> number,
	Accent: () -> Color3,
	-- 0: CLAIM NOW, 1: his GEMS tag.
	ToGems: () -> number,
	-- 0 to 1 of today's ping, `seconds` long.
	Pinged: (seconds: number) -> number,
	-- Day 7: the gun on offer (nil when it pays Gems instead), and whether it pays Gems.
	Gun: () -> any,
	IsGemsPrize: () -> boolean,
	Offset: () -> Vector2,
	Fade: () -> number,
	Scale: () -> number,
	Sheen: () -> number,
	Counted: () -> number,
}

local function cardState(state: Types.TDailyState, elapsed: () -> number, shown: () -> number, slot: number): TCard
	local isPrize = slot == WEEK
	local dealDelay = Timing.DEAL_DELAY + Timing.DEAL_STAGGER * (slot - 1)
	local restAccent = ACCENTS[slot]

	local switched = derive(function(): number
		return Progress(state.Now(), state.WeekAt(), Timing.WEEK, Timing.WEEK_STAGGER * (slot - 1))
	end)
	local day = derive(function(): number
		local week = if switched() < 0.5 then state.WeekFrom() else state.Week()
		return (week - 1) * WEEK + slot
	end)
	local status = derive(function(): string
		local current, shownDay = state.Day(), day()
		if shownDay < current then return "Claimed" end
		if shownDay > current then return "Future" end
		return if state.IsClaimable() then "Claimable" else "Claimed"
	end)
	local isClaimable = derive(function(): boolean
		return status() == "Claimable"
	end)
	local isOwnClaim = derive(function(): boolean
		return state.ClaimedDay() == day() and status() == "Claimed"
	end)
	-- Held at the claim's end, so the clock ticking for a later gesture works none of it out again.
	local sinceRelease = derive(function(): number
		if not isOwnClaim() then return math.huge end
		return math.min(state.Now() - state.ClaimedAt(), Cards.CLAIM_SECONDS)
	end)
	local function claimShare(delay: number, seconds: number): number
		return math.clamp((sinceRelease() - delay) / seconds, 0, 1)
	end

	-- The wind-up while the server is asked, held until the reward lets go.
	local charge = derive(function(): number
		local isWinding = (isClaimable() and state.IsPending()) or (isOwnClaim() and sinceRelease() < 0)
		if not isWinding then return 0 end
		return Motion.Out(Progress(state.Now(), state.PressedAt(), Timing.WIND_UP))
	end)
	local settled = derive(function(): number
		if status() ~= "Claimed" then return 0 end
		return Motion.Out(claimShare(Cards.IMPACT_SECONDS, Timing.SETTLE))
	end)
	local greenness = derive(function(): number
		if isClaimable() then return 1 end
		if isOwnClaim() then return 1 - settled() end
		return 0
	end)
	local toGems = derive(function(): number
		if isClaimable() then return 0 end
		if isOwnClaim() then return settled() end
		return 1
	end)

	-- Today's ping, once its card is in place: only today's card reads the clock for it, and only until it is over.
	local sincePing = derive(function(): number
		if not isClaimable() then return math.huge end
		local at = math.max(state.ReadyAt(), state.ToggledAt() + dealDelay + Parts.Timing.SLIDE)
		return math.min(state.Now() - at, Timing.PING_RING)
	end)
	local function pinged(seconds: number): number
		return math.clamp(sincePing() / seconds, 0, 1)
	end
	-- Tomorrow's wink, once a claim has settled (after the week has turned, when the claim ended one).
	local wink = derive(function(): number
		local claimed = state.ClaimedDay()
		if claimed == 0 or day() ~= claimed + 1 or status() ~= "Future" then return 1 end
		local delay = if claimed % WEEK == 0 then Cards.TURN_SECONDS + Timing.WINK_AFTER_TURN else Timing.WINK_DELAY
		return Progress(state.Now(), state.ClaimedAt() + delay, Timing.WINK)
	end)

	local squash = derive(function(): number
		local wound = charge()
		if wound > 0 then return Timing.SQUASH * wound end
		return Timing.SQUASH * (1 - Motion.Out(claimShare(0, Timing.RELEASE)))
	end)
	local pop = derive(function(): number
		local thump = if isPrize then Timing.PRIZE_POP else Timing.POP
		return thump * Motion.Swing(claimShare(0, Timing.POP_SECONDS))
			+ Timing.PING_POP * Motion.Bump(pinged(Timing.PING_POP_SECONDS))
			+ Timing.WINK_POP * Motion.Bump(wink())
	end)
	local hand = Hand.React("Take", isClaimable)

	-- The entrance, the week switch, a refusal and the stamp's jolt, as one offset.
	local away = Parts.Away(state, elapsed, dealDelay)
	local offset = derive(function(): Vector2
		local x, y = 0, Timing.DEAL_RISE * away()
		local w = switched()
		if w > 0 and w < 1 then
			local direction = if state.Week() > state.WeekFrom() then 1 else -1
			x -= if w < 0.5
				then direction * Timing.WEEK_SLIDE * Motion.Accelerate(w * 2)
				else -direction * Timing.WEEK_SLIDE * (1 - Motion.Decelerate(w * 2 - 1))
		end
		if state.Refused() == day() then
			local at = state.RefusedAt()
			x += Timing.REFUSE_SHAKE * Motion.Shake(Progress(state.Now(), at, Timing.REFUSE), at)
		end
		y += Timing.JOLT * Motion.Bump(claimShare(Cards.IMPACT_SECONDS, Timing.JOLT_SECONDS))
		return Vector2.new(math.round(x), math.round(y))
	end)
	local fade = derive(function(): number
		if not state.IsOpen() then return 1 - shown() end
		local dealt = 1 - Motion.Out(Progress(elapsed(), dealDelay, Parts.Timing.PIECE_FADE))
		local w = switched()
		local switching = if w > 0 and w < 1 then 1 - math.abs(2 * w - 1) else 0
		return math.max(dealt, switching)
	end)

	local isCalling = derive(function(): boolean
		return isClaimable() and not state.IsPending()
	end)
	local landed = Parts.Since(state, elapsed, dealDelay + Timing.SHEEN_DELAY, Timing.SHEEN)
	-- The light crossing it: as it is dealt in, as tomorrow's wink, and each time today's card is called.
	local sheen = Hand.Sheen(hand, function(): number
		local light = landed()
		if light < 1 then return light end
		local winked = wink()
		if winked > 0 and winked < 1 then return winked end
		if not isCalling() then return 1 end
		return Progress(state.Now(), state.CallAt(), Timing.CALL_SHEEN)
	end)

	local isGemsPrize = derive(function(): boolean
		if not isPrize then return false end
		if isOwnClaim() then return state.ClaimedGun() == 0 end
		return status() ~= "Claimed" and state.OwnedPrizes()[day()] == true
	end)

	return {
		Slot = slot,
		IsPrize = isPrize,
		Size = if isPrize then Layout.PRIZE_SIZE else Layout.CARD,
		Corner = if isPrize
			then Layout.PRIZE
			else Vector2.new(Layout.CARD_XS[(slot - 1) % 3 + 1], Layout.CARD_YS[(slot - 1) // 3 + 1]),
		DealDelay = dealDelay,
		Hand = hand,
		Day = day,
		Reward = derive(function(): DailyRewardsCore.TReward
			return DailyRewardsCore.REWARDS[day()]
		end),
		Status = status,
		IsClaimable = isClaimable,
		IsOwnClaim = isOwnClaim,
		IsCalling = isCalling,
		ClaimShare = claimShare,
		SinceRelease = sinceRelease,
		Charge = charge,
		Settled = settled,
		Greenness = greenness,
		Accent = derive(function(): Color3
			return restAccent:Lerp(Palette.Green, greenness())
		end),
		ToGems = toGems,
		Pinged = pinged,
		Gun = derive(function()
			if not isPrize or isGemsPrize() then return nil end
			return DailyRewardsCore.GunOf(day())
		end),
		IsGemsPrize = isGemsPrize,
		Offset = offset,
		Fade = fade,
		Scale = function(): number
			return hand.Scale() * (1 - squash() + pop())
		end,
		Sheen = sheen,
		Counted = Parts.Since(state, elapsed, dealDelay + Timing.COUNT_DELAY, Timing.COUNT),
	}
end

-- ============================== The pieces ==============================

-- The day's gem: it rattles in the wind-up, bursts into the flying Gems as the claim lets go, and comes back dimmed
-- once the stamp has landed.
local function gem(state: Types.TDailyState, card: TCard): ImageLabel
	local at = if card.IsPrize then Layout.DISC else Layout.GEM
	local claimShare = card.ClaimShare

	return Components.Icon("Gem", {
		Name = "Gem",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			local wound = card.Charge()
			if wound == 0 then return UDim2.fromOffset(at.X, at.Y) end
			local now = state.Now()
			return UDim2.fromOffset(
				at.X + Timing.RATTLE * wound * math.sin(now * 85),
				at.Y + Timing.RATTLE * wound * math.cos(now * 97)
			)
		end,
		Size = Components.GlyphBox(if card.IsPrize then Layout.PRIZE_GEM_GLYPH else Layout.GEM_GLYPH),
		ImageColor3 = Parts.GEM_BLUE,
		Visible = function()
			return not card.IsPrize or card.IsGemsPrize()
		end,
		ImageTransparency = function()
			if card.Status() ~= "Claimed" then return 0 end
			if not card.IsOwnClaim() then return CLAIMED_GEM end
			local burst = claimShare(0, Timing.BURST)
			if burst < 1 or card.SinceRelease() < Cards.IMPACT_SECONDS then return burst end
			return 1 - (1 - CLAIMED_GEM) * card.Settled()
		end,
		ZIndex = 5,
		create("UIScale")({
			Scale = function()
				-- Only while it bursts: once it is gone it comes back at its own size.
				local burst = claimShare(0, Timing.BURST)
				return if burst < 1 then 1 + Timing.BURST_GROW * Motion.Out(burst) else 1
			end,
		}),
	})
end

-- CLAIM NOW, centred on `middleY`. On a small card it turns into his GEMS tag as the claim settles; on day 7
-- (`isPrize`) it fades, and the rarity tag under it shows again.
local function claimTag(card: TCard, middleY: number, isPrize: boolean): Frame
	local toGems = card.ToGems

	return create("Frame")({
		Name = "Tag",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(card.Size.X / 2, middleY),
		Size = function()
			local box = lerp2(Parts.CLAIM_TAG, Parts.GEMS_TAG, if isPrize then 0 else toGems())
			return UDim2.fromOffset(math.round(box.X), math.round(box.Y))
		end,
		BackgroundColor3 = function()
			return Palette.Green:Lerp(Parts.GEMS_EDGE, if isPrize then 0 else toGems())
		end,
		BackgroundTransparency = function()
			return if isPrize then toGems() else 0
		end,
		BorderSizePixel = 0,
		Visible = function()
			return not isPrize or toGems() < 1
		end,
		ZIndex = 5,
		create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
		create("Frame")({
			Name = "Face",
			Position = UDim2.fromOffset(2, 2),
			Size = UDim2.new(1, -4, 1, -4),
			BackgroundColor3 = Palette.Ink,
			BackgroundTransparency = function()
				return if isPrize then 1 else 1 - toGems()
			end,
			BorderSizePixel = 0,
			create("UICorner")({ CornerRadius = UDim.new(0, 1) }),
		}),
		Label({
			Name = "Claim",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, 0, 0, Parts.CLAIM_TAG_TEXT),
			TextYAlignment = Enum.TextYAlignment.Center,
			TextSize = Parts.CLAIM_TAG_TEXT,
			TextColor3 = Palette.Ink,
			TextTransparency = function()
				return math.min(1, toGems() * 2)
			end,
			Text = "CLAIM NOW",
			ZIndex = 2,
		}),
		if isPrize
			then nil
			else Label({
				Name = "Gems",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(1, 0, 0, Parts.GEMS_TAG_TEXT),
				TextYAlignment = Enum.TextYAlignment.Center,
				TextSize = Parts.GEMS_TAG_TEXT,
				TextColor3 = Parts.GEM_BLUE,
				TextTransparency = function()
					return math.min(1, (1 - toGems()) * 2)
				end,
				Text = "GEMS",
				ZIndex = 2,
			}),
	})
end

-- The CLAIMED stamp on a claimed card: it falls onto the card, turning and shrinking into place, as the claim lands.
local function claimedStamp(card: TCard): Frame
	local fall = derive(function(): number
		if card.Status() ~= "Claimed" then return 0 end
		return card.ClaimShare(Timing.STAMP_DELAY, Timing.STAMP)
	end)
	local at = if card.IsPrize then Layout.PRIZE_STAMP else Layout.STAMP
	local size = if card.IsPrize then Layout.PRIZE_STAMP_SCALE else 1

	return stamp({
		Position = UDim2.fromOffset(at.X, at.Y),
		Rotation = function()
			return Layout.STAMP_TURN - Timing.STAMP_SPIN * (1 - fall())
		end,
		Visible = function()
			return fall() > 0
		end,
		create("UIScale")({
			Scale = function()
				return size * (Timing.STAMP_FROM - (Timing.STAMP_FROM - 1) * Motion.Accelerate(fall()))
			end,
		}),
	})
end

-- A Gems day's number (run up as the card is dealt in, dimmed once claimed) and its tag.
local function gemsPieces(card: TCard): { Instance }
	return {
		Label({
			Name = "Value",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(card.Size.X / 2, Layout.VALUE_TOP),
			Size = UDim2.fromOffset(card.Size.X - 20, Layout.VALUE_TEXT),
			TextSize = Layout.VALUE_TEXT,
			Text = function()
				local gems = card.Reward().Gems
				local counted = math.round(gems * Motion.Out(card.Counted()) / 5) * 5
				return Components.Commas(math.min(counted, gems))
			end,
			TextTransparency = function()
				return if card.Status() == "Claimed" then CLAIMED_VALUE * card.Settled() else 0
			end,
		}),
		claimTag(card, Layout.TAG_MIDDLE, false),
	}
end

-- Day 7's disc, PERMANENT, the gun's name and its rarity; for a gun owned already, the Gems it pays and his GEMS tag.
local function prizePieces(card: TCard): { Instance }
	local gun = card.Gun
	local rarity = derive(function()
		local current = gun()
		return if current then WeaponParts.RARITIES[current.Rarity] or WeaponParts.RARITIES.Common else nil
	end)

	return {
		create("Frame")({
			Name = "Disc",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(Layout.DISC.X, Layout.DISC.Y),
			Size = UDim2.fromOffset(2 * Layout.DISC_RADIUS, 2 * Layout.DISC_RADIUS),
			BackgroundColor3 = card.Accent,
			BackgroundTransparency = DISC_FILL,
			BorderSizePixel = 0,
			ZIndex = 3,
			create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
			create("UIStroke")({
				Color = card.Accent,
				Thickness = Layout.DISC_LINE,
				Transparency = DISC_LINE,
			}),
		}),
		create("Frame")({
			Name = "Permanent",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(Layout.PERMANENT.X, Layout.PERMANENT.Y),
			Size = UDim2.fromOffset(Layout.PERMANENT_SIZE.X, Layout.PERMANENT_SIZE.Y),
			Rotation = function()
				return Layout.PERMANENT_TURN + 6 * Motion.Swing(card.ClaimShare(0, Timing.GUN_SPIN))
			end,
			BackgroundColor3 = Palette.Pink,
			BorderSizePixel = 0,
			Visible = function()
				return gun() ~= nil
			end,
			ZIndex = 6,
			create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			Label({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(1, 0, 0, Layout.PERMANENT_TEXT),
				TextYAlignment = Enum.TextYAlignment.Center,
				TextSize = Layout.PERMANENT_TEXT,
				Text = "PERMANENT",
				ZIndex = 2,
			}),
		}),
		Label({
			Name = "Name",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(Layout.DISC.X, Layout.NAME_TOP),
			Size = UDim2.fromOffset(Layout.NAME_SIZE.X, Layout.NAME_SIZE.Y),
			TextScaled = true,
			TextYAlignment = Enum.TextYAlignment.Center,
			Text = function()
				local current = gun()
				if current then return string.upper(current.Name) end
				return Components.Commas(card.Reward().Gems)
			end,
			TextTransparency = function()
				return if card.IsGemsPrize() and card.Status() == "Claimed" then CLAIMED_VALUE * card.Settled() else 0
			end,
			ZIndex = 6,
			create("UITextSizeConstraint")({ MaxTextSize = Layout.NAME_SIZE.Y }),
		}),
		-- His gold tag, in the gun's own rarity.
		create("Frame")({
			Name = "Rarity",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(Layout.DISC.X, Layout.RARITY_TOP),
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, Layout.RARITY_HEIGHT),
			BackgroundColor3 = function()
				local tier = rarity()
				return if tier then tier.Accent else Palette.Gold
			end,
			BackgroundTransparency = function()
				return 1 - card.ToGems()
			end,
			BorderSizePixel = 0,
			Visible = function()
				return gun() ~= nil and card.ToGems() > 0
			end,
			ZIndex = 5,
			create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			create("UIPadding")({
				PaddingLeft = UDim.new(0, Layout.RARITY_PAD),
				PaddingRight = UDim.new(0, Layout.RARITY_PAD),
			}),
			Label({
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, Layout.RARITY_HEIGHT),
				TextYAlignment = Enum.TextYAlignment.Center,
				TextSize = Layout.RARITY_TEXT,
				TextColor3 = function()
					local tier = rarity()
					return if tier and not tier.IsInk then Palette.White else Palette.Ink
				end,
				TextTransparency = function()
					return 1 - card.ToGems()
				end,
				Text = function()
					local tier = rarity()
					return `{if tier then tier.Text else "LEGENDARY"} WEAPON`
				end,
				ZIndex = 2,
			}),
		}),
		Parts.GemsTag({
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(Layout.DISC.X, Layout.RARITY_TOP),
			Visible = function()
				return card.IsGemsPrize() and card.ToGems() > 0
			end,
		}, Vector2.new(84, 32), 17),
		claimTag(card, Layout.PRIZE_TAG_MIDDLE, true),
	}
end

-- Day 7's gun on its disc, spinning round once as it is claimed. It stands over the card's group, since a
-- ViewportFrame is not drawn inside a CanvasGroup's texture.
local function gunPicture(state: Types.TDailyState, card: TCard): Frame
	local gun = card.Gun

	return GunPicture.Build(function()
		local current = gun()
		return if current then GunPicture.FromGun(current.Id) else nil
	end, {
		Lean = Layout.GUN_LEAN,
		Yaw = function()
			if state.ClaimedGun() == 0 then return 0 end
			return 360 * Motion.Decelerate(card.ClaimShare(0, Timing.GUN_SPIN))
		end,
		Transparency = card.Fade,
	}, {
		Name = "Gun",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, Layout.DISC.X - card.Size.X / 2, 0.5, Layout.DISC.Y - card.Size.Y / 2),
		Size = UDim2.fromOffset(Layout.GUN_BOX, Layout.GUN_BOX),
		Visible = function()
			return gun() ~= nil
		end,
		ZIndex = 2,
	})
end

-- A light of the card's own shape: white over it, growing `grow` px each side as `share` runs 0 to 1, from
-- `peak` opaque to nothing.
local function flash(name: string, share: () -> number, grow: number, peak: number): Frame
	return create("Frame")({
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = function()
			local px = 2 * math.round(grow * Motion.Out(share()))
			return UDim2.new(1, px, 1, px)
		end,
		BackgroundColor3 = Palette.White,
		BackgroundTransparency = function()
			return 1 - peak * (1 - share())
		end,
		BorderSizePixel = 0,
		Visible = function()
			local t = share()
			return t > 0 and t < 1
		end,
		ZIndex = 3,
		create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
	})
end

-- One ring of the card's own shape leaving it, `reach` px as `share` runs 0 to 1, from `from` transparent.
local function ring(name: string, share: () -> number, reach: number, color: any, from: number): Frame
	return create("Frame")({
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = function()
			local px = 2 * math.round(reach * Motion.Out(share()))
			return UDim2.new(1, px, 1, px)
		end,
		BackgroundTransparency = 1,
		Visible = function()
			local t = share()
			return t > 0 and t < 1
		end,
		ZIndex = 4,
		create("UICorner")({ CornerRadius = UDim.new(0, 6) }),
		create("UIStroke")({
			Color = color,
			Thickness = Timing.RING_LINE,
			Transparency = function()
				return from + (1 - from) * share()
			end,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
	})
end

-- What is drawn over the card's group, riding it: the claim's flash and ring (in the gun's rarity on day 7), today's
-- ping, and day 7's gun.
local function effects(state: Types.TDailyState, card: TCard): { Instance }
	local claimShare = card.ClaimShare
	local pieces = {
		flash("Flash", function()
			return claimShare(0, Timing.FLASH)
		end, Timing.FLASH_GROW, Timing.FLASH_PEAK),
		ring(
			"Shockwave",
			function()
				return claimShare(0, Timing.RING)
			end,
			Timing.RING_REACH,
			function()
				local gun = if card.IsPrize and state.ClaimedGun() ~= 0 then card.Gun() else nil
				local look = if gun then WeaponParts.RARITIES[gun.Rarity] else nil
				return if look then look.Accent else Palette.Green
			end,
			0.15
		),
		flash("PingFlash", function()
			return card.Pinged(Timing.PING_FLASH)
		end, 0, Timing.PING_FLASH_PEAK),
		ring("PingRing", function()
			return card.Pinged(Timing.PING_RING)
		end, Timing.PING_REACH, Palette.Green, 0.2),
	}
	if card.IsPrize then table.insert(pieces, gunPicture(state, card)) end

	return pieces
end

-- The card itself: his card in the day's colour with the dark band at its top, his white ring round today's, and
-- what the day pays. Pressing today's claims it; pressing one still to come is turned down.
local function face(state: Types.TDailyState, actions: Types.TDailyActions, card: TCard, gemGlyph: ImageLabel)
	local hand = card.Hand
	local size = card.Size
	local greenness = card.Greenness

	return Components.Button({
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundTransparency = 1,
		Activated = function()
			local status = card.Status()
			if status == "Claimable" then
				actions.Claim()
			elseif status == "Future" then
				actions.Refuse(card.Day())
			end
		end,
		hand.Events,
		Components.Card({
			Accent = function()
				return Parts.EdgeOf(card.Accent())
			end,
			Glow = card.Accent,
			GlowTransparency = function()
				return Timing.GLOW - Timing.GLOW_LIT * hand.Light() - (if card.IsCalling() then Timing.CALL_GLOW else 0)
			end,
			Tint = 0.27,
			Marks = true,
			Tall = card.IsPrize,
			Brackets = function()
				return Layout.BRACKETS + Timing.HOVER_BRACKETS * hand.Rise()
			end,
			BracketLength = Layout.BRACKET_LENGTH,
			BracketTransparency = function()
				return 0.6 + 0.4 * greenness() - 0.3 * hand.Light()
			end,
		}, {
			Name = "Face",
			-- Anchored in the middle: its UIScale (the press, the pop, the squeeze) scales about the anchor.
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			create("UIScale")({ Scale = card.Scale }),
			-- His white ring round today's card, standing where the brackets stand on the others.
			create("Frame")({
				Name = "Ring",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = function()
					local out = 2
						* math.round(Layout.RING + Timing.HOVER_BRACKETS * hand.Rise() + 6 * (1 - greenness()))
					return UDim2.new(1, out, 1, out)
				end,
				BackgroundTransparency = 1,
				Visible = function()
					return greenness() > 0.01
				end,
				ZIndex = 0,
				create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
				create("UIStroke")({
					Color = Palette.White,
					Thickness = 1.5,
					Transparency = function()
						return 1 - 0.95 * greenness()
					end,
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				}),
			}),
			create("Frame")({
				Name = "Band",
				Position = UDim2.fromOffset(3, 3),
				Size = UDim2.new(1, -6, 0, if card.IsPrize then Layout.PRIZE_BAND else Layout.BAND),
				BackgroundColor3 = Parts.BAND,
				BorderSizePixel = 0,
				ZIndex = 2,
				create("UICorner")({ CornerRadius = UDim.new(0, 1) }),
			}),
			Hand.WashLayer(hand, 3, 2),
			Components.Sheen(card.Sheen, 7),
			Label({
				Name = "Day",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromOffset(size.X / 2, Layout.DAY_TOP),
				Size = UDim2.fromOffset(size.X - 20, if card.IsPrize then Layout.PRIZE_DAY_TEXT else Layout.DAY_TEXT),
				TextSize = if card.IsPrize then Layout.PRIZE_DAY_TEXT else Layout.DAY_TEXT,
				Text = function()
					return `DAY {card.Day()}`
				end,
			}),
			gemGlyph,
			if card.IsPrize then prizePieces(card) else gemsPieces(card),
			claimedStamp(card),
		}),
	})
end

-- ============================== The week ==============================

-- The week's cards, the effects over each, and each card's gem glyph by its place in the week.
function Cards.Build(
	state: Types.TDailyState,
	actions: Types.TDailyActions,
	elapsed: () -> number,
	shown: () -> number
): ({ Instance }, { ImageLabel })
	local children = table.create(2 * WEEK)
	local glyphs = table.create(WEEK)
	for slot = 1, WEEK do
		local card = cardState(state, elapsed, shown, slot)
		local size = card.Size
		local gemGlyph = gem(state, card)
		local topLeft = function(): UDim2
			local at = card.Corner + card.Offset()
			return UDim2.fromOffset(at.X, at.Y)
		end
		glyphs[slot] = gemGlyph

		children[2 * slot - 1] = create("CanvasGroup")({
			Name = `Day{slot}`,
			Position = function()
				return topLeft() - UDim2.fromOffset(Layout.MARGIN, Layout.MARGIN)
			end,
			Size = UDim2.fromOffset(size.X + 2 * Layout.MARGIN, size.Y + 2 * Layout.MARGIN),
			BackgroundTransparency = 1,
			GroupTransparency = card.Fade,
			ZIndex = 3,
			face(state, actions, card, gemGlyph),
		})
		-- The same rect, offset and scale as the card, anchored in its middle so the scale grows it about the same point.
		children[2 * slot] = create("Frame")({
			Name = `Day{slot}Effects`,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				return topLeft() + UDim2.fromOffset(size.X / 2, size.Y / 2)
			end,
			Size = UDim2.fromOffset(size.X, size.Y),
			BackgroundTransparency = 1,
			ZIndex = 4,
			create("UIScale")({ Scale = card.Scale }),
			effects(state, card),
		})
	end

	return children, glyphs
end

return Cards
