--!nonstrict
-- The settings rows' controls (UIMatt.md, Settings), drawn to his art's measured rects: the slider, the switch, the
-- name field and the reset button every row ends in. At rest each is his render; what moves is the hand's doing.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local vide = require(ReplicatedStorage.Packages.vide)
local SettingsCore = require(ReplicatedStorage.GlobalShared.Core.SettingsCore)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local Components = require(script.Parent.Parent.Components)
local Hand = require(script.Parent.Parent.Hand)
local Motion = require(script.Parent.Parent.Motion)
local Theme = require(script.Parent.Parent.Theme)
local Types = require(script.Parent.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local source = vide.source
local Palette = Theme.Palette
local Font = Theme.Font
local Lerp = Motion.Lerp

-- His drawn rects in px at 1080. A control is placed by its middle, so that it grows from there under the hand.
local Layout = table.freeze({
	-- The slider: the knob's middle rides the track's whole length, so it overhangs both ends by half itself.
	TRACK = Vector2.new(300, 14),
	KNOB = Vector2.new(26, 40),
	-- The hit box reaches this far past the track's ends and over the row's whole height.
	SLIDER_REACH = 16,
	SLIDER_HEIGHT = 71,
	-- The value's right end from the slider's left end, and its letter height.
	VALUE_RIGHT = 372,
	VALUE_SIZE = 24,
	SWITCH = Vector2.new(74, 36),
	SWITCH_EDGE = 1.5,
	SWITCH_KNOB = Vector2.new(30, 28),
	-- The knob's middle from the switch's left end, off and on.
	SWITCH_OFF_X = 19.5,
	SWITCH_ON_X = 54,
	RESET = 48,
	RESET_GLYPH = 21,
	-- Room round the reset button inside the group that dims it, for its shadow (a CanvasGroup clips).
	RESET_MARGIN = 26,
	-- The red slabs' arrow, the gap to their word, and the word.
	SLAB_GLYPH = 20,
	SLAB_GAP = 14,
	SLAB_TEXT_SIZE = 27,
})

local Timing = table.freeze({
	-- A slider's fill glides to where a reset or the server put it; under the hand it is the hand.
	GLIDE_PERIOD = 0.3,
	KNOB_PERIOD = 0.14,
	KNOB_HOVER = 1.1,
	KNOB_HELD = 1.22,
	KNOB_GLOW = 0.45,
	-- The switch's knob slides over, lengthening on the way; turned on it throws one ring.
	SWITCH_PERIOD = 0.2,
	SWITCH_DAMPING = 0.8,
	SWITCH_STRETCH = 8,
	RING = 0.45,
	RING_GROW = 14,
	-- A reset button comes alight when its row has left its default, and its arrow turns once back as it is pressed.
	LIT_PERIOD = 0.2,
	SPIN = 0.55,
	PRESS_PERIOD = 0.14,
	HOVER_PERIOD = 0.18,
})

-- His colours, sampled off the art.
local Look = table.freeze({
	TRACK_TRANSPARENCY = 0.88,
	SWITCH_EDGE_OFF = Color3.fromRGB(119, 97, 181),
	SWITCH_EDGE_ON = Color3.fromRGB(47, 188, 116),
	SWITCH_FACE_OFF = Color3.fromRGB(47, 39, 72),
	SWITCH_FACE_ON = Color3.fromRGB(34, 70, 74),
	SWITCH_KNOB_OFF = Color3.fromRGB(153, 153, 173),
	-- A reset button with nothing to reset, as he dimmed it.
	RESET_IDLE_TRANSPARENCY = 0.56,
})

local Controls = {}

Controls.Layout = Layout

Controls.Spring = Hand.Spring
Controls.Hand = Hand.Track

-- His slider: a pale track, the pink fill, a white knob and the value at its right end. `counted` is 0 to 1 as the
-- row is dealt in, so the fill and the number run up to the value; `props` places the track's middle.
function Controls.Slider(
	row: Types.TVolumeRow,
	actions: Types.TActions,
	counted: () -> number,
	props: { [any]: any }
): TextButton
	local isHovered = source(false)
	local track: Frame? = nil
	-- The touch that holds the knob, or true for the mouse; and what follows it while it is held.
	local held: (InputObject | boolean)? = nil
	local moved: RBXScriptConnection? = nil
	local ended: RBXScriptConnection? = nil

	-- Under the hand the fill is the hand; let go, it glides to where a reset or the server put it.
	local glided = Controls.Spring(function()
		return row.Value()
	end, Timing.GLIDE_PERIOD)
	local percent = function(): number
		local value = if row.IsDragging() then row.Value() else glided()
		return math.clamp(value, 0, SettingsCore.MAX_VOLUME) * counted()
	end
	-- Both in the steps they are drawn in, so a glide rewrites the fill once a pixel and the number once a percent.
	local filled = vide.derive(function(): number
		return math.round(Layout.TRACK.X * percent() / SettingsCore.MAX_VOLUME)
	end)
	local shown = vide.derive(function(): number
		return math.round(percent())
	end)
	local grip = Controls.Spring(function()
		return if row.IsDragging() then Timing.KNOB_HELD elseif isHovered() then Timing.KNOB_HOVER else 1
	end, Timing.KNOB_PERIOD, 0.8)
	local glow = Controls.Spring(function()
		return if row.IsDragging() then 1 else 0
	end, Timing.KNOB_PERIOD)

	local function follow(x: number)
		local bar = track
		if not bar then return end
		local along = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
		actions.DragVolume(row, math.round(along * SettingsCore.MAX_VOLUME))
	end

	local function release()
		if not held then return end
		held = nil
		if moved then moved:Disconnect() end
		if ended then ended:Disconnect() end
		moved, ended = nil, nil
		actions.ReleaseVolume(row)
	end

	-- The hand may leave the slider while it holds the knob, so the move and the release are heard everywhere, and
	-- only while it holds it.
	local function grab(input: InputObject)
		local isMouse = input.UserInputType == Enum.UserInputType.MouseButton1
		if held or (not isMouse and input.UserInputType ~= Enum.UserInputType.Touch) then return end
		held = if isMouse then true else input
		moved = UserInputService.InputChanged:Connect(function(changed: InputObject)
			local isHeld = if isMouse
				then changed.UserInputType == Enum.UserInputType.MouseMovement
				else changed == input
			if isHeld then follow(changed.Position.X) end
		end)
		ended = UserInputService.InputEnded:Connect(function(finished: InputObject)
			local isHeld = if isMouse
				then finished.UserInputType == Enum.UserInputType.MouseButton1
				else finished == input
			if isHeld then release() end
		end)
		follow(input.Position.X)
	end

	vide.cleanup(release)

	return create("TextButton")({
		Name = "Slider",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(Layout.TRACK.X + 2 * Layout.SLIDER_REACH, Layout.SLIDER_HEIGHT),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 3,
		-- The hover only: dragging the menu volume plays its own clicks (SettingsController), and a click on release
		-- would double them.
		MouseEnter = function()
			isHovered(true)
			SoundsCore.PlayHover()
		end,
		MouseLeave = function()
			isHovered(false)
		end,
		InputBegan = grab,
		create("Frame")({
			Name = "Track",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(Layout.TRACK.X, Layout.TRACK.Y),
			BackgroundColor3 = Palette.White,
			BackgroundTransparency = Look.TRACK_TRANSPARENCY,
			BorderSizePixel = 0,
			vide.action(function(instance: Instance)
				track = instance :: Frame
			end),
			create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
		}),
		create("Frame")({
			Name = "Fill",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, Layout.SLIDER_REACH, 0.5, 0),
			Size = function()
				return UDim2.fromOffset(filled(), Layout.TRACK.Y)
			end,
			BackgroundColor3 = Palette.Pink,
			BorderSizePixel = 0,
			create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
		}),
		create("Frame")({
			Name = "Knob",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				return UDim2.new(0, Layout.SLIDER_REACH + filled(), 0.5, 0)
			end,
			Size = UDim2.fromOffset(Layout.KNOB.X, Layout.KNOB.Y),
			BackgroundColor3 = Palette.White,
			BorderSizePixel = 0,
			ZIndex = 2,
			create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			create("UIScale")({ Scale = grip }),
			create("UIShadow")({
				Name = "Glow",
				BlurRadius = UDim.new(0, 16),
				Color = Palette.Pink,
				Spread = UDim2.new(),
				Transparency = function()
					return 1 - Timing.KNOB_GLOW * glow()
				end,
				ZIndex = -1,
			}),
		}),
		create("TextLabel")({
			Name = "Value",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(0, Layout.VALUE_RIGHT, 0.5, 0),
			Size = UDim2.fromOffset(60, Layout.VALUE_SIZE),
			BackgroundTransparency = 1,
			FontFace = Font.Display,
			TextSize = Layout.VALUE_SIZE,
			TextColor3 = Palette.White,
			TextXAlignment = Enum.TextXAlignment.Right,
			Text = function()
				return tostring(shown())
			end,
		}),
		props,
	}) :: TextButton
