--!native
--!optimize 2
-- Flowfields over ArenaCore's layered nav graph: one per living character, one for every barricade at once. A field is
-- each node's path cost to its target, which is what "nearest" means here: a player on a platform reached by stairs is
-- not near the enemy under it.
--
-- Barricades are obstacles for every field and the sources of their own, so a crowd routes around them toward a player
-- and walks up to them when they are the nearest thing to hit.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local ArenaCore = require(ReplicatedStorage.Shared.Core.ArenaCore)

local readu8 = buffer.readu8
local readu32 = buffer.readu32
local readi32 = buffer.readi32
local writeu32 = buffer.writeu32

local INF = 0xFFFFFFFF
local NO_NODE = ArenaCore.NO_NODE
local COST_DIAGONAL = ArenaCore.COST_DIAGONAL
-- One bucket per possible cost remainder: the largest link cost plus one.
local BUCKETS = COST_DIAGONAL + 1
-- A field is rebuilt only when its source moved to a new node or a barricade changed the graph, and no faster than
-- these, so a party running around costs a handful of floods a second.
local REBUILDS_PER_FRAME = 1
local MIN_REBUILD_SECONDS = 0.25

export type TNavField = {
	Dist: buffer,
	-- False until its first flood lands; an enemy then falls back to a straight line.
	IsReady: boolean,
	IsDirty: boolean,
	Sources: { number },
	RebuiltAt: number,
}

local NavService = {}

NavService.INF = INF
-- Per node, 1 when a barricade stands on it. Read by enemiesUpdate.
NavService.Blocked = buffer.create(1)
NavService.CharacterFields = {} :: { [number]: TNavField }
NavService.BarricadeField = nil :: TNavField?

local characterNodes: { [number]: number } = {}
local barricadeSources: { number } = {}
local bucketLists: { { number } } = table.create(BUCKETS)
local bucketCounts: { number } = table.create(BUCKETS, 0)
for i = 1, BUCKETS do
	bucketLists[i] = {}
end

local function newField(nodeCount: number): TNavField
	return {
		Dist = buffer.create(math.max(nodeCount, 1) * 4),
		IsReady = false,
		IsDirty = true,
		Sources = {},
		RebuiltAt = -math.huge,
	}
end

