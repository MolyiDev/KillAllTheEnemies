-- The upgrade pick run offline, for ror to film: the real controller with its server, camera and wallet stood in, a
-- hand dealt, the pointer walked over the cards, a redeal, and a pick.
--   ree record --harness tools/ree/UpgradePick.luau --out <dir> --seconds 7 --viewport 1920x1080 --offline \
--     --mount ReplicatedStorage/Packages=Packages --mount ReplicatedStorage/Types=src/Global/Types \
--     --mount ReplicatedStorage/Data=src/Global/Data --mount ReplicatedStorage/GlobalShared=src/Global/Shared \
--     --mount ReplicatedStorage/Shared=src/Game/Shared \
--     --mount StarterPlayer/StarterPlayerScripts/GlobalClient=src/Global/Client \
--     --mount StarterPlayer/StarterPlayerScripts/Client=src/Game/Client
--   ROR_RUR=~/.local/share/roblox-tools/roblox-ui-renderer ror video <dir>/scene.rbxm --no-service \
--     --playback <dir>/playback.json --camera-track <dir>/camera.json --duration 7
-- (--no-service: the warm render service keeps the environment it started with, and without ROR_RUR draws no GUI.)
-- The HUD's group-owned images 403 offline: swapped for their local PNGs.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

local ROOT = "file:///home/molyi/Projects/KillAllTheMonsters/Assets/ui/hud/"

local NETWORK = [[
local function event() return { On = function() end, Fire = function() end } end
return { Server = { Upgrades = { Offer = event(), Picked = event(), Reset = event() } },
	Client = { Upgrades = { Pick = event(), Reroll = event() } } }
]]

return function(Context)
	local scripts = StarterPlayer.StarterPlayerScripts
	local globalClient = scripts.GlobalClient
	local controllers = scripts.Client.Controllers
	local playerScripts = Players.LocalPlayer:FindFirstChild("PlayerScripts") or Instance.new("Folder")
	playerScripts.Name = "PlayerScripts"
	playerScripts.Parent = Players.LocalPlayer
	local running = globalClient:Clone()
	running.Parent = playerScripts

	Context.StandIn(globalClient.Network, NETWORK)
	Context.StandIn(running.Controllers.CameraController, "return { IsMouseFreed = false }")
	Context.StandIn(controllers.MatchController, "return { Gold = 500 }")
	Context.StandIn(controllers.TweensController, "return { PunchFov = function() end }")
	Context.StandIn(
		ReplicatedStorage.GlobalShared.Core.SoundsCore,
		"local none = function() end return { PlayUISound = none, PlayUINamed = none, PlayHover = none, PlayClick = none, SetMuffled = none }"
	)
	Context.StandIn(ReplicatedStorage.Packages.Ignis, "return { Register = function(module) return module end }")

	local Icons = require(globalClient.UI.Icons)
	local swaps = { [Icons.IMAGE] = ROOT .. "Icons.png", [Icons.PANEL_TEXTURE] = ROOT .. "PanelTexture.png" }
	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui") or Instance.new("PlayerGui", Players.LocalPlayer)
	playerGui.DescendantAdded:Connect(function(instance)
		if instance:IsA("ImageLabel") and swaps[instance.Image] then instance.Image = swaps[instance.Image] end
	end)

	-- Something to dim: a floor and a few bricks.
	local floor = Instance.new("Part")
	floor.Anchored = true
	floor.Size = Vector3.new(200, 1, 200)
	floor.Color = Color3.fromRGB(90, 170, 90)
	floor.Parent = Workspace
	for index = 1, 6 do
		local brick = Instance.new("Part")
		brick.Anchored = true
		brick.Size = Vector3.new(4, 6 + index, 4)
		brick.Position = Vector3.new(-30 + index * 9, 4, -30 - (index % 3) * 6)
		brick.Color = Color3.fromHSV(index / 7, 0.6, 0.9)
		brick.Parent = Workspace
	end

	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 70
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 9, 14), Vector3.new(0, 6, -20))

	local Pick = require(controllers.UpgradePickController)
	Pick.OnStart()

	local function hand(cards, isReroll)
		return {
			Cards = cards,
			Round = 5,
			RerollPrice = if isReroll then 100 else 50,
			Seconds = 12,
			IsReroll = isReroll,
		}
	end

	Pick.Show(hand({
		{ Id = 1, Level = 1, Rarity = 2 },
		{ Id = 6, Level = 1, Rarity = 3 },
		{ Id = 2, Level = 3, Rarity = 1 },
	}, false))

	-- The pointer: onto the first card, across to the third, then resting on the second, low and to its right.
	local viewport = camera.ViewportSize
	local middle = viewport / 2
	local function point(x: number, y: number)
		Pick.BenchPointer = Vector2.new(middle.X + x, middle.Y + y)
	end
	task.delay(1.5, point, -480, -60)
	task.delay(1.9, point, -330, 120)
	task.delay(2.3, point, 330, -100)
	task.delay(2.7, point, 470, 150)
	task.delay(3.0, function()
		Pick.BenchPointer = nil
		Pick.Show(hand({
			{ Id = 5, Level = 1, Rarity = 4 },
			{ Id = 3, Level = 2, Rarity = 1 },
			{ Id = 7, Level = 1, Rarity = 5 },
		}, true))
	end)
	task.delay(4.2, point, 90, 140)
	task.delay(4.8, Pick.Resolve, 2)
end
