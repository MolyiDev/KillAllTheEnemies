--!nonstrict
-- The Gems a purchase is paid with, flying out of the HUD's Gems counter into what they buy (the weapons screen's gun
-- or star, the classes screen's star). Each is thrown out of the counter, hangs, and is pulled in on its own bend
-- (UI.md 5j); they land one after another, and what they buy is shown on the last.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(script.Parent.Components)
local Motion = require(script.Parent.Motion)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
local Progress = Motion.Progress

local Tune = table.freeze({
	COUNT = 8,
	-- Each sets off this long after the one before it and flies this long.
	STAGGER = 0.03,
	FLIGHT = 0.45,
	-- The throw: how far out of the counter, in px, and the fan it is thrown across (degrees from straight down-left).
	THROW_MIN = 60,
	THROW_MAX = 120,
	FAN = 70,
	-- The bend of the pull home, as a share of the trip, to one side or the other.
	BEND_MIN = 0.2,
	BEND_MAX = 0.45,
	-- How much of the pace is kept from the throw (the rest is the pull, accelerating into the target).
	LINEAR = 0.35,
	GEM = 26,
	-- In and out of sight over these shares of a flight, never a blink.
	FADE_IN = 0.12,
	FADE_OUT = 0.15,
})

export type TSpec = {
	-- The screen's clock, and the moment the Gems set off.
	Now: () -> number,
	PaidAt: () -> number,
	-- Where they set off from and land, in the px of the frame the pieces are put in.
	From: () -> Vector2,
	To: () -> Vector2,
	-- Each landing, and whether it was the last.
	OnLanded: (isLast: boolean) -> (),
}

local GemFlight = {}

-- How long from the Gems setting off to the last landing: the moment what they buy is shown.
GemFlight.SECONDS = (Tune.COUNT - 1) * Tune.STAGGER + Tune.FLIGHT

-- The same throw for the same piece every time, so a purchase reads the same twice.
local function scatter(index: number, salt: number): number
	local x = math.sin(index * 12.9898 + salt * 78.233) * 43758.5453
	return x - math.floor(x)
end

local function bezier(a: Vector2, b: Vector2, c: Vector2, d: Vector2, t: number): Vector2
	local u = 1 - t
	return a * (u * u * u) + b * (3 * u * u * t) + c * (3 * u * t * t) + d * (t * t * t)
end

-- The pieces, to put in a frame whose px From and To are in.
function GemFlight.Build(spec: TSpec): { ImageLabel }
	local landed = derive(function(): number
		local since = spec.Now() - spec.PaidAt() - Tune.FLIGHT
		if since < 0 then return 0 end
		return math.min(Tune.COUNT, math.floor(since / Tune.STAGGER) + 1)
	end)
	-- All landed before any flight, so mounting the screen sounds nothing.
	local lastLanded = Tune.COUNT
	vide.effect(function()
		local count = landed()
		vide.untrack(function()
			if count > lastLanded then spec.OnLanded(count == Tune.COUNT) end
			lastLanded = count
		end)
	end)

	local pieces = table.create(Tune.COUNT)
	for index = 1, Tune.COUNT do
		local angle = math.rad(180 + 45 + (scatter(index, 1) - 0.5) * Tune.FAN)
		local throw = Vector2.new(math.cos(angle), -math.sin(angle))
			* (Tune.THROW_MIN + (Tune.THROW_MAX - Tune.THROW_MIN) * scatter(index, 2))
		local bend = (Tune.BEND_MIN + (Tune.BEND_MAX - Tune.BEND_MIN) * scatter(index, 3))
			* (if index % 2 == 0 then 1 else -1)
		local t = derive(function(): number
			return Progress(spec.Now(), spec.PaidAt(), Tune.FLIGHT, Tune.STAGGER * (index - 1))
		end)

		pieces[index] = Components.Picture(EIcons.Gem, {
			Name = `Gem{index}`,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				local progress = t()
				local from, to = spec.From(), spec.To()
				local trip = to - from
				local side = Vector2.new(-trip.Y, trip.X) * bend
				local along = Tune.LINEAR * progress + (1 - Tune.LINEAR) * progress * progress
				local at = bezier(from, from + throw, to + side - trip * 0.15, to, along)
				return UDim2.fromOffset(at.X, at.Y)
			end,
			Size = Components.PictureBox(Tune.GEM),
			ImageTransparency = function()
				local progress = t()
				local appear = math.clamp(progress / Tune.FADE_IN, 0, 1)
				local vanish = math.clamp((1 - progress) / Tune.FADE_OUT, 0, 1)
				return 1 - math.min(appear, vanish)
			end,
			Visible = function()
				local progress = t()
				return progress > 0 and progress < 1
			end,
			ZIndex = 20,
			create("UIScale")({
				Scale = function()
					return 1 - 0.45 * t()
				end,
			}),
		})
	end

	return pieces
end

return GemFlight
