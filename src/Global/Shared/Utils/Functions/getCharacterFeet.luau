-- Where a character's feet are: the root part's centre lowered by half its height and the hip height. Enemy
-- targeting, swings and ground AoE all measure against the feet, the same point an enemy's Position is.
-- `lead` seconds of the current velocity are added flat, so a running target is met where he is going.
return function(rootPart: BasePart, humanoid: Humanoid, lead: number): vector
	local position = rootPart.Position
	local velocity = rootPart.AssemblyLinearVelocity
	local feetY = position.Y - rootPart.Size.Y / 2 - humanoid.HipHeight
	return vector.create(position.X + velocity.X * lead, feetY, position.Z + velocity.Z * lead)
end
