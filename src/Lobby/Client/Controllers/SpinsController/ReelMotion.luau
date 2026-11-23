-- Where the reel stands and how fast it turns, worked out from a spin's plan and the clock (no state of its own): a
-- press winds it back a hair and throws it, it runs flat out until the server has answered, then brakes onto the
-- prize, stopping anywhere inside its card and easing onto its middle. Positions are in slots (slot k rests under the
-- pointer at offset k). Simulated in lune: 4.6 to 5.4 s a spin, the last card taking 0.3 to 0.75 s.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SpinsCore = require(ReplicatedStorage.Shared.Core.SpinsCore)
local Types = require(script.Parent.Types)

local Run = table.freeze({
	WINDUP = 0.16,
	-- How far it is wound back before the throw, in slots.
	BACK = 0.2,
	RAMP = 0.3,
	-- Slots a second flat out.
	TOP = 24,
	-- It runs flat out at least this long before braking, however fast the answer came.
	CRUISE = 0.3,
	-- The fewest slots the brake covers: the seven prizes come round four times on the way.
	TRAVEL = 26,
	-- Where in its card it stops, as a share of a slot off the middle either way, before it eases onto the middle.
	JITTER = 0.42,
	SETTLE = 0.5,
	-- A refused spin brakes onto the nearest slot this far on.
	REFUSED_TRAVEL = 5,
})

local ReelMotion = {}

ReelMotion.TOP = Run.TOP
ReelMotion.SETTLE = Run.SETTLE

-- Where the reel stands at `now` and how fast it turns (slots a second): resting on `rest` with no spin.
function ReelMotion.At(spin: Types.TSpin?, rest: number, now: number): (number, number)
	if not spin then return rest, 0 end

	local brakeAt = spin.BrakeAt
	if brakeAt and now >= brakeAt then
		local seconds = spin.BrakeSeconds :: number
		local s = math.clamp((now - brakeAt) / seconds, 0, 1)
		if s < 1 then
			return (spin.BrakeFrom :: number) + Run.TOP * seconds / 3 * (1 - (1 - s) ^ 3), Run.TOP * (1 - s) ^ 2
		end

		-- Settled onto the slot's middle on a smoothstep: it starts and ends at rest.
		local stop = spin.StopAt :: number
		local slot = spin.Slot :: number
		local u = math.clamp((now - brakeAt - seconds) / Run.SETTLE, 0, 1)
		return stop + (slot - stop) * u * u * (3 - 2 * u), (slot - stop) * 6 * u * (1 - u) / Run.SETTLE
	end

	local t = now - spin.StartAt
	if t < 0 then return spin.From, 0 end
	if t < Run.WINDUP then
		local u = t / Run.WINDUP
		return spin.From - Run.BACK * math.sin(math.pi * u) ^ 2,
			-Run.BACK * math.pi / Run.WINDUP * math.sin(2 * math.pi * u)
	end

	t -= Run.WINDUP
	if t < Run.RAMP then return spin.From + Run.TOP * t * t / (2 * Run.RAMP), Run.TOP * t / Run.RAMP end
	return spin.From + Run.TOP * Run.RAMP / 2 + Run.TOP * (t - Run.RAMP), Run.TOP
end

-- The spin once the server has answered at `now` with `prize` (0: refused): when it brakes, where it stops and when
-- it has landed. `jitter` is where in the card it stops, -1 to 1.
function ReelMotion.Plan(spin: Types.TSpin, prize: number, now: number, jitter: number): Types.TSpin
	local brakeAt = math.max(now, spin.StartAt + Run.WINDUP + Run.RAMP + Run.CRUISE)
	-- Still running flat out when it brakes, so the rest it would have had makes no difference.
	local from = ReelMotion.At(spin, spin.From, brakeAt)
	local slot, stop
	if prize == 0 then
		slot = math.ceil(from + Run.REFUSED_TRAVEL)
		stop = slot
	else
		local off = Run.JITTER * jitter
		slot = math.ceil(from + Run.TRAVEL - off)
		while SpinsCore.PrizeAt(slot) ~= prize do
			slot += 1
		end
		stop = slot + off
	end

	local brake = 3 * (stop - from) / Run.TOP
	local planned = table.clone(spin)
	planned.BrakeAt = brakeAt
	planned.BrakeFrom = from
	planned.BrakeSeconds = brake
	planned.StopAt = stop
	planned.Slot = slot
	planned.Prize = prize
	planned.LandAt = brakeAt + brake + Run.SETTLE
	return planned
end

return table.freeze(ReelMotion)
