--!nonstrict
-- The art behind a thing on show (the weapons and classes stages, the index's stage, day 7's prize): one of a few
-- looks, each its own drawing with its own idle motion, way in and cheer. Drawn from one white atlas
-- (Icons.SHOWCASE, icons.py's showcase()), tinted with the owner's accent, and over a floor of its own
-- (Icons.SHOWCASE_FLOOR) where the owner gives it one. Its clock is os.clock, read on Heartbeat only while the owner
-- says the art is up, so a closed screen writes nothing.
--
-- Particles are glowing pixels: plain squares, never turned, swelling in and shrinking away rather than blinking.
-- Rays' are drawn on a layer of their own, which the owner puts over the thing on show; Orbit's pass behind it and
-- over it; Dots' and Spotlight's stay behind it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Icons = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Icons)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)

local create = vide.create
local derive = vide.derive
local source = vide.source
local Palette = Theme.Palette
-- Read by bindings on every frame the art is up, so hoisted out of their module.
local easeOut = Motion.Out
local decelerate = Motion.Decelerate
local lerp = Motion.Lerp
local bump = Motion.Bump

local Showcase = {}

-- "Rings" is his two rings, which each owner still draws itself; "None" draws nothing.
Showcase.LOOKS = table.freeze({ "Rings", "None", "Rays", "Dots", "Orbit", "Spotlight" })

-- The look each place draws, and the bench's switch: the stories write Looks before they build a screen.
Showcase.GAME_LOOKS = table.freeze({
	Weapons = "Orbit",
	Classes = "Spotlight",
	-- The classes screen's other page, the same look under its avatar.
	Equipment = "Spotlight",
	Index = "Dots",
	Prize = "Rays",
})
Showcase.Looks = table.clone(Showcase.GAME_LOOKS)

export type TSpec = {
	Look: string,
	-- The art's size in px: what the rays, dots or rings fill.
	Diameter: number,
	-- Where the thing stands, in px below the middle: the floor's middle, the spotlight's pool, where motes rise from.
	Floor: number,
	-- The floor's size in px, nil for none (the owner then draws none either).
	FloorSize: Vector2?,
	-- The bench's floor switch: a ShowcaseFloorCells cell, or "His" (Icons.FLOOR_OFFSET's), drawn in place of the
	-- look's own floor. Nil for the look's own.
	FloorCell: string?,
	Accent: () -> Color3,
	-- 0 gone, 1 in: its way in, and out backwards.
	Shown: () -> number,
	-- When the thing on show was last cheered (bought, raised, claimed, revealed), in os.clock; -math.huge for never.
	CheeredAt: () -> number,
	-- Whether the screen is up: the idle clock ticks only then.
	IsActive: () -> boolean,
}

