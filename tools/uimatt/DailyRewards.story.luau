-- The lobby's daily rewards screen with a fixed state, for rur to render beside the designer's Daily Rewards render
-- (Assets/ui/UIMatt/renders/11_Daily_Rewards.png, the same renderer and background):
--   rur-native render --headless --offline --rojo <lobby.project.json without its comments> \
--     --story tools/uimatt/DailyRewards.story.luau --viewport 1920x1080 --scale 1 --background 40,40,60 --time 2 \
--     --controls '{"Moment": "Rest"}' --dir <out>
-- Moment: Rest (his state: day 1 claimed, day 2 waiting, week 1), Enter (the screen opening 0.2 s in), Claim (day 2
-- pressed 0.2 s in, answered 0.1 s later: the wind-up, the burst, the Gems flying to where the HUD's pill is, the
-- stamp, tomorrow's wink), Week (week 2 picked 0.2 s in), Prize (day 7 waiting, claimed 0.2 s in: the gun spins, then
-- the screen turns to week 2 and day 8 winks), Owned (day 7 waiting
-- with its gun owned already, so it pays Gems), Refused (day 5 pressed), Locked (week 4 pressed), for
-- `rur-native sequence`. The group-owned images 403 offline, so they are swapped for the local PNGs they were made
-- from. The guns' meshes are private, so the gun picture comes out empty here: judge it in a playtest.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Icons = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Icons)
local Showcase = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Showcase)
local EGunsIds = require(ReplicatedStorage.Types.Enums.Data.EGunsIds)
local GemPayout = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.GemPayout)
local Screen = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.DailyRewardsController.Screen)
local Shell = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.DailyController.Shell)

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
local ANSWER = 0.1
-- The HUD's Gems glyph at 1080 (LobbyController's Hud: the pill 154 left of the middle, its glyph 55 into it, 44 down
-- from the screen's top).
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

local function noop() end

return {
	vide = vide,
	controls = {
		Moment = { "Rest", "Enter", "Claim", "Week", "Prize", "Owned", "Refused", "Locked" },
		-- The art behind day 7's prize (Showcase.LOOKS); Game is the look the game draws.
		Look = { "Game", table.unpack(Showcase.LOOKS) },
	},
	story = function(props)
		local moment = props.controls.Moment()
		local look = props.controls.Look()
		Showcase.Looks.Prize = if look == "Game" then Showcase.GAME_LOOKS.Prize else look
		local at = os.clock() + MOMENT_AT
		local isPrize = moment == "Prize" or moment == "Owned"
		local day = if isPrize then 7 else 2

		local state = {
			Scale = source(1),
			Now = source(os.clock()),
			CallAt = source(-math.huge),
			IsOpen = source(true),
			ToggledAt = source(if moment == "Enter" then at else -math.huge),
			Day = source(day),
			IsClaimable = source(true),
			OwnedPrizes = source(if moment == "Owned" then { [7] = true } else {}),
			NextDayAt = source(os.clock() + 13 * 3600 + 24 * 60 + 58),
			SecondsLeft = source(13 * 3600 + 24 * 60 + 58),
			Week = source(1),
			WeekFrom = source(1),
			WeekAt = source(-math.huge),
			IsPending = source(false),
			PressedAt = source(-math.huge),
			ClaimedDay = source(0),
			ClaimedAt = source(-math.huge),
			ClaimedGems = source(0),
			ClaimedGun = source(0),
			ReadyAt = source(if moment == "Enter" then at else -math.huge),
			Refused = source(0),
			RefusedAt = source(-math.huge),
		}

		local layer = create("Frame")({
			Name = "Layer",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(1920, 1080),
		})
		local payout = GemPayout.Build(state.Scale, function()
			return PILL
		end)
		-- On the daily screen's panel, as DailyController shows it.
		local shell = {
			Scale = source(1),
			Now = state.Now,
			IsOpen = source(true),
			ToggledAt = state.ToggledAt,
			Tab = source(1),
			TabAt = source(-math.huge),
			CallAt = source(-math.huge),
			Refused = source(0),
			RefusedAt = source(-math.huge),
		}
		local morph = Shell.Morph(shell)
		local top = Shell.Top(morph)
		local children, glyphs = Screen.Build(state, {
			Claim = noop,
			PickWeek = noop,
			Refuse = noop,
		}, Shell.Lift(top, 1, state.IsOpen))
		local back, middle, front = Shell.Build(shell, { Close = noop, PickTab = noop }, {
			Day = state.Day,
			IsWaiting = function(tab: number): boolean
				return tab == 2
			end,
			IsSpinning = function(): boolean
				return false
			end,
			Shake = function(): number
				return 0
			end,
		}, morph, top, children)

		local isClaim = moment == "Claim" or isPrize
		local gems = if moment == "Prize" then 0 elseif moment == "Owned" then 750 else 75
		local isAnswered, isReleased = false, false
		if moment == "Week" then
			state.WeekFrom(1)
			state.Week(2)
			state.WeekAt(at)
		elseif moment == "Refused" then
			state.Refused(5)
			state.RefusedAt(at)
		elseif moment == "Locked" then
			state.Refused(-4)
			state.RefusedAt(at)
		elseif isClaim then
			state.IsPending(true)
			state.PressedAt(at)
		end

		RunService.Heartbeat:Connect(function()
			local now = os.clock()
			state.Now(now)
			-- The controller's call: the light across today's card every 2.6 s.
			if now - state.CallAt() >= 2.6 then state.CallAt(now) end
			if isClaim and not isAnswered and now >= at + ANSWER then
				isAnswered = true
				state.IsPending(false)
				state.IsClaimable(false)
				state.ClaimedDay(day)
				state.ClaimedGems(gems)
				state.ClaimedGun(if moment == "Prize" then EGunsIds.RpgBazooka else 0)
				state.ClaimedAt(math.max(now, at + 0.14))
			end
			if isAnswered and not isReleased and now >= state.ClaimedAt() and gems > 0 then
				isReleased = true
				local glyph = glyphs[(day - 1) % 7 + 1]
				payout.Burst(glyph.AbsolutePosition + glyph.AbsoluteSize / 2, gems, now, noop)
			end
			-- What the controller does once day 7 has settled: the screen turns to week 2.
			if isAnswered and isPrize and state.Week() == 1 and now >= state.ClaimedAt() + Screen.TURN_SECONDS then
				state.WeekFrom(1)
				state.Week(2)
				state.WeekAt(now)
			end
			payout.Step(now)
		end)

		local root = create("Frame")({
			Name = "Root",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(1920, 1080),
			create("Frame")({ Name = "Back", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, back }),
			create("Frame")({
				Name = "Pages",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ZIndex = 2,
				middle,
			}),
			create("Frame")({
				Name = "Front",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ZIndex = 3,
				front,
			}),
			create("Frame")({
				Name = "Flights",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ZIndex = 4,
				layer,
				payout.Layer,
			}),
		})
		swapImages(root)
		return root
	end,
}
