-- The settings screen's saved values (TProfile.Settings, SettingsCore), in both places. The client applies a change
-- at once and sends it here to be saved; a setting is stored only while it is not its default.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local NetworkMeta = require(ServerScriptService.GlobalServer.NetworkMeta)
local DatabaseService = require(script.Parent.DatabaseService)
local SettingsCore = require(ReplicatedStorage.GlobalShared.Core.SettingsCore)
local ESettings = require(ReplicatedStorage.Types.Enums.ESettings)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)
local TProfile = require(ReplicatedStorage.Types.TProfile)

local ServerNetworkSettings = NetworkMeta.Server.Settings
local ClientNetworkSettings = NetworkMeta.Client.Settings

local VOLUMES = SettingsCore.Volumes
local TOGGLES = SettingsCore.Toggles

local SettingsService = {}

local function send(player: Player, profile: TProfile.TProfile)
	local saved = profile.Settings
	ServerNetworkSettings.Sync.Fire(
		player,
		saved.MusicVolume or VOLUMES[ESettings.MusicVolume].Default,
		saved.SoundEffectsVolume or VOLUMES[ESettings.SoundEffectsVolume].Default,
		saved.MenuSoundsVolume or VOLUMES[ESettings.MenuSoundsVolume].Default,
		-- Each is false by default; `or false` only makes a boolean of a missing key.
		saved.IsCameraShakeReduced or false,
		saved.IsDragFireToAim or false,
		-- True by default: false is saved, so `or` cannot stand in for the missing key.
		if saved.ShouldShowDamageNumbers == nil
			then TOGGLES[ESettings.ShouldShowDamageNumbers].Default
			else saved.ShouldShowDamageNumbers,
		saved.ShouldShowDebugInfo or false
	)
end

-- Writes one key of the profile's settings, nil for its default. Nothing is written when it already holds that.
local function save(player: Player, key: string, value: (number | boolean)?)
	DatabaseService.Update(player, function(profile)
		local saved = profile.Settings :: { [string]: any }
		if saved[key] == value then return false end
		saved[key] = value
		return true
	end)
end

SettingsService.OnDataLoaded = function(player: Player)
	local profile = DatabaseService.Get(player)
	if profile then send(player, profile) end
end :: TPlayerEvents.OnDataLoaded

-- The handlers below need no character: a setting is the player's own, changed from either place, alive or down.
ClientNetworkSettings.SetVolume.On(function(player: Player, id: number, percent: number)
	local setting = VOLUMES[id]
	if not setting or percent > SettingsCore.MAX_VOLUME then return end
	save(player, setting.Key, if percent == setting.Default then nil else percent)
end)

ClientNetworkSettings.SetToggle.On(function(player: Player, id: number, isOn: boolean)
	local setting = TOGGLES[id]
	if not setting then return end
	save(player, setting.Key, if isOn == setting.Default then nil else isOn)
end)

ClientNetworkSettings.ResetAll.On(function(player: Player)
	DatabaseService.Update(player, function(profile)
		local saved = profile.Settings :: { [string]: any }
		local hasChanged = false
		for _, setting in VOLUMES do
			hasChanged = hasChanged or saved[setting.Key] ~= nil
			saved[setting.Key] = nil
		end
		for _, setting in TOGGLES do
			hasChanged = hasChanged or saved[setting.Key] ~= nil
			saved[setting.Key] = nil
		end

		return hasChanged
	end)
end)

return Ignis.Register(SettingsService)
