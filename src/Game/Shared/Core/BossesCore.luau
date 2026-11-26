-- What both sides agree on about a boss's fight: where a target stands round its body, how its runs move, and its
-- intro's clock and camera, so the server times and the client draws the same things.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TData = require(ReplicatedStorage.Types.TData)

local BossesCore = {}

-- A guard's glow (TEnemy.Glow): its own Highlight's fill, this transparent between hits.
BossesCore.GLOW_TRANSPARENCY = 0.55

-- The intro's roar plays in slow motion: at ROAR_SPEED for ROAR_SLOW seconds of real time, then back up to full speed
-- over ROAR_RAMP. The camera, the effects and the server's hold all run off IntroClock, so they agree.
BossesCore.ROAR_SPEED = 0.3
BossesCore.ROAR_SLOW = 0.7
BossesCore.ROAR_RAMP = 0.6

-- A turn on the spot goes to its left (the way its turn clip is authored) up to this far round, else the short way to
-- its right. Past a chained charge's widest turn (180 + BossService's CHAIN_ARC of 45), so the client's drawn yaw
-- being a little off never flips one.
local TURN_LEFT_MOST = math.rad(240)

-- The intro's camera keys, as delivered with the scene (its BossCutscene script): authored at the delivered body's
-- scale 1, in the ground frame of the delivered RootPart (where the walk-in ends, a little ahead of the hips), x to
-- the body's right, -z ahead of it. IntroFrame turns them into world space. Each shot is a run of keys (time on the intro's clock, eye, look, field of view, roll in degrees,
-- the ease INTO the key); a shot starts where the last one ends, with a cut.
export type TShotKey = {
	Time: number,
	Eye: Vector3,
	Look: Vector3,
	Fov: number,
	Roll: number,
	Ease: string?,
}

local function key(time: number, eye: Vector3, look: Vector3, fov: number, roll: number?, ease: string?): TShotKey
	return { Time = time, Eye = eye, Look = look, Fov = fov, Roll = roll or 0, Ease = ease }
end

