-- The lobby's shooting range on the server (RangeCore). Whoever stands in it is offered guns (Range.Offer) and holds
-- the one they picked of those, and loses both on the way out. Walked in, the offer is their loadout, one gun a tier;
-- brought by the weapons screen's TRY, only the gun they are trying, owned or not, since trying costs nothing. Every shot is run as the match's WeaponService runs one: re-cast from
-- the character's own head with this side's seed and spread, against the hall and the standing dummies' aim shapes.
-- A dummy's health, its fall and its standing back up are decided here; every client draws them (RangeController).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local jecs = require(ReplicatedStorage.Packages.jecs)
local Network = require(ServerScriptService.GlobalServer.Network)
local DatabaseService = require(ServerScriptService.GlobalServer.Services.DatabaseService)
local buildGunTool = require(ServerScriptService.GlobalServer.Utils.buildGunTool)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local GunsCore = require(ReplicatedStorage.GlobalShared.Core.GunsCore)
local LoadoutCore = require(ReplicatedStorage.GlobalShared.Core.LoadoutCore)
local RangeCore = require(ReplicatedStorage.Shared.Core.RangeCore)
local sightCast = require(ReplicatedStorage.GlobalShared.Utils.sightCast)
local Components = require(ReplicatedStorage.GlobalShared.ECS.Components)
local Tags = require(ReplicatedStorage.GlobalShared.ECS.Tags)
local World = require(ReplicatedStorage.GlobalShared.ECS.Worlds.World)
local getCharacterEntityFromPlayer =
	require(ReplicatedStorage.GlobalShared.Utils.Functions.getCharacterEntityFromPlayer)
local TData = require(ReplicatedStorage.Types.TData)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)
local TCharacterEvents = require(ReplicatedStorage.Types.Events.TCharacterEvents)

local ServerNetworkWeapons = Network.Server.Weapons
local ClientNetworkWeapons = Network.Client.Weapons
local ServerNetworkRange = Network.Server.Range
local ClientNetworkRange = Network.Client.Range

local GUNS = DataCore.Guns.ById
local GunsTune = GunsCore.Tune
local FLAT_XZ = Vector3.new(1, 0, 1)

local Tune = table.freeze({
	-- Who is in the range is looked at this often.
	CHECK_SECONDS = 0.25,
	-- WeaponService's: a shot accepted this much early against the gun's interval, and the pad on every gun's
	-- HitRadius for the bodies the client aimed at a little behind where the server has them.
	RATE_TOLERANCE = 0.8,
	LAG_PAD = 0.75,
	-- Picks closer together than this are let go: each one builds a gun.
	PICK_SECONDS = 0.1,
	-- A booth with a character this close to it is taken.
	BOOTH_TAKEN_STUDS = 6,
	-- A player TRY stood in a booth is not taken for gone for this long: the move may not have reached their body yet.
	TRY_GRACE_SECONDS = 1.5,
	-- Others see a shooter's arms on their last shot's line for this long, then on where the body faces.
	AIM_HOLD_SECONDS = 1.5,
	AIMS_PER_SECOND = 10,
	ANGLE_SCALE = 32767 / math.pi,
})

local EOutcome = table.freeze({ Hit = 0, Kill = 1, Overkill = 2 })

type TArmed = {
	Gun: TData.TGun,
	Tool: Tool,
	CharacterEntity: jecs.Entity<any>,
	NextShotAt: number,
	ShotCount: number,
	Look: Vector3,
	LookedAt: number,
}

local RangeService = {}

local dummies: { RangeCore.TDummy } = {}
local healths: { number } = {}
-- os.clock until which each dummy is down (0 standing).
local downUntil: { number } = {}
local sightParams: RaycastParams? = nil
local armed: { [Player]: TArmed } = {}
-- The guns each player in the range is offered, and the one of them they hold.
local offers: { [Player]: { number } } = {}
local chosen: { [Player]: number } = {}
local pickedAt: { [Player]: number } = {}
local triedAt: { [Player]: number } = {}
local templates: { [number]: Tool | false } = {}

-- Scratch, reused so a shot allocates nothing: the standing dummies (their index by body), each pellet's direction,
-- and the damage per dummy.
local bodies = GunsCore.NewBodies()
local bodyDummies: { number } = {}
-- Each standing dummy's feet for this shot, by index (nil while down).
local standingFeet: { [number]: Vector3 } = {}
local pelletDirections: { Vector3 } = {}
local hitDamage: { [number]: number } = {}
local aims: { { Character: number, Pitch: number, Yaw: number } } = {}
local checkAccumulator = 0
local aimsAccumulator = 0

