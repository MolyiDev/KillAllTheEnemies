# Sound design in Last Wave

> **Carried over from Ballarc (Last Wave) on 2026-11-20.** The method, the engine facts and the measured lessons
> apply here; the old game's look does not. Kill All The Monsters is not pixel art and not anime: maps are stud-style
> (LEGO-like bricks at real scale), UI is sleek and modern (`UIMatt.md` is the designer's spec). Sections named after
> a Last Wave weapon, boss or screen are worked examples. A path that does not exist in this repo (`Assets/...`,
> `tools/vfx/...`, a `src/Survivors/...` module) is in `../Ballarc`; `../Anime Zombie Survival` holds the enemy rig,
> map and burst pipelines this repo's `tools/` came from.

Read this before choosing or changing audio in Ballarc. These rules come from the user's listening reviews,
not from a preference for any particular sound pack. The aim is satisfying feedback that matches the action,
its material, its size and its importance. A successful asset load and a matching loudness number do not
establish that a sound feels right.

The current source-owned bank is `Assets/Sounds/Feedback.model.json`, mounted in both places as
`ReplicatedStorage.Sounds.Feedback`. Its source files, upload IDs, playback settings and volume targets are
recorded in `Assets/Sounds/manifest.json`. Original game sounds also live elsewhere in the Studio place;
the feedback bank is not the entire game's audio inventory.

## 1. Keep the identity the user has already chosen

- Preserve existing attack voices when adding coverage. The user specifically caught replacements of Mortar
  Hat's launch and the original gunshots. Original Mortar Hat launches, Revolver shots and Shotgun blasts
  remain their baseline voices (the Mortar Hat's blast was replaced by the user's own pick, 2026-11-11: section 3's
  "Mortar Hat").
- Salvo already sounds special because many original Mortar Hat launches overlap. Rapid Fire gets its
  identity the same way from the original Revolver shots. Do not put a generic activation jingle over them,
  debounce their original overlapping voices, or replace each shot to invent a new effect.
- "The others are good" means keep those choices. Do not restart a complete redesign after every criticism.
  The approved Boots dash/blink/Stampede family, Shield Rally/dome family and Aura force pulses are examples (the Boots and Greatshield sets were later reopened
  by the user for their pixel effects).
  Check the latest manifest and audit rather than restoring an older candidate by name.
- Filling a silent action and strengthening an existing one are different tasks. Add a deliberate layer or a
  stronger version of its own timbre when appropriate. Do not silently substitute a different base attack.
- The original Greatshield template has Volume 0. Its asset remains; audible ShieldBite/ShieldHeavyBite
  layers were added at the jaw snap. A muted placeholder is not proof that the basic attack has audio.

## 2. Match the physical action; avoid unrelated music and comedy

| Context | Good starting point | What failed here |
| --- | --- | --- |
| Dash / recoil movement | Fast air displacement, pressure rush, short whoosh | A jump boing or rising game-note sequence |
| Sustained ground slide | Continuous friction scrape, a steady loop with a short fade and subtle speed response | Repeating an impact, an activation jingle, or looping while stationary or airborne |
| Teleport / blink | Short wind/force displacement | Dizzy-spin cartoon flourish |
| Shield planted into the ground | Ground/stone strike, then low pressure/energy expansion | Collectible stingers, a little tune, pitched bubble-like power-up |
| Shield support / Aura buff | Brief low force pulse, restrained nonmusical texture | A melody, alert sequence or electrical buzz unrelated to the desired feel |
| Heavy ground attack | Dense low/mid impact, short debris/rumble tail | A small tap or a thin high-frequency pop |
| Weapon ready / mode change | Cocking, chambering, catch, taut string or mechanical click | Generic power-up jingle or long synthetic scan |
| World objective taking damage | Impact appropriate to the actual representation | Error-message beep; assuming a physical cart when the current Convoy is a beam/sphere |
| Coins, score, rewards, quest/UI confirmation | Readable ticks, small pitch rises, short positive/negative cues | Applying the combat "no tunes" rule blindly to reward feedback |

The game can use retro sounds and physical stock sounds together. A folder called Retro, Positive Sounds,
Weird Sounds or Mechanical Noise is not evidence that a file suits the action. Pick the material/envelope
first. Do not choose a musical stinger merely because its name says power-up, or an enemy cry for a weapon
because its name says attack. Reserve beeps/alarms for an actual warning or UI indication. Avoid gratuitous
cartoon wobble, chirps, boings and electrical crackle in combat abilities.

## 3. Power has a hierarchy

An ultimate needs to feel larger than a normal attack. Matching every cue to the same body level loses that
hierarchy. Build weight with a fast transient, dense low/mid body and a controlled tail; lowering pitch alone
or extending the duration is not enough. Retain enough midrange attack to read beside the normal shots.

- Boots Stampede steps reuse the normal BootsImpact file at 0.72 playback speed and a 3 dB higher measured
  body target. This corrects the rejected version that was higher pitched than the ordinary step.
- Shovel's ultimate strikes should follow the same principle: deeper/heavier than its own basic strike,
  rather than a different, thin high-pitched explosion at the basic target.
- Death Line is a giant shot. Its release must be a massive initial **BOOM**, not a quiet pop, a funny laser
  chirp or a sound sustained for the whole moving rectangle. The user first requested full coverage, then
  explicitly corrected that choice. The current intent is a short, weighty launch and a silent continuation.
  When the effect became a held 3D ray (2026-11-09) the user found the sub-only shot "not at the level of the
  effect" and asked for more power, more volume and a "DEATH RAY" sound. They picked review B (a deep blaster boom
  and a Mecha laser beam) layered over the previous shot, built into one file by
  `Assets/Sounds/Review/DeathRay/make_release.py`: 2.1 s, the beam fading out while the ray is visibly held, still
  silent for most of the 5.7 s sweep. The previous shot is in `Revisions/DeathLineFire-v4`.
- **The Death Line's blast (2026-11-16)** is a second layer for the ground, not more boom: the release already has
  the boom, so the blast took the fast hit with the most midrange (Pixel Combat `Mecha Intense Hit`, 28% at 150 Hz-2
  kHz) at -6, 3 dB under the release. The user said "Add the sound", so it shipped unheard with its round beside it
  (`Review/DeathRay/` round 2); a sub-only wave (98% under 150 Hz) was left as a candidate, not the pick.
- A long visual is not permission for a long sound. Use a loop only for a genuinely sustained action or a
  charging phase that benefits from one. Buff activation can be brief while empowered hits carry its weight.
- Nuke and large landing bursts need more weight than small impacts. Frequent echoes sit below their parent
  attacks. A power difference should come from both timbre and gain, without overpowering every other event.

### Loudness: where a new cue belongs

Every number here is **in-game dB**: the loudest 100 ms window after a 10 kHz low-pass and K weighting,
times the template Volume and the call-site scale. World (Effects) cues are mixed to mono and lowered by the
12.5-stud default zoom (`ZOOM_DEFAULT` in `src/PlayerModule/CameraModule/ZoomController`, about -0.75 dB).
UI cues are measured in stereo with no distance loss. These tiers were set by ear on 2026-11-02;
`Assets/Sounds/volume-audit.json` has every sound's current value. Place a new cue by its role:

