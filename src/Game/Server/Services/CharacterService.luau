-- Characters in a match: their health, their network id, and when they come back.
--
-- HEALTH IS THE ECS'S. CurrentHealth / MaxHealth are the truth; the Humanoid only mirrors them, and is set to 0 only to
-- kill the rig, which is what removes Tags.Alive. Nothing else writes Humanoid.Health.
--
-- The network id is CharacterIdsService's: a character counts once it has one on every side (OnCharacterReady).
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
local CharacterIdsService = require(ServerScriptService.GlobalServer.Services.CharacterIdsService)
local EquipmentService = require(ServerScriptService.GlobalServer.Services.EquipmentService)
local loadCharacter = require(ServerScriptService.GlobalServer.Utils.loadCharacter)
local EconomyService = require(script.Parent.EconomyService)
local NavService = require(script.Parent.NavService)
local arenaMap = require(ServerScriptService.Server.Utils.arenaMap)
local upgradeStats = require(ServerScriptService.Server.Utils.upgradeStats)
local TimeCore = require(ReplicatedStorage.Shared.Core.TimeCore)
local UpgradesCore = require(ReplicatedStorage.Shared.Core.UpgradesCore)
local healthUpgrades = require(ReplicatedStorage.Shared.Utils.healthUpgrades)
local Components = require(ReplicatedStorage.GlobalShared.ECS.Components)
local Tags = require(ReplicatedStorage.GlobalShared.ECS.Tags)
local World = require(ReplicatedStorage.GlobalShared.ECS.Worlds.World)
local getCharacterEntityFromPlayer =
	require(ReplicatedStorage.GlobalShared.Utils.Functions.getCharacterEntityFromPlayer)
local getPlayerFromCharacterEntity =
	require(ReplicatedStorage.GlobalShared.Utils.Functions.getPlayerFromCharacterEntity)
local EUpgradesIds = require(ReplicatedStorage.Types.Enums.Data.EUpgradesIds)
local TCharacterEvents = require(ReplicatedStorage.Types.Events.TCharacterEvents)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)

local ServerNetworkCharacters = Network.Server.Characters
local ClientNetworkCharacters = Network.Client.Characters

local CharactersFolder = Workspace:WaitForChild("Characters")

local Tune = table.freeze({
	MAX_HEALTH = healthUpgrades.BASE,
	-- After a hit lands, the window in which further hits are ignored. A crowd pressed against a player then
	-- costs one blow per window rather than one per body, which is what makes standing in a horde survivable
	-- for a moment and lethal for a few.
	HURT_WINDOW_SECONDS = 0.35,
	-- Regeneration (GDD 18): this long after the last hit, this much a second, mirrored to clients this often.
	REGEN_DELAY_SECONDS = 4,
	REGEN_PER_SECOND = 5,
	HEALTH_SYNC_SECONDS = 0.25,
})

local CharacterService = {}

-- (characterEntity, player) once the id is registered on every side: a character a match can count. Its health is
-- sent on it here, and every service of the match hangs its own setup on it.
CharacterService.OnCharacterReady = CharacterIdsService.OnCharacterReady
-- (characterEntity, player)
CharacterService.OnCharacterDied = Signal.new()

local RegenQuery = World
	:query(Components.CurrentHealth, Components.MaxHealth, Components.LastHurtAt, Components.Humanoid)
	:with(Tags.Character, Tags.Alive)
	:cached()
local healthSyncAccumulator = 0
local regenerated: { jecs.Entity<any> } = {}
-- The HEALTH levels each player bought this run (absent is none), kept across deaths: a revive stands up with them.
local healthLevels: { [Player]: number } = {}
-- The players the `god` command made unhurtable, kept across deaths and runs until it is toggled off.
local godPlayers: { [Player]: true } = {}

-- A character's max health with no HEALTH level bought: the base and what the equipment it wears adds.
local function baseMaxHealth(player: Player?): number
	return Tune.MAX_HEALTH + (if player then EquipmentService.StatOf(player, "MaxHealth") else 0)
end

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
	local ok, err = pcall(loadCharacter, player)
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

