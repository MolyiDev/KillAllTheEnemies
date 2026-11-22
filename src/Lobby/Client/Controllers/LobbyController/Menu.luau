--!nonstrict
-- The host's party menu (GDD 3: form a party, select an eligible map). A map list on the left; on the right the
-- picked map's banner with this player's best wave, then party size, difficulty and access, each section in its own
-- colour; the config read back in one line beside CREATE. A locked map or difficulty shows what opens it (GDD 8).
-- Nothing is decided here: CREATE sends the picks and the server checks every one of them again.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local MapsCore = require(ReplicatedStorage.GlobalShared.Core.MapsCore)
local PadsCore = require(ReplicatedStorage.Shared.Core.PadsCore)
local Bar = require(script.Parent.Bar)
local Types = require(script.Parent.Types)

local create = vide.create
local spring = vide.spring
local Color = Theme.Color
local Font = Theme.Font
local Text = Components.Text

local WIDTH = 980
local HEADER_HEIGHT = 64
local LEFT_WIDTH = 300
local RIGHT_WIDTH = WIDTH - LEFT_WIDTH
local BANNER_HEIGHT = 190
local SECTION_HEIGHT = 128
local BODY_HEIGHT = BANNER_HEIGHT + 2 * SECTION_HEIGHT
local FOOTER_HEIGHT = 88
local HEIGHT = HEADER_HEIGHT + BODY_HEIGHT + FOOTER_HEIGHT
local LINE = Theme.EDGE_THICKNESS
local MAP_ROW_HEIGHT = 84
local THUMB_SIZE = 60
local CREATE_WIDTH = 300
-- Above the EXIT button, never on it.
local BOTTOM = Bar.BUTTON_TOP + 24
-- Seconds a colour takes to ease to its new state.
local COLOR_PERIOD = 0.15
local FADE_PERIOD = 0.25
local BOSS_EVERY = 15

-- The colour each section speaks in, so the eye finds it by colour before it reads the label.
local SIZE_COLOR = Color.Gem
local ACCESS_COLOR = Color.Xp

local function difficultyColor(difficulty: string): Color3
	return if difficulty == MapsCore.DIFFICULTIES[1] then Color.Action else Color.Boss
end

-- Only the source: spring also returns its settings function, which a caller passing this on would take as an
-- argument (Edge's transparency, the first playtest).
local function eased(color: () -> Color3): () -> Color3
	local animated = spring(color, COLOR_PERIOD, 1)
	return animated
end

-- What the hand lays over a button's face, under its words: the white it washes over it and its glint.
local function handLayers(hand: Hand.TReaction): { Frame }
	return { Hand.WashLayer(hand, 0), Components.Sheen(hand.Glint, 0) }
end

-- A line between two parts of the panel, in the panel's edge colour.
local function line(props: { [any]: any }): Frame
	return create("Frame")({
		BackgroundColor3 = Color.Edge,
		BorderSizePixel = 0,
		props,
	})
end

local function label(text: string, color: Color3, props: { [any]: any }): TextLabel
	return Text({
		FontFace = Font.Mono,
		TextSize = 16,
		TextColor3 = color,
		Text = text,
		props,
	})
end

-- One choice: `color` lights it when picked; a locked one is grey and does nothing.
local function tile(props: {
	Order: number,
	Size: UDim2,
	Label: string,
	TextSize: number,
	Color: Color3,
	IsPicked: () -> boolean,
	IsLocked: (() -> boolean)?,
	Pick: () -> (),
}): TextButton
	local isTileLocked = props.IsLocked or function()
		return false
	end
	local hand = Hand.React("Operate", function()
		return not isTileLocked()
	end)
	local fill = eased(function()
		if isTileLocked() then return Color.Locked end
		if props.IsPicked() then return props.Color end
		return if hand.IsHovered() then Color.Edge else Color.Surface
	end)

	return Components.Button({
		LayoutOrder = props.Order,
		Size = props.Size,
		BackgroundColor3 = fill,
		Activated = function()
			if isTileLocked() then return end
			hand.Commit()
			props.Pick()
		end,
		hand.Events,
		handLayers(hand),
		Components.Edge(eased(function()
			if props.IsPicked() and not isTileLocked() then return props.Color:Lerp(Color.Text, 0.45) end
			return Color.Edge
		end)),
		Text({
			Size = UDim2.fromScale(1, 1),
			FontFace = Font.Heavy,
			TextSize = props.TextSize,
			Text = props.Label,
			TextColor3 = function()
				return if props.IsPicked() and not isTileLocked() then Color.Ink else Color.Text
			end,
		}),
	})
end

-- A centred row of `children`, as the children of whatever frame it is put in.
local function row(children: { Instance }, padding: number): { Instance }
	local list: { Instance } = table.clone(children)
	table.insert(
		list,
		create("UIListLayout")({
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, padding),
			SortOrder = Enum.SortOrder.LayoutOrder,
		})
	)
	return list
