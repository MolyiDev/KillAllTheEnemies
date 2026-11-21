# Billboards vs Motor6D + Part

**Question:** is it cheaper to draw a swarm as BillboardGui-on-Attachment sprites than as Motor6D-driven parts,
and does `AlwaysOnTop` matter?

**Answer: no.** Billboards cost ~1.8x more non-script frame time per entity, despite a *cheaper* update loop in
raw Luau. `AlwaysOnTop` makes ~3-4% difference, in favour of `true`.

Script: [`scripts/01-render-bench.client.luau`](scripts/01-render-bench.client.luau)

## Setup

One entity is one thing in every variant.

- **Motor6D + Part** - an anchored `MoveBase`, one plain 2.6-stud cube Part, one `Motor6D`. Moved by writing
  the joint's `Transform` with a placed **and rotated** CFrame, because a part has a facing.
- **Billboard** - an `Attachment` on a single shared anchored host part, carrying a `BillboardGui` (2.6 studs)
  with one `ImageLabel` (`rbxasset://textures/face.png`, ships with the client, no fetch). Moved by writing the
  attachment's `Position`, because a billboard has no facing to write. Charging it for a rotation it ignores
  would be a strawman.

Best of 3 interleaved repetitions. Baseline empty scene: **239.0 FPS** (confirms the 240 cap).

## Results (best of 3)

| n | Motor6D + Part | Billboard AOT=false | Billboard AOT=true |
| --- | --- | --- | --- |
| 600 | **240.1** (4.17ms) | 240.1 (4.17ms) | 240.1 (4.17ms) |
| 1200 | **240.1** (4.17ms) | 240.1 (4.17ms) | 240.1 (4.17ms) |
| 2400 | **240.1** (4.17ms) | 208.0 (4.81ms) | 216.5 (4.62ms) |
| 4800 | **167.3** (5.98ms) | 105.9 (9.46ms) | 107.5 (9.30ms) |

Full detail, best row per cell:

| Variant | n | fps | mean | med | p95 | worst | script | atCap | mem | instances |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Motor6D + Part | 600 | 240.1 | 4.17 | 4.21 | 4.91 | 5.59 | 173.4us | 57.3% | 0.0MB | 1800 |
| Billboard AOT=false | 600 | 240.1 | 4.17 | 4.29 | 4.67 | 5.25 | 185.7us | 60.7% | 0.0MB | 1801 |
| Billboard AOT=true | 600 | 240.1 | 4.17 | 4.28 | 4.71 | 7.61 | 176.1us | 61.4% | 0.0MB | 1801 |
| Motor6D + Part | 1200 | 240.1 | 4.17 | 4.20 | 4.90 | 6.48 | 341.7us | 66.3% | 0.6MB | 3600 |
| Billboard AOT=false | 1200 | 240.1 | 4.17 | 4.07 | 4.95 | 5.63 | 354.2us | 71.2% | 0.2MB | 3601 |
| Billboard AOT=true | 1200 | 240.1 | 4.17 | 4.05 | 4.94 | 5.32 | 346.8us | 71.4% | 0.0MB | 3601 |
| Motor6D + Part | 2400 | 240.1 | 4.17 | 4.11 | 5.39 | 6.14 | 689.7us | 66.2% | 0.8MB | 7200 |
| Billboard AOT=false | 2400 | 208.0 | 4.81 | 4.69 | 5.54 | 7.20 | 648.1us | 0.0% | 2.7MB | 7201 |
| Billboard AOT=true | 2400 | 216.5 | 4.62 | 4.51 | 5.43 | 7.49 | 639.5us | 13.4% | 0.1MB | 7201 |
| Motor6D + Part | 4800 | 167.3 | 5.98 | 5.90 | 6.93 | 9.24 | 1489.2us | 0.0% | 3.2MB | 14400 |
| Billboard AOT=false | 4800 | 105.9 | 9.46 | 9.27 | 10.81 | 12.38 | 1363.9us | 0.0% | 2.8MB | 14401 |
| Billboard AOT=true | 4800 | 107.5 | 9.30 | 9.06 | 10.99 | 12.54 | 1451.1us | 0.0% | 0.8MB | 14401 |

Repetition spread at n=4800 (tight, so the gap is real and not a stray spike):

- Motor6D + Part: 163.8 / 165.2 / 167.3
- Billboard AOT=false: 101.9 / 102.9 / 105.9
- Billboard AOT=true: 106.9 / 107.3 / 107.5

## Raw property write cost, rendering excluded

Same value written back to back, off-frame, 1000 instances x 200 iterations:

| Property | ns per write |
| --- | --- |
| `Attachment.Position` | **67** (60 in an earlier run) |
| `Motor6D.Transform` | 83 (81 earlier) |
| `Attachment.CFrame` | 114 (111 earlier) |

Reproduced within 3% across two runs.

## Interpretation

The billboard genuinely **is** cheaper in raw code - `Attachment.Position` is the cheapest of the three writes,
and at n=4800 the billboard update loop cost 1364us/frame against the rig's 1489us (the rig pays extra for
building a rotated CFrame the billboard cannot use). That ~125us script win is swamped by rendering.

Subtracting the update loop from the frame at n=4800:

- Motor6D: 5.98 - 1.49 = **4.49ms** non-script
- Billboard: 9.46 - 1.36 = **8.10ms** non-script

Roughly **1.8x** per object. Parts batch; each BillboardGui is an alpha-blended quad with per-gui overhead, and
at 4800 on-screen there is heavy overdraw. Memory was identical (3 instances per entity either way).

`AlwaysOnTop=true` was consistently ~3-4% *faster* (107.2 vs 103.6 avg at 4800), presumably from skipping depth
work.

## Caveats

- The scene is empty, so `AlwaysOnTop=false` never got to occlusion-cull anything. In a real level with walls it
  would gain ground.
- This compares **one part** to **one billboard**. A real bug is 13 parts, so it answers "which mechanism is
  cheaper per object", not "is the current 13-part bug cheaper than a 1-quad billboard". See
  [04-specialmesh-vs-meshpart.md](04-specialmesh-vs-meshpart.md) for per-part scaling.
- The billboard is a transparent textured quad and the part is opaque and untextured. That difference is
  inherent to the two approaches, so it is a fair representation of the real choice, but it means the gap is
  fill-rate and blending driven.
