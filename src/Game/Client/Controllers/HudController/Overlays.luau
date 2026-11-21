--!nonstrict
-- What lies over the play: the red edge on a hit, the downed card with the paid revive, and the results. The downed
-- card ends above the hotbar (Hotbar.HEIGHT).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
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
-- Seconds for a card to fade in or out.
local FADE_PERIOD = 0.3

local Overlays = {}

-- One edge of the vignette: its colour fading from the screen's edge inward.
local function edge(state: Types.THudState, rotation: number, props: { [any]: any }): Frame
	return create("Frame")({
		BackgroundColor3 = Color.Hurt,
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

function Overlays.Vignette(state: Types.THudState): Frame
	return create("Frame")({
		Name = "Vignette",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 0,
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
	local isHovered = vide.source(false)
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
			Components.Button({
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -14),
				Size = UDim2.fromOffset(220, 44),
				BackgroundColor3 = function()
					return if isHovered() then Color.ActionEdge else Color.Action
				end,
				Visible = state.IsReviveOffered,
				Activated = actions.Revive,
				MouseEnter = function()
					isHovered(true)
				end,
				MouseLeave = function()
					isHovered(false)
				end,
				Components.Edge(Color.ActionEdge),
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

local function statRow(order: number, label: string, color: Color3, value: () -> string): Frame
	return create("Frame")({
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundTransparency = 1,
		Text({
			Size = UDim2.fromScale(0.6, 1),
			TextXAlignment = Enum.TextXAlignment.Left,
			FontFace = Font.Mono,
			TextSize = 15,
			TextColor3 = Color.Muted,
			Text = label,
		}),
		Text({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromScale(0.4, 1),
			TextXAlignment = Enum.TextXAlignment.Right,
			FontFace = Font.Heavy,
			TextSize = 22,
			TextColor3 = color,
			Text = value,
		}),
	})
end

function Overlays.Results(state: Types.THudState): CanvasGroup
	return card(function()
		return state.Phase() == "Ended"
	end, {
		Name = "Results",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 10,
		-- The world dims behind it: the run is over and this is the only thing to read.
		create("Frame")({
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color.Ink,
			BackgroundTransparency = 0.4,
			BorderSizePixel = 0,
		}),
		Block({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.45),
			Size = UDim2.fromOffset(440, 320),
			create("Frame")({
				Size = UDim2.new(1, 0, 0, 64),
				BackgroundColor3 = Color.Action,
				BorderSizePixel = 0,
				Text({
					Size = UDim2.fromScale(1, 1),
					FontFace = Font.Mono,
					TextSize = 36,
					TextColor3 = Color.Ink,
					Text = "RUN OVER",
				}),
			}),
			Text({
				Position = UDim2.fromOffset(0, 78),
				Size = UDim2.new(1, 0, 0, 24),
				TextSize = 20,
				Text = function()
					local rounds = state.RoundsCleared()
					return if rounds == 1 then "Survived 1 wave" else `Survived {rounds} waves`
				end,
			}),
			create("Frame")({
				Position = UDim2.fromOffset(36, 118),
				Size = UDim2.new(1, -72, 0, 108),
				BackgroundTransparency = 1,
				create("UIListLayout")({ Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
				statRow(1, "GOLD EARNED", Color.Gold, function()
					return `${Components.Commas(state.RunGold())}`
				end),
				statRow(2, "GEMS EARNED", Color.Gem, function()
					return Components.Commas(state.RunGems())
				end),
			}),
			Text({
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 0, 1, -18),
				Size = UDim2.new(1, 0, 0, 18),
				FontFace = Font.Mono,
				TextSize = 14,
				TextColor3 = Color.Muted,
				Text = function()
					return `BACK TO THE LOBBY IN {state.ReturnIn()}S`
				end,
			}),
		}),
	})
end

return Overlays
