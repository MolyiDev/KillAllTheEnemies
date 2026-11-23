-- The quests screen (UIMatt.md, Quests - Daily / Weekly): the daily and weekly boards, and claiming a quest or a whole
-- board (QuestsService decides; this asks and shows). The lobby's QUESTS card opens it. While it is up the world
-- behind is blurred and heard under water.
--
-- A claim is shown in the order it is paid: the card winds up while the server is asked, strikes on the answer, and
-- its Gems burst out of the card's gem into the HUD's Gems pill (GemPayout, one a card, so a CLAIM ALL's cards throw
-- theirs one after another), which holds what is still in the air (HeldGems) and takes each slice as it lands.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local vide = require(ReplicatedStorage.Packages.vide)
local NetworkMeta = require(StarterPlayer.StarterPlayerScripts.GlobalClient.NetworkMeta)
local GemPayout = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.GemPayout)
-- Through PlayerScripts, the copy that runs: requiring the StarterPlayer one would load a second controller.
local BlurController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.BlurController)
local QuestsCore = require(ReplicatedStorage.GlobalShared.Core.QuestsCore)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local Card = require(script.Card)
local Parts = require(script.Parts)
local Screen = require(script.Screen)
local Types = require(script.Types)
local NetworkMetaTypes = require(ReplicatedStorage.Types.NetworkMetaTypes)

local ServerNetworkQuests = NetworkMeta.Server.Quests
local ClientNetworkQuests = NetworkMeta.Client.Quests
local LocalPlayer = Players.LocalPlayer
local source = vide.source
local create = vide.create

type TWireBoard = NetworkMetaTypes.Server_Quests_QuestBoard
type TBurst = { At: number, Board: number, Slot: number, Gems: number, IsFirst: boolean }

local Tune = table.freeze({
	-- The screen is his 1920 x 1080, fitted inside the viewport whole.
	DESIGN = Vector2.new(1920, 1080),
	-- Above the lobby's HUD, under the settings screen.
	DISPLAY_ORDER = 5,
	-- It is drawn this long after it is shut, for its way out.
	LEAVE_SECONDS = 0.45,
	-- How long the clock keeps ticking after a stamp: the longest gesture is shorter.
	MOTION_SECONDS = 2.4,
	-- A CLAIM ALL's cards strike one after another, top to bottom, this far apart.
	CASCADE = 0.11,
	-- Landing ticks closer together than this are one tick: five cards' Gems land over each other.
	TICK_GAP = 0.035,
})

-- A board's strike: its first card's sound, by board.
local STRIKE_SOUNDS = table.freeze({ "PickRare", "PickEpic" })

local QuestsController = {}

local state: Types.TQuestsState = {
	Scale = source(1),
	Now = source(os.clock()),
	Pulse = source(os.clock()),
	IsOpen = source(false),
	ToggledAt = source(-math.huge),
	OpenedAt = source(-math.huge),
	Board = source(1),
	BoardAt = source(-math.huge),
	Boards = source({} :: { Types.TBoardView }),
	SecondsLeft = source(0),
	PendingBoard = source(0),
	PendingSlot = source(0),
	PressedAt = source(-math.huge),
	Strikes = source({ {}, {} } :: { { [number]: number } }),
	RefusedSlot = source(0),
	RefusedAt = source(-math.huge),
}

-- The Gems the profile holds that are still in the air, and whether they are landing in the pill right now.
local heldGems = source(0)
local isLanding = source(false)
-- What each card's payout still owes the pill, by slot.
local owed: { number } = table.create(QuestsCore.BOARD_SIZE, 0)

-- os.clock until which Now keeps ticking.
local motionUntil = -math.huge
-- The newest State, applied at once unless a claim is waiting on its answer (that State is the claim's own, and is
-- applied with it).
local latest: { TWireBoard }? = nil
-- The bursts still to come, soonest first.
local bursts: { TBurst } = {}
local payouts: { GemPayout.TPayout } = {}
-- The gem each card's Gems burst out of, by board then slot.
local gems: { { [number]: GuiObject } } = { {}, {} }
local gemsTarget: GuiObject? = nil
-- Whether the board on show has a quest to claim: its CLAIMs' idle light needs the pulse. Worked out as the boards or
-- the tab change, not every frame.
local isShownReady = false
local lastTickAt = -math.huge

-- Whether the screen is up. Reads a vide source, so a view that calls it follows it.
function QuestsController.IsOpen(): boolean
	return state.IsOpen()
end

-- The Gems a claim paid that are still flying to the HUD's pill: the pill shows that many fewer. Reads a vide source.
function QuestsController.HeldGems(): number
	return heldGems()
end

-- Whether a claim's Gems are landing in the pill now. Reads a vide source.
function QuestsController.IsLandingGems(): boolean
	return isLanding()
end

-- Where the Gems fly to: the glyph on the HUD's Gems pill.
function QuestsController.SetGemsTarget(glyph: GuiObject)
	gemsTarget = glyph
end

local function stir(seconds: number)
	motionUntil = math.max(motionUntil, os.clock() + seconds)