end

local function isLocked(state: Types.TLobbyState, map: MapsCore.TMap): boolean
	return not MapsCore.IsUnlockedBy(map, state.BestByMap())
end

local function pickedMap(state: Types.TLobbyState): MapsCore.TMap
	return MapsCore.LIST[state.PickMap()] or MapsCore.LIST[1]
end

local function bestOf(state: Types.TLobbyState, map: MapsCore.TMap): number
	return state.BestByMap()[map.Name] or 0
end

-- The map's initials, for a thumbnail until the maps have pictures.
local function initials(name: string): string
	local letters = {}
	for word in string.gmatch(name, "%a+") do
		letters[#letters + 1] = string.sub(word, 1, 1)
	end

	return string.upper(table.concat(letters, "", 1, math.min(#letters, 2)))
end

local function header(actions: Types.TLobbyActions): Frame
	local hand = Hand.React("Operate")
	local isHovered = hand.IsHovered
	return create("Frame")({
		Size = UDim2.new(1, 0, 0, HEADER_HEIGHT),
		BackgroundTransparency = 1,
		label("LOBBY // NEW PARTY", Color.Action, {
			Position = UDim2.fromOffset(28, 0),
			Size = UDim2.new(1, -120, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 26,
		}),
		Components.Button({
			Name = "Close",
			-- Placed by its middle, so it grows from there.
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -12 - 22, 0.5, 0),
			Size = UDim2.fromOffset(44, 44),
			BackgroundColor3 = eased(function()
				return if isHovered() then Color.Boss else Color.Ink
			end),
			Activated = function()
				hand.Commit()
				actions.Leave()
			end,
			hand.Events,
			create("UIScale")({ Scale = hand.Scale }),
			handLayers(hand),
			Components.Edge(Color.Boss),
			Text({
				Size = UDim2.fromScale(1, 1),
				FontFace = Font.Heavy,
				TextSize = 28,
				Text = "X",
				TextColor3 = eased(function()
					return if isHovered() then Color.Text else Color.Boss
				end),
			}),
		}),
		line({ Position = UDim2.new(0, 0, 1, -LINE), Size = UDim2.new(1, 0, 0, LINE) }),
	})
end

local function mapRow(state: Types.TLobbyState, actions: Types.TLobbyActions, index: number): TextButton
	local map = MapsCore.LIST[index]
	local hand = Hand.React("Operate", function()
		return not isLocked(state, map)
	end)
	local function isPicked(): boolean
		return state.PickMap() == index
	end
	local tint = difficultyColor(map.Difficulty)

	return Components.Button({
		LayoutOrder = index,
		Size = UDim2.new(1, 0, 0, MAP_ROW_HEIGHT),
		BackgroundColor3 = eased(function()
			return if isPicked() or hand.IsHovered() then Color.Surface else Color.Ink
		end),
		Activated = function()
			if isLocked(state, map) then return end
			hand.Commit()
			actions.PickMap(index)
		end,
		hand.Events,
		handLayers(hand),
		-- The picked row's accent bar.
		create("Frame")({
			Size = UDim2.new(0, 6, 1, 0),
			BorderSizePixel = 0,
			BackgroundColor3 = tint,
			Visible = isPicked,
		}),
		create("Frame")({
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 22, 0.5, 0),
			Size = UDim2.fromOffset(THUMB_SIZE, THUMB_SIZE),
			BorderSizePixel = 0,
			BackgroundColor3 = function()
				return if isLocked(state, map) then Color.Locked else tint
			end,
			Components.Edge(function()
				return if isLocked(state, map) then Color.Edge else tint:Lerp(Color.Text, 0.45)
			end),
			Text({
				Size = UDim2.fromScale(1, 1),
				FontFace = Font.Mono,
				TextSize = 24,
				Text = initials(map.DisplayName),
				TextColor3 = function()
					return if isLocked(state, map) then Color.Text else Color.Ink
				end,
			}),
		}),
		Text({
			Position = UDim2.fromOffset(98, 16),
			Size = UDim2.new(1, -110, 0, 26),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			FontFace = Font.Heavy,
			TextSize = 22,
			Text = string.upper(map.DisplayName),
		}),
		Text({
			Position = UDim2.fromOffset(98, 46),
			Size = UDim2.new(1, -110, 0, 18),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			FontFace = Font.Mono,
			TextSize = 13,
			TextColor3 = function()
				return if isLocked(state, map) then Color.BossEdge else Color.Muted
			end,
			Text = function()
				if isLocked(state, map) then return `LOCKED - {string.upper(MapsCore.RequirementText(map))}` end
				return `{string.upper(map.Difficulty)} / BEST WAVE {bestOf(state, map)}`
			end,
		}),
	})
end

local function mapList(state: Types.TLobbyState, actions: Types.TLobbyActions): Frame
	local rows = table.create(#MapsCore.LIST)
	for index in MapsCore.LIST do
		rows[index] = mapRow(state, actions, index)
	end

	return create("Frame")({
		Position = UDim2.fromOffset(0, HEADER_HEIGHT),
		Size = UDim2.fromOffset(LEFT_WIDTH, BODY_HEIGHT),
		BackgroundTransparency = 1,
		label("SELECT MAP", Color.Action, { Size = UDim2.new(1, 0, 0, 48) }),
		create("Frame")({
			Position = UDim2.fromOffset(0, 48),
			Size = UDim2.new(1, -LINE, 1, -48),
			BackgroundTransparency = 1,
			create("UIListLayout")({ SortOrder = Enum.SortOrder.LayoutOrder }),
			rows,
		}),
		line({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, LINE, 1, 0) }),
	})
end

local function infoBox(order: number, title: string, value: () -> string): Frame
	return create("Frame")({
		LayoutOrder = order,
		Size = UDim2.fromOffset(160, 64),
		BackgroundColor3 = Color.Ink,
		BorderSizePixel = 0,
		Components.Edge(),
		label(title, Color.Muted, { Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 18), TextSize = 13 }),
		Text({
			Position = UDim2.fromOffset(0, 28),
			Size = UDim2.new(1, 0, 0, 28),
			FontFace = Font.Heavy,
			TextSize = 22,
			Text = value,
		}),
	})
end

local function banner(state: Types.TLobbyState): Frame
	local tint = eased(function()
		return difficultyColor(pickedMap(state).Difficulty)
	end)

	return create("Frame")({
		Size = UDim2.new(1, 0, 0, BANNER_HEIGHT),
		BackgroundColor3 = Color.Surface,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		-- The difficulty's colour washing in from the left, where the name stands.
		create("Frame")({
			Size = UDim2.fromScale(1, 1),
			BorderSizePixel = 0,
			BackgroundColor3 = tint,
			create("UIGradient")({ Transparency = NumberSequence.new(0.55, 1) }),
		}),
		create("Frame")({
			Position = UDim2.fromOffset(28, 24),
			Size = UDim2.fromOffset(96, 30),
			BorderSizePixel = 0,
			BackgroundColor3 = tint,
			Text({
				Size = UDim2.fromScale(1, 1),
				FontFace = Font.Mono,
				TextSize = 16,
				TextColor3 = Color.Ink,
				Text = function()
					return string.upper(pickedMap(state).Difficulty)
				end,
			}),
		}),
		Text({
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 28, 1, -22),
			Size = UDim2.new(1, -240, 0, 64),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			FontFace = Font.Mono,
			TextSize = 56,
			Text = function()
				return string.upper(pickedMap(state).DisplayName)
			end,
			Components.Ink(56),
		}),
		create("Frame")({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -22, 0.5, 0),
			Size = UDim2.fromOffset(160, 140),
			BackgroundTransparency = 1,
			create("UIListLayout")({
				Padding = UDim.new(0, 12),
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Center,
			}),
			infoBox(1, "YOUR BEST", function()
				return `WAVE {bestOf(state, pickedMap(state))}`
			end),
			infoBox(2, "BOSS", function()
				return `EVERY {BOSS_EVERY}TH`
			end),
		}),
	})
