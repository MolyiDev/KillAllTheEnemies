# Lobby GPU (overdraw) results - 2026-11-09

Baseline HEAD is `b57c902`. The changes are uncommitted in `src/`, synced to the Lobby Studio (place 127928217434499)
through Rojo. Nothing was published. The probe and its two hooks were removed afterwards.

## Why overdraw

Phone captures (Samsung A13, Mali-G52, quality 1, 2026-11-08) showed every lobby screen GPU-bound, with only 1-3k
triangles. The engine's per-frame "GPU Time" label tracked how many times the menu canvas is painted:

| Screen | Overdraw | Phone GPU ms | 8 + 7.2 x overdraw |
| --- | --- | --- | --- |
| Lobby | 3.28 | 31.6 | 31.6 |
| Shop Boxes | 4.20 | 43.9 | 38.2 |
| Shop Deals | 8.07 | 67.8 | 66.1 |
| Shop Tools | 8.75 | 70.9 | 71.0 |
| Skill tree | 4.45 | 44.8 | 40.0 |

So about 7 ms of A13 GPU per full-canvas layer. Studio's `Stats.RenderGPUFrameTime` is useless for this (240 FPS cap,
RTX 4060), so overdraw is measured directly instead.

## Method

`BenchProbe.client.luau` (copied into `src/Lobby/Client` for a run) opens each screen through a temporary hook on
LobbyUI, waits 3 s, then walks the MenuUI SurfaceGui: every visible GuiObject adds its clipped canvas area once per
thing it draws (background, image, viewport, canvas group, text, text stroke). The sum over the canvas area is the
overdraw. Deterministic: the same screen measures the same every run.

## Results

| Screen | Base | +slab shadow/bezel strips, glow off under the sky | +outline ring, black off under the sky |
| --- | --- | --- | --- |
| Lobby | 3.28 | 3.04 | 2.90 |
| Shop Boxes | 4.20 | 3.88 | 3.70 |
| Shop Bundles | 8.91 | 6.34 | 5.04 |
| Shop Deals | 8.07 | 5.62 | 4.18 |
| Shop Tools | 8.75 | 6.11 | 4.77 |
| Shop Premium | 9.11 | 6.32 | 4.92 |
| Skill tree | 4.45 | 3.63 | 2.50 |

Raw output: `run2.raw.json`, `run3.raw.json` (the base run is in the session log).

## Changes

1. **`pixelSlab.Body` draws only what shows.** Shadow, Outline and Bezel were full-size Frames stacked under the Well,
   so a slab cost four fills of its area for one visible fill plus thin rings. Now the Shadow is a right and a bottom
   strip, the Bezel its two sides (top and bottom were already the Light and Shade rows), and the Outline four edges.
   The three frames keep their names and hierarchy as transparent holders, because callers hide the Shadow, parent into
   the Bezel and Outline, and recolour `slab.Outline.BackgroundColor3` on hover: the edges follow that property.
   Pixel-identical by construction. Global, so the run's HUD slabs get it too.
2. **Navigation glow off under the skill tree.** The sky covers it.
3. **MenuUI's black Background off under the skill tree**, with the sky made opaque in the colour it used to blend to
   (4% see-through over black). `LobbyUI` returns `IsCanvasCovered` for it.
4. **Three chests on the box wheel, one shadow.** A chest is shown or hidden, never part see-through (that showed the
   chest's inside while it faded). Past 0.6 of the way round (the back two at 0.8, already black there) it is hidden,
   and a hidden chest is not moved, lit or given a floor. Only the chest nearest the front casts the shadow copy
   (`chestLook.Sync(casters)`). The 3D cost is not in the overdraw number.
5. **No idle sheen on the boost rack.** Lit boosts no longer join the lobby's every-few-seconds attract sheen; the sheen
   still plays when a boost is switched on and when the rack arms on open.

## Not changed, and what is left

- Each card's Wash (gradient) and Stripes (tiled image) are 0.4-0.57 fills each on the card tabs. They are the cards'
  look; merging them into one object would not help, since a background and an image are two draws either way.
- The box wheel's two full-page ViewportFrames (chests and shadow, 0.79 each) and the lobby's rig viewport (0.76).
  Shrinking them changes the camera framing.
- The glow (0.65) on the shop's card tabs is partly visible round the panel.

Next check: a phone capture of the same screens. The model predicts about 41-43 ms GPU on Deals/Tools (from 68-71) and
about 30 ms on the skill tree (from 45).
