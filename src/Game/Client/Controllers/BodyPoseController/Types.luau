-- One R6 body as the pose drives it: its joints, their rest C0s, and the pose's running state.
export type TRig = {
	Model: Model,
	Humanoid: Humanoid,
	Torso: BasePart,
	Root: BasePart,
	Head: BasePart,
	Neck: Motor6D,
	RootJoint: Motor6D,
	Right: Motor6D,
	Left: Motor6D,
	Hips: { Motor6D },
	Bases: { [Motor6D]: CFrame },
	-- The gun's handle this frame, or nil unarmed (looked up once a frame, in the PreRender pass).
	Handle: BasePart?,
	-- Smoothed aim: pitch, yaw against the body, the torso's share of the yaw.
	Pitch: number,
	Yaw: number,
	Twist: number,
	-- Where the server last said this body looks (others only), world angles.
	WantedPitch: number,
	WantedYaw: number,
	Kick: number,
	KickVelocity: number,
	-- Lean springs (+ pitch tips forward, + roll tips right) and what drives them.
	LeanPitch: number,
	LeanPitchVelocity: number,
	LeanRoll: number,
	LeanRollVelocity: number,
	LastVelocity: Vector3,
	Accel: Vector3,
	WasAirborne: boolean,
	-- The fastest fall of this airborne stretch: the landing frame's velocity is already stopped.
	FallSpeed: number,
	-- The hips' turn off the facing (+ toward the right), and whether the walk is a backpedal.
	LegYaw: number,
	IsBackpedalling: boolean,
}

return nil
