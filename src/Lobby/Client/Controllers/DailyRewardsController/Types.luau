-- What the daily rewards screen's pieces read and what they may ask for. init.luau owns every source and writes them
-- from the network and the hand; the pieces only read them and call the actions.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.vide)

export type Source<T> = vide.Source<T>

export type TDailyState = {
	Scale: Source<number>,
	-- os.clock(), written only while a timed gesture runs.
	Now: Source<number>,
	-- When the light last crossed today's card to call for it, every few seconds while it waits on the screen.
	CallAt: Source<number>,
	IsOpen: Source<boolean>,
	ToggledAt: Source<number>,
	-- From DailyRewards.State: the day of the cycle he is on, whether it is still to be claimed, the gun days that pay
	-- Gems instead, and the os.clock the next UTC day starts at.
	Day: Source<number>,
	IsClaimable: Source<boolean>,
	OwnedPrizes: Source<{ [number]: boolean }>,
	NextDayAt: Source<number>,
	-- Whole seconds left until the next day, written as they change while the screen is drawn.
	SecondsLeft: Source<number>,
	-- The week on show and the one before it, and when it changed.
	Week: Source<number>,
	WeekFrom: Source<number>,
	WeekAt: Source<number>,
	-- A claim: when it was pressed (the card winds up until the answer), the day the answer gave, when the reward was
	-- let go (never before the wind-up has shown), and what it paid.
	IsPending: Source<boolean>,
	PressedAt: Source<number>,
	ClaimedDay: Source<number>,
	ClaimedAt: Source<number>,
	ClaimedGems: Source<number>,
	ClaimedGun: Source<number>,
	-- When today's card last came up (the screen opening, or midnight while it is up): it pings once it is in place.
	ReadyAt: Source<number>,
	-- A press the screen turned down: the day card (or -week for a locked tab) and when.
	Refused: Source<number>,
	RefusedAt: Source<number>,
}

export type TDailyActions = {
	Close: () -> (),
	Claim: () -> (),
	PickWeek: (week: number) -> (),
	-- A press on a day or a week that cannot be had yet: `which` is the day, or -week for a tab.
	Refuse: (which: number) -> (),
}

return nil
