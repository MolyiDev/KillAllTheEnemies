# Ballarc enemy replication results - 2026-10-29

Baseline HEAD is `485570d`. The retained changes are uncommitted in `src/` and were synced to the Survivors Studio (place **137835287157016**) through Rojo. Nothing was published. Studio probes and timing hooks were removed afterwards, and Studio's copies were checked against disk.

## The "1k enemies but ~20 on screen" report

It was not packet loss. Every enemy lifecycle event (`Added`, `Killed`, `KilledMultiple`, `Removed`) is Reliable and arrives in order.

- **What the debug number counts.** It counts every enemy the client has an entity for, which is every enemy AOI ever subscribed the player to. Subscriptions stay until the enemy dies or is recycled, so an enemy that leaves the view stays counted, parked far away and hidden. The spin scene shows it: after a camera turn the client holds **all 8,000** enemies while only part of the crowd is on screen. Killing what is in front of you leaves the rest counted.
- **Network lag made it worse.** At ~330 KB/s on a Reliable RemoteEvent, Roblox queues the backlog instead of dropping it. Position packets arriving more than 1 s late make on-screen enemies hide as stale while they are still counted.

Two real bugs were found and fixed:

1. **Ghost enemies (`EnemiesService.Kill` / `KillMultiple`).** Subscribers were popped, then `Killed` was only sent if the killer had an `InstanceId`. A kill with no killer id (for example a damage-over-time effect whose owner's character is gone) left a ghost on every subscribed client forever. The event now always goes out, with killer id 0 like the explode path.
2. **Live enemies deleted on id wrap (`EnemiesService.Spawn`).** Ids run 30000-65535 and wrap. After the wrap, `Spawn` removed whatever living enemy still held the next id, with no kill credit. At 8,000 alive that is about 1 in 4 spawns once the counter wraps. Spawn now skips ids still in use and only evicts if every id is taken.

## Method

- Survivors place, F5 playtest, single client, Studio focused with a 240 FPS cap, viewport 1919x1080. Same development machine as the 10-22 runs (not re-verified this session). Server and client share the machine, so heavy server work also shows up in client frame times.
- **8,000 enemies** around an anchored, invulnerable character with weapons and progression held. Fixed third-person camera, FOV 90, default 400-stud render distance and 100-stud animation distance.
- Four scenes, each 6 s settle then 10 s capture:
  - **ground:** Slimes spread by area over 20-320 studs. They pile onto the player by the end, so most rows are near by then.
  - **mixed:** half Bees, half of all enemies charmed. Charmed enemies fight each other, which is a heavy main-thread combat load created by the scene itself.
  - **spin:** the ground layout with the camera turning 45°/s, so enemies keep entering and leaving view.
  - **spread:** Slimes over 100-500 studs. About 60% stay beyond 150 studs for the whole capture, which is closest to a real wave arriving from a distance.
- Every arm ran **twice, in opposite order** (pass 1 base→all, pass 2 all→base). Repeats agree within a few percent. Runs where Studio lost focus are excluded (one final ground run, one final spread run).
- **Exactness check after every scene.** The server froze enemies and sent every position it had sent to the player in the last 0.5 s, and the client compared them with what it had decoded. **0 mismatches** in every run (about 4,300-4,900 positions per scene), with max error 0.025 studs, the quantization limit.
- **Smoke checks** on the final code: TimeStop freeze/resume on both peers, manual pause/resume, camera hide and re-enter, restart cleanup. All passed.
- "Commit ms/s" times the main-thread worker-result commit. In arms without D it also includes packing and sending; with D (and in the final code), sending runs in a separate per-frame flush that isn't in this column.
- Network numbers: `kBps` is the position packet bytes the server sent. `Stats.DataSendKbps` on the server (wire level, after Roblox compression) tracks it at about 0.9x and is listed as "wire". `Stats.DataReceiveKbps` reads 0 on the Studio client, so client wire numbers are not available.

## Results per change

Each number is the mean of the valid runs. **Base** = all six changes off (same behaviour as HEAD). A→B→C→D were added on top of each other, so each row shows what that change added. E and F were also measured on their own. Lower is better except FPS.

### Ground (8,000 Slimes)

| Arm | FPS | Median frame ms | Client enemy update ms | Position KB/s | Wire KB/s | Worker CPU ms/s | Commit ms/s |
| --- | --- | --- | --- | --- | --- | --- | --- |
| base | 68 | 12.9 | 5.7 | 355 | 322 | 1660 | 93 |
| +A | 68 | 13.0 | 5.6 | 195 | 170 | 1604 | 92 |
| +B | 76 | 11.6 | 4.5 | 197 | 174 | 1631 | 94 |
| +C | 75 | 11.6 | 4.6 | 131 | 117 | 1652 | 96 |
| +D | 78 | 11.3 | 4.4 | 127 | 116 | 1656 | 88 |
| E alone | 68 | 13.0 | 5.7 | 317 | 283 | 1557 | 83 |
| F alone | 67 | 13.0 | 5.6 | 347 | 310 | 1657 | 91 |
| **final (A-E)** | 72 | 12.4 | 4.9 | 135 | 128 | 1623 | 80 |

### Mixed (8,000, half Bees, half charmed)

| Arm | FPS | Median frame ms | Client enemy update ms | Position KB/s | Wire KB/s | Packets/s | Server main thread ms/frame |
| --- | --- | --- | --- | --- | --- | --- | --- |
| base | 44 | 16.3 | 6.6 | 327 | 278 | 36 | 9.6 |
| +A | 44 | 16.2 | 6.5 | 160 | 134 | 36 | 9.7 |
| +B | 49 | 14.1 | 4.4 | 164 | 131 | 37 | 8.6 |
| +C | 49 | 14.1 | 4.4 | 109 | 87 | 38 | 8.7 |
| +D | 50 | 13.9 | 4.3 | 105 | 88 | 9 | 8.7 |
| E alone | 45 | 16.0 | 6.5 | 304 | 255 | 36 | 9.3 |
| F alone | 43 | 16.5 | 6.6 | 322 | 277 | 36 | 9.7 |
| **final (A-E)** | 50 | 13.8 | 4.4 | 105 | 87 | 9 | 8.7 |

### Spin (camera turning) and spread (wave mostly far)

| Scene / arm | FPS | Client update ms | Position KB/s | Wire KB/s | Worker CPU ms/s | Commit ms/s | Server main ms/frame | Client resident | Added + Removed /s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| spin base | 63 | 6.3 | 343 | 310 | 1600 | 91 | 3.7 | 8,000 | 0 |
| spin E | 63 | 6.4 | 314 | 273 | 1571 | 84 | 3.6 | 8,000 | 0 |
| spin F | 61 | 6.4 | 347 | 310 | 1591 | 91 | 4.0 | 7,581 | **1,348** |
| **spin final** | 70 | 5.1 | 127 | 116 | 1583 | 81 | 3.3 | 8,000 | 0 |
| spread base | 74 | 4.6 | 292 | 261 | 1323 | 104 | 2.9 | 4,454 | 148 |
| spread A | 76 | 4.3 | 112 | 97 | 1312 | 106 | 2.7 | 4,414 | 155 |
| spread E | 78 | 4.5 | 196 | 170 | 1170 | 81 | 2.6 | 4,450 | 156 |
| spread F | 74 | 4.7 | 288 | 256 | 1281 | 104 | 2.8 | 4,416 | 157 |
| **spread final** | **94** | **2.5** | **73** | **64** | 1214 | 83 | **2.2** | 4,403 | 158 |

## What each change gives, what it costs, and the verdict

### A - Send far enemies less often - **keep**

- **What it does:** within 60 studs of the camera, every movement tick (10 Hz). From 60 to 150 studs, every other tick (5 Hz). Beyond 150, every fourth tick (2.5 Hz). Only enemies the player is subscribed to are sent; the rest have no client entity yet and `Added` carries their position anyway.
- **Gives:** position traffic **−45% on ground, −51% on mixed, −62% on spread**. Wire level on spread: 261 → 97 KB/s.
- **Costs:** about +2 ms of server packing CPU per second per player, nothing measurable on frames. Far enemies update every 0.4 s instead of 0.1 s, which B makes look intentional. The longest gap (0.4 s) stays well under the client's 1 s stale timeout.
- **Opinion:** biggest bandwidth win for almost no cost. Keep.

### B - Far enemies jump instead of sliding - **keep**

- **What it does:** past 150 studs from the camera, the client places an enemy directly on each new position and skips it entirely until the next packet. Nearer enemies still interpolate. It is skipped while enemies are frozen, so TimeStop can't make a far enemy jump. That case was a bug in the first version, caught by the smoke test.
- **Gives:** client enemy update **5.6 → 4.5 ms on ground, 6.5 → 4.4 ms on mixed, 6.3 → 5.1 ms on spin**. **+8 to +12% FPS.** This is the main client win.
- **Costs:** far enemies move in small visible steps 2.5 times a second. At 150+ studs that is a few pixels. Animations already stop past 100 studs, so nothing else changes.
- **Opinion:** keep. If the stepping bothers you in play, raise the 150-stud threshold (`FAR_SNAP_DISTANCE_SQ` in EnemiesController, and the matching tier in EnemyPacker) rather than dropping it.

### C - Send moves as small offsets - **keep**

- **What it does:** after one full position (8 bytes), a player receives each enemy as a 5-byte record (id + three 1-byte offsets from the last position sent). If an offset doesn't fit, it sends a full position again. Both ends keep the "last position sent" only inside the position stream itself: the server per player, the client in one 393 KB buffer. Blink lifecycle events, which arrive on a different remote, can therefore never desync it. A cut-off packet is rejected whole.
- **Gives:** **8.0 → 5.3 bytes per enemy, about −33% more on top of A** (ground 197 → 131 KB/s, mixed 164 → 109 KB/s).
- **Costs:** 393 KB of memory per player on the server and once on the client. The client handler moved from `ConnectParallel` to `Connect`, because offsets must be applied in arrival order; the unpack is under 0.1 ms. Correctness depends on the RemoteEvent staying Reliable, so this format can't move to `UnreliableRemoteEvent`. It held up: 254k randomized records offline and every live exactness check matched.
- **Opinion:** keep. A plus C bring 8,000 enemies from ~330 to ~110-130 KB/s.

### D - One packet per player per frame - **keep**

- **What it does:** the four movement categories plus the stationary pulse used to send separately. Now their rows are queued and sent once per Heartbeat.
- **Gives:** **mixed 36 → 9 packets/s** (fewer `FireClient` calls and per-message overhead) and a few percent fewer bytes. The commit column also drops about 10%, but that's mostly the send moving out of the timed actor callback into the per-frame flush. It's not real saved work; packing time itself is unchanged.
- **Costs:** positions can leave up to one server frame (~16 ms) later.
- **Opinion:** small but free. It also centralizes the code: the 6 copy-pasted per-player loops are now one `AOIService.SendPositions`. Keep.

### E - Simulate far enemies at half rate - **keep, expect a modest gain**

- **What it does:** ground and flying enemies more than 150 studs from every player step on alternate ticks with twice the step time. Charmed enemies are untouched.
- **Gives (spread, the realistic wave):** worker CPU **−12%**, commit time **−22%**, position bytes **−33%** on its own, server main thread **−10%**, +5% FPS. On ground it gives worker −6% and commit −11%, because the slimes are near by mid-capture. On mixed only −3%, because charmed enemies, not covered, dominate there.
- **Costs:** far enemies move in 0.2 s physics steps. Collision pushes and terrain climbing are slightly coarser for them, but they are 150+ studs away and B already shows them at 2.5 Hz.
- **Opinion:** keep. It is the only change that cuts the server's real cost, the movement workers. It's a modest cut because movement near the player can't be skipped. See "Server CPU" below.

### F - Drop enemies that stay off screen - **rejected, removed**

- **What it did:** unsubscribed enemies a player hadn't been sent for 3 s (keeping anything within 60 studs) and told the client to remove them.
- **Gives:** with a fixed camera, nothing (0-3 releases per second). On spin, resident enemies only dropped **8,000 → 7,581 (−5%)**.
- **Costs:** on spin, **~700 `Added` + ~640 `Removed` per second**. Turning the camera brings released enemies straight back, so the client pays rig attach and detach and extra bytes for no frame gain (FPS 63 → 61).
- **Opinion:** don't add it. It would only make the debug count look nicer. The archived version is `held/AOIService-with-F-release.patch`; a much longer release delay (tens of seconds) would be the only variant worth retrying.

## Combined effect (final code: bug fixes + A, B, C, D, E)

| Scene | FPS | Client enemy update | Position bytes | Wire send | Server main thread |
| --- | --- | --- | --- | --- | --- |
| ground | 68 → 72 | 5.7 → 4.9 ms | 355 → 135 KB/s (−62%) | 322 → 128 KB/s | 3.4 → 3.3 ms |
| mixed | 44 → 50 | 6.6 → 4.4 ms | 327 → 105 KB/s (−68%) | 278 → 87 KB/s | 9.6 → 8.7 ms |
| spin | 63 → 70 | 6.3 → 5.1 ms | 343 → 127 KB/s (−63%) | 310 → 116 KB/s | 3.7 → 3.3 ms |
| spread | 74 → 94 | 4.6 → 2.5 ms | 292 → 73 KB/s (−75%) | 261 → 64 KB/s | 2.9 → 2.2 ms |

The final ground run (72 FPS) is a little under the earlier A-D arms (76-78). Only one valid final ground run exists, and run-to-run spread on that scene is ~3 FPS, so treat ground as roughly +5-15%.

## Server CPU: what this did and did not fix

- Replication itself was never the server's big cost. Packing positions for one player is ~4-8 ms of CPU per second, and committing worker results ~80-100 ms/s. **The movement workers are: 1.2-1.7 s of CPU per second on ground/spread and ~3.9 s on mixed**, which is 1-4 cores' worth at 8,000 enemies. On a Roblox server with fewer cores than this dev machine, that is where it struggles.
- **Correction:** an earlier version of this section blamed charm damage for the mixed scene's heavier main thread. In these runs the probe added the Charmed tag without an inflictor, so charmed enemies never dealt damage. The extra cost was the Bees' wide separation search competing for CPU. The follow-up below measures both causes properly.
- Two follow-up fixes (next section) cut the Bee simulation cost and the charm damage load. What remains: cheaper separation for big ground piles (nearest-K or lower rate) and extending E to medium distances. Both change how crowds move, so they need a design call.
- Bandwidth does scale with players. Packing time and bytes are per player, so 8 players at base would be ~2.6 MB/s of position data from the server. A-D cut that by about two thirds.

## Follow-up: Bee separation (fix 1) and charm contact batching (fix 2) - both **keep**

Same method as above, with three new scenes, two runs per arm in opposite order. The charm setup now matches the Charm pickup (`DebuffInflictor` = the grabber), so charmed hits deal real damage. Exactness: 120,855 positions checked, 0 mismatches. Smoke checks all pass.

- **bees:** 8,000 Bees, none charmed.
- **charm:** 8,000 Slimes, half charmed.
- **mixed:** half Bees, a quarter charmed.

| Scene / arm | FPS | Median frame ms | p95 frame ms | Server main ms/frame | Server main p95 | Worker CPU ms/s | Damage events/s |
| --- | --- | --- | --- | --- | --- | --- | --- |
| bees, neither | 48 | 16.3 | 44.9 | 8.2 | 16.5 | 4,171 | 0 |
| bees, fix 1 | **58** | 15.9 | **27.7** | **4.3** | **7.0** | **1,777** | 0 |
| charm, neither | 43 | 21.2 | 36.3 | 6.2 | 6.8 | 1,974 | 7,001 |
| charm, fix 2 | **53** | **16.4** | **31.0** | 5.7 | 6.4 | 2,157 | **24** |
| mixed, neither | 39 | 23.2 | 46.1 | 11.2 | 12.7 | 3,922 | 4,516 |
| mixed, fix 1 | 40 | 19.6 | 44.2 | 10.0 | 11.3 | 3,392 | 4,443 |
| mixed, fix 2 | 44 | 16.5 | 48.6 | 9.9 | 11.2 | 3,840 | 19 |
| **mixed, both** | **46** | **16.7** | **44.8** | **9.0** | **10.0** | **3,360** | **19** |

(The single valid charm/fix 1 run, 42 FPS, matches "neither": fix 1 only touches flying enemies.)

### Fix 1 - Bees search only as far as a push can reach

- **What it does:** the flying and charmed-flying workers searched 18 studs for neighbours, but a push only happens within the Bee's size plus the neighbour's half-size. The search radius is now `min(18, radius + largest enemy half-size)`. The largest half-size comes from every enemy's base model at load (`EnemiesService.GetMaxEnemyHalfExtent`). Server records are always base-model sized, so it bounds every neighbour.
- **Gives (bees):** worker CPU **−57%**, server main thread **8.2 → 4.3 ms/frame** (p95 16.5 → 7.0), **FPS 48 → 58**, p95 frame 45 → 28 ms. Part of the main-thread gain is less CPU contention from the workers.
- **Costs:** nothing in behaviour. The Lune check (`separation/`) found identical pushing neighbours and identical pushes for 20,000 Bees over 414,660 neighbour pairs, with mixed sizes and the largest present.
- **Opinion:** keep. It removes wasted work, nothing else.

### Fix 2 - Charm contact hits go out in one batch per frame

- **What it does:** each charmed contact used to run `EnemiesService.Damage` immediately and send one `Damaged` event. Now `EnemiesService.QueueContactDamage` collects the hits, grouped by who charmed them and by damage value, and flushes them once per Heartbeat through `DamageMultiple`. That sends one `DamagedMultiple` per player. A target hit by several charmers in a frame goes out once per round, so it still takes every hit.
- **Gives (charm):** damage events **7,001 → 24 per second**, **FPS 43 → 53**, median frame **21.2 → 16.4 ms**. Most of the FPS gain is on the client: it no longer handles thousands of single hit events, each with its own lookup and hit sound. Server main thread 6.2 → 5.7 ms.
- **Costs:** hits land up to one frame later. Floating numbers and the per-enemy hit-effect limit are the same as before, but the hit sound now plays once per batch (nearest hit) instead of once per hit, so a big charm fight is quieter. Damage totals, kills and credit are unchanged. Worker CPU reads ~9% higher in the charm scene. That's likely the movement ticks keeping their 10 Hz pace now the main thread is freer, not extra work per tick.
- **Opinion:** keep. The Charm pickup can charm a big chunk of an 8,000 crowd, so this load is realistic.

## Limits

Single client in Studio on a strong desktop, server and client on one machine. No multiplayer, no mobile, no real weapons or procs. Each arm had two runs. Differences of 1-3 FPS are within noise; the bandwidth numbers are very stable (±3%).

## Files

- `harness.py`: flips the per-change flags used during testing (`flags A,B,...`), and adds or strips the tagged timing hooks (`instrument` / `strip`). The final source no longer has the flags, so `flags` only works on the tested revision.
- `bench.*.luau` (ground/mixed + smoke), `bench2.*.luau` (spin/spread): temporary probes. Never publish.
- `run.py` / `run2.py`: run one arm through Tripwire (`tw.py`) and save `raw-<label>.json`. `batch.sh` / `batch2.sh` run all arms in both orders.
- `analyze.py` → `summary.md` / `summary.json`.
- `delta-check.sh` + `delta-check.luau`: Lune round trip of the final EnemyPacker (random moves, big jumps, coordinate wrap, unsubscribes, duplicates, cut-off packet).
- `raw-shake*.json` and `raw-check-base.json` are shakedown runs from fixing the harness (SharedTable keys, the exactness filter, the camera test). Don't cite them.
- `held/AOIService-with-F-release.patch`: the rejected F.
- `bench3.*.luau`, `run3.py`, `batch3.sh`: the fix 1 / fix 2 runs (bees, charm, mixed). `harness.py variant fix1,fix2` swaps the old lines in and out (exact whole-line swaps; `strip` never touches them).
- `separation/run-separation-check.sh`: Lune proof that fix 1 keeps the Bee pushes identical.
- `raw-s3shake-*.json`: probe shakedowns. In `s3shake-1` the charmed enemies had no inflictor, so it shows no charm damage.
