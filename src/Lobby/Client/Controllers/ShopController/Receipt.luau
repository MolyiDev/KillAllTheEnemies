--!nonstrict
-- A Robux purchase's receipt, over every lobby screen and under the Gems pill: the dim falls and the light gathers
-- where the card will land; the card drops onto it from above the screen and lands hard (one flash, one ring, a dip,
-- the light bursting out behind it and its own art cheering); its tab of thanks grows in over its top edge and its
-- name stamps down into its band. Then what it gave prints out from under it a line at a time, each count rolling up
-- and stamping (the Gems line's Gems burst on into the pill), a pass bought for good slaps on its FOREVER ribbon, the
-- finale cheers the light and sweeps the card, and AWESOME! comes in. A press during the reveal lands it all at once.
--
-- Every beat is a curve of the receipt's own clock against its plan (Receipts.Plan), which a press replaces; the
-- controller plays the sounds and throws the Gems on the same plan. Built once per receipt.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local GunPicture = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.GunPicture)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Ribbon = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Ribbon)
local Showcase = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Showcase)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local LoadoutCore = require(ReplicatedStorage.GlobalShared.Core.LoadoutCore)
local Parts = require(script.Parent.Parts)
local Receipts = require(script.Parent.Receipts)
local Types = require(script.Parent.Types)

local create = vide.create
local derive = vide.derive
local source = vide.source
local Palette = Theme.Palette
local Font = Theme.Font
local Label = Parts.Label
local Progress = Motion.Progress
local bump = Motion.Bump
local decelerate = Motion.Decelerate
local accelerate = Motion.Accelerate
local lerp = Motion.Lerp

-- Design px on his 1920 x 1080 screen.
local Layout = table.freeze({
	DESIGN = Vector2.new(1920, 1080),
	-- The receipt is centred in the screen below this: the HUD's Gems counter reaches 78 down (LobbyController's
	-- Hud.Layout, COUNTER_MIDDLE 44 and its + square 67 tall), and the Gems land in it, so it stays in sight.
	TOP_CLEAR = 84,
	CARD = Vector2.new(500, 440),
	BAND = 72,
	NAME_TEXT = 38,
	-- The picture's middle from the card's top, and its longest side; a gun's box instead.
	PICTURE_Y = 192,
	PICTURE = 270,
	GUN = Vector2.new(460, 250),
	ART = 480,
	ART_FLOOR = 120,
	CARD_EDGE = 3,
	TAB = 48,
	RIBBON_ALONG = 110,
	RIBBON_THICKNESS = 38,
	RIBBON_TEXT = 20,
	-- The light behind the card, and the shadow it falls onto.
	RAYS = 1300,
	SHADOW = Vector2.new(460, 34),
	SHADOW_DROP = 18,
	-- The lines under the card: their size, the gap between them and from the card; the icon's middle from a line's
	-- left and its longest side (a gun's box instead); where the words start; the tag's height and inset.
	ROW = Vector2.new(720, 76),
	ROW_GAP = 14,
	ROWS_GAP = 32,
	ICON_X = 54,
	ICON = 52,
	ROW_GUN = Vector2.new(100, 58),
	TEXT_LEFT = 106,
	COUNT_TEXT = 40,
	WORD_TEXT = 24,
	WORDS_TEXT = 28,
	TEXT_GAP = 12,
	TAG = 30,
	TAG_INSET = 18,
	-- What a line of words leaves for its tag: the widest, LEGENDARY.
	TAG_ROOM = 150,
	BUTTON = Vector2.new(340, 84),
	BUTTON_TEXT = 34,
	BUTTON_TRACKING = 3,
	BUTTON_GAP = 34,
	-- Room round a piece in its fading group: its glow, its ring and the tab over its edge (a group clips).
	MARGIN = 48,
	ROW_MARGIN = 28,
})

