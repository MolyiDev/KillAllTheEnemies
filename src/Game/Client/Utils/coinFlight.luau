-- How a coin flies from a kill into its taker: thrown out against drag until it hangs, then pulled by a magnet that
-- only gets stronger, aimed at where he is THIS frame and over the crowd between, coming down into him. Pure, so `tools/lune/coins.luau` flies it headless.
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

local Tune = CoinFlight.Tune

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

return CoinFlight
