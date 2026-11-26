--!nonstrict
-- The player's health bar as the designer drew it over his character (UIMatt.md, In-Game HUD, Player Container): a
-- black rim, a dark well, one green fill cut into cells by darker lines, the damage just taken left white behind it.
-- px are design px at 1080 (his art is drawn at twice that). It moves as the boss's bar does (BarJuice): a blow
-- flashes the fill, lights its cut and throws chips off it, and health given back runs ahead of the fill in pale
-- green.
-- A cell is CELL health, so his ten are the base 100 and a bought HEALTH level adds cells: the bar keeps its length
-- and its cells narrow to make room (state.BarMax). As a bought level lands (state.Vital.LandAt) the bar is struck
-- white, thumps, throws a ring and its new cells cool from white.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local EquipmentCore = require(ReplicatedStorage.GlobalShared.Core.EquipmentCore)
local healthUpgrades = require(ReplicatedStorage.Shared.Utils.healthUpgrades)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local BarJuice = require(script.Parent.BarJuice)
local Types = require(script.Parent.Types)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette

-- Health a cell, and the most cells a bar can have: every HEALTH level bought, on the most the equipment can add.
local CELL = 10
local MAX_CELLS = math.ceil(
	(healthUpgrades.BASE + healthUpgrades.GAIN * healthUpgrades.MAX_LEVEL + EquipmentCore.MOST_MAX_HEALTH) / CELL
)
local RIM = 2
-- The well showing between the rim and the fill.
local GAP = 1
local DIVIDER = 2
local WELL = Color3.fromRGB(12, 10, 28)
local RIM_COLOR = Color3.new()
-- A divider is the fill this much darker: his (30, 104, 73) on (51, 217, 128).
local DIVIDER_SHADE = 0.47
local TRAIL_DIVIDER = Color3.fromRGB(150, 150, 160)
-- Health being given back, ahead of the fill.
local GIVEN = Palette.Green:Lerp(Palette.White, 0.55)
-- The lit edge where the fill ends, as a blow lands.
local CUT = 2
-- A bought level landing: how long the blow lasts and the new cells take to cool, how white the bar goes, how much
-- it grows for the blow, how far the ring it throws runs (px past the bar, each side) and how white its new cells
-- start.
local STRIKE_SECONDS = 0.45
local CELLS_SECONDS = 0.8
local STRIKE_FLASH = 0.85
local STRIKE_THUMP = 0.14
local ECHO_REACH = 16
local CELLS_FLASH = 0.9

local HealthBar = {}

