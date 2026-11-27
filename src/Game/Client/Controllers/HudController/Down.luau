--!nonstrict
-- Being down, on the HUD (DownedController owns the down; the look is Assets/effects/death's): the fight's HUD steps
-- off (init), YOU DIED with the pink skull is dealt in the middle and flies up into the WAVE plate's place, where it
-- stamps down as a plate for as long as the player is down, saying under it what brings them back, and turns into
-- REVIVING as they are brought back; the spectate card where the gold and the hotbar were (the squadmate watched, their
-- health, the arrows), with the player's own big REVIVE over it; and, for a player standing, a chip by the boss strip
-- for each downed squadmate, with REVIVE to buy theirs. Every gesture here reads state.Down.Clock, written only while
-- down or just back up.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local Types = require(script.Parent.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress

-- The party invite card's bar track.
local BAR_TRACK = Color3.fromRGB(58, 50, 86)

-- Px at 1080, against the HUD's design root: x from the middle of the screen, y from its top (the spectate card's from
-- its bottom).
local Layout = table.freeze({
	-- YOU DIED in the middle: its centre's height, the skull, the words, the gap between them, and how far its row's
	-- middle stands over the group's (the row is 110 tall at the top of a 200 tall group).
	TITLE_Y = 410,
	TITLE_TEXT = 76,
	TITLE_SKULL = 78,
	TITLE_GAP = 18,
	TITLE_LINE = 24,
	TITLE_ROW = -45,
	-- The plate it becomes, on the WAVE plate's top and height (Wave's Layout), its skull, words and their gap; the
	-- line under it.
	PLATE_TOP = 16,
	PLATE_SIZE = Vector2.new(440, 88),
	PLATE_SKULL = 58,
	PLATE_TEXT = 54,
	PLATE_GAP = 14,
	LINE_TOP = 118,
	LINE_TEXT = 20,
	-- The spectate card where the gold and the hotbar were: its centre's height over the screen's bottom and its size,
	-- then its pieces from its top left.
	CARD_FROM_BOTTOM = 122,
	CARD_SIZE = Vector2.new(470, 92),
	TAG = Vector2.new(12, -12),
	TAG_HEIGHT = 24,
	TAG_TEXT = 14,
	TAG_PAD = 10,
	HEAD = Vector2.new(14, 12),
	HEAD_SIZE = 68,
	NAME = Vector2.new(98, 14),
	NAME_TEXT = 26,
	BAR = Vector2.new(98, 56),
	BAR_SIZE = Vector2.new(260, 12),
	HEALTH_TEXT = 17,
	-- The arrows either side of it, clear of its brackets.
	ARROW_SIZE = 60,
	ARROW_GAP = 34,
	ARROW_PICTURE = 24,
	-- The player's own REVIVE over the card, as big as the reference's: its centre's height over the screen's bottom
	-- (its bottom 16 px over the card's tag, clear of its brackets at a press's peak), its size, the heart and the word.
	REVIVE_FROM_BOTTOM = 238,
	REVIVE_SIZE = Vector2.new(320, 84),
	REVIVE_HEART = 46,
	REVIVE_GAP = 12,
	REVIVE_TEXT = 38,
	-- How far its ring grows past it.
	RING_REACH = 30,
	-- A downed squadmate's chip, left of the boss strip (its left edge is 232 px left of the middle): its right edge
	-- from the middle, the first one's top, how far apart, its size, and its pieces.
	CHIP_RIGHT = -252,
	CHIP_Y = 116,
	CHIP_PITCH = 50,
	CHIP_SIZE = Vector2.new(260, 42),
	CHIP_SKULL = 26,
	CHIP_TEXT = 17,
	CHIP_REVIVE_SIZE = Vector2.new(100, 30),
	CHIP_BUTTON_TEXT = 14,
	-- At most this many chips (a party of four has three others).
	CHIPS = 3,
	MARGIN = 60,
})