end

local function sizeSection(state: Types.TLobbyState): Frame
	local tiles = table.create(PadsCore.MAX_PLAYERS)
	for count = 1, PadsCore.MAX_PLAYERS do
		tiles[count] = tile({
			Order = count,
			Size = UDim2.fromOffset(64, 56),
			Label = tostring(count),
			TextSize = 26,
			Color = SIZE_COLOR,
			IsPicked = function()
				return state.PickPlayers() == count
			end,
			Pick = function()
				state.PickPlayers(count)
			end,
		})
	end

	return create("Frame")({
		Position = UDim2.fromOffset(0, BANNER_HEIGHT),
		Size = UDim2.new(1, 0, 0, SECTION_HEIGHT),
		BackgroundTransparency = 1,
		line({ Size = UDim2.new(1, 0, 0, LINE) }),
		label("PARTY SIZE", SIZE_COLOR, { Position = UDim2.fromOffset(0, 12), Size = UDim2.new(1, 0, 0, 20) }),
		create("Frame")({
			Position = UDim2.fromOffset(0, 38),
			Size = UDim2.new(1, 0, 0, 56),
			BackgroundTransparency = 1,
			row(tiles, 12),
		}),
		-- Records are kept per party category (GDD 16), so say which one this run counts for.
		label("", Color.Muted, {
			Position = UDim2.fromOffset(0, 100),
			Size = UDim2.new(1, 0, 0, 16),
			TextSize = 13,
			Text = function()
				return if state.PickPlayers() == 1 then "SOLO RECORD" else "SQUAD RECORD"
			end,
		}),
	})
