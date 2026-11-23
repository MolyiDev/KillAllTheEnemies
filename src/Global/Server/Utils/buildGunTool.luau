-- Turns a gun's model (GunsCore.GetModel) into the Tool a character holds: scaled to the gun's Length, a Handle at the
-- grip facing out of the barrel (GunsCore.FindAxes), and a Muzzle attachment at its tip. A model with a child Model
-- `Slide` (its PrimaryPart the slide's body) gets it as one piece on a Weld named `Slide`, which the clients move
-- (Client/Utils/gunSlide).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GunsCore = require(ReplicatedStorage.GlobalShared.Core.GunsCore)
local TData = require(ReplicatedStorage.Types.TData)

-- Where the hand closes on the gun, as fractions of its length from the back and its height from the bottom.
local GRIP_ALONG = 0.32
local GRIP_UP = 0.3
local CORNERS = table.freeze({
	Vector3.new(-1, -1, -1),
	Vector3.new(-1, -1, 1),
	Vector3.new(-1, 1, -1),
	Vector3.new(-1, 1, 1),
	Vector3.new(1, -1, -1),
	Vector3.new(1, -1, 1),
	Vector3.new(1, 1, -1),
	Vector3.new(1, 1, 1),
})

local function getParts(model: Model): { BasePart }
	local parts = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then parts[#parts + 1] = descendant end
	end

	return parts
end

local function measure(model: Model, frame: CFrame): (Vector3, Vector3)
	local low = Vector3.one * math.huge
	local high = -low
	for _, part in getParts(model) do
		local half = part.Size / 2
		for _, corner in CORNERS do
			local point = frame:PointToObjectSpace(part.CFrame * (half * corner))
			low = low:Min(point)
			high = high:Max(point)
		end
	end

	return low, high
end

return function(gun: TData.TGun): Tool?
	local source = GunsCore.GetModel(gun)
	if not source then
		warn(`[buildGunTool] no ReplicatedStorage.Models.Guns model for {gun.Name} ({gun.ModelName})`)
		return nil
	end

	local model = source:Clone()
	local frame = GunsCore.FindAxes(model, gun)
	local low, high = measure(model, frame)
	model:ScaleTo(model:GetScale() * gun.Length / math.max(high.X - low.X, 1e-3))
	frame = GunsCore.FindAxes(model, gun)
	low, high = measure(model, frame)

	local grip = frame * Vector3.new(low.X + (high.X - low.X) * GRIP_ALONG, low.Y + (high.Y - low.Y) * GRIP_UP, 0)
	local forward = frame.XVector
	local up = frame.YVector
	local tool = Instance.new("Tool")
	tool.Name = gun.Name
	tool.CanBeDropped = false
	tool.ManualActivationOnly = true
	tool.RequiresHandle = true

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.one * 0.2
	handle.Transparency = 1
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	handle.Massless = true
	handle.CFrame = CFrame.fromMatrix(grip, forward:Cross(up), up, -forward)
	handle.Parent = tool

	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Parent = handle
	-- A model says where its barrel ends with a `Muzzle` attachment; without one it is the middle of the front, which
	-- on a gun with a long grip is under the barrel.
	local barrelEnd = model:FindFirstChild("Muzzle", true)
	muzzle.WorldPosition = if barrelEnd and barrelEnd:IsA("Attachment")
		then barrelEnd.WorldPosition
		else frame * Vector3.new(high.X, (low.Y + high.Y) / 2, 0)

	local slide = model:FindFirstChild("Slide")
	local slideBody = if slide and slide:IsA("Model") then slide.PrimaryPart else nil
	for _, part in getParts(model) do
		part.Anchored = false
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.CastShadow = false
		if part == slideBody then continue end

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = if slideBody and part:IsDescendantOf(slide) then slideBody else handle
		weld.Part1 = part
		weld.Parent = handle
	end

	if slideBody then
		local weld = Instance.new("Weld")
		weld.Name = "Slide"
		weld.Part0 = handle
		weld.Part1 = slideBody
		weld.C0 = handle.CFrame:ToObjectSpace(slideBody.CFrame)
		weld.Parent = handle
	end

	model.Name = "Model"
	model.Parent = tool
	return tool
end
