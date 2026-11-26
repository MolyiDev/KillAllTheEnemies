-- Draws the crowd: a row for each enemy this client has been shown (AOIService), a rig when it can afford one, moved
-- toward the latest packet every frame.
--
-- NEVER ASK A RIG WHERE IT IS: it stays anchored at the origin and Root.Transform carries the world CFrame
-- (TData.TEnemyModel), so every positional question goes through EnemiesCore's hash.
--
-- EVERY BODY OWNS ITS HIT-FLASH HIGHLIGHT, cloned with it and never re-aimed: re-aiming one costs +16 ms
-- (performance/13, 14). So rigs are destroyed with their enemy, never pooled, since a pooled rig would hold one of the
-- 255 slots while it waited. Reserves hold clones that were never parented, whose Highlights take no slot.
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local jecs = require(ReplicatedStorage.Packages.jecs)
local Network = require(StarterPlayer.StarterPlayerScripts.GlobalClient.Network)
local MatchController = require(script.Parent.MatchController)
local EnemyImpacts = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Utils.enemyImpacts)
local targetHits = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Utils.targetHits)
local InertialBlend = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Utils.inertialBlend)
local Ragdoll = require(script.Parent.Parent.Utils.ragdoll)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local BossesCore = require(ReplicatedStorage.Shared.Core.BossesCore)
local EnemiesCore = require(ReplicatedStorage.Shared.Core.EnemiesCore)
local RoundCore = require(ReplicatedStorage.Shared.Core.RoundCore)
local TimeCore = require(ReplicatedStorage.Shared.Core.TimeCore)
local EnemyPacker = require(ReplicatedStorage.Shared.Packers.EnemyPacker)
local Components = require(ReplicatedStorage.GlobalShared.ECS.Components)
local EnemyWorldRef = require(ReplicatedStorage.GlobalShared.ECS.References.EnemyWorldRef)
local WorldRef = require(ReplicatedStorage.GlobalShared.ECS.References.WorldRef)
local Tags = require(ReplicatedStorage.GlobalShared.ECS.Tags)
local EnemyWorld = require(ReplicatedStorage.GlobalShared.ECS.Worlds.EnemyWorld)
local World = require(ReplicatedStorage.GlobalShared.ECS.Worlds.World)
local TData = require(ReplicatedStorage.Types.TData)

local ServerNetworkEnemies = Network.Server.Enemies

local EnemiesFolder = Workspace:WaitForChild("Enemies")
local ENEMIES = DataCore.Enemies.ById

local RiggedQuery = EnemyWorld:query(Components.CFrame, Components.Bone, Components.InstanceId, Components.Data)
	:cached()
-- Every body with a model, for reaching its clips (modelTracks).
local ModelQuery = EnemyWorld:query(Components.InstanceId, Components.Model):cached()

local exp = math.exp
local sin = math.sin
local cos = math.cos
local rad = math.rad
local random = math.random

local FAR_AWAY_CFRAME = CFrame.new(2 ^ 24, 2 ^ 24, 2 ^ 24)
local FAR_AWAY_X = FAR_AWAY_CFRAME.Position.X
local V3_YAXIS = Vector3.yAxis
local TAU = 2 * math.pi
-- Past this the body snaps instead of gliding there (a first sighting after a long park, a fall).
local SNAP_DISTANCE_SQ = 25 * 25
-- No packet for this long (EnemyClock): the server's cull dropped it, so park it rather than freeze it in place.
local STALE_TIME = 1
local RENDER_DISTANCE = 400
local RENDER_DISTANCE_SQ = RENDER_DISTANCE * RENDER_DISTANCE

local Tune = table.freeze({
	-- Bodies kept ready per type. Spawns pour at RoundCore.SPAWNS_PER_SECOND (20), well under what the refill
	-- builds, so this only covers the first moments of a round.
	RESERVE_TARGET = 16,
	-- Clone() calls a frame, whatever for (~0.8 ms each on an R6 zombie rig).
	MAX_CLONES_PER_FRAME = 5,
	-- How much of that the reserve refill may take: it is work ahead of a round, never urgent.
	MAX_RESERVE_CLONES_PER_FRAME = 2,
	-- Bodies handed a rig a frame. One off the reserve is a parent and two loaded tracks, so this rarely binds.
	MAX_RIGS_PER_FRAME = 8,
	-- Bodies ragdolling or sinking at once. Past it a kill vanishes on the spot.
	MAX_CORPSES = 40,
	-- The killing blow's shove, studs/s at the shoulders; the whole body gets BASE_SHARE of it. Spread is the
	-- random turn off straight-away-from-the-killer, so a crowd killed together does not fall in one direction.
	KNOCK_SPEED = 12,
	KNOCK_BASE_SHARE = 0.2,
	KNOCK_SPREAD_DEG = 25,
	-- Under Workspace.Gravity a 5-stud body is down in a fifth of a second, too quick to read as a fall; at 0.6 it
	-- lands in 0.3-0.45 s (tools/lune/ragdoll.luau).
	RAGDOLL_GRAVITY_SCALE = 0.6,
	-- Lying still before it sinks, then how fast it goes under, and how far past its highest point.
	SINK_DELAY = 0.4,
	SINK_SPEED = 3,
	SINK_MARGIN = 0.3,
	-- The floor under a falling body is re-measured each time it slides this far from where it was last measured.
	FLOOR_REPROBE_DISTANCE = 1.5,
	FLOOR_PROBE_UP = 4,
	FLOOR_PROBE_DOWN = 80,
	LOCOMOTION_FADE = 0.2,
	ATTACK_FADE = 0.1,
	-- A clip switch asked with a fade is cut and blended from the pose on screen over this long (inertialBlend); a
	-- boss is big and held in view, so its body settles over longer.
	BLEND = 0.2,
	BOSS_BLEND = 0.35,
	-- A fresh spawn drops in: drawn this high over its feet, settling and fading in over this long (enemy time).
	ARRIVAL_HEIGHT = 6,
	ARRIVAL_TIME = 0.5,
	-- The hit flash: white, gone in this long.
	FLASH_TIME = 0.12,
	FLASH_COLOR = Color3.new(1, 1, 1),
	-- A hit's jolt: a lean away from the shooter, pivoted on the feet, peaking at 15 deg and 0.5 studs of push 0.05 s
	-- in and spent at 2*pi / FLINCH_SPEED (0.26 s), with a sideways shake decaying over FLINCH_SHAKE_TIME (3 swings).
	-- A hit within FLINCH_RETRIGGER of the last does not restart it, or a fast gun would pin the body at the start.
	FLINCH_ANGLE = rad(24),
	FLINCH_PUSH = 0.8,
	FLINCH_SPEED = 24,
	FLINCH_DAMPER = 0.32,
	FLINCH_SHAKE_TIME = 0.22,
	FLINCH_SHAKE_SPEED = 95,
	FLINCH_SHAKE_STUDS = 0.45,
	FLINCH_RETRIGGER = 0.22,
	-- A boss's hit flash only tints it: a body that size flashing white on every bullet strobes over its clips and
	-- reads as weightless, as a flinch does (a boss takes none). Its blows show where they land
	-- (EnemyImpacts.EmitBossHit); a full flash is kept for its moments (Flash).
	BOSS_FLASH_TRANSPARENCY = 0.8,
	-- The engine renders this many Highlights in the whole DataModel (EnemiesCore.MAX_ALIVE).
	MAX_HIGHLIGHTS = 255,
	-- The last few of a wave (RoundCore.LAST_SHOWN) are outlined through walls on their own Flash. Magenta, measured
	-- against every colour the schoolyard is built from at half coverage: CIELAB difference at least 35 (its violet
	-- flowers), 80 at the median, where white vanishes on the lines and black on the asphalt.
	LAST_OUTLINE_COLOR = Color3.fromRGB(255, 0, 255),
	LAST_OUTLINE_TRANSPARENCY = 0.5,
	-- A stiff body (SetStiff) keeps this much of its fill showing under its colour between hits.
	STIFF_TRANSPARENCY = 0.35,
	-- A body's hit sound plays at most once in this long; the flash still shows every hit.
	HIT_SOUND_DEBOUNCE = 0.5,
	-- The crowd's groan: one at a time, from the first visible body the loop reaches, every MIN to MAX seconds of
	-- enemy time. One shared timer, so a crowd mutters at the same rate at five bodies or two hundred.
	IDLE_GROAN_MIN = 1.6,
	IDLE_GROAN_MAX = 3.4,
	-- A wind-up snarl at most this often across the crowd: a dozen in reach is a dozen swings a second, and one clear
	-- snarl says the crowd is winding up where ten overlapping say nothing.
	ATTACK_SNARL_GAP = 0.25,
	-- The clips follow an ease of the clock in steps this big (rescaleClips).
	CLIP_RESCALE_STEP = 0.05,
	-- A body killed into its Death clip: frozen this close to the clip's end (a track that runs out drops its pose),
	-- lying there this long, then sinking at SINK_SPEED.
	DEATH_HOLD_MARGIN = 0.05,
	DEATH_LINGER = 3,
	DEATH_CORPSES = 4,
	-- A moving clip of its own fades in over this.
	CLIP_FADE = 0.15,
})

local IDLE_PRIORITY = Enum.AnimationPriority.Idle
local WALK_PRIORITY = Enum.AnimationPriority.Movement
local ATTACK_PRIORITY = Enum.AnimationPriority.Action

