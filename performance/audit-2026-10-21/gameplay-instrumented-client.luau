local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")
local Network = require(StarterPlayer.StarterPlayerScripts.GlobalClient.Network)
local StatsController = require(script.Parent.Parent.StatsController)
local TelegraphController = require(script.Parent.Parent.TelegraphController)
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local jecs = require(ReplicatedStorage.Packages.jecs)
local SoulsGain = require(ReplicatedStorage.Data.Passives.SoulsGain)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local EnemiesCore = require(ReplicatedStorage.Shared.Core.EnemiesCore)
local PassivesCore = require(ReplicatedStorage.GlobalShared.Core.PassivesCore)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local GeneratorCore = require(ReplicatedStorage.Shared.Core.GeneratorCore)
local StreakCore = require(ReplicatedStorage.Shared.Core.StreakCore)
local TimeCore = require(ReplicatedStorage.Shared.Core.TimeCore)
local Components = require(ReplicatedStorage.GlobalShared.ECS.Components)
local EnemyWorldRef = require(ReplicatedStorage.GlobalShared.ECS.References.EnemyWorldRef)
local Tags = require(ReplicatedStorage.GlobalShared.ECS.Tags)
local EnemyWorld = require(ReplicatedStorage.GlobalShared.ECS.Worlds.EnemyWorld)
local World = require(ReplicatedStorage.GlobalShared.ECS.Worlds.World)
local EnemyPacker = require(ReplicatedStorage.Shared.Packers.EnemyPacker)
local getCharacterEntityFromInstanceId =
	require(ReplicatedStorage.GlobalShared.Utils.Functions.getCharacterEntityFromInstanceId)
local getCharacterEntityFromPlayer =
	require(ReplicatedStorage.GlobalShared.Utils.Functions.getCharacterEntityFromPlayer)
local ObjectPooler = require(ReplicatedStorage.GlobalShared.Utils.ObjectPooler)
local TData = require(ReplicatedStorage.Types.TData)
local FloatingNumbers = require(script.Parent.Parent.Parent.Utils.FloatingNumbers)
local DebugController = require(script.Parent.Parent.DebugController)
local DebuffsController = require(script.Parent.Parent.DebuffsController)
local ModifiersController = require(script.Parent.Parent.ModifiersController)
local ParticleHelper = require(ReplicatedStorage.GlobalShared.Core.ParticleHelper)
local SettingsController = require(script.Parent.Parent.Parent.Parent.GlobalClient.Controllers.SettingsController)
local Signal = require(ReplicatedStorage.Packages.Signal)
local ESettings = require(ReplicatedStorage.Types.Enums.Settings.ESettings)
local ESettingsVisual = require(ReplicatedStorage.Types.Enums.Settings.ESettingsVisual)

local atan2 = math.atan2
local sin = math.sin
local cos = math.cos
local exp = math.exp
local rad = math.rad
local random = math.random
local max = math.max
local floor = math.floor

local EnemiesFolder = Workspace:WaitForChild("Enemies") :: Folder

local Camera = Workspace.CurrentCamera
local EnemiesQuery =
	EnemyWorld
		:query(Components.CFrame, Components.WalkAnimation, Components.Bone, Components.InstanceId, Components.Data)
		:cached()

local FAR_AWAY_CFRAME = CFrame.new(2 ^ 24, 2 ^ 24, 2 ^ 24)
local FAR_AWAY_X = FAR_AWAY_CFRAME.Position.X
local V3_YAXIS = Vector3.yAxis
local SNAP_DISTANCE_SQ = 25 * 25
local HIT_SPREAD = 2
local renderDist = SettingsController.GetNumber(ESettings.Visual, ESettingsVisual.RenderDistance)
local animDist = SettingsController.GetNumber(ESettings.Visual, ESettingsVisual.AnimationDistance)
local RENDER_DISTANCE_SQ = renderDist * renderDist
local ANIMATION_DISTANCE_SQ = animDist * animDist

local particlesEnabled = SettingsController.GetNumber(ESettings.Visual, ESettingsVisual.Particles) > 0

SettingsController.OnNumberChanged:Connect(function(category, key, value)
	if category ~= ESettings.Visual then return end
	if key == ESettingsVisual.RenderDistance then
		RENDER_DISTANCE_SQ = value * value
	elseif key == ESettingsVisual.AnimationDistance then
		ANIMATION_DISTANCE_SQ = value * value
	elseif key == ESettingsVisual.Particles then
		particlesEnabled = value > 0
	end
end)

local EnemiesController = {}
EnemiesController.OnEnemyKilled = Signal.new() :: Signal.Signal<number>
EnemiesController.OnLocalKill = Signal.new() :: Signal.Signal<number>

local EnemyPools: { [number]: ObjectPooler.ObjectPoolerAPI<TData.TEnemyModel> } = {}
local EliteEnemyPools: { [number]: ObjectPooler.ObjectPoolerAPI<TData.TEnemyModel> } = {}
local EnemyDeathPools: { [number]: ObjectPooler.ObjectPoolerAPI<TData.TDeathEffect> } = {}
local ModelToWalkTrack: { [TData.TEnemyModel]: AnimationTrack } = {}

