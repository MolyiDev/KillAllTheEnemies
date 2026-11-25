# Bosses (plan)

Steps 1 and 4-6 of the order of work are built for the T-Rex (2026-11-24, "As built (code)" at the end). Sources are the three scene places in `RBXL/` (`PumpkinScene`,
`spiderscene`, `TrexCutscene(FullyDeveloped)`); renders of them as delivered are in
`Assets/models/Bosses/preview/scenes_as_delivered.png`. **The Skeleton T-Rex comes first.**

## The roster and the rotation

Every map has two bosses: a **principal** and the **filler**. A boss wave comes every 15 waves and they take turns:
wave 15 the principal, 30 the filler, 45 the principal, and so on.

| Map | Principal | Filler |
| --- | --- | --- |
| Pirate Cove | Skeleton T-Rex | Giant Spider |
| Grass Lands | Pumpkin Head | Giant Spider |
| Baseplate | none: a test map, gone from the lobby. Bosses come from the console there. | |

- `MapsCore.MAPS` gets `Bosses = { principal, filler }` (enemy ids), and `RoundCore.GetBoss(round, mapName)` becomes
  `Bosses[(round // BOSS_EVERY - 1) % #Bosses + 1]`. A boss whose rig is not in yet is skipped, so a map plays its
  principal every 15 waves until the Spider is in. `IntroRound` no longer picks the boss.
- The HUD's boss bar already shows the next boss's name. It also needs that boss's picture, not the fixed
  `EIcons.ZombieKing`.

## Removing the Zombie King

End to end: `Data/Enemies/ZombieKing.luau`, its picture in `Icons` / `EIcons`, and every place that names it.

- The id 100 stays retired in `EEnemiesIds` (ids are never reused).
- Saves: pre-release, so nothing is migrated. Its index and quest entries in a profile are left to the wipe.
- The places that use its picture as "a boss" (party map lock, index Bosses tab, lobby stats, equipment source) take
  the T-Rex's picture instead.
- Things the T-Rex takes over: the two boss quests (`QuestsCore` 10 and the other boss quest), the two equipment drops
  (Hip Pack, Knight Shoulders), and the five potions that brew from its souls.
- The Mutation and Index UI stories and `tools/lune/sim.luau` move to the T-Rex.
- `Goliath` and the `Enemies.Troll` sounds stay: the rig list in `Assets/README.md` still lists Goliath.

## The rig: the T-Rex fits the enemy contract with two changes

The T-Rex is already what the game wants: meshes bent by bones (29 bones, `body_1` > legs, spine, `neck_1-3` >
`head` > `mouth`), with an `AnimationController`.

- **Two skinned MeshParts, not 24.** One is the bone white, one the neon green, both on the same skeleton. The neon
  can't share a part with the bone because Neon is per part. That is about 3,700 triangles for one body on screen,
  against the zombies' budget for 255. The renderer and the hit flash (one Highlight on the Model) are checked to
  handle a second part.
- **A `Root` bone above `body_1`**, owned by the renderer as on every enemy (it carries the world CFrame). Front +Z,
  feet at Root's pivot.
- **Rescaled to about 0.7 of delivered**: about 13 studs tall and 33 long, against a 5-stud player and the Zombie
  King's 12. It still reads big. This is checked by a render beside an R6 body before anything is animated, and
  against the narrowest passage on each map's nav grid. Every stud distance in the clips is multiplied by the same
  factor. **Played at 0.875 since the first playtest** (2026-11-24, "a 20-30% more"): built and exported at 0.7, the
  template in the place `ScaleTo`'d 1.25.
- Its sources go in `Assets/models/Bosses/TRex/` and are uploaded by group 34796361. The delivered meshes belong to
  another group (9167302).

Later, the same contract for the other two. The Spider and the Pumpkin are rigid parts on Motor6Ds, played by a
Luau script that writes the joints from saved poses. In Blender each part becomes one mesh weighted 100% to its own
bone, and their saved poses become bone clips. That puts all three on one path: Animator-played clips and no
per-frame Luau. Planned scales: Spider about 0.5 (25 wide, 11 tall), Pumpkin about 0.75 (14 tall).

