--!nonstrict
-- The daily screen round its two pages on his 1920 x 1080 (UIMatt.md, Daily Spins: his DAILY | SPIN tabbed modal): the
-- lobby dimmed, one panel that takes the shape of the page on show (his Daily Rewards rect for DAILY, his Daily Spins
-- rect for SPIN), and its header: the two tabs under his pink slab, the page's gold words, the rule; EXIT under it.
--
-- Three layers: the back (the dim and the panel), the pages seen through the panel under the rule, the front (the
-- header) over them, so a prize's rays never cross the tabs; the flights into the HUD go over all three.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local Types = require(script.Parent.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
local source = vide.source
local spring = vide.spring
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress

-- His drawn rects in px at 1080. The panel keeps its left and width on both pages (his two differ by 18 px, and the
-- SPIN page stands in the middle of it); its top and height are each page's, DAILY's 40 px shorter than his so it ends
-- above EXIT as the other lobby screens' panels do, SPIN's his for one reel and growing with more (the page's shape). The header is placed from the panel's top left: his tabs where his
-- Daily Spins draws them, the words and the rule where both his screens do. EXIT is on the screen, where every lobby
-- screen has it.
local Layout = table.freeze({
	PANEL_X = 301,
	PANEL_WIDTH = 1318,
	TOPS = { 100, 251 },
	HEIGHTS = { 840, 560 },
	-- The room round the panel and the header inside the groups that fade them, for the glow and the brackets.
	MARGIN = 48,
	-- How far down the panel the header reaches, past the rule, and where the pages are cut off above (under the rule).
	HEADER = 110,
	PAGES_TOP = 97,
	-- SPIN stands 22 px off DAILY (his 6): each tab's brackets stand up to 8 px out under the hand, and closer, the two
	-- tabs' corners crossed.
	TABS = { Vector2.new(45, 27), Vector2.new(253, 27) },
	TAB_SIZE = Vector2.new(186, 60),
	TAB_BRACKET_LENGTH = 14,
	TAB_TEXT = 22,
	TAB_GLYPH = 26,
	TAB_GAP = 12,
	-- The page's words end where the rule does.
	INFO_RIGHT = 1287,
	INFO_Y = 38,
	INFO_TEXT = 20,
	RULE = Vector2.new(31, 96),
	RULE_WIDTH = 1256,
	-- The light that runs along the rule as a page is picked.
	SWEEP_WIDTH = 240,
})

-- His rule's lavender, sampled off the art.
local RULE = Color3.fromRGB(140, 111, 210)
local RULE_TRANSPARENCY = 0.55

local Timing = table.freeze({
	-- His lobby modals dim the world this much (UIMatt.md section 2: 0.7 transparent).
	DIM = 0.3,
	-- The screen's open and shut (UI.md 5o): the panel decelerates up into place and accelerates down out of it, the
	-- exit the faster; its fade runs on the clock, not on the move.
	OPEN = 0.36,
	FADE = 0.28,
	RISE = 28,
	CLOSE = 0.2,
	SINK = 14,
	-- Every gesture of an open is over by now.
	SETTLED = 1.8,
	-- The header arrives after the panel: the tabs drop in one after the other, the words come up, the rule draws
	-- itself out. EXIT rises in last.
	TABS_DELAY = 0.06,
	TABS_STAGGER = 0.05,
	TABS_DROP = 20,
	SLIDE = 0.42,
	INFO_DELAY = 0.16,
	EXIT_DELAY = 0.22,
	RULE_DELAY = 0.1,
	RULE = 0.45,
	-- A page picked: the panel takes the new page's shape on a spring that carries a little past it (a movement, as
	-- the slab under the tabs), the slab glides, the words change places, a light runs down the rule.
	MORPH_PERIOD = 0.42,
	MORPH_DAMPING = 0.74,
	PICK_PERIOD = 0.3,
	PICK_DAMPING = 0.72,
	-- The words coming wait INFO_GAP for the ones going to lift most of the way, or the two lines cross in one place.
	INFO_IN = 0.3,
	INFO_OUT = 0.18,
	INFO_GAP = 0.12,
	INFO_TRAVEL = 16,
	SWEEP = 0.55,
	-- The picked tab's glyph: the gift hops, the wheel turns once.
	HOP = 8,
	HOP_PERIOD = 0.32,
	HOP_DAMPING = 0.45,
	SPIN_PERIOD = 0.9,
	SPIN_DAMPING = 0.85,
	-- A tab whose page has something waiting, off show: its glow lit this much, and the light crossing it in CALL
	-- seconds each time init calls.
	CALL = 0.7,
	CALL_GLOW = 0.3,
	REFUSE = 0.42,
	REFUSE_SHAKE = 8,
})

