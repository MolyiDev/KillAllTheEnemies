-- What the equipment page's pieces read and what they may ask for. init.luau owns every source and writes them from
-- the network and the hand; the pieces only read them and call the actions.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.vide)

export type Source<T> = vide.Source<T>

-- The grid's filter: every piece, or one slot's (EquipmentCore.SLOTS).
export type TFilter = "All" | "Head" | "Torso" | "Legs"

-- What a press is waiting on the server for.
export type TRequest = "Equip" | "Unequip" | "Show"

export type TEquipmentState = {
	-- os.clock(), written only while a timed gesture runs.
	Now: Source<number>,
	-- The page on show (the classes screen up on its EQUIPMENT tab), when it last came or went, and whether that was
	-- the screen opening or shutting rather than a tab: a tab fades the page over the other one in place, the screen
	-- sends it off the way the classes page goes.
	IsShown: Source<boolean>,
	ShownAt: Source<number>,
	IsByScreen: Source<boolean>,
	Filter: Source<TFilter>,
	FilterAt: Source<number>,
	-- The piece in the info panel (a piece Id), and when it was picked.
	Selected: Source<number>,
	SelectedAt: Source<number>,
	-- From Equipment.Sync: the pieces owned (Id -> true), the piece each slot holds (slot -> Id, absent for none) and
	-- the pieces drawn off the avatar (Id -> true).
	Owned: Source<{ [number]: boolean }>,
	Equipped: Source<{ [string]: number }>,
	Hidden: Source<{ [number]: boolean }>,
	-- The press waiting on the server, nil for none.
	Pending: Source<TRequest?>,
	-- The last answer worth a gesture: the piece, what happened to it, and when.
	ChangedItem: Source<number>,
	Change: Source<TRequest>,
	ChangedAt: Source<number>,
	-- A press the server turned down, or one the page knew it would (a piece not owned).
	RefusedAt: Source<number>,
	-- The ?'s word on where the piece comes from: open or not, and when that last changed.
	IsHelpOpen: Source<boolean>,
	HelpAt: Source<number>,
	-- A copy of the player's avatar for the stage, without its pieces (the stage dresses it), taken each time the page
	-- comes up.
	Avatar: Source<Model?>,
}

export type TEquipmentActions = {
	Filter: (filter: TFilter) -> (),
	Select: (itemId: number) -> (),
	-- The info panel's slab: puts the selected piece on, takes it off, or for one not owned says where it comes from.
	Press: () -> (),
	ToggleShown: () -> (),
	ToggleHelp: () -> (),
	-- Keeps the clock ticking for a gesture a view starts on its own.
	Stir: (seconds: number) -> (),
}

return nil
