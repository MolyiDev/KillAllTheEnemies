# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Kill All The Monsters** is a co-op Roblox wave-survival shooter: Roblox's *Survive a Million Monkeys* is the
reference for the loop (waves with a count, run cash spent on weapon / ability / defense upgrades, barricades and
turrets, a class picked in the lobby), with **many more enemy types**. The number alive stays capped at about 255
(below). Players gather in the **Lobby** place, queue on a pad, and are teleported together into the **Game** place
to survive escalating waves. Luau on `jecs`
(ECS), `Ignis` (loader and lifecycles), `Signal`, `Butler` and `Blink` (network codegen), `vide` for UI; packages
via Wally.

The look is **not anime and not pixel art**: maps are stud-style (LEGO-like bricks at real scale), the UI is sleek
and modern. The designer's UI spec is `UI Matt.rbxl`, inventoried in `UIMatt.md`. `Plan.md` is the status and the
list of deviations still to make from the code this started from.

Built from three reference games in `../`, each still useful to read:

- **Anime Zombie Survival** (`../Anime Zombie Survival`) is the code this repo started from (2026-11-20): the
  lobby pads, the match and rounds, run Gold, defenses, the first / third-person camera with zoom and shoulder lock,
  and above all **the enemies**: a layered nav grid baked from the map, one flowfield per player, so a crowd finds
  its way through a complex map (stairs, decks, walls).
- **Ballarc** (public name Last Wave, `../Ballarc`) is the most polished and studied: the asset pipeline docs
  (`Animations.md`, `Models.md`, `VFX.md`, `Sounds.md`, `Textures.md`, `UI.md`, `Maps.md`) come from it, as do
  TopbarPlus, live configs and the Meta network.
- **BeACastleLord** (`../BeACastleLord`) was the reference for enemy bodies and rigs (R6-shaped skinned meshes,
  hit-flash, blocky player body).

`performance/` holds the measurements behind the engine-level decisions; read `performance/README.md` and
`performance/15-luau-idioms.md` before changing a rule below. `performance/09`-`14` (skinned ceiling, packing many
bodies per mesh, tint vs Highlight flash) are why the enemy flash is a Highlight and why that caps the crowd.

### Places

| | Place id (served by Rojo) | Old place (read only) |
| --- | --- | --- |
| Lobby (`lobby.project.json`) | 97384805316642 | 105859632802526 |
| Game (`game.project.json`) | 113327793187086 | 104435679031452 |

All four are in universe **10768635421**, owned by group **34796361**. Audio and animations play only in games their
owner owns: anything uploaded by the earlier games' group (35115431) or a user needs this universe granted use of it
(Tripwire `grant_asset_permissions`) or a re-upload by 34796361. The old places hold an earlier version of this game: read their code and
instances with Tripwire to see what to keep or improve, never serve Rojo into them and never teleport to them. The
ids live in the project files (`servePlaceIds`, with the old ones in a comment) and in `EPlaceIds`.

## Tooling

- **Formatter:** StyLua (`stylua.toml`, 120 columns). `stylua --check src` must pass.
- **Linter:** Selene (`selene.toml`, Roblox standard library). Generated network files, `src/PlayerModule` and the
  vendored TopbarPlus are excluded. `selene src` passes with zero warnings today; keep it that way.
- **Types:** `luau-lsp analyze` with a `rojo sourcemap` and the Roblox definitions. Package types (`jecs.*`,
  `Ignis.*`) are unresolved until `wally-package-types` is run, which is noise, not errors.
- **Network:** `blink/generate.sh` regenerates both Blink networks (`blink/.blink`, the hot gameplay one, and
  `blink/Meta.blink`, cold menu / profile / lobby / config domains) into `src/Global/{Client,Server}/Network.luau`,
  `NetworkMeta.luau` and `src/Global/Types/NetworkTypes.luau` / `NetworkMetaTypes.luau`, strips `--!native` from the
  server files (it blows the native code budget) and prints each network's highest reliable event index.
- **Packages:** `wally install` (into `Packages/`, gitignored).
- **Configs:** `python3 tools/configs/upload.py [Key ...]` publishes `MainConfig.json` to Experience Configs on the
  universe (no test universe yet; add it first in `UNIVERSES` when there is one). Keys come from
  `ROBLOX_CONFIGS_API_KEY_PROD` (or `ROBLOX_CONFIGS_API_KEY`) in `.env`, with `universe:read` and `universe:write`. A
  new key also needs an `EConfigKeys` entry and an observer, or it publishes and does nothing.
- **Build:** `rojo build game.project.json -o game.rbxl`, `rojo build lobby.project.json -o lobby.rbxl`. The project
  files are JSONC (Rojo 7.6 reads comments).
