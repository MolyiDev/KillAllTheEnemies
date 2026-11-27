-- The Giant Spider as it is heard: placeholders out of the T-Rex's picks (Sounds.Bosses.TRex) until its own go
-- through a listening round (Sounds.md, "A boss or giant creature"). Each spider cue names the T-Rex take standing in
-- for it, played at the place it happens. A cue that builds into its beat is started Lead seconds early.
local trexSounds = require(script.Parent.trexSounds)

local spiderSounds = {}

local STAND_INS: { [string]: string } = table.freeze({
	-- Its weight and its blades.
	Step = "Step",
	Land = "Stomp",
	Whoosh = "TailSweep",
	BladeHit = "SpineLand",
	Stab = "SpineLand",
	Rear = "StompLift",
	Crouch = "ChompDraw",
	Snort = "Snort",
	-- Its web.
	Spit = "SpineLaunch",
	GlobLand = "SpineLand",
	Shoot = "SpineLaunch",
	Hatch = "Shatter",
	Drop = "Fall",
	-- Its voice and its end.
	Hurt = "Hurt",
	Shatter = "Shatter",
	DeathCry = "DeathCry",
	Collapse = "Collapse",
	Fall = "Fall",
	DeathSettle = "DeathSettle",
	-- The intro.
	Descend = "TailWind",
	ThreadSnap = "BeamSnap",
	Study = "Glare",
	Sharpen = "Skid",
	Salute = "SummonRear",
	Bow = "StompLift",
	Click = "ChompHome",
})

function spiderSounds.Lead(name: string): number
	local standIn = STAND_INS[name]
	return if standIn then trexSounds.Lead(standIn) else 0
end

-- `owner` as trexSounds.Play's.
function spiderSounds.Play(name: string, at: Vector3, owner: number?)
	local standIn = STAND_INS[name]
	if standIn then trexSounds.Play(standIn, at, owner) end
end

return spiderSounds
