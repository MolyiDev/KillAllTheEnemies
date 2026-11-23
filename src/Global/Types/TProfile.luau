-- The saved profile. Run state (Gold, run upgrades, placed defenses) is never in here: it lives in the match server's
-- memory and is gone when the run ends.

-- Highest round per map and party category ("PirateCove:Solo", "GrassLands:Squad").
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
	-- The codes redeemed (CodesCore.Normalize'd), each true. Nil until the first, so adding it needed no store wipe.
	RedeemedCodes: { [string]: boolean }?,
	Achievements: { [string]: number },
	Records: { [string]: TRecord },
	-- Game passes and one-time products, by name ("DoubleGems", "Vip", "StarterPack").
	Entitlements: { [string]: boolean },
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
	},
}

return nil
