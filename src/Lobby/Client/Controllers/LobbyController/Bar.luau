--!nonstrict
-- The notice at the top for a pad that refused. EXIT and the queue's status are the queue screen's (Queue).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local Types = require(script.Parent.Types)

local create = vide.create
local spring = vide.spring
local Color = Theme.Color
local Font = Theme.Font
local Block = Components.Block
local Text = Components.Text

-- Below the platform's top bar (UI.md: 58 tall), centred, so it never meets it.
local TOAST_TOP = 72
local FADE_PERIOD = 0.25

local Bar = {}

local function toast(state: Types.TLobbyState): CanvasGroup
	local shown = spring(function()
		return if state.IsToastShown() then 1 else 0
	end, FADE_PERIOD, 1)

	return create("CanvasGroup")({
		Name = "Notice",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(0, TOAST_TOP) + UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(460, 52),
		BackgroundTransparency = 1,
		GroupTransparency = function()
			return 1 - shown()
		end,
		Visible = function()
			return shown() > 0.01
		end,
		Block({
			Position = UDim2.fromOffset(2, 2),
			Size = UDim2.new(1, -4, 1, -4),
			Components.Edge(Color.BossEdge),
			Text({
				Size = UDim2.fromScale(1, 1),
				FontFace = Font.Bold,
				TextSize = 20,
				Text = state.ToastText,
			}),
		}),
	})
end

function Bar.Build(state: Types.TLobbyState): { Instance }
	return { toast(state) }
end

return Bar
