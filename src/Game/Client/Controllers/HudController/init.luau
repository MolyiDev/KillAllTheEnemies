-- The arena HUD, the designer's In-Game HUD (UIMatt.md). This file owns every vide source and writes them once a frame
-- inside one batch; a source ignores a write of the value it already holds, so a quiet frame touches no Instance. The
-- pieces (Wave, Items, Upgrades, Shop, Hotbar, Overhead, Squad, Overlays) only read sources and call actions, which
-- are requests to the controllers: the HUD decides nothing. Squad and Settings are icons on Roblox's top bar
-- (TopbarPlus).
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local vide = require(ReplicatedStorage.Packages.vide)
local CoinsController = require(script.Parent.CoinsController)
local DefensePlacementController = require(script.Parent.DefensePlacementController)
local EnemiesController = require(script.Parent.EnemiesController)
local HealthController = require(script.Parent.HealthController)
local MatchController = require(script.Parent.MatchController)
local WeaponController = require(script.Parent.WeaponController)
-- Through PlayerScripts, the copy that runs: requiring the StarterPlayer one loads a second ProfileController, which
-- Ignis refuses as already registered (the first playtest of the HUD).
local ProfileController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.ProfileController)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local GunsCore = require(ReplicatedStorage.GlobalShared.Core.GunsCore)
local RoundCore = require(ReplicatedStorage.Shared.Core.RoundCore)
local TimeCore = require(ReplicatedStorage.Shared.Core.TimeCore)
local TopbarPlus = require(ReplicatedStorage.GlobalShared.TopbarPlus)
local Hotbar = require(script.Hotbar)
local Icons = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Icons)
local Items = require(script.Items)
local Overhead = require(script.Overhead)
local Overlays = require(script.Overlays)
local Shop = require(script.Shop)
local Squad = require(script.Squad)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local Topbar = require(script.Topbar)
local Upgrades = require(script.Upgrades)
local Wave = require(script.Wave)
local WeaponUpgrade = require(script.WeaponUpgrade)
local Types = require(script.Types)
local EProducts = require(ReplicatedStorage.Types.Enums.EProducts)
local TCharacter = require(ReplicatedStorage.Types.TCharacter)
local TCharacterEvents = require(ReplicatedStorage.Types.Events.TCharacterEvents)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)

local LocalPlayer = Players.LocalPlayer
local ENEMIES = DataCore.Enemies.ById
local ALL_ENEMIES = DataCore.Enemies.All
local DEFENSES = DataCore.Defenses.ById
local LADDER = GunsCore.LADDER
local source = vide.source
local create = vide.create

