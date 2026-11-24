--!nonstrict
-- The equipment grid (his left panel, Item Grid Container): ALL | HEAD | TORSO | LEGS under his pink slab, ITEMS with
-- how many of them are owned, and each piece as his card with its own model on it: dim with a lock until it is got,
-- the green tick on the ones worn, closed brackets round the one picked. A filter's cards are dealt in when the page
-- comes up and when it is picked, and shrink away as another is.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local EquipmentCore = require(ReplicatedStorage.GlobalShared.Core.EquipmentCore)
local Parts = require(script.Parent.Parts)
local panelTop = require(script.Parent.Parent.Parent.Utils.panelTop)
local Types = require(script.Parent.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress
local Label = Parts.Label

-- His drawn rects in px at 1080, from the panel's top left (his panel is the classes list's).
local Layout = table.freeze({
	PANEL = Vector2.new(40, 190),
	SIZE = Vector2.new(440, 850),
	TEXTURE = Vector2.new(120, 60),
	BRACKET_LENGTH = 24,
	-- The filter tabs: 86 wide and 17 apart over his span (his 92 and 8): a Take tab's brackets reach 10 px out under
	-- a press. The slab under the picked one is a px bigger all round.
	TAB_LEFTS = { 22, 125, 228, 331 },
	TAB_TOP = 24,
	TAB_SIZE = Vector2.new(86, 47),
	TAB_BRACKET_LENGTH = 12,
	TAB_TEXT = 17,
	-- ITEMS: the glyph's middle and longer side, the word, the count's right edge, the rule.
	HEADER_GLYPH = Vector2.new(35, 110),
	HEADER_GLYPH_SIZE = 20,
	HEADER_TITLE = Vector2.new(56, 96),
	HEADER_TEXT = 29,
	COUNT_RIGHT = 418,
	COUNT_Y = 102,
	COUNT_TEXT = 18,
	RULE = Vector2.new(24, 136),
	RULE_WIDTH = 392,
	-- The cards: his 120 x 176, 18 apart across (his 16) and 20 down: a card's brackets reach 12 px out across and 14
	-- down under a press. The first row stands 24 under the rule for the same reach.
	CARD_XS = { 22, 160, 298 },
	CARD_TOP = 160,
	CARD = Vector2.new(120, 176),
	ROW_STEP = 196,
	-- Inside a card: the picture's box and middle, the rule over the name band, the name, the corner badge.
	PICTURE_BOX = 100,
	PICTURE = Vector2.new(60, 74),
	CARD_RULE = Vector2.new(12, 143),
	CARD_RULE_WIDTH = 96,
	NAME_Y = 152,
	NAME_TEXT = 13,
	CORNER_BADGE = 24,
	CORNER = Vector2.new(88, 8),
})

local Timing = table.freeze({
	-- The cards grow onto their places one after another as the page comes up and as a filter is picked.
	DEAL_DELAY = 0.1,
	DEAL_STAGGER = 0.04,
	DEAL = 0.3,
	-- The filter tabs grow in one after another as the page comes up, and ITEMS fades in a beat after the first.
	TAB_STAGGER = 0.04,
	HEADER = 0.06,
	-- A filter picked: the old cards shrink away first; the slab glides on a spring that carries a little past.
	SWEEP = 0.12,
	PICK_PERIOD = 0.3,
	PICK_DAMPING = 0.72,
	-- A count changing punches its number.
	COUNT_PERIOD = 0.3,
	COUNT_DAMPING = 0.5,
	COUNT_PUNCH = 0.3,
	-- A piece put on: its card pops and flashes, and its tick is struck in from big.
	POP_PERIOD = 0.26,
	POP_DAMPING = 0.58,
	POP = 0.12,
	FLASH = 0.4,
	TICK_FROM = 1.8,
	TICK = 0.32,
	-- A card the hand is on that refuses (not owned): the lock shakes this many px for this long.
	SHAKE = 6,
	SHAKE_SECONDS = 0.3,
})

