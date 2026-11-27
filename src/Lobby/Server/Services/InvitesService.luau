-- The invite reward: a friend who comes into the game for the first time by a player's invite (Roblox's referral
-- link, GetJoinData().ReferredByPlayerId) on an account at least Tune.MIN_ACCOUNT_DAYS old pays that player
-- Tune.GEMS, for up to Tune.MAX_FRIENDS friends. The banner on Roblox's invite screen that promises it is set on the
-- Creator Hub (Engagement > Referral Rewards), and its terms must say these numbers: change one, change them there.
--
-- THE REWARD GOES THROUGH THE INVITER'S INBOX, as a gift does (ShopService): the friend's server writes it into a
-- DataStore key of the inviter's, and the inviter's server takes it into their profile with the friend's id in the
-- same write, so each step can be retried and no friend pays twice. An inviter in another lobby server is told through
-- MessagingService; one in a match or offline finds it on their next load into the lobby.
--
-- THE SURPRISE GIFT: the lobby's toast (offered once a visit, Invites.Gift) sends its invite tagged
-- (InvitesCore.GIFT_LAUNCH_DATA), and the first friend to join by a tagged invite pays Tune.GIFT_GEMS instead of
-- Tune.GEMS, once per player ever, under the same rules. The referral banner's terms must say it too.
local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Conch = require(ReplicatedStorage.Packages.conch)
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local NetworkMeta = require(ServerScriptService.GlobalServer.NetworkMeta)
local DatabaseService = require(ServerScriptService.GlobalServer.Services.DatabaseService)
local InvitesCore = require(ReplicatedStorage.Shared.Core.InvitesCore)
local getStoreName = require(ReplicatedStorage.GlobalShared.Utils.Functions.getStoreName)
local TJoinData = require(ReplicatedStorage.Types.TJoinData)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)

local ServerNetworkInvites = NetworkMeta.Server.Invites
local ClientNetworkInvites = NetworkMeta.Client.Invites

-- A friend waiting in an inbox: their user id and display name, and whether they came by the surprise gift's invite.
type TInboxEntry = { UserId: number, Name: string, IsGift: boolean? }
-- A friend paid for: who, the Gems, and whether it was the surprise gift.
type TPaid = { Entry: TInboxEntry, Gems: number, IsGift: boolean }

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
	-- The surprise gift: what its friend pays in place of GEMS, and how many times its toast may be turned down before
	-- it stops coming.
	GIFT_GEMS = 5000,
	GIFT_DECLINES = 3,
	-- Its toast comes in a random number of seconds into a lobby visit, between these.
	GIFT_AFTER_MIN = 45,
	GIFT_AFTER_MAX = 120,
})
local TOPIC = "Invites"
local PERMISSION_DEV = "command.dev"

local InvitesService = {}

local inbox = DataStoreService:GetDataStore(`{getStoreName()}_Invites`)
local isClaiming: { [Player]: boolean } = {}
-- A friend posted while a claim was reading the inbox: it runs again once that one is done.
local isClaimAgain: { [Player]: boolean } = {}
-- Offered the gift's toast this visit, until they turn it down.
local isGiftOffered: { [Player]: boolean } = {}
local random = Random.new()

