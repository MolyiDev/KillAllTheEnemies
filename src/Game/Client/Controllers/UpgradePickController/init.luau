--!nonstrict
-- The pick of a run upgrade (UpgradesService deals the hand and applies the pick): the cards are dealt in front of
-- the camera as parts (Stage) wearing the designer's card (Card), lean and sink under the hand, and the one taken is
-- held up while the others are thrown away. This file owns the flow, the input and every vide source; the server
-- decides what is in a hand and which card was taken, and nothing is shown as picked before it says so.
--
-- A ScreenGui always draws over the world, so while the cards are up the HUD is hidden (IsCovering, read by
-- HudController) and the dim is a part behind them. A black curtain on the screen fades the HUD out and in round that
-- swap, so neither side of it snaps. While they are up the world is heard as if under water (SoundsCore.SetMuffled).
--
-- It also shows the others' picks: a tag over each teammate who is picking (PickingTag), from the server's word. A
-- pick is seen on the taker's body too (upgradeFx): one's own once the screen has gone, a teammate's as their tag goes.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local vide = require(ReplicatedStorage.Packages.vide)
local Network = require(StarterPlayer.StarterPlayerScripts.GlobalClient.Network)
local CameraController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.CameraController)
local MatchController = require(script.Parent.MatchController)
local TweensController = require(script.Parent.TweensController)
local upgradeFx = require(script.Parent.Parent.Utils.upgradeFx)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local UpgradesCore = require(ReplicatedStorage.Shared.Core.UpgradesCore)
local Components = require(ReplicatedStorage.GlobalShared.ECS.Components)
local World = require(ReplicatedStorage.GlobalShared.ECS.Worlds.World)
local getCharacterEntityFromPlayer =
	require(ReplicatedStorage.GlobalShared.Utils.Functions.getCharacterEntityFromPlayer)
local Card = require(script.Card)
local PickingTag = require(script.PickingTag)
local Screen = require(script.Screen)
local Stage = require(script.Stage)
local ERarities = require(ReplicatedStorage.Types.Enums.ERarities)
local NetworkTypes = require(ReplicatedStorage.Types.NetworkTypes)
local TPlayerEvents = require(ReplicatedStorage.Types.Events.TPlayerEvents)

local ServerNetworkUpgrades = Network.Server.Upgrades
local ClientNetworkUpgrades = Network.Client.Upgrades
local LocalPlayer = Players.LocalPlayer
local UPGRADES = DataCore.Upgrades.ById

local source = vide.source
local create = vide.create

local UpgradePickController = {}

-- The cards are up and the HUD is to be hidden under them. A source, so the HUD goes and comes back on the very
-- frame the dim changes hands, whichever of the two steps first.
UpgradePickController.IsCovering = source(false)
-- The server has this player out of the fight for a pick (Tags.Picking): from the deal until the card taken has left.
UpgradePickController.IsPicking = false
-- A screen stands over the cards (the squad, the settings; HudController says which). The cards read the mouse
-- themselves, past the full-screen catch that eats every press, so they would take that screen's clicks too.
UpgradePickController.IsOverlaid = false

local Tune = table.freeze({
	-- Design px between two cards' middles, and how far under the screen's middle they stand (his rects).
	SPACING = 396,
	REST_Y = -30,
	-- The canvas is drawn this many times its design size, so a card held up close is still sharp.
	RESOLUTION = 1.5,
	-- His dim over the world, and how long the curtain takes to bring the HUD under it and back.
	DIM = 0.4,
	CURTAIN_SECONDS = 0.18,
	CLOSE_SECONDS = 0.22,

	-- The deal: each card comes up from under the right of the screen, face down and askew, this long after the last,
	-- and turns over on its way. Nothing can be picked until they have landed, so a hand still on the trigger from
	-- the wave does not take one.
	DEAL_STAGGER = 0.11,
	DEAL_FROM = Vector3.new(560, -820, 0.72),
	DEAL_TURN = Vector3.new(0.5, -math.pi, -0.5),
	DEAL_SETTLE = 0.8,
	INPUT_LOCK = 0.55,
	-- Where it is: little overshoot. How it is turned: a wobble that dies in a few swings.
	POINT_FREQUENCY = 2.4,
	POINT_DAMPING = 0.72,
	DEAL_TURN_FREQUENCY = 2,
	DEAL_TURN_DAMPING = 0.42,
	TURN_FREQUENCY = 3.4,
	TURN_DAMPING = 0.3,

	-- Under the hand a card comes toward the eye and leans as if pressed where the hand is; held down it sinks and
	-- leans further. The others give it room.
	HOVER_ZOOM = 1.07,
	PRESS_ZOOM = 0.96,
	TILT = 0.2,
	PRESS_TILT = 0.32,
	NEIGHBOUR_PUSH = 16,
	HOVER_KICK = 2.2,
	-- A card keeps the hand until it is this far outside its rect, so the lean cannot flicker it away.
	HOVER_REACH = 1.06,
	HOVER_RATE = 12,
	ASK_KICK = 1.6,
	ASK_TIMEOUT = 3,

	-- A redeal: each card turns face down, becomes its new card while nobody can see, and turns back.
	REROLL_STAGGER = 0.07,
	REROLL_HALF = 0.22,
	REROLL_LOCK = 0.7,
	REROLL_TURN_DAMPING = 0.5,

	-- The pick: the taken card spins once on its way to the middle and is held there; the others are thrown down and
	-- away. Then it drops out toward the hotbar.
	PICK_POINT = Vector2.new(0, 10),
	PICK_ZOOM = 1.22,
	PICK_FREQUENCY = 2.2,
	PICK_DAMPING = 0.62,
	SPIN_FREQUENCY = 1.7,
	SPIN_DAMPING = 0.62,
	FLASH_SECONDS = 0.45,
	HOLD_SECONDS = 1.15,
	LEAVE_SECONDS = 0.45,
	LEAVE_TO = Vector3.new(0, -980, 0.4),
	LEAVE_FREQUENCY = 1.5,
	TOSS_FREQUENCY = 0.9,
	TOSS_TO_Y = -1500,
	TOSS_VELOCITY = Vector3.new(520, 950, 0),
	TOSS_SPIN = Vector3.new(2, 3, 7),
	SHADE_RATE = 7,
	-- A hand taken back (a boss coming, the run over) leaves the way it was dealt: each card, the last dealt first,
	-- turns face down on its way back under the right of the screen, gathering speed as it goes.
	UNDEAL_FREQUENCY = 1.8,
	UNDEAL_TURN_FREQUENCY = 2,
	UNDEAL_SECONDS = 0.6,
	FOV_PUNCH = 3,
	FOV_RETURN = 0.5,

	-- Teammates' tags: one each, enough for a full party.
	MAX_TAGS = 4,

	-- The count ticks aloud for its last seconds only.
	TICK_SECONDS = 3,
})