| Role | In game | Reference sounds already there |
| --- | --- | --- |
| Personal reward, box reveal | -4 to -6 | HealthGain / ShieldGain -4 (approved), rarity reveals Common -6 up to Godly / Secret -4 |
| Strong release, ultimate | -3.75 to -10 | Death Line shot -3.75 (asked louder), Aura Singularity blast -6.8, Nuke -8.8, Aura Shockwave (both layers) -8.8, Mortar Strike -9.8 |
| Basic weapon shot | -6 to -11 | Shotgun -6, Revolver -10.4, Mortar Hat -11 |
| Ultimate / ability ready | -6 / -8 | UltimateReady above AbilityReady |
| Ability or one-off world cue | about -12 | most of the Feedback bank |
| UI confirmation, quest event | -10 to -11 | QuestStarted / Completed -10, bank UI cues -11 |
| Frequent stream (many per second) | -11 to -15.5 | EnemyHit -11, counter ticks -14, small impacts -15, EnemyDeath -15.5 |
| Echo, hover, subtle | -17 to -20 | BootsEcho -17.8, HoverHud -20 |

The user judged EnemyHit at -8.7 and EnemyDeath at -13 "a little loud"; a frequent stream must sit below a
one-off of the same weight, because many of them overlap. Earlier passes at -23/-26 and then -13/-16 dB in
the old metric were both too quiet. Do not go back to either.

What the old numbers got wrong, so it is not repeated:

- **Measure what is heard.** Plain K weighting counted energy above 10 kHz as loudness. ShieldGain read
  -10 dB, had 81% of its energy above 10 kHz and was inaudible in game; it actually played at -22.5. Before
  trusting a clip's number, check its energy above 10 kHz, and compare it against a sound the user knows
  (EnemyHit) at its real Volume and call-site scale, not against another number.
- **Stereo world cues are mono in game.** Summing both channels read stereo Effects files 3 dB too loud, so
  they were set 3 dB too quiet.
- **No -3 dB peak cap.** It held cues such as HealthGain below their target; EnemyHit at Volume 2 already
  peaks above 0 dBFS in game. Roblox Volume goes to 10. The ceiling is now only a +6 dB sanity bound, and
  RevolverDeadEye, ShotgunBuckshot and MortarDetonatorArm still sit 2-5 dB under target at that bound.
- **A loudness number is not a listening check.** Say so when a volume has only been measured.
- **A long tail at the right number is louder; `balance.py` now measures it.** The 100 ms window let the Pixel
  Combat Boots set (2.5 s clips near full level for 300-860 ms, replacing 90-150 ms hits) measure like short hits,
  and they sounded far louder ("the boots sounds are too loud", 2026-11-11). The body level is now the 100 ms
  window or the 400 ms window + 2.5 dB, whichever is louder, so a sustained cue is lowered automatically. Cues
  heard and kept at their 100 ms level carry `legacyBodyMetric: true` (Quest/Challenge stingers, Nuke, Death Line,
  Aura abilities, pickups and others); do not remove it without a listening check, and never put it on a new cue.
- **Cues played at one moment are levelled as one sound.** Two layers each at the target sum ~3 dB over it. A
  second layer sets `layerOf: <head>`, the head sets `layerTargetBodyDb` (the pair's role level), and each layer's
  own `targetBodyDb` only sets the balance between them. `balance.py` fails when two `PlayWorldCue` calls with
  different cues sit within two lines of each other in `src` without one group. AuraShockwave and ShieldDome pairs
  are grouped but pinned (legacy head); their `layerTargetBodyDb` records the sum they were approved at.
- **A per-strike or per-step cue is a frequent stream even inside an ability or ultimate** (Stampede steps -14,
  Excavator strike and landing -13, Earthshaker strike -13, Boots step -16 and echo -19 for their ringing tails).
  `balance.py` cannot see call rates: put a new one in `FREQUENT` or give it a frequent-tier target.

### Aura and Fragmentation: audible versions (2026-11-09)

The user found every Aura ability and Revolver Fragmentation almost inaudible. Each one was a 0.2-0.4 s retro
blip. Several measured on target (-11) and still disappeared: Shockwave measured the same as MeteorImpact but read
smaller, because the meteor is a longer, fuller explosion. **A short blip at the right number is still too small
for an ability.** Picks came from three listening rounds (`Assets/Sounds/Review/Aura/`, `Review/Fragmentation/`).
The old files are in `Revisions/Aura-v1` and `Revisions/Fragmentation-v1`.

- Fragmentation: Free Sounds Pack `Sci-Fi Gun 1 Reload`, a two-stage mechanical load with real midrange.
- Shockwave: two layers that each roll one of four takes per cast (below). Blast: Gamemaster
  `fireball_blast_projectile_spell_02-05`. Body: Gamemaster `explosion_large_01/06/10`, `explosion_small_03`, at the
  same level. A single fireball take was rejected: its details stood out after hearing it over and over. Single
  `energy_blast_large` takes were "too cartoonish", and a Forge powerful impact read as a sword hit.
- Magnetism pull: Gamemaster `magic_conjure_charge1_01`. The first picks (reversed whooshes, time-warp casts) read
  as whooshes, not pulls; a conjure charge reads as a pull.
- Magnetism freeze (new): Gamemaster `ice_blast_projectile_spell_01`, on AuraAbilityFx's Frost beat (`Sound`
  field), so it follows Duration and is cancelled with the beat. It plays even with particles off.
- Resonance: Gamemaster `energy_blast_small_03`. Singularity charge: `magic_conjure_charge2_02` from 0.45 s.
- **Resonance's ring (2026-11-16, round 4 D)**: `AuraResonanceRing`, Pixel Combat `Mecha Engine Burst` 001-006 as six
  rolled takes (no regions: they hit within 10 ms), -14 (a frequent stream, one a pulse for 5 s). AuraClient.Attack queues
  it on the pulse's game-time queue to land with the echo's front (the Ring's lifetime x 8 / 16, then the Echo's x 5 / 16,
  ~0.37 s), at the disc. Queued from Attack, not PlayPulse: the bench's pulses stay silent, and Weapon Opacity hiding the
  echo does not mute it. Not yet heard in game.
- Singularity blast: the user asked for one sound with the blast of `cyberpunk_explosion_003` and the echo and tail
  of `sci-fi explosion_005`. `Review/Aura/make_singularity_release.py` builds it (crossover at 0.75 s).

### Boots Fault Line (2026-11-10)

