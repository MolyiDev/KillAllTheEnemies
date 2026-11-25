--!nonstrict
-- The POTIONS page on his panel: the slots (what is drunk as the next match starts) and every potion held, built from
-- his pieces (the section headers, his cards and flat tags). A potion card pressed goes into the first free slot, or
-- out of its slot; a slot pressed lets its potion go, or, closed, is bought (the Gems' slot) or prompts its pass.
-- DISSOLVE turns the grid to picking potions to give back a share of their souls: picked cards go red, and the second
-- press crunches them and throws their souls into the MUTATE tab.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Scrollbar = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Scrollbar)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local PotionsCore = require(ReplicatedStorage.GlobalShared.Core.PotionsCore)
local ShopCore = require(ReplicatedStorage.GlobalShared.Core.ShopCore)
local Parts = require(script.Parent.Parts)
local Types = require(script.Parent.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress
local Label = Parts.Label

local Layout = table.freeze({
	SLOTS_HEADER_Y = 300,
	SLOTS_Y = 360,
	SLOT_SIZE = Vector2.new(398, 124),
	-- Three across the column, 35 apart: past the bracket check's 22 for a 398 px Operate card.
	SLOT_GAP = 35,
	SLOT_BOTTLE = Vector2.new(62, 62),
	SLOT_BOTTLE_SIZE = 84,
	SLOT_TEXT_X = 120,
	GRID_HEADER_Y = 510,
	-- The window clips, so it stands a bracket's reach outside the cards on every side.
	WINDOW = Rect.new(312, 558, 1608, 934),
	WINDOW_PAD = 16,
	CARD_SIZE = Vector2.new(160, 160),
	CARD_GAP = 24,
	COLUMNS = 7,
	CARD_BOTTLE_Y = 62,
	CARD_BOTTLE = 80,
	CARD_NAME_Y = 106,
	CARD_NAME_TEXT = 15,
	SCROLLBAR_X = 1607,
	-- DISSOLVE and CANCEL at the right of YOUR POTIONS, 18 apart (an Operate button's reach at its press is 10), and
	-- the words left of them.
	DISSOLVE = Rect.new(1382, 506, 1592, 540),
	CANCEL = Rect.new(1234, 506, 1364, 540),
	ACTION_TEXT = 17,
	CARD_REFUND_Y = 136,
})

local Timing = table.freeze({
	SLOTS_DELAY = 0.04,
	SLOTS_STAGGER = 0.05,
	GRID_DELAY = 0.14,
	CARD_STAGGER = 0.025,
	RISE = 24,
	-- A potion put in or taken out of a slot: the slot's flash and punch.
	SLOTTED = 0.35,
	REFUSE = 0.4,
	REFUSE_SHAKE = 8,
	-- A dissolved card: flash, shrink and shake over this long before it is gone (init.luau keeps it this long).
	CRUNCH = 0.32,
	-- Picking starts or stops: the cards wobble once.
	TURN = 0.25,
})

local Potions = {}

Potions.CRUNCH = Timing.CRUNCH

local SLOT_WORDS = table.freeze({ "1ST SLOT", "2ND SLOT", "3RD SLOT" })

local function potionById(state: Types.TLabState, potionId: number): Types.TPotion?
	for _, potion in state.Potions() do
		if potion.Id == potionId then return potion end
	end
	return nil
end

local function shakeOf(state: Types.TLabState, who: string): () -> number
	return derive(function(): number
		if state.Refused() ~= who then return 0 end
		local at = state.RefusedAt()
		return Timing.REFUSE_SHAKE * Motion.Shake(Progress(state.Now(), at, Timing.REFUSE), at)
	end)
end

-- ============================== Slots ==============================

local function slot(state: Types.TLabState, actions: Types.TLabActions, index: number): TextButton
	local x = Parts.LEFT + (index - 1) * (Layout.SLOT_SIZE.X + Layout.SLOT_GAP)
	local dealt = Parts.Dealt(state, 2, Timing.SLOTS_DELAY + Timing.SLOTS_STAGGER * (index - 1))
	local info = derive(function()
		return state.Slots()[index]
	end)
	-- The potion in it: open slots take the equipped potions in order.
	local potion = derive(function(): Types.TPotion?
		local slotInfo = info()
		if not slotInfo or not slotInfo.IsOpen then return nil end
		local potionId = state.Equipped()[index]
		return if potionId then potionById(state, potionId) else nil
	end)
	local isOpen = derive(function(): boolean
		local slotInfo = info()
		return slotInfo ~= nil and slotInfo.IsOpen
	end)
	local kind = derive(function(): number
		local slotInfo = info()
		return if slotInfo then slotInfo.Kind else 1
	end)
	local canAct = derive(function(): boolean
		return potion() ~= nil or not isOpen()
	end)
	local hand = Hand.React("Operate", canAct)
	local accent = derive(function(): Color3
		local held = potion()
		if held then return Parts.Rarity(held.Rarity).Accent end
		if isOpen() then return Parts.LOCKED end
		return if kind() == 3 then Palette.Gold else Palette.Pink
	end)
	-- The flash and punch of a potion going in or out.
	local slotted = derive(function(): number
		local held = potion()
		local id = state.SlottedId()
		if id == 0 then return 1 end
		if held and held.Id ~= id then return 1 end
		return Progress(state.Now(), state.SlottedAt(), Timing.SLOTTED)
	end)
	local shake = shakeOf(state, `Slot{index}`)
	local gemsShort = derive(function(): boolean
		return state.Gems() < PotionsCore.GEM_SLOT_PRICE
	end)

	local title = derive(function(): string
		local held = potion()
		if held then return string.upper(DataCore.Potions.ById[held.Recipe].Name) end
		if isOpen() then return "EMPTY SLOT" end
		return `UNLOCK {SLOT_WORDS[index] or "SLOT"}`
	end)
	local lineOne = derive(function(): string
		local held = potion()
		if held then return Parts.EffectLines(DataCore.Potions.ById[held.Recipe], held.Rarity)[1] or "" end
		if isOpen() then return "Pick a potion below" end
		return if kind() == 3 then "Bought once, yours for good" else "With the Extra Potion Slot pass"
	end)
	local lineTwo = derive(function(): string
		local held = potion()
		if held then return Parts.EffectLines(DataCore.Potions.ById[held.Recipe], held.Rarity)[2] or "" end
		if isOpen() then return "to drink it next match" end
		return ""
	end)

	return Components.Button({
		Name = `Slot{index}`,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			return UDim2.fromOffset(
				x + Layout.SLOT_SIZE.X / 2 + math.round(shake()),
				Layout.SLOTS_Y + Layout.SLOT_SIZE.Y / 2 + math.round(Timing.RISE * (1 - dealt()))
			)
		end,
		Size = UDim2.fromOffset(Layout.SLOT_SIZE.X, Layout.SLOT_SIZE.Y),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Visible = function()
			return info() ~= nil
		end,
		Activated = function()
			local held = potion()
			if held then
				hand.Commit()
				actions.TogglePotion(held.Id)
			elseif not isOpen() then
				hand.Commit()
				actions.BuySlot(kind())
			end
		end,
		hand.Events,
		create("UIScale")({
			Scale = function()
				local punch = 0.06 * (1 - Motion.Decelerate(slotted()))
				return (0.92 + 0.08 * dealt()) * hand.Scale() * (1 + punch)
			end,
		}),
		Components.Card({
			Accent = accent,
			Tint = function()
				return if potion() or not isOpen() then 0.3 else 0.1
			end,
			Wide = true,
			Brackets = hand.Rise,
			GlowTransparency = function()
				return if potion() then 0.55 - 0.2 * hand.Light() else 0.8 - 0.2 * hand.Light()
			end,
		}, {
			Name = "Card",
			Size = UDim2.fromScale(1, 1),
			Hand.WashLayer(hand, 6, 2),
			create("Frame")({
				Name = "Flash",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Palette.White,
				BorderSizePixel = 0,
				ZIndex = 7,
				BackgroundTransparency = function()
					local t = Progress(slotted(), 0, 0.6)
					return if t >= 1 then 1 else 0.5 + 0.5 * t * t
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			}),
			Components.Picture(function()
				if potion() then return EIcons.PotionBottle end
				if isOpen() then return EIcons.PotionBottle end
				return if kind() == 3 then EIcons.Lock else EIcons.PotionRack
			end, {
				Name = "Picture",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(Layout.SLOT_BOTTLE.X, Layout.SLOT_BOTTLE.Y),
				Size = Components.PictureBox(Layout.SLOT_BOTTLE_SIZE),
				ImageColor3 = function()
					local held = potion()
					if held then return Parts.Rarity(held.Rarity).Accent end
					return if isOpen() then Parts.LOCKED else Palette.White
				end,
				ImageTransparency = function()
					return if isOpen() and not potion() then 0.5 else 0
				end,
				ZIndex = 3,
			}),
			Label({
				Name = "Corner",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -12, 0, 12),
				Size = UDim2.fromOffset(120, 13),
				FontFace = Font.DisplayBold,
				TextSize = 13,
				TextColor3 = Palette.Lavender,
				TextXAlignment = Enum.TextXAlignment.Right,
				Text = function()
					local held = potion()
					if held then return Parts.MatchesWord(held.Matches) end
					return SLOT_WORDS[index] or ""
				end,
			}),
			Label({
				Name = "Title",
				Position = UDim2.fromOffset(Layout.SLOT_TEXT_X, 30),
				Size = UDim2.fromOffset(Layout.SLOT_SIZE.X - Layout.SLOT_TEXT_X - 12, 22),
				TextSize = 22,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextColor3 = function()
					return if isOpen() and not potion() then Palette.Lavender else Palette.White
				end,
				Text = title,
			}),
			Label({
				Name = "LineOne",
				Position = UDim2.fromOffset(Layout.SLOT_TEXT_X, 60),
				Size = UDim2.fromOffset(Layout.SLOT_SIZE.X - Layout.SLOT_TEXT_X - 12, 16),
				FontFace = Font.DisplayBold,
				TextSize = 16,
				TextColor3 = function()
					return if potion() then Palette.White else Palette.Lavender
				end,
				Text = lineOne,
			}),
			Label({
				Name = "LineTwo",
				Position = UDim2.fromOffset(Layout.SLOT_TEXT_X, 82),
				Size = UDim2.fromOffset(Layout.SLOT_SIZE.X - Layout.SLOT_TEXT_X - 12, 16),
				FontFace = Font.DisplayBold,
				TextSize = 16,
				TextColor3 = function()
					return if potion() then Palette.White else Palette.Lavender
				end,
				Text = lineTwo,
			}),
			-- A closed slot's price: Gems, or the pass's Robux.
			create("Frame")({
				Name = "Price",
				Position = UDim2.fromOffset(Layout.SLOT_TEXT_X, 80),
				Size = UDim2.fromOffset(Layout.SLOT_SIZE.X - Layout.SLOT_TEXT_X - 12, 26),
				BackgroundTransparency = 1,
				ZIndex = 4,
				Visible = function()
					return not isOpen()
				end,
				create("UIListLayout")({
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 8),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
				Components.Picture(EIcons.Gem, {
					LayoutOrder = 1,
					Size = Components.PictureBox(26),
					Visible = function()
						return kind() == 3
					end,
				}),
				Components.Icon("Robux", {
					LayoutOrder = 1,
					Size = Components.GlyphBox(20),
					ImageColor3 = Palette.White,
					Visible = function()
						return kind() == 2
					end,
				}),
				Label({
					LayoutOrder = 2,
					AutomaticSize = Enum.AutomaticSize.X,
					Size = UDim2.fromOffset(0, 24),
					TextSize = 24,
					TextColor3 = function()
						if kind() == 2 then return Palette.White end
						return if gemsShort() then Palette.Lavender else Palette.Gold
					end,
					Text = function()
						if kind() == 2 then return Components.Commas(ShopCore.ByName.PotionSlot.Robux) end
						return Components.Commas(PotionsCore.GEM_SLOT_PRICE)
					end,
				}),
			}),
		}),
	}) :: TextButton
end

-- ============================== Grid ==============================

-- The souls a potion gives back, of every kind together.
local function refundOf(potion: Types.TPotion): number
	local total = 0
	for _, amount in PotionsCore.Refund(DataCore.Potions.ById[potion.Recipe], potion.Rarity) do
		total += amount
	end
	return total
end

-- The order the grid shows: the rarest first, the newest first among equals. Potions dissolving stay in their place
-- until they have crunched.
local function sorted(state: Types.TLabState): () -> { number }
	return derive(function(): { number }
		local list = table.clone(state.Potions())
		local held = {}
		for _, potion in list do
			held[potion.Id] = true
		end
		for potionId, leaving in state.Leaving() do
			if not held[potionId] then table.insert(list, leaving.Potion) end
		end
		table.sort(list, function(a, b)
			if a.Rarity ~= b.Rarity then return a.Rarity > b.Rarity end
			return a.Id > b.Id
		end)
		local ids = table.create(#list)
		for index, potion in list do
			ids[index] = potion.Id
		end
		return ids
	end)
end

local function potionCard(
	state: Types.TLabState,
	actions: Types.TLabActions,
	potionId: number,
	index: () -> number,
	window: () -> ScrollingFrame
)
	local potion = derive(function(): Types.TPotion?
		local leaving = state.Leaving()[potionId]
		if leaving then return leaving.Potion end
		return potionById(state, potionId)
	end)
	local isEquipped = derive(function(): boolean
		return table.find(state.Equipped(), potionId) ~= nil
	end)
	local hand = Hand.React("Take")
	local accent = derive(function(): Color3
		local held = potion()
		return if held then Parts.Rarity(held.Rarity).Accent else Parts.LOCKED
	end)
	-- Staggered by where it stood as it was built: a card that moves later does not deal again.
	local dealt = Parts.Dealt(state, 2, Timing.GRID_DELAY + Timing.CARD_STAGGER * math.min(vide.untrack(index) - 1, 14))
	-- Out of sight until its potion, still flying from the result card, has landed on the tab.
	local arrived = derive(function(): number
		for _, flight in state.Flights() do
			if flight.PotionId == potionId then return Progress(state.Now(), flight.LandAt, 0.3) end
		end
		return 1
	end)
	local shake = shakeOf(state, `Potion{potionId}`)
	local isPicking = derive(function(): boolean
		return state.IsDissolving() and not isEquipped()
	end)
	local isMarked = derive(function(): boolean
		return state.IsDissolving() and state.DissolvePicks()[potionId] == true
	end)
	-- 0 to 1 over its crunch once dissolved, nil while it is not going.
	local crunch = derive(function(): number?
		local leaving = state.Leaving()[potionId]
		if not leaving then return nil end
		return Progress(state.Now(), leaving.At, Timing.CRUNCH)
	end)
	-- A wobble as picking starts or stops.
	local turned = derive(function(): number
		if isEquipped() then return 1 end
		return Progress(state.Now(), state.DissolveAt(), Timing.TURN)
	end)
	local accentNow = function(): Color3
		if isMarked() then return Parts.DANGER end
		return accent()
	end
	-- Its middle in the scrolling window.
	local place = derive(function(): Vector2
		local at = index() - 1
		local column = at % Layout.COLUMNS
		local row = at // Layout.COLUMNS
		return Vector2.new(
			Layout.WINDOW_PAD + column * (Layout.CARD_SIZE.X + Layout.CARD_GAP) + Layout.CARD_SIZE.X / 2,
			Layout.WINDOW_PAD + row * (Layout.CARD_SIZE.Y + Layout.CARD_GAP) + Layout.CARD_SIZE.Y / 2
		)
	end)
	-- Where it stands on the screen, for its souls to leave from.
	state.Locate[potionId] = function(): Vector2?
		local frame = window()
		if not frame then return nil end
		return Vector2.new(Layout.WINDOW.Min.X, Layout.WINDOW.Min.Y) + vide.untrack(place) - frame.CanvasPosition
	end
	vide.cleanup(function()
		state.Locate[potionId] = nil
	end)

	return Components.Button({
		Name = `Potion{potionId}`,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			local at = place()
			local shaking = shake()
			local crunched = crunch()
			if crunched then
				shaking += 6 * Motion.Shake(crunched, potionId)
			end
			return UDim2.fromOffset(at.X + math.round(shaking), at.Y + math.round(Timing.RISE * (1 - dealt())))
		end,
		Size = UDim2.fromOffset(Layout.CARD_SIZE.X, Layout.CARD_SIZE.Y),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Activated = function()
			if crunch() then return end
			hand.Commit()
			actions.TogglePotion(potionId)
		end,
		hand.Events,
		create("UIScale")({
			Scale = function()
				local wobble = 0.05 * Motion.Bump(turned())
				local crunched = crunch()
				local squash = if crunched then 1 - 0.85 * Motion.Accelerate(crunched) else 1
				return (0.9 + 0.1 * dealt())
					* hand.Scale()
					* (0.6 + 0.4 * Motion.Decelerate(arrived()))
					* (1 - wobble)
					* squash
			end,
		}),
		Components.Card({
			Accent = accentNow,
			Tint = function()
				return if isMarked() then 0.45 else 0.3
			end,
			Brackets = hand.Rise,
			BracketsClosed = function()
				return isEquipped() or isMarked()
			end,
			GlowTransparency = function()
				if isMarked() then return 0.35 - 0.15 * hand.Light() end
				return if isEquipped() then 0.4 else 0.72 - 0.25 * hand.Light()
			end,
		}, {
			Name = "Card",
			Size = UDim2.fromScale(1, 1),
			Visible = function()
				return arrived() > 0 and crunch() ~= 1
			end,
			Hand.WashLayer(hand, 6, 2),
			-- The white a crunch flashes with.
			create("Frame")({
				Name = "Flash",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Palette.White,
				BorderSizePixel = 0,
				ZIndex = 8,
				BackgroundTransparency = function()
					local crunched = crunch()
					return if crunched then 0.2 + 0.8 * crunched else 1
				end,
				Visible = function()
					return crunch() ~= nil
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			}),
			-- Out of reach while picking: a potion in a slot is not dissolved.
			create("Frame")({
				Name = "Shade",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Color3.new(),
				BorderSizePixel = 0,
				BackgroundTransparency = 0.45,
				ZIndex = 7,
				Visible = function()
					return state.IsDissolving() and isEquipped()
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			}),
			Parts.Tag(
				function()
					local held = potion()
					return if held then Parts.Rarity(held.Rarity).Text else ""
				end,
				accent,
				function()
					local held = potion()
					return held ~= nil and Parts.Rarity(held.Rarity).IsInk
				end,
				12,
				{
					Position = UDim2.fromOffset(9, 9),
					Size = UDim2.fromOffset(0, 20),
				},
				8
			),
			Components.Picture(EIcons.PotionBottle, {
				Name = "Bottle",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(Layout.CARD_SIZE.X / 2, Layout.CARD_BOTTLE_Y),
				Size = Components.PictureBox(Layout.CARD_BOTTLE),
				ImageColor3 = accent,
				ZIndex = 3,
				create("UIScale")({
					Scale = function()
						return 1 + 0.12 * hand.Rise()
					end,
				}),
			}),
			-- What it gives back, while picking.
			create("Frame")({
				Name = "Refund",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromOffset(Layout.CARD_SIZE.X / 2, Layout.CARD_REFUND_Y),
				Size = UDim2.fromOffset(Layout.CARD_SIZE.X - 14, 16),
				BackgroundTransparency = 1,
				ZIndex = 4,
				Visible = isPicking,
				create("UIListLayout")({
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 4),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
				Components.Picture(EIcons.Soul, {
					LayoutOrder = 1,
					Size = Components.PictureBox(16),
				}),
				Label({
					LayoutOrder = 2,
					AutomaticSize = Enum.AutomaticSize.X,
					Size = UDim2.fromOffset(0, 14),
					FontFace = Font.DisplayBold,
					TextSize = 14,
					TextColor3 = Palette.Gold,
					Text = function()
						local held = potion()
						return if held then `+{refundOf(held)} SOULS` else ""
					end,
				}),
			}),
			Label({
				Name = "Name",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromOffset(Layout.CARD_SIZE.X / 2, Layout.CARD_NAME_Y),
				Size = UDim2.fromOffset(Layout.CARD_SIZE.X - 14, Layout.CARD_NAME_TEXT * 2 + 2),
				TextSize = Layout.CARD_NAME_TEXT,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Center,
				Text = function()
					local held = potion()
					return if held then string.upper(DataCore.Potions.ById[held.Recipe].Name) else ""
				end,
			}),
			Label({
				Name = "Matches",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -10, 0, 12),
				Size = UDim2.fromOffset(40, 14),
				FontFace = Font.DisplayBold,
				TextSize = 14,
				TextColor3 = Palette.Gold,
				TextXAlignment = Enum.TextXAlignment.Right,
				Text = function()
					local held = potion()
					return if held and held.Matches > 1 then `x{held.Matches}` else ""
				end,
				Visible = function()
					return not isEquipped() and not isMarked()
				end,
			}),
			-- His check box on a potion in a slot, red on one picked to dissolve.
			create("Frame")({
				Name = "Check",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -9, 0, 9),
				Size = UDim2.fromOffset(24, 24),
				BackgroundColor3 = Palette.Ink,
				BorderSizePixel = 0,
				ZIndex = 6,
				Visible = function()
					return isEquipped() or isMarked()
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
				create("UIStroke")({
					Color = function()
						return if isMarked() then Parts.DANGER else Palette.Green
					end,
					Thickness = 2,
				}),
				Components.Picture(EIcons.Check, {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = Components.PictureBox(18),
					ImageColor3 = function()
						return if isMarked() then Parts.DANGER else Palette.Green
					end,
				}),
			}),
		}),
	}) :: TextButton
end

local function grid(state: Types.TLabState, actions: Types.TLabActions, shown: () -> number): Frame
	local ids = sorted(state)
	local rect = Layout.WINDOW
	-- The cards read it for where they stand; it is made with them.
	local window: ScrollingFrame
	window = create("ScrollingFrame")({
		Name = "Window",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 0,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ElasticBehavior = Enum.ElasticBehavior.Never,
		CanvasSize = function()
			local rows = math.max(math.ceil(#ids() / Layout.COLUMNS), 1)
			local height = rows * Layout.CARD_SIZE.Y + (rows - 1) * Layout.CARD_GAP + 2 * Layout.WINDOW_PAD
			return UDim2.fromOffset(0, height)
		end,
		ZIndex = 3,
		vide.values(ids, function(potionId: number, index: () -> number)
			return potionCard(state, actions, potionId, index, function()
				return window
			end)
		end),
	})

	-- It grows down into the room the panel's rise makes, its top staying with the panel's.
	return create("Frame")({
		Name = "Grid",
		Position = UDim2.fromOffset(rect.Min.X, rect.Min.Y),
		Size = function()
			return UDim2.fromOffset(rect.Width, rect.Height + Parts.Lift())
		end,
		BackgroundTransparency = 1,
		ZIndex = 3,
		window,
		Scrollbar.Build(window, {
			Length = function(): number
				return rect.Height + Parts.Lift() - 2 * Layout.WINDOW_PAD
			end,
			Shown = shown,
		}, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(Layout.SCROLLBAR_X - rect.Min.X, Layout.WINDOW_PAD),
			ZIndex = 4,
		}),
		Label({
			Name = "Empty",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.4),
			Size = UDim2.fromOffset(rect.Width, 22),
			TextSize = 22,
			TextColor3 = Palette.Lavender,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = "NO POTIONS YET: BREW ONE ON THE MUTATE PAGE",
			Visible = function()
				return #ids() == 0
			end,
		}),
	})
end

-- One of the small slabs at the right of YOUR POTIONS: its word, its kind, whether it can be pressed, and its press.
local function action(
	rect: Rect,
	word: () -> string,
	kind: () -> string,
	isLive: () -> boolean,
	isShown: () -> boolean,
	header: () -> number,
	press: () -> ()
): TextButton
	local hand = Hand.React("Operate", isLive)

	return Components.Button({
		Name = "Action",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			return UDim2.fromOffset(
				rect.Min.X + rect.Width / 2,
				rect.Min.Y + rect.Height / 2 + math.round(12 * (1 - header()))
			)
		end,
		Size = UDim2.fromOffset(rect.Width, rect.Height),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Visible = isShown,
		Activated = function()
			hand.Commit()
			press()
		end,
		hand.Events,
		create("UIScale")({ Scale = hand.Scale }),
		Components.Slab({
			Kind = kind,
			Brackets = hand.Rise,
			GlowTransparency = function()
				return if isLive() then 0.6 - 0.3 * hand.Light() else 0.85
			end,
		}, {
			Name = "Slab",
			Size = UDim2.fromScale(1, 1),
			Hand.WashLayer(hand, 3, 3),
			Components.Sheen(hand.Glint, 3, rect.Width / rect.Height),
			create("Frame")({
				Name = "Row",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ZIndex = 4,
				create("UIListLayout")({
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 6),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
				Components.Picture(EIcons.Soul, {
					LayoutOrder = 1,
					Size = Components.PictureBox(20),
					Visible = function()
						return kind() ~= "Steel"
					end,
				}),
				Label({
					LayoutOrder = 2,
					AutomaticSize = Enum.AutomaticSize.X,
					Size = UDim2.fromOffset(0, Layout.ACTION_TEXT),
					TextSize = Layout.ACTION_TEXT,
					TextColor3 = function()
						return if isLive() then Palette.White else Palette.Lavender
					end,
					Text = word,
				}),
			}),
		}),
	}) :: TextButton
end

-- What the picked potions give back, all together.
local function pickedRefund(state: Types.TLabState): number
	local total = 0
	local picks = state.DissolvePicks()
	for _, potion in state.Potions() do
		if picks[potion.Id] then
			total += refundOf(potion)
		end
	end
	return total
end

function Potions.Build(state: Types.TLabState, actions: Types.TLabActions, shown: () -> number): { any }
	local header = Parts.Dealt(state, 2, 0)
	local picked = derive(function(): number
		local count = 0
		for _ in state.DissolvePicks() do
			count += 1
		end
		return count
	end)
	local info = derive(function(): string
		if state.IsDissolving() then
			if picked() == 0 then return "PICK POTIONS TO DISSOLVE" end
			return `+{pickedRefund(state)} SOULS BACK`
		end
		local count = #state.Potions()
		return if count == 1 then "1 POTION" else `{count} POTIONS`
	end)

	return {
		Parts.Header("POTION SLOTS", "DRUNK AS YOUR NEXT MATCH STARTS", Layout.SLOTS_HEADER_Y, EIcons.Flask, nil, {
			Position = function()
				return UDim2.fromOffset(Parts.LEFT, Layout.SLOTS_HEADER_Y + math.round(12 * (1 - header())))
			end,
		}),
		slot(state, actions, 1),
		slot(state, actions, 2),
		slot(state, actions, 3),
		Parts.Header("YOUR POTIONS", "", Layout.GRID_HEADER_Y, EIcons.PotionBottle, Palette.Gold, {
			Position = function()
				return UDim2.fromOffset(Parts.LEFT, Layout.GRID_HEADER_Y + math.round(12 * (1 - header())))
			end,
		}),
		Label({
			Name = "Info",
			AnchorPoint = Vector2.new(1, 0),
			Position = function()
				local right = if state.IsDissolving() then Layout.CANCEL.Min.X else Layout.DISSOLVE.Min.X
				return UDim2.fromOffset(right - 20, Layout.GRID_HEADER_Y + 6 + math.round(12 * (1 - header())))
			end,
			Size = UDim2.fromOffset(500, 17),
			FontFace = Font.DisplayBold,
			TextSize = 17,
			TextColor3 = Palette.Gold,
			TextXAlignment = Enum.TextXAlignment.Right,
			Text = info,
		}),
		action(Layout.CANCEL, function()
			return "CANCEL"
		end, function()
			return "Steel"
		end, function()
			return true
		end, state.IsDissolving, header, actions.CancelDissolve),
		action(Layout.DISSOLVE, function()
			if not state.IsDissolving() then return "DISSOLVE" end
			return if picked() == 0 then "DISSOLVE" else `DISSOLVE {picked()}`
		end, function()
			if not state.IsDissolving() then return "Violet" end
			return if picked() > 0 then "Red" else "Off"
		end, function()
			return not state.IsDissolving() or picked() > 0
		end, function()
			return #state.Potions() > 0 or state.IsDissolving()
		end, header, actions.Dissolve),
		grid(state, actions, shown),
	}
end

return Potions