end

local function difficultyHalf(state: Types.TLobbyState, actions: Types.TLobbyActions): Frame
	local tiles = table.create(#MapsCore.DIFFICULTIES)
	for order, difficulty in MapsCore.DIFFICULTIES do
		local first: MapsCore.TMap? = nil
		for _, map in MapsCore.LIST do
			if map.Difficulty == difficulty then
				first = map
				break
			end
		end
		tiles[order] = tile({
			Order = order,
			Size = UDim2.fromOffset(136, 56),
			Label = string.upper(difficulty),
			TextSize = 20,
			Color = difficultyColor(difficulty),
			IsPicked = function()
				return state.PickDifficulty() == difficulty
			end,
			IsLocked = function()
				return first == nil or isLocked(state, first)
			end,
			Pick = function()
				actions.PickDifficulty(difficulty)
			end,
		})
	end

	return create("Frame")({
		Size = UDim2.fromScale(0.5, 1),
		BackgroundTransparency = 1,
		label("DIFFICULTY", Color.Action, { Position = UDim2.fromOffset(0, 12), Size = UDim2.new(1, 0, 0, 20) }),
		create("Frame")({
			Position = UDim2.fromOffset(0, 38),
			Size = UDim2.new(1, 0, 0, 56),
			BackgroundTransparency = 1,
			row(tiles, 10),
		}),
		label("", Color.Muted, {
			Position = UDim2.fromOffset(0, 100),
			Size = UDim2.new(1, 0, 0, 16),
			TextSize = 13,
			Text = function()
				for _, map in MapsCore.LIST do
					if isLocked(state, map) then
						return `{string.upper(map.Difficulty)}: {string.upper(MapsCore.RequirementText(map))}`
					end
				end
				return "EVERY DIFFICULTY OPEN"
			end,
		}),
	})
end

local function accessHalf(state: Types.TLobbyState): Frame
	return create("Frame")({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(0.5, 1),
		BackgroundTransparency = 1,
		line({ Size = UDim2.new(0, LINE, 1, 0) }),
		label("ACCESS", ACCESS_COLOR, { Position = UDim2.fromOffset(0, 12), Size = UDim2.new(1, 0, 0, 20) }),
		create("Frame")({
			Position = UDim2.fromOffset(0, 38),
			Size = UDim2.new(1, 0, 0, 56),
			BackgroundTransparency = 1,
			row({
				tile({
					Order = 1,
					Size = UDim2.fromOffset(136, 56),
					Label = "PUBLIC",
					TextSize = 20,
					Color = ACCESS_COLOR,
					IsPicked = function()
						return not state.PickFriendsOnly()
					end,
					Pick = function()
						state.PickFriendsOnly(false)
					end,
				}),
				tile({
					Order = 2,
					Size = UDim2.fromOffset(136, 56),
					Label = "FRIENDS",
					TextSize = 20,
					Color = ACCESS_COLOR,
					IsPicked = state.PickFriendsOnly,
					Pick = function()
						state.PickFriendsOnly(true)
					end,
				}),
			}, 10),
		}),
		label("", Color.Muted, {
			Position = UDim2.fromOffset(0, 100),
			Size = UDim2.new(1, 0, 0, 16),
			TextSize = 13,
			Text = function()
				return if state.PickFriendsOnly() then "ONLY YOUR FRIENDS CAN JOIN" else "ANYONE CAN JOIN"
			end,
		}),
	})
end

local function footer(state: Types.TLobbyState, actions: Types.TLobbyActions): Frame
	local function canCreate(): boolean
		return not isLocked(state, pickedMap(state))
	end
	local hand = Hand.React("Operate", canCreate)

	return create("Frame")({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, FOOTER_HEIGHT),
		BackgroundTransparency = 1,
		line({ Size = UDim2.new(1, 0, 0, LINE) }),
		label("CONFIG", Color.Muted, {
			Position = UDim2.fromOffset(28, 18),
			Size = UDim2.new(1, -CREATE_WIDTH - 56, 0, 18),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 14,
		}),
		label("", Color.Text, {
			Position = UDim2.fromOffset(28, 42),
			Size = UDim2.new(1, -CREATE_WIDTH - 56, 0, 26),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextSize = 20,
			Text = function()
				local map = pickedMap(state)
				local players = state.PickPlayers()
				local party = if players == 1 then "SOLO" else `SQUAD OF {players}`
				local access = if state.PickFriendsOnly() then "FRIENDS" else "PUBLIC"
				return `{string.upper(map.DisplayName)} / {string.upper(map.Difficulty)} / {party} / {access}`
			end,
		}),
		Components.Button({
			Name = "Create",
			-- Placed by its middle, so it grows from there.
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -CREATE_WIDTH / 2, 1, -(FOOTER_HEIGHT - LINE) / 2),
			Size = UDim2.new(0, CREATE_WIDTH, 1, -LINE),
			BackgroundColor3 = eased(function()
				if not canCreate() then return Color.Locked end
				return if hand.IsHovered() then Color.ActionEdge else Color.Action
			end),
			Activated = function()
				hand.Commit()
				actions.StartParty()
			end,
			hand.Events,
			create("UIScale")({ Scale = hand.Scale }),
			handLayers(hand),
			Text({
				Size = UDim2.fromScale(1, 1),
				FontFace = Font.Mono,
				TextSize = 36,
				TextColor3 = function()
					return if canCreate() then Color.Ink else Color.Text
				end,
				Text = "CREATE ->",
			}),
		}),
	})
