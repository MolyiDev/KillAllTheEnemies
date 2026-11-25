--!nonstrict
-- The MUTATE page on his panel: the two souls picked (ingredient slots), the potion they make (the result card), the
-- souls held (SELECT SOULS), how many to brew at once (countPicker) and BREW POTION, which sells that many brews for
-- Robux once the day's are used.
--
-- A brew is beats off its stamps (Brew.Times): BREW pressed pours both souls into the flask as pixels while the
-- card shakes and brightens (the wind-up, never shorter than WINDUP however fast the server answers); then the
-- rarity CLIMBS, the card's colour stepping up through the rarities to the one rolled, each step a tick higher and a
-- beat slower; then it LANDS: a white flash, one ring, the bottle punched in in its colour over rays, the name and
-- the tags. The rarer, the harder it lands. A batch opens its cards in the tray where the souls stood (Tray), and the
-- result card follows the best so far, landing with the last. Its potions then fly to the POTIONS tab (Flight).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Showcase = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Showcase)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local PotionsCore = require(ReplicatedStorage.GlobalShared.Core.PotionsCore)
local Brew = require(script.Parent.Brew)
local Parts = require(script.Parent.Parts)
local Tray = require(script.Parent.Tray)
local Picture = require(script.Parent.Parent.IndexController.Picture)
local countPicker = require(script.Parent.Parent.Parent.Utils.countPicker)
local Types = require(script.Parent.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress
local Label = Parts.Label

-- His drawn rects in px at 1080, from the screen's top left.
local Layout = table.freeze({
	INGREDIENTS = { Vector2.new(328, 306), Vector2.new(638, 306) },
	INGREDIENT_SIZE = 230,
	-- Inside an ingredient: the cost tag, the picture, the name band.
	COST_TAG = Rect.new(12, 12, 65, 40),
	PICTURE_CENTRE = Vector2.new(115, 92),
	ENEMY = 116,
	BAND = 45,
	BAND_TEXT = 19,
	PLUS = Vector2.new(597, 421),
	PLUS_SIZE = 34,
	ARROW = Vector2.new(909, 421),
	ARROW_SIZE = 44,
	RESULT = Rect.new(952, 306, 1592, 536),
	-- Inside the result card.
	FLASK_CENTRE = Vector2.new(119, 115),
	BOTTLE = 124,
	RAYS = 330,
	DIVIDER_X = 236,
	DIVIDER = Vector2.new(32, 200),
	TEXT_X = 262,
	NEW_TAG = Rect.new(262, 34, 383, 60),
	NAME_Y = 70,
	NAME_TEXT = 36,
	EFFECT_Y = { 118, 146 },
	EFFECT_TEXT = 21,
	RARITY_TAG_Y = 182,
	RARITY_TAG_HEIGHT = 26,
	TAG_TEXT = 14,
	-- SELECT SOULS and the cards under it: six across his panel's column, 24 apart (the bracket check: a 190 px Take
	-- card reaches 15 px at its press).
	HEADER_Y = 562,
	CARDS_Y = 626,
	CARD_SIZE = Vector2.new(190, 170),
	CARD_GAP = 24,
	CARD_ENEMY_Y = 58,
	CARD_ENEMY = 92,
	CARD_NAME_Y = 107,
	CARD_NAME_TEXT = 18,
	CARD_COUNT_Y = 135,
	CARD_COUNT_TEXT = 21,
	CHECK = 26,
	-- BREW POTION, 40 px off the count trigger: past the reach of a 1024 px Operate slab at its press.
	BREW = Rect.new(568, 845, 1592, 917),
	COUNT = Rect.new(328, 845, 528, 917),
	-- Round the souls' cards inside the group that fades them out for the tray: their glow, brackets and growth.
	SOULS_MARGIN = 48,
	BREW_TEXT = 30,
	BREW_GLYPH = 34,
	ROBUX = 26,
})

local Timing = table.freeze({
	-- The open's staging, by what the page is for: the souls, the slots and the result, then the bottom row.
	CARDS_DELAY = 0.04,
	CARDS_STAGGER = 0.035,
	SLOTS_DELAY = 0.1,
	RESULT_DELAY = 0.16,
	BOTTOM_DELAY = 0.22,
	RISE = 26,
	-- The bottom row (BREW and the count) rises less: it stands 23 px off the panel's bottom edge, and its brackets 6 px
	-- out of it, so a longer rise starts it past the edge.
	BOTTOM_RISE = 12,
	-- A pick: the picture drops into its slot and the slot flashes.
	PICK = 0.34,
	PICK_DROP = 30,
	PICK_FLASH = 0.22,
	-- A refusal's shake.
	REFUSE = 0.4,
	REFUSE_SHAKE = 8,
	-- The card on the hover: the monster turns this far to you.
	HOVER_TURN = 28,
	-- While BREW can go, the light crosses it this long.
	CALL = 0.7,
})

local Mutate = {}

local topGrowth = Parts.TopGrowth
local cardsGrowth = Parts.CardsGrowth

-- How far the middle of the top row moves down as it grows.
local function topShift(): number
	return math.round(topGrowth() / 2)
end

-- Where brewed potions leave from: the result card's flask, in the panel's raised layer.
function Mutate.FlaskAt(): Vector2
	return Layout.RESULT.Min + Layout.FLASK_CENTRE + Vector2.new(0, topShift())
end

-- The result card's look at `now`: the accent it wears, the rarity on its tag (0 for none), and how far into the
-- landing it is (nil before it). Worked out once a frame for every piece of the card.
local function resultLook(state: Types.TLabState)
	return derive(function()
		local shown = state.Shown()
		local times = Brew.Times(state)
		local now = state.Now()
		if times and now < times.LandAt then
			-- Still brewing: no rarity before the climb, then the step it has climbed to.
			local step = Brew.StepAt(times, now)
			return { Accent = if step > 0 then Parts.Rarity(step).Accent else Palette.Lavender, Rarity = step }
		end
		if shown then
			return {
				Accent = Parts.Rarity(shown.Rarity).Accent,
				Rarity = shown.Rarity,
				Since = if times then now - times.LandAt else math.huge,
			}
		end
		return { Accent = Palette.Gold, Rarity = 0 }
	end)
