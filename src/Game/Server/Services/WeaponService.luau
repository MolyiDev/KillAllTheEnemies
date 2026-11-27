-- Guns on the server: the one each player holds (a Tool, so the gun in the hand replicates on its own) and every shot.
-- A shot is re-cast here from the character's own head with this side's seed and spread, against the arena and the
-- enemies' aim shapes (EnemiesCore), and pays out as one DamageMultiple per damage figure. The client only says where
-- it aimed. Each player climbs their own ladder through the run (GunsCore.Ladder, from their lobby loadout), one bought
-- step at a time.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local jecs = require(ReplicatedStorage.Packages.jecs)
local Network = require(ServerScriptService.GlobalServer.Network)
local AOIService = require(script.Parent.AOIService)
local CharacterService = require(script.Parent.CharacterService)
local DatabaseService = require(ServerScriptService.GlobalServer.Services.DatabaseService)
local EconomyService = require(script.Parent.EconomyService)
local EnemiesService = require(script.Parent.EnemiesService)
local EnemyMovementService = require(script.Parent.EnemyMovementService)
local buildGunTool = require(ServerScriptService.GlobalServer.Utils.buildGunTool)
local upgradeStats = require(script.Parent.Parent.Utils.upgradeStats)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local GunsCore = require(ReplicatedStorage.GlobalShared.Core.GunsCore)
local EnemiesCore = require(ReplicatedStorage.Shared.Core.EnemiesCore)
local TimeCore = require(ReplicatedStorage.Shared.Core.TimeCore)
local sightCast = require(ReplicatedStorage.GlobalShared.Utils.sightCast)
local Components = require(ReplicatedStorage.GlobalShared.ECS.Components)
local Tags = require(ReplicatedStorage.GlobalShared.ECS.Tags)
local EnemyWorld = require(ReplicatedStorage.GlobalShared.ECS.Worlds.EnemyWorld)
local World = require(ReplicatedStorage.GlobalShared.ECS.Worlds.World)
local getCharacterEntityFromPlayer =
	require(ReplicatedStorage.GlobalShared.Utils.Functions.getCharacterEntityFromPlayer)
local EUpgradesIds = require(ReplicatedStorage.Types.Enums.Data.EUpgradesIds)
local TData = require(ReplicatedStorage.Types.TData)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)

local ServerNetworkWeapons = Network.Server.Weapons
local ClientNetworkWeapons = Network.Client.Weapons

local GUNS = DataCore.Guns.ById
local GunsTune = GunsCore.Tune
local EnemiesSpatialHash = EnemiesCore.EnemiesSpatialHash
-- A long body's pieces reach far past its feet, where the spatial hash keeps it, so these are tested on every shot.
-- Not while under the floor: nothing can hit it there.
local PiecedQuery =
	EnemyWorld:query(Components.Position, Components.Yaw, Components.AimPieces):without(Tags.Submerged):cached()

local Tune = table.freeze({
	-- A shot is accepted this much early against the gun's interval, for the jitter between two of the client's.
	RATE_TOLERANCE = 0.8,
	-- The widest body's half width, so a body whose centre is just off the ray's box is still tested.
	MAX_BODY_RADIUS = 4,
	-- A body that took less than this share of a shoving shot is not shoved: any shove at all costs a body about a
	-- second getting back up to speed, which a one-pellet graze has not earned.
	KNOCKBACK_MIN_SHARE = 0.25,
	AIMS_PER_SECOND = 10,
	ANGLE_SCALE = 32767 / math.pi,
})

type TArmed = {
	Gun: TData.TGun,
	Tool: Tool,
	CharacterEntity: jecs.Entity<any>,
	NextShotAt: number,
	ShotCount: number,
}

local WeaponService = {}

local armed: { [Player]: TArmed } = {}
-- The gun each player chose, kept across deaths: a revive hands back the same one.
local chosen: { [Player]: number } = {}
-- The step of their ladder each player is on this run (1 when absent).
local steps: { [Player]: number } = {}
-- Each player's ladder, built once their profile loads (ladderOf gives the starters' until then).
local ladders: { [Player]: { GunsCore.TLadderStep } } = {}
local templates: { [number]: Tool | false } = {}

-- Scratch, reused so a shot allocates nothing: the bodies near it (and their entities, by the same index), each
-- pellet's direction, the damage per body, and the bodies grouped by damage figure (lists out of a pool).
local bodies = GunsCore.NewBodies()
local bodyEntities: { jecs.Entity<any> } = {}
local pelletDirections: { Vector3 } = {}
-- One pellet's hits, nearest first (GunsCore.CastBodiesAll).
local castIndices: { number } = {}
local castDistances: { number } = {}
local reusableCandidates: { jecs.Entity<any> } = {}
local hitDamage: { [jecs.Entity<any>]: number } = {}
local byFigure: { [number]: { jecs.Entity<any> } } = {}
local figureLists: { { jecs.Entity<any> } } = {}
local aims: { { Character: number, Pitch: number, Yaw: number } } = {}
local aimsAccumulator = 0