end

local Menu = {}

function Menu.Build(state: Types.TLobbyState, actions: Types.TLobbyActions): CanvasGroup
	local shown = spring(function()
		return if state.IsChoosing() then 1 else 0
	end, FADE_PERIOD, 1)

	return create("CanvasGroup")({
		Name = "PartyMenu",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -BOTTOM),
		Size = UDim2.fromOffset(WIDTH, HEIGHT),
		BackgroundColor3 = Color.Ink,
		BorderSizePixel = 0,
		GroupTransparency = function()
			return 1 - shown()
		end,
		Visible = function()
			return shown() > 0.01
		end,
		create("UIScale")({
			Scale = function()
				return 0.94 + 0.06 * shown()
			end,
		}),
		-- The panel's edge, hung on a frame inset by its width: a CanvasGroup clips a stroke drawn outside its bounds.
		create("Frame")({
			Position = UDim2.fromOffset(LINE, LINE),
			Size = UDim2.new(1, -2 * LINE, 1, -2 * LINE),
			BackgroundTransparency = 1,
			ZIndex = 2,
			Components.Edge(),
		}),
		header(actions),
		mapList(state, actions),
		create("Frame")({
			Position = UDim2.fromOffset(LEFT_WIDTH, HEADER_HEIGHT),
			Size = UDim2.fromOffset(RIGHT_WIDTH, BODY_HEIGHT),
			BackgroundTransparency = 1,
			banner(state),
			sizeSection(state),
			create("Frame")({
				Position = UDim2.fromOffset(0, BANNER_HEIGHT + SECTION_HEIGHT),
				Size = UDim2.new(1, 0, 0, SECTION_HEIGHT),
				BackgroundTransparency = 1,
				line({ Size = UDim2.new(1, 0, 0, LINE) }),
				difficultyHalf(state, actions),
				accessHalf(state),
			}),
		}),
		footer(state, actions),
	})
end

return Menu
