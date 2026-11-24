-- The lobby's daily screen (DailyController: the shell and its DAILY and SPIN pages) with a fixed state, for rur:
--   rur-native render --headless --offline --rojo <lobby.project.json without its comments> \
--     --story tools/uimatt/Daily.story.luau --viewport 1920x1080 --scale 1 --background 40,40,60 --time 2 \
--     --controls '{"Moment": "Daily"}' --dir <out>
-- Moment: Daily (open on DAILY and settled: day 2 waiting, two free spins waiting, so the SPIN tab calls), Spin (open
-- on SPIN), ToSpin / ToDaily (the other tab picked 0.4 s in: the panel takes the new page's shape, the slab glides,
-- the words change places, a light runs down the rule, the pages swap), Enter (the screen opening 0.2 s in on DAILY),
-- Close (shutting 0.4 s in), Refused (on SPIN with the reel turning, DAILY pressed 0.4 s in), for `rur-native
-- sequence`. It does what DailyController does on those moments. The group-owned images 403 offline, so they are
-- swapped for the local PNGs they were made from.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Icons = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Icons)
local GemPayout = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.GemPayout)
local Controllers = StarterPlayer.StarterPlayerScripts.Client.Controllers
local Shell = require(Controllers.DailyController.Shell)
local RewardsScreen = require(Controllers.DailyRewardsController.Screen)
local SpinsScreen = require(Controllers.SpinsController.Screen)

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
local MOMENT_AT = 0.4
-- DailyController's: the page picked comes in this long after the other starts to leave.
local SWITCH_DELAY = 0.15
local CLOCK = 13 * 3600 + 24 * 60 + 58
local PILL = Vector2.new(960 - 154 + 55, 44)
local BAR = Vector2.new(38 + 233, 47 + 48 + 6)

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
		Moment = { "Daily", "Spin", "ToSpin", "ToDaily", "Enter", "Close", "Refused" },
	},
	story = function(props)
		local moment = props.controls.Moment()
		local at = os.clock() + MOMENT_AT
		local now = os.clock()
		local startTab = if moment == "Spin" or moment == "ToDaily" or moment == "Refused" then 2 else 1
		local enteredAt = if moment == "Enter" then now + 0.2 else -math.huge

		local shell = {
			Scale = source(1),
			Now = source(now),
			IsOpen = source(true),
			ToggledAt = source(enteredAt),
			Tab = source(startTab),
			TabAt = source(-math.huge),
			CallAt = source(-math.huge),
			Refused = source(0),
			RefusedAt = source(-math.huge),
		}
		local rewards = {
			Scale = source(1),
			Now = source(now),
			CallAt = source(-math.huge),
			IsOpen = source(startTab == 1),
			ToggledAt = source(if startTab == 1 then enteredAt else -math.huge),
			Day = source(2),
			IsClaimable = source(true),
			OwnedPrizes = source({}),
			NextDayAt = source(now + CLOCK),
			SecondsLeft = source(CLOCK),
			Week = source(1),
			WeekFrom = source(1),
			WeekAt = source(-math.huge),
			IsPending = source(false),
			PressedAt = source(-math.huge),
			ClaimedDay = source(0),
			ClaimedAt = source(-math.huge),
			ClaimedGems = source(0),
			ClaimedGun = source(0),
			ReadyAt = source(enteredAt),
			Refused = source(0),
			RefusedAt = source(-math.huge),
		}
		local spins = {
			Scale = source(1),
			Now = source(now),
			IsOpen = source(startTab == 2),
			ToggledAt = source(if startTab == 2 then enteredAt else -math.huge),
			FreeLeft = source(2),
			FreePerDay = source(2),
			Bought = source(0),
			SecondsLeft = source(CLOCK),
			CanBuy = source(true),
			Mode = source(if moment == "Refused" then "Busy" else "Spin"),
			Rest = source(4),
			Spin = source(if moment == "Refused" then { StartAt = now, From = 4 } else nil),
			PillAt = source(PILL),
			BarAt = source(BAR),
			BarLength = source(226),
			RefusedAt = source(-math.huge),
			BeckonAt = source(-math.huge),
		}

		local morph = Shell.Morph(shell)
		local top = Shell.Top(morph)
		local rewardsPage = RewardsScreen.Build(
			rewards,
			{ Claim = noop, PickWeek = noop, Refuse = noop },
			Shell.Lift(top, 1, rewards.IsOpen)
		)
		local spinsPage, spinsFlights, shake =
			SpinsScreen.Build(spins, { Spin = noop }, Shell.Lift(top, 2, spins.IsOpen))
		local payout = GemPayout.Build(rewards.Scale, function()
			return PILL
		end)
		local page = function(name: string, children: { any }): Frame
			return create("Frame")({
				Name = name,
				Size = UDim2.fromOffset(1920, 1080),
				BackgroundTransparency = 1,
				children,
			})
		end
		local back, middle, front = Shell.Build(shell, { Close = noop, PickTab = noop }, {
			Day = rewards.Day,
			FreePerDay = function(): number
				return 2
			end,
			IsWaiting = function(tab: number): boolean
				if tab == 1 then return rewards.IsClaimable() end
				return spins.FreeLeft() > 0
			end,
			IsSpinning = function(): boolean
				return spins.Mode() == "Busy"
			end,
			Shake = shake,
		}, morph, top, { page("Rewards", rewardsPage), page("Spins", spinsPage) })

		-- What DailyController does on the moment.
		local isDone = false
		local nextCall = now + 0.6
		RunService.Heartbeat:Connect(function()
			local clock = os.clock()
			shell.Now(clock)
			rewards.Now(clock)
			spins.Now(clock)
			if clock >= nextCall then
				nextCall = clock + 2.6
				shell.CallAt(clock)
			end
			if isDone or clock < at then return end
			isDone = true
			if moment == "ToSpin" or moment == "ToDaily" then
				local tab = if moment == "ToSpin" then 2 else 1
				shell.Tab(tab)
				shell.TabAt(clock)
				local leaving = if tab == 2 then rewards else spins
				local coming = if tab == 2 then spins else rewards
				leaving.IsOpen(false)
				leaving.ToggledAt(clock)
				coming.IsOpen(true)
				coming.ToggledAt(clock + SWITCH_DELAY)
				if tab == 1 then rewards.ReadyAt(clock + SWITCH_DELAY) end
			elseif moment == "Close" then
				shell.IsOpen(false)
				shell.ToggledAt(clock)
				rewards.IsOpen(false)
				rewards.ToggledAt(clock)
			elseif moment == "Refused" then
				shell.Refused(1)
				shell.RefusedAt(clock)
			end
		end)

		-- Stacked as DailyController stacks them.
		local function layer(name: string, zIndex: number, children: { any }): Frame
			return create("Frame")({
				Name = name,
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ZIndex = zIndex,
				children,
			})
		end
		local root = create("Frame")({
			Name = "Root",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(1920, 1080),
			layer("Back", 1, back),
			layer("Pages", 2, middle),
			layer("Front", 3, front),
			layer("Flights", 4, { spinsFlights, payout.Layer }),
		})
		swapImages(root)
		return root
	end,
}