end

-- The recipe the two picks make, or nil.
local function pickedRecipe(state: Types.TLabState)
	return derive(function()
		local picks = state.Picks()
		if #picks < 2 then return nil end
		return PotionsCore.RecipeOf(picks[1], picks[2])
	end)
end

-- How many potions the picks' souls pay for, brews aside: 0 without two picks.
local function affordable(state: Types.TLabState): number
	local picks = state.Picks()
	if #picks < 2 then return 0 end
	local energy = state.Energy()
	local most = PotionsCore.MAX_BATCH
	for _, enemyId in picks do
		local _, kind = Parts.Energy(enemyId)
		most = math.min(most, (energy[enemyId] or 0) // kind.Cost)
	end
	return most
end

-- How many potions a brew of the picks could make now: their souls and the brews left both pay. Reads sources.
function Mutate.Possible(state: Types.TLabState): number
	return math.min(affordable(state), state.BrewsLeft())
end

-- How many BREW makes now: the count picked, held to what is possible, at least 1.
function Mutate.Count(state: Types.TLabState): number
	return math.max(math.min(state.BrewCount(), Mutate.Possible(state)), 1)
end

-- How many brews BREW sells once the day's are used: the count picked, held to what the souls pay for, down to a
-- count sold on its own (PotionsCore.BREW_PRODUCTS). 0 when none is for sale.
function Mutate.BuyCount(state: Types.TLabState): number
	local most = math.min(state.BrewCount(), affordable(state))
	local best = 0
	for _, count in PotionsCore.BREW_COUNTS do
		if count <= most and PotionsCore.BREW_PRODUCTS[count] ~= 0 then best = count end
	end
	return best
end

-- Why BREW cannot brew now, as its words, or nil when it can. Out of brews with the souls ready, it may sell one
-- instead (Mutate.Mode).
function Mutate.Blocker(state: Types.TLabState): string?
	local picks = state.Picks()
	if Brew.IsBusy(state) then return "BREWING..." end
	if #picks < 2 then return if #picks == 0 then "PICK 2 SOULS" else "PICK 1 MORE SOUL" end
	local energy = state.Energy()
	for _, enemyId in picks do
		local enemy, kind = Parts.Energy(enemyId)
		if (energy[enemyId] or 0) < kind.Cost then return `NOT ENOUGH {Parts.SoulsWord(enemy)}` end
	end
	if state.BrewsLeft() <= 0 then return "NO BREWS LEFT TODAY" end
	return nil
end

-- What BREW does now: brews, sells a brew for Robux (out of brews, the souls ready), or nothing.
function Mutate.Mode(state: Types.TLabState): "Brew" | "Buy" | "Off"
	local blocker = Mutate.Blocker(state)
	if not blocker then return "Brew" end
	local isOutOfBrews = state.BrewsLeft() <= 0 and affordable(state) > 0 and not Brew.IsBusy(state)
	if isOutOfBrews and state.CanBuyBrew() and Mutate.BuyCount(state) > 0 then return "Buy" end
	return "Off"
end

-- A shake of the head off a refusal stamped for `who`.
local function shakeOf(state: Types.TLabState, who: string): () -> number
	return derive(function(): number
		if state.Refused() ~= who then return 0 end
		local at = state.RefusedAt()
		return Timing.REFUSE_SHAKE * Motion.Shake(Progress(state.Now(), at, Timing.REFUSE), at)
	end)
end

-- ============================== Ingredients ==============================

local function ingredient(state: Types.TLabState, actions: Types.TLabActions, index: number, shown: () -> number)
	local at = Layout.INGREDIENTS[index]
	local size = Layout.INGREDIENT_SIZE
	local hand = Hand.React("Take", function(): boolean
		return state.Picks()[index] ~= nil and not Brew.IsBusy(state)
	end)
	local pick = derive(function(): number?
		return state.Picks()[index]
	end)
	local accent = derive(function(): Color3
		local enemyId = pick()
		if not enemyId then return Parts.LOCKED end
		local _, kind = Parts.Energy(enemyId)
		return kind.Color
	end)
	-- 0 to 1 over the picture's drop into the slot, from the pick's stamp.
	local dropped = derive(function(): number
		local enemyId = pick()
		local pickedAt = if enemyId then state.PickedAt()[enemyId] else nil
		if not pickedAt then return 1 end
		return Progress(state.Now(), pickedAt, Timing.PICK)
	end)
	-- The pour: the picture drains into the flask over the wind-up, and is back once the brew has landed.
	local poured = derive(function(): number
		local times = Brew.Times(state)
		if not times then return 0 end
		local now = state.Now()
		if now >= times.LandAt then return 1 - Progress(now, times.LandAt, 0.3) end
		return Motion.Out(Progress(now, times.BrewAt, Brew.WINDUP))
	end)
	local isEnough = derive(function(): boolean
		local enemyId = pick()
		if not enemyId then return true end
		local _, kind = Parts.Energy(enemyId)
		return (state.Energy()[enemyId] or 0) >= kind.Cost
	end)
	local shake = shakeOf(state, `Ingredient{index}`)

	return Components.Button({
		Name = `Ingredient{index}`,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			return UDim2.fromOffset(
				at.X + size / 2 + math.round(shake()),
				at.Y + (size + topGrowth()) / 2 + math.round(Timing.RISE * (1 - shown()))
			)
		end,
		Size = function()
			return UDim2.fromOffset(size, size + topGrowth())
		end,
		BackgroundTransparency = 1,
		ZIndex = 3,
		Interactable = Parts.Uncovered(state),
		Activated = function()
			if not pick() or Brew.IsBusy(state) then return end
			hand.Commit()
			actions.DropPick(index)
		end,
		hand.Events,
		create("UIScale")({
			Scale = function()
				return (0.9 + 0.1 * shown()) * hand.Scale()
			end,
		}),
		Components.Card({
			Accent = accent,
			Tint = 0.3,
			Band = Layout.BAND,
			Brackets = hand.Rise,
			GlowTransparency = function()
				return 0.7 - 0.25 * hand.Light() - 0.3 * poured()
			end,
		}, {
			Name = "Card",
			Size = UDim2.fromScale(1, 1),
			Hand.WashLayer(hand, 6, 2),
			-- The flash a pick lands with.
			create("Frame")({
				Name = "Flash",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Palette.White,
				BorderSizePixel = 0,
				ZIndex = 7,
				BackgroundTransparency = function()
					local t = Progress(dropped() * Timing.PICK, 0, Timing.PICK_FLASH)
					return if t >= 1 then 1 else 0.55 + 0.45 * t * t
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			}),
			Parts.Tag(
				function()
					local enemyId = pick()
					if not enemyId then return "" end
					local _, kind = Parts.Energy(enemyId)
					return `x{kind.Cost}`
				end,
				function()
					return if isEnough() then accent() else Palette.Grey
				end,
				true,
				16,
				{
					Position = UDim2.fromOffset(Layout.COST_TAG.Min.X, Layout.COST_TAG.Min.Y),
					Size = UDim2.fromOffset(Layout.COST_TAG.Width, Layout.COST_TAG.Height),
					Visible = function()
						return pick() ~= nil
					end,
				}
			),
			Picture.Build(function()
				local enemyId = pick()
				return if enemyId then DataCore.Enemies.ById[enemyId] else nil
			end, {
				Moving = hand.IsHovered,
				Transparency = function()
					return math.clamp(poured() * 1.2, 0, 1)
				end,
			}, {
				Name = "Enemy",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = function()
					local fall = 1 - Motion.Decelerate(dropped())
					return UDim2.fromOffset(
						Layout.PICTURE_CENTRE.X,
						Layout.PICTURE_CENTRE.Y
							+ topShift()
							- math.round(Timing.PICK_DROP * fall)
							- math.round(18 * poured())
					)
				end,
				Size = function()
					local px = math.round((Layout.ENEMY + topGrowth()) * (1 - 0.45 * poured()))
					return UDim2.fromOffset(px, px)
				end,
				ZIndex = 4,
			}),
			Label({
				Name = "Empty",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = function()
					return UDim2.fromOffset(Layout.PICTURE_CENTRE.X, Layout.PICTURE_CENTRE.Y + topShift())
				end,
				Size = UDim2.fromOffset(Layout.ENEMY, 40),
				TextSize = 40,
				TextColor3 = Palette.Lavender,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
				Text = "+",
				Visible = function()
					return pick() == nil
				end,
			}),
			Label({
				Name = "Name",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 1, -Layout.BAND / 2),
				Size = UDim2.new(1, -16, 0, Layout.BAND_TEXT),
				TextSize = Layout.BAND_TEXT,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextColor3 = function()
					return if pick() then Palette.White else Palette.Lavender
				end,
				Text = function()
					local enemyId = pick()
					if not enemyId then return "PICK A SOUL" end
					return Parts.SoulsWord(DataCore.Enemies.ById[enemyId])
				end,
				ZIndex = 5,
			}),
		}),
	}) :: TextButton
