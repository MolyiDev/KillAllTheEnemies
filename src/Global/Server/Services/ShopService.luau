-- The shop's purchases (ShopCore), in both places: every Gem pack, featured gun, bundle and pass bought for oneself or
-- as a gift, which passes each player holds (bought here, on the game's page, or given), and who is VIP.
--
-- A GIFT GOES THROUGH THE RECEIVER'S INBOX, a DataStore key of their own that any server may write: the receipt moves
-- the buyer's pick (PendingGift) into their GiftsOut in the write that claims it, the inbox is written from there, and
-- the receiver takes it into their profile with a receipt of its own. Each step can be retried, so a gift is never
-- lost or granted twice, and one to a player who has left reaches them the next time they load.
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local NetworkMeta = require(ServerScriptService.GlobalServer.NetworkMeta)
local DatabaseService = require(script.Parent.DatabaseService)
local PurchasesService = require(script.Parent.PurchasesService)
local LoadoutCore = require(ReplicatedStorage.GlobalShared.Core.LoadoutCore)
local ShopCore = require(ReplicatedStorage.GlobalShared.Core.ShopCore)
local getStoreName = require(ReplicatedStorage.GlobalShared.Utils.Functions.getStoreName)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)
local TProfile = require(ReplicatedStorage.Types.TProfile)

local ServerNetworkShop = NetworkMeta.Server.Shop
local ClientNetworkShop = NetworkMeta.Client.Shop

-- A gift entry waiting in an inbox.
type TInboxEntry = { Id: string, Offer: string, From: string }

local Tune = table.freeze({
	-- An inbox holds at most this many gifts; past it the oldest wait in the givers' GiftsOut.
	MAX_INBOX = 50,
	-- A second past the featured gun's change, so a clock a hair behind still reads the new one.
	ROLLOVER_MARGIN = 1,
})

local GIFT_SENT = 0
local GIFT_REFUSED = 1

local ShopService = {}

local inbox = DataStoreService:GetDataStore(`{getStoreName()}_Gifts`)
local offerIndex: { [string]: number } = {}
for index, offer in ShopCore.OFFERS do
	offerIndex[offer.Name] = index
end

-- PolicyService's word per player: true until it has answered, so nothing random is sold before it does.
local restricted: { [Player]: boolean } = {}
-- The last State each player was sent, so a profile change that does not touch it sends nothing.
local lastState: { [Player]: string } = {}
local vips: { [Player]: boolean } = {}
local isClaiming: { [Player]: boolean } = {}
local isDelivering: { [Player]: boolean } = {}

-- Whether paid random items (the spins' extras and luck) are off for this player.
function ShopService.IsRandomRestricted(player: Player): boolean
	return restricted[player] ~= false
end

-- Puts what `offer` gives into the profile. A pass or bundle gives its contents once; a gun already owned is paid as
-- its price in Gems. `isGift`: a pass the receiver got meanwhile is paid as its Robux in Gems, so a gift is never
-- wasted. Returns the Gems paid in place of what was held already, for the receipt to say.
local function grant(profile: TProfile.TProfile, offer: ShopCore.TOffer, now: number, isGift: boolean): number
	local refund = 0
	if offer.GamePassId ~= 0 then
		if ShopCore.HasPass(profile, offer.Name) then
			if isGift then
				refund = ShopCore.RobuxToGems(offer.Robux)
				profile.Gems += refund
			end
			return refund
		end
		profile.Entitlements[offer.Name] = true
	end

	for _, content in offer.Contents do
		if content.Kind == "Gems" then
			profile.Gems += content.Amount :: number
		elseif content.Kind == "Class" then
			local classId = content.ClassId :: number
			if not table.find(profile.OwnedClasses, classId) then table.insert(profile.OwnedClasses, classId) end
		else
			local name = if content.Kind == "FeaturedGun" then ShopCore.FeaturedGun(now) else content.Name :: string
			local gun = LoadoutCore.ByName[name]
			if profile.Loadout.Owned[name] ~= nil or gun.Price == 0 then
				profile.Gems += gun.Price
				refund += gun.Price
			else
				profile.Loadout.Owned[name] = 1
			end
		end
	end

	return refund
end

local function stateOf(player: Player, profile: TProfile.TProfile): ({ number }, boolean, number, boolean)
	local now = os.time()
	local owned = {}
	for index, offer in ShopCore.OFFERS do
		if offer.GamePassId ~= 0 and ShopCore.HasPass(profile, offer.Name) then table.insert(owned, index) end
	end

	local hasFeatured = profile.Loadout.Owned[ShopCore.FeaturedGun(now)] ~= nil
	return owned, ShopService.IsRandomRestricted(player), ShopCore.FeaturedSecondsLeft(now), hasFeatured
end

local function vipIds(): { number }
	local userIds = {}
	for player in vips do
		table.insert(userIds, player.UserId)
	end

	return userIds
end

local function sendVips()
	ServerNetworkShop.Vips.FireAll(vipIds())
end

-- Sends the shop's State when it changed (or always, `isForced`), and the VIP list when this player's VIP did.
local function send(player: Player, profile: TProfile.TProfile, isForced: boolean?)
	local owned, isRestricted, secondsLeft, hasFeatured = stateOf(player, profile)
	local key = `{table.concat(owned, ",")}|{isRestricted}|{ShopCore.FeaturedGun(os.time())}|{hasFeatured}`
	if isForced or lastState[player] ~= key then
		lastState[player] = key
		ServerNetworkShop.State.Fire(player, owned, isRestricted, secondsLeft, hasFeatured)
	end

	local isVip = ShopCore.HasPass(profile, "Vip")
	if (vips[player] == true) == isVip then return end
	vips[player] = if isVip then true else nil
	sendVips()
end

-- A pass bought, on the game's page or here: its contents once, saved at once.
local function grantPass(player: Player, offer: ShopCore.TOffer)
	local refund = 0
	local isNew = DatabaseService.Update(player, function(profile)
		if ShopCore.HasPass(profile, offer.Name) then return false end
		refund = grant(profile, offer, os.time(), false)
		return true
	end)
	if not isNew then return end

	DatabaseService.SaveAsync(player)
	ServerNetworkShop.Granted.Fire(player, offerIndex[offer.Name], "", refund)
end

-- Passes bought where this server could not see: on the website, or in another server.
local function syncPasses(player: Player)
	for _, offer in ShopCore.OFFERS do
		if offer.GamePassId == 0 then continue end
		local profile = DatabaseService.Get(player)
		if not profile or ShopCore.HasPass(profile, offer.Name) then continue end
		local ok, isOwned =
			pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, offer.GamePassId)
		if ok and isOwned and player.Parent then grantPass(player, offer) end
	end
