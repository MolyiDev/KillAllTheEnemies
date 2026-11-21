-- Characters in a match: their health, their network id, and when they come back.
--
-- HEALTH IS THE ECS'S. CurrentHealth / MaxHealth are the truth; the Humanoid only mirrors them, and is set to 0 only to
-- kill the rig, which is what removes Tags.Alive. Nothing else writes Humanoid.Health.
--
-- A character is registered (CharacterCore.AddCharacter) only once every client has acknowledged its InstanceId:
-- registered sooner, an enemy swing or a kill credit could name an id some client cannot map yet.
--
-- CharacterAutoLoads is off (game.project.json): this loads every rig, and a death lasts until MatchService revives.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local Signal = require(ReplicatedStorage.Packages.Signal)
local jecs = require(ReplicatedStorage.Packages.jecs)
local Network = require(ServerScriptService.GlobalServer.Network)
local loadBlockyCharacter = require(ServerScriptService.GlobalServer.Utils.loadBlockyCharacter)
local NavService = require(script.Parent.NavService)
local arenaMap = require(ServerScriptService.Server.Utils.arenaMap)
local CharacterCore = require(ReplicatedStorage.GlobalShared.Core.CharacterCore)
local TimeCore = require(ReplicatedStorage.Shared.Core.TimeCore)
local Components = require(ReplicatedStorage.GlobalShared.ECS.Components)
local Tags = require(ReplicatedStorage.GlobalShared.ECS.Tags)
local World = require(ReplicatedStorage.GlobalShared.ECS.Worlds.World)
local IdGenerator = require(ReplicatedStorage.GlobalShared.Utils.IdGenerator)
local getCharacterEntityFromPlayer =
	require(ReplicatedStorage.GlobalShared.Utils.Functions.getCharacterEntityFromPlayer)
local blockyBody = require(ReplicatedStorage.GlobalShared.Utils.blockyBody)
local getPlayerFromCharacterEntity =
	require(ReplicatedStorage.GlobalShared.Utils.Functions.getPlayerFromCharacterEntity)
local EGenerator = require(ReplicatedStorage.Types.Enums.EGenerator)
local TCharacterEvents = require(ReplicatedStorage.Types.Events.TCharacterEvents)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)

local ServerNetworkCharacters = Network.Server.Characters
local ClientNetworkCharacters = Network.Client.Characters

local CharactersFolder = Workspace:WaitForChild("Characters")

-- Ids 1..1000; 0 is reserved on the wire for "nobody" (a kill credited to no one).
local IdEntityGen = IdGenerator.new(EGenerator.CharacterEntities, 0, 1000)

local Tune = table.freeze({
	MAX_HEALTH = 100,
	-- After a hit lands, the window in which further hits are ignored. A crowd pressed against a player then
	-- costs one blow per window rather than one per body, which is what makes standing in a horde survivable
	-- for a moment and lethal for a few.
	HURT_WINDOW_SECONDS = 0.35,
	ACK_TIMEOUT_SECONDS = 5,
	-- Regeneration (GDD 18): this long after the last hit, this much a second, mirrored to clients this often.
	REGEN_DELAY_SECONDS = 4,
	REGEN_PER_SECOND = 5,
	HEALTH_SYNC_SECONDS = 0.25,
})

type TPendingAck = { remaining: number, acked: { [Player]: boolean }, signal: Signal.Signal<> }
local pendingAcks: { [number]: TPendingAck } = {}

local CharacterService = {}

-- (characterEntity, player) once the id is registered on every side: a character a match can count.
CharacterService.OnCharacterReady = Signal.new()
-- (characterEntity, player)
CharacterService.OnCharacterDied = Signal.new()

local RegenQuery = World
	:query(Components.CurrentHealth, Components.MaxHealth, Components.LastHurtAt, Components.Humanoid)
	:with(Tags.Character, Tags.Alive)
	:cached()
local healthSyncAccumulator = 0
local regenerated: { jecs.Entity<any> } = {}

