# Part+SpecialMesh vs MeshPart, one part against one part

**Question:** does a Part wearing a `SpecialMesh` - what bugs are actually authored as - hit the
MeshPart-on-Motor6D cliff from [03](03-meshpart-on-motor6d-cliff.md)?

**Answer: no.** It is completely stable at every scale tested.

Script: [`scripts/04-meshkind.client.luau`](scripts/04-meshkind.client.luau)

## Setup

- **Part+SpecialMesh** - `Roach.Body` exactly as authored: a `Part` of 0.4 x 0.2 x 0.9 with a `SpecialMesh`
  (`MeshType = FileMesh`, `Scale = 1,1,1`), `CastShadow` off. Its child joints and Sound are stripped so it is a
  single part and nothing else.
- **MeshPart** - the `Test` skinned mesh, 2 x 2 x 2, the variant that collapsed. Positive control: if this does
  *not* collapse, the run is broken.
- **Scaled variant** - the same Part+SpecialMesh grown x2.2 to roughly the Test mesh's footprint, so a win
  cannot be waved away as "it is just smaller on screen".

Sentinel between every variant, two passes (forward and reversed), n=4800.

## Sentinel

    pass1  122.5(6.31)  164.2(6.03)  162.0(6.08)  161.2(6.12)  159.2(6.14)
    pass2  159.8(6.13)  162.3(6.15)  158.6(6.14)  166.2(5.96)  151.5(6.52)

Flat (one startup outlier). The comparison holds.

## Results at n=4800 (pass 1 / pass 2)

| Variant | median | p95 | worst |
| --- | --- | --- | --- |
| cube Part (sentinel, no mesh) | ~6.1ms | ~7.1ms | - |
| **Bone.Transform** | 6.19 / 6.36ms | 9.25 / 9.80ms | 595 / 597ms |
| **Part + SpecialMesh (as authored)** | 10.40 / 10.21ms | 12.01 / 11.90ms | 14 / 924ms |
| **Part + SpecialMesh (scaled x2.2)** | 9.93 / 10.06ms | 11.10 / 11.76ms | 14 / 890ms |
| MeshPart on Motor6D (positive control) | 296.21 / 335.04ms | **1407 / 1842ms** | 1407 / 1842ms |

## Interpretation

**Part+SpecialMesh on a Motor6D is stable.** Median ~10ms and p95 ~12ms, reproduced across both passes and both
scales. The MeshPart doing the same job in the same session has a **30x worse median and a 150x worse p95** -
p95 of 1.4-1.8 seconds means more than one frame in twenty takes over a second. Two different regimes, not two
points on a curve.

**Footprint is not the explanation.** Scaling the roach body 2.2x to match the Test mesh's size moved the median
from 10.40 to 9.93ms - i.e. nothing.

## Note on the `worst` column

Pass 1 showed a 14ms worst frame for both SpecialMesh rows; pass 2 showed isolated ~900ms frames. With p95 still
at ~12ms, those are one hitch per run (build churn leaking past the settle window), **not** a sustained cost.
`Bone.Transform` shows the same isolated-hitch pattern (worst ~595ms, p95 ~9.5ms). Only the MeshPart has it in
the p95. Do not read the `worst` column without the p95 next to it.

## Scale context

4800 parts is roughly **370 roaches** at 13 parts each, and that ran at 96-100 FPS. The mesh itself costs about
4ms over bare parts at that count, ~0.85us per part.

Ranking of the mesh-bearing options at 4800:

    Bone (~6.3ms)  <  Part+SpecialMesh (~10.2ms)  <<  MeshPart+Motor6D (~300ms)

The bone row draws a 2x2x2 cube mesh and the SpecialMesh row draws the actual roach mesh, so that ~4ms gap is
partly geometry, not purely mechanism.
