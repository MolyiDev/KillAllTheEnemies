-- The Mutation Lab in the lobby (PotionsCore): each player's lab told to their screen (Mutation.Sync), brewing potions
-- from two kinds of souls (Energy in the data), dissolving them back, putting them in and out of the slots, the slot
-- sold for Gems, the brew sold for Robux, the index's potion reveals marked as played, and the `potions` console
-- command. The energy is dropped and the potions drunk in the Game
-- place (its MutationService). The rarity is rolled here and the potion written in the same write that spends the
-- energy and the brew.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Conch = require(ReplicatedStorage.Packages.conch)
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local NetworkMeta = require(ServerScriptService.GlobalServer.NetworkMeta)
local DatabaseService = require(ServerScriptService.GlobalServer.Services.DatabaseService)
local PurchasesService = require(ServerScriptService.GlobalServer.Services.PurchasesService)
local ShopService = require(ServerScriptService.GlobalServer.Services.ShopService)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local PotionsCore = require(ReplicatedStorage.GlobalShared.Core.PotionsCore)
local ShopCore = require(ReplicatedStorage.GlobalShared.Core.ShopCore)
local DailyRewardsCore = require(ReplicatedStorage.Shared.Core.DailyRewardsCore)
local CommandTypes = require(ReplicatedStorage.Types.CommandTypes)
local EEnemiesIds = require(ReplicatedStorage.Types.Enums.Data.EEnemiesIds)
local EProducts = require(ReplicatedStorage.Types.Enums.EProducts)
local EPotionsIds = require(ReplicatedStorage.Types.Enums.Data.EPotionsIds)
local ERarities = require(ReplicatedStorage.Types.Enums.ERarities)
local TData = require(ReplicatedStorage.Types.TData)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)
local TProfile = require(ReplicatedStorage.Types.TProfile)

local ServerNetworkMutation = NetworkMeta.Server.Mutation
local ClientNetworkMutation = NetworkMeta.Client.Mutation
local args = Conch.args

local PERMISSION_DEV = "command.dev"
-- A second past midnight, so a clock a hair behind the server's still reads the new day.
local ROLLOVER_MARGIN = 1
local SLOT_KINDS = table.freeze({ Free = 1, Pass = 2, Gems = 3 })

local MutationService = {}

local random = Random.new()
local potionsByName: { [string]: TData.TPotion } = {}
for _, potion in DataCore.Potions.All do
	potionsByName[potion.Name] = potion
end

local function send(player: Player, profile: TProfile.TProfile)
	local now = os.time()
	local isRestricted = ShopService.IsRandomRestricted(player)
	local perDay = PotionsCore.BrewsPerDay(profile, isRestricted)
	local mutation = profile.Mutation

	local discovered, energyIds, energyCounts = {}, {}, {}
	for _, enemy in PotionsCore.ENERGIES do
		if profile.Index and profile.Index[enemy.Name] then table.insert(discovered, enemy.Id) end
		local held = if mutation then mutation.Energy[enemy.Name] or 0 else 0
		if held <= 0 then continue end
		table.insert(energyIds, enemy.Id)
		table.insert(energyCounts, held)
	end

	local potionIds, recipes, rarities, matches = {}, {}, {}, {}
	local foundIds, foundCounts, foundNew = {}, {}, {}
	if mutation then
		for _, potion in mutation.Potions do
			local data = potionsByName[potion.Name]
			if not data then continue end
			table.insert(potionIds, potion.Id)
			table.insert(recipes, data.Id)
			table.insert(rarities, (ERarities :: any)[potion.Rarity] or ERarities.Common)
			table.insert(matches, potion.Matches)
		end
		-- By the data rather than the saved keys: a recipe taken out of the game is not on the wire.
		for _, data in DataCore.Potions.All do
			local found = mutation.Found[data.Name]
			if not found then continue end
			table.insert(foundIds, data.Id)
			table.insert(foundCounts, found.Brewed)
			table.insert(foundNew, found.IsNew == true)
		end
	end

	local slotKinds, slotsOpen = {}, {}
	for _, slot in PotionsCore.Slots(profile) do
		table.insert(slotKinds, SLOT_KINDS[slot.Kind])
		table.insert(slotsOpen, slot.IsOpen)
	end

	ServerNetworkMutation.Sync.Fire(player, {
		Discovered = discovered,
		EnergyIds = energyIds,
		EnergyCounts = energyCounts,
		PotionIds = potionIds,
		PotionRecipes = recipes,
		PotionRarities = rarities,
		PotionMatches = matches,
		Equipped = if mutation then table.clone(mutation.Equipped) else {},
		SlotKinds = slotKinds,
		SlotsOpen = slotsOpen,
		BrewsLeft = PotionsCore.BrewsLeft(mutation, DailyRewardsCore.Today(now), perDay),
		BrewsPerDay = perDay,
		SecondsLeft = DailyRewardsCore.SecondsLeft(now),
		Luck = ShopCore.Luck(profile, isRestricted),
		FoundIds = foundIds,
		FoundCounts = foundCounts,
		FoundNew = foundNew,
	})
