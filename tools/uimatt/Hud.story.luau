-- The arena HUD with a fixed state, for rur to render beside the designer's In-Game HUD render
-- (Assets/ui/UIMatt/renders/15_In_Game_HUD.png, the same renderer and background):
--   rur-native render --headless --offline --rojo <game.project.json without its comments> \
--     --story tools/uimatt/Hud.story.luau --viewport 1920x1080 --scale 1 --background 40,40,60 --time 1.5 \
--     --controls '{"Phase": "Fighting"}' --dir <out>
-- The weapon card's moments (Moment: Ready, Denied, Buy, Maxed) start 0.2 s in, for `rur-native sequence`.
-- rur reads the project file as plain JSON, so strip its comments into a copy first. The HUD's group-owned images 403
-- offline, so they are swapped for the local PNGs they were made from.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local GunsCore = require(ReplicatedStorage.GlobalShared.Core.GunsCore)
local Icons = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Icons)

local hud = StarterPlayer.StarterPlayerScripts.Client.Controllers.HudController
local Wave = require(hud.Wave)
local Items = require(hud.Items)
local Upgrades = require(hud.Upgrades)
local WeaponUpgrade = require(hud.WeaponUpgrade)
local Shop = require(hud.Shop)
local Hotbar = require(hud.Hotbar)
local HealthBar = require(hud.HealthBar)

local source = vide.source
local create = vide.create

local ROOT = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/hud/"
local SWAPS = {
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

local LADDER = GunsCore.LADDER
local MOMENT_AT = 0.2

-- The gun models' meshes cannot be fetched offline, so the starter guns are swapped for silhouettes of plain parts
-- (barrel, body, grip, stock), each a different length so the swap reads.
local function standIns()
	local guns = ReplicatedStorage.Models.Guns
	local function block(model: Model, size: Vector3, position: Vector3)
		local part = Instance.new("Part")
		part.Size = size
		part.Position = position
		part.Anchored = true
		part.Parent = model
	end

	local starters = guns["starter weapons"]
	for name, barrel in { ["1"] = 0.9, ["2"] = 2.4, ["4"] = 1.6, TerminatorGun = 1.4 } do
		local folder = if name == "TerminatorGun" then guns.Epic else starters
		local old = folder:FindFirstChild(name)
		if old then old:Destroy() end
		local model = Instance.new("Model")
		model.Name = name
		block(model, Vector3.new(1.6, 0.6, 0.35), Vector3.new(0, 0, 0))
		block(model, Vector3.new(barrel, 0.22, 0.2), Vector3.new(0.8 + barrel / 2, 0.12, 0))
		block(model, Vector3.new(0.35, 0.8, 0.3), Vector3.new(-0.35, -0.6, 0))
		if name ~= "1" then block(model, Vector3.new(1.2, 0.45, 0.3), Vector3.new(-1.4, -0.15, 0)) end
		model.Parent = folder
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
		BossName = source(""),
		BossHealth = source(0),
		BossMaxHealth = source(0),
		NextBossName = source("The Cove King"),
		NextBossRound = source(15),
		Gold = source(60),
		GoldShown = source(60),
		GoldPulse = source(0),
		GoldDenied = source(0),
		Health = source(82),
		MaxHealth = source(100),
		TrailHealth = source(82),
		IsDown = source(false),
		Head = source(nil),
		IsFirstPerson = source(false),
		Vignette = source(0),
		Defenses = defenses,
		Squad = source({}),
		IsSquadOpen = source(false),
		SquadToggledAt = source(-math.huge),
		RunSeconds = source(0),
		EnemyCount = source(0),
		IsNukePrompted = source(false),
		IsHealPrompted = source(false),
		Gun = source(nil),
		GunModel = source(nil),
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
		Keys = { Skip = Enum.KeyCode.N, Turn = Enum.KeyCode.T, Upgrade = Enum.KeyCode.V },
		RoundsCleared = source(0),
		RunGold = source(0),
		RunGems = source(0),
		ReturnIn = source(0),
	}
end

local function noop() end

local ACTIONS = {
	VoteStart = noop,
	ToggleAutoSkip = noop,
	PlaceDefense = noop,
	UpgradeWeapon = noop,
	Revive = noop,
	BuyHealAll = noop,
	BuyNukeAll = noop,
	CloseSquad = noop,
}

return {
	vide = vide,
	controls = {
		Phase = { "Preparing", "Fighting" },
		Moment = { "Rest", "Ready", "Denied", "Buy", "Maxed" },
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
		end

		RunService.Heartbeat:Connect(function()
			hudState.Now(os.clock())
			weapon.Clock(os.clock())
		end)
		local root = create("Frame")({
			Name = "Root",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Wave.Build(hudState, ACTIONS),
			Items.Build(hudState, ACTIONS),
			Upgrades.Build(hudState, ACTIONS),
			Shop.Defenses(hudState, ACTIONS),
			Hotbar.Build(hudState),
			WeaponUpgrade.Build(hudState, Upgrades.WEAPON_PICTURE, Upgrades.PICTURE_SIZE, Upgrades.PICTURE_TILT),
			-- Where the designer drew the bar over his character.
			HealthBar.Build(hudState, { Position = UDim2.fromOffset(1141, 494), Size = UDim2.fromOffset(200, 22) }),
		})
		swapImages(root)
		return root
	end,
}
