--!nonstrict
-- What every health bar in the HUD does on top of its look (the boss's and the player's). The fill chases the truth on
-- a quick spring that carries a hair past a blow; the ghost behind it holds what was just taken, then drains, or runs
-- ahead with what is being given back; and a blow throws chips of the bar off its cut. A bar's owner steps its chase
-- once a frame (Step, Write: init for the player's, BossBar.Update for the boss's); the bars draw the track it writes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Types = require(script.Parent.Types)

local create = vide.create
local derive = vide.derive
local source = vide.source
local Palette = Theme.Palette

-- The springs' fixed step, so a long frame cannot throw one off.
local STEP = 1 / 120
-- The fill on a blow: fast, and just underdamped, so it carries a few percent of the bite past and comes back. Given
-- back, it rises slowly and lands soft, so the band ahead of it is seen filling.
local QUICK_PERIOD = 0.14
local QUICK_DAMPING = 0.62
local HEAL_PERIOD = 0.55
-- The ghost holds the bite this long, then falls on a spring from rest: it hangs, then goes.
local HOLD_SECONDS = 0.45
local GHOST_PERIOD = 0.6
-- A blow while the ghost is already falling throws it back up, so each hit opens the band wider than itself and is
-- seen, scaled by the bite: a bar takes hits orders of magnitude apart.
local BAND_IMPULSE = 2.2
-- Under this share of the bar a drop is a rounding wobble or a tick, not a blow: nothing flashes or flies.
local BLOW_FLOOR = 0.002
-- Closer than this (a share of the bar) and a spring is home: it is put there, so a settled bar writes nothing.
local SETTLE = 1e-4

-- A blow's light: how long it lasts, and how much of the fill it washes white a share of the bar bitten. Only a big
-- blow washes the fill (a stream of small ones would hold it pale); every blow lights the cut.
local FLASH_SECONDS = 0.16
local FLASH_PER_BITE = 6

-- Chips: the drag on them and how much of each one's life is spent fading.
local CHIP_DRAG = 5
local CHIP_FADE_SHARE = 0.5
-- Each chip's launch, in degrees off straight up (or down), and the share launched upward.
local CHIP_SPREAD_DEG = 35
local CHIP_UP_SHARE = 0.6
-- How much of a chip is lifted toward white: a piece in the air at the bar's own colour reads as a hole.
local CHIP_LIFT = 0.35

local BarJuice = {}

-- The blows a track remembers at once: their chips fly on while the next ones land.
BarJuice.BLOWS = 4

-- How a bar's numbers move, in its own units (health, or a share). Plain values, stepped by Step.
export type TChase = {
	Fill: number,
	FillVelocity: number,
	Ghost: number,
	GhostVelocity: number,
	Target: number,
	HoldUntil: number,
	IsHealing: boolean,
}

-- What a bar's chips look like. Sizes in design px, speeds in px a second.
export type TChipLook = {
	-- The most chips one blow throws, and the share of the bar each one stands for.
	PerBlow: number,
	SharePerChip: number,
	Size: number,
	SpeedMin: number,
	SpeedMax: number,
	Gravity: number,
	Life: number,
	-- The share of the bar the chips are born across, centred on the cut: nil for a point.
	Spread: number?,
	-- A source of the bar's colour where it was cut.
	Color: () -> Color3,
}

function BarJuice.NewChase(value: number): TChase
	return {
		Fill = value,
		FillVelocity = 0,
		Ghost = value,
		GhostVelocity = 0,
		Target = value,
		HoldUntil = -math.huge,
		IsHealing = false,
	}
end

function BarJuice.NewTrack(): Types.TBarTrack
	local blows = table.create(BarJuice.BLOWS)
	for index = 1, BarJuice.BLOWS do
		blows[index] = {
			At = source(-math.huge),
			Cut = source(0),
			Bite = source(0),
			Seed = source(0),
		}
	end

	return {
		Fill = source(0),
		Ghost = source(0),
		IsHealing = source(false),
		Blows = blows,
		Count = 0,
		HitAt = source(-math.huge),
		HitBite = source(0),
	}
end

