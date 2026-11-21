-- Every enemy attack that is not a plain swing (GDD 11, 14). enemiesUpdate decides when one starts; this shows it and
-- resolves it.
--
-- THE WARNING IS THE HITBOX: what resolves is exactly the shape sent as the ground warning, same centre, same size,
-- same floor (TelegraphCore's footprint), same moment. Once shown it resolves on schedule even if its caster is
-- staggered, frozen, knocked away or killed (GDD 13), except an exploding zombie killed during its fuse, whose warning
-- is taken back.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local Network = require(ServerScriptService.GlobalServer.Network)
local CharacterService = require(script.Parent.CharacterService)
local DefenseService = require(script.Parent.DefenseService)
local EnemiesService = require(script.Parent.EnemiesService)
local ArenaCore = require(ReplicatedStorage.Shared.Core.ArenaCore)
local TelegraphCore = require(ReplicatedStorage.Shared.Core.TelegraphCore)
local TimeCore = require(ReplicatedStorage.Shared.Core.TimeCore)
local Components = require(ReplicatedStorage.GlobalShared.ECS.Components)
local Tags = require(ReplicatedStorage.GlobalShared.ECS.Tags)
local EnemyWorld = require(ReplicatedStorage.GlobalShared.ECS.Worlds.EnemyWorld)
local World = require(ReplicatedStorage.GlobalShared.ECS.Worlds.World)
local getCharacterFeet = require(ReplicatedStorage.GlobalShared.Utils.Functions.getCharacterFeet)
local ETelegraphs = require(ReplicatedStorage.Types.Enums.ETelegraphs)
local TData = require(ReplicatedStorage.Types.TData)

local ServerNetworkEnemies = Network.Server.Enemies

local CharactersQuery =
	World:query(Components.HumanoidRootPart, Components.Humanoid):with(Tags.Character, Tags.Alive):cached()

-- A defense is in a cone or a line when its centre is this close to it (a circle measures its footprint instead).
local DEFENSE_REACH = 1.5

type TPending = {
	TelegraphId: number,
	Entity: any,
	Attack: TData.TEnemyAttack,
	Warning: TelegraphCore.TWarning,
	-- The nav nodes it covers; nil when there is no grid under it (flat, HEIGHT up and down).
	Footprint: { [number]: boolean }?,
	Damage: number,
	ResolveAt: number,
}

type TRing = {
	TelegraphId: number,
	Center: vector,
	Footprint: { [number]: boolean }?,
	Radius: number,
	MaxRadius: number,
	Speed: number,
	Damage: number,
	Hit: { [any]: boolean },
}

local EnemyAttacksService = {}

local pending: { TPending } = {}
-- Each pending entry's Warning, at the same index: what enemiesUpdate keeps new warnings off.
local warnings: { TelegraphCore.TWarning } = {}
local rings: { TRing } = {}
local nextTelegraphId = 0
local reusableDefenses: { number } = {}

local function newTelegraphId(): number
	nextTelegraphId = nextTelegraphId % 65535 + 1
	return nextTelegraphId
end

-- Called by enemiesUpdate (deferred, after its loop) when an attack's wind-up begins.
function EnemyAttacksService.Start(entity: any, attackIndex: number, attack: TData.TEnemyAttack, center: vector)
	EnemiesService.SignalAttackStarted(entity, attackIndex)
	if attack.Kind == "Melee" then return end

	local damage = (EnemyWorld:get(entity, Components.Damage) or 0) * attack.DamageScale
	local id = newTelegraphId()
	local kind, size, width = TelegraphCore.ShapeOf(attack)
	local data = EnemyWorld:get(entity, Components.Data)
	local isBoss = data ~= nil and data.IsBoss == true
	local yaw = 0
	-- enemiesUpdate has already turned the body to its target, so its yaw is the aim.
	if kind == ETelegraphs.Cone or kind == ETelegraphs.Line then
		center = EnemyWorld:get(entity, Components.Position) or center
		yaw = EnemyWorld:get(entity, Components.Yaw) or 0
	end

	local footprint = {}
	local floorY = TelegraphCore.Footprint(ArenaCore.Nav, kind, center, yaw, size, width, footprint)
	-- On the floor itself, so the client's flood starts from the same node.
	if floorY then center = vector.create(center.x, floorY, center.z) end

	ServerNetworkEnemies.Telegraph.FireAll(
		id,
		kind,
		center :: any,
		yaw,
		size,
		width,
		attack.Delay,
		attack.Speed or 0,
		isBoss,
		attack.Kind == "Explode"
	)
	local warning: TelegraphCore.TWarning =
		{ IsBoss = isBoss, Kind = kind, Center = center, Yaw = yaw, Size = size, Width = width }
	table.insert(warnings, warning)
	table.insert(pending, {
		TelegraphId = id,
		Entity = entity,
		Attack = attack,
		Warning = warning,
		Footprint = if floorY then footprint else nil,
		Damage = damage,
		ResolveAt = TimeCore.EnemyClock + attack.Delay,
	})
end

-- The warnings still winding up, for enemiesUpdate to keep new ones off. Read only.
function EnemyAttacksService.GetWarnings(): { TelegraphCore.TWarning }
	return warnings
end

function EnemyAttacksService.Reset()
	for _, entry in pending do
		ServerNetworkEnemies.TelegraphEnded.FireAll(entry.TelegraphId)
	end

	for _, ring in rings do
		ServerNetworkEnemies.TelegraphEnded.FireAll(ring.TelegraphId)
	end

	table.clear(pending)
	table.clear(warnings)
	table.clear(rings)
end

-- Everything inside a warning takes its damage: living characters and defenses.
local function hitArea(entry: TPending)
	local nav = ArenaCore.Nav
	local warning = entry.Warning
	local kind, center, yaw, size, width = warning.Kind, warning.Center, warning.Yaw, warning.Size, warning.Width
	for characterEntity, rootPart, humanoid in CharactersQuery do
		local feet = getCharacterFeet(rootPart, humanoid, 0)
		if not TelegraphCore.IsInside(nav, entry.Footprint, kind, center, yaw, size, width, feet) then continue end
		CharacterService.Damage(characterEntity, entry.Damage)
	end

	local reach = if kind == ETelegraphs.Line then math.sqrt(size * size + width * width / 4) else size
	table.clear(reusableDefenses)
	for _, id in DefenseService.GetInRadius(center, reach, reusableDefenses) do
		local at = DefenseService.GetPosition(id)
		if not at then continue end
		if kind ~= ETelegraphs.Circle then
			local x, z = TelegraphCore.ToLocal(center, yaw, at)
			if TelegraphCore.Distance(kind, size, width, x, z) > DEFENSE_REACH then continue end
		end

		DefenseService.Damage(id, entry.Damage)
	end
end

local function resolve(entry: TPending)
	local attack = entry.Attack
	local kind = attack.Kind
	if kind == "Explode" then
		if not EnemyWorld:contains(entry.Entity) then return end
		hitArea(entry)
		-- It is gone with the blast, credited to nobody: a blast is not a kill a player earned.
		EnemiesService.Kill(nil, entry.Entity, 0)
	elseif kind == "Slam" then
		hitArea(entry)
	elseif kind == "Shockwave" then
		table.insert(rings, {
			TelegraphId = entry.TelegraphId,
			Center = entry.Warning.Center,
			Footprint = entry.Footprint,
			Radius = 0,
			MaxRadius = entry.Warning.Size,
			Speed = attack.Speed or 25,
			Damage = entry.Damage,
			Hit = {},
		})
		return
	end

	ServerNetworkEnemies.TelegraphEnded.FireAll(entry.TelegraphId)
end

-- Kill-to-cancel: a fuse whose body is gone takes its warning back with it.
EnemiesService.OnEnemyRemoving:Connect(function(entity)
	for i = #pending, 1, -1 do
		local entry = pending[i]
		if entry.Entity ~= entity or entry.Attack.Kind ~= "Explode" then continue end
		ServerNetworkEnemies.TelegraphEnded.FireAll(entry.TelegraphId)
		table.remove(pending, i)
		table.remove(warnings, i)
	end
end)

RunService.Heartbeat:Connect(function(dt: number)
	if TimeCore.IsPaused then return end
	local now = TimeCore.EnemyClock
	for i = #pending, 1, -1 do
		local entry = pending[i]
		if now < entry.ResolveAt then continue end
		table.remove(pending, i)
		table.remove(warnings, i)
		resolve(entry)
	end

	local enemyDt = TimeCore.GetEnemyDeltaTime(dt)
	local nav = ArenaCore.Nav
	local band = TelegraphCore.RING_BAND
	local clearance = TelegraphCore.RING_CLEARANCE
	for i = #rings, 1, -1 do
		local ring = rings[i]
		ring.Radius += ring.Speed * enemyDt
		local outer, inner = ring.Radius, math.max(ring.Radius - band, 0)
		for characterEntity, rootPart, humanoid in CharactersQuery do
			if ring.Hit[characterEntity] then continue end
			local feet = getCharacterFeet(rootPart, humanoid, 0)
			local dx, dz = feet.x - ring.Center.x, feet.z - ring.Center.z
			local distSq = dx * dx + dz * dz
			if distSq > outer * outer or distSq < inner * inner then continue end
			local floorY = TelegraphCore.FloorUnder(nav, ring.Footprint, ring.Center, feet)
			-- On a floor it does not run along, or jumped over it.
			if not floorY or feet.y - floorY > clearance then continue end
			ring.Hit[characterEntity] = true
			CharacterService.Damage(characterEntity, ring.Damage)
		end

		if ring.Radius < ring.MaxRadius then continue end
		ServerNetworkEnemies.TelegraphEnded.FireAll(ring.TelegraphId)
		table.remove(rings, i)
	end
end)

return Ignis.Register(EnemyAttacksService)
