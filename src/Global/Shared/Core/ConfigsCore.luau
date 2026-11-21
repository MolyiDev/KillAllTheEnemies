-- Live tuning from Roblox Experience Configs (Creator Hub > Configs). ConfigService
-- is server-only: the server reads it here and ConfigsService sends every value to
-- clients, so Observe behaves the same on both sides. MainConfig.json documents
-- each key's value; tools/configs/upload.py publishes it.
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EConfigKeys = require(ReplicatedStorage.Types.Enums.EConfigKeys)

local ConfigsCore = {}

local MAX_RETRY_DELAY_SECONDS = 60

local values: { [string]: any } = {}
local loadedKeys: { [string]: boolean } = {}
local observers: { [string]: { (value: any, oldValue: any) -> () } } = {}

-- Calls back with the key's current value (nil when the key is not set) once it
-- has loaded, then again on every published change. Callers keep their own
-- defaults for nil.
function ConfigsCore.Observe(key: string, callback: (value: any, oldValue: any) -> ())
	local list = observers[key]
	if not list then
		list = {}
		observers[key] = list
	end
	list[#list + 1] = callback

	if loadedKeys[key] then task.spawn(callback, values[key], nil) end
end

function ConfigsCore.IsLoaded(key: string): boolean
	return loadedKeys[key] == true
end

function ConfigsCore.Get(key: string): any
	return values[key]
end

local function set(key: string, value: any)
	local oldValue = values[key]
	values[key] = value
	loadedKeys[key] = true

	local list = observers[key]
	if not list then return end
	for _, callback in list do
		task.spawn(callback, value, oldValue)
	end
end

local function loadSnapshot(): ConfigSnapshot
	local ConfigService = game:GetService("ConfigService")
	local retryDelay = 1
	while true do
		local ok, result = pcall(ConfigService.GetConfigAsync, ConfigService)
		if ok then return result end
		warn("[ConfigsCore] GetConfigAsync failed, retrying:", result)
		task.wait(retryDelay)
		retryDelay = math.min(retryDelay * 2, MAX_RETRY_DELAY_SECONDS)
	end
end

if RunService:IsServer() then
	task.spawn(function()
		local snapshot = loadSnapshot()

		-- A refresh fires every key's GetValueChangedSignal whose value moved.
		snapshot.UpdateAvailable:Connect(function()
			snapshot:Refresh()
		end)

		for _, key in EConfigKeys do
			snapshot:GetValueChangedSignal(key):Connect(function(newValue)
				set(key, newValue)
			end)
			local ok, value = pcall(snapshot.GetValue, snapshot, key)
			set(key, if ok then value else nil)
		end
	end)
else
	local StarterPlayer = game:GetService("StarterPlayer")
	local NetworkMeta = require(StarterPlayer.StarterPlayerScripts.GlobalClient.NetworkMeta)
	local ServerNetworkConfigs = NetworkMeta.Server.Configs

	-- A key can arrive twice (the join batch and the load broadcast race), so an
	-- unchanged value is dropped instead of rerunning every observer.
	local lastJson: { [string]: string } = {}

	local function apply(key: string, json: string)
		if lastJson[key] == json and loadedKeys[key] then return end
		lastJson[key] = json

		local value = nil
		if json ~= "" then
			local ok, decoded = pcall(HttpService.JSONDecode, HttpService, json)
			if ok then value = decoded end
		end
		set(key, value)
	end

	ServerNetworkConfigs.ConfigsLoaded.On(function(keys: { string }, jsonValues: { string })
		for i, key in keys do
			apply(key, jsonValues[i])
		end
	end)

	ServerNetworkConfigs.ConfigChanged.On(apply)
end

return ConfigsCore
