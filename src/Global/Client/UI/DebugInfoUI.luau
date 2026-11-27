--!nonstrict
-- The debug readout (the settings' DEBUG INFO), in both places: a column of free words in the bottom-right corner, no
-- panel, so it never takes attention from the run. Each line hangs off a thin tick in its grade's colour (FPS and ping
-- green, gold or red, the rest lavender): showing, the ticks draw up one after another from the bottom and the words
-- slide out from behind them; hidden, the words slide back in and the ticks fold away. DebugInfoController owns the
-- sources and writes a value only when what it shows changes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(script.Parent.Components)
local Motion = require(script.Parent.Motion)
local Theme = require(script.Parent.Theme)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress

export type Source<T> = (() -> T) & ((value: T) -> T)

export type TLine = {
	Name: string,
	-- The value as shown, and the grade's colour its tick and number wear.
	Value: Source<string>,
	Color: Source<Color3>,
	-- Whether anything in this place counts it: a line nothing tracks is not drawn.
	IsUsed: Source<boolean>,
}

export type TDebugInfoState = {
	Scale: Source<number>,
	-- os.clock, written only while the column moves (DebugInfoController's motion window).
	Now: Source<number>,
	IsShown: Source<boolean>,
	-- os.clock the column was last shown or hidden.
	ToggledAt: Source<number>,
	-- Design px the column stands higher than its place: over a phone's jump button.
	Lift: Source<number>,
	-- Design px off the screen's right edge that a place keeps for its own corner (the match's ability column and
	-- CHARGE NOW): the column stands left of it.
	Clear: Source<number>,
	-- Top to bottom.
	Lines: { TLine },
}

-- Design px at 1080.
local Layout = table.freeze({
	-- Off the screen's right and bottom edges: clear of the lobby's CLASSES and the match's ULT meter above it.
	RIGHT = 24,
	BOTTOM = 22,
	-- Off what a place keeps in the corner (state.Clear).
	CLEAR_GAP = 20,
	WIDTH = 230,
	LINE = 24,
	GAP = 3,
	TICK = 3,
	-- The words' window ends this far left of the tick.
	TICK_GAP = 8,
	VALUE_WIDTH = 66,
	VALUE_SIZE = 20,
	NAME_SIZE = 14,
	NAME_GAP = 10,
})

local Timing = table.freeze({
	-- Showing: each line a beat after the one under it, its tick drawing up, then its words sliding out of it.
	STAGGER = 0.05,
	TICK = 0.16,
	WORDS_DELAY = 0.07,
	WORDS = 0.36,
	FADE = 0.22,
	-- The tick lands white and cools to its colour.
	FLASH = 0.35,
	-- Hiding: quicker, top line first, the words in, then the tick.
	LEAVE_STAGGER = 0.03,
	LEAVE_WORDS = 0.16,
	LEAVE_TICK = 0.12,
	LEAVE_TICK_DELAY = 0.1,
})

local DebugInfoUI = {}

-- Seconds from the column's toggle to its last gesture's end, for `count` lines: the controller keeps its clock this
-- long.
function DebugInfoUI.SettleSeconds(count: number): number
	return Timing.STAGGER * count + Timing.WORDS_DELAY + Timing.WORDS + Timing.FLASH
end

-- Seconds a hidden column of `count` lines takes to fold away: shorter than SettleSeconds, so the clock is still
-- ticking when it is over and the gui can be switched off.
function DebugInfoUI.LeaveSeconds(count: number): number
	return Timing.LEAVE_TICK_DELAY + Timing.LEAVE_STAGGER * count + Timing.LEAVE_TICK
end

-- Design px from the screen's right edge to the column's, with `clear` px kept for the place's corner (state.Clear).
function DebugInfoUI.Right(clear: number): number
	return if clear > 0 then clear + Layout.CLEAR_GAP else Layout.RIGHT
end

-- Design px the column must rise, `gap` over it, to clear something whose top is at `top` and right edge at `right`
-- (screen px from its top left), drawn at `scale` in a `viewport` with `clear` kept (state.Clear): 0 when it ends left
-- of the column or under it.
function DebugInfoUI.LiftOver(
	top: number,
	right: number,
	viewport: Vector2,
	scale: number,
	gap: number,
	clear: number
): number
	local columnLeft = viewport.X - (DebugInfoUI.Right(clear) + Layout.WIDTH) * scale
	local columnBottom = viewport.Y - Layout.BOTTOM * scale
	if right <= columnLeft or top >= columnBottom then return 0 end
	return math.round((columnBottom - top) / scale + gap)
end

