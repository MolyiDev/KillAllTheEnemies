-- The lobby's screen (GDD 3): the designer's HUD (Hud), every pad's colour and board, EXIT and the queue's status,
-- the host's party menu, the classes screen (Classes), and opening the weapons, index, daily rewards and quests
-- screens (WeaponsController, IndexController, DailyRewardsController, QuestsController). The server decides
-- everything (LobbyService); this draws what it is told and sends requests.
-- A pad's green or red is this player's own answer to "could I step on now", which is why it is drawn here.
--
-- A countdown is sent as seconds left at the moment of a change and counted down here, so the server only sends on a
-- change rather than every second.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")
local StarterPlayer = game:GetService("StarterPlayer")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local vide = require(ReplicatedStorage.Packages.vide)
local NetworkMeta = require(StarterPlayer.StarterPlayerScripts.GlobalClient.NetworkMeta)
-- Through PlayerScripts, the copy that runs: requiring the StarterPlayer one would load a second controller.
local SettingsController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.SettingsController)
local CodesController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.CodesController)
local CrosshairController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.CrosshairController)
local MusicController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.MusicController)
local CameraController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.CameraController)
local ProfileController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.ProfileController)
local BlurController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.BlurController)
local PlayerModule = require(Players.LocalPlayer.PlayerScripts:WaitForChild("PlayerModule") :: ModuleScript) :: any
local TopbarPlus = require(ReplicatedStorage.GlobalShared.TopbarPlus)
local AbilitiesCore = require(ReplicatedStorage.GlobalShared.Core.AbilitiesCore)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local Icons = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Icons)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local Topbar = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Topbar)
local MapsCore = require(ReplicatedStorage.GlobalShared.Core.MapsCore)
local PadsCore = require(ReplicatedStorage.Shared.Core.PadsCore)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local copyCharacter = require(StarterPlayer.StarterPlayerScripts.GlobalClient.Utils.copyCharacter)
local AbilityPicture = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.AbilityPicture)
local Bar = require(script.Bar)
local Classes = require(script.Classes)
local WeaponsController = require(script.Parent.WeaponsController)
local IndexController = require(script.Parent.IndexController)
local DailyRewardsController = require(script.Parent.DailyRewardsController)
local LobbyEnteringController = require(script.Parent.LobbyEnteringController)
local SpinsController = require(script.Parent.SpinsController)
local QuestsController = require(script.Parent.QuestsController)
local RangeController = require(script.Parent.RangeController)
local Hud = require(script.Hud)
local Menu = require(script.Menu)
local PadArt = require(script.PadArt)
local PadBoard = require(script.PadBoard)
local Types = require(script.Types)

local ServerNetworkLobby = NetworkMeta.Server.Lobby
local ClientNetworkLobby = NetworkMeta.Client.Lobby
local ServerNetworkClasses = NetworkMeta.Server.Classes
local ClientNetworkClasses = NetworkMeta.Client.Classes

local LocalPlayer = Players.LocalPlayer
local source = vide.source
local create = vide.create
local EPhase = PadsCore.EPhase
local ERefusal = PadsCore.ERefusal

local TOAST_SECONDS = 3
-- The HUD slides in this long after the lobby is up, so the first frames' hitches are behind it; the profile's
-- numbers roll in once the pieces they stand on have landed.
local ENTER_DELAY = 0.3
local ROLL_DELAY = 0.55
local MUSIC_FADE_SECONDS = 4
-- While today's daily reward waits, or the index has a discovery to show, the light crosses the card calling for it
-- this often; the daily rewards screen also opens by itself once a lobby visit, as soon as nothing else is up.
local DAILY_CALL_SECONDS = 2.6
local DAILY_CALL_SHEEN = 0.7
-- The light catches the Gems counter's stone this often while nothing covers the whole view.
local GEM_GLINT_SECONDS = 4.5
-- A pad this player may step on, and one he may not. The Theme's Action and Boss, so the pads and the menu agree.
local OPEN_COLOR = Theme.Color.Action
local CLOSED_COLOR = Theme.Color.Boss

type TPadState = {
	Phase: number,
	Count: number,
	MaxPlayers: number,
	Map: number,
	IsFriendsOnly: boolean,
	HostId: number,
}

