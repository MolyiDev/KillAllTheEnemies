--!nonstrict
-- The tag over a teammate who is picking an upgrade: a chip on top of where the health bar stands over a head, with a
-- fan of three cards rippling through, PICKING beside it and the light crossing it now and then. As they take a card
-- it thumps, throws a ring and goes the card's rarity for a moment; when they are done it shrinks away. Nothing with
-- a number on it, and no Highlight or bubble: the tag alone says the body cannot be hurt and is not playing. px are
-- design px at 1080; the billboard draws in screen pixels, so it takes the HUD's scale by hand.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local UpgradesCore = require(ReplicatedStorage.Shared.Core.UpgradesCore)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress

local TAU = 2 * math.pi

local Layout = table.freeze({
	CHIP = Vector2.new(136, 34),
	-- The chip's ink lets a little of the world through.
	CHIP_TRANSPARENCY = 0.08,
	-- The chip's middle this far over the bar's: half the bar's 22, a gap, half the chip.
	LIFT = 11 + 7 + 17,
	-- Room round the chip inside the billboard, which clips: for the pop, the thump and the ring.
	ROOM = 30,
	RIM = 2,
	CORNER = 6,
	-- The fan: each card's size, where the middle card's foot is (from the chip's left, and under its middle), how far
	-- under that the cards turn about, and the spread between two (radians).
	FAN_CARD = Vector2.new(13, 18),
	FAN_FOOT = Vector2.new(29, 9),
	FAN_PIVOT_DROP = 14,
	FAN_SPREAD = 0.36,
	LABEL_X = 56,
	LABEL_TEXT = 17,
})

local Timing = table.freeze({
	-- In: it pops from small, overshooting a little, and fades in faster than it grows.
	POP = 0.34,
	FADE_IN = 0.16,
	POP_FROM = 0.45,
	-- Out: it shrinks as it fades, accelerating away.
	OUT = 0.26,
	OUT_SHRINK = 0.4,
	-- The fan's ripple: once a second, each card lifting in turn.
	RIPPLE_RATE = 0.95,
	RIPPLE_SHARE = 0.38,
	RIPPLE_STAGGER = 0.17,
	RIPPLE_LIFT = 4,
	-- The light across the chip, every this long.
	SHEEN_PERIOD = 2.4,
	SHEEN = 0.7,
	-- Life while it waits: a slow bob of a px and a half.
	BOB_RATE = 0.8,
	BOB = 1.5,
	-- A card taken: the thump, the fan thrown open, the ring, the rim's flash of the rarity and its hold after.
	THUMP = 0.36,
	THUMP_SCALE = 0.24,
	FLING = 0.5,
	FLING_SPREAD = 0.2,
	RING = 0.5,
	RING_GROW = 0.35,
	RIM_FLASH = 0.6,
	RIM_HOLD = 0.55,
	-- Past the show, how long the word that the pick is over may take to arrive.
	PICK_GRACE = 0.5,
})

local RIM_COLOR = Color3.new()
local CARD_BACK = Palette.Lavender

-- What a tag is told (UpgradePickController writes them). The stamps are os.clock; EndedAt is math.huge until the
-- pick is over.
export type TTagState = {
	Adornee: vide.Source<BasePart?>,
	Clock: vide.Source<number>,
	ShownAt: vide.Source<number>,
	PickedAt: vide.Source<number>,
	PickedColor: vide.Source<Color3>,
	EndedAt: vide.Source<number>,
}

local PickingTag = {}

-- Where the tag stands over the root: the head's middle is 1.5 over an R6 root, and the bar over a head stands where
-- HudController's Overhead puts the local player's.
PickingTag.OFFSET = Vector3.new(0, 1.5 + 1.9, 0)
-- How long a tag takes to shrink away once its pick is over.
PickingTag.OUT_SECONDS = Timing.OUT

function PickingTag.Build(tag: TTagState, scale: () -> number): BillboardGui
	-- 0 to 1 and back to 0: the whole tag's presence.
	-- Derived where many parts read one value, so it is worked out once a frame rather than once a part.
	-- How far in the tag is, 0 to 1: in as it comes up, out as it goes; `hidden` is the transparency that makes.
	local shown = derive(function(): number
		local now = tag.Clock()
		local into = Motion.Out(Progress(now, tag.ShownAt(), Timing.FADE_IN))
		return into * (1 - Progress(now, tag.EndedAt(), Timing.OUT))
	end)
	local hidden = derive(function(): number
		return 1 - shown()
	end)

	local picked = function(): number
		return tag.Clock() - tag.PickedAt()
	end
	-- The card taken shows while it is on the picker's screen, and on through the way out: the word that the pick is
	-- over lands a moment after the show, and the tag must not flick back to PICKING in between.
	local isShowingPick = derive(function(): boolean
		local since = picked()
		if since < 0 then return false end
		return since < UpgradesCore.SHOW_SECONDS + Timing.PICK_GRACE or tag.EndedAt() < math.huge
	end)

	local chipScale = function(): number
		local now = tag.Clock()
		local pop = Timing.POP_FROM + (1 - Timing.POP_FROM) * Motion.OutBack(Progress(now, tag.ShownAt(), Timing.POP))
		local out = 1 - Timing.OUT_SHRINK * Motion.Accelerate(Progress(now, tag.EndedAt(), Timing.OUT))
		local thump = Motion.Fade(now, tag.PickedAt(), Timing.THUMP)
		return pop * out + Timing.THUMP_SCALE * thump * thump
	end

	local fan = table.create(3)
	for index = 1, 3 do
		local side = index - 2
		local lift = function(): number
			local now = tag.Clock()
			local phase = ((now - tag.ShownAt()) * Timing.RIPPLE_RATE - (index - 1) * Timing.RIPPLE_STAGGER) % 1
			return Timing.RIPPLE_LIFT * Motion.Bump(phase / Timing.RIPPLE_SHARE)
		end
		local angle = derive(function(): number
			local fling = Motion.Fade(tag.Clock(), tag.PickedAt(), Timing.FLING)
			return side * (Layout.FAN_SPREAD + Timing.FLING_SPREAD * fling * fling)
		end)

		fan[index] = create("Frame")({
			Name = `Card{index}`,
			AnchorPoint = Vector2.new(0.5, 1),
			Size = UDim2.fromOffset(Layout.FAN_CARD.X, Layout.FAN_CARD.Y),
			-- Turned about a point under the fan, as cards held in a hand, and lifted along its own up. A frame turns
			-- about its middle, so the middle is placed on the turn and the foot (the anchor) is half a card under it.
			Position = function()
				local turn = angle()
				local half = Layout.FAN_CARD.Y / 2
				local reach = Layout.FAN_PIVOT_DROP + half + lift()
				local pivotY = Layout.CHIP.Y / 2 + Layout.FAN_FOOT.Y + Layout.FAN_PIVOT_DROP
				local x = Layout.FAN_FOOT.X + math.sin(turn) * reach
				local y = pivotY - math.cos(turn) * reach + half
				return UDim2.fromOffset(math.round(x), math.round(y))
			end,
			Rotation = function()
				return math.deg(angle())
			end,
			-- The middle card in front of the two it is fanned over.
			ZIndex = if side == 0 then 4 else 3,
			BorderSizePixel = 0,
			BackgroundColor3 = function()
				return if isShowingPick() then tag.PickedColor() else CARD_BACK
			end,
			BackgroundTransparency = hidden,
			create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			create("UIStroke")({
				Color = Palette.White,
				Thickness = 1.5,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Transparency = hidden,
			}),
		})
	end

	local sheenTravel = function(): number
		local since = (tag.Clock() - tag.ShownAt()) % Timing.SHEEN_PERIOD
		return Progress(since, 0, Timing.SHEEN)
	end

	local chip = create("Frame")({
		Name = "Chip",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			local bob = math.sin(tag.Clock() * TAU * Timing.BOB_RATE) * Timing.BOB
			return UDim2.new(0.5, 0, 0.5, math.round(-Layout.LIFT + bob))
		end,
		Size = UDim2.fromOffset(Layout.CHIP.X, Layout.CHIP.Y),
		BackgroundColor3 = Palette.Ink,
		BorderSizePixel = 0,
		BackgroundTransparency = function()
			return 1 - (1 - Layout.CHIP_TRANSPARENCY) * shown()
		end,
		create("UIScale")({ Scale = chipScale }),
		create("UICorner")({ CornerRadius = UDim.new(0, Layout.CORNER) }),
		create("UIStroke")({
			Thickness = Layout.RIM,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = function()
				local flash = Motion.Fade(tag.Clock(), tag.PickedAt(), Timing.RIM_FLASH)
				local hold = if isShowingPick() then Timing.RIM_HOLD else 0
				return RIM_COLOR:Lerp(tag.PickedColor(), math.max(hold, flash))
			end,
			Transparency = hidden,
		}),
		Components.Text({
			Name = "Label",
			Position = UDim2.fromOffset(Layout.LABEL_X, 0),
			Size = UDim2.new(1, -Layout.LABEL_X - 10, 1, 0),
			FontFace = Font.Display,
			TextSize = Layout.LABEL_TEXT,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 3,
			Text = function()
				return if isShowingPick() then "PICKED" else "PICKING"
			end,
			TextColor3 = function()
				return if isShowingPick() then tag.PickedColor() else Palette.White
			end,
			TextTransparency = hidden,
		}),
		create("Frame")({
			Name = "Fan",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 3,
			fan,
		}),
		create("Frame")({
			Name = "SheenClip",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = 2,
			create("UICorner")({ CornerRadius = UDim.new(0, Layout.CORNER) }),
			Components.Sheen(function()
				return sheenTravel() * shown()
			end, 2),
		}),
	})

	-- The ring a taken card throws off the chip's rim.
	local ring = create("Frame")({
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -Layout.LIFT),
		Size = UDim2.fromOffset(Layout.CHIP.X, Layout.CHIP.Y),
		BackgroundTransparency = 1,
		Visible = function()
			local since = picked()
			return since >= 0 and since < Timing.RING
		end,
		create("UICorner")({ CornerRadius = UDim.new(0, Layout.CORNER) }),
		create("UIScale")({
			Scale = function()
				return 1 + Timing.RING_GROW * Motion.Out(Progress(tag.Clock(), tag.PickedAt(), Timing.RING))
			end,
		}),
		create("UIStroke")({
			Thickness = 3,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = tag.PickedColor,
			Transparency = function()
				return Progress(tag.Clock(), tag.PickedAt(), Timing.RING)
			end,
		}),
	})

	return create("BillboardGui")({
		Name = "PickingTag",
		ResetOnSpawn = false,
		AlwaysOnTop = true,
		LightInfluence = 0,
		StudsOffsetWorldSpace = PickingTag.OFFSET,
		Adornee = tag.Adornee,
		Enabled = function()
			return tag.Adornee() ~= nil
		end,
		Size = function()
			local factor = scale()
			local width = Layout.CHIP.X + 2 * Layout.ROOM
			local height = 2 * (Layout.LIFT + Layout.CHIP.Y / 2 + Layout.ROOM)
			return UDim2.fromOffset(math.round(width * factor), math.round(height * factor))
		end,
		-- Sized 1 / scale so that after its UIScale it fills the billboard, with the tag's px in design px.
		create("Frame")({
			Name = "Root",
			BackgroundTransparency = 1,
			Size = function()
				local factor = scale()
				return UDim2.fromScale(1 / factor, 1 / factor)
			end,
			create("UIScale")({ Scale = scale }),
			chip,
			ring,
		}),
	})
end

return PickingTag