-- The R6 contract's limbs, in the order the ragdoll's limb ends are numbered (tools/rig/r6_zombie.py).
local LIMB_NAMES = table.freeze({ "ArmLeft", "ArmRight", "LegLeft", "LegRight" })
local LIMB_IS_LEG = table.freeze({ false, false, true, true })
-- The R6 zombie's proportions (tools/rig/r6_zombie.py): legs 2 tall, torso 2, at the rig's size. The size is read
-- off the bones (hips over feet), not the extents, which grow with whatever hair or headgear a rig wears.
local R6_HIPS_HEIGHT = 2

local EnemiesController = {}

-- Enemies this client holds a row for (AOIService shows it those near its player), for the HUD.
EnemiesController.Count = 0
-- The bosses among them, by instance id (BossController follows each). Read only.
EnemiesController.Bosses = {} :: { [number]: TData.TEnemy }

-- (instanceId, attackerCharacterId, damage, worldPosition, halfWidth?): every surviving hit, for numbers and sounds.
-- The shared targetHits signals, so the crosshair and the damage numbers, which serve the lobby's range too, hear them.
EnemiesController.OnEnemyDamaged = targetHits.Damaged
-- (instanceId, killerCharacterId, damage, isOverkill, worldPosition, halfWidth?): the position is the chest, as a
-- hit's is.
EnemiesController.OnEnemyKilled = targetHits.Killed

-- ============================== Per-id state ==============================
-- Plain maps keyed by instance id: the render loop reads several per body per frame and a hash read is cheaper
-- than an ECS get. Every one is cleared in forgetId.
local positions: { [number]: Vector3 } = {}
local yaws: { [number]: number } = {}
local moving: { [number]: boolean } = {}
local lastUpdate: { [number]: number } = {}
-- The target transform as last built, and the packet it was built from.
local targetCFrames: { [number]: CFrame } = {}
local targetBuiltFrom: { [number]: Vector3 } = {}
local targetBuiltYaw: { [number]: number } = {}
-- Lua-side animation state, so the loop never asks a track IsPlaying.
local isWalking: { [number]: boolean } = {}
local isShown: { [number]: boolean } = {}
-- Live hit flashes, only bodies hit in the last FLASH_TIME: a handful even in a full crowd.
local flashTarget: { [number]: Highlight } = {}
local flashEndsAt: { [number]: number } = {}
-- The fill each live flash was struck at, 0 for a full one.
local flashFrom: { [number]: number } = {}
-- Bodies still reeling from a hit (Tune.FLINCH_*): os.clock it began, and the flat direction away from the shooter.
local flinchStartedAt: { [number]: number } = {}
local flinchAway: { [number]: Vector3 } = {}
-- EnemyClock when each arriving body has landed. A handful: only spawns of the last ARRIVAL_TIME.
local arrivalEndsAt: { [number]: number } = {}
-- os.clock of each body's last hit sound (Tune.HIT_SOUND_DEBOUNCE).
local hitSoundAt: { [number]: number } = {}
-- Bodies held stiff (SetStiff): the yaw each was caught at, which it keeps until it is let go.
local stiffYaws: { [number]: number } = {}
-- Bosses walking at other than their own speed (SetWalkPace): that share of it.
local walkPaces: { [number]: number } = {}
-- Bodies lit in their own glow between hits (TEnemy.Glow).
local glowing: { [number]: boolean } = {}
-- Bodies drawn where their driver says (Drive): a function of the enemy clock giving the ground CFrame, nil once it
-- lets go.
local drivers: { [number]: (enemyClock: number) -> CFrame? } = {}
local nextIdleGroan = 0
local nextAttackSnarl = 0
-- The volley being sounded (beginVolley).
local volleyCameraPosition = Vector3.zero
local volleyNearestDistSq = math.huge
-- The player's own character entity, to tell their blows from a teammate's.
local selfEntity: any = nil

-- ============================== Rig state ==============================
-- A rig as this client builds it: the uploaded model plus the hit-flash Highlight getTemplate gives every template.
type TRig = TData.TEnemyModel & { Flash: Highlight }

local templates: { [number]: TData.TEnemyModel } = {}
local reserves: { [number]: { TData.TEnemyModel } } = {}
local groundLifts: { [number]: CFrame } = {}
local missingModelWarned: { [number]: boolean } = {}
-- Each rigged type's clips, filled with its template.
local clipsById: { [number]: EnemiesCore.TClips } = {}
-- Tracks loaded per live rig. A rig is unique per spawn, so its entry goes when it is destroyed.
local modelTracks: { [Model]: { [Animation]: AnimationTrack } } = {}
-- Every track currently playing, so a freeze or a park stops exactly those.
local playingTracks: { [AnimationTrack]: boolean } = {}
-- The speed a track was started at (an attack clip is stretched to its wind-up), so a thaw restores it.
local trackSpeeds: { [AnimationTrack]: number } = {}
-- Tracks that play at their own speed whatever the match's clock (PlayClip's IsUnscaled).
local unscaledTracks: { [AnimationTrack]: boolean } = {}
-- The rate every clip plays at over its own speed: the match's clock times the enemies' (rescaleClips).
local clipScale = 1
-- The rig each track is on, each rig's inertial blend, the blends with work this frame (a boss's always: it keeps the
-- speed its pose moves at), the ones started by an unscaled clip (they ease at real time), and the bosses' rigs.
local trackModels: { [AnimationTrack]: TData.TEnemyModel } = {}
local blends: { [Model]: InertialBlend.TInertialBlend } = {}
local steppingBlends: { [InertialBlend.TInertialBlend]: boolean } = {}
local unscaledBlends: { [InertialBlend.TInertialBlend]: boolean } = {}
local bossRigs: { [Model]: boolean } = {}
-- Each rigged body's Flash, so a hit reaches it with one read (a name lookup on the model costs 10x: measured
-- 2026-11-20, 8 ns against 82 ns for model.Flash and 103 ns for FindFirstChild).
local flashHighlights: { [number]: Highlight } = {}
-- Parented Highlights: living rigs plus corpses still flashing. Kept under MAX_HIGHLIGHTS.
local highlightCount = 0
-- Every living rig is outlined: the wave is down to its last few.
local isMarkingLast = false

local rigQueue: { number } = {}
local rigQueueHead = 1
local rigQueueTail = 0

-- A rig's rest pose as the ragdoll needs it, measured once per template. Rest frames are the bones' world CFrames
-- with every Transform at identity, so a bone's Transform can be solved from where the ragdoll puts its segment.
type TRagdollRig = {
	shape: Ragdoll.TRig,
	scale: number,
	rootRest: CFrame,
	rootRestInverse: CFrame,
	torsoRest: CFrame,
	torsoRestInverse: CFrame,
	limbRest: { CFrame },
	limbRestInverse: { CFrame },
}
-- nil when the rig has not got the R6 bones: such a body vanishes when killed.
local ragdollRigs: { [number]: TRagdollRig | false } = {}

type TCorpse = {
	model: TData.TEnemyModel,
	rig: TRagdollRig,
	root: Bone,
	limbs: { Bone },
	body: Ragdoll.TBody,
	probedAt: Vector3,
	-- Set when it lands: the torso frame it lies in, how long it lies still, how far it has sunk and must sink.
	restingFrame: CFrame,
	sinkDelay: number,
	sunk: number,
	sinkDepth: number,
	highlight: Highlight?,
	flashRemaining: number,
}
local CORPSE_STUB: TCorpse = {
	model = nil :: any,
	rig = nil :: any,
	root = nil :: any,
	limbs = nil :: any,
	body = nil :: any,
	probedAt = Vector3.zero,
	restingFrame = CFrame.identity,
	sinkDelay = 0,
	sunk = 0,
	sinkDepth = -1,
	highlight = nil,
	flashRemaining = 0,
}
local corpses: { TCorpse } = {}

-- A body killed into its Death clip (EnemiesCore.TClips.Death): it falls as the clip has it, lies on its last frame,
-- then sinks. Root holds the ground frame it died in.
type TClipCorpse = {
	model: TData.TEnemyModel,
	root: Bone,
	track: AnimationTrack,
	frame: CFrame,
	-- The rate its clip runs at: the game clock's, which a pause (an upgrade pick) stops.
	rate: number,
	isHeld: boolean,
	lingers: number,
	sunk: number,
	sinkDepth: number,
	highlight: Highlight?,
	flashRemaining: number,
}
local clipCorpses: { TClipCorpse } = {}

local floorParams = RaycastParams.new()
floorParams.FilterType = Enum.RaycastFilterType.Include
local floorArena: Instance? = nil

-- ============================== Render state ==============================
local cameraX, cameraY, cameraZ = 0, 0, 0
local lookX, lookY, lookZ = 0, 0, 1
local thresholdSq = 0
local apexShiftPerRadius = 1
-- Each type's EnemiesCore.ViewSphere, read per body per frame.
local viewSpheresById: { [number]: vector } = {}

-- The rendered ground CFrame of an enemy, or nil while it is parked or has no rig. For effects that sit on a body.
function EnemiesController.GetCFrame(instanceId: number): CFrame?
	local entity = EnemyWorldRef:Search(instanceId)
	local cframe = if entity then EnemyWorld:get(entity, Components.CFrame) else nil
	if not cframe or cframe.Position.X == FAR_AWAY_X then return nil end
	return cframe
end

