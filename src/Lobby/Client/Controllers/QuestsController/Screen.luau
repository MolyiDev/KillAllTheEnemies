--!nonstrict
-- The quests screen on his 1920 x 1080 (UIMatt.md, Quests - Daily / Weekly): the lobby dimmed as his lobby screens dim
-- it, the board's panel with its DAILY / WEEKLY tabs and reset clock, the board's five quests (Card), CLAIM ALL, and
-- EXIT. The HUD's Gems pill stays up over it as the screen's balance. The panel arrives first, its cards are dealt onto
-- it one under another, then the tabs, CLAIM ALL, and EXIT last.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local QuestsCore = require(ReplicatedStorage.GlobalShared.Core.QuestsCore)
local formatCountdown = require(ReplicatedStorage.GlobalShared.Utils.Functions.formatCountdown)
local Card = require(script.Parent.Card)
local Parts = require(script.Parent.Parts)
local Types = require(script.Parent.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
local spring = vide.spring
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress
local Label = Parts.Label

-- His drawn rects in px at 1080, from the screen's top left.
local Layout = table.freeze({
	PANEL = Vector2.new(299, Parts.PANEL_TOP),
	PANEL_SIZE = Vector2.new(1322, 772),
	-- The tabs' rects, their glyphs and words, and the pink slab gliding under the one on show. WEEKLY stands 22 px off
	-- DAILY (his 13): each tab's brackets stand up to 8 px out under the hand, and closer, the two tabs' corners crossed.
	TABS = { Vector2.new(327, 193), Vector2.new(591, 194) },
	TAB_SIZES = { Vector2.new(242, 62), Vector2.new(241, 60) },
	TAB_GLIDER = Vector2.new(242, 62),
	TAB_TEXT = 22,
	TAB_GLYPH = 22,
	-- The reset clock at the header's right, ending where the rule does, the stopwatch just left of the words.
	CLOCK_RIGHT = 1590,
	CLOCK_Y = 217,
	CLOCK_TEXT = 20,
	STOPWATCH_GLYPH = 22,
	STOPWATCH_GAP = 10,
	RULE = Vector2.new(330, 278),
	RULE_WIDTH = 1260,
	CARDS = Vector2.new(327, 300),
	CLAIM_ALL = Vector2.new(327, 846),
	CLAIM_ALL_SIZE = Vector2.new(1266, 71),
	CLAIM_ALL_TEXT = 28,
	CLAIM_ALL_CHECK = 26,
})

local Timing = table.freeze({
	-- His lobby screens dim the world this much (UIMatt.md section 2: 0.7 transparent).
	DIM = 0.3,
	PANEL_DELAY = 0,
	PANEL_RISE = 30,
	TABS_DELAY = 0.14,
	TABS_STAGGER = 0.05,
	TABS_DROP = 20,
	GLIDE_PERIOD = 0.28,
	GLIDE_DAMPING = 0.85,
	-- The cards grow onto their places one under another as the panel settles, and as a board is picked; the old
	-- board's shrink away first.
	DEAL_DELAY = 0.12,
	DEAL_STAGGER = 0.06,
	DEAL = 0.32,
	SWEEP = 0.12,
	-- The clock's words slide in as the board changes.
	CLOCK = 0.25,
	CLOCK_SLIDE = 14,
	-- CLAIM ALL rises in after the tabs, EXIT last.
	BOTTOM_DELAY = 0.24,
	RISE = 24,
	EXIT_DELAY = 0.28,
	-- A press on CLAIM ALL moves it by its width, so it takes this share of a button's reach, and goes in this much
	-- while the server is asked.
	CLAIM_ALL_REACH = 1 / 3,
	CLAIM_ALL_WIND = 0.02,
	-- CLAIM ALL's idle light: one crossing a period, half a period off the cards' own.
	IDLE_PERIOD = 2.6,
	IDLE_OFFSET = 1.3,
	IDLE_CROSS = 0.7,
	-- A count changing punches CLAIM ALL's number.
	COUNT_PERIOD = 0.3,
	COUNT_DAMPING = 0.5,
	COUNT_PUNCH = 0.35,
})

local lift = Parts.Lift

local Screen = {}

-- How long a board's deal and its bars' fill take, for the controller's clock.
Screen.DEAL_SECONDS = Timing.DEAL_DELAY
	+ Timing.SWEEP
	+ Timing.DEAL_STAGGER * (QuestsCore.BOARD_SIZE - 1)
	+ Timing.DEAL
	+ Card.FILL_SECONDS
	+ 0.4

-- The panel, its rule and the reset clock: they fade as one picture in a group with room for the panel's shadow.
local function panel(state: Types.TQuestsState, elapsed: () -> number): Frame
	local away = Parts.Away(state, elapsed, Timing.PANEL_DELAY)
	local faded = Parts.Faded(state, elapsed, Timing.PANEL_DELAY)
	local clockIn = derive(function(): number
		return Motion.Decelerate(Progress(state.Now(), state.BoardAt(), Timing.CLOCK))
	end)
	local clockFaded = function(): number
		return 1 - clockIn()
	end
	local margin = 40
	local origin = Layout.PANEL
	local clockY = Layout.CLOCK_Y - origin.Y

	return create("CanvasGroup")({
		Name = "Chrome",
		Position = function()
			return UDim2.fromOffset(
				origin.X - margin,
				origin.Y - lift() - margin + math.round(Timing.PANEL_RISE * away())
			)
		end,
		Size = function()
			return UDim2.fromOffset(Layout.PANEL_SIZE.X + 2 * margin, Layout.PANEL_SIZE.Y + lift() + 2 * margin)
		end,
		BackgroundTransparency = 1,
		GroupTransparency = faded,
		ZIndex = 2,
		Components.Panel({ Brackets = true, Tall = true, Wide = true }, {
			Name = "Panel",
			Position = UDim2.fromOffset(margin, margin),
			Size = function()
				return UDim2.fromOffset(Layout.PANEL_SIZE.X, Layout.PANEL_SIZE.Y + lift())
			end,
			-- Grows left from its right end as the words change; the stopwatch rides its left edge.
			Label({
				Name = "Clock",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = function()
					return UDim2.fromOffset(
						Layout.CLOCK_RIGHT - origin.X + math.round(Timing.CLOCK_SLIDE * clockFaded()),
						clockY
					)
				end,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, Layout.CLOCK_TEXT),
				TextSize = Layout.CLOCK_TEXT,
				TextColor3 = Palette.Gold,
				TextTransparency = clockFaded,
				Text = function()
					return `RESETS IN {formatCountdown(state.SecondsLeft())}`
				end,
				Components.Picture(EIcons.Stopwatch, {
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(0, -Layout.STOPWATCH_GAP, 0.5, 0),
					Size = Components.PictureBox(Layout.STOPWATCH_GLYPH),
					ImageTransparency = clockFaded,
					ZIndex = 4,
				}),
			}),
			create("Frame")({
				Name = "Rule",
				Position = UDim2.fromOffset(Layout.RULE.X - origin.X, Layout.RULE.Y - origin.Y),
				Size = UDim2.fromOffset(Layout.RULE_WIDTH, 1),
				BackgroundColor3 = Parts.RULE,
				BorderSizePixel = 0,
				ZIndex = 4,
			}),
		}),
	})
