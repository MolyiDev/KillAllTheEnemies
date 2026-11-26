-- The arena HUD with a fixed state, for rur to render beside the designer's In-Game HUD render
-- (Assets/ui/UIMatt/renders/15_In_Game_HUD.png, the same renderer and background):
--   rur-native render --headless --offline --rojo <game.project.json without its comments> \
--     --story tools/uimatt/Hud.story.luau --viewport 1920x1080 --scale 1 --background 40,40,60 --time 1.5 \
--     --controls '{"Phase": "Fighting"}' --dir <out>
-- The weapon card's moments (Moment: Ready, Denied, Buy, Maxed), the gun slot's (Arrive, Swap) and the squad's
-- announcements (Nuke, Heal), a bought Gold pack (GoldPack, GoldPackBig) and the squad screen's (Squad opens it,
-- SquadKill opens it and scores on the second row a second later, SquadClose shuts it) start 0.2 s in, for
-- `rur-native sequence`. The squad's four are his render's numbers; their faces cannot be fetched offline. The boss's
-- bar: Boss (up mid-fight, still), BossArrive, BossFight (a stream of hits that empties a segment, then a big one),
-- BossShare (the damage share from nobody: a squadmate comes onto it, then the local player, who streams hits past
-- them, then lands a big one, 0.2 s in),
-- BossFall (the Knight Shoulders won half a second after it, the Hip Pack missed), BossOwned (still, the shoulders
-- owned already), BossShield (its guards' shield up, one of four down), Way (kills streaming onto the way to the next boss,
-- completing its second segment), WayFull (the last kills fill it, it charges, and the boss comes on); the player's:
-- Hurt, Heal. They run through BossBar.Update and BarJuice.Step as the HUD does, off a scripted
-- server.
-- rur reads the project file as plain JSON, so strip its comments into a copy first. The HUD's group-owned images 403
-- offline, so they are swapped for the local PNGs they were made from, and the Hip Pack's mesh (not public) is read from
-- its downloaded source.
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
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local GunsCore = require(ReplicatedStorage.GlobalShared.Core.GunsCore)
local RoundCore = require(ReplicatedStorage.Shared.Core.RoundCore)
local EquipmentCore = require(ReplicatedStorage.GlobalShared.Core.EquipmentCore)
local EEnemiesIds = require(ReplicatedStorage.Types.Enums.Data.EEnemiesIds)
local EEquipmentIds = require(ReplicatedStorage.Types.Enums.Data.EEquipmentIds)
local Icons = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Icons)
local AvatarPose = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.AvatarPose)

local hud = StarterPlayer.StarterPlayerScripts.Client.Controllers.HudController
local Wave = require(hud.Wave)
local Items = require(hud.Items)
local Announce = require(hud.Announce)
local Upgrades = require(hud.Upgrades)
local WeaponUpgrade = require(hud.WeaponUpgrade)
local HealthUpgrade = require(hud.HealthUpgrade)
local Shop = require(hud.Shop)
local Hotbar = require(hud.Hotbar)
local HealthBar = require(hud.HealthBar)
local Squad = require(hud.Squad)
local BarJuice = require(hud.BarJuice)
local BossBar = require(hud.BossBar)

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

local PRIVATE_MESHES = {
	["rbxassetid://13656925925"] = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/models/Equipment/sources/13656925925.mesh",
	["rbxassetid://13656942660"] = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/models/Equipment/sources/13656942660.png",
}
for _, mesh in ReplicatedStorage.Models.Equipment:GetDescendants() do
	if not mesh:IsA("SpecialMesh") then continue end
	mesh.MeshId = PRIVATE_MESHES[mesh.MeshId] or mesh.MeshId
	mesh.TextureId = PRIVATE_MESHES[mesh.TextureId] or mesh.TextureId
end

local LADDER = GunsCore.STARTER_LADDER
local MOMENT_AT = 0.2

