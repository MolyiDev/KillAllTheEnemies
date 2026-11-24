-- The invite reward: a friend who comes into the game for the first time by a player's invite (Roblox's referral
-- link, GetJoinData().ReferredByPlayerId) on an account at least Tune.MIN_ACCOUNT_DAYS old pays that player
-- Tune.GEMS, for up to Tune.MAX_FRIENDS friends. The banner on Roblox's invite screen that promises it is set on the
-- Creator Hub (Engagement > Referral Rewards), and its terms must say these numbers: change one, change them there.
--
-- THE REWARD GOES THROUGH THE INVITER'S INBOX, as a gift does (ShopService): the friend's server writes it into a
-- DataStore key of the inviter's, and the inviter's server takes it into their profile with the friend's id in the
-- same write, so each step can be retried and no friend pays twice. An inviter in another lobby server is told through
-- MessagingService; one in a match or offline finds it on their next load into the lobby.
local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Conch = require(ReplicatedStorage.Packages.conch)
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local NetworkMeta = require(ServerScriptService.GlobalServer.NetworkMeta)
local DatabaseService = require(ServerScriptService.GlobalServer.Services.DatabaseService)
local getStoreName = require(ReplicatedStorage.GlobalShared.Utils.Functions.getStoreName)
local TJoinData = require(ReplicatedStorage.Types.TJoinData)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)

local ServerNetworkInvites = NetworkMeta.Server.Invites

-- A friend waiting in an inbox: their user id and display name.
type TInboxEntry = { UserId: number, Name: string }

local Tune = table.freeze({
	GEMS = 1000,
	-- Friends who pay, per inviter: past it a friend is taken from the inbox without paying, so new accounts made to
	-- farm it stop paying. Invites.Rewarded's u8.
	MAX_FRIENDS = 20,
	-- A friend's account must be this old (Player.AccountAge) when they first join, so one made to farm it pays nothing.
	MIN_ACCOUNT_DAYS = 7,
	-- An inbox holds at most this many friends not taken yet; past it a friend waits in their own profile (InvitedBy
	-- unset) and is posted again on their next load.
	MAX_INBOX = 50,
})
local TOPIC = "Invites"
local PERMISSION_DEV = "command.dev"

local InvitesService = {}

local inbox = DataStoreService:GetDataStore(`{getStoreName()}_Invites`)
local isClaiming: { [Player]: boolean } = {}
-- A friend posted while a claim was reading the inbox: it runs again once that one is done.
local isClaimAgain: { [Player]: boolean } = {}

