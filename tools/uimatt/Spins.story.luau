-- The lobby's daily spins screen with a fixed state, for rur to render beside the designer's Daily Spins render
-- (Assets/ui/UIMatt/renders/12_Daily_Spins.png, the same renderer and background):
--   rur-native render --headless --offline --rojo <lobby.project.json without its comments> \
--     --story tools/uimatt/Spins.story.luau --viewport 1920x1080 --scale 1 --background 40,40,60 --time 2 \
--     --controls '{"Moment": "Rest", "Count": "1"}' --dir <out>
-- Count is how many reels SPIN turns (1, 3 or 5). Moment: Rest (open and settled, 5 free spins), Enter (the screen
-- opening 0.2 s in), Gems / Xp / Jackpot (SPIN pressed 0.2 s in, the server answering 0.1 s later with Gems, XP or the
-- jackpot on the first reel and a spread on the rest; the reels run about five seconds, land one after another down
-- the page and each prize flies to where the HUD's pill and bar are at 1080), Buy (no spins left, SPIN sells Count),
-- None (no spins left and none for sale), Menu (the count menu open), Grow (one reel at rest, Count picked 0.2 s in:
-- the page takes its new shape), Close (shutting 0.2 s in), Beckon (the page brought up 0.2 s in for a spin waiting,
-- SPIN wobbling once 0.5 s later), for `rur-native sequence`. The group-owned images 403 offline, so they are swapped
-- for the local PNGs they were made from.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Icons = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Icons)
local Spins = StarterPlayer.StarterPlayerScripts.Client.Controllers.SpinsController
local Payout = require(Spins.Payout)
local Reel = require(Spins.Reel)
local ReelMotion = require(Spins.ReelMotion)
local Screen = require(Spins.Screen)
local Shape = require(Spins.Shape)
local SpinsCore = require(ReplicatedStorage.Shared.Core.SpinsCore)
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
}
local MOMENT_AT = 0.2
local ANSWER_AFTER = 0.1
-- The prizes each spinning moment lands on, a reel each (SpinsCore.PRIZES), and where each stops inside its card.
local PRIZES = {
	Gems = { 3, 2, 6, 5, 3 },
	Xp = { 4, 7, 2, 4, 6 },
	Jackpot = { 1, 6, 3, 7, 2 },
}
local JITTERS = { 0.7, -0.4, 0.2, -0.8, 0.5 }
-- At 1080 the HUD's scale is 1: the pill's glyph and the level bar where LobbyController's Hud draws them.
local PILL = Vector2.new(960 - 154 + 55, 44)
local BAR = Vector2.new(38 + 233, 47 + 48 + 6)