-- The gun models' meshes cannot be fetched offline, so the starter guns are swapped for silhouettes of plain parts
-- (barrel, body, grip, stock), each a different length so the swap reads. SmoothPlastic, since the viewport worker
-- cannot find the Plastic atlas offline and draws nothing.
local function standIns()
	local guns = ReplicatedStorage.Models.Guns
	local function block(model: Model, size: Vector3, position: Vector3, color: Color3)
		local part = Instance.new("Part")
		part.Size = size
		part.Position = position
		part.Color = color
		part.Material = Enum.Material.SmoothPlastic
		part.Anchored = true
		part.Parent = model
	end

	local starters = guns.Common
	for name, barrel in { ["1"] = 0.9, ["2"] = 2.4, ["4"] = 1.6, TerminatorGun = 1.4 } do
		local old = starters:FindFirstChild(name)
		if old then old:Destroy() end
		local model = Instance.new("Model")
		model.Name = name
		block(model, Vector3.new(1.6, 0.6, 0.35), Vector3.new(0, 0, 0), Color3.fromRGB(92, 100, 118))
		block(
			model,
			Vector3.new(barrel, 0.22, 0.2),
			Vector3.new(0.8 + barrel / 2, 0.12, 0),
			Color3.fromRGB(176, 184, 198)
		)
		block(model, Vector3.new(0.35, 0.8, 0.3), Vector3.new(-0.35, -0.6, 0), Color3.fromRGB(150, 98, 58))
		if name ~= "1" then
			block(model, Vector3.new(1.2, 0.45, 0.3), Vector3.new(-1.4, -0.15, 0), Color3.fromRGB(150, 98, 58))
		end
		model.Parent = starters
	end
end

-- A Tool like buildGunTool's, holding gun `gunId`'s model with its Handle on the gun's axes, for the hotbar's picture.
local function heldModel(gunId: number): Model?
	local gun = DataCore.Guns.ById[gunId]
	local template = if gun then GunsCore.GetModel(gun) else nil
	if not gun or not template then return nil end
	local model = template:Clone()
	local axes = GunsCore.FindAxes(model, gun)
	local tool = Instance.new("Tool")
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.CFrame = CFrame.fromMatrix(axes.Position, axes.XVector:Cross(axes.YVector), axes.YVector, -axes.XVector)
	handle.Parent = tool
	model.Name = "Model"
	model.Parent = tool
	return model
end