-- One line, `rank` lines from the bottom and `fromTop` from the top among the drawn ones.
local function line(state: TDebugInfoState, data: TLine, rank: () -> number, fromTop: () -> number): Frame
	local elapsed = function(): number
		return state.Now() - state.ToggledAt()
	end
	-- How much of the tick is drawn and how far out the words are, 0 to 1. Derived, so at rest the clock ticking for
	-- another line's gesture redraws nothing here.
	local drawn = derive(function(): number
		if state.IsShown() then
			return Motion.Decelerate(Progress(elapsed(), 0, Timing.TICK, Timing.STAGGER * rank()))
		end
		return 1
			- Motion.Accelerate(
				Progress(elapsed(), 0, Timing.LEAVE_TICK, Timing.LEAVE_TICK_DELAY + Timing.LEAVE_STAGGER * fromTop())
			)
	end)
	local out = derive(function(): number
		if state.IsShown() then
			return Motion.Decelerate(Progress(elapsed(), 0, Timing.WORDS, Timing.STAGGER * rank() + Timing.WORDS_DELAY))
		end
		return 1 - Motion.Accelerate(Progress(elapsed(), 0, Timing.LEAVE_WORDS, Timing.LEAVE_STAGGER * fromTop()))
	end)
	local faded = derive(function(): number
		if not state.IsShown() then return out() end
		return Motion.Out(Progress(elapsed(), 0, Timing.FADE, Timing.STAGGER * rank() + Timing.WORDS_DELAY))
	end)
	local flash = derive(function(): number
		if not state.IsShown() then return 0 end
		return 1 - Motion.Out(Progress(elapsed(), 0, Timing.FLASH, Timing.STAGGER * rank() + Timing.TICK * 0.5))
	end)

	local window = Layout.WIDTH - Layout.TICK - Layout.TICK_GAP

	return create("Frame")({
		Name = data.Name,
		Size = UDim2.fromOffset(Layout.WIDTH, Layout.LINE),
		BackgroundTransparency = 1,
		Visible = data.IsUsed,
		create("Frame")({
			Name = "Tick",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(1, 0.5),
			Size = function()
				return UDim2.fromOffset(Layout.TICK, math.round(Layout.LINE * drawn()))
			end,
			BackgroundColor3 = function()
				return data.Color():Lerp(Palette.White, flash())
			end,
			BorderSizePixel = 0,
			Visible = function()
				return drawn() > 0.01
			end,
		}),
		-- The words slide out from behind the tick: the window clips them where it ends.
		create("Frame")({
			Name = "Window",
			Size = UDim2.fromOffset(window, Layout.LINE),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			create("Frame")({
				Name = "Words",
				Position = function()
					return UDim2.fromOffset(math.round(window * (1 - out())), 0)
				end,
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				create("TextLabel")({
					Name = "Value",
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.fromScale(1, 0.5),
					Size = UDim2.fromOffset(Layout.VALUE_WIDTH, Layout.LINE),
					BackgroundTransparency = 1,
					FontFace = Font.Display,
					TextSize = Layout.VALUE_SIZE,
					TextXAlignment = Enum.TextXAlignment.Right,
					-- Rewritten several times a second: never sent through translation.
					AutoLocalize = false,
					Text = data.Value,
					TextColor3 = data.Color,
					TextTransparency = function()
						return 1 - faded()
					end,
					Components.Ink(Layout.VALUE_SIZE),
				}),
				create("TextLabel")({
					Name = "Name",
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -(Layout.VALUE_WIDTH + Layout.NAME_GAP), 0.5, 1),
					Size = UDim2.fromOffset(window - Layout.VALUE_WIDTH - Layout.NAME_GAP, Layout.LINE),
					BackgroundTransparency = 1,
					FontFace = Font.DisplayBold,
					TextSize = Layout.NAME_SIZE,
					TextXAlignment = Enum.TextXAlignment.Right,
					TextColor3 = Palette.Lavender,
					Text = data.Name,
					TextTransparency = function()
						return 1 - faded()
					end,
					Components.Ink(Layout.NAME_SIZE),
				}),
			}),
		}),
	})
end

function DebugInfoUI.Build(state: TDebugInfoState): Frame
	local lines = state.Lines
	local count = #lines
	local children = table.create(count + 1)
	children[1] = create("UIListLayout")({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, Layout.GAP),
	})
	local usedCount = derive(function(): number
		local used = 0
		for _, data in lines do
			if data.IsUsed() then
				used += 1
			end
		end

		return used
	end)
	for index, data in lines do
		-- The drawn lines under this one: the bottom line comes first and goes last.
		local rank = derive(function(): number
			local below = 0
			for after = index + 1, count do
				if lines[after].IsUsed() then
					below += 1
				end
			end

			return below
		end)
		local fromTop = derive(function(): number
			return usedCount() - 1 - rank()
		end)
		local frame = line(state, data, rank, fromTop)
		frame.LayoutOrder = index
		children[index + 1] = frame
	end

	return create("Frame")({
		Name = "Column",
		AnchorPoint = Vector2.new(1, 1),
		Position = function()
			return UDim2.new(1, -DebugInfoUI.Right(state.Clear()), 1, -(Layout.BOTTOM + math.round(state.Lift())))
		end,
		Size = UDim2.fromOffset(Layout.WIDTH, count * (Layout.LINE + Layout.GAP)),
		BackgroundTransparency = 1,
		children,
	})
end

return DebugInfoUI
