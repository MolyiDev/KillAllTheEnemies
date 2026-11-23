-- Classes and their abilities on the server: the class each player plays this run, their cooldowns, the ultimate's
-- meter (filled by kills, never by time) and everything a cast does. The client sends a slot and where it aimed
-- (Abilities.Cast); what that slot is, whether it is ready and what it reaches are worked out here.
--
-- Every area hit is one EnemiesService.DamageMultiple a blow, never a call per body.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local jecs = require(ReplicatedStorage.Packages.jecs)
local Network = require(ServerScriptService.GlobalServer.Network)
local DatabaseService = require(ServerScriptService.GlobalServer.Services.DatabaseService)
local CharacterService = require(script.Parent.CharacterService)
local EconomyService = require(script.Parent.EconomyService)
local EnemiesService = require(script.Parent.EnemiesService)
local EnemyMovementService = require(script.Parent.EnemyMovementService)
local NavService = require(script.Parent.NavService)
local QuestProgressService = require(script.Parent.QuestProgressService)
local AbilitiesCore = require(ReplicatedStorage.GlobalShared.Core.AbilitiesCore)
local ArenaCore = require(ReplicatedStorage.Shared.Core.ArenaCore)
local EnemiesCore = require(ReplicatedStorage.Shared.Core.EnemiesCore)
local TimeCore = require(ReplicatedStorage.Shared.Core.TimeCore)
local Components = require(ReplicatedStorage.GlobalShared.ECS.Components)
local Tags = require(ReplicatedStorage.GlobalShared.ECS.Tags)
local EnemyWorld = require(ReplicatedStorage.GlobalShared.ECS.Worlds.EnemyWorld)
local World = require(ReplicatedStorage.GlobalShared.ECS.Worlds.World)
local getCharacterEntityFromPlayer =
	require(ReplicatedStorage.GlobalShared.Utils.Functions.getCharacterEntityFromPlayer)
local getCharacterFeet = require(ReplicatedStorage.GlobalShared.Utils.Functions.getCharacterFeet)
local sightCast = require(ReplicatedStorage.GlobalShared.Utils.sightCast)
local TData = require(ReplicatedStorage.Types.TData)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)

local ServerNetworkAbilities = Network.Server.Abilities
local ClientNetworkAbilities = Network.Client.Abilities

local EnemiesSpatialHash = EnemiesCore.EnemiesSpatialHash

