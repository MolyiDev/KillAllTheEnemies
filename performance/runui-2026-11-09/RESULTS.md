# Run UI layout results - 2026-11-09

Baseline HEAD is `b57c902`, plus the uncommitted work in `src/`, synced to the Survivors Studio (place 137835287157016)
through Rojo. Nothing was published. `run.py` injects the probes into the edit DataModel, runs an F5 playtest and
deletes them again (`CLIENT=bench.lab2.client.luau python3 run.py LABEL '[]'` for a lab probe).

## What UI layout is

`Render::UpdateUILayouts` is the engine working out every GuiObject's absolute position and size before drawing. The
public guidance (DevForum threads below) is: hidden or disabled UI can still be relaid out, AutomaticSize and tweening
force relayouts, and mostly-static and mostly-dynamic UI should sit in separate ScreenGuis so the dynamic part does not
invalidate the static part.

- https://devforum.roblox.com/t/large-performance-hit-from-updateuilayouts/2884226
- https://devforum.roblox.com/t/updateuilayouts-triggers-when-updated-ui-is-disabled-or-invisible-causing-unnecessary-processing/2881147
- https://devforum.roblox.com/t/static-ui-with-no-active-scripts-and-no-user-input-causes-20ms-updateuilayouts-every-frame-on-google-pixel-6a/2701280
- https://devforum.roblox.com/t/static-ui-performance-improvements/222557

## The phone (A13 capture 225605, heavy fight)

| Cost on Worker C, per frame | ms |
| --- | --- |
| `UpdateUILayouts` | 5.75 |
| of it `Layout`, 6.9 passes a frame | 4.97 (self 3.46, `Layout Viewport` 0.83, `Post-Layout Event Dispatch` 0.67) |
| `GuiLayerCollector::processDescendants` (touch input), 116 calls | 1.26 |

Each frame has two passes of 1.2-1.7 ms, one of about 0.9 ms and four of 0.2-0.4 ms. So a pass has a fixed cost of about
0.25 ms on the phone, whatever its size. The capture does not name the root a pass belongs to. The game thread was busy
about 37 ms of the 48 ms frame and the GPU 41.7 ms: the run is close to both limits.

## What a pass costs (PC lab, `bench.lab2.client.luau`)

Studio sits on the 240 FPS cap, so the lab burns 8 ms in every PreRender and the frame time then shows what each
synthetic tree adds when one thing in it is written every frame. 3-4 rounds each, alternating:

| Case | Added frame time |
| --- | --- |
| 2,000 visible static frames in another ScreenGui (drawing only) | +0.89 ms |
| the same 2,000 in the ScreenGui being written | **+2.31 ms** |
| the same, writing only a BackgroundTransparency | +2.33 ms |
| 2,000 hidden static frames in the ScreenGui being written | ~0 |
| written frame among 200 hidden siblings | ~0 |
| 30 ScreenGuis of one frame, all written | ~0 (noise ±50 us) |
| 300 visible frames in the written root vs in another root | +0.31 vs +0.15 ms |
| 300 fully transparent frames in the written root | +0.12 ms |

So: **any write in a ScreenGui makes the frame redo every visible element of that ScreenGui** (about 0.5 us each on
PC, transparent frames included), even a write that moves nothing. Hidden elements are free. A forced read
(`AbsolutePosition` after a write) shows a different cost, about 0.25 us per sibling of the written element, hidden ones
included, but that does not show up in the frame (the 200-hidden-siblings case), so it is not the frame's cost.

## Who writes the run's UI (`bench.client.luau`, `ui.py`)

Every property change on every gui, per frame, plus each gui's visible count at the start of the capture. A fight of
500 enemies 15-28 studs round the player, 433 kills in 12 s (`vis3`):

