-- How a coin flies from a kill into its taker: thrown out against drag until it hangs, then pulled by a magnet that
-- only gets stronger, aimed at where he is THIS frame and over the crowd between, coming down into him. And how a
-- bought pack's coins fly (the Shower): out of the buyer and back into him, each landing at a time it was given.
-- Pure, so `tools/lune/coins.luau` flies both headless.
local CoinFlight = {}

CoinFlight.Tune = table.freeze({
	-- The throw: fast off the body, most of it eaten by drag in a quarter second, so it hangs instead of falling.
	DRAG = 7,
	GRAVITY = Vector3.new(0, -22, 0),
	-- A taker this close starts the pull at this share of the hang: walking into his coins never makes them wait.
	NEAR_STUDS = 10,
	NEAR_HANG_SHARE = 0.3,
	-- The pull keeps going the way the coin was thrown before it turns, so it comes home on a curve; a share of the
	-- trip, so a coin at his feet does not swing out wide first.
	CARRY_SPEED = 9,
	CARRY_PER_STUD = 0.5,
	PULL_SPEED = 4,
	-- Harder for a longer trip, so a kill across the field pays out without dragging.
	PULL_ACCEL = 110,
	PULL_ACCEL_PER_STUD = 1.5,
	MAX_SPEED = 200,
	-- The pull aims this share of the remaining ground distance ABOVE him, up to the cap, so it arcs over the zombies
	-- in the way (a body is 5 studs tall) and drops into him as the distance closes. It leaves already rising.
	ARC_SHARE = 0.45,
	ARC_MAX_STUDS = 12,
	LIFT_SPEED = 14,
	LIFT_PER_STUD = 0.8,
	-- How fast the heading swings onto him, per second; it grows, so the carry turns into a lock without orbiting.
	TURN_RATE = 2.5,
	TURN_GROWTH = 30,
	ARRIVE_STUDS = 1,
	-- Whatever happens, a coin is in after this long.
	MAX_SECONDS = 3,
})

-- A bought Gold pack's coins (CoinsController). Every time is seconds from the purchase, and every place is from
-- the buyer's chest, so the shower goes where he goes and lands on its beats however he moves.
CoinFlight.Shower = table.freeze({
	-- The first coin lands at FIRST and the last at LAST, the gaps between them closing: a rattle that speeds up.
	-- The pack's sound has its closing hit on LAST (Assets/sounds/Review/GoldPack), and the HUD and the burst on the
	-- body strike on it too: moving it moves all three.
	FIRST = 0.62,
	LAST = 1.5,
	GAPS = 0.8,
	-- How many coins carry a pack and how far from the chest they are thrown (studs, out and up). A pack of BIG_FROM
	-- Gold or more is a big one: more coins, thrown BIG_REACH times as far, and a bigger burst (goldFx).
	COINS = 24,
	COINS_BIG = 40,
	OUT_MIN = 3.5,
	OUT_MAX = 7.5,
	UP_MIN = 2.5,
	UP_MAX = 8,
	BIG_FROM = 10000,
	BIG_REACH = 1.35,
	-- The throw: 1 - e^(-DRAG t) of its reach, so half of it in a tenth of a second, then a slow sink while it hangs.
	DRAG = 7,
	SINK_SPEED = 0.9,
	-- The pull home takes this long, from standing and faster and faster; a coin hangs until it starts.
	PULL_MIN = 0.26,
	PULL_MAX = 0.36,
	-- Before it turns home the coin carries on the way it was thrown by this share of its distance, and its path
	-- bows to one side by a share of it between these.
	CARRY = 0.3,
	BOW_MIN = 0.2,
	BOW_MAX = 0.5,
})

local Tune = CoinFlight.Tune
local Shower = CoinFlight.Shower

export type TFlight = {
	Position: Vector3,
	Velocity: Vector3,
	-- The horizontal way it was thrown, which the pull carries on.
	Out: Vector3,
	Age: number,
	HangSeconds: number,
	IsPulling: boolean,
	PullAge: number,
	PullAccel: number,
}

-- One coin of a shower, in studs from the buyer's chest.
export type TShower = {
	-- Where the throw would stop with no sink.
	Reach: Vector3,
	HangAt: number,
	LandAt: number,
	-- The pull's curve from where the coin hung (its end is the chest, the origin).
	Hang: Vector3,
	Carry: Vector3,
	Turn: Vector3,
}

function CoinFlight.New(at: Vector3, velocity: Vector3, hangSeconds: number): TFlight
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	return {
		Position = at,
		Velocity = velocity,
		Out = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zero,
		Age = 0,
		HangSeconds = hangSeconds,
		IsPulling = false,
		PullAge = 0,
		PullAccel = 0,
	}
end

