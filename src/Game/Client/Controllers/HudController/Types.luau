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

-- The HEALTH card and the show of a bought level (HealthUpgrade.Timing). Stamps are os.clock.
export type THealthUpgrade = {
	Level: Source<number>,
	-- The Gold the next level costs (nil once the last is bought) and what the last one bought cost.
	Price: Source<number?>,
	Paid: Source<number>,
	-- The Gold on the counter covers the next level.
	CanAfford: Source<boolean>,
	-- os.clock while the card or the show is moving, math.huge otherwise, as the weapon card's is.
	Clock: Source<number>,
	-- The server confirmed a buy, the bought level lands in the health bar, the last ask, the last refusal, and when
	-- the next level last became affordable.
	BoughtAt: Source<number>,
	LandAt: Source<number>,
	AskedAt: Source<number>,
	DeniedAt: Source<number>,
	ReadyAt: Source<number>,
	-- The middle of the health bar on the screen while a show runs, for what flies to it and what is stamped on it.
	BarAt: Source<UDim2>,
}

-- One of the class's abilities in the hotbar. Stamps are os.clock.
export type TAbilitySlot = {
	Slot: number,
	Name: string,
	-- Its picture (the model of its kind).
	Kind: string,
	Key: Enum.KeyCode,
	Accent: Color3,
	-- Gold a use costs.
	Cost: number,
	-- How much of its cooldown is left, 1 to 0 in the slot's own pixels, and in whole seconds.
	Cooling: Source<number>,
	Seconds: Source<number>,
	-- The last use, the last press refused, and the moment its cooldown last ran out.
	UsedAt: Source<number>,
	DeniedAt: Source<number>,
	ReadyAt: Source<number>,
}

-- The class's ultimate, on its card and the charge bar beside it.
export type TUltimate = {
	Slot: number,
	Name: string,
	-- Its picture (the model of its kind).
	Kind: string,
	Key: Enum.KeyCode,
	-- The meter, 0 to 1 in the bar's own pixels, and whether it is full.
	Charge: Source<number>,
	IsReady: Source<boolean>,
	-- How much of the ultimate's time is left while it is out, 1 to 0; 0 when it is not.
	Burning: Source<number>,
	-- The moment the meter last filled, the last use and the last press refused.
	ChargedAt: Source<number>,
	UsedAt: Source<number>,
	DeniedAt: Source<number>,
}

-- One player's row on the squad screen.
export type TSquadMember = {
	Name: string,
	UserId: number,
	IsSelf: boolean,
	-- The class they play this run, as its tag reads.
	ClassName: Source<string>,
	Kills: Source<number>,
	Deaths: Source<number>,
	-- Their run Gold. It rolls toward the real amount while the screen is up.
	Cash: Source<number>,
	-- os.clock their kills and their deaths last went up with the screen up.
	KilledAt: Source<number>,
	DiedAt: Source<number>,
}

-- The results, up while a wiped run is held (Results.luau). Stamps are os.clock.
export type TResults = {
	IsOpen: Source<boolean>,
	-- When they last went up or came down.
	ToggledAt: Source<number>,
	-- os.clock while one of their one-off gestures is running (Results.Seconds), math.huge otherwise: every gesture
	-- reads as finished, and a screen at rest redraws nothing for it.
	Clock: Source<number>,
	-- os.clock for as long as they are up, 0 otherwise, for the few things that never rest (REVIVE's heart, the lights
	-- on the buttons that are bought).
	Beat: Source<number>,
	Wave: Source<number>,
	IsNewBest: Source<boolean>,
	SquadKills: Source<number>,
	-- Whole seconds the run lasted.
	Seconds: Source<number>,
	-- The Gems the run had earned as it ended, and the profile's Gems then (which already held them).
	Gems: Source<number>,
	TotalGems: Source<number>,
	-- What doubling them costs in Robux, 0 with nothing to double or once it is done.
	DoubleRobux: Source<number>,
	-- An ad that pays the doubling can be shown right now.
	CanWatchAd: Source<boolean>,
	-- A copy of the player's own avatar with its arms folded, once there is one.
	Avatar: Source<Model?>,
	-- The Gems a doubling bought here added (0 before one), and when.
	Doubled: Source<number>,
	DoubledAt: Source<number>,
	-- A revive is sold here.
	CanRevive: Source<boolean>,
	-- The countdown to the lobby: whole seconds left, the share of it left in the bar's own pixels, when it last
	-- ticked down, and whether it is waiting for somebody's purchase.
	ReturnIn: Source<number>,
	ReturnShare: Source<number>,
	ReturnTickAt: Source<number>,
	IsReturnHeld: Source<boolean>,
	-- PLAY AGAIN's count, whether the local player is in it, and when it last changed.
	Votes: Source<number>,
	VotesNeeded: Source<number>,
	HasVoted: Source<boolean>,
	VotesAt: Source<number>,
}

