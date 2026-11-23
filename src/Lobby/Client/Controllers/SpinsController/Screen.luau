--!nonstrict
-- The spins screen on his 1920 x 1080 (UIMatt.md, Daily Spins): the lobby dimmed, his panel under the daily rewards'
-- header (the pink glyph, SPINS, the rule), the reel (Reel), how many spins are left, SPIN and the time to the next free ones; the prize flies out of it
-- into the HUD (Payout). The panel rises into place as it fades in, the cards fall into the well from the middle out
-- and the pointer drops onto them; it sinks and fades on the way out.
--
-- His DAILY | SPIN tabs are not drawn: the daily rewards are a screen of their own, and the two screens share that
-- header instead. His token balance (bottom right) is left out: the prizes are Gems and XP, and the HUD's pill already
-- shows the Gems.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local SpinsCore = require(ReplicatedStorage.Shared.Core.SpinsCore)
local Payout = require(script.Parent.Payout)
local Parts = require(script.Parent.Parts)
local Reel = require(script.Parent.Reel)
local ReelMotion = require(script.Parent.ReelMotion)
local Types = require(script.Parent.Types)

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
	PANEL_BRACKETS = 5,
	-- The header, as the daily rewards draw theirs: the glyph's middle and longer side, the title's corner and letter
	-- height, the gold words by their right end, the X, and the rule under it all.
	GLYPH = Vector2.new(48.5, 48),
	GLYPH_SIZE = 30,
	TITLE = Vector2.new(81, 26),
	TITLE_TEXT = 44,
	HEADER_RIGHT = 1187,
	HEADER_Y = 38,
	HEADER_TEXT = 20,
	CLOSE = Vector2.new(1212, 15),
	CLOSE_SIZE = 66,
	CLOSE_BAR = Vector2.new(23, 2),
	RULE = Vector2.new(31, 96),
	RULE_WIDTH = 1238,
	-- Under the reel: the spins left (centred), SPIN, the clock.
	LEFT_Y = 388,
	LEFT_TEXT = 22,
	BUTTON = Vector2.new(459, 430),
	BUTTON_SIZE = Vector2.new(382, 82),
	BUTTON_BRACKETS = 5,
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

-- His rule's lavender, sampled off the art.
local RULE = Color3.fromRGB(140, 111, 210)
local RULE_TRANSPARENCY = 0.55