local Tune = table.freeze({
	-- Rays: two fans turning against each other (the second sits half a ray over, so they shimmer where they cross),
	-- the light in the middle, and pixels rising out of it.
	RAYS_TURN = 5,
	RAYS_BACK_TURN = -3,
	RAYS_PITCH = 360 / 16,
	RAYS_ALPHA = 0.42,
	RAYS_BACK_ALPHA = 0.26,
	RAYS_BACK_SIZE = 0.8,
	RAYS_SPIN_IN = 70,
	-- Dots: a halftone disc turning slowly and breathing, pixels round it.
	DOTS_TURN = 4,
	DOTS_ALPHA = 0.34,
	DOTS_BREATH = 0.025,
	DOTS_BREATH_PERIOD = 3.2,
	DOTS_SPIN_IN = -50,
	-- Orbit: a reticle turning one way and a smaller one the other, pixels flying round it on tilted rings.
	RETICLE_TURN = 9,
	RETICLE_INNER_TURN = -15,
	RETICLE_INNER_SIZE = 0.64,
	RETICLE_ALPHA = 0.6,
	RETICLE_INNER_ALPHA = 0.2,
	RETICLE_SPIN_IN = 160,
	ORBITS = { 0, 58, -58 },
	ORBIT_SQUASH = 0.3,
	ORBIT_TURNS = 0.32,
	TRAIL = 6,
	TRAIL_GAP = 0.035,
	-- Spotlight: a beam from above onto the floor, a pool where it lands, dust hanging in it.
	BEAM_TOP = 0.55,
	BEAM_WIDTH = 0.92,
	POOL = Vector2.new(0.8, 0.17),
	FLICKER = 0.04,
	-- The screens stand over the blurred lobby, about as bright as the beam, so the beam and its pool are at full
	-- strength, the beam is drawn this many times over (its core is behind the thing on show, so only its faint edges
	-- are seen) and the stage round it is shaded dark.
	BEAM_LAYERS = 2,
	SHADE_SIZE = 2.4,
	SHADE_ALPHA = 0.85,
	-- The light in the middle of every look but the spotlight's.
	GLOW_SIZE = 0.78,
	GLOW_ALPHA = 0.65,
	-- Pixels: how many rise (Rays), circle (Dots) or hang (Spotlight), a mote's life in seconds, a pixel's biggest size
	-- in px, its light's size as a share of it and its light's strength.
	MOTES = 12,
	MOTE_LIFE = 3.4,
	MOTE_SIZE = 9,
	MOTE_GLOW = 5,
	MOTE_LIGHT = 0.7,
	RING_PIXELS = 10,
	RING_PIXELS_TURN = -9,
	DUST = 14,
	-- A cheer: the art flares, punches and spins, and pixels burst out from beyond the thing's own light. The spin is a
	-- whole turn (and every part turns by whole or half turns of it, which its drawing repeats at), so the art comes to
	-- rest where it would have been, and the next cheer starts from there instead of jumping back.
	CHEER = 0.9,
	CHEER_PUNCH = 0.14,
	CHEER_SPIN = 360,
	BURST = 14,
	BURST_FROM = 0.24,
	BURST_REACH = 0.3,
	BURST_DROP = 0.08,
	BURST_SIZE = 9,
	-- The floors: they grow in from this share of their size; each look's floor at its strength, and the light under
	-- it; a ripple runs out across them from RIPPLE_FROM of the floor to RIPPLE_TO.
	FLOOR_FROM = 0.8,
	PAD_ALPHA = 0.6,
	DOTS_FLOOR_ALPHA = 0.85,
	RETICLE_FLOOR_ALPHA = 0.65,
	SPOT_FLOOR_ALPHA = 0.7,
	FLOOR_GLOW = 0.4,
	RIPPLE_FROM = 0.5,
	RIPPLE_TO = 1.45,
	RIPPLE_ALPHA = 0.7,
	-- Orbit's floor: two trains of pixels running round its rim, opposite ways, turns a second.
	RIM_TURNS = 0.22,
	RIM_TRAIL = 7,
	RIM_GAP = 0.045,
})

local MIDDLE = UDim2.fromScale(0.5, 0.5)
local CENTRE = Vector2.new(0.5, 0.5)
-- His floor's cell in Icons.IMAGE, for the bench's floor switch.
local HIS_FLOOR = table.freeze({ Offset = Icons.FLOOR_OFFSET, Size = Icons.FLOOR_SIZE })

-- 0 to 1, the same for the same index and salt: where each pixel starts, how long it lives.
local function scatter(index: number, salt: number): number
	local x = math.sin(index * 12.9898 + salt * 78.233) * 43758.5453
	return x - math.floor(x)
end

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- One cell of the atlas, centred unless `props` says otherwise.
local function sprite(cell: string, props: { [any]: any }): ImageLabel
	local at = Icons.ShowcaseCells[cell]
	props.BackgroundTransparency = 1
	props.Image = Icons.SHOWCASE
	props.ImageRectOffset = at.Offset
	props.ImageRectSize = at.Size
	props.AnchorPoint = props.AnchorPoint or CENTRE
	props.Position = props.Position or MIDDLE
	return create("ImageLabel")(props)
end

-- A glowing pixel: a plain square with its soft light round it. `pose` gives its middle from the art's middle and its
-- size, in whole px; `alpha` how much of it shows. Each is worked out once a frame, though two bindings read it. The
-- light is the square's sibling, since a child draws over its parent.
local function pixel(name: string, color: () -> Color3, pose: () -> Vector3, alpha: () -> number): Frame
	local at = derive(pose)
	local shows = derive(alpha)
	return create("Frame")({
		Name = name,
		AnchorPoint = CENTRE,
		Position = function()
			local middle = at()
			return UDim2.new(0.5, middle.X, 0.5, middle.Y)
		end,
		Size = function()
			local size = at().Z
			return UDim2.fromOffset(size, size)
		end,
		BackgroundTransparency = 1,
		-- Over the art and the floors (2), in whichever layer it is drawn.
		ZIndex = 3,
		sprite("Glow", {
			Name = "Light",
			Size = UDim2.fromScale(Tune.MOTE_GLOW, Tune.MOTE_GLOW),
			ImageColor3 = color,
			ImageTransparency = function()
				return 1 - Tune.MOTE_LIGHT * shows()
			end,
		}),
		create("Frame")({
			Name = "Square",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = color,
			BackgroundTransparency = function()
				return 1 - shows()
			end,
			BorderSizePixel = 0,
			ZIndex = 2,
		}),
	})
