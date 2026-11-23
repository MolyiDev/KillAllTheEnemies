--!nonstrict
-- Gems a claim pays, bursting out of where they were won (a daily reward's gem, a quest's reward) and pulled into the
-- lobby HUD's Gems pill (UI.md 5j): thrown out
-- round the gem against drag, they hang, then each is pulled home on its own bend, carrying on the way it was thrown
-- before it turns. They land one at a time on a closing beat, each handing the pill its slice, so the count climbs in
-- ticks you can count, and the last one lands the whole amount.
--
-- Drawn in screen px on a full-screen layer with no scale of its own, since both ends are measured off the screen
-- (the card's gem, the pill's glyph). A fixed pool, stepped by the controller every frame while it is busy.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.vide)
local Icons = require(script.Parent.Icons)
local Motion = require(script.Parent.Motion)
local Theme = require(script.Parent.Theme)

local create = vide.create
local Palette = Theme.Palette

-- Distances are design px at 1080, multiplied by the screen's scale.
local Tune = table.freeze({
	COUNT = 22,
	POOL = 32,
	-- The throw: how far out, the drag that stops it (1 - e^(-k t): half its reach in 0.1 s), and its spin, in degrees a
	-- second, dying as e^(-SPIN_DECAY t).
	REACH_MIN = 150,
	REACH_MAX = 300,
	DRAG = 7,
	SPIN = 900,
	SPIN_DECAY = 2,
	-- The landings, from the burst: the first at FIRST, the last at FIRST + SPREAD, the gaps closing as order^CLOSE (73
	-- ms between the first two, 31 between the last two).
	FIRST = 0.55,
	SPREAD = 0.9,
	CLOSE = 0.8,
	-- The hang, and the least time a pull home may take.
	HANG_MIN = 0.22,
	HANG_MAX = 0.42,
	PULL_MIN = 0.3,
	-- The pull: how far it carries on the way it was thrown, and its bend as a share of the trip.
	CARRY_MIN = 90,
	CARRY_MAX = 200,
	BEND_MIN = 0.15,
	BEND_MAX = 0.35,
	HOME_SHARE = 0.35,
	-- A piece's glyph (its longest side), its pop into being, its shrink as it is drunk in and its last fade.
	SIZE_MIN = 22,
	SIZE_MAX = 34,
	BIRTH = 0.08,
	ARRIVED = 0.45,
	EXIT = 0.06,
	-- The streak behind it: its length is the distance it covers in this long, up to MAX.
	STREAK_SECONDS = 0.05,
	STREAK_MAX = 80,
	STREAK_WIDTH = 0.35,
	STREAK_TRANSPARENCY = 0.35,
	-- Spread round the pill's glyph where they land.
	LAND_JITTER = 7,
	-- Whatever is still owed by then is handed over, flown or not.
	DEADLINE = 1.8,
})

-- A lifted shade of what they came off (a chip at the exact colour of its source reads as a hole), the gem and white.
local COLORS = table.freeze({
	-- His gem blue (UIMatt.md, Daily Rewards).
	Color3.fromRGB(89, 191, 255),
	Color3.fromRGB(160, 225, 255),
	Palette.White,
})

export type TPayout = {
	Layer: Frame,
	-- Throws `amount` Gems from `from` (screen px) at `now`. `onLand(owed)` is called on each landing with what is
	-- still in the air; 0 on the last.
	Burst: (from: Vector2, amount: number, now: number, onLand: (owed: number) -> ()) -> (),
	-- Moves every piece; false once nothing is left to do.
	Step: (now: number) -> boolean,
}

local GemPayout = {}

local function cubic(a: Vector2, b: Vector2, c: Vector2, d: Vector2, t: number): Vector2
	local u = 1 - t
	return a * (u * u * u) + b * (3 * u * u * t) + c * (3 * u * t * t) + d * (t * t * t)
end

