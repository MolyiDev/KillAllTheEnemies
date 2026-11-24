-- The lobby's shop with a fixed state, for rur to render beside the designer's Robux Shop render
-- (Assets/ui/UIMatt/renders/03_Robux_Shop.png, the same renderer and background):
--   rur-native render --headless --offline --rojo <lobby.project.json without its comments> \
--     --story tools/uimatt/Shop.story.luau --viewport 1920x1080 --scale 1 --background 40,40,60 --time 2 \
--     --controls '{"Moment": "Rest"}' --dir <out>
-- Moment: Rest (the top of the scroll), Enter (opening 0.2 s in), Bundles / Gems / Passes (opened on that section, as
-- the game opens it), Granted (the class bundle bought 0.4 s in: the cheer and OWNED), Owned (it and the featured gun
-- held),
-- Gift (the gift list up over the shop), Restricted (Passes with paid random items restricted), Leave (shutting from
-- 0.2 s: render at --time 0.3 for 0.1 s into it), Mega (the biggest Gem pack), Bottom (the end of the scroll). The group-owned images
-- 403 offline, so they are swapped for the local PNGs they were made from. The gun models live in the places, so their
-- pictures come out empty here: judge them in a playtest.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Icons = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Icons)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local ShopCore = require(ReplicatedStorage.GlobalShared.Core.ShopCore)
local Screen = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.ShopController.Screen)

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
local MOMENT_AT = 0.2
-- The section each moment opens on, and a scroll past it for the moments about the class bundle.
local SECTIONS = { Bundles = "Bundles", Gems = "Gems", Passes = "Passes", Restricted = "Passes", Mega = "Gems" }
local SCROLLS = { Granted = 440, Owned = 440, Mega = 1900, Bottom = 99999 }

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

local function noop() end

return {
	vide = vide,
	controls = {
		Moment = {
			"Rest",
			"Enter",
			"Bundles",
			"Gems",
			"Passes",
			"Granted",
			"Owned",
			"Gift",
			"Restricted",
			"Leave",
			"Mega",
			"Bottom",
		},
	},
	story = function(props)
		local moment = props.controls.Moment()
		local at = os.clock() + MOMENT_AT
		local owned = {}
		if moment == "Owned" then
			owned = { Vip = true, DoubleGems = true, StarterPack = true, SurvivorBundle = true }
		end

		local state = {
			Scale = source(1),
			Now = source(os.clock()),
			IsOpen = source(moment ~= "Leave"),
			ToggledAt = source(if moment == "Enter" or moment == "Leave" then at else -math.huge),
			Owned = source(owned),
			IsRestricted = source(moment == "Restricted"),
			HasFeatured = source(moment == "Owned"),
			FeaturedEndsAt = source(os.time() + ShopCore.FeaturedSecondsLeft(os.time())),
			Clock = source(os.time()),
			Section = source(SECTIONS[moment] or "Featured"),
			SectionAt = source(-math.huge),
			PressedAt = source({}),
			GrantedAt = source({}),
			RefusedAt = source({}),
			GiftOffer = source(if moment == "Gift" then "GemsLarge" else nil),
			GiftToggledAt = source(if moment == "Gift" then at else -math.huge),
			GiftPlayers = source({
				{ UserId = 1, Name = "Roblox", DisplayName = "Roblox" },
				{ UserId = 156, Name = "builderman", DisplayName = "Builderman" },
				{ UserId = 261, Name = "Shedletsky", DisplayName = "Shedletsky" },
				-- Enough rows to overflow the list, for its scrollbar.
				{ UserId = 2, Name = "John", DisplayName = "John" },
				{ UserId = 3, Name = "Jane", DisplayName = "Jane" },
				{ UserId = 4, Name = "Bob", DisplayName = "Bob" },
				{ UserId = 5, Name = "Alice", DisplayName = "Alice" },
			}),
			Message = source(if moment == "Granted" then "GIFT SENT TO BUILDERMAN!" else ""),
			MessageColor = source(Theme.Palette.Green),
			MessageAt = source(if moment == "Granted" then at else -math.huge),
		}

		local grantAt = if moment == "Granted" then os.clock() + 0.4 else math.huge
		RunService.Heartbeat:Connect(function()
			state.Now(os.clock())
			if os.clock() < grantAt then return end
			grantAt = math.huge
			state.Owned({ SurvivorBundle = true })
			state.GrantedAt({ SurvivorBundle = os.clock() })
		end)

		local root = create("Frame")({
			Name = "Root",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(1920, 1080),
			Screen.Build(state, {
				Close = noop,
				PickSection = noop,
				Buy = noop,
				OpenGift = noop,
				CloseGift = noop,
				SendGift = noop,
				MarkScroll = function(frame: ScrollingFrame)
					local y = SCROLLS[moment]
					if y then frame.CanvasPosition = Vector2.new(0, y) end
				end,
				Stir = noop,
			}),
		})
		swapImages(root)
		return root
	end,
}
