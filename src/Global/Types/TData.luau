-- The shape of every data table in src/Global/Data.

-- ============================== Enemies ==============================

-- An enemy's rig, the zombie contract (Models.md section 7): ONE skinned MeshPart shaped like R6,
-- its bones `Root` > `Torso` > `Head`, `ArmLeft`, `ArmRight`, `LegLeft`, `LegRight` (clips key them by name), front +Z,
-- feet at the bottom of Root's pivot. The renderer reads:
--   * PrimaryPart: the skinned MeshPart, with the Bone `Root` directly under it;
--   * AnimationController.Animator, so clips play locally with zero Luau cost per body.
-- The rig is never moved through its parts: Root.Transform carries the world CFrame, so nothing may raycast or
-- overlap-query an enemy (every MeshPart sits at the origin). Ask EnemiesCore's hash instead.
export type TEnemyModel = Model & {
	PrimaryPart: MeshPart & { Root: Bone },
	AnimationController: AnimationController & { Animator: Animator },
}

-- What an attack does when its wind-up ends (TEnemyAttack.Kind).
--   Melee      hits what stands in the body's swing then (the oriented box plus Reach).
--   Explode    the body blows up: everything within Radius of it, and it dies. Killing it during the fuse cancels.
--   Slam       a circle of Radius, at the body or at where its target stood when the charge began (AtTarget).
--   Shockwave  a ring expanding from the body at Speed out to Radius; it hits whoever it passes who is on the ground.
-- Every kind but Melee shows its area on the ground for the whole wind-up (Enemies.Telegraph), and the area shown is
-- exactly the area that hurts: the floor it was cast on and what that floor steps onto (TelegraphCore).
export type TEnemyAttackKind = "Melee" | "Explode" | "Slam" | "Shockwave"

-- A Slam's area (TEnemyAttack.Shape). A Cone or a Line starts at the body and points where it faces (at its target),
-- whatever AtTarget says.
--   Circle  Radius around its centre.
--   Cone    Radius long, Angle degrees wide (one of TelegraphCore.CONE_ANGLES).
--   Line    Radius long, Width wide.
export type TEnemyAttackShape = "Circle" | "Cone" | "Line"

export type TEnemyAttack = {
	Kind: TEnemyAttackKind,
	-- Starts when a target is this close (flat studs, to its surface for Melee).
	Range: number,
	-- The wind-up, the telegraph, and the window to get out.
	Delay: number,
	-- Recovery after it resolves, before the next attack can start.
	Cooldown: number,
	-- Multiplies the body's Damage.
	DamageScale: number,
	Radius: number?,
	AtTarget: boolean?,
	Speed: number?,
	-- A Slam's area, "Circle" when nil.
	Shape: TEnemyAttackShape?,
	Angle: number?,
	Width: number?,
	-- The clip played on the wind-up (TEnemy.AnimationSet), "Attack" when nil. Every attack clip lands its blow at
	-- EnemiesCore.ATTACK_CLIP_IMPACT and is played faster or slower to meet Delay.
	AnimationName: string?,
}