## The T-Rex's clips (Blender)

Authored in Blender (the live session), the way Animations.md section 7 does enemies.

- The meshes are Roblox mesh version 7 (Draco compressed). They are decoded with their skin weights, and the
  skeleton comes from the place.
- **Import check first:** the delivered intro is brought in as an action, played back, and compared against the
  place's own poses. Only then is anything authored.

| Clip | Use |
| --- | --- |
| Idle, Walk | loops; Walk on its stride at chase speed |
| Chomp | the bite in front |
| TailSweep | the sweep behind |
| Stomp, Quake | one stamp; left, right, left with the last the heaviest |
| ChargeWindup, Charge, Skid, ChargeTurn | crouch and scrape, the run, the braking slide, the turn into a second charge |
| Barrage | rears up and shakes its spines loose |
| DiveSink, DiveRise, Reassemble | sinks into the floor; bursts up under the target; shakes itself back together |
| Summon | the roar that raises the guards (the intro's roar, shortened) |
| Death | it falls apart; the R6 ragdoll can't take this body |
| Intro | the delivered one, rescaled |

Each attack clip lands its blow at `EnemiesCore.ATTACK_CLIP_IMPACT`. Each clip is rendered with `ror video` for you
before it's uploaded. The enemy design checklist applies: the body leads every move, a menacing stance, and every
stop carries momentum.

**As built (2026-11-24, not uploaded yet).** `Assets/models/Bosses/TRex/TRex.blend` holds the rig and all the clips
(plus `Barrage4`, the phase 2 volley). They are authored in `anim/trex_clips.py` and the intro is carried over by
`anim/intro.py`; `anim/clips.json` lists each clip's length, loop, ground speed and beat times. Renders are in
`preview/`. The `.blend`, `clips.json` and the uploaded clips are at 0.7; the game plays them at 0.875 (the template
`ScaleTo`'d 1.25, and the Animator scales every clip's translations with it), so the studs below are the played ones,
1.25 times the `.blend`'s. Facts the code steps need:

- **The rig:** 30 bones (`Root` > `Hips` > the spine, neck, arms, tail and legs, renamed from the delivered ones),
  two skinned meshes (`Bone` and `Neon`), at 0.875 of delivered: 14.8 studs tall, 42.4 long. Root is on the ground
  under the hips, not at the body's middle: the head is 23.5 ahead of it and the tail tip 18.1 behind.
- **The attack clips are authored at their real timing, with the blow on the attack's own wind-up**, not on
  `ATTACK_CLIP_IMPACT` (0.6). Played sped to 0.6, a 0.9 s bite would be squeezed a third shorter. The boss's attacks
  need an impact time per clip, so they play at speed 1: Chomp 0.9, TailSweep 1.0, Stomp 0.8, Quake 0.75 / 1.45 /
  2.6, Barrage releases 0.9 / 1.5 / 2.1 (/ 2.7), DiveRise 0.15 (the hips burst through the floor), Summon's roar 0.85.
- **The clips' ground speeds**, or the planted feet slide: Walk 16.25 studs/s, Charge 62.5 (the walk's stride at a
  run, a 0.6 s loop), in `TEnemyBoss.WalkSpeed` / `ChargeSpeed`. The body keeps 13 and 50; each clip is played at
  the body's speed over its own (0.8).
- **The bite:** at impact the snout is 26.9 studs ahead of Root and the jaw's underside 1.4 above the floor. **The
  sweep:** the tail tip is fastest crossing the line behind it, 18.3 behind Root and about 6 up.
- **ChargeTurn is a drift:** the game yaws Root 180 degrees (to its left) at a constant rate over the clip's 1.0 s.
  The feet are braced and scrape round with the body; it ends in the launch pose.
- **The dive:** DiveSink leaves the floor at 0.5 s and is entirely under it from 1.35 s; DiveRise starts entirely
  under it and lands at 0.85 s. DiveRise ends shaken loose, which is the pose Reassemble starts from.