end

-- Stamps a gesture's start and keeps Now ticking for it. `moment` may be still to come.
local function stamp(at: Types.Source<number>, moment: number)
	at(moment)
	motionUntil = math.max(motionUntil, moment + Tune.MOTION_SECONDS)
end

local function updateShownReady()
	isShownReady = Parts.ReadyCount(state.Boards()[state.Board()]) > 0
end

local function secondsLeftOf(board: number): number
	local view = state.Boards()[board]
	return if view then math.max(0, math.ceil(view.EndsAt - os.clock())) else 0
end

function QuestsController.Open()
	if state.IsOpen() then return end
	vide.batch(function()
		local now = os.clock()
		state.IsOpen(true)
		stamp(state.ToggledAt, now)
		state.OpenedAt(now)
		state.SecondsLeft(secondsLeftOf(state.Board()))
	end)
	stir(Screen.DEAL_SECONDS)
	SoundsCore.SetMuffled("Quests", true)
	BlurController.SetBlurred("Quests", true)
	SoundsCore.PlayUINamed("UI", "MenuIn")
end

function QuestsController.Close()
	if not state.IsOpen() then return end
	state.IsOpen(false)
	stamp(state.ToggledAt, os.clock())
	SoundsCore.SetMuffled("Quests", false)
	BlurController.SetBlurred("Quests", false)
	SoundsCore.PlayUINamed("UI", "MenuOut")
end

local function refuse(slot: number)
	vide.batch(function()
		state.RefusedSlot(slot)
		stamp(state.RefusedAt, os.clock())
	end)
	SoundsCore.PlayUINamed("UI.UpgradePick", "Denied")
end

local actions: Types.TQuestsActions = {
	Close = QuestsController.Close,
	PickBoard = function(board: number)
		if state.Board() == board then return end
		vide.batch(function()
			state.Board(board)
			stamp(state.BoardAt, os.clock())
			state.SecondsLeft(secondsLeftOf(board))
		end)
		updateShownReady()
		stir(Screen.DEAL_SECONDS)
		SoundsCore.PlayUINamed("UI.UpgradePick", "Deal")
	end,
	-- Checked here only to answer at once: the server checks it again.
	Claim = function(slot: number)
		if state.PendingBoard() ~= 0 then return end
		local board = state.Board()
		local view = state.Boards()[board]
		local quest = if view then QuestsCore.ById[view.Ids[slot]] else nil
		if not view or not quest or view.Claimed[slot] then return end
		if (view.Progress[slot] or 0) < quest.Goal then
			refuse(slot)
			return
		end

		vide.batch(function()
			state.PendingBoard(board)
			state.PendingSlot(slot)
			stamp(state.PressedAt, os.clock())
		end)
		ClientNetworkQuests.Claim.Fire(board, slot)
	end,
	ClaimAll = function()
		if state.PendingBoard() ~= 0 then return end
		local board = state.Board()
		if Parts.ReadyCount(state.Boards()[board]) == 0 then
			SoundsCore.PlayUINamed("UI.UpgradePick", "Denied")
			return
		end

		vide.batch(function()
			state.PendingBoard(board)
			state.PendingSlot(0)
			stamp(state.PressedAt, os.clock())
		end)
		ClientNetworkQuests.ClaimAll.Fire(board)
	end,
	MarkGem = function(board: number, slot: number, glyph: GuiObject)
		gems[board][slot] = glyph
	end,
	Stir = stir,
}

