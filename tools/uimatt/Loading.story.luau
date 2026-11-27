-- The loading screen running a scripted join, for rur (the real LoadingScreen, its clock and its sounds):
--   rur-native render --headless --offline --rojo <game.project.json without its comments> \
--     --story tools/uimatt/Loading.story.luau --viewport 1920x1080 --scale 1 --time 3 \
--     --controls '{"Moment": "Join"}' --dir <out>
-- or `rur-native sequence ... --from 0 --to 8 --fps 30` for the whole of it.
-- Moment: Join (the assets in steps to 0.65, WAITING FOR THE SQUAD, ready at 3.4 s, the payoff, the way out), Slow
-- (a long wait that creeps and never ends, with the skip prompt from 2 s), Fast (everything in before the bar opens:
-- it fills in one sweep), Cover (a teleport out: the squares close in over the game, the title and an empty bar come
-- up), Arrive (that cover, its still copy taken as a teleport would, and the arriving place's screen taking over under
-- it at 3 s).
-- rur reads the project file as plain JSON, so strip its comments into a copy first. The group-owned images 403
-- offline, so they are swapped for the local PNGs they were made from.
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(game:GetService("ReplicatedStorage").Packages.vide)
local Icons = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Icons)
local LoadingScreen = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.LoadingScreen)

local create = vide.create

local ROOT = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/hud/"
local RENDERED = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/rendered/"
local SWAPS = {
	[Icons.Pictures.Gem.Image] = RENDERED .. "Pictures1.png",
	[Icons.Pictures.Potion.Image] = RENDERED .. "Pictures2.png",
	[Icons.Pictures.Pointer.Image] = RENDERED .. "Pictures3.png",
	[Icons.Pictures.UpArrow.Image] = RENDERED .. "Pictures4.png",
	[Icons.Pictures.SurvivorVest.Image] = RENDERED .. "Pictures5.png",
	[Icons.IMAGE] = ROOT .. "Icons.png",
	[Icons.PANEL_TEXTURE] = ROOT .. "PanelTexture.png",
	[Icons.SHOWCASE] = ROOT .. "Showcase.png",
}

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

-- Each moment's load: the assets' shares as they come in, a step apart, then how long the place takes to be ready.
local LOADS = {
	Join = { Steps = { 0.1, 0.25, 0.4, 0.55, 0.7, 0.85, 1 }, Step = 0.3, Ready = 1.3 },
	Slow = { Steps = { 0.05, 0.2, 0.3 }, Step = 0.8, Ready = math.huge },
	Fast = { Steps = { 1 }, Step = 0.3, Ready = 0.2 },
}

return {
	vide = vide,
	controls = {
		Moment = { "Join", "Slow", "Fast", "Cover", "Arrive" },
	},
	story = function(props)
		local load = LOADS[props.controls.Moment()]
		local root = create("Frame")({
			Name = "Root",
			Size = UDim2.fromOffset(1920, 1080),
			BackgroundColor3 = Color3.fromRGB(120, 150, 190),
			BorderSizePixel = 0,
		})
		swapImages(root)

		-- From plain code, as LoadingScreen.client calls it: deferred past the story's own vide scope, which would hide a
		-- reactive call made outside the screen's root (task.spawn runs at once, still inside it).
		task.defer(function()
			local moment = props.controls.Moment()
			if moment == "Cover" or moment == "Arrive" then
				local away =
					create("Frame")({ Name = "Away", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
				away.Parent = root
				local cover = LoadingScreen.new(away, { Mode = "Cover", Text = "ENTERING THE RUN" })
				if moment == "Cover" then return end
				task.wait(3)
				cover.WaitReady()
				-- What Snapshot does to its ScreenGui, on the story's frame.
				local copy = away:Clone()
				for _, descendant in copy:GetDescendants() do
					if descendant.Name == "Motes" or descendant.Name == "Squares" then descendant:Destroy() end
				end
				cover.Destroy()
				away:Destroy()
				copy.ZIndex = 1000
				copy.Parent = root
				local arrival = LoadingScreen.new(root, { Mode = "Arrive", Arriving = copy })
				arrival.SetPhase("LOADING", 0, 0.65)
				for _, share in LOADS.Join.Steps do
					task.wait(LOADS.Join.Step)
					arrival.SetProgress(share)
				end
				return
			end
			local screen = LoadingScreen.new(root)
			screen.SetPhase("LOADING", 0, 0.65)
			task.delay(2, function()
				screen.ShowSkip(function() end)
			end)
			for _, share in load.Steps do
				task.wait(load.Step)
				screen.SetProgress(share)
			end
			screen.SetPhase("WAITING FOR THE SQUAD", 0.65, 1)
			if load.Ready == math.huge then return end
			task.wait(load.Ready)
			screen.Complete()
			screen.Leave()
		end)

		return root
	end,
}
