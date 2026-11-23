--!nonstrict
-- The right of the results (UIMatt.md, Lobby Entering › Match Stats Container and Lobby Button), on his drawn rects at
-- 1080 with x from the screen's right edge: MATCH STATS over four cards (the Gems earned, the squad's kills, the wave
-- reached, the time survived), and LOBBY under them.
--
-- The cards slide in from the right one after another, each number counting up and landing with a swell as a light
-- crosses its card; a new best is stamped on after its number lands. LOBBY rises last and catches the light now and
-- then until it is pressed.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local Scrim = require(script.Parent.Scrim)
local Types = require(script.Parent.Types)

local create = vide.create
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress
local Lerp = Motion.Lerp

local Layout = table.freeze({
	-- The column's left, from the screen's right edge, and its width.
	LEFT = 439,
	WIDTH = 399,
	HEADER_Y = 216,
	BARS = Vector2.new(1, 9),
	TITLE = Vector2.new(32, 3),
	TITLE_TEXT = 29,
	RULE_Y = 38,
	CARD_TOPS = { 278, 428, 578, 728 },
	CARD_HEIGHT = 132,
	LABEL = Vector2.new(21, 22),
	LABEL_TEXT = 18,
	VALUE = Vector2.new(21, 44),
	VALUE_TEXT = 46,
	SUB = Vector2.new(21, 100),
	SUB_TEXT = 14,
	GLYPH = Vector2.new(345, 66),
	GLYPH_SIZE = 62,
	BEST = Vector2.new(279, -12),
	BEST_SIZE = Vector2.new(102, 24),
	BEST_TEXT = 13,
	LOBBY_Y = 905,
	LOBBY_HEIGHT = 113,
	LOBBY_TEXT = 62,
	ARROW = 46,
	MARGIN = 40,
	-- The soft shadow under the whole column, the stage showing through it: how far past the column it reaches on
	-- each side, its fade and how dark its middle is.
	SCRIM_REACH = Vector2.new(70, 60),
	SCRIM_FEATHER = 80,
	SCRIM_STRENGTH = 0.5,
})

local Timing = table.freeze({
	HEADER_DELAY = 0.36,
	CARDS_DELAY = 0.46,
	CARD_STAGGER = 0.1,
	DEAL = 0.42,
	DEAL_SLIDE = 70,
	GLYPH_DELAY = 0.12,
	GLYPH = 0.4,
	COUNT_DELAY = 0.18,
	COUNT = 0.9,
	PUNCH = 0.32,
	PUNCH_SCALE = 0.14,
	SHEEN = 0.7,
	BEST_DELAY = 0.1,
	BEST = 0.26,
	BEST_SCALE = 0.6,
	BEST_FLASH = 0.45,
	LOBBY_DELAY = 1.05,
	LOBBY = 0.45,
	LOBBY_RISE = 30,
	ASK_EVERY = 3.4,
	ASK_SHEEN = 0.8,
})

-- His cards' accents (the orange is his "SQUAD KILLS"), and how faint the big glyph is.
local Colors = table.freeze({
	KILLS = Color3.fromRGB(255, 128, 38),
	WAVE = Color3.fromRGB(89, 191, 255),
	RULE = Color3.fromRGB(140, 111, 211),
	GLYPH_TRANSPARENCY = 0.45,
})

-- One card: its accent, word, glyph, the number it counts to and how that is written, its line under it, and
-- whether a new best is stamped on.
type TCard = {
	Name: string,
	Accent: Color3,
	Word: string,
	Glyph: string,
	Value: (state: Types.TState) -> number,
	Format: (value: number) -> string,
	Sub: (state: Types.TState) -> string,
	IsNewBest: (state: Types.TState) -> boolean,
}

local function clockText(seconds: number): string
	local whole = math.max(math.floor(seconds), 0)
	return `{whole // 60}:{string.format("%02d", whole % 60)}`
end

local function never(): boolean
	return false
end