-- Seconds unless named otherwise.
local Look = table.freeze({
	DIM = 0.62,
	DIM_IN = 0.25,
	DIM_OUT = 0.3,
	-- The light behind gathers to this share of itself while the card falls, and is all out this long after the
	-- landing; on the way out it fades over RAYS_OUT.
	RAYS_CHARGE = 0.3,
	RAYS_IN = 0.35,
	RAYS_OUT = 0.45,
	SHADOW_ALPHA = 0.5,
	SHADOW_OUT = 0.35,
	-- The landing: the card sinks this share and comes back, and the stage dips this many px.
	SLAM_SQUASH = 0.06,
	SLAM_SQUASH_SECONDS = 0.2,
	SLAM_DIP = 14,
	SLAM_DIP_SECONDS = 0.32,
	SLAM_FLASH = 0.95,
	SLAM_FLASH_SECONDS = 0.32,
	RING = 0.55,
	RING_GROW = 40,
	-- A flash's white at its peak.
	FLASH_ALPHA = 0.6,
	-- The card's glow at rest, and how much a flash and the light's call lift it.
	GLOW = 0.5,
	GLOW_FLASH = 0.35,
	GLOW_CALL = 0.15,
	-- The picture punches on the landing and again, less, on the finale.
	PICTURE_PUNCH = 0.12,
	PICTURE_FINALE = 0.08,
	PICTURE_PUNCH_SECONDS = 0.4,
	-- The name stamps down from STAMP_FROM in STAMP; the card thumps as it lands.
	STAMP = 0.1,
	STAMP_FROM = 1.6,
	STAMP_THUMP = 0.025,
	STAMP_THUMP_SECONDS = 0.22,
	STAMP_FLASH = 0.45,
	STAMP_FLASH_SECONDS = 0.2,
	-- The name is all in this share of the way through its stamp.
	STAMP_FADE = 0.4,
	TAB_IN = 0.22,
	TAB_FROM = 0.6,
	-- A gun on the card turns toward the viewer as it lands, and back.
	GUN_TURN = 26,
	GUN_TURN_SECONDS = 0.7,
	-- A line grows from this share as it slides out; it thumps as it stamps; its count punches.
	ROW_FROM = 0.6,
	ROW_LAND_FLASH = 0.6,
	ROW_LAND_FLASH_SECONDS = 0.25,
	ROW_STAMP_FLASH_SECONDS = 0.3,
	ROW_THUMP = 0.035,
	ROW_THUMP_SECONDS = 0.25,
	ROW_RING_GROW = 22,
	ROW_GLOW = 0.82,
	ROW_GLOW_FLASH = 0.5,
	-- As a line stamps its count punches, its icon more and a line of words less.
	COUNT_POP = 0.16,
	ICON_POP = 0.2,
	WORDS_POP = 0.06,
	COUNT_POP_SECONDS = 0.28,
	FINALE_THUMP = 0.03,
	FINALE_THUMP_SECONDS = 0.3,
	FINALE_FLASH = 0.5,
	FINALE_FLASH_SECONDS = 0.3,
	SHEEN = 0.6,
	-- CONTINUE grows in from BUTTON_FROM; its glow lifts under the hand, as the lobby's slabs' do.
	BUTTON_IN = 0.25,
	BUTTON_FROM = 0.6,
	BUTTON_GLOW = 0.6,
	BUTTON_GLOW_LIGHT = 0.3,
	-- The way out: everything shrinks this share as it fades, the lines a beat apart from the bottom up.
	LEAVE = 0.24,
	LEAVE_SHRINK = 0.1,
	LEAVE_STAGGER = 0.03,
})

-- Where a line waits until it prints: off the screen, never hidden with Visible.
local PARKED = UDim2.fromOffset(-10000, -10000)
-- The card's fall: it lands on the plan's slam.
local DROP = Receipts.Timing.DROP

local Receipt = {}

Receipt.Layout = Layout
-- Every gesture of the way out is over by then: the light's fade is the longest.
Receipt.LEAVE_SECONDS = Look.RAYS_OUT + 0.05

export type TPlace = {
	CardCenter: Vector2,
	-- Each line's middle.
	Rows: { Vector2 },
	Button: Vector2,
}

-- What every piece of one receipt reads: its clock and plan, where it all stands, its way out (0 to 1) and when the
-- light last cheered.
type TView = {
	State: Types.TShopState,
	Receipt: Types.TReceipt,
	Place: TPlace,
	Now: () -> number,
	Plan: () -> Types.TReceiptPlan,
	Leave: () -> number,
	CheeredAt: () -> number,
}

