-- The body pose's tuning, shared by its parts. Angles in radians, distances in studs, rates per second.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(script.Parent.Types)
local TData = require(ReplicatedStorage.Types.TData)

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
	-- First person the body's gun is hidden: its barrel sits here, out of the camera, and the arms are not solved.
	HOLD_FIRST_PERSON = Vector3.new(1.25, 0.2, -1.55),
	-- The grip sits this far inside the hand's block rather than on its face.
	HAND_INSET = 0.2,
	-- An arm slides along itself at most this far into the shoulder and out of it, so the gun can sit where it looks
	-- right rather than wherever rigid arms reach; a kick lets them in further (KICK_SLIDE). Rounds of pulling the
	-- hands into reach: each one closes most of what the last left.
	ARM_SLIDE_IN = 0.15,
	ARM_SLIDE_OUT = 0.5,
	SETTLE_ROUNDS = 4,
	-- Drawing a gun: it comes up from low and pointing down, carries a little past the hold and settles.
	RAISE_TIME = 0.32,
	RAISE_DROP = 1.1,
	RAISE_TILT = 0.9,
	RAISE_OVERSHOOT = 1.4,
	-- A shot's jolt: its spring, how far it throws the arms up, and how much of it the hands, muzzle, head and chest
	-- take. KICK_BACK shoves the gun back along its barrel and KICK_SLIDE lets the arms into the shoulders with it.
	KICK_SPEED = 30,
	KICK_DAMPER = 0.45,
	KICK_ANGLE = math.rad(11),
	KICK_BACK = 1,
	KICK_SLIDE = 1,
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
	LEG_BLADE = 0.5,
	LEG_RATE = 12,
	BACKPEDAL_ANGLE = math.rad(100),
	BACKPEDAL_HYSTERESIS = math.rad(12),
	LEG_MIN_SPEED = 1.5,
}

-- Per hold, third person (in the aim frame at the torso's centre): where the barrel's line passes at the right hand's
-- depth, how far the torso turns right off the aim (bringing the left shoulder forward to a grip far up the gun; the
-- head turns back onto the aim), and how far under its grip each hand sits (right, left), so the gun rests on a
-- hand's face instead of through its block (negative: over it, for a handle on top). The hands go on the gun's own
-- grips (TGun.Hands); the gun stays here while the arms can reach it, sliding out of the shoulders, and moves the
-- least it must when they cannot.
Tune.HOLDS = table.freeze({
	Rifle = { Grip = Vector3.new(0.65, 0.85, -0.9), Blade = math.rad(65), Drop = Vector2.new(0.25, 0.45) },
	Pistol = { Grip = Vector3.new(0.7, 0.75, -1.5), Blade = math.rad(25), Drop = Vector2.new(0.15, 0.35) },
	Heavy = { Grip = Vector3.new(0.8, -0.7, -1.0), Blade = math.rad(55), Drop = Vector2.new(-0.3, -0.3) },
	Launcher = { Grip = Vector3.new(1.0, 1.35, -1.0), Blade = math.rad(40), Drop = Vector2.new(0.25, 0.25) },
}) :: { [TData.TGunHold]: Types.THold }

-- The pivots as offsets, built once.
Tune.PIVOT_CFRAME = CFrame.new(0, Tune.PIVOT, 0)
Tune.UNPIVOT_CFRAME = Tune.PIVOT_CFRAME:Inverse()
Tune.HIP_CFRAME = CFrame.new(0, -Tune.HIP, 0)
Tune.UNHIP_CFRAME = Tune.HIP_CFRAME:Inverse()
Tune.FEET_CFRAME = CFrame.new(0, -Tune.FEET_DEPTH, 0)
Tune.UNFEET_CFRAME = Tune.FEET_CFRAME:Inverse()

return table.freeze(Tune)
