-- A lobby dump (tools/lobby/dump.luau's JSON) back into a place file ror can draw:
--   lune run tools/lobby/place.luau dump.json out.rbxl <assets dir>
-- Every asset is private to an offline renderer, so each content id that has a file of its number in the assets
-- dir is pointed at it. A MeshPart gets InitialSize from the dump's `ms`, or it draws at the mesh's own size.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Instance, Vector3, CFrame, Color3, Enum =
	roblox.Instance, roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum

local SKIP = { n = true, c = true, p = true, cf = true, s = true, ms = true, Font = true }
local ENUMS = {
	Material = "Material",
	Shape = "PartType",
	Face = "NormalId",
	LightingStyle = "LightingStyle",
	TonemapperPreset = "TonemapperPreset",
	MeshType = "MeshType",
	SizingMode = "SurfaceGuiSizingMode",
}
local COLORS = {
	Color = true,
	Color3 = true,
	Ambient = true,
	OutdoorAmbient = true,
	ColorShift_Top = true,
	ColorShift_Bottom = true,
	TintColor = true,
	Decay = true,
	TextColor3 = true,
}

local data = serde.decode("json", fs.readFile(process.args[1]))
local assets = process.args[3]
local game = Instance.new("DataModel")
local workspace = game:GetService("Workspace")
local lighting = game:GetService("Lighting")

local function localize(value: any): any
	if type(value) ~= "string" or not assets then return value end
	local id = string.match(value, "^rbxassetid://(%d+)$") or string.match(value, "asset/%?id=(%d+)$")
	if id and fs.isFile(`{assets}/{id}`) then return `file://{assets}/{id}` end
	return value
end

local made = {}
for index, entry in data.list do
	local instance = if entry.c == "Lighting" then lighting else nil
	if not instance then
		local ok, new = pcall(Instance.new, entry.c)
		if not ok then
			made[index] = false
			continue
		end
		instance = new
		instance.Name = entry.n
	end
	made[index] = instance

	-- Properties a class does not have are skipped: the dump reads one list off every instance.
	local any = instance :: any
	if entry.ms then any.InitialSize = Vector3.new(entry.ms[1], entry.ms[2], entry.ms[3]) end
	if entry.s then any.Size = Vector3.new(entry.s[1], entry.s[2], entry.s[3]) end
	if entry.cf then any.CFrame = CFrame.new(table.unpack(entry.cf)) end
	for key, value in entry do
		if SKIP[key] then continue end
		pcall(function()
			if COLORS[key] then
				any[key] = Color3.new(value[1], value[2], value[3])
			elseif ENUMS[key] then
				any[key] = (Enum :: any)[ENUMS[key]][value]
			elseif type(value) == "table" and #value == 3 then
				any[key] = Vector3.new(value[1], value[2], value[3])
			elseif type(value) ~= "table" then
				any[key] = localize(value)
			end
		end)
	end

	if entry.c ~= "Lighting" then
		local parent = if entry.p == 0 then workspace else made[entry.p]
		if parent then instance.Parent = parent end
	end
end

fs.writeFile(process.args[2], roblox.serializePlace(game))
print(`{#data.list} instances -> {process.args[2]}`)
