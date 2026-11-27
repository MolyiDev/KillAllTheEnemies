-- The gun in the local player's hands, in both places (the match, and the lobby's shooting range): the trigger, what
-- the crosshair is over (or the aim assist's pick), and everything a shot shows (tracers, the muzzle flash and sparks
-- or the gun's own effect kit through gunFx, the sound, the camera kick, the arms' jolt). It tells the server only
-- where it aimed (Weapons.Fire); hits and damage are the server's, and the bodies' flashes and numbers come from its
-- damage events. Other players' shots arrive as Weapons.Shot and are drawn here the same way.
--
-- What a gun can hit is every EnemyWorld row tagged Enemy with a CFrame (its feet) and an AimShape: the match's
-- enemies (EnemiesController) and the range's dummies (RangeController) alike.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local StarterPlayer = game:GetService("StarterPlayer")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local Network = require(StarterPlayer.StarterPlayerScripts.GlobalClient.Network)
local CameraController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.CameraController)
local BodyPoseController = require(script.Parent.BodyPoseController)
local ViewmodelController = require(script.Parent.ViewmodelController)
local gunFx = require(script.Parent.Parent.Utils.gunFx)
local gunSlide = require(script.Parent.Parent.Utils.gunSlide)
local tracers = require(script.Parent.Parent.Utils.tracers)
local EnemyImpacts = require(script.Parent.Parent.Utils.enemyImpacts)
local CharacterCore = require(ReplicatedStorage.GlobalShared.Core.CharacterCore)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local GunsCore = require(ReplicatedStorage.GlobalShared.Core.GunsCore)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local sightCast = require(ReplicatedStorage.GlobalShared.Utils.sightCast)
local Components = require(ReplicatedStorage.GlobalShared.ECS.Components)
local Tags = require(ReplicatedStorage.GlobalShared.ECS.Tags)
local EnemyWorld = require(ReplicatedStorage.GlobalShared.ECS.Worlds.EnemyWorld)
local World = require(ReplicatedStorage.GlobalShared.ECS.Worlds.World)
local TCharacterEvents = require(ReplicatedStorage.Types.Events.TCharacterEvents)
local TData = require(ReplicatedStorage.Types.TData)

local ServerNetworkWeapons = Network.Server.Weapons
local ClientNetworkWeapons = Network.Client.Weapons

-- Called per body in the walks below, so hoisted out of its module.
local addBody = GunsCore.AddBody

local GUNS = DataCore.Guns.ById
local SOUND_GROUP = "Guns"
-- Rendered bodies only: a parked one sits far away and is never under the crosshair.
local DrawnEnemiesQuery = EnemyWorld:query(Components.CFrame, Components.AimShape):with(Tags.Enemy):cached()
-- A long body's pieces (TEnemy.AimPieces) on top of its AimShape, which is only its trunk.
local PiecedQuery = EnemyWorld:query(Components.CFrame, Components.AimPieces):with(Tags.Enemy):cached()

