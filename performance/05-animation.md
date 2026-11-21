# Procedural BugGait vs a per-entity AnimationTrack

**Question:** a bug rig walking on the procedural gait, against a skinned mesh playing an `AnimationTrack` -
matched on joint count.

**Answer:** the AnimationTrack is ~9x cheaper per entity and costs **zero Luau time**, contradicting the cost
argument in `BugGait`'s own header. But the animation is not where the money is - part count is.

Script: [`scripts/05-anim.client.luau`](scripts/05-anim.client.luau)

## Matching the rigs

- `Skeleton` skinned mesh: 5 bones - `Root` + `Arm_L`, `Arm_R`, `Leg_L`, `Leg_R`.
- `Slug` rig: `MoveBase` + `Body` + `Goo` + `AntennaL` + `AntennaR` + `Tail` = 5 Motor6Ds (one root, four limbs).

`BugGait.Measure` was confirmed at runtime to animate **4 joints** on the Slug rig - exact parity with the
Skeleton's 4 animated bones. (It classifies limbs by geometry and leaves wings at rest, so this had to be
verified rather than assumed.)

The bug side runs the **real `BugGait` module** required out of `PlayerScripts.Client.Utils.BugGait` - same LUT,
same `Apply`, same one-index-and-a-property-write per joint the shipping render loop does. A parity variant
drives all four limb joints off a plain shared 128-step LUT, to pin the joint count regardless of classification.

## Results

| n | Variant | median | p95 | script (upd) | fps |
| --- | --- | --- | --- | --- | --- |
| 1200 | Slug, no anim | 8.85ms | 10.55 | 431us | 110.2 |
| 1200 | **Slug + BugGait (real, 4 joints)** | 10.24ms | 12.05 | 1560us | 96.5 |
| 1200 | Slug + plain LUT (4 limbs) | 9.59ms | 12.65 | 1110us | 100.8 |
| 1200 | Skeleton, no anim | 4.19ms | 5.00 | 377us | 240.0 |
| 1200 | **Skeleton + AnimationTrack** | 4.13ms | 5.70 | 434us | 234.2 |
| 2400 | Slug, no anim | 19.14ms | 21.49 | 1063us | 51.4 |
| 2400 | **Slug + BugGait (real)** | 22.26ms | 24.50 | 3578us | 44.8 |
| 2400 | Slug + plain LUT | 20.76ms | 23.82 | 2502us | 47.2 |
| 2400 | Skeleton, no anim | 4.06ms | 5.18 | 978us | 194.4 |
| 2400 | **Skeleton + AnimationTrack** | 4.40ms | 5.52 | 976us | 137.9 |

Sentinels ran at the start and end of each count block and stayed flat at 4.06-4.22ms.

## Animation cost, isolated against each side's own no-animation row

| Path | delta | per entity |
| --- | --- | --- |
| Bug + `BugGait` | +1.39ms @1200, +3.12ms @2400 | **~1.3us** |
| Skeleton + `AnimationTrack` | +0.34ms @2400 | **~0.14us** |

About **9x cheaper per entity**, and the reason is in the script column: the Skeleton's animation costs **zero
Luau time** (976us with the track playing vs 978us without). The Animator evaluates in engine code, off the
update loop. `BugGait.Apply` costs 1129us of Luau at 1200 and 2515us at 2400, because those joint writes happen
on the Luau thread.

That contradicts the reasoning in `BugGait`'s header - the "per-entity object and a per-entity update" argument
against AnimationTracks. At these counts the per-entity Animator is cheaper *precisely because* it is not
running in Luau.

For what it is worth, the LUT is well optimised: the plain 4-limb LUT beat `BugGait.Apply` by ~450us at 1200,
since `Apply` adds a per-rig table lookup and the `grow` branch on top.

## But the animation is not the story

Before any animation, 2400 Slugs cost **19.14ms** and 2400 Skeletons cost **4.06ms** - a slug is 6 parts, a
skeleton is 1 MeshPart. That 15ms gap dwarfs the 3ms the gait adds. The skinned mesh wins here mainly by being
one instance instead of six, not by how it animates.

Fully animated at 2400: Slug 22.26ms (44.8 FPS) vs Skeleton 4.40ms. Roughly 5x, end to end.

## Caveats

- The 137.9 FPS on the animated Skeleton row is depressed by build hitches - 2400 `LoadAnimation` calls bleeding
  past the settle window. Its **median of 4.40ms** is the trustworthy figure; p95 is 5.52ms, so there is no
  sustained problem.
- At n=1200 the Skeleton sat at the 240 cap in both rows, so its animation cost only resolves at 2400.
- **This does not price the vacuum deform.** `BugGait`'s header is right that a skinned mesh has no
  `SpecialMesh` to write `Scale`/`Offset` onto. See
  [07-scale-size-and-the-vacuum-stretch.md](07-scale-size-and-the-vacuum-stretch.md) - that is the piece that
  decides the whole question.
