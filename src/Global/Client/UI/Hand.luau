--!nonstrict
-- How a button answers the hand, one reaction for every button so they all feel alike (UI.md 5f): it rises and lights
-- under the pointer with a glint across it, goes in on the frame it is pressed and pops as the press goes through.
-- Everything here is a vide spring, so it runs on vide's own clock and needs no screen's clock ticking.
--
-- A thing you TAKE (a card, a pack) moves and lights more than a thing you OPERATE (SKIP WAVE, a switch). A button
-- that cannot be used right now (not enough Gold, cooling down) still answers, in kind rather than in strength: a
-- smaller rise, no light thrown outward, no glint and no pop, since a pop says something happened and the server is
-- about to refuse it. Its press still goes in, or the screen did not hear the click.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.vide)

local action = vide.action
local create = vide.create
local source = vide.source
local spring = vide.spring
local derive = vide.derive

-- Each kind's reach, as shares of its size: the rise under the pointer, how far in a press takes it from there, the pop
-- as the press goes through, and the white washed over its face under the pointer and under the press.
-- The pop is kept small: on top of the rise it is what a press peaks at (Take 1.085, Operate 1.05), and a big card
-- that grew more pushed its brackets into the next one's.
local KINDS = table.freeze({
	Take = table.freeze({ Lift = 0.06, Press = 0.11, Pop = 0.03, WashHover = 0.07, WashPress = 0.2 }),
	Operate = table.freeze({ Lift = 0.035, Press = 0.07, Pop = 0.02, WashHover = 0.09, WashPress = 0.22 }),
})
-- What a button that cannot be used keeps of the rise and of the light it washes over its face.
local DEAD_RISE = 0.4
local DEAD_LIGHT = 0.3
-- A wash fainter than this (under a tenth of a step of 8-bit alpha) is taken out of the renderer.
local WASH_FLOOR = 0.0004
-- The rise is a movement and ticks a little past its mark; the light and the press are acknowledgements and land on
-- the frame (UI.md 5f, "The rise and the light are two different speeds"). Periods in seconds.
local Tune = table.freeze({
	RISE_PERIOD = 0.26,
	RISE_DAMPING = 0.6,
	LIGHT_PERIOD = 0.1,
	PRESS_PERIOD = 0.08,
	-- The pop rings once and dies. It rests at 0 and is struck with a position and a velocity together: the position
	-- gives vide's settle test a tolerance (it is a share of the last position written, so a spring struck at exactly
	-- 0 never retires), and the two are scaled so the pop peaks at 1, 50 ms after the strike.
	POP_PERIOD = 0.3,
	POP_DAMPING = 0.38,
	POP_KICK = 0.385,
	POP_SPEED = 30.8,
	-- The glint's travel, 0 to 1 over about 0.3 s: thrown from 0 toward GLINT_END so it is still moving fast as it
	-- leaves the face at 1, rather than creeping onto it.
	GLINT_PERIOD = 1,
	GLINT_SPEED = 2.2,
	GLINT_END = 1.6,
})

export type TKind = "Take" | "Operate"

export type TReaction = {
	-- To put among the button's properties.
	Events: { [any]: any },
	IsHovered: () -> boolean,
	IsPressed: () -> boolean,
	-- For the UIScale on what moves.
	Scale: () -> number,
	-- 0 to 1 and a little past: the rise, for a picture on the button to grow with.
	Rise: () -> number,
	-- 0 to 1: the light under the pointer, swelling under the press; for the glow, the brackets, the edge. Always 0 on
	-- a button that cannot be used: only one that can throws light outward.
	Light: () -> number,
	-- How opaque a white wash over the face is.
	Wash: () -> number,
	-- A Components.Sheen's travel: 1 at rest, 0 to 1 as the glint crosses.
	Glint: () -> number,
	-- Call from Activated when the press went through: it pops and glints.
	Commit: () -> (),
}

local Hand = {}

local function always(): boolean
	return true
end

-- A spring toward `target`, pinned on each change of target: one heading back to 0 otherwise never settles (UI.md
-- 5g), and a stepping spring reruns everything hung off it every frame. The goal is derived, so a source the target
-- reads that changes without moving it (Gold on every kill, a cooldown every frame) neither pins nor wakes it.
function Hand.Spring(target: () -> number, period: number, damping: number?): () -> number
	local goal = derive(function(): number
		return target()
	end)
	local value, configure = spring(goal, period, damping or 1)
	vide.effect(function()
		goal()
		vide.untrack(function()
			configure({ position = value() })
		end)
	end)

	return value
end

-- A one-shot spring resting at 0: `strike(position)` throws it there, and it rings back home.
function Hand.Kick(period: number, damping: number): (() -> number, (number) -> ())
	local value, configure = spring(function()
		return 0
	end, period, damping)
	return value, function(position: number)
		configure({ position = position, velocity = 0 })
	end
end

-- Whether the pointer can reach `instance`: nothing on its way up to its LayerCollector is Interactable = false.
-- Roblox fires MouseEnter on every button under the pointer, covered or not, and an Active cover does not stop it in
-- the lobby's SurfaceGui. So a screen turns off what lies under a menu it opens, and a hover asks this first.
function Hand.IsReachable(instance: Instance): boolean
	local current: Instance? = instance
	-- One IsA a level: a GUI's ancestors are GuiObjects up to its LayerCollector, which is not one.
	while current do
		if current:IsA("GuiObject") then
			if not current.Interactable then return false end
		elseif current:IsA("LayerCollector") then
			break
		end
		current = current.Parent
	end

	return true
