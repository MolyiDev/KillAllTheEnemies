--!nonstrict
-- The reel (UIMatt.md, Daily Spins): his well with the gold pointer over it, seven of his cards resting in it with
-- the white ring round the one under the pointer, and the spin turning them (where to, ReelMotion). Every card that
-- passes the pointer ticks it; the slow last ones flick it.
--
-- The landing is the card's: it punches, flashes white and throws one ring, light opens in rays behind it, glowing
-- pixels leave its edge and the other cards step back. The prize then flies into the HUD (Payout).
--
-- The reel is NINE cards walked round: each holds the slot nearest it that is its own modulo nine, so a card's
-- picture changes only as it wraps from one end to the other.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local SpinsCore = require(ReplicatedStorage.Shared.Core.SpinsCore)
local Parts = require(script.Parent.Parts)
local ReelMotion = require(script.Parent.ReelMotion)
local Types = require(script.Parent.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Progress = Motion.Progress
local Scatter = Parts.Scatter
local PARKED = Parts.PARKED

-- His drawn rects in px at 1080, from the panel's top left.
local Layout = table.freeze({
	-- The well: its 1 px edge round the dark face.
	WELL = Vector2.new(40, 159),
	WELL_SIZE = Vector2.new(1220, 200),
	-- In the well's face (inside its edge): the middle of the card under the pointer, and the step between cards.
	CENTER = Vector2.new(609, 99),
	PITCH = 166,
	CARD = Vector2.new(150, 164),
	-- 6 out, so two cards 16 apart keep their corners apart (his 8 met).
	CARD_BRACKET_LENGTH = 22,
	-- The cards walked round, and how far from the pointer one is still one of his seven at rest, in slots.
	POOL = 9,
	SHOWN = 3.6,
	-- Inside a card, from its top: the glyph's middle and longer side, the value, the word, the bar.
	GLYPH_Y = 37,
	GLYPH = 36,
	VALUE_Y = 72,
	VALUE_TEXT = 38,
	WORD_Y = 114,
	WORD_TEXT = 14,
	BAR_Y = 143,
	BAR = Vector2.new(90, 4),
	-- The white ring round the card under the pointer: 6 px off the card, 2 px thick.
	RING_OUTSET = 4,
	RING_LINE = 2,
	-- The pointer: its tip's top middle, its size, and the gold line under it through the well.
	POINTER = Vector2.new(650, 137),
	POINTER_SIZE = Vector2.new(18, 12),
	LINE_WIDTH = 2,
})

-- His colours that are not in the Palette: the well's edge and face, and the pointer line's strength.
local WELL_EDGE = Color3.fromRGB(62, 50, 100)
local WELL_FACE = Color3.fromRGB(14, 10, 29)
local LINE_TRANSPARENCY = 0.44
-- His cards' edge is their accent a little darker; the glow is the accent itself.
local EDGE_SHARE = 0.85
local CARD_TINT = 0.4
local GLOW_TRANSPARENCY = 0.7

-- The turning reel's look: cards away from the pointer shrink as on a drum, the card passing it swells, everything
-- smears at speed, and the well's ends darken while it turns. The pointer leans with the speed and flicks on each
-- slow card. Ticks are never closer than TICK_GAP.
local Turn = table.freeze({
	DRUM = 0.07,
	DRUM_REACH = 3.5,
	PASS = 0.06,
	PASS_BELOW = 10,
	SMEAR = 0.5,
	SHADE_WIDTH = 150,
	SHADE = 0.95,
	LEAN = 10,
	FLICK = 9,
	FLICK_BELOW = 9,
	FLICK_PERIOD = 0.14,
	FLICK_DAMPING = 0.5,
	TICK_GAP = 0.028,
})

-- The landing, in seconds from it.
local Land = table.freeze({
	PUNCH = 0.12,
	PUNCH_IN = 0.06,
	PUNCH_OUT = 0.42,
	FLASH = 0.32,
	FLASH_STRENGTH = 0.7,
	GLOW = 0.4,
	RING = 0.5,
	RING_REACH = 44,
	RING_LINE = 3,
	-- The other cards step back, hold, and come back as the prize finishes landing.
	DIM = 0.55,
	DIM_IN = 0.15,
	DIM_HOLD = 1.7,
	DIM_OUT = 0.4,
	-- The jackpot also lights the whole well.
	WELL_FLASH = 0.2,
	WELL_FLASH_SECONDS = 0.3,
})

-- Light behind the card: even-width rays from its middle, born a beat apart, each opening, holding and closing where it
-- was born while it turns slowly. Faint alone; it is their overlap that is bright.
local Rays = table.freeze({
	POOL = 30,
	COUNT = 18,
	JACKPOT_COUNT = 30,
	EVERY = 0.05,
	LIFE_MIN = 0.5,
	LIFE_MAX = 1.1,
	LENGTH_MIN = 170,
	LENGTH_MAX = 260,
	JACKPOT_LENGTH_MIN = 240,
	JACKPOT_LENGTH_MAX = 380,
	WIDTH = 10,
	TURN = 40,
	ALPHA_MIN = 0.3,
	ALPHA_MAX = 0.6,
	-- Shares of a ray's life: open by OPEN, held to HOLD, closed by 1.
	OPEN = 0.33,
	HOLD = 0.62,
	WHITE = 0.45,
})

-- Glowing pixels thrown off the card's edge: born a step outside its glow, thrown out against drag, a little gravity,
-- faded in and out (never a blink).
local Pixels = table.freeze({
	POOL = 34,
	COUNT = 20,
	JACKPOT_COUNT = 34,
	OUTSIDE = 26,
	REACH_MIN = 60,
	REACH_MAX = 150,
	DRAG = 6,
	GRAVITY = 70,
	SIZE_MIN = 5,
	SIZE_MAX = 9,
	LIFE_MIN = 0.75,
	LIFE_MAX = 1.25,
	FADE_IN = 0.05,
	FADE_FROM = 0.55,
	WHITE_EVERY = 3,
	LIFT = 0.35,
})

-- The open: the cards fall into the well one after another from the middle out, the pointer after them.
local Deal = table.freeze({
	DELAY = 0.08,
	STAGGER = 0.05,
	SECONDS = 0.42,
	DROP = 200,
	POINTER_DELAY = 0.42,
	POINTER_DROP = 22,
	POINTER = 0.3,
})

local Reel = {}

-- How long a landing's light and the other cards' step back last: the controller keeps the clock ticking for them.
Reel.LAND_SECONDS = Land.DIM_IN + Land.DIM_HOLD + Land.DIM_OUT

-- The prize the spin turning now landed on, nil until it lands (or with none, or a refused one).
local function landedPrize(state: Types.TSpinsState): () -> SpinsCore.TPrize?
	return derive(function(): SpinsCore.TPrize?
		local spin = state.Spin()
		local index = if spin and spin.LandAt then spin.Prize else nil
		return if index and index > 0 then SpinsCore.PRIZES[index] else nil
	end)
end

-- Seconds since the spin landed, nil before it lands or with none. Derived: past the landing's light it holds.
local function landedFor(state: Types.TSpinsState): () -> number?
	return derive(function(): number?
		local spin = state.Spin()
		local at = if spin then spin.LandAt else nil
		if not at or not spin.Prize or spin.Prize == 0 then return nil end
		local since = state.Now() - at
		if since < 0 then return nil end
		return math.min(since, Reel.LAND_SECONDS)
	end)
end

-- 0 at rest, 1 while the reel turns: up as it is thrown, down as it settles.
local function turningOf(state: Types.TSpinsState): () -> number
	return derive(function(): number
		local spin = state.Spin()
		if not spin then return 0 end
		local now = state.Now()
		local up = Progress(now, spin.StartAt, 0.3)
		local brakeAt = spin.BrakeAt
		if not brakeAt then return up end
		local stoppedAt = brakeAt + (spin.BrakeSeconds :: number)
		return up * (1 - Progress(now, stoppedAt, ReelMotion.SETTLE))
	end)
end

local function card(
	state: Types.TSpinsState,
	index: number,
	reading: () -> Vector2,
	turning: () -> number,
	landed: () -> number?,
	elapsed: () -> number
): Frame
	local slot = derive(function(): number
		local base = math.floor(reading().X + 0.5) - 4
		return base + (index - base) % Layout.POOL
	end)
	local prize = derive(function(): SpinsCore.TPrize
		return SpinsCore.PRIZES[SpinsCore.PrizeAt(slot())]
	end)
	local accent = derive(function(): Color3
		return Parts.AccentOf(prize())
	end)
	local edge = derive(function(): Color3
		local color = accent()
		return Color3.new(color.R * EDGE_SHARE, color.G * EDGE_SHARE, color.B * EDGE_SHARE)
	end)
	local isWon = derive(function(): boolean
		local spin = state.Spin()
		return landed() ~= nil and spin ~= nil and slot() == spin.Slot
	end)
	-- The open: from the middle out, by where it rests.
	local dealt = derive(function(): number
		if not state.IsOpen() then return 1 end
		-- Capped: mid-spin a card is tens of slots from the rest, and its fall must already be over.
		local away = math.min(math.abs(slot() - state.Rest()), 4)
		return Motion.Decelerate(Progress(elapsed(), Deal.DELAY + Deal.STAGGER * away, Deal.SECONDS))
	end)
	local scale = derive(function(): number
		local dx = slot() - reading().X
		local speed = math.abs(reading().Y)
		local turn = turning()
		local reach = math.min(math.abs(dx) / Turn.DRUM_REACH, 1)
		local passing = math.max(0, 1 - math.abs(dx) * 2) ^ 2 * (1 - math.clamp(speed / Turn.PASS_BELOW, 0, 1))
		local value = 1 - Turn.DRUM * turn * reach * reach + Turn.PASS * turn * passing
		local since = if isWon() then landed() else nil
		if since then
			local up = Motion.Decelerate(math.clamp(since / Land.PUNCH_IN, 0, 1))
			local down = Motion.Out(math.clamp((since - Land.PUNCH_IN) / Land.PUNCH_OUT, 0, 1))
			value += Land.PUNCH * up * (1 - down)
		end

		return value
	end)
	local smear = derive(function(): number
		return Turn.SMEAR * math.clamp(math.abs(reading().Y) / ReelMotion.TOP, 0, 1) ^ 1.5
	end)
	local flash = derive(function(): number
		local since = if isWon() then landed() else nil
		if not since then return 0 end
		local left = 1 - math.clamp(since / Land.FLASH, 0, 1)
		return left * left
	end)
	local dim = derive(function(): number
		local since = landed()
		if not since or isWon() then return 0 end
		local fall = Motion.Out(math.clamp(since / Land.DIM_IN, 0, 1))
		local rise = Motion.Out(math.clamp((since - Land.DIM_IN - Land.DIM_HOLD) / Land.DIM_OUT, 0, 1))
		return fall * (1 - rise)
	end)
	-- Its brackets, gone under the pointer, where the white ring stands round the card instead: two sets read as a double
	-- corner (UI.md). Derived, so the four corners share one reading of the reel a frame, held at rest.
	local bracketsFaded = derive(function(): number
		local dx = math.abs(slot() - reading().X)
		return 0.65 + 0.35 * math.max(0, 1 - 2 * dx)
	end)
	local lit = derive(function(): number
		local since = if isWon() then landed() else nil
		if not since then return 0 end
		local fall = Motion.Out(math.clamp((since - Land.DIM_IN - Land.DIM_HOLD) / Land.DIM_OUT, 0, 1))
		return 1 - fall
	end)

	return Components.Card({
		Accent = edge,
		Glow = accent,
		GlowTransparency = function()
			return GLOW_TRANSPARENCY - Land.GLOW * lit()
		end,
		Tint = CARD_TINT,
		Marks = true,
		Brackets = true,
		BracketLength = Layout.CARD_BRACKET_LENGTH,
		BracketTransparency = bracketsFaded,
	}, {
		Name = `Card{index}`,
		AnchorPoint = Vector2.new(0.5, 0.5),
		-- At rest his seven stand alone in the well: the two wrapping round its ends are parked unless it turns.
		Position = function()
			local dx = slot() - reading().X
			if turning() == 0 and math.abs(dx) >= Layout.SHOWN then return PARKED end
			return UDim2.fromOffset(
				math.round(Layout.CENTER.X + Layout.PITCH * dx),
				Layout.CENTER.Y - math.round(Deal.DROP * (1 - dealt()))
			)
		end,
		Size = UDim2.fromOffset(Layout.CARD.X, Layout.CARD.Y),
		ZIndex = 3,
		create("UIScale")({ Scale = scale }),
		Components.Picture(function()
			local current = prize()
			if current.Kind == "Xp" then return EIcons.Rank end
			return if current.IsJackpot then EIcons.GemPile else EIcons.Gem
		end, {
			Name = "Glyph",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(Layout.CARD.X / 2, Layout.GLYPH_Y),
			Size = Components.PictureBox(Layout.GLYPH),
			ImageTransparency = smear,
			ZIndex = 4,
		}),
		Parts.Label({
			Name = "Value",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(Layout.CARD.X / 2, Layout.VALUE_Y),
			Size = UDim2.fromOffset(Layout.CARD.X, Layout.VALUE_TEXT),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextSize = Layout.VALUE_TEXT,
			TextColor3 = accent,
			TextTransparency = smear,
			Text = function()
				return Components.Commas(prize().Amount)
			end,
		}),
		Parts.Label({
			Name = "Word",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(Layout.CARD.X / 2, Layout.WORD_Y),
			Size = UDim2.fromOffset(Layout.CARD.X, Layout.WORD_TEXT),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextSize = Layout.WORD_TEXT,
			TextTransparency = smear,
			Text = function()
				return if prize().Kind == "Xp" then "XP" else "GEMS"
			end,
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
			Name = "Dim",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(),
			BorderSizePixel = 0,
			ZIndex = 6,
			Visible = function()
				return dim() > 0.004
			end,
			BackgroundTransparency = function()
				return 1 - Land.DIM * dim()
			end,
			create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
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
				return 1 - Land.FLASH_STRENGTH * flash()
			end,
			create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
		}),
	})
end

-- The rays behind the landed card, in the well's face, under the cards. Turned, so the well does not clip them
-- (ClipsDescendants skips a turned child): they open past the well over the panel, under its words.
local function rays(prize: () -> SpinsCore.TPrize?, landed: () -> number?): { Instance }
	local accent = derive(function(): Color3
		local current = prize()
		return if current then Parts.AccentOf(current):Lerp(Palette.White, Rays.WHITE) else Palette.White
	end)
	local isJackpot = derive(function(): boolean
		local current = prize()
		return current ~= nil and current.IsJackpot == true
	end)

	local pieces = table.create(Rays.POOL)
	for index = 1, Rays.POOL do
		local life = Rays.LIFE_MIN + (Rays.LIFE_MAX - Rays.LIFE_MIN) * Scatter(index, 1)
		local born = (index - 1) * Rays.EVERY
		local turn = Rays.TURN * (if Scatter(index, 5) < 0.5 then -1 else 1)
		local alpha = Rays.ALPHA_MIN + (Rays.ALPHA_MAX - Rays.ALPHA_MIN) * Scatter(index, 4)
		local reach = Scatter(index, 3)
		-- 0 to 1 over the ray's life, nil while it is not alive.
		local age = derive(function(): number?
			local since = landed()
			if not since then return nil end
			if index > (if isJackpot() then Rays.JACKPOT_COUNT else Rays.COUNT) then return nil end
			local t = (since - born) / life
			return if t > 0 and t < 1 then t else nil
		end)
		local open = derive(function(): number
			local t = age() or 0
			if t < Rays.OPEN then return Motion.Out(t / Rays.OPEN) end
			if t < Rays.HOLD then return 1 end
			return 1 - (t - Rays.HOLD) / (1 - Rays.HOLD)
		end)
		local length = derive(function(): number
			local short = if isJackpot() then Rays.JACKPOT_LENGTH_MIN else Rays.LENGTH_MIN
			local long = if isJackpot() then Rays.JACKPOT_LENGTH_MAX else Rays.LENGTH_MAX
			return short + (long - short) * reach
		end)

		pieces[index] = create("Frame")({
			Name = `Ray{index}`,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				return if age() then UDim2.fromOffset(Layout.CENTER.X, Layout.CENTER.Y) else PARKED
			end,
			Size = function()
				return UDim2.fromOffset(math.round(2 * length() * open()), Rays.WIDTH)
			end,
			Rotation = function()
				return 360 * Scatter(index, 2) + turn * (age() or 0) * life
			end,
			BackgroundColor3 = accent,
			BackgroundTransparency = function()
				return 1 - alpha * math.min(open() * 1.5, 1)
			end,
			BorderSizePixel = 0,
			ZIndex = 2,
			-- Only the half past the middle shows, fading out to its tip: a ray from the card's middle.
			create("UIGradient")({
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.5, 1),
					NumberSequenceKeypoint.new(0.501, 0),
					NumberSequenceKeypoint.new(1, 1),
				}),
			}),
		})
	end

	return pieces