- **Headless checks:** `lune run tools/lune/compile.luau src` (the 200-local limit Selene cannot see) and
  `lune run tools/lune/sim.luau "$PWD"` (rounds, the nav graph and flowfields on a synthetic map with a deck, a stair
  and a wall, 255 enemies through the real `enemiesUpdate`, the packer round trip, the ground warnings' footprints);
  `tools/lune/ragdoll.luau` (the death ragdoll), `tools/lune/coins.luau` (kill coins' flight) and
  `lune run tools/lune/guns.luau "$PWD"` (how fast each step of the weapon ladder kills, one body at a distance and
  a crowd of each round's mix: run it after changing a ladder gun, since damage a second does not show a step down).
- **Maps:** built in Studio and saved with the Game place under `ServerStorage.Maps` (a Model per `MapsCore` name:
  `PirateCove`, `GrassLands`), never mapped in Rojo. Each may have `Blockers` (the invisible walls round the play
  area: never floor, and the nav grid covers only their footprint) and `Backdrop` (scenery moved out of the arena
  before the bake: the sea, far islands). No spawn parts: enemies drop in around the players. Read `Maps.md` for
  the look and the rule that matters most: **no player may stand where enemies cannot follow**.
- **The old places, offline:** `research/OldGame` and `research/OldLobby` (gitignored) are dumps of the user's saved
  copies (`GameOld.rbxl`, `LobbyOld.rbxl` in Vinegar's `Documents/KillAllTheMonsters`): every script as a file at its
  instance path plus `_tree.txt`, and `_assets.txt` (every sound, mesh, texture and particle id with its instance
  path, from `tools/oldplaces/assets.luau`). Grep them instead of reading through Tripwire one script at a time; regenerate with
  `tools/oldplaces/dump.luau` (its header has the command). `research/Review-*.md` are the reviews of what to port.
- **Assets:** the source of every sound, image, animation, effect and model the game uses is kept under `Assets/`
  (listed in `Assets/README.md`), to be uploaded by group 34796361. Anything new or ported goes there too.
- **Enemy rigs:** `tools/rig/` builds R6 enemy rigs into `Assets/models/Enemies/` (gitignored); Models.md sections
  7-8 for the contract and the upload. The scripts still paint the anime zombie: the stud look is a new paint pass.
- **Seeing effects and UI offline:** `ror` (renders a model or an effect to PNGs and MP4), `ree` (runs Luau against
  an emulated engine) and `rur-native` (renders Roblox UI), in `~/.local/bin`, docs in
  `~/.local/share/roblox-tools/`. Point `ROR_ROBLOX_CONTENT` (ror, ree) **and** `RUR_ROBLOX_CONTENT` (rur) at
  Vinegar's Studio `content` folder, or built-in fonts and textures silently draw nothing. Group-owned images 403:
  swap ids for local PNG paths, or set `ROBLOX_ASSET_DELIVERY_API_KEY`. Never hand them a `.ROBLOSECURITY` cookie or
  `ROR_STUDIO_COOKIE=1`. VFX.md section 25 has the workflow.

## Architecture

### Places and trees

| Rojo tree | Lobby place | Game place |
| --- | --- | --- |
| `ReplicatedFirst.GlobalFirstShared` / `.FirstShared` | `src/Global/FirstShared` / `src/Lobby/FirstShared` | same / `src/Game/FirstShared` |
| `ReplicatedStorage.GlobalShared` | `src/Global/Shared` | same |
| `ReplicatedStorage.Types` / `.Data` | `src/Global/Types` / `src/Global/Data` | same |
| `ReplicatedStorage.Shared` | `src/Lobby/Shared` | `src/Game/Shared` |
| `ServerScriptService.GlobalServer` | `src/Global/Server` | same |
| `ServerScriptService.Server` | `src/Lobby/Server` | `src/Game/Server` |
| `StarterPlayerScripts.GlobalClient` | `src/Global/Client` | same |
| `StarterPlayerScripts.Client` | `src/Lobby/Client` | `src/Game/Client` |

Each entry script (`init.server.luau` / `init.client.luau`) loads its place's Services or Controllers, the global
ones, `GlobalShared.Core`, `GlobalShared.Modding` and `Shared.Core` through `Ignis.LoadDescendants`, then ignites.

One Game place plays every map. The maps are Models under `ServerStorage.Maps` in the Game place file, named as in
`MapsCore`; the first arrival's teleport data picks one and `arenaMap` moves it to `Workspace.Arena` once, before
any character spawns.

### ECS and lifecycles

`src/Global/Shared/ECS`: `World` (players, characters) and `EnemyWorld` (enemies, both sides). `References/` maps a
Player, a character Model or a network InstanceId to its entity. Character and enemy ids come from separate
`IdGenerator`s; id 0 is "nobody" on the wire. `PlayerEvents` / `CharacterEvents` (`src/Global/Shared/Modding`)
create the entities and fire `OnPlayerConnected`, `OnPlayerDisconnected`, `OnCharacterAdded`, `OnCharacterRemoving`,
and on the client `OnSelfCharacterAdded` / `OnSelfCharacterRemoving`. `DatabaseService` fires `OnDataLoaded`. Use
them; never hand-wire `Players` connections. Their types are `Types/Events/TPlayerEvents` / `TCharacterEvents`.

`CharacterEvents` fires the character hooks only once it has waited for the Humanoid, the HumanoidRootPart, the
Humanoid's Animator and the Head, and it stores the first three on the entity (`Components.Humanoid`,
`.HumanoidRootPart`, `.Animator`); `TCharacter` types all four. So never `WaitForChild` or `FindFirstChild` them again:

- In a character hook, index what it hands you: `character.Humanoid.Animator`, `character.HumanoidRootPart`.
- Needed later on the client: keep it from `OnSelfCharacterAdded` in a module local and clear it in
  `OnSelfCharacterRemoving` (`CameraController`'s `selfRoot`), rather than searching `LocalPlayer.Character`.
- Anywhere else (a server poll, a check by player): read them off the character entity
  (`getCharacterEntityFromPlayer`, then `World:get`). A character with no entity has not finished loading: treat it
  as absent. Health is `Components.CurrentHealth`, never `Humanoid.Health` (see CharacterService).

### Persistence

`DatabaseService`: one session-locked DocumentService document per player (`TProfile`), with the open / steal / kick
flow. The cache is deep-frozen: write through `DatabaseService.Update(player, mutate)`, and follow anything GRANTED
with `SaveAsync`. `PurchasesService` is the one `ProcessReceipt`: each product's grant and its receipt id are one
write, saved before acknowledging, so a retried receipt is never granted twice. `ProfileSyncService` mirrors the
HUD's part of the profile (`Profile.Sync`, Meta network) to `ProfileController`. Run Gold, abilities and defenses
are never saved. **Once the game is live, every schema change needs a migration.** The store is
`KillAllTheMonsters_Live` / `_Studio` (`getStoreName`). The old places save in the same universe through ProfileStore
under `"Profiles"`: a different store, never opened by this game (carrying old saves over would be a deliberate
migration).

### Live configs

`ConfigsCore.Observe(EConfigKeys.X, callback)` on both sides: ConfigService is server-only, so the server reads it
and `ConfigsService` sends the values to clients (Meta network). `MainConfig.json` is the source of every key's
value. The callback gets nil when the key is not set, so every observer keeps its own default (see
`EnemiesService`'s `Enemies.MaxAlive`, which can only lower the cap).

### The run (Game place)

```
Lobby pad -> token in MemoryStore -> TeleportToPrivateServer (Game place)
  -> MatchService: read token, place its map (arenaMap), wait for the party / profile / characters / ArenaCore.Bake,
     BeginRun kits
  -> RoundService: Preparing (countdown, no votes) -> Fighting (metered spawns, boss every 15th; SKIP WAVE vote
     or auto-skip -> the next countdown, the skipped wave still open)
     -> each wave pays once, when it and every wave before it are cleared
  -> EnemyMovementService (10 Hz) -> enemiesUpdate (targets by NavService path cost) -> EnemyPacker -> AOI-culled stream
  -> EnemyAttacksService: telegraphs + resolution of Explode / Slam / Shockwave
  -> WeaponService (guns), DefenseService (turrets, barricades), EconomyService (Gold, Gems)
  -> everybody down -> MatchEnded -> lobby (Studio: restart)
```

- **MatchService**: arrival (the handshake via `GlobalServer.Utils.JoinData`), run setup and teardown, the wipe,
  revive offers after a clear (`EProducts.Revive`).
- **RoundService** + **RoundCore**: wave sizes, scales, the boss, rewards (Gold, Gems, XP %, records per map and
  party category) paid once per clear; kill Gold on each kill with its coin picture (`Economy.Coins`).
- **CharacterService**: ECS health (the Humanoid only mirrors it), the hurt window, regeneration, no auto-respawn,
  avatars loaded on `blockyBody`, and the InstanceId handshake (announced, acknowledged by every client, then
  registered).
- **EnemiesService**: spawn / damage / kill / remove, `DamageMultiple` / `KillMultiple` (one event per volley per
  player), immunity, the stagger, the boss bar. Events go only to the body's AOI subscribers.
- **AOIService**: per-player area-of-interest subscriptions and camera state. A client only ever holds rows and rigs
  for enemies it has been shown.
- **EnemyAttacksService** + **TelegraphCore**: every non-melee enemy attack. The ground warning is the hitbox (a
  Circle, Ring, Cone or Line over its FOOTPRINT: the nav nodes flooded from the floor under its centre through
  step-sized links, so it runs up a stair but never onto a deck over it, off a ledge or through a wall). Both sides
  flood the same grid, so `TelegraphController` draws exactly what hits.
- **WeaponService** + **GunsCore**: guns (`Data/Guns`, the old Game place's 20; models in `ReplicatedStorage.Models.Guns`
  from `Assets/models/Guns`). A gun is a Tool built from its model (`Server/Utils/buildGunTool`). The client sends
  only its aim point (`Weapons.Fire`); the server shoots from the character's head with its own seed and spread,
  tests the arena and the enemies' aim shapes (`GunsCore.RayCylinder` over the spatial hash, no rewind yet: a
  `LAG_PAD` instead) and pays one `DamageMultiple` per damage figure. A gun's bullets can go on through bodies
  (`TGun.Pierce`) and its shot can shove what survives it (`TGun.Knockback`, `EnemyMovementService.Push`). Client: `WeaponController` (trigger, tracers,
  flash, sound, kick; holding a gun, the body faces the aim with the cursor free too), `BodyPoseController` (every
  R6 body's sprung lean, legs turned toward the walk and a backwards walk clip when backpedalling, and an armed
  body's arms and torso on its aim; others' aim is relayed by `Weapons.Aims` from the camera sync),
  `ViewmodelController` (first person). The `gun <name>` console command swaps the gun.
- **AbilityService** + **AbilitiesCore**: classes (`Data/Classes`, two abilities and an ultimate each; everybody is
  Human until a class is picked, `TProfile.SelectedClass`). The client sends a slot and its aim (`Abilities.Cast`);
  cooldowns, the ultimate's meter (kills, never time) and every effect are the server's. A Decoy is a lure
  (`EnemyMovementService.SetLure`: a target with its own flowfield that bodies in its reach prefer to any player),
  foam holds a body and makes it `Components.Brittle`, the Orbital Cannon lands where it was aimed, then goes after the
  nearest boss in its reach or the thickest crowd on its own at a capped speed, and overkills what it touches. Client:
  `AbilityController` and `Utils/decoyFx`, `foamFx`, `orbitalFx`. The `ult` console command fills the meter.
- **DefenseService**: placement validated on the nav grid; barricades block nodes and are the barricade field's
  targets; turrets shoot the nearest enemy and credit their owner.

### Enemies and navigation

This is the part that makes the game: keep its rules when the enemies change.

- **The cap is 255 alive, and it stays** (`EnemiesCore.MAX_ALIVE`): every living body carries its own hit-flash
  Highlight, and the engine draws at most 255 Highlights. **Nothing else may use a Highlight.** The game grows by
  enemy TYPES (behaviours, attacks, elites, bosses) and by health / damage / mix per wave, never by more bodies.
  Rigs are destroyed, never pooled; reserves are unparented clones.
- **The rig** is an R6 shape as ONE skinned MeshPart (`TData.TEnemyModel`, Models.md section 7): bones `Root` >
  `Torso` > `Head` > `Hair` / arms / legs, Root.Transform carries the world CFrame. **Every body is drawn up to the
  cap at once, so every triangle is paid that many times**; enemies cast no shadow. Clips are a shared set
  (`TEnemy.AnimationSet`), rotations only so they play at any size; each attack clip lands its blow at
  `EnemiesCore.ATTACK_CLIP_IMPACT` and is sped to the attack's Delay.
- **A kill ragdolls** on the client (`Client/Utils/ragdoll`), colliding with the floor only (raycasts at
  `Workspace.Arena`), then sinks and is destroyed; `MAX_CORPSES` caps them. An **overkill** (a blow worth 4x max
  health, decided by `EnemiesService`) bursts instead. **Nothing may raycast or overlap-query an enemy**: ask
  `EnemiesCore.EnemiesSpatialHash`.
- **ArenaCore** bakes `Workspace.Arena` into a LAYERED nav grid (up to 4 floors per 2-stud cell: decks, bridges and
  the ground under them) by raycasting once per match, then links floors (step up 2.5, drop 8, no corner cutting). A
  floor too high to step onto below head height is a wall. `Blockers`, `Caps` and any part players cannot
  collide with are not floor.
- **NavService** floods one flowfield per living character plus one for all barricades (Dial's algorithm, at most
  one flood a frame). "Nearest" is path cost, so a player on a deck reached by stairs is as far as the stairs make
  them. `enemiesUpdate` steers down the field, refuses any step onto no standable floor, and goes straight when
  point-blank on the same level.
- `Enemies.Positions` carries an `EnemyPacker` buffer: 9 bytes per enemy, 2,297 bytes at 255, reliable and whole,
  since an unreliable event's ~1,000-byte payload limit would force chunking.

### The lobby

`LobbyService`: pads under `Workspace.Lobby.Pads`, numbered by name order. The first player on an empty pad
(walked on, or put there by PLAY) is its host and picks size, map and access in the party menu; the rest join until
it is full, when the countdown drops to `PadsCore.FULL_COUNTDOWN_SECONDS`. A player on a pad is anchored there until
EXIT. The pads' rim and glow are built on each client (`LobbyController/PadArt`).

### UI and the top bar

UI is `vide` (`src/Global/Client/UI`: `Theme`, `Components`, `ConsoleUI`; the HUD in
`src/Game/Client/Controllers/HudController`). The current HUD is a placeholder; the real one follows `UIMatt.md`.
`UI.md` is Ballarc's UI method (benches, motion, juice): its lessons apply, its pixel look does not.
`GlobalShared.TopbarPlus` is a vendored TopbarPlus v3 with local changes (Butler instead of Janitor, a `PixelSkin`
feature that is Ballarc's look): update it by hand, never from Wally.

### Networking

Two Blink networks, each with its own **256-event id space** (Blink writes an event id as one byte, and the 257th
generates without an error and breaks at runtime): `blink/.blink` for hot gameplay (both places), `blink/Meta.blink`
for cold domains (`Configs`, `Profile`, `Lobby`, `Console`), required as `GlobalClient.NetworkMeta` /
`GlobalServer.NetworkMeta`. Domain files live in `blink/Client` and `blink/Server` and are imported by one network
or the other, never both. Single-value payloads are written bare (`data: boolean`): `(boolean)` does not parse.
Blink comments are `--`, not `//`. Never use plain RemoteEvents for game traffic.

The conch command console (`GlobalCommandsService`, `ConsoleController`, `ConsoleUI`) opens on backquote for a player
given a role by their rank in group 34796361 (today only Admin 254 and Owner 255 reach a role), and for everybody in Studio and the test places. Debug benches
register their commands on it (`vfxbench`, `telebench`). The Game place's server commands (`pause`, `timescale`,
`enemy spawn|clear`) are in `Server/Services/CommandsService`; their argument types are `Types/CommandTypes`, which
both sides require.

### Data

`src/Global/Data/<Kind>/*.luau`: a typed local (`local data: TData.TEnemy = {...}`) returned frozen, so the analyzer
checks it against `TData`. Registered by `DataCore` (`Enemies`, `Defenses`: `ById` / `All`). Ids in
`src/Global/Types/Enums/Data`, never reused. Enemies and defenses name their models (`ModelName`) rather than holding
them, so data loads before the art is in the place.

## Performance Rules

Every number below was measured in this engine, not assumed. The harness, the full tables, and the places where
these rules and [luau.org/performance](https://luau.org/performance) disagree are in
[performance/15-luau-idioms.md](performance/15-luau-idioms.md). Read that before changing a rule here.

### Loops and tables

- Prefer generalized iteration, `for _, v in t do`. It is 8-35% faster than `for i = 1, #t do`, and `pairs` /
  `ipairs` land within noise of it. Reach for a numeric loop only when the index is needed for something other than
  reading `t[i]`, or when iterating a range rather than a table. Do not hoist `#t` into a local first; the loop bound
  is evaluated once either way, so that only adds a `MOVE`.
- When the count is known, preallocate and write to a known index: `local t = table.create(n)` then `t[i] = v`. That
  is 1.6-2.3x faster than `t[#t + 1] = v`. When the count is not known, carry a counter (`c += 1; t[c] = v`) instead
  of recomputing `#t`. Do not worry about `t[#t + 1] = v` vs `table.insert(t, v)`: they are within 1-9% of each other
  and neither is where the time goes.
- Pre-allocate with `table.create(n)` or reuse with `table.clear(t)`. Both beat a fresh `{}` by 1.3-1.9x and are
  equal to each other. Prefer reuse when you already have a table to reuse, since it produces no garbage at all.
- Use early returns to minimize nesting.

### Calls

- Do not call a helper from **another ModuleScript** inside a hot loop. A cross-module call costs ~15ns and cannot
  be optimized away, because the compiler cannot see past a `require`; at 10k calls a frame that is 0.15ms. A helper
  in the **same** module costs nothing measurable, so this is not a reason to inline by hand. Fix it by moving the
  helper into the module, or by hoisting it to a local outside the loop (`local lerp = Tools.Lerp`), which saves
  20-25% on its own.
- Call builtins directly rather than as methods: `string.byte(s, i)` is 2.2-4.1x faster than `s:byte(i)`, because
  the method form gives up the fastcall. Localizing the builtin first makes no difference either way.
- Hoist Instance property reads out of loops. `workspace.Gravity` costs ~40ns per read against ~3ns for a cached
  local, 15x. Every property read is a C++ reflection call and is an order of magnitude more expensive than any Luau
  table or global access.
- Only localize Roblox mutable globals (`game`, `workspace`, `script`, `plugin`, `shared`) when a loop reads them
  tens of thousands of times; it saves ~0.7ns per read and nothing else. Never localize non-mutable globals (`math`,
  `table`, `string`, `Vector3`, etc.): `GETIMPORT` already resolves them at load time, so localizing adds a `MOVE`
  for no gain.
- Never use `getfenv`, `setfenv`, or `loadstring`. They destroy the safe flag for the entire script, disable
  `GETIMPORT` for all globals, and switch off function inlining for the whole module.

### Objects and closures

- In object constructors, pre-define a **metatable-free** stub table at module level and use `table.clone(STUB)`
  instead of building a fresh table each call. It is 1.4-2.6x faster on median and far steadier under GC pressure.
  The stub must have no metatable on it: cloning a stub that carries one is 1.5-2.4x slower.
- When the object needs a metatable, write `setmetatable(table.clone(STUB), MT)`. That costs the same as the bare
  clone, and is ~2x cheaper than cloning a stub that already carries the metatable.
- Prefer metatable-based OOP over closure-based OOP for objects that are instantiated many times (e.g. ECS
  entities). Closures duplicate methods into every instance, while metatables share them in one table, significantly
  reducing memory usage at scale.
- Keep `__index` pointing straight at a table, one level deep, ideally the metatable itself. A three-deep `__index`
  chain costs ~2x a one-deep one, and an `__index` **function** costs ~2-3x. Call methods as `obj:Method()`, not
  `obj.Method(obj)` (1.1-1.5x).
- Read static fields off the class table (`Class.Static`), not through an instance (`obj.Static`). Resolving through
  `__index` costs ~3x a direct field read.
- Never capture a local declared **inside** a hot loop, and above all never capture a mutable one: those cost
  3.0-3.5x and 4.9-6.8x a plain call. A closure that captures nothing, or only immutable module-scope locals, is
  cached by the compiler and costs 1.6x, so it does not need to be avoided. In object factories, pass captured
  values as parameters (`self`) instead of closing over unique locals; that lets Luau emit `DUPCLOSURE` (reuse one
  function object) instead of `NEWCLOSURE` (allocate a new one per call).
- Pre-bind hot table fields to locals before loops only when the field is accessed **multiple times** inside the
  loop (e.g. `local originX = grid.OriginX`). Single-use field access does not benefit and adds a `MOVE` opcode.

### Math and directives

- Keep positions and directions as `Vector3` rather than unpacking them into three numbers. One vector op beats
  three scalar ops by 2.1-3.3x, and building a `Vector3` inside a loop is free: vectors are values, not heap
  allocations.
- Add `--!native` to parallel Actor scripts and math-heavy utility modules. It is worth 1.4-4.2x on code that stays
  inside Luau doing arithmetic, calls and table work. It is worth nothing on allocation-bound code, and it makes
  Instance property reads and cross-module calls **slower**, so keep it off services whose hot loop is mostly engine
  calls.
- `--!optimize 2` does nothing in this engine, which already compiles at level 2. Harmless where it already sits,
  but it is not a lever and adding it is not an optimization.
- Use `task.wait()` over `wait()`.

## Logic & Syntax

- Use `if then else` expressions for assignments instead of `and or`.
  - Good: `local value = if condition then a else b`
  - Bad: `local value = condition and a or b` (fails if `a` is false or nil)
- Test truthiness directly: `if isRunning then`, `if not isRunning then`. Never `== true` or `== false` **in a
  condition**. `x ~= nil` is right where nil is the case actually being asked about (an optional value, or one that
  may legitimately be `false`); `x ~= false` is the default-true field (`if data.HasFoliage ~= false then`), which
  truthiness would get wrong. As a *value*, `params.Centered == true` is fine, and is the normal way to get a real
  boolean out of a maybe-nil field.
- Invert the condition and leave early. Guard clauses go at the top of the function, one line each (`if not entity
  then return end`), so the body sits at one indent level instead of nesting under the happy path. StyLua keeps
  those on one line (`collapse_simple_statement = "ConditionalOnly"`) and Selene allows them (`one_line_if =
  "allow"`).
- Index constant keys with a dot: `ESoundsIds.ClickHud`, not `ESoundsIds["ClickHud"]`. Readability only: the two
  compile to the same thing and measure the same (`performance/15-luau-idioms.md` §10). Brackets stay for variable
  keys (`Lookup[EFoo.Bar]`).
- Never use Instance attributes (`SetAttribute`, `GetAttribute`, `GetAttributeChangedSignal`). Tuning lives in code,
  keyed by name where it has to be per-instance (`MapsCore.MAPS`).
- `type()` for Luau's own types (`"string"`, `"number"`, `"table"`), `typeof()` for Roblox ones (`"Vector3"`,
  `"Instance"`). Keeping them apart makes the kind of type being tested obvious at the call.
- A `Name` enum's value that is saved (a key in a profile) is a saved key: changing the value renames it in every
  save, so it needs a `DatabaseService` migration; renaming the enum's key breaks every require (never do that).

## Module Layout

Every file opens in the same order, so anything can be found by where it sits:

1. The file header comment: what this module owns, in a line or two (see the comment rules below).
2. Services, via `game:GetService("...")`. Never index `game.Workspace` and friends directly.
3. Packages (`ReplicatedStorage.Packages.*`), then project modules (Network, sibling Services/Controllers, Cores,
   ECS, Utils), then Types. One `require` per line, all at the top. The two requires that stay in the body are the
   dynamic one (`require(data.Module)`, the module a data table names) and the lazy one guarded behind
   `RunService:IsStudio()`, which must not load in production.
4. Derived locals off the above (`Network.Server.Gifts`, `Players.LocalPlayer`, `Workspace.CurrentCamera`).
5. The module table, then its constants and module-level state (`Tune`, caches, connections), then the functions.
6. The functions in three bands, then the `return`:
   1. **Public API** (`function Module.X`): what other systems call, so what a reader opens the file for.
   2. **Internals** (`local function`): each one above its first user, which Lua requires anyway: a local is only
      visible to code written below it, and above its definition the same name is a nil global that fails only when
      that line runs (`selene src` reports it as `undefined_variable`, so run it after moving a function). A helper a
      public function needs sits just above that public function. One that only the lifecycles use goes last, just
      above them, not at the top where nothing near it calls it.
   3. **Wiring**: the Ignis lifecycles (`OnStart`, `OnPlayerConnected`, `OnCharacterAdded`, ...), network listeners
      (`.On(...)`) and signal connections. They connect everything, so they can call anything above.

   No forward declarations to get the API above its helpers (`local foo` at the top, defined below): that is a
   second list of names to keep in sync, and a missed `local` makes a global without an error. State built out of
   local functions (a table of callbacks) is an internal, not state. A big file split into banner sections
   (`EnemiesController`) keeps them inside the bands: state sections, then function sections, each grouped by what
   it is about. Class modules (`SpatialHash`, `Grid`) have no wiring and are sectioned per table. A `.client` /
   `.server` script is not reordered: its top-level statements run in file order, so the order is its behaviour.

Functions repeat that shape inside: guard clauses, argument defaults, locals, main logic. Return only when there is
something to return.

- A function reads in steps: one blank line between steps (load, rebuild a table, connect), none inside a step,
  however short the function. Two blocks in a row that do different things are two steps. One blank line, never two
  (StyLua collapses them anyway), and not between every line: the guard clauses at the top are one block, and so is
  a run of locals read together.
- A loop is a step of its own:
  - A group of locals before it (its inputs and accumulators) is the paragraph above it, with a blank line between.
    A single setup line stays attached: the `table.clear` directly above the loop that refills that table.
  - What comes after it is the next step: the `return` of what it worked out, the line that publishes a list it
    built, a guard on what it counted, the append a check-loop allowed. Only what closes the loop stays attached:
    `table.clear` of what it emptied, `debug.profileend`, releasing the lists it used.
  - A `return` after any block is its own step, with a blank line before it.
- No blank line between a local and the `if` that tests or builds it (`local bounds = ...` then `if not bounds`),
  nor between a get-or-create `if` and the line that uses what it made (`subs[player] = true`). Nor inside a small
  block (an `if` branch, a short callback) or a tight loop body whose filters and work are one step.
- Past four or five parameters, take one table instead: positional mismatch gets likely and the call stops being
  readable. The exception is hot paths (`Grid`, `SpatialHash`, packers), where the table allocation costs more than
  the mismatch risk.
- Comments say **why**, not what, and sit next to the code they explain. A comment earns its place by stopping a
  reader from making a mistake: an engine quirk ("the PlayerModule restores RotationType, so it is set every
  frame"), a rule a future edit could break, or a fact the code cannot show (a project setting, another system's
  behaviour). Delete anything the code already says: nothing checks a comment against the code, so it goes stale,
  and a stale comment is worse than none.
- **The file header is short**: a line or two on what the module owns, plus only the rules that bind the whole file
  and the facts from outside it. A reason that belongs to one function goes on that function. No walkthrough of the
  implementation, no list of what the file does not do, no design rationale.
- **Comments do not name the reference games** (Anime Zombie Survival, Ballarc, BeACastleLord). Where code came from
  is history, and the reader cannot follow the pointer: write the reason itself ("a kill that does not flash reads as
  a miss"), cite a measurement by its file under `performance/`, and never list what was left out of the original.
  Name a reference game only where the reader has to go there: an asset it owns or holds (group-owned clips,
  uploaded image ids, a model to insert from its place) or a vendored file.
- **A module's main chunk holds at most 200 locals** (Luau's register limit). Past it the file fails to load ("Out
  of local registers"), and every module that requires it fails with it: one new `require` can take down every
  controller that depends on that file. In a module that is close, group its tuning constants into frozen tables
  (`Tune`) with the constant names as keys rather than spending a local on each, and never fix it by merging two
  unrelated locals into one.

## Systems

A system is a Service (server) or a Controller (client), registered with Ignis. **Services decide, Controllers
show.** A Service owns state and rules; a Controller owns input, camera, UI and presentation, asks a Service for
changes and never decides an outcome.

### Where new code goes

Classify before placing: a module sits in the folder of what it **is** (Services, Controllers, Core, Utils), not the
feature it serves. Then take the first of these that fits:

1. **Part of a feature that already has a system:** add it to that system. Grep for whoever already owns the data or
   the lifecycle (a global Service in `src/Global/Server/Services/` often does) before adding a peer.
2. **Tuning numbers:** constants in the owning module (`Tune`), or a frozen table in `Shared/Utils` if both sides
   read them. A number to change without a release goes in `MainConfig.json` behind an `EConfigKeys` key.
3. **Stateless helper:** a plain module beside its one user, or `Shared/Utils` once two systems need it.
4. **A new system**, only when the feature has all three: state that others should change only through its
   functions, its own lifetime (per-player setup and cleanup, timers, connections), and its own client requests.

If a system's functions start being about two unrelated things, or other systems keep reaching into its tables, that
is two systems.

### Splitting a system across files

When a system grows a second concern, give it a folder: `FooService/init.luau` is still one ModuleScript to Rojo, so
no `require` changes. Split by responsibility (lookup, validation and mutation, networking, presentation), not by
line count.

- `init.luau` is the only file Ignis sees: it holds the lifecycles, the Blink listeners and the state, and routes
  each request to a child.
- Children are plain modules: no lifecycles, no connections, no module-level state. They take what they need as
  arguments. They may require pure siblings and a shared `Types.luau`, never `init.luau`, never in a cycle.

This is the rule for new splits. The 1000-line Controllers already in the tree (`EnemiesController`) are not a bug
to fix in passing.

### Dependencies

- Point one way. If B requires A, A never requires B, at the top or lazily. Shared **state** goes in a leaf module
  both require; a **trigger** becomes a signal on A that B subscribes to (reuse one that exists before adding one,
  and never make a signal with a single subscriber).
- Per-player and per-character setup and cleanup go through the Ignis lifecycles (`OnPlayerConnected`,
  `OnPlayerDisconnected`, `OnCharacterAdded`, `OnDataLoaded`, ...), not hand-wired `Players` connections.

### Trusting the client

Blink checks the **types** of what a client sends. It does not check the **claim**. Every `.On` handler on the
server starts from the sender's own character entity and guards, one line each, that the request is possible right
now: the player has a character, holds the weapon, is not downed, is in range, owns the thing, can pay. A handler
that checks nothing says why in its comment (a cosmetic relay, like `PlayerSync.CameraSync`).

- Never take a player, an amount of currency, a damage figure or a result from the client. Take the intent (`slot`,
  `abilityId`, `choice`) and work the rest out on the server.
- Check a document's cache for nil in every handler, and never hold one across a yield: the player may have left
  and the document closed while you waited.

## Naming Conventions

- **Folders/Modules/Classes/Functions:** `PascalCase`
- **Variables:** `camelCase`
- **Constants:** `CONSTANT_CASE`
- **Types:** `TPascalCase` (e.g., `TBulletState`)
- **Enums:** `EPascalCase` (e.g., `EGameState`)
- **Booleans:** Prefix with `is`, `has`, `can`, or `should`
- **Async:** Suffix with `Async`
- **Acronyms:** Treat as words (e.g., `HttpService`, not `HTTPService`)
- **Units:** Include in name (e.g., `speedStuds`, `timeoutMs`, `yawDeg`)
- Name things for what they are, not how they are used: `Catalog`, not `ShopHelper`.
- No abbreviations beyond the universal ones (`id`, `ui`, `dt`, `vfx`, `hrp`).

## File Naming

- **Components/Classes:** `PascalCase.luau`
- **Utils:** `kebab-case.luau` or `camelCase.luau`

## Before Calling It Done

There are no automated tests in this repo, so a change is checked by reasoning about it, by the linters, by the
headless checks, and by playing it.

- Be able to say why the change is correct and where it would break. Passing the linters is not that: Selene cannot
  tell a spring that settles from one that flies off.
- Work numbers out in code, not in the reply: tuning values, ratios, unit conversions. `lune run file.luau` runs
  plain Luau, and `require("@lune/roblox")` gives it `Vector3`, so a formula can be pasted straight out of the
  module. Same standard as the Performance Rules: measured, not assumed.
- Run the linters from Tooling, and `tools/lune/sim.luau` after touching rounds, navigation, enemies or the packer.
- Lune's `@lune/roblox` CFrame is not the engine's: `CFrame.lookAt` came out facing backwards there (2026-11-11).
  Check vector maths in lune, but check orientation maths in a playtest (`run_luau_live` does plain maths on the
  server).
- Compile a big file you added a local to (`tools/lune/compile.luau`). Selene does not see the 200-local limit; the
  compiler does.
- **Look at it offline with `ror`, `ree` and `rur-native` on your own, without being asked** (Tooling, "Seeing effects
  and UI offline"). The user has had to ask for them in session after session. Anything that is seen gets rendered
  before it is reported: an effect or a model with `ror render` / `ror video` (read the frames), a UI change with
  `rur-native render`, and client Luau that can run without a server (a bench, a per-frame loop, an effect module)
  with `ree run`. They are also the way forward when Studio cannot playtest: render, judge, fix, then hand over, never
  stop at "waiting for Studio". Keep the renders the user is shown beside the sources, in the kit's `preview/` under
  `Assets/` (e.g. `Assets/effects/pistol/preview/`), not in a scratch folder.
- A lifecycle or an order of events is checked by logging it, on both sides: wrap each hook on the module table (the
  callers look the field up at call time, so the wrapper is what runs) and read the sequence back.
- A throwaway probe goes in `StarterPlayer.StarterPlayerScripts` and is deleted once its output has appeared (deleted
  straight after `start_playtest`, it is gone before the playtest copies the place and never runs). **Say so if one
  was running when the user was watching.** A probe that needs `Network` requires it by the `StarterPlayer` path the
  game uses, and a controller by the `PlayerScripts` path, or it gets a second copy. A probe that requires a client
  module waits for `PlayerScripts:WaitForChild("GlobalClient")` first: a module it loads early can fail to find
  `GlobalClient`, and the failed load is cached, so the controllers that require it fail too.
- Several Studios can be connected to Tripwire at once (this game's Lobby and Game, and the old places), all
  possibly titled "Place1". Check `list_studios` and pick by `placeId` (the Places table above) with
  `set_active_studio` before any edit or playtest: the active one is whichever connected first. Never edit an old
  place.
- Tripwire cannot start a playtest while Studio is minimized: `start_playtest` answers `started` and every later call
  says "No live server peer". Ask the user to bring Studio up, and delete the probe you created meanwhile.
- Say what was actually verified: linted, run headless, rendered in ror / rur, played in Studio, or reasoned only. "Not playtested" is a
  fine answer; leaving it out is not.
