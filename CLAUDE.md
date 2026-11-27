# CLAUDE.md

## Project Overview

**Kill All The Monsters** is a co-op Roblox wave-survival shooter. The loop follows Roblox's *Survive a Million
Monkeys* (counted waves, run cash spent on weapon / ability / defense upgrades, barricades and turrets, a class picked
in the lobby) with **many more enemy types**; the number alive stays capped at about 255 (below). Players queue on a
pad in the **Lobby** place and are teleported together into the **Game** place to survive escalating waves. Luau on
`jecs` (ECS), `Ignis` (loader and lifecycles), `Signal`, `Butler`, `Blink` (network codegen), `vide` for UI; packages
via Wally.

The look is **not anime and not pixel art**: stud-style maps (LEGO-like bricks at real scale), a sleek modern UI. The
designer's UI spec is `UI Matt.rbxl`, inventoried in `UIMatt.md`. `Plan.md` is the status and the deviations still to
make from the code this started from.

Three reference games in `../`, each still worth reading:

- **Anime Zombie Survival** (`../Anime Zombie Survival`): the code this repo started from (2026-11-20). Lobby pads,
  match and rounds, run Gold, defenses, the first / third-person camera (zoom, shoulder lock), and above all **the
  enemies**: a layered nav grid baked from the map, one flowfield per player, so a crowd finds its way through stairs,
  decks and walls.
- **Ballarc** (public name Last Wave, `../Ballarc`): the most polished and studied. Source of the asset pipeline docs
  (`Animations.md`, `Models.md`, `VFX.md`, `Sounds.md`, `Textures.md`, `UI.md`, `Maps.md`), TopbarPlus, live configs
  and the Meta network.
- **BeACastleLord** (`../BeACastleLord`): enemy bodies and rigs (R6-shaped skinned meshes, hit-flash, blocky player
  body).

`performance/` holds the measurements behind engine-level decisions: read `performance/README.md` and
`performance/15-luau-idioms.md` before changing a rule below. `performance/09`-`14` (skinned ceiling, packing many
bodies per mesh, tint vs Highlight flash) are why the enemy flash is a Highlight and why that caps the crowd.

### Places

| | Place id (served by Rojo) | Old place (read only) |
| --- | --- | --- |
| Lobby (`lobby.project.json`) | 105859632802526 (the start place) | none: published over (`LobbyOld.rbxl`) |
| Game (`game.project.json`) | 113327793187086 | 104435679031452 |

All four are in universe **10768635421**, owned by group **34796361**. Audio and animations play only in games their
owner owns: anything uploaded by the earlier games' group (35115431) or a user needs this universe granted use of it
(Tripwire `grant_asset_permissions`) or a re-upload by 34796361. The old Game place holds an earlier version of this
game: read its code and instances with Tripwire to see what to keep or improve; never serve Rojo into it or teleport
to it. The earlier lobby is in `LobbyOld.rbxl` and its place's version history; 97384805316642 is a spare. The ids
live in the project files (`servePlaceIds`, old ones in a comment) and in `EPlaceIds`.

## Tooling

- **Formatter:** StyLua (`stylua.toml`, 120 columns). `stylua --check src` must pass.
- **Linter:** Selene (`selene.toml`, Roblox std). Excludes the generated network files, `src/PlayerModule` and the
  vendored TopbarPlus. `selene src` passes with zero warnings; keep it that way.
- **Types:** `luau-lsp analyze` with a `rojo sourcemap` and the Roblox definitions. Package types (`jecs.*`,
  `Ignis.*`) stay unresolved until `wally-package-types` runs: noise, not errors.
- **Network:** `blink/generate.sh` regenerates both networks (`blink/.blink` hot gameplay, `blink/Meta.blink` cold
  menu / profile / lobby / config) into `src/Global/{Client,Server}/Network.luau`, `NetworkMeta.luau` and
  `src/Global/Types/NetworkTypes.luau` / `NetworkMetaTypes.luau`, strips `--!native` from the server files (it blows
  the native code budget) and prints each network's highest reliable event index.
- **Packages:** `wally install` (into `Packages/`, gitignored).
- **Configs:** `python3 tools/configs/upload.py [Key ...]` publishes `MainConfig.json` to the universe's Experience
  Configs (no test universe yet; add it first in `UNIVERSES` when there is one). Key from `ROBLOX_CONFIGS_API_KEY_PROD`
  (or `ROBLOX_CONFIGS_API_KEY`) in `.env`, with `universe:read` and `universe:write`. A new config key also needs an
  `EConfigKeys` entry and an observer, or it publishes and does nothing.
- **Build:** `rojo build game.project.json -o game.rbxl`, `rojo build lobby.project.json -o lobby.rbxl`. The project
  files are JSONC (Rojo 7.6 reads comments).
