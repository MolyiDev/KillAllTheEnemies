--!nonstrict
-- What the weapons screen's pieces share: his colours for tiers and rarities, his badges and selection ring, a gun's
-- picture, and the clock every piece's entrance reads.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local GunPicture = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.GunPicture)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local Types = require(script.Parent.Types)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress

local Parts = {}

-- A screen's open and shut (UI.md 5o): pieces decelerate in, staged by what the screen is for, and accelerate out
-- faster; every fade runs on its own clock.
Parts.Timing = table.freeze({
	FADE = 0.3,
	SLIDE = 0.42,
	CLOSE = 0.22,
	-- Every gesture of an open is over by now; past it the clock's ticks redraw none of them.
	SETTLED = 1.6,
})

-- His card colours. A card's edge is its accent a little darker; the glow is the accent itself.
Parts.EDGE_SHARE = 0.85
local RED = Color3.fromRGB(230, 60, 72)
Parts.TIER_ACCENTS = table.freeze({ Palette.Steel, Palette.Green, Palette.Violet, Palette.Gold })
-- A rarity's accent, its word, and whether its tag is lettered in ink (his gold tag) rather than white.
Parts.RARITIES = table.freeze({
	Starter = table.freeze({ Accent = Palette.Steel, Text = "STARTER", IsInk = true }),
	Common = table.freeze({ Accent = Palette.Green, Text = "COMMON", IsInk = true }),
	Rare = table.freeze({ Accent = Palette.Violet, Text = "RARE", IsInk = false }),
	Epic = table.freeze({ Accent = Palette.Pink, Text = "EPIC", IsInk = false }),
	Legendary = table.freeze({ Accent = Palette.Gold, Text = "LEGENDARY", IsInk = true }),
	BlackMarket = table.freeze({ Accent = RED, Text = "BLACK MARKET", IsInk = false }),
})
-- A gun not owned yet, drawn dim as his grey glyphs are.
Parts.LOCKED_TINT = Color3.fromRGB(128, 124, 140)
Parts.LOCKED_TRANSPARENCY = 0.25
-- His thin rules (the list's and the upgrade header's), and the dark gold edge round a price (the cards' chips, the
-- cost block's tile).
Parts.RULE = Color3.fromRGB(72, 56, 112)
Parts.GOLD_EDGE = Color3.fromRGB(106, 79, 47)

function Parts.EdgeOf(accent: Color3): Color3
	local share = Parts.EDGE_SHARE
	return Color3.new(accent.R * share, accent.G * share, accent.B * share)
end

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

-- Seconds since the screen opened or shut, held once every gesture is over, so the clock ticking for a later
-- gesture works none of the open out again.
function Parts.Elapsed(state: Types.TWeaponsState): () -> number
	return derive(function(): number
		return math.min(state.Now() - state.ToggledAt(), Parts.Timing.SETTLED)
	end)
end

-- 0 to 1 as a piece's entrance runs, `delay` after the open; 1 while the screen shuts.
function Parts.Since(state: Types.TWeaponsState, elapsed: () -> number, delay: number, seconds: number): () -> number
	return derive(function(): number
		if not state.IsOpen() then return 1 end
		return Progress(elapsed(), delay, seconds)
	end)
end

-- How far from its place a piece is, as a share of its travel: decelerating in after `delay`, accelerating out.
function Parts.Away(state: Types.TWeaponsState, elapsed: () -> number, delay: number): () -> number
	return derive(function(): number
		if state.IsOpen() then return 1 - Motion.Decelerate(Progress(elapsed(), delay, Parts.Timing.SLIDE)) end
		return Motion.Accelerate(Progress(elapsed(), 0, Parts.Timing.CLOSE))
	end)
end

-- How transparent a piece is: its fade in after `delay` (away at once, gentle onto the mark), an even fade out.
function Parts.Faded(state: Types.TWeaponsState, elapsed: () -> number, delay: number): () -> number
	return derive(function(): number
		if state.IsOpen() then return 1 - Motion.Out(Progress(elapsed(), delay, Parts.Timing.FADE)) end
		return Progress(elapsed(), 0, Parts.Timing.CLOSE)
	end)
end

-- His badges, `size` px square: Check (his green tick square), Upgrade (his gold square with the chevrons: an upgrade
-- he can pay for), Lock (his grey-edged ink square with a white lock).
function Parts.Badge(kind: string, size: number, props: { [any]: any }): Frame
	if kind == "Lock" then
		return Components.Plaque({
			Size = UDim2.fromOffset(size, size),
			Components.Icon("Lock", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = Components.GlyphBox(math.round(size * 0.56)),
				ImageColor3 = Palette.White,
				ZIndex = 2,
			}),
			props,
		})
	end

	local isCheck = kind == "Check"
	return create("Frame")({
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = if isCheck then Palette.Green else Palette.Gold,
		BorderSizePixel = 0,
		create("UICorner")({ CornerRadius = UDim.new(0, 2) }),
		Components.Icon(if isCheck then "Check" else "Rank", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = Components.GlyphBox(math.round(size * (if isCheck then 0.62 else 0.58))),
			ImageColor3 = Palette.Ink,
			ZIndex = 2,
		}),
		props,
	})
end

-- His selection ring: a thin white rounded outline standing `outset` px off what it frames. `props` are its own
-- (size it to the framed piece; the outset is added).
function Parts.Ring(outset: number, props: { [any]: any }): Frame
	return create("Frame")({
		Name = "Ring",
		BackgroundTransparency = 1,
		create("Frame")({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, 2 * outset, 1, 2 * outset),
			BackgroundTransparency = 1,
			create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
			create("UIStroke")({
				Color = Palette.White,
				Thickness = 1.5,
				Transparency = 0.05,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
		}),
		props,
	})
end

-- A gun's own model, side on, the barrel to the right (GunPicture). `spec` is GunPicture.Build's.
function Parts.Gun(gunId: () -> number, spec: { [any]: any }, props: { [any]: any }): Frame
	return GunPicture.Build(function()
		return GunPicture.FromGun(gunId())
	end, spec, props)
end

return Parts
