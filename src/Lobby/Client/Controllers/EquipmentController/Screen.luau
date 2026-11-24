--!nonstrict
-- The equipment page on his 1920 x 1080, inside the classes screen's root: the grid on the left (Grid), the avatar's
-- stage and WEARING in the middle (Stage), the picked piece on the right (Info). Drawn only while on show or leaving.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local vide = require(ReplicatedStorage.Packages.vide)
local Grid = require(script.Parent.Grid)
local Info = require(script.Parent.Info)
local Parts = require(script.Parent.Parts)
local Stage = require(script.Parent.Stage)
local Types = require(script.Parent.Types)

local create = vide.create
local source = vide.source

local Screen = {}

function Screen.Build(state: Types.TEquipmentState, actions: Types.TEquipmentActions): { Instance }
	local isDrawn = Parts.IsDrawn(state)

	-- The preview's own clock: seconds since the page came up, written every frame only while it is up, for the sway of
	-- the piece on show. Its own, so the sway never keeps the gestures' clock ticking.
	local sway = source(0)
	local ticker: RBXScriptConnection? = nil
	vide.effect(function()
		local isShown = state.IsShown()
		vide.untrack(function()
			if isShown and not ticker then
				local from = os.clock()
				ticker = RunService.PreRender:Connect(function()
					sway(os.clock() - from)
				end)
			elseif not isShown and ticker then
				ticker:Disconnect()
				ticker = nil
			end
		end)
	end)
	vide.cleanup(function()
		if ticker then ticker:Disconnect() end
	end)

	return {
		create("Frame")({
			Name = "Equipment",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Visible = isDrawn,
			Stage.Build(state, actions),
			Grid.Build(state, actions),
			Info.Build(state, actions, sway),
		}),
	}
end

return Screen
