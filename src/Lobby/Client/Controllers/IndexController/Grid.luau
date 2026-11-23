--!nonstrict
-- The enemy grid (his middle panel): the page on show, each of its enemies as his card with the enemy's own rig on it,
-- a dark silhouette with a "?" until it is discovered. A page's cards are dealt in when the screen opens and when the
-- page is picked, and swept away as another is; the white ring glides to the picked card.
--
-- A discovery not shown yet is drawn unknown until its page comes up, then revealed on its card (Parts.Known): the
-- silhouette burns white, the card pops, flashes and throws a ring, the lock is thrown off, and the enemy comes
-- through in its colours. It keeps NEW until it is picked.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local Parts = require(script.Parent.Parts)
local Picture = require(script.Parent.Picture)
local Types = require(script.Parent.Types)

local create = vide.create
local derive = vide.derive
local spring = vide.spring
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress
local Label = Parts.Label

-- His drawn rects in px at 1080, from the panel's top left.
local Layout = table.freeze({
	PANEL = Vector2.new(504, 190),
	SIZE = Vector2.new(912, 750),
	-- The room round the panel inside the group that fades it, for its shadow and brackets.
	MARGIN = 48,
	BRACKETS = 5,
	-- The header: the glyph's middle and longer side, the page's word, the count's right edge, the rule.
	GLYPH = Vector2.new(35, 39),
	GLYPH_SIZE = 19,
	TITLE = Vector2.new(56, 24),
	TITLE_TEXT = 29,
	COUNT_RIGHT = 888,
	COUNT_Y = 30,
	COUNT_TEXT = 18,
	RULE = Vector2.new(24, 64),
	RULE_WIDTH = 864,
	-- The cards scroll in a window under the rule once a page has more than three rows; the first row's top in it, the
	-- steps between cards and their size.
	WINDOW_Y = 70,
	COLUMNS = 4,
	FIRST = Vector2.new(23, 19),
	STEP = Vector2.new(220, 212),
	CARD = Vector2.new(204, 195),
	-- Inside a card: the picture's middle and box, the "?" over a silhouette, the rule over the name band, the name,
	-- the corner badge and NEW.
	PICTURE = Vector2.new(102, 84),
	PICTURE_BOX = 158,
	MYSTERY_TEXT = 64,
	BAND = 29,
	CARD_RULE = Vector2.new(11, 161),
	CARD_RULE_WIDTH = 182,
	NAME_Y = 172,
	NAME_TEXT = 16,
	BADGE = 25,
	BADGE_AT = Vector2.new(171, 8),
	NEW_AT = Vector2.new(8, 8),
	NEW_HEIGHT = 22,
	NEW_TEXT = 14,
	CARD_BRACKETS = 6,
	RING = 5,
})

local Timing = table.freeze({
	PANEL_DELAY = 0,
	PANEL_SLIDE = 30,
	-- Its cards grow onto their places one after another as it settles, and as a page is picked.
	DEAL_DELAY = 0.12,
	DEAL_STAGGER = 0.04,
	DEAL = 0.3,
	-- A page picked: the old cards shrink away first.
	SWEEP = 0.12,
	-- The header's word slides in as the page changes.
	TITLE = 0.25,
	TITLE_SLIDE = 14,
	RING_PERIOD = 0.3,
	RING_DAMPING = 0.8,
	-- Under the hand a card's enemy turns to face you.
	HOVER_TURN = 28,
	HOVER_GROW = 0.08,
	HOVER_BRACKETS = 4,
	-- A reveal, from the moment the enemy starts coming through: the card pops, flashes and throws a ring, and its lock
	-- is thrown off.
	POP_PERIOD = 0.28,
	POP_DAMPING = 0.5,
	POP = 0.18,
	FLASH = 0.45,
	BURST = 0.55,
	BURST_REACH = 26,
	LOCK_THROW = 0.4,
	LOCK_RISE = 22,
	-- The count going up punches it this much.
	COUNT_PUNCH = 0.3,
})

local Grid = {}

-- Where card `order` stands in the window, its middle.
local function placeOf(order: number): Vector2
	local column = (order - 1) % Layout.COLUMNS
	local row = (order - 1) // Layout.COLUMNS
	return Vector2.new(
		Layout.FIRST.X + Layout.STEP.X * column + Layout.CARD.X / 2,
		Layout.FIRST.Y + Layout.STEP.Y * row + Layout.CARD.Y / 2
	)
end

