--!nonstrict
-- The party screen's choices beside the map: party size (four tiles, and a head under each that lights for every
-- player the party holds), difficulty (each in its own colour) and access. Each row is his dark plaques with one glossy
-- slab gliding under the picked one, as the quests screen's tabs; the picked word punches as the slab arrives.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local MapsCore = require(ReplicatedStorage.GlobalShared.Core.MapsCore)
local PadsCore = require(ReplicatedStorage.Shared.Core.PadsCore)
local Parts = require(script.Parent.Parts)
local Types = require(script.Parent.Parent.Types)
local EIcons = require(ReplicatedStorage.Types.Enums.EIcons)

local create = vide.create
local derive = vide.derive
local spring = vide.spring
local Palette = Theme.Palette
local Font = Theme.Font
local Label = Parts.Label

-- Px at 1080 from the panel's top left.
local Layout = table.freeze({
	LEFT = 761,
	WIDTH = 508,
	-- 18 between two tiles (his 14): a tile's brackets reach 11 px out under a press, and at his they crossed.
	GAP = 18,
	SIZE_HEADER = 118,
	SIZE_TILES = 156,
	SIZE_TILE_HEIGHT = 112,
	SIZE_TEXT = 54,
	HEADS = 292,
	HEAD_GLYPH = 30,
	DIFFICULTY_HEADER = 324,
	DIFFICULTY_TILES = 360,
	DIFFICULTY_GAP = 18,
	DIFFICULTY_TEXT = 17,
	ACCESS_HEADER = 446,
	ACCESS_TILES = 482,
	ROW_TILE_HEIGHT = 62,
	ROW_TEXT = 22,
	ACCESS_NOTE = 560,
	ACCESS_NOTE_TEXT = 16,
	-- PUBLIC and FRIENDS stand 24 apart: tiles this wide reach 17 px out under a press.
	ACCESS_GAP = 24,
})

local Gesture = table.freeze({
	-- The slab gliding under the picked tile, and the word warming to white as it arrives.
	GLIDE_PERIOD = 0.28,
	GLIDE_DAMPING = 0.85,
	SIZE_DELAY = 0.12,
	DIFFICULTY_DELAY = 0.22,
	ACCESS_DELAY = 0.28,
	STAGGER = 0.04,
	PUNCH_PERIOD = 0.3,
	PUNCH_DAMPING = 0.5,
	PUNCH = 0.2,
	-- The heads light one after another, outward from the last one already lit, and go out the other way.
	HEAD = 0.22,
	HEAD_STAGGER = 0.05,
	HEAD_DIM = 0.55,
	-- A note slides up into place as its choice changes.
	NOTE = 0.3,
	NOTE_RISE = 8,
})

local Picks = {}

-- One choice on a plaque, and its word as a piece of its own over the glider that slides between them; and the hand's
-- scale on it, which the glider takes while it lies on this choice.
local function choice(props: {
	Name: string,
	Center: Vector2,
	Size: Vector2,
	Word: string,
	TextSize: number,
	IsPicked: () -> boolean,
	Pick: () -> (),
	Dealt: () -> number,
}): ({ Instance }, () -> number)
	local hand = Hand.React("Take", function(): boolean
		return not props.IsPicked()
	end)
	local picked = spring(function(): number
		return if props.IsPicked() then 1 else 0
	end, Gesture.GLIDE_PERIOD, 1)
	local punch, strikePunch = Hand.Kick(Gesture.PUNCH_PERIOD, Gesture.PUNCH_DAMPING)
	Parts.OnChange(props.IsPicked, function(isPicked: boolean)
		if isPicked then strikePunch(Gesture.PUNCH) end
	end)
	local position = UDim2.fromOffset(props.Center.X, props.Center.Y)
	local size = UDim2.fromOffset(props.Size.X, props.Size.Y)

	local word = Label({
		Name = `{props.Name}Word`,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = size,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextSize = props.TextSize,
		TextColor3 = function()
			return Palette.Lavender:Lerp(Palette.White, picked())
		end,
		ZIndex = 6,
		Text = props.Word,
		create("UIScale")({
			Scale = function()
				return props.Dealt() * hand.Scale() * (1 + punch())
			end,
		}),
	})

	local button = Components.Button({
		Name = props.Name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		ZIndex = 4,
		Activated = function()
			if props.IsPicked() then return end
			hand.Commit()
			props.Pick()
		end,
		hand.Events,
		create("UIScale")({
			Scale = function()
				return props.Dealt() * hand.Scale()
			end,
		}),
		Parts.Plaque({
			Name = "Plaque",
			Size = UDim2.fromScale(1, 1),
			ZIndex = 4,
			Components.Brackets(hand.Rise, function()
				return 0.6 - 0.3 * hand.Light()
			end, 14, props.IsPicked),
			Hand.WashLayer(hand, 5, 2),
		}),
	})

	return { button, word }, hand.Scale
