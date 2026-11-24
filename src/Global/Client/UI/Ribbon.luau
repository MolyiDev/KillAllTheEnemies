--!nonstrict
-- A word on a band across one corner of a card (NEW, a level): the card's own child, sized to it whole, which clips the
-- band at the card's outer edge so it runs over the edge and off the card. The band is shaded as the rendered pictures
-- are (Assets/ui/rendered/STYLE.md), in this UI's smooth light: one soft ramp from a lit top through its colour to a
-- deeper bottom, a soft shade under it, no outline.
--
-- It moves on beats off its own stamps (when it was shown, when it was taken off) read from one clock for every ribbon,
-- which ticks only while one of them moves: it slaps in from beyond the corner, swells, flashes, throws one ring and
-- the light runs along it; on show it catches the light every CALL_PERIOD, the ribbons on one screen one after
-- another; taken off, it flashes and is pulled out through the corner.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(script.Parent.Components)
local Motion = require(script.Parent.Motion)
local Theme = require(script.Parent.Theme)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Progress = Motion.Progress

local Ribbon = {}

export type TCorner = "TopLeft" | "TopRight"

export type TSpec = {
	Corner: TCorner,
	-- Its word, its colour and whether the word is ink (on a bright colour) rather than white. May be sources.
	Text: string | () -> string,
	Color: Color3 | () -> Color3,
	IsInk: (boolean | () -> boolean)?,
	-- Whether it is on the card. Read as a vide source.
	IsShown: () -> boolean,
	-- px from the corner, along each edge, to where the band's middle line meets it; the band's thickness; the word's
	-- size. The word must fit inside the band's short (corner) side: Ribbon.MinAlong.
	Along: number,
	Thickness: number,
	TextSize: number,
	-- Seconds after it is built before it slaps in, when it is built on show: its card is dealt in first. Shown later
	-- (a discovery revealed), it slaps in at once.
	Delay: number?,
	-- Its turn in the screen's calls, in steps of CALL_STAGGER; nil for none.
	CallOrder: number?,
	ZIndex: number?,
}

local Look = table.freeze({
	-- Its ramp across the band: toward white at the top, its own colour at FACE_AT, toward black at the bottom.
	LIT = 0.32,
	FACE_AT = 0.45,
	DEEP = 0.22,
	-- Its shade on the card, px straight down, fading out toward its lower edge so it is a soft line, not a step.
	SHADE = 3,
	SHADE_TRANSPARENCY = 0.6,
	RING_LINE = 2,
})

-- Seconds from the slap's start unless named otherwise.
local Arrive = table.freeze({
	-- The slide in from beyond the corner, decelerating, and the moment it reads as landed.
	SLIDE = 0.2,
	LAND = 0.15,
	-- The swell of its thickness and the word: up fast from just before it lands, back without a wobble.
	SWELL_FROM = 0.12,
	SWELL = 0.3,
	SWELL_PEAK = 0.15,
	SWELL_BY = 0.35,
	WORD_BY = 0.22,
	FLASH = 0.32,
	FLASH_PEAK = 0.9,
	-- One ring off the band, RING_REACH px out each side by the end.
	RING = 0.5,
	RING_REACH = 14,
	-- The light runs along it once it has landed.
	SHEEN_FROM = 0.22,
	SHEEN = 0.55,
	-- All of it is over: past the sheen and the ring.
	SECONDS = 0.8,
})

local Leave = table.freeze({
	FLASH = 0.18,
	FLASH_PEAK = 0.6,
	PULL_FROM = 0.04,
	PULL = 0.26,
	SECONDS = 0.32,
})

-- The light runs along every ribbon on show every PERIOD, each CALL_STAGGER after the one before (at most MAX_DELAY),
-- so a screen of them catches it one after another.
local Call = table.freeze({
	PERIOD = 3.2,
	SECONDS = 0.6,
	STAGGER = 0.07,
	MAX_DELAY = 1.2,
})
-- The share of each period the clock ticks for the calls: every ribbon's call and a frame or two past the last.
local CALL_WINDOW = Call.SECONDS + Call.MAX_DELAY + 0.05

-- One clock for every ribbon: os.clock(), written only while one slaps in, leaves or calls.
local clock = vide.source(os.clock())
local motionUntil = -math.huge
local callers = 0
local connection: RBXScriptConnection? = nil

