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
	-- Roblox's top bar, in screen px: the HUD stands under it.
	TopInset: Source<number>,
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
	-- os.clock(), written only while a timed gesture runs (the HUD's entrance and rolls).
	Now: Source<number>,
	-- When the HUD's pieces start sliding in.
	EnteredAt: Source<number>,
	-- The level plate rolls from one level-and-share (Level + Xp / 100) to another, from a moment on (Hud.Rolled).
	XpFrom: Source<number>,
	XpTo: Source<number>,
	XpAt: Source<number>,
	-- The Gems pill's roll.
	GemsFrom: Source<number>,
	GemsTo: Source<number>,
	GemsAt: Source<number>,
	-- Gems the profile holds that a screen is still flying into the pill (the daily rewards' claim): the pill shows that
	-- many fewer until each slice lands, and swells while they land.
	GemsHeld: Source<number>,
	IsGemsFed: Source<boolean>,
	-- When the light last caught the counter's stone (every few seconds while the HUD is up).
	GemGlintAt: Source<number>,
	-- The classes or weapons page is up: the Gems counter stands in his coin slot on it rather than at the top centre.
	IsGemsDocked: Source<boolean>,
	-- XP (percents of a level) the profile holds that a screen is still flying into the level bar (a spin's prize):
	-- the plate rolls toward that much less until each slice lands.
	XpHeld: Source<number>,
	-- Whether today's daily reward waits and whether a type found in a run is still to be shown in the index, and when
	-- the light last crossed the cards that call for them.
	IsDailyReady: Source<boolean>,
	IsIndexNew: Source<boolean>,
	CallAt: Source<number>,
	-- The key held down that no text box took, for the HUD's keyed buttons.
	HeldKey: Source<Enum.KeyCode?>,
	-- A screen is up over the lobby (classes, weapons, the index), and when the last one opened or shut: the HUD steps
	-- aside.
	IsCovered: Source<boolean>,
	CoveredAt: Source<number>,
	-- A screen that takes the whole view is up (the results of a run), and when that last changed: even the pills,
	-- which stay up over the shops, step aside.
	IsBare: Source<boolean>,
	BareAt: Source<number>,
	-- The classes screen: whether it is up, and when it last opened or shut.
	IsClassesOpen: Source<boolean>,
	ClassesToggledAt: Source<number>,
	-- The ability its info panel shows (an index into the class's abilities, the ultimate after them), and when it
	-- was picked.
	ShownAbility: Source<number>,
	AbilityPickedAt: Source<number>,
	-- Each class's ability levels by slot, the ultimate last (Classes.Sync), and the Gems the profile holds.
	ClassLevels: Source<{ [number]: { number } }>,
	Gems: Source<number>,
	-- An upgrade asked for and not shown yet (unanswered, or its Gems still flying); when the last granted one's Gems
	-- set off from the pill, and when they land and the level is shown (in the future while they fly); when the last
	-- press was refused.
	IsUpgrading: Source<boolean>,
	UpgradePaidAt: Source<number>,
	UpgradedAt: Source<number>,
	UpgradeRefusedAt: Source<number>,
	-- The Gems counter's glyph (Hud.BuildGems), where a level's Gems fly from.
	GemsGlyph: Source<GuiObject?>,
	-- A copy of the player's avatar for its stage, and one in the doll's pose for the Decoy's card
	-- (AbilityPicture.Doll), taken each time it opens.
	Avatar: Source<Model?>,
	Doll: Source<Model?>,
}

export type TLobbyActions = {
	Play: () -> (),
	Leave: () -> (),
	StartParty: () -> (),
	PickDifficulty: (difficulty: string) -> (),
	PickMap: (index: number) -> (),
	InviteFriends: () -> (),
	OpenClasses: () -> (),
	OpenWeapons: () -> (),
	OpenDailyRewards: () -> (),
	OpenSpins: () -> (),
	OpenQuests: () -> (),
	OpenIndex: () -> (),
	-- The Gems pill's glyph, handed over as it is made: where Gems fly into the pill land.
	MarkGemsGlyph: (glyph: GuiObject) -> (),
	CloseClasses: () -> (),
	PickAbility: (index: number) -> (),
	UpgradeAbility: (classId: number, slot: number) -> (),
}

return nil
