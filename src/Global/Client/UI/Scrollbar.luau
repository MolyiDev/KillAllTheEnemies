--!nonstrict
-- The scrollbar every scroll draws beside its window (the engine's own is hidden: ScrollBarThickness = 0): his slim
-- accent pill in a dark groove. It follows the scroll on a spring, widens and glows under the hand, is dragged or
-- clicked to a place, squashes against an end the player scrolled into, and is gone while nothing overflows.
--
-- CanvasPosition and the canvas's offset are in the canvas's own unscaled px under a UIScale, so the canvas must be
-- sized in offset (not AutomaticCanvasSize). The window's height is read from its offset where it has one; otherwise
-- it is worked out from the absolute pair, which a UIScale changes on both at once.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local UserInputService = game:GetService("UserInputService")
local vide = require(ReplicatedStorage.Packages.vide)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)

local create = vide.create
local derive = vide.derive
local source = vide.source
local Palette = Theme.Palette

local Scrollbar = {}

-- Sizes in design px, periods in seconds.
local Tune = table.freeze({
	-- The drawn thumb, and under the hand or held.
	WIDTH = 8,
	HOT_WIDTH = 12,
	GROOVE = 4,
	-- What takes the hand: wider than what is drawn, so a finger can catch it. It must stop short of the list.
	GRAB = 28,
	MIN_THUMB = 48,
	-- The grip's three lines show on a thumb this tall.
	GRIP = 72,
	FOLLOW = 0.1,
	FOLLOW_DAMPING = 0.85,
	LIGHT = 0.12,
	SHOW = 0.22,
	-- Reaching an end squashes the thumb this many px against it, and it rings back.
	SQUASH = 10,
	SQUASH_PERIOD = 0.3,
	SQUASH_DAMPING = 0.45,
	-- A wheel or touch pan this recent makes an end squash: a page that resets its scroll just slides.
	PLAYER_SCROLL = 0.35,
})
local GROOVE_COLOR = Color3.fromRGB(30, 22, 54)
local GROOVE_EDGE = Color3.fromRGB(72, 56, 112)