local function getTemplate(gun: TData.TGun): Tool?
	local template = templates[gun.Id]
	if template == nil then
		template = buildGunTool(gun) or false
		templates[gun.Id] = template
	end

	return template or nil
end

-- The character's root while it stands, or nil.
local function getStandingRoot(characterEntity: jecs.Entity<any>): BasePart?
	if not World:contains(characterEntity) or not World:has(characterEntity, Tags.Alive) then return nil end
	local humanoid = World:get(characterEntity, Components.Humanoid)
	if not humanoid or humanoid.Health <= 0 then return nil end
	return World:get(characterEntity, Components.HumanoidRootPart)
end

local function disarm(player: Player)
	local entry = armed[player]
	if not entry then return end
	armed[player] = nil
	entry.Tool:Destroy()
end

local function arm(player: Player, characterEntity: jecs.Entity<any>, gun: TData.TGun)
	local humanoid = World:get(characterEntity, Components.Humanoid)
	local template = getTemplate(gun)
	if not humanoid or not template then return end

	disarm(player)
	local tool = template:Clone()
	humanoid:EquipTool(tool)
	armed[player] = {
		Gun = gun,
		Tool = tool,
		CharacterEntity = characterEntity,
		NextShotAt = 0,
		ShotCount = 0,
		Look = Vector3.xAxis,
		LookedAt = -math.huge,
	}
	ServerNetworkWeapons.Equipped.Fire(player, gun.Id, 0)
end

-- Offers `gunIds` to `player`, holding the first of them unless the one they hold is among them.
local function offer(player: Player, gunIds: { number })
	offers[player] = gunIds
	if not table.find(gunIds, chosen[player]) then chosen[player] = gunIds[1] end
	ServerNetworkRange.Offer.Fire(player, gunIds)
end

local function withdraw(player: Player)
	if not offers[player] then return end
	offers[player] = nil
	chosen[player] = nil
	ServerNetworkRange.Offer.Fire(player, {})
end

-- The gun each tier of the player's loadout holds, first tier first.
local function loadoutOf(player: Player): { number }
	local profile = DatabaseService.Get(player)
	local equipped = if profile then profile.Loadout.Equipped else {}
	local gunIds = table.create(LoadoutCore.TIERS)
	for tier = 1, LoadoutCore.TIERS do
		gunIds[tier] = LoadoutCore.EquippedOf(equipped, tier).Id
	end

	return gunIds
end

-- Inside, offered their loadout as they walk in and the gun they picked in hand (again if it went missing); outside,
-- empty hands and no offer.
local function check(player: Player)
	local characterEntity = getCharacterEntityFromPlayer(player)
	local root = if characterEntity then getStandingRoot(characterEntity) else nil
	if not characterEntity or not root or not RangeCore.IsInside(root.Position) then
		if os.clock() - (triedAt[player] or -math.huge) < Tune.TRY_GRACE_SECONDS then return end
		disarm(player)
		withdraw(player)
		return
	end

	if not offers[player] then offer(player, loadoutOf(player)) end
	local gun = GUNS[chosen[player]]
	if not gun then return end
	local entry = armed[player]
	if entry and entry.Gun == gun and entry.Tool.Parent == root.Parent then return end
	arm(player, characterEntity, gun)
end

-- After the weapons screen changed the player's loadout: in the range, the strip shows it at once (a TRY's gun gives
-- way to it too), and a gun taken out of its tier is swapped in hand for the one put in.
function RangeService.LoadoutChanged(player: Player)
	if not offers[player] then return end
	local held = GUNS[chosen[player]]
	local gunIds = loadoutOf(player)
	if held and not table.find(gunIds, held.Id) then chosen[player] = gunIds[held.Tier] end
	offer(player, gunIds)
	check(player)
end

-- Whether a dummy stands now; one whose time down is over is whole again.
local function isStanding(index: number, now: number): boolean
	local standsAt = downUntil[index]
	if standsAt == 0 then return true end
	if now < standsAt then return false end
	downUntil[index] = 0
	healths[index] = RangeCore.HEALTH
	return true
