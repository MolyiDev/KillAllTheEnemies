-- 40 rigs x 7 bones, a pose "clip" written each frame (as the Animator would), a blend started every 0.25 s per rig.
return function(Context)
	local RS = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")
	if Context.Before then Context.StandIn(RS.Fx.GlobalClient.Utils.inertialBlend, Context.Before) end
	local IB = require(RS.Fx.GlobalClient.Utils.inertialBlend)
	local RIGS, JOINTS = 40, 7
	local rigs = {}
	for r = 1, RIGS do
		local part = Instance.new("Part"); part.Anchored = true; part.Parent = workspace
		local joints = {}
		for j = 1, JOINTS do
			local b = Instance.new("Bone"); b.Name = "B" .. j; b.Parent = part; joints[j] = b
		end
		-- one in three joints is never keyed by the "clip", as the R6 clips leave some alone
		rigs[r] = { joints = joints, blend = IB.new(joints, false), clip = 0 }
	end
	local frame, sum, t0, stepWork = 0, 0, nil, 0
	local function pose(r, j, clip, t)
		if j % 3 == 0 then return nil end
		local a = math.sin(t * (2 + j) + r) * (0.4 + clip * 0.5)
		return CFrame.new(0, 0.1 * j * clip, 0.05 * math.cos(t + j)) * CFrame.Angles(a, a * 0.5 * clip, -a)
	end
	RunService.PreSimulation:Connect(function(dt)
		frame += 1
		local t = frame / 60
		for r, rig in rigs do
			if (frame + r * 3) % 15 == 0 then
				rig.blend:Start(0.25)
				rig.clip = 1 - rig.clip
			end
			for j, joint in rig.joints do
				local p = pose(r, j, rig.clip, t)
				if p then joint.Transform = p end
			end
		end
		-- PreAnimation never fires in ree: bump the module's pass count the way it would, via its own connection's
		-- absence, by calling Step after a frame's delay (IsPending resolves when animatorPasses > PendingPass).
		Context.FireEvent(RunService, "PreAnimation", 1 / 60)
		local w0 = Context.WorkSeconds()
		for _, rig in rigs do rig.blend:Step(1 / 60, 1) end
		if frame > 60 then stepWork += Context.WorkSeconds() - w0 end
		if frame > 60 then
			for _, rig in rigs do
				for _, joint in rig.joints do
					local cf = joint.Transform
					sum += cf.X * 1.3 + cf.Y * 1.7 + cf.Z * 1.9 + cf.XVector.X + cf.YVector.Z * 2 + cf.ZVector.Y * 3
				end
			end
		end
		if frame == 100 then
			local n = 0
			for _, rig in rigs do if rig.blend.IsBlending then n += 1 end end
			local ok, e = pcall(Context.FireEvent, RunService, "PreAnimation", 1 / 60)
			print("blending", n, "pending", rigs[1].blend.IsPending, rigs[1].blend.PendingPass, ok, e)
		end
		if frame == 60 + 600 then
			print(string.format("%s: %.4f ms/frame Step for %d rigs, checksum %.9f", Context.Label, stepWork * 1000 / 600, RIGS, sum))
			print("@done")
		end
	end)
end
