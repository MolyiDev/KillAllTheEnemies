# Ballarc enemy performance audit — 2026-10-21

Audit baseline: Ballarc `c9592f3fb5a82aa08f57396b1ff2b22422839d9f`; BeACastleLord `0a00235a06ac8f6dfc65543eeb4c5c4fd162e698` with its existing working-tree changes. This is an audit and a collection of temporary benchmark experiments, not a production optimization patch.

## Recommendation

Keep Ballarc's server ECS, client-owned skinned rigs, local AnimationTracks, spatial collision queries, packed position updates, and parallel movement. The strongest opportunities are the work surrounding those systems: repeated worker snapshot decoding, fragmented dispatch, unnecessary snapshot packing, per-frame client orientation work, synchronous rig allocation, persistent AOI residency, and expensive burst paths.

Do not replace the enemy renderer with Humanoids, swap bones for BulkMoveTo, or remove Actors on the strength of a CPU microbenchmark. Ballarc already implements much of the architecture that a generic large-crowd recommendation would propose. Your existing rendering experiments support keeping it, subject to actual-asset and device measurements.

Two shared spatial-hash correctness defects should be fixed before tuning collision quality. Both also exist in BeACastleLord's byte-identical module.

## Evidence and benchmark boundaries

The initial isolated server benchmarks ran in the lobby, place **127928217434499**. They execute actual shared spatial-hash and extracted movement functions, but contain no Survivors client, real gameplay scene, or Actor scheduling. They are algorithm measurements only. The user correctly identified this distinction.

Subsequent F5 measurements ran in the actual Survivors place, **137835287157016**, verified against `survivors.project.json`, its game-specific module tree, a live character, generated terrain, and the actual position RemoteEvent. The client viewport was **1900 × 570**. No desktop focus or graphics configuration was changed.

Machine verified during the audit: **Ryzen 9 7900X (12 cores / 24 threads), RTX 4060**, NVIDIA driver 615.78.08; Studio log build `0.744.0.7441077` under the existing Linux/Vinegar environment. This is a strong development machine and a relatively short viewport, not a representative mobile device. Frame-cap behavior was not independently controlled; the 500-enemy median is near a 240 FPS floor. The focus-loss event did not fire during samples, which alone does not prove initial focus.

Controlled game scenes spawn actual Slimes on a three-stud grid around an anchored, invulnerable character. Weapons and progression are held; movement, terrain/crowd collision, server ECS commits, AOI encoding, position delivery, the actual client controller, and rendering continue. These tests exclude the weapon/proc/VFX load of a late-game build. Server and client run together in Studio on this machine, so a serial server hitch can directly disturb the client. Production uses separate processes/machines. A low frame time here does not certify low-end mobile performance.

Run 1 uses a high overhead camera and normal animation-distance settings, so it is a movement/rendering test with distant animation culled. It is **not** an all-animated crowd test. The first two 500-enemy stages were contaminated by a delayed normal-game start and contain 510/566 enemies; exclude them from a matched A/B conclusion. The 1,500 and 3,000 stages have the requested population. Later measurements explicitly force animation range and record playing-track counts.

Raw logs and runnable probe sources are stored alongside this report. `engine-run-2.json` supersedes run 1's erroneous crowded-layout measurement. The decoder microbenchmark reuses a stable population and excludes stale-entry cleanup; treat its speedup as an upper bound for that mechanism. The later game decoder experiment includes removal of records and buckets absent from the new snapshot.

## Measurements: what they establish

### Real Survivors movement pipeline, run 1

| Active/visible Slimes | Current parallel client median / p95 | Direct serial prototype median / p95 | Actual client Update median, current |
| --- | --- | --- | --- |
| 1,500 | 5.09 / 5.94 ms | 5.07 / 19.37 ms | 2.25 ms |
| 3,000 | 9.36 / 11.33 ms | 9.22 / 63.41 ms | 4.79 ms |

The serial prototype uses the real movement function with live hash tables and table results instead of snapshot decoding and result serialization. It takes **20.75 ms/tick at 1,500** and **51.38 ms/tick at 3,000**, before commit and encoding. These scenes are much more expensive than the uniform flat-world microbenchmark. They establish a practical reason to retain parallelism. They do not establish how much an optimized parallel implementation will save.

