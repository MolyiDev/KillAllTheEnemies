-- The weapons screen (UIMatt.md, Weapons Shop): the four tiers, each tier's guns owned and not, the gun on the stage
-- and its numbers, and buying, raising, equipping and wearing one on the back (LoadoutService decides each; this asks
-- and shows). The lobby's WEAPONS slab opens it. While it is up the world behind is blurred and heard under water.
--
-- A purchase is shown in the order it is paid: the Gems leave the HUD's pill and fly into the gun (Flight), and only
-- as they land does the gun become owned on the screen. So a Sync that answers a purchase is held until then.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local vide = require(ReplicatedStorage.Packages.vide)
local NetworkMeta = require(StarterPlayer.StarterPlayerScripts.GlobalClient.NetworkMeta)
-- Through PlayerScripts, the copy that runs: requiring the StarterPlayer one would load a second controller.
local ProfileController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.ProfileController)
local BlurController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.BlurController)
local RangeController = require(script.Parent.RangeController)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local LoadoutCore = require(ReplicatedStorage.GlobalShared.Core.LoadoutCore)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local Parts = require(script.Parts)
local Screen = require(script.Screen)
local Types = require(script.Types)

local ServerNetworkLoadout = NetworkMeta.Server.Loadout
local ClientNetworkLoadout = NetworkMeta.Client.Loadout
local LocalPlayer = Players.LocalPlayer
local source = vide.source
local create = vide.create

local Tune = table.freeze({
	-- The screen is his 1920 x 1080, fitted inside the viewport whole.
	DESIGN = Vector2.new(1920, 1080),
	-- Above the lobby's HUD, under the settings screen.
	DISPLAY_ORDER = 5,
	-- It is drawn this long after it is shut, for its way out (Screen.LEAVE_SECONDS is shorter).
	LEAVE_SECONDS = 0.45,
	-- How long the clock keeps ticking after a stamp: the longest gesture is shorter.
	MOTION_SECONDS = 2.2,
	-- Where a purchase's Gems set off before the HUD's Gems glyph has been handed over: where it docks on a 1080 screen.
	GEMS_FROM = Vector2.new(1627, 44),
})

local WeaponsController = {}

local state: Types.TWeaponsState = {
	Scale = source(1),
	Now = source(os.clock()),
	StageClock = source(os.clock()),
	IsOpen = source(false),
	ToggledAt = source(-math.huge),
	Tier = source(1),
	TierAt = source(-math.huge),
	Selected = source(LoadoutCore.Starters[1].Id),
	SelectedAt = source(-math.huge),
	Levels = source({} :: { [number]: number }),
	Equipped = source({} :: { number }),
	Shown = source(0),
	ShownAt = source(-math.huge),
	ShownFor = source(0),
	Gems = source(0),
	Pending = source(nil :: Types.TRequest?),
	BoughtGun = source(0),
	BoughtAt = source(-math.huge),
	UpgradedGun = source(0),
	UpgradedAt = source(-math.huge),
	PaidAt = source(-math.huge),
	PaidFor = source("Buy" :: Types.TRequest),
	GemsFrom = source(Tune.GEMS_FROM),
	EquippedAt = source(-math.huge),
	RefusedAt = source(-math.huge),
}

-- os.clock until which Now keeps ticking.
local motionUntil = -math.huge
-- A Sync held until its purchase's Gems have landed, and the moment they land.
local heldSync: { Levels: { [number]: number }, Equipped: { number }, Shown: number }? = nil
local heldUntil = math.huge
-- The gun the pending press was made on: the hand may pick another before the answer comes.
local pendingGun = 0
-- The HUD's Gems glyph, where a purchase's Gems set off, and the screen's 1920 x 1080 they fly in.
local gemsTarget: GuiObject? = nil
local root: Frame? = nil

-- Whether the screen is up. Reads a vide source, so a view that calls it follows it.
function WeaponsController.IsOpen(): boolean
	return state.IsOpen()
end

-- The os.clock it last opened or shut at. Reads a vide source.
function WeaponsController.ToggledAt(): number
	return state.ToggledAt()
end

-- Whether the Gems held buy a gun not owned yet or raise one that is: the WEAPONS slab wears the up arrow. Reads vide
-- sources.
function WeaponsController.CanUpgrade(): boolean
	return Parts.HasOffer(state, DataCore.Guns.All)
end

