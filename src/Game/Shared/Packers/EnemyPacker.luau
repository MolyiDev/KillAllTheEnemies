--!native
--!optimize 2
-- The enemy position stream. Per enemy: u16 id, three u16 coordinates in fixed point and a u8 yaw = 9 bytes, behind a
-- u16 count. A full packet at the cap is 2,297 bytes, so it stays one reliable packet: an UnreliableRemoteEvent's
-- payload limit is ~1,000 bytes (performance/audit-2026-10-21/REPORT.md §18).

-- World units per integer step. 0.05 spans +-1,638 studs, far past any arena; a bigger map needs an origin.
local SCALE = 0.05
local INV_SCALE = 1 / SCALE
local HEADER = 2
local BYTES_PER_ENEMY = 9
local YAW_OFFSET = 8

-- 256 even steps around the circle (~1.4 deg), smoothed out by the client's CFrame follow anyway. Only sin/cos
-- of the angle are used to rebuild a facing, so the wrap point does not matter.
local TAU = 2 * math.pi
local YAW_ENC = 256 / TAU
local YAW_DEC = TAU / 256

-- Reusable scratch for PackFiltered's single pass, grown to the largest batch seen.
local scratchBuf: buffer = nil :: any

local floor = math.floor

local EnemyPacker = {}

-- Single pass into the scratch buffer, then one copy into an exact-size result.
-- cam*: camera world position (cone origin). look*: unit camera forward. thresholdSq: cos^2(FOV/2), negative to
-- skip the cone. Returns nil when nothing passes, so the caller never fires an empty packet.
function EnemyPacker.PackFiltered(
	instanceIds: { number },
	positions: { vector },
	yaws: { number },
	count: number,
	camX: number,
	camY: number,
	camZ: number,
	lookX: number,
	lookY: number,
	lookZ: number,
	thresholdSq: number,
	renderDistanceSq: number
): buffer?
	local noFrustum = thresholdSq < 0

	local neededBytes = HEADER + count * BYTES_PER_ENEMY
	if not scratchBuf or buffer.len(scratchBuf) < neededBytes then scratchBuf = buffer.create(neededBytes) end

	local written = 0
	local off = HEADER

	for i = 1, count do
		local pos = positions[i]
		local vx = pos.x - camX
		local vy = pos.y - camY
		local vz = pos.z - camZ
		local distSq = vx * vx + vy * vy + vz * vz
		if distSq > renderDistanceSq then continue end
		if not noFrustum and distSq >= 1 then
			local dot = vx * lookX + vy * lookY + vz * lookZ
			if dot <= 0 then continue end
			if dot * dot <= thresholdSq * distSq then continue end
		end

		buffer.writeu16(scratchBuf, off, instanceIds[i])
		buffer.writeu16(scratchBuf, off + 2, floor(pos.x * INV_SCALE + 0.5) % 65536)
		buffer.writeu16(scratchBuf, off + 4, floor(pos.y * INV_SCALE + 0.5) % 65536)
		buffer.writeu16(scratchBuf, off + 6, floor(pos.z * INV_SCALE + 0.5) % 65536)
		buffer.writeu8(scratchBuf, off + YAW_OFFSET, floor(yaws[i] * YAW_ENC + 0.5) % 256)
		off += BYTES_PER_ENEMY
		written += 1
	end

	if written == 0 then return nil end

	buffer.writeu16(scratchBuf, 0, written)
	local used = HEADER + written * BYTES_PER_ENEMY
	local out = buffer.create(used)
	buffer.copy(out, 0, scratchBuf, 0, used)
	return out
end

-- `lastUpdate[id] = now` per accepted id, so the client can tell an enemy whose packets stopped (it left the
-- player's cone) and park it instead of letting a frozen target lerp back in.
--
-- `moving[id]`: did this enemy's position change since the previous packet? That is what switches walk and idle,
-- and this is the one place it is free: positions arrive quantised, so a body standing still reads exactly equal.
-- A first sighting has no previous value and reads as moving, which is what a body marching in is doing.
function EnemyPacker.UnpackInto(
	buf: buffer,
	positions: { [number]: Vector3 },
	yaws: { [number]: number },
	moving: { [number]: boolean },
	lastUpdate: { [number]: number },
	now: number
): ()
	local bufLen = buffer.len(buf)
	if bufLen < HEADER then return end

	local n = math.min(buffer.readu16(buf, 0), floor((bufLen - HEADER) / BYTES_PER_ENEMY))
	local off = HEADER

	for _ = 1, n do
		local id = buffer.readu16(buf, off)
		local ux = buffer.readu16(buf, off + 2)
		local uy = buffer.readu16(buf, off + 4)
		local uz = buffer.readu16(buf, off + 6)

		local sx = if ux >= 32768 then ux - 65536 else ux
		local sy = if uy >= 32768 then uy - 65536 else uy
		local sz = if uz >= 32768 then uz - 65536 else uz

		local position = Vector3.new(sx * SCALE, sy * SCALE, sz * SCALE)
		moving[id] = positions[id] ~= position
		positions[id] = position
		yaws[id] = buffer.readu8(buf, off + YAW_OFFSET) * YAW_DEC
		lastUpdate[id] = now

		off += BYTES_PER_ENEMY
	end
end

return EnemyPacker
