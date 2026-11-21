--!native
--!optimize 2
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local jecs = require(ReplicatedStorage.Packages.jecs)

--==[ Types ]==--
export type EntityId = jecs.Entity<any>
export type Bucket = { EntityId }
export type Buckets = { [number]: Bucket }

export type RecordPoint = { x: number, y: number, z: number, shape: number }
export type RecordCircle = { x: number, y: number, z: number, radius: number, shape: number }
export type RecordAABB = { x: number, y: number, z: number, halfx: number, halfy: number, halfz: number, shape: number }

export type Records = { [EntityId]: RecordPoint | RecordCircle | RecordAABB }
export type RecordInfo = { hash: number, index: number, coarseHash: number, coarseIndex: number }
export type RecordsInfo = { [EntityId]: RecordInfo }

export type SpatialHashStatic = {
	new: (cellSize: number?, coarseFactor: number?) -> SpatialHash,
	QueryAABBAsPoints: (
		minX: number,
		minZ: number,
		maxX: number,
		maxZ: number,
		size: number,
		func: (EntityId) -> (),
		buckets: Buckets,
		records: Records
	) -> (),
	QueryRadiusAsPoints: (
		cx: number,
		cz: number,
		radius: number,
		size: number,
		func: (EntityId) -> (),
		buckets: Buckets,
		records: Records
	) -> (),
	QueryAABB: (
		minX: number,
		minZ: number,
		maxX: number,
		maxZ: number,
		size: number,
		func: (EntityId) -> (),
		buckets: Buckets,
		records: Records
	) -> (),
	QueryRadius: (
		cx: number,
		cz: number,
		radius: number,
		size: number,
		func: (EntityId) -> (),
		buckets: Buckets,
		records: Records
	) -> (),

	PackBuckets: (buckets: Buckets) -> buffer,
	UnpackBuckets: (buf: buffer) -> Buckets,
	UnpackBucketsInto: (buf: buffer, reuse: Buckets, epochs: { [number]: number }?, epoch: number?) -> (),
	PackRecords: (records: Records) -> buffer,
	UnpackRecords: (buf: buffer) -> Records,
	UnpackRecordsInto: (buf: buffer, reuse: Records, epochs: { [number]: number }?, epoch: number?) -> (),
}

export type SpatialHash = {
	CELL_SIZE: number,
	COARSE_FACTOR: number,
	COARSE_SIZE: number,

	Records: Records,
	RecordsInfo: RecordsInfo,
	FineBuckets: Buckets,
	CoarseBuckets: Buckets,

	Reset: (self: SpatialHash, cellSize: number?, coarseFactor: number?) -> (),

	AddPoint: (self: SpatialHash, entity: EntityId, position: vector) -> (),
	AddAABB: (self: SpatialHash, entity: EntityId, position: vector, halfSize: vector) -> (),
	AddCircle: (self: SpatialHash, entity: EntityId, position: vector, radius: number) -> (),
	AddAABBRecursively: (self: SpatialHash, entity: EntityId, position: vector, halfSize: vector) -> (),
	AddCircleRecursively: (self: SpatialHash, entity: EntityId, position: vector, radius: number) -> (),

	Update: (self: SpatialHash, entity: EntityId, position: vector) -> (),
	Update3: (self: SpatialHash, entity: EntityId, position: Vector3) -> (),

	Remove: (self: SpatialHash, entity: EntityId) -> (),
	RemoveRecursively: (self: SpatialHash, entity: EntityId) -> (),

	QueryAABBAsPoints: (
		self: SpatialHash,
		minX: number,
		minZ: number,
		maxX: number,
		maxZ: number,
		func: (EntityId) -> ()
	) -> (),
	QueryRadiusAsPoints: (self: SpatialHash, cx: number, cz: number, radius: number, func: (EntityId) -> ()) -> (),
	QueryAABB: (
		self: SpatialHash,
		minX: number,
		minZ: number,
		maxX: number,
		maxZ: number,
		func: (EntityId) -> ()
	) -> (),
	QueryRadius: (self: SpatialHash, cx: number, cz: number, radius: number, func: (EntityId) -> ()) -> (),
}

--==[ Defaults ]==--
local CELL_SIZE_DEFAULT: number = 5
local COARSE_FACTOR_DEFAULT: number = 32
-- Cap on how many grid cells one query may walk. A query box built from a
-- runaway position (flung character, oversized stat scale) can span millions
-- of cells and spin the cell loop past the script watchdog. Past the cap the
-- queries scan the records map directly instead, which is O(entities) no
-- matter how big the box is. The comparisons are written as
-- `not (cellCount <= MAX_QUERY_CELLS)` so NaN and inf inputs also take the
-- bounded path.
local MAX_QUERY_CELLS = 4096
local ERelation = table.freeze({
	Outside = 0,
	Inside = 1,
	Intersect = 2,
})
local EShape = table.freeze({
	Point = 0,
	Circle = 1,
	AABB = 2,
})

--==[ Helpers ]==--
local bor = bit32.bor
local band = bit32.band
local lshift = bit32.lshift
local floor = math.floor
local max = math.max
local table_create = table.create
local table_clear = table.clear

-- Center-bucket shapes need an extent-expanded broad phase. Keep metadata out of
-- Records so packing/iteration still sees only entity IDs. Removed large shapes
-- may leave a conservative upper bound until Reset or the next full decode.
type QueryBounds = { x: number, z: number, recursive: boolean }
local queryExtents: { [Records]: QueryBounds } = setmetatable({}, { __mode = "k" }) :: any
local function trackExtents(records: Records, hx: number, hz: number, recursive: boolean?)
	local bounds = queryExtents[records]
	if not bounds then
		bounds = { x = 0, z = 0, recursive = false }
		queryExtents[records] = bounds
	end

	if recursive then
		bounds.recursive = true
	else
		bounds.x = max(bounds.x, hx)
		bounds.z = max(bounds.z, hz)
	end