The current spatial snapshot packer ran **195 times/s at 1,500** and **105 times/s at 3,000**, following the Studio Heartbeat rather than the approximately 10 Hz movement cadence. Its measured record+bucket packing cost was **53.3 and 63.5 ms CPU/s**, respectively. Therefore “once per frame” can mean much more than 60 Hz in Studio; production must be measured separately.

Measured raw position-buffer traffic to this single, all-visible client was **118.3 kB/s at 1,500**, **229.3 kB/s at 3,000**. These figures are application buffer lengths, **not wire bandwidth**: Roblox serialization, compression and transport overhead are excluded. The actual transport is `RemoteEvent`.

### Real Survivors, all animations playing, run 2

This pass prevents delayed progression restarts, has exactly the requested populations, forces render/animation range to 1,000 studs through local controller signals without saving settings, and logs the actual playing-track count. Every enemy in these rows was resident, visible according to the controller, and playing its walk track. The camera remains 210 studs above the scene; no occlusion or screen-projection audit was performed. “Visible” here means the controller accepts its view/distance/staleness checks.

| Enemies / playing tracks | Current median / p95 | Reused decoder median / p95 | Current worker mean per job → reuse |
| --- | --- | --- | --- |
| 500 / 500 | 4.15 / 5.25 ms | 4.16 / 5.30 ms | 0.542 → 0.546 ms |
| 1,500 / 1,500 | 5.53 / 6.37 ms | 5.43 / 6.27 ms | 2.415 → 2.302 ms |
| 3,000 / 3,000 | 10.09 / 12.08 ms | 10.10 / 12.12 ms | 5.921 → 5.743 ms |

These worker values are `os.clock` elapsed durations summed across jobs and divided by jobs. They include decode, movement math and result packing; they exclude dispatch/copy/receive/commit. They are **not measured per-thread CPU time or end-to-end parallel latency**. Work can overlap and be preempted.

Normalized by processed rows, reuse changes summed worker duration by **−0.7% at 500, +4.7% at 1,500 and +3.0% at 3,000** (positive means improvement). That is a modest signal from one sequential A/B per population, not a robust production speedup claim. The frame times show **no material improvement at 3,000**. Cleanup and collision work make the practical gain much smaller than the isolated decoder ratio. Retain reuse as a useful allocation reduction candidate, but prioritize profiling collision density, client target construction and worker snapshot duplication over promising a large FPS gain from this patch alone.

Each stage settles eight seconds after chunked creation and samples seven seconds. This is shorter and less rigorous than the adaptive multi-window settling recommended by BAC's methodology; the close A/B differences may be noise or scene evolution. The 3,000 count exceeds Ballarc's normal production cap of 1,500 only through the test spawner. These results establish a controlled desktop stress scene, not a validated cap increase.

### Isolated algorithm measurements, lobby F8

| Same work, paired samples | Current median | Prototype median | Interpretation |
| --- | --- | --- | --- |
| Full hash decode, 1,500 records | 0.339 ms | 0.064 ms | 5.32× faster stable-table decode |
| Full hash decode, 5,000 records | 1.018 ms | 0.232 ms | 4.39× faster stable-table decode |
| Ground movement, 1,500, 16 chunks executed sequentially | 8.25 ms | 2.69 ms | 3.07× lower aggregate CPU without repeated decode/serialization |
| Ground movement, 5,000, same comparison | 26.83 ms | 8.95 ms | 3.00× lower aggregate CPU; not parallel latency |
| 250 nearest-enemy searches, 1,500 | 1.095 ms | 0.879 ms | Exact local search plus full-scan fallback, 1.25× |
| 250 nearest-enemy searches, 5,000 | 3.480 ms | 0.924 ms | Same, 3.76× |

The movement outputs matched exactly in that flat-world experiment. It excludes Actor messaging/copy, partition construction, ECS/hash commits, networking, combat and the client. Sixteen sequential decodes cost 3.83 ms at 1,500 and 14.88 ms at 5,000, but those are **aggregate serial CPU equivalents**, not measured parallel wall time.

Ordinary versus adversarial density also matters. Two hundred radius queries over 5,000 spaced records took 0.127 ms and visited 827 candidates; placing all 5,000 in one bucket took 40.36 ms and visited 1,000,000 candidates. This counts callbacks without full collision math. It demonstrates degeneration under extreme overlap, not an expected normal frame.