local CARDS: { TCard } = {
	{
		Name = "Gems",
		Accent = Palette.Pink,
		Word = "GEMS EARNED",
		Glyph = "Gem",
		Value = function(state)
			local record = state.Record()
			return if record then record.Gems else 0
		end,
		Format = function(value)
			return `+{Components.Commas(value)}`
		end,
		Sub = function(state)
			return `TOTAL: {Components.Commas(state.TotalGems())}`
		end,
		IsNewBest = never,
	},
	{
		Name = "Kills",
		Accent = Colors.KILLS,
		Word = "SQUAD KILLS",
		Glyph = "Skull",
		Value = function(state)
			local record = state.Record()
			return if record then record.SquadKills else 0
		end,
		Format = Components.Commas,
		Sub = function(state)
			local record = state.Record()
			return `YOU: {Components.Commas(if record then record.Kills else 0)}`
		end,
		IsNewBest = never,
	},
	{
		Name = "Wave",
		Accent = Colors.WAVE,
		Word = "WAVE REACHED",
		Glyph = "Boss",
		Value = function(state)
			local record = state.Record()
			return if record then record.Wave else 0
		end,
		Format = tostring,
		Sub = function(state)
			local record = state.Record()
			return `BEST: {if record then math.max(record.Wave, record.BestWaveBefore) else 0}`
		end,
		IsNewBest = function(state)
			local record = state.Record()
			return record ~= nil and record.Wave > record.BestWaveBefore
		end,
	},
	{
		Name = "Time",
		Accent = Palette.Gold,
		Word = "TIME SURVIVED",
		Glyph = "Stopwatch",
		Value = function(state)
			local record = state.Record()
			return if record then record.Seconds else 0
		end,
		Format = clockText,
		Sub = function(state)
			local record = state.Record()
			return `BEST: {clockText(if record then math.max(record.Seconds, record.BestSecondsBefore) else 0)}`
		end,
		IsNewBest = function(state)
			local record = state.Record()
			return record ~= nil and record.Seconds > record.BestSecondsBefore
		end,
	},
}

local Stats = {}

local function label(props: { [any]: any }): TextLabel
	return create("TextLabel")({
		BackgroundTransparency = 1,
		FontFace = Font.Display,
		TextColor3 = Palette.White,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
		props,
	})
end

-- A piece of the column at `y`, `height` tall: it slides in from the right and fades in from `delay`.
local function dealt(
	state: Types.TState,
	clock: Types.TClock,
	name: string,
	y: number,
	height: number,
	delay: number,
	child: Instance
): CanvasGroup
	local margin = Layout.MARGIN
	return create("CanvasGroup")({
		Name = name,
		Position = function()
			local slide = Timing.DEAL_SLIDE * (1 - Motion.Decelerate(clock.Since(delay, Timing.DEAL)))
			return UDim2.new(1, -Layout.LEFT - margin + math.round(slide), 0, y - margin)
		end,
		Size = UDim2.fromOffset(Layout.WIDTH + 2 * margin, height + 2 * margin),
		BackgroundTransparency = 1,
		GroupTransparency = function()
			if not state.IsOpen() then return 1 - clock.Shown() end
			return 1 - Motion.Out(clock.Since(delay, Timing.DEAL * 0.7))
		end,
		create("Frame")({
			Name = "Holder",
			Position = UDim2.fromOffset(margin, margin),
			Size = UDim2.fromOffset(Layout.WIDTH, height),
			BackgroundTransparency = 1,
			child,
		}),
	})
end

local function header(): Frame
	local bars = {}
	for index, height in { 9, 15, 12 } do
		bars[index] = create("Frame")({
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromOffset((index - 1) * 7, 18),
			Size = UDim2.fromOffset(4, height),
			BackgroundColor3 = Palette.Pink,
			BorderSizePixel = 0,
		})
	end

	return create("Frame")({
		Name = "Header",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		create("Frame")({
			Name = "Bars",
			Position = UDim2.fromOffset(Layout.BARS.X, Layout.BARS.Y),
			Size = UDim2.fromOffset(18, 18),
			BackgroundTransparency = 1,
			bars,
		}),
		label({
			Position = UDim2.fromOffset(Layout.TITLE.X, Layout.TITLE.Y),
			Size = UDim2.fromOffset(300, Layout.TITLE_TEXT),
			TextSize = Layout.TITLE_TEXT,
			Text = "MATCH STATS",
		}),
		create("Frame")({
			Name = "Rule",
			Position = UDim2.fromOffset(0, Layout.RULE_Y),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = Colors.RULE,
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
		}),
	})
end