local Gesture = table.freeze({
	-- YOU DIED: dealt TITLE_AT after going down, up from RISE px as it fades in, the skull stamped down from
	-- STAMP_FROM a beat later. TITLE_UP after going down it flies up into the plate's place over FLY, shrinking to the
	-- plate's words at their stamp's start, its line gone over the first LINE_OUT and the words handing over to the
	-- plate's over the last HAND_OVER.
	TITLE_AT = 0.6,
	TITLE_UP = 2.05,
	TITLE_IN = 0.4,
	RISE = 24,
	STAMP_DELAY = 0.08,
	STAMP = 0.18,
	STAMP_FROM = 1.6,
	FLY = 0.36,
	LINE_OUT = 0.12,
	HAND_OVER = 0.06,
	-- The plate lands as the title arrives: stamped down from PLATE_STAMP_FROM, one white flash, one pink ring, its skull
	-- punched; the line under it rises LINE_RISE px in a beat later. It goes up and out as the body shows.
	PLATE_STAMP_FROM = 1.15,
	SKULL_PUNCH = 0.35,
	LINE_DELAY = 0.15,
	LINE_IN = 0.3,
	LINE_RISE = 10,
	PLATE_OUT = 0.25,
	PLATE_LIFT = 16,
	-- The revive arriving (the body starting to be built back): the line under the plate fades away over LINE_GONE,
	-- sinking LINE_SINK px; YOU DIED and its skull collapse into the plate's middle over COLLAPSE; there it flashes white,
	-- rings green and turns green over TURN, and REVIVING with its heart grows out of the middle over BLOOM, the heart
	-- stamped down from STAMP_FROM and beating as REVIVE's does.
	LINE_GONE = 1,
	LINE_SINK = 8,
	COLLAPSE = 0.2,
	TURN = 0.3,
	BLOOM = 0.3,
	-- The spectate card rises in once the camera has lifted off the body, its arrows dealt after it; a switch deals the
	-- head and name again with one flash. It goes as the rebuild starts.
	CARD_AT = 2.7,
	CARD_IN = 0.4,
	CARD_RISE = 30,
	ARROW_DELAY = 0.09,
	DEAL = 0.3,
	FROM = 0.6,
	SWAP_OUT = 0.15,
	SWAP_SLIDE = 22,
	FLASH = 0.2,
	FLASH_PEAK = 0.5,
	-- REVIVE grows in from nothing REVIVE_DELAY after the card starts in, over REVIVE_IN, and lands with one flash, one
	-- ring, the light across it and its heart stamped down from STAMP_FROM. Its light crosses it every ASK_EVERY seconds
	-- after, over CALL, the glow lifting; its heart beats lub-dub once every BEAT (DUB after the first, each beat over
	-- THUMP), the one idle motion, since it says what the button does.
	REVIVE_DELAY = 0.3,
	REVIVE_IN = 0.3,
	RING = 0.45,
	ASK_EVERY = 3,
	CALL = 0.7,
	BEAT = 1,
	DUB = 0.22,
	THUMP = 0.2,
	BEAT_SWELL = 0.12,
	DUB_SWELL = 0.07,
	-- Under the hand the heart grows HEART_RISE of its own with the button's rise (a picture rides its button's growth
	-- with only a little of its own).
	HEART_RISE = 0.06,
	-- A press goes through: a lighter flash, a ring, the heart punched HEART_PUNCH bigger and back over PUNCH.
	PRESS_FLASH = 0.4,
	HEART_PUNCH = 0.3,
	PUNCH = 0.3,
	-- The revive arriving (the body starting to be built back): a full flash, a ring, the brackets sealed round it,
	-- the heart punched, and the button swelling SWELL over the first SWELL_SHARE of REVIVE_OUT, then shrinking away.
	REVIVE_OUT = 0.45,
	SWELL = 0.08,
	SWELL_SHARE = 0.3,
	-- Gone with the down (a wipe), it shrinks away over AWAY.
	AWAY = 0.25,
	-- A chip slides in from the left and fades, and back out.
	CHIP_PERIOD = 0.3,
	CHIP_SLIDE = 30,
})

local Down = {}

local function label(props: { [any]: any }): TextLabel
	return create("TextLabel")({
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		FontFace = Font.Display,
		TextColor3 = Palette.White,
		ZIndex = 4,
		props,
	})
end

-- His flat tag over a card's top edge: `text` in white on `color`, sized to the words.
local function tag(state: Types.THudState, text: string, color: Color3, scale: () -> number): Frame
	local width = vide.source(0)
	return create("Frame")({
		Name = "Tag",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(Layout.TAG.X, Layout.TAG.Y + Layout.TAG_HEIGHT / 2),
		Size = function()
			return UDim2.fromOffset(width() + 2 * Layout.TAG_PAD, Layout.TAG_HEIGHT)
		end,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = 6,
		create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
		create("UIScale")({ Scale = scale }),
		label({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 1),
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, Layout.TAG_TEXT),
			TextSize = Layout.TAG_TEXT,
			ZIndex = 7,
			Text = text,
			-- TextBounds is in screen px, under the root's UIScale; the width is in design px.
			vide.changed("TextBounds", function(bounds: Vector2)
				width(math.ceil(bounds.X / math.max(vide.untrack(state.Scale), 0.01)))
			end),
		}),
	})
end

-- His dark key badge's frame, an ink face in a thin edge of `edge`, holding a picture.
local function plaque(edge: Color3, props: { [any]: any }): Frame
	return create("Frame")({
		BackgroundColor3 = edge,
		BorderSizePixel = 0,
		create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
		create("Frame")({
			Name = "Face",
			Position = UDim2.fromOffset(2, 2),
			Size = UDim2.new(1, -4, 1, -4),
			BackgroundColor3 = Palette.Ink,
			BorderSizePixel = 0,
			ZIndex = props.ZIndex,
			create("UICorner")({ CornerRadius = UDim.new(0, 1) }),
		}),
		props,
	})
end

-- A white flash over a whole piece, `amount` 0 (none) to 1.
local function flash(amount: () -> number, zIndex: number): Frame
	return create("Frame")({
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Palette.White,
		BorderSizePixel = 0,
		Visible = function()
			return amount() > 0.005
		end,
		BackgroundTransparency = function()
			return 1 - amount()
		end,
		ZIndex = zIndex,
		create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
	})
end

-- One outline of `color` (or a source of it) leaving its parent's rect as `life` runs 0 to 1, grown by RING_REACH px
-- at one weight. Faded, never turned Visible: an element turned Visible is drawn at its last layout for a frame.
local function ring(life: () -> number, color: Color3 | () -> Color3, zIndex: number): Frame
	return create("Frame")({
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = function()
			local grow = math.round(Layout.RING_REACH * Motion.Out(life()))
			return UDim2.new(1, 2 * grow, 1, 2 * grow)
		end,
		BackgroundTransparency = 1,
		ZIndex = zIndex,
		create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
		create("UIStroke")({
			Color = color,
			Thickness = 3,
			Transparency = function()
				local t = life()
				return if t <= 0 or t >= 1 then 1 else Motion.Lerp(0.1, 1, t)
			end,
		}),
	})