end

-- ============================== Result ==============================

-- The soul pixels the pour throws from both slots into the flask over the wind-up: each on a curve bent to one
-- side by a share of the trip, launched in a stagger, accelerating in. Parked off the card while there is no pour.
local function motes(state: Types.TLabState): { Frame }
	local list = {}
	local flask = Layout.RESULT.Min + Layout.FLASK_CENTRE
	for side = 1, 2 do
		local from = Layout.INGREDIENTS[side] + Vector2.new(Layout.PICTURE_CENTRE.X, Layout.PICTURE_CENTRE.Y)
		local trip = flask - from
		local normal = Vector2.new(-trip.Y, trip.X).Unit
		for index = 1, Brew.MOTES do
			-- Fixed per mote, so a pour looks the same every time but no two motes share a path.
			local bend = (if index % 2 == 0 then 1 else -1) * (0.12 + 0.05 * (index % 4)) * trip.Magnitude
			local launch = (index - 1) / Brew.MOTES * Brew.POUR_SPREAD + (side - 1) * 0.06
			local size = 6 + (index % 3) * 2
			local t = derive(function(): number?
				local times = Brew.Times(state)
				if not times then return nil end
				local flown = Progress(state.Now(), times.BrewAt + launch, Brew.MOTE_FLIGHT)
				return if flown > 0 and flown < 1 then flown else nil
			end)
			local color = function(): Color3
				local enemyId = state.Picks()[side]
				if not enemyId then return Palette.White end
				local _, kind = Parts.Energy(enemyId)
				return kind.Color
			end
			list[#list + 1] = create("Frame")({
				Name = "Mote",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = function()
					local at = t()
					if not at then return UDim2.fromOffset(-100, -100) end
					local eased = Motion.Accelerate(at) * 0.7 + at * 0.3
					-- The slots' pictures and the flask move down alike as the top row grows: only the point does.
					local point = from + trip * eased + normal * (bend * Motion.Bump(eased))
					return UDim2.fromOffset(math.round(point.X), math.round(point.Y) + topShift())
				end,
				Size = UDim2.fromOffset(size, size),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				ZIndex = 8,
				BackgroundTransparency = function()
					local at = t()
					return if at then 0.1 + 0.6 * Motion.Bump(math.max(at - 0.75, 0) * 4) else 1
				end,
				create("UIShadow")({
					BlurRadius = UDim.new(0, 10),
					Color = color,
					Spread = UDim2.new(),
					Transparency = 0.35,
					ZIndex = -1,
				}),
			})
		end
	end

	return list
