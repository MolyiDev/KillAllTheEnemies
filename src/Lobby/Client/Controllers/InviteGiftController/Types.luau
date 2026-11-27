-- The surprise gift's toast: its state and actions, shared by the controller and its view.

export type Source<T> = (() -> T) & ((value: T) -> T)

-- The friend the toast names, or nil for any friend (none could be picked): Roblox's invite screen then lists them.
export type TFriend = {
	UserId: number,
	Username: string,
	IsOnline: boolean,
}

export type TToastState = {
	-- Screen px per design px.
	Scale: Source<number>,
	-- os.clock, written only while something moves.
	Now: Source<number>,
	Friend: Source<TFriend?>,
	-- What the friend's first join pays (Invites.Gift).
	Gems: Source<number>,
	-- When it came in and when it last left (os.clock): it is up while ShownAt is the later. Answer: how it left
	-- ("Invite" lifts it away; "Close", and "Aside" for its time running out or standing aside, slide it out).
	ShownAt: Source<number>,
	GoneAt: Source<number>,
	Answer: Source<string>,
	-- The light crossing INVITE while it waits.
	CallAt: Source<number>,
}

export type TToastActions = {
	Invite: () -> (),
	Close: () -> (),
}

return nil
