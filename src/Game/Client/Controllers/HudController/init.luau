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
local Network = require(StarterPlayer.StarterPlayerScripts.GlobalClient.Network)
local NetworkMeta = require(StarterPlayer.StarterPlayerScripts.GlobalClient.NetworkMeta)
local AbilityController = require(script.Parent.AbilityController)
local BossController = require(script.Parent.BossController)
local CoinsController = require(script.Parent.CoinsController)
local DefensePlacementController = require(script.Parent.DefensePlacementController)
local DownedController = require(script.Parent.DownedController)
local CameraController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.CameraController)
local EnemiesController = require(script.Parent.EnemiesController)
local EquipmentDropController = require(script.Parent.EquipmentDropController)
local HealthController = require(script.Parent.HealthController)
local MatchController = require(script.Parent.MatchController)
local UpgradePickController = require(script.Parent.UpgradePickController)
local WeaponRunController = require(script.Parent.WeaponRunController)
local copyCharacter = require(StarterPlayer.StarterPlayerScripts.GlobalClient.Utils.copyCharacter)
local equipmentPieces = require(StarterPlayer.StarterPlayerScripts.GlobalClient.Utils.equipmentPieces)
-- Through PlayerScripts, the copy that runs: requiring the StarterPlayer one loads a second ProfileController, which
-- Ignis refuses as already registered (the first playtest of the HUD).
local ProfileController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.ProfileController)
local DebugInfoController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.DebugInfoController)
local SettingsController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.SettingsController)
local WeaponController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.WeaponController)
local AbilitiesCore = require(ReplicatedStorage.GlobalShared.Core.AbilitiesCore)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local EquipmentCore = require(ReplicatedStorage.GlobalShared.Core.EquipmentCore)
local GunsCore = require(ReplicatedStorage.GlobalShared.Core.GunsCore)
local EnemiesCore = require(ReplicatedStorage.Shared.Core.EnemiesCore)
local RoundCore = require(ReplicatedStorage.Shared.Core.RoundCore)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local TimeCore = require(ReplicatedStorage.Shared.Core.TimeCore)
local doubleGems = require(ReplicatedStorage.Shared.Utils.doubleGems)
local healthUpgrades = require(ReplicatedStorage.Shared.Utils.healthUpgrades)
local TopbarPlus = require(ReplicatedStorage.GlobalShared.TopbarPlus)
local Announce = require(script.Announce)
local AbilityPicture = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.AbilityPicture)
local AvatarPose = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.AvatarPose)
local BarJuice = require(script.BarJuice)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local BossBar = require(script.BossBar)
local Down = require(script.Down)
local HealthUpgrade = require(script.HealthUpgrade)
local Hotbar = require(script.Hotbar)
local Icons = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Icons)
local Items = require(script.Items)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Topbar = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Topbar)
local Overhead = require(script.Overhead)
local Overlays = require(script.Overlays)
local QuestToast = require(script.QuestToast)
local Results = require(script.Results)
local Shop = require(script.Shop)
local Squad = require(script.Squad)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local UiFade = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.UiFade)
local Upgrades = require(script.Upgrades)
local Wave = require(script.Wave)
local WeaponUpgrade = require(script.WeaponUpgrade)
local Types = require(script.Types)
local EProducts = require(ReplicatedStorage.Types.Enums.EProducts)
local TCharacter = require(ReplicatedStorage.Types.TCharacter)
local TCharacterEvents = require(ReplicatedStorage.Types.Events.TCharacterEvents)
local TData = require(ReplicatedStorage.Types.TData)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local LocalPlayer = Players.LocalPlayer
local ServerNetworkQuests = NetworkMeta.Server.Quests
local ClientNetworkCharacters = Network.Client.Characters
local ENEMIES = DataCore.Enemies.ById
local DEFENSES = DataCore.Defenses.ById
-- Everybody's class until the server says otherwise.
local DEFAULT_CLASS: TData.TClass = AbilitiesCore.ClassOf(nil)
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
	-- The same edge in green when a wave is done (MatchController.MarkWaveDone): a reward, so it lingers longer than a
	-- hit.
	WAVE_DONE_PEAK = 0.5,
	WAVE_DONE_SECONDS = 1.2,
	-- Down: the edge holds the blow's red at DOWN_PEAK and cools over DOWN_COOL into a dark frame at DOWN_HOLD for as
	-- long as the player is down, gone as the rebuild starts; the lower HUD steps aside over LOWER_PERIOD, and the
	-- fight's HUD at the top lifts FIGHT_LIFT px off as it fades; the down's clock runs this long past the body showing,
	-- for the plate's way out.
	DOWN_PEAK = 0.75,
	DOWN_COOL = 1.4,
	DOWN_HOLD = 0.45,
	DOWN_OUT = 0.6,
	DOWN_EDGE = Color3.fromRGB(20, 8, 24),
	LOWER_PERIOD = 0.35,
	FIGHT_LIFT = 24,
	DOWN_CLOCK_AFTER = 1,
	-- The camera this close to the head is first person (Roblox's own zoom-in puts it at the head).
	FIRST_PERSON_STUDS = 1.5,
	-- More enemies than this and NUKE ALL asks to be bought; under this share of health, HEAL ALL does.
	NUKE_PROMPT_ENEMIES = 30,
	HEAL_PROMPT_SHARE = 0.4,
	-- The results' way out takes this long; their countdown's bar moves in this many steps, one a pixel.
	RESULTS_CLOSE_SECONDS = 0.5,
	RETURN_BAR_STEPS = 193,
	-- How long Now keeps ticking after anything starts a timed gesture: the longest one is shorter.
	MOTION_SECONDS = 1.6,
	-- SKIP WAVE's cooldown fill moves in this many steps, about one a pixel across the button.
	SKIP_FILL_STEPS = 300,
	-- An ability's cooldown shade and the ultimate's charge bar move in this many steps, about one a pixel.
	COOLDOWN_STEPS = 96,
	CHARGE_STEPS = 114,
	-- What each ability's slot wears, by kind.
	ABILITY_ACCENTS = {
		Decoy = Theme.Palette.Pink,
		FoamCannon = Theme.Palette.Steel,
	},
})
-- The HUD's roots (hudRoot): over the floating numbers (-3), under the mutation and drop cards (2). The squad screen
-- opens over the upgrade cards (10) and the hurt vignette (11) too, under the settings screen (15).
local HUD_DISPLAY_ORDERS = table.freeze({ Base = -2, Live = -1, Top = 0, Squad = 12 })

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

