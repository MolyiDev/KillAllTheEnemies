# How many elements per MeshPart? The packing sweet spot

**Answer: 25-50.** Not 100. This corrects [10](10-bonegrid-many-per-mesh.md), which benchmarked 100 per mesh and
called it the win - 100 turns out to sit on a ~35% worse plateau.

Script: [`scripts/14-packing.client.luau`](scripts/14-packing.client.luau).
Assets: `Pack010` / `Pack025` / `Pack050` / `Pack100` / `Pack200` / `Pack400`, see [assets/](assets/README.md).

## Method

Entity count held **fixed**, packing varied, so the only thing changing is how many MeshParts those entities are
spread across. Adaptive settle, reps interleaved across the whole curve rather than run back to back.

## n=19200 (2 reps, tight agreement)

| per mesh | meshes | median | p95 | script | µs/entity |
| --- | --- | --- | --- | --- | --- |
| 10 | 1920 | 18.58ms | 18.96 | 5939us | 0.968 |
| **25** | 768 | **9.40ms** | 10.98 | 5473us | **0.490** |
| **50** | 384 | **9.49ms** | 11.81 | 5588us | **0.494** |
| 100 | 192 | 13.05ms | 14.92 | 5577us | 0.680 |
| 200 | 96 | 12.72ms | 14.89 | 5481us | 0.662 |
| 400 | 48 | 12.93ms | 14.85 | 5436us | 0.673 |

## n=9600 (1 rep)

| per mesh | meshes | median | µs/entity |
| --- | --- | --- | --- |
| 10 | 960 | 9.71ms | 1.012 |
| **25** | 384 | **5.22ms** | **0.544** |
| **50** | 192 | **5.37ms** | **0.560** |
| 100 | 96 | 11.40ms | 1.187 |
| 200 | 48 | 7.60ms | 0.791 |
| 400 | 24 | 11.36ms | 1.184 |

## Reading it

- **25 and 50 tie**, at both counts, and beat everything >=100 by ~35%.
- **10 is too few** - 1920 meshes at 19200 entities puts you back to paying per-MeshPart (18.58ms).
- **The script column is flat** across every packing (5.4-5.9us at 19200). Packing changes only the engine side;
  your update loop does the same number of writes regardless.
- **It is a step, not a slope.** 100, 200 and 400 all land on the same ~12.7-13.1ms plateau. Something changes
  between 50 and 100 rather than degrading gradually.

**Hypothesis for the step: a GPU skinning bone limit.** 64 or 128 bone matrices in a uniform buffer is a common
hardware/driver constraint, and exceeding it drops the renderer onto a slower path. If that is what this is, the
true optimum is "as many as fits under the limit", i.e. ~64. **Untested** - measuring 64 and 80 would pin it.
Staying at 50 is safe either way and costs nothing measurable.

Trust the 19200 rows. The 9600 stage had one rep and its 100/200/400 values are non-monotonic (200 beats both
100 and 400), which is the run-to-run variance flagged in [10](10-bonegrid-many-per-mesh.md).

## Consequence for a real bug

Bones per mesh is the budget, not bugs per mesh. At 50 bones:

| bones per bug | bugs per mesh |
| --- | --- |
| 5 (root + 4 limbs) | 10 |
| 13 (a full roach) | ~4 |

A full-detail 13-bone rig erodes the packing win considerably - 4 bugs per mesh is much closer to the
one-mesh-per-entity case that this whole approach exists to escape.