export type TEnemy = {
	Id: number,
	Name: string,
	-- One or two plain sentences for the lobby's index: what it does and how to answer it.
	Description: string,
	-- Rig under ReplicatedStorage.Models.Enemies. A name rather than the instance, so the data loads before the
	-- model has been put in the place (EnemiesCore.GetModel resolves it).
	ModelName: string,

	-- The collision box the movement update is tuned against. The aim point is measured off the rig instead
	-- (EnemiesCore.AimShape), because a hand-typed box drifts from the model it describes.
	CollisionSize: Vector3,
	Mass: number,

	BaseMaxHealth: number,
	BaseDamage: number,
	BaseMovementSpeed: number,

	-- In pattern order; a body walks while recovering and stands still through a wind-up.
	Attacks: { TEnemyAttack },
	-- Seconds a surviving hit holds the next attack off. nil only cancels the pending one; a boss is never staggered.
	HitStunTime: number?,

	-- Rounds (RoundCore): first round it can appear in and how often it is drawn against the others. A boss is never
	-- drawn: RoundCore adds it to every BOSS_EVERY-th round.
	IntroRound: number,
	SpawnWeight: number,
	IsBoss: boolean?,
	-- The maps it comes on (MapsCore names), for the draw and the lobby's index; nil for every map.
	Maps: { string }?,

	-- Gold its killer earns (GDD 17), before the round's scaling.
	GoldDrop: number,
	-- The energy its kills drop for the Mutation Lab's brews (PotionsCore); nil for none.
	Energy: TEnemyEnergy?,

	-- Clips under ReplicatedStorage.Animations.Enemies.<AnimationSet>: Idle, Walk, and each attack's AnimationName
	-- ("Attack" when it has none). A set rather than a clip per enemy: every R6 zombie shares one (tools/rig), since
	-- its clips key rotations only and play on any size. There is no death clip: a kill ragdolls (EnemiesController).
	AnimationSet: string,
	-- Its own voice, on top of the impact palette every enemy shares (Client/Utils/enemyImpacts). nil: the palette
	-- alone.
	Sounds: TEnemySounds?,
	-- What its model is painted in, for the stud pieces and pixels a blow knocks off it (Client/Utils/enemyImpacts).
	-- Repaint the model and these change with it. nil: grey pieces.
	Colors: TEnemyColors?,
}

-- What a kind's energy is (PotionsCore): the run upgrade a potion brewed from it adds to (an EUpgradesIds value), how
-- much of it one brew takes, the chance one kill drops one for its killer (a boss's drops for everybody in the match,
-- each on their own roll), and its colour on the lab's cards. A crowd's kind drops rarely and costs more; a boss's
-- drops often and costs little, since there are few of them.
export type TEnemyEnergy = {
	Upgrade: number,
	Cost: number,
	Chance: number,
	Color: Color3,
}

-- Head, arms and bare skin; the torso's clothes; the legs'.
export type TEnemyColors = {
	Skin: Color3,
	Top: Color3,
	Legs: Color3,
}

-- Names under ReplicatedStorage.Sounds.<Group>, each one clip or a folder of takes to roll. Each is optional and a
-- missing one is silence (or the palette, for Hit), so a type can be wired before its clips exist.
export type TEnemySounds = {
	Group: string,
	-- The crowd's groan, from one visible body at a time on a shared timer, never a timer per body.
	Idle: string?,
	-- The wind-up (Enemies.AttackStarted), so it warns while the blow can still be answered.
	Attack: string?,
	Hit: string?,
	Death: string?,
}

-- ============================== Defenses (GDD 15) ==============================

export type TDefenseKind = "Barricade" | "Turret"

export type TDefense = {
	Id: number,
	Name: string,
	Kind: TDefenseKind,
	ModelName: string,
	-- Gold to place one, and to buy each upgrade level after it.
	Cost: number,
	UpgradeCosts: { number },
	-- Flat footprint in studs (X, Z), which is also what it blocks on the nav grid.
	Footprint: Vector2,
	MaxHealth: number,
	-- How many one player may have standing.
	MaxPerPlayer: number,
	-- Turret only: range, seconds between shots, damage per shot and its growth per upgrade level.
	Range: number?,
	FireInterval: number?,
	Damage: number?,
	DamagePerLevel: number?,
}

-- The one rarity ladder of guns, classes, equipment, potions and run upgrade cards, lowest first: ERarities's keys.
export type TRarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic"

-- How the arms hold it, first and third person (ViewmodelController, BodyPoseController).
export type TGunHold = "Rifle" | "Pistol" | "Heavy" | "Launcher"