-- The screen's clips (Sounds.UI.UpgradePick, Assets/sounds/Review/UpgradePick). A Deal take carries its snap 0.10 s in,
-- where a card dealt or starting a turn shows its other face (Stage's springs), so it plays as the card moves off.
local SOUNDS = "UI.UpgradePick"
local PICK_SOUNDS = table.freeze({
	[ERarities.Common] = "PickCommon",
	[ERarities.Uncommon] = "PickUncommon",
	[ERarities.Rare] = "PickRare",
	[ERarities.Epic] = "PickEpic",
	[ERarities.Legendary] = "PickLegendary",
	[ERarities.Mythic] = "PickMythic",
})
-- A card this rare is announced as it turns face up.
local REVEAL_SOUNDS = table.freeze({
	[ERarities.Epic] = "RevealEpic",
	[ERarities.Legendary] = "RevealLegendary",
	[ERarities.Mythic] = "RevealMythic",
})
-- The level-up on the body once the screen has gone: heard in the world (Effects bus), not on the screen's.
local BODY_SOUNDS = "Upgrades"

type THand = NetworkTypes.Server_Upgrades_Hand
type TPhase = "Closed" | "Opening" | "Open" | "Picked" | "Closing"

-- What each card is told, and whether its part is drawn.
type TCardSources = Card.TCardState & { IsShown: vide.Source<boolean>, Order: vide.Source<number> }

local cards: { TCardSources } = table.create(UpgradesCore.HAND_SIZE)
for index = 1, UpgradesCore.HAND_SIZE do
	cards[index] = {
		Id = source(0),
		Level = source(1),
		Rarity = source(1),
		IsFaceUp = source(false),
		IsRevealed = source(false),
		Hover = source(0),
		GlareAt = source(0),
		Shade = source(0),
		Flash = source(0),
		IsShown = source(false),
		Order = source(0),
	}
end

local screen: Screen.TScreenState = {
	IsEnabled = source(false),
	Scale = source(1),
	Clock = source(math.huge),
	PickClock = source(math.huge),
	IsUp = source(false),
	ToggledAt = source(-math.huge),
	Curtain = source(0),
	IsCatching = source(false),
	Round = source(0),
	RerollPrice = source(UpgradesCore.REROLL_PRICE),
	CanReroll = source(false),
	RerollAskedAt = source(-math.huge),
	RerollDeniedAt = source(-math.huge),
	SecondsLeft = source(0),
	TickAt = source(-math.huge),
	PickedAt = source(-math.huge),
	PickedColor = source(Theme.Palette.White),
	PickPoint = Tune.PICK_POINT,
	PickSize = Card.SIZE * Tune.PICK_ZOOM,
}
local dimOpacity = source(0)

local stage = Stage.new(table.create(UpgradesCore.HAND_SIZE, Vector2.zero), Card.SIZE, Card.CANVAS)
local bodies = stage.Bodies

-- What the run's picks add up to, by upgrade id.
local stats: { [number]: number } = {}

local phase: TPhase = "Closed"
local phaseAt = 0
-- The hand that is up, and one that arrived while the last pick was still being shown.
local hand: THand? = nil
local queuedHand: THand? = nil
-- os.clock the server picks at, the cards are dealt from, and input opens at.
local pickAt = 0
local dealAt = 0
local inputFrom = 0
-- The card under the hand, the one held down, the one asked for (until the server answers), and the one the pad is on.
local hoverIndex: number? = nil
local pressedIndex: number? = nil
local askedIndex: number? = nil
local askedAt = 0
local padIndex: number? = nil
local touchAt: Vector2? = nil
-- A redeal in flight: the hand each card turns into, and when it started.
local rerollTo: THand? = nil
local rerollAt = 0
-- Each card's place in the flow: whether it has been dealt, how far it is through a redeal (0 not started, 1 turning
-- face down, 2 turning back), the os.clock it leaves at when the hand is taken back, and how much of the hand's light
-- and the losers' shade it has (0 to 1, before they are rounded onto its sources).
local slots: { { IsDealt: boolean, RerollStep: number, LeaveAt: number, Hover: number, Shade: number } } =
	table.create(UpgradesCore.HAND_SIZE)