local LobbyController = {}

local pads: { Types.TPadView } = {}
-- os.clock() each pad's countdown ends at, or nil.
local endsAt: { [number]: number? } = {}
-- The last PadState per pad: the server sends them on joining, which can be before the pads' views exist.
local latest: { [number]: TPadState } = {}
local arts: { [number]: PadArt.TPadArt } = {}
-- Host UserId -> whether he is this player's friend, for friends-only pads. Fetched once each: it is a web call.
local isFriendOf: { [number]: boolean } = {}
local isFriendFetching: { [number]: boolean } = {}
local toastThread: thread? = nil

local state: Types.TLobbyState = {
	Scale = source(1),
	TopInset = source(0),
	Pads = pads,
	CurrentPad = source(0),
	IsChoosing = source(false),
	BestByMap = source({} :: { [string]: number }),
	PickPlayers = source(PadsCore.DEFAULT_PLAYERS),
	PickDifficulty = source(MapsCore.DIFFICULTIES[1]),
	PickMap = source(1),
	PickFriendsOnly = source(false),
	ToastText = source(""),
	IsToastShown = source(false),
	Now = source(os.clock()),
	EnteredAt = source(math.huge),
	XpFrom = source(0),
	XpTo = source(0),
	XpAt = source(-math.huge),
	GemsFrom = source(0),
	GemsTo = source(0),
	GemsAt = source(-math.huge),
	GemsHeld = source(0),
	XpHeld = source(0),
	IsGemsFed = source(false),
	GemGlintAt = source(-math.huge),
	IsGemsDocked = source(false),
	IsDailyReady = source(false),
	IsIndexNew = source(false),
	CallAt = source(-math.huge),
	HeldKey = source(nil :: Enum.KeyCode?),
	IsCovered = source(false),
	CoveredAt = source(-math.huge),
	IsBare = source(false),
	BareAt = source(-math.huge),
	IsClassesOpen = source(false),
	ClassesToggledAt = source(-math.huge),
	ShownAbility = source(1),
	AbilityPickedAt = source(-math.huge),
	ClassLevels = source({} :: { [number]: { number } }),
	Gems = source(0),
	IsUpgrading = source(false),
	UpgradePaidAt = source(-math.huge),
	UpgradedAt = source(-math.huge),
	UpgradeRefusedAt = source(-math.huge),
	GemsGlyph = source(nil :: GuiObject?),
	Avatar = source(nil :: Model?),
	Doll = source(nil :: Model?),
}

-- os.clock until which Now keeps ticking.
local motionUntil = -math.huge
local isProfileShown = false
-- The ability upgrade asked for, and its level then: the answer is a Sync, granted when that level rose.
local pendingUpgrade: { Class: number, Slot: number, Level: number }? = nil
-- A granted upgrade's levels, held until its Gems have flown into the star (state.UpgradedAt).
local heldLevels: { [number]: { number } }? = nil
local nextDailyCall = math.huge
local nextGemGlint = math.huge
local hasOpenedDaily = false

-- Keeps Now ticking until os.clock reaches `moment`.
local function stir(moment: number)
	motionUntil = math.max(motionUntil, moment)
end

-- Rolls the HUD's level and Gems to the profile's. The first time, the bar fills from the start of the level and the
-- Gems count up from 0, after the HUD has landed; after that each rolls on from where it stands.
local function showProfile()
	local now = os.clock()
	local xp = ProfileController.Level + (ProfileController.Xp - state.XpHeld()) / 100
	local at = math.max(now, state.EnteredAt() + ROLL_DELAY)
	vide.batch(function()
		if isProfileShown then
			state.XpFrom(Hud.Rolled(state.XpFrom(), state.XpTo(), state.XpAt(), now))
			state.GemsFrom(Hud.Rolled(state.GemsFrom(), state.GemsTo(), state.GemsAt(), now))
		else
			state.XpFrom(ProfileController.Level)
			state.GemsFrom(0)
		end
		state.XpTo(xp)
		state.XpAt(at)
		state.GemsTo(ProfileController.Gems - state.GemsHeld())
		state.GemsAt(at)
		state.Gems(ProfileController.Gems)
	end)
	isProfileShown = true
	stir(at + Hud.ROLL_SECONDS)
