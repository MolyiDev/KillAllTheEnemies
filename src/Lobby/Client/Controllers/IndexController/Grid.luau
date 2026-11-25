--!nonstrict
-- The enemy grid (his middle panel): the page on show, each of its enemies as his card with the enemy's own rig on it,
-- a dark silhouette under a padlock until it is discovered. A page's cards are dealt in when the screen opens and when
-- the page is picked, and swept away as another is; the picked card's brackets close round it. The POTIONS page deals
-- the same cards with the recipe's bottle in its colour, or its silhouette under the padlock until it is brewed.
--
-- A discovery not shown yet is drawn unknown until its page comes up, then revealed on its card (Parts.Known): the
-- padlock rattles, springs open and blows away, the silhouette burns white, the card pops, flashes and throws a ring,
-- and the enemy comes through in its colours. It keeps NEW until it is picked.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local ItemCard = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.ItemCard)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Ribbon = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Ribbon)
local Scrollbar = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Scrollbar)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local Parts = require(script.Parent.Parts)
local Picture = require(script.Parent.Picture)
local padlock = require(script.Parent.Parent.Parent.Utils.padlock)
local panelTop = require(script.Parent.Parent.Parent.Utils.panelTop)
local Types = require(script.Parent.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
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
	-- The scrollbar in the margin right of the cards, clear of their brackets at a press, and its ends' room.
	SCROLLBAR_X = 899,
	SCROLLBAR_MARGIN = 12,
	COLUMNS = 4,
	-- 6 px narrower than his and 22 apart across and down (his 16 and 17), over his span: a card grows its brackets
	-- 15 px out under a press, and at his they crossed the next card's.
	FIRST = Vector2.new(26, 19),
	STEP = Vector2.new(220, 217),
	CARD = Vector2.new(198, 195),
	-- Inside a card: the picture's box, the padlock's longer side over a silhouette and the NEW ribbon (its middle line
	-- meets the edges NEW_ALONG from the corner).
	PICTURE_BOX = 158,
	-- A recipe's bottle, its longer side.
	BOTTLE = 124,
	LOCK = 80,
	NEW_ALONG = 72,
	NEW_THICKNESS = 22,
	NEW_TEXT = 14,
	-- 3 out, opening 1 under the hand: cards 16 apart grow 6 px a side under the hand and more on a press, and his 6 + 4
	-- crossed the next card's and ran out past the grid's edge.
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
	-- Under the hand a card's enemy turns to face you.
	HOVER_TURN = 28,
	-- A reveal, from the moment the enemy starts coming through: the card pops, flashes and throws a ring.
	POP_PERIOD = 0.28,
	POP_DAMPING = 0.5,
	POP = 0.18,
	FLASH = 0.45,
	BURST = 0.55,
	-- Under the hand a locked card's padlock grows; pressed, it rattles on its spring (degrees).
	LOCK_GROW = 0.1,
	RATTLE_PERIOD = 0.11,
	RATTLE_DAMPING = 0.22,
	RATTLE = 14,
	-- The count going up punches it this much.
	COUNT_PUNCH = 0.3,
})

-- The panel is raised to just under the top bar, its bottom staying put: the window of cards grows with it.
local panelLift = panelTop.Lift(Layout.PANEL.Y)
local function panelSize(): UDim2
	return UDim2.fromOffset(Layout.SIZE.X, Layout.SIZE.Y + panelLift())
end

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

-- The padlock over an unknown enemy's silhouette: `unlocking` is seconds into its reveal (0 shut), `rattle` and `rise`
-- the hand's.
local function lock(unlocking: () -> number, rattle: () -> number, rise: () -> number): Frame
	return padlock.Build({
		Unlocking = unlocking,
		Turn = rattle,
		Grow = function(): number
			return Timing.LOCK_GROW * rise()
		end,
		At = ItemCard.PictureAt(Layout.CARD),
		Longest = Layout.LOCK,
		ZIndex = 5,
	})
end

