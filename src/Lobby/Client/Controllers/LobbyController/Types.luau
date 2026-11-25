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
	-- MapsCore.DIFFICULTIES index.
	Difficulty: Source<number>,
	IsFriendsOnly: Source<boolean>,
	-- Whole seconds left on the countdown, or -1 for none.
	Seconds: Source<number>,
}

-- The classes screen's two pages, picked by its tabs.
export type TClassesPage = "Classes" | "Equipment"

-- Another player in this server, as the invite list shows them. One table per player for as long as they are here, so
-- the list keeps their card when it is rebuilt.
export type TInvitePlayer = {
	UserId: number,
	Name: string,
	DisplayName: string,
}

-- What the server last answered about an invite to a player (PadsCore.EInvite), and when.
export type TInviteResult = {
	Result: number,
	At: number,
}

-- A party's invite to this player (Lobby.Invited): its pad, who sent it, and the os.clock() it lapses at.
export type TInvitation = {
	Pad: number,
	UserId: number,
	DisplayName: string,
	EndsAt: number,
}

export type TLobbyState = {
	-- The HUD's: 1080 design px under Roblox's top bar.
	Scale: Source<number>,
	-- The screens' (classes, party, queue): his 1920 x 1080 fitted to the whole window and centred, as every other
	-- lobby screen fits it, so their pieces and EXIT land where the weapons', shop's and quests' do.
	PageScale: Source<number>,
	-- Roblox's top bar, in screen px: the HUD stands under it.
	TopInset: Source<number>,
	-- From the right of Roblox's buttons on the top bar to the screen's middle, in HUD px: the level plate's room.
	TopbarRoom: Source<number>,
	Pads: { TPadView },
	-- The pad this player is on, 0 for none.
	CurrentPad: Source<number>,
	-- He is the host of a pad still being picked: the party menu is his.
	IsChoosing: Source<boolean>,
	-- Per map, by map name (Lobby.MapRecords): the best completed round, the times its boss fell with this player in the
	-- run, and whether its unlock has played (or is playing).
	BestByMap: Source<{ [string]: number }>,
	BossKills: Source<{ [string]: number }>,
	MapsShown: Source<{ [string]: boolean }>,
	-- The player's level (Profile.Sync): the maps open on it too.
	Level: Source<number>,
	-- The map whose unlock plays on the party screen (0 for none yet), and when it starts: the screen holds the host
	-- on it until Party.Parts.Unlock.HOLD.
	UnlockMap: Source<number>,
	UnlockAt: Source<number>,
	-- The host's picks in the menu.
	PickPlayers: Source<number>,
	PickDifficulty: Source<string>,
	PickMap: Source<number>,
	PickFriendsOnly: Source<boolean>,
	-- When the party screen last opened or shut.
	ChoosingAt: Source<number>,
	-- When the map was last picked, and which way the showcase turned to it (-1 back, 1 on).
	MapAt: Source<number>,
	MapStep: Source<number>,
	-- The map shown before it, for the dots under the showcase.
	MapFrom: Source<number>,
	-- When the difficulty was last picked, and what it was before.
	DifficultyAt: Source<number>,
	DifficultyFrom: Source<string>,
	-- When the party size was last picked, and what it was before.
	PlayersAt: Source<number>,
	PlayersFrom: Source<number>,
	-- When the access was last picked.
	AccessAt: Source<number>,
	-- When CREATE last went through, and when a press on something locked was refused.
	CreatedAt: Source<number>,
	PartyRefusedAt: Source<number>,
	-- When the light last crossed CREATE (every few seconds while the screen is up).
	PartyCallAt: Source<number>,
	ToastText: Source<string>,
	IsToastShown: Source<boolean>,
	-- The invite list over the queue: whether it is up and when it last opened or shut; every other player in this
	-- server; what the server answered about each one invited (by user id); and the pad each one stands on (by user id,
	-- none for none), seen from their bodies while the list is up.
	IsInviteOpen: Source<boolean>,
	InviteAt: Source<number>,
	InvitePlayers: Source<{ TInvitePlayer }>,
	InviteResults: Source<{ [number]: TInviteResult }>,
	InviteOnPad: Source<{ [number]: number }>,
	-- The party's invite on show (kept while it leaves), when it came in and when it went (-math.huge while it is up),
	-- how it went ("Join", "Decline" or "Lapse"), its whole seconds left, and when the light last crossed JOIN.
	Invitation: Source<TInvitation?>,
	InvitationAt: Source<number>,
	InvitationGoneAt: Source<number>,
	InvitationAnswer: Source<string>,
	InvitationSeconds: Source<number>,
	InvitationCallAt: Source<number>,
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
	-- The classes or weapons page is up: the Gems counter stands at the right rather than at the top centre.
	IsGemsDocked: Source<boolean>,
	-- XP (percents of a level) the profile holds that a screen is still flying into the level bar (a spin's prize):
	-- the plate rolls toward that much less until each slice lands.
	XpHeld: Source<number>,
	-- Whether today's daily reward waits (the daily screen opens by itself once a visit for it).
	IsDailyReady: Source<boolean>,
	-- Whether anything waits on the daily screen at all (a free spin counts): the top bar's Daily button calls for it.
	IsDailyWaiting: Source<boolean>,
	-- What the HUD's buttons wear (Notice): how many index discoveries and finished quests wait, and whether the Gems
	-- held buy or raise a gun or a class ability; and when the light last crossed the buttons that call for what waits
	-- (every 2.6 s while anything does).
	IndexCount: Source<number>,
	QuestsReady: Source<number>,
	CanUpgradeWeapons: Source<boolean>,
	CanUpgradeClasses: Source<boolean>,
	-- A brew could go in the Mutation Lab now (MutationController.CanBrew): the LAB card wears "!".
	CanBrew: Source<boolean>,
	CallAt: Source<number>,
	-- When PLAY was last pressed, when the server last found no pad for it, and when the light last crossed it (every few
	-- seconds while the HUD is up).
	PlayAt: Source<number>,
	PlayRefusedAt: Source<number>,
	PlayCallAt: Source<number>,
	-- A screen is up over the lobby (classes, weapons, the index, the daily, settings and codes screens), and when the
	-- last one opened or shut: the HUD steps aside, as those screens stand over its pieces.
	IsCovered: Source<boolean>,
	CoveredAt: Source<number>,
	-- The same, less the daily screen: the level plate stays up over it, as a spin's XP flies into it.
	IsPlateCovered: Source<boolean>,
	PlateCoveredAt: Source<number>,
	-- A screen that takes the whole view is up (the results of a run), and when that last changed: even the pills,
	-- which stay up over the shops, step aside.
	IsBare: Source<boolean>,
	BareAt: Source<number>,
	-- The classes screen: whether it is up, and when it last opened or shut.
	IsClassesOpen: Source<boolean>,
	ClassesToggledAt: Source<number>,
	-- The page on show (its tabs: CLASSES, or EQUIPMENT, whose page is EquipmentController's), and when the other
	-- was last left for it (-math.huge while the screen has been on one page since it opened).
	ClassesPage: Source<TClassesPage>,
	ClassesPageAt: Source<number>,
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
	-- The Gems counter's glyph (Hud.BuildTop), where a level's Gems fly from.
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
	-- The next map along the path (1) or the one before (-1); nothing past either end.
	StepMap: (step: number) -> (),
	PickPlayers: (count: number) -> (),
	PickFriendsOnly: (isFriendsOnly: boolean) -> (),
	-- Keeps the clock ticking for a gesture a view starts on its own.
	Stir: (seconds: number) -> (),
	InviteFriends: () -> (),
	-- The invite list over the queue: open it (only in an open party), shut it, and invite a player from it.
	OpenInvite: () -> (),
	CloseInvite: () -> (),
	InvitePlayer: (userId: number) -> (),
	-- JOIN (true) or DECLINE on the party's invite on show.
	AnswerInvitation: (isJoining: boolean) -> (),
	OpenClasses: () -> (),
	OpenWeapons: () -> (),
	OpenQuests: () -> (),
	OpenIndex: () -> (),
	OpenLab: () -> (),
	-- The shop, on a section ("Gems" from the pill's +), or on FEATURED.
	OpenShop: (section: string?) -> (),
	-- The Gems pill's glyph, handed over as it is made: where Gems fly into the pill land.
	MarkGemsGlyph: (glyph: GuiObject) -> (),
	-- The level plate's bar, handed over as it is made: where a spin's XP lands.
	MarkXpBar: (bar: GuiObject) -> (),
	CloseClasses: () -> (),
	PickClassesPage: (page: TClassesPage) -> (),
	PickAbility: (index: number) -> (),
	UpgradeAbility: (classId: number, slot: number) -> (),
}

return nil
