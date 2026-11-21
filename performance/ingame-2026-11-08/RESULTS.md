# In-game client results - 2026-11-08

Baseline HEAD is `b57c902`. The changes are uncommitted in `src/`, synced to the Survivors Studio (place
137835287157016) through Rojo. Nothing was published. `run.py` injects the two probes (`bench.server.luau`,
`bench.client.luau`) into the edit DataModel, runs an F5 playtest and deletes them again; the timing lines added to
`MinimapUI` and `pixelMotion` for a run were removed afterwards.

## Where the phone's frame went

Samsung A13 capture `microprofile-20261108-225605` (heavy fight, 48 ms frames), game thread (Worker C), per frame:

| Cost | ms | Notes |
| --- | --- | --- |
| UI layout (`Render::UpdateUILayouts`) | 5.75 | 6.9 layout roots a frame |
| Animators (`AnimatorParallelManager::stepAll`) | 3.66 | plus `IkControlManager::update` 0.37 ms, 379 calls: one per stepping Animator |
| Minimap `EdgeShimmer` | 2.15 | |
| pixelMotion springs | 1.88 | filed under `Script_PropsController`: the connection runs in the thread of whoever woke it first |
| `ClientUpdate` (EnemiesController) | 1.84 | |
| ConsoleController loop | 0.89 | plus all 0.69 ms of `attemptLocalization`. Only accounts with console access run it |
| CullJob (worker threads) | ~7 | split over Workers A, B, D |

Studio's frame time can't show any of this: the client sits on the 240 FPS cap (RTX 4060), the cap can't be lifted
from a script, and `Stats` render values can't be read. So each system is timed directly, and the PC-to-A13 ratio is
taken from the two systems measured both ways: animators 0.18 ms -> 3.66 ms and shimmer 0.046 ms -> 2.15 ms, both
about 20-47x.

## Method

F5 playtest, one client, 1919x1080, default camera (13-14 studs from the character). The server holds the run
(no waves, weapons held, character anchored with GodMode) and, per arm, clears and respawns the same seeded crowd:
Slime, Skeleton, Fungus and Bee in equal shares, 15-160 studs round the character. 3 s settle, 6 s capture. Arms run
forward then backward in one playtest; the repeats agree within 0.01 ms.

- **Animation step:** client time from `RunService.PreAnimation` to `PreSimulation`. With nothing animated it is a
  0.20 ms floor; the rest is the Animators.
- **Shimmer and springs:** `os.clock` around the `EdgeShimmer` loop and pixelMotion's `stepAll`, per stepper.

## 1. Animate only the nearest enemies (`EnemiesController`)

The phone already defaults to a 50-stud animation distance, and still stepped 344-409 Animators: a swarm packs hundreds
inside any distance. Now, past 60 playing tracks the animated radius shrinks (one rescale by `60 / count`, since the
count grows with the radius squared) and grows back by 10% a frame once under 45, up to the setting.

1,500 enemies, 718-734 on screen:

| Arm | Animated | Animation step ms | Animator share ms |
| --- | --- | --- | --- |
| distance 100, before | 667-673 | 0.38 | 0.18 |
| distance 40, before | 366-371 | 0.30 | 0.10 |
| distance 0 | 0 | 0.20 | 0 |
| **distance 100, cap** | **55** | **0.22** | **0.02** |
| **distance 50, cap** | **55** | **0.22** | **0.02** |

-88% on the Animator share. On the A13 that is about 3.7 -> 0.5 ms, and the per-Animator IK update shrinks with it.
Looks: past the nearest 60, enemies hold their rest pose while they move, which is the other game's look. The
start/stop edge sits nearer the player in a big swarm.

### The limit is a setting (Visuals > Animated Enemies)

0-1000 in steps of 10, saved like the other visual settings (`ESettingsVisual.MaxAnimatedEnemies`, a new `f32` in
`VisualSettings`, Blink regenerated). The server's default is 100 on PC and console and 50 on touch. 0 animates
nothing. Old saves have no value and get the default, so no migration. Run `setting`, 1,500 enemies, PC: the join value
read 100, and limits of 50 / 100 / 1000 / 0 held at 48 / 93 / 992 / 0 animated.

## 2. Minimap shimmer redraws a quarter of the edge cells a frame (`MinimapUI`)

The shimmer's sine has a 5.2 s period (1.2 rad/s), so redrawing each fog-edge cell every fourth frame moves the same.
Cells go by `index % 4`, so neighbouring cells are spread over the four frames. Exploring three strips across the map
first left 80 edge cells:

| Arm | Shimmer ms/frame |
| --- | --- |
| before | 0.046 |
| **sliced** | **0.014** (-70%) |
| minimap animations off | 0 |

On the A13 that is about 2.15 -> 0.65 ms.

## 3. One border wall per run of same-height cells (`GeneratorController`)

Every border cell was its own tall black Part. Now a row's run of border cells at one height is one Part covering the
same space. The template is plain black Plastic with no children, so the walls look the same. On one map, **500
border walls -> 264** (-47%). Border heights follow the terrain (32 different heights on that map), so merging rows
together would not gain much more.

That map had about 2,240 parts: scenery Props 890-970, Blocks 364-368, Fills 170-283, InteractableProps 154-168,
Slopes 32-36 and Borders. So this is about a tenth of the parts. CullJob time can't be read in Studio; the next
phone capture will show it.

## Measured, not changed

- **pixelMotion springs**: 0.08-0.11 ms a frame on PC in a fight, so the phone's 1.88 ms. The top steppers are
  `rewardCard:800`, `SelfStatsUI:335` (souls roll, chip thumps, the fire drawn every frame while it burns),
  `levelBar:615`, `runClock:586` (the bonus motes and breathing keep it awake for the whole run) and `pixelCursor:389`.
  Each is a designed effect, so cutting it changes how it looks; it needs a call per effect.
- **UI layout, 5.75 ms**: can't be measured from a script. The springs above write Size/Position every frame and each
  write invalidates its layout root, so they are the first suspect.
- **Scenery props**: about 900 MeshParts, the biggest part group for culling. Server-built.
- **ConsoleController**: 1.6 ms a frame on the phone (loop plus localization), for console-access accounts only.

## Files

`run.py LABEL 'ARMS_JSON' COUNT` runs one bench (`raw-LABEL.json`), `show.py LABEL...` prints the arms. Raw runs:
`anim-p2` (distance, before), `cap-p1` (cap), `shim-base` / `shim-slice`, `census2` / `census3` (parts, after the
merge), `fight` (springs).
