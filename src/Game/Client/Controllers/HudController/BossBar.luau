--!nonstrict
-- The boss strip under the wave plate (UIMatt.md, In-Game HUD, Boss Container) and the boss's bar it grows into. With
-- no boss up it is his strip exactly: NEXT BOSS, the name, and the way to that boss in four segments. When a boss
-- comes on the same pieces grow (one object, its states told apart by size, colour and light): the tag reads BOSS,
-- the segments become the boss's health with its share on the right, and the two who have taken the most off it
-- unfold under it. Every rect is in px at 1080; the strip's are his drawn ones.
--
-- What it does is BarJuice's chase on the boss's health, plus its own moments, each with its cue: the bar fills on
-- arrival a segment at a time, a segment emptied bursts, and a fall strikes the whole strip and stamps it DEFEATED
-- before it turns back into the way to the next one. Everything timed off the HUD's clock is derived, so a bar at
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

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress
local Lerp = Motion.Lerp

-- Each piece as his strip draws it, and as the boss's bar does. Px at 1080, x from the strip's left.
local Layout = table.freeze({
	-- The wave plate's top and height (Wave.luau), which the strip hangs under and comes out from behind.
	PLATE_TOP = 16,
	PLATE_HEIGHT = 88,
	TOP = 116,
	STRIP = Vector2.new(460, 76),
	BOSS = Vector2.new(620, 132),
	PORTRAIT = Vector2.new(11, 9),
	PORTRAIT_SIZE = 55,
	CROWN = 41,
	BOSS_PORTRAIT = Vector2.new(12, 12),
	BOSS_PORTRAIT_SIZE = 108,
	BOSS_CROWN = 74,
	-- The row of the tag, sized to its word, and the name after it.
	TAG = Vector2.new(82, 10),
	BOSS_TAG = Vector2.new(136, 12),
	TAG_HEIGHT = 24,
	BOSS_TAG_HEIGHT = 28,
	TAG_TEXT = 12,
	BOSS_TAG_TEXT = 15,
	TAG_PAD = 10,
	TAG_GAP = 7,
	NAME_SIZE = 26,
	BOSS_NAME_SIZE = 30,
	-- The row ends this far in from the strip's right.
	ROW_RIGHT = 12,
	BOSS_ROW_RIGHT = 16,
	BAR = Vector2.new(82, 50),
	BAR_SIZE = Vector2.new(354, 10),
	BOSS_BAR = Vector2.new(136, 50),
	BOSS_BAR_SIZE = Vector2.new(468, 24),
	SEGMENTS = 4,
	BAR_GAP = 7,
	-- The boss's share, at the right end of the name's row, and the room the name leaves it.
	PERCENT_TEXT = 28,
	PERCENT_ROOM = 104,
	-- The damage share: a line each for the two who have taken the most, one under the other, under the bar. Each is
	-- its rank, the name, a bar for the part, and the part as a number.
	SHARE_ROW = Vector2.new(136, 84),
	SHARE_HEIGHT = 16,
	SHARE_STEP = 20,
	SHARE_TEXT = 15,
	SHARE_GAP = 10,
	SHARE_RANK = 12,
	SHARE_NAME = 150,
	SHARE_BAR = 8,
	SHARE_PERCENT = 64,
	-- The cut at the fill's end.
	CUT = 3,
})

local SEGMENT = Color3.fromRGB(49, 44, 66)
-- What was just taken, behind the fill, and what is being given back.
local GHOST = Palette.White
local GIVEN = Palette.Green:Lerp(Palette.White, 0.55)
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
})

-- How far a ring grows past what throws it, in px.
local BREAK_REACH = 14
local FALL_REACH = 24

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
}

function BossBar.NewMemory(): TBossMemory
	return {
		DataId = 0,
		Chase = BarJuice.NewChase(0),
		Segments = 0,
		Rows = { { UserId = 0, Shown = 0, Sent = 0 }, { UserId = 0, Shown = 0, Sent = 0 } },
		FallEndsAt = -math.huge,
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

-- One frame of the bar: writes `bar` from `seen`. Returns the os.clock the HUD's clock must run until for what this
-- frame started (-math.huge for nothing).
function BossBar.Update(bar: Types.TBossBar, memory: TBossMemory, seen: TBossSeen, now: number, dt: number): number
	local runUntil = -math.huge
	local share = seen.Share
	if seen.DataId ~= 0 and seen.DataId ~= memory.DataId then
		memory.DataId = seen.DataId
		memory.Chase = BarJuice.NewChase(share)
		memory.Segments = math.ceil(share * Layout.SEGMENTS - 1e-6)
		for _, row in memory.Rows do
			row.UserId, row.Shown, row.Sent = 0, 0, 0
		end
		bar.Name(seen.Name)
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
	IsHealing: () -> boolean,
	-- 0 to 1 per segment: the white it is struck, lit as the arrival's fill passes it or emptied.
	Strike: (index: number) -> number,
	-- The newest blow's wash over the fill, and its light on the cut.
	Flash: () -> number,
	Flare: () -> number,
	-- The light run across the bar once it has filled.
	Sheen: () -> number,
}