-- Pays `player` for each friend in `entries` not paid already, while under MAX_FRIENDS. Returns whether the inbox may
-- let go of them: not while the profile is closed (it took nothing) or a payment is not saved.
local function take(player: Player, entries: { TInboxEntry }): boolean
	local isOpen = false
	local paid: { TInboxEntry } = {}
	local friends = 0
	local isPaid = DatabaseService.Update(player, function(profile)
		isOpen = true
		local list = profile.InvitedFriends or {}
		for _, entry in entries do
			if #list >= Tune.MAX_FRIENDS then break end
			if table.find(list, entry.UserId) then continue end
			table.insert(list, entry.UserId)
			table.insert(paid, entry)
			profile.Gems += Tune.GEMS
		end
		profile.InvitedFriends = list
		friends = #list
		return #paid > 0
	end)
	if not isOpen then return false end
	if not isPaid then return true end

	-- In the same frame as the profile it paid, so the HUD's hold is in place before it draws the new Gems. The
	-- document closes a frame after its player leaves, so a write can still land on one who has gone.
	for index, entry in paid do
		if not player.Parent then break end
		ServerNetworkInvites.Rewarded.Fire(player, entry.Name, Tune.GEMS, friends - #paid + index, Tune.MAX_FRIENDS)
	end

	return DatabaseService.Save(player)
end

-- Takes `entries` out of the inbox at `key`, keeping any friend posted since they were read.
local function drop(key: string, entries: { TInboxEntry })
	local ids = {}
	for _, entry in entries do
		ids[entry.UserId] = true
	end

	pcall(inbox.UpdateAsync, inbox, key, function(current: { TInboxEntry }?)
		local kept = {}
		local entries: { TInboxEntry } = current or {}
		for _, entry in entries do
			if not ids[entry.UserId] then table.insert(kept, entry) end
		end
		return kept
	end)
end

-- Takes every friend waiting in `player`'s inbox into their profile, then out of the inbox.
local function claim(player: Player)
	if isClaiming[player] then
		isClaimAgain[player] = true
		return
	end
	if not DatabaseService.Get(player) then return end
	isClaiming[player] = true

	local key = tostring(player.UserId)
	local ok, entries = pcall(inbox.GetAsync, inbox, key)
	if ok and type(entries) == "table" and #entries > 0 and take(player, entries) then drop(key, entries) end

	isClaiming[player] = nil
	if not isClaimAgain[player] or not player.Parent then return end
	isClaimAgain[player] = nil
	claim(player)
end

-- Writes a friend into `inviterId`'s inbox and tells the inviter's server, wherever it is. Returns whether they are
-- in it (already, or now).
local function post(inviterId: number, userId: number, name: string): boolean
	local isIn = false
	local ok = pcall(
		inbox.UpdateAsync,
		inbox,
		tostring(inviterId),
		function(current: { TInboxEntry }?): { TInboxEntry }?
			isIn = false
			local entries: { TInboxEntry } = current or {}
			for _, entry in entries do
				if entry.UserId ~= userId then continue end
				isIn = true
				return nil
			end
			if #entries >= Tune.MAX_INBOX then return nil end
			table.insert(entries, { UserId = userId, Name = name })
			isIn = true
			return entries
		end
	)
	if not ok or not isIn then return false end

	local inviter = Players:GetPlayerByUserId(inviterId)
	if inviter then
		task.spawn(claim, inviter)
	else
		pcall(MessagingService.PublishAsync, MessagingService, TOPIC, inviterId)
	end
	return true
end

-- A player's first load: who invited them, kept for good (0 for nobody) once the inviter's inbox holds them. A post
-- that failed leaves it unset, so the next load tries again.
local function arrive(player: Player)
	local profile = DatabaseService.Get(player)
	if not profile or profile.InvitedBy ~= nil then return end
	local joinData = player:GetJoinData() :: TJoinData.TJoin
	local inviterId = joinData.ReferredByPlayerId or 0
	local isInvited = inviterId > 0 and inviterId ~= player.UserId and player.AccountAge >= Tune.MIN_ACCOUNT_DAYS
	if isInvited and not post(inviterId, player.UserId, player.DisplayName) then return end

	local isKept = DatabaseService.Update(player, function(draft)
		if draft.InvitedBy ~= nil then return false end
		draft.InvitedBy = if isInvited then inviterId else 0
		return true
	end)
	if isKept then DatabaseService.SaveAsync(player) end
end

-- `invite friend <userId>` has that account join by your invite, through your inbox like a real one; `invite clear`
-- takes your invites back to a new player's, so the next join counts as a first.
local function registerInvite()
	Conch.register("invite", {
		permissions = { PERMISSION_DEV },
		description = "Have an account join by your invite, or clear your invites back to a new player's.",
		arguments = function()
			return Conch.args.overload({
				{
					description = "A friend joins by your invite",
					arguments = {
						Conch.args.literal("friend"),
						Conch.args.number("userId", "The friend's user id."),
					},
				},
				{
					description = "Clear your invites",
					arguments = { Conch.args.literal("clear") },
				},
			})
		end,
		callback = function(verb: string, userId: number?)
			local player = (Conch.get_command_context() :: any).executor.player :: Player?
			if not player or not DatabaseService.Get(player) then return end
			if verb == "clear" then
				local isCleared = DatabaseService.Update(player, function(profile)
					profile.InvitedBy = nil
					profile.InvitedFriends = nil
					return true
				end)
				if isCleared then Conch.log("normal", "Invites cleared.") end
				return
			end

			local id = math.floor(userId or 0)
			if not (id > 0) or id == player.UserId then
				Conch.log("error", "The user id must be another account's.")
				return
			end
			-- Conch.log finds its player by the command's thread, so the spawned one logs through log_to.
			task.spawn(function()
				local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, id)
				if post(player.UserId, id, if ok then name else `Friend{id}`) then
					Conch.log_to(player, "normal", `{if ok then name else id} joined by your invite.`)
				else
					Conch.log_to(player, "error", "The inbox could not be written.")
				end
			end)
		end,
	})
end

InvitesService.OnStart = function()
	registerInvite()

	-- A friend posted on another server: claimed here if the inviter is here.
	task.spawn(function()
		local ok, err = pcall(MessagingService.SubscribeAsync, MessagingService, TOPIC, function(message)
			if type(message.Data) ~= "number" then return end
			local inviter = Players:GetPlayerByUserId(message.Data)
			if inviter then task.spawn(claim, inviter) end
		end)
		if not ok then warn("[InvitesService] SubscribeAsync failed:", err) end
	end)
end

InvitesService.OnDataLoaded = function(player: Player)
	arrive(player)
	claim(player)
end :: TPlayerEvents.OnDataLoaded

InvitesService.OnPlayerDisconnected = function(player: Player)
	isClaiming[player] = nil
	isClaimAgain[player] = nil
end :: TPlayerEvents.OnPlayerDisconnected

return Ignis.Register(InvitesService)