-- Pays `player` for each friend in `entries` not paid already, while under MAX_FRIENDS. Returns whether the inbox may
-- let go of them: not while the profile is closed (it took nothing) or a payment is not saved.
local function take(player: Player, entries: { TInboxEntry }): boolean
	local isOpen = false
	local paid: { TPaid } = {}
	local friends = 0
	local isPaid = DatabaseService.Update(player, function(profile)
		isOpen = true
		local list = profile.InvitedFriends or {}
		local gift = profile.InviteGift or { IsPaid = false, Declines = 0 }
		for _, entry in entries do
			if #list >= Tune.MAX_FRIENDS then break end
			if table.find(list, entry.UserId) then continue end
			local isGift = entry.IsGift == true and not gift.IsPaid
			if isGift then gift.IsPaid = true end
			local gems = if isGift then Tune.GIFT_GEMS else Tune.GEMS
			table.insert(list, entry.UserId)
			table.insert(paid, { Entry = entry, Gems = gems, IsGift = isGift })
			profile.Gems += gems
		end
		profile.InvitedFriends = list
		if gift.IsPaid then profile.InviteGift = gift end
		friends = #list
		return #paid > 0
	end)
	if not isOpen then return false end
	if not isPaid then return true end

	-- In the same frame as the profile it paid, so the HUD's hold is in place before it draws the new Gems. The
	-- document closes a frame after its player leaves, so a write can still land on one who has gone.
	for index, friend in paid do
		if not player.Parent then break end
		-- Paid, the toast is taken back if it is still to come this visit.
		if friend.IsGift then
			isGiftOffered[player] = nil
			ServerNetworkInvites.Gift.Fire(player, 0, 0)
		end
		local count = friends - #paid + index
		ServerNetworkInvites.Rewarded.Fire(
			player,
			friend.Entry.Name,
			friend.Gems,
			count,
			Tune.MAX_FRIENDS,
			friend.IsGift
		)
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
local function post(inviterId: number, userId: number, name: string, isGift: boolean): boolean
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
			table.insert(entries, { UserId = userId, Name = name, IsGift = if isGift then true else nil })
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
	local isGift = joinData.LaunchData == InvitesCore.GIFT_LAUNCH_DATA
	if isInvited and not post(inviterId, player.UserId, player.DisplayName, isGift) then return end

	local isKept = DatabaseService.Update(player, function(draft)
		if draft.InvitedBy ~= nil then return false end
		draft.InvitedBy = if isInvited then inviterId else 0
		return true
	end)
	if isKept then DatabaseService.SaveAsync(player) end
end

-- Offers `player` the surprise gift's toast, `seconds` from now, if it is still theirs to win: not paid, not turned
-- down too often, and a friend left who could pay.
local function offerGift(player: Player, seconds: number)
	local profile = DatabaseService.Get(player)
	if not profile then return end
	local gift = profile.InviteGift
	if gift and (gift.IsPaid or gift.Declines >= Tune.GIFT_DECLINES) then return end
	local friends = profile.InvitedFriends
	if friends and #friends >= Tune.MAX_FRIENDS then return end

	isGiftOffered[player] = true
	ServerNetworkInvites.Gift.Fire(player, Tune.GIFT_GEMS, seconds)
end

-- `invite friend <userId>` has that account join by your invite, through your inbox like a real one, and
-- `invite gift <userId>` by the surprise gift's; `invite offer` brings the gift's toast in now; `invite clear` takes
-- your invites and the gift back to a new player's, so the next join counts as a first.
local function registerInvite()
	Conch.register("invite", {
		permissions = { PERMISSION_DEV },
		description = "Have an account join by your invite, bring the gift's toast in, or clear your invites.",
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
					description = "A friend joins by the surprise gift's invite",
					arguments = {
						Conch.args.literal("gift"),
						Conch.args.number("userId", "The friend's user id."),
					},
				},
				{
					description = "Bring the surprise gift's toast in now",
					arguments = { Conch.args.literal("offer") },
				},
				{
					description = "Clear your invites and the gift",
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
					profile.InviteGift = nil
					return true
				end)
				if isCleared then Conch.log("normal", "Invites cleared.") end
				return
			end
			if verb == "offer" then
				offerGift(player, 0)
				if not isGiftOffered[player] then
					Conch.log("error", "The gift is paid or turned down: clear first.")
				end
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
				if post(player.UserId, id, if ok then name else `Friend{id}`, verb == "gift") then
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
	if not player.Parent then return end
	offerGift(player, random:NextInteger(Tune.GIFT_AFTER_MIN, Tune.GIFT_AFTER_MAX))
end :: TPlayerEvents.OnDataLoaded

InvitesService.OnPlayerDisconnected = function(player: Player)
	isClaiming[player] = nil
	isClaimAgain[player] = nil
	isGiftOffered[player] = nil
end :: TPlayerEvents.OnPlayerDisconnected

-- The toast turned down: counted once a visit, until it stops coming. A gift paid meanwhile has nothing to count.
ClientNetworkInvites.DeclineGift.On(function(player: Player)
	if not isGiftOffered[player] then return end
	isGiftOffered[player] = nil
	local isCounted = DatabaseService.Update(player, function(profile)
		local gift = profile.InviteGift or { IsPaid = false, Declines = 0 }
		if gift.IsPaid then return false end
		gift.Declines += 1
		profile.InviteGift = gift
		return true
	end)
	if isCounted then DatabaseService.SaveAsync(player) end
end)

return Ignis.Register(InvitesService)
