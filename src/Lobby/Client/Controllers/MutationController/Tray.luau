--!nonstrict
-- A batch's potions on the MUTATE page, one card each in a row where the souls' cards stand (they make way while it is
-- up). BREW pressed for more than one, the souls fade down and the cards deal in sealed, their bottles shaking as the
-- flask brews; once the answer is in they open one after another (Brew.Times' Cards), lowest rarity first and the
-- best last: a quick climb through the rarities, then the landing, harder the rarer (a punch, one flash, one ring,
-- the glow up and the tag stamped; light behind an Epic or better, a Mythic's card shaken). Each potion then flies
-- out of its own card to the POTIONS tab (init), the empty tray leaves and the souls come back.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Showcase = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Showcase)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local PotionsCore = require(ReplicatedStorage.GlobalShared.Core.PotionsCore)
local Brew = require(script.Parent.Brew)
local Parts = require(script.Parent.Parts)
local Types = require(script.Parent.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)
local ERarities = require(ReplicatedStorage.Types.Enums.ERarities)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Progress = Motion.Progress

-- His drawn rects in px at 1080, from the screen's top left: the row is the souls' cards' (Mutate), centred in the
-- panel's column. Up to five cards share his 24 px gap; ten stand 18 apart, the bracket check at a landing's peak
-- (a 110 px card punched 13% reaches 12 px).
local Layout = table.freeze({
	ROW_Y = 626,
	ROW_HEIGHT = 170,
	CENTRE_X = (Parts.LEFT + Parts.RIGHT) / 2,
	WIDTH = Parts.RIGHT - Parts.LEFT,
	CARD_MAX = 200,
	GAP = 24,
	GAP_TIGHT = 18,
	-- The bottle: a share of the card's width, at most BOTTLE_MAX, its middle this share down the card.
	BOTTLE_SHARE = 0.56,
	BOTTLE_MAX = 84,
	BOTTLE_Y = 0.42,
	TAG_HEIGHT = 24,
	TAG_TEXT = 13,
	TAG_PAD = 10,
	TAG_BOTTOM = 16,
	BRACKET_LENGTH = 18,
	-- Room round a card inside the group that fades it, for its glow, its brackets and its ring.
	FADE_MARGIN = 48,
	-- The light behind a landed Epic or better, as a share of the card's width.
	RAYS_SHARE = 1.8,
})

local Timing = table.freeze({
	-- The souls make way as BREW is pressed, and come back once the tray has gone.
	SOULS_OUT = 0.22,
	SOULS_BACK = 0.38,
	SOULS_DROP = 16,
	-- The cards deal in once the souls are mostly gone, from the left, growing in from DEAL_FROM.
	DEAL_DELAY = 0.12,
	DEAL_STAGGER = 0.045,
	DEAL = 0.34,
	DEAL_FROM = 0.6,
	DEAL_RISE = 18,
	LEAVE_STAGGER = 0.03,
	LEAVE = 0.24,
	-- Sealed, the bottle shakes harder as the brew builds.
	JIGGLE_MIN = 0.6,
	JIGGLE_MAX = 2.6,
	-- Each step of a climb nudges the card.
	STEP_PUNCH = 0.05,
	STEP_PUNCH_SECONDS = 0.14,
	-- The landing: the punch (by rarity, within the bracket check), the flash, the ring, the tag stamped.
	PUNCH_MIN = 0.06,
	PUNCH_MAX = 0.13,
	PUNCH = 0.42,
	FLASH = 0.28,
	-- How white the flash starts, a Common's to a Mythic's: a full white card reads as a blank one.
	FLASH_MIN = 0.45,
	FLASH_MAX = 0.75,
	RING = 0.5,
	RING_REACH = 30,
	STAMP_DELAY = 0.05,
	STAMP = 0.22,
	STAMP_FROM = 1.55,
	-- The glow: sealed, landed (a rarer one brighter), and the landing's flare on top.
	GLOW_SEALED = 0.8,
	GLOW_LANDED = 0.68,
	GLOW_POWER = 0.25,
	GLOW_FLARE = 0.3,
	GLOW_FLARE_SECONDS = 0.6,
	RAYS = 0.5,
	SHAKE = 0.45,
	SHAKE_PX = 5,
})

local Tray = {}

-- Whether the brew on show is a batch: it asked for more than one until the answer, then made more than one (a
-- batch cut short to one potion is shown on the result card alone).
local function isBatch(state: Types.TLabState): boolean
	if state.AnsweredAt() == math.huge then return state.Asked() > 1 end
	return #state.Batch() > 1
end

-- How many cards the tray holds: what was asked until the answer, then what was made.
local function countOf(state: Types.TLabState, times: Brew.TTimes): number
	if times.Cards then return #times.Cards end
	return state.Asked()
end

local function widthOf(count: number): (number, number)
	local gap = if count > 5 then Layout.GAP_TIGHT else Layout.GAP
	return math.min(Layout.CARD_MAX, math.floor((Layout.WIDTH - (count - 1) * gap) / count)), gap
end

local function rowTop(): number
	return Layout.ROW_Y + Parts.TopGrowth()
end

local function rowHeight(): number
	return Layout.ROW_HEIGHT + Parts.CardsGrowth()
end

-- The middle of card `index` of `count` in the page's px (the panel's raised layer): where its potion flies from.
function Tray.CardAt(index: number, count: number): Vector2
	local width, gap = widthOf(count)
	local span = count * width + (count - 1) * gap
	local x = Layout.CENTRE_X - span / 2 + (index - 1) * (width + gap) + width / 2
	return Vector2.new(math.round(x), math.round(rowTop() + rowHeight() / 2))