local retiredDataIds: { [number]: boolean } = {}
local elitePoolKeyToDataId: { [number]: number } = {}

local function getElitePoolKey(dataId: number, tier: number): number
	return dataId * 10 + tier
end

local HitEffect = ReplicatedStorage:WaitForChild("Effects"):WaitForChild("Hit") :: { Hit: ParticleEmitter } & Attachment
local HitEffectsPool = ObjectPooler.new(HitEffect, 20, 20, ObjectPooler.ReturnCF, Workspace.Temporal)

local EnemiesPosition = {}
local freshlyAdded: { [number]: boolean } = {}
-- TimeCore.EnemyClock value at each position-packer write. An enemy is stale once
-- EnemyClock - lastUpdate > STALE_TIME, meaning the server frustum filter dropped
-- it (camera turned away, player walked off, etc.) and its targetPos must not lerp
-- back in as a frozen "zombie". EnemyClock pauses during full pause AND enemy-only
-- pauses (augment select etc.), so this doesn't false-flag while enemies sit still.
local EnemiesLastUpdate: { [number]: number } = {}
local STALE_TIME = 1

-- Debounce so multi-weapon volleys don't stack hit particles + sounds on the
-- same target. os.clock so the timer keeps advancing across pauses (no damage
-- events fire while paused, so the cooldown will simply have expired by the
-- time the next hit comes in).
local HIT_EFFECT_DEBOUNCE = 0.5

local cameraCF = Camera.CFrame
local cameraLookVector = cameraCF.LookVector
local threshold = 0
local thresholdSq = 0
local cameraPosX, cameraPosY, cameraPosZ = 0, 0, 0

local deathSoundPool = SoundsCore.CreatePool(ReplicatedStorage.Sounds.EnemyDeath :: Sound, 8)
local hitSoundPool = SoundsCore.CreatePool(ReplicatedStorage.Sounds.EnemyHit :: Sound, 8)
local DEATH_SOUND_VOLUME_SCALE = 0.6

-- Takes pre-fetched components so hot callers (KillEnemy / KilledMultiple) don't
-- have to re-fetch what they already read. deathEffect=nil means the caller has
-- already returned the effect to its pool and this path should skip it.
-- walkAnim:Stop(0) uses fade=0 to skip the default 0.1s fade - otherwise the
-- animator keeps writing bones for 6 more frames after the enemy is pooled.
local function removeEntityInternal(
	entity: jecs.Entity<any>,
	enemyData: TData.TEnemy?,
	walkAnim: AnimationTrack?,
	model: any?,
	deathEffect: any?,
	instanceId: number?,
	eliteTier: number?
)
	if walkAnim then walkAnim:Stop(0) end

	if enemyData then
		local isRetired = retiredDataIds[enemyData.Id]
		if model then
			if isRetired then
				model:Destroy()
			elseif eliteTier then
				local elitePool = EliteEnemyPools[getElitePoolKey(enemyData.Id, eliteTier)]
				if elitePool then
					elitePool:Return(model)
				else
					-- Pool was drained (e.g. retired between drain tick and kill); destroy
					-- the model directly so it doesn't get orphaned in the world.
					model:Destroy()
				end
			else
				local enemyPool = EnemyPools[enemyData.Id]
				if enemyPool then
					enemyPool:Return(model)
				else
					model:Destroy()
				end
			end
		end

		if deathEffect then
			if isRetired then
				deathEffect:Destroy()
			else
				local deathPool = EnemyDeathPools[enemyData.Id]
				if deathPool then
					deathPool:Return(deathEffect)
				else
					deathEffect:Destroy()
				end
			end
		end
	end

	DebugController.RemoveEnemyCount()

	if instanceId then
		EnemiesPosition[instanceId] = nil
		EnemiesLastUpdate[instanceId] = nil
		TelegraphController.CancelTelegraphByEnemyInstanceId(instanceId)
		DebuffsController.CleanupEnemy(instanceId)
		EnemyWorldRef:Nuke(instanceId, entity)
	else
		EnemyWorld:delete(entity)
	end
end

local function RemoveEnemy(entity: jecs.Entity<any>)
	debug.profilebegin("RemoveEnemy")
	local enemyData = EnemyWorld:get(entity, Components.Data) :: TData.TEnemy
	local walkAnim = EnemyWorld:get(entity, Components.WalkAnimation)
	local model = EnemyWorld:get(entity, Components.Model)
	local deathEffect = EnemyWorld:get(entity, Components.DeathEffect)
	local instanceId = EnemyWorld:get(entity, Components.InstanceId)
	local eliteTier = EnemyWorld:get(entity, Components.EliteTier) :: number?
	removeEntityInternal(entity, enemyData, walkAnim, model, deathEffect, instanceId, eliteTier)
	debug.profileend()
end

-- Lazily-created pools for the regular enemy model and its death-effect attachment.
-- These are also called from the EnemyTypesForRun prewarm path before the first wave
-- so the pool clones/uploads happen during the pre-wave window instead of mid-run.
local function ensureEnemyPool(dataId: number, enemyData: TData.TEnemy): ObjectPooler.ObjectPoolerAPI<any>
	local pool = EnemyPools[dataId]
	if not pool then
		pool = ObjectPooler.new(enemyData.Model, 60, 5, ObjectPooler.ReturnBoneTransform, EnemiesFolder)
		EnemyPools[dataId] = pool
	end
	return pool
