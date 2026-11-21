-- Who has been shown which enemy, and where each player's camera is. An enemy is subscribed to a player the first time
-- it comes within his render distance and camera cone, and from then on every event about it reaches only its
-- subscribers. That is what keeps a client's Highlight count under the engine's 255 (EnemiesCore.MAX_ALIVE).
--
-- The hot paths fill caller-owned or pooled lists, so a volley of damage allocates nothing per hit.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local Network = require(ServerScriptService.GlobalServer.Network)
local EnemiesCore = require(ReplicatedStorage.Shared.Core.EnemiesCore)
local Components = require(ReplicatedStorage.GlobalShared.ECS.Components)
local EnemyWorld = require(ReplicatedStorage.GlobalShared.ECS.Worlds.EnemyWorld)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)

local cos = math.cos
local sin = math.sin

local PI = math.pi
local HALF_PI = math.pi / 2
local INV_32767 = 1 / 32767
local INV_65535 = 1 / 65535

-- Before the first CameraSync, accept everything within render distance in every direction.
local NO_FRUSTUM = -1
-- Rejects malformed packets (NaN, infinity, absurd coordinates). Far beyond any arena.
local MAX_CAM_COORD = 1e5
-- How far a player is shown enemies. An arena fits well inside it; a settings menu can lower it per player.
local RENDER_DISTANCE = 400

export type TPlayerAOIState = {
	renderDistance: number,
	renderDistanceSq: number,
	camX: number,
	camY: number,
	camZ: number,
	lookX: number,
	lookY: number,
	lookZ: number,
	-- cos^2(FOV/2), NO_FRUSTUM until the first CameraSync.
	thresholdSq: number,
	knownEnemies: { [number]: boolean },
}

local playerStates: { [Player]: TPlayerAOIState } = {}
-- Inverse index: enemy instance id -> its subscribers.
local enemySubscribers: { [number]: { [Player]: boolean } } = {}

-- Module-level state for the spatial hash callback, so the tick allocates no closure.
local tickPlayer: Player = nil :: any
local tickState: TPlayerAOIState = nil :: any
local tickOnNewlySubscribed: ((Player, number) -> ())? = nil

-- Pool of inner id lists for the per-player builders.
local listPool: { { number } } = {}
local listPoolSize = 0

local AOIService = {}

-- Read directly by EnemyMovementService each tick. Written only here.
AOIService.PlayerStates = playerStates

local function takeList(): { number }
	if listPoolSize == 0 then return {} end
	local list = listPool[listPoolSize]
	listPool[listPoolSize] = nil
	listPoolSize -= 1
	return list
end

local function isInView(state: TPlayerAOIState, x: number, y: number, z: number): boolean
	local vx = x - state.camX
	local vy = y - state.camY
	local vz = z - state.camZ
	local distSq = vx * vx + vy * vy + vz * vz
	if distSq > state.renderDistanceSq then return false end
	if state.thresholdSq < 0 or distSq < 1 then return true end
	local dot = vx * state.lookX + vy * state.lookY + vz * state.lookZ
	if dot <= 0 then return false end
	return dot * dot > state.thresholdSq * distSq
end

local function subscribe(player: Player, state: TPlayerAOIState, instanceId: number)
	state.knownEnemies[instanceId] = true
	local subs = enemySubscribers[instanceId]
	if not subs then
		subs = {}
		enemySubscribers[instanceId] = subs
	end
	subs[player] = true
end

local function tickSpatialHashCallback(enemyEntity: any)
	local instanceId = EnemyWorld:get(enemyEntity, Components.InstanceId)
	if not instanceId or tickState.knownEnemies[instanceId] then return end
	local position = EnemyWorld:get(enemyEntity, Components.Position)
	if not position or not isInView(tickState, position.x, position.y, position.z) then return end
	subscribe(tickPlayer, tickState, instanceId)
	if tickOnNewlySubscribed then tickOnNewlySubscribed(tickPlayer, instanceId) end
end

-- The player's full camera look, or nil before the first CameraSync. Abilities aim along it.
function AOIService.GetCameraLook(player: Player): Vector3?
	local state = playerStates[player]
	if not state or state.thresholdSq < 0 then return nil end
	return Vector3.new(state.lookX, state.lookY, state.lookZ)
end

function AOIService.GetCameraPosition(player: Player): Vector3?
	local state = playerStates[player]
	if not state or state.thresholdSq < 0 then return nil end
	return Vector3.new(state.camX, state.camY, state.camZ)
end

