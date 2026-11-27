return function(Context)
	local RS = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")
	local vide = require(RS.Packages.vide)
	local Hand = require(RS.UI.Hand)
	local results = {}
	local function trial(label, make)
		local reruns, lastAt = 0, 0
		local target
		vide.root(function()
			target = vide.source(false)
			local value = make(function() return if target() then 1 else 0 end)
			vide.effect(function() value(); reruns += 1; lastAt = os.clock() end)
		end)
		target(true)
		for _ = 1, 90 do RunService.Heartbeat:Wait() end
		reruns = 0
		local t0 = os.clock()
		target(false)
		for _ = 1, 60 * 20 do RunService.Heartbeat:Wait() end
		print(string.format("%s: %d reruns after going back to 0, last %.2f s after", label, reruns, lastAt - t0))
	end
	trial("vide.spring", function(t) return (vide.spring(t, 0.2, 0.9)) end)
	trial("Hand.Spring", function(t) return Hand.Spring(t, 0.2, 0.9) end)
	print("@done")
end
