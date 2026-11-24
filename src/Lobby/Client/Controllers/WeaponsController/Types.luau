-- What the weapons screen's pieces read and what they may ask for. init.luau owns every source and writes them from
-- the network and the hand; the pieces only read them and call the actions.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.vide)

export type Source<T> = vide.Source<T>

-- What a press is waiting on the server for.
export type TRequest = "Buy" | "Upgrade" | "Equip" | "Show"

export type TWeaponsState = {
	Scale: Source<number>,
	-- os.clock(), written only while a timed gesture runs.
	Now: Source<number>,
	-- os.clock(), written every frame while the screen is drawn: only the stage reads it (the idle sway and the gun
	-- in the hand).
	StageClock: Source<number>,
	IsOpen: Source<boolean>,
	ToggledAt: Source<number>,
	-- The tier on show, and when it was last switched to.
	Tier: Source<number>,
	TierAt: Source<number>,
	-- The gun on the stage and in the info panel (a gun Id), and when it changed.
	Selected: Source<number>,
	SelectedAt: Source<number>,
	-- From Loadout.Sync: owned gun Id -> level, and the gun each tier holds.
	Levels: Source<{ [number]: number }>,
	Equipped: Source<{ number }>,
	-- The gun worn on the back (a gun Id, 0 for none), when a SHOW or HIDE was last answered and for which gun.
	Shown: Source<number>,
	ShownAt: Source<number>,
	ShownFor: Source<number>,
	Gems: Source<number>,
	-- The press waiting on the server, nil for none.
	Pending: Source<TRequest?>,
	-- The answers worth a gesture: the gun, and when its moment starts. A purchase's moment starts once the Gems have
	-- flown into it (Flight), so its stamp is in the future when it is written.
	BoughtGun: Source<number>,
	BoughtAt: Source<number>,
	UpgradedGun: Source<number>,
	UpgradedAt: Source<number>,
	-- When the Gems for the last purchase or upgrade set off, which one it was, and where from: the HUD's Gems glyph
	-- in his 1920 x 1080, read as they set off.
	PaidAt: Source<number>,
	PaidFor: Source<TRequest>,
	GemsFrom: Source<Vector2>,
	EquippedAt: Source<number>,
	-- A press the server turned down, or one the screen knew it would.
	RefusedAt: Source<number>,
}

export type TWeaponsActions = {
	Close: () -> (),
	PickTier: (tier: number) -> (),
	Select: (gunId: number) -> (),
	Buy: () -> (),
	Upgrade: () -> (),
	Equip: () -> (),
	-- Wears the selected gun on the back, or takes it off when it is the one worn.
	Show: () -> (),
	-- Shuts the screen and takes the selected gun to the shooting range, owned or not.
	Try: () -> (),
	-- Keeps the clock ticking for a gesture a view starts on its own.
	Stir: (seconds: number) -> (),
}

return nil
