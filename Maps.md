# Maps.md

> **Carried over from Ballarc (Last Wave) on 2026-11-20.** The method, the engine facts and the measured lessons
> apply here; the old game's look does not. Kill All The Monsters is not pixel art and not anime: maps are stud-style
> (LEGO-like bricks at real scale), UI is sleek and modern (`UIMatt.md` is the designer's spec). Sections named after
> a Last Wave weapon, boss or screen are worked examples. A path that does not exist in this repo (`Assets/...`,
> `tools/vfx/...`, a `src/Survivors/...` module) is in `../Ballarc`; `../Anime Zombie Survival` holds the enemy rig,
> map and burst pipelines this repo's `tools/` came from.

How an arena map is made, learned on the Easy map (`maps/Easy.*`, 2026-10-23) in five rounds of feedback. Each rule
below cost a round. Read it before touching `tools/arena/` or building the Hard map.

Sections 8 and 9 are this game's own: the Lobby place's world (the plaza, the shooting range), how to read, render
and build in it, and the order of work that would have saved four rounds. Read section 9 before changing anything
under `Workspace.Lobby.Map`.

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
  sight and every effect's landing pass through them: those rays go through `GlobalShared.Utils.sightCast`, which skips any
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

## 8. The lobby's shooting range (2026-11-23)

A porch on the plaza's axis (z = -13: the ring's middle, which the SHOP and LEADERBOARDS mirror about), a corridor in
and a hall centred on it. `Workspace.Lobby.Map.Range.Hall` and `.Door` are generated; `Range.Targets` (the dummies) is
placed by hand and `Range.Front` (the SHOP's portico, banners, lamps and planters, with the label) is inserted from a
model. Four rounds: the first hall was "snapped onto the lobby", z-fighting, with a character gone white at its
door; its remake matched the plaza but was "full of things" (hanging lamps, wall emblems, crates, floor paint) with a
label unlike the other buildings'; stripped bare, its front was a hole in a wall beside the SHOP's portico, its
standing room too thin and its corridor too long.

```
python3 tools/lobby/range.py /tmp/range.json                      # the parts; "z-fights: 0" or it does not ship
python3 tools/lobby/preview.py dump /tmp/lobby.json               # in a Lobby playtest: the live place as JSON
python3 tools/lobby/preview.py render /tmp/lobby.json out/ --range /tmp/range.json    # ror, before Studio is touched
python3 tools/lobby/range_push.py /tmp/range.json                 # no playtest running; then save the place
lune run tools/lobby/range_front.luau /tmp/old.rbxl Assets/models/Lobby/Range/RangeFront.rbxm   # the front, to insert
```

- **A range is bare: the guns being tried are the point**, and what decorates it is what decorates the PLAY hall:
  lines of neon. Floor, walls, a counter with one hazard band, three pilasters a side under a truss with a cream
  strip up each, a blue line round the walls and three along the ceiling, and green lines on the floor (plain Parts
  0.6 wide and 0.1 high, as PLAY's are) that run in along the corridor's edges and turn along the counter. No props,
  no emblems, no lamps, no light sources in the hall.
- **A building's front is the plaza's kit, lifted.** The SHOP's portico (`Building.Base` without its body `Cube`),
  its `flags` (the banners with chevron Beams on their frame), three ceiling lamps and its two front planters are
  taken out of the old Lobby place file by `range_front.luau` and stood where the same pieces would stand here: face
  at x = -23, as far from the ring as the SHOP's is (the slot between the two terraces is 96 wide for exactly this).
  The body is a closed shell, so the porch behind the portico is the generator's (side masses, roof, floor, the
  SHOP body's 70 by 34.9 cut to 12 deep) round the door. Imitating the kit with boxes was what read as a hole in a
  wall. Models.md section 11's rule, again: lift the props, never rebuild them.
- **Cohesive means the plaza's own vocabulary, measured**: its stud (`rbxassetid://7447638591`, a `Texture` named
  `Stud` on each seen face, 2 studs a tile, 1 on small parts), its greys (`#3e4048`, `#4b4c56`, `#5b5d69`,
  `#63667a`, `#767a93`), its neon (blue `#5978ce`, cream `#b0ae92`, green `#6db665`). The first hall used a
  `MaterialVariant` (`Range Studs`) that only the old place had: MaterialService is empty here, so its walls drew as
  flat plastic. Never lean on a MaterialVariant; put the stud on as a Texture.
- **A building's label is the plaza's letters, not a SurfaceGui.** SHOP and LEADERBOARDS are neon MeshParts from one
  alphabet pack (0.6 x 0.6 x 0.05 meshes; LEADERBOARDS draws them 6.75 times that, 0.5 deep, 0.6 apart, `#5978ce`)
  on a studded band with a green line under and a thin blue one over. The pack's ids rise as the alphabet falls
  (T 3265176909, S ..6963, R ..7028, P ..7142, O ..7206, N ..7251, M ..7304, L ..7358, K ..7402, J ..7458,
  I ..7517, H ..7579, G ..7634, F ..7684, D ..7764, B ..7895, A ..7951; E 3265180705): a missing letter is found by
  downloading the ids between two known ones and keeping the mesh of that size. Fourteen characters fit the band's
  52-stud panel at 5.8 times the mesh. No plugin writes `MeshPart.MeshId`, so `range_front.luau` writes the whole
  front as a model, uploaded (`upload_asset`, Model) and put in with `insert_model`; the first sign was a yellow
  TextLabel on a black plate and was rejected. A Model asset cannot be archived: every upload stays in the group.
- **The way in sits on the plaza's axis** and the hall is centred on the way in. The corridor is only 16 wide
  because the building south of it has its face at z = -21.18, so it is kept short instead: the hall starts at
  x = 32, just past that building, which gives 23 studs of standing room behind the counter, and a pier in each west
  corner takes in the neighbours' corners that reach into the hall. The old entrance room is filled solid.
- **The plaza's arrow strips** are Beams on invisible `Floor.Arrows` parts (four of one name: rename three out of
  the way to reach the fourth by path), each destination's own colour, their attachments well off the part. The one
  toward the range was the black market's: skewed 0.02 rad, 0.8 off the axis and ending at x = -19. It now runs
  straight down z = -13 to the door (the part's CFrame and attachment `2`'s Position); the porch's floor plate is
  0.06 thick so the strip, drawn 0.09 over the plaza floor, stays above it. The other three sit about 3 studs off
  their buildings' middles, as built.
  Moving the hall moves `RangeCore`'s `ORIGIN` and `BOOTHS` and every dummy with it (one `mass_set_property` of
  CFrames read from the dump: part names are unique inside a dummy).