-- The smallest Along at which a word `wordWidth` px wide fits on a band `thickness` thick: inside its short side, with
-- a thickness of room at each end where the side meets the card's edge at 45 degrees.
function Ribbon.MinAlong(wordWidth: number, thickness: number): number
	return (wordWidth + 3 * thickness) / math.sqrt(2)
end

local function read(value: any): any
	return if type(value) == "function" then value() else value
end

local function isCalling(now: number): boolean
	return callers > 0 and now % Call.PERIOD < CALL_WINDOW
end

local function tick()
	local now = os.clock()
	if now < motionUntil or isCalling(now) then clock(now) end
	if now < motionUntil or callers > 0 then return end
	if connection then connection:Disconnect() end
	connection = nil
end

-- Keeps the clock ticking until `untilAt`.
local function wake(untilAt: number)
	motionUntil = math.max(motionUntil, untilAt)
	if not connection then connection = RunService.Heartbeat:Connect(tick) end
end

-- The thickness's swell, 0 to 1: up fast to its peak, then back down easing onto 0.
local function swellAt(t: number): number
	if t <= 0 or t >= 1 then return 0 end
	if t < Arrive.SWELL_PEAK then return Motion.Out(t / Arrive.SWELL_PEAK) end
	local back = (t - Arrive.SWELL_PEAK) / (1 - Arrive.SWELL_PEAK)
	return (1 - back) * (1 - back)
end