local Shell = {}

Shell.LEAVE_SECONDS = Timing.CLOSE
Shell.CALL_SECONDS = Timing.CALL

-- The panel's shape, 0 (DAILY's) to 1 (SPIN's) and a little past on the way: a spring toward the page on show, put on
-- it outright as the screen opens.
function Shell.Morph(state: Types.TDailyScreenState): () -> number
	local goal = derive(function(): number
		return if state.Tab() == 2 then 1 else 0
	end)
	local value, configure = spring(goal, Timing.MORPH_PERIOD, Timing.MORPH_DAMPING)
	local wasOpen = false
	-- Pinned on each change of target too: a spring heading back to 0 never settles (UI.md 5g).
	vide.effect(function()
		local target = goal()
		local isOpen = state.IsOpen()
		vide.untrack(function()
			if isOpen and not wasOpen then
				configure({ position = target, velocity = 0 })
			else
				configure({ position = value() })
			end
			wasOpen = isOpen
		end)
	end)

	return value
end

-- The panel's top in px at 1080 as it takes its shape: `spinShape` is the SPIN page's (its top and height).
function Shell.Top(morph: () -> number, spinShape: () -> Vector2): () -> number
	return derive(function(): number
		return Motion.Lerp(Layout.TOPS[1], spinShape().X, morph())
	end)
end

-- How far below its own place `tab`'s page stands, in px at 1080: it rides the panel's top while on show, and holds
-- where it was as it is taken off, so the panel closes round it (Build clips the pages to it) rather than carrying it.
function Shell.Lift(top: () -> number, tab: number, isShown: () -> boolean): () -> number
	local own = Layout.TOPS[tab]
	local held = source(0)
	vide.effect(function()
		local shown = isShown()
		vide.untrack(function()
			if not shown then held(top() - own) end
		end)
	end)

	return derive(function(): number
		if isShown() then return top() - own end
		return held()
	end)
end

-- Seconds since the screen opened or shut, held once every gesture is over.
local function elapsedOf(state: Types.TDailyScreenState): () -> number
	return derive(function(): number
		return math.min(state.Now() - state.ToggledAt(), Timing.SETTLED)
	end)
end

-- How far a header piece still has to come, 1 to 0, decelerating in after `delay`; 0 while the screen shuts (it rides
-- out with the panel).
local function away(state: Types.TDailyScreenState, elapsed: () -> number, delay: number): () -> number
	return derive(function(): number
		if not state.IsOpen() then return 0 end
		return 1 - Motion.Decelerate(Progress(elapsed(), delay, Timing.SLIDE))
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

-- One tab: his dark plate with the page's glyph and word, lavender off show and white on it, the pink slab gliding
-- under the one on show and its brackets closed round it. Returns its pieces and the hand's scale on it, which the slab
-- takes while it lies on this tab. Its word is a piece of its own over the slab, riding the plate's press. Off show with its
-- page waiting, it calls in light.
local function tab(
	state: Types.TDailyScreenState,
	actions: Types.TDailyScreenActions,
	pages: Types.TPagesInfo,
	elapsed: () -> number,
	index: number
): ({ Instance }, () -> number)
	local drop = away(state, elapsed, Timing.TABS_DELAY + Timing.TABS_STAGGER * (index - 1))
	local isPicked = derive(function(): boolean
		return state.Tab() == index
	end)
	local hand = Hand.React("Take", function(): boolean
		return not isPicked()
	end)
	-- 1 on the page on show, gliding to 0 as another is picked: the word and glyph go from lavender to white with it.
	local picked = Hand.Spring(function(): number
		return if state.Tab() == index then 1 else 0
	end, Timing.PICK_PERIOD)
	local hop, strikeHop = Hand.Kick(Timing.HOP_PERIOD, Timing.HOP_DAMPING)
	local turn, strikeTurn = Hand.Kick(Timing.SPIN_PERIOD, Timing.SPIN_DAMPING)
	-- On each pick of this tab, by the hand or by the screen moving on to SPIN by itself; never as the screen opens.
	vide.effect(function()
		local at = state.TabAt()
		vide.untrack(function()
			if state.Tab() ~= index or at == -math.huge then return end
			if index == 1 then
				strikeHop(-Timing.HOP)
			else
				strikeTurn(-360)
			end
		end)
	end)
	local isCalling = derive(function(): boolean
		return state.Tab() ~= index and pages.IsWaiting(index)
	end)
	local called = derive(function(): number
		if not isCalling() then return 1 end
		return Progress(state.Now(), state.CallAt(), Timing.CALL)
	end)
	local at = Layout.TABS[index]
	-- Derived: the plate and its word both read it.
	local position = derive(function(): UDim2
		local shake = 0
		if state.Refused() == index then
			local refusedAt = state.RefusedAt()
			shake = Timing.REFUSE_SHAKE * Motion.Shake(Progress(state.Now(), refusedAt, Timing.REFUSE), refusedAt)
		end
		return UDim2.fromOffset(
			Layout.MARGIN + at.X + Layout.TAB_SIZE.X / 2 + math.round(shake),
			Layout.MARGIN + at.Y + Layout.TAB_SIZE.Y / 2 - math.round(Timing.TABS_DROP * drop())
		)
	end)
	local scale = derive(function(): number
		return (1 - drop()) * hand.Scale()
	end)
	local ink = function(): Color3
		return Palette.Lavender:Lerp(Palette.White, math.clamp(picked(), 0, 1))
	end
	local calling = Hand.Spring(function(): number
		return if isCalling() then 1 else 0
	end, Timing.PICK_PERIOD)
	local lit = function(): number
		return math.max(hand.Light(), calling())
	end

	local word = create("Frame")({
		Name = `Tab{index}Word`,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(Layout.TAB_SIZE.X, Layout.TAB_SIZE.Y),
		BackgroundTransparency = 1,
		ZIndex = 5,
		create("UIScale")({ Scale = scale }),
		create("Frame")({
			Name = "Row",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			create("UIListLayout")({
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, Layout.TAB_GAP),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			-- The glyph turns and hops inside a box the row lays out, so the row never shifts under it.
			create("Frame")({
				Name = "GlyphBox",
				LayoutOrder = 1,
				Size = UDim2.fromOffset(Layout.TAB_GLYPH, Layout.TAB_GLYPH),
				BackgroundTransparency = 1,
				Components.Picture(if index == 1 then EIcons.GiftBox else EIcons.PrizeWheel, {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = function()
						return UDim2.new(0.5, 0, 0.5, math.round(hop()))
					end,
					Size = Components.PictureBox(Layout.TAB_GLYPH),
					Rotation = turn,
					ImageColor3 = ink,
					create("UIScale")({
						Scale = function()
							return 1 + 0.12 * hand.Rise()
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
				Text = if index == 1 then "DAILY" else "SPIN",
			}),
		}),
	})

	local button = Components.Button({
		Name = `Tab{index}`,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(Layout.TAB_SIZE.X, Layout.TAB_SIZE.Y),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Activated = function()
			if state.Tab() == index then return end
			actions.PickTab(index)
			-- Refused (the reel still turning): the tab shakes instead.
			if state.Tab() ~= index then return end
			hand.Commit()
		end,
		hand.Events,
		create("UIScale")({ Scale = scale }),
		-- His dark shade at rest, warming to a pink glow under the hand or while it calls.
		Components.Panel({
			Glow = function()
				return Color3.new():Lerp(Palette.Pink, lit())
			end,
			GlowTransparency = function()
				return 0.6 - Timing.CALL_GLOW * lit()
			end,
		}, {
			Name = "Plate",
			Size = UDim2.fromScale(1, 1),
			Hand.WashLayer(hand, 3, 2),
			Components.Sheen(Hand.Sheen(hand, called), 3),
			create("Frame")({
				Name = "BracketsHolder",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Components.Brackets(hand.Rise, function()
					return 0.6 - 0.3 * hand.Light()
				end, Layout.TAB_BRACKET_LENGTH, isPicked),
			}),
		}),
	}) :: TextButton

	return { button, word }, hand.Scale
end

-- His pink slab under the tab on show, gliding from one to the other. It grows and presses with the tab it lies on
-- (`scales`, each tab's hand), or the plate under it shows round its edge and its closed brackets go under it.
local function glider(state: Types.TDailyScreenState, elapsed: () -> number, scales: { () -> number }): Frame
	local drop = away(state, elapsed, Timing.TABS_DELAY)
	local x = Hand.Spring(function(): number
		return Layout.TABS[state.Tab()].X
	end, Timing.PICK_PERIOD, Timing.PICK_DAMPING)

	-- No brackets of its own: the plate's, under it, answer the hand, and two sets read as a double corner (UI.md).
	return Components.Slab({
		Kind = "Pink",
		Marks = true,
	}, {
		Name = "Glider",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			return UDim2.fromOffset(
				Layout.MARGIN + math.round(x()) + Layout.TAB_SIZE.X / 2,
				Layout.MARGIN + Layout.TABS[1].Y + Layout.TAB_SIZE.Y / 2 - math.round(Timing.TABS_DROP * drop())
			)
		end,
		-- A px bigger all round than the plate it lies on.
		Size = UDim2.fromOffset(Layout.TAB_SIZE.X + 2, Layout.TAB_SIZE.Y + 2),
		ZIndex = 4,
		create("UIScale")({
			Scale = function()
				return (1 - drop()) * scales[state.Tab()]()
			end,
		}),
	})
end

-- One page's gold words at the header's right. The one coming up rises in from under its place as the one going lifts out of it,
-- both fading; on the open, the words of the page on show rise in a beat after the tabs.
local function words(state: Types.TDailyScreenState, index: number, text: () -> string): TextLabel
	-- -1 (gone up) through 0 (in place) to 1 (still under it).
	local offset = derive(function(): number
		local now = state.Now()
		local tabAt = state.TabAt()
		if state.Tab() == index then
			local from = math.max(tabAt + Timing.INFO_GAP, state.ToggledAt() + Timing.INFO_DELAY)
			if not state.IsOpen() then return 0 end
			return 1 - Motion.Decelerate(Progress(now, from, Timing.INFO_IN))
		end
		-- Off show since the open: nothing to lift out.
		if tabAt < state.ToggledAt() then return -1 end
		return -Motion.Accelerate(Progress(now, tabAt, Timing.INFO_OUT))
	end)

	return label({
		Name = `Info{index}`,
		AnchorPoint = Vector2.new(1, 0),
		Position = function()
			return UDim2.fromOffset(
				Layout.MARGIN + Layout.INFO_RIGHT,
				Layout.MARGIN + Layout.INFO_Y + math.round(Timing.INFO_TRAVEL * offset())
			)
		end,
		Size = UDim2.fromOffset(500, Layout.INFO_TEXT),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = Layout.INFO_TEXT,
		TextColor3 = Palette.Gold,
		TextTransparency = function()
			return math.abs(offset())
		end,
		Visible = function()
			return math.abs(offset()) < 1
		end,
		Text = text,
	})
end

-- The rule under the header: it draws itself out from the left as the screen opens, and a light runs down it each
-- time a page is picked.
local function rule(state: Types.TDailyScreenState, elapsed: () -> number): Frame
	local drawn = derive(function(): number
		if not state.IsOpen() then return 1 end
		return Motion.Decelerate(Progress(elapsed(), Timing.RULE_DELAY, Timing.RULE))
	end)
	local swept = derive(function(): number
		if state.TabAt() < state.ToggledAt() then return 1 end
		return Progress(state.Now(), state.TabAt(), Timing.SWEEP)
	end)
	local isSweeping = derive(function(): boolean
		local t = swept()
		return t > 0 and t < 1
	end)

	return create("Frame")({
		Name = "Rule",
		Position = UDim2.fromOffset(Layout.MARGIN + Layout.RULE.X, Layout.MARGIN + Layout.RULE.Y),
		Size = function()
			return UDim2.fromOffset(math.round(Layout.RULE_WIDTH * drawn()), 1)
		end,
		BackgroundColor3 = RULE,
		BackgroundTransparency = RULE_TRANSPARENCY,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 3,
		-- The light: a white run tapering at both ends, three px tall so it reads over a one px line, travelling the
		-- rule's length plus its own so it comes in and goes out past the ends.
		create("Frame")({
			Name = "Sweep",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = function()
				local travel = Motion.Decelerate(swept())
				return UDim2.new(
					0,
					math.round((Layout.RULE_WIDTH + Layout.SWEEP_WIDTH) * travel - Layout.SWEEP_WIDTH),
					0.5,
					0
				)
			end,
			Size = UDim2.fromOffset(Layout.SWEEP_WIDTH, 1),
			BackgroundColor3 = Palette.White,
			BorderSizePixel = 0,
			Visible = isSweeping,
			create("UIGradient")({
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.7, 0),
					NumberSequenceKeypoint.new(1, 1),
				}),
			}),
		}),
	})
end

-- The back (the dim and the panel), the middle (`content`, the pages: unscaled 1920 x 1080 frames, cut to the panel
-- under the rule) and the front (the header), to be stacked in that order. `top` is the panel's top (Shell.Top),
-- `morph` its shape.
function Shell.Build(
	state: Types.TDailyScreenState,
	actions: Types.TDailyScreenActions,
	pages: Types.TPagesInfo,
	morph: () -> number,
	top: () -> number,
	content: { Instance }
): ({ Instance }, { Instance }, { Instance })
	local elapsed = elapsedOf(state)
	-- How much of the screen is there, 0 to 1: its fade, on the clock both ways.
	local shown = derive(function(): number
		if state.IsOpen() then return Motion.Out(Progress(elapsed(), 0, Timing.FADE)) end
		return 1 - Progress(elapsed(), 0, Timing.CLOSE)
	end)
	-- How far under its place the screen is, in px: up decelerating as it opens, down accelerating as it shuts.
	local drop = derive(function(): number
		if state.IsOpen() then return Timing.RISE * (1 - Motion.Decelerate(Progress(elapsed(), 0, Timing.OPEN))) end
		return Timing.SINK * Motion.Accelerate(Progress(elapsed(), 0, Timing.CLOSE))
	end)
	local height = derive(function(): number
		return math.round(Motion.Lerp(Layout.HEIGHTS[1], pages.SpinShape().Y, morph()))
	end)
	-- The panel's top left on the screen, the jackpot's shake and the open's rise on it.
	local corner = derive(function(): Vector2
		return Vector2.new(Layout.PANEL_X + math.round(pages.Shake()), math.round(top() + drop()))
	end)
	-- How far EXIT still has to come, 1 to 0: it rises in last and shrinks away as the screen shuts.
	local exitGone = derive(function(): number
		if state.IsOpen() then return 1 - Motion.Decelerate(Progress(elapsed(), Timing.EXIT_DELAY, Timing.SLIDE)) end
		return Motion.Accelerate(Progress(elapsed(), 0, Timing.CLOSE))
	end)
	local dailyTab, dailyScale = tab(state, actions, pages, elapsed, 1)
	local spinTab, spinScale = tab(state, actions, pages, elapsed, 2)

	local back = {
		-- Past the screen's edges whatever its shape. A click on it shuts the screen, but never while the reel turns.
		-- Modal: in first person the engine holds the mouse at the centre unless a visible button says otherwise.
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
				if not pages.IsSpinning() then actions.Close() end
			end,
		}),
		create("Frame")({
			Name = "Root",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(1920, 1080),
			BackgroundTransparency = 1,
			ZIndex = 2,
			create("UIScale")({ Scale = state.Scale }),
			-- A press on the panel stops here. A Frame lets it through to the dim, which would shut the screen.
			create("TextButton")({
				Name = "Sink",
				Position = function()
					local at = corner()
					return UDim2.fromOffset(at.X, at.Y)
				end,
				Size = function()
					return UDim2.fromOffset(Layout.PANEL_WIDTH, height())
				end,
				BackgroundTransparency = 1,
				AutoButtonColor = false,
				Text = "",
			}),
			-- Big enough for the taller page's shape, glow and brackets included; the panel moves inside it.
			Components.FadeGroup("Chrome", shown, {
				Position = function()
					return UDim2.fromOffset(
						Layout.PANEL_X - Layout.MARGIN + math.round(pages.Shake()),
						Layout.TOPS[1] - Layout.MARGIN + math.round(drop())
					)
				end,
				Size = UDim2.fromOffset(Layout.PANEL_WIDTH + 2 * Layout.MARGIN, Layout.HEIGHTS[1] + 2 * Layout.MARGIN),
			}, {
				-- Longer than the streak texture: its window starts at the corner and it is tiled across.
				Components.Panel({
					Brackets = true,
					TexturePhase = Vector2.zero,
					Wide = true,
					Tall = true,
				}, {
					Name = "Panel",
					Position = function()
						return UDim2.fromOffset(Layout.MARGIN, Layout.MARGIN + math.round(top() - Layout.TOPS[1]))
					end,
					Size = function()
						return UDim2.fromOffset(Layout.PANEL_WIDTH, height())
					end,
				}),
			}),
		}),
	}

	-- The pages, laid out on the whole screen, seen through the panel under the rule: the one coming rides the panel's
	-- top, the one going holds still as the panel closes round it.
	local middle = {
		create("Frame")({
			Name = "Pages",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(1920, 1080),
			BackgroundTransparency = 1,
			create("UIScale")({ Scale = state.Scale }),
			create("Frame")({
				Name = "Window",
				Position = function()
					local at = corner()
					return UDim2.fromOffset(at.X, at.Y + Layout.PAGES_TOP)
				end,
				Size = function()
					return UDim2.fromOffset(Layout.PANEL_WIDTH, height() - Layout.PAGES_TOP)
				end,
				BackgroundTransparency = 1,
				ClipsDescendants = true,
				create("Frame")({
					Name = "Screen",
					Position = function()
						local at = corner()
						return UDim2.fromOffset(-at.X, -at.Y - Layout.PAGES_TOP)
					end,
					Size = UDim2.fromOffset(1920, 1080),
					BackgroundTransparency = 1,
					content,
				}),
			}),
		}),
	}

	local front = {
		create("Frame")({
			Name = "Header",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(1920, 1080),
			BackgroundTransparency = 1,
			create("UIScale")({ Scale = state.Scale }),
			Components.FadeGroup("Group", shown, {
				Position = function()
					local at = corner()
					return UDim2.fromOffset(at.X - Layout.MARGIN, at.Y - Layout.MARGIN)
				end,
				Size = UDim2.fromOffset(Layout.PANEL_WIDTH + 2 * Layout.MARGIN, Layout.HEADER + 2 * Layout.MARGIN),
			}, {
				dailyTab,
				spinTab,
				glider(state, elapsed, { dailyScale, spinScale }),
				words(state, 1, function(): string
					return `DAY {pages.Day()} STREAK`
				end),
				words(state, 2, function(): string
					return `{pages.FreePerDay()} FREE SPINS EVERY DAY`
				end),
				rule(state, elapsed),
			}),
			Components.Exit(exitGone, actions.Close),
		}),
	}

	return back, middle, front
end

return Shell