end

-- The light in the middle.
local function glow(spec: TSpec, flare: () -> number): ImageLabel
	local size = math.round(spec.Diameter * Tune.GLOW_SIZE)
	return sprite("Glow", {
		Name = "Glow",
		Size = UDim2.fromOffset(size, size),
		ImageColor3 = function()
			return spec.Accent():Lerp(Palette.White, 0.4 + 0.5 * flare())
		end,
		ImageTransparency = function()
			return 1 - math.min(1, Tune.GLOW_ALPHA * (1 + flare())) * spec.Shown()
		end,
	})
end

-- A cheer's beats, shared by every piece of a look: how far through it is (0 at the cheer, 1 once it is over and at
-- rest), its flare (1 at the cheer, falling to 0) and its extra turn (a whole one, see CHEER_SPIN).
local function cheerOf(sinceCheer: () -> number): (() -> number, () -> number, () -> number)
	local cheer = derive(function(): number
		local since = sinceCheer()
		if since < 0 or since >= Tune.CHEER then return 1 end
		return since / Tune.CHEER
	end)
	local flare = derive(function(): number
		return 1 - easeOut(cheer())
	end)
	local turn = derive(function(): number
		return Tune.CHEER_SPIN * decelerate(cheer())
	end)

	return cheer, flare, turn
end

-- Pixels thrown out by a cheer, from just past the thing's own light, slowing as they go, falling a little, swelling
-- in and shrinking away. At rest they are fully transparent.
local function burst(spec: TSpec, cheer: () -> number, color: () -> Color3): { Instance }
	local diameter = spec.Diameter
	local from = diameter * Tune.BURST_FROM
	local drop = diameter * Tune.BURST_DROP

	local pieces = table.create(Tune.BURST)
	for index = 1, Tune.BURST do
		local angle = 2 * math.pi * (index + 0.6 * scatter(index, 11)) / Tune.BURST
		local reach = diameter * Tune.BURST_REACH * (0.6 + 0.4 * scatter(index, 12))
		local size = Tune.BURST_SIZE * (0.6 + 0.4 * scatter(index, 13))
		local direction = Vector2.new(math.cos(angle), math.sin(angle))
		pieces[index] = pixel(`Burst{index}`, color, function(): Vector3
			local t = cheer()
			local at = direction * (from + reach * easeOut(t)) + Vector2.new(0, drop * t * t)
			local swell = math.min(t / 0.12, 1) * (1 - smooth((t - 0.55) / 0.45))
			return Vector3.new(math.round(at.X), math.round(at.Y), math.round(size * swell))
		end, function(): number
			local t = cheer()
			if t <= 0 or t >= 1 then return 0 end
			return 1 - smooth((t - 0.6) / 0.4)
		end)
	end

	return pieces
end

-- One floor of the floor atlas on the owner's floor, growing in with the art. `alpha` is how much of it shows.
local function floorLayer(
	spec: TSpec,
	cell: string,
	color: () -> Color3,
	alpha: () -> number,
	grow: (() -> number)?
): ImageLabel
	local size = spec.FloorSize :: Vector2
	local isHis = cell == "His"
	local at = if isHis then HIS_FLOOR else Icons.ShowcaseFloorCells[cell]
	return create("ImageLabel")({
		Name = `Floor{cell}`,
		AnchorPoint = CENTRE,
		Position = UDim2.new(0.5, 0, 0.5, spec.Floor),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundTransparency = 1,
		Image = if isHis then Icons.IMAGE else Icons.SHOWCASE_FLOOR,
		ImageRectOffset = at.Offset,
		ImageRectSize = at.Size,
		ImageColor3 = color,
		-- His floor at his own strength: its ring is opaque in the atlas, the looks' floors are not.
		ImageTransparency = if isHis
			then function()
				return 1 - (1 - Icons.FLOOR_TRANSPARENCY) * spec.Shown()
			end
			else function()
				return 1 - math.min(1, alpha()) * spec.Shown()
			end,
		ZIndex = 2,
		create("UIScale")({
			Scale = function()
				local extra = if grow then grow() else 0
				return lerp(Tune.FLOOR_FROM, 1, decelerate(spec.Shown())) + extra
			end,
		}),
	})
