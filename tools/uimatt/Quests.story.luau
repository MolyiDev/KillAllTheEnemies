-- The lobby's quests screen with fixed boards, for rur to render beside the designer's Quests renders
-- (Assets/ui/UIMatt/renders/09_Quests_Daily.png and 10_Quests_Weekly.png, the same renderer and background):
--   rur-native render --headless --offline --rojo <lobby.project.json without its comments> \
--     --story tools/uimatt/Quests.story.luau --viewport 1920x1080 --scale 1 --background 40,40,60 --time 2 \
--     --controls '{"Moment": "Rest"}' --dir <out>
-- Moment: Rest (the Daily board landed: two quests done, two going, one claimed, as his), Weekly (the Weekly board),
-- Enter (the screen opening 0.2 s in), Claim (the first quest claimed 1.6 s in, once the bars have filled: the wind-up, the strike and its Gems
-- thrown at where the HUD's pill would be), ClaimAll (both done quests, one after the other), Tab (Weekly picked 0.2 s
-- in), Refused (a press on a quest still going), Close (shutting 1.6 s in, the bars still full), for
-- `rur-native sequence`. The group-owned images 403 offline, so they
-- are swapped for the local PNGs they were made from.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Icons = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Icons)
local GemPayout = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.GemPayout)
local QuestsCore = require(ReplicatedStorage.GlobalShared.Core.QuestsCore)
local Screen = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.QuestsController.Screen)

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
}
local MOMENT_AT = 0.2
local CLAIM_AT = 1.6
local WIND_UP = 0.3
local CASCADE = 0.11
-- The HUD's Gems glyph, in his 1920 x 1080.
local PILL = Vector2.new(960 - 154 + 55, 44)

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

local function idsOf(names: { string }): { number }
	local ids = {}
	for index, name in names do
		ids[index] = QuestsCore.ByName[name].Id
	end
	return ids
end

local function noop() end

return {
	vide = vide,
	controls = {
		Moment = { "Rest", "Weekly", "Enter", "Claim", "ClaimAll", "Tab", "Refused", "Close" },
	},
	story = function(props)
		local moment = props.controls.Moment()
		local isClaim = moment == "Claim" or moment == "ClaimAll"
		-- A claim, and the shut, come once the board has been dealt and its bars have filled.
		local isLate = isClaim or moment == "Close"
		local at = os.clock() + (if isLate then CLAIM_AT else MOMENT_AT)
		local daily = {
			Ids = idsOf({ "ZombieSlayer", "SpeedBump", "Survivor", "ChampionsFall", "AbilityAce" }),
			Progress = { 150, 40, 6, 0, 20 },
			Claimed = { false, false, false, false, true },
			EndsAt = os.clock() + 13 * 3600 + 24 * 60 + 58,
		}
		local weekly = {
			Ids = idsOf({ "Exterminator", "TitanTamer", "Marathon", "BossHunter", "PowerUser" }),
			Progress = { 1830, 200, 14, 1, 150 },
			Claimed = { false, false, false, false, true },
			EndsAt = os.clock() + 4 * 86400 + 13 * 3600 + 120,
		}
		local claimSlots = if moment == "ClaimAll" then { 1, 2 } else { 1 }

		local state = {
			Scale = source(1),
			Now = source(os.clock()),
			Pulse = source(os.clock()),
			IsOpen = source(true),
			ToggledAt = source(if moment == "Enter" then at else -math.huge),
			OpenedAt = source(if moment == "Enter" then at else -math.huge),
			Board = source(if moment == "Weekly" then 2 else 1),
			BoardAt = source(-math.huge),
			Boards = source({ daily, weekly }),
			SecondsLeft = source(0),
			PendingBoard = source(if isClaim then 1 else 0),
			PendingSlot = source(if moment == "ClaimAll" then 0 else 1),
			PressedAt = source(if isClaim then at else -math.huge),
			Strikes = source({ {}, {} }),
			RefusedSlot = source(if moment == "Refused" then 3 else 0),
			RefusedAt = source(if moment == "Refused" then at else -math.huge),
		}

		local gems = { {}, {} }
		local payouts = {}
		local layers = {}
		for slot = 1, QuestsCore.BOARD_SIZE do
			payouts[slot] = GemPayout.Build(function()
				return 1
			end, function(): Vector2?
				return PILL
			end)
			layers[slot] = payouts[slot].Layer
		end

		local isAnswered = false
		local isTabbed = false
		local thrown = {}
		RunService.Heartbeat:Connect(function()
			local now = os.clock()
			state.Now(now)
			state.Pulse(now)
			state.SecondsLeft(math.ceil(state.Boards()[state.Board()].EndsAt - now))
			if moment == "Close" and state.IsOpen() and now >= at then
				state.IsOpen(false)
				state.ToggledAt(now)
			end
			if moment == "Tab" and not isTabbed and now >= at then
				isTabbed = true
				state.Board(2)
				state.BoardAt(now)
			end
			if isClaim and not isAnswered and now >= at + WIND_UP then
				isAnswered = true
				local claimed = table.clone(daily.Claimed)
				local strikes = {}
				for order, slot in claimSlots do
					claimed[slot] = true
					strikes[slot] = now + CASCADE * (order - 1)
				end
				local answered = table.clone(daily)
				answered.Claimed = claimed
				state.PendingBoard(0)
				state.Boards({ answered, weekly })
				state.Strikes({ strikes, {} })
			end
			local strikes = state.Strikes()[1]
			for slot, strikeAt in strikes do
				if thrown[slot] or now < strikeAt then continue end
				thrown[slot] = true
				local glyph = gems[1][slot]
				if glyph then
					local quest = QuestsCore.ById[daily.Ids[slot]]
					payouts[slot].Burst(glyph.AbsolutePosition + glyph.AbsoluteSize / 2, quest.Gems, now, noop)
				end
			end
			for _, payout in payouts do
				payout.Step(now)
			end
		end)

		local root = create("Frame")({
			Name = "Root",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(1920, 1080),
			Screen.Build(state, {
				Close = noop,
				PickBoard = noop,
				Claim = noop,
				ClaimAll = noop,
				MarkGem = function(board: number, slot: number, glyph: GuiObject)
					gems[board][slot] = glyph
				end,
				Stir = noop,
			}),
			layers,
		})
		swapImages(root)
		return root
	end,
}
