--!nonstrict
-- The categories (his left panel): a card for each page with his glyph for it, its name and how many of it are
-- found, the white ring gliding to the page on show, and COMPLETION with its bar under them. His reward card is left
-- out: discovering everything earns nothing yet. A count goes up as each reveal lands, punched, and the bar slides on.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local Parts = require(script.Parent.Parts)
local Types = require(script.Parent.Types)

local create = vide.create
local derive = vide.derive
local spring = vide.spring
local Palette = Theme.Palette
local Font = Theme.Font
local Label = Parts.Label

-- His drawn rects in px at 1080, from the panel's top left.
local Layout = table.freeze({
	PANEL = Vector2.new(40, 190),
	SIZE = Vector2.new(440, 850),
	MARGIN = 48,
	BRACKETS = 5,
	-- The two headers: the glyph's middle and longer side, the word, the right-hand count, the rule; COMPLETION's
	-- sits COMPLETION_Y lower.
	GLYPH = Vector2.new(35, 39),
	GLYPH_SIZE = 19,
	QUESTION = Vector2.new(35, 38),
	QUESTION_TEXT = 26,
	TITLE = Vector2.new(56, 24),
	TITLE_TEXT = 29,
	COUNT_RIGHT = 416,
	COUNT_Y = 30,
	COUNT_TEXT = 18,
	RULE = Vector2.new(24, 64),
	RULE_WIDTH = 392,
	COMPLETION_Y = 336,
	BAR = Vector2.new(24, 422),
	BAR_SIZE = Vector2.new(392, 14),
	-- The page cards: the first one's top left, the step down, their size; inside one the glyph's tile, the name, the
	-- count and NEW.
	CARD = Vector2.new(24, 91),
	CARD_STEP = 124,
	CARD_SIZE = Vector2.new(392, 104),
	CARD_BRACKETS = 6,
	TILE = Vector2.new(16, 16),
	TILE_SIZE = 72,
	-- His glyphs' longer side, and each one's middle off the tile's, in whole px (an offset is an integer).
	TILE_GLYPH = 53,
	TILE_GLYPH_OFFSETS = table.freeze({
		Zombie = Vector2.new(-3, 0),
		Boss = Vector2.new(-1, 0),
	}),
	NAME = Vector2.new(107, 22),
	NAME_TEXT = 32,
	FOUND = Vector2.new(107, 62),
	FOUND_TEXT = 17,
	NEW_RIGHT = 14,
	NEW_HEIGHT = 22,
	NEW_TEXT = 14,
	RING = 6,
})

local Timing = table.freeze({
	PANEL_DELAY = 0.05,
	PANEL_SLIDE = 40,
	-- The page cards grow in one after the other.
	CARDS_DELAY = 0.12,
	CARDS_STAGGER = 0.06,
	RING_PERIOD = 0.28,
	RING_DAMPING = 0.8,
	-- A count going up is punched this much; the bar slides to its new share and its fill flares.
	COUNT_PUNCH = 0.35,
	BAR_PERIOD = 0.6,
	BAR_DAMPING = 0.75,
	BAR_FLARE_GAP = 0.08,
	HOVER_BRACKETS = 4,
	GLYPH_GROW = 0.12,
})

-- The bar's track.
local TRACK = Color3.fromRGB(46, 38, 72)

local Categories = {}

