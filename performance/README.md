# Rendering performance investigation

Everything measured in Roblox Studio on **2026-08-06**, in the `Game` place, against the real `Roach` / `Slug`
rigs and a purpose-built skinned `Test` / `Skeleton` mesh.

**Verdict: keep the current architecture.** Bugs authored as Parts wearing SpecialMeshes, driven by writing
`Motor6D.Transform`, beat every alternative tested on the axes that decide this game. The decisive one is the
vacuum stretch: it is nearly free today and effectively impossible on a skinned mesh.

---

## Contents

| File | What is in it |
| --- | --- |
| [METHODOLOGY.md](METHODOLOGY.md) | How the harness works, and **every measurement trap hit along the way**. Read before trusting or extending any of this. |
| [01-billboards-vs-motor6d.md](01-billboards-vs-motor6d.md) | BillboardGui-on-Attachment vs Motor6D + Part |
| [02-bone-vs-motor6d.md](02-bone-vs-motor6d.md) | `Bone.Transform` (Ballarc's scheme) vs `Motor6D.Transform` |
| [03-meshpart-on-motor6d-cliff.md](03-meshpart-on-motor6d-cliff.md) | The MeshPart-in-a-Motor6D-assembly collapse, and what it is *not* |
| [04-specialmesh-vs-meshpart.md](04-specialmesh-vs-meshpart.md) | Does Part+SpecialMesh hit that cliff? (No.) |
| [05-animation.md](05-animation.md) | Procedural `BugGait` vs a per-entity `AnimationTrack` |
| [06-color-transparency-fastcluster.md](06-color-transparency-fastcluster.md) | `SurfaceAppearance.Color`, `Part.Color`, `Part.Transparency` vs Roblox's FastCluster claims |
| [07-scale-size-and-the-vacuum-stretch.md](07-scale-size-and-the-vacuum-stretch.md) | `MeshPart.Size`, `Model:ScaleTo`, `SpecialMesh.Scale`+`Offset` |
| [08-spawn-despawn.md](08-spawn-despawn.md) | Pooling cost: skinned mesh vs Part rig |
| [09-skinned-ceiling.md](09-skinned-ceiling.md) | Where skinned meshes actually stop working, and why the earlier answer was wrong |
| [10-bonegrid-many-per-mesh.md](10-bonegrid-many-per-mesh.md) | Packing 100 entities into one skinned mesh - moves the ceiling ~4-8x |
| [11-packing-sweet-spot.md](11-packing-sweet-spot.md) | **How many per mesh? 25-50, not 100** - corrects doc 10 |
| [12-bugpack-animation.md](12-bugpack-animation.md) | Animating packed bugs: engine Animator vs bone writes in code |
| [13-damage-flash-tint-vs-highlight.md](13-damage-flash-tint-vs-highlight.md) | The white damage flash: `SurfaceAppearance.Color` vs five ways of driving a `Highlight` |
| [14-enemy-spawn-with-highlight.md](14-enemy-spawn-with-highlight.md) | What it costs to spawn and despawn enemies that carry a `Highlight`, and how many fit in one frame |
| [16-shell-ripple-mechanism.md](16-shell-ripple-mechanism.md) | The Core shell's impact ripple: a panel lattice on `Motor6D` vs `EditableMesh` vertex displacement, at four resolutions. **Every EditableMesh limit worth knowing is here** |
| [15-luau-idioms.md](15-luau-idioms.md) | **Not a rendering investigation.** Every Luau performance rule in `CLAUDE.md`, checked against [luau.org/performance](https://luau.org/performance) and then measured. Two rules were wrong |
| [assets/](assets/) | The `BoneGrid100` skinned mesh and the Blender script that generates it |
| [scripts/](scripts/) | Archival copies of every benchmark LocalScript, as run |

---

## Bone vs Motor6D, side by side

### Per-frame operations

| Operation | Motor6D + Part rig | Bone + skinned mesh | Winner |
| --- | --- | --- | --- |
| Position + rotation (raw write) | `Motor6D.Transform` 86ns | `Bone.Transform` 79ns | Bone, marginally |
| Position + rotation (frame @4800) | 6.09ms median | 4.59ms median | **Bone** |
| Colour | +4.8-6.6ms per 9000 parts (~0.6us each), bounded | free (-0.6ms at 2400) | **Bone** |
| Transparency, staying transparent | free at 4500 parts, **~1000ms stall** at 9000 | free (-0.65ms at 2400) | **Bone** |
| Transparency, crossing 0 | same threshold cliff | +34.6ms at 2400 (~15-19us each), bounded | **Bone** |
| Uniform scale (`Model:ScaleTo`, 40) | +1.5ms engine (~73us/model) | **+42.9ms**, full rebuild | **Motor6D** |
| Size (`Part.Size` / `MeshPart.Size`) | via ScaleTo, ~73us/model | **~43ms fixed**, for even one write | **Motor6D** |
| Non-uniform deform (the vacuum stretch) | +0.05ms for 40 | **not possible** | **Motor6D**, decisively |
| Skeletal animation | ~1.3us/entity, on the Luau thread | ~0.14us/entity, **zero Luau** | **Bone** |

### Per-entity structure and lifecycle

| Property | Motor6D + Part rig | Bone + skinned mesh | Winner |
| --- | --- | --- | --- |
| Instances per entity | 12 (slug) / 27 (13-part roach) | 3 | Bone |
| Render cost @2400 entities | 19.14ms (6-part slug) | 4.06ms | **Bone** |
| Spawn cost | ~3.8-4.6ms each | ~1.4-1.7ms each | **Bone** |
| Despawn tail @2400 | 2562ms excess, 2322ms worst frame | 666ms excess, 522ms worst | **Bone** |
| Demonstrated ceiling | stable at 4800 (162 FPS); **limit never found** | **~4800.** Clean to 4800 (5.60ms med, 6.80ms p95); tail breaks at 6000 (p95 212ms); median breaks at 7200 (44.77ms) | **Motor6D**, with a caveat - see below |
| Engine spatial queries | **work** - `Part1.CFrame` tracks the Transform | **broken** - MeshPart stays at origin | **Motor6D** |
| Per-limb control (colour, alpha, deform) | yes, per part | no, one value per entity | **Motor6D** |

Bones win most individual rows and lose the two that decide the architecture. Note that the two biggest bone
wins - render cost per entity and churn - are really **part-count** wins, not mechanism wins: one skinned animal
is 1 part where a roach is 13.

### On the "demonstrated ceiling" row

This row is **asymmetric evidence**, not a measured comparison. What was actually established:

- **Skinned has a real ceiling, and it was bisected in [09](09-skinned-ceiling.md): ~4800.** Clean to 4800
  (median 5.60ms, p95 6.80ms), tail breaks at 6000 (median still 6.68ms but p95 **212.73ms**), median breaks at
  7200 (44.77ms), uniformly dead at 8400 (226ms). The mechanism was not identified, but the stall duration is
  constant (240-253ms) across counts while its *frequency* climbs, which looks like a fixed-cost operation
  recurring more often rather than work growing with entity count.
  - An earlier draft said "collapses between 4800 and 7200" based on a 164ms median at 7200. That number was
    inflated by build contamination - 7200 skeletons is ~10s of build CPU against a 2s settle. With a proper
    settle it is 44.77ms. The ceiling was real but placed too high.
- **Motor6D's ceiling is unknown.** It was stable at 4800 entities (162 FPS, median 6.09ms, p95 7.15ms) and was
  never pushed higher. "Motor6D wins" here means only "the skinned path has a demonstrated limit and this one
  does not, within what was tested".

**Do not read this row as "Part rigs have smoother frame times".** An earlier draft of this file claimed skinned
scenes threw worse outlier frames (244-618ms) at 2400-4800. Those maxima are real but they are **not**
skinned-specific:

- On p95 at 4800 the bone is *better* than Part+SpecialMesh (9.25 / 9.80ms vs 12.01 / 11.90ms).
- Part rigs hitch just as hard - the slug move-only control threw a **1607ms** worst frame, and Part+SpecialMesh
  threw 923ms and 890ms in pass 2 of the same run where it showed 14ms in pass 1.

Those are build and teardown churn leaking past the settle window (METHODOLOGY trap 6), and both paths do it.
Judge tail behaviour by p95, not by the `worst` column.

---

## Decisions this supports

1. **Do not migrate bugs to skinned MeshParts.** The vacuum stretch is +0.05ms today for a 40-bug grip and
   ~43ms on a skinned rig, where the only lever is `MeshPart.Size` and it triggers a near-fixed rebuild.
2. **Keep authoring bugs as Parts wearing SpecialMeshes, not MeshParts.** A MeshPart inside an unanchored
   Motor6D assembly falls off a cliff at scale (2.5-16 FPS, p95 frame times of 1.2-1.6 **seconds**). Part rigs
   do not. The `CLAUDE.md` note about this is load-bearing for a second reason beyond the deform.
3. **Keep parking bugs at `FAR_AWAY_CFRAME` instead of fading them.** `Part.Transparency` on Part rigs is free
   at 4500 parts and costs ~1000ms stalls at 9000. The comment in `BugsController` justifies parking on
   instruction count; the real reason is far stronger.
4. **Keep `ObjectPooler`.** One skinned mesh costs ~1.4ms to spawn and one slug rig ~3.8ms - a third to a whole
   frame per bug at 240fps. Pooling is a requirement, not an optimisation.
5. **Billboards are not an upgrade.** ~1.8x more non-script frame time per entity than a Motor6D part, despite
   a cheaper update loop in raw Luau.

## Open threads

- **`CollisionFidelity` is the leading unconfirmed hypothesis** for both the MeshPart-on-Motor6D cliff and the
  `MeshPart.Size` rebuild. A LocalScript cannot write it (needs Plugin capability), so it was never tested.
  To close it: set `CollisionFidelity = Box` on the template in edit mode, re-run
  [03](03-meshpart-on-motor6d-cliff.md) and [07](07-scale-size-and-the-vacuum-stretch.md), then set it back.
- **`BugGait`'s header argument against AnimationTracks is wrong on cost.** A per-entity Animator costs
  ~0.14us/entity and zero Luau time; the LUT costs ~1.3us/entity on the Luau thread. The conclusion (keep the
  LUT) still holds because a skinned mesh loses the stretch - but the stated reasoning does not match measurement.
- **A repro case for Roblox exists** for the remaining `Part.Transparency` rebuild time; staff explicitly asked
  for one. See [06](06-color-transparency-fastcluster.md).