end

-- One end of the well darkening while the reel turns, so the cards run into it.
local function shade(turning: () -> number, isRight: boolean): Frame
	return create("Frame")({
		Name = if isRight then "ShadeRight" else "ShadeLeft",
		AnchorPoint = Vector2.new(if isRight then 1 else 0, 0),
		Position = UDim2.fromScale(if isRight then 1 else 0, 0),
		Size = UDim2.new(0, Turn.SHADE_WIDTH, 1, 0),
		BackgroundColor3 = WELL_FACE,
		BorderSizePixel = 0,
		ZIndex = 5,
		Visible = function()
			return turning() > 0.004
		end,
		-- Up faster than the reel, so the cards wrapping round come in under it.
		BackgroundTransparency = function()
			return 1 - Turn.SHADE * math.sqrt(turning())
		end,
		create("UIGradient")({
			Rotation = if isRight then 180 else 0,
			Transparency = NumberSequence.new(0, 1),
		}),
	})
end

-- The well, the cards in it, the ring, the rays and the pointer, among the panel's children. `reading` is where the
-- reel stands and how fast it turns (ReelMotion.At, as X and Y), shared with SPIN's die.
function Reel.Build(state: Types.TSpinsState, reading: () -> Vector2, elapsed: () -> number): { Instance }
	local turning = turningOf(state)
	local landed = landedFor(state)

	-- A tick as each card's edge passes the pointer, and the pointer flicked by the slow ones.
	local flick, strikeFlick = Hand.Kick(Turn.FLICK_PERIOD, Turn.FLICK_DAMPING)
	local under = derive(function(): number
		return math.floor(reading().X + 0.5)
	end)
	local lastUnder: number? = nil
	local lastTickAt = -math.huge
	vide.effect(function()
		local current = under()
		vide.untrack(function()
			local isSpinning = state.Spin() ~= nil
			if isSpinning and lastUnder and current ~= lastUnder then
				local now = os.clock()
				if now - lastTickAt >= Turn.TICK_GAP then
					lastTickAt = now
					SoundsCore.PlayUINamed("UI.UpgradePick", "Tick")
				end
				local speed = math.abs(reading().Y)
				if speed < Turn.FLICK_BELOW then strikeFlick(Turn.FLICK) end
			end
			lastUnder = current
		end)
	end)

	local prize = landedPrize(state)
	local wellFlash = derive(function(): number
		local current = prize()
		local since = landed()
		if not current or not current.IsJackpot or not since then return 0 end
		local left = 1 - math.clamp(since / Land.WELL_FLASH_SECONDS, 0, 1)
		return left * left
	end)

	local cards = table.create(Layout.POOL)
	for index = 1, Layout.POOL do
		cards[index] = card(state, index, reading, turning, landed, elapsed)
	end

	local pointerDropped = derive(function(): number
		if not state.IsOpen() then return 1 end
		return Motion.Decelerate(Progress(elapsed(), Deal.POINTER_DELAY, Deal.POINTER))
	end)

	return {
		create("Frame")({
			Name = "Well",
			Position = UDim2.fromOffset(Layout.WELL.X, Layout.WELL.Y),
			Size = UDim2.fromOffset(Layout.WELL_SIZE.X, Layout.WELL_SIZE.Y),
			BackgroundColor3 = WELL_EDGE,
			BorderSizePixel = 0,
			ZIndex = 2,
			create("Frame")({
				Name = "Face",
				Position = UDim2.fromOffset(1, 1),
				Size = UDim2.new(1, -2, 1, -2),
				BackgroundColor3 = WELL_FACE,
				BorderSizePixel = 0,
				ClipsDescendants = true,
				create("Frame")({
					Name = "Line",
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.fromOffset(Layout.CENTER.X, 0),
					Size = UDim2.new(0, Layout.LINE_WIDTH, 1, 0),
					BackgroundColor3 = Palette.Gold,
					BackgroundTransparency = LINE_TRANSPARENCY,
					BorderSizePixel = 0,
					ZIndex = 1,
				}),
				rays(prize, landed),
				cards,
				shade(turning, false),
				shade(turning, true),
				create("Frame")({
					Name = "Ring",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(Layout.CENTER.X, Layout.CENTER.Y),
					Size = UDim2.fromOffset(
						Layout.CARD.X + 2 * Layout.RING_OUTSET,
						Layout.CARD.Y + 2 * Layout.RING_OUTSET
					),
					BackgroundTransparency = 1,
					ZIndex = 6,
					create("UIScale")({
						Scale = function()
							return Motion.Lerp(0.8, 1, pointerDropped())
						end,
					}),
					create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
					create("UIStroke")({
						Color = Palette.White,
						Thickness = Layout.RING_LINE,
						Transparency = function()
							return 1 - pointerDropped()
						end,
					}),
				}),
				create("Frame")({
					Name = "Flash",
					Size = UDim2.fromScale(1, 1),
					BackgroundColor3 = Palette.White,
					BorderSizePixel = 0,
					ZIndex = 7,
					Visible = function()
						return wellFlash() > 0.004
					end,
					BackgroundTransparency = function()
						return 1 - Land.WELL_FLASH * wellFlash()
					end,
				}),
			}),
		}),
		-- Turned about its top, where it hangs: a frame turns about its middle, so the tip hangs off a point.
		create("Frame")({
			Name = "Pointer",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				return UDim2.fromOffset(
					Layout.POINTER.X,
					Layout.POINTER.Y - math.round(Deal.POINTER_DROP * (1 - pointerDropped()))
				)
			end,
			Size = UDim2.fromOffset(2, 2),
			BackgroundTransparency = 1,
			ZIndex = 5,
			Rotation = function()
				return Turn.LEAN * math.clamp(math.abs(reading().Y) / ReelMotion.TOP, 0, 1) + flick()
			end,
			-- Its cell is square: the picture's middle sits half its height under where it hangs.
			Components.Picture(EIcons.Pointer, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0.5, Layout.POINTER_SIZE.Y / 2),
				Size = Components.PictureBox(Layout.POINTER_SIZE.X),
				ImageTransparency = function()
					return 1 - pointerDropped()
				end,
			}),
		}),
	}
