-- The lobby's start-game area on screen (GDD 3): every pad's colour and board, PLAY / EXIT, the queue's status, and
-- the host's party menu. The server decides everything (LobbyService); this draws what it is told and sends requests.
-- A pad's green or red is this player's own answer to "could I step on now", which is why it is drawn here.
--
-- A countdown is sent as seconds left at the moment of a change and counted down here, so the server only sends on a
-- change rather than every second.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local vide = require(ReplicatedStorage.Packages.vide)
local NetworkMeta = require(StarterPlayer.StarterPlayerScripts.GlobalClient.NetworkMeta)
-- Through PlayerScripts, the copy that runs: requiring the StarterPlayer one would load a second controller.
local SettingsController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.SettingsController)
local TopbarPlus = require(ReplicatedStorage.GlobalShared.TopbarPlus)
local Icons = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Icons)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local MapsCore = require(ReplicatedStorage.GlobalShared.Core.MapsCore)
local PadsCore = require(ReplicatedStorage.Shared.Core.PadsCore)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local Bar = require(script.Bar)
local Menu = require(script.Menu)
local PadArt = require(script.PadArt)
local PadBoard = require(script.PadBoard)
local Types = require(script.Types)

local ServerNetworkLobby = NetworkMeta.Server.Lobby
local ClientNetworkLobby = NetworkMeta.Client.Lobby

local LocalPlayer = Players.LocalPlayer
local source = vide.source
local create = vide.create
local EPhase = PadsCore.EPhase
local ERefusal = PadsCore.ERefusal

local TOAST_SECONDS = 3
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
}

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
}

local function update()
	local viewport = Workspace.CurrentCamera.ViewportSize
	state.Scale(math.clamp(viewport.Y / Theme.DESIGN_HEIGHT, Theme.MIN_SCALE, Theme.MAX_SCALE))

	local now = os.clock()
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

ServerNetworkLobby.PadJoined.On(function(index: number)
	state.CurrentPad(index)
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

ServerNetworkLobby.MapRecords.On(function(bests: { number })
	local byName = {}
	for index, map in MapsCore.LIST do
		byName[map.Name] = bests[index] or 0
	end

	state.BestByMap(byName)
	tintPads()
end)

LobbyController.OnStart = function()
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

	update()
	updateChoosing()
	tintPads()
	-- The lobby's screens are not in the designer's look yet, so its Settings icon wears the top bar's own.
	local settingsIcon = TopbarPlus.new()
	settingsIcon
		:setName("Settings")
		:setImage(Icons.IMAGE)
		:modifyTheme({ "IconImage", "ImageRectOffset", Icons.Cells.Settings })
		:modifyTheme({ "IconImage", "ImageRectSize", Icons.CELL_SIZE })
		:setCaption("Settings")
		:align("Right")
		:bindEvent("selected", SettingsController.Open)
		:bindEvent("deselected", SettingsController.Close)
	-- TopbarPlus builds its own button, so it never gets Components.ButtonSounds: the same two sounds, by hand.
	local clickRegion = settingsIcon:getInstance("ClickRegion")
	clickRegion.MouseEnter:Connect(SoundsCore.PlayHover)
	clickRegion.Activated:Connect(SoundsCore.PlayClick)

	vide.mount(function()
		-- The settings screen shuts by its own X too: the icon is let go with it.
		vide.effect(function()
			if not SettingsController.IsOpen() then settingsIcon:deselect() end
		end)

		return {
			create("ScreenGui")({
				Name = "Lobby",
				ResetOnSpawn = false,
				IgnoreGuiInset = true,
				ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
				ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
				-- Scaled from a 1080-tall design, as the HUD is.
				create("Frame")({
					Name = "Root",
					BackgroundTransparency = 1,
					Size = function()
						local scale = state.Scale()
						return UDim2.fromScale(1 / scale, 1 / scale)
					end,
					create("UIScale")({ Scale = state.Scale }),
					Bar.Build(state, actions),
					Menu.Build(state, actions),
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