end

-- One tab and its word; and the hand's scale on it, which the glider takes while it lies on this tab.
local function tab(
	state: Types.TQuestsState,
	actions: Types.TQuestsActions,
	elapsed: () -> number,
	board: number
): ({ Instance }, () -> number)
	local delay = Timing.TABS_DELAY + Timing.TABS_STAGGER * (board - 1)
	local away = Parts.Away(state, elapsed, delay)
	local hand = Hand.React("Take", function(): boolean
		return state.Board() ~= board
	end)
	-- 1 on the board on show, gliding to 0 as another is picked: the word goes from lavender to white with it.
	local picked = spring(function(): number
		return if state.Board() == board then 1 else 0
	end, Timing.GLIDE_PERIOD, 1)
	local at, size = Layout.TABS[board], Layout.TAB_SIZES[board]
	local word = if board == 1 then "DAILY" else "WEEKLY"
	local position = function()
		return UDim2.fromOffset(at.X + size.X / 2, at.Y - lift() + size.Y / 2 - math.round(Timing.TABS_DROP * away()))
	end

	-- The word is its own piece over the glider, which slides between the plaque and it.
	local label = create("Frame")({
		Name = `{word}Word`,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundTransparency = 1,
		ZIndex = 5,
		create("UIScale")({
			Scale = function()
				return (1 - away()) * hand.Scale()
			end,
		}),
		create("Frame")({
			Name = "Word",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, Layout.TAB_TEXT),
			BackgroundTransparency = 1,
			create("UIListLayout")({
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 12),
			}),
			Components.Picture(if board == 1 then EIcons.Scroll else EIcons.Star, {
				LayoutOrder = 1,
				Size = Components.PictureBox(Layout.TAB_GLYPH),
				ImageColor3 = function()
					return Palette.Lavender:Lerp(Palette.White, picked())
				end,
			}),
			Label({
				LayoutOrder = 2,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, Layout.TAB_TEXT),
				TextSize = Layout.TAB_TEXT,
				TextColor3 = function()
					return Palette.Lavender:Lerp(Palette.White, picked())
				end,
				Text = word,
			}),
		}),
	})

	local button = Components.Button({
		Name = word,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Activated = function()
			if state.Board() == board then return end
			hand.Commit()
			actions.PickBoard(board)
		end,
		hand.Events,
		create("UIScale")({
			Scale = function()
				return (1 - away()) * hand.Scale()
			end,
		}),
		Parts.Plaque({
			Name = "Plaque",
			Size = UDim2.fromScale(1, 1),
			Components.Brackets(
				hand.Rise,
				function()
					return 0.6 - 0.3 * hand.Light()
				end,
				14,
				function()
					return state.Board() == board
				end
			),
			Hand.WashLayer(hand, 3, 2),
		}),
	}) :: TextButton

	return { button, label }, hand.Scale
