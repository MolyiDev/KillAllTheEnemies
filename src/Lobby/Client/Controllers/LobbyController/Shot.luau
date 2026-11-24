-- The camera's shot of a party on its pad: from out in front (the pad's +Z, the way out), a little over their heads,
-- the bodies standing in the band of the screen the queue leaves clear between its map card and its clock, and a little
-- further back for each one, so the line has room as it grows.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PadsCore = require(ReplicatedStorage.Shared.Core.PadsCore)

local Tune = table.freeze({
	FOV = 50,
	-- A body from its feet to the top of its hair (studs), and the share of the screen's height it stands in: the queue
	-- leaves about 450 to 790 of 1080 clear.
	BODY_HEIGHT = 5.4,
	BODY_SHARE = 0.3,
	-- The bodies' middle this share of half the screen's height under the screen's middle (620 of 1080).
	DROP = 0.15,
	PITCH = math.rad(10),
	-- Pulled back by this share of the shot for each body after the first.
	SPREAD = 0.04,
	-- Room beside the outermost bodies' middles (studs), and the most of the screen's width the line may take.
	SIDE_ROOM = 2,
	WIDTH_SHARE = 0.8,
	-- A root this near a spot (studs, flat) stands on it.
	ON_SPOT = 1,
})

local Shot = {}

Shot.FOV = Tune.FOV

-- Where the pad's spots are in the world, for Taken. Pads never move, so this is worked out once per pad.
function Shot.SpotsOf(pad: BasePart): { Vector3 }
	local spots = table.create(#PadsCore.SPOTS)
	for index in PadsCore.SPOTS do
		spots[index] = PadsCore.SpotAt(pad, index).Position
	end
	return spots
end

-- Which of the spots (SpotsOf) a body stands on, as bits (spot 1 is bit 0). Every frame on a pad, so each root's
-- Position, an engine read, is read once.
function Shot.Taken(spots: { Vector3 }, roots: { [Model]: BasePart }): number
	local taken = 0
	local nearSquared = Tune.ON_SPOT * Tune.ON_SPOT
	for _, root in roots do
		local position = root.Position
		for index, spot in spots do
			local offset = position - spot
			if offset.X * offset.X + offset.Z * offset.Z > nearSquared then continue end
			taken = bit32.bor(taken, bit32.lshift(1, index - 1))
			break
		end
	end

	return taken
end

-- The eye and the point it looks at for the spots in `taken` (Taken's bits), on a viewport `aspect` wide for its
-- height. Nobody on a spot yet frames the first, where the host will stand. The shot is centred on the host's spot
-- whatever else it frames: the spots run further out on one side, and centred on the line the host stood off to it.
function Shot.Frame(pad: BasePart, taken: number, aspect: number): (Vector3, Vector3)
	if taken == 0 then taken = 1 end

	local centreX = PadsCore.SPOTS[1].X
	local reach, sumZ, count = 0, 0, 0
	for index, spot in PadsCore.SPOTS do
		if not bit32.btest(taken, bit32.lshift(1, index - 1)) then continue end
		reach = math.max(reach, math.abs(spot.X - centreX))
		sumZ += spot.Z
		count += 1
	end

	local tanHalf = math.tan(math.rad(Tune.FOV) / 2)
	local fitHeight = Tune.BODY_HEIGHT / (Tune.BODY_SHARE * 2 * tanHalf)
	local fitWidth = (reach + Tune.SIDE_ROOM) / (tanHalf * aspect * Tune.WIDTH_SHARE)
	local distance = math.max(fitHeight * (1 + Tune.SPREAD * (count - 1)), fitWidth)

	-- In pad space, looking back at the pad from its front and down a little.
	local forward = Vector3.new(0, -math.sin(Tune.PITCH), -math.cos(Tune.PITCH))
	local up = Vector3.new(0, math.cos(Tune.PITCH), -math.sin(Tune.PITCH))
	local middle = Vector3.new(centreX, pad.Size.Y / 2 + Tune.BODY_HEIGHT / 2, sumZ / count)
	local eye = middle - forward * distance
	local look = middle + up * (Tune.DROP * tanHalf * distance)
	return pad.CFrame:PointToWorldSpace(eye), pad.CFrame:PointToWorldSpace(look)
end

return Shot