-- The class is the run's, known before the HUD is built (AbilityController starts on the default until the server
-- says otherwise).
local abilities = table.create(#AbilityController.Class.Abilities)
for slot, ability in AbilityController.Class.Abilities do
	abilities[slot] = {
		Slot = slot,
		Name = ability.Name,
		Kind = ability.Kind,
		Key = AbilityController.KEYS[slot],
		Accent = Tune.ABILITY_ACCENTS[ability.Kind] or Theme.Palette.Steel,
		Cost = source(ability.Cost or 0),
		Cooling = source(0),
		Seconds = source(0),
		UsedAt = source(-math.huge),
		DeniedAt = source(-math.huge),
		ReadyAt = source(-math.huge),
	}
end

local state: Types.THudState = {
	Scale = source(1),
	Now = source(os.clock()),
	Breath = source(os.clock()),
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
		DropWonAt = table.create(BossBar.MOST_DROPS),
	},
	NextBossName = source(""),
	NextBossRound = source(0),
	Gold = source(0),
	GoldShown = source(0),
	GoldPulse = source(0),
	GoldDenied = source(0),
	GoldDeniedAt = source(-math.huge),
	Health = source(0),
	MaxHealth = source(0),
	BarHealth = source(0),
	BarMax = source(0),
	HealthTrack = BarJuice.NewTrack(),
	IsDown = source(false),
	Down = {
		Clock = source(0),
		At = source(-math.huge),
		SwitchedAt = source(-math.huge),
		RebuildAt = source(-math.huge),
		StoodAt = source(-math.huge),
		IsRebuilding = source(false),
		Watched = source(""),
		WatchedHealth = source(0),
		WatchedMax = source(0),
	},
	Downed = source(table.freeze({}) :: { Player }),
	Head = source(nil :: BasePart?),
	IsFirstPerson = source(false),
	Vignette = source(0),
	VignetteColor = source(Theme.Color.Hurt),
	Shock = source(0),
	Defenses = defenses,
	Squad = source(table.freeze({}) :: { Types.TSquadMember }),
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
	Quest = {
		Id = source(0),
		Board = source(1),
		At = source(-math.huge),
		Hold = source(QuestToast.HOLD),
		Clock = source(0),
	},
	Gun = source(nil :: any),
	GunModel = source(nil :: Model?),
	Avatar = source(nil :: Model?),
	GunAt = source(-math.huge),
	Weapon = {
		Offer = source(GunsCore.STARTER_LADDER[2] :: GunsCore.TLadderStep?),
		Held = source(GunsCore.STARTER_LADDER[1] :: GunsCore.TLadderStep?),
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
		Price = source(healthUpgrades.PRICES[1] :: number?),
		Paid = source(0),
		CanAfford = source(false),
		Clock = source(math.huge),
		BoughtAt = source(-math.huge),
		LandAt = source(-math.huge),
		AskedAt = source(-math.huge),
		DeniedAt = source(-math.huge),
		ReadyAt = source(-math.huge),
		BarAt = source(Hotbar.HEALTH),
	},
	Abilities = abilities,
	Ultimate = {
		Slot = #abilities + 1,
		Name = AbilityController.Class.Ultimate.Name,
		Kind = AbilityController.Class.Ultimate.Kind,
		Key = AbilityController.ULTIMATE_KEY,
		Charge = source(0),
		IsReady = source(false),
		Burning = source(0),
		ChargedAt = source(-math.huge),
		UsedAt = source(-math.huge),
		DeniedAt = source(-math.huge),
		CanBuy = EProducts.ChargeUltimate ~= 0,
		BoughtAt = source(-math.huge),
		LandedAt = source(-math.huge),
	},
	CanRevive = EProducts.Revive ~= 0,
	CanQuickRevive = EProducts.QuickRevive ~= 0,
	Keys = table.freeze({
		Skip = MatchController.SKIP_KEY,
		Turn = DefensePlacementController.TURN_KEY,
		Upgrade = WeaponRunController.UPGRADE_KEY,
		Health = HealthController.UPGRADE_KEY,
	}),
	Results = {
		IsOpen = source(false),
		ToggledAt = source(-math.huge),
		Clock = source(math.huge),
		Beat = source(0),
		Wave = source(0),
		IsNewBest = source(false),
		SquadKills = source(0),
		Seconds = source(0),
		Gems = source(0),
		TotalGems = source(0),
		DoubleRobux = source(0),
		CanWatchAd = source(false),
		Avatar = source(nil :: Model?),
		Doubled = source(0),
		DoubledAt = source(-math.huge),
		CanRevive = source(false),
		ReturnIn = source(0),
		ReturnShare = source(1),
		ReturnTickAt = source(-math.huge),
		IsReturnHeld = source(false),
		Votes = source(0),
		VotesNeeded = source(0),
		HasVoted = source(false),
		VotesAt = source(-math.huge),
	},
}
for index = 1, BossBar.MOST_DROPS do
	state.Boss.DropWonAt[index] = source(-math.huge)
end

