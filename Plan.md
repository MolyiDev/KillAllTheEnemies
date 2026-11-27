# Plan

Where the code stands, what it still carries from the anime game it started from, and what to bring over from the
old places.
Architecture is CLAUDE.md; this is status. Started 2026-11-20.

## The target

*Survive a Million Monkeys* with more enemy types (reference video: `../Ballarc/SurviveAMillionMonkeys.mp4`;
`../Ballarc/PlanTutorial.md` section 2 studies its first session second by second). What it does, and the closest code
here:

| Survive a Million Monkeys | Here today | To do |
| --- | --- | --- |
| Intro cinematic over the load ("HOLD TO SKIP"), the player's own avatar in it | - | Intro on arrival |
| "SURVIVE WAVES 0/5", then "WAVE n", "NEXT WAVE IN", "SURVIVE 7s" | RoundService / RoundCore waves, Preparing -> Fighting, START and SKIP votes | Wave goal with a count, a final timed wave |
| Run cash (`$`) from kills, spent on cards: Shotgun / Minigun, Health, Grenade, Barricade, Airstrike ULT | Run Gold from kills and clears; turret and barricade defenses; the old place's 20 guns (one held, `gun` command to swap) | Guns, upgrade cards (weapon tiers, health), grenade, an ultimate: from the old Game place |
| Barricades, placed on the ground | DefenseService: placement on the nav grid, barricades block nodes and draw the crowd | Keep; new models |
| Hordes climbing stairs and decks of a brick island, dropping in around the players | NavService flowfields over a layered nav grid; 255 alive; ring spawns that drop in and fade | More enemy types (below) |
| Classes in the lobby: Survivor, Medic, Engineer, Juggernaut, Bomber, Pyromaniac, Outlaw; upgrade per item | - | Classes and weapon shop from the old places |
| Guide portrait with two lines at the bottom centre, one lit button, no menus before the fun | - | Tutorial (PlanTutorial principles) |
| End screen: gems earned, back to LOBBY | MatchEnded -> lobby | Results screen (UIMatt.md) |

## Carried from the anime game, to replace

Each is a working placeholder; nothing here should ship as it is. The anime powers, the gacha, melee combat with
its dash and the schoolyard map were removed on 2026-11-20.

- **Anime effects** (coin sprites in `CoinsController`, the white-hot gradient in `DamageNumbersController`): the
  new effect language is VFX.md section 30 (glowing pixels and stud pieces). The pistol's shot and the enemy bursts
  are in it (2026-11-20, sections 30 and 31); these two are still to redo.
- **Zombie enemies** (`Data/Enemies/*` names, `ZombieNormal` model, `ZombieR6` clips, `tools/rig` painting): new
  monsters with a stud look; the R6 skinned contract (Models.md 7-8) and the clip set can stay.
- **Placeholder HUD** (`HudController`): becomes the designer's UI (`UIMatt.md`).

## More enemy types, same cap

"More enemies" is variety, not count: the cap stays at 255 alive (one hit-flash Highlight per body, the engine's
ceiling). Waves escalate by health, damage and the mix of types. The enemy pipeline already supports a type as data
(`Data/Enemies`, `TData.TEnemy`: attacks Melee / Explode / Slam / Shockwave with ground warnings, bosses); a new
behaviour is a new attack kind in `enemiesUpdate` / `EnemyAttacksService`. The old game's types (Walker, Runner,
Bomber, Brute, elites, MiniBoss, Boss) are the first list to bring over.

`EnemiesCore.MAX_ALIVE` is the ceiling; `Enemies.MaxAlive` in `MainConfig.json` lowers it live without a release.

## Before it plays end to end

Assets the code expects (each is a missing-asset warning until it is there, never an error):

- `ReplicatedStorage.Models.Enemies.<ModelName>` rigs and `ReplicatedStorage.Animations.Enemies.<Set>` clips
  (Models.md 8, Animations.md 7).
- Players are R6 and animated by Roblox's default Animate (as in the old places). The code's own directional walks
  (`MovementController`, `ReplicatedStorage.Animations`) came from games with R15 bodies:
  their clips are R15 and never apply here. Own R6 clips later need an empty Animate back in the project files.
- `ReplicatedStorage.Models.Defenses.*` (a coloured block stands in).
- `Workspace.Lobby.Pads` in the lobby place.
- `TEST` place ids in `EPlaceIds` once a test copy exists, and product ids in `EProducts`.

## Ballarc systems to port when the game needs them

Built and shipped in `../Ballarc/src/Global`, not brought over yet because they are styled for its pixel look or tied
to its economy. Port the logic, restyle the view:

- `Client/Controllers`: `SettingsController` (+ `UI/SettingsUI`), `InputTypeController`, `GamepadFocusController`,
  `HapticsController`, `MusicController`, `TeleportCoverController`, `CameraZoomController`.
