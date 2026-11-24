-- The lobby's screen (GDD 3): the designer's HUD (Hud), every pad's light and board, the host's party screen and the
-- queue that follows it (Party), the classes screen (Classes), the top bar's Daily, Codes and Settings buttons, and
-- opening the weapons, index, daily and quests screens (WeaponsController, IndexController, DailyController,
-- QuestsController). The server decides everything (LobbyService); this draws what it is told and sends requests.
-- A pad's light is this player's own answer to "could I step on now", which is why it is drawn here.
--
-- A countdown is sent as seconds left at the moment of a change and counted down here, so the server only sends on a
-- change rather than every second.
local ContextActionService = game:GetService("ContextActionService")
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
local CodesController = require(script.Parent.CodesController)
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
local EquipmentController = require(script.Parent.EquipmentController)
local IndexController = require(script.Parent.IndexController)
local DailyRewardsController = require(script.Parent.DailyRewardsController)
local DailyController = require(script.Parent.DailyController)
local LobbyEnteringController = require(script.Parent.LobbyEnteringController)
local SpinsController = require(script.Parent.SpinsController)
local QuestsController = require(script.Parent.QuestsController)
local ShopController = require(script.Parent.ShopController)
local MutationController = require(script.Parent.MutationController)
local RangeController = require(script.Parent.RangeController)
local Hud = require(script.Hud)
local Party = require(script.Party)
local Queue = require(script.Party.Queue)
local PadExit = require(script.Party.Exit)
local PadArt = require(script.PadArt)
local Shot = require(script.Shot)
local Board = require(script.Party.Board)
local Ghosts = require(script.Party.Ghosts)
local Invite = require(script.Party.Invite)
local Invitation = require(script.Party.Invitation)
local PartyParts = require(script.Party.Parts)
local Types = require(script.Types)
local TCharacter = require(ReplicatedStorage.Types.TCharacter)
local TCharacterEvents = require(ReplicatedStorage.Types.Events.TCharacterEvents)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local ServerNetworkLobby = NetworkMeta.Server.Lobby
local ClientNetworkLobby = NetworkMeta.Client.Lobby
local ServerNetworkClasses = NetworkMeta.Server.Classes
local ClientNetworkClasses = NetworkMeta.Client.Classes

local LocalPlayer = Players.LocalPlayer
local source = vide.source
local create = vide.create
local EPhase = PadsCore.EPhase
local ERefusal = PadsCore.ERefusal
local EInvite = PadsCore.EInvite

