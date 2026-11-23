-- Lists every asset id a place file's instances hold (sounds, animations, meshes, textures, images, particles), one
-- line each: kind, id, instance path. Same stripped input as dump.luau:
--   lune run tools/oldplaces/assets.luau /tmp/clean.rbxl > research/OldGame/_assets.txt
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local process = require("@lune/process")

local game = roblox.deserializePlace(fs.readFile(process.args[1]))
-- Newer files store these as Content (ImageContent, AudioContent, MeshContent...); the string names are older ones.
local PROPS = {
	Sound = { "AudioContent", "SoundId" },
	Animation = { "AnimationId" },
	MeshPart = { "MeshContent", "TextureContent", "MeshId", "TextureID" },
	SpecialMesh = { "MeshId", "TextureId" },
	Decal = { "TextureContent", "Texture" },
	Texture = { "TextureContent", "Texture" },
	ParticleEmitter = { "Texture" },
	Beam = { "Texture" },
	Trail = { "Texture" },
	ImageLabel = { "ImageContent", "Image" },
	ImageButton = { "ImageContent", "Image" },
	SurfaceAppearance = { "ColorMapContent", "NormalMapContent", "RoughnessMapContent", "MetalnessMapContent" },
	Shirt = { "ShirtTemplate" },
	Pants = { "PantsTemplate" },
	Sky = { "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp" },
}
local function path(inst)
	local parts = {}
	while inst and inst.Parent do
		table.insert(parts, 1, inst.Name)
		inst = inst.Parent
	end
	return table.concat(parts, ".")
end
for _, inst in game:GetDescendants() do
	local props = PROPS[inst.ClassName]
	if not props then continue end
	for _, prop in props do
		local ok, value = pcall(function()
			return inst[prop]
		end)
		if ok and typeof(value) == "Content" then value = (value :: any).Uri end
		if ok and type(value) == "string" and value ~= "" then
			print(inst.ClassName .. "." .. prop, value, path(inst))
		end
	end
end