end

-- The Gems a screen is flying into the pill: held back, then shown exactly as each slice lands, since the landings
-- are the motion. A screen's claim arrives after the Sync that paid it, so the hold puts the pill back where it was.
local function holdGems(held: number, isFed: boolean)
	state.IsGemsFed(isFed)
	if held == state.GemsHeld() then return end
	local shown = ProfileController.Gems - held
	vide.batch(function()
		state.GemsHeld(held)
		state.GemsFrom(shown)
		state.GemsTo(shown)
		state.GemsAt(-math.huge)
	end)
end

local function isScreenUp(): boolean
	return state.IsClassesOpen()
		or WeaponsController.IsOpen()
		or IndexController.IsOpen()
		or DailyRewardsController.IsOpen()
		or QuestsController.IsOpen()
		or LobbyEnteringController.IsOpen()
end

-- The body walks only off a pad (the server anchors it there, which stops it but not its stride) and while no screen
-- covers the lobby.
local function updateControls()
	PlayerModule:GetControls()
		:Enable(state.CurrentPad() == 0 and not state.IsCovered() and not SpinsController.IsOpen())
end

-- Whether a screen covers the lobby now, stamped as that changes, so the HUD steps aside and comes back.
local function updateCover()
	local isCovered = isScreenUp()
	local isBare = LobbyEnteringController.IsOpen()
	local isDocked = state.IsClassesOpen() or WeaponsController.IsOpen()
	if state.IsGemsDocked() ~= isDocked then state.IsGemsDocked(isDocked) end
	if state.IsBare() ~= isBare then
		local now = os.clock()
		vide.batch(function()
			state.IsBare(isBare)
			state.BareAt(now)
		end)
		stir(now + Classes.SETTLE_SECONDS)
	end

	if state.IsCovered() == isCovered then return end
	local now = os.clock()
	vide.batch(function()
		state.IsCovered(isCovered)
		state.CoveredAt(now)
		state.HeldKey(nil)
	end)
	stir(now + Classes.SETTLE_SECONDS)
	updateControls()
end

-- Swaps `copy` into `slot`, destroying the copy it held.
local function replaceCopy(slot: vide.Source<Model?>, copy: Model?)
	if not copy then return end
	local old = slot()
	slot(copy)
	if old then old:Destroy() end
end

-- Fresh copies of the avatar for the classes screen, as it looks now: on its stage, and as the Decoy's doll.
local function takeAvatar()
	local character = LocalPlayer.Character
	if not character then return end
	replaceCopy(state.Avatar, copyCharacter(character))
	replaceCopy(state.Doll, AbilityPicture.Doll(character))
end

local function setClassesOpen(isOpen: boolean)
	if state.IsClassesOpen() == isOpen then return end
	if isOpen then takeAvatar() end
	local now = os.clock()
	vide.batch(function()
		state.IsClassesOpen(isOpen)
		state.ClassesToggledAt(now)
	end)
	stir(now + Classes.SETTLE_SECONDS)
	updateCover()
	SoundsCore.SetMuffled("Classes", isOpen)
	BlurController.SetBlurred("Classes", isOpen)
	SoundsCore.PlayUINamed("UI", if isOpen then "MenuIn" else "MenuOut")
end

local function showToast(text: string)
	state.ToastText(text)
	state.IsToastShown(true)
	if toastThread then task.cancel(toastThread) end
	toastThread = task.delay(TOAST_SECONDS, function()
		toastThread = nil
		state.IsToastShown(false)
	end)
end

local function updateChoosing()
	local padState = latest[state.CurrentPad()]
	local isChoosing = padState ~= nil and padState.Phase == EPhase.Choosing and padState.HostId == LocalPlayer.UserId
	state.IsChoosing(isChoosing)
end

-- Whether this player could step on the pad right now; the server's canJoin decides it for real.
local function isOpenToMe(index: number): boolean
	if state.CurrentPad() == index then return true end
	local padState = latest[index]
	if not padState then return false end
	if padState.Phase == EPhase.Empty then return state.CurrentPad() == 0 end
	if padState.Phase ~= EPhase.Open or padState.Count >= padState.MaxPlayers then return false end

	local map = MapsCore.LIST[padState.Map]
	if not map or not MapsCore.IsUnlockedBy(map, state.BestByMap()) then return false end
	if padState.IsFriendsOnly and padState.HostId ~= LocalPlayer.UserId then
		return isFriendOf[padState.HostId] == true
	end

	return true
