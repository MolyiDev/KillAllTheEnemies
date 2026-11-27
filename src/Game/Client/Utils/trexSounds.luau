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
	RoarShort = 0.15,
	Bite = 0.415,
	TailSweep = 0.36,
	Snort = 0.312,
	Rise = 0.02,
})

type TFade = { Sound: Sound, Volume: number, StartedAt: number, Seconds: number }

-- Each boss's move cues that may still be ringing, by its instance id; and the ones easing out.
local ringing: { [number]: { Sound } } = {}
local fading: { TFade } = {}

function trexSounds.Lead(name: string): number
	return LEAD[name] or 0
end

-- `owner` (a boss's instance id) when the cue is one of its moves, so its death can fade what is still ringing.
function trexSounds.Play(name: string, at: Vector3, owner: number?)
	local _, sound = SoundsCore.PlayWorldNamed(GROUP, name, at)
	if not sound or not owner then return end
	local list = ringing[owner]
	if not list then
		list = {}
		ringing[owner] = list
	end

	-- A cue that has ended has had its holder destroyed (SoundsCore.PlayWorldSound).
	for i = #list, 1, -1 do
		if list[i].Parent then continue end
		list[i] = list[#list]
		list[#list] = nil
	end

	list[#list + 1] = sound
end

-- Every cue `owner` started that is still ringing eases out over `seconds` of real time, so a move cut short by its
-- death never plays on over the fall, nor stops dead.
function trexSounds.FadeOut(owner: number, seconds: number)
	local list = ringing[owner]
	if not list then return end
	ringing[owner] = nil
	local now = os.clock()
	for _, sound in list do
		if sound.Parent then
			fading[#fading + 1] = { Sound = sound, Volume = sound.Volume, StartedAt = now, Seconds = seconds }
		end
	end
end

-- Once a frame: the fades in progress.
function trexSounds.Update()
	if #fading == 0 then return end
	local now = os.clock()
	for i = #fading, 1, -1 do
		local entry = fading[i]
		local sound = entry.Sound
		local u = (now - entry.StartedAt) / entry.Seconds
		if u < 1 and sound.Parent then
			-- Squared, so the tail thins out rather than cutting at the end.
			sound.Volume = entry.Volume * (1 - u) * (1 - u)
			continue
		end
		fading[i] = fading[#fading]
		fading[#fading] = nil
		local holder = sound.Parent
		if holder then holder:Destroy() end
	end
end

return trexSounds