for index = 1, UpgradesCore.HAND_SIZE do
	slots[index] = { IsDealt = false, RerollStep = 0, LeaveAt = math.huge, Hover = 0, Shade = 0 }
end
-- os.clock until which the screen's clock runs (the last of its gestures to end), and the frame's dt for step, so
-- the per-frame batch passes a function that captures nothing.
local clockUntil = -math.huge
-- The same for the pick's own clock: its ring and sparks are not run by the count's tick.
local pickClockUntil = -math.huge
local frameDt = 0
local pickedIndex = 0
local isLeaving = false
-- Seconds from a hand being taken back until its last card is gone.
local undealSeconds = 0
-- The rarest card taken since the screen opened (0 for none): shown on the body once it has closed.
local takenRarity = 0

-- The teammates' tags: a tag is a teammate's from their first word that they pick until it has shrunk away.
type TTag = PickingTag.TTagState & { Player: Player?, IsPicking: boolean, Rarity: number }
local tags: { TTag } = table.create(Tune.MAX_TAGS)
for index = 1, Tune.MAX_TAGS do
	tags[index] = {
		Adornee = source(nil :: BasePart?),
		Clock = source(0),
		ShownAt = source(-math.huge),
		PickedAt = source(-math.huge),
		PickedColor = source(Theme.Palette.White),
		EndedAt = source(math.huge),
		Player = nil,
		IsPicking = false,
		Rarity = 0,
	}
end
local tagScale = source(1)
local isAnyTagUp = false

-- A bench's hand: where the pointer is taken to be (raw viewport px) instead of the mouse. Nil in play.
UpgradePickController.BenchPointer = nil :: Vector2?

-- What the run's picks of `upgradeId` add up to; 0 with none.
function UpgradePickController.GetStat(upgradeId: number): number
	return stats[upgradeId] or 0
end

-- Stamps one of the screen's gestures and keeps its clock running until it is over.
local function stamp(at: vide.Source<number>, now: number, seconds: number)
	at(now)
	clockUntil = math.max(clockUntil, now + seconds)
end

local function setHeader(isUp: boolean, now: number)
	if screen.IsUp() == isUp then return end
	screen.IsUp(isUp)
	stamp(screen.ToggledAt, now, Screen.Seconds.HEADER)
end

local function writeCard(index: number, card: UpgradesCore.TCard)
	local sources = cards[index]
	sources.Id(card.Id)
	sources.Level(card.Level)
	sources.Rarity(card.Rarity)
end

-- Sends a body off the bottom of the screen, tumbling, away from the middle.
local function toss(body: Stage.TBody)
	-- Away from the middle; the middle card goes right.
	local side = if body.Rest.X < 0 then -1 else 1
	body.Sway = 0
	body.PointFrequency = Tune.TOSS_FREQUENCY
	body.PointDamping = 1
	body.PointTarget = Vector3.new(body.Rest.X * 2.4 + side * 200, Tune.TOSS_TO_Y, 0.8)
	body.PointVelocity = Vector3.new(side * Tune.TOSS_VELOCITY.X, Tune.TOSS_VELOCITY.Y, 0)
	body.TurnVelocity = Vector3.new(Tune.TOSS_SPIN.X, side * Tune.TOSS_SPIN.Y, side * Tune.TOSS_SPIN.Z)
end

local function hideBodies()
	for index, body in bodies do
		body.IsShown = false
		cards[index].IsShown(false)
		cards[index].Shade(0)
		cards[index].Flash(0)
		cards[index].Hover(0)
		slots[index].Hover = 0
		slots[index].Shade = 0
	end
end

-- Puts `newHand` on the table: its cards on their sources and their rests, to be dealt from `now`.
local function deal(newHand: THand, now: number)
	hand = newHand
	pickAt = now + newHand.Seconds
	dealAt = now
	inputFrom = now + #newHand.Cards * Tune.DEAL_STAGGER + Tune.INPUT_LOCK
	hoverIndex, pressedIndex, askedIndex, padIndex, rerollTo = nil, nil, nil, nil, nil
	isLeaving = false
	hideBodies()
	local count = #newHand.Cards
	for index, body in bodies do
		slots[index].IsDealt = index > count
		slots[index].RerollStep = 0
		body.Rest = Vector2.new((index - (count + 1) / 2) * Tune.SPACING, Tune.REST_Y)
		if index <= count then writeCard(index, newHand.Cards[index]) end
	end

	screen.Round(newHand.Round)
	screen.RerollPrice(newHand.RerollPrice)
	screen.IsCatching(true)
	setHeader(true, now)
