# The MeshPart-on-a-Motor6D cliff

**Finding:** a `MeshPart` inside an **unanchored Motor6D assembly** falls off a cliff at scale - 2.5-16 FPS with
p95 frame times of **1.2-1.6 seconds** - while the identical mesh anchored and written straight to `.CFrame` is
stable, and a plain cube Part on a Motor6D is completely fine.

This matters because the `Test` mesh is cube-shaped with 8 vertices. Geometry was never the explanation.

Script: [`scripts/03-mesh-isolation.client.luau`](scripts/03-mesh-isolation.client.luau)

## What was isolated

Four things differ between a Part and that MeshPart. Each was varied one at a time, all at n=4800:

| Variable | Tests |
| --- | --- |
| bone present or not | is it the skinned / deformable render path |
| `CastShadow` on/off | is it re-skinning every instance into the shadow map |
| joint or no joint | anchored MeshPart written straight to `.CFrame` uses no Motor6D and no assembly |
| `CollisionFidelity` | **untestable** - a LocalScript lacks the Plugin capability to write it |

## Sentinel: the run is valid

The cube-Part sentinel ran 14 times interleaved through both passes, including immediately after every collapse:

    pass1  137.4  160.9  160.2  161.4  159.2  159.4  161.0   fps
           6.57   6.18   6.16   6.11   6.23   6.21   6.19    ms median
    pass2  161.8  154.7  158.4  161.4  155.6  158.4  165.5   fps
           6.18   6.34   6.28   6.15   6.35   6.31   6.00    ms median

Medians 6.00-6.57ms throughout (one 6.57 outlier at startup). **No session drift**, so the differences below are
real. This control exists because an earlier single-pass run produced three mesh variants at 46.8 / 4.0 / 3.2
FPS - a perfect monotonic decline that tracked run order, not the variable under test.

## Results at n=4800 (pass 1 / pass 2)

| Variant | median | p95 |
| --- | --- | --- |
| M6D + cube Part (sentinel) | 6.0-6.6ms | ~7ms |
| **Bone.Transform** | 4.69 / 6.45ms | 7.95 / 8.97ms |
| CFrame + Mesh, NO bone, **no joint** | 14.04 / 13.53ms | 15.50 / 15.22ms |
| CFrame + Mesh, bone, **no joint** | 18.92 / 18.24ms | 20.12 / 19.55ms |
| M6D + Mesh (bone, shadow) | 8.87 / **270.05**ms | **445 / 1646ms** |
| M6D + Mesh (NO bone) | 268.01 / 208.19ms | **1258 / 1553ms** |
| M6D + Mesh (bone, NO shadow) | 363.98 / 391.59ms | **1400 / 1558ms** |

Script cost for the no-joint rows: 12416 / 11876us (with bone) and 10578 / 10222us (without) - direct `.CFrame`
writes on 4800 parts are expensive in Luau but produce a **stable** frame.

## What it is NOT

- **Not the bone / skinning.** Removing the bone entirely does not fix it (4.2 / 4.4 FPS). It gets *worse*.
- **Not shadows.** `CastShadow = false` does not fix it (3.1 / 2.5 FPS).
- **Not run order or session degradation.** The sentinel recovers to ~160 FPS immediately after every collapse.

## What it IS

Specifically **a MeshPart inside an unanchored Motor6D assembly**, at scale. The isolating control is the
no-joint row: same mesh, same geometry, same count, anchored and written straight to `.CFrame` gives
**54-73 FPS, stable, p95 ~15-20ms**. Put that identical mesh on a Motor6D and it is 2.5-16 FPS with p95 spikes
of 1.2-1.6 seconds. A cube Part on a Motor6D is fine at ~160 FPS.

The second-long stalls are on the physics/assembly side, not the renderer.

## Unconfirmed hypothesis

**Collision geometry.** A `MeshPart` defaults to `CollisionFidelity.Default`, which builds a real collision
mesh, while a cube Part gets a trivial box - and 4800 of those being maintained on unanchored assemblies matches
the stall pattern.

**This was never tested**, because `CollisionFidelity` is not writable from a LocalScript ("lacking capability
Plugin"). To close it: set `CollisionFidelity = Box` on the template in edit mode, re-run, set it back.

## Consequence

The current rigs are **Parts wearing SpecialMeshes, not MeshParts** (`measureRig` keys off
`instance:IsA("SpecialMesh")`, and `CLAUDE.md` calls the choice out explicitly). That is the cube-Part case, the
one that runs at ~160 FPS. **The existing Motor6D system does not touch this cliff at all.**

If bug rigs are ever migrated to MeshParts, do not hang them off Motor6Ds without re-checking this first.
See [04-specialmesh-vs-meshpart.md](04-specialmesh-vs-meshpart.md) for the direct confirmation.
