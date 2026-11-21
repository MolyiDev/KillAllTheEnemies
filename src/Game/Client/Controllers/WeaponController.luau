-- The gun in the local player's hands: the trigger, what the crosshair is over (or the aim assist's pick), and everything a shot shows (tracers,
-- the muzzle flash and sparks or the gun's own effect kit through gunFx, the sound, the camera kick, the arms' jolt). It tells the server only where it aimed
-- (Weapons.Fire); hits and damage are WeaponService's, and the enemies' flashes and numbers come from its damage
-- events. Other players' shots arrive as Weapons.Shot and are drawn here the same way. It also asks for the next
-- weapon upgrade (GunsCore.LADDER) and shows it landing in the hands.
local ContextActionService = game:GetService("ContextActionService")
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
local MatchController = require(script.Parent.MatchController)
local TweensController = require(script.Parent.TweensController)
local ViewmodelController = require(script.Parent.ViewmodelController)
local gunFx = require(script.Parent.Parent.Utils.gunFx)
local gunSlide = require(script.Parent.Parent.Utils.gunSlide)
local tracers = require(script.Parent.Parent.Utils.tracers)
local CharacterCore = require(ReplicatedStorage.GlobalShared.Core.CharacterCore)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local GunsCore = require(ReplicatedStorage.GlobalShared.Core.GunsCore)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local EnemiesCore = require(ReplicatedStorage.Shared.Core.EnemiesCore)
local sightCast = require(ReplicatedStorage.Shared.Utils.sightCast)
local Components = require(ReplicatedStorage.GlobalShared.ECS.Components)
local Tags = require(ReplicatedStorage.GlobalShared.ECS.Tags)
local EnemyWorld = require(ReplicatedStorage.GlobalShared.ECS.Worlds.EnemyWorld)
local World = require(ReplicatedStorage.GlobalShared.ECS.Worlds.World)
local ESoundsIds = require(ReplicatedStorage.Types.Enums.Sounds.ESoundsIds)
local TCharacterEvents = require(ReplicatedStorage.Types.Events.TCharacterEvents)
local TData = require(ReplicatedStorage.Types.TData)

local ServerNetworkWeapons = Network.Server.Weapons
local ClientNetworkWeapons = Network.Client.Weapons

-- Called per body in the walks below, so hoisted out of their modules.
local getAimShape = EnemiesCore.AimShape
local addBody = GunsCore.AddBody

local GUNS = DataCore.Guns.ById
local SOUND_GROUP = "Guns"
-- Rendered bodies only: a parked one sits far away and is never under the crosshair.
local DrawnEnemiesQuery = EnemyWorld:query(Components.CFrame, Components.Data):with(Tags.Enemy):cached()

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
	-- A bought upgrade landing in the hands: the view breathes out this many degrees and back over this long, the
	-- arms hoist the new gun with this many shots' jolt, and the camera kicks up this many studs at its peak (past
	-- any shotgun's), a share of it sideways, on a softer spring than a shot's so it settles with the breath.
	UPGRADE_FOV_PUNCH = 7,
	UPGRADE_FOV_RETURN = 0.55,
	UPGRADE_POSE_KICK = 2.8,
	UPGRADE_KICK_PEAK = 0.45,
	UPGRADE_KICK_SIDE_SHARE = 0.3,
	UPGRADE_RECOIL_FREQUENCY = 14,
	UPGRADE_RECOIL_DAMPING = 0.55,
})

-- A recoil spring's peak displacement per unit of impulse, so a kick is asked for in studs:
-- peak = v0 / wd * exp(-z / sqrt(1 - z^2) * atan2(sqrt(1 - z^2), z)), wd = w * sqrt(1 - z^2).
local function peakPerImpulse(frequency: number, damping: number): number
	local root = math.sqrt(1 - damping * damping)
	return math.exp(-damping / root * math.atan2(root, damping)) / (frequency * root)
end

local RECOIL_PEAK_PER_IMPULSE = peakPerImpulse(Tune.RECOIL_FREQUENCY, Tune.RECOIL_DAMPING)
local UPGRADE_KICK_IMPULSE = Tune.UPGRADE_KICK_PEAK
	/ peakPerImpulse(Tune.UPGRADE_RECOIL_FREQUENCY, Tune.UPGRADE_RECOIL_DAMPING)
-- CameraController.Shake makes 4 swings every `roughness` seconds.
local SHAKE_ROUGHNESS = 4 * Tune.SHAKE_SECONDS / Tune.SHAKE_SWINGS

type TPendingSound = { At: number, Node: string, Position: Vector3, IsOwn: boolean }

local WeaponController = {}

WeaponController.UPGRADE_KEY = Enum.KeyCode.V

