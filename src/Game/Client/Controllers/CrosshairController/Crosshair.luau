--!nonstrict
-- The crosshair, drawing only: four corner brackets round the gun's cone and a dot, with the hit marker as ticks on
-- the four sides between the corners. CrosshairController feeds the sources.
--
-- Every stroke is white on an ink copy a unit bigger all round, so it reads on a white sky and a black wall alike, and
-- a bracket's bend joins cleanly because every ink copy is drawn under every face. Sizes are design pixels (a 1080-tall
-- screen) times Unit, the screen's height over 1080, and every edge is rounded to a whole screen pixel, so a line is
-- crisp at any size.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)

local create = vide.create
local source = vide.source
local Palette = Theme.Palette
local round = math.round

export type TState = {
	Now: vide.Source<number>,
	Unit: vide.Source<number>,
	Position: vide.Source<UDim2>,
	IsVisible: vide.Source<boolean>,
	-- Design pixels from the middle to the edge of the gun's cone, and how far its last shot threw the corners out.
	Spread: vide.Source<number>,
	Kick: vide.Source<number>,
	IsArmed: vide.Source<boolean>,
	ArmedAt: vide.Source<number>,
	IsOnTarget: vide.Source<boolean>,
	TargetAt: vide.Source<number>,
	FiredAt: vide.Source<number>,
	HitAt: vide.Source<number>,
	-- Hits close together, from 1: each draws the hit marker a little longer.
	Streak: vide.Source<number>,
	KillAt: vide.Source<number>,
	IsOverkill: vide.Source<boolean>,
	HurtAt: vide.Source<number>,
}

-- What moves, each value derived on its own: a derive stops when its value comes out the same, so a stroke's property
-- runs again only when what it draws from changed, not on every frame of every gesture.
type TMotion = {
	-- The corners' opacity: 0 unarmed, when only the dot is left.
	Shown: () -> number,
	-- Design pixels from the middle to a corner's outer edge.
	Reach: () -> number,
	-- 1 at the answer, falling to 0; KillT runs 0 to 1 through the kill.
	Hit: () -> number,
	KillT: () -> number,
	Face: () -> Color3,
	Mark: () -> Color3,
}

local Crosshair = {}

-- Seconds. A hit is gone in a fifth of a second, so a stream of them reads as a flicker and never a pile.
local Timing = table.freeze({
	ARM_IN = 0.26,
	ARM_OUT = 0.12,
	TARGET_IN = 0.06,
	TARGET_OUT = 0.12,
	KICK = 0.14,
	HIT = 0.2,
	KILL = 0.42,
	HURT = 0.3,
})
-- How long after an answer starts the clock has to keep running for every gesture to land.
Crosshair.LONGEST = 0.45

-- Design pixels. Strokes are as heavy as the toy HUD's: a 4-pixel face in a 1-pixel ink line, about 40 across.
--
-- THE HIT TICKS RUN THROUGH THE GAPS BETWEEN THE CORNERS, so a side's gap (twice REACH less LEG, at the smallest cone
-- and locked on) must stay wider than a tick with its ink (THICK plus twice INK), or the marker lands on the brackets.
local Look = table.freeze({
	THICK = 4,
	INK = 1,
	INK_OPACITY = 0.85,
	DOT = 4,
	-- The corners sit the gun's cone out from the middle (never nearer than MIN_GAP nor further than MAX_GAP) plus
	-- REACH, with legs LEG long. Past SOFT_GAP a cone counts SOFT_SLOPE a pixel, so a shotgun's wide cone does not
	-- open the corners across the screen and the wider guns still read wider. They come in from FLY further out, lock
	-- LOCK in on an enemy, flick FLICK out on a hit, and burst BURST out with a quarter turn (SPIN) on a kill.
	MIN_GAP = 6,
	SOFT_GAP = 16,
	SOFT_SLOPE = 0.25,
	MAX_GAP = 32,
	REACH = 11,
	LEG = 9,
	FLY = 16,
	LOCK = 3,
	FLICK = 3,
	BURST = 8,
	SPIN = 90,
	-- The hit marker: four ticks on the axes from MARK_IN out, drifting MARK_DRIFT as they fade, popped MARK_POP
	-- bigger at the hit; a kill's are longer and bolder. Full for the first MARK_HOLD of their life.
	MARK = 8,
	MARK_KILL = 12,
	MARK_KILL_THICK = 6,
	MARK_IN = 7,
	MARK_DRIFT = 5,
	MARK_POP = 0.4,
	MARK_HOLD = 0.5,
	STREAK_GROWTH = 0.12,
	MAX_STREAK = 5,
})