-- The newest State onto the screen. A board dealt again (a new period) forgets its strikes.
local function apply()
	local current = latest
	if not current then return end
	local now = os.clock()
	local old = state.Boards()
	local views = table.create(#QuestsCore.BOARDS)
	local strikes = table.clone(state.Strikes())
	for board, wire in current do
		views[board] = {
			Ids = wire.Ids,
			Progress = wire.Progress,
			Claimed = wire.Claimed,
			EndsAt = now + wire.SecondsLeft,
		}
		local before = old[board]
		for slot, id in wire.Ids do
			if not before or before.Ids[slot] ~= id then
				strikes[board] = {}
				break
			end
		end
	end

	state.Boards(views)
	state.Strikes(strikes)
	state.SecondsLeft(secondsLeftOf(state.Board()))
	updateShownReady()
end

-- Tells the HUD what the payouts still owe its pill; `isLandingNow` while their Gems are landing.
local function hold(isLandingNow: boolean)
	local total = 0
	for _, amount in owed do
		total += amount
	end
	heldGems(total)
	isLanding(isLandingNow and total > 0)
end

-- A card's moment: its sound, and its Gems out of its gem.
local function burst(job: TBurst, now: number)
	if job.IsFirst then
		SoundsCore.PlayUINamed("UI.UpgradePick", STRIKE_SOUNDS[job.Board] or "PickRare")
	else
		SoundsCore.PlayUINamed("UI.UpgradePick", "Deal")
	end

	local glyph = gems[job.Board][job.Slot]
	local payout = payouts[job.Slot]
	if not glyph or not glyph.Parent or not payout or not state.IsOpen() then
		owed[job.Slot] = 0
		hold(isLanding())
		return
	end

	local from = glyph.AbsolutePosition + glyph.AbsoluteSize / 2
	payout.Burst(from, job.Gems, now, function(left: number)
		owed[job.Slot] = left
		hold(true)
		local tickAt = os.clock()
		if tickAt - lastTickAt >= Tune.TICK_GAP then
			lastTickAt = tickAt
			SoundsCore.PlayUINamed("UI.UpgradePick", "Tick")
		end
	end)
end

local function updateScale()
	local viewport = Workspace.CurrentCamera.ViewportSize
	state.Scale(math.max(math.min(viewport.Y / Tune.DESIGN.Y, viewport.X / Tune.DESIGN.X), 0.01))
end

QuestsController.OnStart = function()
	local isPayingOut = source(false)
	vide.mount(function()
		-- Drawn only while it is up, still leaving, or its Gems are still in the air: shut, it costs nothing.
		local isDrawn = vide.derive(function(): boolean
			return state.IsOpen() or state.Now() - state.ToggledAt() < Tune.LEAVE_SECONDS or isPayingOut()
		end)
		local layers = table.create(QuestsCore.BOARD_SIZE)
		for slot = 1, QuestsCore.BOARD_SIZE do
			local payout = GemPayout.Build(state.Scale, function(): Vector2?
				local glyph = gemsTarget
				if not glyph or not glyph.Parent then return nil end
				return glyph.AbsolutePosition + glyph.AbsoluteSize / 2
			end)
			payouts[slot] = payout
			layers[slot] = payout.Layer
		end

		return create("ScreenGui")({
			Name = "Quests",
			ResetOnSpawn = false,
			IgnoreGuiInset = true,
			ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			DisplayOrder = Tune.DISPLAY_ORDER,
			Enabled = isDrawn,
			-- His 1920 x 1080, scaled whole into the middle of the screen.
			create("Frame")({
				Name = "Root",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(Tune.DESIGN.X, Tune.DESIGN.Y),
				BackgroundTransparency = 1,
				create("UIScale")({ Scale = state.Scale }),
				Screen.Build(state, actions),
			}),
			layers,
		})
	end, LocalPlayer:WaitForChild("PlayerGui"))

	-- Now is written only while something moves, so a screen at rest, open or shut, redraws nothing.
	RunService.PreRender:Connect(function()
		local now = os.clock()
		while bursts[1] and now >= bursts[1].At do
			burst(table.remove(bursts, 1) :: TBurst, now)
		end
		if now < motionUntil then state.Now(now) end

		local isUp = state.IsOpen() or now - state.ToggledAt() < Tune.LEAVE_SECONDS
		if isUp then
			local left = secondsLeftOf(state.Board())
			if left ~= state.SecondsLeft() then state.SecondsLeft(left) end
			if isShownReady and state.PendingBoard() == 0 then state.Pulse(now) end
		end

		local isBusy = false
		for _, payout in payouts do
			if payout.Step(now) then isBusy = true end
		end
		if isBusy ~= isPayingOut() then isPayingOut(isBusy) end
	end)

	local camera = Workspace.CurrentCamera
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	updateScale()
end

ServerNetworkQuests.State.On(function(daily: TWireBoard, weekly: TWireBoard)
	latest = { daily, weekly }
	if state.PendingBoard() ~= 0 then return end
	vide.batch(apply)
end)

-- Always after the State it changed (QuestsService), so `latest` is the claim's own.
ServerNetworkQuests.Claimed.On(function(board: number, slots: { number }, paid: number)
	local now = os.clock()
	local pressed = state.PendingSlot()
	vide.batch(function()
		state.PendingBoard(0)
		apply()
		if #slots == 0 then
			if pressed ~= 0 then refuse(pressed) end
			return
		end

		-- The Gems are the profile's already: the pill holds them back until they land. Each card throws its own
		-- quest's; whatever the server paid past them goes with the last.
		local view = state.Boards()[board]
		-- The wind-up always shows whole, however fast the answer came: a release with no wind-up is a pop.
		local release = math.max(now, state.PressedAt() + Card.WIND_UP)
		local strikes = table.clone(state.Strikes())
		local onBoard = table.clone(strikes[board] or {})
		local left = paid
		for order, slot in slots do
			local quest = if view then QuestsCore.ById[view.Ids[slot]] else nil
			local amount = if order == #slots then left else math.min(left, if quest then quest.Gems else 0)
			left -= amount
			local at = release + Tune.CASCADE * (order - 1)
			onBoard[slot] = at
			owed[slot] = amount
			table.insert(bursts, { At = at, Board = board, Slot = slot, Gems = amount, IsFirst = order == 1 })
		end
		strikes[board] = onBoard
		state.Strikes(strikes)
		hold(isLanding())
		motionUntil = math.max(motionUntil, release + Tune.CASCADE * #slots + Card.STRIKE_SECONDS + Tune.MOTION_SECONDS)
	end)
end)

return Ignis.Register(QuestsController)