local squadMembers: { [Player]: Types.TSquadMember } = {}
-- The Gold each squad row shows, before it is floored: it rolls toward the real amount.
local squadCash: { [Player]: number } = {}
local squadIcon: any = nil
local settingsIcon: any = nil
-- os.clock until which Now keeps ticking (Tune.MOTION_SECONDS past the last gesture that started).
local motionUntil = -math.huge
-- os.clock until which the squad's announcement is up.
local announceUntil = -math.huge
-- CHARGE NOW's bolts (Shop), the last bought fill seen, the share of the meter still flying into the bar, and the last
-- time the meter filled that the ULT card has answered: a bought fill's answer waits for its last bolt.
local chargeFlight: Shop.TChargeFlight? = nil
local lastBoughtAt = -math.huge
local owedShare = 0
local chargedSeen = -math.huge
-- Quests finished and not shown yet, as (board, quest Id), oldest first; questClock until which the card on show runs.
local questQueue: { { number } } = {}
local questUntil = -math.huge
-- Seconds the HUD has been drawn: a card on show stands still while the HUD is hidden (the upgrade cards over it), so
-- it is never missed.
local questClock = 0
-- os.clock until which the results' clock runs (the last of their one-off gestures to end), and whether a purchase
-- prompt opened from them is up.
local resultsUntil = -math.huge
local isBuyingFromResults = false
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
-- The same for the HEALTH card: HealthController's stamps as last seen, whether the next level was affordable last
-- frame, and until when the card or its show is moving.
local lastHealthUpgradedAt = -math.huge
local lastHealthAskedAt = -math.huge
local lastHealthDeniedAt = -math.huge
local wasHealthAffordable = false
local vitalUntil = -math.huge
-- The health bar's own max and health (state.BarMax, BarHealth), and the max it drew when the last level was bought:
-- the bar grows from that to the truth once the level lands.
local barMax = 0
local barGrowsFrom = 0
-- The Tool the local character holds, kept by its ChildAdded / ChildRemoved.
local heldModel: Model? = nil
local selfHumanoid: Humanoid? = nil
-- The health bar's chase, in health.
local healthChase = BarJuice.NewChase(0)
local goldShown = 0
local goldTarget = 0
local lastPendingGold = 0
local goldInAt = -math.huge
local goldDeniedAt = -math.huge
local nextBossRound, nextBossName = -1, ""
-- The boss bar's memory between frames, and what is seen of the boss each frame (one table, refilled).
local bossMemory = BossBar.NewMemory()
local bossSeen: BossBar.TBossSeen = {
	DataId = 0,
	Name = "",
	Share = 0,
	Top = { { UserId = 0, Name = "", Share = 0 }, { UserId = 0, Name = "", Share = 0 } },
	SelfId = LocalPlayer.UserId,
	IsRunning = false,
	WayKills = 0,
	WayNeeded = 0,
	Drops = {},
	WonAt = EquipmentDropController.WonAt,
}
-- The boss whose drops bossSeen holds (0 for none), so they are read once as it comes on.
local dropsBossId = 0
-- Display names by UserId for the boss bar's damage share, looked up once each.
local namesById: { [number]: string } = {}
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
	-- Never past a boss on its way (its way full) or up: the server refuses the vote until it is dead (RoundService).
	local wayNeeded = MatchController.BossWayNeeded
	local isBossHeld = MatchController.BossDataId ~= 0 or (wayNeeded > 0 and MatchController.BossWayKills >= wayNeeded)
	local canSkip = phase == "Fighting" and gameNow >= MatchController.SkipOpensAt and not isBossHeld
	if canSkip and not wasSkipOpen then stamp(state.SkipOpenedAt, now) end
	wasSkipOpen = canSkip
	state.CanSkip(canSkip)
	-- One cooldown across the countdown and the wave's opening seconds: SKIP WAVE fills from the moment a countdown
	-- starts. Rounded to the fill's own pixels, so a frame that would not move it writes nothing.
	local skipCooldownSeconds = RoundCore.PREPARE_SECONDS + RoundCore.GetSkipAfterSeconds(MatchController.Round)
	local waited = if phase == "Preparing"
		then RoundCore.PREPARE_SECONDS - (MatchController.PrepareEndsAt - gameNow)
		else skipCooldownSeconds - (MatchController.SkipOpensAt - gameNow)
	local cooldown = math.clamp(waited / skipCooldownSeconds, 0, 1)
	state.SkipProgress(
		if (phase ~= "Preparing" and phase ~= "Fighting") or isBossHeld
			then 0
			else math.round(cooldown * Tune.SKIP_FILL_STEPS) / Tune.SKIP_FILL_STEPS
	)
	state.IsAutoSkip(ProfileController.IsAutoSkip)

	local countdown = math.ceil(math.max(MatchController.PrepareEndsAt - gameNow, 0))
	if countdown ~= lastCountdown then
		lastCountdown = countdown
		if phase == "Preparing" then
			stamp(state.CountdownAt, now)
			-- The upgrade screen's tick takes, quieter, so the game counts down in one voice. Silent on GO, and under the
			-- cards: they hide the square and tick their own count. Silent while down too: the square has stepped aside.
			if countdown > 0 and not UpgradePickController.IsCovering() and not state.IsDown() then
				SoundsCore.PlayUINamed("UI", "CountdownTick")
			end
		end
	end

	state.Countdown(countdown)

	-- The boss the way leads to, which moves on as it falls; before the server has said, the first one.
	local upcoming = if MatchController.BossWayRound > 0 then MatchController.BossWayRound else RoundCore.BOSS_EVERY
	if upcoming ~= nextBossRound then
		nextBossRound = upcoming
		local nextBoss = RoundCore.GetBoss(upcoming, MatchController.MapName, ENEMIES, EnemiesCore.HasModel)
		nextBossName = if nextBoss then nextBoss.Name else ""
	end

	state.NextBossRound(nextBossRound)
	state.NextBossName(nextBossName)
end

-- One line of the boss's damage share: `damage` taken off a boss of `maxHealth` by `userId` (0 for nobody).
local function fillShare(line: BossBar.TShareSeen, userId: number, damage: number, maxHealth: number)
	local name = namesById[userId]
	if userId ~= 0 and not name then
		local player = Players:GetPlayerByUserId(userId)
		name = if player then player.DisplayName else nil
		namesById[userId] = name
	end

	line.UserId = if name then userId else 0
	line.Name = name or ""
	line.Share = if name and maxHealth > 0 then math.clamp(damage / maxHealth, 0, 1) else 0
end

