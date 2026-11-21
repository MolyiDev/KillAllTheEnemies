--!native
--!optimize 2
local vectorCreate = vector.create

return function(position: vector, charPositions: { [number]: vector }): (number, vector)
	local bestId: number
	local best: vector
	local bestDistSq = math.huge

	for id, charPos in charPositions do
		local dx = charPos.x - position.x
		local dz = charPos.z - position.z
		local distSq = dx * dx + dz * dz

		if distSq < bestDistSq then
			bestId = id
			best = charPos
			bestDistSq = distSq
		end
	end

	return bestId, vectorCreate(best.x - position.x, best.z - position.z)
end