-- The gun the server last handed this player, or nil.
WeaponController.Gun = nil :: TData.TGun?
-- The step of GunsCore.LADDER the server has this player on (0 before the first gun).
WeaponController.Step = 0
-- os.clock of the last upgrade the server confirmed, the last one asked for, and the last one the purse refused.
WeaponController.UpgradedAt = -math.huge
WeaponController.UpgradeAskedAt = -math.huge
WeaponController.UpgradeDeniedAt = -math.huge

local LocalPlayer = Players.LocalPlayer
local LADDER = GunsCore.LADDER

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
local pelletDirections: { Vector3 } = {}
-- The enemy the aim was on last frame, under the crosshair or assisted, and the assist's best few, best first.
local heldEntity: unknown = nil
local assistCount = 0
local assistEntities: { unknown } = table.create(Tune.ASSIST_CHECKS)
local assistPoints: { Vector3 } = table.create(Tune.ASSIST_CHECKS)
local assistScores: { number } = table.create(Tune.ASSIST_CHECKS)

-- Asks for the next step of the ladder. Refused here, for the HUD to show it, when there is none, the body is down or
-- the Gold is short; the server checks them all again.
function WeaponController.Upgrade()
	local offer = LADDER[WeaponController.Step + 1]
	local humanoid = selfHumanoid
	local isStanding = WeaponController.Gun ~= nil and humanoid ~= nil and humanoid.Health > 0
	local now = os.clock()
	if not offer or not isStanding or MatchController.Gold < offer.Price then
		WeaponController.UpgradeDeniedAt = now
		return
	end

	WeaponController.UpgradeAskedAt = now
	ClientNetworkWeapons.Upgrade.Fire()
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

-- The drawn bodies a shot from `origin` can reach, gathered once a shot.
local function gatherDrawnBodies(origin: Vector3, direction: Vector3, range: number)
	local rangeSq = range * range

	bodies.Count = 0
	for entity, cframe, enemyData in DrawnEnemiesQuery do
		addBodyAhead(entity, cframe.Position, getAimShape(enemyData), origin, direction, rangeSq)
	end
end

-- Where a ray stops: in one of the gathered bodies (its index, 0 for none), on the arena (with what it hit), or at its
-- full length. It goes through `pierce` bodies first (TGun.Pierce), so it stops in the one after them, or carries on
-- to the arena when there are no more in its way.
local function castLine(
	origin: Vector3,
	unit: Vector3,
	range: number,
	pierce: number
): (Vector3, RaycastResult?, number)
	local wall, length = sightCast(origin, unit * range)
	local body, distance = GunsCore.CastBodies(bodies, origin, unit, length, 0, -1)
	for _ = 1, pierce do
		if body == 0 then break end
		body, distance = GunsCore.CastBodies(bodies, origin, unit, length, 0, distance)
	end
	if body > 0 then return origin + unit * distance, nil, body end

	return origin + unit * length, wall, 0
end

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
	for entity, cframe, enemyData in DrawnEnemiesQuery do
		local feet = cframe.Position
		local aim = getAimShape(enemyData)
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

	return eye, direction
end

-- The best assist candidate in sight of `origin`, the server's shot origin, which decides the hit (the muzzle can see
-- round a corner the head cannot): its chest and body, or nil.
local function findSighted(origin: Vector3): (Vector3?, unknown)
	for index = 1, assistCount do
		local point = assistPoints[index]
		local offset = point - origin
		local wall, distance = sightCast(origin, offset)
		if not wall or distance >= offset.Magnitude - Tune.ASSIST_SIGHT_SLACK then
			return point, assistEntities[index]
		end
	end

	return nil, nil
end

-- Where this frame's shot goes: the first thing under the crosshair, or, over no enemy, the assisted chest.
local function findAim(camera: Camera, pointer: Vector2, gun: TData.TGun, root: BasePart): Vector3
	local origin = root.Position + Vector3.yAxis * GunsCore.Tune.EYE_HEIGHT
	local eye, direction = gatherAim(camera, pointer, origin, gun.Range)
	local target, _, body = castLine(eye, direction, Tune.AIM_RANGE, 0)
	if body > 0 then
		heldEntity = bodyEntities[body]
		return target
	end

	local point, entity = findSighted(origin)
	heldEntity = entity
	return point or target
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

-- The sound, the cycle after it, the shooter's release, and the pellets' tracers from `from` toward `target`.
local function drawShot(gun: TData.TGun, shooter: Model, from: Vector3, target: Vector3, seed: number, isClose: boolean)
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

	local toTarget = target - from
	if toTarget.Magnitude < 0.5 then return end
	local direction = toTarget.Unit
	local pellets = math.min(gun.Pellets, GunsCore.Tune.MAX_PELLETS)
	gatherDrawnBodies(from, direction, gun.Range)
	GunsCore.PelletDirections(direction, seed, gun.SpreadDeg, pellets, pelletDirections)
	local kit = gun.Fx
	local pierce = gun.Pierce or 0
	for pellet = 1, pellets do
		local to, wall, body = castLine(from, pelletDirections[pellet], gun.Range, pierce)
		local normal = if wall then wall.Normal else nil
		local surface = if wall and kit then gunFx.SurfaceColor(wall) else nil
		if kit and gunFx.Shot(kit, from, to, normal, surface, body > 0, isClose) then continue end
		tracers.Fire(from, to, isClose)
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