-- Floods `field` from its sources over the REVERSE links (ArenaCore's packed incoming lists), so each node's cost is
-- its cost to walk TO a source. Dial's algorithm: link costs are small integers, so a ring of buckets replaces the
-- heap and a flood is linear in the nodes.
local function flood(nav: ArenaCore.TNavGrid, field: TNavField)
	local dist = field.Dist
	local nodeCount = nav.NodeCount
	buffer.fill(dist, 0, 0xFF, nodeCount * 4)
	local blocked = NavService.Blocked
	local incomingStart = nav.IncomingStart
	local incomingNode = nav.IncomingNode
	local incomingCost = nav.IncomingCost

	for i = 1, BUCKETS do
		bucketCounts[i] = 0
	end

	local pending = 0
	for _, source in field.Sources do
		if source < 0 or source >= nodeCount then continue end
		writeu32(dist, source * 4, 0)
		bucketCounts[1] += 1
		bucketLists[1][bucketCounts[1]] = source
		pending += 1
	end

	local cost = 0
	while pending > 0 do
		local slot = cost % BUCKETS + 1
		local list = bucketLists[slot]
		-- Link costs are 10 and 14, never 0, so nothing is added to this slot while it is walked: cost + 14 wraps
		-- back onto it only after it has been emptied.
		for index = 1, bucketCounts[slot] do
			local node = list[index]
			pending -= 1
			if readu32(dist, node * 4) ~= cost then continue end
			for at = readu32(incomingStart, node * 4), readu32(incomingStart, (node + 1) * 4) - 1 do
				local from = readi32(incomingNode, at * 4)
				if readu8(blocked, from) ~= 0 then continue end
				local newCost = cost + readu8(incomingCost, at)
				if readu32(dist, from * 4) <= newCost then continue end
				writeu32(dist, from * 4, newCost)
				local target = newCost % BUCKETS + 1
				bucketCounts[target] += 1
				bucketLists[target][bucketCounts[target]] = from
				pending += 1
			end
		end

		bucketCounts[slot] = 0
		cost += 1
	end

	field.IsReady = true
	field.IsDirty = false
	field.RebuiltAt = os.clock()
end

local function markAllDirty()
	for _, field in NavService.CharacterFields do
		field.IsDirty = true
	end

	if NavService.BarricadeField then NavService.BarricadeField.IsDirty = true end
end

-- The node a character stands on, reported each movement tick. A new node dirties its field.
function NavService.SetCharacterNode(characterId: number, node: number)
	local nav = ArenaCore.Nav
	if not nav or node == NO_NODE then return end
	local field = NavService.CharacterFields[characterId]
	if not field then
		field = newField(nav.NodeCount)
		NavService.CharacterFields[characterId] = field
	end

	if characterNodes[characterId] == node then return end
	characterNodes[characterId] = node
	field.Sources[1] = node
	field.IsDirty = true
end

function NavService.RemoveCharacter(characterId: number)
	NavService.CharacterFields[characterId] = nil
	characterNodes[characterId] = nil
end

-- Marks `nodes` as walls (or clears them) for every field. Barricades call this when placed and destroyed.
function NavService.SetBlocked(nodes: { number }, isBlocked: boolean)
	local nav = ArenaCore.Nav
	if not nav then return end
	for _, node in nodes do
		if node >= 0 and node < nav.NodeCount then
			buffer.writeu8(NavService.Blocked, node, if isBlocked then 1 else 0)
		end
	end

	markAllDirty()
end

-- Every node a barricade can be attacked from. Replaces the previous set.
function NavService.SetBarricadeSources(nodes: { number })
	table.clear(barricadeSources)
	table.move(nodes, 1, #nodes, 1, barricadeSources)
	local nav = ArenaCore.Nav
	if not nav then return end
	if #barricadeSources == 0 then
		NavService.BarricadeField = nil
		return
	end

	local field = NavService.BarricadeField or newField(nav.NodeCount)
	NavService.BarricadeField = field
	field.Sources = table.clone(barricadeSources)
	field.IsDirty = true
end

-- Floods one field now, for tests and for a field that must be fresh before an enemy can use it.
NavService.Flood = flood

function NavService.Reset()
	table.clear(NavService.CharacterFields)
	table.clear(characterNodes)
	table.clear(barricadeSources)
	NavService.BarricadeField = nil
	local nav = ArenaCore.Nav
	NavService.Blocked = buffer.create(if nav then math.max(nav.NodeCount, 1) else 1)
end

ArenaCore.OnBaked:Connect(NavService.Reset)

RunService.Heartbeat:Connect(function()
	local nav = ArenaCore.Nav
	if not nav then return end
	local now = os.clock()
	local budget = REBUILDS_PER_FRAME
	-- Oldest dirty field first, so one player moving constantly cannot starve another.
	while budget > 0 do
		local oldest: TNavField? = nil
		for _, field in NavService.CharacterFields do
			if not field.IsDirty or now - field.RebuiltAt < MIN_REBUILD_SECONDS then continue end
			if not oldest or field.RebuiltAt < oldest.RebuiltAt then oldest = field end
		end

		local barricades = NavService.BarricadeField
		if barricades and barricades.IsDirty and now - barricades.RebuiltAt >= MIN_REBUILD_SECONDS then
			if not oldest or barricades.RebuiltAt < oldest.RebuiltAt then oldest = barricades end
		end

		if not oldest then return end
		debug.profilebegin("NavFlood")
		flood(nav, oldest)
		debug.profileend()
		budget -= 1
	end
end)

return Ignis.Register(NavService)
