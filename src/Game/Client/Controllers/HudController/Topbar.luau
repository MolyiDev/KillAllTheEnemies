--!nonstrict
-- The designer's Squad and Settings buttons (UIMatt.md, In-Game HUD) drawn inside TopbarPlus icons: his panel with
-- its streaks, stroke and corner brackets behind the icon's own image and label. The widget clips, so the brackets
-- stand inside its box rather than past it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Types = require(script.Parent.Types)

local create = vide.create
local spring = vide.spring
local Palette = Theme.Palette

-- Px in the topbar (unscaled): the panel stands this far inside the icon's box, its brackets one px short of it.
local INSET = 5
local BRACKET_LENGTH = 10
-- The press goes in at once and comes back over this long.
local PRESS_SECONDS = 0.24
local PRESS_DEPTH = 0.08
-- The light answers the hand quickly; nothing about it bounces.
local HOVER_PERIOD = 0.12

local Topbar = {}

-- The theme every skinned icon wears: TopbarPlus's own button face and hover wash off, white ink in every state, and
-- room for the panel's edge on both sides. A fresh list each call: TopbarPlus keeps and edits the tables it is handed.
function Topbar.Theme(): { { any } }
	return {
		{ "IconButton", "BackgroundTransparency", 1 },
		{ "IconOverlay", "BackgroundTransparency", 1 },
		{ "IconLabel", "TextColor3", Palette.White, "Selected" },
		{ "IconImage", "ImageColor3", Palette.White, "Selected" },
		{ "IconLabel", "TextSize", 15 },
		{ "PaddingLeft", "Size", UDim2.new(0, 14, 1, 0) },
		{ "PaddingRight", "Size", UDim2.new(0, 16, 1, 0) },
	}
end

-- The panel behind one icon. `skin` is the icon's hand state, written by init from its signals.
function Topbar.Skin(state: Types.THudState, skin: Types.TTopbarSkin): Frame
	local isLit = function()
		return skin.IsHovered() or skin.IsSelected()
	end

	local lit, configure = spring(function()
		return if isLit() then 1 else 0
	end, HOVER_PERIOD, 1)
	-- Pinned on each change of target, or a spring heading back to 0 never settles (UI.md 5g).
	vide.effect(function()
		isLit()
		vide.untrack(function()
			configure({ position = lit() })
		end)
	end)

	return create("Frame")({
		Name = "Skin",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 0,
		create("Frame")({
			Name = "Body",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -2 * INSET, 1, -2 * INSET),
			BackgroundTransparency = 1,
			create("UIScale")({
				Scale = function()
					return 1 - PRESS_DEPTH * Motion.Fade(state.Now(), skin.PressedAt(), PRESS_SECONDS)
				end,
			}),
			-- His dark drop shadow at rest, warming to a pink glow under the hand.
			Components.Panel({
				Stroke = function()
					return Palette.EdgePink:Lerp(Palette.Pink, lit())
				end,
				Glow = function()
					return Color3.new():Lerp(Palette.Pink, lit())
				end,
				GlowTransparency = function()
					return 0.6 - 0.1 * lit()
				end,
			}, {
				Name = "Face",
				Size = UDim2.fromScale(1, 1),
				if skin.HasBrackets
					then Components.Brackets(INSET - 1, function()
						return 0.6 - 0.3 * lit()
					end, BRACKET_LENGTH)
					else nil,
			}),
		}),
	})
end

return Topbar