end

-- A white flash that peaked `age` seconds ago at `peak`, squared and short so it reads as a hit, not a pale button; 0
-- before it (Progress reads 0 there) and after.
local function flashOf(age: number, peak: number): number
	if age < 0 then return 0 end
	local fade = 1 - Progress(age, 0, Gesture.FLASH)
	return peak * fade * fade
end

-- A picture stamped down from `from` times its size onto 1 as `t` runs 0 to 1, landing fast.
local function stampDown(from: number, t: number): number
	return from - (from - 1) * t * t
end

-- A heart's beat, lub-dub, `age` seconds into beating: its swell over 1.
local function lubDub(age: number): number
	if age < 0 then return 0 end
	local phase = age % Gesture.BEAT
	return Gesture.BEAT_SWELL * Motion.Bump(phase / Gesture.THUMP)
		+ Gesture.DUB_SWELL * Motion.Bump((phase - Gesture.DUB) / Gesture.THUMP)
end

-- A picture's punch for a moment `age` seconds ago, falling from `peak` the same way over PUNCH.
local function punchOf(age: number, peak: number): number
	if age < 0 then return 0 end
	local fade = 1 - Progress(age, 0, Gesture.PUNCH)
	return peak * fade * fade
end

-- ============================== YOU DIED ==============================

-- Components.Ink on words that fade by their own transparency: the stroke is faded with them, or the letters' ink
-- stays as a dark blot while they go.
local function fadingInk(size: number, transparency: () -> number): UIStroke
	return create("UIStroke")({
		Color = Theme.Color.Ink,
		Thickness = math.max(1, math.round(size * Theme.INK_SHARE)),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Miter,
		Transparency = transparency,
	})
end

-- When the title has landed in the plate's place, from going down, and how long the plate's landing gestures last after
-- it. A clock held still past its gestures leaves every curve on it at rest: the down lasts a whole wave, and a clock
-- that kept counting would have them all worked out again every frame of it.
local TITLE_LANDS = Gesture.TITLE_UP + Gesture.FLY
local LANDING_SECONDS =
	math.max(Gesture.RING, Gesture.FLASH, Gesture.STAMP + Gesture.PUNCH, Gesture.LINE_DELAY + Gesture.LINE_IN)
-- The spectate card's deal, from going down.
local CARD_DEALT = Gesture.CARD_AT + 2 * Gesture.ARROW_DELAY + Gesture.DEAL

-- Seconds since the title landed in the plate's place, -1 before, held at LANDING_SECONDS after.
local function landedAge(since: number): number
	return if since < TITLE_LANDS then -1 else math.min(since - TITLE_LANDS, LANDING_SECONDS)
end

-- YOU DIED in the middle, then flying up into the plate's place: one element moving, so the eye follows it there.
local function title(state: Types.THudState): CanvasGroup
	local down = state.Down
	-- Held once it has landed: its gestures are over.
	local since = derive(function(): number
		return math.min(down.Clock() - down.At(), TITLE_LANDS)
	end)
	-- 0 to 1 over the flight, eased in and out.
	local fly = derive(function(): number
		local t = Progress(since(), Gesture.TITLE_UP, Gesture.FLY)
		return t * t * (3 - 2 * t)
	end)
	local shown = derive(function(): number
		local t = since()
		if t < Gesture.TITLE_UP then return Motion.Decelerate(Progress(t, Gesture.TITLE_AT, Gesture.TITLE_IN)) end
		return 1 - Progress(t, Gesture.TITLE_UP + Gesture.FLY - Gesture.HAND_OVER, Gesture.HAND_OVER)
	end)
	local lift = derive(function(): number
		return Gesture.RISE * (1 - Motion.Decelerate(Progress(since(), Gesture.TITLE_AT, Gesture.TITLE_IN)))
	end)
	-- Shrunk to the plate's words as they start their stamp, so the hand-over is the same size.
	local landScale = Layout.PLATE_TEXT * Gesture.PLATE_STAMP_FROM / Layout.TITLE_TEXT
	local scale = derive(function(): number
		return Motion.Lerp(1, landScale, fly())
	end)
	local stamp = derive(function(): number
		return Progress(since(), Gesture.TITLE_AT + Gesture.STAMP_DELAY, Gesture.STAMP)
	end)
	local lineGone = derive(function(): number
		return Progress(since(), Gesture.TITLE_UP, Gesture.LINE_OUT)
	end)
	-- The row's middle from the middle of the screen to the plate's, the group's centre following under its scale.
	local plateMiddle = Layout.PLATE_TOP + Layout.PLATE_SIZE.Y / 2

	return create("CanvasGroup")({
		Name = "DownTitle",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			local rowY = Motion.Lerp(Layout.TITLE_Y + lift() + Layout.TITLE_ROW, plateMiddle, fly())
			return UDim2.new(0.5, 0, 0, math.round(rowY - Layout.TITLE_ROW * scale()))
		end,
		Size = UDim2.fromOffset(900, 200),
		BackgroundTransparency = 1,
		Visible = function()
			return state.IsDown() and shown() > 0.005
		end,
		GroupTransparency = function()
			return 1 - shown()
		end,
		create("UIScale")({ Scale = scale }),
		create("Frame")({
			Name = "Row",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 110),
			BackgroundTransparency = 1,
			create("UIListLayout")({
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, Layout.TITLE_GAP),
			}),
			create("Frame")({
				LayoutOrder = 1,
				Size = UDim2.fromOffset(Layout.TITLE_SKULL, Layout.TITLE_SKULL),
				BackgroundTransparency = 1,
				Components.Picture(EIcons.Skull, {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = Components.PictureBox(Layout.TITLE_SKULL),
					ImageColor3 = Palette.Pink,
					ImageTransparency = function()
						return if stamp() <= 0 then 1 else 0
					end,
					create("UIScale")({
						Scale = function()
							return stampDown(Gesture.STAMP_FROM, stamp())
						end,
					}),
				}),
			}),
			label({
				LayoutOrder = 2,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, Layout.TITLE_TEXT),
				TextSize = Layout.TITLE_TEXT,
				Text = "YOU DIED",
				Components.Ink(Layout.TITLE_TEXT),
			}),
		}),
		label({
			Name = "Line",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 112),
			Size = UDim2.fromOffset(900, Layout.TITLE_LINE),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextSize = Layout.TITLE_LINE,
			TextColor3 = Palette.Lavender,
			TextTransparency = lineGone,
			Text = "Your squad fights on. Watch them while you wait.",
			fadingInk(Layout.TITLE_LINE, lineGone),
		}),
	})
