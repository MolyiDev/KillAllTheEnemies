-- The card a boss drop is shown on in a match (EquipmentDropController.Card), for rur to render at moments of its
-- reveal:
--   rur-native render --headless --rojo <game.project.json without its comments> \
--     --story tools/uimatt/EquipmentDrop.story.luau --viewport 1920x1080 --scale 1 --background 40,40,60 --time 1.5 \
--     --controls '{"Piece": "KnightShoulders"}' --dir <out>
-- The drop goes up 0.2 s in. rur reads the project file as plain JSON, so strip its comments into a copy first. The
-- group-owned images 403 offline, so they are swapped for the local PNGs they were made from, and the Hip Pack's mesh
-- (not public) is read from its downloaded source.
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
local EEquipmentIds = require(ReplicatedStorage.Types.Enums.Data.EEquipmentIds)
local Card = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.EquipmentDropController.Card)

local source = vide.source
local create = vide.create

local ROOT = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/hud/"
local SWAPS = {
	[Icons.IMAGE] = ROOT .. "Icons.png",
	[Icons.PANEL_TEXTURE] = ROOT .. "PanelTexture.png",
	[Icons.SHOWCASE] = ROOT .. "Showcase.png",
	[Icons.SHOWCASE_FLOOR] = ROOT .. "ShowcaseFloor.png",
}
local PRIVATE_MESHES = {
	["rbxassetid://13656925925"] = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/models/Equipment/sources/13656925925.mesh",
	["rbxassetid://13656942660"] = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/models/Equipment/sources/13656942660.png",
}
local MOMENT_AT = 0.2

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

return {
	vide = vide,
	controls = {
		Piece = { "KnightShoulders", "HipPack", "KnightHelmet" },
	},
	story = function(props)
		local now = source(os.clock())
		RunService.Heartbeat:Connect(function()
			now(os.clock())
		end)
		local gui = Card.Build({
			Scale = source(1),
			Now = now,
			Item = source(EEquipmentIds[props.controls.Piece()]),
			At = source(os.clock() + MOMENT_AT),
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