end

-- A card comes onto the table: under the right of the screen, face down, on its way to its rest.
local function dealBody(index: number)
	local body = bodies[index]
	local rest = Vector3.new(body.Rest.X, body.Rest.Y, 1)
	slots[index].IsDealt = true
	body.IsShown = true
	body.Sway = 0
	body.Point = Vector3.new(rest.X + Tune.DEAL_FROM.X, Tune.DEAL_FROM.Y, Tune.DEAL_FROM.Z)
	body.PointVelocity = Vector3.zero
	body.PointTarget = rest
	body.PointFrequency = Tune.POINT_FREQUENCY
	body.PointDamping = Tune.POINT_DAMPING
	body.Turn = Tune.DEAL_TURN
	body.TurnVelocity = Vector3.zero
	body.TurnTarget = Vector3.zero
	body.TurnFrequency = Tune.DEAL_TURN_FREQUENCY
	body.TurnDamping = Tune.DEAL_TURN_DAMPING
	cards[index].IsShown(true)
	SoundsCore.PlayUINamed(SOUNDS, "Deal")
end

local function close(now: number)
	phase = "Closing"
	phaseAt = now
	hand = nil
	hideBodies()
	UpgradePickController.IsCovering(false)
	screen.IsCatching(false)
	setHeader(false, now)
	SoundsCore.SetMuffled("UpgradePick", false)
end

local function canInput(now: number): boolean
	return phase == "Open"
		and now >= inputFrom
		and not askedIndex
		and not rerollTo
		and not UpgradePickController.IsOverlaid
end

-- Asks the server for card `index` of the hand. The card answers the hand at once; it is taken when the server says.
local function ask(index: number)
	local now = os.clock()
	if not canInput(now) or not hand or not hand.Cards[index] then return end
	askedIndex = index
	askedAt = now
	hoverIndex = index
	pressedIndex = nil
	bodies[index].PointVelocity += Vector3.new(0, 0, Tune.ASK_KICK)
	SoundsCore.PlayClick()
	ClientNetworkUpgrades.Pick.Fire(index)
end

-- Asks for a new hand. Refused here, for REROLL to show it, when the Gold is short; the server checks it again.
local function reroll()
	local now = os.clock()
	if not canInput(now) or not hand then return end
	if MatchController.Gold < hand.RerollPrice then
		stamp(screen.RerollDeniedAt, now, Screen.Seconds.GESTURE)
		SoundsCore.PlayUINamed(SOUNDS, "Denied")
		return
	end

	stamp(screen.RerollAskedAt, now, Screen.Seconds.GESTURE)
	-- Held until the new hand lands, so a second press cannot pay twice for one look.
	inputFrom = now + Tune.ASK_TIMEOUT
	ClientNetworkUpgrades.Reroll.Fire()
end

-- The pointer in raw viewport px: the pad's card, a finger, or the mouse.
local function pointerHit(): (number?, number, number)
	if padIndex then return padIndex, 0, 0 end
	local bench = UpgradePickController.BenchPointer
	if not bench and not touchAt and not UserInputService.MouseEnabled then return nil, 0, 0 end
	local pointer = bench or touchAt or UserInputService:GetMouseLocation()
	return stage:Hit(pointer, hoverIndex, Tune.HOVER_REACH)
end

-- Each card comes onto the table in its turn, and takes its rest sway once it has landed.
local function stepDeal(now: number, dt: number)
	for index, body in bodies do
		local dealtFor = now - dealAt - (index - 1) * Tune.DEAL_STAGGER
		if not slots[index].IsDealt and dealtFor >= 0 then dealBody(index) end
		if not body.IsShown or rerollTo or dealtFor < Tune.DEAL_SETTLE then continue end
		body.TurnFrequency = Tune.TURN_FREQUENCY
		body.TurnDamping = Tune.TURN_DAMPING
		body.Sway = math.min(body.Sway + dt * 2, 1)
	end
end

-- A redeal: each card in its turn goes face down, becomes its card of `redeal` while it cannot be seen, and comes
-- back up. A card the new hand has nothing for is thrown away.
local function stepReroll(redeal: THand, now: number)
	local isDone = true
	for index, body in bodies do
		local slot = slots[index]
		local t = now - rerollAt - (index - 1) * Tune.REROLL_STAGGER
		if slot.RerollStep == 0 and t >= 0 then
			slot.RerollStep = 1
			body.Sway = 0
			body.TurnFrequency = Tune.TURN_FREQUENCY
			body.TurnDamping = Tune.REROLL_TURN_DAMPING
			body.TurnTarget = Vector3.new(0, math.pi, 0)
			if body.IsShown then SoundsCore.PlayUINamed(SOUNDS, "Deal") end
		elseif slot.RerollStep == 1 and t >= Tune.REROLL_HALF then
			slot.RerollStep = 2
			local card = redeal.Cards[index]
			if card then
				writeCard(index, card)
				-- A whole turn off where it is, which looks the same: it carries on round the same way.
				body.Turn -= Vector3.new(0, 2 * math.pi, 0)
				body.TurnTarget = Vector3.zero
				body.TurnDamping = Tune.DEAL_TURN_DAMPING
				SoundsCore.PlayUINamed(SOUNDS, "Deal")
			elseif body.IsShown then
				toss(body)
			end
		end
		if slot.RerollStep < 2 then isDone = false end
	end
	if not isDone or now < rerollAt + Tune.REROLL_LOCK then return end

	rerollTo = nil
	-- Landed: the cards take their rest sway again at once.
	dealAt = now - Tune.DEAL_SETTLE
	for _, slot in slots do
		slot.RerollStep = 0
	end
