-- What the quests screen's pieces read and what they may ask for. init.luau owns every source and writes them from the
-- network and the hand; the pieces only read them and call the actions.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.vide)

export type Source<T> = vide.Source<T>

-- One board as the server last told it (Quests.State), in its order: quest Ids, progress, claimed. EndsAt is the
-- os.clock it is dealt again at.
export type TBoardView = {
	Ids: { number },
	Progress: { number },
	Claimed: { boolean },
	EndsAt: number,
}

export type TQuestsState = {
	Scale: Source<number>,
	-- os.clock(), written only while a timed gesture runs.
	Now: Source<number>,
	-- os.clock(), written every frame while the screen is up and something on it can be claimed: the idle sheens.
	Pulse: Source<number>,
	IsOpen: Source<boolean>,
	ToggledAt: Source<number>,
	-- When it last opened: a board's deal and its bars' fill run from here, and hold while it shuts.
	OpenedAt: Source<number>,
	-- The board on show (1 Daily, 2 Weekly), and when it was last switched to.
	Board: Source<number>,
	BoardAt: Source<number>,
	-- Both boards, by board number.
	Boards: Source<{ TBoardView }>,
	-- Whole seconds until the board on show is dealt again.
	SecondsLeft: Source<number>,
	-- The board a claim is waiting on the server for (0: none), the slot pressed (0: CLAIM ALL), and when.
	PendingBoard: Source<number>,
	PendingSlot: Source<number>,
	PressedAt: Source<number>,
	-- When each claimed slot's moment starts, by board then slot: the card strikes, turns, and throws its Gems. Written
	-- as the answer comes, a moment that may still be to come (a claim-all's cascade).
	Strikes: Source<{ { [number]: number } }>,
	-- A press on a quest that is not finished: its slot and when (the card shakes).
	RefusedSlot: Source<number>,
	RefusedAt: Source<number>,
}

export type TQuestsActions = {
	Close: () -> (),
	PickBoard: (board: number) -> (),
	Claim: (slot: number) -> (),
	ClaimAll: () -> (),
	-- The glyph a card's Gems burst out of, so the payout knows where it is on the screen.
	MarkGem: (board: number, slot: number, glyph: GuiObject) -> (),
	-- Keeps the clock ticking for a gesture a view starts on its own.
	Stir: (seconds: number) -> (),
}

return nil