-- Toggles the `god` command's immunity to every blow. Returns whether it is now on.
function CharacterService.ToggleGod(player: Player): boolean
	local isGod = not godPlayers[player]
	godPlayers[player] = if isGod then true else nil
	return isGod
end

-- One blow on a character. The amount is the server's own (an enemy's Damage), never a client's.
function CharacterService.Damage(characterEntity: jecs.Entity<any>, amount: number)
	if amount <= 0 then return end
	if not World:has(characterEntity, Tags.Alive) then return end
	if World:has(characterEntity, Tags.Picking) then return end
	local now = TimeCore.GameClock
	local hurtUntil = World:get(characterEntity, Components.HurtUntil) or 0
	if now < hurtUntil then return end
	local player = getPlayerFromCharacterEntity(characterEntity)
	if player and godPlayers[player] then return end
	World:set(characterEntity, Components.HurtUntil, now + Tune.HURT_WINDOW_SECONDS)
	World:set(characterEntity, Components.LastHurtAt, now)

	local current = World:get(characterEntity, Components.CurrentHealth)
	if not current then return end
	if player then
		amount *= 1 - math.min(upgradeStats.Get(player, EUpgradesIds.Armor), UpgradesCore.MAX_ARMOR)
		amount *= 1 - EquipmentService.StatOf(player, "Armor")
	end
	current = math.max(current - amount, 0)
	World:set(characterEntity, Components.CurrentHealth, current)

	local humanoid = World:get(characterEntity, Components.Humanoid)
	if humanoid then humanoid.Health = if current > 0 then current else 0 end
	sendHealth(characterEntity)

	if current > 0 then return end
	CharacterService.OnCharacterDied:Fire(characterEntity, player)
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

-- The Heal All product: everyone standing back to full, everyone down back up (a fresh character is full).
function CharacterService.HealAll()
	for characterEntity, max in World:query(Components.MaxHealth):with(Tags.Character, Tags.Alive) do
		CharacterService.Heal(characterEntity, max)
	end

	CharacterService.ReviveDead()
end

-- A new run: everyone's bought HEALTH levels are gone, and a body still standing is back to the base maximum.
function CharacterService.ResetRun()
	for player in healthLevels do
		ServerNetworkCharacters.HealthLevel.FireAll(player, 0)
	end
	table.clear(healthLevels)

	for characterEntity, max in World:query(Components.MaxHealth):with(Tags.Character) do
		local base = baseMaxHealth(getPlayerFromCharacterEntity(characterEntity))
		if max == base then continue end
		-- A body that spawned before its profile opened was given no equipment: its max rises now, and it is healed by
		-- as much, as a bought HEALTH level heals.
		local current = World:get(characterEntity, Components.CurrentHealth) or 0
		current = math.min(current + math.max(base - max, 0), base)
		World:set(characterEntity, Components.MaxHealth, base)
		World:set(characterEntity, Components.CurrentHealth, current)
		local humanoid = World:get(characterEntity, Components.Humanoid)
		if humanoid and current > 0 then
			humanoid.MaxHealth = base
			humanoid.Health = current
		end
		sendHealth(characterEntity)
	end
end

-- Players.CharacterAutoLoads is false in game.project.json, so it holds before the first player arrives.
CharacterService.OnPlayerConnected = function(player: Player)
	task.spawn(CharacterService.Spawn, player)
end :: TPlayerEvents.OnPlayerConnected

-- A profile that opens after its body spawned (a late joiner) brings its equipment's health now: the max rises and the
-- body is healed by as much.
CharacterService.OnDataLoaded = function(player: Player)
	local characterEntity = getCharacterEntityFromPlayer(player)
	if not characterEntity or not World:has(characterEntity, Tags.Alive) then return end
	local max = World:get(characterEntity, Components.MaxHealth)
	local current = World:get(characterEntity, Components.CurrentHealth)
	if not max or not current then return end
	local wanted = baseMaxHealth(player) + healthUpgrades.GAIN * (healthLevels[player] or 0)
	if wanted <= max then return end

	current += wanted - max
	World:set(characterEntity, Components.MaxHealth, wanted)
	World:set(characterEntity, Components.CurrentHealth, current)
	local humanoid = World:get(characterEntity, Components.Humanoid)
	if humanoid then
		-- The maximum first: Health is clamped to it.
		humanoid.MaxHealth = wanted
		humanoid.Health = current
	end
	sendHealth(characterEntity)
