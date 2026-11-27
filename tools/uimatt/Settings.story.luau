-- The settings screen with a fixed state, for rur to render beside the designer's Settings renders
-- (Assets/ui/UIMatt/renders/07_Settings.png and 08_Settings_Reset_Confirm.png, the same renderer and background):
--   rur-native render --headless --offline --rojo <game.project.json without its comments> \
--     --story tools/uimatt/Settings.story.luau --viewport 1920x1080 --scale 1 --background 40,40,60 --time 1.5 \
--     --controls '{"Moment": "Rest"}' --dir <out>
-- Moment: Rest (everything landed, his values), Confirm (his reset confirm over it), Defaults (nothing changed, so
-- nothing to reset), Scrolled (the scroll at its end), Open (the screen going up, 0.2 s in), Ask (the confirm coming
-- forward), ResetAll (the confirm accepted: every row going home), Toggle (a switch turned on), Scroll (the scroll
-- running from its top to its end from 0.2 s), for `rur-native sequence`. Reach: the px at the top kept free, the
-- lobby's Gems row at 1080 (73) or a bare Roblox top bar (58).
-- rur reads the project file as plain JSON, so strip its comments into a copy first. The group-owned images 403
-- offline, so they are swapped for the local PNGs they were made from.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Icons = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Icons)
local SettingsUI = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.SettingsUI)

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
		Moment = { "Rest", "Confirm", "Defaults", "Scrolled", "Open", "Ask", "ResetAll", "Toggle", "Scroll" },
		Reach = 73,
	},
	story = function(props)
		local moment = props.controls.Moment()
		local at = os.clock() + MOMENT_AT
		local isDefault = moment == "Defaults"
		local isMoving = moment == "Open"
			or moment == "Ask"
			or moment == "ResetAll"
			or moment == "Toggle"
			or moment == "Scroll"

		local function volume(id: number, text: string, value: number)
			return {
				Id = id,
				Label = text,
				Default = 100,
				Value = source(if isDefault then 100 else value),
				IsDragging = source(false),
				ResetAt = source(-math.huge),
			}
		end
		local function toggle(id: number, text: string, description: string, isOn: boolean, default: boolean?)
			return {
				Id = id,
				Label = text,
				Description = description,
				Default = default == true,
				IsOn = source(if isDefault then default == true else isOn),
				ChangedAt = source(-math.huge),
				ResetAt = source(-math.huge),
			}
		end

		-- His values: music 100, sound effects 75, menu sounds 0, shake as it is, drag fire on, a typed name.
		local state = {
			Scale = source(1),
			Height = source(SettingsUI.HeightFor(1080, props.controls.Reach())),
			Now = source(if isMoving then os.clock() else math.huge),
			IsOpen = source(true),
			ToggledAt = source(if moment == "Open" then at else -math.huge),
			IsConfirmOpen = source(moment == "Confirm" or moment == "ResetAll"),
			ConfirmToggledAt = source(-math.huge),
			Volumes = {
				volume(1, "MUSIC", 100),
				volume(2, "SOUND EFFECTS", 75),
				volume(3, "MENU SOUNDS", 0),
			},
			Toggles = {
				toggle(4, "REDUCE CAMERA SHAKE", "No camera shake; weapon kick stays", false),
				toggle(5, "DRAG FIRE TO AIM", "Drag the fire button to look around", true),
				toggle(6, "DAMAGE NUMBERS", "Show the damage each hit deals", true, true),
				toggle(7, "DEBUG INFO", "FPS, ping, enemies and more in the corner", true),
			},
			SavedAt = source(-math.huge),
		}

		if moment == "Ask" then
			task.delay(MOMENT_AT, function()
				state.IsConfirmOpen(true)
				state.ConfirmToggledAt(os.clock())
			end)
		elseif moment == "ResetAll" then
			task.delay(MOMENT_AT, function()
				local now = os.clock()
				for index, row in state.Volumes do
					row.Value(row.Default)
					row.ResetAt(now + 0.05 * index)
				end
				state.Toggles[2].IsOn(false)
				state.Toggles[2].ResetAt(now + 0.2)
				state.IsConfirmOpen(false)
				state.ConfirmToggledAt(now)
				state.SavedAt(now)
			end)
		elseif moment == "Toggle" then
			task.delay(MOMENT_AT, function()
				state.Toggles[1].IsOn(true)
				state.Toggles[1].ChangedAt(os.clock())
				state.SavedAt(os.clock())
			end)
		end

		if isMoving then RunService.Heartbeat:Connect(function()
			state.Now(os.clock())
		end) end

		local root = create("Frame")({
			Name = "Root",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			SettingsUI.Build(state, {
				Close = noop,
				DragVolume = noop,
				ReleaseVolume = noop,
				ResetVolume = noop,
				SetToggle = noop,
				ResetToggle = noop,
				AskResetAll = noop,
				CancelResetAll = noop,
				ConfirmResetAll = noop,
			}),
		})
		swapImages(root)
		local list = root:FindFirstChild("List", true) :: ScrollingFrame
		if moment == "Scrolled" then
			list.CanvasPosition = Vector2.new(0, 10_000)
		elseif moment == "Scroll" then
			local from = os.clock() + MOMENT_AT
			RunService.Heartbeat:Connect(function()
				local t = math.clamp((os.clock() - from) / 0.6, 0, 1)
				list.CanvasPosition = Vector2.new(0, 400 * (1 - (1 - t) ^ 3))
			end)
		end
		return root
	end,
}
