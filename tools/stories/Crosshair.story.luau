-- The crosshair over the places a crosshair gets lost (sky, grass, a red wall, a muzzle flash, the dark), playing one
-- moment of the fight, for rur to render:
--   rur-native render --headless --offline --rojo <game.project.json without its comments> \
--     --story tools/stories/Crosshair.story.luau --viewport 1000x1250 --scale 1 --time 1 \
--     --controls '{"Moment": "Fight"}' --dir <out>
-- and `rur-native sequence` the same way for the motion. The moments start MOMENT_AT in; Fight loops every
-- FIGHT_SECONDS. Unit is the screen's height over 1080: 2 magnifies it, 1 is a 1080p screen.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Crosshair = require(StarterPlayer.StarterPlayerScripts.GlobalClient.Controllers.CrosshairController.Crosshair)

local create = vide.create

local ROOT = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/crosshair/preview/backgrounds/"
local BACKGROUNDS = { "sky", "grass", "wall", "flash", "dark" }
local DARK = Color3.fromRGB(32, 30, 48)
local CELL = 300
local HEADER = 40
local MOMENT_AT = 0.3
local FIGHT_SECONDS = 3
-- The gun's cone at a 1080p screen, design pixels (the controller's spreadOf at 70 degrees).
local SPREADS = { Sniper = 0, Rifle = 8.1, Pistol = 10.8, Smg = 29.7 }
local KICK = 7

type TEvent = { At: number, Run: (state: Crosshair.TState, now: number) -> () }

local function arm(state: Crosshair.TState, now: number)
	state.IsArmed(true)
	state.ArmedAt(now)
end

local function fire(state: Crosshair.TState, now: number)
	state.FiredAt(now)
	state.Kick(KICK)
end

local function aim(isOn: boolean)
	return function(state: Crosshair.TState, now: number)
		state.IsOnTarget(isOn)
		state.TargetAt(now)
	end
end

local function hit(streak: number)
	return function(state: Crosshair.TState, now: number)
		state.HitAt(now)
		state.Streak(streak)
	end
end

local function kill(isOverkill: boolean)
	return function(state: Crosshair.TState, now: number)
		state.KillAt(now)
		state.IsOverkill(isOverkill)
	end
end

local function hurt(state: Crosshair.TState, now: number)
	state.HurtAt(now)
end

-- Each moment's events, seconds after MOMENT_AT. A moment that starts armed arms at 0 first.
local MOMENTS: { [string]: { TEvent } } = {
	Rest = {},
	Arm = { { At = 0, Run = arm } },
	Unarm = {
		{
			At = 0,
			Run = function(state, now)
				state.IsArmed(false)
				state.ArmedAt(now)
			end,
		},
	},
	Fire = { { At = 0, Run = fire } },
	Target = { { At = 0, Run = aim(true) } },
	Hit = { { At = 0, Run = fire }, { At = 0.03, Run = hit(1) } },
	Streak = {},
	Kill = { { At = 0, Run = aim(true) }, { At = 0, Run = fire }, { At = 0.03, Run = kill(false) } },
	Overkill = { { At = 0, Run = aim(true) }, { At = 0, Run = fire }, { At = 0.03, Run = kill(true) } },
	Hurt = { { At = 0, Run = hurt } },
	-- On an enemy, a short streak of hits and then the kill.
	TargetHit = {
		{ At = 0, Run = aim(true) },
		{ At = 0.1, Run = fire },
		{ At = 0.13, Run = hit(1) },
		{ At = 0.3, Run = fire },
		{ At = 0.33, Run = hit(2) },
		{ At = 0.5, Run = fire },
		{ At = 0.53, Run = hit(3) },
		{ At = 0.7, Run = fire },
		{ At = 0.73, Run = kill(false) },
	},
	Fight = {
		{ At = 0.3, Run = aim(true) },
		{ At = 0.4, Run = fire },
		{ At = 0.43, Run = hit(1) },
		{ At = 0.6, Run = fire },
		{ At = 0.63, Run = hit(2) },
		{ At = 0.8, Run = fire },
		{ At = 0.83, Run = kill(false) },
		{ At = 1.1, Run = aim(false) },
		{ At = 1.4, Run = hurt },
		{ At = 1.8, Run = aim(true) },
		{ At = 1.9, Run = fire },
		{ At = 1.93, Run = kill(true) },
		{ At = 2.3, Run = aim(false) },
	},
}
for shot = 0, 5 do
	table.insert(MOMENTS.Streak, { At = shot * 0.1, Run = fire })
	table.insert(MOMENTS.Streak, { At = shot * 0.1 + 0.03, Run = hit(shot + 1) })