end

-- Every standing dummy, where the shooter saw it: the sway taken back by their ping, since they aimed at the dummy as
-- it was drawn when they fired. A dozen bodies, so no box is worth testing first.
local function gatherBodies(serverTime: number, now: number)
	bodies.Count = 0
	for index, dummy in dummies do
		if not isStanding(index, now) then
			standingFeet[index] = nil
			continue
		end
		local feet = RangeCore.Feet(dummy, serverTime).Position
		standingFeet[index] = feet
		GunsCore.AddBody(bodies, feet, dummy.Aim.z, dummy.Aim.y)
		bodyDummies[bodies.Count] = index
	end
end

-- The standing dummies (gatherBodies) whose feet are within `radius` of `at` across the floor.
local function addSplash(at: Vector3, radius: number, damage: number, directHit: number?)
	for index, feet in standingFeet do
		if index == directHit or ((at - feet) * FLAT_XZ).Magnitude > radius then continue end
		hitDamage[index] = (hitDamage[index] or 0) + damage
	end
end

-- Each dummy's share of the volley as one blow (only standing ones were hit): down it goes when that empties it.
local function payOut(instanceId: number, now: number)
	for index, damage in hitDamage do
		local left = healths[index] - damage
		local outcome = EOutcome.Hit
		if left <= 0 then
			left = 0
			downUntil[index] = now + RangeCore.DOWN_SECONDS
			outcome = if damage >= RangeCore.HEALTH * RangeCore.OVERKILL_RATIO then EOutcome.Overkill else EOutcome.Kill
		end
		healths[index] = left
		ServerNetworkRange.Hit.FireAll(index, instanceId, damage, outcome)
	end

	table.clear(hitDamage)
end

local function shoot(player: Player, entry: TArmed, origin: Vector3, direction: Vector3, instanceId: number)
	local gun = entry.Gun
	local profile = DatabaseService.Get(player)
	local level = (if profile then LoadoutCore.LevelOf(profile.Loadout.Owned, gun) else nil) or 1
	local pellets = math.min(gun.Pellets, GunsTune.MAX_PELLETS)
	local pelletDamage = LoadoutCore.Damage(gun, level) / gun.Pellets
	local pad = gun.HitRadius + Tune.LAG_PAD
	local splashRadius = gun.SplashRadius
	local pierce = gun.Pierce or 0
	local now = os.clock()
	local serverTime = Workspace:GetServerTimeNow() - player:GetNetworkPing()
	gatherBodies(serverTime, now)
	GunsCore.PelletDirections(direction, entry.ShotCount, gun.SpreadDeg, pellets, pelletDirections)

	for pellet = 1, pellets do
		local unit = pelletDirections[pellet]
		local wall, wallDistance = sightCast(origin, unit * gun.Range, sightParams)
		local body, distance = GunsCore.CastBodies(bodies, origin, unit, wallDistance, pad, -1)
		local stoppedIn = nil
		local piercesLeft = pierce
		while body > 0 do
			local index = bodyDummies[body]
			hitDamage[index] = (hitDamage[index] or 0) + pelletDamage
			if piercesLeft == 0 then
				stoppedIn = index
				break
			end
			piercesLeft -= 1
			body, distance = GunsCore.CastBodies(bodies, origin, unit, wallDistance, pad, distance)
		end

		if splashRadius and (stoppedIn or wall) then
			addSplash(origin + unit * distance, splashRadius, pelletDamage * GunsTune.SPLASH_SHARE, stoppedIn)
		end
	end

	payOut(instanceId, now)
end

-- The booth nobody stands in, the nearest the middle first; all taken, the least crowded.
local function freeBooth(player: Player): CFrame
	local best, bestCount = RangeCore.BOOTHS[1], math.huge
	for _, booth in RangeCore.BOOTHS do
		local count = 0
		for _, other in Players:GetPlayers() do
			local character = other.Character
			if other == player or not character then continue end
			local distance = (character:GetPivot().Position - booth.Position).Magnitude
			if distance < Tune.BOOTH_TAKEN_STUDS then
				count += 1
			end
		end
		if count < bestCount then
			best, bestCount = booth, count
		end
	end

	return best
end

