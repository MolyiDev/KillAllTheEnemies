--!nonstrict
-- The daily screen's SPIN page on his 1920 x 1080 (UIMatt.md, Daily Spins): the reel (Reel), how many spins are left,
-- SPIN and the time to the next free ones, on the panel DailyController draws under his DAILY | SPIN tabs, riding its
-- top as it changes shape; the prize flies out of it into the HUD (Payout). The page rises in as it fades in, the
-- cards fall into the well from the middle out and the pointer drops onto them; it sinks and fades on the way out.
--
-- His token balance (bottom right) is left out: the prizes are Gems and XP, and the HUD's pill already shows the Gems.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local SpinsCore = require(ReplicatedStorage.Shared.Core.SpinsCore)
local formatCountdown = require(ReplicatedStorage.GlobalShared.Utils.Functions.formatCountdown)
local Payout = require(script.Parent.Payout)
local Parts = require(script.Parent.Parts)
local Reel = require(script.Parent.Reel)
local ReelMotion = require(script.Parent.ReelMotion)
local Types = require(script.Parent.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
local spring = vide.spring
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress

-- His drawn rects in px at 1080, from the panel's top left unless said otherwise.
local Layout = table.freeze({
	-- The panel, from the screen's top left.
	PANEL = Vector2.new(310, 251),
	SIZE = Vector2.new(1300, 560),
	-- Under the reel: the spins left (centred), SPIN, the clock.
	LEFT_Y = 388,
	LEFT_TEXT = 22,
	BUTTON = Vector2.new(459, 430),
	BUTTON_SIZE = Vector2.new(382, 82),
	DIE = 28,
	BUTTON_TEXT = 31,
	BUTTON_TRACKING = 3,
	BUTTON_GAP = 14,
	ROBUX = 26,
	WATCH = Vector2.new(52, 470),
	WATCH_SIZE = 21,
	CLOCK = Vector2.new(74, 461),
	CLOCK_TEXT = 20,
	-- The room round the panel inside the group that fades it, for the glow, the brackets and the rays (a CanvasGroup
	-- clips).
	MARGIN = 160,
})

local Timing = table.freeze({
	-- The page decelerates up into place and accelerates down out of it, the exit the faster; its fade runs on the
	-- clock, not on the move.
	OPEN = 0.34,
	FADE = 0.27,
	RISE = 26,
	CLOSE = 0.2,
	SINK = 14,
	-- Every gesture of an open is over by now.
	SETTLED = 1.6,
	-- SPIN catches the light as the open lands, and again every INVITE seconds while a spin waits for it.
	SHEEN_DELAY = 0.45,
	SHEEN = 0.6,
	INVITE = 3,
	-- The spins left sting white when their number changes.
	STING_PERIOD = 0.35,
	-- With a spin waiting, SPIN wobbles once to be pressed (BeckonAt): it pops and hops, its width and height
	-- trade places a few times as it dies out (a jelly: nothing turns, or the brackets' windows stop clipping), the die
	-- rolls round once, the light crosses it, its glow comes up and one ring leaves it.
	BECKON = 0.95,
	BECKON_POP = 0.12,
	BECKON_POP_SECONDS = 0.32,
	BECKON_HOP = 12,
	BECKON_HOP_SECONDS = 0.36,
	BECKON_JELLY = 0.09,
	BECKON_WOBBLES = 2.6,
	BECKON_ROLL = 0.7,
	BECKON_SHEEN_DELAY = 0.08,
	BECKON_SHEEN = 0.55,
	BECKON_RING = 0.6,
	BECKON_REACH = 36,
	BECKON_GLOW = 0.35,
	-- A refused press shakes SPIN.
	REFUSED = 0.35,
	REFUSED_SHAKE = 7,
	-- The jackpot shakes the panel.
	SHAKE = 5,
	SHAKE_SECONDS = 0.5,
	SHAKE_RATE = 55,
})

local Screen = {}

Screen.LEAVE_SECONDS = Timing.CLOSE

local function plural(count: number, word: string): string
	return if count == 1 then `{count} {word}` else `{count} {word}S`
end

-- SPIN: his green slab with the die. Selling a spin it turns his violet Robux slab with the price; with nothing to
-- spin and nothing for sale, or while the reel turns, it is the grey one. The die rolls a quarter turn for every card
-- that passes the pointer.
local function spinButton(
	state: Types.TSpinsState,
	actions: Types.TSpinsActions,
	reading: () -> Vector2,
	elapsed: () -> number
): TextButton
	local isLive = derive(function(): boolean
		local mode = state.Mode()
		return mode == "Spin" or mode == "Buy"
	end)
	local hand = Hand.React("Operate", isLive)
	local roll = derive(function(): number
		return -90 * reading().X
	end)
	local kick, strikeKick = Hand.Kick(0.5, 0.8)

	-- The light crossing it as the open lands, and every few seconds while a spin waits on it.
	local invite, throwInvite = spring(function()
		return 1.6
	end, 1, 1)
	vide.effect(function()
		local seconds = state.SecondsLeft()
		vide.untrack(function()
			if seconds % Timing.INVITE == 0 and isLive() and state.IsOpen() then
				throwInvite({ position = 0, velocity = 2.2 })
			end
		end)
	end)
	local landed = derive(function(): number
		if not state.IsOpen() then return 1 end
		return Progress(elapsed(), Timing.SHEEN_DELAY, Timing.SHEEN)
	end)
	-- The wobble, 0 to 1 from BeckonAt, and 1 at rest; and its light's travel.
	local beckoned = derive(function(): number
		return Progress(state.Now(), state.BeckonAt(), Timing.BECKON)
	end)
	local beckonSheen = derive(function(): number
		return Progress(state.Now(), state.BeckonAt(), Timing.BECKON_SHEEN, Timing.BECKON_SHEEN_DELAY)
	end)
	local light = function(): number
		local travel = math.min(invite(), 1)
		if travel < 1 then return travel end
		local beckon = beckonSheen()
		return if beckon > 0 and beckon < 1 then beckon else landed()
	end
	-- Its jelly: + wider and shorter, - narrower and taller; first up, as it hops.
	local jelly = derive(function(): number
		local t = beckoned()
		if t <= 0 or t >= 1 then return 0 end
		return -Timing.BECKON_JELLY * math.sin(2 * math.pi * Timing.BECKON_WOBBLES * t) * (1 - t) * (1 - t)
	end)
	local hop = derive(function(): number
		return Timing.BECKON_HOP * Motion.Bump(Progress(state.Now(), state.BeckonAt(), Timing.BECKON_HOP_SECONDS))
	end)
	local beckonPop = derive(function(): number
		return Timing.BECKON_POP * Motion.Bump(Progress(state.Now(), state.BeckonAt(), Timing.BECKON_POP_SECONDS))
	end)
	-- One turn of the die, back to 0 once round rather than resting at -360.
	local beckonRoll = derive(function(): number
		local t = Progress(state.Now(), state.BeckonAt(), Timing.BECKON_ROLL)
		if t >= 1 then return 0 end
		return -360 * Motion.Decelerate(t)
	end)
	local ring = derive(function(): number
		return Progress(state.Now(), state.BeckonAt(), Timing.BECKON_RING)
	end)

	local shake = derive(function(): number
		local at = state.RefusedAt()
		return Timing.REFUSED_SHAKE * Motion.Shake(Progress(state.Now(), at, Timing.REFUSED), at)
	end)
	local isBuy = derive(function(): boolean
		return state.Mode() == "Buy"
	end)

	return Components.Button({
		Name = "SpinButton",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			return UDim2.fromOffset(
				Layout.BUTTON.X + Layout.BUTTON_SIZE.X / 2 + math.round(shake()),
				Layout.BUTTON.Y + Layout.BUTTON_SIZE.Y / 2 - math.round(hop())
			)
		end,
		Size = function()
			local j = jelly()
			return UDim2.fromOffset(
				math.round(Layout.BUTTON_SIZE.X * (1 + j)),
				math.round(Layout.BUTTON_SIZE.Y * (1 - 1.4 * j))
			)
		end,
		BackgroundTransparency = 1,
		ZIndex = 4,
		Activated = function()
			hand.Commit()
			if isLive() then strikeKick(-360) end
			actions.Spin()
		end,
		hand.Events,
		create("UIScale")({
			Scale = function()
				return hand.Scale() + beckonPop()
			end,
		}),
		-- The wobble's one ring, the slab's own outline grown off it.
		create("Frame")({
			Name = "Beckon",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = function()
				local grow = math.round(Timing.BECKON_REACH * Motion.Out(ring()))
				return UDim2.new(1, 2 * grow, 1, 2 * grow)
			end,
			BackgroundTransparency = 1,
			Visible = function()
				local t = ring()
				return t > 0 and t < 1
			end,
			create("UICorner")({ CornerRadius = UDim.new(0, 6) }),
			create("UIStroke")({
				Color = Palette.Green,
				Thickness = function()
					return 3 * (1 - ring()) + 1
				end,
				Transparency = ring,
			}),
		}),
		Components.Slab({
			Kind = function()
				local mode = state.Mode()
				if mode == "Spin" then return "Go" end
				return if mode == "Buy" then "Violet" else "Off"
			end,
			Marks = true,
			Brackets = true,
			GlowTransparency = function()
				return 0.6 - 0.3 * hand.Light() - Timing.BECKON_GLOW * Motion.Bump(beckoned())
			end,
		}, {
			Name = "Slab",
			Size = UDim2.fromScale(1, 1),
			Hand.WashLayer(hand, 4, 3),
			Components.Sheen(Hand.Sheen(hand, light), 4),
			create("Frame")({
				Name = "Content",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ZIndex = 5,
				create("UIListLayout")({
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, Layout.BUTTON_GAP),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
				Components.Picture(EIcons.Dice, {
					Name = "Die",
					LayoutOrder = 1,
					Size = Components.PictureBox(Layout.DIE),
					Rotation = function()
						return roll() + kick() + beckonRoll()
					end,
					ZIndex = 5,
				}),
				Components.Tracked("SPIN", Layout.BUTTON_TEXT, Layout.BUTTON_TRACKING, Font.Display, {
					Name = "Word",
					LayoutOrder = 2,
					ZIndex = 5,
				}),
				Components.Icon("Robux", {
					Name = "Robux",
					LayoutOrder = 3,
					Size = Components.GlyphBox(Layout.ROBUX),
					ImageColor3 = Palette.White,
					Visible = isBuy,
					ZIndex = 5,
				}),
				Parts.Label({
					Name = "Price",
					LayoutOrder = 4,
					AutomaticSize = Enum.AutomaticSize.X,
					Size = UDim2.fromOffset(0, Layout.BUTTON_TEXT),
					TextSize = Layout.BUTTON_TEXT,
					Visible = isBuy,
					ZIndex = 5,
					Text = tostring(SpinsCore.ROBUX),
				}),
			}),
		}),
	}) :: TextButton
end

-- How many spins are left, stinging white as the number changes.
local function spinsLeft(state: Types.TSpinsState): TextLabel
	local text = derive(function(): string
		local free = state.FreeLeft()
		if free > 0 then return `{plural(free, "FREE SPIN")} LEFT TODAY` end
		local bought = state.Bought()
		if bought > 0 then return `{plural(bought, "EXTRA SPIN")} LEFT` end
		return "NO FREE SPINS LEFT TODAY"
	end)
	local sting, strikeSting = Hand.Kick(Timing.STING_PERIOD, 1)
	local last = nil
	vide.effect(function()
		local current = text()
		vide.untrack(function()
			if last and current ~= last then strikeSting(1) end
			last = current
		end)
	end)

	return Parts.Label({
		Name = "SpinsLeft",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(Layout.SIZE.X / 2, Layout.LEFT_Y),
		Size = UDim2.fromOffset(600, Layout.LEFT_TEXT),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = Layout.LEFT_TEXT,
		TextColor3 = function()
			return Palette.Lavender:Lerp(Palette.White, math.clamp(sting(), 0, 1))
		end,
		Text = text,
	})
end

-- The page, standing `lift` px under its own place as the shell's panel changes shape; the prize's flight into the HUD,
-- to be laid over the shell's header; and the jackpot's shake across the page in px, for the shell to shake the panel
-- by too. All in his 1920 x 1080, unscaled.
function Screen.Build(
	state: Types.TSpinsState,
	actions: Types.TSpinsActions,
	lift: () -> number
): ({ Instance }, { Instance }, () -> number)
	-- Seconds since the screen opened or shut, held once every gesture is over, so the clock ticking for a spin works
	-- none of the open out again.
	local elapsed = derive(function(): number
		return math.min(state.Now() - state.ToggledAt(), Timing.SETTLED)
	end)
	-- Where the reel stands and how fast it turns, as X and Y: the reel and SPIN's die both read it.
	local reading = derive(function(): Vector2
		local offset, speed = ReelMotion.At(state.Spin(), state.Rest(), state.Now())
		return Vector2.new(offset, speed)
	end)
	-- How much of the screen is there, 0 to 1: its fade, on the clock both ways.
	local shown = derive(function(): number
		if state.IsOpen() then return Motion.Out(Progress(elapsed(), 0, Timing.FADE)) end
		return 1 - Progress(elapsed(), 0, Timing.CLOSE)
	end)
	-- How far under its place the panel is, in px, and the jackpot's shake across it.
	local drop = derive(function(): number
		if state.IsOpen() then return Timing.RISE * (1 - Motion.Decelerate(Progress(elapsed(), 0, Timing.OPEN))) end
		return Timing.SINK * Motion.Accelerate(Progress(elapsed(), 0, Timing.CLOSE))
	end)
	local shake = derive(function(): number
		local spin = state.Spin()
		local prize = if spin
				and spin.LandAt
				and spin.Prize
				and spin.Prize > 0
			then SpinsCore.PRIZES[spin.Prize]
			else nil
		if not prize or not prize.IsJackpot then return 0 end
		local t = state.Now() - (spin.LandAt :: number)
		if t < 0 or t > Timing.SHAKE_SECONDS then return 0 end
		return Timing.SHAKE * math.sin(t * Timing.SHAKE_RATE) * (1 - t / Timing.SHAKE_SECONDS) ^ 2
	end)
	local windowAt = function(): UDim2
		return UDim2.fromOffset(Layout.PANEL.X + math.round(shake()), Layout.PANEL.Y + math.round(lift() + drop()))
	end

	return {
		create("Frame")({
			Name = "Window",
			Position = windowAt,
			Size = UDim2.fromOffset(Layout.SIZE.X, Layout.SIZE.Y),
			BackgroundTransparency = 1,
			ZIndex = 2,
			Components.FadeGroup("Content", shown, {
				Position = UDim2.fromOffset(-Layout.MARGIN, -Layout.MARGIN),
				Size = UDim2.new(1, 2 * Layout.MARGIN, 1, 2 * Layout.MARGIN),
			}, {
				create("Frame")({
					Name = "Page",
					Position = UDim2.fromOffset(Layout.MARGIN, Layout.MARGIN),
					Size = UDim2.new(1, -2 * Layout.MARGIN, 1, -2 * Layout.MARGIN),
					BackgroundTransparency = 1,
					Reel.Build(state, reading, elapsed),
					spinsLeft(state),
					spinButton(state, actions, reading, elapsed),
					Components.Picture(EIcons.Stopwatch, {
						Name = "Watch",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromOffset(Layout.WATCH.X, Layout.WATCH.Y),
						Size = Components.PictureBox(Layout.WATCH_SIZE),
						ZIndex = 4,
					}),
					Parts.Label({
						Name = "Clock",
						Position = UDim2.fromOffset(Layout.CLOCK.X, Layout.CLOCK.Y),
						Size = UDim2.fromOffset(320, Layout.CLOCK_TEXT),
						TextSize = Layout.CLOCK_TEXT,
						TextColor3 = Palette.Lavender,
						Text = function()
							return `NEXT FREE SPIN  {formatCountdown(state.SecondsLeft())}`
						end,
					}),
				}),
			}),
			create("Frame")({
				Name = "Fx",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ZIndex = 3,
				Reel.BuildFx(state),
			}),
		}),
	},
		Payout.Build(state),
		shake
end

return Screen