local function pageCard(
	state: Types.TIndexState,
	actions: Types.TIndexActions,
	category,
	elapsed: () -> number
): TextButton
	local key = category.Key
	local accent = category.Accent
	local hand = Hand.React("Take")
	local away = Parts.Away(state, elapsed, Timing.CARDS_DELAY + Timing.CARDS_STAGGER * (key - 1))
	local found = derive(function(): number
		return Parts.ShownCount(state, category.Enemies)
	end)
	local punch = Parts.Punched(found, Timing.COUNT_PUNCH)
	local hasNew = derive(function(): boolean
		local hidden, unread = state.Hidden(), state.Unread()
		for _, enemy in category.Enemies do
			if hidden[enemy.Id] or unread[enemy.Id] then return true end
		end
		return false
	end)
	local glyphOffset = Layout.TILE_GLYPH_OFFSETS[category.Glyph]
	local top = Layout.CARD.Y + Layout.CARD_STEP * (key - 1)

	return Components.Button({
		Name = category.Word,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(Layout.CARD.X + Layout.CARD_SIZE.X / 2, top + Layout.CARD_SIZE.Y / 2),
		Size = UDim2.fromOffset(Layout.CARD_SIZE.X, Layout.CARD_SIZE.Y),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Activated = function()
			hand.Commit()
			if state.Category() ~= key then SoundsCore.PlayUINamed("UI.UpgradePick", "Deal") end
			actions.PickCategory(key)
		end,
		hand.Events,
		create("UIScale")({
			Scale = function()
				return (1 - away()) * hand.Scale()
			end,
		}),
		Components.Card({
			Accent = Parts.EdgeOf(accent),
			Glow = accent,
			GlowTransparency = function()
				return 0.7 - 0.35 * hand.Light()
			end,
			Tint = 0.35,
			Marks = true,
			Brackets = function()
				return Layout.CARD_BRACKETS + Timing.HOVER_BRACKETS * hand.Rise()
			end,
			BracketLength = 20,
			BracketTransparency = function()
				return if state.Category() == key then 1 else 0.6 - 0.3 * hand.Light()
			end,
		}, {
			Name = "Card",
			Size = UDim2.fromScale(1, 1),
			Hand.WashLayer(hand, 3, 2),
			Components.Sheen(hand.Glint, 3),
			create("Frame")({
				Name = "Tile",
				Position = UDim2.fromOffset(Layout.TILE.X, Layout.TILE.Y),
				Size = UDim2.fromOffset(Layout.TILE_SIZE, Layout.TILE_SIZE),
				BackgroundColor3 = Parts.EdgeOf(accent),
				BorderSizePixel = 0,
				ZIndex = 4,
				create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
				create("Frame")({
					Name = "Face",
					Position = UDim2.fromOffset(1, 1),
					Size = UDim2.new(1, -2, 1, -2),
					BackgroundColor3 = Parts.STAT_FACE,
					BorderSizePixel = 0,
					ClipsDescendants = true,
					create("UICorner")({ CornerRadius = UDim.new(0, 1) }),
					Components.Icon(category.Glyph, {
						Name = "Glyph",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.new(0.5, glyphOffset.X, 0.5, glyphOffset.Y),
						Size = Components.GlyphBox(Layout.TILE_GLYPH),
						ImageColor3 = accent,
						create("UIScale")({
							Scale = function()
								return 1 + Timing.GLYPH_GROW * hand.Rise()
							end,
						}),
					}),
				}),
			}),
			Label({
				Name = "Word",
				Position = UDim2.fromOffset(Layout.NAME.X, Layout.NAME.Y),
				Size = UDim2.fromOffset(260, Layout.NAME_TEXT),
				TextSize = Layout.NAME_TEXT,
				Text = category.Word,
			}),
			Label({
				Name = "Found",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromOffset(Layout.FOUND.X, Layout.FOUND.Y + Layout.FOUND_TEXT / 2),
				Size = UDim2.fromOffset(200, Layout.FOUND_TEXT),
				FontFace = Font.DisplayBold,
				TextSize = Layout.FOUND_TEXT,
				TextColor3 = accent,
				Text = function()
					return `{found()} / {#category.Enemies}  FOUND`
				end,
				create("UIScale")({
					Scale = function()
						return 1 + punch()
					end,
				}),
			}),
			create("Frame")({
				Name = "New",
				AnchorPoint = Vector2.new(1, 0.5),
				AutomaticSize = Enum.AutomaticSize.X,
				Position = UDim2.new(1, -Layout.NEW_RIGHT, 0.5, 0),
				Size = UDim2.fromOffset(0, Layout.NEW_HEIGHT),
				BackgroundColor3 = Palette.Pink,
				BorderSizePixel = 0,
				Visible = hasNew,
				ZIndex = 5,
				create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
				create("UIPadding")({ PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) }),
				Label({
					AutomaticSize = Enum.AutomaticSize.X,
					Size = UDim2.fromScale(0, 1),
					TextYAlignment = Enum.TextYAlignment.Center,
					TextSize = Layout.NEW_TEXT,
					Text = "NEW",
					ZIndex = 6,
				}),
			}),
		}),
	}) :: TextButton
end

-- One of his two headers, `y` px below the first's place.
local function header(glyph: Instance, word: string, color: Color3, count: any, y: number): { Instance }
	return {
		glyph,
		Label({
			Position = UDim2.fromOffset(Layout.TITLE.X, Layout.TITLE.Y + y),
			Size = UDim2.fromOffset(260, Layout.TITLE_TEXT),
			TextSize = Layout.TITLE_TEXT,
			TextColor3 = color,
			Text = word,
		}),
		count,
		create("Frame")({
			Name = "Rule",
			Position = UDim2.fromOffset(Layout.RULE.X, Layout.RULE.Y + y),
			Size = UDim2.fromOffset(Layout.RULE_WIDTH, 1),
			BackgroundColor3 = Parts.RULE,
			BorderSizePixel = 0,
			ZIndex = 4,
		}),
	}
end

