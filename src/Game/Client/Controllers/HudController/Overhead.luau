--!nonstrict
-- The player's own health over his head, a BillboardGui holding the designer's bar (HealthBar). No number on it: GDD 9
-- and 16 forbid numeric HP over heads. In first person the head is the camera, so this hides and Hotbar shows the bar
-- instead.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.vide)
local HealthBar = require(script.Parent.HealthBar)
local Types = require(script.Parent.Types)

local create = vide.create

-- His bar over the character, in px at a 1080-tall screen; the billboard draws in screen pixels, so it takes the HUD's
-- scale by hand.
local WIDTH = 200
local HEIGHT = 22
-- Above the head's centre: half the 1.2-stud head, and air.
local OFFSET = Vector3.new(0, 1.9, 0)

local Overhead = {}

function Overhead.Build(state: Types.THudState): BillboardGui
	return create("BillboardGui")({
		Name = "OwnHealth",
		ResetOnSpawn = false,
		AlwaysOnTop = true,
		LightInfluence = 0,
		StudsOffsetWorldSpace = OFFSET,
		Adornee = state.Head,
		Size = function()
			local scale = state.Scale()
			return UDim2.fromOffset(math.round(WIDTH * scale), math.round(HEIGHT * scale))
		end,
		Enabled = function()
			return state.Head() ~= nil and not state.IsFirstPerson() and not state.IsDown() and state.Phase() ~= "Ended"
		end,
		-- Sized 1 / scale so that after its UIScale it fills the billboard, with the bar's px in design px.
		create("Frame")({
			Name = "Root",
			BackgroundTransparency = 1,
			Size = function()
				local scale = state.Scale()
				return UDim2.fromScale(1 / scale, 1 / scale)
			end,
			create("UIScale")({ Scale = state.Scale }),
			HealthBar.Build(state, { Size = UDim2.fromScale(1, 1) }),
		}),
	})
end

return Overhead