end

-- Bubbles rising in the flask while it brews: pixels in the card's colour, swelling in and shrinking away.
local function bubbles(state: Types.TLabState, look: () -> any): { Frame }
	local list = {}
	for index = 1, Brew.BUBBLES do
		local x = ((index * 37) % 90) - 45
		local period = 0.55 + (index % 4) * 0.12
		local offset = index / Brew.BUBBLES
		local t = derive(function(): number?
			local times = Brew.Times(state)
			if not times or state.Now() >= times.LandAt then return nil end
			local since = state.Now() - times.BrewAt
			return ((since / period) + offset) % 1
		end)
		list[index] = create("Frame")({
			Name = "Bubble",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				local at = t()
				if not at then return UDim2.fromOffset(-100, -100) end
				return UDim2.fromOffset(
					Layout.FLASK_CENTRE.X + x + math.round(4 * math.sin(at * 9 + index)),
					Layout.FLASK_CENTRE.Y + topShift() + 55 - math.round(110 * at)
				)
			end,
			Size = function()
				local at = t()
				local px = if at then math.round(4 + 6 * Motion.Bump(at)) else 0
				return UDim2.fromOffset(px, px)
			end,
			BackgroundColor3 = function()
				return look().Accent
			end,
			BorderSizePixel = 0,
			ZIndex = 6,
		})
	end
	return list
end

