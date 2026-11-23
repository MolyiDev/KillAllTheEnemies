-- Sends the server's Roblox config values to clients, since ConfigService is
-- server-only. Values travel as JSON strings ("" for a key that is not set).
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Ignis = require(ReplicatedStorage.Packages.Ignis)
local NetworkMeta = require(ServerScriptService.GlobalServer.NetworkMeta)
local ConfigsCore = require(ReplicatedStorage.GlobalShared.Core.ConfigsCore)
local EConfigKeys = require(ReplicatedStorage.Types.Enums.EConfigKeys)

local ServerNetworkConfigs = NetworkMeta.Server.Configs

local ConfigsService = {}

-- Kept on the server: every client would otherwise hold the whole list of codes, the private ones too.
local SERVER_ONLY = table.freeze({
	[EConfigKeys.Codes] = true,
})

local function encode(value: any): string
	if value == nil then return "" end
	return HttpService:JSONEncode(value)
end

local function sendLoadedConfigs(player: Player)
	local keys = {}
	local jsonValues = {}
	local count = 0

	for _, key in EConfigKeys do
		if SERVER_ONLY[key] or not ConfigsCore.IsLoaded(key) then continue end
		count += 1
		keys[count] = key
		jsonValues[count] = encode(ConfigsCore.Get(key))
	end

	if count == 0 then return end
	ServerNetworkConfigs.ConfigsLoaded.Fire(player, keys, jsonValues)
end

-- Keys that load after a player joins reach them through the broadcast below.
ConfigsService.OnPlayerConnected = sendLoadedConfigs

for _, key in EConfigKeys do
	if SERVER_ONLY[key] then continue end
	ConfigsCore.Observe(key, function(value)
		ServerNetworkConfigs.ConfigChanged.FireAll(key, encode(value))
	end)
end

return Ignis.Register(ConfigsService)
