-- ConsoleUI's spinner as it was: a source ticked by a task.wait loop forever, a hidden label's Text derived from it.
return function(Context)
	local RS = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")
	local vide = require(RS.Packages.vide)
	local gui = Instance.new("ScreenGui"); gui.Enabled = false; gui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
	local loadingSteps = { "-", "/", "|", "\\" }
	local loadingDt
	vide.root(function()
		loadingDt = vide.source(0)
		local label = vide.create("TextLabel")({ Visible = false, Text = function()
			return `{loadingSteps[(loadingDt() * 6 // 1) % 4 + 1]} - {loadingDt() * 100 // 1 / 100}\ts`
		end })
		label.Parent = gui
	end)
	for _ = 1, 30 do RunService.Heartbeat:Wait() end
	local t0 = Context.WorkSeconds()
	for _ = 1, 300 do RunService.Heartbeat:Wait() end
	local idle = (Context.WorkSeconds() - t0) / 300 * 1e6
	task.spawn(function() while true do loadingDt(loadingDt() + task.wait()) end end)
	for _ = 1, 30 do RunService.Heartbeat:Wait() end
	t0 = Context.WorkSeconds()
	for _ = 1, 300 do RunService.Heartbeat:Wait() end
	local ticking = (Context.WorkSeconds() - t0) / 300 * 1e6
	print(string.format("spinner clock ticking %.2f us/frame, not ticking %.2f us/frame (harness loop included in both)", ticking, idle))
	print("@done")
end
