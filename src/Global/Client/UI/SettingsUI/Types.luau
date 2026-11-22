-- What the settings screen reads and asks for. SettingsController owns the sources and writes them; the views only
-- read them and call the actions.
export type Source<T> = (() -> T) & ((value: T) -> T)

export type TVolumeRow = {
	Id: number,
	Label: string,
	Default: number,
	-- A whole percent.
	Value: Source<number>,
	IsDragging: Source<boolean>,
	-- os.clock its reset button last sent it home.
	ResetAt: Source<number>,
}

export type TToggleRow = {
	Id: number,
	Label: string,
	Description: string,
	Default: boolean,
	IsOn: Source<boolean>,
	-- os.clock it was last flipped by hand, and last sent home by its reset button.
	ChangedAt: Source<number>,
	ResetAt: Source<number>,
}

export type TSettingsState = {
	Scale: Source<number>,
	-- os.clock, written only in frames where something on the screen is moving (SettingsController's motion window).
	Now: Source<number>,
	IsOpen: Source<boolean>,
	-- os.clock the screen was last opened or shut.
	ToggledAt: Source<number>,
	IsConfirmOpen: Source<boolean>,
	ConfirmToggledAt: Source<number>,

	Volumes: { TVolumeRow },
	Toggles: { TToggleRow },
	-- os.clock a change was last sent to be saved.
	SavedAt: Source<number>,
}

export type TActions = {
	Close: () -> (),
	-- A slider under the hand: heard at once, saved when it is let go.
	DragVolume: (row: TVolumeRow, percent: number) -> (),
	ReleaseVolume: (row: TVolumeRow) -> (),
	ResetVolume: (row: TVolumeRow) -> (),
	SetToggle: (row: TToggleRow, isOn: boolean) -> (),
	ResetToggle: (row: TToggleRow) -> (),
	AskResetAll: () -> (),
	CancelResetAll: () -> (),
	ConfirmResetAll: () -> (),
}

return nil
