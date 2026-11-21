-- Drives the crowd: every TimeCore.FIXED_DT it tells NavService where the characters stand, runs enemiesUpdate over
-- the whole crowd, and streams each player the positions inside his camera.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local Network = require(ServerScriptService.GlobalServer.Network)
local AOIService = require(script.Parent.AOIService)
local CharacterService = require(script.Parent.CharacterService)
local DefenseService = require(script.Parent.DefenseService)
local EnemiesService = require(script.Parent.EnemiesService)
local EnemyAttacksService = require(script.Parent.EnemyAttacksService)
local NavService = require(script.Parent.NavService)
local enemiesUpdate = require(ServerScriptService.Server.Utils.enemiesUpdate)
local CharacterCore = require(ReplicatedStorage.GlobalShared.Core.CharacterCore)
local ArenaCore = require(ReplicatedStorage.Shared.Core.ArenaCore)
local EnemiesCore = require(ReplicatedStorage.Shared.Core.EnemiesCore)
local TimeCore = require(ReplicatedStorage.Shared.Core.TimeCore)
local EnemyPacker = require(ReplicatedStorage.Shared.Packers.EnemyPacker)
local Components = require(ReplicatedStorage.GlobalShared.ECS.Components)
local Tags = require(ReplicatedStorage.GlobalShared.ECS.Tags)
local EnemyWorld = require(ReplicatedStorage.GlobalShared.ECS.Worlds.EnemyWorld)
local World = require(ReplicatedStorage.GlobalShared.ECS.Worlds.World)
local getCharacterFeet = require(ReplicatedStorage.GlobalShared.Utils.Functions.getCharacterFeet)
local TData = require(ReplicatedStorage.Types.TData)

local ServerNetworkEnemies = Network.Server.Enemies

-- The order here is the order enemiesUpdate destructures. Immunity is not in it: a fresh body walks.
local WalkQuery = EnemyWorld:query(
	Components.Position,
	Components.Velocity,
	Components.Force,
	Components.Radius,
	Components.HalfExtents,
	Components.Mass,
	Components.AttackWindup,
	Components.AttackCount,
	Components.MovementSpeed,
	Components.Yaw,
	Components.InstanceId,
	Components.Data
)
	:with(Tags.Enemy)
	:cached()

local FrozenQuery =
	EnemyWorld:query(Components.InstanceId, Components.Position, Components.Yaw):with(Tags.Enemy):cached()

-- Only a character every client knows (it has its InstanceId) and that is alive can be a target.
local CharactersQuery = World:query(Components.HumanoidRootPart, Components.Humanoid, Components.InstanceId)
	:with(Tags.Character, Tags.Alive)
	:cached()

-- Targets are led by this much of their velocity, so a crowd meets a runner ahead.
local TARGET_LEAD_SECONDS = 1 / 6
-- A shove is spent a tick at a time: this share of what is left, until under PUSH_REST studs are. Counted in ticks,
-- not seconds, so a shove travels the same distance wherever in a tick it lands.
local PUSH_SHARE = 0.5
local PUSH_REST = 0.25

local EnemyMovementService = {}

-- Off between runs, so a cleared arena does nothing at all.
EnemyMovementService.IsRunning = false

-- The studs each shoved body still has to travel, for a Mass of 1.
local pushes: { [any]: vector } = {}
local aggroCounts: { [number]: number } = {}
local tick: enemiesUpdate.TTick = {
	Dt = TimeCore.FIXED_DT,
	CharacterFeet = {},
	BarricadeIds = {},
	BarricadeCenters = {},
	BarricadeHalves = {},
	BarricadeCount = 0,
	-- The live list: EnemyAttacksService keeps it current between ticks.
	Warnings = EnemyAttacksService.GetWarnings(),
	OutIds = table.create(EnemiesCore.MAX_ALIVE),
	OutPositions = table.create(EnemiesCore.MAX_ALIVE),
	OutYaws = table.create(EnemiesCore.MAX_ALIVE),
	OnAttackStarted = function(enemy: any, attackIndex: number, attack: TData.TEnemyAttack, center: vector, _)
		if EnemyWorld:contains(enemy) then EnemyAttacksService.Start(enemy, attackIndex, attack, center) end
	end,
	OnSwingLanded = function(enemy: any, targetId: number, damageScale: number)
		if not EnemyWorld:contains(enemy) then return end
		local damage = (EnemyWorld:get(enemy, Components.Damage) or 0) * damageScale
		if targetId < 0 then
			DefenseService.Damage(-targetId, damage)
			return
		end

		local characterEntity = CharacterCore.GetCharacterByInstanceId(targetId)
		if characterEntity then CharacterService.Damage(characterEntity, damage) end
	end,
	OnFellOut = function(enemy: any)
		if EnemyWorld:contains(enemy) then EnemiesService.Remove(enemy, true) end
	end,
}
-- Reset to 0 after each step rather than carrying the remainder: carrying it raises the effective rate ~17% and
-- changes movement pace, for no frame-time gain (performance/audit-2026-10-21/REPORT.md).
local accumulator = 0

