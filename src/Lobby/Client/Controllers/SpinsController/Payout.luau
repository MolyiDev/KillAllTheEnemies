--!nonstrict
-- The prize flying out of the landed card into the HUD (UI.md 5j): Gems into the Gems pill, XP into the level plate's
-- bar at the head of its fill. Each piece is thrown out of the card against drag, hangs, and is pulled home on a curve
-- that keeps the way it was thrown; the landings are placed, not left to the flights, with the gaps closing, and each
-- one pays its share (the controller lets the HUD's number through a slice at a time).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local SpinsCore = require(ReplicatedStorage.Shared.Core.SpinsCore)
local Parts = require(script.Parent.Parts)
local Types = require(script.Parent.Types)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Scatter = Parts.Scatter

local Tune = table.freeze({
	POOL = 24,
	-- How many pieces carry a prize: more for more, within these.
	MIN = 8,
	MAX = 24,
	-- The landings, from the pieces setting off: the first at FIRST, the last SPAN later, the gaps closing.
	FIRST = 0.55,
	SPAN = 0.8,
	CLOSING = 0.8,
	-- The throw: evenly round the card, out against drag, then turning home.
	REACH_MIN = 90,
	REACH_MAX = 170,
	DRAG = 7,
	HANG_MIN = 0.22,
	HANG_MAX = 0.42,
	-- The pull gets at least this long.
	PULL_MIN = 0.3,
	-- How far it carries on the way it was thrown as it turns, and how far it bows, as shares of the trip home.
	CARRY = 0.25,
	BOW_MIN = 0.15,
	BOW_MAX = 0.35,
	GLYPH = 24,
	-- It arrives at this share of its size, and fades in and out over these shares of its flight.
	ARRIVE_SCALE = 0.55,
	FADE_IN = 0.06,
	FADE_OUT = 0.08,
	-- Where on the target a piece lands: jittered this many px.
	JITTER = 8,
})

-- The landed card's middle in his 1920 x 1080 (Screen's panel at 310, 251; the card under the pointer at 650, 259).
local FROM = Vector2.new(960, 510)

local Payout = {}

-- How long from the pieces setting off to the last landing.
Payout.SECONDS = Tune.FIRST + Tune.SPAN

-- How many pieces carry `prize`.
function Payout.Count(prize: SpinsCore.TPrize): number
	return math.clamp(math.round(4 + math.sqrt(prize.Amount)), Tune.MIN, Tune.MAX)
end

-- When the `rank`th piece of `count` lands, after they set off.
function Payout.ArriveAt(rank: number, count: number): number
	return Tune.FIRST + Tune.SPAN * ((rank - 1) / math.max(count - 1, 1)) ^ Tune.CLOSING
end

local function cubic(a: Vector2, b: Vector2, c: Vector2, d: Vector2, t: number): Vector2
	local u = 1 - t
	return a * (u * u * u) + b * (3 * u * u * t) + c * (3 * u * t * t) + d * (t * t * t)
end

