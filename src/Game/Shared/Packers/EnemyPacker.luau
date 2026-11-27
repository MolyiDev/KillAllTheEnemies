--!native
--!optimize 2
-- The enemy position stream: a u16 count of absolute records and one of delta records, then the records. Absolute:
-- u16 id, three u16 coordinates in fixed point and a u8 yaw = 9 bytes. Delta: u16 id, three i8 steps from the last
-- position sent for that id and a u8 yaw = 6 bytes, for a body that moved under 128 steps (6.35 studs) since. A full
-- packet at the cap is at most 2,299 bytes, so it stays one reliable packet: an UnreliableRemoteEvent's payload limit is
-- ~1,000 bytes (performance/audit-2026-10-21/REPORT.md §18).
--
-- The last position sent per id is kept on both ends (the server's per-player sentQ, the client's netBase) and
-- written only by this stream, which is reliable and in order, so both agree. A body the server has no send time for
-- (never sent, or forgotten by AOIService) goes absolute, which resets the client's baseline for its id.

-- World units per integer step. 0.05 spans +-1,638 studs, far past any arena; a bigger map needs an origin.
local SCALE = 0.05
local INV_SCALE = 1 / SCALE
local HEADER = 4
local BYTES_PER_ABSOLUTE = 9
local BYTES_PER_DELTA = 6
-- Every id fits in u16, so the baselines are flat buffers of three u16 per id.
local BYTES_PER_BASELINE = 6
local BASELINE_BYTES = 65536 * BYTES_PER_BASELINE

-- 256 even steps around the circle (~1.4 deg), smoothed out by the client's CFrame follow anyway. Only sin/cos
-- of the angle are used to rebuild a facing, so the wrap point does not matter.
local TAU = 2 * math.pi
local YAW_ENC = 256 / TAU
local YAW_DEC = TAU / 256

-- Bodies far from a player's camera are sent to them less often. Within NEAR, the farthest a client animates a body
-- (EnemiesController: 100 studs times a graphics scale of at most 1.6), every tick; past it they are held still and
-- drawn on each packet's spot, so fewer packets only means fewer jumps there. Intervals sit half a movement tick (0.05 s)
-- under 2 and 4 ticks so tick jitter cannot skip a round.
local NEAR_SEND_DISTANCE_SQ = 160 * 160
local FAR_SEND_DISTANCE_SQ = 240 * 240
local MID_SEND_INTERVAL = 0.15
local FAR_SEND_INTERVAL = 0.35

-- Reusable scratch for PackFiltered's single pass, one for each kind of record, grown to the largest batch seen.
local absoluteScratch: buffer = nil :: any
local deltaScratch: buffer = nil :: any

local floor = math.floor

local EnemyPacker = {}

-- A baseline (sentQ on the server, netBase on the client): the last quantized position sent per id.
function EnemyPacker.CreateBaseline(): buffer
	return buffer.create(BASELINE_BYTES)
end