function HealthBar.Build(state: Types.THudState, props: { [any]: any }): Frame
	local vital = state.Vital
	local track = state.HealthTrack
	local share = function(value: number): number
		local maxHealth = state.BarMax()
		return if maxHealth > 0 then math.clamp(value / maxHealth, 0, 1) else 0
	end

	-- Derived: every divider reads these, and they are worked out once a change.
	local fraction = derive(function(): number
		return share(track.Fill())
	end)
	local trail = derive(function(): number
		return share(math.max(track.Ghost(), track.Fill()))
	end)

	local flash, flare = BarJuice.Lights(state, track)

	-- Seconds since a bought level landed in the bar: negative while it is on its way, held at the landing's length
	-- once it is over. Derived, so the bar is not worked out again on the frames the clock runs for the card alone.
	local landed = derive(function(): number
		return math.min(vital.Clock() - vital.LandAt(), CELLS_SECONDS)
	end)

	-- 1 on the landing's frame, falling away: the blow.
	local strike = function(): number
		local t = landed()
		if t < 0 then return 0 end
		local k = Motion.Fade(t, 0, STRIKE_SECONDS)
		return k * k
	end

	-- The ring the blow throws: 0 to 1 as it runs out.
	local echo = function(): number
		return Motion.Progress(landed(), 0, STRIKE_SECONDS)
	end

	local cooling = function(): number
		local t = landed()
		return if t < 0 then 0 else Motion.Fade(t, 0, CELLS_SECONDS)
	end

	-- Green, souring to pink as it empties.
	local fillColor = derive(function(): Color3
		return Palette.Pink:Lerp(Palette.Green, math.clamp(fraction() * 1.6 - 0.3, 0, 1))
	end)

	local dividers = table.create(MAX_CELLS - 1)
	for index = 1, MAX_CELLS - 1 do
		local health = index * CELL
		-- Where this line stands along the bar, or past its end while the bar has no such cell.
		local at = function(): number
			local maxHealth = state.BarMax()
			return if maxHealth > health then health / maxHealth else 2
		end

		dividers[index] = create("Frame")({
			AnchorPoint = Vector2.new(0.5, 0),
			Position = function()
				return UDim2.fromScale(at(), 0)
			end,
			Size = UDim2.new(0, DIVIDER, 1, 0),
			BorderSizePixel = 0,
			ZIndex = 4,
			-- Only a line across the fill or the trail: over the empty well it would read as a cell still there.
			BackgroundColor3 = function()
				return if fraction() > at() then fillColor():Lerp(RIM_COLOR, DIVIDER_SHADE) else TRAIL_DIVIDER
			end,
			BackgroundTransparency = function()
				local where = at()
				return if trail() > where or fraction() > where then 0 else 1
			end,
		})
	end

	return create("Frame")({
		Name = "HealthBar",
		BackgroundColor3 = RIM_COLOR,
		BorderSizePixel = 0,
		create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
		create("UIScale")({
			Scale = function()
				return 1 + STRIKE_THUMP * strike()
			end,
		}),
		create("Frame")({
			Name = "Echo",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundTransparency = 1,
			ZIndex = 0,
			Visible = function()
				local k = echo()
				return k > 0 and k < 1
			end,
			Size = function()
				local reach = 2 * math.round(ECHO_REACH * Motion.Decelerate(echo()))
				return UDim2.new(1, reach, 1, reach)
			end,
			create("UICorner")({ CornerRadius = UDim.new(0, 6) }),
			create("UIStroke")({
				Color = Palette.Green,
				Thickness = 3,
				Transparency = function()
					return Motion.Out(echo())
				end,
			}),
		}),
		create("Frame")({
			Name = "Flash",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Palette.White,
			BorderSizePixel = 0,
			ZIndex = 5,
			BackgroundTransparency = function()
				return 1 - STRIKE_FLASH * strike()
			end,
			create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
		}),
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
						return UDim2.fromScale(trail(), 1)
					end,
					BackgroundColor3 = function()
						return if track.IsHealing() then GIVEN else Palette.White
					end,
					BorderSizePixel = 0,
				}),
				-- The cells a bought level added, at the bar's end: white as they arrive, cooling to what is under
				-- them (the fill where the body is that healthy, the well where it is not).
				create("Frame")({
					Name = "Gained",
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.fromScale(1, 0),
					BackgroundColor3 = Palette.White,
					BorderSizePixel = 0,
					ZIndex = 3,
					-- What the bar has grown past the max it had before the level: nothing as the level lands, the
					-- whole gain once the bar is its new length.
					Size = function()
						local before = state.MaxHealth() - healthUpgrades.GAIN
						return UDim2.fromScale(share(math.max(state.BarMax() - before, 0)), 1)
					end,
					BackgroundTransparency = function()
						return 1 - CELLS_FLASH * cooling()
					end,
				}),
				create("Frame")({
					Name = "Fill",
					Size = function()
						return UDim2.fromScale(fraction(), 1)
					end,
					BackgroundColor3 = fillColor,
					BorderSizePixel = 0,
					ZIndex = 2,
					create("Frame")({
						Name = "Hit",
						Size = UDim2.fromScale(1, 1),
						BackgroundColor3 = Palette.White,
						BorderSizePixel = 0,
						BackgroundTransparency = function()
							return 1 - 0.8 * flash()
						end,
					}),
				}),
				create("Frame")({
					Name = "Cut",
					AnchorPoint = Vector2.new(1, 0),
					Position = function()
						return UDim2.fromScale(fraction(), 0)
					end,
					Size = UDim2.new(0, CUT, 1, 0),
					BackgroundColor3 = Palette.White,
					BorderSizePixel = 0,
					ZIndex = 5,
					BackgroundTransparency = function()
						return if fraction() > 0 then 1 - flare() else 1
					end,
				}),
				dividers,
				BarJuice.Chips(state, track, {
					PerBlow = 5,
					SharePerChip = 0.02,
					Size = 5,
					SpeedMin = 90,
					SpeedMax = 170,
					Gravity = 160,
					Life = 0.5,
					Color = fillColor,
				}),
			}),
		}),
		props,
	})
end

return HealthBar