export type TSpec = {
	-- The bar's length in design px: the window's height, less any margin the caller keeps. A source for a window
	-- whose height follows something else (the lobby's panels follow the top bar).
	Length: number | () -> number,
	Accent: Color3?,
	-- 0 to 1, the screen's own fade, for a bar not inside a group that fades it. Nil for always.
	Shown: (() -> number)?,
}

-- The bar for `frame`, sized `Tune.GRAB` x `spec.Length`: `props` places it (AnchorPoint, Position, ZIndex).
function Scrollbar.Build(frame: ScrollingFrame, spec: TSpec, props: { [any]: any }): Frame
	local accent = spec.Accent or Palette.Pink
	local given = spec.Length
	local length = if type(given) == "function"
		then given
		else function(): number
			return given :: number
		end
	local outer = spec.Shown

	-- The canvas, the window and the scroll, in the canvas's own px.
	local canvasUnits = source(0)
	local windowUnits = source(0)
	local scrolled = source(0)
	local function measure()
		local canvas = frame.CanvasSize.Y.Offset
		local window = frame.Size.Y.Offset
		if frame.Size.Y.Scale ~= 0 then
			local absoluteCanvas = frame.AbsoluteCanvasSize.Y
			window = if absoluteCanvas > 0 then canvas * frame.AbsoluteWindowSize.Y / absoluteCanvas else 0
		end
		canvasUnits(canvas)
		windowUnits(window)
	end

	local range = derive(function(): number
		return math.max(canvasUnits() - windowUnits(), 0)
	end)
	local isNeeded = derive(function(): boolean
		return windowUnits() > 0 and range() > 1
	end)
	local thumbLength = derive(function(): number
		local canvas = canvasUnits()
		local long = length()
		if canvas <= 0 then return long end
		return math.clamp(long * windowUnits() / canvas, Tune.MIN_THUMB, long)
	end)
	local thumbTop = derive(function(): number
		local share = if range() > 0 then math.clamp(scrolled() / range(), 0, 1) else 0
		return share * (length() - thumbLength())
	end)

	local isHovered = source(false)
	local isHeld = source(false)
	local top = Hand.Spring(thumbTop, Tune.FOLLOW, Tune.FOLLOW_DAMPING)
	local size = Hand.Spring(thumbLength, Tune.FOLLOW, Tune.FOLLOW_DAMPING)
	local light = Hand.Spring(function(): number
		return if isHovered() or isHeld() then 1 else 0
	end, Tune.LIGHT)
	local reveal = Hand.Spring(function(): number
		return if isNeeded() then 1 else 0
	end, Tune.SHOW)
	local shown = function(): number
		local value = math.clamp(reveal(), 0, 1)
		return if outer then value * outer() else value
	end
	local squash, strike = Hand.Kick(Tune.SQUASH_PERIOD, Tune.SQUASH_DAMPING)
	-- Which end the squash pins the thumb to: -1 the top, 1 the bottom.
	local squashEnd = 1
	local lastEnd = 0
	local lastPlayerScroll = -math.huge

	-- A bar that appears is placed where it belongs, not slid in from where it was.
	vide.effect(function()
		if not isNeeded() then return end
		vide.untrack(function()
			top(thumbTop())
			size(thumbLength())
		end)
	end)

	local function onScrolled()
		local y = frame.CanvasPosition.Y
		scrolled(y)
		local most = range()
		local atEnd = if most <= 0 then 0 elseif y <= 0.5 then -1 elseif y >= most - 0.5 then 1 else 0
		local isPlayers = isHeld() or os.clock() - lastPlayerScroll < Tune.PLAYER_SCROLL
		if atEnd ~= 0 and atEnd ~= lastEnd and isPlayers then
			squashEnd = atEnd
			strike(1)
		end
		lastEnd = atEnd
	end

	local connections = {
		frame:GetPropertyChangedSignal("CanvasSize"):Connect(measure),
		frame:GetPropertyChangedSignal("Size"):Connect(measure),
		frame:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(measure),
		frame:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(measure),
		frame:GetPropertyChangedSignal("CanvasPosition"):Connect(onScrolled),
		frame.InputChanged:Connect(function(input: InputObject)
			local kind = input.UserInputType
			if kind == Enum.UserInputType.MouseWheel or kind == Enum.UserInputType.Touch then
				lastPlayerScroll = os.clock()
			end
		end),
	}
	measure()
	scrolled(frame.CanvasPosition.Y)

	-- The drag: where along the bar the hand is, in design px, from the groove's place on screen (an InputObject and
	-- AbsolutePosition are in the same space).
	local groove: Frame
	local grabOffset = 0
	local dragConnections: { RBXScriptConnection } = {}
	local function along(input: InputObject): number
		local scale = groove.AbsoluteSize.Y / length()
		if scale <= 0 then return 0 end
		return (input.Position.Y - groove.AbsolutePosition.Y) / scale
	end
	local function dragTo(input: InputObject)
		local room = length() - thumbLength()
		if room <= 0 then return end
		local share = math.clamp((along(input) - grabOffset) / room, 0, 1)
		frame.CanvasPosition = Vector2.new(frame.CanvasPosition.X, share * range())
	end
	local function release()
		for _, connection in dragConnections do
			connection:Disconnect()
		end
		table.clear(dragConnections)
		if isHeld() then isHeld(false) end
	end
	local function grab(input: InputObject)
		local kind = input.UserInputType
		if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then return end
		if not isNeeded() then return end
		-- On the thumb, it is held where it was caught; on the groove, the thumb's middle jumps to the hand.
		local at = along(input)
		local from = thumbTop()
		grabOffset = if at >= from and at <= from + thumbLength() then at - from else thumbLength() / 2
		isHeld(true)
		SoundsCore.PlayClick()
		dragTo(input)
		table.insert(
			dragConnections,
			UserInputService.InputChanged:Connect(function(moved: InputObject)
				local movedKind = moved.UserInputType
				if movedKind == Enum.UserInputType.MouseMovement or movedKind == Enum.UserInputType.Touch then
					dragTo(moved)
				end
			end)
		)
		table.insert(
			dragConnections,
			UserInputService.InputEnded:Connect(function(ended: InputObject)
				local endedKind = ended.UserInputType
				if endedKind == Enum.UserInputType.MouseButton1 or endedKind == Enum.UserInputType.Touch then
					release()
				end
			end)
		)
	end

	vide.cleanup(function()
		release()
		for _, connection in connections do
			connection:Disconnect()
		end
	end)

	-- The thumb's rect with its squash: the end it hit holds still, the far end gives.
	local squashPx = function(): number
		return Tune.SQUASH * squash()
	end
	local width = function(): number
		return Tune.WIDTH + (Tune.HOT_WIDTH - Tune.WIDTH) * light()
	end

	local gripLines = table.create(3)
	for index = 1, 3 do
		gripLines[index] = create("Frame")({
			LayoutOrder = index,
			Size = UDim2.fromOffset(4, 2),
			BackgroundColor3 = Palette.White,
			BackgroundTransparency = function()
				return 1 - (0.35 + 0.4 * light()) * shown()
			end,
			BorderSizePixel = 0,
		})
	end

	groove = create("Frame")({
		Name = "Groove",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(0, Tune.GROOVE, 1, 0),
		BackgroundColor3 = GROOVE_COLOR,
		BackgroundTransparency = function()
			return 1 - 0.85 * shown()
		end,
		BorderSizePixel = 0,
		create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
		create("UIStroke")({
			Color = GROOVE_EDGE,
			Thickness = 1,
			Transparency = function()
				return 1 - 0.5 * shown()
			end,
		}),
	}) :: Frame

	local thumb = create("Frame")({
		Name = "Thumb",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = function()
			local offset = if squashEnd > 0 then squashPx() else 0
			return UDim2.new(0.5, 0, 0, math.round(top() + offset))
		end,
		Size = function()
			return UDim2.fromOffset(math.round(width()), math.round(math.max(size() - math.abs(squashPx()), 8)))
		end,
		BackgroundColor3 = function()
			return accent:Lerp(Palette.White, 0.2 * light())
		end,
		BackgroundTransparency = function()
			return 1 - shown()
		end,
		BorderSizePixel = 0,
		ZIndex = 2,
		create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
		-- Lit down its left, as his slabs are lit from the upper left.
		create("UIGradient")({
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
				ColorSequenceKeypoint.new(0.45, Color3.new(0.92, 0.92, 0.92)),
				ColorSequenceKeypoint.new(1, Color3.new(0.62, 0.62, 0.62)),
			}),
		}),
		create("UIShadow")({
			Name = "Glow",
			BlurRadius = UDim.new(0, 14),
			Color = accent,
			Offset = UDim2.new(),
			Spread = UDim2.new(),
			Transparency = function()
				return 1 - (0.3 + 0.45 * light()) * shown()
			end,
			ZIndex = -1,
		}),
		create("Frame")({
			Name = "Grip",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(4, 14),
			BackgroundTransparency = 1,
			Visible = function()
				return size() >= Tune.GRIP
			end,
			ZIndex = 3,
			create("UIListLayout")({
				FillDirection = Enum.FillDirection.Vertical,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 3),
			}),
			gripLines,
		}),
	})

	return create("TextButton")({
		Name = "Scrollbar",
		Size = function()
			return UDim2.fromOffset(Tune.GRAB, length())
		end,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		Selectable = false,
		Visible = function()
			return shown() > 0.01
		end,
		InputBegan = grab,
		MouseEnter = function()
			if UserInputService:GetLastInputType() == Enum.UserInputType.Touch then return end
			isHovered(true)
			SoundsCore.PlayHover()
		end,
		MouseLeave = function()
			isHovered(false)
		end,
		groove,
		thumb,
		props,
	}) :: Frame
end

return Scrollbar
