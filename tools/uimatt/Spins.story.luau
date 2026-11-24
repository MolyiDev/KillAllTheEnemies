-- The lobby's daily spins screen with a fixed state, for rur to render beside the designer's Daily Spins render
-- (Assets/ui/UIMatt/renders/12_Daily_Spins.png, the same renderer and background):
--   rur-native render --headless --offline --rojo <lobby.project.json without its comments> \
--     --story tools/uimatt/Spins.story.luau --viewport 1920x1080 --scale 1 --background 40,40,60 --time 2 \
--     --controls '{"Moment": "Rest"}' --dir <out>
-- Moment: Rest (open and settled, 2 free spins), Enter (the screen opening 0.2 s in), Gems / Xp / Jackpot (SPIN
-- pressed 0.2 s in, the server answering 0.1 s later with 100 Gems, 50 XP or the jackpot; the reel runs about five
-- seconds and the prize flies to where the HUD's pill and bar are at 1080), Buy (no spins left, SPIN sells one),
-- None (no spins left and none for sale), Close (shutting 0.2 s in), Beckon (the page brought up 0.2 s in for a spin
-- waiting, SPIN wobbling once 0.5 s later), for `rur-native sequence`. The group-owned
-- images 403 offline, so they are swapped for the local PNGs they were made from.
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
-- The prize each spinning moment lands on (SpinsCore.PRIZES), and where it stops inside its card (-1 to 1).
local PRIZES = { Gems = 3, Xp = 4, Jackpot = 1 }
local JITTER = 0.7
-- At 1080 the HUD's scale is 1: the pill's glyph and the level bar where LobbyController's Hud draws them.
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
		Moment = { "Rest", "Enter", "Gems", "Xp", "Jackpot", "Buy", "None", "Close", "Beckon" },
	},
	story = function(props)
		local moment = props.controls.Moment()
		local at = os.clock() + MOMENT_AT
		local isEmpty = moment == "Buy" or moment == "None"
		local prize = PRIZES[moment]

		local state = {
			Scale = source(1),
			Now = source(os.clock()),
			IsOpen = source(moment ~= "Close"),
			ToggledAt = source(if moment == "Enter" or moment == "Close" or moment == "Beckon" then at else -math.huge),
			FreeLeft = source(if isEmpty then 0 else 2),
			FreePerDay = source(2),
			Bought = source(0),
			SecondsLeft = source(13 * 3600 + 24 * 60 + 58),
			CanBuy = source(moment ~= "None"),
			Mode = source(if moment == "Buy" then "Buy" elseif moment == "None" then "None" else "Spin"),
			Rest = source(4),
			Spin = source(nil),
			PillAt = source(PILL),
			BarAt = source(BAR),
			BarLength = source(226),
			RefusedAt = source(-math.huge),
			BeckonAt = source(if moment == "Beckon" then at + 0.5 else -math.huge),
		}

		-- What the controller does: the press, the answer, and the end.
		local isPressed, isAnswered, isDone = false, false, false
		RunService.Heartbeat:Connect(function()
			local now = os.clock()
			state.Now(now)
			if not prize or isDone then return end
			if not isPressed and now >= at then
				isPressed = true
				state.Spin({ StartAt = at, From = state.Rest() })
				state.Mode("Busy")
				state.FreeLeft(1)
			end
			if isPressed and not isAnswered and now >= at + ANSWER_AFTER then
				isAnswered = true
				local planned = ReelMotion.Plan(state.Spin(), prize, now, JITTER)
				planned.PayAt = planned.LandAt + 0.35
				planned.Pieces = 16
				planned.BarFrom = 0.3
				planned.BarTo = 0.8
				state.Spin(planned)
			end
			local spin = state.Spin()
			if spin and spin.PayAt and now >= spin.PayAt + Payout.SECONDS + Reel.LAND_SECONDS then
				isDone = true
				state.Rest(spin.Slot)
				state.Spin(nil)
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
		local top = Shell.Top(morph)
		local page, flights, shake = Screen.Build(state, { Spin = noop }, Shell.Lift(top, 2, state.IsOpen))
		local back, middle, front = Shell.Build(shell, { Close = noop, PickTab = noop }, {
			Day = function(): number
				return 2
			end,
			IsWaiting = function(tab: number): boolean
				return tab == 1
			end,
			IsSpinning = function(): boolean
				return state.Mode() == "Busy"
			end,
			Shake = shake,
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
