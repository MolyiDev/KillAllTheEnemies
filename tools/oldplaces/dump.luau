-- Dumps a place file for reading offline: every script's source to <out>/<instance path>/<Name>.(server|client).luau, and
-- <out>/_tree.txt with every instance (ClassName, Part sizes). Run on a file stripped by tools/uimatt/strip.py:
--   python3 tools/uimatt/strip.py Place.rbxl /tmp/clean.rbxl Tags && lune run tools/oldplaces/dump.luau /tmp/clean.rbxl research/OldGame
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local process = require("@lune/process")

local placePath, out = process.args[1], process.args[2]
local game = roblox.deserializePlace(fs.readFile(placePath))
fs.writeDir(out)

local lines = {}
local count = 0
local function safe(name)
	return (string.gsub(name, "[^%w%._%- ]", "_"))
end
local function walk(inst, path, depth)
	local extra = ""
	if inst:IsA("BasePart") then
		local s = inst.Size
		extra = string.format(" size=(%.1f,%.1f,%.1f)", s.X, s.Y, s.Z)
	end
	table.insert(lines, string.rep("  ", depth) .. inst.Name .. " [" .. inst.ClassName .. "]" .. extra)
	if inst:IsA("LuaSourceContainer") then
		local ok, src = pcall(function() return inst.Source end)
		if ok and src then
			local suffix = if inst.ClassName == "Script" then ".server.luau" elseif inst.ClassName == "LocalScript" then ".client.luau" else ".luau"
			local dir = out .. "/" .. path
			fs.writeDir(dir)
			local file = dir .. "/" .. safe(inst.Name) .. suffix
			if fs.isFile(file) then file = dir .. "/" .. safe(inst.Name) .. "_" .. count .. suffix end
			fs.writeFile(file, src)
			count += 1
		end
	end
	for _, child in inst:GetChildren() do
		walk(child, path .. "/" .. safe(inst.Name), depth + 1)
	end
end
for _, service in game:GetChildren() do
	walk(service, "", 0)
end
fs.writeFile(out .. "/_tree.txt", table.concat(lines, "\n"))
print(placePath, "scripts:", count, "instances:", #lines)
