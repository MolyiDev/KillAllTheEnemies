-- What travels from a lobby pad to the match. See JoinData.

export type TJoin = {
	TeleportData: {
		SecureToken: string,
	}?,
}

export type TMessage = {
	-- How many players the pad sent, so the match waits for the whole party before its first round.
	SupposedPlayers: number,
	-- The pad the party queued on, and the map it was for (MapsCore.MAPS).
	PadName: string,
	MapName: string,
}

return nil
