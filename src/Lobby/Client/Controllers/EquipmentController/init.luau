-- The equipment page (UIMatt.md, Equipment), the classes screen's EQUIPMENT tab: every piece in a grid filtered by slot,
-- the player's avatar on a stage wearing what they show, the three slots worn under it, and the picked piece's
-- picture, numbers and where it comes from beside them. Putting a piece on or off, and on or off the avatar, is
-- EquipmentService's to decide: this asks and shows. The classes screen (LobbyController) holds the page and says when
-- it is on show (SetShown); the page builds itself into that screen (BuildPage).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local vide = require(ReplicatedStorage.Packages.vide)
local NetworkMeta = require(StarterPlayer.StarterPlayerScripts.GlobalClient.NetworkMeta)
local copyCharacter = require(StarterPlayer.StarterPlayerScripts.GlobalClient.Utils.copyCharacter)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local EquipmentCore = require(ReplicatedStorage.GlobalShared.Core.EquipmentCore)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local Parts = require(script.Parts)
local Screen = require(script.Screen)
local Types = require(script.Types)

local ServerNetworkEquipment = NetworkMeta.Server.Equipment
local ClientNetworkEquipment = NetworkMeta.Client.Equipment
local LocalPlayer = Players.LocalPlayer
local source = vide.source

local PIECES = DataCore.Equipment.ById
-- The folder EquipmentWearController keeps a character's pieces in: the stage's copy is dressed by the stage instead.
local WORN_FOLDER = "Equipment"
-- The sound a piece put on makes, by its rarity: the upgrade pick's, as the screen's own cue on the UI bus.
local PICK_SOUNDS = table.freeze({
	Common = "PickCommon",
	Uncommon = "PickUncommon",
	Rare = "PickRare",
	Epic = "PickEpic",
	Legendary = "PickLegendary",
	Mythic = "PickMythic",
})

local EquipmentController = {}

-- How long the classes page stays drawn under this one as it comes up: its stage takes that long to go.
EquipmentController.FADE_SECONDS = Parts.Timing.COVER

local state: Types.TEquipmentState = {
	Now = source(os.clock()),
	IsShown = source(false),
	ShownAt = source(-math.huge),
	IsByScreen = source(true),
	Filter = source("All" :: Types.TFilter),
	FilterAt = source(-math.huge),
	Selected = source(EquipmentCore.All[1].Id),
	SelectedAt = source(-math.huge),
	Owned = source({} :: { [number]: boolean }),
	Equipped = source({} :: { [string]: number }),
	Hidden = source({} :: { [number]: boolean }),
	Pending = source(nil :: Types.TRequest?),
	ChangedItem = source(0),
	Change = source("Equip" :: Types.TRequest),
	ChangedAt = source(-math.huge),
	RefusedAt = source(-math.huge),
	IsHelpOpen = source(false),
	HelpAt = source(-math.huge),
	Avatar = source(nil :: Model?),
}

-- os.clock until which Now keeps ticking.
local motionUntil = -math.huge
-- The piece the pending press was made on: the hand may pick another before the answer comes.
local pendingItem = 0

local function stir(seconds: number)
	motionUntil = math.max(motionUntil, os.clock() + seconds)
end

-- Stamps a gesture's start and keeps Now ticking for it.
local function stamp(at: Types.Source<number>)
	at(os.clock())
	stir(Parts.Timing.SETTLED)
end

-- A fresh copy of the avatar for the stage, as it looks now, without the pieces it wears: the stage puts on what the
-- page says it wears, so a change shows on it the moment it is answered.
local function takeAvatar()
	local character = LocalPlayer.Character
	local copy = if character then copyCharacter(character) else nil
	if not copy then return end
	local worn = copy:FindFirstChild(WORN_FOLDER)
	if worn then worn:Destroy() end

	local old = state.Avatar()
	state.Avatar(copy)
	if old then old:Destroy() end
end

-- Shows or leaves the page. `isByScreen` is the classes screen opening or shutting; false, a tab was picked.
function EquipmentController.SetShown(isShown: boolean, isByScreen: boolean)
	if state.IsShown() == isShown then return end
	if isShown then takeAvatar() end
	vide.batch(function()
		state.IsShown(isShown)
		state.IsByScreen(isByScreen)
		stamp(state.ShownAt)
	end)
end

local function inFilter(filter: Types.TFilter, itemId: number): boolean
	local item = PIECES[itemId]
	return item ~= nil and (filter == "All" or item.Slot == filter)
end

