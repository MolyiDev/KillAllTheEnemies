-- Universal across R6 and R15. Rig-specific parts (Torso for R6, UpperTorso/LowerTorso/etc. for R15) are
-- intentionally not in the type so callers don't accidentally code against one rig: use FindFirstChild and fall back.
export type TCharacter = {
	Head: BasePart,
	HumanoidRootPart: BasePart,
	Humanoid: THumanoid,
} & Model

export type THumanoid = {
	Animator: Animator,
} & Humanoid

return nil
