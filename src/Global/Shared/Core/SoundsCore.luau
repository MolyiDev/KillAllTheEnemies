-- Plays the clips under ReplicatedStorage.Sounds (sounds/Sounds.rbxmx, built by tools/sounds/build.luau). A cue is
-- named by its folder: ("Enemies.Kills", "Kill") is Sounds.Enemies.Kills.Kill. Every lookup is nil-safe, so a cue can
-- be wired before its clips are in the tree and stays silent until they are.
--
-- A folder of Sounds is a bag of takes, and one is rolled per play. A Sound's level is its Volume in the tree, so the
-- mix is tuned there.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ESoundGroups = require(ReplicatedStorage.Types.Enums.Sounds.ESoundGroups)
local ESoundsIds = require(ReplicatedStorage.Types.Enums.Sounds.ESoundsIds)

local SoundsFolder = ReplicatedStorage:WaitForChild("Sounds")

-- The bus of each top folder; anything else is Effects. A model file cannot point at a SoundGroup outside itself, so
-- the buses are set here rather than in the tree.
local BUS_BY_FOLDER: { [string]: string } = {
	UI = ESoundGroups.UI,
	Music = ESoundGroups.Music,
}

-- Past this a pooled play is not heard at all, and inside it fades linearly with distance.
local POOLED_MAX_DIST = 150
local POOLED_MAX_DIST_SQ = POOLED_MAX_DIST * POOLED_MAX_DIST
-- A cue asked for again this soon after it played is dropped: a volley's kills, a crowd's cries or coins landing on
-- neighbouring frames are heard as one hit, not stacked into a blast. Under the fastest gun's FireInterval (0.05 s),
-- so a held trigger never loses a shot.
local MERGE_SECONDS = 0.035
-- What a muffle does to the world's buses (SetMuffled), and how it comes and goes: going under is quick and settles
-- in, coming up starts slow and breaks the surface.
local MUFFLED_BUSES = table.freeze({ ESoundGroups.Effects, ESoundGroups.Music })
local MUFFLED = table.freeze({ HighGain = -80, MidGain = -15, LowGain = -3 })
local CLEAR = table.freeze({ HighGain = 0, MidGain = 0, LowGain = 0 })
local MUFFLE_IN = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local MUFFLE_OUT = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

type TSoundPool = {
	Sounds: { Sound },
	Index: number,
	Size: number,
	BaseVolume: number,
	BaseSpeed: number,
}

local SoundsCore = {}

local soundsById: { [number]: Sound } = {}
-- Hits only, both: a folder or take added later starts working the moment it is there, and one that exists is
-- walked once for the session.
local groupFolders: { [string]: Instance } = {}
local bagTakes: { [Instance]: { Sound } } = {}
-- Per bag (its takes list), the weight of each take (rollIndex).
local takeWeights: { [{ Sound }]: { number } } = {}
-- Per cue (a pool, a list of pools, a tree node or a UI id): when it last played and how far from the camera (claim).
local playedAt: { [unknown]: number } = {}
local playedDistSq: { [unknown]: number } = {}
local muffleReasons: { [string]: true } = {}
local muffles: { EqualizerSoundEffect }? = nil
local isMuffled = false

do
	local soundGroups: { [string]: SoundGroup } = {}
	for _, child in SoundService:GetChildren() do
		if child:IsA("SoundGroup") then soundGroups[child.Name] = child end
	end

	for _, child in SoundsFolder:GetDescendants() do
		if not child:IsA("Sound") then continue end
		local top = child
		while top.Parent ~= SoundsFolder do
			top = top.Parent :: Instance
		end

		child.SoundGroup = soundGroups[BUS_BY_FOLDER[top.Name] or ESoundGroups.Effects]
		local id = (ESoundsIds :: { [string]: number })[child.Name]
		if id then soundsById[id] = child end
	end
end

-- ============================== Lookup ==============================
local function resolveGroup(group: string): Instance?
	local cached = groupFolders[group]
	if cached then return cached end

	local node: Instance = SoundsFolder
	for segment in string.gmatch(group, "[^.]+") do
		local child = node:FindFirstChild(segment)
		if not child then return nil end
		node = child
	end

	groupFolders[group] = node
	return node
end

