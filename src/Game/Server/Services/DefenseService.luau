-- Placed defenses (GDD 15): turrets that shoot on their own, and barricades enemies route around and attack. A
-- barricade blocks its nodes for every flowfield and its ring of neighbours is the barricade field's sources
-- (NavService). A turret hits in its owner's name, so its kills pay its owner (GDD 13).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local Network = require(ServerScriptService.GlobalServer.Network)
local EconomyService = require(script.Parent.EconomyService)
local EnemiesService = require(script.Parent.EnemiesService)
local NavService = require(script.Parent.NavService)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local ArenaCore = require(ReplicatedStorage.Shared.Core.ArenaCore)
local EnemiesCore = require(ReplicatedStorage.Shared.Core.EnemiesCore)
local TimeCore = require(ReplicatedStorage.Shared.Core.TimeCore)
local Components = require(ReplicatedStorage.GlobalShared.ECS.Components)
local Tags = require(ReplicatedStorage.GlobalShared.ECS.Tags)
local EnemyWorld = require(ReplicatedStorage.GlobalShared.ECS.Worlds.EnemyWorld)
local World = require(ReplicatedStorage.GlobalShared.ECS.Worlds.World)
local getCharacterEntityFromPlayer =
	require(ReplicatedStorage.GlobalShared.Utils.Functions.getCharacterEntityFromPlayer)
local TData = require(ReplicatedStorage.Types.TData)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)

local ServerNetworkDefenses = Network.Server.Defenses
local ClientNetworkDefenses = Network.Client.Defenses

local DEFENSES = DataCore.Defenses.ById
local DefensesFolder = Workspace:WaitForChild("Defenses")
local ModelsFolder = ReplicatedStorage:WaitForChild("Models")

-- How far from his character a player may place (flat studs).
local PLACE_REACH = 30
-- A footprint's floor may vary this much before it is not "flat".
local FLAT_TOLERANCE = 0.6
local NO_NODE = ArenaCore.NO_NODE

type TPlaced = {
	Id: number,
	Data: TData.TDefense,
	Owner: Player,
	Position: vector,
	-- Half the footprint after its turn, and half the height: what swings and blasts are measured against.
	Half: vector,
	Health: number,
	MaxHealth: number,
	Level: number,
	Model: Model,
	Nodes: { number },
	Ring: { number },
	NextFireAt: number,
}

local DefenseService = {}

local placed: { [number]: TPlaced } = {}
local nextId = 0
local reusableCaught: { any } = {}

local function countOwned(player: Player, dataId: number): number
	local count = 0
	for _, defense in placed do
		if defense.Owner == player and defense.Data.Id == dataId then
			count += 1
		end
	end

	return count
end

local function isClaimed(node: number): boolean
	for _, defense in placed do
		if table.find(defense.Nodes, node) then return true end
	end

	return false
end

-- The nodes under a footprint centred at (x, z) on the floor at `floorY`, or nil when it is not flat open floor.
local function footprintNodes(nav: ArenaCore.TNavGrid, x: number, z: number, floorY: number, half: vector): { number }?
	local cellSize = nav.CellSize
	local minCX = math.floor((x - half.x - nav.OriginX) / cellSize + 0.5)
	local maxCX = math.floor((x + half.x - nav.OriginX) / cellSize + 0.5)
	local minCZ = math.floor((z - half.z - nav.OriginZ) / cellSize + 0.5)
	local maxCZ = math.floor((z + half.z - nav.OriginZ) / cellSize + 0.5)
	local nodes = {}

	for cz = minCZ, maxCZ do
		for cx = minCX, maxCX do
			local node = ArenaCore.StepTarget(nav, cx, cz, floorY)
			if node == NO_NODE or math.abs(ArenaCore.NodeHeight(nav, node) - floorY) > FLAT_TOLERANCE then
				return nil
			end
			if buffer.readu8(NavService.Blocked, node) ~= 0 or isClaimed(node) then return nil end
			table.insert(nodes, node)
		end
	end

	return nodes
end

-- The open nodes around a footprint, which is where a body stands to hit it.
local function ringNodes(nav: ArenaCore.TNavGrid, nodes: { number }): { number }
	local ring = {}
	local seen = {}

	for _, node in nodes do
		seen[node] = true
	end

	for _, node in nodes do
		for d = 1, 8 do
			local link = ArenaCore.Link(nav, node, d)
			if link == NO_NODE or seen[link] then continue end
			seen[link] = true
			table.insert(ring, link)
		end
	end

	return ring
