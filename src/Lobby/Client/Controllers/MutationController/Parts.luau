--!nonstrict
-- What the Mutation Lab's pieces share: his panel's rect, the open's clock and curves, the rarities' looks, a
-- potion's words, and his section header and flat tag.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local PotionsCore = require(ReplicatedStorage.GlobalShared.Core.PotionsCore)
local panelTop = require(script.Parent.Parent.Parent.Utils.panelTop)
local ERarities = require(ReplicatedStorage.Types.Enums.ERarities)
local TData = require(ReplicatedStorage.Types.TData)
local Types = require(script.Parent.Types)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress

local Parts = {}

-- His drawn rects in px at 1080, from the screen's top left (UIMatt.md, Monster Mutation; measured off his PNGs).
Parts.PANEL = Rect.new(301, 170, 1619, 940)
-- How far the panel is raised to just under the top bar, its bottom staying put (Screen).
Parts.Lift = panelTop.Lift(Parts.PANEL.Min.Y)
-- Inside it, the column every row lines up on.
Parts.LEFT = 328
Parts.RIGHT = 1592

-- The room the panel's rise makes goes to the MUTATE page's cards: the top row (the slots, the result card) and the
-- souls' cards under it each grow by a share, the souls' header and cards moving down by the top row's.
function Parts.TopGrowth(): number
	return math.floor(Parts.Lift() / 2)
end

function Parts.CardsGrowth(): number
	return Parts.Lift() - Parts.TopGrowth()
end

-- A screen's open and shut (UI.md 5o): pieces decelerate in, staged by what the screen is for, and accelerate out
-- faster; every fade runs on its own clock.
Parts.Timing = table.freeze({
	FADE = 0.3,
	SLIDE = 0.42,
	CLOSE = 0.22,
	-- Every gesture of an open is over by now.
	SETTLED = 1.6,
})

Parts.RARITIES = Theme.RaritiesByNumber
Parts.MAX_RARITY = ERarities.Mythic

function Parts.Rarity(rarity: number)
	return Parts.RARITIES[rarity]
end

-- His locked cards' grey violet.
Parts.LOCKED = Color3.fromRGB(104, 84, 168)
-- The index's red: what is about to be dissolved.
Parts.DANGER = Color3.fromRGB(230, 60, 72)
-- His thin rules.
Parts.RULE = Color3.fromRGB(72, 56, 112)

-- An energy kind's enemy and its energy, by the enemy's data Id.
function Parts.Energy(enemyId: number): (TData.TEnemy, TData.TEnemyEnergy)
	local enemy = DataCore.Enemies.ById[enemyId]
	return enemy, enemy.Energy :: TData.TEnemyEnergy
end

-- A kind of souls' word on its card: the enemy's name without "Zombie", BOSS for a boss.
function Parts.EnergyWord(enemy: TData.TEnemy): string
	if enemy.IsBoss then return "BOSS" end
	local word = string.gsub(enemy.Name, "%s*Zombie%s*", "")
	return string.upper(if word == "" then enemy.Name else word)
end

-- A kind of souls named in full: BASIC SOULS.
function Parts.SoulsWord(enemy: TData.TEnemy): string
	return `{Parts.EnergyWord(enemy)} SOULS`
end

-- A potion's effect lines at `rarity`.
function Parts.EffectLines(recipe: TData.TPotion, rarity: number): { string }
	local lines = {}
	for index, effect in PotionsCore.Effects(recipe, rarity) do
		lines[index] = PotionsCore.Describe(effect)
	end
	return lines
end

function Parts.MatchesWord(matches: number): string
	return if matches == 1 then "LASTS 1 MATCH" else `LASTS {matches} MATCHES`
end

function Parts.Label(props: { [any]: any }): TextLabel
	return create("TextLabel")({
		BackgroundTransparency = 1,
		FontFace = Font.Display,
		TextColor3 = Palette.White,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 4,
		props,
	})
end

-- Seconds since the screen opened or shut, held once every gesture is over.
function Parts.Elapsed(state: Types.TLabState): () -> number
	return derive(function(): number
		return math.min(state.Now() - state.ToggledAt(), Parts.Timing.SETTLED)
	end)
end

-- How far from its place a piece is, as a share of its travel: decelerating in after `delay`, accelerating out.
function Parts.Away(state: Types.TLabState, elapsed: () -> number, delay: number): () -> number
	return derive(function(): number
		if state.IsOpen() then return 1 - Motion.Decelerate(Progress(elapsed(), delay, Parts.Timing.SLIDE)) end
		return Motion.Accelerate(Progress(elapsed(), 0, Parts.Timing.CLOSE))
	end)
end

-- How transparent a piece is: its fade in after `delay`, an even fade out.
function Parts.Faded(state: Types.TLabState, elapsed: () -> number, delay: number): () -> number
	return derive(function(): number
		if state.IsOpen() then return 1 - Motion.Out(Progress(elapsed(), delay, Parts.Timing.FADE)) end
		return Progress(elapsed(), 0, Parts.Timing.CLOSE)
	end)