-- The boss's bar, from what the server last said about the boss up.
local function updateBoss(now: number, dt: number)
	local data = ENEMIES[MatchController.BossDataId]
	local maxHealth = MatchController.BossMaxHealth
	bossSeen.DataId = if data then data.Id else 0
	bossSeen.Name = if data then data.Name else ""
	bossSeen.Share = if data and maxHealth > 0 then math.clamp(MatchController.BossHealth / maxHealth, 0, 1) else 0
	fillShare(bossSeen.Top[1], MatchController.BossFirstId, MatchController.BossFirstDamage, maxHealth)
	fillShare(bossSeen.Top[2], MatchController.BossSecondId, MatchController.BossSecondDamage, maxHealth)
	bossSeen.IsRunning = MatchController.IsRunning and not MatchController.IsEnded
	bossSeen.WayKills = MatchController.BossWayKills
	bossSeen.WayNeeded = MatchController.BossWayNeeded
	if bossSeen.DataId ~= dropsBossId then
		dropsBossId = bossSeen.DataId
		local drops = {}
		for index, item in EquipmentCore.DropsOf(dropsBossId) do
			if index > BossBar.MOST_DROPS then break end
			local drop = item.Drop :: TData.TEquipmentDrop
			drops[index] =
				{ Id = item.Id, Chance = drop.Chance, IsOwned = EquipmentDropController.Owned[item.Id] == true }
		end
		bossSeen.Drops = drops
	end
	motionUntil = math.max(motionUntil, BossBar.Update(state.Boss, bossMemory, bossSeen, now, dt))
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
	state.GoldDeniedAt(goldDeniedAt)
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

	-- A bought level is on its way to the bar until it lands, then the bar's max rises into it. The max and the health
	-- are held back by the same amount, so the fill never slides backwards on the one event that made it bigger, and a
	-- hit taken meanwhile still shows at once.
	local grown = Motion.Decelerate(Motion.Progress(now, state.Vital.LandAt(), HealthUpgrade.Timing.GROW))
	barMax = if maxHealth > barGrowsFrom and barGrowsFrom > 0
		then barGrowsFrom + (maxHealth - barGrowsFrom) * grown
		else maxHealth
	local barHealth = math.max(health - (maxHealth - barMax), 0)
	-- While the bar grows into a bought level its health rises with its max, which is not a heal.
	local bite = BarJuice.Step(healthChase, barHealth, barMax, dt, now, barMax ~= maxHealth)
	if bite > 0 then motionUntil = now + Tune.MOTION_SECONDS end
	BarJuice.Write(state.HealthTrack, healthChase, bite, if barMax > 0 then barHealth / barMax else 0, now)

	local isDown = MatchController.IsRunning and DownedController.IsDown
	state.Health(health)
	state.MaxHealth(maxHealth)
	state.BarHealth(barHealth)
	state.BarMax(barMax)
	state.IsDown(isDown)
	local head = state.Head()
	state.IsFirstPerson(
		head ~= nil and (Workspace.CurrentCamera.CFrame.Position - head.Position).Magnitude < Tune.FIRST_PERSON_STUDS
	)

	local hurt = Tune.HURT_PEAK * fade(HealthController.HurtAt, Tune.HURT_SECONDS, now)
	local share = if maxHealth > 0 then health / maxHealth else 1
	-- The edge draws over the upgrade cards (to greet the wave they came with), where low health's red was never shown.
	local low = if not isDown
			and share < Tune.LOW_HEALTH_SHARE
			and not UpgradePickController.IsCovering()
		then Tune.LOW_HEALTH_EDGE * (0.75 + 0.25 * math.sin(now * 4))
		else 0
	local red = math.max(hurt, low)
	local waveDone = Tune.WAVE_DONE_PEAK * fade(MatchController.WaveDoneAt, Tune.WAVE_DONE_SECONDS, now)
	-- Down: the blow's red held, cooling into the dark frame that stays until the rebuild starts.
	local downEdge, downColor = 0, Theme.Color.Hurt
	if isDown then
		local cooled = Motion.Out(Motion.Progress(now, DownedController.DownAt, Tune.DOWN_COOL))
		local gone = Motion.Decelerate(Motion.Progress(now, DownedController.RebuildAt, Tune.DOWN_OUT))
		local isGoing = DownedController.RebuildAt > DownedController.DownAt
		downEdge = (Tune.DOWN_PEAK + (Tune.DOWN_HOLD - Tune.DOWN_PEAK) * cooled) * (if isGoing then 1 - gone else 1)
		downColor = Theme.Color.Hurt:Lerp(Tune.DOWN_EDGE, cooled)
	end
	local edge = math.max(red, downEdge)
	state.Vignette(math.max(edge, waveDone))
	local shock = DownedController.Shock(now)
	if shock ~= state.Shock() then state.Shock(shock) end
	state.VignetteColor(
		if waveDone > edge then Theme.Palette.Green elseif downEdge > red then downColor else Theme.Color.Hurt
	)

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
	local ladder = WeaponRunController.Ladder
	local step = math.max(WeaponController.Step, 1)
	local offer = ladder[step + 1]
	weapon.Step(step)
	weapon.Held(ladder[step])
	weapon.Offer(offer)

	local isBought = WeaponController.UpgradedAt ~= lastUpgradedAt
	if isBought then
		lastUpgradedAt = WeaponController.UpgradedAt
		stampWeapon(weapon.BoughtAt, now)
		weapon.LandAt(now + WeaponUpgrade.Timing.FLIGHT)
	end

	if WeaponRunController.UpgradeAskedAt ~= lastAskedAt then
		lastAskedAt = WeaponRunController.UpgradeAskedAt
		stampWeapon(weapon.AskedAt, now)
	end

	if WeaponRunController.UpgradeDeniedAt ~= lastDeniedAt then
		lastDeniedAt = WeaponRunController.UpgradeDeniedAt
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

-- Stamps one of the HEALTH card's gestures, as stampWeapon does the weapon card's.
local function stampVital(at: vide.Source<number>, now: number)
	stamp(at, now)
	vitalUntil = now + HealthUpgrade.Timing.TOTAL
end

-- Where the middle of the health bar is on the screen, in the HUD's design px: over the head, or above the Gold in
-- first person.
local function healthBarPoint(): UDim2
	local head = state.Head()
	if not head or state.IsFirstPerson() then return Hotbar.HEALTH end

	local point = Workspace.CurrentCamera:WorldToViewportPoint(head.Position + Overhead.OFFSET)
	local scale = state.Scale()
	return UDim2.fromOffset(math.round(point.X / scale), math.round(point.Y / scale))
end

local function updateVital(now: number)
	local vital = state.Vital
	local level = HealthController.Level
	local price = healthUpgrades.PRICES[level + 1]
	vital.Level(level)
	vital.Price(price)

	if HealthController.UpgradedAt ~= lastHealthUpgradedAt then
		lastHealthUpgradedAt = HealthController.UpgradedAt
		barGrowsFrom = barMax
		vital.Paid(healthUpgrades.PRICES[level] or 0)
		stampVital(vital.BoughtAt, now)
		vital.LandAt(now + HealthUpgrade.Timing.LAND)
	end

	if HealthController.UpgradeAskedAt ~= lastHealthAskedAt then
		lastHealthAskedAt = HealthController.UpgradeAskedAt
		stampVital(vital.AskedAt, now)
	end

	if HealthController.UpgradeDeniedAt ~= lastHealthDeniedAt then
		lastHealthDeniedAt = HealthController.UpgradeDeniedAt
		stampVital(vital.DeniedAt, now)
		-- Short of Gold, the counter says so too.
		if price and MatchController.Gold < price then goldDeniedAt = now end
	end

	-- The sweep waits for the card to finish dealing the next level in, so it lands on a card at rest.
	local canAfford = price ~= nil and goldShown >= price
	vital.CanAfford(canAfford)
	if not canAfford then
		wasHealthAffordable = false
	elseif not wasHealthAffordable and now >= vital.BoughtAt() + HealthUpgrade.Timing.TOTAL then
		wasHealthAffordable = true
		stampVital(vital.ReadyAt, now)
	end

	local isMoving = now < vitalUntil
	vital.Clock(if isMoving then now else math.huge)
	-- The bar follows the camera, so what flies to it is told where it is only while something does.
	if isMoving then vital.BarAt(healthBarPoint()) end
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

