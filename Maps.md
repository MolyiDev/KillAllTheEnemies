# Maps.md

> **Carried over from Ballarc (Last Wave) on 2026-11-20.** The method, the engine facts and the measured lessons
> apply here; the old game's look does not. Kill All The Monsters is not pixel art and not anime: maps are stud-style
> (LEGO-like bricks at real scale), UI is sleek and modern (`UIMatt.md` is the designer's spec). Sections named after
> a Last Wave weapon, boss or screen are worked examples. A path that does not exist in this repo (`Assets/...`,
> `tools/vfx/...`, a `src/Survivors/...` module) is in `../Ballarc`; `../Anime Zombie Survival` holds the enemy rig,
> map and burst pipelines this repo's `tools/` came from.

How an arena map is made, learned on the Easy map (`maps/Easy.*`, 2026-10-23) in five rounds of feedback. Each rule
below cost a round. Read it before touching `tools/arena/` or building the Hard map.

## 1. Where a map lives

- **Two places, one experience.** The Lobby and ONE Game place that plays every map (ids in CLAUDE.md's Places
  table and `EPlaceIds`). There is no place per map: the pad's teleport token carries `MapName`, and `arenaMap`
  (server) moves `ServerStorage.Maps.<Name>` to `Workspace.Arena` once, on the first arrival, before any character
  spawns (`CharacterService.Spawn` waits on it).
- **Here a map is built in Studio and saved with the Game place** (`PirateCove`, `GrassLands`, brought from the old
  Game place on 2026-11-20). Rojo never maps `ServerStorage.Maps`: a sync would replace them. The generator sections
  below (`tools/arena/`, `maps/Easy.*`) are Ballarc's and describe how its map was made.
- **Inside a map's Model**: the playable parts in folders by area, `Blockers` (the invisible walls round the play
  area; the nav grid covers only their footprint), `Caps` (§3), `Backdrop` (§6, the sea, far islands), a
  `SpawnLocation`. `ArenaCore.Bake` skips `Caps` and every part players cannot collide with (water sheets,
  foliage); `arenaMap` moves `Backdrop` to `Workspace` first. There are no enemy spawn parts: enemies drop in on a
  ring around a player, on a floor that leads to them (`RoundService`).
- **Invisible means Transparency 1, and only bodies meet it.** Blockers, Caps, trunk boxes, emitter holders
  (`Fuego`, `Luciernagas`), invisible water and the SpawnLocation stop players, but the crosshair, shots, line of
  sight and every effect's landing pass through them: those rays go through `Shared.Utils.sightCast`, which skips any
  part at Transparency 1 (VFX.md §6). So a part meant to stop a bullet must be seen, and a part meant to be hidden
  must be fully transparent: at 0.99 it is a wall nobody sees that still eats shots.
- **Studio places keep their template Baseplate and SpawnLocation**: delete them in the arena place, or players spawn
  there instead of on the map.
- **A new `$path` in a project file may not reach a running `rojo serve`**: restart it and reconnect the plugin.
- `ReplicatedStorage.Effects` (the Leaves emitter) is a place instance, not in Rojo: save the place after changing it.

## 2. The pipeline

```
python3 tools/arena/schoolyard.py && lune run tools/arena/build.luau "$PWD" Easy
blender -b --python tools/arena/render.py -- Easy <outdir>      # renders, ~2 s, no Studio
```

| File | What it does |
|---|---|
| `tools/arena/schoolyard.py` | the Easy layout, the caps, a Python copy of `ArenaCore.Bake`'s column sampling, the player standing spots, the geometry checks; writes `maps/Easy.json` |
| `tools/arena/trees.py` | trees grown by space colonization (§5) |
| `tools/arena/checks.py` | `zfight` and `loose` (floating parts, near misses), vendored from BeACastleLord's `tools/stronghold_kit.py` |
| `tools/arena/build.luau` | JSON to `maps/Easy.rbxmx`; runs the REAL `ArenaCore.Build` (through `tools/lune/harness.luau`) on the sampled floors and reports routes, drops, unreached islands and stranded standing spots |
| `tools/arena/render.py` | Blender Workbench render of the JSON from fixed shots |

**Every line of the report must be zero before a map ships**: faces on a sample line, obstacles between sample
points, z-fighting, floating, near misses, standing spots enemies cannot reach. Then read the routes (§4) and look at
the renders. The renders show colour only, not material, and come out darker and browner than Roblox.

The next map should move the bake copy and the checks out of `schoolyard.py` into a module both maps share.

## 3. No player stands where zombies cannot follow

The user's rule, after finding a player on the shed roof, the water tank and a tree canopy, every one out of reach.

- **Don't trust jump math.** Default `CharacterJumpHeight` is 7.2, yet players got 8 to 15 studs up by climbing
  stepped geometry (canopy tiers, tank legs). Caps solve it whatever the cause.
- **Caps** ("A Million Zombies" does the same): every collidable part with `walk=False` gets an invisible part from
  its top to `CAP_TOP` (70), or to the bottom of the first `walk=True` part above it (vending machines under the
  walkway stop at its slab). A cap may pass through other non-walk parts (a crown through its canopy). Transparent,
  so the camera's occlusion ignores it (Popper skips anything over 25% transparent).
