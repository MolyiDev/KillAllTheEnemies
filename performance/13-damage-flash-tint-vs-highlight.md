# The damage flash: SurfaceAppearance tint vs Highlight

Measured in Roblox Studio on **2026-08-14**, in the `Game` place, against the real
`ReplicatedStorage.Models.Enemies.Slime` (a skinned `MeshPart` with one `Bone` and a `SurfaceAppearance` tinted
`0.055, 0.624, 0.812`).

**Verdict: tint the `SurfaceAppearance`, and author enemy textures so the tint has room to brighten.** Writing
the tint costs +0.24 to +0.60ms on the flash frame and is the *only* cheap way to change how a skinned MeshPart
looks. Everything else tested - detaching the SurfaceAppearance, swapping the Material, re-parenting a Highlight,
re-aiming a Highlight - costs 15 to 22ms on the frame it happens.

Not because highlights draw slowly: 240 of them render for about 0.05ms, and one that lives permanently inside
its enemy toggles for free. The problem is that a `Highlight` is only free while it keeps pointing at the same
mesh. Re-aiming one costs **+16.33ms even when there is exactly one highlight and one enemy**, so the cost is a
fixed rebuild rather than per-highlight work, and pooling cannot amortise it. And the engine allows **255
Highlight instances in the whole DataModel**, disabled ones included, so the scheme that *is* free caps the game
at 255 enemies - a ceiling this game's own wave curve crosses.

Scripts: [`scripts/14-flash-calibrate.client.luau`](scripts/14-flash-calibrate.client.luau),
[`scripts/15-flash-bench.client.luau`](scripts/15-flash-bench.client.luau),
[`scripts/16-flash-visual-and-cap.client.luau`](scripts/16-flash-visual-and-cap.client.luau),
[`scripts/17-flash-mechanism.client.luau`](scripts/17-flash-mechanism.client.luau),
[`scripts/18-flash-textured.client.luau`](scripts/18-flash-textured.client.luau),
[`scripts/19-flash-colormap.client.luau`](scripts/19-flash-colormap.client.luau)

---

## Summary

| Method | Luau per write | Flash frame | Instances needed | Enemy ceiling |
| --- | --- | --- | --- | --- |
| `SurfaceAppearance.Color` = white | **143ns** | **+0.24 to +0.60ms** | 0 | none |
| Highlight already in the Model, toggle `.Enabled` | 248ns | **-0.06 to +0.23ms** | 1 per enemy | **255** |
| Highlight already in the MeshPart, toggle `.Enabled` | 248ns | **+0.03ms** (24) / -0.03ms (240) | 1 per enemy | **255** |
| Highlight already in place, tween `FillTransparency` | 248ns | **-0.01 to +0.11ms** | 1 per enemy | **255** |
| Pooled highlight, `Adornee` swapped to a new enemy | 603ns | **+15.38ms** (24), **+16.33ms at K=1** | 1 per simultaneous flash | 255 |
| Pooled highlight, re-`Parent`ed into the Model | 1546ns | **+16.95ms** | 1 per simultaneous flash | 255 |
| Pooled highlight, re-`Parent`ed into the MeshPart | 1424ns | **+16.98ms** | 1 per simultaneous flash | 255 |
| `SurfaceAppearance.Parent` = nil / back | n/a | **+21.41ms on, +21.75ms off** | 0 | none |
| `MeshPart.Material` = Neon / back | n/a | **+19.75ms on, +19.21ms off** | 0 | none |
| `SurfaceAppearance.ColorMap` blanked | n/a | **not measurable** - the property cannot even be read from a LocalScript | 0 | none |

Only two things are cheap: writing the tint, and toggling a highlight that already lives inside the mesh it
adorns. Everything else that changes how a skinned MeshPart is shaded costs 15-22ms on the frame it happens,
whether it moves an instance, swaps a material, or re-aims a highlight.

The two pooled-reparent rows are the ones this benchmark was commissioned to check, and they are among the worst
options on every axis.

The tint and bound-highlight rows were each measured in three independent runs (15, 18, 19) and reproduced every
time, which is why they are quoted as ranges.

---

## The decision

