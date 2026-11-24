--!nonstrict
-- The categories (his left panel): a card for each page with his glyph for it, its name and how many of it are
-- found, the brackets closed round the page on show, and COMPLETION with its bar under them. His reward card is left
-- out: discovering everything earns nothing yet. A count goes up as each reveal lands, punched, and the bar slides on.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Ribbon = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Ribbon)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local Parts = require(script.Parent.Parts)
local panelTop = require(script.Parent.Parent.Parent.Utils.panelTop)
local Types = require(script.Parent.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Font = Theme.Font
local Label = Parts.Label

-- His drawn rects in px at 1080, from the panel's top left.
local Layout = table.freeze({
	PANEL = Vector2.new(40, 190),
	SIZE = Vector2.new(440, 850),
	MARGIN = 48,
	-- The two headers: the picture's middle and longer side, the word, the right-hand count, the rule; COMPLETION's
	-- sits COMPLETION_Y lower, his 336 plus a card step for the third page's card, which keeps his 41 px under it.
	GLYPH = Vector2.new(35, 39),
	GLYPH_SIZE = 19,
	TITLE = Vector2.new(56, 24),
	TITLE_TEXT = 29,
	COUNT_RIGHT = 416,
	COUNT_Y = 30,
	COUNT_TEXT = 18,
	RULE = Vector2.new(24, 64),
	RULE_WIDTH = 392,
	COMPLETION_Y = 460,
	BAR = Vector2.new(24, 546),
	BAR_SIZE = Vector2.new(392, 14),
	-- The page cards: the first one's top left, the step down, their size; inside one the glyph's tile, the name, the
	-- count and the NEW ribbon over the top right corner.
	CARD = Vector2.new(24, 91),
	CARD_STEP = 124,
	CARD_SIZE = Vector2.new(392, 104),
	-- 5 out, opening 2 under the hand: cards 20 apart, and his 6 + 4 crossed the next card's.
	TILE = Vector2.new(16, 16),
	TILE_SIZE = 72,
	-- The picture's longer side, centred in the tile.
	TILE_PICTURE = 62,
	NAME = Vector2.new(107, 22),
	NAME_TEXT = 32,
	FOUND = Vector2.new(107, 62),
	FOUND_TEXT = 17,
	NEW_ALONG = 64,
	NEW_THICKNESS = 20,
	NEW_TEXT = 13,
})

local Timing = table.freeze({
	PANEL_DELAY = 0.05,
	PANEL_SLIDE = 40,
	-- The page cards grow in one after the other.
	CARDS_DELAY = 0.12,
	CARDS_STAGGER = 0.06,
	-- A card's NEW slaps in this long after it starts growing in, as it lands.
	NEW_DELAY = 0.34,
	-- A count going up is punched this much; the bar slides to its new share and its fill flares.
	COUNT_PUNCH = 0.35,
	BAR_PERIOD = 0.6,
	BAR_DAMPING = 0.75,
	BAR_FLARE_GAP = 0.08,
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
		return Parts.FoundCount(state, category)
	end)
	local punch = Parts.Punched(found, Timing.COUNT_PUNCH)
	local hasNew = derive(function(): boolean
		local hidden, unread = state.Hidden(), state.Unread()
		for _, enemy in category.Enemies do
			if hidden[enemy.Id] or unread[enemy.Id] then return true end
		end
		for _, recipe in category.Potions or {} do
			if Parts.IsPotionNew(state, recipe.Id) then return true end
		end
		return false
	end)
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
			Brackets = hand.Rise,
			BracketLength = 20,
			BracketTransparency = function()
				return 0.6 - 0.3 * hand.Light()
			end,
			BracketsClosed = function()
				return state.Category() == key
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
					Components.Picture(category.Picture, {
						Name = "Glyph",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.5),
						Size = Components.PictureBox(Layout.TILE_PICTURE),
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
					return `{found()} / {Parts.Size(category)}  FOUND`
				end,
				create("UIScale")({
					Scale = function()
						return 1 + punch()
					end,
				}),
			}),
			Ribbon.Build({
				Corner = "TopRight",
				Text = "NEW",
				Color = Palette.Pink,
				IsShown = hasNew,
				Along = Layout.NEW_ALONG,
				Thickness = Layout.NEW_THICKNESS,
				TextSize = Layout.NEW_TEXT,
				Delay = Timing.CARDS_DELAY + Timing.CARDS_STAGGER * (key - 1) + Timing.NEW_DELAY,
				CallOrder = key - 1,
				ZIndex = 6,
			}),
		}),
	}) :: TextButton