local Timing = table.freeze({
	-- The panel decelerates up into place and accelerates down out of it, the exit the faster; its fade runs on the
	-- clock, not on the move.
	OPEN = 0.34,
	FADE = 0.27,
	RISE = 26,
	CLOSE = 0.2,
	SINK = 14,
	-- His lobby modals dim the world this much (UIMatt.md section 2: 0.7 transparent).
	DIM = 0.3,
	-- Every gesture of an open is over by now.
	SETTLED = 1.6,
	-- The header's words slide in from the left and the rule draws itself out under them.
	TITLE_DELAY = 0.06,
	TITLE = 0.32,
	TITLE_SLIDE = 22,
	RULE_DELAY = 0.1,
	RULE = 0.45,
	-- SPIN catches the light as the open lands, and again every INVITE seconds while a spin waits for it.
	SHEEN_DELAY = 0.45,
	SHEEN = 0.6,
	INVITE = 3,
	-- The spins left sting white when their number changes.
	STING_PERIOD = 0.35,
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

local function clock(seconds: number): string
	return string.format("%02d:%02d:%02d", seconds // 3600, seconds // 60 % 60, seconds % 60)
end

-- The daily rewards' header: the pink glyph and the title slide in from the left, the gold words beside the X, the
-- rule drawing itself out under them.
local function header(state: Types.TSpinsState, elapsed: () -> number): { Instance }
	local away = derive(function(): number
		if not state.IsOpen() then return 0 end
		return 1 - Motion.Decelerate(Progress(elapsed(), Timing.TITLE_DELAY, Timing.TITLE))
	end)
	local drawn = derive(function(): number
		if not state.IsOpen() then return 1 end
		return Motion.Decelerate(Progress(elapsed(), Timing.RULE_DELAY, Timing.RULE))
	end)

	return {
		create("Frame")({
			Name = "Header",
			Size = UDim2.new(1, 0, 0, Layout.RULE.Y),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = 3,
			create("Frame")({
				Name = "Title",
				Position = function()
					return UDim2.fromOffset(-math.round(Timing.TITLE_SLIDE * away()), 0)
				end,
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Components.Icon("Spin", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(Layout.GLYPH.X, Layout.GLYPH.Y),
					Size = Components.GlyphBox(Layout.GLYPH_SIZE),
					ImageColor3 = Palette.Pink,
					ImageTransparency = away,
					ZIndex = 4,
				}),
				Parts.Label({
					Position = UDim2.fromOffset(Layout.TITLE.X, Layout.TITLE.Y),
					Size = UDim2.fromOffset(500, Layout.TITLE_TEXT),
					TextSize = Layout.TITLE_TEXT,
					TextTransparency = away,
					Text = "SPINS",
				}),
			}),
		}),
		Parts.Label({
			Name = "FreeEveryDay",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromOffset(Layout.HEADER_RIGHT, Layout.HEADER_Y),
			Size = UDim2.fromOffset(400, Layout.HEADER_TEXT),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextSize = Layout.HEADER_TEXT,
			TextColor3 = Palette.Gold,
			TextTransparency = away,
			Text = `{SpinsCore.FREE_PER_DAY} FREE SPINS EVERY DAY`,
		}),
		create("Frame")({
			Name = "Rule",
			Position = UDim2.fromOffset(Layout.RULE.X, Layout.RULE.Y),
			Size = function()
				return UDim2.fromOffset(math.round(Layout.RULE_WIDTH * drawn()), 1)
			end,
			BackgroundColor3 = RULE,
			BackgroundTransparency = RULE_TRANSPARENCY,
			BorderSizePixel = 0,
			ZIndex = 3,
		}),
	}
end

-- His pink X: a slab with two white bars that turn a quarter under the hand.
local function closeButton(actions: Types.TSpinsActions): TextButton
	local hand = Hand.React("Operate")
	local function bar(rotation: number): Frame
		return create("Frame")({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(Layout.CLOSE_BAR.X, Layout.CLOSE_BAR.Y),
			Rotation = function()
				return rotation + 90 * hand.Rise()
			end,
			BackgroundColor3 = Palette.White,
			BorderSizePixel = 0,
			ZIndex = 5,
		})
	end

	return Components.Button({
		Name = "Close",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(Layout.CLOSE.X + Layout.CLOSE_SIZE / 2, Layout.CLOSE.Y + Layout.CLOSE_SIZE / 2),
		Size = UDim2.fromOffset(Layout.CLOSE_SIZE, Layout.CLOSE_SIZE),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Activated = function()
			hand.Commit()
			actions.Close()
		end,
		hand.Events,
		create("UIScale")({ Scale = hand.Scale }),
		Components.Slab({
			Kind = "Pink",
			GlowTransparency = function()
				return 0.6 - 0.25 * hand.Light()
			end,
		}, {
			Name = "Face",
			Size = UDim2.fromScale(1, 1),
			Hand.WashLayer(hand, 4, 3),
			bar(45),
			bar(-45),
		}),
	}) :: TextButton
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
	local light = function(): number
		local travel = math.min(invite(), 1)
		return if travel < 1 then travel else landed()
	end

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
				Layout.BUTTON.Y + Layout.BUTTON_SIZE.Y / 2
			)
		end,
		Size = UDim2.fromOffset(Layout.BUTTON_SIZE.X, Layout.BUTTON_SIZE.Y),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Activated = function()
			hand.Commit()
			if isLive() then strikeKick(-360) end
			actions.Spin()
		end,
		hand.Events,
		create("UIScale")({ Scale = hand.Scale }),
		Components.Slab({
			Kind = function()
				local mode = state.Mode()
				if mode == "Spin" then return "Go" end
				return if mode == "Buy" then "Violet" else "Off"
			end,
			Marks = true,
			Brackets = Layout.BUTTON_BRACKETS,
			GlowTransparency = function()
				return 0.6 - 0.3 * hand.Light()
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
				Components.Icon("Dice", {
					Name = "Die",
					LayoutOrder = 1,
					Size = Components.GlyphBox(Layout.DIE),
					ImageColor3 = Palette.White,
					Rotation = function()
						return roll() + kick()
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

function Screen.Build(state: Types.TSpinsState, actions: Types.TSpinsActions): { any }
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
		return UDim2.fromOffset(Layout.PANEL.X + math.round(shake()), Layout.PANEL.Y + math.round(drop()))
	end

	return {
		-- Past the screen's edges whatever its shape. A click on it shuts the screen, but never while the reel turns.
		create("TextButton")({
			Name = "Dim",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(4, 4),
			BackgroundColor3 = Color3.new(),
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Modal = true,
			Text = "",
			BackgroundTransparency = function()
				return 1 - Timing.DIM * shown()
			end,
			Activated = function()
				if state.Mode() ~= "Busy" then actions.Close() end
			end,
		}),
		create("Frame")({
			Name = "Window",
			Position = windowAt,
			Size = UDim2.fromOffset(Layout.SIZE.X, Layout.SIZE.Y),
			BackgroundTransparency = 1,
			ZIndex = 2,
			-- A press on the panel stops here. A Frame lets it through to the dim, which would shut the screen.
			create("TextButton")({
				Name = "Sink",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				AutoButtonColor = false,
				Text = "",
			}),
			create("CanvasGroup")({
				Name = "Chrome",
				Position = UDim2.fromOffset(-Layout.MARGIN, -Layout.MARGIN),
				Size = UDim2.new(1, 2 * Layout.MARGIN, 1, 2 * Layout.MARGIN),
				BackgroundTransparency = 1,
				GroupTransparency = function()
					return 1 - shown()
				end,
				-- Longer than the streak texture: its window starts at the corner and it is tiled across.
				Components.Panel(
					{ Brackets = Layout.PANEL_BRACKETS, TexturePhase = Vector2.zero, Wide = true, Tall = true },
					{
						Name = "Panel",
						Position = UDim2.fromOffset(Layout.MARGIN, Layout.MARGIN),
						Size = UDim2.new(1, -2 * Layout.MARGIN, 1, -2 * Layout.MARGIN),
						header(state, elapsed),
						closeButton(actions),
						Reel.Build(state, reading, elapsed),
						spinsLeft(state),
						spinButton(state, actions, reading, elapsed),
						Components.Icon("Stopwatch", {
							Name = "Watch",
							AnchorPoint = Vector2.new(0.5, 0.5),
							Position = UDim2.fromOffset(Layout.WATCH.X, Layout.WATCH.Y),
							Size = Components.GlyphBox(Layout.WATCH_SIZE),
							ImageColor3 = Palette.Lavender,
							ZIndex = 4,
						}),
						Parts.Label({
							Name = "Clock",
							Position = UDim2.fromOffset(Layout.CLOCK.X, Layout.CLOCK.Y),
							Size = UDim2.fromOffset(320, Layout.CLOCK_TEXT),
							TextSize = Layout.CLOCK_TEXT,
							TextColor3 = Palette.Lavender,
							Text = function()
								return `NEXT FREE SPIN  {clock(state.SecondsLeft())}`
							end,
						}),
					}
				),
			}),
			create("Frame")({
				Name = "Fx",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ZIndex = 3,
				Reel.BuildFx(state),
			}),
		}),
		Payout.Build(state),
	}
end

return Screen