local FILTERS = table.freeze({ "All", "Head", "Torso", "Legs" } :: { Types.TFilter })
local FILTER_WORDS = table.freeze({ All = "ALL", Head = "HEAD", Torso = "TORSO", Legs = "LEGS" })

local Grid = {}

local function itemsOf(filter: Types.TFilter)
	return if filter == "All" then EquipmentCore.All else EquipmentCore.BySlot[filter]
end

-- One filter tab: his dark plate, its brackets closed while it is picked, and its word over the slab. Returns its
-- pieces and its hand's scale, for the slab lying on it.
local function tab(
	state: Types.TEquipmentState,
	actions: Types.TEquipmentActions,
	index: number
): ({ Instance }, () -> number)
	local filter = FILTERS[index]
	local isPicked = derive(function(): boolean
		return state.Filter() == filter
	end)
	local hand = Hand.React("Take", function(): boolean
		return not isPicked()
	end)
	local picked = Hand.Spring(function(): number
		return if isPicked() then 1 else 0
	end, Timing.PICK_PERIOD)
	local landed = Parts.Landing(state, Timing.TAB_STAGGER * index)
	-- Grown onto its place as the page comes up, one after another.
	local dealt = Parts.Dealt(state, Timing.TAB_STAGGER * (index - 1), Timing.DEAL)
	local grown = function(): number
		return Motion.Decelerate(dealt()) * hand.Scale()
	end
	local position =
		UDim2.fromOffset(Layout.TAB_LEFTS[index] + Layout.TAB_SIZE.X / 2, Layout.TAB_TOP + Layout.TAB_SIZE.Y / 2)

	local word = Label({
		Name = `{filter}Word`,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(Layout.TAB_SIZE.X, Layout.TAB_TEXT),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = Layout.TAB_TEXT,
		TextColor3 = function()
			return Palette.Lavender:Lerp(Palette.White, math.clamp(picked(), 0, 1))
		end,
		Text = FILTER_WORDS[filter],
		ZIndex = 6,
		create("UIScale")({ Scale = grown }),
	})

	local button = Components.Button({
		Name = `{filter}Tab`,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(Layout.TAB_SIZE.X, Layout.TAB_SIZE.Y),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Activated = function()
			if isPicked() then return end
			hand.Commit()
			actions.Filter(filter)
		end,
		hand.Events,
		create("UIScale")({ Scale = grown }),
		Components.Panel({
			Glow = function()
				return Color3.new():Lerp(Palette.Pink, hand.Light())
			end,
			GlowTransparency = function()
				return 0.6 - 0.3 * hand.Light()
			end,
		}, {
			Name = "Plate",
			Size = UDim2.fromScale(1, 1),
			Hand.WashLayer(hand, 3, 2),
			Components.Sheen(Hand.Sheen(hand, landed), 3),
			create("Frame")({
				Name = "BracketsHolder",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Components.Brackets(hand.Rise, function()
					return 0.6 - 0.3 * hand.Light()
				end, Layout.TAB_BRACKET_LENGTH, isPicked),
			}),
		}),
	}) :: TextButton

	return { button, word }, hand.Scale
end

