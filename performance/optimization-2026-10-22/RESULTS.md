# Ballarc performance results — 2026-10-22

The retained implementation is in `src/`, uncommitted, and synced to the actual Survivors Studio (place **137835287157016**). It has not been published. Benchmark scripts, temporary modules, remotes, and source instrumentation were removed. All 31 restored Studio scripts were read back and matched the production disk sources exactly. Survivors remained connected and idle after cleanup. BeACastleLord was not changed.

**Measured game performance**

Hardware verified this session: Ryzen 9 7900X, RTX 4060, driver 615.78.08; Linux/Vinegar Studio 0.744, viewport 1900×858. These are controlled single-client Studio scenes with weapons/progression held, actual Slime/Bee assets, and all counted enemies visible and animated. They are not mobile, multiplayer, or full-combat guarantees. The production cap remains 1,500; 3,000 is a stress test.

| Scene | Approx. sampled FPS before → after | Median frame, ms before → after | p95 frame, ms before → after |
| --- | --- | --- | --- |
| 1,500 ground | 187 → 223 | 5.24 → 4.38 | 6.47 → 5.80 |
| 3,000 ground | 101 → 115 | 9.51 → 8.07 | 12.79 → 13.00 |
| 1,500 mixed | 122 → 151 | 6.91 → 6.46 | 16.46 → 7.91 |
| 3,000 mixed | 37 → 91 | 11.95 → 10.13 | 74.21 → 17.63 |

Mixed means ground/flying/charmed/charmed-flying categories plus optional-component archetype fragmentation. It is more expensive than a ground-only wave of the same count. FPS is estimated from captured client frames divided by the corresponding server capture duration, so replication timing adds uncertainty. Before values are means of eligible per-run summaries from `before-1` and `before-2`; final values are from `after-final-native`. Quantiles were not pooled. Earlier repeated candidate runs corroborate the broad gains, but the exact final variant has one complete four-scene capture. Raw captures and `summary.json` expose the individual values.

Ground median frame time fell about **15–17%**. Mixed p95 fell about **52% at 1,500** and **76% at 3,000**. The mixed scene's average FPS improves much more than its median because the long recurring stalls are reduced. Do not invert median frame time and call that average FPS.

Not every metric improved: uniform 3,000-enemy client p95 was essentially unchanged (12.79 → 13.00 ms). Its server Heartbeat p95 was approximately 17.03 → 18.86 ms in the final capture, while its median fell approximately 9.01 → 8.00 ms. Other candidate runs put the server tail around 18–19 ms. This is a remaining scheduling-tail concern, not evidence for a universal regression-free claim. The larger mixed-scene tail improvements and ground average-FPS gains are much stronger than these small differences. Procedural terrain was not seeded across separate playtests, and these runs do not establish statistical significance for small changes.

**Changes retained**

- Cache ground target transforms/terrain orientation between position changes; retain flying pitch smoothing and per-frame interpolation. Track animation state in Lua and handle freeze/resume correctly. Ground client Update median fell about **33–35%**; mixed Update fell about **19–20%**.
- Pack one collision snapshot lazily when movement actually dispatches, shared across categories in the frame. At 3,000 ground enemies, summed packing elapsed time fell from approximately **726 → 71 ms per ten-second window**, about **90% less**. At 1,500, the reduction was about **94%**. These are summed timings around packing calls, not isolated thread CPU measurements.
- Coalesce archetype rows into persistent worker partitions, with at most 16 jobs per category and a minimum 64 rows/job. Reuse decoded record tables/bucket arrays, prune absent entries, and commit only returned entity IDs. This targets repeated full-snapshot decoding and excessive messages in fragmented scenes.
- Bound each category to one in-flight movement batch; reject old/duplicate replies and old map/pause generations. Validate full entity generation, movement revision, role, stun, and telegraph state. Main-thread-owned Force remains input-only to workers. Read the current jecs record/columns once during commit to avoid repeated lookups for these checks.
- Use exact local spatial lookup for charm targets, with a full-scan fallback when the local neighborhood contains no valid target. Stable equal-distance tie breaking, self exclusion, and returned positions were checked against full scans. Remove redundant target-position snapshots from charm worker messages.
- Native compilation for the two small custom packers, with unchanged packet bytes and decoded values. In alternating direct tests at 3,000 rows, median per-call time changed: entity pack **0.305 → 0.102 ms**, entity unpack **0.172 → 0.052 ms**, position filtering **0.283 → 0.045 ms**, position unpack **0.140 → 0.040 ms**. These are kernel gains, not 3–6× whole-game gains. Native code uses additional compiled-code memory; that memory delta was not measured and was disclosed before retention. One 50-row native pack round was an outlier; all raw rounds are retained.
- Camera reports at **20 Hz**, explicitly approved by the user. Reports are up to roughly 50 ms apart at sufficient frame rates; under slow frames they can be farther apart. This lowers the old frame-based report frequency on high-refresh clients.

