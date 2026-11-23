--!nonstrict
-- What the index screen's pieces share: its two pages and their enemies, each enemy's accent, threat and tags, his
-- badges and selection ring, a discovery's reveal, and the clock every piece's entrance reads.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local MapsCore = require(ReplicatedStorage.GlobalShared.Core.MapsCore)
local TData = require(ReplicatedStorage.Types.TData)
local Types = require(script.Parent.Types)

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
	-- A discovery's reveal: the silhouette burns white for WHITE seconds, then the enemy comes through it over CROSS.
	REVEAL_WHITE = 0.22,
	REVEAL_CROSS = 0.38,
})
Parts.REVEAL_SECONDS = Parts.Timing.REVEAL_WHITE + Parts.Timing.REVEAL_CROSS

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

-- The pages: MONSTERS (everything a wave is drawn from) and BOSSES, each in the order its enemies first come.
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
			Glyph = "Zombie",
			Accent = Palette.Green,
			Enemies = table.freeze(monsters),
		}),
		table.freeze({
			Key = 2,
			Word = "BOSSES",
			Glyph = "Boss",
			Accent = Palette.Pink,
			Enemies = table.freeze(bosses),
		}),
	})
end

Parts.CATEGORIES = categories()
Parts.TOTAL = #DataCore.Enemies.All

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

-- How far into being known `enemyId` is: 0 unknown (never killed, or found but its reveal not played yet), 1 known,
-- and between them the reveal running. Reads the clock only while a reveal is due or running: a reveal over is told by
-- os.clock, so a card revealed long ago is not worked out again on every tick of the screen's clock.
function Parts.Known(state: Types.TIndexState, enemyId: () -> number): () -> number
	return derive(function(): number
		local id = enemyId()
		if state.Kills()[id] == nil or state.Hidden()[id] then return 0 end
		local at = state.RevealAt()[id]
		if not at or os.clock() >= at + Parts.REVEAL_SECONDS then return 1 end
		return Progress(state.Now(), at, Parts.REVEAL_SECONDS)
	end)
end

-- How many of `enemies` show as found now: a reveal counts once its enemy starts coming through.
function Parts.ShownCount(state: Types.TIndexState, enemies: { TData.TEnemy }): number
	local kills, hidden, revealAt = state.Kills(), state.Hidden(), state.RevealAt()
	local count = 0
	for _, enemy in enemies do
		local id = enemy.Id
		if kills[id] == nil or hidden[id] then continue end
		local at = revealAt[id]
		-- A reveal over is told by os.clock, as in Known.
		if at and os.clock() < at + Parts.Timing.REVEAL_WHITE and state.Now() < at + Parts.Timing.REVEAL_WHITE then
			continue
		end
		count += 1
	end

	return count
end

-- Seconds since `enemyId` started coming through its silhouette, for what its reveal throws off (a flash, a ring);
-- nil before that and once it is a second old.
function Parts.SinceLit(state: Types.TIndexState, enemyId: () -> number): () -> number?
	return derive(function(): number?
		local at = state.RevealAt()[enemyId()]
		-- A reveal over is told by os.clock, as in Known.
		if not at or os.clock() >= at + Parts.Timing.REVEAL_WHITE + 1 then return nil end
		local since = state.Now() - at - Parts.Timing.REVEAL_WHITE
		return if since >= 0 and since < 1 then since else nil
	end)
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

-- A reveal's two halves out of Known: how white the silhouette has burned, and how far the enemy has come through.
function Parts.Burned(known: () -> number): () -> number
	return function(): number
		return math.clamp(known() * Parts.REVEAL_SECONDS / Parts.Timing.REVEAL_WHITE, 0, 1)
	end
end

function Parts.Lit(known: () -> number): () -> number
	return function(): number
		local seconds = known() * Parts.REVEAL_SECONDS - Parts.Timing.REVEAL_WHITE
		return math.clamp(seconds / Parts.Timing.REVEAL_CROSS, 0, 1)
	end
end

-- His badges, `size` px square: Check (his green tick square), Lock (his grey-edged ink square with a white lock).
function Parts.Badge(kind: string, size: number, props: { [any]: any }): Frame
	if kind == "Lock" then
		return Components.Plaque({
			Size = UDim2.fromOffset(size, size),
			Components.Icon("Lock", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = Components.GlyphBox(math.round(size * 0.56)),
				ImageColor3 = Palette.White,
				ZIndex = 2,
			}),
			props,
		})
	end

	return create("Frame")({
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Palette.Green,
		BorderSizePixel = 0,
		create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
		Components.Icon("Check", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = Components.GlyphBox(math.round(size * 0.62)),
			ImageColor3 = Palette.Ink,
			ZIndex = 2,
		}),
		props,
	})
end

-- His selection ring: a thin white rounded outline standing `outset` px off what it frames. `props` are its own
-- (size it to the framed piece; the outset is added).
function Parts.Ring(outset: number, props: { [any]: any }): Frame
	return create("Frame")({
		Name = "Ring",
		BackgroundTransparency = 1,
		create("Frame")({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, 2 * outset, 1, 2 * outset),
			BackgroundTransparency = 1,
			create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
			create("UIStroke")({
				Color = Palette.White,
				Thickness = 1.5,
				Transparency = 0.05,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
		}),
		props,
	})
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