- **Death** (4.0 s) is on the floor at 1.6 s and comes apart from there; it ends as a pile of bones lying still,
  and is held on its last frame. The pelvis, belly and ribs stay one piece (their skin is blended).
- **Intro:** the delivered clip at the new size. The body walks in from 15.75 studs behind Root and ends standing on
  it. The delivered camera keys are in the frame of the delivered model's pivot (its `RootPart`, at its feet's height):
  where the walk ENDS, 2.39 studs ahead of Root (`TEnemyBossIntro.ShotsAhead`). Taking it for where the walk started
  put every shot 14.5 studs too far back in the first playtest. One change: where the delivered jaw went 2.3
  studs into the floor (the head sweeping the ground before the roar, 7.0 s), the neck is lifted just enough.

## The T-Rex's attacks

### Why the reference bosses have the attacks they have

Survive a Million Monkeys' bosses, as the user describes them. While a boss is up the waves stop: no crowd spawns,
so the fight is the boss and whatever it brings. Each move answers a problem a boss in a co-op shooter has.

**The monkey boss**

| Its move | The problem it answers |
| --- | --- |
| Jumps out of view and lands on a player | Players outrun and kite a big slow body. Without a way to come to them, the boss becomes a health bar far away. A perch stops being safe too. |
| Throws bananas | Distance is safe from every melee move. A ranged attack gives the players at the back something to dodge. |
| Belly-flops forward | Point blank in front is where everybody shoots from. |
| Lands on its back | The counterpart. Front and back together leave the sides, a position you read and take. |
| Eats a banana to heal | A moment the party must burst it. |
| Summons four special monkeys and shields itself until they die | Every gun on the boss stops working: the party switches targets and spreads out. The fight's midpoint. |

**The gunner**

| Its move | The problem it answers |
| --- | --- |
| Six stomps in a row, each a shockwave to jump or outrun | A rhythm test: not one dodge but six, with two answers (jump each, or get far enough). |
| Sprays bullets at the player | Bullet hell: a dodge you keep doing with your movement, not one step out of a circle. |
| Blasts the ground three times, then a fourth with a small shockwave | A counted sequence with a finisher. The player learns the count, and the last beat changes the answer. |
| Hits in a rectangle in front with its gun | Point blank in front again, in a different shape. |

**The radioactive one**

| Its move | The problem it answers |
| --- | --- |
| Lobs radioactive waste off its back in an arc | Ranged, aimed at the player, slow enough to see coming. |
| Charges at the player | The gap closer. |
| Three floor punches, each a + (four cones, thin at the centre, wide at the ends) | A shape to read: the safe places are the diagonals, and the closer you stand the more room there is. Three in a row move the safe lanes. |
| A punch all around, then a blast off its back that scatters waste everywhere | A close ring, then the whole area: get out, then watch the ground. |

What all three have in common:

- **A way to come to the player:** a leap, a charge. Nobody kites a boss forever.
- **A ranged attack aimed at players:** bananas, bullets, lobs. Distance is never safe.
- **A close punish:** front, back, rectangle, or all around. Standing on it is never safe.
- **At least one sequence:** six stomps, three blasts and a fourth, three punches. A rhythm to learn, often with a
  finisher that is different.
- **Many answers:** step out of a shape, jump a ring, get far, find the diagonal, keep moving. Not the same dodge
  twice.
- **The monkey alone also has a goal-changer** (the summons and the shield) and a heal.

This is the checklist for every boss here, the Spider and the Pumpkin included.

### What makes a good boss (read on the web, 2026-11-24)

- **A boss is a test of the skills the game taught.** List the skills, then make one attack test each (Mike Stout,
  "Boss Battle Design and Structure", Game Developer).
- **Telegraph, attack, punish.** Every attack advertises itself before it hits; every attack has a clear answer, and
  many leave a window to hit back. "If you fail, you should know why" (Aviar dev blog). This game already has the
  telegraph: the ground warning is exactly the hitbox.
- **Don't let the players lock the boss out.** If they can keep it where none of its attacks work, give it a defence
  (a force field, a way out of reach) (Stout). Here that means kiting, answered by the charge; perches, answered by
  the dive; and focus fire, answered by the shield.