| Root written | Visible | Share of frames written | Main writers |
| --- | --- | --- | --- |
| TimerGui | 27 | 82% | clock digits' punch, sheen, rings, motes |
| SelfStatsGui | 52 | 40% | kill motes, the kills milestone sheen, chip thumps, the streak fire |
| CursorUI | 10 | 38% | the aim dot's rings and motes on hits and kills |
| MinimapUI | 73 | 6% | markers |
| DamageNumbers | live labels | every 24 Hz update | position and fade |

The clock's 82% and the countdown glow (`TimerBarUI`) are the bench's: a reward pick's countdown was left running, and
in pick mode the clock punches every second. In a plain run it punches on the minute and in the last 10 seconds.

The phone's capture had a reward choice open (`rewardCard` was its top stepper). In the bench the open card wrote its
sheen rows 12 times a frame and its motes and breathing rings every frame, into a root of about 100 visible elements,
so the reward screen is rebuilt every frame for as long as a choice is open.

## Changed

- **The objectives card's idle sheen is gone** (`QuestsUI`). Every 14 s a sheen crossed the card under the minimap; now
  only the next pip blinks. The sheen still plays when an altar is activated and when the NEW QUEST banner lands.
- **Closed screens turn their ScreenGui off** (`enableWhileShown`). A gui is on in the same frame its content turns
  Visible and off once it has stayed hidden for 2 s, so the close animation and its trailing puffs finish first. Wired:
  Info, Settings and its backdrop, Kick and its backdrop, Pause, Self revive, Restart radial (both), Dialogue, the side
  tutorial prompt, the reward screen (`AugmentGui`). Checked in a playtest (`sleep1`): all of them read off at rest,
  and the Info screen's trace was `-/-` x24, `Visible/Enabled` x590 (on in the same frame as the open), `hidden/Enabled`
  x480 (the 2 s linger after the close finished), then off. In the lab a disabled ScreenGui keeps its contents'
  AbsoluteSize and still updates it on a resize, so a screen built while off lays out right (`enable1`). Not wired:
  the upgrade screen, the confetti layer and the rarity impact keep their top frames shown when closed, so they have
  no one frame to follow.
- **Ambient loops step at 12 Hz** (`pixelMotion.AmbientHz`, `AmbientGate`), kept after a look at `Stories/Ambient`: the
  run clock's breath and bonus motes, the XP bar's charge or lock breath and motes, the reward card's breathing rings
  and motes, and every steady (drifting) mote of `pixelFx.Particles`. Sparks, rings, sheens, thumps and punches still
  move every frame. Rewriting an unchanged value costs nothing (`lab6`: same as no write), so the frames between steps
  write nothing. The story mounted in a playtest (`story1`, 240 FPS, 6 s): the every-frame side wrote on 1,440 of
  1,441 frames, the 12 Hz side on 354 (the rest is the card's sheen crossing every 3.2 s).

## Tried and reverted

- **Damage numbers without AutomaticSize.** 200 pooled labels sit in one ScreenGui, and a forced read there costs 51 us
  a write against 2 us elsewhere. A fixed-size box changed nothing (the cost is the 200 siblings, not AutomaticSize),
  and the frame lab shows hidden siblings cost nothing in the frame. Reverted.

## Trade-off to know: `pixelSlab` strips (lobby change)

The lobby's overdraw fix draws a slab's shadow, outline and bezel as strips, so a slab is 16 GuiObjects instead of 8.
In the run that is +8 elements per slab in every root that gets written (TimerGui has 1 slab, SelfStatsGui 2). In the
lab, 40 strip slabs in a written root added +343 us against +231 us for the old ones (noisy). The run is GPU-bound as
well (41.7 ms), and the strips cut GPU fill, so it is kept.

## Not changed

- The reward and upgrade cards' sheen every 3.2 s while a choice is open still rebuilds the choice screen for its 0.6 s.
- The aim dot's rings and motes are thrown by hits and kills, not ambient, so they stay every frame.
- The XP bar's rainbow march (40 units a second) is left smooth: at 12 Hz it would jump three units a step.