end

-- At every UTC midnight the brews come back, so everybody is told.
local function rollOver()
	for _, player in Players:GetPlayers() do
		local profile = DatabaseService.Get(player)
		if profile then send(player, profile) end
	end

	task.delay(DailyRewardsCore.SecondsLeft(os.time()) + ROLLOVER_MARGIN, rollOver)
end

-- Puts a potion of `recipe` at `rarity` in `mutation` and counts the recipe found. Returns the new potion's Id.
local function addPotion(mutation: TProfile.TMutation, recipe: TData.TPotion, rarity: number): number
	local id = mutation.NextId
	mutation.NextId += 1
	table.insert(mutation.Potions, {
		Id = id,
		Name = recipe.Name,
		Rarity = PotionsCore.RARITY_NAMES[rarity],
		Matches = PotionsCore.MatchesOf(rarity),
	})

	local found = mutation.Found[recipe.Name]
	if found then
		found.Brewed += 1
	else
		mutation.Found[recipe.Name] = { Brewed = 1, IsNew = true }
	end

	return id
end

-- Brews `recipe` into `mutation`: spends both energies and a brew (the day's free ones first, then a bought one), rolls
-- the rarity, and returns the new potion's Id, or 0 when the energy or the brew is not there.
local function brew(mutation: TProfile.TMutation, recipe: TData.TPotion, today: number, perDay: number, luck: number)
	if PotionsCore.BrewsLeft(mutation, today, perDay) <= 0 then return 0 end
	for _, enemyId in recipe.Energies do
		local enemy = DataCore.Enemies.ById[enemyId]
		local energy = enemy.Energy :: TData.TEnemyEnergy
		if (mutation.Energy[enemy.Name] or 0) < energy.Cost then return 0 end
	end

	local held: { [string]: number? } = mutation.Energy
	for _, enemyId in recipe.Energies do
		local enemy = DataCore.Enemies.ById[enemyId]
		local left = mutation.Energy[enemy.Name] - (enemy.Energy :: TData.TEnemyEnergy).Cost
		held[enemy.Name] = if left > 0 then left else nil
	end

	if PotionsCore.FreeBrewsLeft(mutation, today, perDay) > 0 then
		if mutation.BrewDay ~= today then
			mutation.BrewDay = today
			mutation.BrewsUsed = 0
		end
		mutation.BrewsUsed += 1
	else
		local bought = (mutation.BrewsBought or 0) - 1
		mutation.BrewsBought = if bought > 0 then bought else nil
	end

	return addPotion(mutation, recipe, PotionsCore.RollRarity(random:NextNumber(), luck))
end

local function holds(mutation: TProfile.TMutation, potionId: number): boolean
	for _, potion in mutation.Potions do
		if potion.Id == potionId then return true end
	end

	return false
end

-- Takes the potion `potionId` out of `mutation` and gives back its share of souls. False when it is not held, or is in
-- a slot.
local function dissolve(mutation: TProfile.TMutation, potionId: number): boolean
	if table.find(mutation.Equipped, potionId) then return false end
	local index = 0
	for at, potion in mutation.Potions do
		if potion.Id ~= potionId then continue end
		index = at
		break
	end
	if index == 0 then return false end

	local potion = table.remove(mutation.Potions, index) :: TProfile.TPotion
	local recipe = potionsByName[potion.Name]
	local rarity = (ERarities :: any)[potion.Rarity] :: number?
	if not recipe or not rarity then return true end
	for at, amount in PotionsCore.Refund(recipe, rarity) do
		if amount <= 0 then continue end
		local enemy = DataCore.Enemies.ById[recipe.Energies[at]]
		mutation.Energy[enemy.Name] = (mutation.Energy[enemy.Name] or 0) + amount
	end
	return true
end

-- The kinds of energy a command names: every kind for "all" (or none named), else the one whose EEnemiesIds key it is
-- in lower case, if it drops energy.
local function energiesNamed(target: string?): { TData.TEnemy }
	if not target or target == "all" then return PotionsCore.ENERGIES end
	for key, id in EEnemiesIds :: { [string]: number } do
		if string.lower(key) ~= target then continue end
		local enemy = DataCore.Enemies.ById[id]
		return if enemy and enemy.Energy then { enemy } else {}
	end

	return {}
end

-- The recipes a command names: every one for "all", else the one whose EPotionsIds key it is in lower case.
local function recipesNamed(target: string): { TData.TPotion }
	if target == "all" then return DataCore.Potions.All end
	for key, id in EPotionsIds :: { [string]: number } do
		if string.lower(key) ~= target then continue end
		local recipe = DataCore.Potions.ById[id]
		return if recipe then { recipe } else {}
	end

	return {}
end

-- A rarity a command names (an ERarities key in lower case), or nil for "random" or none named.
local function rarityNamed(target: string?): number?
	for key, rarity in ERarities :: { [string]: number } do
		if string.lower(key) == target then return rarity end
	end

	return nil
end

local function registerPotions()
	Conch.register("potions", {
		permissions = { PERMISSION_DEV },
		description = "Test the Mutation Lab: give energy, potions, today's brews or the Gems slot, or empty it.",
		arguments = function()
			return args.overload({
				{
					description = "Give energy of every kind, or of one",
					arguments = {
						args.literal("energy"),
						args.number("amount", "How much of each kind."),
						args.optional(CommandTypes.enemyOrAll("kind", "The enemy whose energy, or all (default all).")),
					},
				},
				{
					description = "Give potions as if brewed (each recipe counts as found)",
					arguments = {
						args.literal("give"),
						CommandTypes.potionOrAll("recipe", "The potion, or all."),
						args.optional(CommandTypes.rarityOrRandom("rarity", "Its rarity, or random (default random).")),
						args.optional(args.number("count", "How many of each (default 1).")),
					},
				},
				{
					description = "Give back today's brews",
					arguments = { args.literal("brews") },
				},
				{
					description = "Open the slot sold for Gems, or close it again, without paying",
					arguments = { args.literal("slot") },
				},
				{
					description = "Empty the lab: no energy, potions, found recipes or bought slot",
					arguments = { args.literal("clear") },
				},
			})
		end,
		-- The overloads' arguments after the action, by position: energy (amount, kind), give (recipe, rarity, count).
		callback = function(action: string, first: any?, second: any?, third: any?)
			local player = (Conch.get_command_context() :: any).executor.player :: Player?
			if not player then return end
			local summary = "the lab is empty"
			DatabaseService.Update(player, function(profile)
				if action == "clear" then
					profile.Mutation = nil
					return true
				end
				local mutation = profile.Mutation or PotionsCore.Empty()
				profile.Mutation = mutation
				if action == "energy" then
					local amount = math.max(math.floor(first or 0), 0)
					local kinds = energiesNamed(second)
					for _, enemy in kinds do
						mutation.Energy[enemy.Name] = (mutation.Energy[enemy.Name] or 0) + amount
					end
					summary = `{amount} energy of {#kinds} kind(s) given`
				elseif action == "give" then
					local recipes = recipesNamed(first or "")
					local rarity = rarityNamed(second)
					local count = math.max(math.floor(third or 1), 1)
					local luck = ShopCore.Luck(profile, ShopService.IsRandomRestricted(player))
					for _, recipe in recipes do
						for _ = 1, count do
							addPotion(mutation, recipe, rarity or PotionsCore.RollRarity(random:NextNumber(), luck))
						end
					end
					summary = `{#recipes * count} potion(s) given`
				elseif action == "brews" then
					mutation.BrewsUsed = 0
					summary = "today's brews are back"
				elseif action == "slot" then
					mutation.HasGemSlot = not mutation.HasGemSlot
					-- A potion in the slot just closed comes out of it.
					local slots = PotionsCore.SlotCount(profile)
					while #mutation.Equipped > slots do
						table.remove(mutation.Equipped)
					end
					summary = if mutation.HasGemSlot then "the Gems slot is open" else "the Gems slot is closed"
				end
				return true
			end)
			Conch.log("normal", `Potions: {summary}.`)
		end,
	})
end

MutationService.OnStart = function()
	registerPotions()
	task.delay(DailyRewardsCore.SecondsLeft(os.time()) + ROLLOVER_MARGIN, rollOver)

	PurchasesService.Register(EProducts.ExtraBrew, function(_player: Player, profile: TProfile.TProfile)
		local mutation = profile.Mutation or PotionsCore.Empty()
		mutation.BrewsBought = (mutation.BrewsBought or 0) + 1
		profile.Mutation = mutation
		return true
	end)
end

MutationService.OnDataLoaded = function(player: Player)
	local profile = DatabaseService.Get(player)
	if profile then send(player, profile) end
end :: TPlayerEvents.OnDataLoaded

-- A brew, a slot, a pass bought or a match's energy written changes what the screen shows.
DatabaseService.OnProfileChanged:Connect(send)

-- Needs no character: the lab is a menu. Every Brew is answered with a Brewed, a refused one too, so the screen
-- waiting on it always settles; it follows the Sync of the same write, in the same frame. A batch brews one at a time
-- and stops at the first the souls or the brews cannot pay for.
ClientNetworkMutation.Brew.On(function(player: Player, first: number, second: number, count: number)
	local recipe = PotionsCore.RecipeOf(first, second)
	local made: { number } = {}
	if recipe and count > 0 then
		local today = DailyRewardsCore.Today(os.time())
		local isRestricted = ShopService.IsRandomRestricted(player)
		DatabaseService.Update(player, function(profile)
			local mutation = profile.Mutation
			if not mutation then return false end
			local perDay = PotionsCore.BrewsPerDay(profile, isRestricted)
			local luck = ShopCore.Luck(profile, isRestricted)
			for _ = 1, math.min(count, PotionsCore.MAX_BATCH) do
				local potionId = brew(mutation, recipe, today, perDay, luck)
				if potionId == 0 then break end
				table.insert(made, potionId)
			end
			return #made > 0
		end)
	end

	ServerNetworkMutation.Brewed.Fire(player, made)
	if #made > 0 then DatabaseService.SaveAsync(player) end
end)

-- Answered with a Dissolved, a refused one too, after the Sync of the same write.
ClientNetworkMutation.Dissolve.On(function(player: Player, potionIds: { number })
	local gone: { number } = {}
	DatabaseService.Update(player, function(profile)
		local mutation = profile.Mutation
		if not mutation then return false end
		for _, potionId in potionIds do
			if dissolve(mutation, potionId) then table.insert(gone, potionId) end
		end
		return #gone > 0
	end)

	ServerNetworkMutation.Dissolved.Fire(player, gone)
	if #gone > 0 then DatabaseService.SaveAsync(player) end
end)

ClientNetworkMutation.Equip.On(function(player: Player, potionId: number)
	local isDone = DatabaseService.Update(player, function(profile)
		local mutation = profile.Mutation
		if not mutation or not holds(mutation, potionId) then return false end
		if table.find(mutation.Equipped, potionId) then return false end
		if #mutation.Equipped >= PotionsCore.SlotCount(profile) then return false end
		table.insert(mutation.Equipped, potionId)
		return true
	end)

	-- A refused request is answered too, so the screen drops what it guessed.
	local profile = DatabaseService.Get(player)
	if not isDone and profile then send(player, profile) end
end)

ClientNetworkMutation.Unequip.On(function(player: Player, potionId: number)
	local isDone = DatabaseService.Update(player, function(profile)
		local mutation = profile.Mutation
		local index = if mutation then table.find(mutation.Equipped, potionId) else nil
		if not mutation or not index then return false end
		table.remove(mutation.Equipped, index)
		return true
	end)

	local profile = DatabaseService.Get(player)
	if not isDone and profile then send(player, profile) end
end)

ClientNetworkMutation.BuySlot.On(function(player: Player)
	local isBought = DatabaseService.Update(player, function(profile)
		local mutation = profile.Mutation or PotionsCore.Empty()
		if mutation.HasGemSlot or profile.Gems < PotionsCore.GEM_SLOT_PRICE then return false end
		profile.Gems -= PotionsCore.GEM_SLOT_PRICE
		mutation.HasGemSlot = true
		profile.Mutation = mutation
		return true
	end)

	local profile = DatabaseService.Get(player)
	if isBought then
		DatabaseService.SaveAsync(player)
	elseif profile then
		send(player, profile)
	end
end)

-- Only flags the profile already holds are cleared, so a made-up id changes nothing. The screen has already shown the
-- reveal, so the Sync this sends changes nothing on it.
ClientNetworkMutation.Seen.On(function(player: Player, recipeIds: { number })
	DatabaseService.Update(player, function(profile)
		local mutation = profile.Mutation
		if not mutation then return false end
		local hasChanged = false
		for _, recipeId in recipeIds do
			local data = DataCore.Potions.ById[recipeId]
			local found = if data then mutation.Found[data.Name] else nil
			if not found or not found.IsNew then continue end
			found.IsNew = nil
			hasChanged = true
		end
		return hasChanged
	end)
end)

return Ignis.Register(MutationService)
