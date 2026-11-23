-- Records what each player has met for the lobby's index (TProfile.Index): a type is discovered for everybody in the
-- match the first time the squad kills one, and each player's own kills of it are counted. A kill comes dozens of
-- times a second and a profile write clones the whole profile, so the counts gather in memory and are written every
-- FLUSH_SECONDS, and once more as the player leaves.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local DatabaseService = require(ServerScriptService.GlobalServer.Services.DatabaseService)
local EnemiesService = require(script.Parent.EnemiesService)
local TData = require(ReplicatedStorage.Types.TData)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)

local FLUSH_SECONDS = 3

local IndexService = {}

-- Per player: enemy data Name -> kills not written yet. A 0 is a discovery with no kill of their own.
local pending: { [Player]: { [string]: number } } = {}
-- Per player: the types already in their index or on its way there, remembered once seen. A type known stays known, and
-- every kill asks this for every player in the match.
local known: { [Player]: { [string]: true } } = {}
local nextFlushAt = 0

local function add(player: Player, name: string, kills: number)
	local counts = pending[player]
	if not counts then
		counts = {}
		pending[player] = counts
	end
	counts[name] = (counts[name] or 0) + kills
end

-- Whether `player` already has `name` in their index or on its way there: a squad kill of a type they know adds
-- nothing, so it writes nothing.
local function isKnown(player: Player, name: string): boolean
	local names = known[player]
	if names and names[name] then return true end
	local counts = pending[player]
	local profile = DatabaseService.Get(player)
	local index = if profile then profile.Index else nil
	if not (counts and counts[name]) and not (index and index[name]) then return false end
	if not names then
		names = {}
		known[player] = names
	end
	names[name] = true
	return true
end

-- Kept when the profile is not open, so it goes in with the next flush.
local function flush(player: Player)
	local counts = pending[player]
	if not counts then return end
	local isWritten = DatabaseService.Update(player, function(profile)
		local index = profile.Index or {}
		for name, kills in counts do
			local entry = index[name]
			if entry then
				entry.Kills += kills
			else
				index[name] = { Kills = kills, IsNew = true }
			end
		end
		profile.Index = index
		return true
	end)

	if isWritten then pending[player] = nil end
end

IndexService.OnPlayerDisconnected = function(player: Player)
	flush(player)
	pending[player] = nil
	known[player] = nil
end :: TPlayerEvents.OnPlayerDisconnected

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if now < nextFlushAt or next(pending) == nil then return end
	nextFlushAt = now + FLUSH_SECONDS
	for player in pending do
		flush(player)
	end
end)

EnemiesService.OnEnemyDied:Connect(function(_, enemyData: TData.TEnemy, killer: Player?)
	local name = enemyData.Name
	if killer then add(killer, name, 1) end
	for _, player in Players:GetPlayers() do
		if player ~= killer and not isKnown(player, name) then add(player, name, 0) end
	end
end)

return Ignis.Register(IndexService)