end
local function getExtents(records: Records)
	local bounds = queryExtents[records]
	if bounds then return bounds.x, bounds.z, bounds.recursive end

	-- Public static queries may receive an independently constructed Records map.
	local hx, hz = 0, 0
	for _, rec in records do
		if rec.shape == EShape.AABB then
			hx = max(hx, (rec :: RecordAABB).halfx)
			hz = max(hz, (rec :: RecordAABB).halfz)
		elseif rec.shape == EShape.Circle then
			hx = max(hx, (rec :: RecordCircle).radius)
			hz = max(hz, (rec :: RecordCircle).radius)
		end
	end

	return hx, hz, true
end

local function ihash(ix: number, iz: number): number
	-- Pack signed grid indices into 32 bits. Works for |ix|,|iz| < 32768.
	return bor(lshift(band(ix, 0xFFFF), 16), band(iz, 0xFFFF))
end

local function cellIndexSize(x: number, z: number, size: number): (number, number)
	return floor(x / size), floor(z / size)
end

local function ensure(bags: { [number]: Bucket }, h: number): Bucket
	local b = bags[h]
	if b ~= nil then return b end

	local n = table_create(8) :: Bucket
	bags[h] = n

	return n
end

local function insertInfo(self: SpatialHash, entity: EntityId, x: number, z: number)
	local fix, fiz = cellIndexSize(x, z, self.CELL_SIZE)
	local cix, ciz = cellIndexSize(x, z, self.COARSE_SIZE)
	local fh, ch = ihash(fix, fiz), ihash(cix, ciz)

	local fb = ensure(self.FineBuckets, fh)
	fb[#fb + 1] = entity

	local cb = ensure(self.CoarseBuckets, ch)
	cb[#cb + 1] = entity

	local existing = self.RecordsInfo[entity]
	if existing then
		existing.hash = fh
		existing.index = #fb
		existing.coarseHash = ch
		existing.coarseIndex = #cb
	else
		self.RecordsInfo[entity] = { hash = fh, index = #fb, coarseHash = ch, coarseIndex = #cb }
	end
end

local function swapRemoveFine(self: SpatialHash, bags: { [number]: Bucket }, hash: number, idx: number)
	local b = bags[hash]
	if b == nil then return end

	local n = #b
	local last = b[n]

	if idx ~= n then
		b[idx] = last
		local li = self.RecordsInfo[last]
		if li then li.index = idx end
	end

	b[n] = nil
	if n - 1 == 0 then bags[hash] = nil end
end

local function swapRemoveCoarse(self: SpatialHash, bags: { [number]: Bucket }, h: number, idx: number)
	local b = bags[h]
	if b == nil then return end

	local n = #b
	local last = b[n]

	if idx ~= n then
		b[idx] = last
		local li = self.RecordsInfo[last]
		if li then li.coarseIndex = idx end
	end

	b[n] = nil
	if n - 1 == 0 then bags[h] = nil end
end

local function removeDual(self: SpatialHash, info: RecordInfo)
	swapRemoveFine(self, self.FineBuckets, info.hash, info.index)
	swapRemoveCoarse(self, self.CoarseBuckets, info.coarseHash, info.coarseIndex)
end

local function cellAABB(ix: number, iz: number, size: number): (number, number, number, number)
	local minx = ix * size
	local minz = iz * size
	return minx, minx + size, minz, minz + size
end

local function circleAABBRelation(
	minx: number,
	maxx: number,
	minz: number,
	maxz: number,
	cx: number,
	cz: number,
	r2: number
): number
	-- outside if AABB is farther than r from circle center
	local dx = 0
	if cx < minx then
		dx = minx - cx
	elseif cx > maxx then
		dx = cx - maxx
	end

	local dz = 0
	if cz < minz then
		dz = minz - cz
	elseif cz > maxz then
		dz = cz - maxz
	end

	if dx * dx + dz * dz > r2 then return ERelation.Outside end

	-- inside if all four corners inside the circle
	local rminx = minx - cx
	local rmaxx = maxx - cx
	local rminz = minz - cz
	local rmaxz = maxz - cz
	if
		rminx * rminx + rminz * rminz <= r2
		and rminx * rminx + rmaxz * rmaxz <= r2
		and rmaxx * rmaxx + rminz * rminz <= r2
		and rmaxx * rmaxx + rmaxz * rmaxz <= r2
	then
		return ERelation.Inside
	end

	return ERelation.Intersect
end

local function aabbRelation(
	minx: number,
	maxx: number,
	minz: number,
	maxz: number,
	qminx: number,
	qmaxx: number,
	qminz: number,
	qmaxz: number
): number
	if maxx < qminx or minx > qmaxx or maxz < qminz or minz > qmaxz then return ERelation.Outside end
	if minx >= qminx and maxx <= qmaxx and minz >= qminz and maxz <= qmaxz then return ERelation.Inside end

	return ERelation.Intersect
end

local function pointInAABB(x: number, z: number, qminx: number, qmaxx: number, qminz: number, qmaxz: number): boolean
	return x >= qminx and x <= qmaxx and z >= qminz and z <= qmaxz
end

local function pointInRadius(dx: number, dz: number, r2: number): boolean
	return dx * dx + dz * dz <= r2
end

local function circleVsAABB(
	cx: number,
	cz: number,
	r2: number,
	qminx: number,
	qmaxx: number,
	qminz: number,
	qmaxz: number
): boolean
	local dx = 0

	if cx < qminx then
		dx = qminx - cx
	elseif cx > qmaxx then
		dx = cx - qmaxx
	end

	local dz = 0
	if cz < qminz then
		dz = qminz - cz
	elseif cz > qmaxz then
		dz = cz - qmaxz
	end

	return dx * dx + dz * dz <= r2
end

local function aabbVsAABB(
	minx: number,
	maxx: number,
	minz: number,
	maxz: number,
	qminx: number,
	qmaxx: number,
	qminz: number,
	qmaxz: number
): boolean
	return not (maxx < qminx or minx > qmaxx or maxz < qminz or minz > qmaxz)
end

local function circleVsCircle(ax: number, az: number, ar: number, bx: number, bz: number, br: number): boolean
	local dx = ax - bx
	local dz = az - bz
	return dx * dx + dz * dz <= (ar + br) * (ar + br)
end

local function pushUnique(bags: Buckets, h: number, e: EntityId)
	local b = ensure(bags, h)
	for i = 1, #b do
		if b[i] == e then return end
	end

	b[#b + 1] = e
end

local function removeAllLinear(self: SpatialHash, bags: Buckets, h: number, e: EntityId, isFine: boolean)
	local b = bags[h]
	if b == nil then return end

	local i = 1
	while i <= #b do
		if b[i] ~= e then
			i += 1
			continue
		end

		local n = #b
		local last = b[n]
		if i ~= n then
			b[i] = last
			-- keep single-cell bookkeeping consistent for the swapped entity
			local li = self.RecordsInfo[last]
			if li then
				if isFine and li.hash == h then li.index = i end
				if (not isFine) and li.coarseHash == h then li.coarseIndex = i end
			end
		end
		b[n] = nil
		-- do not i=i+1 here; we must check the new element at i
	end

	if #b == 0 then bags[h] = nil end
end

local function rangeCircle(cx: number, cz: number, r: number, size: number)
	local minIx, minIz = cellIndexSize(cx - r, cz - r, size)
	local maxIx, maxIz = cellIndexSize(cx + r, cz + r, size)
	return minIx, minIz, maxIx, maxIz
end

local function rangeAABB(cx: number, cz: number, hx: number, hz: number, size: number)
	local minIx, minIz = cellIndexSize(cx - hx, cz - hz, size)
	local maxIx, maxIz = cellIndexSize(cx + hx, cz + hz, size)
	return minIx, minIz, maxIx, maxIz
end

--==[ SpatialHash ]==--
local SpatialHashStatic = {}
local SpatialHash = {}
SpatialHash.__index = SpatialHash

function SpatialHashStatic.new(cellSize: number?, coarseFactor: number?): SpatialHash
	local self = (setmetatable({}, SpatialHash) :: any) :: SpatialHash
	self.FineBuckets = {}
	self.CoarseBuckets = {}
	self.Records = {}
	self.RecordsInfo = {}

	if cellSize and cellSize > 0 then
		self.CELL_SIZE = cellSize
	else
		self.CELL_SIZE = CELL_SIZE_DEFAULT
	end

	if coarseFactor and coarseFactor >= 2 then
		self.COARSE_FACTOR = coarseFactor
	else
		self.COARSE_FACTOR = COARSE_FACTOR_DEFAULT
	end

	self.COARSE_SIZE = self.CELL_SIZE * self.COARSE_FACTOR

	return self
end

function SpatialHash.Reset(self: SpatialHash, cellSize: number?, coarseFactor: number?)
	if cellSize and cellSize > 0 then self.CELL_SIZE = cellSize end
	if coarseFactor and coarseFactor >= 2 then self.COARSE_FACTOR = coarseFactor end

	self.COARSE_SIZE = self.CELL_SIZE * self.COARSE_FACTOR

	table_clear(self.FineBuckets)
	table_clear(self.CoarseBuckets)
	table_clear(self.Records)
	table_clear(self.RecordsInfo)
	queryExtents[self.Records] = { x = 0, z = 0, recursive = false }
end

function SpatialHash.AddPoint(self: SpatialHash, entity: EntityId, position: vector)
	if self.Records[entity] then return end
	self.Records[entity] = { x = position.x, y = position.y, z = position.z, shape = EShape.Point } :: RecordPoint
	trackExtents(self.Records, 0, 0)
	insertInfo(self, entity, position.x, position.z)
end

function SpatialHash.AddAABB(self: SpatialHash, entity: EntityId, position: vector, halfSize: vector)
	if self.Records[entity] then return end
	trackExtents(self.Records, halfSize.x, halfSize.z)
	self.Records[entity] = {
		x = position.x,
		y = position.y,
		z = position.z,
		halfx = halfSize.x,
		halfy = halfSize.y,
		halfz = halfSize.z,
		shape = EShape.AABB,
	} :: RecordAABB
	insertInfo(self, entity, position.x, position.z)
end

function SpatialHash.AddCircle(self: SpatialHash, entity: EntityId, position: vector, radius: number)
	if self.Records[entity] then return end
	trackExtents(self.Records, radius, radius)
	self.Records[entity] = {
		x = position.x,
		y = position.y,
		z = position.z,
		radius = radius,
		shape = EShape.Circle,
	} :: RecordCircle
	insertInfo(self, entity, position.x, position.z)
end

function SpatialHash.AddAABBRecursively(self: SpatialHash, e: EntityId, pos: vector, halfSize: vector)
	if self.Records[e] then return end
	local hx = max(0, halfSize.x)
	local hy = max(0, halfSize.y)
	local hz = max(0, halfSize.z)
	trackExtents(self.Records, hx, hz, true)
	self.Records[e] =
		{ x = pos.x, y = pos.y, z = pos.z, halfx = hx, halfy = hy, halfz = hz, shape = EShape.AABB } :: RecordAABB

	-- fine
	do
		local minIx, minIz, maxIx, maxIz = rangeAABB(pos.x, pos.z, hx, hz, self.CELL_SIZE)
		for ix = minIx, maxIx do
			local base = lshift(band(ix, 0xFFFF), 16)
			for iz = minIz, maxIz do
				local h = bor(base, band(iz, 0xFFFF))
				pushUnique(self.FineBuckets, h, e)
			end
		end
	end

	-- coarse
	do
		local minIx, minIz, maxIx, maxIz = rangeAABB(pos.x, pos.z, hx, hz, self.COARSE_SIZE)
		for ix = minIx, maxIx do
			local base = lshift(band(ix, 0xFFFF), 16)
			for iz = minIz, maxIz do
				local h = bor(base, band(iz, 0xFFFF))
				pushUnique(self.CoarseBuckets, h, e)
			end
		end
	end
end

function SpatialHash.AddCircleRecursively(self: SpatialHash, e: EntityId, pos: vector, radius: number)
	if self.Records[e] then return end
	if radius < 0 then radius = 0 end
	trackExtents(self.Records, radius, radius, true)
	self.Records[e] = {
		x = pos.x,
		y = pos.y,
		z = pos.z,
		radius = radius,
		shape = EShape.Circle,
	} :: RecordCircle

	-- fine
	do
		local minIx, minIz, maxIx, maxIz = rangeCircle(pos.x, pos.z, radius, self.CELL_SIZE)
		for ix = minIx, maxIx do
			local base = lshift(band(ix, 0xFFFF), 16)
			for iz = minIz, maxIz do
				local h = bor(base, band(iz, 0xFFFF))
				pushUnique(self.FineBuckets, h, e)
			end
		end
	end

	-- coarse
	do
		local minIx, minIz, maxIx, maxIz = rangeCircle(pos.x, pos.z, radius, self.COARSE_SIZE)
		for ix = minIx, maxIx do
			local base = lshift(band(ix, 0xFFFF), 16)
			for iz = minIz, maxIz do
				local h = bor(base, band(iz, 0xFFFF))
				pushUnique(self.CoarseBuckets, h, e)
			end
		end
	end
end

function SpatialHash.Update(self: SpatialHash, entity: EntityId, position: vector)
	local record = self.Records[entity]
	if record == nil then return end

	local info = self.RecordsInfo[entity]
	if info == nil then
		local pos = vector.create(position.x, position.y, position.z)
		if record.shape == EShape.AABB then
			local half =
				vector.create((record :: RecordAABB).halfx, (record :: RecordAABB).halfy, (record :: RecordAABB).halfz)
			SpatialHash.RemoveRecursively(self, entity)
			SpatialHash.AddAABBRecursively(self, entity, pos, half)
		elseif record.shape == EShape.Circle then
			local radius = (record :: RecordCircle).radius
			SpatialHash.RemoveRecursively(self, entity)
			SpatialHash.AddCircleRecursively(self, entity, pos, radius)
		end
		return
	end

	local fix, fiz = cellIndexSize(position.x, position.z, self.CELL_SIZE)
	local cix, ciz = cellIndexSize(position.x, position.z, self.COARSE_SIZE)
	local fh, ch = ihash(fix, fiz), ihash(cix, ciz)

	if fh ~= info.hash or ch ~= info.coarseHash then
		removeDual(self, info)
		insertInfo(self, entity, position.x, position.z)
	end

	record.x = position.x
	record.z = position.z
	record.y = position.y
end

function SpatialHash.Update3(self: SpatialHash, entity: EntityId, position: Vector3)
	local record = self.Records[entity]
	if record == nil then return end

	local info = self.RecordsInfo[entity]
	if info == nil then
		local pos = vector.create(position.X, position.Y, position.Z)
		if record.shape == EShape.AABB then
			local half =
				vector.create((record :: RecordAABB).halfx, (record :: RecordAABB).halfy, (record :: RecordAABB).halfz)
			SpatialHash.RemoveRecursively(self, entity)
			SpatialHash.AddAABBRecursively(self, entity, pos, half)
		elseif record.shape == EShape.Circle then
			local radius = (record :: RecordCircle).radius
			SpatialHash.RemoveRecursively(self, entity)
			SpatialHash.AddCircleRecursively(self, entity, pos, radius)
		end
		return
	end

	local fix, fiz = cellIndexSize(position.X, position.Z, self.CELL_SIZE)
	local cix, ciz = cellIndexSize(position.X, position.Z, self.COARSE_SIZE)
	local fh, ch = ihash(fix, fiz), ihash(cix, ciz)

	if fh ~= info.hash or ch ~= info.coarseHash then
		removeDual(self, info)
		insertInfo(self, entity, position.X, position.Z)
	end

	record.x = position.X
	record.z = position.Z
	record.y = position.Y
end

function SpatialHash.Remove(self: SpatialHash, entity: EntityId)
	local record = self.Records[entity]
	if record == nil then return end
	local info = self.RecordsInfo[entity]
	if info == nil then
		if record.shape ~= EShape.Point then
			SpatialHash.RemoveRecursively(self, entity)
		else
			self.Records[entity] = nil
		end
		return
	end

	removeDual(self, info)

	self.Records[entity] = nil
	self.RecordsInfo[entity] = nil
end

function SpatialHash.RemoveRecursively(self: SpatialHash, entity: EntityId)
	local record = self.Records[entity]
	if record == nil then return end

	-- compute ranges from the stored shape
	if record.shape == EShape.Circle then
		local r = (record :: RecordCircle).radius
		-- fine
		do
			local minIx, minIz, maxIx, maxIz = rangeCircle(record.x, record.z, r, self.CELL_SIZE)
			for ix = minIx, maxIx do
				local base = lshift(band(ix, 0xFFFF), 16)
				for iz = minIz, maxIz do
					local h = bor(base, band(iz, 0xFFFF))
					removeAllLinear(self, self.FineBuckets, h, entity, true)
				end
			end
		end

		-- coarse
		do
			local minIx, minIz, maxIx, maxIz = rangeCircle(record.x, record.z, r, self.COARSE_SIZE)
			for ix = minIx, maxIx do
				local base = lshift(band(ix, 0xFFFF), 16)
				for iz = minIz, maxIz do
					local h = bor(base, band(iz, 0xFFFF))
					removeAllLinear(self, self.CoarseBuckets, h, entity, false)
				end
			end
		end
	elseif record.shape == EShape.AABB then
		local a = record :: RecordAABB
		-- fine
		do
			local minIx, minIz, maxIx, maxIz = rangeAABB(record.x, record.z, a.halfx, a.halfz, self.CELL_SIZE)
			for ix = minIx, maxIx do
				local base = lshift(band(ix, 0xFFFF), 16)
				for iz = minIz, maxIz do
					local h = bor(base, band(iz, 0xFFFF))
					removeAllLinear(self, self.FineBuckets, h, entity, true)
				end
			end
		end

		-- coarse
		do
			local minIx, minIz, maxIx, maxIz = rangeAABB(record.x, record.z, a.halfx, a.halfz, self.COARSE_SIZE)
			for ix = minIx, maxIx do
				local base = lshift(band(ix, 0xFFFF), 16)
				for iz = minIz, maxIz do
					local h = bor(base, band(iz, 0xFFFF))
					removeAllLinear(self, self.CoarseBuckets, h, entity, false)
				end
			end
		end
	else
		return SpatialHash.Remove(self, entity)
	end

	-- clear record; ignore RecordsInfo (single-cell) because we did linear removes
	self.Records[entity] = nil
	self.RecordsInfo[entity] = nil
end

--==[ Queries ]==--
function SpatialHashStatic.QueryAABB(
	minX: number,
	minZ: number,
	maxX: number,
	maxZ: number,
	size: number,
	func: (EntityId) -> (),
	buckets: Buckets,
	records: Records
): ()
	if minX > maxX then
		minX, maxX = maxX, minX
	end

	if minZ > maxZ then
		minZ, maxZ = maxZ, minZ
	end

	local hx, hz, recursive = getExtents(records)
	local seen = if recursive then {} else nil
	local minIx, minIz = cellIndexSize(minX - hx, minZ - hz, size)
	local maxIx, maxIz = cellIndexSize(maxX + hx, maxZ + hz, size)

	local cellCount = (maxIx - minIx + 1) * (maxIz - minIz + 1)
	if not (cellCount <= MAX_QUERY_CELLS) then
		for entity, rec in records do
			if rec.shape == EShape.Point then
				if pointInAABB(rec.x, rec.z, minX, maxX, minZ, maxZ) then func(entity) end
			elseif rec.shape == EShape.Circle then
				local r = (rec :: RecordCircle).radius
				if circleVsAABB(rec.x, rec.z, r * r, minX, maxX, minZ, maxZ) then func(entity) end
			else
				if
					aabbVsAABB(
						rec.x - (rec :: RecordAABB).halfx,
						rec.x + (rec :: RecordAABB).halfx,
						rec.z - (rec :: RecordAABB).halfz,
						rec.z + (rec :: RecordAABB).halfz,
						minX,
						maxX,
						minZ,
						maxZ
					)
				then
					func(entity)
				end
			end
		end
		return
	end

	for ix = minIx, maxIx do
		local base = lshift(band(ix, 0xFFFF), 16)
		for iz = minIz, maxIz do
			local hash = bor(base, band(iz, 0xFFFF))
			local bucket = buckets[hash]
			if bucket == nil then continue end

			local cminx, cmaxx, cminz, cmaxz = ix * size, ix * size + size, iz * size, iz * size + size
			local rel = aabbRelation(cminx, cmaxx, cminz, cmaxz, minX, maxX, minZ, maxZ)

			if rel == ERelation.Inside and not recursive then
				for i = #bucket, 1, -1 do
					local entity = bucket[i]
					if not seen or not seen[entity] then
						if seen then seen[entity] = true end
						func(entity)
					end
				end
			else
				for i = #bucket, 1, -1 do
					local entity = bucket[i]
					if seen then
						if seen[entity] then continue end
						seen[entity] = true
					end

					local rec = records[entity]
					if rec.shape == EShape.Point then
						if pointInAABB(rec.x, rec.z, minX, maxX, minZ, maxZ) then func(entity) end
					elseif rec.shape == EShape.Circle then
						if
							circleVsAABB(
								rec.x,
								rec.z,
								(rec :: RecordCircle).radius * (rec :: RecordCircle).radius,
								minX,
								maxX,
								minZ,
								maxZ
							)
						then
							func(entity)
						end
					else
						if
							aabbVsAABB(
								rec.x - (rec :: RecordAABB).halfx,
								rec.x + (rec :: RecordAABB).halfx,
								rec.z - (rec :: RecordAABB).halfz,
								rec.z + (rec :: RecordAABB).halfz,
								minX,
								maxX,
								minZ,
								maxZ
							)
						then
							func(entity)
						end
					end
				end
			end
		end
	end
end

function SpatialHashStatic.QueryRadius(
	cx: number,
	cz: number,
	radius: number,
	size: number,
	func: (EntityId) -> (),
	buckets: Buckets,
	records: Records
): ()
	local r2 = radius * radius
	local minx, maxx, minz, maxz = cx - radius, cx + radius, cz - radius, cz + radius
	local hx, hz, recursive = getExtents(records)
	local seen = if recursive then {} else nil
	local minIx, minIz = cellIndexSize(minx - hx, minz - hz, size)
	local maxIx, maxIz = cellIndexSize(maxx + hx, maxz + hz, size)

	local cellCount = (maxIx - minIx + 1) * (maxIz - minIz + 1)
	if not (cellCount <= MAX_QUERY_CELLS) then
		for entity, record in records do
			if record.shape == EShape.Point then
				if pointInRadius(record.x - cx, record.z - cz, r2) then func(entity) end
			elseif record.shape == EShape.Circle then
				if circleVsCircle(record.x, record.z, (record :: RecordCircle).radius, cx, cz, radius) then
					func(entity)
				end
			else
				if
					circleVsAABB(
						cx,
						cz,
						r2,
						record.x - (record :: RecordAABB).halfx,
						record.x + (record :: RecordAABB).halfx,
						record.z - (record :: RecordAABB).halfz,
						record.z + (record :: RecordAABB).halfz
					)
				then
					func(entity)
				end
			end
		end
		return
	end

	for ix = minIx, maxIx do
		local base = lshift(band(ix, 0xFFFF), 16)
		for iz = minIz, maxIz do
			local hash = bor(base, band(iz, 0xFFFF))
			local bucket = buckets[hash]
			if bucket == nil then continue end

			local cminx, cmaxx, cminz, cmaxz = cellAABB(ix, iz, size)
			local rel = circleAABBRelation(cminx, cmaxx, cminz, cmaxz, cx, cz, r2)

			if rel == ERelation.Inside and not recursive then
				for i = #bucket, 1, -1 do
					local entity = bucket[i]
					if not seen or not seen[entity] then
						if seen then seen[entity] = true end
						func(entity)
					end
				end
			else
				for i = #bucket, 1, -1 do
					local entity = bucket[i]
					if seen then
						if seen[entity] then continue end
						seen[entity] = true
					end

					local record = records[entity]

					if record.shape == EShape.Point then
						local dx, dz = record.x - cx, record.z - cz
						if pointInRadius(dx, dz, r2) then func(entity) end
					elseif record.shape == EShape.Circle then
						if circleVsCircle(record.x, record.z, (record :: RecordCircle).radius, cx, cz, radius) then
							func(entity)
						end
					else
						if
							circleVsAABB(
								cx,
								cz,
								r2,
								record.x - (record :: RecordAABB).halfx,
								record.x + (record :: RecordAABB).halfx,
								record.z - (record :: RecordAABB).halfz,
								record.z + (record :: RecordAABB).halfz
							)
						then
							func(entity)
						end
					end
				end
			end
		end
	end
end

function SpatialHashStatic.QueryAABBAsPoints(
	minX: number,
	minZ: number,
	maxX: number,
	maxZ: number,
	size: number,
	func: (EntityId) -> (),
	buckets: Buckets,
	records: Records
): ()
	if minX > maxX then
		minX, maxX = maxX, minX
	end

	if minZ > maxZ then
		minZ, maxZ = maxZ, minZ
	end

	local minIx, minIz = cellIndexSize(minX, minZ, size)
	local maxIx, maxIz = cellIndexSize(maxX, maxZ, size)

	local meta = queryExtents[records]
	local recursive = not meta or meta.recursive
	local seen = if recursive then {} else nil
	local cellCount = (maxIx - minIx + 1) * (maxIz - minIz + 1)
	if not (cellCount <= MAX_QUERY_CELLS) then
		for entity, record in records do
			if pointInAABB(record.x, record.z, minX, maxX, minZ, maxZ) then func(entity) end
		end
		return
	end

	for ix = minIx, maxIx do
		local base = lshift(band(ix, 0xFFFF), 16)
		for iz = minIz, maxIz do
			local hash = bor(base, band(iz, 0xFFFF))
			local bucket = buckets[hash]
			if bucket == nil then continue end

			local minx, maxx, minz, maxz = cellAABB(ix, iz, size)
			local rel = aabbRelation(minx, maxx, minz, maxz, minX, maxX, minZ, maxZ)

			if rel == ERelation.Inside and not recursive then
				for i = #bucket, 1, -1 do
					func(bucket[i])
				end
			elseif rel == ERelation.Intersect or (recursive and rel == ERelation.Inside) then
				-- border cells: test each point against query box
				for i = #bucket, 1, -1 do
					local entity = bucket[i]
					if seen then
						if seen[entity] then continue end
						seen[entity] = true
					end

					local record = records[entity] :: { x: number, z: number }

					if pointInAABB(record.x, record.z, minX, maxX, minZ, maxZ) then func(entity) end
				end
			end
		end
	end
end

function SpatialHashStatic.QueryRadiusAsPoints(
	cx: number,
	cz: number,
	radius: number,
	size: number,
	func: (EntityId) -> (),
	buckets: Buckets,
	records: Records
): ()
	local r2 = radius * radius
	local minx, maxx, minz, maxz = cx - radius, cx + radius, cz - radius, cz + radius

	local minIx, minIz = cellIndexSize(minx, minz, size)
	local maxIx, maxIz = cellIndexSize(maxx, maxz, size)

	local meta = queryExtents[records]
	local recursive = not meta or meta.recursive
	local seen = if recursive then {} else nil
	local cellCount = (maxIx - minIx + 1) * (maxIz - minIz + 1)
	if not (cellCount <= MAX_QUERY_CELLS) then
		for entity, record in records do
			if pointInRadius(record.x - cx, record.z - cz, r2) then func(entity) end
		end
		return
	end

	for ix = minIx, maxIx do
		local base = lshift(band(ix, 0xFFFF), 16)
		for iz = minIz, maxIz do
			local hash = bor(base, band(iz, 0xFFFF))
			local bucket = buckets[hash]
			if bucket == nil then continue end

			local cminx, cmaxx, cminz, cmaxz = cellAABB(ix, iz, size)
			local rel = circleAABBRelation(cminx, cmaxx, cminz, cmaxz, cx, cz, r2)

			if rel == ERelation.Inside and not recursive then
				for i = #bucket, 1, -1 do
					func(bucket[i])
				end
			elseif rel == ERelation.Intersect or (recursive and rel == ERelation.Inside) then
				-- border: point-in-circle
				for i = #bucket, 1, -1 do
					local entity = bucket[i]
					if seen then
						if seen[entity] then continue end
						seen[entity] = true
					end

					local record = records[entity]
					local dx = record.x - cx
					local dz = record.z - cz

					if pointInRadius(dx, dz, r2) then func(entity) end
				end
			end
		end
	end
end

function SpatialHash.QueryAABB(
	self: SpatialHash,
	minX: number,
	minZ: number,
	maxX: number,
	maxZ: number,
	func: (EntityId) -> ()
): ()
	if minX > maxX then
		minX, maxX = maxX, minX
	end

	if minZ > maxZ then
		minZ, maxZ = maxZ, minZ
	end

	local spanX, spanZ = maxX - minX, maxZ - minZ
	local size: number
	local buckets: Buckets

	if spanX >= self.COARSE_SIZE * 4 or spanZ >= self.COARSE_SIZE * 4 then
		size = self.COARSE_SIZE
		buckets = self.CoarseBuckets
	else
		size = self.CELL_SIZE
		buckets = self.FineBuckets
	end

	SpatialHashStatic.QueryAABB(minX, minZ, maxX, maxZ, size, func, buckets, self.Records)
end

function SpatialHash.QueryRadius(self: SpatialHash, cx: number, cz: number, radius: number, func: (EntityId) -> ()): ()
	local size: number
	local buckets: Buckets

	if radius >= self.COARSE_SIZE * 4 then
		size = self.COARSE_SIZE
		buckets = self.CoarseBuckets
	else
		size = self.CELL_SIZE
		buckets = self.FineBuckets
	end

	SpatialHashStatic.QueryRadius(cx, cz, radius, size, func, buckets, self.Records)
end

function SpatialHash.QueryAABBAsPoints(
	self: SpatialHash,
	minX: number,
	minZ: number,
	maxX: number,
	maxZ: number,
	func: (EntityId) -> ()
): ()
	if minX > maxX then
		minX, maxX = maxX, minX
	end

	if minZ > maxZ then
		minZ, maxZ = maxZ, minZ
	end

	local spanX, spanZ = (maxX - minX), (maxZ - minZ)
	local size: number
	local buckets: Buckets

	if spanX >= self.COARSE_SIZE * 4 or spanZ >= self.COARSE_SIZE * 4 then
		size = self.COARSE_SIZE
		buckets = self.CoarseBuckets
	else
		size = self.CELL_SIZE
		buckets = self.FineBuckets
	end

	SpatialHashStatic.QueryAABBAsPoints(minX, minZ, maxX, maxZ, size, func, buckets, self.Records)
end

function SpatialHash.QueryRadiusAsPoints(
	self: SpatialHash,
	cx: number,
	cz: number,
	radius: number,
	func: (EntityId) -> ()
): ()
	local size: number
	local buckets: Buckets

	if radius >= self.COARSE_SIZE * 4 then
		size = self.COARSE_SIZE
		buckets = self.CoarseBuckets
	else
		size = self.CELL_SIZE
		buckets = self.FineBuckets
	end

	SpatialHashStatic.QueryRadiusAsPoints(cx, cz, radius, size, func, buckets, self.Records)
end

--==[ Serialization ]==--
local HEADER = 2
local BYTES_PER_RECORD = 21
local SCALE = 0.05
local INV_SCALE = 1 / SCALE

local function numToU16(v: number): number
	return floor(v * INV_SCALE + 0.5) % 65536
end

local function u16ToNum(u: number): number
	return (if u >= 32768 then u - 65536 else u) * SCALE
end

function SpatialHashStatic.PackBuckets(buckets: Buckets): buffer
	local n = 0
	local total = HEADER

	for _, arr in buckets do
		n += 1
		total += 6 + 2 * #arr
	end

	local buf = buffer.create(total)
	buffer.writeu16(buf, 0, n)

	local off = HEADER

	for key, arr in buckets do
		local m = #arr

		buffer.writeu32(buf, off, key)
		buffer.writeu16(buf, off + 4, m)
		off += 6

		for i = 1, m do
			buffer.writeu16(buf, off, (arr[i] :: any) :: number)
			off += 2
		end
	end

	return buf
end

function SpatialHashStatic.UnpackBuckets(buf: buffer): Buckets
	local lenBuf = buffer.len(buf)
	if lenBuf < HEADER then return {} end

	local n = buffer.readu16(buf, 0)
	local off = HEADER

	local out = table_create(n) :: Buckets

	for _ = 1, n do
		if off + 6 > lenBuf then break end

		local key = buffer.readu32(buf, off)
		local m = buffer.readu16(buf, off + 4)
		off += 6

		if off + m * 2 > lenBuf then m = max(0, floor((lenBuf - off) / 2)) end

		local arr = table_create(m) :: { number }
		for i = 1, m do
			arr[i] = buffer.readu16(buf, off)
			off += 2
		end

		out[key] = arr :: any
	end

	return out
end

function SpatialHashStatic.UnpackBucketsInto(
	buf: buffer,
	reuse: Buckets,
	epochs: { [number]: number }?,
	epoch: number?
): ()
	local lenBuf = buffer.len(buf)
	if lenBuf < HEADER then return end

	local n = buffer.readu16(buf, 0)
	local off = HEADER

	for _ = 1, n do
		if off + 6 > lenBuf then break end

		local key = buffer.readu32(buf, off)
		local m = buffer.readu16(buf, off + 4)
		off += 6

		if off + m * 2 > lenBuf then m = max(0, floor((lenBuf - off) / 2)) end

		local arr = reuse[key]
		if arr then
			table_clear(arr)
		else
			arr = table_create(m)
		end

		for i = 1, m do
			arr[i] = buffer.readu16(buf, off)
			off += 2
		end

		reuse[key] = arr :: any
		if epochs then epochs[key] = epoch :: number end
	end
end

function SpatialHashStatic.PackRecords(records: Records): buffer
	local n = 0

	for _ in records do
		n += 1
	end

	local approx = HEADER + n * BYTES_PER_RECORD
	local buf = buffer.create(approx)

	buffer.writeu16(buf, 0, n)

	local off = HEADER
	for key, rec in records do
		buffer.writeu16(buf, off, (key :: any) :: number)
		off += 2
		buffer.writef32(buf, off, rec.x)
		off += 4
		buffer.writef32(buf, off, rec.z)
		off += 4
		buffer.writef32(buf, off, rec.y)
		off += 4
		buffer.writeu8(buf, off, rec.shape)
		off += 1

		if rec.shape == EShape.AABB then
			buffer.writeu16(buf, off, numToU16((rec :: RecordAABB).halfx))
			off += 2
			buffer.writeu16(buf, off, numToU16((rec :: RecordAABB).halfy))
			off += 2
			buffer.writeu16(buf, off, numToU16((rec :: RecordAABB).halfz))
			off += 2
		elseif rec.shape == EShape.Circle then
			buffer.writeu16(buf, off, numToU16((rec :: RecordCircle).radius))
			off += 2
		end
	end

	if off < approx then
		local shrunk = buffer.create(off)
		buffer.copy(shrunk, 0, buf, 0, off)
		return shrunk
	end

	return buf
end

function SpatialHashStatic.UnpackRecords(buf: buffer): Records
	local lenBuf = buffer.len(buf)
	if lenBuf < HEADER then return {} end

	local n = buffer.readu16(buf, 0)
	local out = table_create(n) :: Records
	local off = HEADER
	local bounds = queryExtents[out]
	if not bounds then
		bounds = { x = 0, z = 0, recursive = false }
		queryExtents[out] = bounds
	end
	bounds.x, bounds.z = 0, 0

	for _ = 1, n do
		if off + 15 > lenBuf then break end
		local key = buffer.readu16(buf, off)
		off += 2
		local x = buffer.readf32(buf, off)
		off += 4
		local z = buffer.readf32(buf, off)
		off += 4
		local y = buffer.readf32(buf, off)
		off += 4
		local shape = buffer.readu8(buf, off)
		off += 1

		if shape == EShape.Point then
			out[key :: any] = { x = x, y = y, z = z, shape = shape }
		elseif shape == EShape.AABB then
			if off + 6 > lenBuf then break end
			local hx = u16ToNum(buffer.readu16(buf, off))
			off += 2
			local hy = u16ToNum(buffer.readu16(buf, off))
			off += 2
			local hz = u16ToNum(buffer.readu16(buf, off))
			bounds.x = max(bounds.x, hx)
			bounds.z = max(bounds.z, hz)
			off += 2
			out[key :: any] = { x = x, y = y, z = z, shape = shape, halfx = hx, halfy = hy, halfz = hz }
		else
			if off + 2 > lenBuf then break end
			local radius = u16ToNum(buffer.readu16(buf, off))
			bounds.x = max(bounds.x, radius)
			bounds.z = max(bounds.z, radius)
			off += 2
			out[key :: any] = { x = x, y = y, z = z, shape = shape, radius = radius }
		end
	end

	return out
end

function SpatialHashStatic.UnpackRecordsInto(buf: buffer, reuse: Records, epochs: { [number]: number }?, epoch: number?)
	local lenBuf = buffer.len(buf)
	if lenBuf < HEADER then return end

	local n = buffer.readu16(buf, 0)
	local off = HEADER
	local bounds = queryExtents[reuse]
	if not bounds then
		bounds = { x = 0, z = 0, recursive = false }
		queryExtents[reuse] = bounds
	end
	bounds.x, bounds.z = 0, 0

	for _ = 1, n do
		if off + 15 > lenBuf then break end
		local key = buffer.readu16(buf, off)
		off += 2
		local x = buffer.readf32(buf, off)
		off += 4
		local z = buffer.readf32(buf, off)
		off += 4
		local y = buffer.readf32(buf, off)
		off += 4
		local shape = buffer.readu8(buf, off)
		off += 1
		local rec = reuse[key :: any] :: any
		if not rec then
			rec = {}
			reuse[key :: any] = rec
		end

		rec.x, rec.y, rec.z, rec.shape = x, y, z, shape
		if epochs then epochs[key] = epoch :: number end

		if shape == EShape.Point then
			rec.radius, rec.halfx, rec.halfy, rec.halfz = nil, nil, nil, nil
		elseif shape == EShape.AABB then
			if off + 6 > lenBuf then break end
			local hx = u16ToNum(buffer.readu16(buf, off))
			off += 2
			local hy = u16ToNum(buffer.readu16(buf, off))
			off += 2
			local hz = u16ToNum(buffer.readu16(buf, off))
			bounds.x = max(bounds.x, hx)
			bounds.z = max(bounds.z, hz)
			off += 2
			rec.halfx, rec.halfy, rec.halfz, rec.radius = hx, hy, hz, nil
		else
			if off + 2 > lenBuf then break end
			local radius = u16ToNum(buffer.readu16(buf, off))
			bounds.x = max(bounds.x, radius)
			bounds.z = max(bounds.z, radius)
			off += 2
			rec.radius, rec.halfx, rec.halfy, rec.halfz = radius, nil, nil, nil
		end
	end
end

return SpatialHashStatic :: SpatialHashStatic
