-- What the results' pieces read. init.luau owns every source and writes them; the pieces only read them and call the
-- one action.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.vide)
local TProfile = require(ReplicatedStorage.Types.TProfile)

type Source<T> = vide.Source<T>

-- One of the squad, standing on the stage.
export type TMember = {
	UserId: number,
	Name: string,
	ClassId: number,
	Kills: number,
	-- Most kills (alone, that is them).
	IsMvp: boolean,
	-- Where they stand (Stage's spots, 1 on the dais), and the order they step on in (the MVP last).
	Slot: number,
	Order: number,
	-- Their avatar once it has loaded, and os.clock() of that (math.huge before).
	Avatar: Source<Model?>,
	LoadedAt: Source<number>,
	-- Where their tag goes, written every frame by the stage: x and y in design px, and how far the head is from the
	-- camera (studs; not above 0 when it is behind it).
	HeadAt: Source<Vector3>,
	-- How wide their tag's writing is, in the tag's own px (its widest row), for its shadow: written by Squad.
	InfoWidth: Source<number>,
}

-- What every piece times itself off.
export type TClock = {
	-- Seconds since the screen went up or came down.
	Elapsed: () -> number,
	-- How much of it is there, 0 to 1.
	Shown: () -> number,
	-- 0 to 1 as a gesture `seconds` long runs from `delay` after the screen went up; 1 while it comes down.
	Since: (delay: number, seconds: number) -> number,
}

export type TState = {
	Scale: Source<number>,
	-- The root's width in design px: the screen's, at Scale.
	Width: Source<number>,
	-- os.clock(), ticked every frame while the screen is up or going.
	Now: Source<number>,
	IsOpen: Source<boolean>,
	ToggledAt: Source<number>,
	Record: Source<TProfile.TMatchRecord?>,
	Members: Source<{ TMember }>,
	-- The player's Gems now, for TOTAL.
	TotalGems: Source<number>,
}

export type TActions = {
	Close: () -> (),
}

return nil
