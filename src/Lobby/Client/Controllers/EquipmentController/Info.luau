--!nonstrict
-- The equipment page's info panel (his right panel, Item Info Container): the picked piece's slot, its own model on his
-- preview card with its rarity tag, its name and ?, what it adds counting up on his stat rows, its words, SHOW ON
-- CHARACTER (Settings' switch), and his slab: EQUIP, EQUIPPED (UNEQUIP? under the hand) or, for a piece not got yet,
-- who drops it. The ? opens where the piece comes from over the rows; pressing the slab of a piece not got opens it too.
-- A pick deals the details in again.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local Controls = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.SettingsUI.Controls)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
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
local PIECES = DataCore.Equipment.ById

-- His drawn rects in px at 1080, from the panel's top left (his panel is the classes info panel's; its right edge is
-- RIGHT from the screen's).
local Layout = table.freeze({
	RIGHT = 40,
	TOP = 190,
	SIZE = Vector2.new(440, 850),
	-- Kept inside the 1024 px texture at the panel's grown height (up to about 940 under the top bar).
	TEXTURE = Vector2.new(380, 80),
	BRACKET_LENGTH = 24,
	-- The header: the glyph's middle and longer side, the slot, the rule.
	HEADER_GLYPH = Vector2.new(35, 39),
	HEADER_GLYPH_SIZE = 20,
	HEADER_TITLE = Vector2.new(56, 24),
	HEADER_TEXT = 29,
	RULE = Vector2.new(24, 64),
	RULE_WIDTH = 392,
	-- His preview card, its picture's box and the rarity tag in its corner.
	PREVIEW = Vector2.new(24, 88),
	PREVIEW_SIZE = Vector2.new(392, 240),
	PREVIEW_PICTURE = 210,
	TAG = Vector2.new(12, 199),
	TAG_SIZE = Vector2.new(104, 28),
	TAG_TEXT = 15,
	-- The name and the ?.
	NAME = Vector2.new(24, 350),
	NAME_TEXT = 40,
	HELP = Vector2.new(376, 352),
	HELP_SIZE = 40,
	HELP_TEXT = 26,
	-- His stat rows: the first's top, the step to the next, the size; inside, the number's corner and the words after it.
	STAT_X = 24,
	STAT_TOP = 410,
	STAT_STEP = 76,
	STAT_SIZE = Vector2.new(392, 64),
	STAT_VALUE = Vector2.new(18, 16),
	STAT_VALUE_TEXT = 32,
	STAT_GAP = 14,
	STAT_LABEL_TEXT = 22,
	-- The words under the rows: 20 below the last.
	DESCRIPTION_GAP = 20,
	DESCRIPTION_WIDTH = 392,
	DESCRIPTION_TEXT = 19,
	-- Where the piece comes from, opened by the ?, over the rows.
	WHERE = Vector2.new(24, 404),
	WHERE_TEXT = 26,
	WHERE_PAD = 22,
	-- SHOW ON CHARACTER's row, its word, and the switch's middle.
	TOGGLE = Vector2.new(24, 656),
	TOGGLE_SIZE = Vector2.new(392, 72),
	TOGGLE_WORD = Vector2.new(18, 26),
	TOGGLE_TEXT = 20,
	SWITCH = Vector2.new(337, 36),
	-- His slab, its check's middle and longer side, and its words.
	SLAB = Vector2.new(22, 749),
	SLAB_SIZE = Vector2.new(394, 78),
	CHECK = Vector2.new(106, 39),
	CHECK_GLYPH = 31,
	SLAB_TEXT = 35,
	SLAB_TEXT_LEFT = 135,
	SOURCE_GLYPH = 34,
	SOURCE_TEXT = 30,
	SOURCE_GAP = 12,
})

-- His row's edge and face (the classes stat rows'), and a row's dim while its piece is not got.
local Colors = table.freeze({
	ROW_EDGE = Color3.fromRGB(67, 53, 106),
	ROW_FACE = Color3.fromRGB(29, 23, 52),
	OFF_TRANSPARENCY = 0.55,
})