local function spring(x: number, v: number, goal: number, period: number, damping: number, dt: number): (number, number)
	local w = 2 * math.pi / period
	local stiffness, friction = w * w, 2 * w * damping
	while dt > 0 do
		local h = math.min(dt, STEP)
		v += (-(x - goal) * stiffness - v * friction) * h
		x += v * h
		dt -= h
	end

	return x, v
end

-- Steps `chase` toward `target` (of `full`, the bar's whole length) by `dt`. `isSnap` puts it there with no motion
-- (the bar growing into a bought level). Returns the bite of a blow that landed this frame, a share of the bar, or 0.
function BarJuice.Step(chase: TChase, target: number, full: number, dt: number, now: number, isSnap: boolean): number
	if isSnap or full <= 0 then
		chase.Fill, chase.FillVelocity = target, 0
		chase.Ghost, chase.GhostVelocity = target, 0
		chase.Target = target
		return 0
	end

	local bite = (chase.Target - target) / full
	chase.Target = target
	if bite > BLOW_FLOOR then
		-- The ghost keeps what was on show. A blow on a resting ghost holds it; one on a falling ghost throws it back.
		local isResting = chase.IsHealing or chase.Ghost - chase.Fill < SETTLE * full
		chase.Ghost = math.max(if chase.IsHealing then chase.Fill else chase.Ghost, chase.Fill)
		chase.IsHealing = false
		if isResting then
			chase.GhostVelocity = 0
			chase.HoldUntil = now + HOLD_SECONDS
		elseif now >= chase.HoldUntil then
			chase.GhostVelocity += bite * BAND_IMPULSE * full
		end
	else
		bite = 0
	end

	if target > chase.Ghost then chase.IsHealing = true end
	local isGivenBack = chase.IsHealing and target > chase.Fill
	chase.Fill, chase.FillVelocity = spring(
		chase.Fill,
		chase.FillVelocity,
		target,
		if isGivenBack then HEAL_PERIOD else QUICK_PERIOD,
		if isGivenBack then 1 else QUICK_DAMPING,
		dt
	)
	if math.abs(chase.Fill - target) < SETTLE * full and math.abs(chase.FillVelocity) < SETTLE * full then
		chase.Fill, chase.FillVelocity = target, 0
	end

	if chase.IsHealing then
		chase.Ghost, chase.GhostVelocity = target, 0
	elseif now >= chase.HoldUntil then
		chase.Ghost, chase.GhostVelocity = spring(chase.Ghost, chase.GhostVelocity, chase.Fill, GHOST_PERIOD, 1, dt)
	end

	if chase.Ghost - chase.Fill < SETTLE * full then
		chase.Ghost, chase.GhostVelocity = chase.Fill, 0
		chase.IsHealing = false
	end

	return bite
end

-- Puts a blow of `bite` (a share of the bar) cut at `cut` into `track`'s ring.
function BarJuice.Throw(track: Types.TBarTrack, cut: number, bite: number, now: number)
	track.Count += 1
	local blow = track.Blows[(track.Count - 1) % BarJuice.BLOWS + 1]
	blow.At(now)
	blow.Cut(cut)
	blow.Bite(bite)
	blow.Seed(math.random())
	track.HitAt(now)
	track.HitBite(bite)
end

-- Writes `chase` into `track`, and a blow of `bite` (from Step) cut at `cut`.
function BarJuice.Write(track: Types.TBarTrack, chase: TChase, bite: number, cut: number, now: number)
	track.Fill(chase.Fill)
	track.Ghost(chase.Ghost)
	track.IsHealing(chase.IsHealing)
	if bite > 0 then BarJuice.Throw(track, cut, bite, now) end
end

-- A blow's light, as two sources a bar reads wherever it likes: the white it washes over the fill (as strong as its
-- bite) and the light on the cut (full on every blow), both gone inside a sixth of a second. Derived, so they are
-- worked out once a frame however many pieces read them, and settle at 0 without waking anything.
function BarJuice.Lights(state: Types.THudState, track: Types.TBarTrack): (() -> number, () -> number)
	local flare = derive(function(): number
		local k = Motion.Fade(state.Now(), track.HitAt(), FLASH_SECONDS)
		return k * k
	end)

	local flash = derive(function(): number
		local k = flare()
		return if k > 0 then math.min(track.HitBite() * FLASH_PER_BITE, 1) * k else 0
	end)

	return flash, flare
