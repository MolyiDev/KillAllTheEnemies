--!nonstrict
-- The boss strip under the wave plate (UIMatt.md, In-Game HUD, Boss Container) and the boss's bar it grows into. With
-- no boss up it is his strip exactly: NEXT BOSS, the name, and the way to that boss in four segments, which the kills
-- fill (the boss comes once the run's kills reach the bodies of every wave up to its own, RoundService). When a boss
-- comes on the same pieces grow into the boss's bar (one object, its states told apart by size, colour and light): the
-- panel and the portrait go, so the bar stands on the world with its letters inked (Boss); the tag reads BOSS, the
-- segments become the boss's health with its share inside the bar, and under it the two who have taken the most off
-- it unfold on the left and what it drops on the right. Every rect is in px at 1080; the strip's are his drawn ones.
--
-- The way rises on BarJuice's given-back chase, its head lit by the kills pressing in; each segment it completes is
-- struck with one ring and a light run, and the last one rings the whole strip, reads INCOMING and charges white until
-- the boss comes on (its intro is the release).
--
-- What it does is BarJuice's chase on the boss's health, plus its own moments, each with its cue: the bar fills on
-- arrival a segment at a time, a segment emptied bursts, and a fall punches the strip, rings the bar and stamps it
-- DEFEATED, rolls for its drops, and turns back into the way to the next one. Everything timed off the HUD's clock is derived, so a bar at
-- rest works nothing out while the clock runs for the rest of the HUD.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local RoundCore = require(ReplicatedStorage.Shared.Core.RoundCore)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local BarJuice = require(script.Parent.BarJuice)
local Types = require(script.Parent.Types)
local GunPicture = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.GunPicture)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress
local Lerp = Motion.Lerp
local PIECES = DataCore.Equipment.ById

-- Each piece as his strip draws it, and what the boss's bar (Boss below) draws the same way. Px at 1080, x from the
-- strip's left.
local Layout = table.freeze({
	-- The wave plate's top and height (Wave.luau), which the strip hangs under and comes out from behind.
	PLATE_TOP = 16,
	PLATE_HEIGHT = 88,
	TOP = 116,
	STRIP = Vector2.new(460, 76),
	PORTRAIT = Vector2.new(11, 9),
	PORTRAIT_SIZE = 55,
	CROWN = 41,
	-- The row of the tag, sized to its word, and the name after it.
	TAG = Vector2.new(82, 10),
	TAG_HEIGHT = 24,
	TAG_TEXT = 12,
	TAG_PAD = 10,
	TAG_GAP = 7,
	NAME_SIZE = 26,
	-- The row ends this far in from the strip's right.
	ROW_RIGHT = 12,
	BAR = Vector2.new(82, 50),
	BAR_SIZE = Vector2.new(354, 10),
	SEGMENTS = 4,
	BAR_GAP = 7,
	-- The room the name leaves the boss's share, and how far in from the bar's end it stands inside the bar.
	PERCENT_ROOM = 104,
	PERCENT_IN_BAR = 10,
	-- The shield's marks, one a guard, in the share's place while it is up: this big, this far apart.
	GUARD_MARK = 16,
	GUARD_GAP = 6,
	-- The damage share: a line each for the two who have taken the most, one under the other, under the bar. Each is
	-- its rank, the name, a bar for the part, and the part as a number. Its corner and widths are the look's.
	SHARE_HEIGHT = 16,
	SHARE_STEP = 20,
	SHARE_TEXT = 15,
	SHARE_GAP = 10,
	SHARE_RANK = 12,
	SHARE_BAR = 8,
	SHARE_PERCENT = 64,
	-- The cut at the fill's end.
	CUT = 3,
	-- What the boss drops, under the bar: its caption (the die over DROPS) in a column this wide, then a card a piece,
	-- this far apart.
	DROPS_CAPTION = 14,
	DROPS_CAPTION_WIDTH = 52,
	DROPS_DIE = 22,
	DROP_CARD_GAP = 12,
	-- A card: an edge in the piece's rarity round its picture's face, and under the face, the card's own width, a band
	-- with its chance.
	DROP_CARD = Vector2.new(44, 60),
	DROP_CARD_EDGE = 2,
	DROP_BAND = 16,
	DROP_CHIP_TEXT = 11,
	DROP_CHECK = 18,
	-- The share's caption over its lines, and the chance's.
	CAPTION_TEXT = 12,
})

-- The most pieces the drops show; a boss dropping more shows its rarest.
local MOST_DROPS = 4

-- The boss's bar the strip grows into, px at 1080 from the strip's left. It stands on the world with no panel and no
-- portrait, its letters inked: the tag and the name, the bar in his brackets with the share inside its right end, and
-- under it DAMAGE SHARE on the left and DROPS on the right, a card a piece.
local Boss = table.freeze({
	SIZE = Vector2.new(760, 150),
	-- The strip's portrait shrinks to nothing here.
	PORTRAIT = Vector2.zero,
	PORTRAIT_SIZE = 0,
	CROWN = 0,
	TAG = Vector2.new(0, 0),
	TAG_HEIGHT = 28,
	TAG_TEXT = 15,
	NAME_SIZE = 30,
	ROW_RIGHT = 0,
	BAR = Vector2.new(0, 40),
	BAR_SIZE = Vector2.new(760, 28),
	PERCENT_TEXT = 22,
	-- DAMAGE SHARE: its caption's top, its first line's corner, the column's width and the name's.
	CAPTION = 80,
	SHARES = Vector2.new(0, 98),
	SHARES_WIDTH = 360,
	SHARE_NAME = 160,
	-- DROPS: the caption's corner, the cards after it.
	DROPS = Vector2.new(440, 82),
	-- Wider than half the streak texture: where the strip's face looks into it as it grows.
	TEXTURE_PHASE = Vector2.new(40, 160),
})

-- The room round the strip's panel for its shade, inside the group it fades out as.
local SHADE_ROOM = 24

local SEGMENT = Color3.fromRGB(49, 44, 66)
-- What was just taken, behind the fill, and what is being given back; on the way to a boss, the kills just made.
local GHOST = Palette.White
local GIVEN = Palette.Green:Lerp(Palette.White, 0.55)
local GAINED = Palette.Pink:Lerp(Palette.White, 0.5)
local DEFEATED_NAME = Color3.fromRGB(150, 140, 175)

-- Seconds, each gesture timed from the stamp that starts it.
local Timing = table.freeze({
	-- The strip under the plate: tucked up behind it as a wave is cleared, dropped back as one starts.
	OUT = 0.24,
	IN = 0.46,
	IN_DELAY = 0.22,
	-- The strip growing into the boss's bar, and back.
	GROW = 0.45,
	SHRINK = 0.4,
	-- The bar filling on arrival, once it has mostly grown, then the light run across it.
	FILL = 1.1,
	FILL_DELAY = 0.3,
	SHEEN = 0.7,
	-- A segment lit as the arrival's fill passes it, and one emptied.
	TICK = 0.3,
	BREAK = 0.5,
	PUNCH = 0.35,
	RING = 0.45,
	-- The fall: its flash, how long DEFEATED holds before the strip turns back, and how long after the fall a cleared
	-- wave may tuck it away.
	FLASH = 0.55,
	HOLD = 2,
	TUCK_AFTER = 1.5,
	-- A line's part growing, and the two lines trading places.
	GREW = 0.3,
	SWAP = 0.4,
	-- What the boss drops, dealt once the arrival's fill is most of the way (FILL_DELAY plus 0.7 of FILL), each after
	-- the one before it, its chance counting up as it lands.
	DEAL_FROM = 1.07,
	DEAL = 0.32,
	DEAL_STEP = 0.09,
	COUNT = 0.45,
	-- A segment emptied runs a light down the chances, each a step after the one above.
	GLINT_DELAY = 0.08,
	GLINT = 0.45,
	GLINT_STEP = 0.07,
	-- The fall's rolls: a light runs over the pieces still open, ROLL_PASSES times round them and slowing, until the
	-- rolls are settled (before the strip may be tucked away, TUCK_AFTER); a piece not won by then greys out.
	ROLL_DELAY = 0.15,
	SETTLE = 1.15,
	DIM = 0.3,
	-- A piece won: its strike and its punch.
	WON = 0.6,
	WON_PUNCH = 0.4,
})

