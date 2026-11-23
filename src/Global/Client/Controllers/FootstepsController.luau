-- Footsteps for every character this client sees, in the lobby and the arena, out of Sounds.Footsteps.<Material>.
-- <Gait>. Walk and Run off the "Footstep" markers in the locomotion clips (they replicate, so a remote character's
-- steps are heard too), Wander as a scuff when turning or stopping on the spot, Skid on a hard turn and Start on
-- setting off from a stand (both the Skid takes), Jump on takeoff and Land on touchdown, both off the Humanoid's state.
-- Each is also seen: the floor's dust at the feet (Utils/stepFx).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local stepFx = require(script.Parent.Parent.Utils.stepFx)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local sightCast = require(ReplicatedStorage.GlobalShared.Utils.sightCast)
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
	-- A landing looks this much further: the Humanoid says Landed while the body is still coming down (measured in
	-- play: the root 1.1 studs over where it comes to rest, a tenth of a stud past the probe).
	PROBE_LANDING = 3,
	-- A body with no legs to read: each foot's dust is this far to its side of the root.
	FOOT_SPREAD = 0.45,
	-- Feet nearer level than this are both down (standing, a landing): they take turns.
	FEET_LEVEL = 0.05,
	-- Coming down from lower than this (studs: off a stair, a state flicker) is seen as a step, not a landing.
	LAND_DROP = 1.2,
	-- A landing grows from a jump's on the flat (7.2 studs) to its biggest at a long fall's.
	HEAVY_DROP_MIN = 9,
	HEAVY_DROP_MAX = 31,
	-- A skid: the body was going faster than this when it let go of a way, and within SKID_MEMORY seconds is told
	-- to go one whose dot with it is under SKID_DOT (a turn sharper than about 70 degrees).
	SKID_MIN_SPEED_SQ = 5 * 5,
	SKID_MEMORY = 0.3,
	SKID_DOT = 0.35,
	SKID_COOLDOWN = 0.15,
	-- Setting off from a stand throws this much of a skid (0 its least, 1 a straight reversal), backwards.
	START_SHARPNESS = 0.4,
	-- Under an invisible floor, how far down the floor that is seen is looked for.
	SEEN_FLOOR_BELOW = 4,
	BODY_RADIUS = 0.9,
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
	Skid = { "Skid" },
	Start = { "Skid" },
}

-- A gait's volume over its takes' own; a gait not named plays them as they are.
local GAIT_VOLUME_SCALE: { [string]: number } = table.freeze({
	Run = 1.2,
	Land = 1.4,
	-- 2 dB under a skid (Assets/sounds/Review/Skid): a start is heard every time a body sets off.
	Start = 0.79,
})

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
	-- How far under the root's centre the floor is looked for: its hips and PROBE_BELOW_HIPS.
	ProbeReach: number,
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
	LastSkidTime: number,
	-- The last way it was told to go, how fast it was going when that ended, and when.
	Heading: Vector3,
	HeadingSpeedSq: number,
	HeadingTime: number,
	-- The legs its feet are the bottom of, found on the first step after they replicate, and half their height.
	LeftLeg: BasePart?,
	RightLeg: BasePart?,
	LegHalf: number,
	-- Which foot stepped last, for when the legs cannot say: their dust takes turns.
	IsLeftStep: boolean,
	-- Off the floor, and the highest its root has been since it left: how far it comes down is how hard it lands.
	-- Positions, not velocity: another player's velocity is not what replicates, and its own is already zero by the
	-- time the state says it landed.
	IsInAir: boolean,
	PeakY: number,
	-- This time in the air began with a jump.
	DidJump: boolean,
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
	if not animation:IsA("Animation") then continue end
	-- The lobby has no Enemies folder, and IsDescendantOf(nil) is true for everything: it would skip every clip.
	if enemyAnimations and animation:IsDescendantOf(enemyAnimations) then continue end
	local isRun = string.sub(animation.Name, 1, #RUN_ANIM_PREFIX) == RUN_ANIM_PREFIX
	clipGaits[animation.AnimationId] = if isRun then "Run" else "Walk"
end

-- The floor under the root, or nil in the air.
local function floorUnder(state: TFootsteps, isLanding: boolean?): RaycastResult?
	local reach = state.ProbeReach + (if isLanding then Tune.PROBE_LANDING else 0)
	local probe = Vector3.new(0, -reach, 0)
	local origin, params = state.Root.Position, state.RayParams
	local hit = Workspace:Raycast(origin, probe, params)
	-- On an edge the root's centre is past it: a ball as wide as the body still finds what holds it up.
	if not hit then
		local radius = Tune.BODY_RADIUS
		hit = Workspace:Spherecast(origin, radius, probe + Vector3.new(0, radius, 0), params)
	end
	if not hit or hit.Material == Enum.Material.Air then return nil end
	if (hit.Instance :: BasePart).Transparency < 1 then return hit end

	-- An invisible floor (a ramp laid over steps, a cap): what is stepped on, to the eye and the ear, is the floor
	-- seen under it.
	local seen = sightCast(hit.Position, Vector3.new(0, -Tune.SEEN_FLOOR_BELOW, 0), params)
	return seen or hit
end

-- The colour a floor's dust and pieces take, or nil for an invisible one with nothing seen close under it (a cap
-- players stand on): dust off thin air.
local function floorColorOf(floor: RaycastResult): Color3?
	local part = floor.Instance :: BasePart
	if part.Transparency >= 1 then return nil end

	return part.Color
