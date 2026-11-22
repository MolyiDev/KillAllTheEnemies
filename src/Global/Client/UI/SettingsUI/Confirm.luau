--!nonstrict
-- The "RESET ALL SETTINGS?" modal over the settings screen (UIMatt.md, Settings - Reset Confirm): a second dim, his
-- panel with the warning tile, CANCEL and RESET. It comes forward out of the screen behind it, the tile throws one
-- ring, and the words and buttons rise in after it. A click on the dim is CANCEL.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(script.Parent.Parent.Components)
local Motion = require(script.Parent.Parent.Motion)
local Theme = require(script.Parent.Parent.Theme)
local Controls = require(script.Parent.Controls)
local Types = require(script.Parent.Types)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress
local Lerp = Motion.Lerp

-- His drawn rects in px at 1080, from the modal's top left corner.
local Layout = table.freeze({
	SIZE = Vector2.new(640, 420),
	TILE = Vector2.new(272, 32),
	TILE_SIZE = 95,
	WARNING_SIZE = 57,
	-- Centred, then this far right of it, as his is.
	TITLE_X = 3,
	TITLE_Y = 149,
	TITLE_SIZE = 41,
	BODY = Vector2.new(50, 202),
	BODY_SIZE = Vector2.new(540, 44),
	BODY_TEXT_SIZE = 22,
	CANCEL = Vector2.new(40, 320),
	CANCEL_SIZE = Vector2.new(268, 72),
	CANCEL_TEXT_SIZE = 27,
	RESET = Vector2.new(330, 319),
	RESET_SIZE = Vector2.new(270, 74),
	-- The room round the panel inside the group that fades it, for its shadow and brackets (a CanvasGroup clips).
	MARGIN = 48,
})

local Timing = table.freeze({
	-- The modal comes forward from a little small and goes back a little small, fading on the clock both ways.
	OPEN = 0.28,
	FADE = 0.2,
	FROM_SCALE = 0.94,
	CLOSE = 0.16,
	TO_SCALE = 0.97,
	DIM = 0.6,
	-- The tile lands, flares and throws its one ring; the words and the buttons rise in after it.
	TILE_DELAY = 0.06,
	TILE = 0.3,
	TILE_FROM = 0.8,
	RING_DELAY = 0.2,
	RING = 0.55,
	RING_GROW = 26,
	FLARE = 0.6,
	TITLE_DELAY = 0.1,
	BODY_DELAY = 0.15,
	BUTTONS_DELAY = 0.2,
	WORDS = 0.3,
	RISE = 10,
	-- Every gesture of an open or a shut is over by now.
	SETTLED = 1,
})

-- The warning's red, off his tile's edge and triangle.
local WARNING = Color3.fromRGB(230, 51, 64)
local WARNING_EDGE = Color3.fromRGB(205, 47, 61)
-- Broken where his is: left to wrap, the first line takes one word more.
local BODY_TEXT = "Audio, camera and profile settings will go back to\ntheir default values. This can't be undone."

local Confirm = {}

-- His red-edged square with the warning triangle and four brackets standing off it. `elapsed` is the seconds since
-- the modal was opened or shut.
local function tile(state: Types.TSettingsState, elapsed: () -> number): Frame
	local function since(delay: number, seconds: number): number
		if not state.IsConfirmOpen() then return 1 end
		return Progress(elapsed(), delay, seconds)
	end

	return create("Frame")({
		Name = "Tile",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(Layout.TILE.X + Layout.TILE_SIZE / 2, Layout.TILE.Y + Layout.TILE_SIZE / 2),
		Size = UDim2.fromOffset(Layout.TILE_SIZE, Layout.TILE_SIZE),
		BackgroundTransparency = 1,
		ZIndex = 2,
		create("Frame")({
			Name = "Ring",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = function()
				local grow = 2 * Timing.RING_GROW * Motion.Out(since(Timing.RING_DELAY, Timing.RING))
				return UDim2.new(1, grow, 1, grow)
			end,
			BackgroundTransparency = 1,
			create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
			create("UIStroke")({
				Color = WARNING,
				Thickness = 1.5,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Transparency = function()
					return Lerp(0.15, 1, Motion.Out(since(Timing.RING_DELAY, Timing.RING)))
				end,
			}),
		}),
		Components.Card({
			Accent = WARNING_EDGE,
			Edge = 2,
			Tint = 0.45,
			Glow = WARNING,
			Brackets = 6,
			BracketLength = 16,
			GlowTransparency = function()
				return Lerp(0.3, 0.6, Motion.Out(since(Timing.RING_DELAY, Timing.FLARE)))
			end,
		}, {
			Name = "Face",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			create("UIScale")({
				Scale = function()
					return Lerp(Timing.TILE_FROM, 1, Motion.Decelerate(since(Timing.TILE_DELAY, Timing.TILE)))
				end,
			}),
			Components.Icon("Warning", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0.5, -1),
				Size = Components.GlyphBox(Layout.WARNING_SIZE),
				ImageColor3 = WARNING,
				ZIndex = 3,
			}),
		}),
	})