end

local function tintPads()
	for index, art in arts do
		PadArt.Tint(art, if isOpenToMe(index) then OPEN_COLOR else CLOSED_COLOR)
	end
end

local function fetchFriendship(hostId: number)
	if hostId == 0 or isFriendOf[hostId] ~= nil or isFriendFetching[hostId] then return end
	isFriendFetching[hostId] = true
	task.spawn(function()
		local ok, result = pcall(LocalPlayer.IsFriendsWithAsync, LocalPlayer, hostId)
		isFriendFetching[hostId] = nil
		isFriendOf[hostId] = ok and result == true
		tintPads()
	end)
end

local function pickDifficulty(difficulty: string)
	state.PickDifficulty(difficulty)
	for index, map in MapsCore.LIST do
		if map.Difficulty ~= difficulty then continue end
		state.PickMap(index)
		return
	end
end

local function refuseUpgrade()
	local now = os.clock()
	state.UpgradeRefusedAt(now)
	stir(now + Classes.SETTLE_SECONDS)
	SoundsCore.PlayUINamed("UI.UpgradePick", "Denied")
end

-- Checked here first only to answer at once: the server checks it again. One at a time, the last one's Gems landed.
local function upgradeAbility(classId: number, slot: number)
	if state.IsUpgrading() then return end
	local class = DataCore.Classes.ById[classId]
	if not class or not AbilitiesCore.AbilityAt(class, slot) then return end
	local levels = state.ClassLevels()[classId]
	local level = if levels then levels[slot] or 1 else 1
	local cost = AbilitiesCore.UpgradeCost(level)
	if not cost then return end
	if state.Gems() < cost then
		refuseUpgrade()
		return
	end

	pendingUpgrade = { Class = classId, Slot = slot, Level = level }
	state.IsUpgrading(true)
	ClientNetworkClasses.Upgrade.Fire(classId, slot)
end

local actions: Types.TLobbyActions = {
	Play = function()
		ClientNetworkLobby.Play.Fire()
	end,
	Leave = function()
		ClientNetworkLobby.LeavePad.Fire()
	end,
	StartParty = function()
		local map = MapsCore.LIST[state.PickMap()]
		if not map or not MapsCore.IsUnlockedBy(map, state.BestByMap()) then return end
		ClientNetworkLobby.StartParty.Fire(state.PickPlayers(), state.PickMap(), state.PickFriendsOnly())
	end,
	PickDifficulty = pickDifficulty,
	PickMap = function(index: number)
		local map = MapsCore.LIST[index]
		if not map then return end
		state.PickMap(index)
		state.PickDifficulty(map.Difficulty)
	end,
	InviteFriends = function()
		task.spawn(function()
			local ok, canInvite = pcall(SocialService.CanSendGameInviteAsync, SocialService, LocalPlayer)
			if ok and canInvite then SocialService:PromptGameInvite(LocalPlayer) end
		end)
	end,
	OpenClasses = function()
		setClassesOpen(true)
	end,
	OpenWeapons = function()
		WeaponsController.Open()
	end,
	OpenDailyRewards = function()
		DailyRewardsController.Open()
	end,
	OpenSpins = function()
		SpinsController.Open()
	end,
	OpenQuests = function()
		QuestsController.Open()
	end,
	OpenIndex = function()
		IndexController.Open()
	end,
	MarkGemsGlyph = function(glyph: GuiObject)
		state.GemsGlyph(glyph)
		DailyRewardsController.SetGemsTarget(glyph)
		SpinsController.SetGemsTarget(glyph)
		QuestsController.SetGemsTarget(glyph)
		CodesController.SetGemsTarget(glyph)
	end,
	CloseClasses = function()
		setClassesOpen(false)
	end,
	PickAbility = function(index: number)
		local now = os.clock()
		vide.batch(function()
			state.ShownAbility(index)
			state.AbilityPickedAt(now)
		end)
		stir(now + Classes.SETTLE_SECONDS)
	end,
	UpgradeAbility = upgradeAbility,
}