end

local function ensureDeathPool(dataId: number, enemyData: TData.TEnemy): ObjectPooler.ObjectPoolerAPI<any>
	local pool = EnemyDeathPools[dataId]
	if not pool then
		pool = ObjectPooler.new(enemyData.DeathEffect, 60, 5, ObjectPooler.ReturnCF, Workspace.Temporal)
		EnemyDeathPools[dataId] = pool
	end
	return pool
end

local function ensureElitePool(
	dataId: number,
	enemyData: TData.TEnemy,
	eliteTier: number
): ObjectPooler.ObjectPoolerAPI<any>
	local poolKey = getElitePoolKey(dataId, eliteTier)
	local pool = EliteEnemyPools[poolKey]
	if not pool then
		local tierData = EnemiesCore.ELITE_TIERS[eliteTier]
		-- Pre-scaled, pre-colored template for this enemy+tier combo. Only one
		-- template per combo - all clones share these baked visuals.
		local template = enemyData.Model:Clone() :: Model
		template:ScaleTo(template:GetScale() * tierData.Scale);
		(template.PrimaryPart.Texture :: SurfaceAppearance).Color = tierData.TextureColor
		pool = ObjectPooler.new(
			template,
			tierData.PoolInitial,
			tierData.PoolRepoblate,
			ObjectPooler.ReturnBoneTransform,
			EnemiesFolder
		)
		EliteEnemyPools[poolKey] = pool
		elitePoolKeyToDataId[poolKey] = dataId
	end
	return pool
end

local function AddEnemy(
	instanceId: number,
	dataId: number,
	position: Vector3,
	eliteTier: number?,
	isForcedElite: boolean?
)
	debug.profilebegin("AddEnemy")
	local enemyData = DataCore.GetData(dataId) :: TData.TEnemy
	if not enemyData then
		debug.profileend()
		return
	end

	local stale = EnemyWorldRef:Search(instanceId)
	if stale then RemoveEnemy(stale) end

	-- Pre-populate so the first Update call targets the correct position even if
	-- the position-packer packet hasn't arrived yet (avoids a 1-frame backward lerp).
	EnemiesPosition[instanceId] = position
	EnemiesLastUpdate[instanceId] = TimeCore.EnemyClock
	freshlyAdded[instanceId] = true

	local deathPool = ensureDeathPool(dataId, enemyData)

	local model: any
	if eliteTier then
		model = ensureElitePool(dataId, enemyData, eliteTier):Get()
	else
		model = ensureEnemyPool(dataId, enemyData):Get()
	end

	local deathEffect = deathPool:Get()
	local entity = EnemyWorldRef:EntityRef(instanceId, instanceId)
	DebugController.AddEnemyCount()

	if eliteTier then EnemyWorld:set(entity, Components.EliteTier, eliteTier) end
	-- Forced elites (Onslaught) keep their elite tier for stats / visuals but are
	-- tagged so the soul-gain path below grants them base souls only, mirroring the
	-- server's bonus exclusion so the HUD count doesn't drift above the real total.
	if isForcedElite then EnemyWorld:add(entity, Tags.ForcedElite) end

	local size = model:GetExtentsSize()
	local radius = max(size.X, size.Z) / 1.6
	local animator = model.AnimationController.Animator

	local walkAnimation = ModelToWalkTrack[model]
	if not walkAnimation then
		walkAnimation = animator:LoadAnimation(enemyData.WalkAnimation)
		ModelToWalkTrack[model] = walkAnimation
	end
	walkAnimation:Play()

	jecs.bulk_insert(EnemyWorld, entity, {
		Components.CFrame,
		Components.Bone,
		Components.InstanceId,
		Components.WalkAnimation,
		Components.Model,
		Components.Data,
		Components.Radius,
		Components.DeathEffect,
		Tags.Enemy,
	}, {
		CFrame.new(position.X, position.Y, position.Z),
		(model.PrimaryPart :: any).Root,
		instanceId,
		walkAnimation,
		model,
		enemyData,
		radius,
		deathEffect,
	})

	DebuffsController.ApplyEnemyColor(instanceId)
	debug.profileend()
end

