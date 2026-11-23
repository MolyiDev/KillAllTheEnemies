-- A gun's model as it is worn on the back (BackGunController): built once per gun, and where it sits on a torso. It is
-- scaled as buildGunTool scales the gun in hand, so it is the same size on the back.
--
-- How it lies and where its visible edges are come from backGunFits, measured off renders of the real meshes
-- (tools/ree/backgunfits.sh): part boxes cannot say, since some guns are modelled at a lean inside their own box and
-- several carry invisible effect parts far bigger than the gun. A gun not measured yet is fitted by its visible parts'
-- boxes, which is close but can stand it off the back.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local backGunFits = require(script.Parent.backGunFits)
local GunsCore = require(ReplicatedStorage.GlobalShared.Core.GunsCore)
local TData = require(ReplicatedStorage.Types.TData)

local Tune = table.freeze({
	-- The barrel climbs this many degrees from flat toward the right shoulder; what is seen of the gun is centred
	-- across the back this far over the torso's middle, and lies this far off it.
	SLANT_DEG = 50,
	RISE = 0.15,
	GAP = 0.03,
})

-- Where a built gun sits: its Handle's place against the middle of the back (torso space, before the back's own
-- depth is added) and its turn there.
export type TFit = {
	Offset: Vector3,
	Turn: CFrame,
}

local backGunModel = {}

-- How far `parts` reach along `axis` from `origin`, both ways.
local function reach(parts: { BasePart }, origin: Vector3, axis: Vector3): (number, number)
	local low, high = math.huge, -math.huge
	for _, part in parts do
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

-- How far an outline (points in the Handle's X and Y) reaches along `axis` (the same plane), both ways.
local function span(outline: { Vector2 }, axis: Vector2): (number, number)
	local low, high = math.huge, -math.huge
	for _, point in outline do
		local along = point:Dot(axis)
		low = math.min(low, along)
		high = math.max(high, along)
	end

	return low, high
end

local function partsOf(model: Model, isVisibleOnly: boolean): { BasePart }
	local parts = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and (not isVisibleOnly or part.Transparency < 1) then table.insert(parts, part) end
	end

	return parts
end

-- The handle on the back, in torso space: the slant turns the gun's axes (X out of the barrel, Y its top, Z its side)
-- into the back's plane, its side flat against the back.
local function turnOf(): CFrame
	local slant = math.rad(Tune.SLANT_DEG)
	return CFrame.fromMatrix(
		Vector3.zero,
		Vector3.new(math.cos(slant), math.sin(slant), 0),
		Vector3.new(-math.sin(slant), math.cos(slant), 0)
	)
end

-- An unmeasured gun's side: GunsCore.FindAxes takes the gun's top from the MODEL's pivot, which on some models is tens
-- of degrees off their parts (every part of a model is turned alike), so its side is snapped to the nearest of the
-- biggest visible part's own axes.
local function sideOf(parts: { BasePart }, frame: CFrame): Vector3
	local biggest, biggestVolume = parts[1], -1
	for _, part in parts do
		local size = part.Size
		local volume = size.X * size.Y * size.Z
		if volume > biggestVolume then
			biggest, biggestVolume = part, volume
		end
	end

	local side, nearest = frame.ZVector, -1
	for _, axis in { biggest.CFrame.RightVector, biggest.CFrame.UpVector, biggest.CFrame.LookVector } do
		local along = axis:Dot(frame.ZVector)
		if math.abs(along) > nearest then
			side, nearest = if along >= 0 then axis else -axis, math.abs(along)
		end
	end

	return side
end

-- The gun's model at its Length, a Handle on its axes (X out of the barrel, Y its top, Z the side it lies on), every
-- part welded to the Handle and touching nothing; nil when the place has no model for it. Also where it sits on the
-- back.
function backGunModel.Build(gun: TData.TGun): (Model?, TFit?)
	local source = GunsCore.GetModel(gun)
	if not source then return nil, nil end

	local model = source:Clone()
	local frame = GunsCore.FindAxes(model, gun)
	local low, high = reach(partsOf(model, false), frame.Position, frame.XVector)
	model:ScaleTo(model:GetScale() * gun.Length / math.max(high - low, 1e-3))
	frame = GunsCore.FindAxes(model, gun)

	for _, item in model:GetDescendants() do
		if
			item:IsA("JointInstance")
			or item:IsA("WeldConstraint")
			or item:IsA("LuaSourceContainer")
			or item:IsA("Sound")
		then
			item:Destroy()
		end
	end

	local measured = backGunFits[gun.Name]
	local visible = partsOf(model, true)
	local barrel, top
	if measured then
		barrel = frame:VectorToWorldSpace(measured.Barrel)
		top = frame:VectorToWorldSpace(measured.Top)
	else
		local side = sideOf(visible, frame)
		barrel = (frame.XVector - side * frame.XVector:Dot(side)).Unit
		top = side:Cross(barrel)
	end

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.one * 0.2
	handle.Transparency = 1
	handle.CFrame = CFrame.fromMatrix(frame.Position, barrel, top)
	handle.Parent = model
	for _, part in partsOf(model, false) do
		part.Anchored = false
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.CastShadow = false
		if part == handle then continue end

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = part
		weld.Parent = handle
	end

	model.Name = "BackGun"
	model.PrimaryPart = handle

	-- What is seen of it, along the back's own axes once it is turned onto the back: centred across the back on its
	-- silhouette (a pistol's box is mostly air under its slide), and its nearest face on the back.
	local turn = turnOf()
	local across = turn:VectorToObjectSpace(Vector3.xAxis)
	local up = turn:VectorToObjectSpace(Vector3.yAxis)
	local lowX, highX, lowY, highY, lowZ
	if measured then
		lowX, highX = span(measured.Outline, Vector2.new(across.X, across.Y))
		lowY, highY = span(measured.Outline, Vector2.new(up.X, up.Y))
		lowZ = measured.Near
	else
		local origin = handle.Position
		lowX, highX = reach(visible, origin, handle.CFrame:VectorToWorldSpace(across))
		lowY, highY = reach(visible, origin, handle.CFrame:VectorToWorldSpace(up))
		lowZ = reach(visible, origin, handle.CFrame.ZVector)
	end

	local fit: TFit = {
		Offset = Vector3.new(-(lowX + highX) / 2, Tune.RISE - (lowY + highY) / 2, Tune.GAP - lowZ),
		Turn = turn,
	}

	return model, fit
end

-- The Handle's place in `torso`'s space at rest. +Z is the back.
function backGunModel.Slot(fit: TFit, torso: BasePart): CFrame
	return CFrame.new(fit.Offset + Vector3.zAxis * torso.Size.Z / 2) * fit.Turn
end

return backGunModel