-- Where the card, the lines and CONTINUE stand for a receipt of `rowCount` lines, the whole centred below the Gems
-- counter.
function Receipt.Place(rowCount: number): TPlace
	local rowsHeight = if rowCount > 0 then rowCount * Layout.ROW.Y + (rowCount - 1) * Layout.ROW_GAP else 0
	local total = Layout.TAB / 2
		+ Layout.CARD.Y
		+ (if rowCount > 0 then Layout.ROWS_GAP + rowsHeight else 0)
		+ Layout.BUTTON_GAP
		+ Layout.BUTTON.Y
	local room = Layout.DESIGN.Y - Layout.TOP_CLEAR
	local cardTop = math.round(Layout.TOP_CLEAR + (room - total) / 2 + Layout.TAB / 2)
	local middle = Layout.DESIGN.X / 2
	local rows = table.create(rowCount)
	local rowsTop = cardTop + Layout.CARD.Y + Layout.ROWS_GAP
	for index = 1, rowCount do
		rows[index] = Vector2.new(middle, rowsTop + (index - 1) * (Layout.ROW.Y + Layout.ROW_GAP) + Layout.ROW.Y / 2)
	end

	local above = if rowCount > 0 then rowsTop + rowsHeight else cardTop + Layout.CARD.Y
	return {
		CardCenter = Vector2.new(middle, cardTop + Layout.CARD.Y / 2),
		Rows = rows,
		Button = Vector2.new(middle, above + Layout.BUTTON_GAP + Layout.BUTTON.Y / 2),
	}
end

-- Where a line's icon stands, in design px: where its Gems burst from.
function Receipt.IconAt(place: TPlace, index: number): Vector2
	local row = place.Rows[index]
	return Vector2.new(row.X - Layout.ROW.X / 2 + Layout.ICON_X, row.Y)
end

-- 1 at `at`, falling to 0 over `seconds` as a square: a white flash, short and bright.
local function flashOf(t: number, at: number, seconds: number): number
	if t < at then return 0 end
	local left = 1 - (t - at) / seconds
	return if left > 0 then left * left else 0
end

-- The light behind and the card's own art turn for as long as the receipt is built.
local function always(): boolean
	return true
end

-- `count` with its prefix and suffix, as the line reads it.
local function countText(row: Types.TReceiptRow, shown: number): string
	return `{row.Prefix or "+"}{Components.Commas(shown)}{row.Suffix or ""}`
end

