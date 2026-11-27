-- What the loading screen's pieces read. init.luau owns every source and writes them; the pieces only read them. Every
-- moment is an os.clock() stamp, math.huge for one that has not happened.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.vide)

type Source<T> = vide.Source<T>

-- The title's measure at Title's MEASURE_SIZE: each line's letters' right edges (the width of the line up to them)
-- and their own widths.
export type TLineMetrics = { Rights: { number }, Widths: { number } }
export type TMetrics = { TLineMetrics }

-- "Join" draws on the default screen's colour at once; "Cover" closes squares in over the game, for a teleport out;
-- "Arrive" opens with the title and the bar already up, under the still copy of a cover the teleport carried in.
export type TMode = "Join" | "Cover" | "Arrive"

export type TState = {
	Mode: TMode,
	Now: Source<number>,
	-- The screen's size in design px (1080 tall at 1080p, wider on a wide screen) and the UIScale carrying it there.
	Scale: Source<number>,
	Width: Source<number>,
	Height: Source<number>,
	-- When the backdrop went up (the screen built) and when the content began, once the title was measured.
	ShownAt: Source<number>,
	-- When the backdrop covers the screen whole: ShownAt, but for a cover, once its squares have closed in.
	CoveredAt: number,
	BeganAt: Source<number>,
	Metrics: Source<TMetrics?>,
	-- The words over the bar.
	Phase: Source<string>,
	-- How full the bar is drawn, 0 to 1.
	Reading: Source<number>,
	PaidAt: Source<number>,
	SkipAt: Source<number>,
	LeaveAt: Source<number>,
	IsTouch: boolean,
}

-- The curves init.luau shares with every piece. `Since(at)` is the seconds since a moment, -1 before it (and for one
-- that has not come). The rest are the way out, by a piece's order (the bar 0, the title 1): `Opacity` how much of
-- it shows, `Close` its share still open, `Content` its scale; and `Cover`, the backdrop's pixels' strength. They read
-- the clock only once the screen leaves, so at rest nothing bound to them is worked out again each frame.
export type TClock = {
	Since: (at: number) -> number,
	Opacity: (order: number) -> number,
	Close: (order: number) -> number,
	Content: (order: number) -> number,
	Cover: () -> number,
}

return {}
