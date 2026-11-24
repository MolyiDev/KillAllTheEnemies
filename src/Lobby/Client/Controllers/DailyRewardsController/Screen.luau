--!nonstrict
-- The daily rewards page of the daily screen on his 1920 x 1080 (UIMatt.md, Daily Rewards): the four week tabs, the
-- week's cards (Cards) and the time to the next reward, on the panel DailyController draws (with the header, EXIT and
-- the dim) and riding its top as it changes shape. The page rises in, the tabs drop in, the
-- cards are dealt and the timer comes up last; it sinks and fades as the other tab is picked or the screen shuts.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local DailyRewardsCore = require(ReplicatedStorage.Shared.Core.DailyRewardsCore)
local formatCountdown = require(ReplicatedStorage.GlobalShared.Utils.Functions.formatCountdown)
local Cards = require(script.Parent.Cards)
local Parts = require(script.Parent.Parts)
local Types = require(script.Parent.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress
local Label = Parts.Label

-- His drawn rects in px at 1080, from the screen's top left.
local Layout = table.freeze({
	-- The room round the timer inside the group that fades it, for its shadow and brackets.
	MARGIN = 48,
	-- The week row: the tabs' lefts, top and size (the picked one is his pink slab, a px bigger all round), the lock and
	-- the words. His arrows are left out (a tab is one press away), and his tabs stand centred 24 px apart rather than
	-- 12: a tab's brackets stand up to 7 px out under the hand, and closer, two tabs' corners crossed.
	TAB_XS = { 564, 768, 972, 1176 },
	TAB_TOP = 216,
	TAB_SIZE = Vector2.new(180, 56),
	TAB_BRACKET_LENGTH = 14,
	TAB_TEXT = 21,
	LOCK_GLYPH = 14,
	LOCK_GAP = 13,
	-- The timer: its plate, the stopwatch's middle and the words' corner. The plate stands 28 px under the cards, as the
	-- cards stand under the week row, and 30 over the panel's foot, which ends above EXIT.
	TIMER = Vector2.new(700, 846),
	TIMER_SIZE = Vector2.new(520, 64),
	WATCH = Vector2.new(794.5, 877),
	WATCH_GLYPH = 19,
	TIMER_WORDS = Vector2.new(818.5, 866),
	TIMER_TEXT = 23,
})

local Timing = table.freeze({
	TABS_DELAY = 0.12,
	TABS_STAGGER = 0.04,
	TABS_DROP = 22,
	TIMER_DELAY = 0.5,
	TIMER_RISE = 20,
	-- The picked tab's slab glides to the next one picked: a movement, so it ticks a little past its mark.
	PICK_PERIOD = 0.3,
	PICK_DAMPING = 0.72,
	REFUSE = 0.42,
	REFUSE_SHAKE = 8,
})

local Screen = {}

-- A key a claim's beats are timed on, for the controller.
Screen.IMPACT_SECONDS = Cards.IMPACT_SECONDS
Screen.CLAIM_SECONDS = Cards.CLAIM_SECONDS
Screen.TURN_SECONDS = Cards.TURN_SECONDS
Screen.WIND_UP_SECONDS = Cards.WIND_UP_SECONDS
Screen.CALL_SECONDS = Cards.CALL_SECONDS
Screen.WINK_AFTER_TURN_SECONDS = Cards.WINK_AFTER_TURN_SECONDS

-- The furthest week that may be looked at: the one he is in and the one after it.
function Screen.LastOpenWeek(day: number): number
	return math.min(DailyRewardsCore.WEEKS, DailyRewardsCore.WeekOf(day) + 1)
end

-- One week's tab: his dark plate with the week in lavender, a lock on a week not open yet. The picked one wears the
-- pink slab gliding over the row, and its brackets close round it.
local function tab(
	state: Types.TDailyState,
	actions: Types.TDailyActions,
	elapsed: () -> number,
	week: number,
	faded: () -> number
)
	local isOpen = function(): boolean
		return week <= Screen.LastOpenWeek(state.Day())
	end
	local isPicked = derive(function(): boolean
		return state.Week() == week
	end)
	local hand = Hand.React("Operate", function()
		return isOpen() and not isPicked()
	end)
	local x = Layout.TAB_XS[week]
	local drop = Parts.Away(state, elapsed, Timing.TABS_DELAY + Timing.TABS_STAGGER * week)
	local position = function(): UDim2
		local shake = 0
		if state.Refused() == -week then
			local at = state.RefusedAt()
			shake = Timing.REFUSE_SHAKE * Motion.Shake(Progress(state.Now(), at, Timing.REFUSE), at)
		end
		return UDim2.fromOffset(
			x + Layout.TAB_SIZE.X / 2 + math.round(shake),
			Layout.TAB_TOP + Layout.TAB_SIZE.Y / 2 - math.round(Timing.TABS_DROP * drop())
		)
	end

	local button = Components.Button({
		Name = `Week{week}`,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(Layout.TAB_SIZE.X, Layout.TAB_SIZE.Y),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Activated = function()
			if not isOpen() then
				actions.Refuse(-week)
				return
			end
			if isPicked() then return end
			hand.Commit()
			actions.PickWeek(week)
		end,
		hand.Events,
		create("CanvasGroup")({
			Name = "Group",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, 40, 1, 40),
			BackgroundTransparency = 1,
			GroupTransparency = faded,
			Components.Panel({}, {
				Name = "Face",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(Layout.TAB_SIZE.X, Layout.TAB_SIZE.Y),
				create("UIScale")({ Scale = hand.Scale }),
				Hand.WashLayer(hand, 3, 2),
				create("Frame")({
					Name = "BracketsHolder",
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					Components.Brackets(hand.Rise, function()
						return 0.6 - 0.3 * hand.Light()
					end, Layout.TAB_BRACKET_LENGTH, isPicked),
				}),
			}),
		}),
	})

	-- Over the slab that glides under the row, so the words are always on top; they ride the tab's press.
	local words = create("Frame")({
		Name = `Week{week}Words`,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(Layout.TAB_SIZE.X, Layout.TAB_SIZE.Y),
		BackgroundTransparency = 1,
		ZIndex = 5,
		create("UIScale")({ Scale = hand.Scale }),
		create("Frame")({
			Name = "Row",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			create("UIListLayout")({
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, Layout.LOCK_GAP),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Components.Picture(EIcons.Lock, {
				LayoutOrder = 1,
				Size = Components.PictureBox(Layout.LOCK_GLYPH),
				ImageTransparency = faded,
				Visible = function()
					return not isOpen()
				end,
			}),
			Label({
				LayoutOrder = 2,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, Layout.TAB_TEXT),
				TextSize = Layout.TAB_TEXT,
				TextColor3 = function()
					return if isPicked() then Palette.White else Palette.Lavender
				end,
				TextTransparency = faded,
				Text = `WEEK {week}`,
			}),
		}),
	})

	return { button, words }, hand.Scale