local function sendHealth(characterEntity: jecs.Entity<any>)
	local instanceId = World:get(characterEntity, Components.InstanceId)
	if not instanceId then return end
	local current = World:get(characterEntity, Components.CurrentHealth) or 0
	local max = World:get(characterEntity, Components.MaxHealth) or 0
	ServerNetworkCharacters.Health.FireAll(instanceId, current, max)
end

-- Yields until the map is placed.
function CharacterService.Spawn(player: Player)
	arenaMap.WaitAsync()
	if not player.Parent then return end
	local ok, err = pcall(loadBlockyCharacter, player)
	if not ok then warn(`[CharacterService] could not load {player.Name}: {err}`) end
end

function CharacterService.IsAlive(player: Player): boolean
	local characterEntity = getCharacterEntityFromPlayer(player)
	if not characterEntity or not World:has(characterEntity, Tags.Alive) then return false end
	return (World:get(characterEntity, Components.CurrentHealth) or 0) > 0
end

-- Brings back every player without a living character. MatchService decides when.
function CharacterService.ReviveDead()
	for _, player in Players:GetPlayers() do
		if CharacterService.IsAlive(player) then continue end
		task.spawn(CharacterService.Spawn, player)
	end
end

-- Characters still standing. Reads CurrentHealth as well as Tags.Alive: the tag leaves on Humanoid.Died, which
-- under deferred signals lands after the blow that killed him, and a match-end check made in between would
-- still count him.
function CharacterService.CountAlive(): number
	local count = 0
	for _, health in World:query(Components.CurrentHealth):with(Tags.Character, Tags.Alive) do
		if health > 0 then
			count += 1
		end
	end

	return count
end

-- One blow on a character. The amount is the server's own (an enemy's Damage), never a client's.
function CharacterService.Damage(characterEntity: jecs.Entity<any>, amount: number)
	if amount <= 0 then return end
	if not World:has(characterEntity, Tags.Alive) then return end
	local now = TimeCore.GameClock
	local hurtUntil = World:get(characterEntity, Components.HurtUntil) or 0
	if now < hurtUntil then return end
	World:set(characterEntity, Components.HurtUntil, now + Tune.HURT_WINDOW_SECONDS)
	World:set(characterEntity, Components.LastHurtAt, now)

	local current = World:get(characterEntity, Components.CurrentHealth)
	if not current then return end
	current = math.max(current - amount, 0)
	World:set(characterEntity, Components.CurrentHealth, current)

	local humanoid = World:get(characterEntity, Components.Humanoid)
	if humanoid then humanoid.Health = if current > 0 then current else 0 end
	sendHealth(characterEntity)

	if current > 0 then return end
	CharacterService.OnCharacterDied:Fire(characterEntity, getPlayerFromCharacterEntity(characterEntity))
end

function CharacterService.Heal(characterEntity: jecs.Entity<any>, amount: number)
	if not World:has(characterEntity, Tags.Alive) then return end
	local current = World:get(characterEntity, Components.CurrentHealth)
	local max = World:get(characterEntity, Components.MaxHealth)
	if not current or not max then return end
	current = math.min(current + amount, max)
	World:set(characterEntity, Components.CurrentHealth, current)
	local humanoid = World:get(characterEntity, Components.Humanoid)
	if humanoid then humanoid.Health = current end
	sendHealth(characterEntity)
end

local function releaseAck(instanceId: number)
	local pending = pendingAcks[instanceId]
	if not pending then return end
	pendingAcks[instanceId] = nil
	pending.signal:Fire()
end

-- Players.CharacterAutoLoads is false in game.project.json, so it holds before the first player arrives.
CharacterService.OnPlayerConnected = function(player: Player)
	-- Late joiners learn the characters that already exist.
	for characterEntity, instanceId in World:query(Components.InstanceId):with(Tags.Character) do
		local owner = getPlayerFromCharacterEntity(characterEntity)
		if owner and owner ~= player then ServerNetworkCharacters.Added.Fire(player, owner, instanceId) end
	end

	task.spawn(CharacterService.Spawn, player)
end :: TPlayerEvents.OnPlayerConnected

