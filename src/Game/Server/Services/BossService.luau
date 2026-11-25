-- A boss's fight (PlanBosses.md): which of its attacks it makes and when, and the ones that are more than a ground
-- warning: a charge's run and skid, a dive under the floor, the guards it raises and the shield they hold up. Also
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
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local ArenaCore = require(ReplicatedStorage.Shared.Core.ArenaCore)
local BossesCore = require(ReplicatedStorage.Shared.Core.BossesCore)
local EnemiesCore = require(ReplicatedStorage.Shared.Core.EnemiesCore)
local TimeCore = require(ReplicatedStorage.Shared.Core.TimeCore)
local Components = require(ReplicatedStorage.GlobalShared.ECS.Components)
local Tags = require(ReplicatedStorage.GlobalShared.ECS.Tags)
local EnemyWorld = require(ReplicatedStorage.GlobalShared.ECS.Worlds.EnemyWorld)
local World = require(ReplicatedStorage.GlobalShared.ECS.Worlds.World)
local getCharacterFeet = require(ReplicatedStorage.GlobalShared.Utils.Functions.getCharacterFeet)
local getPlayerFromCharacterEntity =
	require(ReplicatedStorage.GlobalShared.Utils.Functions.getPlayerFromCharacterEntity)
local EBossMoves = require(ReplicatedStorage.Types.Enums.EBossMoves)
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
	-- How far a lead can carry an aim past where its target stands, and the speed under which a target is standing
	-- still (studs a second): its spines then land round it on every side.
	LEAD_MAX = 30,
	STILL_SPEED = 4,
	-- A volley's salvo: the leading spine where its target is running, the next on the side it would cut to, then
	-- one where it stands, the other side, and the rest scattered this far round the leading one. A salvo's spines
	-- leave a beat apart this short, a spray rather than a line.
	SPINE_FLICK = 10,
	SPINE_SCATTER = table.freeze({ 6, 13 }),
	SPINE_STAGGER = 0.08,
	-- The run hits what its front meets: this far ahead of Root, this far either side past the line's half width, this
	-- high above its floor.
	RAM_REACH = 15,
	RAM_SIDE = 1.5,
	RAM_HEIGHT = 10,
	-- Who it runs over is thrown along the run, up, and out to the side they stood on (studs a second).
	KNOCK_ALONG = 55,
	KNOCK_UP = 38,
	KNOCK_SIDE = 22,
	-- A dive runs under the floor for at least this long, and lands on its target's floor or this close to it.
	MIN_UNDER = 0.6,
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
})

-- What players can do to a boss (canControl): slow it (foam), or bait its next move (a decoy).
type TControl = "Slow" | "Lure"

-- A decoy it goes for: the lure's id (EnemyMovementService.SetLure) and where it stands.
type TBait = { Id: number, Feet: vector }

