--!nonstrict
-- What the daily rewards screen's pieces share: the clock every entrance reads, his colours, and his small tags.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local Types = require(script.Parent.Types)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress

local Parts = {}

-- A screen's open and shut (UI.md 5o): the panel decelerates up into place and accelerates down out of it, the exit
-- the faster; pieces inside it arrive staged by what the screen is for; every fade runs on its own clock.
Parts.Timing = table.freeze({
	OPEN = 0.36,
	FADE = 0.28,
	RISE = 28,
	CLOSE = 0.2,
	SINK = 14,
	SLIDE = 0.42,
	PIECE_FADE = 0.3,
	-- Every gesture of an open is over by now; past it the clock's ticks redraw none of them.
	SETTLED = 1.8,
})

-- His colours that are not in the Palette: the gem's blue (and its word's), the edge round a GEMS tag, the dark band
-- at the top of a day card, the rules.
Parts.GEM_BLUE = Color3.fromRGB(89, 191, 255)
Parts.GEMS_EDGE = Color3.fromRGB(55, 103, 143)
Parts.BAND = Color3.fromRGB(15, 12, 32)
Parts.RULE = Color3.fromRGB(140, 111, 210)
Parts.RULE_TRANSPARENCY = 0.55
-- His card edges are their accent a little darker; the glow is the accent itself.
Parts.EDGE_SHARE = 0.85

-- The GEMS tag and the CLAIM NOW tag, his sizes and letters.
Parts.GEMS_TAG = Vector2.new(67, 26)
Parts.GEMS_TAG_TEXT = 14
Parts.CLAIM_TAG = Vector2.new(121, 30)
Parts.CLAIM_TAG_TEXT = 16

function Parts.EdgeOf(accent: Color3): Color3
	local share = Parts.EDGE_SHARE
	return Color3.new(accent.R * share, accent.G * share, accent.B * share)
end

function Parts.Label(props: { [any]: any }): TextLabel
	return create("TextLabel")({
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		FontFace = Font.Display,
		TextColor3 = Palette.White,
		ZIndex = 4,
		props,
	})
end

-- Seconds since the screen opened or shut, held once every gesture is over, so the clock ticking for a later gesture
-- works none of the open out again.
function Parts.Elapsed(state: Types.TDailyState): () -> number
	return derive(function(): number
		return math.min(state.Now() - state.ToggledAt(), Parts.Timing.SETTLED)
	end)
end

-- 0 to 1 as a piece's own gesture runs, `delay` after the open; 1 while the screen shuts.
function Parts.Since(state: Types.TDailyState, elapsed: () -> number, delay: number, seconds: number): () -> number
	return derive(function(): number
		if not state.IsOpen() then return 1 end
		return Progress(elapsed(), delay, seconds)
	end)
end

-- How far a piece still has to come, 1 to 0, decelerating in after `delay`; 0 while the screen shuts (it rides out
-- with the panel).
function Parts.Away(state: Types.TDailyState, elapsed: () -> number, delay: number): () -> number
	return derive(function(): number
		if not state.IsOpen() then return 0 end
		return 1 - Motion.Decelerate(Progress(elapsed(), delay, Parts.Timing.SLIDE))
	end)
end

-- How transparent a piece under the chrome's fade is: its fade in after `delay` (away at once, gentle onto the mark);
-- 0 while the screen shuts, since the chrome fades it out.
function Parts.Faded(state: Types.TDailyState, elapsed: () -> number, delay: number): () -> number
	return derive(function(): number
		if not state.IsOpen() then return 0 end
		return 1 - Motion.Out(Progress(elapsed(), delay, Parts.Timing.PIECE_FADE))
	end)
end

-- The same fade in for a piece outside the chrome, which fades out on its own with the screen's `shown` as it shuts.
function Parts.FadedOut(
	state: Types.TDailyState,
	elapsed: () -> number,
	shown: () -> number,
	delay: number
): () -> number
	return derive(function(): number
		if not state.IsOpen() then return 1 - shown() end
		return 1 - Motion.Out(Progress(elapsed(), delay, Parts.Timing.PIECE_FADE))
	end)
end

-- How much of the whole screen is there, 0 to 1: its fade, on the clock both ways.
function Parts.Shown(state: Types.TDailyState, elapsed: () -> number): () -> number
	return derive(function(): number
		if state.IsOpen() then return Motion.Out(Progress(elapsed(), 0, Parts.Timing.FADE)) end
		return 1 - Progress(elapsed(), 0, Parts.Timing.CLOSE)
	end)
end

-- A thin rule `width` px long that draws itself out from its left end as `drawn` runs 0 to 1.
function Parts.Rule(position: UDim2, width: number, drawn: () -> number): Frame
	return create("Frame")({
		Name = "Rule",
		Position = position,
		Size = function()
			return UDim2.fromOffset(math.round(width * Motion.Decelerate(drawn())), 1)
		end,
		BackgroundColor3 = Parts.RULE,
		BackgroundTransparency = Parts.RULE_TRANSPARENCY,
		BorderSizePixel = 0,
		ZIndex = 2,
	})
end

-- His GEMS tag: an ink chip edged in a steel blue, the word in the gem's blue. `size` and `text` are his small tag's
-- unless given.
function Parts.GemsTag(props: { [any]: any }, size: Vector2?, text: number?): Frame
	local box = size or Parts.GEMS_TAG
	return create("Frame")({
		Name = "GemsTag",
		Size = UDim2.fromOffset(box.X, box.Y),
		BackgroundColor3 = Parts.GEMS_EDGE,
		BorderSizePixel = 0,
		ZIndex = 5,
		create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
		create("Frame")({
			Name = "Face",
			Position = UDim2.fromOffset(2, 2),
			Size = UDim2.new(1, -4, 1, -4),
			BackgroundColor3 = Palette.Ink,
			BorderSizePixel = 0,
			create("UICorner")({ CornerRadius = UDim.new(0, 1) }),
		}),
		Parts.Label({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, 0, 0, text or Parts.GEMS_TAG_TEXT),
			TextYAlignment = Enum.TextYAlignment.Center,
			TextSize = text or Parts.GEMS_TAG_TEXT,
			TextColor3 = Parts.GEM_BLUE,
			Text = "GEMS",
			ZIndex = 2,
		}),
		props,
	})
end

return Parts