local Tune = table.freeze({
	AIM_RANGE = 1000,
	-- A body this far behind a shot's start (studs along it) is still gathered: it may straddle the muzzle.
	BEHIND_MARGIN = 4,
	MUZZLE_FLASH_TIME = 0.05,
	MUZZLE_LIGHT_RANGE = 8,
	MUZZLE_LIGHT_BRIGHTNESS = 4,
	MUZZLE_LIGHT_BRIGHTNESS_CLOSE = 1.5,
	MUZZLE_LIGHT_COLOR = Color3.fromRGB(255, 214, 20),
	-- The pump or bolt after a shot.
	CYCLE_DELAY = 0.32,
	-- A gun's release after its last shot: its shot takes are cut this long after their hit and fade out as the
	-- release fades in (Assets/sounds/Review/Starters, round 3). Longer than the gun's FireInterval, or a held stream
	-- would ring between shots.
	RELEASE_DELAY = 0.12,
	SOUND_VOICES = 4,
	-- Camera kick: studs at its peak against the gun's kick in degrees, and the sideways share of it, on this spring
	-- (rad/s, damping ratio, roll per stud of side kick), set before every kick.
	KICK_PEAK_BASE = 0.1,
	KICK_PEAK_PER_DEG = 0.14,
	KICK_SIDE_SHARE = 0.45,
	RECOIL_FREQUENCY = 25,
	RECOIL_DAMPING = 0.6,
	RECOIL_ROLL = 0.25,
	-- The arms' jolt from the kick when the gun names none.
	POSE_KICK_REFERENCE_DEG = 1.2,
	POSE_KICK_MIN = 0.6,
	POSE_KICK_MAX = 2.2,
	-- A heavy shot shakes the view too: a gun kicking SHAKE_FROM_DEG or more shakes SHAKE_PER_KICK_DEG per degree of
	-- kick (at most SHAKE_MAX, a blast's), over SHAKE_SECONDS at SHAKE_SWINGS. A gun that fires again sooner than that
	-- never shakes: its shakes would run together into a buzz.
	SHAKE_FROM_DEG = 1.5,
	SHAKE_PER_KICK_DEG = 0.8,
	SHAKE_MAX = 3,
	SHAKE_SECONDS = 0.25,
	SHAKE_SWINGS = 3,
	-- Holding a gun with the cursor free, the body turns to face the aim (the lock already faces it): this fast
	-- (per second, exponential), never quicker than TURN_MAX_SPEED, and not for an aim this close to the feet, whose
	-- direction swings wildly as the cursor crosses them.
	TURN_RATE = 16,
	TURN_MAX_SPEED = math.rad(900),
	TURN_MIN_DISTANCE = 2,
	-- Aim assist, with the crosshair over no enemy: the shot goes to the chest of the best body in sight and in the
	-- gun's range. A body counts within ASSIST_RADIUS of the screen's height from the crosshair, or anywhere on screen
	-- within ASSIST_NEAR studs. Best is the lowest screen distance (in radii, weighed ASSIST_SCREEN) plus range (in the
	-- gun's, weighed ASSIST_DISTANCE), less ASSIST_STICKY for the body aimed at last frame so it does not flicker
	-- between two. Only the best ASSIST_CHECKS are raycast for sight; a wall this close past the chest is the body's own
	-- width, not cover.
	ASSIST_RADIUS = 0.14,
	ASSIST_NEAR = 22,
	ASSIST_SCREEN = 0.6,
	ASSIST_DISTANCE = 0.4,
	ASSIST_STICKY = 0.2,
	ASSIST_CHECKS = 4,
	ASSIST_SIGHT_SLACK = 1,
	-- A new gun handed over (not a step up the match's ladder, which WeaponRunController celebrates): the arms hoist
	-- it with this many shots' jolt and the camera dips this many studs at its peak, on the upgrade's soft spring.
	SWAP_POSE_KICK = 1.6,
	SWAP_KICK_PEAK = 0.18,
	SWAP_RECOIL_FREQUENCY = 14,
	SWAP_RECOIL_DAMPING = 0.55,
	-- Where the player's last bullet went into a boss stands for its blows' numbers this long: the server's word on
	-- that blow comes a round trip after the shot.
	BOSS_CONTACT_SECONDS = 0.6,
})

local RECOIL_PEAK_PER_IMPULSE = CameraController.RecoilPeakPerImpulse(Tune.RECOIL_FREQUENCY, Tune.RECOIL_DAMPING)
local SWAP_KICK_IMPULSE = Tune.SWAP_KICK_PEAK
	/ CameraController.RecoilPeakPerImpulse(Tune.SWAP_RECOIL_FREQUENCY, Tune.SWAP_RECOIL_DAMPING)
-- CameraController.Shake makes 4 swings every `roughness` seconds.
local SHAKE_ROUGHNESS = 4 * Tune.SHAKE_SECONDS / Tune.SHAKE_SWINGS

type TPendingSound = { At: number, Node: string, Position: Vector3, IsOwn: boolean }

local WeaponController = {}

-- The gun the server last handed this player, or nil.
WeaponController.Gun = nil :: TData.TGun?
-- The step of their run ladder the server has this player on (0 before the first gun, and always in the lobby).
WeaponController.Step = 0
-- os.clock of the last step up the ladder the server confirmed.
WeaponController.UpgradedAt = -math.huge
-- This frame: a gun is in living hands, and the crosshair's ray is on a body (not the assist's pick).
WeaponController.IsArmed = false
WeaponController.IsOnEnemy = false
-- os.clock of the local player's last shot.
WeaponController.FiredAt = -math.huge

-- The place's rules on the trigger, which only the match has (WeaponRunController sets them): whether a shot may be
-- drawn now, and the share its rate is raised by. The server holds the same rules.
WeaponController.CanFire = function(): boolean
	return true
end
WeaponController.GetFireRateBonus = function(): number
	return 0
end
-- What a shot stops on: nil for sightCast's default, Workspace.Arena. The lobby has no arena, so its range names its
-- own hall (RangeController); the server casts against the same.
WeaponController.SightParams = nil :: RaycastParams?

local LocalPlayer = Players.LocalPlayer

local selfCharacter: Model? = nil
local selfRoot: BasePart? = nil
local selfHumanoid: Humanoid? = nil
local isTriggerDown = false
local nextShotAt = 0
local shotCount = 0
-- This controller has turned AutoRotate off to face the body to the aim.
local isFacingAim = false
-- By bag. The player's own gun has pools of its own: SoundsCore merges a cue's repeats, and an ally's shot must never
-- swallow one of theirs.
local soundPools: { [string]: { SoundsCore.TSoundPool } } = {}
local ownSoundPools: { [string]: { SoundsCore.TSoundPool } } = {}
local pendingSounds: { TPendingSound } = {}
-- Each shooter's release, pushed back by every shot until the stream stops.
local pendingReleases: { [Model]: TPendingSound } = {}
local flashLights: { [Attachment]: PointLight } = {}
local flashOffAt: { [PointLight]: number } = {}
local random = Random.new()
-- Scratch for one shot: the drawn bodies near it and its pellets' directions.
local bodies = GunsCore.NewBodies()
local bodyEntities: { unknown } = {}
-- One ray's hits, nearest first (GunsCore.CastBodiesAll).
local castIndices: { number } = {}
local castDistances: { number } = {}
local pelletDirections: { Vector3 } = {}
-- The enemy the aim was on last frame, under the crosshair or assisted, and the assist's best few, best first.
local heldEntity: unknown = nil
-- This frame's aimed body among the gathered ones (its index, 0 for none), which a shot is lined up on, and the shot
-- GunsCore.LineUp lines up, filled for each one (lineUp).
local aimBody = 0
local lineUpShot: GunsCore.TLineUpShot = {
	Bodies = bodies,
	Owners = bodyEntities,
	Origin = Vector3.zero,
	Target = Vector3.zero,
	Body = 0,
	Pierce = 0,
	Range = 0,
	Pad = 0,
	CastWall = function(origin: Vector3, vector: Vector3): number
		local _, length = sightCast(origin, vector, WeaponController.SightParams)
		return length
	end,
}
local assistCount = 0
local assistEntities: { unknown } = table.create(Tune.ASSIST_CHECKS)
local assistPoints: { Vector3 } = table.create(Tune.ASSIST_CHECKS)
local assistScores: { number } = table.create(Tune.ASSIST_CHECKS)
-- Where the player's last bullet went into each boss, and the os.clock it did (BossContact).
local bossContacts: { [number]: Vector3 } = {}
local bossContactAt: { [number]: number } = {}

local function getPointer(): Vector2
	local camera = Workspace.CurrentCamera
	local center = camera.ViewportSize / 2
	if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter or not UserInputService.MouseEnabled then
		return center
	end

	local mouse = UserInputService:GetMouseLocation()
	local size = camera.ViewportSize
	if mouse.X < 0 or mouse.Y < 0 or mouse.X > size.X or mouse.Y > size.Y then return center end
	return mouse
end

-- The ray through the crosshair (a free cursor's point, or the screen's centre): where it starts and its unit
-- direction, from the view before shake and recoil (CameraController.AimCFrame), as the gun's own aim is.
function WeaponController.PointerRay(): (Vector3, Vector3)
	local camera = Workspace.CurrentCamera
	local view = CameraController.AimCFrame
	local center = camera.ViewportSize * 0.5
	local focal = center.Y / math.tan(math.rad(camera.FieldOfView) * 0.5)
	local toPointer = (getPointer() - center) / focal
	return view.Position, (view.LookVector + view.RightVector * toPointer.X - view.UpVector * toPointer.Y).Unit
end

-- Where the player's own last bullet went into the boss `instanceId`, if it was just now: a body that long is hit far
-- from its middle, and its numbers stand where the shots land (DamageNumbersController).
function WeaponController.BossContact(instanceId: number): Vector3?
	local at = bossContactAt[instanceId]
	if not at or os.clock() - at > Tune.BOSS_CONTACT_SECONDS then return nil end

	return bossContacts[instanceId]
end

-- Gathers the body if it is in front of `origin` along `direction` (or straddles it) within `rangeSq` (a parked body
-- sits far away and is left out by the range).
local function addBodyAhead(
	entity: unknown,
	feet: Vector3,
	aim: vector,
	origin: Vector3,
	direction: Vector3,
	rangeSq: number
)
	local offset = feet - origin
	if vector.dot(offset, offset) > rangeSq or vector.dot(offset, direction) < -Tune.BEHIND_MARGIN then return end
	addBody(bodies, feet, aim.z, aim.y)
	bodyEntities[bodies.Count] = entity
end

-- Every long body's pieces, wherever its feet are: its head can be in front of a ray its feet are far from.
local function addPieced()
	for entity, cframe, pieces in PiecedQuery do
		-- The body faces its CFrame's back (EnemiesController's buildTarget).
		local first = GunsCore.AddPieces(bodies, cframe.Position, cframe.ZVector, pieces)
		for index = first, bodies.Count do
			bodyEntities[index] = entity
		end
	end
end

-- The drawn bodies a shot from `origin` can reach, gathered once a shot.
local function gatherDrawnBodies(origin: Vector3, direction: Vector3, range: number)
	local rangeSq = range * range

	bodies.Count = 0
	for entity, cframe, aim in DrawnEnemiesQuery do
		addBodyAhead(entity, cframe.Position, aim, origin, direction, rangeSq)
	end

	addPieced()
end

local function isBossBody(body: number): boolean
	local enemyData = EnemyWorld:get(bodyEntities[body] :: any, Components.Data)
	return enemyData ~= nil and enemyData.Boss ~= nil
end

-- Where a ray stops: in one of the gathered bodies (its index, 0 for none), on the arena (with what it hit), or at its
-- full length. It goes through `pierce` bodies first (TGun.Pierce), so it stops in the one after them, or carries on
-- to the arena when there are no more in its way. Also the first boss it goes into, stopping there or not (its index,
-- 0 for none, and how far along): almost every gun pierces, so a bullet seldom stops in one.
local function castLine(
	origin: Vector3,
	unit: Vector3,
	range: number,
	pierce: number
): (Vector3, RaycastResult?, number, number, number)
	local wall, length = sightCast(origin, unit * range, WeaponController.SightParams)
	-- The aim's ray every frame: the nearest body is all it needs.
	if pierce == 0 then
		local body, distance = GunsCore.CastBodies(bodies, origin, unit, length, 0, -1)
		if body == 0 then return origin + unit * length, wall, 0, 0, 0 end
		local isBoss = isBossBody(body)
		return origin + unit * distance, nil, body, if isBoss then body else 0, if isBoss then distance else 0
	end

	local hitCount = GunsCore.CastBodiesAll(bodies, origin, unit, length, 0, castIndices, castDistances)
	local bossBody, bossDistance = 0, 0
	local piercesLeft = pierce
	for hit = 1, hitCount do
		local body, distance = castIndices[hit], castDistances[hit]
		if bossBody == 0 and isBossBody(body) then
			bossBody, bossDistance = body, distance
		end
		if piercesLeft == 0 then return origin + unit * distance, nil, body, bossBody, bossDistance end
		-- The next piece of the same long body is no new body to pierce.
		if hit < hitCount and bodyEntities[castIndices[hit + 1]] ~= bodyEntities[body] then
			piercesLeft -= 1
		end
	end

	return origin + unit * length, wall, 0, bossBody, bossDistance
end

-- Keeps the assist's ASSIST_CHECKS lowest scores, best first.
local function rankCandidate(entity: unknown, point: Vector3, score: number)
	local at = assistCount + 1
	while at > 1 and assistScores[at - 1] > score do
		at -= 1
	end
	if at > Tune.ASSIST_CHECKS then return end

	assistCount = math.min(assistCount + 1, Tune.ASSIST_CHECKS)
	for index = assistCount, at + 1, -1 do
		assistEntities[index] = assistEntities[index - 1]
		assistPoints[index] = assistPoints[index - 1]
		assistScores[index] = assistScores[index - 1]
	end

	assistEntities[at] = entity
	assistPoints[at] = point
	assistScores[at] = score
end

-- One walk over the drawn bodies a frame for both halves of the aim: the bodies along the crosshair's ray, and the
-- assist's best few by screen and by range from `origin`. Returns that ray (eye, unit direction). Bodies are projected
-- here rather than through WorldToViewportPoint, an engine call per body.
--
-- The view is CameraController.AimCFrame, the camera before shake, recoil and bob: through the rendered camera every
-- shake would carry the shot off the crosshair's mark, and a roll would swing a free cursor's.
local function gatherAim(camera: Camera, pointer: Vector2, origin: Vector3, range: number): (Vector3, Vector3)
	local view = CameraController.AimCFrame
	local eye = view.Position
	local look, right, up = view.LookVector, view.RightVector, view.UpVector
	local size = camera.ViewportSize
	local center = size * 0.5
	local focal = center.Y / math.tan(math.rad(camera.FieldOfView) * 0.5)
	local toPointer = (pointer - center) / focal
	local direction = (look + right * toPointer.X - up * toPointer.Y).Unit
	local pull = size.Y * Tune.ASSIST_RADIUS
	local pullSq = pull * pull
	local nearSq = Tune.ASSIST_NEAR * Tune.ASSIST_NEAR
	local rangeSq = range * range
	local aimRangeSq = Tune.AIM_RANGE * Tune.AIM_RANGE

	bodies.Count = 0
	assistCount = 0
	for entity, cframe, aim in DrawnEnemiesQuery do
		local feet = cframe.Position
		addBodyAhead(entity, feet, aim, eye, direction, aimRangeSq)

		local point = feet + Vector3.yAxis * aim.x
		local offset = point - origin
		local distanceSq = vector.dot(offset, offset)
		if distanceSq > rangeSq then continue end
		local fromEye = point - eye
		local depth = vector.dot(fromEye, look)
		if depth <= 0 then continue end
		local screenX = center.X + vector.dot(fromEye, right) / depth * focal
		local screenY = center.Y - vector.dot(fromEye, up) / depth * focal
		if screenX < 0 or screenY < 0 or screenX > size.X or screenY > size.Y then continue end
		local dx, dy = screenX - pointer.X, screenY - pointer.Y
		local pixelsSq = dx * dx + dy * dy
		if pixelsSq > pullSq and distanceSq > nearSq then continue end
		local score = math.sqrt(pixelsSq) / pull * Tune.ASSIST_SCREEN
			+ math.sqrt(distanceSq) / range * Tune.ASSIST_DISTANCE
			- (if entity == heldEntity then Tune.ASSIST_STICKY else 0)
		rankCandidate(entity, point, score)
	end

	addPieced()

	return eye, direction
end

-- The best assist candidate in sight of `origin`, the server's shot origin, which decides the hit (the muzzle can see
-- round a corner the head cannot): its chest and body, or nil.
local function findSighted(origin: Vector3): (Vector3?, unknown)
	for index = 1, assistCount do
		local point = assistPoints[index]
		local offset = point - origin
		local wall, distance = sightCast(origin, offset, WeaponController.SightParams)
		if not wall or distance >= offset.Magnitude - Tune.ASSIST_SIGHT_SLACK then
			return point, assistEntities[index]
		end
	end

	return nil, nil
