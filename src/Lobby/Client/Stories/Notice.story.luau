-- Every look of the chip a button wears while something waits behind it (GlobalClient/UI/Notice) side by side, one row a
-- look, on stand-ins for the buttons that wear it: the WEAPONS slab (the up arrow), the INDEX card (a count), a card
-- with "!" (no count) and the top bar's Daily button (a count), at their sizes and places in the lobby. Moment: Rest,
-- Arrive (it comes), Call (the lobby's call), CountUp (5 to 6), Clear (it goes), each played again every LOOP seconds
-- from MOMENT_AT. The look the game draws is Notice.GAME_LOOK.
--
-- A generic story (render + subscribe), as UI Labs reads its controls as UILabs.Choose / Boolean objects; the gallery
-- is rebuilt on every change and scaled down to fit the widget.
--
-- Offline with rur, where the group-owned images 403, Offline swaps them for the local PNGs they were made from:
--   rur-native render --headless --offline --rojo <lobby.project.json without its comments> \
--     --story src/Lobby/Client/Stories/Notice.story.luau --viewport 1000x800 --scale 1 --background 40,40,60 \
--     --time 2 --controls '{"Moment": "Rest", "Offline": true}' --dir <out>
-- and `rur-native sequence` the same way for the motion.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local UILabs = require(ReplicatedStorage.Packages.UILabs)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Icons = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Icons)
local Notice = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Notice)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

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
}
local MOMENTS = { "Rest", "Arrive", "Call", "CountUp", "Clear" }
local MOMENT_AT = 1
local LOOP = 2.6
local BACKGROUND = Color3.fromRGB(40, 40, 60)
local ROW = 190
local LABEL = 150
local SIZE = Vector2.new(1000, 40 + ROW * #Notice.LOOKS)
-- The lobby's numbers (LobbyController/Hud, Topbar): the slab at his size drawn at 0.78, the card, their chips' middles
-- and sides, and the top bar's panel and its chip.
local SLAB = Vector2.new(366, 101)
local SLAB_SCALE = 0.78
local SLAB_GOLD = Color3.fromRGB(217, 160, 56)
local CARD = 119
local INDEX_RED = Color3.fromRGB(230, 60, 72)
local CARD_NOTICE = Vector2.new(0, 0)
local SLAB_NOTICE = Vector2.new(0, 0)
local TOPBAR = Vector2.new(108, 34)

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

local function word(text: string, size: number, props: { [any]: any }): TextLabel
	return create("TextLabel")({
		BackgroundTransparency = 1,
		FontFace = Theme.Font.Display,
		TextSize = size,
		TextColor3 = Palette.White,
		Text = text,
		props,
	})
end

-- The WEAPONS slab, his size inside, drawn at the lobby's scale, its middle at `at`.
local function slab(at: Vector2, chip: Frame): Frame
	return create("Frame")({
		Name = "Weapons",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(at.X, at.Y),
		Size = UDim2.fromOffset(SLAB.X, SLAB.Y),
		BackgroundTransparency = 1,
		create("UIScale")({ Scale = SLAB_SCALE }),
		Components.FlatSlab({ Face = SLAB_GOLD, Brackets = true, GlowTransparency = 0.55 }, {
			Size = UDim2.fromScale(1, 1),
			Components.Picture(EIcons.Rifle, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(84, 50),
				Size = Components.PictureBox(55),
				ZIndex = 4,
			}),
			Components.Tracked("WEAPONS", 34, 3, Theme.Font.Display, {
				Position = UDim2.fromOffset(119, 34),
			}),
			chip,
		}),
	})
end

-- A rail card with its picture and key, its middle at `at`.
local function card(at: Vector2, picture: string, accent: Color3, chip: Frame): Frame
	local edge = Color3.new(accent.R * 0.85, accent.G * 0.85, accent.B * 0.85)
	return Components.Card({
		Accent = edge,
		Glow = accent,
		GlowTransparency = 0.7,
		Tint = 0.5,
		Marks = true,
		Brackets = true,
		BracketLength = 22,
		BracketTransparency = 0.6,
	}, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(at.X, at.Y),
		Size = UDim2.fromOffset(CARD, CARD),
		Components.Picture(picture, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(60, 58),
			Size = Components.PictureBox(64),
			ZIndex = 4,
		}),
		chip,
	})
end

