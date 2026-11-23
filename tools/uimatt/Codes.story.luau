-- The codes screen with a scripted state, for rur to render (he drew no codes screen: it is checked against the
-- Spins and Settings renders beside it, the same renderer and background):
--   rur-native render --headless --offline --rojo <game.project.json without its comments> \
--     --story tools/uimatt/Codes.story.luau --viewport 1920x1080 --scale 1 --background 40,40,60 --time 1.5 \
--     --controls '{"Moment": "Rest"}' --dir <out>
-- Moment: Rest (open and settled, nothing typed), Typed (LAUNCH typed, the field in focus), Typing (LAUNCH typed a
-- key at a time, then one deleted), Paste (a code pasted), Redeem (LAUNCH redeemed: the scan, the answer at 0.55 s, the
-- cards, the sweep), Refuse (a code that does not exist), Empty (REDEEM pressed with nothing typed), Open (the screen
-- coming up), for `rur-native sequence`. It writes the controller's sources on CodesController's timings. The
-- group-owned images 403 offline, so they are swapped for the local PNGs they were made from.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local CodesCore = require(ReplicatedStorage.GlobalShared.Core.CodesCore)
local Icons = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Icons)
local CodesUI = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.CodesUI)

local source = vide.source
local create = vide.create

local ROOT = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/hud/"
local SWAPS = {
	[Icons.IMAGE] = ROOT .. "Icons.png",
	[Icons.PANEL_TEXTURE] = ROOT .. "PanelTexture.png",
}
-- CodesController's.
local WIND_UP = 0.32
local REWARDS_DELAY = 0.3
local CLEAR_DELAY = 1.15
local SWEEP_STAGGER = 0.03
local PASTE_STAGGER = 0.03

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
		Moment = { "Rest", "Typed", "Typing", "Paste", "Redeem", "Refuse", "Empty", "Open" },
	},
	story = function(props)
		local moment = props.controls.Moment()
		local isMoving = moment ~= "Rest" and moment ~= "Typed"

		local bornAt, ghosts = {}, {}
		for index = 1, CodesCore.MAX_LENGTH do
			bornAt[index] = source(-math.huge)
			ghosts[index] = {
				Letter = source(""),
				Cell = source(1),
				At = source(-math.huge),
				IsLift = source(false),
			}
		end
		local state = {
			Scale = source(1),
			Now = source(if isMoving then os.clock() else math.huge),
			IsOpen = source(true),
			ToggledAt = source(if moment == "Open" then os.clock() + 0.2 else -math.huge),
			Text = source(if moment == "Typed" then "LAUNCH" else ""),
			BornAt = bornAt,
			Ghosts = ghosts,
			IsFocused = source(moment ~= "Rest" and moment ~= "Open"),
			FocusedAt = source(-math.huge),
			IsCaretOn = source(true),
			Status = source("Typing"),
			AskedAt = source(-math.huge),
			AnsweredAt = source(-math.huge),
			Message = source("TYPE A CODE, THEN PRESS REDEEM"),
			MessageKind = source("Hint"),
			MessageAt = source(-math.huge),
			NudgedAt = source(-math.huge),
			Gems = source(0),
			Xp = source(0),
			RewardsAt = source(-math.huge),
		}
		local nextGhost = 1

		local function release(letter: string, cell: number, at: number, isLift: boolean)
			local slot = ghosts[nextGhost]
			nextGhost = nextGhost % #ghosts + 1
			slot.Letter(letter)
			slot.Cell(cell)
			slot.IsLift(isLift)
			slot.At(at)
		end
		-- CodesController's typing, without the sound.
		local function typeText(text: string)
			local old = state.Text()
			local now = os.clock()
			local same = 0
			while same < #old and same < #text and string.byte(old, same + 1) == string.byte(text, same + 1) do
				same += 1
			end
			local added = #text - same
			for cell = same + 1, #old do
				release(string.sub(old, cell, cell), cell, now, false)
			end
			for cell = same + 1, #text do
				bornAt[cell](if added > 1 then now + PASTE_STAGGER * (cell - same - 1) else now)
			end
			state.Text(text)
		end
		local function say(text: string, kind: string)
			state.Message(text)
			state.MessageKind(kind)
			state.MessageAt(os.clock())
		end
		local function at(seconds: number, callback: () -> ())
			task.delay(seconds, callback)
		end
		local function typeOut(code: string, from: number, every: number)
			for index = 1, #code do
				at(from + every * (index - 1), function()
					typeText(string.sub(code, 1, index))
				end)
			end
		end
		local function ask(seconds: number, status: string, answer: () -> ())
			at(seconds, function()
				state.Status("Checking")
				state.AskedAt(os.clock())
			end)
			at(seconds + WIND_UP + 0.03, function()
				state.Status(status)
				state.AnsweredAt(os.clock())
				answer()
			end)
		end

		if moment == "Typing" then
			typeOut("LAUNCH", 0.2, 0.12)
			at(1.1, function()
				typeText("LAUNC")
			end)
		elseif moment == "Paste" then
			at(0.2, function()
				typeText("SUMMEREVENT2026")
			end)
		elseif moment == "Redeem" then
			state.Text("LAUNCH")
			ask(0.2, "Redeemed", function()
				say("CODE REDEEMED!", "Good")
				state.Gems(100)
				state.Xp(50)
				state.RewardsAt(os.clock() + REWARDS_DELAY)
				at(CLEAR_DELAY, function()
					local now = os.clock()
					local text = state.Text()
					for cell = 1, #text do
						release(string.sub(text, cell, cell), cell, now + SWEEP_STAGGER * (cell - 1), true)
					end
					state.Text("")
				end)
			end)
		elseif moment == "Refuse" then
			state.Text("FREEGEMS")
			ask(0.2, "Refused", function()
				say("THAT CODE DOESN'T EXIST", "Bad")
			end)
		elseif moment == "Empty" then
			at(0.2, function()
				state.NudgedAt(os.clock())
				say("TYPE A CODE FIRST", "Bad")
			end)
		end

		if isMoving then RunService.Heartbeat:Connect(function()
			state.Now(os.clock())
		end) end

		local children = CodesUI.Build(state, {
			Close = noop,
			Type = typeText,
			Focus = noop,
			Redeem = noop,
		})
		local root = create("Frame")({
			Name = "Root",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			children,
		})
		swapImages(root)
		return root
	end,
}
