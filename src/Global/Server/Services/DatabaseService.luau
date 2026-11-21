-- The player's saved profile, in both places (GDD 10): one session-locked DocumentService document per player.
--
-- WRITES GO THROUGH Update: the cache is deep-frozen, so a write clones it, changes the clone and sets it back.
-- Anything GRANTED is recorded in the same write that grants it and followed by Save, so a retry finds it there.
--
-- NO MIGRATIONS YET, deliberately: until release a schema change is a store wipe. From the day the game ships, a
-- change to DEFAULT needs a migration.
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local DocumentService = require(ReplicatedStorage.Packages.DocumentService)
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local Signal = require(ReplicatedStorage.Packages.Signal)
local getStoreName = require(ReplicatedStorage.GlobalShared.Utils.Functions.getStoreName)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)
local TProfile = require(ReplicatedStorage.Types.TProfile)

local onDataLoaded = Ignis.RegisterLifecycle("OnDataLoaded") :: Ignis.Lifecycle<Player>

-- Receipts kept for duplicate protection. Roblox retries a receipt until it is acknowledged, for days at most, so
-- the most recent ones are all that can come back.
local MAX_RECEIPTS = 200

local DEFAULT: TProfile.TProfile = {
	Version = 1,
	Gems = 0,
	Xp = 0,
	Level = 1,
	OwnedClasses = {},
	SelectedClass = 0,
	Quests = {},
	Achievements = {},
	Records = {},
	Entitlements = {},
	Receipts = {},
	Tutorial = { Step = 0 },
	Settings = { IsAutoSkip = false, CameraMode = 0 },
}

local DatabaseService = {}

-- (player, profile) after every successful Update, for whoever mirrors part of it to the client.
DatabaseService.OnProfileChanged = Signal.new()

-- Shallow structural check: every top-level key the default has, with the same type. Strict enough to catch a
-- corrupt or foreign document, loose enough that adding a key to DEFAULT is a migration rather than a rejection.
local function check(value: unknown): (boolean, any)
	if type(value) ~= "table" then return false, "not a table" end
	for key, default in DEFAULT :: any do
		if type((value :: any)[key]) ~= type(default) then return false, `bad {key}` end
	end

	return true, value
end

local store = DocumentService.DocumentStore.new({
	dataStore = DataStoreService:GetDataStore(getStoreName()) :: any,
	check = check,
	default = DEFAULT,
	lockSessions = true,
	bindToClose = true,
})

local function getOpenDocument(player: Player): any
	local document = store:GetDocument(tostring(player.UserId))
	if not document:IsOpen() then return nil end
	return document
end

-- The frozen profile, or nil when it is not open (still loading, or the player left). Never hold it across a yield.
function DatabaseService.Get(player: Player): TProfile.TProfile?
	local document = getOpenDocument(player)
	return if document then document:GetCache() else nil
end

-- Clones the profile, hands the clone to `mutate`, and stores it. `mutate` returns false to cancel (a failed check
-- made after reading the fresh profile). Returns whether the write happened. Must not yield.
function DatabaseService.Update(player: Player, mutate: (profile: TProfile.TProfile) -> boolean?): boolean
	local document = getOpenDocument(player)
	if not document then return false end
	local draft = DatabaseService.DeepClone(document:GetCache())
	if mutate(draft) == false then return false end
	local profile = document:SetCache(draft)
	DatabaseService.OnProfileChanged:Fire(player, profile)
	return true
end

-- Writes the profile to the DataStore now, off the caller's thread. For grants (GDD 10: saved as awarded).
function DatabaseService.SaveAsync(player: Player)
	local document = getOpenDocument(player)
	if not document then return end
	task.spawn(function()
		local result = document:Save()
		if not result.success then warn(`[DatabaseService] save failed for {player.UserId}: {result.reason}`) end
	end)
end

-- Writes the profile now and waits for it. For receipts, which must be on disk before Roblox is told they were
-- granted. Returns whether it saved.
function DatabaseService.Save(player: Player): boolean
	local document = getOpenDocument(player)
	if not document then return false end
	local result = document:Save()
	if not result.success then warn(`[DatabaseService] save failed for {player.UserId}: {result.reason}`) end
	return result.success
end

-- Records a purchase receipt inside the same write as its grant; false when it was already processed.
function DatabaseService.ClaimReceipt(profile: TProfile.TProfile, receiptId: string): boolean
	for _, id in profile.Receipts do
		if id == receiptId then return false end
	end

	table.insert(profile.Receipts, receiptId)
	if #profile.Receipts > MAX_RECEIPTS then table.remove(profile.Receipts, 1) end
	return true
end

function DatabaseService.DeepClone<T>(value: T): T
	if type(value) ~= "table" then return value end
	local copy = {}
	for key, inner in value :: any do
		copy[key] = DatabaseService.DeepClone(inner)
	end

	return copy :: any
end

DatabaseService.Store = store

DatabaseService.OnPlayerConnected = function(player: Player)
	local document = store:GetDocument(tostring(player.UserId))
	-- A killed Studio session's lock would otherwise cost ~15 s of retries. Never in production: a live teleport can
	-- still be releasing the lock, and that wait is what protects its save.
	if RunService:IsStudio() then pcall(document.Steal, document) end
	if document:IsOpen() then
		player:Kick("This server is in a bad state. Please rejoin in a minute.")
		return
	end

	local function tryOpen(): { success: boolean, reason: string? }
		local ok, result: any = pcall(document.Open, document)
		if not ok then return { success = false, reason = `OpenThrew: {result}` } end
		return result
	end

	local result = tryOpen()
	if not result.success and result.reason == "SessionLockedError" then
		local stolen, err: any = pcall(document.Steal, document)
		result = if stolen then tryOpen() else { success = false, reason = `StealThrew: {err}` }
	end

	if not result.success then
		player:Kick(`Failed to load data: {result.reason}. Please rejoin.`)
		return
	end

	if not player.Parent then
		document:Close()
		return
	end

	onDataLoaded:Fire(player)
end :: TPlayerEvents.OnPlayerConnected

DatabaseService.OnPlayerDisconnected = function(player: Player)
	local document = getOpenDocument(player)
	if document then document:Close() end
end :: TPlayerEvents.OnPlayerDisconnected

return Ignis.Register(DatabaseService)