local function resultCard(state: Types.TLabState, actions: Types.TLabActions, shown: () -> number): { any }
	local look = resultLook(state)
	local recipe = pickedRecipe(state)
	local hand = Hand.React("Operate", function(): boolean
		return state.Shown() ~= nil and not Brew.IsBusy(state)
	end)
	local rect = Layout.RESULT
	-- How far into the landing, 0 to 1 over its first LAND seconds; nil while there is none to show.
	local landed = derive(function(): number?
		local since = look().Since
		if not since then return nil end
		return math.clamp(since / Brew.LAND, 0, 1)
	end)
	local power = derive(function(): number
		return Brew.Power(look().Rarity)
	end)
	-- The card's shake through the wind-up and the climb, harder as it builds, and the landing's thump.
	local shake = derive(function(): Vector2
		local times = Brew.Times(state)
		if not times then return Vector2.zero end
		local now = state.Now()
		local strength = 0
		if now < times.LandAt then
			strength = 1 + 3 * Progress(now, times.BrewAt, times.LandAt - times.BrewAt)
		else
			strength = 8 * power() * (1 - Progress(now, times.LandAt, 0.35))
		end
		if strength <= 0.05 then return Vector2.zero end
		return Vector2.new(math.sin(now * 61), math.cos(now * 53)) * strength
	end)
	-- The white the card lands with, squared and short (UI.md: a long linear flash reads as disabled).
	local flash = derive(function(): number
		local at = landed()
		if not at then return 1 end
		local t = Progress(at * Brew.LAND, 0, 0.26)
		return if t >= 1 then 1 else t * t
	end)
	local ring = derive(function(): number
		local at = landed()
		return if at then Progress(at * Brew.LAND, 0, 0.55) else 0
	end)
	local punch = derive(function(): number
		local at = landed()
		if not at then return 1 end
		local t = Progress(at * Brew.LAND, 0, 0.4)
		return 1 + (0.35 + 0.35 * power()) * (1 - Motion.Decelerate(t))
	end)
	local isRevealed = derive(function(): boolean
		return look().Since ~= nil
	end)
	local brewing = derive(function(): boolean
		return Brew.IsBusy(state) and not isRevealed()
	end)
	local climbPunch = derive(function(): number
		local times = Brew.Times(state)
		if not times then return 1 end
		local since = Brew.SinceStep(times, state.Now())
		if not since then return 1 end
		return 1 + 0.18 * (1 - Motion.Decelerate(math.clamp(since / 0.18, 0, 1)))
	end)
	local accent = function(): Color3
		return look().Accent
	end
	-- The words: the potion shown, or the recipe the picks make, or what is missing.
	local nameText = derive(function(): string
		local shownPotion = state.Shown()
		if brewing() then return "BREWING..." end
		if shownPotion then return string.upper(DataCore.Potions.ById[shownPotion.Recipe].Name) end
		local made = recipe()
		if made then return if state.Found()[made.Id] then string.upper(made.Name) else "UNKNOWN POTION" end
		return if #state.Picks() == 0 then "MIX TWO SOULS" else "PICK ONE MORE"
	end)
	local lines = derive(function(): { string }
		if brewing() then return {} end
		local shownPotion = state.Shown()
		if shownPotion then return Parts.EffectLines(DataCore.Potions.ById[shownPotion.Recipe], shownPotion.Rarity) end
		local made = recipe()
		if made then return Parts.EffectLines(made, 1) end
		local picks = state.Picks()
		if #picks == 1 then
			local _, kind = Parts.Energy(picks[1])
			return {
				PotionsCore.Describe({ Upgrade = kind.Upgrade, Amount = DataCore.Upgrades.ById[kind.Upgrade].Value }),
			}
		end
		return { "Each soul adds its own power", "Rarer potions add up to 3x" }
	end)
	local isNew = derive(function(): boolean
		if brewing() then return false end
		if state.Shown() then return state.IsShownNew() end
		local made = recipe()
		return made ~= nil and not state.Found()[made.Id]
	end)
	-- The rarity row: the potion's tag and its matches, or a preview's odds.
	local rarityText = derive(function(): string
		local rarity = look().Rarity
		if rarity > 0 then return Parts.Rarity(rarity).Text end
		return "?"
	end)
	local rarityWords = derive(function(): string
		if brewing() then return "" end
		local shownPotion = state.Shown()
		local made = #state.Batch()
		if shownPotion and made > 1 then return `BEST OF {made}: {Parts.MatchesWord(shownPotion.Matches)}` end
		if shownPotion then return Parts.MatchesWord(shownPotion.Matches) end
		if not recipe() then return "" end
		local chances = PotionsCore.Chances(state.Luck())
		local mythic = chances[Parts.MAX_RARITY] * 100
		local luck = if state.Luck() > 1 then " (DOUBLE LUCK)" else ""
		return `MYTHIC {string.format("%.0f", mythic)}%{luck}: LASTS 2 MATCHES`
	end)
	local isFaded = derive(function(): boolean
		return state.Shown() == nil and recipe() == nil
	end)
	local flaskCentre = function(): UDim2
		return UDim2.fromOffset(Layout.FLASK_CENTRE.X, Layout.FLASK_CENTRE.Y + topShift())
	end
	-- Rays behind the bottle in its colour, once it lands; cheered on every landing.
	local showcaseShown = derive(function(): number
		local at = landed()
		if not at then return 0 end
		return math.clamp(at * Brew.LAND / 0.5, 0, 1)
	end)
	local back, front = Showcase.Build({
		Look = "Rays",
		Diameter = Layout.RAYS,
		Floor = 0,
		Accent = accent,
		Shown = showcaseShown,
		CheeredAt = function()
			local times = Brew.Times(state)
			return if times then times.LandAt else -math.huge
		end,
		IsActive = function()
			return state.IsOpen() and state.Tab() == 1 and state.Shown() ~= nil
		end,
	}, {
		Position = flaskCentre,
		ZIndex = 3,
	}, {
		Position = flaskCentre,
		ZIndex = 7,
	})
	local textAway = derive(function(): number
		local at = landed()
		if not at then return 0 end
		return 1 - Motion.Decelerate(Progress(at * Brew.LAND, 0.12, 0.3))
	end)

	local card = Components.Button({
		Name = "Result",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			local jolt = shake()
			return UDim2.fromOffset(
				rect.Min.X + rect.Width / 2 + math.round(jolt.X),
				rect.Min.Y
					+ (rect.Height + topGrowth()) / 2
					+ math.round(jolt.Y)
					+ math.round(Timing.RISE * (1 - shown()))
			)
		end,
		Size = function()
			return UDim2.fromOffset(rect.Width, rect.Height + topGrowth())
		end,
		BackgroundTransparency = 1,
		ZIndex = 3,
		Interactable = Parts.Uncovered(state),
		-- A potion on show is one press from where it went.
		Activated = function()
			if not state.Shown() or Brew.IsBusy(state) then return end
			hand.Commit()
			actions.PickTab(2)
		end,
		hand.Events,
		create("UIScale")({
			Scale = function()
				return (0.9 + 0.1 * shown()) * hand.Scale()
			end,
		}),
		Components.Card({
			Accent = accent,
			Tint = function()
				return if isFaded() then 0.12 else 0.32
			end,
			Wide = true,
			Brackets = hand.Rise,
			GlowTransparency = function()
				local times = Brew.Times(state)
				local build = if times and brewing()
					then Progress(state.Now(), times.BrewAt, times.LandAt - times.BrewAt)
					else 0
				return math.clamp(0.7 - 0.35 * build - 0.4 * power() * (1 - (landed() or 1)), 0.15, 0.85)
			end,
		}, {
			Name = "Card",
			Size = UDim2.fromScale(1, 1),
			Hand.WashLayer(hand, 9, 2),
			create("Frame")({
				Name = "Flash",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Palette.White,
				BorderSizePixel = 0,
				ZIndex = 10,
				BackgroundTransparency = flash,
				Visible = function()
					return flash() < 1
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			}),
			Parts.Burst(ring, 40, accent, { ZIndex = 0 }),
			-- The flask's well: the rays and the bottle, clipped to the card's face.
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
					bubbles(state, look),
					Components.Picture(EIcons.PotionBottle, {
						Name = "Bottle",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = flaskCentre,
						Size = function()
							return Components.PictureBox(Layout.BOTTLE + topGrowth())
						end,
						ImageColor3 = function()
							if isFaded() then return Parts.LOCKED end
							return look().Accent
						end,
						ImageTransparency = function()
							return if isFaded() then 0.35 else 0
						end,
						ZIndex = 5,
						create("UIScale")({
							Scale = function()
								if brewing() then
									local times = Brew.Times(state)
									local wobble = if times then math.sin(state.Now() * 22) * 0.03 else 0
									return climbPunch() * (1 + wobble)
								end
								return punch()
							end,
						}),
					}),
					front,
				}),
			}),
			create("Frame")({
				Name = "Divider",
				Position = UDim2.fromOffset(Layout.DIVIDER_X, Layout.DIVIDER.X),
				Size = function()
					return UDim2.fromOffset(1, Layout.DIVIDER.Y - Layout.DIVIDER.X + topGrowth())
				end,
				BackgroundColor3 = accent,
				BackgroundTransparency = 0.6,
				BorderSizePixel = 0,
				ZIndex = 3,
			}),
			create("Frame")({
				Name = "Words",
				Position = function()
					return UDim2.fromOffset(math.round(24 * textAway()), topShift())
				end,
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ZIndex = 4,
				Parts.Tag("NEW POTION", Palette.Gold, true, Layout.TAG_TEXT, {
					Position = UDim2.fromOffset(Layout.NEW_TAG.Min.X, Layout.NEW_TAG.Min.Y),
					Size = UDim2.fromOffset(Layout.NEW_TAG.Width, Layout.NEW_TAG.Height),
					Visible = isNew,
				}),
				Label({
					Name = "Name",
					Position = UDim2.fromOffset(Layout.TEXT_X, Layout.NAME_Y),
					Size = UDim2.fromOffset(rect.Width - Layout.TEXT_X - 20, Layout.NAME_TEXT),
					TextSize = Layout.NAME_TEXT,
					TextTruncate = Enum.TextTruncate.AtEnd,
					TextColor3 = function()
						return if isFaded() then Palette.Lavender else Palette.White
					end,
					TextTransparency = textAway,
					Text = nameText,
				}),
				Label({
					Name = "Effect1",
					Position = UDim2.fromOffset(Layout.TEXT_X, Layout.EFFECT_Y[1]),
					Size = UDim2.fromOffset(rect.Width - Layout.TEXT_X - 20, Layout.EFFECT_TEXT),
					FontFace = Font.Display,
					TextSize = Layout.EFFECT_TEXT,
					TextColor3 = function()
						return if isFaded() then Palette.Lavender else Palette.White
					end,
					TextTransparency = textAway,
					Text = function()
						return lines()[1] or ""
					end,
				}),
				Label({
					Name = "Effect2",
					Position = UDim2.fromOffset(Layout.TEXT_X, Layout.EFFECT_Y[2]),
					Size = UDim2.fromOffset(rect.Width - Layout.TEXT_X - 20, Layout.EFFECT_TEXT),
					FontFace = Font.Display,
					TextSize = Layout.EFFECT_TEXT,
					TextColor3 = function()
						return if isFaded() then Palette.Lavender else Palette.White
					end,
					TextTransparency = textAway,
					Text = function()
						return lines()[2] or ""
					end,
				}),
				create("Frame")({
					Name = "RarityRow",
					Position = UDim2.fromOffset(Layout.TEXT_X, Layout.RARITY_TAG_Y),
					Size = UDim2.fromOffset(rect.Width - Layout.TEXT_X - 20, Layout.RARITY_TAG_HEIGHT),
					BackgroundTransparency = 1,
					Visible = function()
						return look().Rarity > 0 or recipe() ~= nil or state.Shown() ~= nil
					end,
					create("UIListLayout")({
						FillDirection = Enum.FillDirection.Horizontal,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, 12),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
					create("Frame")({
						Name = "TagBox",
						LayoutOrder = 1,
						AutomaticSize = Enum.AutomaticSize.X,
						Size = UDim2.fromOffset(0, Layout.RARITY_TAG_HEIGHT),
						BackgroundTransparency = 1,
						create("UIScale")({ Scale = climbPunch }),
						Parts.Tag(rarityText, function()
							return if look().Rarity > 0 then look().Accent else Parts.LOCKED
						end, function()
							local rarity = look().Rarity
							return rarity > 0 and Parts.Rarity(rarity).IsInk
						end, Layout.TAG_TEXT, { Size = UDim2.fromOffset(0, Layout.RARITY_TAG_HEIGHT) }, 14),
					}),
					Label({
						Name = "Matches",
						LayoutOrder = 2,
						AutomaticSize = Enum.AutomaticSize.X,
						Size = UDim2.fromOffset(0, 15),
						FontFace = Font.DisplayBold,
						TextSize = 15,
						TextColor3 = Palette.Lavender,
						TextTransparency = textAway,
						Text = rarityWords,
					}),
				}),
			}),
		}),
	}) :: TextButton

	return {
		card,
		Label({
			Name = "Plus",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				return UDim2.fromOffset(
					Layout.PLUS.X,
					Layout.PLUS.Y + topShift() + math.round(Timing.RISE * (1 - shown()))
				)
			end,
			Size = UDim2.fromOffset(Layout.PLUS_SIZE * 2, Layout.PLUS_SIZE * 2),
			TextSize = 56,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextTransparency = function()
				return 1 - shown()
			end,
			Text = "+",
		}),
		Components.Picture(EIcons.Arrow, {
			Name = "Into",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				local times = Brew.Times(state)
				local nudge = if times and brewing() then 6 * math.abs(math.sin(state.Now() * 8)) else 0
				return UDim2.fromOffset(
					Layout.ARROW.X + math.round(nudge),
					Layout.ARROW.Y + topShift() + math.round(Timing.RISE * (1 - shown()))
				)
			end,
			Size = Components.PictureBox(Layout.ARROW_SIZE),
			ImageColor3 = Palette.Pink,
			ImageTransparency = function()
				return 1 - shown()
			end,
			ZIndex = 3,
		}),
	}
