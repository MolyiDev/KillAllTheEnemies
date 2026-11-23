-- Every player wears the same blocky R6 body: their head, face, skin colour, classic Shirt and Pants and rigid
-- accessories on the default limbs. A body bundle's limbs and layered clothing are stripped from the description.
local blockyBody = {}

-- The description the avatar is loaded with: the default limbs, without layered clothing.
function blockyBody.Describe(description: HumanoidDescription)
	description.Torso = 0
	description.LeftArm = 0
	description.RightArm = 0
	description.LeftLeg = 0
	description.RightLeg = 0

	local kept = {}
	for _, accessory in description:GetAccessories(true) do
		if not accessory.IsLayered then table.insert(kept, accessory) end
	end

	description:SetAccessories(kept, true)
end

return blockyBody