Fault Line replaced Chainstep (a teleport) as the Boots' third ability. Its cast plays `BootsFaultLine` (Gamemaster
`rock_smashable_hit_impact_large_01`, -11) as the tear opens; when the ability ends, `BootsFaultErupt` (Pixel Combat
`Eruption` 002, with 005 and 006 as takes, -12) plays as the tear erupts. Both shipped at the user's request before
listening; `Assets/Sounds/Review/Boots/` has the alternatives. Chainstep's swoosh is in `Revisions/Chainstep-v1`,
out of the bank. The user picked Momentum C, Pixel Combat `Nova Whiplash` 001 ("feels super powerful"), over the
0.26 s twig whoosh (`Revisions/Momentum-v1`). They then reopened the older Boots sounds (step, echo, Shockdash,
Stampede and its steps): approved for the old effects, they don't fit the pixel ones. Round 2 picks: the step and
echo are Pixel Combat `Small Flare` (six takes; the echo plays the same uploads at 1.15x), Stampede's steps `Cruncher`
(six takes), and Stampede two layers played together (`Crunchy Burst` + `Mecha Engine Blast` as BootsStampedeBody).
Old files are in `Revisions/Boots-v1`. **A dash sound must be as fast as the dash** (0.25 s): every round 2 dash was
rejected as too slow; round 3's pick is Pixel Combat `Noise Zap` (six takes), whose body ends by 0.31 s. The
step's late takes were fixed with regions (section 4, "Measure every take's onset"). Shockdash's six takes all build
over 40-60 ms to -10 dB, evenly, so they were left alone; the rest (Stampede, its steps, Fault Line, Momentum) hit
within 12 ms.

### Yo-Yo (2026-11-11)

Every Yo-Yo cue was replaced for the pixel effects, from one review round (`Assets/Sounds/Review/YoYo/`, picks in its
README; old files in `Revisions/YoYo-v1`). Mostly Pixel Combat, avoiding the families the Boots and Shovel ship. The
beats the effect draws play from `YoYoFx`, not `YoYoClient`, so they land on the beat: the apex ting (or the heavy slam),
Counterweight's clack 0.15 s after the cast, the colossal's landing, the vortex pulse on every damage tick and the burst
when the colossal is home. Those beats run on game time, so a level-up pause holds them back; a test that stubs the
server's pause still has the client paused.

