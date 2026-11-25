--!nonstrict
-- What the party's pieces share (the screen, the queue and the board over a pad): the curves of an open and shut, his
-- label and dark plaque, a section's header, a map's colour and picture, a difficulty's tag, the countdown's bar, and
-- the reactions every readout uses (a punch on a change, a group that fades only while it moves).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local MapsCore = require(ReplicatedStorage.GlobalShared.Core.MapsCore)
local PadsCore = require(ReplicatedStorage.Shared.Core.PadsCore)
local padlock = require(script.Parent.Parent.Parent.Parent.Utils.padlock)
local Types = require(script.Parent.Parent.Types)

local create = vide.create
local derive = vide.derive
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress

local Parts = {}

Parts.Timing = table.freeze({
	-- The panel decelerates up into place and its pieces are dealt onto it; it sinks on the way out, or, sent off by
	-- CREATE, lifts away the faster.
	FADE = 0.27,
	OPEN = 0.34,
	RISE = 26,
	CLOSE = 0.2,
	SINK = 14,
	LAUNCH = 0.3,
	LAUNCH_RISE = 46,
	-- A piece grows onto its place over this long once its turn in the deal comes.
	DEAL = 0.36,
	-- Every gesture of an open is over by now.
	SETTLED = 1.6,
	-- A countdown's bar drains toward each second as it is told.
	BAR_PERIOD = 0.9,
})

-- A map's unlock on the party screen, in seconds from its start (state.UnlockAt): its requirements tick off one after
-- another, the padlock strains twice, then opens as the index's do (padlock, from LOCK); as the shackle clicks the veil
-- lifts off the picture with a flash and a ring and the map takes its colour, the path's track runs on to it and its
-- point lights, and NEW slaps onto the corner. The host is held on it (no other map, no EXIT, no CREATE) until HOLD.
Parts.Unlock = table.freeze({
	ROWS = 0,
	ROW_STAGGER = 0.16,
	ROW_STAMP = 0.3,
	STRAIN_1 = 0.42,
	STRAIN_2 = 0.68,
	STRAIN = 0.24,
	STRAIN_DEGREES_1 = 5,
	STRAIN_DEGREES_2 = 9,
	LOCK = 0.95,
	CLICK = 0.95 + padlock.CLICK_SECONDS,
	-- The picture comes out from under the veil over OPEN, taking its colour, and throws its flash and ring.
	RELEASE = 0.95 + padlock.CLICK_SECONDS + 0.04,
	OPEN = 0.4,
	FLASH = 0.45,
	FLASH_PEAK = 0.7,
	RING = 0.6,
	RING_REACH = 40,
	POP = 0.06,
	-- The track runs on to the map's point, which then lights with a ring of its own.
	TRACK = 1.3,
	TRACK_RUN = 0.38,
	NODE_RING = 0.5,
	RIBBON = 1.5,
	-- The '?' after it turns into the next map, locked, and a new '?' is dealt in past it.
	REVEAL = 1.75,
	HOLD = 1.85,
	SECONDS = 2.4,
})

-- His rule's lavender, sampled off the art.
Parts.RULE = Color3.fromRGB(140, 111, 210)
Parts.RULE_TRANSPARENCY = 0.55
-- His dark plaque (the tab not on show): a dim pink edge round an ink face.
Parts.PLAQUE_EDGE = Color3.fromRGB(116, 26, 72)
Parts.PLAQUE_FACE = Color3.fromRGB(10, 7, 21)
-- A locked map's grey, and its name's, as white under the veil's dark.
Parts.LOCKED = Color3.fromRGB(100, 88, 116)
Parts.SHUT_NAME = Color3.fromRGB(104, 98, 116)
-- A countdown bar's empty track, his bar track's dark lavender.
Parts.BAR_TRACK = Color3.fromRGB(58, 50, 86)
-- How much of a map's colour is left in its window's dark behind the picture.
local PICTURE_BACK = 0.18