-- One ring growing `grow` px out of a frame of `corner` px as `share` runs 0 to 1.
local function ring(share: () -> number, grow: number, corner: number, zIndex: number): Frame
	return create("Frame")({
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = function()
			local px = math.round(grow * Motion.Out(share()))
			return UDim2.new(1, 2 * px, 1, 2 * px)
		end,
		BackgroundTransparency = 1,
		ZIndex = zIndex,
		Visible = function()
			local t = share()
			return t > 0 and t < 1
		end,
		create("UICorner")({ CornerRadius = UDim.new(0, corner + 4) }),
		create("UIStroke")({
			Color = Palette.White,
			Thickness = 2,
			Transparency = share,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
	})
end

-- White over a face, `amount` of it.
local function flashLayer(amount: () -> number, zIndex: number): Frame
	return create("Frame")({
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Palette.White,
		BorderSizePixel = 0,
		ZIndex = zIndex,
		Visible = function()
			return amount() > 0.01
		end,
		BackgroundTransparency = function()
			return 1 - Look.FLASH_ALPHA * amount()
		end,
		create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
	})
end

local function gunOf(name: string, yaw: () -> number, size: Vector2, props: { [any]: any }): Frame
	return GunPicture.Build(function()
		local data = LoadoutCore.ByName[name]
		return if data then GunPicture.FromGun(data.Id) else nil
	end, {
		Rotation = GunPicture.CARD_TILT,
		Yaw = yaw,
	}, {
		Name = "Gun",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size.X, size.Y),
		props,
	})
end

-- The tab of thanks over the card's top edge: his flat tag in the card's accent, growing in.
local function tab(receipt: Types.TReceipt, shown: () -> number, zIndex: number): Frame
	local isInk = receipt.Accent == Palette.Gold or receipt.Accent == Palette.Green or receipt.Accent == Palette.Steel
	local tall = Layout.TAB
	return create("Frame")({
		Name = "Tab",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(Layout.CARD.X / 2, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, tall),
		BackgroundColor3 = receipt.Accent,
		BorderSizePixel = 0,
		ZIndex = zIndex,
		BackgroundTransparency = function()
			return 1 - shown()
		end,
		create("UIScale")({
			Scale = function()
				return math.max(Look.TAB_FROM + (1 - Look.TAB_FROM) * shown(), 0.01)
			end,
		}),
		create("UIPadding")({
			PaddingLeft = UDim.new(0, math.round(tall * 0.47)),
			PaddingRight = UDim.new(0, math.round(tall * 0.47)),
		}),
		Label({
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromScale(0, 1),
			TextSize = math.round(tall / 2),
			TextYAlignment = Enum.TextYAlignment.Center,
			TextColor3 = if isInk then Palette.Ink else Palette.White,
			AutoLocalize = false,
			Text = receipt.Tab,
			ZIndex = zIndex + 1,
			TextTransparency = function()
				return 1 - shown()
			end,
		}),
	})
end

-- ============================== The card ==============================

local function card(view: TView): Frame
	local state, receipt, place = view.State, view.Receipt, view.Place
	local now, plan, leave = view.Now, view.Plan, view.Leave
	local size = Layout.CARD
	local margin = Layout.MARGIN
	local edge = Layout.CARD_EDGE

	-- Off the screen above until it falls, faster and faster, onto its place; then the landing's dip.
	local offset = derive(function(): number
		local current, t = plan(), now()
		if t >= current.SlamAt then
			return math.round(Look.SLAM_DIP * bump((t - current.SlamAt) / Look.SLAM_DIP_SECONDS))
		end
		local fall = Progress(t, current.SlamAt - DROP, DROP)
		return -math.round((place.CardCenter.Y + size.Y / 2 + margin) * (1 - fall * fall))
	end)
	local scale = derive(function(): number
		local current, t = plan(), now()
		local nameLand = current.NameAt + Look.STAMP
		return (
			1
			- Look.SLAM_SQUASH * bump((t - current.SlamAt) / Look.SLAM_SQUASH_SECONDS)
			+ Look.STAMP_THUMP * bump((t - nameLand) / Look.STAMP_THUMP_SECONDS)
			+ Look.FINALE_THUMP * bump((t - current.FinaleAt) / Look.FINALE_THUMP_SECONDS)
		) * (1 - Look.LEAVE_SHRINK * accelerate(leave()))
	end)
	local flash = derive(function(): number
		local current, t = plan(), now()
		return math.max(
			Look.SLAM_FLASH * flashOf(t, current.SlamAt, Look.SLAM_FLASH_SECONDS),
			Look.STAMP_FLASH * flashOf(t, current.NameAt + Look.STAMP, Look.STAMP_FLASH_SECONDS),
			Look.FINALE_FLASH * flashOf(t, current.FinaleAt, Look.FINALE_FLASH_SECONDS)
		)
	end)
	-- One ring on the landing, one on the finale.
	local ringShare = derive(function(): number
		local current, t = plan(), now()
		local at = if t >= current.FinaleAt then current.FinaleAt else current.SlamAt
		return Progress(t, at, Look.RING)
	end)
	local artShown = derive(function(): number
		return decelerate(Progress(now(), plan().SlamAt, Look.RAYS_IN))
	end)
	local tabShown = derive(function(): number
		return decelerate(Progress(now(), plan().TabAt, Look.TAB_IN))
	end)
	local stamp = derive(function(): number
		local current, t = plan(), now()
		if t < current.NameAt then return -1 end
		return Progress(t, current.NameAt, Look.STAMP)
	end)
	-- The light across the card on the finale, then every time the controller calls.
	local sheen = derive(function(): number
		local current, t = plan(), now()
		if t < current.FinaleAt + Look.SHEEN then return Progress(t, current.FinaleAt, Look.SHEEN) end
		return Progress(t, state.ReceiptCalledAt(), Look.SHEEN)
	end)
	local glow = derive(function(): number
		local called = bump(Progress(now(), state.ReceiptCalledAt(), Look.SHEEN))
		return math.max(Look.GLOW - Look.GLOW_FLASH * flash() - Look.GLOW_CALL * called, 0)
	end)
	local punch = derive(function(): number
		local current, t = plan(), now()
		return 1
			+ Look.PICTURE_PUNCH * bump((t - current.SlamAt) / Look.PICTURE_PUNCH_SECONDS)
			+ Look.PICTURE_FINALE * bump((t - current.FinaleAt) / Look.PICTURE_PUNCH_SECONDS)
	end)
	local gunYaw = derive(function(): number
		return Look.GUN_TURN * bump((now() - plan().SlamAt) / Look.GUN_TURN_SECONDS)
	end)
	local isRibboned = derive(function(): boolean
		return now() >= plan().RibbonAt
	end)

	local center = Vector2.new(size.X / 2, Layout.PICTURE_Y)
	local back, front = Showcase.Build({
		Look = receipt.Art,
		Diameter = Layout.ART,
		Floor = Layout.ART_FLOOR,
		Accent = function(): Color3
			return receipt.ArtAccent
		end,
		Shown = artShown,
		CheeredAt = view.CheeredAt,
		IsActive = always,
	}, { Position = UDim2.fromOffset(center.X - edge, center.Y - edge) }, {
		Position = UDim2.fromOffset(center.X - edge, center.Y - edge),
	})
	local function clipped(name: string, child: Frame?, zIndex: number): Frame?
		if not child then return nil end
		return create("Frame")({
			Name = name,
			Position = UDim2.fromOffset(edge, edge),
			Size = UDim2.fromOffset(size.X - 2 * edge, size.Y - 2 * edge - Layout.BAND),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = zIndex,
			child,
		})
	end

	local shown = if receipt.Gun
		then gunOf(receipt.Gun, gunYaw, Layout.GUN, {
			Position = UDim2.fromOffset(center.X, center.Y),
			ZIndex = 3,
		})
		else Components.Picture(receipt.Picture, {
			Name = "Picture",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(center.X, center.Y),
			Size = Components.PictureBox(Layout.PICTURE),
			ZIndex = 3,
			create("UIScale")({ Scale = punch }),
		})

	local face = Components.Card({
		Accent = receipt.Accent,
		Tint = 0.45,
		Marks = true,
		Band = Layout.BAND,
		Tall = true,
		GlowTransparency = glow,
	}, {
		Name = "Face",
		Position = UDim2.fromOffset(margin, margin),
		Size = UDim2.fromOffset(size.X, size.Y),
		clipped("Art", back, 2),
		shown,
		clipped("ArtFront", front, 4),
		Label({
			Name = "Name",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(size.X / 2, size.Y - edge - Layout.BAND / 2),
			Size = UDim2.fromOffset(size.X - 40, Layout.NAME_TEXT),
			TextSize = Layout.NAME_TEXT,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextScaled = true,
			AutoLocalize = false,
			Text = receipt.Name,
			ZIndex = 5,
			TextTransparency = function()
				local t = stamp()
				return if t < 0 then 1 else 1 - math.min(t / Look.STAMP_FADE, 1)
			end,
			create("UIScale")({
				Scale = function()
					local t = stamp()
					if t < 0 then return Look.STAMP_FROM end
					return Look.STAMP_FROM - (Look.STAMP_FROM - 1) * t * t
				end,
			}),
			create("UITextSizeConstraint")({ MaxTextSize = Layout.NAME_TEXT }),
		}),
		Components.Sheen(sheen, 7, size.X / size.Y),
		flashLayer(flash, 8),
		if receipt.Ribbon
			then Ribbon.Build({
				Corner = "TopRight",
				Text = receipt.Ribbon,
				Color = receipt.RibbonColor or Palette.Pink,
				IsInk = receipt.RibbonIsInk == true,
				IsShown = isRibboned,
				Along = Layout.RIBBON_ALONG,
				Thickness = Layout.RIBBON_THICKNESS,
				TextSize = Layout.RIBBON_TEXT,
				ZIndex = 9,
			})
			else nil,
		tab(receipt, tabShown, 11),
	})

	return create("Frame")({
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			return UDim2.fromOffset(place.CardCenter.X, place.CardCenter.Y + offset())
		end,
		Size = UDim2.fromOffset(size.X + 2 * margin, size.Y + 2 * margin),
		BackgroundTransparency = 1,
		ZIndex = 20,
		create("UIScale")({ Scale = scale }),
		Components.FadeGroup("Card", function(): number
			return 1 - leave()
		end, { Size = UDim2.fromScale(1, 1) }, { face }),
		create("Frame")({
			Name = "RingFrame",
			Position = UDim2.fromOffset(margin, margin),
			Size = UDim2.fromOffset(size.X, size.Y),
			BackgroundTransparency = 1,
			ring(ringShare, Look.RING_GROW, 3, 1),
		}),
	})
end

-- ============================== The lines ==============================

-- A gun on a line stands still.
local function noTurn(): number
	return 0
end

local function row(view: TView, data: Types.TReceiptRow, index: number): Frame
	local state, place, now, plan = view.State, view.Place, view.Now, view.Plan
	local size = Layout.ROW
	local margin = Layout.ROW_MARGIN
	local home = place.Rows[index]
	-- Its way out starts a beat after the line under it.
	local leaveDelay = (#place.Rows - index) * Look.LEAVE_STAGGER
	local beats = function(): Types.TReceiptRowPlan
		return plan().Rows[index]
	end

	local slide = derive(function(): number
		local current, t = beats(), now()
		if t < current.PrintAt then return -1 end
		if current.LandAt <= current.PrintAt then return 1 end
		return decelerate(Progress(t, current.PrintAt, current.LandAt - current.PrintAt))
	end)
	local gone = derive(function(): number
		return Progress(now(), state.ReceiptLeftAt() + leaveDelay, Look.LEAVE)
	end)
	local flash = derive(function(): number
		local current, t = beats(), now()
		return math.max(
			Look.ROW_LAND_FLASH * flashOf(t, current.LandAt, Look.ROW_LAND_FLASH_SECONDS),
			flashOf(t, current.StampAt, Look.ROW_STAMP_FLASH_SECONDS)
		)
	end)
	local shownCount = derive(function(): number
		local count = data.Count or 0
		local current, t = beats(), now()
		if t >= current.StampAt then return count end
		if t < current.LandAt then return 0 end
		return math.floor(count * decelerate(Progress(t, current.LandAt, current.StampAt - current.LandAt)))
	end)
	-- The stamp's punch on the count and the icon, the line's thump, and its one ring.
	local pop = derive(function(): number
		return bump((now() - beats().StampAt) / Look.COUNT_POP_SECONDS)
	end)
	local thump = derive(function(): number
		return bump((now() - beats().StampAt) / Look.ROW_THUMP_SECONDS)
	end)
	local ringShare = derive(function(): number
		return Progress(now(), beats().StampAt, Look.RING)
	end)
	local countWidth = source(0)

	local icon = if data.Gun
		then gunOf(data.Gun, noTurn, Layout.ROW_GUN, {
			Position = UDim2.fromOffset(Layout.ICON_X, size.Y / 2),
			ZIndex = 4,
		})
		else Components.Picture(data.Picture, {
			Name = "Icon",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(Layout.ICON_X, size.Y / 2),
			Size = Components.PictureBox(Layout.ICON),
			ImageColor3 = if data.IsTinted then data.Accent else Palette.White,
			ZIndex = 4,
			create("UIScale")({
				Scale = function()
					return 1 + Look.ICON_POP * pop()
				end,
			}),
		})

	local words
	if data.Count then
		words = {
			-- The count at its full width, so the roll does not push the word about.
			Label({
				Name = "Measure",
				Size = UDim2.fromOffset(400, Layout.COUNT_TEXT),
				TextSize = Layout.COUNT_TEXT,
				TextTransparency = 1,
				Text = countText(data, data.Count),
				-- TextBounds is in screen px, under the root's UIScale; the width is in design px.
				vide.changed("TextBounds", function(bounds: Vector2)
					countWidth(math.ceil(bounds.X / math.max(vide.untrack(state.Scale), 0.01)))
				end),
			}),
			create("Frame")({
				Name = "Words",
				Position = UDim2.fromOffset(Layout.TEXT_LEFT, 0),
				Size = UDim2.fromOffset(size.X - Layout.TEXT_LEFT - Layout.TAG_INSET, size.Y),
				BackgroundTransparency = 1,
				ZIndex = 5,
				create("UIListLayout")({
					FillDirection = Enum.FillDirection.Horizontal,
					SortOrder = Enum.SortOrder.LayoutOrder,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, Layout.TEXT_GAP),
				}),
				Label({
					Name = "Count",
					LayoutOrder = 1,
					Size = function()
						return UDim2.fromOffset(countWidth(), Layout.COUNT_TEXT)
					end,
					TextSize = Layout.COUNT_TEXT,
					TextYAlignment = Enum.TextYAlignment.Center,
					Text = function()
						return countText(data, shownCount())
					end,
					ZIndex = 5,
					create("UIScale")({
						Scale = function()
							return 1 + Look.COUNT_POP * pop()
						end,
					}),
				}),
				Label({
					Name = "Word",
					LayoutOrder = 2,
					AutomaticSize = Enum.AutomaticSize.X,
					Size = UDim2.fromOffset(0, Layout.WORD_TEXT),
					TextSize = Layout.WORD_TEXT,
					TextYAlignment = Enum.TextYAlignment.Center,
					TextColor3 = function()
						return data.Accent:Lerp(Palette.White, flash())
					end,
					Text = data.Text,
					ZIndex = 5,
					-- Its letters sit on the count's line, a little under the count's middle.
					create("UIPadding")({ PaddingTop = UDim.new(0, 5) }),
				}),
			}),
		}
	else
		words = Label({
			Name = "Words",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(Layout.TEXT_LEFT, size.Y / 2),
			Size = UDim2.fromOffset(
				size.X - Layout.TEXT_LEFT - Layout.TAG_INSET - (if data.Tag then Layout.TAG_ROOM else 0),
				Layout.WORDS_TEXT
			),
			TextSize = Layout.WORDS_TEXT,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = data.Text,
			ZIndex = 5,
			create("UIScale")({
				Scale = function()
					return 1 + Look.WORDS_POP * pop()
				end,
			}),
		})
	end

	local face = Components.Card({
		Accent = data.Accent,
		Tint = 0.3,
		Edge = 2,
		Wide = true,
		GlowTransparency = function()
			return math.max(Look.ROW_GLOW - Look.ROW_GLOW_FLASH * flash(), 0)
		end,
	}, {
		Name = "Face",
		Position = UDim2.fromOffset(margin, margin),
		Size = UDim2.fromOffset(size.X, size.Y),
		icon,
		words,
		if data.Tag
			then Parts.Tag(data.Tag.Text, data.Tag.Color, data.Tag.IsInk, false, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -Layout.TAG_INSET, 0.5, 0),
				ZIndex = 5,
			}, Layout.TAG)
			else nil,
		flashLayer(flash, 7),
		create("Frame")({
			Name = "RingFrame",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ring(ringShare, Look.ROW_RING_GROW, 3, 1),
		}),
	})

	return create("Frame")({
		Name = `Row{index}`,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			local t = slide()
			if t < 0 then return PARKED end
			return UDim2.fromOffset(home.X, math.round(lerp(place.CardCenter.Y, home.Y, t)))
		end,
		Size = UDim2.fromOffset(size.X + 2 * margin, size.Y + 2 * margin),
		BackgroundTransparency = 1,
		-- Each under the one above it, all under the card: a line comes out from under them as it prints.
		ZIndex = 5 + #place.Rows - index,
		create("UIScale")({
			Scale = function()
				local t = math.max(slide(), 0)
				return math.max(
					lerp(Look.ROW_FROM, 1, t)
						* (1 + Look.ROW_THUMP * thump())
						* (1 - Look.LEAVE_SHRINK * accelerate(gone())),
					0.01
				)
			end,
		}),
		Components.FadeGroup(`Row{index}`, function(): number
			return 1 - gone()
		end, { Size = UDim2.fromScale(1, 1) }, { face }),
	})