local function DamageEnemy(characterInstanceId: number, entityInstanceId: number, damage: number, crits: number?)
	local enemyEntity = EnemyWorldRef:Search(entityInstanceId)
	if not enemyEntity then return end

	local cf = EnemyWorld:get(enemyEntity, Components.CFrame) :: CFrame
	if cf.Position.X == FAR_AWAY_X then return end

	FloatingNumbers.Add(
		cf.Position,
		damage,
		if crits and crits > 0 then FloatingNumbers.ENumberType.Crit else FloatingNumbers.ENumberType.DamageEnemy,
		crits
	)

	local now = os.clock()
	local lastHit = EnemyWorld:get(enemyEntity, Components.LastHitEffectTime) :: number?
	if lastHit and now - lastHit < HIT_EFFECT_DEBOUNCE then return end
	EnemyWorld:set(enemyEntity, Components.LastHitEffectTime, now)

	local radius = EnemyWorld:get(enemyEntity, Components.Radius) :: number

	if particlesEnabled then
		local effect = HitEffectsPool:Get()
		local rx = (random() - 0.5) * HIT_SPREAD
		local ry = (random() - 0.5) * HIT_SPREAD + 2
		local rz = (random() - 0.5) * HIT_SPREAD
		effect.CFrame = cf * CFrame.new(rx, ry, rz)
		effect.Hit.ZOffset = radius
		ParticleHelper.Emit(effect.Hit, 1)
		task.delay(effect.Hit.Lifetime.Max, HitEffectsPool.Return, HitEffectsPool, effect)
	end

	SoundsCore.PlayPooled(hitSoundPool, cf.Position)
end

local function KillEnemy(characterInstanceId: number, entityInstanceId: number, damage: number, crits: number?): ()
	debug.profilebegin("KillEnemy")
	local enemyEntity = EnemyWorldRef:Search(entityInstanceId)
	if not enemyEntity then
		debug.profileend()
		return
	end

	local cf = EnemyWorld:get(enemyEntity, Components.CFrame) :: CFrame?
	if not cf then
		debug.profileend()
		return
	end
	local enemyData = EnemyWorld:get(enemyEntity, Components.Data) :: TData.TEnemy
	local deathEffect = EnemyWorld:get(enemyEntity, Components.DeathEffect) :: TData.TDeathEffect
	local walkAnim = EnemyWorld:get(enemyEntity, Components.WalkAnimation)
	local model = EnemyWorld:get(enemyEntity, Components.Model)
	local eliteTier = EnemyWorld:get(enemyEntity, Components.EliteTier) :: number?

	local isNotFar = cf.Position.X ~= FAR_AWAY_X

	if isNotFar then
		if particlesEnabled then
			local rx = (random() - 0.5) * HIT_SPREAD
			local ry = (random() - 0.5) * HIT_SPREAD + enemyData.DeathEffectYOffset
			local rz = (random() - 0.5) * HIT_SPREAD
			deathEffect.CFrame = cf * CFrame.new(rx, ry, rz)
			enemyData.EmitDeath(deathEffect :: any)

			local deathPool = EnemyDeathPools[enemyData.Id]
			if deathPool then
				task.delay(0.6, deathPool.Return, deathPool, deathEffect)
			else
				task.delay(0.6, (deathEffect :: any).Destroy, deathEffect)
			end
		else
			local deathPool = EnemyDeathPools[enemyData.Id]
			if deathPool then
				deathPool:Return(deathEffect)
			else
				(deathEffect :: any):Destroy()
			end
		end

		SoundsCore.PlayPooled(deathSoundPool, cf.Position, DEATH_SOUND_VOLUME_SCALE)

		local numberType = if crits and crits > 0
			then FloatingNumbers.ENumberType.Crit
			else FloatingNumbers.ENumberType.DamageEnemy
		FloatingNumbers.Add(cf.Position, damage, numberType, crits)
	else
		local deathPool = EnemyDeathPools[enemyData.Id]
		if deathPool then
			deathPool:Return(deathEffect)
		else
			(deathEffect :: any):Destroy()
		end
	end

	local localEntity = getCharacterEntityFromPlayer(Players.LocalPlayer)
	if localEntity and getCharacterEntityFromInstanceId(characterInstanceId) == localEntity then
		-- Forced elites grant no bonus souls (matches the server), keeping only their
		-- elite stats, so the tier bonus is skipped when the entity carries the tag.
		local tierData = if eliteTier and not EnemyWorld:has(enemyEntity, Tags.ForcedElite)
			then EnemiesCore.ELITE_TIERS[eliteTier]
			else nil
		local baseSouls = if tierData then 1 + tierData.SoulReward else 1
		local streakMul = StreakCore.GetSoulMultiplier(World:get(localEntity, Components.AbilityStreak) or 0)
		local soulsGainMul = PassivesCore.GetPassiveStatWithData(localEntity, SoulsGain)
		StatsController.AddKills(1)
		StatsController.AddSouls(floor(baseSouls * streakMul * soulsGainMul))
		EnemiesController.OnLocalKill:Fire(1)
	end

	if enemyData then EnemiesController.OnEnemyKilled:Fire(enemyData.Id) end

	-- deathEffect is nil because we just handed it off to the death pool above.
	removeEntityInternal(enemyEntity, enemyData, walkAnim, model, nil, entityInstanceId, eliteTier)
	debug.profileend()
end

