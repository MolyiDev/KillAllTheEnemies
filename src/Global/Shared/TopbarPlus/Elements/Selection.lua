return function(Icon)
	-- Credit to lolmansReturn and Canary Software for
	-- retrieving these values
	local selectionContainer = Instance.new("Frame")
	selectionContainer.Name = "SelectionContainer"
	-- Transparent wrapper: the visible ring is the inner `selection` frame's
	-- UIStroke. Without this the container shows its default opaque gray, which
	-- is harmless while it stays Visible=false (gamepad selection) but renders a
	-- gray box over the icon when :setHighlight makes the container itself visible.
	selectionContainer.BackgroundTransparency = 1
	selectionContainer.Visible = false

	local selection = Instance.new("Frame")
	selection.Name = "Selection"
	selection.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	selection.BackgroundTransparency = 1
	selection.BorderColor3 = Color3.fromRGB(0, 0, 0)
	selection.BorderSizePixel = 0
	selection.Parent = selectionContainer

	local UIStroke = Instance.new("UIStroke")
	UIStroke.Name = "UIStroke"
	UIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	UIStroke.Color = Color3.fromRGB(255, 255, 255)
	UIStroke.Thickness = 3
	UIStroke.Parent = selection

	local selectionGradient = Instance.new("UIGradient")
	selectionGradient.Name = "SelectionGradient"
	selectionGradient.Parent = UIStroke

	local UICorner = Instance.new("UICorner")
	UICorner:SetAttribute("Collective", "IconCorners")
	UICorner.Name = "UICorner"
	UICorner.CornerRadius = UDim.new(1, 0)
	UICorner.Parent = selection

	local RunService = game:GetService("RunService")
	local GuiService = game:GetService("GuiService")
	local rotationSpeed = 1
	selection:GetAttributeChangedSignal("RotationSpeed"):Connect(function()
		rotationSpeed = selection:GetAttribute("RotationSpeed")
	end)
	RunService.Heartbeat:Connect(function()
		-- Animate while this icon is the gamepad selection (used as a
		-- SelectionImageObject, container stays Visible=false) OR while shown as a
		-- manual visible highlight via Icon:setHighlight (container Visible=true,
		-- used by the tutorial on mobile / PC where there's no selection focus).
		if not GuiService.SelectedObject and not selectionContainer.Visible then return end
		selectionGradient.Rotation = (os.clock() * rotationSpeed * 100) % 360
	end)

	return selectionContainer
end
