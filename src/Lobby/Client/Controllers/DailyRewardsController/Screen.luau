--!nonstrict
-- The daily rewards screen on his 1920 x 1080 (UIMatt.md, Daily Rewards): the lobby dimmed, his panel with the title,
-- the streak and the close button, the four week tabs between their arrows, the week's cards (Cards) and the time to
-- the next reward. The panel rises into place, the header slides in and its rule draws out, the tabs drop in, the
-- cards are dealt and the timer comes up last. Closed by its X or a click on the dim.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local DailyRewardsCore = require(ReplicatedStorage.Shared.Core.DailyRewardsCore)
local Cards = require(script.Parent.Cards)
local Parts = require(script.Parent.Parts)
local Types = require(script.Parent.Types)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress
local Label = Parts.Label

-- His drawn rects in px at 1080, from the screen's top left.
local Layout = table.freeze({
	PANEL = Vector2.new(301, 100),
	PANEL_SIZE = Vector2.new(1318, 880),
	PANEL_BRACKETS = 5,
	-- The room round the panel inside the group that fades it, for its shadow and brackets.
	MARGIN = 48,
	STAR = Vector2.new(349.5, 148),
	STAR_GLYPH = 30,
	TITLE = Vector2.new(382, 126),
	TITLE_TEXT = 44,
	-- The streak's right edge (his words end there), its top and letters.
	STREAK_RIGHT = 1506,
	STREAK_TOP = 138,
	STREAK_TEXT = 20,
	RULE = Vector2.new(332, 196),
	RULE_WIDTH = 1256,
	CLOSE = Vector2.new(1531, 115),
	CLOSE_SIZE = 66,
	CLOSE_BAR = Vector2.new(23, 2),
	-- The week row: the arrows' corners and side, the tabs' lefts, top and size (the picked one is his pink slab, a px
	-- bigger all round), the lock and the words.
	PREVIOUS = Vector2.new(510, 216),
	NEXT = Vector2.new(1354, 216),
	ARROW = 56,
	CHEVRON_BAR = Vector2.new(11, 2),
	TAB_XS = { 581, 774, 966, 1158 },
	TAB_TOP = 216,
	TAB_SIZE = Vector2.new(180, 56),
	TAB_BRACKETS = 4,
	TAB_BRACKET_LENGTH = 14,
	TAB_TEXT = 21,
	LOCK_GLYPH = 14,
	LOCK_GAP = 13,
	-- The timer: its plate, the stopwatch's middle and the words' corner.
	TIMER = Vector2.new(700, 852),
	TIMER_SIZE = Vector2.new(520, 64),
	TIMER_BRACKETS = 5,
	WATCH = Vector2.new(794.5, 883),
	WATCH_GLYPH = 19,
	TIMER_WORDS = Vector2.new(818.5, 872),
	TIMER_TEXT = 23,
})

local Timing = table.freeze({
	-- His lobby screens dim the world this much (UIMatt.md section 2: 0.7 transparent).
	DIM = 0.3,
	TITLE_DELAY = 0.06,
	TITLE = 0.32,
	TITLE_SLIDE = 22,
	RULE_DELAY = 0.1,
	RULE = 0.45,
	STREAK_DELAY = 0.16,
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
	HOVER_BRACKETS = 3,
})

local Screen = {}

-- A key a claim's beats are timed on, for the controller.
Screen.IMPACT_SECONDS = Cards.IMPACT_SECONDS
Screen.CLAIM_SECONDS = Cards.CLAIM_SECONDS
Screen.TURN_SECONDS = Cards.TURN_SECONDS
Screen.WIND_UP_SECONDS = Cards.WIND_UP_SECONDS
Screen.CALL_SECONDS = Cards.CALL_SECONDS

-- The furthest week that may be looked at: the one he is in and the one after it.
function Screen.LastOpenWeek(day: number): number
	return math.min(DailyRewardsCore.WEEKS, DailyRewardsCore.WeekOf(day) + 1)
end