end

-- Where this frame's shot goes: the first thing under the crosshair, or, over no enemy, the assisted chest. `head` is
-- where the server shoots from.
local function findAim(camera: Camera, pointer: Vector2, gun: TData.TGun, head: Vector3): Vector3
	local eye, direction = gatherAim(camera, pointer, head, gun.Range)
	local target, _, body = castLine(eye, direction, Tune.AIM_RANGE, 0)
	WeaponController.IsOnEnemy = body > 0
	aimBody = body
	if body > 0 then
		heldEntity = bodyEntities[body]
		return target
	end

	local point, entity = findSighted(head)
	heldEntity = entity
	if not point then return target end

	-- Its AimShape, gathered ahead of its pieces.
	for index = 1, bodies.Count do
		if bodyEntities[index] ~= entity then continue end
		aimBody = index
		break
	end

	return point
end

-- Where this frame's shot goes: lined up through the aimed body (GunsCore.LineUp). Only a shot is, not the aim the
-- arms and the body follow every frame.
local function lineUp(gun: TData.TGun, head: Vector3, aimPoint: Vector3): Vector3
	if aimBody == 0 then return aimPoint end

	lineUpShot.Origin = head
	lineUpShot.Target = aimPoint
	lineUpShot.Body = aimBody
	lineUpShot.Pierce = gun.Pierce or 0
	lineUpShot.Range = gun.Range
	lineUpShot.Pad = gun.HitRadius + GunsCore.Tune.LAG_PAD
	return GunsCore.LineUp(lineUpShot)
