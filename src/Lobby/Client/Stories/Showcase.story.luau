-- Every look of the art behind a thing on show (GlobalClient/UI/Showcase) side by side, at one spot's size, accent
-- and floor, round a stand-in for what stands there (a glyph, or a blocky body), in UI Labs. Spot: Weapons, Classes,
-- Index, Prize (day 7's card). Moment: Rest, Enter (the art coming in), Cheer (a purchase, a claim, a reveal), Leave
-- (going), each played again every LOOP seconds. Floor: Own (what each look draws on that screen), one floor under
-- every look (even on a spot whose screen draws none), or None. The look the game draws is Showcase.GAME_LOOKS.
--
-- A generic story (render + subscribe), as UI Labs reads its controls as UILabs.Choose / Boolean objects; the gallery
-- is rebuilt on every change and scaled down to fit the widget.
--
-- Offline with rur, where the group-owned images 403, Offline swaps them for the local PNGs they were made from:
--   rur-native render --headless --offline --rojo <lobby.project.json without its comments> \
--     --story src/Lobby/Client/Stories/Showcase.story.luau --viewport <3 cells by 2, SPOTS' Cell> --scale 1 \
--     --background 40,40,60 --time 2 --controls '{"Spot": "Weapons", "Moment": "Rest", "Floor": "Own", "Offline": true}' \
--     --dir <out>
-- and `rur-native sequence` the same way for the motion.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local UILabs = require(ReplicatedStorage.Packages.UILabs)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Icons = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Icons)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Showcase = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Showcase)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)

local source = vide.source
local create = vide.create
local Palette = Theme.Palette

local ROOT = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/hud/"
local SWAPS = {
	[Icons.Pictures.Gem.Image] = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/rendered/Pictures1.png",
	[Icons.Pictures.Potion.Image] = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/rendered/Pictures2.png",
	[Icons.Pictures.Pointer.Image] = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/rendered/Pictures3.png",
	[Icons.Pictures.UpArrow.Image] = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/rendered/Pictures4.png",
	[Icons.Pictures.SurvivorVest.Image] = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/rendered/Pictures5.png",
	[Icons.IMAGE] = ROOT .. "Icons.png",
	[Icons.PANEL_TEXTURE] = ROOT .. "PanelTexture.png",
	[Icons.SHOWCASE] = ROOT .. "Showcase.png",
	[Icons.SHOWCASE_FLOOR] = ROOT .. "ShowcaseFloor.png",
}
local ENTER_AT = 0.3
local ENTER_SECONDS = 0.45
local CHEER_AT = 0.6
local LEAVE_AT = 0.6
local LEAVE_SECONDS = 0.22
local LOOP = 2.5
local LABEL = 28
local BACKGROUND = Color3.fromRGB(40, 40, 60)
local SPOT_NAMES = { "Weapons", "Classes", "Index", "Prize" }
local MOMENTS = { "Rest", "Enter", "Cheer", "Leave" }
-- "His" is the weapons screen's ellipse (Icons.FLOOR_OFFSET), the rest the floor atlas's cells.
local FLOORS = { "Own", "Pad", "Dots", "Reticle", "Ring", "His", "None" }
-- A floor atlas cell under his rings, about as strong as the looks draw theirs.
local CELL_UNDER_RINGS = 0.4

-- Each spot as its screen draws it: the art's size and floor, its accent, the cell round it, the card it sits in (nil
-- on the open screen), the floor's size (for a picked floor where the screen draws none), and the stand-in: a glyph
-- and its box, or the blocky body.
local SPOTS = {
	Weapons = {
		Diameter = 640,
		Floor = 242,
		Accent = Palette.Green,
		Cell = Vector2.new(820, 720),
		FloorSize = Vector2.new(470, 84),
		-- His floor only: on the weapons stage the gun floats in every other look.
		HasLookFloor = false,
		Glyph = "Rifle",
		Item = 380,
		ItemAt = 30,
	},
	Classes = {
		Diameter = 580,
		Floor = 270,
		-- Human's rarity, Common.
		Accent = Palette.Grey,
		Cell = Vector2.new(760, 760),
		FloorSize = Vector2.new(461, 84),
		Body = 400,
	},
	Index = {
		Diameter = 340,
		Floor = 176,
		Accent = Palette.Steel,
		Cell = Vector2.new(480, 500),
		Card = Vector2.new(392, 396),
		CardMiddle = Vector2.new(196, 176),
		Rings = 244,
		FloorSize = Vector2.new(250, 45),
		Glyph = "Skull",
		Item = 170,
		ItemAt = 20,
	},
	Prize = {
		Diameter = 600,
		Floor = 110,
		Accent = Palette.Violet,
		Cell = Vector2.new(480, 620),
		Card = Vector2.new(400, 518),
		CardMiddle = Vector2.new(200, 270),
		Band = 52,
		Rings = 300,
		FloorSize = Vector2.new(280, 50),
		-- The card draws no floor in any look.
		HasLookFloor = false,
		HasRingsFloor = false,
		Glyph = "Rifle",
		Item = 260,
		ItemAt = 0,
	},
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

-- A blocky body standing on the floor, `height` px tall, its feet at the art's floor.
local function body(height: number, floor: number): Frame
	local unit = height / 5
	local function block(name: string, x: number, y: number, w: number, h: number, color: Color3): Frame
		return create("Frame")({
			Name = name,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, math.round(x * unit), 0.5, math.round(floor - height + y * unit)),
			Size = UDim2.fromOffset(math.round(w * unit), math.round(h * unit)),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = 3,
		})
	end
	return create("Frame")({
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 3,
		block("Head", 0, 0, 1, 1, Color3.fromRGB(255, 205, 64)),
		block("Torso", 0, 1, 2, 2, Color3.fromRGB(72, 160, 90)),
		block("LeftArm", -1.5, 1, 1, 2, Color3.fromRGB(255, 205, 64)),
		block("RightArm", 1.5, 1, 1, 2, Color3.fromRGB(255, 205, 64)),
		block("Legs", 0, 3, 2, 2, Color3.fromRGB(44, 110, 200)),
	})
