-- What both sides need to agree on about enemies: the population cap, the spatial hash every positional
-- question goes through, where a body is aimed at, how much of the view it fills, and which rig it wears.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SpatialHash = require(ReplicatedStorage.GlobalShared.Utils.SpatialHash)
local TData = require(ReplicatedStorage.Types.TData)

local EnemiesCore = {}

-- HOW MANY CAN BE ALIVE AT ONCE. A crowd small enough that one main-thread update
-- moves it with room to spare (no Actors, no snapshot packing, no decoding), and every body can afford real
-- behaviour - attacks with wind-ups, staggers, readable swings - instead of being a dot in a flow field.
--
-- 255 IS THE HIGHLIGHT CEILING. Every living body carries its own hit-flash Highlight (EnemiesController says why they
-- are never pooled or re-aimed), and the engine renders 255 Highlights across the whole DataModel. A client only holds
-- rigs for the enemies it has been shown (AOIService), so it is usually under this; when it is not, a dying body's
-- death flash is what gives way (EnemiesController.MAX_HIGHLIGHTS), never a living body's hit flash. Nothing else in
-- the game may use a Highlight.
--
-- Spawning HOLDS at the cap rather than dropping (RoundService), so a stalled team faces a steady press instead
-- of a round quietly deleting itself.
EnemiesCore.MAX_ALIVE = 255

-- Every positional query about enemies goes through here, on both sides. The rigs are useless for it: each body is a
-- skinned MeshPart anchored at the origin with its root bone carrying the world CFrame, so raycasts and
-- GetPartBoundsInBox see the whole crowd stacked at (0,0,0). Its cross-cell coordinates and shape broad-phase carry the
-- fixes in performance/audit-2026-10-21/REPORT.md.
EnemiesCore.EnemiesSpatialHash = SpatialHash.new()

-- Where the blow lands in every enemy attack clip, in seconds (tools/rig/r6_zombie.py IMPACT). The renderer plays a
-- clip at ATTACK_CLIP_IMPACT / Delay speed, so the swing meets the server's wind-up whatever the attack's Delay.
EnemiesCore.ATTACK_CLIP_IMPACT = 0.6

-- The Nuke All blast: it rolls out from where it was set off at this many studs a second, killing what it reaches, and
-- after this long everything still alive goes with it. The server kills by them and the client draws its front by them.
EnemiesCore.NUKE_SPEED = 110
EnemiesCore.NUKE_SECONDS = 1.1

local ModelsFolder = ReplicatedStorage:WaitForChild("Models")
local EnemyModelsFolder = ModelsFolder:WaitForChild("Enemies")

local models: { [number]: TData.TEnemyModel } = {}

-- ============================== What an enemy is aimed at ==============================
-- Components.Position is the FEET. Everything that aims (a shot, a swing's arc, a damage number) wants the chest,
-- measured once here so the point a hit is scored against and the point its visual goes to are the same point.
-- Measured off the RIG rather than CollisionSize, because the rig is what the player is looking at and cannot drift
-- from itself; CollisionSize is only the fallback for a type whose rig is not in the place yet.
local AIM_CHEST_FRACTION = 0.65

-- (chest height above the feet, full height, horizontal half-width), one vector so a per-enemy gather reads all
-- three with one ECS get. Height and width stay apart so a tall body is not judged as a ball as wide as it is tall.
local aimShapes: { [number]: vector } = {}

-- An enemy's clips, resolved from its AnimationSet and cached. Anything missing comes back nil (the body then holds
-- its rest pose for that state) and is warned about once, so a place without the clips still plays.
export type TClips = {
	Idle: Animation?,
	Walk: Animation?,
	-- Played on a kill instead of the ragdoll, held on its last frame (TEnemy.AnimationSet).
	Death: Animation?,
	-- By attack index.
	Attacks: { [number]: Animation },
	-- Every clip in the set, by name: a boss's moves play more than its attacks' (BossController).
	Named: { [string]: Animation },
}

local clips: { [number]: TClips } = {}

-- The rig an enemy wears. Resolved by name and cached, so a data file can load before its model has been put
-- in the place; a missing model is an error at the first spawn of that type, with the name in it.
function EnemiesCore.GetModel(enemyData: TData.TEnemy): TData.TEnemyModel
	local cached = models[enemyData.Id]
	if cached then return cached end
	local model = EnemyModelsFolder:FindFirstChild(enemyData.ModelName)
	assert(model, `[EnemiesCore] no rig ReplicatedStorage.Models.Enemies.{enemyData.ModelName}`)
	models[enemyData.Id] = model :: any
	return model :: any
