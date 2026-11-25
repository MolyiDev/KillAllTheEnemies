--!nonstrict
-- A piece of equipment a boss dropped for this player (Equipment.Dropped, EquipmentDropsService), shown on its card
-- (Card) with the reveal's sound.
--
-- Its own ScreenGui over the HUD: the boss's death often clears the wave, and the upgrade pick hides the HUD while it
-- is up, so a drop waits for the pick to be over and then plays whole. Several wait their turn.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local vide = require(ReplicatedStorage.Packages.vide)
local NetworkMeta = require(StarterPlayer.StarterPlayerScripts.GlobalClient.NetworkMeta)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local UpgradePickController = require(script.Parent.UpgradePickController)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local Card = require(script.Card)

local ServerNetworkEquipment = NetworkMeta.Server.Equipment
local LocalPlayer = Players.LocalPlayer

local source = vide.source
local PIECES = DataCore.Equipment.ById

local REVEAL_SOUNDS = table.freeze({
	Common = "RevealEpic",
	Uncommon = "RevealEpic",
	Rare = "RevealEpic",
	Epic = "RevealEpic",
	Legendary = "RevealLegendary",
	Mythic = "RevealMythic",
})

local EquipmentDropController = {}

-- The pieces this player owns (Equipment.Sync), Id -> true, and the os.clock each piece was last won here, for the
-- boss bar's drops.
EquipmentDropController.Owned = {} :: { [number]: boolean }
EquipmentDropController.WonAt = {} :: { [number]: number }

local scale = source(1)
local now = source(os.clock())
-- The piece on show (0 for none) and when it went up.
local shownItem = source(0)
local shownAt = source(-math.huge)
-- Drops still to show, oldest first.
local queue: { number } = {}

local function updateScale()
	scale(math.max(Workspace.CurrentCamera.ViewportSize.Y / Theme.DESIGN_HEIGHT, 0.01))
end

-- Puts the next drop up, if one waits and the screen is free for it.
local function showNext()
	if #queue == 0 or UpgradePickController.IsCovering() then return end
	if os.clock() - shownAt() < Card.SECONDS then return end
	local itemId = table.remove(queue, 1)
	local item = PIECES[itemId]
	if not item then return end

	vide.batch(function()
		shownItem(itemId)
		shownAt(os.clock())
		now(os.clock())
	end)
	SoundsCore.PlayUINamed("UI.UpgradePick", REVEAL_SOUNDS[item.Rarity])
end

EquipmentDropController.OnStart = function()
	vide.mount(function()
		return Card.Build({ Scale = scale, Now = now, Item = shownItem, At = shownAt })
	end, LocalPlayer:WaitForChild("PlayerGui"))

	-- The clock runs only while a drop is up; between, the next one is looked for each frame (a table read).
	RunService.PreRender:Connect(function()
		local clock = os.clock()
		if clock - shownAt() < Card.SECONDS then
			now(clock)
		else
			showNext()
		end
	end)

	local camera = Workspace.CurrentCamera
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	updateScale()
end

ServerNetworkEquipment.Dropped.On(function(itemId: number)
	if not PIECES[itemId] then return end
	EquipmentDropController.WonAt[itemId] = os.clock()
	table.insert(queue, itemId)
end)

ServerNetworkEquipment.Sync.On(function(ownedIds: { number })
	local owned = EquipmentDropController.Owned
	table.clear(owned)
	for _, itemId in ownedIds do
		owned[itemId] = true
	end
end)

return Ignis.Register(EquipmentDropController)
