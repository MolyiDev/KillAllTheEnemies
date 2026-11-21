-- The body pose's tuning, shared by its parts. Angles in radians, distances in studs, rates per second.
local Tune = {
	-- Aim: how far the torso and head turn toward it, and how fast the pose follows it (exponential).
	TWIST_TORSO = math.rad(80),
	TWIST_HEAD = math.rad(55),
	TWIST_RATE = 10,
	RATE = 16,
	PITCH_MIN = math.rad(-70),
	PITCH_MAX = math.rad(80),
	-- Share of the pitch the head takes; the arms take all of it.
	HEAD_SHARE = 0.65,
	-- The torso turns about a point this high over its centre (the chest) and the hips below it.
	PIVOT = 1,
	HIP = 1,
	-- The feet, under the root's centre: the lean tips the body from here.
	FEET_DEPTH = 3,
	-- Where the right hand holds the grip, in the aim frame at the chest: third person, and first person.
	HOLD = Vector3.new(0.3, 1, -1.35),
	HOLD_FIRST_PERSON = Vector3.new(1.25, 0.2, -1.55),
	-- The left hand on the barrel: this far along the gun from the grip (a share of its length) and this far under it.
	FORE = 0.42,
	UNDER = 0.12,
	-- A gun shorter than this (studs to the muzzle) is a pistol: both hands on the grip, the left at SUPPORT.
	PISTOL_LENGTH = 1.6,
	SUPPORT = Vector3.new(-0.18, -0.2, 0.12),
	-- A shot's jolt: its spring, how far it throws the arms up, and how much of it the hands, muzzle, head and chest
	-- take.
	KICK_SPEED = 30,
	KICK_DAMPER = 0.45,
	KICK_ANGLE = math.rad(11),
	KICK_BACK = 2,
	KICK_MUZZLE = 0.6,
	KICK_HEAD = 0.9,
	KICK_CHEST = 0.6,
	-- Head nearer the target than this, or the aim is taken along the look instead.
	MIN_TARGET_DISTANCE = 2,
	-- Lean: at full walk speed, and at full acceleration (studs/s/s), forward and sideways. The sum is held to
	-- LEAN_MAX. Backpedalling leans back by the speed term; braking by the acceleration term.
	LEAN_SPEED_REFERENCE = 22,
	LEAN_SPEED_PITCH = math.rad(7),
	LEAN_SPEED_ROLL = math.rad(5),
	LEAN_ACCEL_REFERENCE = 110,
	LEAN_ACCEL_PITCH = math.rad(11),
	LEAN_ACCEL_ROLL = math.rad(13),
	LEAN_MAX = math.rad(18),
	-- The acceleration is smoothed over about this long, so one physics step's spike is not a lean.
	ACCEL_SMOOTHING = 0.08,
	-- The lean's spring: rad/s and a damping ratio under 1, so it overshoots once and settles.
	LEAN_FREQUENCY = 13,
	LEAN_DAMPING = 0.5,
	LEAN_AIR_SHARE = 0.35,
	-- Faster than this up or down (studs/s) is in the air. Read off the velocity, which replicates for every body,
	-- where a Humanoid's floor is only simulated for the local one.
	AIRBORNE_SPEED = 6,
	-- A landing tips the body forward by this much per stud/s of fall, into the lean spring.
	LAND_KICK_PER_SPEED = 0.06,
	LAND_KICK_MAX = 3,
	-- Share of the lean the head takes back, so the eyes stay on the target.
	HEAD_LEVEL = 0.85,
	-- The hips turn toward the walk up to LEG_MAX; past BACKPEDAL_ANGLE off the facing (with the hysteresis) the walk
	-- is backwards instead and the hips turn toward its opposite. Slower than LEG_MIN_SPEED (studs/s) is standing.
	LEG_MAX = math.rad(60),
	LEG_RATE = 12,
	BACKPEDAL_ANGLE = math.rad(100),
	BACKPEDAL_HYSTERESIS = math.rad(12),
	LEG_MIN_SPEED = 1.5,
}

-- The pivots as offsets, built once.
Tune.PIVOT_CFRAME = CFrame.new(0, Tune.PIVOT, 0)
Tune.UNPIVOT_CFRAME = Tune.PIVOT_CFRAME:Inverse()
Tune.HIP_CFRAME = CFrame.new(0, -Tune.HIP, 0)
Tune.UNHIP_CFRAME = Tune.HIP_CFRAME:Inverse()
Tune.FEET_CFRAME = CFrame.new(0, -Tune.FEET_DEPTH, 0)
Tune.UNFEET_CFRAME = Tune.FEET_CFRAME:Inverse()

return table.freeze(Tune)