end

-- ============================== The plate ==============================

-- One row of the plate: a picture and a word, centred, grown from its middle by `scale` (0 to 1 and over).
local function plateRow(
	name: string,
	picture: string,
	text: string,
	scale: () -> number,
	pictureScale: () -> number,
	tint: Color3?
): Frame
	return create("Frame")({
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, Layout.PLATE_SIZE.Y),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Visible = function()
			return scale() > 0.01
		end,
		create("UIScale")({
			Scale = function()
				return math.max(scale(), 0.01)
			end,
		}),
		create("UIListLayout")({
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, Layout.PLATE_GAP),
		}),
		create("Frame")({
			LayoutOrder = 1,
			Size = UDim2.fromOffset(Layout.PLATE_SKULL, Layout.PLATE_SKULL),
			BackgroundTransparency = 1,
			Components.Picture(picture, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = Components.PictureBox(Layout.PLATE_SKULL),
				ImageColor3 = tint,
				ZIndex = 4,
				create("UIScale")({ Scale = pictureScale }),
			}),
		}),
		label({
			LayoutOrder = 2,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, Layout.PLATE_TEXT),
			TextSize = Layout.PLATE_TEXT,
			Text = text,
		}),
	})
end

-- Where WAVE n stood, for as long as the player is down: YOU DIED, and under it what brings them back. The revive
-- turns it into REVIVING in place: one plate changing what it says, never a second one over it.
local function plate(state: Types.THudState): Frame
	local down = state.Down
	-- Never down yet, -inf: an infinite age would read as long landed.
	local since = derive(function(): number
		local at = down.At()
		if at == -math.huge then return -math.huge end
		return down.Clock() - at
	end)
	local isStanding = derive(function(): boolean
		return down.StoodAt() > down.At()
	end)
	-- Out as the body shows: faded and lifted.
	local gone = derive(function(): number
		if not isStanding() then return 0 end
		return Progress(down.Clock(), down.StoodAt(), Gesture.PLATE_OUT)
	end)
	local landed = derive(function(): number
		return landedAge(since())
	end)
	-- Seconds since the revive arrived, -1 before. Read before the clock, so a plate at rest is not worked out again
	-- every frame for a moment that has not come.
	local revived = derive(function(): number
		local at = down.RebuildAt()
		if at < down.At() then return -1 end
		return down.Clock() - at
	end)
	-- Seconds since YOU DIED met in the middle and REVIVING started out of it, -1 before.
	local merged = derive(function(): number
		local age = revived()
		return if age < Gesture.COLLAPSE then -1 else age - Gesture.COLLAPSE
	end)
	local shown = derive(function(): number
		if landed() < 0 then return 0 end
		return 1 - gone()
	end)
	local stamped = derive(function(): number
		local age = landed()
		if age < 0 then return Gesture.PLATE_STAMP_FROM end
		return stampDown(Gesture.PLATE_STAMP_FROM, Progress(age, 0, Gesture.STAMP))
	end)
	local whiteFlash = derive(function(): number
		return math.max(flashOf(landed(), 0.8), flashOf(merged(), 0.9))
	end)
	-- The ring of the latest moment: the landing, then the merge.
	local ringLife = derive(function(): number
		local age = merged()
		if age < 0 then age = landed() end
		return if age < 0 then 0 else Progress(age, 0, Gesture.RING)
	end)
	local ringColor = derive(function(): Color3
		return if merged() >= 0 then Palette.Green else Palette.Pink
	end)
	local heal = derive(function(): number
		local age = merged()
		return if age < 0 then 0 else Motion.Out(Progress(age, 0, Gesture.TURN))
	end)
	local accent = derive(function(): Color3
		return Palette.Pink:Lerp(Palette.Green, heal())
	end)
	local deadScale = derive(function(): number
		local age = revived()
		if age < 0 then return 1 end
		return 1 - Motion.Accelerate(Progress(age, 0, Gesture.COLLAPSE))
	end)
	local skull = derive(function(): number
		return 1 + punchOf(landed() - Gesture.STAMP, Gesture.SKULL_PUNCH)
	end)
	local reviveScale = derive(function(): number
		local age = merged()
		return if age < 0 then 0 else Motion.Decelerate(Progress(age, 0, Gesture.BLOOM))
	end)
	local heart = derive(function(): number
		local age = merged()
		if age < 0 then return 1 end
		local landing = stampDown(Gesture.STAMP_FROM, Progress(age, Gesture.BLOOM * 0.5, Gesture.STAMP))
		return landing + lubDub(age - Gesture.BLOOM * 0.5 - Gesture.STAMP)
	end)
	local line = derive(function(): number
		local age = landed()
		if age < 0 then return 0 end
		local fading = revived()
		local kept = if fading < 0 then 1 else 1 - Motion.Out(Progress(fading, 0, Gesture.LINE_GONE))
		return Motion.Decelerate(Progress(age, Gesture.LINE_DELAY, Gesture.LINE_IN)) * kept * (1 - gone())
	end)
	local lineGone = derive(function(): number
		return 1 - line()
	end)
	local lineDrop = derive(function(): number
		local rise = Gesture.LINE_RISE
			* (1 - Motion.Decelerate(Progress(landed(), Gesture.LINE_DELAY, Gesture.LINE_IN)))
		local fading = revived()
		local sink = if fading < 0 then 0 else Gesture.LINE_SINK * Motion.Out(Progress(fading, 0, Gesture.LINE_GONE))
		return math.round(rise + sink)
	end)
	local size = Layout.PLATE_SIZE
	local lift = function(): number
		return -math.round(Gesture.PLATE_LIFT * Motion.Accelerate(gone()))
	end

	return create("Frame")({
		Name = "DownPlate",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = function()
			return shown() > 0.005 or line() > 0.005
		end,
		Position = function()
			return UDim2.fromOffset(0, lift())
		end,
		create("Frame")({
			Name = "Holder",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, Layout.PLATE_TOP + size.Y / 2),
			Size = UDim2.fromOffset(size.X + 2 * Layout.MARGIN, size.Y + 2 * Layout.MARGIN),
			BackgroundTransparency = 1,
			Components.FadeGroup("Content", shown, { Size = UDim2.fromScale(1, 1) }, {
				Components.Card({
					Accent = accent,
					Tint = 0.5,
					Marks = true,
					Brackets = true,
				}, {
					Name = "Plate",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromOffset(size.X, size.Y),
					create("UIScale")({ Scale = stamped }),
					plateRow("Died", EIcons.Skull, "YOU DIED", deadScale, skull, Palette.Pink),
					plateRow("Reviving", EIcons.Revive, "REVIVING", reviveScale, heart),
					flash(whiteFlash, 9),
					ring(ringLife, ringColor, 2),
				}),
			}),
		}),
		label({
			Name = "Line",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = function()
				return UDim2.new(0.5, 0, 0, Layout.LINE_TOP + lineDrop())
			end,
			Size = UDim2.fromOffset(size.X + 200, Layout.LINE_TEXT),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextSize = Layout.LINE_TEXT,
			TextTransparency = lineGone,
			TextColor3 = Palette.Lavender,
			Text = "Back when the wave is cleared",
			fadingInk(Layout.LINE_TEXT, lineGone),
		}),
	})