-- `scale` is the screen's px per design px; `target` where the pill's glyph is now, in screen px (nil while there is
-- none: they land where it was last seen).
function GemPayout.Build(scale: () -> number, target: () -> Vector2?): TPayout
	local random = Random.new()
	local pieces = table.create(Tune.POOL)
	local icons = table.create(Tune.POOL)
	local streaks = table.create(Tune.POOL)
	for index = 1, Tune.POOL do
		icons[index] = create("ImageLabel")({
			Name = "Gem",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Image = Icons.IMAGE,
			ImageRectOffset = Icons.Cells.Gem,
			ImageRectSize = Icons.CELL_SIZE,
			ScaleType = Enum.ScaleType.Fit,
			Visible = false,
			ZIndex = 2,
		})
		streaks[index] = create("Frame")({
			Name = "Streak",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 1,
			create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
			-- Solid at the piece, nothing at its tail.
			create("UIGradient")({
				Transparency = NumberSequence.new(1, Tune.STREAK_TRANSPARENCY),
			}),
		})
	end

	local layer = create("Frame")({
		Name = "Payout",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 50,
		streaks,
		icons,
	})

	-- The pool slot thrown last: each throw takes the one after it, so the oldest is reused.
	local cursor = 0
	local burstAt = -math.huge
	local amount, count, landed = 0, 0, 0
	local land: ((owed: number) -> ())? = nil
	local lastTarget = Vector2.zero
	local lastNow = 0

	-- Hands over everything up to the `rank`th landing.
	local function payTo(rank: number)
		if rank <= landed or not land then return end
		landed = rank
		local owed = if rank >= count then 0 else amount - math.floor(amount * rank / count)
		land(owed)
		if owed == 0 then land = nil end
	end

	local function hide(piece)
		piece.IsLive = false
		icons[piece.Index].Visible = false
		streaks[piece.Index].Visible = false
	end

	local function burst(from: Vector2, total: number, now: number, onLand: (owed: number) -> ())
		-- A burst still owing settles first, or its Gems would land on the new one's count.
		if land then payTo(count) end
		for _, piece in pieces do
			hide(piece)
		end
		table.clear(pieces)

		amount, count, landed, land = total, Tune.COUNT, 0, onLand
		burstAt = now
		lastNow = now
		local unit = scale()
		lastTarget = target() or lastTarget

		-- Who lands when has nothing to do with where it was thrown.
		local ranks = table.create(count)
		for rank = 1, count do
			ranks[rank] = rank
		end
		for index = count, 2, -1 do
			local other = random:NextInteger(1, index)
			ranks[index], ranks[other] = ranks[other], ranks[index]
		end

		for index = 1, count do
			cursor = cursor % Tune.POOL + 1
			local rank = ranks[index]
			local order = (rank - 1) / (count - 1)
			local arrive = Tune.FIRST + Tune.SPREAD * order ^ Tune.CLOSE
			local hangAt = random:NextNumber(
				Tune.HANG_MIN,
				math.max(Tune.HANG_MIN, math.min(Tune.HANG_MAX, arrive - Tune.PULL_MIN))
			)
			-- Evenly round the circle, then jittered, so the star has no gap and no pattern.
			local angle = (index + random:NextNumber(-0.4, 0.4)) / count * 2 * math.pi
			local out = Vector2.new(math.cos(angle), math.sin(angle))
			local glyph = random:NextNumber(Tune.SIZE_MIN, Tune.SIZE_MAX)
			local color = COLORS[random:NextInteger(1, #COLORS)]
			pieces[index] = {
				Index = cursor,
				IsLive = true,
				From = from,
				Out = out,
				Reach = random:NextNumber(Tune.REACH_MIN, Tune.REACH_MAX) * unit,
				HangAt = hangAt,
				Arrive = arrive,
				Carry = random:NextNumber(Tune.CARRY_MIN, Tune.CARRY_MAX) * unit,
				Bend = random:NextNumber(Tune.BEND_MIN, Tune.BEND_MAX),
				Land = Vector2.new(random:NextNumber(-1, 1), random:NextNumber(-1, 1)) * Tune.LAND_JITTER * unit,
				Spin = if random:NextNumber() < 0.5 then Tune.SPIN else -Tune.SPIN,
				Side = math.round(glyph / Icons.GLYPH_SHARE * unit),
				Rank = rank,
				Last = from,
			}
			icons[cursor].ImageColor3 = color
			streaks[cursor].BackgroundColor3 = color
		end
	end

	local function step(now: number): boolean
		if not land and #pieces == 0 then return false end
		local age = now - burstAt
		if age >= Tune.DEADLINE then payTo(count) end

		local dt = math.max(now - lastNow, 1 / 240)
		lastNow = now
		lastTarget = target() or lastTarget
		local layerAt = layer.AbsolutePosition
		local layerSize = layer.AbsoluteSize
		local unit = scale()
		local isBusy = false

		for _, piece in pieces do
			if not piece.IsLive then continue end
			if age >= piece.Arrive or age >= Tune.DEADLINE then
				hide(piece)
				payTo(piece.Rank)
				continue
			end
			isBusy = true

			local reach = piece.Out * piece.Reach
			local at: Vector2
			local size = 1
			local alpha = 0
			if age < piece.HangAt then
				at = piece.From + reach * (1 - math.exp(-Tune.DRAG * age))
			else
				local hang = piece.From + reach * (1 - math.exp(-Tune.DRAG * piece.HangAt))
				local home = lastTarget + piece.Land
				local chord = home - hang
				local distance = math.max(chord.Magnitude, 1)
				local across = Vector2.new(-chord.Y, chord.X) / distance
				-- It bows the way it was already heading.
				local turn = if piece.Out.X * chord.Y - piece.Out.Y * chord.X >= 0 then 1 else -1
				local s = (age - piece.HangAt) / (piece.Arrive - piece.HangAt)
				at = cubic(
					hang,
					hang + piece.Out * piece.Carry,
					home + (hang - home) * Tune.HOME_SHARE + across * (turn * distance * piece.Bend),
					home,
					s * s
				)
				if s > 0.5 then size = 1 - (1 - Tune.ARRIVED) * (s - 0.5) / 0.5 end
				alpha = 1 - math.clamp((1 - s) / Tune.EXIT, 0, 1)
			end
			if age < Tune.BIRTH then
				size *= Motion.OutBack(age / Tune.BIRTH)
			end

			local icon, streak = icons[piece.Index], streaks[piece.Index]
			local side = math.max(1, math.round(piece.Side * size))
			icon.Position = UDim2.fromScale((at.X - layerAt.X) / layerSize.X, (at.Y - layerAt.Y) / layerSize.Y)
			icon.Size = UDim2.fromOffset(side, side)
			icon.Rotation = piece.Spin / Tune.SPIN_DECAY * (1 - math.exp(-Tune.SPIN_DECAY * age))
			icon.ImageTransparency = alpha
			icon.Visible = true

			-- The streak: the motion it has just made, centred half a streak back, since a frame turns about its middle.
			local moved = at - piece.Last
			piece.Last = at
			local length = math.min(moved.Magnitude / dt * Tune.STREAK_SECONDS, Tune.STREAK_MAX * unit)
			if length > 2 then
				local heading = moved.Unit
				local middle = at - heading * (length / 2)
				streak.Position =
					UDim2.fromScale((middle.X - layerAt.X) / layerSize.X, (middle.Y - layerAt.Y) / layerSize.Y)
				streak.Size = UDim2.fromOffset(length, math.max(2, side * Tune.STREAK_WIDTH))
				streak.Rotation = math.deg(math.atan2(heading.Y, heading.X))
				streak.BackgroundTransparency = alpha
				streak.Visible = true
			else
				streak.Visible = false
			end
		end

		if not isBusy then table.clear(pieces) end
		return isBusy or land ~= nil
	end

	return {
		Layer = layer,
		Burst = burst,
		Step = step,
	}
end

return GemPayout
