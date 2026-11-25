-- The lobby's Mutation Lab with a fixed state, for rur to render beside the designer's Monster Mutation render
-- (Assets/ui/UIMatt/renders/17_Monster_Mutation.png, the same renderer and background):
--   rur-native render --headless --offline --rojo <lobby.project.json without its comments> \
--     --story tools/uimatt/Mutation.story.luau --viewport 1920x1080 --scale 1 --background 40,40,60 --time 2 \
--     --controls '{"Moment": "Rest"}' --dir <out>
-- Moment: Rest (two souls picked, their recipe previewed), Empty (nothing picked, the boss's souls locked), Brew
-- (BREW pressed 0.2 s in, answered 0.3 s later with the potion of `Rarity`: film it with `rur-native sequence`),
-- Batch (the same, `Count` potions at once in the tray, the rarest `Rarity`, each thrown into the POTIONS tab), Shown (a potion of
-- `Rarity` on the card at rest), Menu (the count menu open), Buy (out of brews: BREW sells one for Robux), Potions
-- (the POTIONS page: two slots open, one filled, the pass's closed, nine potions held), Full (every slot open and
-- filled), Dissolve (picking potions to dissolve, two picked). The group-owned images 403 offline, so they are swapped
-- for the local PNGs they were made from. The enemy rigs live in the places, not on disk, so the energy pictures come
-- out empty here: judge them in a playtest.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Icons = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Icons)
local EEnemiesIds = require(ReplicatedStorage.Types.Enums.Data.EEnemiesIds)
local EPotionsIds = require(ReplicatedStorage.Types.Enums.Data.EPotionsIds)
local ERarities = require(ReplicatedStorage.Types.Enums.ERarities)
local Flight = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.MutationController.Flight)
local Brew = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.MutationController.Brew)
local Parts = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.MutationController.Parts)
local Tray = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.MutationController.Tray)
local PotionsCore = require(ReplicatedStorage.GlobalShared.Core.PotionsCore)
local Screen = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.MutationController.Screen)

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
local ANSWER_AFTER = 0.3

