-- The saved profile. Run state (Gold, run upgrades, placed defenses) is never in here: it lives in the match server's
-- memory and is gone when the run ends.

-- Highest round per map and party category ("PirateCove:Solo", "GrassLands:Squad").
export type TRecord = {
	HighestReached: number,
	HighestCompleted: number,
}

export type TProfile = {
	Version: number,
	Gems: number,
	Xp: number,
	Level: number,
	OwnedClasses: { number },
	SelectedClass: number,
	-- Quest / achievement id (string) -> progress. Shapes owned by their services when they exist.
	Quests: { [string]: number },
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
	},
}

return nil