local V = Vector3.new
BossesCore.INTRO_SHOTS = table.freeze({
	TRex = table.freeze({
		-- Ground level, feet stomping out of the fog.
		{
			key(0.0, V(3.8, 0.7, 2.5), V(1.0, 1.2, 8.0), 55, 4),
			key(1.75, V(3.4, 0.9, 1.0), V(0.8, 1.7, 5.0), 52, 1, "Linear"),
		},
		-- A low dolly backwards as it walks at the camera, the skull looming.
		{
			key(1.75, V(-2.5, 2.0, -9.0), V(0, 5.5, -1.0), 60, -3),
			key(3.6, V(-2.0, 2.4, -14.5), V(0, 6.2, -5.0), 55, 0, "Out"),
		},
		-- Round the head while it hunts, ending eye to eye.
		{
			key(3.6, V(8.0, 6.0, -3.0), V(0, 6.3, -5.5), 50, 0),
			key(4.6, V(6.0, 5.5, -11.0), V(0, 6.3, -5.5), 48, 0, "Linear"),
			key(5.6, V(0.8, 6.0, -12.0), V(0, 6.5, -5.5), 40, 0, "Out"),
		},
		-- A dutch low angle for the stomp.
		{
			key(5.6, V(9.0, 0.6, 4.0), V(0.5, 2.5, -3.0), 72, -9),
			key(6.7, V(8.2, 0.7, 2.5), V(0.5, 3.0, -3.0), 70, -7, "Linear"),
		},
		-- A tight creep on the skull as it coils up.
		{
			key(6.7, V(1.5, 4.2, -11.0), V(0, 4.2, -5.0), 40, 2),
			key(7.35, V(1.1, 4.1, -9.5), V(0, 4.3, -5.0), 38, 0, "In"),
		},
		-- The roar: a low three-quarter profile arcing round to the front.
		{
			key(7.35, V(7.5, 2.0, -10.5), V(0, 8.5, -4.0), 80, -4),
			key(8.3, V(4.5, 3.0, -13.0), V(0, 9.0, -4.0), 76, 3, "Out"),
			key(9.45, V(-2.0, 4.0, -13.5), V(0, 8.5, -3.0), 70, 4, "Linear"),
		},
		-- A snap in on the chomp.
		{
			key(9.45, V(1.5, 4.8, -10.0), V(0, 4.8, -4.0), 38, 0),
			key(9.75, V(1.3, 4.7, -9.2), V(0, 4.7, -4.0), 36, 0, "Out"),
		},
		-- The hero pull back, craning up for the title.
		{
			key(9.75, V(1.5, 3.5, -10.0), V(0, 4.5, -3.0), 55, 0),
			key(12.9, V(4.0, 9.0, -24.0), V(0, 4.0, -2.0), 60, 0, "InOut"),
		},
	}),
})
-- The delivered body's scale times the rig's (built at 0.7, ScaleTo'd 1.25 in the place): a key's studs at the size
-- the boss is played.
BossesCore.INTRO_KEY_SCALE = 2.2859 * 0.875

-- "Front", "Behind" or "Beside": where `target` stands round a body at `at` facing `yaw` (TEnemyBoss's arcs).
function BossesCore.Facing(kit: TData.TEnemyBoss, at: vector, yaw: number, target: vector): TData.TEnemyAttackFacing
	local dx, dz = target.x - at.x, target.z - at.z
	local distance = math.sqrt(dx * dx + dz * dz)
	if distance <= kit.UnderRadius then return "Beside" end
	local off = math.deg(math.acos(math.clamp((dx * math.sin(yaw) + dz * math.cos(yaw)) / distance, -1, 1)))
	if off <= kit.FrontArc then return "Front" end
	if off >= 180 - kit.RearArc then return "Behind" end
	return "Beside"
end

-- How many times as long as authored its moves take at health share `share`: TempoStart at full health, TempoEnd at
-- none. Its clips play at 1 / this, so their blows still land on the warnings.
function BossesCore.Tempo(kit: TData.TEnemyBoss, share: number): number
	local u = math.clamp(share, 0, 1)
	return kit.TempoEnd + (kit.TempoStart - kit.TempoEnd) * u
end

-- Tempo for its wind-ups and clips: never under WindupTempoMin.
function BossesCore.WindupTempo(kit: TData.TEnemyBoss, share: number): number
	return math.max(BossesCore.Tempo(kit, share), kit.WindupTempoMin)
end

-- How far a skid has slid `seconds` in: `speed` bled off evenly over `stop` seconds.
function BossesCore.SkidDistance(speed: number, stop: number, seconds: number): number
	local t = math.clamp(seconds, 0, stop)
	return speed * t - speed * t * t / (2 * stop)
end

-- How far round (radians, + to its left) a turn on the spot from `fromYaw` onto `toYaw` goes (TURN_LEFT_MOST). Both
-- sides go by this, so the body is drawn turning the way the server turns it.
function BossesCore.TurnDelta(fromYaw: number, toYaw: number): number
	local left = (toYaw - fromYaw) % (2 * math.pi)
	return if left <= TURN_LEFT_MOST then left else left - 2 * math.pi
end

-- The intro's clock after `seconds` of real time: (the cutscene's clock, the clip's time, the clip's speed now). The
-- clip runs at full speed, slows for the roar and ramps back, and stops at its end (speed 0, the cue to hand over to
-- the idle) while the clock runs on to End.
function BossesCore.IntroClock(intro: TData.TEnemyBossIntro, seconds: number): (number, number, number)
	local roar = intro.Roar
	if seconds <= roar then return seconds, seconds, 1 end

	local slow, ramp, speed = BossesCore.ROAR_SLOW, BossesCore.ROAR_RAMP, BossesCore.ROAR_SPEED
	local clip: number
	local clipSpeed = 1
	local after = seconds - roar
	if after <= slow then
		clip = roar + after * speed
		clipSpeed = speed
	elseif after <= slow + ramp then
		local u = (after - slow) / ramp
		clip = roar + slow * speed + (after - slow) * (speed + (1 - speed) * u / 2)
		clipSpeed = speed + (1 - speed) * u
	else
		clip = roar + slow * speed + ramp * (1 + speed) / 2 + (after - slow - ramp)
	end

	if clip <= intro.Length then return clip, clip, clipSpeed end
	return clip, intro.Length, 0
end

-- The intro's length in real seconds: until its clock reaches End.
function BossesCore.IntroSeconds(intro: TData.TEnemyBossIntro): number
	local slow, ramp, speed = BossesCore.ROAR_SLOW, BossesCore.ROAR_RAMP, BossesCore.ROAR_SPEED
	local covered = slow * speed + ramp * (1 + speed) / 2
	return intro.End + (slow + ramp) - covered
end

-- The frame the intro's camera keys are in, for a boss standing at `stage`: ShotsAhead in front of it, turned round,
-- since the delivered body faced -Z and ours face +Z.
function BossesCore.IntroFrame(stage: CFrame, intro: TData.TEnemyBossIntro): CFrame
	return stage * CFrame.new(0, 0, intro.ShotsAhead) * CFrame.Angles(0, math.pi, 0)
end

return BossesCore