local function swapImages(root: Instance)
	local function swap(instance: Instance)
		if not instance:IsA("ImageLabel") and not instance:IsA("ImageButton") then return end
		local image = instance :: ImageLabel
		local path = SWAPS[image.Image]
		if path then image.Image = path end
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
		Moment = { "Rest", "Empty", "Brew", "Batch", "Shown", "Menu", "Buy", "Potions", "Full", "Dissolve" },
		Rarity = { "Epic", "Common", "Uncommon", "Rare", "Legendary", "Mythic" },
		Count = { "5", "3", "10" },
	},
	story = function(props)
		local moment = props.controls.Moment()
		local rarity = (ERarities :: any)[props.controls.Rarity()] :: number
		local count = if moment == "Batch" then tonumber(props.controls.Count()) :: number else 1
		local at = os.clock() + MOMENT_AT
		local isPotions = moment == "Potions" or moment == "Full" or moment == "Dissolve"
		local isBrewing = moment == "Brew" or moment == "Batch"

		local potions = {
			{ Id = 1, Recipe = EPotionsIds.IronHide, Rarity = ERarities.Epic, Matches = 1 },
			{ Id = 2, Recipe = EPotionsIds.TriggerStorm, Rarity = ERarities.Mythic, Matches = 2 },
			{ Id = 3, Recipe = EPotionsIds.Bloodroot, Rarity = ERarities.Common, Matches = 1 },
			{ Id = 4, Recipe = EPotionsIds.KingsFeast, Rarity = ERarities.Legendary, Matches = 1 },
			{ Id = 5, Recipe = EPotionsIds.SecondWind, Rarity = ERarities.Rare, Matches = 1 },
			{ Id = 6, Recipe = EPotionsIds.Juggernaut, Rarity = ERarities.Common, Matches = 1 },
			{ Id = 7, Recipe = EPotionsIds.VampiresKiss, Rarity = ERarities.Rare, Matches = 1 },
			{ Id = 8, Recipe = EPotionsIds.BoneWard, Rarity = ERarities.Common, Matches = 1 },
			{ Id = 9, Recipe = EPotionsIds.GoldRush, Rarity = ERarities.Epic, Matches = 1 },
		}
		local shownPotion = {
			Id = 10,
			Recipe = EPotionsIds.IronHide,
			Rarity = rarity,
			Matches = if rarity == ERarities.Mythic then 2 else 1,
		}
		local found = {}
		for _, potion in potions do
			found[potion.Recipe] = { Brewed = 1, IsNew = false }
		end

		local slots = if moment == "Full"
			then { { Kind = 1, IsOpen = true }, { Kind = 2, IsOpen = true }, { Kind = 3, IsOpen = true } }
			else { { Kind = 1, IsOpen = true }, { Kind = 3, IsOpen = true }, { Kind = 2, IsOpen = false } }
		local picks = if moment == "Empty" then {} else { EEnemiesIds.Basic, EEnemiesIds.Heavy }
		local discovered = {
			[EEnemiesIds.Basic] = true,
			[EEnemiesIds.Fast] = true,
			[EEnemiesIds.Exploding] = true,
			[EEnemiesIds.Heavy] = true,
			[EEnemiesIds.Slammer] = true,
		}
		if moment ~= "Empty" then discovered[EEnemiesIds.TRex] = true end

		local state = {
			Scale = source(1),
			Now = source(os.clock()),
			IsOpen = source(true),
			ToggledAt = source(-math.huge),
			Tab = source(if isPotions then 2 else 1),
			TabAt = source(-math.huge),
			Discovered = source(discovered),
			Energy = source({
				[EEnemiesIds.Basic] = 120,
				[EEnemiesIds.Fast] = 45,
				[EEnemiesIds.Exploding] = 3,
				[EEnemiesIds.Heavy] = 18,
				[EEnemiesIds.Slammer] = 9,
				[EEnemiesIds.TRex] = if moment == "Empty" then 0 else 2,
			}),
			CanBuyBrew = source(true),
			Potions = source(potions),
			Equipped = source(if moment == "Full" then { 2, 4, 1 } else { 2 }),
			Slots = source(slots),
			BrewsLeft = source(if moment == "Buy" then 0 elseif moment == "Batch" then 12 else 2),
			BrewsPerDay = source(2),
			BrewsBackAt = source(os.time() + 3600 * 5),
			Luck = source(1),
			Found = source(found),
			Gems = source(48250),
			Picks = source(picks),
			PickedAt = source({}),
			BrewCount = source(
				if moment == "Batch" then count elseif moment == "Menu" or moment == "Buy" then 5 else 1
			),
			IsMenuOpen = source(moment == "Menu"),
			MenuAt = source(if moment == "Menu" then -1000 else -math.huge),
			-- Rest: the light crosses BREW as it opens (render at 0.55 s to see it mid-way).
			CalledAt = source(if moment == "Rest" then at else -math.huge),
			BrewAt = source(if moment == "Shown" then -1000 elseif isBrewing then at else -math.huge),
			Asked = source(count),
			AnsweredAt = source(if moment == "Shown" then -1000 else math.huge),
			BrewedId = source(0),
			Shown = source(if moment == "Shown" then shownPotion else nil),
			IsShownNew = source(moment == "Shown"),
			Batch = source(if moment == "Shown" then { shownPotion } else {}),
			Flights = source({}),
			LandedAt = source({ -math.huge, -math.huge }),
			Unseen = source(if isPotions then 0 else 3),
			IsDissolving = source(moment == "Dissolve"),
			DissolveAt = source(-1000),
			DissolvePicks = source(if moment == "Dissolve" then { [6] = true, [8] = true } else {}),
			Leaving = source({}),
			Gained = source(""),
			GainedAt = source(-math.huge),
			Locate = {},
			Clock = source(os.time()),
			Refused = source(""),
			RefusedAt = source(-math.huge),
			RefusedText = source(""),
			SlottedId = source(0),
			SlottedAt = source(-math.huge),
		}

		-- The batch the Batch moment brews: the rest rolled as a brew rolls them (none past `Rarity`), sorted, the rarest
		-- last, as the controller sorts them.
		local batch = { shownPotion }
		if moment == "Batch" then
			local rolls = Random.new(count)
			local rarities = table.create(count - 1)
			for index = 1, count - 1 do
				rarities[index] = math.min(PotionsCore.RollRarity(rolls:NextNumber(), 1), rarity)
			end
			table.sort(rarities)
			batch = table.create(count)
			for index, rolled in rarities do
				batch[index] = {
					Id = 10 + index,
					Recipe = EPotionsIds.IronHide,
					Rarity = rolled,
					Matches = if rolled == ERarities.Mythic then 2 else 1,
				}
			end
			batch[count] = shownPotion
		end
		local function lookOf(potion): any
			return {
				Picture = "PotionBottle",
				Color = Parts.Rarity(potion.Rarity).Accent,
				Size = 64,
				Tab = 2,
				PotionId = potion.Id,
			}
		end
		local random = Random.new(7)
		local answerAt = if isBrewing then at + ANSWER_AFTER else math.huge
		RunService.Heartbeat:Connect(function()
			local now = os.clock()
			state.Now(now)
			if now < answerAt then return end
			answerAt = math.huge
			state.Shown(shownPotion)
			state.Batch(batch)
			state.IsShownNew(true)
			state.AnsweredAt(now)
			local times = Brew.Times(state :: any) :: any
			if #batch == 1 then
				state.Flights(
					Flight.Plan(
						{ lookOf(shownPotion) },
						Vector2.new(1071, 421),
						Vector2.new(640, 224),
						times.FlyAt,
						0,
						random
					)
				)
				return
			end
			local flights = {}
			for index, potion in batch do
				local thrownAt = times.FlyAt + Brew.FLY_STAGGER * (index - 1)
				for _, flight in
					Flight.Plan(
						{ lookOf(potion) },
						Tray.CardAt(index, #batch),
						Vector2.new(640, 224),
						thrownAt,
						0,
						random
					)
				do
					table.insert(flights, flight)
				end
			end
			state.Flights(flights)
		end)

		local root = create("Frame")({
			Name = "Root",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(1920, 1080),
			Screen.Build(state, {
				Close = noop,
				PickTab = noop,
				PickEnergy = noop,
				DropPick = noop,
				Brew = noop,
				SetMenu = noop,
				PickCount = noop,
				TogglePotion = noop,
				Dissolve = noop,
				CancelDissolve = noop,
				BuySlot = noop,
				Stir = noop,
			}),
		})
		swapImages(root)
		return root
	end,
}