-- Every armed character's look: down their last shot's line for a moment, else where the body faces. The records
-- are reused: Blink writes them out on the call.
local function sendAims()
	local now = os.clock()
	local count = 0
	for _, entry in armed do
		local instanceId = World:get(entry.CharacterEntity, Components.InstanceId)
		local root = World:get(entry.CharacterEntity, Components.HumanoidRootPart)
		if not instanceId or not root then continue end
		local look = if now - entry.LookedAt < Tune.AIM_HOLD_SECONDS then entry.Look else root.CFrame.LookVector
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

-- The intent only: where the crosshair was. The guards are this side's: a standing character in the range holding
-- this gun, and its rate. The shot leaves from the server's head, never a point the client names.
ClientNetworkWeapons.Fire.On(function(player: Player, aimPoint: Vector3)
	local entry = armed[player]
	if not entry then return end
	if aimPoint.X ~= aimPoint.X or aimPoint.Y ~= aimPoint.Y or aimPoint.Z ~= aimPoint.Z then return end
	local characterEntity = entry.CharacterEntity
	local root = getStandingRoot(characterEntity)
	if not root or entry.Tool.Parent ~= root.Parent or not RangeCore.IsInside(root.Position) then return end
	local instanceId = World:get(characterEntity, Components.InstanceId)
	if not instanceId then return end
	local now = os.clock()
	if now < entry.NextShotAt then return end

	local origin = root.Position + Vector3.yAxis * GunsTune.EYE_HEIGHT
	local toAim = aimPoint - origin
	if toAim.Magnitude < 0.5 then return end
	entry.NextShotAt = now + entry.Gun.FireInterval * Tune.RATE_TOLERANCE
	entry.ShotCount = (entry.ShotCount + 1) % 65536
	entry.Look = toAim.Unit
	entry.LookedAt = now

	shoot(player, entry, origin, toAim.Unit, instanceId)
	ServerNetworkWeapons.Shot.FireExcept(player, instanceId, aimPoint, entry.ShotCount)
end)

-- One of the guns the range offers them, held at once.
ClientNetworkRange.Pick.On(function(player: Player, gunId: number)
	local offered = offers[player]
	local now = os.clock()
	if not offered or not table.find(offered, gunId) then return end
	if now - (pickedAt[player] or -math.huge) < Tune.PICK_SECONDS then return end
	pickedAt[player] = now
	chosen[player] = gunId
	check(player)
end)

-- The weapons screen's TRY, any gun there is: a standing character not held on a queue pad (the pad anchors it) is
-- stood in a free booth with that gun in hand, and offered only it.
ClientNetworkRange.Try.On(function(player: Player, gunId: number)
	local gun = GUNS[gunId]
	local characterEntity = getCharacterEntityFromPlayer(player)
	local root = if characterEntity then getStandingRoot(characterEntity) else nil
	if not gun or not characterEntity or not root or root.Anchored then return end
	local character = World:get(characterEntity, Components.Model)
	if not character then return end

	offer(player, { gunId })
	triedAt[player] = os.clock()
	character:PivotTo(freeBooth(player))
	root.AssemblyLinearVelocity = Vector3.zero
	arm(player, characterEntity, gun)
end)

RangeService.OnStart = function()
	dummies = RangeCore.GatherDummies()
	if #dummies == 0 then warn("[RangeService] no dummies under Workspace.Lobby.Map.Range.Targets") end
	for index in dummies do
		healths[index] = RangeCore.HEALTH
		downUntil[index] = 0
	end
	sightParams = RangeCore.SightParams()

	RunService.Heartbeat:Connect(function(dt: number)
		checkAccumulator += dt
		if checkAccumulator >= Tune.CHECK_SECONDS then
			checkAccumulator = 0
			for _, player in Players:GetPlayers() do
				check(player)
			end
		end

		aimsAccumulator += dt
		if aimsAccumulator < 1 / Tune.AIMS_PER_SECOND then return end
		aimsAccumulator = 0
		sendAims()
	end)
end

RangeService.OnCharacterRemoving = function(character)
	local player = Players:GetPlayerFromCharacter(character)
	if player then armed[player] = nil end
end :: TCharacterEvents.OnCharacterRemoving

RangeService.OnPlayerDisconnected = function(player: Player)
	armed[player] = nil
	offers[player] = nil
	chosen[player] = nil
	pickedAt[player] = nil
	triedAt[player] = nil
end :: TPlayerEvents.OnPlayerDisconnected

return Ignis.Register(RangeService)
