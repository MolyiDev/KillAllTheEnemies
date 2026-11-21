--!nonstrict
-- A gun drawn as the designer's flat white glyph: a whitened copy of its model in a ViewportFrame, framed side on with
-- the barrel to the right. The hotbar draws the gun in hand this way, the weapon card the gun on offer.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local GunsCore = require(ReplicatedStorage.GlobalShared.Core.GunsCore)

local create = vide.create
local Palette = Theme.Palette
local GUNS = DataCore.Guns.ById

-- A long lens, so the gun reads flat like the designer's glyphs, with this much air round it.
local FOV = 12
local MARGIN = 1.2

-- What to draw: a model (copied, never touched), where its axes sit and which way its barrel and top face.
export type TPicture = {
	Model: Model,
	Origin: Vector3,
	Barrel: Vector3,
	Up: Vector3,
}

local GunPicture = {}

local fromGunCache: { [number]: TPicture | false } = {}

-- The picture of gun `gunId`'s model, or nil when the place has no model for it.
function GunPicture.FromGun(gunId: number): TPicture?
	local cached = fromGunCache[gunId]
	if cached ~= nil then return cached or nil end

	local gun = GUNS[gunId]
	local model = if gun then GunsCore.GetModel(gun) else nil
	local picture: TPicture | false = false
	if gun and model then
		local axes = GunsCore.FindAxes(model, gun)
		picture = { Model = model, Origin = axes.Position, Barrel = axes.XVector, Up = axes.YVector }
	end

	fromGunCache[gunId] = picture
	return picture or nil
end

-- Paints a copy flat white: full ambient and a black key light make every lit face the same colour, so the picture
-- is the gun's outline, the designer's white glyph.
local function whiten(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Color = Palette.White
			descendant.Material = Enum.Material.SmoothPlastic
			if descendant:IsA("MeshPart") then descendant.TextureID = "" end
		elseif descendant:IsA("SurfaceAppearance") or descendant:IsA("Decal") then
			descendant:Destroy()
		end
	end
end

-- How far the gun's parts reach along an axis from `origin`, both ways.
local function reach(model: Model, origin: Vector3, axis: Vector3): (number, number)
	local low, high = math.huge, -math.huge
	for _, part in model:GetDescendants() do
		if not part:IsA("BasePart") then continue end
		local cframe, size = part.CFrame, part.Size
		local along = (cframe.Position - origin):Dot(axis)
		local half = math.abs(cframe.RightVector:Dot(axis)) * size.X / 2
			+ math.abs(cframe.UpVector:Dot(axis)) * size.Y / 2
			+ math.abs(cframe.LookVector:Dot(axis)) * size.Z / 2
		low = math.min(low, along - half)
		high = math.max(high, along + half)
	end

	return low, high
end

local function show(viewport: ViewportFrame, camera: Camera, picture: TPicture): Model
	local copy = picture.Model:Clone()
	whiten(copy)
	local barrel, up, origin = picture.Barrel, picture.Up, picture.Origin
	local backX, frontX = reach(copy, origin, barrel)
	local downY, upY = reach(copy, origin, up)
	local center = origin + barrel * (backX + frontX) / 2 + up * (downY + upY) / 2
	local span = math.max(frontX - backX, upY - downY) * MARGIN
	local distance = span / 2 / math.tan(math.rad(FOV / 2))
	camera.CFrame = CFrame.fromMatrix(center + barrel:Cross(up) * distance, barrel, up)
	copy.Parent = viewport
	return copy
end

-- A ViewportFrame drawing whatever `picture` returns (nil draws nothing), redrawn when it changes. `props` are the
-- frame's own.
function GunPicture.Build(picture: () -> TPicture?, props: { [any]: any }): ViewportFrame
	local camera = create("Camera")({ FieldOfView = FOV })
	local viewport = create("ViewportFrame")({
		BackgroundTransparency = 1,
		Ambient = Palette.White,
		LightColor = Color3.new(),
		CurrentCamera = camera,
		camera,
		props,
	}) :: ViewportFrame

	local shown: Model? = nil
	vide.effect(function()
		local current = picture()
		vide.untrack(function()
			if shown then shown:Destroy() end
			shown = if current then show(viewport, camera, current) else nil
		end)
	end)

	vide.cleanup(function()
		if shown then shown:Destroy() end
	end)

	return viewport
end

return GunPicture
