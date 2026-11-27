-- A boss's fight (PlanBosses.md): which of its attacks it makes and when, and the ones that are more than a ground
-- warning: a charge's run and skid, a dive under the floor, the guards it raises and the shield they hold up, a pounce's
-- leap, a brood's hang out of reach over the egg sacs it lays. Also
-- what players' gadgets do to it: slowed by foam, baited by a decoy, each once in a while (canControl).
--
-- enemiesUpdate walks a boss between attacks and never starts one; while busy here its AttackWindup is positive (the
-- body held where it stands, keeping its yaw), and through a run or a dive this moves it. Every warning goes through
-- EnemyAttacksService.Telegraph, so what is drawn is what hurts. Clients are told each move (Bosses.Move) to play its
-- clip and drive the body exactly where it goes here. Everything runs on TimeCore.EnemyClock, so a freeze, a pause
-- or an intro holds the fight where it stands.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local Network = require(ServerScriptService.GlobalServer.Network)
local CharacterService = require(script.Parent.CharacterService)
local DefenseService = require(script.Parent.DefenseService)
local EnemiesService = require(script.Parent.EnemiesService)
local EnemyAttacksService = require(script.Parent.EnemyAttacksService)
local EnemyMovementService = require(script.Parent.EnemyMovementService)
local NavService = require(script.Parent.NavService)
local TimeService = require(script.Parent.TimeService)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local ArenaCore = require(ReplicatedStorage.Shared.Core.ArenaCore)
local BossesCore = require(ReplicatedStorage.Shared.Core.BossesCore)
local EnemiesCore = require(ReplicatedStorage.Shared.Core.EnemiesCore)
local TelegraphCore = require(ReplicatedStorage.Shared.Core.TelegraphCore)
local TimeCore = require(ReplicatedStorage.Shared.Core.TimeCore)
local Components = require(ReplicatedStorage.GlobalShared.ECS.Components)
local Tags = require(ReplicatedStorage.GlobalShared.ECS.Tags)
local EnemyWorld = require(ReplicatedStorage.GlobalShared.ECS.Worlds.EnemyWorld)
local World = require(ReplicatedStorage.GlobalShared.ECS.Worlds.World)
local getCharacterFeet = require(ReplicatedStorage.GlobalShared.Utils.Functions.getCharacterFeet)
local getPlayerFromCharacterEntity =
	require(ReplicatedStorage.GlobalShared.Utils.Functions.getPlayerFromCharacterEntity)
local EBossMoves = require(ReplicatedStorage.Types.Enums.EBossMoves)
local ETelegraphs = require(ReplicatedStorage.Types.Enums.ETelegraphs)
local TData = require(ReplicatedStorage.Types.TData)

local ServerNetworkBosses = Network.Server.Bosses

local ENEMIES = DataCore.Enemies.ById
local EnemiesSpatialHash = EnemiesCore.EnemiesSpatialHash
local NO_NODE = ArenaCore.NO_NODE

local BossQuery =
	EnemyWorld
		:query(Components.Position, Components.Yaw, Components.CurrentHealth, Components.MaxHealth, Components.Data)
		:with(Tags.Boss)
		:cached()
-- Who a boss goes for: standing, and not picking an upgrade.
local CharactersQuery = World:query(Components.HumanoidRootPart, Components.Humanoid, Components.InstanceId)
	:with(Tags.Character, Tags.Alive)
	:without(Tags.Picking)
	:cached()

local Tune = table.freeze({
	-- Seconds a boss walks after one attack before it may start the next: room to turn and come on.
	REST = 0.35,
	-- How often a free boss looks for its next move.
	THINK_SECONDS = 0.1,
	-- Of the moves that would land, each is drawn by weight: 1, plus up to FRESH_WEIGHT as FRESH_SECONDS pass since
	-- it was last made, and the move it just made at REPEAT_SHARE of that. Moves it has not shown in a while come up.
	FRESH_WEIGHT = 2,
	FRESH_SECONDS = 20,
	REPEAT_SHARE = 0.25,
	-- A player's run is read smoothed over about this many seconds: one frame's velocity is a jump, a dodge's first
	-- step or a knockback, and a lead off it throws a charge or a spine to the wrong side.
	VELOCITY_SMOOTHING = 0.35,
	-- A charge leads its target at most this many degrees off the straight line to them: wide enough that a runner
	-- who keeps running meets it, since its wind-up and run give them seconds to cross a narrower lead.
	CHARGE_LEAD_ARC = 45,
	-- A chained charge turns onto its target only within this many degrees of straight back; farther round, it stops.
	CHAIN_ARC = 45,
	-- A target this much higher or lower than the boss counts this many studs farther when picking whom to go for.
	LEVEL_GAP = 6,
	LEVEL_PENALTY = 25,
	-- A boss that moved less than this in STUCK_SECONDS while its target is beyond its reach is stuck.
	STUCK_STUDS = 3,
	STUCK_SECONDS = 3,
	-- A charge shorter than this, a wall in the way, is not worth making.
	MIN_CHARGE = 15,
	-- The charge's line is traced this finely, and a floor this much lower than the last ends it (a ledge).
	TRACE_STEP = 1,
	LEDGE_DROP = 1,
	-- Where the body's flanks are traced from as well as its feet and snout, as shares of (BodyFront, BodyHalfWidth):
	-- a run or a skid stops before any of them meets a wall.
	FLANK_PROBES = table.freeze({
		table.freeze({ 0.45, 1 }),
		table.freeze({ 0.45, -1 }),
		table.freeze({ 0, 1 }),
		table.freeze({ 0, -1 }),
	}),
	-- A chained charge turns round only with room for its head (this share of BodyFront) and its tail (this share
	-- behind) all the way round, checked this many times along the turn.
	TURN_HEAD = 0.9,
	TURN_TAIL = 0.7,
	TURN_PROBES = 6,
	-- A charge's run is this many times as fast as authored: its tempo to this power, so it opens slower and ends
	-- faster without its clip's feet sliding far.
	RUN_TEMPO_POWER = 0.5,
	-- How far a lead can carry a spine or a dive past where its target stands (a charge's is held by
	-- CHARGE_LEAD_ARC instead), and the speed under which a target is standing still (studs a second): its spines then
	-- land round it on every side.
	LEAD_MAX = 30,
	STILL_SPEED = 4,
	-- A volley's salvo: the leading spine where its target is running, the next on the side it would cut to, then
	-- one where it stands, the other side, and the rest scattered this far round the leading one. A salvo's spines
	-- leave a beat apart this short, a spray rather than a line.
	SPINE_FLICK = 10,
	SPINE_SCATTER = table.freeze({ 6, 13 }),
	SPINE_STAGGER = 0.08,
	-- The run hits what its front meets: this far ahead of Root, the line's width across, this high above its floor.
	-- Its warning is drawn that long and wide (showLine): the warning is the hitbox.
	RAM_REACH = 15,
	RAM_HEIGHT = 10,
	-- Who it runs over is thrown along the run, up, and out to the side they stood on (studs a second).
	KNOCK_ALONG = 55,
	KNOCK_UP = 38,
	KNOCK_SIDE = 22,
	-- A dive runs under the floor for at least this long, and lands on its target's floor or this close to it.
	MIN_UNDER = 0.6,
	-- Under the floor it steers after its target, turning at most DIVE_TURN degrees a second: a target who keeps
	-- running is followed, one who cuts hard at the last moment makes it overshoot and come round. It leaves the hole
	-- at DIVE_LAUNCH of its speed, up to full over DIVE_RAMP seconds, and lunges at DIVE_LUNGE times it over the last
	-- DIVE_LUNGE_STUDS. It comes up once its head is DIVE_CATCH from them, or wherever it is after MAX_UNDER.
	DIVE_TURN = 130,
	DIVE_LAUNCH = 0.45,
	DIVE_RAMP = 0.5,
	DIVE_LUNGE = 1.35,
	DIVE_LUNGE_STUDS = 22,
	DIVE_CATCH = 4,
	MAX_UNDER = 6,
	-- Caught up, it darts on under the floor to where it comes up (TEnemyAttack.Lead ahead of its target) in this
	-- long: the crack shoots out ahead of them as their circle shows.
	DIVE_DART_SECONDS = 0.2,
	-- Its crack is told to clients a leg at a time, this often: it is not known ahead.
	CRACK_LEG_SECONDS = 0.1,
	-- Guards rise this far from the boss, and closer when there is no floor out there.
	GUARD_RADIUS = 28,
	GUARD_RADIUS_NEAR = 16,
	GUARD_FLOOR_REACH = 10,
	-- A body under the floor is out of reach for as long as this; let go as it bursts up.
	UNDER_IMMUNITY = 1e9,
	RISE_IMMUNITY = 0.05,
	-- A kind of control from players' abilities takes on a boss once, then it shrugs that kind off for this long, whoever
	-- casts it: a party takes turns with its gadgets rather than chaining one.
	WISE_SECONDS = 15,
	-- Slowed, it walks at this share of its speed and each move it starts takes 1 / this as long.
	SLOW_PACE = 0.6,
	-- A pounce's flight: its distance at the attack's Speed, held between these (seconds), on BossesCore.LeapPoint's
	-- arc. A chained one goes this long after it lands, at a target at least CHAIN_POUNCE_MIN away.
	POUNCE_FLIGHT = table.freeze({ 0.55, 1.4 }),
	CHAIN_POUNCE_AFTER = 0.9,
	CHAIN_POUNCE_MIN = 14,
	-- A front strike aims its shapes onto its target by turning up to these offsets off the straight line (radians),
	-- tried in order: a chevron's blades lie either side of its nose.
	STRIKE_AIMS = table.freeze({ 0, 0.3, -0.3, 0.55, -0.55 }),
	-- A brood: its sacs are laid this long after it starts (up its line by then).
	BROOD_LAY = 1.4,
	-- Its young hatch this far round where their sac stood.
	HATCH_SPREAD = 2.5,
})

-- What players can do to a boss (canControl): slow it (foam), or bait its next move (a decoy).
type TControl = "Slow" | "Lure"

-- A decoy it goes for: the lure's id (EnemyMovementService.SetLure) and where it stands.
type TBait = { Id: number, Feet: vector }

type TRun = {
	Index: number,
	Attack: TData.TEnemyAttack,
	-- Studs a second, set by its tempo when it began (runSpeed), and that wind-up tempo.
	Speed: number,
	Tempo: number,
	-- Turning onto its first line, which it winds up for once round (beginCharge).
	IsOpening: boolean,
	Phase: "Run" | "Skid" | "Turn",
	PhaseAt: number,
	From: vector,
	Direction: vector,
	Length: number,
	Traveled: number,
	-- The skid's own line: where it starts and how far it can slide before a wall.
	SkidFrom: vector,
	SkidRoom: number,
	TurnFrom: number,
	TurnTo: number,
	ChainsLeft: number,
	Hit: { [any]: boolean },
	HitDefenses: { [number]: boolean },
}