end

-- Takes every gift waiting in `player`'s inbox into their profile, then empties it of them. A gift whose receipt is
-- already in the profile was taken before a crash: it is only cleared.
local function claim(player: Player)
	if isClaiming[player] then return end
	isClaiming[player] = true

	local key = tostring(player.UserId)
	local ok, entries = pcall(inbox.GetAsync, inbox, key)
	if not ok or type(entries) ~= "table" or #entries == 0 then
		isClaiming[player] = nil
		return
	end

	local taken: { TInboxEntry } = {}
	local refunds: { number } = {}
	local now = os.time()
	local isWritten = DatabaseService.Update(player, function(profile)
		for _, entry: TInboxEntry in entries do
			local offer = ShopCore.ByName[entry.Offer]
			if not offer or not DatabaseService.ClaimReceipt(profile, `gift:{entry.Id}`) then continue end
			table.insert(refunds, grant(profile, offer, now, true))
			table.insert(taken, entry)
		end
		return true
	end)

	if isWritten and DatabaseService.Save(player) then
		local ids = {}
		for _, entry: TInboxEntry in entries do
			ids[entry.Id] = true
		end
		pcall(inbox.UpdateAsync, inbox, key, function(current: { TInboxEntry }?)
			local kept = {}
			for _, entry in current or {} do
				if not ids[entry.Id] then table.insert(kept, entry) end
			end
			return kept
		end)

		for index, entry in taken do
			if player.Parent then
				ServerNetworkShop.Granted.Fire(player, offerIndex[entry.Offer], entry.From, refunds[index])
			end
		end
	end

	isClaiming[player] = nil
end

-- Writes the gifts `giver` paid for into their receivers' inboxes, then out of the giver's profile. Run after a gift
-- receipt is saved and as the giver loads, so one a crash left behind still goes.
local function deliver(giver: Player)
	if isDelivering[giver] then return end
	isDelivering[giver] = true

	local profile = DatabaseService.Get(giver)
	local outgoing = if profile then profile.GiftsOut else nil
	for _, gift in outgoing or {} do
		local isIn = false
		local ok = pcall(inbox.UpdateAsync, inbox, tostring(gift.UserId), function(current: { TInboxEntry }?)
			local entries = current or {}
			for _, entry in entries do
				if entry.Id ~= gift.Id then continue end
				isIn = true
				return nil
			end
			if #entries >= Tune.MAX_INBOX then return nil end
			table.insert(entries, { Id = gift.Id, Offer = gift.Offer, From = giver.DisplayName })
			isIn = true
			return entries
		end)
		if not ok or not isIn then continue end

		DatabaseService.Update(giver, function(draft)
			local list = draft.GiftsOut or {}
			for index, entry in list do
				if entry.Id == gift.Id then table.remove(list, index) end
			end
			draft.GiftsOut = if #list > 0 then list else nil
			return true
		end)
		DatabaseService.SaveAsync(giver)

		local receiver = Players:GetPlayerByUserId(gift.UserId)
		ServerNetworkShop.GiftResult.Fire(
			giver,
			offerIndex[gift.Offer],
			if receiver then receiver.DisplayName else "",
			GIFT_SENT
		)
		if receiver then task.spawn(claim, receiver) end
	end

	isDelivering[giver] = nil
