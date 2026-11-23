-- The physical lobby (GDD 3, start-game area): queue pads that fill up, count down and teleport their party into a
-- match together. The first player on an empty pad is its host and picks the party (size, map, access); the Play
-- button puts a player on a free pad as host, or into an open party. A player on a pad is held there (his root is
-- anchored) until he presses Exit, so a step aside cannot drop him out of a party that is about to leave.
--
-- The client only carries a one-time token (GlobalServer.Utils.JoinData), so nothing it can edit reaches the match.
-- Zones are polled, not Touched: a poll cannot miss a player who teleported or respawned onto a pad.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TeleportService = game:GetService("TeleportService")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local NetworkMeta = require(ServerScriptService.GlobalServer.NetworkMeta)
local DatabaseService = require(ServerScriptService.GlobalServer.Services.DatabaseService)
local JoinData = require(ServerScriptService.GlobalServer.Utils.JoinData)
local MapsCore = require(ReplicatedStorage.GlobalShared.Core.MapsCore)
local PadsCore = require(ReplicatedStorage.Shared.Core.PadsCore)
local Components = require(ReplicatedStorage.GlobalShared.ECS.Components)
local World = require(ReplicatedStorage.GlobalShared.ECS.Worlds.World)
local getCharacterEntityFromPlayer =
	require(ReplicatedStorage.GlobalShared.Utils.Functions.getCharacterEntityFromPlayer)
local EPlaceIds = require(ReplicatedStorage.Types.Enums.EPlaceIds)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)

local ServerNetworkLobby = NetworkMeta.Server.Lobby
local ClientNetworkLobby = NetworkMeta.Client.Lobby

local EPhase = PadsCore.EPhase
local ERefusal = PadsCore.ERefusal

local Tune = table.freeze({
	ZONE_POLL_SECONDS = 0.2,
	-- How long a body that joined a pad has to come to rest before it is anchored where it is. Meanwhile the poll
	-- trusts it is on the pad: its client stops it (the controls go off with PadJoined), and after Play the old
	-- position can still arrive for a moment.
	ARRIVAL_GRACE_SECONDS = 1,
	-- Under this speed (studs a second) and within this of standing height it has come to rest: the top of a jump
	-- is slow too.
	SETTLED_SPEED = 0.5,
	SETTLED_HEIGHT = 0.5,
	-- A body anchored outside the pad's footprint is put back this far inside its edge.
	EDGE_INSET = 1.5,
	-- A standing body's root over the floor under its feet.
	STAND_HEIGHT = 3,
	-- How far from the pad's centre Play scatters a character, as a share of the pad's half size.
	ARRIVAL_SCATTER = 0.6,
	-- Where Exit puts him: this far out from the pad's +Z side, so every pad is turned with its +Z to the way out.
	EXIT_STUDS = 5,
})

local NO_COUNTDOWN = -1

type TPad = {
	Index: number,
	Part: BasePart,
	Phase: number,
	-- The first member; whoever picked the party, or took it over when the host left.
	Host: Player?,
	Members: { Player },
	MaxPlayers: number,
	Map: MapsCore.TMap,
	IsFriendsOnly: boolean,
	-- os.clock() the countdown ends at, or nil when none is running.
	EndsAt: number?,
	-- Destination server reserved during the countdown. Codes never expire and
	-- cost nothing until used, so a cancelled countdown keeps its code for the next one.
	ReservedCode: string?,
	IsReserving: boolean,
}

local LobbyService = {}

local pads: { TPad } = {}
local padOfPlayer: { [Player]: TPad } = {}
-- The root anchored while its player is on a pad, once it has come to rest there.
local heldRoot: { [Player]: BasePart } = {}
-- os.clock() until which a player who joined a pad is neither anchored while still moving nor taken off it for
-- standing elsewhere.
local arrivingUntil: { [Player]: number } = {}
-- The last refusal sent per player, so standing on a pad he cannot join tells him once rather than every poll.
local refusalSent: { [Player]: TPad } = {}
-- player -> host UserId -> friends. Filled asynchronously: IsFriendsWithAsync is a web call, so each pair is fetched
-- once, and the poll every 0.2 s waits on the one fetch in flight.
local friendsOf: { [Player]: { [number]: boolean } } = {}
local friendFetching: { [Player]: { [number]: boolean } } = {}
local pollAccumulator = 0

