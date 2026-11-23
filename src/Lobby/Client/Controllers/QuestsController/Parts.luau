--!nonstrict
-- What the quests screen's pieces share: his colours for a quest's group, its bar and a claimed card, the label, and the
-- clock every piece's entrance reads.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local QuestsCore = require(ReplicatedStorage.GlobalShared.Core.QuestsCore)
local Types = require(script.Parent.Types)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress

local Parts = {}

-- A screen's open and shut (UI.md 5o): pieces decelerate in, staged by what the screen is for, and accelerate out
-- faster; every fade runs on its own clock.
Parts.Timing = table.freeze({
	FADE = 0.3,
	SLIDE = 0.42,
	CLOSE = 0.22,
	-- Every gesture of an open is over by now; past it the clock's ticks redraw none of them.
	SETTLED = 1.6,
})

-- A card's accent by its quest's group, as his: green, steel, violet, pink and gold cards. A card's edge is its accent
-- a little darker; the glow is the accent itself.
Parts.ACCENTS = table.freeze({
	Slay = Palette.Green,
	Hunt = Palette.Steel,
	Survive = Palette.Violet,
	Boss = Palette.Pink,
	Skill = Palette.Gold,
})
Parts.EDGE_SHARE = 0.85
-- His claimed card: the accent gone to a grey violet.
Parts.CLAIMED = Color3.fromRGB(100, 88, 116)
-- His bars: pink while it fills, green once it is full, a deep green once it is claimed, on a dark lavender track.
Parts.BAR_FILLING = Color3.fromRGB(251, 47, 142)
Parts.BAR_FULL = Color3.fromRGB(52, 224, 131)
Parts.BAR_CLAIMED = Color3.fromRGB(38, 130, 89)
Parts.BAR_TRACK = Color3.fromRGB(58, 50, 86)
-- The reward's colour on each board: his gold Daily, his blue Weekly.
Parts.REWARD_COLORS = table.freeze({ Palette.Gold, Color3.fromRGB(89, 191, 255) })
-- A card's scroll tile: the card's dark face, warmed toward its accent where it is drawn.
Parts.TILE_FACE = Color3.fromRGB(19, 19, 40)
-- His thin rule under the tabs.
Parts.RULE = Color3.fromRGB(60, 38, 88)
-- His dark plaque (IN PROGRESS, CLAIMED, the tab not on show): a dim pink edge round an ink face.
Parts.PLAQUE_EDGE = Color3.fromRGB(116, 26, 72)
Parts.PLAQUE_FACE = Color3.fromRGB(10, 7, 21)

function Parts.EdgeOf(accent: Color3): Color3
	local share = Parts.EDGE_SHARE
	return Color3.new(accent.R * share, accent.G * share, accent.B * share)
end

function Parts.Label(props: { [any]: any }): TextLabel
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

-- His dark plaque, `props` sized to his drawn rect.
function Parts.Plaque(props: { [any]: any }): Frame
	return create("Frame")({
		BackgroundColor3 = Parts.PLAQUE_EDGE,
		BorderSizePixel = 0,
		create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
		create("UIGradient")({
			Rotation = 90,
			Color = ColorSequence.new(Palette.White, Color3.new(0.8, 0.8, 0.8)),
		}),
		create("Frame")({
			Name = "Face",
			Position = UDim2.fromOffset(2, 2),
			Size = UDim2.new(1, -4, 1, -4),
			BackgroundColor3 = Parts.PLAQUE_FACE,
			BorderSizePixel = 0,
			create("UICorner")({ CornerRadius = UDim.new(0, 1) }),
		}),
		props,
	})
end

-- Seconds since the screen opened or shut, held once every gesture is over, so the clock ticking for a later
-- gesture works none of the open out again.
function Parts.Elapsed(state: Types.TQuestsState): () -> number
	return derive(function(): number
		return math.min(state.Now() - state.ToggledAt(), Parts.Timing.SETTLED)
	end)
end

-- How far from its place a piece is, as a share of its travel: decelerating in after `delay`, accelerating out.
function Parts.Away(state: Types.TQuestsState, elapsed: () -> number, delay: number): () -> number
	return derive(function(): number
		if state.IsOpen() then return 1 - Motion.Decelerate(Progress(elapsed(), delay, Parts.Timing.SLIDE)) end
		return Motion.Accelerate(Progress(elapsed(), 0, Parts.Timing.CLOSE))
	end)
end

-- How transparent a piece is: its fade in after `delay` (away at once, gentle onto the mark), an even fade out.
function Parts.Faded(state: Types.TQuestsState, elapsed: () -> number, delay: number): () -> number
	return derive(function(): number
		if state.IsOpen() then return 1 - Motion.Out(Progress(elapsed(), delay, Parts.Timing.FADE)) end
		return Progress(elapsed(), 0, Parts.Timing.CLOSE)
	end)
end

-- How many quests on a board are finished and not claimed.
function Parts.ReadyCount(view: Types.TBoardView?): number
	if not view then return 0 end
	local count = 0
	for slot, id in view.Ids do
		local quest = QuestsCore.ById[id]
		if quest and not view.Claimed[slot] and (view.Progress[slot] or 0) >= quest.Goal then
			count += 1
		end
	end

	return count
end

-- "13:24:58" under a day, "4D 13H" past one, as his.
function Parts.Clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local days = seconds // 86400
	local hours = seconds // 3600 % 24
	if days > 0 then return `{days}D {hours}H` end
	return string.format("%02d:%02d:%02d", hours, seconds // 60 % 60, seconds % 60)
end

return Parts