end

-- One ring running out across the floor as `share` goes 0 to 1, from RIPPLE_FROM of it to RIPPLE_TO.
local function ripple(spec: TSpec, color: () -> Color3, share: () -> number, strength: number): ImageLabel
	local at = Icons.ShowcaseFloorCells.Ring
	local size = spec.FloorSize :: Vector2
	return create("ImageLabel")({
		Name = "Ripple",
		AnchorPoint = CENTRE,
		Position = UDim2.new(0.5, 0, 0.5, spec.Floor),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundTransparency = 1,
		Image = Icons.SHOWCASE_FLOOR,
		ImageRectOffset = at.Offset,
		ImageRectSize = at.Size,
		ImageColor3 = color,
		ImageTransparency = function()
			local t = share()
			if t <= 0 or t >= 1 then return 1 end
			return 1 - strength * math.min(t / 0.1, 1) * (1 - t) * spec.Shown()
		end,
		ZIndex = 2,
		create("UIScale")({
			Scale = function()
				return lerp(Tune.RIPPLE_FROM, Tune.RIPPLE_TO, easeOut(share()))
			end,
		}),
	})
end

-- The floor's soft light, under the thing.
local function floorGlow(spec: TSpec, color: () -> Color3, flare: () -> number): ImageLabel
	return floorLayer(spec, "Glow", color, function()
		return Tune.FLOOR_GLOW * (1 + flare())
	end, function()
		return 0.25 * flare()
	end)
end

local function punch(flare: () -> number, shown: () -> number, from: number): UIScale
	return create("UIScale")({
		Scale = function()
			return lerp(from, 1, decelerate(shown())) + Tune.CHEER_PUNCH * bump(1 - flare())
		end,
	})
end

-- ============================== The looks ==============================

local function rays(spec: TSpec, clock: () -> number, sinceCheer: () -> number): ({ Instance }, { Instance })
	local diameter = spec.Diameter
	local cheer, flare, cheerTurn = cheerOf(sinceCheer)
	local shown = spec.Shown
	local light = derive(function(): Color3
		return spec.Accent():Lerp(Palette.White, 0.45)
	end)
	local back = math.round(diameter * Tune.RAYS_BACK_SIZE)

	-- Pixels rising from just over the floor to near the top, each on its own life, drifting in and swaying.
	local spread = diameter * 0.5
	local bottom = spec.Floor * 0.8
	local rise = -diameter * 0.42 - bottom
	local moteAlpha = derive(function(): number
		return 0.85 * shown()
	end)

	local motes = table.create(Tune.MOTES)
	for index = 1, Tune.MOTES do
		local life = Tune.MOTE_LIFE * (0.7 + 0.6 * scatter(index, 1))
		local x0 = (scatter(index, 2) - 0.5) * spread
		local size = Tune.MOTE_SIZE * (0.55 + 0.45 * scatter(index, 3))
		local phase = scatter(index, 4)
		local sway = 6 + 10 * scatter(index, 5)
		motes[index] = pixel(`Mote{index}`, light, function(): Vector3
			local t = (clock() / life + phase) % 1
			local x = x0 * (1 - 0.35 * t) + sway * math.sin(2 * math.pi * (1.3 * t + phase))
			local swell = math.min(t / 0.15, 1) * (1 - smooth((t - 0.7) / 0.3))
			return Vector3.new(math.round(x), math.round(bottom + rise * t), math.round(size * swell))
		end, moteAlpha)
	end

	-- A pad lit by the rays, and a ripple across it at a cheer.
	local floor = if spec.FloorSize
		then {
			floorGlow(spec, light, flare),
			floorLayer(spec, spec.FloorCell or "Pad", spec.Accent, function()
				return Tune.PAD_ALPHA * (1 + 0.6 * flare())
			end),
			ripple(spec, light, cheer, Tune.RIPPLE_ALPHA),
		}
		else nil

	return {
		floor,
		glow(spec, flare),
		create("Frame")({
			Name = "Fans",
			AnchorPoint = CENTRE,
			Position = MIDDLE,
			Size = UDim2.fromOffset(diameter, diameter),
			BackgroundTransparency = 1,
			punch(flare, shown, 0.6),
			sprite("Rays", {
				Name = "Back",
				Size = UDim2.fromOffset(back, back),
				ImageColor3 = light,
				ImageTransparency = function()
					return 1 - math.min(1, Tune.RAYS_BACK_ALPHA * (1 + flare())) * shown()
				end,
				Rotation = function()
					return Tune.RAYS_PITCH / 2
						+ Tune.RAYS_BACK_TURN * clock()
						- cheerTurn() / 2
						- Tune.RAYS_SPIN_IN * (1 - decelerate(shown()))
				end,
			}),
			sprite("Rays", {
				Name = "Front",
				Size = UDim2.fromScale(1, 1),
				ImageColor3 = spec.Accent,
				ImageTransparency = function()
					return 1 - math.min(1, Tune.RAYS_ALPHA * (1 + flare())) * shown()
				end,
				Rotation = function()
					return Tune.RAYS_TURN * clock() + cheerTurn() + Tune.RAYS_SPIN_IN * (1 - decelerate(shown()))
				end,
			}),
		}),
	}, {
		motes,
		burst(spec, cheer, light),
	}