-- A dive's tunnel under the floor (stepBurrow): its head and heading (a yaw), whom it is after and where they stood
-- last, and the leg of its crack not yet sent.
type TBurrow = {
	Index: number,
	Attack: TData.TEnemyAttack,
	-- Its circle's seconds once it comes up.
	Warning: number,
	StartedAt: number,
	Head: vector,
	Heading: number,
	Target: any,
	TargetFeet: vector,
	LegFrom: vector,
	LegAt: number,
}

-- A pounce in the air (stepLeap): from where it left to where it lands, over Flight seconds from LeftAt.
type TLeap = {
	Index: number,
	Attack: TData.TEnemyAttack,
	From: vector,
	To: vector,
	LeftAt: number,
	Flight: number,
	Tempo: number,
	ChainsLeft: number,
}

-- A brood under way: up its line until EndsAt (or every sac popped), then down.
type TBrood = {
	Index: number,
	Attack: TData.TEnemyAttack,
	EndsAt: number,
	IsLaid: boolean,
}

type TStep = { At: number, Run: () -> () }

type TBoss = {
	Entity: any,
	InstanceId: number,
	Data: TData.TEnemy,
	Kit: TData.TEnemyBoss,
	Steps: { TStep },
	IsBusy: boolean,
	BusyUntil: number,
	ReadyAt: { [number]: number },
	ReachedAt: number,
	StrandedSince: number?,
	MovedFrom: vector,
	MovedAt: number,
	-- How many of its Summon's health lines it has roared at (summonsDue).
	Summoned: number,
	-- The enemy clock each attack was last made at, and the last one made: what the draw weighs (weightOf).
	UsedAt: { [number]: number },
	LastIndex: number,
	Guards: { [any]: number },
	GuardTotal: number,
	ShieldEndsAt: number,
	Run: TRun?,
	Burrow: TBurrow?,
	Leap: TLeap?,
	Brood: TBrood?,
	NextThinkAt: number,
	-- The console's next move for it (ForceNext): an attack's clip name or kind, any range or cooldown.
	Forced: string?,
	-- Its own walk speed, and the enemy clock its slow ends at (0: not slowed).
	WalkSpeed: number,
	SlowUntil: number,
	-- The enemy clock each kind of control takes on it again from (canControl).
	WiseUntil: { [TControl]: number },
	-- The decoy it is going for, and the one its charge is running down.
	Bait: TBait?,
	Crushing: TBait?,
}

local BossService = {}

local bosses: { [any]: TBoss } = {}
-- What a boss attack lands besides itself, built once per attack: a Quake's last ring, a Summon's roar.
local finishers: { [TData.TEnemyAttack]: TData.TEnemyAttack } = {}
local reusableDefenses: { number } = {}
local reusableFootprint: { [number]: boolean } = {}
-- Each standing character's flat run, smoothed (trackVelocities).
local smoothedVelocities: { [any]: vector } = {}

-- ============================== Helpers ==============================

local function fireMove(
	boss: TBoss,
	move: number,
	index: number,
	from: vector,
	to: vector,
	value: number,
	tempo: number?
)
	ServerNetworkBosses.Move.FireAll(boss.InstanceId, move, index, from :: any, to :: any, value, tempo or 1)
end

local function schedule(boss: TBoss, time: number, run: () -> ())
	table.insert(boss.Steps, { At = time, Run = run })
	table.sort(boss.Steps, function(a, b)
		return a.At < b.At
	end)
end

-- Held where it stands until `untilTime` (math.huge until a move lets it go itself), on attack `index` so the
-- movement update holds it rather than walking it.
local function setBusy(boss: TBoss, index: number, untilTime: number)
	boss.IsBusy = true
	boss.BusyUntil = untilTime
	EnemyWorld:set(boss.Entity, Components.AttackIndex, index)
	EnemyWorld:set(boss.Entity, Components.AttackWindup, 1)
end

local function setFree(boss: TBoss)
	boss.IsBusy = false
	EnemyWorld:set(boss.Entity, Components.AttackWindup, 0)
end

local function markUsed(boss: TBoss, index: number, now: number)
	boss.UsedAt[index] = now
	boss.LastIndex = index
end

-- `tempo` made 1 / SLOW_PACE as long while it is slowed.
local function paced(boss: TBoss, tempo: number): number
	return if TimeCore.EnemyClock < boss.SlowUntil then tempo / Tune.SLOW_PACE else tempo
end

-- Its rests' and cooldowns' tempo now (BossesCore.Tempo).
local function tempoOf(boss: TBoss, share: number): number
	return paced(boss, BossesCore.Tempo(boss.Kit, share))
end

-- Its wind-ups' and clips' tempo now (BossesCore.WindupTempo).
local function windupTempoOf(boss: TBoss, share: number): number
	return paced(boss, BossesCore.WindupTempo(boss.Kit, share))
end

-- A charge's run at `tempo`: slower than authored at a slow pace, faster at a fast one.
local function runSpeed(attack: TData.TEnemyAttack, tempo: number): number
	return (attack.Speed or 50) / tempo ^ Tune.RUN_TEMPO_POWER
end

local function flatDirection(from: vector, to: vector): vector?
	local flat = vector.create(to.x - from.x, 0, to.z - from.z)
	local length = vector.magnitude(flat)
	if length < 1e-3 then return nil end
	return flat / length
end

local function yawOf(direction: vector): number
	return math.atan2(direction.x, direction.z)
end

-- The nearest standing character: (feet, character entity, its id, flat distance), a level apart counting farther.
local function nearestTarget(from: vector): (vector?, any, number, number)
	local bestFeet: vector? = nil
	local bestEntity, bestId, bestScore, bestDistance = nil, 0, math.huge, math.huge
	for characterEntity, rootPart, humanoid, characterId in CharactersQuery do
		local feet = getCharacterFeet(rootPart, humanoid, 0)
		local dx, dz = feet.x - from.x, feet.z - from.z
		local distance = math.sqrt(dx * dx + dz * dz)
		local score = distance + if math.abs(feet.y - from.y) > Tune.LEVEL_GAP then Tune.LEVEL_PENALTY else 0
		if score >= bestScore then continue end
		bestScore = score
		bestFeet, bestEntity, bestId, bestDistance = feet, characterEntity, characterId, distance
	end

	return bestFeet, bestEntity, bestId, bestDistance
end

-- How far a body can run from `from` along `direction` (at most `limit`) before a wall, a ledge or the map's edge.
-- Over drops (`isOverDrops`: a snout or a flank, high off the floor) only a wall ends it.
local function traceLine(from: vector, direction: vector, limit: number, isOverDrops: boolean?): (number, number)
	local nav = ArenaCore.Nav
	if not nav then return limit, from.y end
	local y = from.y
	local length = 0
	while length + Tune.TRACE_STEP <= limit do
		local point = from + direction * (length + Tune.TRACE_STEP)
		local cx = math.floor((point.x - nav.OriginX) / nav.CellSize + 0.5)
		local cz = math.floor((point.z - nav.OriginZ) / nav.CellSize + 0.5)
		local node = ArenaCore.StepTarget(nav, cx, cz, y)
		if node == NO_NODE or NavService.Blocked and buffer.readu8(NavService.Blocked, node) ~= 0 then break end
		local height = ArenaCore.NodeHeight(nav, node)
		if height < y - Tune.LEDGE_DROP and not isOverDrops then break end
		y = height
		length += Tune.TRACE_STEP
	end

	return length, y
end

-- Whether the line from `from` to `from + offset` is clear of walls: a point of the body standing at `from` is not
-- already in one. Its floor's height there when it is.
local function reaches(from: vector, offset: vector): (boolean, number)
	local length = vector.magnitude(offset)
	if length < 1e-3 then return true, from.y end
	local reached, y = traceLine(from, offset / length, length, true)
	return reached + Tune.TRACE_STEP > length, y
end

-- How far the whole body standing at `from` can run along `direction` (at most `limit`): its feet's line, which a
-- ledge ends too, and its snout's and flanks', which a wall ends. A flank already against a wall is left to the rest.
local function traceBody(kit: TData.TEnemyBoss, from: vector, direction: vector, limit: number): number
	-- The snout in a wall already: nowhere to go this way.
	local snout = direction * kit.BodyFront
	local isSnoutClear, snoutY = reaches(from, snout)
	if not isSnoutClear then return 0 end
	local length = math.min(
		traceLine(from, direction, limit),
		(traceLine(vector.create(from.x + snout.x, snoutY, from.z + snout.z), direction, limit, true))
	)

	local side = vector.create(direction.z, 0, -direction.x)
	for _, probe in Tune.FLANK_PROBES do
		if length <= 0 then break end
		local offset = direction * (kit.BodyFront * probe[1]) + side * (kit.BodyHalfWidth * probe[2])
		local isClear, y = reaches(from, offset)
		if not isClear then continue end
		length = math.min(
			length,
			(traceLine(vector.create(from.x + offset.x, y, from.z + offset.z), direction, length, true))
		)
	end

	return length
end

-- Whether a body at `from` can turn round from `fromYaw` to `toYaw` (the way BossesCore.TurnDelta goes) without its
-- head or tail meeting a wall on the way.
local function hasRoomToTurn(kit: TData.TEnemyBoss, from: vector, fromYaw: number, toYaw: number): boolean
	local delta = BossesCore.TurnDelta(fromYaw, toYaw)
	for i = 1, Tune.TURN_PROBES do
		local yaw = fromYaw + delta * i / Tune.TURN_PROBES
		local forward = vector.create(math.sin(yaw), 0, math.cos(yaw))
		if not reaches(from, forward * (kit.BodyFront * Tune.TURN_HEAD)) then return false end
		if not reaches(from, forward * (-kit.BodyFront * Tune.TURN_TAIL)) then return false end
	end

	return true
end

-- Whether a line along `direction` lies beyond the front arc of a body facing `yaw`: a charge down it turns round onto
-- it first (beginCharge).
local function isOffFront(kit: TData.TEnemyBoss, yaw: number, direction: vector): boolean
	local diff = yawOf(direction) - yaw
	return math.abs(math.atan2(math.sin(diff), math.cos(diff))) > math.rad(kit.FrontArc)
end

-- Whether a charge along `direction` can be made from `from` facing `yaw`: ahead, or with room to turn onto it.
local function canFaceLine(kit: TData.TEnemyBoss, from: vector, yaw: number, direction: vector): boolean
	return not isOffFront(kit, yaw, direction) or hasRoomToTurn(kit, from, yaw, yawOf(direction))
end

-- A character's run, flat and smoothed (studs a second): zero for nobody, or before it has been seen.
local function flatVelocity(characterEntity: any): vector
	return smoothedVelocities[characterEntity] or vector.zero
end

-- `direction` turned back toward `base` until it is at most `maxAngle` radians off it (both flat and of length 1).
local function clampTurn(base: vector, direction: vector, maxAngle: number): vector
	local baseYaw = yawOf(base)
	local diff = yawOf(direction) - baseYaw
	local yaw = baseYaw + math.clamp(math.atan2(math.sin(diff), math.cos(diff)), -maxAngle, maxAngle)
	return vector.create(math.sin(yaw), 0, math.cos(yaw))
end

