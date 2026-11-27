-- 240 sparks a frame: Part.Size write vs SpecialMesh.Scale write, both moved by one BulkMoveTo.
return function(Context)
	local Workspace = game:GetService("Workspace")
	local RunService = game:GetService("RunService")
	local N, FRAMES = 240, 120
	local function build(withMesh)
		local f = Instance.new("Folder")
		local parts, meshes = {}, {}
		for i = 1, N do
			local p = Instance.new("Part")
			p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
			p.Material = Enum.Material.Neon; p.CastShadow = false
			p.Size = Vector3.new(0.18, 0.18, 1)
			if withMesh and withMesh ~= "none" then
				local m = Instance.new("SpecialMesh"); m.MeshType = Enum.MeshType.Brick; m.Parent = p
				p.Size = Vector3.one
				meshes[i] = m
			end
			p.Parent = f
			parts[i] = p
		end
		f.Parent = Workspace
		return f, parts, meshes
	end
	local frames = table.create(N)
	local function run(label, withMesh)
		local f, parts, meshes = build(withMesh)
		RunService.Heartbeat:Wait()
		local t0 = Context.WorkSeconds()
		for k = 1, FRAMES do
			for i = 1, N do
				local thick = 0.1 + ((i + k) % 7) * 0.01
				local long = 0.5 + ((i * 3 + k) % 11) * 0.1
				if withMesh == "none" then elseif withMesh then meshes[i].Scale = Vector3.new(thick, thick, long) else parts[i].Size = Vector3.new(thick, thick, long) end
				local at = Vector3.new(i, 5 + k * 0.01, 0)
				frames[i] = CFrame.lookAt(at, at + Vector3.new(1, 0.2, 0.3)) * CFrame.new(0, 0, long / 2)
			end
			Workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
			RunService.Heartbeat:Wait()
		end
		local ms = (Context.WorkSeconds() - t0) * 1000 / FRAMES
		print(string.format("%s: %.3f ms/frame for %d sparks", label, ms, N))
		f:Destroy()
		RunService.Heartbeat:Wait()
	end
	run("no write", "none")
	run("Part.Size", false)
	run("SpecialMesh.Scale", true)
	run("Part.Size again", false)
	run("SpecialMesh.Scale again", true)
	print("@done")
end