-- One card, an enemy's or a recipe's. `spec`: Name, Accent, Known (Parts.Known's 0 to 1), SinceLit (Parts.SinceLit),
-- IsSelected, IsNew (whether it wears NEW once known), Select (the press) and Picture (burned, lit, hand) -> the
-- thing drawn over its silhouette.
local function card(state: Types.TIndexState, spec, order: number, dealt: () -> number): TextButton
	local accent = spec.Accent
	local hand = Hand.React("Take")
	local known = spec.Known
	local burned = Parts.Burned(known)
	local lit = Parts.Lit(known)
	local isSelected = spec.IsSelected
	local sinceLit = spec.SinceLit
	local flash = Parts.Fading(sinceLit, Timing.FLASH)
	local burst = Parts.Over(sinceLit, Timing.BURST, 1)
	-- Seconds into the reveal, for the padlock: 0 while unknown, past its leaving once known.
	local unlocking = function(): number
		return known() * Parts.REVEAL_SECONDS
	end
	local rattle, strikeRattle = Hand.Kick(Timing.RATTLE_PERIOD, Timing.RATTLE_DAMPING)

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

	local accentNow = function(): Color3
		return Parts.LOCKED:Lerp(accent, lit())
	end
	local glow = function(): Color3
		return Parts.LOCKED:Lerp(accent, lit()):Lerp(Palette.White, flash())
	end
	local at = placeOf(order)

	return ItemCard.Build({
		Name = spec.Name,
		Size = Layout.CARD,
		Position = UDim2.fromOffset(at.X, at.Y),
		Hand = hand,
		Accent = accentNow,
		Glow = glow,
		Title = function()
			return if lit() > 0 then string.upper(spec.Name) else Parts.UNKNOWN
		end,
		Lit = lit,
		IsSelected = isSelected,
		Grown = function()
			return Motion.Decelerate(dealt())
		end,
		-- The light crosses it as it is dealt.
		Sheen = dealt,
		Pop = pop,
		Flash = flash,
		Ring = burst,
		Picture = spec.Picture(burned, lit, hand),
		Children = {
			lock(unlocking, rattle, hand.Rise),
			Ribbon.Build({
				Corner = "TopRight",
				Text = "NEW",
				Color = Palette.Pink,
				IsShown = function()
					return spec.IsNew() and lit() >= 1
				end,
				Along = Layout.NEW_ALONG,
				Thickness = Layout.NEW_THICKNESS,
				TextSize = Layout.NEW_TEXT,
				Delay = Timing.DEAL_DELAY + Timing.DEAL_STAGGER * (order - 1) + Timing.DEAL,
				CallOrder = order,
				ZIndex = 6,
			}),
		},
		Activated = function()
			if unlocking() == 0 then strikeRattle(Timing.RATTLE) end
			spec.Select()
		end,
	})
end

local function enemyCard(
	state: Types.TIndexState,
	actions: Types.TIndexActions,
	enemy,
	order: number,
	dealt: () -> number
): TextButton
	local id = enemy.Id
	local function idOf(): number
		return id
	end

	return card(state, {
		Name = enemy.Name,
		Accent = Parts.Threat(enemy).Accent,
		Known = Parts.Known(state, idOf),
		SinceLit = Parts.SinceLit(state, idOf),
		IsSelected = derive(function(): boolean
			return state.Selected() == id
		end),
		IsNew = function(): boolean
			return state.Unread()[id] == true
		end,
		Select = function()
			actions.Select(id)
		end,
		Picture = function(burned: () -> number, lit: () -> number, hand)
			return Picture.Build(function()
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
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(Layout.PICTURE_BOX, Layout.PICTURE_BOX),
			})
		end,
	}, order, dealt)
end

-- A recipe's card: its bottle in its colour once brewed, a dark bottle under the padlock before. A recipe new from the
-- lab is revealed on it as an enemy is.
local function potionCard(
	state: Types.TIndexState,
	actions: Types.TIndexActions,
	recipe,
	order: number,
	dealt: () -> number
): TextButton
	local id = recipe.Id
	local color = Parts.PotionColor(recipe)
	local function idOf(): number
		return id
	end

	return card(state, {
		Name = recipe.Name,
		Accent = color,
		Known = Parts.PotionKnown(state, idOf),
		SinceLit = Parts.PotionSinceLit(state, idOf),
		IsSelected = derive(function(): boolean
			return state.SelectedPotion() == id
		end),
		IsNew = function(): boolean
			return Parts.IsPotionNew(state, id)
		end,
		Select = function()
			actions.SelectPotion(id)
		end,
		Picture = function(burned: () -> number, lit: () -> number, _)
			return Components.Picture(EIcons.PotionBottle, {
				Name = "Bottle",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = Components.PictureBox(Layout.BOTTLE),
				ImageColor3 = function()
					return Parts.SILHOUETTE:Lerp(Palette.White, burned()):Lerp(color, lit())
				end,
			})
		end,
	}, order, dealt)