end

-- His switch: a thin edge round a dim face and a square knob, grey and to the left when off, green and to the right
-- when on. `props` places its middle.
function Controls.Switch(
	state: Types.TSettingsState,
	row: Types.TToggleRow,
	actions: Types.TActions,
	props: { [any]: any }
): TextButton
	local events, isHovered, isPressed = Controls.Hand()
	local on = Controls.Spring(function()
		return if row.IsOn() then 1 else 0
	end, Timing.SWITCH_PERIOD, Timing.SWITCH_DAMPING)
	local scale = Controls.Spring(function()
		return if isPressed() then 0.94 elseif isHovered() then 1.05 else 1
	end, Timing.PRESS_PERIOD, 0.85)
	-- 0 to 1 after it is turned ON by hand; 1 otherwise, where the ring is not there.
	local ring = vide.derive(function(): number
		if not row.IsOn() then return 1 end
		return Motion.Progress(state.Now(), row.ChangedAt(), Timing.RING)
	end)
	local edge = Layout.SWITCH_EDGE
	local lit = function(): number
		return math.clamp(on(), 0, 1)
	end

	return Components.Button({
		Name = "Switch",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(Layout.SWITCH.X, Layout.SWITCH.Y),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Activated = function()
			actions.SetToggle(row, not row.IsOn())
		end,
		events,
		create("UIScale")({ Scale = scale }),
		create("Frame")({
			Name = "Ring",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = function()
				local grow = 2 * Timing.RING_GROW * Motion.Out(ring())
				return UDim2.new(1, grow, 1, grow)
			end,
			BackgroundTransparency = 1,
			create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
			create("UIStroke")({
				Color = Palette.Green,
				Thickness = 1.5,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Transparency = function()
					return Lerp(0.2, 1, Motion.Out(ring()))
				end,
			}),
		}),
		-- The edge is a stroke round a face inset by it: at 1.5 px it is not a whole pixel to inset a second frame by.
		create("Frame")({
			Name = "Face",
			Position = UDim2.fromOffset(edge, edge),
			Size = UDim2.new(1, -2 * edge, 1, -2 * edge),
			BorderSizePixel = 0,
			BackgroundColor3 = function()
				return Look.SWITCH_FACE_OFF:Lerp(Look.SWITCH_FACE_ON, lit())
			end,
			create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			create("UIStroke")({
				Thickness = edge,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = function()
					return Look.SWITCH_EDGE_OFF:Lerp(Look.SWITCH_EDGE_ON, lit())
				end,
			}),
		}),
		create("Frame")({
			Name = "Knob",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				return UDim2.new(0, Lerp(Layout.SWITCH_OFF_X, Layout.SWITCH_ON_X, on()), 0.5, 0)
			end,
			Size = function()
				local stretch = Timing.SWITCH_STRETCH * Motion.Bump(lit())
				return UDim2.fromOffset(Layout.SWITCH_KNOB.X + stretch, Layout.SWITCH_KNOB.Y)
			end,
			BorderSizePixel = 0,
			ZIndex = 2,
			BackgroundColor3 = function()
				return Look.SWITCH_KNOB_OFF:Lerp(Palette.Green, lit())
			end,
			create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
		}),
		props,
	}) :: TextButton
