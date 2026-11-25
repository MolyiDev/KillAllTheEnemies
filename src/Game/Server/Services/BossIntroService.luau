-- A boss's arrival (PlanBosses.md): it is placed on a stage facing the party, shown to everyone, and the whole match
-- is held at once while its intro plays (BossIntroController), every time a boss comes on. Nobody can be hurt while
-- it plays (CharacterService), and anyone joining meanwhile is simply held with the rest.
--
-- The stage is picked here, not kept per map: a spot round the party with floor for the walk-in and the body, whose
-- intro shots (BossesCore.INTRO_SHOTS) see the boss past the arena, so every map's intro frames it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local Network = require(ServerScriptService.GlobalServer.Network)
local EnemiesService = require(script.Parent.EnemiesService)
local TimeService = require(script.Parent.TimeService)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local ArenaCore = require(ReplicatedStorage.Shared.Core.ArenaCore)
local BossesCore = require(ReplicatedStorage.Shared.Core.BossesCore)
local TimeCore = require(ReplicatedStorage.Shared.Core.TimeCore)
local Components = require(ReplicatedStorage.GlobalShared.ECS.Components)
local Tags = require(ReplicatedStorage.GlobalShared.ECS.Tags)
local EnemyWorld = require(ReplicatedStorage.GlobalShared.ECS.Worlds.EnemyWorld)
local World = require(ReplicatedStorage.GlobalShared.ECS.Worlds.World)
local getCharacterFeet = require(ReplicatedStorage.GlobalShared.Utils.Functions.getCharacterFeet)
local TData = require(ReplicatedStorage.Types.TData)

local ServerNetworkBosses = Network.Server.Bosses

local ENEMIES = DataCore.Enemies.ById
local CharactersQuery =
	World:query(Components.HumanoidRootPart, Components.Humanoid):with(Tags.Character, Tags.Alive):cached()

local Tune = table.freeze({
	-- Stages tried round the party's middle: these distances, this many directions each. The first is the one wanted.
	RADII = table.freeze({ 50, 40, 62 }),
	DIRECTIONS = 12,
	-- A stage's floor is within this of the party's.
	LEVEL = 6,
	-- The body and its walk-in need floor here, in its own frame (x right, z ahead), each within FLOOR_MATCH of the
	-- stage's: its width, from the tail at the walk-in's start to the snout.
	ROOM_X = table.freeze({ -10, 0, 10 }),
	ROOM_Z = table.freeze({ -32.5, -20, -7.5, 5, 17.5, 25 }),
	FLOOR_MATCH = 2.5,
	-- A shot whose camera the arena hides from the boss's head (this high) costs this many floor samples.
	HEAD = 8.75,
	SHOT_COST = 3,
	-- Only the arena blocks a shot.
	PROBE_UP = 20,
})

local BossIntroService = {}

-- Real seconds the hold has left; 0 for none.
local holdLeft = 0
local sightParams = RaycastParams.new()
sightParams.FilterType = Enum.RaycastFilterType.Include

-- Where the party stands: the middle of everyone standing, nil for nobody.
local function partyMiddle(): vector?
	local sum = vector.zero
	local count = 0
	for _, rootPart, humanoid in CharactersQuery do
		sum += getCharacterFeet(rootPart, humanoid, 0)
		count += 1
	end

	return if count > 0 then sum / count else nil
end

local function scoreStage(
	stage: CFrame,
	floorY: number,
	shots: { { BossesCore.TShotKey } }?,
	intro: TData.TEnemyBossIntro?
): number
	local score = 0
	for _, x in Tune.ROOM_X do
		for _, z in Tune.ROOM_Z do
			local point = stage:PointToWorldSpace(Vector3.new(x, 0, z))
			local y = ArenaCore.GetFloorY(point.X, point.Z, floorY + Tune.LEVEL)
			if y and math.abs(y - floorY) <= Tune.FLOOR_MATCH then
				score += 1
			end
		end
	end

	local arena = Workspace:FindFirstChild("Arena")
	if not shots or not intro or not arena then return score end
	sightParams.FilterDescendantsInstances = { arena }
	local frame = BossesCore.IntroFrame(stage, intro)
	local head = stage.Position + Vector3.new(0, Tune.HEAD, 0)
	for _, shot in shots do
		local eye = frame:PointToWorldSpace(shot[1].Eye * BossesCore.INTRO_KEY_SCALE)
		if Workspace:Raycast(head, eye - head, sightParams) then
			score -= Tune.SHOT_COST
		end
	end

	return score
end

-- (feet, yaw) for `enemyData`'s stage: facing the party from round it, where the most room and the clearest shots are.
function BossIntroService.PickStage(enemyData: TData.TEnemy): (vector?, number)
	local middle = partyMiddle()
	if not middle then return nil, 0 end
	local kit = enemyData.Boss
	local shots = BossesCore.INTRO_SHOTS[enemyData.AnimationSet]
	local best: vector? = nil
	local bestYaw, bestScore = 0, -math.huge

	for _, radius in Tune.RADII do
		for i = 0, Tune.DIRECTIONS - 1 do
			local angle = i / Tune.DIRECTIONS * 2 * math.pi
			local x, z = middle.x + math.sin(angle) * radius, middle.z + math.cos(angle) * radius
			local y = ArenaCore.GetFloorY(x, z, middle.y + Tune.PROBE_UP)
			if not y or math.abs(y - middle.y) > Tune.LEVEL then continue end
			-- Facing the party: the yaw whose forward points from the stage at the middle.
			local yaw = math.atan2(middle.x - x, middle.z - z)
			local stage = CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0)
			-- Ties go to the first distance tried.
			local score = scoreStage(stage, y, shots, if kit then kit.Intro else nil)
			if score <= bestScore then continue end
			bestScore = score
			best = vector.create(x, y, z)
			bestYaw = yaw
		end
	end

	return best, bestYaw
end

-- Spawns boss `dataId` on its stage and plays its intro for everyone. Returns its entity, or nil when it could not
-- (no room, nobody standing). Waits on nothing: the caller holds the spawn while an upgrade hand is open.
function BossIntroService.Arrive(dataId: number, healthScale: number?, damageScale: number?): any?
	local enemyData = ENEMIES[dataId]
	if not enemyData then return nil end
	local position, yaw = BossIntroService.PickStage(enemyData)
	if not position then return nil end
	local instanceId, entity = EnemiesService.Spawn(dataId, position, healthScale, damageScale, 1)
	if not instanceId or not entity then return nil end
	EnemyWorld:set(entity, Components.Yaw, yaw)
	EnemiesService.ShowBodyToEveryone(instanceId)

	local kit = enemyData.Boss
	if not kit then return entity end
	TimeService.SetCutscene(true)
	holdLeft = BossesCore.IntroSeconds(kit.Intro)
	ServerNetworkBosses.Intro.FireAll(instanceId, dataId, position :: any, yaw)
	return entity
end

-- Real time, since the match's clocks are what it holds.
RunService.Heartbeat:Connect(function(dt: number)
	if holdLeft <= 0 then return end
	-- A run reset let go of the hold already (TimeCore.Reset).
	if not TimeCore.IsCutscene then
		holdLeft = 0
		return
	end

	holdLeft -= dt
	if holdLeft <= 0 then TimeService.SetCutscene(false) end
end)

return Ignis.Register(BossIntroService)
