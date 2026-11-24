-- The shop's Robux receipt (ShopController/Receipt) on its own, over a stand-in for the blurred lobby. Offer picks
-- what was bought (a bought offer, a gift received, a gift sent, a bundle with a gun already owned); Moment: Play
-- (the whole reveal from MOMENT_AT), Hurry (a press 0.8 s in lands it all), Done (it is over, waiting for CONTINUE),
-- Leave (CONTINUE pressed once it is over). Every change plays it again. The Gems' flight and the sounds are the
-- controller's, so neither is here.
--
-- Offline with rur, where the group-owned images 403, Offline swaps them for the local PNGs they were made from:
--   rur-native render --headless --offline --rojo <lobby.project.json without its comments> \
--     --story src/Lobby/Client/Stories/Receipt.story.luau --viewport 1920x1080 --scale 1 --background 40,40,60 \
--     --time 5 --controls '{"Offer": "Survivor bundle", "Moment": "Play", "Offline": true}' --dir <out>
-- and `rur-native sequence` the same way for the motion. The gun models live in the places, so their pictures come out
-- empty offline: judge them in a playtest.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local UILabs = require(ReplicatedStorage.Packages.UILabs)
local Icons = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Icons)
local ShopCore = require(ReplicatedStorage.GlobalShared.Core.ShopCore)
local Receipt = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.ShopController.Receipt)
local Receipts = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.ShopController.Receipts)

local source = vide.source
local create = vide.create

local ROOT = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/hud/"
local SWAPS = {
	[Icons.Pictures.Gem.Image] = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/rendered/Pictures1.png",
	[Icons.Pictures.Potion.Image] = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/rendered/Pictures2.png",
	[Icons.Pictures.Pointer.Image] = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/rendered/Pictures3.png",
	[Icons.Pictures.UpArrow.Image] = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/rendered/Pictures4.png",
	[Icons.Pictures.SurvivorVest.Image] = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/rendered/Pictures5.png",
	[Icons.IMAGE] = ROOT .. "Icons.png",
	[Icons.PANEL_TEXTURE] = ROOT .. "PanelTexture.png",
	[Icons.SHOWCASE] = ROOT .. "Showcase.png",
	[Icons.SHOWCASE_FLOOR] = ROOT .. "ShowcaseFloor.png",
}
local DESIGN = Vector2.new(1920, 1080)
local MOMENT_AT = 0.3
local HURRY_AFTER = 0.8
-- The lobby behind it, blurred: a few soft blocks of its colours.
local BACKGROUND = Color3.fromRGB(40, 40, 60)

-- Each pick: the offer, and who it was from or for, and the Gems paid in place of what was held.
local OFFERS = {
	{ Label = "Gem pack", Offer = "GemsHuge", Giver = "", Refund = 0 },
	{ Label = "Mega Gem pack", Offer = "GemsMega", Giver = "", Refund = 0 },
	{ Label = "Survivor bundle", Offer = "SurvivorBundle", Giver = "", Refund = 0 },
	{ Label = "Arsenal bundle", Offer = "ArsenalBundle", Giver = "", Refund = 0 },
	{ Label = "Starter pack, gun owned", Offer = "StarterPack", Giver = "", Refund = 1500 },
	{ Label = "Featured gun", Offer = "FeaturedLegendary", Giver = "", Refund = 0 },
	{ Label = "VIP", Offer = "Vip", Giver = "", Refund = 0 },
	{ Label = "Double Gems, gift received", Offer = "DoubleGems", Giver = "Builderman", Refund = 0 },
	{ Label = "2x Luck", Offer = "Luck", Giver = "", Refund = 0 },
	{ Label = "Gift sent", Offer = "GemsLarge", Giver = "", Receiver = "Builderman", Refund = 0 },
}
local OFFER_LABELS = {}
for index, pick in OFFERS do
	OFFER_LABELS[index] = pick.Label
end
local MOMENTS = { "Play", "Hurry", "Done", "Leave" }

local function swapImages(root: Instance)
	local function swap(instance: Instance)
		if instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
			local path = SWAPS[instance.Image]
			if path then instance.Image = path end
		end
	end

	for _, instance in root:GetDescendants() do
		swap(instance)
	end
	root.DescendantAdded:Connect(swap)
end

local function pickOf(label: string)
	for _, pick in OFFERS do
		if pick.Label == label then return pick end
	end

	return OFFERS[1]
end

local function bench(target: Frame, label: string, moment: string, isOffline: boolean): Frame
	local pick = pickOf(label)
	local receipt = Receipts.Build(ShopCore.ByName[pick.Offer], {
		Giver = pick.Giver,
		Receiver = pick.Receiver,
		Refund = pick.Refund,
		IsRestricted = false,
	}, ShopCore.FeaturedGun(os.time()))

	local start = os.clock() + MOMENT_AT
	local plan = Receipts.Plan(receipt, start)
	-- Done and Leave start where the reveal is already over.
	if moment == "Done" or moment == "Leave" then plan = Receipts.Plan(receipt, start - plan.ButtonAt + start - 0.5) end
	local state = {
		ReceiptNow = source(os.clock()),
		Receipt = source(receipt),
		ReceiptPlan = source(plan),
		ReceiptLeftAt = source(if moment == "Leave" then start + 0.4 else math.huge),
		ReceiptCalledAt = source(-math.huge),
	}

	local hurryAt = if moment == "Hurry" then start + HURRY_AFTER else math.huge
	local connection = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		state.ReceiptNow(now)
		if now < hurryAt then return end
		hurryAt = math.huge
		state.ReceiptPlan(Receipts.Hurry(state.ReceiptPlan(), now))
	end)
	vide.cleanup(function()
		connection:Disconnect()
	end)

	local scale = math.min(target.AbsoluteSize.X / DESIGN.X, target.AbsoluteSize.Y / DESIGN.Y)
	local root = create("Frame")({
		Name = "Root",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(DESIGN.X, DESIGN.Y),
		BackgroundTransparency = 1,
		create("UIScale")({ Scale = if scale > 0 then scale else 1 }),
		Receipt.Build(state :: any, receipt, {
			Press = function() end,
			Continue = function() end,
		}),
	})
	if isOffline then swapImages(root) end

	return root
end

local CONTROLS = {
	Offer = UILabs.Ordered(UILabs.Choose(OFFER_LABELS, 3), 1),
	Moment = UILabs.Ordered(UILabs.Choose(MOMENTS, 1), 2),
	Offline = UILabs.Ordered(UILabs.Boolean(false), 3),
}

return {
	summary = "The shop's Robux receipt: the card drops, its lines print, AWESOME! comes in.",
	controls = CONTROLS,

	render = function(props)
		local values: { [string]: any } = table.clone(props.controls)
		local unmount: (() -> ())? = nil

		local frame = Instance.new("Frame")
		frame.Name = "ReceiptBench"
		frame.BackgroundColor3 = BACKGROUND
		frame.ClipsDescendants = true
		frame.Size = UDim2.fromScale(1, 1)
		frame.Parent = props.target

		local function build()
			if unmount then unmount() end
			-- The mount frees the state, not the instances.
			frame:ClearAllChildren()
			unmount = vide.mount(function()
				return bench(frame, values.Offer, values.Moment, values.Offline)
			end, frame)
		end
		build()

		local unsubscribe = props.subscribe(function(nextValues)
			values = table.clone(nextValues)
			build()
		end)

		return function()
			unsubscribe()
			if unmount then unmount() end
			frame:Destroy()
		end
	end,
}