end

local function cell(background: string, unit: number, spread: number): (Frame, Crosshair.TState)
	local state = Crosshair.State()
	state.Unit(unit)
	state.Spread(spread)
	state.Position(UDim2.fromScale(0.5, 0.5))

	local isPicture = background ~= "dark" and background ~= "none"
	local frame = create(if isPicture then "ImageLabel" else "Frame")({
		Name = background,
		Size = UDim2.fromOffset(CELL, CELL),
		BackgroundColor3 = DARK,
		BackgroundTransparency = if background == "none" then 1 else 0,
		BorderSizePixel = 0,
		Image = if isPicture then `{ROOT}{background}.png` else nil,
		Crosshair.Build(state),
	})
	return frame, state
end

return {
	vide = vide,
	controls = {
		Moment = {
			"Rest",
			"Arm",
			"Unarm",
			"Fire",
			"Target",
			"Hit",
			"Streak",
			"Kill",
			"Overkill",
			"Hurt",
			"TargetHit",
			"Fight",
		},
		Gun = { "Pistol", "Sniper", "Rifle", "Smg" },
		Unit = { 2, 1, 1.333 },
		-- None draws the crosshairs alone, to lay over a screenshot (render with --background transparent).
		Backdrop = { "Scenes", "None" },
	},
	story = function(props)
		local moment = props.controls.Moment()
		local unit = props.controls.Unit()
		local spread = SPREADS[props.controls.Gun()]
		local backgrounds = if props.controls.Backdrop() == "None" then { "none" } else BACKGROUNDS
		local states: { Crosshair.TState } = {}
		local children = {}

		for column, background in backgrounds do
			table.insert(
				children,
				create("TextLabel")({
					Position = UDim2.fromOffset((column - 1) * CELL, 0),
					Size = UDim2.fromOffset(CELL, HEADER),
					BackgroundTransparency = 1,
					Text = background,
					TextColor3 = Color3.new(1, 1, 1),
					TextSize = 24,
					FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold),
				})
			)
			local frame, state = cell(background, unit, spread)
			frame.Position = UDim2.fromOffset((column - 1) * CELL, HEADER)
			table.insert(children, frame)
			table.insert(states, state)
		end

		local events = MOMENTS[moment]
		for _, state in states do
			state.IsArmed(moment ~= "Arm")
		end

		local clock = 0
		local loop = 0
		local fired = {}
		RunService.Heartbeat:Connect(function(dt: number)
			clock += dt
			local since = clock - MOMENT_AT
			if moment == "Fight" and since >= (loop + 1) * FIGHT_SECONDS then
				loop += 1
				table.clear(fired)
			end

			local intoLoop = since - loop * FIGHT_SECONDS
			for index, event in events do
				if fired[index] or intoLoop < event.At then continue end
				fired[index] = true
				for _, state in states do
					event.Run(state, clock)
				end
			end

			for _, state in states do
				state.Now(clock)
			end
		end)

		return create("Frame")({
			Name = "Stage",
			BackgroundColor3 = Color3.fromRGB(18, 16, 28),
			BackgroundTransparency = if props.controls.Backdrop() == "None" then 1 else 0,
			Size = UDim2.fromOffset(#backgrounds * CELL, HEADER + CELL),
			children,
		})
	end,
}