local AXES = table.freeze({ Vector2.new(1, 0), Vector2.new(-1, 0), Vector2.new(0, 1), Vector2.new(0, -1) })
local CORNERS = table.freeze({ Vector2.new(1, 1), Vector2.new(-1, 1), Vector2.new(1, -1), Vector2.new(-1, -1) })
local LEGS = table.freeze({ Vector2.new(Look.LEG, Look.THICK), Vector2.new(Look.THICK, Look.LEG) })

type TLayers = { Root: Frame, Ink: Frame, Face: Frame }
type TColour = () -> Color3
type TOpacity = () -> number

-- A fresh set of sources, at rest and unarmed.
function Crosshair.State(): TState
	return {
		Now = source(0),
		Unit = source(1),
		Position = source(UDim2.new()),
		IsVisible = source(true),
		Spread = source(0),
		Kick = source(0),
		IsArmed = source(false),
		ArmedAt = source(-math.huge),
		IsOnTarget = source(false),
		TargetAt = source(-math.huge),
		FiredAt = source(-math.huge),
		HitAt = source(-math.huge),
		Streak = source(1),
		KillAt = source(-math.huge),
		IsOverkill = source(false),
		HurtAt = source(-math.huge),
	}
end

local function moving(state: TState): TMotion
	local derive = vide.derive
	-- Through the arming gesture: in when armed, out when not.
	local armedT = derive(function()
		local seconds = if state.IsArmed() then Timing.ARM_IN else Timing.ARM_OUT
		return Motion.Progress(state.Now(), state.ArmedAt(), seconds)
	end)
	local target = derive(function()
		return if state.IsOnTarget()
			then Motion.Out(Motion.Progress(state.Now(), state.TargetAt(), Timing.TARGET_IN))
			else 1 - Motion.Progress(state.Now(), state.TargetAt(), Timing.TARGET_OUT)
	end)
	local hit = derive(function()
		return Motion.Fade(state.Now(), state.HitAt(), Timing.HIT)
	end)
	local killT = derive(function()
		return Motion.Progress(state.Now(), state.KillAt(), Timing.KILL)
	end)
	local hurt = derive(function()
		return Motion.Fade(state.Now(), state.HurtAt(), Timing.HURT)
	end)

	return {
		Shown = derive(function()
			local t = armedT()
			return if state.IsArmed() then math.min(t * 3, 1) else 1 - t
		end),
		Reach = derive(function()
			local t = armedT()
			local armed = if state.IsArmed() then Motion.OutBack(t) else 1 - Motion.Accelerate(t)
			-- Out at once, back fast and then gently.
			local kickLeft = 1 - Motion.Progress(state.Now(), state.FiredAt(), Timing.KICK)
			local flick = hit()
			local burst = 1 - killT()
			local spread = state.Spread()
			local gap = if spread > Look.SOFT_GAP
				then Look.SOFT_GAP + (spread - Look.SOFT_GAP) * Look.SOFT_SLOPE
				else spread
			return math.clamp(gap, Look.MIN_GAP, Look.MAX_GAP)
				+ Look.REACH
				+ state.Kick() * kickLeft * kickLeft
				+ (1 - armed) * Look.FLY
				- Look.LOCK * target()
				+ Look.FLICK * flick * flick
				+ Look.BURST * burst * burst
		end),
		Hit = hit,
		KillT = killT,
		Face = derive(function()
			local face = Palette.White:Lerp(Palette.Pink, target())
			local hurtLeft = hurt()
			return if hurtLeft > 0 then face:Lerp(Theme.Color.Hurt, hurtLeft) else face
		end),
		Mark = derive(function()
			return if state.IsOverkill() then Palette.Gold else Palette.Pink
		end),
	}
end

-- The ink fades ahead of the face, so a fading stroke thins to its colour rather than to a grey band.
local function inkTransparency(opacity: number): number
	return 1 - Look.INK_OPACITY * opacity * opacity
end

-- The ink line in whole screen pixels, at least one.
local function inkPixels(unit: number): number
	return math.max(1, round(Look.INK * unit))
end

-- A zero-size frame on the crosshair's Position holding an ink layer under a face layer, both turned by `rotation`
-- about the middle.
local function layers(state: TState, rotation: () -> number): TLayers
	local function layer(name: string, zIndex: number): Frame
		return create("Frame")({
			Name = name,
			BackgroundTransparency = 1,
			Size = UDim2.new(),
			ZIndex = zIndex,
			Rotation = rotation,
		})
	end

	local ink, face = layer("Ink", 1), layer("Face", 2)
	local root = create("Frame")({
		Name = "Crosshair",
		BackgroundTransparency = 1,
		Size = UDim2.new(),
		Position = state.Position,
		Visible = state.IsVisible,
		ink,
		face,
	})
	return { Root = root, Ink = ink, Face = face }