end

-- Over the panel and unclipped: the ring thrown off the landed card and the pixels leaving its edge. Laid in the
-- panel's own px, with the card resting at the pointer.
function Reel.BuildFx(state: Types.TSpinsState): { Instance }
	local landed = landedFor(state)
	local prize = landedPrize(state)
	local center = Layout.WELL + Vector2.new(1, 1) + Layout.CENTER
	local accent = derive(function(): Color3
		local current = prize()
		return if current then Parts.AccentOf(current) else Palette.White
	end)
	local isJackpot = derive(function(): boolean
		local current = prize()
		return current ~= nil and current.IsJackpot == true
	end)

	local ring = derive(function(): number?
		local since = landed()
		if not since then return nil end
		local t = since / Land.RING
		return if t < 1 then t else nil
	end)

	local half = Layout.CARD / 2 + Vector2.new(Pixels.OUTSIDE, Pixels.OUTSIDE)
	local pixels = table.create(Pixels.POOL)
	for index = 1, Pixels.POOL do
		local angle = (index - 1 + (Scatter(index, 6) - 0.5) * 0.8) / Pixels.COUNT * 2 * math.pi
		local direction = Vector2.new(math.cos(angle), math.sin(angle))
		-- Out of the card's own rectangle, a step past its glow.
		local start = direction
			* math.min(half.X / math.max(math.abs(direction.X), 1e-3), half.Y / math.max(math.abs(direction.Y), 1e-3))
		local reach = Pixels.REACH_MIN + (Pixels.REACH_MAX - Pixels.REACH_MIN) * Scatter(index, 7)
		local life = Pixels.LIFE_MIN + (Pixels.LIFE_MAX - Pixels.LIFE_MIN) * Scatter(index, 8)
		local size = math.round(Pixels.SIZE_MIN + (Pixels.SIZE_MAX - Pixels.SIZE_MIN) * Scatter(index, 9))
		local isWhite = index % Pixels.WHITE_EVERY == 0
		local age = derive(function(): number?
			local since = landed()
			if not since then return nil end
			if index > (if isJackpot() then Pixels.JACKPOT_COUNT else Pixels.COUNT) then return nil end
			return if since < life then since else nil
		end)

		pixels[index] = create("Frame")({
			Name = `Pixel{index}`,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				local t = age()
				if not t then return PARKED end
				local at = center
					+ start
					+ direction * reach * (1 - math.exp(-Pixels.DRAG * t))
					+ Vector2.new(0, Pixels.GRAVITY * t * t)
				return UDim2.fromOffset(math.round(at.X), math.round(at.Y))
			end,
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = function()
				return if isWhite then Palette.White else accent():Lerp(Palette.White, Pixels.LIFT)
			end,
			BackgroundTransparency = function()
				local t = age() or 0
				local share = t / life
				local appear = math.clamp(t / Pixels.FADE_IN, 0, 1)
				local u = math.clamp((share - Pixels.FADE_FROM) / (1 - Pixels.FADE_FROM), 0, 1)
				return 1 - appear * (1 - u * u * (3 - 2 * u))
			end,
			BorderSizePixel = 0,
		})
	end

	return {
		create("Frame")({
			Name = "Burst",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				return if ring() then UDim2.fromOffset(center.X, center.Y) else PARKED
			end,
			Size = function()
				local grow = math.round(Land.RING_REACH * Motion.Out(ring() or 0))
				return UDim2.fromOffset(Layout.CARD.X + 2 * grow, Layout.CARD.Y + 2 * grow)
			end,
			BackgroundTransparency = 1,
			create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
			create("UIStroke")({
				Color = accent,
				Thickness = Land.RING_LINE,
				Transparency = function()
					return 0.15 + 0.85 * (ring() or 1)
				end,
			}),
		}),
		pixels,
	}
end

return Reel
