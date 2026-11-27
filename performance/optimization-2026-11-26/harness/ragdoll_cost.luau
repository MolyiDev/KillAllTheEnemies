-- 40 falling corpses: Ragdoll.Step plus the frames EnemiesController writes (torso + 4 limbs), per frame.
return function(Context)
	local RS = game:GetService("ReplicatedStorage")
	local Ragdoll = require(RS.Fx.Client.Utils.ragdoll)
	local FEET = -2.55
	local rig = Ragdoll.NewRig(Vector3.new(0, FEET + 3, 0), Vector3.new(1, 1, 0.5), 2.1)
	Ragdoll.AddLimb(rig, Vector3.new(-1.5, FEET + 3.5, 0), 1.5, false)
	Ragdoll.AddLimb(rig, Vector3.new(1.5, FEET + 3.5, 0), 1.5, false)
	Ragdoll.AddLimb(rig, Vector3.new(-0.5, FEET + 1.875, 0), 1.875, true)
	Ragdoll.AddLimb(rig, Vector3.new(0.5, FEET + 1.875, 0), 1.875, true)
	local bones = {}
	local part = Instance.new("Part"); part.Parent = workspace
	for i = 1, 40 * 5 do local b = Instance.new("Bone"); b.Parent = part; bones[i] = b end
	local bodies = {}
	for i = 1, 40 do
		local pose = CFrame.new(i * 3, 2.55, 0)
		local dir = Vector3.new(math.cos(i), 0, math.sin(i))
		bodies[i] = Ragdoll.Start(rig, pose, { pose, pose, pose, pose }, dir * 2.4, dir * 12, 0)
	end
	local frames = 0
	local w0 = Context.WorkSeconds()
	for f = 1, 30 do
		for i, body in bodies do
			Ragdoll.Step(body, 1 / 60, 117.7)
			local torso = Ragdoll.TorsoFrame(body)
			bones[(i - 1) * 5 + 1].Transform = torso
			for limb = 1, 4 do bones[(i - 1) * 5 + 1 + limb].Transform = Ragdoll.LimbFrame(body, limb) end
		end
		frames += 1
	end
	print(string.format("40 corpses: %.3f ms/frame (%.1f us each)", (Context.WorkSeconds() - w0) * 1000 / frames, (Context.WorkSeconds() - w0) * 1e6 / frames / 40))
	print("@done")
end