-- Holds a body stiff in `color` (set in foam: its clips stop where they are, it keeps the way it faces, its own
-- Highlight is tinted and stays lit, and a killing blow breaks it apart instead of dropping it), or lets it go with
-- nil. The tint is the body's own Highlight: nothing here may add one (EnemiesCore.MAX_ALIVE).
function EnemiesController.SetStiff(instanceId: number, color: Color3?)
	local entity = EnemyWorldRef:Search(instanceId)
	if not entity then return end
	local isStiff = color ~= nil
	if isStiff == (stiffYaws[instanceId] ~= nil) then return end
	stiffYaws[instanceId] = if isStiff then yaws[instanceId] or 0 else nil

	local highlight = flashHighlights[instanceId]
	if highlight then
		highlight.FillColor = color or Tune.FLASH_COLOR
		if not flashTarget[instanceId] then
			highlight.FillTransparency = if isStiff then Tune.STIFF_TRANSPARENCY else 1
		end
	end

	local tracks = modelTracks[EnemyWorld:get(entity, Components.Model) :: any]
	if not tracks then return end
	local scale = if isStiff then 0 else clipScale
	for _, track in tracks do
		if playingTracks[track] then track:AdjustSpeed(scale * (trackSpeeds[track] or 1)) end
	end
end

-- Takes a body's Highlight off while it is out of sight under the floor (a boss's dive), or puts it back: the last
-- few's outline is drawn through everything and would show it down there.
function EnemiesController.SetBuried(instanceId: number, isBuried: boolean)
	local highlight = flashHighlights[instanceId]
	if highlight then highlight.Enabled = not isBuried end
end

-- A boss's walk clip speed: at the clip's own ground speed times its pace (SetWalkPace), so its planted feet hold.
local function bossWalkSpeed(instanceId: number, enemyData: TData.TEnemy, boss: TData.TEnemyBoss): number
	return enemyData.BaseMovementSpeed / boss.WalkSpeed * (walkPaces[instanceId] or 1)
end

-- Plays a boss's walk at `pace` times its own speed (the server slows its walk). A boss is never stiff.
function EnemiesController.SetWalkPace(instanceId: number, pace: number)
	walkPaces[instanceId] = if pace == 1 then nil else pace
	local entity = EnemyWorldRef:Search(instanceId)
	local enemyData = if entity then EnemyWorld:get(entity, Components.Data) else nil
	local boss = if enemyData then enemyData.Boss else nil
	local walkTrack = EnemiesController.GetTrack(instanceId, "Walk")
	if not enemyData or not boss or not walkTrack or not playingTracks[walkTrack] then return end
	local speed = bossWalkSpeed(instanceId, enemyData, boss)
	trackSpeeds[walkTrack] = speed
	walkTrack:AdjustSpeed(speed * clipScale)
end

-- Draws a body where `driver` says each frame instead of chasing its packets: given the enemy clock, it returns the
-- ground CFrame, or nil to let go (the body then glides on from there). nil takes a driver off. For a boss's runs,
-- turns and dive (BossController), which the server moves faster than its packets can show.
function EnemiesController.Drive(instanceId: number, driver: ((enemyClock: number) -> CFrame?)?)
	-- Let go, it keeps facing the way it was driven until a packet turns it: a held match (an intro) or a dive streams
	-- none, so the yaw it has is stale or missing, and it would swing round to it.
	if not driver and drivers[instanceId] then
		local cframe = EnemiesController.GetCFrame(instanceId)
		if cframe then yaws[instanceId] = math.atan2(cframe.ZVector.X, cframe.ZVector.Z) end
	end
	drivers[instanceId] = driver
end

export type TClipOptions = {
	Speed: number?,
	Fade: number?,
	IsLooped: boolean?,
	Priority: Enum.AnimationPriority?,
	-- At its own speed whatever the match's clock: an intro, played while the match is held for it.
	IsUnscaled: boolean?,
}

-- The rig of a body this client draws, or nil (no rig yet, or gone).
function EnemiesController.GetModel(instanceId: number): TData.TEnemyModel?
	local entity = EnemyWorldRef:Search(instanceId)
	return if entity then EnemyWorld:get(entity, Components.Model) :: TData.TEnemyModel? else nil
end

-- ============================== Rigs ==============================
local function reserveFor(dataId: number): { TData.TEnemyModel }
	local reserve = reserves[dataId]
	if not reserve then
		reserve = {}
		reserves[dataId] = reserve
	end

	return reserve
end

-- The rest pose's shape off the rig's own bones: limb joints exactly where the rig turns them, the torso box and
-- head at R6's proportions for the rig's height.
local function buildRagdollRig(template: TData.TEnemyModel): TRagdollRig?
	local part = template.PrimaryPart
	local root = part.Root
	local torso = root:FindFirstChild("Torso")
	if not torso or not torso:IsA("Bone") then return nil end

	local rootRest = part.CFrame * root.CFrame
	local torsoRest = rootRest * torso.CFrame
	local feet = rootRest.Position
	local scale = (torsoRest.Position.Y - feet.Y) / R6_HIPS_HEIGHT
	local torsoBottomY = feet.Y + 2 * scale
	-- The top of the rig (hair included) over the torso's centre: how far it has to sink to be gone.
	local headTop = template:GetExtentsSize().Y - 3 * scale

	local shape = Ragdoll.NewRig(feet + Vector3.new(0, 3 * scale, 0), Vector3.new(1, 1, 0.5) * scale, headTop)
	local limbRest, limbRestInverse = table.create(4), table.create(4)

	for i, name in LIMB_NAMES do
		local bone = torso:FindFirstChild(name)
		if not bone or not bone:IsA("Bone") then return nil end
		local rest = torsoRest * bone.CFrame
		limbRest[i] = rest
		limbRestInverse[i] = rest:Inverse()
		local joint = rest.Position
		local length = if LIMB_IS_LEG[i] then joint.Y - feet.Y else joint.Y - torsoBottomY
		Ragdoll.AddLimb(shape, joint, math.max(length, 0.1 * scale), LIMB_IS_LEG[i])
	end

	return {
		shape = shape,
		scale = scale,
		rootRest = rootRest,
		rootRestInverse = rootRest:Inverse(),
		torsoRest = torsoRest,
		torsoRestInverse = torsoRest:Inverse(),
		limbRest = limbRest,
		limbRestInverse = limbRestInverse,
	}
end

local function getTemplate(enemyData: TData.TEnemy): TData.TEnemyModel?
	local cached = templates[enemyData.Id]
	if cached then return cached end
	if not EnemiesCore.HasModel(enemyData) then
		if not missingModelWarned[enemyData.Id] then
			missingModelWarned[enemyData.Id] = true
			warn(`[EnemiesController] no rig ReplicatedStorage.Models.Enemies.{enemyData.ModelName}; drawing nothing`)
		end
		return nil
	end

	local template = EnemiesCore.GetModel(enemyData):Clone()
	-- No shadow: a skinned body casting one is skinned and drawn again into the shadow map, the whole crowd twice over,
	-- and the cost of that lands hardest on the devices with the least to spare. Set here so no rig put in the place
	-- can forget it, on every part (a boss is two).
	for _, part in template:GetDescendants() do
		if part:IsA("BasePart") then part.CastShadow = false end
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "Flash"
	highlight.FillColor = Tune.FLASH_COLOR
	highlight.OutlineColor = Tune.LAST_OUTLINE_COLOR
	-- Resting: invisible, and an invisible highlight renders for free.
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = template

	-- template.Parent is deliberately never assigned.
	templates[enemyData.Id] = template

	-- The server's position is the FEET; a skinned body deforms about its MeshPart's centre, half a body up.
	groundLifts[enemyData.Id] = CFrame.new(0, template:GetExtentsSize().Y / 2, 0)

	-- Every clip the server times a blow by is fetched now, ahead of the round: a clip played the first time it is
	-- asked for is still downloading and starts after the blow it shows.
	local clips = EnemiesCore.GetClips(enemyData)
	clipsById[enemyData.Id] = clips
	local preload: { Animation } = {}
	for _, clip in clips.Attacks do
		table.insert(preload, clip)
	end

	if clips.Idle then table.insert(preload, clips.Idle) end
	if clips.Walk then table.insert(preload, clips.Walk) end
	-- A boss plays its whole set, each clip timed by the server.
	if enemyData.Boss then
		for _, clip in clips.Named do
			table.insert(preload, clip)
		end
	end
	task.spawn(ContentProvider.PreloadAsync, ContentProvider, preload)
	local ragdollRig = buildRagdollRig(template)
	if not ragdollRig and not clips.Death then
		warn(`[EnemiesController] {enemyData.ModelName} has not got the R6 bones; kills will not ragdoll`)
	end

	ragdollRigs[enemyData.Id] = ragdollRig or false
	reserveFor(enemyData.Id)
	return template
end

local function getTrack(
	model: TData.TEnemyModel,
	animation: Animation,
	priority: Enum.AnimationPriority,
	isLooped: boolean
): AnimationTrack
	local tracks = modelTracks[model]
	if not tracks then
		tracks = {}
		modelTracks[model] = tracks
	end

	local track = tracks[animation]
	if track then return track end
	track = model.AnimationController.Animator:LoadAnimation(animation)
	-- Set here rather than trusted from the upload: a re-export is one click from reordering the layers.
	track.Priority = priority
	track.Looped = isLooped
	tracks[animation] = track
	trackModels[track] = model
	return track
end

-- The rig's inertial blend, made on first use.
local function blendOf(model: TData.TEnemyModel): InertialBlend.TInertialBlend
	local blend = blends[model]
	if blend then return blend end
	local isBoss = bossRigs[model] == true
	blend = InertialBlend.new(InertialBlend.JointsOf(model), isBoss)
	blends[model] = blend
	if isBoss then steppingBlends[blend] = true end
	return blend
end

local function blendSeconds(model: TData.TEnemyModel): number
	return if bossRigs[model] then Tune.BOSS_BLEND else Tune.BLEND
end

-- The rig cuts to its clips as they are about to be, blended from the pose on screen.
local function blendFrom(model: TData.TEnemyModel, isUnscaled: boolean?)
	local blend = blendOf(model)
	blend:Start(blendSeconds(model))
	unscaledBlends[blend] = if isUnscaled then true else nil
	steppingBlends[blend] = true