- **Escalate in beats.** The same behaviour from full health to zero is dull. A midpoint should raise the stakes, and
  the final stretch tests everything taught (Stout's beats; two or three phases is the usual count).
- **Stay inside the game's rules.** No hit bigger than a player's whole health, and no immunity that makes half the
  kit useless all fight (Josh Bycer, "3 Elements That Every Great Boss Fight Needs").
- **Die spectacularly** (Stout).

### The T-Rex's set

The checklist, answered with the T-Rex's own body: a skeleton (it can sink into the ground and pull itself back
together), green neon spines, a bite, a tail, heavy feet, and a roar. Nothing is a monkey's, gunner's or radioactive
boss's move with a new skin. It walks at about 13 studs a second, against the player's 22. Each attack leaves its own
ground warning in the boss colour, and each has a different answer.

Where the target stands around it decides most of what it does: in front, behind, beside or under it, or far away.

| Attack | Checklist item | When | What happens | Answer and punish window |
| --- | --- | --- | --- | --- |
| **Chomp** | close punish, front | target in front, under 14 studs | Cone in front, 14 long, 60 degrees, 0.9 s wind-up; the head drops and snaps | step out of its face; 0.8 s recovery with its head low |
| **Tail Sweep** | close punish, back | target in the rear arc, under 16 | Cone behind, 16 long, 120 degrees, 1.0 s | don't hang at its back |
| **Stomp** | close punish, under it | target beside it or under its body (neither the front nor the rear arc), under 10 | stamps; a full circle round its feet, radius 11, 0.8 s, no direction to read | get out from under it, any way |
| **Charge** | the way to the player | target over 25 studs away on its floor, or it has gone 6 s without reaching anyone | crouches and scrapes (1.2 s, a Line 8 wide to the target), then runs the line at about 50 a second, hitting whoever is on it, and skids to a stop | sidestep the line; the skid leaves it open about 2 s |
| **Spine Barrage** | ranged, aimed at players | players over 20 studs, cooldown 8 s | rears up and shakes; one green spine lands on each player's spot, 3 times, 0.6 s apart, each with its own circle (radius 5, 1.0 s warning) | keep moving; each player dodges their own |
| **Fossil Dive** | the way to a player it can't walk to | target on a floor it can't path to for 4 s; cooldown 15 s | sinks into the floor (it can't be hit), a green crack runs to the target, and it bursts up at the nearest floor it can stand on: circle radius 12, 1.4 s warning | run out of the circle; it then stands 1.5 s pulling its bones together |
| **Raise the Guard** (once, at 60% health) | goal-changer | the health line is crossed | roars (a ring you jump, the intro's roar), four Fossil Guards rise around the arena, and a green shield takes every hit until all four are dead; a beam runs from each guard to it | split up and kill the guards; the boss bar shows them as four marks |

The Charge is the gap closer; the Dive only answers a player it can't walk to (a deck the nav grid does not link to
it, or one it is stuck under), so the two never compete for the same moment.

Escalation:

- **Phase 1 (100% to 60%): the test.** Chomp, Tail Sweep, Stomp, Charge and Spine Barrage, plus the Dive when it's
  needed. These teach every place to stand.
- **Midpoint (60%): Raise the Guard.** The target switches and the party spreads out.
- **Phase 2 (under 50%): the same moves, expanded.** Each new version extends a move already learned, never a new
  instant hit:
  - The Stomp becomes the **Quake**: left, right, left, each a circle round its feet, and the third also sends a
    ring out to 35 studs. That is the sequence with a finisher: get out from under it, then jump the ring or be far.
  - The Charge chains: it skids, turns and charges again, once.
  - The Barrage fires 4 spines instead of 3.
  - Every cooldown is 20% shorter.
- **Death:** it falls apart into its bones, with the overkill burst's weight.

Rules it keeps: no hit is worth a full health bar at the wave it appears, so damage is checked against player health
at wave 15 and 45. The shield never stays up more than 25 s: if the guards aren't all dead by then, they crumble and
it drops. The guards are 4 bodies against the 255 cap. Every landing is a floor enemies can stand on, since there are
no player-only perches.

### The boss wave is the boss alone

Today a boss wave also pours its ordinary bodies (`RoundCore.GetCount`: "A boss round has these and its boss on
top"). To match the reference, a boss wave spawns no crowd: the boss and its guards are the whole wave. Bodies still
alive from an earlier skipped wave stay, frozen through the intro. Skipping is already closed while a boss is up.

Numbers are a first pass, to tune in a playtest, at the 0.875 scale and re-measured off the clips.

New in the code:

- **`Behind`** on an attack: its Cone or Line points opposite to the way the body faces, and it is taken only when
  the target stands in the rear arc. The telegraph is the same shape turned around.
- **`Beside`** on an attack: taken only when the target is in neither the front nor the rear arc (the Stomp).
- **Health phases** on a boss's attacks: taken only under a health fraction, or once when a line is crossed.
- **A sequence:** one attack repeated a set number of times, apart in time, its last beat able to add a ring (the
  Quake). The same thing gives the volley: one Slam circle at each player in range, repeated.
- **The `Charge` kind:** after the wind-up the body really runs the telegraphed line (EnemyMovementService owns the
  move), hits whoever it passes, then bleeds its speed off in a skid. A wall or a ledge on the line ends it early,
  with the same skid. It can chain once.
- **The dive:** the body leaves the spatial hash while under the floor (nothing can hit it), moves to a standable
  floor at the target, and comes back with a Slam there.
- **A boss wave with no crowd** (`RoundCore`).
- **Summons with a shield:** spawns the guards (a guard type in `Data/Enemies`: an existing zombie rig in bone white
  and green), and holds the boss immune until they are dead or the cap runs out. The beam is drawn by the client.
- `tools/lune/sim.luau` covers each one.

## The intro cutscene

Every time a boss arrives (yes, again each rotation), for every player, including downed ones.

**Server (a small `BossIntroService`, started by RoundService's boss spawn):**

1. **Wait out any open hand.** A boss never arrives while upgrade cards are up: the spawn waits on
   `TimeCore.IsHeld`, a shared state both sides read, so no dependency cycle.
2. **Place the boss on the map's boss stage.** This is an open spot and a facing per map, kept in `MapsCore` by name
   like the rest of the map tuning. It is not a part, so "no spawn parts" still holds. The intro's camera keys are in
   the boss's own frame, so every shot is raycast from the boss against the arena once, and a stage that clips a
   shot is moved.
3. **Show it to everyone** with `AOIService.SubscribeEveryone`, so every client has the rig.
4. **Hold the match**, using a new reason in `TimeCore` beside the upgrade pick's hold. It stops at once rather than
   easing, because a slow ease would let a blow land. Already stopped by a held clock: enemy movement and attacks,
   wave spawns, guns, abilities, turrets, health regen, walking and jumping. Players are also made unable to take
   damage, as a gate in `CharacterService.Damage`, until the hold lets go.
5. **Fire `Bosses.Intro`** (boss id, instance id) to all, and let go after the intro's length.
6. A player who joins mid-intro is simply held with everyone else and skips the show.

**Client (a `BossIntroController`), porting the T-Rex scene's timeline:**

- The intro clip plays on the boss's rig at full speed. It is the one clip exempt from the held clock (EnemiesController
  rescales every other clip by the time scale).
- The camera timeline is the delivered shots, handheld drift and impact shake, scaled to the new size. The camera
  takes over from CameraController and hands back.
- The HUD is hidden. Other players and ordinary enemies stay in the shots, frozen where they stood.
- The grade (colour correction, depth of field) is restored after.
- The letterbox and the title card ("SKELETON T-REX / THE BONE TYRANT") are rebuilt in vide, in the designer's style.
- Effects (dust, ground rings, roar breath, kicked-up rocks) are ported to the project's toy-brick look (VFX.md).
- Sounds (steps, stomp, roar, chomp): none come with the scene. Candidates go through a listening round with you
  before anything is wired.

## Order of work

1. Rotation in `MapsCore` / `RoundCore`, the T-Rex's data stub, and the Zombie King's removal; sim and linters.
2. T-Rex into Blender: decode, import check against the intro, `Root` bone, two parts, rescale. A render beside a
   player for your sign-off on size. **Done 2026-11-24.**
3. Clips: Idle and Walk, then the attacks, then Death and the rescaled Intro, each rendered for you. **Done
   2026-11-24, after three review rounds** (Animations.md section 16 is the recipe and the user's corrections).
4. Upload the rig and clips as group 34796361; place them under `Models.Enemies` and `Animations.Enemies.TRex`.
   **Done 2026-11-24** (Animations.md section 16, "Exporting").
5. The attack code (`Behind`, `Beside`, health phases, sequences, the charge, the dive, summons and shield, the boss
   wave with no crowd), the Fossil Guard, and the boss bar's shield marks, with sim coverage. **Done 2026-11-24.**
6. The intro: hold, damage gate, event, controller, title card, effects; then the sound listening round. **Done**,
   sounds included (2026-11-25: six rounds, `Assets/sounds/Review/TRex/`, wired through `Client/Utils/trexSounds`).
7. Boss stages on both maps, with the camera clearance check. **Picked at run time instead** (below).
8. Playtest in Studio, two players. **One player only so far**, on the test map.

Then the Pumpkin Head and the Giant Spider, by the same steps: copy `Assets/models/Bosses/TRex/` (the `anim/`
library is rig-agnostic except `build_rig.py`'s bone map, the leg solver's digitigrade foot and the arm check's
pieces) and start from Animations.md section 16's order of work.

## As built (code, 2026-11-24)

- **Server.** `BossService` runs every boss's fight: it picks the move by where its target stands (`BossesCore.Facing`),
  holds the body while busy (its `AttackWindup` > 0; `enemiesUpdate` never starts a boss's attack), moves it itself
  through a charge (run, skid, chained turn) and a dive (`Tags.Submerged`: out of the movement update and the spatial
  hash, immune), raises the guards and holds `Tags.Shielded` (EnemiesService refuses every blow and sends
  `Bosses.ShieldHit`). Warnings go through `EnemyAttacksService.Telegraph` (any yaw, delay and length). A charge's run
  hits what its front meets and throws the player (`Bosses.Knocked`, laid on by their own client).
  `BossIntroService` places and holds (`TimeCore.IsCutscene`, stopped at once; `CharacterService.Damage` refuses
  meanwhile) and fires `Bosses.Intro`. `RoundService` brings the boss on through it, never over an open upgrade hand,
  and a boss wave is the boss alone.
- **The stage is picked, not kept in `MapsCore`.** Round the party (50, 40 or 62 studs, twelve directions), facing them,
  scored on floor for the walk-in and the body and on the intro's shots seeing the boss past the arena. Every map gets
  one with no hand data.
- **Client.** `BossController` plays each move's clips at speed 1 (`Bosses.Move`, `EBossMoves`), draws runs, turns and
  the dive exactly (`EnemiesController.Drive`), and throws the weight: footfalls on the clips' own step times
  (`TEnemyBoss.WalkSteps`, read off the `.blend`), stomps, the skid's scrape and catch, spines flying to their circles,
  the dive's crack, the shield bubble and the guards' beams, the fall. `BossIntroController` ports the delivered
  cutscene (shots in `BossesCore.INTRO_SHOTS`, handheld drift, jolts, grade, letterbox and title card in vide).
  `EnemiesController` plays a set's Death clip instead of the ragdoll and holds it, never parks a driven body, lights
  a guard's glow on its own Highlight, and a boss flinches at 0.15 of a zombie.
- **Console:** `boss trex` brings it on as its wave does (stage, intro, fight); `bossmove <clip or kind>` makes the boss
  up take that move next, out of range or cooling down.
- **Still to do:** its picture (the boss bar and the other "boss" spots still show `EIcons.ZombieKing`: a T-Rex icon
  needs takes from `Assets/ui/rendered/generate.py` and a pick); the Giant Spider and
  the Pumpkin Head (the T-Rex stands in on both maps' lists); a two-player playtest.