-- Single pass into the scratch buffers, then one copy of each into an exact-size result.
-- views: each body's EnemiesCore.ViewSphere, so a body passes when any of it is in the cone, not only its feet.
-- cam*: camera world position (cone origin). look*: unit camera forward. thresholdSq: cos^2(FOV/2), negative to
-- skip the cone. apexShiftPerRadius: 1 / sin(FOV/2) (AOIService's isInView has the why). sentAt: the clock each id
-- was last sent to this player at, and sentQ their baseline (CreateBaseline), both read and written here; everyTick:
-- the bodies sent every tick whatever their distance (bosses). Returns nil when nothing passes, so the caller never
-- fires an empty packet.
function EnemyPacker.PackFiltered(
	instanceIds: { number },
	positions: { vector },
	yaws: { number },
	views: { vector },
	count: number,
	camX: number,
	camY: number,
	camZ: number,
	lookX: number,
	lookY: number,
	lookZ: number,
	thresholdSq: number,
	apexShiftPerRadius: number,
	renderDistanceSq: number,
	sentAt: { [number]: number },
	sentQ: buffer,
	everyTick: { boolean },
	now: number
): buffer?
	local noFrustum = thresholdSq < 0

	if not absoluteScratch or buffer.len(absoluteScratch) < count * BYTES_PER_ABSOLUTE then
		absoluteScratch = buffer.create(count * BYTES_PER_ABSOLUTE)
		deltaScratch = buffer.create(count * BYTES_PER_DELTA)
	end

	local absoluteCount = 0
	local deltaCount = 0
	local absoluteOff = 0
	local deltaOff = 0

	for i = 1, count do
		local pos = positions[i]
		local view = views[i]
		local radius = view.y
		local vx = pos.x - camX
		local vy = pos.y + view.x - camY
		local vz = pos.z - camZ
		local distSq = vx * vx + vy * vy + vz * vz
		if distSq > renderDistanceSq then continue end
		if not noFrustum and distSq >= radius * radius then
			local shift = radius * apexShiftPerRadius
			vx += lookX * shift
			vy += lookY * shift
			vz += lookZ * shift
			local dot = vx * lookX + vy * lookY + vz * lookZ
			if dot <= 0 then continue end
			if dot * dot <= thresholdSq * (vx * vx + vy * vy + vz * vz) then continue end
		end

		local id = instanceIds[i]
		local lastSent = sentAt[id]
		if lastSent and distSq > NEAR_SEND_DISTANCE_SQ and not everyTick[i] then
			local interval = if distSq > FAR_SEND_DISTANCE_SQ then FAR_SEND_INTERVAL else MID_SEND_INTERVAL
			if now - lastSent < interval then continue end
		end
		sentAt[id] = now

		local ux = floor(pos.x * INV_SCALE + 0.5) % 65536
		local uy = floor(pos.y * INV_SCALE + 0.5) % 65536
		local uz = floor(pos.z * INV_SCALE + 0.5) % 65536
		local yaw = floor(yaws[i] * YAW_ENC + 0.5) % 256
		local baseOff = id * BYTES_PER_BASELINE
		if lastSent then
			-- The wrapped difference, so a coordinate crossing the u16 boundary stays small.
			local dx = (ux - buffer.readu16(sentQ, baseOff) + 32768) % 65536 - 32768
			local dy = (uy - buffer.readu16(sentQ, baseOff + 2) + 32768) % 65536 - 32768
			local dz = (uz - buffer.readu16(sentQ, baseOff + 4) + 32768) % 65536 - 32768
			if dx >= -128 and dx <= 127 and dy >= -128 and dy <= 127 and dz >= -128 and dz <= 127 then
				buffer.writeu16(deltaScratch, deltaOff, id)
				buffer.writei8(deltaScratch, deltaOff + 2, dx)
				buffer.writei8(deltaScratch, deltaOff + 3, dy)
				buffer.writei8(deltaScratch, deltaOff + 4, dz)
				buffer.writeu8(deltaScratch, deltaOff + 5, yaw)
				deltaOff += BYTES_PER_DELTA
				deltaCount += 1
				buffer.writeu16(sentQ, baseOff, ux)
				buffer.writeu16(sentQ, baseOff + 2, uy)
				buffer.writeu16(sentQ, baseOff + 4, uz)
				continue
			end
		end

		buffer.writeu16(sentQ, baseOff, ux)
		buffer.writeu16(sentQ, baseOff + 2, uy)
		buffer.writeu16(sentQ, baseOff + 4, uz)
		buffer.writeu16(absoluteScratch, absoluteOff, id)
		buffer.writeu16(absoluteScratch, absoluteOff + 2, ux)
		buffer.writeu16(absoluteScratch, absoluteOff + 4, uy)
		buffer.writeu16(absoluteScratch, absoluteOff + 6, uz)
		buffer.writeu8(absoluteScratch, absoluteOff + 8, yaw)
		absoluteOff += BYTES_PER_ABSOLUTE
		absoluteCount += 1
	end

	if absoluteCount + deltaCount == 0 then return nil end

	local out = buffer.create(HEADER + absoluteOff + deltaOff)
	buffer.writeu16(out, 0, absoluteCount)
	buffer.writeu16(out, 2, deltaCount)
	buffer.copy(out, HEADER, absoluteScratch, 0, absoluteOff)
	buffer.copy(out, HEADER + absoluteOff, deltaScratch, 0, deltaOff)
	return out
end

-- `lastUpdate[id] = now` per accepted id, so the client can tell an enemy whose packets stopped (it left the
-- player's cone) and park it instead of letting a frozen target lerp back in.
--
-- `moving[id]`: did this enemy's position change since the previous packet? That is what switches walk and idle,
-- and this is the one place it is free: positions arrive quantised, so a body standing still reads exactly equal.
-- A first sighting has no previous value and reads as moving, which is what a body marching in is doing.
--
-- `netBase` is this client's baseline (CreateBaseline): every record, absolute or delta, moves it on, so the next
-- delta for that id reads from where this one left it.
function EnemyPacker.UnpackInto(
	buf: buffer,
	netBase: buffer,
	positions: { [number]: Vector3 },
	yaws: { [number]: number },
	moving: { [number]: boolean },
	lastUpdate: { [number]: number },
	now: number
): ()
	local bufLen = buffer.len(buf)
	if bufLen < HEADER then return end

	local absoluteCount = buffer.readu16(buf, 0)
	local deltaCount = buffer.readu16(buf, 2)
	if HEADER + absoluteCount * BYTES_PER_ABSOLUTE + deltaCount * BYTES_PER_DELTA > bufLen then return end
	local off = HEADER

	for record = 1, absoluteCount + deltaCount do
		local id = buffer.readu16(buf, off)
		local baseOff = id * BYTES_PER_BASELINE
		local ux, uy, uz, yaw
		if record <= absoluteCount then
			ux = buffer.readu16(buf, off + 2)
			uy = buffer.readu16(buf, off + 4)
			uz = buffer.readu16(buf, off + 6)
			yaw = buffer.readu8(buf, off + 8)
			off += BYTES_PER_ABSOLUTE
		else
			ux = (buffer.readu16(netBase, baseOff) + buffer.readi8(buf, off + 2)) % 65536
			uy = (buffer.readu16(netBase, baseOff + 2) + buffer.readi8(buf, off + 3)) % 65536
			uz = (buffer.readu16(netBase, baseOff + 4) + buffer.readi8(buf, off + 4)) % 65536
			yaw = buffer.readu8(buf, off + 5)
			off += BYTES_PER_DELTA
		end
		buffer.writeu16(netBase, baseOff, ux)
		buffer.writeu16(netBase, baseOff + 2, uy)
		buffer.writeu16(netBase, baseOff + 4, uz)

		local sx = if ux >= 32768 then ux - 65536 else ux
		local sy = if uy >= 32768 then uy - 65536 else uy
		local sz = if uz >= 32768 then uz - 65536 else uz

		local position = Vector3.new(sx * SCALE, sy * SCALE, sz * SCALE)
		moving[id] = positions[id] ~= position
		positions[id] = position
		yaws[id] = yaw * YAW_DEC
		lastUpdate[id] = now
	end
end

return EnemyPacker