end

-- One-shot `track` blends out of its last frame into whatever is under it, instead of dropping its pose.
local function blendOut(track: AnimationTrack)
	local model = trackModels[track]
	if not model then return end
	local blend = blendOf(model)
	blend:Watch(track, blendSeconds(model))
	steppingBlends[blend] = true
end

-- A fade asks for a blend: the engine's own fade is linear, the rig's blend eases (inertialBlend).
local function play(track: AnimationTrack, fade: number?, speed: number?, isUnscaled: boolean?)
	local baseSpeed = speed or 1
	local model = trackModels[track]
	if model and fade and fade > 0 then
		blendFrom(model, isUnscaled)
		fade = 0
	elseif model and fade == 0 and blends[model] then
		-- A cut asked for (up out of the floor, an intro's first frame): no blend carries on over it.
		blends[model]:Cancel()
	end
	track:Play(fade, nil, if isUnscaled then baseSpeed else baseSpeed * clipScale)
	trackSpeeds[track] = baseSpeed
	playingTracks[track] = true
	unscaledTracks[track] = if isUnscaled then true else nil
end

local function stop(track: AnimationTrack, fade: number?)
	if not playingTracks[track] then return end
	local model = trackModels[track]
	if model and fade and fade > 0 then
		blendFrom(model, unscaledTracks[track])
		fade = 0
	end
	track:Stop(fade)
	playingTracks[track] = nil
	unscaledTracks[track] = nil
end

-- Everything stopped at once (a park, a death), any blend let go with it.
local function stopAll(model: TData.TEnemyModel)
	local blend = blends[model]
	if blend then
		blend:Cancel()
		if not blend:IsActive() then steppingBlends[blend] = nil end
	end
	local tracks = modelTracks[model]
	if not tracks then return end
	for _, track in tracks do
		stop(track, 0)
	end
end

-- A body's clip by name off its set, loaded on its rig; nil while it has no rig or the set has no such clip.
local function namedTrack(instanceId: number, name: string, options: TClipOptions?): AnimationTrack?
	local entity = EnemyWorldRef:Search(instanceId)
	if not entity then return nil end
	local model = EnemyWorld:get(entity, Components.Model) :: TData.TEnemyModel?
	local enemyData = EnemyWorld:get(entity, Components.Data)
	if not model or not enemyData then return nil end
	local clips = clipsById[enemyData.Id] or EnemiesCore.GetClips(enemyData)
	local animation = clips.Named[name]
	if not animation then return nil end
	local priority = if options and options.Priority then options.Priority else ATTACK_PRIORITY
	return getTrack(model, animation, priority, options ~= nil and options.IsLooped == true)
end

-- Plays clip `name` of the body's set as an action over whatever it was doing (BossController's moves). It follows
-- the match's clock like every other clip unless IsUnscaled. Returns the track, or nil with no rig or no such clip.
function EnemiesController.PlayClip(instanceId: number, name: string, options: TClipOptions?): AnimationTrack?
	local track = namedTrack(instanceId, name, options)
	if not track then return nil end
	track.Looped = options ~= nil and options.IsLooped == true
	play(
		track,
		if options and options.Fade then options.Fade else Tune.CLIP_FADE,
		if options then options.Speed else nil,
		options ~= nil and options.IsUnscaled == true
	)
	if not track.Looped then blendOut(track) end
	return track
end

function EnemiesController.StopClip(instanceId: number, name: string, fade: number?)
	local track = namedTrack(instanceId, name)
	if track then stop(track, fade or Tune.CLIP_FADE) end
end

-- The track of clip `name` on the body's rig if it is loaded (played once), for reading where it is.
function EnemiesController.GetTrack(instanceId: number, name: string): AnimationTrack?
	local entity = EnemyWorldRef:Search(instanceId)
	local model = if entity then EnemyWorld:get(entity, Components.Model) :: TData.TEnemyModel? else nil
	local enemyData = if entity then EnemyWorld:get(entity, Components.Data) else nil
	local tracks = if model then modelTracks[model] else nil
	if not tracks or not enemyData then return nil end
	local clips = clipsById[enemyData.Id]
	local animation = if clips then clips.Named[name] else nil
	return if animation then tracks[animation] else nil
end

-- A rig going for good: its tracks forgotten, the instance (and its Highlight) destroyed.
local function destroyRig(model: TData.TEnemyModel)
	local tracks = modelTracks[model]
	if tracks then
		for _, track in tracks do
			playingTracks[track] = nil
			trackSpeeds[track] = nil
			unscaledTracks[track] = nil
			trackModels[track] = nil
		end
		modelTracks[model] = nil
	end

	local blend = blends[model]
	if blend then
		steppingBlends[blend] = nil
		unscaledBlends[blend] = nil
		blends[model] = nil
	end
	bossRigs[model] = nil

	model:Destroy()
end

-- The outline of the last few, seen through walls so they can be found. Off, the Flash is back to a hit flash.
local function setMarked(highlight: Highlight, isMarked: boolean)
	highlight.OutlineTransparency = if isMarked then Tune.LAST_OUTLINE_TRANSPARENCY else 1
	highlight.DepthMode = if isMarked then Enum.HighlightDepthMode.AlwaysOnTop else Enum.HighlightDepthMode.Occluded
end

local function attachRig(
	entity: jecs.Entity<any>,
	instanceId: number,
	enemyData: TData.TEnemy,
	model: TData.TEnemyModel
)
	local bone = model.PrimaryPart.Root
	local highlight = (model :: TRig).Flash
	flashHighlights[instanceId] = highlight
	if isMarkingLast and not enemyData.Boss then setMarked(highlight, true) end
	local glow = enemyData.Glow
	if glow then
		glowing[instanceId] = true
		highlight.FillColor = glow
		highlight.FillTransparency = BossesCore.GLOW_TRANSPARENCY
	end
	-- Parked, not placed: the render loop reads the far-away CFrame as "coming into view" and snaps it onto its
	-- live position on this same frame, or leaves it parked at no cost if it is off screen.
	bone.Transform = FAR_AWAY_CFRAME

	-- Parented once fully built, so Workspace sees one hierarchy event carrying the highlight with it
	-- (performance/14: attaching a Highlight to a model already rendering is the dearest order).
	model.Parent = EnemiesFolder
	highlightCount += 1

	-- Loaded, not played: a playing track on a parked body walks its root back to the model origin. The loop starts
	-- them the frame the body is first shown.
	local clips = EnemiesCore.GetClips(enemyData)
	if enemyData.IsBoss then bossRigs[model] = true end
	if clips.Idle then getTrack(model, clips.Idle, IDLE_PRIORITY, true) end
	if clips.Walk then getTrack(model, clips.Walk, WALK_PRIORITY, true) end
	jecs.bulk_insert(EnemyWorld, entity, { Components.Bone, Components.Model }, { bone, model })
	EnemyWorld:set(entity, Components.CFrame, FAR_AWAY_CFRAME)
end

-- Gives out this frame's bodies and returns what is left of the clone budget for the refill. Getting a rig is queued
-- apart from the spawn so a round arriving costs a few clones a frame instead of a spike; a body killed before its
-- turn never gets one.
local function drainRigQueue(cloneBudget: number): number
	if rigQueueHead > rigQueueTail then
		if rigQueueTail > 0 then
			table.clear(rigQueue)
			rigQueueHead = 1
			rigQueueTail = 0
		end
		return cloneBudget
	end

	local rigs = Tune.MAX_RIGS_PER_FRAME
	while rigQueueHead <= rigQueueTail and rigs > 0 do
		local instanceId = rigQueue[rigQueueHead]
		local entity = EnemyWorldRef:Search(instanceId)
		local enemyData = if entity then EnemyWorld:get(entity, Components.Data) else nil
		-- Gone before its body came out of the queue, or already given one: nothing to do.
		if not entity or not enemyData or EnemyWorld:has(entity, Components.Model) then
			rigQueue[rigQueueHead] = nil
			rigQueueHead += 1
			continue
		end

		local template = getTemplate(enemyData)
		local reserve = reserveFor(enemyData.Id)
		local model: TData.TEnemyModel? = nil
		local ready = #reserve
		if ready > 0 then
			model = reserve[ready]
			reserve[ready] = nil
		elseif template and cloneBudget > 0 then
			cloneBudget -= 1
			model = template:Clone()
		elseif template then
			-- Nothing ready and no clone left this frame: the rest waits a frame.
			break
		end

		rigQueue[rigQueueHead] = nil
		rigQueueHead += 1
		rigs -= 1
		if model then attachRig(entity, instanceId, enemyData, model) end
	end

	return cloneBudget
end

local function refillReserves(cloneBudget: number)
	cloneBudget = math.min(cloneBudget, Tune.MAX_RESERVE_CLONES_PER_FRAME)
	if cloneBudget <= 0 then return end
	for dataId, reserve in reserves do
		local template = templates[dataId]
		if not template then continue end
		local count = #reserve
		while count < Tune.RESERVE_TARGET and cloneBudget > 0 do
			count += 1
			reserve[count] = template:Clone()
			cloneBudget -= 1
		end

		if cloneBudget <= 0 then return end
	end
end

