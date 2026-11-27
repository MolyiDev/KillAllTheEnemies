-- Inertialization (Bollo, "Inertialization: High-Performance Animation Transitions in Gears of War", GDC 2018) for a
-- rig's joints, Bones or Motor6Ds alike. A clip switch is cut, and what the joints showed before it is carried as an
-- offset over the new pose that dies away on a quintic, leaving with the old motion's speed and never overshooting.
-- The engine's own fade is a linear crossfade: every joint slides at one even rate and stops dead, which reads as
-- robotic, and a one-shot clip that runs out drops its pose in a single frame.
--
-- Step runs after the Animator has posed the rig (PreSimulation): it reads the pose just written and writes over it.
local RunService = game:GetService("RunService")

local InertialBlend = {}
InertialBlend.__index = InertialBlend

type TJoint = Bone | Motor6D

-- One joint's offset: a turn about Axis by Turn(t), a shift along Shift by Slide(t), each a quintic over its own span.
type TCurve = { Span: number, X0: number, V0: number, A: number, B: number, C: number, D: number }
type TOffset = { Axis: Vector3, Turn: TCurve?, Shift: Vector3, Slide: TCurve? }

export type TInertialBlend = typeof(setmetatable(
	{} :: {
		Joints: { TJoint },
		IsTrackingSpeed: boolean,
		Shown: { CFrame },
		ShownBefore: { CFrame },
		ShownGap: number,
		Seconds: number,
		Elapsed: number,
		IsPending: boolean,
		PendingPass: number,
		IsBlending: boolean,
		Offsets: { TOffset | false },
		-- What Step wrote on each joint and the fresh pose under it: a joint no playing clip keys keeps the last write.
		Written: { CFrame },
		Bases: { CFrame },
		Watched: AnimationTrack?,
		WatchSeconds: number,
	},
	InertialBlend
))

-- Offsets smaller than these are no offset.
local MIN_TURN = 1e-4
local MIN_SHIFT = 1e-4

-- Blends Run steps at real time, and its connection while any has work.
local running: { [TInertialBlend]: boolean } = {}
local runner: RBXScriptConnection? = nil
-- The Animator's passes so far: a blend asked for inside a frame's PreSimulation (a renderer switching clips as it
-- steps) is measured only once the Animator has posed the switch, a frame later.
local animatorPasses = 0

local STUB = {
	IsTrackingSpeed = false,
	ShownGap = 1 / 60,
	Seconds = 0.2,
	Elapsed = 0,
	IsPending = false,
	PendingPass = 0,
	IsBlending = false,
	WatchSeconds = 0.2,
}

