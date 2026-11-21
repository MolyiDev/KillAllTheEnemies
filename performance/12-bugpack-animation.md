# Animating packed bugs: engine Animator vs writing bones in code

**Answer: a dead heat on frame time (~2.1ms per 4800 bugs either way), but they pay in opposite places.** Code
puts the cost on your Luau thread; the Animator puts it in the engine.

Script: [`scripts/15-bug-anim.client.luau`](scripts/15-bug-anim.client.luau).
Asset: `BugPack10` - one MeshPart, 10 bugs, each a root bone plus 4 limb bones (50 bones, the
[packing sweet spot](11-packing-sweet-spot.md)).

## The three variants

| | limbs driven by | instances per mesh |
| --- | --- | --- |
| **A** root only | nothing - the baseline | 51 |
| **B** code LUT | 4 bone Transforms per bug from a shared 128-step table, **each bug at its own phase** | 51 |
| **C** Animator | one AnimationController+Animator per mesh playing a generated KeyframeSequence | 53 |

Movement is identical in all three: `root.Transform = <world CFrame>`, one write per bug per frame.

**Instance parity was enforced**: A and B `:Destroy()` the imported AnimationController, so they carry 51
instances per mesh against C's 53. Leaving a dead controller on the code rows would have handed them a free
extra instance each.

**The animation is generated at runtime** - a `KeyframeSequence` built in Luau and registered via
`KeyframeSequenceProvider:RegisterKeyframeSequence`, which returns an id usable as `Animation.AnimationId`.
Nothing needed uploading. It registered successfully and `tracks=480` confirmed every Animator loaded and played.

## Results, n=4800 bugs (480 meshes)

| variant | median | p95 | script | engine | per bug |
| --- | --- | --- | --- | --- | --- |
| **A** root only | 5.56ms | 7.27 | 1.53ms | 4.03ms | 1.158us |
| **B** code LUT | **7.67ms** | 9.28 | **3.62ms** | 4.05ms | 1.597us |
| **C** Animator | **7.74ms** | 9.17 | 1.69ms | **6.05ms** | 1.613us |

Animation costs **~2.1ms** at 4800 bugs, or **~0.44us per bug**, whichever way you drive it. The split is what
differs:

- **B**: script 1.53 -> 3.62ms (+2.09ms), engine unchanged (4.03 -> 4.05).
- **C**: script 1.53 -> 1.69ms (+0.16ms), engine 4.03 -> 6.05ms (+2.02ms).

1200 and 2400 were cap-limited for all three variants and carry no information.

## Which to choose

They cost the same today but fail differently at scale. [10](10-bonegrid-many-per-mesh.md) found the Luau loop
becomes over half the frame past ~20k entities - and **the Animator moves that work off your thread at equal
total cost**, so it has the better asymptote.

The cost is phase granularity. An `AnimationTrack` has one `TimePosition`, so all 10 bugs sharing a mesh step in
unison. You do get **per-mesh** phase: set each mesh's `track.TimePosition` differently and 480 meshes give 480
distinct phases in clusters of 10. At swarm distance that may read fine; ten bugs in visible lockstep next to
each other is the risk.

- **C (Animator)** if clustered phase is acceptable and you want the Luau headroom.
- **B (code)** if bugs must be individually phased. This is also what `BugGait` already does, just writing Bones
  instead of Motor6Ds.

## Against the current rigs

`Slug + real BugGait` (5 Motor6Ds, from [05](05-animation.md)) measured **22.26ms at 2400 bugs**. `BugPack`
code-LUT at 2400 measured **4.26ms** - and that row was cap-limited, so the true figure is lower. At 4800,
BugPack runs 7.67ms where 4800 slugs extrapolate to roughly 45ms.

Call it **5-6x**, and treat it as indicative rather than exact: a BugPack bug is 5 cubes inside a shared mesh, a
Slug is 6 authored parts wearing SpecialMeshes. Geometry and mesh complexity differ alongside the mechanism.

## Still unresolved

None of this touches the blocker. The vacuum stretch is +0.05ms today and effectively impossible on a skinned
mesh ([07](07-scale-size-and-the-vacuum-stretch.md)); per-entity colour is unavailable on a shared MeshPart
([10](10-bonegrid-many-per-mesh.md)); and engine spatial queries stay broken. The animation result removes one
objection to skinned bugs, not the decisive ones.