local ServerNetworkEnemies = Network.Server.Enemies
ServerNetworkEnemies.Added.On(AddEnemy)
ServerNetworkEnemies.Removed.On(function(instanceId: number)
	local enemyEntity = EnemyWorldRef:Search(instanceId)
	if not enemyEntity then return end
	RemoveEnemy(enemyEntity)
end)
ServerNetworkEnemies.Killed.On(KillEnemy)
ServerNetworkEnemies.KilledMultiple.On(
	function(characterInstanceId: number, entityInstanceIds: { number }, damage: number, crits: number?)
		local count = #entityInstanceIds
		if count == 0 then return end

		local localEntity = getCharacterEntityFromPlayer(Players.LocalPlayer)
		local isLocalPlayer = localEntity ~= nil
			and getCharacterEntityFromInstanceId(characterInstanceId) == localEntity
		if isLocalPlayer then
			local bonusSouls = 0
			for i = 1, count do
				local entity = EnemyWorldRef:Search(entityInstanceIds[i])
				if entity then
					local tier = EnemyWorld:get(entity, Components.EliteTier) :: number?
					-- Forced elites grant no bonus souls (matches the server), so
					-- only naturally-rolled elite tiers add their SoulReward.
					if tier and not EnemyWorld:has(entity, Tags.ForcedElite) then
						bonusSouls += EnemiesCore.ELITE_TIERS[tier].SoulReward
					end
				end
			end
			local baseSouls = count + bonusSouls
			local streakMul = StreakCore.GetSoulMultiplier(World:get(localEntity, Components.AbilityStreak) or 0)
			local soulsGainMul = PassivesCore.GetPassiveStatWithData(localEntity, SoulsGain)
			StatsController.AddKills(count)
			StatsController.AddSouls(floor(baseSouls * streakMul * soulsGainMul))
			EnemiesController.OnLocalKill:Fire(count)
		end

		debug.profilebegin("Kill Multiple")
		local toReturn: { [ObjectPooler.ObjectPoolerAPI<TData.TDeathEffect>]: { TData.TDeathEffect } } = {}
		local closestDistSq = math.huge
		local closestPos: Vector3? = nil
		local discoveredIds: { [number]: true } = {}

		for i = 1, count do
			local entityInstanceId = entityInstanceIds[i]
			local enemyEntity = EnemyWorldRef:Search(entityInstanceId)
			if not enemyEntity then continue end

			local cf = EnemyWorld:get(enemyEntity, Components.CFrame) :: CFrame?
			if not cf then continue end
			local enemyData = EnemyWorld:get(enemyEntity, Components.Data) :: TData.TEnemy
			local deathEffect = EnemyWorld:get(enemyEntity, Components.DeathEffect) :: TData.TDeathEffect
			local walkAnim = EnemyWorld:get(enemyEntity, Components.WalkAnimation)
			local model = EnemyWorld:get(enemyEntity, Components.Model)
			local eliteTier = EnemyWorld:get(enemyEntity, Components.EliteTier) :: number?
			if enemyData then discoveredIds[enemyData.Id] = true end

			local pos = cf.Position
			local dx = pos.X - cameraPosX
			local dy = pos.Y - cameraPosY
			local dz = pos.Z - cameraPosZ
			local distSq = dx * dx + dy * dy + dz * dz
			if distSq < closestDistSq then
				closestDistSq = distSq
				closestPos = pos
			end

			local deathPool = EnemyDeathPools[enemyData.Id]
			if pos.X ~= FAR_AWAY_X then
				if particlesEnabled then
					local rx = (random() - 0.5) * HIT_SPREAD
					local ry = (random() - 0.5) * HIT_SPREAD + enemyData.DeathEffectYOffset
					local rz = (random() - 0.5) * HIT_SPREAD
					deathEffect.CFrame = cf * CFrame.new(rx, ry, rz)
					enemyData.EmitDeath(deathEffect)

					if deathPool then
						local effects = toReturn[deathPool]
						if not effects then
							effects = table.create(count)
							toReturn[deathPool] = effects
						end
						effects[#effects + 1] = deathEffect
					else
						task.delay(0.6, (deathEffect :: any).Destroy, deathEffect)
					end
				else
					if deathPool then
						deathPool:Return(deathEffect)
					else
						(deathEffect :: any):Destroy()
					end
				end

				local numberType = if crits and crits > 0
					then FloatingNumbers.ENumberType.Crit
					else FloatingNumbers.ENumberType.DamageEnemy
				FloatingNumbers.Add(pos, damage, numberType, crits)
			else
				if deathPool then
					deathPool:Return(deathEffect)
				else
					(deathEffect :: any):Destroy()
				end
			end

			removeEntityInternal(enemyEntity, enemyData, walkAnim, model, nil, entityInstanceId, eliteTier)
		end

		for dataId in discoveredIds do
			EnemiesController.OnEnemyKilled:Fire(dataId)
		end

		if closestPos then SoundsCore.PlayPooled(deathSoundPool, closestPos, DEATH_SOUND_VOLUME_SCALE) end

		task.delay(0.6, function()
			for pool, effects in toReturn do
				for i = 1, #effects do
					pool:Return(effects[i])
				end
			end
		end)

		debug.profileend()
	end
)
ServerNetworkEnemies.Damaged.On(DamageEnemy)
ServerNetworkEnemies.DamagedMultiple.On(
	function(characterInstanceId: number, entityInstanceIds: { number }, damage: number, crits: number?)
		debug.profilebegin("Damage Multiple")
		local now = os.clock()
		local closestDistSq = math.huge
		local closestPos: Vector3? = nil
		local numberType = if crits and crits > 0
			then FloatingNumbers.ENumberType.Crit
			else FloatingNumbers.ENumberType.DamageEnemy
		local hitLifetime = HitEffect.Hit.Lifetime.Max

		for i = 1, #entityInstanceIds do
			local enemyEntity = EnemyWorldRef:Search(entityInstanceIds[i])
			if not enemyEntity then continue end

			local cf = EnemyWorld:get(enemyEntity, Components.CFrame) :: CFrame?
			if not cf then continue end
			local pos = cf.Position
			if pos.X == FAR_AWAY_X then continue end

			FloatingNumbers.Add(pos, damage, numberType, crits)

			local lastHit = EnemyWorld:get(enemyEntity, Components.LastHitEffectTime) :: number?
			if lastHit and now - lastHit < HIT_EFFECT_DEBOUNCE then continue end
			EnemyWorld:set(enemyEntity, Components.LastHitEffectTime, now)

			local dx = pos.X - cameraPosX
			local dy = pos.Y - cameraPosY
			local dz = pos.Z - cameraPosZ
			local distSq = dx * dx + dy * dy + dz * dz
			if distSq < closestDistSq then
				closestDistSq = distSq
				closestPos = pos
			end

			if particlesEnabled then
				local effect = HitEffectsPool:Get()
				local rx = (random() - 0.5) * HIT_SPREAD
				local ry = (random() - 0.5) * HIT_SPREAD + 2
				local rz = (random() - 0.5) * HIT_SPREAD
				effect.CFrame = cf * CFrame.new(rx, ry, rz)
				effect.Hit.ZOffset = EnemyWorld:get(enemyEntity, Components.Radius) :: number
				ParticleHelper.Emit(effect.Hit, 1)
				task.delay(hitLifetime, HitEffectsPool.Return, HitEffectsPool, effect)
			end
		end

		if closestPos then SoundsCore.PlayPooled(hitSoundPool, closestPos) end
		debug.profileend()
	end
)

local UpdateEnemiesEvent = ReplicatedStorage.Events.UpdateEnemies

local function yaw(entity: jecs.Entity<any>, currentPos: Vector3, targetPos: Vector3): number
	local dx = targetPos.X - currentPos.X
	local dz = targetPos.Z - currentPos.Z
	if dx * dx + dz * dz > 0.01 then
		local y = atan2(dx, dz)
		EnemyWorld:set(entity, Components.Yaw, y)
		return y
	end
	return EnemyWorld:get(entity, Components.Yaw) or 0
end

local function getViewThreshold()
	return cos(rad(Camera.DiagonalFieldOfView) / 2)
end

local cameraLookX, cameraLookY, cameraLookZ = 0, 0, 0

local function isVisible(position: Vector3)
	local vx = position.X - cameraPosX
	local vy = position.Y - cameraPosY
	local vz = position.Z - cameraPosZ
	local distSq = vx * vx + vy * vy + vz * vz
	if distSq > RENDER_DISTANCE_SQ then return false end
	local dot = vx * cameraLookX + vy * cameraLookY + vz * cameraLookZ
	if dot <= 0 then return false end
	return dot * dot > thresholdSq * distSq
end

local enemyTimeScale = TimeCore.TimeScale * TimeCore.EnemyTimeScale

local function onTimeScaleChanged()
	enemyTimeScale = TimeCore.TimeScale * TimeCore.EnemyTimeScale
	-- When effectively paused, Stop (not just AdjustSpeed(0)) - a stopped track
	-- lets the Animator skip writing bone.Transform entirely, so our last Update
	-- values persist naturally without needing a per-frame counter-write loop.
	-- Update will Play them again on resume via its shouldAnimate branch.
	if enemyTimeScale <= 0.01 then
		for _, _, walkAnim in EnemiesQuery do
			if walkAnim.IsPlaying then walkAnim:Stop(0) end
		end
	else
		for _, _, walkAnim in EnemiesQuery do
			if walkAnim.IsPlaying then walkAnim:AdjustSpeed(enemyTimeScale) end
		end
	end
end

TimeCore.OnTimeScaleChange:Connect(onTimeScaleChanged)
TimeCore.OnManualPauseChange:Connect(onTimeScaleChanged)

local auditUpdate = { lastMs = 0, calls = 0 }
EnemiesController.AuditUpdate = auditUpdate

local function Update(dt: number)
	local auditStarted = os.clock()
	debug.profilebegin("ClientUpdate")

	local lerpAlpha = 1 - exp(-TimeCore.GetEnemyDeltaTime(TimeCore.RENDER_DT) * dt)
	cameraCF = Camera.CFrame
	cameraLookVector = cameraCF.LookVector
	threshold = getViewThreshold()
	thresholdSq = threshold * threshold
	local camPos = cameraCF.Position
	cameraPosX, cameraPosY, cameraPosZ = camPos.X, camPos.Y, camPos.Z
	local lookVec = cameraLookVector
	cameraLookX, cameraLookY, cameraLookZ = lookVec.X, lookVec.Y, lookVec.Z
	local staleBefore = TimeCore.EnemyClock - STALE_TIME

	for entity, cf, walkAnim, bone, instanceId, enemyData in EnemiesQuery do
		local targetPos = EnemiesPosition[instanceId]
		if not targetPos then continue end

		local isFar = cf.Position.X == FAR_AWAY_X
		local lastUpdate = EnemiesLastUpdate[instanceId]
		local isStale = lastUpdate == nil or lastUpdate < staleBefore

		if isStale or not isVisible(targetPos) then
			if isFar then continue end
			debug.profilebegin("EnemyInvisible")
			if walkAnim.IsPlaying then walkAnim:Stop(0) end
			bone.Transform = FAR_AWAY_CFRAME
			EnemyWorld:set(entity, Components.CFrame, FAR_AWAY_CFRAME)
			debug.profileend()
			continue
		end

		debug.profilebegin("EnemyVisible")
		local targetYaw = yaw(entity, cf.Position, targetPos)

		local forward, up
		if enemyData.CanFly then
			local dx = targetPos.X - cf.Position.X
			local dy = targetPos.Y - cf.Position.Y
			local dz = targetPos.Z - cf.Position.Z
			local horizDist = (dx * dx + dz * dz) ^ 0.5
			local targetPitch = atan2(dy, horizDist)
			local prevPitch = EnemyWorld:get(entity, Components.Pitch) or 0
			local pitch = prevPitch + (targetPitch - prevPitch) * lerpAlpha
			EnemyWorld:set(entity, Components.Pitch, pitch)

			local cp = cos(pitch)
			local sp = sin(pitch)
			forward = Vector3.new(-sin(targetYaw) * cp, -sp, -cos(targetYaw) * cp)
			up = V3_YAXIS
		else
			local groundNormal = V3_YAXIS
			local cell = GeneratorCore.Grid:GetCellFromWorldPos3(targetPos)
			if cell and cell.IsSlope and targetPos.Y < cell.Height + GeneratorCore.CELL_SIZE then
				groundNormal = GeneratorCore.CardinalToSlopeNormal[cell.SlopeCardinal :: number] or V3_YAXIS
			end

			local forwardFlat = Vector3.new(-sin(targetYaw), 0, -cos(targetYaw))
			forward = (forwardFlat - (forwardFlat:Dot(groundNormal)) * groundNormal).Unit
			up = groundNormal
		end
		local right = forward:Cross(up).Unit

		local target = CFrame.fromMatrix(targetPos, right, up, -forward)
		if isFar then
			cf = target
		else
			local dx = targetPos.X - cf.Position.X
			local dy = targetPos.Y - cf.Position.Y
			local dz = targetPos.Z - cf.Position.Z
			if dx * dx + dy * dy + dz * dz > SNAP_DISTANCE_SQ then
				cf = target
			else
				cf = cf:Lerp(target, lerpAlpha)
			end
		end

		EnemyWorld:set(entity, Components.CFrame, cf)

		local dxc = cf.Position.X - cameraPosX
		local dyc = cf.Position.Y - cameraPosY
		local dzc = cf.Position.Z - cameraPosZ
		local shouldAnimate = dxc * dxc + dyc * dyc + dzc * dzc <= ANIMATION_DISTANCE_SQ

		if walkAnim.IsPlaying then
			if not shouldAnimate then walkAnim:Stop(0) end
		else
			if shouldAnimate then
				walkAnim:Play(0)
				walkAnim:AdjustSpeed(enemyTimeScale)
			end
		end

		bone.Transform = cf
		debug.profileend()
	end

	debug.profileend()
	auditUpdate.lastMs = (os.clock() - auditStarted) * 1000
	auditUpdate.calls += 1
end

UpdateEnemiesEvent.OnClientEvent:ConnectParallel(function(packed)
	debug.profilebegin("EnemyPackerUnpack")
	EnemyPacker.UnpackInto(packed, EnemiesPosition, freshlyAdded, EnemiesLastUpdate, TimeCore.EnemyClock)
	table.clear(freshlyAdded)
	debug.profileend()
end)

local poolDrainTimer = 0

local function isModelAtFarAway(item: any): boolean
	return item.PrimaryPart.Root.Transform.Position.X == FAR_AWAY_X
end

local function isAttachmentAtFarAway(item: any): boolean
	return item.CFrame.Position.X == FAR_AWAY_X
end

local function drainRetiredPools()
	debug.profilebegin("DrainRetiredPools")
	local toRemoveEnemy: { number }? = nil
	local toRemoveDeath: { number }? = nil
	local toRemoveElite: { number }? = nil

	for dataId, pool in EnemyPools do
		if not retiredDataIds[dataId] then continue end
		local item = pool.Pool[#pool.Pool]
		if item then
			if isModelAtFarAway(item) then
				pool.Pool[#pool.Pool] = nil
				item:Destroy()
			end
		else
			if not toRemoveEnemy then toRemoveEnemy = {} end
			toRemoveEnemy[#toRemoveEnemy + 1] = dataId
		end
	end

	for dataId, pool in EnemyDeathPools do
		if not retiredDataIds[dataId] then continue end
		local item = pool.Pool[#pool.Pool]
		if item then
			if isAttachmentAtFarAway(item) then
				pool.Pool[#pool.Pool] = nil
				item:Destroy()
			end
		else
			if not toRemoveDeath then toRemoveDeath = {} end
			toRemoveDeath[#toRemoveDeath + 1] = dataId
		end
	end

	for poolKey, pool in EliteEnemyPools do
		local dataId = elitePoolKeyToDataId[poolKey]
		if not dataId or not retiredDataIds[dataId] then continue end
		local item = pool.Pool[#pool.Pool]
		if item then
			if isModelAtFarAway(item) then
				pool.Pool[#pool.Pool] = nil
				item:Destroy()
			end
		else
			if not toRemoveElite then toRemoveElite = {} end
			toRemoveElite[#toRemoveElite + 1] = poolKey
		end
	end

	if toRemoveEnemy then
		for i = 1, #toRemoveEnemy do
			EnemyPools[toRemoveEnemy[i]] = nil
		end
	end
	if toRemoveDeath then
		for i = 1, #toRemoveDeath do
			EnemyDeathPools[toRemoveDeath[i]] = nil
		end
	end
	if toRemoveElite then
		for i = 1, #toRemoveElite do
			local poolKey = toRemoveElite[i]
			elitePoolKeyToDataId[poolKey] = nil
			EliteEnemyPools[poolKey] = nil
		end
	end
	debug.profileend()
end

RunService.PreSimulation:Connect(function(dt)
	if TimeCore.IsPaused then
		-- Animator keeps writing the frozen walk pose to bone.Transform during
		-- pause, which pulls enemies back to the model origin. Re-assert the
		-- last-known CFrame every frame so they stay put.
		debug.profilebegin("PausedEnemies")
		for _, cf, _, bone in EnemiesQuery do
			bone.Transform = cf
		end
		debug.profileend()
		return
	end
	Update(dt)

	poolDrainTimer += dt
	if poolDrainTimer >= 1 then
		poolDrainTimer = 0
		drainRetiredPools()
	end
end)

ServerNetworkEnemies.EnemyTypeRetired.On(function(dataId: number)
	retiredDataIds[dataId] = true
end)

-- Pre-warm enemy / death / elite pools for every type that may spawn this run, so the
-- model cloning + texture/scale baking + FastCluster uploads happen before the first
-- wave instead of mid-fight. Elite pools are created for all 3 tiers per type with
-- tier-weighted sizes (5/3/2) since Vanguard spawns ~14× more often than Overlord.
--
-- Onslaught forces every server-side spawn into an elite, so the normal-enemy
-- pool would never be drawn from. Skip ensureEnemyPool when Onslaught is active
-- to keep memory down on lower-end devices - relies on ModifiersForRun having
-- arrived before EnemyTypesForRun, which GameplayService guarantees by firing
-- the modifier broadcast first.
ServerNetworkEnemies.EnemyTypesForRun.On(function(dataIds: { number })
	local skipNormalPool = ModifiersController.IsActive("Onslaught")
	for i = 1, #dataIds do
		local dataId = dataIds[i]
		local enemyData = DataCore.GetData(dataId) :: TData.TEnemy
		if not enemyData then continue end

		if not skipNormalPool then ensureEnemyPool(dataId, enemyData) end
		ensureDeathPool(dataId, enemyData)
		for tier = 1, #EnemiesCore.ELITE_TIERS do
			ensureElitePool(dataId, enemyData, tier)
		end
	end
end)

ServerNetworkEnemies.Telegraph.On(function(enemyInstanceId: number)
	local enemyEntity = EnemyWorldRef:Search(enemyInstanceId)
	if not enemyEntity then return end

	local data = EnemyWorld:get(enemyEntity, Components.Data) :: TData.TEnemy
	local cf = EnemyWorld:get(enemyEntity, Components.CFrame) :: CFrame

	if data and cf and data.ExplosionRadius and data.ExplosionTime then
		-- Update the bone position because CFrame might lag behind for telegraph
		local bone = EnemyWorld:get(enemyEntity, Components.Bone)
		local position = EnemiesPosition[enemyInstanceId]

		if not position then position = if bone then bone.Transform.Position else cf.Position end

		TelegraphController.CreateSphereTelegraph(position, data.ExplosionRadius, data.ExplosionTime, enemyInstanceId)
	end
end)

EnemiesController.OnGameRestarting = function()
	-- Remove all active enemies (returns models to pools)
	local enemiesToRemove = {}
	for enemyEntity in EnemyWorld:query(Tags.Enemy) do
		enemiesToRemove[#enemiesToRemove + 1] = enemyEntity
	end
	for i = 1, #enemiesToRemove do
		RemoveEnemy(enemiesToRemove[i])
	end

	table.clear(EnemiesPosition)
	table.clear(EnemiesLastUpdate)
	table.clear(freshlyAdded)
	table.clear(retiredDataIds)

	for _, pool in EnemyPools do
		pool:Purge()
	end
	for _, pool in EliteEnemyPools do
		pool:Purge()
	end
	for _, pool in EnemyDeathPools do
		pool:Purge()
	end
	HitEffectsPool:Purge()
	table.clear(EnemyPools)
	table.clear(EliteEnemyPools)
	table.clear(EnemyDeathPools)
	table.clear(elitePoolKeyToDataId)
	table.clear(ModelToWalkTrack)
end

return Ignis.Register(EnemiesController)