-- Seconds after the page comes up (or a piece is picked): when each detail starts in and how long it takes.
local Timing = table.freeze({
	DETAILS = 0.12,
	IN = 0.42,
	HEADER = 0,
	PREVIEW = 0.04,
	TAG = 0.18,
	TAG_IN = 0.3,
	TAG_STAMP = 0.6,
	NAME = 0.08,
	NAME_FROM = 18,
	STATS = 0.14,
	STAT_STEP = 0.06,
	COUNT_DELAY = 0.08,
	COUNT = 0.45,
	DESCRIPTION = 0.22,
	TOGGLE = 0.26,
	SLAB = 0.3,
	DETAIL_FROM = 26,
	-- A pick swings the preview's model and pops it.
	PICK_SWING = 22,
	PICK_POP = 0.16,
	PICK = 0.55,
	-- The preview's model sways this far each way (deg) every SWAY seconds while the page is up.
	SWAY_DEG = 22,
	SWAY = 6,
	-- The ?'s word comes and goes this fast.
	HELP = 0.14,
	-- A piece put on: the slab flashes and its check is struck in from big; a refusal shakes the slab this far.
	FLASH = 0.35,
	CHECK_FROM = 1.8,
	CHECK = 0.32,
	JOLT = 8,
	JOLT_SECONDS = 0.3,
	-- The slab's words trade places under the hand (EQUIPPED for UNEQUIP?).
	SWAP = 0.12,
})

local Info = {}

local function rowFace(props: { [any]: any }): Frame
	return create("Frame")({
		BackgroundColor3 = Colors.ROW_EDGE,
		BorderSizePixel = 0,
		ZIndex = 4,
		create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
		create("Frame")({
			Name = "Face",
			Position = UDim2.fromOffset(1, 1),
			Size = UDim2.new(1, -2, 1, -2),
			BackgroundColor3 = Colors.ROW_FACE,
			BorderSizePixel = 0,
			create("UICorner")({ CornerRadius = UDim.new(0, 1) }),
		}),
		props,
	})
end