end

local function getMuzzle(tool: Tool): Attachment?
	local handle = tool:FindFirstChild("Handle")
	local muzzle = if handle then handle:FindFirstChild("Muzzle") else nil
	return if muzzle and muzzle:IsA("Attachment") then muzzle else nil
end

local function playSound(node: string, position: Vector3, isOwn: boolean)
	local cache = if isOwn then ownSoundPools else soundPools
	local pools = cache[node]
	if not pools then
		pools = SoundsCore.CreateVariantPools(SOUND_GROUP, node, Tune.SOUND_VOICES)
		cache[node] = pools
	end

	SoundsCore.PlayPooledRandom(pools, position)
end

local function flash(muzzle: Attachment, isClose: boolean)
	tracers.Sparks(muzzle.WorldCFrame, isClose)
	local light = flashLights[muzzle]
	if not light then
		light = Instance.new("PointLight")
		light.Color = Tune.MUZZLE_LIGHT_COLOR
		light.Range = Tune.MUZZLE_LIGHT_RANGE
		light.Parent = muzzle
		flashLights[muzzle] = light
		muzzle.Destroying:Once(function()
			flashLights[muzzle] = nil
		end)
	end

	local shown = light :: PointLight
	shown.Brightness = if isClose then Tune.MUZZLE_LIGHT_BRIGHTNESS_CLOSE else Tune.MUZZLE_LIGHT_BRIGHTNESS
	shown.Enabled = true
	flashOffAt[shown] = os.clock() + Tune.MUZZLE_FLASH_TIME