-- The Sounds directly under a bag, or nil when it has none.
local function getTakes(bag: Instance): { Sound }?
	local cached = bagTakes[bag]
	if cached then return cached end

	local takes: { Sound } = {}
	local count = 0
	for _, child in bag:GetChildren() do
		if not child:IsA("Sound") then continue end
		count += 1
		takes[count] = child
	end
	if count == 0 then return nil end

	bagTakes[bag] = takes
	return takes
end

-- One take out of a bag, never the one just played and rarely the one before: a repeat is heard as the game having
-- one clip. Each take weighs one point per draw it has sat out, up to count - 1, and the one played drops to 0, so it
-- comes back over a few draws instead of under a hard ban, which at three or four takes turns into a fixed rotation.
local function rollIndex(bag: { any }): number
	local count = #bag
	if count <= 1 then return 1 end

	local fullWeight = count - 1
	local weights = takeWeights[bag]
	if not weights then
		weights = table.create(count, fullWeight)
		takeWeights[bag] = weights
	end

	local total = 0
	for _, weight in weights do
		total += weight
	end

	local roll = math.random(total)
	local picked = count
	local sum = 0
	for i, weight in weights do
		sum += weight
		if roll <= sum then
			picked = i
			break
		end
	end

	for i, weight in weights do
		weights[i] = math.min(fullWeight, weight + 1)
	end
	weights[picked] = 0

	return picked
end

-- ============================== Merging ==============================
-- Whether a play of `cue` this far from the camera is heard (MERGE_SECONDS). A nearer one still plays inside the
-- window, so a far body's cue never swallows the one at the player's feet.
local function claim(cue: unknown, distSq: number): boolean
	local now = os.clock()
	local last = playedAt[cue]
	if last and now - last < MERGE_SECONDS and distSq >= playedDistSq[cue] then return false end

	playedAt[cue] = now
	playedDistSq[cue] = distSq
	return true
end

local function distSqFromCamera(position: Vector3): number
	local offset = position - Workspace.CurrentCamera.CFrame.Position
	return offset:Dot(offset)
end

-- One named clip: ("Weapons", "Pistol") when it is a Sound. nil for a bag.
function SoundsCore.FindNamed(group: string, name: string): Sound?
	local folder = resolveGroup(group)
	local source = if folder then folder:FindFirstChild(name) else nil
	return if source and source:IsA("Sound") then source else nil
end

-- The takes of a bag folder, for a caller that resolves its bags once and rolls with RollTake. nil for a single clip,
-- or a bag with no takes.
function SoundsCore.FindTakes(group: string, node: string): { Sound }?
	local folder = resolveGroup(group)
	local bag = if folder then folder:FindFirstChild(node) else nil
	return if bag then getTakes(bag) else nil
end

-- One take out of a list FindTakes gave.
function SoundsCore.RollTake(takes: { Sound }): Sound
	return takes[rollIndex(takes)]
end

-- One take rolled out of a bag folder. nil for a single clip, or a bag with no takes.
function SoundsCore.FindRandom(group: string, node: string): Sound?
	local takes = SoundsCore.FindTakes(group, node)
	return if takes then takes[rollIndex(takes)] else nil
end

-- ============================== Pools ==============================
-- For cues fired many times a frame, where a clone per play would cost too much. The voices sit in SoundService, so
-- they play flat (no panning) and are faded by distance here instead. The pool cycles, so `size` is also the voice
-- limit: the next overlapping play restarts the oldest voice rather than stacking a wall of one clip.
function SoundsCore.CreatePool(source: Sound, size: number): TSoundPool
	local sounds: { Sound } = table.create(size)
	for i = 1, size do
		local sound = source:Clone()
		sound.Parent = SoundService
		sounds[i] = sound
	end

	return { Sounds = sounds, Index = 0, Size = size, BaseVolume = source.Volume, BaseSpeed = source.PlaybackSpeed }
end