-- Each map's colour, so the showcase, its card and the read-back all speak in it.
local ACCENTS = table.freeze({
	PirateCove = Color3.fromRGB(89, 191, 255),
	GrassLands = Palette.Green,
})
-- Each map's picture (Assets/ui/party/maps); a map without one shows its initials on its colour. Still the old lobby's
-- ids, not uploaded by this game's group yet.
Parts.PICTURES = table.freeze({
	PirateCove = "rbxassetid://90290960375821",
	GrassLands = "rbxassetid://101532776698527",
} :: { [string]: string })
-- A party by its size, as the read-back and the pad's board name it.
Parts.PARTY_NAMES = table.freeze({ "SOLO", "DUO", "TRIO", "QUAD" })
-- Each difficulty's slab and colour, easiest first.
Parts.DIFFICULTY_SLABS = table.freeze({ Normal = "Go", Hard = "Gold", Nightmare = "Violet", Hell = "Red" })
Parts.DIFFICULTY_COLORS = table.freeze({
	Normal = Palette.Green,
	Hard = Palette.Gold,
	Nightmare = Color3.fromRGB(176, 132, 255),
	Hell = Color3.fromRGB(255, 84, 96),
})

function Parts.AccentOf(map: MapsCore.TMap): Color3
	return ACCENTS[map.Name] or Palette.Steel
end

function Parts.PickedMap(state: Types.TLobbyState): MapsCore.TMap
	return MapsCore.LIST[state.PickMap()] or MapsCore.LIST[1]
end

function Parts.IsLocked(state: Types.TLobbyState, map: MapsCore.TMap): boolean
	return not MapsCore.IsUnlockedBy(map, state.Level(), state.BossKills())
end

-- Seconds into map `index`'s unlock (negative before it starts), or nil when it has none running. Reads the clock only
-- while one is due or running, so a map unlocked long ago works nothing out per frame.
function Parts.Unlocking(state: Types.TLobbyState, index: number): number?
	if state.UnlockMap() ~= index then return nil end
	local at = state.UnlockAt()
	if os.clock() - at > Parts.Unlock.SECONDS then return nil end
	return state.Now() - at
end

-- How open map `index` looks, 0 (under its padlock) to 1: open once its unlock has played, opening as it plays.
function Parts.Opened(state: Types.TLobbyState, index: number): number
	local map = MapsCore.LIST[index]
	if not map or Parts.IsLocked(state, map) then return 0 end
	if not MapsCore.HasRequirement(map) then return 1 end
	local unlocking = Parts.Unlocking(state, index)
	if unlocking then return Progress(unlocking, 0, Parts.Unlock.OPEN, Parts.Unlock.RELEASE) end
	return if state.MapsShown()[map.Name] then 1 else 0
end

-- Whether map `index` is reached on the path: open, and its unlock (if one is playing) past its REVEAL.
local function isReached(state: Types.TLobbyState, index: number): boolean
	local unlocking = Parts.Unlocking(state, index)
	if unlocking then return unlocking >= Parts.Unlock.REVEAL end
	return Parts.Opened(state, index) >= 1
end