-- The top bar's Daily button: his panel with the gift and the caption, its middle at `at`.
local function topbar(at: Vector2, chip: Frame): Frame
	return Components.Panel({}, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(at.X, at.Y),
		Size = UDim2.fromOffset(TOPBAR.X, TOPBAR.Y),
		Components.Picture(EIcons.GiftBox, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 9, 0.5, 0),
			Size = UDim2.fromOffset(22, 22),
			ZIndex = 4,
		}),
		word("Daily", 15, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 37, 0.5, 0),
			Size = UDim2.fromOffset(40, 15),
			TextXAlignment = Enum.TextXAlignment.Left,
			FontFace = Theme.Font.Medium,
			ZIndex = 4,
		}),
		chip,
	})
end

local function gallery(target: Frame, moment: string, isOffline: boolean): Frame
	local start = os.clock()
	local now = source(start)
	local isShown = source(moment ~= "Arrive")
	local count = source(if moment == "CountUp" then 5 else 6)
	local callAt = source(-math.huge)
	local ticker = RunService.Heartbeat:Connect(function()
		local clock = os.clock()
		now(clock)
		local loopAt = start + LOOP * math.floor((clock - start) / LOOP)
		local isAfter = clock - loopAt >= MOMENT_AT
		if moment == "Arrive" then
			if isShown() ~= isAfter then isShown(isAfter) end
		elseif moment == "Clear" then
			if isShown() == isAfter then isShown(not isAfter) end
		elseif moment == "CountUp" then
			local due = if isAfter then 6 else 5
			if count() ~= due then count(due) end
		elseif moment == "Call" then
			local due = loopAt + MOMENT_AT
			if callAt() ~= due then callAt(due) end
		end
	end)
	vide.cleanup(function()
		ticker:Disconnect()
	end)

	local function counted(): number
		return if isShown() then count() else 0
	end
	local function chip(look: string, kind: "Upgrade" | "New", size: number, at: Vector2, isCounted: boolean): Frame
		return Notice.Build({
			Kind = kind,
			Size = size,
			IsShown = isShown,
			Count = if isCounted then counted else nil,
			Now = now,
			CallAt = callAt,
			Look = look :: any,
		}, { Position = UDim2.fromOffset(at.X, at.Y) })
	end

	local rows = table.create(#Notice.LOOKS)
	for index, look in Notice.LOOKS do
		local y = 40 + ROW * (index - 1) + ROW / 2
		rows[index] = create("Frame")({
			Name = look,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			word(if look == Notice.GAME_LOOK then `{look} (game)` else look, 20, {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromOffset(20, y),
				Size = UDim2.fromOffset(LABEL - 20, 20),
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			slab(Vector2.new(LABEL + 160, y), chip(look, "Upgrade", 48, SLAB_NOTICE, false)),
			card(Vector2.new(LABEL + 400, y), EIcons.MonsterBook, INDEX_RED, chip(look, "New", 40, CARD_NOTICE, true)),
			card(Vector2.new(LABEL + 560, y), EIcons.Scroll, Palette.Steel, chip(look, "New", 40, CARD_NOTICE, false)),
			topbar(Vector2.new(LABEL + 740, y), chip(look, "New", 26, Vector2.zero, true)),
		})
	end

	local fit = source(1)
	local function refit()
		local room = target.AbsoluteSize
		if room.X <= 0 or room.Y <= 0 then return end
		fit(math.min(room.X / SIZE.X, room.Y / SIZE.Y, 1))
	end
	local resized = target:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
	vide.cleanup(function()
		resized:Disconnect()
	end)
	refit()

	local root = create("Frame")({
		Name = "Gallery",
		Size = UDim2.fromOffset(SIZE.X, SIZE.Y),
		BackgroundColor3 = BACKGROUND,
		BorderSizePixel = 0,
		create("UIScale")({ Scale = fit }),
		word(`Moment: {moment}`, 16, {
			Position = UDim2.fromOffset(20, 12),
			Size = UDim2.fromOffset(300, 16),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Palette.Lavender,
		}),
		rows,
	})
	if isOffline then swapImages(root) end

	return root
end

local CONTROLS = {
	Moment = UILabs.Ordered(UILabs.Choose(MOMENTS, 1), 1),
	Offline = UILabs.Ordered(UILabs.Boolean(false), 2),
}

return {
	summary = "The chip a button wears while something waits behind it: every Notice look side by side.",
	controls = CONTROLS,

	render = function(props)
		local values: { [string]: any } = table.clone(props.controls)
		local unmount: (() -> ())? = nil

		local frame = Instance.new("Frame")
		frame.Name = "NoticeBench"
		frame.BackgroundColor3 = BACKGROUND
		frame.ClipsDescendants = true
		frame.Size = UDim2.fromScale(1, 1)
		frame.Parent = props.target

		local function build()
			if unmount then unmount() end
			-- The mount frees the state, not the instances.
			frame:ClearAllChildren()
			unmount = vide.mount(function()
				return gallery(frame, values.Moment, values.Offline)
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