end

-- Each take plays from this character's own voice of it, cloned on first use and replayed after (a Sound's Play
-- restarts it). A take never rolls twice running and seldom within a few plays, so a replay almost never cuts its own
-- tail, and when it does the new step covers the cut.
local function playStep(state: TFootsteps, gait: string, floor: RaycastResult)
	local gaits = gaitsByMaterial[floor.Material] or defaultGaits
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
	local boost = GAIT_VOLUME_SCALE[gait] or 1
	local jitter = Tune.MIN_VOLUME_SCALE + math.random() * (Tune.MAX_VOLUME_SCALE - Tune.MIN_VOLUME_SCALE)
	voice.Volume = take.Volume * jitter * boost
	voice.PlaybackSpeed = take.PlaybackSpeed * (Tune.MIN_SPEED + math.random() * (maxSpeed - Tune.MIN_SPEED))
	voice:Play()
end

-- Where on the floor the foot that just stepped is. Which foot: the one its clip's marker names (`foot`, "Left" or
-- "Right": the game's own walk clips say), else the lower one, which is the one any walk or run has just put down.
-- Level feet (standing, a landing), or a body whose feet are not found, take turns.
local function footOn(state: TFootsteps, floor: RaycastResult, foot: string?): Vector3
	local isLeft = not state.IsLeftStep
	local left, right = state.LeftLeg, state.RightLeg
	if not left or not right then
		local character = state.Root.Parent
		if character then
			left = character:FindFirstChild("Left Leg") :: BasePart?
			right = character:FindFirstChild("Right Leg") :: BasePart?
		end
		if not left or not right then
			state.IsLeftStep = isLeft
			local spread = if isLeft then -Tune.FOOT_SPREAD else Tune.FOOT_SPREAD
			return floor.Position + state.Root.CFrame.RightVector * spread
		end
		state.LeftLeg, state.RightLeg, state.LegHalf = left, right, left.Size.Y / 2
	end

	local normal, origin = floor.Normal, floor.Position
	local sole = Vector3.new(0, -state.LegHalf, 0)
	local leftSole, rightSole = left.CFrame * sole, right.CFrame * sole
	local leftHeight, rightHeight = (leftSole - origin):Dot(normal), (rightSole - origin):Dot(normal)
	if foot == "Left" or foot == "Right" then
		isLeft = foot == "Left"
	elseif math.abs(leftHeight - rightHeight) > Tune.FEET_LEVEL then
		isLeft = leftHeight < rightHeight
	end
	state.IsLeftStep = isLeft

	return if isLeft then leftSole - normal * leftHeight else rightSole - normal * rightHeight