end

-- The two tabs and his pink slab under the one on show: one piece gliding from tab to tab. No brackets of its own: the
-- tab's, under it, close round it, and two sets read as a double corner (UI.md).
local function tabs(state: Types.TQuestsState, actions: Types.TQuestsActions, elapsed: () -> number): { Instance }
	local away = Parts.Away(state, elapsed, Timing.TABS_DELAY)
	local glideX = spring(function(): number
		local at = Layout.TABS[state.Board()]
		return at.X + Layout.TAB_GLIDER.X / 2
	end, Timing.GLIDE_PERIOD, Timing.GLIDE_DAMPING)
	local centerY = Layout.TABS[1].Y + Layout.TAB_GLIDER.Y / 2

	local daily, dailyScale = tab(state, actions, elapsed, 1)
	local weekly, weeklyScale = tab(state, actions, elapsed, 2)
	local scales = { dailyScale, weeklyScale }

	return {
		daily,
		weekly,
		Components.Slab({
			Kind = "Pink",
			Marks = true,
		}, {
			Name = "Glider",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				return UDim2.fromOffset(math.round(glideX()), centerY - lift() - math.round(Timing.TABS_DROP * away()))
			end,
			Size = UDim2.fromOffset(Layout.TAB_GLIDER.X, Layout.TAB_GLIDER.Y),
			ZIndex = 4,
			-- It grows and presses with the tab it lies on, or the plaque under it shows round its edge.
			create("UIScale")({
				Scale = function()
					return (1 - away()) * scales[state.Board()]()
				end,
			}),
		}),
	}
end

-- One board's five cards, for vide.switch: dealt in when the board comes up and shrunk away when another does.
local function page(state: Types.TQuestsState, actions: Types.TQuestsActions, board: number, present: () -> boolean)
	-- When this page's cards start growing in: the later of the open and the pick of the board.
	local builtAt = os.clock()
	actions.Stir(Screen.DEAL_SECONDS)
	local function startsAt(order: number): number
		local from = math.max(state.OpenedAt() + Timing.DEAL_DELAY, builtAt + Timing.SWEEP)
		return from + Timing.DEAL_STAGGER * (order - 1)
	end
	local function dealt(order: number): () -> number
		return derive(function(): number
			if not present() then return 1 - Motion.Accelerate(Progress(state.Now(), state.BoardAt(), Timing.SWEEP)) end
			-- The cards are not under the panel's fade, so they shrink away with the shut on their own.
			if not state.IsOpen() then
				return 1 - Motion.Accelerate(Progress(state.Now(), state.ToggledAt(), Parts.Timing.CLOSE))
			end
			return Progress(state.Now(), startsAt(order), Timing.DEAL)
		end)
	end
	local function landsAt(order: number): () -> number
		return derive(function(): number
			return startsAt(order) + Timing.DEAL
		end)
	end

	local cards = table.create(QuestsCore.BOARD_SIZE)
	for slot = 1, QuestsCore.BOARD_SIZE do
		cards[slot] = Card.Build(state, actions, board, slot, dealt(slot), landsAt(slot))
	end

	return create("Frame")({
		Name = QuestsCore.BOARDS[board],
		Position = function()
			return UDim2.fromOffset(Layout.CARDS.X, Layout.CARDS.Y - lift())
		end,
		Size = UDim2.fromOffset(Card.SIZE.X, Card.SIZE.Y),
		BackgroundTransparency = 1,
		ZIndex = 3,
		cards,
	}),
		Timing.SWEEP + 0.02
end