end

-- ============================== Spectating ==============================

-- An arrow either side of the card: his violet slab and the arrow picture. Pressed only by hand: no key steps through
-- the squad.
local function arrowButton(
	actions: Types.TActions,
	isLeft: boolean,
	dealt: () -> number,
	isLive: () -> boolean
): TextButton
	local hand = Hand.React("Operate")
	local size = Layout.ARROW_SIZE
	local x = (if isLeft then -1 else 1) * (Layout.CARD_SIZE.X / 2 + Layout.ARROW_GAP + size / 2)
	local step = if isLeft then -1 else 1

	return Components.Button({
		Name = if isLeft then "Previous" else "Next",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, x, 1, -Layout.CARD_FROM_BOTTOM),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		Interactable = isLive,
		Activated = function()
			hand.Commit()
			actions.Spectate(step)
		end,
		hand.Events,
		create("UIScale")({
			Scale = function()
				return math.max((Gesture.FROM + (1 - Gesture.FROM) * dealt()) * hand.Scale(), 0.01)
			end,
		}),
		Components.Slab({
			Kind = "Violet",
			Marks = true,
			Brackets = hand.Rise,
			GlowTransparency = function()
				return 0.6 - 0.35 * hand.Light()
			end,
		}, {
			Name = "Slab",
			Size = UDim2.fromScale(1, 1),
			ZIndex = 5,
			Hand.WashLayer(hand, 7, 3),
			Components.Picture(EIcons.Arrow, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = Components.PictureBox(Layout.ARROW_PICTURE),
				Rotation = if isLeft then 180 else 0,
				ZIndex = 6,
			}),
		}),
	}) :: TextButton
end