-- A stand-in for the player's avatar on the Decoy's card: an R15 body's upper limbs as blocks, each with its rig
-- attachment, facing down -Z as a character does, with a visor worn on the head so its front shows, posed as the HUD
-- poses the real one.
local function avatar(): Model
	local model = Instance.new("Model")
	local function limb(
		name: string,
		size: Vector3,
		at: Vector3,
		color: Color3,
		joint: string?,
		jointAt: Vector3?
	): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.Position = at
		part.Color = color
		part.Material = Enum.Material.SmoothPlastic
		part.Anchored = true
		part.Parent = model
		if joint and jointAt then
			local attachment = Instance.new("Attachment")
			attachment.Name = joint
			attachment.Position = jointAt
			attachment.Parent = part
		end
		return part
	end

	local skin, shirt, trousers =
		Color3.fromRGB(255, 214, 120), Color3.fromRGB(60, 200, 110), Color3.fromRGB(60, 110, 255)
	limb("HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.new(0, 3, 0), shirt).Transparency = 1
	limb("UpperTorso", Vector3.new(2, 2, 1), Vector3.new(0, 3, 0), shirt)
	limb(
		"RightUpperArm",
		Vector3.new(1, 2, 1),
		Vector3.new(1.5, 3, 0),
		skin,
		"RightShoulderRigAttachment",
		Vector3.new(-0.5, 0.75, 0)
	)
	limb(
		"LeftUpperArm",
		Vector3.new(1, 2, 1),
		Vector3.new(-1.5, 3, 0),
		skin,
		"LeftShoulderRigAttachment",
		Vector3.new(0.5, 0.75, 0)
	)
	limb(
		"RightUpperLeg",
		Vector3.new(1, 2, 1),
		Vector3.new(0.5, 1, 0),
		trousers,
		"RightHipRigAttachment",
		Vector3.new(0, 1, 0)
	)
	limb(
		"LeftUpperLeg",
		Vector3.new(1, 2, 1),
		Vector3.new(-0.5, 1, 0),
		trousers,
		"LeftHipRigAttachment",
		Vector3.new(0, 1, 0)
	)
	local head = limb(
		"Head",
		Vector3.new(1.2, 1.2, 1.2),
		Vector3.new(0, 4.6, 0),
		skin,
		"NeckRigAttachment",
		Vector3.new(0, -0.6, 0)
	)

	local visor = Instance.new("Accessory")
	local handle = limb("Handle", Vector3.new(0.9, 0.3, 0.2), Vector3.new(0, 4.75, -0.6), Color3.fromRGB(30, 30, 50))
	local weld = Instance.new("Weld")
	weld.Part0 = handle
	weld.Part1 = head
	weld.Parent = handle
	handle.Parent = visor
	visor.Parent = model

	AvatarPose.Apply(model, AvatarPose.DOLL)
	return model
end

-- His render's four rows, the first the local player's.
local function squad()
	local members = {}
	for index, row in { { 42, 3, 1250 }, { 35, 5, 980 }, { 61, 2, 2400 }, { 18, 7, 420 } } do
		members[index] = {
			Name = "Username",
			UserId = 0,
			IsSelf = index == 1,
			ClassName = source("Human"),
			Kills = source(row[1]),
			Deaths = source(row[2]),
			Cash = source(row[3]),
			KilledAt = source(-math.huge),
			DiedAt = source(-math.huge),
		}
	end

	return members
end

local function state(phase: string, moment: string)
	local defenses = {}
	local keys = { Enum.KeyCode.E, Enum.KeyCode.R }
	for index, data in DataCore.Defenses.All do
		defenses[index] = {
			Key = keys[index],
			Name = data.Name,
			Cost = data.Cost,
			Limit = data.MaxPerPlayer,
			DataId = data.Id,
			Count = source(0),
			IsPlacing = source(false),
			PlacedAt = source(-math.huge),
			DeniedAt = source(-math.huge),
		}
	end

	return {
		Scale = source(1),
		Now = source(os.clock()),
		Phase = source(phase),
		PhaseAt = source(-math.huge),
		PreviousPhase = source(if phase == "Preparing" then "Fighting" else "Preparing"),
		Round = source(2),
		Countdown = source(3),
		CountdownAt = source(-math.huge),
		IsBossRound = source(false),
		Votes = source(0),
		VotesNeeded = source(1),
		CanSkip = source(phase == "Fighting"),
		SkipProgress = source(if phase == "Fighting" then 1 else 0.3),
		SkipOpenedAt = source(-math.huge),
		VotesAt = source(-math.huge),
		IsAutoSkip = source(false),
		Boss = {
			Name = source(""),
			Bar = BarJuice.NewTrack(),
			Breaks = BarJuice.NewTrack(),
			Shares = {
				{
					Name = source(""),
					IsSelf = source(false),
					Share = source(0),
					Lead = source(0),
					Glow = source(0),
					EnteredAt = source(-math.huge),
				},
				{
					Name = source(""),
					IsSelf = source(false),
					Share = source(0),
					Lead = source(0),
					Glow = source(0),
					EnteredAt = source(-math.huge),
				},
			},
			SwappedAt = source(-math.huge),
			AppearedAt = source(-math.huge),
			Broken = source(0),
			BrokeAt = source(-math.huge),
			DefeatedAt = source(-math.huge),
			Guards = source(0),
			GuardsTotal = source(0),
			Way = BarJuice.NewTrack(),
			Filled = source(0),
			FilledAt = source(-math.huge),
			FullAt = source(-math.huge),
			Surge = source(0),
			Drops = source({}),
			DropWonAt = { source(-math.huge), source(-math.huge), source(-math.huge), source(-math.huge) },
		},
		NextBossName = source("The Cove King"),
		NextBossRound = source(15),
		Gold = source(60),
		GoldShown = source(60),
		GoldPulse = source(0),
		GoldDenied = source(0),
		GoldDeniedAt = source(-math.huge),
		GoldDenied = source(0),
		Health = source(82),
		MaxHealth = source(100),
		BarHealth = source(82),
		BarMax = source(100),
		HealthTrack = BarJuice.NewTrack(),
		IsDown = source(false),
		Head = source(nil),
		IsFirstPerson = source(false),
		Vignette = source(0),
		VignetteColor = source(Color3.new()),
		Defenses = defenses,
		Squad = source(squad()),
		IsSquadOpen = source(false),
		SquadToggledAt = source(-math.huge),
		RunSeconds = source(0),
		EnemyCount = source(0),
		IsNukePrompted = source(false),
		IsHealPrompted = source(false),
		Announce = {
			Kind = source(""),
			Name = source(""),
			Count = source(0),
			At = source(-math.huge),
		},
		GoldPack = {
			Amount = source(0),
			At = source(-math.huge),
		},
		Gun = source(nil),
		GunModel = source(heldModel(LADDER[1].Gun)),
		GunAt = source(-math.huge),
		IsReviveOffered = source(false),
		CanRevive = false,
		Weapon = {
			Offer = source(LADDER[2]),
			Held = source(LADDER[1]),
			Step = source(1),
			CanAfford = source(false),
			Clock = source(math.huge),
			BoughtAt = source(-math.huge),
			LandAt = source(-math.huge),
			AskedAt = source(-math.huge),
			DeniedAt = source(-math.huge),
			ReadyAt = source(-math.huge),
		},
		Vital = {
			Level = source(0),
			Price = source(40),
			Paid = source(0),
			CanAfford = source(true),
			Clock = source(math.huge),
			BoughtAt = source(-math.huge),
			LandAt = source(-math.huge),
			AskedAt = source(-math.huge),
			DeniedAt = source(-math.huge),
			ReadyAt = source(-math.huge),
			-- The middle of the bar drawn below, where the designer drew it over his character.
			BarAt = source(UDim2.fromOffset(1241, 505)),
		},
		-- The Human class: the Decoy ready, the Foam Cannon part way through its cooldown, the ultimate at 62%.
		Abilities = {
			{
				Slot = 1,
				Name = "Decoy",
				Kind = "Decoy",
				Key = Enum.KeyCode.Q,
				Accent = Color3.fromRGB(255, 46, 139),
				Cost = 40,
				Cooling = source(0),
				Seconds = source(0),
				UsedAt = source(-math.huge),
				DeniedAt = source(-math.huge),
				ReadyAt = source(-math.huge),
			},
			{
				Slot = 2,
				Name = "Foam Cannon",
				Kind = "FoamCannon",
				Key = Enum.KeyCode.E,
				Accent = Color3.fromRGB(158, 186, 217),
				Cost = 50,
				Cooling = source(0.6),
				Seconds = source(7),
				UsedAt = source(-math.huge),
				DeniedAt = source(-math.huge),
				ReadyAt = source(-math.huge),
			},
		},
		Ultimate = {
			Slot = 3,
			Name = "Orbital Cannon",
			Kind = "OrbitalCannon",
			Key = Enum.KeyCode.G,
			Charge = source(0.62),
			IsReady = source(false),
			Burning = source(0),
			ChargedAt = source(-math.huge),
			UsedAt = source(-math.huge),
			DeniedAt = source(-math.huge),
		},
		Avatar = source(avatar()),
		Keys = { Skip = Enum.KeyCode.N, Turn = Enum.KeyCode.T, Upgrade = Enum.KeyCode.V, Health = Enum.KeyCode.C },
	}
end

local function noop() end

local ACTIONS = {
	VoteStart = noop,
	ToggleAutoSkip = noop,
	PlaceDefense = noop,
	UpgradeWeapon = noop,
	UpgradeHealth = noop,
	CastAbility = noop,
	Revive = noop,
	BuyProduct = noop,
	CloseSquad = noop,
}

return {
	vide = vide,
	controls = {
		Phase = { "Preparing", "Fighting" },
		Moment = {
			"Rest",
			"Ready",
			"Denied",
			"Buy",
			"Maxed",
			"Arrive",
			"Swap",
			"Nuke",
			"Heal",
			"HealthBuy",
			"HealthMaxed",
			"Boss",
			"BossArrive",
			"BossFight",
			"BossShare",
			"BossFall",
			"BossOwned",
			"BossShield",
			"Way",
			"WayFull",
			"Hurt",
			"Heal",
			"GoldPack",
			"GoldPackBig",
			"Squad",
			"SquadKill",
			"SquadClose",
		},
	},
	story = function(props)
		standIns()
		local moment = props.controls.Moment()
		local hudState = state(props.controls.Phase(), moment)
		local weapon = hudState.Weapon
		local startedAt = os.clock()
		local at = startedAt + MOMENT_AT
		if moment == "Ready" then
			hudState.Gold(160)
			hudState.GoldShown(160)
			weapon.CanAfford(true)
			weapon.ReadyAt(at)
		elseif moment == "Denied" then
			weapon.DeniedAt(at)
		elseif moment == "Buy" or moment == "Maxed" then
			local step = if moment == "Buy" then 2 else #LADDER
			weapon.Step(step)
			weapon.Held(LADDER[step])
			weapon.Offer(LADDER[step + 1])
			weapon.BoughtAt(at)
			weapon.LandAt(at + WeaponUpgrade.Timing.FLIGHT)
			hudState.GunModel(heldModel(LADDER[step].Gun))
		elseif moment == "HealthBuy" then
			-- 82 of 100 becomes 102 of 120: the bar holds the old numbers until the kit lands, then grows.
			local vital = hudState.Vital
			vital.Level(1)
			vital.Paid(40)
			vital.Price(80)
			vital.CanAfford(false)
			vital.BoughtAt(at)
			vital.LandAt(at + HealthUpgrade.Timing.LAND)
			hudState.Health(102)
			hudState.MaxHealth(120)
		elseif moment == "HealthMaxed" then
			hudState.Vital.Level(5)
			hudState.Vital.Price(nil)
			hudState.MaxHealth(200)
			hudState.BarMax(200)
			hudState.Health(200)
			hudState.BarHealth(200)
		elseif moment == "Arrive" then
			local model = hudState.GunModel()
			hudState.GunModel(nil)
			task.delay(MOMENT_AT, hudState.GunModel, model)
		elseif moment == "Swap" then
			hudState.GunModel(heldModel(LADDER[2].Gun))
			hudState.GunAt(at)
		elseif moment == "Nuke" or moment == "Heal" then
			hudState.Announce.Kind(moment)
			hudState.Announce.Name("Molyi")
			hudState.Announce.Count(137)
			hudState.Announce.At(at)
		elseif moment == "GoldPack" or moment == "GoldPackBig" then
			-- The counter lands on the new amount as the last coin does (CoinsController holds it back until then).
			local amount = if moment == "GoldPack" then 1000 else 99999
			hudState.GoldPack.Amount(amount)
			hudState.GoldPack.At(at)
			task.delay(MOMENT_AT + 1.5, function()
				hudState.GoldShown(hudState.GoldShown() + amount)
			end)
		elseif moment == "Squad" or moment == "SquadKill" then
			hudState.Round(2)
			hudState.RunSeconds(19)
			task.delay(MOMENT_AT, function()
				hudState.IsSquadOpen(true)
				hudState.SquadToggledAt(os.clock())
			end)
			if moment == "SquadKill" then
				task.delay(MOMENT_AT + 1.2, function()
					local member = hudState.Squad()[2]
					member.Kills(member.Kills() + 3)
					member.Cash(member.Cash() + 45)
					member.KilledAt(os.clock())
					local downed = hudState.Squad()[4]
					downed.Deaths(downed.Deaths() + 1)
					downed.DiedAt(os.clock())
				end)
			end
		elseif moment == "SquadClose" then
			hudState.RunSeconds(19)
			hudState.IsSquadOpen(true)
			task.delay(MOMENT_AT, function()
				hudState.IsSquadOpen(false)
				hudState.SquadToggledAt(os.clock())
			end)
		end

		-- The scripted server: the boss's health and the local player's part in it, by seconds since the story began, and
		-- the local player's health.
		-- In WayFull the way fills a second in, and the boss comes on as RoundService brings it.
		local wayFullAt = MOMENT_AT + 1 + RoundCore.BOSS_ARRIVE_SECONDS
		local bossAt = startedAt
			+ (if moment == "BossArrive" then MOMENT_AT elseif moment == "WayFull" then wayFullAt else -5)
		-- The way: 400 bodies, kills coming in batches ten times a second, as the server sends them.
		local function wayKills(t: number): number
			local batches = math.max(math.floor((t - MOMENT_AT) * 10), 0)
			if moment == "Way" then return math.min(185 + 2 * batches, 230) end
			if moment == "WayFull" then return math.min(380 + 2 * batches, 400) end
			return 120
		end
		local isBossMoment = string.sub(moment, 1, 4) == "Boss"
		local function bossShare(t: number): (number, number)
			if moment == "Boss" or moment == "BossShield" or moment == "BossOwned" or moment == "BossShare" then
				return 0.62, 0.18
			end
			if moment == "BossArrive" or moment == "WayFull" then return 1, 0 end
			if moment == "BossFight" then
				-- Ten blows a second from 0.79 down past the first segment's end, then a heavy one.
				local blows = math.clamp(math.floor((t - MOMENT_AT) * 10), 0, 14)
				local share = 0.79 - 0.006 * blows - (if t >= MOMENT_AT + 2 then 0.09 else 0)
				return share, (0.79 - share) * 0.9 + 0.1
			end
			-- BossFall: one blow, then the last.
			return if t >= MOMENT_AT then 0.02 else 0.06, 0.31
		end

		local function health(t: number): number
			if moment == "Hurt" then
				return 82 - (if t >= MOMENT_AT then 18 else 0) - (if t >= MOMENT_AT + 0.5 then 9 else 0)
			end
			if moment == "Heal" then return if t >= MOMENT_AT then 90 else 40 end
			return hudState.Health()
		end

		-- Its guards' shield up, one of four down.
		if moment == "BossShield" then
			hudState.Boss.Guards(3)
			hudState.Boss.GuardsTotal(4)
		end
		if moment == "Boss" or isBossMoment or moment == "WayFull" then
			hudState.Round(15)
			hudState.IsBossRound(true)
			hudState.NextBossRound(15)
		end
		if moment == "Heal" then
			hudState.Health(40)
			hudState.BarHealth(40)
		end

		local memory = BossBar.NewMemory()
		local healthChase = BarJuice.NewChase(hudState.BarHealth())
		local seen = {
			DataId = 0,
			Name = "",
			Share = 0,
			Top = { { UserId = 0, Name = "", Share = 0 }, { UserId = 0, Name = "", Share = 0 } },
			SelfId = 1,
			IsRunning = true,
			WayKills = 0,
			WayNeeded = 400,
			Drops = {},
			WonAt = {},
		}
		-- The T-Rex's real drops; the shoulders owned in BossOwned, and won half a second after the fall in BossFall.
		for index, item in EquipmentCore.DropsOf(EEnemiesIds.TRex) do
			local drop = item.Drop :: any
			seen.Drops[index] = {
				Id = item.Id,
				Chance = drop.Chance,
				IsOwned = moment == "BossOwned" and item.Id == EEquipmentIds.KnightShoulders,
			}
		end
		-- A stand-in third piece, so the bench shows a list as long as the reference's.
		table.insert(seen.Drops, { Id = EEquipmentIds.KnightHelmet, Chance = 0.3, IsOwned = false })
		if moment == "BossFall" then
			task.delay(MOMENT_AT + 1.1, function()
				seen.WonAt[EEquipmentIds.KnightShoulders] = os.clock()
			end)
		end
		local last = os.clock()
		RunService.Heartbeat:Connect(function()
			local now = os.clock()
			local dt = now - last
			last = now
			local t = now - startedAt
			seen.WayKills = wayKills(t)
			local isUp = (moment == "Boss" or isBossMoment or moment == "WayFull")
				and now >= bossAt
				and not (moment == "BossFall" and t >= MOMENT_AT + 0.6)
			local share, mine = bossShare(t)
			seen.DataId = if isUp then 1 else 0
			seen.Name = if isUp then "The Cove King" else ""
			seen.Share = if isUp then share else 0
			-- A squadmate leads until the local player's part passes theirs. The parts come ten times a second, as the
			-- server sends them.
			local sent = math.floor(math.max(t - MOMENT_AT, 0) * 10) / 10
			local theirs = if moment == "BossFight" then 0.15 + 0.05 * math.min(sent, 1) else 0.2
			if moment == "BossShare" then
				-- They come on first, the local player 0.6 s later streaming faster, passing them at 2.3 s, and a big blow
				-- at 3 s.
				theirs = if t >= MOMENT_AT then 0.04 + 0.006 * sent else 0
				mine = if sent >= 0.6 then 0.02 + 0.02 * (sent - 0.6) + (if sent >= 3 then 0.1 else 0) else 0
			end
			local isAhead = mine > theirs
			local me = { 1, "Molyi", mine }
			local them = { 2, "Dragonslayer99", theirs }
			for rank, who in (if isAhead then { me, them } else { them, me }) do
				local line = seen.Top[rank]
				local isOn = isUp and who[3] > 0
				line.UserId = if isOn then who[1] else 0
				line.Name = if isOn then who[2] else ""
				line.Share = if isOn then who[3] else 0
			end
			BossBar.Update(hudState.Boss, memory, seen, now, dt)
			-- Up before the story began: its arrival is long over.
			if isUp and bossAt < startedAt and hudState.Boss.AppearedAt() > bossAt then
				hudState.Boss.AppearedAt(bossAt)
			end
			if moment == "Hurt" or moment == "Heal" then
				hudState.Health(health(t))
				hudState.BarHealth(health(t))
			end
			local isGrowing = hudState.BarMax() ~= hudState.MaxHealth()
			local bite = BarJuice.Step(healthChase, hudState.BarHealth(), hudState.BarMax(), dt, now, isGrowing)
			BarJuice.Write(hudState.HealthTrack, healthChase, bite, hudState.BarHealth() / hudState.BarMax(), now)
			hudState.Now(os.clock())
			weapon.Clock(os.clock())
			hudState.Vital.Clock(os.clock())
			-- The bar's growth, as HudController walks it.
			local landAt = hudState.Vital.LandAt()
			local grown = 1 - (1 - math.clamp((os.clock() - landAt) / HealthUpgrade.Timing.GROW, 0, 1)) ^ 3
			local max = hudState.MaxHealth()
			local barMax = if moment == "HealthBuy" then 100 + (max - 100) * grown else max
			hudState.BarMax(barMax)
			hudState.BarHealth(hudState.Health() - (max - barMax))
		end)
		local root = create("Frame")({
			Name = "Root",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Wave.Build(hudState, ACTIONS),
			Items.Build(hudState, ACTIONS),
			Announce.Build(hudState),
			Upgrades.Build(hudState, ACTIONS),
			Shop.Abilities(hudState, ACTIONS),
			Hotbar.Build(hudState),
			WeaponUpgrade.Build(hudState, Upgrades.WEAPON_PICTURE, Upgrades.PICTURE_SIZE, Upgrades.PICTURE_TILT),
			-- Where the designer drew the bar over his character.
			HealthUpgrade.Build(hudState, Upgrades.HEALTH_PICTURE, Upgrades.HEALTH_PICTURE_SIZE),
			-- Where the designer drew the bar over his character.
			HealthBar.Build(hudState, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(1241, 505),
				Size = UDim2.fromOffset(200, 22),
			}),
			Squad.Build(hudState, ACTIONS),
		})
		swapImages(root)
		return root
	end,
}