end :: TPlayerEvents.OnDataLoaded

CharacterService.OnPlayerDisconnected = function(player: Player)
	healthLevels[player] = nil
	godPlayers[player] = nil
end :: TPlayerEvents.OnPlayerDisconnected

CharacterService.OnCharacterAdded = function(character, characterEntity)
	character.Parent = CharactersFolder

	local owner = Players:GetPlayerFromCharacter(character)
	local level = if owner then healthLevels[owner] or 0 else 0
	local maxHealth = baseMaxHealth(owner) + healthUpgrades.GAIN * level
	local humanoid = World:get(characterEntity, Components.Humanoid)
	if humanoid then
		-- The Humanoid never heals itself: its bar is a mirror of CurrentHealth.
		local regen = character:FindFirstChild("Health")
		if regen then regen:Destroy() end
		humanoid.MaxHealth = maxHealth
		humanoid.Health = maxHealth
	end

	World:set(characterEntity, Components.MaxHealth, maxHealth)
	World:set(characterEntity, Components.CurrentHealth, maxHealth)
	World:set(characterEntity, Components.HurtUntil, 0)
	World:set(characterEntity, Components.LastHurtAt, 0)
end :: TCharacterEvents.OnCharacterAdded

-- The id is everybody's now, so the health can name it.
CharacterIdsService.OnCharacterReady:Connect(sendHealth)

CharacterService.OnCharacterRemoving = function(_, characterEntity)
	local instanceId = World:get(characterEntity, Components.InstanceId)
	if not instanceId then return end
	NavService.RemoveCharacter(instanceId)
end :: TCharacterEvents.OnCharacterRemoving

RunService.Heartbeat:Connect(function(dt: number)
	if TimeCore.IsPaused then return end
	local now = TimeCore.GameClock
	local scaledDt = TimeCore.GetDeltaTime(dt)

	for characterEntity, current, max, lastHurtAt, humanoid in RegenQuery do
		if current <= 0 or current >= max or now - lastHurtAt < Tune.REGEN_DELAY_SECONDS then continue end
		local player = getPlayerFromCharacterEntity(characterEntity)
		local bonus = if player then upgradeStats.Get(player, EUpgradesIds.Regeneration) else 0
		current = math.min(current + (Tune.REGEN_PER_SECOND + bonus) * scaledDt, max)
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

-- Buys the next HEALTH level: the maximum goes up and the body is healed by as much (90 of 100 becomes 110 of 120).
-- The guards are the body's and the purse's: a standing character, a level left to buy, and its Gold, taken in the
-- same step.
ClientNetworkCharacters.UpgradeHealth.On(function(player: Player)
	local characterEntity = getCharacterEntityFromPlayer(player)
	if not characterEntity or not World:has(characterEntity, Tags.Alive) then return end
	local current = World:get(characterEntity, Components.CurrentHealth)
	local max = World:get(characterEntity, Components.MaxHealth)
	if not current or not max or current <= 0 then return end
	local level = (healthLevels[player] or 0) + 1
	local price = healthUpgrades.PRICES[level]
	if not price or not EconomyService.TrySpendGold(player, price) then return end

	healthLevels[player] = level
	max += healthUpgrades.GAIN
	current += healthUpgrades.GAIN
	World:set(characterEntity, Components.MaxHealth, max)
	World:set(characterEntity, Components.CurrentHealth, current)
	local humanoid = World:get(characterEntity, Components.Humanoid)
	if humanoid then
		-- The maximum first: Health is clamped to it.
		humanoid.MaxHealth = max
		humanoid.Health = current
	end

	ServerNetworkCharacters.HealthLevel.FireAll(player, level)
	sendHealth(characterEntity)
end)

return Ignis.Register(CharacterService)
