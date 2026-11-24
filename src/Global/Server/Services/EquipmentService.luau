-- Each player's equipment (TProfile.Equipment, EquipmentCore) in both places: the lobby's equipment screen puts pieces
-- in their slots and on or off the avatar, a match's bosses give pieces (EquipmentDropsService), and every client draws
-- what each player wears (Equipment.Worn, EquipmentWearController). A match reads what the worn pieces add (StatOf).
-- Every request is answered with the player's whole equipment (Equipment.Sync), a refused one too, so the screen
-- waiting on it always hears back.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local NetworkMeta = require(ServerScriptService.GlobalServer.NetworkMeta)
local DatabaseService = require(script.Parent.DatabaseService)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local EquipmentCore = require(ReplicatedStorage.GlobalShared.Core.EquipmentCore)
local TData = require(ReplicatedStorage.Types.TData)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)
local TProfile = require(ReplicatedStorage.Types.TProfile)

local ServerNetworkEquipment = NetworkMeta.Server.Equipment
local ClientNetworkEquipment = NetworkMeta.Client.Equipment

local PIECES = DataCore.Equipment.ById

local EquipmentService = {}

-- Each loaded player's worn and shown piece Ids as everybody last heard them, and the same as one string to compare.
local sent: { [Player]: { Worn: { number }, Key: string } } = {}

-- What the pieces `player` wears add to `stat`; 0 while their profile is not open.
function EquipmentService.StatOf(player: Player, stat: TData.TEquipmentStat): number
	local profile = DatabaseService.Get(player)
	if not profile then return 0 end
	return EquipmentCore.StatOf(EquipmentCore.SaveOf(profile.Equipment), stat)
end

-- Sends the player's whole equipment (Equipment.Sync): after each of the screen's requests, and after anything else
-- that gives them a piece.
function EquipmentService.Sync(player: Player)
	local profile = DatabaseService.Get(player)
	if not profile then return end
	local save = EquipmentCore.SaveOf(profile.Equipment)

	local owned, hidden = {}, {}
	for _, item in EquipmentCore.All do
		if EquipmentCore.IsOwned(save, item) then table.insert(owned, item.Id) end
		if not EquipmentCore.IsShown(save, item) then table.insert(hidden, item.Id) end
	end
	local equipped = table.create(#EquipmentCore.SLOTS)
	for index, slot in EquipmentCore.SLOTS do
		local item = EquipmentCore.EquippedOf(save, slot)
		equipped[index] = if item then item.Id else 0
	end

	ServerNetworkEquipment.Sync.Fire(player, owned, equipped, hidden)
end

-- Changes `player`'s save through `mutate` (on a clone of it), which returns false to change nothing. Returns whether
-- it changed. The checks are made inside, on the profile as it is then.
local function change(player: Player, mutate: (save: TProfile.TEquipmentSave) -> boolean): boolean
	return DatabaseService.Update(player, function(profile)
		-- The draft is a deep clone already; a profile with no save yet starts from an empty one.
		local save = profile.Equipment or DatabaseService.DeepClone(EquipmentCore.EMPTY)
		if not mutate(save) then return false end
		profile.Equipment = save
		return true
	end)
end

-- Gives `player` `item` for good. Returns whether it is new to them; a new one is saved at once.
function EquipmentService.Grant(player: Player, item: TData.TEquipment): boolean
	local isNew = change(player, function(save)
		if EquipmentCore.IsOwned(save, item) then return false end
		save.Owned[item.Name] = true
		return true
	end)
	if not isNew then return false end

	DatabaseService.SaveAsync(player)
	EquipmentService.Sync(player)
	return true
end

-- The Ids of the pieces `save` wears and shows, in slot order.
local function wornOf(save: TProfile.TEquipmentSave): { number }
	local worn = {}
	for _, slot in EquipmentCore.SLOTS do
		local item = EquipmentCore.EquippedOf(save, slot)
		if item and EquipmentCore.IsShown(save, item) then table.insert(worn, item.Id) end
	end

	return worn
end

local function broadcast(player: Player, profile: TProfile.TProfile)
	local worn = wornOf(EquipmentCore.SaveOf(profile.Equipment))
	local key = table.concat(worn, ",")
	local last = sent[player]
	if last and last.Key == key then return end
	sent[player] = { Worn = worn, Key = key }
	ServerNetworkEquipment.Worn.FireAll(player, worn)
end

EquipmentService.OnDataLoaded = function(player: Player)
	local profile = DatabaseService.Get(player)
	if not profile then return end
	EquipmentService.Sync(player)

	-- Nobody has drawn a piece on a player who just loaded, so wearing none needs no word.
	sent[player] = { Worn = {}, Key = "" }
	broadcast(player, profile)
	for other, last in sent do
		if other == player or last.Key == "" or other.Parent ~= Players then continue end
		ServerNetworkEquipment.Worn.Fire(player, other, last.Worn)
	end
end :: TPlayerEvents.OnDataLoaded

EquipmentService.OnPlayerDisconnected = function(player: Player)
	sent[player] = nil
end :: TPlayerEvents.OnPlayerDisconnected

DatabaseService.OnProfileChanged:Connect(function(player: Player, profile: TProfile.TProfile)
	-- A write before the profile is announced is told by OnDataLoaded.
	if sent[player] == nil then return end
	broadcast(player, profile)
end)

-- The handlers need no character: the equipment is the player's own, changed from the menu whatever their body is
-- doing. A change is a look and a choice, not a grant, so the next save carries it.
ClientNetworkEquipment.Equip.On(function(player: Player, itemId: number)
	local item = PIECES[itemId]
	if item then
		change(player, function(save)
			if not EquipmentCore.IsOwned(save, item) or EquipmentCore.IsEquipped(save, item) then return false end
			save.Equipped[item.Slot] = item.Name
			return true
		end)
	end

	EquipmentService.Sync(player)
end)

ClientNetworkEquipment.Unequip.On(function(player: Player, itemId: number)
	local item = PIECES[itemId]
	if item then
		change(player, function(save)
			if not EquipmentCore.IsEquipped(save, item) then return false end
			save.Equipped[item.Slot] = ""
			return true
		end)
	end

	EquipmentService.Sync(player)
end)

ClientNetworkEquipment.Show.On(function(player: Player, itemId: number, isShown: boolean)
	local item = PIECES[itemId]
	if item then
		change(player, function(save)
			if not EquipmentCore.IsOwned(save, item) or EquipmentCore.IsShown(save, item) == isShown then
				return false
			end
			save.Hidden[item.Name] = if isShown then nil else true
			return true
		end)
	end

	EquipmentService.Sync(player)
end)

return Ignis.Register(EquipmentService)
