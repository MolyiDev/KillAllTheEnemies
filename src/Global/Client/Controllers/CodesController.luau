-- The codes screen on this client, in both places (UI/CodesUI): what is typed, asking CodesService to redeem it and
-- showing the answer, and the screen's opening and shutting. The top bar's ticket opens it.
--
-- An answer is held until the wind-up after the press has played, so a fast server never skips it. A code's Gems are
-- the profile's in the same frame as the answer: in the lobby they are held back from the HUD's pill (HeldGems) and let
-- through a slice per piece as they fly into it (GemPayout); where there is no pill (a match) nothing flies.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local vide = require(ReplicatedStorage.Packages.vide)
local NetworkMeta = require(StarterPlayer.StarterPlayerScripts.GlobalClient.NetworkMeta)
local CameraController = require(script.Parent.CameraController)
local CodesCore = require(ReplicatedStorage.GlobalShared.Core.CodesCore)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local CodesUI = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.CodesUI)
local GemPayout = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.GemPayout)
local Types = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.CodesUI.Types)

local ServerNetworkCodes = NetworkMeta.Server.Codes
local ClientNetworkCodes = NetworkMeta.Client.Codes
local LocalPlayer = Players.LocalPlayer
local Status = CodesCore.Status
local source = vide.source
local create = vide.create

local Tune = table.freeze({
	-- The screen is a 1920 x 1080 design, fitted inside the viewport whole.
	DESIGN = Vector2.new(1920, 1080),
	-- With the settings screen: above the HUD and the lobby's screens. Only one of the two is ever open.
	DISPLAY_ORDER = 10,
	-- How long the clock keeps ticking after anything starts a timed gesture: the longest one is shorter.
	MOTION_SECONDS = 1.6,
	-- Longer than the screen's way out (CodesUI): it is drawn this long after it is shut.
	LEAVE_SECONDS = CodesUI.LEAVE_SECONDS + 0.05,
	-- The least time between the press and its answer showing: the field's scan and REDEEM's rattle get to play.
	WIND_UP = 0.32,
	-- An answer that never came is given up after this long.
	ANSWER_TIMEOUT = 6,
	-- After a redeem: the cards are dealt, the field is swept clear, its letters lifting out a beat apart, and the Gems
	-- burst off their card once its number has run up.
	REWARDS_DELAY = 0.3,
	CLEAR_DELAY = 1.15,
	SWEEP_STAGGER = 0.03,
	-- A paste lands its letters this far apart.
	PASTE_STAGGER = 0.03,
	-- The caret's blink, on for half of each period, starting on at every key.
	BLINK = 1.06,
})

local MESSAGES = table.freeze({
	Hint = "TYPE A CODE, THEN PRESS REDEEM",
	Empty = "TYPE A CODE FIRST",
	Redeemed = "CODE REDEEMED!",
	NoAnswer = "NO ANSWER, TRY AGAIN",
	[Status.NotFound] = "THAT CODE DOESN'T EXIST",
	[Status.AlreadyRedeemed] = "YOU ALREADY USED THAT CODE",
	[Status.Expired] = "THAT CODE HAS EXPIRED",
	[Status.TooFast] = "TOO FAST! WAIT A SECOND",
	[Status.Failed] = "SOMETHING WENT WRONG, TRY AGAIN",
})

local function ghost(): Types.TGhost
	return {
		Letter = source(""),
		Cell = source(1),
		At = source(-math.huge),
		IsLift = source(false),
	}
end