end

-- A step's dust under the foot that took it, kicked back from the way the body is going.
local function showStep(state: TFootsteps, floor: RaycastResult, isRun: boolean, foot: string?)
	local color = floorColorOf(floor)
	if not color then return end

	local velocity = state.Root.AssemblyLinearVelocity
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	local back = if flat.Magnitude > 1 then -flat.Unit else Vector3.zero
	stepFx.Step(footOn(state, floor, foot), floor.Normal, color, back, isRun)
end

local function step(state: TFootsteps, gait: string, foot: string?)
	local now = os.clock()
	if now - state.LastFootstepTime < Tune.FOOTSTEP_COOLDOWN then return end
	state.LastFootstepTime = now
	local floor = floorUnder(state)
	if not floor then return end

	playStep(state, gait, floor)
	showStep(state, floor, gait == "Run", foot)
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
		Connection = track:GetMarkerReachedSignal(FOOTSTEP_MARKER):Connect(function(foot: string?)
			learnMarkerTime(times, track)
			step(state, gait, foot)
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

-- A body told to go another way while it still carries the speed of the way it was going: its feet tear at the
-- floor, and what they tear off keeps going the old way. A body setting off from a stand pushes the floor back the
-- same way, less of it. Returns whether it was thrown.
local function skid(state: TFootsteps, previous: Vector3, wanted: Vector3, now: number): boolean
	if state.IsInAir or now - state.LastSkidTime < Tune.SKID_COOLDOWN then return false end

	local along: Vector3, sharpness: number, gait: string
	local wantedUnit = wanted.Unit
	if now - state.HeadingTime <= Tune.SKID_MEMORY and state.HeadingSpeedSq >= Tune.SKID_MIN_SPEED_SQ then
		local heading = state.Heading.Unit
		local dot = heading:Dot(wantedUnit)
		if dot >= Tune.SKID_DOT then return false end
		along, sharpness, gait = heading, (Tune.SKID_DOT - dot) / (Tune.SKID_DOT + 1), "Skid"
	elseif previous == Vector3.zero then
		along, sharpness, gait = -wantedUnit, Tune.START_SHARPNESS, "Start"
	else
		return false
	end
	local floor = floorUnder(state)
	local color = if floor then floorColorOf(floor) else nil
	if not floor or not color then return false end

	state.LastSkidTime = now
	state.HeadingSpeedSq = 0
	playStep(state, gait, floor)
	stepFx.Skid(floor.Position, floor.Normal, color, along, sharpness)
	return true
end

-- The scuff of turning or stopping on the spot, and the skid of turning hard at speed. No clip shows a pivot, so
-- both ride MoveDirection, which replicates.
local function onMoveDirection(state: TFootsteps)
	local previous = state.LastMoveDirection
	local current = state.Humanoid.MoveDirection
	state.LastMoveDirection = current

	local now = os.clock()
	local velocity = state.Root.AssemblyLinearVelocity
	local flatSq = velocity.X * velocity.X + velocity.Z * velocity.Z
	-- The way it was going and how fast, kept from the moment that way is let go: the keys of a quick left-right
	-- overlap or leave a gap (the direction passes through nothing), and by the time the new way arrives the body
	-- has already slowed.
	if previous ~= Vector3.zero then
		state.Heading = previous
		state.HeadingSpeedSq = flatSq
		state.HeadingTime = now
	end
	local hasSkidded = current ~= Vector3.zero and skid(state, previous, current, now)

	-- The skid's take and dust are the scuff's, and more of them.
	if hasSkidded or flatSq > Tune.WANDER_MAX_SPEED_SQ then return end
	-- A start or a stop always qualifies: one side is the zero vector.
	if previous:Dot(current) >= Tune.WANDER_DOT_THRESHOLD then return end
	if now - state.LastWanderTime < Tune.WANDER_COOLDOWN then return end
	state.LastWanderTime = now
	local floor = floorUnder(state)
	if not floor then return end

	playStep(state, "Wander", floor)
	showStep(state, floor, false)
end

-- A body lands when it was in the air and its state is back on the ground: through Landed, or straight into Running
-- from Freefall (a short drop) or from Jumping (a hop that never fell).
local function onStateChanged(state: TFootsteps, new: Enum.HumanoidStateType)
	local now = os.clock()
	local wasInAir, didJump = state.IsInAir, state.DidJump
	local isInAir = new == Enum.HumanoidStateType.Jumping or new == Enum.HumanoidStateType.Freefall
	if isInAir and not wasInAir then state.PeakY = state.Root.Position.Y end
	state.IsInAir = isInAir
	state.DidJump = isInAir and (didJump or new == Enum.HumanoidStateType.Jumping)

	if new == Enum.HumanoidStateType.Jumping then
		if now - state.LastJumpTime < Tune.JUMP_COOLDOWN then return end
		state.LastJumpTime = now
		local floor = floorUnder(state)
		if not floor then return end

		local velocity = state.Root.AssemblyLinearVelocity
		local flatSq = velocity.X * velocity.X + velocity.Z * velocity.Z
		playStep(state, if flatSq < Tune.JUMP_RUN_SPEED_SQ then "Wander" else "Jump", floor)
		local color = floorColorOf(floor)
		if color then stepFx.Jump(floor.Position, floor.Normal, color) end
		return
	end

	local isGrounded = new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running
	if not wasInAir or not isGrounded or now - state.LastLandTime < Tune.LAND_COOLDOWN then return end
	state.LastLandTime = now
	local floor = floorUnder(state, true)
	if not floor then return end

	playStep(state, "Land", floor)
	-- A jump always lands as one, even onto a ledge as high as it went; a fall has to come down some way.
	local drop = math.max(state.PeakY - state.Root.Position.Y, 0)
	if not didJump and drop < Tune.LAND_DROP then
		showStep(state, floor, false)
		return
	end
	local color = floorColorOf(floor)
	if not color then return end

	local heavy = (drop - Tune.HEAVY_DROP_MIN) / (Tune.HEAVY_DROP_MAX - Tune.HEAVY_DROP_MIN)
	stepFx.Land(floor.Position, floor.Normal, color, math.clamp(heavy, 0, 1))
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
		stepFx.BeginFrame()
		for _, state in footsteps do
			stepBackwards(state)
			if state.IsInAir then state.PeakY = math.max(state.PeakY, state.Root.Position.Y) end
		end
	end)