function Payout.Build(state: Types.TSpinsState): { Instance }
	local prize = derive(function(): SpinsCore.TPrize?
		local spin = state.Spin()
		local index = if spin and spin.PayAt then spin.Prize else nil
		return if index and index > 0 then SpinsCore.PRIZES[index] else nil
	end)
	local count = derive(function(): number
		local spin = state.Spin()
		return if spin and spin.Pieces then spin.Pieces else 0
	end)
	local since = derive(function(): number?
		local spin = state.Spin()
		local at = if spin then spin.PayAt else nil
		if not at then return nil end
		local t = state.Now() - at
		return if t >= 0 and t <= Payout.SECONDS + 0.1 then t else nil
	end)

	-- Who lands when has nothing to do with where it was thrown: each piece's place in the landings, a fixed shuffle of
	-- the pieces round the card.
	local ranks = derive(function(): { number }
		local total = count()
		local order = table.create(total)
		for index = 1, total do
			order[index] = index
		end
		table.sort(order, function(a: number, b: number): boolean
			return Scatter(a, 11) < Scatter(b, 11)
		end)

		local byPiece = table.create(total)
		for rank, index in order do
			byPiece[index] = rank
		end

		return byPiece
	end)

	-- What every piece wears: the prize's glyph in its accent, lifted.
	local cell = derive(function(): Vector2
		local current = prize()
		return Components.IconCell(if current and current.Kind == "Xp" then "Rank" else "Gem")
	end)
	local color = derive(function(): Color3
		local current = prize()
		return if current then Parts.AccentOf(current):Lerp(Palette.White, 0.2) else Palette.White
	end)

	local pieces = table.create(Tune.POOL)
	for index = 1, Tune.POOL do
		-- A piece's throw, worked out once a prize: when it lands, where it is thrown, and where it hangs.
		local throw = derive(function()
			local total = count()
			local rank = ranks()[index] or 1
			local arrive = Payout.ArriveAt(rank, total)
			local angle = (index - 1 + (Scatter(index, 14) - 0.5) * 0.8) / math.max(total, 1) * 2 * math.pi
			local heading = Vector2.new(math.cos(angle), math.sin(angle))
			local reach = Tune.REACH_MIN + (Tune.REACH_MAX - Tune.REACH_MIN) * Scatter(index, 15)
			local hangAt = math.clamp(
				Tune.HANG_MIN + (Tune.HANG_MAX - Tune.HANG_MIN) * Scatter(index, 16),
				Tune.HANG_MIN,
				math.max(Tune.HANG_MIN, arrive - Tune.PULL_MIN)
			)
			return {
				Rank = rank,
				Arrive = arrive,
				Heading = heading,
				Reach = reach,
				HangAt = hangAt,
				Hang = FROM + heading * reach * (1 - math.exp(-Tune.DRAG * hangAt)),
				Bow = Tune.BOW_MIN + (Tune.BOW_MAX - Tune.BOW_MIN) * Scatter(index, 17),
			}
		end)
		local flight = derive(function(): number?
			local t = since()
			if not t or index > count() then return nil end
			local arrive = throw().Arrive
			return if t < arrive then t / arrive else nil
		end)
		-- Gems land on the pill's glyph; XP at the head of the bar's fill as the pieces before it left it.
		local target = function(): Vector2
			local current = prize()
			if current and current.Kind == "Xp" then
				local spin = state.Spin()
				local from = spin.BarFrom or 0
				local to = spin.BarTo or from
				local head = from + (to - from) * throw().Rank / math.max(count(), 1)
				return state.BarAt() + Vector2.new(state.BarLength() * math.min(head, 1), Scatter(index, 13) * 6 - 3)
			end

			return state.PillAt() + Vector2.new(Scatter(index, 12) - 0.5, Scatter(index, 13) - 0.5) * 2 * Tune.JITTER
		end

		pieces[index] = Components.Icon("Gem", {
			Name = `Piece{index}`,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				local share = flight()
				if not share then return Parts.PARKED end
				local thrown = throw()
				local t = share * thrown.Arrive
				if t < thrown.HangAt then
					local at = FROM + thrown.Heading * thrown.Reach * (1 - math.exp(-Tune.DRAG * t))
					return UDim2.fromOffset(at.X, at.Y)
				end

				-- From the hang, a curve that first carries on the way it was thrown, then turns home.
				local hang = thrown.Hang
				local land = target()
				local trip = land - hang
				local distance = trip.Magnitude
				local across = Vector2.new(-trip.Y, trip.X) / math.max(distance, 1)
				local turn = if thrown.Heading:Dot(across) >= 0 then 1 else -1
				local s = (t - thrown.HangAt) / math.max(thrown.Arrive - thrown.HangAt, 1e-3)
				local at = cubic(
					hang,
					hang + thrown.Heading * distance * Tune.CARRY,
					land - trip * 0.35 + across * (turn * distance * thrown.Bow),
					land,
					s * s
				)
				return UDim2.fromOffset(at.X, at.Y)
			end,
			Size = Components.GlyphBox(Tune.GLYPH),
			ImageRectOffset = cell,
			ImageColor3 = color,
			ImageTransparency = function()
				local share = flight() or 0
				local appear = math.clamp(share / Tune.FADE_IN, 0, 1)
				local vanish = math.clamp((1 - share) / Tune.FADE_OUT, 0, 1)
				return 1 - math.min(appear, vanish)
			end,
			ZIndex = 20,
			create("UIScale")({
				Scale = function()
					local share = flight() or 0
					return 1 - (1 - Tune.ARRIVE_SCALE) * share * share
				end,
			}),
		})
	end

	return pieces
end

return Payout
