-- Where a gun's hands close and its barrel runs, in its Handle's space: the data's shares (TGun.Hands, TGun.Barrel)
-- of the box round every part but the Handle, whose back is the Handle's +Z. First and third person read the same
-- points, so a hand is on the same grip in both.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TData = require(ReplicatedStorage.Types.TData)

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

export type TGunGrips = {
	Right: Vector3,
	Left: Vector3,
	-- The barrel's axis at the right hand's depth.
	Barrel: Vector3,
}

return function(gun: TData.TGun, handle: BasePart, root: Instance): TGunGrips
	local low, high = Vector3.one * math.huge, Vector3.one * -math.huge
	local origin = handle.CFrame
	for _, part in root:GetDescendants() do
		if not part:IsA("BasePart") or part == handle then continue end
		local offset = origin:ToObjectSpace(part.CFrame)
		local half = part.Size / 2
		for _, corner in CORNERS do
			local point = offset * (half * corner)
			low = low:Min(point)
			high = high:Max(point)
		end
	end

	local size = high - low
	local right = gun.Hands.Right
	local left = gun.Hands.Left
	local rightHand = Vector3.new(0, low.Y + size.Y * right.Y, high.Z - size.Z * right.X)
	return {
		Right = rightHand,
		Left = Vector3.new(0, low.Y + size.Y * left.Y, high.Z - size.Z * left.X),
		Barrel = Vector3.new(0, low.Y + size.Y * gun.Barrel, rightHand.Z),
	}
end
