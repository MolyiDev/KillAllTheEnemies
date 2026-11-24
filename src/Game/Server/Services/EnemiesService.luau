-- The enemy lifecycle on the server: spawn, damage, kill, remove. The ECS row in EnemyWorld is the enemy; its record in
-- EnemiesCore.EnemiesSpatialHash is where it is; clients are told by id, and only those subscribed to that body
-- (AOIService). Game layers hook in through the signals: OnEnemyDied for Gold and loot, OnEnemyKilled for the round.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local Signal = require(ReplicatedStorage.Packages.Signal)
local jecs = require(ReplicatedStorage.Packages.jecs)
local Network = require(ServerScriptService.GlobalServer.Network)
local AOIService = require(script.Parent.AOIService)
local ConfigsCore = require(ReplicatedStorage.GlobalShared.Core.ConfigsCore)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local EnemiesCore = require(ReplicatedStorage.Shared.Core.EnemiesCore)
local TimeCore = require(ReplicatedStorage.Shared.Core.TimeCore)
local Components = require(ReplicatedStorage.GlobalShared.ECS.Components)
local EnemyWorldRef = require(ReplicatedStorage.GlobalShared.ECS.References.EnemyWorldRef)
local Tags = require(ReplicatedStorage.GlobalShared.ECS.Tags)
local EnemyWorld = require(ReplicatedStorage.GlobalShared.ECS.Worlds.EnemyWorld)
local World = require(ReplicatedStorage.GlobalShared.ECS.Worlds.World)
local IdGenerator = require(ReplicatedStorage.GlobalShared.Utils.IdGenerator)
local getPlayerFromCharacterEntity =
	require(ReplicatedStorage.GlobalShared.Utils.Functions.getPlayerFromCharacterEntity)
local EConfigKeys = require(ReplicatedStorage.Types.Enums.EConfigKeys)
local EGenerator = require(ReplicatedStorage.Types.Enums.EGenerator)
local TData = require(ReplicatedStorage.Types.TData)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)

local ServerNetworkEnemies = Network.Server.Enemies

local ENEMIES = DataCore.Enemies.ById
local EnemiesSpatialHash = EnemiesCore.EnemiesSpatialHash
local EnemiesImmuneQuery = EnemyWorld:query(Components.Immunity):with(Tags.Enemy):cached()
local EnemiesQuery = EnemyWorld:query(Tags.Enemy):cached()
local NukeQuery = EnemyWorld:query(Components.Position, Components.MaxHealth):with(Tags.Enemy):cached()
local BossQuery =
	EnemyWorld:query(Components.DataId, Components.CurrentHealth, Components.MaxHealth):with(Tags.Boss):cached()

-- A fresh body cannot be hurt for this long, so a blast on the spawn point does not delete it before anyone saw it.
local ENEMY_IMMUNITY_TIME = 0.35
local AOI_TICK_SECONDS = 0.25
local BOSS_BAR_SECONDS = 0.1
-- u16 on the wire; 0 is never handed out.
local IdEntityGen = IdGenerator.new(EGenerator.EnemyEntities, 1, 65535)

local enemyCount = 0
local aoiAccumulator = 0
local bossBarAccumulator = 0
local isBossBarDirty = false
-- The health each player has taken off the boss now up, for their part of its bar. A new boss starts it over.
local bossDamage: { [Player]: number } = {}
-- The Nuke All blast while it rolls (KillAll): where it was set off, the GameClock it started at, and who is paid.
local nukeOrigin: vector? = nil
local nukeStartedAt = 0
local nukeInflictor: jecs.Entity<any>? = nil

-- Scratch, reused so the batched paths allocate nothing per call.
local reusableKilledEntities: { jecs.Entity<any> } = {}
local reusableKilledIds: { number } = {}
local reusableDamagedIds: { number } = {}
local reusableToRemove: { jecs.Entity<any> } = {}
local reusableBrittle: { jecs.Entity<any> } = {}
local reusablePlayers: { Player } = {}
local reusablePerPlayer: { [Player]: { number } } = {}

local EnemiesService = {}

EnemiesService.MAX_ALIVE = EnemiesCore.MAX_ALIVE

-- A killing blow worth this many times the body's max health pulverizes it (the kill events' overkill flag).
local OVERKILL_DAMAGE_RATIO = 4
EnemiesService.OVERKILL_DAMAGE_RATIO = OVERKILL_DAMAGE_RATIO