end

-- ============================== Energy ==============================

local function energyCard(
	state: Types.TLabState,
	actions: Types.TLabActions,
	enemy: any,
	index: number,
	soulsShown: () -> number
): TextButton
	local enemyId = enemy.Id
	local kind = enemy.Energy
	local x = Parts.LEFT + 2 + (index - 1) * (Layout.CARD_SIZE.X + Layout.CARD_GAP)
	local dealt = Parts.Dealt(state, 1, Timing.CARDS_DELAY + Timing.CARDS_STAGGER * (index - 1))
	local isKnown = derive(function(): boolean
		return state.Discovered()[enemyId] == true or (state.Energy()[enemyId] or 0) > 0
	end)
	local isPicked = derive(function(): boolean
		return table.find(state.Picks(), enemyId) ~= nil
	end)
	local hand = Hand.React("Take", function(): boolean
		return isKnown() and not Brew.IsBusy(state)
	end)
	local held = derive(function(): number
		return state.Energy()[enemyId] or 0
	end)
	local accent = function(): Color3
		return if isKnown() then kind.Color else Parts.LOCKED
	end
	local shake = shakeOf(state, `Energy{enemyId}`)
	-- The held count rolls down as a brew spends it.
	local count = Hand.Spring(held, 0.35)
	-- The monster grows with the card, its top staying put.
	local enemyCentre = function(): UDim2
		return UDim2.fromOffset(Layout.CARD_SIZE.X / 2, Layout.CARD_ENEMY_Y + math.round(cardsGrowth() / 2))
	end

	return Components.Button({
		Name = `Energy{enemyId}`,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			return UDim2.fromOffset(
				x + Layout.CARD_SIZE.X / 2 + math.round(shake()),
				Layout.CARDS_Y
					+ topGrowth()
					+ (Layout.CARD_SIZE.Y + cardsGrowth()) / 2
					+ math.round(Timing.RISE * (1 - dealt()))
			)
		end,
		Size = function()
			return UDim2.fromOffset(Layout.CARD_SIZE.X, Layout.CARD_SIZE.Y + cardsGrowth())
		end,
		BackgroundTransparency = 1,
		ZIndex = 3,
		-- Not while the tray stands in the souls' place.
		Interactable = function()
			return not state.IsMenuOpen() and soulsShown() >= 1
		end,
		Activated = function()
			if isKnown() and not Brew.IsBusy(state) then hand.Commit() end
			actions.PickEnergy(enemyId)
		end,
		hand.Events,
		create("UIScale")({
			Scale = function()
				return (0.9 + 0.1 * dealt()) * hand.Scale()
			end,
		}),
		Components.Card({
			Accent = accent,
			Tint = 0.3,
			Brackets = hand.Rise,
			BracketsClosed = isPicked,
			GlowTransparency = function()
				return if isPicked() then 0.45 else 0.75 - 0.25 * hand.Light()
			end,
		}, {
			Name = "Card",
			Size = UDim2.fromScale(1, 1),
			Hand.WashLayer(hand, 6, 2),
			create("Frame")({
				Name = "Fade",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ZIndex = 3,
				Picture.Build(function()
					return if isKnown() then enemy else nil
				end, {
					Moving = function()
						return hand.IsHovered() or isPicked()
					end,
					Yaw = function()
						return Timing.HOVER_TURN * hand.Rise()
					end,
				}, {
					Name = "Enemy",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = enemyCentre,
					Size = function()
						local px = Layout.CARD_ENEMY + cardsGrowth()
						return UDim2.fromOffset(px, px)
					end,
					ZIndex = 3,
				}),
				Components.Picture(EIcons.Lock, {
					Name = "Lock",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = enemyCentre,
					Size = Components.PictureBox(64),
					ImageColor3 = Color3.fromRGB(120, 110, 150),
					Visible = function()
						return not isKnown()
					end,
					ZIndex = 3,
				}),
				Label({
					Name = "Name",
					AnchorPoint = Vector2.new(0.5, 0),
					Position = function()
						return UDim2.fromOffset(Layout.CARD_SIZE.X / 2, Layout.CARD_NAME_Y + cardsGrowth())
					end,
					Size = UDim2.fromOffset(Layout.CARD_SIZE.X - 12, Layout.CARD_NAME_TEXT),
					TextSize = Layout.CARD_NAME_TEXT,
					TextXAlignment = Enum.TextXAlignment.Center,
					TextColor3 = function()
						return if isKnown() then Palette.White else Palette.Lavender
					end,
					Text = function()
						return if isKnown() then Parts.EnergyWord(enemy) else "???"
					end,
				}),
				Label({
					Name = "Count",
					AnchorPoint = Vector2.new(0.5, 0),
					Position = function()
						return UDim2.fromOffset(Layout.CARD_SIZE.X / 2, Layout.CARD_COUNT_Y + cardsGrowth())
					end,
					Size = UDim2.fromOffset(Layout.CARD_SIZE.X - 12, Layout.CARD_COUNT_TEXT),
					TextSize = Layout.CARD_COUNT_TEXT,
					TextXAlignment = Enum.TextXAlignment.Center,
					TextColor3 = function()
						if not isKnown() then return Palette.Lavender end
						return if held() >= kind.Cost then kind.Color else Palette.Lavender
					end,
					Text = function()
						if not isKnown() then return "LOCKED" end
						local shownCount = math.max(math.round(count()), 0)
						if held() >= kind.Cost then return `x{shownCount}` end
						return `x{shownCount} / {kind.Cost}`
					end,
				}),
			}),
			-- His check box in the top right of a picked card.
			create("Frame")({
				Name = "Check",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -10, 0, 10),
				Size = UDim2.fromOffset(Layout.CHECK, Layout.CHECK),
				BackgroundColor3 = Palette.Ink,
				BorderSizePixel = 0,
				ZIndex = 6,
				Visible = isPicked,
				create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
				create("UIStroke")({ Color = Palette.Green, Thickness = 2 }),
				Components.Picture(EIcons.Check, {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = Components.PictureBox(Layout.CHECK - 6),
					ImageColor3 = Palette.Green,
				}),
			}),
		}),
	}) :: TextButton