CharacterService.OnPlayerDisconnected = function(player: Player)
	-- Every handshake still waiting on this player stops waiting for them.
	for instanceId, pending in pendingAcks do
		if pending.acked[player] then continue end
		pending.acked[player] = true
		pending.remaining -= 1
		if pending.remaining <= 0 then releaseAck(instanceId) end
	end
end :: TPlayerEvents.OnPlayerDisconnected

CharacterService.OnCharacterAdded = function(character, characterEntity)
	character.Parent = CharactersFolder

	local humanoid = World:get(characterEntity, Components.Humanoid)
	if humanoid then
		blockyBody.Apply(humanoid)

		-- The Humanoid never heals itself: its bar is a mirror of CurrentHealth.
		local regen = character:FindFirstChild("Health")
		if regen then regen:Destroy() end
		humanoid.MaxHealth = Tune.MAX_HEALTH
		humanoid.Health = Tune.MAX_HEALTH
	end

	World:set(characterEntity, Components.MaxHealth, Tune.MAX_HEALTH)
	World:set(characterEntity, Components.CurrentHealth, Tune.MAX_HEALTH)
	World:set(characterEntity, Components.HurtUntil, 0)
	World:set(characterEntity, Components.LastHurtAt, 0)

	task.defer(function()
		local player = getPlayerFromCharacterEntity(characterEntity)
		if not player or player.Character ~= character then return end

		local instanceId = IdEntityGen:Generate()
		while CharacterCore.GetCharacterByInstanceId(instanceId) do
			instanceId = IdEntityGen:Generate()
		end

		local players = Players:GetPlayers()
		local pending: TPendingAck = { remaining = #players, acked = {}, signal = Signal.new() }
		pendingAcks[instanceId] = pending
		ServerNetworkCharacters.Added.FireAll(player, instanceId)
		task.delay(Tune.ACK_TIMEOUT_SECONDS, releaseAck, instanceId)
		pending.signal:Wait()
		pending.signal:Destroy()

		-- The rig may have been replaced or removed while the clients answered.
		if player.Character ~= character or not World:contains(characterEntity) then return end
		CharacterCore.AddCharacter(characterEntity, instanceId)
		sendHealth(characterEntity)
		CharacterService.OnCharacterReady:Fire(characterEntity, player)
	end)
end :: TCharacterEvents.OnCharacterAdded

CharacterService.OnCharacterRemoving = function(_, characterEntity)
	local instanceId = World:get(characterEntity, Components.InstanceId)
	if not instanceId then return end
	CharacterCore.RemoveCharacter(instanceId)
	NavService.RemoveCharacter(instanceId)
	ServerNetworkCharacters.Removed.FireAll(instanceId)
end :: TCharacterEvents.OnCharacterRemoving

RunService.Heartbeat:Connect(function(dt: number)
	if TimeCore.IsPaused then return end
	local now = TimeCore.GameClock
	local step = Tune.REGEN_PER_SECOND * TimeCore.GetDeltaTime(dt)

	for characterEntity, current, max, lastHurtAt, humanoid in RegenQuery do
		if current <= 0 or current >= max or now - lastHurtAt < Tune.REGEN_DELAY_SECONDS then continue end
		current = math.min(current + step, max)
		World:set(characterEntity, Components.CurrentHealth, current)
		humanoid.Health = current
		if not table.find(regenerated, characterEntity) then table.insert(regenerated, characterEntity) end
	end

	healthSyncAccumulator += dt
	if healthSyncAccumulator < Tune.HEALTH_SYNC_SECONDS or #regenerated == 0 then return end
	healthSyncAccumulator = 0
	for _, characterEntity in regenerated do
		if World:contains(characterEntity) then sendHealth(characterEntity) end
	end

	table.clear(regenerated)
end)

-- Deduped per player, so a client spamming CharacterReady cannot count for anyone else.
ClientNetworkCharacters.CharacterReady.On(function(player: Player, instanceId: number)
	local pending = pendingAcks[instanceId]
	if not pending or pending.acked[player] then return end
	pending.acked[player] = true
	pending.remaining -= 1
	if pending.remaining <= 0 then releaseAck(instanceId) end
end)

return Ignis.Register(CharacterService)