**The reported 100 FPS → 30 FPS second-wave problem**

The original baseline itself shows approximately **101 FPS for 3,000 ground enemies** and **37 FPS for 3,000 mixed/fragmented enemies**. Those are different workloads despite equal enemy counts. That is consistent with the large drop observed while watching the benchmark; it does not establish the cause of every future slowdown.

Two explicit same-wave checks were stable:

- Clear/respawn identical ground waves: median frame **8.02 → 8.06 ms**.
- Real client `KilledMultiple` visuals, followed by removal and identical respawn: **7.88 → 7.91 ms**. These synthetic kills used killer ID 0 and did not grant player rewards.

Both waves had exactly **3,000 unique active models**, no duplicate pool entries, unchanged cached-track counts, and **zero playing tracks on idle models**. The tested kill cycle did not accumulate another invisible active wave.

Retained models still have a measurable cost. After warming the second enemy type, there were **4,692 Workspace models: 3,000 active and 1,692 idle**. With positions held still and all 3,000 active models animated, temporary detachment of the idle models changed median frame time from **8.25/8.31 → 7.59/7.51 ms**, about **9% lower**. Restoring the models restored the cost. This was a residency experiment, not a production change.

A separate code defect did retain references to destroyed retired-type models in `ModelToWalkTrack`. Destruction now removes those cache entries. Delayed death effects also now verify that their pool is still current, so a restart/type retirement cannot return effects into an orphaned old pool. A live restart during pending death effects left **zero orphaned Slime death attachments**. No FPS or memory-saving estimate is assigned to these correctness fixes.

**Experiments excluded from production**

- Idle model reparenting: despite the residency gain, warm 3,000-model AddEnemy work rose **55 → 139 ms**, attachment completion **0.39 → 0.90 seconds**, and removal work **35 → 133 ms**. Typical warm 50-enemy AddEnemy work rose about **0.66 → 1.91 ms**. The extra hierarchy work is a significant burst regression. The prototype is archived under `held/` and is not installed.
- Queued rig attachment and bounded particles: prior stress tests smoothed spikes but delayed complete 3,000-model attachment **1.15 → 2.42 seconds**. A warmed reserve of 32 death effects for one type can show only 32 effects in a single synchronous 1,500-kill batch; replenishment between frames makes gradual kills different. The user requested more detail rather than approving these tradeoffs. Original immediate attachment and full particle behavior are retained.
- Aggressive high-water pool destruction: rejected in the earlier pass because it caused sustained post-death frame regressions.
- Contact batching: removed from all four pipelines. It preserved the tested 40,000 callbacks but did not improve frame times.
- Movement residual/catch-up cadence change: removed. The original cadence is retained; the final comparison does not gain performance by changing the intended workload rate.
- Additional native flags on the four Work/Parallel pairs: trial archived as `after-final-actor-native.json`; no convincing additional average-FPS gain over the retained small-packer flags, so they are not in the final source.