end

FootstepsController.OnCharacterAdded = function(character: TCharacter.TCharacter)
	local humanoid = character.Humanoid
	local root = character.HumanoidRootPart

	-- Never an enemy: their rigs sit at the origin (TData.TEnemyModel).
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	-- Only what a body stands on: the maps lay walk-through things on their floors (invisible texture patches, grass
	-- tufts, flowers, zones), and a ray that stops on one steps on the wrong material and draws its dust on nothing.
	rayParams.RespectCanCollide = true
	local enemies = Workspace:FindFirstChild("Enemies")
	rayParams.FilterDescendantsInstances = if enemies then { character, enemies } else { character }

	-- A body with no hip height (R6) stands its legs' 2 studs over the floor.
	local hipHeight = humanoid.HipHeight
	local state: TFootsteps = {
		Humanoid = humanoid,
		Root = root,
		RayParams = rayParams,
		ProbeReach = (if hipHeight > 0 then hipHeight else 2) + Tune.PROBE_BELOW_HIPS,
		Connections = {},
		Voices = {},
		WiredTracks = {},
		LastFootstepTime = 0,
		LastMoveDirection = Vector3.zero,
		LastWanderTime = 0,
		LastLandTime = 0,
		LastJumpTime = 0,
		LastSkidTime = 0,
		Heading = Vector3.zero,
		HeadingSpeedSq = 0,
		HeadingTime = 0,
		LeftLeg = nil,
		RightLeg = nil,
		LegHalf = 1,
		IsLeftStep = false,
		IsInAir = false,
		PeakY = 0,
		DidJump = false,
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
		humanoid.StateChanged:Connect(function(_, new)
			onStateChanged(state, new)
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
