return function(Context)
	local RunService = game:GetService("RunService")
	local gui = Instance.new("ScreenGui"); gui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
	local labels, strokes = {}, {}
	for i = 1, 48 do
		local l = Instance.new("TextLabel"); l.Text = tostring(i * 37); l.Size = UDim2.fromOffset(80, 30); l.Parent = gui
		local s = Instance.new("UIStroke"); s.Parent = l
		labels[i], strokes[i] = l, s
	end
	local N = 300
	local function run(skip)
		local last = {}
		local t0 = Context.WorkSeconds()
		for f = 1, N do
			for i, l in labels do
				local rot, tr = 4, 0.1
				if skip then
					if last[i] ~= rot then l.Rotation = rot; last[i] = rot end
				else
					l.Rotation = rot; l.TextTransparency = tr; strokes[i].Transparency = tr
				end
			end
		end
		return (Context.WorkSeconds() - t0) / N * 1e6
	end
	local a = run(false); local b = run(true)
	print(string.format("48 popups: 3 unchanged writes each %.1f us/frame, skipped %.1f us/frame", a, b))
	print("@done")
end
