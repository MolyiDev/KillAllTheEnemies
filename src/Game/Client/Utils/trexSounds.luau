-- The Skeleton T-Rex as it is heard: Sounds.Bosses.TRex (picked in Assets/sounds/Review/TRex, its README), each cue
-- played at the place it happens (Sounds.md, "Where a one-shot is heard from"). BossController and
-- BossIntroController say when and where. A cue that builds into its moment (a voice, a whoosh) carries that build
-- before its beat, so its caller starts it Lead seconds early and the voice arrives on the beat.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)

local trexSounds = {}

local GROUP = "Bosses.TRex"
-- Seconds each cue plays before its beat, as baked (Review/TRex/ship_picks.py prints them); one not here starts on it.
local LEAD: { [string]: number } = table.freeze({
	Roar = 0.725,
	RoarShort = 0.36,
	Bite = 0.415,
	TailSweep = 0.36,
	Snort = 0.312,
	Rise = 0.02,
})

function trexSounds.Lead(name: string): number
	return LEAD[name] or 0
end

function trexSounds.Play(name: string, at: Vector3)
	SoundsCore.PlayWorldNamed(GROUP, name, at)
end

return trexSounds
