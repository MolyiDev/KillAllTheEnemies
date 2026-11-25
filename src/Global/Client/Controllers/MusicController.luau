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
local levels: { [string]: number } = {}
-- Every track's level is multiplied by this: a moment clearing room for itself, kept apart from the levels the
-- places ask for so it gives each track back the level it had.
local duck = 1

local function fade(track: Sound, volume: number, seconds: number)
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(track, info, { Volume = volume }):Play()
end

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

	levels[name] = level
	fade(track, fullVolumes[name] * level * duck, fadeSeconds or DEFAULT_FADE_SECONDS)
end

-- Every track down to `level` of what it is asked for (1 gives it all back), over `fadeSeconds`.
function MusicController.Duck(level: number, fadeSeconds: number)
	duck = level
	for name, track in tracks do
		fade(track, fullVolumes[name] * levels[name] * duck, fadeSeconds)
	end
end

return Ignis.Register(MusicController)