local function collect(enemyEntity: any)
	reusableCandidates[#reusableCandidates + 1] = enemyEntity
end

local function getTemplate(gun: TData.TGun): Tool?
	local template = templates[gun.Id]
	if template == nil then
		template = buildGunTool(gun) or false
		templates[gun.Id] = template
	end

	return template or nil
end

local function equip(player: Player, characterEntity: jecs.Entity<any>, gun: TData.TGun): boolean
	local humanoid = World:get(characterEntity, Components.Humanoid)
	local template = getTemplate(gun)
	if not humanoid or not template then return false end

	local previous = armed[player]
	if previous then previous.Tool:Destroy() end

	local tool = template:Clone()
	humanoid:EquipTool(tool)
	armed[player] = { Gun = gun, Tool = tool, CharacterEntity = characterEntity, NextShotAt = 0, ShotCount = 0 }
	ServerNetworkWeapons.Equipped.Fire(player, gun.Id, steps[player] or 1)
	return true
end

-- Hands `player` gun `gunId`, replacing what they held. False when they have no character or the gun has no model.
function WeaponService.Equip(player: Player, gunId: number): boolean
	local gun = GUNS[gunId]
	if not gun then return false end
	chosen[player] = gunId
	local characterEntity = getCharacterEntityFromPlayer(player)
	return characterEntity ~= nil and equip(player, characterEntity, gun)
end

local function ladderOf(player: Player): { GunsCore.TLadderStep }
	return ladders[player] or GunsCore.STARTER_LADDER
end

-- A new run: everyone back on the first step, the first step's gun in hand.
function WeaponService.ResetRun()
	table.clear(steps)
	table.clear(chosen)
	for player, entry in armed do
		local first = GUNS[ladderOf(player)[1].Gun]
		if entry.Gun ~= first then
			equip(player, entry.CharacterEntity, first)
		else
			ServerNetworkWeapons.Equipped.Fire(player, first.Id, 1)
		end
	end
end

-- Every body a shot from `origin` along `direction` could reach: the box around its whole cone, out to `range`.
local function gatherBodies(origin: Vector3, direction: Vector3, range: number, spreadDeg: number, pad: number)
	local finish = origin + direction * range
	local reach = range * math.tan(math.rad(spreadDeg))
	local margin = reach + Tune.MAX_BODY_RADIUS
	table.clear(reusableCandidates)
	EnemiesSpatialHash:QueryAABBAsPoints(
		math.min(origin.X, finish.X) - margin,
		math.min(origin.Z, finish.Z) - margin,
		math.max(origin.X, finish.X) + margin,
		math.max(origin.Z, finish.Z) + margin,
		collect
	)

	-- The box takes in most of the arena for a diagonal shot. A body farther from the shot's line, seen from above, than
	-- the cone's reach plus the widest body and the pad cannot be hit by any pellet: dropped before its reads, its
	-- shape and every pellet's cast (-15% to -56% a shot, same hits: performance/optimization-2026-11-26).
	local originX, originZ = origin.X, origin.Z
	local lineX, lineZ = finish.X - originX, finish.Z - originZ
	local lineSq = lineX * lineX + lineZ * lineZ
	local tube = reach + Tune.MAX_BODY_RADIUS + pad
	local tubeSq = tube * tube

	bodies.Count = 0
	for _, enemyEntity in reusableCandidates do
		local position = EnemyWorld:get(enemyEntity, Components.Position)
		if not position then continue end
		local offsetX, offsetZ = position.x - originX, position.z - originZ
		local along = if lineSq > 0 then math.clamp((offsetX * lineX + offsetZ * lineZ) / lineSq, 0, 1) else 0
		local sideX, sideZ = offsetX - lineX * along, offsetZ - lineZ * along
		if sideX * sideX + sideZ * sideZ > tubeSq then continue end
		local enemyData = EnemyWorld:get(enemyEntity, Components.Data)
		if not enemyData or enemyData.AimPieces then continue end
		local aim = EnemiesCore.AimShape(enemyData)
		GunsCore.AddBody(bodies, position :: any, aim.z, aim.y)
		bodyEntities[bodies.Count] = enemyEntity
	end

	for enemyEntity, position, yaw, pieces in PiecedQuery do
		local first = GunsCore.AddPieces(bodies, position :: any, Vector3.new(math.sin(yaw), 0, math.cos(yaw)), pieces)
		for index = first, bodies.Count do
			bodyEntities[index] = enemyEntity
		end
	end
end

local function addSplash(at: Vector3, radius: number, damage: number, directHit: any)
	table.clear(reusableCandidates)
	EnemiesSpatialHash:QueryRadiusAsPoints(at.X, at.Z, radius, collect)
	for _, enemyEntity in reusableCandidates do
		if enemyEntity == directHit then continue end
		hitDamage[enemyEntity] = (hitDamage[enemyEntity] or 0) + damage
	end
end

-- The volley's damage grouped by figure: a body three pellets hit takes one figure, a body one hit another, and each
-- figure is one DamageMultiple. A gun that shoves (TGun.Knockback) shoves each figure's bodies along the shot by the
-- share of the shot they took, after the damage: the dead are gone by then and only what still stands gives ground.
local function payOut(characterEntity: jecs.Entity<any>, gun: TData.TGun, direction: Vector3)
	local used = 0
	for enemyEntity, damage in hitDamage do
		local list = byFigure[damage]
		if not list then
			used += 1
			list = figureLists[used]
			if not list then
				list = {}
				figureLists[used] = list
			end
			byFigure[damage] = list
		end
		list[#list + 1] = enemyEntity
	end

	table.clear(hitDamage)
	local knockback = gun.Knockback
	local shoveFrom = gun.Damage * Tune.KNOCKBACK_MIN_SHARE
	for damage, enemyEntities in byFigure do
		EnemiesService.DamageMultiple(characterEntity, enemyEntities, damage)
		if knockback and damage >= shoveFrom then
			EnemyMovementService.Push(enemyEntities, direction, knockback * math.min(damage / gun.Damage, 1))
		end
		table.clear(enemyEntities)
	end

	table.clear(byFigure)
end

local function shoot(
	characterEntity: jecs.Entity<any>,
	gun: TData.TGun,
	origin: Vector3,
	direction: Vector3,
	seed: number
)
	local pellets = math.min(gun.Pellets, GunsTune.MAX_PELLETS)
	local pelletDamage = gun.Damage / gun.Pellets
	local pad = gun.HitRadius + GunsTune.LAG_PAD
	local splashRadius = gun.SplashRadius
	local pierce = gun.Pierce or 0
	gatherBodies(origin, direction, gun.Range, gun.SpreadDeg, pad)
	GunsCore.PelletDirections(direction, seed, gun.SpreadDeg, pellets, pelletDirections)

	for pellet = 1, pellets do
		local unit = pelletDirections[pellet]
		local wall, wallDistance = sightCast(origin, unit * gun.Range)
		local hitCount = GunsCore.CastBodiesAll(bodies, origin, unit, wallDistance, pad, castIndices, castDistances)
		-- The pellet hurts the first body in its way and the `pierce` behind it, each in full. It stops in the last of
		-- those, or goes on to the arena when it runs out of bodies first (`distance` is then the wall's).
		-- A long body's pieces come one after another along the ray: the body is hit once, and the next piece of it is
		-- no new body to pierce.
		local stoppedIn = nil
		local distance = wallDistance
		local piercesLeft = pierce
		local lastHit = nil
		for hit = 1, hitCount do
			local enemyEntity = bodyEntities[castIndices[hit]]
			if enemyEntity == lastHit then continue end
			lastHit = enemyEntity
			hitDamage[enemyEntity] = (hitDamage[enemyEntity] or 0) + pelletDamage
			if piercesLeft == 0 then
				stoppedIn = enemyEntity
				distance = castDistances[hit]
				break
			end
			piercesLeft -= 1
		end

		if splashRadius and (stoppedIn or wall) then
			addSplash(origin + unit * distance, splashRadius, pelletDamage * GunsTune.SPLASH_SHARE, stoppedIn)
		end
	end

	payOut(characterEntity, gun, direction)
end

-- Every armed character's look, from the camera sync. The records are reused: Blink writes them out on the call.
local function sendAims()
	local count = 0
	for player, entry in armed do
		local instanceId = World:get(entry.CharacterEntity, Components.InstanceId)
		local look = AOIService.GetCameraLook(player)
		if not instanceId or not look then continue end
		count += 1
		local aim = aims[count]
		if not aim then
			aim = { Character = 0, Pitch = 0, Yaw = 0 }
			aims[count] = aim
		end
		aim.Character = instanceId
		aim.Pitch = math.round(math.asin(math.clamp(look.Y, -1, 1)) * Tune.ANGLE_SCALE)
		aim.Yaw = math.round(math.atan2(-look.X, -look.Z) * Tune.ANGLE_SCALE)
	end

	for index = count + 1, #aims do
		aims[index] = nil
	end

	if count > 0 then ServerNetworkWeapons.Aims.FireAll(aims) end
end

-- The intent only: where the crosshair was. The guards are this side's: a standing character holding this gun, not
-- picking an upgrade (it cannot be hurt meanwhile), its rate, the match not paused. The shot leaves from the server's
-- head, never a point the client names.
ClientNetworkWeapons.Fire.On(function(player: Player, aimPoint: Vector3)
	local entry = armed[player]
	if not entry or TimeCore.IsPaused then return end
	if aimPoint.X ~= aimPoint.X or aimPoint.Y ~= aimPoint.Y or aimPoint.Z ~= aimPoint.Z then return end
	local characterEntity = entry.CharacterEntity
	if not World:contains(characterEntity) or not World:has(characterEntity, Tags.Alive) then return end
	if (World:get(characterEntity, Components.CurrentHealth) or 0) <= 0 then return end
	if World:has(characterEntity, Tags.Picking) then return end
	local root = World:get(characterEntity, Components.HumanoidRootPart)
	if not root or entry.Tool.Parent ~= root.Parent then return end
	local now = TimeCore.GameClock
	if now < entry.NextShotAt then return end

	local origin = root.Position + Vector3.yAxis * GunsTune.EYE_HEIGHT
	local toAim = aimPoint - origin
	if toAim.Magnitude < 0.5 then return end
	local rate = 1 + upgradeStats.Get(player, EUpgradesIds.FireRate)
	entry.NextShotAt = now + entry.Gun.FireInterval / rate * Tune.RATE_TOLERANCE
	entry.ShotCount = (entry.ShotCount + 1) % 65536

	shoot(characterEntity, entry.Gun, origin, toAim.Unit, entry.ShotCount)

	local instanceId = World:get(characterEntity, Components.InstanceId)
	if instanceId then ServerNetworkWeapons.Shot.FireExcept(player, instanceId, aimPoint, entry.ShotCount) end
end)

-- Buys the next step of the ladder. The guards are the purse's and the body's: a standing character holding a gun,
-- a next step whose gun can be built, and its Gold, taken in the same step that hands the gun over.
ClientNetworkWeapons.Upgrade.On(function(player: Player)
	local entry = armed[player]
	if not entry then return end
	local characterEntity = entry.CharacterEntity
	if not World:contains(characterEntity) or not World:has(characterEntity, Tags.Alive) then return end
	if (World:get(characterEntity, Components.CurrentHealth) or 0) <= 0 then return end
	local step = (steps[player] or 1) + 1
	local offer = ladderOf(player)[step]
	local gun = if offer then GUNS[offer.Gun] else nil
	if not gun or not getTemplate(gun) then return end
	if not EconomyService.TrySpendGold(player, offer.Price) then return end

	steps[player] = step
	chosen[player] = gun.Id
	equip(player, characterEntity, gun)
end)

-- A character is armed once every client knows its id, so the gun's shots can name it.
CharacterService.OnCharacterReady:Connect(function(characterEntity: jecs.Entity<any>, player: Player)
	local gun = GUNS[chosen[player] or ladderOf(player)[steps[player] or 1].Gun]
	if gun then equip(player, characterEntity, gun) end
end)

-- The ladder comes from the lobby loadout, which cannot change during the match. A character armed before the profile
-- loaded holds the starter: it takes its own ladder's gun of the same step, unless it chose one (the console).
WeaponService.OnDataLoaded = function(player: Player)
	local profile = DatabaseService.Get(player)
	if not profile then return end

	local ladder = GunsCore.Ladder(profile.Loadout.Equipped)
	ladders[player] = ladder
	local gunIds = table.create(#ladder)
	for index, step in ladder do
		gunIds[index] = step.Gun
	end

	ServerNetworkWeapons.Ladder.Fire(player, gunIds)

	local entry = armed[player]
	if not entry or chosen[player] then return end
	local gun = GUNS[ladder[steps[player] or 1].Gun]
	if entry.Gun ~= gun then equip(player, entry.CharacterEntity, gun) end
end :: TPlayerEvents.OnDataLoaded

WeaponService.OnCharacterRemoving = function(character)
	local player = Players:GetPlayerFromCharacter(character)
	if player then armed[player] = nil end
end

WeaponService.OnPlayerDisconnected = function(player: Player)
	armed[player] = nil
	chosen[player] = nil
	steps[player] = nil
	ladders[player] = nil
end :: TPlayerEvents.OnPlayerDisconnected

RunService.Heartbeat:Connect(function(dt: number)
	aimsAccumulator += dt
	if aimsAccumulator < 1 / Tune.AIMS_PER_SECOND then return end
	aimsAccumulator = 0
	sendAims()
end)

return Ignis.Register(WeaponService)