- `Server/Services`: `AnalyticsEventsService` (funnels, economy events; `../Ballarc/Analytics.md`), `BadgesService`,
  `LeaderboardService`, `LoginStreakService`, `ShopService`.
- `FirstShared/LoadingScreen.client.luau` (both places) and `Client/Utils/loadingGate`.

## The old places

Game 104435679031452 (same universe) and the old lobby (`LobbyOld.rbxl`, published over since) hold an earlier version of this game. Dumped offline
to `research/OldGame` / `research/OldLobby` (CLAUDE.md, Tooling) and reviewed on 2026-11-20:
`research/Review-Combat.md`, `Review-Horde.md`, `Review-Lobby.md`. Each has an inventory with numbers, what is good,
what is unsafe (file:line), a port plan onto this architecture and the assets it uses. The headlines:

- **Guns ported 2026-11-20** (Review-Combat 4.6 steps 1, 2 and 4: data, server fire, tracers, recoil, arms aiming, first person). Still to do from it: lag rewind (a fixed pad today), the loadout and swapping, ammo if wanted, the upgrade cards, classes. **Combat's fire flow is the model**: the client sends intent (direction, time),
  the server re-casts every pellet, rewinds enemy positions to what the client saw, decides damage and batches
  it. Fix on the way: the 8-stud client muzzle (shoots through thin walls), the client-chosen
  spread seed, the client's ADS flag, client-side dashes. 20 guns, 9 classes / 36 abilities, 12 upgrade cards; ammo
  and reload exist but are switched off, every gun is automatic, the free Starter SMG out-damages every Common and
  Rare. Order: Review-Combat 4.6 (one pistol against the crowd first, then prediction / tracers / recoil, lag
  compensation, viewmodel, cards, classes).
- **The old match was not wave survival** but an "Expedition" (objectives, danger levels, dropship extraction); its
  wave code never ran past wave 1. Its enemies (12 types, all melee) top out at 207 alive, under the cap. This repo's
  enemies, navigation and attacks are already better. Worth taking (Review-Horde 3): difficulty modes with reward
  scale, kill streaks, run modifiers, an elite / mini-boss mix, Hunters (go for the isolated player) and Ghosts
  (blink to the target), stuck-body culling with requeue, congestion cost in the flowfields, danger lighting, a
  "try again" vote.
- **The old lobby never saved**: it opened a mock store, so nothing bought there persisted. Its server-side purchase
  checks, "quest progress = stat now minus stat at roll", `LastMatch` kept until dismissed and settings stored only
  when not default are worth keeping. Port order (Review-Lobby 4.2): classes, loadout and weapon shop, match
  results, level, settings, tutorial, quests, daily rewards, spin, Robux shop, head tags, analytics. Dropped: Black
  Market / crafting / materials / tokens / crystals, Workshop, the like pad, AFK World, the server browser.
- **Game passes** (old universe, still on it): 2X SPINS 2037986450, 2X XP 2037002480, 2X CASH 2036078508, VIP
  2036606478. No developer products.

### Decisions for the user before porting

1. **Currencies**: the profile saves Gems; UIMatt's screens also show coins, energy, tokens and credits.
2. **Class roster**: Survive a Million Monkeys' 7 or the old place's 9 (Review-Combat 1.2, Review-Lobby 1.3).
3. **In-run upgrades**: Gold spent in a shop (the HUD's buyable upgrades), the old bar-fill pick 1 of 3 (UIMatt's
   Upgrade Selection after a wave), or both.
4. **Gun models**: several look like CS:GO skins; check where they came from before uploading them again.

### Maps

`PirateCove` and `GrassLands` are in the new Game place's `ServerStorage.Maps` (copied 2026-11-20): spawn parts
removed (enemies drop in around the players), the barriers renamed `Blockers` (the nav grid is their footprint:
~400 x 400 and ~315 x 170 studs), PirateCove's `Sea` in `Backdrop`, a SpawnLocation at each map's old `PlayerSpawn`.
Still to do in Studio: delete the Highlight on `PirateCove.Island.Model."Cube.004"` (Tripwire cannot address a name
with a dot); decide whether the far scene `Island.Model` (1,700 studs west, its own water) stays as scenery or goes;
run a perch check (Maps.md) on both.

## Performance to measure in Studio

Lune numbers are interpreter numbers. In Studio, on the real map:

- `NavFlood` (profiler label): ~6.5 ms per flood in lune for 6.8k nodes. PirateCove's grid is ~41k cells (GrassLands
  ~13k), so expect several times that: if it shows in the frame, flood over several frames or coarsen far cells.
- `EnemiesUpdate`: ~4.6 ms per 10 Hz tick in lune for 255.
- `EnemiesRender` on a mobile device at the cap, and with `MAX_CORPSES` (40) ragdolls falling at once.
