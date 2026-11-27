--!nonstrict
-- What the screen stands on: his panels' deep violet, shaded darker toward every edge, and a few glowing pixels rising
-- slowly through it (plain squares that swell in and shrink away, never blink). The base is the flat colour
-- LoadingScreen.client covers the default screen with before anything loads, so the shading and the pixels come in
-- over it and nothing jumps.
--
-- Leaving, it is cut into squares, ROWS of them tiling the screen, and each shrinks to its own middle on a delay that
-- grows from the screen's middle out, so the world opens from the centre. Each square is a window onto its own copy of
-- the whole backdrop, laid where the backdrop lies, so the swap from the whole backdrop to the squares is the same
-- picture to the pixel; the squares are built hidden while the screen loads, so the swap costs nothing then. Only the
-- pixels are not in the squares: they fade out before the first square moves. No panel streaks: a copy placed in a
-- window rounds to a different pixel than the whole one, and their 1 px lines jumped at the swap (the shading is
-- smooth, so a pixel does not show).
--
-- A cover (a teleport out) is the way out run backwards: the squares grow in over the game from the edges to the
-- middle, and the whole backdrop takes over once the last has closed.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local Types = require(script.Parent.Types)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Progress = Motion.Progress

local Backdrop = {}

-- The flat colour under everything; LoadingScreen.client's first cover is this colour.
Backdrop.BASE = Color3.fromRGB(22, 16, 44)

-- The squares: they start this long after the screen starts leaving (the content mostly gone first), the last starts
-- SPREAD (and up to JITTER) later, and each takes SECONDS. EXIT_SECONDS is when the last is gone.
Backdrop.SQUARES_AT = 0.2
local Squares = table.freeze({
	ROWS = 9,
	SPREAD = 0.45,
	JITTER = 0.06,
	SECONDS = 0.3,
})
Backdrop.EXIT_SECONDS = Backdrop.SQUARES_AT + Squares.SPREAD + Squares.JITTER + Squares.SECONDS
-- A cover's squares have all closed by this, after it is shown.
Backdrop.COVER_SECONDS = Squares.SPREAD + Squares.JITTER + Squares.SECONDS

local Look = table.freeze({
	SHADE = Color3.fromRGB(6, 4, 14),
	-- The shading toward the top and bottom, then the sides: its transparency along the screen.
	SHADE_DOWN = table.freeze({ { 0, 0.15 }, { 0.3, 1 }, { 0.62, 1 }, { 1, 0.05 } }),
	SHADE_ACROSS = table.freeze({ { 0, 0.3 }, { 0.22, 1 }, { 0.78, 1 }, { 1, 0.3 } }),
	IN_SECONDS = 0.6,
	MOTES = 16,
	MOTE_LIFE_LOW = 5,
	MOTE_LIFE_HIGH = 9,
	MOTE_SIZE_LOW = 3,
	MOTE_SIZE_HIGH = 6,
	-- How far up the screen a mote rises over its life, as shares of the height.
	MOTE_RISE_LOW = 0.3,
	MOTE_RISE_HIGH = 0.6,
	MOTE_ALPHA_LOW = 0.2,
	MOTE_ALPHA_HIGH = 0.5,
	-- Its light: a square this many times its size, this much as bright.
	MOTE_GLOW = 3,
	MOTE_GLOW_ALPHA = 0.2,
	COLORS = table.freeze({ Palette.Pink, Palette.Violet, Palette.Lavender }),
})

local NEVER = math.huge

-- A steady pseudo-random 0 to 1 for a mote and its life, or a square, worked out from the clock alone.
local function scatter(a: number, b: number): number
	return (math.sin(a * 12.9898 + b * 78.233) * 43758.5453) % 1
end

-- 0 to 1 and back to 0 over a life, quick in and slower out, so a pixel swells in and shrinks away.
local function swell(t: number): number
	return math.min(t / 0.18, 1) * math.min((1 - t) / 0.35, 1)
end

