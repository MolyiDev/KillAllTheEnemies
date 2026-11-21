local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local game = roblox.deserializePlace(fs.readFile("clean.rbxl"))
for i, sg in game:GetService("StarterGui"):GetChildren() do
	local root = roblox.Instance.new("Frame")
	root.Name = "Root"
	root.Size = roblox.UDim2.fromScale(1, 1)
	root.BackgroundColor3 = roblox.Color3.fromRGB(40, 40, 60)
	root.BorderSizePixel = 0
	for _, c in sg:GetChildren() do c:Clone().Parent = root end
	for _, d in root:GetDescendants() do
		if d.ClassName == "ImageLabel" then
			d.BackgroundTransparency = 0.88
			d.BackgroundColor3 = roblox.Color3.fromRGB(140, 120, 255)
			d.BorderSizePixel = 1
			d.BorderColor3 = roblox.Color3.fromRGB(170, 160, 230)
		elseif d.ClassName == "ImageButton" then
			d.BorderSizePixel = 1
			d.BorderColor3 = roblox.Color3.fromRGB(80, 220, 140)
		end
	end
	local file = string.format("models/%02d_%s.rbxm", i, (sg.Name:gsub("[^%w]+", "_")))
	fs.writeFile(file, roblox.serializeModel({ root }))
	print(file)
end