end

-- The picked week's pink slab, gliding to each tab picked. No brackets of its own: the tab's, under it, close round
-- it, and two sets read as a double corner (UI.md). It grows and presses with the tab it lies on (`scales`, each
-- tab's hand), or the plate under it shows round its edge.
local function pickedSlab(
	state: Types.TDailyState,
	elapsed: () -> number,
	faded: () -> number,
	scales: { () -> number }
): Frame
	local x = Hand.Spring(function()
		return Layout.TAB_XS[state.Week()]
	end, Timing.PICK_PERIOD, Timing.PICK_DAMPING)
	-- It drops in with the first tab, the one it opens on being picked a moment later at most.
	local drop = Parts.Away(state, elapsed, Timing.TABS_DELAY + Timing.TABS_STAGGER)

	return create("CanvasGroup")({
		Name = "Picked",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			return UDim2.fromOffset(
				math.round(x()) + Layout.TAB_SIZE.X / 2,
				Layout.TAB_TOP + Layout.TAB_SIZE.Y / 2 - math.round(Timing.TABS_DROP * drop())
			)
		end,
		Size = UDim2.fromOffset(Layout.TAB_SIZE.X + 60, Layout.TAB_SIZE.Y + 60),
		BackgroundTransparency = 1,
		GroupTransparency = faded,
		ZIndex = 4,
		Components.Slab({ Kind = "Pink" }, {
			Name = "Slab",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(Layout.TAB_SIZE.X + 2, Layout.TAB_SIZE.Y + 2),
			create("UIScale")({
				Scale = function()
					return scales[state.Week()]()
				end,
			}),
		}),
	})
end

local function timer(state: Types.TDailyState, elapsed: () -> number, shown: () -> number): Frame
	local away = Parts.Away(state, elapsed, Timing.TIMER_DELAY)
	local faded = Parts.FadedOut(state, elapsed, shown, Timing.TIMER_DELAY)

	return create("CanvasGroup")({
		Name = "Timer",
		Position = function()
			return UDim2.fromOffset(
				Layout.TIMER.X - Layout.MARGIN,
				Layout.TIMER.Y - Layout.MARGIN + math.round(Timing.TIMER_RISE * away())
			)
		end,
		Size = UDim2.fromOffset(Layout.TIMER_SIZE.X + 2 * Layout.MARGIN, Layout.TIMER_SIZE.Y + 2 * Layout.MARGIN),
		BackgroundTransparency = 1,
		GroupTransparency = faded,
		ZIndex = 3,
		Components.Panel({ Brackets = true }, {
			Name = "Plate",
			Position = UDim2.fromOffset(Layout.MARGIN, Layout.MARGIN),
			Size = UDim2.fromOffset(Layout.TIMER_SIZE.X, Layout.TIMER_SIZE.Y),
			Components.Picture(EIcons.Stopwatch, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(Layout.WATCH.X - Layout.TIMER.X, Layout.WATCH.Y - Layout.TIMER.Y),
				Size = Components.PictureBox(Layout.WATCH_GLYPH),
				ZIndex = 4,
			}),
			Label({
				Position = UDim2.fromOffset(
					Layout.TIMER_WORDS.X - Layout.TIMER.X,
					Layout.TIMER_WORDS.Y - Layout.TIMER.Y
				),
				Size = UDim2.fromOffset(380, Layout.TIMER_TEXT),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextSize = Layout.TIMER_TEXT,
				TextColor3 = Palette.Lavender,
				Text = function()
					return `NEXT REWARD IN  {formatCountdown(state.SecondsLeft())}`
				end,
			}),
		}),
	})