end

-- The reset button a row ends in: his small dark panel with the turning arrow, dim while the row is at its default
-- and gold once it has left it. `isChanged` is whether there is anything to reset, `resetAt` the os.clock it last
-- was. `props` places its middle.
function Controls.Reset(
	state: Types.TSettingsState,
	isChanged: () -> boolean,
	resetAt: () -> number,
	onReset: () -> (),
	props: { [any]: any }
): CanvasGroup
	local events, isHovered, isPressed = Controls.Hand()
	local lit = Controls.Spring(function()
		return if isChanged() then 1 else 0
	end, Timing.LIT_PERIOD)
	local hover = Controls.Spring(function()
		return if isHovered() and isChanged() then 1 else 0
	end, Timing.HOVER_PERIOD)
	local scale = Controls.Spring(function()
		if not isChanged() then return 1 end
		return if isPressed() then 0.9 elseif isHovered() then 1.08 else 1
	end, Timing.PRESS_PERIOD, 0.85)
	-- Derived, like every gesture read off the clock here: once it is over, the clock ticking for another row
	-- redraws nothing. The arrow points back round to the left, so that is the way it turns.
	local spin = vide.derive(function(): number
		return -360 * Motion.Decelerate(Motion.Progress(state.Now(), resetAt(), Timing.SPIN))
	end)
	local margin = Layout.RESET_MARGIN

	return create("CanvasGroup")({
		Name = "Reset",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(Layout.RESET + 2 * margin, Layout.RESET + 2 * margin),
		BackgroundTransparency = 1,
		ZIndex = 4,
		GroupTransparency = function()
			return Lerp(Look.RESET_IDLE_TRANSPARENCY, 0, math.clamp(lit(), 0, 1))
		end,
		Components.Button({
			Name = "Button",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(Layout.RESET, Layout.RESET),
			BackgroundTransparency = 1,
			Interactable = isChanged,
			Activated = function()
				if isChanged() then onReset() end
			end,
			events,
			create("UIScale")({ Scale = scale }),
			Components.Panel({
				Stroke = function()
					return Palette.EdgePink:Lerp(Palette.Pink, hover())
				end,
			}, {
				Name = "Face",
				Size = UDim2.fromScale(1, 1),
				Components.Picture(EIcons.Replay, {
					Name = "Arrow",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = Components.PictureBox(Layout.RESET_GLYPH),
					ZIndex = 2,
					ImageColor3 = function()
						return Palette.Lavender:Lerp(Palette.Gold, math.clamp(lit(), 0, 1))
					end,
					Rotation = spin,
				}),
			}),
		}),
		props,
	})