end

-- The glossy slab under the picked choice of a row, gliding from one to the next. `Picked` is the picked choice's
-- place in the row; `Centers` and `Scales` are each choice's middle (px across the panel) and its hand's scale, which
-- the slab grows and presses with (or the plaque under it shows round its edge); `KindAt` is its slab's kind for where
-- it is now.
local function glider(props: {
	Name: string,
	KindAt: (x: number) -> string,
	Picked: () -> number,
	Centers: { number },
	Scales: { () -> number },
	Y: number,
	Size: Vector2,
	Dealt: () -> number,
})
	local x = spring(function(): number
		return props.Centers[props.Picked()]
	end, Gesture.GLIDE_PERIOD, Gesture.GLIDE_DAMPING)
	local kind = derive(function(): string
		return props.KindAt(x())
	end)
	-- No brackets of its own: the picked tile's, under it, are the ones that answer the hand.
	return Components.Slab({
		Kind = kind,
		Marks = true,
	}, {
		Name = props.Name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			return UDim2.fromOffset(math.round(x()), props.Y)
		end,
		Size = UDim2.fromOffset(props.Size.X, props.Size.Y),
		ZIndex = 5,
		create("UIScale")({
			Scale = function()
				return props.Dealt() * props.Scales[props.Picked()]()
			end,
		}),
	})
end

-- The middle of choice `index` of `count` across the column, `gap` px apart.
local function columnX(index: number, count: number, gap: number?): number
	local between = gap or Layout.GAP
	local width = (Layout.WIDTH - between * (count - 1)) / count
	return Layout.LEFT + (width + between) * (index - 1) + width / 2
end

-- A head under size tile `slot`: lit while the party holds that many, lighting outward from the last one already lit
-- and going out the other way.
local function head(state: Types.TLobbyState, slot: number, dealt: () -> number): ImageLabel
	-- How lit it is, and whether it is lighting rather than going out.
	local lit = derive(function(): Vector2
		local from, to = state.PlayersFrom(), state.PickPlayers()
		local wasLit, isLit = slot <= from, slot <= to
		if wasLit == isLit then return Vector2.new(if isLit then 1 else 0, 0) end
		local order = if isLit then slot - from else from - slot + 1
		local t = Motion.Progress(state.Now(), state.PlayersAt(), Gesture.HEAD, Gesture.HEAD_STAGGER * (order - 1))
		return Vector2.new(if isLit then t else 1 - t, if isLit then 1 else 0)
	end)

	return Components.Picture(EIcons.Player, {
		Name = `Head{slot}`,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(columnX(slot, PadsCore.MAX_PLAYERS), Layout.HEADS),
		Size = Components.PictureBox(Layout.HEAD_GLYPH),
		ImageColor3 = function()
			return Parts.PLAQUE_EDGE:Lerp(Palette.White, lit().X)
		end,
		ImageTransparency = function()
			return Gesture.HEAD_DIM * (1 - lit().X)
		end,
		ZIndex = 4,
		create("UIScale")({
			Scale = function()
				local reading = lit()
				-- Lighting, it pops past its size and settles; going out, it only shrinks back.
				local grow = if reading.Y > 0 then Motion.OutBack(reading.X) else reading.X
				return dealt() * (0.8 + 0.2 * grow)
			end,
		}),
	})
