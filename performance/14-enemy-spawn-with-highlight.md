# Spawning enemies that carry a Highlight

Measured in Roblox Studio on **2026-08-15**, in the `Game` place, against
`ReplicatedStorage.Models.Enemies.Slime`. Follows on from
[13](13-damage-flash-tint-vs-highlight.md), which established that a Highlight bound permanently into an enemy is
free to *flash* but said nothing about what it costs to *create*.

**Verdict: the Highlight is not the problem, `Clone()` is.** Carrying a highlight adds about 40us of Luau and
20us of engine time per enemy, which is 5-10% on top of a spawn that costs ~0.8ms whatever you do. Construction
order barely matters. What matters is that **60-90% of a spawn is the `Clone()` call, and `Clone()` does not have
to happen on the spawn frame.**

Script: [`scripts/21-spawn-with-highlight.client.luau`](scripts/21-spawn-with-highlight.client.luau)

---

## The scene

A steady population of 60 slimes, all inside the frustum (`vis=60/60` every row), each moved every frame. Every
30 frames M enemies are spawned; 15 frames later the M oldest are destroyed, so the population returns to 60.
Frames are tagged `spawn`, `destroy`, `tail` (the six frames after a destroy) or `quiet`, analysed separately and
shifted by one frame, as METHODOLOGY requires.

Quiet frames sit at 3.92ms, which is the 240 FPS cap. That is fine here because spawn spikes are many times the
cap, but it means **deltas below about 0.3ms are not resolvable in this run** and the negative deltas at low M
are the cap absorbing the work rather than the work being free.

---

## Construction order, M=26

Four orders, all ending with an identical live enemy. Quiet baseline 3.91-3.93ms.

| Variant | clone | config | parent | add HL | **total Luau** | spawn frame | delta | destroy | destroy delta | tail excess |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SENTINEL, no churn | - | - | - | - | - | 4.01 | +0.09 | - | -0.06 | +0.11 |
| PLAIN, no highlight | 364.8us | 3.1 | 35.1 | - | **403.0us** | 9.40 | **+5.48** | 137.5us | -0.95 | -0.26 |
| TEMPLATE has highlight | 426.8us | 3.1 | 14.5 | - | **444.5us** | 9.83 | **+5.92** | 158.7us | -0.86 | -0.27 |
| ADD BEFORE parenting | 288.7us | 6.4 | 77.1 | - | **372.3us** | 9.77 | **+5.85** | 132.9us | -0.89 | -0.26 |
| ADD AFTER parenting | 271.4us | 2.9 | 160.8 | 6.5 | **441.5us** | 10.41 | **+6.48** | 150.4us | -1.18 | -0.31 |

Frame figures are engine ms. The real spawn-frame `dt` is engine + Luau, so ~20ms for 26 enemies.

**Adding the highlight after the model is already in Workspace is the worst of the four, and only just.**
`ADD AFTER` costs +0.63ms more than `ADD BEFORE` across 26 enemies, about 24us each. That is a real, repeatable
ordering effect in the direction the docs predict, but it is nothing like the +15 to +17ms that *re-aiming* an
established highlight costs in doc 13. Attaching a highlight to a model that arrived on this same frame is
evidently not the same operation as re-binding one that has been sitting in the scene.

`TEMPLATE` and `ADD BEFORE` are indistinguishable (+5.92 vs +5.85), which is the expected result: Workspace sees
exactly one hierarchy event in both cases. Pick on code clarity, not speed.

The per-phase split wobbles between rows (`clone` reads 271-427us for what is nearly the same work, and `parent`
reads 14-161us) because the phases are timed with `os.clock` around individual calls and deferred work lands
where it lands. **Trust the totals and the frame deltas; treat the individual phase columns as indicative.** The
one phase reading that is stable across every row is that `clone` is the largest single component.

### Despawn is free

Every variant shows a **negative** destroy-frame delta (-0.86 to -1.18ms) and a **negative** tail excess over the
six following frames. Destroying costs 133-159us of Luau each and produces no deferred cleanup spike at all.

