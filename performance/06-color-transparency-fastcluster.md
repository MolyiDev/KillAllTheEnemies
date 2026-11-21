# Colour, transparency and FastCluster rebuilds

**Context.** Roblox's ["Making Avatar Rendering More Performant"](https://devforum.roblox.com/t/making-avatar-rendering-more-performant/4147160)
(12 Dec 2025) promised:

> In early 2026, we will release an update to eliminate the need for FastCluster to be rebuilt due to changes to
> `Part.Color`, `Part.Transparency`, and `SurfaceAppearance.Color`.

Roblox staff (stormchaser9k) later added in-thread:

> To clarify, the optimization we put in should not cause a full FastCluster rebuild, but we still need to run a
> check to ensure we can skip the rebuild, which in some avatar configurations could show up in the
> Microprofiler, but it shouldn't be more than ~1-2 ms. [...] Note that the transparency (and color) change
> optimization has been rolled out for several months, so if you are still getting significant FastCluster
> rebuild time for transparency/color changes, please submit a reproducible case for us to debug.

and, on what still triggers rebuilds:

> It could rebuild the Skeleton due to constraint changes, adding / removing parts, or generally hierarchy
> changes. [...] Yes models that contain skinned meshes or Humanoid. A single buildSkeleton is for a single rig
> under a Model or under the Workspace itself.