end

local function dots(spec: TSpec, clock: () -> number, sinceCheer: () -> number): ({ Instance }, { Instance }?)
	local diameter = spec.Diameter
	local cheer, flare, cheerTurn = cheerOf(sinceCheer)
	local shown = spec.Shown
	local light = derive(function(): Color3
		return spec.Accent():Lerp(Palette.White, 0.5)
	end)

	-- The disc's and its floor's breath, and the ring's turn and radius, the same for every pixel on it.
	local breath = derive(function(): number
		return Tune.DOTS_BREATH * math.sin(2 * math.pi * clock() / Tune.DOTS_BREATH_PERIOD)
	end)
	local ringTurn = derive(function(): number
		return math.rad(Tune.RING_PIXELS_TURN * clock() - cheerTurn())
	end)
	local ringRadius = derive(function(): number
		return diameter * (0.5 * lerp(0.7, 1, decelerate(shown())) + 0.08 * flare())
	end)
	local ringAlpha = derive(function(): number
		return 0.9 * shown()
	end)

	local ring = table.create(Tune.RING_PIXELS)
	for index = 1, Tune.RING_PIXELS do
		local offset = 2 * math.pi * index / Tune.RING_PIXELS
		local size = Tune.MOTE_SIZE * (0.6 + 0.4 * scatter(index, 6))
		local rate = 1.5 + scatter(index, 7)
		ring[index] = pixel(`Orbiter{index}`, light, function(): Vector3
			local angle = offset + ringTurn()
			local out = ringRadius()
			local twinkle = 0.65 + 0.35 * math.sin(rate * clock() + offset)
			return Vector3.new(
				math.round(out * math.cos(angle)),
				math.round(out * math.sin(angle)),
				math.round(size * twinkle)
			)
		end, ringAlpha)
	end

	-- The halftone laid flat, breathing with the disc.
	local floor = if spec.FloorSize
		then {
			floorGlow(spec, spec.Accent, flare),
			floorLayer(spec, spec.FloorCell or "Dots", spec.Accent, function()
				return Tune.DOTS_FLOOR_ALPHA * (1 + 0.6 * flare())
			end, breath),
		}
		else nil

	return {
		floor,
		glow(spec, flare),
		sprite("Dots", {
			Name = "Dots",
			Size = UDim2.fromOffset(diameter, diameter),
			ImageColor3 = spec.Accent,
			ImageTransparency = function()
				return 1 - math.min(1, Tune.DOTS_ALPHA * (1 + 0.8 * flare())) * shown()
			end,
			Rotation = function()
				return Tune.DOTS_TURN * clock() + cheerTurn() + Tune.DOTS_SPIN_IN * (1 - decelerate(shown()))
			end,
			create("UIScale")({
				Scale = function()
					return lerp(0.6, 1, decelerate(shown())) + breath() + Tune.CHEER_PUNCH * bump(1 - flare())
				end,
			}),
		}),
		ring,
		burst(spec, cheer, light),
	}
end