end

local function refreshBarricadeField()
	local sources = {}
	for _, defense in placed do
		if defense.Data.Kind ~= "Barricade" then continue end
		for _, node in defense.Ring do
			if buffer.readu8(NavService.Blocked, node) == 0 then table.insert(sources, node) end
		end
	end

	NavService.SetBarricadeSources(sources)
end

local function buildModel(data: TData.TDefense, half: vector): Model
	local defensesModels = ModelsFolder:FindFirstChild("Defenses")
	local template = if defensesModels then defensesModels:FindFirstChild(data.ModelName) else nil
	if template and template:IsA("Model") then return template:Clone() end

	-- TODO: the real model. A block the size of the footprint until it exists.
	local model = Instance.new("Model")
	local part = Instance.new("Part")
	part.Anchored = true
	part.Size = Vector3.new(half.x * 2, half.y * 2, half.z * 2)
	part.Color = if data.Kind == "Barricade" then Color3.fromRGB(90, 170, 255) else Color3.fromRGB(255, 200, 80)
	part.Material = Enum.Material.Neon
	part.Transparency = 0.2
	part.Parent = model
	model.PrimaryPart = part
	return model
end

local function remove(defense: TPlaced)
	placed[defense.Id] = nil
	defense.Model:Destroy()
	if defense.Data.Kind == "Barricade" then
		NavService.SetBlocked(defense.Nodes, false)
		refreshBarricadeField()
	end

	ServerNetworkDefenses.Removed.FireAll(defense.Id)
end

-- Places `dataId` for `player` at `position` (its foot centre), turned `quarterTurns` * 90 degrees. Returns the id.
function DefenseService.Place(player: Player, dataId: number, position: vector, quarterTurns: number): number?
	local data = DEFENSES[dataId]
	local nav = ArenaCore.Nav
	if not data or not nav then return nil end
	local characterEntity = getCharacterEntityFromPlayer(player)
	if not characterEntity or not World:has(characterEntity, Tags.Alive) then return nil end
	local root = World:get(characterEntity, Components.HumanoidRootPart)
	if not root then return nil end
	local dx, dz = position.x - root.Position.X, position.z - root.Position.Z
	if dx * dx + dz * dz > PLACE_REACH * PLACE_REACH then return nil end
	if countOwned(player, dataId) >= data.MaxPerPlayer then return nil end

	local isTurned = quarterTurns % 2 == 1
	local fx = if isTurned then data.Footprint.Y else data.Footprint.X
	local fz = if isTurned then data.Footprint.X else data.Footprint.Y
	local floorY = ArenaCore.GetFloorY(position.x, position.z, position.y + ArenaCore.MAX_STEP)
	if not floorY then return nil end
	local height = if data.Kind == "Barricade" then 5 else 4
	local half = vector.create(fx / 2, height / 2, fz / 2)
	local nodes = footprintNodes(nav, position.x, position.z, floorY, half)
	if not nodes then return nil end
	if not EconomyService.TrySpendGold(player, data.Cost) then return nil end

	nextId = nextId % 65535 + 1
	while placed[nextId] do
		nextId = nextId % 65535 + 1
	end

	local at = vector.create(position.x, floorY, position.z)
	local model = buildModel(data, half)
	model.Name = `{data.Name}_{nextId}`
	model:PivotTo(CFrame.new(at.x, at.y + half.y, at.z) * CFrame.Angles(0, quarterTurns * math.pi / 2, 0))
	model.Parent = DefensesFolder

	local defense: TPlaced = {
		Id = nextId,
		Data = data,
		Owner = player,
		Position = at,
		Half = half,
		Health = data.MaxHealth,
		MaxHealth = data.MaxHealth,
		Level = 0,
		Model = model,
		Nodes = nodes,
		Ring = ringNodes(nav, nodes),
		NextFireAt = 0,
	}
	placed[nextId] = defense
	if data.Kind == "Barricade" then
		NavService.SetBlocked(nodes, true)
		refreshBarricadeField()
	end

	ServerNetworkDefenses.Placed.FireAll(nextId, dataId, player, at :: any)
	ServerNetworkDefenses.Health.FireAll(nextId, defense.Health, defense.MaxHealth)
	return nextId
end

