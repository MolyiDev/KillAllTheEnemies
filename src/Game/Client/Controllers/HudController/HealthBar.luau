--!nonstrict
-- The player's health bar as the designer drew it over his character (UIMatt.md, In-Game HUD, Player Container): a
-- black rim, a dark well, one green fill cut into ten by darker lines, the damage just taken left white behind it.
-- Fills its parent; px are design px at 1080 (his art is drawn at twice that).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local Types = require(script.Parent.Types)

local create = vide.create
local Palette = Theme.Palette

local SEGMENTS = 10
local RIM = 2
-- The well showing between the rim and the fill.
local GAP = 1
local DIVIDER = 2
local WELL = Color3.fromRGB(12, 10, 28)
local RIM_COLOR = Color3.new()
-- A divider is the fill this much darker: his (30, 104, 73) on (51, 217, 128).
local DIVIDER_SHADE = 0.47
local TRAIL_DIVIDER = Color3.fromRGB(150, 150, 160)

local HealthBar = {}

function HealthBar.Build(state: Types.THudState, props: { [any]: any }): Frame
	local share = function(value: number): number
		local maxHealth = state.MaxHealth()
		return if maxHealth > 0 then math.clamp(value / maxHealth, 0, 1) else 0
	end

	local fraction = function()
		return share(state.Health())
	end

	-- Green, souring to pink as it empties.
	local fillColor = function()
		return Palette.Pink:Lerp(Palette.Green, math.clamp(fraction() * 1.6 - 0.3, 0, 1))
	end

	local dividers = table.create(SEGMENTS - 1)
	for index = 1, SEGMENTS - 1 do
		local at = index / SEGMENTS
		dividers[index] = create("Frame")({
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(at, 0),
			Size = UDim2.new(0, DIVIDER, 1, 0),
			BorderSizePixel = 0,
			ZIndex = 3,
			-- Only a line across the fill or the trail: over the empty well it would read as a cell still there.
			BackgroundColor3 = function()
				return if fraction() > at then fillColor():Lerp(RIM_COLOR, DIVIDER_SHADE) else TRAIL_DIVIDER
			end,
			BackgroundTransparency = function()
				return if share(state.TrailHealth()) > at or fraction() > at then 0 else 1
			end,
		})
	end

	return create("Frame")({
		Name = "HealthBar",
		BackgroundColor3 = RIM_COLOR,
		BorderSizePixel = 0,
		create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
		create("Frame")({
			Name = "Well",
			Position = UDim2.fromOffset(RIM, RIM),
			Size = UDim2.new(1, -2 * RIM, 1, -2 * RIM),
			BackgroundColor3 = WELL,
			BorderSizePixel = 0,
			create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
			create("Frame")({
				Name = "Track",
				Position = UDim2.fromOffset(GAP, GAP),
				Size = UDim2.new(1, -2 * GAP, 1, -2 * GAP),
				BackgroundTransparency = 1,
				create("Frame")({
					Name = "Trail",
					Size = function()
						return UDim2.fromScale(share(state.TrailHealth()), 1)
					end,
					BackgroundColor3 = Palette.White,
					BorderSizePixel = 0,
				}),
				create("Frame")({
					Name = "Fill",
					Size = function()
						return UDim2.fromScale(fraction(), 1)
					end,
					BackgroundColor3 = fillColor,
					BorderSizePixel = 0,
					ZIndex = 2,
				}),
				dividers,
			}),
		}),
		props,
	})
end

return HealthBar