- **The z-fights were fillers**: a block under the floor with its top on the floor's plane, a block over the
  ceiling with its bottom on the ceiling's, a front 0.02 from the neighbours'. The generator's check counts two
  drawn faces on one plane facing the same way with overlapping rectangles, unless the patch is buried in a third
  box, and takes in the plaza parts that reach the hall (`PLAZA`, world boxes). The front stands 0.34 proud of its
  neighbours on purpose.
- **Light is measured on a body, not judged on walls.** `Lighting.Ambient` is 250 here, so indoors is already fully
  lit: the first hall's fill PointLights and SurfaceLight strips on top of it clipped a pale block to white at the
  door (255, 255, 238 in a render) where the plaza gives 216, 208, 197. Neon carries no light.
- **What collides is what stops a shot**: trim and neon are `CanCollide` and `CanQuery` off, so the range's sight
  cast (`RangeCore.SightParams`: Hall and Door) passes them; floors, walls, counter, pilasters and the berm are on.
- **Read the place through a playtest.** Edit mode gives names, not geometry, and Studio's autosave of a place can
  be days old. `dump.luau` on the playtest's server returns every part, texture and light; `place.luau` turns that
  back into a file `ror` draws, with each private mesh and texture fetched through Tripwire and a MeshPart's
  `InitialSize` set from its `MeshSize` (without it every mesh draws at its own size, all over the map).
- **Tripwire builds it** (`mass_create`, 120 a call): typed values only (no ColorSequence, no Vector2). Every
  parent is named uniquely, since a path finds the first child of a name. The new Hall is made beside the old one
  and swapped in at the end.
- **The lobby's Lighting is the old Lobby place's** (`lobby.project.json`): noon, latitude 0, Ambient 250,
  OutdoorAmbient (10, 7, 34), bloom 1 / 24 / 2, and its two Sky instances in the place in their old order
  (`Afternoon Sky`, then `DeepSpace`: the same two in the same order, so the engine picks as it did there; which
  one that is has not been checked by eye). Rojo's plugin does not write `LightingStyle`: set it in Studio.

## 9. Building anything in the lobby: the order that saves the rounds

Section 8 took four rounds of "no". Every one of them was answerable before building, from the place itself. This
is that order; the range is the worked example.

### Before drawing anything

1. **Dump the live place and render it** (`tools/lobby/preview.py dump`, then `render`): the thing to change, and
   the buildings next to it, from where a player stands. Judge the new thing in the SAME frame as its neighbours
   (a camera that takes in the SHOP and the range together), not alone: every "it does not match" was visible in a
   side by side and invisible in a close-up.
2. **Inventory the neighbours as a kit, with numbers**: which instances make the SHOP's front (portico, band,
   letters, banners, lamps, planters), their sizes, colours, how far the front stands from the ring. The table below
   is that inventory. If the plaza already has the piece, LIFT it out of the old place file (Models.md section 15);
   build from boxes only what the plaza has no piece for (walls, floors, a porch round a door).
3. **Find the axes before placing**: the ring's middle is (-68, -13); the SHOP and LEADERBOARDS mirror about
   z = -13 and PLAY and the range face each other along it. "Centred" means on that, and the user checks it against
   the floor's arrow strips, so read those too (section 8).
4. **Read the reference picture for mood, then ask what the lobby's own answer is.** Survive a Million Monkeys'
   range (dark, hanging lamps, crates, targets on poles) was offered as "only a reference": copying its props into
   a neon sci-fi plaza was the second rejection. What carried over was the idea (a hall, a firing line, dummies).