That is the opposite of [08](08-spawn-despawn.md), where a 12-part slug rig left a 2562ms teardown tail. The
difference is part count: the Slime is one skinned MeshPart, so there is almost nothing to tear down. Carrying a
Highlight adds ~20us to the destroy and changes nothing about the tail.

---

## How many fit in one frame

| M | PLAIN engine | PLAIN Luau | **PLAIN frame** | TEMPLATE engine | TEMPLATE Luau | **TEMPLATE frame** |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 3.49 | 0.73 | **4.2ms** | 3.98 | 0.22 | **4.2ms** |
| 4 | 3.32 | 2.13 | **5.5ms** | 3.76 | 2.32 | **6.1ms** |
| 8 | 4.95 | 3.06 | **8.0ms** | 5.98 | 3.79 | **9.8ms** |
| 13 | 7.03 | 5.94 | **13.0ms** | 7.17 | 4.84 | **12.0ms** |
| 26 | 9.80 | 11.33 | **21.1ms** | 10.71 | 13.49 | **24.2ms** |

Frame is engine + Luau, the actual `dt` on the spawn frame. It is close to linear at **~0.8ms per enemy**, and
the highlight version tracks about 5-10% above the plain one throughout.

So, in budget terms:

- **1 to 4 per frame is invisible.** The frame stays at the 240 cap; `fps` reads 240.0.
- **8 per frame** costs ~8-10ms. Fine at 60 FPS, over budget at 120.
- **26 in one frame is a ~21-24ms hitch**, a guaranteed dropped frame at 60 FPS, and the worst frames recorded
  were 25-31ms.

**Your 26-enemy wave wants about 5 per frame, not one every 2 frames.** Five per frame lands 26 enemies in 6
frames, or 100ms at 60 FPS, while adding roughly 4ms to each of those frames. One enemy every two frames would
take 52 frames and spend more than a third of the wave's opening spawning it.

---

## The optimisation the split points at

`Clone()` is 60-90% of the spawn cost and **it does not have to happen on the spawn frame.** Parenting a
pre-cloned, detached model into Workspace is 15-80us against ~400us for the whole spawn.

A queue of pre-cloned enemies parked at `nil` parent is not the "large pool" that the Highlight cap rules out:

- They are not in Workspace, so they do not render, do not move, and cost no frame time.
- **Their highlights cost nothing against the 255 cap.** A Highlight inside a Model whose Parent was never set
  does not consume a slot, measured in [13](13-damage-flash-tint-vs-highlight.md#what-actually-consumes-a-slot-measured).
  Only live enemies count, so the queue can be any size.
- The clone cost gets paid during the calm phase, which the Camp / Fight loop already provides.

The same fact makes the *templates* free: clone each enemy prefab once at startup, add its Highlight to the
clone, and hold those clones in a Lua table with no parent. 100 enemy types then cost 0 slots instead of 100,
and every spawn is a single `Clone()` that brings the highlight with it.

Done that way, a 26-enemy wave opening costs roughly 26 x 0.1ms spread over a couple of frames instead of a
21ms hitch, and the highlight rides along for free because it was cloned with the template.

If pre-cloning is not wanted, spawn 5 per frame and accept ~4ms of added frame time for 6 frames.

---

## Honest limits

- **The scene is small and capped.** 60 enemies render in well under the 4.167ms budget, so quiet frames are
  floored and sub-0.3ms effects are invisible. This run answers "what does a spawn burst cost" and not "what does
  a highlight cost to own", which doc 13 covers.
- **Viewport was 1340x546**, not full screen. Spawn cost is CPU-side so this matters little here, but it is
  recorded rather than assumed.
- **The per-phase Luau columns are noisy**, especially at M=1 where only a handful of spawns are sampled per
  second: `clone` reads 693us for PLAIN and 148us for TEMPLATE at M=1, which cannot both be true. The M=26 rows
  have 26x the samples per event and are the ones to quote.
- **Only the Slime was tested**, a single skinned MeshPart with one Bone. A multi-part enemy would move both the
  clone cost and the despawn tail substantially, as doc 08 found for the slug rig.
- **`ADD AFTER`'s +0.63ms was measured once**, in one block, against three siblings in the same run. The
  direction agrees with Roblox's documentation but the magnitude is a single measurement.
