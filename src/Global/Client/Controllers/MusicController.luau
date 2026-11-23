-- The soundtrack: the looped tracks under Sounds.Music, flat on the Music bus, each faded to the level its place asks
-- for (1 is the track's Volume in the tree). The tracks are Roblox's licensed library, so they play in any experience.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)

local MUSIC_GROUP = "Music"
local DEFAULT_FADE_SECONDS = 3

local MusicController = {}

local tracks: { [string]: Sound } = {}
local fullVolumes: { [string]: number } = {}

-- A track faded to 0 keeps playing, so a layer that comes back picks up where it was instead of from its top, and it
-- starts only when first asked for above 0. A new fade cancels the one running (TweenService does that for a property
-- already being tweened), so it starts from wherever the last one left the Volume.
function MusicController.SetLevel(name: string, level: number, fadeSeconds: number?)
	local track = tracks[name]
	if not track then
		if level <= 0 then return end
		local source = SoundsCore.FindNamed(MUSIC_GROUP, name)
		if not source then return end
		track = source:Clone()
		track.Volume = 0
		track.Parent = SoundService
		track:Play()
		tracks[name] = track
		fullVolumes[name] = source.Volume
	end

	local info = TweenInfo.new(fadeSeconds or DEFAULT_FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(track, info, { Volume = fullVolumes[name] * level }):Play()
end

return Ignis.Register(MusicController)