-- One enemy's card.
local function card(
	state: Types.TIndexState,
	actions: Types.TIndexActions,
	enemy,
	order: number,
	dealt: () -> number
): TextButton
	local id = enemy.Id
	local threat = Parts.Threat(enemy)
	local accent = threat.Accent
	local hand = Hand.React("Take")
	local known = Parts.Known(state, function()
		return id
	end)
	local burned = Parts.Burned(known)
	local lit = Parts.Lit(known)
	local isSelected = derive(function(): boolean
		return state.Selected() == id
	end)
	local sinceLit = Parts.SinceLit(state, function()
		return id
	end)
	local flash = Parts.Fading(sinceLit, Timing.FLASH)
	local burst = Parts.Over(sinceLit, Timing.BURST, 1)
	local thrown = Parts.Over(sinceLit, Timing.LOCK_THROW, 0)
	local isLockShown = derive(function(): boolean
		return lit() < 1 or (thrown() > 0 and thrown() < 1)
	end)

	local pop, strikePop = Hand.Kick(Timing.POP_PERIOD, Timing.POP_DAMPING)
	local isComingThrough = derive(function(): boolean
		return sinceLit() ~= nil
	end)
	vide.effect(function()
		if not isComingThrough() then return end
		vide.untrack(function()
			strikePop(Timing.POP)
		end)
	end)

	local edge = function(): Color3
		return Parts.EdgeOf(Parts.LOCKED:Lerp(accent, lit()))
	end
	local glow = function(): Color3
		return Parts.LOCKED:Lerp(accent, lit()):Lerp(Palette.White, flash())
	end
	local at = placeOf(order)

	return Components.Button({
		Name = enemy.Name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(at.X, at.Y),
		Size = UDim2.fromOffset(Layout.CARD.X, Layout.CARD.Y),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Activated = function()
			hand.Commit()
			actions.Select(id)
		end,
		hand.Events,
		create("UIScale")({
			Scale = function()
				return Motion.Decelerate(dealt()) * (hand.Scale() + pop())
			end,
		}),
		Parts.Burst(burst, Timing.BURST_REACH, accent, UDim.new(0, 4), {
			Size = UDim2.fromScale(1, 1),
		}),
		Components.Card({
			Accent = edge,
			Glow = glow,
			GlowTransparency = function()
				return 0.7 - 0.35 * math.max(hand.Light(), flash())
			end,
			Tint = 0.35,
			Band = Layout.BAND,
			Marks = true,
			Brackets = function()
				return Layout.CARD_BRACKETS + Timing.HOVER_BRACKETS * hand.Rise()
			end,
			BracketLength = 20,
			BracketTransparency = function()
				return if isSelected() then 1 else 0.6 - 0.3 * hand.Light()
			end,
		}, {
			Name = "Card",
			Size = UDim2.fromScale(1, 1),
			Hand.WashLayer(hand, 3, 2),
			Components.Sheen(hand.Glint, 3),
			Picture.Build(function()
				return enemy
			end, {
				Burned = burned,
				Lit = lit,
				-- Under the hand it turns to face you and walks.
				Moving = hand.IsHovered,
				Yaw = function()
					return Timing.HOVER_TURN * hand.Rise()
				end,
			}, {
				Name = "Enemy",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(Layout.PICTURE.X, Layout.PICTURE.Y),
				Size = UDim2.fromOffset(Layout.PICTURE_BOX, Layout.PICTURE_BOX),
				ZIndex = 4,
				create("UIScale")({
					Scale = function()
						return 1 + Timing.HOVER_GROW * hand.Rise()
					end,
				}),
			}),
			Label({
				Name = "Mystery",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(Layout.PICTURE.X, Layout.PICTURE.Y),
				Size = UDim2.fromOffset(Layout.PICTURE_BOX, Layout.MYSTERY_TEXT),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextSize = Layout.MYSTERY_TEXT,
				TextColor3 = Palette.Lavender,
				TextTransparency = function()
					return 0.35 + 0.65 * burned()
				end,
				Visible = function()
					return burned() < 1
				end,
				Text = "?",
				ZIndex = 5,
			}),
			create("Frame")({
				Name = "Rule",
				Position = UDim2.fromOffset(Layout.CARD_RULE.X, Layout.CARD_RULE.Y),
				Size = UDim2.fromOffset(Layout.CARD_RULE_WIDTH, 2),
				BackgroundColor3 = function()
					return Parts.LOCKED:Lerp(accent, lit())
				end,
				BackgroundTransparency = 0.6,
				BorderSizePixel = 0,
				ZIndex = 4,
			}),
			Label({
				Name = "Name",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromOffset(Layout.CARD.X / 2, Layout.NAME_Y),
				Size = UDim2.fromOffset(Layout.CARD.X - 16, Layout.NAME_TEXT),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextScaled = true,
				TextColor3 = function()
					return Palette.Lavender:Lerp(Palette.White, lit())
				end,
				Text = function()
					return if lit() > 0 then string.upper(enemy.Name) else Parts.UNKNOWN
				end,
				create("UITextSizeConstraint")({ MaxTextSize = Layout.NAME_TEXT }),
			}),
			Parts.Badge("Check", Layout.BADGE, {
				Name = "Found",
				Position = UDim2.fromOffset(Layout.BADGE_AT.X, Layout.BADGE_AT.Y),
				Visible = function()
					return lit() >= 1
				end,
				ZIndex = 5,
			}),
			-- Thrown off as the enemy comes through: up, turning, growing and fading as one picture.
			create("CanvasGroup")({
				Name = "Lock",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = function()
					return UDim2.fromOffset(
						Layout.BADGE_AT.X + Layout.BADGE / 2,
						Layout.BADGE_AT.Y + Layout.BADGE / 2 - math.round(Timing.LOCK_RISE * Motion.Out(thrown()))
					)
				end,
				Size = UDim2.fromOffset(Layout.BADGE, Layout.BADGE),
				Rotation = function()
					return 25 * Motion.Out(thrown())
				end,
				BackgroundTransparency = 1,
				GroupTransparency = thrown,
				Visible = isLockShown,
				ZIndex = 6,
				create("UIScale")({
					Scale = function()
						return 1 + 0.5 * Motion.Out(thrown())
					end,
				}),
				Parts.Badge("Lock", Layout.BADGE, {}),
			}),
			create("Frame")({
				Name = "New",
				AutomaticSize = Enum.AutomaticSize.X,
				Position = UDim2.fromOffset(Layout.NEW_AT.X, Layout.NEW_AT.Y),
				Size = UDim2.fromOffset(0, Layout.NEW_HEIGHT),
				BackgroundColor3 = Palette.Pink,
				BorderSizePixel = 0,
				Visible = function()
					return state.Unread()[id] == true and lit() >= 1
				end,
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
			create("Frame")({
				Name = "Flash",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Palette.White,
				BorderSizePixel = 0,
				ZIndex = 7,
				Visible = function()
					return flash() > 0.01
				end,
				BackgroundTransparency = function()
					return 1 - 0.75 * flash()
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			}),
		}),
	}) :: TextButton
end

-- One page's cards and the ring, for vide.switch: grown in when the page comes up and shrunk away when another does.
local function page(state: Types.TIndexState, actions: Types.TIndexActions, category, present: () -> boolean)
	-- When this page's cards start growing in: the later of the open and the pick of the page.
	local builtAt = os.clock()
	actions.Stir(Timing.DEAL_DELAY + Timing.DEAL + Timing.DEAL_STAGGER * #category.Enemies)
	local function dealt(order: number): () -> number
		return derive(function(): number
			if not present() then
				return 1 - Motion.Accelerate(Progress(state.Now(), state.CategoryAt(), Timing.SWEEP))
			end
			-- The cards are not under the panel's fade (Grid.Build), so they shrink away with the shut on their own.
			if not state.IsOpen() then
				return 1 - Motion.Accelerate(Progress(state.Now(), state.ToggledAt(), Parts.Timing.CLOSE))
			end
			local from = math.max(state.ToggledAt() + Timing.DEAL_DELAY, builtAt + Timing.SWEEP)
			return Progress(state.Now(), from, Timing.DEAL, Timing.DEAL_STAGGER * (order - 1))
		end)
	end

	local children = {}
	local orders = {}
	for order, enemy in category.Enemies do
		orders[enemy.Id] = order
		children[order] = card(state, actions, enemy, order, dealt(order))
	end

	local whole = dealt(1)
	local ringTarget = derive(function(): Vector2?
		local order = orders[state.Selected()]
		return if order then placeOf(order) else nil
	end)
	local ringAt = spring(function(): Vector2
		return ringTarget() or Vector2.zero
	end, Timing.RING_PERIOD, Timing.RING_DAMPING)

	local rows = math.max(1, math.ceil(#category.Enemies / Layout.COLUMNS))
	local window = create("ScrollingFrame")({
		Name = category.Word,
		Position = UDim2.fromOffset(0, Layout.WINDOW_Y),
		Size = UDim2.new(1, 0, 1, -Layout.WINDOW_Y),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(0, 2 * Layout.FIRST.Y + (rows - 1) * Layout.STEP.Y + Layout.CARD.Y),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Palette.Lavender,
		ScrollBarImageTransparency = 0.4,
		ZIndex = 2,
		children,
		Parts.Ring(Layout.RING, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				local position = ringAt()
				return UDim2.fromOffset(math.round(position.X), math.round(position.Y))
			end,
			Size = UDim2.fromOffset(Layout.CARD.X, Layout.CARD.Y),
			Visible = function()
				return ringTarget() ~= nil and whole() > 0.5
			end,
			ZIndex = 2,
		}),
	})
	vide.cleanup(function()
		window:Destroy()
	end)

	return window, Timing.SWEEP + 0.02
end

function Grid.Build(state: Types.TIndexState, actions: Types.TIndexActions, elapsed: () -> number): Frame
	local away = Parts.Away(state, elapsed, Timing.PANEL_DELAY)
	local faded = Parts.Faded(state, elapsed, Timing.PANEL_DELAY)
	local category = derive(function()
		return Parts.CATEGORIES[state.Category()]
	end)
	local titleIn = derive(function(): number
		return Progress(state.Now(), state.CategoryAt(), Timing.TITLE)
	end)
	local found = derive(function(): number
		return Parts.ShownCount(state, category().Enemies)
	end)
	local punch = Parts.Punched(found, Timing.COUNT_PUNCH, state.Category)

	local pages = {}
	for key, each in Parts.CATEGORIES do
		pages[key] = function(present)
			return page(state, actions, each, present)
		end
	end
	local margin = Layout.MARGIN

	-- The panel and its header fade as one picture in a group with room for its shadow. The cards are not in it:
	-- they carry the enemies' own pictures and move under the hand, and a group redraws its whole canvas whenever
	-- anything in it changes; they grow in and shrink away on their own instead.
	return create("Frame")({
		Name = "Grid",
		Position = function()
			return UDim2.fromOffset(Layout.PANEL.X, Layout.PANEL.Y + math.round(Timing.PANEL_SLIDE * away()))
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
			Components.Panel({ Brackets = Layout.BRACKETS, Tall = true, Wide = true }, {
				Name = "Panel",
				Position = UDim2.fromOffset(margin, margin),
				Size = UDim2.fromOffset(Layout.SIZE.X, Layout.SIZE.Y),
				Components.Icon("Skull", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(Layout.GLYPH.X, Layout.GLYPH.Y),
					Size = Components.GlyphBox(Layout.GLYPH_SIZE),
					ImageColor3 = function()
						return category().Accent
					end,
					ZIndex = 4,
				}),
				Label({
					Name = "Page",
					Position = function()
						return UDim2.fromOffset(
							Layout.TITLE.X + math.round(Timing.TITLE_SLIDE * (1 - Motion.Decelerate(titleIn()))),
							Layout.TITLE.Y
						)
					end,
					Size = UDim2.fromOffset(400, Layout.TITLE_TEXT),
					TextSize = Layout.TITLE_TEXT,
					TextTransparency = function()
						return 1 - Motion.Out(titleIn())
					end,
					Text = function()
						return category().Word
					end,
				}),
				Label({
					Name = "Count",
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.fromOffset(Layout.COUNT_RIGHT, Layout.COUNT_Y + Layout.COUNT_TEXT / 2),
					Size = UDim2.fromOffset(300, Layout.COUNT_TEXT),
					TextXAlignment = Enum.TextXAlignment.Right,
					FontFace = Font.DisplayBold,
					TextSize = Layout.COUNT_TEXT,
					TextColor3 = Palette.Gold,
					Text = function()
						return `DISCOVERED  {found()} / {#category().Enemies}`
					end,
					create("UIScale")({
						Scale = function()
							return 1 + punch()
						end,
					}),
				}),
				create("Frame")({
					Name = "Rule",
					Position = UDim2.fromOffset(Layout.RULE.X, Layout.RULE.Y),
					Size = UDim2.fromOffset(Layout.RULE_WIDTH, 1),
					BackgroundColor3 = Parts.RULE,
					BorderSizePixel = 0,
					ZIndex = 4,
				}),
			}),
		}),
		create("Frame")({
			Name = "Cards",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 2,
			vide.switch(state.Category)(pages),
		}),
	})
end

return Grid