local function selectItem(itemId: number)
	if state.Selected() == itemId then return end
	vide.batch(function()
		state.Selected(itemId)
		stamp(state.SelectedAt)
	end)
end

local function refuse()
	stamp(state.RefusedAt)
	SoundsCore.PlayUINamed("UI.UpgradePick", "Denied")
end

local function setHelpOpen(isOpen: boolean)
	if state.IsHelpOpen() == isOpen then return end
	vide.batch(function()
		state.IsHelpOpen(isOpen)
		stamp(state.HelpAt)
	end)
end

local function ask(request: Types.TRequest, itemId: number)
	state.Pending(request)
	pendingItem = itemId
end

local actions: Types.TEquipmentActions = {
	Filter = function(filter: Types.TFilter)
		if state.Filter() == filter then return end
		vide.batch(function()
			state.Filter(filter)
			stamp(state.FilterAt)
			if inFilter(filter, state.Selected()) then return end
			-- The slot's piece worn, or its first.
			local first = (EquipmentCore.BySlot[filter] or EquipmentCore.All)[1]
			local worn = state.Equipped()[filter]
			if worn or first then selectItem(worn or first.Id) end
		end)
	end,
	Select = selectItem,
	-- Each press is checked here first only to answer at once: the server checks it again.
	Press = function()
		local item = PIECES[state.Selected()]
		if state.Pending() or not item then return end
		if not state.Owned()[item.Id] then
			refuse()
			setHelpOpen(true)
			return
		end

		if state.Equipped()[item.Slot] == item.Id then
			ask("Unequip", item.Id)
			ClientNetworkEquipment.Unequip.Fire(item.Id)
		else
			ask("Equip", item.Id)
			ClientNetworkEquipment.Equip.Fire(item.Id)
		end
	end,
	ToggleShown = function()
		local item = PIECES[state.Selected()]
		if state.Pending() or not item then return end
		if not state.Owned()[item.Id] then
			refuse()
			return
		end
		ask("Show", item.Id)
		ClientNetworkEquipment.Show.Fire(item.Id, state.Hidden()[item.Id] == true)
	end,
	ToggleHelp = function()
		setHelpOpen(not state.IsHelpOpen())
	end,
	Stir = stir,
}

-- The answer to whatever was pending, as a gesture on the piece it was about.
local function answer(owned: { [number]: boolean }, equipped: { [string]: number }, hidden: { [number]: boolean })
	local pending = state.Pending()
	state.Pending(nil)
	local item = PIECES[pendingItem]
	local wasEquipped = item ~= nil and state.Equipped()[item.Slot] == item.Id
	local wasHidden = item ~= nil and state.Hidden()[item.Id] == true
	state.Owned(owned)
	state.Equipped(equipped)
	state.Hidden(hidden)
	if not pending or not item then return end

	local isEquipped = equipped[item.Slot] == item.Id
	local isHidden = hidden[item.Id] == true
	local isDone = (pending == "Equip" and isEquipped and not wasEquipped)
		or (pending == "Unequip" and wasEquipped and not isEquipped)
		or (pending == "Show" and isHidden ~= wasHidden)
	if not isDone then
		refuse()
		return
	end

	state.ChangedItem(item.Id)
	state.Change(pending)
	stamp(state.ChangedAt)
	if pending == "Equip" then
		SoundsCore.PlayUINamed("UI.UpgradePick", PICK_SOUNDS[item.Rarity])
	else
		SoundsCore.PlayClick()
	end
end

EquipmentController.OnStart = function()
	-- Now is written only while something moves, so a page at rest, up or not, redraws nothing.
	RunService.PreRender:Connect(function()
		local now = os.clock()
		if now < motionUntil then state.Now(now) end
	end)
end

-- Builds the page into the classes screen (its root is his 1920 x 1080, scaled), drawn only while on show or leaving.
function EquipmentController.BuildPage(): { Instance }
	return Screen.Build(state, actions)
end

ServerNetworkEquipment.Sync.On(function(ownedIds: { number }, equippedIds: { number }, hiddenIds: { number })
	local owned, hidden = {}, {}
	for _, itemId in ownedIds do
		owned[itemId] = true
	end
	for _, itemId in hiddenIds do
		hidden[itemId] = true
	end
	local equipped = {}
	for index, slot in EquipmentCore.SLOTS do
		local itemId = equippedIds[index]
		if itemId and itemId ~= 0 then equipped[slot] = itemId end
	end

	vide.batch(function()
		answer(owned, equipped, hidden)
	end)
end)

return Ignis.Register(EquipmentController)