- **A merged pick is a layer group, previewed as it ships.** "A merged with D's then" became a head cue and a
  `layerOf` layer played on the same line pair, levelled together to the head's `layerTargetBodyDb`, so each layer sits
  1-2 dB under its solo preview. `Review/YoYo/render_shipped.py` writes each merge from the bank at its shipped volumes
  (`*_SHIPPED.wav`, at the round's shared gain) so the user can hear the merge they asked for, not the two halves.
- **Read an ambiguous merge back.** "A for the first part and merge it with B for the then" was read as A's then and
  B's then together; the README says which reading shipped and what to drop if the other was meant.
- **One upload per file.** A file used by two cues (the heavy throw's takeoff, also the colossal's at 0.85x; the
  thud, the heavy slam and a pulse take; the detonator, in two bursts) is uploaded once and its id reused
  (`Review/YoYo/uploads.json` maps library file to id; `ship_round1.py` builds the manifest and model from it).

- **Tether became a pluck (2026-11-16).** The cast keeps its scrape; the landing of the wave (the hit) borrows
  `YoYoHeavySlam` as a placeholder on the strings, the ring and the colossal, so no unheard sound shipped. Round 2
  (`Review/YoYo/round2`, `make_round2.py`) holds the candidates for two new cues, the pluck and the ring under Around
  the World; wire only the pick, in YoYoFx's landing beats.

### Greatshield (2026-11-11)

Every Greatshield cue was replaced for the pixel effects over two rounds (`Assets/Sounds/Review/Greatshield/`, picks
and the user's words in its README; old files in `Revisions/Greatshield-v1`). The user asked for **bass impacts** for
the chomp, the Bite and the Charge slam after a round of punchy midrange snaps and blasts. Shipped: the chomp is a
Pixel Combat `Gut Punch` with Gamemaster heavy kicks on top (six takes each), the Bite the chomp's punch at 0.8x
with a Forge powerful impact and a Pixel Combat `Bass Hit`, Rally `Mecha Morale`, the slam a bass hit with a metal
thud and a rock smash ("B with a dirt / rock sound"), Bastion Gamemaster's sci-fi shield boom and power-up, the dome
break `Laser Impact` with a glass break, and a new **ShieldHit** (below).

- **Time a moment to the animation, not to the button.** The first Charge start "doesn't sound anything like what the
  player does in the animation, he grabs the shield and puts it in front then rams forward". The Start animation's
  keyframes, read in a playtest (`KeyframeSequenceProvider:GetKeyframeSequenceAsync` on its AnimationId, the Handle
  pose per keyframe), put the shield in front at 0.38 s. The pick is three layers on those beats (a lance swing
  peaking at 0.38 s, a bass punch on the plant, a large pass-by for the ram), baked into one file by
  `Review/Greatshield/make_charge_start.py` so one cue keeps the beats.
- **A whoosh placed to peak on a beat keeps its lead-in.** The late-hit rule (section 4) trimmed the swings' and
  rushes' build-ups and moved their peaks off the plant. A layer that builds into its beat is played from its start.
- **Pin down which shield before wiring a hit sound.** "Use the same sounds for the hits when enemies hit the shield"
  was said in the Bastion line and meant its dome. It first shipped on every hit the Greatshield soaked on the player
  and the user heard it "when the player is being hit, the ultimate was not even used". ShieldHit (BeACastleLord's
  Core shield hit: this library's `Hits/Glitch` Epidemic Sound Debris Hit Short 03, six takes, over Glitch Impact
  Thud, three takes) plays at the dome on `Weapons.GreatshieldDomeHealth`, which the server sends every 0.1 s only while
  enemies bash it, at most once per 0.2 s. Read a request in the line it was said in (section 4: "Pin down which
  event the user means").
- **A weapon's sound lists live with its effects.** `GreatshieldFx.Sounds` holds every Greatshield moment as the cues
  heard together (a head and its `layerOf` layers) and `GreatshieldFx.PlaySound` plays a list whole, for the client
  and the bench alike. balance.py's adjacent-call check cannot see a list, so a new layer goes in the manifest group
  and the list together.
- "Bite: E and D" was read as one merge of both previews (their shared bass hit once). If it meant rolling between
  them, the two would be takes of one cue instead.

**Rounds 3 and 4 (2026-11-12): the moments the effects review asked for** (`Review/Greatshield/`, README "Round 3"
on): the user found the Charge's grab "not even hearable", Bastion silent where the animation grabs the shield and slams
it ("some dirt sounds would be nice"), the run quiet between its start and its end ("the footsteps ... thicker or more
stronger"), and asked for a sound when enemies hit the shield during the run. Shipped, all moderation Approved:

| Moment | Cues (layers play together) |
| --- | --- |
| Charge grab (round 3 B) | ShieldChargeGrab, BeACastleLord's equip grab (raised copy, below), a layer of ShieldChargeStart; the start plays from 0.15 s (round 4 B) so its swing follows the grab sooner; group -7.03 |
| Bastion grab (round 3 B) | ShieldBastionGrab, BeACastleLord's other equip grab (raised copy), -11 |
| Bastion dirt (round 3 C) | ShieldDomeDirt, BeACastleLord's building-landing rock crash (PM `Rock_Impact_Carsh_Big_Cinematic_41`), in ShieldDomeSlam's group, -6.12 |
| Charge steps (round 4 D) | ShieldChargeStep (Pixel Combat `Thud`, six takes) + ShieldChargeStepDirt (NOX grass jump landings, six takes), -13, FREQUENT |
| Rams (round 3 D) | ShieldRam (Gamemaster `kick_heavy_impact_02-07`, the chomp kick's uploads) + ShieldRamDull (Forge `Impact_Dull`, ten takes: BeACastleLord's Core hit), -14, FREQUENT |

- **New sounds asked for in an effects review still get a listening round first.** Round 3's sounds were first picked
  and wired unheard; the user: "You should had made me a round3 ... not add them right away", and pointed at
  BeACastleLord's grabs (its sword cinematic, its gift). Render candidates (the obvious pick as one of them, the user's
  other project's files when named, copied unchanged from `/home/molyi/Projects/BeACastleLord/Assets/sounds`) and wire
  only the pick. The rejected placeholders are in `Revisions/Greatshield-r3-placeholders`.
- **A file that starts late is silent where the motion starts.** ShieldChargeStart's swing is inaudible before 0.355 s
  (it builds to the plant at 0.38 s), so nothing played as the hand took the shield. A grab layer fills it; the user
  then wanted the swing "sooner" after the grab: a PlaybackRegion from 0.15 s, no new upload.
- **Ship a pick at the level it was previewed at.** A new layer in an approved group gets the preview's level less the
  head's present shift, and the group's target becomes the preview's sum (`ship_round3_picks.py`), so neither the new
  layer nor the approved head moves. Adding any layer to a group otherwise pulls the approved layers down.
- **Moving a layer in time changes its group's sum.** Starting the Charge start 0.15 s sooner overlapped it more with
  the grab; their sum read 0.45 dB louder and balance.py pulled both down. The group's target went up by the same.
  After any region or timing change in a group, compare the volumes with the preview's.
- **A source too quiet for Volume 10 gets a raised copy.** BeACastleLord's Epidemic Sound backpack grabs sit ~30 dB under
  the library (body -41 dB); at Volume 10 they played 8-13 dB under the preview. The bank file is a gain-only copy raised
  to a -1 dBFS peak (`Review/Greatshield/loud/`). Check `afterBodyDb` against the target in `loudness-report.json`
  whenever a volume lands on 10.
- **Grass under a step, not stone.** The game's floor is grass: Pixel Combat `Hard Step` with Gamemaster dirt landings
  "sounds like concrete or stone". The Thud "gives the shield vibe"; grass jump landings carry the ground.
- **A merge offered is not a merge taken.** Asked to "merge D and B" for the rams, the merge previewed in three balances
  lost to round 3's D alone. Keep the unmerged pick in the comparison.
- **A review script never reads the live bank.** Its "@Cue" layers read the manifest at render time, so re-running round
  3 and 4 after the picks shipped rewrote the files the user had heard (the new grab where the placeholder was, the
  start's new region skipped twice). Both now pin the bank as heard (`make_round3.PINNED`, archived placeholders) and
  re-render byte-identical. Rounds 1 and 2 still read the live bank: do not re-run them.

### Mortar Hat (2026-11-11)

Every Mortar Hat moment was reviewed for the pixel effects in one round (`Assets/Sounds/Review/MortarHat/`, picks and
the user's words in its README; old files in `Revisions/MortarHat-v1`). The launch keeps the original MortarHat voice
(section 1) with a pixel flare over it; the blast's original ExplosionEnemy was replaced at the user's pick (D) by
MortarImpact + MortarImpactBody. The fall whistle stayed. Two new cues: MortarDetonate (the plunger press) and
MortarFinal (the last bomb). `MortarHatFx.Sounds` holds each moment as a list, as GreatshieldFx does.

- **A chain is heard as a run.** "Not just casting every sound at the same moment, somewhat like the shard sounds or
  enemy hits": many blasts going off within a few frames stack into one wall. MortarHatFx's `chainPop` queues each
  pop at least 0.075 s after the last, a little higher and quieter each time, at most ten a run (pooled per take,
  since PlayWorldCue has no pitch). Use it for any burst of many identical hits.
- **A landing sound starts on its hit.** "The sound has some silence on the start": a layered impact for a visual
  landing is baked from each layer's hit (cut where it is last 24 dB under its peak), not from the file's start.
- **Salvo carries the new launch too (2026-11-12).** "Make the first ability sound be also the new Launch sound,
  because it used the old one too": a Salvo's shells leave on one frame, so the original launch stacked once per
  shell while PlayWorldCue's 35 ms gap let only one flare through, and the volley sounded like the old one.
  `MortarHatFx.PlaySalvoFlare` gives each shell its own flare (pooled per take, at most six, 0.045 s apart, each a
  little quieter, pitch within 6%); the original still stacks per shell (section 1). Any cue that must sound once
  per projectile on one frame needs the pooled path, not PlayWorldCue.
- **One run shape for both.** The chain's pops and the Salvo's flares are the same thing, a `TRun` (a cue's takes
  pooled, a gap, a cap, how long a run lingers) and one `queue(run)` that says when the next play is due; each caller
  only picks its pitch and level from `run.Count`. A new "many at once, heard as a run" sound is one more `newRun`.
- **Moderation can reject a take.** Two Flare Ignite takes came back Rejected ("Asset is not approved for the
  requester" in the playtest log). Check `get_asset` for every upload before calling a cue shipped; drop a rejected
  take rather than re-uploading it.

### Shotgun (2026-11-15)

The Shotgun's sounds are reviewed for its pixel effects in `Assets/Sounds/Review/Shotgun/` (picks and the user's words in
its README; old files in `Revisions/Shotgun-v1`). Round 1 shipped Blast C (the original voice kept, a Pixel Combat `Bit
Bomb` layer on every shot, the Stomp's too: ShotgunClient `playShot`), Buckshot B and Overdrive Cast A (two baked files,
the cast raised to the ultimate tier, -7).

- **A layer 6 dB under the shotgun is not heard.** The voice measures -5.2 in game, the loudest basic shot; every
  round 1 candidate for the Stomp and the Overdrive burn and shots sat at -11 to -17 under it, and the user: "the
  shotgun sound is louder than them". A cue played on the same frame as the shot (the Stomp's rise and dive) or right
  after it (the landing, the Overdrive shot layer) is levelled against the shot, not against the role table alone.
  Round 2 sets them at -5 to -8 (the burn loop -12).
- **A pass-by peaks late; the dive is over by then.** The body lands 0.35 s after the dive's shot. Round 2 dives that
  built to a peak at 0.4-0.8 s measured on target and were still "no volume compared to the actual shotgun shot": in
  the dive's own 0.35 s they sat 10 to 25 dB under it. Measure a cue in the window its action lasts, not only whole.
- Round 2 shipped Buckshot F (an "epic recharge": grab, slow rack, flare), the rise (Propulsor Ignition), the Overdrive
  burn (a loop ShotgunClient owns on the body, faded with the fire, paused with game time) and the Overdrive shot (a
  fireball and a spark on every shot under Overdrive, one group). Round 3 reopens the dive and the landing.
- **A low-end peak holds a cue under its target; give it `peakCeilingDb`.** Round 3's dive (a deep whoosh) and landing
  (an earthquake) peak 12-14 dB over their K-weighted body, so balance.py's +6 dB bound shipped them 4.4 and 1.3 dB
  under the picked previews. A baked limiter cannot fix it: the peak is the same broad low swell as the body. A
  manifest `peakCeilingDb` raises the bound for that cue alone (here 10.5 and 7.5, what their peak needs). Read
  `peakLimited` in loudness-report.json after every `--apply`.
- **TimeCore.OnTimeScaleChange fires before IsPaused is set.** A handler pausing owned audio reads the scale it is
  passed (`<= 0.01`), not `TimeCore.IsPaused`.

### Layered cues and alternate takes (how Guns N Goblins does it)

GnG's FMOD bank builds each big sound from layers, and a frequent layer rolls one take per play.
`python3 Assets/Sounds/Review/gng_bank_layers.py [regex]` prints every GnG event whose samples match, with its
layers and takes; its header records the bank layout it relies on. Look there first when the user points at GnG. Its fireball explosion is one of five Gamemaster
fireball blasts over one of three grenade explosions. Its large explosions stack two to five sounds. Use the same
recipe here when one take repeated is noticeable:

- A template's child Sounds are its alternate takes (manifest `takeOf`). `SoundsCore.PlayWorldCue` rolls one per
  play, never the same take twice in a row. Each take is its own manifest entry and file, balanced by `balance.py`
  like any cue. Only the world-cue path rolls takes.
- A second layer is a second cue played at the same moment (`AuraShockwave` + `AuraShockwaveBody`), so the two
  layers combine freely.
- GnG's own sample files (grenade explosions, the zapsplat shockwave) exist only as extracted game assets marked
  "prototype only". Do not ship them; use the user's library files (Gamemaster is the same source for most of them).

**A PlaybackRegion end is a hard cut.** Previews that cut a tail at -30 or -35 dB under the peak were heard
stopping short ("cuts off at the final without fall off"). Let a one-shot decay to its file's own end; set a
region only to skip a lead-in. Check the file's last 50 ms is far below its peak (these were -69 dB or lower).

### Running a listening review

The Aura review (`Review/Aura/make_review.py`, `make_round3.py`) is the template for the next one:

- Give each moment 3-5 candidates, chosen by envelope and spectrum first (where the peak falls, what share sits
  at 150 Hz-2 kHz), then by name. Include the current cue at its shipped level and a reference the user named.
- Level every candidate with `balance.body_level_db` (not a copied 100 ms window) and sum layers before levelling,
  so a sustained or layered candidate previews at the level it ships at.
- Render every candidate as it would ship (its region, speed and level) and keep ONE shared gain across all
  previews and all rounds (-6.3 dB here), so a later round still compares with an earlier one.
- To judge repetition, render a sequence of several casts that rolls the takes the way the game would. A
  single preview cannot show that a take wears thin; the user caught it only by listening over and over.
- Keep each round's files in `roundN/` and log the picks and the reasons in the review README. Reasons in the
  user's words ("sounds like a whoosh, not a pull") are what pick the next round's candidates.
- A weapon's review script that imports the Aura's helpers (`from make_review import ...`) must not itself be named
  `make_review.py` for another script to import: Python finds the importer first and the import fails. Load it by
  path (`importlib.util.spec_from_file_location`), as `Review/YoYo/render_shipped.py` does.
- Downmix stereo with `pan=mono|c0=0.5*c0+0.5*c1`, as `balance.py` does. FFmpeg's `-ac 1` reads correlated stereo
  about 3 dB louder, which made two current cues look 3 dB hot in the first render.

### Editing the bank by script

- `Feedback.model.json` and `manifest.json` are written with `indent=2` plus a trailing newline. Rewriting either
  with any other indent reformats the whole file (3,400 changed lines for one cue). Diff before moving on.
- `balance.py --apply` writes Volume into nested take Sounds as well as top-level templates.
- Moving a cue to a new file: reset its PlaybackSpeed to 1 and its region unless the new file needs them. The old
  Singularity blast had been played at 0.85x; carried over, that would have slowed the new composite.

### Win box reveal: keep the original sounds (2026-11-02)

The win box / lobby box screen (`winBoxScreen`, `winBoxCard`, `winBoxCardSealed`) keeps its original
ChestJump, ChestItemCycle and ObjectChange voices. A full set of eight retro replacements (open, deal whoosh, card
deal, flip, reel tick, stamp, breach, slam) was wired, played and rejected as "worse than before", then
reverted. The files and ids are in `Assets/Sounds/Revisions/WinBox-v1`. Do not swap these voices again unless the
user reopens it; if a moment there is silent, look for why the existing sound does not play before replacing it.

### Lobby reuse and review boundary (2026-11-06)

The user first authorized reusing existing game sounds, then replaced several review clips and explicitly
approved adding the revised selection, with the scrap choice delegated. The approved source list and current
implementation are in `Assets/Sounds/LobbyReview/README.md`. New, unfamiliar future candidates still need
local listening review before integration; copying a file alone is not approval.

- Original ChestBanish was missing only in Lobby. Restore the existing asset, not a replacement voice.
  Its Lobby-only source is `Assets/Sounds/Lobby/ChestBanish.model.json`, mounted directly under Sounds
  by `lobby.project.json`; the manifest/raw original are beside it. It preserves the verified Game asset,
  Volume 0.9 and base rate 1, with UI routing. The Game original remains Studio-owned and unchanged.
- Compare actual source hashes before deciding that a candidate needs uploading. Quest-ready reuses the
  existing QuestBegin. The first loadout candidate reused BarrierCollect, but the user's revised selection
  now uses `sfx_sounds_pause7_out.wav` as LoadoutApplied. BarrierCollect/pickups stay unchanged.
- Seven approved cues live in `Assets/Sounds/Lobby/Feedback.model.json`, mounted only in Lobby as
  `ReplicatedStorage.Sounds.Lobby`: AchievementClaimed, InvitationReceived, GiftReceived, LoadoutApplied,
  RerollConfirmed, ActionFailed and StashScrap. Their raw files, IDs, source hashes and per-instance volumes
  are in that folder's manifest; its loudness report uses the same measure as the shared bank. Do not add
  these assets to the Game place's preload. All templates/voices route to UI, at base rate 1, without loops.
- The user chose coin cluster 5 for invitation arrival, fanfare 1 for confirmed gifts, pause 7 in for
  confirmed rerolls and pause 7 out for loadout confirmation. The retained Shiny_object/error3 files cover
  achievement claims and generic lobby failures. Scrap uses single-shot 1 from the four approved options:
  a 139 ms hit with lower/mid body, at the confirmed stack crunch. Codex banishing keeps original ChestBanish.
- Loadout feedback follows a matching targeted LoadoutsCore.OnChanged after a local request. Full snapshot
  syncs carry nil and stay silent; hidden/closed Codex and replies older than five seconds do not play.
  No timer or per-frame scan is needed. A switch's active-slot echo and following snapshot play once.
- Generic lobby refusals and the kicked-from-run notice now use the approved ActionFailed; the originating
  screens share that name/gain so uiSound coalesces the notice with the local refusal. Skill-tree refusals
  and kick arming keep original BuyRefuse; SkillTreeUI passes it as the notice's optional sound override.
  Keep normal party departure's MenuOut. NotificationUI gates both display and sound during Ascension.
  AchievementClaimed overrides only that confirmed claim's generic toast accent, preserving payout audio.
- Reroll confirmation is part of the authoritative update: DailyQuestsUpdated includes the rerolled tab
  (Daily/Weekly, empty normally), and DailyDealsLoaded includes isRerolled. Only successful manual rerolls
  set these fields. Client handlers forward them on existing signals; visible matching UI refreshes then
  plays RerollConfirmed. Initial load, progress/reset sync, canceled payment and other tabs stay silent.
  Both Blink networks must be regenerated together after changing those payloads.
- **A UI cue never borrows a weapon's cue.** The shop box carousel's step whoosh played `BootsMomentum`, so the Boots
  round (2026-11-10) swapped it for Nova Whiplash too and the user heard the shop change. It is now `ShopBoxSwitch`
  here: the old twig whoosh's upload, Volume and speed unchanged (`Revisions/Momentum-v1`), so it plays as before.
- Seven approved assets were uploaded to group 35115431 and passed Roblox moderation and controlled Studio
  preload/playback checks. Prior review metadata is archived under `Revisions/Lobby-review-v1`. Keep the
  protected win-box voices, soundtrack, shared-bank gains and intentional slide silence.

## 4. Timing comes from the action, not the button

- Pin down which event the user means before wiring. "Health / shield increase" meant the **max** health /
  max shield going up from an upgrade, item or trait (`PassivesCore.OnPassiveStatChanged`), not regen,
  lifesteal or shield recharge (`Healed` / `ShieldHealed`, every 0.5 s). Those stay silent.

- Play on the actual visual/authoritative moment: jaw snap, fired shell, stuck shell, ground contact,
  dome raise, teleport shockwave, recall, collection arrival or confirmed claim result.
- Ability callbacks run on **both StartAbility and StopAbility**. Check the corresponding active flag before
  playing an activation cue. A release cue belongs in its release branch. Do not double a cast on stop.
- Shield Charge and Mortar Detonator accept a second press. Repress must not play another initial launch or
  arming cue. Keep the per-weapon guard and clear it on stop/removal.
- Gate sounds behind a valid action/model/root. A missing target or a rejected reward claim must stay silent.
- Snapshot shell payload at spawn: a heavy shell can land after its buff ends. Preserve the original launch
  and impact and add the heavy payload's intended impact weight.
- Mortar sky shells start 200 studs overhead, beyond the 150-stud world-cue range. Their incoming warning
  plays over the landing site, not at an inaudible spawn position.
- Aura ultimate start/release must have a fast attack. The rejected slow power-on swell lagged behind the
  immediate reaction. Current force hits begin promptly and decay in a fraction of a second.
- Long source files may have silence or windup. Author a PlaybackRegion to align the actual hit rather than
  delaying the action, and measure the selected region. Do not alter the raw WAV just to trim it.
- **Measure every take's onset, not only the first.** Takes of one family are not cut alike: Pixel Combat `Small
  Flare` 001 hits at 3 ms, but 002-006 swell quietly (about -22 dB under the peak) for 130-145 ms first. Rolled one
  per step, five plays in six came late, and the user heard "some steps" trigger after the effect. Report each take's
  time to -10 dB under its own peak (5 ms RMS window); takes of one cue should land within ~25 ms of each other. A
  quiet swell is not silence, so start the region at the last point still 24 dB under the peak, a few ms before the
  hit, not at the hit itself (a cut into loud material clicks). The steps' takes 2-6 (and the echo's, same files) now
  start at 0.112-0.133 s and reach -10 dB in 7-23 ms (2026-11-11). A region writes to the manifest
  (`playbackRegion: [start, end]`) and to the model Sound (`PlaybackRegionsEnabled` plus `PlaybackRegion`), and its
  end stays the file's end; SoundsCore clones each take with its region, so a take's region needs no code.

`RevolverClient` owns Death Line's charge and initial shot sound. The charge follows the visual clock.
The initial shot is non-looped and ends well before the rectangle; its fade-out is baked into the
combined file now, so it carries no `FadeOutSeconds`. `fadeOutSeconds` / the `FadeOutSeconds` attribute are currently
implemented by this owned shot only. Do not add that field to an ordinary pooled cue and assume its caller
will fade it. `balance.py` enforces this restriction and includes that envelope when measuring.

On cancellation, recast, death, missing root, weapon removal, normal completion or an error, destroy the
owned sound/anchor. Check cancellation again after yields so an old task cannot write to destroyed parts or
create late audio after a replacement cast. Pause/resume owned audio with the entity-scaled visual time.

### Ground slide: intentionally silent (2026-10-31)

**Final user decision: "Leave it silent."** Slide audio is intentionally absent. The slide voice logic and
sound enum entry were removed, and there is no active template or manifest entry. Do not resume the search,
buy a clip or restore any candidate unless the user explicitly reopens slide audio. The review history below
records what failed; it is not unfinished work. Slide movement/physics are unchanged.

**The first crop was rejected:** matching two endpoint sample values and seeing DidLoop fire did not make the
recording sound connected. A real loop must flow from its end into its beginning without an audible reset,
gap, changing noise texture or recurring attack/decay. Do not call a repeating one-shot seamless.

**The custom crossfade was also rejected.** The user explicitly wants an existing, clearly authored loop from
the library, not a reworked one-shot. Do not crop, crossfade, reverse, stretch or otherwise edit a recording to
force this sound into a loop. A successful playback test is not permission to repeat the same rejected choice.

**The rock-door loop was rejected too:** it sounds like an engine or stone drill. The floor is **grass/dirt**.
The slide needs soft dry ground friction/rustling, without a sustained mechanical/sub-bass grind. An authored
loop is necessary but does not excuse the wrong material. Do not reuse either rock-door variant, machinery,
vehicle loops, a running-footstep cadence or bird/weather ambience as if it were grass sliding.

There is **no active SlideLoop template**: the rejected stone voice has been removed from the bank
and manifest, and the controller no longer creates a slide sound.
Already-running clients retain their cloned voice until a character respawn or permitted playtest restart.
The three rejected versions and metadata are retained in `Revisions/Slide-loop-v1`, `Slide-loop-v2` and
`Slide-loop-v3`; the custom preparation script is archived in v2. An archive is not an approved fallback.

The current library search found dirt scuffs and grass/rustle one-shots, but no suitable authored grass/dirt
slide loop was verified, including archive filenames and sampler-loop metadata in 1,041 material WAVs.
The user authorized an external search, then chose silence. `Assets/Sounds/SlideLoopSearch.md` retains the
candidate history; no clip was purchased or installed from that search.

If the user reopens this later, a loop needs sustained-body/seam review, not just a valid ID or a promising filename.
Source hash, loudness, build and controlled playback evidence is in `slide-loop-verification.json`. Check
several wraps at actual playback rates, including envelope and texture. Neither a filename, a small sample
jump nor DidLoop alone proves perceptual continuity. Human listening remains the final check.

## 5. Choose, import and mix reproducibly

1. Inspect the owning code and existing sound before choosing a candidate. Read all basic attacks and four
   abilities, including impact/release events and empowered hits. Sentry currently has no playable data/kit;
   do not invent triggers for an empty placeholder module.
2. Search `/mnt/HDD/Assets/Sounds`. Copy unchanged WAVs into the project's `Assets/Sounds` subfolders. The
   user can review those files; do not post or upload them into chat as a listening deliverable. Stock sounds
   are the default here; generated audio is not required.
3. If in-game playback needs a Roblox asset, use the authorized Tripwire audio-upload workflow
   (`upload_asset`, type Audio). Current uploads belong to experience group 35115431. A local WAV alone is not
   playable in Roblox. Retain upload IDs in the manifest. Do not re-upload a file when an existing suitable
   asset can be reused with settings. A new upload can sit in moderation "Reviewing" and stay silent until
   `get_asset` reports Approved; say so if the user tests before then.
4. Before replacing an added cue, retain the prior raw file and manifest entry under `Assets/Sounds/Revisions`.
   Keep inactive alternatives out of the active bank and preload. They are review history, not fallback picks.
5. Update the manifest and model together. Preserve the SoundGroup reference, authored Volume,
   PlaybackSpeed, PlaybackRegion and LoopRegion. Reset obsolete loop/region overrides when returning to a
   simple one-shot. Add a name to `ESoundsNames` only for a new cue; `ESoundsIds` is derived from the names.
6. Give the manifest entry its `soundGroup` (UI if it only plays through `PlayUISound`, else Effects) and,
   when its role is not the default, a `targetBodyDb` from the role table in section 3. `balance.py`
   targets are before the distance loss: -11 ordinary (the default), -14 frequent (names in its `FREQUENT`
   set), -17 echo, -9.5 to -7 strong, -3 the Death Line shot. A UI personal reward such as HealthGain is
   set by ear with `fixedVolume`, which `balance.py` never changes.
7. Run `python3 Assets/Sounds/balance.py` to inspect, then `--apply` to write template volumes and reports.
   It needs FFmpeg and numpy, includes playback rate/region and the owned shot fade, and does not rewrite
   source audio. Delete the `__pycache__` it leaves when importing it from another script.
8. Original sounds outside the bank (`ReplicatedStorage.Sounds.*`, `.UI.*`) are Studio-only, not Rojo. Their
   source files are in `~/Documents` and `~/Documents/LastWave/Sounds` under the same names; confirm a match by
   duration against `source-inventory.json` / `mix-reference-measurements.json` before measuring. The Tripwire
   key cannot download assets (`download_asset` lacks the scope) and the public asset endpoint refuses group
   audio, so those local files are the only source. Change their Volume with Tripwire `mass_set_property`
   in **both** the Game and the Lobby Studio wherever the sound exists, record old and new values in
   `volume-audit.json`, and tell the user to save both places. A call-site scale in code (such as
   `DEATH_SOUND_VOLUME_SCALE`) is part of the level.
9. For a running client, existing cached pools retain their cloned settings; restart a permitted test or
   rebuild its pool before judging a change. Compare in the game against existing weapon, pickup and UI cues.
   Inspect both a solo event and a burst. Listen for body, transient, masking, cadence and fatigue.

Tripwire in this repo: its tools can appear as deferred `mcp__tripwire__*` tools (load them with ToolSearch;
`upload_asset` and `get_asset` worked on 2026-11-09). When they are absent, the daemon still runs at `http://127.0.0.1:44331/mcp` (streamable HTTP, needs an
`Mcp-Session-Id` from `initialize`, sessions expire and return 404). `list_studios` shows the open Studios;
`set_active_studio` picks one by instance-id prefix (place 137835287157016 is the Game, 127928217434499 the
Lobby). Switch it back to whatever was active when done. `get_instance_properties` does not return Sound
properties, and `run_luau` runs against the configured TestX place, not the game.

`Volume` is an amplitude multiplier, not a loudness unit. Playback gain also depends on the SoundGroup,
call-site scale and spatial attenuation. An AudioAnalyzer probe is an additional comparison metric; its
unweighted sampled RMS is not interchangeable with the offline in-game dB metric. Numeric matching and
file names cannot certify that something is non-goofy, satisfying or equally loud to a listener.

All game Sound instances need a group: Effects for world/combat, UI for menus/counters/announcements,
Music for the soundtrack. Shared cues may be routed to UI at a local HUD call site. Templates must also be
assigned; do not rely solely on a runtime helper to fix ungrouped sources. Both project files give the three
SoundGroups stable `$id` values; model `Rojo_Target_SoundGroup` attributes persist their references through
Rojo. Inspect a built place as well as the live instance. Leave editor plugin preview sounds alone.

## 6. Playback, performance and positive feedback

- Use `SoundsCore.PlayWorldCue` / `PlayWorldCueOnEntity` for the new detached positional one-shots. It lazily
  caches eight voices per cue, with a Terrain Attachment for each voice, linear rolloff (8 to 150 studs), and
  a 35 ms coalescing gap for identical new cues. It has no per-frame scan or cleanup timer per one-shot. A cue
  with alternate takes gets at least two voices per take and rolls one take per play (section 3).
- Keep the original entity and explosion pools where their cadence is part of the sound design. The new
  coalescing gap must not erase Salvo's original overlapping shots. The gap also drops every repeat of a NEW layer
  fired on one frame: a Salvo's six flares through PlayWorldCue played once (2026-11-12). Queue those as a run
  (section 3, "Mortar Hat").
- Fire-and-forget Sounds use cycling arrays. `Sound:Play()` restarts an occupied voice; increase a pool only
  when testing shows a genuine tail cutoff. Do not add an ObjectPooler return task to every sound. Owned,
  rare charge/shot sounds are bounded by their presentation's lifetime and clean up explicitly.
- Set `PlayOnRemove = false` on active voices, including character/entity clones. The original Jump template has it enabled. Keep template flags for the UI path that intentionally plays on removal; do not turn it off globally in `Clone`. Destroying or cancelling an active voice must not trigger playback.
- `uiSound.luau` caches templates. ScoreTick, TicketTick, StardustTick, StyleLine and StyleScore reuse four SoundService voices each;
  other UI cues use the established one-off path. Its name debounce is 30 ms.
- The first 49 ms menu-like ScoreTick candidate was inaudible during review; it was replaced with a 131 ms coin blip. A short file, a valid ID and a nonzero Volume do not establish a readable tick.
- Final stats play for the local screen, not once per visible player. Score ticks have a 75 ms minimum gap;
  ticket/stardust accents share a 140 ms cadence and alternate. Closing the screen stops new ticks, and
  reopening resets chains. Do not queue a backlog to play after a counter or panel has finished.
- `pitchChain.luau` raises consecutive reward/XP arrivals by 0.01 playback-speed steps, caps at 1.14 and resets
  after a 0.45 s gap. Scores, tickets, stardust and XP have independent chains. Multiply the template's base
  rate; reset on replay. This subtle positive-feedback climb is appropriate for pickups/counters, not a
  reason to pitch combat ultimates higher.
- Pickups batch same-frame arrivals. Anime Zombie Survival supplied the subtle coin-chain logic;
  BeACastleLord supplied batching/pooling ideas. Their actual audio files were not copied into this game.
- Lobby claim sounds play after server success, not on an unconfirmed click. Music and unrelated gameplay
  should retain their settings and behavior during an audio pass.

### Style meter: its own cues (2026-11-12)

The style meter (UI.md, "the style meter") first shipped with bank placeholders: `ScoreTick` per line,
`ScoreCategory` per headline, and per rank up `ChestJump` plus the win box's chest landing and chord for a matching
rarity. The user played it and rejected the chest voices: "the sounds should not really be the same as the winboxui
because that makes the actual things that come out of the chest have less value". **A reward screen's voice is
reserved for that reward.** The rank up still borrows the box reveal's screen hit, only the look.

Seven new cues, all Pixel Combat families no weapon uses, in `Assets/Sounds/Style/` (UI group, uploaded and Approved
2026-11-12), chosen by envelope (every one reaches -10 dB under its peak within 40 ms) and played through `uiSound`:

| Cue | Source (Pixel Combat, take 001) | When | Target |
| --- | --- | --- | --- |
| StyleLine | `FGHTImpt_HIT-Strong Smack` | a move takes a feed line (`pitchChain`); a repeat at 0.6 | -14, frequent (pooled 4) |
| StyleScore | `DSGNTonl_USABLE-Retro Zap` | a "+points" lands in the score (`pitchChain`), at 0.7 | -15, frequent (pooled 4) |
| StyleBig | `DSGNMisc_SKILL IMPACT-Critical Strike` | a headline move takes a line | -11 |
| StyleRankUp | `DSGNSynth_BUFF-Stats Up` | every rank up, 0.85x at D rising 0.06 a rank | -10 |
| StyleRankHigh | `DSGNTonl_SKILL IMPACT-Energetic Impact` | with StyleRankUp from S up | -12 |
| StyleRankTop | `DSGNMisc_SKILL IMPACT-Dramatic Finish` | with both at SSS | -9 |
| StyleRankDown | `MAGSpel_CAST-Teleport Downer` | a rank drop (was silent, then `MenuOut`) | -15 |

A fighting-game smack says "style" where a coin says "money"; the score tick is tonal, not a coin, so the run's
real coins and tickets keep their meaning. **Nothing here has been heard.** If a round is wanted, the same families
hold five more takes each, and the fit to test first is the frequent pair: a fight sends several lines and landings a
second, so they must stay under EnemyHit.

## 7. Verify the thing that changed

- Run the repository's StyLua and Selene checks; compare Selene with the before snapshot. Compile changed
  large modules with Lune's Luau compiler as well. Do not reformat unrelated work to hide an existing failure.
- Build both places. Verify serialized asset IDs, actual SoundGroup refs, Volume, PlaybackSpeed and regions. A
  binary `.rbxl` compresses its strings, so grep a `.rbxlx` build for ids.
  Local Lune reflection may not expose legacy SoundId: current builds serialize AudioContent; inspect the
  XML Content URI for that property rather than claiming the build is broken or changing working assets.
- In Studio check asset load success, not just the ID. Verify the template **and** pooled clone gains/groups.
  Check start, stop, repeat press, missing model, buff expiry, cancellation and cleanup where relevant.
- A temporary client probe belongs in StarterPlayerScripts. Tripwire's start-playtest ACK precedes F5 cloning:
  wait for a unique client BEGIN log before deleting the edit-mode probe, then read its result. Deleting it
  immediately after the ACK can prevent it from ever running. Remove disposable objects and end your test.
- Use the project's actual StarterPlayer Network and PlayerScripts controller paths; a second require can
  create another controller/network copy. Capturing a temporary module copy's listener registrations can
  exercise the actual presentation closures without replacing the live listeners. Restore all wrappers.
- LoadStringEnabled is disabled here. Do not enable it merely to run an audio probe. Do not use screenshots,
  desktop control, or reconnect/restart Rojo as a substitute for reading the live source and output.
- A probe that wraps `SoundsCore.PlayWorldCue` and `PlayWorldCueOnEntity` logs an entity cue twice: OnEntity calls
  PlayWorldCue through the module table. Wrap PlayWorldCue alone, or the log reads as a double play.
- Keep probes narrow. Use `os.clock()` for durations, not a guessed frame rate; this Studio can run well above
  60 Hz. Do not walk the whole DataModel every Heartbeat. Do not change saved data for a presentation test.
- Preserve a user's running playtest unless restarting has been authorized. A stopped test's heartbeat flag
  can lag; distinguish the runner/session from stale metadata. Say when a probe was running during review.
- Report exactly what passed: source checks, builds, controlled presentation playback, or full combat/mix
  listening. Human approval of timbre is separate from a passed numerical/probe check.

### Lessons from the Death Line release (2026-11-09)

- **Check the spectrum before trusting "weight".** The rejected shot was 97% energy under 150 Hz: it measured loud and
  felt heavy, but had nothing in the midrange to say what it was. A release that must read as a ray needs a
  midrange layer (the Mecha beams are 55-70% between 150 Hz and 2 kHz) over the low hit.
- **Render candidates as the combination they would ship as**, each layer cropped, sped and levelled by the same
  body metric, and write every preview with ONE shared gain. Peak-limiting each preview on its own made the current
  shot read 3 dB louder than the candidates, which is a false comparison.
- **A user-asked composite is a new authored file, built by a script that stays beside it**
  (`Review/DeathRay/make_release.py`): its sources unchanged in `Review/DeathRay/sources`, the old shot in
  `Revisions/`, the fade baked in (so no `FadeOutSeconds`), peak at -1 dBFS and the level left to `balance.py`.
  Copying unchanged WAVs is still the rule for everything else.
- A disabled `PlaybackRegion` in `Feedback.model.json` is written `[0, 0]` with `PlaybackRegionsEnabled: false`.
- A fresh audio upload stays in moderation ("Reviewing") and is silent in game until `get_asset` says Approved.

Use `Assets/Sounds/rules-audit.json` for the current per-cue review decisions, `sound-rules-verification.json`
for this pass's checks, and the manifest as the source of current values. Older reports document their own
revision; they do not override newer feedback. If a choice is rejected, retain the old file, record why it
failed, and change the rule/selection at its owner so the next session does not repeat the same experiment.