-- Where a target at `feet` running at `velocity` would be `seconds` on, `share` of the way: at most `maxLead` off
-- (LEAD_MAX when nil).
local function leadPoint(feet: vector, velocity: vector, seconds: number, share: number, maxLead: number?): vector
	local offset = velocity * (seconds * share)
	local length = vector.magnitude(offset)
	local limit = maxLead or Tune.LEAD_MAX
	if length > limit then
		offset *= limit / length
	end

	return feet + offset
end

-- The floor a body moving on it stands on at (x, z), stepping from `y`; `y` itself where there is no grid.
local function floorAt(x: number, z: number, y: number): number
	local nav = ArenaCore.Nav
	if not nav then return y end
	local node = ArenaCore.NodeAt(nav, x, y, z, ArenaCore.MAX_STEP)
	return if node ~= NO_NODE then ArenaCore.NodeHeight(nav, node) else y
end

local function place(boss: TBoss, position: vector, yaw: number?)
	EnemyWorld:set(boss.Entity, Components.Position, position)
	if yaw then EnemyWorld:set(boss.Entity, Components.Yaw, yaw) end
	if not EnemyWorld:has(boss.Entity, Tags.Submerged) then EnemiesSpatialHash:Update(boss.Entity, position) end
end

-- ============================== Attacks ==============================

local function finisherOf(attack: TData.TEnemyAttack): TData.TEnemyAttack
	local cached = finishers[attack]
	if cached then return cached end
	local ring: TData.TEnemyAttack = table.freeze({
		Kind = "Shockwave",
		Radius = if attack.Kind == "Summon" then attack.Radius else attack.FinisherRadius,
		Speed = if attack.Kind == "Summon" then attack.Speed else attack.FinisherSpeed,
		Range = 0,
		Delay = 0,
		Cooldown = 0,
		DamageScale = attack.DamageScale,
	})
	finishers[attack] = ring
	return ring
end

-- A spot in a body's frame (+X its left, +Z ahead) in the world, for the body at `position` facing `yaw`.
local function strikePoint(position: vector, yaw: number, spot: Vector3): vector
	local c, s = math.cos(yaw), math.sin(yaw)
	local x, z = spot.X, spot.Z
	return vector.create(position.x + x * c + z * s, position.y, position.z - x * s + z * c)
end

