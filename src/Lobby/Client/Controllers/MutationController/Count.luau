--!nonstrict
-- How many BREW makes at once: the trigger left of BREW (the count picked) and the menu it unrolls upward over the
-- souls (1X nearest the trigger, up to MAX). One plate slides to the row under the hand, its leading edge on a quicker spring so it
-- stretches toward the row and snaps shut on it; each row's hover is a step higher. A press anywhere else folds it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local Parts = require(script.Parent.Parts)
local Types = require(script.Parent.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
local source = vide.source
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress
local Label = Parts.Label

local Layout = table.freeze({
	-- The trigger, where the cost box stood: 40 px off BREW, past an Operate BREW's reach at its press (UI.md).
	TRIGGER = Rect.new(328, 845, 528, 917),
	TRIGGER_TEXT = 34,
	CHEVRON = 26,
	-- The menu stands this far over the trigger, its rows this tall inside this much padding.
	MENU_GAP = 12,
	ROW = 50,
	PAD = 8,
	ROW_TEXT = 26,
	ROW_NOTE = 16,
})

local Timing = table.freeze({
	-- Unrolls with an ease out, folds faster.
	OPEN = 0.13,
	CLOSE = 0.08,
	PLATE_LEAD = 0.07,
	PLATE_TRAIL = 0.16,
	PUNCH = 0.3,
})

local Count = {}

-- The counts on offer, top row first: 0 is MAX.
Count.OPTIONS = table.freeze({ 0, 10, 5, 3, 1 })
Count.Layout = Layout

-- A count's word: x5, or MAX.
function Count.Word(count: number): string
	return if count == 0 then "MAX" else `x{count}`
end

-- 0 to 1 as the menu unrolls, back to 0 as it folds.
local function unrolled(state: Types.TLabState): () -> number
	return derive(function(): number
		local at = state.MenuAt()
		if state.IsMenuOpen() then return Motion.Decelerate(Progress(state.Now(), at, Timing.OPEN)) end
		return 1 - Motion.Accelerate(Progress(state.Now(), at, Timing.CLOSE))
	end)
end

local function trigger(state: Types.TLabState, actions: Types.TLabActions, canBrew: () -> boolean)
	local rect = Layout.TRIGGER
	local hand = Hand.React("Operate")
	local open = unrolled(state)
	-- The number punches as a new count is picked.
	local pickedAt = source(-math.huge)
	local last = vide.untrack(state.BrewCount)
	vide.effect(function()
		local count = state.BrewCount()
		if count == last then return end
		last = count
		pickedAt(vide.untrack(state.Now))
	end)

	return Components.Button({
		Name = "Count",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(rect.Min.X + rect.Width / 2, rect.Min.Y + rect.Height / 2),
		Size = UDim2.fromOffset(rect.Width, rect.Height),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Activated = function()
			hand.Commit()
			actions.SetMenu(not state.IsMenuOpen())
		end,
		hand.Events,
		create("UIScale")({ Scale = hand.Scale }),
		Components.Panel({
			Brackets = hand.Rise,
			BracketsClosed = state.IsMenuOpen,
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
			Label({
				Name = "Caption",
				Position = UDim2.fromOffset(20, 12),
				Size = UDim2.fromOffset(120, 13),
				FontFace = Font.DisplayBold,
				TextSize = 13,
				TextColor3 = Palette.Lavender,
				Text = "BREW",
			}),
			Label({
				Name = "Count",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromOffset(20, 44),
				Size = UDim2.fromOffset(120, Layout.TRIGGER_TEXT),
				TextSize = Layout.TRIGGER_TEXT,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextColor3 = function()
					return if canBrew() then Palette.White else Palette.Lavender
				end,
				Text = function()
					return Count.Word(state.BrewCount())
				end,
				create("UIScale")({
					Scale = function()
						return 1 + 0.25 * (1 - Motion.Decelerate(Progress(state.Now(), pickedAt(), Timing.PUNCH)))
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

local function menu(state: Types.TLabState, actions: Types.TLabActions, possible: () -> number): { Instance }
	local rect = Layout.TRIGGER
	local open = unrolled(state)
	local rows = #Count.OPTIONS
	local height = rows * Layout.ROW + 2 * Layout.PAD
	local bottom = rect.Min.Y - Layout.MENU_GAP
	local hovered = source(0)
	-- The row the plate is on: the one under the hand, else the count picked. Rows count from the top.
	local target = derive(function(): number
		if hovered() > 0 then return hovered() end
		return table.find(Count.OPTIONS, state.BrewCount()) or rows
	end)
	local lead = Hand.Spring(function(): number
		return target()
	end, Timing.PLATE_LEAD)
	local trail = Hand.Spring(function(): number
		return target()
	end, Timing.PLATE_TRAIL)
	local isDrawn = derive(function(): boolean
		return open() > 0.001
	end)
	-- Folded, nothing is under the hand.
	vide.effect(function()
		if not state.IsMenuOpen() then hovered(0) end
	end)

	local list = {}
	for index, count in Count.OPTIONS do
		local isReachable = derive(function(): boolean
			return count == 0 or count <= math.max(possible(), 1)
		end)
		list[index] = create("TextButton")({
			Name = `Row{index}`,
			Position = UDim2.fromOffset(Layout.PAD, Layout.PAD + (index - 1) * Layout.ROW),
			Size = UDim2.fromOffset(rect.Width - 2 * Layout.PAD, Layout.ROW),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 4,
			MouseEnter = function()
				hovered(index)
				SoundsCore.PlayUINamed("UI", "HoverHud", 1 + 0.05 * (rows - index))
			end,
			MouseLeave = function()
				if hovered() == index then hovered(0) end
			end,
			Activated = function()
				actions.PickCount(count)
			end,
			Label({
				Name = "Word",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromScale(0, 0.5) + UDim2.fromOffset(16, 0),
				Size = UDim2.fromOffset(100, Layout.ROW_TEXT),
				TextSize = Layout.ROW_TEXT,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextColor3 = function()
					if target() == index then return Palette.White end
					return if isReachable() then Palette.White:Lerp(Palette.Lavender, 0.3) else Palette.Lavender
				end,
				TextTransparency = function()
					return if isReachable() then 0 else 0.35
				end,
				Text = Count.Word(count),
				ZIndex = 5,
			}),
			Label({
				Name = "Note",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -14, 0.5, 0),
				Size = UDim2.fromOffset(80, Layout.ROW_NOTE),
				FontFace = Font.DisplayBold,
				TextSize = Layout.ROW_NOTE,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextXAlignment = Enum.TextXAlignment.Right,
				TextColor3 = Palette.Gold,
				-- MAX says how many it makes now.
				Text = function()
					if count ~= 0 then return "" end
					return `x{possible()}`
				end,
				Visible = function()
					return count == 0 and possible() > 0
				end,
				ZIndex = 5,
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
			Visible = state.IsMenuOpen,
			Activated = function()
				actions.SetMenu(false)
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

-- The trigger and its menu. `possible` is how many a brew of the picks could make now (0 when none).
function Count.Build(state: Types.TLabState, actions: Types.TLabActions, possible: () -> number): { any }
	local canBrew = derive(function(): boolean
		return possible() > 0
	end)

	return { trigger(state, actions, canBrew), menu(state, actions, possible) }
end

return Count