-- Mirrors one of AbilityController's stamps, and keeps Now ticking for the gesture it starts.
local function mirrorStamp(at: vide.Source<number>, value: number, now: number)
	if at() == value then return end
	at(value)
	motionUntil = now + Tune.MOTION_SECONDS
end

-- Each bolt of a bought fill landing in the bar: a tick, and on the last the ULT card's moment of filling (stamped by
-- updateAbilities once nothing is owed).
local function landCharge(owed: number)
	owedShare = owed
	stamp(state.Ultimate.LandedAt, os.clock())
	SoundsCore.PlayUINamed("UI.UpgradePick", if owed > 0 then "Tick" else "RevealLegendary")
end

-- `gameNow` for what runs on the match's clock (cooldowns, the beam), `now` for the HUD's own gestures.
local function updateAbilities(now: number, gameNow: number)
	local slots = AbilityController.Slots
	for _, card in state.Abilities do
		local slot = slots[card.Slot]
		if not slot then continue end
		local left = math.max(slot.ReadyAt - gameNow, 0)
		local cooldown = if slot.Ability.Cooldown then AbilityController.CooldownOf(slot.Ability) else 1
		local cooling = math.ceil(left / cooldown * Tune.COOLDOWN_STEPS) / Tune.COOLDOWN_STEPS
		card.Cost(AbilityController.CostOf(slot))
		if cooling == 0 and card.Cooling() > 0 then stamp(card.ReadyAt, now) end
		card.Cooling(cooling)
		card.Seconds(math.ceil(left))
		mirrorStamp(card.UsedAt, slot.UsedAt, now)
		-- Short of Gold, the counter says so too.
		if card.DeniedAt() ~= slot.DeniedAt and cooling == 0 and MatchController.Gold < card.Cost() then
			goldDeniedAt = now
		end
		mirrorStamp(card.DeniedAt, slot.DeniedAt, now)
	end

	local ultimate = state.Ultimate
	local slot = slots[ultimate.Slot]
	if not slot then return end
	local needed = if slot.Ability.ChargeKills then AbilityController.ChargeKillsOf(slot.Ability) else 1
	if AbilityController.BoughtAt ~= lastBoughtAt then
		lastBoughtAt = AbilityController.BoughtAt
		local from = AbilityController.BoughtFrom
		if from < needed and chargeFlight then
			owedShare = 1 - from / needed
			stamp(ultimate.BoughtAt, now)
			chargeFlight.Throw(from / needed, now, landCharge)
		end
	end

	local share = math.clamp(AbilityController.Charge / needed - owedShare, 0, 1)
	local beamLeft = AbilityController.BeamUntil - gameNow
	ultimate.Charge(math.floor(share * Tune.CHARGE_STEPS) / Tune.CHARGE_STEPS)
	ultimate.IsReady(share >= 1)
	ultimate.Burning(
		if beamLeft > 0
			then math.ceil(beamLeft / math.max(AbilityController.BeamSeconds, 1e-3) * Tune.CHARGE_STEPS) / Tune.CHARGE_STEPS
			else 0
	)
	if AbilityController.ChargedAt ~= chargedSeen and owedShare == 0 then
		chargedSeen = AbilityController.ChargedAt
		stamp(ultimate.ChargedAt, now)
	end
	mirrorStamp(ultimate.UsedAt, slot.UsedAt, now)
	mirrorStamp(ultimate.DeniedAt, slot.DeniedAt, now)
end

-- The squad screen's rows, from the lines the server sends. A number that goes up while the screen is up is stamped,
-- for the row's answer to it; with the screen shut nothing rolls and nothing is stamped.
local function updateSquad(now: number, dt: number)
	local isOpen = state.IsSquadOpen()
	local scores = MatchController.Scores
	for player, member in squadMembers do
		local score = scores[player]
		if not score then continue end
		member.ClassName(AbilitiesCore.ClassOf(score.ClassId).Name)
		if isOpen and score.Kills > member.Kills() then stamp(member.KilledAt, now) end
		if isOpen and score.Deaths > member.Deaths() then stamp(member.DiedAt, now) end
		member.Kills(score.Kills)
		member.Deaths(score.Deaths)

		-- The local player's is the Gold counter's own number, which already rolls and holds back coins in flight.
		local shown = squadCash[player] or 0
		if member.IsSelf then
			shown = state.GoldShown()
		elseif not isOpen or score.Gold < shown then
			shown = score.Gold
		else
			shown += (score.Gold - shown) * math.min(dt * Tune.GOLD_ROLL_RATE, 1)
			if score.Gold - shown < 0.5 then shown = score.Gold end
		end

		squadCash[player] = shown
		member.Cash(math.floor(shown))
	end
end