local function buildState(): Types.TCodesState
	local bornAt = table.create(CodesCore.MAX_LENGTH)
	local ghosts = table.create(CodesCore.MAX_LENGTH)
	for index = 1, CodesCore.MAX_LENGTH do
		bornAt[index] = source(-math.huge)
		ghosts[index] = ghost()
	end

	return {
		Scale = source(1),
		Now = source(os.clock()),
		IsOpen = source(false),
		ToggledAt = source(-math.huge),
		Text = source(""),
		BornAt = bornAt,
		Ghosts = ghosts,
		IsFocused = source(false),
		FocusedAt = source(-math.huge),
		IsCaretOn = source(true),
		Status = source("Typing" :: Types.TStatus),
		AskedAt = source(-math.huge),
		AnsweredAt = source(-math.huge),
		Message = source(MESSAGES.Hint),
		MessageKind = source("Hint" :: "Hint" | "Bad" | "Good"),
		MessageAt = source(-math.huge),
		NudgedAt = source(-math.huge),
		Gems = source(0),
		Xp = source(0),
		RewardsAt = source(-math.huge),
	}
end

local state = buildState()

-- os.clock until which Now keeps ticking.
local motionUntil = -math.huge
-- The server's answer waiting for the wind-up to finish: (status, gems, xp) and when it is let go.
local pending: { Status: number, Gems: number, Xp: number }? = nil
local releaseAt = math.huge
-- After a redeem: when the field is swept, and when the Gems burst off their card.
local clearAt = math.huge
local burstAt = math.huge
-- os.clock of the last key, for the caret's blink.
local typedAt = -math.huge
local nextGhost = 1

-- What the HUD's pill is held back by, and whether Gems are landing in it now.
local heldGems = source(0)
local isLandingGems = source(false)
local gemsTarget: GuiObject? = nil
local payout: GemPayout.TPayout? = nil
local gemGlyph: ImageLabel? = nil

local CodesController = {}

-- Whether the screen is up. Reads a vide source, so a view that calls it follows it.
function CodesController.IsOpen(): boolean
	return state.IsOpen()
end

-- The Gems a code paid that have not flown into the HUD's pill yet: the HUD shows the profile's less these. Reads a
-- vide source.
function CodesController.HeldGems(): number
	return heldGems()
end

-- Whether a code's Gems are landing in the pill now. Reads a vide source.
function CodesController.IsLandingGems(): boolean
	return isLandingGems()
end

-- Where the Gems fly to: the glyph on the lobby HUD's Gems pill.
function CodesController.SetGemsTarget(glyph: GuiObject)
	gemsTarget = glyph
end

local function stir(seconds: number)
	motionUntil = math.max(motionUntil, os.clock() + seconds)
end

local function say(text: string, kind: "Hint" | "Bad" | "Good", now: number)
	if state.Message() == text and state.MessageKind() == kind then return end
	state.Message(text)
	state.MessageKind(kind)
	state.MessageAt(now)
end

-- A letter leaving cell `cell` at `at`: falling (deleted) or lifting (swept after a redeem).
local function release(letter: string, cell: number, at: number, isLift: boolean)
	local slot = state.Ghosts[nextGhost]
	nextGhost = nextGhost % #state.Ghosts + 1
	slot.Letter(letter)
	slot.Cell(cell)
	slot.IsLift(isLift)
	slot.At(at)
end

function CodesController.Open()
	if state.IsOpen() then return end
	local now = os.clock()
	vide.batch(function()
		state.IsOpen(true)
		state.ToggledAt(now)
		-- What the last visit paid has been seen; an answer still on its way is shown when it comes.
		if state.Status() ~= "Checking" then
			state.Status("Typing")
			say(MESSAGES.Hint, "Hint", -math.huge)
			state.RewardsAt(-math.huge)
			state.Gems(0)
			state.Xp(0)
		end
	end)
	CameraController.IsMouseFreed = true
	stir(Tune.MOTION_SECONDS)
	SoundsCore.PlayUINamed("UI", "MenuIn")
end

function CodesController.Close()
	if not state.IsOpen() then return end
	vide.batch(function()
		state.IsOpen(false)
		state.ToggledAt(os.clock())
	end)
	CameraController.IsMouseFreed = false
	stir(Tune.MOTION_SECONDS)
	SoundsCore.PlayUINamed("UI", "MenuOut")
end