end

-- One of his two headers, `y` px below the first's place, with its right-hand count when it has one.
local function header(glyph: Instance, word: string, color: Color3, count: Instance?, y: number): { Instance }
	return {
		glyph,
		Label({
			Position = UDim2.fromOffset(Layout.TITLE.X, Layout.TITLE.Y + y),
			Size = UDim2.fromOffset(260, Layout.TITLE_TEXT),
			TextSize = Layout.TITLE_TEXT,
			TextColor3 = color,
			Text = word,
		}),
		create("Frame")({
			Name = "Rule",
			Position = UDim2.fromOffset(Layout.RULE.X, Layout.RULE.Y + y),
			Size = UDim2.fromOffset(Layout.RULE_WIDTH, 1),
			BackgroundColor3 = Parts.RULE,
			BorderSizePixel = 0,
			ZIndex = 4,
		}),
		-- Last, so a header without one leaves no hole in the list.
		count,
	}
end

function Categories.Build(state: Types.TIndexState, actions: Types.TIndexActions, elapsed: () -> number): Frame
	local away = Parts.Away(state, elapsed, Timing.PANEL_DELAY)
	local faded = Parts.Faded(state, elapsed, Timing.PANEL_DELAY)
	local total = derive(function(): number
		local count = 0
		for _, category in Parts.CATEGORIES do
			count += Parts.FoundCount(state, category)
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
	local margin = Layout.MARGIN
	-- Raised to just under the top bar, its bottom staying put: everything on it rides up with the top.
	local lift = panelTop.Lift(Layout.PANEL.Y)
	local size = function(): UDim2
		return UDim2.fromOffset(Layout.SIZE.X, Layout.SIZE.Y + lift())
	end

	-- The panel and what is written on it fade as one picture in a group with room for its shadow; the cards move
	-- under the hand and hold pictures, so they grow in on their own instead.
	return create("Frame")({
		Name = "Categories",
		Position = function()
			return UDim2.fromOffset(Layout.PANEL.X - math.round(Timing.PANEL_SLIDE * away()), Layout.PANEL.Y - lift())
		end,
		Size = size,
		BackgroundTransparency = 1,
		ZIndex = 2,
		create("CanvasGroup")({
			Name = "Chrome",
			Position = UDim2.fromOffset(-margin, -margin),
			Size = UDim2.new(1, 2 * margin, 1, 2 * margin),
			BackgroundTransparency = 1,
			GroupTransparency = faded,
			Components.Panel({ Brackets = true, Tall = true }, {
				Name = "Panel",
				Position = UDim2.fromOffset(margin, margin),
				Size = size,
				header(
					Components.Picture(EIcons.Skull, {
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromOffset(Layout.GLYPH.X, Layout.GLYPH.Y),
						Size = Components.PictureBox(Layout.GLYPH_SIZE),
						ZIndex = 4,
					}),
					"CATEGORIES",
					Palette.White,
					nil,
					0
				),
				header(
					Components.Picture(EIcons.Trophy, {
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromOffset(Layout.GLYPH.X, Layout.GLYPH.Y + Layout.COMPLETION_Y),
						Size = Components.PictureBox(Layout.GLYPH_SIZE),
						ZIndex = 4,
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
	})
end

return Categories
