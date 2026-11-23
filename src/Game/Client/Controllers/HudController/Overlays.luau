--!nonstrict
-- What lies over the play: the edge flashed on a hit or a wave done, and the downed card with the paid revive. The
-- downed card ends above the hotbar (Hotbar.HEIGHT).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Hotbar = require(script.Parent.Hotbar)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local Types = require(script.Parent.Types)

local create = vide.create
local spring = vide.spring
local Color = Theme.Color
local Font = Theme.Font
local Block = Components.Block
local Text = Components.Text

local DOWN_BOTTOM = Hotbar.HEIGHT + 24
-- The edge's own layer: over the upgrade pick's screen (10), which the HUD gives way to, since the cards are dealt as
-- the wave ends and its green greets them. Under the crosshair (1000).
local VIGNETTE_DISPLAY_ORDER = 11
-- Seconds for a card to fade in or out.
local FADE_PERIOD = 0.3

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
	})
end

-- A CanvasGroup that fades and grows in while `isShown`.
local function card(isShown: () -> boolean, props: { [any]: any }): CanvasGroup
	local shown = spring(function()
		return if isShown() then 1 else 0
	end, FADE_PERIOD, 1)
	return create("CanvasGroup")({
		BackgroundTransparency = 1,
		GroupTransparency = function()
			return 1 - shown()
		end,
		Visible = function()
			return shown() > 0.01
		end,
		create("UIScale")({
			Scale = function()
				return 0.94 + 0.06 * shown()
			end,
		}),
		props,
	})
end

function Overlays.Down(state: Types.THudState, actions: Types.TActions): CanvasGroup
	local hand = Hand.React("Operate")
	return card(function()
		return state.IsDown() and state.Phase() ~= "Ended"
	end, {
		Name = "Down",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -DOWN_BOTTOM),
		Size = UDim2.fromOffset(424, 164),
		Block({
			Position = UDim2.fromOffset(2, 2),
			Size = UDim2.new(1, -4, 1, -4),
			Components.Edge(Color.BossEdge),
			create("Frame")({
				Size = UDim2.new(1, 0, 0, 40),
				BackgroundColor3 = Color.Boss,
				BorderSizePixel = 0,
				Text({
					Size = UDim2.fromScale(1, 1),
					FontFace = Font.Mono,
					TextSize = 26,
					Text = "YOU'RE DOWN",
				}),
			}),
			Text({
				Position = UDim2.fromOffset(20, 48),
				Size = UDim2.new(1, -40, 0, 40),
				FontFace = Font.Medium,
				TextSize = 16,
				TextWrapped = true,
				TextColor3 = Color.Muted,
				Text = function()
					if state.IsReviveOffered() then return "Come back for the next wave." end
					if state.CanRevive then
						return "Your squad fights on. A revive is offered when the wave is cleared."
					end
					return "Your squad fights on."
				end,
			}),
			-- Placed by its middle, so it grows from there.
			Components.Button({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 1, -14 - 22),
				Size = UDim2.fromOffset(220, 44),
				BackgroundColor3 = function()
					return Color.Action:Lerp(Color.ActionEdge, hand.Light())
				end,
				Visible = state.IsReviveOffered,
				Activated = function()
					hand.Commit()
					actions.Revive()
				end,
				hand.Events,
				create("UIScale")({ Scale = hand.Scale }),
				Components.Edge(Color.ActionEdge),
				Hand.WashLayer(hand, 0),
				Components.Sheen(hand.Glint, 2),
				Text({
					Size = UDim2.fromScale(1, 1),
					FontFace = Font.Mono,
					TextSize = 22,
					TextColor3 = Color.Ink,
					Text = "REVIVE",
				}),
			}),
		}),
	})
end

return Overlays