end

-- ============================== CONTINUE ==============================

local function continueButton(view: TView, actions: Types.TReceiptActions): TextButton
	local state, place, now, plan, leave = view.State, view.Place, view.Now, view.Plan, view.Leave
	local hand = Hand.React("Operate")
	local size = Layout.BUTTON
	local margin = Layout.ROW_MARGIN
	local appear = derive(function(): number
		return decelerate(Progress(now(), plan().ButtonAt, Look.BUTTON_IN))
	end)
	local shown = derive(function(): number
		return appear() * (1 - leave())
	end)
	local isDone = derive(function(): boolean
		return now() >= plan().ButtonAt and state.ReceiptLeftAt() == math.huge
	end)

	return Components.Button({
		Name = "Continue",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(place.Button.X, place.Button.Y),
		Size = UDim2.fromOffset(size.X + 2 * margin, size.Y + 2 * margin),
		BackgroundTransparency = 1,
		ZIndex = 21,
		Visible = function()
			return shown() > 0
		end,
		Interactable = isDone,
		Activated = function()
			hand.Commit()
			actions.Continue()
		end,
		hand.Events,
		create("UIScale")({
			Scale = function()
				local grown = Look.BUTTON_FROM + (1 - Look.BUTTON_FROM) * appear()
				return math.max(grown * hand.Scale() * (1 - Look.LEAVE_SHRINK * accelerate(leave())), 0.01)
			end,
		}),
		Components.FadeGroup("Continue", shown, { Size = UDim2.fromScale(1, 1) }, {
			Components.Slab({
				Kind = "Go",
				Marks = true,
				Brackets = hand.Rise,
				GlowTransparency = function()
					return Look.BUTTON_GLOW - Look.BUTTON_GLOW_LIGHT * hand.Light()
				end,
			}, {
				Name = "Slab",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(size.X, size.Y),
				Hand.WashLayer(hand, 3, 3),
				Components.Sheen(hand.Glint, 3),
				Components.Tracked("AWESOME!", Layout.BUTTON_TEXT, Layout.BUTTON_TRACKING, Font.Display, {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
				}),
			}),
		}),
	}) :: TextButton