-- How many points the path shows: every map reached, the next one (locked), and a '?' past them, which is there even
-- when no map is left after them: what comes next is never shown before the player gets that far.
function Parts.PathCount(state: Types.TLobbyState): number
	local reached = 0
	for index in MapsCore.LIST do
		if not isReached(state, index) then break end
		reached = index
	end

	return math.min(reached + 1, #MapsCore.LIST) + 1
end

-- Map `index` as a path of `count` points (PathCount) shows it: nil for the '?' at its end (and past it).
function Parts.ShownMap(index: number, count: number): MapsCore.TMap?
	return if index < count then MapsCore.LIST[index] else nil
end

-- Whether an unlock holds the host on its map: no other map, no EXIT, no CREATE.
function Parts.IsHeld(state: Types.TLobbyState): boolean
	local unlocking = Parts.Unlocking(state, state.UnlockMap())
	return unlocking ~= nil and unlocking < Parts.Unlock.HOLD
end

function Parts.BestOf(state: Types.TLobbyState, map: MapsCore.TMap): number
	return state.BestByMap()[map.Name] or 0
end

-- The map's initials, for its picture until it has one.
function Parts.Initials(name: string): string
	local letters = {}
	for word in string.gmatch(name, "%a+") do
		letters[#letters + 1] = string.sub(word, 1, 1)
	end

	return string.upper(table.concat(letters, "", 1, math.min(#letters, 2)))
end

function Parts.Label(props: { [any]: any }): TextLabel
	return create("TextLabel")({
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		FontFace = Font.Display,
		TextColor3 = Palette.White,
		ZIndex = 4,
		props,
	})
end

-- His dark plaque, `props` sized to his drawn rect.
function Parts.Plaque(props: { [any]: any }): Frame
	return create("Frame")({
		BackgroundColor3 = Parts.PLAQUE_EDGE,
		BorderSizePixel = 0,
		create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
		create("UIGradient")({
			Rotation = 90,
			Color = ColorSequence.new(Palette.White, Color3.new(0.8, 0.8, 0.8)),
		}),
		create("Frame")({
			Name = "Face",
			Position = UDim2.fromOffset(2, 2),
			Size = UDim2.new(1, -4, 1, -4),
			BackgroundColor3 = Parts.PLAQUE_FACE,
			BorderSizePixel = 0,
			create("UICorner")({ CornerRadius = UDim.new(0, 1) }),
		}),
		props,
	})
end

-- A section's header, as the classes screen's panels head theirs: the picture and the word.
function Parts.Header(props: { At: Vector2, Width: number, Picture: string, Word: string }): Frame
	return create("Frame")({
		Name = props.Word,
		Position = UDim2.fromOffset(props.At.X, props.At.Y),
		Size = UDim2.fromOffset(props.Width, 24),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Components.Picture(props.Picture, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(11, 12),
			Size = Components.PictureBox(22),
			ZIndex = 4,
		}),
		Parts.Label({
			Position = UDim2.fromOffset(34, 0),
			Size = UDim2.fromOffset(props.Width - 34, 24),
			TextSize = 24,
			Text = props.Word,
		}),
	})
end

-- A map's picture filling its parent, its initials big and faint on its colour while it has none, or the locked grey
-- alone for the path's '?' (a nil map). `initialsScale` is how big the letters are against 100 px (TextSize stops at
-- 100, so they are drawn at that and scaled up).
function Parts.Picture(map: () -> MapsCore.TMap?, initialsScale: number, props: { [any]: any }): Frame
	local shot = derive(function(): string?
		local shown = map()
		return if shown then Parts.PICTURES[shown.Name] else nil
	end)
	local accent = derive(function(): Color3
		local shown = map()
		return if shown then Parts.AccentOf(shown) else Parts.LOCKED
	end)

	return create("Frame")({
		Name = "Picture",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = function()
			return accent():Lerp(Color3.new(), 1 - PICTURE_BACK)
		end,
		BorderSizePixel = 0,
		ZIndex = 4,
		create("ImageLabel")({
			Name = "Shot",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ScaleType = Enum.ScaleType.Crop,
			Image = function()
				return shot() or ""
			end,
			Visible = function()
				return shot() ~= nil
			end,
			ZIndex = 4,
		}),
		Parts.Label({
			Name = "Initials",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.42),
			Size = UDim2.fromOffset(300, 100),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextSize = 100,
			TextColor3 = accent,
			TextTransparency = 0.78,
			Visible = function()
				return shot() == nil and map() ~= nil
			end,
			Text = function()
				local shown = map()
				return if shown then Parts.Initials(shown.DisplayName) else ""
			end,
			ZIndex = 4,
			create("UIScale")({ Scale = initialsScale }),
		}),
		props,
	})
end

-- The dark rising from the bottom of a picture that its name stands on.
function Parts.Shade(): Frame
	return create("Frame")({
		Name = "Shade",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(),
		BorderSizePixel = 0,
		ZIndex = 5,
		create("UIGradient")({
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.45, 1),
				NumberSequenceKeypoint.new(1, 0.2),
			}),
		}),
	})
end