-- Where a purchase's Gems set off: the glyph on the HUD's Gems counter.
function WeaponsController.SetGemsTarget(glyph: GuiObject)
	gemsTarget = glyph
end

local function stir(seconds: number)
	motionUntil = math.max(motionUntil, os.clock() + seconds)
end

-- Stamps a gesture's start and keeps Now ticking for it. `at` may be a moment still to come.
local function stamp(at: Types.Source<number>, moment: number)
	at(moment)
	motionUntil = math.max(motionUntil, moment + Tune.MOTION_SECONDS)
end

local function selectGun(gunId: number)
	if state.Selected() == gunId then return end
	vide.batch(function()
		state.Selected(gunId)
		stamp(state.SelectedAt, os.clock())
	end)
end

local function pickTier(tier: number)
	if state.Tier() == tier and state.TierAt() > -math.huge then return end
	vide.batch(function()
		state.Tier(tier)
		stamp(state.TierAt, os.clock())
		selectGun(state.Equipped()[tier] or LoadoutCore.Starters[tier].Id)
	end)
end

function WeaponsController.Open()
	if state.IsOpen() then return end
	vide.batch(function()
		state.IsOpen(true)
		stamp(state.ToggledAt, os.clock())
		-- It opens where it was left, on the gun that tier holds now.
		local tier = state.Tier()
		state.Selected(state.Equipped()[tier] or LoadoutCore.Starters[tier].Id)
	end)
	SoundsCore.SetMuffled("Weapons", true)
	BlurController.SetBlurred("Weapons", true)
end

function WeaponsController.Close()
	if not state.IsOpen() then return end
	state.IsOpen(false)
	stamp(state.ToggledAt, os.clock())
	SoundsCore.SetMuffled("Weapons", false)
	BlurController.SetBlurred("Weapons", false)
end

local function refuse()
	stamp(state.RefusedAt, os.clock())
	SoundsCore.PlayUINamed("UI.UpgradePick", "Denied")
end

local function selectedGun()
	return DataCore.Guns.ById[state.Selected()]
end

local actions: Types.TWeaponsActions = {
	Close = WeaponsController.Close,
	PickTier = pickTier,
	Select = selectGun,
	-- Each press is checked here first only to answer at once: the server checks it again.
	Buy = function()
		local gun = selectedGun()
		if state.Pending() or not gun or state.Levels()[gun.Id] then return end
		if state.Gems() < gun.Price then
			refuse()
			return
		end
		state.Pending("Buy")
		pendingGun = gun.Id
		ClientNetworkLoadout.Buy.Fire(gun.Id)
	end,
	Upgrade = function()
		local gun = selectedGun()
		local level = if gun then state.Levels()[gun.Id] else nil
		if state.Pending() or not gun or not level then return end
		local cost = LoadoutCore.UpgradeCost(gun, level)
		if not cost then return end
		if state.Gems() < cost then
			refuse()
			return
		end
		state.Pending("Upgrade")
		pendingGun = gun.Id
		ClientNetworkLoadout.Upgrade.Fire(gun.Id)
	end,
	Equip = function()
		local gun = selectedGun()
		if state.Pending() or not gun or not state.Levels()[gun.Id] then return end
		if state.Equipped()[gun.Tier] == gun.Id then return end
		state.Pending("Equip")
		pendingGun = gun.Id
		ClientNetworkLoadout.Equip.Fire(gun.Id)
	end,
	Show = function()
		local gun = selectedGun()
		if state.Pending() or not gun then return end
		if not state.Levels()[gun.Id] then
			refuse()
			return
		end
		state.Pending("Show")
		pendingGun = gun.Id
		ClientNetworkLoadout.Show.Fire(if state.Shown() == gun.Id then 0 else gun.Id)
	end,
	Try = function()
		local gun = selectedGun()
		if not gun then return end
		WeaponsController.Close()
		RangeController.Try(gun.Id)
	end,
	Stir = stir,
}

local function apply(levels: { [number]: number }, equipped: { number }, shown: number)
	state.Levels(levels)
	state.Equipped(equipped)
	state.Shown(shown)
end