end

function EnemiesCore.HasModel(enemyData: TData.TEnemy): boolean
	return models[enemyData.Id] ~= nil or EnemyModelsFolder:FindFirstChild(enemyData.ModelName) ~= nil
end

function EnemiesCore.AimShape(enemyData: TData.TEnemy): vector
	local cached = aimShapes[enemyData.Id]
	if cached then return cached end
	-- A long body's extents are mostly head and tail, far off its feet: its first piece is its trunk.
	local pieces = enemyData.AimPieces
	if pieces then
		local trunk = pieces[1]
		local shape =
			vector.create(trunk.Bottom + trunk.Height * AIM_CHEST_FRACTION, trunk.Bottom + trunk.Height, trunk.Radius)
		aimShapes[enemyData.Id] = shape
		return shape
	end

	local size = if EnemiesCore.HasModel(enemyData)
		then EnemiesCore.GetModel(enemyData):GetExtentsSize()
		else enemyData.CollisionSize
	local shape = vector.create(size.Y * AIM_CHEST_FRACTION, size.Y, math.max(size.X, size.Z) * 0.5)
	aimShapes[enemyData.Id] = shape
	return shape
end

-- (height of its centre over the feet, radius): a ball holding the whole body, which is what the view culls test
-- (AOIService, EnemyPacker, EnemiesController), since the feet alone hide a body whose head is on screen. Centred over
-- the root and reaching the far corner of the rig's box, as the T-Rex's root sits well off the middle of a rig 41 studs
-- long; grown for the clips, which reach past the rest pose (its bite, 26.9 ahead).
local VIEW_POSE_MARGIN = 1.25

local viewSpheres: { [number]: vector } = {}

-- `rootOffset`: the root (the feet) in the frame of the upright box `size`.
local function sphereOver(size: Vector3, rootOffset: Vector3): vector
	local reachX = math.abs(rootOffset.X) + size.X * 0.5
	local reachY = size.Y * 0.5
	local reachZ = math.abs(rootOffset.Z) + size.Z * 0.5
	local radius = math.sqrt(reachX * reachX + reachY * reachY + reachZ * reachZ) * VIEW_POSE_MARGIN
	return vector.create(-rootOffset.Y, radius, 0)
end

function EnemiesCore.ViewSphere(enemyData: TData.TEnemy): vector
	local cached = viewSpheres[enemyData.Id]
	if cached then return cached end
	local sphere
	if EnemiesCore.HasModel(enemyData) then
		local model = EnemiesCore.GetModel(enemyData)
		local box, size = model:GetBoundingBox()
		sphere = sphereOver(size, box:PointToObjectSpace(model.PrimaryPart.Root.WorldPosition))
	else
		local size = enemyData.CollisionSize
		sphere = sphereOver(size, Vector3.new(0, -size.Y * 0.5, 0))
	end

	viewSpheres[enemyData.Id] = sphere
	return sphere
end

function EnemiesCore.GetClips(enemyData: TData.TEnemy): TClips
	local cached = clips[enemyData.Id]
	if cached then return cached end
	local animations = ReplicatedStorage:FindFirstChild("Animations")
	local enemies = if animations then animations:FindFirstChild("Enemies") else nil
	local set = if enemies then enemies:FindFirstChild(enemyData.AnimationSet) else nil
	if not set then warn(`[EnemiesCore] no clips ReplicatedStorage.Animations.Enemies.{enemyData.AnimationSet}`) end
	local function find(name: string): Animation?
		local clip = if set then set:FindFirstChild(name) else nil
		return if clip and clip:IsA("Animation") then clip else nil
	end

	local attacks: { [number]: Animation } = {}
	for i, attack in enemyData.Attacks do
		local clip = find(attack.AnimationName or "Attack")
		if clip then attacks[i] = clip end
	end

	local named: { [string]: Animation } = {}
	if set then
		for _, clip in set:GetChildren() do
			if clip:IsA("Animation") then named[clip.Name] = clip end
		end
	end

	local result: TClips =
		{ Idle = find("Idle"), Walk = find("Walk"), Death = find("Death"), Attacks = attacks, Named = named }
	clips[enemyData.Id] = result
	return result
end

return EnemiesCore