function Ribbon.Build(spec: TSpec): Frame
	local along = spec.Along
	local thickness = spec.Thickness
	local delay = spec.Delay or 0
	local callDelay = if spec.CallOrder then math.min(spec.CallOrder * Call.STAGGER, Call.MAX_DELAY) else nil
	local isLeft = spec.Corner == "TopLeft"
	-- Its middle at rest, from the corner, and the way to the corner: the band slaps in from there and leaves by it.
	local middle = along / 2
	local outward = Vector2.new(if isLeft then -1 else 1, -1).Unit
	-- From its middle to past the corner, its shade and 2 px more: out of sight.
	local shift = along / math.sqrt(2) + thickness / 2 + Look.SHADE + 2
	-- Long enough to run off both edges at any swell; the clip cuts it.
	local length = math.ceil(along * math.sqrt(2) + 3 * thickness)

	-- The caller's IsShown read once for every piece below, and passed on only when it changes.
	local isShown = derive(spec.IsShown)
	local shownAt = vide.source(-math.huge)
	local hiddenAt = vide.source(-math.huge)
	local wasShown = false
	local isBuilding = true
	vide.effect(function()
		local up = isShown()
		vide.untrack(function()
			local hold = if isBuilding then delay else 0
			isBuilding = false
			if up == wasShown then return end
			wasShown = up
			local now = os.clock()
			if up then
				shownAt(now + hold)
				wake(now + hold + Arrive.SECONDS)
			else
				hiddenAt(now)
				wake(now + Leave.SECONDS)
			end
		end)
	end)
	if callDelay then
		vide.effect(function()
			if not isShown() then return end
			vide.untrack(function()
				callers += 1
				wake(os.clock())
			end)
			vide.cleanup(function()
				callers -= 1
			end)
		end)
	end

	-- Seconds into the slap (huge once it is long over), and into the leave (negative while it is on show).
	local arrived = derive(function(): number
		return math.min(clock() - shownAt(), Arrive.SECONDS)
	end)
	local left = derive(function(): number
		if isShown() then return -1 end
		return math.min(clock() - hiddenAt(), Leave.SECONDS)
	end)
	local isDrawn = derive(function(): boolean
		if isShown() then return arrived() > 0 end
		return left() < Leave.SECONDS
	end)
	-- How far toward the corner it stands, 0 to 1 (1 is out of sight).
	local away = derive(function(): number
		local out = left()
		if out >= 0 then return Motion.Accelerate(Progress(out, Leave.PULL_FROM, Leave.PULL)) end
		return 1 - Motion.Decelerate(Progress(arrived(), 0, Arrive.SLIDE))
	end)
	local swell = derive(function(): number
		if left() >= 0 then return 0 end
		return swellAt(Progress(arrived(), Arrive.SWELL_FROM, Arrive.SWELL))
	end)
	local flash = derive(function(): number
		local out = left()
		if out >= 0 then
			local f = 1 - Progress(out, 0, Leave.FLASH)
			return Leave.FLASH_PEAK * f * f
		end
		local t = arrived()
		if t < Arrive.LAND then return 0 end
		local f = 1 - Progress(t, Arrive.LAND, Arrive.FLASH)
		return Arrive.FLASH_PEAK * f * f
	end)
	local ringed = derive(function(): number
		if left() >= 0 then return 1 end
		return Progress(arrived(), Arrive.LAND, Arrive.RING)
	end)
	-- The light along it: the slap's, then each call's while it is on show. 1 at rest.
	local sheen = derive(function(): number
		if left() >= 0 then return 1 end
		local t = arrived()
		if t < Arrive.SECONDS then return Progress(t, Arrive.SHEEN_FROM, Arrive.SHEEN) end
		if not callDelay then return 1 end
		local phase = (clock() - callDelay) % Call.PERIOD
		if phase >= Call.SECONDS then return 1 end
		return phase / Call.SECONDS
	end)

	local color = function(): Color3
		return read(spec.Color)
	end
	local lit = function(): Color3
		return color():Lerp(Palette.White, Look.LIT)
	end
	local rotation = if isLeft then -45 else 45
	-- Its middle from the corner, its thickness and the ring's growth, in whole px: passed on only as they change by one.
	local spot = derive(function(): Vector2
		local at = outward * shift * away()
		return Vector2.new(math.round((if isLeft then middle else -middle) + at.X), math.round(middle + at.Y))
	end)
	local thick = derive(function(): number
		return math.round(thickness * (1 + Arrive.SWELL_BY * swell()))
	end)
	local ringGrow = derive(function(): number
		return math.round(Arrive.RING_REACH * Motion.Out(ringed()))
	end)
	local side = if isLeft then 0 else 1
	local function placed(drop: number): UDim2
		local at = spot()
		return UDim2.new(side, at.X, 0, at.Y + drop)
	end

	return create("Frame")({
		Name = "Ribbon",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Visible = isDrawn,
		ZIndex = spec.ZIndex or 6,
		create("Frame")({
			Name = "Shade",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				return placed(Look.SHADE)
			end,
			Size = function()
				return UDim2.fromOffset(length, thick())
			end,
			Rotation = rotation,
			BackgroundColor3 = Color3.new(),
			BackgroundTransparency = Look.SHADE_TRANSPARENCY,
			BorderSizePixel = 0,
			ZIndex = 1,
			create("UIGradient")({
				Rotation = 90,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(0.8, 0),
					NumberSequenceKeypoint.new(1, 1),
				}),
			}),
		}),
		create("Frame")({
			Name = "Ring",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				return placed(0)
			end,
			Size = function()
				return UDim2.fromOffset(length, thickness + 2 * ringGrow())
			end,
			Rotation = rotation,
			BackgroundTransparency = 1,
			Visible = function()
				local r = ringed()
				return r > 0 and r < 1
			end,
			ZIndex = 2,
			create("UIStroke")({
				Color = lit,
				Thickness = Look.RING_LINE,
				Transparency = ringed,
			}),
		}),
		create("Frame")({
			Name = "Band",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				return placed(0)
			end,
			Size = function()
				return UDim2.fromOffset(length, thick())
			end,
			Rotation = rotation,
			BorderSizePixel = 0,
			ZIndex = 3,
			Components.Gradient(function()
				local face = color()
				return {
					{ 0, lit() },
					{ Look.FACE_AT, face },
					{ 1, face:Lerp(Color3.new(), Look.DEEP) },
				}
			end),
			Components.Sheen(sheen, 3),
			create("TextLabel")({
				Name = "Word",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(1, 0, 0, spec.TextSize),
				BackgroundTransparency = 1,
				FontFace = Theme.Font.Display,
				TextSize = spec.TextSize,
				TextColor3 = function()
					return if read(spec.IsInk) then Palette.Ink else Palette.White
				end,
				Text = function()
					return read(spec.Text)
				end,
				ZIndex = 4,
				create("UIScale")({
					Scale = function()
						return 1 + Arrive.WORD_BY * swell()
					end,
				}),
			}),
			create("Frame")({
				Name = "Flash",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Palette.White,
				BorderSizePixel = 0,
				ZIndex = 5,
				Visible = function()
					return flash() > 0.01
				end,
				BackgroundTransparency = function()
					return 1 - flash()
				end,
			}),
		}),
	})
end

return Ribbon