-- A pixel going round the thing on show, as a pair: the back layer's draws it on the far half of its path, behind the
-- thing, and the front layer's on the near half, over it. `angle` is where it is on its path, whose near half is where
-- the sine is positive (the lower side, the path seen from a little above); `pose` places it there. The swap is at
-- the path's two ends, out beside the thing, so neither layer is seen to take over.
local function circling(
	name: string,
	color: () -> Color3,
	angle: () -> number,
	pose: (angle: number) -> Vector3,
	alpha: () -> number
): (Frame, Frame)
	local at = derive(function(): Vector3
		return pose(angle())
	end)
	local isNear = derive(function(): boolean
		return math.sin(angle()) > 0
	end)

	return pixel(`{name}Back`, color, at, function(): number
		return if isNear() then 0 else alpha()
	end),
		pixel(`{name}Front`, color, at, function(): number
			return if isNear() then alpha() else 0
		end)
end

local function orbit(spec: TSpec, clock: () -> number, sinceCheer: () -> number): ({ Instance }, { Instance })
	local diameter = spec.Diameter
	local cheer, flare, cheerTurn = cheerOf(sinceCheer)
	local shown = spec.Shown
	local light = derive(function(): Color3
		return spec.Accent():Lerp(Palette.White, 0.55)
	end)
	local inner = math.round(diameter * Tune.RETICLE_INNER_SIZE)
	local spinIn = function(): number
		return Tune.RETICLE_SPIN_IN * (1 - decelerate(shown()))
	end

	-- Each orbit's pixel leads a train of smaller ones, each a step behind it in time, passing behind the thing on the
	-- far half of the orbit and over it on the near half.
	local rx, ry = diameter * 0.52, diameter * 0.52 * Tune.ORBIT_SQUASH
	-- How big the orbits are, the same for every pixel on them: they open as the art comes in, and swell at a cheer.
	local opened = derive(function(): number
		return lerp(0.4, 1, decelerate(shown())) + 0.12 * flare()
	end)

	local total = #Tune.ORBITS * Tune.TRAIL
	local satellitesBack, satellitesFront = table.create(total), table.create(total)
	local count = 0
	for ring, tilt in Tune.ORBITS do
		local turn = math.rad(tilt)
		local cos, sin = math.cos(turn), math.sin(turn)
		local phase = ring / #Tune.ORBITS
		for car = 0, Tune.TRAIL - 1 do
			local share = 1 - car / Tune.TRAIL
			local size = Tune.MOTE_SIZE * (0.35 + 0.65 * share) * (if car == 0 then 1.2 else 1)
			count += 1
			satellitesBack[count], satellitesFront[count] = circling(`Satellite{ring}_{car}`, light, function(): number
				local turns = Tune.ORBIT_TURNS * (clock() - car * Tune.TRAIL_GAP) + phase + cheerTurn() / 360
				return 2 * math.pi * turns
			end, function(angle: number): Vector3
				local out = opened()
				local x, y = rx * out * math.cos(angle), ry * out * math.sin(angle)
				return Vector3.new(math.round(x * cos - y * sin), math.round(x * sin + y * cos), math.round(size))
			end, function(): number
				return (0.35 + 0.6 * share) * shown()
			end)
		end
	end

	-- The sight laid flat, with two trains of pixels running round its rim, opposite ways (behind the thing along the
	-- far edge, over it along the near one), and a ripple at a cheer.
	local floor = nil
	local trainsBack, trainsFront = nil, nil
	local floorSize = spec.FloorSize
	if floorSize then
		local floorX, floorY = floorSize.X / 2 * 0.985, floorSize.Y / 2 * 0.985
		local grown = derive(function(): number
			return lerp(Tune.FLOOR_FROM, 1, decelerate(shown()))
		end)
		trainsBack, trainsFront = table.create(2 * Tune.RIM_TRAIL), table.create(2 * Tune.RIM_TRAIL)
		for train = 1, 2 do
			local direction = if train == 1 then 1 else -1
			for car = 0, Tune.RIM_TRAIL - 1 do
				local share = 1 - car / Tune.RIM_TRAIL
				local size = Tune.MOTE_SIZE * (0.3 + 0.6 * share)
				local index = (train - 1) * Tune.RIM_TRAIL + car + 1
				trainsBack[index], trainsFront[index] = circling(`Rim{train}_{car}`, light, function(): number
					local turns = direction * Tune.RIM_TURNS * (clock() - car * Tune.RIM_GAP)
						+ (train - 1) / 2
						+ direction * cheerTurn() / 360
					return 2 * math.pi * turns
				end, function(angle: number): Vector3
					local out = grown()
					return Vector3.new(
						math.round(floorX * out * math.cos(angle)),
						math.round(spec.Floor + floorY * out * math.sin(angle)),
						math.round(size)
					)
				end, function(): number
					return (0.3 + 0.65 * share) * shown()
				end)
			end
		end
		floor = {
			floorGlow(spec, spec.Accent, flare),
			floorLayer(spec, spec.FloorCell or "Reticle", light, function()
				return Tune.RETICLE_FLOOR_ALPHA * (1 + flare())
			end),
			ripple(spec, light, cheer, Tune.RIPPLE_ALPHA),
		}
	end

	return {
		floor,
		glow(spec, flare),
		create("Frame")({
			Name = "Reticles",
			AnchorPoint = CENTRE,
			Position = MIDDLE,
			Size = UDim2.fromOffset(diameter, diameter),
			BackgroundTransparency = 1,
			punch(flare, shown, 1.25),
			sprite("Reticle", {
				Name = "Outer",
				Size = UDim2.fromScale(1, 1),
				ImageColor3 = light,
				ImageTransparency = function()
					return 1 - math.min(1, Tune.RETICLE_ALPHA * (1 + flare())) * shown()
				end,
				Rotation = function()
					return Tune.RETICLE_TURN * clock() + cheerTurn() + spinIn()
				end,
			}),
			sprite("Reticle", {
				Name = "Inner",
				Size = UDim2.fromOffset(inner, inner),
				ImageColor3 = spec.Accent,
				ImageTransparency = function()
					return 1 - math.min(1, Tune.RETICLE_INNER_ALPHA * (1 + flare())) * shown()
				end,
				Rotation = function()
					return Tune.RETICLE_INNER_TURN * clock() - cheerTurn() - spinIn()
				end,
			}),
		}),
		trainsBack,
		satellitesBack,
	}, {
		satellitesFront,
		trainsFront,
		burst(spec, cheer, light),
	}