-- A purchase's Gems set off now, from where the HUD's glyph stands: both are measured from under the top bar, so the
-- difference is the glyph's place in the screen's 1920 x 1080 however the two guis are scaled.
local function pay(kind: Types.TRequest, now: number)
	local glyph, page = gemsTarget, root
	if glyph and glyph.Parent and page then
		state.GemsFrom((glyph.AbsolutePosition + glyph.AbsoluteSize / 2 - page.AbsolutePosition) / state.Scale())
	end
	state.PaidFor(kind)
	stamp(state.PaidAt, now)
end

-- The answer to whatever was pending, as a gesture: what changed for the selected gun.
local function answer(levels: { [number]: number }, equipped: { number }, shown: number)
	local pending = state.Pending()
	state.Pending(nil)
	local gun = DataCore.Guns.ById[pendingGun]
	if not pending or not gun then
		apply(levels, equipped, shown)
		return
	end

	local now = os.clock()
	local before = state.Levels()[gun.Id]
	local after = levels[gun.Id]
	if pending == "Buy" and not before and after then
		pay("Buy", now)
		state.BoughtGun(gun.Id)
		heldUntil = now + Screen.FLIGHT_SECONDS
		stamp(state.BoughtAt, heldUntil)
		stamp(state.EquippedAt, heldUntil)
		heldSync = { Levels = levels, Equipped = equipped, Shown = shown }
	elseif pending == "Upgrade" and before and after and after > before then
		pay("Upgrade", now)
		state.UpgradedGun(gun.Id)
		heldUntil = now + Screen.FLIGHT_SECONDS
		stamp(state.UpgradedAt, heldUntil)
		heldSync = { Levels = levels, Equipped = equipped, Shown = shown }
	elseif pending == "Equip" and equipped[gun.Tier] == gun.Id then
		apply(levels, equipped, shown)
		stamp(state.EquippedAt, now)
		SoundsCore.PlayClick()
	elseif pending == "Show" and shown ~= state.Shown() then
		apply(levels, equipped, shown)
		state.ShownFor(gun.Id)
		stamp(state.ShownAt, now)
		SoundsCore.PlayClick()
	else
		apply(levels, equipped, shown)
		refuse()
	end
end

local function updateScale()
	local viewport = Workspace.CurrentCamera.ViewportSize
	state.Scale(math.max(math.min(viewport.Y / Tune.DESIGN.Y, viewport.X / Tune.DESIGN.X), 0.01))
end

WeaponsController.OnStart = function()
	state.Gems(ProfileController.Gems)
	ProfileController.OnChanged:Connect(function()
		state.Gems(ProfileController.Gems)
	end)

	vide.mount(function()
		-- Drawn only while it is up or still leaving: shut, the screen costs nothing.
		local isDrawn = vide.derive(function(): boolean
			return state.IsOpen() or state.Now() - state.ToggledAt() < Tune.LEAVE_SECONDS
		end)
		-- His 1920 x 1080, scaled whole into the middle of the screen.
		root = create("Frame")({
			Name = "Root",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(Tune.DESIGN.X, Tune.DESIGN.Y),
			BackgroundTransparency = 1,
			create("UIScale")({ Scale = state.Scale }),
			Screen.Build(state, actions),
		})

		return create("ScreenGui")({
			Name = "Weapons",
			ResetOnSpawn = false,
			IgnoreGuiInset = true,
			ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			DisplayOrder = Tune.DISPLAY_ORDER,
			Enabled = isDrawn,
			root,
		})
	end, LocalPlayer:WaitForChild("PlayerGui"))

	-- Now is written only while something moves, so a screen at rest, open or shut, redraws nothing.
	RunService.PreRender:Connect(function()
		local now = os.clock()
		if heldSync and now >= heldUntil then
			local held = heldSync
			heldSync = nil
			apply(held.Levels, held.Equipped, held.Shown)
		end
		if now < motionUntil then state.Now(now) end
		if state.IsOpen() or now - state.ToggledAt() < Tune.LEAVE_SECONDS then state.StageClock(now) end
	end)

	local camera = Workspace.CurrentCamera
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	updateScale()
end

ServerNetworkLoadout.Sync.On(function(owned: { number }, levels: { number }, equipped: { number }, shown: number)
	local byId = {}
	for index, gunId in owned do
		byId[gunId] = levels[index]
	end

	-- A Sync while an earlier one is still held replaces it: the newer one is the truth.
	if heldSync then
		heldSync = nil
		heldUntil = math.huge
	end
	vide.batch(function()
		answer(byId, equipped, shown)
	end)
end)

return Ignis.Register(WeaponsController)
