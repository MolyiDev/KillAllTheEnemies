-- A brew's beats, worked out from its stamps so every piece of the lab reads the same moments: the wind-up from BREW
-- (never shorter than WINDUP, so a fast answer still pours), the rarity's climb once the answer is in (a step a
-- rarity, each a beat slower than the last, so the eye feels it slowing toward the one rolled: a batch climbs to its
-- rarest), the landing, and when its potions leave for the POTIONS tab (Flight) after being on show a while.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ERarities = require(ReplicatedStorage.Types.Enums.ERarities)
local Types = require(script.Parent.Types)

export type TTimes = {
	BrewAt: number,
	-- When the climb starts: the wind-up's end or the answer, whichever is later. math.huge until the answer.
	RevealAt: number,
	Rarity: number,
	LandAt: number,
	-- When the potions start leaving the card for the tab.
	FlyAt: number,
}

local Brew = {}

Brew.WINDUP = 1.15
-- The gap before each rarity is reached, by ERarities: the climb slows toward the top.
Brew.STEPS = table.freeze({
	[ERarities.Uncommon] = 0.18,
	[ERarities.Rare] = 0.24,
	[ERarities.Epic] = 0.32,
	[ERarities.Legendary] = 0.42,
	[ERarities.Mythic] = 0.54,
})
-- A beat between the last step and the landing.
Brew.PAUSE = 0.14
-- How long the landing's own gestures run.
Brew.LAND = 0.9
-- How long a potion is on show before it flies to the tab, by rarity: the rarer, the longer it is admired.
Brew.HOLD = table.freeze({
	[ERarities.Common] = 1.3,
	[ERarities.Uncommon] = 1.35,
	[ERarities.Rare] = 1.4,
	[ERarities.Epic] = 1.6,
	[ERarities.Legendary] = 2,
	[ERarities.Mythic] = 2.4,
})
-- A batch's potions leave the flask this far apart.
Brew.FLY_STAGGER = 0.045
-- The pour: pixels a slot, spread over this much of the wind-up, each flying this long.
Brew.MOTES = 10
Brew.POUR_SPREAD = 0.55
Brew.MOTE_FLIGHT = 0.5
Brew.BUBBLES = 8

-- How hard a rarity lands, 0 (Common) to 1 (Mythic).
function Brew.Power(rarity: number): number
	return math.clamp((rarity - ERarities.Common) / (ERarities.Mythic - ERarities.Common), 0, 1)
end

-- The climb's length to `rarity`.
local function climb(rarity: number): number
	local seconds = 0
	for step = ERarities.Common + 1, rarity do
		seconds += Brew.STEPS[step] or 0
	end
	return seconds
end

-- The brew in flight or last made, or nil when there is none.
function Brew.Times(state: Types.TLabState): TTimes?
	local brewAt = state.BrewAt()
	if brewAt == -math.huge then return nil end
	local answeredAt = state.AnsweredAt()
	local shown = state.Shown()
	if answeredAt == math.huge or not shown then
		return {
			BrewAt = brewAt,
			RevealAt = math.huge,
			Rarity = 1,
			LandAt = math.huge,
			FlyAt = math.huge,
		}
	end

	local revealAt = math.max(brewAt + Brew.WINDUP, answeredAt)
	local landAt = revealAt + climb(shown.Rarity) + Brew.PAUSE
	local flyAt = landAt + (Brew.HOLD[shown.Rarity] or Brew.HOLD[ERarities.Common])
	return {
		BrewAt = brewAt,
		RevealAt = revealAt,
		Rarity = shown.Rarity,
		LandAt = landAt,
		FlyAt = flyAt,
	}
end

-- The rarity the climb has reached at `now`: 0 before it starts.
function Brew.StepAt(times: TTimes, now: number): number
	if now < times.RevealAt then return 0 end
	local at = times.RevealAt
	local step = ERarities.Common
	while step < times.Rarity do
		at += Brew.STEPS[step + 1] or 0
		if now < at then break end
		step += 1
	end
	return step
end

-- The moment the climb reached step `step` (1 is the climb's start).
function Brew.StepMoment(times: TTimes, step: number): number
	return times.RevealAt + climb(step)
end

-- Seconds since the climb last stepped, or nil outside the climb.
function Brew.SinceStep(times: TTimes, now: number): number?
	if now < times.RevealAt or now >= times.LandAt then return nil end
	return now - Brew.StepMoment(times, Brew.StepAt(times, now))
end

-- Whether a brew is still being made or shown on its way to the tab: the hand waits for it.
function Brew.IsBusy(state: Types.TLabState): boolean
	local times = Brew.Times(state)
	if not times then return false end
	return state.Now() < times.LandAt + 0.35
end

return Brew