- **Mark `walk=True` exactly what enemies stand on**: ground, overlays, slabs, decks, roofs they reach, treads, ramp,
  stage, bench seats, flower beds. Everything else collidable is capped.
- **`CanQuery = false` on a collidable part may be ignored by Roblox** (BeACastleLord's trunk boxes note it is only
  honoured with `CanCollide` off). So the bake skips caps by FOLDER, not by `CanQuery`.
- **The check**: the generator samples every collidable top (caps included, a player's 5 studs of headroom free),
  and `build.luau` requires each to have a node enemies reach within one cell and 0.75 studs of height.
- The cost: invisible walls rise over rails and hedges, so players cannot jump over them either.

## 4. Writing for the bake

`ArenaCore.Bake` casts one column of rays every 2 studs on the arena's bounding box. With a 256 x 256 map centred
on the origin those are the EVEN coordinates.

- **No face on a sample line** (odd or .5 coordinates): a ray on a face's edge is a coin toss.
- **Every obstacle covers a sample point** (centre it on an even coordinate), or the nav graph never sees it and
  enemies walk through. A thin rail between samples is harmless only where the drop past it is more than `MAX_DROP`.
  Thin parts that stand on something already seen (fence posts on the wall) take `query=False`.
- **A stair's 1-stud treads cannot each cover a sample**: stairs are judged as a flight (`obstacle=False` per tread).
- **No roof over stairs.** Under a ceiling the bake tests a floor's headroom from 0.3 above it, and the next tread
  (0.6 up) fills that box, so every tread under a roof stops being floor. The stage roof stops short of its steps.
- **A stair's cheek wall stands 4.2 over its tread**, not a railing's 3.4. Sampled every 2 studs, the tread two risers
  up sits 1.2 nearer the next cell's wall top, which put the rail within an enemy's 2.5 step and they walked on it.
- **Drops**: `MAX_DROP` is 8 (raised from 6 for this map). Anything up to 8 high is a ledge enemies step off; a
  second floor (12) is stairs only. A floor too high to step onto below head height (a parapet) is a wall even with
  ground in drop range under it (`ArenaCore.StepTarget`, `enemiesUpdate`'s `floorNode`). Before that rule, enemies
  dropped straight through a railed walkway's parapet.
- **Anything walked under is at least 5 up** (`CLEARANCE`, the enemy's height). The client's floor probe starts 4
  above an enemy's feet, so a canopy or roof lower than that would catch it.
- **Read the routes** in the report: a drop shows as a short route (garden edge 48 studs) against the long way
  round (103). Probes and routes are listed in `PROBES` / `ROUTES` at the end of the generator.

## 5. Trees

- **Grown, not modelled**: `trees.py` ports BeACastleLord's `TreeCore` (space colonization, then the pipe model for
  radii), seeded from the tree's position so a rebuild is identical.
- **One bark block per growth segment, never merged.** Each 1.6-stud segment is its own Part with its own shade
  between the bark colours, which is what reads as a carved trunk. Merging straight runs into long blocks (the first
  attempt) read as a plain pole and was rejected.
- **Foliage**: `Grass` cubes, 2.6 to 4.4, tumbled at random round each twig tip (`Blob`); the pine uses flat level
  pads (`Pad`) for cloud-pruned niwaki. Species: `SAKURA` (wide low umbrella, pink) and `MATSU` (leaning trunk, near
  level limbs).
- **Bark and leaves never collide and are never queried.** The only collision is an invisible trunk box from the
  ground to the first fork (capped like everything else). The crown is no floor, and nothing stands on it.
- **Falling leaves**: each tree carries an invisible `LeavesVolume` (0.85 of the foliage's box). `arenaMap` clones
  `ReplicatedStorage.Effects.Leaves` into each, tinted from the volume's Color to a shade darker, and enables it at
  `LEAF_RATE`: the asset ships `Enabled = false` because it is also a burst (`EmitCount` attribute).
- **Budget**: about 190 parts a tree, 59% of the map. Bark under 0.8 studs wide casts no shadow (twigs sit in the
  foliage's shadow anyway), which halved the map's shadow casters.

## 6. The look

- **Real proportions**: a character is 5 studs, about 1.7 m. Storey 12, window 6 tall over a 3-stud sill, door 7.5,
  railing 3.4, stair riser 0.6 on a 1-stud tread, a sakura's crown 26 wide. The first map built doors and windows
  ending at a player's head, and it read as tiny.
- **Bright and alive, for kids.** Muted ramps and an all-dirt floor read as dead. The reference is a sunny low-poly
  island: saturated sand, lime grass, bright roofs, and a ground broken up into paths, lawns and a red running track.
  The zombies stay muted (Textures.md), so they read against a SAND play area. A big green lawn where they fight would
  hide their green skin.
- **Materials**: a small textured set. `Slate` for everything built (walls, slabs, stairs, paving, rails, roofs),
  `Wood` / `WoodPlanks`, `Metal`, `Fabric`, `Sand`, `Grass`, `Glass` for panes. `SmoothPlastic` reads as a
  placeholder and is used only on invisible parts.
- **A facade is counted in parts, not painted flat** (measured off two toolbox schools, 2026-10-23: their OBJ
  export and renders are how to read a reference, §7). Their brick school sets its glass 0.25 back in a 1.4-thick
  wall, with stone sills and heads 0.12 proud, a transom, a 2-stud band at each floor, a cornice cap and a plinth,
  and paints its end blocks brick against a grey middle. Ours takes the same steps with trim only (the collision
  face never moves): `window()` puts the glass 0.08 off the wall inside jambs 0.35 out, a head 0.55 and a sill 0.75
  out; the school has brick end pavilions 0.25 out, pilasters between bays, floor bands, a plinth and a deep
  cornice. The first windows had the glass in FRONT of its frame and read as stickers.
- **The ground gets edges and furniture**: kerbs round every lawn (0.35, walkable), shrubs along building feet
  (walked through, so no cap), lamps and bins on even coordinates (they cover a sample point and get capped).
  Both references are busy at ground level where ours was bare sand.
- **A sports ground is a stadium, not a coloured rectangle** (the toolbox school's, 490 parts, measured
  2026-10-23). What makes it read: a ROUNDED track (each corner a polygon arc of 22.5-degree chords, every line
  getting shorter toward the inside), lanes of white lines on brick red (they used 6 lanes of 6.33; ours are 3 of
  a real 3.6), the grass a step lower than the track and the lines a step above it, all on a concrete apron whose
  corners show past the curves; framed goals (posts, crossbar, stays raked back to a ground bar, a net); a
  grandstand of rows a step up each, seats on the back of every tread, aisles of half steps with handrails, a glass
  rail with posts; and balls left lying in twos and threes. Four colours carry it: grass, red, white, grey, plus
  one accent. Ours (`schoolyard.py`, "the sports ground") adds mown stripes and the pitch's markings.
- **Props are built like the real thing, at real size** (seven toolbox models measured 2026-10-23: a park, two
  plazas, a strip mall with parking, planters, a flower bed). A bench is three seat slats on rails, three
  backrest planks and square legs, not a plank on two legs (ours: `bench()`, back toward `back`, its only
  collision an invisible seat). A lamp is a post under a glass lantern and a cap; a bin a round can with a dark
  lid; a fountain a stone basin brim-full of 35%-transparent water, a column and a bowl. Flowers stand in leaf
  tufts on soil, never on bare stone; stones come in threes (big, middling, small), tumbled and half sunk;
  plants come in pots and troughs with soil showing. A road has a dashed centre line, a solid edge line and cars
  parked along it (13 x 5.4 studs: body, glass cabin, roof, four wheels). Where paths cross, a round plaza with
  a fountain and benches facing it gives the crossing a reason.
- **Curves and fine lines are trim on one walkable slab.** The stadium's base is one axis-aligned walkable part;
  the track, grass, lines and stripes lie on it a few hundredths thick (`flat()`, `rounded()`, `ring()`), never
  collided or sampled, so turned parts never meet the nav grid. Lines that cross each take their own height (a
  hundredth apart) and sink their bottoms into what they lie on, or the z-fight check flags them; fan slices are
  turned off the axes so they never share a plane with the bands.
- **Ground overlays** (paths, lawns, track) are parts 0.1 thick on the base floor, a step nobody feels. They must
  not overlap each other (z-fighting); split them where they cross.
- **No void**: the walls are 5 of concrete under a 30-stud ball-stop net, and the `Backdrop` (roads, houses with
  wedge roofs, apartment blocks, utility poles, out to 800 studs) fills every view past them. Backdrop parts never
  collide, are never queried and cast no shadow. It is moved out of the arena because the bake's grid is the arena's
  bounding box, and 800 studs of scenery would make it 800 x 800.

## 7. Tripwire

- **The active Studio can change between calls** (the user reconnecting one). Run `list_studios` and
  `set_active_studio` before reading a place, or you read the lobby while meaning the arena.
- `capture_screenshot` times out when the Studio window is not on screen, and edit mode draws only `Workspace`, not
  `ServerStorage.Maps`. Use the Blender render.
- `get_instance_children` on a tree folder (thousands of parts) overflows the result; grep the saved file instead.
- **Reading a reference model**: Tripwire's edit-mode reads give names, not geometry, and paths are ambiguous where
  names repeat. Have the user export it from Studio as OBJ (`Export Selection`): every part is a `g` group whose
  vertices give its box, its `usemtl` gives the colour (`Kd`) and a texture that names the material (Concrete,
  Brick, Grass...). Blender's `wm.obj_import` loads 33k parts in seconds; render it with Workbench in MATERIAL
  colour, each material's `diffuse_color` set from its Principled base colour (the textures are grey).
- Read a property back to confirm a Rojo sync (`get_instance_properties` on one part) rather than trusting it.