-- The header: the picked piece's slot.
local function header(state: Types.TEquipmentState, item: () -> any): { Instance }
	local named = Parts.Dealt(state, Timing.HEADER, Timing.IN, state.SelectedAt)
	return {
		Components.Picture(EIcons.Star, {
			Name = "Glyph",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(Layout.HEADER_GLYPH.X, Layout.HEADER_GLYPH.Y),
			Size = Components.PictureBox(Layout.HEADER_GLYPH_SIZE),
			ImageTransparency = function()
				return 1 - Motion.Out(named())
			end,
			ZIndex = 4,
		}),
		Label({
			Name = "Slot",
			Position = function()
				return UDim2.fromOffset(
					Layout.HEADER_TITLE.X + math.round(14 * (1 - Motion.Decelerate(named()))),
					Layout.HEADER_TITLE.Y
				)
			end,
			Size = UDim2.fromOffset(240, Layout.HEADER_TEXT),
			TextSize = Layout.HEADER_TEXT,
			TextTransparency = function()
				return 1 - Motion.Out(named())
			end,
			Text = function()
				local current = item()
				return if current then string.upper(current.Slot) else ""
			end,
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
	}
end

-- His preview card: the piece's model swaying on it, swung in on each pick, and its rarity's tag stamped down.
local function preview(state: Types.TEquipmentState, item: () -> any, sway: () -> number): Frame
	local dealt = Parts.Dealt(state, Timing.PREVIEW, Timing.IN)
	local picked = Parts.Dealt(state, Timing.PREVIEW, Timing.PICK, state.SelectedAt)
	local tagged = Parts.Dealt(state, Timing.TAG, Timing.TAG_IN, state.SelectedAt)
	local rarity = derive(function()
		local current = item()
		return Parts.RARITIES[if current then current.Rarity else "Common"]
	end)
	local isOwned = derive(function(): boolean
		local current = item()
		return current ~= nil and state.Owned()[current.Id] == true
	end)

	return Components.Card({
		Accent = function()
			return Parts.EdgeOf(rarity().Accent)
		end,
		Glow = function()
			return rarity().Accent
		end,
		GlowTransparency = 0.75,
		Tint = 0.3,
		Marks = true,
		Brackets = true,
		BracketLength = 22,
	}, {
		Name = "Preview",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(
			Layout.PREVIEW.X + Layout.PREVIEW_SIZE.X / 2,
			Layout.PREVIEW.Y + Layout.PREVIEW_SIZE.Y / 2
		),
		Size = UDim2.fromOffset(Layout.PREVIEW_SIZE.X, Layout.PREVIEW_SIZE.Y),
		ZIndex = 3,
		create("UIScale")({
			Scale = function()
				return Motion.Decelerate(dealt())
			end,
		}),
		Parts.Picture(function()
			local current = item()
			return if current then current.Id else 0
		end, {
			Tint = function()
				return if isOwned() then Palette.White else Parts.LOCKED_TINT
			end,
			Yaw = function()
				return Timing.SWAY_DEG * math.sin(2 * math.pi * sway() / Timing.SWAY)
					+ Timing.PICK_SWING * Motion.Swing(picked())
			end,
		}, {
			Name = "Picture",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.48),
			Size = UDim2.fromOffset(Layout.PREVIEW_PICTURE, Layout.PREVIEW_PICTURE),
			ZIndex = 4,
			create("UIScale")({
				Scale = function()
					return Motion.Decelerate(picked()) * (1 + Timing.PICK_POP * Motion.Bump(picked()))
				end,
			}),
		}),
		create("Frame")({
			Name = "Tag",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(Layout.TAG.X + Layout.TAG_SIZE.X / 2, Layout.TAG.Y + Layout.TAG_SIZE.Y / 2),
			Size = UDim2.fromOffset(Layout.TAG_SIZE.X, Layout.TAG_SIZE.Y),
			BackgroundColor3 = function()
				return rarity().Accent
			end,
			BackgroundTransparency = function()
				return 1 - Motion.Out(tagged())
			end,
			BorderSizePixel = 0,
			ZIndex = 5,
			create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			create("UIScale")({
				Scale = function()
					return 1 + Timing.TAG_STAMP * (1 - Motion.Decelerate(tagged()))
				end,
			}),
			Label({
				Size = UDim2.fromScale(1, 1),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextSize = Layout.TAG_TEXT,
				TextColor3 = function()
					return if rarity().IsInk then Palette.Ink else Palette.White
				end,
				TextTransparency = function()
					return 1 - Motion.Out(tagged())
				end,
				Text = function()
					return rarity().Text
				end,
			}),
		}),
	})
end

-- One of the piece's stat rows, unrolling from its left end, its number counting up.
local function statRow(state: Types.TEquipmentState, item: () -> any, index: number): Frame
	local delay = Timing.STATS + Timing.STAT_STEP * (index - 1)
	local unrolled = Parts.Dealt(state, delay, Timing.IN, state.SelectedAt)
	local counted = Parts.Dealt(state, delay + Timing.COUNT_DELAY, Timing.COUNT, state.SelectedAt)
	local bonus = derive(function()
		local current = item()
		return if current then current.Stats[index] else nil
	end)
	-- Derived, so the count writes its text only when the number it shows moves on.
	local number = derive(function(): string
		local current = bonus()
		if not current then return "" end
		local t = counted()
		-- The number only (StatText's first return), counted on an ease-out.
		return (EquipmentCore.StatText({ Stat = current.Stat, Value = current.Value * (1 - (1 - t) * (1 - t)) }))
	end)
	local words = derive(function(): string
		local current = bonus()
		if not current then return "" end
		local _, text = EquipmentCore.StatText(current)
		return text
	end)

	return rowFace({
		Name = `Stat{index}`,
		Position = UDim2.fromOffset(Layout.STAT_X, Layout.STAT_TOP + Layout.STAT_STEP * (index - 1)),
		Size = function()
			return UDim2.fromOffset(math.round(Layout.STAT_SIZE.X * Motion.Decelerate(unrolled())), Layout.STAT_SIZE.Y)
		end,
		Visible = function()
			return bonus() ~= nil
		end,
		ClipsDescendants = true,
		create("Frame")({
			Name = "Line",
			Position = UDim2.fromOffset(Layout.STAT_VALUE.X, Layout.STAT_VALUE.Y),
			Size = UDim2.fromOffset(Layout.STAT_SIZE.X - 2 * Layout.STAT_VALUE.X, Layout.STAT_VALUE_TEXT),
			BackgroundTransparency = 1,
			ZIndex = 2,
			create("UIListLayout")({
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, Layout.STAT_GAP),
			}),
			Label({
				Name = "Value",
				LayoutOrder = 1,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, Layout.STAT_VALUE_TEXT),
				TextSize = Layout.STAT_VALUE_TEXT,
				TextColor3 = Palette.Green,
				Text = number,
			}),
			Label({
				Name = "Words",
				LayoutOrder = 2,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, Layout.STAT_LABEL_TEXT),
				FontFace = Font.DisplayBold,
				TextSize = Layout.STAT_LABEL_TEXT,
				TextTransparency = function()
					return 1 - Motion.Out(unrolled())
				end,
				Text = words,
			}),
		}),
	})