local function bar(state: Types.THudState, look: TBarLook): Frame
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
				BackgroundColor3 = function()
					return if look.IsHealing() then GIVEN else GHOST
				end,
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
			ring(function()
				return if boss.Broken() == index then Progress(state.Now(), boss.BrokeAt(), Timing.RING) else 1
			end, BREAK_REACH, Palette.Pink, 0),
		})
	end

	local chipColor = function(): Color3
		return Palette.Pink
	end

	return create("Frame")({
		Name = "Bar",
		Position = function()
			return offset(Layout.BAR:Lerp(Layout.BOSS_BAR, look.Mix()))
		end,
		Size = function()
			return offset(Layout.BAR_SIZE:Lerp(Layout.BOSS_BAR_SIZE, look.Mix()))
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
	})
end

-- ============================== The damage share ==============================

-- The line for `rank` (1 the most damage), after its rank's number: the name ("YOU" for the local player, in green), a
-- bar for the part and the part as a number. Two who trade places slide past each other: the one going up is lit, the
-- one going down fades through the crossing so the two never print over each other.
local function shareLine(state: Types.THudState, rank: number, shown: () -> number, swapping: () -> number): Frame
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
			props,
		})
	end

	local top = Layout.SHARE_ROW.Y + (rank - 1) * Layout.SHARE_STEP
	-- Where it came from: the other line's place.
	local from = Layout.SHARE_ROW.Y + (2 - rank) * Layout.SHARE_STEP
	local left = Layout.SHARE_ROW.X + Layout.SHARE_RANK + Layout.SHARE_GAP
	return create("Frame")({
		Name = "Share",
		Position = function()
			return UDim2.fromOffset(left, math.round(Lerp(top, from, swapping())))
		end,
		Size = UDim2.new(1, -left - Layout.BOSS_ROW_RIGHT, 0, Layout.SHARE_HEIGHT),
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
			Size = UDim2.new(0, Layout.SHARE_NAME, 1, 0),
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

	local frames = table.create(4)
	for rank, line in boss.Shares do
		frames[rank] = shareLine(state, rank, shown, swapping)
		frames[rank + 2] = label({
			Name = "Rank",
			Position = UDim2.fromOffset(Layout.SHARE_ROW.X, Layout.SHARE_ROW.Y + (rank - 1) * Layout.SHARE_STEP),
			Size = UDim2.fromOffset(Layout.SHARE_RANK, Layout.SHARE_HEIGHT),
			FontFace = Font.DisplayBold,
			TextSize = Layout.SHARE_TEXT,
			TextColor3 = Palette.Lavender,
			ZIndex = 3,
			Text = tostring(rank),
			TextTransparency = function()
				return if line.Name() ~= "" then 1 - shown() else 1
			end,
		})
	end

	return frames
end

-- ============================== The strip ==============================

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

	-- With no boss up, the bar is the way to the next one: the waves of its cycle already cleared (none yet once the
	-- round's own boss is down).
	local cycle = function(): number
		local every = RoundCore.BOSS_EVERY
		return math.clamp((state.Round() - 1 - (state.NextBossRound() - every)) / every, 0, 1)
	end

	local fill = derive(function(): number
		if not isBossUp() then return cycle() end
		local intro = arrival()
		if intro <= 0 then return cycle() * (1 - mix()) end
		return math.min(boss.Bar.Fill(), intro)
	end)

	local ghost = derive(function(): number
		if not isBossUp() then return 0 end
		return math.min(math.max(boss.Bar.Ghost(), boss.Bar.Fill()), arrival())
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
		IsHealing = boss.Bar.IsHealing,
		Strike = function(index: number): number
			local now = state.Now()
			local lit = 0
			if isBossUp() and now >= tickAt(index) then
				local k = Motion.Fade(now, tickAt(index), Timing.TICK)
				lit = 0.7 * k * k
			end
			if boss.Broken() ~= index then return lit end
			local k = Motion.Fade(now, boss.BrokeAt(), Timing.BREAK)
			return math.max(lit, 0.9 * k * k)
		end,
		Flash = flash,
		Flare = flare,
		Sheen = derive(function(): number
			if not isBossUp() or isFallen() then return 0 end
			return Progress(state.Now(), boss.AppearedAt() + Timing.FILL_DELAY + Timing.FILL, Timing.SHEEN)
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
		return Layout.STRIP:Lerp(Layout.BOSS, mix())
	end)

	-- The fall and an emptied segment punch the strip: a reward moves.
	local punch = function(): number
		return 0.06 * struck() + 0.025 * broke()
	end

	local tagText = function(): string
		if not isBossUp() then return "NEXT BOSS" end
		return if isFallen() then "DEFEATED" else "BOSS"
	end

	local tagHeight = function(): number
		return math.round(Lerp(Layout.TAG_HEIGHT, Layout.BOSS_TAG_HEIGHT, mix()))
	end

	local tagSize = function(): number
		return math.round(Lerp(Layout.TAG_TEXT, Layout.BOSS_TAG_TEXT, mix()))
	end

	local tagPop = derive(function(): number
		if not isFallen() then return 1 end
		local k = Motion.Fade(state.Now(), boss.DefeatedAt(), Timing.PUNCH)
		return 1 + 0.35 * k * k
	end)

	local nameSize = function(): number
		return math.round(Lerp(Layout.NAME_SIZE, Layout.BOSS_NAME_SIZE, mix()))
	end

	-- A window from the plate's bottom down, so the strip comes out from behind the plate.
	local windowTop = Layout.PLATE_TOP + Layout.PLATE_HEIGHT - 4
	local resting = Layout.TOP - windowTop
	return create("Frame")({
		Name = "BossWindow",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, windowTop),
		Size = UDim2.fromOffset(Layout.BOSS.X + 80, resting + Layout.BOSS.Y + 50),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = 2,
		Visible = function()
			return shown() > 0.001 and name() ~= ""
		end,
		Components.Panel({ Brackets = 6 }, {
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
					return offset(Layout.PORTRAIT:Lerp(Layout.BOSS_PORTRAIT, mix()))
				end,
				Size = function()
					local side = math.round(Lerp(Layout.PORTRAIT_SIZE, Layout.BOSS_PORTRAIT_SIZE, mix()))
					return UDim2.fromOffset(side, side)
				end,
				ZIndex = 2,
				Components.Brackets(7, nil, 21),
				Components.Icon("Boss", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = function()
						return Components.GlyphBox(math.round(Lerp(Layout.CROWN, Layout.BOSS_CROWN, mix())))
					end,
					ImageColor3 = function()
						return Palette.Pink:Lerp(Palette.White, struck())
					end,
					ZIndex = 2,
				}),
			}),
			create("Frame")({
				Name = "Title",
				Position = function()
					return offset(Layout.TAG:Lerp(Layout.BOSS_TAG, mix()))
				end,
				Size = function()
					local m = mix()
					local left = Lerp(Layout.TAG.X, Layout.BOSS_TAG.X, m)
					local right = Lerp(Layout.ROW_RIGHT, Layout.BOSS_ROW_RIGHT, m)
					local height = Lerp(Layout.NAME_SIZE, Layout.BOSS_NAME_SIZE, m)
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
							return if isFallen() then Palette.GoBottom:Lerp(Palette.Green, 0.6) else Palette.Pink
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
				}),
			}),
			-- The boss's share, at the right end of the name's row: counts up with the arrival, punches pink as a
			-- segment goes.
			label({
				Name = "Percent",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = function()
					local m = mix()
					local right = Lerp(Layout.ROW_RIGHT, Layout.BOSS_ROW_RIGHT, m)
					local middle =
						Lerp(Layout.TAG.Y + Layout.NAME_SIZE / 2, Layout.BOSS_TAG.Y + Layout.BOSS_NAME_SIZE / 2, m)
					return UDim2.new(1, -math.round(right + Layout.PERCENT_ROOM / 2), 0, math.round(middle))
				end,
				Size = UDim2.fromOffset(Layout.PERCENT_ROOM, Layout.BOSS_NAME_SIZE),
				TextXAlignment = Enum.TextXAlignment.Right,
				TextSize = Layout.PERCENT_TEXT,
				ZIndex = 3,
				TextTransparency = function()
					return 1 - math.clamp((mix() - 0.5) * 2, 0, 1)
				end,
				TextColor3 = function()
					return Palette.White:Lerp(Palette.Pink, broke())
				end,
				Text = function()
					return string.format("%.1f%%", 100 * fill())
				end,
				create("UIScale")({
					Scale = function()
						return 1 + 0.3 * broke()
					end,
				}),
			}),
			bar(state, look),
			shares(state, mix),
			-- The fall: the whole strip struck white, and a ring off it.
			create("Frame")({
				Name = "Struck",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Palette.White,
				BorderSizePixel = 0,
				ZIndex = 9,
				BackgroundTransparency = function()
					return 1 - 0.75 * struck()
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
			}),
			ring(function()
				return if isFallen() then Progress(state.Now(), boss.DefeatedAt(), Timing.RING) else 1
			end, FALL_REACH, Palette.Green, 0),
		}),
	})
end

return BossBar