-- A picture whose name changes (a reel's card) sets its Image again, so each one is swapped as it changes too.
local function swapImages(root: Instance)
	local function swap(instance: Instance)
		if not instance:IsA("ImageLabel") and not instance:IsA("ImageButton") then return end
		local image = instance :: ImageLabel
		local function apply()
			local path = SWAPS[image.Image]
			if path then image.Image = path end
		end
		apply()
		image:GetPropertyChangedSignal("Image"):Connect(apply)
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
		Moment = { "Rest", "Enter", "Gems", "Xp", "Jackpot", "Buy", "None", "Menu", "Grow", "Close", "Beckon" },
		Count = { "1", "3", "5" },
	},
	story = function(props)
		local moment = props.controls.Moment()
		local count = tonumber(props.controls.Count()) :: number
		local at = os.clock() + MOMENT_AT
		local isEmpty = moment == "Buy" or moment == "None"
		local prizes = PRIZES[moment]
		local shownReels = if moment == "Grow" then 1 else count
		local isBuy = moment == "Buy"

		local state = {
			Scale = source(1),
			Now = source(os.clock()),
			IsOpen = source(moment ~= "Close"),
			ToggledAt = source(if moment == "Enter" or moment == "Close" or moment == "Beckon" then at else -math.huge),
			FreeLeft = source(if isEmpty then 0 else 5),
			FreePerDay = source(5),
			Bought = source(0),
			SecondsLeft = source(13 * 3600 + 24 * 60 + 58),
			CanBuy = source(moment ~= "None"),
			Mode = source(if isBuy then "Buy" elseif moment == "None" then "None" else "Spin"),
			Count = source(shownReels),
			IsMenuOpen = source(moment == "Menu"),
			MenuAt = source(if moment == "Menu" then -1000 else -math.huge),
			Reels = source(shownReels),
			ReelsAt = source(-math.huge),
			Batch = source(shownReels),
			Price = source(if isBuy then SpinsCore.PRICES[shownReels] else 0),
			Rests = source({ 4, 2, 6, 3, 5 }),
			Spins = source({}),
			PillAt = source(PILL),
			BarAt = source(BAR),
			BarLength = source(226),
			RefusedAt = source(-math.huge),
			BeckonAt = source(if moment == "Beckon" then at + 0.5 else -math.huge),
		}
		-- The menu's rows show their prices when SPIN sells.
		if isBuy then state.Mode("Buy") end

		-- What the controller does: the count picked, the press, the answer, and the end.
		local isPressed, isAnswered, isDone = false, false, false
		RunService.Heartbeat:Connect(function()
			local now = os.clock()
			state.Now(now)
			if moment == "Grow" and not isDone and now >= at then
				isDone = true
				state.Count(count)
				state.Batch(count)
				state.ReelsAt(now)
				state.Reels(count)
			end
			if not prizes or isDone then return end
			if not isPressed and now >= at then
				isPressed = true
				local spins = {}
				for index = 1, count do
					spins[index] = { StartAt = at + (index - 1) * 0.07, From = state.Rests()[index] }
				end
				state.Spins(spins)
				state.Mode("Busy")
				state.FreeLeft(5 - count)
			end
			if isPressed and not isAnswered and now >= at + ANSWER_AFTER then
				isAnswered = true
				local planned = {}
				local last = -math.huge
				for index, spin in state.Spins() do
					local gap = if index > 1 and index == count then 0.54 else 0.32
					local plan = ReelMotion.PlanAfter(spin, prizes[index], now, JITTERS[index], last + gap)
					last = plan.LandAt
					plan.PayAt = plan.LandAt + 0.35
					plan.Pieces = Payout.Count(SpinsCore.PRIZES[prizes[index]])
					plan.BarFrom = 0.3
					plan.BarTo = 0.8
					planned[index] = plan
				end
				state.Spins(planned)
			end
			local spins = state.Spins()
			local final = spins[#spins]
			if final and final.PayAt and now >= final.PayAt + Payout.SECONDS + Reel.LAND_SECONDS then
				isDone = true
				local rests = table.clone(state.Rests())
				for index, spin in spins do
					rests[index] = spin.Slot
				end
				state.Rests(rests)
				state.Spins({})
				state.Mode("Spin")
			end
		end)

		-- On the daily screen's panel, as DailyController shows it.
		local shell = {
			Scale = source(1),
			Now = state.Now,
			IsOpen = state.IsOpen,
			ToggledAt = state.ToggledAt,
			Tab = source(2),
			TabAt = source(-math.huge),
			CallAt = source(-math.huge),
			Refused = source(0),
			RefusedAt = source(-math.huge),
		}
		local morph = Shell.Morph(shell)
		local shape = Shape.Build(state)
		local panel = vide.derive(function(): Vector2
			local current = shape()
			return Vector2.new(current.Top, current.Height)
		end)
		local top = Shell.Top(morph, panel)
		local page, flights, shake = Screen.Build(
			state,
			{ Spin = noop, SetMenu = noop, PickCount = noop },
			Shell.Lift(top, 2, state.IsOpen),
			shape
		)
		local back, middle, front = Shell.Build(shell, { Close = noop, PickTab = noop }, {
			Day = function(): number
				return 2
			end,
			FreePerDay = state.FreePerDay,
			IsWaiting = function(tab: number): boolean
				return tab == 1
			end,
			IsSpinning = function(): boolean
				return state.Mode() == "Busy"
			end,
			Shake = shake,
			SpinShape = panel,
		}, morph, top, page)
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
			layer("Flights", 4, flights),
		})
		swapImages(root)
		return root
	end,
}