local ROLL_PASSES = 2

-- How far a ring grows past what throws it, in px.
local BREAK_REACH = 14
local FALL_REACH = 24
local WON_REACH = 12

-- The kills coming in on the way: each batch the server sends adds to a pressure that drains, eased onto what is shown,
-- so a crowd going down is a surge and not a shiver (UI.md 5j, "A reaction that fires per piece must survive the
-- rate"). A batch counts at most MOST_PER_BATCH kills: a nuke is a surge, not a white-out.
local Surge = table.freeze({
	PER_KILL = 0.18,
	MOST_PER_BATCH = 4,
	DRAIN = 0.35,
	EASE = 0.08,
	-- Shown at this resolution, so a settling surge stops writing.
	STEPS = 50,
})

-- A line's part rolls toward what the server last said at this exponential rate.
local SHARE_ROLL_RATE = 12
-- How long a blow, a segment emptied or a line moving keeps the HUD's clock running: its longest gesture is the shards
-- a segment throws.
local GESTURE_SECONDS = 0.8
-- Where the cues are, under ReplicatedStorage.Sounds (Sounds.md, section 8).
local SOUNDS = "UI.BossBar"
-- The local player's line wears green; another player's, steel.
local SELF_INK = Palette.Green
local OTHER_INK = Palette.Steel

local BossBar = {}

BossBar.MOST_DROPS = MOST_DROPS

-- One of the two who have taken the most off the boss: their UserId (0 for nobody), name, and the health they took
-- as a share of its max.
export type TShareSeen = {
	UserId: number,
	Name: string,
	Share: number,
}

-- What the HUD sees of the boss each frame: the boss up (0 and "" for none), its health as a share of its max, the two
-- biggest parts in it (first, second), the local player's UserId, and whether the run is still on (a boss gone at its
-- end did not fall).
export type TBossSeen = {
	DataId: number,
	Name: string,
	Share: number,
	Top: { TShareSeen },
	SelfId: number,
	IsRunning: boolean,
	-- The way to the next boss: bodies killed on it, and how many it takes.
	WayKills: number,
	WayNeeded: number,
	-- What the boss up drops, read as it comes on; and the os.clock each piece was last won by the local player, by
	-- equipment Id.
	Drops: { Types.TDropRow },
	WonAt: { [number]: number },
}

-- A damage share line between frames: whose it is, its part as shown and as last sent.
type TShareMemory = {
	UserId: number,
	Shown: number,
	Sent: number,
}

-- What the bar remembers between frames: the boss it is about, its chase, the segments still holding health, the two
-- lines, and when a fallen boss's bar is done with it.
export type TBossMemory = {
	DataId: number,
	Chase: BarJuice.TChase,
	Segments: number,
	Rows: { TShareMemory },
	FallEndsAt: number,
	-- The way: its chase, the kills and the size last seen, the segments it has completed, and the kills' pressure and
	-- how much of it is shown.
	Way: BarJuice.TChase,
	WayKills: number,
	WayNeeded: number,
	WaySegments: number,
	Pressure: number,
	Surge: number,
}

function BossBar.NewMemory(): TBossMemory
	return {
		DataId = 0,
		Chase = BarJuice.NewChase(0),
		Segments = 0,
		Rows = { { UserId = 0, Shown = 0, Sent = 0 }, { UserId = 0, Shown = 0, Sent = 0 } },
		FallEndsAt = -math.huge,
		Way = BarJuice.NewChase(0),
		WayKills = 0,
		WayNeeded = 0,
		WaySegments = 0,
		Pressure = 0,
		Surge = 0,
	}
end

-- The two lines from what the server last said. Two who trade places keep what their lines show, and slide past each
-- other. Returns whether anything moved that the HUD's clock must run for.
local function updateShares(bar: Types.TBossBar, memory: TBossMemory, seen: TBossSeen, now: number, dt: number): boolean
	local rows, top = memory.Rows, seen.Top
	local isMoving = false
	if top[1].UserId ~= 0 and top[1].UserId == rows[2].UserId and top[2].UserId == rows[1].UserId then
		rows[1], rows[2] = rows[2], rows[1]
		bar.SwappedAt(now)
		isMoving = true
	end

	for rank, row in rows do
		local line, said = bar.Shares[rank], top[rank]
		if said.UserId ~= row.UserId then
			row.UserId, row.Shown, row.Sent = said.UserId, said.Share, said.Share
		end
		if said.Share > row.Sent then
			line.GrewAt(now)
			isMoving = true
		end
		row.Sent = said.Share
		row.Shown += (said.Share - row.Shown) * math.min(dt * SHARE_ROLL_RATE, 1)
		if math.abs(said.Share - row.Shown) < 1e-4 then row.Shown = said.Share end
		line.Name(said.Name)
		line.IsSelf(said.UserId ~= 0 and said.UserId == seen.SelfId)
		line.Share(row.Shown)
	end

	return isMoving
end

-- The way to the next boss, one frame: its chase, what its kills complete, and their pressure. Returns the os.clock the
-- HUD's clock must run until (-math.huge for nothing).
local function updateWay(bar: Types.TBossBar, memory: TBossMemory, seen: TBossSeen, now: number, dt: number): number
	local kills, needed = seen.WayKills, seen.WayNeeded
	local share = if needed > 0 then math.clamp(kills / needed, 0, 1) else 0
	local segments = math.floor(share * Layout.SEGMENTS + 1e-6)
	local isSnap = needed ~= memory.WayNeeded or kills < memory.WayKills
	if isSnap then
		-- A new way (a boss fell, a run began, a late join) or the party's size changed what it takes: put there, with
		-- nothing to celebrate.
		memory.WaySegments = segments
		if share < 1 then
			bar.FullAt(-math.huge)
		elseif bar.FullAt() == -math.huge then
			bar.FullAt(now)
		end
	elseif kills > memory.WayKills then
		local batch = math.min(kills - memory.WayKills, Surge.MOST_PER_BATCH)
		memory.Pressure = math.min(memory.Pressure + Surge.PER_KILL * batch, 1)
		-- The last segment is the whole strip's moment, with its own ring: one ring a moment.
		if segments >= Layout.SEGMENTS and memory.WaySegments < Layout.SEGMENTS then
			bar.FullAt(now)
		elseif segments > memory.WaySegments then
			bar.Filled(segments)
			bar.FilledAt(now)
		end
		memory.WaySegments = segments
	end
	memory.WayKills, memory.WayNeeded = kills, needed

	BarJuice.Step(memory.Way, share, 1, dt, now, isSnap)
	BarJuice.Write(bar.Way, memory.Way, 0, share, now)
	if memory.Pressure > 0 then
		memory.Pressure *= math.exp(-dt / Surge.DRAIN)
		memory.Surge += (memory.Pressure - memory.Surge) * (1 - math.exp(-dt / Surge.EASE))
		if memory.Pressure < 1e-3 and memory.Surge < 1e-3 then
			memory.Pressure, memory.Surge = 0, 0
		end
		bar.Surge(math.round(memory.Surge * Surge.STEPS) / Surge.STEPS)
	end

	-- Moving, lit, or charging for a boss on its way.
	local way = memory.Way
	local isCharging = seen.DataId == 0 and bar.FullAt() ~= -math.huge
	if way.Fill ~= share or way.Ghost ~= share or memory.Surge > 0 or isCharging then return now + GESTURE_SECONDS end
	return -math.huge
