-- The debug readout (UI/DebugInfoUI) with fixed numbers, for rur over the HUD story's background:
--   rur-native render --headless --offline --rojo <game.project.json without its comments> \
--     --story tools/uimatt/DebugInfo.story.luau --viewport 1920x1080 --scale 1 --background 40,40,60 --time 1.5 \
--     --controls '{"Moment": "Rest"}' --dir <out>
-- Moment: Rest (a match's seven lines up), Lobby (the four a lobby counts), Slow (FPS and ping graded gold and red),
-- Show (the column coming up from 0.2 s) and Hide (going from 0.2 s), for `rur-native sequence`.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local DebugInfoUI = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.DebugInfoUI)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)

local source = vide.source
local create = vide.create
local Palette = Theme.Palette

local MOMENT_AT = 0.2
local RED = Color3.fromRGB(230, 60, 72)

return {
	vide = vide,
	controls = {
		Moment = { "Rest", "Lobby", "Slow", "Show", "Hide" },
	},
	story = function(props)
		local moment = props.controls.Moment()
		local at = os.clock() + MOMENT_AT
		local isMoving = moment == "Show" or moment == "Hide"
		local isLobby = moment == "Lobby"
		local isSlow = moment == "Slow"

		local function line(name: string, value: string, color: Color3?, isUsed: boolean?)
			return {
				Name = name,
				Value = source(value),
				Color = source(color or Palette.White),
				IsUsed = source(isUsed ~= false),
			}
		end

		local state = {
			Scale = source(1),
			Now = source(if isMoving then os.clock() else math.huge),
			IsShown = source(moment ~= "Show"),
			ToggledAt = source(-math.huge),
			Lift = source(0),
			Lines = {
				line("ENEMIES", "212", nil, not isLobby),
				line("PROJECTILES", if isLobby then "0" else "31"),
				line("COINS", "18", nil, not isLobby),
				line("PARTICLES", if isLobby then "4" else "486"),
				line("SPEED", if isLobby then "33.0" else "21.7"),
				line("PING", if isSlow then "312" else "64", if isSlow then RED else Palette.Green),
				line("FPS", if isSlow then "41" else "60", if isSlow then Palette.Gold else Palette.Green),
			},
		}

		if isMoving then
			task.delay(MOMENT_AT, function()
				state.IsShown(moment == "Show")
				state.ToggledAt(at)
			end)
			RunService.Heartbeat:Connect(function()
				state.Now(os.clock())
			end)
		end

		return create("Frame")({
			Name = "Root",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			DebugInfoUI.Build(state),
		})
	end,
}
