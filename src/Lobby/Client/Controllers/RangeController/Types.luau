-- What the range's strip of guns reads and may ask for. init.luau owns every source and writes them; the strip only
-- reads them and calls the actions.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.vide)

export type Source<T> = vide.Source<T>

export type TRangeState = {
	-- The design's 1080 tall fitted to the screen's height.
	Scale: Source<number>,
	-- os.clock(), written only while a gesture runs.
	Now: Source<number>,
	-- The local player stands in the range, and when that last changed.
	IsInside: Source<boolean>,
	InsideAt: Source<number>,
	-- The guns the range offers, in the strip's order (Range.Offer): the loadout, or the one TRY brought.
	Shown: Source<{ number }>,
	-- The gun in hand (a gun Id, 0 for none) and when it was picked.
	Held: Source<number>,
	HeldAt: Source<number>,
	-- The screen covering the trip TRY takes to the range: when it started closing over, and when it opened again.
	CoverAt: Source<number>,
	UncoverAt: Source<number>,
}

export type TRangeActions = {
	Pick: (gunId: number) -> (),
}

return nil