end

-- One page's cards, for vide.switch: grown in when the page comes up and shrunk away when another does.
-- `shown` is the panel's fade, which the scrollbar follows: the cards are not in the panel's group.
local function page(
	state: Types.TIndexState,
	actions: Types.TIndexActions,
	category,
	present: () -> boolean,
	shown: () -> number
)
	-- When this page's cards start growing in: the later of the open and the pick of the page.
	local builtAt = os.clock()
	local size = Parts.Size(category)
	actions.Stir(Timing.DEAL_DELAY + Timing.DEAL + Timing.DEAL_STAGGER * size)
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

	local children = table.create(size)
	for order, enemy in category.Enemies do
		children[order] = enemyCard(state, actions, enemy, order, dealt(order))
	end
	for order, recipe in category.Potions or {} do
		children[order] = potionCard(state, actions, recipe, order, dealt(order))
	end

	local rows = math.max(1, math.ceil(size / Layout.COLUMNS))
	local window = create("ScrollingFrame")({
		Name = category.Word,
		Position = UDim2.fromOffset(0, Layout.WINDOW_Y),
		Size = UDim2.new(1, 0, 1, -Layout.WINDOW_Y),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(0, 2 * Layout.FIRST.Y + (rows - 1) * Layout.STEP.Y + Layout.CARD.Y),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 0,
		ZIndex = 2,
		children,
	}) :: ScrollingFrame
	local holder = create("Frame")({
		Name = `{category.Word}Page`,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		window,
		Scrollbar.Build(window, {
			Length = function(): number
				return Layout.SIZE.Y + panelLift() - Layout.WINDOW_Y - 2 * Layout.SCROLLBAR_MARGIN
			end,
			Shown = shown,
		}, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(Layout.SCROLLBAR_X, Layout.WINDOW_Y + Layout.SCROLLBAR_MARGIN),
			ZIndex = 3,
		}),
	})
	vide.cleanup(function()
		holder:Destroy()
	end)

	return holder, Timing.SWEEP + 0.02
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
		return Parts.FoundCount(state, category())
	end)
	local punch = Parts.Punched(found, Timing.COUNT_PUNCH, state.Category)

	local pages = {}
	for key, each in Parts.CATEGORIES do
		pages[key] = function(present)
			return page(state, actions, each, present, function(): number
				return 1 - faded()
			end)
		end
	end
	local margin = Layout.MARGIN

	-- The panel and its header fade as one picture in a group with room for its shadow. The cards are not in it:
	-- they carry the enemies' own pictures and move under the hand, and a group redraws its whole canvas whenever
	-- anything in it changes; they grow in and shrink away on their own instead.
	return create("Frame")({
		Name = "Grid",
		Position = function()
			return UDim2.fromOffset(
				Layout.PANEL.X,
				Layout.PANEL.Y - panelLift() + math.round(Timing.PANEL_SLIDE * away())
			)
		end,
		Size = panelSize,
		BackgroundTransparency = 1,
		ZIndex = 2,
		create("CanvasGroup")({
			Name = "Chrome",
			Position = UDim2.fromOffset(-margin, -margin),
			Size = UDim2.new(1, 2 * margin, 1, 2 * margin),
			BackgroundTransparency = 1,
			GroupTransparency = faded,
			Components.Panel({ Brackets = true, Tall = true, Wide = true }, {
				Name = "Panel",
				Position = UDim2.fromOffset(margin, margin),
				Size = panelSize,
				Components.Picture(function()
					return category().Picture
				end, {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(Layout.GLYPH.X, Layout.GLYPH.Y),
					Size = Components.PictureBox(Layout.GLYPH_SIZE),
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
						return `DISCOVERED  {found()} / {Parts.Size(category())}`
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
