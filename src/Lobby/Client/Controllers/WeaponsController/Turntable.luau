--!nonstrict
-- The gun on the stage taken in the hand. A drag turns it round its up and tips it toward or away (held in by a rubber
-- band), a quick one throws it spinning, and a press that barely moved flicks it a whole turn away from the side it
-- poked. Let go, it always comes home: a throw coasts on and lands on the whole turn nearest where it would have
-- stopped, a still release holds a beat and eases back. Angles are the gun's own, in degrees: a positive turn takes
-- its near side to the right, a positive tip brings its top toward the viewer.
--
-- Stepped by the stage's clock, which runs only while the screen is drawn; its drag listens to the whole screen only
-- while it holds.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local UserInputService = game:GetService("UserInputService")
local vide = require(ReplicatedStorage.Packages.vide)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)

local create = vide.create
local source = vide.source
local spring = vide.spring

-- Degrees a design px of drag turns and tips it; the tip's soft limit; the fastest throw (deg a second); how much of
-- the pointer's speed each move keeps, and how long it may rest before letting go and still throw; how far a press
-- may move (design px) before it is a drag.
local Drag = table.freeze({
	TURN_PER_PX = 0.45,
	TIP_PER_PX = 0.3,
	TIP_LIMIT = 35,
	MAX_THROW = 1500,
	SMOOTHING = 0.6,
	STILL_SECONDS = 0.1,
	CLICK_PX = 6,
})

-- The way home. A throw lands on the whole turn nearest where it would coast to in CARRY seconds, in a time that
-- leaves at the throw's own speed and lands still (a cubic ease out), held between the two limits. One too slow to
-- reach the next turn swings on a little and comes back, and a still release waits WAIT first: both take BACK seconds
-- and a share more for each degree it is off, at most BACK_MAX. A flick is one turn in FLICK seconds.
local Glide = table.freeze({
	CARRY = 0.45,
	MIN_SECONDS = 0.45,
	MAX_SECONDS = 1.6,
	WAIT = 0.45,
	BACK = 0.55,
	BACK_PER_DEG = 1 / 500,
	BACK_MAX = 1,
	FLICK = 0.9,
})

-- The feel under the hand: the most it leans (deg) with its spin and the spin that gets three quarters of that, how
-- quickly the lean follows; how much it grows under the hand and in it, and on a flick; how quickly the idle sway stops
-- as the hand takes it, so it does not drift under the hand, and starts again once it is home.
local Feel = table.freeze({
	LEAN = 5,
	LEAN_SPEED = 600,
	LEAN_SECONDS = 0.08,
	HOVER = 0.025,
	HELD = 0.05,
	LIFT_PERIOD = 0.17,
	LIFT_DAMPING = 0.82,
	FLICK_POP = 0.06,
	POP_PERIOD = 0.26,
	POP_DAMPING = 0.58,
	SWAY_STOP = 0.08,
	SWAY_START = 0.4,
})

-- One angle's way home: a cubic from `From`, leaving at `Slope` (degrees over the whole glide), to `To`, arriving still.
type TCurve = { From: number, Slope: number, To: number }

-- The glide home: when it starts (os.clock), how long it takes, and its two curves.
type TGlide = { At: number, Seconds: number, Turn: TCurve, Tip: TCurve }

export type TTurntable = {
	-- The gun's turn and tip from the hand, in degrees, and its lean in the picture's plane.
	Turn: () -> number,
	Tip: () -> number,
	Lean: () -> number,
	-- How much bigger the hand makes it: under it, in it, and a flick's pop.
	Grown: () -> number,
	-- Seconds of the stage's clock that ran while it was left alone, eased in and out: what the idle sway reads, so
	-- the sway stops under the hand and starts again from where it stood.
	IdleClock: () -> number,
	-- The button that takes the hand over the gun.
	Grab: TextButton,
}

local Turntable = {}

-- Where `curve` stands at s (0 to 1 through the glide), and its slope there.
local function along(curve: TCurve, s: number): (number, number)
	local s2, s3 = s * s, s * s * s
	local at = (2 * s3 - 3 * s2 + 1) * curve.From + (s3 - 2 * s2 + s) * curve.Slope + (-2 * s3 + 3 * s2) * curve.To
	local slope = (6 * s2 - 6 * s) * curve.From + (3 * s2 - 4 * s + 1) * curve.Slope + (-6 * s2 + 6 * s) * curve.To
	return at, slope
end