end

-- ============================== Bottom ==============================

-- BREW POTION: green while it can go, with the light crossing it now and then; violet with the price where a brew is
-- sold for Robux; grey with what is missing otherwise.
local function brewButton(state: Types.TLabState, actions: Types.TLabActions): TextButton
	local rect = Layout.BREW
	local mode = derive(function(): string
		return Mutate.Mode(state)
	end)
	local isLive = derive(function(): boolean
		return mode() ~= "Off"
	end)
	local isBuy = derive(function(): boolean
		return mode() == "Buy"
	end)
	local words = derive(function(): string
		local current = mode()
		if current == "Buy" then
			local count = Mutate.BuyCount(state)
			return if count == 1 then "BUY A BREW" else `BUY {count} BREWS`
		end
		if current == "Off" then return Mutate.Blocker(state) or "" end
		local count = Mutate.Count(state)
		return if count == 1 then "BREW POTION" else `BREW {count} POTIONS`
	end)
	local hand = Hand.React("Operate", isLive)
	local shake = shakeOf(state, "Brew")
	local called = derive(function(): number
		if not isLive() then return 1 end
		return Progress(state.Now(), state.CalledAt(), Timing.CALL)
	end)

	return Components.Button({
		Name = "Brew",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			return UDim2.fromOffset(rect.Min.X + rect.Width / 2 + math.round(shake()), rect.Min.Y + rect.Height / 2)
		end,
		Size = UDim2.fromOffset(rect.Width, rect.Height),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Interactable = Parts.Uncovered(state),
		Activated = function()
			hand.Commit()
			actions.Brew()
		end,
		hand.Events,
		create("UIScale")({ Scale = hand.Scale }),
		Components.Slab({
			Kind = function()
				local current = mode()
				if current == "Brew" then return "Go" end
				return if current == "Buy" then "Violet" else "Off"
			end,
			Marks = true,
			Brackets = hand.Rise,
			GlowTransparency = function()
				return if isLive() then 0.6 - 0.3 * hand.Light() else 0.85
			end,
		}, {
			Name = "Slab",
			Size = UDim2.fromScale(1, 1),
			Hand.WashLayer(hand, 3, 3),
			Components.Sheen(Hand.Sheen(hand, called), 3, rect.Width / rect.Height),
			create("Frame")({
				Name = "Row",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ZIndex = 4,
				create("UIListLayout")({
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 14),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
				Components.Picture(EIcons.Flask, {
					LayoutOrder = 1,
					Size = Components.PictureBox(Layout.BREW_GLYPH),
					ImageTransparency = function()
						return if isLive() then 0 else 0.4
					end,
				}),
				Label({
					LayoutOrder = 2,
					AutomaticSize = Enum.AutomaticSize.X,
					Size = UDim2.fromOffset(0, Layout.BREW_TEXT),
					TextSize = Layout.BREW_TEXT,
					TextColor3 = function()
						return if isLive() then Palette.White else Palette.Lavender
					end,
					Text = words,
				}),
				Components.Icon("Robux", {
					Name = "Robux",
					LayoutOrder = 3,
					Size = Components.GlyphBox(Layout.ROBUX),
					ImageColor3 = Palette.White,
					Visible = isBuy,
				}),
				Label({
					Name = "Price",
					LayoutOrder = 4,
					AutomaticSize = Enum.AutomaticSize.X,
					Size = UDim2.fromOffset(0, Layout.BREW_TEXT),
					TextSize = Layout.BREW_TEXT,
					Visible = isBuy,
					Text = function()
						return tostring(PotionsCore.BREW_PRICES[Mutate.BuyCount(state)] or 0)
					end,
				}),
			}),
		}),
	}) :: TextButton
end

function Mutate.Build(state: Types.TLabState, actions: Types.TLabActions): { any }
	local slots = Parts.Dealt(state, 1, Timing.SLOTS_DELAY)
	local result = Parts.Dealt(state, 1, Timing.RESULT_DELAY)
	local bottom = Parts.Dealt(state, 1, Timing.BOTTOM_DELAY)
	local header = Parts.Dealt(state, 1, 0)
	-- Once for the count menu's rows.
	local souls = derive(function(): number
		return affordable(state)
	end)
	local isLive = derive(function(): boolean
		return Mutate.Mode(state) ~= "Off"
	end)
	local soulsShown = Tray.SoulsShown(state)
	local soulsDrop = Tray.SoulsDrop(soulsShown)
	-- The souls' section's room inside the group that fades it as the tray takes its place: the cards, their glow,
	-- brackets and the hand's growth.
	local groupAt = function(): Vector2
		return Vector2.new(Parts.LEFT - Layout.SOULS_MARGIN, Layout.CARDS_Y + topGrowth() - Layout.SOULS_MARGIN)
	end

	local cards = {}
	for index, enemy in PotionsCore.ENERGIES do
		cards[index] = energyCard(state, actions, enemy, index, soulsShown)
	end

	return {
		ingredient(state, actions, 1, slots),
		ingredient(state, actions, 2, slots),
		resultCard(state, actions, result),
		motes(state),
		Parts.Header(
			Tray.Title(state, soulsShown),
			Tray.Info(state, soulsShown),
			Layout.HEADER_Y,
			function()
				return if soulsShown() > 0.5 then EIcons.Soul else EIcons.PotionBottle
			end,
			nil,
			{
				Position = function()
					return UDim2.fromOffset(Parts.LEFT, Layout.HEADER_Y + topGrowth() + math.round(12 * (1 - header())))
				end,
			}
		),
		Components.FadeGroup("Souls", soulsShown, {
			Position = function()
				local at = groupAt()
				return UDim2.fromOffset(at.X, at.Y)
			end,
			Size = function()
				return UDim2.fromOffset(
					Parts.RIGHT - Parts.LEFT + 2 * Layout.SOULS_MARGIN,
					Layout.CARD_SIZE.Y + cardsGrowth() + 2 * Layout.SOULS_MARGIN
				)
			end,
			ZIndex = 3,
		}, {
			create("Frame")({
				Name = "Screen",
				Position = function()
					local at = groupAt()
					return UDim2.fromOffset(-at.X, -at.Y + math.round(soulsDrop()))
				end,
				Size = UDim2.fromOffset(1920, 1080),
				BackgroundTransparency = 1,
				cards,
			}),
		}),
		Tray.Build(state),
		-- His rects, so the bottom row keeps its place as the panel grows over it, rising in as one; over the cards,
		-- where the count's menu opens.
		create("Frame")({
			Name = "Bottom",
			Position = function()
				return UDim2.fromOffset(0, Parts.Lift() + math.round(Timing.BOTTOM_RISE * (1 - bottom())))
			end,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 11,
			brewButton(state, actions),
			countPicker.Build({
				Rect = Layout.COUNT,
				Caption = "BREW",
				Options = PotionsCore.BREW_COUNTS,
				Picked = state.BrewCount,
				IsOpen = state.IsMenuOpen,
				MenuAt = state.MenuAt,
				Now = state.Now,
				IsLive = isLive,
				IsReachable = function(count: number): boolean
					return count <= math.max(souls(), 1)
				end,
				Price = function(count: number): number?
					local isSold = state.BrewsLeft() <= 0
						and state.CanBuyBrew()
						and PotionsCore.BREW_PRODUCTS[count] ~= 0
					return if isSold then PotionsCore.BREW_PRICES[count] else nil
				end,
				SetOpen = actions.SetMenu,
				Pick = actions.PickCount,
			}),
		}),
	}
end

return Mutate
