-- The local character's own walk and idle clips (ReplicatedStorage.Animations), played on the local Animator so they
-- replicate. The places hold no Idle or Walking clips today, so Roblox's default Animate animates the R6 body, with its
-- walk swapped for Animations.Walk. Before adding clips, put an empty Animate back in StarterCharacterScripts (the
-- project files), or both play at once.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local CameraController = require(script.Parent.CameraController)
local TCharacter = require(ReplicatedStorage.Types.TCharacter)
local TCharacterEvents = require(ReplicatedStorage.Types.Events.TCharacterEvents)

local AnimationsFolder = ReplicatedStorage:WaitForChild("Animations")

local FADE_IN = 0.3
local FADE_OUT = 0.3
local IDLE_SPEED = 0.65
-- The walk clips' authored speed: at this WalkSpeed a stride is played at 1x (Roblox's default; the places set 22).
local BASE_WALK_SPEED = 16
-- Eighths of a turn clockwise from straight ahead: 1 front, 2 front-right, 3 right ... 8 front-left.
local SECTOR_ANGLE = math.pi / 4
local STANDING = 0
local FRONT = 1
-- The default Animate's walk and run Animations (R6 plays the same clip for both).
local ANIMATE_WALK_CLIPS = table.freeze({ WalkAnim = true, RunAnim = true })

local MovementController = {}

local idleTrack: AnimationTrack? = nil
local walkTracks: { AnimationTrack } = {}
-- Sector (FRONT and on, clockwise) -> the walks that make it. Indexed by a number, not a direction vector: a
-- rounded vector carries -0 where the table's key has 0.
local walksBySector: { { AnimationTrack } } = table.create(8)
local humanoid: Humanoid? = nil
local connections: { RBXScriptConnection } = {}
-- The sector walking now, so a move that stays in it (the camera turning a locked view every frame) changes nothing.
local currentSector = STANDING
-- Where the last walk was when last seen playing, at what speed, and when (resumeTime).
local lastTrack: AnimationTrack? = nil
local lastPlayedAt = 0
local lastTimePosition = 0
local lastSpeed = 1
-- The default Animate's walk, while it is the one playing.
local animateWalk: AnimationTrack? = nil
local lastIsFacingAim = false

-- The nearest of the eight sectors to `move` as seen from the camera, read off its flat right and forward so a view
-- tipped down does not squash the diagonals.
local function toSector(move: Vector3): number
	local right = Workspace.CurrentCamera.CFrame.RightVector
	local forward = Vector3.new(right.Z, 0, -right.X)
	return math.round(math.atan2(move:Dot(right), move:Dot(forward)) / SECTOR_ANGLE) % 8 + 1
end

local function walkSpeed(): number
	return if humanoid then humanoid.WalkSpeed / BASE_WALK_SPEED else 1
end

local function stopWalks()
	if lastTrack then
		lastPlayedAt = os.clock()
		lastTimePosition = lastTrack.TimePosition
		lastSpeed = lastTrack.Speed
	end

	for _, track in walkTracks do
		if track.IsPlaying then track:Stop(FADE_OUT) end
	end
end

-- Where a walk starting now picks up: the stopped one's phase moved on by the time since, inside its fade; else 0.
-- Tapping W again then carries on the stride instead of restarting it.
local function resumeTime(length: number): number
	local since = os.clock() - lastPlayedAt
	if since > FADE_OUT or length <= 0 then return 0 end
	return (lastTimePosition + since * lastSpeed) % length
end

-- The default Animate stops and destroys its walk the frame the body stops, so its phase is read while it plays.
local function sampleAnimateWalk()
	local track = animateWalk
	if not track or not track.IsPlaying then return end
	lastPlayedAt = os.clock()
	lastTimePosition = track.TimePosition
	lastSpeed = track.Speed
end

-- The default Animate loads a fresh walk for every start, from the top of the clip; picked up again within FADE_OUT
-- it carries on the stride instead.
local function onAnimationPlayed(track: AnimationTrack)
	local animation = track.Animation
	if not animation or not ANIMATE_WALK_CLIPS[animation.Name] then return end
	animateWalk = track
	track.TimePosition = resumeTime(track.Length)
end

local function load(animator: Animator, path: { string }): AnimationTrack?
	local node: Instance? = AnimationsFolder
	for _, name in path do
		node = if node then node:FindFirstChild(name) else nil
	end

	if not node or not node:IsA("Animation") then return nil end
	local track = animator:LoadAnimation(node)
	track.Looped = true
	return track