| What is flashing | Use | Why |
| --- | --- | --- |
| Swarm enemies, any count | **`SurfaceAppearance.Color`** | 143ns, +0.24 to +0.60ms, no cap, works per part |
| Bosses and elites, a handful at a time | **A Highlight bound into the model forever**, toggled with `.Enabled` or `FillTransparency` | free per flash, true white over any texture, and their count is bounded by design |
| Anything, as extra punch | A hit spark at the impact point | uncapped, never touches the enemy's shading |

**A budget only rescues the Highlight approach if it is a budget on how many enemies own a highlight
permanently - never a budget on how many flash at once.** Those sound similar and are not:

- *"At most 250 enemies exist, each owns a Highlight from spawn to despawn."* Works. Nothing ever rebinds, every
  flash is free. Costs you the 251st enemy, which silently stops flashing.
- *"At most 32 enemies flash at once, served from a pool of 32 highlights."* Does not work. The pool hands its
  highlight to whoever was just hit, which is a rebind, which is **+16.33ms even at a pool of one**. Capping the
  pool smaller does not help, because the cost never scaled with pool size in the first place.

For this game the first option is not available either: `WaveCore` starts at `BASE_COUNT = 22`, adds
`COUNT_PER_WAVE = 4`, and multiplies by up to 2.5 for a four-player party, so late waves put more than 255
enemies in the world and the overflow would stop flashing mid-run. That is what settles it in favour of the tint
for the swarm, and leaves Highlight for the things there are only ever a few of.

## The scene

2400 slimes on a deterministic grid (260 x 140 x 40 studs), camera at `(0, 0, 155)` looking at the origin,
FOV 70, **`vis=2400/2400` on every single sample** - every slime inside the frustum, verified per row with
`Camera:WorldToViewportPoint`. Each slime is moved every frame by writing `MeshPart.CFrame`.

240 of the 2400 are flash targets, every 10th slot so they are spread across the whole grid. 240 is not
arbitrary: it is the largest round number under the engine's 255-Highlight cap, so the one-highlight-per-enemy
variants are legal.

Every 30 frames, K targets flash together; 6 frames later they unflash. Frames are tagged `ON`, `OFF` or `QUIET`,
analysed separately, and **shifted by one frame** because `PreRender`'s `dt` bills frame N's work to N+1
(METHODOLOGY). `engine = frameTimes[N + 1] - updateTimes[N]` strips the Luau cost out, so the delta columns below
are engine-side work only.

### Getting out from under the 240 FPS cap

The calibration sweep ([`14-flash-calibrate`](scripts/14-flash-calibrate.client.luau)) exists because a flash
costing 0.3ms is invisible in a scene pinned at 4.167ms (METHODOLOGY trap 2):

| n | median | script | atCap | visible |
| --- | --- | --- | --- | --- |
| 240 | 4.19ms | 615us | 58.4% | 240/240 |
| 600 | 4.28ms | 1467us | 53.4% | 600/600 |
| 1200 | 4.37ms | 2863us | 47.4% | 1200/1200 |
| **2400** | **8.99ms** | 6580us | **0.0%** | 2400/2400 |
| 3600 | 13.35ms | 10278us | 0.0% | 3600/3600 |

2400 is the first count that is never capped. Note *why* it clears: the `MeshPart.CFrame` writes cost ~2.7us
each, so movement alone is 6.6ms of Luau. **This scene is script-bound, not render-bound** - the engine residual
is only 2.4ms at 2400 and 3.1ms at 3600, about 0.85us of render per slime. That is a useful fact in its own
right, and it means the movement doubles as honest ballast: static ballast could not clear the cap (trap 3), but
work the scene genuinely does can.

---

## Raw write cost

100 entities, 2000 iterations each, measured outside `PreRender` so this is the instruction cost only - any
deferred render work is *not* in these numbers, which is the whole reason the frame analysis exists.

| Operation | ns/op |
| --- | --- |
| `SurfaceAppearance.Color` = **new** value | **142.6** |
| `SurfaceAppearance.Color` = **same** value | 127.0 |
| `Highlight.Enabled` true <-> false | 247.5 |
| `Highlight.Adornee` = model <-> nil | 602.8 |
| `Highlight.Parent` = mesh <-> pool | 1423.6 |
| `Highlight.Parent` = model <-> pool | 1546.3 |
| `Instance.new("Highlight")` + config + `Destroy` | 6770.1 |