local function secondsLeft(pad: TPad): number
	local endsAt = pad.EndsAt
	if not endsAt then return NO_COUNTDOWN end
	return math.max(endsAt - os.clock(), 0)
end

-- PadState's arguments, in its order.
local function stateOf(pad: TPad): (number, number, number, number, number, boolean, number, number)
	local host = pad.Host
	local hostId = if host then host.UserId else 0
	local map = MapsCore.INDEX[pad.Map.Name]
	return pad.Index, pad.Phase, #pad.Members, pad.MaxPlayers, map, pad.IsFriendsOnly, hostId, secondsLeft(pad)
end

-- To everybody, or to one player who just joined.
local function sendState(pad: TPad, player: Player?)
	if player then
		ServerNetworkLobby.PadState.Fire(player, stateOf(pad))
		return
	end

	ServerNetworkLobby.PadState.FireAll(stateOf(pad))
end

local function refuse(player: Player, pad: TPad, reason: number)
	if refusalSent[player] == pad then return end
	refusalSent[player] = pad
	ServerNetworkLobby.PadRefused.Fire(player, pad.Index, reason)
end

local function resetPad(pad: TPad)
	pad.Phase = EPhase.Empty
	pad.Host = nil
	pad.MaxPlayers = PadsCore.DEFAULT_PLAYERS
	pad.Map = MapsCore.MAPS[MapsCore.DEFAULT]
	pad.IsFriendsOnly = false
	pad.EndsAt = nil
end

local function prefetchReservedServer(pad: TPad)
	if pad.ReservedCode or pad.IsReserving or RunService:IsStudio() or EPlaceIds.Game == 0 then return end
	pad.IsReserving = true
	task.spawn(function()
		local ok, code = pcall(TeleportService.ReserveServer, TeleportService, EPlaceIds.Game)
		pad.IsReserving = false
		if ok then pad.ReservedCode = code end
	end)
end

-- A full pad has no reason to keep its party waiting.
local function shortenIfFull(pad: TPad)
	if #pad.Members < pad.MaxPlayers then return end
	local fullEndsAt = os.clock() + PadsCore.FULL_COUNTDOWN_SECONDS
	pad.EndsAt = if pad.EndsAt then math.min(pad.EndsAt, fullEndsAt) else fullEndsAt
end

-- nil while the answer is still being fetched.
local function isFriendOfHost(player: Player, host: Player): boolean?
	local known = friendsOf[player]
	if not known then
		known = {}
		friendsOf[player] = known
	end

	local fetching = friendFetching[player]
	if not fetching then
		fetching = {}
		friendFetching[player] = fetching
	end

	local hostId = host.UserId
	local cached = known[hostId]
	if cached ~= nil then return cached end
	if fetching[hostId] then return nil end

	fetching[hostId] = true
	task.spawn(function()
		local ok, result = pcall(player.IsFriendsWithAsync, player, hostId)
		fetching[hostId] = nil
		known[hostId] = ok and result == true
	end)

	return nil
end

-- Whether the player could join this pad now, and the refusal to show if not (0 for one that needs no notice).
local function canJoin(player: Player, pad: TPad): (boolean, number)
	if pad.Phase == EPhase.Empty then return true, 0 end
	if pad.Phase ~= EPhase.Open or #pad.Members >= pad.MaxPlayers then return false, 0 end

	-- The hard map's gate (GDD 20) is checked per player: everyone on its pad has earned it.
	local profile = DatabaseService.Get(player)
	if not profile then return false, 0 end
	if not MapsCore.IsUnlocked(profile, pad.Map.Name) then return false, ERefusal.Locked end

	local host = pad.Host
	if pad.IsFriendsOnly and host and host ~= player then
		local isFriend = isFriendOfHost(player, host)
		if isFriend == nil then return false, 0 end
		if not isFriend then return false, ERefusal.FriendsOnly end
	end

	return true, 0
end

