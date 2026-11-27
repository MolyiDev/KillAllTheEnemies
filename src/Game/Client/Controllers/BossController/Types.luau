-- What BossController and its children share: a boss as this client follows it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TData = require(ReplicatedStorage.Types.TData)

export type TBoss = {
	InstanceId: number,
	Data: TData.TEnemy,
	Kit: TData.TEnemyBoss,
	-- Effects due on the enemy clock, in order.
	Timeline: { { At: number, Run: () -> () } },
	-- Last place each step clip was read at, to see a footfall pass.
	StepClock: { [string]: number },
	Shield: BasePart?,
	ShieldAlpha: number,
	ShieldHitAt: number,
	ShieldSoundAt: number,
	ShieldTarget: boolean,
	-- The floor under the bubble's middle, looked up once as it rises.
	ShieldFloor: Vector3?,
	-- Each guard's beam, its own phase (so beams do not pulse together) and the motes it owes.
	Beams: { [number]: { Beam: Beam, From: Attachment, Phase: number, Owed: number } },
	Anchor: Attachment?,
	Guards: { number },
	LastCFrame: CFrame?,
	-- The dive's crack, drawn leg by leg as the server steers it: studs to its next step, steps drawn, and when it was
	-- last heard.
	CrackOwed: number,
	CrackSteps: number,
	CrackHeardAt: number,
	-- The enemy clock its last dart lands at: the floor under its circle heaves from then.
	DartLandsAt: number,
	-- Under the floor (its dive): nothing of it is seen, so nothing of it reacts.
	IsBuried: boolean,
	-- The enemy clock its last chained charge's turn began, to tell a skid that ends the run from one a turn cuts.
	TurnedAt: number,
	-- Quarters of its health still standing, 0 until the server has said; and its last recoil (Tune.HURT_*): the
	-- enemy clock it started, which way it turns (1 its front toward its left, away from shots from its right; -1 the
	-- other way), and per bone the pose its clip gave and what was written over it, to tell a clip's write from this
	-- one's.
	Quarters: number,
	HurtAt: number,
	HurtSide: number,
	HurtBase: { [Bone]: CFrame },
	HurtWritten: { [Bone]: CFrame },
	-- A spider's (BossController/Spider): its silk line is up (from its brood's shot to its drop), and how many times
	-- its legs' groups had landed when last looked (a footfall for each new one).
	IsThreaded: boolean,
	LegLandings: number,
	-- Killed or cleared: its moves are let go (BossController's release) and no new one plays.
	IsDead: boolean,
}

-- What a child is handed of BossController's own: the timeline, the rig's bones, the shake.
export type TApi = {
	Schedule: (boss: TBoss, at: number, run: () -> ()) -> (),
	BoneFrame: (boss: TBoss, name: string) -> CFrame?,
	BonePosition: (boss: TBoss, name: string) -> Vector3?,
	Shake: (at: Vector3, preset: { number }, scale: number?) -> (),
	Facing: (boss: TBoss) -> Vector3,
}

return {}