-- NEW BEST in the card's accent on its top edge, stamped on once its number has landed.
local function newBest(state: Types.TState, clock: Types.TClock, accent: Color3, at: number): Frame
	local stamped = function(): number
		return Motion.Decelerate(clock.Since(at, Timing.BEST))
	end
	local flash = function(): number
		if not state.IsOpen() then return 0 end
		local left = 1 - Progress(clock.Elapsed(), at + Timing.BEST * 0.5, Timing.BEST_FLASH)
		return left * left
	end

	return create("Frame")({
		Name = "NewBest",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(Layout.BEST.X + Layout.BEST_SIZE.X / 2, Layout.BEST.Y + Layout.BEST_SIZE.Y / 2),
		Size = UDim2.fromOffset(Layout.BEST_SIZE.X, Layout.BEST_SIZE.Y),
		BorderSizePixel = 0,
		ZIndex = 6,
		BackgroundColor3 = function()
			return accent:Lerp(Palette.White, flash())
		end,
		BackgroundTransparency = function()
			return 1 - Motion.Out(clock.Since(at, Timing.BEST * 0.6))
		end,
		create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
		create("UIScale")({
			Scale = function()
				return 1 + Timing.BEST_SCALE * (1 - stamped())
			end,
		}),
		label({
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextSize = Layout.BEST_TEXT,
			TextColor3 = Palette.Ink,
			TextTransparency = function()
				return 1 - Motion.Out(clock.Since(at, Timing.BEST * 0.6))
			end,
			Text = "NEW BEST",
		}),
	})
end

local function card(state: Types.TState, clock: Types.TClock, spec: TCard, delay: number): Frame
	local countAt = delay + Timing.COUNT_DELAY
	local landsAt = countAt + Timing.COUNT
	local counted = function(): number
		return Motion.Out(clock.Since(countAt, Timing.COUNT))
	end
	-- 1 as the number lands, falling to 0.
	local punch = function(): number
		if not state.IsOpen() then return 0 end
		local since = clock.Elapsed() - landsAt
		if since < 0 then return 0 end
		return math.clamp(1 - since / Timing.PUNCH, 0, 1)
	end

	return Components.Card({
		Accent = spec.Accent,
		Tint = 0.5,
		Edge = 2,
		Marks = true,
		Brackets = 5,
		GlowTransparency = function()
			local lit = punch()
			return Lerp(0.7, 0.35, lit * lit)
		end,
	}, {
		Name = spec.Name,
		Size = UDim2.fromScale(1, 1),
		label({
			Position = UDim2.fromOffset(Layout.LABEL.X, Layout.LABEL.Y),
			Size = UDim2.fromOffset(300, Layout.LABEL_TEXT),
			TextSize = Layout.LABEL_TEXT,
			TextColor3 = spec.Accent,
			Text = spec.Word,
		}),
		label({
			Name = "Value",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(Layout.VALUE.X, Layout.VALUE.Y + Layout.VALUE_TEXT / 2),
			Size = UDim2.fromOffset(300, Layout.VALUE_TEXT),
			TextSize = Layout.VALUE_TEXT,
			Text = function()
				return spec.Format(math.round(spec.Value(state) * counted()))
			end,
			create("UIScale")({
				Scale = function()
					local swell = punch()
					return 1 + Timing.PUNCH_SCALE * swell * swell
				end,
			}),
		}),
		label({
			Position = UDim2.fromOffset(Layout.SUB.X, Layout.SUB.Y),
			Size = UDim2.fromOffset(300, Layout.SUB_TEXT),
			FontFace = Font.DisplayBold,
			TextSize = Layout.SUB_TEXT,
			TextColor3 = Palette.Lavender,
			Text = function()
				return spec.Sub(state)
			end,
		}),
		Components.Icon(spec.Glyph, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(Layout.GLYPH.X, Layout.GLYPH.Y),
			Size = Components.GlyphBox(Layout.GLYPH_SIZE),
			ImageColor3 = spec.Accent,
			ImageTransparency = Colors.GLYPH_TRANSPARENCY,
			ZIndex = 3,
			create("UIScale")({
				Scale = function()
					return 0.5 + 0.5 * Motion.OutBack(clock.Since(delay + Timing.GLYPH_DELAY, Timing.GLYPH))
				end,
			}),
		}),
		create("Frame")({
			Name = "SheenWindow",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = 5,
			Components.Sheen(function()
				return clock.Since(landsAt, Timing.SHEEN)
			end, 5),
		}),
		vide.show(function()
			return spec.IsNewBest(state)
		end, function()
			return newBest(state, clock, spec.Accent, landsAt + Timing.BEST_DELAY)
		end),
	})
end