end

-- The cards answer the hand: the one under it comes up and leans where it is pressed, the others give it room.
local function stepHover(count: number, now: number)
	if askedIndex and now - askedAt > Tune.ASK_TIMEOUT then askedIndex = nil end
	local hit, u, v = nil, 0, 0
	if askedIndex then
		hit = askedIndex
	elseif canInput(now) then
		hit, u, v = pointerHit()
	end

	if hit ~= hoverIndex then
		hoverIndex = hit
		if hit then
			-- It rocks as the hand lands on it.
			bodies[hit].TurnVelocity += Vector3.new(0, 0, if u < 0 then Tune.HOVER_KICK else -Tune.HOVER_KICK)
			-- Every UI's hover, with the card's own over it.
			if not askedIndex then
				SoundsCore.PlayHover()
				SoundsCore.PlayUINamed(SOUNDS, "Hover")
			end
		end
	end
	if pressedIndex ~= hit then pressedIndex = nil end

	for index, body in bodies do
		if not body.IsShown or index > count then continue end
		if index ~= hit then
			local push = if not hit then 0 elseif index < hit then -Tune.NEIGHBOUR_PUSH else Tune.NEIGHBOUR_PUSH
			body.PointTarget = Vector3.new(body.Rest.X + push, body.Rest.Y, 1)
			body.TurnTarget = Vector3.zero
			continue
		end

		local isPressed = index == pressedIndex
		local tilt = if isPressed then Tune.PRESS_TILT else Tune.TILT
		body.PointTarget = Vector3.new(body.Rest.X, body.Rest.Y, if isPressed then Tune.PRESS_ZOOM else Tune.HOVER_ZOOM)
		body.TurnTarget = Vector3.new(-v * tilt, u * tilt, 0)
		cards[index].GlareAt(math.round(u * 40) / 40)
	end
end

-- A card goes back the way it came: under the right of the screen, turning face down.
local function undealBody(index: number)
	local body = bodies[index]
	slots[index].IsDealt = false
	body.Sway = 0
	body.PointTarget = Vector3.new(body.Rest.X + Tune.DEAL_FROM.X, Tune.DEAL_FROM.Y, Tune.DEAL_FROM.Z)
	body.PointFrequency = Tune.UNDEAL_FREQUENCY
	body.PointDamping = 1
	body.TurnTarget = Tune.DEAL_TURN
	body.TurnFrequency = Tune.UNDEAL_TURN_FREQUENCY
	body.TurnDamping = 1
	SoundsCore.PlayUINamed(SOUNDS, "Deal")
end

-- The cards once one is taken (`pickedIndex`, 0 when the hand was taken back): held up, then let go.
local function stepPicked(now: number)
	local since = now - phaseAt
	local chosen = bodies[pickedIndex]
	if chosen then
		local flash = Motion.Fade(now, phaseAt, Tune.FLASH_SECONDS)
		cards[pickedIndex].Flash(math.round(flash * flash * 30) / 30)
		if not isLeaving and since >= Tune.HOLD_SECONDS then
			isLeaving = true
			chosen.PointFrequency = Tune.LEAVE_FREQUENCY
			chosen.PointDamping = 1
			chosen.PointTarget = Tune.LEAVE_TO
			chosen.TurnTarget = Vector3.new(-0.7, 0, 0)
		end
	else
		for index, slot in slots do
			if slot.IsDealt and now >= slot.LeaveAt then undealBody(index) end
		end
	end
	if since < (if chosen then Tune.HOLD_SECONDS + Tune.LEAVE_SECONDS else undealSeconds) then return end

	local nextHand = queuedHand
	queuedHand = nil
	if nextHand then
		phase = "Open"
		phaseAt = now
		deal(nextHand, now)
	else
		close(now)
	end
end

