--!nonstrict
-- What the index screen's pieces share: its three pages and their enemies or recipes, each enemy's accent, threat and
-- tags, a discovery's reveal, and the clock every piece's entrance reads.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local MapsCore = require(ReplicatedStorage.GlobalShared.Core.MapsCore)
local TData = require(ReplicatedStorage.Types.TData)
local padlock = require(script.Parent.Parent.Parent.Utils.padlock)
local Types = require(script.Parent.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress

local Parts = {}

-- A screen's open and shut (UI.md 5o): pieces decelerate in, staged by what the screen is for, and accelerate out
-- faster; every fade runs on its own clock.
Parts.Timing = table.freeze({
	FADE = 0.3,
	SLIDE = 0.42,
	CLOSE = 0.22,
	-- Every gesture of an open is over by now; past it the clock's ticks redraw none of them.
	SETTLED = 1.6,
	-- A count going up is punched: its spring.
	COUNT_PERIOD = 0.3,
	COUNT_DAMPING = 0.5,
	-- A discovery's reveal: its card's padlock springs open over UNLOCK seconds, then the silhouette burns white for
	-- WHITE seconds, then the enemy comes through it over CROSS.
	REVEAL_UNLOCK = padlock.OPEN_SECONDS,
	-- When in it the shackle clicks up out of its sockets, and the unlock sound plays.
	REVEAL_CLICK = padlock.CLICK_SECONDS,
	REVEAL_WHITE = 0.22,
	REVEAL_CROSS = 0.38,
})
Parts.REVEAL_SECONDS = Parts.Timing.REVEAL_UNLOCK + Parts.Timing.REVEAL_WHITE + Parts.Timing.REVEAL_CROSS
-- How far into a reveal the enemy starts coming through: what it throws off (a flash, a ring, its sound) goes then.
Parts.REVEAL_LIT = Parts.Timing.REVEAL_UNLOCK + Parts.Timing.REVEAL_WHITE

Parts.EDGE_SHARE = 0.85
-- An unknown enemy's card and silhouette: his locked cards' grey violet, and the dark the silhouette is filled with.
Parts.LOCKED = Color3.fromRGB(104, 84, 168)
Parts.SILHOUETTE = Color3.fromRGB(44, 34, 78)
-- His thin rules, and the stat boxes' edge and face.
Parts.RULE = Color3.fromRGB(72, 56, 112)
Parts.STAT_EDGE = Color3.fromRGB(54, 47, 73)
Parts.STAT_FACE = Color3.fromRGB(29, 25, 47)
-- What a page with nothing found yet is drawn as on its card.
Parts.UNKNOWN = "???"

-- How dangerous a type reads, by the first wave it comes in (a boss is always the top): its word and its accent, the
-- colour of its card, its stage and its THREAT.
local THREATS = table.freeze({
	table.freeze({ UpTo = 2, Word = "LOW", Accent = Palette.Steel }),
	table.freeze({ UpTo = 4, Word = "MEDIUM", Accent = Palette.Green }),
	table.freeze({ UpTo = math.huge, Word = "HIGH", Accent = Palette.Gold }),
})
local BOSS_THREAT = table.freeze({ Word = "EXTREME", Accent = Palette.Pink })
-- Each attack's word on the info panel's tags.
local ATTACK_WORDS = table.freeze({
	Melee = "MELEE",
	Explode = "EXPLODES",
	Slam = "SLAM",
	Shockwave = "SHOCKWAVE",
})

local function byArrival(a: TData.TEnemy, b: TData.TEnemy): boolean
	if a.IntroRound ~= b.IntroRound then return a.IntroRound < b.IntroRound end
	return a.Id < b.Id
end

-- The pages: MONSTERS (everything a wave is drawn from) and BOSSES, each in the order its enemies first come, then
-- POTIONS, the Mutation Lab's recipes in data Id order.
local function categories(): { Types.TCategory }
	local monsters, bosses = {}, {}
	for _, enemy in DataCore.Enemies.All do
		table.insert(if enemy.IsBoss then bosses else monsters, enemy)
	end
	table.sort(monsters, byArrival)
	table.sort(bosses, byArrival)

	return table.freeze({
		table.freeze({
			Key = 1,
			Word = "MONSTERS",
			Picture = EIcons.Zombie,
			Accent = Palette.Green,
			Enemies = table.freeze(monsters),
		}),
		table.freeze({
			Key = 2,
			Word = "BOSSES",
			Picture = EIcons.ZombieKing,
			Accent = Palette.Pink,
			Enemies = table.freeze(bosses),
		}),
		table.freeze({
			Key = 3,
			Word = "POTIONS",
			Picture = EIcons.Flask,
			Accent = Palette.Violet,
			Enemies = table.freeze({}),
			Potions = DataCore.Potions.All,
		}),
	})
end

Parts.CATEGORIES = categories()
-- The POTIONS page's key: the stage, the info and the grid draw a recipe on it instead of an enemy.
Parts.POTIONS = 3
-- Everything the index can show found: every enemy and every recipe.
Parts.TOTAL = #DataCore.Enemies.All + #DataCore.Potions.All

-- How many things `category` holds.
function Parts.Size(category: Types.TCategory): number
	return if category.Potions then #category.Potions else #category.Enemies
end

-- A recipe's colour: its first energy's, as a recipe has no rarity of its own.
function Parts.PotionColor(recipe: TData.TPotion): Color3
	local enemy = DataCore.Enemies.ById[recipe.Energies[1]]
	local energy = if enemy then enemy.Energy else nil
	return if energy then energy.Color else Palette.Violet
end

-- Whether `recipeId` wears NEW: found and not shown yet, or shown this session and not picked since.
function Parts.IsPotionNew(state: Types.TIndexState, recipeId: number): boolean
	if state.PotionsUnread()[recipeId] then return true end
	local found = state.Potions()[recipeId]
	return found ~= nil and found.IsNew
end

-- The page `enemy` is on.
function Parts.CategoryOf(enemy: TData.TEnemy): number
	return if enemy.IsBoss then 2 else 1
end

-- How dangerous `enemy` reads: { Word, Accent }.
function Parts.Threat(enemy: TData.TEnemy)
	if enemy.IsBoss then return BOSS_THREAT end
	for _, threat in THREATS do
		if enemy.IntroRound <= threat.UpTo then return threat end
	end

	return THREATS[#THREATS]
end

-- Where it comes, for FOUND IN: its maps' names, or ALL MAPS for one that comes on every map.
function Parts.MapsText(enemy: TData.TEnemy): string
	local maps = enemy.Maps
	if not maps then return "ALL MAPS" end
	local names = table.create(#maps)
	for index, name in maps do
		local map = MapsCore.MAPS[name]
		names[index] = string.upper(if map then map.DisplayName else name)
	end

	return table.concat(names, ", ")
end

-- Its attacks' words, each once, in its pattern's order.
function Parts.AttackWords(enemy: TData.TEnemy): { string }
	if enemy.IndexTags then return enemy.IndexTags end
	local words, seen = {}, {}
	for _, attack in enemy.Attacks do
		local word = ATTACK_WORDS[attack.Kind]
		if not word or seen[word] then continue end
		seen[word] = true
		table.insert(words, word)
	end

	return words
end

function Parts.EdgeOf(accent: Color3): Color3
	local share = Parts.EDGE_SHARE
	return Color3.new(accent.R * share, accent.G * share, accent.B * share)
end

function Parts.Label(props: { [any]: any }): TextLabel
	return create("TextLabel")({
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		FontFace = Font.Display,
		TextColor3 = Palette.White,
		ZIndex = 4,
		props,
	})
end

-- Seconds since the screen opened or shut, held once every gesture is over, so the clock ticking for a later
-- gesture works none of the open out again.
function Parts.Elapsed(state: Types.TIndexState): () -> number
	return derive(function(): number
		return math.min(state.Now() - state.ToggledAt(), Parts.Timing.SETTLED)
	end)
end

-- How far from its place a piece is, as a share of its travel: decelerating in after `delay`, accelerating out.
function Parts.Away(state: Types.TIndexState, elapsed: () -> number, delay: number): () -> number
	return derive(function(): number
		if state.IsOpen() then return 1 - Motion.Decelerate(Progress(elapsed(), delay, Parts.Timing.SLIDE)) end
		return Motion.Accelerate(Progress(elapsed(), 0, Parts.Timing.CLOSE))
	end)
end

-- How transparent a piece is: its fade in after `delay` (away at once, gentle onto the mark), an even fade out.
function Parts.Faded(state: Types.TIndexState, elapsed: () -> number, delay: number): () -> number
	return derive(function(): number
		if state.IsOpen() then return 1 - Motion.Out(Progress(elapsed(), delay, Parts.Timing.FADE)) end
		return Progress(elapsed(), 0, Parts.Timing.CLOSE)
	end)
end

-- Whether `recipeId` shows as found (its reveal may still be running): brewed, and not held unknown for a reveal the
-- lab's NEW calls for.
function Parts.IsPotionShown(state: Types.TIndexState, recipeId: number): boolean
	local found = state.Potions()[recipeId]
	return found ~= nil and (not found.IsNew or state.PotionsRevealAt()[recipeId] ~= nil)
end

-- How far into its reveal a thing shown found is, `at` its reveal's moment (nil: none, so known). Reads the clock only
-- while the reveal is due or running: one over is told by os.clock, so a card revealed long ago is not worked out
-- again on every tick of the screen's clock.
local function revealed(state: Types.TIndexState, at: number?): number
	if not at or os.clock() >= at + Parts.REVEAL_SECONDS then return 1 end
	return Progress(state.Now(), at, Parts.REVEAL_SECONDS)
end

-- How far into being known `enemyId` is: 0 unknown (never killed, or found but its reveal not played yet), 1 known,
-- and between them the reveal running.
function Parts.Known(state: Types.TIndexState, enemyId: () -> number): () -> number
	return derive(function(): number
		local id = enemyId()
		if state.Kills()[id] == nil or state.Hidden()[id] then return 0 end
		return revealed(state, state.RevealAt()[id])
	end)
end

-- The same for `recipeId`: 0 until it shows as found (IsPotionShown).
function Parts.PotionKnown(state: Types.TIndexState, recipeId: () -> number): () -> number
	return derive(function(): number
		local id = recipeId()
		if not Parts.IsPotionShown(state, id) then return 0 end
		return revealed(state, state.PotionsRevealAt()[id])
	end)
end

-- Whether a thing shown found counts yet, `at` as in revealed: once it starts coming through. A reveal over is told
-- by os.clock, as there.
local function isCounted(state: Types.TIndexState, at: number?): boolean
	return not at or os.clock() >= at + Parts.REVEAL_LIT or state.Now() >= at + Parts.REVEAL_LIT
end

-- How many of `enemies` show as found now: a reveal counts once its enemy starts coming through.
function Parts.ShownCount(state: Types.TIndexState, enemies: { TData.TEnemy }): number
	local kills, hidden, revealAt = state.Kills(), state.Hidden(), state.RevealAt()
	local count = 0
	for _, enemy in enemies do
		local id = enemy.Id
		if kills[id] == nil or hidden[id] or not isCounted(state, revealAt[id]) then continue end
		count += 1
	end

	return count
end

-- How many of `category`'s things show as found now: its enemies as ShownCount counts them, or its recipes the same
-- way.
function Parts.FoundCount(state: Types.TIndexState, category: Types.TCategory): number
	local potions = category.Potions
	if not potions then return Parts.ShownCount(state, category.Enemies) end
	local revealAt = state.PotionsRevealAt()
	local count = 0
	for _, recipe in potions do
		local id = recipe.Id
		if not Parts.IsPotionShown(state, id) or not isCounted(state, revealAt[id]) then continue end
		count += 1
	end

	return count
end

local function sinceLit(state: Types.TIndexState, revealAt: () -> { [number]: number }, id: () -> number)
	return derive(function(): number?
		local at = revealAt()[id()]
		-- A reveal over is told by os.clock, as in Known.
		if not at or os.clock() >= at + Parts.REVEAL_LIT + 1 then return nil end
		local since = state.Now() - at - Parts.REVEAL_LIT
		return if since >= 0 and since < 1 then since else nil
	end)
end

-- Seconds since `enemyId` started coming through its silhouette, for what its reveal throws off (a flash, a ring);
-- nil before that and once it is a second old.
function Parts.SinceLit(state: Types.TIndexState, enemyId: () -> number): () -> number?
	return sinceLit(state, state.RevealAt, enemyId)
end

-- The same for `recipeId`'s bottle.
function Parts.PotionSinceLit(state: Types.TIndexState, recipeId: () -> number): () -> number?
	return sinceLit(state, state.PotionsRevealAt, recipeId)
end

-- 0 to 1 over `seconds` of `since` (SinceLit), and `rest` while there is none.
function Parts.Over(since: () -> number?, seconds: number, rest: number): () -> number
	return derive(function(): number
		local at = since()
		return if at then math.clamp(at / seconds, 0, 1) else rest
	end)
end

-- 1 falling to 0 over `seconds` of `since` (SinceLit), and 0 while there is none: a flash.
function Parts.Fading(since: () -> number?, seconds: number): () -> number
	return derive(function(): number
		local at = since()
		return if at then 1 - math.clamp(at / seconds, 0, 1) else 0
	end)
end

-- A number's punch (for a UIScale), struck by `size` each time `count` goes up. `key`, when given, is what the number
-- counts (a page): a change of it is a new number, not a rise.
function Parts.Punched(count: () -> number, size: number, key: (() -> any)?): () -> number
	local punch, strike = Hand.Kick(Parts.Timing.COUNT_PERIOD, Parts.Timing.COUNT_DAMPING)
	local last, lastKey = nil, nil
	vide.effect(function()
		local current = count()
		local currentKey = if key then key() else nil
		vide.untrack(function()
			if last and currentKey == lastKey and current > last then strike(size) end
			last, lastKey = current, currentKey
		end)
	end)

	return punch
end

-- A reveal's halves out of Known: how white the silhouette has burned, and how far the enemy has come through. The
-- padlock opening before them is the card's own (Grid).
function Parts.Burned(known: () -> number): () -> number
	return function(): number
		local seconds = known() * Parts.REVEAL_SECONDS - Parts.Timing.REVEAL_UNLOCK
		return math.clamp(seconds / Parts.Timing.REVEAL_WHITE, 0, 1)
	end
end

function Parts.Lit(known: () -> number): () -> number
	return function(): number
		local seconds = known() * Parts.REVEAL_SECONDS - Parts.REVEAL_LIT
		return math.clamp(seconds / Parts.Timing.REVEAL_CROSS, 0, 1)
	end
end

-- One ring thrown out of a piece: its own outline grown `reach` px off it and fading as `t` runs 0 to 1. Out of the
-- renderer at rest. `props` are its own; size it to the piece.
function Parts.Burst(t: () -> number, reach: number, color: any, corner: UDim, props: { [any]: any }): Frame
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
		create("UICorner")({ CornerRadius = corner }),
		create("UIStroke")({ Color = color, Thickness = 3, Transparency = t }),
		props,
	})
end

return Parts