-- One pool per take in a folder, each with the take's own Volume. Empty when the folder is missing.
function SoundsCore.CreateVariantPools(group: string, node: string, sizeEach: number): { TSoundPool }
	local takes = SoundsCore.FindTakes(group, node)
	if not takes then return {} end

	local pools: { TSoundPool } = table.create(#takes)
	for i, take in takes do
		pools[i] = SoundsCore.CreatePool(take, sizeEach)
	end

	return pools
end

local function playVoice(pool: TSoundPool, distSq: number, playbackSpeed: number?)
	pool.Index = pool.Index % pool.Size + 1
	local sound = pool.Sounds[pool.Index]
	sound.Volume = pool.BaseVolume * (1 - math.sqrt(distSq) / POOLED_MAX_DIST)
	sound.PlaybackSpeed = pool.BaseSpeed * (playbackSpeed or 1)
	sound:Play()
end

-- `playbackSpeed` scales the take's own pitch (a rising run of pickups).
function SoundsCore.PlayPooled(pool: TSoundPool, position: Vector3, playbackSpeed: number?)
	local distSq = distSqFromCamera(position)
	if distSq > POOLED_MAX_DIST_SQ or not claim(pool, distSq) then return end

	playVoice(pool, distSq, playbackSpeed)
end

-- The pools of one bag merge as one cue: two takes on one frame are still one hit heard twice.
function SoundsCore.PlayPooledRandom(pools: { TSoundPool }, position: Vector3, playbackSpeed: number?)
	if #pools == 0 then return end
	local distSq = distSqFromCamera(position)
	if distSq > POOLED_MAX_DIST_SQ or not claim(pools, distSq) then return end

	playVoice(pools[rollIndex(pools)], distSq, playbackSpeed)
end

-- ============================== One-shots ==============================
-- A positional one-shot at a fixed point, panned and attenuated, on a throwaway Attachment that goes when it ends.
function SoundsCore.PlayWorldSound(source: Sound, position: Vector3, volumeScale: number?): Sound
	local attachment = Instance.new("Attachment")
	attachment.Parent = Workspace.Terrain
	attachment.WorldPosition = position

	local sound = source:Clone()
	sound.Volume = source.Volume * (volumeScale or 1)
	sound.Parent = attachment
	sound.Ended:Once(function()
		attachment:Destroy()
	end)
	sound:Play()
	return sound
end

-- A clone of `source` played once under `parent` and destroyed when it ends: positional under a part, flat under
-- SoundService.
local function playClone(source: Sound, parent: Instance, volumeScale: number?, playbackSpeed: number?): Sound
	local sound = source:Clone()
	sound.Volume = source.Volume * (volumeScale or 1)
	sound.PlaybackSpeed = source.PlaybackSpeed * (playbackSpeed or 1)
	sound.Parent = parent
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	sound:Play()
	return sound
end

-- A one-shot riding a moving part, for anything a character does: a fixed point is left behind as he moves, and his
-- own swing slides into one ear. `playbackSpeed` multiplies the clip's own.
function SoundsCore.PlaySoundOnPart(source: Sound, part: BasePart, volumeScale: number?, playbackSpeed: number?): Sound
	return playClone(source, part, volumeScale, playbackSpeed)
end

-- The clip to play for `name` (itself, or a take rolled from its bag) and its tree node, the merge's key. Both nil
-- when it is not in the tree.
local function resolveNamed(group: string, name: string): (Sound?, Instance?)
	local folder = resolveGroup(group)
	local node = if folder then folder:FindFirstChild(name) else nil
	if not node then return nil, nil end
	if node:IsA("Sound") then return node, node end
	local takes = getTakes(node)
	if not takes then return nil, nil end

	return takes[rollIndex(takes)], node
end

-- `name` is one clip, or a bag of takes to roll. False when it is not in the tree, so a caller can fall back to
-- another; true when it is, even when merged into the one that just played (a fallback would stack a second sound).
-- The Sound comes second when one started, for a caller that may have to fade it.
function SoundsCore.PlayWorldNamed(
	group: string,
	name: string,
	position: Vector3,
	volumeScale: number?
): (boolean, Sound?)
	local source, node = resolveNamed(group, name)
	if not source then return false, nil end
	if not claim(node, distSqFromCamera(position)) then return true, nil end

	return true, SoundsCore.PlayWorldSound(source, position, volumeScale)
end

-- PlayWorldNamed riding `part`: anything a body does that rings on while it moves (Sounds.md, "Where a one-shot is
-- heard from").
function SoundsCore.PlayNamedOnPart(group: string, name: string, part: BasePart)
	local source, node = resolveNamed(group, name)
	if not source or not claim(node, distSqFromCamera(part.Position)) then return end

	playClone(source, part)
end

-- No position: heard the same wherever the listener stands or faces, on the clip's own bus, so a muffle still takes
-- it. For a moment that belongs to the whole squad rather than to a place (the nuke, a heal for everybody).
function SoundsCore.PlayFlatNamed(group: string, name: string)
	local source, node = resolveNamed(group, name)
	if not source or not claim(node, 0) then return end

	playClone(source, SoundService)
end

-- For infrequent cues; a cue fired many times a frame wants a pool.
function SoundsCore.PlayWorldRandom(group: string, node: string, position: Vector3)
	local folder = resolveGroup(group)
	local bag = if folder then folder:FindFirstChild(node) else nil
	local takes = if bag then getTakes(bag) else nil
	if not takes or not claim(takes, distSqFromCamera(position)) then return end

	SoundsCore.PlayWorldSound(takes[rollIndex(takes)], position)
end

function SoundsCore.PlayRandomOnPart(group: string, node: string, part: BasePart)
	local source = SoundsCore.FindRandom(group, node)
	if source then SoundsCore.PlaySoundOnPart(source, part) end
end

-- ============================== UI ==============================
-- Flat, on the UI bus. Never played: every UI clip is authored PlayOnRemove, so parenting the clone and destroying it
-- IS the play, and nothing is left to clean up.
local function playFlat(source: Sound, playbackSpeed: number?)
	local sound = source:Clone()
	if playbackSpeed then sound.PlaybackSpeed = source.PlaybackSpeed * playbackSpeed end
	sound.Parent = SoundService
	sound:Destroy()
end

function SoundsCore.PlayUISound(soundId: number)
	local source = soundsById[soundId]
	if not source or not claim(soundId, 0) then return end
	playFlat(source)
end

-- A UI clip by name: `name` is a clip, or a bag of takes to roll. Silent when it is not in the tree.
-- `playbackSpeed` scales the take's own pitch (a rising run).
function SoundsCore.PlayUINamed(group: string, name: string, playbackSpeed: number?)
	local folder = resolveGroup(group)
	local node = if folder then folder:FindFirstChild(name) else nil
	if not node then return end
	local isClip = node:IsA("Sound")
	local takes = if isClip then nil else getTakes(node)
	if not takes and not isClip then return end
	if not claim(node, 0) then return end

	playFlat(if takes then takes[rollIndex(takes)] else node :: Sound, playbackSpeed)
end

-- Every UI's hover and click (bags under Sounds.UI), named once here for all their callers.
function SoundsCore.PlayHover()
	SoundsCore.PlayUINamed("UI", "HoverHud")
end

function SoundsCore.PlayClick()
	SoundsCore.PlayUINamed("UI", "ClickHud")
end

-- ============================== Muffle ==============================
-- Under water: the world's buses lose their top and most of their middle and dip a little while anything asks, by a
-- named reason so two askers never undo each other. The UI bus stays clear, so the menu that asked is heard over the
-- world it muffles. Each bus gets its own EqualizerSoundEffect, made on first use: the volume settings write the
-- buses' Volume. Client only.
local function getMuffles(): { EqualizerSoundEffect }
	if muffles then return muffles end
	local made = {}
	for _, name in MUFFLED_BUSES do
		local bus = SoundService:FindFirstChild(name)
		if not bus then continue end
		local equalizer = Instance.new("EqualizerSoundEffect")
		equalizer.Name = "Muffle"
		equalizer.HighGain = 0
		equalizer.MidGain = 0
		equalizer.LowGain = 0
		equalizer.Parent = bus
		made[#made + 1] = equalizer
	end

	muffles = made
	return made
end

function SoundsCore.SetMuffled(reason: string, isOn: boolean)
	muffleReasons[reason] = if isOn then true else nil
	local shouldMuffle = next(muffleReasons) ~= nil
	if shouldMuffle == isMuffled then return end
	isMuffled = shouldMuffle

	local info = if shouldMuffle then MUFFLE_IN else MUFFLE_OUT
	local goal = if shouldMuffle then MUFFLED else CLEAR
	for _, equalizer in getMuffles() do
		TweenService:Create(equalizer, info, goal):Play()
	end
end

return SoundsCore
