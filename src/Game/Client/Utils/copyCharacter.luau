-- A copy of a character with everything but its looks taken out, or nil when it cannot be copied: the Decoy's doll,
-- and the avatar on the Decoy's card. The copy's parts stay as the avatar loaded them (the engine paints the face and
-- the clothes onto a body through its Humanoid only while they are), so nothing here repaints one.
return function(source: Model): Model?
	local wasArchivable = source.Archivable
	source.Archivable = true
	local copy = source:Clone()
	source.Archivable = wasArchivable
	if not copy then return nil end

	for _, child in copy:GetDescendants() do
		if
			child:IsA("LuaSourceContainer")
			or child:IsA("Tool")
			or child:IsA("Sound")
			or child:IsA("ForceField")
			or child:IsA("BillboardGui")
			or child:IsA("ParticleEmitter")
			or child:IsA("Light")
		then
			child:Destroy()
		end
	end

	-- The Humanoid stays, since clothes are drawn through it, but shows no name or bar and runs nothing.
	local humanoid = copy:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.BreakJointsOnDeath = false
		humanoid.RequiresNeck = false
	end

	return copy
end
