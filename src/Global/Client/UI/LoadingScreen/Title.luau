--!nonstrict
-- KILL ALL THE / MONSTERS, one label per letter so each is dealt in on its own: it rises into place growing from 0.6
-- as it fades in, and shrinks as it fades out when the screen leaves. Laid out from the font's own measure (Measure),
-- so the letters sit as the word would.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local TextService = game:GetService("TextService")
local vide = require(ReplicatedStorage.Packages.vide)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local Types = require(script.Parent.Types)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Progress = Motion.Progress

type TLine = {
	Text: string,
	Size: number,
	Tracking: number,
	Y: number,
	Ramp: ColorSequence?,
	Stagger: number,
}

local Title = {}

-- Each line: its words, size and tracking in design px, its middle's height from the screen's middle, and for the
-- big word a ramp (light at the top, deep at the bottom, as the pictures are lit).
local LINES: { TLine } = table.freeze({
	table.freeze({
		Text = "KILL ALL THE",
		Size = 46,
		Tracking = 10,
		Y = -134,
		Ramp = nil,
		Stagger = 0.035,
	}),
	table.freeze({
		Text = "MONSTERS",
		Size = 132,
		-- Montserrat's caps stand wide apart at this size; pulled in, the word reads as one.
		Tracking = -6,
		Y = -46,
		-- Straight keys on a white letter: none is dark enough for the gradient's 8-bit squared blend to crush.
		Ramp = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 160, 205)),
			ColorSequenceKeypoint.new(0.42, Color3.fromRGB(255, 46, 139)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(176, 14, 86)),
		}),
		Stagger = 0.05,
	}),
})

local Timing = table.freeze({
	AT = 0.1,
	-- The big word starts as the small line's last letter is halfway in.
	SECOND_LINE_OVERLAP = 0.15,
	DEAL_SECONDS = 0.32,
	RISE_PX = 24,
	FROM_SCALE = 0.6,
})

local MEASURE_SIZE = 100
local FONT = Theme.Font.Display
-- Montserrat Heavy's caps, roughly, for a layout without the font's measure (it never came in time).
local GUESS_ADVANCE = 0.8

-- When each letter lands, in seconds after the content began, by line.
local function landTimesOf(): { { number } }
	local times = {}
	local start = Timing.AT
	for lineIndex, line in LINES do
		local count = #line.Text
		local landing = table.create(count)
		for index = 1, count do
			landing[index] = start + (index - 1) * line.Stagger + Timing.DEAL_SECONDS
		end
		times[lineIndex] = landing
		start = start + (count - 1) * line.Stagger + Timing.DEAL_SECONDS - Timing.SECOND_LINE_OVERLAP
	end
	return times
end

local LAND_TIMES = landTimesOf()
local LAST_LINE_TIMES = LAND_TIMES[#LAND_TIMES]

-- When the last letter has landed, in seconds after the content began: each line deals in after the one above.
Title.LANDED_AT = LAST_LINE_TIMES[#LAST_LINE_TIMES]

-- Every line's letters' right edges and widths at MEASURE_SIZE. Yields (the font is fetched first). Measuring the
-- prefixes keeps the spaces between words, which a measure of a trailing space may trim.
function Title.Measure(): Types.TMetrics
	local params = Instance.new("GetTextBoundsParams")
	params.Font = FONT
	params.Size = MEASURE_SIZE
	params.Width = 100000
	local metrics = table.create(#LINES)
	for lineIndex, line in LINES do
		local count = #line.Text
		local rights = table.create(count)
		local widths = table.create(count)
		for index = 1, count do
			params.Text = string.sub(line.Text, 1, index)
			rights[index] = TextService:GetTextBoundsAsync(params).X
			params.Text = string.sub(line.Text, index, index)
			widths[index] = TextService:GetTextBoundsAsync(params).X
		end
		metrics[lineIndex] = { Rights = rights, Widths = widths }
	end
	params:Destroy()
	return metrics
end

function Title.Guess(): Types.TMetrics
	local metrics = table.create(#LINES)
	for lineIndex, line in LINES do
		local count = #line.Text
		local rights = table.create(count)
		local widths = table.create(count)
		for index = 1, count do
			rights[index] = index * GUESS_ADVANCE * MEASURE_SIZE
			widths[index] = GUESS_ADVANCE * MEASURE_SIZE
		end
		metrics[lineIndex] = { Rights = rights, Widths = widths }
	end
	return metrics
end

-- One letter: `x` its middle from the screen's middle, `landAt` seconds after the content began.
local function letter(
	state: Types.TState,
	clock: Types.TClock,
	line: TLine,
	char: string,
	x: number,
	width: number,
	landAt: number
): TextLabel
	local deal = derive(function(): number
		return Progress(clock.Since(state.BeganAt()), landAt - Timing.DEAL_SECONDS, Timing.DEAL_SECONDS)
	end)

	return create("TextLabel")({
		Name = `Letter{char}`,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(math.ceil(width) + 8, line.Size),
		BackgroundTransparency = 1,
		ZIndex = 4,
		FontFace = FONT,
		TextSize = line.Size,
		Text = char,
		TextColor3 = Palette.White,
		Position = function()
			local rise = (1 - Motion.Decelerate(deal())) * Timing.RISE_PX
			return UDim2.new(0.5, math.round(x), 0.5, line.Y + math.round(rise))
		end,
		TextTransparency = function()
			return 1 - math.min(1, deal() * 2.2) * clock.Opacity(1)
		end,
		if line.Ramp then create("UIGradient")({ Rotation = 90, Color = line.Ramp }) else nil,
		create("UIScale")({
			Scale = function()
				local grow = Timing.FROM_SCALE + (1 - Timing.FROM_SCALE) * Motion.Decelerate(deal())
				return grow * clock.Content(1)
			end,
		}),
	})
end

-- Builds once the measure is in (state.Metrics), so nothing is laid out on a guess that the real one then moves.
function Title.Build(state: Types.TState, clock: Types.TClock): () -> { Instance }?
	return derive(function()
		local metrics = state.Metrics()
		if not metrics then return nil end
		return vide.untrack(function()
			local letters = {}
			for lineIndex, line in LINES do
				local measure = metrics[lineIndex]
				local count = #line.Text
				local k = line.Size / MEASURE_SIZE
				local total = measure.Rights[count] * k + line.Tracking * (count - 1)
				for index = 1, count do
					local char = string.sub(line.Text, index, index)
					if char == " " then continue end
					local width = measure.Widths[index] * k
					local x = -total / 2 + measure.Rights[index] * k - width / 2 + line.Tracking * (index - 1)
					table.insert(letters, letter(state, clock, line, char, x, width, LAND_TIMES[lineIndex][index]))
				end
			end
			return letters
		end)
	end)
end

return Title
