-- Left row: sparks stretched by Part.Size (before). Right row: by a Brick SpecialMesh's Scale (after).
return function(Context)
	local function spark(x, z, thick, long, mesh)
		local p = Instance.new("Part")
		p.Anchored = true; p.CastShadow = false; p.Material = Enum.Material.Neon
		p.Color = Color3.fromRGB(255, 175, 20)
		if mesh then
			p.Size = Vector3.one
			local m = Instance.new("SpecialMesh"); m.MeshType = Enum.MeshType.Brick; m.Scale = Vector3.new(thick, thick, long); m.Parent = p
		else
			p.Size = Vector3.new(thick, thick, long)
		end
		local at = Vector3.new(x, 3, z)
		p.CFrame = CFrame.lookAt(at, at + Vector3.new(0.3, 0.5, 1)) * CFrame.new(0, 0, long / 2)
		p.Parent = workspace
	end
	local floor = Instance.new("Part"); floor.Anchored = true; floor.Size = Vector3.new(40, 1, 30); floor.Position = Vector3.new(0, -0.5, 0); floor.Color = Color3.fromRGB(90, 140, 80); floor.Parent = workspace
	for i = 0, 5 do
		local thick = 0.18 * (0.4 + 0.6 * (1 - i / 6))
		local long = math.max(thick, 2.5 * (1 - i / 6))
		spark(-6, -8 + i * 3, thick, long, false)
		spark(6, -8 + i * 3, thick, long, true)
	end
end