end

-- A gun with an effect kit draws its own muzzle; the rest, or one whose kit is not in the place, the plain flash.
local function muzzleFlash(gun: TData.TGun, muzzle: Attachment, isClose: boolean)
	if gun.Fx and gunFx.Muzzle(gun.Fx, muzzle, isClose) then return end
	flash(muzzle, isClose)
end

-- A pellet going into the boss `entity` (castLine's) at `at`: what its light shows there. The player's own is kept as
-- the boss's contact.
local function bossHitOn(entity: unknown, at: Vector3, damage: number, isOwn: boolean): EnemyImpacts.TBossHit?
	local enemyData = EnemyWorld:get(entity :: any, Components.Data)
	if not enemyData then return nil end

	if isOwn then
		local instanceId = EnemyWorld:get(entity :: any, Components.InstanceId)
		if instanceId then
			bossContacts[instanceId] = at
			bossContactAt[instanceId] = os.clock()
		end
	end

	return { Data = enemyData, Damage = damage, IsOwn = isOwn, At = at }
end

-- The sound, the cycle after it, the shooter's release, and the pellets' tracers from the muzzle at `from`. The pellets
-- are the server's: from the shooter's head (`eye`) toward `target`, each drawn from the muzzle to where it stops.
local function drawShot(
	gun: TData.TGun,
	shooter: Model,
	from: Vector3,
	eye: Vector3,
	target: Vector3,
	seed: number,
	isClose: boolean
)
	local isOwn = shooter == selfCharacter
	playSound(gun.Sound, from, isOwn)
	if gun.CycleSound then
		pendingSounds[#pendingSounds + 1] =
			{ At = os.clock() + Tune.CYCLE_DELAY, Node = gun.CycleSound, Position = from, IsOwn = isOwn }
	end
	local releaseNode = gun.ReleaseSound
	if releaseNode then
		local release = pendingReleases[shooter]
		if not release then
			release = { At = 0, Node = releaseNode, Position = from, IsOwn = isOwn }
			pendingReleases[shooter] = release
		end
		release.At = os.clock() + Tune.RELEASE_DELAY
		release.Node = releaseNode
		release.Position = from
	end

	local toTarget = target - eye
	if toTarget.Magnitude < 0.5 then return end
	local direction = toTarget.Unit
	local pellets = math.min(gun.Pellets, GunsCore.Tune.MAX_PELLETS)
	gatherDrawnBodies(eye, direction, gun.Range)
	GunsCore.PelletDirections(direction, seed, gun.SpreadDeg, pellets, pelletDirections)
	local kit = gun.Fx
	local pierce = gun.Pierce or 0
	local pelletDamage = gun.Damage / gun.Pellets
	for pellet = 1, pellets do
		local unit = pelletDirections[pellet]
		local to, wall, body, bossBody, bossDistance = castLine(eye, unit, gun.Range, pierce)
		local bossHit = if bossBody > 0
			then bossHitOn(bodyEntities[bossBody], eye + unit * bossDistance, pelletDamage, isOwn)
			else nil
		if kit and gunFx.Shot(kit, from, to, wall, body > 0, isClose, bossHit) then continue end
		tracers.Fire(from, to, isClose, bossHit)
	end
end

local function kickOf(gun: TData.TGun): (number, number)
	local kickDeg = GunsCore.KickDeg(gun)
	local poseKick = gun.PoseKick
		or math.clamp(kickDeg / Tune.POSE_KICK_REFERENCE_DEG, Tune.POSE_KICK_MIN, Tune.POSE_KICK_MAX)
	return kickDeg, poseKick
end

local function shakeOf(gun: TData.TGun, kickDeg: number): number
	if gun.Shake then return gun.Shake end
	if kickDeg < Tune.SHAKE_FROM_DEG or gun.FireInterval < Tune.SHAKE_SECONDS then return 0 end
	return math.min(kickDeg * Tune.SHAKE_PER_KICK_DEG, Tune.SHAKE_MAX)
end

-- `target` is where this shot goes (lineUp).
local function shoot(gun: TData.TGun, character: Model, tool: Tool, head: Vector3, target: Vector3)
	ClientNetworkWeapons.Fire.Fire(target)
	shotCount = (shotCount + 1) % 65536
	WeaponController.FiredAt = os.clock()

	local isClose = ViewmodelController.IsActive
	local muzzle = ViewmodelController.GetMuzzle() or getMuzzle(tool)
	local from = if muzzle then muzzle.WorldPosition else head
	drawShot(gun, character, from, head, target, shotCount, isClose)
	if muzzle then muzzleFlash(gun, muzzle, isClose) end

	local kickDeg, poseKick = kickOf(gun)
	local impulse = (Tune.KICK_PEAK_BASE + Tune.KICK_PEAK_PER_DEG * kickDeg) / RECOIL_PEAK_PER_IMPULSE
	CameraController.SetRecoilSpring(Tune.RECOIL_FREQUENCY, Tune.RECOIL_DAMPING, Tune.RECOIL_ROLL)
	CameraController.AddRecoil(impulse, impulse * Tune.KICK_SIDE_SHARE * random:NextNumber(-1, 1))
	-- Never in first person, where the eye is the gun: a shot's shake moved it 0.7 studs on average, several times the
	-- kick itself.
	local shake = if isClose then 0 else shakeOf(gun, kickDeg)
	if shake > 0 then CameraController.Shake(shake, SHAKE_ROUGHNESS, Tune.SHAKE_SECONDS) end

	BodyPoseController.Kick(selfCharacter, poseKick)
	ViewmodelController.Kick(poseKick)
	gunSlide.Kick(tool)
end

-- Holding a gun, the body faces the aim, so walking any way is a strafe or a backpedal (BodyPoseController turns the
-- legs and leans) rather than the body swinging round to each key. With the cursor locked CameraController already
-- faces it; free, this turns it, eased so a cursor flicked across the screen swings the body rather than snapping it.
local function faceAim(root: BasePart, humanoid: Humanoid, target: Vector3, dt: number)
	if CameraController.IsFacingAim then
		isFacingAim = false
		return
	end

	if humanoid.AutoRotate then humanoid.AutoRotate = false end
	isFacingAim = true
	local flat = Vector3.new(target.X - root.Position.X, 0, target.Z - root.Position.Z)
	if flat.Magnitude < Tune.TURN_MIN_DISTANCE then return end

	local look = root.CFrame.LookVector
	local current = math.atan2(-look.X, -look.Z)
	local delta = (math.atan2(-flat.X, -flat.Z) - current + math.pi) % (2 * math.pi) - math.pi
	local maxStep = Tune.TURN_MAX_SPEED * dt
	local turn = math.clamp(delta * (1 - math.exp(-Tune.TURN_RATE * dt)), -maxStep, maxStep)
	root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, current + turn, 0)
end

-- Unarmed, the body goes back to facing where it walks.
local function releaseFacing(humanoid: Humanoid?)
	if not isFacingAim then return end
	isFacingAim = false
	if humanoid and not CameraController.IsFacingAim then humanoid.AutoRotate = true end
end

local function stepEffects(now: number)
	tracers.Step()
	gunFx.Step()
	gunSlide.Step(now)
	for light, offAt in flashOffAt do
		if now < offAt then continue end
		light.Enabled = false
		flashOffAt[light] = nil
	end

	for index = #pendingSounds, 1, -1 do
		local pending = pendingSounds[index]
		if now < pending.At then continue end
		playSound(pending.Node, pending.Position, pending.IsOwn)
		pendingSounds[index] = pendingSounds[#pendingSounds]
		pendingSounds[#pendingSounds] = nil
	end

	for shooter, pending in pendingReleases do
		if now < pending.At then continue end
		playSound(pending.Node, pending.Position, pending.IsOwn)
		pendingReleases[shooter] = nil
	end
end

local function step(dt: number)
	local now = os.clock()
	stepEffects(now)

	local gun = WeaponController.Gun
	local character = selfCharacter
	local tool = if character then character:FindFirstChildOfClass("Tool") else nil
	local root, humanoid = selfRoot, selfHumanoid
	local isArmed = gun ~= nil and tool ~= nil and root ~= nil and humanoid ~= nil and humanoid.Health > 0
	BodyPoseController.IsFirstPerson = ViewmodelController.IsActive
	WeaponController.IsArmed = isArmed
	if not isArmed then
		WeaponController.IsOnEnemy = false
		BodyPoseController.Target = nil
		ViewmodelController.Target = nil
		heldEntity = nil
		aimBody = 0
		releaseFacing(humanoid)
		return
	end

	local head = (root :: BasePart).Position + Vector3.yAxis * GunsCore.Tune.EYE_HEIGHT
	local aimPoint = findAim(Workspace.CurrentCamera, getPointer(), gun :: TData.TGun, head)
	BodyPoseController.Target = aimPoint
	ViewmodelController.Target = aimPoint
	faceAim(root :: BasePart, humanoid :: Humanoid, aimPoint, dt)

	if isTriggerDown and now >= nextShotAt and WeaponController.CanFire() then
		nextShotAt = now + (gun :: TData.TGun).FireInterval / (1 + WeaponController.GetFireRateBonus())
		local shotPoint = lineUp(gun :: TData.TGun, head, aimPoint)
		shoot(gun :: TData.TGun, character :: Model, tool :: Tool, head, shotPoint)
	end
end

local function isTrigger(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2
end

-- A step up the ladder is stamped for WeaponRunController to celebrate. Any other change of gun is a swap, hoisted
-- into the hands; a revive hands back the same gun, which is no swap.
ServerNetworkWeapons.Equipped.On(function(gunId: number, ladderStep: number)
	local previous = WeaponController.Gun
	local isUpgrade = WeaponController.Step > 0 and ladderStep > WeaponController.Step
	WeaponController.Gun = GUNS[gunId]
	WeaponController.Step = ladderStep
	shotCount = 0
	nextShotAt = 0
	if isUpgrade then
		WeaponController.UpgradedAt = os.clock()
		return
	end
	if not previous or previous == WeaponController.Gun then return end

	BodyPoseController.Kick(selfCharacter, Tune.SWAP_POSE_KICK)
	CameraController.SetRecoilSpring(Tune.SWAP_RECOIL_FREQUENCY, Tune.SWAP_RECOIL_DAMPING, Tune.RECOIL_ROLL)
	CameraController.AddRecoil(SWAP_KICK_IMPULSE, 0)
end)

ServerNetworkWeapons.Shot.On(function(characterId: number, target: Vector3, seed: number)
	local entity = CharacterCore.GetCharacterByInstanceId(characterId)
	local model = if entity then World:get(entity, Components.Model) else nil
	local tool = if model then model:FindFirstChildOfClass("Tool") else nil
	local gun = if tool then GunsCore.FromToolName(tool.Name) else nil
	local muzzle = if tool then getMuzzle(tool) else nil
	local root = if entity then World:get(entity, Components.HumanoidRootPart) else nil
	if not gun or not muzzle or not root or model == LocalPlayer.Character then return end

	local eye = root.Position + Vector3.yAxis * GunsCore.Tune.EYE_HEIGHT
	drawShot(gun, model :: Model, muzzle.WorldPosition, eye, target, seed, false)
	muzzleFlash(gun, muzzle, false)
	local _, poseKick = kickOf(gun)
	BodyPoseController.Kick(model, poseKick)
	gunSlide.Kick(tool :: Tool)
end)

WeaponController.OnSelfCharacterAdded = function(character)
	selfCharacter = character
	selfRoot = character.HumanoidRootPart
	selfHumanoid = character.Humanoid
	isFacingAim = false
end :: TCharacterEvents.OnCharacterAdded

WeaponController.OnSelfCharacterRemoving = function()
	isFacingAim = false
	selfCharacter = nil
	selfRoot = nil
	selfHumanoid = nil
	isTriggerDown = false
end :: TCharacterEvents.OnCharacterRemoving

WeaponController.OnStart = function()
	-- The loadout is this game's, not Roblox's backpack bar.
	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, false)
	tracers.Init(Workspace:WaitForChild("Temporal"))

	UserInputService.InputBegan:Connect(function(input: InputObject, isProcessed: boolean)
		if not isProcessed and isTrigger(input) then isTriggerDown = true end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if isTrigger(input) then isTriggerDown = false end
	end)

	-- After CameraController's PreRender, so the aim is the view as shown.
	RunService.PreRender:Connect(step)
end

return Ignis.Register(WeaponController)
