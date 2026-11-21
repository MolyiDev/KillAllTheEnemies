--!nonstrict
-- The board over each pad: how full it is and how long until it leaves, and nothing else; the pad's own colour
-- (PadArt) says whether this player can step on. Sized in studs, so it is a sign in the world that shrinks with
-- distance, not a label that stays the same size on screen.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local PadsCore = require(ReplicatedStorage.Shared.Core.PadsCore)
local Types = require(script.Parent.Types)

local create = vide.create
local Color = Theme.Color
local Font = Theme.Font
local Text = Components.Text
local EPhase = PadsCore.EPhase

local WIDTH_STUDS = 7
local HEIGHT_STUDS = 5
-- Over the pad's top face, to the board's centre.
local RISE_STUDS = 6.5
local MAX_DISTANCE_STUDS = 160
-- Ink round the letters, in pixels: the board is drawn at its on-screen size, so this is fixed, not a share.
local INK_THICKNESS = 2

local PadBoard = {}

local function ink(): UIStroke
	return create("UIStroke")({
		Color = Color.Ink,
		Thickness = INK_THICKNESS,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Miter,
	})
end

local function board(pad: Types.TPadView): BillboardGui
	return create("BillboardGui")({
		Name = `PadBoard{pad.Index}`,
		Adornee = pad.Part,
		Size = UDim2.fromScale(WIDTH_STUDS, HEIGHT_STUDS),
		StudsOffsetWorldSpace = Vector3.new(0, pad.Part.Size.Y / 2 + RISE_STUDS, 0),
		MaxDistance = MAX_DISTANCE_STUDS,
		LightInfluence = 0,
		ResetOnSpawn = false,
		Text({
			Size = UDim2.fromScale(1, 0.6),
			FontFace = Font.Heavy,
			TextScaled = true,
			Text = function()
				return `{pad.Count()}/{pad.MaxPlayers()}`
			end,
			ink(),
		}),
		Text({
			Position = UDim2.fromScale(0, 0.6),
			Size = UDim2.fromScale(1, 0.4),
			FontFace = Font.Heavy,
			TextScaled = true,
			TextColor3 = function()
				return if pad.Count() >= pad.MaxPlayers() then Color.Gold else Color.Text
			end,
			Visible = function()
				return pad.Phase() == EPhase.Open and pad.Seconds() >= 0
			end,
			Text = function()
				return `{pad.Seconds()}s`
			end,
			ink(),
		}),
	})
end

function PadBoard.Build(state: Types.TLobbyState): { BillboardGui }
	local boards = table.create(#state.Pads)
	for index, pad in state.Pads do
		boards[index] = board(pad)
	end

	return boards
end

return PadBoard
