--!nonstrict
-- Pictures thrown out of a piece and pulled into a tab (Types.TFlight): the potions a brew made, into POTIONS; the souls
-- a dissolve gave back, into MUTATE. Two phases (UI.md, collect animations): a throw against drag that slows and
-- hangs, then a pull that keeps the throw's direction before it turns and speeds into the tab, bent by a share of the
-- trip. Landings are shuffled and spaced so they tick in one by one. One pool of pictures draws them all.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Types = require(script.Parent.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local derive = vide.derive

local Flight = {}

Flight.Timing = table.freeze({
	-- The throw slows to its hang over this long.
	THROW = 0.38,
	-- After the last throw, the first pull; then a landing every SPACING, the trip itself HOME long.
	HANG = 0.16,
	SPACING = 0.075,
	HOME = 0.46,
	-- How far the pull keeps the throw's direction, as a share of the trip.
	KEEP = 0.45,
	-- The picture shrinks to this share of its size as it lands.
	LANDED_SIZE = 0.45,
})

-- Enough for the biggest brew and a dissolve of a full row of potions' souls.
Flight.POOL = 48

local Timing = Flight.Timing

-- Plans one picture for each of `looks`, thrown from `from` into `to` from `at` a `stagger` apart in a fan opening
-- upward, and landing one by one in a shuffled order. `random` shuffles and jitters, so no two bursts are the same.
function Flight.Plan(
	looks: { Types.TFlightLook },
	from: Vector2,
	to: Vector2,
	at: number,
	stagger: number,
	random: Random
): { Types.TFlight }
	local count = #looks
	-- Each one's place in the landing order, 0 first.
	local ranks = table.create(count)
	for index = 1, count do
		ranks[index] = index - 1
	end
	for index = count, 2, -1 do
		local other = random:NextInteger(1, index)
		ranks[index], ranks[other] = ranks[other], ranks[index]
	end

	local firstHome = at + stagger * (count - 1) + Timing.THROW + Timing.HANG
	local flights = table.create(count)
	for index, look in looks do
		-- Spread over the upper half, a jitter each.
		local share = if count == 1 then 0.5 else (index - 1) / (count - 1)
		local angle = math.rad(-160 + 140 * share + random:NextNumber(-8, 8))
		local homeAt = firstHome + Timing.SPACING * ranks[index]
		flights[index] = {
			Picture = look.Picture,
			Color = look.Color,
			Size = look.Size,
			Tab = look.Tab,
			PotionId = look.PotionId,
			From = from,
			To = to,
			Direction = Vector2.new(math.cos(angle), math.sin(angle)),
			Reach = (if count == 1 then 70 else 90) + random:NextNumber(0, 70),
			ThrowAt = at + stagger * (index - 1),
			HomeAt = homeAt,
			LandAt = homeAt + Timing.HOME,
		}
	end

	return flights
end

-- Where `flight` is at `now` in the screen's 1920 x 1080 and how far it has shrunk (1 whole), or nil while it is not in
-- the air.
function Flight.At(flight: Types.TFlight, now: number): (Vector2?, number)
	if now < flight.ThrowAt or now >= flight.LandAt then return nil, 1 end
	local thrown = Motion.Decelerate(math.clamp((now - flight.ThrowAt) / Timing.THROW, 0, 1))
	local hang = flight.From + flight.Direction * (flight.Reach * thrown)
	if now < flight.HomeAt then return hang, 1 end

	local t = Motion.Accelerate((now - flight.HomeAt) / (flight.LandAt - flight.HomeAt))
	local trip = (flight.To - hang).Magnitude
	local bend = hang + flight.Direction * (trip * Timing.KEEP)
	local point = hang:Lerp(bend, t):Lerp(bend:Lerp(flight.To, t), t)
	return point, 1 - (1 - Timing.LANDED_SIZE) * t
end

-- The pool: picture `index` draws `state.Flights()[index]`, parked off the screen while there is none.
function Flight.Build(state: Types.TLabState): { ImageLabel }
	local list = table.create(Flight.POOL)
	for index = 1, Flight.POOL do
		local flight = derive(function(): Types.TFlight?
			return state.Flights()[index]
		end)
		-- Its point and shrink as one value (X, Y, share), nil while it is not in the air.
		local place = derive(function(): Vector3?
			local planned = flight()
			if not planned then return nil end
			local point, share = Flight.At(planned, state.Now())
			return if point then Vector3.new(point.X, point.Y, share) else nil
		end)
		list[index] = Components.Picture(function()
			local planned = flight()
			return if planned then planned.Picture else EIcons.PotionBottle
		end, {
			Name = "Flight",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				local point = place()
				if not point then return UDim2.fromOffset(-400, -400) end
				return UDim2.fromOffset(math.round(point.X), math.round(point.Y))
			end,
			Size = function()
				local planned = flight()
				local point = place()
				if not planned or not point then return UDim2.new() end
				return Components.PictureBox(math.round(planned.Size * point.Z))
			end,
			ImageColor3 = function()
				local planned = flight()
				return if planned then planned.Color else Color3.new(1, 1, 1)
			end,
			Visible = function()
				return place() ~= nil
			end,
			ZIndex = 20,
		})
	end

	return list
end

return Flight