local function tabs(state: Types.TEquipmentState, actions: Types.TEquipmentActions): { Instance }
	local pieces, scales = {}, {}
	for index in FILTERS do
		local own, scale = tab(state, actions, index)
		table.move(own, 1, #own, #pieces + 1, pieces)
		scales[index] = scale
	end
	local pickedIndex = function(): number
		return table.find(FILTERS, state.Filter()) or 1
	end
	local x = Hand.Spring(function(): number
		return Layout.TAB_LEFTS[pickedIndex()]
	end, Timing.PICK_PERIOD, Timing.PICK_DAMPING)

	-- No brackets of its own: the plate's, under it, answer the hand (UI.md).
	table.insert(
		pieces,
		Components.Slab({ Kind = "Pink", Marks = true }, {
			Name = "Glider",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				return UDim2.fromOffset(math.round(x()) + Layout.TAB_SIZE.X / 2, Layout.TAB_TOP + Layout.TAB_SIZE.Y / 2)
			end,
			Size = UDim2.fromOffset(Layout.TAB_SIZE.X + 2, Layout.TAB_SIZE.Y + 2),
			ZIndex = 5,
			create("UIScale")({
				Scale = function()
					return scales[pickedIndex()]()
				end,
			}),
		})
	)

	return pieces
end

-- One piece's card at grid place `order`, grown in by `dealt`.
local function card(
	state: Types.TEquipmentState,
	actions: Types.TEquipmentActions,
	item,
	order: number,
	dealt: () -> number
): TextButton
	local rarity = Parts.RARITIES[item.Rarity]
	local accent = rarity.Accent
	local hand = Hand.React("Take")
	local column = (order - 1) % 3 + 1
	local row = (order - 1) // 3
	local isOwned = derive(function(): boolean
		return state.Owned()[item.Id] == true
	end)
	local isWorn = derive(function(): boolean
		return state.Equipped()[item.Slot] == item.Id
	end)
	local isSelected = derive(function(): boolean
		return state.Selected() == item.Id
	end)
	-- 0 to 1 from the moment this piece is put on; 1 otherwise.
	local putOn = derive(function(): number
		if state.ChangedItem() ~= item.Id or state.Change() ~= "Equip" then return 1 end
		return Progress(state.Now(), state.ChangedAt(), Timing.TICK)
	end)
	local flash = derive(function(): number
		if state.ChangedItem() ~= item.Id or state.Change() ~= "Equip" then return 0 end
		return Motion.Fade(state.Now(), state.ChangedAt(), Timing.FLASH)
	end)
	local pop, strikePop = Hand.Kick(Timing.POP_PERIOD, Timing.POP_DAMPING)
	-- Struck once a piece put on, on the answer's stamp: never as the page is built.
	vide.effect(function()
		local at = state.ChangedAt()
		vide.untrack(function()
			local isPutOn = state.ChangedItem() == item.Id and state.Change() == "Equip"
			if isPutOn and os.clock() - at < Timing.TICK then strikePop(Timing.POP) end
		end)
	end)
	-- The lock shakes its head when a press on this picked piece is refused.
	local shake = derive(function(): number
		if not isSelected() or isOwned() then return 0 end
		local at = state.RefusedAt()
		return math.round(Timing.SHAKE * Motion.Shake(Progress(state.Now(), at, Timing.SHAKE_SECONDS), at))
	end)
	local tint = derive(function(): Color3
		return if isOwned() then Palette.White else Parts.LOCKED_TINT
	end)

	return Components.Button({
		Name = item.Name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(
			Layout.CARD_XS[column] + Layout.CARD.X / 2,
			Layout.CARD_TOP + row * Layout.ROW_STEP + Layout.CARD.Y / 2
		),
		Size = UDim2.fromOffset(Layout.CARD.X, Layout.CARD.Y),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Activated = function()
			hand.Commit()
			actions.Select(item.Id)
		end,
		hand.Events,
		create("UIScale")({
			Scale = function()
				return Motion.Decelerate(dealt()) * (hand.Scale() + pop())
			end,
		}),
		Components.Card({
			Accent = Parts.EdgeOf(accent),
			Glow = accent,
			GlowTransparency = function()
				return 0.7 - 0.35 * math.max(hand.Light(), flash())
			end,
			Tint = 0.35,
			Marks = true,
			Brackets = hand.Rise,
			BracketLength = 20,
			BracketTransparency = function()
				return 0.6 - 0.3 * hand.Light()
			end,
			BracketsClosed = isSelected,
		}, {
			Name = "Card",
			Size = UDim2.fromScale(1, 1),
			Hand.WashLayer(hand, 3, 2),
			Components.Sheen(hand.Glint, 3),
			Parts.Picture(function()
				return item.Id
			end, {
				Tint = tint,
				Transparency = function()
					return if isOwned() then 0 else Parts.LOCKED_TRANSPARENCY
				end,
			}, {
				Name = "Picture",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(Layout.PICTURE.X, Layout.PICTURE.Y),
				Size = UDim2.fromOffset(Layout.PICTURE_BOX, Layout.PICTURE_BOX),
				ZIndex = 4,
				create("UIScale")({
					Scale = function()
						return 1 + 0.1 * hand.Rise()
					end,
				}),
			}),
			create("Frame")({
				Name = "Rule",
				Position = UDim2.fromOffset(Layout.CARD_RULE.X, Layout.CARD_RULE.Y),
				Size = UDim2.fromOffset(Layout.CARD_RULE_WIDTH, 2),
				BackgroundColor3 = accent,
				BackgroundTransparency = 0.6,
				BorderSizePixel = 0,
				ZIndex = 4,
			}),
			Label({
				Name = "Name",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromOffset(Layout.CARD.X / 2, Layout.NAME_Y),
				Size = UDim2.fromOffset(Layout.CARD.X - 12, Layout.NAME_TEXT),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextScaled = true,
				TextColor3 = function()
					return if isOwned() then Palette.White else Palette.Lavender
				end,
				Text = string.upper(item.Name),
				create("UITextSizeConstraint")({ MaxTextSize = Layout.NAME_TEXT }),
			}),
			Parts.Badge("Lock", Layout.CORNER_BADGE, {
				Name = "Lock",
				Position = function()
					return UDim2.fromOffset(Layout.CORNER.X + shake(), Layout.CORNER.Y)
				end,
				Visible = function()
					return not isOwned()
				end,
				ZIndex = 6,
			}),
			-- Struck in from big as the piece is put on.
			Parts.Badge("Check", Layout.CORNER_BADGE, {
				Name = "Worn",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(
					Layout.CORNER.X + Layout.CORNER_BADGE / 2,
					Layout.CORNER.Y + Layout.CORNER_BADGE / 2
				),
				Visible = isWorn,
				ZIndex = 6,
				create("UIScale")({
					Scale = function()
						return 1 + (Timing.TICK_FROM - 1) * (1 - Motion.Decelerate(putOn()))
					end,
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
					return 1 - 0.7 * flash()
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			}),
		}),
	}) :: TextButton
end

-- One filter's cards, for vide.switch: grown in when the filter comes up and shrunk away when another does.
local function page(
	state: Types.TEquipmentState,
	actions: Types.TEquipmentActions,
	filter: Types.TFilter,
	present: () -> boolean
)
	local builtAt = os.clock()
	actions.Stir(Timing.DEAL_DELAY + Timing.DEAL * 3)
	local function dealt(order: number): () -> number
		return derive(function(): number
			if not present() then
				return 1 - Motion.Accelerate(Progress(state.Now(), state.FilterAt(), Timing.SWEEP))
			end
			if not state.IsShown() then return 1 end
			local from = math.max(state.ShownAt() + Timing.DEAL_DELAY, builtAt + Timing.SWEEP)
			return Progress(state.Now(), from, Timing.DEAL, Timing.DEAL_STAGGER * (order - 1))
		end)
	end

	local cards = {}
	for order, item in itemsOf(filter) do
		cards[order] = card(state, actions, item, order, dealt(order))
	end

	local frame = create("Frame")({
		Name = filter,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		cards,
	})
	vide.cleanup(function()
		frame:Destroy()
	end)

	return frame, Timing.SWEEP + 0.02
end

-- How many of the filter's pieces are owned, and how many there are.
local function counts(state: Types.TEquipmentState): () -> (number, number)
	return function(): (number, number)
		local items = itemsOf(state.Filter())
		local owned = state.Owned()
		local count = 0
		for _, item in items do
			if owned[item.Id] then
				count += 1
			end
		end
		return count, #items
	end
end

local function countText(owned: number, total: number): string
	return `{owned} / {total} OWNED`
end

-- Every text the count can show, keyed by itself.
local function countTexts(): { [string]: string }
	local texts = {}
	for _, filter in FILTERS do
		local total = #itemsOf(filter)
		for owned = 0, total do
			local text = countText(owned, total)
			texts[text] = text
		end
	end

	return texts
end

function Grid.Build(state: Types.TEquipmentState, actions: Types.TEquipmentActions): Frame
	local headerIn = Parts.Dealt(state, Timing.HEADER, Timing.DEAL)
	local away = Parts.Away(state)
	local landed = Parts.Landing(state, 0)
	local count = counts(state)
	local punch, strike = Hand.Kick(Timing.COUNT_PERIOD, Timing.COUNT_DAMPING)
	local text = derive(function(): string
		return countText(count())
	end)
	local textBounds = Parts.TextBounds(countTexts(), Font.DisplayBold, Layout.COUNT_TEXT)
	-- The count's box is its text's width, its right edge on COUNT_RIGHT, so the punch grows from the text's middle.
	-- Unmeasured, the box is empty and its right-aligned text runs left from that edge all the same.
	local countWidth = derive(function(): number
		local bounds = textBounds()[text()]
		return if bounds then bounds.X else 0
	end)
	local last = nil
	vide.effect(function()
		local current = text()
		vide.untrack(function()
			if last and current ~= last then strike(Timing.COUNT_PUNCH) end
			last = current
		end)
	end)

	local pages = {}
	for _, filter in FILTERS do
		pages[filter] = function(present)
			return page(state, actions, filter, present)
		end
	end

	-- Raised to just under the top bar, its bottom staying put: everything on it rides up with the top.
	local lift = panelTop.Lift(Layout.PANEL.Y)

	return create("Frame")({
		Name = "Grid",
		BackgroundTransparency = 1,
		Visible = Parts.ArePanelsUp(state),
		Position = function()
			return UDim2.fromOffset(
				Layout.PANEL.X - math.round(Parts.Timing.SIDE_TRAVEL * away()),
				Layout.PANEL.Y - lift()
			)
		end,
		Size = function()
			return UDim2.fromOffset(Layout.SIZE.X, Layout.SIZE.Y + lift())
		end,
		ZIndex = 2,
		Components.Panel({
			Tall = true,
			Brackets = true,
			BracketLength = Layout.BRACKET_LENGTH,
			TexturePhase = Layout.TEXTURE,
		}, {
			Name = "Panel",
			Size = UDim2.fromScale(1, 1),
			-- Stops a press here going through to the classes page under it or to the dim.
			create("ImageButton")({
				Name = "Sink",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ImageTransparency = 1,
				Selectable = false,
				ZIndex = 0,
			}),
			Components.Sheen(landed, 3),
			tabs(state, actions),
			Components.Picture(EIcons.UpgradeArmor, {
				Name = "Glyph",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(Layout.HEADER_GLYPH.X, Layout.HEADER_GLYPH.Y),
				Size = Components.PictureBox(Layout.HEADER_GLYPH_SIZE),
				ImageTransparency = function()
					return 1 - Motion.Out(headerIn())
				end,
				ZIndex = 4,
			}),
			Label({
				Name = "Title",
				Position = UDim2.fromOffset(Layout.HEADER_TITLE.X, Layout.HEADER_TITLE.Y),
				Size = UDim2.fromOffset(200, Layout.HEADER_TEXT),
				TextSize = Layout.HEADER_TEXT,
				TextTransparency = function()
					return 1 - Motion.Out(headerIn())
				end,
				Text = "ITEMS",
			}),
			Label({
				Name = "Count",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = function()
					return UDim2.fromOffset(
						Layout.COUNT_RIGHT - countWidth() / 2,
						Layout.COUNT_Y + Layout.COUNT_TEXT / 2
					)
				end,
				Size = function()
					return UDim2.fromOffset(countWidth(), Layout.COUNT_TEXT)
				end,
				TextXAlignment = Enum.TextXAlignment.Right,
				FontFace = Font.DisplayBold,
				TextSize = Layout.COUNT_TEXT,
				TextColor3 = Palette.Gold,
				TextTransparency = function()
					return 1 - Motion.Out(headerIn())
				end,
				Text = text,
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
				BackgroundTransparency = Parts.RULE_TRANSPARENCY,
				BorderSizePixel = 0,
				ZIndex = 4,
			}),
			create("Frame")({
				Name = "Cards",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ZIndex = 3,
				vide.switch(state.Filter)(pages),
			}),
		}),
	})
end

return Grid
