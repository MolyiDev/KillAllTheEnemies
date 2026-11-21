# Scale, Size, and the vacuum stretch

**This is the finding that decides the architecture.**

`BugsController` deforms a gripped bug by writing `SpecialMesh.Scale` and `SpecialMesh.Offset` - pure render
properties that cost no physics. A skinned MeshPart has no `SpecialMesh`, so the only equivalent is
`MeshPart.Size`, and Size is not a render property: it is geometry the engine has to react to.

Scripts: [`scripts/09-stretch.client.luau`](scripts/09-stretch.client.luau),
[`scripts/10-scale-lifecycle.client.luau`](scripts/10-scale-lifecycle.client.luau)

---

## The stretch, n=2400, grip=40

The deformation asked for is the real one: volume-preserving, the axis along the pull growing and the two across
it shrinking by the square root - so both paths are asked for the same shape, not just the same write count.
Two populations, because the vacuum does not stretch the room: **GRIP 40** (roughly what a cone holds) and
**ALL**.

| Path | frame median | engine median | script |
| --- | --- | --- | --- |
| **SKINNED** move only (control) | 4.14ms | 3.17ms | 948us |
| **SKINNED** `MeshPart.Size`, 40 only | **44.91ms** | 43.62ms | 1227us |
| **SKINNED** `MeshPart.Size`, all 2400 | 53.80ms | 46.36ms | 7142us |
| **TODAY** move only (control) | 5.31ms | 4.27ms | 1035us |
| **TODAY** `Scale`+`Offset`, 40 only | **5.36ms** | 4.31ms | 1070us |
| **TODAY** `Scale`+`Offset`, all 2400 | 13.79ms | 10.20ms | 3600us |

Burst check (one frame in 30 writes Size): change frames engine median **53.65ms**, max 92.75ms, against
**3.63ms** on quiet frames. The cost lands precisely on the writing frame.

## `MeshPart.Size` is a fixed-cost rebuild, not a per-instance cost

Writing Size to **40** meshes costs 43.62ms of engine time. Writing it to **2400** costs 46.36ms. Sixty times
the writes for 6% more cost - so **any** Size write at all triggers roughly the same ~43ms of engine work,
regardless of how many are touched. That is a whole-scene rebuild with a trigger, not work proportional to the
deformation.

Practical consequence: **gripping a single bug would cost the frame.** Deforming 40 takes the scene from 4.14ms
to 44.91ms - 83 FPS down to 18.

## Today's stretch is effectively free at grip scale

`SpecialMesh.Scale`+`Offset` on 40 meshes costs **+0.05ms** over its control (5.36 vs 5.31ms). Deforming *all
2400* still only costs +8.5ms - **five times cheaper than writing Size to just 40**. At the realistic grip count
the gap is roughly **800x**.

---

## `Model:ScaleTo` - does not dodge it on skinned, but is usable on Part rigs

There is **no `Model.Scale` property** in this engine version; reading it throws. The API is `Model:ScaleTo(n)`
and `Model:GetScale()`, which is what `getPool` already calls on pool templates.

| Rig | control (engine) | `ScaleTo` on 40 (engine) | script delta |
| --- | --- | --- | --- |
| **Skinned** | 3.17 / 3.53ms | **42.90 / 43.45ms** | +0.5ms |
| **Part rig (Slug)** | 13.62ms | **15.11ms** (+1.49ms) | +2.91ms |

On the skinned mesh, `ScaleTo` costs ~43ms - indistinguishable from writing `MeshPart.Size` directly (43.62ms),
because that is what it does underneath. Measured twice.

On a Part rig it is a different story: **+1.49ms of engine** for 40 models. The bulk of its cost there is Luau
(+2.91ms) walking the model and scaling parts and joints, **~73us per model**. No rebuild.

Also measured, skinned `ScaleTo` on ALL 2400: 76.03ms frame median, 57.69ms engine, 18344us script - the Luau
cost of 2400 `ScaleTo` calls dominates on top of the same rebuild.

### So the rebuild belongs to MeshPart geometry, not to scaling

Part rigs scale without it. Practically:

- `ScaleTo` **is** a viable occasional tool on the existing Part rigs - size buckets, an arrival pop, a growth
  effect - at ~73us per bug.
- It is **not** a per-frame tool: still ~90x more expensive than `SpecialMesh.Scale`'s +0.05ms for 40.
- It remains unusable on skinned meshes.
- Uniform scale cannot do the stretch anyway, which is non-uniform by construction.

---

## Verdict

There is no cheap deformation path on a skinned mesh. Bones carry rotation and translation but **not scale**, so
`MeshPart.Size` is the only lever and it rebuilds. Whatever the bone approach wins on movement (~6.3ms vs
~10.2ms per frame at 4800), the vacuum alone would cost ~40ms a frame and erase it many times over.

`BugGait`'s header called this out - *"a skinned mesh has no SpecialMesh to write Scale and Offset onto, and the
deform is the whole feel of the vacuum"* - and the numbers back it much harder than the comment claims.

## Caveats

- The skinned control showed a 618ms max frame; those 2400-skeleton scenes stay hitchy, consistent with every
  other run. The medians are clean and the effect is far too large to be noise.
- The two controls differ (4.14 vs 5.31ms) because the geometry differs, which is why each path is compared
  against its own control rather than against each other.
- `CollisionFidelity = Box` was never tested as a way to avoid the Size rebuild - a LocalScript cannot write
  that property. Same open thread as [03](03-meshpart-on-motor6d-cliff.md).
