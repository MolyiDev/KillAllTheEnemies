--!nonstrict
-- The designer's Squad and Settings buttons (UIMatt.md, In-Game HUD) drawn inside TopbarPlus icons: his panel with
-- its streaks, stroke and corner brackets behind the icon's own image and label. The widget clips, so the brackets
-- stand inside its box rather than past it. Worn by the HUD's icons and the lobby's.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Notice = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Notice)

local create = vide.create
local source = vide.source
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
-- An icon stepping aside (IsShown) shrinks into its own middle as it lifts this many px toward the screen's edge, and
-- comes back the same way, critically damped over about SHOW_PERIOD.
local SHOW_PERIOD = 0.3
local SHOW_LIFT = 10
-- The "!" (a Notice, as every lobby button wears): its side; its middle is on the panel's top right corner.
local BADGE = 26
-- While something waits: the glow lit this much, and the light crossing in CALL_SECONDS.
local CALL_GLOW = 0.6
local CALL_SECONDS = 0.7

-- How one icon is dressed. `Now` is the caller's UI clock, which only moves while the caller ticks it: a press hands
-- `OnPress` the os.clock it has come back by, and the caller keeps `Now` ticking until then.
export type TOptions = {
	IsSelected: () -> boolean,
	-- His Squad button wears corner brackets; his Settings button does not.
	HasBrackets: boolean,
	Now: () -> number,
	OnPress: (settledAt: number) -> (),
	-- Whether the icon is up; nil for always. Read as a vide source.
	IsShown: (() -> boolean)?,
	-- How many things wait behind the icon, worn as a "!" on its corner while above 0; nil for none. While above 0
	-- the icon also glows, and the light crosses it each time `CallAt` (an os.clock stamp on `Now`) is stamped. Read as
	-- vide sources.
	Count: (() -> number)?,
	CallAt: (() -> number)?,
}

local Topbar = {}

-- The theme every skinned icon wears: TopbarPlus's own button face and hover wash off, white ink in every state, and
-- room for the panel's edge on both sides. A fresh list each call: TopbarPlus keeps and edits the tables it is handed.
local function theme(): { { any } }
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

-- The panel behind one icon.
local function skinPanel(options: TOptions, isHovered: () -> boolean, pressedAt: () -> number): Frame
	local isLit = function()
		return isHovered() or options.IsSelected()
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
	local count = options.Count
	local callAt = options.CallAt
	local isCalling = vide.derive(function(): boolean
		return count ~= nil and count() > 0
	end)
	local calling = Hand.Spring(function(): number
		return if isCalling() then 1 else 0
	end, SHOW_PERIOD)
	local glowLight = function(): number
		return math.max(lit(), CALL_GLOW * calling())
	end
	local called = vide.derive(function(): number
		if not callAt or not isCalling() then return 1 end
		return Motion.Progress(options.Now(), callAt(), CALL_SECONDS)
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
					return 1 - PRESS_DEPTH * Motion.Fade(options.Now(), pressedAt(), PRESS_SECONDS)
				end,
			}),
			-- His dark drop shadow at rest, warming to a pink glow under the hand or while something waits.
			Components.Panel({
				Stroke = function()
					return Palette.EdgePink:Lerp(Palette.Pink, lit())
				end,
				Glow = function()
					return Color3.new():Lerp(Palette.Pink, glowLight())
				end,
				GlowTransparency = function()
					return 0.6 - 0.1 * glowLight()
				end,
			}, {
				Name = "Face",
				Size = UDim2.fromScale(1, 1),
				if callAt then Components.Sheen(called, 3) else nil,
				if options.HasBrackets
					then Components.Brackets(nil, function()
						return 0.6 - 0.3 * lit()
					end, BRACKET_LENGTH)
					else nil,
			}),
		}),
	})
end

-- An icon going out of the bar and coming back as `isShown` changes: it shrinks into its own middle as it lifts, and
-- leaves the bar only once it has shrunk away, so it never blinks; it is back in at once, still at nothing, and grows.
-- The UIScale it returns goes on the button.
local function stepAside(icon: any, button: Frame, isShown: () -> boolean): UIScale
	local shown = Hand.Spring(function()
		return if isShown() then 1 else 0
	end, SHOW_PERIOD)
	local isGone = vide.derive(function(): boolean
		return not isShown() and shown() < 0.01
	end)
	vide.effect(function()
		local gone = isGone()
		vide.untrack(function()
			icon:setEnabled(not gone)
		end)
	end)
	-- TopbarPlus places the button once, in the middle of its widget; it is lifted from there.
	vide.effect(function()
		button.Position = UDim2.new(0.5, 0, 0.5, -math.round(SHOW_LIFT * (1 - shown())))
	end)

	return create("UIScale")({ Scale = shown })
end

-- Dresses a TopbarPlus icon in the panel and feeds the panel what the hand does to it.
function Topbar.Dress(icon: any, options: TOptions)
	local isHovered = source(false)
	local pressedAt = source(-math.huge)
	icon:modifyTheme(theme())
	icon.viewingStarted:Connect(function()
		isHovered(true)
	end)
	icon.viewingEnded:Connect(function()
		isHovered(false)
	end)

	-- TopbarPlus builds its own button, so it never gets Components.ButtonSounds: the same two sounds, by hand.
	local clickRegion = icon:getInstance("ClickRegion")
	clickRegion.MouseButton1Down:Connect(function()
		local now = os.clock()
		pressedAt(now)
		options.OnPress(now + PRESS_SECONDS)
	end)
	clickRegion.MouseEnter:Connect(SoundsCore.PlayHover)
	clickRegion.Activated:Connect(SoundsCore.PlayClick)

	-- TopbarPlus clips the icon (for its dropdowns, which these have none of), which would cut the panel's shadow; it
	-- clips the button again on every deselect, so this runs after it.
	local widget, button = icon:getInstance("Widget"), icon:getInstance("IconButton")
	local function unclip()
		widget.ClipsDescendants = false
		button.ClipsDescendants = false
	end

	unclip()
	icon.deselected:Connect(function()
		task.defer(unclip)
	end)

	vide.mount(function()
		return {
			skinPanel(options, isHovered, pressedAt),
			-- Over TopbarPlus's own image and caption, which the skin is under.
			if options.Count
				then Notice.Build({
					Kind = "New",
					Size = BADGE,
					IsShown = function()
						return options.Count() > 0
					end,
					Now = options.Now,
					CallAt = options.CallAt,
				}, {
					-- TopbarPlus's theme resizes and moves anything named "Notice" inside an icon.
					Name = "Waiting",
					Position = UDim2.new(1, -INSET, 0, INSET),
					ZIndex = 20,
				})
				else nil,
			if options.IsShown then stepAside(icon, button, options.IsShown) else nil,
		}
	end, button)
end

return Topbar