local function updateScale()
	local viewport = Workspace.CurrentCamera.ViewportSize
	local inset = GuiService:GetGuiInset().Y
	state.TopInset(inset)
	state.Scale(math.clamp((viewport.Y - inset) / Theme.DESIGN_HEIGHT, Theme.MIN_SCALE, Theme.MAX_SCALE))
end

local function update()
	local now = os.clock()
	if now < motionUntil then state.Now(now) end
	if heldLevels and now >= state.UpgradedAt() then
		state.ClassLevels(heldLevels)
		state.IsUpgrading(false)
		heldLevels = nil
	end
	if now >= nextDailyCall and (state.IsDailyReady() or state.IsIndexNew()) and not state.IsCovered() then
		if state.IsDailyReady() and not hasOpenedDaily and state.CurrentPad() == 0 then
			hasOpenedDaily = true
			DailyRewardsController.Open()
		end
		nextDailyCall = now + DAILY_CALL_SECONDS
		state.CallAt(now)
		stir(now + DAILY_CALL_SHEEN)
	end
	if now >= nextGemGlint then
		nextGemGlint = now + GEM_GLINT_SECONDS
		if not state.IsBare() then state.GemGlintAt(now) end
	end
	for index, pad in pads do
		local ending = endsAt[index]
		pad.Seconds(if ending then math.ceil(math.max(ending - now, 0)) else -1)
	end
end

local function applyPad(index: number)
	local pad = pads[index]
	local padState = latest[index]
	if not pad or not padState then return end
	pad.Phase(padState.Phase)
	pad.Count(padState.Count)
	pad.MaxPlayers(padState.MaxPlayers)
	pad.Map(padState.Map)
	pad.IsFriendsOnly(padState.IsFriendsOnly)
end

ServerNetworkLobby.PadState.On(
	function(
		index: number,
		phase: number,
		count: number,
		maxPlayers: number,
		map: number,
		isFriendsOnly: boolean,
		hostId: number,
		seconds: number
	)
		latest[index] = {
			Phase = phase,
			Count = count,
			MaxPlayers = maxPlayers,
			Map = map,
			IsFriendsOnly = isFriendsOnly,
			HostId = hostId,
		}
		endsAt[index] = if seconds >= 0 then os.clock() + seconds else nil
		if isFriendsOnly then fetchFriendship(hostId) end
		vide.batch(function()
			applyPad(index)
			update()
			updateChoosing()
		end)
		tintPads()
	end
)

-- Whether the top bar's Codes and Settings are up: they step aside while the Gems counter is docked on the classes or
-- weapons page. Roblox draws them at a fixed size in px while the page scales, so on a smaller screen they would sit on
-- the counter, and moving the counter would take it off the panel and the tabs it lines up with. Reads a vide source.
local function isTopbarShown(): boolean
	return not state.IsGemsDocked()
end

ServerNetworkLobby.PadJoined.On(function(index: number)
	state.CurrentPad(index)
	updateControls()
	updateChoosing()
	tintPads()
end)

ServerNetworkLobby.PadRefused.On(function(index: number, reason: number)
	if reason == ERefusal.NoFreePad then
		showToast("Every pad is busy. Try again in a moment.")
		return
	end

	local pad = pads[index]
	local map = if pad then MapsCore.LIST[pad.Map()] else nil
	if reason == ERefusal.Locked and map then
		showToast(`Locked: {MapsCore.RequirementText(map)}`)
	elseif reason == ERefusal.FriendsOnly then
		showToast("This party is for the host's friends only.")
	end
end)