end

-- ============================== The receipt ==============================

-- Everything a receipt draws, on the 1920 x 1080 design root.
function Receipt.Build(state: Types.TShopState, receipt: Types.TReceipt, actions: Types.TReceiptActions): { Instance }
	local now = state.ReceiptNow
	local place = Receipt.Place(#receipt.Rows)
	local plan = function(): Types.TReceiptPlan
		return state.ReceiptPlan() :: Types.TReceiptPlan
	end
	-- The light behind and the card's art cheer on the landing, then on the finale.
	local cheeredAt = derive(function(): number
		local current, t = plan(), now()
		if t >= current.FinaleAt then return current.FinaleAt end
		if t >= current.SlamAt then return current.SlamAt end
		return -math.huge
	end)
	local view: TView = {
		State = state,
		Receipt = receipt,
		Place = place,
		Now = now,
		Plan = plan,
		Leave = derive(function(): number
			return Progress(now(), state.ReceiptLeftAt(), Look.LEAVE)
		end),
		CheeredAt = cheeredAt,
	}
	local dim = derive(function(): number
		local t = now()
		return decelerate(Progress(t, plan().At, Look.DIM_IN)) * (1 - Progress(t, state.ReceiptLeftAt(), Look.DIM_OUT))
	end)
	local rays = derive(function(): number
		local current, t = plan(), now()
		local out = 1 - Progress(t, state.ReceiptLeftAt(), Look.RAYS_OUT)
		if t < current.SlamAt then
			return Look.RAYS_CHARGE * decelerate(Progress(t, current.At, current.SlamAt - current.At)) * out
		end
		return (Look.RAYS_CHARGE + (1 - Look.RAYS_CHARGE) * decelerate(Progress(t, current.SlamAt, Look.RAYS_IN))) * out
	end)
	-- The shadow the card falls onto: it widens and darkens as the card comes, then goes once it has landed.
	local shadow = derive(function(): Vector2
		local current, t = plan(), now()
		if t < current.SlamAt then
			local charge = Progress(t, current.At, current.SlamAt - current.At)
			return Vector2.new(0.3 + 0.6 * charge, Look.SHADOW_ALPHA * charge)
		end
		return Vector2.new(0.9, Look.SHADOW_ALPHA * (1 - Progress(t, current.SlamAt, Look.SHADOW_OUT)))
	end)

	local center = place.CardCenter
	local back, front = Showcase.Build({
		Look = "Rays",
		Diameter = Layout.RAYS,
		Floor = 0,
		Accent = function(): Color3
			return receipt.Accent
		end,
		Shown = rays,
		CheeredAt = cheeredAt,
		IsActive = always,
	}, { Position = UDim2.fromOffset(center.X, center.Y), ZIndex = 2 }, {
		Position = UDim2.fromOffset(center.X, center.Y),
		ZIndex = 3,
	})

	local rows = table.create(#receipt.Rows)
	for index, data in receipt.Rows do
		rows[index] = row(view, data, index)
	end

	return {
		-- Over the whole screen and pressable, so nothing under it hears a press: during the reveal a press lands it
		-- all, after it continues.
		create("TextButton")({
			Name = "Dim",
			-- The design root is fitted inside the screen, so on a wider or taller one the dim reaches well past it.
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(4, 4),
			BackgroundColor3 = Palette.Ink,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Selectable = false,
			Text = "",
			ZIndex = 1,
			Interactable = function()
				return state.ReceiptLeftAt() == math.huge
			end,
			BackgroundTransparency = function()
				return 1 - Look.DIM * dim()
			end,
			Activated = actions.Press,
		}),
		back,
		front,
		create("ImageLabel")({
			Name = "Shadow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(center.X, center.Y + Layout.CARD.Y / 2 + Layout.SHADOW_DROP),
			Size = function()
				return UDim2.fromOffset(math.round(Layout.SHADOW.X * shadow().X), Layout.SHADOW.Y)
			end,
			BackgroundTransparency = 1,
			Image = "rbxasset://textures/whiteCircle.png",
			ImageColor3 = Palette.Ink,
			ImageTransparency = function()
				return 1 - shadow().Y
			end,
			Visible = function()
				return shadow().Y > 0.01
			end,
			ZIndex = 4,
		}),
		rows,
		card(view),
		continueButton(view, actions),
	}
end

return table.freeze(Receipt)