local function updateResults(now: number)
	local results = state.Results
	local run = MatchController.Results
	if (run ~= nil) ~= results.IsOpen() then
		results.IsOpen(run ~= nil)
		CameraController.SetMouseFreed("Results", run ~= nil)
		results.ToggledAt(now)
		resultsUntil = now + (if run then Results.Seconds.OPEN else Tune.RESULTS_CLOSE_SECONDS)
		-- The total as the run ended, which already holds its Gems: what a doubling adds is counted onto it as its
		-- Gems land, whenever the profile's own number arrives.
		if run then results.TotalGems(ProfileController.Gems) end
	end

	results.Beat(if run then now else 0)
	if not run then
		results.Clock(if now < resultsUntil then now else math.huge)
		return
	end

	-- Each one-off gesture keeps the clock running for as long as it lasts.
	local left = if run.IsReturnHeld then run.ReturnSeconds else math.max(run.ReturnAt - now, 0)
	local whole = math.ceil(left)
	if whole ~= results.ReturnIn() then
		results.ReturnTickAt(now)
		resultsUntil = math.max(resultsUntil, now + Results.Seconds.GESTURE)
	end

	if run.Votes ~= results.Votes() or run.VotesNeeded ~= results.VotesNeeded() then
		results.VotesAt(now)
		resultsUntil = math.max(resultsUntil, now + Results.Seconds.GESTURE)
	end

	if run.DoubledAt ~= results.DoubledAt() then
		resultsUntil = math.max(resultsUntil, run.DoubledAt + Results.Seconds.DOUBLED)
	end

	results.Clock(if now < resultsUntil then now else math.huge)
	results.Wave(run.Wave)
	results.IsNewBest(run.IsNewBest)
	results.SquadKills(run.SquadKills)
	results.Seconds(run.SecondsSurvived)
	results.Gems(run.Gems)
	results.DoubleRobux(doubleGems.GetRobux(run.DoubleProductId) or 0)
	results.CanWatchAd(run.CanWatchAd and run.DoubleProductId ~= 0)
	results.Doubled(run.Doubled)
	results.DoubledAt(run.DoubledAt)
	results.CanRevive(MatchController.ReviveProductId ~= 0)
	results.ReturnIn(whole)
	results.ReturnShare(
		math.ceil(math.clamp(left / run.ReturnTotal, 0, 1) * Tune.RETURN_BAR_STEPS) / Tune.RETURN_BAR_STEPS
	)
	results.IsReturnHeld(run.IsReturnHeld)
	results.Votes(run.Votes)
	results.VotesNeeded(run.VotesNeeded)
	results.HasVoted(run.HasVoted)
end

-- Whether the HUD is drawn. The upgrade cards are parts in the world, which a ScreenGui draws over: the HUD gives way to
-- them. The settings screen stands over the items, the wave and the hotbar, so the HUD gives way to it too. A boss's
-- intro fades it out (UiFade).
local function isHudUp(): boolean
	return not UpgradePickController.IsCovering() and not SettingsController.IsOpen() and UiFade.IsUp()
end

-- The squad screen can be opened over the upgrade cards (its own root, over theirs), so only the settings screen and a
-- boss's intro take it away.
local function isSquadUp(): boolean
	return not SettingsController.IsOpen() and UiFade.IsUp()
end

-- Runs the quest card on show, and brings up the next one waiting once it has gone, only while the HUD is drawn (a
-- quest finished as a wave clears lands under the upgrade pick, and waits for it).
local function updateQuest(dt: number)
	if not isHudUp() then return end
	questClock += dt
	local now = questClock
	local notice = state.Quest
	if now < questUntil then
		notice.Clock(now)
		return
	end
	if notice.Id() ~= 0 then
		notice.Clock(now)
		notice.Id(0)
	end

	local nextQuest = questQueue[1]
	if not nextQuest then return end
	table.remove(questQueue, 1)
	local hold = if questQueue[1] then QuestToast.SHORT_HOLD else QuestToast.HOLD
	questUntil = now + QuestToast.Seconds(hold)
	notice.Board(nextQuest[1])
	notice.Hold(hold)
	notice.At(now)
	notice.Clock(now)
	notice.Id(nextQuest[2])
end

-- The down's fields (DownedController), each written only as it changes, and the squadmates down for the chips.
local downedList: { Player } = {}
local function updateDown(now: number)
	local down = state.Down
	local isDown = state.IsDown()
	if down.At() ~= DownedController.DownAt then down.At(DownedController.DownAt) end
	if down.SwitchedAt() ~= DownedController.SwitchedAt then down.SwitchedAt(DownedController.SwitchedAt) end
	if down.RebuildAt() ~= DownedController.RebuildAt then down.RebuildAt(DownedController.RebuildAt) end
	if down.StoodAt() ~= DownedController.StoodAt then down.StoodAt(DownedController.StoodAt) end
	local isRebuilding = isDown and DownedController.RebuildAt > DownedController.DownAt
	if down.IsRebuilding() ~= isRebuilding then down.IsRebuilding(isRebuilding) end
	local watched = DownedController.Watched
	local name = if isDown and watched then watched.DisplayName else ""
	if down.Watched() ~= name then down.Watched(name) end
	if watched then
		local health, max = HealthController.HealthOf(watched)
		if down.WatchedHealth() ~= health then down.WatchedHealth(health) end
		if down.WatchedMax() ~= max then down.WatchedMax(max) end
	end
	if isDown or now - DownedController.StoodAt < Tune.DOWN_CLOCK_AFTER then down.Clock(now) end

	local count = 0
	local isChanged = false
	if MatchController.IsRunning then
		for _, player in Players:GetPlayers() do
			if player == LocalPlayer or not HealthController.IsPlayerDown(player) then continue end
			count += 1
			if downedList[count] ~= player then
				downedList[count] = player
				isChanged = true
			end
		end
	end
	for index = #downedList, count + 1, -1 do
		downedList[index] = nil
		isChanged = true
	end
	if isChanged then state.Downed(table.freeze(table.clone(downedList))) end
end

local function update(dt: number)
	local now = os.clock()
	local gameNow = TimeCore.GameClock
	local viewport = Workspace.CurrentCamera.ViewportSize
	state.Scale(math.clamp(viewport.Y / Theme.DESIGN_HEIGHT, Theme.MIN_SCALE, Theme.MAX_SCALE))
	updateRound(now, gameNow)
	updateBoss(now, dt)
	updateWallet(now, dt)
	updateVital(now)
	updateHealth(now, dt)
	updateDefenses(now)
	updateGun(now, updateWeapon(now))
	if chargeFlight then chargeFlight.Step(now) end
	updateAbilities(now, gameNow)
	updateSquad(now, dt)
	updateResults(now)
	updateQuest(dt)
	updateDown(now)
	if now < motionUntil or now < announceUntil then state.Now(now) end
	-- A prompted item breathes for as long as it asks, and a full ultimate for as long as it waits.
	if state.IsNukePrompted() or state.IsHealPrompted() or state.Ultimate.IsReady() then state.Breath(now) end
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