end

-- A glossy red slab with the turning arrow and a word (RESET ALL, the confirm's RESET). `isEnabled` false is the grey
-- slab that cannot be pressed. `props` places its middle and sizes it.
function Controls.ResetSlab(
	text: string,
	isEnabled: () -> boolean,
	onActivated: () -> (),
	props: { [any]: any }
): TextButton
	local events, isHovered, isPressed = Controls.Hand()
	local hover = Controls.Spring(function()
		return if isHovered() and isEnabled() then 1 else 0
	end, Timing.HOVER_PERIOD)
	local scale = Controls.Spring(function()
		if not isEnabled() then return 1 end
		return if isPressed() then 0.96 elseif isHovered() then 1.03 else 1
	end, Timing.PRESS_PERIOD, 0.85)
	local ink = function(): number
		return if isEnabled() then 0 else 0.5
	end

	return Components.Button({
		Name = "ResetSlab",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Interactable = isEnabled,
		Activated = function()
			if isEnabled() then onActivated() end
		end,
		events,
		create("UIScale")({ Scale = scale }),
		Components.Slab({
			Kind = function()
				return if isEnabled() then "Red" else "Off"
			end,
			Marks = true,
			Brackets = true,
			GlowTransparency = function()
				return Lerp(0.6, 0.35, hover())
			end,
		}, {
			Name = "Face",
			Size = UDim2.fromScale(1, 1),
			create("Frame")({
				Name = "Words",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ZIndex = 3,
				create("UIListLayout")({
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, Layout.SLAB_GAP),
				}),
				Components.Picture(EIcons.Replay, {
					Size = Components.PictureBox(Layout.SLAB_GLYPH),
					ImageColor3 = Palette.White,
					ImageTransparency = ink,
					LayoutOrder = 1,
				}),
				create("TextLabel")({
					Size = UDim2.fromOffset(0, Layout.SLAB_TEXT_SIZE),
					AutomaticSize = Enum.AutomaticSize.X,
					BackgroundTransparency = 1,
					FontFace = Font.Display,
					TextSize = Layout.SLAB_TEXT_SIZE,
					TextColor3 = Palette.White,
					TextTransparency = ink,
					Text = text,
					LayoutOrder = 2,
				}),
			}),
		}),
		props,
	}) :: TextButton
end

return Controls
