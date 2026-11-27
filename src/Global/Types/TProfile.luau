-- The saved profile. Run state (Gold, run upgrades, placed defenses) is never in here: it lives in the match server's
-- memory and is gone when the run ends.

-- Highest round per map and party category ("Baseplate:Solo", "Baseplate:Squad").
export type TRecord = {
	HighestReached: number,
	HighestCompleted: number,
	-- The longest run, in seconds of the match clock. Nil until a run on it ended.
	BestSeconds: number?,
}

-- One of the squad in the last run, as the lobby stands them over its results.
export type TMatchMember = {
	UserId: number,
	-- The username, never the display name.
	Name: string,
	ClassId: number,
	Kills: number,
}

-- The last run this player played, written by the Game place as it ends or as they leave it, and shown in the lobby
-- (Lobby Entering) until they press LOBBY. The bests are as the run began, so the screen can tell a new one; Xp is
-- in percents of a level, as the profile's, and what the run earned is by source.
export type TMatchRecord = {
	MapName: string,
	Wave: number,
	BestWaveBefore: number,
	Seconds: number,
	BestSecondsBefore: number,
	Gems: number,
	Kills: number,
	SquadKills: number,
	LevelBefore: number,
	XpBefore: number,
	XpWaves: number,
	XpBosses: number,
	Squad: { TMatchMember },
}

-- Lifetime figures, shown on the head tags. Trophies are runs that set a new best wave on their map.
export type TStats = {
	Deaths: number,
	Trophies: number,
}

-- One enemy type in the index: how many this player has killed, and whether the lobby has yet to show it found (its
-- reveal plays once, the next time its card is on screen).
export type TIndexEntry = {
	Kills: number,
	IsNew: boolean?,
}

-- The daily rewards' streak (DailyRewardsCore): the last day of the cycle claimed (1 to 28) and the UTC day it was
-- claimed on.
export type TDaily = {
	Day: number,
	LastDay: number,
}

-- One board of quests (QuestsCore): the period it was dealt for (a UTC day, or a UTC week from Monday), and its quests
-- by Name with how far each has got and whether it was claimed, in the same order.
export type TQuestBoard = {
	Period: number,
	Names: { string },
	Progress: { number },
	Claimed: { boolean },
}

-- The daily spins (SpinsCore): the UTC day the free ones were last used on and how many of them, and the extra spins
-- bought and not used yet.
export type TSpins = {
	Day: number,
	Used: number,
	Bought: number,
}

-- The equipment (EquipmentCore), by data Name. Owned: each piece got, true (an EarlyUnlock piece is everybody's and
-- never in it). Equipped: slot ("Head", "Torso", "Legs") -> Name, or "" for a slot emptied by hand; a slot never
-- picked holds its EarlyUnlock piece. Hidden: the pieces drawn off the avatar, true (worn, they still count).
export type TEquipmentSave = {
	Owned: { [string]: boolean },
	Equipped: { [string]: string },
	Hidden: { [string]: boolean },
}

-- One potion brewed and not used up (PotionsCore): its recipe by data Name, its rarity by ERarities key, and the
-- matches it has still to give. Id is the profile's own count (TMutation.NextId), so two of one recipe are told apart.
export type TPotion = {
	Id: number,
	Name: string,
	Rarity: string,
	Matches: number,
}

-- A recipe brewed at least once: how many times, and whether the index has yet to show it found.
export type TPotionFound = {
	Brewed: number,
	IsNew: boolean?,
}

-- The Mutation Lab (PotionsCore). Energy: held, by enemy data Name. Equipped: potion Ids in slot order, never more
-- than the slots open. BrewDay / BrewsUsed: the UTC day brews were last used on and how many. Found: by recipe Name.
-- HasGemSlot: the slot bought with Gems. BrewsBought: brews bought with Robux and not used yet (nil for none, so adding
-- it needed no store wipe); the day's free ones go first.
export type TMutation = {
	Energy: { [string]: number },
	Potions: { TPotion },
	Equipped: { number },
	NextId: number,
	BrewDay: number,
	BrewsUsed: number,
	Found: { [string]: TPotionFound },
	HasGemSlot: boolean,
	BrewsBought: number?,
}

export type TInviteGift = {
	IsPaid: boolean,
	Declines: number,
}