-- Every Upgrade is answered with one, a refused one too.
ServerNetworkClasses.Sync.On(function(classes: { { Class: number, Levels: { number } } })
	local byClass = {}
	for _, entry in classes do
		byClass[entry.Class] = entry.Levels
	end

	local pending = pendingUpgrade
	pendingUpgrade = nil
	local levels = if pending then byClass[pending.Class] else nil
	local isGranted = pending ~= nil and levels ~= nil and (levels[pending.Slot] or 1) > pending.Level
	-- Granted, the level is shown only as its Gems land in its star (Classes' Flight, which sounds the landings).
	if isGranted then
		local now = os.clock()
		local landsAt = now + Classes.FLIGHT_SECONDS
		heldLevels = byClass
		vide.batch(function()
			state.UpgradePaidAt(now)
			state.UpgradedAt(landsAt)
		end)
		stir(landsAt + Classes.SETTLE_SECONDS)
		return
	end

	-- A Sync while a level is held is the newer truth: it replaces it.
	heldLevels = nil
	vide.batch(function()
		state.ClassLevels(byClass)
		state.IsUpgrading(false)
	end)
	if pending then refuseUpgrade() end
end)

ServerNetworkLobby.MapRecords.On(function(bests: { number })
	local byName = {}
	for index, map in MapsCore.LIST do
		byName[map.Name] = bests[index] or 0
	end

	state.BestByMap(byName)
	tintPads()
end)

LobbyController.OnStart = function()
	CameraController.UseRobloxMouse()

	for index, part in PadsCore.GetPads() do
		pads[index] = {
			Index = index,
			Part = part,
			Phase = source(EPhase.Empty),
			Count = source(0),
			MaxPlayers = source(PadsCore.DEFAULT_PLAYERS),
			Map = source(1),
			IsFriendsOnly = source(false),
			Seconds = source(-1),
		}
		applyPad(index)
	end

	-- Local only: each player sees his own colours, and the server's Workspace stays the pads alone.
	local artFolder = Instance.new("Folder")
	artFolder.Name = "PadArt"
	artFolder.Parent = Workspace
	for index, pad in pads do
		arts[index] = PadArt.Build(pad.Part, artFolder)
	end

	updateScale()
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(updateScale)
	update()
	updateChoosing()
	tintPads()
	MusicController.SetLevel("Lobby", 1, MUSIC_FADE_SECONDS)
	-- Codes is made first, so it stands left of Settings. Both are modal over the same spot: opening one shuts the
	-- other.
	local codesIcon = TopbarPlus.new()
	codesIcon
		:setName("Codes")
		:setImage(Icons.IMAGE)
		:modifyTheme({ "IconImage", "ImageRectOffset", Icons.Cells.Ticket })
		:modifyTheme({ "IconImage", "ImageRectSize", Icons.CELL_SIZE })
		:setCaption("Codes")
		:align("Right")
		:bindEvent("selected", function()
			SettingsController.Close()
			CodesController.Open()
		end)
		:bindEvent("deselected", CodesController.Close)
	Topbar.Dress(codesIcon, {
		IsSelected = CodesController.IsOpen,
		HasBrackets = false,
		Now = state.Now,
		OnPress = stir,
		IsShown = isTopbarShown,
	})
	local settingsIcon = TopbarPlus.new()
	settingsIcon
		:setName("Settings")
		:setImage(Icons.IMAGE)
		:modifyTheme({ "IconImage", "ImageRectOffset", Icons.Cells.Settings })
		:modifyTheme({ "IconImage", "ImageRectSize", Icons.CELL_SIZE })
		:setCaption("Settings")
		:align("Right")
		:bindEvent("selected", function()
			CodesController.Close()
			SettingsController.Open()
		end)
		:bindEvent("deselected", SettingsController.Close)
	Topbar.Dress(settingsIcon, {
		IsSelected = SettingsController.IsOpen,
		HasBrackets = false,
		Now = state.Now,
		OnPress = stir,
		IsShown = isTopbarShown,
	})

	state.EnteredAt(os.clock() + ENTER_DELAY)
	stir(state.EnteredAt() + Hud.ARRIVE_SECONDS)
	nextDailyCall = state.EnteredAt() + Hud.ARRIVE_SECONDS
	nextGemGlint = state.EnteredAt() + Hud.ARRIVE_SECONDS + GEM_GLINT_SECONDS
	if ProfileController.IsLoaded then showProfile() end
	ProfileController.OnChanged:Connect(showProfile)

	-- A key a text box took (chat) is typing, not a press; and a screen over the lobby covers the HUD's keys.
	UserInputService.InputBegan:Connect(function(input: InputObject, isProcessed: boolean)
		if isProcessed or input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		if state.IsCovered() or SpinsController.IsOpen() then return end
		state.HeldKey(input.KeyCode)
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if state.HeldKey() == input.KeyCode then state.HeldKey(nil) end
	end)

	vide.mount(function()
		-- The settings screen shuts by its own X too: the icon is let go with it.
		vide.effect(function()
			if not SettingsController.IsOpen() then settingsIcon:deselect() end
		end)
		vide.effect(function()
			if not CodesController.IsOpen() then codesIcon:deselect() end
		end)
		vide.effect(function()
			WeaponsController.IsOpen()
			IndexController.IsOpen()
			DailyRewardsController.IsOpen()
			QuestsController.IsOpen()
			LobbyEnteringController.IsOpen()
			vide.untrack(updateCover)
		end)
		-- In the shooting range the gun's crosshair takes the pointer's place, as in a match; anywhere else, and over
		-- any screen, the lobby keeps Roblox's pointer.
		vide.effect(function()
			local isAiming = RangeController.IsInside()
				and not isScreenUp()
				and not SpinsController.IsOpen()
				and not SettingsController.IsOpen()
				and not CodesController.IsOpen()
			CrosshairController.SetShown(isAiming)
		end)
		vide.effect(function()
			state.IsDailyReady(DailyRewardsController.IsClaimable())
		end)
		vide.effect(function()
			state.IsIndexNew(IndexController.HasNew())
		end)
		vide.effect(function()
			local held = DailyRewardsController.HeldGems()
				+ SpinsController.HeldGems()
				+ QuestsController.HeldGems()
				+ CodesController.HeldGems()
			local isFed = DailyRewardsController.IsLandingGems()
				or SpinsController.IsLandingGems()
				or QuestsController.IsLandingGems()
				or CodesController.IsLandingGems()
			vide.untrack(function()
				holdGems(held, isFed)
			end)
		end)
		-- A spin's XP rolls into the plate a slice at a time as it lands.
		vide.effect(function()
			local held = SpinsController.HeldXp()
			vide.untrack(function()
				if held == state.XpHeld() then return end
				state.XpHeld(held)
				if isProfileShown then showProfile() end
			end)
		end)
		-- The spins screen is a modal over the HUD rather than a page: it covers nothing, but the body stands still
		-- and the HUD's keys wait while it is up.
		vide.effect(function()
			SpinsController.IsOpen()
			vide.untrack(function()
				state.HeldKey(nil)
				updateControls()
			end)
		end)

		return {
			create("ScreenGui")({
				Name = "Lobby",
				ResetOnSpawn = false,
				IgnoreGuiInset = true,
				ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
				ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
				-- Scaled from a 1080-tall design, as the HUD is, under Roblox's top bar: its buttons are on the left,
				-- over the level plate, and the Settings icon on the right. The Gems counter has its own gui (below).
				create("Frame")({
					Name = "Root",
					BackgroundTransparency = 1,
					Position = function()
						return UDim2.fromOffset(0, state.TopInset())
					end,
					Size = function()
						local scale = state.Scale()
						return UDim2.new(1 / scale, 0, 1 / scale, -state.TopInset() / scale)
					end,
					create("UIScale")({ Scale = state.Scale }),
					Hud.Build(state, actions),
					Bar.Build(state, actions),
					Menu.Build(state, actions),
				}),
			}),
			Classes.Build(state, actions),
			-- The Gems counter over every lobby screen and its dim (they are at 5), under the settings and codes (10).
			-- Laid from the screen's top, as the pages are: it stands up in Roblox's top bar strip.
			create("ScreenGui")({
				Name = "Gems",
				ResetOnSpawn = false,
				IgnoreGuiInset = true,
				ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
				ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
				DisplayOrder = 6,
				create("Frame")({
					Name = "Root",
					BackgroundTransparency = 1,
					Size = function()
						local scale = state.Scale()
						return UDim2.fromScale(1 / scale, 1 / scale)
					end,
					create("UIScale")({ Scale = state.Scale }),
					Hud.BuildGems(state, actions),
				}),
			}),
			PadBoard.Build(state),
		}
	end, LocalPlayer:WaitForChild("PlayerGui"))

	RunService.Heartbeat:Connect(function()
		vide.batch(update)
	end)
end

return Ignis.Register(LobbyController)