-- (killerPlayer?, killCount), once per Kill / KillMultiple call.
EnemiesService.OnEnemyKilled = Signal.new()
-- (position, enemyData, killerPlayer?), once per BODY a player put down: the Gold and loot hook. Not on a removal.
EnemiesService.OnEnemyDied = Signal.new()
-- (enemyEntity), just before a body's row goes, for whoever keeps per-body state (EnemyAttacksService).
EnemiesService.OnEnemyRemoving = Signal.new()

-- A hit the body survives drops the swing it was winding up and holds the next one off for HitStunTime, carried
-- as a NEGATIVE AttackWindup: that is already the countdown a finished attack recovers through, so the stagger needs
-- no component and no branch in the movement update. A ground warning is never dropped: EnemyAttacksService resolves
-- it anyway, so its caster stays on it rather than walking away from where it lands.
local function stagger(enemyEntity: jecs.Entity<any>, enemyData: TData.TEnemy)
	if enemyData.IsBoss then return end
	local windup = EnemyWorld:get(enemyEntity, Components.AttackWindup)
	if not windup then return end
	if windup > 0 then
		local windingUp = enemyData.Attacks[EnemyWorld:get(enemyEntity, Components.AttackIndex) :: number]
		if windingUp and windingUp.Kind ~= "Melee" then return end
	end

	local stunTime = enemyData.HitStunTime
	if not stunTime then
		if windup > 0 then EnemyWorld:set(enemyEntity, Components.AttackWindup, 0) end
		return
	end

	EnemyWorld:set(enemyEntity, Components.AttackWindup, math.min(windup, -stunTime))
end

local function getInflictorId(inflictorEntity: jecs.Entity<any>?): number
	if not inflictorEntity or not World:contains(inflictorEntity) then return 0 end
	return World:get(inflictorEntity, Components.InstanceId) or 0
end

local function getKillerPlayer(inflictorEntity: jecs.Entity<any>?): Player?
	if not inflictorEntity or not World:contains(inflictorEntity) then return nil end
	return getPlayerFromCharacterEntity(inflictorEntity)
end

-- `landed` is what the blow took off, never past what the boss had left, so the parts add up to its bar.
local function creditBoss(inflictorEntity: jecs.Entity<any>?, landed: number)
	isBossBarDirty = true
	local player = getKillerPlayer(inflictorEntity)
	if not player then return end
	bossDamage[player] = (bossDamage[player] or 0) + landed
end

function EnemiesService.GetCount(): number
	return enemyCount
end

function EnemiesService.HasRoom(): boolean
	return enemyCount < EnemiesService.MAX_ALIVE
end

-- Spawns one body at `position` (its feet). Refuses past MAX_ALIVE: callers hold their spawns, they do not drop
-- them (RoundService). Returns the instance id and entity, or nothing when refused.
function EnemiesService.Spawn(
	dataId: number,
	position: vector,
	healthScale: number?,
	damageScale: number?,
	speedScale: number?
): (number?, jecs.Entity<any>?)
	if enemyCount >= EnemiesService.MAX_ALIVE then return nil, nil end
	local enemyData = ENEMIES[dataId]
	if not enemyData then return nil, nil end

	-- Skip any id still in use: recycling a live id would silently steal its body on every client.
	local instanceId = IdEntityGen:Generate()
	while EnemyWorldRef:Search(instanceId) do
		instanceId = IdEntityGen:Generate()
	end

	local collisionSize = enemyData.CollisionSize
	local radius = math.max(collisionSize.X, collisionSize.Z)
	local halfExtents = vector.create(collisionSize.X / 2, collisionSize.Y / 2, collisionSize.Z / 2)
	local maxHealth = enemyData.BaseMaxHealth * (healthScale or 1)
	local enemy = EnemyWorldRef:EntityRef(instanceId)

	-- Every enemy carries the same set, so the whole crowd shares one archetype and every per-tick write in the
	-- movement update is a plain column store. Immunity leaves on its own timer; Boss is set once at spawn.
	jecs.bulk_insert(EnemyWorld, enemy, {
		Components.Position,
		Components.Velocity,
		Components.Force,
		Components.Radius,
		Components.HalfExtents,
		Components.AimShape,
		Components.Mass,
		Components.AttackWindup,
		Components.AttackIndex,
		Components.AttackCount,
		Components.MaxHealth,
		Components.CurrentHealth,
		Components.Damage,
		Components.MovementSpeed,
		Components.Yaw,
		Components.InstanceId,
		Components.DataId,
		Components.Data,
		Components.Immunity,
		Tags.Enemy,
	}, {
		position,
		vector.zero,
		vector.zero,
		radius,
		halfExtents,
		EnemiesCore.AimShape(enemyData),
		enemyData.Mass,
		0,
		1,
		0,
		maxHealth,
		maxHealth,
		enemyData.BaseDamage * (damageScale or 1),
		enemyData.BaseMovementSpeed * (speedScale or 1),
		0,
		instanceId,
		enemyData.Id,
		enemyData,
		ENEMY_IMMUNITY_TIME,
	})
	if enemyData.IsBoss then
		EnemyWorld:add(enemy, Tags.Boss)
		isBossBarDirty = true
		table.clear(bossDamage)
	end

	enemyCount += 1
	EnemiesSpatialHash:AddAABB(enemy, position, halfExtents)
	table.clear(reusablePlayers)
	AOIService.GetVisiblePlayersInto(position.x, position.y, position.z, reusablePlayers)
	for _, player in reusablePlayers do
		AOIService.Subscribe(player, instanceId)
	end

	if #reusablePlayers > 0 then
		ServerNetworkEnemies.Added.FireList(reusablePlayers, instanceId, dataId, position :: any, true)
	end

	return instanceId, enemy