local function spectateCard(state: Types.THudState, actions: Types.TActions): Frame
	local down = state.Down
	-- Held once the card is dealt: its gestures are over.
	local since = derive(function(): number
		return math.min(down.Clock() - down.At(), CARD_DEALT)
	end)
	local isUp = derive(function(): boolean
		return state.IsDown() and not down.IsRebuilding() and down.Watched() ~= ""
	end)
	-- In once the camera has lifted off the body (or as a squadmate first stands to be watched), out as it goes.
	local shown = Hand.Spring(function()
		return if isUp() and since() >= Gesture.CARD_AT then 1 else 0
	end, Gesture.CARD_IN, 1)
	local leftDealt = derive(function(): number
		return Motion.Decelerate(Progress(since(), Gesture.CARD_AT + Gesture.ARROW_DELAY, Gesture.DEAL))
	end)
	local rightDealt = derive(function(): number
		return Motion.Decelerate(Progress(since(), Gesture.CARD_AT + 2 * Gesture.ARROW_DELAY, Gesture.DEAL))
	end)
	local headDealt = derive(function(): number
		return Motion.Decelerate(Progress(since(), Gesture.CARD_AT + 0.12, Gesture.DEAL))
	end)
	-- How far the watched one's head and name have come in: -1 to 0 as the old one slides out, then 0 to 1 in.
	local swap = derive(function(): number
		local t = down.Clock() - down.SwitchedAt()
		if t < 0 then return 1 end
		if t < Gesture.SWAP_OUT then return -Motion.Accelerate(Progress(t, 0, Gesture.SWAP_OUT)) end
		return Motion.Decelerate(Progress(t, Gesture.SWAP_OUT, Gesture.DEAL))
	end)
	local cardFlash = derive(function(): number
		local t = down.Clock() - down.SwitchedAt() - Gesture.SWAP_OUT
		if t < 0 then return 0 end
		local f = Progress(t, 0, Gesture.FLASH)
		return Gesture.FLASH_PEAK * (1 - f) * (1 - f)
	end)
	local function swapOffset(): number
		local s = swap()
		return if s < 0 then s * Gesture.SWAP_SLIDE else (1 - s) * Gesture.SWAP_SLIDE
	end
	local function swapTransparency(): number
		local s = swap()
		return if s < 0 then -s else 1 - s
	end
	local size = Layout.CARD_SIZE

	return create("Frame")({
		Name = "Spectate",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = function()
			return shown() > 0.005
		end,
		Position = function()
			return UDim2.fromOffset(0, math.round(Gesture.CARD_RISE * (1 - shown())))
		end,
		Components.FadeGroup("Content", shown, { Size = UDim2.fromScale(1, 1) }, {
			Components.Card({
				Accent = Palette.Violet,
				Tint = 0.3,
				Marks = true,
				Brackets = true,
			}, {
				Name = "Card",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 1, -Layout.CARD_FROM_BOTTOM),
				Size = UDim2.fromOffset(size.X, size.Y),
				ZIndex = 3,
				tag(state, "SPECTATING", Palette.Violet, headDealt),
				plaque(Palette.Violet, {
					Name = "Head",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(
						Layout.HEAD.X + Layout.HEAD_SIZE / 2,
						Layout.HEAD.Y + Layout.HEAD_SIZE / 2
					),
					Size = UDim2.fromOffset(Layout.HEAD_SIZE, Layout.HEAD_SIZE),
					ZIndex = 5,
					Components.Picture(EIcons.Player, {
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = function()
							return UDim2.new(0.5, math.round(swapOffset() * 0.5), 0.5, 0)
						end,
						Size = Components.PictureBox(Layout.HEAD_SIZE - 12),
						ImageTransparency = swapTransparency,
						ZIndex = 6,
					}),
				}),
				label({
					Name = "Name",
					Position = function()
						return UDim2.fromOffset(Layout.NAME.X + math.round(swapOffset()), Layout.NAME.Y)
					end,
					Size = UDim2.fromOffset(330, Layout.NAME_TEXT),
					TextSize = Layout.NAME_TEXT,
					TextTruncate = Enum.TextTruncate.AtEnd,
					TextTransparency = swapTransparency,
					Text = down.Watched,
				}),
				create("Frame")({
					Name = "Track",
					Position = UDim2.fromOffset(Layout.BAR.X, Layout.BAR.Y),
					Size = UDim2.fromOffset(Layout.BAR_SIZE.X, Layout.BAR_SIZE.Y),
					BackgroundColor3 = BAR_TRACK,
					BorderSizePixel = 0,
					ZIndex = 4,
					create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
					create("Frame")({
						Name = "Fill",
						Size = function()
							local max = down.WatchedMax()
							local share = if max > 0 then math.clamp(down.WatchedHealth() / max, 0, 1) else 0
							local s = swap()
							local filled = if s < 0 then share else share * s
							return UDim2.fromOffset(math.round(Layout.BAR_SIZE.X * filled), Layout.BAR_SIZE.Y)
						end,
						BackgroundColor3 = Palette.Green,
						BorderSizePixel = 0,
						ZIndex = 5,
						create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
					}),
				}),
				label({
					Name = "Health",
					Position = UDim2.fromOffset(Layout.BAR.X + Layout.BAR_SIZE.X + 14, Layout.BAR.Y - 4),
					Size = UDim2.fromOffset(90, 20),
					TextSize = Layout.HEALTH_TEXT,
					TextTransparency = swapTransparency,
					AutoLocalize = false,
					Text = function()
						return `{math.ceil(down.WatchedHealth())}/{math.ceil(down.WatchedMax())}`
					end,
				}),
				flash(cardFlash, 9),
			}),
			arrowButton(actions, true, leftDealt, isUp),
			arrowButton(actions, false, rightDealt, isUp),
		}),
	})