function Categories.Build(state: Types.TIndexState, actions: Types.TIndexActions, elapsed: () -> number): Frame
	local away = Parts.Away(state, elapsed, Timing.PANEL_DELAY)
	local faded = Parts.Faded(state, elapsed, Timing.PANEL_DELAY)
	local total = derive(function(): number
		local count = 0
		for _, category in Parts.CATEGORIES do
			count += Parts.ShownCount(state, category.Enemies)
		end
		return count
	end)
	local punch = Parts.Punched(total, Timing.COUNT_PUNCH)
	local share = Hand.Spring(function(): number
		return total() / math.max(Parts.TOTAL, 1)
	end, Timing.BAR_PERIOD, Timing.BAR_DAMPING)
	-- The fill flares while it is still sliding up to a new share, fully lit while it is BAR_FLARE_GAP short of it.
	local flare = derive(function(): number
		local behind = total() / math.max(Parts.TOTAL, 1) - share()
		return math.clamp(behind / Timing.BAR_FLARE_GAP, 0, 1)
	end)

	local cards = {}
	for key, category in Parts.CATEGORIES do
		cards[key] = pageCard(state, actions, category, elapsed)
	end
	local ringY = spring(function(): number
		return Layout.CARD.Y + Layout.CARD_STEP * (state.Category() - 1) + Layout.CARD_SIZE.Y / 2
	end, Timing.RING_PERIOD, Timing.RING_DAMPING)
	local ringFaded = Parts.Faded(state, elapsed, Timing.CARDS_DELAY)
	local margin = Layout.MARGIN

	-- The panel and what is written on it fade as one picture in a group with room for its shadow; the cards move
	-- under the hand and hold pictures, so they grow in on their own instead.
	return create("Frame")({
		Name = "Categories",
		Position = function()
			return UDim2.fromOffset(Layout.PANEL.X - math.round(Timing.PANEL_SLIDE * away()), Layout.PANEL.Y)
		end,
		Size = UDim2.fromOffset(Layout.SIZE.X, Layout.SIZE.Y),
		BackgroundTransparency = 1,
		ZIndex = 2,
		create("CanvasGroup")({
			Name = "Chrome",
			Position = UDim2.fromOffset(-margin, -margin),
			Size = UDim2.new(1, 2 * margin, 1, 2 * margin),
			BackgroundTransparency = 1,
			GroupTransparency = faded,
			Components.Panel({ Brackets = Layout.BRACKETS, Tall = true }, {
				Name = "Panel",
				Position = UDim2.fromOffset(margin, margin),
				Size = UDim2.fromOffset(Layout.SIZE.X, Layout.SIZE.Y),
				header(
					Components.Icon("Skull", {
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromOffset(Layout.GLYPH.X, Layout.GLYPH.Y),
						Size = Components.GlyphBox(Layout.GLYPH_SIZE),
						ImageColor3 = Palette.Pink,
						ZIndex = 4,
					}),
					"CATEGORIES",
					Palette.White,
					Label({
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.fromOffset(Layout.COUNT_RIGHT, Layout.COUNT_Y),
						Size = UDim2.fromOffset(200, Layout.COUNT_TEXT),
						TextXAlignment = Enum.TextXAlignment.Right,
						FontFace = Font.DisplayBold,
						TextSize = Layout.COUNT_TEXT,
						TextColor3 = Palette.Gold,
						Text = `{#Parts.CATEGORIES} TYPES`,
					}),
					0
				),
				header(
					Label({
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromOffset(Layout.QUESTION.X, Layout.QUESTION.Y + Layout.COMPLETION_Y),
						Size = UDim2.fromOffset(Layout.QUESTION_TEXT, Layout.QUESTION_TEXT),
						TextXAlignment = Enum.TextXAlignment.Center,
						TextYAlignment = Enum.TextYAlignment.Center,
						TextSize = Layout.QUESTION_TEXT,
						TextColor3 = Palette.Gold,
						Text = "?",
					}),
					"COMPLETION",
					Palette.Gold,
					Label({
						Name = "Total",
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.fromOffset(
							Layout.COUNT_RIGHT,
							Layout.COUNT_Y + Layout.COMPLETION_Y + Layout.COUNT_TEXT / 2
						),
						Size = UDim2.fromOffset(200, Layout.COUNT_TEXT),
						TextXAlignment = Enum.TextXAlignment.Right,
						TextSize = Layout.COUNT_TEXT,
						Text = function()
							return `{total()} / {Parts.TOTAL}`
						end,
						create("UIScale")({
							Scale = function()
								return 1 + punch()
							end,
						}),
					}),
					Layout.COMPLETION_Y
				),
				create("Frame")({
					Name = "Bar",
					Position = UDim2.fromOffset(Layout.BAR.X, Layout.BAR.Y),
					Size = UDim2.fromOffset(Layout.BAR_SIZE.X, Layout.BAR_SIZE.Y),
					BackgroundColor3 = TRACK,
					BorderSizePixel = 0,
					ZIndex = 4,
					create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
					create("Frame")({
						Name = "Fill",
						Size = function()
							return UDim2.fromScale(math.clamp(share(), 0, 1), 1)
						end,
						BackgroundColor3 = function()
							return Palette.Pink:Lerp(Palette.White, 0.6 * flare())
						end,
						BorderSizePixel = 0,
						Visible = function()
							return share() > 0.001
						end,
						ZIndex = 5,
						create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
					}),
				}),
			}),
		}),
		cards,
		Parts.Ring(Layout.RING, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				return UDim2.fromOffset(Layout.CARD.X + Layout.CARD_SIZE.X / 2, math.round(ringY()))
			end,
			Size = UDim2.fromOffset(Layout.CARD_SIZE.X, Layout.CARD_SIZE.Y),
			Visible = function()
				return ringFaded() < 0.5
			end,
			ZIndex = 2,
		}),
	})
end

return Categories