end

local function sizeRow(state: Types.TLobbyState, actions: Types.TLobbyActions, elapsed: () -> number): { any }
	local count = PadsCore.MAX_PLAYERS
	local tile = Vector2.new((Layout.WIDTH - Layout.GAP * (count - 1)) / count, Layout.SIZE_TILE_HEIGHT)
	local y = Layout.SIZE_TILES + Layout.SIZE_TILE_HEIGHT / 2
	local pieces = {}
	local centers = table.create(count)
	local scales = table.create(count)
	for slot = 1, count do
		local dealt = Parts.Dealt(state, elapsed, Gesture.SIZE_DELAY + Gesture.STAGGER * (slot - 1))
		centers[slot] = columnX(slot, count)
		pieces[#pieces + 1], scales[slot] = choice({
			Name = `Size{slot}`,
			Center = Vector2.new(centers[slot], y),
			Size = tile,
			Word = tostring(slot),
			TextSize = Layout.SIZE_TEXT,
			IsPicked = function()
				return state.PickPlayers() == slot
			end,
			Pick = function()
				actions.PickPlayers(slot)
			end,
			Dealt = dealt,
		})
		pieces[#pieces + 1] = head(state, slot, dealt)
	end

	pieces[#pieces + 1] = glider({
		Name = "SizeGlider",
		KindAt = function()
			return "Pink"
		end,
		Picked = state.PickPlayers,
		Centers = centers,
		Scales = scales,
		Y = y,
		Size = tile,
		Dealt = Parts.Dealt(state, elapsed, Gesture.SIZE_DELAY),
	})
	pieces[#pieces + 1] = Parts.Header({
		At = Vector2.new(Layout.LEFT, Layout.SIZE_HEADER),
		Width = Layout.WIDTH,
		Picture = EIcons.Player,
		Word = "PARTY SIZE",
	})

	return pieces
end

local function difficultyRow(state: Types.TLobbyState, actions: Types.TLobbyActions, elapsed: () -> number): { any }
	local count = #MapsCore.DIFFICULTIES
	local gap = Layout.DIFFICULTY_GAP
	local width = (Layout.WIDTH - gap * (count - 1)) / count
	local y = Layout.DIFFICULTY_TILES + Layout.ROW_TILE_HEIGHT / 2
	local pieces = {}
	local centers = table.create(count)
	local scales = table.create(count)
	for order, difficulty in MapsCore.DIFFICULTIES do
		centers[order] = columnX(order, count, gap)
		pieces[#pieces + 1], scales[order] = choice({
			Name = difficulty,
			Center = Vector2.new(centers[order], y),
			Size = Vector2.new(width, Layout.ROW_TILE_HEIGHT),
			Word = string.upper(difficulty),
			TextSize = Layout.DIFFICULTY_TEXT,
			IsPicked = function()
				return state.PickDifficulty() == difficulty
			end,
			Pick = function()
				actions.PickDifficulty(difficulty)
			end,
			Dealt = Parts.Dealt(state, elapsed, Gesture.DIFFICULTY_DELAY + Gesture.STAGGER * (order - 1)),
		})
	end

	-- The slab wears the colour of the tile it is passing, so a jump to a harder one heats up on the way there.
	pieces[#pieces + 1] = glider({
		Name = "DifficultyGlider",
		KindAt = function(x: number): string
			local slot = math.clamp(math.round((x - Layout.LEFT - width / 2) / (width + gap)) + 1, 1, count)
			return Parts.DIFFICULTY_SLABS[MapsCore.DIFFICULTIES[slot]] or "Go"
		end,
		Picked = function(): number
			return table.find(MapsCore.DIFFICULTIES, state.PickDifficulty()) or 1
		end,
		Centers = centers,
		Scales = scales,
		Y = y,
		Size = Vector2.new(width, Layout.ROW_TILE_HEIGHT),
		Dealt = Parts.Dealt(state, elapsed, Gesture.DIFFICULTY_DELAY),
	})
	pieces[#pieces + 1] = Parts.Header({
		At = Vector2.new(Layout.LEFT, Layout.DIFFICULTY_HEADER),
		Width = Layout.WIDTH,
		Picture = EIcons.Skull,
		Word = "DIFFICULTY",
	})

	return pieces
