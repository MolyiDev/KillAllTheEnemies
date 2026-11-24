--!nonstrict
-- The chip on a button that says something waits behind it (UI.md "Notices"): an up arrow while something there can
-- be bought or raised with what the player holds, "!" (or how many) while something there is new or ready to claim.
-- One look for every button in both places (GAME_LOOK), so a player learns it once; the others stay drawable for the
-- bench (Stories/Notice) until one is picked.
--
-- It comes and goes on vide springs, so it needs no clock; its call is a curve of the caller's clock from the caller's
-- stamp, so a row of them can call one after another and the caller's clock stops once they have.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(script.Parent.Components)
local Hand = require(script.Parent.Hand)
local Motion = require(script.Parent.Motion)
local Theme = require(script.Parent.Theme)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
local spring = vide.spring
local Palette = Theme.Palette
local Progress = Motion.Progress

export type TKind = "Upgrade" | "New"
-- Sticker: a gold or red chip in a thick ink rim, the toy's look (the first round, the control). Plaque: his ink
-- square with a 2 px edge and a glow in the accent, the mark in the accent. Tag: a flat block of the accent with a
-- dark lip, like the index's NEW. Framed: the plaque under his white corner brackets.
export type TLook = "Sticker" | "Plaque" | "Tag" | "Framed"

export type TSpec = {
	Kind: TKind,
	-- Its side in px.
	Size: number,
	-- Whether it is up; nil to follow Count. Read as a vide source.
	IsShown: (() -> boolean)?,
	-- How many wait (New only): worn instead of "!", and up while above 0. Read as a vide source.
	Count: (() -> number)?,
	-- The caller's clock and its call stamp (an os.clock moment): each stamp, `CallDelay` later, the chip calls. The
	-- caller keeps Now ticking for Notice.CALL_SECONDS past the stamp and the delay. Read as vide sources.
	Now: (() -> number)?,
	CallAt: (() -> number)?,
	CallDelay: number?,
	-- Nil for GAME_LOOK; the bench names one.
	Look: TLook?,
}

-- The Sticker's faces, top to bottom: lit, its colour, deep.
local STICKER_FACES = table.freeze({
	Upgrade = table.freeze({
		Lit = Color3.fromRGB(255, 231, 150),
		Face = Palette.Gold,
		Deep = Color3.fromRGB(226, 140, 24),
	}),
	New = table.freeze({
		Lit = Color3.fromRGB(255, 138, 150),
		Face = Color3.fromRGB(255, 59, 79),
		Deep = Color3.fromRGB(196, 24, 52),
	}),
})
-- The modern looks' accent: his gold for what can be raised, his pink for what calls.
local ACCENTS = table.freeze({ Upgrade = Palette.Gold, New = Palette.Pink })
-- His + button's ink face; a Tag's lip.
local PLAQUE_FACE = Color3.fromRGB(21, 15, 40)
local LIP = Color3.new(0, 0, 0)