end

-- A number from 0 to 1 that looks random and is the same for the same `x`.
local function hash(x: number): number
	return (math.sin(x * 12.9898) * 43758.5453) % 1
end

-- One chip's flight, worked out once a blow: its life in seconds, where along the bar it is born (a share), which edge
-- (0 the top, 1 the bottom) and its launch in px a second.
type TFlight = {
	Life: number,
	Born: number,
	Edge: number,
	Launch: Vector2,
}

-- The chips a bar's blows throw, over the bar (a Frame its size: a chip is placed by a share of its width). Each is
-- a square of the bar's colour born on the bar's top or bottom edge at the cut, flying away from it under drag and
-- a light gravity, shrinking and fading out; the gravity is low enough for its size that one thrown up never falls
-- back into the bar while it can be seen. A spent chip costs one comparison a frame: its age stays 1.
function BarJuice.Chips(state: Types.THudState, track: Types.TBarTrack, look: TChipLook): Frame
	local chips = table.create(BarJuice.BLOWS * look.PerBlow)
	local count = 0
	local lifted = derive(function(): Color3
		return look.Color():Lerp(Palette.White, CHIP_LIFT)
	end)

	local fall = look.Gravity / CHIP_DRAG
	for blowIndex, blow in track.Blows do
		for index = 1, look.PerBlow do
			local salt = blowIndex * 31 + index * 7.13
			-- nil when its blow threw fewer chips than this one's index, or there has been no blow yet: then its age reads
			-- no clock at all.
			local flight = derive(function(): TFlight?
				local bite = blow.Bite()
				if bite <= 0 or index > math.clamp(math.ceil(bite / look.SharePerChip), 1, look.PerBlow) then
					return nil
				end
				local seed = blow.Seed()
				local angle = math.rad((hash(seed * 17 + salt) * 2 - 1) * CHIP_SPREAD_DEG)
				local speed = Motion.Lerp(look.SpeedMin, look.SpeedMax, hash(seed * 5 + salt * 3))
				local isUp = hash(seed * 3 + salt * 5) < CHIP_UP_SHARE
				local spread = look.Spread or 0
				return {
					Life = look.Life * (0.8 + 0.4 * hash(seed * 11 + salt * 2)),
					Born = blow.Cut() + (hash(seed * 13 + salt * 1.7) - 0.5) * spread,
					Edge = if isUp then 0 else 1,
					Launch = Vector2.new(math.sin(angle), if isUp then -math.cos(angle) else math.cos(angle)) * speed,
				}
			end)

			-- 0 to 1 over its life; 1 when it is spent or was never thrown.
			local age = derive(function(): number
				local current = flight()
				if not current then return 1 end
				return math.clamp((state.Now() - blow.At()) / current.Life, 0, 1)
			end)

			count += 1
			chips[count] = create("Frame")({
				Name = "Chip",
				AnchorPoint = Vector2.new(0.5, 0.5),
				BorderSizePixel = 0,
				ZIndex = 8,
				BackgroundColor3 = if index % 3 == 0 then Palette.White else lifted,
				BackgroundTransparency = function()
					local t = age()
					if t <= 0 or t >= 1 then return 1 end
					local fade = math.clamp((t - (1 - CHIP_FADE_SHARE)) / CHIP_FADE_SHARE, 0, 1)
					return fade * fade
				end,
				Size = function()
					local side = math.max(math.round(look.Size * (1 - 0.6 * age())), 1)
					return UDim2.fromOffset(side, side)
				end,
				-- Under linear drag: the launch carried out and spent, and gravity's drift.
				Position = function()
					local t = age()
					local current = flight()
					if t <= 0 or t >= 1 or not current then return UDim2.fromScale(0, 0.5) end
					local seconds = t * current.Life
					local carry = (1 - math.exp(-CHIP_DRAG * seconds)) / CHIP_DRAG
					local launch = current.Launch
					local y = fall * seconds + (launch.Y - fall) * carry
					return UDim2.new(current.Born, math.round(launch.X * carry), current.Edge, math.round(y))
				end,
			})
		end
	end

	return create("Frame")({
		Name = "Chips",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 8,
		chips,
	})
end

return BarJuice
