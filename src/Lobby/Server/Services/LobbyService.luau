-- The physical lobby (GDD 3, start-game area): queue pads that fill up, count down and teleport their party into a
-- match together. The first player on an empty pad is its host and picks the party (size, map, access); the Play
-- button puts a player on a free pad as host, or into an open party. Joining puts the body on its spot at once
-- (PadsCore.SPOTS: the host in the middle, the rest at the sides), held there (its root anchored) until Exit, so a step
-- aside cannot drop anyone out of a party that is about to leave. A party with room can invite anyone in the server, and
-- JOIN on the invite puts them on its pad from wherever they stand.
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
local EInvite = PadsCore.EInvite

local Tune = table.freeze({
	ZONE_POLL_SECONDS = 0.2,
	-- How long a body put on its spot has to come to rest before it is anchored anyway. Meanwhile the poll trusts it
	-- is on the pad: its client stops it (the controls go off with PadJoined), and the old position can still arrive
	-- for a moment.
	ARRIVAL_GRACE_SECONDS = 1,
	-- Under this speed (studs a second) and within this of standing height it has come to rest: the top of a jump
	-- is slow too.
	SETTLED_SPEED = 0.5,
	SETTLED_HEIGHT = 0.5,
	-- A standing body's root over the floor under its feet.
	STAND_HEIGHT = 3,
	-- Where Exit puts him: this far out from the pad's +Z side, so every pad is turned with its +Z to the way out.
	EXIT_STUDS = 5,
	-- How far outside a pad's zone (studs) a body that says it stepped in may still be here: its position arrives a
	-- frame or two after its request.
	STEP_SLACK = 3,
	-- A JOIN this late on an invite still counts: it left the invitee's screen up to a round trip ago.
	INVITE_SLACK_SECONDS = 1.5,
	-- How soon the same player may invite the same player again: a press held down is one invite.
	INVITE_COOLDOWN_SECONDS = 3,
	-- A member still here this long after the party's teleport went out is released anyway: a teleport that neither
	-- completes nor fails must not hold a body anchored and the pad taken.
	TELEPORT_TIMEOUT_SECONDS = 30,
})

local NO_COUNTDOWN = -1

type TPad = {
	Index: number,
	Part: BasePart,
	Phase: number,
	-- The first member; whoever picked the party, or took it over when the host left.
	Host: Player?,
	Members: { Player },
	-- Each member's index into PadsCore.SPOTS, kept while they stay: a leaver's spot goes to the next to join.
	Spots: { [Player]: number },
	MaxPlayers: number,
	Map: MapsCore.TMap,
	-- MapsCore.DIFFICULTIES, by name.
	Difficulty: string,
	IsFriendsOnly: boolean,
	-- os.clock() the countdown ends at, or nil when none is running.
	EndsAt: number?,
	-- Destination server reserved during the countdown. Codes never expire and
	-- cost nothing until used, so a cancelled countdown keeps its code for the next one.
	ReservedCode: string?,
	IsReserving: boolean,
	-- os.clock() whoever is still on the pad is released at, set only once the party's teleport went out.
	ReleaseAt: number?,
	-- Counts the parties the pad has held: an invite names the party it came from, not a later one on the same pad.
	Run: number,
}

-- An invite a player holds from a party: who sent it, that party's Run, and the os.clock() it lapses at.
type TInvite = { From: Player, Run: number, EndsAt: number }

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
-- The invites each player holds, by the pad they came from.
local invitesTo: { [Player]: { [TPad]: TInvite } } = {}
-- When each player last invited each other one (by user id), and until when a party a player turned down may not
-- invite them again (by pad, for its Run).
local invitedAt: { [Player]: { [number]: number } } = {}
local declinedUntil: { [Player]: { [TPad]: { Run: number, Until: number } } } = {}

local function secondsLeft(pad: TPad): number
	local endsAt = pad.EndsAt
	if not endsAt then return NO_COUNTDOWN end
	return math.max(endsAt - os.clock(), 0)
end

-- PadState's arguments, in its order.
local function stateOf(pad: TPad): (number, number, number, number, number, number, boolean, number, number)
	local host = pad.Host
	local hostId = if host then host.UserId else 0
	local map = MapsCore.INDEX[pad.Map.Name]
	local difficulty = table.find(MapsCore.DIFFICULTIES, pad.Difficulty) or 1
	return pad.Index,
		pad.Phase,
		#pad.Members,
		pad.MaxPlayers,
		map,
		difficulty,
		pad.IsFriendsOnly,
		hostId,
		secondsLeft(pad)
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
	pad.Run += 1
	pad.Phase = EPhase.Empty
	pad.Host = nil
	table.clear(pad.Spots)
	pad.MaxPlayers = PadsCore.DEFAULT_PLAYERS
	pad.Map = MapsCore.LIST[1]
	pad.Difficulty = MapsCore.DIFFICULTIES[1]
	pad.IsFriendsOnly = false
	pad.EndsAt = nil
	pad.ReleaseAt = nil
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