local function getRoot(player: Player): BasePart?
	local characterEntity = getCharacterEntityFromPlayer(player)
	return if characterEntity then World:get(characterEntity, Components.HumanoidRootPart) else nil
end

-- The body's root standing on the pad's top over the pad-space point (x, z), facing as it does now. Written to the
-- root's CFrame, never PivotTo: an R6 character's pivot is its Head, 1.5 studs higher.
local function standingAt(pad: TPad, rootPart: BasePart, x: number, z: number): CFrame
	local part = pad.Part
	local position = part.CFrame:PointToWorldSpace(Vector3.new(x, part.Size.Y / 2 + Tune.STAND_HEIGHT, z))
	return CFrame.new(position) * rootPart.CFrame.Rotation
end

local function isAtRest(pad: TPad, rootPart: BasePart): boolean
	if rootPart.AssemblyLinearVelocity.Magnitude >= Tune.SETTLED_SPEED then return false end
	local height = pad.Part.CFrame:PointToObjectSpace(rootPart.Position).Y - pad.Part.Size.Y / 2
	return math.abs(height - Tune.STAND_HEIGHT) < Tune.SETTLED_HEIGHT
end

-- Anchored where it came to rest, so nobody can push it off a party that is about to leave. Only once at rest:
-- anchored while walking, the walk clip never hears the body stop and plays for as long as it is held. A body
-- that did not stop on the pad is stood back inside it first.
local function hold(player: Player, pad: TPad, rootPart: BasePart)
	if not PadsCore.IsOnPad(pad.Part, rootPart.Position) then
		local onPad = pad.Part.CFrame:PointToObjectSpace(rootPart.Position)
		local reach = pad.Part.Size / 2 - Vector3.one * Tune.EDGE_INSET
		local x = math.clamp(onPad.X, -reach.X, reach.X)
		local z = math.clamp(onPad.Z, -reach.Z, reach.Z)
		rootPart.CFrame = standingAt(pad, rootPart, x, z)
	end

	rootPart.Anchored = true
	heldRoot[player] = rootPart
end

