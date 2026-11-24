--!nonstrict
-- The index screen on his 1920 x 1080: the lobby dimmed as his lobby screens dim it, the categories (Categories), the
-- enemy grid (Grid), the picked enemy's stage and info (Info) and EXIT. The HUD's pills stay up over it. Pieces arrive
-- staged by what the screen is for: the grid, then the categories and the stage, the info, and EXIT last.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Categories = require(script.Parent.Categories)
local Grid = require(script.Parent.Grid)
local Info = require(script.Parent.Info)
local Parts = require(script.Parent.Parts)
local Types = require(script.Parent.Types)

local create = vide.create

local Timing = table.freeze({
	-- His lobby screens dim the world this much (UIMatt.md section 2: 0.7 transparent).
	DIM = 0.3,
	EXIT_DELAY = 0.28,
})

local Screen = {}

function Screen.Build(state: Types.TIndexState, actions: Types.TIndexActions): { any }
	local elapsed = Parts.Elapsed(state)
	local dimFaded = Parts.Faded(state, elapsed, 0)

	return {
		-- Past the screen's edges whatever its shape, and it takes the clicks the pieces do not: this is a page, so a
		-- click on nothing shuts nothing.
		create("TextButton")({
			Name = "Dim",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(4, 4),
			BackgroundColor3 = Color3.new(),
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			BackgroundTransparency = function()
				return 1 - Timing.DIM * (1 - dimFaded())
			end,
		}),
		Categories.Build(state, actions, elapsed),
		Grid.Build(state, actions, elapsed),
		Info.Build(state, actions, elapsed),
		Components.Exit(Parts.Away(state, elapsed, Timing.EXIT_DELAY), actions.Close),
	}
end

return Screen
