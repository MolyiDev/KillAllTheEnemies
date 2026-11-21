--!native
--!optimize 2
local clamp = math.clamp
local sqrt = math.sqrt
local abs = math.abs

-- Returns nx, nz, penetration for a circle (cx,cz,r) vs an AABB centered at (wx,wz)
-- with half-extents (hx,hz). penetration == 0 means no overlap.
return function(
	cx: number,
	cz: number,
	r: number,
	wx: number,
	wz: number,
	hx: number,
	hz: number
): (number, number, number)
	local dx = cx - wx
	local dz = cz - wz

	local qx = clamp(dx, -hx, hx)
	local qz = clamp(dz, -hz, hz)

	local vx = dx - qx
	local vz = dz - qz
	local d2 = vx * vx + vz * vz

	if d2 > 0 then
		local dist = sqrt(d2)
		if dist >= r then return 0, 0, 0 end
		return vx / dist, vz / dist, r - dist
	end

	-- circle center inside box: push out along shallowest axis
	local px = hx - abs(dx)
	local pz = hz - abs(dz)
	if px < pz then
		return if dx >= 0 then 1 else -1, 0, r + px
	else
		return 0, if dz >= 0 then 1 else -1, r + pz
	end
end
