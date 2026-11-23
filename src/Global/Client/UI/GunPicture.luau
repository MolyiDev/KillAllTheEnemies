--!nonstrict
-- A gun drawn as its own model with its shadow under it: two ViewportFrames holding a copy each, framed side on with
-- the barrel to the right, the lower one drawn black. One frame draws its contents once, so the shadow has to be a
-- second frame. The hotbar draws the gun in hand this way, the weapon card the gun on offer.
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
local AMBIENT = Color3.fromRGB(200, 200, 200)
local LIGHT = Color3.fromRGB(196, 188, 172)
-- Where the key light travels in the camera's own frame: past it, down and to the right, so it always comes over the
-- camera's left shoulder.
local KEY_LIGHT = Vector3.new(0.44, -0.64, -0.63).Unit
-- A viewport blends its edge pixels toward its BackgroundColor3 even when the background is transparent, so the
-- default white leaves a light line round the model.
local FRINGE = Color3.new()
-- The shadow falls straight down by this share of the picture, and is this far from solid. A share, so a small icon
-- and a big stage sit as close over theirs: 10 px under the Index stage's 340 px enemy, as close as a chest's.
local SHADOW_DROP = 10 / 340
local SHADOW_TRANSPARENCY = 0.3

-- What to draw: a model (copied, never touched), where its axes sit and which way its barrel and top face.
export type TPicture = {
	Model: Model,
	Origin: Vector3,
	Barrel: Vector3,
	Up: Vector3,
}

local GunPicture = {}

-- A light that is nearly flat, for a model made of plain coloured parts (an ability's, an upgrade's): every face
-- keeps its own colour on a dark card. Passed as a picture's `Ambient` and `Light`.
GunPicture.FLAT_AMBIENT = Color3.fromRGB(236, 236, 236)
GunPicture.FLAT_LIGHT = Color3.fromRGB(150, 146, 136)
-- The shadow's drop and fade, for another picture drawn the same way (an enemy's in the Index).
GunPicture.SHADOW_DROP = SHADOW_DROP
GunPicture.SHADOW_TRANSPARENCY = SHADOW_TRANSPARENCY

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

-- The picture of `model`, one built with its front to +Z, looked at from `yawDeg` round it from its front and
-- `pitchDeg` over it.
function GunPicture.FromModel(model: Model, yawDeg: number, pitchDeg: number): TPicture
	-- The camera stands off the picture's right crossed with its up.
	local frame = CFrame.Angles(0, math.rad(yawDeg), 0) * CFrame.Angles(-math.rad(pitchDeg), 0, 0)
	return { Model = model, Origin = model:GetBoundingBox().Position, Barrel = frame.XVector, Up = frame.YVector }
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

-- Where the camera stands for `picture`: side on, rolled so the barrel climbs `leanDeg` to the right. The fit is of
-- the leaned gun WITH its shadow: a gun as tall as it is long (a pistol) grows past a box fitted to it lying flat once
-- it is turned, and sits off the middle of it; and the shadow under the gun is part of what is seen, so the two
-- together are centred, not the gun. Also returns the point it looks at, which a turn of the camera goes round.
local function stand(picture: TPicture, leanDeg: number): (CFrame, Vector3)
	local lean = math.rad(leanDeg)
	local barrel, up, origin, model = picture.Barrel, picture.Up, picture.Origin, picture.Model
	local right = barrel * math.cos(lean) - up * math.sin(lean)
	local top = barrel * math.sin(lean) + up * math.cos(lean)
	local leftX, rightX = reach(model, origin, right)
	local downY, upY = reach(model, origin, top)
	-- The box's side in studs: the gun's width, or its height and the shadow's drop under it (a share of this side).
	local span = math.max(rightX - leftX, (upY - downY) / (1 - SHADOW_DROP * MARGIN)) * MARGIN
	local center = origin + right * (leftX + rightX) / 2 + top * ((downY + upY) / 2 - SHADOW_DROP * span / 2)
	local distance = span / 2 / math.tan(math.rad(FOV / 2))
	return CFrame.fromMatrix(center + right:Cross(top) * distance, right, top), center
end

