-- What the HUD's pieces read and what they may ask for. init.luau owns every source and writes them once a frame
-- from the controllers (a source ignores a write of the value it already holds, so a quiet frame redraws nothing);
-- the pieces only read them and call the actions.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.vide)
local GunsCore = require(ReplicatedStorage.GlobalShared.Core.GunsCore)
local TData = require(ReplicatedStorage.Types.TData)

type Source<T> = vide.Source<T>

-- Where the run is: "Waiting" for the party, "Preparing" a round, "Fighting" one, or "Ended".
export type TPhase = "Waiting" | "Preparing" | "Fighting" | "Ended"

export type TDefenseCard = {
	-- nil past DefensePlacementController.KEYS: placed from its card only.
	Key: Enum.KeyCode?,
	Name: string,
	Cost: number,
	Limit: number,
	DataId: number,
	Count: Source<number>,
	IsPlacing: Source<boolean>,
	-- os.clock of the last placement, and of the last click refused for want of Gold.
	PlacedAt: Source<number>,
	DeniedAt: Source<number>,
}

-- The weapon card and the show of a bought upgrade (WeaponUpgrade.Timing).
export type TWeaponUpgrade = {
	-- The step on offer (nil once the last is bought) and the step in hand.
	Offer: Source<GunsCore.TLadderStep?>,
	Held: Source<GunsCore.TLadderStep?>,
	Step: Source<number>,
	-- The Gold on the counter covers the offer.
	CanAfford: Source<boolean>,
	-- os.clock while the card or the show is moving, math.huge otherwise (every gesture reads as finished). The
	-- weapon's pieces time themselves off this rather than Now, which ticks for every coin that lands.
	Clock: Source<number>,
	-- os.clock the server confirmed a buy, and the one its gun lands in the hotbar at.
	BoughtAt: Source<number>,
	LandAt: Source<number>,
	-- os.clock of the last ask, the last refusal, and when the offer last became affordable.
	AskedAt: Source<number>,
	DeniedAt: Source<number>,
	ReadyAt: Source<number>,
}

export type TSquadMember = {
	Name: string,
	UserId: number,
	IsSelf: boolean,
	Health: Source<number>,
	MaxHealth: Source<number>,
}

-- A top bar icon wearing the HUD's panel (Topbar.luau): what the hand is doing to it.
export type TTopbarSkin = {
	-- His Squad button wears corner brackets; his Settings button does not.
	HasBrackets: boolean,
	IsHovered: Source<boolean>,
	IsSelected: Source<boolean>,
	PressedAt: Source<number>,
}

export type THudState = {
	Scale: Source<number>,
	-- os.clock, written only in frames where something is moving (init's motion window), so a quiet HUD redraws
	-- nothing. Every timed gesture reads it against one of the *At stamps below.
	Now: Source<number>,

	Phase: Source<TPhase>,
	Round: Source<number>,
	-- os.clock the phase last changed, and the phase before it.
	PhaseAt: Source<number>,
	PreviousPhase: Source<TPhase>,
	Countdown: Source<number>,
	-- os.clock of the countdown's last tick down.
	CountdownAt: Source<number>,
	IsBossRound: Source<boolean>,
	Votes: Source<number>,
	VotesNeeded: Source<number>,
	-- The wave being fought has run long enough to be skipped by vote.
	CanSkip: Source<boolean>,
	-- How far SKIP WAVE's cooldown has run (0 to 1, over the countdown and the wave's opening seconds), and the
	-- os.clock it opened.
	SkipProgress: Source<number>,
	SkipOpenedAt: Source<number>,
	VotesAt: Source<number>,
	IsAutoSkip: Source<boolean>,

	-- The boss on the field ("" for none) and its bar.
	BossName: Source<string>,
	BossHealth: Source<number>,
	BossMaxHealth: Source<number>,
	-- The next boss and the round it comes on.
	NextBossName: Source<string>,
	NextBossRound: Source<number>,

	Gold: Source<number>,
	-- The counter rolls toward Gold rather than jumping (GDD 17).
	GoldShown: Source<number>,
	-- 1 when Gold came in, fading; 1 when a purchase was refused for want of it, fading.
	GoldPulse: Source<number>,
	GoldDenied: Source<number>,

	Health: Source<number>,
	MaxHealth: Source<number>,
	TrailHealth: Source<number>,
	IsDown: Source<boolean>,
	-- The local character's head, for the health over it, and whether the camera is inside it.
	Head: Source<BasePart?>,
	IsFirstPerson: Source<boolean>,
	-- The red screen edge (GDD 9): a hit flashes it, low health holds a little of it.
	Vignette: Source<number>,

	Defenses: { TDefenseCard },
	-- Everyone in the run, the local player first.
	Squad: Source<{ TSquadMember }>,
	IsSquadOpen: Source<boolean>,
	SquadToggledAt: Source<number>,
	-- Whole seconds since the run began.
	RunSeconds: Source<number>,

	-- Enemies this client holds (EnemiesController.Count), and which buy-all item is asking to be bought: the nuke
	-- when the crowd is big, the heal when health is low, the nuke first.
	EnemyCount: Source<number>,
	IsNukePrompted: Source<boolean>,
	IsHealPrompted: Source<boolean>,

	-- The gun in hand and the model of the Tool holding it, for its slot's picture.
	Gun: Source<TData.TGun?>,
	GunModel: Source<Model?>,
	GunAt: Source<number>,
	Weapon: TWeaponUpgrade,

	IsReviveOffered: Source<boolean>,
	CanRevive: boolean,
	-- The fixed bindings the HUD draws caps for (the defenses' keys live on their own entries).
	Keys: { Skip: Enum.KeyCode, Turn: Enum.KeyCode, Upgrade: Enum.KeyCode },

	RoundsCleared: Source<number>,
	RunGold: Source<number>,
	RunGems: Source<number>,
	ReturnIn: Source<number>,
}

export type TActions = {
	VoteStart: () -> (),
	ToggleAutoSkip: () -> (),
	PlaceDefense: (dataId: number) -> (),
	UpgradeWeapon: () -> (),
	Revive: () -> (),
	BuyHealAll: () -> (),
	BuyNukeAll: () -> (),
	CloseSquad: () -> (),
}

return nil