## Priority 0: correctness and bounded work

### 1. Update coordinates after a hash-cell crossing

[SpatialHash.Update / Update3](../../src/Global/Shared/Utils/SpatialHash.luau) only write record X/Z in the branch where bucket membership stays unchanged. Moving to a new bucket updates its membership but preserves the old position in `Records`.

Engine reproduction: add `(1,0,1)`, update to `(6,3,1)` with cell size 5; the record becomes `(1,3,1)`. Repeating the update finally changes X to 6. This affects snapshots, collision, queries and teleported/recycled enemies.

Write X/Y/Z unconditionally after membership maintenance, in both overloads. Benefit: correct collision/target data and fewer misleading measurements. No defensible FPS percentage; the fix may increase legitimate collision work by restoring previously missed interactions.

### 2. Define and repair shape-query broad-phase semantics

AABBs are stored in their center bucket, but shape-aware radius queries visit only buckets overlapped by the query circle. An intersecting box whose center lies in another bucket can be missed.

Engine reproduction: box center X=5.1, half-width=1; circle center X=4, radius=0.2; geometrically overlapping, zero results. Choose either center-point membership with an extent-expanded broad phase and exact narrow phase, or true multi-cell shape membership with deduplication and correct updates. Preserve `AsPoints` semantics for callers that intentionally query centers. Wider candidate sets cost CPU; correctness should precede choosing the smallest useful broad phase.

### 3. Give movement jobs a tick and entity generation

Each [actor Parallel module](../../src/Survivors/Server/Actors/EnemiesActor/Parallel/init.luau) resets shared partition counters and the result map when dispatching. Replies carry no dispatch epoch. Under overload, old replies can mix with newer work. The current 100-stud displacement guard protects large teleports, but not job age, ID reuse, tag changes, or smaller stale movements.

Use `(tickId, entityId, generation)`, accept only the intended batch, and allow one in-flight batch or a tightly bounded versioned pipeline. Count dropped/late jobs and end-to-end dispatch-to-commit latency. Preserve main-thread ownership of Force: the stale Force writeback has already been fixed. Benefit: prevents backlog and stale writes; throughput gain is workload-dependent rather than guaranteed.

## Priority 1: improve the current server design

### 4. Reuse decoded records and bucket arrays

[Ground worker](../../src/Survivors/Server/Utils/enemiesUpdateServer.luau) clears both outer maps, then `UnpackRecordsInto` allocates one new table per record and `UnpackBucketsInto` one per bucket. “Into” currently reuses the map, not its contents. All four movement variants need the same review.

At 5,000 spaced entities, a snapshot contains 5,000 record tables and 1,824 bucket arrays. Sixteen jobs at 10 Hz create about **1.09 million tables/s**, before result decoding and partitions. At 1,500 the corresponding estimate is **324,640/s**. These estimates assume one 16-job wave; archetype fragmentation can increase it, while fewer jobs reduce it.

Persist records by entity ID, refill bucket arrays, and prune missing IDs/buckets with a generation stamp or equivalent lifecycle mechanism. Handle shrinkage, shape changes and recycled IDs. The isolated decode cost falls 77–81% in the stable-population prototype; **do not apply that percentage to the whole movement tick or FPS**. Reuse also removes a source of GC variance.

### 5. Decode once per worker per tick and partition across archetypes

Each category precreates 16 workers: 64 across normal/flying/charmed/charmed-flying. The dispatcher partitions each archetype separately and starts again at worker 1. This can send several jobs with the same full snapshot to the same worker in one tick.

First coalesce compatible archetype columns into balanced jobs and cap the total jobs per category/tick. Cache a decoded snapshot by snapshot version within each worker. Then benchmark 4/8/16 workers under representative density and mixed tags. Fewer larger jobs lower copy/decode overhead but reduce parallelism; too many tiny jobs add overhead and may skew load. Enemy count alone is insufficient: a dense corner needs a different balance than a sparse field.