**Correctness and error handling**

Fixed cross-cell hash coordinates, shape broad-phase extents, in-memory recursive-query deduplication/movement/removal, reusable decode state cleanup, stale movement results, animation restart after freeze, retired-model cache references, delayed-effect pool ownership, and truncated enemy packet handling. Known empty inventory/history image IDs are guarded. A narrow Gamebeast config compatibility wrapper prevents the observed nil EventData iteration. The oversized generated server Network file skips native compilation, and Blink postprocessing preserves that change without changing its protocol/body.

Production-code captures and smoke tests had no `MessageError` entries. Three startup warnings remain: the pinned Gamebeast SDK update notice, asset 203785492 type mismatch, and another blank ContentId warning. Early property tracing did not identify the remaining asset references. They have not been silenced, blamed on plugins, or claimed fixed. The SDK was not upgraded. Historical CSV-only errors were not treated as reproduced current failures.

Validation passed: Selene with zero errors/warnings/parse errors, StyLua on changed handwritten Luau, `git diff --check`, and Rojo builds for Survivors/Lobby/Defenders. Generated Network was checked against HEAD and differs only by its native directive. Lune checks execute current source algorithms: brute-force shape/point queries, recursive moves/removals, persistent decode/pruning, 1,200 nearest comparisons, 91-archetype partition alignment, and **4,000 commit-guard comparisons against the installed jecs 0.11.0**, including recycled generations and changed roles/columns.

Live checks passed: server freeze, revision change on recycling, rejection of an old reply after a small recycle displacement, client freeze/resume, manual pause/resume, camera hide/reentry, restart cleanup, and restart while death effects are pending. Full weapon/proc combinations, multiple clients, mobile devices, and long play sessions were not exercised.

**Reproduction and provenance**

Run `python performance/optimization-2026-10-22/checks.py` from the repository root. `analyze.py` rebuilds parsed summaries from raw MCP captures. `source-hashes.json` fingerprints the retained modified production modules. Baseline HEAD is `c9592f3fb5a82aa08f57396b1ff2b22422839d9f`.

`prepare.py before|after|clean LABEL` produces ordered private Tripwire source chunks under `/tmp/ballarc-final-bench`. It never changes `src/`. For a game benchmark, create a server Script and StarterPlayerScripts LocalScript named `BallarcFinalBench`, plus a ReplicatedStorage RemoteEvent `BallarcFinalBenchReady`. Concatenate chunks in numeric order per path before applying them. Start only after Studio has actually returned to PlaceIdle. Use the correct Survivors place, collect through `effects-done`, then stop, restore `clean` sources, and delete the probe instances. Labels containing `ownership`, starting with `pool`, or containing `actor-native` select the archived experiments; `detach-*` reads a held prototype. Never publish these probes. Private source chunks can contain existing SDK configuration keys; do not print or commit them.

The direct packing test uses `packing-kernels.server.luau` with four child modules: EntityBase/EnemyBase from the custom packers without compiler directives, and EntityNative/EnemyNative from identical bodies with the native/optimize directives. It alternates ordering over four rounds and checks byte/decoded equality.

Exclude `before-1`'s focus-lost 1,500-ground frame sample and all `after-1` frame samples, which were affected by background throttling. `pool-1-aborted.json` stopped on a probe namespace error. The moving-crowd detached/restored portions of `pool-2.json` are invalid because visible/animated counts changed; use `pool-static.json` for residency. Earlier lifecycle and target exclusions remain documented in the previous day's handoff. Intermediate `after-*` files have different candidate features/cadences and are not all final-source repetitions.

Further work with the strongest practical value is full-combat/mobile/multiplayer validation and an approach to idle-model residency that avoids expensive per-model hierarchy changes. The current high-water pools deliberately remain intact; the failed detachment/destruction prototypes should not be installed as optimizations.
