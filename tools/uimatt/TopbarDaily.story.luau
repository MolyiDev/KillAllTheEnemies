-- The lobby's top bar Daily button (Topbar.Dress with a count, worn as "!", and a call) beside Codes and Settings, on a stand-in for
-- the TopbarPlus icon (the instances and events Dress touches; TopbarPlus itself does not run offline), for rur:
--   rur-native render --headless --offline --rojo <lobby.project.json without its comments> \
--     --story tools/uimatt/TopbarDaily.story.luau --viewport 520x120 --scale 2 --background 40,40,60 --time 1 \
--     --controls '{"Moment": "Waiting"}' --dir <out>
-- Moment: Waiting (3 things wait: the "!", the glow, the light crossing every 1.2 s here), Arrive (the count going
-- from 0 to 3 at 0.3 s), Up (2 to 3 at 0.3 s: nothing should move), Clear (1 to 0 at 0.3 s: the "!" shrinks away),
-- Selected (the screen open), Quiet (nothing waits), for `rur-native sequence`.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Icons = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Icons)
local Topbar = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Topbar)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local source = vide.source
local create = vide.create

local ROOT = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/hud/"
local SWAPS = {
	[Icons.Pictures.Gem.Image] = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/rendered/Pictures1.png",
	[Icons.Pictures.UpArrow.Image] = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/rendered/Pictures4.png",
	[Icons.Pictures.SurvivorVest.Image] = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/rendered/Pictures5.png",
	[Icons.IMAGE] = ROOT .. "Icons.png",
	[Icons.PANEL_TEXTURE] = ROOT .. "PanelTexture.png",
}
local MOMENT_AT = 0.3
local CALL_EVERY = 1.2
local COUNTS = {
	Waiting = { 3, 3 },
	Arrive = { 0, 3 },
	Up = { 2, 3 },
	Clear = { 1, 0 },
	Selected = { 3, 3 },
	Quiet = { 0, 0 },
}

local function swapImages(root: Instance)
	local function swap(instance: Instance)
		if instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
			local path = SWAPS[instance.Image]
			if path then instance.Image = path end
		end
	end

	for _, instance in root:GetDescendants() do
		swap(instance)
	end
	root.DescendantAdded:Connect(swap)
end

-- The parts of a TopbarPlus icon Dress reaches for: its widget, button and click region, the hover and deselect
-- events, its theme and its enabling. Laid out as TopbarPlus lays an icon with an image and a caption.
local function standIn(name: string, picture: string, width: number): (any, Frame)
	local picked = Icons.Pictures[picture]
	local button = create("Frame")({
		Name = "IconButton",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		create("ImageLabel")({
			Name = "IconImage",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 14, 0.5, 0),
			Size = UDim2.fromOffset(22, 22),
			BackgroundTransparency = 1,
			Image = picked.Image,
			ImageRectOffset = picked.Offset,
			ImageRectSize = Icons.PICTURE_CELL_SIZE,
			ZIndex = 2,
		}),
		create("TextLabel")({
			Name = "IconLabel",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 42, 0.5, 0),
			Size = UDim2.new(1, -58, 0, 15),
			BackgroundTransparency = 1,
			FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Medium),
			TextSize = 15,
			TextColor3 = Color3.new(1, 1, 1),
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = name,
			ZIndex = 2,
		}),
		create("TextButton")({
			Name = "ClickRegion",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "",
			ZIndex = 3,
		}),
	})
	local widget = create("Frame")({
		Name = name,
		Size = UDim2.fromOffset(width, 44),
		BackgroundTransparency = 1,
		button,
	})
	local never = Instance.new("BindableEvent").Event
	local icon = {
		viewingStarted = never,
		viewingEnded = never,
		deselected = never,
	}
	function icon:modifyTheme() end
	function icon:setEnabled() end
	function icon:getInstance(part: string): Instance
		if part == "Widget" then return widget end
		if part == "IconButton" then return button end
		return button:FindFirstChild(part) :: Instance
	end

	return icon, widget
end

return {
	vide = vide,
	controls = {
		Moment = { "Waiting", "Arrive", "Up", "Clear", "Selected", "Quiet" },
	},
	story = function(props)
		local moment = props.controls.Moment()
		local counts = COUNTS[moment]
		local at = os.clock() + MOMENT_AT
		local now = source(os.clock())
		local count = source(counts[1])
		local callAt = source(-math.huge)
		local nextCall = os.clock() + 0.5
		RunService.Heartbeat:Connect(function()
			local clock = os.clock()
			now(clock)
			if clock >= at and count() ~= counts[2] then count(counts[2]) end
			if clock >= nextCall then
				nextCall = clock + CALL_EVERY
				callAt(clock)
			end
		end)

		local row = {}
		for index, spec in
			{ { "Daily", EIcons.GiftBox, 108 }, { "Codes", EIcons.Ticket, 112 }, { "Settings", EIcons.Gear, 128 } }
		do
			local icon, widget = standIn(spec[1], spec[2], spec[3])
			widget.LayoutOrder = index
			local isDaily = index == 1
			vide.untrack(function()
				Topbar.Dress(icon, {
					IsSelected = function()
						return isDaily and moment == "Selected"
					end,
					HasBrackets = false,
					Now = now,
					OnPress = function() end,
					Count = if isDaily then count else nil,
					CallAt = if isDaily then callAt else nil,
				})
			end)
			row[index] = widget
		end

		local root = create("Frame")({
			Name = "Root",
			Size = UDim2.fromOffset(520, 120),
			BackgroundTransparency = 1,
			create("Frame")({
				Name = "Bar",
				Position = UDim2.fromOffset(40, 38),
				Size = UDim2.fromOffset(440, 44),
				BackgroundTransparency = 1,
				create("UIListLayout")({
					FillDirection = Enum.FillDirection.Horizontal,
					Padding = UDim.new(0, 12),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
				row,
			}),
		})
		swapImages(root)
		return root
	end,
}