end

-- The ? and where the piece comes from, which it opens over the rows: grown down from the middle of its top edge.
local function help(
	state: Types.TEquipmentState,
	actions: Types.TEquipmentActions,
	item: () -> any,
	opened: () -> number
): { Instance }
	local hand = Hand.React("Operate")
	local dealt = Parts.Dealt(state, Timing.NAME, Timing.IN)
	local isOpenShown = derive(function(): boolean
		return opened() > 0.01
	end)
	local texts = {}
	for _, piece in EquipmentCore.All do
		texts[piece.Id] = EquipmentCore.WhereFrom(piece)
	end
	local textBounds =
		Parts.TextBounds(texts, Font.DisplayBold, Layout.WHERE_TEXT, Layout.DESCRIPTION_WIDTH - 2 * Layout.WHERE_PAD)

	return {
		Components.Button({
			Name = "Help",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(Layout.HELP.X + Layout.HELP_SIZE / 2, Layout.HELP.Y + Layout.HELP_SIZE / 2),
			Size = UDim2.fromOffset(Layout.HELP_SIZE, Layout.HELP_SIZE),
			BackgroundTransparency = 1,
			ZIndex = 5,
			Activated = function()
				hand.Commit()
				actions.ToggleHelp()
			end,
			hand.Events,
			Components.Plaque({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(1, 1),
				create("UIScale")({
					Scale = function()
						return Motion.Decelerate(dealt()) * hand.Scale()
					end,
				}),
				create("TextLabel")({
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					FontFace = Font.Display,
					TextSize = Layout.HELP_TEXT,
					TextColor3 = Palette.Green,
					Text = "?",
					ZIndex = 2,
				}),
			}),
		}),
		Components.Panel({ Glow = Palette.Green, GlowTransparency = 0.6, Stroke = Palette.Green }, {
			Name = "Where",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(Layout.WHERE.X + Layout.DESCRIPTION_WIDTH / 2, Layout.WHERE.Y),
			Size = function()
				local current = item()
				local bounds = if current then textBounds()[current.Id] else nil
				local textHeight = if bounds then bounds.Y else Layout.WHERE_TEXT
				return UDim2.fromOffset(Layout.DESCRIPTION_WIDTH, textHeight + 2 * Layout.WHERE_PAD)
			end,
			Visible = isOpenShown,
			ZIndex = 6,
			create("UIScale")({ Scale = opened }),
			Label({
				Position = UDim2.fromOffset(Layout.WHERE_PAD, Layout.WHERE_PAD),
				Size = UDim2.new(1, -2 * Layout.WHERE_PAD, 1, -2 * Layout.WHERE_PAD),
				TextXAlignment = Enum.TextXAlignment.Center,
				FontFace = Font.DisplayBold,
				TextSize = Layout.WHERE_TEXT,
				TextWrapped = true,
				TextTransparency = function()
					return 1 - opened()
				end,
				Text = function()
					local current = item()
					return if current then EquipmentCore.WhereFrom(current) else ""
				end,
				ZIndex = 2,
			}),
		}),
	}
end