-- Advances one frame toward `target`; true when it has landed.
function CoinFlight.Step(flight: TFlight, target: Vector3, dt: number): boolean
	flight.Age += dt
	local offset = target - flight.Position
	local distance = offset.Magnitude
	if distance <= Tune.ARRIVE_STUDS or flight.Age >= Tune.MAX_SECONDS then return true end

	if not flight.IsPulling then
		flight.Velocity = flight.Velocity * math.exp(-Tune.DRAG * dt) + Tune.GRAVITY * dt
		flight.Position += flight.Velocity * dt
		local hang = if distance < Tune.NEAR_STUDS
			then flight.HangSeconds * Tune.NEAR_HANG_SHARE
			else flight.HangSeconds
		if flight.Age < hang then return false end
		flight.IsPulling = true
		flight.PullAccel = Tune.PULL_ACCEL + distance * Tune.PULL_ACCEL_PER_STUD
		flight.Velocity += flight.Out * math.min(Tune.CARRY_SPEED, distance * Tune.CARRY_PER_STUD) + Vector3.new(
			0,
			math.min(Tune.LIFT_SPEED, distance * Tune.LIFT_PER_STUD),
			0
		)
		return false
	end

	flight.PullAge += dt
	local pullAge = flight.PullAge
	local speed = math.min(Tune.PULL_SPEED + flight.PullAccel * pullAge, Tune.MAX_SPEED)
	local steer = 1 - math.exp(-(Tune.TURN_RATE + Tune.TURN_GROWTH * pullAge) * dt)
	local ground = Vector3.new(offset.X, 0, offset.Z).Magnitude
	local aim = offset + Vector3.new(0, math.min(ground * Tune.ARC_SHARE, Tune.ARC_MAX_STUDS), 0)
	flight.Velocity = flight.Velocity:Lerp(aim * (speed / aim.Magnitude), steer)
	local step = flight.Velocity * dt
	-- A step that would reach him lands this frame rather than passing through and turning back.
	if step:Dot(offset) >= distance * distance then return true end

	flight.Position += step
	return false
end

-- When the coin landing `rank`th of `count` lands, seconds from the purchase.
local function showerLanding(rank: number, count: number): number
	local order = if count > 1 then (rank - 1) / (count - 1) else 1
	return Shower.FIRST + (Shower.LAST - Shower.FIRST) * order ^ Shower.GAPS
end

local function showerThrow(reach: Vector3, age: number): Vector3
	return reach * (1 - math.exp(-Shower.DRAG * age)) - Vector3.new(0, Shower.SINK_SPEED * age, 0)
end

-- A coin thrown to `reach` that lands at `landAt`. `pull` is how long its trip home takes, `bow` the share of its
-- distance its path bows by, to the left of its throw when negative.
local function newShower(reach: Vector3, landAt: number, pull: number, bow: number): TShower
	local hangAt = math.max(landAt - pull, 0)
	local hang = showerThrow(reach, hangAt)
	local distance = hang.Magnitude
	local flat = Vector3.new(reach.X, 0, reach.Z)
	local across = if flat.Magnitude > 1e-3 then flat.Unit:Cross(Vector3.yAxis) else Vector3.xAxis
	return {
		Reach = reach,
		HangAt = hangAt,
		LandAt = landAt,
		Hang = hang,
		Carry = hang + reach.Unit * (distance * Shower.CARRY),
		Turn = hang * 0.35 + across * (distance * bow),
	}
end

-- The coins of a pack of `amount` Gold, thrown all round the buyer: evenly round the circle and then jittered, so
-- there is no gap and no pattern, and who lands when shuffled apart from where it was thrown. `random` is a Random.
function CoinFlight.ThrowShower(amount: number, random: Random): { TShower }
	local isBig = amount >= Shower.BIG_FROM
	local count = math.min(if isBig then Shower.COINS_BIG else Shower.COINS, amount)
	local scale = if isBig then Shower.BIG_REACH else 1
	local turn = random:NextNumber(0, 2 * math.pi)
	local ranks = table.create(count)
	for i = 1, count do
		ranks[i] = i
	end
	for i = count, 2, -1 do
		local j = random:NextInteger(1, i)
		ranks[i], ranks[j] = ranks[j], ranks[i]
	end

	local showers = table.create(count)
	for i = 1, count do
		local angle = turn + (i + random:NextNumber(-0.4, 0.4)) / count * 2 * math.pi
		local out = random:NextNumber(Shower.OUT_MIN, Shower.OUT_MAX) * scale
		local up = random:NextNumber(Shower.UP_MIN, Shower.UP_MAX) * scale
		local bow = random:NextNumber(Shower.BOW_MIN, Shower.BOW_MAX)
		showers[i] = newShower(
			Vector3.new(math.cos(angle) * out, up, math.sin(angle) * out),
			showerLanding(ranks[i], count),
			random:NextNumber(Shower.PULL_MIN, Shower.PULL_MAX),
			if random:NextNumber() < 0.5 then bow else -bow
		)
	end

	return showers
end

-- Where the coin is `age` seconds after the purchase, from the buyer's chest. It has landed from LandAt on.
function CoinFlight.ShowerAt(shower: TShower, age: number): Vector3
	if age <= shower.HangAt then return showerThrow(shower.Reach, age) end
	local u = math.min((age - shower.HangAt) / (shower.LandAt - shower.HangAt), 1)
	local s = u * u
	local k = 1 - s
	-- A cubic from the hang to the chest; its last point is the origin.
	return shower.Hang * (k * k * k) + shower.Carry * (3 * k * k * s) + shower.Turn * (3 * k * s * s)
end

return CoinFlight