end

local function spotlight(spec: TSpec, clock: () -> number, sinceCheer: () -> number): ({ Instance }, { Instance }?)
	local diameter = spec.Diameter
	local floorY = spec.Floor
	local cheer, flare = cheerOf(sinceCheer)
	local light = derive(function(): Color3
		return spec.Accent():Lerp(Palette.White, 0.5)
	end)
	-- The light comes on like a stage's: a stutter, then up.
	local on = derive(function(): number
		local t = spec.Shown()
		if t < 0.25 then return 0 end
		if t < 0.38 then return 0.8 end
		if t < 0.5 then return 0.15 end
		return easeOut((t - 0.5) / 0.5)
	end)
	-- Read by every layer of the beam, so worked out once a frame.
	local beamAlpha = derive(function(): number
		local t = clock()
		return (1 - Tune.FLICKER * (0.5 + 0.5 * math.sin(7.3 * t) * math.sin(2.1 * t + 1))) * on()
	end)
	local beamTop = -diameter * Tune.BEAM_TOP
	local beamHeight = math.round(floorY - beamTop)
	local beamWidth = math.round(diameter * Tune.BEAM_WIDTH)
	local poolSize = Vector2.new(math.round(diameter * Tune.POOL.X), math.round(diameter * Tune.POOL.Y))

	-- Dust hanging in the beam: each drifts round its own spot, inside the cone at its height, and twinkles.
	local dust = table.create(Tune.DUST)
	for index = 1, Tune.DUST do
		local height = 0.12 + 0.8 * scatter(index, 8)
		local across = (scatter(index, 9) - 0.5) * 0.8
		local size = Tune.MOTE_SIZE * (0.35 + 0.4 * scatter(index, 10))
		local rate = 0.4 + 0.5 * scatter(index, 14)
		local phase = 2 * math.pi * scatter(index, 15)
		dust[index] = pixel(`Dust{index}`, light, function(): Vector3
			local t = clock()
			local h = height + 0.04 * math.sin(rate * t + phase)
			local half = beamWidth / 2 * (0.16 + 0.84 * h)
			local x = across * half + 8 * math.sin(0.7 * rate * t + 2 * phase)
			local y = beamTop + beamHeight * h
			return Vector3.new(math.round(x), math.round(y), math.round(size))
		end, function(): number
			local twinkle = 0.5 + 0.5 * math.sin(2.6 * rate * clock() + phase)
			return (0.3 + 0.6 * twinkle) * on()
		end)
	end

	local beams = table.create(Tune.BEAM_LAYERS)
	for index = 1, Tune.BEAM_LAYERS do
		beams[index] = sprite("Beam", {
			Name = `Layer{index}`,
			Size = UDim2.fromScale(1, 1),
			ImageColor3 = light,
			ImageTransparency = function()
				return 1 - beamAlpha()
			end,
		})
	end
	local shade = math.round(diameter * Tune.SHADE_SIZE)

	return {
		sprite("Glow", {
			Name = "Shade",
			Size = UDim2.fromOffset(shade, shade),
			ImageColor3 = Palette.Ink,
			-- The dark comes in with the screen; only the light stutters.
			ImageTransparency = function()
				return 1 - Tune.SHADE_ALPHA * spec.Shown()
			end,
		}),
		sprite("Glow", {
			Name = "Back",
			Size = UDim2.fromOffset(math.round(diameter * 0.9), math.round(diameter * 0.9)),
			ImageColor3 = spec.Accent,
			ImageTransparency = function()
				return 1 - math.min(1, 0.6 * (1 + flare())) * on()
			end,
		}),
		create("Frame")({
			Name = "Beam",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 0.5, floorY),
			Size = UDim2.fromOffset(beamWidth, beamHeight),
			BackgroundTransparency = 1,
			create("UIScale")({
				Scale = function()
					return 1 + 0.08 * flare()
				end,
			}),
			beams,
		}),
		-- The lit halftone under the pool, stuttering on with the beam, and a ripple at a cheer.
		if spec.FloorSize
			then {
				floorLayer(spec, spec.FloorCell or "Dots", light, function()
					return Tune.SPOT_FLOOR_ALPHA * (1 + 0.5 * flare()) * on()
				end),
				ripple(spec, light, cheer, Tune.RIPPLE_ALPHA),
			}
			else nil,
		sprite("Glow", {
			Name = "Pool",
			ZIndex = 2,
			Position = UDim2.new(0.5, 0, 0.5, floorY),
			Size = function()
				local grow = 1 + 0.35 * flare()
				return UDim2.fromOffset(math.round(poolSize.X * grow), math.round(poolSize.Y * grow))
			end,
			ImageColor3 = light,
			ImageTransparency = function()
				return 1 - on()
			end,
		}),
		dust,
		burst(spec, cheer, light),
	}