Reparenting is ~6x an `Enabled` toggle and ~11x a tint write before the engine does any work at all. Creating a
highlight per flash instead of pooling one costs 6.8us, so **if you use highlights at all, pooling is worth it
on the Luau side** - it is the engine side that ruins it.

Unlike `Part.Transparency` in [06](06-color-transparency-fastcluster.md), the engine's early-out on unchanged
values is weak here: writing the same colour back is only 11% cheaper than a real change, not 8x.

---

## Block A - K=24 flashing at once

The realistic case: a couple of dozen enemies taking damage on the same frame. Quiet frames sit at 2.4-2.6ms
engine, 8.9-9.4ms wall.

| Variant | quiet | ON | **delta ON** | OFF | delta OFF | med | p95 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SENTINEL move only | 2.44 | 2.44 | **-0.00** | 2.51 | +0.07 | 8.88 | 10.43 |
| TINT `SurfaceAppearance` | 2.40 | 2.66 | **+0.26** | 2.64 | +0.23 | 8.93 | 10.29 |
| POOL -> Model | 2.61 | 19.55 | **+16.95** | 3.54 | +0.93 | 9.38 | **26.26** |
| POOL -> MeshPart | 2.50 | 19.48 | **+16.98** | 3.55 | +1.04 | 9.30 | **26.46** |
| POOL `Adornee` swap | 2.61 | 17.98 | **+15.38** | 2.77 | +0.17 | 9.32 | **25.24** |
| PRE in Model `.Enabled` | 2.60 | 2.66 | **+0.06** | 2.59 | -0.01 | 9.11 | 10.46 |
| PRE in MeshPart `.Enabled` | 2.61 | 2.64 | **+0.03** | 2.54 | -0.07 | 9.18 | 10.44 |
| SENTINEL move only | 2.42 | 2.48 | **+0.06** | 2.33 | -0.09 | 8.92 | 10.12 |

All times in ms. The sentinel ran first and last and moved by 0.02ms, so nothing here is session drift.

Three things fall out:

**The sentinel proves the tagging is free.** Its ON delta is -0.00ms, so the ON/OFF split is not itself creating
the spikes.

**Model vs MeshPart does not matter.** +16.95 vs +16.98 for the reparent, +0.06 vs +0.03 for the toggle. Whichever
reads better in code wins; it is not a performance decision.

**`Adornee` costs the same as reparenting** (+15.38 vs +16.95), so **the reparent is not the expensive part**.
Both variants change *which mesh the highlight points at*, and that is what costs. `p95` tells the same story:
25-26ms for every pooled variant against 10.3-10.5ms for everything else.

---

## Block B - K=240, and a confound worth knowing about

| Variant | quiet | ON | delta ON | OFF | delta OFF | med | p95 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TINT `SurfaceAppearance` | 2.54 | 3.12 | +0.58 | 3.07 | +0.53 | 9.27 | 10.68 |
| POOL -> Model | 2.65 | 14.13 | **+11.48** | 14.39 | **+11.74** | 9.24 | 21.16 |
| POOL -> MeshPart | 2.67 | 14.23 | **+11.56** | 14.13 | **+11.46** | 9.29 | 21.11 |
| POOL `Adornee` swap | 2.63 | 3.18 | **+0.56** | 2.91 | +0.28 | 9.21 | 10.75 |
| PRE in Model `.Enabled` | 2.68 | 2.67 | -0.01 | 2.68 | +0.00 | 9.26 | 10.60 |
| PRE in MeshPart `.Enabled` | 2.71 | 2.69 | -0.03 | 2.67 | -0.04 | 9.37 | 10.71 |
| SENTINEL move only | 2.40 | 2.44 | +0.04 | 2.39 | -0.00 | 8.83 | 10.33 |

**The `Adornee` row flipped from +15.38ms to +0.56ms, and that is an artefact of the harness, not a discovery.**
With K equal to the target count, the rotation that picks each burst's victims wraps exactly, so highlight *j*
landed back on target *j* every single time - an accidental fixed pairing. That is the tell that the cost is
**per (highlight, adornee) pair**: keep the pairing and it is free, change it and it is 15ms.

