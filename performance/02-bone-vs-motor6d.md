# Bone.Transform vs Motor6D.Transform

**Question:** for moving large numbers of entities, is Ballarc's scheme (a skinned MeshPart parked at the
origin, with its root `Bone.Transform` carrying the world CFrame) faster than a Motor6D rig?

**Answer: yes for movement**, by a clear margin - and the same run turned up the MeshPart-on-Motor6D collapse
documented in [03](03-meshpart-on-motor6d-cliff.md).

Script: [`scripts/02-bone-bench.client.luau`](scripts/02-bone-bench.client.luau)

## Setup

Ballarc's `EnemiesController` writes `bone.Transform = cf` with the MeshPart anchored at the origin - the same
"base at origin, Transform carries the world CFrame" shape `BugsController` uses for `moveJoint`.

Three variants, all with identical layout and motion:

1. **Motor6D + Part** - plain cube Part, reference.
2. **Motor6D + TestMesh** - the *same* `Test` skinned MeshPart as variant 3, bone left at rest, driven by a
   Motor6D. Variants 2 and 3 differ **only** in mechanism.
3. **Bone.Transform** - the `Test` model, MeshPart anchored at origin, root bone carrying the world CFrame.

## Results (best of 3 interleaved repetitions)

| Variant | n | fps | mean | med | p95 | worst | script | atCap |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Motor6D + Part | 1200 | 240.0 | 4.17 | 4.21 | 4.98 | 6.53 | 368.9us | 62.3% |
| Motor6D + TestMesh | 1200 | 193.6 | 5.21 | 4.12 | 5.18 | 43.34 | 378.1us | 67.4% |
| **Bone.Transform** | 1200 | **240.1** | 4.17 | 4.17 | 4.91 | 5.58 | 361.0us | 62.3% |
| Motor6D + Part | 2400 | 240.1 | 4.17 | 4.08 | 5.42 | 6.06 | 721.6us | 68.0% |
| Motor6D + TestMesh | 2400 | 185.2 | 5.56 | 4.17 | 5.40 | 128.09 | 757.7us | 60.9% |
| **Bone.Transform** | 2400 | **240.1** | 4.16 | 4.16 | 4.89 | 5.25 | 709.5us | 66.6% |
| Motor6D + Part | 4800 | 162.3 | 6.16 | 6.09 | 7.15 | 15.20 | 1453.0us | 0.0% |
| Motor6D + TestMesh | 4800 | **9.0** | 114.80 | 8.68 | **322.19** | 419.54 | 1530.8us | 0.0% |
| **Bone.Transform** | 4800 | **204.9** | 5.23 | 4.59 | 6.19 | 290.19 | 1539.9us | 32.8% |

Repetition spread at n=4800:

- Motor6D + Part: 163.8 / 165.2 / 167.3
- Motor6D + TestMesh: 4.2 / 8.5 / 9.0
- Bone.Transform: 147.6 / 186.7 / 204.9

## Raw property write cost, rendering excluded

| Property | ns per write |
| --- | --- |
| `Bone.Transform` | **79** |
| `Motor6D.Transform` | 86 |

~8% in the bone's favour - noise next to the frame difference.

## Camera-away control (n=2400)

Turning the camera off the cluster returned all three to the cap (Motor6D+Part 240.1, Bone 240.1, TestMesh 196.2
with a median of 4.22ms - its mean dragged by a single load spike). Geometry is genuinely culled when off
screen, so the on-screen numbers are real draw cost.

## Interpretation

At the only count where anything separates, the bone is fastest: **204.9 FPS (4.59ms median, still 32.8% of
frames pinned at the cap, so its true cost is lower still)** against 162.3 for plain Motor6D parts.

Writing `bone.Transform` pushes movement entirely into the skinning path; the Motor6D approach makes the engine
maintain 4800 independently-moving assemblies.

It also drops to **2 instances per entity** instead of 3.

## Caveats

- **The bone numbers are, if anything, pessimistic.** Each bone repetition ran immediately after the
  catastrophic `Motor6D + TestMesh` repetition and inherited that degraded state - hence its own spread.
- **You lose engine spatial queries.** Every MeshPart sits at the origin with the bone carrying the world
  CFrame, so raycasts, `GetPartBoundsInBox` and touch see all entities stacked at `(0,0,0)`. That is presumably
  why Ballarc does its own `isVisible` / `RENDER_DISTANCE_SQ` culling. This project already has
  `SpatialHash.luau` for anything positional.
- **This tests one bone.** The `Test` mesh has a single `Root`. Root motion is one write per entity either way;
  per-bone writes for an actual pose scale on top - see [05-animation.md](05-animation.md).
- **Skinned meshes collapse somewhere between 4800 and 7200.** At 7200, bone movement alone measured 193.65ms
  mean / 164.32ms median engine time - about 5 FPS with nothing else happening. The range was never bisected and
  the mechanism was never investigated. Motor6D's own ceiling was never found; it was simply stable at every
  count tested.
- The 4800-count skinned scenes show worst frames around 290ms, but **that is not a skinned-specific weakness** -
  Part rigs throw the same kind of outlier (a slug control hit 1607ms), and on p95 the bone is the better of the
  two. Those maxima are build/teardown churn, not steady state. See the README's note on the ceiling row.
