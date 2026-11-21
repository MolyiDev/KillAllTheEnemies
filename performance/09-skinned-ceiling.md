# Where the skinned-mesh ceiling actually is

**Answer: ~4800.** Not 7200, and it fails in two stages rather than falling off a cliff.

Script: [`scripts/11-ceiling.client.luau`](scripts/11-ceiling.client.luau)

## Why this run exists

An earlier measurement put 7200 skeletons at **164.32ms median engine time** and concluded skinned meshes
"collapse between 4800 and 7200". That conclusion was contaminated: skeleton spawn cost is ~1.4ms per entity, so
7200 of them is roughly **ten seconds of build CPU**, and that run allowed a **2 second settle**. It was largely
measuring the tail of the build.

This run fixes it with a chunked build and an **adaptive settle** - sample the frame time in 1s windows and only
begin measuring once two consecutive windows agree within 10%, reporting how long that took.

## Results (bone movement only, no property writes)

| n | build | settle | fps | mean | median | p95 | worst | script |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2400 | 5425ms | 6.2s converged | 239.3 | 4.18 | **4.10** | 5.04 | 9.68 | 1021us |
| 4800 | 6122ms | 4.3s converged | 105.8 | 9.90 | **5.60** | 6.80 | 240.28 | 2052us |
| 6000 | 7807ms | 4.6s converged | 52.2 | 20.07 | **6.68** | **212.73** | 241.40 | 2663us |
| 7200 | 8061ms | 5.0s converged | 10.2 | 102.49 | **44.77** | 237.75 | 253.59 | 3405us |
| 8400 | 11213ms | 5.1s converged | 4.4 | 226.07 | **225.99** | 245.37 | 248.50 | 3965us |

Every count converged, so all of these are genuine steady states rather than build tails.

## The old number was inflated, but the ceiling was real

At 7200: **164.32ms median before, 44.77ms median after** a proper settle - a 3.7x improvement. So the original
figure was substantially a build artefact. But 44.77ms is still ~22 FPS, so 7200 genuinely does not work; the
ceiling existed, it was just placed too high.

## Two-stage failure

- **Up to 4800 - clean.** Median 5.60ms, p95 6.80ms. A tight distribution, genuinely usable.
- **6000 - the tail goes first.** Median is still healthy at 6.68ms but p95 jumps to **212.73ms**. Typical frames
  stay fast while stalls start recurring.
- **7200 - the median goes.** 44.77ms.
- **8400 - uniformly dead.** mean 226 = median 226 = p95 245. No longer spiky, just constantly slow.

**The stall looks like a fixed-cost operation recurring more often, not work that grows with entity count.**
Worst frames cluster at 240-253ms at 4800, 6000 *and* 7200 while their frequency climbs; script cost meanwhile
scales linearly and stays small (1.0 -> 4.0ms), so the Luau loop is not the cause. The mechanism was not
identified.

Note that 4800's worst frame was already 240.28ms - the stall mechanism exists there too, just rarely enough
that p95 stays at 6.80ms.

## The methodological consequence

**Every count needed 4.3-6.2 seconds to settle, including n=2400.** Earlier runs in this folder allowed 1.5-2s.
That means the settle window was too short in essentially every high-count skinned measurement here, not only
the 7200 one.

What that does and does not invalidate:

- **Medians and p95 in the other docs still hold** where they were taken at 1200-4800 with variants compared
  against their own controls in the same run - both sides of every comparison had the same too-short settle, so
  the *relative* results stand.
- **`worst`-frame columns everywhere should be treated as suspect**, since a short settle leaves build tail in
  the sample. This is why [04](04-specialmesh-vs-meshpart.md) shows 14ms worst frames in one pass and 900ms in
  another for the same variant.
- Anything re-run for absolute numbers should use the adaptive settle from this script.

## Practical read

For a swarm of skinned meshes, **budget ~4800 on this hardware** and treat 6000 as the point where stalls start
even though the average still looks fine. That is well above the ~600 bugs this game targets, so the ceiling is
not a live constraint - it is only relevant to the architecture comparison in the [README](README.md).