local function mote(state: Types.TState, index: number, strength: () -> number): { Instance }
	local life = Look.MOTE_LIFE_LOW + (Look.MOTE_LIFE_HIGH - Look.MOTE_LIFE_LOW) * scatter(index, 1)
	local phase = scatter(index, 2)
	-- Where it is this frame: x and y as shares of the screen, its size in px, its strength and its colour's index.
	local at = derive(function(): { number }
		local age = (state.Now() - state.ShownAt()) / life + phase
		local generation = math.floor(age)
		local t = age - generation
		local seed = index * 31 + generation
		local x = scatter(seed, 3) + 0.012 * math.sin(2 * math.pi * (t + scatter(seed, 4)))
		local rise = Look.MOTE_RISE_LOW + (Look.MOTE_RISE_HIGH - Look.MOTE_RISE_LOW) * scatter(seed, 5)
		local y = 0.3 + 0.75 * scatter(seed, 6) - rise * t
		local size = Look.MOTE_SIZE_LOW + (Look.MOTE_SIZE_HIGH - Look.MOTE_SIZE_LOW) * scatter(seed, 7)
		local alpha = Look.MOTE_ALPHA_LOW + (Look.MOTE_ALPHA_HIGH - Look.MOTE_ALPHA_LOW) * scatter(seed, 8)
		local color = math.floor(scatter(seed, 9) * #Look.COLORS) + 1
		return { x, y, math.round(size * swell(t)), alpha * strength(), color }
	end)
	local color = function(): Color3
		return Look.COLORS[at()[5]]
	end
	local function square(name: string, scale: number, alpha: number, zIndex: number): Frame
		return create("Frame")({
			Name = name,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BorderSizePixel = 0,
			ZIndex = zIndex,
			BackgroundColor3 = color,
			Position = function()
				local where = at()
				return UDim2.fromScale(where[1], where[2])
			end,
			Size = function()
				local px = at()[3] * scale
				return UDim2.fromOffset(px, px)
			end,
			BackgroundTransparency = function()
				return 1 - at()[4] * alpha
			end,
			Visible = function()
				return at()[3] >= 1 and at()[4] > 0
			end,
		})
	end

	return {
		square(`MoteGlow{index}`, Look.MOTE_GLOW, Look.MOTE_GLOW_ALPHA, 1),
		square(`Mote{index}`, 1, 1, 2),
	}
end

-- The backdrop's picture: the base and the two shadings. Drawn once whole and once in every square, always from here,
-- so every copy is the same. `layered` (a source) is how far the shading has come in; nil is all the way, as it is by
-- the time the squares show (the screen leaves at the skip's 2 s at the earliest, the shading is in by IN_SECONDS), so
-- the squares' copies bind nothing.
local function picture(layered: (() -> number)?, props: { [any]: any }): Frame
	local function shade(rotation: number, keys: { { number } }): Frame
		local points = table.create(#keys)
		for index, key in keys do
			points[index] = NumberSequenceKeypoint.new(key[1], key[2])
		end
		return create("Frame")({
			Name = "Shade",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Look.SHADE,
			BorderSizePixel = 0,
			BackgroundTransparency = if layered
				then function()
					return 1 - layered()
				end
				else 0,
			create("UIGradient")({
				Rotation = rotation,
				Transparency = NumberSequence.new(points),
			}),
		})
	end

	return create("Frame")({
		Name = "Picture",
		BackgroundColor3 = Backdrop.BASE,
		BorderSizePixel = 0,
		shade(90, Look.SHADE_DOWN),
		shade(0, Look.SHADE_ACROSS),
		props,
	})
end

-- The squares tiling a screen of `width` x `height` design px, every edge from one rounded number so no seam opens
-- between two, each a px larger than its cell so a screen scaled off 1080 shows no hairline either. A square is a
-- window (it clips) onto the picture, held where the whole picture lies as the window shrinks round its middle.
local function squares(
	state: Types.TState,
	width: number,
	height: number,
	isLeaving: () -> boolean,
	isCovering: () -> boolean
): { Instance }
	local rows = Squares.ROWS
	local cols = math.max(1, math.ceil(width / (height / rows)))
	local reach = math.sqrt(0.5)
	local cells = table.create(rows * cols)
	for row = 0, rows - 1 do
		local top = math.round(row * height / rows)
		local bottom = math.round((row + 1) * height / rows)
		for col = 0, cols - 1 do
			local left = math.round(col * width / cols)
			local right = math.round((col + 1) * width / cols)
			local middle = Vector2.new((left + right) / 2, (top + bottom) / 2)
			local cell = Vector2.new(right - left + 1, bottom - top + 1)
			local dx = middle.X / width - 0.5
			local dy = middle.Y / height - 0.5
			local distance = math.sqrt(dx * dx + dy * dy) / reach
			local jitter = scatter(row * 97 + col, 11) * Squares.JITTER
			local delay = Backdrop.SQUARES_AT + distance * Squares.SPREAD + jitter
			local coverDelay = (1 - distance) * Squares.SPREAD + jitter
			-- The clock is read only while the squares move: at rest the hidden squares work out nothing.
			local size = derive(function(): Vector2
				local leaveAt = state.LeaveAt()
				if leaveAt ~= NEVER then
					local u = Progress(state.Now(), leaveAt + delay, Squares.SECONDS)
					return cell * (1 - u * u)
				end
				if not isCovering() then return cell end
				return cell * Motion.Out(Progress(state.Now(), state.ShownAt() + coverDelay, Squares.SECONDS))
			end)
			table.insert(
				cells,
				create("Frame")({
					Name = "Square",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(middle.X, middle.Y),
					BackgroundTransparency = 1,
					ClipsDescendants = true,
					Visible = function()
						return (isLeaving() or isCovering()) and size().X > 0.05
					end,
					Size = function()
						local s = size()
						return UDim2.fromOffset(s.X, s.Y)
					end,
					picture(nil, {
						Size = UDim2.fromOffset(width, height),
						Position = function()
							local s = size()
							return UDim2.fromOffset(s.X / 2 - middle.X, s.Y / 2 - middle.Y)
						end,
					}),
				})
			)
		end
	end
	return cells
end

-- `strength` is the pixels' (1 up, 0 gone), which init fades before the squares move.
function Backdrop.Build(state: Types.TState, strength: () -> number): Frame
	local isLeaving = derive(function(): boolean
		return state.LeaveAt() ~= NEVER
	end)
	local isCovering = if state.Mode == "Cover"
		then derive(function(): boolean
			return state.Now() < state.CoveredAt
		end)
		else function(): boolean
			return false
		end
	local covered = derive(function(): number
		return Motion.Out(Progress(state.Now(), state.CoveredAt, Look.IN_SECONDS))
	end)
	-- Only a join's shading comes in over the flat base: a cover's squares and an arrival's copy carry it whole.
	local layered = if state.Mode == "Join" then covered else nil
	local moteStrength = derive(function(): number
		return covered() * strength()
	end)

	local motes = table.create(Look.MOTES * 2)
	for index = 1, Look.MOTES do
		for _, square in mote(state, index, moteStrength) do
			table.insert(motes, square)
		end
	end

	-- Built for the screen's size as it loads, and again only if that changes.
	local width = derive(function(): number
		return math.round(state.Width())
	end)
	local height = derive(function(): number
		return math.round(state.Height())
	end)
	local cut = derive(function()
		local w, h = width(), height()
		return vide.untrack(function()
			return squares(state, w, h, isLeaving, isCovering)
		end)
	end)
	-- The whole picture and the squares' copies share this box, so the two are drawn alike to the pixel, held on the
	-- middle so a screen still being sized grows from there.
	local function centred(props: { [any]: any }): { [any]: any }
		props.AnchorPoint = Vector2.new(0.5, 0.5)
		props.Position = UDim2.fromScale(0.5, 0.5)
		props.Size = function()
			return UDim2.fromOffset(width(), height())
		end
		return props
	end

	return create("Frame")({
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		picture(
			layered,
			centred({
				Name = "Whole",
				Visible = function()
					return not isLeaving() and not isCovering()
				end,
			})
		),
		create("Frame")(centred({
			Name = "Squares",
			BackgroundTransparency = 1,
			cut,
		})),
		create("Frame")({
			Name = "Motes",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 3,
			motes,
		}),
	})
end

return Backdrop