-- A card was taken (or, with `index` 0, the hand was taken back: with the run, or for a boss).
local function showPicked(index: number, now: number)
	phase = "Picked"
	phaseAt = now
	pickedIndex = index
	isLeaving = false
	rerollTo = nil
	askedIndex, pressedIndex = nil, nil
	hoverIndex = if index > 0 then index else nil
	screen.IsCatching(false)
	setHeader(false, now)

	-- Taken back: each card dealt leaves in turn, the last one first.
	if index == 0 then
		local leaving = 0
		for bodyIndex = #bodies, 1, -1 do
			local slot = slots[bodyIndex]
			slot.LeaveAt = math.huge
			if not bodies[bodyIndex].IsShown or not slot.IsDealt then continue end
			slot.LeaveAt = now + leaving * Tune.DEAL_STAGGER
			leaving += 1
		end
		undealSeconds = math.max(leaving - 1, 0) * Tune.DEAL_STAGGER + Tune.UNDEAL_SECONDS
		return
	end

	for bodyIndex, body in bodies do
		if not body.IsShown then continue end
		if bodyIndex ~= index then
			toss(body)
			continue
		end

		body.Sway = 0
		body.PointFrequency = Tune.PICK_FREQUENCY
		body.PointDamping = Tune.PICK_DAMPING
		body.PointTarget = Vector3.new(Tune.PICK_POINT.X, Tune.PICK_POINT.Y, Tune.PICK_ZOOM)
		-- A whole turn behind where it is: it spins once on its way to facing the eye.
		body.Turn -= Vector3.new(0, 2 * math.pi, 0)
		body.TurnTarget = Vector3.zero
		body.TurnFrequency = Tune.SPIN_FREQUENCY
		body.TurnDamping = Tune.SPIN_DAMPING
		screen.PickedColor(Card.RarityColor(cards[bodyIndex].Rarity()))
		screen.PickedAt(now)
		pickClockUntil = now + Screen.Seconds.PICK
		SoundsCore.PlayUINamed(SOUNDS, PICK_SOUNDS[cards[bodyIndex].Rarity()])
		TweensController.PunchFov(Tune.FOV_PUNCH, Tune.FOV_RETURN)
	end
end

-- The pick seen on `player`'s body, if it has one, and heard from it.
local function showOnBody(player: Player, rarity: number)
	local characterEntity = getCharacterEntityFromPlayer(player)
	local root = if characterEntity then World:get(characterEntity, Components.HumanoidRootPart) else nil
	if not root then return end
	upgradeFx.Cast(root, rarity)
	SoundsCore.PlayNamedOnPart(BODY_SOUNDS, "LevelUp", root)
end