end

local LOOKS = table.freeze({
	Rays = rays,
	Dots = dots,
	Orbit = orbit,
	Spotlight = spotlight,
})

-- ============================== The art ==============================

-- The art for `spec.Look` in two layers centred on the same point: what goes behind the thing on show, and its
-- particles, which go over it. `props` and `frontProps` are each layer's own (its Position, the front's ZIndex). Nil
-- for a look the owner draws itself ("Rings") or none; the front alone is nil for a look whose particles all stay
-- behind (Dots, Spotlight).
function Showcase.Build(spec: TSpec, props: { [any]: any }, frontProps: { [any]: any }): (Frame?, Frame?)
	local look = LOOKS[spec.Look]
	if not look then return nil, nil end

	local clock = source(os.clock())
	local stepper: RBXScriptConnection? = nil
	vide.effect(function()
		local isActive = spec.IsActive()
		vide.untrack(function()
			if isActive and not stepper then
				clock(os.clock())
				stepper = RunService.Heartbeat:Connect(function()
					clock(os.clock())
				end)
			elseif not isActive and stepper then
				stepper:Disconnect()
				stepper = nil
			end
		end)
	end)
	vide.cleanup(function()
		if stepper then stepper:Disconnect() end
	end)
	local sinceCheer = function(): number
		return clock() - spec.CheeredAt()
	end

	local back, front = look(spec, clock, sinceCheer)
	local function layer(name: string, children: { Instance }, layerProps: { [any]: any }): Frame
		return create("Frame")({
			Name = name,
			AnchorPoint = CENTRE,
			Size = UDim2.fromOffset(spec.Diameter, spec.Diameter),
			BackgroundTransparency = 1,
			children,
			layerProps,
		})
	end

	return layer("Showcase", back, props), if front then layer("ShowcaseFront", front, frontProps) else nil
end

return Showcase
