local ReplicatedStorage = game:GetService("ReplicatedStorage")
local countMap = require(ReplicatedStorage.GlobalShared.Utils.Functions.countMap)

export type TEntityServerInfo = {
	pos: vector,
	velocity: vector,
	climbGrace: number,
}
export type TEntityServerMap = { [number]: TEntityServerInfo }

export type TEntityClientInfo = { cf: CFrame }
export type TEntityClientMap = { [number]: TEntityClientInfo }

local HEADER = 2

local BYTES_PER_SERVER_TABLE = 30
local BYTES_PER_CLIENT_TABLE = 26

local EntityPacker = {}

-- SERVER ---
function EntityPacker.PackServer(entities: TEntityServerMap): buffer
	local n = countMap(entities)

	local total = HEADER + n * BYTES_PER_SERVER_TABLE
	local buf = buffer.create(total)

	buffer.writeu16(buf, 0, n)

	local off = HEADER
	for id, info in entities do
		-- id
		buffer.writeu16(buf, off, id)

		-- pos
		local p = info.pos
		buffer.writef32(buf, off + 2, p.x)
		buffer.writef32(buf, off + 6, p.y)
		buffer.writef32(buf, off + 10, p.z)

		-- velocity
		local v = info.velocity
		buffer.writef32(buf, off + 14, v.x)
		buffer.writef32(buf, off + 18, v.y)
		buffer.writef32(buf, off + 22, v.z)

		-- climbGrace
		buffer.writef32(buf, off + 26, info.climbGrace)

		off += BYTES_PER_SERVER_TABLE
	end

	return buf
end

function EntityPacker.UnpackServerInto(buf: buffer, reuse: TEntityServerMap): ()
	local lenBuf = buffer.len(buf)
	if lenBuf < HEADER then return end
	local n = buffer.readu16(buf, 0)

	local expected = HEADER + n * BYTES_PER_SERVER_TABLE
	if lenBuf < expected then n = math.max(0, math.floor((buffer.len(buf) - HEADER) / BYTES_PER_SERVER_TABLE)) end

	local off = HEADER
	for _ = 1, n do
		local id = buffer.readu16(buf, off)

		local px = buffer.readf32(buf, off + 2)
		local py = buffer.readf32(buf, off + 6)
		local pz = buffer.readf32(buf, off + 10)

		local vx = buffer.readf32(buf, off + 14)
		local vy = buffer.readf32(buf, off + 18)
		local vz = buffer.readf32(buf, off + 22)

		local grace = buffer.readf32(buf, off + 26)

		local existant = reuse[id]
		if existant then
			existant.pos = vector.create(px, py, pz)
			existant.velocity = vector.create(vx, vy, vz)
			existant.climbGrace = grace
		else
			reuse[id] = {
				pos = vector.create(px, py, pz),
				velocity = vector.create(vx, vy, vz),
				climbGrace = grace,
			}
		end

		off += BYTES_PER_SERVER_TABLE
	end
end

-- CLIENT --
function EntityPacker.PackClient(entities: TEntityClientMap): buffer
	local n = countMap(entities)

	local total = HEADER + n * BYTES_PER_CLIENT_TABLE
	local buf = buffer.create(total)

	buffer.writeu16(buf, 0, n)

	local off = HEADER
	for id, info in entities do
		-- id
		buffer.writeu16(buf, off, id)

		-- cf
		local axis_1, angle_1 = info.cf:ToAxisAngle()
		axis_1 = axis_1 * angle_1

		buffer.writef32(buf, off + 2, info.cf.Position.X)
		buffer.writef32(buf, off + 6, info.cf.Position.Y)
		buffer.writef32(buf, off + 10, info.cf.Position.Z)

		buffer.writef32(buf, off + 14, axis_1.X)
		buffer.writef32(buf, off + 18, axis_1.Y)
		buffer.writef32(buf, off + 22, axis_1.Z)

		off += BYTES_PER_CLIENT_TABLE
	end

	return buf
end

function EntityPacker.UnpackClientInto(buf: buffer, reuse: TEntityClientMap)
	local lenBuf = buffer.len(buf)
	if lenBuf < HEADER then return end
	local n = buffer.readu16(buf, 0)

	local expected = HEADER + n * BYTES_PER_CLIENT_TABLE
	if lenBuf < expected then n = math.max(0, math.floor((buffer.len(buf) - HEADER) / BYTES_PER_CLIENT_TABLE)) end

	local off = HEADER
	for _ = 1, n do
		local id = buffer.readu16(buf, off)

		local px = buffer.readf32(buf, off + 2)
		local py = buffer.readf32(buf, off + 6)
		local pz = buffer.readf32(buf, off + 10)

		local ax = buffer.readf32(buf, off + 14)
		local ay = buffer.readf32(buf, off + 18)
		local az = buffer.readf32(buf, off + 22)

		local existant = reuse[id]
		if existant then
			existant.cf = CFrame.new(px, py, pz) * CFrame.Angles(ax, ay, az)
		else
			reuse[id] = {
				cf = CFrame.new(px, py, pz) * CFrame.Angles(ax, ay, az),
			}
		end

		off += BYTES_PER_CLIENT_TABLE
	end
end

return EntityPacker
