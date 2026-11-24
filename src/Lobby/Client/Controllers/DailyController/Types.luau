-- What the daily screen's shell reads and what it may ask for. init.luau owns every source and writes them from the
-- hand and the pages; the shell only reads them and calls the actions.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.vide)

export type Source<T> = vide.Source<T>

export type TDailyScreenState = {
	Scale: Source<number>,
	-- os.clock(), written only while a timed gesture runs.
	Now: Source<number>,
	IsOpen: Source<boolean>,
	ToggledAt: Source<number>,
	-- The page on show (1 DAILY, 2 SPIN) and when it was picked.
	Tab: Source<number>,
	TabAt: Source<number>,
	-- When the light last crossed a tab whose page has something waiting, every few seconds while it is not on show.
	CallAt: Source<number>,
	-- A tab press turned down (the reel still turning), and when.
	Refused: Source<number>,
	RefusedAt: Source<number>,
}

export type TDailyScreenActions = {
	Close: () -> (),
	PickTab: (tab: number) -> (),
}

-- What the shell reads off the pages: each reads a vide source.
export type TPagesInfo = {
	-- The streak's day, for the DAILY page's words in the header.
	Day: () -> number,
	-- The free spins a day with the passes, for the SPIN page's words in the header.
	FreePerDay: () -> number,
	-- Whether each page has something waiting: today's reward, a free spin.
	IsWaiting: (tab: number) -> boolean,
	-- Whether the reel is turning: the screen holds the SPIN page until it is done.
	IsSpinning: () -> boolean,
	-- The jackpot's shake across the SPIN page in px, which the panel takes too.
	Shake: () -> number,
}

return nil
