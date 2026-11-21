-- What the lobby's pieces read and what they may ask for. init.luau owns every source and writes them from the
-- network; the pieces only read them and call the actions.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.vide)

type Source<T> = vide.Source<T>

export type TPadView = {
	Index: number,
	Part: BasePart,
	-- PadsCore.EPhase.
	Phase: Source<number>,
	Count: Source<number>,
	MaxPlayers: Source<number>,
	-- MapsCore.LIST index.
	Map: Source<number>,
	IsFriendsOnly: Source<boolean>,
	-- Whole seconds left on the countdown, or -1 for none.
	Seconds: Source<number>,
}

export type TLobbyState = {
	Scale: Source<number>,
	Pads: { TPadView },
	-- The pad this player is on, 0 for none.
	CurrentPad: Source<number>,
	-- He is the host of a pad still being picked: the party menu is his.
	IsChoosing: Source<boolean>,
	-- Best completed round per map, by map name (Lobby.MapRecords).
	BestByMap: Source<{ [string]: number }>,
	-- The host's picks in the menu.
	PickPlayers: Source<number>,
	PickDifficulty: Source<string>,
	PickMap: Source<number>,
	PickFriendsOnly: Source<boolean>,
	ToastText: Source<string>,
	IsToastShown: Source<boolean>,
}

export type TLobbyActions = {
	Play: () -> (),
	Leave: () -> (),
	StartParty: () -> (),
	PickDifficulty: (difficulty: string) -> (),
	PickMap: (index: number) -> (),
}

return nil