-- Opens the purchase prompt for `productId`. Opened from the results, the server is told for as long as it is up: the
-- countdown to the lobby waits, so nobody is sent away in the middle of paying.
local function prompt(productId: number)
	if productId == 0 then return end
	if MatchController.Results then
		isBuyingFromResults = true
		MatchController.SetBuying(true)
	end

	MarketplaceService:PromptProductPurchase(LocalPlayer, productId)
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
	UpgradeWeapon = WeaponRunController.Upgrade,
	UpgradeHealth = HealthController.Upgrade,
	CastAbility = AbilityController.Cast,
	Revive = function()
		prompt(EProducts.Revive)
	end,
	Spectate = DownedController.Spectate,
	QuickRevive = function(player: Player?)
		ClientNetworkCharacters.Revive.Fire(player or LocalPlayer)
	end,
	BuyProduct = function(productId: number)
		if productId ~= 0 then MarketplaceService:PromptProductPurchase(LocalPlayer, productId) end
	end,
	CloseSquad = function()
		if squadIcon then squadIcon:deselect() end
	end,
	PlayAgain = MatchController.VotePlayAgain,
	LeaveToLobby = MatchController.LeaveToLobby,
	WatchAd = MatchController.WatchAd,
	DoubleGems = function()
		local run = MatchController.Results
		if run then prompt(run.DoubleProductId) end
	end,
}

local function setSquadOpen(isOpen: boolean)
	state.IsSquadOpen(isOpen)
	stamp(state.SquadToggledAt, os.clock())
end

-- A top bar press keeps Now ticking until it has come back.
local function holdMotion(settledAt: number)
	motionUntil = math.max(motionUntil, settledAt)
end

-- The icons step aside while a cutscene hides every screen's UI.
local function isUiShown(): boolean
	return not UiFade.IsHidden()
end

-- The top bar's icons: SQUAD on the left with Roblox's own buttons, Settings in the right corner. Codes are the lobby's
-- alone.
local function createTopbarIcons()
	squadIcon = TopbarPlus.new()
	squadIcon
		:setName("Squad")
		:setImage(Icons.Pictures[EIcons.Squad].Image)
		:modifyTheme({ "IconImage", "ImageRectOffset", Icons.Pictures[EIcons.Squad].Offset })
		:modifyTheme({ "IconImage", "ImageRectSize", Icons.PICTURE_CELL_SIZE })
		:setLabel("SQUAD")
		:setTextFont(Theme.Font.Display.Family, Enum.FontWeight.Heavy)
		:bindEvent("selected", function()
			setSquadOpen(true)
		end)
		:bindEvent("deselected", function()
			setSquadOpen(false)
		end)

	Topbar.Dress(squadIcon, {
		IsSelected = state.IsSquadOpen,
		HasBrackets = true,
		Now = state.Now,
		OnPress = holdMotion,
		IsShown = isUiShown,
	})

	settingsIcon = TopbarPlus.new()
	settingsIcon
		:setName("Settings")
		:setImage(Icons.Pictures[EIcons.Gear].Image)
		:modifyTheme({ "IconImage", "ImageRectOffset", Icons.Pictures[EIcons.Gear].Offset })
		:modifyTheme({ "IconImage", "ImageRectSize", Icons.PICTURE_CELL_SIZE })
		:setCaption("Settings")
		:align("Right")
		:bindEvent("selected", SettingsController.Open)
		:bindEvent("deselected", SettingsController.Close)

	Topbar.Dress(settingsIcon, {
		IsSelected = SettingsController.IsOpen,
		HasBrackets = false,
		Now = state.Now,
		OnPress = holdMotion,
		IsShown = isUiShown,
	})
end

-- Puts the banner up: `buyer` used the item `kind` ("Nuke" or "Heal"); `count` is the bodies a nuke kills.
local function announce(kind: string, buyer: Player, count: number)
	local now = os.clock()
	announceUntil = now + Announce.SECONDS
	vide.batch(function()
		state.Announce.Kind(kind)
		state.Announce.Name(buyer.DisplayName)
		state.Announce.Count(count)
		state.Announce.At(now)
		state.Now(now)
	end)
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

MatchController.OnNukedAll:Connect(function(buyer: Player, _, bodies: number)
	announce("Nuke", buyer, bodies)
end)

MarketplaceService.PromptProductPurchaseFinished:Connect(function()
	if not isBuyingFromResults then return end
	isBuyingFromResults = false
	MatchController.SetBuying(false)
end)

-- A quest finished: its card waits its turn (updateQuest).
ServerNetworkQuests.Completed.On(function(board: number, questId: number)
	table.insert(questQueue, { board, questId })
end)

MatchController.OnHealedAll:Connect(function(buyer: Player)
	announce("Heal", buyer, 0)
end)

-- The local player's own pack: its stamp goes up over the money plate, in the handler so it is on the frame the
-- coins leave him.
MatchController.OnGoldBought:Connect(function(buyer: Player, amount: number)
	if buyer ~= LocalPlayer then return end
	local now = os.clock()
	motionUntil = math.max(motionUntil, now + Hotbar.GOLD_PACK_SECONDS)
	vide.batch(function()
		state.GoldPack.Amount(amount)
		state.GoldPack.At(now)
		state.Now(now)
	end)
end)

HudController.OnPlayerConnected = function(player: Player)
	squadMembers[player] = {
		Name = player.DisplayName,
		UserId = player.UserId,
		IsSelf = player == LocalPlayer,
		ClassName = source(DEFAULT_CLASS.Name),
		Kills = source(0),
		Deaths = source(0),
		Cash = source(0),
		KilledAt = source(-math.huge),
		DiedAt = source(-math.huge),
	}
	rebuildSquad()
end :: TPlayerEvents.OnPlayerConnected

HudController.OnPlayerDisconnected = function(player: Player)
	if not squadMembers[player] then return end
	squadMembers[player] = nil
	squadCash[player] = nil
	rebuildSquad()
end :: TPlayerEvents.OnPlayerDisconnected

-- The Decoy's card draws the avatar, in the doll's pose, once its clothes and hats are on it. Copied from the first
-- body only: the avatar never changes in a match, and a revived body comes in hidden on this client until it is built
-- out of its bricks (reviveFx), so a copy of it would draw nothing. Yields.
local function copyAvatar(character: Model)
	if state.Avatar() then return end
	if not LocalPlayer:HasAppearanceLoaded() then LocalPlayer.CharacterAppearanceLoaded:Wait() end
	if LocalPlayer.Character ~= character then return end
	local copy = AbilityPicture.Doll(character)
	if not copy then return end
	state.Avatar(copy)

	-- The results draw it too, arms folded, alone as on the card: the equipment may not have arrived yet.
	local folded = copyCharacter(character)
	if not folded then return end
	equipmentPieces.Strip(folded)
	AvatarPose.Apply(folded, AvatarPose.CROSSED)
	state.Results.Avatar(folded)
end

HudController.OnSelfCharacterAdded = function(character: TCharacter.TCharacter)
	state.Head(character.Head)
	selfHumanoid = character.Humanoid
	watchHeldTool(character)
	task.spawn(copyAvatar, character)