local Tune = table.freeze({
	-- Gold's counter pops as Gold comes in, and goes red when a purchase is refused for want of it.
	GOLD_PULSE_SECONDS = 0.35,
	GOLD_DENIED_SECONDS = 0.5,
	-- Exponential rate the Gold counter rolls toward the real amount at (GDD 17: a counter animation).
	GOLD_ROLL_RATE = 10,
	-- The red edge on a hit: its peak and how long it takes to fade (GDD 9: fade quickly).
	HURT_PEAK = 0.55,
	HURT_SECONDS = 0.5,
	-- Under this share of health the edge holds a little red, breathing.
	LOW_HEALTH_SHARE = 0.3,
	LOW_HEALTH_EDGE = 0.16,
	-- The health bar's chip of what was lost waits, then drains at this share of max health a second.
	TRAIL_HOLD_SECONDS = 0.35,
	TRAIL_DRAIN_RATE = 0.9,
	-- The camera this close to the head is first person (Roblox's own zoom-in puts it at the head).
	FIRST_PERSON_STUDS = 1.5,
	-- More enemies than this and NUKE ALL asks to be bought; under this share of health, HEAL ALL does.
	NUKE_PROMPT_ENEMIES = 30,
	HEAL_PROMPT_SHARE = 0.4,
	-- How long Now keeps ticking after anything starts a timed gesture: the longest one is shorter.
	MOTION_SECONDS = 1.6,
	-- SKIP WAVE's cooldown fill moves in this many steps, about one a pixel across the button.
	SKIP_FILL_STEPS = 300,
})

local HudController = {}

local defenses = table.create(#DataCore.Defenses.All)
for index, data in DataCore.Defenses.All do
	defenses[index] = {
		Key = DefensePlacementController.KEYS[index],
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

local state: Types.THudState = {
	Scale = source(1),
	Now = source(os.clock()),
	Phase = source("Waiting" :: Types.TPhase),
	PhaseAt = source(-math.huge),
	PreviousPhase = source("Waiting" :: Types.TPhase),
	Round = source(0),
	Countdown = source(0),
	CountdownAt = source(-math.huge),
	IsBossRound = source(false),
	Votes = source(0),
	VotesNeeded = source(0),
	CanSkip = source(false),
	SkipProgress = source(0),
	SkipOpenedAt = source(-math.huge),
	VotesAt = source(-math.huge),
	IsAutoSkip = source(false),
	BossName = source(""),
	BossHealth = source(0),
	BossMaxHealth = source(0),
	NextBossName = source(""),
	NextBossRound = source(0),
	Gold = source(0),
	GoldShown = source(0),
	GoldPulse = source(0),
	GoldDenied = source(0),
	Health = source(0),
	MaxHealth = source(0),
	TrailHealth = source(0),
	IsDown = source(false),
	Head = source(nil :: BasePart?),
	IsFirstPerson = source(false),
	Vignette = source(0),
	Defenses = defenses,
	Squad = source(table.freeze({}) :: { Types.TSquadMember }),
	IsSquadOpen = source(false),
	SquadToggledAt = source(-math.huge),
	RunSeconds = source(0),
	EnemyCount = source(0),
	IsNukePrompted = source(false),
	IsHealPrompted = source(false),
	Gun = source(nil :: any),
	GunModel = source(nil :: Model?),
	GunAt = source(-math.huge),
	Weapon = {
		Offer = source(LADDER[2] :: GunsCore.TLadderStep?),
		Held = source(LADDER[1] :: GunsCore.TLadderStep?),
		Step = source(1),
		CanAfford = source(false),
		Clock = source(math.huge),
		BoughtAt = source(-math.huge),
		LandAt = source(-math.huge),
		AskedAt = source(-math.huge),
		DeniedAt = source(-math.huge),
		ReadyAt = source(-math.huge),
	},
	IsReviveOffered = source(false),
	CanRevive = EProducts.Revive ~= 0,
	Keys = table.freeze({
		Skip = MatchController.SKIP_KEY,
		Turn = DefensePlacementController.TURN_KEY,
		Upgrade = WeaponController.UPGRADE_KEY,
	}),
	RoundsCleared = source(0),
	RunGold = source(0),
	RunGems = source(0),
	ReturnIn = source(0),
}

local squadMembers: { [Player]: Types.TSquadMember } = {}
-- Every other player's humanoid, from OnCharacterAdded (the local player's health is HealthController's).
local squadHumanoids: { [Player]: Humanoid } = {}
local squadIcon: any = nil
-- os.clock until which Now keeps ticking (Tune.MOTION_SECONDS past the last gesture that started).
local motionUntil = -math.huge
local runStartedAt = 0
local lastCountdown = 0
local lastVotes = 0
local wasSkipOpen = false
local lastGun: any = nil
-- WeaponController's stamps as last seen, and whether the offer was affordable last frame.
local lastUpgradedAt = -math.huge
local lastAskedAt = -math.huge
local lastDeniedAt = -math.huge
local wasAffordable = false
-- os.clock until which the weapon card or its show is moving (state.Weapon.Clock runs till then).
local weaponUntil = -math.huge
-- The Tool the local character holds, kept by its ChildAdded / ChildRemoved.
local heldModel: Model? = nil
local selfHumanoid: Humanoid? = nil
local trailHealth = 0
local goldShown = 0
local goldTarget = 0
local lastPendingGold = 0
local goldInAt = -math.huge
local goldDeniedAt = -math.huge
-- The round a boss was seen in, so a boss round whose boss is dead points at the next one.
local bossSeenRound = 0
local nextBossRound, nextBossName = -1, ""
-- The frame's dt for updateFrame, so the per-frame batch passes a function that captures nothing.
local frameDt = 0

local function fade(since: number, seconds: number, now: number): number
	return math.clamp(1 - (now - since) / seconds, 0, 1)
end

-- Stamps a gesture's start and keeps Now ticking for it.
local function stamp(at: vide.Source<number>, now: number)
	at(now)
	motionUntil = now + Tune.MOTION_SECONDS
end

local function updateRound(now: number, gameNow: number)
	local phase: Types.TPhase = if MatchController.IsEnded
		then "Ended"
		elseif MatchController.IsPreparing then "Preparing"
		elseif MatchController.IsRunning and MatchController.Round > 0 then "Fighting"
		else "Waiting"
	local previous = state.Phase()
	if phase ~= previous then
		state.PreviousPhase(previous)
		stamp(state.PhaseAt, now)
		if previous == "Waiting" then runStartedAt = now end
	end

	local round = MatchController.Round
	state.Phase(phase)
	state.Round(round)
	state.IsBossRound(RoundCore.IsBossRound(round))
	state.RunSeconds(if phase == "Waiting" then 0 else math.floor(now - runStartedAt))
	if MatchController.Votes ~= lastVotes then
		lastVotes = MatchController.Votes
		stamp(state.VotesAt, now)
	end

	state.Votes(MatchController.Votes)
	state.VotesNeeded(MatchController.VotesNeeded)
	-- Never past a boss: the server refuses the vote until it is dead (RoundService).
	local isBossUp = MatchController.BossDataId ~= 0
	local canSkip = phase == "Fighting" and gameNow >= MatchController.SkipOpensAt and not isBossUp
	if canSkip and not wasSkipOpen then stamp(state.SkipOpenedAt, now) end
	wasSkipOpen = canSkip
	state.CanSkip(canSkip)
	-- One cooldown across the countdown and the wave's opening seconds: SKIP WAVE fills from the moment a countdown
	-- starts. Rounded to the fill's own pixels, so a frame that would not move it writes nothing.
	local waited = if phase == "Preparing"
		then RoundCore.PREPARE_SECONDS - (MatchController.PrepareEndsAt - gameNow)
		else RoundCore.PREPARE_SECONDS + RoundCore.SKIP_AFTER_SECONDS - (MatchController.SkipOpensAt - gameNow)
	local cooldown = math.clamp(waited / (RoundCore.PREPARE_SECONDS + RoundCore.SKIP_AFTER_SECONDS), 0, 1)
	state.SkipProgress(
		if (phase ~= "Preparing" and phase ~= "Fighting") or isBossUp
			then 0
			else math.round(cooldown * Tune.SKIP_FILL_STEPS) / Tune.SKIP_FILL_STEPS
	)
	state.IsAutoSkip(ProfileController.IsAutoSkip)

	local countdown = math.ceil(math.max(MatchController.PrepareEndsAt - gameNow, 0))
	if countdown ~= lastCountdown then
		lastCountdown = countdown
		if phase == "Preparing" then stamp(state.CountdownAt, now) end
	end

	state.Countdown(countdown)

	local boss = ENEMIES[MatchController.BossDataId]
	if boss then bossSeenRound = round end
	state.BossName(if boss then boss.Name else "")
	state.BossHealth(MatchController.BossHealth)
	state.BossMaxHealth(MatchController.BossMaxHealth)

	local every = RoundCore.BOSS_EVERY
	local upcoming = math.max(math.ceil(round / every) * every, every)
	if upcoming == round and bossSeenRound == round and not boss then
		upcoming += every
	end

	if upcoming ~= nextBossRound then
		nextBossRound = upcoming
		local nextBoss = RoundCore.GetBoss(upcoming, ALL_ENEMIES)
		nextBossName = if nextBoss then nextBoss.Name else ""
	end

	state.NextBossRound(nextBossRound)
	state.NextBossName(nextBossName)
end

local function updateWallet(now: number, dt: number)
	local gold = MatchController.Gold
	-- Gold still flying in as coins is held back. A kill's Gold and its coins are fired together and arrive in one
	-- flush, so the counter never sees one without the other; Gold spent while coins fly can take it below zero.
	local pending = CoinsController.PendingGold
	local target = math.max(gold - pending, 0)
	if target > goldTarget then
		goldInAt = now
		motionUntil = now + Tune.MOTION_SECONDS
	end
	goldTarget = target
	-- A coin landing puts its Gold on in one tick, so the count climbs coin by coin.
	if target < goldShown or pending < lastPendingGold then
		goldShown = target
	else
		goldShown += (target - goldShown) * math.min(dt * Tune.GOLD_ROLL_RATE, 1)
		if target - goldShown < 0.5 then goldShown = target end
	end
	lastPendingGold = pending

	state.Gold(gold)
	state.GoldShown(math.floor(goldShown))
	state.GoldPulse(fade(goldInAt, Tune.GOLD_PULSE_SECONDS, now))
	state.GoldDenied(fade(goldDeniedAt, Tune.GOLD_DENIED_SECONDS, now))
end

local function updateHealth(now: number, dt: number)
	local health, maxHealth = HealthController.Health, HealthController.MaxHealth
	-- Until the server's first Health arrives, the Humanoid's mirror of it.
	if maxHealth <= 0 then
		local humanoid = selfHumanoid
		if humanoid then
			health, maxHealth = humanoid.Health, humanoid.MaxHealth
		end
	end

	trailHealth = math.max(trailHealth, health)
	if now > HealthController.HurtAt + Tune.TRAIL_HOLD_SECONDS then
		trailHealth = math.max(trailHealth - Tune.TRAIL_DRAIN_RATE * maxHealth * dt, health)
	end

	local isDown = MatchController.IsRunning and HealthController.IsDown()
	state.Health(health)
	state.MaxHealth(maxHealth)
	state.TrailHealth(trailHealth)
	state.IsDown(isDown)
	local head = state.Head()
	state.IsFirstPerson(
		head ~= nil and (Workspace.CurrentCamera.CFrame.Position - head.Position).Magnitude < Tune.FIRST_PERSON_STUDS
	)

	local hurt = Tune.HURT_PEAK * fade(HealthController.HurtAt, Tune.HURT_SECONDS, now)
	local share = if maxHealth > 0 then health / maxHealth else 1
	local low = if not isDown and share < Tune.LOW_HEALTH_SHARE
		then Tune.LOW_HEALTH_EDGE * (0.75 + 0.25 * math.sin(now * 4))
		else 0
	state.Vignette(math.max(hurt, low))

	for player, member in squadMembers do
		if member.IsSelf then
			member.Health(health)
			member.MaxHealth(maxHealth)
			continue
		end

		local humanoid = squadHumanoids[player]
		member.Health(if humanoid then humanoid.Health else 0)
		member.MaxHealth(if humanoid then humanoid.MaxHealth else 0)
	end

	-- The nuke is the bigger save, so it asks first.
	local isNuke = MatchController.IsRunning and not isDown and EnemiesController.Count > Tune.NUKE_PROMPT_ENEMIES
	state.EnemyCount(EnemiesController.Count)
	state.IsNukePrompted(isNuke)
	state.IsHealPrompted(
		MatchController.IsRunning and not isNuke and not isDown and maxHealth > 0 and share < Tune.HEAL_PROMPT_SHARE
	)
end

local function updateDefenses(now: number)
	for _, defense in defenses do
		local count = DefensePlacementController.Owned[defense.DataId] or 0
		if count > defense.Count() then stamp(defense.PlacedAt, now) end
		defense.Count(count)
		defense.IsPlacing(DefensePlacementController.PlacingId == defense.DataId)
	end
end

-- Stamps one of the weapon card's gestures. Every one is over within Timing.TOTAL, and stamp keeps Now ticking at
-- least that long too.
local function stampWeapon(at: vide.Source<number>, now: number)
	stamp(at, now)
	weaponUntil = now + WeaponUpgrade.Timing.TOTAL
end

local function updateWeapon(now: number): boolean
	local weapon = state.Weapon
	local step = math.max(WeaponController.Step, 1)
	local offer = LADDER[step + 1]
	weapon.Step(step)
	weapon.Held(LADDER[step])
	weapon.Offer(offer)

	local isBought = WeaponController.UpgradedAt ~= lastUpgradedAt
	if isBought then
		lastUpgradedAt = WeaponController.UpgradedAt
		stampWeapon(weapon.BoughtAt, now)
		weapon.LandAt(now + WeaponUpgrade.Timing.FLIGHT)
	end

	if WeaponController.UpgradeAskedAt ~= lastAskedAt then
		lastAskedAt = WeaponController.UpgradeAskedAt
		stampWeapon(weapon.AskedAt, now)
	end

	if WeaponController.UpgradeDeniedAt ~= lastDeniedAt then
		lastDeniedAt = WeaponController.UpgradeDeniedAt
		stampWeapon(weapon.DeniedAt, now)
		-- Short of Gold, the counter says so too.
		if offer and MatchController.Gold < offer.Price then goldDeniedAt = now end
	end

	-- The sweep waits for the card to finish dealing the next step in, so it lands on a card at rest.
	local canAfford = offer ~= nil and goldShown >= offer.Price
	weapon.CanAfford(canAfford)
	if not canAfford then
		wasAffordable = false
	elseif not wasAffordable and now >= weapon.BoughtAt() + WeaponUpgrade.Timing.TOTAL then
		wasAffordable = true
		stampWeapon(weapon.ReadyAt, now)
	end

	weapon.Clock(if now < weaponUntil then now else math.huge)
	return isBought
end

-- `isBought`: the new gun is a bought upgrade, which lands in its slot with its own punch (Hotbar).
local function updateGun(now: number, isBought: boolean)
	local gun = WeaponController.Gun
	if gun ~= lastGun then
		lastGun = gun
		if not isBought then stamp(state.GunAt, now) end
	end

	state.Gun(gun)
	state.GunModel(heldModel)
end

local function updateOverlays(now: number)
	state.IsReviveOffered(MatchController.ReviveProductId ~= 0)
	state.RoundsCleared(MatchController.RoundsCleared)
	state.RunGold(MatchController.RunGold)
	state.RunGems(MatchController.RunGems)
	state.ReturnIn(math.max(math.ceil(MatchController.ReturnAt - now), 0))
end

local function update(dt: number)
	local now = os.clock()
	local gameNow = TimeCore.GameClock
	local viewport = Workspace.CurrentCamera.ViewportSize
	state.Scale(math.clamp(viewport.Y / Theme.DESIGN_HEIGHT, Theme.MIN_SCALE, Theme.MAX_SCALE))
	updateRound(now, gameNow)
	updateWallet(now, dt)
	updateHealth(now, dt)
	updateDefenses(now)
	updateGun(now, updateWeapon(now))
	updateOverlays(now)
	-- A prompted item breathes for as long as it asks, so the clock runs with it.
	if now < motionUntil or state.IsNukePrompted() or state.IsHealPrompted() then state.Now(now) end
end

local function rebuildSquad()
	local list = {}
	local own = squadMembers[LocalPlayer]
	if own then list[1] = own end
	for _, player in Players:GetPlayers() do
		local member = squadMembers[player]
		if member and player ~= LocalPlayer then list[#list + 1] = member end
	end

	state.Squad(table.freeze(list))
end

local function updateFrame()
	update(frameDt)
end

local actions: Types.TActions = {
	VoteStart = MatchController.VoteStart,
	ToggleAutoSkip = function()
		MatchController.SetAutoSkip(not ProfileController.IsAutoSkip)
	end,
	PlaceDefense = function(dataId: number)
		local data = DEFENSES[dataId]
		if not data then return end
		if DefensePlacementController.PlacingId ~= dataId and MatchController.Gold < data.Cost then
			local now = os.clock()
			goldDeniedAt = now
			for _, defense in defenses do
				if defense.DataId == dataId then stamp(defense.DeniedAt, now) end
			end
			return
		end

		DefensePlacementController.Begin(dataId)
	end,
	UpgradeWeapon = WeaponController.Upgrade,
	Revive = function()
		local productId = MatchController.ReviveProductId
		if productId ~= 0 then MarketplaceService:PromptProductPurchase(LocalPlayer, productId) end
	end,
	-- Shown before their products exist, as the design lays them out: a click does nothing until EProducts has them.
	BuyHealAll = function()
		if EProducts.HealAll ~= 0 then MarketplaceService:PromptProductPurchase(LocalPlayer, EProducts.HealAll) end
	end,
	BuyNukeAll = function()
		if EProducts.NukeAll ~= 0 then MarketplaceService:PromptProductPurchase(LocalPlayer, EProducts.NukeAll) end
	end,
	CloseSquad = function()
		if squadIcon then squadIcon:deselect() end
	end,
}

local function setSquadOpen(isOpen: boolean)
	state.IsSquadOpen(isOpen)
	stamp(state.SquadToggledAt, os.clock())
end

-- Dresses a top bar icon in the HUD's panel (Topbar.luau) and feeds the panel what the hand does to it.
local function skinTopbarIcon(icon: any, isSelected: vide.Source<boolean>, hasBrackets: boolean)
	local skin: Types.TTopbarSkin = {
		HasBrackets = hasBrackets,
		IsHovered = source(false),
		IsSelected = isSelected,
		PressedAt = source(-math.huge),
	}
	icon:modifyTheme(Topbar.Theme())
	icon.viewingStarted:Connect(function()
		skin.IsHovered(true)
	end)
	icon.viewingEnded:Connect(function()
		skin.IsHovered(false)
	end)
	icon:getInstance("ClickRegion").MouseButton1Down:Connect(function()
		stamp(skin.PressedAt, os.clock())
	end)

	-- TopbarPlus clips the icon (for its dropdowns, which these have none of), which would cut the panel's shadow; it
	-- clips the button again on every deselect, so this runs after it.
	local widget, button = icon:getInstance("Widget"), icon:getInstance("IconButton")
	local function unclip()
		widget.ClipsDescendants = false
		button.ClipsDescendants = false
	end

	unclip()
	icon.deselected:Connect(function()
		task.defer(unclip)
	end)

	vide.mount(function()
		return Topbar.Skin(state, skin)
	end, icon:getInstance("IconButton"))
end

-- The top bar's two icons: SQUAD on the left with Roblox's own buttons, Settings in the right corner.
local function createTopbarIcons()
	local offset = Icons.Cells
	squadIcon = TopbarPlus.new()
	squadIcon
		:setName("Squad")
		:setImage(Icons.IMAGE)
		:modifyTheme({ "IconImage", "ImageRectOffset", offset.Squad })
		:modifyTheme({ "IconImage", "ImageRectSize", Icons.CELL_SIZE })
		:setLabel("SQUAD")
		:setTextFont(Theme.Font.Display.Family, Enum.FontWeight.Heavy)
		:bindEvent("selected", function()
			setSquadOpen(true)
		end)
		:bindEvent("deselected", function()
			setSquadOpen(false)
		end)

	skinTopbarIcon(squadIcon, state.IsSquadOpen, true)

	-- The Settings screen (UIMatt.md, Settings) is not ported yet: the icon is in its place and opens nothing.
	local settingsIcon = TopbarPlus.new()
		:setName("Settings")
		:setImage(Icons.IMAGE)
		:modifyTheme({ "IconImage", "ImageRectOffset", offset.Settings })
		:modifyTheme({ "IconImage", "ImageRectSize", Icons.CELL_SIZE })
		:setCaption("Settings")
		:align("Right")
		:oneClick()
	skinTopbarIcon(settingsIcon, source(false), false)
end

-- The Tool the character holds, for the gun slot's picture (WeaponService builds it with its model inside).
local function watchHeldTool(character: Model)
	local function refresh()
		local tool = character:FindFirstChildOfClass("Tool")
		heldModel = if tool then tool:FindFirstChild("Model") :: Model? else nil
	end

	refresh()
	character.ChildAdded:Connect(refresh)
	character.ChildRemoved:Connect(refresh)
end

HudController.OnPlayerConnected = function(player: Player)
	squadMembers[player] = {
		Name = player.DisplayName,
		UserId = player.UserId,
		IsSelf = player == LocalPlayer,
		Health = source(0),
		MaxHealth = source(0),
	}
	rebuildSquad()
end :: TPlayerEvents.OnPlayerConnected

HudController.OnPlayerDisconnected = function(player: Player)
	if not squadMembers[player] then return end
	squadMembers[player] = nil
	squadHumanoids[player] = nil
	rebuildSquad()
end :: TPlayerEvents.OnPlayerDisconnected

HudController.OnCharacterAdded = function(character: TCharacter.TCharacter)
	local player = Players:GetPlayerFromCharacter(character)
	if player and player ~= LocalPlayer then squadHumanoids[player] = character.Humanoid end
end :: TCharacterEvents.OnCharacterAdded

HudController.OnCharacterRemoving = function(character: TCharacter.TCharacter)
	local player = Players:GetPlayerFromCharacter(character)
	if player and squadHumanoids[player] == character.Humanoid then squadHumanoids[player] = nil end
end :: TCharacterEvents.OnCharacterRemoving

HudController.OnSelfCharacterAdded = function(character: TCharacter.TCharacter)
	state.Head(character.Head)
	selfHumanoid = character.Humanoid
	watchHeldTool(character)
end :: TCharacterEvents.OnCharacterAdded

HudController.OnSelfCharacterRemoving = function()
	state.Head(nil)
	selfHumanoid = nil
	heldModel = nil
end :: TCharacterEvents.OnCharacterRemoving

HudController.OnStart = function()
	-- The HUD's own bar replaces the platform's, which would show the same number twice.
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

	createTopbarIcons()
	update(0)
	vide.mount(function()
		-- A list: mount keeps only the first value a component returns.
		return {
			create("ScreenGui")({
				Name = "Hud",
				ResetOnSpawn = false,
				IgnoreGuiInset = true,
				ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
				ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
				-- Scaled from a 1080-tall design: the root is sized 1 / scale so that after its UIScale it fills the
				-- screen.
				create("Frame")({
					Name = "Root",
					BackgroundTransparency = 1,
					Size = function()
						local scale = state.Scale()
						return UDim2.fromScale(1 / scale, 1 / scale)
					end,
					create("UIScale")({ Scale = state.Scale }),
					Overlays.Vignette(state),
					Wave.Build(state, actions),
					Items.Build(state, actions),
					Upgrades.Build(state, actions),
					Shop.Defenses(state, actions),
					Hotbar.Build(state),
					WeaponUpgrade.Build(state, Upgrades.WEAPON_PICTURE, Upgrades.PICTURE_SIZE, Upgrades.PICTURE_TILT),
					Squad.Build(state, actions),
					Overlays.Down(state, actions),
					Overlays.Results(state),
				}),
			}),
			Overhead.Build(state),
		}
	end, LocalPlayer:WaitForChild("PlayerGui"))

	RunService.PreRender:Connect(function(dt: number)
		frameDt = dt
		vide.batch(updateFrame)
	end)
end

return Ignis.Register(HudController)
