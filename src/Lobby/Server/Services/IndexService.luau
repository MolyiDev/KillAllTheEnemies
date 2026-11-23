-- The index in the lobby: each player's discoveries told to their screen (Index.Sync), their reveals marked as played,
-- and the `index` console command that edits them for a test. Discoveries and kills are counted in the Game place (its
-- IndexService); here they are only read.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Conch = require(ReplicatedStorage.Packages.conch)
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local NetworkMeta = require(ServerScriptService.GlobalServer.NetworkMeta)
local DatabaseService = require(ServerScriptService.GlobalServer.Services.DatabaseService)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local CommandTypes = require(ReplicatedStorage.Types.CommandTypes)
local EEnemiesIds = require(ReplicatedStorage.Types.Enums.Data.EEnemiesIds)
local TData = require(ReplicatedStorage.Types.TData)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)
local TProfile = require(ReplicatedStorage.Types.TProfile)

local ServerNetworkIndex = NetworkMeta.Server.Index
local ClientNetworkIndex = NetworkMeta.Client.Index
local args = Conch.args

local PERMISSION_DEV = "command.dev"

local IndexService = {}

local function send(player: Player, profile: TProfile.TProfile)
	local ids, kills, isNew = {}, {}, {}
	local count = 0
	local index = profile.Index or {}
	-- By the data rather than the saved keys: a type taken out of the game is not on the wire.
	for _, enemy in DataCore.Enemies.All do
		local entry = index[enemy.Name]
		if not entry then continue end
		count += 1
		ids[count] = enemy.Id
		kills[count] = entry.Kills
		isNew[count] = entry.IsNew == true
	end

	ServerNetworkIndex.Sync.Fire(player, ids, kills, isNew)
end

-- The enemies a command names: every one for "all", else the one whose EEnemiesIds key it is in lower case.
local function named(target: string): { TData.TEnemy }
	if target == "all" then return DataCore.Enemies.All end
	for key, id in EEnemiesIds :: { [string]: number } do
		if string.lower(key) ~= target then continue end
		local enemy = DataCore.Enemies.ById[id]
		return if enemy then { enemy } else {}
	end

	return {}
end

-- Changes the executor's index with `change` (entry by Name, nil when not found, to the new entry or nil) for each
-- enemy `target` names, then sends it, so an open screen plays what changed. Returns how many it touched.
local function edit(target: string, change: (entry: TProfile.TIndexEntry?) -> TProfile.TIndexEntry?): number
	local player = (Conch.get_command_context() :: any).executor.player :: Player?
	local enemies = named(target)
	if not player or #enemies == 0 then return 0 end
	DatabaseService.Update(player, function(profile)
		local index = profile.Index or {}
		for _, enemy in enemies do
			index[enemy.Name] = change(index[enemy.Name])
		end
		profile.Index = if next(index) then index else nil
		return true
	end)

	local profile = DatabaseService.Get(player)
	if profile then send(player, profile) end
	return #enemies
end

local function registerIndex()
	Conch.register("index", {
		permissions = { PERMISSION_DEV },
		description = "Test the index: discover or forget enemies, replay every reveal, or set an enemy's kills.",
		arguments = function()
			return args.overload({
				{
					description = "Discover every enemy, or one: each newly found one is revealed on its page",
					arguments = {
						args.literal("discover"),
						CommandTypes.enemyOrAll("name", "The enemy to discover, or all."),
					},
				},
				{
					description = "Forget every enemy, or one, as if never met",
					arguments = {
						args.literal("forget"),
						CommandTypes.enemyOrAll("name", "The enemy to forget, or all."),
					},
				},
				{
					description = "Show every found enemy as just found again, so each reveal plays once more",
					arguments = { args.literal("replay") },
				},
				{
					description = "Set how many of an enemy you have defeated (it is discovered if it was not)",
					arguments = {
						args.literal("kills"),
						CommandTypes.enemyName("name", "The enemy."),
						args.number("amount", "How many defeated."),
					},
				},
			})
		end,
		callback = function(action: string, target: string?, amount: number?)
			if action == "discover" then
				local count = edit(target or "all", function(entry)
					return entry or { Kills = 0, IsNew = true }
				end)
				Conch.log("normal", `Discovered {count}: open the index to see them revealed.`)
			elseif action == "forget" then
				local count = edit(target or "all", function()
					return nil
				end)
				Conch.log("normal", `Forgot {count}.`)
			elseif action == "replay" then
				local count = edit("all", function(entry)
					return if entry then { Kills = entry.Kills, IsNew = true } else nil
				end)
				Conch.log("normal", `Every found enemy is new again ({count} checked): open the index.`)
			elseif action == "kills" then
				local kills = math.max(math.floor(amount or 0), 0)
				local count = edit(target or "", function(entry)
					return { Kills = kills, IsNew = if entry then entry.IsNew else true }
				end)
				if count == 0 then
					Conch.log("error", `Unknown enemy: {target}`)
				else
					Conch.log("normal", `{target} defeated: {kills}.`)
				end
			end
		end,
	})
end

IndexService.OnStart = function()
	registerIndex()
end

IndexService.OnDataLoaded = function(player: Player)
	local profile = DatabaseService.Get(player)
	if profile then send(player, profile) end
end :: TPlayerEvents.OnDataLoaded

-- Only flags the profile already holds are cleared, so a made-up id changes nothing. The screen has already shown the
-- reveal, so nothing is sent back.
ClientNetworkIndex.Seen.On(function(player: Player, enemyIds: { number })
	DatabaseService.Update(player, function(profile)
		local index = profile.Index
		if not index then return false end
		local hasChanged = false
		for _, enemyId in enemyIds do
			local enemy = DataCore.Enemies.ById[enemyId]
			local entry = if enemy then index[enemy.Name] else nil
			if not entry or not entry.IsNew then continue end
			entry.IsNew = nil
			hasChanged = true
		end
		return hasChanged
	end)
end)

return Ignis.Register(IndexService)