-- Shoves `enemyEntities` `studs` across the floor along `direction` over the next few ticks, most of it in the first.
-- The movement update divides it by Mass, so a heavy body gives less ground, and refuses any step off its floor. A
-- boss stands its ground.
function EnemyMovementService.Push(enemyEntities: { any }, direction: Vector3, studs: number)
	local flat = vector.create(direction.X, 0, direction.Z)
	local length = vector.magnitude(flat)
	if length < 1e-3 or studs <= 0 then return end

	local shove = flat * (studs / length)
	for _, enemyEntity in enemyEntities do
		if not EnemyWorld:contains(enemyEntity) or EnemyWorld:has(enemyEntity, Tags.Boss) then continue end
		pushes[enemyEntity] = (pushes[enemyEntity] or vector.zero) + shove
	end
end

-- This tick's part of every shove, written as the Force the movement update reads (a velocity, for a Mass of 1).
local function applyPushes()
	for enemyEntity, left in pushes do
		if not EnemyWorld:contains(enemyEntity) then
			pushes[enemyEntity] = nil
			continue
		end

		if vector.magnitude(left) < PUSH_REST then
			pushes[enemyEntity] = nil
			EnemyWorld:set(enemyEntity, Components.Force, vector.zero)
			continue
		end

		local step = left * PUSH_SHARE
		pushes[enemyEntity] = left - step
		EnemyWorld:set(enemyEntity, Components.Force, step / tick.Dt)
	end
end

local function stream(count: number)
	if count == 0 then return end

	for player, state in AOIService.PlayerStates do
		local packet = EnemyPacker.PackFiltered(
			tick.OutIds,
			tick.OutPositions,
			tick.OutYaws,
			count,
			state.camX,
			state.camY,
			state.camZ,
			state.lookX,
			state.lookY,
			state.lookZ,
			state.thresholdSq,
			state.renderDistanceSq
		)
		if packet then ServerNetworkEnemies.Positions.Fire(player, packet) end
	end
end

-- Frozen: nothing moves, but positions keep streaming so a camera turning back onto the crowd still finds it (the
-- client parks anything whose packets stopped).
local function streamFrozen()
	local count = 0
	for _, instanceId, position, yaw in FrozenQuery do
		count += 1
		tick.OutIds[count] = instanceId
		tick.OutPositions[count] = position
		tick.OutYaws[count] = yaw
	end

	stream(count)
end

local function gatherTargets()
	local feet = tick.CharacterFeet
	table.clear(feet)
	local nav = ArenaCore.Nav
	for _, rootPart, humanoid, characterId in CharactersQuery do
		local at = getCharacterFeet(rootPart, humanoid, TARGET_LEAD_SECONDS)
		feet[characterId] = at
		if nav then NavService.SetCharacterNode(characterId, ArenaCore.NodeAt(nav, at.x, at.y, at.z, 0.75)) end
	end

	tick.BarricadeCount = DefenseService.GetBarricades(tick.BarricadeIds, tick.BarricadeCenters, tick.BarricadeHalves)
end

RunService.Heartbeat:Connect(function(dt: number)
	if not EnemyMovementService.IsRunning or TimeCore.IsPaused then return end
	if EnemiesService.GetCount() == 0 then return end

	-- Frozen enemies accumulate raw game time so the frozen stream keeps its rate; otherwise enemy time, so a
	-- slow-motion crowd steps less often rather than taking shorter steps.
	local isFrozen = TimeCore.EnemyTimeScale <= 0
	accumulator += if isFrozen then TimeCore.GetDeltaTime(dt) else TimeCore.GetEnemyDeltaTime(dt)
	if accumulator < TimeCore.FIXED_DT then return end
	accumulator = 0

	if isFrozen then
		streamFrozen()
		return
	end

	gatherTargets()
	applyPushes()
	table.clear(aggroCounts)
	stream(enemiesUpdate(WalkQuery, tick, aggroCounts))
end)

return Ignis.Register(EnemyMovementService)