-- The box's text, normalized by the field. Each new letter pops in its cell (a paste's a beat apart), each one gone
-- drops out of it.
local function typeText(text: string)
	local old = state.Text()
	if text == old then return end
	local now = os.clock()

	local same = 0
	while same < #old and same < #text and string.byte(old, same + 1) == string.byte(text, same + 1) do
		same += 1
	end
	local added = #text - same
	vide.batch(function()
		for cell = same + 1, #old do
			release(string.sub(old, cell, cell), cell, now, false)
		end
		for cell = same + 1, #text do
			state.BornAt[cell](if added > 1 then now + Tune.PASTE_STAGGER * (cell - same - 1) else now)
		end
		state.Text(text)
		state.IsCaretOn(true)
		-- The answer shown stood for the code it answered: a new one goes back to the hint.
		if state.Status() == "Redeemed" or state.Status() == "Refused" then
			state.Status("Typing")
			say(MESSAGES.Hint, "Hint", now)
		end
	end)
	typedAt = now
	clearAt = math.huge
	stir(0.5 + Tune.PASTE_STAGGER * added)
	SoundsCore.PlayHover()
end

local function refuse(text: string, now: number)
	vide.batch(function()
		state.Status("Refused")
		state.AnsweredAt(now)
		say(text, "Bad", now)
	end)
	stir(Tune.MOTION_SECONDS)
	if state.IsOpen() then SoundsCore.PlayUINamed("UI.UpgradePick", "Denied") end
end

-- The answer let go at `now`. One that comes back to a shut screen is shown if it is opened again, without a sound.
local function answer(status: number, gems: number, xp: number, now: number)
	if status ~= Status.Redeemed then
		refuse(MESSAGES[status] or MESSAGES[Status.Failed], now)
		return
	end

	vide.batch(function()
		state.Status("Redeemed")
		state.AnsweredAt(now)
		say(MESSAGES.Redeemed, "Good", now)
		state.Gems(gems)
		state.Xp(xp)
		state.RewardsAt(now + Tune.REWARDS_DELAY)
	end)
	clearAt = now + Tune.CLEAR_DELAY
	-- The Gems wait in their card until its number has run up, then fly; with nowhere to fly, the pill has them now.
	local canFly = gems > 0 and state.IsOpen() and gemsTarget ~= nil and gemsTarget.Parent ~= nil
	heldGems(if canFly then gems else 0)
	burstAt = if canFly then now + Tune.REWARDS_DELAY + CodesUI.COUNTED_SECONDS else math.huge
	stir(Tune.CLEAR_DELAY + Tune.MOTION_SECONDS)
	if state.IsOpen() then SoundsCore.PlayUINamed("UI.UpgradePick", "RevealLegendary") end
end

local actions: Types.TCodesActions = {
	Close = CodesController.Close,
	Type = typeText,
	Focus = function(isFocused: boolean)
		if state.IsFocused() == isFocused then return end
		local now = os.clock()
		vide.batch(function()
			state.IsFocused(isFocused)
			state.IsCaretOn(true)
			if isFocused then state.FocusedAt(now) end
		end)
		typedAt = now
		stir(0.6)
	end,
	-- Checked here first only to answer at once: the server checks it all again.
	Redeem = function()
		if state.Status() == "Checking" then return end
		local now = os.clock()
		if state.Text() == "" then
			vide.batch(function()
				state.NudgedAt(now)
				say(MESSAGES.Empty, "Bad", now)
			end)
			stir(0.8)
			SoundsCore.PlayUINamed("UI.UpgradePick", "Denied")
			return
		end

		vide.batch(function()
			state.Status("Checking")
			state.AskedAt(now)
		end)
		pending = nil
		releaseAt = math.huge
		clearAt = math.huge
		stir(Tune.WIND_UP)
		ClientNetworkCodes.Redeem.Fire(state.Text())
	end,
}

