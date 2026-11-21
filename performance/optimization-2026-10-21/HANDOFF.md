# Ballarc performance work — stopped 2026-10-21

Resumed and completed locally on 2026-10-22. This document describes the historical stopping point; current retained changes, resolved cleanup, rejected experiments, and remaining validation limits are in [the new results](../optimization-2026-10-22/RESULTS.md).

User requested stopping because of the remaining usage limit. Implementation is unfinished and uncommitted. No publishing, staging, or commits were performed. BeACastleLord was consulted previously but was not changed in this implementation pass.

## Resume here first

1. **Revert the rejected contact-batching experiment. It is still present in production files.** In all four actor families' `Parallel/Work.luau` and `Parallel/init.luau`, remove the contact/telegraph arrays carried by Receive and restore individual side-effect messages. Keep tick/job/generation checks, movement revisions, pause invalidation, touched-result commits, and the other worker improvements. Update both ends of each protocol together. I announced the reversion, but the user stopped work before it was executed.
2. **Remove live benchmark instrumentation after Studio reconnects.** Both MCP Studios reported disconnected at handoff, with playtestActive=false. The earlier stop request had been issued, but independent lifecycle confirmation and source cleanup could not be completed. Do not restart or disconnect Rojo/Studio to accomplish this.
3. Review the complete diff and run final live correctness checks and a final combined before/after benchmark. The grouped measurements below are evidence for individual stages, not a measurement of the final combined source.

## Studio identity and pending cleanup

- Actual game: Survivors place **137835287157016**, Studio `9107c478-6cd2-4c70-9bf7-ecfd745d81c4`. Keep this active for game tests.
- Lobby: place **127928217434499**, Studio `7161908f-24fc-4292-b38a-7fac86d34d75`. Do not benchmark enemy gameplay there.
- Tripwire endpoint: `http://127.0.0.1:44331/mcp`.
- Delete `game.ServerScriptService.BallarcPerfProbe20261021`.
- Delete `game.StarterPlayer.StarterPlayerScripts.BallarcPerfProbe20261021`.
- Delete `game.ReplicatedStorage.BallarcPerfReady20261021` if present.
- Restore instrumented edit-mode modules from the current disk sources, after reverting rejected contact batching. In particular: EnemiesController, the four Parallel modules and their Work children; also check MovementPartitions, movement utility modules, and EnemyHashPackerService for older instrumentation.
- Expected client helpers are `EnemyRigQueue` and `EnemyRetirementQueue`. `EnemyModelRetirement` was an obsolete temporary name and should not exist.
- Check that no benchmark attributes, alternate legacy branches, audit counters, or probes remain. Root scripts may contain existing SDK keys: never print or archive their full source mappings into public reports.
- A source restoration mapping was prepared in **55** ordered `/tmp/ballarc-perf-20261021/clean-N.json` chunks. These contain source fragments grouped by Studio path; concatenate fragments in numeric order before updating each script. **These chunks predate the pending contact revert and must be refreshed first.** They were not applied because connections were lost.

## Measurements gathered

Local hardware: Ryzen 9 7900X, RTX 4060, Linux/Vinegar Studio 0.744, viewport approximately 1900×570. These are controlled single-client Studio tests with real Slime/Bee models, an anchored invulnerable character, and progression/weapons held. They do not establish mobile, multiplayer, or full late-game-combat capacity. Production enemy cap remains 1,500; 3,000 was a stress test. Frame values below are milliseconds; lower is better. Improvements from separate stages must not be added together.

| Change / scene | Before | After | Interpretation |
| --- | --- | --- | --- |
| Client update cost, 3,000 enemies, two runs | 4.73–4.77 ms | 2.98–3.06 ms | About 36% lower measured update time |
| Same stage, median frame | 10.06–10.10 ms | 7.99–8.16 ms | About 20% lower median frame time |
| Snapshot packing, 3,000, 8-second windows | 478–484 ms summed packing time; 748–752 packs | 58–60 ms; 77 packs | About 88% less elapsed packing time and 90% fewer packs |
| Coalesced workers, mixed 1,500, frame p95 | 22.39 ms | 8.54 ms | About 62% lower p95 in fragmented archetype scenario |
| Same worker scene, server Heartbeat p95 | 26.01 ms | 12.99 ms | About 50% lower p95 |
| Workers, uniform 3,000, median / p95 | 8.36 / 13.45 ms | 8.20 / 13.44 ms | Small median change; p95 effectively unchanged |
| Charm spatial targeting, 3,000, p95 | 30.28 ms | 18.25 ms | About 40% lower p95; median ~9.47 ms unchanged; needs reversed-order repeat |
| Lifecycle v2, 1,500 burst spawn p95 | 32.85 ms | 19.15 ms | About 42% lower spike percentile |
| Lifecycle v2, 3,000 burst spawn p95 | 30.61 ms | 23.02 ms | About 25% lower spike percentile |
| Lifecycle v2, 3,000 death phase p95 | 16.54 ms | 5.03 ms | About 70% lower p95; full frame includes server removal work |
| Lifecycle v2, 3,000 attachment completion | 1.15 s | 2.42 s | Tradeoff: smoother burst with slower full visual attachment |
| Lifecycle v2, 3,000 Temporal children | 3,202 | 240 | Bounded particle allocation; zero per-living-enemy DeathEffect components |

Lifecycle retained high-water model pools. An earlier aggressive pool-trimming prototype was rejected: it caused sustained post-death frame regressions. Its raw result is retained only as provenance. Lifecycle v2 measurements precede the latest nearest-first heap/helper refactor, so rerun the final version.

