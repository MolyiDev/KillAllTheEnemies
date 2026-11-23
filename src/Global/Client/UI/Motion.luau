-- The UI's curves (UI.md 5c): a thing that MOVES in arrives on easeOutBack and leaves on easeInBack, a thing that
-- APPEARS eases out with no overshoot, and a panel arrives decelerating and leaves accelerating. Every gesture is
-- driven by hand from a start time and a length, so it lands ON its number rather than creeping toward it.
local Motion = {}

-- 0 at `at`, 1 once `seconds` have passed.
function Motion.Progress(now: number, at: number, seconds: number, delay: number?): number
	return math.clamp((now - at - (delay or 0)) / seconds, 0, 1)
end

-- Away at once, gentle onto the mark.
function Motion.Out(t: number): number
	return 1 - (1 - t) * (1 - t)
end

-- Fluent's decelerate: for panels arriving.
function Motion.Decelerate(t: number): number
	return 1 - (1 - t) ^ 3
end

-- Material's accelerate: for panels leaving.
function Motion.Accelerate(t: number): number
	return t * t * t
end

-- Sails about 10% past the mark and settles back.
function Motion.OutBack(t: number): number
	local s = 1.70158
	local u = t - 1
	return 1 + (s + 1) * u * u * u + s * u * u
end

-- Lifts off the mark, then runs out fast.
function Motion.InBack(t: number): number
	local s = 1.70158
	return (s + 1) * t * t * t - s * t * t
end

-- 0 to 1 and back to 0 as `t` runs 0 to 1, exactly 0 outside it: a dip or a lift that leaves nothing behind.
function Motion.Bump(t: number): number
	if t <= 0 or t >= 1 then return 0 end
	return math.sin(math.pi * t)
end

-- A swing that starts at rest, goes out, comes back past the middle and dies as `t` runs 0 to 1.
function Motion.Swing(t: number): number
	if t <= 0 or t >= 1 then return 0 end
	return math.sin(t * math.pi * 3) * (1 - t) * (1 - t)
end

-- A refusal's shake of the head, -1 to 1 as `t` runs 0 to 1: out to one side at once, as far out to the other, then
-- eased back onto the mark. `at` is the refusal's stamp: its millisecond picks the side, so one refusal after another
-- does not always lean the same way, and the side holds for the whole shake.
function Motion.Shake(t: number, at: number): number
	if t <= 0 or t >= 1 then return 0 end
	local side = if math.floor(at * 1000) % 2 == 0 then 1 else -1
	if t < 0.75 then return side * math.sin(t * math.pi * 2) end
	return -side * (1 + math.cos((t - 0.75) * 4 * math.pi)) / 2
end

-- 1 at `at`, falling to 0 over `seconds`: a flash or a punch.
function Motion.Fade(now: number, at: number, seconds: number): number
	return 1 - math.clamp((now - at) / seconds, 0, 1)
end

function Motion.Lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

return Motion
