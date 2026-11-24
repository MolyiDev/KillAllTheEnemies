--!nonstrict
-- What the equipment page's pieces share: the clock every piece's way in and out reads, the rarity colours (Theme's,
-- the classes'), the weapon list's badges and dim for what is not owned, and a piece's picture.
--
-- The page comes by a tab, so it never slides in. Its panels are the classes page's panels to the px, so they are up at
-- once over those, and only what is in them changes: its contents deal in, staged, as the classes page's dealt in. Its
-- stage fades in as the classes stage goes. It leaves by a tab the other way round (the panels gone at once, onto the
-- classes page dealing in again), or by the screen shutting, when it goes off as the classes page goes, sliding out.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local TextService = game:GetService("TextService")
local vide = require(ReplicatedStorage.Packages.vide)
local GunPicture = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.GunPicture)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local WeaponsParts = require(script.Parent.Parent.WeaponsController.Parts)
local Types = require(script.Parent.Types)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress

local Parts = {}

Parts.Timing = table.freeze({
	-- A tab: the stage fades in over this long, the contents start dealing DEAL_DELAY in; the stage fades out over
	-- FADE_OUT. The classes page stays drawn under this page for COVER (its stage takes that long to go).
	FADE = 0.24,
	COVER = 0.24,
	FADE_OUT = 0.18,
	DEAL_DELAY = 0.08,
	-- The screen shutting: the page goes off accelerating, as the classes page's pieces do, the side panels this far
	-- (px) toward their edges.
	CLOSE = 0.22,
	SIDE_TRAVEL = 520,
	-- The light crossing a piece as it lands.
	SHEEN = 0.6,
	-- Every gesture is over by now; past it the clock's ticks redraw none of them.
	SETTLED = 1.6,
})

-- A rarity's colour, word and whether its tag is lettered in ink: the classes'.
Parts.RARITIES = Theme.Rarities
-- A piece not owned yet, drawn dim as a gun not owned is.
Parts.LOCKED_TINT = WeaponsParts.LOCKED_TINT
Parts.LOCKED_TRANSPARENCY = WeaponsParts.LOCKED_TRANSPARENCY
Parts.EdgeOf = WeaponsParts.EdgeOf
Parts.Badge = WeaponsParts.Badge
-- His thin rule under a panel's header, and its lavender.
Parts.RULE = Color3.fromRGB(140, 111, 211)
Parts.RULE_TRANSPARENCY = 0.55

function Parts.Label(props: { [any]: any }): TextLabel
	return create("TextLabel")({
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		FontFace = Font.Display,
		TextColor3 = Palette.White,
		ZIndex = 4,
		props,
	})
end

-- Each text measured once at `size` px in `font`, wrapped to `width` if given: its size in whole px, by the key it
-- came under, empty until measured. Not a label's TextBounds: that comes back under the screen's UIScale.
function Parts.TextBounds<K>(texts: { [K]: string }, font: Font, size: number, width: number?): () -> { [K]: Vector2 }
	local measured = vide.source({})
	task.spawn(function()
		local params = Instance.new("GetTextBoundsParams")
		params.Font = font
		params.Size = size
		if width then params.Width = width end
		local result = {}
		for key, text in texts do
			params.Text = text
			local isMeasured, bounds = pcall(TextService.GetTextBoundsAsync, TextService, params)
			if isMeasured then result[key] = Vector2.new(math.ceil(bounds.X), math.ceil(bounds.Y)) end
		end
		params:Destroy()
		measured(result)
	end)
	return measured
end

-- Whether the page is drawn at all: on show, or still leaving.
function Parts.IsDrawn(state: Types.TEquipmentState): () -> boolean
	return derive(function(): boolean
		if state.IsShown() then return true end
		return state.Now() - state.ShownAt() < math.max(Parts.Timing.FADE_OUT, Parts.Timing.CLOSE)
	end)
end

-- Whether the panels are up: at once on a tab, and while the screen sends them off sliding.
function Parts.ArePanelsUp(state: Types.TEquipmentState): () -> boolean
	return derive(function(): boolean
		return state.IsShown() or state.IsByScreen()
	end)
end

-- 0 gone to 1 solid: the stage's fade, `delay` after the page is shown by a tab; solid while the screen sends it off.
function Parts.Shown(state: Types.TEquipmentState, delay: number?): () -> number
	return derive(function(): number
		local now, at = state.Now(), state.ShownAt()
		if state.IsShown() then return Motion.Out(Progress(now, at, Parts.Timing.FADE, delay)) end
		if state.IsByScreen() then return 1 end
		return 1 - Progress(now, at, Parts.Timing.FADE_OUT)
	end)
end

-- 0 in place to 1 off: how far a piece has gone as the screen shuts. A tab never moves it.
function Parts.Away(state: Types.TEquipmentState): () -> number
	return derive(function(): number
		if state.IsShown() or not state.IsByScreen() then return 0 end
		return Motion.Accelerate(Progress(state.Now(), state.ShownAt(), Parts.Timing.CLOSE))
	end)
end

-- 0 to 1: a piece of a panel's contents coming in `delay` after the page comes up, over `seconds`, and again from the
-- moment `again` stamps if it is given. 1 while the page goes: it leaves with its panel.
function Parts.Dealt(state: Types.TEquipmentState, delay: number, seconds: number, again: (() -> number)?): () -> number
	return derive(function(): number
		if not state.IsShown() then return 1 end
		local now = state.Now()
		local opened = Progress(now, state.ShownAt(), seconds, Parts.Timing.DEAL_DELAY + delay)
		local redealt = if again then Progress(now, again(), seconds, delay) else 1
		return math.min(opened, redealt)
	end)
end

-- The light crossing a piece as it lands, `delay` after the page comes up: 0 to 1, and 1 at rest.
function Parts.Landing(state: Types.TEquipmentState, delay: number): () -> number
	return derive(function(): number
		if not state.IsShown() then return 1 end
		return Progress(state.Now(), state.ShownAt(), Parts.Timing.SHEEN, Parts.Timing.DEAL_DELAY + delay)
	end)
end

-- A piece of equipment's own model, seen as worn (GunPicture.FromEquipment). `spec` is GunPicture.Build's.
function Parts.Picture(itemId: () -> number, spec: { [any]: any }, props: { [any]: any }): Frame
	return GunPicture.Build(function()
		return GunPicture.FromEquipment(itemId())
	end, spec, props)
end

-- A colour toward black: `share` of it kept.
function Parts.Shade(color: Color3, share: number): Color3
	return Color3.new(color.R * share, color.G * share, color.B * share)
end

return Parts