Latest contact test: 500 stationary overlapping Slimes, 40,000 damage callbacks and 80 position ticks per 8-second sample. Before median/p95 4.30/5.39 ms; after 4.32/5.56 and 4.31/5.75 ms. Server Heartbeat p95 stayed around 6.01 ms. The last before sample lost focus and is excluded. Batching preserved contact counts but showed no frame benefit and slightly worse valid p95; revert it. Structural message-count reductions alone are not a measured player-facing gain.

## Implemented changes awaiting final review

- **Spatial hash correctness:** cross-cell Update/Update3 now refresh coordinates; shape broad phase accounts for center-indexed extents; recursive records are deduplicated and checked exactly; recursive move/remove works; point queries reject recursive false positives. This fixes correctness defects, not just speed.
- **Persistent decode:** new SpatialHashDecoder reuses record tables/bucket arrays, clears obsolete fields, and prunes absent entries using epochs.
- **Worker coalescing:** new MovementPartitions combines archetype rows into persistent partitions; max one job per worker/category, minimum 64 rows/job; single in-flight batch with timeout; tick/job IDs and duplicate/old-reply rejection; map/pause invalidation; movement revisions for recycled entities; role/stun/telegraph validation; touched-result commits. Force remains main-thread-owned. Latest residual cadence retains elapsed remainder with one dispatch per Heartbeat.
- **Charm targeting:** radius-10 spatial lookup from the same collision snapshot, full-scan fallback, stable lower-ID ties, no duplicate full target-position buffer per worker.
- **Snapshot packing:** lazy, at most once per dispatching frame; idle/paused/non-dispatch Heartbeats avoid full O(N) packing.
- **Client transforms/animation:** cache ground targets and terrain normals, preserve flying smoothing, cache Animator state, handle enemy time scale in animation state, clear caches on removal/reset.
- **Client lifecycle:** logical spawn before model attachment; soft attach time budget and clone/attachment caps; latest queue uses nearest-first heap with stable ties; cached template radii and tracks; smaller warm reserves; queued elite preparation; no per-enemy preallocated death effect; bounded hit/death effects and centralized returns; bounded retired-model destruction. Burst particle density is reduced intentionally under load. Normal model pools retain their high-water capacity.
- **Other fixes:** elapsed-time camera sync at 20 Hz; defensive truncated enemy packet handling; blank image URI handling; Gamebeast GBConfigs/EventData compatibility wrapper; remove native compilation only from oversized generated GlobalServer.Network and preserve that in Blink generation via postprocess.py.

## Validation completed and limits

- Selene passed all changed production Luau and new helpers: zero errors/warnings/parse errors at the latest broad pass.
- Rojo builds passed for Survivors, Lobby, and Defenders.
- git diff --check passed.
- Blink regeneration verified the generated server protocol/body unchanged except removal of the native directive; client/types unchanged.
- Lune tests passed: 40,000 mixed-shape brute-force hash comparisons plus movement/removal/recursive cases; 91-archetype partition alignment and persistent decode/pruning; 1,200 spatial-nearest results against full scan; nearest-first queue ordering/ties/3,000 entries and bounded 1,500-model retirement.
- Tests and probe generators currently live in `/tmp/ballarc-perf-20261021`; archive a runnable, reviewed reproduction set before considering the task complete.
- **Not yet completed:** final combined production-source live benchmark; queued spawn canceled before attach; stale reply after same-ID recycling; pause/freeze/resume without animation/origin glitches; camera hide/reenter; reset/restart cleanup; representative 3,000-enemy test of latest heap, cadence, pause guards and recursive hash refinements; real weapons/procs; multiplayer; mobile.

## Errors and warnings

- Later valid runs no longer reproduced Gamebeast nil iteration, oversized generated-network native compile failure, or empty inventory image URI errors after their fixes.
- Gamebeast out-of-date warning remains. SDK was not upgraded; compatibility wrapper is a narrow fix, not an SDK migration.
- Audio asset 203785492 warning remains unlocated. Verified publicly as an audio asset, but searches did not establish the referencing instance/source. It may involve Studio/plugin content, but that is unproven. Do not claim fixed or suppress it.
- Historical CSV UI/Fluid C-stack issue was not reproduced; no speculative broad UI rewrite performed.

## Artifacts and reproducibility

- Prior deep audit: `../audit-2026-10-21/REPORT.md` and adjacent evidence.
- `before*.json`: original baseline.
- `client-packing-ab*.json`, `workers-ab*.json`: grouped A/B captures and parsed samples.
- `target-ab.json`: target comparison. **Exclude first 1,500-before sample: it was paused with zero visible enemies/traffic.**
- `lifecycle-before.json`: corrected handshake baseline with all spawns counted.
- `lifecycle-before-preliminary.json`: superseded; initial spawns missed, do not use.
- `lifecycle-after-rejected-trimming.json`: rejected prototype, do not cite as retained result.
- `lifecycle-after.json`: retained v2 measurements before latest queue refactor.
- `contacts-ab.json`: complete latest contact-test capture; exclude focus-lost last sample from frame comparison.
- `/tmp/ballarc-perf-20261021/baseline/src`: exact turn-start source snapshot, from HEAD c9592f3fb5a82aa08f57396b1ff2b22422839d9f.
- `/tmp/ballarc-perf-20261021/stage2-baseline/src`: intermediate source before charm target-buffer removal/contact batching.
- Local tracked changes are the implementation; preexisting untracked `Errors and warnings by count.csv`, `data/`, and prior `performance/` artifacts were left intact. No commit was made. Some temporary source mappings contain existing SDK keys; keep them private.

After the rejected experiment is removed, finish correctness/live cleanup, repeat the important A/B comparisons in reversed order, then produce the final report with final combined numbers and explicit hardware/workload limits.
