--!nonstrict
-- The bottom of the lobby screen: PLAY (onto a free pad as its host), EXIT while on a pad (the only way off it), the
-- queue's status above it, and a notice at the top for a pad that refused.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local MapsCore = require(ReplicatedStorage.GlobalShared.Core.MapsCore)
local PadsCore = require(ReplicatedStorage.Shared.Core.PadsCore)
local Types = require(script.Parent.Types)

local create = vide.create
local source = vide.source
local spring = vide.spring
local Color = Theme.Color
local Font = Theme.Font
local Block = Components.Block
local Text = Components.Text
local EPhase = PadsCore.EPhase

local BUTTON_WIDTH = 380
local BUTTON_HEIGHT = 84
local BUTTON_BOTTOM = 36
local STATUS_WIDTH = 380
local STATUS_HEIGHT = 64
-- Below the platform's top bar (UI.md: 58 tall), centred, so it never meets it.
local TOAST_TOP = 72
local FADE_PERIOD = 0.25
local COLOR_PERIOD = 0.15

local Bar = {}

-- Design pixels from the screen's bottom to the button's top, for whatever stands above it.
Bar.BUTTON_TOP = BUTTON_BOTTOM + BUTTON_HEIGHT

local function currentPad(state: Types.TLobbyState): Types.TPadView?
	return state.Pads[state.CurrentPad()]
end

-- What the queue says, and the colour of its band.
local function statusOf(state: Types.TLobbyState): (string, string, Color3)
	local pad = currentPad(state)
	if not pad then return "", "", Color.Surface end
	local phase = pad.Phase()
	if phase == EPhase.Choosing then return "SETTING UP", "Pick your party", Color.Gold end
	if phase == EPhase.Teleporting then return "TELEPORTING", "Hold on...", Color.Gem end

	local map = MapsCore.LIST[pad.Map()]
	local mapText = if map then `{string.upper(map.DisplayName)} - {string.upper(map.Difficulty)}` else ""
	local count, maxPlayers, seconds = pad.Count(), pad.MaxPlayers(), pad.Seconds()
	local title = if count >= maxPlayers then "STARTING" else `WAITING {count}/{maxPlayers}`
	local time = if seconds >= 0 then ` - {seconds}s` else ""
	local band = if map and map.Difficulty ~= MapsCore.DIFFICULTIES[1] then Color.Boss else Color.Action
	return title .. time, mapText, band
end

local function status(state: Types.TLobbyState): CanvasGroup
	-- Worked out once per change, not once per property that shows a part of it.
	local current = vide.derive(function()
		local title, detail, band = statusOf(state)
		return { Title = title, Detail = detail, Band = band }
	end)
	local shown = spring(function()
		local pad = currentPad(state)
		return if pad and not state.IsChoosing() then 1 else 0
	end, FADE_PERIOD, 1)

	return create("CanvasGroup")({
		Name = "QueueStatus",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -(BUTTON_BOTTOM + BUTTON_HEIGHT + 14)),
		Size = UDim2.fromOffset(STATUS_WIDTH, STATUS_HEIGHT),
		BackgroundTransparency = 1,
		GroupTransparency = function()
			return 1 - shown()
		end,
		Visible = function()
			return shown() > 0.01
		end,
		Block({
			Position = UDim2.fromOffset(2, 2),
			Size = UDim2.new(1, -4, 1, -4),
			create("Frame")({
				Size = UDim2.new(0, 10, 1, 0),
				BorderSizePixel = 0,
				BackgroundColor3 = function()
					return current().Band
				end,
			}),
			Text({
				Position = UDim2.fromOffset(24, 8),
				Size = UDim2.new(1, -36, 0, 28),
				TextXAlignment = Enum.TextXAlignment.Left,
				FontFace = Font.Mono,
				TextSize = 24,
				Text = function()
					return current().Title
				end,
			}),
			Text({
				Position = UDim2.fromOffset(24, 36),
				Size = UDim2.new(1, -36, 0, 18),
				TextXAlignment = Enum.TextXAlignment.Left,
				FontFace = Font.Medium,
				TextSize = 15,
				TextColor3 = Color.Muted,
				Text = function()
					return current().Detail
				end,
			}),
		}),
	})
end

local function playButton(state: Types.TLobbyState, actions: Types.TLobbyActions): TextButton
	local isHovered = source(false)
	local function isQueued(): boolean
		return state.CurrentPad() ~= 0
	end
	local function isTeleporting(): boolean
		local pad = currentPad(state)
		return pad ~= nil and pad.Phase() == EPhase.Teleporting
	end

	return Components.Button({
		Name = "Play",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -BUTTON_BOTTOM),
		Size = UDim2.fromOffset(BUTTON_WIDTH, BUTTON_HEIGHT),
		-- A party on its way cannot be left.
		Visible = function()
			return not isTeleporting()
		end,
		BackgroundColor3 = spring(function()
			if isQueued() then return if isHovered() then Color.BossEdge else Color.Boss end
			return if isHovered() then Color.ActionEdge else Color.Action
		end, COLOR_PERIOD, 1),
		Activated = function()
			if isQueued() then
				actions.Leave()
			else
				actions.Play()
			end
		end,
		MouseEnter = function()
			isHovered(true)
		end,
		MouseLeave = function()
			isHovered(false)
		end,
		Components.Edge(function()
			return if isQueued() then Color.BossEdge else Color.ActionEdge
		end),
		Text({
			Size = UDim2.fromScale(1, 1),
			FontFace = Font.Mono,
			TextSize = 48,
			TextColor3 = Color.Ink,
			Text = function()
				return if isQueued() then "EXIT" else "PLAY"
			end,
		}),
	})
end

local function toast(state: Types.TLobbyState): CanvasGroup
	local shown = spring(function()
		return if state.IsToastShown() then 1 else 0
	end, FADE_PERIOD, 1)

	return create("CanvasGroup")({
		Name = "Notice",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(0, TOAST_TOP) + UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(460, 52),
		BackgroundTransparency = 1,
		GroupTransparency = function()
			return 1 - shown()
		end,
		Visible = function()
			return shown() > 0.01
		end,
		Block({
			Position = UDim2.fromOffset(2, 2),
			Size = UDim2.new(1, -4, 1, -4),
			Components.Edge(Color.BossEdge),
			Text({
				Size = UDim2.fromScale(1, 1),
				FontFace = Font.Bold,
				TextSize = 20,
				Text = state.ToastText,
			}),
		}),
	})
end

function Bar.Build(state: Types.TLobbyState, actions: Types.TLobbyActions): { Instance }
	return {
		status(state),
		playButton(state, actions),
		toast(state),
	}
end

return Bar