local function claimAll(state: Types.TQuestsState, actions: Types.TQuestsActions, elapsed: () -> number): TextButton
	local away = Parts.Away(state, elapsed, Timing.BOTTOM_DELAY)
	local count = derive(function(): number
		return Parts.ReadyCount(state.Boards()[state.Board()])
	end)
	local isLive = derive(function(): boolean
		return count() > 0
	end)
	local hand = Hand.React("Operate", isLive)
	local punch, strikePunch = Hand.Kick(Timing.COUNT_PERIOD, Timing.COUNT_DAMPING)
	local last = nil
	vide.effect(function()
		local current = count()
		vide.untrack(function()
			if last and current ~= last then strikePunch(Timing.COUNT_PUNCH) end
			last = current
		end)
	end)
	local wind = derive(function(): number
		if state.PendingBoard() == 0 or state.PendingSlot() ~= 0 then return 0 end
		return Motion.Out(Progress(state.Now(), state.PressedAt(), Card.WIND_UP))
	end)
	local idle = derive(function(): number
		if not isLive() or state.PendingBoard() ~= 0 then return 1 end
		local phase = (state.Pulse() + Timing.IDLE_OFFSET) % Timing.IDLE_PERIOD
		return math.min(phase / Timing.IDLE_CROSS, 1)
	end)
	local textColor = function(): Color3
		return if isLive() then Palette.White else Palette.Lavender
	end
	local size = Layout.CLAIM_ALL_SIZE

	return Components.Button({
		Name = "ClaimAll",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			return UDim2.fromOffset(
				Layout.CLAIM_ALL.X + size.X / 2,
				Layout.CLAIM_ALL.Y + size.Y / 2 + math.round(Timing.RISE * away())
			)
		end,
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Activated = function()
			if isLive() then hand.Commit() end
			actions.ClaimAll()
		end,
		hand.Events,
		create("UIScale")({
			Scale = function()
				local handScale = 1 + (hand.Scale() - 1) * Timing.CLAIM_ALL_REACH
				return (1 - away()) * handScale * (1 - Timing.CLAIM_ALL_WIND * wind())
			end,
		}),
		Components.Slab({
			Kind = function()
				return if isLive() then "Go" else "Off"
			end,
			Marks = true,
			Brackets = hand.Rise,
			GlowTransparency = function()
				return 0.6 - 0.3 * hand.Light()
			end,
		}, {
			Name = "Slab",
			Size = UDim2.fromScale(1, 1),
			Hand.WashLayer(hand, 3, 3),
			Components.Sheen(function(): number
				local glint = hand.Glint()
				return if glint < 1 then glint else idle()
			end, 3),
			create("Frame")({
				Name = "Word",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, Layout.CLAIM_ALL_TEXT),
				BackgroundTransparency = 1,
				ZIndex = 4,
				create("UIListLayout")({
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 14),
				}),
				Components.Picture(EIcons.Check, {
					LayoutOrder = 1,
					Size = Components.PictureBox(Layout.CLAIM_ALL_CHECK),
					ImageColor3 = textColor,
				}),
				Components.Tracked("CLAIM ALL", Layout.CLAIM_ALL_TEXT, 2, Font.Display, {
					LayoutOrder = 2,
					Color = textColor,
				}),
				create("Frame")({
					LayoutOrder = 3,
					Size = UDim2.fromOffset(52, Layout.CLAIM_ALL_TEXT),
					BackgroundTransparency = 1,
					Label({
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.5),
						Size = UDim2.fromScale(1, 1),
						TextXAlignment = Enum.TextXAlignment.Center,
						TextYAlignment = Enum.TextYAlignment.Center,
						TextSize = Layout.CLAIM_ALL_TEXT,
						TextColor3 = textColor,
						Text = function()
							return `({count()})`
						end,
						create("UIScale")({
							Scale = function()
								return 1 + punch()
							end,
						}),
					}),
				}),
			}),
		}),
	}) :: TextButton
end

function Screen.Build(state: Types.TQuestsState, actions: Types.TQuestsActions): { any }
	local elapsed = Parts.Elapsed(state)
	local dimFaded = Parts.Faded(state, elapsed, 0)
	local pages = {}
	for board in QuestsCore.BOARDS do
		pages[board] = function(present)
			return page(state, actions, board, present)
		end
	end

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
		tabs(state, actions, elapsed),
		create("Frame")({
			Name = "Cards",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 3,
			vide.switch(state.Board)(pages),
		}),
		claimAll(state, actions, elapsed),
		Components.Exit(Parts.Away(state, elapsed, Timing.EXIT_DELAY), actions.Close),
	}
end

return Screen
