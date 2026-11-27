-- Size vs Brick SpecialMesh Scale, one long box each, at three rotations (none, yaw 45, lookAt up).
return function(Context)
	local floor = Instance.new("Part"); floor.Anchored = true; floor.Size = Vector3.new(40, 1, 30); floor.Position = Vector3.new(0, -0.5, 0); floor.Parent = workspace
	local rots = { CFrame.identity, CFrame.Angles(0, math.rad(45), 0), CFrame.lookAt(Vector3.zero, Vector3.new(0.3, 0.5, 1)) }
	for i, rot in rots do
		for side = 0, 1 do
			local p = Instance.new("Part"); p.Anchored = true; p.Material = Enum.Material.Neon
			p.Color = if side == 0 then Color3.new(1, 0.2, 0.2) else Color3.new(0.2, 0.4, 1)
			if side == 0 then p.Size = Vector3.new(0.5, 0.5, 4) else
				p.Size = Vector3.one
				local m = Instance.new("SpecialMesh"); m.MeshType = Enum.MeshType.Brick; m.Scale = Vector3.new(0.5, 0.5, 4); m.Parent = p
			end
			p.CFrame = CFrame.new(-8 + i * 6 + side * 2, 3, 0) * rot
			p.Parent = workspace
		end
	end
end
