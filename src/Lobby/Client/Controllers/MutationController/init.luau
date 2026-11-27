-- The Mutation Lab (UIMatt.md, Monster Mutation): brew potions out of the souls kills drop (Energy in the data),
-- dissolve them back into souls, and pick which are drunk in the next match. MutationService decides everything (a
-- brew's rarity, a slot, the Gems, a refund); this draws what it is told and sends requests. Selling a brew for Robux
-- is selling a random item, so it is offered only where PolicyService allows paid random items. The lobby's LAB card opens it; while it is up the world behind is blurred and heard under
-- water. The index's POTIONS page reads what is found here (Found, MarkSeen).
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local vide = require(ReplicatedStorage.Packages.vide)
local NetworkMeta = require(StarterPlayer.StarterPlayerScripts.GlobalClient.NetworkMeta)
-- Through PlayerScripts, the copy that runs: requiring the StarterPlayer one would load a second controller.
local BlurController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.BlurController)
local ProfileController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.ProfileController)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local PotionsCore = require(ReplicatedStorage.GlobalShared.Core.PotionsCore)
local ShopCore = require(ReplicatedStorage.GlobalShared.Core.ShopCore)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)
local ERarities = require(ReplicatedStorage.Types.Enums.ERarities)
local Brew = require(script.Brew)
local Flight = require(script.Flight)
local Mutate = require(script.Mutate)
local Parts = require(script.Parts)
local Potions = require(script.Potions)
local Screen = require(script.Screen)
local Tray = require(script.Tray)
local Types = require(script.Types)

local ServerNetworkMutation = NetworkMeta.Server.Mutation
local ClientNetworkMutation = NetworkMeta.Client.Mutation
local LocalPlayer = Players.LocalPlayer
local source = vide.source
local create = vide.create

