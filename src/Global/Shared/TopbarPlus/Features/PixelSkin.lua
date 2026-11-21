-- Last Wave: draws the pixel Slab (UI.md) on every icon, inside its box: the Widget clips, so nothing can hang outside
-- it. Ink edges, a lit top row and a shaded bottom row; the edges light gold under the hand and the face squashes on a
-- press and springs back.

local TweenService = game:GetService("TweenService")

local UNIT = 2
local INK = Color3.fromRGB(16, 12, 26)
local HOT = Color3.fromRGB(255, 236, 150)
local PRESS_INFO = TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local RELEASE_INFO = TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local PixelSkin = {}

local function edge(parent: Instance, name: string, position: UDim2, size: UDim2, color: Color3, alpha: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = alpha
	frame.Position = position
	frame.Size = size
	frame.ZIndex = 25
	frame.Active = false
	frame.Parent = parent
	return frame
end

function PixelSkin.apply(icon)
	local button = icon:getInstance("IconButton")
	local clickRegion = icon:getInstance("ClickRegion")
	if not button or not clickRegion then return end

	local edges = {
		edge(button, "PixelTop", UDim2.new(), UDim2.new(1, 0, 0, UNIT), INK, 0),
		edge(button, "PixelBottom", UDim2.new(0, 0, 1, -UNIT), UDim2.new(1, 0, 0, UNIT), INK, 0),
		edge(button, "PixelLeft", UDim2.new(), UDim2.new(0, UNIT, 1, 0), INK, 0),
		edge(button, "PixelRight", UDim2.new(1, -UNIT, 0, 0), UDim2.new(0, UNIT, 1, 0), INK, 0),
	}
	local lit = edge(button, "PixelLit", UDim2.fromOffset(UNIT, UNIT), UDim2.new(1, -2 * UNIT, 0, UNIT), HOT, 0.8)
	edge(button, "PixelShade", UDim2.new(0, UNIT, 1, -2 * UNIT), UDim2.new(1, -2 * UNIT, 0, UNIT), INK, 0.55)

	local scale = Instance.new("UIScale")
	scale.Parent = button

	local function setHot(isHot: boolean)
		for _, frame in edges do
			frame.BackgroundColor3 = if isHot then HOT else INK
		end
		lit.BackgroundTransparency = if isHot then 0.45 else 0.8
	end

	icon.janitor:Add(icon.viewingStarted:Connect(function()
		setHot(true)
	end))
	icon.janitor:Add(icon.viewingEnded:Connect(function()
		setHot(false)
	end))
	icon.janitor:Add(clickRegion.MouseButton1Down:Connect(function()
		TweenService:Create(scale, PRESS_INFO, { Scale = 0.88 }):Play()
	end))
	local function release()
		TweenService:Create(scale, RELEASE_INFO, { Scale = 1 }):Play()
	end
	icon.janitor:Add(clickRegion.MouseButton1Up:Connect(release))
	icon.janitor:Add(clickRegion.MouseLeave:Connect(release))
end

return PixelSkin