-- Each frame: the answer let go, the field swept, the Gems thrown, a lost answer given up on, the caret's blink.
local function step(now: number)
	local answered = pending
	if answered and now >= releaseAt then
		pending = nil
		releaseAt = math.huge
		answer(answered.Status, answered.Gems, answered.Xp, now)
	elseif state.Status() == "Checking" then
		-- The scan and the rattle run for as long as the answer is out, and no longer.
		if now - state.AskedAt() > Tune.ANSWER_TIMEOUT then
			refuse(MESSAGES.NoAnswer, now)
		else
			motionUntil = math.max(motionUntil, now + 0.05)
		end
	end

	if now >= clearAt then
		clearAt = math.huge
		local text = state.Text()
		for cell = 1, #text do
			release(string.sub(text, cell, cell), cell, now + Tune.SWEEP_STAGGER * (cell - 1), true)
		end
		state.Text("")
	end

	if now >= burstAt then
		burstAt = math.huge
		local current, glyph = payout, gemGlyph
		if current and glyph and state.IsOpen() then
			current.Burst(glyph.AbsolutePosition + glyph.AbsoluteSize / 2, heldGems(), now, function(owed: number)
				heldGems(owed)
				isLandingGems(owed > 0)
				SoundsCore.PlayUINamed("UI.UpgradePick", "Tick")
			end)
		else
			heldGems(0)
		end
	end

	if state.IsFocused() then
		local isOn = (now - typedAt) % Tune.BLINK < Tune.BLINK / 2
		if isOn ~= state.IsCaretOn() then state.IsCaretOn(isOn) end
	end
end

local function updateScale()
	local viewport = Workspace.CurrentCamera.ViewportSize
	state.Scale(math.max(math.min(viewport.Y / Tune.DESIGN.Y, viewport.X / Tune.DESIGN.X), 0.01))
end

CodesController.OnStart = function()
	local isPayingOut = source(false)
	vide.mount(function()
		-- Drawn only while it is up, still leaving, or its Gems are still in the air: shut, it costs nothing.
		local isDrawn = vide.derive(function(): boolean
			return state.IsOpen() or state.Now() - state.ToggledAt() < Tune.LEAVE_SECONDS or isPayingOut()
		end)
		local built = GemPayout.Build(state.Scale, function(): Vector2?
			local glyph = gemsTarget
			if not glyph or not glyph.Parent then return nil end
			return glyph.AbsolutePosition + glyph.AbsoluteSize / 2
		end)
		payout = built
		local children, glyph = CodesUI.Build(state, actions)
		gemGlyph = glyph

		return create("ScreenGui")({
			Name = "Codes",
			ResetOnSpawn = false,
			IgnoreGuiInset = true,
			ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			DisplayOrder = Tune.DISPLAY_ORDER,
			Enabled = isDrawn,
			children,
			built.Layer,
		})
	end, LocalPlayer:WaitForChild("PlayerGui"))

	-- Now is written only while something moves, so a screen at rest, open or shut, redraws nothing.
	RunService.PreRender:Connect(function()
		local now = os.clock()
		vide.batch(function()
			step(now)
			if now < motionUntil then state.Now(now) end
		end)

		local current = payout
		local isBusy = current ~= nil and current.Step(now)
		if isBusy ~= isPayingOut() then isPayingOut(isBusy) end
		if not isBusy and isLandingGems() then isLandingGems(false) end
	end)

	local camera = Workspace.CurrentCamera
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	updateScale()
end

-- Every Redeem is answered, a refused one too, in the same frame as the profile a paid one changed.
ServerNetworkCodes.Redeemed.On(function(status: number, gems: number, xp: number)
	if state.Status() ~= "Checking" then return end
	pending = { Status = status, Gems = gems, Xp = xp }
	releaseAt = state.AskedAt() + Tune.WIND_UP
	-- Paid already: until the answer is let go, the pill must not show it.
	if status == Status.Redeemed and gems > 0 and gemsTarget then heldGems(gems) end
end)

return Ignis.Register(CodesController)