end

-- Stamps each piece on the bar the local player has won since the boss came on (the server says so once it is saved,
-- which can be after the fall). Returns whether one was.
local function updateDrops(bar: Types.TBossBar, seen: TBossSeen, now: number): boolean
	local isWon = false
	for index, row in bar.Drops() do
		local wonAt = bar.DropWonAt[index]
		if not wonAt or row.IsOwned or wonAt() ~= -math.huge then continue end
		local at = seen.WonAt[row.Id]
		if not at or at < bar.AppearedAt() then continue end
		wonAt(now)
		isWon = true
	end

	return isWon
end

-- One frame of the bar: writes `bar` from `seen`. Returns the os.clock the HUD's clock must run until for what this
-- frame started (-math.huge for nothing).
function BossBar.Update(bar: Types.TBossBar, memory: TBossMemory, seen: TBossSeen, now: number, dt: number): number
	local runUntil = updateWay(bar, memory, seen, now, dt)
	local share = seen.Share
	if seen.DataId ~= 0 and seen.DataId ~= memory.DataId then
		memory.DataId = seen.DataId
		memory.Chase = BarJuice.NewChase(share)
		memory.Segments = math.ceil(share * Layout.SEGMENTS - 1e-6)
		for _, row in memory.Rows do
			row.UserId, row.Shown, row.Sent = 0, 0, 0
		end
		bar.Name(seen.Name)
		bar.Drops(seen.Drops)
		for _, wonAt in bar.DropWonAt do
			wonAt(-math.huge)
		end
		bar.DefeatedAt(-math.huge)
		bar.AppearedAt(now)
		SoundsCore.PlayUINamed(SOUNDS, "Arrive")
		runUntil = now + Timing.FILL_DELAY + Timing.FILL + Timing.SHEEN
	elseif seen.DataId == 0 and memory.DataId ~= 0 then
		memory.DataId = 0
		if seen.IsRunning then
			bar.DefeatedAt(now)
			SoundsCore.PlayUINamed(SOUNDS, "Defeated")
			memory.FallEndsAt = now + Timing.HOLD + Timing.SHRINK
			runUntil = memory.FallEndsAt
		else
			memory.FallEndsAt = now
		end
	end

	if memory.DataId == 0 and now >= memory.FallEndsAt then bar.Name("") end
	if bar.Name() == "" then return runUntil end
	if updateDrops(bar, seen, now) then runUntil = math.max(runUntil, now + Timing.WON) end

	local bite = BarJuice.Step(memory.Chase, share, 1, dt, now, false)
	if bite > 0 then runUntil = math.max(runUntil, now + GESTURE_SECONDS) end
	BarJuice.Write(bar.Bar, memory.Chase, bite, share, now)

	-- Each segment emptied throws itself; the flash and the ring go to the last one.
	local segments = math.ceil(share * Layout.SEGMENTS - 1e-6)
	if segments < memory.Segments then
		for index = segments + 1, memory.Segments do
			BarJuice.Throw(bar.Breaks, (index - 0.5) / Layout.SEGMENTS, 1, now)
		end
		bar.Broken(segments + 1)
		bar.BrokeAt(now)
		-- The last one goes with the fall, which has its own cue.
		if segments > 0 then SoundsCore.PlayUINamed(SOUNDS, "Break") end
		runUntil = math.max(runUntil, now + GESTURE_SECONDS)
	end
	memory.Segments = segments

	if memory.DataId == 0 then return runUntil end
	if updateShares(bar, memory, seen, now, dt) then runUntil = math.max(runUntil, now + GESTURE_SECONDS) end
	return runUntil
end

local function label(props: { [any]: any }): TextLabel
	return create("TextLabel")({
		BackgroundTransparency = 1,
		FontFace = Font.Display,
		TextColor3 = Palette.White,
		props,
	})
end