Longer term, spatially partition work and send each worker its owned entities plus a halo covering maximum interaction reach. That avoids every worker receiving the whole world. Cross-boundary collisions, movement between cells, terrain climbing, charms and bubbles make this a substantial change. A shared immutable/double-buffered snapshot is another candidate; [SharedTable avoids message copying](https://create.roblox.com/docs/scripting/multithreading) but has different access costs and must be benchmarked, not assumed faster.

### 6. Preserve result reuse and commit actual result IDs

`receivedEntitiesInfo` is cleared before the next wave, defeating per-record reuse in `EntityPacker.UnpackServerInto`. Keep reusable result slots and a touched-ID list; distinguish current batch membership from allocated storage. Commit only touched valid entities rather than scanning the broad `EnemiesIdQuery` after each category completes. Existing output `infoSlots` in the worker are already pooled; retain that optimization.

Benefit: removes roughly one result-table allocation per moved enemy/tick and avoids full-world commit scans for sparse categories. Absolute savings require separate receive/commit profiling; no measured whole-frame estimate.

### 7. Pack one immutable collision snapshot per movement tick

[EnemyHashPackerService](../../src/Survivors/Server/Services/EnemyHashPackerService.luau) packs every Heartbeat, including ticks with no dispatch. Coordinate snapshot construction with dispatch, share its version across categories, and skip unnecessary work while paused. All jobs for a simulation step should read the same snapshot.

Changing 60 Hz packing to 10 Hz removes 83% of this particular work. In the measured game run, packing was 105–195 Hz: targeting 10 Hz would remove roughly **90–95%**, or approximately **51–57 ms CPU/s** if per-pack cost remained similar. That is about 0.85–0.96 ms of CPU per 60 Hz frame when amortized, not an equivalent guaranteed frame-time reduction. A timer alone can give workers older data; a coordinated snapshot is preferable.

### 8. Replace repeated charm target scans

[nearestEnemy](../../src/Survivors/Server/Utils/nearestEnemy.luau) scans the whole enemy-position map for every charmed enemy. At 5,000 enemies and 1,000 charms, that is approximately 5 million comparisons/tick, 50 million/s at 10 Hz.

Keep a valid target until reacquisition is needed; stagger reacquisition. Use a radius query with exact distance comparison. If a target is found inside radius R, entities outside R cannot be nearer; otherwise expand or fall back to the full scan. This preserves nearest-target semantics. Exclude self exactly as today and preserve the current eligibility rules, including whether other charmed enemies can be targeted.

The 5,000-enemy microbenchmark reduced candidates about 146× but elapsed time only 3.76×; generic hash-query overhead matters. Do not sell candidate reductions as CPU speedups. Sticky targets can save more but change responsiveness if the refresh interval is too long.

### 9. Batch contact messages without changing thorns

Workers send individual `Damage` Actor messages for touching enemies. Main-thread damage cooldowns reject repeated player hits, but the handler still evaluates thorns/Thornstorm per attacker. Batch contact IDs per worker/player/tick. Resolve the player once and process the batch under existing rules.

Do not collapse the batch to one attacker unless changing thorns/proc balance is intentional. This reduces message and repeated lookup overhead; contacts and passives must be profiled to estimate milliseconds.

### 10. Bound density-sensitive separation work

Hashing does not bound the number of nearby neighbors. Add occupancy/candidate counters, then benchmark the existing climbing/separation behavior in a corner, a BlackHole pile, and a multi-player choke point. Spatially balanced jobs reduce stragglers. A cap of nearest K separation neighbors, aggregated pressure fields, or lower-frequency distant separation can bound cost, but each changes crowd behavior. Keep exact authoritative damage/weapon queries separate from approximate separation.

### 11. Make fixed-step cadence explicit

The updaters reset their accumulator to zero after dispatch, discarding residual time. In a synthetic 60-second clock, nominal 10 Hz produced 514 updates at exactly 60 FPS versus about 599 when preserving the remainder. Real scheduler timing differs.

Use residual time with a bounded catch-up/drop policy. This corrects simulation cadence and overload behavior; it is **not a free optimization**. Correcting 8.57 Hz to 10 Hz increases work approximately 17% and may change movement pace relative to today's implementation. Verify slow motion, freeze pulses and restart behavior.

## Priority 1: client cost, residency and bursts

### 12. Cache target orientation and terrain-derived values

[EnemiesController.Update](../../src/Survivors/Client/Controllers/Actor/EnemiesController.luau) recomputes yaw, terrain lookup, slope projection, normalization, trigonometry and a target CFrame every visible frame; it also writes ECS orientation/CFrame state and checks AnimationTrack state per enemy.

Compute terrain normal and a stable target transform when a position packet arrives, or when its terrain cell/heading changes. Keep the cheap interpolation and root-bone write per rendered frame. A packet-derived heading or velocity differs from a heading based on the current smoothed position, so assess turns, slopes, airborne motion and knockback visually.

Moving selected calculations from 60 Hz to 10 Hz removes 83% of **those calculations**, and even more at 120/240 Hz. In run 1, the entire controller measured 2.25 ms median at 1,500 and 4.79 ms at 3,000. Those totals are useful ceilings on potential script savings, not an amount recoverable in full: iteration, visibility, interpolation and transform writes remain. A whole-loop 2× improvement, if a prototype established it, would save about 1.1/2.4 ms respectively; it is currently a target, not a measured result.

### 13. Track animation transitions and use hysteresis

Avoid checking `IsPlaying` on every resident enemy every frame. Store controller-owned animation state, change it on visibility/range/pause transitions, and evaluate distance tiers at a bounded cadence with hysteresis. Preserve the existing animation-distance setting and client-only Animator path. Never restart a frozen track at speed zero simply because it is inside animation range; test freeze/resume explicitly.

Use animation LOD to reduce distant skeletal work where the change is visually acceptable. It will not reduce the root-transform work required for moving enemies. The old Animator-versus-procedural benchmark already favors AnimationTracks for its tested rig, so replacing Animator with per-bone Luau is not justified.

### 14. Separate logical AOI subscription from resident rigs

[AOIService](../../src/Survivors/Server/Services/AOIService.luau) remembers discovered enemies until kill, recycle, disconnect or reset; leaving view does not normally release the client's rig. The client parks stale/invisible bones far away but retains the ECS row, model, cached track and per-enemy death effect.

Keep a lightweight logical record while releasing rigs outside a padded view/distance region after a delay. Maintain a bounded warm pool per useful type/tier. Apply a per-frame attachment budget when re-entering. Reliable lifecycle events and entity generations must prevent late snapshots from resurrecting old entities. Preserve kill-credit/subscription behavior separately.

Potential reduction scales with actual residency: if 3,000 enemies are logically known but only 600 require rigs, active rig/Animator count can fall 80%. This is an example, not an observed Ballarc ratio. If all 3,000 are visible, AOI residency cannot deliver that saving. Memory per actual rig still needs measurement.

### 15. Adapt BeACastleLord's queued rig attachment

Ballarc creates pools of 60 normal rigs and 60 death attachments synchronously per type, and refills five at once when empty. Prewarming exists, but can still cause a concentrated startup or type-introduction stall. `AddEnemy` acquires a death attachment for every living enemy, calculates model extents, and starts the walk track even if the enemy will immediately be culled.

Current [BeACastleLord EnemiesController](../../../BeACastleLord/src/FeedTheCore/Client/Controllers/EnemiesController.luau) separates logical spawn from attachment, queues work, uses a reserve target of 24, at most five clones and eight rig attachments/frame, and shares the clone budget with reserve refills. Adapt the mechanism with a time budget measured on Ballarc assets. Do not blindly transplant its counts or destruction policy.

Cache extents/radius per template and elite tier; the server's `getModelExtents` already caches and does not need this advice again. Keep Ballarc's model-to-AnimationTrack cache. Acquire death effects at death from a bounded effect pool rather than reserving one per living enemy, with a cosmetic overflow policy. Prewarm the expected early burst across frames before the wave.

Existing BAC spawn costs (~0.4 ms for its later real enemy clone, 1.4–1.7 ms for an older skinned test asset) show why scheduling matters, but are **not Ballarc Slime measurements**. If Ballarc clones cost 0.4 ms, moving 60 clones out of one frame would distribute approximately 24 ms of cloning; verify the premise before quoting it as a gain.

### 16. Preserve smooth presentation while changing cadence

Current exponential following uses `RENDER_DT = 4`, approximately a 250 ms time constant at normal speed, on top of snapshot delay. Timestamped snapshot interpolation can make motion more consistent and enable packet loss handling, at the cost of an explicit interpolation delay. Test 100–150 ms buffers against current motion before choosing one. Nearby damaging threats should remain readable and consistent with authoritative positions.

Do not move bone-driven combat to Workspace overlap queries: moving the root bone does not move the MeshPart's physics representation. The existing custom server spatial representation is essential.

## Networking

### 17. Keep the existing compact format; reduce selected records first

[EnemyPacker](../../src/Survivors/Shared/Packers/EnemyPacker.luau) already uses two header bytes plus **8 bytes/enemy**: u16 ID and three quantized signed coordinates at 0.05-stud precision. `PackFiltered` already uses a single-pass scratch buffer. Generic “batch your updates/use buffers” advice has already been implemented.

At 10 Hz, 1,500 fully selected enemies imply about 120 kB/s raw payload/client and 5,000 about 400 kB/s, before compression and overhead. With eight players all receiving 5,000, aggregate raw server payload would be 3.2 MB/s; actual frustum/distance selection may be much lower. Encode the quantized world state once per simulation tick, then select/copy records per player; benchmark against the current fused encoder because extra staging can lose at low player counts.

Use changed-position thresholds and distance/importance tiers, with periodic refreshes. Preserve the client's one-second stale timeout: suppressing stationary updates forever currently causes legitimate enemies to disappear. Near threats and camera re-entry need prompt updates; do not obtain bandwidth savings by hiding relevant enemies.

### 18. Treat unreliable transport as a protocol change

The actual position event is reliable. [`UnreliableRemoteEvent`](https://create.roblox.com/docs/reference/engine/classes/UnreliableRemoteEvent) is suitable for superseded motion but has unordered/lossy delivery and a documented 1,000-byte event payload limit. The full 1,500-enemy buffer is about 12 kB, so changing the Instance class alone is invalid.

Use conservatively sized chunks (for example 800–850 bytes before verifying the engine-encoded payload), snapshot sequence/time, and entity generation. Reject older updates for each entity when chunks arrive out of order; one global last-sequence value can incorrectly reject a different chunk from the same snapshot. Keep spawn/death/recycle reliable. Test loss, reorder, missing chunks, camera re-entry, freeze pulses and respawn. It can avoid queueing obsolete motion; it does not inherently reduce payload bytes.

Signed 16-bit coordinates at 0.05 resolution span about ±1,638 studs. The current map scale fits; enlarging the world eventually needs a sector/origin scheme rather than silent wrapping. Sequence/generation and packet metadata add bytes to the present compact format.

### 19. Make camera synchronization time-based

[CameraController](../../src/Survivors/Client/Controllers/CameraController.luau) sends every three rendered frames: approximately 20 Hz at 60 FPS, 80 Hz at 240 FPS. Use an elapsed-time target and position/direction thresholds with a maximum refresh interval. At 240 FPS, capping at 20 Hz removes 75% of calls. These are already compact unreliable messages, so this is a small improvement; ensure fast camera turns still update AOI quickly.

## Combat, effects and lower-priority paths

| Opportunity | Why / implementation | Estimate and tradeoff |
| --- | --- | --- |
| Batch remaining heterogeneous area damage | Most weapons already call `DamageMultiple`; preserve that. Explosive barrels still apply distance-dependent damage individually. A batch accepting per-target values can preserve falloff without inventing shared damage. | Fewer handler/transport calls; measure real weapon builds. Crit/proc ordering and kill credit must remain identical. |
| Batch DoT deaths | `DebuffsCore.Tick` and the enemy service update DoT continuously and can call individual kill paths during a large expiry/death wave. Collect deaths by inflictor and compatible damage semantics before dispatch. | Primarily burst/tail savings. Preserve each actual damage amount and on-kill behavior. |
| Schedule expiries and projectile arrivals | Many projectile `CourseTime` values are decremented every Heartbeat despite known arrival times. Use entity-clock deadlines and a heap/time wheel where appropriate; skip inactive debuff work. | Work changes from all-active polling toward due events. Pauses/time scales, target death, bounce/split order and staged damage refunds complicate it. No measured milliseconds. |
| Cache combat modifiers per batch/version | Repeated passive/augment resolution can dominate mass hits. Existing `DamageMultiple` already hoists some collection. Cache only stable values; invalidate on loadout and conditional-stat changes. | Build-specific; health/velocity-dependent passives cannot be frozen for a whole wave. |
| Budget cosmetic effects and return work | Hundreds of deaths can create many delayed returns and particles in one frame. Share return queues and cap expensive local effects by density/distance. | Lower p95 during mass kills; visible cosmetic reduction, no dropped authoritative kills/damage. Floating numbers already have a 200 cap, 24 Hz update and spatial deduplication. |
| Fix native compilation scope | Actual startup warns that generated `GlobalServer.Network` exceeds the native code-generation memory limit and runs interpreted. Exclude huge cold generated code via generator/configuration and confirm the intended hot math is native. | This warning does not prove movement is interpreted. No automatic 4× claim; use native compiler/profiler evidence. |
| Update performance guidance with measured rules | BAC's Luau experiments contradict the blanket numeric-loop rule and show several micro-optimizations are small or engine no-ops. | Avoid widespread style churn. Algorithm, copying and allocation dominate these findings. |

Drop pickup throttling, shard fusion/caps, pooled output records, batch damage, frustum filtering, freeze pulses, pre-scaled elite templates and cached walk tracks already exist. They should be preserved and measured, not listed as missing optimizations.

## What the BeACastleLord results actually transfer

- [02](../../../BeACastleLord/performance/02-bone-vs-motor6d.md): root Bone.Transform writes were ~79 ns versus Motor6D ~86 ns in its microbenchmark. This points away from replacing Ballarc's root-write primitive. Ballarc's whole client loop is orders of magnitude more work than that individual write.
- [05](../../../BeACastleLord/performance/05-animation.md): AnimationTracks beat the tested procedural gait on script cost. Ballarc already has the advantageous local Animator path.
- [06](../../../BeACastleLord/performance/06-color-transparency-fastcluster.md) and [07](../../../BeACastleLord/performance/07-scale-size-and-the-vacuum-stretch.md): avoid large transparency-boundary and runtime skinned-size/ScaleTo changes. Ballarc's pre-scaled elite templates already follow this principle.
- [09](../../../BeACastleLord/performance/09-skinned-ceiling.md): the corrected test was stable around 4,800 skeletons (5.60 ms median, 6.80 ms p95), with a serious p95 cliff at 6,000. This is a tested asset/device/scene boundary, not a Roblox NPC limit or a guarantee for 4,800 Ballarc enemies. Early insufficient-settle results were misleading.
- [11](../../../BeACastleLord/performance/11-packing-sweet-spot.md): 25–50 **moving bones per mesh** was the best range in that packing experiment. With 13 bones per full enemy, this is only about 2–4 full enemies/mesh, not 25–50. Independent phase, tint, scale, animation and culling become harder. Investigate only after profiling an actual per-mesh engine bottleneck, probably as a distant crowd LOD.
- [14](../../../BeACastleLord/performance/14-enemy-spawn-with-highlight.md): clone/attach scheduling is more actionable than assuming Highlight is the primary spawn expense. Its real enemy asset differs from Ballarc's.
- [15](../../../BeACastleLord/performance/15-luau-idioms.md): measured idioms should replace assumptions. Generalized iteration was faster than numeric iteration in its pure-loop tests; native helped compute but not Instance/allocation work. These are local ratios, not a reason to rewrite every loop.
- [16](../../../BeACastleLord/performance/16-shell-ripple-mechanism.md): the existing shell experiment supports an effect-specific EditableMesh choice and documents budget/failure pitfalls. It provides no evidence that EditableMesh is the right enemy renderer.

Current BAC `FeedTheCore` uses more serial movement and navigation support for a different gameplay scale; its configured maximum is **230**. Its flowfield machinery is relevant if Ballarc needs navigation around obstacles, but Ballarc currently performs direct chase and terrain climbing rather than thousands of PathfindingService requests. A flowfield would primarily change navigation behavior; there is no expensive per-enemy pathfinding system here to “remove” for an assumed speedup.

## Complete target architecture and rollout

1. **Authoritative ECS:** stable entity ID + generation, server-only combat/collision state, correct spatial records, explicit pause-aware clocks.
2. **Movement coordinator:** fixed cadence with bounded overload policy, one immutable snapshot/version, globally balanced jobs, explicit tick/generation validation, bounded in-flight work.
3. **Parallel workers:** persistent decode storage initially; one decode/worker/snapshot; spatial subsets plus halo only if the simpler implementation still dominates. Return compact touched results and batched contacts.
4. **Spatial target/collision systems:** correct broad phase, exact damage queries, cached/staggered targeting; optional approximations only for separation and distant AI with agreed behavior tradeoffs.
5. **Replication:** reliable lifecycle, compact selected position records, per-player relevance with hysteresis, timestamps and periodic refresh; unreliable chunking only after protocol correctness tests.
6. **Client entity records:** lightweight logical existence separated from bounded resident visuals; queued/prewarmed rig attachment and cached tracks/templates; death effects allocated for deaths.
7. **Client presentation:** cached packet-derived targets, per-frame interpolation/root writes, animation transitions and distance LOD, bounded cosmetic work. Keep current skinned assets initially.
8. **Combat scheduling:** batch compatible hits/deaths/contacts, absolute event deadlines where useful, unchanged authoritative outcomes.
9. **Instrumentation:** separate worker compute, dispatch-to-commit latency, main-thread pack/partition/receive/commit, client script, engine rendering/animation, allocation/GC, raw selected bytes, residency and spawn queues.

Start with correctness and observability, then low-risk decode/result reuse and coordinated packing; next client target caching and queued attachment; then residency/network tiers; finally larger parallel/spatial changes. Re-profile each step and keep a change only when its control comparison improves the relevant budget.

## Performance expectations and acceptance criteria

There is no defensible single “2× more enemies” number from this audit. The measured isolated 3× aggregate CPU reduction did **not** translate into a faster actual serial game. The strongest defensible numbers are mechanism-specific: 4.4–5.3× stable decode speed but only about 3–5% improvement in whole-worker elapsed duration at 1,500–3,000 in the actual reuse experiment, about 3.8× target-search speed at 5,000 in the tested distribution, the measured client-loop budget, actual packing CPU, and bytes selected per client. Do not multiply these ratios together.

For a 60 FPS target, 16.67 ms is the whole-frame budget. Allocate a provisional 2–4 ms to visible-enemy client script, leave substantial room for engine animation/rendering and late-game effects, and judge p95/p99 rather than average FPS. This is an engineering budget, not a measured guarantee on mobile. A 30 FPS tier has 33.3 ms total, but still needs bounded spikes and memory.

Before raising the production cap, run actual assets at 500/1,500/3,000/5,000, dense and sparse layouts, realistic camera distance, all animation enabled versus normal LOD, mixed ground/flying/charm archetypes, max AoE/proc builds, repeated mass death/respawn, camera re-entry, freeze/slow-mo, and multiple clients. Use repeated alternating controls, adaptive settle windows, recorded viewport/focus/cap/device, and a long steady-state run to expose GC/memory growth. A development desktop stress scene can establish a regression boundary; device-tier measurements establish a shipping cap.

## Workspace and Studio cleanup

The audit adds only this artifact directory. No tracked production source changes, commits, published assets, saved player settings or live-server changes were made. Four temporarily instrumented Survivors ModuleScripts were restored from exact pre-edit Studio backups, with a source comparison before overwrite. Temporary server/client probe Instances and the unsuccessful temporary Actor binder were removed. The earlier lobby probe was removed as well. Rojo connections were preserved.

The Gamebeast SDK nil-iteration error and generated Network native-compilation warning occurred during normal startup; they are recorded as observed limitations, not attributed as the cause of the measured enemy costs. The standalone probe's initial Actor binding error was an instrumentation error, corrected before the reported game runs.

## Public references checked during this audit

- [Roblox Actor API](https://create.roblox.com/docs/reference/engine/classes/Actor): Actor isolation, asynchronous messaging and cross-VM argument copies.
- [Parallel Luau](https://create.roblox.com/docs/scripting/multithreading): serial/parallel boundaries and SharedTable communication.
- [UnreliableRemoteEvent](https://create.roblox.com/docs/reference/engine/classes/UnreliableRemoteEvent): lossy/unordered delivery and 1,000-byte payload limit; encoded/compressed buffer size must be verified.
- [Roblox performance guidance](https://create.roblox.com/docs/performance-optimization/improve): client-owned NPC animation, size/scale invalidation and render instancing constraints. These support the architectural direction; local measurements determine its practical benefit.