-- Whether the player could join this pad now, and the refusal to show if not (0 for one that needs no notice). A
-- player the party invited needs no friendship with its host.
local function canJoin(player: Player, pad: TPad, isInvited: boolean?): (boolean, number)
	if pad.Phase == EPhase.Empty then return true, 0 end
	if pad.Phase == EPhase.Choosing then return false, ERefusal.Busy end
	if pad.Phase ~= EPhase.Open or #pad.Members >= pad.MaxPlayers then return false, 0 end

	-- The hard map's gate (GDD 20) is checked per player: everyone on its pad has earned it.
	local profile = DatabaseService.Get(player)
	if not profile then return false, 0 end
	if not MapsCore.IsUnlocked(profile, pad.Map.Name) then return false, ERefusal.Locked end

	local host = pad.Host
	if pad.IsFriendsOnly and host and host ~= player and not isInvited then
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

-- Why the party on `pad` may not invite `target` now (PadsCore.EInvite), or nil when it may.
local function inviteRefusal(target: Player, pad: TPad): number?
	local onPad = padOfPlayer[target]
	if onPad then return if onPad == pad then EInvite.Joined else EInvite.InParty end
	if #pad.Members >= pad.MaxPlayers then return EInvite.Full end
	local profile = DatabaseService.Get(target)
	if not profile or not getRoot(target) then return EInvite.Away end
	if not MapsCore.IsUnlocked(profile, pad.Map.Name) then return EInvite.Locked end
	local turnedDown = declinedUntil[target]
	local declined = if turnedDown then turnedDown[pad] else nil
	if declined and declined.Run == pad.Run and os.clock() < declined.Until then return EInvite.Declined end
	return nil
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

-- The root standing on the member's spot, facing the front.
local function standingOnSpot(pad: TPad, spot: number): CFrame
	return PadsCore.SpotAt(pad.Part, spot) * CFrame.new(0, Tune.STAND_HEIGHT, 0)
end

-- The lowest spot no member stands on.
local function freeSpot(pad: TPad): number
	for index in PadsCore.SPOTS do
		local isTaken = false
		for _, taken in pad.Spots do
			if taken == index then
				isTaken = true
				break
			end
		end
		if not isTaken then return index end
	end

	return 1
end

-- Anchored on its spot, so nobody can push it off a party that is about to leave. Only once at rest: anchored while
-- walking, the walk clip never hears the body stop and plays for as long as it is held. Stood on the spot again
-- first, in case the client's old position arrived after Join put it there.
local function hold(player: Player, pad: TPad, rootPart: BasePart)
	local spot = pad.Spots[player]
	if spot then rootPart.CFrame = standingOnSpot(pad, spot) end
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