-- ============================== Lifecycle ==============================
local function forgetId(instanceId: number)
	positions[instanceId] = nil
	yaws[instanceId] = nil
	moving[instanceId] = nil
	lastUpdate[instanceId] = nil
	targetCFrames[instanceId] = nil
	targetBuiltFrom[instanceId] = nil
	targetBuiltYaw[instanceId] = nil
	isWalking[instanceId] = nil
	isShown[instanceId] = nil
	flashTarget[instanceId] = nil
	flashEndsAt[instanceId] = nil
	flashFrom[instanceId] = nil
	flashHighlights[instanceId] = nil
	flinchStartedAt[instanceId] = nil
	flinchAway[instanceId] = nil
	hitSoundAt[instanceId] = nil
	arrivalEndsAt[instanceId] = nil
	stiffYaws[instanceId] = nil
	walkPaces[instanceId] = nil
	glowing[instanceId] = nil
	drivers[instanceId] = nil
	EnemiesController.Bosses[instanceId] = nil
end

-- The floor height under a point: the arena only (never an enemy, which all sit at the origin). Off the arena, or
-- in a place with none, `fallback`.
local function probeFloor(at: Vector3, fallback: number): number
	local arena = Workspace:FindFirstChild("Arena")
	if not arena then return fallback end
	if arena ~= floorArena then
		floorArena = arena
		floorParams.FilterDescendantsInstances = { arena }
	end

	local hit = Workspace:Raycast(
		at + Vector3.new(0, Tune.FLOOR_PROBE_UP, 0),
		Vector3.new(0, -Tune.FLOOR_PROBE_DOWN, 0),
		floorParams
	)
	return if hit then hit.Position.Y else fallback
end

-- Where a character stands, or nil for nobody (id 0) or one that has no body. A volley reads it once for all its hits.
local function characterPosition(characterId: number): Vector3?
	local entity = WorldRef:Search(characterId)
	local character = if entity then World:get(entity, Components.Model) :: Model? else nil
	local root = if character then character.PrimaryPart else nil
	return if root then root.Position else nil
end

-- Away from the attacker, or backwards off the body's own facing when it is unknown or on top of the body.
local function knockDirection(from: Vector3?, at: Vector3, facing: CFrame): Vector3
	local away = if from then at - from else -facing.LookVector
	away = Vector3.new(away.X, 0, away.Z)
	if away.Magnitude < 0.1 then away = Vector3.new(-facing.LookVector.X, 0, -facing.LookVector.Z) end
	local spread = rad(Tune.KNOCK_SPREAD_DEG) * (random() * 2 - 1)
	return CFrame.Angles(0, spread, 0):VectorToWorldSpace(away.Unit)
end

-- Turns a killed body into a falling one: its pose read off its bones as the clip left it, its Animator removed so
-- nothing writes them again, and the ragdoll started from there. nil when the rig cannot ragdoll.
local function startRagdoll(
	model: TData.TEnemyModel,
	enemyData: TData.TEnemy,
	killerPosition: Vector3?,
	cframe: CFrame
): TCorpse?
	local rig = ragdollRigs[enemyData.Id]
	if not rig then return nil end

	local root = model.PrimaryPart.Root
	local torso = root:FindFirstChild("Torso") :: Bone
	local limbs = table.create(4)

	for i, name in LIMB_NAMES do
		limbs[i] = torso:FindFirstChild(name) :: Bone
	end

	-- Rest -> world for each segment as posed now (the transforms the last frame wrote).
	local rootFrame = rig.rootRest * root.Transform * rig.rootRestInverse
	local torsoFrame = rootFrame * rig.torsoRest * torso.Transform * rig.torsoRestInverse
	local limbFrames = table.create(4)

	for i, bone in limbs do
		limbFrames[i] = torsoFrame * rig.limbRest[i] * bone.Transform * rig.limbRestInverse[i]
	end

	stopAll(model)
	model.AnimationController:Destroy()
	-- The torso's pose is folded into Root's from here on.
	torso.Transform = CFrame.identity

	local center = torsoFrame * rig.shape.TorsoCenter
	local direction = knockDirection(killerPosition, center, cframe)
	local speed = Tune.KNOCK_SPEED * rig.scale * (0.85 + random() * 0.3)
	local corpse = table.clone(CORPSE_STUB)
	corpse.model = model
	corpse.rig = rig
	corpse.root = root
	corpse.limbs = limbs
	corpse.body = Ragdoll.Start(
		rig.shape,
		torsoFrame,
		limbFrames,
		direction * (speed * Tune.KNOCK_BASE_SHARE),
		direction * speed,
		probeFloor(center, cframe.Position.Y)
	)
	corpse.probedAt = center
	return corpse
end

-- Turns a killed body into one falling as its Death clip has it, in the ground frame it died in. Everything else it
-- was playing stops, so the fall is the clip's alone.
local function startDeathClip(model: TData.TEnemyModel, clip: Animation, cframe: CFrame, lift: CFrame): TClipCorpse
	stopAll(model)
	local track = getTrack(model, clip, Enum.AnimationPriority.Action4, false)
	play(track, 0.1, 1)
	local corpse: TClipCorpse = {
		model = model,
		root = model.PrimaryPart.Root,
		track = track,
		frame = cframe * lift,
		rate = clipScale,
		isHeld = false,
		lingers = Tune.DEATH_LINGER,
		sunk = 0,
		sinkDepth = model:GetExtentsSize().Y + Tune.SINK_MARGIN,
		highlight = nil,
		flashRemaining = 0,
	}
	corpse.root.Transform = corpse.frame
	return corpse
end