end

-- ============================== Your REVIVE ==============================

-- The player's own REVIVE (the Robux revive during a run), big and green over the spectate card where the eye already
-- is. It is the down's one call to act, so it lands as a reward does and goes as one: grown in with a flash, a ring
-- and the heart stamped; a press flashes and rings; the revive itself seals its brackets, flashes it white and swells
-- it away. The beats are curves of Down.Clock off their stamps, and a moment not come yet reads no clock.
local function reviveButton(state: Types.THudState, actions: Types.TActions): TextButton
	local down = state.Down
	local size = Layout.REVIVE_SIZE
	local inAt = Gesture.CARD_AT + Gesture.REVIVE_DELAY
	local landAt = inAt + Gesture.REVIVE_IN
	local pressedAt = vide.source(-math.huge)
	local since = derive(function(): number
		return down.Clock() - down.At()
	end)
	-- Seconds since the body started being built back, -1 before (a rebuild stamped before this down is the last one's).
	local revivedAge = derive(function(): number
		local at = down.RebuildAt()
		if at < down.At() then return -1 end
		return down.Clock() - at
	end)
	local isRevived = derive(function(): boolean
		return down.RebuildAt() >= down.At()
	end)
	local isLive = derive(function(): boolean
		return state.CanQuickRevive and state.IsDown() and not isRevived() and since() >= landAt
	end)
	local hand = Hand.React("Operate", isLive)
	local pressAge = derive(function(): number
		local at = pressedAt()
		if at < down.At() then return -1 end
		return down.Clock() - at
	end)
	-- Away with the down when it ends without a revive (a wipe).
	local away = Hand.Spring(function()
		return if state.IsDown() then 0 else 1
	end, Gesture.AWAY, 1)
	local grown = derive(function(): number
		local gone = revivedAge()
		if gone < 0 then return Motion.Decelerate(Progress(since(), inAt, Gesture.REVIVE_IN)) end
		-- Revived: from as far as it had come (nothing, if the revive beat it in), swelled, then shrunk away.
		local arrived = Motion.Decelerate(Progress(down.RebuildAt() - down.At(), inAt, Gesture.REVIVE_IN))
		local t = Progress(gone, 0, Gesture.REVIVE_OUT)
		if t < Gesture.SWELL_SHARE then return arrived * (1 + Gesture.SWELL * Motion.Out(t / Gesture.SWELL_SHARE)) end
		local shrink = Motion.Accelerate((t - Gesture.SWELL_SHARE) / (1 - Gesture.SWELL_SHARE))
		return arrived * (1 + Gesture.SWELL) * (1 - shrink)
	end)
	local scale = derive(function(): number
		return grown() * (1 - away())
	end)
	local whiteFlash = derive(function(): number
		local landing = if since() < landAt then 0 else flashOf(since() - landAt, 1)
		return math.max(landing, flashOf(pressAge(), Gesture.PRESS_FLASH), flashOf(revivedAge(), 1))
	end)
	-- The ring of the latest moment: the landing, a press or the revive.
	local ringLife = derive(function(): number
		local age = since() - landAt
		local press = pressAge()
		if press >= 0 then age = math.min(age, press) end
		local revived = revivedAge()
		if revived >= 0 then age = math.min(age, revived) end
		if age < 0 then return 0 end
		return Progress(age, 0, Gesture.RING)
	end)
	-- The light across it: once as it lands, then every ASK_EVERY while it can be pressed; 1 at rest.
	local call = derive(function(): number
		local t = since() - landAt
		if t < 0 or isRevived() then return 1 end
		return math.clamp((t % Gesture.ASK_EVERY) / Gesture.CALL, 0, 1)
	end)
	-- Stamped down as the slab grows its last way, landing with it: stamped after, the word stood off an empty slot.
	local stamp = derive(function(): number
		return Progress(since(), landAt - Gesture.STAMP, Gesture.STAMP)
	end)
	local heart = derive(function(): number
		local s = stamp()
		local stamped = stampDown(Gesture.STAMP_FROM, s)
		local punch = math.max(punchOf(pressAge(), Gesture.HEART_PUNCH), punchOf(revivedAge(), Gesture.HEART_PUNCH))
		local beat = 0
		if not isRevived() and s >= 1 then beat = lubDub(since() - landAt) end
		return stamped + punch + beat + Gesture.HEART_RISE * hand.Rise()
	end)

	return Components.Button({
		Name = "Revive",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 1, -Layout.REVIVE_FROM_BOTTOM),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Visible = function()
			return state.CanQuickRevive and scale() > 0.005
		end,
		Interactable = isLive,
		Activated = function()
			if not isLive() then return end
			hand.Commit()
			pressedAt(down.Clock())
			actions.QuickRevive(nil)
		end,
		hand.Events,
		create("UIScale")({
			Scale = function()
				return math.max(scale() * hand.Scale(), 0.01)
			end,
		}),
		Components.Slab({
			Kind = "Go",
			Marks = true,
			Brackets = hand.Rise,
			BracketsClosed = isRevived,
			GlowTransparency = function()
				if isRevived() then return 0.2 end
				return 0.55 - 0.3 * math.max(hand.Light(), Motion.Bump(call()))
			end,
		}, {
			Name = "Slab",
			Size = UDim2.fromScale(1, 1),
			ZIndex = 5,
			Hand.WashLayer(hand, 3, 3),
			Components.Sheen(Hand.Sheen(hand, call), 3, size.X / size.Y),
			create("Frame")({
				Name = "Word",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, Layout.REVIVE_HEART),
				BackgroundTransparency = 1,
				ZIndex = 6,
				create("UIListLayout")({
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, Layout.REVIVE_GAP),
				}),
				create("Frame")({
					LayoutOrder = 1,
					Size = UDim2.fromOffset(Layout.REVIVE_HEART, Layout.REVIVE_HEART),
					BackgroundTransparency = 1,
					Components.Picture(EIcons.Revive, {
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.5),
						Size = Components.PictureBox(Layout.REVIVE_HEART),
						ImageTransparency = function()
							return if stamp() <= 0 then 1 else 0
						end,
						ZIndex = 6,
						create("UIScale")({ Scale = heart }),
					}),
				}),
				Components.Tracked("REVIVE", Layout.REVIVE_TEXT, 3, Font.Display, {
					LayoutOrder = 2,
					ZIndex = 6,
				}),
			}),
			flash(whiteFlash, 9),
		}),
		ring(ringLife, Palette.Green, 4),
	}) :: TextButton