export type TGun = {
	Id: number,
	Name: string,
	-- ReplicatedStorage.Models.Guns.<rarity folder>.<ModelName> (GunsCore.GetModel).
	ModelName: string,
	Rarity: TRarity,
	-- Its loadout slot, 1-4.
	Tier: number,
	Price: number,
	-- A shot's damage, split between its pellets.
	Damage: number,
	FireInterval: number,
	Pellets: number,
	SpreadDeg: number,
	Range: number,
	-- Added to every enemy's aim shape for this gun's bullets: a fat rocket hits what a sniper round misses.
	HitRadius: number,
	-- The model is scaled to this length (studs) and turned muzzle-forward when the tool is built (buildGunTool).
	Length: number,
	-- The model's long axis points backwards: turn it around.
	IsFlipped: boolean?,
	-- Roll about the barrel, for a model built on its side.
	PitchDeg: number?,
	-- Blast radius where a bullet stops; everything in it takes GunsCore's share of the damage.
	SplashRadius: number?,
	-- Bodies a bullet goes on through after the first it hits, each hurt in full.
	Pierce: number?,
	-- Studs a whole shot shoves a body of Mass 1 that survives it, along the shot (EnemyMovementService.Push); a body
	-- hit by part of the shot is shoved by that part.
	Knockback: number?,
	Hold: TGunHold,
	-- Where each hand closes on the model, first and third person (Utils/gunGrips), as shares of the built gun's box:
	-- X of its length from its back, Y of its height from its bottom. Picked and checked on the gun's side view
	-- (tools/ree/gunsheet.sh).
	Hands: { Right: Vector2, Left: Vector2 },
	-- Share of that box's height, from its bottom, where the barrel's axis runs: first person puts every gun's barrel
	-- on the same line under the crosshair, whatever hangs under it or stands on top (a magazine, a scope).
	Barrel: number,
	-- Sound bank nodes under ReplicatedStorage.Sounds.Guns: the shot, and the pump / bolt after it.
	Sound: string,
	CycleSound: string?,
	-- The last shot's ring when a stream of shots stops: for a gun whose shot takes are cut short so a fast stream
	-- stays a run of hits, the release continuing where they fade (WeaponController's Tune.RELEASE_DELAY).
	ReleaseSound: string?,
	-- Its effect kit under ReplicatedStorage.Effects (Client/Utils/gunFx); without one it draws the plain tracers.
	Fx: string?,
	-- Camera kick in degrees, when not worked out from Damage (GunsCore.KickDeg).
	RecoilDeg: number?,
	-- How hard the arms jolt, when not worked out from the kick.
	PoseKick: number?,
	-- Camera shake a shot (CameraController.Shake magnitude), when not worked out from the kick; 0 for none.
	Shake: number?,
}

-- ============================== Classes ==============================

-- What an ability does, which picks the code that casts it (AbilityService) and draws it (AbilityController).
--   Decoy          a doll thrown to a spot: every enemy within Radius of it goes for it until it pops, and the pop
--                  blasts what is round it.
--   FoamCannon     a cone of foam: what it catches is held where it stands and takes more damage.
--   OrbitalCannon  a beam from the sky, called on a spot, then going after a boss or the thickest crowd on its own.
export type TAbilityKind = "Decoy" | "FoamCannon" | "OrbitalCannon"

-- The fields of TAbility a level can raise.
export type TAbilityStat =
	"Cooldown"
	| "ChargeKills"
	| "Range"
	| "Radius"
	| "Duration"
	| "Blows"
	| "Damage"
	| "BlastRadius"
	| "AngleDeg"
	| "DamageTaken"
	| "BossShare"

-- One stat a level sets: its new value, and what the classes screen calls it.
export type TAbilityLevelStat = {
	Stat: TAbilityStat,
	Label: string,
	Value: number,
}

export type TAbility = {
	Kind: TAbilityKind,
	Name: string,
	-- What it does, in a line, for the lobby's classes screen.
	Description: string?,
	-- Run Gold each cast costs. An ultimate has none: it is paid for in kills (ChargeKills).
	Cost: number?,
	-- Seconds between two casts. An ultimate has none: it fills from kills (ChargeKills).
	Cooldown: number?,
	ChargeKills: number?,
	-- How far from the caster it reaches (flat studs): the throw, the cone's length, the beam's leash.
	Range: number,
	-- Decoy: how far it draws enemies from. OrbitalCannon: the beam's reach round its middle.
	Radius: number,
	-- Seconds it lasts once it is out: the doll standing, the foam set, the beam burning.
	Duration: number,

	-- Decoy: the blows it takes before it pops, and how long it is in the air.
	Blows: number?,
	FlightSeconds: number?,
	-- Decoy: the pop's blow on every body within BlastRadius of it (flat studs).
	Damage: number?,
	BlastRadius: number?,

	-- FoamCannon: the cone's full width, and what a foamed body's damage is multiplied by.
	AngleDeg: number?,
	DamageTaken: number?,

	-- OrbitalCannon: seconds the mark shows before the beam lands, how fast the beam moves (studs a second),
	-- seconds between its blows, and the share of a boss's max health each blow takes (anything else it overkills).
	TargetSeconds: number?,
	Speed: number?,
	TickSeconds: number?,
	BossShare: number?,

	-- Bought with Gems in the lobby (AbilitiesCore.MAX_LEVEL - 1 entries): entry n is what level n + 1 sets, and holds
	-- for every level above it.
	Levels: { { TAbilityLevelStat } },
}

-- Two abilities and an ultimate (PlanAbilities.md). A slot is an index into Abilities, the ultimate the one after.
export type TClass = {
	Id: number,
	Name: string,
	-- Its tag and colour on the classes screen.
	Rarity: TRarity,
	-- Its emblem on the classes screen and the head tag: an EIcons name.
	Icon: string,
	Abilities: { TAbility },
	Ultimate: TAbility,
}

-- A run upgrade, picked one of three after a cleared wave (UpgradesService). It lasts the run and is never saved.
export type TUpgrade = {
	Id: number,
	Name: string,
	-- Its picture: an EIcons name.
	Icon: string,
	-- What one Common pick adds to the stat; a rarer card adds UpgradesCore.MULTIPLIERS times it.
	Value: number,
	-- How many times it can be picked in a run.
	MaxLevel: number,
	-- The card's line, with %d where the card's own amount goes (Value times its rarity, times PercentScale).
	Description: string,
	-- 100 where the stat is a share shown as a percentage, 1 where it is shown as it is.
	PercentScale: number,
}

-- ============================== Potions ==============================

-- A Mutation Lab recipe (PotionsCore): the two kinds of energy it is brewed from (enemy data Ids, either order), each
-- adding its own run upgrade for a whole match. Found the first time it is brewed, and then shown in the index.
export type TPotion = {
	Id: number,
	Name: string,
	Energies: { number },
	-- One line for the index: what it is like to drink.
	Description: string,
}

-- ============================== Equipment ==============================

-- Where a piece of equipment is worn: one of each at a time (EquipmentCore.SLOTS).
export type TEquipmentSlot = "Head" | "Torso" | "Legs"

-- What a piece adds in a match (EquipmentService.StatOf): MaxHealth in health points, Armor the share of every blow
-- taken off it, KillGold the share added to the Gold each kill pays.
export type TEquipmentStat = "MaxHealth" | "Armor" | "KillGold"

export type TEquipmentBonus = {
	Stat: TEquipmentStat,
	Value: number,
}

-- Where a piece comes from when it is not everybody's: a boss that drops it, and the chance each player in the squad
-- has of getting it when that boss dies.
export type TEquipmentDrop = {
	Enemy: number,
	Chance: number,
}

-- A piece of equipment, kept for good once got (TProfile.Equipment) and worn on the avatar while it is in its slot.
export type TEquipment = {
	Id: number,
	Name: string,
	Slot: TEquipmentSlot,
	Rarity: TRarity,
	Description: string,
	Stats: { TEquipmentBonus },
	-- Its accessories under ReplicatedStorage.Models.Equipment (a Folder of Accessories, one per body attachment).
	ModelName: string,
	-- Everybody owns it from their first visit, so the profile never needs to hold it.
	EarlyUnlock: boolean?,
	Drop: TEquipmentDrop?,
}

return nil