end

-- An upright stroke over the rect `rect` returns (left, top, right, bottom: design pixels from the middle, +y down),
-- its edges on whole screen pixels so it never straddles one. `colour` and `opacity` should be derives, or they redraw
-- the stroke every frame the clock runs.
local function box(
	into: TLayers,
	state: TState,
	rect: () -> (number, number, number, number),
	colour: TColour,
	opacity: TOpacity
)
	-- The face in whole screen pixels; the ink copy is the same rect grown by its ink on every side.
	local pixels = vide.derive(function()
		local unit = state.Unit()
		local left, top, right, bottom = rect()
		return Rect.new(round(left * unit), round(top * unit), round(right * unit), round(bottom * unit))
	end)

	local function frame(isInk: boolean, parent: Frame, color: Color3 | TColour, transparency: TOpacity)
		create("Frame")({
			Parent = parent,
			BorderSizePixel = 0,
			BackgroundColor3 = color,
			BackgroundTransparency = transparency,
			Position = function()
				local at = pixels().Min
				local ink = if isInk then inkPixels(state.Unit()) else 0
				return UDim2.fromOffset(at.X - ink, at.Y - ink)
			end,
			Size = function()
				local edges = pixels()
				local ink = if isInk then inkPixels(state.Unit()) else 0
				return UDim2.fromOffset(edges.Width + 2 * ink, edges.Height + 2 * ink)
			end,
			create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
		})
	end

	frame(true, into.Ink, Palette.Ink, function()
		return inkTransparency(opacity())
	end)
	frame(false, into.Face, colour, function()
		return 1 - opacity()
	end)
end

-- From `from` to `to` along one axis's `sign`, low end first.
local function span(sign: number, from: number, to: number): (number, number)
	local a, b = sign * from, sign * to
	return math.min(a, b), math.max(a, b)
end

-- The four corners, each a leg along either side (LEGS) meeting at the outer corner.
local function brackets(into: TLayers, state: TState, motion: TMotion)
	local reach = motion.Reach

	for _, corner in CORNERS do
		for _, leg in LEGS do
			box(into, state, function()
				local out = reach()
				local left, right = span(corner.X, out - leg.X, out)
				local top, bottom = span(corner.Y, out - leg.Y, out)
				return left, top, right, bottom
			end, motion.Face, motion.Shown)
		end
	end
end

-- The hit marker: white ticks shooting out through the sides, longer for a streak; a kill's are longer, bolder and
-- pink (gold for an overkill).
local function ticks(into: TLayers, state: TState, motion: TMotion)
	local derive = vide.derive
	local isKill = derive(function()
		return motion.KillT() < 1
	end)
	-- 1 at the answer showing, falling to 0.
	local life = derive(function()
		return if isKill() then 1 - motion.KillT() else motion.Hit()
	end)
	local colour = derive(function()
		return if isKill() then motion.Mark() else Palette.White
	end)
	local opacity = derive(function()
		return math.min(life() / Look.MARK_HOLD, 1)
	end)

	for _, direction in AXES do
		box(into, state, function()
			local alive = life()
			local streak = 1 + Look.STREAK_GROWTH * (math.min(state.Streak(), Look.MAX_STREAK) - 1)
			local length = (if isKill() then Look.MARK_KILL else Look.MARK * streak) * (1 + Look.MARK_POP * alive ^ 4)
			local inner = Look.MARK_IN + Look.MARK_DRIFT * (1 - alive)
			local half = (if isKill() then Look.MARK_KILL_THICK else Look.THICK) / 2
			if direction.X ~= 0 then
				local left, right = span(direction.X, inner, inner + length)
				return left, -half, right, half
			end
			local top, bottom = span(direction.Y, inner, inner + length)
			return -half, top, half, bottom
		end, colour, opacity)
	end
end

-- The pointer itself, there armed or not: a hit pops it a design pixel each side.
local function dot(into: TLayers, state: TState, motion: TMotion)
	box(
		into,
		state,
		function()
			local half = Look.DOT / 2 + motion.Hit()
			return -half, -half, half, half
		end,
		motion.Face,
		function()
			return 1
		end
	)
end

-- The crosshair, centred on its Position. Everything turns together, so a kill's quarter turn carries the ticks with
-- the corners and they never cross.
function Crosshair.Build(state: TState): Frame
	local motion = moving(state)
	local into = layers(
		state,
		vide.derive(function()
			local killT = motion.KillT()
			return if killT < 1 then Look.SPIN * Motion.OutBack(killT) else 0
		end)
	)

	brackets(into, state, motion)
	ticks(into, state, motion)
	dot(into, state, motion)

	return into.Root
end

return Crosshair