-- "13:24:58".
local function clock(seconds: number): string
	return string.format("%02d:%02d:%02d", seconds // 3600, seconds // 60 % 60, seconds % 60)
end

-- His pink square with a thin white X. Under the hand it grows a little and the X turns a quarter; pressed, it dips.
local function closeButton(actions: Types.TDailyActions): TextButton
	local events, isHovered, isPressed = Hand.Track()
	local hover = Hand.Spring(function()
		return if isHovered() then 1 else 0
	end, 0.22, 0.85)
	local scale = Hand.Spring(function()
		return if isPressed() then 0.93 elseif isHovered() then 1.06 else 1
	end, 0.16, 0.85)

	local function bar(rotation: number): Frame
		return create("Frame")({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(Layout.CLOSE_BAR.X, Layout.CLOSE_BAR.Y),
			Rotation = function()
				return rotation + 90 * hover()
			end,
			BackgroundColor3 = Palette.White,
			BorderSizePixel = 0,
			ZIndex = 2,
		})
	end

	return Components.Button({
		Name = "Close",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(
			Layout.CLOSE.X - Layout.PANEL.X + Layout.CLOSE_SIZE / 2,
			Layout.CLOSE.Y - Layout.PANEL.Y + Layout.CLOSE_SIZE / 2
		),
		Size = UDim2.fromOffset(Layout.CLOSE_SIZE, Layout.CLOSE_SIZE),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Activated = actions.Close,
		events,
		create("UIScale")({ Scale = scale }),
		Components.Slab({
			Kind = "Pink",
			GlowTransparency = function()
				return Motion.Lerp(0.6, 0.4, hover())
			end,
		}, {
			Name = "Face",
			Size = UDim2.fromScale(1, 1),
			bar(45),
			bar(-45),
		}),
	}) :: TextButton
end

-- The panel, its header and the close button, faded as one picture.
local function chrome(
	state: Types.TDailyState,
	actions: Types.TDailyActions,
	elapsed: () -> number,
	shown: () -> number
): CanvasGroup
	local away = function(): number
		if not state.IsOpen() then return 0 end
		return 1 - Motion.Decelerate(Progress(elapsed(), Timing.TITLE_DELAY, Timing.TITLE))
	end
	local streakFaded = Parts.Faded(state, elapsed, Timing.STREAK_DELAY)
	local drawn = Parts.Since(state, elapsed, Timing.RULE_DELAY, Timing.RULE)
	local corner = Layout.PANEL

	return create("CanvasGroup")({
		Name = "Chrome",
		Position = UDim2.fromOffset(corner.X - Layout.MARGIN, corner.Y - Layout.MARGIN),
		Size = UDim2.fromOffset(Layout.PANEL_SIZE.X + 2 * Layout.MARGIN, Layout.PANEL_SIZE.Y + 2 * Layout.MARGIN),
		BackgroundTransparency = 1,
		GroupTransparency = function()
			return 1 - shown()
		end,
		Components.Panel({
			Brackets = Layout.PANEL_BRACKETS,
			TexturePhase = Vector2.zero,
			Wide = true,
			Tall = true,
		}, {
			Name = "Panel",
			Position = UDim2.fromOffset(Layout.MARGIN, Layout.MARGIN),
			Size = UDim2.fromOffset(Layout.PANEL_SIZE.X, Layout.PANEL_SIZE.Y),
			create("Frame")({
				Name = "Header",
				Size = UDim2.new(1, 0, 0, Layout.RULE.Y - corner.Y),
				BackgroundTransparency = 1,
				ClipsDescendants = true,
				ZIndex = 2,
				create("Frame")({
					Name = "Title",
					Position = function()
						return UDim2.fromOffset(-math.round(Timing.TITLE_SLIDE * away()), 0)
					end,
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					Components.Icon("Star", {
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromOffset(Layout.STAR.X - corner.X, Layout.STAR.Y - corner.Y),
						Size = Components.GlyphBox(Layout.STAR_GLYPH),
						ImageColor3 = Palette.Pink,
						ImageTransparency = away,
						ZIndex = 2,
					}),
					Label({
						Position = UDim2.fromOffset(Layout.TITLE.X - corner.X, Layout.TITLE.Y - corner.Y),
						Size = UDim2.fromOffset(500, Layout.TITLE_TEXT),
						TextXAlignment = Enum.TextXAlignment.Left,
						TextSize = Layout.TITLE_TEXT,
						TextTransparency = away,
						Text = "DAILY REWARDS",
						ZIndex = 2,
					}),
				}),
			}),
			Label({
				Name = "Streak",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromOffset(Layout.STREAK_RIGHT - corner.X, Layout.STREAK_TOP - corner.Y),
				Size = UDim2.fromOffset(300, Layout.STREAK_TEXT),
				TextXAlignment = Enum.TextXAlignment.Right,
				TextSize = Layout.STREAK_TEXT,
				TextColor3 = Palette.Gold,
				TextTransparency = streakFaded,
				Text = function()
					return `DAY {state.Day()} STREAK`
				end,
				ZIndex = 2,
			}),
			Parts.Rule(UDim2.fromOffset(Layout.RULE.X - corner.X, Layout.RULE.Y - corner.Y), Layout.RULE_WIDTH, drawn),
			closeButton(actions),
		}),
	})
end

-- One of the arrows: his dark square with a lavender chevron; it steps a week that way.
local function arrow(state: Types.TDailyState, actions: Types.TDailyActions, step: number, faded: () -> number)
	local target = function(): number
		return state.Week() + step
	end
	local isLive = function(): boolean
		local week = target()
		return week >= 1 and week <= Screen.LastOpenWeek(state.Day())
	end
	local hand = Hand.React("Operate", isLive)
	local at = if step < 0 then Layout.PREVIOUS else Layout.NEXT

	local function bar(turn: number, rise: number): Frame
		return create("Frame")({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, rise * 3.5),
			Size = UDim2.fromOffset(Layout.CHEVRON_BAR.X, Layout.CHEVRON_BAR.Y),
			Rotation = turn,
			BackgroundColor3 = Palette.Lavender,
			BorderSizePixel = 0,
			ZIndex = 4,
			create("UICorner")({ CornerRadius = UDim.new(0, 1) }),
		})
	end
	-- A chevron pointing `step`'s way: two bars meeting at its tip.
	local sign = if step < 0 then 1 else -1

	return Components.Button({
		Name = if step < 0 then "Previous" else "Next",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(at.X + Layout.ARROW / 2, at.Y + Layout.ARROW / 2),
		Size = UDim2.fromOffset(Layout.ARROW, Layout.ARROW),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Activated = function()
			local week = target()
			if week < 1 or week > DailyRewardsCore.WEEKS then return end
			hand.Commit()
			actions.PickWeek(week)
		end,
		hand.Events,
		create("CanvasGroup")({
			Name = "Group",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, 24, 1, 24),
			BackgroundTransparency = 1,
			GroupTransparency = faded,
			Components.Panel({}, {
				Name = "Face",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(Layout.ARROW, Layout.ARROW),
				create("UIScale")({ Scale = hand.Scale }),
				Hand.WashLayer(hand, 3, 2),
				create("Frame")({
					Name = "Chevron",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromOffset(12, 12),
					BackgroundTransparency = 1,
					ZIndex = 4,
					bar(-45 * sign, -1),
					bar(45 * sign, 1),
				}),
			}),
		}),
	})