end

-- What the hand is doing to a button: the events to put on it, and whether it is over it and down on it. `onEnter`
-- runs as the pointer arrives.
function Hand.Track(onEnter: (() -> ())?): ({ [any]: any }, () -> boolean, () -> boolean)
	local isHovered = source(false)
	local isPressed = source(false)
	local button: Instance? = nil

	local function enter()
		isHovered(true)
		if onEnter then onEnter() end
	end
	local function leave()
		isHovered(false)
		isPressed(false)
	end
	local events = {
		action(function(instance: Instance)
			button = instance
		end),
		MouseEnter = function()
			if button and not Hand.IsReachable(button) then return end
			enter()
		end,
		MouseLeave = leave,
		-- Neither MouseEnter nor MouseLeave fires when what covers the button comes or goes under a still pointer, so a
		-- move over it settles which it is.
		MouseMoved = function()
			if not button then return end
			local isReachable = Hand.IsReachable(button)
			if isReachable == isHovered() then return end
			if isReachable then
				enter()
			else
				leave()
			end
		end,
		MouseButton1Down = function()
			isPressed(true)
		end,
		MouseButton1Up = function()
			isPressed(false)
		end,
		-- A finger lifted is a hand gone: a tap fires MouseEnter but not reliably MouseLeave, so a tapped button would
		-- stay raised.
		InputEnded = function(input: InputObject)
			if input.UserInputType ~= Enum.UserInputType.Touch then return end
			leave()
		end,
	}

	return events, isHovered, isPressed
end

-- The reaction of a button of `kind`. `isLive` says whether it can be used right now; nil for always.
function Hand.React(kind: TKind, isLive: (() -> boolean)?): TReaction
	local reach = KINDS[kind]
	-- Derived, so what the caller's test reads changing every frame reaches nothing here unless the answer flips. Called
	-- with no arguments: derive hands its function the last value, and `isLive` may be a source, which that would set.
	local live = if isLive
		then derive(function(): boolean
			return isLive()
		end)
		else always

	local glintTravel, throw = spring(function()
		return Tune.GLINT_END
	end, Tune.GLINT_PERIOD, 1)
	-- Derived, so the travel's slow last second toward GLINT_END redraws nothing past the face.
	local glint = derive(function(): number
		return math.min(glintTravel(), 1)
	end)
	local function glintOnce()
		throw({ position = 0, velocity = Tune.GLINT_SPEED })
	end

	local events, isHovered, isPressed = Hand.Track(function()
		if live() then glintOnce() end
	end)
	local rise = Hand.Spring(function()
		if not isHovered() then return 0 end
		return if live() then 1 else DEAD_RISE
	end, Tune.RISE_PERIOD, Tune.RISE_DAMPING)
	local light = Hand.Spring(function()
		if not isHovered() then return 0 end
		return if live() then 1 else DEAD_LIGHT
	end, Tune.LIGHT_PERIOD)
	local press = Hand.Spring(function()
		return if isPressed() then 1 else 0
	end, Tune.PRESS_PERIOD)
	local pop, strike = spring(function()
		return 0
	end, Tune.POP_PERIOD, Tune.POP_DAMPING)

	-- Derived: the glow, the edge and the brackets all read it, and it holds 0 at rest whatever `live` does.
	local outward = derive(function(): number
		if not live() then return 0 end
		return math.clamp(light() + 0.5 * press(), 0, 1)
	end)

	return {
		Events = events,
		IsHovered = isHovered,
		IsPressed = isPressed,
		Scale = function(): number
			return 1 + reach.Lift * rise() - reach.Press * press() + reach.Pop * pop()
		end,
		Rise = rise,
		Light = outward,
		Wash = function(): number
			return reach.WashHover * math.clamp(light(), 0, 1) + reach.WashPress * press()
		end,
		Glint = glint,
		Commit = function()
			if not live() then return end
			strike({ position = Tune.POP_KICK, velocity = Tune.POP_SPEED })
			glintOnce()
		end,
	}
end

-- A Components.Sheen's travel for a button that already has a light of its own (`other`, 1 at rest): the hand's
-- glint while it crosses, `other` the rest of the time, so the two share one layer.
function Hand.Sheen(reaction: TReaction, other: () -> number): () -> number
	local glint = reaction.Glint
	return function(): number
		local travel = glint()
		return if travel < 1 then travel else other()
	end
end

-- The white the hand washes over a face, under what is written on it (`zIndex` among its siblings). `cornerPx` rounds
-- it to the face's corners; nil for square. Out of the renderer while there is none: a layer at full transparency is
-- still drawn (UI.md 5g), and every button has one.
function Hand.WashLayer(reaction: TReaction, zIndex: number, cornerPx: number?): Frame
	local wash = reaction.Wash
	local isWashed = derive(function(): boolean
		return wash() > WASH_FLOOR
	end)

	return create("Frame")({
		Name = "Wash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = zIndex,
		Visible = isWashed,
		BackgroundTransparency = function()
			return 1 - wash()
		end,
		if cornerPx then create("UICorner")({ CornerRadius = UDim.new(0, cornerPx) }) else nil,
	})
end

return Hand