end

local function accessRow(state: Types.TLobbyState, actions: Types.TLobbyActions, elapsed: () -> number): { any }
	local width = (Layout.WIDTH - Layout.ACCESS_GAP) / 2
	local y = Layout.ACCESS_TILES + Layout.ROW_TILE_HEIGHT / 2
	local size = Vector2.new(width, Layout.ROW_TILE_HEIGHT)
	local noted = Parts.Since(state, state.AccessAt, Gesture.NOTE)
	local pieces = {}
	local centers = table.create(2)
	local scales = table.create(2)
	for order, isFriendsOnly in { false, true } do
		centers[order] = columnX(order, 2, Layout.ACCESS_GAP)
		pieces[#pieces + 1], scales[order] = choice({
			Name = if isFriendsOnly then "Friends" else "Public",
			Center = Vector2.new(centers[order], y),
			Size = size,
			Word = if isFriendsOnly then "FRIENDS" else "PUBLIC",
			TextSize = Layout.ROW_TEXT,
			IsPicked = function()
				return state.PickFriendsOnly() == isFriendsOnly
			end,
			Pick = function()
				actions.PickFriendsOnly(isFriendsOnly)
			end,
			Dealt = Parts.Dealt(state, elapsed, Gesture.ACCESS_DELAY + Gesture.STAGGER * (order - 1)),
		})
	end

	pieces[#pieces + 1] = glider({
		Name = "AccessGlider",
		KindAt = function()
			return "Violet"
		end,
		Picked = function(): number
			return if state.PickFriendsOnly() then 2 else 1
		end,
		Centers = centers,
		Scales = scales,
		Y = y,
		Size = size,
		Dealt = Parts.Dealt(state, elapsed, Gesture.ACCESS_DELAY),
	})
	pieces[#pieces + 1] = Parts.Header({
		At = Vector2.new(Layout.LEFT, Layout.ACCESS_HEADER),
		Width = Layout.WIDTH,
		Picture = EIcons.Friends,
		Word = "ACCESS",
	})
	pieces[#pieces + 1] = Label({
		Name = "AccessNote",
		Position = function()
			return UDim2.fromOffset(
				Layout.LEFT,
				Layout.ACCESS_NOTE + math.round(Gesture.NOTE_RISE * (1 - Motion.Decelerate(noted())))
			)
		end,
		Size = UDim2.fromOffset(Layout.WIDTH, Layout.ACCESS_NOTE_TEXT),
		TextXAlignment = Enum.TextXAlignment.Center,
		FontFace = Font.DisplayBold,
		TextSize = Layout.ACCESS_NOTE_TEXT,
		TextColor3 = Palette.Lavender,
		TextTransparency = function()
			return 1 - Motion.Out(noted())
		end,
		Text = function()
			return if state.PickFriendsOnly() then "ONLY YOUR FRIENDS CAN JOIN" else "ANYONE CAN JOIN"
		end,
	})

	return pieces
end

function Picks.Build(state: Types.TLobbyState, actions: Types.TLobbyActions, elapsed: () -> number): { any }
	return {
		sizeRow(state, actions, elapsed),
		difficultyRow(state, actions, elapsed),
		accessRow(state, actions, elapsed),
	}
end

return Picks