-- Every joint a rig's clips move: its Bones but Root (where a renderer places the body) and its Motor6Ds.
function InertialBlend.JointsOf(model: Model): { TJoint }
	local joints = {}
	for _, child in model:GetDescendants() do
		if (child:IsA("Bone") and child.Name ~= "Root") or child:IsA("Motor6D") then joints[#joints + 1] = child end
	end

	return joints
end

-- A blend over `joints`. `isTrackingSpeed`: keep the last two poses shown every Step, so a blend leaves with the
-- motion's speed (a few joints a frame, for one big body on screen); without it a blend leaves from rest.
function InertialBlend.new(joints: { TJoint }, isTrackingSpeed: boolean): TInertialBlend
	local self = setmetatable(table.clone(STUB), InertialBlend) :: any
	self.Joints = joints
	self.IsTrackingSpeed = isTrackingSpeed
	self.Shown = table.create(#joints)
	self.ShownBefore = table.create(#joints)
	self.Offsets = table.create(#joints)
	self.Written = table.create(#joints)
	self.Bases = table.create(#joints)
	return self
end

-- From the pose on screen now into whatever the Animator poses next, over `seconds` (call it just as the clips
-- switch, with the new clip played or the old one stopped at no fade).
function InertialBlend.Start(self: TInertialBlend, seconds: number)
	if not self.IsTrackingSpeed or #self.Shown == 0 then
		-- Mid-blend, what is on screen is the blend's own last write, whatever the Animator has posed since.
		for i, joint in self.Joints do
			local shown = if self.IsBlending then self.Written[i] or joint.Transform else joint.Transform
			self.Shown[i] = shown
			self.ShownBefore[i] = shown
		end
	end

	self.Seconds = seconds
	self.IsPending = true
	self.PendingPass = animatorPasses
end

-- Cuts one-shot `track` a frame before it runs out and blends out of it over `seconds`: a track that runs out drops
-- its pose at once.
function InertialBlend.Watch(self: TInertialBlend, track: AnimationTrack, seconds: number)
	self.Watched = track
	self.WatchSeconds = seconds
end

-- Ends a blend: its last write put back to the fresh pose under it on any joint no clip keys (it would keep it).
local function release(self: TInertialBlend)
	self.IsBlending = false
	local written, bases = self.Written, self.Bases
	for i, joint in self.Joints do
		local pose = written[i]
		if pose and joint.Transform == pose then joint.Transform = bases[i] end
	end

	table.clear(written)
	table.clear(bases)
end

-- Lets go: the Animator's pose is shown as it is from now on.
function InertialBlend.Cancel(self: TInertialBlend)
	release(self)
	self.IsPending = false
	self.Watched = nil
	table.clear(self.Shown)
	table.clear(self.ShownBefore)
end

-- Whether Step still has anything to do.
function InertialBlend.IsActive(self: TInertialBlend): boolean
	return self.IsTrackingSpeed or self.IsPending or self.IsBlending or self.Watched ~= nil
end

-- The quintic from x0 (moving at v0) to rest at 0 within `seconds`, sooner when the motion already heads there fast
-- (it would overshoot otherwise); a motion heading away is not carried on.
local function curve(x0: number, v0: number, seconds: number): TCurve
	local v = math.min(v0, 0)
	local span = if v < 0 then math.min(seconds, -5 * x0 / v) else seconds
	span = math.max(span, 1e-3)
	local span2 = span * span
	local a0 = math.max(0, (-8 * v * span - 20 * x0) / span2)
	return {
		Span = span,
		X0 = x0,
		V0 = v,
		A = -(a0 * span2 + 6 * v * span + 12 * x0) / (2 * span2 * span2 * span),
		B = (3 * a0 * span2 + 16 * v * span + 30 * x0) / (2 * span2 * span2),
		C = -(3 * a0 * span2 + 12 * v * span + 20 * x0) / (2 * span2 * span),
		D = a0 / 2,
	}
end

-- The pose the Animator gave joint `i` this frame (not this blend's own write from the last).
local function freshOf(self: TInertialBlend, i: number, joint: TJoint): CFrame
	local current = joint.Transform
	return if current == self.Written[i] then self.Bases[i] else current
end

local function at(c: TCurve, t: number): number
	if t >= c.Span then return 0 end
	return ((((c.A * t + c.B) * t + c.C) * t + c.D) * t + c.V0) * t + c.X0
end

-- Each joint's offset from the fresh pose to the one shown, and how fast the shown one was moving along it.
local function capture(self: TInertialBlend)
	local gap = math.max(self.ShownGap, 1e-3)
	for i, joint in self.Joints do
		local fresh = freshOf(self, i, joint)
		local shown, before = self.Shown[i], self.ShownBefore[i]
		if not shown then
			self.Offsets[i] = false
			continue
		end

		local inverse = fresh.Rotation:Inverse()
		local axis, angle = (shown.Rotation * inverse):ToAxisAngle()
		local turn: TCurve? = nil
		if angle > MIN_TURN then
			local beforeAxis, beforeAngle = (before.Rotation * inverse):ToAxisAngle()
			local beforeX = (beforeAxis * beforeAngle):Dot(axis)
			turn = curve(angle, (angle - beforeX) / gap, self.Seconds)
		end

		local shift = shown.Position - fresh.Position
		local distance = shift.Magnitude
		local slide: TCurve? = nil
		local direction = Vector3.zero
		if distance > MIN_SHIFT then
			direction = shift / distance
			local beforeX = (before.Position - fresh.Position):Dot(direction)
			slide = curve(distance, (distance - beforeX) / gap, self.Seconds)
		end

		self.Offsets[i] = if turn or slide
			then { Axis = axis, Turn = turn, Shift = direction, Slide = slide }
			else false
	end
end

-- After the Animator: `dt` real seconds this frame, `rate` the clips' own clock against it (slow motion, a pause).
function InertialBlend.Step(self: TInertialBlend, dt: number, rate: number)
	if self.IsPending and animatorPasses > self.PendingPass then
		self.IsPending = false
		capture(self)
		self.IsBlending = true
		self.Elapsed = 0
	end

	if self.IsBlending then
		self.Elapsed += dt * rate
		local t = self.Elapsed
		local offsets, written, bases = self.Offsets, self.Written, self.Bases
		local isLive = false
		for i, joint in self.Joints do
			local offset = offsets[i]
			if not offset then continue end
			local current = joint.Transform
			local fresh = if current == written[i] then bases[i] else current
			local turn = if offset.Turn then at(offset.Turn, t) else 0
			local slide = if offset.Slide then at(offset.Slide, t) else 0
			-- The same pose as CFrame.new(position) * fromAxisAngle(axis, turn) * rotation, built with fewer CFrames, and
			-- none for a joint whose curves have run out (`at` is 0 for good past a span): it gets its fresh pose once
			-- more and is skipped from then on (performance/optimization-2026-11-26).
			local pose
			if turn ~= 0 then
				isLive = true
				pose = CFrame.fromAxisAngle(offset.Axis, turn) * fresh.Rotation
					+ (fresh.Position + offset.Shift * slide)
			elseif slide ~= 0 then
				isLive = true
				pose = fresh + offset.Shift * slide
			else
				offsets[i] = false
				pose = fresh
			end
			bases[i] = fresh
			written[i] = pose
			joint.Transform = pose
		end

		if not isLive then release(self) end
	end

	-- What is on screen this frame, kept for the speed a blend leaves with.
	if self.IsTrackingSpeed then
		local shown, before = self.ShownBefore, self.Shown
		for i, joint in self.Joints do
			shown[i] = joint.Transform
		end
		self.Shown, self.ShownBefore = shown, before
		self.ShownGap = dt * rate
	end

	-- Cut a frame and a half before it runs out, while its pose is still on screen.
	local watched = self.Watched
	if not watched then return end
	if not watched.IsPlaying then
		self.Watched = nil
		return
	end

	local length = watched.Length
	if length > 0 and watched.TimePosition + dt * math.abs(watched.Speed) * 1.5 >= length then
		self.Watched = nil
		watched:Stop(0)
		self:Start(self.WatchSeconds)
	end
end

-- Steps the blend here, at real time, until it has nothing left to do: for bodies no renderer steps (the lobby's).
function InertialBlend.Run(self: TInertialBlend)
	running[self] = true
	if runner then return end
	runner = RunService.PreSimulation:Connect(function(dt: number)
		for blend in running do
			blend:Step(dt, 1)
			if not blend:IsActive() then running[blend] = nil end
		end

		if next(running) == nil and runner then
			runner:Disconnect()
			runner = nil
		end
	end)
end

-- Plays one-shot `track` over whatever the rig is doing, blended in from the pose on screen and out of its last frame
-- into what is under it, each over `seconds`.
function InertialBlend.PlayOneShot(self: TInertialBlend, track: AnimationTrack, seconds: number)
	self:Start(seconds)
	track:Play(0)
	self:Watch(track, seconds)
	self:Run()
end

RunService.PreAnimation:Connect(function()
	animatorPasses += 1
end)

return InertialBlend