export type TProfile = {
	Version: number,
	Gems: number,
	Xp: number,
	Level: number,
	OwnedClasses: { number },
	SelectedClass: number,
	-- The guns (LoadoutCore), by data Name. Owned: Name -> level (1 to LoadoutCore.MAX_LEVEL); a starter is only in it
	-- once upgraded. Equipped: tier ("1".."4") -> Name; a tier never picked holds its starter. Shown: the owned gun worn
	-- on the back (BackGunService), nil for none, so adding it needed no store wipe.
	Loadout: {
		Owned: { [string]: number },
		Equipped: { [string]: string },
		Shown: string?,
	},
	-- The class abilities' levels (AbilitiesCore), by "Class.Ability" Name (2 to AbilitiesCore.MAX_LEVEL); an ability
	-- is only in it once upgraded. Nil until the first upgrade, so adding it needed no store wipe.
	AbilityLevels: { [string]: number }?,
	-- Nil until the first piece is got, equipped or hidden, so adding it needed no store wipe.
	Equipment: TEquipmentSave?,
	-- The daily and weekly quest boards (QuestsCore). Each is nil until its first write, and a board from a past period
	-- is dealt again on the next one, so the default stays {}.
	Quests: {
		Daily: TQuestBoard?,
		Weekly: TQuestBoard?,
	},
	-- Nil until the first claim, so adding it needed no store wipe.
	Daily: TDaily?,
	-- Nil until the first spin or purchase, so adding it needed no store wipe.
	Spins: TSpins?,
	-- Nil until a run has ended and again once its results were seen, so adding it needed no store wipe.
	LastMatch: TMatchRecord?,
	-- Nil until the first death or trophy, so adding it needed no store wipe.
	Stats: TStats?,
	-- The enemies discovered, by data Name: a type is discovered the first time a squad this player is in kills one.
	-- Nil until the first, so adding it needed no store wipe.
	Index: { [string]: TIndexEntry }?,
	-- Nil until the first energy is dropped, so adding it needed no store wipe.
	Mutation: TMutation?,
	-- The codes redeemed (CodesCore.Normalize'd), each true. Nil until the first, so adding it needed no store wipe.
	RedeemedCodes: { [string]: boolean }?,
	-- Who invited this player (InvitesService), by user id, written on their first load: 0 when nobody did or the
	-- invite did not count (an account too new). Nil only before that first load, which is how a new player is told
	-- from one who has been here.
	InvitedBy: number?,
	-- The friends whose first join by this player's invite paid them (InvitesService), by user id, oldest first. Nil
	-- until the first.
	InvitedFriends: { number }?,
	-- The lobby's surprise gift (InvitesService): whether a friend's join by an invite from its toast has paid it, and
	-- how many times its toast was turned down. Nil until either.
	InviteGift: TInviteGift?,
	Achievements: { [string]: number },
	Records: { [string]: TRecord },
	-- How many times this player was in the run as a boss fell, by map Name: what opens the map after it (MapsCore).
	-- Nil until the first, so adding it needed no store wipe.
	BossKills: { [string]: number }?,
	-- The maps whose unlock the party screen has played, by Name, each true. Nil until the first.
	MapsShown: { [string]: boolean }?,
	-- Game passes and one-time products, by name ("DoubleGems", "Vip", "StarterPack").
	Entitlements: { [string]: boolean },
	-- A gift picked in the shop and not paid for yet (ShopService): the offer's Name and who gets it. Nil until the
	-- first gift, so adding it needed no store wipe.
	PendingGift: { Offer: string, UserId: number }?,
	-- Gifts paid for and not yet in their receiver's inbox, each by its receipt id. Nil until the first.
	GiftsOut: { { Id: string, Offer: string, UserId: number } }?,
	-- Processed purchase receipt ids, newest last (DatabaseService.ClaimReceipt).
	Receipts: { string },
	Tutorial: {
		Step: number,
	},
	Settings: {
		IsAutoSkip: boolean,
		CameraMode: number,
		-- The settings screen's (SettingsCore): each is saved only while it is not its default, so nil is the default.
		-- Volumes are whole percents.
		MusicVolume: number?,
		SoundEffectsVolume: number?,
		MenuSoundsVolume: number?,
		IsCameraShakeReduced: boolean?,
		IsDragFireToAim: boolean?,
		ShouldShowDamageNumbers: boolean?,
		ShouldShowDebugInfo: boolean?,
	},
}

return nil