-- Every player who can see (x, y, z) now, into `out` (cleared by the caller).
function AOIService.GetVisiblePlayersInto(x: number, y: number, z: number, out: { Player }): { Player }
	for player, state in playerStates do
		if isInView(state, x, y, z) then out[#out + 1] = player end
	end

	return out
end

function AOIService.Subscribe(player: Player, instanceId: number)
	local state = playerStates[player]
	if state then subscribe(player, state, instanceId) end
end

-- Subscribes every player who has not been shown `instanceId`, wherever it is, calling `onNewlySubscribed` for each.
function AOIService.SubscribeEveryone(instanceId: number, onNewlySubscribed: (Player, number) -> ())
	for player, state in playerStates do
		if state.knownEnemies[instanceId] then continue end
		subscribe(player, state, instanceId)
		onNewlySubscribed(player, instanceId)
	end
end

-- Subscribers of `instanceId` into `out` (cleared by the caller). Leaves the subscriptions.
function AOIService.GetSubscribedPlayersInto(instanceId: number, out: { Player }): { Player }
	local subs = enemySubscribers[instanceId]
	if not subs then return out end
	for player in subs do
		out[#out + 1] = player
	end

	return out
end

-- Subscribers of `instanceId` into `out`, and drops them: for the body's last event.
function AOIService.PopSubscribedPlayersInto(instanceId: number, out: { Player }): { Player }
	local subs = enemySubscribers[instanceId]
	if not subs then return out end
	for player in subs do
		local state = playerStates[player]
		if state then state.knownEnemies[instanceId] = nil end
		out[#out + 1] = player
	end

	enemySubscribers[instanceId] = nil
	return out
end

function AOIService.OnEnemyRemoved(instanceId: number)
	local subs = enemySubscribers[instanceId]
	if not subs then return end
	for player in subs do
		local state = playerStates[player]
		if state then state.knownEnemies[instanceId] = nil end
	end

	enemySubscribers[instanceId] = nil
end

-- {player -> the ids among `instanceIds` he is subscribed to}, into `result` (empty). Release it after.
function AOIService.BuildSubscribedPerPlayerLists(instanceIds: { number }, result: { [Player]: { number } })
	for _, instanceId in instanceIds do
		local subs = enemySubscribers[instanceId]
		if not subs then continue end
		for player in subs do
			local list = result[player]
			if not list then
				list = takeList()
				result[player] = list
			end

			list[#list + 1] = instanceId
		end
	end
end

-- The same, and drops the subscriptions: for a volley of kills.
function AOIService.PopSubscribedPlayersMultiple(instanceIds: { number }, result: { [Player]: { number } })
	for _, instanceId in instanceIds do
		local subs = enemySubscribers[instanceId]
		if not subs then continue end
		for player in subs do
			local state = playerStates[player]
			if state then state.knownEnemies[instanceId] = nil end
			local list = result[player]
			if not list then
				list = takeList()
				result[player] = list
			end

			list[#list + 1] = instanceId
		end

		enemySubscribers[instanceId] = nil
	end
end

-- Empties a per-player result, returning its lists to the pool. Do not keep the inner lists.
function AOIService.ReleasePerPlayerLists(result: { [Player]: { number } })
	for player, list in result do
		table.clear(list)
		listPoolSize += 1
		listPool[listPoolSize] = list
		result[player] = nil
	end
end

-- Subscribes players to enemies that came into their view since they spawned, calling `onNewlySubscribed` for
-- each pair. Run a few times a second (EnemiesService); new spawns subscribe their viewers at spawn.
function AOIService.Tick(onNewlySubscribed: (Player, number) -> ())
	tickOnNewlySubscribed = onNewlySubscribed
	for player, state in playerStates do
		tickPlayer = player
		tickState = state
		EnemiesCore.EnemiesSpatialHash:QueryRadiusAsPoints(
			state.camX,
			state.camZ,
			state.renderDistance,
			tickSpatialHashCallback
		)
	end

	tickOnNewlySubscribed = nil
end

function AOIService.Reset()
	table.clear(enemySubscribers)
	for _, state in playerStates do
		table.clear(state.knownEnemies)
	end
end

AOIService.OnPlayerConnected = function(player: Player)
	playerStates[player] = {
		renderDistance = RENDER_DISTANCE,
		renderDistanceSq = RENDER_DISTANCE * RENDER_DISTANCE,
		camX = 0,
		camY = 0,
		camZ = 0,
		lookX = 0,
		lookY = 0,
		lookZ = 1,
		thresholdSq = NO_FRUSTUM,
		knownEnemies = {},
	}
end :: TPlayerEvents.OnPlayerConnected

AOIService.OnPlayerDisconnected = function(player: Player)
	local state = playerStates[player]
	if state then
		for instanceId in state.knownEnemies do
			local subs = enemySubscribers[instanceId]
			if subs then subs[player] = nil end
		end
	end

	playerStates[player] = nil
end :: TPlayerEvents.OnPlayerDisconnected

-- A cosmetic cull input: a lying client only hides enemies from itself, so beyond rejecting garbage there is
-- nothing to check.
Network.Client.PlayerSync.CameraSync.On(
	function(player: Player, camX: number, camY: number, camZ: number, yawQ: number, pitchQ: number, thresholdQ: number)
		local state = playerStates[player]
		if not state then return end
		if camX ~= camX or camY ~= camY or camZ ~= camZ then return end
		if math.abs(camX) > MAX_CAM_COORD or math.abs(camY) > MAX_CAM_COORD or math.abs(camZ) > MAX_CAM_COORD then
			return
		end

		local pitch = pitchQ * INV_32767 * HALF_PI
		local yaw = yawQ * INV_32767 * PI
		local cosPitch = cos(pitch)
		state.camX = camX
		state.camY = camY
		state.camZ = camZ
		state.lookX = cosPitch * sin(yaw)
		state.lookY = -sin(pitch)
		state.lookZ = -cosPitch * cos(yaw)
		local threshold = thresholdQ * INV_65535
		state.thresholdSq = threshold * threshold
	end
)

return Ignis.Register(AOIService)