function DefenseService.Upgrade(player: Player, id: number): boolean
	local defense = placed[id]
	if not defense or defense.Owner ~= player then return false end
	local cost = defense.Data.UpgradeCosts[defense.Level + 1]
	if not cost or not EconomyService.TrySpendGold(player, cost) then return false end
	defense.Level += 1
	-- A level is also a full repair, so upgrading a worn barricade is worth its price.
	defense.MaxHealth = defense.Data.MaxHealth * (1 + 0.5 * defense.Level)
	defense.Health = defense.MaxHealth
	ServerNetworkDefenses.Health.FireAll(id, defense.Health, defense.MaxHealth)
	return true
end

-- An enemy or a blast hit a defense.
function DefenseService.Damage(id: number, amount: number)
	local defense = placed[id]
	if not defense or amount <= 0 then return end
	defense.Health -= amount
	if defense.Health <= 0 then
		remove(defense)
		return
	end

	ServerNetworkDefenses.Health.FireAll(id, defense.Health, defense.MaxHealth)
end

-- Barricades into the movement tick's parallel arrays. Returns how many.
function DefenseService.GetBarricades(ids: { number }, centers: { vector }, halves: { vector }): number
	local count = 0
	for id, defense in placed do
		if defense.Data.Kind ~= "Barricade" then continue end
		count += 1
		ids[count] = id
		centers[count] = defense.Position
		halves[count] = defense.Half
	end

	return count
end

-- Every defense within `radius` of `center` (flat), into `out`. For blasts.
function DefenseService.GetInRadius(center: vector, radius: number, out: { number }): { number }
	for id, defense in placed do
		local dx, dz = defense.Position.x - center.x, defense.Position.z - center.z
		local reach = radius + math.max(defense.Half.x, defense.Half.z)
		if dx * dx + dz * dz <= reach * reach then table.insert(out, id) end
	end

	return out
end

function DefenseService.GetPosition(id: number): vector?
	local defense = placed[id]
	return if defense then defense.Position else nil
end

function DefenseService.ClearAll()
	for _, defense in placed do
		remove(defense)
	end
end

local function collect(enemyEntity: any)
	reusableCaught[#reusableCaught + 1] = enemyEntity
end

DefenseService.OnPlayerDisconnected = function(player: Player)
	-- A leaver's defenses go with him: nobody can upgrade them, and their kills would pay no one.
	for _, defense in placed do
		if defense.Owner == player then remove(defense) end
	end
end :: TPlayerEvents.OnPlayerDisconnected

RunService.Heartbeat:Connect(function()
	if TimeCore.IsPaused then return end
	local now = TimeCore.GameClock
	for id, defense in placed do
		local data = defense.Data
		if data.Kind ~= "Turret" or now < defense.NextFireAt then continue end
		table.clear(reusableCaught)
		local at = defense.Position
		EnemiesCore.EnemiesSpatialHash:QueryRadiusAsPoints(at.x, at.z, data.Range :: number, collect)

		-- Nearest first, ties by instance id, so two turrets on one crowd agree on who goes first.
		local best, bestSq, bestId = nil, math.huge, math.huge
		for _, enemyEntity in reusableCaught do
			local position = EnemyWorld:get(enemyEntity, Components.Position)
			local instanceId = EnemyWorld:get(enemyEntity, Components.InstanceId)
			if not position or not instanceId then continue end
			local dx, dy, dz = position.x - at.x, position.y - at.y, position.z - at.z
			local sq = dx * dx + dy * dy + dz * dz
			if sq < bestSq or (sq == bestSq and instanceId < bestId) then
				best, bestSq, bestId = enemyEntity, sq, instanceId
			end
		end

		if not best then continue end
		defense.NextFireAt = now + (data.FireInterval :: number)
		local damage = (data.Damage :: number) + (data.DamagePerLevel or 0) * defense.Level
		local ownerCharacter = if defense.Owner.Parent then getCharacterEntityFromPlayer(defense.Owner) else nil
		EnemiesService.Damage(ownerCharacter, best, damage)
		ServerNetworkDefenses.Shot.FireAll(id, bestId)
	end
end)

-- The intent only: what, where, which way. Reach, cost, footprint and limits are all checked in Place.
ClientNetworkDefenses.Place.On(function(player: Player, dataId: number, position: vector, quarterTurns: number)
	DefenseService.Place(player, dataId, position, quarterTurns % 4)
end)

ClientNetworkDefenses.Upgrade.On(function(player: Player, id: number)
	DefenseService.Upgrade(player, id)
end)

return Ignis.Register(DefenseService)
