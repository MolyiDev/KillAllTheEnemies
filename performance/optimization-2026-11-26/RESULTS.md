# Optimization loop - 2026-11-26

Baseline HEAD is `737641f`, plus another session's uncommitted loading-screen work (MatchService, MatchController,
LobbyController, LobbyService, DefaultRobloxUI, UI.md), which this work did not touch. Nothing was published. Round 1
is offline only: **ree 0.7.0** (Luau and engine calls priced as a Studio desktop client, `os.clock` and
`Context.WorkSeconds()` on its work clock), **rur-native 0.8.0** (host time of a story's Luau) and **ror 0.6.0** for the
looks; rounds 2-4 add F5 playtests in the Game Studio (Animator step, UI census); rounds 5-6 could not be playtested
(another session's loading screen held the client) and say so. How far each tool matches Studio is at the end.

**Keeping it**: the rules that hold this performance are in CLAUDE.md ("Enemies and navigation", "What a client draws",
"UI and the top bar", Tooling's "Performance benches") and VFX.md section 5; re-run a harness here after touching the
code it measures.

The harnesses are in `harness/`. Server ones mount the Game place's trees through `harness/mounts.sh`; client-utils
ones run through `harness/runfx.sh`, which stands an older copy of the module in for a before/after.

## Kept

| Change | Where | Before | After | Tool | Same result how |
| --- | --- | --- | --- | --- | --- |
| A boss no longer widens every crowd collision query | `SpatialHash` (large set) | 0.89 ms / 10 Hz tick with a boss record, 0.63 without | 0.65 with, 0.63 without | ree, `server_tick_boss.luau` | `hash_check.luau`: 2,400 `QueryRadius` / `QueryAABB` against brute force over crowds, large boxes and circles, adds, moves and removes: 0 mismatches, no duplicates. `sim.luau` behaviour lines identical |
| Shots drop bodies off the shot's line before reading them | `WeaponService.gatherBodies` | SMG 32.3, shotgun 293.6, piercing sniper 37.2 us/shot | 27.6 / 237.0 / 16.3 | ree, `gather.luau` (255 real enemies, 400 shots each) | the hit lists (every pellet, every body, in order) are identical; `guns.luau` output identical |
| A piercing pellet walks the bodies once | `GunsCore.CastBodiesAll`, `WeaponService`, `WeaponController.castLine` | shotgun (pierce 4) 237.0, sniper (pierce 10) 16.3 us/shot | 77.3 / 11.3 (**-74% / -70% overall**) | ree, `gather.luau` | identical hit lists; the aim ray (pierce 0, every frame) keeps the plain `CastBodies` |
| Sparks stretch through a Brick SpecialMesh, not `Part.Size` | `tracers` | 0.488 ms/frame (4 SMG players) | 0.306 (-37%) | ree, `tracers_real.luau`; per write 1.93 us Size vs 0.36 us Scale (`sparks.luau`) | the game already stretches rotated parts this way (`motorParts`, gun streaks); see ror below |
| The HUD's breathing cards get their own clock | `HudController` (`state.Breath`), `Items`, `Shop`, `Hud.story` | heartbeat 0.51 ms/frame with the nuke prompted | 0.22 (-57%) | rur, `Hud.story` with the nuke prompted, Now ticking vs only Breath | rur renders at 1.5 s and 1.8 s: before and after pixel-identical, the card breathes and sheens in both |
| Springs heading back to 0 settle | `Hotbar` presence, `Wave` knob, `Squad` hovers, `Results` hover, `Overlays` card (now `Hand.Spring`) | rerunning readers every frame 20 s after going back to 0 | settled after 25 frames (0.4 s) | ree, `spring_settle.luau` | `Hand.Spring` only sets the spring's start point (its tolerance), never its position or speed |
| Inertial blends build fewer CFrames, skip finished joints | `inertialBlend.Step` | 0.234 ms/frame, 40 rigs x 7 joints | 0.231; ~130,000 fewer CFrame allocations a 10 s run | ree, `blend.luau` + `--profile alloc` | checksum of every joint's Transform every frame identical |
| Damage numbers write Rotation / transparency only on change | `DamageNumbersController` | 8.7 us/frame of unchanged writes at 48 popups | 0.3 | ree, `popup_writes.luau` (a stand-in) | only writes of the value already set are skipped |
| A warning's footprint reads the nav buffers itself | `TelegraphCore.Footprint` (server and client) | 0.82 ms for a 60-stud ring on a 44k-node map; 51.0 ms for 300 random warnings | 0.73 with the calls hoisted; read directly 32.6 ms for the 300 (-36%) | ree, `footprint.luau`, `footprint_check.luau` | the 300 footprints' node sets and floor heights identical to HEAD's; `sim.luau` telegraph lines identical |
| The console's spinner clock ticks only while a command runs | `ConsoleUI` (mounted for role holders: admins, and everybody in Studio) | 55.8 us/frame with its clock ticking, the console closed | 5.5 (the harness's own floor) | ree, `console_spinner.luau` (the pattern alone: ree cannot build the whole console, TextService returns nil at line 306 in both versions) | the label is shown only while `working()`, and reads the same seconds since the console was built |
| An arriving body is made transparent before it is parented | `EnemiesController.attachRig` | one skinned-mesh Transparency crossing off 0 per arrival (15-19 us in Studio, performance/06) | none | reasoned from performance/06; not re-measured | the loop writes the same fade on the first shown frame; rigs are never pooled |

## Round 2: the crowd tricks from Ballarc (animation distance, animation cap, far tiers)

Ballarc's `Survivors/Client/Controllers/Actor/EnemiesController` and `Survivors/Shared/Packers/EnemyPacker`, ported to
this game's controller (its clips are Idle + Walk + attacks, blended by `inertialBlend`, not one walk track):

- **Animation distance and cap** (`EnemiesController`, `Tune.ANIMATION_DISTANCE` / `MAX_ANIMATED`, Ballarc's device
  defaults: desktop 100 studs / 100 bodies, touch 50 / 50). Past the cap the radius is rescaled at once, and it grows
  back 10% a frame only under 75% of the cap. A body leaving it has its clips blended out into its mesh's rest pose
  (`holdStill`); one entering blends its Idle (and Walk) back in. A body that is not animated plays no attack clip
  (the snarl is still heard). Bosses and driven bodies always animate.
- **Held far bodies** are drawn on each packet's spot and skipped between packets (no clip rewrites their root).
- **Send tiers** (`EnemyPacker.PackFiltered`, per-player `sentAt` in `AOIService`): every tick inside 100 studs of the
  player's camera, every 0.15 s to 150, every 0.35 s past it, bosses always every tick (`OutEveryTick`). Real time, so
  a paused match keeps streaming.

Measured in Studio, F5, the Game place, god mode, ~230 mixed enemies spawned 30-100 studs round the player
(`harness/studio_animator_bench.py` drives it through the Tripwire daemon; the probe is
`harness/studio-animator-step.client.luau`, Ballarc's method: client time from `PreAnimation` to `PreSimulation`).
Studio sat at 60 FPS (unfocused), so frame time means nothing here; the Animator step is timed directly.

| | Bodies on screen | Bodies playing clips | Playing tracks | Animator step, median (p90) |
| --- | --- | --- | --- | --- |
| Before | 220-226 | 216-218 | 403-437 | 0.34 ms (0.41) |
| After (cap 100) | 221-230 | 92-99 | 181-204 | 0.24-0.26 ms (0.29-0.34) |

Ballarc's floor with nothing animated was 0.20 ms (performance/ingame-2026-11-08), so the enemies' share goes from
~0.14 to ~0.05 ms (-60%); on its A13 capture the same share was ~20x (3.66 ms for ~380 Animators). Screenshots:
`studio-crowd-capped.png` (no T-poses, nothing at the origin: the held bodies stand in their mesh's posture) and
`studio-crowd-near-and-far.png` (a crowd half 30-100, half 150-260 studs out). The magenta there is the last-few
outline (`markLast`), on because the test bodies were spawned outside a round; by reading only, not compared against HEAD.

The send tiers in ree (`harness/stream_tiers.luau`, the sim's crowd streamed for 10 s): with the camera among the
crowd nothing changes (22,970 bytes/s to one player, all within 100 studs); with the camera 60-230 studs off it,
**22,970 -> 5,742 bytes/s (-75%)** and the pack 8.3 -> 5.5 us a tick. `sim.luau`'s behaviour lines are identical.

What changes on screen: past the nearest 100 (50 on a phone), or past 100 studs (50), bodies slide in their rest
pose instead of walking; past 100 studs from the camera they move in steps of their packets (every 0.15 s to 150
studs, 0.35 s past it). Rojo stopped syncing twice during this round: the files were pushed through Tripwire and every
one of the 23 changed modules was compared with disk before the runs.

## Round 3: the graphics level, and the HUD split in three

- **The animation limits follow Roblox's graphics level** (the user: no settings rows; this is the norm, scaled by the
  player's graphics setting). `UserGameSettings.SavedQualityLevel` 1-10 scales the distance and the cap from 0.4x
  (level 1) to 1.6x (level 10), 1x in the middle, live as the slider moves. Automatic reads 0 to a script (DevForum:
  no API exposes the level Automatic picks), so it keeps the norm; `GraphicsQualityLevel` is tried in a pcall first.
  Whether it is readable was not confirmed: the playtest's output buffer had dropped the probe's line. Not measured
  (it moves the same limits as round 2).
- **The HUD is three ScreenGuis** (`HudController`'s `hudRoot`): `Hud` (-2: Upgrades, Abilities, Hotbar), `HudLive`
  (-1: Wave, Items, Down) and `HudTop` (0: Announce, the two upgrade flights, Squad, Results); the floating numbers
  moved -1 -> -3 to stay under all three. Pieces are still built in the old order, because each card's marks are drawn
  at random in build order (the first try reordered them and every frame differed by ~5,000 pixels of marks).
  - Same picture: `Hud.story` built both ways (one root; three layer frames, which paint as three DisplayOrders do)
    over 31 moments x 2 times, the nuke and heal prompted included: **62 of 62 pixel-identical** in rur. Down and
    Results are not in the story: their place in the order is reasoned (Down stays over the wave and a resting item and
    under a prompted one; Results stays over everything). During a boss intro's 0.5 s UI fade the three roots fade as
    three CanvasGroups, so where a live piece overlaps a calm one the fade may blend slightly differently.
  - Studio census in a fight with the nuke prompted (`harness/studio-hud-census.client.luau`, ~200 enemies):

    | | Root written every frame | Visible elements laid out again a frame |
    | --- | --- | --- |
    | Before (one `Hud`) | `Hud` (Items 299/300 frames, Wave 285-299) | ~340 |
    | After | `HudLive` 299/300; `Hud` 0/300; `HudTop` 1-3/300 | ~120 (-64%) |

    At runui-2026-11-09's ~1.15 us per visible element in a written root on the PC, about 0.39 -> 0.14 ms a frame on
    the PC; the phone pays several times that (its UI layout was the single biggest cost in Ballarc's A13 capture).
    `studio-hud-split.png`: the split HUD in game, every piece in place.
- **Ragdolls, measured, not changed**: 40 falling corpses (the cap) cost 0.081 ms a frame in ree, 2 us each
  (`harness/ragdoll_cost.luau`).

## Round 4: delta-encoded positions (Ballarc's stream)

`EnemyPacker`: a record is absolute (9 bytes: id, three u16, yaw) for a body with no send time, or one that moved 128
steps (6.35 studs) or more since its last record, else a delta (6 bytes: id, three i8, yaw). Both ends keep the last
position sent per id (`AOIService`'s per-player `sentQ`, `EnemiesController`'s `netBase`), written only by the
stream. Blink queues a reliable event until its listener connects and replays in order, so the client never misses a
record. The header is two counts now (4 bytes).

- Same positions: `harness/delta_roundtrip.luau`, 6,000 ticks of 255 bodies through the real packer and decoder with
  random walks, 30-stud jumps, bodies crossing the u16 wrap, AOI forgetting bodies, recycled ids, tiers and bosses:
  **695,956 records decoded, 0 mismatches**, 2.5% of them absolute. `sim.luau` identical but its one packet, 2 bytes
  longer for the second count.
- Bytes (`harness/stream_delta.luau`, the sim's crowd streamed for 10 s, HEAD's packer against this one): camera among
  the crowd **22,970 -> 15,416 bytes/s (-33%)**; camera 60-230 studs off it **22,970 -> 3,912 (-83%)**. The client's
  unpack is 20.0 -> 22.3 us a packet (the baseline reads and writes), ~0.02 ms a second at 10 Hz.
- Studio: a near-and-far crowd ran with no script error (`studio-crowd-delta.png`); the user was playing in that
  playtest. 130-133 bodies animated against a cap of 100 at Automatic: that Studio's graphics level was set by hand
  (8 scales the cap to 133), so the level is read.

## Round 5: the effects budget and the quality tiers (Ballarc's `ParticleHelper`, `fxLod`, `qualityDefaults`)

KATM's VFX.md section 5 described Ballarc's machinery (`fxRings`, `fxLod`, `ParticleHelper`) as if it were here; none
of it was, and every effect called `emitter:Emit` directly. Ported, with no setting rows (the user: the norm, moved by
the Roblox graphics level):

- **`GraphicsQualityController`** (global): the tier (levels 1-3 Low, 4-6 Medium, 7-10 High; Automatic is High on a PC,
  Medium on a phone, and drops a tier if the place cannot hold 45 fps over a 20 s window after a 10 s warmup, once,
  only down) and the scale (0.4 at level 1 to 1.6 at 10; Automatic 1, then 0.7 / 0.4 after a drop). `OnChanged` when
  either moves. EnemiesController's animation distance and cap and DamageNumbersController's reaches and per-frame caps
  read the scale; EnemiesController's render distance is Ballarc's device norm (PC 400, phone 150) times the scale,
  never past the server's 400, and a boss is always seen to 400.
- **`fxBudget.Emit(emitter, count, at?)`** (global util): every burst in CoinsController, nukeFx, burstLayers, goldFx,
  upgradeFx, healthUpFx, healFx, trexFx, stepFx, enemyImpacts and gunFx goes through it. Scaled by the tier (1 / 0.6 /
  0.35), thinned by distance from the camera's focus (High: half past 90 studs, none past 220 or behind the camera;
  Medium 70 / 170; Low 50 / 120 at 0.35), and spent from one estimate of the burst particles alive (700 / 300 / 180),
  past which a burst is thinned, never dropped. Ground warnings (`telegraphFx`) stay out: a warning is the hitbox.
- Measured in ree (`harness/fx_budget.luau`): a heavy fight's 300 bursts of 10 a second (60% within 60 studs of the
  focus, 25% 60-150, 15% far or behind):

  | | Particles drawn a second | Cost a burst |
  | --- | --- | --- |
  | Before (raw `Emit`) | 3,000 | 0.12 us |
  | High | 1,501 | 2.37 us |
  | Medium | 658 | 2.36 us |
  | Low | 368 | 2.31 us |

  The wrapper is ~0.01 ms a frame at that rate. On High the budget thins bursts close to the camera too once 700 are
  alive: Ballarc's numbers, kept as they are.
- Not playtested: the files are in the Game Studio (pushed through Tripwire, all 36 of this session's files checked
  against disk), but every playtest after them sat on another session's new loading screen ("GETTING READY 95%"),
  which now holds the client before any StarterPlayerScripts probe runs. The controller and `fxBudget` load and run in
  ree (the bench requires the real modules).

## Round 6: the rest of Ballarc, swept by two read-only agents (its docs and measurements; its code)

Most of Ballarc's client tricks were already here (view-cone parking with `Stop(0)`, unparented reserves, BulkMoveTo,
effect parts with no query, touch, collision or shadow, pooled sounds, the blur off once eased out, CanvasGroups only
while fading, closed screens' guis off, `--!native` on the hot modules). Ported now, none measured here (each rests on
Ballarc's phone capture; every playtest after round 5 stops on another session's loading screen):

- **Lighting by tier** (`GraphicsQualityController`, Ballarc's `qualityDefaults` OFF table): Medium turns the place's
  SunRays and DepthOfField off, Low also its Bloom and `GlobalShadows`; a higher tier puts back the place's own values.
  Only the effects the place has at start are touched (a boss intro's focus and the screens' blur are their owners').
  A phone on Automatic is Medium, so it loses SunRays and DepthOfField. Phones are GPU-bound in a fight (41.7 ms of
  GPU on Ballarc's A13 capture). `PrioritizeLightingQuality` is left on: it picks whether lighting or view distance
  scales down first on weak devices, it is not scriptable, and it carries the old place's look.
- **`AutoLocalize = false`** on the number labels rewritten most frames (the Gold counter and a pack's amount, the
  squad's kills, deaths and cash as they count up, the boss bar's percentages, the ultimate's charge, an ability's
  cooldown or price). Ballarc's A13 spent 0.69 ms a frame in `attemptLocalization` on one such label. Digits only:
  a label with words keeps auto-translation.
- **The floating numbers' ScreenGui is off while nothing shows** (Ballarc's `enableWhileShown`): a touch device walks
  every enabled ScreenGui each frame (1.26 ms over 116 calls on the A13).

Left, with why:
- Ambient HUD loops at 12 Hz and the floating numbers at 24 Hz: stepped motion in a smooth UI (the breathing card, the
  numbers' punch), and the HUD split already took most of the layout cost.
- The Mutation ScreenGui: something in it is shown through a fight (3 elements in the census), so it cannot go off.
- Big for phones, needing the user or a pass of their own: the maps' part counts and shadow casters (Ballarc merged
  border walls -47%, and bark under 0.8 studs casts no shadow); a UI overdraw audit (Ballarc's lobby: ~7 ms of A13
  GPU per full-screen layer, Shop Deals overdraw 8.07 -> 4.18 with strips for shadows and bezels); capping how much
  screen a big effect covers (Ballarc's ScreenRadiusMax and thinned blast runs), for overkill bursts, slams, the nuke
  and the orbital cannon.

## Finalize: a fresh review of the whole diff, and what it fixed

- **EnemiesController required `GraphicsQualityController` through `StarterPlayer`** while every other module uses
  `Players.LocalPlayer.PlayerScripts`: a second copy of the controller, with its own Lighting record and fps check. Fixed
  to the PlayerScripts path. Separately, the session had created the two new modules in Studio by hand while Rojo was
  not syncing; Rojo then added its own and the user hit Ignis's "already registered" in a playtest. Rojo removed the
  hand-made copies; `harness/studio_sync.py` no longer creates modules, and CLAUDE.md says why.
- **`fxBudget` could drop a one-particle flash** (a hit's flash, the nuke's bloom: the moment itself) on Low or over
  budget. A burst of one or two now always draws one while on screen; only distance can take it.
- **The server's near send band was 100 studs** while a client at graphics levels 7-10 animates out to 160: bodies there
  walked toward targets that came every 0.15 s. The bands are now 160 / 240. Bytes with the camera away from the crowd:
  22,970 -> 7,433 a second (-68%, was 3,912 with the narrow bands); among the crowd unchanged (15,416). Round trip
  again 0 mismatches over 1,070,005 records.
- **SpatialHash's two decoders built bounds without the large set**: latent (nothing calls them), fixed.
- `tools/lune/sim.luau` now streams six more ticks through one pair of baselines at its end (deltas, one 30-stud jump):
  1,564 bytes a packet, error 0.025 studs, the quantization. Its other lines are unchanged.
- Readability: one `isHudUp` for the three HUD roots, `fxBudget`'s distance share private, Automatic's scales indexed by
  tiers dropped, comments that named another game now cite the measurement, a stale story comment moved.
- Not changed: the three ways of testing for a boss (one `EnemiesCore.IsBoss` would be tidier), and callers of
  `fxBudget.Emit` that could pass their position instead of letting it read the emitter's parent (~2 us a burst).

## Measured, not changed

| What | Cost | Why not |
| --- | --- | --- |
| A flowfield flood (`NavService`) | 1.73 ms at 43,911 nodes (`flood.luau`); 6,784 nodes 0.3 ms | Already Dial's buckets. Up to 16 a second with 4 moving players (~3% of a server core, one a frame at most). Flooding only when the source moves more than a cell, or stopping the flood past the farthest enemy, changes what enemies path to: the user's call |
| The server tick's jecs iterator and sets (`enemiesUpdate`) | ~24 us of the 630 us tick (profile: `world_query_iter_next` + `world_set`) | Reading jecs columns directly couples the update to jecs internals for 4% |
| The client loop's jecs iterator and `set` (`EnemiesController`) | 14.7 vs 8.4 us/frame at 255 (`jecs_iter.luau`) | 6 us a frame, same coupling |
| A positional one-shot (`SoundsCore.PlayWorldSound`) | 4.8 us a call to start | ~0.01 ms a frame at 80 a second; a voice ring risks cutting tails. A cull past `RollOffMaxDistance` would rarely fire: casings and debris are Max 120, impacts 320 |
| Kill Gold sent per kill | one `Gold` event per body of a volley | ~100 small events on a nuke's frame; batching reorders Gold after Coins on the client |
| The Gold counter's `TextScaled` while it rolls (`Hotbar`) | one label re-fitted per changed frame | It is under an animated UIScale: a fixed TextSize is not provably the same picture at every HUD scale |
| The crowd collision query itself (`SpatialHash.QueryRadius`) | 75% of the 0.63 ms tick | Already inlined and same-module; 45 candidates and 20 neighbours a body in a packed crowd |

## Studio: who writes the UI (one F5 playtest, `harness/studio-ui-census.client.luau`)

The Game Studio (113327793187086), Rojo-synced with this round's changes (checked: `GunsCore.CastBodiesAll` was there),
god mode on, 199 mixed enemies spawned 40-100 studs round the player by `EnemiesService.Spawn` from `run_luau_live`. The
probe counted every UI property change for 600 frames twice (`raw-studio-ui-census.json`). **It did not catch a fight**:
the first window caught the run's end (Revive and Results animating), the second the restarted match's countdown with
no enemies. No script error in either playtest's log, only the known asset-permission lines. Frame 4.17-4.33 ms median
(the 240 FPS cap), p95 4.9-5.6, at 1919x1080.

| Root | Visible elements | Frames written of 600 | Top writers |
| --- | --- | --- | --- |
| `Hud` | 248 (run's end), 340 (countdown) | 359, 385 | health bars' Fill / Cut (191), the countdown's beat and number (167), the skip button's cooldown (151), the gun slot's Rotation / UIScale (86) |
| `Vignette` | 6 | 599 | its fade frame, 4 writes a frame |
| `OwnHealth` | 54 | 191 | the overhead bar |
| `Command Executor` (the console) | 0 | 255-257 | the spinner label's Text: fixed above |

So the HUD's ~250-340 visible elements are laid out again in about 60% of frames outside a fight too. Splitting the
`Hud` ScreenGui by how often each piece is written (the sweep's proposal: calm pieces, live pieces, a top layer for the
dims) is the remaining UI lever, and a structural one: three roots must keep today's paint order and `UiFade` group.
Not done; it needs a census of a real fight first (the probe, with the run kept alive).

## The maps (published place, Open Cloud Luau, read only)

| Map | Parts | MeshParts | Cast shadow | Non-colliding casters | Distinct looks | Biggest groups |
| --- | --- | --- | --- | --- | --- | --- |
| GrassLands | 9,490 | 65 | 7,667 (293 under 1 stud, 3,391 of 1-4) | 5,618 | 41 | Trees 4,021, Island 2,714, Foliage 1,701, Props 792 |
| PirateCove | 5,115 | 76 | 2,073 | 451 | 66 | Island 5,042 (plus 87 lights, 18 emitters, 172 semi-transparent parts) |

Every part is a culling and shadow-pass entry on every client. GrassLands' trees and foliage are brick builds: one
union or mesh per tree would keep the look and cut thousands of parts; shadows off on non-colliding decor would cut the
shadow pass but change the picture. Both are Studio work on the user's maps. Not done.

## The tools against Studio (what this round found)

- **ree** prices CFrame userdata as cheap: the blend change shows -1.5% on the work clock while its allocation profile
  drops ~10% of the run's CFrames. In Studio those are GC work ree does not run, so judge allocation-bound changes by
  `--profile alloc`, not the work clock.
- **ree** fires `PreAnimation` (VFX.md 25 said it never did, for ree 0.7.0 at the time): `inertialBlend`'s pending
  blends resolved without `Context.FireEvent`.
- **ree** in the client context waits forever on `JABBY_REMOTES` for anything requiring the ECS worlds: run jecs
  benches with `--run-context server`, or make the folder first as `Hud.story` does.
- **ror** draws a Brick SpecialMesh's `Scale` in the wrong axes once the part is pitched (yaw alone is right):
  `ror-mesh-axes.png`, red = `Part.Size`, blue = the same box through a SpecialMesh, at no rotation, yaw 45 and a
  look-at with pitch. The engine scales in the part's own axes (the game's `motorParts` and gun streaks rely on it).
- **rur**'s `timings.layout` is ~0.02 ms for the whole HUD: far below Studio's ~0.5 us per visible element. It ranks
  layout changes; it cannot size them.
