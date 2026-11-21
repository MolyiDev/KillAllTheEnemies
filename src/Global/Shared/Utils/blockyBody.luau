-- Every player wears the same blocky body: R6-shaped parts on an R15 rig. R15 for the US 18+ DevEx rate, R6-shaped
-- because the game is animated like R6 (straight limbs, an arm free to leave its shoulder). Body bundles, Rthro
-- proportions and layered clothing fight that (a layered jacket smears across the gap when an arm flies off), so they
-- are stripped from the description; head, face, skin colour, classic Shirt and Pants and rigid accessories stay.
--
-- ReplicatedStorage.Models.R6Body is R6ify's R15 Freshener set (DevForum 4607425), its shoulder and hip attachments
-- moved to where R6's joints sit, baked into the assets. Shared because the pack screen's doll is built on the client.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Copied from BeACastleLord with the place that holds it: insert ReplicatedStorage.Models.R6Body from that place.
-- Until it is there the avatar loads on the default R15 body (Describe still strips layered clothing and scaling).
local R6_BODY = ReplicatedStorage:WaitForChild("Models"):FindFirstChild("R6Body")

local blockyBody = {}

-- The description the avatar is loaded with: the default body at R6's size, without layered clothing.
function blockyBody.Describe(description: HumanoidDescription)
	description.Torso = 0
	description.LeftArm = 0
	description.RightArm = 0
	description.LeftLeg = 0
	description.RightLeg = 0
	description.BodyTypeScale = 0
	description.ProportionScale = 0
	description.HeightScale = 1
	description.WidthScale = 1
	description.DepthScale = 1
	description.HeadScale = 1

	local kept = {}
	for _, accessory in description:GetAccessories(true) do
		if not accessory.IsLayered then table.insert(kept, accessory) end
	end

	description:SetAccessories(kept, true)
end

-- Swaps the loaded default body's parts for the R6-shaped ones, keeping each part's skin colour.
function blockyBody.Apply(humanoid: Humanoid)
	if not R6_BODY or humanoid.RigType ~= Enum.HumanoidRigType.R15 then return end
	local character = humanoid.Parent
	if not character then return end

	-- Swapping the UpperTorso breaks the neck for a moment, which kills a Humanoid that requires one
	local requiresNeck = humanoid.RequiresNeck
	humanoid.RequiresNeck = false
	for _, source in R6_BODY:GetChildren() do
		if not source:IsA("MeshPart") then continue end
		local part = source:Clone()
		local old = character:FindFirstChild(source.Name)
		if old and old:IsA("BasePart") then part.Color = old.Color end
		humanoid:ReplaceBodyPartR15(Enum.BodyPartR15[source.Name], part)
	end

	humanoid.RequiresNeck = requiresNeck
end

return blockyBody
