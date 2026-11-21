# BoneGrid: many entities per MeshPart

> **Superseded in part by [11-packing-sweet-spot.md](11-packing-sweet-spot.md).** This doc benchmarks 100
> elements per mesh and treats that as the win. A later sweep found **25-50 is the sweet spot** and 100 sits on
> a ~35% worse plateau: at 19200 entities, 50 per mesh gives 9.49ms where 100 gives 13.05ms. The conclusion that
> packing beats one-mesh-per-entity stands; the specific number 100 does not.

**Question:** the skinned ceiling is ~4800 *instances* while a bone write costs 79ns. If the binding constraint
is MeshPart count rather than the number of moving things, does packing many entities into one skinned mesh move
the ceiling?

**Answer: yes, by roughly 4-8x.** Clean to ~19200 entities where one-mesh-per-entity was already broken at 7200.
But the bottleneck moves to your own Luau loop, and you lose per-entity frustum culling.

Asset: [`assets/BoneGrid100.fbx`](assets/README.md) - one skinned mesh, 100 cubes, each bound 1:1 to its own bone
at weight 1.0. Scripts: [`scripts/12-bonegrid.client.luau`](scripts/12-bonegrid.client.luau) (sweep),
[`scripts/13-bonegrid-validity.client.luau`](scripts/13-bonegrid-validity.client.luau) (controls).

## Instance arithmetic

The bones remain real Instances - only the MeshPart count falls:

| | 4800 entities as Skeletons | 4800 entities as BoneGrid |
| --- | --- | --- |
| MeshParts | 4800 | **48** |
| Bones | 4800 | 4800 |
| total instances | 9600 | 4848 |

So this tests specifically whether **MeshPart** count is what binds.

## Sweep (adaptive settle, every row converged, all on screen)

| entities | meshes | build | fps | mean | median | p95 | worst | script | engine (med) | atCap |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2400 | 24 | 272ms | 240.1 | 4.17 | **4.17** | 4.93 | 5.39 | 745us | - | 68.6% |
| 4800 | 48 | 581ms | 231.5 | 4.32 | **4.20** | 5.10 | 22.23 | 1511us | - | 63.5% |
| 9600 | 96 | 1157ms | 133.9 | 7.47 | **7.36** | 8.60 | 10.22 | 3021us | 4.34 | 0.0% |
| 19200 | 192 | 1956ms | 73.2 | 13.67 | **13.55** | 15.12 | 16.72 | 6044us | 7.50 | 0.0% |
| 38400 | 384 | 4803ms | 25.8 | 41.44 | **38.07** | 56.59 | 396.02 | 13180us | 24.89 | 0.0% |
| 76800 | 768 | 9991ms | 6.6 | 162.87 | **45.68** | **436.38** | 460.67 | 24743us | 20.94 | 0.0% |

The 2400 and 4800 rows are cap-limited, so their engine figures are meaningless.

## Against one-mesh-per-entity ([09](09-skinned-ceiling.md))

| entities | one MeshPart each | BoneGrid (100 per mesh) |
| --- | --- | --- |
| 4800 | 5.60ms med / 6.80 p95 (clean) | 4.20ms med (at cap) |
| 6000 | 6.68ms med / **212.73 p95** (tail broken) | - |
| 7200 | **44.77ms med** (broken) | - |
| 8400 | 225.99ms med (dead) | - |
| 9600 | far past dead | 7.36ms med / 8.60 p95 |
| 19200 | - | **13.55ms med / 15.12 p95 (clean)** |
| 38400 | - | 38.07ms med / 56.59 p95 (degraded) |
| 76800 | - | 45.68ms med / **436 p95** (tail broken) |

**The usable ceiling moves from ~4800 to somewhere around 19200-38400.** BoneGrid's median does not reach the
44.77ms that broke individual meshes at 7200 until past 38400 entities.

Per-entity engine cost is also lower: ~0.39-0.45us for BoneGrid at 9600-19200, against ~0.74us for individual
skeletons at 4800.

## Validity: the geometry really is being drawn

Every cube rests on the origin, so each MeshPart's bounding box is one 2x2x2 cube while its bones throw geometry
across the screen. If Roblox culled the displaced geometry against that box, nothing would render and the whole
sweep would be measuring bone writes and nothing else.

The first attempt at this control ran at 4800 where 63% of frames were pinned at the 240 cap, so LOOK and AWAY
matched for a trivial reason - **that control was worthless**. Re-run at uncapped counts, with a third condition
that does not depend on the camera at all (every bone written to 2^24, so identical instance count and identical
write count with the geometry in the void):

| n | LOOK (engine) | AWAY (engine) | PARKED (engine) | LOOK vs AWAY | LOOK vs PARKED |
| --- | --- | --- | --- | --- | --- |
| 9600 | 8.33ms | 1.97ms | 3.13ms | **4.24x** | **2.67x** |
| 19200 | 7.35ms | 3.38ms | 2.88ms | **2.17x** | **2.55x** |

Drawing confirmed, and the bounding-box culling risk did not materialise in this layout.

## Two things that change how you would use this

### The bottleneck moves from the engine to Luau

Per-entity script cost is a flat **~0.31-0.34us** at every count (it is one Transform write plus the CFrame
math). But in absolute terms:

- 19200: script 6.04ms of a 13.55ms frame - 45%
- 38400: script 13.18ms of 38.07ms - 35%
- 76800: script **24.74ms of 45.68ms - 54%**

Past roughly 20k entities your own update loop is the larger half of the frame. Optimising rendering stops
helping there; the write loop is what you would attack (parallel Actors, fewer writes per frame, LOD on update
rate).

### You lose per-entity frustum culling, and this benchmark is its best case

Culling is per-MeshPart. Every MeshPart's bounds are one 2x2x2 cube at the origin **regardless of where its
bones threw the geometry**. In this benchmark everything was on screen, which costs that nothing.

In a real floor where most bugs are off camera, individual meshes cull individually while BoneGrid can only cull
in all-or-nothing blocks of 100 - from bounds that do not describe where the geometry actually is. **This is
untested and it is the most likely thing to bite.**

The fix would be spread-out rest positions (so a mesh's bounds cover a real region) plus assigning entities to
meshes by locality so a block is coherent enough to cull as a unit. That is real complexity, and it trades away
the clean `bone.Transform = <world CFrame>` mapping for offset-from-rest.

## Caveats

- **At 9600 the two runs disagreed by ~50%** (7.36ms vs 11.54ms median). At 19200 they agreed exactly (13.55 vs
  13.54). Treat the 9600 row as soft.
- Build cost scales badly at the top: 768 instances x 101 sub-instances took ~10s even chunked.
- 100 elements per mesh is the only packing tested. Whether 50 or 250 behaves differently - particularly for
  culling granularity - is unknown.
- Cubes, not real bug geometry. A 13-part roach cannot be expressed as one bone; a skinned bug would need one
  bone per moving limb, so a "100 entity" mesh would really be ~20 bugs at 5 bones each. Divide the entity
  counts here accordingly for any real migration.
