--[[
Rebuilds clips read out of a playtest (KeyframeSequenceProvider, serialized as JSON) into KeyframeSequence .rbxm
files that Open Cloud uploads as Animations (tools/rig/upload.py --player).

	lune run tools/lune/keyframes.luau <dir>        every <dir>/<Clip>.json -> <dir>/<Clip>.rbxm

WHY: an animation plays only in games its owner owns, and the player's locomotion clips are BeACastleLord's, owned
by its group, while the arena places are a user's. The clips are re-uploaded as that user from their own keyframes,
so they are the same motion and nothing is re-animated.

JSON shape (one clip): { Name, Loop, Priority, Keyframes = { { T, N, M = { {N, V} }, P = { pose } } } }, a pose
being { N, C = CFrame:GetComponents(), W, S = EasingStyle, D = EasingDirection, K = { subposes } }.
]]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Instance = roblox.Instance
local CFrame = roblox.CFrame
local Enum = roblox.Enum

local dir = process.args[1]
assert(dir, "usage: lune run tools/lune/keyframes.luau <dir>")

local function buildPose(node, parent)
	local pose = Instance.new("Pose")
	pose.Name = node.N
	pose.CFrame = CFrame.new(table.unpack(node.C))
	pose.Weight = node.W
	pose.EasingStyle = (Enum.PoseEasingStyle :: any)[node.S]
	pose.EasingDirection = (Enum.PoseEasingDirection :: any)[node.D]
	for _, child in node.K do
		buildPose(child, pose)
	end
	pose.Parent = parent
end

for _, file in fs.readDir(dir) do
	if not string.match(file, "%.json$") then continue end
	local clip = serde.decode("json", fs.readFile(`{dir}/{file}`))
	local sequence = Instance.new("KeyframeSequence")
	sequence.Name = clip.Name
	sequence.Loop = clip.Loop
	sequence.Priority = (Enum.AnimationPriority :: any)[clip.Priority]
	for _, frame in clip.Keyframes do
		local keyframe = Instance.new("Keyframe")
		keyframe.Name = frame.N
		keyframe.Time = frame.T
		for _, node in frame.P do
			buildPose(node, keyframe)
		end
		for _, marker in frame.M do
			local keyframeMarker = Instance.new("KeyframeMarker")
			keyframeMarker.Name = marker.N
			keyframeMarker.Value = marker.V
			keyframeMarker.Parent = keyframe
		end
		keyframe.Parent = sequence
	end
	fs.writeFile(`{dir}/{clip.Name}.rbxm`, roblox.serializeModel({ sequence }))
	print(`[KEYFRAMES] {clip.Name}: {#clip.Keyframes} keyframes, loop {clip.Loop}, {clip.Priority}`)
end
