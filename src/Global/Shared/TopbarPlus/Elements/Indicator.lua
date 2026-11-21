return function(icon, Icon)
	local widget = icon.widget
	local contents = icon:getInstance("Contents")

	-- Layout anchor that sits just past the icon's right edge. Auto-sizes on X so
	-- the badge grows with its text; the icon makes room for it via the
	-- IndicatorPadding modification below.
	local indicator = Instance.new("Frame")
	indicator.Name = "Indicator"
	indicator.LayoutOrder = 9999999
	indicator.ZIndex = 6
	indicator.AnchorPoint = Vector2.new(0, 0.5)
	indicator.AutomaticSize = Enum.AutomaticSize.X
	indicator.Size = UDim2.new(0, 0, 0, 42)
	indicator.Position = UDim2.new(1, 0, 0.5, 0)
	indicator.BackgroundTransparency = 1
	indicator.BorderSizePixel = 0
	indicator.Visible = false
	indicator.Parent = contents

	-- The visible pill: dark rounded background with the prompt text.
	local indicatorButton = Instance.new("Frame")
	indicatorButton.Name = "IndicatorButton"
	indicatorButton.AnchorPoint = Vector2.new(0, 0.5)
	indicatorButton.AutomaticSize = Enum.AutomaticSize.X
	indicatorButton.Position = UDim2.new(0, 0, 0.5, 0)
	indicatorButton.Size = UDim2.new(0, 0, 1, 0)
	indicatorButton.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	indicatorButton.BackgroundTransparency = 0.25
	indicatorButton.BorderSizePixel = 0
	indicatorButton.Parent = indicator

	local UICorner = Instance.new("UICorner")
	UICorner.CornerRadius = UDim.new(1, 0)
	UICorner.Parent = indicatorButton

	local UIPadding = Instance.new("UIPadding")
	UIPadding.PaddingLeft = UDim.new(0, 9)
	UIPadding.PaddingRight = UDim.new(0, 9)
	UIPadding.Parent = indicatorButton

	local UIListLayout = Instance.new("UIListLayout")
	UIListLayout.FillDirection = Enum.FillDirection.Horizontal
	UIListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	UIListLayout.Padding = UDim.new(0, 4)
	UIListLayout.Parent = indicatorButton

	-- Optional key glyph (e.g. the gamepad Select button) shown before the text.
	local imageLabel = Instance.new("ImageLabel")
	imageLabel.Name = "IndicatorImage"
	imageLabel.ZIndex = 15
	imageLabel.LayoutOrder = 1
	imageLabel.BackgroundTransparency = 1
	imageLabel.ScaleType = Enum.ScaleType.Fit
	imageLabel.Visible = false
	imageLabel.Parent = indicatorButton

	-- Text prompt (e.g. "Tap"). Replaces the old keycode ImageLabel: the
	-- GetImageForKeyCode path was unused (highlightKey is disabled), so the
	-- indicator is now text-only.
	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "IndicatorLabel"
	textLabel.ZIndex = 15
	textLabel.AnchorPoint = Vector2.new(0, 0.5)
	textLabel.AutomaticSize = Enum.AutomaticSize.X
	textLabel.Position = UDim2.new(0, 0, 0.5, 0)
	textLabel.Size = UDim2.new(0, 0, 1, 0)
	textLabel.BackgroundTransparency = 1
	textLabel.FontFace = Font.new("rbxassetid://12187371840", Enum.FontWeight.Bold, Enum.FontStyle.Normal)
	textLabel.Text = ""
	textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	textLabel.TextSize = 14
	textLabel.LayoutOrder = 2
	textLabel.Parent = indicatorButton

	local GamepadService = game:GetService("GamepadService")
	local function setIndicatorVisible(visibility)
		if visibility == nil then visibility = indicator.Visible end
		if GamepadService.GamepadCursorEnabled then visibility = false end
		if visibility then
			icon:modifyTheme({ "PaddingRight", "Size", UDim2.new(0, 0, 1, 0) }, "IndicatorPadding")
		elseif indicator.Visible then
			icon:removeModification("IndicatorPadding")
		end
		icon:modifyTheme({ "Indicator", "Visible", visibility })
		icon.updateSize:Fire()
	end
	icon.janitor:Add(GamepadService:GetPropertyChangedSignal("GamepadCursorEnabled"):Connect(setIndicatorVisible))
	icon.indicatorSet:Connect(function(text, image)
		-- Only a non-empty string or image shows; nil (or a stray KeyCode from the
		-- old gamepad caller) hides the badge.
		local hasText = typeof(text) == "string" and text ~= ""
		local hasImage = typeof(image) == "string" and image ~= ""
		textLabel.Text = if hasText then text else ""
		textLabel.Visible = hasText
		imageLabel.Image = if hasImage then image else ""
		imageLabel.Visible = hasImage
		setIndicatorVisible(hasText or hasImage)
	end)

	local function updateSize()
		local ySize = widget.AbsoluteSize.Y * 0.96
		indicator.Size = UDim2.new(0, 0, 0, ySize)
		textLabel.TextSize = math.max(12, math.floor(ySize * 0.42))
		local imageSize = math.floor(ySize * 0.6)
		imageLabel.Size = UDim2.fromOffset(imageSize, imageSize)
	end
	widget:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateSize)
	updateSize()

	return indicator
end
