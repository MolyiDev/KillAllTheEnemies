--!nonstrict
-- What lies over the play: the edge flashed on a hit, a wave done or being down, and the shock of going down.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local UiFade = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.UiFade)
local Types = require(script.Parent.Types)

local create = vide.create

-- The edge's own layer: over the upgrade pick's screen (10), which the HUD gives way to, since the cards are dealt as
-- the wave ends and its green greets them. Under the crosshair (1000).
local VIGNETTE_DISPLAY_ORDER = 11
-- The shock's dim: under the HUD's roots (-2 and up), so YOU DIED stands sharp on it. Its darkest.
local SHOCK_DISPLAY_ORDER = -3
local SHOCK_DIM = 0.72

local Overlays = {}

-- One edge of the vignette: its colour fading from the screen's edge inward.
local function edge(state: Types.THudState, rotation: number, props: { [any]: any }): Frame
	return create("Frame")({
		BackgroundColor3 = state.VignetteColor,
		BorderSizePixel = 0,
		BackgroundTransparency = function()
			return 1 - state.Vignette()
		end,
		Visible = function()
			return state.Vignette() > 0
		end,
		create("UIGradient")({
			Rotation = rotation,
			Transparency = NumberSequence.new(0, 1),
		}),
		props,
	})
end

function Overlays.Vignette(state: Types.THudState): ScreenGui
	return create("ScreenGui")({
		Name = "Vignette",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = VIGNETTE_DISPLAY_ORDER,
		Enabled = UiFade.IsUp,
		UiFade.Group({
			edge(state, 0, { Size = UDim2.fromScale(0.16, 1) }),
			edge(
				state,
				180,
				{ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(0.16, 1) }
			),
			edge(state, 90, { Size = UDim2.fromScale(1, 0.2) }),
			edge(
				state,
				270,
				{ AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0.2) }
			),
		}),
	})
end

-- The screen dimmed black by the shock of going down, clearing as the camera reaches a squadmate. A boss's intro fades
-- it with every screen's UI.
function Overlays.Shock(state: Types.THudState): ScreenGui
	return create("ScreenGui")({
		Name = "Shock",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = SHOCK_DISPLAY_ORDER,
		Enabled = function()
			return UiFade.IsUp() and state.Shock() > 0
		end,
		UiFade.Group({
			create("Frame")({
				Name = "Dim",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Color3.new(),
				BorderSizePixel = 0,
				BackgroundTransparency = function()
					return 1 - SHOCK_DIM * state.Shock()
				end,
			}),
		}),
	})
end

return Overlays