end

-- Takes a body out without a death: no clip, no credit. `signal` false when the caller tells clients itself.
function EnemiesService.Remove(enemyEntity: jecs.Entity<any>, signal: boolean): number?
	local instanceId = EnemyWorld:get(enemyEntity, Components.InstanceId)
	if not instanceId then return nil end

	EnemiesService.OnEnemyRemoving:Fire(enemyEntity)
	if EnemyWorld:has(enemyEntity, Tags.Boss) then isBossBarDirty = true end
	enemyCount -= 1
	EnemiesSpatialHash:Remove(enemyEntity)
	if signal then
		table.clear(reusablePlayers)
		AOIService.PopSubscribedPlayersInto(instanceId, reusablePlayers)
		if #reusablePlayers > 0 then ServerNetworkEnemies.Removed.FireList(reusablePlayers, instanceId) end
	else
		AOIService.OnEnemyRemoved(instanceId)
	end

	EnemyWorldRef:Nuke(instanceId, enemyEntity)
	return instanceId
end

-- A player came into view of a body that already existed: tell them about it.
local function onNewlySubscribed(player: Player, instanceId: number)
	local entity = EnemyWorldRef:Search(instanceId)
	if not entity then return end
	local dataId = EnemyWorld:get(entity, Components.DataId)
	local position = EnemyWorld:get(entity, Components.Position)
	if dataId and position then ServerNetworkEnemies.Added.Fire(player, instanceId, dataId, position :: any, false) end
end

-- Shows every body to every player who has not been shown it, wherever it is. Only for a handful (RoundService's
-- last few of a wave): every one shown takes a Highlight slot on every client.
function EnemiesService.ShowToEveryone()
	for enemyEntity in EnemiesQuery do
		local instanceId = EnemyWorld:get(enemyEntity, Components.InstanceId)
		if instanceId then AOIService.SubscribeEveryone(instanceId, onNewlySubscribed) end
	end
end

