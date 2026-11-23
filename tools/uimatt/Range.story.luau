-- The shooting range's strip of guns with a fixed state, for rur to render:
--   rur-native render --headless --offline --rojo <lobby.project.json without its comments> \
--     --story tools/uimatt/Range.story.luau --viewport 1920x1080 --scale 1 --background 40,40,60 --time 2 \
--     --controls '{"Moment": "Rest"}' --dir <out>
-- Moment: Rest (walked in, a loadout of four, the Desert Eagle in hand), Enter (walking in 0.2 s in: the strip rising
-- from the middle out), Pick (the third slot, the Starter Smg, the minigun, picked 0.2 s in), Try (brought by TRY:
-- only the Desert Eagle, the cover closing and opening). The group-owned images 403
-- offline, so they are swapped for the local PNGs they were made from. The guns' meshes are private, so the pictures
-- come out empty here: judge them in a playtest.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Icons = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Icons)
local EGunsIds = require(ReplicatedStorage.Types.Enums.Data.EGunsIds)
local Strip = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.RangeController.Strip)

local source = vide.source
local create = vide.create

local ROOT = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/hud/"
local SWAPS = {
	[Icons.IMAGE] = ROOT .. "Icons.png",
	[Icons.PANEL_TEXTURE] = ROOT .. "PanelTexture.png",
}
local MOMENT_AT = 0.2

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
		Moment = { "Rest", "Enter", "Pick", "Try" },
	},
	story = function(props)
		local moment = props.controls.Moment()
		local at = os.clock() + MOMENT_AT
		local state = {
			Scale = source(1),
			Now = source(os.clock()),
			IsInside = source(true),
			InsideAt = source(if moment == "Enter" then at else -math.huge),
			Shown = source(if moment == "Try"
				then { EGunsIds.DesertEagle }
				else {
					EGunsIds.DesertEagle,
					EGunsIds.StarterRifle,
					EGunsIds.StarterSmg,
					EGunsIds.RpgBazooka,
				}),
			Held = source(EGunsIds.DesertEagle),
			HeldAt = source(-math.huge),
			CoverAt = source(if moment == "Try" then at else -math.huge),
			UncoverAt = source(if moment == "Try" then at + 0.3 else -math.huge),
		}
		local hasPicked = false

		RunService.Heartbeat:Connect(function()
			local now = os.clock()
			state.Now(now)
			if moment == "Pick" and not hasPicked and now >= at then
				hasPicked = true
				state.Held(EGunsIds.StarterSmg)
				state.HeldAt(now)
			end
		end)

		local root = create("Frame")({
			Name = "Root",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(1920, 1080),
			Strip.Build(state, { Pick = noop }),
			Strip.Cover(state),
		})
		swapImages(root)
		return root
	end,
}