-- `clock` is the stage's (os.clock, ticking while it is drawn), `scale` the screen's UIScale (pointer px to design
-- px), `isActive` whether the screen is open and `reset` changes when another gun comes on: each lets go and puts it
-- home at once. `props` place the grab button over the gun.
function Turntable.Build(
	clock: () -> number,
	scale: () -> number,
	isActive: () -> boolean,
	reset: () -> any,
	props: { [any]: any }
): TTurntable
	local turn = source(0)
	local tip = source(0)
	local lean = source(0)
	local idleClock = source(0)
	local isHovered = source(false)
	local isHeld = source(false)
	local lift = spring(function(): number
		return (if isHovered() then Feel.HOVER else 0) + (if isHeld() then Feel.HELD else 0)
	end, Feel.LIFT_PERIOD, Feel.LIFT_DAMPING)
	local pop, strikePop = Hand.Kick(Feel.POP_PERIOD, Feel.POP_DAMPING)

	-- Where it stands and how fast it turns (deg a second); the tip before its rubber band.
	local turnDeg, tipDeg, rawTip = 0, 0, 0
	local turnSpeed, tipSpeed = 0, 0
	local leanDeg = 0
	local glide: TGlide? = nil
	-- The idle clock's rate (0 under the hand, 1 left alone) and the stage clock's last tick.
	local idleRate, idleAt, lastAt = 1, 0, clock()
	-- The drag: the pointer's last place (design px) and when it moved, how far it moved in all, where it was taken
	-- (px right of the gun's middle), and its listeners.
	local dragFrom: Vector2? = nil
	local dragAt = 0
	local dragMoved = 0
	local grabX = 0
	local connections: { RBXScriptConnection } = {}

	-- One batch, so the picture's camera, which reads them all, moves once.
	local function publish()
		vide.batch(function()
			idleClock(idleAt)
			turn(turnDeg)
			tip(tipDeg)
			lean(leanDeg)
		end)
	end

	-- Home: a whole turn is the same pose as 0, so the turn is wound back there. The lean is left to settle on its own.
	local function land()
		turnDeg, tipDeg, rawTip, turnSpeed, tipSpeed = 0, 0, 0, 0, 0
		glide = nil
	end

	local function home()
		land()
		leanDeg = 0
		publish()
	end

	-- Sends it home from where it stands at its own speed, after `waitSeconds`. The turn lands on a whole turn, so the
	-- gun faces the way it always does, and is wound back to 0 there.
	local function sendHome(target: number, seconds: number, waitSeconds: number)
		local tipSlope = math.clamp(tipSpeed * seconds, -Drag.TIP_LIMIT, Drag.TIP_LIMIT)
		glide = {
			At = os.clock() + waitSeconds,
			Seconds = seconds,
			Turn = { From = turnDeg, Slope = turnSpeed * seconds, To = target },
			Tip = { From = tipDeg, Slope = tipSlope, To = 0 },
		}
	end

	-- How long the way back takes from `offDeg` away, at no speed of its own to speak of.
	local function back(offDeg: number): number
		return math.min(Glide.BACK + offDeg * Glide.BACK_PER_DEG, Glide.BACK_MAX)
	end

	local function throw()
		local isStill = os.clock() - dragAt > Drag.STILL_SECONDS
		if isStill then
			turnSpeed, tipSpeed = 0, 0
			local target = 360 * math.round(turnDeg / 360)
			local off = math.max(math.abs(target - turnDeg), math.abs(tipDeg))
			sendHome(target, back(off), Glide.WAIT)
			return
		end

		local target = 360 * math.round((turnDeg + turnSpeed * Glide.CARRY) / 360)
		local ahead = target - turnDeg
		-- A cubic ease out leaves at three times its average speed: the time that makes it leave at the throw's.
		local seconds = if ahead * turnSpeed > 0
			then math.clamp(3 * ahead / turnSpeed, Glide.MIN_SECONDS, Glide.MAX_SECONDS)
			else back(math.max(math.abs(ahead), math.abs(tipDeg)))
		sendHome(target, seconds, 0)
	end

	local function flick()
		local side = if grabX >= 0 then 1 else -1
		local target = 360 * math.round(turnDeg / 360) + 360 * side
		turnSpeed = 3 * (target - turnDeg) / Glide.FLICK
		tipSpeed = 0
		sendHome(target, Glide.FLICK, 0)
		strikePop(Feel.FLICK_POP)
	end

	local function release()
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
		dragFrom = nil
		isHeld(false)
	end

	local function letGo()
		local wasClick = dragMoved < Drag.CLICK_PX
		release()
		if wasClick then
			flick()
		else
			throw()
		end
	end

	-- Moves only the locals: a mouse can report several moves a frame, and the step publishes once.
	local function drag(moved: InputObject, input: InputObject)
		local isMove = moved.UserInputType == Enum.UserInputType.MouseMovement
			or (moved.UserInputType == Enum.UserInputType.Touch and moved == input)
		if not isMove or not dragFrom then return end

		local at = Vector2.new(moved.Position.X, moved.Position.Y) / scale()
		local delta = at - dragFrom
		local now = os.clock()
		local dt = math.max(now - dragAt, 1 / 240)
		dragFrom = at
		dragAt = now
		dragMoved += delta.Magnitude

		local turnBy = delta.X * Drag.TURN_PER_PX
		turnDeg += turnBy
		rawTip += delta.Y * Drag.TIP_PER_PX
		local tipWas = tipDeg
		tipDeg = Drag.TIP_LIMIT * math.tanh(rawTip / Drag.TIP_LIMIT)
		-- Smoothed, so a throw is the pointer's last few moves and not its last frame.
		local keep = Drag.SMOOTHING
		turnSpeed = keep * turnSpeed + (1 - keep) * math.clamp(turnBy / dt, -Drag.MAX_THROW, Drag.MAX_THROW)
		tipSpeed = keep * tipSpeed + (1 - keep) * (tipDeg - tipWas) / dt
	end

	local function grab(input: InputObject, fromMiddleX: number)
		local isPointer = input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		if not isPointer or dragFrom or not isActive() then return end

		-- Caught where it is, mid-glide or not: the hand takes it from there.
		glide = nil
		turnSpeed, tipSpeed = 0, 0
		-- The rubber band undone (atanh, which Luau's math lacks), so the drag carries on from where the tip stands.
		local share = math.clamp(tipDeg / Drag.TIP_LIMIT, -0.999, 0.999)
		rawTip = Drag.TIP_LIMIT * 0.5 * math.log((1 + share) / (1 - share))
		dragFrom = Vector2.new(input.Position.X, input.Position.Y) / scale()
		dragAt = os.clock()
		dragMoved = 0
		grabX = fromMiddleX
		isHeld(true)

		-- The whole screen, not the gun: a drag may leave it.
		connections[1] = UserInputService.InputChanged:Connect(function(moved: InputObject)
			drag(moved, input)
		end)
		connections[2] = UserInputService.InputEnded:Connect(function(ended: InputObject)
			if ended.UserInputType == input.UserInputType then letGo() end
		end)
	end

	local function step(now: number)
		local dt = math.clamp(now - lastAt, 0, 0.1)
		lastAt = now
		local isEngaged = dragFrom ~= nil or glide ~= nil
		local swaySeconds = if isEngaged then Feel.SWAY_STOP else Feel.SWAY_START
		idleRate += ((if isEngaged then 0 else 1) - idleRate) * (1 - math.exp(-dt / swaySeconds))
		idleAt += dt * idleRate

		local current = glide
		if dragFrom then
			-- A pointer that stopped is not spinning it.
			if now - dragAt > Drag.STILL_SECONDS then turnSpeed = 0 end
		elseif current then
			local s = (now - current.At) / current.Seconds
			if s >= 1 then
				land()
			elseif s > 0 then
				local slope
				turnDeg, slope = along(current.Turn, s)
				turnSpeed = slope / current.Seconds
				tipDeg = along(current.Tip, s)
			end
		elseif leanDeg == 0 then
			idleClock(idleAt)
			return
		end

		local leanTo = -Feel.LEAN * math.tanh(turnSpeed / Feel.LEAN_SPEED)
		leanDeg += (leanTo - leanDeg) * (1 - math.exp(-dt / Feel.LEAN_SECONDS))
		if not isEngaged and math.abs(leanDeg) < 0.01 then leanDeg = 0 end
		publish()
	end

	vide.effect(function()
		local now = clock()
		vide.untrack(function()
			step(now)
		end)
	end)

	vide.effect(function()
		reset()
		local active = isActive()
		vide.untrack(function()
			release()
			if not active then isHovered(false) end
			home()
		end)
	end)

	vide.cleanup(release)

	local button: TextButton
	button = create("TextButton")({
		Name = "Grab",
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		MouseEnter = function()
			isHovered(true)
		end,
		MouseLeave = function()
			isHovered(false)
		end,
		-- An InputObject is in AbsolutePosition's space already (UI.md, "A GUI mouse event is in RAW screen space").
		InputBegan = function(input: InputObject)
			grab(input, input.Position.X - (button.AbsolutePosition.X + button.AbsoluteSize.X / 2))
		end,
		props,
	}) :: TextButton

	return {
		Turn = turn,
		Tip = tip,
		Lean = lean,
		Grown = function(): number
			return lift() + pop()
		end,
		IdleClock = idleClock,
		Grab = button,
	}
end

return Turntable
