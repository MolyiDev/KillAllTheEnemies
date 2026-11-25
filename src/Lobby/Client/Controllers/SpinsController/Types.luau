-- What the spins screen's pieces read and what they may ask for. init.luau owns every source and writes them from the
-- network and the hand; the pieces only read them and call the actions.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.vide)

export type Source<T> = vide.Source<T>

-- One turn of a reel, from the press to the last of its prize landing in the HUD. Positions are in slots along the
-- reel (slot k rests under the pointer at offset k). A plan is never changed in place: a new one replaces it.
export type TSpin = {
	-- The press, and the offset the reel stood at.
	StartAt: number,
	From: number,
	-- Filled once the server has answered: when the reel starts slowing, from where, for how long, and where it stops
	-- (a fraction off the middle of the slot holding the prize, so it settles onto it after).
	BrakeAt: number?,
	BrakeFrom: number?,
	BrakeSeconds: number?,
	StopAt: number?,
	-- The whole slot it settles on, the prize there (SpinsCore.PRIZES; 0 for a refused spin) and when it has settled.
	Slot: number?,
	Prize: number?,
	LandAt: number?,
	-- The prize flying into the HUD: when it sets off, how many pieces, and for XP where on the level bar the fill
	-- stands before and after (shares of the bar).
	PayAt: number?,
	Pieces: number?,
	BarFrom: number?,
	BarTo: number?,
}

-- What the spin button does now: spin (a free or bought one is left), sell some, nothing (none left and none for sale
-- here), or wait (the reels are turning).
export type TMode = "Spin" | "Buy" | "None" | "Busy"

export type TSpinsState = {
	Scale: Source<number>,
	-- os.clock(), written only while a timed gesture runs.
	Now: Source<number>,
	-- Whether the page is on show in the daily screen, and when that last changed (a moment to come, for a page let in
	-- once the other has cleared).
	IsOpen: Source<boolean>,
	ToggledAt: Source<number>,
	-- From Spins.State: free spins left today and bought ones left.
	FreeLeft: Source<number>,
	-- Free spins a day: SpinsCore.FREE_PER_DAY and the passes', as the server counts them.
	FreePerDay: Source<number>,
	Bought: Source<number>,
	-- Whole seconds left until the next UTC day, written as they change while the screen is drawn.
	SecondsLeft: Source<number>,
	-- Whether extra spins may be sold to this player (PolicyService's paid random items).
	CanBuy: Source<boolean>,
	Mode: Source<TMode>,
	-- How many SPIN turns at once, as picked from its menu (SpinsCore.COUNTS); the menu open or not, and when it last
	-- opened or shut.
	Count: Source<number>,
	IsMenuOpen: Source<boolean>,
	MenuAt: Source<number>,
	-- How many reels are drawn: what SPIN would turn now (the count, held to the spins left while any are), or the
	-- reels turning. And when that last changed, so the page takes its new shape and the new reels are dealt: written
	-- before Reels.
	Reels: Source<number>,
	ReelsAt: Source<number>,
	-- How many SPIN turns or sells now, and the price when it sells (0 when it does not).
	Batch: Source<number>,
	Price: Source<number>,
	-- The slot each reel rests on between spins (SpinsCore.MAX_COUNT of them), and the spins turning now, a reel each
	-- (empty at rest).
	Rests: Source<{ number }>,
	Spins: Source<{ TSpin }>,
	-- Where the prize flies to, in his 1920 x 1080: the Gems glyph in the HUD's pill and the start of its level bar,
	-- with the bar's length.
	PillAt: Source<Vector2>,
	BarAt: Source<Vector2>,
	BarLength: Source<number>,
	-- A press that went nowhere (nothing left, nothing for sale).
	RefusedAt: Source<number>,
	-- When SPIN wobbles once to be pressed (the page brought up, or a spin over, with a spin waiting).
	BeckonAt: Source<number>,
}

export type TSpinsActions = {
	Spin: () -> (),
	-- The count menu opened or shut, and a count picked from it.
	SetMenu: (isOpen: boolean) -> (),
	PickCount: (count: number) -> (),
}

return nil