end

-- 0 to 1 over a page's way in after it is picked (or the screen opens on it) and `delay`; 1 while it is on show, and
-- while the screen shuts: the panel takes its pieces out with it, where dealing them back would drop them all at once.
function Parts.Dealt(state: Types.TLabState, tab: number, delay: number): () -> number
	return derive(function(): number
		if not state.IsOpen() then return 1 end
		if state.Tab() ~= tab then return 0 end
		local at = math.max(state.TabAt(), state.ToggledAt())
		return Motion.Decelerate(Progress(state.Now(), at, Parts.Timing.SLIDE, delay))
	end)
end

-- A button's Interactable: off while the count menu is open, when its catcher has every press and nothing else in the
-- lab may light up. The lobby is a SurfaceGui, where a covered button still gets MouseEnter.
function Parts.Uncovered(state: Types.TLabState): () -> boolean
	return function(): boolean
		return not state.IsMenuOpen()
	end
end

-- His section header (SELECT ENERGY ... PICK 2): a pink mark, the title, the gold words at the right, and the rule
-- under it. `title`, `glyph` and `info` may be sources; `tint` is the mark's colour (a white-plastic mark), nil for its own. Laid at `top`
-- across the panel's column.
function Parts.Header(title: any, info: any, top: number, glyph: any, tint: Color3?, props: { [any]: any }): Frame
	return create("Frame")({
		Name = "Header",
		Position = UDim2.fromOffset(Parts.LEFT, top),
		Size = UDim2.fromOffset(Parts.RIGHT - Parts.LEFT, 40),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Components.Picture(glyph, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(9.5, 14.5),
			Size = Components.PictureBox(22),
			ImageColor3 = tint or Palette.White,
			ZIndex = 4,
		}),
		Parts.Label({
			Position = UDim2.fromOffset(32, 0),
			Size = UDim2.fromOffset(600, 28),
			TextSize = 28,
			Text = title,
		}),
		Parts.Label({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -4, 0, 6),
			Size = UDim2.fromOffset(600, 17),
			FontFace = Font.DisplayBold,
			TextSize = 17,
			TextColor3 = Palette.Gold,
			TextXAlignment = Enum.TextXAlignment.Right,
			Text = info,
		}),
		create("Frame")({
			Name = "Rule",
			Position = UDim2.fromOffset(0, 39),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = Parts.RULE,
			BorderSizePixel = 0,
		}),
		props,
	})
end

-- His flat tag (x10, NEW POTION, EPIC): a block of `accent` with a dark lip, its word in ink or white. `text` and
-- `accent` may be sources. Its frame is sized by the caller (`props.Size`), or, given `padX`, it is that many px
-- wider than its word on each side and only its height is the caller's: the word sizes the frame, never a scaled
-- child, which AutomaticSize cannot measure.
function Parts.Tag(text: any, accent: any, isInk: any, textSize: number, props: { [any]: any }, padX: number?): Frame
	return create("Frame")({
		Name = "Tag",
		AutomaticSize = if padX then Enum.AutomaticSize.X else nil,
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		ZIndex = 5,
		create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
		create("Frame")({
			Name = "Lip",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 2),
			BackgroundColor3 = Color3.new(),
			BackgroundTransparency = 0.7,
			BorderSizePixel = 0,
		}),
		create("TextLabel")({
			AnchorPoint = if padX then Vector2.new(0, 0.5) else Vector2.new(0.5, 0.5),
			Position = if padX then UDim2.fromScale(0, 0.5) else UDim2.fromScale(0.5, 0.5),
			Size = if padX then UDim2.fromOffset(0, textSize) else UDim2.new(1, 0, 0, textSize),
			AutomaticSize = if padX then Enum.AutomaticSize.X else nil,
			BackgroundTransparency = 1,
			FontFace = Font.Display,
			TextSize = textSize,
			TextColor3 = function()
				local ink = if type(isInk) == "function" then isInk() else isInk
				return if ink then Palette.Ink else Palette.White
			end,
			Text = text,
			ZIndex = 2,
			if padX
				then create("UIPadding")({ PaddingLeft = UDim.new(0, padX), PaddingRight = UDim.new(0, padX) })
				else nil,
		}),
		props,
	})
end

-- One ring thrown out of a piece: its own outline grown `reach` px off it and fading as `t` runs 0 to 1. Out of the
-- renderer at rest.
function Parts.Burst(t: () -> number, reach: number, color: any, props: { [any]: any }): Frame
	return create("Frame")({
		Name = "Burst",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = function()
			local grow = math.round(reach * Motion.Out(t()))
			return UDim2.new(1, 2 * grow, 1, 2 * grow)
		end,
		BackgroundTransparency = 1,
		Visible = function()
			local at = t()
			return at > 0 and at < 1
		end,
		create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
		create("UIStroke")({ Color = color, Thickness = 3, Transparency = t }),
		props,
	})
end

return Parts
