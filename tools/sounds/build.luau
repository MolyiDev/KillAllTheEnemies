-- Turns tools/sounds/Sounds.txt into sounds/Sounds.rbxmx, Rojo's ReplicatedStorage.Sounds in both places.
--   lune run tools/sounds/build.luau "$PWD"
-- Sounds.txt holds one Sound a line:
--   path|SoundId|Volume|PlaybackSpeed|bus|flags
-- with flags from Looped, PlayOnRemove, RollOff=<mode>, Min=<studs>, Max=<studs>. Audio plays only in games its
-- owner owns, so every id is group 34796361's (tools/sounds/upload.py) or Roblox library audio; anyone else's is a
-- silent Sound and two Studio warnings every load.
--
-- The bus column is a record only: a model file cannot point at a SoundGroup outside itself, so SoundsCore puts each
-- Sound on its bus by its top folder when it loads.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local root = process.args[1]
assert(root, "usage: lune run tools/sounds/build.luau <repo>")

local DEFAULT_MIN_DISTANCE = 10
local DEFAULT_MAX_DISTANCE = 10000

local model = roblox.Instance.new("Folder")
model.Name = "Sounds"
local nodes: { [string]: any } = { [""] = model }
local count = 0

local function folderFor(path: string)
	local node = nodes[path]
	if node then return node end

	local parentPath, name = string.match(path, "^(.*)/([^/]+)$")
	if not parentPath then
		parentPath, name = "", path
	end
	node = roblox.Instance.new("Folder")
	node.Name = name
	node.Parent = folderFor(parentPath :: string)
	nodes[path] = node
	return node
end

for line in string.gmatch(fs.readFile(`{root}/tools/sounds/Sounds.txt`), "[^\n]+") do
	local path, soundId, volume, speed, _, flags = string.match(line, "^([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)|(.*)$")
	assert(path, `unreadable line: {line}`)

	local parentPath, name = string.match(path :: string, "^(.*)/([^/]+)$")
	if not parentPath then
		parentPath, name = "", path
	end

	local sound = roblox.Instance.new("Sound")
	sound.Name = name
	sound.SoundId = soundId
	sound.Volume = tonumber(volume)
	sound.PlaybackSpeed = tonumber(speed)
	sound.RollOffMode = roblox.Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = DEFAULT_MIN_DISTANCE
	sound.RollOffMaxDistance = DEFAULT_MAX_DISTANCE

	for flag in string.gmatch(flags :: string, "[^,]+") do
		local key, value = string.match(flag, "^(%w+)=(.+)$")
		if flag == "Looped" then
			sound.Looped = true
		elseif flag == "PlayOnRemove" then
			sound.PlayOnRemove = true
		elseif key == "RollOff" then
			sound.RollOffMode = (roblox.Enum.RollOffMode :: any)[value]
		elseif key == "Min" then
			sound.RollOffMinDistance = tonumber(value)
		elseif key == "Max" then
			sound.RollOffMaxDistance = tonumber(value)
		else
			error(`unknown flag {flag} on {path}`)
		end
	end

	sound.Parent = folderFor(parentPath :: string)
	count += 1
end

fs.writeFile(`{root}/sounds/Sounds.rbxmx`, roblox.serializeModel({ model }, true))
print(`sounds/Sounds.rbxmx: {count} sounds`)
