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
-- scale by hand. His 200 px are the base 100 health: the bar is this long a point of max health, so a bought HEALTH
-- level makes it longer.
local WIDTH_PER_HEALTH = 2
local HEIGHT = 22
-- Round the bar inside the billboard, which clips: for the bar's thump, the ring it throws as a level lands and the
-- chips a blow throws off it (the ones thrown down fly about 40).
local ROOM = 48

local Overhead = {}

-- Above the head's centre: half the 1.2-stud head, and air. The bar's middle stands here.
Overhead.OFFSET = Vector3.new(0, 1.9, 0)

function Overhead.Build(state: Types.THudState): BillboardGui
	return create("BillboardGui")({
		Name = "OwnHealth",
		ResetOnSpawn = false,
		AlwaysOnTop = true,
		LightInfluence = 0,
		StudsOffsetWorldSpace = Overhead.OFFSET,
		Adornee = state.Head,
		Size = function()
			local scale = state.Scale()
			local width = WIDTH_PER_HEALTH * state.BarMax() + 2 * ROOM
			return UDim2.fromOffset(math.round(width * scale), math.round((HEIGHT + 2 * ROOM) * scale))
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
			HealthBar.Build(state, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(1, -2 * ROOM, 1, -2 * ROOM),
			}),
		}),
	})
end

return Overhead
