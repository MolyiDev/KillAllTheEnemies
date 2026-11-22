-- Headless check of the kill coins' flight (Game/Client/Utils/coinFlight): a kill's coins thrown away from the taker
-- at several distances, with him standing, walking in, walking off and strafing. Reports when each lands, the slowest
-- speed in the hang against the fastest in the pull (that contrast is the effect), and how far a coin went back
-- beyond the kill, away from him; and how high it stays over the crowd (the floor is y 0, a zombie's head 5.1). Run from the repo root:
--   lune run tools/lune/coins.luau "$PWD"
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local H = require("./harness")(process.args[1])

local Vector3 = roblox.Vector3
local CoinFlight = H.require("StarterPlayer/StarterPlayerScripts/Client/Utils/coinFlight")

local DT = 1 / 60
local WALK_SPEED = 16
local COINS = 4
-- CoinsController's throw and hang, without the jitter.
local UP_SPEED = 18
local SIDE_SPEED = 11
local HANG_FIRST, HANG_SPREAD = 0.3, 0.22
local THROW_ARC = 3.5
local CHEST_UP = Vector3.new(0, 1, 0)

local function run(label: string, distance: number, walk: Vector3)
	local kill = Vector3.new(0, 4, 0)
	local root = Vector3.new(distance, 3, 0)
	local away = Vector3.new(-1, 0, 0)
	local flights = {}
	for i = 1, COINS do
		local order = (i - 1) / (COINS - 1)
		local angle = math.atan2(away.Z, away.X) + ((i - 0.5) / COINS - 0.5) * THROW_ARC
		local velocity = Vector3.new(math.cos(angle) * SIDE_SPEED, UP_SPEED, math.sin(angle) * SIDE_SPEED)
		flights[i] = {
			Flight = CoinFlight.New(kill, velocity, HANG_FIRST + HANG_SPREAD * order ^ 0.8),
			Landed = nil :: number?,
			MinPopSpeed = math.huge,
			MaxSpeed = 0,
			Stray = 0,
			Lowest = math.huge,
			Highest = -math.huge,
		}
	end

	local t = 0
	local left = COINS
	while left > 0 and t < 5 do
		t += DT
		root += walk * DT
		for _, c in flights do
			if c.Landed then continue end
			local before = c.Flight.Position
			if CoinFlight.Step(c.Flight, root + CHEST_UP, DT) then
				c.Landed = t
				left -= 1
				continue
			end
			local speed = (c.Flight.Position - before).Magnitude / DT
			if c.Flight.IsPulling then
				c.MaxSpeed = math.max(c.MaxSpeed, speed)
			elseif c.Flight.Age > 0.15 then
				c.MinPopSpeed = math.min(c.MinPopSpeed, speed)
			end
			c.Stray = math.max(c.Stray, (c.Flight.Position - kill):Dot(away))
			-- Over the crowd: on its way in, more than 3 studs from both the kill and him.
			local at = c.Flight.Position
			local fromKill = Vector3.new(at.X - kill.X, 0, at.Z - kill.Z).Magnitude
			local fromHim = Vector3.new(at.X - root.X, 0, at.Z - root.Z).Magnitude
			if c.Flight.IsPulling and fromKill > 3 and fromHim > 3 then c.Lowest = math.min(c.Lowest, at.Y) end
			c.Highest = math.max(c.Highest, at.Y)
		end
	end

	local lands, hang, peak, stray, lowest, highest = {}, math.huge, 0, 0, math.huge, -math.huge
	for i, c in flights do
		lands[i] = if c.Landed then string.format("%.2f", c.Landed) else "NEVER"
		hang = math.min(hang, c.MinPopSpeed)
		peak = math.max(peak, c.MaxSpeed)
		stray = math.max(stray, c.Stray)
		lowest = math.min(lowest, c.Lowest)
		highest = math.max(highest, c.Highest)
	end
	print(
		string.format(
			"%-26s lands %s | hang %4.1f -> peak %5.1f studs/s | back %.1f | over the crowd y >= %s, top %.1f",
			label,
			table.concat(lands, " "),
			hang,
			peak,
			stray,
			if lowest < math.huge then string.format("%.1f", lowest) else "-",
			highest
		)
	)
end

for _, distance in { 4, 12, 25, 50, 90 } do
	run(string.format("%2d studs, standing", distance), distance, Vector3.zero)
	run(string.format("%2d studs, walking in", distance), distance, Vector3.new(-WALK_SPEED, 0, 0))
	run(string.format("%2d studs, walking off", distance), distance, Vector3.new(WALK_SPEED, 0, 0))
	run(string.format("%2d studs, strafing", distance), distance, Vector3.new(0, 0, WALK_SPEED))
end

-- A bought pack's shower (CoinFlight.ThrowShower), the small pack and the big one: when its coins land and how the
-- gaps close, how far they stray from the chest, and how slow they hang against how fast they come in.
local seed = 7
local random = {
	NextNumber = function(_, least: number?, most: number?): number
		seed = (seed * 1103515245 + 12345) % 2147483648
		local share = seed / 2147483648
		return if least and most then least + (most - least) * share else share
	end,
}
function random.NextInteger(self, least: number, most: number): number
	return math.min(least + math.floor(self:NextNumber() * (most - least + 1)), most)
end

for _, amount in { 1000, 99999 } do
	local showers = CoinFlight.ThrowShower(amount, random :: any)
	local lands = {}
	local widest, highest, lowest, slowest, fastest, worstEnd = 0, -math.huge, math.huge, math.huge, 0, 0
	for i, shower in showers do
		lands[i] = shower.LandAt
		local last = CoinFlight.ShowerAt(shower, 0)
		local t = 0
		while t + DT < shower.LandAt do
			t += DT
			local at = CoinFlight.ShowerAt(shower, t)
			local speed = (at - last).Magnitude / DT
			last = at
			widest = math.max(widest, Vector3.new(at.X, 0, at.Z).Magnitude)
			highest = math.max(highest, at.Y)
			lowest = math.min(lowest, at.Y)
			if t > 0.3 and t < shower.HangAt then slowest = math.min(slowest, speed) end
			if t > shower.HangAt then fastest = math.max(fastest, speed) end
		end
		worstEnd = math.max(worstEnd, CoinFlight.ShowerAt(shower, shower.LandAt).Magnitude)
	end

	table.sort(lands)
	local count = #lands
	print(
		string.format(
			"pack of %d: %d coins land %.2f to %.2f s, gaps %.0f ms closing to %.0f ms | %.1f studs wide, y %.1f to %.1f from the chest | hang %.1f -> pull %.1f studs/s | ends %.3f studs off",
			amount,
			count,
			lands[1],
			lands[count],
			(lands[2] - lands[1]) * 1000,
			(lands[count] - lands[count - 1]) * 1000,
			widest,
			lowest,
			highest,
			slowest,
			fastest,
			worstEnd
		)
	)
end