-- Shares of the chip's side unless named in px.
local Look = table.freeze({
	STICKER_RIM = 0.07,
	STICKER_CORNER = 0.16,
	-- The lit line inside the Sticker's top edge.
	SHINE = 0.35,
	-- The modern looks: a 2 px edge (his + button's), corners of 2 px, a 2 px lip under a Tag.
	EDGE = 2,
	CORNER = 2,
	LIP = 2,
	LIP_TRANSPARENCY = 0.7,
	MARK = 0.66,
	ARROW = 0.6,
	COUNT_TEXT = 0.64,
	-- The Framed look's bracket legs, and how faint they and its edge are at rest.
	BRACKET_LEG = 0.3,
	BRACKET_TRANSPARENCY = 0.35,
	FRAMED_EDGE = 0.55,
	-- Its glow at rest, how much the flash and the call light it, and its blur.
	GLOW = 0.5,
	GLOW_LIT = 0.4,
	GLOW_CALL = 0.3,
	GLOW_BLUR = 0.5,
})

-- How each look moves. Toy: it pops in from nothing turned back, throws sparks, and its "!" rings like a bell (the
-- Sticker's, kept with it). Calm: it grows in from FROM while it fades in, with a little lift past its size and none
-- of the rest (a modern UI's way in), and its "!" calls in light only.
local MOTIONS = table.freeze({
	Toy = table.freeze({
		FROM = 0,
		POP_PERIOD = 0.42,
		POP_DAMPING = 0.32,
		ARRIVE_POP = 0.5,
		LEAVE_SWELL = 0.24,
		COUNT_POP = 0.3,
		COUNT_DOWN_POP = -0.12,
		ARRIVE_TURN = -22,
		HAS_SPARKS = true,
		HAS_BELL = true,
		-- The arrow's call dips first and sails past its mark.
		SAILS = true,
		RING_REACH = 0.45,
	}),
	Calm = table.freeze({
		FROM = 0.6,
		POP_PERIOD = 0.3,
		POP_DAMPING = 0.7,
		ARRIVE_POP = 0.12,
		LEAVE_SWELL = 0.08,
		COUNT_POP = 0.14,
		COUNT_DOWN_POP = -0.06,
		ARRIVE_TURN = 0,
		HAS_SPARKS = false,
		HAS_BELL = false,
		SAILS = false,
		RING_REACH = 0.35,
	}),
})
local LOOKS = table.freeze({
	Sticker = MOTIONS.Toy,
	Plaque = MOTIONS.Calm,
	Tag = MOTIONS.Calm,
	Framed = MOTIONS.Calm,
})

local Tune = table.freeze({
	-- Up quickly and down slower, both critically damped so it never dips under nothing: going, it swells first (the
	-- kick) and the slow start of the fall lets the swell be seen before it shrinks away.
	RISE_PERIOD = 0.16,
	FALL_PERIOD = 0.34,
	TURN_PERIOD = 0.38,
	TURN_DAMPING = 0.3,
	-- White over the face, squared as it fades (a hit of white, gone before the face reads as pale).
	FLASH_PERIOD = 0.28,
	FLASH = 0.85,
	-- One ring off the chip, RING_LINE px, gone by RING_LIFE of the burst.
	RING_LINE = 2,
	RING_LIFE = 0.6,
	-- The burst's clock: a critically damped spring thrown from 0 toward BURST_END at BURST_SPEED, read until it passes
	-- 1 (as the Gems counter's chips).
	BURST_PERIOD = 1.2,
	BURST_END = 1.2,
	BURST_SPEED = 3.4,
	-- The Toy's sparks: SPARKS of them all round, born SPARK_BORN of the side from its middle, thrown SPARK_REACH
	-- further, falling SPARK_FALL by the end; SPARK_SIZE of the side, spun up to SPARK_SPIN degrees.
	SPARKS = 8,
	SPARK_BORN = 0.62,
	SPARK_REACH = Vector2.new(0.35, 0.8),
	SPARK_FALL = 0.25,
	SPARK_SIZE = Vector2.new(0.14, 0.22),
	SPARK_SPIN = 260,
})

-- The call: the arrow leaves through the chip's top and comes back up from under it onto its mark (the Toy winds it
-- down first and lets it sail past); the Toy's "!" rings like a bell. The light crosses the face and the glow lifts.
local Call = table.freeze({
	SECONDS = 0.8,
	-- The arrow is gone out of the top by this share of the call.
	ARROW_OUT = 0.4,
	BELL_TURN = 18,
	BELL_POP = 0.16,
	-- The light crosses in this share of the call, starting with it.
	SHEEN = 0.7,
})

local Notice = {}

Notice.CALL_SECONDS = Call.SECONDS
Notice.LOOKS = table.freeze({ "Sticker", "Plaque", "Tag", "Framed" })
-- The look the game draws.
Notice.GAME_LOOK = "Plaque" :: TLook

-- The same throw for the same spark every time: 0 to 1.
local function scatter(index: number, salt: number): number
	local x = math.sin(index * 12.9898 + salt * 78.233) * 43758.5453
	return x - math.floor(x)
end

-- The sparks thrown off it as `travel` runs 0 to 1, drawn only while it does: born past the chip's edge all round,
-- flying out against drag and falling a little, spinning, shrinking and fading to nothing.
local function sparks(size: number, color: Color3, travel: () -> number, isBursting: () -> boolean): { Frame }
	local pieces = table.create(Tune.SPARKS)
	for index = 1, Tune.SPARKS do
		local angle = math.rad((index - 1 + (scatter(index, 1) - 0.5) * 0.6) * 360 / Tune.SPARKS - 90)
		local out = Vector2.new(math.cos(angle), math.sin(angle))
		local reach = size * Motion.Lerp(Tune.SPARK_REACH.X, Tune.SPARK_REACH.Y, scatter(index, 2))
		local side = size * Motion.Lerp(Tune.SPARK_SIZE.X, Tune.SPARK_SIZE.Y, scatter(index, 3))
		local spin = Tune.SPARK_SPIN * (2 * scatter(index, 4) - 1)
		pieces[index] = create("Frame")({
			Name = "Spark",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				local t = travel()
				local at = out * (size * Tune.SPARK_BORN + reach * Motion.Out(t))
					+ Vector2.new(0, size * Tune.SPARK_FALL * t * t)
				return UDim2.new(0.5, math.round(at.X), 0.5, math.round(at.Y))
			end,
			Size = function()
				local shown = math.max(1, math.round(side * (1 - 0.6 * travel())))
				return UDim2.fromOffset(shown, shown)
			end,
			Rotation = function()
				return 45 + spin * travel()
			end,
			BackgroundColor3 = if index % 2 == 0 then Palette.White else color,
			BackgroundTransparency = function()
				local t = travel()
				return t * t
			end,
			BorderSizePixel = 0,
			Visible = isBursting,
			ZIndex = 1,
		})
	end

	return pieces
end

-- What a look draws inside the chip, under the mark: its edge and face (or the Sticker's rim and face), with the
-- transparency `faded` puts on a base one; `inner` (the mark, the light, the flash and the face's own properties) goes
-- in the face. Returns the pieces, their corner and the glow's colour.
type TBody = { Pieces: { Instance }, Corner: number, Glow: Color3 }

local function stickerBody(kind: TKind, size: number, faded: (number) -> number, inner: { any }): TBody
	local face = STICKER_FACES[kind]
	local rim = math.max(2, math.round(size * Look.STICKER_RIM))
	local corner = math.round(size * Look.STICKER_CORNER)
	local innerCorner = math.max(corner - rim, 1)
	local faceFrame = create("Frame")({
		Name = "Face",
		Position = UDim2.fromOffset(rim, rim),
		Size = UDim2.new(1, -2 * rim, 1, -2 * rim),
		BackgroundColor3 = Palette.White,
		BackgroundTransparency = function()
			return faded(0)
		end,
		BorderSizePixel = 0,
		create("UICorner")({ CornerRadius = UDim.new(0, innerCorner) }),
		create("UIGradient")({
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, face.Lit),
				ColorSequenceKeypoint.new(0.45, face.Face),
				ColorSequenceKeypoint.new(1, face.Deep),
			}),
		}),
		create("Frame")({
			Name = "Shine",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 1),
			Size = UDim2.new(1, -2 * innerCorner, 0, 1),
			BackgroundColor3 = Palette.White,
			BackgroundTransparency = function()
				return faded(Look.SHINE)
			end,
			BorderSizePixel = 0,
			ZIndex = 2,
		}),
		inner,
	})

	return {
		Pieces = { create("UICorner")({ CornerRadius = UDim.new(0, corner) }), faceFrame },
		Corner = corner,
		Glow = face.Face,
	}
end

local function modernBody(look: TLook, kind: TKind, size: number, faded: (number) -> number, inner: { any }): TBody
	local accent = ACCENTS[kind]
	local isTag = look == "Tag"
	local edge = if isTag then 0 else Look.EDGE
	local faceFrame = create("Frame")({
		Name = "Face",
		Position = UDim2.fromOffset(edge, edge),
		Size = UDim2.new(1, -2 * edge, 1, -2 * edge),
		BackgroundColor3 = if isTag then accent else PLAQUE_FACE,
		BackgroundTransparency = function()
			return faded(0)
		end,
		BorderSizePixel = 0,
		create("UICorner")({ CornerRadius = UDim.new(0, math.max(Look.CORNER - edge, 1)) }),
		-- A Tag's dark lip along its bottom, as his slabs' faces have.
		if isTag
			then create("Frame")({
				Name = "Lip",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(1, 0, 0, Look.LIP),
				BackgroundColor3 = LIP,
				BackgroundTransparency = function()
					return faded(Look.LIP_TRANSPARENCY)
				end,
				BorderSizePixel = 0,
				ZIndex = 2,
			})
			else nil,
		inner,
	})
	local pieces = { create("UICorner")({ CornerRadius = UDim.new(0, Look.CORNER) }), faceFrame }
	if look == "Framed" then
		table.insert(
			pieces,
			Components.Brackets(nil, function()
				return faded(Look.BRACKET_TRANSPARENCY)
			end, math.round(size * Look.BRACKET_LEG))
		)
	end

	return { Pieces = pieces, Corner = Look.CORNER, Glow = accent }
end

-- The colour the chip itself is drawn in (the edge behind the face): ink round the Sticker, the accent round a
-- Plaque, a fainter one round a Framed, and the accent under a Tag's own face (so its glow has a shape to follow).
local function chipBack(look: TLook, kind: TKind): (Color3, number)
	if look == "Sticker" then return Palette.Ink, 0 end
	if look == "Framed" then return ACCENTS[kind], Look.FRAMED_EDGE end
	return ACCENTS[kind], 0
end

-- The mark's ink: the Sticker's are drawn in their own colours; a Plaque's and a Framed's take the accent, a Tag's
-- arrow goes to ink on its gold and its "!" stays white on its pink.
local function markColor(look: TLook, kind: TKind): Color3
	if look == "Sticker" then return Palette.White end
	if look == "Tag" then return if kind == "Upgrade" then Palette.Ink else Palette.White end
	return ACCENTS[kind]
end

-- One chip. `props` places it (its middle is its AnchorPoint) and may set its ZIndex.
function Notice.Build(spec: TSpec, props: { [any]: any }): Frame
	local size = spec.Size
	local look: TLook = spec.Look or Notice.GAME_LOOK
	local moves = LOOKS[look]
	local kind = spec.Kind
	local isUpgrade = kind == "Upgrade"
	local count = spec.Count
	local isShown = derive(function(): boolean
		if spec.IsShown then return spec.IsShown() end
		return count ~= nil and count() > 0
	end)

	local function target(): number
		return if isShown() then 1 else 0
	end
	local rise = Hand.Spring(target, Tune.RISE_PERIOD)
	local fall = Hand.Spring(target, Tune.FALL_PERIOD)
	local function shown(): number
		return if isShown() then rise() else fall()
	end
	-- Out of the renderer once it is smaller than a few px: the spring's tail left a speck for a quarter second.
	local isDrawn = derive(function(): boolean
		return shown() > 0.06
	end)
	-- How opaque it is, read once for every piece that fades with it: the Calm looks fade in and out with their size,
	-- the Toy only grows, so it stays solid.
	local opacity = derive(function(): number
		if moves.FROM == 0 then return 1 end
		return math.clamp(shown(), 0, 1)
	end)
	local function faded(base: number): number
		return 1 - (1 - base) * opacity()
	end
	local pop, strikePop = Hand.Kick(moves.POP_PERIOD, moves.POP_DAMPING)
	local flash, strikeFlash = Hand.Kick(Tune.FLASH_PERIOD, 1)
	-- The Toy's turn as it lands; nothing turns a Calm one.
	local turn, strikeTurn
	if moves.ARRIVE_TURN ~= 0 then
		turn, strikeTurn = Hand.Kick(Tune.TURN_PERIOD, Tune.TURN_DAMPING)
	end
	local burstTravel, throwBurst = spring(function()
		return Tune.BURST_END
	end, Tune.BURST_PERIOD, 1)
	local travel = derive(function(): number
		return math.min(burstTravel(), 1)
	end)
	local isBursting = derive(function(): boolean
		local t = travel()
		return t > 0 and t < 1
	end)
	local ringed = derive(function(): number
		return math.min(travel() / Tune.RING_LIFE, 1)
	end)

	local function burst(popBy: number)
		strikePop(popBy)
		strikeFlash(1)
		throwBurst({ position = 0, velocity = Tune.BURST_SPEED })
	end

	-- Up: it comes in with a flash and one ring. Down: it swells, then shrinks away.
	local wasShown = isShown()
	vide.effect(function()
		local up = isShown()
		vide.untrack(function()
			if up and not wasShown then
				burst(moves.ARRIVE_POP)
				if strikeTurn then strikeTurn(moves.ARRIVE_TURN) end
			elseif wasShown and not up then
				strikePop(moves.LEAVE_SWELL)
			end
			wasShown = up
		end)
	end)

	-- The count it wears: the last one above 0, so it shrinks away still wearing it. Going up while up bursts again;
	-- going down gives a little.
	local worn
	if count then
		worn = vide.source(math.max(count(), 1))
		local last = count()
		vide.effect(function()
			local current = count()
			vide.untrack(function()
				if current > 0 then worn(current) end
				if current > last and last > 0 then
					burst(moves.COUNT_POP)
				elseif current < last and current > 0 then
					strikePop(moves.COUNT_DOWN_POP)
				end
				last = current
			end)
		end)
	end

	-- The call, 0 to 1 from the stamp (1 at rest), and only while it is up.
	local called = derive(function(): number
		if not spec.Now or not spec.CallAt or not isShown() then return 1 end
		return Progress(spec.Now(), spec.CallAt(), Call.SECONDS, spec.CallDelay)
	end)
	-- The arrow's height off its mark in px: out of the top, then up from under the chip onto its mark (a sailing one
	-- dips first and sails past).
	local arrowY
	if isUpgrade then
		arrowY = derive(function(): number
			local t = called()
			if t >= 1 then return 0 end
			if t < Call.ARROW_OUT then
				local out = t / Call.ARROW_OUT
				return math.round(-size * (if moves.SAILS then Motion.InBack(out) else Motion.Accelerate(out)))
			end
			local back = (t - Call.ARROW_OUT) / (1 - Call.ARROW_OUT)
			return math.round(size * (1 - (if moves.SAILS then Motion.OutBack(back) else Motion.Decelerate(back))))
		end)
	end
	-- The Toy's "!" swinging like a bell, 0 at rest.
	local bell = if moves.HAS_BELL and not isUpgrade
		then derive(function(): number
			return Motion.Swing(called())
		end)
		else nil
	local sheen = derive(function(): number
		return math.min(called() / Call.SHEEN, 1)
	end)

	local ink = markColor(look, kind)
	local mark
	if count then
		local textSize = math.round(size * Look.COUNT_TEXT)
		mark = create("TextLabel")({
			Name = "Count",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			FontFace = Theme.Font.Display,
			TextSize = textSize,
			TextColor3 = ink,
			TextTransparency = function()
				return faded(0)
			end,
			Text = function()
				local current = worn()
				return if current > 9 then "9+" else tostring(current)
			end,
			ZIndex = 4,
			if look == "Sticker" then Components.Ink(textSize, 1) else nil,
		})
	else
		local picture = if look == "Sticker"
			then (if isUpgrade then EIcons.UpArrow else EIcons.Exclamation)
			else (if isUpgrade then EIcons.ArrowUp else EIcons.Exclamation)
		mark = Components.Picture(picture, {
			Name = "Mark",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = if arrowY
				then function()
					return UDim2.new(0.5, 0, 0.5, arrowY())
				end
				else UDim2.fromScale(0.5, 0.5),
			Size = Components.PictureBox(
				math.round(size * (if isUpgrade and look ~= "Sticker" then Look.ARROW else Look.MARK))
			),
			ImageColor3 = ink,
			ImageTransparency = function()
				return faded(0)
			end,
			ZIndex = 4,
		})
	end

	local inner = {
		-- The arrow leaves through the top and comes back from under it.
		ClipsDescendants = isUpgrade,
		Components.Sheen(sheen, 3),
		mark,
		create("Frame")({
			Name = "Flash",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Palette.White,
			BorderSizePixel = 0,
			ZIndex = 5,
			Visible = function()
				return flash() > 0.01
			end,
			BackgroundTransparency = function()
				local f = flash()
				return 1 - Tune.FLASH * f * f
			end,
		}),
	}
	local body = if look == "Sticker"
		then stickerBody(kind, size, faded, inner)
		else modernBody(look, kind, size, faded, inner)
	local back, backTransparency = chipBack(look, kind)

	return create("Frame")({
		Name = "Notice",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		Visible = isDrawn,
		ZIndex = 10,
		-- The ring and the sparks are the chip's, not carried by its pop.
		create("Frame")({
			Name = "Ring",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = function()
				local grow = math.round(size * moves.RING_REACH * Motion.Out(ringed()))
				return UDim2.new(1, 2 * grow, 1, 2 * grow)
			end,
			BackgroundTransparency = 1,
			Visible = function()
				local t = ringed()
				return t > 0 and t < 1
			end,
			create("UICorner")({ CornerRadius = UDim.new(0, body.Corner) }),
			create("UIStroke")({
				Color = body.Glow,
				Thickness = Tune.RING_LINE,
				Transparency = ringed,
			}),
		}),
		if moves.HAS_SPARKS then sparks(size, body.Glow, travel, isBursting) else nil,
		create("Frame")({
			Name = "Chip",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = back,
			BackgroundTransparency = function()
				return faded(backTransparency)
			end,
			BorderSizePixel = 0,
			ZIndex = 2,
			Rotation = if turn or bell
				then function()
					return (if turn then turn() else 0) + (if bell then Call.BELL_TURN * bell() else 0)
				end
				else 0,
			create("UIScale")({
				Scale = function()
					local rung = if bell then Call.BELL_POP * Motion.Bump(math.min(called() * 2, 1)) else 0
					return math.max(Motion.Lerp(moves.FROM, 1, shown()) * (1 + pop() + rung), 0)
				end,
			}),
			create("UIShadow")({
				BlurRadius = UDim.new(0, math.round(size * Look.GLOW_BLUR)),
				Color = body.Glow,
				Offset = UDim2.new(),
				Spread = UDim2.new(),
				Transparency = function()
					local lit = Look.GLOW_LIT * flash() + Look.GLOW_CALL * Motion.Bump(called())
					return faded(math.max(Look.GLOW - lit, 0))
				end,
				ZIndex = -1,
			}),
			body.Pieces,
		}),
		props,
	})
end

return Notice