- **Headless checks:** `lune run tools/lune/compile.luau src` (the 200-local limit Selene cannot see);
  `lune run tools/lune/sim.luau "$PWD"` (rounds, nav graph and flowfields on a synthetic map with a deck, a stair and a
  wall, 255 enemies through the real `enemiesUpdate`, the packer round trip, the ground warnings' footprints);
  `tools/lune/ragdoll.luau` (death ragdoll); `tools/lune/coins.luau` (kill coins' flight);
  `lune run tools/lune/guns.luau "$PWD"` (how fast each weapon ladder step kills, one body at a distance and a crowd of
  each round's mix: run it after changing a ladder gun, since damage a second does not show a step down);
  `lune run tools/lune/aim.luau "$PWD" "<Gun Name>"` (how many bodies a shot goes into, aimed plain and lined up, on
  flat ground, slopes, a deck and stairs: run it after changing how a shot is aimed).
- **Performance benches:** `performance/optimization-2026-11-26/harness/` runs the game's own modules in ree
  (`mounts.sh` for server code, `runfx.sh` for client utils, an older copy stood in through `Context.StandIn` for a
  before / after) and prices them with `Context.WorkSeconds()`. ree runs no GC, so judge allocation-bound work by
  `--profile alloc`, not its clock; rur's `benchmark.json` heartbeat times story Luau, and its layout timing only
  ranks. The Studio ones (`studio_*_bench.py`) drive a playtest through the Tripwire daemon with a 230-body crowd.
- **Maps:** built in Studio, saved with the Game place under `ServerStorage.Maps` (a Model per `MapsCore` name:
  `PirateCove`, `GrassLands`), never mapped in Rojo. Optional `Blockers` (invisible walls round the play area: never
  floor; the nav grid covers only their footprint) and `Backdrop` (scenery moved out of the arena before the bake: the
  sea, far islands). No spawn parts: enemies drop in around the players. `Maps.md` has the look and the rule that
  matters most: **no player may stand where enemies cannot follow**.
- **The lobby's world:** `Workspace.Lobby.Map` (plaza, buildings, shooting range) is built in Studio and saved with
  the Lobby place. `tools/lobby/` reads, renders and rebuilds it offline: `preview.py dump` / `render` (the live place
  through a playtest, drawn by `ror`), `range.py` and `range_push.py` (the range's hall, generated and pushed through
  Tripwire), `range_front.luau` (its front, the SHOP's own pieces lifted from the old Lobby file). Lighting is in
  `lobby.project.json` (the old Lobby place's values); Sky instances are in the place. Read `Maps.md` section 9 before
  changing anything there: the order of work, the plaza's kit with numbers, and what the user rejected and why.
- **The old places, offline:** `research/OldGame` and `research/OldLobby` (gitignored) dump the user's saved copies
  (`GameOld.rbxl`, `LobbyOld.rbxl` in Vinegar's `Documents/KillAllTheMonsters`): every script as a file at its
  instance path, `_tree.txt`, and `_assets.txt` (every sound, mesh, texture and particle id with its instance path,
  from `tools/oldplaces/assets.luau`). Grep them instead of reading scripts one at a time through Tripwire; regenerate
  with `tools/oldplaces/dump.luau` (command in its header). `research/Review-*.md` review what to port.
- **Assets:** the source of every sound, image, animation, effect and model the game uses lives under `Assets/`
  (listed in `Assets/README.md`), to be uploaded by group 34796361. Anything new or ported goes there too.
- **Enemy rigs:** `tools/rig/` builds R6 enemy rigs into `Assets/models/Enemies/` (gitignored); Models.md sections
  7-8 for the contract and the upload. The scripts still paint the anime zombie: the stud look is a new paint pass.
- **Seeing effects and UI offline:** `ror` (model or effect to PNGs and MP4), `ree` (Luau against an emulated engine)
  and `rur-native` (Roblox UI), in `~/.local/bin`, docs in `~/.local/share/roblox-tools/`. Point `ROR_ROBLOX_CONTENT`
  (ror, ree) **and** `RUR_ROBLOX_CONTENT` (rur) at Vinegar's Studio `content` folder, or built-in fonts and textures
  silently draw nothing. Group-owned images 403: swap ids for local PNG paths, or set
  `ROBLOX_ASSET_DELIVERY_API_KEY`. Never hand them a `.ROBLOSECURITY` cookie or `ROR_STUDIO_COOKIE=1`. Workflow: VFX.md
  section 25.

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

One Game place plays every map: Models under `ServerStorage.Maps`, named as in `MapsCore`. The first arrival's
teleport data picks one and `arenaMap` moves it to `Workspace.Arena` once, before any character spawns.

### ECS and lifecycles

`src/Global/Shared/ECS`: `World` (players, characters) and `EnemyWorld` (enemies, both sides). `References/` maps a
Player, a character Model or a network InstanceId to its entity. Character and enemy ids come from separate
`IdGenerator`s; id 0 is "nobody" on the wire. `PlayerEvents` / `CharacterEvents` (`src/Global/Shared/Modding`) create
the entities and fire `OnPlayerConnected`, `OnPlayerDisconnected`, `OnCharacterAdded`, `OnCharacterRemoving`, and on
the client `OnSelfCharacterAdded` / `OnSelfCharacterRemoving`; `DatabaseService` fires `OnDataLoaded`. Use them; never
hand-wire `Players` connections. Types: `Types/Events/TPlayerEvents` / `TCharacterEvents`.

`CharacterEvents` fires the character hooks only after waiting for the Humanoid, HumanoidRootPart, the Humanoid's
Animator and the Head, and stores the first three on the entity (`Components.Humanoid`, `.HumanoidRootPart`,
`.Animator`); `TCharacter` types all four. Never `WaitForChild` or `FindFirstChild` them again:

- In a character hook, index what it hands you: `character.Humanoid.Animator`, `character.HumanoidRootPart`.
- Needed later on the client: keep it from `OnSelfCharacterAdded` in a module local, clear it in
  `OnSelfCharacterRemoving` (`CameraController`'s `selfRoot`); don't search `LocalPlayer.Character`.
- Anywhere else (a server poll, a check by player): read them off the character entity
  (`getCharacterEntityFromPlayer`, then `World:get`). No entity = not finished loading: treat it as absent. Health is
  `Components.CurrentHealth`, never `Humanoid.Health` (see CharacterService).

### Persistence

`DatabaseService`: one session-locked DocumentService document per player (`TProfile`), with the open / steal / kick
flow. The cache is deep-frozen: write through `DatabaseService.Update(player, mutate)`, and follow anything GRANTED
with `SaveAsync`. `PurchasesService` is the one `ProcessReceipt`: a product's grant and its receipt id are one write,
saved before acknowledging, so a retried receipt is never granted twice. `ProfileSyncService` mirrors the HUD's part
of the profile (`Profile.Sync`, Meta network) to `ProfileController`. Run Gold, abilities and defenses are never
saved. **Once the game is live, every schema change needs a migration.** The store is `KillAllTheMonsters_Live` /
`_Studio` (`getStoreName`). The old places save in this universe through ProfileStore under `"Profiles"`: a different
store this game never opens (carrying old saves over would be a deliberate migration).

### Live configs

`ConfigsCore.Observe(EConfigKeys.X, callback)` on both sides: ConfigService is server-only, so the server reads it and
`ConfigsService` sends the values to clients (Meta network). `MainConfig.json` is the source of every key's value. The
callback gets nil when the key is not set, so every observer keeps its own default (see `EnemiesService`'s
`Enemies.MaxAlive`, which can only lower the cap).

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

- **MatchService**: arrival (handshake via `GlobalServer.Utils.JoinData`), run setup and teardown, the wipe, revive
  offers after a clear (`EProducts.Revive`).
- **RoundService** + **RoundCore**: wave sizes, scales, the boss, rewards (Gold, Gems, XP %, records per map and party
  category) paid once per clear; kill Gold on each kill with its coin picture (`Economy.Coins`).
- **CharacterService**: ECS health (the Humanoid only mirrors it), the hurt window, regeneration, no auto-respawn,
  avatars loaded whole by `GlobalServer.Utils.loadCharacter` (R6 from the place's avatar type; never strip the
  description, or the player loses limbs and accessories), and the InstanceId handshake (announced, acknowledged by
  every client, then registered).
- **EnemiesService**: spawn / damage / kill / remove, `DamageMultiple` / `KillMultiple` (one event per volley per
  player), immunity, the stagger, the boss bar. Events go only to the body's AOI subscribers.
- **AOIService**: per-player area-of-interest subscriptions and camera state. A client only ever holds rows and rigs
  for enemies it has been shown.
- **EnemyAttacksService** + **TelegraphCore**: every non-melee enemy attack. The ground warning is the hitbox (a
  Circle, Ring, Cone or Line over its FOOTPRINT: the nav nodes flooded from the floor under its centre through
  step-sized links, so it runs up a stair but never onto a deck over it, off a ledge or through a wall). Both sides
  flood the same grid, so `TelegraphController` draws exactly what hits.
- **WeaponService** + **GunsCore**: guns (`Data/Guns`, the old Game place's 20; models in
  `ReplicatedStorage.Models.Guns` from `Assets/models/Guns`). A gun is a Tool built from its model
  (`GlobalServer.Utils.buildGunTool`). The client sends only its aim point (`Weapons.Fire`); the server shoots from the
  character's head with its own seed and spread, tests the arena and the enemies' aim shapes (`GunsCore.RayCylinder`
  over the spatial hash; no rewind yet, `GunsCore.Tune.LAG_PAD` instead) and pays one `DamageMultiple` per damage
  figure. Bullets can go on through bodies (`TGun.Pierce`) and a shot can shove survivors (`TGun.Knockback`,
  `EnemyMovementService.Push`). **A shot is a line from the head, not the camera's**: the point under the crosshair,
  shot from the head, climbs over the bodies behind or digs into the floor, so every gun's shot is lined up on the
  client (`GunsCore.LineUp`: still into the aimed body, through as many as its pierce allows, past floors and ledges,
  judged with the server's pad), and tracers are the head's line drawn from the muzzle. Client: `WeaponController`
  (trigger, tracers, flash, sound, kick; holding a gun, the body faces the aim with the cursor free too),
  `BodyPoseController` (every R6 body's sprung lean, legs turned toward the walk, a backwards walk clip when
  backpedalling, an armed body's arms and torso on its aim; others' aim relayed by `Weapons.Aims` from the camera sync),
  `ViewmodelController` (first person; `Viewmodel.md` is how to add or fix a gun's hold and measure it for the back).
  Console: `gun <name>` swaps the gun.
- **AbilityService** + **AbilitiesCore**: classes (`Data/Classes`, two abilities and an ultimate each; everybody is
  Human until a class is picked, `TProfile.SelectedClass`). The client sends a slot and its aim (`Abilities.Cast`);
  cooldowns, the ultimate's meter (kills, never time) and every effect are the server's. A Decoy is a lure
  (`EnemyMovementService.SetLure`: a target with its own flowfield that bodies in its reach prefer to any player);
  foam holds a body and makes it `Components.Brittle`; the Orbital Cannon lands where aimed, then goes after the
  nearest boss in its reach or the thickest crowd at a capped speed, and overkills what it touches. Client:
  `AbilityController` and `Utils/decoyFx`, `foamFx`, `orbitalFx`. Console: `ult` fills the meter.
- **DefenseService**: placement validated on the nav grid; barricades block nodes and are the barricade field's
  targets; turrets shoot the nearest enemy and credit their owner.
- **EquipmentService** (global) + **EquipmentCore**: pieces kept for good (`Data/Equipment`, `TProfile.Equipment` by
  Name; an `EarlyUnlock` piece is everybody's), one per slot, each shown on the avatar or not. A match reads what the
  worn ones add (`StatOf`: max health in CharacterService, armor on each blow, kill Gold in RoundService);
  **EquipmentDropsService** rolls a boss's pieces for every player as it dies. Every client draws everybody's shown
  pieces (`EquipmentWearController`: classic rigid accessories in `Models.Equipment`, welded by the attachment each
  names, which R6 bodies carry). Lobby screen: the classes screen's EQUIPMENT tab (`EquipmentController`). Console:
  `gear give <piece|all>` / `gear clear`.

### Enemies and navigation

This is the part that makes the game: keep its rules when the enemies change.

- **The cap is 255 alive, and it stays** (`EnemiesCore.MAX_ALIVE`): every living body carries its own hit-flash
  Highlight, and the engine draws at most 255 Highlights. **Nothing else may use a Highlight.** The game grows by
  enemy TYPES (behaviours, attacks, elites, bosses) and by health / damage / mix per wave, never by more bodies. Rigs
  are destroyed, never pooled; reserves are unparented clones.
- **The rig** is an R6 shape as ONE skinned MeshPart (`TData.TEnemyModel`, Models.md section 7): bones `Root` >
  `Torso` > `Head` > `Hair` / arms / legs; Root.Transform carries the world CFrame. **Every body is drawn up to the cap
  at once, so every triangle is paid that many times**; enemies cast no shadow. Clips are a shared set
  (`TEnemy.AnimationSet`), rotations only so they play at any size; each attack clip lands its blow at
  `EnemiesCore.ATTACK_CLIP_IMPACT` and is sped to the attack's Delay.
- **Clip switches are blended, never crossfaded or left to run out** (`GlobalClient.Utils.inertialBlend`, Animations.md
  section 17): a one-shot that runs out drops its pose in one frame and the engine's fade is linear. A fade asked of
  `EnemiesController` becomes a blend, every one-shot is watched to its end, and a hand-over the camera holds on (an
  intro's end) is authored into the clip instead.
- **A kill ragdolls** on the client (`Client/Utils/ragdoll`), colliding with the floor only (raycasts at
  `Workspace.Arena`), then sinks and is destroyed; `MAX_CORPSES` caps them. An **overkill** (a blow worth 4x max
  health, decided by `EnemiesService`) bursts instead. **Nothing may raycast or overlap-query an enemy**: ask
  `EnemiesCore.EnemiesSpatialHash`.
- **A boss is a giant under fire**: no flinch, no last-few outline and only a faint tint a blow; each bullet's light
  and sound land where it goes in (`EnemyImpacts.EmitBossHit`, from the client's own bullets), and the body reacts at
  each quarter of its health (`BossController.hurt`) and falls in slow motion (`TimeService.SlowMotion`). VFX.md 41.
- **Every boss warning is a dodge for a player who looks and a hit for one who doesn't**, measured, not felt: a 22
  stud/s player reacting in 0.3 s with 0.1 s of ping clears the worst spot near death, and one standing or strafing
  on is hit (a move that cannot catch either leads its target: `TEnemyAttack.Lead`). Wind-ups never go faster than
  `TEnemyBoss.WindupTempoMin`; the late fight grows by cooldowns. A run's warning is drawn as far and wide as it hits.
  PlanBosses.md, "Every warning is a dodge", has the method and the T-Rex's numbers.
- **ArenaCore** bakes `Workspace.Arena` into a LAYERED nav grid (up to 4 floors per 2-stud cell: decks, bridges and the
  ground under them) by raycasting once per match, then links floors (step up 2.5, drop 8, no corner cutting). A floor
  too high to step onto below head height is a wall. `Blockers`, `Caps` and any part players cannot collide with are
  not floor.
- **NavService** floods one flowfield per living character plus one for all barricades (Dial's algorithm, at most one
  flood a frame). "Nearest" is path cost, so a player on a deck reached by stairs is as far as the stairs make them.
  `enemiesUpdate` steers down the field, refuses any step onto no standable floor, and goes straight when point-blank
  on the same level.
- `Enemies.Positions` carries an `EnemyPacker` buffer, reliable and whole (an unreliable event's ~1,000-byte payload
  limit would force chunking): a 9-byte absolute record or a 6-byte delta from the last position sent, at most 2,299
  bytes at 255. Both ends keep that last position per id (the server's per-player `sentQ` in `AOIService`, the
  client's `netBase`), written only by the stream; a body with no send time (`sentAt`) goes absolute, so anything that
  forgets a body for a player must clear its `sentAt`. Bodies far from a player's camera are sent less often (every
  tick within 160 studs, the farthest a client animates, 0.15 s to 240, 0.35 s past it), bosses always every tick
  (`OutEveryTick`).
- **Only the nearest bodies animate** (`EnemiesController`): within an animation distance and the nearest
  `maxAnimated` of those (the radius shrinks past the cap), the rest hold their mesh's rest pose (`holdStill` blends
  them out) and play no attack clip; one past the distance is drawn on each packet's spot and skipped between packets.
  Bosses and driven bodies always animate and are seen to 400 studs. Every playing track is Animator work each frame
  (218 bodies, 420 tracks: 0.34 ms on a PC, ~20x on a phone): never start a looping clip on a body outside the set.

### What a client draws (graphics quality)

There is no graphics setting of our own: `GraphicsQualityController` (global) turns the player's Roblox graphics level
into a tier (levels 1-3 Low, 4-6 Medium, 7-10 High; Automatic is High on a PC, Medium on a phone, one tier down if the
place cannot hold 45 fps over its first 20 s) and a `Scale` (0.4 at level 1 to 1.6 at 10, 1 on Automatic). The norm
is the device's (PC / phone) and the slider moves it. New distances and counts a client spends on (bodies drawn or
animated, numbers, effects) read `Scale()` and follow `OnChanged`; never a settings row for them.

- **Every particle burst goes through `fxBudget.Emit(emitter, count, at?)`**, never `emitter:Emit`: scaled by tier,
  thinned with distance from the camera's focus (none behind it), and spent from one estimate of live burst particles.
  Ground warnings (`telegraphFx`) stay out: a warning is the hitbox. VFX.md section 5 has the numbers.
- The tier also switches the place's own Lighting (Medium: SunRays, DepthOfField off; Low: Bloom, shadows off).
- The measurements behind all of it, the harnesses to re-run, and how far ree / rur / ror match Studio:
  `performance/optimization-2026-11-26/RESULTS.md`.

### The lobby

`LobbyService`: pads under `Workspace.Lobby.Pads`, numbered by name order. The first player on an empty pad (walked
on, or put there by PLAY) is its host and picks size, map and access in the party menu; the rest join until it is
full, when the countdown drops to `PadsCore.FULL_COUNTDOWN_SECONDS`. A player on a pad is anchored there until EXIT.
The pads' rim and glow are built on each client (`LobbyController/PadArt`).

The lobby's screens (classes, weapons, index, quests, daily, settings, codes, shop) are one up at a time: opening one
from over another goes through `LobbyController`'s `swapTo` (the screen up leaves, then the new one comes in), and a
new screen joins `isPlayerScreenUp` and `closeScreens`. UI.md, "A screen's life", has the rest.

### UI and the top bar

UI is `vide` (`src/Global/Client/UI`: `Theme`, `Components`, `ConsoleUI`; the HUD in
`src/Game/Client/Controllers/HudController`). The current HUD is a placeholder; the real one follows `UIMatt.md`.
`UI.md` is Ballarc's UI method (benches, motion, juice): its lessons apply, its pixel look does not.

- Every icon is a rendered picture drawn as `Components.Picture(EIcons.X, ...)` (only Robux stays a flat glyph);
  `EIcons` is generated by `Assets/ui/rendered/build.py`; `UI.md` "Icons" has the rules.
- Corner brackets stand one distance off everything (`Components.Brackets`, never a number per screen), a picked piece
  closes its own brackets into an outline, and two pieces stand far enough apart for the worst case (a press with the
  hand on one): `UI.md`, "Brackets, picked and side by side", is the check every new piece passes.
- **A write anywhere in a ScreenGui lays out every visible element in it again**, the same value excepted
  (performance/runui-2026-11-09: ~1.15 us an element on a PC, the phone's biggest UI cost). So the HUD is three
  ScreenGuis by how often they are written (`HudController`'s `hudRoot`: calm `Hud`, `HudLive` for Wave, Items and
  Down, `HudTop` for flights, banners and screens): a piece that moves every frame goes in `HudLive`, never in `Hud`.
  An idle loop gets its own clock (`state.Breath`, not `state.Now`), a spring that can go back to 0 is a
  `Hand.Spring` (a bare vide spring heading to 0 never settles), a number label rewritten most frames has
  `AutoLocalize = false`, and a ScreenGui with nothing showing is switched off. Check a UI change's cost with the
  census probe (`performance/optimization-2026-11-26/harness/studio-hud-census.client.luau`) and its look with rur
  pixel diffs of `tools/uimatt` stories.
- `GlobalShared.TopbarPlus` is a vendored TopbarPlus v3 with local changes (Butler instead of Janitor, a `PixelSkin`
  feature that is Ballarc's look): update it by hand, never from Wally.

### Networking

Two Blink networks, each with its own **256-event id space** (ids are one byte; the 257th generates without an error
and breaks at runtime): `blink/.blink` for hot gameplay (both places), `blink/Meta.blink` for cold domains
(`Configs`, `Profile`, `Lobby`, `Console`), required as `GlobalClient.NetworkMeta` / `GlobalServer.NetworkMeta`. Domain
files live in `blink/Client` and `blink/Server`, each imported by one network, never both. Single-value payloads are
written bare (`data: boolean`): `(boolean)` does not parse. Blink comments are `--`, not `//`. Never use plain
RemoteEvents for game traffic.

The conch console (`GlobalCommandsService`, `ConsoleController`, `ConsoleUI`) opens on backquote for a player given a
role by their rank in group 34796361 (today only Admin 254 and Owner 255 reach a role), and for everybody in Studio
and the test places. Debug benches register their commands on it (`vfxbench`, `telebench`). The Game place's server
commands (`pause`, `timescale`, `enemy spawn|clear`) are in `Server/Services/CommandsService`; their argument types
are `Types/CommandTypes`, which both sides require.

### Data

`src/Global/Data/<Kind>/*.luau`: a typed local (`local data: TData.TEnemy = {...}`) returned frozen, so the analyzer
checks it against `TData`. Registered by `DataCore` (`Enemies`, `Defenses`: `ById` / `All`). Ids in
`src/Global/Types/Enums/Data`, never reused. Enemies and defenses name their models (`ModelName`) rather than holding
them, so data loads before the art is in the place.

## Performance Rules

Measured in this engine, not assumed. Harness, full tables, and where these rules disagree with
[luau.org/performance](https://luau.org/performance): [performance/15-luau-idioms.md](performance/15-luau-idioms.md).
Read it before changing a rule here.

### Loops and tables

- Prefer `for _, v in t do` (8-35% faster than `for i = 1, #t do`; `pairs` / `ipairs` within noise). Numeric loops
  only when the index is needed for more than reading `t[i]`, or for a range. Don't hoist `#t` into a local: the bound
  is evaluated once anyway, so it only adds a `MOVE`.
- Known count: `local t = table.create(n)` then `t[i] = v` (1.6-2.3x faster than `t[#t + 1] = v`). Unknown count:
  carry a counter (`c += 1; t[c] = v`) instead of recomputing `#t`. `t[#t + 1] = v` vs `table.insert(t, v)` is 1-9%, not
  where the time goes.
- `table.create(n)` or `table.clear(t)` reuse both beat a fresh `{}` by 1.3-1.9x and equal each other; prefer reuse
  when a table is at hand (no garbage at all).
- Use early returns to minimize nesting.

### Calls

- No helper from **another ModuleScript** inside a hot loop: ~15ns a call the compiler cannot optimize past a
  `require` (10k calls a frame = 0.15ms). A **same**-module helper costs nothing measurable, so this is no reason to
  inline by hand. Move the helper into the module, or hoist it to a local outside the loop (`local lerp = Tools.Lerp`,
  20-25% on its own).
- Call builtins directly, not as methods: `string.byte(s, i)` is 2.2-4.1x faster than `s:byte(i)` (the method form
  loses the fastcall). Localizing the builtin makes no difference.
- Hoist Instance property reads out of loops: `workspace.Gravity` ~40ns a read vs ~3ns cached, 15x. Every property read
  is a C++ reflection call, an order of magnitude over any Luau table or global access.
- Localize Roblox mutable globals (`game`, `workspace`, `script`, `plugin`, `shared`) only when a loop reads them tens
  of thousands of times (~0.7ns a read). Never localize non-mutable globals (`math`, `table`, `string`, `Vector3`,
  etc.): `GETIMPORT` resolves them at load, so localizing only adds a `MOVE`.
- Never use `getfenv`, `setfenv` or `loadstring`: they destroy the safe flag for the whole script, disable `GETIMPORT`
  for all globals and switch off inlining for the whole module.

### Objects and closures

- Constructors: `table.clone(STUB)` of a **metatable-free** module-level stub instead of a fresh table (1.4-2.6x faster
  on median, far steadier under GC). A stub carrying a metatable clones 1.5-2.4x slower.
- Needing a metatable: `setmetatable(table.clone(STUB), MT)`, same cost as the bare clone, ~2x cheaper than cloning a
  stub that carries it.
- Metatable OOP over closure OOP for objects made many times (e.g. ECS entities): closures copy methods into every
  instance, metatables share one table.
- `__index` straight at a table, one level deep, ideally the metatable itself: a three-deep chain costs ~2x, an
  `__index` **function** ~2-3x. Call `obj:Method()`, not `obj.Method(obj)` (1.1-1.5x).
- Read static fields off the class (`Class.Static`), not an instance (`obj.Static`): ~3x through `__index`.
- Never capture a local declared **inside** a hot loop, above all a mutable one (3.0-3.5x and 4.9-6.8x a plain call).
  A closure capturing nothing or only immutable module-scope locals is cached by the compiler (1.6x): no need to avoid
  it. In factories pass captured values as parameters (`self`) so Luau emits `DUPCLOSURE` (one shared function)
  instead of `NEWCLOSURE` (one per call).
- Pre-bind a table field to a local before a loop only when the loop reads it **multiple times** (`local originX =
  grid.OriginX`); a single read gains nothing and adds a `MOVE`.

### Math and directives

- Keep positions and directions as `Vector3`, not three numbers: one vector op beats three scalar ops by 2.1-3.3x, and
  building a `Vector3` in a loop is free (values, not heap allocations).
- `--!native` on parallel Actor scripts and math-heavy utility modules: 1.4-4.2x on code that stays in Luau
  (arithmetic, calls, tables), nothing on allocation-bound code, and **slower** Instance property reads and
  cross-module calls, so keep it off services whose hot loop is mostly engine calls.
- `--!optimize 2` does nothing here (already level 2): harmless where it sits, not an optimization to add.
- `task.wait()` over `wait()`.

## Logic & Syntax

- Assign with `if then else` expressions, not `and or`: `local value = if condition then a else b`, never
  `condition and a or b` (fails if `a` is false or nil).
- Test truthiness directly (`if isRunning then`, `if not isRunning then`); never `== true` / `== false` **in a
  condition**. `x ~= nil` where nil is the actual question (an optional value, or one that may legitimately be
  `false`); `x ~= false` for a default-true field (`if data.HasFoliage ~= false then`), which truthiness gets wrong. As
  a *value*, `params.Centered == true` is fine: the normal way to get a real boolean from a maybe-nil field.
- Invert and leave early: guard clauses at the top, one line each (`if not entity then return end`), so the body sits
  at one indent level. StyLua keeps them on one line (`collapse_simple_statement = "ConditionalOnly"`), Selene allows
  them (`one_line_if = "allow"`).
- Constant keys with a dot: `ESoundsIds.ClickHud`, not `ESoundsIds["ClickHud"]` (readability only: same bytecode and
  speed, `performance/15-luau-idioms.md` §10). Brackets for variable keys (`Lookup[EFoo.Bar]`).
- Never use Instance attributes (`SetAttribute`, `GetAttribute`, `GetAttributeChangedSignal`). Tuning lives in code,
  keyed by name where it must be per-instance (`MapsCore.MAPS`).
- `type()` for Luau types (`"string"`, `"number"`, `"table"`), `typeof()` for Roblox ones (`"Vector3"`, `"Instance"`),
  so the kind being tested is obvious at the call.
- A `Name` enum's value that is saved (a profile key) is a saved key: changing it renames it in every save, so it needs
  a `DatabaseService` migration; renaming the enum's key breaks every require (never do that).

## Module Layout

Every file opens in the same order, so anything can be found by where it sits:

1. The file header comment: what the module owns, in a line or two (rules below).
2. Services via `game:GetService("...")`; never `game.Workspace` and friends.
3. Packages (`ReplicatedStorage.Packages.*`), then project modules (Network, sibling Services/Controllers, Cores, ECS,
   Utils), then Types. One `require` per line, all at the top. Only two stay in the body: the dynamic one
   (`require(data.Module)`, the module a data table names) and the lazy one behind `RunService:IsStudio()`, which must
   not load in production.
4. Derived locals off the above (`Network.Server.Gifts`, `Players.LocalPlayer`, `Workspace.CurrentCamera`).
5. The module table, then its constants and module-level state (`Tune`, caches, connections).
6. The functions in three bands, then the `return`:
   1. **Public API** (`function Module.X`): what other systems call, what a reader opens the file for.
   2. **Internals** (`local function`): each above its first user, which Lua requires anyway (above its definition the
      name is a nil global that fails only when that line runs; `selene src` reports it as `undefined_variable`, so run
      it after moving a function). A helper a public function needs sits just above it; one only the lifecycles use
      goes last, just above them.
   3. **Wiring**: Ignis lifecycles (`OnStart`, `OnPlayerConnected`, `OnCharacterAdded`, ...), network listeners
      (`.On(...)`) and signal connections, which can call anything above.

   No forward declarations to get the API above its helpers (`local foo` at the top, defined below): a second list of
   names to keep in sync, and a missed `local` makes a global without an error. State built out of local functions (a
   table of callbacks) is an internal, not state. A big file in banner sections (`EnemiesController`) keeps them
   inside the bands: state sections, then function sections, grouped by topic. Class modules (`SpatialHash`, `Grid`)
   have no wiring and are sectioned per table. A `.client` / `.server` script is not reordered: its top-level
   statements run in file order.

Functions repeat that shape: guard clauses, argument defaults, locals, main logic. Return only when there is something
to return.

- A function reads in steps: one blank line between steps (load, rebuild a table, connect), none inside one, however
  short the function. Two blocks doing different things are two steps. Never two blank lines (StyLua collapses them),
  and not between every line: the guard clauses are one block, and so is a run of locals read together.
- A loop is a step of its own:
  - Its inputs and accumulators are the paragraph above it, with a blank line between. A single setup line stays
    attached: the `table.clear` directly above the loop that refills that table.
  - What comes after is the next step (the `return` of what it worked out, publishing a list it built, a guard on what
    it counted, the append a check-loop allowed). Only what closes the loop stays attached: `table.clear` of what it
    emptied, `debug.profileend`, releasing the lists it used.
  - A `return` after any block is its own step, with a blank line before it.
- No blank line between a local and the `if` that tests or builds it (`local bounds = ...` then `if not bounds`), nor
  between a get-or-create `if` and the line using what it made (`subs[player] = true`), nor inside a small block (an
  `if` branch, a short callback) or a tight loop body whose filters and work are one step.
- Past four or five parameters, take one table (positional mismatch gets likely). Except hot paths (`Grid`,
  `SpatialHash`, packers), where the allocation costs more than the risk.
- Comments say **why**, not what, next to the code they explain. One earns its place by stopping a mistake: an engine
  quirk ("the PlayerModule restores RotationType, so it is set every frame"), a rule a future edit could break, or a
  fact the code cannot show (a project setting, another system's behaviour). Delete what the code already says: a
  stale comment is worse than none.
- **The file header is short**: what the module owns, plus only the rules binding the whole file and facts from
  outside it. A reason for one function goes on that function. No implementation walkthrough, no list of what the
  file does not do, no design rationale.
- **Comments do not name the reference games** (Anime Zombie Survival, Ballarc, BeACastleLord): origin is history the
  reader cannot follow. Write the reason itself ("a kill that does not flash reads as a miss"), cite a measurement by
  its file under `performance/`, never list what was left out of the original. Name one only where the reader has to
  go there: an asset it owns or holds (group-owned clips, uploaded image ids, a model to insert from its place) or a
  vendored file.
- **A module's main chunk holds at most 200 locals** (Luau's register limit). Past it the file fails to load ("Out of
  local registers") and so does every module requiring it: one new `require` can take down every dependent
  controller. Near the limit, group tuning constants into frozen tables (`Tune`) keyed by constant name; never merge
  two unrelated locals into one.

## Systems

A system is a Service (server) or a Controller (client), registered with Ignis. **Services decide, Controllers
show.** A Service owns state and rules; a Controller owns input, camera, UI and presentation, asks a Service for
changes and never decides an outcome.

### Where new code goes

A module sits in the folder of what it **is** (Services, Controllers, Core, Utils), not the feature it serves. Then
take the first that fits:

1. **Part of a feature that already has a system:** add it there. Grep for whoever owns the data or the lifecycle (a
   global Service in `src/Global/Server/Services/` often does) before adding a peer.
2. **Tuning numbers:** constants in the owning module (`Tune`), or a frozen table in `Shared/Utils` if both sides read
   them. A number to change without a release goes in `MainConfig.json` behind an `EConfigKeys` key.
3. **Stateless helper:** a plain module beside its one user, or `Shared/Utils` once two systems need it.
4. **A new system**, only with all three: state others change only through its functions, its own lifetime
   (per-player setup and cleanup, timers, connections), and its own client requests.

A system whose functions are about two unrelated things, or whose tables other systems keep reaching into, is two
systems.

### Splitting a system across files

A system that grows a second concern gets a folder: `FooService/init.luau` is still one ModuleScript to Rojo, so no
`require` changes. Split by responsibility (lookup, validation and mutation, networking, presentation), not line count.

- `init.luau` is the only file Ignis sees: lifecycles, Blink listeners and state; it routes each request to a child.
- Children are plain modules: no lifecycles, connections or module-level state; they take what they need as
  arguments. They may require pure siblings and a shared `Types.luau`, never `init.luau`, never in a cycle.

This is the rule for new splits. The 1000-line Controllers already in the tree (`EnemiesController`) are not a bug to
fix in passing.

### Dependencies

- Point one way. If B requires A, A never requires B, at the top or lazily. Shared **state** goes in a leaf module both
  require; a **trigger** becomes a signal on A that B subscribes to (reuse an existing one first; never a signal with a
  single subscriber).
- Per-player and per-character setup and cleanup go through the Ignis lifecycles (`OnPlayerConnected`,
  `OnPlayerDisconnected`, `OnCharacterAdded`, `OnDataLoaded`, ...), not hand-wired `Players` connections.

### Trusting the client

Blink checks the **types** a client sends, not the **claim**. Every server `.On` handler starts from the sender's own
character entity and guards, one line each, that the request is possible now: has a character, holds the weapon, is
not downed, is in range, owns the thing, can pay. A handler that checks nothing says why in a comment (a cosmetic
relay, like `PlayerSync.CameraSync`).

- Never take a player, a currency amount, a damage figure or a result from the client. Take the intent (`slot`,
  `abilityId`, `choice`) and work the rest out on the server.
- Check a document's cache for nil in every handler, and never hold one across a yield: the player may have left and
  the document closed meanwhile.

## Naming Conventions

- **Folders/Modules/Classes/Functions:** `PascalCase`. **Variables:** `camelCase`. **Constants:** `CONSTANT_CASE`.
- **Types:** `TPascalCase` (`TBulletState`). **Enums:** `EPascalCase` (`EGameState`).
- **Booleans:** prefix `is`, `has`, `can` or `should`. **Async:** suffix `Async`.
- **Acronyms** as words (`HttpService`, not `HTTPService`). **Units** in the name (`speedStuds`, `timeoutMs`, `yawDeg`).
- Name things for what they are, not how they are used: `Catalog`, not `ShopHelper`.
- No abbreviations beyond the universal ones (`id`, `ui`, `dt`, `vfx`, `hrp`).
- **Files:** components/classes `PascalCase.luau`; utils `kebab-case.luau` or `camelCase.luau`.

## Before Calling It Done

No automated tests: a change is checked by reasoning, the linters, the headless checks, and playing it.

- Be able to say why the change is correct and where it would break. Passing the linters is not that: Selene cannot
  tell a spring that settles from one that flies off.
- Work numbers out in code, not in the reply (tuning values, ratios, unit conversions). `lune run file.luau` runs
  plain Luau and `require("@lune/roblox")` gives it `Vector3`, so a formula can be pasted straight from the module.
  Measured, not assumed.
- Run the linters from Tooling, and `tools/lune/sim.luau` after touching rounds, navigation, enemies or the packer.
- Lune's `@lune/roblox` CFrame is not the engine's (`CFrame.lookAt` faced backwards there, 2026-11-11): check vector
  maths in lune, orientation maths in a playtest (`run_luau_live` does plain maths on the server).
- Compile a big file you added a local to (`tools/lune/compile.luau`): Selene does not see the 200-local limit.
- **Look at it offline with `ror`, `ree` and `rur-native` on your own, without being asked** (Tooling, "Seeing effects
  and UI offline"); the user has had to ask in session after session. Anything seen gets rendered before it is
  reported: an effect or model with `ror render` / `ror video` (read the frames), UI with `rur-native render`, client
  Luau that runs without a server (a bench, a per-frame loop, an effect module) with `ree run`, and a sound that voices
  a move on a ror video of that move with the sound laid on (Sounds.md, "A boss or giant creature"). When Studio cannot
  playtest: render, judge, fix, then hand over; never stop at "waiting for Studio". Keep renders the user is shown
  beside the sources, in the kit's `preview/` under `Assets/` (e.g. `Assets/effects/pistol/preview/`), not in a
  scratch folder.
- Check a lifecycle or an order of events by logging it on both sides: wrap each hook on the module table (callers
  look the field up at call time, so the wrapper runs) and read the sequence back.
- A throwaway probe goes in `StarterPlayer.StarterPlayerScripts` and is deleted once its output has appeared (deleted
  straight after `start_playtest`, it is gone before the playtest copies the place and never runs). **Say so if one
  was running when the user was watching.** A probe needing `Network` requires it by the `StarterPlayer` path the game
  uses, and a controller by the `PlayerScripts` path, or it gets a second copy. A probe requiring a client module
  waits for `PlayerScripts:WaitForChild("GlobalClient")` first: a module loaded early can fail to find
  `GlobalClient`, the failed load is cached, and the controllers requiring it fail too.
- Several Studios can be connected to Tripwire at once (this game's Lobby and Game, the old places), all possibly
  titled "Place1". Check `list_studios` and pick by `placeId` (Places table) with `set_active_studio` before any edit
  or playtest: the active one is whichever connected first. Never edit an old place.
- Rojo can stop syncing without a word (it did twice on 2026-11-26): before a playtest that checks a change, look for a
  line of it in Studio (`grep_scripts`), and push the files with
  `performance/optimization-2026-11-26/harness/studio_sync.py <repo files>` (compares with disk). Never create a new
  module by hand in Studio: Rojo adds its own copy once it syncs, and two modules of one name break Ignis ("already
  registered") and every controller requiring them. Never push files another session is editing.
- Tripwire cannot start a playtest while Studio is minimized: `start_playtest` answers `started` and every later call
  says "No live server peer". Ask the user to bring Studio up, and delete the probe you created meanwhile.
- Say what was actually verified: linted, run headless, rendered in ror / rur, played in Studio, or reasoned only.
  "Not playtested" is a fine answer; leaving it out is not.
