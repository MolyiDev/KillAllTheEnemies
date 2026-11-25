--!nonstrict
-- How many a button makes at once (the Mutation Lab's BREW, the daily SPIN): a trigger beside it (the count picked)
-- and the menu it unrolls upward (the smallest count nearest the trigger). One plate slides to the row under the hand,
-- its leading edge on a quicker spring so it stretches toward the row and snaps shut on it; each row's hover is a step
-- higher. A row may say what that many would cost in Robux. A press anywhere else folds it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
local source = vide.source
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress

local Layout = table.freeze({
	TRIGGER_TEXT = 34,
	CAPTION_TEXT = 13,
	CHEVRON = 26,
	-- The menu stands this far over the trigger, its rows this tall inside this much padding.
	MENU_GAP = 12,
	ROW = 50,
	PAD = 8,
	ROW_TEXT = 26,
	PRICE_TEXT = 18,
	ROBUX = 16,
})

local Timing = table.freeze({
	-- Unrolls with an ease out, folds faster.
	OPEN = 0.13,
	CLOSE = 0.08,
	PLATE_LEAD = 0.07,
	PLATE_TRAIL = 0.16,
	-- The number punches as a new count is picked.
	PUNCH = 0.3,
})

export type TProps = {
	-- The trigger's rect in its parent's px; the menu unrolls up from its top.
	Rect: Rect,
	-- The small word over the count: BREW, SPIN.
	Caption: string,
	-- The counts on offer, smallest first.
	Options: { number },
	Picked: () -> number,
	IsOpen: () -> boolean,
	-- When the menu last opened or shut, on the caller's clock (`Now`, written while a gesture runs).
	MenuAt: () -> number,
	Now: () -> number,
	-- Whether the button beside it can go: the count is drawn white, else lavender.
	IsLive: () -> boolean,
	-- Whether a count can be had now (dimmed when not; it can still be picked).
	IsReachable: ((count: number) -> boolean)?,
	-- What that many would cost in Robux now, or nil when it would not be bought.
	Price: ((count: number) -> number?)?,
	SetOpen: (isOpen: boolean) -> (),
	Pick: (count: number) -> (),
	-- Off while something covers the trigger.
	Interactable: (() -> boolean)?,
}

local countPicker = {}

-- A count's word: x5.
function countPicker.Word(count: number): string
	return `x{count}`
end

-- 0 to 1 as the menu unrolls, back to 0 as it folds.
local function unrolled(props: TProps): () -> number
	return derive(function(): number
		local at = props.MenuAt()
		if props.IsOpen() then return Motion.Decelerate(Progress(props.Now(), at, Timing.OPEN)) end
		return 1 - Motion.Accelerate(Progress(props.Now(), at, Timing.CLOSE))
	end)
end

local function label(fields: { [any]: any }): TextLabel
	return create("TextLabel")({
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		FontFace = Font.Display,
		TextColor3 = Palette.White,
		ZIndex = 4,
		fields,
	})
end

local function trigger(props: TProps, open: () -> number): TextButton
	local rect = props.Rect
	local hand = Hand.React("Operate")
	local pickedAt = source(-math.huge)
	local last = vide.untrack(props.Picked)
	vide.effect(function()
		local count = props.Picked()
		if count == last then return end
		last = count
		pickedAt(vide.untrack(props.Now))
	end)

	return Components.Button({
		Name = "Count",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(rect.Min.X + rect.Width / 2, rect.Min.Y + rect.Height / 2),
		Size = UDim2.fromOffset(rect.Width, rect.Height),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Interactable = props.Interactable,
		Activated = function()
			hand.Commit()
			props.SetOpen(not props.IsOpen())
		end,
		hand.Events,
		create("UIScale")({ Scale = hand.Scale }),
		Components.Panel({
			Brackets = hand.Rise,
			BracketsClosed = props.IsOpen,
			Glow = function()
				return Color3.new():Lerp(Palette.Pink, math.max(hand.Light(), open()))
			end,
			GlowTransparency = function()
				return 0.6 - 0.3 * math.max(hand.Light(), open())
			end,
		}, {
			Name = "Plate",
			Size = UDim2.fromScale(1, 1),
			Hand.WashLayer(hand, 3, 2),
			Components.Sheen(hand.Glint, 3, rect.Width / rect.Height),
			label({
				Name = "Caption",
				Position = UDim2.fromOffset(20, 12),
				Size = UDim2.fromOffset(120, Layout.CAPTION_TEXT),
				FontFace = Font.DisplayBold,
				TextSize = Layout.CAPTION_TEXT,
				TextColor3 = Palette.Lavender,
				Text = props.Caption,
			}),
			label({
				Name = "Count",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromOffset(20, rect.Height - 28),
				Size = UDim2.fromOffset(120, Layout.TRIGGER_TEXT),
				TextSize = Layout.TRIGGER_TEXT,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextColor3 = function()
					return if props.IsLive() then Palette.White else Palette.Lavender
				end,
				Text = function()
					return countPicker.Word(props.Picked())
				end,
				create("UIScale")({
					Scale = function()
						return 1 + 0.25 * (1 - Motion.Decelerate(Progress(props.Now(), pickedAt(), Timing.PUNCH)))
					end,
				}),
			}),
			Components.Picture(EIcons.Arrow, {
				Name = "Chevron",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(1, -36, 0.5, 0),
				Size = Components.PictureBox(Layout.CHEVRON),
				ImageColor3 = Palette.Pink,
				-- Up while shut (the menu unrolls up), down while open.
				Rotation = function()
					return -90 + 180 * open()
				end,
				ZIndex = 4,
			}),
		}),
	}) :: TextButton
end

local function menu(props: TProps, open: () -> number): { Instance }
	local rect = props.Rect
	local options = props.Options
	local rows = #options
	local height = rows * Layout.ROW + 2 * Layout.PAD
	local bottom = rect.Min.Y - Layout.MENU_GAP
	local hovered = source(0)
	-- Rows count from the top, the biggest count first.
	local function rowOf(count: number): number
		local at = table.find(options, count) or 1
		return rows + 1 - at
	end
	-- The row the plate is on: the one under the hand, else the count picked.
	local target = derive(function(): number
		if hovered() > 0 then return hovered() end
		return rowOf(props.Picked())
	end)
	local lead = Hand.Spring(target, Timing.PLATE_LEAD)
	local trail = Hand.Spring(target, Timing.PLATE_TRAIL)
	local isDrawn = derive(function(): boolean
		return open() > 0.001
	end)
	-- Folded, nothing is under the hand.
	vide.effect(function()
		if not props.IsOpen() then hovered(0) end
	end)

	local list = table.create(rows)
	for at, count in options do
		local row = rows + 1 - at
		local isReachable = derive(function(): boolean
			return if props.IsReachable then props.IsReachable(count) else true
		end)
		local price = derive(function(): number?
			return if props.Price then props.Price(count) else nil
		end)
		list[at] = create("TextButton")({
			Name = `Row{count}`,
			Position = UDim2.fromOffset(Layout.PAD, Layout.PAD + (row - 1) * Layout.ROW),
			Size = UDim2.fromOffset(rect.Width - 2 * Layout.PAD, Layout.ROW),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 4,
			MouseEnter = function()
				hovered(row)
				SoundsCore.PlayUINamed("UI", "HoverHud", 1 + 0.05 * (rows - row))
			end,
			MouseLeave = function()
				if hovered() == row then hovered(0) end
			end,
			Activated = function()
				props.Pick(count)
			end,
			label({
				Name = "Word",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromScale(0, 0.5) + UDim2.fromOffset(16, 0),
				Size = UDim2.fromOffset(80, Layout.ROW_TEXT),
				TextSize = Layout.ROW_TEXT,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextColor3 = function()
					if target() == row then return Palette.White end
					return if isReachable() then Palette.White:Lerp(Palette.Lavender, 0.3) else Palette.Lavender
				end,
				TextTransparency = function()
					return if isReachable() then 0 else 0.35
				end,
				Text = countPicker.Word(count),
				ZIndex = 5,
			}),
			-- What that many costs, right-aligned: the Robux mark and the price.
			create("Frame")({
				Name = "Price",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -14, 0.5, 0),
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, Layout.PRICE_TEXT),
				BackgroundTransparency = 1,
				Visible = function()
					return price() ~= nil
				end,
				ZIndex = 5,
				create("UIListLayout")({
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Right,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 5),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
				Components.Icon("Robux", {
					LayoutOrder = 1,
					Size = Components.GlyphBox(Layout.ROBUX),
					ImageColor3 = Palette.Gold,
					ZIndex = 5,
				}),
				label({
					LayoutOrder = 2,
					AutomaticSize = Enum.AutomaticSize.X,
					Size = UDim2.fromOffset(0, Layout.PRICE_TEXT),
					FontFace = Font.DisplayBold,
					TextSize = Layout.PRICE_TEXT,
					TextYAlignment = Enum.TextYAlignment.Center,
					TextColor3 = Palette.Gold,
					Text = function()
						local robux = price()
						return if robux then tostring(robux) else ""
					end,
					ZIndex = 5,
				}),
			}),
		})
	end

	return {
		-- A press anywhere else folds it.
		create("TextButton")({
			Name = "Catcher",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(4, 4),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 11,
			Visible = props.IsOpen,
			Activated = function()
				props.SetOpen(false)
			end,
		}),
		create("Frame")({
			Name = "Menu",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromOffset(rect.Min.X, bottom),
			Size = function()
				return UDim2.fromOffset(rect.Width, math.round(height * open()))
			end,
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			Visible = isDrawn,
			ZIndex = 12,
			Components.Panel({ Glow = Palette.Pink, GlowTransparency = 0.55 }, {
				Name = "Body",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.fromOffset(rect.Width, height),
				ZIndex = 1,
				create("Frame")({
					Name = "Plate",
					Position = function()
						local top = math.min(lead(), trail())
						return UDim2.fromOffset(Layout.PAD, Layout.PAD + math.round((top - 1) * Layout.ROW))
					end,
					Size = function()
						local span = math.abs(lead() - trail())
						return UDim2.fromOffset(rect.Width - 2 * Layout.PAD, math.round((1 + span) * Layout.ROW))
					end,
					BackgroundColor3 = Palette.Pink,
					BackgroundTransparency = function()
						return if hovered() > 0 then 0.15 else 0.55
					end,
					BorderSizePixel = 0,
					ZIndex = 3,
					create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
				}),
				list,
			}),
		}),
	}
end

-- The trigger and its menu, among the parent's children.
function countPicker.Build(props: TProps): { any }
	local open = unrolled(props)

	return { trigger(props, open), menu(props, open) }
end

return countPicker
