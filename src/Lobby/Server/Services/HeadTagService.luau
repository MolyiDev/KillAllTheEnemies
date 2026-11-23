-- The head tags' figures (HeadTagController): each player's level, class, trophies and deaths to everybody
-- (Profile.Public), as their profile loads and when one of those changes, and everybody else's to a player who just
-- loaded. Only the lobby draws head tags, so only the lobby sends them: a client queues an event nothing listens to.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local NetworkMeta = require(ServerScriptService.GlobalServer.NetworkMeta)
local DatabaseService = require(ServerScriptService.GlobalServer.Services.DatabaseService)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)
local TProfile = require(ReplicatedStorage.Types.TProfile)

local ServerNetworkProfile = NetworkMeta.Server.Profile

type TPublic = { Level: number, ClassId: number, Trophies: number, Deaths: number }

local HeadTagService = {}

-- Each loaded player's figures as everybody last heard them.
local sent: { [Player]: TPublic } = {}

local function fire(target: Player?, player: Player, public: TPublic)
	if target then
		ServerNetworkProfile.Public.Fire(target, player, public.Level, public.ClassId, public.Trophies, public.Deaths)
		return
	end

	ServerNetworkProfile.Public.FireAll(player, public.Level, public.ClassId, public.Trophies, public.Deaths)
end

local function broadcast(player: Player, profile: TProfile.TProfile)
	local stats = profile.Stats
	local public = {
		Level = profile.Level,
		ClassId = profile.SelectedClass,
		Trophies = if stats then stats.Trophies else 0,
		Deaths = if stats then stats.Deaths else 0,
	}
	local last = sent[player]
	if
		last
		and last.Level == public.Level
		and last.ClassId == public.ClassId
		and last.Trophies == public.Trophies
		and last.Deaths == public.Deaths
	then
		return
	end

	sent[player] = public
	fire(nil, player, public)
end

HeadTagService.OnDataLoaded = function(player: Player)
	local profile = DatabaseService.Get(player)
	if not profile then return end
	broadcast(player, profile)
	for other, public in sent do
		if other ~= player and other.Parent == Players then fire(player, other, public) end
	end
end :: TPlayerEvents.OnDataLoaded

HeadTagService.OnPlayerDisconnected = function(player: Player)
	sent[player] = nil
end :: TPlayerEvents.OnPlayerDisconnected

DatabaseService.OnProfileChanged:Connect(broadcast)

return Ignis.Register(HeadTagService)