end :: TCharacterEvents.OnCharacterAdded

HudController.OnSelfCharacterRemoving = function()
	state.Head(nil)
	selfHumanoid = nil
	heldModel = nil
end :: TCharacterEvents.OnCharacterRemoving

-- One of the HUD's ScreenGuis, drawn while `isUp` says (isHudUp unless given). Any write in a ScreenGui lays out every visible element in it again
-- (performance/runui-2026-11-09), and the items' breathing and the wave's countdown write every frame of a prompt or a
-- countdown: kept in their own root, they relay ~120 elements instead of the whole HUD's ~340
-- (performance/optimization-2026-11-26). DisplayOrder paints the calm pieces, then the live ones (ZIndex 1 among
-- themselves but a prompted item's 3, Down over the wave), then the flights, banners and screens over everything. The
-- wave and the items now paint over the calm pieces instead of under them; they do not overlap them (rur diffs of
-- Hud.story, 62 of 62 identical).
local function hudRoot(
	name: string,
	displayOrder: number,
	pieces: { any },
	unscaled: { any }?,
	isUp: (() -> boolean)?
): ScreenGui
	return create("ScreenGui")({
		Name = name,
		ResetOnSpawn = false,
		DisplayOrder = displayOrder,
		Enabled = isUp or isHudUp,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		UiFade.Group({
			-- Scaled from a 1080-tall design: the root is sized 1 / scale so that after its UIScale it fills the screen.
			create("Frame")({
				Name = "Root",
				BackgroundTransparency = 1,
				Size = function()
					local scale = state.Scale()
					return UDim2.fromScale(1 / scale, 1 / scale)
				end,
				create("UIScale")({ Scale = state.Scale }),
				pieces,
			}),
			-- Pieces measured in screen px (GemPayout's layers), beside the scaled root.
			unscaled,
		}),
	})
end

HudController.OnStart = function()
	-- The HUD's own bar replaces the platform's, which would show the same number twice.
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	DebugInfoController.Track("ENEMIES", function(): number
		return EnemiesController.Count
	end)
	DebugInfoController.Track("COINS", CoinsController.InAir)
	DebugInfoController.SetClear(Shop.CORNER)

	createTopbarIcons()
	update(0)
	vide.mount(function()
		-- The debug readout gives way to the upgrade cards with the HUD (isHudUp).
		vide.effect(function()
			DebugInfoController.SetCovered(UpgradePickController.IsCovering())
		end)
		-- The settings screen shuts by its own X too: the icon is let go with it.
		vide.effect(function()
			if not SettingsController.IsOpen() and settingsIcon then settingsIcon:deselect() end
		end)
		vide.effect(function()
			UpgradePickController.IsOverlaid = state.IsSquadOpen() or SettingsController.IsOpen()
		end)

		-- Built in this order (each card's marks are drawn at random as it is built), then split by how often they are
		-- written (hudRoot).
		local wave = Wave.Build(state, actions)
		local items = Items.Build(state, actions)
		local announceBanner = Announce.Build(state)
		local upgrades = Upgrades.Build(state, actions)
		local abilitySlots, flight = Shop.Abilities(state, actions)
		chargeFlight = flight
		local hotbar = Hotbar.Build(state)
		local weaponUpgrade =
			WeaponUpgrade.Build(state, Upgrades.WEAPON_PICTURE, Upgrades.PICTURE_SIZE, Upgrades.PICTURE_TILT)
		local healthUpgrade = HealthUpgrade.Build(state, Upgrades.HEALTH_PICTURE, Upgrades.HEALTH_PICTURE_SIZE)
		local squad = Squad.Build(state, actions)
		local down = Down.Build(state, actions)
		-- The gold, the hotbar and the upgrade and ability columns step aside while down; so does everything about the
		-- fight (the wave plate, the boss bar, SKIP WAVE, HEAL ALL and NUKE ALL, the squad's banners), lifting off the
		-- top, and YOU DIED takes the wave plate's place. The top comes back as the body shows, so the wave plate drops
		-- back in as YOU DIED lifts out of its place. Out of the renderer once gone.
		local lowerShown = Hand.Spring(function()
			return if state.IsDown() then 0 else 1
		end, Tune.LOWER_PERIOD, 1)
		local fightShown = Hand.Spring(function()
			local downState = state.Down
			return if state.IsDown() and downState.StoodAt() < downState.At() then 0 else 1
		end, Tune.LOWER_PERIOD, 1)
		local function stepsAside(name: string, content: { any }): Frame
			return create("Frame")({
				Name = name,
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Visible = function()
					return fightShown() > 0.005
				end,
				Components.FadeGroup(name, fightShown, {
					Size = UDim2.fromScale(1, 1),
					Position = function()
						return UDim2.fromOffset(0, -math.round(Tune.FIGHT_LIFT * (1 - fightShown())))
					end,
				}, content),
			})
		end
		local results = Results.Build(state, actions)
		local questToast = QuestToast.Build(state)

		-- A list: mount keeps only the first value a component returns.
		return {
			hudRoot("Hud", HUD_DISPLAY_ORDERS.Base, {
				Components.FadeGroup(
					"Lower",
					lowerShown,
					{ Size = UDim2.fromScale(1, 1) },
					{ upgrades, abilitySlots, hotbar }
				),
			}),
			hudRoot("HudLive", HUD_DISPLAY_ORDERS.Live, { stepsAside("Fight", { wave, items }), down }),
			hudRoot(
				"HudTop",
				HUD_DISPLAY_ORDERS.Top,
				{ stepsAside("Banners", { announceBanner }), weaponUpgrade, healthUpgrade, questToast, results },
				{ if flight then flight.Layer else nil }
			),
			hudRoot("HudSquad", HUD_DISPLAY_ORDERS.Squad, { squad }, nil, isSquadUp),
			Overlays.Vignette(state),
			Overlays.Shock(state),
			Overhead.Build(state),
		}
	end, LocalPlayer:WaitForChild("PlayerGui"))

	RunService.PreRender:Connect(function(dt: number)
		frameDt = dt
		vide.batch(updateFrame)
	end)
end

-- The boss bar's marks for the guards holding its shield up.
BossController.OnShield:Connect(function(_, standing: number, total: number)
	state.Boss.Guards(standing)
	state.Boss.GuardsTotal(if standing > 0 then total else 0)
end)

return Ignis.Register(HudController)