local Tune = table.freeze({
	-- A cast is accepted this much early against its cooldown: the caster's client counts it down on its own clock.
	COOLDOWN_TOLERANCE = 0.9,
	-- Lures take ids from here up (EnemyMovementService.SetLure): characters' stop at 1000.
	LURE_ID_BASE = 2000,
	-- A decoy is on a u8 on the wire.
	DECOY_IDS = 255,
	-- A blow on a decoy counts once in this long, so a crowd pressed against it costs it a blow a window, not one a
	-- body (CharacterService's hurt window, for the same reason).
	DECOY_HURT_SECONDS = 0.3,
	-- Where a decoy lands is looked for on the nav grid at the aim, then this many steps back toward the thrower: it
	-- must stand where enemies can reach it. A floor counts when it is no higher than this over the point tried.
	DECOY_LANDING_STEPS = 8,
	DECOY_FLOOR_TOLERANCE = 3,
	-- The pop's blast reaches no body whose feet are further than this above or below the doll's.
	DECOY_BLAST_HEIGHT = 10,
	-- Foam catches a body this close whatever the angle (it is pressed against the nozzle), and none whose feet are
	-- further than this above or below the caster's.
	FOAM_NEAR = 5,
	FOAM_HEIGHT = 10,
	-- A wall this close past a body's chest is the body's own width, not cover.
	FOAM_SIGHT_SLACK = 1.5,
	-- The beam's first blow, as it lands, reaches this much further than its ticks.
	ORBITAL_SLAM_SCALE = 1.5,
	ORBITAL_SYNCS_PER_SECOND = 10,
	-- The floor under the beam is looked for from this far over the aim.
	ORBITAL_FLOOR_LOOK_UP = 4,
	-- Landed, the beam looks for what to burn this often (game seconds). It leaves the crowd it is on only for one this
	-- many times bigger, so it does not flick between two.
	ORBITAL_LOOK_SECONDS = 0.25,
	ORBITAL_STAY_MARGIN = 1.3,
})

type TLoadout = {
	Class: TData.TClass,
	-- Each slot's level (the ultimate last), and the ability it casts at that level.
	Levels: { number },
	Abilities: { TData.TAbility },
	-- TimeCore.GameClock each slot can next be cast at.
	ReadyAt: { [number]: number },
	-- Kills banked toward the ultimate.
	Charge: number,
}

type TDecoy = {
	Id: number,
	Owner: Player,
	Ability: TData.TAbility,
	Feet: vector,
	-- GameClock it comes down (and starts to draw the crowd) and goes whatever is left of it.
	LandsAt: number,
	EndsAt: number,
	IsOut: boolean,
	Blows: number,
	HurtUntil: number,
}

-- A foamed body: when it is let go (GameClock), and the speed to give it back (nil for a boss, which is never held).
type TFoamed = { Until: number, Speed: number? }

type TBeam = {
	Player: Player,
	CharacterEntity: jecs.Entity<any>,
	InstanceId: number,
	Ability: TData.TAbility,
	-- Where it stands on the floor, and where it is headed.
	Position: Vector3,
	Aim: Vector3,
	-- GameClock the beam lands, burns out, next strikes and next looks for what to burn.
	FireAt: number,
	EndsAt: number,
	NextTickAt: number,
	NextLookAt: number,
	HasFired: boolean,
}

local AbilityService = {}

local loadouts: { [Player]: TLoadout } = {}
local decoys: { [number]: TDecoy } = {}
local nextDecoyId = 0
local foamed: { [jecs.Entity<any>]: TFoamed } = {}
local beams: { [Player]: TBeam } = {}
local syncAccumulator = 0

-- Scratch, reused so a cast or a beam's blow allocates nothing.
local candidates: { jecs.Entity<any> } = {}
local struck: { jecs.Entity<any> } = {}
local struckIds: { number } = {}
-- The bodies a beam weighs up, and how many bodies the last crowd query walked.
local crowdPositions: { vector } = {}
local crowdSize = 0

local function collect(enemyEntity: any)
	candidates[#candidates + 1] = enemyEntity
end

local function countBody()
	crowdSize += 1
end

local function sendState(player: Player, loadout: TLoadout)
	ServerNetworkAbilities.State.Fire(player, loadout.Class.Id, loadout.Levels, loadout.Charge)
end

-- The class a player plays, and its abilities' levels, are the profile's the first time it is asked this run: the
-- lobby is where they change.
local function loadoutOf(player: Player): TLoadout
	local loadout = loadouts[player]
	if loadout then return loadout end

	local profile = DatabaseService.Get(player)
	local class = AbilitiesCore.ClassOf(if profile then profile.SelectedClass else nil)
	local levels = AbilitiesCore.SlotLevels(if profile then profile.AbilityLevels else nil, class)
	local abilities = table.create(#levels)
	for slot, level in levels do
		abilities[slot] = AbilitiesCore.AtLevel(AbilitiesCore.AbilityAt(class, slot) :: TData.TAbility, level)
	end

	local made: TLoadout = {
		Class = class,
		Levels = levels,
		Abilities = abilities,
		ReadyAt = {},
		Charge = 0,
	}
	loadouts[player] = made
	return made
end

-- ============================== Decoy ==============================

-- One blow on every body round a standing doll, credited to its thrower.
local function blastDecoy(decoy: TDecoy)
	local ability = decoy.Ability
	local damage = ability.Damage
	local radius = ability.BlastRadius
	if not damage or not radius then return end
	local feet = decoy.Feet
	local count = 0

	table.clear(candidates)
	table.clear(struck)
	EnemiesSpatialHash:QueryRadiusAsPoints(feet.x, feet.z, radius, collect)
	for _, enemyEntity in candidates do
		local position = EnemyWorld:get(enemyEntity, Components.Position)
		if not position or math.abs(position.y - feet.y) > Tune.DECOY_BLAST_HEIGHT then continue end
		count += 1
		struck[count] = enemyEntity
	end

	if count == 0 then return end
	EnemiesService.DamageMultiple(getCharacterEntityFromPlayer(decoy.Owner), struck, damage)
end

-- `isBlast`: it pops in the arena (worn out, timed out, replaced) rather than being cleared away with the run or
-- its thrower.
local function popDecoy(decoy: TDecoy, isBlast: boolean)
	decoys[decoy.Id] = nil
	if decoy.IsOut then EnemyMovementService.ClearLure(Tune.LURE_ID_BASE + decoy.Id) end
	ServerNetworkAbilities.DecoyPopped.FireAll(decoy.Id)
	if isBlast and decoy.IsOut then blastDecoy(decoy) end
end

-- The floor a decoy thrown at `target` comes down on: the nav grid's under the aim, or the nearest one found walking
-- back toward the thrower, or the thrower's own feet. Never a blocked node (a barricade stands there) and never a
-- point off the grid, where no enemy could get to it.
local function landingFor(feet: vector, target: Vector3): vector
	local nav = ArenaCore.Nav
	if not nav then return vector.create(target.X, ArenaCore.FlatY, target.Z) end

	local from = Vector3.new(feet.x, feet.y, feet.z)
	local to = Vector3.new(target.X, math.max(target.Y, feet.y), target.Z)
	for step = 0, Tune.DECOY_LANDING_STEPS - 1 do
		local point = to:Lerp(from, step / Tune.DECOY_LANDING_STEPS)
		local node = ArenaCore.NodeAt(nav, point.X, point.Y, point.Z, Tune.DECOY_FLOOR_TOLERANCE)
		if node == ArenaCore.NO_NODE or buffer.readu8(NavService.Blocked, node) ~= 0 then continue end
		return vector.create(point.X, ArenaCore.NodeHeight(nav, node), point.Z)
	end

	return feet
end

local function throwDecoy(
	player: Player,
	characterEntity: jecs.Entity<any>,
	instanceId: number,
	root: BasePart,
	ability: TData.TAbility,
	aimPoint: Vector3
)
	-- One doll a thrower: the last one goes as the next leaves the hand.
	for _, decoy in decoys do
		if decoy.Owner == player then popDecoy(decoy, true) end
	end

	local humanoid = World:get(characterEntity, Components.Humanoid)
	if not humanoid then return end
	local feet =
		landingFor(getCharacterFeet(root, humanoid, 0), AbilitiesCore.ClampAim(root.Position, aimPoint, ability.Range))

	repeat
		nextDecoyId = nextDecoyId % Tune.DECOY_IDS + 1
	until not decoys[nextDecoyId]

	local now = TimeCore.GameClock
	local flight = ability.FlightSeconds or 0
	decoys[nextDecoyId] = {
		Id = nextDecoyId,
		Owner = player,
		Ability = ability,
		Feet = feet,
		LandsAt = now + flight,
		EndsAt = now + flight + ability.Duration,
		IsOut = false,
		Blows = ability.Blows or 1,
		HurtUntil = 0,
	}
	ServerNetworkAbilities.DecoyThrown.FireAll(nextDecoyId, instanceId, feet :: any, flight, ability.Duration)
end

local function strikeDecoy(decoy: TDecoy)
	local now = TimeCore.GameClock
	if now < decoy.HurtUntil or decoys[decoy.Id] ~= decoy then return end
	decoy.HurtUntil = now + Tune.DECOY_HURT_SECONDS
	decoy.Blows -= 1
	if decoy.Blows <= 0 then
		popDecoy(decoy, true)
		return
	end

	ServerNetworkAbilities.DecoyHit.FireAll(decoy.Id)
end

local function stepDecoys(now: number)
	for _, decoy in decoys do
		if now >= decoy.EndsAt then
			popDecoy(decoy, true)
		elseif not decoy.IsOut and now >= decoy.LandsAt then
			decoy.IsOut = true
			EnemyMovementService.SetLure(Tune.LURE_ID_BASE + decoy.Id, decoy.Feet, decoy.Ability.Radius, function()
				strikeDecoy(decoy)
			end)
		end
	end
end

-- ============================== Foam Cannon ==============================

-- Sets one body: held where it stands with no attack to start until it is let go, and brittle meanwhile. A boss is
-- never held (as it is never shoved or staggered), only made brittle.
local function foam(enemyEntity: jecs.Entity<any>, ability: TData.TAbility, now: number)
	local state = foamed[enemyEntity]
	if not state then
		local isBoss = EnemyWorld:has(enemyEntity, Tags.Boss)
		state = { Until = 0, Speed = if isBoss then nil else EnemyWorld:get(enemyEntity, Components.MovementSpeed) }
		foamed[enemyEntity] = state
		if state.Speed then EnemyWorld:set(enemyEntity, Components.MovementSpeed, 0) end
		EnemyWorld:set(enemyEntity, Components.Brittle, ability.DamageTaken or 1)
	end

	state.Until = now + ability.Duration
	-- A negative wind-up is the countdown a finished attack recovers through (enemiesUpdate): it drops the swing being
	-- wound up and starts none until it has run out.
	if state.Speed then EnemyWorld:set(enemyEntity, Components.AttackWindup, -ability.Duration) end
end

local function thaw(enemyEntity: jecs.Entity<any>, state: TFoamed)
	foamed[enemyEntity] = nil
	if not EnemyWorld:contains(enemyEntity) then return end
	if state.Speed then EnemyWorld:set(enemyEntity, Components.MovementSpeed, state.Speed) end
	EnemyWorld:remove(enemyEntity, Components.Brittle)
end

local function sprayFoam(
	player: Player,
	characterEntity: jecs.Entity<any>,
	instanceId: number,
	root: BasePart,
	ability: TData.TAbility,
	aimPoint: Vector3
)
	local humanoid = World:get(characterEntity, Components.Humanoid)
	if not humanoid then return end
	local origin = root.Position
	local feetY = getCharacterFeet(root, humanoid, 0).y
	local toAim = Vector3.new(aimPoint.X - origin.X, 0, aimPoint.Z - origin.Z)
	local look = root.CFrame.LookVector
	local direction = if toAim.Magnitude > 0.5 then toAim.Unit else Vector3.new(look.X, 0, look.Z).Unit
	local cosHalf = math.cos(math.rad((ability.AngleDeg or 0) / 2))
	local now = TimeCore.GameClock

	table.clear(candidates)
	table.clear(struckIds)
	EnemiesSpatialHash:QueryRadiusAsPoints(origin.X, origin.Z, ability.Range, collect)
	for _, enemyEntity in candidates do
		local position = EnemyWorld:get(enemyEntity, Components.Position)
		local aim = EnemyWorld:get(enemyEntity, Components.AimShape)
		local enemyId = EnemyWorld:get(enemyEntity, Components.InstanceId)
		if not position or not aim or not enemyId then continue end
		if math.abs(position.y - feetY) > Tune.FOAM_HEIGHT then continue end
		local flat = Vector3.new(position.x - origin.X, 0, position.z - origin.Z)
		local distance = flat.Magnitude
		if distance > Tune.FOAM_NEAR and flat:Dot(direction) < cosHalf * distance then continue end

		-- Foam does not go through a wall.
		local toChest = Vector3.new(position.x, position.y + aim.x, position.z) - origin
		local wall, wallDistance = sightCast(origin, toChest)
		if wall and wallDistance < toChest.Magnitude - Tune.FOAM_SIGHT_SLACK then continue end

		foam(enemyEntity, ability, now)
		struckIds[#struckIds + 1] = enemyId
	end

	ServerNetworkAbilities.FoamSprayed.FireExcept(player, instanceId, aimPoint)
	if #struckIds > 0 then ServerNetworkAbilities.Foamed.FireAll(struckIds, ability.Duration) end
end

local function stepFoam(now: number)
	for enemyEntity, state in foamed do
		if now >= state.Until or not EnemyWorld:contains(enemyEntity) then thaw(enemyEntity, state) end
	end
end

-- ============================== Orbital Cannon ==============================

-- `point` on the floor under it, by the nav grid; at its own height where there is none (off the map: nothing is
-- there to hit either).
local function onFloor(point: Vector3): Vector3
	local floorY = ArenaCore.GetFloorY(point.X, point.Z, point.Y + Tune.ORBITAL_FLOOR_LOOK_UP)
	return if floorY then Vector3.new(point.X, floorY, point.Z) else point
end

local function endBeam(beam: TBeam)
	beams[beam.Player] = nil
	ServerNetworkAbilities.OrbitalEnded.FireAll(beam.InstanceId)
end

-- One blow of the beam on everything within `radius` of it, at any height: it reaches the sky. Whatever is not a
-- boss takes one figure worth an overkill on the toughest of them, so they come apart rather than fall over; a boss
-- takes a share of its own health.
local function strike(beam: TBeam, radius: number)
	local position = beam.Position
	local bossShare = beam.Ability.BossShare or 0
	local toughest = 0

	table.clear(candidates)
	table.clear(struck)
	EnemiesSpatialHash:QueryRadiusAsPoints(position.X, position.Z, radius, collect)
	for _, enemyEntity in candidates do
		local maxHealth = EnemyWorld:get(enemyEntity, Components.MaxHealth)
		if not maxHealth then continue end
		if EnemyWorld:has(enemyEntity, Tags.Boss) then
			EnemiesService.Damage(beam.CharacterEntity, enemyEntity, maxHealth * bossShare)
			continue
		end
		struck[#struck + 1] = enemyEntity
		toughest = math.max(toughest, maxHealth)
	end

	if #struck == 0 then return end
	EnemiesService.DamageMultiple(beam.CharacterEntity, struck, toughest * EnemiesService.OVERKILL_DAMAGE_RATIO)
end

local function callOrbital(
	player: Player,
	characterEntity: jecs.Entity<any>,
	instanceId: number,
	root: BasePart,
	ability: TData.TAbility,
	aimPoint: Vector3
)
	local now = TimeCore.GameClock
	local position = onFloor(AbilitiesCore.ClampAim(root.Position, aimPoint, ability.Range))
	local targetSeconds = ability.TargetSeconds or 0
	beams[player] = {
		Player = player,
		CharacterEntity = characterEntity,
		InstanceId = instanceId,
		Ability = ability,
		Position = position,
		Aim = position,
		FireAt = now + targetSeconds,
		EndsAt = now + targetSeconds + ability.Duration,
		NextTickAt = 0,
		NextLookAt = 0,
		HasFired = false,
	}
	ServerNetworkAbilities.OrbitalCalled.FireAll(instanceId, position, targetSeconds, ability.Duration)
end

-- How far apart two points are across the floor, squared: the beam reaches up and down without limit.
local function flatDistance2(a: vector, b: vector): number
	local dx, dz = a.x - b.x, a.z - b.z
	return dx * dx + dz * dz
end

-- The middle of the bodies within the beam's reach of `centre`, or `centre` when there are none.
local function crowdMiddle(count: number, centre: vector, reach2: number): vector
	local sum = vector.zero
	local found = 0
	for index = 1, count do
		local position = crowdPositions[index]
		if flatDistance2(position, centre) > reach2 then continue end
		sum += position
		found += 1
	end

	return if found > 0 then sum / found else centre
end

-- How many bodies stand within `radius` of `position` (flat), across the whole arena.
local function crowdAt(position: vector, radius: number): number
	crowdSize = 0
	EnemiesSpatialHash:QueryRadiusAsPoints(position.x, position.z, radius, countBody)
	return crowdSize
end

-- The middle of the thickest crowd round any of the `count` bodies weighed up, the nearest to the beam of those as
-- big. A hash query a body is 0.09 to 0.6 ms a look at 255, against 0.8 to 0.9 for testing every pair. The beam stays
-- on the crowd it is over unless the thickest is ORBITAL_STAY_MARGIN times bigger.
local function thickestCrowd(count: number, here: vector, radius: number): vector
	local best = 1
	local bestSize = -1
	local bestDistance2 = math.huge
	for index = 1, count do
		local position = crowdPositions[index]
		local size = crowdAt(position, radius)
		local distance2 = flatDistance2(position, here)
		if size < bestSize or (size == bestSize and distance2 >= bestDistance2) then continue end
		best = index
		bestSize = size
		bestDistance2 = distance2
	end

	local centre = if bestSize > crowdAt(here, radius) * Tune.ORBITAL_STAY_MARGIN then crowdPositions[best] else here
	return crowdMiddle(count, centre, radius * radius)
end

-- What a landed beam goes after among the bodies within its leash of `origin` (its caster): the boss nearest it, else
-- the thickest crowd. nil when nothing is in reach.
local function findPrey(beam: TBeam, origin: Vector3): Vector3?
	local ability = beam.Ability
	local at = beam.Position
	local here = vector.create(at.X, at.Y, at.Z)
	local boss: vector? = nil
	local bossDistance2 = math.huge
	local count = 0

	table.clear(candidates)
	EnemiesSpatialHash:QueryRadiusAsPoints(origin.X, origin.Z, ability.Range, collect)
	for _, enemyEntity in candidates do
		local position = EnemyWorld:get(enemyEntity, Components.Position)
		if not position then continue end
		if EnemyWorld:has(enemyEntity, Tags.Boss) then
			local distance2 = flatDistance2(position, here)
			if distance2 < bossDistance2 then
				boss = position
				bossDistance2 = distance2
			end
		end
		count += 1
		crowdPositions[count] = position
	end

	if boss then return Vector3.new(boss.x, boss.y, boss.z) end
	if count == 0 then return nil end

	local middle = thickestCrowd(count, here, ability.Radius)
	return Vector3.new(middle.x, middle.y, middle.z)
end

-- The mark holds where it was called until the beam lands; from then the beam goes after a boss or the thickest crowd
-- on its own, at its capped speed, striking as it goes. It ends with its time or with its caster.
local function stepBeam(beam: TBeam, now: number, dt: number)
	local characterEntity = beam.CharacterEntity
	local root = if World:contains(characterEntity)
		then World:get(characterEntity, Components.HumanoidRootPart)
		else nil
	local isStanding = root ~= nil
		and World:has(characterEntity, Tags.Alive)
		and (World:get(characterEntity, Components.CurrentHealth) or 0) > 0
	if not isStanding or now >= beam.EndsAt then
		endBeam(beam)
		return
	end

	if now < beam.FireAt then return end

	local ability = beam.Ability
	local origin = (root :: BasePart).Position
	if now >= beam.NextLookAt then
		beam.NextLookAt = now + Tune.ORBITAL_LOOK_SECONDS
		local prey = findPrey(beam, origin)
		if prey then beam.Aim = prey end
	end

	local aim = onFloor(AbilitiesCore.ClampAim(origin, beam.Aim, ability.Range))
	beam.Position = AbilitiesCore.Chase(beam.Position, aim, ability.Speed or 0, dt)
	if not beam.HasFired then
		beam.HasFired = true
		beam.NextTickAt = now + (ability.TickSeconds or 1)
		strike(beam, ability.Radius * Tune.ORBITAL_SLAM_SCALE)
	elseif now >= beam.NextTickAt then
		beam.NextTickAt = now + (ability.TickSeconds or 1)
		strike(beam, ability.Radius)
	end
end

-- ============================== The run ==============================

local CASTS: { [TData.TAbilityKind]: (Player, jecs.Entity<any>, number, BasePart, TData.TAbility, Vector3) -> () } = {
	Decoy = throwDecoy,
	FoamCannon = sprayFoam,
	OrbitalCannon = callOrbital,
}

-- A new run: every meter empty, every cooldown over, nothing left standing from the last one.
function AbilityService.ResetRun()
	for _, decoy in decoys do
		popDecoy(decoy, false)
	end

	for _, beam in beams do
		endBeam(beam)
	end

	for enemyEntity, state in foamed do
		thaw(enemyEntity, state)
	end

	table.clear(loadouts)
	for _, player in Players:GetPlayers() do
		sendState(player, loadoutOf(player))
	end
end

-- The class `player` plays this run. Asked before the run starts, it is the profile's as it stands; the run's start
-- asks again.
function AbilityService.GetClass(player: Player): TData.TClass
	return loadoutOf(player).Class
end

-- Fills `player`'s ultimate (the console's `ult`).
function AbilityService.FillUltimate(player: Player)
	local loadout = loadoutOf(player)
	loadout.Charge = loadout.Abilities[AbilitiesCore.UltimateSlot(loadout.Class)].ChargeKills or 0
	sendState(player, loadout)
end

-- The intent only: a slot and where the crosshair was. The guards are this side's: the match not paused, a standing
-- character every client knows that has no beam out already nor is picking an upgrade (it cannot be hurt
-- meanwhile), a slot its class has, and that slot ready
-- (its cooldown over and its Gold paid in the same step, or the meter full). The reach is clamped where the ability is cast.
ClientNetworkAbilities.Cast.On(function(player: Player, slot: number, aimPoint: Vector3)
	if TimeCore.IsPaused or beams[player] then return end
	if aimPoint.X ~= aimPoint.X or aimPoint.Y ~= aimPoint.Y or aimPoint.Z ~= aimPoint.Z then return end
	local characterEntity = getCharacterEntityFromPlayer(player)
	if not characterEntity or not World:has(characterEntity, Tags.Alive) then return end
	if World:has(characterEntity, Tags.Picking) then return end
	if (World:get(characterEntity, Components.CurrentHealth) or 0) <= 0 then return end
	local root = World:get(characterEntity, Components.HumanoidRootPart)
	local instanceId = World:get(characterEntity, Components.InstanceId)
	if not root or not instanceId then return end

	local loadout = loadoutOf(player)
	local ability = loadout.Abilities[slot]
	if not ability then return end
	local now = TimeCore.GameClock
	local cooldown = ability.Cooldown
	if cooldown then
		if now < (loadout.ReadyAt[slot] or 0) then return end
		if not EconomyService.TrySpendGold(player, ability.Cost or 0) then return end
		loadout.ReadyAt[slot] = now + cooldown * Tune.COOLDOWN_TOLERANCE
	else
		if loadout.Charge < (ability.ChargeKills or math.huge) then return end
		loadout.Charge = 0
		sendState(player, loadout)
	end

	QuestProgressService.Add(player, if cooldown then "Abilities" else "Ultimates", 1)
	CASTS[ability.Kind](player, characterEntity, instanceId, root, ability, aimPoint)
end)

-- Kills fill the meter, a volley at a time. Not while the beam is out: it would refill itself.
EnemiesService.OnEnemyKilled:Connect(function(killerPlayer: Player?, count: number)
	if not killerPlayer or beams[killerPlayer] then return end
	local loadout = loadoutOf(killerPlayer)
	local needed = loadout.Abilities[AbilitiesCore.UltimateSlot(loadout.Class)].ChargeKills or 0
	if loadout.Charge >= needed then return end
	loadout.Charge = math.min(loadout.Charge + count, needed)
	sendState(killerPlayer, loadout)
end)

EnemiesService.OnEnemyRemoving:Connect(function(enemyEntity: jecs.Entity<any>)
	foamed[enemyEntity] = nil
end)

-- A fresh character's client learns its class and what its meter holds: both outlive a death.
CharacterService.OnCharacterReady:Connect(function(_, player: Player)
	sendState(player, loadoutOf(player))
end)

AbilityService.OnPlayerDisconnected = function(player: Player)
	local beam = beams[player]
	if beam then endBeam(beam) end
	for _, decoy in decoys do
		if decoy.Owner == player then popDecoy(decoy, false) end
	end

	loadouts[player] = nil
end :: TPlayerEvents.OnPlayerDisconnected

RunService.Heartbeat:Connect(function(dt: number)
	if TimeCore.IsPaused then return end
	local now = TimeCore.GameClock
	local gameDt = TimeCore.GetDeltaTime(dt)
	stepDecoys(now)
	stepFoam(now)
	for _, beam in beams do
		stepBeam(beam, now, gameDt)
	end

	syncAccumulator += dt
	if syncAccumulator < 1 / Tune.ORBITAL_SYNCS_PER_SECOND then return end
	syncAccumulator = 0
	for _, beam in beams do
		ServerNetworkAbilities.OrbitalMoved.FireAll(beam.InstanceId, beam.Position)
	end
end)

return Ignis.Register(AbilityService)