-- SHOW ON CHARACTER: his row with Settings' switch, dim for a piece not got.
local function toggle(state: Types.TEquipmentState, actions: Types.TEquipmentActions, item: () -> any): Frame
	local dealt = Parts.Dealt(state, Timing.TOGGLE, Timing.IN)
	local isOwned = derive(function(): boolean
		local current = item()
		return current ~= nil and state.Owned()[current.Id] == true
	end)
	local row = {
		IsOn = function(): boolean
			local current = item()
			return current ~= nil and not state.Hidden()[current.Id]
		end,
		ChangedAt = function(): number
			return if state.Change() == "Show" then state.ChangedAt() else -math.huge
		end,
	}

	return rowFace({
		Name = "Show",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = function()
			return UDim2.fromOffset(
				Layout.TOGGLE.X,
				Layout.TOGGLE.Y
					+ Layout.TOGGLE_SIZE.Y / 2
					+ math.round(Timing.DETAIL_FROM * (1 - Motion.Decelerate(dealt())))
			)
		end,
		Size = UDim2.fromOffset(Layout.TOGGLE_SIZE.X, Layout.TOGGLE_SIZE.Y),
		-- It grows from its left end as it comes in, as a stat row unrolls.
		create("UIScale")({
			Scale = function()
				return Motion.Decelerate(dealt())
			end,
		}),
		Label({
			Name = "Word",
			Position = UDim2.fromOffset(Layout.TOGGLE_WORD.X, Layout.TOGGLE_WORD.Y),
			Size = UDim2.fromOffset(260, Layout.TOGGLE_TEXT),
			TextSize = Layout.TOGGLE_TEXT,
			TextTransparency = function()
				return if isOwned() then 0 else Colors.OFF_TRANSPARENCY
			end,
			Text = "SHOW ON CHARACTER",
			ZIndex = 2,
		}),
		Controls.Switch({ Now = state.Now }, row, {
			SetToggle = function()
				actions.ToggleShown()
			end,
		}, {
			Position = UDim2.fromOffset(Layout.SWITCH.X, Layout.SWITCH.Y),
			ZIndex = 3,
		}),
	})
end

-- His slab's words for each state: EQUIP, EQUIPPED (UNEQUIP? under the hand), or who drops a piece not got.
local function slabWords(state: Types.TEquipmentState, item: () -> any, hand: Hand.TReaction): { Instance }
	local isOwned = derive(function(): boolean
		local current = item()
		return current ~= nil and state.Owned()[current.Id] == true
	end)
	local isWorn = derive(function(): boolean
		local current = item()
		return current ~= nil and state.Equipped()[current.Slot] == current.Id
	end)
	-- 1 while the hand is on an EQUIPPED slab: its words become UNEQUIP?.
	local asking = Hand.Spring(function(): number
		return if isWorn() and hand.IsHovered() then 1 else 0
	end, Timing.SWAP)
	local checked = derive(function(): number
		local current = item()
		if not current or state.ChangedItem() ~= current.Id or state.Change() ~= "Equip" then return 1 end
		return Progress(state.Now(), state.ChangedAt(), Timing.CHECK)
	end)
	-- Tracked reads Color and TextTransparency off its props, so they are laid flat in them, not nested.
	local function word(text: string, props: { [any]: any }): Frame
		local flat = table.clone(props)
		flat.AnchorPoint = Vector2.new(0.5, 0.5)
		flat.Position = UDim2.fromScale(0.5, 0.5)
		return Components.Tracked(text, Layout.SLAB_TEXT, 0, Font.Display, flat)
	end

	return {
		-- EQUIPPED, its check struck in from big as the piece goes on.
		create("Frame")({
			Name = "Equipped",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Visible = function()
				return isWorn() and asking() < 0.99
			end,
			ZIndex = 4,
			Components.Picture(EIcons.Check, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(Layout.CHECK.X, Layout.CHECK.Y),
				Size = Components.PictureBox(Layout.CHECK_GLYPH),
				ImageTransparency = asking,
				ZIndex = 4,
				create("UIScale")({
					Scale = function()
						return 1 + (Timing.CHECK_FROM - 1) * (1 - Motion.Decelerate(checked()))
					end,
				}),
			}),
			Components.Tracked("EQUIPPED", Layout.SLAB_TEXT, 0, Font.Display, {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, Layout.SLAB_TEXT_LEFT, 0.5, 0),
				TextTransparency = asking,
			}),
		}),
		word("UNEQUIP?", {
			Name = "Unequip",
			TextTransparency = function()
				return 1 - asking()
			end,
			Visible = function()
				return isWorn() and asking() > 0.01
			end,
		}),
		word("EQUIP", {
			Name = "Equip",
			Visible = function()
				return isOwned() and not isWorn()
			end,
		}),
		-- Who drops a piece not got: the boss's face and name, or LOCKED for one nothing drops yet.
		create("Frame")({
			Name = "Source",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Visible = function()
				return item() ~= nil and not isOwned()
			end,
			ZIndex = 4,
			create("UIListLayout")({
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, Layout.SOURCE_GAP),
			}),
			Components.Picture(function()
				local current = item()
				return if current and EquipmentCore.SourceOf(current) then EIcons.ZombieKing else EIcons.Lock
			end, {
				LayoutOrder = 1,
				Size = Components.PictureBox(Layout.SOURCE_GLYPH),
				ZIndex = 4,
			}),
			Label({
				LayoutOrder = 2,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, Layout.SOURCE_TEXT),
				TextSize = Layout.SOURCE_TEXT,
				TextColor3 = Palette.Lavender,
				Text = function()
					local current = item()
					return if current then EquipmentCore.SourceOf(current) or "LOCKED" else ""
				end,
			}),
		}),
	}