-- Ink round letters of `size`, which stand on the world once the panel has gone: it comes in as `mix` (the strip grown
-- into the boss's bar) runs 0 to 1. A tenth of the letter, so a caption is not choked and a name holds on sand.
-- `shown` is the letters' own fade, which the ink follows.
local function inked(mix: () -> number, size: number, shown: (() -> number)?): UIStroke
	return create("UIStroke")({
		Color = Palette.Ink,
		Thickness = math.max(1, size * 0.1),
		LineJoinMode = Enum.LineJoinMode.Round,
		Transparency = function()
			return 1 - mix() * (if shown then shown() else 1)
		end,
	})
end

-- A rect's corner or size in design px, rounded to whole ones.
local function offset(px: Vector2): UDim2
	return UDim2.fromOffset(math.round(px.X), math.round(px.Y))
end

-- One outline leaving `parent`'s rect as `lifeOf` runs 0 to 1, grown by `reach` px at one weight. It stays Visible and
-- is faded: an element turned Visible is drawn at its last layout for a frame, which was the ring at full reach.
local function ring(lifeOf: () -> number, reach: number, color: any, zIndex: number): Frame
	local life = derive(lifeOf)
	return create("Frame")({
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = function()
			local grow = math.round(reach * Motion.Out(life()))
			return UDim2.new(1, 2 * grow, 1, 2 * grow)
		end,
		BackgroundTransparency = 1,
		ZIndex = zIndex,
		create("UIStroke")({
			Color = color,
			Thickness = 3,
			LineJoinMode = Enum.LineJoinMode.Miter,
			Transparency = function()
				local t = life()
				return if t <= 0 or t >= 1 then 1 else Lerp(0.15, 1, t)
			end,
		}),
	})
end

-- ============================== The bar ==============================

type TBarLook = {
	-- 0 his strip, 1 the boss's bar.
	Mix: () -> number,
	-- What the segments show, as shares of the bar: the fill and the ghost behind it.
	Fill: () -> number,
	Ghost: () -> number,
	GhostColor: () -> Color3,
	-- 0 to 1 per segment: the white it is struck, lit as the arrival's fill passes it or emptied.
	Strike: (index: number) -> number,
	-- The newest blow's wash over the fill, and its light on the cut.
	Flash: () -> number,
	Flare: () -> number,
	-- The light run across the bar once it has filled.
	Sheen: () -> number,
}

-- `extras` are drawn on the bar too: what the boss's bar hangs on it in its panel's place.
local function bar(state: Types.THudState, look: TBarLook, extras: { Instance }?): Frame
	local boss = state.Boss
	local count = Layout.SEGMENTS
	local segments = table.create(count)
	for index = 1, count do
		-- How much of this segment the fill and the ghost cover, 0 to 1: read by several pieces each, worked out once.
		local fillPart = derive(function(): number
			return math.clamp(look.Fill() * count - (index - 1), 0, 1)
		end)
		local ghostPart = derive(function(): number
			return math.clamp(look.Ghost() * count - (index - 1), 0, 1)
		end)
		local strike = derive(function(): number
			return look.Strike(index)
		end)

		segments[index] = create("Frame")({
			Name = "Segment",
			LayoutOrder = index,
			Size = UDim2.new(1 / count, -math.round(Layout.BAR_GAP * (count - 1) / count), 1, 0),
			BackgroundColor3 = SEGMENT,
			BorderSizePixel = 0,
			create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			create("Frame")({
				Name = "Ghost",
				Size = function()
					return UDim2.fromScale(ghostPart(), 1)
				end,
				BackgroundColor3 = look.GhostColor,
				BorderSizePixel = 0,
				BackgroundTransparency = function()
					return if ghostPart() > 0 then 0 else 1
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			}),
			create("Frame")({
				Name = "Fill",
				Size = function()
					return UDim2.fromScale(fillPart(), 1)
				end,
				BackgroundColor3 = Palette.Pink,
				BorderSizePixel = 0,
				ZIndex = 2,
				BackgroundTransparency = function()
					return if fillPart() > 0 then 0 else 1
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
				-- The boss's bar is lit along its top, as his slabs are; his strip's thin bar is flat.
				create("Frame")({
					Name = "Gloss",
					Size = UDim2.fromScale(1, 0.38),
					BackgroundColor3 = Palette.White,
					BorderSizePixel = 0,
					BackgroundTransparency = function()
						return 1 - 0.22 * look.Mix()
					end,
				}),
				-- The blow's white over what is left.
				create("Frame")({
					Name = "Flash",
					Size = UDim2.fromScale(1, 1),
					BackgroundColor3 = Palette.White,
					BorderSizePixel = 0,
					ZIndex = 2,
					BackgroundTransparency = function()
						return 1 - 0.85 * look.Flash()
					end,
					create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
				}),
			}),
			-- The cut: a lit edge where the fill ends, flaring on a blow.
			create("Frame")({
				Name = "Cut",
				AnchorPoint = Vector2.new(1, 0),
				Position = function()
					return UDim2.fromScale(fillPart(), 0)
				end,
				Size = UDim2.new(0, Layout.CUT, 1, 0),
				BackgroundColor3 = Palette.White,
				BorderSizePixel = 0,
				ZIndex = 3,
				BackgroundTransparency = function()
					local share = fillPart()
					if share <= 0 or share >= 1 then return 1 end
					return 1 - math.min(0.45 * look.Mix() + look.Flare(), 1)
				end,
			}),
			-- Struck white as it lights on arrival or is emptied.
			create("Frame")({
				Name = "Strike",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Palette.White,
				BorderSizePixel = 0,
				ZIndex = 4,
				BackgroundTransparency = function()
					return 1 - strike()
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			}),
			-- Off a segment emptied, or one the way completed.
			ring(function()
				local now = state.Now()
				local life = if boss.Broken() == index then Progress(now, boss.BrokeAt(), Timing.RING) else 1
				if boss.Filled() == index then life = math.min(life, Progress(now, boss.FilledAt(), Timing.RING)) end
				return life
			end, BREAK_REACH, Palette.Pink, 0),
		})
	end

	local chipColor = function(): Color3
		return Palette.Pink
	end

	return create("Frame")({
		Name = "Bar",
		Position = function()
			return offset(Layout.BAR:Lerp(Boss.BAR, look.Mix()))
		end,
		Size = function()
			return offset(Layout.BAR_SIZE:Lerp(Boss.BAR_SIZE, look.Mix()))
		end,
		BackgroundTransparency = 1,
		ZIndex = 2,
		create("Frame")({
			Name = "Segments",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			create("UIListLayout")({
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, Layout.BAR_GAP),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			segments,
		}),
		Components.Sheen(look.Sheen, 6),
		BarJuice.Chips(state, boss.Bar, {
			PerBlow = 5,
			SharePerChip = 0.004,
			Size = 6,
			SpeedMin = 140,
			SpeedMax = 260,
			Gravity = 260,
			Life = 0.55,
			Color = chipColor,
		}),
		-- A segment emptied throws its whole width.
		BarJuice.Chips(state, boss.Breaks, {
			PerBlow = 12,
			SharePerChip = 0.001,
			Size = 8,
			SpeedMin = 150,
			SpeedMax = 240,
			Gravity = 260,
			Life = 0.7,
			Spread = 1 / Layout.SEGMENTS,
			Color = chipColor,
		}),
		extras,
	})
end

-- ============================== The damage share ==============================

-- The line for `rank` (1 the most damage), after its rank's number: the name ("YOU" for the local player, in green), a
-- bar for the part and the part as a number. Two who trade places slide past each other: the one going up is lit, the
-- one going down fades through the crossing so the two never print over each other.
local function shareLine(
	state: Types.THudState,
	rank: number,
	shown: () -> number,
	swapping: () -> number,
	mix: () -> number
): Frame
	local line = state.Boss.Shares[rank]
	local grew = derive(function(): number
		local k = Motion.Fade(state.Now(), line.GrewAt(), Timing.GREW)
		return k * k
	end)

	-- How much of the line shows: none for nobody, and the one going down fades through the crossing.
	local seen = derive(function(): number
		if line.Name() == "" then return 0 end
		return if rank == 2 then shown() * (1 - Motion.Bump(1 - swapping())) else shown()
	end)

	-- Its colour, lit as its part grows and, going up, as it passes the other.
	local lit = derive(function(): Color3
		local ink = if line.IsSelf() then SELF_INK else OTHER_INK
		return ink:Lerp(Palette.White, math.max(0.7 * grew(), if rank == 1 then swapping() else 0))
	end)

	local text = function(props: { [any]: any }): TextLabel
		return label({
			Size = UDim2.fromScale(0, 1),
			TextSize = Layout.SHARE_TEXT,
			TextTransparency = function()
				return 1 - seen()
			end,
			inked(mix, Layout.SHARE_TEXT, seen),
			props,
		})
	end

	local top = Boss.SHARES.Y + (rank - 1) * Layout.SHARE_STEP
	-- Where it came from: the other line's place.
	local from = Boss.SHARES.Y + (2 - rank) * Layout.SHARE_STEP
	local left = Boss.SHARES.X + Layout.SHARE_RANK + Layout.SHARE_GAP
	return create("Frame")({
		Name = "Share",
		Position = function()
			return UDim2.fromOffset(left, math.round(Lerp(top, from, swapping())))
		end,
		Size = UDim2.fromOffset(Boss.SHARES.X + Boss.SHARES_WIDTH - left, Layout.SHARE_HEIGHT),
		BackgroundTransparency = 1,
		ZIndex = if rank == 1 then 4 else 3,
		create("UIListLayout")({
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, Layout.SHARE_GAP),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		text({
			Name = "Who",
			LayoutOrder = 2,
			Size = UDim2.new(0, Boss.SHARE_NAME, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = function()
				return if line.IsSelf() then SELF_INK else Palette.White
			end,
			Text = function()
				return if line.IsSelf() then "YOU" else string.upper(line.Name())
			end,
		}),
		create("Frame")({
			Name = "Track",
			LayoutOrder = 3,
			Size = UDim2.fromOffset(0, Layout.SHARE_BAR),
			BackgroundColor3 = SEGMENT,
			BorderSizePixel = 0,
			BackgroundTransparency = function()
				return 1 - seen()
			end,
			create("UIFlexItem")({ FlexMode = Enum.UIFlexMode.Fill }),
			create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			create("Frame")({
				Name = "Fill",
				Size = function()
					return UDim2.fromScale(math.clamp(line.Share(), 0, 1), 1)
				end,
				BorderSizePixel = 0,
				BackgroundColor3 = lit,
				BackgroundTransparency = function()
					return if line.Share() > 0 then 1 - seen() else 1
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			}),
		}),
		text({
			Name = "Part",
			LayoutOrder = 4,
			Size = UDim2.new(0, Layout.SHARE_PERCENT, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = lit,
			Text = function()
				return string.format("%.1f%%", 100 * line.Share())
			end,
		}),
	})
end

-- The two lines, and their ranks' numbers, which stay where they are while the lines trade places.
local function shares(state: Types.THudState, mix: () -> number): { Frame }
	local boss = state.Boss
	-- In once the strip has mostly grown, and first out as it shrinks.
	local shown = derive(function(): number
		return math.clamp((mix() - 0.6) / 0.4, 0, 1)
	end)

	-- 1 as the two trade places, gone as they land.
	local swapping = derive(function(): number
		return 1 - Motion.Out(Progress(state.Now(), boss.SwappedAt(), Timing.SWAP))
	end)

	local frames = table.create(5)
	for rank, line in boss.Shares do
		frames[rank] = shareLine(state, rank, shown, swapping, mix)
		frames[rank + 2] = label({
			Name = "Rank",
			Position = UDim2.fromOffset(Boss.SHARES.X, Boss.SHARES.Y + (rank - 1) * Layout.SHARE_STEP),
			Size = UDim2.fromOffset(Layout.SHARE_RANK, Layout.SHARE_HEIGHT),
			FontFace = Font.DisplayBold,
			TextSize = Layout.SHARE_TEXT,
			TextColor3 = Palette.Lavender,
			ZIndex = 3,
			Text = tostring(rank),
			TextTransparency = function()
				return if line.Name() ~= "" then 1 - shown() else 1
			end,
			inked(mix, Layout.SHARE_TEXT, function()
				return if line.Name() ~= "" then shown() else 0
			end),
		})
	end

	-- DAMAGE SHARE over the lines.
	local caption = Boss.CAPTION
	if caption then
		frames[5] = label({
			Name = "Caption",
			Position = UDim2.fromOffset(Boss.SHARES.X, caption),
			Size = UDim2.fromOffset(Boss.SHARES_WIDTH, Layout.DROPS_CAPTION),
			FontFace = Font.DisplayBold,
			TextSize = Layout.CAPTION_TEXT,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Palette.Lavender,
			ZIndex = 3,
			Text = "DAMAGE SHARE",
			TextTransparency = function()
				return 1 - shown()
			end,
			inked(mix, Layout.CAPTION_TEXT, shown),
		})
	end

	return frames
end

-- The shield's marks at the right end of the name's row: one a guard raised, lit green while it stands.
local function guardMarks(boss: Types.TBossBar, isShielded: () -> boolean): Frame
	local marks = {}
	for i = 1, 8 do
		marks[i] = create("Frame")({
			Name = `Guard{i}`,
			LayoutOrder = i,
			Size = UDim2.fromOffset(Layout.GUARD_MARK, Layout.GUARD_MARK),
			Visible = function()
				return i <= boss.GuardsTotal()
			end,
			BackgroundColor3 = function()
				return if i <= boss.Guards() then Palette.Green else SEGMENT
			end,
			BorderSizePixel = 0,
			Rotation = 45,
			create("UIStroke")({
				Color = function()
					return if i <= boss.Guards() then Palette.White else Palette.Lavender
				end,
				Thickness = 1,
				Transparency = 0.3,
			}),
		})
	end

	return create("Frame")({
		Name = "Guards",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -Boss.ROW_RIGHT, 0, Boss.TAG.Y + Boss.NAME_SIZE / 2),
		Size = UDim2.fromOffset(Layout.PERCENT_ROOM, Boss.NAME_SIZE),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Visible = isShielded,
		create("UIListLayout")({
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, Layout.GUARD_GAP),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		marks,
	})
end

-- ============================== The drops ==============================

-- A chance as its card's band writes it: whole percents plain, a smaller one to a tenth.
local function chanceText(chance: number): string
	local percent = 100 * chance
	if math.abs(percent - math.round(percent)) < 1e-6 then return `{math.round(percent)}%` end
	return string.format("%.1f%%", percent)
end

-- What the drops are told by the strip: how far it has grown into the boss's bar, and whether the boss has fallen.
type TDropsLook = {
	Mix: () -> number,
	IsFallen: () -> boolean,
}

-- One piece the boss drops, as its card shows it: dealt in once the arrival's fill is most of the way, its chance
-- counting up as it lands; lit by a segment emptied (the loot is nearer); at the fall, swept by the roll's light until it
-- is won (struck, punched, and lit in its rarity for good) or the rolls settle without it (it greys). A piece owned as
-- the boss came on cannot drop, so it reads OWNED.
type TDrop = {
	Row: () -> Types.TDropRow?,
	Accent: () -> Color3,
	IsOwned: () -> boolean,
	IsWon: () -> boolean,
	WonAt: () -> number,
	-- 0 to 1: dealt in (and out with the strip), counted up, greyed once missed, the roll's light on it, the win's
	-- strike and punch, and a segment's glint (a sheen's travel).
	Dealt: () -> number,
	Counted: () -> number,
	Missed: () -> number,
	Rolling: () -> number,
	Strike: () -> number,
	Punch: () -> number,
	Glint: () -> number,
	-- The band under the picture: its words, their colour, and its face.
	BandText: () -> string,
	BandInk: () -> Color3,
	BandFace: () -> Color3,
}

-- Piece `index`, of `count` shown.
local function drop(state: Types.THudState, look: TDropsLook, index: number, count: () -> number): TDrop
	local boss = state.Boss
	local wonAt = boss.DropWonAt[index]
	local row = derive(function(): Types.TDropRow?
		return if index <= count() then boss.Drops()[index] else nil
	end)

	local item = derive(function()
		local current = row()
		return if current then PIECES[current.Id] else nil
	end)

	local rarity = derive(function()
		local piece = item()
		return Theme.Rarities[if piece then piece.Rarity else "Common"]
	end)

	local isOwned = function(): boolean
		local current = row()
		return current ~= nil and current.IsOwned
	end

	local isWon = derive(function(): boolean
		return wonAt() ~= -math.huge
	end)

	local dealAt = function(): number
		return boss.AppearedAt() + Timing.DEAL_FROM + Timing.DEAL_STEP * (index - 1)
	end

	-- In from the arrival, out with the strip as it shrinks after the fall.
	local dealt = derive(function(): number
		if not row() then return 0 end
		local grown = math.clamp((look.Mix() - 0.6) / 0.4, 0, 1)
		return grown * Motion.Decelerate(Progress(state.Now(), dealAt(), Timing.DEAL))
	end)

	local counted = derive(function(): number
		if not row() then return 0 end
		return Motion.Out(Progress(state.Now(), dealAt(), Timing.COUNT))
	end)

	local isOpen = function(): boolean
		return look.IsFallen() and not isWon() and not isOwned()
	end

	local missed = derive(function(): number
		if not isOpen() then return 0 end
		return Motion.Out(Progress(state.Now(), boss.DefeatedAt(), Timing.DIM, Timing.SETTLE))
	end)

	-- The roll's light: a spot running over the pieces ROLL_PASSES times, slowing, swelling in and dying away by the
	-- time the rolls settle; each piece lit as it passes.
	local rolling = derive(function(): number
		if not isOpen() then return 0 end
		local u = (state.Now() - boss.DefeatedAt() - Timing.ROLL_DELAY) / (Timing.SETTLE - Timing.ROLL_DELAY)
		if u <= 0 or u >= 1 then return 0 end
		local n = count()
		local at = (Motion.Out(u) * ROLL_PASSES * n - (index - 1)) % n
		local away = math.min(at, n - at)
		return math.max(1 - away, 0) * Motion.Bump(u)
	end)

	local strike = derive(function(): number
		if not isWon() then return 0 end
		local k = Motion.Fade(state.Now(), wonAt(), Timing.WON)
		return k * k
	end)

	local punch = derive(function(): number
		if not isWon() then return 0 end
		local k = Motion.Fade(state.Now(), wonAt(), Timing.WON_PUNCH)
		return k * k
	end)

	return {
		Row = row,
		Accent = function(): Color3
			return rarity().Accent
		end,
		IsOwned = isOwned,
		IsWon = isWon,
		WonAt = wonAt,
		Dealt = dealt,
		Counted = counted,
		Missed = missed,
		Rolling = rolling,
		Strike = strike,
		Punch = punch,
		Glint = function(): number
			if look.IsFallen() then return 1 end
			local at = boss.BrokeAt() + Timing.GLINT_DELAY + Timing.GLINT_STEP * (index - 1)
			return Progress(state.Now(), at, Timing.GLINT)
		end,
		BandText = function(): string
			if isOwned() then return "OWNED" end
			if isWon() then return "WON" end
			local current = row()
			if not current then return "" end
			local k = counted()
			if k >= 1 then return chanceText(current.Chance) end
			return `{math.floor(100 * current.Chance * k)}%`
		end,
		BandInk = function(): Color3
			if isOwned() then return Palette.Green end
			local ink = if rarity().IsInk then Palette.Ink else Palette.White
			return ink:Lerp(Palette.Lavender, missed())
		end,
		BandFace = function(): Color3
			if isOwned() then return Palette.Ink end
			return rarity().Accent:Lerp(SEGMENT, missed())
		end,
	}
end

-- The drops' caption: the die over DROPS, lit while the fall's rolls are open. The word fades in with the strip's
-- growth; the die, a picture, grows in.
local function dropsCaption(state: Types.THudState, look: TDropsLook, shown: () -> number, props): Frame
	local boss = state.Boss
	return create("Frame")({
		Name = "DropsCaption",
		BackgroundTransparency = 1,
		ZIndex = 3,
		create("UIListLayout")({
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Components.Picture(EIcons.Dice, {
			Name = "Die",
			LayoutOrder = 1,
			Size = function()
				return Components.PictureBox(math.round(Layout.DROPS_DIE * shown()))
			end,
		}),
		label({
			Name = "Word",
			LayoutOrder = 2,
			Size = UDim2.fromOffset(0, Layout.DROPS_CAPTION),
			AutomaticSize = Enum.AutomaticSize.X,
			FontFace = Font.DisplayBold,
			TextSize = Layout.CAPTION_TEXT,
			TextColor3 = function()
				local isRolling = look.IsFallen() and state.Now() < boss.DefeatedAt() + Timing.SETTLE
				return if isRolling then Palette.White else Palette.Lavender
			end,
			Text = "DROPS",
			TextTransparency = function()
				return 1 - shown()
			end,
			inked(look.Mix, Layout.CAPTION_TEXT, shown),
		}),
		props,
	})
end

-- The drops as cards in a row after the caption. A card is an edge in the piece's rarity round its picture's face, and
-- under the face, as wide as the card, a band with its chance (OWNED on ink in green for a piece owned, which also
-- wears a check on its corner). Nothing on a card is ever see-through: it grows in from nothing one after another and
-- shrinks away with the strip, and a piece missed darkens. The roll's light runs along the row; a piece won punches, is
-- struck white and closes its brackets round itself as a pick does.
local function dropCards(state: Types.THudState, look: TDropsLook): { Instance }
	local captionShown = derive(function(): number
		return math.clamp((look.Mix() - 0.6) / 0.4, 0, 1)
	end)

	-- How many the boss drops, as many as there is room for: read by every card, worked out once.
	local count = derive(function(): number
		return math.min(#state.Boss.Drops(), MOST_DROPS)
	end)

	local card = Layout.DROP_CARD
	local edge = Layout.DROP_CARD_EDGE
	local frames: { Instance } = table.create(MOST_DROPS + 1)
	frames[1] = dropsCaption(state, look, captionShown, {
		Position = UDim2.fromOffset(Boss.DROPS.X, Boss.DROPS.Y),
		Size = UDim2.fromOffset(Layout.DROPS_CAPTION_WIDTH, card.Y),
	})

	for index = 1, MOST_DROPS do
		local piece = drop(state, look, index, count)
		-- The roll's light and the win's strike, white over the face and the band.
		local lit = derive(function(): number
			return math.max(0.6 * piece.Rolling(), piece.Strike())
		end)

		local left = Boss.DROPS.X + Layout.DROPS_CAPTION_WIDTH + Layout.DROP_CARD_GAP
		local middle =
			Vector2.new(left + (index - 1) * (card.X + Layout.DROP_CARD_GAP) + card.X / 2, Boss.DROPS.Y + card.Y / 2)
		local face = card.X - 2 * edge
		frames[index + 1] = create("Frame")({
			Name = "Drop",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(middle.X, middle.Y),
			Size = UDim2.fromOffset(card.X, card.Y),
			BackgroundColor3 = function()
				return piece.Accent():Lerp(SEGMENT, 0.7 * piece.Missed())
			end,
			BorderSizePixel = 0,
			ZIndex = 3,
			Visible = function()
				return piece.Row() ~= nil and piece.Dealt() > 0
			end,
			create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			create("UIScale")({
				Scale = function()
					return piece.Dealt() * (1 + 0.3 * piece.Punch())
				end,
			}),
			create("Frame")({
				Name = "Face",
				Position = UDim2.fromOffset(edge, edge),
				Size = UDim2.fromOffset(face, face),
				BorderSizePixel = 0,
				BackgroundColor3 = function()
					return Palette.Ink:Lerp(piece.Accent(), 0.3 * (1 - piece.Missed())):Lerp(Palette.White, lit())
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 1) }),
			}),
			GunPicture.Build(function()
				local current = piece.Row()
				return if current then GunPicture.FromEquipment(current.Id) else nil
			end, {
				Tint = function()
					return Palette.White:Lerp(Color3.fromRGB(90, 86, 110), piece.Missed())
				end,
			}, {
				Name = "Picture",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(card.X / 2, edge + face / 2),
				Size = UDim2.fromOffset(face, face),
				ZIndex = 2,
			}),
			label({
				Name = "Band",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(1, 0, 0, Layout.DROP_BAND),
				BackgroundTransparency = 0,
				BackgroundColor3 = piece.BandFace,
				BorderSizePixel = 0,
				TextSize = Layout.DROP_CHIP_TEXT,
				TextColor3 = piece.BandInk,
				Text = piece.BandText,
				ZIndex = 4,
				create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
				create("Frame")({
					Name = "Lit",
					Size = UDim2.fromScale(1, 1),
					BackgroundColor3 = Palette.White,
					BorderSizePixel = 0,
					ZIndex = 2,
					BackgroundTransparency = function()
						return 1 - 0.85 * lit()
					end,
					create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
				}),
			}),
			-- A segment emptied runs a light across the cards.
			Components.Sheen(piece.Glint, 5, card.X / card.Y),
			-- Owned: a check on the card's corner, its middle on the corner.
			Components.Picture(EIcons.Check, {
				Name = "Owned",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(1, 0),
				Size = Components.PictureBox(Layout.DROP_CHECK),
				ImageColor3 = Palette.Green,
				ZIndex = 6,
				Visible = piece.IsOwned,
			}),
			Components.Brackets(nil, function()
				return if piece.IsWon() then 0.2 else 1
			end, 12, piece.IsWon),
			ring(function()
				return if piece.IsWon() then Progress(state.Now(), piece.WonAt(), Timing.RING) else 1
			end, WON_REACH, piece.Accent, 1),
		})
	end

	return frames
end

-- ============================== The strip ==============================

-- The strip's body: his panel, drawn as a group with room for its shade so the whole panel fades out as `mix` (the
-- strip grown into the boss's bar) runs 0 to 1 while the pieces in `props` stay.
local function body(mix: () -> number, props: { [any]: any }): Frame
	return create("Frame")({
		BackgroundTransparency = 1,
		create("CanvasGroup")({
			Name = "PanelFade",
			Position = UDim2.fromOffset(-SHADE_ROOM, -SHADE_ROOM),
			Size = UDim2.new(1, 2 * SHADE_ROOM, 1, 2 * SHADE_ROOM),
			BackgroundTransparency = 1,
			ZIndex = 1,
			GroupTransparency = mix,
			Visible = function()
				return mix() < 0.999
			end,
			Components.Panel({ Brackets = true, TexturePhase = Boss.TEXTURE_PHASE }, {
				Position = UDim2.fromOffset(SHADE_ROOM, SHADE_ROOM),
				Size = UDim2.new(1, -2 * SHADE_ROOM, 1, -2 * SHADE_ROOM),
			}),
		}),
		props,
	})
end

function BossBar.Build(state: Types.THudState): Frame
	local phase = state.Phase
	local boss = state.Boss
	local isBossUp = derive(function()
		return boss.Name() ~= ""
	end)

	local isFallen = derive(function(): boolean
		return boss.DefeatedAt() > boss.AppearedAt()
	end)

	local name = function(): string
		return if isBossUp() then boss.Name() else state.NextBossName()
	end

	-- 0 his strip, 1 the boss's bar: grown as a boss comes on, shrunk back once its fall has been seen.
	-- Every piece reads it, so it is derived: at rest it does not change, and nothing that reads it is worked out again.
	local mix = derive(function(): number
		if not isBossUp() then return 0 end
		local now = state.Now()
		if isFallen() then return 1 - Motion.Out(Progress(now, boss.DefeatedAt(), Timing.SHRINK, Timing.HOLD)) end
		return Motion.Decelerate(Progress(now, boss.AppearedAt(), Timing.GROW))
	end)

	-- The arrival's fill, 0 to 1.
	local arrival = derive(function(): number
		if not isBossUp() then return 0 end
		return Motion.Decelerate(Progress(state.Now(), boss.AppearedAt(), Timing.FILL, Timing.FILL_DELAY))
	end)

	-- When the arrival's fill passes the end of segment `index`: its curve run backwards.
	local tickAt = function(index: number): number
		local share = index / Layout.SEGMENTS
		return boss.AppearedAt() + Timing.FILL_DELAY + Timing.FILL * (1 - (1 - share) ^ (1 / 3))
	end

	-- With no boss up, the bar is the way to the next one, filled by the kills; a boss coming on drains it as the strip
	-- grows, and fills it again with the boss's health.
	local fill = derive(function(): number
		if not isBossUp() then return boss.Way.Fill() end
		local intro = arrival()
		if intro <= 0 then return boss.Way.Fill() * (1 - mix()) end
		return math.min(boss.Bar.Fill(), intro)
	end)

	local ghost = derive(function(): number
		if not isBossUp() then return boss.Way.Ghost() end
		return math.min(math.max(boss.Bar.Ghost(), boss.Bar.Fill()), arrival())
	end)

	-- The way is full and its boss is on its way.
	local isComing = derive(function(): boolean
		return not isBossUp() and boss.FullAt() ~= -math.huge
	end)

	-- The anticipation: from the way filling to the boss's arrival, 0 to 1, slow at first. Its release is the intro.
	local charge = derive(function(): number
		if not isComing() then return 0 end
		return Motion.Accelerate(Progress(state.Now(), boss.FullAt(), RoundCore.BOSS_ARRIVE_SECONDS))
	end)

	-- 1 as the way fills, and as it completes a segment, falling away.
	local full = derive(function(): number
		if not isComing() then return 0 end
		local k = Motion.Fade(state.Now(), boss.FullAt(), Timing.FLASH)
		return k * k
	end)

	local filled = derive(function(): number
		if isBossUp() then return 0 end
		local k = Motion.Fade(state.Now(), boss.FilledAt(), Timing.PUNCH)
		return k * k
	end)

	-- 1 on the fall's frame, falling away.
	local struck = derive(function(): number
		if not isFallen() then return 0 end
		local k = Motion.Fade(state.Now(), boss.DefeatedAt(), Timing.FLASH)
		return k * k
	end)

	-- 1 as a segment is emptied, falling away.
	local broke = derive(function(): number
		local k = Motion.Fade(state.Now(), boss.BrokeAt(), Timing.PUNCH)
		return k * k
	end)

	local flash, flare = BarJuice.Lights(state, boss.Bar)
	local look: TBarLook = {
		Mix = mix,
		Fill = fill,
		Ghost = ghost,
		GhostColor = function(): Color3
			if not isBossUp() then return GAINED end
			return if boss.Bar.IsHealing() then GIVEN else GHOST
		end,
		Strike = function(index: number): number
			local now = state.Now()
			local lit = 0
			if isBossUp() and now >= tickAt(index) then
				local k = Motion.Fade(now, tickAt(index), Timing.TICK)
				lit = 0.7 * k * k
			end
			if not isBossUp() and boss.Filled() == index then
				local k = Motion.Fade(now, boss.FilledAt(), Timing.BREAK)
				lit = math.max(lit, 0.9 * k * k)
			end
			if boss.Broken() ~= index then return lit end
			local k = Motion.Fade(now, boss.BrokeAt(), Timing.BREAK)
			return math.max(lit, 0.9 * k * k)
		end,
		Flash = flash,
		-- On the way, the head is lit by the kills pressing in.
		Flare = function(): number
			return if isBossUp() then flare() else boss.Surge()
		end,
		Sheen = derive(function(): number
			local now = state.Now()
			if not isBossUp() then return Progress(now, math.max(boss.FilledAt(), boss.FullAt()), Timing.SHEEN) end
			if isFallen() then return 0 end
			return Progress(now, boss.AppearedAt() + Timing.FILL_DELAY + Timing.FILL, Timing.SHEEN)
		end),
	}

	-- 1 hanging under the plate, 0 tucked up behind it. A cleared wave waits for a fall to be seen.
	local shown = derive(function(): number
		local now, at = state.Now(), state.PhaseAt()
		local current = phase()
		if current == "Fighting" then
			if state.PreviousPhase() == "Fighting" then return 1 end
			return Motion.OutBack(Progress(now, at, Timing.IN, Timing.IN_DELAY))
		end
		if current == "Preparing" and state.PreviousPhase() == "Fighting" then
			local leaves = if isBossUp() then math.max(at, boss.DefeatedAt() + Timing.TUCK_AFTER) else at
			return 1 - Motion.InBack(Progress(now, leaves, Timing.OUT))
		end
		return 0
	end)

	local size = derive(function(): Vector2
		return Layout.STRIP:Lerp(Boss.SIZE, mix())
	end)

	-- The fall, an emptied segment, a segment the way completed and the way full punch the strip: a reward moves. The
	-- kills coming in thump it gently, and a boss on its way pulls it in before the release.
	local punch = function(): number
		return 0.06 * struck()
			+ 0.025 * broke()
			+ 0.025 * filled()
			+ 0.05 * full()
			+ 0.012 * boss.Surge()
			- 0.035 * charge()
	end

	-- Its guards' shield is up: the share gives way to a mark a guard, lit while it stands.
	local isShielded = function(): boolean
		return isBossUp() and not isFallen() and boss.Guards() > 0
	end

	local tagText = function(): string
		if isComing() then return "INCOMING" end
		if not isBossUp() then return "NEXT BOSS" end
		if isFallen() then return "DEFEATED" end
		return if isShielded() then "SHIELDED" else "BOSS"
	end

	local tagHeight = function(): number
		return math.round(Lerp(Layout.TAG_HEIGHT, Boss.TAG_HEIGHT, mix()))
	end

	local tagSize = function(): number
		return math.round(Lerp(Layout.TAG_TEXT, Boss.TAG_TEXT, mix()))
	end

	local tagPop = derive(function(): number
		if isComing() then return 1 + 0.35 * full() end
		if not isFallen() then return 1 end
		local k = Motion.Fade(state.Now(), boss.DefeatedAt(), Timing.PUNCH)
		return 1 + 0.35 * k * k
	end)

	local nameSize = function(): number
		return math.round(Lerp(Layout.NAME_SIZE, Boss.NAME_SIZE, mix()))
	end

	-- With no panel to ring or strike at the fall, the bar takes its ring; and it stands in his brackets.
	local barExtras = {
		ring(function(): number
			return if isFallen() then Progress(state.Now(), boss.DefeatedAt(), Timing.RING) else 1
		end, FALL_REACH, Palette.Green, 0),
		Components.Brackets(nil, function()
			return 1 - 0.7 * mix()
		end, 14),
	}

	local drops = dropCards(state, { Mix = mix, IsFallen = isFallen })

	-- A window from the plate's bottom down, so the strip comes out from behind the plate.
	local windowTop = Layout.PLATE_TOP + Layout.PLATE_HEIGHT - 4
	local resting = Layout.TOP - windowTop
	return create("Frame")({
		Name = "BossWindow",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, windowTop),
		Size = UDim2.fromOffset(Boss.SIZE.X + 80, resting + Boss.SIZE.Y + 50),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = 2,
		Visible = function()
			return shown() > 0.001 and name() ~= ""
		end,
		body(mix, {
			Name = "Boss",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				local height = size().Y
				local top = Lerp(-(height + 10), resting, shown())
				return UDim2.new(0.5, 0, 0, math.round(top + height / 2))
			end,
			Size = function()
				return offset(size())
			end,
			create("UIScale")({
				Scale = function()
					return 1 + punch()
				end,
			}),

			Components.Card({ Accent = Palette.Pink, Tint = 0.3, GlowTransparency = 0.7 }, {
				Name = "Portrait",
				Position = function()
					return offset(Layout.PORTRAIT:Lerp(Boss.PORTRAIT, mix()))
				end,
				Size = function()
					local side = math.round(Lerp(Layout.PORTRAIT_SIZE, Boss.PORTRAIT_SIZE, mix()))
					return UDim2.fromOffset(side, side)
				end,
				-- The boss's bar shrinks it to nothing.
				Visible = function()
					return Lerp(Layout.PORTRAIT_SIZE, Boss.PORTRAIT_SIZE, mix()) >= 2
				end,
				ZIndex = 2,
				Components.Brackets(nil, nil, 21),
				Components.Picture(EIcons.ZombieKing, {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					-- The boss feeds on the kills, and rises as it comes.
					Size = function()
						local grow = 1 + 0.1 * boss.Surge() + 0.18 * charge()
						return Components.PictureBox(math.round(Lerp(Layout.CROWN, Boss.CROWN, mix()) * grow))
					end,
					ZIndex = 2,
				}),
			}),
			create("Frame")({
				Name = "Title",
				Position = function()
					return offset(Layout.TAG:Lerp(Boss.TAG, mix()))
				end,
				Size = function()
					local m = mix()
					local left = Lerp(Layout.TAG.X, Boss.TAG.X, m)
					local right = Lerp(Layout.ROW_RIGHT, Boss.ROW_RIGHT, m)
					local height = Lerp(Layout.NAME_SIZE, Boss.NAME_SIZE, m)
					return UDim2.new(1, -math.round(left + right), 0, math.round(height))
				end,
				BackgroundTransparency = 1,
				ZIndex = 3,
				create("UIListLayout")({
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, Layout.TAG_GAP),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
				create("UIPadding")({
					PaddingRight = function()
						return UDim.new(0, math.round(Layout.PERCENT_ROOM * mix()))
					end,
				}),
				-- The tag's room in the row, sized to its word by an unseen copy of it; the tag drawn over that pops from its
				-- centre (a list item cannot be anchored there).
				create("Frame")({
					Name = "Tag",
					LayoutOrder = 1,
					Size = function()
						return UDim2.fromOffset(0, tagHeight())
					end,
					AutomaticSize = Enum.AutomaticSize.X,
					BackgroundTransparency = 1,
					label({
						Name = "Measure",
						Size = UDim2.fromScale(0, 1),
						AutomaticSize = Enum.AutomaticSize.X,
						TextTransparency = 1,
						TextSize = tagSize,
						Text = tagText,
						create("UIPadding")({
							PaddingLeft = UDim.new(0, Layout.TAG_PAD),
							PaddingRight = UDim.new(0, Layout.TAG_PAD),
						}),
					}),
					label({
						Name = "Face",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.5),
						Size = UDim2.fromScale(1, 1),
						BackgroundTransparency = 0,
						BackgroundColor3 = function()
							if isFallen() then return Palette.GoBottom:Lerp(Palette.Green, 0.6) end
							return if isShielded() then Palette.GoBottom else Palette.Pink
						end,
						BorderSizePixel = 0,
						TextSize = tagSize,
						Text = tagText,
						create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
						create("UIScale")({ Scale = tagPop }),
					}),
				}),
				-- Takes what the tag leaves, so a long name truncates at the strip's edge.
				label({
					Name = "Name",
					LayoutOrder = 2,
					Size = function()
						return UDim2.fromOffset(0, nameSize())
					end,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextSize = nameSize,
					TextTruncate = Enum.TextTruncate.AtEnd,
					TextColor3 = function()
						return if isFallen() then DEFEATED_NAME else Palette.White
					end,
					Text = function()
						return string.upper(name())
					end,
					create("UIFlexItem")({ FlexMode = Enum.UIFlexMode.Fill }),
					inked(mix, Boss.NAME_SIZE),
				}),
			}),
			-- The boss's share, at the right end of the name's row or inside the bar's: counts up with the arrival, punches
			-- pink as a segment goes.
			label({
				Name = "Percent",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = function()
					local m = mix()
					local stripX = size().X - Layout.ROW_RIGHT - Layout.PERCENT_ROOM / 2
					local stripY = Layout.TAG.Y + Layout.NAME_SIZE / 2
					local x = Boss.BAR.X + Boss.BAR_SIZE.X - Layout.PERCENT_IN_BAR - Layout.PERCENT_ROOM / 2
					local y = Boss.BAR.Y + Boss.BAR_SIZE.Y / 2
					return UDim2.fromOffset(math.round(Lerp(stripX, x, m)), math.round(Lerp(stripY, y, m)))
				end,
				Size = UDim2.fromOffset(Layout.PERCENT_ROOM, Boss.NAME_SIZE),
				TextXAlignment = Enum.TextXAlignment.Right,
				TextSize = Boss.PERCENT_TEXT,
				ZIndex = 5,
				TextTransparency = function()
					if isShielded() then return 1 end
					return 1 - math.clamp((mix() - 0.5) * 2, 0, 1)
				end,
				TextColor3 = function()
					return Palette.White:Lerp(Palette.Pink, broke())
				end,
				Text = function()
					-- The chase can dip a hair under nothing as the last blow lands.
					return string.format("%.1f%%", 100 * math.max(fill(), 0))
				end,
				inked(mix, Boss.PERCENT_TEXT, function()
					return if isShielded() then 0 else math.clamp((mix() - 0.5) * 2, 0, 1)
				end),
				create("UIScale")({
					Scale = function()
						return 1 + 0.3 * broke()
					end,
				}),
			}),
			guardMarks(boss, isShielded),
			bar(state, look, barExtras),
			shares(state, mix),
			drops,
			-- The way full: the whole strip struck white, and a ring off it. A boss on its way charges it white. (A fall
			-- comes with no panel to strike: the bar takes its ring.)
			create("Frame")({
				Name = "Struck",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Palette.White,
				BorderSizePixel = 0,
				ZIndex = 9,
				BackgroundTransparency = function()
					return 1 - math.max(0.6 * full(), 0.5 * charge())
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
			}),
			ring(function()
				return if isComing() then Progress(state.Now(), boss.FullAt(), Timing.RING) else 1
			end, FALL_REACH, Palette.Pink, 0),
		}),
	})
end

return BossBar