end

-- The page, built once: his 1920 x 1080 unscaled (the shell scales and cuts it), standing `lift` px under its own place
-- as the shell's panel changes shape. Returns its pieces and each card's gem glyph by its place in the week.
function Screen.Build(
	state: Types.TDailyState,
	actions: Types.TDailyActions,
	lift: () -> number
): ({ Instance }, { ImageLabel })
	local elapsed = Parts.Elapsed(state)
	local shown = Parts.Shown(state, elapsed)
	-- How far under its place the window is, in px: up decelerating as it opens, down accelerating as it shuts.
	local drop = derive(function(): number
		if state.IsOpen() then
			return Parts.Timing.RISE * (1 - Motion.Decelerate(Progress(elapsed(), 0, Parts.Timing.OPEN)))
		end
		return Parts.Timing.SINK * Motion.Accelerate(Progress(elapsed(), 0, Parts.Timing.CLOSE))
	end)
	local tabsFaded = Parts.FadedOut(state, elapsed, shown, Timing.TABS_DELAY)

	local cards, glyphs = Cards.Build(state, actions, elapsed, shown)
	local tabs = table.create(DailyRewardsCore.WEEKS)
	local scales = table.create(DailyRewardsCore.WEEKS)
	for week = 1, DailyRewardsCore.WEEKS do
		tabs[week], scales[week] = tab(state, actions, elapsed, week, tabsFaded)
	end

	return {
		create("Frame")({
			Name = "Root",
			Size = UDim2.fromOffset(1920, 1080),
			BackgroundTransparency = 1,
			create("Frame")({
				Name = "Window",
				Position = function()
					return UDim2.fromOffset(0, math.round(drop() + lift()))
				end,
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				tabs,
				pickedSlab(state, elapsed, tabsFaded, scales),
				cards,
				timer(state, elapsed, shown),
			}),
		}),
	},
		glyphs
end

return Screen