end

-- How much of the souls' section is on show, 0 to 1: it makes way as a batch is poured and comes back once the
-- tray has gone. 1 with no batch.
function Tray.SoulsShown(state: Types.TLabState): () -> number
	return derive(function(): number
		local times = Brew.Times(state)
		if not times or not isBatch(state) then return 1 end
		local now = state.Now()
		local out = Motion.Out(Progress(now, times.BrewAt, Timing.SOULS_OUT))
		if not times.Cards then return 1 - out end
		local back = Motion.Decelerate(Progress(now, Brew.TrayGoneAt(times), Timing.SOULS_BACK))
		return math.clamp(1 - out + back, 0, 1)
	end)
end

-- How far below their place the souls are while they make way, in px.
function Tray.SoulsDrop(shown: () -> number): () -> number
	return function(): number
		return Timing.SOULS_DROP * (1 - shown())
	end
end

-- The souls' header while the tray is up: what is brewing, then what was brewed; and how many have opened.
function Tray.Title(state: Types.TLabState, soulsShown: () -> number): () -> string
	return derive(function(): string
		if soulsShown() > 0.5 then return "SELECT SOULS" end
		local times = Brew.Times(state)
		if not times then return "SELECT SOULS" end
		local count = countOf(state, times)
		if not times.Cards or state.Now() < times.LandAt then return `BREWING {count} POTIONS` end
		return `{count} POTIONS BREWED`
	end)
end

function Tray.Info(state: Types.TLabState, soulsShown: () -> number): () -> string
	return derive(function(): string
		if soulsShown() > 0.5 then return "" end
		-- The cards open in the batch's order, the rarest last.
		local times = Brew.Times(state)
		local cards = if times then times.Cards else nil
		if not cards then return "" end
		local now = state.Now()
		local opened = 0
		for _, card in cards do
			if now >= card.LandAt then
				opened += 1
			end
		end
		if opened < #cards then return `{opened} / {#cards} OPENED` end
		return `BEST: {Parts.Rarity(cards[#cards].Rarity).Text}`
	end)
end