end

-- His dark CANCEL: a quiet panel beside the red slab. Under the hand its edge and its word come alight.
local function cancelButton(actions: Types.TActions): TextButton
	local events, isHovered, isPressed = Controls.Hand()
	local hover = Controls.Spring(function()
		return if isHovered() then 1 else 0
	end, 0.18)
	local scale = Controls.Spring(function()
		return if isPressed() then 0.96 elseif isHovered() then 1.03 else 1
	end, 0.14, 0.85)

	return Components.Button({
		Name = "Cancel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(
			Layout.CANCEL.X + Layout.CANCEL_SIZE.X / 2,
			Layout.CANCEL.Y + Layout.CANCEL_SIZE.Y / 2
		),
		Size = UDim2.fromOffset(Layout.CANCEL_SIZE.X, Layout.CANCEL_SIZE.Y),
		BackgroundTransparency = 1,
		Activated = actions.CancelResetAll,
		events,
		create("UIScale")({ Scale = scale }),
		Components.Panel({
			Brackets = 5,
			Stroke = function()
				return Palette.EdgePink:Lerp(Palette.Pink, hover())
			end,
		}, {
			Name = "Face",
			Size = UDim2.fromScale(1, 1),
			create("TextLabel")({
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				FontFace = Font.Display,
				TextSize = Layout.CANCEL_TEXT_SIZE,
				Text = "CANCEL",
				ZIndex = 2,
				TextColor3 = function()
					return Palette.Lavender:Lerp(Palette.White, hover())
				end,
			}),
		}),
	}) :: TextButton
end

