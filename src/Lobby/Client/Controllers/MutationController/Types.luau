-- What the Mutation Lab's pieces read and what they may ask for. init.luau owns every source and writes them from the
-- network and the hand; the pieces only read them and call the actions.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.vide)

export type Source<T> = vide.Source<T>

-- A potion held, as Mutation.Sync tells it: its Id, its recipe (a potion data Id), its rarity (ERarities), the
-- matches it has left.
export type TPotion = {
	Id: number,
	Recipe: number,
	Rarity: number,
	Matches: number,
}

-- A slot as PotionsCore.Slots lists it: 1 free, 2 the pass's, 3 the Gems'.
export type TSlot = {
	Kind: number,
	IsOpen: boolean,
}

export type TFound = {
	Brewed: number,
	IsNew: boolean,
}

-- One picture thrown out of a piece and pulled into a tab (a potion brewed, a soul dissolved), in the screen's
-- 1920 x 1080: thrown from `From` along `Direction` for `Reach` px against drag from ThrowAt, hanging, then pulled
-- from HomeAt into `To` by LandAt, keeping the throw's direction before it turns. `Tab` is the tab it lands on;
-- `PotionId` the potion it is (its card in the grid waits for it), 0 for a soul.
export type TFlight = {
	Picture: string,
	Color: Color3,
	Size: number,
	Tab: number,
	PotionId: number,
	From: Vector2,
	To: Vector2,
	Direction: Vector2,
	Reach: number,
	ThrowAt: number,
	HomeAt: number,
	LandAt: number,
}

-- What a flight looks like and where it ends, the rest of it planned (Flight.Plan).
export type TFlightLook = {
	Picture: string,
	Color: Color3,
	Size: number,
	Tab: number,
	PotionId: number,
}

export type TLabState = {
	Scale: Source<number>,
	-- os.clock(), written only while a timed gesture runs.
	Now: Source<number>,
	IsOpen: Source<boolean>,
	ToggledAt: Source<number>,
	-- The page on show: 1 MUTATE, 2 POTIONS; and when it was last picked.
	Tab: Source<number>,
	TabAt: Source<number>,

	-- From Mutation.Sync.
	Discovered: Source<{ [number]: boolean }>,
	Energy: Source<{ [number]: number }>,
	Potions: Source<{ TPotion }>,
	Equipped: Source<{ number }>,
	Slots: Source<{ TSlot }>,
	BrewsLeft: Source<number>,
	BrewsPerDay: Source<number>,
	-- os.clock the brews come back at.
	BrewsBackAt: Source<number>,
	Luck: Source<number>,
	Found: Source<{ [number]: TFound }>,
	Gems: Source<number>,

	-- Whether this player may buy a brew with Robux (PolicyService: paid random items allowed).
	CanBuyBrew: Source<boolean>,

	-- The souls picked for the next brew (enemy data Ids, in the order picked, at most two), and when each was picked.
	Picks: Source<{ number }>,
	PickedAt: Source<{ [number]: number }>,
	-- How many BREW makes at once: a count from the menu (PotionsCore.BREW_COUNTS), held to what the souls and the
	-- brews allow. The menu under it: open or not, and when it last opened or shut.
	BrewCount: Source<number>,
	IsMenuOpen: Source<boolean>,
	MenuAt: Source<number>,
	-- When the light last crossed BREW while it can go (a stamp, so the crossing runs on the clock it wakes).
	CalledAt: Source<number>,
	-- A brew: pressed at, answered at (math.huge until the answer), and what it made (a potion Id, 0 refused). The
	-- reveal starts at RevealAt (the wind-up's end or the answer, whichever is later) and climbs the rarities to it.
	BrewAt: Source<number>,
	-- How many the last BREW asked for: more than one deals that many cards into the tray (Tray) as it pours.
	Asked: Source<number>,
	AnsweredAt: Source<number>,
	BrewedId: Source<number>,
	-- The potion the result card shows once revealed: held here, so the card keeps it after the lab's list has moved on.
	Shown: Source<TPotion?>,
	-- Whether the potion just shown is the first of its recipe (the card's NEW POTION).
	IsShownNew: Source<boolean>,
	-- Every potion the last BREW made, the rarest last; Shown is the rarest.
	Batch: Source<{ TPotion }>,
	-- Pictures in the air (TFlight), and when the last one landed on each tab (1 MUTATE, 2 POTIONS).
	Flights: Source<{ TFlight }>,
	LandedAt: Source<{ number }>,
	-- Potions landed on the POTIONS tab since it was last on show: its badge.
	Unseen: Source<number>,
	-- Picking potions to dissolve: whether the grid is picking, when that last changed, the potions picked, and the
	-- potions dissolving (still drawn while they crunch) with when they went.
	IsDissolving: Source<boolean>,
	DissolveAt: Source<number>,
	DissolvePicks: Source<{ [number]: boolean }>,
	Leaving: Source<{ [number]: { Potion: TPotion, At: number } }>,
	-- The souls the last dissolve gave back, worded ("+12 SOULS"), and when.
	Gained: Source<string>,
	GainedAt: Source<number>,
	-- Where each potion card stands now in the screen's 1920 x 1080, by potion Id: written by the cards as they are
	-- built, read once as a dissolve throws their souls. A plain table, not a source.
	Locate: { [number]: () -> Vector2? },
	-- Whole seconds of os.time, written once a second while the lab is up, for the brews' countdown.
	Clock: Source<number>,
	-- A refusal: the piece that refused (a word), when, and the line it says.
	Refused: Source<string>,
	RefusedAt: Source<number>,
	RefusedText: Source<string>,
	-- A potion put in or taken out of a slot: its Id and when.
	SlottedId: Source<number>,
	SlottedAt: Source<number>,
}

export type TLabActions = {
	Close: () -> (),
	PickTab: (tab: number) -> (),
	-- An energy card pressed: picked, or let go if it was.
	PickEnergy: (enemyId: number) -> (),
	-- An ingredient slot pressed: its energy let go.
	DropPick: (index: number) -> (),
	-- BREW pressed: brews, or offers one for Robux when the day's are used.
	Brew: () -> (),
	-- The count menu opened or shut, and a count picked from it.
	SetMenu: (isOpen: boolean) -> (),
	PickCount: (count: number) -> (),
	-- A potion card pressed: into the first free slot, or out of its slot; picking potions to dissolve, picked or let go.
	TogglePotion: (potionId: number) -> (),
	-- DISSOLVE pressed: picking starts, or the picked potions dissolve. CANCEL: picking stops.
	Dissolve: () -> (),
	CancelDissolve: () -> (),
	-- A closed slot pressed: buy it (Gems), or prompt the pass.
	BuySlot: (kind: number) -> (),
	-- Keeps the clock ticking for a gesture a view starts on its own.
	Stir: (seconds: number) -> (),
}

return nil