end

-- One week's tab: his dark plate with the week in lavender, a lock on a week not open yet. The picked one wears the
-- pink slab gliding over the row.
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
					Components.Brackets(function()
						return Layout.TAB_BRACKETS + Timing.HOVER_BRACKETS * hand.Rise()
					end, function()
						return 0.6 - 0.3 * hand.Light()
					end, Layout.TAB_BRACKET_LENGTH),
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
			Components.Icon("Lock", {
				LayoutOrder = 1,
				Size = Components.GlyphBox(Layout.LOCK_GLYPH),
				ImageColor3 = Palette.Lavender,
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

	return { button, words }
end

-- The picked week's pink slab, gliding to each tab picked.
local function pickedSlab(state: Types.TDailyState, elapsed: () -> number, faded: () -> number): Frame
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
		Components.Slab({ Kind = "Pink", Brackets = Layout.TAB_BRACKETS }, {
			Name = "Slab",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(Layout.TAB_SIZE.X + 2, Layout.TAB_SIZE.Y + 2),
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
		Components.Panel({ Brackets = Layout.TIMER_BRACKETS }, {
			Name = "Plate",
			Position = UDim2.fromOffset(Layout.MARGIN, Layout.MARGIN),
			Size = UDim2.fromOffset(Layout.TIMER_SIZE.X, Layout.TIMER_SIZE.Y),
			Components.Icon("Stopwatch", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(Layout.WATCH.X - Layout.TIMER.X, Layout.WATCH.Y - Layout.TIMER.Y),
				Size = Components.GlyphBox(Layout.WATCH_GLYPH),
				ImageColor3 = Palette.Lavender,
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
					return `NEXT REWARD IN  {clock(state.SecondsLeft())}`
				end,
			}),
		}),
	})
end

-- The screen, built once. Returns its pieces and each card's gem glyph by its place in the week.
function Screen.Build(state: Types.TDailyState, actions: Types.TDailyActions): ({ Instance }, { ImageLabel })
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
	for week = 1, DailyRewardsCore.WEEKS do
		tabs[week] = tab(state, actions, elapsed, week, tabsFaded)
	end

	return {
		-- Modal: in first person the engine holds the mouse at the centre unless a visible button says otherwise.
		create("TextButton")({
			Name = "Dim",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(),
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Modal = true,
			Text = "",
			BackgroundTransparency = function()
				return 1 - Timing.DIM * shown()
			end,
			Activated = actions.Close,
		}),
		create("Frame")({
			Name = "Root",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(1920, 1080),
			BackgroundTransparency = 1,
			ZIndex = 2,
			create("UIScale")({ Scale = state.Scale }),
			create("Frame")({
				Name = "Window",
				Position = function()
					return UDim2.fromOffset(0, math.round(drop()))
				end,
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				-- A press on the panel stops here. A Frame lets it through to the dim, which would shut the screen.
				create("TextButton")({
					Name = "Sink",
					Position = UDim2.fromOffset(Layout.PANEL.X, Layout.PANEL.Y),
					Size = UDim2.fromOffset(Layout.PANEL_SIZE.X, Layout.PANEL_SIZE.Y),
					BackgroundTransparency = 1,
					AutoButtonColor = false,
					Text = "",
				}),
				chrome(state, actions, elapsed, shown),
				arrow(state, actions, -1, tabsFaded),
				tabs,
				pickedSlab(state, elapsed, tabsFaded),
				arrow(state, actions, 1, tabsFaded),
				cards,
				timer(state, elapsed, shown),
			}),
		}),
	},
		glyphs
end

return Screen