### What the user has said, as rules

- **Cohesive = the same pieces, not the same colours.** Same stud Texture, same greys, same neon, and the same
  lettering, band, banners and planters as the building next door. A label is the plaza's neon letter meshes; a
  SurfaceGui sign is never the answer for a building's name.
- **The feature is the point; decoration is lines of neon.** In a range the guns are the point. Props, emblems,
  floor paint, lamps with cones: "clutter". What the PLAY hall has is the whole allowed vocabulary: neon lines on
  floor (green and blue Parts, 0.6 wide, 0.1 high), walls and ceiling, strips up the pilasters, banners, planters at
  doors, flat ceiling lamps. Bare is also wrong ("a hole in a wall"): decorate, with that vocabulary only.
- **Space where the player stands, not where they walk.** Standing room behind a counter wants 20 studs or more;
  a corridor is as short as the neighbours allow.
- **Centre everything on the way in**: door, label, hall, and the arrows leading to it, which run all the way to
  the door.
- **Nothing near a title competes with it**: a neon band from a neighbour beside the label was called out.
  Look at what sits round a new sign before placing it.
- **A body near a door must not go white.** Measure a pale block in renders at the door and inside against one in
  the plaza (section 8); with Ambient at 250 any added fill light clips.
- **Removing a thing means the building, the model and its pointers** (the black market: its kiosk, zone, and the
  arrow strip that led to it became the range's). Its data elsewhere (a gun rarity of the same name) is not it.

### The plaza's kit (old and new Lobby place, same coordinates)

| Piece | Where (old file: `Workspace.Map`, new: `Workspace.Lobby.Map`) | Numbers |
|---|---|---|
| Stud | a `Texture` named `Stud` on all six faces | `rbxassetid://7447638591`, 2 studs a tile (1 on small Parts) |
| Greys | every building | `#3e4048`, `#4b4c56`, `#5b5d69`, `#63667a`, `#767a93` (floor) |
| Neon | every building | blue `#5978ce`, green `#6db665`, cream `#b0ae92` |
| Portico | `Buildings.SHOP.Building.Base` (not `Cube`, its body: a closed shell) | 65 wide, 3.8 deep, band y 19 to 32.5, one opening 52 by 16; face 22.6 from the ring |
| Body | `Base.Cube` | 70 wide, 34.9 high, 33 deep, a room 47 wide with a ceiling at 17.1 |
| Label | `Building.text` | letter meshes (section 8), middles on the band's panel, 2.13 behind its face, y 25.6 to 25.8 |
| Banners | `Building.flags` | frame 75 wide and 40 high, 10.9 behind the face; banners out to 45.8 each side; chevrons are Beams |
| Ceiling lamps | `Building.Lamps` | flat cream panels at y 17 |
| Planters | `SHOP.extra.plantbed2`, benches `extra.bench` | 2.7 square at the room's corners |
| Floor lines | `Buildings.PLAY.Building.floor` | Parts 0.6 wide, 0.1 high, blue and green neon |
| Arrow strips | `Floor.Arrows` (four) | Beam 10 wide, texture every 6 studs, a colour per destination |
| Terraces | `Floor.Part` at z -76.8..-61.2 and 35.1..49.4 (x -35..20) | the 96-wide slot between them is the range's front |

### Tools, and what each one cost to find out

- **Reading**: edit-mode Tripwire reads give names and a few properties. The whole place comes from a playtest
  (`preview.py dump`). `MaterialService` is empty in the new places: a look that depends on a MaterialVariant is
  lost. The old Lobby file has everything, fully (Beams, sequences, meshes): `lune` reads it once stripped.
- **Seeing**: `ror` draws the dump (`preview.py render`) and a model in the place (`ror render model.rbxmx --map
  place.rbxl`). Every asset is private to it: fetch through Tripwire `download_asset` into `research/LobbyAssets`,
  and in an `.rbxmx` rewrite `rbxassetid://N` to `file://<abs>/N` (setting `MeshId` in lune is not enough: the
  file's `MeshContent` wins). Paths handed to `place.luau` must be absolute. Not drawn: Beams without both
  attachments, SurfaceGui text. Studio's own window is usually off screen (`studio-shot` refuses).
- **Writing**: `mass_create` builds Parts, Textures, lights and GUIs from typed values (no sequences, no Vector2,
  no `MeshId`); `mass_set_property` moves existing parts when their names are unique; same-named siblings are
  reached by renaming the ones before them and renaming back. Meshes and Beams go in as an uploaded Model
  (`upload_asset` then `insert_model` with `unpack`), which lands at its authored world position.
- **Playtests**: start, wait 8 s, poll `run_luau_live` up to four times. Two starts in a row that never answer
  mean Studio is minimised: finish offline and say so. Edits made during a playtest are lost; the pusher refuses.
- **Rojo and Lighting**: `lobby.project.json` owns Lighting's properties and they sync at once, except
  `LightingStyle` (set it in Studio). Sky instances live in the place.
- **Nothing is saved until the user saves the place.** Say so in every report that touched Studio.