end

-- His slab at the panel's foot: green for EQUIP and EQUIPPED, his dim slab for a piece not got. It flashes as a piece
-- goes on and shakes its head at a refusal.
local function slab(state: Types.TEquipmentState, actions: Types.TEquipmentActions, item: () -> any): TextButton
	local dealt = Parts.Dealt(state, Timing.SLAB, Timing.IN)
	local landed = Parts.Landing(state, Timing.SLAB)
	local isOwned = derive(function(): boolean
		local current = item()
		return current ~= nil and state.Owned()[current.Id] == true
	end)
	local hand = Hand.React("Operate", isOwned)
	local flash = derive(function(): number
		local current = item()
		if not current or state.ChangedItem() ~= current.Id or state.Change() ~= "Equip" then return 0 end
		return Motion.Fade(state.Now(), state.ChangedAt(), Timing.FLASH)
	end)
	-- In whole px, so it is written only while it shakes.
	local jolt = derive(function(): number
		local at = state.RefusedAt()
		return math.round(Timing.JOLT * Motion.Shake(Progress(state.Now(), at, Timing.JOLT_SECONDS), at))
	end)
	local size = Layout.SLAB_SIZE

	return Components.Button({
		Name = "Slab",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			return UDim2.fromOffset(
				Layout.SLAB.X + size.X / 2 + jolt(),
				Layout.SLAB.Y + size.Y / 2 + math.round(Timing.DETAIL_FROM * (1 - Motion.Decelerate(dealt())))
			)
		end,
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Activated = function()
			hand.Commit()
			actions.Press()
		end,
		hand.Events,
		create("UIScale")({
			Scale = function()
				return Motion.Decelerate(dealt()) * hand.Scale()
			end,
		}),
		Components.Slab({
			Kind = function()
				return if isOwned() then "Go" else "Off"
			end,
			Marks = true,
			Brackets = true,
		}, {
			Name = "Face",
			Size = UDim2.fromScale(1, 1),
			Hand.WashLayer(hand, 3, 3),
			Components.Sheen(Hand.Sheen(hand, landed), 3),
			slabWords(state, item, hand),
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
					return 1 - 0.8 * flash() * flash()
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
			}),
		}),
	}) :: TextButton
end