end

-- ============================== A downed squadmate's chip ==============================

-- The `index`th downed squadmate, for a player standing: a skull, the name, and REVIVE to buy theirs.
local function chip(state: Types.THudState, actions: Types.TActions, index: number): Frame
	local hand = Hand.React("Operate")
	local player = derive(function(): Player?
		if state.IsDown() then return nil end
		return state.Downed()[index]
	end)
	-- The last one shown, kept while the chip slides out.
	local shownPlayer: Player? = nil
	local name = derive(function(): string
		local current = player()
		if current then shownPlayer = current end
		return if shownPlayer then shownPlayer.DisplayName else ""
	end)
	local shown = Hand.Spring(function()
		return if player() then 1 else 0
	end, Gesture.CHIP_PERIOD, 1)
	local size = Layout.CHIP_SIZE
	local button = Layout.CHIP_REVIVE_SIZE

	return create("Frame")({
		Name = `Downed{index}`,
		AnchorPoint = Vector2.new(1, 0),
		Position = function()
			return UDim2.new(
				0.5,
				Layout.CHIP_RIGHT + Layout.MARGIN - math.round(Gesture.CHIP_SLIDE * (1 - shown())),
				0,
				Layout.CHIP_Y + (index - 1) * Layout.CHIP_PITCH - Layout.MARGIN
			)
		end,
		Size = UDim2.fromOffset(size.X + 2 * Layout.MARGIN, size.Y + 2 * Layout.MARGIN),
		BackgroundTransparency = 1,
		Visible = function()
			return shown() > 0.005
		end,
		Components.FadeGroup("Content", shown, { Size = UDim2.fromScale(1, 1) }, {
			Components.Panel({ Stroke = Palette.Pink, Brackets = true }, {
				Name = "Chip",
				Position = UDim2.fromOffset(Layout.MARGIN, Layout.MARGIN),
				Size = UDim2.fromOffset(size.X, size.Y),
				Components.Picture(EIcons.Skull, {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(10 + Layout.CHIP_SKULL / 2, size.Y / 2),
					Size = Components.PictureBox(Layout.CHIP_SKULL),
					ImageColor3 = Palette.Pink,
					ZIndex = 4,
				}),
				label({
					Position = UDim2.fromOffset(18 + Layout.CHIP_SKULL, 0),
					Size = UDim2.fromOffset(size.X - Layout.CHIP_SKULL - button.X - 40, size.Y),
					TextSize = Layout.CHIP_TEXT,
					TextTruncate = Enum.TextTruncate.AtEnd,
					Text = name,
				}),
				Components.Button({
					Name = "Revive",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(size.X - 8 - button.X / 2, size.Y / 2),
					Size = UDim2.fromOffset(button.X, button.Y),
					BackgroundTransparency = 1,
					ZIndex = 5,
					Visible = state.CanQuickRevive,
					Interactable = function()
						return player() ~= nil
					end,
					Activated = function()
						local current = player()
						if not current then return end
						hand.Commit()
						actions.QuickRevive(current)
					end,
					hand.Events,
					create("UIScale")({ Scale = hand.Scale }),
					Components.Slab({
						Kind = "Go",
						Marks = true,
						Brackets = hand.Rise,
						GlowTransparency = function()
							return 0.6 - 0.3 * hand.Light()
						end,
					}, {
						Name = "Slab",
						Size = UDim2.fromScale(1, 1),
						ZIndex = 5,
						Hand.WashLayer(hand, 3, 3),
						Components.Tracked("REVIVE", Layout.CHIP_BUTTON_TEXT, 2, Font.Display, {
							AnchorPoint = Vector2.new(0.5, 0.5),
							Position = UDim2.fromScale(0.5, 0.5),
							ZIndex = 6,
						}),
					}),
				}),
			}),
		}),
	})
end

function Down.Build(state: Types.THudState, actions: Types.TActions): { Instance }
	local chips = table.create(Layout.CHIPS)
	for index = 1, Layout.CHIPS do
		chips[index] = chip(state, actions, index)
	end

	return {
		title(state),
		plate(state),
		spectateCard(state, actions),
		reviveButton(state, actions),
		chips,
	}
end

return Down