function EnemiesService.ClearAll()
	table.clear(reusableToRemove)
	for enemyEntity in EnemiesQuery do
		reusableToRemove[#reusableToRemove + 1] = enemyEntity
	end

	for _, enemyEntity in reusableToRemove do
		EnemiesService.Remove(enemyEntity, true)
	end

	table.clear(reusableToRemove)
	enemyCount = 0
	nukeOrigin = nil
	nukeInflictor = nil
	EnemiesSpatialHash:Reset()
	AOIService.Reset()
end

-- The client plays the attack's clip. Every subscriber, since a wind-up is the telegraph.
function EnemiesService.SignalAttackStarted(enemyEntity: jecs.Entity<any>, attackIndex: number)
	local instanceId = EnemyWorld:get(enemyEntity, Components.InstanceId)
	if not instanceId then return end
	table.clear(reusablePlayers)
	AOIService.GetSubscribedPlayersInto(instanceId, reusablePlayers)
	if #reusablePlayers > 0 then
		ServerNetworkEnemies.AttackStarted.FireList(reusablePlayers, instanceId, attackIndex)
	end
end

function EnemiesService.Kill(inflictorEntity: jecs.Entity<any>?, enemyEntity: jecs.Entity<any>, damage: number)
	-- Read before Remove tears the row down.
	local position = EnemyWorld:get(enemyEntity, Components.Position)
	local enemyData = EnemyWorld:get(enemyEntity, Components.Data)
	local instanceId = EnemyWorld:get(enemyEntity, Components.InstanceId)
	local maxHealth = EnemyWorld:get(enemyEntity, Components.MaxHealth)
	if not instanceId then return end
	table.clear(reusablePlayers)
	AOIService.PopSubscribedPlayersInto(instanceId, reusablePlayers)
	EnemiesService.Remove(enemyEntity, false)

	if #reusablePlayers > 0 then
		local isOverkill = maxHealth ~= nil and damage >= maxHealth * OVERKILL_DAMAGE_RATIO
		ServerNetworkEnemies.Killed.FireList(
			reusablePlayers,
			getInflictorId(inflictorEntity),
			instanceId,
			damage,
			isOverkill
		)
	end

	local killerPlayer = getKillerPlayer(inflictorEntity)
	if killerPlayer and position and enemyData then
		EnemiesService.OnEnemyDied:Fire(position, enemyData, killerPlayer)
	end
	EnemiesService.OnEnemyKilled:Fire(killerPlayer, 1)
end

function EnemiesService.KillMultiple(
	inflictorEntity: jecs.Entity<any>?,
	enemyEntities: { jecs.Entity<any> },
	damage: number
)
	local killerPlayer = getKillerPlayer(inflictorEntity)
	table.clear(reusableKilledIds)
	-- One damage figure for the whole volley, so one overkill answer, measured against the toughest body it killed: a
	-- blast through a line of weaklings and one heavy only pulverizes if it would have pulverized the heavy.
	local toughestMaxHealth = 0
	for _, enemyEntity in enemyEntities do
		if not EnemyWorld:contains(enemyEntity) then continue end
		local instanceId = EnemyWorld:get(enemyEntity, Components.InstanceId)
		if not instanceId then continue end
		reusableKilledIds[#reusableKilledIds + 1] = instanceId
		toughestMaxHealth = math.max(toughestMaxHealth, EnemyWorld:get(enemyEntity, Components.MaxHealth) or 0)
	end

	if #reusableKilledIds == 0 then return end
	AOIService.PopSubscribedPlayersMultiple(reusableKilledIds, reusablePerPlayer)

	local killedCount = 0
	for _, enemyEntity in enemyEntities do
		if not EnemyWorld:contains(enemyEntity) then continue end
		local position = EnemyWorld:get(enemyEntity, Components.Position)
		local enemyData = EnemyWorld:get(enemyEntity, Components.Data)
		if not EnemiesService.Remove(enemyEntity, false) then continue end
		killedCount += 1
		if killerPlayer and position and enemyData then
			EnemiesService.OnEnemyDied:Fire(position, enemyData, killerPlayer)
		end
	end

	local inflictorId = getInflictorId(inflictorEntity)
	local isOverkill = toughestMaxHealth > 0 and damage >= toughestMaxHealth * OVERKILL_DAMAGE_RATIO
	for player, ids in reusablePerPlayer do
		ServerNetworkEnemies.KilledMultiple.Fire(player, inflictorId, ids, damage, isOverkill)
	end
	AOIService.ReleasePerPlayerLists(reusablePerPlayer)
	EnemiesService.OnEnemyKilled:Fire(killerPlayer, killedCount)
end

-- The Nuke All product: a blast rolls out from `origin` (EnemiesCore.NUKE_SPEED) and kills every body it reaches,
-- immune ones and bosses too, each blown apart; once it has run NUKE_SECONDS everything still alive goes with it. The
-- bodies round `origin` die on the next step. A second one while the first rolls starts over from its own origin.
function EnemiesService.KillAll(inflictorEntity: jecs.Entity<any>?, origin: vector)
	nukeOrigin = origin
	nukeStartedAt = TimeCore.GameClock
	nukeInflictor = inflictorEntity
end

-- One blow on one body. `damage` is the server's figure, never the client's. Returns what landed, or nothing when
-- it did not (gone, immune).
function EnemiesService.Damage(
	inflictorEntity: jecs.Entity<any>?,
	enemyEntity: jecs.Entity<any>,
	damage: number
): number?
	if not EnemyWorld:contains(enemyEntity) then return nil end
	if EnemyWorld:has(enemyEntity, Components.Immunity) then return nil end
	local currentHealth = EnemyWorld:get(enemyEntity, Components.CurrentHealth)
	local enemyData = EnemyWorld:get(enemyEntity, Components.Data)
	if not currentHealth or not enemyData then return nil end

	damage *= EnemyWorld:get(enemyEntity, Components.Brittle) or 1
	if enemyData.IsBoss then creditBoss(inflictorEntity, math.min(damage, currentHealth)) end
	currentHealth -= damage
	if currentHealth <= 0 then
		EnemiesService.Kill(inflictorEntity, enemyEntity, damage)
		return damage
	end

	EnemyWorld:set(enemyEntity, Components.CurrentHealth, currentHealth)
	stagger(enemyEntity, enemyData)
	local instanceId = EnemyWorld:get(enemyEntity, Components.InstanceId) :: number
	table.clear(reusablePlayers)
	AOIService.GetSubscribedPlayersInto(instanceId, reusablePlayers)
	if #reusablePlayers > 0 then
		ServerNetworkEnemies.Damaged.FireList(reusablePlayers, getInflictorId(inflictorEntity), instanceId, damage)
	end

	return damage
end

-- One figure on many bodies: one event for the survivors and one for the dead per player. Brittle bodies are left
-- out and kept in reusableBrittle unless `isBrittleBatch` (DamageMultiple gives them their own figure). Returns how
-- many it killed and the largest Brittle multiplier it left out.
local function damageBatch(
	inflictorEntity: jecs.Entity<any>?,
	enemyEntities: { jecs.Entity<any> },
	damage: number,
	isBrittleBatch: boolean
): (number, number)
	table.clear(reusableKilledEntities)
	table.clear(reusableDamagedIds)
	local brittleScale = 1

	for _, enemyEntity in enemyEntities do
		if not EnemyWorld:contains(enemyEntity) then continue end
		if EnemyWorld:has(enemyEntity, Components.Immunity) then continue end
		local currentHealth = EnemyWorld:get(enemyEntity, Components.CurrentHealth)
		local enemyData = EnemyWorld:get(enemyEntity, Components.Data)
		if not currentHealth or not enemyData then continue end
		local brittle = if isBrittleBatch then nil else EnemyWorld:get(enemyEntity, Components.Brittle)
		if brittle then
			reusableBrittle[#reusableBrittle + 1] = enemyEntity
			brittleScale = math.max(brittleScale, brittle)
			continue
		end
		if enemyData.IsBoss then creditBoss(inflictorEntity, math.min(damage, currentHealth)) end

		currentHealth -= damage
		if currentHealth <= 0 then
			reusableKilledEntities[#reusableKilledEntities + 1] = enemyEntity
			continue
		end
		EnemyWorld:set(enemyEntity, Components.CurrentHealth, currentHealth)
		stagger(enemyEntity, enemyData)
		reusableDamagedIds[#reusableDamagedIds + 1] = EnemyWorld:get(enemyEntity, Components.InstanceId) :: number
	end

	local killCount = #reusableKilledEntities
	if killCount > 0 then EnemiesService.KillMultiple(inflictorEntity, reusableKilledEntities, damage) end
	if #reusableDamagedIds > 0 then
		AOIService.BuildSubscribedPerPlayerLists(reusableDamagedIds, reusablePerPlayer)
		local inflictorId = getInflictorId(inflictorEntity)
		for player, ids in reusablePerPlayer do
			ServerNetworkEnemies.DamagedMultiple.Fire(player, inflictorId, ids, damage)
		end

		AOIService.ReleasePerPlayerLists(reusablePerPlayer)
	end

	return killCount, brittleScale
end

-- One blow on many bodies (a cleave, a blast, a turret's volley). One event for the survivors and one for the
-- dead per player, however many it caught; the brittle ones among them (Components.Brittle) take the blow times
-- their multiplier as a volley of their own, since a volley carries one figure. Returns how many it killed.
function EnemiesService.DamageMultiple(
	inflictorEntity: jecs.Entity<any>?,
	enemyEntities: { jecs.Entity<any> },
	damage: number
): number
	table.clear(reusableBrittle)
	local killCount, brittleScale = damageBatch(inflictorEntity, enemyEntities, damage, false)
	if #reusableBrittle > 0 then
		killCount += damageBatch(inflictorEntity, reusableBrittle, damage * brittleScale, true)
		table.clear(reusableBrittle)
	end

	return killCount
end

-- The boss bar is the round's, so it goes to everybody whether or not the body is in view, with the two biggest parts.
local function sendBossBar()
	for _, dataId, health, maxHealth in BossQuery do
		local first: Player?, second: Player? = nil, nil
		local firstDamage, secondDamage = 0, 0
		for player, damage in bossDamage do
			if damage > firstDamage then
				second, secondDamage = first, firstDamage
				first, firstDamage = player, damage
			elseif damage > secondDamage then
				second, secondDamage = player, damage
			end
		end

		ServerNetworkEnemies.BossHealth.FireAll(
			dataId,
			math.max(health, 0),
			maxHealth,
			if first then first.UserId else 0,
			firstDamage,
			if second then second.UserId else 0,
			secondDamage
		)
		return
	end

	ServerNetworkEnemies.BossHealth.FireAll(0, 0, 0, 0, 0, 0, 0)
end

-- One step of the blast: every body its front has passed (flat distance, so a deck over the blast goes with the floor
-- under it) in one volley, the blow worth an overkill on the toughest of them.
local function stepNuke()
	local origin = nukeOrigin
	if not origin then return end
	local elapsed = TimeCore.GameClock - nukeStartedAt
	local isOver = elapsed >= EnemiesCore.NUKE_SECONDS
	local reach = elapsed * EnemiesCore.NUKE_SPEED
	local reachSq = reach * reach
	local count = 0
	local toughestMaxHealth = 0

	table.clear(reusableToRemove)
	for enemyEntity, position, maxHealth in NukeQuery do
		if not isOver then
			local offset = position - origin
			if offset.x * offset.x + offset.z * offset.z > reachSq then continue end
		end
		count += 1
		reusableToRemove[count] = enemyEntity
		toughestMaxHealth = math.max(toughestMaxHealth, maxHealth)
	end

	if count > 0 then
		EnemiesService.KillMultiple(nukeInflictor, reusableToRemove, toughestMaxHealth * OVERKILL_DAMAGE_RATIO)
	end
	table.clear(reusableToRemove)
	if not isOver then return end
	nukeOrigin = nil
	nukeInflictor = nil
end

EnemiesService.OnPlayerDisconnected = function(player: Player)
	bossDamage[player] = nil
end :: TPlayerEvents.OnPlayerDisconnected

-- A live lever to shed load (Enemies.MaxAlive in MainConfig.json). It can only lower the cap: EnemiesCore.MAX_ALIVE is
-- a ceiling the clients are built for, not a default. Bodies already alive stay; spawns wait until the count drops.
ConfigsCore.Observe(EConfigKeys.Enemies, function(config)
	local maxAlive = if type(config) == "table" then tonumber(config.MaxAlive) else nil
	EnemiesService.MAX_ALIVE = if maxAlive
		then math.clamp(math.floor(maxAlive), 0, EnemiesCore.MAX_ALIVE)
		else EnemiesCore.MAX_ALIVE
end)

RunService.Heartbeat:Connect(function(dt: number)
	if TimeCore.IsPaused then return end

	-- Game time, not enemy time: a freeze must not trap fresh bodies in their immunity.
	local gameDt = TimeCore.GetDeltaTime(dt)
	for enemyEntity, immunity in EnemiesImmuneQuery do
		immunity -= gameDt
		if immunity <= 0 then
			EnemyWorld:remove(enemyEntity, Components.Immunity)
		else
			EnemyWorld:set(enemyEntity, Components.Immunity, immunity)
		end
	end

	stepNuke()

	aoiAccumulator += dt
	if aoiAccumulator >= AOI_TICK_SECONDS then
		aoiAccumulator = 0
		AOIService.Tick(onNewlySubscribed)
	end

	bossBarAccumulator += dt
	if isBossBarDirty and bossBarAccumulator >= BOSS_BAR_SECONDS then
		bossBarAccumulator = 0
		isBossBarDirty = false
		sendBossBar()
	end
end)

return Ignis.Register(EnemiesService)
