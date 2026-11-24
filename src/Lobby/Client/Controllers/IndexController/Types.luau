-- What the index screen's pieces read and what they may ask for. init.luau owns every source and writes them from the
-- network and the hand; the pieces only read them and call the actions.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.vide)
local TData = require(ReplicatedStorage.Types.TData)

export type Source<T> = vide.Source<T>

-- A page of the index: its key, its word, its card's picture (an EIcons name), its accent and its enemies in
-- the order they come in a run, or (the POTIONS page) its recipes in data Id order and no enemies.
export type TCategory = {
	Key: number,
	Word: string,
	Picture: string,
	Accent: Color3,
	Enemies: { TData.TEnemy },
	Potions: { TData.TPotion }?,
}

-- A recipe brewed at least once: how many times, and whether the index has not shown it found yet.
export type TFoundPotion = {
	Brewed: number,
	IsNew: boolean,
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
	-- When the thing on the stage was last clicked.
	PokedAt: Source<number>,
	-- The recipe on the stage and in the info panel while the POTIONS page is on show (a potion data Id). A pick of
	-- one stamps SelectedAt too.
	SelectedPotion: Source<number>,
	-- The Mutation Lab's word on the recipes found: data Id -> TFoundPotion.
	Potions: Source<{ [number]: TFoundPotion }>,
	-- The os.clock each recipe's reveal plays at, as RevealAt. One the lab calls new with none is drawn unknown.
	PotionsRevealAt: Source<{ [number]: number }>,
	-- Recipes shown found this session and not picked since: their cards carry NEW.
	PotionsUnread: Source<{ [number]: boolean }>,
}

export type TIndexActions = {
	Close: () -> (),
	PickCategory: (key: number) -> (),
	Select: (enemyId: number) -> (),
	SelectPotion: (recipeId: number) -> (),
	-- The thing on the stage was clicked: an enemy attacks, or a locked one shakes its head.
	Poke: () -> (),
	-- Keeps the clock ticking for a gesture a view starts on its own.
	Stir: (seconds: number) -> (),
}

return nil
