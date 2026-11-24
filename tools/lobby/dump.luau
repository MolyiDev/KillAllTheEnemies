-- Run in a Lobby playtest's server (Tripwire run_luau_live; tools/lobby/preview.py does it): every instance of
-- Workspace.Lobby and Lighting as a flat JSON list ({n, c, p = the parent's index, cf, s, ms = a mesh's own size,
-- then properties}), left in _G.dump for the caller to fetch in slices. Returns its length. Edit mode cannot read a
-- place this way, and a saved copy of it is stale the moment Studio edits it.
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local PROPERTIES = {
	"Transparency",
	"Reflectance",
	"CanCollide",
	"CanQuery",
	"CanTouch",
	"CastShadow",
	"Anchored",
	"MeshId",
	"TextureID",
	"Texture",
	"Brightness",
	"Range",
	"Angle",
	"Shadows",
	"Enabled",
	"StudsPerTileU",
	"StudsPerTileV",
	"OffsetStudsU",
	"OffsetStudsV",
	"Text",
	"TextScaled",
	"TextureId",
	"Scale",
	"ClockTime",
	"GeographicLatitude",
	"ExposureCompensation",
	"EnvironmentDiffuseScale",
	"EnvironmentSpecularScale",
	"GlobalShadows",
	"ShadowSoftness",
	"Intensity",
	"Size",
	"Threshold",
	"Spread",
	"Density",
	"Offset",
	"Glare",
	"Haze",
	"Contrast",
	"Saturation",
	"SkyboxBk",
	"SkyboxDn",
	"SkyboxFt",
	"SkyboxLf",
	"SkyboxRt",
	"SkyboxUp",
	"SunTextureId",
	"MoonTextureId",
	"SunAngularSize",
	"MoonAngularSize",
	"StarCount",
	"CelestialBodiesShown",
	"MaterialVariant",
	"PixelsPerStud",
	"LightInfluence",
	"BackgroundTransparency",
}
local ENUMS = { "Material", "Shape", "Face", "LightingStyle", "TonemapperPreset", "MeshType", "Font", "SizingMode" }
local COLORS = {
	"Color",
	"Color3",
	"Ambient",
	"OutdoorAmbient",
	"ColorShift_Top",
	"ColorShift_Bottom",
	"TintColor",
	"Decay",
	"TextColor3",
}

local list = {}

local function round(value: number): number
	return math.round(value * 10000) / 10000
end

local function read(instance: Instance, name: string): any
	local ok, value = pcall(function()
		return (instance :: any)[name]
	end)
	return if ok then value else nil
end

local function walk(instance: Instance, parent: number)
	local entry: { [string]: any } = { n = instance.Name, c = instance.ClassName, p = parent }
	table.insert(list, entry)
	local index = #list

	if instance:IsA("BasePart") then
		local components = { instance.CFrame:GetComponents() }
		for i, value in components do
			components[i] = round(value)
		end
		entry.cf = components
		entry.s = { round(instance.Size.X), round(instance.Size.Y), round(instance.Size.Z) }
		if instance:IsA("MeshPart") then
			entry.ms = { instance.MeshSize.X, instance.MeshSize.Y, instance.MeshSize.Z }
		end
	end
	for _, name in PROPERTIES do
		local value = read(instance, name)
		if type(value) == "number" then
			entry[name] = round(value)
		elseif type(value) == "boolean" or type(value) == "string" then
			entry[name] = value
		elseif typeof(value) == "Vector3" then
			entry[name] = { round(value.X), round(value.Y), round(value.Z) }
		end
	end
	for _, name in ENUMS do
		local value = read(instance, name)
		if typeof(value) == "EnumItem" then entry[name] = value.Name end
	end
	for _, name in COLORS do
		local value = read(instance, name)
		if typeof(value) == "Color3" then entry[name] = { round(value.R), round(value.G), round(value.B) } end
	end

	for _, child in instance:GetChildren() do
		walk(child, index)
	end
end

walk(Workspace:FindFirstChild("Lobby") :: Instance, 0)
walk(Lighting, 0)
_G.dump = HttpService:JSONEncode({ place = game.PlaceId, list = list })

return #_G.dump
