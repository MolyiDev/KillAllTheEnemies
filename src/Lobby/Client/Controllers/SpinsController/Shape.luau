-- The SPIN page's shape for the reels it draws: one reel is his render; two stack under it at his size; three or more
-- stack as slimmer reels. The panel grows down to fit them, then up once it reaches the bottom every lobby panel ends
-- at. A change of count moves every piece from where it stands to the new shape on one curve, so the page reads as one
-- thing changing shape: wells open and close in place, cards reflow, the panel and what is under the reels follow.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local SpinsCore = require(ReplicatedStorage.Shared.Core.SpinsCore)
local Types = require(script.Parent.Types)

-- Px at 1080, from the panel's top.
local Layout = table.freeze({
	-- His one reel's panel and well, and his card.
	TOP = 251,
	HEIGHT = 560,
	WELL_Y = 159,
	WELL = 200,
	CARD = 164,
	-- Reels stacked: the first one's top (room for the one pointer under the rule), the gap, and the tallest slim well;
	-- a slim card is its well less this.
	STACK_Y = 136,
	STACK_GAP = 10,
	SLIM_WELL = 120,
	SLIM_INSET = 20,
	-- Every lobby panel ends by here (EXIT's room) and starts no higher than the daily screen's.
	BOTTOM = 940,
	CEILING = 100,
	-- Slim from this many reels.
	SLIM_FROM = 3,
})

local MORPH = 0.5

export type TShape = {
	-- Each reel's well: its top and height (0 while it is not drawn: it closes in place under the last one).
	WellY: { number },
	WellHeight: { number },
	-- The cards' height, and 0 (his card) to 1 (the slim card's layout).
	Card: number,
	Slim: number,
	-- How far under his one reel's bottom the reels end: what stands under them moves down by it.
	Below: number,
	-- The panel on the screen.
	Top: number,
	Height: number,
}

local Shape = {}

Shape.Layout = Layout

-- The shape for `reels` reels, at rest.
function Shape.For(reels: number): TShape
	local slim = reels >= Layout.SLIM_FROM
	local first = if reels == 1 then Layout.WELL_Y else Layout.STACK_Y
	local well = Layout.WELL
	if slim then
		local room = Layout.BOTTOM
			- Layout.CEILING
			- (Layout.HEIGHT - Layout.WELL_Y - Layout.WELL)
			- first
			- (reels - 1) * Layout.STACK_GAP
		well = math.min(Layout.SLIM_WELL, math.floor(room / reels))
	end

	local wellY = table.create(SpinsCore.MAX_COUNT)
	local wellHeight = table.create(SpinsCore.MAX_COUNT)
	local bottom = first + reels * well + (reels - 1) * Layout.STACK_GAP
	for index = 1, SpinsCore.MAX_COUNT do
		if index <= reels then
			wellY[index] = first + (index - 1) * (well + Layout.STACK_GAP)
			wellHeight[index] = well
		else
			wellY[index] = bottom + Layout.STACK_GAP
			wellHeight[index] = 0
		end
	end

	local below = bottom - (Layout.WELL_Y + Layout.WELL)
	local height = Layout.HEIGHT + below
	return {
		WellY = wellY,
		WellHeight = wellHeight,
		Card = if slim then well - Layout.SLIM_INSET else Layout.CARD,
		Slim = if slim then 1 else 0,
		Below = below,
		Top = math.min(Layout.TOP, Layout.BOTTOM - height),
		Height = height,
	}
end

local function lerp(a: TShape, b: TShape, t: number): TShape
	local wellY = table.create(SpinsCore.MAX_COUNT)
	local wellHeight = table.create(SpinsCore.MAX_COUNT)
	for index = 1, SpinsCore.MAX_COUNT do
		wellY[index] = Motion.Lerp(a.WellY[index], b.WellY[index], t)
		wellHeight[index] = Motion.Lerp(a.WellHeight[index], b.WellHeight[index], t)
	end
	return {
		WellY = wellY,
		WellHeight = wellHeight,
		Card = Motion.Lerp(a.Card, b.Card, t),
		Slim = Motion.Lerp(a.Slim, b.Slim, t),
		Below = Motion.Lerp(a.Below, b.Below, t),
		Top = Motion.Lerp(a.Top, b.Top, t),
		Height = Motion.Lerp(a.Height, b.Height, t),
	}
end

-- The shape now: from wherever it stood as the count changed to the new one, decelerating. Put on outright while the
-- page is not on show. Built once inside the daily screen's vide root; every piece of the page and the panel read it.
function Shape.Build(state: Types.TSpinsState): () -> TShape
	local toReels = vide.untrack(state.Reels)
	local from = Shape.For(toReels)
	local to = from
	local at = -math.huge
	local current = from

	-- The same table while it rests, so nothing that reads it is redrawn as the clock ticks for a spin.
	return vide.derive(function(): TShape
		local reels = state.Reels()
		local now = state.Now()
		if reels ~= toReels then
			-- Off show it takes the shape at once; on show it moves from where it stands.
			to = Shape.For(reels)
			toReels = reels
			from = if vide.untrack(state.IsOpen) then current else to
			at = vide.untrack(state.ReelsAt)
		end
		if current == to then return to end
		local t = Motion.Decelerate(Motion.Progress(now, at, MORPH))
		current = if t >= 1 then to else lerp(from, to, t)
		return current
	end)
end

Shape.SECONDS = MORPH

return Shape