function Confirm.Build(state: Types.TSettingsState, actions: Types.TActions): Frame
	-- Seconds since the modal was opened or shut, held once every gesture is over.
	local elapsed = derive(function(): number
		return math.min(state.Now() - state.ConfirmToggledAt(), Timing.SETTLED)
	end)
	local shown = function(): number
		if state.IsConfirmOpen() then return Motion.Out(Progress(elapsed(), 0, Timing.FADE)) end
		return 1 - Progress(elapsed(), 0, Timing.CLOSE)
	end
	-- 0 to 1 as a piece's own gesture runs after the modal opens; all done while it shuts.
	local function since(delay: number, seconds: number): number
		if not state.IsConfirmOpen() then return 1 end
		return Progress(elapsed(), delay, seconds)
	end

	-- How far under its place a piece that rises in a beat after the modal still is, in px, and how faded.
	local function sunk(delay: number): number
		return math.round(Timing.RISE * (1 - Motion.Decelerate(since(delay, Timing.WORDS))))
	end
	local function faded(delay: number): number
		if not state.IsConfirmOpen() then return 1 - shown() end
		return 1 - Motion.Out(since(delay, Timing.WORDS))
	end

	return create("Frame")({
		Name = "Confirm",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Visible = function()
			return shown() > 0.001
		end,
		create("TextButton")({
			Name = "Dim",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(),
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			BackgroundTransparency = function()
				return 1 - Timing.DIM * shown()
			end,
			Activated = actions.CancelResetAll,
		}),
		create("Frame")({
			Name = "Window",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(Layout.SIZE.X, Layout.SIZE.Y),
			BackgroundTransparency = 1,
			ZIndex = 2,
			create("UIScale")({
				Scale = function()
					if state.IsConfirmOpen() then
						return Lerp(Timing.FROM_SCALE, 1, Motion.Decelerate(Progress(elapsed(), 0, Timing.OPEN)))
					end
					return Lerp(1, Timing.TO_SCALE, Motion.Accelerate(Progress(elapsed(), 0, Timing.CLOSE)))
				end,
			}),
			-- A press on the panel stops here. A Frame lets it through to the dim, which would cancel.
			create("TextButton")({
				Name = "Sink",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				AutoButtonColor = false,
				Text = "",
			}),
			create("CanvasGroup")({
				Name = "Chrome",
				Position = UDim2.fromOffset(-Layout.MARGIN, -Layout.MARGIN),
				Size = UDim2.new(1, 2 * Layout.MARGIN, 1, 2 * Layout.MARGIN),
				BackgroundTransparency = 1,
				GroupTransparency = function()
					return 1 - shown()
				end,
				-- Longer than half the streak texture: its window starts at the corner and it is tiled across.
				Components.Panel({ Brackets = 5, TexturePhase = Vector2.zero, Wide = true, Tall = true }, {
					Name = "Panel",
					Position = UDim2.fromOffset(Layout.MARGIN, Layout.MARGIN),
					Size = UDim2.new(1, -2 * Layout.MARGIN, 1, -2 * Layout.MARGIN),
					tile(state, elapsed),
				}),
			}),
			-- Words fade by their own ink; only the buttons, which are built of many pieces, need a group to fade in.
			create("TextLabel")({
				Name = "Title",
				Position = function()
					return UDim2.fromOffset(Layout.TITLE_X, Layout.TITLE_Y + sunk(Timing.TITLE_DELAY))
				end,
				Size = UDim2.new(1, 0, 0, Layout.TITLE_SIZE),
				BackgroundTransparency = 1,
				FontFace = Font.Display,
				TextSize = Layout.TITLE_SIZE,
				TextColor3 = Palette.White,
				Text = "RESET ALL SETTINGS?",
				ZIndex = 2,
				TextTransparency = function()
					return faded(Timing.TITLE_DELAY)
				end,
			}),
			create("TextLabel")({
				Name = "Body",
				Position = function()
					return UDim2.fromOffset(Layout.BODY.X, Layout.BODY.Y + sunk(Timing.BODY_DELAY))
				end,
				Size = UDim2.fromOffset(Layout.BODY_SIZE.X, Layout.BODY_SIZE.Y),
				BackgroundTransparency = 1,
				FontFace = Font.DisplayBold,
				TextSize = Layout.BODY_TEXT_SIZE,
				TextColor3 = Palette.Lavender,
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Top,
				Text = BODY_TEXT,
				ZIndex = 2,
				TextTransparency = function()
					return faded(Timing.BODY_DELAY)
				end,
			}),
			create("CanvasGroup")({
				Name = "Buttons",
				Position = function()
					return UDim2.fromOffset(-Layout.MARGIN, sunk(Timing.BUTTONS_DELAY) - Layout.MARGIN)
				end,
				Size = UDim2.new(1, 2 * Layout.MARGIN, 1, 2 * Layout.MARGIN),
				BackgroundTransparency = 1,
				ZIndex = 2,
				GroupTransparency = function()
					return faded(Timing.BUTTONS_DELAY)
				end,
				create("Frame")({
					Position = UDim2.fromOffset(Layout.MARGIN, Layout.MARGIN),
					Size = UDim2.new(1, -2 * Layout.MARGIN, 1, -2 * Layout.MARGIN),
					BackgroundTransparency = 1,
					cancelButton(actions),
					Controls.ResetSlab("RESET", state.IsConfirmOpen, actions.ConfirmResetAll, {
						Position = UDim2.fromOffset(
							Layout.RESET.X + Layout.RESET_SIZE.X / 2,
							Layout.RESET.Y + Layout.RESET_SIZE.Y / 2
						),
						Size = UDim2.fromOffset(Layout.RESET_SIZE.X, Layout.RESET_SIZE.Y),
					}),
				}),
			}),
		}),
	})
end

return Confirm
