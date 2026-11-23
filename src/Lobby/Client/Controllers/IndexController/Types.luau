-- What the index screen's pieces read and what they may ask for. init.luau owns every source and writes them from the
-- network and the hand; the pieces only read them and call the actions.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.vide)
local TData = require(ReplicatedStorage.Types.TData)

export type Source<T> = vide.Source<T>

-- A page of the index: its key, its word, its card's glyph (an Icons cell), its accent and its enemies in the order
-- they come in a run.
export type TCategory = {
	Key: number,
	Word: string,
	Glyph: string,
	Accent: Color3,
	Enemies: { TData.TEnemy },
}

export type TIndexState = {
	Scale: Source<number>,
	-- os.clock(), written only while a timed gesture runs.
	Now: Source<number>,
	IsOpen: Source<boolean>,
	ToggledAt: Source<number>,
	-- The page on show (a TCategory.Key), and when it was last switched to.
	Category: Source<number>,
	CategoryAt: Source<number>,
	-- The enemy on the stage and in the info panel (an enemy Id), and when it changed.
	Selected: Source<number>,
	SelectedAt: Source<number>,
	-- From Index.Sync: each discovered enemy's Id -> this player's kills of it.
	Kills: Source<{ [number]: number }>,
	-- Discoveries whose reveal has not played yet: drawn as unknown until their page is on show.
	Hidden: Source<{ [number]: boolean }>,
	-- The os.clock each reveal plays at, stamped as its page comes up (it may be still to come).
	RevealAt: Source<{ [number]: number }>,
	-- Revealed this session and not picked since: their cards carry NEW.
	Unread: Source<{ [number]: boolean }>,
	-- When the enemy on the stage was last clicked.
	PokedAt: Source<number>,
}

export type TIndexActions = {
	Close: () -> (),
	PickCategory: (key: number) -> (),
	Select: (enemyId: number) -> (),
	-- The enemy on the stage was clicked: it attacks, or a locked one shakes its head.
	Poke: () -> (),
	-- Keeps the clock ticking for a gesture a view starts on its own.
	Stir: (seconds: number) -> (),
}

return nil