Also relevant: the [SurfaceAppearance Tinting full release](https://devforum.roblox.com/t/surfaceappearance-tinting-is-live-in-production-client-beta/3129960)
(22 Aug 2024) states "SurfaceAppearance Tinting comes at no performance cost", and
[EditableImage support for SurfaceAppearance](https://devforum.roblox.com/t/in-experience-build-a-texture-editableimage-support-for-surfaceappearance/3866947)
(26 Jan 2026) is a separate 2026 feature - with a reported limit of one `EditableImage` update per frame.

Scripts: [`scripts/06-tint.client.luau`](scripts/06-tint.client.luau),
[`scripts/07-cluster.client.luau`](scripts/07-cluster.client.luau),
[`scripts/08-skinned-props.client.luau`](scripts/08-skinned-props.client.luau)

---

## Summary

| Property | Skinned mesh | Part rig | Matches the claim? |
| --- | --- | --- | --- |
| `SurfaceAppearance.Color` | free | n/a | **yes** |
| `Part.Color` | free | cheap, bounded (+4.8ms / 9000 parts) | **yes** |
| `Part.Transparency` | ~15-19us each, only when crossing 0 | free at 4500 parts, **~1000ms** at 9000 | **partly** - fine at avatar counts, not at swarm scale |

---

## SurfaceAppearance.Color - free

`SurfaceAppearance.Color` is writable at runtime from a LocalScript and the value sticks (readback confirmed).

n=1200 skeletons (sentinel median 4.22ms):

| Variant | median | p95 | worst | script |
| --- | --- | --- | --- | --- |
| move only | 4.18ms | 5.10 | 71.69 | 432us |
| tint every frame, **new** value | 4.10ms | 5.05 | 6.98 | 1403us |
| tint every frame, **same** value | 4.18ms | 4.95 | 5.33 | 548us |
| tint burst every 60 frames | 4.17ms | 4.96 | 5.55 | 457us |

n=2400 (sentinel median 4.11ms):

| Variant | median | script |
| --- | --- | --- |
| move only | 4.10ms | 954us |
| tint every frame, **new** value | **6.21ms** | 3164us |
| tint every frame, **same** value | 4.13ms | 1244us |

**Burst analysis** (frames following a mass change vs quiet frames, shifted one frame):

| n | after a mass tint change | quiet frames |
| --- | --- | --- |
| 1200 | mean **4.28ms**, max **5.01ms** (20 events) | mean 4.16ms, max 5.55ms |
| 2400 | mean **6.84ms**, max **7.52ms** (16 events) | mean 5.02ms, max 171ms |

At 1200 the change frames are not even the *worst* frames. At 2400 the +1.82ms is fully accounted for by the
Luau write cost (2.21ms measured separately), so the render side added nothing.

**The engine early-outs on unchanged values:** a genuinely new colour costs ~0.9us per SurfaceAppearance;
writing the same value back costs ~0.11us - about 8x cheaper.

The 163-172ms worst frames at n=2400 appear in the **move-only** row too (167ms). Those are build hitches from
spawning 2400 skeletons, not tint-related.

---

## Engine-time isolated: what the residual check costs

Using `engine = frameTimes[N+1] - updateTimes[N]`, change frames vs quiet frames in the same run.

### Skinned mesh, n=2400 (quiet median 3.0-4.4ms)

| Property | change median | change max | delta |
| --- | --- | --- | --- |
| `Part.Color` | 3.37ms | 4.04ms | **-0.55ms** (free) |
| `SurfaceAppearance.Color` | 3.17ms | 4.26ms | **-0.85ms** (free) |
| `Transparency` **WITHIN** 0.5<->0.6 | 4.97ms | 5.98ms | **-0.65ms** (free) |
| `Transparency` **CROSS** 0<->0.5 | **49.29ms** | 93.36ms | **+34.59ms** |

On skinned meshes the opaque/transparent **boundary** is what costs - ~15-19us per mesh when a part moves
between the opaque and transparent render passes. Changing transparency while already transparent is free.

**The n=4800 skinned block is unusable for transparency** and is excluded: the CROSS row caught *one* change
sample and quiet frames had a 219ms median (worse than the change frames, which is why its delta reads
negative). The colour rows at 4800 stayed clean (max ~5.5ms) and do hold.

### Part rigs (Slug), n=1800 = 9000 parts

| Variant | delta (engine) | change median | change max |
| --- | --- | --- | --- |
| control / `Part.Color` | -14.8 / **+4.79ms** | 18.44ms | 20.34ms |
| Transparency, original cycle 0/.2/.4/.6 | **+769ms** | 998ms | 1054ms |
| Transparency **WITHIN** 0.5<->0.6 | **+1033ms** | 1055ms | 1064ms |
| Transparency **CROSS** 0<->0.5 (run **first**) | +481ms | 70.7ms | 1008ms |
| Transparency **CROSS** 0<->0.5 (run **last**) | +606ms | 58.7ms | 1041ms |

Quiet frames in the same runs sat at 14-16ms median. An earlier run measured the same original cycle at
+749ms - reproduced.

### Part rigs, n=900 = 4500 parts

Everything free. `CROSS` -0.07ms (max 4.94ms), `WITHIN` +0.05ms, `SAME` (no-op write) -0.05ms,
`COLOR` -0.01ms.

## Two hypotheses killed

- **Not run order or session degradation.** The transparency stall reproduces when it runs *first*, before
  anything else has built and torn down a scene.
- **Not the opaque/transparent boundary** - on Part rigs. `WITHIN` (0.5 <-> 0.6, never touching zero) is the
  *worst* row at +1033ms. That hypothesis does hold on skinned meshes, where only `CROSS` costs. The two paths
  behave differently.

## It is a threshold on Part rigs, not a slope

Free at 4500 parts, ~1 second at 9000. Something crosses a threshold in between. On skinned meshes the cost is
instead roughly linear per mesh and only at the boundary.

## Honest limits

- The transparency change-frame sample counts are tiny (n=3-5) precisely **because** each event eats ~1s of a 6s
  window. The effect reproduced across four independent runs and is ~60x the quiet median, so its existence is
  not in doubt - the exact magnitudes are soft. The CROSS medians (59-71ms) vs WITHIN/ORIGINAL (~1000ms) vary
  more than can be explained here.
- Quiet frames in that regime also show 409ms and 644ms outliers, so the whole state is unstable.
- The slug rigs are Models with Motor6Ds but **no Humanoid and no skinned mesh**, so per staff this is not
  `buildSkeleton` - it is whatever path `Part.Transparency` takes for Part rigs.
- Part counts could not be matched between the two paths: 4800 skeletons = 4800 parts, and the slug cliff sits
  between 4500 and 9000 parts, but ~7200 skinned meshes collapse for unrelated reasons. So whether skinned
  meshes would hit a similar cliff further up is **unknown**.
- Only `Color` was tested. `ColorMap` / `NormalMap` / `RoughnessMap` are not script-assignable at runtime.

## Verdict on the post's claim

Scaled to the counts the post is about - avatars, tens to low hundreds - ~15us per mesh is well under 1ms, which
matches the "~1-2 ms" figure. **The claim holds for its intended audience.** What these measurements add is that
a residual cost becomes visible at swarm scale.

## Consequence for this project

**Do not fade bugs with `Transparency` at swarm scale.** `BugsController` parks bugs at `FAR_AWAY_CFRAME`
instead, and the comment justifies it on instruction count ("a Transparency write is one property, a whole rig's
worth of Transparency is a dozen"). The real justification is much stronger. `Part.Color` is the cheap
alternative if a tint effect is ever wanted.

**A repro case for Roblox exists** and staff asked for one: N slug rigs, burst-write `Transparency`, watch the
900 -> 1800 rig cliff. `scripts/07-cluster.client.luau` is that repro.