-- One card of the tray, slot `index`: drawn only while a batch holds that many.
local function trayCard(state: Types.TLabState, index: number): Frame
	local times = derive(function(): Brew.TTimes?
		local current = Brew.Times(state)
		if not current or not isBatch(state) then return nil end
		return current
	end)
	local count = derive(function(): number
		local current = times()
		return if current then countOf(state, current) else 0
	end)
	local opening = derive(function(): Brew.TCard?
		local current = times()
		local cards = if current then current.Cards else nil
		return if cards then cards[index] else nil
	end)
	local width = derive(function(): number
		return (widthOf(math.max(count(), 1)))
	end)
	-- 0 to 1 dealt in, 1 to 0 as it leaves: its fade.
	local dealt = derive(function(): number
		local current = times()
		if not current or index > count() then return 0 end
		return Motion.Decelerate(
			Progress(state.Now(), current.BrewAt, Timing.DEAL, Timing.DEAL_DELAY + Timing.DEAL_STAGGER * (index - 1))
		)
	end)
	local left = derive(function(): number
		local current = times()
		if not current or not current.Cards then return 0 end
		local goneAt = Brew.TrayGoneAt(current) - Brew.TRAY_LEAVE
		return Motion.Accelerate(Progress(state.Now(), goneAt, Timing.LEAVE, Timing.LEAVE_STAGGER * (index - 1)))
	end)
	local shown = derive(function(): number
		return dealt() * (1 - left())
	end)
	local step = derive(function(): number
		local card = opening()
		return if card then Brew.CardStep(card, state.Now()) else 0
	end)
	-- Seconds since it landed, nil before.
	local since = derive(function(): number?
		local card = opening()
		if not card then return nil end
		local t = state.Now() - card.LandAt
		return if t >= 0 then t else nil
	end)
	-- Seconds since its climb last stepped, nil outside the climb.
	local sinceStep = derive(function(): number?
		local card = opening()
		local current = step()
		if not card or current == 0 or since() then return nil end
		return state.Now() - (card.StartAt + card.Step * (current - ERarities.Common))
	end)
	local power = derive(function(): number
		local card = opening()
		return if card then Brew.Power(card.Rarity) else 0
	end)
	local accent = derive(function(): Color3
		local current = step()
		return if current > 0 then Parts.Rarity(current).Accent else Parts.LOCKED
	end)
	-- Its potion has left it for the POTIONS tab.
	local isThrown = derive(function(): boolean
		local current = times()
		if not current or not current.Cards then return false end
		return state.Now() >= current.FlyAt + Brew.FLY_STAGGER * (index - 1)
	end)
	local flash = derive(function(): number
		local t = since()
		if not t then return 1 end
		local fading = 1 - math.clamp(t / Timing.FLASH, 0, 1)
		return 1 - Motion.Lerp(Timing.FLASH_MIN, Timing.FLASH_MAX, power()) * fading * fading
	end)
	local ring = derive(function(): number
		local t = since()
		return if t then Progress(t, 0, Timing.RING) else 0
	end)
	local scale = derive(function(): number
		local value = Motion.Lerp(Timing.DEAL_FROM, 1, dealt()) * (1 - 0.1 * left())
		local t = since()
		if t then
			local punch = Motion.Lerp(Timing.PUNCH_MIN, Timing.PUNCH_MAX, power())
			value *= 1 + punch * (1 - Motion.Decelerate(Progress(t, 0, Timing.PUNCH)))
		end
		local stepT = sinceStep()
		if stepT then
			value *= 1 + Timing.STEP_PUNCH * (1 - Progress(stepT, 0, Timing.STEP_PUNCH_SECONDS))
		end
		return value
	end)
	local shake = derive(function(): Vector2
		local card = opening()
		local t = since()
		if not card or not t or card.Rarity < ERarities.Mythic or t >= Timing.SHAKE then return Vector2.zero end
		local now = state.Now()
		local strength = Timing.SHAKE_PX * (1 - t / Timing.SHAKE)
		return Vector2.new(math.sin(now * 61 + index), math.cos(now * 53 + index)) * strength
	end)
	-- Sealed, the bottle shakes harder as the brew builds; its climb and landing hold it still.
	local jiggle = derive(function(): Vector2
		local current = times()
		if not current or step() > 0 then return Vector2.zero end
		local now = state.Now()
		local build = Progress(now, current.BrewAt, Brew.WINDUP)
		local strength = Motion.Lerp(Timing.JIGGLE_MIN, Timing.JIGGLE_MAX, build)
		return Vector2.new(math.sin(now * 47 + index * 1.7), math.cos(now * 39 + index * 2.3)) * strength
	end)
	local isRayed = derive(function(): boolean
		local card = opening()
		return card ~= nil and card.Rarity >= ERarities.Epic
	end)
	local raysShown = derive(function(): number
		local t = since()
		if not t or not isRayed() then return 0 end
		return Progress(t, 0, Timing.RAYS) * (1 - left())
	end)
	local bottleCentre = function(): UDim2
		local wobble = jiggle()
		return UDim2.new(0.5, math.round(wobble.X), Layout.BOTTLE_Y, math.round(wobble.Y))
	end
	local back, front = Showcase.Build({
		Look = "Rays",
		Diameter = math.round(Layout.CARD_MAX * Layout.RAYS_SHARE),
		Floor = 0,
		Accent = accent,
		Shown = raysShown,
		CheeredAt = function()
			local card = opening()
			return if card then card.LandAt else -math.huge
		end,
		IsActive = function()
			return state.IsOpen() and raysShown() > 0
		end,
	}, {
		Position = UDim2.fromScale(0.5, Layout.BOTTLE_Y),
		ZIndex = 2,
		create("UIScale")({
			Scale = function()
				return width() / Layout.CARD_MAX
			end,
		}),
	}, {
		Position = UDim2.fromScale(0.5, Layout.BOTTLE_Y),
		ZIndex = 6,
		create("UIScale")({
			Scale = function()
				return width() / Layout.CARD_MAX
			end,
		}),
	})

	local face = Components.Card({
		Accent = accent,
		Tint = function()
			return if step() > 0 then 0.38 else 0.15
		end,
		Brackets = true,
		BracketLength = Layout.BRACKET_LENGTH,
		GlowTransparency = function()
			local t = since()
			if not t then return Timing.GLOW_SEALED end
			local flare = 1 - Progress(t, 0, Timing.GLOW_FLARE_SECONDS)
			return Timing.GLOW_LANDED - Timing.GLOW_POWER * power() - Timing.GLOW_FLARE * flare
		end,
	}, {
		Name = "Card",
		Position = UDim2.fromOffset(Layout.FADE_MARGIN, Layout.FADE_MARGIN),
		Size = UDim2.new(1, -2 * Layout.FADE_MARGIN, 1, -2 * Layout.FADE_MARGIN),
		Parts.Burst(ring, Timing.RING_REACH, accent, { ZIndex = 0 }),
		-- The bottle's well: the light and the bottle, clipped to the face.
		create("Frame")({
			Name = "Well",
			Position = UDim2.fromOffset(3, 3),
			Size = UDim2.new(1, -6, 1, -6),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = 2,
			create("Frame")({
				Name = "Inside",
				Position = UDim2.fromOffset(-3, -3),
				Size = UDim2.new(1, 6, 1, 6),
				BackgroundTransparency = 1,
				back,
				Components.Picture(EIcons.PotionBottle, {
					Name = "Bottle",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = bottleCentre,
					Size = function()
						return Components.PictureBox(
							math.min(math.round(width() * Layout.BOTTLE_SHARE), Layout.BOTTLE_MAX)
						)
					end,
					ImageColor3 = accent,
					ImageTransparency = function()
						if isThrown() then return 1 end
						return if step() > 0 then 0 else 0.3
					end,
					ZIndex = 4,
				}),
				front,
			}),
		}),
		create("Frame")({
			Name = "Flash",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Palette.White,
			BorderSizePixel = 0,
			ZIndex = 8,
			BackgroundTransparency = flash,
			Visible = function()
				return flash() < 1
			end,
			create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
		}),
		create("Frame")({
			Name = "TagBox",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -Layout.TAG_BOTTOM),
			Size = UDim2.fromOffset(0, Layout.TAG_HEIGHT),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			ZIndex = 5,
			create("UIScale")({
				Scale = function()
					local t = since()
					if not t then return 1 end
					local stamped = Motion.Decelerate(Progress(t, 0, Timing.STAMP, Timing.STAMP_DELAY))
					return Motion.Lerp(Timing.STAMP_FROM, 1, stamped)
				end,
			}),
			Parts.Tag(
				function()
					local current = step()
					return if current > 0 then Parts.Rarity(current).Text else "?"
				end,
				accent,
				function()
					local current = step()
					return current > 0 and Parts.Rarity(current).IsInk
				end,
				Layout.TAG_TEXT,
				{ Size = UDim2.fromOffset(0, Layout.TAG_HEIGHT) },
				Layout.TAG_PAD
			),
		}),
	})

	return create("Frame")({
		Name = `TrayCard{index}`,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			local at = Tray.CardAt(index, math.max(count(), index))
			local jolt = shake()
			return UDim2.fromOffset(
				at.X + math.round(jolt.X),
				at.Y + math.round(jolt.Y + Timing.DEAL_RISE * (1 - dealt()))
			)
		end,
		Size = function()
			return UDim2.fromOffset(width() + 2 * Layout.FADE_MARGIN, rowHeight() + 2 * Layout.FADE_MARGIN)
		end,
		BackgroundTransparency = 1,
		Visible = function()
			return shown() > 0.001
		end,
		ZIndex = 4,
		create("UIScale")({ Scale = scale }),
		Components.FadeGroup("Fade", shown, { Size = UDim2.fromScale(1, 1) }, { face }),
	})
end

-- Every card slot, among the MUTATE page's pieces.
function Tray.Build(state: Types.TLabState): { Frame }
	local cards = table.create(PotionsCore.MAX_BATCH)
	for index = 1, PotionsCore.MAX_BATCH do
		cards[index] = trayCard(state, index)
	end

	return cards
end

return Tray