The reparent rows stayed expensive even with that fixed pairing (+11.5ms on **both** ON and OFF), so re-parenting
re-binds the highlight regardless of whether it lands on the same enemy it left.

Per-highlight, the cost does not scale: +16.95ms for 24 rebinds is 0.71ms each, +11.5ms for 240 is 0.05ms each.
It behaves like a **fixed-cost rebuild triggered by any rebind that frame**, not like per-highlight work. If that
holds at K=1 then a single enemy taking a single hit costs a 15ms hitch, which would end the discussion. That is
what [`17-flash-mechanism`](scripts/17-flash-mechanism.client.luau) is for.

---

## Block C - having and drawing highlights is nearly free

K=0: the highlights exist and are left alone, so this is the standing cost of the instances themselves.

| Variant | quiet engine | med frame |
| --- | --- | --- |
| SENTINEL move only | 2.40 - 2.46 | 8.83 - 9.07 |
| 240 highlights in Models, all **disabled** | 2.62 | 9.23 |
| 240 highlights in Models, all **enabled and drawing** | 2.67 | 9.15 |
| 240 highlights in MeshParts, all **enabled and drawing** | 2.74 | 9.40 |
| 240 highlights idle in a workspace Folder | 2.43 | 9.04 |

240 highlights **actually rendering white over 240 skinned meshes cost ~0.05ms more than the same 240 sitting
disabled**, and ~0.25ms over not having them at all. A highlight is cheap to own and cheap to draw. Every cost in
this document is a *rebinding* cost.

---

## One rebind costs as much as two hundred

[`19-flash-colormap`](scripts/19-flash-colormap.client.luau) ran the pooled `Adornee` swap with a pool of
**one**: a single highlight, re-aimed at one different enemy per burst.

| Variant | quiet | ON | delta ON | OFF | delta OFF | p95 | worst |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SENTINEL move only, K=1 | 2.89 | 2.78 | -0.11 | 2.86 | -0.03 | 11.50 | 13.34 |
| POOL rotating `Adornee`, **K=1** | 2.92 | 19.25 | **+16.33** | 2.96 | +0.03 | 11.87 | **39.79** |

One highlight, one enemy, +16.33ms - the same as 24 of them (+15.38ms) and more than 240 of them (+11.48ms).
**The cost does not scale with how many highlights rebind, so it is a fixed rebuild triggered by any rebind in
the frame.** A single enemy taking a single hit drops a frame at 60 FPS. That closes the question: a highlight
that gets re-aimed is unusable for a per-hit effect at any scale, including one.

Unbinding is free (+0.03ms), so it is specifically **binding to a target the highlight was not already bound to**
that pays. Consistent with the block A finding that `Adornee` and `Parent` cost the same, and with the block B
accident where a wrapped rotation kept every pairing fixed and the cost vanished.

## Nothing else that changes the shading is cheap either

[`18-flash-textured`](scripts/18-flash-textured.client.luau) chased the two remaining uncapped, texture-agnostic
ideas. Both are dead. K=24, quiet 2.9-3.1ms:

| Variant | quiet | ON | delta ON | OFF | delta OFF | p95 | worst |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SENTINEL move only | 2.88 | 2.90 | +0.02 | 2.79 | -0.10 | 11.27 | 13.34 |
| TINT white | 3.01 | 3.25 | +0.24 | 3.21 | +0.20 | 11.64 | 17.14 |
| **`SurfaceAppearance.Parent` = nil / back** | 3.08 | 24.49 | **+21.41** | 24.82 | **+21.75** | 33.42 | 47.07 |
| **`MeshPart.Material` = Neon / back** | 3.08 | 22.83 | **+19.75** | 22.29 | **+19.21** | 32.20 | 42.12 |
| HIGHLIGHT bound, `.Enabled` | 3.11 | 3.25 | +0.14 | 3.03 | -0.08 | 11.52 | 13.32 |

The detach result was expected to be bad - it is a hierarchy change, the same category that costs 17ms for a
Highlight. **The material swap is the informative one.** It is a plain property write, on a property the attached
`SurfaceAppearance` overrides anyway so it changes nothing on screen, and it still cost 19.75ms. So the trigger
is not "hierarchy change" and not "visible difference" - it is **anything that invalidates how a skinned MeshPart
is shaded**. `SurfaceAppearance.Color` is the one write in this family that the engine handles without
invalidating anything.