local Tune = table.freeze({
	-- Above the lobby's HUD, under the settings screen.
	DISPLAY_ORDER = 5,
	-- It is drawn this long after it is shut, for its way out.
	LEAVE_SECONDS = 0.45,
	-- How long the clock keeps ticking after a stamp: the longest gesture is shorter.
	MOTION_SECONDS = 2.2,
	-- The sounds of a landing, by rarity, and the reveal layered on the rarer ones.
	PICK_SOUNDS = {
		[ERarities.Common] = "PickCommon",
		[ERarities.Uncommon] = "PickUncommon",
		[ERarities.Rare] = "PickRare",
		[ERarities.Epic] = "PickEpic",
		[ERarities.Legendary] = "PickLegendary",
		[ERarities.Mythic] = "PickMythic",
	},
	REVEAL_SOUNDS = {
		[ERarities.Epic] = "RevealEpic",
		[ERarities.Legendary] = "RevealLegendary",
		[ERarities.Mythic] = "RevealMythic",
	},
	-- Each climb step's tick is this much higher than the last, and each landing's in a stream.
	TICK_STEP = 0.1,
	-- A batch: each card's opening ticks this much higher than the one before, its climb's ticks a step under it.
	CARD_TICK_STEP = 0.06,
	LANDING_STEP = 0.03,
	LANDING_STEPS = 12,
	-- While BREW can go, the light crosses it this often.
	CALL_PERIOD = 3.2,
	-- A potion thrown out of the flask, and a soul out of a dissolved card: their size, and how far apart they leave.
	POTION_SIZE = 64,
	SOUL_SIZE = 34,
	SOUL_STAGGER = 0.02,
	-- A dissolved potion throws up to this many souls of each kind it gives back, this far into its crunch, from its
	-- card (or the grid's middle, scrolled out of sight).
	SOULS_PER_KIND = 2,
	SOULS_LEAVE = 0.6,
	GRID_MIDDLE = Vector2.new(960, 740),
	-- A flight is let go this long after it lands, and a dissolved card waits this long for the server to take it.
	LANDED_KEEP = 0.5,
	LEAVING_TIMEOUT = 5,
	-- Brews bought are brewed once Roblox's dialog is closed, or this long after they arrived if it never says so (the
	-- shop's receipt waits as long).
	MAX_DIALOG_WAIT = 10,
	-- Where brewed potions and souls land (the tabs' glyphs); they leave from the result card's flask (Mutate.FlaskAt).
	MUTATE_TAB = Vector2.new(387, 224),
	POTIONS_TAB = Vector2.new(640, 224),
})

local MutationController = {}

local SLOT_KINDS = table.freeze({ Free = 1, Pass = 2, Gems = 3 })

local state: Types.TLabState = {
	Scale = source(1),
	Now = source(os.clock()),
	IsOpen = source(false),
	ToggledAt = source(-math.huge),
	Tab = source(1),
	TabAt = source(-math.huge),
	Discovered = source({} :: { [number]: boolean }),
	Energy = source({} :: { [number]: number }),
	Potions = source({} :: { Types.TPotion }),
	Equipped = source({} :: { number }),
	Slots = source({ { Kind = SLOT_KINDS.Free, IsOpen = true } } :: { Types.TSlot }),
	BrewsLeft = source(0),
	BrewsPerDay = source(PotionsCore.BREWS_PER_DAY),
	BrewsBackAt = source(0),
	Luck = source(1),
	Found = source({} :: { [number]: Types.TFound }),
	Gems = source(0),
	CanBuyBrew = source(false),
	Picks = source({} :: { number }),
	PickedAt = source({} :: { [number]: number }),
	BrewCount = source(1),
	IsMenuOpen = source(false),
	MenuAt = source(-math.huge),
	CalledAt = source(-math.huge),
	BrewAt = source(-math.huge),
	Asked = source(1),
	AnsweredAt = source(math.huge),
	BrewedId = source(0),
	Shown = source(nil :: Types.TPotion?),
	IsShownNew = source(false),
	Batch = source({} :: { Types.TPotion }),
	Flights = source({} :: { Types.TFlight }),
	LandedAt = source({ -math.huge, -math.huge }),
	Unseen = source(0),
	IsDissolving = source(false),
	DissolveAt = source(-math.huge),
	DissolvePicks = source({} :: { [number]: boolean }),
	Leaving = source({} :: { [number]: { Potion: Types.TPotion, At: number } }),
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

-- os.clock until which Now keeps ticking.
local motionUntil = -math.huge
-- Sounds still to play: each one's moment, group, name and speed.
local dueSounds: { { At: number, Group: string, Name: string, Speed: number? } } = {}
-- What the next Brewed answers: the picks it was asked with.
local isAsking = false
-- Brews bought from BREW, brewed once they have arrived and Roblox's dialog is down: whether one is awaited, whether
-- the dialog is still up (its confirmation not yet pressed), and when the brews arrived.
local isAwaitingPurchase = false
local isPrompting = false
local grantedAt = math.huge
-- Every product that sells brews (PotionsCore.BREW_PRODUCTS), to know their prompts when they close.
local brewProducts: { [number]: boolean } = {}
for _, productId in PotionsCore.BREW_PRODUCTS do
	if productId ~= 0 then brewProducts[productId] = true end
end
local nextClockAt = 0
local nextCallAt = 0
-- The flights already landed, so each ticks once, and how many have in this stream of them.
local landed: { [Types.TFlight]: boolean } = {}
local landedCount = 0
local random = Random.new()

-- Whether the screen is up. Reads a vide source, so a view that calls it follows it.
function MutationController.IsOpen(): boolean
	return state.IsOpen()
end

-- What the LAB card wears: a brew could go now (a brew left, and two kinds with enough energy). Reads vide sources.
function MutationController.CanBrew(): boolean
	if state.BrewsLeft() <= 0 then return false end
	local enough = 0
	local energy = state.Energy()
	for _, enemy in PotionsCore.ENERGIES do
		if (energy[enemy.Id] or 0) >= (enemy.Energy :: any).Cost then
			enough += 1
		end
	end
	return enough >= 2
end

-- The recipes found (potion data Id -> { Brewed, IsNew }), for the index's POTIONS page. Reads a vide source.
function MutationController.Found(): { [number]: Types.TFound }
	return state.Found()
end

-- The index has shown these recipes found: they are not new any more.
function MutationController.MarkSeen(recipeIds: { number })
	if #recipeIds == 0 then return end
	local found = table.clone(state.Found())
	for _, recipeId in recipeIds do
		local entry = found[recipeId]
		if entry then found[recipeId] = { Brewed = entry.Brewed, IsNew = false } end
	end
	state.Found(found)
	ClientNetworkMutation.Seen.Fire(recipeIds)
end

local function stir(seconds: number)
	motionUntil = math.max(motionUntil, os.clock() + seconds)
end

local function refuse(who: string, text: string)
	local now = os.clock()
	vide.batch(function()
		state.Refused(who)
		state.RefusedAt(now)
		state.RefusedText(text)
	end)
	stir(3)
	SoundsCore.PlayUINamed("UI.UpgradePick", "Denied")
end

local function schedule(at: number, group: string, name: string, speed: number?)
	table.insert(dueSounds, { At = at, Group = group, Name = name, Speed = speed })
end

-- A brew done or let go: the card goes back to showing what the picks make.
local function settleBrew()
	vide.batch(function()
		state.BrewAt(-math.huge)
		state.AnsweredAt(math.huge)
		state.Shown(nil)
		state.IsShownNew(false)
		state.Batch({})
	end)
end

local function setMenu(isOpen: boolean)
	if state.IsMenuOpen() == isOpen then return end
	vide.batch(function()
		state.IsMenuOpen(isOpen)
		state.MenuAt(os.clock())
	end)
	stir(0.6)
end

local function setDissolving(isDissolving: boolean)
	if state.IsDissolving() == isDissolving then return end
	vide.batch(function()
		state.IsDissolving(isDissolving)
		state.DissolveAt(os.clock())
		state.DissolvePicks({})
	end)
	stir(0.6)
end

function MutationController.Open()
	if state.IsOpen() then return end
	vide.batch(function()
		state.IsOpen(true)
		state.ToggledAt(os.clock())
		state.Clock(os.time())
	end)
	stir(Tune.MOTION_SECONDS)
	SoundsCore.SetMuffled("Mutation", true)
	BlurController.SetBlurred("Mutation", true)
end

function MutationController.Close()
	if not state.IsOpen() then return end
	isAwaitingPurchase = false
	setMenu(false)
	vide.batch(function()
		state.IsOpen(false)
		state.ToggledAt(os.clock())
	end)
	stir(Tune.MOTION_SECONDS)
	SoundsCore.SetMuffled("Mutation", false)
	BlurController.SetBlurred("Mutation", false)
end

local function pickTab(tab: number)
	if state.Tab() == tab then return end
	setMenu(false)
	setDissolving(false)
	vide.batch(function()
		state.Tab(tab)
		state.TabAt(os.clock())
		if tab == 2 then state.Unseen(0) end
	end)
	stir(Tune.MOTION_SECONDS)
	SoundsCore.PlayClick()
end

local function setPicks(picks: { number }, pickedId: number?)
	if not Brew.IsBusy(state) and state.Shown() then settleBrew() end
	local now = os.clock()
	vide.batch(function()
		state.Picks(picks)
		if pickedId then
			local pickedAt = table.clone(state.PickedAt())
			pickedAt[pickedId] = now
			state.PickedAt(pickedAt)
		end
	end)
	stir(Tune.MOTION_SECONDS)
end

local function potionById(potionId: number): Types.TPotion?
	for _, potion in state.Potions() do
		if potion.Id == potionId then return potion end
	end
	return nil
end

-- Puts `planned` in the air after what is already flying (as many as the pool draws), and returns when the last of
-- them lands, `since` if none does.
local function launch(planned: { Types.TFlight }, since: number): number
	local flights = table.clone(state.Flights())
	local lastLanding = since
	for _, flight in planned do
		if #flights >= Flight.POOL then break end
		table.insert(flights, flight)
		lastLanding = math.max(lastLanding, flight.LandAt)
	end
	state.Flights(flights)
	return lastLanding
end

-- The picked potions crunch where they stand and throw their souls into the MUTATE tab. Drawn at once on the guess;
-- the server's Dissolved confirms it, or a refusal says so and the cards come back.
local function dissolvePicked()
	local picks = state.DissolvePicks()
	local equipped = state.Equipped()
	local now = os.clock()
	local throwAt = now + Potions.CRUNCH * Tune.SOULS_LEAVE
	local leaving = table.clone(state.Leaving())
	local ids = {}
	local total = 0
	local lastLanding = now
	for _, potion in state.Potions() do
		if not picks[potion.Id] or table.find(equipped, potion.Id) then continue end
		table.insert(ids, potion.Id)
		leaving[potion.Id] = { Potion = potion, At = now }
		local recipe = DataCore.Potions.ById[potion.Recipe]
		local looks: { Types.TFlightLook } = {}
		for index, amount in PotionsCore.Refund(recipe, potion.Rarity) do
			total += amount
			local _, kind = Parts.Energy(recipe.Energies[index])
			for _ = 1, math.min(amount, Tune.SOULS_PER_KIND) do
				table.insert(looks, {
					Picture = EIcons.Soul,
					Color = kind.Color,
					Size = Tune.SOUL_SIZE,
					Tab = 1,
					PotionId = 0,
				})
			end
		end
		local locate = state.Locate[potion.Id]
		local from = (if locate then locate() else nil) or Tune.GRID_MIDDLE
		local planned = Flight.Plan(looks, from, Tune.MUTATE_TAB, throwAt, Tune.SOUL_STAGGER, random)
		lastLanding = math.max(lastLanding, launch(planned, now))
	end

	if #ids == 0 then
		refuse("Dissolve", "PICK POTIONS THAT ARE NOT IN A SLOT")
		return
	end
	vide.batch(function()
		state.Leaving(leaving)
		state.IsDissolving(false)
		state.DissolveAt(now)
		state.DissolvePicks({})
		state.Gained(`+{total} SOULS`)
		state.GainedAt(lastLanding)
	end)
	stir(lastLanding + 2 - now)
	SoundsCore.PlayUINamed("UI.UpgradePick", "Reroll")
	ClientNetworkMutation.Dissolve.Fire(ids)
end

local actions: Types.TLabActions = {
	Close = MutationController.Close,
	PickTab = pickTab,
	PickEnergy = function(enemyId: number)
		if Brew.IsBusy(state) then return end
		local enemy = DataCore.Enemies.ById[enemyId]
		local isKnown = state.Discovered()[enemyId] or (state.Energy()[enemyId] or 0) > 0
		if not isKnown then
			refuse(`Energy{enemyId}`, "KILL ONE IN A MATCH TO UNLOCK ITS ENERGY")
			return
		end
		local picks = table.clone(state.Picks())
		local at = table.find(picks, enemyId)
		if at then
			table.remove(picks, at)
			setPicks(picks)
			SoundsCore.PlayClick()
			return
		end
		-- A third pick takes the place of the oldest.
		if #picks >= 2 then table.remove(picks, 1) end
		table.insert(picks, enemyId)
		setPicks(picks, enemyId)
		SoundsCore.PlayUINamed("UI.UpgradePick", "Deal")
		if enemy and enemy.Sounds and enemy.Sounds.Idle then
			SoundsCore.PlayUINamed(enemy.Sounds.Group, enemy.Sounds.Idle)
		end
	end,
	DropPick = function(index: number)
		if Brew.IsBusy(state) then return end
		local picks = table.clone(state.Picks())
		if not picks[index] then return end
		table.remove(picks, index)
		setPicks(picks)
		SoundsCore.PlayClick()
	end,
	Brew = function()
		setMenu(false)
		local mode = Mutate.Mode(state)
		if mode == "Buy" then
			isAwaitingPurchase = true
			isPrompting = true
			grantedAt = math.huge
			MarketplaceService:PromptProductPurchase(LocalPlayer, PotionsCore.BREW_PRODUCTS[Mutate.BuyCount(state)])
			return
		end
		local blocker = Mutate.Blocker(state)
		if blocker or isAsking then
			if blocker and not Brew.IsBusy(state) then refuse("Brew", blocker) end
			return
		end
		local picks = state.Picks()
		local count = Mutate.Count(state)
		local now = os.clock()
		isAsking = true
		vide.batch(function()
			state.Shown(nil)
			state.IsShownNew(false)
			state.BrewedId(0)
			state.AnsweredAt(math.huge)
			state.Asked(count)
			state.BrewAt(now)
		end)
		stir(Brew.WINDUP + 4)
		SoundsCore.PlayUINamed("Craft", "Forge")
		ClientNetworkMutation.Brew.Fire(picks[1], picks[2], count)
	end,
	SetMenu = function(isOpen: boolean)
		setMenu(isOpen)
		SoundsCore.PlayClick()
	end,
	PickCount = function(count: number)
		state.BrewCount(count)
		setMenu(false)
		stir(0.6)
		SoundsCore.PlayUINamed("UI.UpgradePick", "Deal")
	end,
	Dissolve = function()
		if not state.IsDissolving() then
			setDissolving(true)
			SoundsCore.PlayClick()
			return
		end
		dissolvePicked()
	end,
	CancelDissolve = function()
		setDissolving(false)
		SoundsCore.PlayClick()
	end,
	TogglePotion = function(potionId: number)
		local potion = potionById(potionId)
		if not potion then return end
		local now = os.clock()
		if state.IsDissolving() then
			if table.find(state.Equipped(), potionId) then
				refuse(`Potion{potionId}`, "TAKE IT OUT OF ITS SLOT TO DISSOLVE IT")
				return
			end
			local picks = table.clone(state.DissolvePicks())
			picks[potionId] = if picks[potionId] then nil else true
			state.DissolvePicks(picks)
			stir(1)
			if picks[potionId] then
				SoundsCore.PlayUINamed("UI.UpgradePick", "Deal")
			else
				SoundsCore.PlayClick()
			end
			return
		end
		local isIn = table.find(state.Equipped(), potionId) ~= nil
		if not isIn then
			local open = 0
			for _, slot in state.Slots() do
				if slot.IsOpen then
					open += 1
				end
			end
			if #state.Equipped() >= open then
				refuse(`Potion{potionId}`, "YOUR SLOTS ARE FULL: TAKE ONE OUT FIRST")
				return
			end
		end
		-- Drawn at once; the server's Sync confirms it, or puts it back.
		local equipped = table.clone(state.Equipped())
		if isIn then
			table.remove(equipped, table.find(equipped, potionId) :: number)
			ClientNetworkMutation.Unequip.Fire(potionId)
			SoundsCore.PlayUINamed("UI", "ClickHud")
		else
			table.insert(equipped, potionId)
			ClientNetworkMutation.Equip.Fire(potionId)
			SoundsCore.PlayUINamed("UI.UpgradePick", Tune.PICK_SOUNDS[potion.Rarity])
		end
		vide.batch(function()
			state.Equipped(equipped)
			state.SlottedId(potionId)
			state.SlottedAt(now)
		end)
		stir(1)
	end,
	BuySlot = function(kind: number)
		local index = 0
		for at, slot in state.Slots() do
			if slot.Kind == kind then index = at end
		end
		if kind == SLOT_KINDS.Gems then
			if state.Gems() < PotionsCore.GEM_SLOT_PRICE then
				refuse(
					`Slot{index}`,
					`NOT ENOUGH GEMS: THIS SLOT COSTS {Components.Commas(PotionsCore.GEM_SLOT_PRICE)}`
				)
				return
			end
			ClientNetworkMutation.BuySlot.Fire()
			SoundsCore.PlayUINamed("UI", "WeaponUpgrade")
			return
		end
		local passId = ShopCore.ByName.PotionSlot.GamePassId
		if passId == 0 then
			refuse(`Slot{index}`, "THE 3RD SLOT IS NOT ON SALE YET")
			return
		end
		MarketplaceService:PromptGamePassPurchase(LocalPlayer, passId)
	end,
	Stir = stir,
}

local function updateScale()
	local viewport = Workspace.CurrentCamera.ViewportSize
	local design = Screen.DESIGN
	state.Scale(math.max(math.min(viewport.Y / design.Y, viewport.X / design.X), 0.01))
end

local function playDueSounds(now: number)
	for index = #dueSounds, 1, -1 do
		local due = dueSounds[index]
		if now < due.At then continue end
		table.remove(dueSounds, index)
		if state.IsOpen() then SoundsCore.PlayUINamed(due.Group, due.Name, due.Speed) end
	end
end

-- The brew's beats from its answer: a tick for each rarity the climb passes, the landing in the rarity's voice, and
-- its potions thrown out of the flask into the POTIONS tab (Flight), rarest last off the card.
-- A batch's beats: each card's climb ticking up to it, its opening a tick higher than the last card's and its landing
-- in its rarity's voice; then each potion thrown out of its own card into the POTIONS tab, one after another.
local function scheduleBatch(times: Brew.TTimes, cards: { Brew.TCard })
	local count = #cards
	for index, card in cards do
		local pitch = 1 + Tune.CARD_TICK_STEP * (index - 1)
		for step = ERarities.Common + 1, card.Rarity do
			local at = card.StartAt + card.Step * (step - ERarities.Common - 1)
			schedule(at, "UI.UpgradePick", "Tick", pitch + 0.5 * Tune.TICK_STEP * (step - 1))
		end
		schedule(card.LandAt, "UI.UpgradePick", Tune.PICK_SOUNDS[card.Rarity])
		local reveal = Tune.REVEAL_SOUNDS[card.Rarity]
		if reveal then schedule(card.LandAt, "UI.UpgradePick", reveal) end
	end
	schedule(times.FlyAt, "UI.UpgradePick", "Deal")

	local lastLanding = times.FlyAt
	for index, potion in state.Batch() do
		local look: Types.TFlightLook = {
			Picture = EIcons.PotionBottle,
			Color = Parts.Rarity(potion.Rarity).Accent,
			Size = Tune.POTION_SIZE,
			Tab = 2,
			PotionId = potion.Id,
		}
		local at = times.FlyAt + Brew.FLY_STAGGER * (index - 1)
		local planned = Flight.Plan({ look }, Tray.CardAt(index, count), Tune.POTIONS_TAB, at, 0, random)
		lastLanding = math.max(lastLanding, launch(planned, at))
	end
	stir(lastLanding + 0.8 - os.clock())
end

local function scheduleReveal()
	local times = Brew.Times(state)
	if not times then return end
	local cards = times.Cards
	if cards then
		scheduleBatch(times, cards)
		return
	end
	for step = ERarities.Common + 1, times.Rarity do
		schedule(Brew.StepMoment(times, step), "UI.UpgradePick", "Tick", 1 + Tune.TICK_STEP * step)
	end
	schedule(times.LandAt, "UI.UpgradePick", Tune.PICK_SOUNDS[times.Rarity])
	local reveal = Tune.REVEAL_SOUNDS[times.Rarity]
	if reveal then schedule(times.LandAt, "UI.UpgradePick", reveal) end
	schedule(times.FlyAt, "UI.UpgradePick", "Deal")

	local looks: { Types.TFlightLook } = {}
	for index, potion in state.Batch() do
		looks[index] = {
			Picture = EIcons.PotionBottle,
			Color = Parts.Rarity(potion.Rarity).Accent,
			Size = Tune.POTION_SIZE,
			Tab = 2,
			PotionId = potion.Id,
		}
	end
	local planned = Flight.Plan(looks, Mutate.FlaskAt(), Tune.POTIONS_TAB, times.FlyAt, Brew.FLY_STAGGER, random)
	stir(launch(planned, times.FlyAt) + 0.8 - os.clock())
end

-- Every flight that lands ticks once, a step higher for each before it in the stream, and punches its tab; a potion
-- counts on the POTIONS badge. Flights long landed are let go, and the stream ends with the last of them.
local function landFlights(now: number)
	local flights = state.Flights()
	if #flights == 0 then return end

	local landedAt = state.LandedAt()
	local hasLanded = false
	local potions = 0
	local isStale = false
	for _, flight in flights do
		if now >= flight.LandAt + Tune.LANDED_KEEP then isStale = true end
		if landed[flight] or now < flight.LandAt then continue end
		landed[flight] = true
		landedCount += 1
		if not hasLanded then
			hasLanded = true
			landedAt = table.clone(landedAt)
		end
		landedAt[flight.Tab] = now
		if flight.PotionId ~= 0 then
			potions += 1
		end
	end
	if hasLanded then
		vide.batch(function()
			state.LandedAt(landedAt)
			if potions > 0 and state.Tab() ~= 2 then state.Unseen(state.Unseen() + potions) end
		end)
		local step = math.min(landedCount, Tune.LANDING_STEPS)
		SoundsCore.PlayUINamed("UI.UpgradePick", "Tick", 1 + Tune.LANDING_STEP * step)
	end
	if not isStale then return end

	local kept = table.create(#flights)
	for _, flight in flights do
		if now < flight.LandAt + Tune.LANDED_KEEP then
			table.insert(kept, flight)
		else
			landed[flight] = nil
		end
	end
	if #kept == 0 then landedCount = 0 end
	state.Flights(kept)
end

-- Whether a dissolved card is done: crunched and its potion taken by the server, or never taken and put back.
local function isLeft(potionId: number, at: number, now: number): boolean
	local age = now - at
	if age < Potions.CRUNCH then return false end
	return age > Tune.LEAVING_TIMEOUT or potionById(potionId) == nil
end

-- Lets go of the dissolved cards that are done; the rest stay drawn.
local function releaseLeaving(now: number)
	local leaving = state.Leaving()
	local isAnyLeft = false
	for potionId, entry in leaving do
		if not isLeft(potionId, entry.At, now) then continue end
		isAnyLeft = true
		break
	end
	if not isAnyLeft then return end

	local kept = {}
	for potionId, entry in leaving do
		if not isLeft(potionId, entry.At, now) then kept[potionId] = entry end
	end
	state.Leaving(kept)
end

-- Brews just bought are brewed once they have arrived and Roblox's dialog is down, as the shop's receipt waits for it:
-- the brew never starts under the dialog's confirmation.
local function brewBought(now: number)
	if grantedAt == math.huge then return end
	if isPrompting and now - grantedAt < Tune.MAX_DIALOG_WAIT then return end
	if not state.IsOpen() or Mutate.Mode(state) ~= "Brew" then return end
	isAwaitingPurchase = false
	isPrompting = false
	actions.Brew()
end

MutationController.OnStart = function()
	vide.mount(function()
		local isDrawn = vide.derive(function(): boolean
			return state.IsOpen() or state.Now() - state.ToggledAt() < Tune.LEAVE_SECONDS
		end)

		return create("ScreenGui")({
			Name = "Mutation",
			ResetOnSpawn = false,
			IgnoreGuiInset = true,
			ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			DisplayOrder = Tune.DISPLAY_ORDER,
			Enabled = isDrawn,
			create("Frame")({
				Name = "Root",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(Screen.DESIGN.X, Screen.DESIGN.Y),
				BackgroundTransparency = 1,
				create("UIScale")({ Scale = state.Scale }),
				-- Built only while drawn: shut, its rigs and their clips are gone too.
				vide.show(isDrawn, function()
					local pieces = Screen.Build(state, actions)
					vide.cleanup(function()
						for _, piece in pieces do
							if typeof(piece) == "Instance" then piece:Destroy() end
						end
					end)
					return pieces
				end),
			}),
		})
	end, LocalPlayer:WaitForChild("PlayerGui"))

	-- Now is written only while something moves, so a screen at rest, open or shut, redraws nothing.
	RunService.PreRender:Connect(function()
		local now = os.clock()
		-- While BREW can go, the light crosses it now and then: its clock wakes for the crossing.
		if state.IsOpen() and state.Tab() == 1 and now >= nextCallAt then
			nextCallAt = now + Tune.CALL_PERIOD
			if Mutate.Mode(state) == "Brew" then
				state.CalledAt(now)
				stir(1)
			end
		end
		if now < motionUntil then
			state.Now(now)
			landFlights(now)
			releaseLeaving(now)
		end
		if #dueSounds > 0 then playDueSounds(now) end
		if isAwaitingPurchase then brewBought(now) end
		if state.IsOpen() and now >= nextClockAt then
			nextClockAt = now + 1
			state.Clock(os.time())
		end
	end)

	local camera = Workspace.CurrentCamera
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	updateScale()

	state.Gems(ProfileController.Gems)
	ProfileController.OnChanged:Connect(function()
		state.Gems(ProfileController.Gems)
	end)

	task.spawn(function()
		local ok, policy = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, LocalPlayer)
		if not ok or policy.ArePaidRandomItemsRestricted then return end
		state.CanBuyBrew(true)
	end)
end

ServerNetworkMutation.Sync.On(function(lab)
	local discovered, energy = {}, {}
	for _, enemyId in lab.Discovered do
		discovered[enemyId] = true
	end
	for index, enemyId in lab.EnergyIds do
		energy[enemyId] = lab.EnergyCounts[index]
	end
	local potions = table.create(#lab.PotionIds)
	for index, potionId in lab.PotionIds do
		potions[index] = {
			Id = potionId,
			Recipe = lab.PotionRecipes[index],
			Rarity = lab.PotionRarities[index],
			Matches = lab.PotionMatches[index],
		}
	end
	local slots = table.create(#lab.SlotKinds)
	for index, kind in lab.SlotKinds do
		slots[index] = { Kind = kind, IsOpen = lab.SlotsOpen[index] }
	end
	local found = {}
	for index, recipeId in lab.FoundIds do
		found[recipeId] = { Brewed = lab.FoundCounts[index], IsNew = lab.FoundNew[index] }
	end

	vide.batch(function()
		state.Discovered(discovered)
		state.Energy(energy)
		state.Potions(potions)
		state.Equipped(lab.Equipped)
		state.Slots(slots)
		state.BrewsLeft(lab.BrewsLeft)
		state.BrewsPerDay(lab.BrewsPerDay)
		state.BrewsBackAt(os.time() + lab.SecondsLeft)
		state.Luck(lab.Luck)
		-- A recipe the index has shown found this session stays shown, whatever an older Sync says.
		local seen = state.Found()
		for recipeId, entry in found do
			local was = seen[recipeId]
			if was and not was.IsNew then entry.IsNew = false end
		end
		state.Found(found)
	end)

	if isAwaitingPurchase and grantedAt == math.huge and lab.BrewsLeft > 0 then
		grantedAt = os.clock()
		brewBought(grantedAt)
	end
end)

-- Every Brew is answered: the potions made (the Sync before it carried them), or none refused. The card shows the
-- rarest; it is new when this batch was the recipe's first.
ServerNetworkMutation.Brewed.On(function(potionIds: { number })
	isAsking = false
	local batch = {}
	for _, potionId in potionIds do
		local potion = potionById(potionId)
		if potion then table.insert(batch, potion) end
	end
	if #batch == 0 then
		settleBrew()
		if #potionIds == 0 then refuse("Brew", "THE BREW FIZZLED: CHECK YOUR SOULS AND BREWS") end
		return
	end

	table.sort(batch, function(a, b)
		if a.Rarity ~= b.Rarity then return a.Rarity < b.Rarity end
		return a.Id < b.Id
	end)
	local best = batch[#batch]
	local found = state.Found()[best.Recipe]
	vide.batch(function()
		state.BrewedId(best.Id)
		state.Shown(best)
		state.Batch(batch)
		state.IsShownNew(found ~= nil and found.Brewed == #batch)
		state.AnsweredAt(os.clock())
	end)
	scheduleReveal()
end)

-- Every Dissolve is answered: what went (the cards already crunched on the guess), or none when it was refused.
ServerNetworkMutation.Dissolved.On(function(potionIds: { number })
	if #potionIds > 0 then return end
	state.Leaving({})
	state.GainedAt(-math.huge)
	refuse("Dissolve", "THOSE POTIONS COULD NOT BE DISSOLVED")
end)

MarketplaceService.PromptProductPurchaseFinished:Connect(
	function(userId: number, productId: number, isPurchased: boolean)
		if userId ~= LocalPlayer.UserId or not brewProducts[productId] then return end
		isPrompting = false
		if not isPurchased then
			isAwaitingPurchase = false
			return
		end
		brewBought(os.clock())
	end
)

return Ignis.Register(MutationController)
