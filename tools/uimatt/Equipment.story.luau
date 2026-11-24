-- The lobby's classes screen on its EQUIPMENT tab with a fixed state, for rur to render beside the designer's
-- Equipment render (Assets/ui/UIMatt/renders/06_Equipment.png, the same renderer and background):
--   rur-native render --headless --offline --rojo <lobby.project.json without its comments> \
--     --story tools/uimatt/Equipment.story.luau --viewport 1920x1080 --scale 1 --background 40,40,60 --time 1.5 \
--     --controls '{"Moment": "Rest"}' --dir <out>
-- Moment: Rest (the page up and settled on the helmet, worn), Tab (EQUIPMENT picked 0.2 s in: the page fading in over
-- the classes page), Pick (the shoulders picked 0.2 s in), Equip (the shoulders put on 0.2 s in), Locked (the hip pack
-- picked and its slab pressed 0.2 s in: refused, where it comes from opened), Filter (TORSO picked 0.2 s in), Close
-- (the screen shutting 0.2 s in), for `rur-native sequence`. Owned is what the player has got. The avatar is the
-- classes story's blocky stand-in, with an R6 body's attachments for the pieces. rur reads the project file as plain
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
local EEquipmentIds = require(ReplicatedStorage.Types.Enums.Data.EEquipmentIds)
local Classes = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.LobbyController.Classes)
local EquipmentParts = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.EquipmentController.Parts)
local EquipmentScreen = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.EquipmentController.Screen)

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
-- The meshes offline asset delivery refuses (401: the Hip Pack's is not public), read from their downloaded sources.
local PRIVATE_MESHES = {
	["rbxassetid://13656925925"] = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/models/Equipment/sources/13656925925.mesh",
	["rbxassetid://13656942660"] = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/models/Equipment/sources/13656942660.png",
}

for _, mesh in ReplicatedStorage.Models.Equipment:GetDescendants() do
	if not mesh:IsA("SpecialMesh") then continue end
	mesh.MeshId = PRIVATE_MESHES[mesh.MeshId] or mesh.MeshId
	mesh.TextureId = PRIVATE_MESHES[mesh.TextureId] or mesh.TextureId
end

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

-- A blocky R6 body in plain colours, its root at the origin, with the attachments an R6 body carries for accessories.
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
	local attachments = {
		Head = { HatAttachment = Vector3.new(0, 0.6, 0) },
		Torso = { WaistCenterAttachment = Vector3.new(0, -1, 0) },
		["Left Arm"] = { LeftShoulderAttachment = Vector3.new(0, 1, 0) },
		["Right Arm"] = { RightShoulderAttachment = Vector3.new(0, 1, 0) },
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
		for name, at in attachments[spec[1]] or {} do
			local attachment = Instance.new("Attachment")
			attachment.Name = name
			attachment.Position = at
			attachment.Parent = part
		end
		if spec[1] == "HumanoidRootPart" then model.PrimaryPart = part end
	end
	return model
end

local function noop() end

return {
	vide = vide,
	controls = {
		Moment = { "Rest", "Tab", "Pick", "Equip", "Locked", "Filter", "Close" },
		-- What the player has got besides the helmet everybody has.
		Owned = { "Shoulders", "None", "All" },
		-- The art behind the avatar (Showcase.LOOKS); Game is the look the game draws.
		Look = { "Game", table.unpack(Showcase.LOOKS) },
	},
	story = function(props)
		local moment = props.controls.Moment()
		local look = props.controls.Look()
		Showcase.Looks.Equipment = if look == "Game" then Showcase.GAME_LOOKS.Equipment else look
		local ownedPick = props.controls.Owned()
		local at = os.clock() + MOMENT_AT
		local helmet, shoulders, hipPack =
			EEquipmentIds.KnightHelmet, EEquipmentIds.KnightShoulders, EEquipmentIds.HipPack
		local owned = { [helmet] = true }
		if ownedPick ~= "None" then owned[shoulders] = true end
		if ownedPick == "All" then owned[hipPack] = true end

		local selected = if moment == "Pick"
				or moment == "Equip"
				or moment == "Filter"
			then shoulders
			elseif moment == "Locked" then hipPack
			else helmet
		local lobby = {
			Scale = source(1),
			PageScale = source(1),
			Now = source(os.clock()),
			IsClassesOpen = source(moment ~= "Close"),
			ClassesToggledAt = source(if moment == "Close" then at else -math.huge),
			ClassesPage = source("Equipment"),
			ClassesPageAt = source(if moment == "Tab" then at else -math.huge),
			ShownAbility = source(1),
			AbilityPickedAt = source(-math.huge),
			ClassLevels = source({ [EClassesIds.Human] = { 1, 1, 1 } }),
			Gems = source(0),
			IsUpgrading = source(false),
			UpgradePaidAt = source(-math.huge),
			UpgradedAt = source(-math.huge),
			UpgradeRefusedAt = source(-math.huge),
			GemsGlyph = source(nil),
			Avatar = source(dummy()),
			Doll = source(dummy()),
		}
		local state = {
			Now = source(os.clock()),
			IsShown = source(moment ~= "Close"),
			ShownAt = source(if moment == "Tab" or moment == "Close" then at else -math.huge),
			IsByScreen = source(moment == "Close"),
			Filter = source(if moment == "Filter" then "Torso" else "All"),
			FilterAt = source(if moment == "Filter" then at else -math.huge),
			Selected = source(selected),
			SelectedAt = source(
				if moment == "Pick" or moment == "Locked" or moment == "Filter" then at else -math.huge
			),
			Owned = source(owned),
			Equipped = source({ Head = helmet } :: { [string]: number }),
			Hidden = source({}),
			Pending = source(nil),
			ChangedItem = source(0),
			Change = source("Equip"),
			ChangedAt = source(-math.huge),
			RefusedAt = source(if moment == "Locked" then at else -math.huge),
			IsHelpOpen = source(false),
			HelpAt = source(-math.huge),
			Avatar = source(dummy()),
		}
		local actions = {
			Filter = noop,
			Select = noop,
			Press = noop,
			ToggleShown = noop,
			ToggleHelp = noop,
			Stir = noop,
		}

		local isDone = false
		RunService.Heartbeat:Connect(function()
			local now = os.clock()
			lobby.Now(now)
			state.Now(now)
			if isDone or now < at then return end
			isDone = true
			if moment == "Equip" then
				vide.batch(function()
					state.Equipped({ Head = helmet, Torso = shoulders })
					state.ChangedItem(shoulders)
					state.Change("Equip")
					state.ChangedAt(now)
				end)
			elseif moment == "Locked" then
				state.IsHelpOpen(true)
				state.HelpAt(now)
			end
		end)

		local gui = Classes.Build(lobby, {
			CloseClasses = noop,
			PickAbility = noop,
			UpgradeAbility = noop,
			PickClassesPage = noop,
		}, {
			Pieces = EquipmentScreen.Build(state, actions),
			FadeSeconds = EquipmentParts.Timing.FADE,
		})
		local root = create("Frame")({
			Name = "Root",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
		})
		for _, child in gui:GetChildren() do
			child.Parent = root
		end
		swapImages(root)
		return root
	end,
}