local function step(dt: number)
	if phase == "Closed" then return end
	local now = os.clock()
	local viewport = Workspace.CurrentCamera.ViewportSize
	local scale = math.clamp(viewport.Y / Theme.DESIGN_HEIGHT, Theme.MIN_SCALE, Theme.MAX_SCALE)
	local since = now - phaseAt
	screen.Scale(scale)

	-- The curtain brings the HUD under his dim, and the dim in the world takes over as the HUD goes.
	local curtain, dim = 0, Tune.DIM
	if phase == "Opening" then
		curtain, dim = Tune.DIM * math.min(since / Tune.CURTAIN_SECONDS, 1), 0
		if since >= Tune.CURTAIN_SECONDS and hand then
			phase = "Open"
			phaseAt = now
			UpgradePickController.IsCovering(true)
			curtain, dim = 0, Tune.DIM
			deal(hand, now)
		end
	elseif phase == "Closing" then
		curtain, dim = Tune.DIM * (1 - math.min(since / Tune.CLOSE_SECONDS, 1)), 0
	end
	screen.Curtain(math.round(curtain * 100) / 100)
	dimOpacity(dim)

	local current = hand
	if phase == "Open" and current then
		stepDeal(now, dt)
		if rerollTo then
			stepReroll(rerollTo, now)
		else
			stepHover(#current.Cards, now)
		end
	elseif phase == "Picked" then
		stepPicked(now)
	end

	-- The hand's light and the losers' shade ease in and out, in steps a source can hold still on.
	for index, body in bodies do
		local slot = slots[index]
		local isHeld = body.IsShown and index == hoverIndex
		local isShaded = phase == "Picked" and pickedIndex > 0 and index ~= pickedIndex
		slot.Hover = math.clamp(slot.Hover + (if isHeld then dt else -dt) * Tune.HOVER_RATE, 0, 1)
		slot.Shade = math.clamp(slot.Shade + (if isShaded then dt else -dt) * Tune.SHADE_RATE, 0, 1)
		cards[index].Hover(math.round(slot.Hover * 20) / 20)
		cards[index].Shade(math.round(slot.Shade * 20) / 20)
		cards[index].Order(if isHeld then 1 else 0)
	end

	stage:Step(dt, now, scale)
	for index, body in bodies do
		local sources = cards[index]
		-- Only while the hand is up: the pick's spin turns the card over too.
		if phase == "Open" and body.IsFaceUp and not sources.IsFaceUp() then
			local reveal = REVEAL_SOUNDS[sources.Rarity()]
			if reveal then SoundsCore.PlayUINamed(SOUNDS, reveal) end
		end
		sources.IsFaceUp(body.IsFaceUp)
		-- Held through the pick's spin and the way out, which turn the card over too.
		if phase == "Opening" or phase == "Open" then sources.IsRevealed(body.IsFaceUp) end
	end

	if current then
		local left = math.max(math.ceil(pickAt - now), 0)
		if left ~= screen.SecondsLeft() then
			screen.SecondsLeft(left)
			stamp(screen.TickAt, now, Screen.Seconds.TICK)
			if phase == "Open" and left >= 1 and left <= Tune.TICK_SECONDS then
				SoundsCore.PlayUINamed(SOUNDS, "Tick")
			end
		end
		screen.CanReroll(MatchController.Gold >= current.RerollPrice)
	end

	-- Written only while a gesture runs: a hand at rest redraws nothing on the screen.
	screen.Clock(if now < clockUntil then now else math.huge)
	screen.PickClock(if now < pickClockUntil then now else math.huge)
	-- Read again, not `since`: a close that the pick started this frame has only just begun.
	if phase ~= "Closing" or now - phaseAt < Tune.CLOSE_SECONDS then return end
	phase = "Closed"
	screen.Clock(math.huge)
	screen.IsEnabled(false)
	stage:SetParent(nil)
	CameraController.SetMouseFreed("UpgradePick", false)
	ContextActionService:UnbindAction("UpgradePick")

	-- After the curtain, so the body's light is not dimmed under it.
	if takenRarity > 0 then showOnBody(LocalPlayer, takenRarity) end
	takenRarity = 0
end

-- The tag that is `player`'s; with nil, a free one.
local function findTag(player: Player?): TTag?
	for _, tag in tags do
		if tag.Player == player then return tag end
	end

	return nil
end

-- Frees a tag, hidden at once.
local function releaseTag(tag: TTag)
	tag.Player = nil
	tag.IsPicking = false
	tag.Adornee(nil)
end

-- The teammates' tags: each one's clock and body while it is up, and a tag that has shrunk away is let go.
local function stepTags(now: number)
	if not isAnyTagUp then return end
	local viewport = Workspace.CurrentCamera.ViewportSize
	tagScale(math.clamp(viewport.Y / Theme.DESIGN_HEIGHT, Theme.MIN_SCALE, Theme.MAX_SCALE))

	local isUp = false
	for _, tag in tags do
		local player = tag.Player
		if not player then continue end
		if not tag.IsPicking and now >= tag.EndedAt() + PickingTag.OUT_SECONDS then
			releaseTag(tag)
			continue
		end

		isUp = true
		tag.Clock(now)
		local characterEntity = getCharacterEntityFromPlayer(player)
		tag.Adornee(if characterEntity then World:get(characterEntity, Components.HumanoidRootPart) else nil)
	end

	isAnyTagUp = isUp
end

local function stepFrame()
	stepTags(os.clock())
	step(frameDt)
end

-- The d-pad walks the cards, A takes the one it is on and X asks for a new hand. Bound only while a hand is up.
local function onAction(_, inputState: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Sink end
	local keyCode = input.KeyCode
	if keyCode == Enum.KeyCode.DPadLeft or keyCode == Enum.KeyCode.DPadRight then
		local count = if hand then #hand.Cards else 0
		if count == 0 then return Enum.ContextActionResult.Sink end
		local move = if keyCode == Enum.KeyCode.DPadLeft then -1 else 1
		padIndex = math.clamp((padIndex or math.ceil(count / 2) - move) + move, 1, count)
	elseif keyCode == Enum.KeyCode.ButtonA then
		if padIndex then ask(padIndex) end
	elseif keyCode == Enum.KeyCode.ButtonX then
		reroll()
	end

	return Enum.ContextActionResult.Sink
end

local function open(newHand: THand)
	local now = os.clock()
	phase = "Opening"
	phaseAt = now
	hand = newHand
	stage:SetParent(Workspace.CurrentCamera)
	screen.IsEnabled(true)
	screen.IsCatching(true)
	CameraController.SetMouseFreed("UpgradePick", true)
	SoundsCore.SetMuffled("UpgradePick", true)
	SoundsCore.PlayUINamed(SOUNDS, "Open")
	ContextActionService:BindActionAtPriority(
		"UpgradePick",
		onAction,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.DPadLeft,
		Enum.KeyCode.DPadRight,
		Enum.KeyCode.ButtonA,
		Enum.KeyCode.ButtonX
	)
end

-- A finger's place in raw viewport px (an InputObject's is in the inset space).
local function touchPoint(input: InputObject): Vector2
	local inset = GuiService:GetGuiInset()
	return Vector2.new(input.Position.X + inset.X, input.Position.Y + inset.Y)
end

local function isPointerButton(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

-- A hand from the server: dealt, queued behind a pick still being shown, or turned over in place of the one that is
-- up. Public for a bench, which deals without a server.
function UpgradePickController.Show(newHand: THand)
	if not newHand.IsReroll then MatchController.MarkWaveDone(newHand.Round) end

	local now = os.clock()
	if phase == "Closed" or phase == "Closing" then
		open(newHand)
	elseif phase == "Picked" then
		queuedHand = newHand
	elseif phase == "Opening" then
		hand = newHand
	elseif newHand.IsReroll then
		SoundsCore.PlayUINamed(SOUNDS, "Reroll")
		hand = newHand
		rerollTo = newHand
		rerollAt = now
		pickAt = now + newHand.Seconds
		inputFrom = now + Tune.REROLL_LOCK
		pressedIndex = nil
		screen.RerollPrice(newHand.RerollPrice)
	else
		deal(newHand, now)
	end
end

-- The server closed the hand: card `index` of it was taken, or none (0) when it was taken back (the run over, a boss
-- coming).
function UpgradePickController.Resolve(index: number)
	local current = hand
	local card = if current then current.Cards[index] else nil
	local data = if card then UPGRADES[card.Id] else nil
	if card and data then stats[card.Id] = (stats[card.Id] or 0) + UpgradesCore.Amount(data, card.Rarity) end
	if card then takenRarity = math.max(takenRarity, card.Rarity) end

	if phase == "Opening" then
		-- Taken before a card was dealt: there is nothing to show.
		close(os.clock())
	elseif phase == "Open" then
		showPicked(index, os.clock())
	elseif phase == "Picked" and index == 0 then
		-- The hand taken back was the one waiting behind the pick still being shown.
		queuedHand = nil
	end
end

ServerNetworkUpgrades.Offer.On(UpgradePickController.Show)

ServerNetworkUpgrades.Picked.On(UpgradePickController.Resolve)

ServerNetworkUpgrades.Reset.On(function()
	table.clear(stats)
	queuedHand = nil
end)

-- A teammate's pick: their tag comes up, flashes the rarity of the card they take, and shrinks away when they are done.
ServerNetworkUpgrades.Picking.On(function(player: Player, isPicking: boolean, rarity: number)
	if player == LocalPlayer then
		UpgradePickController.IsPicking = isPicking
		return
	end
	local now = os.clock()

	if not isPicking then
		local tag = findTag(player)
		if not tag or not tag.IsPicking then return end
		tag.IsPicking = false
		tag.EndedAt(now)
		if tag.Rarity > 0 then showOnBody(player, tag.Rarity) end
		return
	end

	-- Theirs, still up or on its way out, else a free one.
	local tag = findTag(player) or findTag(nil)
	if not tag then return end
	if not tag.IsPicking then
		tag.Player = player
		tag.IsPicking = true
		tag.ShownAt(now)
		tag.PickedAt(-math.huge)
		tag.EndedAt(math.huge)
		tag.Rarity = 0
	end
	if rarity > 0 then
		tag.PickedColor(Card.RarityColor(rarity))
		tag.PickedAt(now)
		tag.Rarity = math.max(tag.Rarity, rarity)
	end
	isAnyTagUp = true
end)

-- A leaver's tag goes with them.
UpgradePickController.OnPlayerDisconnected = function(player: Player)
	local tag = findTag(player)
	if tag then releaseTag(tag) end
end :: TPlayerEvents.OnPlayerDisconnected

UpgradePickController.OnStart = function()
	vide.mount(function()
		local guis = { Screen.Build(screen, { Reroll = reroll }) }
		guis[2] = create("SurfaceGui")({
			Name = "UpgradeDim",
			Adornee = stage.Dim,
			Face = Enum.NormalId.Back,
			ResetOnSpawn = false,
			LightInfluence = 0,
			SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
			CanvasSize = Vector2.new(64, 64),
			Enabled = function()
				return dimOpacity() > 0
			end,
			create("Frame")({
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Color3.new(),
				BorderSizePixel = 0,
				BackgroundTransparency = function()
					return 1 - dimOpacity()
				end,
			}),
		})
		for index, sources in cards do
			guis[index + 2] = create("SurfaceGui")({
				Name = `UpgradeCard{index}`,
				Adornee = bodies[index].Part,
				Face = Enum.NormalId.Back,
				ResetOnSpawn = false,
				AlwaysOnTop = true,
				LightInfluence = 0,
				-- Fixed: the canvas is stretched over the part, whatever size the stage gives it.
				SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
				CanvasSize = Card.CANVAS * Tune.RESOLUTION,
				Enabled = sources.IsShown,
				ZOffset = sources.Order,
				create("Frame")({
					Name = "Root",
					Size = UDim2.fromOffset(Card.CANVAS.X, Card.CANVAS.Y),
					BackgroundTransparency = 1,
					create("UIScale")({ Scale = Tune.RESOLUTION }),
					Card.Build(sources),
				}),
			})
		end
		for _, tag in tags do
			guis[#guis + 1] = PickingTag.Build(tag, tagScale)
		end

		return guis
	end, LocalPlayer:WaitForChild("PlayerGui"))

	-- After CameraController's (Camera + 1), so the cards and the dim stand on the view as it is drawn, the shoulder
	-- lock's offset included. Two connections to one event have no promised order, and the cards were left off to
	-- the side under the lock.
	RunService:BindToRenderStep("UpgradePick", Enum.RenderPriority.Camera.Value + 2, function(dt: number)
		frameDt = dt
		vide.batch(stepFrame)
		upgradeFx.Step()
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject)
		if not isPointerButton(input) or not canInput(os.clock()) then return end
		padIndex = nil
		if input.UserInputType == Enum.UserInputType.Touch then touchAt = touchPoint(input) end
		pressedIndex = pointerHit()
	end)

	UserInputService.InputChanged:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			padIndex = nil
		elseif input.UserInputType == Enum.UserInputType.Touch and touchAt then
			touchAt = touchPoint(input)
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if not isPointerButton(input) then return end
		if input.UserInputType == Enum.UserInputType.Touch then touchAt = touchPoint(input) end
		local released = pressedIndex
		pressedIndex = nil
		local hit = if canInput(os.clock()) then pointerHit() else nil
		touchAt = nil
		if released and hit == released then ask(released) end
	end)
end

return Ignis.Register(UpgradePickController)