-- `target` is this frame's aim (findAim).
local function shoot(gun: TData.TGun, character: Model, tool: Tool, target: Vector3)
	ClientNetworkWeapons.Fire.Fire(target)
	shotCount = (shotCount + 1) % 65536

	local isClose = ViewmodelController.IsActive
	local muzzle = ViewmodelController.GetMuzzle() or getMuzzle(tool)
	local from = if muzzle then muzzle.WorldPosition elseif selfRoot then selfRoot.Position else target
	drawShot(gun, character, from, target, shotCount, isClose)
	if muzzle then muzzleFlash(gun, muzzle, isClose) end

	local kickDeg, poseKick = kickOf(gun)
	local impulse = (Tune.KICK_PEAK_BASE + Tune.KICK_PEAK_PER_DEG * kickDeg) / RECOIL_PEAK_PER_IMPULSE
	CameraController.SetRecoilSpring(Tune.RECOIL_FREQUENCY, Tune.RECOIL_DAMPING, Tune.RECOIL_ROLL)
	CameraController.AddRecoil(impulse, impulse * Tune.KICK_SIDE_SHARE * random:NextNumber(-1, 1))
	local shake = shakeOf(gun, kickDeg)
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
	if not isArmed then
		BodyPoseController.Target = nil
		ViewmodelController.Target = nil
		heldEntity = nil
		releaseFacing(humanoid)
		return
	end

	local aimPoint = findAim(Workspace.CurrentCamera, getPointer(), gun :: TData.TGun, root :: BasePart)
	BodyPoseController.Target = aimPoint
	ViewmodelController.Target = aimPoint
	faceAim(root :: BasePart, humanoid :: Humanoid, aimPoint, dt)

	if isTriggerDown and now >= nextShotAt then
		nextShotAt = now + (gun :: TData.TGun).FireInterval
		shoot(gun :: TData.TGun, character :: Model, tool :: Tool, aimPoint)
	end
end

local function isTrigger(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2
end

-- A step up the ladder is the one equip that celebrates: a revive hands back the same step, a new run the first.
ServerNetworkWeapons.Equipped.On(function(gunId: number, ladderStep: number)
	local isUpgrade = WeaponController.Step > 0 and ladderStep > WeaponController.Step
	WeaponController.Gun = GUNS[gunId]
	WeaponController.Step = ladderStep
	shotCount = 0
	nextShotAt = 0
	if not isUpgrade then return end

	WeaponController.UpgradedAt = os.clock()
	SoundsCore.PlayUISound(ESoundsIds.WeaponUpgrade)
	ViewmodelController.Flourish()
	BodyPoseController.Kick(selfCharacter, Tune.UPGRADE_POSE_KICK)
	TweensController.PunchFov(Tune.UPGRADE_FOV_PUNCH, Tune.UPGRADE_FOV_RETURN)
	CameraController.SetRecoilSpring(Tune.UPGRADE_RECOIL_FREQUENCY, Tune.UPGRADE_RECOIL_DAMPING, Tune.RECOIL_ROLL)
	local side = UPGRADE_KICK_IMPULSE * Tune.UPGRADE_KICK_SIDE_SHARE * random:NextNumber(-1, 1)
	CameraController.AddRecoil(UPGRADE_KICK_IMPULSE, side)
end)

ServerNetworkWeapons.Shot.On(function(characterId: number, target: Vector3, seed: number)
	local entity = CharacterCore.GetCharacterByInstanceId(characterId)
	local model = if entity then World:get(entity, Components.Model) else nil
	local tool = if model then model:FindFirstChildOfClass("Tool") else nil
	local gun = if tool then GunsCore.FromToolName(tool.Name) else nil
	local muzzle = if tool then getMuzzle(tool) else nil
	if not gun or not muzzle or model == LocalPlayer.Character then return end

	drawShot(gun, model :: Model, muzzle.WorldPosition, target, seed, false)
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

	ContextActionService:BindAction("UpgradeWeapon", function(_, state)
		if state == Enum.UserInputState.Begin then WeaponController.Upgrade() end
		return Enum.ContextActionResult.Sink
	end, false, WeaponController.UPGRADE_KEY)

	-- After CameraController's PreRender, so the aim is the view as shown.
	RunService.PreRender:Connect(step)
end

return Ignis.Register(WeaponController)