-- Drops the row. A body killed on screen ragdolls and is a corpse until it has sunk, flashing on the way down;
-- anything else is destroyed on the spot. `killerId` is nil when it was removed rather than killed, and 0 when nobody
-- killed it: that is an exploder's own blast, and a body that blew itself up has nothing left to fall. An overkill
-- leaves nothing to fall either: the body comes apart. `killerPosition` is where the killer stands, to fall away from.
local function removeEnemy(
	instanceId: number,
	killerId: number?,
	isOverkill: boolean?,
	killerPosition: Vector3?
): Vector3?
	local entity = EnemyWorldRef:Search(instanceId)
	if not entity then
		forgetId(instanceId)
		return nil
	end

	local enemyData = EnemyWorld:get(entity, Components.Data)
	local model = EnemyWorld:get(entity, Components.Model) :: TData.TEnemyModel?
	local cframe = EnemyWorld:get(entity, Components.CFrame)
	local isOnScreen = cframe ~= nil and cframe.Position.X ~= FAR_AWAY_X
	local at = if isOnScreen then (cframe :: CFrame).Position else positions[instanceId]
	-- A body set stiff has nothing loose to fall with: it breaks apart.
	if stiffYaws[instanceId] and killerId then isOverkill = true end

	if model and enemyData then
		-- Killed mid-arrival: the corpse falls solid.
		if arrivalEndsAt[instanceId] then model.PrimaryPart.Transparency = 0 end
		-- A set with its own fall plays it, whatever killed it (a boss, which no ragdoll can take).
		local deathClip = clipsById[enemyData.Id] and clipsById[enemyData.Id].Death
		local clipCorpse = if killerId
				and isOnScreen
				and deathClip
				and #clipCorpses < Tune.DEATH_CORPSES
			then startDeathClip(model, deathClip, cframe :: CFrame, groundLifts[enemyData.Id])
			else nil
		if clipCorpse then
			local highlight = flashHighlights[instanceId]
			setMarked(highlight, false)
			highlight.FillTransparency = 0
			clipCorpse.highlight = highlight
			clipCorpse.flashRemaining = Tune.FLASH_TIME
			clipCorpses[#clipCorpses + 1] = clipCorpse
		end
		local corpse = if killerId
				and not clipCorpse
				and killerId ~= 0
				and not isOverkill
				and isOnScreen
				and #corpses < Tune.MAX_CORPSES
			then startRagdoll(model, enemyData, killerPosition, cframe :: CFrame)
			else nil
		if corpse then
			-- Every killing blow flashes (a kill that does not flash reads as a miss). The flash is
			-- spent by duration, so it is a corpse's Highlight that gives way when the budget is full.
			local highlight = flashHighlights[instanceId]
			setMarked(highlight, false)
			highlight.FillTransparency = 0
			corpse.highlight = highlight
			corpse.flashRemaining = Tune.FLASH_TIME
			corpses[#corpses + 1] = corpse
		elseif not clipCorpse then
			highlightCount -= 1
			destroyRig(model)
		end

		-- The killing blow shows a hit's light with more of the body knocked off, and a body that goes on the spot a
		-- puff to hide that it popped. An overkill's burst stands in for both.
		if killerId and isOnScreen then
			local aim = EnemiesCore.AimShape(enemyData)
			local chest = (at :: Vector3) + Vector3.new(0, aim.x, 0)
			if isOverkill then
				EnemyImpacts.EmitOverkill(enemyData, chest, aim, killerPosition)
			else
				EnemyImpacts.EmitKill(enemyData, chest, aim, killerPosition)
				if not corpse and not clipCorpse then EnemyImpacts.EmitVanish(enemyData, chest, aim) end
			end
		end
	end

	forgetId(instanceId)
	EnemyWorldRef:Nuke(instanceId, entity)
	EnemiesController.Count -= 1
	return at
end

-- Outlines every living rig but a boss's, or takes the outline off them all. A boss is never lost: it has its bar,
-- its size and its intro, and an outline round a giant reads over its effects.
local function markLast(isMarked: boolean)
	if isMarked == isMarkingLast then return end
	isMarkingLast = isMarked
	for instanceId, highlight in flashHighlights do
		if not EnemiesController.Bosses[instanceId] then setMarked(highlight, isMarked) end
	end
end

-- `from` is the fill it is struck at: 0 white, a boss's blow far fainter.
local function flash(instanceId: number, from: number)
	local highlight = flashHighlights[instanceId]
	if not highlight then return end
	highlight.FillTransparency = from
	flashTarget[instanceId] = highlight
	flashEndsAt[instanceId] = os.clock() + Tune.FLASH_TIME
	flashFrom[instanceId] = from
end

-- A full white flash, for a boss's moment (a quarter of its health gone, BossController) over its faint blows.
function EnemiesController.Flash(instanceId: number)
	flash(instanceId, 0)
end

-- Where a hit lands: the chest of a drawn body, with its aim shape (EnemiesCore.AimShape), its ground CFrame and its
-- data; the last packet's feet and none of the others for one that is parked out of view.
local function hitPosition(instanceId: number): (Vector3?, vector?, CFrame?, TData.TEnemy?)
	local entity = EnemyWorldRef:Search(instanceId)
	local cframe = if entity then EnemyWorld:get(entity, Components.CFrame) else nil
	local enemyData = if entity then EnemyWorld:get(entity, Components.Data) else nil
	if not cframe or not enemyData or cframe.Position.X == FAR_AWAY_X then
		return positions[instanceId], nil, nil, nil
	end
	local aim = EnemiesCore.AimShape(enemyData)
	return cframe.Position + Vector3.new(0, aim.x, 0), aim, cframe, enemyData
end

local function addEnemy(instanceId: number, dataId: number, position: Vector3, isArriving: boolean)
	local enemyData = ENEMIES[dataId]
	if not enemyData then return end
	if EnemyWorldRef:Search(instanceId) then removeEnemy(instanceId, nil) end

	-- Pre-filled so the first frame targets the right place before a packet arrives.
	positions[instanceId] = position
	lastUpdate[instanceId] = TimeCore.EnemyClock
	-- A boss stands for its intro, and the held match streams no packet to say so: walking, its Walk would sit
	-- frozen under the Intro clip and show through it as a stride held still once the clip fades.
	moving[instanceId] = not enemyData.IsBoss
	-- A boss comes on through its intro, not dropping in.
	if isArriving and not enemyData.IsBoss then arrivalEndsAt[instanceId] = TimeCore.EnemyClock + Tune.ARRIVAL_TIME end

	viewSpheresById[enemyData.Id] = EnemiesCore.ViewSphere(enemyData)
	local entity = EnemyWorldRef:EntityRef(instanceId)
	EnemiesController.Count += 1
	if enemyData.Boss then EnemiesController.Bosses[instanceId] = enemyData end
	jecs.bulk_insert(EnemyWorld, entity, {
		Components.CFrame,
		Components.InstanceId,
		Components.Data,
		Components.AimShape,
		Tags.Enemy,
	}, {
		CFrame.new(position),
		instanceId,
		enemyData,
		EnemiesCore.AimShape(enemyData),
	})
	if enemyData.AimPieces then EnemyWorld:set(entity, Components.AimPieces, enemyData.AimPieces) end

	rigQueueTail += 1
	rigQueue[rigQueueTail] = instanceId
end

local function enemyDataOf(instanceId: number): TData.TEnemy?
	local entity = EnemyWorldRef:Search(instanceId)
	return if entity then EnemyWorld:get(entity, Components.Data) else nil
end

local function flinch(instanceId: number, at: Vector3, facing: CFrame, attackerPosition: Vector3?)
	local now = os.clock()
	local startedAt = flinchStartedAt[instanceId]
	if startedAt and now - startedAt < Tune.FLINCH_RETRIGGER then return end
	flinchStartedAt[instanceId] = now
	flinchAway[instanceId] = knockDirection(attackerPosition, at, facing)
end

-- Flashes every hit, and bursts and jolts every one in view; the sound is the caller's, so a volley can play one for
-- all of it.
local function onDamaged(attackerId: number, attackerPosition: Vector3?, instanceId: number, damage: number): Vector3?
	local isBoss = EnemiesController.Bosses[instanceId] ~= nil
	flash(instanceId, if isBoss then Tune.BOSS_FLASH_TRANSPARENCY else 0)
	local at, aim, cframe, enemyData = hitPosition(instanceId)
	if not at then return nil end
	EnemiesController.OnEnemyDamaged:Fire(instanceId, attackerId, damage, at, if aim then aim.z else nil)

	-- A boss's blow is drawn where its bullet lands (EnemyImpacts.EmitBossHit), and it stands its ground.
	if not aim or not cframe or not enemyData or isBoss then return at end
	EnemyImpacts.EmitHit(enemyData, at, aim, attackerPosition)
	flinch(instanceId, at, cframe, attackerPosition)
	return at
end

-- Where a blow's impact is heard from: the camera for the player's own, so it is as loud on a far body as on a near
-- one, and the body for anybody else's, which fades with distance.
local function heardFrom(attackerId: number, at: Vector3): Vector3
	if not selfEntity or WorldRef:Search(attackerId) ~= selfEntity then return at end

	return Workspace.CurrentCamera.CFrame.Position
end

local function playHitSound(instanceId: number, at: Vector3, from: Vector3)
	-- A boss's blows are heard as their bullets land, each one (EnemyImpacts.EmitBossHit).
	if EnemiesController.Bosses[instanceId] then return end
	local now = os.clock()
	local last = hitSoundAt[instanceId]
	if last and now - last < Tune.HIT_SOUND_DEBOUNCE then return end
	hitSoundAt[instanceId] = now
	EnemyImpacts.PlayHit(enemyDataOf(instanceId), at, from)
end

-- A volley plays its one sound at the body nearest the camera: beginVolley, then isNearestInVolley for each body.
local function beginVolley()
	volleyCameraPosition = Workspace.CurrentCamera.CFrame.Position
	volleyNearestDistSq = math.huge
end

local function isNearestInVolley(at: Vector3): boolean
	local offset = at - volleyCameraPosition
	local distSq = offset:Dot(offset)
	if distSq >= volleyNearestDistSq then return false end
	volleyNearestDistSq = distSq
	return true
end

-- The killing blow's hit and the death cry play on the kill, ragdoll or not: a last hit that lands silently reads as
-- a miss.
local function playKillSounds(enemyData: TData.TEnemy?, at: Vector3, from: Vector3, count: number, isOverkill: boolean)
	EnemyImpacts.PlayHit(enemyData, at, from)
	EnemyImpacts.PlayDeath(enemyData, at, from, isOverkill)
	EnemyImpacts.AddKills(count, from)
end

local function onKilled(
	killerId: number,
	killerPosition: Vector3?,
	instanceId: number,
	damage: number,
	isOverkill: boolean
): (Vector3?, TData.TEnemy?)
	-- Read before the row goes.
	local enemyData = enemyDataOf(instanceId)
	local chest, aim = hitPosition(instanceId)
	local at = removeEnemy(instanceId, killerId, isOverkill, killerPosition)
	if at then
		EnemiesController.OnEnemyKilled:Fire(
			instanceId,
			killerId,
			damage,
			isOverkill,
			chest or at,
			if aim then aim.z else nil
		)
	end
	return at, enemyData
end

-- ============================== Render ==============================
-- Any of the body's view sphere on screen, the same test as the server's (AOIService's isInView has the why).
local function isVisible(position: Vector3, view: vector): boolean
	local radius = view.y
	local vx = position.X - cameraX
	local vy = position.Y + view.x - cameraY
	local vz = position.Z - cameraZ
	local distSq = vx * vx + vy * vy + vz * vz
	if distSq > RENDER_DISTANCE_SQ then return false end
	if distSq < radius * radius then return true end
	local shift = radius * apexShiftPerRadius
	vx += lookX * shift
	vy += lookY * shift
	vz += lookZ * shift
	local dot = vx * lookX + vy * lookY + vz * lookZ
	if dot <= 0 then return false end
	return dot * dot > thresholdSq * (vx * vx + vy * vy + vz * vz)
end

-- The rigs' facing convention: forward is the NEGATED (sin, 0, cos) of the yaw, and goes into fromMatrix negated again.
-- Unnegated, every body walks backwards.
local function buildTarget(position: Vector3, yaw: number): CFrame
	local forward = Vector3.new(-sin(yaw), 0, -cos(yaw))
	local right = forward:Cross(V3_YAXIS).Unit
	return CFrame.fromMatrix(position, right, V3_YAXIS, -forward)
end

-- A reeling body as drawn: leaned away from the shooter on its feet and shaken sideways. The lean outlasts the shake,
-- so its end is the flinch's.
local function flinched(instanceId: number, cf: CFrame, elapsed: number): CFrame
	local phase = elapsed * Tune.FLINCH_SPEED
	if phase >= TAU then
		flinchStartedAt[instanceId] = nil
		flinchAway[instanceId] = nil
		return cf
	end

	local lean = sin(phase) * exp(-phase * Tune.FLINCH_DAMPER)
	local shake = if elapsed < Tune.FLINCH_SHAKE_TIME
		then sin(elapsed * Tune.FLINCH_SHAKE_SPEED) * (1 - elapsed / Tune.FLINCH_SHAKE_TIME) * Tune.FLINCH_SHAKE_STUDS
		else 0
	local away = flinchAway[instanceId]
	-- The axis that tips the top toward `away`, and also the sideways the shake runs along.
	local side = V3_YAXIS:Cross(away)
	return CFrame.new(cf.Position + away * (lean * Tune.FLINCH_PUSH) + side * shake)
		* CFrame.fromAxisAngle(side, lean * Tune.FLINCH_ANGLE)
		* cf.Rotation
end

-- Kept small (performance/optimization-2026-10-22/RESULTS.md): a target is rebuilt only when a packet moved or turned
-- the body, and walk / idle is tracked here rather than by asking a track IsPlaying.
local function update(dt: number)
	debug.profilebegin("EnemiesRender")
	local camera = Workspace.CurrentCamera
	local cameraCFrame = camera.CFrame
	local cameraPosition = cameraCFrame.Position
	local look = cameraCFrame.LookVector
	cameraX, cameraY, cameraZ = cameraPosition.X, cameraPosition.Y, cameraPosition.Z
	lookX, lookY, lookZ = look.X, look.Y, look.Z
	local halfFov = rad(camera.DiagonalFieldOfView) / 2
	local threshold = cos(halfFov)
	thresholdSq = threshold * threshold
	apexShiftPerRadius = 1 / sin(halfFov)

	local lerpAlpha = 1 - exp(-TimeCore.GetEnemyDeltaTime(TimeCore.RENDER_DT) * dt)
	local enemyClock = TimeCore.EnemyClock
	local staleBefore = enemyClock - STALE_TIME
	local wantsIdleGroan = enemyClock >= nextIdleGroan

	-- Fade every live hit flash. Driven off the fraction LEFT, not the live value: easing from the current reading
	-- compounds into a framerate-dependent decay.
	local now = os.clock()
	for instanceId, highlight in flashTarget do
		local remaining = flashEndsAt[instanceId] - now
		local rest = if stiffYaws[instanceId]
			then Tune.STIFF_TRANSPARENCY
			elseif glowing[instanceId] then BossesCore.GLOW_TRANSPARENCY
			else 1
		if remaining <= 0 or not highlight.Parent then
			highlight.FillTransparency = rest
			flashTarget[instanceId] = nil
			flashEndsAt[instanceId] = nil
			flashFrom[instanceId] = nil
		else
			local from = flashFrom[instanceId] or 0
			highlight.FillTransparency = from + (rest - from) * (1 - remaining / Tune.FLASH_TIME)
		end
	end

	-- Corpses: falling, then lying still, then sinking. A corpse's Highlight is dropped the moment its flash ends, so
	-- the budget is spent by duration, not by how long the body takes to go under. The fall runs on game time, so a
	-- pause holds it; an enemy freeze does not, since the body is no longer an enemy.
	local gameDt = TimeCore.GetDeltaTime(dt)
	local timeScale = TimeCore.TimeScale
	local gravity = TimeCore.GRAVITY * Tune.RAGDOLL_GRAVITY_SCALE

	for i = #clipCorpses, 1, -1 do
		local corpse = clipCorpses[i]
		local highlight = corpse.highlight
		if highlight then
			corpse.flashRemaining -= dt
			if corpse.flashRemaining <= 0 or highlightCount > Tune.MAX_HIGHLIGHTS then
				highlight:Destroy()
				corpse.highlight = nil
				highlightCount -= 1
			else
				highlight.FillTransparency = 1 - corpse.flashRemaining / Tune.FLASH_TIME
			end
		end

		-- Every frame: the clip keys Root too (at rest), and its write lands before this one.
		corpse.root.Transform = CFrame.new(0, -corpse.sunk, 0) * corpse.frame
		-- On the game clock, as its fall's thud is: a clip left running through a pause plays off its end and stands
		-- the body back up.
		local track = corpse.track
		if not corpse.isHeld and corpse.rate ~= timeScale then
			corpse.rate = timeScale
			track:AdjustSpeed(timeScale)
		end
		if gameDt <= 0 then continue end
		if not corpse.isHeld then
			if track.Length > 0 and track.TimePosition >= track.Length - Tune.DEATH_HOLD_MARGIN then
				track:AdjustSpeed(0)
				trackSpeeds[track] = 0
				corpse.isHeld = true
			end
		elseif corpse.lingers > 0 then
			corpse.lingers -= gameDt
		else
			corpse.sunk = math.min(corpse.sinkDepth, corpse.sunk + Tune.SINK_SPEED * gameDt)
			if corpse.sunk < corpse.sinkDepth then continue end
			if corpse.highlight then
				highlightCount -= 1
			end
			destroyRig(corpse.model)
			clipCorpses[i] = clipCorpses[#clipCorpses]
			clipCorpses[#clipCorpses] = nil
		end
	end

	for i = #corpses, 1, -1 do
		local corpse = corpses[i]
		local highlight = corpse.highlight
		if highlight then
			-- Over budget, a corpse's flash is what gives way, never a living body's.
			corpse.flashRemaining -= dt
			if corpse.flashRemaining <= 0 or highlightCount > Tune.MAX_HIGHLIGHTS then
				highlight:Destroy()
				corpse.highlight = nil
				highlightCount -= 1
			else
				highlight.FillTransparency = 1 - corpse.flashRemaining / Tune.FLASH_TIME
			end
		end

		if gameDt <= 0 then continue end

		local rig = corpse.rig
		local body = corpse.body
		local isGone = false
		if corpse.sinkDepth < 0 then
			Ragdoll.Step(body, gameDt, gravity)
			local center = body.center
			local moved = center - corpse.probedAt
			if moved.X * moved.X + moved.Z * moved.Z > Tune.FLOOR_REPROBE_DISTANCE * Tune.FLOOR_REPROBE_DISTANCE then
				corpse.probedAt = center
				Ragdoll.SetFloor(body, probeFloor(center, body.floorY))
			end

			local torsoFrame = Ragdoll.TorsoFrame(body)
			corpse.root.Transform = rig.rootRestInverse * torsoFrame * rig.rootRest
			local toTorso = torsoFrame:Inverse()
			for limb, bone in corpse.limbs do
				bone.Transform = rig.limbRestInverse[limb]
					* toTorso
					* Ragdoll.LimbFrame(body, limb)
					* rig.limbRest[limb]
			end

			if body.isSettled then
				-- Fell into nothing (off the map, into the void): gone now rather than sinking under no floor.
				isGone = not body.hasLanded
				corpse.restingFrame = torsoFrame
				corpse.sinkDelay = Tune.SINK_DELAY
				corpse.sinkDepth = Ragdoll.TopY(body) - body.floorY + Tune.SINK_MARGIN * rig.scale
			end
		elseif corpse.sinkDelay > 0 then
			corpse.sinkDelay -= gameDt
		else
			-- Limbs are posed relative to the torso, so sinking the whole body is Root's write alone.
			corpse.sunk = math.min(corpse.sinkDepth, corpse.sunk + Tune.SINK_SPEED * gameDt)
			local sunkFrame = CFrame.new(0, -corpse.sunk, 0) * corpse.restingFrame
			corpse.root.Transform = rig.rootRestInverse * sunkFrame * rig.rootRest
			isGone = corpse.sunk >= corpse.sinkDepth
		end

		if not isGone then continue end

		if corpse.highlight then
			highlightCount -= 1
		end
		destroyRig(corpse.model)
		corpses[i] = corpses[#corpses]
		corpses[#corpses] = nil
	end

	for entity, cf, bone, instanceId, enemyData in RiggedQuery do
		local targetPos = positions[instanceId]
		if not targetPos then continue end
		local cfPos = cf.Position
		local isFar = cfPos.X == FAR_AWAY_X
		local updatedAt = lastUpdate[instanceId]
		-- A driven body is where its driver says, packets or none (a boss under the floor streams none).
		local driver = drivers[instanceId]
		local driven = if driver then driver(enemyClock) else nil
		if driver and not driven then drivers[instanceId] = nil end
		if driven then
			targetPos = driven.Position
			updatedAt = enemyClock
		end

		-- Never parked while driven: parking stops its clips, and a driven body is mid-move (an intro, a run).
		local isStale = updatedAt == nil or updatedAt < staleBefore
		if not driven and (isStale or not isVisible(targetPos, viewSpheresById[enemyData.Id])) then
			if isFar then continue end

			-- Stop everything BEFORE parking: a playing Animator rewrites the root each frame and would walk the
			-- hidden body back to the origin, in plain sight. Written once; next frame the isFar check skips it.
			stopAll(EnemyWorld:get(entity, Components.Model) :: TData.TEnemyModel)
			isShown[instanceId] = nil
			isWalking[instanceId] = nil
			bone.Transform = FAR_AWAY_CFRAME
			EnemyWorld:set(entity, Components.CFrame, FAR_AWAY_CFRAME)
			continue
		end

		-- targetPos, not cf: a body coming back into view still has the parking spot as its CFrame this frame.
		if wantsIdleGroan then
			local sounds = enemyData.Sounds
			if sounds and sounds.Idle then
				SoundsCore.PlayWorldNamed(sounds.Group, sounds.Idle, targetPos)
				wantsIdleGroan = false
				nextIdleGroan = enemyClock
					+ Tune.IDLE_GROAN_MIN
					+ random() * (Tune.IDLE_GROAN_MAX - Tune.IDLE_GROAN_MIN)
			end
		end

		local model: TData.TEnemyModel? = nil
		-- A read from this module's own map: GetClips is a cross-module call, and this runs per body per frame.
		local clips = clipsById[enemyData.Id]
		if not isShown[instanceId] then
			isShown[instanceId] = true
			model = EnemyWorld:get(entity, Components.Model) :: TData.TEnemyModel
			if clips.Idle then
				local idleTrack = getTrack(model :: TData.TEnemyModel, clips.Idle, IDLE_PRIORITY, true)
				play(idleTrack, 0)
				if stiffYaws[instanceId] then idleTrack:AdjustSpeed(0) end
			end
		end

		-- Walk over idle, switched only on the frame the packet's answer changes. A fresh walk starts at a random
		-- point so a round that arrived together does not march in step.
		local stiffYaw = stiffYaws[instanceId]
		local isMoving = moving[instanceId] == true
		local walkClip = clips.Walk
		if isMoving ~= isWalking[instanceId] and walkClip and not stiffYaw then
			isWalking[instanceId] = isMoving
			model = model or EnemyWorld:get(entity, Components.Model) :: TData.TEnemyModel
			local walkTrack = getTrack(model :: TData.TEnemyModel, walkClip, WALK_PRIORITY, true)
			if isMoving then
				local boss = enemyData.Boss
				local speed = if boss then bossWalkSpeed(instanceId, enemyData, boss) else nil
				play(walkTrack, Tune.LOCOMOTION_FADE, speed)
				if walkTrack.Length > 0 then walkTrack.TimePosition = random() * walkTrack.Length end
			else
				stop(walkTrack, Tune.LOCOMOTION_FADE)
			end
		end

		-- Rebuilt only when a packet moved or turned it: an exact compare against what it was built from.
		local yaw = stiffYaw or yaws[instanceId] or 0
		local target = targetCFrames[instanceId]
		if not target or targetBuiltFrom[instanceId] ~= targetPos or targetBuiltYaw[instanceId] ~= yaw then
			target = buildTarget(targetPos, yaw)
			targetCFrames[instanceId] = target
			targetBuiltFrom[instanceId] = targetPos
			targetBuiltYaw[instanceId] = yaw
		end

		if driven then
			cf = driven
		elseif isFar then
			cf = target
		else
			local dx = targetPos.X - cfPos.X
			local dy = targetPos.Y - cfPos.Y
			local dz = targetPos.Z - cfPos.Z
			cf = if dx * dx + dy * dy + dz * dz > SNAP_DISTANCE_SQ then target else cf:Lerp(target, lerpAlpha)
		end

		EnemyWorld:set(entity, Components.CFrame, cf)
		-- The CFrame stays the ground one, a flinch and an arrival only move what is drawn: hits and effects aim at
		-- where the server has the body.
		local flinchedAt = flinchStartedAt[instanceId]
		local drawn = if flinchedAt then flinched(instanceId, cf, now - flinchedAt) else cf
		local arrivalEnd = arrivalEndsAt[instanceId]
		if not arrivalEnd then
			bone.Transform = drawn * groundLifts[enemyData.Id]
			continue
		end

		-- Eased on the fraction left, so it comes to rest on its feet instead of landing with a jolt.
		local left = (arrivalEnd - enemyClock) / Tune.ARRIVAL_TIME
		local mesh = (EnemyWorld:get(entity, Components.Model) :: TData.TEnemyModel).PrimaryPart
		if left <= 0 then
			arrivalEndsAt[instanceId] = nil
			mesh.Transparency = 0
			bone.Transform = drawn * groundLifts[enemyData.Id]
		else
			mesh.Transparency = left
			bone.Transform = (drawn + Vector3.new(0, Tune.ARRIVAL_HEIGHT * left * left, 0)) * groundLifts[enemyData.Id]
		end
	end

	-- Nothing visible had a groan to give: held shut a beat, or every visible body would test for one every frame.
	if wantsIdleGroan then nextIdleGroan = enemyClock + Tune.IDLE_GROAN_MIN end
	debug.profileend()
end

ServerNetworkEnemies.Added.On(function(instanceId: number, dataId: number, position: Vector3, isArriving: boolean)
	addEnemy(instanceId, dataId, position, isArriving)
end)

ServerNetworkEnemies.Removed.On(function(instanceId: number)
	removeEnemy(instanceId, nil)
end)

ServerNetworkEnemies.Killed.On(function(killerId: number, instanceId: number, damage: number, isOverkill: boolean)
	local at, enemyData = onKilled(killerId, characterPosition(killerId), instanceId, damage, isOverkill)
	if at then playKillSounds(enemyData, at, heardFrom(killerId, at), 1, isOverkill) end
end)

-- One hit and one death cry for the whole volley, at the body nearest the camera: a wipe is one sound, not a dozen
-- stacked on a frame. The whole count still feeds the wipe layer.
ServerNetworkEnemies.KilledMultiple.On(
	function(killerId: number, instanceIds: { number }, damage: number, isOverkill: boolean)
		beginVolley()
		local killerPosition = characterPosition(killerId)
		local nearestAt: Vector3? = nil
		local nearestData: TData.TEnemy? = nil

		for _, instanceId in instanceIds do
			local at, enemyData = onKilled(killerId, killerPosition, instanceId, damage, isOverkill)
			if at and isNearestInVolley(at) then
				nearestAt = at
				nearestData = enemyData
			end
		end

		if nearestAt then
			playKillSounds(nearestData, nearestAt, heardFrom(killerId, nearestAt), #instanceIds, isOverkill)
		end
	end
)

ServerNetworkEnemies.Damaged.On(function(attackerId: number, instanceId: number, damage: number)
	local at = onDamaged(attackerId, characterPosition(attackerId), instanceId, damage)
	if at then playHitSound(instanceId, at, heardFrom(attackerId, at)) end
end)

ServerNetworkEnemies.DamagedMultiple.On(function(attackerId: number, instanceIds: { number }, damage: number)
	beginVolley()
	local attackerPosition = characterPosition(attackerId)
	local nearestId = 0
	local nearestAt: Vector3? = nil

	for _, instanceId in instanceIds do
		local at = onDamaged(attackerId, attackerPosition, instanceId, damage)
		-- A boss is heard as its bullets land (playHitSound), so the volley's one sound goes to the nearest other body.
		if at and not EnemiesController.Bosses[instanceId] and isNearestInVolley(at) then
			nearestId = instanceId
			nearestAt = at
		end
	end

	if nearestAt then playHitSound(nearestId, nearestAt, heardFrom(attackerId, nearestAt)) end
end)

ServerNetworkEnemies.AttackStarted.On(function(instanceId: number, attackIndex: number)
	local entity = EnemyWorldRef:Search(instanceId)
	if not entity or not isShown[instanceId] then return end
	local enemyData = EnemyWorld:get(entity, Components.Data)

	-- On the wind-up, not the blow, while it can still be answered.
	local sounds = if enemyData then enemyData.Sounds else nil
	local at = positions[instanceId]
	local now = os.clock()
	if sounds and sounds.Attack and at and now >= nextAttackSnarl then
		nextAttackSnarl = now + Tune.ATTACK_SNARL_GAP
		SoundsCore.PlayWorldNamed(sounds.Group, sounds.Attack, at)
	end

	local model = EnemyWorld:get(entity, Components.Model) :: TData.TEnemyModel?
	local attack = if enemyData then enemyData.Attacks[attackIndex] else nil
	local animation = if enemyData then EnemiesCore.GetClips(enemyData).Attacks[attackIndex] else nil
	if not model or not attack or not animation then return end

	-- Stretched so its blow lands as the server's wind-up ends.
	local speed = EnemiesCore.ATTACK_CLIP_IMPACT / math.max(attack.Delay, 0.05)
	local track = getTrack(model, animation, ATTACK_PRIORITY, false)
	play(track, Tune.ATTACK_FADE, speed)
	blendOut(track)
end)

ServerNetworkEnemies.Positions.On(function(packet: buffer)
	EnemyPacker.UnpackInto(packet, positions, yaws, moving, lastUpdate, TimeCore.EnemyClock)
end)

-- Templates built and reserves opened before the first round, so the refill fills them during preparation.
ServerNetworkEnemies.TypesForMatch.On(function(dataIds: { number })
	for _, dataId in dataIds do
		local enemyData = ENEMIES[dataId]
		if enemyData then getTemplate(enemyData) end
	end
end)

-- The server shows the last few to everyone (RoundService), so every body held then is one of them.
MatchController.OnChanged:Connect(function()
	local remaining = MatchController.Remaining
	markLast(
		MatchController.IsRunning
			and not MatchController.IsPreparing
			and remaining > 0
			and remaining <= RoundCore.LAST_SHOWN
	)
end)

-- Every clip at the rate of the match's clock times the enemies': a freeze or a pause stops them where they stand, a
-- slow motion slows them, and a thaw lets them go again. A body held stiff stays stopped. An ease fires the clock's
-- change every frame, so the clips follow it in steps (each step is an AdjustSpeed a playing clip), landing on 0 and
-- 1 exactly.
local function rescaleClips()
	local scale = TimeCore.TimeScale * TimeCore.EnemyTimeScale
	if scale == clipScale then return end
	if scale ~= 0 and scale ~= 1 and math.abs(scale - clipScale) < Tune.CLIP_RESCALE_STEP then return end
	clipScale = scale

	for _, instanceId, model in ModelQuery do
		local tracks = modelTracks[model :: any]
		if not tracks then continue end
		local trackScale = if stiffYaws[instanceId] then 0 else scale
		for _, track in tracks do
			if playingTracks[track] and not unscaledTracks[track] then
				track:AdjustSpeed(trackScale * (trackSpeeds[track] or 1))
			end
		end
	end
end

TimeCore.OnEnemyTimeScaleChange:Connect(rescaleClips)
TimeCore.OnTimeScaleChange:Connect(rescaleClips)

-- After the Animator and the renderer's own writes: each blend reads the pose just made and writes over it.
local function stepBlends(dt: number)
	for blend in steppingBlends do
		blend:Step(dt, if unscaledBlends[blend] then 1 else clipScale)
		if not blend:IsActive() then steppingBlends[blend] = nil end
	end
end

EnemiesController.OnStart = function()
	-- PreSimulation runs after the Animator has posed the rigs for the frame, so these root writes land last.
	RunService.PreSimulation:Connect(function(dt: number)
		EnemyImpacts.BeginFrame()
		local budget = drainRigQueue(Tune.MAX_CLONES_PER_FRAME)
		refillReserves(budget)
		update(dt)
		stepBlends(dt)
	end)
end

EnemiesController.OnSelfCharacterAdded = function(_, characterEntity: any)
	selfEntity = characterEntity
end

EnemiesController.OnSelfCharacterRemoving = function()
	selfEntity = nil
end

return Ignis.Register(EnemiesController)