-- One blow a bar took (BarJuice): when, where the bar was cut (a share of its length), how much it took (a share of
-- it) and a random number its chips fly by.
export type TBlow = {
	At: Source<number>,
	Cut: Source<number>,
	Bite: Source<number>,
	Seed: Source<number>,
}

-- A health bar as BarJuice moves it, in the bar's own units: the fill, and the ghost behind it, which is what was
-- just taken or, while IsHealing, what is being given back.
export type TBarTrack = {
	Fill: Source<number>,
	Ghost: Source<number>,
	IsHealing: Source<boolean>,
	-- The last BarJuice.BLOWS blows, a ring, and how many it has taken in all (which slot the next one overwrites).
	Blows: { TBlow },
	Count: number,
	-- The newest blow's, for the flash.
	HitAt: Source<number>,
	HitBite: Source<number>,
}

-- One line of the boss's damage share: who ("" for nobody), whether it is the local player, the health they took off
-- as a share of its max (rolled toward the truth), and the os.clock it last grew.
export type TShareRow = {
	Name: Source<string>,
	IsSelf: Source<boolean>,
	Share: Source<number>,
	GrewAt: Source<number>,
}

-- The boss's bar (BossBar.luau).
export type TBossBar = {
	-- The boss on the field, or the one whose fall is still playing; "" for none.
	Name: Source<string>,
	-- Its health as a share of its max, moved by BarJuice; and the segments it has lost, thrown whole (only their
	-- blows are used).
	Bar: TBarTrack,
	Breaks: TBarTrack,
	-- The two who have taken the most off it, first then second, and the os.clock they last traded places.
	Shares: { TShareRow },
	SwappedAt: Source<number>,
	-- os.clock it came on; the segment it last lost (1 the leftmost) and when; when it fell (-math.huge while it
	-- stands).
	AppearedAt: Source<number>,
	Broken: Source<number>,
	BrokeAt: Source<number>,
	DefeatedAt: Source<number>,
}

-- A top bar icon wearing the HUD's panel (Topbar.luau): what the hand is doing to it.
export type TTopbarSkin = {
	-- His Squad button wears corner brackets; his Settings button does not.
	HasBrackets: boolean,
	IsHovered: Source<boolean>,
	IsSelected: () -> boolean,
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

	Boss: TBossBar,
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
	-- What the health bar draws: Health and MaxHealth, but for the moments a bought HEALTH level is still on its way
	-- to the bar, when both are held back by it and then walked up together (the bar's length is its max).
	BarHealth: Source<number>,
	BarMax: Source<number>,
	-- BarHealth as the bar moves it, in health.
	HealthTrack: TBarTrack,
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

	-- The squad item last used, for its banner: "Nuke", "Heal" or "" before any, who used it, the bodies a nuke
	-- kills, and when.
	Announce: {
		Kind: Source<string>,
		Name: Source<string>,
		Count: Source<number>,
		At: Source<number>,
	},

	-- The Gold pack the local player last bought: its Gold and the os.clock it arrived (Hotbar's stamp and strike,
	-- the pack's slab in Upgrades).
	GoldPack: {
		Amount: Source<number>,
		At: Source<number>,
	},

	-- The gun in hand and the model of the Tool holding it, for its slot's picture.
	Gun: Source<TData.TGun?>,
	GunModel: Source<Model?>,
	-- A copy of the player's own avatar, for the Decoy's card: the doll is one.
	Avatar: Source<Model?>,
	GunAt: Source<number>,
	Weapon: TWeaponUpgrade,
	Vital: THealthUpgrade,
	-- The class's abilities, in slot order, and its ultimate.
	Abilities: { TAbilitySlot },
	Ultimate: TUltimate,

	IsReviveOffered: Source<boolean>,
	CanRevive: boolean,
	-- The fixed bindings the HUD draws caps for (the defenses' keys live on their own entries).
	Keys: { Skip: Enum.KeyCode, Turn: Enum.KeyCode, Upgrade: Enum.KeyCode, Health: Enum.KeyCode },

	Results: TResults,
}

export type TActions = {
	VoteStart: () -> (),
	ToggleAutoSkip: () -> (),
	PlaceDefense: (dataId: number) -> (),
	UpgradeWeapon: () -> (),
	UpgradeHealth: () -> (),
	CastAbility: (slot: number) -> (),
	Revive: () -> (),
	BuyProduct: (productId: number) -> (),
	CloseSquad: () -> (),
	-- The results' buttons: vote to start over, leave now, buy the doubling, or watch an ad for it.
	WatchAd: () -> (),
	PlayAgain: () -> (),
	LeaveToLobby: () -> (),
	DoubleGems: () -> (),
}

return nil
