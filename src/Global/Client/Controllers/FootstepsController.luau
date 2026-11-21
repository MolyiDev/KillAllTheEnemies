-- Footsteps for every character this client sees, in the lobby and the arena, out of Sounds.Footsteps.<Material>.
-- <Gait>. Five gaits: Walk and Run off the "Footstep" markers in the locomotion clips (they replicate, so a remote
-- character's steps are heard too), Wander as a scuff when turning or stopping on the spot, Jump on takeoff and Land
-- on touchdown, both off the Humanoid's state.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local TCharacter = require(ReplicatedStorage.Types.TCharacter)
local TCharacterEvents = require(ReplicatedStorage.Types.Events.TCharacterEvents)

local AnimationsFolder = ReplicatedStorage:WaitForChild("Animations")

local FOOTSTEP_MARKER = "Footstep"
-- A locomotion clip whose name starts with this is a run; any other with the marker is a walk. Read off the clip, so
-- the gait follows the animation playing rather than the speed.
local RUN_ANIM_PREFIX = "Run"

local Tune = table.freeze({
	FOOTSTEP_COOLDOWN = 0.05,
	-- Two hearings of one marker closer than this are the same marker, read a frame or two apart.
	MARKER_MERGE_SECONDS = 0.1,
	-- Pitch spread, so no two steps sound alike. A run lands harder, so its top end is wider.
	MIN_SPEED = 0.95,
	MAX_SPEED = 1.05,
	RUN_MAX_SPEED = 1.08,
	-- Volume jitter multiplies each take's own Volume, so the mix in the tree is kept and only varied.
	MIN_VOLUME_SCALE = 0.82,
	MAX_VOLUME_SCALE = 1,
	RUN_VOLUME_BOOST = 1.2,
	LAND_VOLUME_BOOST = 1.4,
	-- State flicker at an edge or on a slope flips these within a couple of frames; the cooldowns swallow it.
	LAND_COOLDOWN = 0.15,
	JUMP_COOLDOWN = 0.15,
	-- A jump below this flat speed is a hop on the spot and plays the Wander scuff instead of the Jump pool.
	JUMP_RUN_SPEED_SQ = 7 * 7,
	-- A turn sharper than this dot (about 60 degrees), a start or a stop scuffs, but only below this flat speed:
	-- past it the markers own the sound.
	WANDER_MAX_SPEED_SQ = 7 * 7,
	WANDER_DOT_THRESHOLD = 0.5,
	WANDER_COOLDOWN = 0.2,
	-- Below the hips, far enough to reach the floor on a slope.
	PROBE_BELOW_HIPS = 2,
})

-- Roblox material -> its set, Sounds.Footsteps.<Set>. Only Stone, Sand and Grass are this game's group's uploads:
-- the other sets in the tree (Concrete, Dirt, Wood, Metal...) are an earlier group's ids and play nothing here, so
-- every material steps on the nearest of the three until those are re-uploaded. Anything unmapped is
-- DEFAULT_MATERIAL.
local MATERIAL_MAP: { [Enum.Material]: string } = {
	-- Soft and muffled.
	[Enum.Material.Grass] = "Footsteps.Grass",
	[Enum.Material.LeafyGrass] = "Footsteps.Grass",
	[Enum.Material.Mud] = "Footsteps.Grass",
	[Enum.Material.Fabric] = "Footsteps.Grass",
	-- Loose and gritty.
	[Enum.Material.Sand] = "Footsteps.Sand",
	[Enum.Material.Sandstone] = "Footsteps.Sand",
	[Enum.Material.Ground] = "Footsteps.Sand",
	[Enum.Material.Pebble] = "Footsteps.Sand",
	[Enum.Material.CrackedLava] = "Footsteps.Sand",
	[Enum.Material.Snow] = "Footsteps.Sand",
	[Enum.Material.Glacier] = "Footsteps.Sand",
	[Enum.Material.Water] = "Footsteps.Sand",
	-- Hard.
	[Enum.Material.Slate] = "Footsteps.Stone",
	[Enum.Material.Rock] = "Footsteps.Stone",
	[Enum.Material.Basalt] = "Footsteps.Stone",
	[Enum.Material.Cobblestone] = "Footsteps.Stone",
	[Enum.Material.Brick] = "Footsteps.Stone",
	[Enum.Material.Limestone] = "Footsteps.Stone",
	[Enum.Material.Granite] = "Footsteps.Stone",
	[Enum.Material.Asphalt] = "Footsteps.Stone",
	[Enum.Material.Concrete] = "Footsteps.Stone",
	[Enum.Material.Plastic] = "Footsteps.Stone",
	[Enum.Material.SmoothPlastic] = "Footsteps.Stone",
	[Enum.Material.Marble] = "Footsteps.Stone",
	[Enum.Material.Glass] = "Footsteps.Stone",
	[Enum.Material.Ice] = "Footsteps.Stone",
	[Enum.Material.Wood] = "Footsteps.Stone",
	[Enum.Material.WoodPlanks] = "Footsteps.Stone",
	[Enum.Material.Metal] = "Footsteps.Stone",
	[Enum.Material.CorrodedMetal] = "Footsteps.Stone",
	[Enum.Material.DiamondPlate] = "Footsteps.Stone",
	[Enum.Material.Foil] = "Footsteps.Stone",
}
local DEFAULT_MATERIAL = "Footsteps.Stone"

-- The bags a gait draws from, first that exists: a material without a Run or Land set still steps.
local GAIT_FALLBACKS: { [string]: { string } } = {
	Walk = { "Walk" },
	Run = { "Run", "Walk" },
	Wander = { "Wander", "Walk" },
	Land = { "Land", "Run", "Walk" },
	Jump = { "Jump", "Wander", "Run", "Walk" },
}

-- Gait -> the takes it plays on one floor.
type TGaits = { [string]: { Sound } }

type TWiredTrack = {
	Connection: RBXScriptConnection,
	Gait: string,
	-- Its clip's entry in markerTimes.
	MarkerTimes: { number },
	-- Its TimePosition last frame, to see a backwards walk pass a marker.
	LastTime: number,
}

type TFootsteps = {
	Humanoid: Humanoid,
	Root: BasePart,
	RayParams: RaycastParams,
	Connections: { RBXScriptConnection },
	-- Template take -> this character's voice of it, on the root.
	Voices: { [Sound]: Sound },
	-- Keyed by track, not clip: the default Animate loads a fresh track for every walk start (after a stop, a jump)
	-- and destroys the last, so a clip's later tracks need wiring too. Dropped once not playing; played again, a track
	-- is wired again.
	WiredTracks: { [AnimationTrack]: TWiredTrack },
	LastFootstepTime: number,
	LastMoveDirection: Vector3,
	LastWanderTime: number,
	LastLandTime: number,
	LastJumpTime: number,
}

local FootstepsController = {}

-- AnimationId -> the gait its markers step, for every locomotion clip that can carry the marker.
local clipGaits: { [string]: string } = {}
-- AnimationId -> its Footstep times, learned as the markers fire forward. Roblox fires a marker only while its clip
-- plays forward, and a backpedal plays the walk backwards (BodyPoseController), so stepBackwards steps on these.
local markerTimes: { [string]: { number } } = {}
local footsteps: { [Model]: TFootsteps } = {}
-- Every floor's gaits, resolved once in OnStart, so a step reads two tables instead of walking the tree by name.
local gaitsByMaterial: { [Enum.Material]: TGaits } = {}
local defaultGaits: TGaits = {}

local enemyAnimations = AnimationsFolder:FindFirstChild("Enemies")
for _, animation in AnimationsFolder:GetDescendants() do
	if not animation:IsA("Animation") or animation:IsDescendantOf(enemyAnimations) then continue end
	local isRun = string.sub(animation.Name, 1, #RUN_ANIM_PREFIX) == RUN_ANIM_PREFIX
	clipGaits[animation.AnimationId] = if isRun then "Run" else "Walk"
end

-- The floor's gaits under the root, or nil in the air.
local function resolveGaits(state: TFootsteps): TGaits?
	local hipHeight = state.Humanoid.HipHeight
	if hipHeight <= 0 then hipHeight = 2 end
	local probe = Vector3.new(0, -(hipHeight + Tune.PROBE_BELOW_HIPS), 0)
	local hit = Workspace:Raycast(state.Root.Position, probe, state.RayParams)
	if not hit or hit.Material == Enum.Material.Air then return nil end

	return gaitsByMaterial[hit.Material] or defaultGaits
end

-- Each take plays from this character's own voice of it, cloned on first use and replayed after (a Sound's Play
-- restarts it). A take never rolls twice running and seldom within a few plays, so a replay almost never cuts its own
-- tail, and when it does the new step covers the cut.
local function playStep(state: TFootsteps, gait: string)
	local gaits = resolveGaits(state)
	if not gaits then return end
	local takes = gaits[gait]
	if not takes then return end

	local take = SoundsCore.RollTake(takes)
	local voice = state.Voices[take]
	if not voice then
		voice = take:Clone()
		voice.Parent = state.Root
		state.Voices[take] = voice
	end

	local maxSpeed = if gait == "Run" then Tune.RUN_MAX_SPEED else Tune.MAX_SPEED
	local boost = if gait == "Land" then Tune.LAND_VOLUME_BOOST elseif gait == "Run" then Tune.RUN_VOLUME_BOOST else 1
	local jitter = Tune.MIN_VOLUME_SCALE + math.random() * (Tune.MAX_VOLUME_SCALE - Tune.MIN_VOLUME_SCALE)
	voice.Volume = take.Volume * jitter * boost
	voice.PlaybackSpeed = take.PlaybackSpeed * (Tune.MIN_SPEED + math.random() * (maxSpeed - Tune.MIN_SPEED))
	voice:Play()
end

local function step(state: TFootsteps, gait: string)
	local now = os.clock()
	if now - state.LastFootstepTime < Tune.FOOTSTEP_COOLDOWN then return end
	state.LastFootstepTime = now
	playStep(state, gait)
end

local function learnMarkerTime(times: { number }, track: AnimationTrack)
	local length = track.Length
	if length <= 0 or track.Speed <= 0 then return end

	local time = track.TimePosition
	for _, known in times do
		-- The distance round the loop: the clip's last marker is heard just past its end, at the top.
		local gap = math.abs(known - time)
		if math.min(gap, length - gap) < Tune.MARKER_MERGE_SECONDS then return end
	end

	table.insert(times, time)
end

local function wireClip(state: TFootsteps, track: AnimationTrack)
	if state.WiredTracks[track] then return end
	local animationId = track.Animation.AnimationId
	local gait = clipGaits[animationId]
	if not gait then return end

	local times = markerTimes[animationId]
	if not times then
		times = {}
		markerTimes[animationId] = times
	end

	state.WiredTracks[track] = {
		Connection = track:GetMarkerReachedSignal(FOOTSTEP_MARKER):Connect(function()
			learnMarkerTime(times, track)
			step(state, gait)
		end),
		Gait = gait,
		MarkerTimes = times,
		LastTime = track.TimePosition,
	}
end

-- A walk played backwards steps on the learned marker times it passes; one played forward has its markers.
local function stepBackwards(state: TFootsteps)
	local wiredTracks = state.WiredTracks
	for track, wired in wiredTracks do
		if not track.IsPlaying then
			wired.Connection:Disconnect()
			wiredTracks[track] = nil
			continue
		end

		local time = track.TimePosition
		local previous = wired.LastTime
		wired.LastTime = time
		if track.Speed >= 0 then continue end

		-- Backwards the time only falls; a rise past half the clip is the loop from its top round to its end.
		local isWrapped = time - previous > track.Length * 0.5
		if time >= previous and not isWrapped then continue end
		for _, marker in wired.MarkerTimes do
			local isPassed = if isWrapped
				then marker <= previous or marker > time
				else marker <= previous and marker > time
			if not isPassed then continue end
			step(state, wired.Gait)
			break
		end
	end
end

-- The scuff of turning or stopping on the spot. No clip shows a pivot, so it rides MoveDirection, which replicates.
local function onMoveDirection(state: TFootsteps)
	local previous = state.LastMoveDirection
	local current = state.Humanoid.MoveDirection
	state.LastMoveDirection = current

	local velocity = state.Root.AssemblyLinearVelocity
	if velocity.X * velocity.X + velocity.Z * velocity.Z > Tune.WANDER_MAX_SPEED_SQ then return end
	-- A start or a stop always qualifies: one side is the zero vector.
	if previous:Dot(current) >= Tune.WANDER_DOT_THRESHOLD then return end
	local now = os.clock()
	if now - state.LastWanderTime < Tune.WANDER_COOLDOWN then return end
	state.LastWanderTime = now

	playStep(state, "Wander")
end

-- The default Humanoid lands through Landed, or straight from Freefall into Running on a short drop.
local function onStateChanged(state: TFootsteps, old: Enum.HumanoidStateType, new: Enum.HumanoidStateType)
	local now = os.clock()
	if new == Enum.HumanoidStateType.Jumping then
		if now - state.LastJumpTime < Tune.JUMP_COOLDOWN then return end
		state.LastJumpTime = now
		local velocity = state.Root.AssemblyLinearVelocity
		local flatSq = velocity.X * velocity.X + velocity.Z * velocity.Z
		playStep(state, if flatSq < Tune.JUMP_RUN_SPEED_SQ then "Wander" else "Jump")
		return
	end

	local isLanding = new == Enum.HumanoidStateType.Landed
		or (new == Enum.HumanoidStateType.Running and old == Enum.HumanoidStateType.Freefall)
	if not isLanding or now - state.LastLandTime < Tune.LAND_COOLDOWN then return end
	state.LastLandTime = now
	playStep(state, "Land")
end

-- A set's takes per gait, the first bag down GAIT_FALLBACKS that exists, else `fallback`'s for that gait. A gait
-- with neither stays absent and is silent.
local function resolveSet(set: string, fallback: TGaits): TGaits
	local gaits: TGaits = {}
	for gait, bags in GAIT_FALLBACKS do
		for _, bag in bags do
			local takes = SoundsCore.FindTakes(set, bag)
			if not takes then continue end
			gaits[gait] = takes
			break
		end
		if not gaits[gait] then gaits[gait] = fallback[gait] end
	end

	return gaits
end

-- The tree is whole by now (SoundsCore read all of it when it loaded), and it does not change in a session.
FootstepsController.OnStart = function()
	defaultGaits = resolveSet(DEFAULT_MATERIAL, {})

	-- Several materials share a set: each set is resolved once.
	local bySet: { [string]: TGaits } = { [DEFAULT_MATERIAL] = defaultGaits }
	for material, set in MATERIAL_MAP do
		local gaits = bySet[set]
		if not gaits then
			gaits = resolveSet(set, defaultGaits)
			bySet[set] = gaits
		end
		gaitsByMaterial[material] = gaits
	end

	RunService.Heartbeat:Connect(function()
		for _, state in footsteps do
			stepBackwards(state)
		end
	end)
end

FootstepsController.OnCharacterAdded = function(character: TCharacter.TCharacter)
	local humanoid = character.Humanoid
	local root = character.HumanoidRootPart

	-- Never an enemy: their rigs sit at the origin (TData.TEnemyModel).
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local enemies = Workspace:FindFirstChild("Enemies")
	rayParams.FilterDescendantsInstances = if enemies then { character, enemies } else { character }

	local state: TFootsteps = {
		Humanoid = humanoid,
		Root = root,
		RayParams = rayParams,
		Connections = {},
		Voices = {},
		WiredTracks = {},
		LastFootstepTime = 0,
		LastMoveDirection = Vector3.zero,
		LastWanderTime = 0,
		LastLandTime = 0,
		LastJumpTime = 0,
	}
	footsteps[character] = state

	local connections = state.Connections
	table.insert(
		connections,
		humanoid.Animator.AnimationPlayed:Connect(function(track: AnimationTrack)
			wireClip(state, track)
		end)
	)
	table.insert(
		connections,
		humanoid:GetPropertyChangedSignal("MoveDirection"):Connect(function()
			onMoveDirection(state)
		end)
	)
	table.insert(
		connections,
		humanoid.StateChanged:Connect(function(old, new)
			onStateChanged(state, old, new)
		end)
	)
	-- Clips already playing when the character reached this client.
	for _, track in humanoid.Animator:GetPlayingAnimationTracks() do
		wireClip(state, track)
	end
end :: TCharacterEvents.OnCharacterAdded

FootstepsController.OnCharacterRemoving = function(character: TCharacter.TCharacter)
	local state = footsteps[character]
	if not state then return end
	footsteps[character] = nil

	for _, connection in state.Connections do
		connection:Disconnect()
	end
	for _, wired in state.WiredTracks do
		wired.Connection:Disconnect()
	end
	-- Not left to the body's own end: this module does not decide when, or whether, the model is destroyed.
	for _, voice in state.Voices do
		voice:Destroy()
	end
end :: TCharacterEvents.OnCharacterRemoving

return Ignis.Register(FootstepsController)