-- Free to walk again, and off the pad in front of it if it still stands there (a respawn's new body does not).
local function release(player: Player, pad: TPad)
	local held = heldRoot[player]
	heldRoot[player] = nil
	if held then held.Anchored = false end
	local rootPart = getRoot(player)
	if not rootPart or not PadsCore.IsOnPad(pad.Part, rootPart.Position) then return end
	rootPart.CFrame = standingAt(pad, rootPart, 0, pad.Part.Size.Z / 2 + Tune.EXIT_STUDS)
end

function LobbyService.Join(player: Player, pad: TPad)
	if padOfPlayer[player] then return end
	local isAllowed, refusal = canJoin(player, pad)
	if not isAllowed then
		if refusal ~= 0 then refuse(player, pad, refusal) end
		return
	end

	refusalSent[player] = nil
	pad.Members[#pad.Members + 1] = player
	padOfPlayer[player] = pad
	arrivingUntil[player] = os.clock() + Tune.ARRIVAL_GRACE_SECONDS
	if pad.Phase == EPhase.Empty then
		pad.Phase = EPhase.Choosing
		pad.Host = player
	else
		shortenIfFull(pad)
	end

	ServerNetworkLobby.PadJoined.Fire(player, pad.Index)
	sendState(pad)
end

function LobbyService.Leave(player: Player)
	local pad = padOfPlayer[player]
	if not pad then return end
	padOfPlayer[player] = nil
	arrivingUntil[player] = nil
	local index = table.find(pad.Members, player)
	if index then table.remove(pad.Members, index) end

	-- Only an Open pad has members besides its host: it keeps what was picked and the next in line holds it.
	if #pad.Members == 0 then
		resetPad(pad)
	elseif pad.Host == player then
		pad.Host = pad.Members[1]
	end

	release(player, pad)
	if player.Parent then ServerNetworkLobby.PadJoined.Fire(player, 0) end
	sendState(pad)
end

-- Stores the payload and reserves a server at the same time, returning the access code. Errors re-raise so the
-- caller's pcall treats either failing as the teleport failing.
local function storeAndReserve(token: string, message: any, placeId: number): string
	local reserveOk, reserveResult
	local storeOk, storeResult
	local remaining = 2
	local done = Instance.new("BindableEvent")
	task.spawn(function()
		reserveOk, reserveResult = pcall(TeleportService.ReserveServer, TeleportService, placeId)
		remaining -= 1
		if remaining == 0 then done:Fire() end
	end)

	task.spawn(function()
		storeOk, storeResult = pcall(JoinData.StoreAsync, token, message)
		remaining -= 1
		if remaining == 0 then done:Fire() end
	end)

	if remaining > 0 then done.Event:Wait() end
	done:Destroy()
	if not storeOk then error(storeResult, 0) end
	if not reserveOk then error(reserveResult, 0) end
	return reserveResult
end

local function startTeleport(pad: TPad)
	pad.Phase = EPhase.Teleporting
	pad.EndsAt = nil

	-- Read everything before the first yield: a member leaving mid-teleport can empty the pad.
	local players = table.clone(pad.Members)
	local message = { SupposedPlayers = #players, PadName = pad.Part.Name, MapName = pad.Map.Name }
	local placeId = EPlaceIds.Game
	local reservedCode = pad.ReservedCode
	sendState(pad)

	local ok, err = pcall(function()
		if RunService:IsStudio() then error("Studio cannot teleport: play the lobby in a live server", 0) end
		if placeId == 0 then error("no arena place id (EPlaceIds)", 0) end
		local token = HttpService:GenerateGUID(false)
		local code: string
		if reservedCode then
			code = reservedCode
			JoinData.StoreAsync(token, message)
		else
			code = storeAndReserve(token, message, placeId)
		end

		TeleportService:TeleportToPrivateServer(placeId, code, players, nil, { SecureToken = token })
	end)

	if ok then
		-- The code is spent on this party; the next one reserves its own. The members stay on the pad, shown as
		-- teleporting, until they leave the server.
		pad.ReservedCode = nil
		return
	end

	warn("[LobbyService] teleport failed:", err)

	-- Whoever is still here stays queued and gets a fresh countdown.
	if #pad.Members == 0 then
		resetPad(pad)
	else
		pad.Phase = EPhase.Open
		pad.EndsAt = os.clock() + PadsCore.COUNTDOWN_SECONDS
	end

	sendState(pad)
end

-- A party the player could join now: an empty pad first, so Play makes him a host; else a party with room.
local function findPadForPlay(player: Player): TPad?
	for _, pad in pads do
		if pad.Phase == EPhase.Empty then return pad end
	end

	for _, pad in pads do
		if pad.Phase == EPhase.Open and canJoin(player, pad) then return pad end
	end

	return nil
end

local function moveOnto(player: Player, pad: TPad)
	local rootPart = getRoot(player)
	if not rootPart then return end
	local reach = pad.Part.Size / 2 * Tune.ARRIVAL_SCATTER
	local x = (math.random() * 2 - 1) * reach.X
	local z = (math.random() * 2 - 1) * reach.Z
	rootPart.CFrame = standingAt(pad, rootPart, x, z)
end

local function poll()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local rootPart = getRoot(player)
		local position = if rootPart then rootPart.Position else nil

		local current = padOfPlayer[player]
		local isArriving = (arrivingUntil[player] or 0) > now
		if current and rootPart and not heldRoot[player] then
			if not isArriving or isAtRest(current, rootPart) then hold(player, current, rootPart) end
		end

		-- Held, he cannot walk off; off his pad all the same means he died or respawned.
		if current and not isArriving and (not position or not PadsCore.IsOnPad(current.Part, position)) then
			if current.Phase ~= EPhase.Teleporting then LobbyService.Leave(player) end
			continue
		end

		if current or not position then continue end

		local isOnAny = false
		for _, pad in pads do
			if not PadsCore.IsOnPad(pad.Part, position) then continue end
			isOnAny = true
			LobbyService.Join(player, pad)
			break
		end

		-- Off every pad: the next pad he steps on may tell him why it refuses, even the same one again.
		if not isOnAny then refusalSent[player] = nil end
	end

	for _, pad in pads do
		local endsAt = pad.EndsAt
		if endsAt and pad.Phase == EPhase.Open and now >= endsAt then task.spawn(startTeleport, pad) end
	end
end

LobbyService.OnStart = function()
	for index, part in PadsCore.GetPads() do
		local pad: TPad = {
			Index = index,
			Part = part,
			Phase = EPhase.Empty,
			Host = nil,
			Members = {},
			MaxPlayers = PadsCore.DEFAULT_PLAYERS,
			Map = MapsCore.MAPS[MapsCore.DEFAULT],
			IsFriendsOnly = false,
			EndsAt = nil,
			ReservedCode = nil,
			IsReserving = false,
		}
		pads[index] = pad
	end

	if #pads == 0 then warn("[LobbyService] no pads under Workspace.Lobby.Pads") end

	RunService.Heartbeat:Connect(function(dt: number)
		pollAccumulator += dt
		if pollAccumulator < Tune.ZONE_POLL_SECONDS then return end
		pollAccumulator = 0
		poll()
	end)
end

LobbyService.OnPlayerConnected = function(player: Player)
	for _, pad in pads do
		sendState(pad, player)
	end
end :: TPlayerEvents.OnPlayerConnected

-- The menu's locks and requirements (GDD 8: show the exact requirement in matchmaking). Records only change in a
-- match, so once per visit is enough.
LobbyService.OnDataLoaded = function(player: Player)
	local profile = DatabaseService.Get(player)
	if not profile then return end
	local bests = table.create(#MapsCore.LIST)
	for index, map in MapsCore.LIST do
		bests[index] = math.min(MapsCore.BestCompleted(profile, map.Name), 65535)
	end

	ServerNetworkLobby.MapRecords.Fire(player, bests)
end :: TPlayerEvents.OnDataLoaded

LobbyService.OnPlayerDisconnected = function(player: Player)
	LobbyService.Leave(player)
	arrivingUntil[player] = nil
	refusalSent[player] = nil
	friendsOf[player] = nil
	friendFetching[player] = nil
end :: TPlayerEvents.OnPlayerDisconnected

-- The Exit button. Leaving is always allowed but for a party already on its way.
ClientNetworkLobby.LeavePad.On(function(player: Player)
	local pad = padOfPlayer[player]
	if not pad or pad.Phase == EPhase.Teleporting then return end
	LobbyService.Leave(player)
end)

ClientNetworkLobby.Play.On(function(player: Player)
	if padOfPlayer[player] then return end
	if not getCharacterEntityFromPlayer(player) then return end
	if not DatabaseService.Get(player) then return end
	local pad = findPadForPlay(player)
	if not pad then
		ServerNetworkLobby.PadRefused.Fire(player, 0, ERefusal.NoFreePad)
		return
	end

	moveOnto(player, pad)
	LobbyService.Join(player, pad)
end)

-- The call to teleport returned, but this player's teleport did not start: release him so he can queue again.
TeleportService.TeleportInitFailed:Connect(function(player: Player, result: Enum.TeleportResult, message: string)
	warn(`[LobbyService] teleport of {player.Name} failed: {result.Name} {message}`)
	local pad = padOfPlayer[player]
	if not pad or pad.Phase ~= EPhase.Teleporting then return end
	LobbyService.Leave(player)
end)

ClientNetworkLobby.StartParty.On(function(player: Player, maxPlayers: number, mapIndex: number, isFriendsOnly: boolean)
	local pad = padOfPlayer[player]
	if not pad or pad.Host ~= player or pad.Phase ~= EPhase.Choosing then return end
	if maxPlayers < 1 or maxPlayers > PadsCore.MAX_PLAYERS then return end
	local map = MapsCore.LIST[mapIndex]
	if not map then return end
	local profile = DatabaseService.Get(player)
	if not profile or not MapsCore.IsUnlocked(profile, map.Name) then return end

	pad.MaxPlayers = maxPlayers
	pad.Map = map
	pad.IsFriendsOnly = isFriendsOnly
	pad.Phase = EPhase.Open
	pad.EndsAt = os.clock() + PadsCore.COUNTDOWN_SECONDS
	shortenIfFull(pad)
	prefetchReservedServer(pad)
	sendState(pad)
end)

return Ignis.Register(LobbyService)