end

local function cell(look: string, spot: any, floorPick: string, column: number, row: number, timeline: any): Frame
	local shown = timeline.Shown
	local at = if spot.Card
		then UDim2.fromOffset(spot.CardMiddle.X - 3, spot.CardMiddle.Y - 3 - (spot.Band or 0))
		else UDim2.fromScale(0.5, 0.5)
	local isOwnFloor = floorPick == "Own"
	local hasFloor = floorPick ~= "None"
	local hasLookFloor = if isOwnFloor then spot.HasLookFloor ~= false else hasFloor
	local art, front = Showcase.Build({
		Look = look,
		Diameter = spot.Diameter,
		Floor = spot.Floor,
		FloorSize = if hasLookFloor then spot.FloorSize else nil,
		FloorCell = if isOwnFloor then nil else floorPick,
		Accent = function()
			return spot.Accent
		end,
		Shown = shown,
		CheeredAt = timeline.CheeredAt,
		IsActive = function()
			return true
		end,
	}, { Position = at }, { Position = at, ZIndex = 4 })

	-- His rings, for the control: two faint circles, his size in a card, a little inside the art's on a stage.
	local rings = spot.Rings or math.round(spot.Diameter * 0.9)
	local ringFrames = if look == "Rings"
		then {
			create("Frame")({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(rings, rings),
				BackgroundTransparency = 1,
				create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
				create("UIStroke")({ Color = Color3.fromRGB(139, 111, 211), Thickness = 1.5, Transparency = 0.75 }),
			}),
			create("Frame")({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(math.round(rings * 0.73), math.round(rings * 0.73)),
				BackgroundColor3 = spot.Accent,
				BackgroundTransparency = 0.94,
				create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
				create("UIStroke")({ Color = spot.Accent, Thickness = 1.5, Transparency = 0.72 }),
			}),
		}
		else nil

	local item = if spot.Body
		then body(spot.Body, spot.Floor)
		else Components.Icon(spot.Glyph, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, spot.ItemAt),
			Size = UDim2.fromOffset(spot.Item, spot.Item),
			ImageColor3 = Palette.White,
			ZIndex = 3,
		})

	-- His floor, or the picked one, for the control; every other look draws its own. No cell is his.
	local hasRingsFloor = if isOwnFloor then spot.HasRingsFloor ~= false else hasFloor
	local cellAt = Icons.ShowcaseFloorCells[floorPick]
	local floor = if look == "Rings" and hasRingsFloor
		then create("ImageLabel")({
			Name = "Floor",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, spot.Floor),
			Size = UDim2.fromOffset(spot.FloorSize.X, spot.FloorSize.Y),
			BackgroundTransparency = 1,
			Image = if cellAt then Icons.SHOWCASE_FLOOR else Icons.IMAGE,
			ImageRectOffset = if cellAt then cellAt.Offset else Icons.FLOOR_OFFSET,
			ImageRectSize = if cellAt then cellAt.Size else Icons.FLOOR_SIZE,
			ImageColor3 = if spot.Card then spot.Accent else Palette.Pink,
			ImageTransparency = if cellAt then CELL_UNDER_RINGS else Icons.FLOOR_TRANSPARENCY,
			ZIndex = 1,
		})
		else nil

	-- In a card, the art and its particles are clipped to its face under the band, as on the screens.
	local function clipped(name: string, child: Frame?, zIndex: number): Frame
		return create("Frame")({
			Name = name,
			Position = UDim2.fromOffset(3, 3 + (spot.Band or 0)),
			Size = UDim2.fromOffset(spot.Card.X - 6, spot.Card.Y - 6 - (spot.Band or 0)),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = zIndex,
			child,
		})
	end
	local stage = if spot.Card
		then Components.Card({
			Accent = spot.Accent,
			Glow = spot.Accent,
			Tint = 0.3,
			Tall = true,
		}, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(spot.Card.X, spot.Card.Y),
			create("Frame")({
				Name = "Band",
				Position = UDim2.fromOffset(3, 3),
				Size = UDim2.new(1, -6, 0, spot.Band or 0),
				BackgroundColor3 = Color3.fromRGB(18, 12, 34),
				BorderSizePixel = 0,
				Visible = spot.Band ~= nil,
				ZIndex = 2,
			}),
			clipped("Art", art, 2),
			clipped("ArtFront", front, 4),
			create("Frame")({
				Name = "Middle",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(spot.CardMiddle.X, spot.CardMiddle.Y),
				Size = UDim2.fromOffset(0, 0),
				BackgroundTransparency = 1,
				ZIndex = 3,
				ringFrames,
				floor,
				item,
			}),
		})
		else create("Frame")({
			Name = "Stage",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(0, 0),
			BackgroundTransparency = 1,
			art,
			ringFrames,
			floor,
			item,
			front,
		})

	return create("Frame")({
		Name = look,
		Position = UDim2.fromOffset(column * spot.Cell.X, row * spot.Cell.Y),
		Size = UDim2.fromOffset(spot.Cell.X, spot.Cell.Y),
		BackgroundTransparency = 1,
		create("TextLabel")({
			Position = UDim2.fromOffset(16, 10),
			Size = UDim2.fromOffset(spot.Cell.X - 32, LABEL),
			BackgroundTransparency = 1,
			FontFace = Theme.Font.Display,
			TextSize = LABEL,
			TextColor3 = Palette.Lavender,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = string.upper(look),
		}),
		create("Frame")({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, LABEL / 2),
			Size = UDim2.fromOffset(0, 0),
			BackgroundTransparency = 1,
			stage,
		}),
	})