end

local function registerProducts()
	for productId, entry in ShopCore.ByProduct do
		local offer = entry.Offer
		if not entry.IsGift then
			PurchasesService.Register(productId, function(player, profile)
				local refund = grant(profile, offer, os.time(), false)
				return true,
					function()
						ServerNetworkShop.Granted.Fire(player, offerIndex[offer.Name], "", refund)
					end
			end)
			continue
		end

		-- With no pick for this offer to go to (it was overwritten by another), the giver gets it themselves.
		PurchasesService.Register(productId, function(player, profile, receiptId)
			local pending = profile.PendingGift
			if not pending or pending.Offer ~= offer.Name or pending.UserId == player.UserId then
				local refund = grant(profile, offer, os.time(), true)
				return true,
					function()
						ServerNetworkShop.Granted.Fire(player, offerIndex[offer.Name], "", refund)
					end
			end

			local outgoing = profile.GiftsOut or {}
			table.insert(outgoing, { Id = receiptId, Offer = offer.Name, UserId = pending.UserId })
			profile.GiftsOut = outgoing
			profile.PendingGift = nil
			return true, function()
				deliver(player)
			end
		end)
	end
end

-- Rotates the featured gun: everybody is told, since its seconds and ownership change with it.
local function rollOver()
	for _, player in Players:GetPlayers() do
		local profile = DatabaseService.Get(player)
		if profile then send(player, profile, true) end
	end

	task.delay(ShopCore.FeaturedSecondsLeft(os.time()) + Tune.ROLLOVER_MARGIN, rollOver)
end

ShopService.OnStart = function()
	registerProducts()
	task.delay(ShopCore.FeaturedSecondsLeft(os.time()) + Tune.ROLLOVER_MARGIN, rollOver)
end

ShopService.OnPlayerConnected = function(player: Player)
	local ok, policy = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, player)
	if not player.Parent then return end
	restricted[player] = not ok or policy.ArePaidRandomItemsRestricted == true

	-- What depends on it (the shop, the spins' count) is sent again. An answer after the profile loaded is the case
	-- this covers: every mirror of the profile resends on this signal.
	local profile = DatabaseService.Get(player)
	if profile then DatabaseService.OnProfileChanged:Fire(player, profile) end
end :: TPlayerEvents.OnPlayerConnected

ShopService.OnDataLoaded = function(player: Player)
	local profile = DatabaseService.Get(player)
	if not profile then return end
	send(player, profile, true)
	ServerNetworkShop.Vips.Fire(player, vipIds())

	syncPasses(player)
	deliver(player)
	claim(player)
end :: TPlayerEvents.OnDataLoaded

ShopService.OnPlayerDisconnected = function(player: Player)
	restricted[player] = nil
	lastState[player] = nil
	isClaiming[player] = nil
	isDelivering[player] = nil
	if vips[player] then
		vips[player] = nil
		sendVips()
	end
end :: TPlayerEvents.OnPlayerDisconnected

DatabaseService.OnProfileChanged:Connect(function(player: Player, profile: TProfile.TProfile)
	send(player, profile)
end)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, isPurchased: boolean)
	local offer = ShopCore.ByPass[passId]
	if isPurchased and offer then grantPass(player, offer) end
end)

-- A gift pick: the giver's and the receiver's profiles loaded, the receiver here and not the giver, able to hold it
-- (not held already, nothing random where it is restricted for either). The pick is kept in the giver's profile, so
-- the receipt finds it on any server, then the gift product is prompted.
ClientNetworkShop.Gift.On(function(player: Player, index: number, userId: number)
	local offer = ShopCore.OFFERS[index]
	if not offer or offer.GiftProductId == 0 then return end
	local receiver = Players:GetPlayerByUserId(userId)
	local receiverProfile = if receiver then DatabaseService.Get(receiver) else nil
	local name = if receiver then receiver.DisplayName else ""
	local isRandomRefused = offer.IsRandomItem
		and (ShopService.IsRandomRestricted(player) or (receiver ~= nil and ShopService.IsRandomRestricted(receiver)))
	if
		not receiver
		or receiver == player
		or not receiverProfile
		or ShopCore.IsOwned(receiverProfile, offer, os.time())
		or isRandomRefused
	then
		ServerNetworkShop.GiftResult.Fire(player, index, name, GIFT_REFUSED)
		return
	end

	local isKept = DatabaseService.Update(player, function(profile)
		profile.PendingGift = { Offer = offer.Name, UserId = userId }
		return true
	end)
	if not isKept then return end
	DatabaseService.SaveAsync(player)
	MarketplaceService:PromptProductPurchase(player, offer.GiftProductId)
end)

return Ignis.Register(ShopService)