-- A difficulty's name on its own slab, `props` placing it.
function Parts.DifficultyTag(difficulty: () -> string, textSize: number, props: { [any]: any }): Frame
	return Components.Slab({
		Kind = function()
			return Parts.DIFFICULTY_SLABS[difficulty()] or "Go"
		end,
	}, {
		Name = "Difficulty",
		ZIndex = 6,
		Parts.Label({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextSize = textSize,
			ZIndex = 8,
			Text = function()
				return string.upper(difficulty())
			end,
		}),
		props,
	})
end

-- How much of a pad's wait is left, 0 to 1, of the full wait or of the short one once it is full, draining toward
-- each second as it is told; nothing once the party is going.
function Parts.CountdownShare(seconds: () -> number, isFull: () -> boolean, isGoing: () -> boolean): () -> number
	return Hand.Spring(function(): number
		if isGoing() then return 0 end
		local total = if isFull() then PadsCore.FULL_COUNTDOWN_SECONDS else PadsCore.COUNTDOWN_SECONDS
		return math.clamp(math.max(seconds(), 0) / total, 0, 1)
	end, Parts.Timing.BAR_PERIOD)
end

-- A countdown's bar: `share` of `size` filled in `color` over his dark track, `props` placing it.
function Parts.CountdownBar(share: () -> number, size: Vector2, color: any, props: { [any]: any }): Frame
	return create("Frame")({
		Name = "Track",
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = Parts.BAR_TRACK,
		BorderSizePixel = 0,
		ZIndex = 4,
		create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
		create("Frame")({
			Name = "Fill",
			Size = function()
				return UDim2.fromOffset(math.round(size.X * share()), size.Y)
			end,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = 5,
			create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
		}),
		props,
	})
end

-- Runs `react(current, last)` on every change of `value` after its first reading: a punch, a flash, a tick.
function Parts.OnChange<T>(value: () -> T, react: (current: T, last: T) -> ())
	local isRead = false
	local last: T
	vide.effect(function()
		local current = value()
		vide.untrack(function()
			if isRead and current ~= last then react(current, last) end
			isRead = true
			last = current
		end)
	end)
end

-- Seconds since the screen opened or shut, held once every gesture is over, so the clock ticking for a later gesture
-- works none of the open out again.
function Parts.Elapsed(state: Types.TLobbyState): () -> number
	return derive(function(): number
		return math.min(state.Now() - state.ChoosingAt(), Parts.Timing.SETTLED)
	end)
end

-- How far a piece has grown onto its place, 0 to 1: decelerating in after `delay` as the screen opens, held while it
-- shuts so it rides out with its panel.
function Parts.Dealt(state: Types.TLobbyState, elapsed: () -> number, delay: number): () -> number
	return derive(function(): number
		if not state.IsChoosing() then return 1 end
		return Motion.Decelerate(Progress(elapsed(), delay, Parts.Timing.DEAL))
	end)
end

-- Material's standard curve, cubic-bezier(0.4, 0, 0.2, 1): what a thing that changes size in place eases on. Solved
-- for x by Newton's method, then read off as y.
function Parts.Standard(t: number): number
	if t <= 0 then return 0 end
	if t >= 1 then return 1 end
	local u = t
	for _ = 1, 6 do
		local x = 3 * (1 - u) * (1 - u) * u * 0.4 + 3 * (1 - u) * u * u * 0.2 + u * u * u
		local slope = 3 * (1 - u) * (1 - u) * 0.4 + 6 * (1 - u) * u * (0.2 - 0.4) + 3 * u * u * (1 - 0.2)
		if slope == 0 then break end
		u = math.clamp(u - (x - t) / slope, 0, 1)
	end

	return 3 * (1 - u) * u * u + u * u * u
end

-- 0 to 1 over `seconds` from the stamp `at()` (and `delay` after it), read off the clock only while it runs.
function Parts.Since(state: Types.TLobbyState, at: () -> number, seconds: number, delay: number?): () -> number
	return derive(function(): number
		return Progress(state.Now(), at(), seconds, delay)
	end)
end

return Parts
