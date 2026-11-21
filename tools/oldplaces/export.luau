-- Saves instances out of a place file as .rbxm, one per child of the given path (Folders become directories), so a
-- model or an animation can be inserted in Studio (Insert from File) or uploaded. Same stripped input as dump.luau:
--   lune run tools/oldplaces/export.luau /tmp/clean.rbxl ReplicatedStorage.Assets.Guns Assets/models/Guns
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local process = require("@lune/process")

local placePath, instancePath, out = process.args[1], process.args[2], process.args[3]
local game = roblox.deserializePlace(fs.readFile(placePath))

local node: any = game
for name in string.gmatch(instancePath, "[^%.]+") do
	node = node:FindFirstChild(name)
	assert(node, `no {instancePath} in {placePath}`)
end

local count = 0
local function safe(name: string): string
	return (string.gsub(name, "[^%w%._%- ]", "_"))
end
local function export(inst, dir: string)
	fs.writeDir(dir)
	if inst.ClassName == "Folder" then
		for _, child in inst:GetChildren() do
			export(child, dir .. "/" .. safe(inst.Name))
		end
		return
	end
	fs.writeFile(dir .. "/" .. safe(inst.Name) .. ".rbxm", roblox.serializeModel({ inst }))
	count += 1
end
for _, child in node:GetChildren() do
	export(child, out)
end
print(`{instancePath}: {count} files under {out}`)