-- LOBBY: his big green slab with its arrow. It catches the light every ASK_EVERY once it is up.
local function lobbyButton(state: Types.TState, clock: Types.TClock, actions: Types.TActions): TextButton
	local isLive = function(): boolean
		return state.IsOpen()
	end
	local hand = Hand.React("Operate", isLive)
	local landsAt = Timing.LOBBY_DELAY + Timing.LOBBY

	return Components.Button({
		Name = "Lobby",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Active = isLive,
		Activated = function()
			if not isLive() then return end
			hand.Commit()
			actions.Close()
		end,
		hand.Events,
		create("UIScale")({ Scale = hand.Scale }),
		Components.Slab({
			Kind = "Go",
			Marks = true,
			Brackets = function()
				return 5 + 3 * hand.Rise()
			end,
			GlowTransparency = function()
				return Lerp(0.5, 0.3, hand.Light())
			end,
		}, {
			Name = "Face",
			Size = UDim2.fromScale(1, 1),
			create("Frame")({
				Name = "Caption",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ZIndex = 4,
				create("UIListLayout")({
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 22),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
				label({
					LayoutOrder = 1,
					Size = UDim2.fromOffset(0, Layout.LOBBY_TEXT),
					AutomaticSize = Enum.AutomaticSize.X,
					TextSize = Layout.LOBBY_TEXT,
					Text = "LOBBY",
				}),
				Components.Icon("Arrow", {
					LayoutOrder = 2,
					Size = Components.GlyphBox(Layout.ARROW),
					ImageColor3 = Palette.White,
				}),
			}),
			Hand.WashLayer(hand, 3, 4),
			create("Frame")({
				Name = "SheenWindow",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ClipsDescendants = true,
				ZIndex = 5,
				Components.Sheen(
					Hand.Sheen(hand, function(): number
						if not state.IsOpen() then return 1 end
						local since = clock.Elapsed() - landsAt
						if since < 0 then return 1 end
						return math.clamp((since % Timing.ASK_EVERY) / Timing.ASK_SHEEN, 0, 1)
					end),
					5
				),
			}),
		}),
	}) :: TextButton
end

function Stats.Build(state: Types.TState, clock: Types.TClock, actions: Types.TActions): Frame
	local cards = table.create(#CARDS)
	for index, spec in CARDS do
		local delay = Timing.CARDS_DELAY + (index - 1) * Timing.CARD_STAGGER
		cards[index] = dealt(
			state,
			clock,
			`{spec.Name}Card`,
			Layout.CARD_TOPS[index],
			Layout.CARD_HEIGHT,
			delay,
			card(state, clock, spec, delay)
		)
	end

	return create("Frame")({
		Name = "Stats",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Scrim(
			Vector2.new(
				Layout.WIDTH + 2 * Layout.SCRIM_REACH.X,
				Layout.LOBBY_Y + Layout.LOBBY_HEIGHT - Layout.HEADER_Y + 2 * Layout.SCRIM_REACH.Y
			),
			Layout.SCRIM_FEATHER,
			Layout.SCRIM_STRENGTH,
			{
				Position = UDim2.new(1, -Layout.LEFT - Layout.SCRIM_REACH.X, 0, Layout.HEADER_Y - Layout.SCRIM_REACH.Y),
				ZIndex = 0,
				GroupTransparency = function()
					if not state.IsOpen() then return 1 - clock.Shown() end
					return 1 - Motion.Out(clock.Since(Timing.HEADER_DELAY, Timing.DEAL))
				end,
			}
		),
		dealt(state, clock, "Header", Layout.HEADER_Y, Layout.RULE_Y + 1, Timing.HEADER_DELAY, header()),
		cards,
		create("CanvasGroup")({
			Name = "LobbyGroup",
			Position = function()
				local rise = Timing.LOBBY_RISE * (1 - Motion.Decelerate(clock.Since(Timing.LOBBY_DELAY, Timing.LOBBY)))
				return UDim2.new(1, -Layout.LEFT - Layout.MARGIN, 0, Layout.LOBBY_Y - Layout.MARGIN + math.round(rise))
			end,
			Size = UDim2.fromOffset(Layout.WIDTH + 2 * Layout.MARGIN, Layout.LOBBY_HEIGHT + 2 * Layout.MARGIN),
			BackgroundTransparency = 1,
			GroupTransparency = function()
				if not state.IsOpen() then return 1 - clock.Shown() end
				return 1 - Motion.Out(clock.Since(Timing.LOBBY_DELAY, Timing.LOBBY * 0.7))
			end,
			create("Frame")({
				Name = "Holder",
				Position = UDim2.fromOffset(Layout.MARGIN, Layout.MARGIN),
				Size = UDim2.fromOffset(Layout.WIDTH, Layout.LOBBY_HEIGHT),
				BackgroundTransparency = 1,
				lobbyButton(state, clock, actions),
			}),
		}),
	})
end

return Stats
