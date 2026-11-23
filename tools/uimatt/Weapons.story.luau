-- The lobby's weapons screen with a fixed state, for rur to render beside the designer's Weapons Shop render
-- (Assets/ui/UIMatt/renders/02_Weapons_Shop.png, the same renderer and background):
--   rur-native render --headless --offline --rojo <lobby.project.json without its comments> \
--     --story tools/uimatt/Weapons.story.luau --viewport 1920x1080 --scale 1 --background 40,40,60 --time 2 \
--     --controls '{"Moment": "Rest"}' --dir <out>
-- Moment: Rest (everything landed: tier 1, the Desert Eagle picked and held, 48,250 Gems), Enter (the screen opening
-- 0.2 s in), Buy (the Freeze Pistol bought 0.2 s in: the Gems fly into the stage, then it unlocks and crosses into
-- OWNED), Upgrade (the Desert Eagle raised to level 2), Tier (tier 3 picked 0.2 s in), Refused (a purchase he cannot
-- pay for), Show / Hide (the Desert Eagle put on the back / taken off 0.2 s in), Close (the screen shut 1.7 s in, once
-- everything has landed), for `rur-native sequence`. The group-owned images 403 offline, so they are swapped for the local PNGs
-- they were made from. The guns' meshes are private and rur cannot be pointed at local copies of them, so the gun
-- pictures come out empty here: judge them in a playtest.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Icons = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Icons)
local EGunsIds = require(ReplicatedStorage.Types.Enums.Data.EGunsIds)
local Screen = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.WeaponsController.Screen)

local source = vide.source
local create = vide.create

local ROOT = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/hud/"
local SWAPS = {
	[Icons.IMAGE] = ROOT .. "Icons.png",
	[Icons.PANEL_TEXTURE] = ROOT .. "PanelTexture.png",
}
local MOMENT_AT = 0.2
local GEMS = 48250
local FLIGHT = Screen.FLIGHT_SECONDS
local CLOSE_AT = 1.7

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

local function noop() end

return {
	vide = vide,
	controls = {
		Moment = { "Rest", "Enter", "Buy", "Upgrade", "Tier", "Refused", "Show", "Hide", "Close" },
	},
	story = function(props)
		local moment = props.controls.Moment()
		local at = os.clock() + MOMENT_AT
		local levels = {
			[EGunsIds.StarterPistol] = 2,
			[EGunsIds.AaMitra] = 1,
			[EGunsIds.DesertEagle] = 1,
			[EGunsIds.StarterRifle] = 1,
			[EGunsIds.StarterShotgun] = 1,
			[EGunsIds.StarterSmg] = 1,
		}
		local equipped = { EGunsIds.DesertEagle, EGunsIds.StarterRifle, EGunsIds.StarterShotgun, EGunsIds.StarterSmg }
		local isBuy = moment == "Buy"
		local isUpgrade = moment == "Upgrade"
		local isShow = moment == "Show"
		local isHide = moment == "Hide"
		local isClosing = moment == "Close"
		local closeAt = at - MOMENT_AT + CLOSE_AT

		local state = {
			Scale = source(1),
			Now = source(os.clock()),
			StageClock = source(os.clock()),
			IsOpen = source(true),
			ToggledAt = source(if moment == "Enter" then at else -math.huge),
			Tier = source(if moment == "Tier" then 3 else 1),
			TierAt = source(if moment == "Tier" then at else -math.huge),
			Selected = source(if isBuy or moment == "Refused" then EGunsIds.FreezePistol else EGunsIds.DesertEagle),
			SelectedAt = source(-math.huge),
			Levels = source(levels),
			Equipped = source(equipped),
			Shown = source(if isHide then EGunsIds.DesertEagle else 0),
			ShownAt = source(-math.huge),
			ShownFor = source(0),
			Gems = source(GEMS),
			Pending = source(nil),
			BoughtGun = source(if isBuy then EGunsIds.FreezePistol else 0),
			BoughtAt = source(if isBuy then at + FLIGHT else -math.huge),
			UpgradedGun = source(if isUpgrade then EGunsIds.DesertEagle else 0),
			UpgradedAt = source(if isUpgrade then at + FLIGHT else -math.huge),
			PaidAt = source(if isBuy or isUpgrade then at else -math.huge),
			PaidFor = source(if isUpgrade then "Upgrade" else "Buy"),
			EquippedAt = source(if isBuy then at + FLIGHT else -math.huge),
			RefusedAt = source(if moment == "Refused" then at else -math.huge),
		}

		-- What the controller does as the Gems land: the purchase or the level shows.
		local held = nil
		if isBuy then
			held = table.clone(levels)
			held[EGunsIds.FreezePistol] = 1
		elseif isUpgrade then
			held = table.clone(levels)
			held[EGunsIds.DesertEagle] = 2
		end
		local heldEquipped = table.clone(equipped)
		if isBuy then heldEquipped[1] = EGunsIds.FreezePistol end

		-- The answer to SHOW or HIDE, written on the frame it comes, as the controller writes it.
		local isAnswerDue = isShow or isHide
		RunService.Heartbeat:Connect(function()
			local now = os.clock()
			state.Now(now)
			state.StageClock(now)
			if isAnswerDue and now >= at then
				isAnswerDue = false
				vide.batch(function()
					state.Shown(if isShow then EGunsIds.DesertEagle else 0)
					state.ShownFor(EGunsIds.DesertEagle)
					state.ShownAt(now)
				end)
			end
			if isClosing and now >= closeAt then
				isClosing = false
				vide.batch(function()
					state.IsOpen(false)
					state.ToggledAt(now)
				end)
			end
			if held and now >= at + FLIGHT then
				state.Levels(held)
				state.Equipped(heldEquipped)
				held = nil
			end
		end)

		local root = create("Frame")({
			Name = "Root",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(1920, 1080),
			Screen.Build(state, {
				Close = noop,
				PickTier = noop,
				Select = noop,
				Buy = noop,
				Upgrade = noop,
				Equip = noop,
				Show = noop,
				Try = noop,
				Stir = noop,
			}),
		})
		swapImages(root)
		return root
	end,
}
