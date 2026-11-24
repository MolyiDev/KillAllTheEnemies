# Balance.md

How the guns are balanced against each other, worked out on 2026-11-22 by measuring every gun in
`tools/lune/guns.luau`. Read it before adding a gun or changing one's numbers in `src/Global/Data/Guns`.

## 1. The ladder a run climbs

- **Four tiers, four steps.** The lobby loadout holds one gun per tier (`LoadoutCore`, `TProfile.Loadout.Equipped`).
  A run starts on the tier 1 gun and buys the next tier's gun for run Gold: `GunsCore.LADDER_PRICES` is
  0 / 150 / 450 / 1000 (`GunsCore.Ladder`, `WeaponService`).
- **Every step must be a step up, whatever the player equipped.** So the weakest gun of a tier, its free starter,
  has to beat the strongest gun of the tier below it.
- **The four starters set the difficulty.** A player who bought nothing climbs Pistol, Terminator Gun (shotgun),
  Starter Rifle, Starter Minigun, and the waves were tuned against that climb. Change a starter only together with
  the rounds (`RoundCore`), then run `tools/lune/sim.luau` as well.

## 2. Price, rarity and tier go together

The bigger the price, the bigger the rarity, and the other way round, over every gun. A tier holds one band of each:

| Tier | Starter (free) | Paid rarity | Gems |
| --- | --- | --- | --- |
| 1 | Starter Pistol | Uncommon | 700-900 |
| 2 | Terminator Gun | Rare | 1,800-2,600 |
| 3 | Starter Rifle | Epic | 6,000-7,000 |
| 4 | Starter Minigun | Legendary, then Mythic | 12,000-13,000, then 25,000-28,000 |

- A starter is `Price = 0` and `Rarity = "Common"`, and only a starter is either. One per tier: `LoadoutCore`
  takes the gun of price 0 as the tier's starter.
- A new gun's price sits inside its rarity's band, and its rarity matches its tier.
- **The rarity is also a folder.** `GunsCore.GetModel` loads the model from `Assets/models/Guns/<rarity>/`,
  so changing a gun's rarity means moving its model file to the matching folder.

## 3. Power follows price

**The rule:** every gun kills faster than the cheaper guns of its tier and every gun of the tiers below. A starter
is the weakest gun of its tier. It still beats the whole tier below, because buying it is the run's next step.

**How it is measured:** `lune run tools/lune/guns.luau "$PWD"`. Its last table ranks every gun by tier, then price,
and marks any that is not above the one before it. The score is the geometric mean of kills a second over five
crowds of the round's own mix (round 4 at 20 alive; round 8 at 6, 20 and 45; round 12 at 45). A geometric mean,
so a gun that only shines in one crowd (a sniper in a thick one) cannot top the list on that crowd alone. Damage
a second says nothing here: a slow gun that one-shots wastes most of its damage, and a gun that pierces kills
several bodies a shot.

The scores on 2026-11-22, the spacing to keep:

| Tier | Starter | Paid guns, by price |
| --- | --- | --- |
| 1 | Pistol 0.56 | AA Mitra 1.08, Freeze Pistol 1.22, Desert Eagle 1.47, AWP Printstream 1.62 |
| 2 | Terminator Gun 2.01 | Starter Sniper 2.24, Celebration Gun 2.48, Flame Gatling 2.71, AWP The Prince 2.86 |
| 3 | Starter Rifle 3.44 | Poison Pistol 3.99, Snowy Rifle 4.13, RPG Bazooka 4.50 |
| 4 | Starter Minigun 6.04 | Sandan Gun 6.39, UFO Bullpup 6.56, Hacker Drum 7.16, Lavaforge 7.98, Corrupted Runes AK 8.73 |

A new paid gun goes between its tier's starter and the next tier's starter, at the place its price gives it, with
room on both sides: about 5-15% over the gun priced just below it.

## 4. Which number to turn

Keep a gun's `FireInterval`, `SpreadDeg` and `Range` where they are: they are how it feels and sounds. Tune the rest
by what the gun is:

- **Automatic guns** (Mitra, Celebration, Flame Gatling, UFO, Hacker Drum): `Damage`. Once a bullet kills in one
  hit, more damage does nothing, and the gun tops out near one kill a shot. Past that, `Pierce = 1` (the Minigun,
  Lavaforge, Corrupted Runes AK).
- **Slow guns** (snipers, Desert Eagle, Poison Pistol, Snowy Rifle): `Pierce`, so one bullet kills several bodies
  in a line and makes up for the wait between shots. The longer the wait, the more pierce.
- **Snipers also get a wide shot**: `HitRadius` 1.0 to 2.0 studs instead of a thin line, so a pierce through a
  crowd meets the bodies beside its line too (AWP Printstream 1.0 and pierce 2 at the bottom, Sandan Gun 2.0 and
  pierce 10 at the top).
- **Launchers** (RPG Bazooka): `Damage` and `SplashRadius`. A rocket never pierces.
- **Only when nothing else reaches the score, `FireInterval`.** With few enemies about, a slow gun kills at most one
  body a shot, so pierce and splash cannot lift it there (Sandan went from 0.7 to 0.4 s, the RPG from 1.6 to
  1.2 s, to beat their tier's starter).
- **Pin the kick when damage changes.** A gun without `RecoilDeg` kicks the camera by its damage
  (`GunsCore.KickDeg`: 0.35 + 0.03 per point, 0.4 to 3.5 degrees), and its arm jolt and shake follow the kick. A
  damage change alone would change the feel, so a rebalanced gun writes its old kick into `RecoilDeg`.

## 5. Adding a gun

1. Pick its tier, then a price inside that tier's band (section 2), and set its rarity to match. Put the model in
   that rarity's folder.
2. Try numbers before they go into its data: an overrides file
   (`return { ["Gun Name"] = { Damage = 40, Pierce = 2 } }`), then
   `lune run tools/lune/guns.luau "$PWD" overrides.luau`. Each run of every gun takes about 20 seconds.
3. Turn the number its kind calls for (section 4) until its score sits between its neighbours, with no gun marked.
4. Write the numbers into `src/Global/Data/Guns/<Gun>.luau`, set `RecoilDeg` if the derived kick is not the feel
   wanted, and run the tool once more on the real data: the table must match the overrides run.
5. Update section 3's table here.

## 6. What the tool does not show

- **A single tough body.** Bosses and elites are not measured: a sniper's one big hit matters more there than any
  crowd score says.
- **Splash from a miss.** A rocket that hits the arena still blasts; the tool only blasts where a rocket stops in a
  body, so a launcher is a little better than its score.
- **A shove's second.** A shoved body then takes about a second to get back up to speed, which the tool does not
  model: the Terminator holds a crowd off better than its score.
- **Loadout levels.** The lobby's upgrade levels (`LoadoutCore.Damage`, +10% a level) are not counted, and are not
  applied in a run yet.
- **Gun names.** The Freeze, Poison and Flame guns have no effect behind their names: they are plain guns.