Both K=240 rows for these two variants are excluded: one carries a `*** FOCUS LOST ***` marker and both show
quiet baselines of 13.64 and 16.43ms against 3.0ms everywhere else, so that pair of samples was taken while the
session was degraded. The direction is not in doubt, the magnitudes there are.

### The mechanisms that do not exist

Worth writing down so they are not re-investigated:

- **`SurfaceAppearance` cannot show the part's material or colour underneath.** That is an open engine feature
  request, [Allow SurfaceAppearance to show the part's Material underneath](https://devforum.roblox.com/t/allow-surfaceappearance-to-show-the-parts-material-underneath/2973767),
  which is why the Neon swap changes nothing on screen while still costing 19.75ms.
- **`AlphaMode = Overlay` only reveals `MeshPart.Color` where the ColorMap is transparent.** Per
  [PBR textures](https://create.roblox.com/docs/art/modeling/surface-appearance): "Overlay overlays the ColorMap
  over the underlying mesh's `MeshPart.Color`. Color maps using overlay mode reveal the base color of the mesh
  anywhere transparency is present." An opaque texture never shows the part colour, so `MeshPart.Color` - which
  *is* cheap - cannot drive a flash on a normally-authored enemy.
- **The map properties cannot be written at runtime.** `ColorMapContent`, `NormalMapContent`,
  `RoughnessMapContent`, `MetalnessMapContent` and `EmissiveMaskContent` are all read-only to scripts.
- **`AssetService:CreateSurfaceAppearanceAsync`** (January 2026, [announcement](https://devforum.roblox.com/t/in-experience-build-a-texture-editableimage-support-for-surfaceappearance/3866947))
  does let you build a whole `SurfaceAppearance` at runtime from EditableImages. It does not help here: you would
  still have to swap the finished object onto the mesh, and that is the +21.41ms hierarchy change.

### Blanking the ColorMap is not available

The idea behind it was sound: leave every instance where it is and swap only the texture binding. It cannot be
tested, because **`SurfaceAppearance.ColorMap` cannot even be read from a LocalScript**, let alone written -
`[PROBE] ColorMap readable=false`. It is plugin-security gated, like `CollisionFidelity` (METHODOLOGY trap 10).
Doc [06](06-color-transparency-fastcluster.md)'s note that the map properties are not script-assignable at
runtime still holds, and it holds more strongly than written there: they are not script-*readable* either.

## FillTransparency is free too, and there is no culling threshold

Every devforum answer to "how do I flash white" is the same shape: park a Highlight inside the part and tween
`FillTransparency`. Everything above measured the `.Enabled` toggle instead, so
[`20-flash-filltransparency`](scripts/20-flash-filltransparency.client.luau) measured the one people actually
use - split `CROSS` (1 to 0, invisible to opaque) from `WITHIN` (0.5 to 0, never invisible) the same way
[06](06-color-transparency-fastcluster.md) split `Part.Transparency`, because the docs say a fully transparent
highlight is culled and crossing back could have paid a wake-up.

| Variant | K=24 delta ON | K=240 delta ON |
| --- | --- | --- |
| SENTINEL move only | +0.09 | -0.01 |
| TINT white | +0.33 | +0.59 |
| Model `.Enabled` | +0.03 | -0.04 |
| **Model Fill CROSS 1 <-> 0** | **-0.00** | **+0.11** |
| **Model Fill WITHIN 0.5 <-> 0** | **+0.02** | **-0.11** |
| **Mesh Fill CROSS 1 <-> 0** | **-0.01** | **+0.06** |

`FillTransparency` is free, and unlike `Part.Transparency` there is **no boundary cost** - crossing fully
invisible reads the same as moving within the visible range. So tweening it, which writes the property every
frame of the tween at 248ns a write, is fine. Use whichever of `.Enabled` and `FillTransparency` the code wants;
neither is a performance decision. The cap and the rebind cost are still the whole story.

The `WITHIN` row at K=24 carries a `*** FOCUS LOST ***` marker and the viewport changed size mid-run, so treat
that one row as soft; its delta agrees with the other five.

## What Roblox's own documentation says

[Highlighting objects](https://create.roblox.com/docs/effects/highlighting) independently confirms most of this,
which is worth knowing before anyone re-litigates it:

> Adding or removing a `Highlight` can cause a geometry rebuilding step that might lead to performance spikes and
> extra draw calls.

> Highlights that are not visible on the screen (whether disabled or fully transparent) incur no performance
> cost.

That is block A (+16.95ms for a re-parent) and block C (240 disabled highlights ~ free), stated by the vendor.

**One line of it does not survive measurement:**

> Changing any property of the `Highlight` instance is lightweight and doesn't impact performance.

`Adornee` is a property, and changing it to a mesh the highlight was not already bound to costs **+15.38ms at
K=24 and +16.33ms at K=1**. Only the *unbind* (`Adornee = nil`) is lightweight, at +0.03ms. The documentation
frames the rebuild as a consequence of adding or removing the instance; in practice re-aiming an existing one
triggers the same rebuild. **This is a reportable repro case**, the same shape as the `Part.Transparency` one in
[06](06-color-transparency-fastcluster.md): 2400 skinned meshes, one pooled Highlight, re-point `Adornee` at a
different mesh once every 30 frames, watch the flash frame.

Two things the docs add that this benchmark did not measure, both mobile:

> The first `Highlight` rendered on the screen incurs most of the performance cost (up to 1 millisecond of GPU
> time on mobile devices). [...] On mobile devices, highlights are more costly on performance when they cover
> more of the screen.

Everything here was measured on desktop, where 240 rendering highlights cost about 0.05ms. On mobile the *first*
one can cost up to 1ms of GPU, and the cost scales with screen coverage - so a flash that fills the screen with
white on 20 nearby enemies is a different proposition on a phone than these numbers suggest.

And one structural rule if highlights are ever used on enemies:

> It's best to keep objects with `Highlight` instances outside of a parent/child relationship with other objects
> with `Highlight` instances.

## The 255 cap decides this on its own

Independent of any timing, from Roblox's own documentation and announcements:

- The cap was **raised from 31 to 255 on 10 November 2025**
  ([Lights, Camera, More Highlights!](https://devforum.roblox.com/t/lights-camera-more-highlights/4061534)).
- "Studio only displays 255 simultaneous `Highlight` instances on the client-side at a time."
  ([Highlighting objects](https://create.roblox.com/docs/effects/highlighting))
- **A disabled highlight still takes a slot:** "While a disabled `Highlight` doesn't display, it still takes one
  of the 255 available `Highlight` slots. If you plan to permanently disable a `Highlight` instance, it's best to
  delete the highlight rather than disable it." (same page)
- **So does one parked outside Workspace.** A 2025 bug report,
  [Highlights not under Workspace still count towards the highlight limit](https://devforum.roblox.com/t/highlights-not-under-workspace-still-count-towards-the-highlight-limit/3611524),
  states that highlights in e.g. `ReplicatedStorage` still consume slots even while disabled. No staff reply; the
  thread auto-closed on 27 August 2025 unresolved. **Confirmed here** - see below.

### What actually consumes a slot: measured

The rule is **membership of the DataModel**, not membership of Workspace. Verified by eye with
[`22-highlight-cap-parentless`](scripts/22-highlight-cap-parentless.client.luau) and
[`23-highlight-cap-detached-models`](scripts/23-highlight-cap-detached-models.client.luau): 300 extra highlights
are created first, then one slime in front of the camera gets a full-white highlight **last**, so it is last in
line for a slot. If the slime renders white, its highlight got one.

| 300 extra highlights held as | Slime still white? | Takes a slot? |
| --- | --- | --- |
| nothing (control) | yes | n/a |
| `Highlight.Parent` **never set**, held only by a Lua table | **yes** | **no** |
| `Highlight` inside a **Model whose Parent is never set** | **yes** | **no** |
| `Highlight` inside a Model parented to `ReplicatedStorage` | **no** | **yes** |
| control again, extras destroyed | yes | reverses cleanly |

So anything reachable from `game` costs a slot even when it is disabled, invisible and unrendered, while
anything held alive purely by a Lua reference costs nothing.

**That makes detached templates the way to store per-enemy-type highlights.** Keeping 100 enemy prefabs in
`ReplicatedStorage` with a Highlight authored into each would spend 100 of the 255 before a single enemy exists.
Cloning each prefab once at startup, adding the Highlight to the clone, and holding those clones in a Lua table
with no parent costs zero. Only live enemies count.

The obvious caveat: this is undocumented behaviour, not a guarantee. It is also trivially reversible if it ever
changes, since the fallback is to create the highlight at spawn instead, which
[14](14-enemy-spawn-with-highlight.md) measures at the same frame cost.
- The docs also recommend "customizing highlight properties directly rather than adding/removing instances" to
  avoid rebuilding geometry - which is the documentation-side statement of what block A measured.

So your instinct was right: **a pre-parented highlight consumes its slot whether it is enabled or not, and
parking a pool in `ReplicatedStorage` does not dodge the cap either.** The budget is 255 highlights in the whole
game, shared with anything else that wants one - interaction outlines, nametag glows, the tool being held.

This project sizes enemy reasoning to thousands of enemies on screen, so a highlight per enemy is not a tuning
question, it is impossible.

---

## What this means for the flash

Use `SurfaceAppearance.Color`. It costs 143ns per write and +0.26ms of engine time for a 24-enemy burst, it needs
no instances, it has no cap, and it works per-part if a limb ever needs to flash on its own.

### The tint is a multiply, so the texture has to leave it somewhere to go

`SurfaceAppearance.Color` multiplies the ColorMap. **The result can never be brighter than the raw texture.** A
tint can darken or shift hue; it can only "flash white" if the texture is already bright and the tint is what is
holding it down.

The slime is authored exactly that way - a light ColorMap with the blue living in the tint - which is the only
reason white reads as a flash on it. An enemy authored the other way round, with its colour baked into the pixels
and the tint left at white, cannot flash brighter at all.

**So this is an authoring rule, not a code one: keep the ColorMap bright and neutral and put the enemy's colour
in `SurfaceAppearance.Color`.** For a multicoloured enemy that will not reduce to one tint, the general form of
the same rule works: author the ColorMap brighter than the intended look and set the default tint below 1 to
reserve headroom. A default tint of 0.5 buys a 2x brightening on flash, which lands on a blown-out version of the
enemy rather than pure white, and still reads as a hit.

Where re-authoring a texture is not worth it, **tinting toward a saturated red or orange works on any texture no
matter how it was authored**, for the same 143ns. Multiplying toward a colour is always available; multiplying
toward brighter is not.

### The other answer: do not touch the enemy at all

The standard Roblox approach to hit feedback does not recolour the target. It spawns a separate effect at the
impact point - a burst mesh plus a `ParticleEmitter` - and leaves the enemy's own appearance alone (see
[Hit Effect Handler](https://devforum.roblox.com/t/hit-effect-handler-how-to-make-a-good-hit-effect-in-5-minutes-mesh-particles/1511337)).
That is uncapped, texture-agnostic, and never invalidates a skinned mesh's shading, because it never writes to
one. It reads as a hit landing rather than as the enemy reacting, so it is a different design choice, not a
cheaper version of the same one - but it is the option that no texture authoring can take away, and the two
combine well: a cheap tint shift on the body plus a spark at the contact point.

### Why not just give every enemy a Highlight

Because the 255 cap is a hard ceiling and this game's wave curve crosses it. `WaveCore` starts at
`BASE_COUNT = 22` and adds `COUNT_PER_WAVE = 4`, scaled by up to `2.5` for a four-player party, so late waves put
more than 255 enemies in the world. Past that point the extra highlights silently do not render and those enemies
stop flashing, with no error. A mechanism that stops working at a wave number is not a mechanism.

If a highlight is wanted for something there are one or two of - a boss outline, a marked target, the enemy under
the crosshair - the rule from these numbers is: **give it a permanent home inside the thing it adorns and toggle
`Enabled`**. Never re-aim one. And count disabled ones against the 255.

---

## Honest limits

- **The scene is script-bound.** 6.6ms of the 9ms frame is the movement loop. Engine time is isolated by
  subtracting the measured Luau cost per frame, which is the same method as
  [06](06-color-transparency-fastcluster.md), but if the render thread overlaps the Luau thread then a
  small *render*-side cost could hide under it. The rebind spikes are 5-7x the whole engine residual, so they are
  not hiding anywhere; a sub-0.2ms effect might be.
- **Change-frame sample counts are 11-19 per row.** Enough for the 15ms effects, thin for the 0.26ms ones.
- **The `mem` column is unusable.** It read -2MB, 0MB, 14MB, 25MB, 27MB, 34MB, 50MB and 75MB for scenes that
  differ by at most 240 Highlight instances. That is GC timing, not measurement.
- **Build time drifted across the run** (325ms to ~1000ms for the same 2400 slimes) as the session accumulated
  churn. Steady-state numbers did not drift - the sentinel held 2.40-2.46ms quiet from first row to last - so the
  measurements stand, but a fresh session per block would be better.
- **One row in the reverse pass has a bad `fps` column** (66.0 against a 9.38ms median, which should read ~107).
  Its engine deltas agree with the forward pass, so the row is kept, but the frame counter for that sample is not
  trustworthy.
- **Run 15's reverse pass was cut short.** Studio stopped rendering partway through it - two rows came back with
  `fps=0.0` and `settle=20.1s NO`, and the viewport check dropped to `vis=2012/2400`, which is what a minimized
  or occluded window looks like. Everything from run 15 reported above is from before that point and is backed by
  a sentinel. The lost rows were re-covered by runs 18 and 19 rather than by repeating the reverse pass, which is
  stronger evidence than a repeat would have been: the tint and bound-highlight numbers now come from three
  independent runs on three separate sessions.
- **The quiet baseline differs between sessions** - 2.4-2.7ms in run 15, 2.9-3.1ms in runs 18 and 19. Deltas are
  always taken against the sentinel measured in the same run, so this does not affect any comparison, but do not
  read absolute engine times across runs.
- **The viewport was not 1918x1080 and was not even constant.** Run 20 was the first to print it, and it read
  `vp=1002x238` for the first four rows and `vp=1340x546` for the rest - the Studio window was resized mid-run.
  Earlier runs did not record it, so their viewports are unknown, and the `vis=2012/2400` and `vis=23/2400`
  readings during the two stalled sessions were the frustum shrinking with the window rather than the scene
  moving. **Every rebuild cost in this document is CPU-side and 15-22ms, far too large to be a fill-rate
  artefact, and every delta is against a sentinel measured in the same window.** What this *does* undermine is
  the one fill-rate-sensitive claim: "240 rendering highlights cost ~0.05ms" was measured on a small viewport and
  would be larger full screen, in the direction the mobile guidance warns about. Treat it as a lower bound.
- **Print the viewport in future runs.** METHODOLOGY asserts 1918x1080; nothing was checking it.

## Closed

- **Does K=1 cost 15ms?** Yes, +16.33ms. Rebinding is a fixed cost, not per-highlight work.
- **Is the pre-parented case really free, or does it just pay its build during the settle window?** Genuinely
  free. Run 19 holds all flashing until the sample window opens, and the bound highlight's first ever enable
  (`ON#1 = 3.15ms` against a 3.11ms quiet baseline) costs nothing. The binding is paid when the Highlight is
  **parented**, during scene build; enabling it later is free forever after.
- **Is there an uncapped, texture-agnostic white flash?** No. Detaching the `SurfaceAppearance` costs +21.41ms,
  swapping `MeshPart.Material` costs +19.75ms, and `ColorMap` is not scriptable at all.

## Open

- **Camera-away control.** If the rebind cost survives with nothing on screen it is CPU bookkeeping rather than
  render work, which would make it worse, not better. It does not change any recommendation either way, which is
  why it has not been chased. [`17-flash-mechanism`](scripts/17-flash-mechanism.client.luau) has the rows.
- **`ON#1` and `ON#2` are cheap in the K=1 rebind row** (3.03 and 4.19ms) before the median settles at 19.25ms
  over the remaining 17 bursts. Whatever warms up in the first two bursts was not identified. It does not affect
  the conclusion, since the steady state is the state the game runs in.
- **A visual side-by-side exists but has not been captured.** Run 19 holds six slimes close up for 14 seconds
  (reference, tint white, two ColorMap slots that are inert, highlight `Occluded`, highlight `AlwaysOnTop`).
  `capture_screenshot` is edit-mode only so it cannot be grabbed from a playtest; it has to be watched live.
