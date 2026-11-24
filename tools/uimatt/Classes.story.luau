-- The lobby's classes screen with a fixed state, for rur to render beside the designer's Classes render
-- (Assets/ui/UIMatt/renders/05_Classes.png, the same renderer and background):
--   rur-native render --headless --offline --rojo <lobby.project.json without its comments> \
--     --story tools/uimatt/Classes.story.luau --viewport 1920x1080 --scale 1 --background 40,40,60 --time 1.5 \
--     --controls '{"Moment": "Rest"}' --dir <out>
-- Moment: Rest (open and settled on the first ability), Open (the screen opening 0.2 s in), Pick (the ultimate
-- picked 0.2 s in), Close (shutting 0.2 s in), Upgraded (a level paid 0.2 s in: its Gems fly from a stand-in for the
-- HUD's Gems glyph, and the level is shown as they land), Refused (a press refused 0.2 s in), for `rur-native
-- sequence`. Level is every ability's, Gems what the player holds. The avatar is a plain blocky stand-in with
-- no Humanoid: ror's viewport worker draws nothing for a model that holds one. rur reads the project file as plain
-- JSON, so strip its comments into a copy first. The group-owned images 403 offline, so they are swapped for the local
-- PNGs they were made from.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

-- The ECS world's debugger (jabby) waits on a client for the remotes its server makes, and offline there is no server.
-- The page reaches it (AbilityPicture, copyCharacter, BodyPoseController, the World), so they are made before it loads.
-- The names are jabby 0.2.3's (its modules/remotes.luau).
if not ReplicatedStorage:FindFirstChild("JABBY_REMOTES") then
	local folder = Instance.new("Folder")
	folder.Name = "JABBY_REMOTES"
	for _, name in
		{
			"server_registered",
			"ping",
			"client_registered",
			"update_server_data",
			"send_mouse_pointer",
			"send_mouse_entity",
			"validate_query",
			"validate_result",
			"replicate_query",
			"disconnect_query",
			"advance_query_page",
			"pause_query",
			"refresh_query",
			"update_query_result",
			"count_total_entities",
			"initiate_replicate_scheduler",
			"disconnect_replicate_scheduler",
			"scheduler_system_update_static",
			"append_frame_system",
			"scheduler_pause",
			"validate_entity_component",
			"validate_entity_component_result",
			"inspect_entity",
			"delete_entity",
			"stop_inspect_entity",
			"update_entity",
			"inspect_entity_settings_update",
			"inspect_entity_update",
			"create_watch",
			"remove_watch",
			"request_watch_data",
			"update_watch_data",
			"start_record_watch",
			"stop_watch",
			"clear_watch",
			"connect_to_watch",
			"disconnect_watch",
			"update_watch_overview",
		}
	do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		local actor = Instance.new("BindableEvent")
		actor.Name = "actor"
		actor.Parent = remote
		local peer = Instance.new("RemoteEvent")
		peer.Name = "peer"
		peer.Parent = remote
		remote.Parent = folder
	end
	folder.Parent = ReplicatedStorage
end

local vide = require(ReplicatedStorage.Packages.vide)
local Icons = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Icons)
local Showcase = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Showcase)
local EClassesIds = require(ReplicatedStorage.Types.Enums.Data.EClassesIds)
local Classes = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.LobbyController.Classes)

local source = vide.source
local create = vide.create

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
local MOMENT_AT = 0.2

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

-- A blocky R6 body in plain colours, its root at the origin.
local function dummy(): Model
	local model = Instance.new("Model")
	model.Name = "Avatar"
	local parts = {
		{ "HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.new(0, 0, 0), Color3.fromRGB(255, 255, 255), 1 },
		{ "Torso", Vector3.new(2, 2, 1), Vector3.new(0, 0, 0), Color3.fromRGB(52, 142, 64), 0 },
		{ "Head", Vector3.new(2, 1, 1), Vector3.new(0, 1.5, 0), Color3.fromRGB(245, 205, 48), 0 },
		{ "Left Arm", Vector3.new(1, 2, 1), Vector3.new(-1.5, 0, 0), Color3.fromRGB(245, 205, 48), 0 },
		{ "Right Arm", Vector3.new(1, 2, 1), Vector3.new(1.5, 0, 0), Color3.fromRGB(245, 205, 48), 0 },
		{ "Left Leg", Vector3.new(1, 2, 1), Vector3.new(-0.5, -2, 0), Color3.fromRGB(13, 105, 172), 0 },
		{ "Right Leg", Vector3.new(1, 2, 1), Vector3.new(0.5, -2, 0), Color3.fromRGB(13, 105, 172), 0 },
	}
	for _, spec in parts do
		local part = Instance.new("Part")
		part.Name = spec[1]
		part.Size = spec[2]
		part.CFrame = CFrame.new(spec[3])
		part.Color = spec[4]
		part.Transparency = spec[5]
		part.Anchored = true
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = model
		if spec[1] == "HumanoidRootPart" then model.PrimaryPart = part end
	end
	return model
end

local function noop() end

return {
	vide = vide,
	controls = {
		Moment = { "Rest", "Open", "Pick", "Close", "Upgraded", "Refused" },
		-- The shown ability's level, and the Gems held.
		Level = 2,
		Gems = 1000,
		-- The art behind the avatar (Showcase.LOOKS); Game is the look the game draws.
		Look = { "Game", table.unpack(Showcase.LOOKS) },
	},
	story = function(props)
		local moment = props.controls.Moment()
		local look = props.controls.Look()
		Showcase.Looks.Classes = if look == "Game" then Showcase.GAME_LOOKS.Classes else look
		local level = props.controls.Level()
		local at = os.clock() + MOMENT_AT
		local levels = { level, level, level }
		local landsAt = at + Classes.FLIGHT_SECONDS
		-- Where the HUD's Gems glyph stands while this page is up (docked at the right, on the top row).
		local gemsGlyph = create("Frame")({
			Name = "GemsGlyph",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(1627, 44),
			Size = UDim2.fromOffset(40, 40),
			BackgroundTransparency = 1,
		})

		local state = {
			Scale = source(1),
			PageScale = source(1),
			Now = source(os.clock()),
			IsClassesOpen = source(moment ~= "Close"),
			ClassesToggledAt = source(if moment == "Open" or moment == "Close" then at else -math.huge),
			ClassesPage = source("Classes"),
			ClassesPageAt = source(-math.huge),
			ShownAbility = source(if moment == "Pick" then 3 else 1),
			AbilityPickedAt = source(if moment == "Pick" then at else -math.huge),
			ClassLevels = source({ [EClassesIds.Human] = levels }),
			Gems = source(props.controls.Gems()),
			IsUpgrading = source(moment == "Upgraded"),
			UpgradePaidAt = source(if moment == "Upgraded" then at else -math.huge),
			UpgradedAt = source(if moment == "Upgraded" then landsAt else -math.huge),
			UpgradeRefusedAt = source(if moment == "Refused" then at else -math.huge),
			GemsGlyph = source(gemsGlyph),
			Avatar = source(dummy()),
			Doll = source(dummy()),
		}

		local isLanded = moment ~= "Upgraded"
		RunService.Heartbeat:Connect(function()
			local now = os.clock()
			state.Now(now)
			if isLanded or now < landsAt then return end
			isLanded = true
			state.ClassLevels({ [EClassesIds.Human] = { level + 1, level + 1, level + 1 } })
			state.IsUpgrading(false)
		end)

		local gui = Classes.Build(state, {
			CloseClasses = noop,
			PickAbility = noop,
			UpgradeAbility = noop,
			PickClassesPage = noop,
		})
		local root = create("Frame")({
			Name = "Root",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
		})
		for _, child in gui:GetChildren() do
			child.Parent = root
		end
		gemsGlyph.Parent = root
		swapImages(root)
		return root
	end,
}
