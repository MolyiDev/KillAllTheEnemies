-- What the settings screen's rows are, for both sides: each one's id, the key it is saved under in TProfile.Settings
-- and its default. A setting is saved only while it is not its default, so a default changed here reaches everybody
-- who never moved it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ESettings = require(ReplicatedStorage.Types.Enums.ESettings)

export type TVolume = { Id: number, Key: string, Default: number }
export type TToggle = { Id: number, Key: string, Default: boolean }

local SettingsCore = {}

-- Whole percents of each bus's own level in the place.
SettingsCore.MAX_VOLUME = 100

SettingsCore.Volumes = table.freeze({
	[ESettings.MusicVolume] = table.freeze({ Id = ESettings.MusicVolume, Key = "MusicVolume", Default = 100 }),
	[ESettings.SoundEffectsVolume] = table.freeze({
		Id = ESettings.SoundEffectsVolume,
		Key = "SoundEffectsVolume",
		Default = 100,
	}),
	[ESettings.MenuSoundsVolume] = table.freeze({
		Id = ESettings.MenuSoundsVolume,
		Key = "MenuSoundsVolume",
		Default = 100,
	}),
}) :: { [number]: TVolume }

SettingsCore.Toggles = table.freeze({
	[ESettings.IsCameraShakeReduced] = table.freeze({
		Id = ESettings.IsCameraShakeReduced,
		Key = "IsCameraShakeReduced",
		Default = false,
	}),
	[ESettings.IsDragFireToAim] = table.freeze({
		Id = ESettings.IsDragFireToAim,
		Key = "IsDragFireToAim",
		Default = false,
	}),
}) :: { [number]: TToggle }

return table.freeze(SettingsCore)