function LobbyService.Join(player: Player, pad: TPad, isInvited: boolean?)
	if padOfPlayer[player] then return end
	local isAllowed, refusal = canJoin(player, pad, isInvited)
	if not isAllowed then
		if refusal ~= 0 then refuse(player, pad, refusal) end
		return
	end

	refusalSent[player] = nil
	invitesTo[player] = nil
	local spot = freeSpot(pad)
	pad.Members[#pad.Members + 1] = player
	pad.Spots[player] = spot
	padOfPlayer[player] = pad
	arrivingUntil[player] = os.clock() + Tune.ARRIVAL_GRACE_SECONDS

	-- Stood on the spot at once, and still, so the first poll finds it at rest and anchors it there.
	local rootPart = getRoot(player)
	if rootPart then
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.CFrame = standingOnSpot(pad, spot)
	end

	if pad.Phase == EPhase.Empty then
		pad.Phase = EPhase.Choosing
		pad.Host = player
		pad.EndsAt = os.clock() + PadsCore.CHOOSE_SECONDS
	else
		shortenIfFull(pad)
	end

	-- The state first: both go out in one buffer in call order, and a client told it is on a pad it still knows as
	-- Empty shows the queue screen (EXIT, the countdown) for a moment before the host's party screen.
	sendState(pad)
	ServerNetworkLobby.PadJoined.Fire(player, pad.Index)
end

function LobbyService.Leave(player: Player)
	local pad = padOfPlayer[player]
	if not pad then return end
	padOfPlayer[player] = nil
	arrivingUntil[player] = nil
	pad.Spots[player] = nil
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

-- The menu's locks and requirements (GDD 8: show the exact requirement in matchmaking): each map's best wave, its boss
-- kills and whether its unlock has played. Sent as the profile loads and as a console command changes them: the rest
-- only change in a match.
function LobbyService.SendMapRecords(player: Player)
	local profile = DatabaseService.Get(player)
	if not profile then return end
	local bossKills = profile.BossKills or {}
	local shown = profile.MapsShown or {}
	local records = table.create(#MapsCore.LIST)
	for index, map in MapsCore.LIST do
		records[index] = {
			Best = math.min(MapsCore.BestCompleted(profile, map.Name), 65535),
			BossKills = math.min(bossKills[map.Name] or 0, 65535),
			IsShown = shown[map.Name] == true,
		}
	end

	ServerNetworkLobby.MapRecords.Fire(player, records)
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
	local message = {
		SupposedPlayers = #players,
		PadName = pad.Part.Name,
		MapName = pad.Map.Name,
		Difficulty = pad.Difficulty,
	}
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
		-- teleporting, until they leave the server or TELEPORT_TIMEOUT_SECONDS runs out.
		pad.ReservedCode = nil
		pad.ReleaseAt = os.clock() + Tune.TELEPORT_TIMEOUT_SECONDS
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
		local releaseAt = pad.ReleaseAt
		if releaseAt and now >= releaseAt then
			-- Leave takes each off the members list, and the last one resets the pad.
			for _, member in table.clone(pad.Members) do
				LobbyService.Leave(member)
			end
			continue
		end

		local endsAt = pad.EndsAt
		if not endsAt or now < endsAt then continue end
		if pad.Phase == EPhase.Open then
			task.spawn(startTeleport, pad)
		elseif pad.Phase == EPhase.Choosing and pad.Host then
			-- Picked nothing in time: the pad goes back to whoever comes next.
			local host = pad.Host
			ServerNetworkLobby.PadRefused.Fire(host, pad.Index, ERefusal.Idle)
			LobbyService.Leave(host)
		end
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
			Spots = {},
			MaxPlayers = PadsCore.DEFAULT_PLAYERS,
			Map = MapsCore.LIST[1],
			Difficulty = MapsCore.DIFFICULTIES[1],
			IsFriendsOnly = false,
			EndsAt = nil,
			ReservedCode = nil,
			IsReserving = false,
			ReleaseAt = nil,
			Run = 0,
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

LobbyService.OnDataLoaded = function(player: Player)
	LobbyService.SendMapRecords(player)
end :: TPlayerEvents.OnDataLoaded

LobbyService.OnPlayerDisconnected = function(player: Player)
	LobbyService.Leave(player)
	arrivingUntil[player] = nil
	refusalSent[player] = nil
	friendsOf[player] = nil
	friendFetching[player] = nil
	invitesTo[player] = nil
	invitedAt[player] = nil
	declinedUntil[player] = nil
end :: TPlayerEvents.OnPlayerDisconnected

-- The Exit button. Leaving is always allowed but for a party already on its way.
ClientNetworkLobby.LeavePad.On(function(player: Player)
	local pad = padOfPlayer[player]
	if not pad or pad.Phase == EPhase.Teleporting then return end
	LobbyService.Leave(player)
end)

-- The client asks the moment its body crosses into a pad's zone, so it is put on its spot then rather than at the
-- next poll. The poll still finds anyone who never asks.
ClientNetworkLobby.StepOnPad.On(function(player: Player, index: number)
	local pad = pads[index]
	if not pad or padOfPlayer[player] then return end
	local rootPart = getRoot(player)
	if not rootPart or not PadsCore.IsOnPad(pad.Part, rootPart.Position, Tune.STEP_SLACK) then return end
	LobbyService.Join(player, pad)
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

	LobbyService.Join(player, pad)
end)

-- Anyone in an open party with room may invite anyone in this server who could join it. The invitee holds it until it
-- lapses or they answer; a second press on the same player is the same invite and is not sent again.
ClientNetworkLobby.InvitePlayer.On(function(player: Player, userId: number)
	local pad = padOfPlayer[player]
	if not pad or pad.Phase ~= EPhase.Open then return end
	local target = Players:GetPlayerByUserId(userId)
	if not target or target == player then return end
	local sent = invitedAt[player]
	if not sent then
		sent = {}
		invitedAt[player] = sent
	end
	local now = os.clock()
	if now - (sent[userId] or -math.huge) < Tune.INVITE_COOLDOWN_SECONDS then return end
	sent[userId] = now

	local refusal = inviteRefusal(target, pad)
	if refusal then
		ServerNetworkLobby.InviteAnswered.Fire(player, userId, refusal)
		return
	end

	local held = invitesTo[target]
	if not held then
		held = {}
		invitesTo[target] = held
	end
	local current = held[pad]
	local isNew = not current or current.Run ~= pad.Run or now >= current.EndsAt
	if isNew then
		held[pad] = { From = player, Run = pad.Run, EndsAt = now + PadsCore.INVITE_SECONDS }
		ServerNetworkLobby.Invited.Fire(target, pad.Index, player.UserId, PadsCore.INVITE_SECONDS)
	end
	ServerNetworkLobby.InviteAnswered.Fire(player, userId, EInvite.Sent)
end)

-- JOIN puts the invitee on the party's pad wherever they stand, as a step onto it would; a friends-only party lets them
-- in. Either answer is told to whoever sent the invite.
ClientNetworkLobby.AnswerInvite.On(function(player: Player, index: number, isJoining: boolean)
	local pad = pads[index]
	local held = invitesTo[player]
	local invite = if pad and held then held[pad] else nil
	if not pad or not held or not invite then return end
	held[pad] = nil
	local inviter = invite.From
	local isSameParty = invite.Run == pad.Run and pad.Phase == EPhase.Open
	if not isJoining then
		if isSameParty then
			local declined = declinedUntil[player] or {}
			declined[pad] = { Run = pad.Run, Until = os.clock() + PadsCore.INVITE_DECLINED_SECONDS }
			declinedUntil[player] = declined
		end
		if inviter.Parent then ServerNetworkLobby.InviteAnswered.Fire(inviter, player.UserId, EInvite.Declined) end
		return
	end

	if padOfPlayer[player] or not getRoot(player) then return end
	if not isSameParty or os.clock() > invite.EndsAt + Tune.INVITE_SLACK_SECONDS then
		ServerNetworkLobby.PadRefused.Fire(player, pad.Index, ERefusal.Expired)
		return
	end

	LobbyService.Join(player, pad, true)
	if padOfPlayer[player] ~= pad or not inviter.Parent then return end
	ServerNetworkLobby.InviteAnswered.Fire(inviter, player.UserId, EInvite.Joined)
end)

-- The call to teleport returned, but this player's teleport did not start: release him so he can queue again.
TeleportService.TeleportInitFailed:Connect(function(player: Player, result: Enum.TeleportResult, message: string)
	warn(`[LobbyService] teleport of {player.Name} failed: {result.Name} {message}`)
	local pad = padOfPlayer[player]
	if not pad or pad.Phase ~= EPhase.Teleporting then return end
	LobbyService.Leave(player)
end)

-- Only an open map's unlock can have played. Not answered: the screen marked it on its side as it played.
ClientNetworkLobby.MapShown.On(function(player: Player, mapIndex: number)
	local map = MapsCore.LIST[mapIndex]
	if not map then return end
	DatabaseService.Update(player, function(profile)
		if not MapsCore.IsUnlocked(profile, map.Name) then return false end
		local shown = profile.MapsShown or {}
		if shown[map.Name] then return false end
		shown[map.Name] = true
		profile.MapsShown = shown
		return true
	end)
end)

ClientNetworkLobby.StartParty.On(
	function(player: Player, maxPlayers: number, mapIndex: number, difficultyIndex: number, isFriendsOnly: boolean)
		local pad = padOfPlayer[player]
		if not pad or pad.Host ~= player or pad.Phase ~= EPhase.Choosing then return end
		if maxPlayers < 1 or maxPlayers > PadsCore.MAX_PLAYERS then return end
		local map = MapsCore.LIST[mapIndex]
		if not map then return end
		local difficulty = MapsCore.DIFFICULTIES[difficultyIndex]
		if not difficulty then return end
		local profile = DatabaseService.Get(player)
		if not profile or not MapsCore.IsUnlocked(profile, map.Name) then return end

		pad.MaxPlayers = maxPlayers
		pad.Map = map
		pad.Difficulty = difficulty
		pad.IsFriendsOnly = isFriendsOnly
		pad.Phase = EPhase.Open
		pad.EndsAt = os.clock() + PadsCore.COUNTDOWN_SECONDS
		shortenIfFull(pad)
		prefetchReservedServer(pad)
		sendState(pad)
	end
)

return Ignis.Register(LobbyService)