local TOAST_SECONDS = 3
-- His screens' width; the height is Theme.DESIGN_HEIGHT.
local DESIGN_WIDTH = 1920
-- A screen opened from over another (the Gems pill's +, a top bar icon) comes in once the other has left: every screen
-- leaves in 0.2 to 0.22 s, and two fading through each other read as a jumble.
local SWAP_SECONDS = 0.2
-- The HUD slides in this long after the lobby is up, so the first frames' hitches are behind it; the profile's
-- numbers roll in once the pieces they stand on have landed.
local ENTER_DELAY = 0.3
local ROLL_DELAY = 0.55
local MUSIC_FADE_SECONDS = 4
-- While something waits on the daily screen (today's reward, a free spin), or the index has a discovery to show, the
-- light crosses the button calling for it this often; the daily screen also opens by itself once a lobby visit when a
-- reward waits, as soon as nothing else is up.
local DAILY_CALL_SECONDS = 2.6
local DAILY_CALL_SHEEN = 0.7
-- The light catches the Gems counter's stone this often while nothing covers the whole view.
local GEM_GLINT_SECONDS = 4.5
-- The light crosses PLAY as often as it catches the stone, half a period apart, so the two never catch together.
local PLAY_CALL_SECONDS = GEM_GLINT_SECONDS
local PLAY_CALL_OFFSET = GEM_GLINT_SECONDS / 2
-- A pad's light: free to take (green), a party waiting with room this player may join (yellow), and closed to him
-- (red: full, being picked, leaving, locked or friends only). His own pad shows what everybody else sees of it.
local OPEN_COLOR = Theme.Color.Action
local WAITING_COLOR = Theme.Color.Gold
local CLOSED_COLOR = Theme.Color.Boss
-- Stepping into a pad he can take stops the body there and then, rather than when the server's poll has seen it and
-- answered; if no answer puts him on it by then, he is let go.
local STUN_SECONDS = 1.2
-- How hard a body arriving on this player's pad pushes the camera in (studs a second; it springs back).
local ARRIVAL_NUDGE = 9
-- Invites: how often the open list looks again at who stands on which pad, how long an answer stands on a card before
-- it offers INVITE again (SENT for as long as the invite stands, the rest a moment), how often the light crosses JOIN
-- on a party's invite on show, and how many invites may wait behind it.
local InviteTune = table.freeze({
	ON_PAD_SECONDS = 0.5,
	ANSWER_SECONDS = 4,
	CALL_SECONDS = 2.6,
	QUEUE = 4,
})
-- The keys swallowed while the body is held on a pad (updateControls), over everything else bound to them.
local HOLD_ACTION = "PadHold"
local HOLD_PRIORITY = Enum.ContextActionPriority.High.Value + 1
local HOLD_KEYS = {
	Enum.KeyCode.W,
	Enum.KeyCode.A,
	Enum.KeyCode.S,
	Enum.KeyCode.D,
	Enum.KeyCode.Up,
	Enum.KeyCode.Down,
	Enum.KeyCode.Left,
	Enum.KeyCode.Right,
	Enum.KeyCode.Space,
}

type TPadState = {
	Phase: number,
	Count: number,
	MaxPlayers: number,
	Map: number,
	Difficulty: number,
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
-- Each pad's spots in the world (Shot.SpotsOf).
local padSpots: { [number]: { Vector3 } } = {}
-- Host UserId -> whether he is this player's friend, for friends-only pads. Fetched once each: it is a web call.
local isFriendOf: { [number]: boolean } = {}
local isFriendFetching: { [number]: boolean } = {}
local toastThread: thread? = nil

local state: Types.TLobbyState = {
	Scale = source(1),
	PageScale = source(1),
	TopInset = source(0),
	TopbarRoom = source(0),
	Pads = pads,
	CurrentPad = source(0),
	IsChoosing = source(false),
	BestByMap = source({} :: { [string]: number }),
	BossKills = source({} :: { [string]: number }),
	MapsShown = source({} :: { [string]: boolean }),
	Level = source(1),
	UnlockMap = source(0),
	UnlockAt = source(-math.huge),
	PickPlayers = source(PadsCore.DEFAULT_PLAYERS),
	PickDifficulty = source(MapsCore.DIFFICULTIES[1]),
	PickMap = source(1),
	PickFriendsOnly = source(false),
	ChoosingAt = source(-math.huge),
	MapAt = source(-math.huge),
	MapStep = source(1),
	MapFrom = source(1),
	DifficultyAt = source(-math.huge),
	DifficultyFrom = source(MapsCore.DIFFICULTIES[1]),
	PlayersAt = source(-math.huge),
	PlayersFrom = source(PadsCore.DEFAULT_PLAYERS),
	AccessAt = source(-math.huge),
	CreatedAt = source(-math.huge),
	PartyRefusedAt = source(-math.huge),
	PartyCallAt = source(-math.huge),
	ToastText = source(""),
	IsToastShown = source(false),
	IsInviteOpen = source(false),
	InviteAt = source(-math.huge),
	InvitePlayers = source({} :: { Types.TInvitePlayer }),
	InviteResults = source({} :: { [number]: Types.TInviteResult }),
	InviteOnPad = source({} :: { [number]: number }),
	Invitation = source(nil :: Types.TInvitation?),
	InvitationAt = source(-math.huge),
	InvitationGoneAt = source(-math.huge),
	InvitationAnswer = source(""),
	InvitationSeconds = source(0),
	InvitationCallAt = source(-math.huge),
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
	IsDailyWaiting = source(false),
	IndexCount = source(0),
	QuestsReady = source(0),
	CanUpgradeWeapons = source(false),
	CanUpgradeClasses = source(false),
	CanBrew = source(false),
	CallAt = source(-math.huge),
	PlayAt = source(-math.huge),
	PlayRefusedAt = source(-math.huge),
	PlayCallAt = source(-math.huge),
	HeldKey = source(nil :: Enum.KeyCode?),
	IsCovered = source(false),
	CoveredAt = source(-math.huge),
	IsPlateCovered = source(false),
	PlateCoveredAt = source(-math.huge),
	IsBare = source(false),
	BareAt = source(-math.huge),
	IsClassesOpen = source(false),
	ClassesToggledAt = source(-math.huge),
	ClassesPage = source("Classes" :: Types.TClassesPage),
	ClassesPageAt = source(-math.huge),
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
local nextPlayCall = math.huge
local nextPartyCall = math.huge
-- A map's unlock's sounds still to play, each at its os.clock moment.
local dueSounds: { { At: number, Group: string, Name: string } } = {}
-- The local body's root, while it has one.
local selfRoot: BasePart? = nil
local selfHumanoid: Humanoid? = nil
-- The body's WalkSpeed from before it was held (holdStill), put back as it is let go.
local heldWalkSpeed: number? = nil
-- os.clock until which the body is held for a pad it stepped into, before the server has put it on it, and that pad.
local stunnedUntil = -math.huge
local stunnedPad = 0
-- A pad whose stun ran out with no answer: not stunned on again until the body has stepped off it.
local unansweredPad = 0
local isMovementSunk = false
local hasOpenedDaily = false
-- A screen waiting for the one it replaces to leave (swapTo), and when it comes in.
local pendingOpen: (() -> ())? = nil
local pendingOpenAt = 0
-- Every character's root, to see who stands on which spot of a pad.
local bodies: { [Model]: BasePart } = {}
-- While on a pad: the spots the camera's shot frames (Shot.Taken's bits) and the viewport shape it was framed for.
local isShotHeld = false
local shotTaken = 0
local shotFramed = 0
local shotAspect = 0
-- The open places' bodies on this player's pad (Ghosts) by spot, the pad they stand on, the one under the pointer, and
-- when they were last stepped.
local ghosts: { Ghosts.TGhost } = {}
local ghostPad = 0
local hoveredGhost: Ghosts.TGhost? = nil
local ghostsAt = os.clock()
local ghostFolder: Folder? = nil
-- Every other player in this server as the invite list shows them, by user id: one table each while they are here.
local invitePlayers: { [number]: Types.TInvitePlayer } = {}
local nextOnPadLook = 0
-- Parties' invites waiting behind the one on show, oldest first, and when the light next crosses its JOIN.
local invitationQueue: { Types.TInvitation } = {}
local nextInvitationCall = math.huge

-- Whether the classes or weapons page is up: the pages that show a body on a stage, which the head tags make way for.
function LobbyController.IsPageOpen(): boolean
	return state.IsClassesOpen() or WeaponsController.IsOpen()
end

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

-- Whether a screen the player opened is up: the ones closeScreens shuts. A new screen joins both lists.
local function isPlayerScreenUp(): boolean
	return state.IsClassesOpen()
		or WeaponsController.IsOpen()
		or IndexController.IsOpen()
		or QuestsController.IsOpen()
		or DailyController.IsOpen()
		or SettingsController.IsOpen()
		or CodesController.IsOpen()
		or ShopController.IsOpen()
		or MutationController.IsOpen()
end

-- On a pad the queue (or the party screen) takes the whole view, and the last run's results take it on arrival.
local function isScreenUp(): boolean
	return state.CurrentPad() ~= 0 or LobbyEnteringController.IsOpen() or isPlayerScreenUp()
end

-- Only presses are swallowed. The key the body walked onto the pad with is still down when this is bound, and
-- swallowing its release left whatever reads it walking for as long as the body was held.
local function sinkMovement(_: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then return Enum.ContextActionResult.Sink end
	return Enum.ContextActionResult.Pass
end

-- A held body cannot walk whatever key is down. It stops for real, so the default Animate hears it stop and goes to
-- idle before the server anchors it: anchored still walking, the walk clip never ends.
local function holdStill(isHeld: boolean)
	local humanoid = selfHumanoid
	if not humanoid then return end
	if isHeld then
		if heldWalkSpeed then return end
		heldWalkSpeed = humanoid.WalkSpeed
		humanoid.WalkSpeed = 0
		return
	end

	if heldWalkSpeed then humanoid.WalkSpeed = heldWalkSpeed end
	heldWalkSpeed = nil
end

-- The body walks only off a pad and while no screen covers the lobby. On a pad, or stopped stepping into one, the
-- movement keys are swallowed as well: with the controls off, the engine still turned the Humanoid's MoveDirection from
-- them through ContextActionService (a playtest: a sunk W left it at zero, an unsunk S did not), and every turn of it
-- scuffs dust and sound at the feet (FootstepsController). A key already down as the body is held is not swallowed,
-- so holdStill keeps it from walking.
local function updateControls()
	local isHeld = state.CurrentPad() ~= 0 or os.clock() < stunnedUntil
	PlayerModule:GetControls():Enable(not isHeld and not state.IsCovered())
	if isHeld == isMovementSunk then return end
	isMovementSunk = isHeld
	holdStill(isHeld)
	if isHeld then
		ContextActionService:BindActionAtPriority(
			HOLD_ACTION,
			sinkMovement,
			false,
			HOLD_PRIORITY,
			table.unpack(HOLD_KEYS)
		)
	else
		ContextActionService:UnbindAction(HOLD_ACTION)
	end
end

-- Sets a HUD flag and stamps when it changed, keeping Now ticking while the HUD slides. Whether it changed.
local function restamp(flag: vide.Source<boolean>, at: vide.Source<number>, value: boolean): boolean
	if flag() == value then return false end
	local now = os.clock()
	vide.batch(function()
		flag(value)
		at(now)
	end)
	stir(now + Classes.SETTLE_SECONDS)
	return true
end

-- Whether a screen covers the lobby now, stamped as that changes, so the HUD steps aside and comes back.
local function updateCover()
	local isCovered = isScreenUp()
	local isDocked = state.IsClassesOpen() or WeaponsController.IsOpen()
	if state.IsGemsDocked() ~= isDocked then state.IsGemsDocked(isDocked) end
	restamp(state.IsPlateCovered, state.PlateCoveredAt, isCovered and not DailyController.IsOpen())
	restamp(state.IsBare, state.BareAt, LobbyEnteringController.IsOpen() or state.CurrentPad() ~= 0)
	if not restamp(state.IsCovered, state.CoveredAt, isCovered) then return end

	RangeController.SetCovered(isCovered)
	state.HeldKey(nil)
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
		-- The CLASSES slab opens the screen on its own page, whichever was left up.
		if isOpen then
			state.ClassesPage("Classes")
			state.ClassesPageAt(-math.huge)
		end
	end)
	EquipmentController.SetShown(isOpen and state.ClassesPage() == "Equipment", true)
	stir(now + Classes.SETTLE_SECONDS)
	updateCover()
	SoundsCore.SetMuffled("Classes", isOpen)
	BlurController.SetBlurred("Classes", isOpen)
	SoundsCore.PlayUINamed("UI", if isOpen then "MenuIn" else "MenuOut")
end

-- Shuts every screen the player opened; whether one was up.
local function closeScreens(): boolean
	if not isPlayerScreenUp() then return false end

	setClassesOpen(false)
	WeaponsController.Close()
	IndexController.Close()
	QuestsController.Close()
	DailyController.Close()
	SettingsController.Close()
	CodesController.Close()
	ShopController.Close()
	MutationController.Close()
	return true
end

-- Opens a screen in place of whichever is up: that one leaves first, then `open` runs (update), so one screen is up
-- at a time and two never fade through each other. With nothing up it opens at once; already up (`isOpen`), it stays.
local function swapTo(open: () -> (), isOpen: () -> boolean)
	if isOpen() then return end
	if not closeScreens() then
		pendingOpen = nil
		open()
		return
	end

	pendingOpen = open
	pendingOpenAt = os.clock() + SWAP_SECONDS
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

local function isMapOpen(map: MapsCore.TMap): boolean
	return MapsCore.IsUnlockedBy(map, state.Level(), state.BossKills())
end

-- Whether map `index` is open and its unlock has never played: the first map has none to play.
local function isUnlockDue(index: number): boolean
	local map = MapsCore.LIST[index]
	if not map or not MapsCore.HasRequirement(map) or state.MapsShown()[map.Name] then return false end
	return isMapOpen(map)
end

-- The map the party screen opens on: the first along the path whose unlock is still to play, so each plays in turn,
-- or else the furthest open.
local function openingMap(): number
	local furthest = 1
	for index, map in MapsCore.LIST do
		if isUnlockDue(index) then return index end
		if isMapOpen(map) then furthest = index end
	end

	return furthest
end

-- Whether a map's unlock holds the host on it: no other map, no EXIT, no CREATE.
local function isHeldByUnlock(): boolean
	return os.clock() < state.UnlockAt() + PartyParts.Unlock.HOLD
end

-- Plays map `index`'s unlock on the party screen from `at`, if it is due: marked played at once, here and on the
-- server, so it never plays twice. CREATE's light crosses it as the hold lets go.
local function playUnlock(index: number, at: number)
	if not state.IsChoosing() or not isUnlockDue(index) or index >= PartyParts.PathCount(state) then return end
	local map = MapsCore.LIST[index]
	local shown = table.clone(state.MapsShown())
	shown[map.Name] = true
	vide.batch(function()
		state.MapsShown(shown)
		state.UnlockMap(index)
		state.UnlockAt(at)
	end)
	local unlock = PartyParts.Unlock
	stir(at + unlock.SECONDS)
	nextPartyCall = at + unlock.HOLD
	-- A tick for each row the map asks for, on its turn: the level's first, the boss's second.
	for row, isAsked in { map.UnlockLevel > 0, map.UnlockBossKills > 0 } do
		if not isAsked then continue end
		local rowAt = at + unlock.ROWS + unlock.ROW_STAGGER * (row - 1)
		table.insert(dueSounds, { At = rowAt, Group = "UI.UpgradePick", Name = "Tick" })
	end
	table.insert(dueSounds, { At = at + unlock.CLICK, Group = "UI.Index", Name = "Unlock" })
	table.insert(dueSounds, { At = at + unlock.RELEASE, Group = "UI.UpgradePick", Name = "RevealLegendary" })
	ClientNetworkLobby.MapShown.Fire(index)
end

local function updateChoosing()
	local padState = latest[state.CurrentPad()]
	local isChoosing = padState ~= nil and padState.Phase == EPhase.Choosing and padState.HostId == LocalPlayer.UserId
	if state.IsChoosing() == isChoosing then return end
	local now = os.clock()
	-- It opens on the newest map, after the one played last.
	local opening = if isChoosing then openingMap() else state.PickMap()
	vide.batch(function()
		state.IsChoosing(isChoosing)
		state.ChoosingAt(now)
		state.PickMap(opening)
		state.MapFrom(opening)
		if isChoosing then state.MapAt(-math.huge) end
	end)
	nextPartyCall = if isChoosing then now + Party.FIRST_CALL_SECONDS else math.huge
	stir(now + Party.SETTLE_SECONDS)
	updateCover()
	SoundsCore.SetMuffled("Party", isChoosing)
	BlurController.SetBlurred("Party", isChoosing)
	SoundsCore.PlayUINamed("UI", if isChoosing then "MenuIn" else "MenuOut")

	if not isChoosing then table.clear(dueSounds) end
	playUnlock(opening, now + Party.UNLOCK_OPEN_DELAY)
end

-- Whether this player could step on the pad right now; the server's canJoin decides it for real.
local function isOpenToMe(index: number): boolean
	if state.CurrentPad() == index then return true end
	local padState = latest[index]
	if not padState then return false end
	if padState.Phase == EPhase.Empty then return state.CurrentPad() == 0 end
	if padState.Phase ~= EPhase.Open or padState.Count >= padState.MaxPlayers then return false end

	local map = MapsCore.LIST[padState.Map]
	if not map or not isMapOpen(map) then return false end
	if padState.IsFriendsOnly and padState.HostId ~= LocalPlayer.UserId then
		return isFriendOf[padState.HostId] == true
	end

	return true
end

local function padColor(index: number): Color3
	local padState = latest[index]
	local isWaiting = padState ~= nil and padState.Phase == EPhase.Open and padState.Count < padState.MaxPlayers
	if state.CurrentPad() == index then return if isWaiting then WAITING_COLOR else CLOSED_COLOR end
	if not isOpenToMe(index) then return CLOSED_COLOR end
	return if isWaiting then WAITING_COLOR else OPEN_COLOR
end

local function tintPads()
	for index, art in arts do
		PadArt.Tint(art, padColor(index))
	end
end

-- Off a pad, a body inside one it could take stops dead: controls off and its walk taken out of it, as the server
-- will put it on that pad in a moment.
-- Runs every frame, so the cross-module test is hoisted out of the loop.
local function stunOnPad(now: number)
	local root = selfRoot
	if state.CurrentPad() ~= 0 or not root or now < stunnedUntil then return end
	local isOnPad = PadsCore.IsOnPad
	local position = root.Position
	local unanswered = pads[unansweredPad]
	if unanswered and not isOnPad(unanswered.Part, position) then unansweredPad = 0 end
	for index, pad in pads do
		if index == unansweredPad then continue end
		if not isOnPad(pad.Part, position) or not isOpenToMe(index) then continue end
		stunnedUntil = now + STUN_SECONDS
		stunnedPad = index
		local velocity = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(0, math.min(velocity.Y, 0), 0)
		updateControls()
		ClientNetworkLobby.StepOnPad.Fire(index)
		return
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

-- Shows map `index` (as far as the path goes: the '?' past its end too), the showcase turning `step`'s way to it, and
-- plays its unlock as it lands if one is due.
local function setMap(index: number, step: number)
	if index < 1 or index > PartyParts.PathCount(state) or index == state.PickMap() or isHeldByUnlock() then return end
	local now = os.clock()
	vide.batch(function()
		state.MapFrom(state.PickMap())
		state.PickMap(index)
		state.MapAt(now)
		state.MapStep(step)
	end)
	stir(now + Party.SETTLE_SECONDS)
	playUnlock(index, now + Party.UNLOCK_ARRIVE_DELAY)
end

local function pickDifficulty(difficulty: string)
	if not table.find(MapsCore.DIFFICULTIES, difficulty) or difficulty == state.PickDifficulty() then return end
	local now = os.clock()
	vide.batch(function()
		state.DifficultyFrom(state.PickDifficulty())
		state.PickDifficulty(difficulty)
		state.DifficultyAt(now)
	end)
	stir(now + Party.SETTLE_SECONDS)
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

-- The invite list's players, by display name: everyone in this server but this player.
local function listInvitePlayers()
	local list = {}
	local count = 0
	for _, player in invitePlayers do
		count += 1
		list[count] = player
	end
	table.sort(list, function(a, b)
		return string.lower(a.DisplayName) < string.lower(b.DisplayName)
	end)

	state.InvitePlayers(list)
end

-- Which pad each other player stands on, from their bodies, written only as it changes.
local function lookOnPads()
	local onPad: { [number]: number } = {}
	local isOnPad = PadsCore.IsOnPad
	for model, root in bodies do
		local player = Players:GetPlayerFromCharacter(model)
		if not player or player == LocalPlayer then continue end
		local position = root.Position
		for index, pad in pads do
			if not isOnPad(pad.Part, position) then continue end
			onPad[player.UserId] = index
			break
		end
	end

	local last = state.InviteOnPad()
	for userId, index in onPad do
		if last[userId] ~= index then
			state.InviteOnPad(onPad)
			return
		end
	end
	for userId in last do
		if not onPad[userId] then
			state.InviteOnPad(onPad)
			return
		end
	end
end

-- The invite list over the queue, only in an open party this player is in.
local function setInviteOpen(isOpen: boolean)
	if state.IsInviteOpen() == isOpen then return end
	if isOpen then
		local pad = pads[state.CurrentPad()]
		if not pad or pad.Phase() ~= EPhase.Open then return end
		listInvitePlayers()
		lookOnPads()
		nextOnPadLook = os.clock() + InviteTune.ON_PAD_SECONDS
	end
	local now = os.clock()
	vide.batch(function()
		state.IsInviteOpen(isOpen)
		state.InviteAt(now)
	end)
	stir(now + Invite.SETTLE_SECONDS)
	BlurController.SetBlurred("Invite", isOpen)
	SoundsCore.PlayUINamed("UI", if isOpen then "MenuIn" else "MenuOut")
end

-- Writes what the server answered about an invite to `userId`, or takes it off with nil.
local function setInviteResult(userId: number, result: number?)
	local results = table.clone(state.InviteResults())
	results[userId] = if result then { Result = result, At = os.clock() } else nil
	state.InviteResults(results)
end

-- The next party's invite in line comes on, once the one before has gone.
local function showInvitation(now: number)
	local invitation = table.remove(invitationQueue, 1)
	if not invitation then return end
	vide.batch(function()
		state.Invitation(invitation)
		state.InvitationAt(now)
		state.InvitationAnswer("")
		state.InvitationSeconds(math.ceil(math.max(invitation.EndsAt - now, 0)))
	end)
	nextInvitationCall = now + InviteTune.CALL_SECONDS
	stir(now + Invitation.ARRIVE_SECONDS)
	SoundsCore.PlayUINamed("UI.Index", "Unlock")
end

-- The invite on show goes: "Join" lifts it away, "Decline" and "Lapse" slide it back out.
local function dismissInvitation(answer: string)
	if state.InvitationGoneAt() >= state.InvitationAt() or not state.Invitation() then return end
	local now = os.clock()
	vide.batch(function()
		state.InvitationAnswer(answer)
		state.InvitationGoneAt(now)
	end)
	nextInvitationCall = math.huge
	stir(now + Invitation.LEAVE_SECONDS)
end

-- Whether a party's invite to this player still means anything: its party still open with room, and this player on no
-- pad of their own.
local function isInvitationLive(invitation: Types.TInvitation, now: number): boolean
	if now >= invitation.EndsAt or state.CurrentPad() ~= 0 then return false end
	local padState = latest[invitation.Pad]
	return padState ~= nil and padState.Phase == EPhase.Open and padState.Count < padState.MaxPlayers
end

-- The list's answers that have had their time go back to INVITE: SENT for as long as the invite stands, DECLINED for as
-- long as the server holds the party off, the rest a moment.
local function expireInviteResults(now: number)
	for userId, answer in state.InviteResults() do
		local seconds = if answer.Result == EInvite.Sent
			then PadsCore.INVITE_SECONDS
			elseif answer.Result == EInvite.Declined then PadsCore.INVITE_DECLINED_SECONDS
			else InviteTune.ANSWER_SECONDS
		if now - answer.At >= seconds then setInviteResult(userId, nil) end
	end
end

-- The open list sees again who stands where every so often, and shuts once the party is no longer open.
local function updateInviteList(now: number)
	if not state.IsInviteOpen() then return end
	local pad = pads[state.CurrentPad()]
	if not pad or pad.Phase() ~= EPhase.Open then setInviteOpen(false) end
	if now < nextOnPadLook then return end
	nextOnPadLook = now + InviteTune.ON_PAD_SECONDS
	lookOnPads()
end

-- The party's invite on show counts down, calls on JOIN and lapses; once it has gone, the next in line comes on, those
-- that lapsed while waiting dropped unseen.
local function updateInvitation(now: number)
	local invitation = state.Invitation()
	if invitation and state.InvitationGoneAt() < state.InvitationAt() then
		local seconds = math.ceil(math.max(invitation.EndsAt - now, 0))
		if seconds ~= state.InvitationSeconds() then state.InvitationSeconds(seconds) end
		if not isInvitationLive(invitation, now) then dismissInvitation("Lapse") end
		if now < nextInvitationCall then return end
		nextInvitationCall = now + InviteTune.CALL_SECONDS
		state.InvitationCallAt(now)
		stir(now + Invitation.CALL_SECONDS)
		return
	end

	if #invitationQueue == 0 or now < state.InvitationGoneAt() + Invitation.LEAVE_SECONDS then return end
	while invitationQueue[1] and not isInvitationLive(invitationQueue[1], now) do
		table.remove(invitationQueue, 1)
	end
	showInvitation(now)
end

local actions: Types.TLobbyActions = {
	Play = function()
		local now = os.clock()
		state.PlayAt(now)
		stir(now + Hud.PLAY_SECONDS)
		ClientNetworkLobby.Play.Fire()
	end,
	-- The pad's EXIT. Over the invite list it goes back one step: the list shuts and the player stays on the pad.
	Leave = function()
		if state.IsInviteOpen() then
			setInviteOpen(false)
			return
		end
		if state.IsChoosing() and isHeldByUnlock() then return end
		ClientNetworkLobby.LeavePad.Fire()
	end,
	OpenInvite = function()
		setInviteOpen(true)
	end,
	CloseInvite = function()
		setInviteOpen(false)
	end,
	-- Shown as SENT at once; the server's answer stamps over it.
	InvitePlayer = function(userId: number)
		if not state.IsInviteOpen() or state.InviteResults()[userId] then return end
		setInviteResult(userId, EInvite.Sent)
		stir(os.clock() + Invite.SETTLE_SECONDS)
		SoundsCore.PlayUINamed("UI.UpgradePick", "PickRare")
		ClientNetworkLobby.InvitePlayer.Fire(userId)
	end,
	-- JOIN shuts whatever screen is up first, so the queue the server's answer brings is the one thing on screen.
	AnswerInvitation = function(isJoining: boolean)
		local invitation = state.Invitation()
		if not invitation or state.InvitationGoneAt() >= state.InvitationAt() then return end
		dismissInvitation(if isJoining then "Join" else "Decline")
		ClientNetworkLobby.AnswerInvite.Fire(invitation.Pad, isJoining)
		if not isJoining then
			SoundsCore.PlayUINamed("UI", "MenuOut")
			return
		end
		closeScreens()
		SoundsCore.PlayUINamed("UI.UpgradePick", "RevealEpic")
	end,
	StartParty = function()
		if isHeldByUnlock() then return end
		local now = os.clock()
		local map = MapsCore.LIST[state.PickMap()]
		stir(now + Party.SETTLE_SECONDS)
		if not map or not isMapOpen(map) then
			state.PartyRefusedAt(now)
			SoundsCore.PlayUINamed("UI.UpgradePick", "Denied")
			return
		end
		state.CreatedAt(now)
		local difficulty = table.find(MapsCore.DIFFICULTIES, state.PickDifficulty()) or 1
		ClientNetworkLobby.StartParty.Fire(state.PickPlayers(), state.PickMap(), difficulty, state.PickFriendsOnly())
	end,
	PickDifficulty = pickDifficulty,
	PickMap = function(index: number)
		setMap(index, if index < state.PickMap() then -1 else 1)
	end,
	StepMap = function(step: number)
		setMap(state.PickMap() + step, step)
	end,
	PickPlayers = function(count: number)
		if count == state.PickPlayers() or count < 1 or count > PadsCore.MAX_PLAYERS then return end
		local now = os.clock()
		vide.batch(function()
			state.PlayersFrom(state.PickPlayers())
			state.PickPlayers(count)
			state.PlayersAt(now)
		end)
		stir(now + Party.SETTLE_SECONDS)
	end,
	PickFriendsOnly = function(isFriendsOnly: boolean)
		if isFriendsOnly == state.PickFriendsOnly() then return end
		local now = os.clock()
		vide.batch(function()
			state.PickFriendsOnly(isFriendsOnly)
			state.AccessAt(now)
		end)
		stir(now + Party.SETTLE_SECONDS)
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
	OpenQuests = function()
		QuestsController.Open()
	end,
	OpenIndex = function()
		IndexController.Open()
	end,
	OpenLab = function()
		MutationController.Open()
	end,
	-- Over the shop it glides to `section`; over any other screen it takes that screen's place.
	OpenShop = function(section: string?)
		if ShopController.IsOpen() then
			ShopController.Open(section :: any)
			return
		end
		swapTo(function()
			ShopController.Open(section :: any)
		end, ShopController.IsOpen)
	end,
	MarkGemsGlyph = function(glyph: GuiObject)
		state.GemsGlyph(glyph)
		DailyRewardsController.SetGemsTarget(glyph)
		SpinsController.SetGemsTarget(glyph)
		QuestsController.SetGemsTarget(glyph)
		CodesController.SetGemsTarget(glyph)
		ShopController.SetGemsTarget(glyph)
		WeaponsController.SetGemsTarget(glyph)
	end,
	MarkXpBar = function(bar: GuiObject)
		SpinsController.SetXpTarget(bar)
		CodesController.SetXpTarget(bar)
	end,
	CloseClasses = function()
		setClassesOpen(false)
	end,
	PickClassesPage = function(page: Types.TClassesPage)
		if not state.IsClassesOpen() or state.ClassesPage() == page then return end
		local now = os.clock()
		vide.batch(function()
			state.ClassesPage(page)
			state.ClassesPageAt(now)
		end)
		EquipmentController.SetShown(page == "Equipment", false)
		stir(now + Classes.SETTLE_SECONDS)
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
	Stir = function(seconds: number)
		stir(os.clock() + seconds)
	end,
}

local function updateScale()
	local viewport = Workspace.CurrentCamera.ViewportSize
	local inset = GuiService:GetGuiInset().Y
	local scale = Hud.ScaleFor(viewport.Y, inset)
	vide.batch(function()
		state.TopInset(inset)
		state.Scale(scale)
		state.PageScale(math.max(math.min(viewport.Y / Theme.DESIGN_HEIGHT, viewport.X / DESIGN_WIDTH), 0.01))
		state.TopbarRoom((viewport.X / 2 - GuiService.TopbarInset.Min.X) / scale)
	end)
end

-- Every place of an open party, taken or not, as Shot.Taken's bits: the server hands out the lowest spots first, so a
-- party of n stands on the first n.
local function placesOf(pad: Types.TPadView): number
	if pad.Phase() ~= EPhase.Open then return 0 end
	return bit32.lshift(1, math.min(pad.MaxPlayers(), #PadsCore.SPOTS)) - 1
end

-- On a pad the camera holds a shot of the party (Shot), framed again as bodies are put on their spots or leave them.
-- An open party's free places are framed too, where their bodies stand (Ghosts). Each arrival lights the pad and, once
-- the shot is up, pushes the camera in a little.
local function frameShot()
	local index = state.CurrentPad()
	local pad = pads[index]
	if not pad then
		if not isShotHeld then return end
		isShotHeld = false
		shotTaken = 0
		shotFramed = 0
		CameraController.ReleaseShot()
		return
	end

	local taken = Shot.Taken(padSpots[index], bodies)
	local framed = bit32.bor(taken, placesOf(pad))
	local viewport = Workspace.CurrentCamera.ViewportSize
	local aspect = viewport.X / math.max(viewport.Y, 1)
	if isShotHeld and taken == shotTaken and framed == shotFramed and aspect == shotAspect then return end

	if bit32.band(taken, bit32.bnot(shotTaken)) ~= 0 then
		local art = arts[index]
		if art then PadArt.Flash(art) end
		if isShotHeld then CameraController.NudgeShot(ARRIVAL_NUDGE) end
	end

	isShotHeld = true
	shotTaken = taken
	shotFramed = framed
	shotAspect = aspect
	local eye, look = Shot.Frame(pad.Part, framed, aspect)
	CameraController.HoldShot(eye, look, Shot.FOV)
end

-- The open place's body along `ray`, the nearest if several.
local function ghostAlong(ray: Ray): Ghosts.TGhost?
	local nearest, nearestDistance = nil, math.huge
	for _, ghost in ghosts do
		local distance = Ghosts.Hit(ghost, ray)
		if distance and distance < nearestDistance then
			nearest, nearestDistance = ghost, distance
		end
	end

	return nearest
end

-- Whether a button of any screen is under the screen point (inset-excluded, as AbsolutePosition): it takes the press,
-- so the body behind it does not light.
local function isButtonAt(point: Vector2): boolean
	for _, object in LocalPlayer.PlayerGui:GetGuiObjectsAtPosition(point.X, point.Y) do
		if object:IsA("GuiButton") and object.Interactable then return true end
	end

	return false
end

-- The body under the mouse, while the invite list is not over them.
local function hoverGhost(): Ghosts.TGhost?
	if ghostPad == 0 or state.IsInviteOpen() or not UserInputService.MouseEnabled then return nil end
	local mouse = UserInputService:GetMouseLocation()
	local ghost = ghostAlong(Workspace.CurrentCamera:ViewportPointToRay(mouse.X, mouse.Y))
	if not ghost or isButtonAt(mouse - GuiService:GetGuiInset()) then return nil end
	return ghost
end

-- A body pressed: it sinks and punches as the invite list rises over it.
local function pressGhost(ghost: Ghosts.TGhost)
	Ghosts.Press(ghost, os.clock())
	SoundsCore.PlayClick()
	setInviteOpen(true)
end

-- The open places' bodies on this player's pad: built as they step on, offered while the party is open and the spot
-- free, lifted off as a player lands on one, and destroyed once they have gone after the player left the pad.
local function updateGhosts(now: number)
	local dt = math.min(now - ghostsAt, 0.1)
	ghostsAt = now
	local index = state.CurrentPad()
	local pad = pads[index]
	if index ~= ghostPad then
		local isGone = true
		for _, ghost in ghosts do
			Ghosts.Open(ghost, false, false, now)
			if not ghost.IsGone then isGone = false end
		end
		local folder = ghostFolder
		if isGone and folder then
			for _, ghost in ghosts do
				ghost.Model:Destroy()
			end
			table.clear(ghosts)
			hoveredGhost = nil
			ghostPad = index
			if pad then
				for spot in PadsCore.SPOTS do
					ghosts[spot] = Ghosts.Build(pad.Part, spot, folder)
				end
			end
		end
	end

	if pad and index == ghostPad then
		local free = bit32.band(placesOf(pad), bit32.bnot(shotTaken))
		for spot, ghost in ghosts do
			local bit = bit32.lshift(1, spot - 1)
			Ghosts.Open(ghost, bit32.btest(free, bit), bit32.btest(shotTaken, bit), now)
		end
	end

	local hovered = hoverGhost()
	if hovered ~= hoveredGhost then
		hoveredGhost = hovered
		if hovered then SoundsCore.PlayHover() end
	end
	for _, ghost in ghosts do
		Ghosts.Step(ghost, now, dt, ghost == hovered)
	end
end

-- Whether any button calls for what waits behind it: the daily screen, the index, the quests, an upgrade.
local function isAnythingWaiting(): boolean
	return state.IsDailyWaiting()
		or state.IndexCount() > 0
		or state.QuestsReady() > 0
		or state.CanUpgradeWeapons()
		or state.CanUpgradeClasses()
end

-- Whether the Gems held raise any class's ability a level.
local function canUpgradeClasses(): boolean
	local gems, byClass = state.Gems(), state.ClassLevels()
	for _, class in DataCore.Classes.All do
		local levels = byClass[class.Id]
		for slot = 1, AbilitiesCore.UltimateSlot(class) do
			local cost = AbilitiesCore.UpgradeCost(if levels then levels[slot] or 1 else 1)
			if cost and cost <= gems then return true end
		end
	end

	return false
end

local function update()
	local now = os.clock()
	if now < motionUntil then state.Now(now) end
	local open = pendingOpen
	if open and now >= pendingOpenAt then
		pendingOpen = nil
		open()
	end
	if heldLevels and now >= state.UpgradedAt() then
		state.ClassLevels(heldLevels)
		state.IsUpgrading(false)
		heldLevels = nil
	end
	if now >= nextDailyCall and not state.IsCovered() and isAnythingWaiting() then
		local isFree = state.CurrentPad() == 0 and not SettingsController.IsOpen() and not CodesController.IsOpen()
		if state.IsDailyReady() and not hasOpenedDaily and isFree then
			hasOpenedDaily = true
			DailyController.Open()
		end
		nextDailyCall = now + DAILY_CALL_SECONDS
		state.CallAt(now)
		stir(now + math.max(DAILY_CALL_SHEEN, Hud.NOTICE_CALL_SECONDS))
	end
	if now >= nextPartyCall then
		nextPartyCall = now + Party.CALL_SECONDS
		state.PartyCallAt(now)
		stir(now + Party.SHEEN_SECONDS)
	end
	if now >= nextGemGlint then
		nextGemGlint = now + GEM_GLINT_SECONDS
		if not state.IsBare() then state.GemGlintAt(now) end
	end
	if now >= nextPlayCall then
		nextPlayCall = now + PLAY_CALL_SECONDS
		if not state.IsCovered() then
			state.PlayCallAt(now)
			stir(now + Hud.PLAY_CALL_SHEEN)
		end
	end
	for index, pad in pads do
		local ending = endsAt[index]
		local seconds = if ending then math.ceil(math.max(ending - now, 0)) else -1
		if pad.Seconds() ~= seconds then pad.Seconds(seconds) end
	end
	for index = #dueSounds, 1, -1 do
		local due = dueSounds[index]
		if now < due.At then continue end
		table.remove(dueSounds, index)
		SoundsCore.PlayUINamed(due.Group, due.Name)
	end
	stunOnPad(now)
	frameShot()
	updateGhosts(now)
	expireInviteResults(now)
	updateInviteList(now)
	updateInvitation(now)
	-- A stun the server never answered lets go.
	if stunnedUntil > -math.huge and now >= stunnedUntil then
		stunnedUntil = -math.huge
		unansweredPad = stunnedPad
		updateControls()
	end
end

-- The level the maps open on, as the profile has it. A map it opens while the screen is up plays its unlock there.
local function syncLevel()
	if state.Level() == ProfileController.Level then return end
	state.Level(ProfileController.Level)
	tintPads()
	playUnlock(state.PickMap(), os.clock())
end

local function applyPad(index: number)
	local pad = pads[index]
	local padState = latest[index]
	if not pad or not padState then return end
	pad.Phase(padState.Phase)
	pad.Count(padState.Count)
	pad.MaxPlayers(padState.MaxPlayers)
	pad.Map(padState.Map)
	pad.Difficulty(padState.Difficulty)
	pad.IsFriendsOnly(padState.IsFriendsOnly)
end

ServerNetworkLobby.PadState.On(
	function(
		index: number,
		phase: number,
		count: number,
		maxPlayers: number,
		map: number,
		difficulty: number,
		isFriendsOnly: boolean,
		hostId: number,
		seconds: number
	)
		latest[index] = {
			Phase = phase,
			Count = count,
			MaxPlayers = maxPlayers,
			Map = map,
			Difficulty = difficulty,
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

-- Whether the top bar's Daily, Codes and Settings are up: they step aside while the Gems counter is docked on the classes or
-- weapons page. Roblox draws them at a fixed size in px while the page scales, so on a smaller screen they would sit on
-- the counter, and moving the counter would take it off the panel and the tabs it lines up with. Reads a vide source.
local function isTopbarShown(): boolean
	return not state.IsGemsDocked() and state.CurrentPad() == 0
end

-- Batched: vide runs effects as each source is set, so CurrentPad alone would open the queue screen (EXIT live)
-- for the moment before IsChoosing follows.
ServerNetworkLobby.PadJoined.On(function(index: number)
	stunnedUntil = -math.huge
	vide.batch(function()
		state.CurrentPad(index)
		updateCover()
		updateControls()
		updateChoosing()
	end)
	tintPads()
end)

ServerNetworkLobby.PadRefused.On(function(index: number, reason: number)
	-- Only PLAY is refused this way: it shakes its head.
	if reason == ERefusal.NoFreePad then
		local now = os.clock()
		state.PlayRefusedAt(now)
		stir(now + Hud.PLAY_SECONDS)
		SoundsCore.PlayUINamed("UI.UpgradePick", "Denied")
		showToast("Every pad is busy. Try again in a moment.")
		return
	end

	local pad = pads[index]
	local map = if pad then MapsCore.LIST[pad.Map()] else nil
	if reason == ERefusal.Locked and map then
		showToast(`Locked: {MapsCore.RequirementText(map)}`)
	elseif reason == ERefusal.FriendsOnly then
		showToast("This party is for the host's friends only.")
	elseif reason == ERefusal.Busy then
		showToast("Someone is setting up this party.")
	elseif reason == ERefusal.Idle then
		showToast("Time's up: the pad is free again.")
	elseif reason == ERefusal.Expired then
		showToast("That invite has run out.")
	end
end)

-- A party's invite: shown at once if nothing else is, else it waits its turn. The same party asking again only renews
-- the one it already has, wherever it is in line.
ServerNetworkLobby.Invited.On(function(index: number, userId: number, seconds: number)
	local inviter = Players:GetPlayerByUserId(userId)
	if not inviter or not pads[index] then return end
	local lapsesAt = os.clock() + seconds
	local current = state.Invitation()
	if current and current.Pad == index and state.InvitationGoneAt() < state.InvitationAt() then
		state.Invitation({ Pad = index, UserId = userId, DisplayName = inviter.DisplayName, EndsAt = lapsesAt })
		return
	end
	for position, waiting in invitationQueue do
		if waiting.Pad ~= index then continue end
		table.remove(invitationQueue, position)
		break
	end
	if #invitationQueue >= InviteTune.QUEUE then table.remove(invitationQueue, 1) end
	table.insert(
		invitationQueue,
		{ Pad = index, UserId = userId, DisplayName = inviter.DisplayName, EndsAt = lapsesAt }
	)
end)

-- What came of an invite this player sent: its card stamps the answer. Joining sounds here; the rest sound as they
-- matter (turned down), or not at all (what the card already showed).
ServerNetworkLobby.InviteAnswered.On(function(userId: number, result: number)
	local last = state.InviteResults()[userId]
	if last and last.Result == result then return end
	setInviteResult(userId, result)
	stir(os.clock() + Invite.SETTLE_SECONDS)
	if result == EInvite.Joined then
		SoundsCore.PlayUINamed("UI.UpgradePick", "RevealEpic")
	elseif result ~= EInvite.Sent then
		SoundsCore.PlayUINamed("UI.UpgradePick", "Denied")
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

ServerNetworkLobby.MapRecords.On(function(records: { { Best: number, BossKills: number, IsShown: boolean } })
	local bests, bossKills, shown = {}, {}, {}
	for index, map in MapsCore.LIST do
		local record = records[index]
		bests[map.Name] = if record then record.Best else 0
		bossKills[map.Name] = if record then record.BossKills else 0
		shown[map.Name] = record ~= nil and record.IsShown
	end

	vide.batch(function()
		state.BestByMap(bests)
		state.BossKills(bossKills)
		state.MapsShown(shown)
	end)
	tintPads()
	-- A map opened while the screen is up plays its unlock there and then.
	playUnlock(state.PickMap(), os.clock())
end)

LobbyController.OnSelfCharacterAdded = function(character)
	selfRoot = character.HumanoidRootPart
	selfHumanoid = character.Humanoid
	-- A new body while held (a respawn on the pad) is held still too.
	if isMovementSunk then holdStill(true) end
end

LobbyController.OnSelfCharacterRemoving = function()
	selfRoot = nil
	selfHumanoid = nil
	heldWalkSpeed = nil
end

LobbyController.OnCharacterAdded = function(character: TCharacter.TCharacter)
	bodies[character] = character.HumanoidRootPart
end :: TCharacterEvents.OnCharacterAdded

LobbyController.OnCharacterRemoving = function(character: TCharacter.TCharacter)
	bodies[character] = nil
end :: TCharacterEvents.OnCharacterRemoving

LobbyController.OnPlayerConnected = function(player: Player)
	if player == LocalPlayer then return end
	invitePlayers[player.UserId] = {
		UserId = player.UserId,
		Name = player.Name,
		DisplayName = player.DisplayName,
	}
	listInvitePlayers()
end :: TPlayerEvents.OnPlayerConnected

LobbyController.OnPlayerDisconnected = function(player: Player)
	if not invitePlayers[player.UserId] then return end
	invitePlayers[player.UserId] = nil
	listInvitePlayers()
	setInviteResult(player.UserId, nil)
end :: TPlayerEvents.OnPlayerDisconnected

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
			Difficulty = source(1),
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
		padSpots[index] = Shot.SpotsOf(pad.Part)
	end
	local folder = Instance.new("Folder")
	folder.Name = "PartyGhosts"
	folder.Parent = Workspace
	ghostFolder = folder

	updateScale()
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(updateScale)
	update()
	updateChoosing()
	tintPads()
	MusicController.SetLevel("Lobby", 1, MUSIC_FADE_SECONDS)
	-- Made in the order they stand, left to right: Daily, Codes, Settings. Each takes the place of any screen up
	-- (swapTo), the shop and the pages included. Daily wears the count of what waits on its screen, and calls in light while there is any.
	local dailyIcon = TopbarPlus.new()
	dailyIcon
		:setName("Daily")
		:setImage(Icons.Pictures[EIcons.GiftBox].Image)
		:modifyTheme({ "IconImage", "ImageRectOffset", Icons.Pictures[EIcons.GiftBox].Offset })
		:modifyTheme({ "IconImage", "ImageRectSize", Icons.PICTURE_CELL_SIZE })
		:setCaption("Daily")
		:align("Right")
		:bindEvent("selected", function()
			swapTo(DailyController.Open, DailyController.IsOpen)
		end)
		:bindEvent("deselected", DailyController.Close)
	Topbar.Dress(dailyIcon, {
		IsSelected = DailyController.IsOpen,
		HasBrackets = false,
		Now = state.Now,
		OnPress = stir,
		IsShown = isTopbarShown,
		Count = DailyController.Waiting,
		CallAt = state.CallAt,
	})
	local codesIcon = TopbarPlus.new()
	codesIcon
		:setName("Codes")
		:setImage(Icons.Pictures[EIcons.Ticket].Image)
		:modifyTheme({ "IconImage", "ImageRectOffset", Icons.Pictures[EIcons.Ticket].Offset })
		:modifyTheme({ "IconImage", "ImageRectSize", Icons.PICTURE_CELL_SIZE })
		:setCaption("Codes")
		:align("Right")
		:bindEvent("selected", function()
			swapTo(CodesController.Open, CodesController.IsOpen)
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
		:setImage(Icons.Pictures[EIcons.Gear].Image)
		:modifyTheme({ "IconImage", "ImageRectOffset", Icons.Pictures[EIcons.Gear].Offset })
		:modifyTheme({ "IconImage", "ImageRectSize", Icons.PICTURE_CELL_SIZE })
		:setCaption("Settings")
		:align("Right")
		:bindEvent("selected", function()
			swapTo(SettingsController.Open, SettingsController.IsOpen)
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
	nextPlayCall = nextGemGlint + PLAY_CALL_OFFSET
	if ProfileController.IsLoaded then showProfile() end
	ProfileController.OnChanged:Connect(showProfile)
	syncLevel()
	ProfileController.OnChanged:Connect(syncLevel)

	-- A key a text box took (chat) is typing, not a press; and a screen over the lobby covers the HUD's keys.
	UserInputService.InputBegan:Connect(function(input: InputObject, isProcessed: boolean)
		if isProcessed or input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		if state.IsCovered() then return end
		state.HeldKey(input.KeyCode)
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if state.HeldKey() == input.KeyCode then state.HeldKey(nil) end
	end)
	-- A click or a tap on an open place's body that no button took. A tap has no hover, so it is aimed from its own
	-- point (inset-excluded, which ScreenPointToRay expects).
	UserInputService.InputBegan:Connect(function(input: InputObject, isProcessed: boolean)
		if isProcessed or state.IsInviteOpen() then return end
		local ghost
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			ghost = hoveredGhost
		elseif input.UserInputType == Enum.UserInputType.Touch and ghostPad ~= 0 then
			local point = input.Position
			ghost = ghostAlong(Workspace.CurrentCamera:ScreenPointToRay(point.X, point.Y))
		end
		if ghost then pressGhost(ghost) end
	end)

	vide.mount(function()
		-- The settings screen shuts by its own X too: the icon is let go with it.
		vide.effect(function()
			if not SettingsController.IsOpen() then settingsIcon:deselect() end
		end)
		vide.effect(function()
			if not CodesController.IsOpen() then codesIcon:deselect() end
		end)
		-- The daily screen shuts by its EXIT and its dim, and opens by itself once a visit: the icon follows it (its selected
		-- event then finds the screen up, and swapTo leaves it).
		vide.effect(function()
			if DailyController.IsOpen() then
				dailyIcon:select()
			else
				dailyIcon:deselect()
			end
		end)
		vide.effect(function()
			WeaponsController.IsOpen()
			IndexController.IsOpen()
			QuestsController.IsOpen()
			LobbyEnteringController.IsOpen()
			DailyController.IsOpen()
			SettingsController.IsOpen()
			CodesController.IsOpen()
			ShopController.IsOpen()
			MutationController.IsOpen()
			vide.untrack(updateCover)
		end)
		-- In the shooting range the gun's crosshair takes the pointer's place, as in a match; anywhere else, and over
		-- any screen, the lobby keeps Roblox's pointer.
		vide.effect(function()
			local isAiming = RangeController.IsInside()
				and not isScreenUp()
				and not DailyController.IsOpen()
				and not SettingsController.IsOpen()
				and not CodesController.IsOpen()
			CrosshairController.SetShown(isAiming)
		end)
		vide.effect(function()
			state.IsDailyReady(DailyRewardsController.IsClaimable())
			state.IsDailyWaiting(DailyController.Waiting() > 0)
		end)
		vide.effect(function()
			state.IndexCount(IndexController.NewCount())
		end)
		vide.effect(function()
			state.QuestsReady(QuestsController.ReadyCount())
		end)
		vide.effect(function()
			state.CanUpgradeWeapons(WeaponsController.CanUpgrade())
		end)
		vide.effect(function()
			state.CanBrew(MutationController.CanBrew())
		end)
		vide.effect(function()
			-- Not while an upgrade's Gems are in the air: its level is held until they land.
			state.CanUpgradeClasses(not state.IsUpgrading() and canUpgradeClasses())
		end)
		vide.effect(function()
			local held = DailyRewardsController.HeldGems()
				+ SpinsController.HeldGems()
				+ QuestsController.HeldGems()
				+ CodesController.HeldGems()
				+ ShopController.HeldGems()
			local isFed = DailyRewardsController.IsLandingGems()
				or SpinsController.IsLandingGems()
				or QuestsController.IsLandingGems()
				or CodesController.IsLandingGems()
				or ShopController.IsLandingGems()
			vide.untrack(function()
				holdGems(held, isFed)
			end)
		end)
		-- A spin's or a code's XP rolls into the plate a slice at a time as it lands.
		vide.effect(function()
			local held = SpinsController.HeldXp() + CodesController.HeldXp()
			vide.untrack(function()
				if held == state.XpHeld() then return end
				state.XpHeld(held)
				if isProfileShown then showProfile() end
			end)
		end)

		return {
			create("ScreenGui")({
				Name = "Lobby",
				ResetOnSpawn = false,
				IgnoreGuiInset = true,
				ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
				ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
				-- Scaled from a 1080-tall design, as the HUD is, under Roblox's top bar. The level plate and the Gems
				-- counter have their own gui (below).
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
					Bar.Build(state),
				}),
			}),
			Party.Build(state, actions),
			Queue.Build(state, actions),
			Invite.Build(state, actions),
			PadExit.Build(state, actions),
			Invitation.Build(state, actions),
			Classes.Build(state, actions, {
				Pieces = EquipmentController.BuildPage(),
				FadeSeconds = EquipmentController.FADE_SECONDS,
			}),
			-- The level plate and the Gems counter over every lobby screen and its dim (they are at 5) and over the
			-- shop's receipt and the codes (6), whose Gems and XP fly into them, under the settings (10). Laid from the
			-- screen's top, as the pages are: they stand up in Roblox's top bar strip.
			create("ScreenGui")({
				Name = "Top",
				ResetOnSpawn = false,
				IgnoreGuiInset = true,
				ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
				ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
				DisplayOrder = 7,
				create("Frame")({
					Name = "Root",
					BackgroundTransparency = 1,
					Size = function()
						local scale = state.Scale()
						return UDim2.fromScale(1 / scale, 1 / scale)
					end,
					create("UIScale")({ Scale = state.Scale }),
					Hud.BuildTop(state, actions),
				}),
			}),
			Board.Build(state),
		}
	end, LocalPlayer:WaitForChild("PlayerGui"))

	RunService.Heartbeat:Connect(function()
		vide.batch(update)
	end)
end

return Ignis.Register(LobbyController)