-- One of the two frames. The shadow is lit by nothing and multiplied to black on the way out, so Neon, which ignores
-- the light, is black too.
local function layer(isShadow: boolean, ambient: Color3, light: Color3, props: { [any]: any }): ViewportFrame
	local camera = create("Camera")({ FieldOfView = FOV })
	return create("ViewportFrame")({
		Name = if isShadow then "Shadow" else "Art",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BackgroundColor3 = FRINGE,
		Ambient = if isShadow then FRINGE else ambient,
		LightColor = if isShadow then FRINGE else light,
		ImageColor3 = if isShadow then FRINGE else Palette.White,
		ZIndex = if isShadow then 1 else 2,
		CurrentCamera = camera,
		camera,
		props,
	}) :: ViewportFrame
end

-- A box drawing whatever `picture` returns (nil draws nothing), redrawn when it changes. `spec.Lean` is how far the
-- barrel climbs at rest, in degrees, fitted to the box (stand). The rest of `spec` may be sources: Rotation (a turn
-- of the picture in its own plane on top of that, in degrees, about the box's middle) and Transparency (0 shown, 1
-- gone), Tint (multiplies the gun's colours, white by default: grey for one not yet owned) and Yaw (the camera
-- swung this many degrees round the gun's up, for a gun turning on a stand). `spec.Ambient` and `spec.Light` replace the light the picture is drawn under. They go to the two frames rather than the box: the shadow turns about its own middle, so it falls straight
-- down whatever the turn, and it fades with the gun. `props` are the box's own; scaling the box moves the shadow out
-- with the gun.
function GunPicture.Build(picture: () -> TPicture?, spec: { [any]: any }, props: { [any]: any }): Frame
	local fade = spec.Transparency
	local leanDeg = spec.Lean or 0
	local faded = function(): number
		return if type(fade) == "function" then fade() else fade or 0
	end

	local ambient, lightColor = spec.Ambient or AMBIENT, spec.Light or LIGHT
	local shadow = layer(true, ambient, lightColor, {
		Position = UDim2.fromScale(0.5, 0.5 + SHADOW_DROP),
		Rotation = spec.Rotation,
		ImageTransparency = function()
			return SHADOW_TRANSPARENCY + (1 - SHADOW_TRANSPARENCY) * faded()
		end,
	})
	local art = layer(false, ambient, lightColor, {
		Position = UDim2.fromScale(0.5, 0.5),
		Rotation = spec.Rotation,
		ImageTransparency = faded,
		ImageColor3 = spec.Tint,
	})

	-- The two frames and the copy each holds; the copies are replaced when the picture changes.
	local frames = { shadow, art }
	local copies: { Model } = {}
	-- The camera at rest and what it looks at, for a Yaw to swing it round.
	local rest, pivot = CFrame.identity, Vector3.zero
	local up = Vector3.yAxis
	local yaw = spec.Yaw
	local function aim()
		local cframe = rest
		if yaw then
			local turn = CFrame.fromAxisAngle(up, math.rad(yaw()))
			cframe = CFrame.new(pivot) * turn * (CFrame.new(-pivot) * rest)
		end
		for _, viewport in frames do
			(viewport.CurrentCamera :: Camera).CFrame = cframe
		end
	end
	local function clear()
		for _, copy in copies do
			copy:Destroy()
		end
		table.clear(copies)
	end

	vide.effect(function()
		local current = picture()
		vide.untrack(function()
			clear()
			if not current then return end
			local frame, center = stand(current, leanDeg)
			rest, pivot, up = frame, center, current.Up
			aim()
			local light = frame:VectorToWorldSpace(KEY_LIGHT)
			for index, viewport in frames do
				viewport.LightDirection = light
				local copy = current.Model:Clone()
				copy.Parent = viewport
				copies[index] = copy
			end
		end)
	end)
	vide.cleanup(clear)
	-- The camera follows the turn on its own, without copying the gun again.
	local function follow()
		yaw()
		vide.untrack(aim)
	end
	if yaw then vide.effect(follow) end

	return create("Frame")({
		BackgroundTransparency = 1,
		shadow,
		art,
		props,
	}) :: Frame
end

return GunPicture
