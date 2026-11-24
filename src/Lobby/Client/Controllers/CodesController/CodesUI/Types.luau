-- What the codes screen reads and asks for. CodesController owns the sources and writes them; the views only read them
-- and call the actions.
export type Source<T> = (() -> T) & ((value: T) -> T)

-- Typing: nothing asked. Checking: asked, the answer not shown yet. Redeemed / Refused: the last answer, shown until
-- the next letter typed.
export type TStatus = "Typing" | "Checking" | "Redeemed" | "Refused"

-- A letter taken out of the field, drawn falling out of its cell (backspace) or lifting out of it (the field emptied
-- after a code paid). A pool, reused round-robin.
export type TGhost = {
	Letter: Source<string>,
	Cell: Source<number>,
	-- os.clock it left; a future one waits its turn in a sweep.
	At: Source<number>,
	IsLift: Source<boolean>,
}

export type TCodesState = {
	Scale: Source<number>,
	-- os.clock, written only in frames where something on the screen is moving (CodesController's motion window).
	Now: Source<number>,
	IsOpen: Source<boolean>,
	-- os.clock the screen was last opened or shut.
	ToggledAt: Source<number>,

	-- The code as it is typed, already CodesCore.Normalize'd.
	Text: Source<string>,
	-- os.clock each cell last took a new letter: its pop. A paste stamps its letters a beat apart.
	BornAt: { Source<number> },
	Ghosts: { TGhost },
	IsFocused: Source<boolean>,
	FocusedAt: Source<number>,
	-- The caret's blink, written only as it flips.
	IsCaretOn: Source<boolean>,

	Status: Source<TStatus>,
	-- os.clock REDEEM was pressed, and the answer let go (never sooner than the wind-up after the press).
	AskedAt: Source<number>,
	AnsweredAt: Source<number>,
	-- The line under the field: the hint, a refusal or the payoff. Its kind colours it; a change pops it in.
	Message: Source<string>,
	MessageKind: Source<"Hint" | "Bad" | "Good">,
	MessageAt: Source<number>,
	-- A press with nothing typed: the field shakes.
	NudgedAt: Source<number>,

	-- What the last code paid, the XP in percents of a level, and os.clock its cards were dealt (-math.huge: never, and
	-- the panel stays short).
	Gems: Source<number>,
	Xp: Source<number>,
	RewardsAt: Source<number>,
}

export type TCodesActions = {
	Close: () -> (),
	-- The box's text changed: the controller normalizes it and writes it back.
	Type: (text: string) -> (),
	Focus: (isFocused: boolean) -> (),
	Redeem: () -> (),
}

return nil