-- A strike's warning for the body at `position` facing `yaw`: (centre, yaw, length). A circle's yaw is 0 and its
-- length nil (the attack's Radius).
local function strikeShape(position: vector, yaw: number, strike: TData.TEnemyStrike): (vector, number, number?)
	local from = strikePoint(position, yaw, strike.From)
	local spot = strike.To
	if not spot then return from, 0, nil end
	local to = strikePoint(position, yaw, spot)
	local flat = vector.create(to.x - from.x, 0, to.z - from.z)
	local length = vector.magnitude(flat)
	if length < 1e-3 then return from, yaw, 1 end
	return from, math.atan2(flat.x, flat.z), length
end

-- A Slam round, in front of or behind the body: once, or once a beat with its last ring, or as its Strikes. Every
-- time is `tempo` times as long as authored.
local function startSlam(
	boss: TBoss,
	attack: TData.TEnemyAttack,
	now: number,
	position: vector,
	yaw: number,
	tempo: number
)
	local shapeYaw = if attack.Facing == "Behind" then yaw + math.pi else yaw
	local strikes = attack.Strikes
	if strikes then
		-- Each strike shown Delay before it lands: a sequence reads one shape at a time.
		for _, strike in strikes do
			local landsAt = strike.At * tempo
			local shownAt = math.max(landsAt - attack.Delay * tempo, 0)
			schedule(boss, now + shownAt, function()
				if not EnemyWorld:contains(boss.Entity) then return end
				local center, strikeYaw, length = strikeShape(position, yaw, strike)
				EnemyAttacksService.Telegraph(boss.Entity, attack, center, strikeYaw, landsAt - shownAt, length)
			end)
		end
		return
	end

	local beats = attack.Beats
	if not beats then
		EnemyAttacksService.Telegraph(boss.Entity, attack, position, shapeYaw, attack.Delay * tempo)
		return
	end

	-- Each beat's circle shows from the blow before it, so the next one is always on the ground as one lands.
	for i, beat in beats do
		local shownAt = (if i == 1 then 0 else beats[i - 1]) * tempo
		local landsAt = beat * tempo
		local isLast = i == #beats
		schedule(boss, now + shownAt, function()
			if not EnemyWorld:contains(boss.Entity) then return end
			local here = EnemyWorld:get(boss.Entity, Components.Position) or position
			EnemyAttacksService.Telegraph(boss.Entity, attack, here, shapeYaw, landsAt - shownAt)
			if isLast and attack.FinisherRadius then
				EnemyAttacksService.Telegraph(boss.Entity, finisherOf(attack), here, 0, landsAt - shownAt)
			end
		end)
	end
end

-- How many of `total` spines each of `count` beats throws: as even as it goes, the odd ones on random beats.
local function splitOverBeats(total: number, count: number): { number }
	local split = table.create(count, total // count)
	local beats = table.create(count)
	for i = 1, count do
		beats[i] = i
	end
	for i = 1, total % count do
		local pick = math.random(i, count)
		beats[i], beats[pick] = beats[pick], beats[i]
		split[beats[i]] += 1
	end

	return split
end

-- Where a salvo's `count` spines land on a target at `feet` running at `velocity`, its circles showing for `warning`:
-- the first where they are running to, the second on the side they would cut to on seeing it, then where they stand
-- (stopping is no answer), the other side, and the rest round the first. Standing still: round them on three sides.
local function salvoSpots(attack: TData.TEnemyAttack, feet: vector, velocity: vector, warning: number, count: number)
	local speed = vector.magnitude(velocity)
	local ahead = leadPoint(feet, velocity, warning, attack.Lead or 0)
	local isRunning = speed > Tune.STILL_SPEED
	local angle = math.random() * 2 * math.pi
	local across = if isRunning
		then vector.create(velocity.z / speed, 0, -velocity.x / speed)
		else vector.create(math.cos(angle), 0, math.sin(angle))
	if math.random() < 0.5 then across = -across end
	local flick = across * Tune.SPINE_FLICK
	local pattern = {
		ahead,
		ahead + flick,
		if isRunning then feet else ahead - flick,
		if isRunning then ahead - flick else ahead + vector.create(flick.z, 0, -flick.x),
	}
	local scatterFrom, scatterTo = Tune.SPINE_SCATTER[1], Tune.SPINE_SCATTER[2]

	local spots = table.create(count)
	for i = 1, count do
		local spot = pattern[i]
		if not spot then
			local turn = math.random() * 2 * math.pi
			local reach = scatterFrom + math.random() * (scatterTo - scatterFrom)
			spot = ahead + vector.create(math.cos(turn), 0, math.sin(turn)) * reach
		end
		spots[i] = spot
	end

	return spots
end

-- Spines rained on every standing player in Range: SpineCount each, a salvo a beat, each spine its own circle, aimed
-- where its player is going (TEnemyAttack.Lead) when it is thrown.
local function startVolley(
	boss: TBoss,
	index: number,
	attack: TData.TEnemyAttack,
	now: number,
	position: vector,
	tempo: number
)
	local flight = attack.Flight or 0.8
	local range = attack.Range
	local warning = attack.Delay * tempo
	local beats = attack.Beats or { attack.Delay }
	local counts = attack.SpineCount
	local shares: { [any]: { number } } = {}
	for characterEntity in CharactersQuery do
		local total = if counts then math.random(counts[1], counts[2]) else #beats
		shares[characterEntity] = splitOverBeats(total, #beats)
	end

	for i, beat in beats do
		-- Thrown as the clip shakes them loose, landing as their circles resolve.
		local thrownAt = now + math.max(beat * tempo + flight - warning, 0)
		schedule(boss, thrownAt, function()
			if not EnemyWorld:contains(boss.Entity) then return end
			for characterEntity, rootPart, humanoid in CharactersQuery do
				local share = shares[characterEntity]
				if not share or share[i] <= 0 then continue end
				local feet = getCharacterFeet(rootPart, humanoid, 0)
				local dx, dz = feet.x - position.x, feet.z - position.z
				if dx * dx + dz * dz > range * range then continue end
				local spots = salvoSpots(attack, feet, flatVelocity(characterEntity), warning, share[i])
				-- The first is due now, so runSteps throws it in this same pass.
				for n, spot in spots do
					schedule(boss, TimeCore.EnemyClock + (n - 1) * Tune.SPINE_STAGGER, function()
						if not EnemyWorld:contains(boss.Entity) then return end
						local landing = vector.create(spot.x, floorAt(spot.x, spot.z, feet.y), spot.z)
						EnemyAttacksService.Telegraph(boss.Entity, attack, landing, 0, warning)
						fireMove(boss, EBossMoves.Spine, index, position, landing, warning)
					end)
				end
			end
		end)
	end
end

-- How far `feet` stands off the run's front as it swept `length` studs from `from` along `along`, flat; nil when
-- it is ahead of that or behind, or this far above or below its floor at `to`.
local function offTheRam(feet: vector, from: vector, to: vector, along: vector, length: number): vector?
	if math.abs(feet.y - to.y) > Tune.RAM_HEIGHT then return nil end
	local offset = vector.create(feet.x - from.x, 0, feet.z - from.z)
	local t = vector.dot(offset, along)
	if t < 0 or t > length then return nil end
	return offset - along * t
end

-- Everything in the run's front from `from` to `to`: once per run, thrown along it. A decoy it runs down pops.
local function ram(boss: TBoss, run: TRun, from: vector, to: vector)
	local direction = run.Direction
	local front = to + direction * Tune.RAM_REACH
	local segment = front - from
	local length = vector.magnitude(segment)
	if length < 1e-3 then return end
	local along = segment / length
	local side = (run.Attack.Width or 8) / 2
	local damage = (EnemyWorld:get(boss.Entity, Components.Damage) or 0) * run.Attack.DamageScale

	local crushing = boss.Crushing
	local offDoll = if crushing then offTheRam(crushing.Feet, from, to, along, length) else nil
	if crushing and offDoll and vector.magnitude(offDoll) <= side then
		boss.Crushing = nil
		EnemyMovementService.CrushLure(crushing.Id, boss.Entity)
	end

	for characterEntity, rootPart, humanoid in CharactersQuery do
		if run.Hit[characterEntity] then continue end
		local across = offTheRam(getCharacterFeet(rootPart, humanoid, 0), from, to, along, length)
		if not across or vector.magnitude(across) > side then continue end
		run.Hit[characterEntity] = true
		CharacterService.Damage(characterEntity, damage)

		local player = getPlayerFromCharacterEntity(characterEntity)
		if not player then continue end
		local away = if vector.magnitude(across) > 1e-3 then vector.normalize(across) else vector.zero
		local knock = direction * Tune.KNOCK_ALONG + away * Tune.KNOCK_SIDE + vector.create(0, Tune.KNOCK_UP, 0)
		ServerNetworkBosses.Knocked.Fire(player, knock :: any)
	end

	-- Barricades and turrets in its path are run down too.
	table.clear(reusableDefenses)
	for _, id in DefenseService.GetInRadius(to, Tune.RAM_REACH + side, reusableDefenses) do
		if run.HitDefenses[id] then continue end
		run.HitDefenses[id] = true
		DefenseService.Damage(id, damage)
	end
end

local function beginRun(boss: TBoss, run: TRun, now: number, from: vector)
	run.Phase = "Run"
	run.PhaseAt = now
	run.From = from
	run.Traveled = 0
	fireMove(boss, EBossMoves.ChargeRun, run.Index, from, from + run.Direction * run.Length, run.Speed)
end

-- Faced along its line: the wind-up's clip, then the run.
local function windUp(boss: TBoss, run: TRun, now: number, position: vector)
	local yaw = yawOf(run.Direction)
	EnemyWorld:set(boss.Entity, Components.Yaw, yaw)
	fireMove(boss, EBossMoves.Attack, run.Index, position, position, yaw, run.Tempo)
	schedule(boss, now + run.Attack.Delay * run.Tempo, function()
		if not EnemyWorld:contains(boss.Entity) then return end
		boss.Run = run
		beginRun(boss, run, TimeCore.EnemyClock, EnemyWorld:get(boss.Entity, Components.Position) or position)
	end)
end

-- A charge's line from where it stands, as far as its front reaches: the run, the skid's slide (stepRun rams through
-- it) and RAM_REACH ahead of Root. Shown for `lead` seconds plus the run and the skid, so it is on the ground until
-- the body has stopped.
local function showLine(boss: TBoss, run: TRun, from: vector, lead: number)
	local kit = boss.Kit
	local direction = run.Direction
	local endFlat = from + direction * run.Length
	local runEnd = vector.create(endFlat.x, floorAt(endFlat.x, endFlat.z, from.y), endFlat.z)
	local slide = BossesCore.SkidDistance(run.Speed, kit.SkidStop, kit.SkidStop)
	local reach = run.Length + traceBody(kit, runEnd, direction, slide) + Tune.RAM_REACH
	EnemyAttacksService.Telegraph(
		boss.Entity,
		run.Attack,
		from,
		yawOf(direction),
		lead + run.Length / run.Speed + kit.SkidStop,
		math.max(reach, 1)
	)
end

local function beginSkid(boss: TBoss, run: TRun, now: number, from: vector)
	run.Phase = "Skid"
	run.PhaseAt = now
	run.SkidFrom = from
	local slide = BossesCore.SkidDistance(run.Speed, boss.Kit.SkidStop, boss.Kit.SkidStop)
	run.SkidRoom = traceBody(boss.Kit, from, run.Direction, slide)
	fireMove(boss, EBossMoves.Skid, run.Index, from, from + run.Direction * run.SkidRoom, run.Speed)
end

-- The way back a chained charge turns onto (round to its left) and how far it runs: straight at its target, when they
-- stand on its level within CHAIN_ARC of straight back and the run would reach them before a wall. nil otherwise: a
-- chain aimed off them, or into a wall, would only run at nobody.
local function chainLine(kit: TData.TEnemyBoss, run: TRun, from: vector): (number?, number)
	local feet = nearestTarget(from)
	local toTarget = if feet then flatDirection(from, feet) else nil
	if not feet or not toTarget or math.abs(feet.y - from.y) > ArenaCore.MAX_STEP + 1 then return nil, 0 end
	local back = yawOf(run.Direction) + math.pi
	local diff = yawOf(toTarget) - back
	diff = math.atan2(math.sin(diff), math.cos(diff))
	if math.abs(diff) > math.rad(Tune.CHAIN_ARC) then return nil, 0 end

	local length = traceBody(kit, from, toTarget, run.Attack.Radius or 70)
	local distance = vector.magnitude(vector.create(feet.x - from.x, 0, feet.z - from.z))
	if length < Tune.MIN_CHARGE or length + Tune.RAM_REACH < distance then return nil, 0 end
	return back + diff, length
end

-- Turns round onto `turnTo` and shows the next line, `length` long.
local function beginTurn(boss: TBoss, run: TRun, now: number, from: vector, turnTo: number, length: number)
	run.Phase = "Turn"
	run.PhaseAt = now
	run.ChainsLeft -= 1
	run.TurnFrom = yawOf(run.Direction)
	run.TurnTo = turnTo
	run.Direction = vector.create(math.sin(run.TurnTo), 0, math.cos(run.TurnTo))
	run.Length = length
	run.Hit = {}
	run.HitDefenses = {}
	showLine(boss, run, from, boss.Kit.TurnLength)
	fireMove(boss, EBossMoves.ChargeTurn, run.Index, from, from, run.TurnTo)
end

local function endRun(boss: TBoss, run: TRun, share: number)
	boss.Run = nil
	boss.Crushing = nil
	local untilTime = run.PhaseAt + boss.Kit.SkidLength
	boss.BusyUntil = untilTime
	-- Every charge it has waits: one in another health phase, open at once, would set off again straight away with
	-- its target behind it.
	local readyAt = untilTime + run.Attack.Cooldown * tempoOf(boss, share)
	for index, attack in boss.Data.Attacks do
		if attack.Kind == "Charge" then boss.ReadyAt[index] = math.max(boss.ReadyAt[index] or 0, readyAt) end
	end
end

local function stepRun(boss: TBoss, run: TRun, now: number, dt: number, position: vector, share: number)
	local speed = run.Speed
	if run.Phase == "Run" then
		local before = run.From + run.Direction * run.Traveled
		run.Traveled = math.min(run.Traveled + speed * dt, run.Length)
		local flat = run.From + run.Direction * run.Traveled
		local to = vector.create(flat.x, floorAt(flat.x, flat.z, position.y), flat.z)
		place(boss, to)
		ram(boss, run, before, to)
		if run.Traveled >= run.Length then beginSkid(boss, run, now, to) end
		return
	end

	local elapsed = now - run.PhaseAt
	if run.Phase == "Skid" then
		local kit = boss.Kit
		local slid = math.min(BossesCore.SkidDistance(speed, kit.SkidStop, elapsed), run.SkidRoom)
		local flat = run.SkidFrom + run.Direction * slid
		local to = vector.create(flat.x, floorAt(flat.x, flat.z, position.y), flat.z)
		local before = position
		place(boss, to)
		-- Still plowing while it slides.
		if elapsed < kit.SkidStop then ram(boss, run, before, to) end
		if elapsed < kit.SkidStop then return end
		-- Chained, unless its head or tail would meet a wall on the way round.
		if run.ChainsLeft > 0 then
			local turnTo, length = chainLine(kit, run, to)
			if turnTo and hasRoomToTurn(kit, to, yawOf(run.Direction), turnTo) then
				beginTurn(boss, run, now, to, turnTo, length)
				return
			end
		end
		endRun(boss, run, share)
		return
	end

	-- The turn: yawed at an even rate, the body braced on the spot, then straight off along the new line, or into the
	-- wind-up when it turned onto its first.
	local u = math.min(elapsed / boss.Kit.TurnLength, 1)
	place(boss, position, run.TurnFrom + (run.TurnTo - run.TurnFrom) * u)
	if u < 1 then return end
	if run.IsOpening then
		run.IsOpening = false
		boss.Run = nil
		windUp(boss, run, now, position)
		return
	end
	beginRun(boss, run, now, position)
end

-- A line beyond its front arc is turned onto first (its ChargeTurn, the line already on the ground), then wound up
-- for: a body this long never spins round under its wind-up.
local function beginCharge(
	boss: TBoss,
	index: number,
	attack: TData.TEnemyAttack,
	now: number,
	position: vector,
	direction: vector,
	length: number,
	tempo: number
)
	boss.ReachedAt = now
	markUsed(boss, index, now)

	local kit = boss.Kit
	local yaw = EnemyWorld:get(boss.Entity, Components.Yaw) or 0
	local chargeYaw = yawOf(direction)
	local isOpening = isOffFront(kit, yaw, direction)
	local run: TRun = {
		Index = index,
		Attack = attack,
		Speed = runSpeed(attack, tempo),
		Tempo = tempo,
		IsOpening = isOpening,
		Phase = if isOpening then "Turn" else "Run",
		PhaseAt = now,
		From = position,
		Direction = direction,
		Length = length,
		Traveled = 0,
		SkidFrom = position,
		SkidRoom = 0,
		TurnFrom = yaw,
		TurnTo = yaw + BossesCore.TurnDelta(yaw, chargeYaw),
		ChainsLeft = attack.Chains or 0,
		Hit = {},
		HitDefenses = {},
	}

	local windup = attack.Delay * tempo
	setBusy(boss, index, math.huge)
	showLine(boss, run, position, if isOpening then kit.TurnLength + windup else windup)
	if not isOpening then
		windUp(boss, run, now, position)
		return
	end

	boss.Run = run
	fireMove(boss, EBossMoves.ChargeTurn, index, position, position, chargeYaw)
end

-- Down through the floor where it stands, its circle shown for its Delay once it comes up, at any tempo: the sink and
-- the run under already give its target seconds to see it coming. Under the floor stepBurrow steers it after them.
local function startDive(boss: TBoss, index: number, attack: TData.TEnemyAttack, now: number, targetFeet: vector)
	setBusy(boss, index, math.huge)
	schedule(boss, now + boss.Kit.DiveUnder, function()
		local entity = boss.Entity
		if not EnemyWorld:contains(entity) then return end
		local from = EnemyWorld:get(entity, Components.Position) :: vector
		EnemyWorld:set(entity, Components.Immunity, Tune.UNDER_IMMUNITY)
		EnemyWorld:add(entity, Tags.Submerged)
		EnemiesSpatialHash:Remove(entity)

		-- Off the way it went down, curving onto whoever is nearest now.
		local feet, characterEntity = nearestTarget(from)
		local yaw = EnemyWorld:get(entity, Components.Yaw) or 0
		local clock = TimeCore.EnemyClock
		boss.Burrow = {
			Index = index,
			Attack = attack,
			Warning = attack.Delay,
			StartedAt = clock,
			Head = from,
			Heading = yaw,
			Target = characterEntity,
			TargetFeet = feet or targetFeet,
			LegFrom = from,
			LegAt = clock,
		}
	end)
end

-- Where a character a dive is after stands, while they are still a target (CharactersQuery's terms).
local function feetOf(characterEntity: any): vector?
	if not characterEntity or not World:contains(characterEntity) then return nil end
	if not World:has(characterEntity, Tags.Alive) or World:has(characterEntity, Tags.Picking) then return nil end
	local rootPart = World:get(characterEntity, Components.HumanoidRootPart)
	local humanoid = World:get(characterEntity, Components.Humanoid)
	if not rootPart or not humanoid then return nil end
	return getCharacterFeet(rootPart, humanoid, 0)
end

local function sendLeg(boss: TBoss, burrow: TBurrow, now: number)
	fireMove(boss, EBossMoves.Crack, burrow.Index, burrow.LegFrom, burrow.Head, now - burrow.LegAt)
	burrow.LegFrom = burrow.Head
	burrow.LegAt = now
end

-- Where a dive that caught its target comes up: Lead of the way to where they would be as its circle resolves if they
-- kept running, along their floor up to a wall or a ledge; under their feet when they stand still. A runner who never
-- looks down runs into it; one who stops or cuts away gets out.
local function diveAim(burrow: TBurrow): vector
	local feet = burrow.TargetFeet
	local aim = leadPoint(feet, flatVelocity(burrow.Target), burrow.Warning, burrow.Attack.Lead or 0)
	local direction = flatDirection(feet, aim)
	if not direction then return feet end
	local length, y = traceLine(feet, direction, vector.magnitude(aim - feet))
	return vector.create(feet.x + direction.x * length, y, feet.z + direction.z * length)
end

-- Its head stops: caught up, it darts on to its aim (diveAim) on its target's floor; given up, it stays where it is
-- (theirs off the grid). Its circle is shown there, and up through it as the circle resolves.
local function surface(boss: TBoss, burrow: TBurrow, now: number, isCaught: boolean)
	local entity = boss.Entity
	local kit = boss.Kit
	local index, attack, warning = burrow.Index, burrow.Attack, burrow.Warning
	local head, target = burrow.Head, burrow.TargetFeet
	boss.Burrow = nil

	local spot = if isCaught then diveAim(burrow) else head
	local fromY = if isCaught then spot.y + 0.75 else head.y
	local landing = vector.create(spot.x, fromY, spot.z)
	local nav = ArenaCore.Nav
	if nav then
		local node = ArenaCore.NodeAt(nav, spot.x, fromY, spot.z, ArenaCore.MAX_STEP)
		landing = if node ~= NO_NODE
			then vector.create(spot.x, ArenaCore.NodeHeight(nav, node), spot.z)
			else vector.create(target.x, floorAt(target.x, target.z, target.y + 0.75), target.z)
	end

	-- Caught: the crack's last leg to its head, then the dart on; given up, its last leg to where it comes up.
	if not isCaught then burrow.Head = landing end
	sendLeg(boss, burrow, now)
	if isCaught then fireMove(boss, EBossMoves.Dart, index, head, landing, Tune.DIVE_DART_SECONDS) end
	fireMove(boss, EBossMoves.Surface, index, landing, landing, warning)
	EnemyAttacksService.Telegraph(entity, attack, landing, 0, warning)

	local riseAt = now + warning - kit.DiveRiseImpact
	schedule(boss, riseAt, function()
		if not EnemyWorld:contains(entity) then return end
		local toward = nearestTarget(landing)
		local direction = if toward then flatDirection(landing, toward) else nil
		local yaw = if direction then yawOf(direction) else burrow.Heading
		EnemyWorld:remove(entity, Tags.Submerged)
		local halfExtents = EnemyWorld:get(entity, Components.HalfExtents) :: vector
		EnemiesSpatialHash:AddAABB(entity, landing, halfExtents)
		place(boss, landing, yaw)
		EnemyWorld:set(entity, Components.Velocity, vector.zero)
		fireMove(boss, EBossMoves.DiveRise, index, landing, landing, yaw)
		boss.BusyUntil = riseAt + kit.DiveRiseLength + kit.ReassembleLength
	end)

	schedule(boss, riseAt + kit.DiveRiseImpact, function()
		if EnemyWorld:contains(entity) then EnemyWorld:set(entity, Components.Immunity, Tune.RISE_IMMUNITY) end
	end)
end

-- A frame of the tunnel: turned toward its target as far as its turn allows, then on along its heading.
local function stepBurrow(boss: TBoss, burrow: TBurrow, now: number, dt: number)
	-- Whom it went down for while they stand, then whoever is nearest its head.
	local feet = feetOf(burrow.Target)
	if not feet then
		feet, burrow.Target = nearestTarget(burrow.Head)
	end
	if feet then burrow.TargetFeet = feet end

	local head, target = burrow.Head, burrow.TargetFeet
	local toTarget = vector.create(target.x - head.x, 0, target.z - head.z)
	local distance = vector.magnitude(toTarget)
	local under = now - burrow.StartedAt
	if distance <= Tune.DIVE_CATCH and under >= Tune.MIN_UNDER then
		surface(boss, burrow, now, true)
		return
	end
	if under >= Tune.MAX_UNDER then
		surface(boss, burrow, now, false)
		return
	end

	local heading = burrow.Heading
	if distance > 1e-3 then
		local wanted = yawOf(toTarget)
		local diff = math.atan2(math.sin(wanted - heading), math.cos(wanted - heading))
		local turn = math.rad(Tune.DIVE_TURN) * dt
		heading += math.clamp(diff, -turn, turn)
		burrow.Heading = heading
	end

	local launch = Tune.DIVE_LAUNCH + (1 - Tune.DIVE_LAUNCH) * math.min(under / Tune.DIVE_RAMP, 1)
	local lunge = if distance < Tune.DIVE_LUNGE_STUDS then Tune.DIVE_LUNGE else 1
	local speed = boss.Kit.DiveSpeed * launch * lunge
	local flat = head + vector.create(math.sin(heading), 0, math.cos(heading)) * (speed * dt)
	burrow.Head = vector.create(flat.x, floorAt(flat.x, flat.z, head.y), flat.z)
	if now - burrow.LegAt >= Tune.CRACK_LEG_SECONDS then sendLeg(boss, burrow, now) end
end

local function guardSpot(center: vector, yaw: number, i: number, count: number): vector?
	for _, radius in { Tune.GUARD_RADIUS, Tune.GUARD_RADIUS_NEAR } do
		local angle = yaw + (i - 0.5) / count * 2 * math.pi
		local x, z = center.x + math.sin(angle) * radius, center.z + math.cos(angle) * radius
		local y = ArenaCore.GetFloorY(x, z, center.y + Tune.GUARD_FLOOR_REACH)
		if y and math.abs(y - center.y) <= Tune.GUARD_FLOOR_REACH then return vector.create(x, y, z) end
	end

	return nil
end

local function sendShield(boss: TBoss)
	local ids = {}
	for _, instanceId in boss.Guards do
		ids[#ids + 1] = instanceId
	end

	ServerNetworkBosses.Shield.FireAll(boss.InstanceId, ids, boss.GuardTotal)
end

-- The shield comes down: what guards are left crumble with it.
local function dropShield(boss: TBoss)
	EnemyWorld:remove(boss.Entity, Tags.Shielded)
	local guards = boss.Guards
	boss.Guards = {}
	for guard in guards do
		if EnemyWorld:contains(guard) then EnemiesService.Kill(nil, guard, 0) end
	end

	sendShield(boss)
end

-- The roar: a ring to jump, then its guards rise round the arena and its shield goes up until they are dead.
-- How many of a Summon's health lines (TEnemyAttack.HealthLines) health share `share` is under; without lines, the one
-- its phase opens.
local function linesPassed(attack: TData.TEnemyAttack, share: number): number
	local lines = attack.HealthLines
	if not lines then return 1 end
	local count = 0
	for _, line in lines do
		if share < line then
			count += 1
		end
	end

	return count
end

local function startSummon(
	boss: TBoss,
	attack: TData.TEnemyAttack,
	now: number,
	position: vector,
	yaw: number,
	share: number
)
	-- A blow past two lines at once is one roar.
	boss.Summoned = math.max(boss.Summoned, linesPassed(attack, share))
	EnemyAttacksService.Telegraph(boss.Entity, finisherOf(attack), position, 0, attack.Delay)
	schedule(boss, now + attack.Delay, function()
		local entity = boss.Entity
		if not EnemyWorld:contains(entity) then return end
		local summons = attack.Summons
		local guardData = if summons then ENEMIES[summons] else nil
		if not guardData then return end

		local health = EnemyWorld:get(entity, Components.MaxHealth) or boss.Data.BaseMaxHealth
		local damage = EnemyWorld:get(entity, Components.Damage) or boss.Data.BaseDamage
		local healthScale = health / boss.Data.BaseMaxHealth
		local damageScale = damage / boss.Data.BaseDamage
		local count = attack.Count or 4
		for i = 1, count do
			local spot = guardSpot(position, yaw, i, count) or position
			local instanceId, guard = EnemiesService.Spawn(guardData.Id, spot, healthScale, damageScale)
			if not instanceId or not guard then continue end
			boss.Guards[guard] = instanceId
			EnemiesService.ShowBodyToEveryone(instanceId)
		end

		boss.GuardTotal = count
		if next(boss.Guards) == nil then return end
		EnemyWorld:add(entity, Tags.Shielded)
		boss.ShieldEndsAt = TimeCore.EnemyClock + (attack.ShieldSeconds or 25)
		sendShield(boss)
	end)
end

-- ============================== Pounce ==============================

-- Where a pounce at a target at `feet` running at `velocity` lands `seconds` from now: Lead of the way to where they
-- will be, on floor enemies stand on (the nav grid's), else under their feet. nil: no floor there at all.
local function pounceSpot(attack: TData.TEnemyAttack, feet: vector, velocity: vector, seconds: number): vector?
	local nav = ArenaCore.Nav
	if not nav then return feet end
	local aim = leadPoint(feet, velocity, seconds, attack.Lead or 0)
	for _, spot in { aim, feet } do
		local node = ArenaCore.NodeAt(nav, spot.x, feet.y + 0.75, spot.z, ArenaCore.MAX_STEP)
		if node ~= NO_NODE then return vector.create(spot.x, ArenaCore.NodeHeight(nav, node), spot.z) end
	end

	return nil
end

-- A pounce's seconds in the air from `from` to `to`: its distance at the attack's Speed, within POUNCE_FLIGHT.
local function flightOf(attack: TData.TEnemyAttack, from: vector, to: vector): number
	local distance = vector.magnitude(vector.create(to.x - from.x, 0, to.z - from.z))
	return math.clamp(distance / (attack.Speed or 45), Tune.POUNCE_FLIGHT[1], Tune.POUNCE_FLIGHT[2])
end

local function healthShare(entity: any): number
	local health = EnemyWorld:get(entity, Components.CurrentHealth) or 1
	local maxHealth = EnemyWorld:get(entity, Components.MaxHealth) or 1
	return if maxHealth > 0 then health / maxHealth else 1
end

-- Crouched where it stands until its clip's PounceLeave, then off the floor onto its target (stepLeap); the circle
-- where it lands is on the ground from the start. `chains`: how many more it makes after this one. False when there
-- is no floor to land on near them.
local function beginPounce(
	boss: TBoss,
	index: number,
	attack: TData.TEnemyAttack,
	now: number,
	position: vector,
	feet: vector,
	characterEntity: any,
	share: number,
	chains: number
): boolean
	local kit = boss.Kit
	local tempo = windupTempoOf(boss, share)
	local leave = (kit.PounceLeave or 0.8) * tempo
	local land = pounceSpot(attack, feet, flatVelocity(characterEntity), leave + flightOf(attack, position, feet))
	if not land then return false end
	local flight = flightOf(attack, position, land)
	local toLand = flatDirection(position, land)
	local yaw = if toLand then yawOf(toLand) else EnemyWorld:get(boss.Entity, Components.Yaw) or 0

	EnemyWorld:set(boss.Entity, Components.Yaw, yaw)
	fireMove(boss, EBossMoves.Attack, index, position, position, yaw, tempo)
	boss.ReachedAt = now
	boss.StrandedSince = nil
	markUsed(boss, index, now)
	local landLength = (kit.PounceLandLength or 1.7) * tempo
	boss.ReadyAt[index] = now + leave + flight + landLength + attack.Cooldown * tempoOf(boss, share)
	setBusy(boss, index, math.huge)
	EnemyAttacksService.Telegraph(boss.Entity, attack, land, 0, leave + flight)

	schedule(boss, now + leave, function()
		local entity = boss.Entity
		if not EnemyWorld:contains(entity) then return end
		local from = EnemyWorld:get(entity, Components.Position) or position
		-- Out of the hash while it flies: nothing may hit the floor it left, or a body its packets are not showing.
		EnemyWorld:add(entity, Tags.Submerged)
		EnemiesSpatialHash:Remove(entity)
		boss.Leap = {
			Index = index,
			Attack = attack,
			From = from,
			To = land,
			LeftAt = TimeCore.EnemyClock,
			Flight = flight,
			Tempo = tempo,
			ChainsLeft = chains,
		}
		fireMove(boss, EBossMoves.Leap, index, from, land, flight)
	end)
	return true
end

-- A frame of the leap: along its arc, and down on its landing (the circle resolves there on its own timer). A chained
-- one goes again at the nearest target once it has found its feet.
local function stepLeap(boss: TBoss, leap: TLeap, now: number)
	local u = math.min((now - leap.LeftAt) / leap.Flight, 1)
	place(boss, BossesCore.LeapPoint(leap.From, leap.To, u))
	if u < 1 then return end

	boss.Leap = nil
	local entity = boss.Entity
	EnemyWorld:remove(entity, Tags.Submerged)
	EnemiesSpatialHash:AddAABB(entity, leap.To, EnemyWorld:get(entity, Components.HalfExtents) :: vector)
	place(boss, leap.To)
	EnemyWorld:set(entity, Components.Velocity, vector.zero)
	boss.BusyUntil = now + (boss.Kit.PounceLandLength or 1.7) * leap.Tempo
	if leap.ChainsLeft <= 0 then return end

	schedule(boss, now + Tune.CHAIN_POUNCE_AFTER * leap.Tempo, function()
		if not EnemyWorld:contains(entity) or boss.Leap or boss.Brood then return end
		local here = EnemyWorld:get(entity, Components.Position) or leap.To
		local feet, characterEntity, _, distance = nearestTarget(here)
		if not feet or distance < Tune.CHAIN_POUNCE_MIN then return end
		local share = healthShare(entity)
		beginPounce(
			boss,
			leap.Index,
			leap.Attack,
			TimeCore.EnemyClock,
			here,
			feet,
			characterEntity,
			share,
			leap.ChainsLeft - 1
		)
	end)
end

-- ============================== Brood ==============================

-- Up its line and out of reach (its clip hauls it up from BroodUp), its sacs laid round the arena once it hangs there.
-- stepBrood brings it down when they are all popped or its time is up.
local function startBrood(
	boss: TBoss,
	index: number,
	attack: TData.TEnemyAttack,
	now: number,
	position: vector,
	yaw: number,
	share: number
)
	boss.Summoned = math.max(boss.Summoned, linesPassed(attack, share))
	setBusy(boss, index, math.huge)
	boss.Brood = { Index = index, Attack = attack, EndsAt = math.huge, IsLaid = false }

	schedule(boss, now + (boss.Kit.BroodUp or 1.1), function()
		local entity = boss.Entity
		if not EnemyWorld:contains(entity) then return end
		EnemyWorld:set(entity, Components.Immunity, Tune.UNDER_IMMUNITY)
		EnemyWorld:add(entity, Tags.Submerged)
		EnemiesSpatialHash:Remove(entity)
	end)

	schedule(boss, now + Tune.BROOD_LAY, function()
		local entity = boss.Entity
		local brood = boss.Brood
		if not EnemyWorld:contains(entity) or not brood then return end
		brood.IsLaid = true
		brood.EndsAt = TimeCore.EnemyClock + (attack.ShieldSeconds or 16)
		local sacData = if attack.Summons then ENEMIES[attack.Summons] else nil
		if not sacData then return end

		local health = EnemyWorld:get(entity, Components.MaxHealth) or boss.Data.BaseMaxHealth
		local healthScale = health / boss.Data.BaseMaxHealth
		local count = attack.Count or 4
		for i = 1, count do
			local spot = guardSpot(position, yaw, i, count) or position
			local instanceId, sac = EnemiesService.Spawn(sacData.Id, spot, healthScale, 1)
			if not instanceId or not sac then continue end
			boss.Guards[sac] = instanceId
			EnemiesService.ShowBodyToEveryone(instanceId)
		end
		boss.GuardTotal = count
		sendShield(boss)
	end)
end

-- A sac still whole bursts: it goes, and its young come out round where it stood.
local function hatch(boss: TBoss, attack: TData.TEnemyAttack, sac: any)
	local at = EnemyWorld:get(sac, Components.Position)
	EnemiesService.Kill(nil, sac, 0)
	local young = if attack.HatchType then ENEMIES[attack.HatchType] else nil
	if not at or not young then return end

	fireMove(boss, EBossMoves.Hatch, 0, at, at, 0)
	local health = EnemyWorld:get(boss.Entity, Components.MaxHealth) or boss.Data.BaseMaxHealth
	local damage = EnemyWorld:get(boss.Entity, Components.Damage) or boss.Data.BaseDamage
	local healthScale = health / boss.Data.BaseMaxHealth
	local damageScale = damage / boss.Data.BaseDamage
	local count = attack.Hatch or 3
	for i = 1, count do
		local angle = i / count * 2 * math.pi
		local spot = at + vector.create(math.cos(angle), 0, math.sin(angle)) * Tune.HATCH_SPREAD
		EnemiesService.Spawn(young.Id, spot, healthScale, damageScale)
	end
end

-- Down off its line: what sacs are left hatch, the circle under it shows for the attack's Delay, and it lands on its
-- belly through it, dazed for a while (BossesCore.BROOD_DAZE past its clip).
local function endBrood(boss: TBoss, brood: TBrood, now: number)
	local entity = boss.Entity
	local attack = brood.Attack
	local kit = boss.Kit
	boss.Brood = nil
	local sacs = boss.Guards
	boss.Guards = {}
	for sac in sacs do
		if EnemyWorld:contains(sac) then hatch(boss, attack, sac) end
	end
	sendShield(boss)

	local position = EnemyWorld:get(entity, Components.Position) :: vector
	local warning = attack.Delay
	local landsAt = now + warning
	EnemyAttacksService.Telegraph(entity, attack, position, 0, warning)
	fireMove(boss, EBossMoves.Drop, brood.Index, position, position, warning)
	boss.BusyUntil = landsAt + ((kit.BroodDropLength or 2.8) - (kit.BroodLand or 0.66)) + BossesCore.BROOD_DAZE
	schedule(boss, landsAt, function()
		if not EnemyWorld:contains(entity) then return end
		EnemyWorld:remove(entity, Tags.Submerged)
		EnemiesSpatialHash:AddAABB(entity, position, EnemyWorld:get(entity, Components.HalfExtents) :: vector)
		EnemyWorld:set(entity, Components.Immunity, Tune.RISE_IMMUNITY)
	end)
end

-- Its sacs counted each frame once laid: the boss bar's marks follow them, and it comes down when they are all popped
-- or its time is up.
local function stepBrood(boss: TBoss, brood: TBrood, now: number)
	if not brood.IsLaid then return end
	local isChanged = false
	for sac in boss.Guards do
		if EnemyWorld:contains(sac) then continue end
		boss.Guards[sac] = nil
		isChanged = true
	end

	if next(boss.Guards) == nil or now >= brood.EndsAt then
		endBrood(boss, brood, now)
	elseif isChanged then
		sendShield(boss)
	end
end

-- ============================== Control ==============================

-- Not behind its shield nor under the floor: players' gadgets can reach it.
local function isExposed(boss: TBoss): boolean
	return not EnemyWorld:has(boss.Entity, Tags.Shielded) and not EnemyWorld:has(boss.Entity, Tags.Submerged)
end

-- Whether players' `kind` of control takes on it now: exposed, and not yet wise to that kind (WISE_SECONDS).
local function canControl(boss: TBoss, kind: TControl, now: number): boolean
	return now >= (boss.WiseUntil[kind] or 0) and isExposed(boss)
end

-- Walks it at `pace` times its own speed, its walk clip with it on every client.
local function setPace(boss: TBoss, pace: number)
	EnemyWorld:set(boss.Entity, Components.MovementSpeed, boss.WalkSpeed * pace)
	local position = EnemyWorld:get(boss.Entity, Components.Position) :: vector
	fireMove(boss, EBossMoves.Pace, 0, position, position, pace)
end

-- Slows boss `entity` for `seconds` (foam): it walks at SLOW_PACE, and each move it starts meanwhile takes 1 /
-- SLOW_PACE as long. A move already under way keeps its time: its warning is on the ground. False when it shrugs it
-- off (canControl).
function BossService.Slow(entity: any, seconds: number): boolean
	local boss = bosses[entity]
	local now = TimeCore.EnemyClock
	if not boss or not canControl(boss, "Slow", now) then return false end
	boss.WiseUntil.Slow = now + Tune.WISE_SECONDS
	boss.SlowUntil = now + seconds
	setPace(boss, Tune.SLOW_PACE)
	return true
end

local function stepSlow(boss: TBoss, now: number)
	if boss.SlowUntil == 0 or now < boss.SlowUntil then return end
	boss.SlowUntil = 0
	setPace(boss, 1)
end

local function dropBait(boss: TBoss)
	boss.Bait = nil
	EnemyWorld:remove(boss.Entity, Tags.Baited)
end

-- The decoy it goes for: the one it took while it still stands, else one standing in its reach when decoys take on it.
-- Taking one makes it wise to them, so it walks to a doll for that doll's life at most.
local function baitOf(boss: TBoss, now: number, position: vector): TBait?
	local bait = boss.Bait
	if bait and EnemyMovementService.HasLure(bait.Id) and isExposed(boss) then return bait end
	if bait then dropBait(boss) end
	if not canControl(boss, "Lure", now) then return nil end
	local id, feet = EnemyMovementService.LureReaching(position)
	if not id or not feet then return nil end

	boss.WiseUntil.Lure = now + Tune.WISE_SECONDS
	local taken: TBait = { Id = id, Feet = feet }
	boss.Bait = taken
	EnemyWorld:add(boss.Entity, Tags.Baited)
	return taken
end

-- ============================== Choosing ==============================

-- Makes every boss up take `name` (an attack's clip name or kind, any case) as its next move, out of range or
-- cooling down as it may be: the console's, to see and tune each move. Returns how many bosses took it.
function BossService.ForceNext(name: string): number
	local count = 0
	for _, boss in bosses do
		boss.Forced = string.lower(name)
		count += 1
	end

	return count
end

local function isInPhase(attack: TData.TEnemyAttack, share: number): boolean
	if attack.HealthBelow and share >= attack.HealthBelow then return false end
	if attack.HealthAbove and share < attack.HealthAbove then return false end
	return true
end

local function isOpen(boss: TBoss, index: number, attack: TData.TEnemyAttack, share: number, now: number): boolean
	if now < (boss.ReadyAt[index] or 0) then return false end
	return isInPhase(attack, share)
end

-- Whether its target is somewhere it cannot walk to, for StrandedSeconds or more: off its flowfield, or the boss
-- stuck short of them.
local function updateStranded(boss: TBoss, now: number, position: vector, targetId: number, distance: number): boolean
	local nav = ArenaCore.Nav
	local field = NavService.CharacterFields[targetId]
	local isOff = false
	if nav and field and field.IsReady then
		local node = ArenaCore.NodeAt(nav, position.x, position.y, position.z, ArenaCore.MAX_STEP)
		isOff = node == NO_NODE or buffer.readu32(field.Dist, node * 4) == NavService.INF
	end

	if now - boss.MovedAt >= Tune.STUCK_SECONDS then
		local isStuck = not boss.IsBusy
			and distance > 25
			and vector.magnitude(position - boss.MovedFrom) < Tune.STUCK_STUDS
		isOff = isOff or isStuck
		boss.MovedFrom = position
		boss.MovedAt = now
	end

	if not isOff then
		boss.StrandedSince = nil
		return false
	end
	boss.StrandedSince = boss.StrandedSince or now
	return now - (boss.StrandedSince :: number) >= boss.Kit.StrandedSeconds
end

-- Whether anyone stands at least `minRange` and at most `range` away.
local function isAnyoneBetween(position: vector, minRange: number, range: number): boolean
	for _, rootPart, humanoid in CharactersQuery do
		local feet = getCharacterFeet(rootPart, humanoid, 0)
		local dx, dz = feet.x - position.x, feet.z - position.z
		local sq = dx * dx + dz * dz
		if sq >= minRange * minRange and sq <= range * range then return true end
	end

	return false
end

local function start(boss: TBoss, index: number, now: number, position: vector, yaw: number, share: number)
	local attack = boss.Data.Attacks[index]
	local kind = attack.Kind
	local bossTempo = tempoOf(boss, share)
	-- The roar and the brood come once, at their lines, as authored.
	local tempo = if kind == "Summon" or kind == "Brood" then 1 else windupTempoOf(boss, share)
	local length = (attack.Length or attack.Delay) * tempo
	EnemyWorld:set(boss.Entity, Components.Yaw, yaw)
	fireMove(boss, EBossMoves.Attack, index, position, position, yaw, tempo)
	boss.ReadyAt[index] = now + length + attack.Cooldown * bossTempo
	markUsed(boss, index, now)
	if kind == "Brood" then
		startBrood(boss, index, attack, now, position, yaw, share)
		return
	end
	if kind == "Summon" then
		startSummon(boss, attack, now, position, yaw, share)
	elseif attack.IsVolley then
		startVolley(boss, index, attack, now, position, tempo)
	else
		startSlam(boss, attack, now, position, yaw, tempo)
	end
	setBusy(boss, index, now + length)
end

-- A charge at its target, aimed where they are running (TEnemyAttack.Lead) but never more than CHARGE_LEAD_ARC off
-- them: the way it goes, how far it can, and whether its front gets as far as them before a wall or a ledge stops it.
local function chargeLine(
	boss: TBoss,
	attack: TData.TEnemyAttack,
	position: vector,
	feet: vector,
	characterEntity: any,
	tempo: number
): (vector?, number, boolean)
	local toFeet = flatDirection(position, feet)
	if not toFeet then return nil, 0, false end
	local arrives = attack.Delay * tempo + vector.magnitude(feet - position) / runSpeed(attack, tempo)
	local aim = leadPoint(feet, flatVelocity(characterEntity), arrives, attack.Lead or 0, math.huge)
	local direction = clampTurn(toFeet, flatDirection(position, aim) or toFeet, math.rad(Tune.CHARGE_LEAD_ARC))
	local length = traceBody(boss.Kit, position, direction, attack.Radius or 70)
	local along = vector.dot(vector.create(feet.x - position.x, 0, feet.z - position.z), direction)
	return direction, length, length + Tune.RAM_REACH >= along
end

local function beginDive(
	boss: TBoss,
	index: number,
	attack: TData.TEnemyAttack,
	now: number,
	position: vector,
	yaw: number,
	feet: vector,
	share: number
)
	local tempo = tempoOf(boss, share)
	boss.StrandedSince = nil
	fireMove(boss, EBossMoves.Attack, index, position, position, yaw)
	boss.ReadyAt[index] = now + attack.Cooldown * tempo
	markUsed(boss, index, now)
	startDive(boss, index, attack, now, feet)
end

-- The yaw a close slam on a target at `feet` would be made at: a bite turns its head onto them while they are in its
-- front arc (nil when they are not), everything else is made the way it faces.
local function slamYaw(
	kit: TData.TEnemyBoss,
	attack: TData.TEnemyAttack,
	position: vector,
	yaw: number,
	feet: vector
): number?
	if attack.Facing ~= "Front" then return yaw end
	if BossesCore.Facing(kit, position, yaw, feet) ~= "Front" then return nil end
	local toTarget = flatDirection(position, feet)
	return if toTarget then yawOf(toTarget) else yaw
end

-- Whether feet at `feet` are in `attack`'s shape made from `position` turned to `yaw`, on the floor its warning
-- floods (EnemyAttacksService's own test, so no wall, ledge or deck between).
local function isInArea(
	attack: TData.TEnemyAttack,
	position: vector,
	yaw: number,
	feet: vector,
	sizeOverride: number?
): boolean
	local nav = ArenaCore.Nav
	local kind, shapeSize, width = TelegraphCore.ShapeOf(attack)
	local size = sizeOverride or shapeSize
	local shapeYaw = if kind == ETelegraphs.Cone or kind == ETelegraphs.Line then yaw else 0
	-- The shape alone first: the flood is the costly part, and only someone inside the shape needs it.
	local x, z = TelegraphCore.ToLocal(position, shapeYaw, feet)
	if TelegraphCore.Distance(kind, size, width, x, z) > 0 then return false end
	table.clear(reusableFootprint)
	local floorY = TelegraphCore.Footprint(nav, kind, position, shapeYaw, size, width, reusableFootprint)
	local footprint = if floorY then reusableFootprint else nil
	return TelegraphCore.IsInside(nav, footprint, kind, position, shapeYaw, size, width, feet)
end

-- Whether a close slam made at `yaw` (slamYaw) would catch feet at `feet` where they stand now: in its shape (turned
-- back for the tail) or in the ring its last beat rolls out. A move that would land on nothing is not made.
local function wouldHit(attack: TData.TEnemyAttack, position: vector, yaw: number, feet: vector): boolean
	local strikes = attack.Strikes
	if strikes then
		for _, strike in strikes do
			local center, strikeYaw, length = strikeShape(position, yaw, strike)
			if isInArea(attack, center, strikeYaw, feet, length) then return true end
		end
		return false
	end

	local shapeYaw = if attack.Facing == "Behind" then yaw + math.pi else yaw
	if isInArea(attack, position, shapeYaw, feet) then return true end
	return attack.FinisherRadius ~= nil and isInArea(finisherOf(attack), position, 0, feet)
end

-- The yaw a close slam on a target at `feet` would be made at to land on them (slamYaw), nil when none would: a front
-- strike's shapes lie off its nose (a chevron's blades), so it is turned a little off the straight line to lay one on
-- them (STRIKE_AIMS).
local function aimedYaw(
	kit: TData.TEnemyBoss,
	attack: TData.TEnemyAttack,
	position: vector,
	yaw: number,
	feet: vector
): number?
	local aimYaw = slamYaw(kit, attack, position, yaw, feet)
	if not aimYaw then return nil end
	if not attack.Strikes or attack.Facing ~= "Front" then
		return if wouldHit(attack, position, aimYaw, feet) then aimYaw else nil
	end

	for _, offset in Tune.STRIKE_AIMS do
		if wouldHit(attack, position, aimYaw + offset, feet) then return aimYaw + offset end
	end

	return nil
end

-- Its weight in a draw (Tune.FRESH_WEIGHT): more the longer since it was made, less if it was the last.
local function weightOf(boss: TBoss, index: number, now: number): number
	local since = now - (boss.UsedAt[index] or -math.huge)
	local weight = 1 + Tune.FRESH_WEIGHT * math.min(since / Tune.FRESH_SECONDS, 1)
	return if index == boss.LastIndex then weight * Tune.REPEAT_SHARE else weight
end

-- Runs one of `options`, drawn by `weights` (same order); nothing when there are none.
local function draw(options: { () -> () }, weights: { number })
	local total = 0
	for _, weight in weights do
		total += weight
	end
	if total <= 0 then return end

	local roll = math.random() * total
	for i, weight in weights do
		roll -= weight
		if roll > 0 then continue end
		options[i]()
		return
	end
end

-- Its next move at the decoy it took (baitOf): a close slam that would catch the doll, cooling down or not, else a
-- charge at it from far enough off; the blow pops the doll, whose blast the boss takes. Neither in reach, it walks on
-- to it (Tags.Baited).
local function goForBait(boss: TBoss, now: number, position: vector, yaw: number, share: number, bait: TBait)
	local feet = bait.Feet
	if math.abs(feet.y - position.y) > ArenaCore.MAX_STEP + 1 then return end
	local distance = vector.magnitude(vector.create(feet.x - position.x, 0, feet.z - position.z))
	local tempo = windupTempoOf(boss, share)
	local attacks = boss.Data.Attacks
	for index, attack in attacks do
		if attack.Kind ~= "Slam" or attack.IsVolley then continue end
		if distance > attack.Range or not isInPhase(attack, share) then continue end
		local aimYaw = aimedYaw(boss.Kit, attack, position, yaw, feet)
		if not aimYaw then continue end
		dropBait(boss)
		start(boss, index, now, position, aimYaw, share)
		local beats = attack.Beats
		schedule(boss, now + (if beats then beats[1] else attack.Delay) * tempo, function()
			if EnemyWorld:contains(boss.Entity) then EnemyMovementService.CrushLure(bait.Id, boss.Entity) end
		end)
		return
	end

	for index, attack in attacks do
		if attack.Kind ~= "Charge" or distance < (attack.MinRange or 0) or distance > attack.Range then continue end
		if not isInPhase(attack, share) then continue end
		local direction, length, isReaching = chargeLine(boss, attack, position, feet, nil, tempo)
		-- A wall short of the doll, or no room to turn onto it: it walks round instead.
		if not direction or length < Tune.MIN_CHARGE or not isReaching then continue end
		if not canFaceLine(boss.Kit, position, yaw, direction) then continue end
		dropBait(boss)
		boss.Crushing = bait
		beginCharge(boss, index, attack, now, position, direction :: vector, length, tempo)
		return
	end
end

-- The console's move (ForceNext), made at its target whatever its range, cooldown or phase.
local function forced(
	boss: TBoss,
	now: number,
	position: vector,
	yaw: number,
	share: number,
	feet: vector,
	characterEntity: any
)
	local name = boss.Forced :: string
	boss.Forced = nil
	for index, attack in boss.Data.Attacks do
		local clip = string.lower(attack.AnimationName or "")
		if clip ~= name and string.lower(attack.Kind) ~= name then continue end
		local toTarget = flatDirection(position, feet)
		local aimYaw = if toTarget then yawOf(toTarget) else yaw
		if attack.Kind == "Charge" then
			local tempo = windupTempoOf(boss, share)
			local direction, length = chargeLine(boss, attack, position, feet, characterEntity, tempo)
			direction = direction or vector.create(math.sin(yaw), 0, math.cos(yaw))
			beginCharge(boss, index, attack, now, position, direction :: vector, length, tempo)
		elseif attack.Kind == "Dive" then
			beginDive(boss, index, attack, now, position, yaw, feet, share)
		elseif attack.Kind == "Pounce" then
			beginPounce(boss, index, attack, now, position, feet, characterEntity, share, attack.Chains or 0)
		else
			start(boss, index, now, position, if attack.Facing == "Front" then aimYaw else yaw, share)
		end
		return
	end
end

-- The move for this moment, by where its target stands: the shield at each health line, a dive at someone it cannot
-- reach, a close slam that would catch them where they stand, then a charge at a runner or spines on the far ones.
-- Of the close ones, and of the far ones, any that would land is drawn by weight (weightOf); none, and it walks on.
local function think(boss: TBoss, now: number, position: vector, yaw: number, share: number)
	local feet, characterEntity, targetId, distance = nearestTarget(position)
	if not feet then return end
	if boss.Forced then
		forced(boss, now, position, yaw, share, feet, characterEntity)
		return
	end
	local attacks = boss.Data.Attacks
	local kit = boss.Kit
	if distance <= 20 then boss.ReachedAt = now end
	local isStranded = updateStranded(boss, now, position, targetId, distance)
	local isSameLevel = math.abs(feet.y - position.y) <= ArenaCore.MAX_STEP + 1

	-- Never over a shield already up: its guards are still to kill.
	for index, attack in attacks do
		local isGoalChanger = attack.Kind == "Summon" or attack.Kind == "Brood"
		if not isGoalChanger or next(boss.Guards) ~= nil then continue end
		if linesPassed(attack, share) <= boss.Summoned or not isOpen(boss, index, attack, share, now) then continue end
		start(boss, index, now, position, yaw, share)
		return
	end

	local bait = baitOf(boss, now, position)
	if bait then
		goForBait(boss, now, position, yaw, share, bait)
		return
	end

	-- Somewhere it cannot walk to: under the floor to them, or a leap onto their floor.
	if isStranded then
		for index, attack in attacks do
			if not isOpen(boss, index, attack, share, now) then continue end
			if attack.Kind == "Dive" then
				beginDive(boss, index, attack, now, position, yaw, feet, share)
				return
			end
			if attack.Kind ~= "Pounce" then continue end
			-- False with no floor to land on near them: it looks on.
			if beginPounce(boss, index, attack, now, position, feet, characterEntity, share, attack.Chains or 0) then
				return
			end
		end
	end

	-- Close: the bite turned onto its target in front, the tail behind, a stamp's circle on any side.
	local options: { () -> () } = {}
	local weights: { number } = {}
	if isSameLevel then
		for index, attack in attacks do
			if attack.Kind ~= "Slam" or attack.IsVolley or distance > attack.Range then continue end
			if not isOpen(boss, index, attack, share, now) then continue end
			local aimYaw = aimedYaw(kit, attack, position, yaw, feet)
			if not aimYaw then continue end
			table.insert(options, function()
				start(boss, index, now, position, aimYaw, share)
			end)
			table.insert(weights, weightOf(boss, index, now))
		end
	end
	if #options > 0 then
		draw(options, weights)
		return
	end

	-- At range: a charge down a clear line that reaches its target, a dive up under them, or spines on everybody far
	-- off.
	local isChasing = now - boss.ReachedAt >= kit.ChaseSeconds
	local tempo = windupTempoOf(boss, share)
	for index, attack in attacks do
		if not isOpen(boss, index, attack, share, now) then continue end
		local move: (() -> ())? = nil
		if attack.Kind == "Charge" and isSameLevel and distance <= attack.Range then
			if distance < (attack.MinRange or 0) and not isChasing then continue end
			local direction, length, isReaching = chargeLine(boss, attack, position, feet, characterEntity, tempo)
			if not direction or length < Tune.MIN_CHARGE or not isReaching then continue end
			if not canFaceLine(kit, position, yaw, direction) then continue end
			move = function()
				beginCharge(boss, index, attack, now, position, direction :: vector, length, tempo)
			end
		elseif attack.Kind == "Pounce" and distance <= attack.Range then
			if distance < (attack.MinRange or 0) and not isChasing then continue end
			if not pounceSpot(attack, feet, flatVelocity(characterEntity), 0) then continue end
			move = function()
				beginPounce(boss, index, attack, now, position, feet, characterEntity, share, attack.Chains or 0)
			end
		elseif attack.Kind == "Dive" and distance >= (attack.MinRange or math.huge) then
			move = function()
				beginDive(boss, index, attack, now, position, yaw, feet, share)
			end
		elseif attack.IsVolley and isAnyoneBetween(position, attack.MinRange or 0, attack.Range) then
			move = function()
				start(boss, index, now, position, yaw, share)
			end
		end
		if not move then continue end
		table.insert(options, move)
		table.insert(weights, weightOf(boss, index, now))
	end

	draw(options, weights)
end

-- ============================== Lifecycle ==============================

local function adopt(entity: any, data: TData.TEnemy, position: vector): TBoss?
	local kit = data.Boss
	if not kit then return nil end
	local now = TimeCore.EnemyClock
	local boss: TBoss = {
		Entity = entity,
		InstanceId = EnemyWorld:get(entity, Components.InstanceId) :: number,
		Data = data,
		Kit = kit,
		Steps = {},
		IsBusy = false,
		BusyUntil = 0,
		ReadyAt = {},
		ReachedAt = now,
		StrandedSince = nil,
		MovedFrom = position,
		MovedAt = now,
		Summoned = 0,
		UsedAt = {},
		LastIndex = 0,
		Guards = {},
		GuardTotal = 0,
		ShieldEndsAt = 0,
		Run = nil,
		Burrow = nil,
		Leap = nil,
		Brood = nil,
		-- Adopted on the first frame the match runs after its intro.
		NextThinkAt = now + kit.OpeningSeconds,
		Forced = nil,
		WalkSpeed = EnemyWorld:get(entity, Components.MovementSpeed) or data.BaseMovementSpeed,
		SlowUntil = 0,
		WiseUntil = {},
		Bait = nil,
		Crushing = nil,
	}
	bosses[entity] = boss
	return boss
end

local function updateShield(boss: TBoss, now: number)
	if next(boss.Guards) == nil then return end
	local isChanged = false
	for guard in boss.Guards do
		if EnemyWorld:contains(guard) then continue end
		boss.Guards[guard] = nil
		isChanged = true
	end

	if next(boss.Guards) == nil or now >= boss.ShieldEndsAt then
		dropShield(boss)
	elseif isChanged then
		sendShield(boss)
	end
end

local function runSteps(boss: TBoss, now: number)
	local steps = boss.Steps
	while steps[1] and steps[1].At <= now do
		local step = table.remove(steps, 1) :: TStep
		step.Run()
	end
end

-- Eases each standing character's smoothed run toward its velocity now, over `dt` real seconds
-- (Tune.VELOCITY_SMOOTHING), and forgets the ones gone.
local function trackVelocities(dt: number)
	local blend = 1 - math.exp(-dt / Tune.VELOCITY_SMOOTHING)
	for characterEntity, rootPart in CharactersQuery do
		local velocity = rootPart.AssemblyLinearVelocity
		local flat = vector.create(velocity.X, 0, velocity.Z)
		local last = smoothedVelocities[characterEntity]
		smoothedVelocities[characterEntity] = if last then last + (flat - last) * blend else flat
	end

	for characterEntity in smoothedVelocities do
		if not World:contains(characterEntity) then smoothedVelocities[characterEntity] = nil end
	end
end

-- Put down by a player: the whole match drops into slow motion for its fall.
EnemiesService.OnEnemyDied:Connect(function(_, enemyData: TData.TEnemy)
	if enemyData.IsBoss then TimeService.SlowMotion() end
end)

-- Gone (killed, cleared): its guards crumble and its shield's marks go with it.
EnemiesService.OnEnemyRemoving:Connect(function(entity)
	local boss = bosses[entity]
	if not boss then return end
	bosses[entity] = nil
	if next(boss.Guards) == nil then return end
	local guards = boss.Guards
	boss.Guards = {}
	-- Deferred: this runs inside the boss's own removal.
	task.defer(function()
		for guard in guards do
			if EnemyWorld:contains(guard) then EnemiesService.Kill(nil, guard, 0) end
		end
		ServerNetworkBosses.Shield.FireAll(boss.InstanceId, {}, boss.GuardTotal)
	end)
end)

RunService.Heartbeat:Connect(function(dt: number)
	if TimeCore.IsPaused then return end
	local enemyDt = TimeCore.GetEnemyDeltaTime(dt)
	if enemyDt <= 0 then return end
	local now = TimeCore.EnemyClock
	if next(bosses) == nil then
		table.clear(smoothedVelocities)
	else
		trackVelocities(dt)
	end

	for entity, position, yaw, health, maxHealth, data in BossQuery do
		local boss = bosses[entity] or adopt(entity, data, position)
		if not boss then continue end
		local share = if maxHealth > 0 then health / maxHealth else 1
		runSteps(boss, now)
		if not EnemyWorld:contains(entity) then continue end
		local brood = boss.Brood
		if brood then
			stepBrood(boss, brood, now)
		else
			updateShield(boss, now)
		end
		stepSlow(boss, now)

		local leap = boss.Leap
		if leap then
			stepLeap(boss, leap, now)
			continue
		end

		local run = boss.Run
		if run then
			stepRun(boss, run, now, enemyDt, EnemyWorld:get(entity, Components.Position) :: vector, share)
			continue
		end
		local burrow = boss.Burrow
		if burrow then
			stepBurrow(boss, burrow, now, enemyDt)
			continue
		end

		if boss.IsBusy and now >= boss.BusyUntil then setFree(boss) end
		local rest = Tune.REST * tempoOf(boss, share)
		if boss.IsBusy or now < boss.BusyUntil + rest or now < boss.NextThinkAt then continue end
		boss.NextThinkAt = now + Tune.THINK_SECONDS
		think(boss, now, position, yaw, share)
	end
end)

return Ignis.Register(BossService)
