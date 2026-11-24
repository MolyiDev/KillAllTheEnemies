--!nonstrict
-- The code field, in his Display Name input's look (UIMatt.md, Settings: ink face, pink edge, the pencil): a TextBox
-- takes the keys, and the letters are drawn over it one cell each, so every letter can move on its own. A letter typed
-- slams into its cell, one deleted drops out of it, a paste lands a beat apart; the field lights while it is typed in,
-- a light scans it while the code is checked, it shakes red at a refusal and goes green with a ring at a redeem, its
-- letters hopping in a wave before they lift away.
--
-- The box itself draws nothing: its text is invisible and 1 px, so its own caret and selection are too (the caret here
-- is drawn, at the cells' end), and the cursor is held at the end of the text.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local UserInputService = game:GetService("UserInputService")
local vide = require(ReplicatedStorage.Packages.vide)
local CodesCore = require(ReplicatedStorage.GlobalShared.Core.CodesCore)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local Types = require(script.Parent.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress

-- Px at 1080, from the field's top left.
local Layout = table.freeze({
	SIZE = Vector2.new(760, 84),
	EDGE = 2,
	CORNER = 2,
	-- The letters: the first cell's left, each cell's width, the letters' height.
	PAD = 28,
	CELL = 33,
	LETTER = 34,
	PLACEHOLDER = 24,
	-- In focus the hint steps aside for the caret.
	PLACEHOLDER_SLIDE = 16,
	CARET = Vector2.new(3, 40),
	PENCIL = Vector2.new(722, 42),
	PENCIL_SIZE = 24,
	-- The ring a redeem throws, from the field's edge outward.
	RING_GROW = 26,
	RING_LINE = 2,
})

local Timing = table.freeze({
	FOCUS_PERIOD = 0.12,
	-- A letter typed: it lands from big and pink to its size and white.
	POP = 0.2,
	POP_GROW = 0.55,
	POP_DROP = 10,
	-- A letter deleted falls out and fades; one swept after a redeem lifts out.
	GHOST = 0.24,
	GHOST_FALL = 16,
	GHOST_LIFT = 30,
	GHOST_SHRINK = 0.35,
	-- vide steps springs at 120 Hz by semi-implicit Euler: a critically damped one under about 0.063 s blows up.
	CARET_PERIOD = 0.09,
	PENCIL_WIGGLE = 0.5,
	PENCIL_TURN = 22,
	-- The scan while the code is checked: one crossing every SCAN seconds.
	SCAN = 0.5,
	-- A refusal: the shake, the red holding, then draining back.
	SHAKE = 0.45,
	SHAKE_PX = 14,
	RED_HOLD = 0.35,
	RED_DRAIN = 0.7,
	-- A redeem: the white flash over the face, the ring, and the letters hopping one after another.
	FLASH = 0.32,
	FLASH_STRENGTH = 0.55,
	RING = 0.55,
	HOP_STAGGER = 0.035,
	HOP = 0.34,
	HOP_PX = 14,
	GREEN_IN = 0.12,
})

-- His edge and face, sampled off the art, and the refusal's red.
local EDGE = Color3.fromRGB(163, 33, 97)
local FACE = Color3.fromRGB(12, 10, 28)
local RED = Color3.fromRGB(255, 72, 88)
-- A white flash over the ink reads as grey: it is lit with the redeem's green.
local FLASH_COLOR = Palette.White:Lerp(Palette.Green, 0.5)

local Field = {}

Field.SIZE = Layout.SIZE

-- The field, standing in the middle of its parent.
function Field.Build(state: Types.TCodesState, actions: Types.TCodesActions): Frame
	local now = state.Now
	local focus = Hand.Spring(function()
		return if state.IsFocused() then 1 else 0
	end, Timing.FOCUS_PERIOD)

	-- 1 while a refusal's red holds, draining to 0; a press with nothing typed flashes it too.
	local red = derive(function(): number
		local at = state.NudgedAt()
		if state.Status() == "Refused" then at = math.max(at, state.AnsweredAt()) end
		if at == -math.huge then return 0 end
		return 1 - Progress(now(), at, Timing.RED_DRAIN, Timing.RED_HOLD)
	end)
	-- 0 to 1 as a redeem's green comes in; held while its answer is shown.
	local green = derive(function(): number
		if state.Status() ~= "Redeemed" then return 0 end
		return Progress(now(), state.AnsweredAt(), Timing.GREEN_IN)
	end)
	local flash = derive(function(): number
		if state.Status() ~= "Redeemed" then return 0 end
		return Motion.Fade(now(), state.AnsweredAt(), Timing.FLASH)
	end)
	local shake = derive(function(): number
		local at = state.NudgedAt()
		if state.Status() == "Refused" then at = math.max(at, state.AnsweredAt()) end
		return Timing.SHAKE_PX * Motion.Shake(Progress(now(), at, Timing.SHAKE), at)
	end)
	local scan = derive(function(): number
		if state.Status() ~= "Checking" then return 1 end
		return ((now() - state.AskedAt()) / Timing.SCAN) % 1
	end)
	-- Derived: the edge and the glow both wear it.
	local tint = derive(function(): Color3
		local color = EDGE:Lerp(Palette.Pink, focus())
		color = color:Lerp(Palette.Green, green())
		return color:Lerp(RED, red())
	end)

	local length = derive(function(): number
		return #state.Text()
	end)

	-- One cell's letter: it pops as it lands, hops at a redeem, goes red at a refusal and dims while checked. An empty
	-- cell returns before reading the clock, so the clock's ticks rerun nothing in it.
	local function letter(index: number): TextLabel
		local isEmpty = derive(function(): boolean
			return index > length()
		end)
		local char = derive(function(): string
			return string.sub(state.Text(), index, index)
		end)
		local pop = derive(function(): number
			if isEmpty() then return 0 end
			return 1 - Motion.Out(Progress(now(), state.BornAt[index](), Timing.POP))
		end)
		-- A pasted letter not yet landed waits unseen.
		local isWaiting = derive(function(): boolean
			if isEmpty() then return false end
			return now() < state.BornAt[index]()
		end)
		local hop = derive(function(): number
			if isEmpty() or state.Status() ~= "Redeemed" then return 0 end
			return Motion.Bump(Progress(now(), state.AnsweredAt() + Timing.HOP_STAGGER * (index - 1), Timing.HOP))
		end)

		return create("TextLabel")({
			Name = `Letter{index}`,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				local y = -Timing.POP_DROP * pop() - Timing.HOP_PX * hop()
				return UDim2.new(0, Layout.PAD + Layout.CELL * (index - 0.5), 0.5, math.round(y))
			end,
			Size = UDim2.fromOffset(Layout.CELL + 12, Layout.LETTER),
			BackgroundTransparency = 1,
			FontFace = Font.Display,
			TextSize = Layout.LETTER,
			Text = char,
			TextColor3 = function()
				local color = Palette.White:Lerp(Palette.Pink, pop())
				color = color:Lerp(Palette.Green, green())
				return color:Lerp(RED, red())
			end,
			TextTransparency = function()
				if isWaiting() then return 1 end
				return if state.Status() == "Checking" then 0.4 else 0
			end,
			ZIndex = 5,
			create("UIScale")({
				Scale = function()
					return 1 + Timing.POP_GROW * pop() + 0.12 * hop()
				end,
			}),
		})
	end

	-- A letter leaving its cell: one waiting its turn in a sweep sits still in it. Empty once it has gone.
	local function ghost(slot: Types.TGhost): TextLabel
		-- A slot never used reads no clock.
		local t = derive(function(): number
			if slot.At() == -math.huge then return 1 end
			return Progress(now(), slot.At(), Timing.GHOST)
		end)
		local isGoing = derive(function(): boolean
			return t() < 1
		end)

		return create("TextLabel")({
			Name = "Ghost",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				local at = t()
				local y = if slot.IsLift()
					then -Timing.GHOST_LIFT * Motion.Decelerate(at)
					else Timing.GHOST_FALL * Motion.Accelerate(at)
				return UDim2.new(0, Layout.PAD + Layout.CELL * (slot.Cell() - 0.5), 0.5, math.round(y))
			end,
			Size = UDim2.fromOffset(Layout.CELL + 12, Layout.LETTER),
			BackgroundTransparency = 1,
			FontFace = Font.Display,
			TextSize = Layout.LETTER,
			Text = function()
				return if isGoing() then slot.Letter() else ""
			end,
			TextColor3 = function()
				return if slot.IsLift() then Palette.Green else Palette.Lavender
			end,
			TextTransparency = function()
				return Motion.Out(t())
			end,
			ZIndex = 5,
			create("UIScale")({
				Scale = function()
					return 1 - Timing.GHOST_SHRINK * t()
				end,
			}),
		})
	end

	-- The letters that have landed: a paste's caret runs along with them rather than waiting at the end.
	local landed = derive(function(): number
		local count = length()
		if count == 0 then return 0 end
		local at = now()
		while count > 0 and state.BornAt[count]() > at do
			count -= 1
		end
		return count
	end)
	local caretX = Hand.Spring(function()
		return Layout.PAD + Layout.CELL * landed()
	end, Timing.CARET_PERIOD)
	local pencilTurn = derive(function(): number
		return Timing.PENCIL_TURN * Motion.Swing(Progress(now(), state.FocusedAt(), Timing.PENCIL_WIGGLE))
	end)

	local letters = table.create(CodesCore.MAX_LENGTH)
	for index = 1, CodesCore.MAX_LENGTH do
		letters[index] = letter(index)
	end
	local ghosts = table.create(#state.Ghosts)
	for index, slot in state.Ghosts do
		ghosts[index] = ghost(slot)
	end

	local box: TextBox? = nil
	-- What reaches the controller is already as the server compares it: the box is put right first, which fires this
	-- again with nothing left to change.
	local function onText()
		local current = box
		if not current then return end
		local normalized = CodesCore.Normalize(current.Text)
		if normalized ~= current.Text then
			current.Text = normalized
			return
		end
		actions.Type(normalized)
		current.CursorPosition = #normalized + 1
	end

	-- Opened, a keyboard player can type at once; a touch one taps the field, rather than having the keyboard thrown
	-- over the screen. Shut, the keys go back to the game.
	vide.effect(function()
		local isOpen = state.IsOpen()
		vide.untrack(function()
			local current = box
			if not current then return end
			if not isOpen then
				current:ReleaseFocus()
			elseif UserInputService.KeyboardEnabled and not UserInputService.TouchEnabled then
				task.defer(current.CaptureFocus, current)
			end
		end)
	end)

	return create("Frame")({
		Name = "Field",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			return UDim2.new(0.5, math.round(shake()), 0.5, 0)
		end,
		Size = UDim2.fromOffset(Layout.SIZE.X, Layout.SIZE.Y),
		BackgroundColor3 = tint,
		BorderSizePixel = 0,
		ZIndex = 3,
		create("UICorner")({ CornerRadius = UDim.new(0, Layout.CORNER) }),
		create("UIShadow")({
			Name = "Glow",
			BlurRadius = UDim.new(0, 22),
			Color = tint,
			Offset = UDim2.new(),
			Spread = UDim2.new(),
			Transparency = function()
				local light = math.max(0.45 * focus(), green(), red())
				return 1 - 0.55 * light
			end,
			ZIndex = -1,
		}),
		create("Frame")({
			Name = "Face",
			Position = UDim2.fromOffset(Layout.EDGE, Layout.EDGE),
			Size = UDim2.new(1, -2 * Layout.EDGE, 1, -2 * Layout.EDGE),
			BackgroundColor3 = FACE,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			ZIndex = 3,
			create("UICorner")({ CornerRadius = UDim.new(0, 1) }),
			Components.Sheen(scan, 4),
			create("Frame")({
				Name = "Flash",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = FLASH_COLOR,
				BorderSizePixel = 0,
				ZIndex = 4,
				Visible = function()
					return flash() > 0.004
				end,
				BackgroundTransparency = function()
					return 1 - Timing.FLASH_STRENGTH * flash()
				end,
			}),
		}),
		create("TextLabel")({
			Name = "Placeholder",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = function()
				return UDim2.new(0, Layout.PAD + math.round(Layout.PLACEHOLDER_SLIDE * focus()), 0.5, 0)
			end,
			Size = UDim2.fromOffset(500, Layout.PLACEHOLDER),
			BackgroundTransparency = 1,
			FontFace = Font.Display,
			TextSize = Layout.PLACEHOLDER,
			TextColor3 = Palette.Lavender,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "TYPE A CODE",
			TextTransparency = function()
				if length() > 0 then return 1 end
				return 0.55 - 0.25 * focus()
			end,
			ZIndex = 5,
		}),
		letters,
		ghosts,
		create("Frame")({
			Name = "Caret",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				return UDim2.new(0, math.round(caretX()) + 2, 0.5, 0)
			end,
			Size = UDim2.fromOffset(Layout.CARET.X, Layout.CARET.Y),
			BackgroundColor3 = Palette.Pink,
			BorderSizePixel = 0,
			ZIndex = 6,
			Visible = function()
				return state.IsFocused()
					and state.IsCaretOn()
					and state.Status() ~= "Checking"
					and length() < CodesCore.MAX_LENGTH
			end,
		}),
		Components.Picture(EIcons.Pencil, {
			Name = "Pencil",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(Layout.PENCIL.X, Layout.PENCIL.Y),
			Size = Components.PictureBox(Layout.PENCIL_SIZE),
			Rotation = pencilTurn,
			ZIndex = 6,
		}),
		create("TextBox")({
			Name = "Box",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ClearTextOnFocus = false,
			MultiLine = false,
			TextEditable = function()
				return state.Status() ~= "Checking"
			end,
			FontFace = Font.Display,
			TextSize = 1,
			TextTransparency = 1,
			PlaceholderText = "",
			Text = state.Text,
			ZIndex = 7,
			vide.action(function(instance: Instance)
				local current = instance :: TextBox
				box = current
				current:GetPropertyChangedSignal("Text"):Connect(onText)
				-- The letters are drawn in cells from the left: the cursor stays at the end, where the caret is.
				current:GetPropertyChangedSignal("CursorPosition"):Connect(function()
					local at = #current.Text + 1
					if current.CursorPosition ~= -1 and current.CursorPosition ~= at then
						current.CursorPosition = at
					end
				end)
				current.Focused:Connect(function()
					actions.Focus(true)
				end)
				current.FocusLost:Connect(function(isEnter: boolean)
					actions.Focus(false)
					if isEnter then actions.Redeem() end
				end)
			end),
		}),
	})
end

-- The ring a redeem throws off the field: one outline growing out of its edge and fading, from the middle of its parent.
function Field.Ring(state: Types.TCodesState): Frame
	local t = derive(function(): number
		if state.Status() ~= "Redeemed" then return 1 end
		return Progress(state.Now(), state.AnsweredAt(), Timing.RING)
	end)

	return create("Frame")({
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = function()
			local grow = math.round(2 * Layout.RING_GROW * Motion.Out(t()))
			return UDim2.fromOffset(Layout.SIZE.X + grow, Layout.SIZE.Y + grow)
		end,
		BackgroundTransparency = 1,
		ZIndex = 2,
		Visible = function()
			return t() < 1
		end,
		create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
		create("UIStroke")({
			Color = Palette.Green,
			Thickness = Layout.RING_LINE,
			Transparency = function()
				return Motion.Out(t())
			end,
		}),
	})
end

return Field