-- `sway` is seconds the page has been up, read by the preview's model only.
function Info.Build(state: Types.TEquipmentState, actions: Types.TEquipmentActions, sway: () -> number): Frame
	local away = Parts.Away(state)
	local landed = Parts.Landing(state, Timing.HEADER)
	local item = derive(function()
		return PIECES[state.Selected()]
	end)
	local maxStats = 0
	local descriptions = {}
	for _, piece in EquipmentCore.All do
		maxStats = math.max(maxStats, #piece.Stats)
		descriptions[piece.Id] = piece.Description
	end
	local named = Parts.Dealt(state, Timing.NAME, Timing.IN, state.SelectedAt)
	local described = Parts.Dealt(state, Timing.DESCRIPTION, Timing.IN, state.SelectedAt)
	-- 0 to 1 as where the piece comes from opens over the rows; the words under them make way for it.
	local helpOpened = Hand.Spring(function()
		return if state.IsHelpOpen() then 1 else 0
	end, Timing.HELP)
	local rows = table.create(maxStats)
	for index = 1, maxStats do
		rows[index] = statRow(state, item, index)
	end
	-- Raised to just under the top bar, its bottom staying put: what is written on it rides up with the top, and the
	-- show switch and the slab keep their place.
	local lift = panelTop.Lift(Layout.TOP)

	return create("Frame")({
		Name = "Info",
		BackgroundTransparency = 1,
		Visible = Parts.ArePanelsUp(state),
		AnchorPoint = Vector2.new(1, 0),
		Position = function()
			return UDim2.new(1, -Layout.RIGHT + math.round(Parts.Timing.SIDE_TRAVEL * away()), 0, Layout.TOP - lift())
		end,
		Size = function()
			return UDim2.fromOffset(Layout.SIZE.X, Layout.SIZE.Y + lift())
		end,
		ZIndex = 4,
		Components.Panel({
			Tall = true,
			Brackets = true,
			BracketLength = Layout.BRACKET_LENGTH,
			TexturePhase = Layout.TEXTURE,
		}, {
			Name = "Panel",
			Size = UDim2.fromScale(1, 1),
			create("ImageButton")({
				Name = "Sink",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ImageTransparency = 1,
				Selectable = false,
				ZIndex = 0,
			}),
			Components.Sheen(landed, 3),
			header(state, item),
			preview(state, item, sway),
			Label({
				Name = "ItemName",
				Position = function()
					return UDim2.fromOffset(
						Layout.NAME.X + math.round(Timing.NAME_FROM * (1 - Motion.Decelerate(named()))),
						Layout.NAME.Y
					)
				end,
				Size = UDim2.fromOffset(Layout.HELP.X - Layout.NAME.X - 16, Layout.NAME_TEXT),
				TextSize = Layout.NAME_TEXT,
				TextScaled = true,
				TextTransparency = function()
					return 1 - Motion.Out(named())
				end,
				Text = function()
					local current = item()
					return if current then string.upper(current.Name) else ""
				end,
				create("UITextSizeConstraint")({ MaxTextSize = Layout.NAME_TEXT }),
			}),
			rows,
			Label({
				Name = "Description",
				Position = function()
					local current = item()
					local count = if current then #current.Stats else 0
					return UDim2.fromOffset(
						Layout.STAT_X,
						Layout.STAT_TOP
							+ Layout.STAT_STEP * count
							- (Layout.STAT_STEP - Layout.STAT_SIZE.Y)
							+ Layout.DESCRIPTION_GAP
							+ math.round(10 * (1 - Motion.Decelerate(described())))
					)
				end,
				Size = UDim2.fromOffset(Layout.DESCRIPTION_WIDTH, 120),
				FontFace = Font.DisplayBold,
				TextSize = Layout.DESCRIPTION_TEXT,
				TextColor3 = Palette.Lavender,
				TextWrapped = true,
				TextTransparency = function()
					return 1 - Motion.Out(described()) * (1 - math.clamp(helpOpened(), 0, 1))
				end,
				Text = function()
					local current = item()
					return if current then descriptions[current.Id] else ""
				end,
			}),
			help(state, actions, item, helpOpened),
			-- His rect, so the switch and the slab keep their place as the panel grows over them.
			create("Frame")({
				Name = "Bottom",
				Position = function()
					return UDim2.fromOffset(0, lift())
				end,
				Size = UDim2.fromOffset(Layout.SIZE.X, Layout.SIZE.Y),
				BackgroundTransparency = 1,
				ZIndex = 4,
				toggle(state, actions, item),
				slab(state, actions, item),
			}),
		}),
	})
end

return Info