end

-- The six looks for `spot`, playing `moment` over `floorPick`, scaled down to fit `target`.
local function gallery(target: Frame, spotName: string, moment: string, floorPick: string, isOffline: boolean): Frame
	local spot = SPOTS[spotName]
	local start = os.clock()
	local now = source(start)
	local ticker = RunService.Heartbeat:Connect(function()
		now(os.clock())
	end)
	vide.cleanup(function()
		ticker:Disconnect()
	end)

	-- When the moment's loop last began.
	local function loopAt(): number
		return start + LOOP * math.floor((now() - start) / LOOP)
	end
	local timeline = {
		Shown = function(): number
			local t = now() - loopAt()
			if moment == "Enter" then
				return Motion.Out(Motion.Progress(t, ENTER_AT, ENTER_SECONDS))
			elseif moment == "Leave" then
				return 1 - Motion.Progress(t, LEAVE_AT, LEAVE_SECONDS)
			end
			return 1
		end,
		CheeredAt = function(): number
			return if moment == "Cheer" then loopAt() + CHEER_AT else -math.huge
		end,
	}

	local cells = table.create(#Showcase.LOOKS)
	for index, look in Showcase.LOOKS do
		cells[index] = cell(look, spot, floorPick, (index - 1) % 3, (index - 1) // 3, timeline)
	end

	local size = Vector2.new(3 * spot.Cell.X, 2 * spot.Cell.Y)
	local fit = source(1)
	local function refit()
		local room = target.AbsoluteSize
		if room.X <= 0 or room.Y <= 0 then return end
		fit(math.min(room.X / size.X, room.Y / size.Y, 1))
	end
	local resized = target:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
	vide.cleanup(function()
		resized:Disconnect()
	end)
	refit()

	local root = create("Frame")({
		Name = "Gallery",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size.X, size.Y),
		create("UIScale")({ Scale = fit }),
		cells,
	})
	if isOffline then swapImages(root) end

	return root
end

local CONTROLS = {
	Spot = UILabs.Ordered(UILabs.Choose(SPOT_NAMES, 1), 1),
	Moment = UILabs.Ordered(UILabs.Choose(MOMENTS, 1), 2),
	Floor = UILabs.Ordered(UILabs.Choose(FLOORS, 1), 3),
	Offline = UILabs.Ordered(UILabs.Boolean(false), 4),
}

return {
	summary = "The art behind a thing on show: every Showcase look side by side at one spot's size.",
	controls = CONTROLS,

	render = function(props)
		local values: { [string]: any } = table.clone(props.controls)
		local unmount: (() -> ())? = nil

		local frame = Instance.new("Frame")
		frame.Name = "ShowcaseBench"
		frame.BackgroundColor3 = BACKGROUND
		frame.ClipsDescendants = true
		frame.Size = UDim2.fromScale(1, 1)
		frame.Parent = props.target

		local function build()
			if unmount then unmount() end
			-- The mount frees the state, not the instances.
			frame:ClearAllChildren()
			unmount = vide.mount(function()
				return gallery(frame, values.Spot, values.Moment, values.Floor, values.Offline)
			end, frame)
		end
		build()

		local unsubscribe = props.subscribe(function(nextValues)
			values = table.clone(nextValues)
			build()
		end)

		return function()
			unsubscribe()
			if unmount then unmount() end
			frame:Destroy()
		end
	end,
}
