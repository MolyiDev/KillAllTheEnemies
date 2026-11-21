-- Headless check of the death ragdoll (Game/Client/Utils/ragdoll) on the R6 zombie's rest shape (tools/rig): a body
-- standing on the floor knocked over from every direction, and one killed mid-air over a drop. Reports how long the
-- fall takes, how flat the body ends up, and how far any limb stretched. Run from the repo root:
--   lune run tools/lune/ragdoll.luau "$PWD"
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local H = require("./harness")(process.args[1])

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Ragdoll = H.require("StarterPlayer/StarterPlayerScripts/Client/Utils/ragdoll")

-- tools/rig/r6_zombie.py's body (Roblox's R6 with the classic head), centred on Y: 5.1 tall, feet at -2.55. The same
-- numbers EnemiesController measures off a rig.
local FEET = -2.55
local rig = Ragdoll.NewRig(Vector3.new(0, FEET + 3, 0), Vector3.new(1, 1, 0.5), 2.1)
Ragdoll.AddLimb(rig, Vector3.new(-1.5, FEET + 3.5, 0), 1.5, false)
Ragdoll.AddLimb(rig, Vector3.new(1.5, FEET + 3.5, 0), 1.5, false)
Ragdoll.AddLimb(rig, Vector3.new(-0.5, FEET + 1.875, 0), 1.875, true)
Ragdoll.AddLimb(rig, Vector3.new(0.5, FEET + 1.875, 0), 1.875, true)

local DT = 1 / 60
local GRAVITY = 196.2 * 0.6
local KNOCK = 12

local function run(label: string, standY: number, floorY: number, direction: Vector3, dt: number)
	local pose = CFrame.new(0, standY - FEET, 0)
	local limbs = { pose, pose, pose, pose }
	local body = Ragdoll.Start(rig, pose, limbs, direction * (KNOCK * 0.2), direction * KNOCK, floorY)
	local t, steps = 0, 0
	local worstStretch = 0
	repeat
		local settled = Ragdoll.Step(body, dt, GRAVITY)
		t += dt
		steps += 1
		for i, length in rig.Lengths do
			local joint = Ragdoll.LimbFrame(body, i) * rig.Joints[i]
			local tip = body.points[4 + i]
			worstStretch = math.max(worstStretch, math.abs((tip - joint).Magnitude - length))
		end
		local c = body.center
		assert(c.X == c.X and c.Y == c.Y, "NaN")
	until settled or steps > 1000
	local torso = Ragdoll.TorsoFrame(body)
	local upY = torso.UpVector.Y
	local feetLift = math.huge
	for i = 3, 4 do
		feetLift = math.min(feetLift, body.points[4 + i].Y - floorY)
	end
	return string.format(
		"%-22s %s %.2fs | torso up.y %+.2f (0 = lying) | centre %.2f over floor, slid %.1f | top %.2f | stretch %.3f",
		label,
		if body.hasLanded then "landed" else "GAVE UP",
		t,
		upY,
		body.center.Y - floorY,
		Vector3.new(body.center.X, 0, body.center.Z).Magnitude,
		Ragdoll.TopY(body) - floorY,
		worstStretch
	)
end

for _, deg in { 0, 45, 90, 135, 180, 225, 270, 315 } do
	local r = math.rad(deg)
	print(run(`ground, push {deg} deg`, 0, 0, Vector3.new(math.sin(r), 0, math.cos(r)), DT))
end
print(run("ground, 30 fps", 0, 0, Vector3.new(0, 0, 1), 1 / 30))
print(run("ground, 144 fps", 0, 0, Vector3.new(0, 0, 1), 1 / 144))
print(run("off a deck, 8 drop", 8, 0, Vector3.new(1, 0, 0), DT))
print(run("into the void", 0, -1000, Vector3.new(1, 0, 0), DT))