type TRun = {
	Index: number,
	Attack: TData.TEnemyAttack,
	-- Studs a second, set by its tempo when it began (runSpeed).
	Speed: number,
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
	HasSummoned: boolean,
	Guards: { [any]: number },
	GuardTotal: number,
	ShieldEndsAt: number,
	Run: TRun?,
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

local function tempoOf(boss: TBoss, share: number): number
	local tempo = BossesCore.Tempo(boss.Kit, share)
	return if TimeCore.EnemyClock < boss.SlowUntil then tempo / Tune.SLOW_PACE else tempo
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

-- Whether a body at `from` can turn round from `fromYaw` to `toYaw` (to its left) without its head or tail meeting a
-- wall on the way.
local function hasRoomToTurn(kit: TData.TEnemyBoss, from: vector, fromYaw: number, toYaw: number): boolean
	local delta = (toYaw - fromYaw) % (2 * math.pi)
	for i = 1, Tune.TURN_PROBES do
		local yaw = fromYaw + delta * i / Tune.TURN_PROBES
		local forward = vector.create(math.sin(yaw), 0, math.cos(yaw))
		if not reaches(from, forward * (kit.BodyFront * Tune.TURN_HEAD)) then return false end
		if not reaches(from, forward * (-kit.BodyFront * Tune.TURN_TAIL)) then return false end
	end

	return true
end

-- A character's run, flat (studs a second).
local function flatVelocity(characterEntity: any): vector
	local rootPart = if characterEntity then World:get(characterEntity, Components.HumanoidRootPart) else nil
	if not rootPart then return vector.zero end
	local velocity = rootPart.AssemblyLinearVelocity
	return vector.create(velocity.X, 0, velocity.Z)
end

-- Where a target at `feet` running at `velocity` would be `seconds` on, `share` of the way: at most LEAD_MAX off.
local function leadPoint(feet: vector, velocity: vector, seconds: number, share: number): vector
	local offset = velocity * (seconds * share)
	local length = vector.magnitude(offset)
	if length > Tune.LEAD_MAX then
		offset *= Tune.LEAD_MAX / length
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

-- A Slam round, in front of or behind the body: once, or once a beat with its last ring. Every time is `tempo`
-- times as long as authored.
local function startSlam(
	boss: TBoss,
	attack: TData.TEnemyAttack,
	now: number,
	position: vector,
	yaw: number,
	tempo: number
)
	local shapeYaw = if attack.Facing == "Behind" then yaw + math.pi else yaw
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
	local side = (run.Attack.Width or 8) / 2 + Tune.RAM_SIDE
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

-- A charge's line from where it stands: shown for `lead` seconds plus the run, so it is on the ground until the body
-- has passed its end.
local function showLine(boss: TBoss, run: TRun, from: vector, lead: number)
	EnemyAttacksService.Telegraph(
		boss.Entity,
		run.Attack,
		from,
		yawOf(run.Direction),
		lead + run.Length / run.Speed,
		math.max(run.Length, 1)
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

-- The way back a chained charge turns onto: round to its left, aimed at its target within 45 degrees of it.
local function chainYaw(run: TRun, from: vector): number
	local back = yawOf(run.Direction) + math.pi
	local target = nearestTarget(from)
	local toTarget = if target then flatDirection(from, target) else nil
	if not toTarget then return back end
	local diff = yawOf(toTarget) - back
	return back + math.clamp(math.atan2(math.sin(diff), math.cos(diff)), -math.pi / 4, math.pi / 4)
end

-- Turns round onto `turnTo` and shows the next line.
local function beginTurn(boss: TBoss, run: TRun, now: number, from: vector, turnTo: number)
	run.Phase = "Turn"
	run.PhaseAt = now
	run.ChainsLeft -= 1
	run.TurnFrom = yawOf(run.Direction)
	run.TurnTo = turnTo
	run.Direction = vector.create(math.sin(run.TurnTo), 0, math.cos(run.TurnTo))
	run.Length = traceBody(boss.Kit, from, run.Direction, run.Attack.Radius or 70)
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
	boss.ReadyAt[run.Index] = untilTime + run.Attack.Cooldown * tempoOf(boss, share)
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
			local turnTo = chainYaw(run, to)
			if hasRoomToTurn(kit, to, yawOf(run.Direction), turnTo) then
				beginTurn(boss, run, now, to, turnTo)
				return
			end
		end
		endRun(boss, run, share)
		return
	end

	-- The turn: yawed at an even rate, the body braced on the spot, then straight off along the new line.
	local u = math.min(elapsed / boss.Kit.TurnLength, 1)
	place(boss, position, run.TurnFrom + (run.TurnTo - run.TurnFrom) * u)
	if u >= 1 then beginRun(boss, run, now, position) end
end

local function startCharge(
	boss: TBoss,
	index: number,
	attack: TData.TEnemyAttack,
	now: number,
	position: vector,
	direction: vector,
	length: number,
	tempo: number
)
	local run: TRun = {
		Index = index,
		Attack = attack,
		Speed = runSpeed(attack, tempo),
		Phase = "Run",
		PhaseAt = now,
		From = position,
		Direction = direction,
		Length = length,
		Traveled = 0,
		SkidFrom = position,
		SkidRoom = 0,
		TurnFrom = 0,
		TurnTo = 0,
		ChainsLeft = attack.Chains or 0,
		Hit = {},
		HitDefenses = {},
	}
	local windup = attack.Delay * tempo
	showLine(boss, run, position, windup)
	setBusy(boss, index, math.huge)
	schedule(boss, now + windup, function()
		if not EnemyWorld:contains(boss.Entity) then return end
		boss.Run = run
		beginRun(boss, run, TimeCore.EnemyClock, EnemyWorld:get(boss.Entity, Components.Position) or position)
	end)
end

-- Down through the floor, along under it to its target, and up through theirs, its circle shown `tempo` times as
-- long as authored.
local function startDive(
	boss: TBoss,
	index: number,
	attack: TData.TEnemyAttack,
	now: number,
	targetFeet: vector,
	tempo: number
)
	local kit = boss.Kit
	local warning = attack.Delay * tempo
	setBusy(boss, index, math.huge)
	schedule(boss, now + kit.DiveUnder, function()
		local entity = boss.Entity
		if not EnemyWorld:contains(entity) then return end
		local from = EnemyWorld:get(entity, Components.Position) :: vector
		EnemyWorld:set(entity, Components.Immunity, Tune.UNDER_IMMUNITY)
		EnemyWorld:add(entity, Tags.Submerged)
		EnemiesSpatialHash:Remove(entity)

		-- Where its target stands now, on the floor under them.
		local target = nearestTarget(from) or targetFeet
		local landing = vector.create(target.x, floorAt(target.x, target.z, target.y + 0.75), target.z)
		local under = math.max(vector.magnitude(landing - from) / kit.DiveSpeed, Tune.MIN_UNDER)
		fireMove(boss, EBossMoves.Crack, index, from, landing, under)

		local surfaceAt = TimeCore.EnemyClock + under
		schedule(boss, surfaceAt, function()
			if not EnemyWorld:contains(entity) then return end
			EnemyAttacksService.Telegraph(entity, attack, landing, 0, warning)
		end)

		local riseAt = surfaceAt + warning - kit.DiveRiseImpact
		schedule(boss, riseAt, function()
			if not EnemyWorld:contains(entity) then return end
			local toward = nearestTarget(landing)
			local direction = if toward then flatDirection(landing, toward) else nil
			local yaw = if direction then yawOf(direction) else EnemyWorld:get(entity, Components.Yaw) or 0
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
	end)
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
local function startSummon(boss: TBoss, attack: TData.TEnemyAttack, now: number, position: vector, yaw: number)
	boss.HasSummoned = true
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
	-- The roar comes once, at its line, as authored.
	local tempo = if kind == "Summon" then 1 else bossTempo
	local length = (attack.Length or attack.Delay) * tempo
	fireMove(boss, EBossMoves.Attack, index, position, position, yaw, tempo)
	boss.ReadyAt[index] = now + length + attack.Cooldown * bossTempo
	if kind == "Summon" then
		startSummon(boss, attack, now, position, yaw)
	elseif attack.IsVolley then
		startVolley(boss, index, attack, now, position, tempo)
	else
		startSlam(boss, attack, now, position, yaw, tempo)
	end
	setBusy(boss, index, now + length)
end

-- A charge at its target, aimed where they are running (TEnemyAttack.Lead): the way it goes and how far it can.
local function chargeLine(
	boss: TBoss,
	attack: TData.TEnemyAttack,
	position: vector,
	feet: vector,
	characterEntity: any,
	tempo: number
): (vector?, number)
	local arrives = attack.Delay * tempo + vector.magnitude(feet - position) / runSpeed(attack, tempo)
	local aim = leadPoint(feet, flatVelocity(characterEntity), arrives, attack.Lead or 0)
	local direction = flatDirection(position, aim) or flatDirection(position, feet)
	if not direction then return nil, 0 end
	return direction, traceBody(boss.Kit, position, direction, attack.Radius or 70)
end

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
	local chargeYaw = yawOf(direction)
	EnemyWorld:set(boss.Entity, Components.Yaw, chargeYaw)
	fireMove(boss, EBossMoves.Attack, index, position, position, chargeYaw, tempo)
	boss.ReachedAt = now
	startCharge(boss, index, attack, now, position, direction, length, tempo)
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
	startDive(boss, index, attack, now, feet, tempo)
end

-- The yaw a close punish on the `facing` side of a target at `feet` is made at: a bite turns the head onto them first.
local function aimSlam(
	boss: TBoss,
	facing: TData.TEnemyAttackFacing,
	position: vector,
	yaw: number,
	feet: vector
): number
	local toTarget = flatDirection(position, feet)
	if facing ~= "Front" or not toTarget then return yaw end
	local aimYaw = yawOf(toTarget)
	EnemyWorld:set(boss.Entity, Components.Yaw, aimYaw)
	return aimYaw
end

-- Its next move at the decoy it took (baitOf): the close punish for the side the doll stands on, cooling down or not,
-- else a charge at it from far enough off; the blow pops the doll, whose blast the boss takes. Neither in reach, it
-- walks on to it (Tags.Baited).
local function goForBait(boss: TBoss, now: number, position: vector, yaw: number, share: number, bait: TBait)
	local feet = bait.Feet
	if math.abs(feet.y - position.y) > ArenaCore.MAX_STEP + 1 then return end
	local distance = vector.magnitude(vector.create(feet.x - position.x, 0, feet.z - position.z))
	local tempo = tempoOf(boss, share)
	local attacks = boss.Data.Attacks
	local facing = BossesCore.Facing(boss.Kit, position, yaw, feet)
	for index, attack in attacks do
		if attack.Kind ~= "Slam" or attack.IsVolley or attack.Facing ~= facing then continue end
		if distance > attack.Range or not isInPhase(attack, share) then continue end
		dropBait(boss)
		start(boss, index, now, position, aimSlam(boss, facing, position, yaw, feet), share)
		local beats = attack.Beats
		schedule(boss, now + (if beats then beats[1] else attack.Delay) * tempo, function()
			if EnemyWorld:contains(boss.Entity) then EnemyMovementService.CrushLure(bait.Id, boss.Entity) end
		end)
		return
	end

	for index, attack in attacks do
		if attack.Kind ~= "Charge" or distance < (attack.MinRange or 0) or distance > attack.Range then continue end
		if not isInPhase(attack, share) then continue end
		local direction, length = chargeLine(boss, attack, position, feet, nil, tempo)
		-- A wall short of the doll: it walks round instead.
		if not direction or length < Tune.MIN_CHARGE or length + Tune.RAM_REACH < distance then continue end
		dropBait(boss)
		boss.Crushing = bait
		beginCharge(boss, index, attack, now, position, direction :: vector, length, tempo)
		return
	end
end

-- The move for this moment, by where its target stands: the shield at its health line, a dive at someone it cannot
-- reach, the close punish for the side they are on, then a charge at a runner or spines on the far ones.
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
			local tempo = tempoOf(boss, share)
			local direction, length = chargeLine(boss, attack, position, feet, characterEntity, tempo)
			direction = direction or vector.create(math.sin(yaw), 0, math.cos(yaw))
			beginCharge(boss, index, attack, now, position, direction :: vector, length, tempo)
		elseif attack.Kind == "Dive" then
			beginDive(boss, index, attack, now, position, yaw, feet, share)
		else
			if attack.Kind == "Summon" then boss.HasSummoned = false end
			local facingYaw = if attack.Facing == "Front" then aimYaw else yaw
			EnemyWorld:set(boss.Entity, Components.Yaw, facingYaw)
			start(boss, index, now, position, facingYaw, share)
		end
		return
	end
end

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

	for index, attack in attacks do
		if attack.Kind ~= "Summon" or boss.HasSummoned then continue end
		if not isOpen(boss, index, attack, share, now) then continue end
		start(boss, index, now, position, yaw, share)
		return
	end

	local bait = baitOf(boss, now, position)
	if bait then
		goForBait(boss, now, position, yaw, share, bait)
		return
	end

	if isStranded then
		for index, attack in attacks do
			if attack.Kind ~= "Dive" or not isOpen(boss, index, attack, share, now) then continue end
			beginDive(boss, index, attack, now, position, yaw, feet, share)
			return
		end
	end

	-- The close punish for the side its target stands on.
	local facing = BossesCore.Facing(kit, position, yaw, feet)
	for index, attack in attacks do
		if attack.Kind ~= "Slam" or attack.IsVolley or attack.Facing ~= facing then continue end
		if not isSameLevel or distance > attack.Range or not isOpen(boss, index, attack, share, now) then continue end
		start(boss, index, now, position, aimSlam(boss, facing, position, yaw, feet), share)
		return
	end

	-- At range: a charge down a clear line at where its target is running, a dive up under them, or spines on
	-- everybody far off. Any of them that is open.
	local isChasing = now - boss.ReachedAt >= kit.ChaseSeconds
	local tempo = tempoOf(boss, share)
	local options: { () -> () } = {}
	for index, attack in attacks do
		if not isOpen(boss, index, attack, share, now) then continue end
		if attack.Kind == "Charge" and isSameLevel and distance <= attack.Range then
			if distance < (attack.MinRange or 0) and not isChasing then continue end
			local direction, length = chargeLine(boss, attack, position, feet, characterEntity, tempo)
			if not direction or length < Tune.MIN_CHARGE then continue end
			table.insert(options, function()
				beginCharge(boss, index, attack, now, position, direction :: vector, length, tempo)
			end)
		elseif attack.Kind == "Dive" and distance >= (attack.MinRange or math.huge) then
			table.insert(options, function()
				beginDive(boss, index, attack, now, position, yaw, feet, share)
			end)
		elseif attack.IsVolley and isAnyoneBetween(position, attack.MinRange or 0, attack.Range) then
			table.insert(options, function()
				start(boss, index, now, position, yaw, share)
			end)
		end
	end

	if #options == 0 then return end
	options[math.random(1, #options)]()
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
		HasSummoned = false,
		Guards = {},
		GuardTotal = 0,
		ShieldEndsAt = 0,
		Run = nil,
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

	for entity, position, yaw, health, maxHealth, data in BossQuery do
		local boss = bosses[entity] or adopt(entity, data, position)
		if not boss then continue end
		local share = if maxHealth > 0 then health / maxHealth else 1
		runSteps(boss, now)
		if not EnemyWorld:contains(entity) then continue end
		updateShield(boss, now)
		stepSlow(boss, now)

		local run = boss.Run
		if run then
			stepRun(boss, run, now, enemyDt, EnemyWorld:get(entity, Components.Position) :: vector, share)
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