end

local function moveDirection()
	local body = humanoid
	if not body then return end
	local move = body.MoveDirection
	local sector = STANDING
	if move.Magnitude >= 0.1 and body.Health > 0 then
		-- Not facing the aim, the body turns to where it walks, so it is always walking forward.
		sector = if CameraController.IsFacingAim then toSector(move) else FRONT
	end

	if sector == currentSector then return end

	currentSector = sector
	stopWalks()
	if sector == STANDING then return end

	local tracks = walksBySector[sector]
	if not tracks or #tracks == 0 then tracks = walksBySector[FRONT] end
	if not tracks then return end

	local speed = walkSpeed()
	for _, track in tracks do
		local position = resumeTime(track.Length)
		track:Play(FADE_IN, 1, speed)
		track.TimePosition = position
		lastTrack = track
	end
end

local function adjustSpeed()
	local speed = walkSpeed()
	for _, track in walkTracks do
		if track.IsPlaying then track:AdjustSpeed(speed) end
	end
end

-- Roblox's default walk carries no Footstep marker, so FootstepsController hears nothing off it; Animations.Walk is
-- the same clip with the markers. The default Animate rebuilds a set when one of its Animations changes, and its
-- tracks replicate, so other clients hear these steps too.
local function useMarkedWalk(character: Model)
	local walk = AnimationsFolder:FindFirstChild("Walk")
	local animate = character:FindFirstChild("Animate")
	if not walk or not walk:IsA("Animation") or not animate then return end

	local walkId = walk.AnimationId
	for _, animation in animate:GetDescendants() do
		if animation:IsA("Animation") and ANIMATE_WALK_CLIPS[animation.Name] then animation.AnimationId = walkId end
	end
end

local function disconnect()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

MovementController.OnSelfCharacterAdded = function(character: TCharacter.TCharacter)
	disconnect()
	local body = character.Humanoid
	local animator = body.Animator
	humanoid = body
	currentSector = STANDING
	lastTrack = nil
	animateWalk = nil
	lastIsFacingAim = CameraController.IsFacingAim
	useMarkedWalk(character)

	idleTrack = load(animator, { "Idle" })
	if idleTrack then
		idleTrack.Priority = Enum.AnimationPriority.Idle
		idleTrack:Play(0.1, 1, IDLE_SPEED)
	end

	local front = load(animator, { "Walking", "WalkFront" })
	local back = load(animator, { "Walking", "WalkBack" })
	local left = load(animator, { "Walking", "WalkLeft" })
	local right = load(animator, { "Walking", "WalkRight" })

	table.clear(walkTracks)
	for _, track in { front, back, left, right } do
		if not track then continue end
		track.Priority = Enum.AnimationPriority.Movement
		walkTracks[#walkTracks + 1] = track
	end

	local function pair(a: AnimationTrack?, b: AnimationTrack?): { AnimationTrack }
		local tracks = {}
		if a then table.insert(tracks, a) end
		if b then table.insert(tracks, b) end
		return tracks
	end

	table.clear(walksBySector)
	walksBySector[1] = pair(front, nil)
	walksBySector[2] = pair(front, right)
	walksBySector[3] = pair(right, nil)
	walksBySector[4] = pair(back, right)
	walksBySector[5] = pair(back, nil)
	walksBySector[6] = pair(back, left)
	walksBySector[7] = pair(left, nil)
	walksBySector[8] = pair(front, left)

	connections[1] = body:GetPropertyChangedSignal("MoveDirection"):Connect(moveDirection)
	connections[2] = body:GetPropertyChangedSignal("WalkSpeed"):Connect(adjustSpeed)
	-- Facing the aim or not turns which way the body faces without the move changing, so the walk is re-picked on
	-- the frame that flips.
	connections[3] = RunService.Heartbeat:Connect(function()
		sampleAnimateWalk()
		local isFacingAim = CameraController.IsFacingAim
		if isFacingAim == lastIsFacingAim then return end
		lastIsFacingAim = isFacingAim
		moveDirection()
	end)
	connections[4] = animator.AnimationPlayed:Connect(onAnimationPlayed)
end :: TCharacterEvents.OnCharacterAdded

MovementController.OnSelfCharacterRemoving = function()
	disconnect()
	humanoid = nil
	idleTrack = nil
	lastTrack = nil
	animateWalk = nil
	table.clear(walkTracks)
	table.clear(walksBySector)
end :: TCharacterEvents.OnCharacterRemoving

return Ignis.Register(MovementController)
