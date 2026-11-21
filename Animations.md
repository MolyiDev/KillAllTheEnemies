# Animating in this project

> **Carried over from Ballarc (Last Wave) on 2026-11-20.** The method, the engine facts and the measured lessons
> apply here; the old game's look does not. Kill All The Monsters is not pixel art and not anime: maps are stud-style
> (LEGO-like bricks at real scale), UI is sleek and modern (`UIMatt.md` is the designer's spec). Sections named after
> a Last Wave weapon, boss or screen are worked examples. A path that does not exist in this repo (`Assets/...`,
> `tools/vfx/...`, a `src/Survivors/...` module) is in `../Ballarc`; `../Anime Zombie Survival` holds the enemy rig,
> map and burst pipelines this repo's `tools/` came from.

What has been paid for, in the order it costs you. The rules are the sword's and the enemies' both:
`animation/` holds the code-driven first-person swings, `tools/bbanim/` the enemy clips, and everything
below applies to either unless it says otherwise.

Two things sit underneath all of it. **A swing is judged on where the working end is and how fast it is
going there**, and neither is visible in a list of Euler angles - so measure, do not squint. And **the
numbers here were all measured in this engine on these rigs**; where one contradicts general advice, the
measurement wins and the note says what it was measured against.

---

## 1. The shape of an attack

Every attack in the game has the same five parts. Nothing else needs inventing.

| | | |
|---|---|---|
| **dip** | ~5-8% | Down and BACK before anything goes up, and the elbows STRAIGHTEN. The anticipation for the anticipation. Cheap, and its absence is why a wind-up can look like it started already in progress |
| **charge** | 30-45% | The haul. Continuous, slightly decelerating, never snapping to the top |
| **strain** | 12-18% | The pose stops travelling and SHAKES. The only near-still stretch a clip is allowed |
| **strike** | 6-10% | Accelerating the whole way, fastest frame ON contact |
| **recover** | 35-45% | follow-through, then a long even haul home to a gather, then a short settle |

The ratio between charge and strike is the character. On the Brute it is measured at **0.30 studs a
frame charging, 0.09 straining, 2.5 dropping** - eight to one from charge to drop and twenty-five to one
from the tremble. That ratio is what "massive" means; it is not the pose and it is not the duration.

### Easing vocabulary, and it is short on purpose

Four curves, all of them the sword's (`ToolSwingAnims`), because everything has to sit beside those.

- **`draw`** (`t^0.8`, the sword's `easeDraw`) for a charge. A cubic spends ~70% of its travel in its
  first third, which over half a second does not read as drawing back - it reads as a snap followed by
  a freeze.
- **`outCubic`** to throw a limb out and settle it at the top of a short reach.
- **`inQuad`** for a fall. Constant acceleration, which is what a mass under gravity does. `inCubic`
  over a tenth of a second puts **43% of the whole travel in the final frame** and lands in two frames,
  which is a teleport, not a fast attack.
- **`linear`** for travel, and for a follow-through - see §3.

### The strain is a tremor, not a hold

**A held key is a stop.** A pose that does not change for a tenth of a second reads as the animation
hanging, whatever was intended by it. The readable beat a hold was supposed to buy is bought instead by
one of two things that keep moving:

- a **COIL** - the chest and head snap back while the arms stay up, so the telegraph is a beat of real
  motion in a different body part; or
- a **TREMOR** - eleven cycles a second, amplitude building across the window and released on the frame
  the strike starts, each bone on its own phase so the body judders rather than rattling in one piece.

Measured on the Brute's strain window: without the tremor the claw creeps at a dead-constant 0.052-0.058
studs a frame; with it, 0.027-0.101. Same average, completely different read.

Author a tremor as a shake, not as keys. At 11 Hz it is a keyframe every 2.5 frames.

---

## 2. Sign conventions and the shoulder, which is where the real bugs are

### THE BRANCH BUG. Read this before aiming any limb.

Aiming a hanging arm overhead has **two** Euler answers: `z = 180`, a rotation about the model's forward
axis, and `x = -180`, one about its sideways axis. They END IN THE SAME POSE. They get there completely
differently - the first sweeps the arm out to the side and up over the shoulder, the second lifts it up
the front of the body - and **nothing in the file distinguishes them**, because they differ only along
the way and the way is what the engine interpolates.

Picked wrong, a two-handed overhead wind-up plays as a T-pose that keeps going: the arms go out before
they go up. It is invisible in every keyframe and obvious the moment it plays.

`bblib.shoulder_for` handles it:

- Pick the branch that keeps **elevation on X** - the smaller `|z|`.
- **Never** pick the branch nearest the previous key. It is the obvious rule and it is wrong: coming out
  of an overhead pose it picks the branch that keeps rotating the same way, which is the arm continuing
  over the shoulder instead of swinging back down the front.
- The previous key resolves FULL TURNS only, which is a different question and the one it is good at.
- Carry the branch forward so a track cannot flip mid-swing where the two nearly tie.
- Which way round a raise goes (+180 and -180 are the same pose, opposite paths) is settled by putting
  an intermediate key with the arm pointing **FORWARD** in the haul. That is also just what a body does.

### A shoulder's actual range

Backward and up are mutually exclusive: about **70 degrees behind with the arm hanging, 33 at shoulder
height, 6 with it overhead**. Anything that has to get behind the head is the ELBOW's job, which is how
a real body cocks a claw anyway. Reaching more than about 0.6 across the body is a shrug - yaw the chest
instead.

**Check the PATH, not just the keys.** Two legal poses can be joined by an illegal sweep: the Brute's
rake went from the arm dropped back to the arm raised out, and the straight line between them took the
shoulder through horizontal-BACKWARD. Sample ~11 points between every pair of keys and check each.

### An elbow inherits its hinge plane from the shoulder's roll

The shoulder rolls thirty degrees across a walk cycle, so a third of every degree of elbow bend goes
sideways, the hands come away from the body, and a heavy shamble reads as a mince. **Cancel the
shoulder's y on the forearm.** Measured: the claw's sideways drift through the Brute's walk fell from
2.3 units to 0.4 when cancelled.

Keep the locomotion elbow SMALL. The reference (`animation.Zombie_mutant.walk`) swings its shoulder 75
degrees and its elbow through a 30-degree band around a 12-degree bend. A body whose whole silhouette is
its arms hanging to its ankles loses that silhouette the moment you fold them.

### Reading a rig's axes off the rig

Never assume which way a rig faces. The Brute's was settled two ways that agreed: the head is a box and
the face carrying the eyes and mouth is the one whose outward normal is `(0, -0.46, +0.89)` (and every
element's signed volume is positive, so that normal is really outward); and the game builds its CFrame
from the NEGATED `(sin, 0, cos)` of a yaw that is itself `atan2(dx, dz)`, two negations that leave the
rig's own +Z pointing at its target. `+Z forward, +Y up`, and the bone named `ArmLeft` sits at +X.

---

## 3. Timing, measured

### Never let an `out` curve own a follow-through

Every `out` curve ends at **zero velocity**. A follow-through given its own beat therefore decelerates
to a standstill in the middle of the clip, and the long haul home has to start again from nothing -
measured at 0.04 studs a frame across the seam, which is exactly what "it stops mid way" looks like.

Run the follow-through **`linear`**. The speed then STEPS down three times - fast out of the strike,
slower through the follow, slower again on the haul - and only the last tenth eases off. Nothing reaches
zero until it is home.

### A recovery has three beats

The sword's `settledRecover`, weights `0.35 / 0.44 / 0.21`:

1. **follow-through** - the working end carries past the impact. A cut that stops where it lands reads
   as a poke.
2. **travel**, linear - the long haul home at an even pace. Any ease here front-loads the distance and
   the limb whips back the way it came (`easeOut` peaks at 22 degrees of screen per frame against 8).
3. **settle**, eased - to a GATHER pose ~85% of the way home, so the last short beat has a fraction of
   the distance and simply bleeds the speed off. Without it the return runs at one constant speed and
   then stops dead, which is what "robotic" looks like.

The gather also stops the return being a rewind: put it off the straight line home (limbs drawn in
toward the body) and the recovery comes back on its own shorter arc.

**A recovery must be slower than the strike**, judged as a ratio of peak speeds. At 62% it still read as
a snap; ~34% reads as a recovery. That is a TIMING fix, not a curve fix.

### Protect peak speed

Smoothing a swing to remove its stall halves the peak and it stops reading as a blow. This was built,
measured and rejected once already: a C1 spline through the same keyposes removed a 173ms stall, three
dead stops and a 90 studs/s lurch, and halved peak tip speed 204 -> 99. "They look really smooth, but it
doesn't look good." Stall and lurch are only worth attacking if peak survives, and that needs POSE
changes - a tighter wind-up so the strike owns more of the travel - not a different interpolator.

### The band a strike frame lives in

Measured on the Brute, whose claw sits ~31 units from the shoulder:

| studs/frame at peak | reads as |
|---|---|
| under ~1.0 | soft; the strike does not separate from the wind-up |
| **1.8 - 2.6** | fast and trackable. Five or six frames of visible arc into contact |
| over ~3.0 | a jump cut. The claw crosses half the body height in one frame |

Judge it per frame, not per second, and check the FRAME DISTRIBUTION as well as the peak - an `inCubic`
peaking at 2.5 can still land 43% of its travel on one frame.

---

## 4. Rigs without the joints you want

Most of these rigs are missing something. Work with it rather than around it.

- **No pelvis.** The legs hang off the TORSO, so every degree the chest turns or folds is a degree the
  feet turn or fold with it - a ground slam folded 40 degrees swings both legs backwards and drives half
  a stud of foot through the floor. Counter it on the legs, a few hundredths of a second BEHIND the
  torso and a little short of 1:1, so the stance drags and catches up. That lag is the difference
  between a pivot and a statue being spun. (`bblib.plant_legs`)
- **No knee.** Every unit of crouch is a unit of foot through the floor. Hold the sink to about a third
  of a stud - which is what the shipped Walk already spends - and buy reach with the fold and the arm
  angle instead.
- **Feet through the floor is normal here.** The shipped Walk goes 0.32 studs under, Death 0.66. Measure
  against those rather than against zero.
- **A head that juts forward is most of the silhouette.** Fifteen units of forward mass on a neck pivot;
  a fold the head goes along with swings the whole skull down over the hands and the attack disappears
  behind its own face. Counter the head against the chest, and let it come up off the floor a beat
  BEFORE the body follows - standing up chest-first and looking down the whole way reads as a thing that
  has forgotten what it was hitting.
- **A stance must not OPEN under a downward blow.** It reads as slipping, not driving. The reference
  smash does not animate its legs at all.

---

## 5. What the engine will and will not let you animate

- **`Root` is off limits on an enemy clip.** `EnemiesController` writes `model.PrimaryPart.Root.Transform`
  every frame for world placement, so anything a clip puts there is overwritten. Weight shift goes on
  `Torso`, which translates freely.
- **`ReceiveAttack` and `Death` are not played as animations at all.** `Client/Utils/HitPoses.luau`
  fetches their KeyframeSequences, resamples them onto a 60 Hz grid and writes bones directly, so it can
  yaw the pose into the real hit direction. They are load-bearing in a way the attacks are not - extend
  them, do not redraw them.
- **Whether that re-aim runs at all depends on the clip carrying a `Root` channel.** `HitPoses` marks
  the poses whose PARENT pose is Root as the ones to turn, so a KeyframeSequence with no Root pose in
  it yields an empty set and replays the clip exactly as authored from every angle. ZombieNormal's
  `ReceiveAttack` is the only clip in its set without one, which is why the directional flinch had
  never run on a shipped body until the Brute - whose clips come out of Blender with every bone baked.
- **A hit react is two things.** The POSE belongs in the clip and reads from every angle; the
  DISPLACEMENT does not, because a clip can only step the way it was authored and a zombie shot in the
  back would step backwards into the shot. Displacement is code, along the real hit direction.
- **A fall is not a lean.** A lean has no front or back so its axis can be yawed; a fall does, and
  yawing a face-down fall by 90 degrees lands the body on its shoulder. Nothing dies sideways.
- **Which way a death clip topples is not a convention here, so do not assume it.** Measured off the
  torso track's last frame: ZombieNormal ends at `-99.2` degrees and goes down BACKWARDS onto its back,
  while ZombieRunner (`+87.7`) and ZombieBrute (`+81.6`) both pitch FORWARD onto their faces. The
  renderer reads it off the clip (`HitPoses.FallsForward`, the aimed bone's `UpVector.Z` on the last
  frame) rather than assuming, because assuming aimed two of the three species a half turn out and they
  fell toward the blow. Author a new one either way; just do not hand-code the sign anywhere.
- **`AttackDelay` is per SPECIES unless the species has `Attacks`.** A one-beat species' clips must all land
  their blow on the same beat. A species whose attacks do not share one (the Spitter's spit releases at 0.9 s,
  its charged spit at 1.833) gives each its own `Delay` and `Cooldown` in `TEnemy.Attacks`, parallel to
  `AttackAnimations`, and throws them in an `AttackPattern` (`{ 1, 1, 2 }`: two spits, then the big one); the server
  sends the index with `Enemies.AttackStarted` so the client plays the clip that matches the beat it is counting.
  Either way the delay is also the window in which a hit CANCELS the attack, so lengthening a wind-up to make it
  readable directly makes it more interruptible - decide which you want.
- **A ranged body holds still for its whole throw**: the wind-up and, after the release, `HoldAfter` (the rest of
  its clip), because the spit clips plant the feet and a body walking under them is a statue sliding along.
- **A ranged body holds the lord it is throwing at** (`Components.RangedTarget`) out to 1.5 times its FireRange,
  walking after him past HoldRange, and a throw it has begun finishes at him whatever the lane rule says. The lane
  rule alone dropped him the moment he stepped out of the corridor, and the Spitter turned on the Core mid-wind-up
  and threw at it from out of range. **No throw ever goes past FireRange**: at the release, a target further than
  that is thrown at the ground at FireRange on the line to it (enemiesUpdateServer's release). A downed lord and a
  wall between still hand it back to the Core, as for every enemy.
- **Blend targets.** A one-shot over locomotion should end at or near the pose the idle starts from, or
  the fade out is a visible snap.

---

## 6. Working method

**Author in Python, bake at 60 fps, linear.** What Blockbench draws is then exactly what Roblox plays,
with no dependence on the two agreeing about an easing curve; it buys easing shapes Blockbench has no
name for; and it matches every clip the extractor already wrote. The cost is that the keys are not
hand-draggable - the Python IS the authoring surface.

**Emit a key at every authored time as well as on the frame grid.** A key at 0.62s falls between frames
37 and 38 and is otherwise never sampled: the peak of the whole swing gets quietly rounded off, which is
invisible in the numbers and reads as a blunted hit.

**Measure the fastest point on the WHOLE BODY, per frame, in studs, bucketed into tenth-of-a-second
windows.** A claw parked on the floor while the chest keeps folding is not a stopped animation, and a
claw-only measure calls it one. Anything under **0.05 studs a frame across a whole window is a stop**;
the top of a charge is allowed to sit near 0.07 because that is the anticipation.

**Look at it from where the player is.** A pose can read perfectly from the side and disappear behind
the rig's own head from a survivors camera. Render front, side and a high three-quarter, and render
EVERY FRAME of the strike separately - the flipbook is where a two-frame teleport shows up.

**Verify the file says what you think it says.** Load it back through Blockbench and compare every
keyframe against the file; the last pass checked 22,569 data points at a worst disagreement of exactly
0. Maths being right does not mean serialization is - a data point is a Molang EXPRESSION, and a value
written in scientific notation comes back as something else entirely.

**Steal structure from a reference and measure it, do not eyeball it.** `animation.Zombie_mutant.smash`
was read by posing its glTF and tracing where its hand actually goes, which is how the dip, the drifting
top, the coil and the 40%-of-the-clip tail were found. None of them are visible in its keyframe list.

**Read a published clip's beats in a playtest when its source is not in the repo.** `run_luau_live` can call
`KeyframeSequenceProvider:GetKeyframeSequenceAsync(animation.AnimationId)` and print each keyframe's time and the
Poses of the parts that matter. The Greatshield's Charge Start (1.67 s) was read that way: its Handle swings from
behind the back (Z +0.88) to in front of the chest (Z -2.4) by 0.38 s, which is where its sound's plant was put
(Sounds.md, Greatshield). Its markers come back too (`Keyframe:GetMarkers()`), e.g. the Running loop's Footsteps.

---

## 7. Getting a rig and its clips into Roblox

`tools/bbanim/to_fbx.py` builds the FBX with Blender; `tripwire`'s `upload_asset` takes it (`Model` for
the rig, `Animation` for each clip - the type IS accepted, contrary to what the public asset docs list).
Everything below was measured by uploading and reading it back out of a playtest, because none of it is
visible in the file.

### Four conventions the round trip changes, and every one is silent

1. **Blockbench's own FBX export is rigidly PARENTED, not skinned.** Right bone tree, all the animation
   stacks, no `Deformer` and no `Pose`. Roblox needs skin deformers to give back one MeshPart with
   `Bone` children. Converting is lossless because these rigs are rigid: every mesh binds 100% to one
   bone, so each parent relationship becomes a single full-weight vertex group.
2. **Roblox ignores the FBX's `UnitScaleFactor`.** Blender writes 100 (centimetres), so a rig exported
   at stud scale arrives a hundred times too big - the first upload came in at `550 x 723 x 324`.
   Export at `global_scale=0.01`. `MeshPart.Size` would fix the MESH and only the mesh: an animation's
   Pose translations are absolute studs and do not rescale with it.
3. **The axis mapping that survives is `(x, y, z) -> (-x, z, y)`**, not the obvious `(x, -z, y)`. The
   obvious one is wrong by a half turn about Y, and mesh, bones and animation all come back rotated
   together - so the rig is perfectly self-consistent and simply faces backwards.
4. **The bone frame arrives half-turned about Y, so every pose channel plays with X and Z inverted.**
   Both rotation and translation. It cannot be fixed by rolling the bones, because the exporter
   re-derives bone axes from `primary_bone_axis` and discards the roll - it has to be undone in the
   data (`AXIS_SIGN`).

A throwaway clip that isolates all six channels settles 3 and 4 in one upload, and is worth building
before trusting anything:

```
rot  x=+20 -> -19.8    y=+20 -> +19.6    z=+20 -> -19.3
pos  x=+8  ->  -7.6    y=+8  ->  +7.6    z=+8  ->  -7.4
```

**The REST POSE is correct under every one of these**, which is what makes them so easy to ship: the rig
looks perfect in Studio and is wrong the moment it moves. A symmetrical clip like a two-handed slam
still looks plausible while playing its arms backwards.

### An uploaded clip is a COPY of the exporter, and the two drift apart in silence

This is the one that actually shipped, and no rule above would have caught it, because none of them was
broken: **`to_fbx.py` gained `AXIS_SIGN` on its position channel after ZombieBrute's clips were already
uploaded, and nothing was re-exported.** All seven played rotations exact to 0.007 degrees and
translations mirrored on x and z. Only the hit reaction looked wrong, because the fault scales with how
far a bone travels - 1.36 studs of claw there against half a stud of torso in the attacks and a tenth in
the idle - so six wrong clips sat in the game looking fine and one got reported.

Two things follow.

**Touching the exporter invalidates every clip already uploaded, of every species.** Re-export and
re-upload the whole set, not the clip somebody complained about. Nothing in Studio can tell you an asset
is stale; the only trace is the asset's `revisionCreateTime` (Open Cloud `GET /assets/v1/assets/<id>`)
being older than the last change to `to_fbx.py`. That comparison is how this was found.

**Only the upload can settle `AXIS_SIGN`, so read the upload.** `verify.py` and `verify_fbx.py` both
compare Blender against the `.bbmodel`, and Blender undoes on the way in exactly what it did on the way
out - so a wrong half turn cancels itself and both pass. Fetch the live asset instead and pick a bone
that TRANSLATES a long way, because a clip that only rotates plays perfectly with the translation sign
wrong:

```lua
local seq = game:GetService("KeyframeSequenceProvider"):GetKeyframeSequenceAsync("rbxassetid://<id>")
-- find a Pose and compare CFrame.Position * 8 against the .bbmodel's own numbers
```

Eight, not sixteen: the extractor scales by 16 from the mesh's own units, and the rigs are played at
twice their natural size, so a stud is 8 `.bbmodel` units in game. The Brute stands 57.845 units and
7.2306 studs.

On a rig BUILT by `to_fbx` the bone rest rotations are identity (measured on ZombieBrute), so a Pose's
numbers compare against the source directly. On an originally-imported rig they are not - ZombieNormal's
torso rests pitched 14 degrees and its limbs 151.9 - so there, conjugate by the rest first.

### Animating an enemy in Blender

`tools/bbanim/to_blend.py <bbmodel> <blend>` builds `Assets/models/Enemies/Zombie<Name>.blend` from the same
`to_fbx.build` the exporter uses, so the file animated is the file exported: one armature, one skinned body with a
full-weight vertex group per bone, eight `.bbmodel` units to the stud, pose bones in XYZ Euler, 60 fps, `Root`
locked (the renderer owns it), and any clips in the `.bbmodel` as actions. It takes the generated cube zombies as
well as the extracted meshes (`to_fbx.as_mesh`).

**What Blender shows is what the game plays.** Measured on all seven of ZombieBrute's clips against `bblib`'s
forward kinematics: with `AXIS_SIGN` applied the Blender pose matches the `.bbmodel` to 0.00000 studs, and with the
keys taken verbatim it is off by up to 8.1 studs. So `AXIS_SIGN` is the Blockbench-to-Blender conversion (a bone's
local X and Z point the opposite way from the `.bbmodel`'s under the axis map), not something the exporter adds
later. Two consequences: a Blender X or Z value reads NEGATED against the same Blockbench key (Y is the same), and a
clip authored in Blender goes out with `to_fbx.export`'s settings and no extra flip. In the `.blend`, front is +Y
and the zombie's own left (`ArmLeft`) is -X.

### What the user will ask for anyway: get it right the first time

Every item here cost the Charger a round of back and forth (2026-09-27). Check a new enemy against all of them
BEFORE showing it.

- **A named reference is measured, not remembered.** When the user names a game ("like the charger of l4d2"),
  measure its clips (§12; L4D2 is installed for study) and retarget by direction before authoring. The first charge
  was invented: a raised hand leading. The user wanted the SHOULDER leading, the body bowed behind it.
- **Moves lead with the body.** A charge is a shoulder barge with the whole body thrown behind it. An arm held out in
  front reads as a hand raised, and a small arm motion at speed reads as the arm shaking.
- **Keep the reference's timing.** The cycle length decides walk against run (§12 rule 1). Squeezing L4D2's 0.5 s
  charge cycle into 0.4 s to fit a speed read as scurrying. For a faster body, change the stride, never the cadence.
- **A menacing stance**: straight legs splayed a little OUT, feet wider than the hips, a crouch on bent knees.
  Knock-knees or legs bowed back in under the hips read as goofy. A body that crouches needs knees AND ankles (§7,
  "The Charger's knees").
- **Size by role.** A special heavy stands over the Brute (7.2 studs); the Charger went to 8.8. Scale the model in
  its generator, before painting (Models.md §7), and multiply every stud distance in the clips by the same factor.
- **Chase speeds against the lord's RUN (26 studs/s), and prove the catch in numbers**: (speed - 26) x run time +
  reach against the Range. The charge started at 21.2, below a running lord, and he simply ran away.
- **Every ending carries its momentum.** A run that runs out skids: the server bleeds the speed off, and the clip
  braces, slides and lurches as the feet catch. A stop in place reads as the charge losing all its force. A hit is the
  one ending that stops dead, because that is the impact.
- **Every number in the data that comes from a pose is measured off that pose**, and measured again when the clip or
  the body changes: the charge's `Reach` is the ram's front minus the box's half depth (6, then 3.2, then 4.1 as the
  clip and the size changed), and `AttackReach` is where the fist lands.

### An enemy animated in Blender, start to finish (the Spitter, 2026-09-26)

All six of its clips were accepted in one or two rounds each by working this way. The authoring script is kept in
the session's scratchpad (`spitter_clips.py` for the loops, `spitter_attacks.py` for the one-shots); copy its shape.
The two throws were re-authored on 2026-09-27 by `Assets/models/Enemies/refs/spitter_anim/spitter_lob.py` (its
`spitter_lib.py` is the Charger's library pointed at this rig), which is the one to rebuild them from now.

**Authoring**, over the Blender MCP in the user's open file:

- **Clips are functions of time, baked one key per frame, LINEAR, pose bones only, fake user on.** Key times on
  WHOLE frames: the FBX export bakes on whole frames (`bake_anim_step = 1`), so a key between frames is rounded off
  there however carefully it was emitted in Blender. Author the release on a frame.
- **Blender 5 keeps an action's curves in layers**: `action.fcurves` is empty. Read them through
  `action.layers[0].strips[0].channelbag(action.slots[0]).fcurves`, and when swapping the rig's action set
  `animation_data.action_slot` too. Evaluate a pose off the curves or through `L.FK` rather than `frame_set` on the
  user's scene, and put the rig's action back after.
- **Search a pose numerically when a number decides it.** The throws' release angle came from a grid search over the
  heave's keys (torso lunge, torso pitch, head angle and when it peaks) scored on the mouth's velocity angle, the
  head's aim and the speed, a few hundred poses a second through `L.FK`. Hand-tuning had put the first pass at 108
  degrees straight up.
- **Bone signs, read off the rig**: every bone's rest frame is `x = world X, y = world up, z = world back`. Torso and
  Head: `+x` pitches back, `+y` yaws to its left, `+z` leans to its left. A hanging limb: `+x` swings it forward, `+z`
  swings the hand or foot toward the zombie's right (+X). A pose bone's location is `(x, up, back)` in studs.
- **Solve the stance legs, never key them.** (This is the knee-less rig's solver. A rig with knees and ankles uses
  `refs/charger_anim/legs.py`: see "The Charger's knees" below.) Straight legs with no knee cannot absorb anything,
  so a planted foot is solved every frame: it rolls heel then toe on its foot box's real corners (read the mesh; the heel is not the
  thigh's bounding box) and holds its ground point, which slides back at the walk speed in rig space. Measured slide:
  0.0000 studs a frame. The torso height is the lowest any planted leg allows (the other drags in), and it may only
  sink ahead of a heel strike at a set rate so it never drops in one frame. On a rigid foot a stride set further
  BACK than forward (19 degrees at strike, 26 at toe-off) is the one where heel strike and toe-off want the same hip
  height. Feet cannot skate at `BaseMovementSpeed`, and only at it; the shipped walks slide theirs 3-9x.
- **Secondary motion is damped springs on each child's parent pitch** (head on torso, jaw on head, throat on both,
  arms on torso, 2.4-5 Hz, zeta 0.2-0.7), trailing 2-4 frames and tapered to zero over the last 10-14 frames so a
  one-shot lands exactly on rest.
- **A strain tremor**: 11 Hz plus an off-ratio 1.37x component, each bone its own phase, enveloped `u^grow` and
  released on the strike frame. On the charged spit it built for 0.7 s and read from across the map.
- **A part hung off the head but sitting in the jaw** (the throat sac) stays put when the jaw opens and fills the
  mouth like a ball. Swing it with the jaw about the hinge (85% of the jaw's angle) on top of its own motion.
- **On a body with its hunch baked in, pitching the torso forward past ~10 degrees buries the head** between the
  shoulders and points the mouth at the floor. Drive the chest FORWARD (translate) and whip the head up relative to it.
- **A throw moves the release point ALONG the projectile's launch.** The first Spit and SpitCharged reared up and back
  and snapped forward: the mouth dropped through the release (-19 and -18 degrees) while the glob left it at 40-60 UP,
  and the user felt the throw and the arc as two things. Re-authored 2026-09-27 (`refs/spitter_anim/spitter_lob.py`,
  planted-foot solver from the Charger's): the gather goes LOW (chin tucked, chest curled back over the gut, the sac
  swelling; the charged one drops out of its reared charge into a gulp), and the heave lunges the chest forward while
  the head comes up, so the mouth leaves at +43 and +50 degrees. The server then throws at THAT angle at every
  distance (`TEnemySpit.LaunchAngle`): timed off a flat speed, a far throw climbed far above what the body showed. Two things the search taught:
  **a head still whipping up on the release throws the mouth up and BACK** (perpendicular to the head), so the head
  arrives early and is near its top on the release frame, and the forward-and-up comes from the chest's lunge; and
  **pitching the chest forward drives the mouth forward and DOWN**, so the torso stays near level through the heave.
  Measure the mouth's velocity INTO the release frame (`mouth_report`), and put the data's `Mouth` on that frame's lips.
  The Spit's first wind-up (0.617 s) read as too fast; it is 0.9 s with only the gather longer, two gulps in it so a
  slow gather is a body loading up and not a pose held.
- **A step into a throw, on legs with no knee** (L4D2's Spitter steps a third of its height into a lunge on the
  release): let the stepping leg stop holding the body up while it is in the air (the other leg alone sets the height;
  a foot swinging forward of a hip held at full height clears the ground by itself), and move the foot LATE (`inQuad`)
  so it never leads the hip: a foot ahead of the hip swung the thigh 50 degrees and its culled top came out of the
  pelvis. 1.5 studs is as far as ours steps before that. Swinging the arms back behind the body for the lunge needs
  -60 degrees on a rig whose rest pose already hangs them forward; -30 only brought them to vertical.
- **A charged attack reads at range from its silhouette**: the arms flare into a wide A with the black mouth growing
  for a second before the release.
- **A one-shot that ends in a slump** (a gather past home: sags forward, then stands into the idle) keeps the
  recover moving; a plain settle home went under 0.05 studs a frame for its last 0.2 s.
- **A death that topples about the toes** (the whole body rigid, a floor clamp lifting it wherever it would sink
  more than 0.15) falls clearly forward. The gut holds the hips up, so it drops 7.2 units, not the originals' 13;
  the orchestrator kept it. Face down, "forward" is into the floor: trail the arms BACK along the flanks.

**What the Charger added** (2026-09-27; scripts in `Assets/models/Enemies/refs/charger_anim/`, `charger_lib.py` is
the reusable half: forward kinematics off the rig's rest matrices, which matched the skinned mesh to 4e-7 studs, the
planted-foot solver and the hole check):

- **A rigid sole rolling onto a long toe lifts the hip.** The Charger's toe is 0.94 ahead of the ankle against a
  0.47 heel, so toe-roll wants the torso ~0.14 higher than a far-forward heel strike, and taking the higher of the
  two planted legs dropped the body 0.09 in one frame at every toe-off. Hand the height over across double support
  (a smoothstep from the trailing leg's need to the leading one's), cap how fast the torso may SINK (0.016 a frame,
  swept backwards so it starts down ahead of the strike), and sweep the stride: short in front, long behind (+14 /
  -38 degrees here).
- **Stance targets are relative to where the hips actually are.** A run pitched 16 degrees forward carries the hips
  back 0.2 studs; targets written against a hip at y 0 put every strike that much further forward and dropped the
  body 0.25 on each landing.
- **A run with a flight phase and no knee** buries the swinging toe behind while the body is lowest on the next
  landing. Sweep duty, stride and swing ease together (an `outCubic` swing that leaves the ground fast) and accept
  what is left inside the shipped Walk's 0.3.
- **Face down, a limb's "forward" is the floor.** A death swung the big arm forward to meet the ground and the floor
  clamp propped the whole body up on it. On a fallen body swing the arm OUT (z) to sprawl, and search the final pose
  for arm angles that lie on the floor rather than prop it (`death_arm_search`). A body with its lean baked in
  (28 degrees) only needs ~62 more to lie flat, with the legs folding flat behind at the hip.
- **A one-shot built on the Idle's first frame, not on zero**, or its start is off the idle by the breath (0.29 here).

**The Charger's knees** (2026-09-27, after the user found the straight, knock-kneed legs goofy). The rig grew
`ShinLeft/Right` (knee, at the thigh's bottom) and `FootLeft/Right` (ankle), the legs straightened into one line
splayed 4 degrees out, and the three items above about stiff legs no longer apply to it. `legs.py` solves them:

- **A knee needs an ankle.** With the foot fixed to the shin, every bent knee tips the sole onto its heel or toe, so
  a crouch cannot stand flat. Add both or neither.
- **Solve from where the foot is.** Place the sole (midpoint, height, pitch: toe up at the heel strike, flat, heel up
  onto the toe), which fixes the ankle; thigh and shin reach it from the hip with the knee bent FORWARD, both bones
  in one plane so the knee is a pure hinge. Keep the bend between 8 degrees (a chain at full stretch pops) and 145 (a
  folded block shin buries its top in the thigh).
- **The height is designed now, not found.** A crouch (0.14 standing, 0.26 running) and a bounce twice a cycle; the
  torso only drops further when a planted foot is out of reach. Cancel what the torso's ROTATION does to the hips
  (`hip_rise`), or a run bowed 60 degrees hoists them 0.37 and straightens the legs.
- **Never plant a frame that was planted already**: the crouch goes on twice (the flinch sat 0.28 low). Clips built on
  the Idle start from its unplanted pose.
- **Crossfade legs by ankle position, not joint angles.** Blending the charge's airborne leg into a standing one by
  Euler swung the foot 0.25 through the floor; lerping the ankle target and solving keeps it above.
- **Proportions cap the lift.** This thigh is 0.88 against a 1.57 shin, so the knee barely rises; a charge's foot
  lift comes from the heel kicking up BEHIND. 1.3 studs of lift folded the knee flat; 0.9 clears.
- **The shin must end above the ankle.** A shin box reaching under the ankle pivot drove its back corner through the
  floor as soon as the shin leaned forward over a flat foot.
- **Two dips the stiff legs used to throw away now land**: the Attack's sink had to be cut to a third, or the fist
  buried itself 0.21 in the ground.
- **Hinge the knee about the body's side axis, never "toward forward".** Aiming it at forward flipped the thigh over
  whenever a swinging foot kicked up level behind the hip (forward then lies along the leg), and the wide thigh box
  jumped 2 studs in a frame. Found by the fastest-vertex-per-bone read, not by eye.
- **A retargeted loop shorter than its source has a seam.** Our 0.5 s charge is one of the two cycles in L4D2's 1.0 s
  clip, and the end of their first is not their start: the big arm jumped 1.1 studs at the loop. Crossfade their
  first cycle into the one before our start across the loop so the last frame lands on the first.
- **A clip for a bigger body is the same clip times its size.** When the Charger grew 1.3 times, every stud distance
  in the clips (crouch, bounce, stride targets, lift, sinks) went through `charger_lib.SIZE`, read off the rig; ground,
  soles and pivots are read off the rig and the `.bbmodel`, never typed in. Speeds are the game's and stay.

**A charge that runs out skids** (the user: it "stops too suddenly and without any force remaining"). The server's
`Skid` state carries the run's speed on for `StopSkid` (0.5 s), bled off evenly: 50 to 0, about 12.5 studs, still
plowing and still hitting what it meets. In the clip a planted foot moves with the body, so a planted foot IS the
skid: the front leg locked out ahead on its heel, the back one dragged on its toe, the body thrown back 26 degrees and
sunk, juddering at 13 Hz while the feet scrape, then the lurch when the feet catch and the body does not (pitch
forward, the big arm flung on, the head whipping down) before it stands. A hit still stops dead: that is the impact.

**Check a chase speed against the lord's RUN, not his walk, and work out the catch.** A lord runs by default at
14 x 1.857 = 26 studs/s; the charge was set at 1.5 times his 14-stud walk (21.2) and he outran it. What decides it is
(speed - 26) x run time + reach against the Range: at 40 over 55 studs a lord running straight away escaped from
anywhere past 25.6. It is 50 over 70 now (caught from anywhere inside the 40 Range), which is also L4D2's Charger's
speed for this size (8.2 head heights a second, 12.5-stud strides). A planted foot only covers what a crouched hip
reaches (4.5 studs here), so a fast gait gets a short stance and a long flight, and it needs the walk's sink-rate
limit: a heel landing past the hip's reach pulled the body down 0.44 in one frame.

**Checking**, before the user sees anything:

- **Measure** the fastest vertex on the whole body per frame in 0.1 s windows (§6), the planted foot's slide against
  the ground speed, how far under the floor it goes, and for an attack the release frame's speed, the recover's peak
  as a fraction of it (the Spitter's 0.28-0.34), and the mouth's world position on the release frame.
- **Render from a COPY of the file** (`save_as_mainfile(copy=True)`, then `blender -b copy.blend --python render.py`)
  so the user's scene is never touched: orthographic front, side and high three-quarter contact sheets, every frame of
  the release as a flipbook, and Blockbench's "distance 110" camera (perspective, 30 degree vertical FOV, 13.75 studs
  from the centre, raised 0.15 of that) for the hit and the death. A close three-quarter of the mouth is where the
  sac-in-the-mouth and the buried head showed; the side view hid both.
- **Never re-run `to_blend.py` on a `.blend` that has clips in it**: it rebuilds the file and deletes every action.
- **When the rig changes (new bones, a new size), use `to_blend.rebuild_live` in the user's OPEN session**
  (`runpy.run_path("tools/bbanim/to_blend.py", init_globals={"LIVE": <bbmodel>})`). It swaps the rig and body, keeps
  the file and its actions, and then every clip is rebuilt from its script. Save a copy first
  (`save_as_mainfile(copy=True)`). **Never run the headless path, or `to_fbx.build()` with its default `reset=True`,
  inside the live Blender.** It resets to an empty factory scene and unloads the MCP add-on: the session is gone
  until the user reopens the file and reconnects the add-on.
- **A clip script imports its libraries once per Blender session**: pop `charger_lib`, `legs` and `retarget` from
  `sys.modules` before each `runpy`, or an edit to them is silently not used.

**Exporting** (`tools/bbanim/blend_to_fbx.py`): opens the `.blend` and writes the rig plus one FBX per action through
`to_fbx.export` itself, no copy of the settings and no extra flip.

- **Name the copy exactly like the file** (`<scratch>/c/ZombieNest.blend`, not `nest_copy.blend`): the FBXs are named
  after the `.blend` (`ZombieNest_Crawl.fbx`), and `verify_blend_fbx.py` looks them up by that name, so a renamed copy
  exports fine and then fails to verify.
- **A new clip on an unchanged rig is one upload**: export the lot, verify the lot, upload only the new clip, and make
  its `Animation` under `Animations.Enemies.<Name>` with Tripwire's `create_instance` in EDIT mode, `AnimationId` set.
  The Nest's Crawl went in that way (Models.md §9).
- **A clip built in the live session is kept by saving the live file** (`bpy.ops.wm.save_mainfile()`), after checking
  `bpy.data.is_dirty` was False before starting, so no other unsaved work rides along. A new action with a fake user
  does not mark the file dirty; save anyway.
- A headless render or export prints "BlenderMCP server stopped / addon unregistered" on the way out. That is the
  headless Blender's own copy of the add-on; the live session is untouched.

- **Verify the FBX against the `.blend` by the SKINNED MESH** with `tools/bbanim/verify_blend_fbx.py` (run it on the
  same copy, it must print PASS), frame by frame (FBX frame `f` is source frame `f - 1`), vertices matched by index. Two traps, both of which reported a clean file as broken: Blender's FBX
  importer CONNECTS `Torso` to `Root` and a connected bone ignores its location (disconnect every edit bone after
  importing), and sampling several actions from one open file leaks state from one to the next (reopen per clip).
  Done right, all six Spitter clips came back at 0.00000 studs. The imported FBX is at the export's `global_scale`
  (0.01): multiply it by 100 before comparing, or every vertex reads off by 99%.
- **Read the upload back** (§7 above): the Spitter's Spit keyframes put the Torso 0.34 studs forward and the Jaw at
  42.4 degrees on the release key, frame 37 with the X/Z flip. Roblox spaces an N-frame clip's keys at `length/(N-1)`
  of the FBX's frames, so they arrive 1/71 s apart instead of 1/60 and the release lands ~8 ms late: the "one frame
  later" below.
- `HitPoses.LoadAsync(animation)` runs on the SERVER through `run_luau_live` too, which reads a death clip's
  `FallDirZ` and a hit clip's `AimedNames` on the uploaded asset without a client probe.

### After the import, before it works

- **Cancel the Root bone's x and z in the MeshPart's CFrame.** `EnemiesController` writes a WORLD CFrame
  into `Root.Transform`, so a body lands wherever `part.CFrame * Root.CFrame` puts it. The ground lift
  handles y; anything left on x or z is a permanent gap between where the ECS says a body is and where
  it is drawn. The Runner's Root rests at z `+0.2371` so its part sits at z `-0.2371`. ZombieBrute does
  not do this and is drawn 0.8618 studs behind itself.
- **Clear the MeshPart's `PivotOffset`.** The importer leaves it rotated 90 degrees about X. Nothing
  looks wrong, but `Model:GetExtentsSize()` is taken in the pivot's frame, so it comes back with Y and Z
  SWAPPED - and `EnemiesController.getGroundLift` is `GetExtentsSize().Y / 2`, so every body sinks two
  studs into the floor. Measured against the shipped rig: 1.6189 against the correct 3.6153. Both the
  shipped Brute and ZombieNormal carry an identity `PivotOffset`; that is the house convention.
- **Rebuild the wrapper Model.** The imported one carries its own `WorldPivot`, which cannot be cleared
  through the Studio bridge. A fresh `Model` falls back to the PrimaryPart's frame.
- Set `PrimaryPart`, and match the shipped part flags: `Anchored`, `CanCollide = false`,
  `CanTouch = false`.
- **Verify against the source, not by eye.** That the rig PLAYS the clip right, which is a separate
  question from the asset data being right (above): load every clip and check `AnimationTrack.Length`
  against the `.bbmodel`, then step one with `AdjustSpeed(0)` and `TimePosition` and compare where a
  known vertex lands against the same point through the Python FK. A residual under a frame's worth of
  travel is the probe sampling, not the file.

### An R6 Humanoid clip onto the enemy rig (the old Game place's clips, 2026-11-20)

`tools/lune/retarget_r6.luau` turns a Motor6D KeyframeSequence into one on the rig's bones. A Pose holds its
Motor6D's `Transform` in the joint's frame (C0's rotation), so the bone takes `J * R * J^-1`.

- **The rig is R6 turned half round.** It faces its own +Z with `ArmLeft` at +X; R6 faces -Z with its left arm at
  -X. Without the turn in `J` every clip plays mirrored front to back and side to side, and the first upload swung
  the attack's arm backwards. The rest pose is right either way, so only a moving check shows it.
- **Check it in ree against the original** (`tools/rig/ClipCheck.luau`, the command in its header): a real R6 rig
  plays the original, the shipped bones play the retargeted clip, and every frame prints the largest angle between
  a part and its bone. The fixed clips read 0.0 degrees through Walk, Attack and Spawn; the unturned attack read 179.
  ree simulates no physics, so the harness poses the R6 parts from each Motor6D's `Transform` itself.
- **Rotations only**, because the set plays on every body size, so a clip whose life is a translation (the old
  Spawn climbing out of the ground) loses it. An attack is retimed so its blow lands at `ATTACK_CLIP_IMPACT`.

### The one thing that stays slightly off

Roblox plays the clip about **one frame later** than the source says (16 ms). It is below perception and
well inside the jitter the damage packet already has, so it is left alone - but it is why a claw check
at the fastest frame of a strike reads ~0.9 studs out and nowhere else does.

---

## 8. First-person guns authored in Blockbench (the RevolverNew)

A viewmodel gun whose clips are drawn in Blockbench rather than ported from a mod. Everything below cost a
round trip with the player to learn; most of it is invisible in Blockbench and only shows in game.

### The pipeline, and which file is the source

- **`Assets/models/Weapons/<Gun>/<Gun>.bbmodel` is the source.** Rig, meshes and every clip live there.
- `animation/bbmodel2luau.py <bbmodel> <out>` prints `RIGS.<Gun>`; splice it over the block between
  `-- GENERATED from Assets/models/Weapons/<Gun>/<Gun>.bbmodel` and its closing `})` in `Client/Utils/GunClips.luau`. Never
  hand-edit that block. The converter decodes every bezier key back to a named easing and **fails the build
  on one it cannot name**, which is the check that a key was rewritten without re-encoding its handles.
- `animation/bbmodel2blender.py` (`blender --python bbmodel2blender.py -- <bbmodel>`) rebuilds the file in
  Blender behind the game's own first-person camera, with the game's arms. `Assets/models/Weapons/<Gun>/<Gun>.blend` is its
  output: rebuild it after an edit rather than editing both.
- Which clips the game plays and which use both hands are two dicts in the converter (`CLIPS`, `BOTH_HANDS`)
  and repeated in the Blender importer (`GAME_CLIPS`, `BOTH_HANDS`). A clip the converter does not list
  (the file's `charge`, `charge_tremble`) is a picture of code and never reaches the game.
- After a change: splice, `stylua --check src`, `selene` on the touched files, rebuild the `.blend`.
- **The draw is keyed by script, not by hand**: `animation/holsterdraw.py` writes the `pullout`'s hand keys into the
  `.bbmodel` from keyposes on the BODY (the right hip, lower torso space), taken into the eye's space so the one clip
  lands on the hip in third person and under the lens in first. A 4.5-stud gun cannot swing down through the bottom
  at the hip without going through the floor, so it is pulled forward along its line and flipped up and over, the
  Sword's draw. The rig's `EquipIsTakeOut` keeps the generic raise-in off it in both views.
- **To see what the GAME plays, both views**: `lune run animation/gameclips.luau <Gun> <json>` runs GunClips.Pose,
  equipRaise and the weapon's RigPose as they are, then places them as ViewmodelController and Firearm + HoldRig do;
  `blender -b --python animation/gameclips2blender.py -- <json> Assets/models/Weapons/<Gun>/<Gun>InGame.blend` bakes every frame
  (FP.* and TP.* bones, one action per clip, `FirstPerson` and `ThirdPerson` cameras). Measured against the
  authored `.blend`: the gun agrees to 0.00001 studs except where the game really differs (the equip's raise-in, and
  up to 2 cm on the flying rounds, where GunClips' named sine easings stand in for Blockbench's bezier handles).

### Spaces, measured

- **Blockbench's Generic format flips nothing**: `world = parent . T(origin - parentOrigin + pos) . Rz.Ry.Rx`.
  Blender's `XYZ` euler is the same product, so a bone pointing +Y with zero roll takes every key AS TYPED.
- **Blockbench -> the gun model, in studs**: `M(p) = 0.036 * (-z, y, x)`. On screen the rig sits at
  `camera . ModelMount . T(-HandleOffset) . M`. Camera: 90 degrees VERTICAL field of view (`sensor_fit =
  VERTICAL` in Blender).
- The gun's axes: muzzle is -X, +Y is up, +Z is the gun's left and the SCREEN's left, +X is back toward the
  camera. On the hand bone (`right`): rot X rolls (+ = top leans screen-left), rot Z pitches (- = muzzle up),
  rot Y yaws (+ = muzzle toward screen-left).
- **Measure framing, do not eyeball it**: project the muzzle, hammer, grip and cylinder through the camera
  (`world_to_camera_view`) and keep them roughly inside 0.2-0.85 of the screen. That is how "kinda out of
  camera" became "the hammer sits at -0.29".

### What the player actually sees

- **The `.bbmodel`'s arm cubes are not what the game draws.** The game draws Viewmodel's own arm: a fixed
  0.64 x 1.92 stud box, hand on the marker bone, lying back toward `RigPose.Viewmodel.RightShoulder`. A
  pose that reads in Blockbench because its 4-stud arm runs off screen shows a stub in game.
- **An arm laid from the shoulder ignores the wrist.** Tip the gun and it swivels in a frozen fist. The rig
  flag `GunArmRidesBone` lays the GUN arm at the Idle pose and then carries it with the hand bone. The OFF
  arm stays shoulder-laid: turned with its bone, the short box leaves its cut end floating mid-screen.
- **Put the hand IN FRONT of the grip** (at the trigger guard), so the arm box swallows the grip like a
  fist. On the grip itself the front of the grip sticks out of the arm's end and the gun reads as standing
  on it.
- **To make a new gun feel like an old one, give it the old one's GRIP POINT, hand offset and shoulders**,
  carried through each gun's grip frame. Matching where the MUZZLE lands on screen instead reads as a
  smaller gun held further forward and turned toward the crosshair.
- **A rest-pose cant is undone with a roll on `ModelMount` about the hand, never in the keys.** Editing the
  hand bone's X moves the gun under the off hand and breaks every docking already solved.
- **A hand working at the back of an upright cylinder hides it.** That is geometry; no shoulder position
  fixes it (three were rendered).

### Clips, and the player's taste on them

- **Idle is ONE still frame.** The viewmodel's code already breathes; an idle loop breathes twice.
- **The gun's kick lives in the Fire clip** when there is one (`ViewmodelRecoil`/`WeaponTilt` `Kick = 0`),
  exactly as the ported Revolver does. The camera kick stays code.
- **Keep the gun upright; move the HAND.** A big wrist tilt reads as the gun balanced on the end of the arm.
- **A slam that closes something**: gather one way with the top of the gun leading, then swing back through
  the close and carry straight into the idle hold. Rotating the bottom one way and the top the other is
  robotic.
- **Inspects are motion, not particles** ("effects" meant flair), and they are taken with patience: each
  side held about a second, the roll to the other side limited to about 120 degrees and done TOP FIRST.
- **Author wrist poses as wrist poses**: yaw about the camera's up, pitch across the wrist, roll about the
  FOREARM's own axis (which leaves the square arm box looking unmoved), plus a move of the hand in camera
  studs, then convert to the hand bone's keys. Key a big roll every ~60 degrees, all one way, or the
  interpolation takes the short way round underneath.
- **Copying another gun's clip exactly**: pose it with a copy of `GunClips.Pose`, take its motion ABOUT
  ITS GRIP (`CF0^-1 . CF(t)`), apply that to the new gun's grip, carry hand offsets as camera-space deltas
  and a second hand in the gun's frame, solve the bones, and bake at 60 fps as smooth keys.

### Things that leave the gun

- **They leave along the chamber axis until clear**, then fall. Anything else cuts through the cylinder.
- **They keep their momentum.** A fall that starts from rest reads as the round hitting something; a rise
  after leaving reads as it being punched back up. Key a thrown arc every 1/30 s: exit speed carried on with
  drag, gravity from the same instant (`p = exit + v0 (1 - e^-k.t) / k - 1/2 g t^2`). Measured result: the
  backward speed fades 5 -> 1.3 studs/s while the fall builds 0 -> 23, with no frame that stops.
- **A throw authored for one orientation of the gun breaks when the gun is re-posed**: rounds and a
  speedloader that fell when the gun pointed up flew through the camera once it was upright. Re-aim them in
  CAMERA space after any change to the hand's motion.
- **Anything that docks** (a speedloader into a cylinder) is solved per frame in the frame of what it docks
  INTO (the crane's yoke), not interpolated between hand keys. Seat pose once, slide along the axis.
- **Solving a child's keys needs the parent's FINAL motion loaded.** The first rounds solve ran against the
  old parent flight and the rounds barely fell.

### What the engine does to it

- **A Motor6D that RESTS at exactly 180 degrees jitters in random directions** (float noise flips +180/-180
  and the engine swings through a random axis). The crane's two hinges summed to 180; resting at 178 fixed
  it. Moving through 180 is fine. Blender cannot show this.
- **A part that moves on its own needs its own part and joint.** The six rounds were one mesh; splitting
  meant reading the mesh out with `EditableMesh` in a playtest, exporting one component as FBX, uploading it
  as a Model, inserting it six times, and setting Size, TextureID, CFrame and a Motor6D per round
  (`C0 = Gun^-1 . T(At)`, `C1 = identity`). The upload arrived yawed 180 degrees against the originals;
  compare which end carries which UVs before trusting it. These parts live in the PLACE, not in Rojo.
- **A turn kept between clips is a turn about the CYLINDER'S axis** (`CylinderKeepsTurn`), applied to every
  joint under the cylinder. Applied about each round's own joint, the cylinder moves one chamber while the
  rounds spin in place.
- **A bezier key rewritten keeps its old handles**, measured for the old gap and the old values. Re-encode
  the easing of every segment touched (and of a kept key next to a new stretch) or the converter rejects it.
- Parts are hidden by scaling their bone to 0.001; the converter turns that into a `Show` track.

### Checking it in the running game

Tripwire cannot screenshot a playtest, so the game is read as numbers:

- A throwaway LocalScript in `StarterPlayerScripts` logs each part's CFrame relative to the `Gun` part every
  other Heartbeat. Give the gun with `WeaponsCore.AddWeaponToEntity` and draw it with `EquipService.SetSlot`
  from `run_luau_live`; start a reload with `Network.Server.Weapons.Reloading.FireAll(instanceId, 6)`; press
  F with `simulate_keyboard_input`. Log for the whole clip at fixed steps, since the clip starts a network
  hop after the trigger. Delete the probe afterwards.
- To tell bad data from a runtime problem, replay `GunClips.Pose` offline on the same clip: smooth offline
  and jittering in game is the engine (the 180 case above).
- The playtest sometimes never registers a server peer. Stop after two tries and say so.

---

## 9. A held tool driven by baked clips (the pack)

The pack (`Data/Tools/Backpack`, `Client/Controllers/PackController`) is the first TOOL whose hands are
animation rather than a mount and two fixed grips. Its clips are keys in Python (`animation/packclips.py`),
viewed in `Assets/models/Tools/Backpack/Backpack.blend` and baked to `Client/Utils/PackClips.luau`. It took six rounds with
the player; everything below is what those rounds cost.

### What a clip is, and why it is not a rig

A held tool is one welded model the viewmodel re-frames onto the camera, with two fixed-length box arms laid
from the shoulders to wherever the hands are (`Viewmodel.PlaceArm`). So a clip is five things a frame and
nothing else: **the model in CAMERA space, the moving part's angle (the lid), the camera's pitch, and both hands
in camera space.** `ViewmodelController.SetHeldPose(fn)` hands the viewmodel over to such a clip: every frame it
asks `fn(frame, dt)` for the model and both hands in world space, `frame` being the camera with the sway, bob and
landing on it, and nil gives the frame back to the ordinary hold. **The clip's first and last frames ARE the
tool's resting hold, number for number** (`RigPose.Viewmodel` = the clip's `HOLD_*`), so the viewmodel draws the
idle on its own between clips with no seam.

- **Author in AIM space, bake in camera space.** "It goes down and the view follows it" is two motions in the
  world. The keys are written against the untilted aim; the bake takes the tilt back out, so the game does one
  multiply (`camera * pack`).
- **Hands are weights between holds**: on the side grip, on the lid, or FREE in camera space, the rest of the
  weight going to free. A hand moving between two holds lifts on an arc (`REACH_ARC`), most at an even split.
- **Start the clip's clock inside the pose callback**, so a clip begins on the first frame it is DRAWN. A model
  still replicating in otherwise spends its equip unseen.
- **Left-handed variants are the right ones MIRRORED by the script** (`mirror`: x -> -x, yaw and roll negated,
  the hand channels swapped). Never author a side twice; the two drift apart.
- **Check every seam in numbers**: each open ends exactly on its opened still, each close starts there, each
  equip, inspect and close ends exactly on the idle. The script's own check printed 0.0 for all of them.
- **The tool is usable the moment it comes out**, as a gun fires off its draw (the player asked for it): the use
  button and the inspect key CUT into the equip, and the use button into an inspect. A cut starts the new clip
  from the pose on screen and blends into it on `1 - (1 - u)^2`, **timed by the distance**: a fixed 0.22 s cut
  early, with the pack still over the shoulder, threw it at 0.53 studs a frame against the equip's own 0.31.
  Timed so the blend's peak (twice its average on that ease) is the equip's own, every cut peaks at 0.30 and the
  longest runs 0.39 s. Measure a cut offline off the evaluator at several cut times before shipping one.

### Smoothness: what "snappy" and "robotic" were, measured

- **A snap was a hand going from one hold to another in eight frames.** Measured as the hand's own on-screen
  movement per frame while it is not locked onto a hold: the grab the player saw at frame 31 was **1.15 studs a
  frame**; the fixed one is **0.108**. `--report` prints it for every clip, and flags any weight that changes in
  under `REACH_MIN` (0.28 s). Strikes (a flick, a yank, a swat) may run 0.2-0.27: there the hand is travelling
  with the thing it threw.
- **The default curve is `smooth`: Catmull-Rom in TIME, held MONOTONE (Fritsch-Carlson).** Separate eases per
  segment step the speed at every key. Plain Catmull-Rom overshoots: `InspectTurn` keyed its yaw at 58 and the
  curve ran to **66.6** and swung back, which the player called a shake. With the slopes held monotone the curve
  never passes a key, so every overshoot in a clip is one that was keyed.
- **A hand letting go starts free from EXACTLY where its hold had it** (read off the evaluator at the release
  time, never typed in). A release toward a fixed point was a hand dragged across the screen.
- **A lid resting SHUT can only bounce, never ring**: a ring swings below its rest, and below 0 is the lid going
  into the body. `bounce()` hops above the seat and falls back (outQuad up, inQuad down).
- **The player's taste on the pack, stated once**: the hand that opens the lid HOLDS it the whole time it is open
  and closes it, like a hatch pushed open and held (a hand that let go and dropped to the rim read as robotic);
  no push-back before the close (it lifted the hand and read as a hitch); no press at the end of it.

### The box arms decide a lot

The arm is a fixed 1.92-stud box laid from the hand back toward its shoulder. **A hand about 2.5 studs or more
from its shoulder puts the arm's near end at the camera, and it fills a third of the screen.** Measure where a
hand lands on screen before keying it (`--report`'s "highest hand"): the lid's near lip rode up to +0.55 of the
screen when open; its side, half way back to the hinge, sits at +0.27. Sweep the candidate holds and pitches in
the script's own projection rather than guessing: tipping the pack AWAY was the obvious fix for a high hand and
measured WORSE than tipping it toward the eye.

### The camera's pitch is held, never laid on

A pitch written onto `Camera.CFrame` is read back as aim by the PlayerModule and stays there
(CameraController's cosmetic-motion note). So the pitch plays only while the view is HELD
(`CameraController.HoldLookAt(target, 1e4)`: an ease rate that high lands exactly on the clip every frame), and
only for the open, the opened still and the close. The equip and the inspects keep their few degrees of pitch in
the file and drop them in the game: taking the camera off a walking player for them costs more than they give.

- **Release the hold in Heartbeat, never inside the viewmodel's PreRender.** The close ended inside the pose
  callback, after the camera had been placed for that frame; `ReleaseLook` put the raw camera on it on the
  spot, and that frame drew the arms and the pack against a camera that had moved under them - a one-frame jump.
- **While a hold owns the camera, the aiming mouse delta reads zero** (`GetAimingMouseDelta`). The pointer is
  not turning the view then either, and the viewmodel's look sway went on swinging the arms off it.

### Engine facts this cost

- **A weak-keyed table of Instances can lose its entries while the Instances live.** The lid's rest offset was
  cached in one; the Luau object for the joint was collected mid-open, the next frame read the already-turned
  C0 as the rest, and the lid came home half a stud out of place (C0 jumped from (0, 0.535, -0.724) to
  (0, 0.048, -0.597) at the same 95 degrees). Hold one plain reference to the thing in the hands.
- **EquipService's `Turning` joint pivots at the part's CENTRE** (`C0 = rest position`, `C1 = rest rotation`
  inverse). A lid turns about its HINGE, so the client writes `C0 = T(hinge) * R * T(rest - hinge)` and skips
  the write when the angle has not changed. The write is local, so other players see the lid shut.
- **Driving it from Tripwire**: give the tool with `EquipService.GiveTool(entity, HotbarCore.PackTool)` from
  `run_luau_live`; a click at the screen centre opens; `ButtonR2` closes (`ButtonB` is bound to the core UI and
  refused, and a simulated click did not fire PackUI's CLOSE). Log the lid's C0 and the screen's window size
  from a probe, printing on change only.

### What everyone else sees: the same moves on his body

Every first-person clip has a third-person twin of the same name and length (`packclips.py`'s THIRD PERSON,
baked to `Client/Utils/PackBodyClips`, played by `Client/Tools/PackHoldClient`), started on our own body as
PackController starts the first-person clip and relayed to everyone else (`Equip.PackMove` -> `PackMoved`).

- **It is not a Roblox Animation.** Every lord wears the same R6-shaped body (`blockyBody`), so the clip is that
  body's pose, baked: the torso's lean and the head's turn (laid on the Root's and Neck's rest, so the walk
  still plays on the legs), the pack in upper torso space (the ToolMount's C0), the lid, and each UPPER ARM's
  place and turn, written through the shoulder's Transform with the elbow and wrist straight.
- **It moves like R6** (`packclips.py`'s R6 BODY). Nothing bends inside a block: no Waist, elbow, wrist or knee.
  The torso is one block leaned about the lower torso's centre, each hip turned back so the legs stand where they
  were and the gap opens at the hips. An arm is aimed from its shoulder at its hand target, then shaped by what
  the player asked for, round by round in Blender:
  - an arm held forward had its back end out through his back: it is brought up to 0.5 out in front after it is
    laid (before, the slide back into the shoulder undid it), less the more the target already pulled it off
    the shoulder (added on top of the opened pack's own slide, it stood a stud off his body);
  - aimed all the way in at a grip, its back end flared out past the shoulder: it turns only half the sideways
    offset, so the arms stay near parallel with the hands on the outside of the pack;
  - it sat too high: a forward arm is lowered 0.2;
  - and the PACK goes where the hands took it (the holding hands' shift averaged), or it ends up on the
    forearms.
  The pose the player approved is the `ThirdPersonR6` preview; the bake was checked against its every bone key.
- **Author in body space** (the upper torso's rest frame) and let the bake take the lean back out, so a
  leaning chest brings his shoulders to the pack instead of carrying the pack off.
- **Judge it on the R6 body**: `animation/rigs/R15.blend`'s part meshes (MrXen0's rig; within 0.06 of the R6
  body's blocks) in `Backpack.blend`'s `ThirdPerson` scene, posed by `tp_body` (§10). `--report-body` prints how
  far each arm leaves its shoulder and how deep the pack goes into him.
- **The pack is two studs tall and an R15 arm reaches 1.77**, and that decided most of it. The inspects keep
  about half the first-person turn and hold the pack further out, with the chest turning after it (a turned
  pack in front of the chest either put its corners through him or its far grip out of reach). The lid's hinge
  is its far edge, so an open lid stands a stud past the pack: he leans over it, the pack comes up his front
  tipped toward him, and the hand on the lid still sits at shoulder height, which is simply where a bag that
  size puts it. The lid's run past open is cut to 35% of the first-person one (it pulled the hand off it).
- **Check the head, not just the chest, and put the MOUTH on his gaze.** Held low and close with him leaned
  over it, the open pack's black mouth faced his upper chest while his eyes looked out past it. Raised to his
  face and tipped up at it, the open lid's free edge went into his forehead - which the head check first MISSED,
  because it sampled only the lid's top face: sample a moving part through its whole thickness. What reads sits
  between: held out 1.6 studs, tipped 40 degrees at his face, the torso leaning 8, and it tips up at him only once
  the lid is open (and back before it shuts). Gaze 22 degrees off the mouth, the mouth 24 off his eyes, the lid 0.1
  clear of his head, which is as close as an R15 arm's reach lets a pack this size come. The head's look is aimed
  from his EYES, not his neck (aimed from the neck it missed a near mouth by 40 degrees). `--report-body` prints
  the gaze, the mouth and the head clearance. The over-the-shoulder haul still brushes the head (0.05).
- **He goes down WITH the push.** A head and chest that bowed once the lid was already open read as not quite
  human; the lean and the look now arrive together with the lid, and the pack tips up at him as it lands.
- **The pack is worn on his back whenever it is not in his hands** (an Accessory, Models.md §2), and the
  third-person equip starts exactly there: the hold's first pose is taken off his own `BodyBackAttachment` and
  blends into the clip, so a scaled avatar's hand goes back for the pack where it actually hung.
- **Nothing is scaled to the wearer any more.** It was, while avatars differed (their arm against the stock R15's
  1.77); with every lord on the R6 body the ratio was a constant 0.9 that shrank every clip, and the baked arms
  are the body's own pose.
- **Our own lid is written by the third-person hold too**, for the over-the-shoulder view, where the first-person
  clip never runs and the lid used to stay shut. In first person PackController writes it again in PreRender,
  EVERY frame (a skip-if-unchanged there let the other writer's angle stand), and both read the rest off
  `PackHoldClient.LidRest`, which the first to see the joint stores on it.

### Doing the next one: a third-person twin for a held item's clips

In order, with the step that cost a round with the player named:

1. **Author it beside the first-person clips, one evaluator, same names and lengths** (`packclips.py`'s THIRD
   PERSON). Derive what only turns in the hands off the first-person clip (`turn`, `push`); author the equip and
   anything that changes what the body does (the open) by hand.
2. **Judge it on the R6 body** (`animation/rigs/R15.blend`'s part meshes posed by `tp_body`, the torso one block,
   every limb straight) in a scene of its own, from where another player stands, never through the
   first-person lens.
3. **Check it in numbers before looking** (`--report-body`): how far each arm leaves its shoulder, how deep the
   item goes into the chest and legs, how clear of the
   HEAD it stays (sample a moving part through its whole thickness, not a face of it), and for anything looked
   into, how far the gaze is off it and it is off the eyes.
4. **When the numbers fight each other, sweep, do not nudge.** A throwaway script that imports the evaluator,
   overrides one clip's keys over a grid (height, distance, tip, lean, look) and filters on every check at once
   found in seconds what four rounds of hand-tuning did not, and showed when a thing could not be had at all
   (the pack aimed at the eyes AND in reach AND clear of the face needs a longer arm than an R15's).
5. **Aim looks from the EYES and time them WITH the action.** A head that turns after the thing it looks at has
   arrived reads as not human; one aimed from the neck misses anything near.
6. **In the game**: the baked upper arms through the shoulders' Transform every frame (the Animator rewrites
   them), the lean on the Root's REST (hips turned back against it) and the look on the Neck's, a move relayed as
   its index in the clip list, the item written by every viewer (ours too, for the over-the-shoulder view), and a
   hold that starts from where the item was worn. §10 has the R6 rules and the order to work in.

### Blender facts this cost

- **A second scene does not animate in the background.** `scene.frame_set` on a scene that is not the window's
  evaluates nothing, and `blender -b` has no window: render a scene headless from a copy of the file with the
  other scenes deleted.
- **Objects loaded from another .blend have no matrix_world** until they are linked into a scene with their
  armature and the view layer updated. And they arrive RENAMED where a name is taken (the first-person scene's
  `RightHand` empty made the R15's hand `RightHand.001`): map them by the names asked for, not the names they get.
- **An armature's `matrix_world` set before it is in a view layer does not stick; set `matrix_basis`.**
- **Rebuild in the user's live session over the Blender MCP** with `runpy.run_path(packclips.py)`, then point
  the window at the scene (`window.scene`) and save; a file rebuilt headless is not what an open session shows.
  But `build_blender` DELETES every object, action and the ThirdPerson scene first: never run it (or save) while
  the player is judging a preview in that session (§10).

Models.md covers the model under all this: the bake, the lid cut, the import's half turn, and the worn copy.

---

## 10. Third-person clips on the R6 body

Every lord wears the same R6-shaped body on an R15 rig (`Shared/Utils/blockyBody`, parts from
`ReplicatedStorage.Models.R6Body`), so a third-person clip is posed like R6: **nothing bends inside a block.** The
pack (§9) was the first held item done this way, and it took five rounds with the player, two of them spent
undoing work the player had not asked for. What follows is so the next one takes one or two.

### How to work with the player on it

1. **Preview in Blender first, change nothing else.** Build the new pose as a SEPARATE scene in the player's open Blender session
   (a full copy of the existing one, its own actions under a new prefix, e.g. `ThirdPersonR6` / `R6Body*`), from
   a scratch script that imports the evaluator. Do not touch the repo, the game, or the existing scene, and do
   not save the `.blend`: it is a test the player must be able to walk away from.
2. **Iterate on the preview only**, one ask at a time, and apply each ask to EVERY clip, not only the one in the
   screenshot (the player said "check if this happens in other actions too" and meant it every time). Before changing a
   number, measure the thing the player pointed at over all the clips (a small offline probe on the evaluator) and quote
   those numbers back.
3. **"Add them to the game" means THE PREVIEW, AS IT IS.** Move the preview's maths into the repo (same
   constants, same order of operations), bake, and prove it: read every bone key back out of the preview's
   actions and compare (the pack: 15,792 keys, worst 0.000000 studs, 0.03 degrees, which is float storage).
   Never re-derive the pose from the game's own systems (HoldRig's arm, the R6Body attachment numbers) and never
   rebuild the preview from the game: that was done once, it looked different, and it deleted the scene the player had
   approved.
4. **Leave the player's Blender alone while porting.** If the builder in the repo changed, say so and do not run it.

### The R6 rules the player chose (all measured on the pack, `packclips.py` R6 BODY)

- **The torso is one block**, leaned about the lower torso's centre (`HIP`, y -1 in upper torso space). No Waist
  bend.
- **The legs stay standing**: each hip turned back by the same lean, so the gap opens at the hips, as an R6 one
  does. No knee.
- **An arm is one straight block** (upper arm, lower arm and hand moved as one; elbow and wrist at rest), and it
  may leave its shoulder: the player said so explicitly ("you don't have to be strict on having them exactly unified on
  the shoulders"). Its pivot is half a stud under its top (y 0.25), the hand's centre 1.3 below that.
- **Aimed from the shoulder at the hand's target**, then corrected, each for a complaint:
  - slid along its own line toward the target, at most 0.3 back INTO the shoulder (`MAX_SLIDE_IN`); past that
    the hand goes on into the item;
  - **forward**: an arm held forward had its back end out through his back. It is moved up to 0.5 out in front
    (`ARM_FORWARD`, scaled by how far forward it points, so a hanging arm stays put), AFTER the slide (applied
    before, the slide undid it and the equip looked unchanged), and less the more the target already pulled it
    off the shoulder (on top of the opened pack's own 0.54 slide it stood a stud off his body: "almost
    detached");
  - **not flared**: aimed all the way in at a grip, the back ends swung out past the shoulders (x 2.0-2.26
    against a rest of 1.5). It turns toward only half the sideways offset (`ARM_LATERAL`), so the arms stay near
    parallel with the hands on the outside of the item;
  - **not too high**: a forward arm is lowered 0.2 (`ARM_DOWN`, scaled the same way).
- **The item follows the hands.** Once the arms move, the item must move with them (the holding hands' shift
  averaged, weighted by how much each is on it), or it ends up on the forearms. A one-handed haul off the back
  does not count, so the equip still starts where the item hangs.

### What the game does with it (`PackHoldClient`)

- **Bake the pose, not targets.** Each frame carries the lean, the neck's turn, the item's CFrame, and each UPPER
  ARM's centre and turn, all in upper torso space. Nothing is aimed or solved in game, so it cannot drift from
  Blender. Nothing is scaled to the wearer either: every lord has the same body.
- **Arms through the shoulder's `Transform`**: `Transform = C0^-1 * upperArm * C1` (Motor6D C0/C1, or an
  AnimationConstraint's two attachments, `HoldRig.GetJointFrames`), elbow and wrist `Transform = identity`.
  Written EVERY frame, in PreSimulation: the Animator puts its own pose back on them each frame. Work the
  Transform out only when the pose moves and write the stored one.
- **The lean on the Root's REST** about the lower torso's centre: `rest * T(-rootAt) * lean * T(rootAt)`,
  `rootAt` being the lower torso's `RootRigAttachment` (0, -0.25, 0 on the R6 body, which puts the Root on the
  hip line). Hips: `lean^-1 * hipRest`. Put all three back when the item leaves his hands; the arms need
  nothing put back.
- **Left-handed clips are mirrors** (x -> -x, a turn's y and z negated, the arms swapped). Check the mirror is
  exact before relying on it (the pack's was 0.000000).

### The R6 body's numbers (read off `ReplicatedStorage.Models.R6Body` in edit mode)

Upper torso space, the upper torso 2 x 1.5 x 1, its top at +0.75: shoulders (+-1, 0.25, 0), neck (0, 0.75, 0),
waist (0, -0.75, 0); the lower torso's centre at -1 with its Root and hips 0.25 below it ((0, -1.25, 0),
(+-1, -1.25, 0)). An arm's upper arm centre is half a stud out from its shoulder attachment, and the whole arm runs
0.7375 to -1.2617 (upper arm 0.975 tall, lower arm 0.775, hand 0.25). `rigs/R15.blend`'s meshes are within 0.06
of these, so Blender draws the same blocks.

### Tools this cost

- **Tripwire's `run_luau` is Open Cloud and has no execution scope on this place** (403), and `run_luau_live`
  needs a playtest. To read a model in edit mode use `get_instance_children` and `get_instance_properties` on
  each attachment.
- **Blender 5 actions are layered**: `action.fcurves` does not exist. Read keys with
  `bpy_extras.anim_utils.action_get_channelbag_for_slot(action, action.slots[0]).fcurves`.
- **`bpy.ops.scene.new(type="FULL_COPY")` of the body scene** gives a preview with its own rig to key; its
  objects come back with `.001` names.
- **Render to compare, from where the player looks**: `render.opengl(view_context=True)` through the scene camera, moved
  to his side (x -7), front (y +7) and behind, and tiled with `magick montage`. The player's screenshots are side and back
  views, so check those, not only the watcher camera.
- **A generated table of long rows**: wrap it in `-- stylua: ignore start` / `-- stylua: ignore end`, or StyLua
  puts every number on its own line (PackBodyClips was 12,387 lines without it, 486 with it).

---

## 11. A melee weapon's baked clips (the Sword)

`animation/swordclips.py` authors the Sword in both views (`Assets/models/Weapons/Sword/Sword.blend`) and bakes two files:
`--luau` -> `Client/Utils/SwordClips` (the first-person draw, inspect and parry; the swings stay ToolSwingAnims')
and `--luau-body` -> `Client/Utils/SwordBodyClips` (every clip on the R6 body). `Client/Utils/MeleeClips` plays both;
MeleeWeapon only picks the clip and the time. What either body player does to the joints (the lean on the Root, the hips
turned back, the look, the arms through the shoulders) is `Client/Utils/BodyPose`, shared with the pack's
`PackHoldClient`; a still pose (the idle) is laid once, not every frame, as the pack's carry already was.

- **Third person is derived from first person.** A body clip is the first-person move laid on the body's hold, with only
  the chest, head and a free hand keyed per clip (§10's R6 rules). The player's asks that shaped it: two hands like first
  person; placed like the game's own hold (`WeaponRigPoses.BodyMount`: out on his right, well in front), arms allowed off
  the shoulders for it; a pierce that goes forward point first (the chest must not carry it); and a parry that is a
  simple, fast stroke from the bottom to the top (three variants were tried, and a guard that stopped, got knocked back
  and shoved out was rejected: one rising deflect, named Parry, is what stayed).
- **A swing thrown at another speed is stretched onto its clip a part at a time**: the baked `Strike` marks where the
  strike ends, so the strike maps onto the strike and the recover onto the rest (`MeleeClips.SwingTime`). The heavy's
  draw is sampled at the charge's alpha; other players only ever see its release (the relay carries no draw).
- **The draw starts where the sword hung.** `Data/Weapons/Sword.luau`'s `Worn` is the body draw's first frame in BODY
  space off `WaistCenterAttachment`: the draw opens with the chest turned 56 degrees toward the hilt, so its first frame
  in torso space puts the sword in front of his belly. From a released body the clip blends the turn in
  (`FROM_REST_SECONDS`) rather than snapping it.
- **First person**: the draw and the inspect own the hands (`ViewmodelController.SetWeaponHeldPose`, a slot of its own:
  the pack keeps `SetHeldPose` for the whole session); the parry rides the guard's held-pose channel as moves, so the
  block's ring and freeze still lay over it. Anything the player does cuts a clip, handing its pose to the attack.
- **The inspect has its own relay** (`Weapons.Inspect` / `Inspected`), so every screen plays it; the parry needs
  nothing new on the wire, since a weapon has one.

---

## 12. A structure's clips (the Nest)

`Assets/models/Enemies/ZombieNest.blend` holds Idle (4.0 s loop), Crawl (1.2 s loop, its walk), Spawn (1.7 s, its
attack), ReceiveAttack (0.6 s) and Death (1.2 s). They are functions of time in
`Assets/models/Enemies/refs/nest_anim/nest_clips.py` over `nest_lib.py` (curves, baking, measuring and the hole check),
rendered by `render_nest.py`. In the live session: `runpy.run_path(".../nest_clips.py", run_name="nest_clips_live")`
(any name but `__main__`, so its headless branch stays off), pop `nest_lib` from `sys.modules` first, then call the
returned `build([...])` and `measure([...])`. A structure is not a body, and most of §1-§6
assumes one; what changed:

- **Author in the user's LIVE Blender session**, over the MCP in the open file, as §7 says. The Nest was built headless
  into a new `.blend` because the open session held unsaved work on another file, and the user did not want it that
  way: ask them to save or switch instead.
- **The mesh has holes by design, so check every frame for them.** The generator culls hidden faces (Models.md §7,
  "Triangles"), including every face lying on the ground. `nest_lib.hole_check` samples each culled face on a 0.25
  grid per frame and asserts it stays inside another posed box (or no higher than it rests, for a ground face). Run
  it on every clip before looking: 0 face-frames on all four.
- **What that check makes a rule**: `Body` NEVER RISES above rest (every ground face would open a gap under the
  mound), and a Body lean needs a sink under it, `sink = r * sin(lean)` for the footprint's reach `r` (2.1 studs about
  X, 2.2 about Z), so the lean rocks over the edge that stays down (`nest_clips.body_pose`). The Jaw, Mouth, Arm and
  pods may use their whole joint guard (`JOINT_SWING`) freely.
- **A mouth that is one bone cannot open.** The Nest's lips, teeth, tongue and throat were all `Mouth`, which can only
  lurch or tip; it got a `Jaw` (lower lip, lower teeth, tongue) and the clawing arm an `Arm` before any clip was keyed
  (Models.md §9). Ask before re-rigging: the user decides.
- **A gape tips the maw UP-forward.** Pitching `Mouth` forward on the release brought the upper lip down over the
  opening and drove the dropped lower lip into the skirt: from the survivors camera it read as a slot, not a mouth.
  The wind-up clenches it down a little (-4) and the release throws it up and out (+14) as the Jaw drops 27; the eyes
  in the throat are then what shows.
- **Measure, then trust the stop line less on a mound.** Whole-body speed per 0.1 s window is still the read (§6), but a
  mound's farthest moving point is a 1.6-stud arm and a jaw, so a charge built from the body alone sat at 0.02-0.04
  studs a frame. Give the charge a limb with reach (the Arm hauls up and out, then slams down on the release), and
  keep the strike out of `inCubic` over six frames: that put ~40% of the jaw's travel in one frame (0.59 studs); an
  `inQuad` over eight peaks at 0.28.
- **Its hit leans BACK** like every hit clip (EnemiesController's re-aim assumes it) and carries no displacement:
  `HitReactPush = 0` and `HitReactLean = 0` in its data, or the renderer's give-ground slides and tips the debris.
- **Its death caves in rather than topples.** It screams, shudders and sinks 0.33 studs with a 5-degree slump
  forward. A structure is never turned toward the blow (`TEnemy.Structure` skips the corpse turn, which spins the whole
  model, debris and all). The sink is capped by what stays on Root: a beam buried in the flesh was left floating in the
  air, so it moved onto Body.
- **The release frame is data**: Spawn's is f58 (0.967 s, `Attacks[1].Delay`), the mouth there is 2.04 studs out
  front (`Brood.Mouth`). Read back off the upload it lands on the key at 0.976 s (102 keys spaced over 103 frames,
  §7's one frame late), with the Jaw at +27 degrees: Blender's -27 through the X flip.
- **Crawl (1.2 s loop, 2026-09-28) is stick-slip over a constant slide.** The server moves Root at a flat 4.5 studs/s
  (the data's `BaseMovementSpeed`; authored at 3, raised when the root spot moved a whole tile clear of the fog) from
  the murk to its tile; the clip surges the Body 0.52 studs ahead of Root on the heave (rears back 3.5, lurches to
  -4.5 with the front sinking) and lets it lag back on the drag, so the mass's speed over the ground swings 3.1 to
  8.0 studs/s. The arm can't reach the ground (its hand is 2 studs up), so it claws ahead through the gather and rakes
  back on the heave, and the maw gasps on each lurch. The debris rides Root, so it is dragged along under it. Springs
  run three laps and the last frame is the first: seam 0.00000. `CRAWL_SPEED` in `nest_clips.py` must match the data.
  It plays as the data's `WalkAnimation`: the client runs the walk track whenever a body's position changed between
  packets, so a structure that moves needs nothing else on the client.
- **What the server does around the clips** (enemiesUpdateServer's Structure branch, WaveService's "Where a structure
  roots"), measured in a playtest:
  - **Every Nest crawls, wherever it was put** (a wave's or `enemy spawn Nest`): `WaveService.RootStructure` gives it
    a spot, `Components.RootAt`, and it crawls there in a straight line facing where it goes. Rooted in the murk, where
    it used to stay, no lord could reach it.
  - **The spot is a tile from the fog**: on battlefield inside the wall, with nothing built there, on a tile whose four
    neighbours are walkable (bought land counts, the fog may touch at a corner). Asking for all eight neighbours, or
    for 30 studs to the nearest fog, failed every tile the ROUND wall clips at a corner and sent Nests 80-110 studs
    deep; this roots them 50-70 inside the wall. Work such a rule out in code first: at the closest line the field is
    only two tiles deep, and one tile passed the eight-neighbour rule.
  - **Never inside another**: a tile's middle first, then four spots 9 off it on the diagonals, each at least 12 studs
    from every claimed root, and the straight crawl to it no closer than that to one either. A spot off a middle
    beside another Nest lost to a free middle further off: two 12.7 apart in one tile read as one clump.
  - **It faces the Core, and the arena's middle when the Core is not lit**: `CoreService.GetCorePosition` is nil while
    the Core is dormant or out, and holding the spawn yaw left the Nest facing yaw 0, due north, straight into the fog.
    It turns there at 90 degrees a second after the crawl and broods only within 5 degrees of it.
  - **What it brings out looks where it looks**: the body is born on the Nest's yaw and held there through its
    `TEnemyBrood.Hold` (`Components.HoldYaw`, read only for bodies at speed 0, so walkers pay nothing), and the client
    seeds the newborn's yaw from the Nest's in `Brooded`, since its first yaw would otherwise wait for the next packet.
    Every server tick recomputes a walker's yaw toward its target, so anything that should face some other way for a
    while has to be held there, not just spawned that way.
- **Rig facts, off the rig**: bone frames are `x = world X, y = up, z = back`, as on the Spitter. Body `+x` tips its
  top back, `+z` to its own left; `Jaw` `-x` drops it; `Mouth` `+x` tips the top back and the bottom forward; `Arm`
  `+z` leans it further out. A rig faces its own `+Z`, so in game its forward is `-LookVector`.

---

## 12. Measured against Left 4 Dead 2's infected

Left 4 Dead 2 is installed for STUDYING its infected (never shipping them). Every special and the common infected
were measured bone by bone; the full tables, per-infected numbers and re-run scripts are in
`Assets/models/Enemies/refs/l4d2_study/FINDINGS.md` (local only, Assets is not committed), and the memory note
`reference-l4d2-animation-study` says how the files are read. H below is the body's head height as it walks.

**Locomotion**
- Cadence decides walk against run; speed comes from the stride. Walk: a step every 0.48 s, stride 1.1-1.5 H, feet
  down 0.47-0.58 of the cycle. Run: a step every 0.26 s, stride 2.1-2.5 H, feet down 0.28-0.33 (a flight phase).
  A charge keeps the run's cadence, doubles the stride and leans about 28 degrees further.
- A straight leg swings about ±29 degrees walking and ±30 running. The body bounces 5-8% H twice a cycle, lowest
  about 0.3 of a step after the foot lands (a brute's run 17%). With no knees that bounce is the torso's height.
- Shoulders twist ±13 degrees walking and ±21 running, the right shoulder ahead as the left foot lands; arms swing
  ±19 / ±42 against the legs. A heavy arm is carried still. Heads nod 1.6x the torso, except a brute's, which is
  locked (that is what reads as heavy).

**Attacks**
- The fastest hand comes at about 41% of the clip; the strike lasts about 0.23 s and the recover about three times
  that. The damage frame is one frame after the fastest frame.
- The wind-up is a cocked pose reached fast and held 1-3 frames: shoulders turned 20-90 degrees away, the hand
  behind the pelvis. Whole-body blows wind up for 0.57-0.87 s.
- The chain runs hips, chest, then arm, compressed: hips peak about 67 ms before the hand, chest 50 ms, and the arm
  segments together. The shoulder line turns about 66 degrees into the blow.
- Ranged attacks release on a HEAD move, not a hand (the spit on a head whip riding a torso lunge after a 0.13 s
  rear-back), and the body keeps folding after the release.

**Hit reactions, deaths, idles**
- A flinch: the head snaps back first (24 degrees at 0.17 s), the torso follows (28 at 0.30 s), home by 0.67 s, feet
  never step. A heavy body leads with the torso instead.
- The specials have no death clips (ragdolls); commons play 0.3-1.2 s starts and hand off mid-fall, so we author
  the rest of the fall.
- Fighters breathe every 1.1-1.5 s, heavy bodies every 2.7-4.6 s, with 7-13 degrees of torso pitch on a hunched body.

**What does not carry over to our rigs**
- No knees (every rig but the Charger's, which grew knees and ankles, §7): no foot lift or heel kick. Clearance
  comes from the bounce and, running, the flight phase. With knees, measured on their Charger: 22-49 degrees bent
  standing, 12-70 walking, 0-134 charging, the swinging one folded right up.
- No pelvis: the legs hang off the torso, so torso roll lifts one hip and drops the other. Keep torso yaw within
  about ±8 degrees and roll within ±5 on anything with feet down (the Charger's charge took 15% of their roll), and
  put the rest into the arms and head.
- No elbows: a straight arm's hand speed is its angular speed times its length (8 H/s is about 1100 degrees/s for an
  arm 0.4 H long), so reach comes from starting the arm further back, not from extending it.
- Their lean and twist are offsets from their own hunch; ours is baked, so apply the swings on top of it. Retarget by
  DIRECTION (`Assets/models/Enemies/refs/charger_anim/retarget.py`): the lean absolute, the twist and roll as the change
  from their walk, the arms as absolute segment directions.

---

## 13. A boss's clips (the Bloater)

`Assets/models/Enemies/ZombieBloater.blend` holds twelve clips in two sets, authored in
`Assets/models/Enemies/refs/bloater_anim/bloater_clips.py` over `bloater_lib.py` (forward kinematics, curves, the hole
check, all plain numpy, matched to Blender to 1e-6 studs, so `python3 bloater_clips.py measure` checks every clip
offline). Bake them into the open file with
`runpy.run_path(".../bloater_clips.py", run_name="bloater_live")["build"]([names])` (pop `bloater_lib` and
`bloater_clips` from `sys.modules` first). `rest.json` is the rig's rest pose dumped once and `bloater.json` the
generator's cubes, both copied from the build; redo them if the model changes.

- **Two lives, one rig, and the ground is Root's plane in both.** Hanging (Idle, Drift as its walk, Vomit, Burst,
  SacPop, ReceiveAttack) its toes are at Root and the game lifts Root to the hover height; Crash goes from the hanging
  rest to the crawl rest; crawling (CrawlIdle, Crawl as its walk, CrawlVomit, CrawlReceiveAttack, Death) its gut lies
  on Root's plane. So the game picks the idle, walk, attack and hit clip by phase: the hanging Idle or ReceiveAttack
  played on a crashed body lifts it back into the air (HitPoses writes every bone).
- **It cannot crawl upright.** The arms are 4.2 studs and on its bottom the shoulders stand 6.3 over the ground. Lying
  face down at 88 degrees they stand 3.2 up and a fist plants from 2.5 behind the shoulder to 2.9 ahead, so it crawls
  on its face. Face down its mouth points at the ground; the head turns back up 58 (60 is the most before it goes
  deeper into the gut than at rest), and its withered legs stick out of its back end 4.5 up, hanging limp at 32 (the
  right thigh's culled top opens past 40: the leg joint guard is the default 30).
- **A hanging body turns about the sacs** (`PIVOT_HANG`, 8.5 studs up), so a sway swings the feet, not the head. The
  Vomit and the hit turn about its own middle: pitched about the sacs, the retch swung the feet 5 studs in 8 frames.
- **A crawling torso's height is solved, not keyed**: every frame it is set down so its lowest vertex sits on the
  floor (`lying`), which rolls the gut on the ground whatever the pitch and roll.
- **A planted fist is an IK target** (`solve_arm`: the arm's pitch and roll and the elbow, damped Newton). Under the
  shoulder a folded arm cannot reach down 2.7, so the fists plant 1.2 outside the shoulders' line (0.35 slid 0.8 studs
  a frame). Three angles for one point has more than one answer: an arm arriving from a fling landed on the mirrored
  one, 0.97 off the rest, so a hand in the air is steered by ANGLE onto the rest's own branch before the IK takes it.
  Hands moving between holds go by target along an arc held above the floor; blending angles put a fist 1.1 under it.
- **Planted fists cap the rear, so the crawl throw lets go of the ground.** Past 8 degrees of pitch back the fists
  leave it. Face down its mouth is on the dirt, and the first crawl vomit (rearing 8, the head back) threw UP from
  there while its face looked down: the user caught it. It now rears its front to 45 degrees with the fists torn up and
  reaching forward, and throws on the slam back down.
- **A throw is judged by where the mouth FACES and where it MOVES on the release, and the ball leaves between them**
  (the Spitter's rule). The first hanging vomit faced 76 degrees down and was aimed at a mark under it, so the ball
  went down through its own gut. Both throws now face 24-25 degrees down and move 39-42 down, and leave at -30.
- **Measured**: no holes on any clip (every culled face, every other frame); loops seam 0.00000; every one-shot starts
  and ends on its rest to 0.001; the crawl's fists slide 0.002 studs a frame (the vomit's slam 0.054); the mass swings
  1.8-5.4 studs/s over Root's constant 3.6.
- **Data off the poses** (from Root, studs, x / forward / up): Vomit releases f78 (1.3 s) with the mouth at
  (-0.15, 3.24, 9.35); Burst's doors are open on f66 (1.1 s) with the opening at (-0.03, -0.35, 3.22); Crash lands Root
  on f30 (0.5 s: the game drops Root over the frames before it), the gut hits on f38; CrawlVomit releases f78 with the
  mouth at (-0.15, 5.54, 5.16); the lips rest at (-0.15, 2.64, 9.21), where the charge ball grows (TEnemySpit.MouthRest);
  the crawl's speed must be `CRAWL_SPEED`, 3.6 (TEnemyBoss.CrawlSpeed).
- **The file carries the sacs as previews** (`SacPreview1..4`, bone-parented to the anchors from the printed mount
  data). `blend_to_fbx.py` drops every object but the rig and its skinned body before exporting, and
  `verify_blend_fbx.py` picks the skinned body, so neither takes a sac for the model.
- **Death plays on the ground only**: brought to zero while it hangs, its sacs burst and it falls, and BossService kills
  it when the Crash clip ends. It ends face down, so the corpse turn toward the blow is skipped for a boss as for a
  Structure (§12).
- **In the game** (Server/Services/BossService, Client/Utils/BossRender): the sacs are enemies of their own drawn on the
  body's anchor bones, placed by composing each joint's Transform by hand (TransformedWorldCFrame lacks the Root the
  renderer wrote that frame, so sacs hung off it trailed the body whenever it moved); the throws are the Spitter's
  charged spit through SpitVfx at ChargeScale 2.6 off the Bloater's own lips.

---

## 14. A body carrying something in both hands (the Shield)

`Assets/models/Enemies/ZombieShield.blend` holds Idle (2.8 s loop), Walk (1.0 s loop at 4 studs/s), Attack (1.9 s, the
door slammed down onto what is in front, contact f53 = 0.883 s), Block (0.6 s, a blow taken on the door), ParriedStart
(0.45 s) / Parried (1.3 s loop) / ParriedStop (0.5 s) (the guard knocked open for as long as the stun lasts),
ReceiveAttack (0.667 s) and Death (2.2 s),
authored in `Assets/models/Enemies/refs/shield_anim/shield_clips.py` over `shield_lib.py`, rendered by `render.py`. In
the live session: pop `shield_lib` and `shield_clips` from `sys.modules`, then
`runpy.run_path(".../shield_clips.py", run_name="shield_live")["main"](["build", <names>])` (or `"measure"`).

- **The hands are on the arm bones and the door on its own, so nothing holds them together.** Author the DOOR (in the
  torso's frame) and SOLVE the arms onto its grips every frame (`grip_arms`): each arm takes the door's own turn, so the
  fist turns with the grip, then swings about its shoulder until the fist is on it. Two locked arms can only carry the
  door on a circle about the shoulders' line, so a door is moved by turning it about that line
  (`door_about_shoulders`), with a small tip about its middle for the wrists. Anything else needs a longer arm; the arm
  slides along its own line for the difference. Measured on every clip: fists 0.0000 studs off their grips.
- **A long toe caps the walk's double support.** This boot's toe is 0.81 ahead of the ankle, so rolling onto it lifts
  the hip 0.13 late in stance, higher than the leading heel can reach: at duty 0.6 the striking heel landed 0.10 in the
  air. At 0.52 the trailing toe is back down by the strike (soles -0.011..+0.020, the swinging foot 0.025 clear). Read
  the needs of both legs across a cycle before choosing a duty.
- **A swinging foot's clearance without a knee**: slide the leg up into the pelvis at mid-swing (`HIKE`, 0.13). The
  thigh's culled top goes deeper, so the hole check stays clean.
- **Face down, a hunched head props the body up.** The first death lay a stud in the air because the head, jutting
  forward, pointed into the door under it and the floor clamp lifted everything to clear it. Turn the head UP off the
  ground as the body lands (+34..+46 here), sprawl the arms OUT, and drop the legs toward the floor (+x on a face-down
  body) so the feet reach the ground past the door.
- **Use the held thing as what it is, or the move reads as someone else's.** The first attack rocked back and lunged
  forward behind a door that barely moved against him, and the user saw the Spitter's throw in it, "nothing to do with
  a door". A door is a slab: it is heaved up over the head on straight arms (the wrists standing it up, `tip = -pitch`,
  so it stays upright while the fists rise; past 125 degrees its bottom edge goes through the helmet), cocked back
  behind the head through the strain, chopped down flat onto what is in front (its top edge 2.6 studs up on the contact
  frame, a lord's chest) and driven on into the ground four frames later, where the thud is. The chest leads the door
  by two frames. Peak 1.94 studs a frame, 1.49 into contact. The tips on both frames are solved, not typed.
- **Get a helper's sign from the rig before writing a clip on it.** `door_about_shoulders`' pitch was first documented
  backwards (+ swings the fists FORWARD and up, tipping the top back), and the first gather tipped the door's top into
  his face while meaning to pull it in.
- **Knocked open is a gate, not a shove.** A parry that snapped the door straight back put its planks through his chest
  and face (the clip test, `shield_lib.crossings`, caught 35 frames). It swings out to his right on the fists and rolls,
  then sags with its top tipped AWAY (the wrists, 40 degrees) and the fists kept forward, or its bottom swings into his
  legs. The dazed hold needed a pant and a sway big enough to stay over 0.05 studs a frame.
- **Twist is the one joint the model's guard does not cover.** The generator keeps culled faces hidden through +-30
  degrees of pitch and roll only, so 9 degrees of torso yaw over planted legs opened the thighs' tops. Keep yaw under
  ~4 on a stance, or add Y to the guard.
- **A state that lasts as long as the game says is three clips, not one.** The first Parried was one 1.6 s clip timed
  to the Sword's 1 s stun, and the user asked for a start, a loop and a stop so the stun can grow. Start ends exactly
  on the loop's first frame and Stop starts exactly on it (0.00000), and the loop's sway is on its own clock, faded in
  over Start's tail and out over Stop's head, so both seams carry their motion. The client hands Start on to the loop
  when Start stops playing, so the clips are preloaded (EnemiesController's getTemplate): unfetched, a clip reports
  itself playing while it downloads and Start held for 1.2 s.
- **In the game** (2026-09-28): `Data/Enemies/ZombieShield.luau`, `TEnemy.Shield` (FrontArc 100, TurnRate 70 and the
  four clips). The server blocks a blow whose attacker stands inside the arc (EnemiesService's `isBlocked`, in `Damage`
  and `DamageMultiple`; nothing lands or staggers) unless the body is stunned, and says so on `Enemies.Blocked`, which
  plays Block (not over its own swing, not on a parked body). The walker turns it at TurnRate and walks and swings
  only the way it faces (enemiesUpdateServer), at its full pace, so it walks an arc round toward a lord (at 4 studs/s
  and 70 degrees a second, a circle 3.3 studs in radius); it stands still only through the slam's wind-up, and its swing never
  reaches behind it. A first version slowed it by how far it still had to turn, which stood it still to turn at a
  right angle; the user wanted it turning as it walks, as every other body is always walking. The stun pass plays the parried trio. Generated waves bring one
  from the first and one more every four, up to four, first in and across the middle. `BaseMovementSpeed` = 4
  (`WALK_SPEED`), `AttackDelay` 0.8, `AttackReach` 3.5 (the door lies 1.9-6.3 studs ahead on the contact frame).
  Measured in a playtest: 67 degrees a second of turn against the data's 70; front hits at 0 and 60 degrees did
  nothing and fired Blocked, at 120 and 170 they landed; stunned, a front hit landed; the trio played 0.45 / until the
  stun ended / 0.5.
- **The damage lands after the blow is SEEN to land** (the user: "the sword doesn't do the damage just when it starts
  doing the swing"). The first `AttackDelay` was the clip's contact frame, 0.883 s, and the lord took the hit while
  the door was still coming down. Three things put the picture behind the number: the client starts the clip a
  network hop after the server starts counting; the server lands a blow on its 0.1 s tick (`TimeCore.FIXED_DT`), so a
  delay of 1.0 hits at 1.1-1.12 (measured); and the first slam of a session played its clip unfetched, starting late.
  At 1.0 (landing at 1.12, after the thud on f57) the user found it late; it is 0.8 now, landing at 0.915-0.924
  (measured, three slams), between the door on the chest (0.883) and on the ground (0.95). Every clip a blow is timed
  by (every species' AttackAnimations, a Charge's four, a boss's and a Shield's) is fetched when the species' template
  is built (EnemiesController's getTemplate); measured, the first swing of a Zombie, a Brute and a Shield in a fresh
  session all played loaded. Set a delay so that, with the tick's ~0.12 s added, the blow lands on the frames where it
  is seen to connect: never where it starts to fall, and not after it has finished landing either.
- **A parry that opens a body has to leave time to use the opening.** The Sword's `StunSeconds` was 1 s, and a Shield
  knocked open by it had its door back up before a lord could land anything through the front. It is 2.5 s for every
  enemy now (the parry's own cooldown), which is also how long the Curse lasts.

---

## 15. A floating weapon's motion in code (the Shovel and the Revolver, 2026-11-11, unjudged)

The Yo-Yo's rework (VFX.md 22) set the bar: every path blends, nothing snaps, every beat has its own move. The Shovel
and the Revolver got the same pass. Their motion is code, not clips: `ShovelClient.Pose` / `ShovelClient.Blow` and
`src/Survivors/Client/Weapons/RevolverMotion.luau`. Both benches (`shovelbench`, `revolverbench`) stand the old motion
(Before) beside the new (After). The old pose lives only in the bench files, to be deleted once the user picks.

### A blow the server has already landed

The server hits first, so there is no wind-up to show: §1's dip, charge and strain do not exist. What is left is
the strike and the recovery, and the recovery carries all the weight. A Shovel blow is four beats (`Blows` in
ShovelClient, tilt in degrees with the tip outward, drop in studs at scale 1):

- **Slam**, `inQuad`, ending on the frame the effect draws the blow (ShovelFx's `SlamSeconds`, 0.07). Keep the two
  equal: a slam that lands before or after the dust reads as a miss.
- **Bite**: held in the ground with a 22 Hz tremor fading out. §1's rule, that a held key is a stop, applies here
  too: a stuck blade that does not shake reads as the game hanging.
- **Pry**: `linear` (§3) from the bite to a pose PAST rest: blade swung back, shovel lifted above its float.
- **Settle**: `(1 - u)^2 * cos(1.5 pi u)` of that overshoot. One small counter-swing, then it lands at rest with no
  speed left, so the end never snaps.

The kinds differ in numbers, not in shape: Strike, Heavy (Earthshaker or Excavator up), Whirl (a short chop over the
lean), Plunge (Groundbreaker: driven to the handle, buried 0.28 s while the spikes run out, yanked out high) and Shiver
(the casts: an ease-out lift and lean back, shivering, then a nod forward).

- **A new blow starts from where the last one has the shovel** (`FromTilt` / `FromDrop`, the last drawn values). The
  old bonk restarted from rest, so a strike landing mid-recovery snapped the blade up a frame before it fell.
- **A long blow is locked against short ones.** Strikes keep coming during Groundbreaker; without the lock
  (`PLUNGE_LOCK_SECONDS`, slam plus bite) the next strike pulled the buried shovel out mid-eruption.
- **Things that come and go rise and sink.** Excavator doubling and halving the shovels made them pop in and vanish. New
  ones now rise out of the floor with a twirl (`easeOutBack`); taken ones sink back in from the slot they left
  (`ShovelClient.Leave` keeps the slot and its angle, so the sway does not jump when the list reorders).
- **Give every copy its own phase.** Four shovels floating on one sine read as one rigid piece. A phase per slot (bob
  and sway on different steps) makes them read as four.

### Recoil is a spring, not a curve

The Revolver had no recoil at all: each shot snapped the gun onto the target and held it there. Now every shot kicks
a damped spring (`RevolverMotion.Kick`), and the spring drives the slide back, the muzzle flip and an alternating roll.

- **The numbers, measured in lune:** 30 rad/s at a damping of 0.42 peaks two frames after the kick (0.033 s), then
  dips 23% under the aim before it settles. That dip is the gun coming back past the aim instead of stopping on it.
  At 0.5 damping the dip is 15% and reads stiff; at 0.35 it is 30% and wobbles. 26 rad/s peaks on the third frame
  (0.05 s), which reads soft.
- **Normalise the kick, then tune in shots.** The kick speed for a peak of exactly 1 comes from the closed form
  (`KICK_IMPULSE`: at `t* = atan2(wd, z w) / wd` the peak is `exp(-z w t*) sin(wd t*) / wd` per unit of speed). After
  that, every moment is a number of shots: Crit 1.35, Death Line 3.2. Big kicks are softened (`x / (1 + 0.3|x|)`) so
  3.2 shots of kick do not flip the gun over.
- **Step a stiff spring in substeps.** At 30 rad/s a 30 fps frame is ~1 radian of motion. 240 Hz substeps keep it
  stable on a long frame. Let it sleep once it is too small to see, so an idle gun steps nothing.
- **A charge strains, a release kicks.** The Death Line's charge draws the gun back and up and trembles it at 11 Hz,
  each axis on its own phase (§1), all building with the share squared. It is released on the fire frame and the
  3.2-shot kick lands two frames later. The forward snap between them reads as the release, so it was kept.
- The reload became a toss: up 1.1 studs while it twirls twice backward, slowing into the catch (`outCubic`, so it
  reaches the catch at zero spin), then a dip and a bob that settle. The old reload was one `easeOutBack` turn over
  the whole reload.

### Joints a clip owns

**Never write a joint's Transform while a clip is animating it.** During Rapid Fire the shooting clips animate the
Revolver's Handle joint: that is what puts the gun in the hand. The first recoil pass wrote that Transform every
frame to kick the gun in hand, so the clip's pose was lost and the gun hung at the player's side (the user's report,
2026-11-11). RevolverClient.Update `continue`s before touching the joint while Rapid Fire's shots are recent, and Rapid
shots do not kick. Before adding a code-driven layer to any weapon, find out whether a clip animates that joint
(`Animations/Abilities/<Weapon>`); if one does, the layer goes on a part the clip does not own, or nowhere.

**A held pose outranks every per-shot pose.** The Death Line holds the gun out on its line, but the auto-attack kept
firing under it, and each shot still ran its own pose (snapped toward the target, or welded into the hand for Rapid
Fire), so the gun swung to the side on every round (the user, 2026-11-12). A big moment that owns the weapon's pose
must be checked by every writer: the shot (fire, write nothing), the ability start (no weld) and the per-frame update
(keep holding even while another rule would step aside).

### A bite with a wind-up the server waits out (the Greatshield, 2026-11-11, unjudged)

Unlike the Shovel's blows, the Greatshield's chomp has a real wind-up: the server waits `BITE_WINDUP` (scaled by attack
speed) before it bites, so §1's shape applies whole. `GreatshieldMotion` is a pure function of the wielder's clock,
sampled by GreatshieldClient and the bench alike; the old bite was three `task.spawn` loops on Heartbeat.

- **The jaw meets ON the damage.** The old bite opened over the whole windup and only then clacked shut over 0.08 s,
  so the chomp landed after the hit. Now the snap (`inQuad`, fastest on contact) ends on the windup, and the sound,
  jolt and effects fire on that frame (`TakeHit`). Checked in lune: the jaw is shut on the hit frame at 0.65, 1 and 3
  attack speed.
- **Dip, open, strain, snap, chew, pry, settle.** The shield draws back and cocks the other way (10% of the windup),
  opens on `draw` (`t^0.8`), strains with an 11 Hz tremor building with the share squared, snaps, holds shut with a
  22 Hz chew while it has its prey, is pried loose linearly to a pose past rest, then one counter-swing into rest. The
  swell (the Bite) overshoots in as it opens and sinks a touch under true size on the pry.
- **A new bite starts from the last drawn pose**, the dip blending from it, so a chomp arriving mid-settle never snaps.
  An ability's bite still locks the auto-chomp out until its jaw meets (`IsLocked`). A grip into the hand (Charge,
  Bastion's cast) shuts the jaw from where it is (`Close`).
- **Idle**: a slow bob and sway on the shield's own phase, and a lean into the way the aim turns (eased, so a flick of
  the camera rolls it and it swings back). Remote shields lean too.
- `greatshieldbench Motion` stands the old bite (Before, copied into the bench only) beside the new (After).

- **A pose layered over tracking cannot see the floor; lift it by what it would sink** (2026-11-12, unjudged). The
  user saw the floating Greatshield dip into the ground: its bob, its lean into turns and the bite's roll all turn it
  about its middle, which drops a corner. The shield model's bounding box is read once in its Handle's frame; every frame
  the posed box's lowest point (`|Right.Y| * half.X + |Up.Y| * half.Y + |Look.Y| * half.Z` under its middle, plus the
  lower jaw hanging open, all times the swell's scale) is checked against the feet, and the transform is raised in the
  joint's parent space by the difference (`liftOffFloor`). It costs one CFrame chain a shield, keeps every tilt (the
  user ruled out straightening it), and does nothing while the pose is clear of the floor.
- **Read an animation's beats off its body parts, not its name.** A probe plays the clip on the live character and logs
  the hands' or feet's height and reach in the root's frame every frame: the Greatshield's Ultimate (0.667 s) grabs the
  shield on its first frame, lifts it to 0.26 s and slams it into the floor at about 0.5 s (the server's
  `ULT_DOME_RAISE_DELAY`); the Charge's Running loop (1 s) plants the right foot at phase 0.07 and the left at 0.57.
  A sound or a puff placed on those beats lands on the motion; one placed on the button does not.

### A hat on a head (the Mortar Hat, 2026-11-11, unjudged)

`MortarHatMotion` is pure, sampled by MortarHatClient (every hat it has seen) and the bench. **Its joint is free to
write**: the hat's Motor6D has Part0 the hat and Part1 the head, and its Idle and Equip clips key only the body (read
off the KeyframeSequences: every pose hangs under HumanoidRootPart > Torso). With C1 the identity and C0 (0, -1.35, 0),
the hat sits at `Head * Transform^-1 * C0^-1`, so a pose M in head space is `Transform = M^-1` (checked in a playtest:
writing (0, -1, 0) lifted the hat 1 stud).

- **Recoil**: a spring (22 rad/s, damping 0.36) kicked per shell, peaking 0.058 s after the kick and swinging back 29%
  past rest (lune). The hat sinks 0.32 studs and tips 16 degrees away from where the shell went; kicks are softened so
  a whole Salvo on one frame shows as about 2 shells, not 6.
- **Lean**: eased toward the burst's targets, held 0.35 s after the last shell, eased home.
- **Moments**: Heavy Shell's load (a hop, slammed down `inQuad`, a 22 Hz shudder, one counter-bob), Detonator's twist
  (a full turn with a hop, overshooting), the detonation's plunger (punched down in 0.07 s, settled), Mortar Strike
  raised and trembling at 11 Hz for the whole rain, a flare kick per sky shell and a big kick for the last one.
- **Idle**: a 0.04-stud bob and a 2.5-degree wobble on a random phase per hat. Measured in a playtest: at rest the hat
  sits 1.31 to 1.39 studs over the head centre, tipping up to 3.5 degrees.

### A gun that swings to its shots (the Shotgun, 2026-11-15, unjudged)

The old float had one move: every Blast snapped the gun back along its barrel and flipped it, easing home
exponentially. The Stomp's shots straight down and straight up left the gun pointing ahead, and Buckshot, Overdrive and
the landing never touched it. `ShotgunMotion` is pure (sampled on the wielder's clock by ShotgunClient and the bench), and
its offsets sit in the aim frame between the float and `FACE_OFFSET`: `HANDLE_C0_INV * float * motion * FACE_OFFSET`. The
grip is the aim frame's origin, so every turn pivots on the grip, as a hand would turn it.

- **Two springs, not one.** The recoil (24 rad/s, damping 0.4: peaks at 0.05 s, swings back 24% past the aim, heavier
  than the Revolver's 30 rad/s two-frame kick) and the pump, a stiffer spring (34 rad/s, 0.38) kicked 0.16 s after the
  last shot that nods the gun down and back up. Emptying the charges stacks the recoil and racks once at the end, so a
  burst never pumps between shots.
- **A move is keys, each from the last key's pose.** The first key starts from wherever the gun is drawn (`Play` copies
  the pose, its angles wrapped into one turn so a move ending a whole turn round never unwinds it), the last ends at
  rest with `Settle` (the Shovel's counter-swing above). A key can carry a tremor (fading or building, each axis on its
  own phase), a kick and a rack, fired as it starts. **A move owns its shot's kick**: the Stomp and the Overdrive cast
  call `Play` only, never `Shot`, whose rack 0.16 s later landed in the middle of the next swing. Rise: swung to the
  floor, rattling on the jet, swung back past level with a rack. Dive: swung to the sky, shaking harder as it falls;
  the landing cuts it short, since a dive lasts about a tenth of a second. Land: hammered into the floor `InQuad`, a
  22 Hz shudder, pried out past rest with a rack. Buckshot: a spin-cock, thrown out first, one forward turn about the
  grip racked as it goes. Overdrive: a shot to the sky, two barrel rolls down into the fire, a rack as it levels, and a
  13 Hz shiver for the whole ult.
- **A swing and the recoil's flip add up.** The user saw the Overdrive cast "go a little crazy": the cast's kick flips
  the muzzle about 50 degrees, which stacked on the 55-degree swing to the sky put the gun past vertical over the head,
  and its two twirls about the grip then swept the muzzle 0.5 studs from the body's axis, through the torso. The dive
  went over the head the same way and the rise's kick swung the muzzle into the legs. The fix: the flip and the kick's
  lift scale with the cosine of the move's pitch (a gun swung to the floor or the sky is only shoved along its
  barrel), and nothing turns about the grip toward the body: Overdrive rolls about the barrel, and the spin-cock is
  thrown 1 to 1.4 studs out first. Measured in lune: the muzzle now stays at least 1.26 studs from the body's axis on
  every move (the rise is the closest), and the highest a move takes it is 87 degrees (the dive).
- **The tip's speed decides the swing's length** (measured in lune at 60 fps, the muzzle 2.9 studs from the grip). A
  quarter turn takes 0.09 to 0.11 s `OutQuad`: `OutCubic` put 3.5 studs on its first frame. A spin-cock at 0.085 s
  (to land on the sound's cock at 0.12 s) peaked at 5 studs a frame, a teleport; at 0.3 s it peaks at 2.0, so the rack
  fires as the spin starts instead of at its end. The fastest frame left is the dive's shot (3.0, kick and swing
  adding).
- **A pose that aims vertical does not trail.** The float tips the muzzle against the body's vertical speed (flown up by
  a Blast it tips down), scaled by the same cosine, or the rise's straight-down pose would tip past the floor into the
  body.
- Directions checked with real engine CFrames (`run_luau_live`): pitch -90 points the muzzle straight down, +80 up,
  the kick's +pitch flips it up and its +Z slides the gun toward the body. Not yet played: the lean's roll sign.
- `shotgunbench` stands each piece twice: the old bump (Before, copied into the bench only) beside ShotgunMotion
  (After), on the same beats.

### Making it cheap, and keeping it so

- **Build a layer only while it moves.** Recoil, flourish, reload and strain each return nil (or are skipped) at rest,
  so an idle frame writes the cached Transform with no CFrame work. The same goes for an ease toward zero: Whirlwind's
  share `w += (0 - w) * k dt` never reaches 0, so the lean branch ran on every idle frame. It now snaps to 0 under 1e-3.
- **Fold turns into one rotation.** `CFrame.lookAt(at, at + out, up)` with `out = (sin a, 0, -cos a)` is
  `CFrame.new(at) * CFrame.Angles(0, -a, 0)`; checked in the engine (`run_luau_live`, worst axis error 2e-7). A twirl
  about the same axis goes in the same `Angles`, and a fixed rest rotation is a module constant (`UPRIGHT`), not
  rebuilt every frame. Lune's `CFrame.lookAt` faces backwards (CLAUDE.md), so check the facing against its definition
  (Look = target direction, Right = Look x Up), never against lune's lookAt.
- **Hold the data, not its name.** A shovel's motion holds its blow's table (`motion.Blow`), not a name looked up
  every frame.

## 10. The players' procedural body (Kill All The Monsters, 2026-11-20)

Players here are R6 and walk on Roblox's default Animate (its clips are Roblox's and play in any game).
`BodyPoseController` lays the rest on top in code: `Motion` (lean, legs), `Aim` (aim, hands), numbers in its `Tune`.

- **Holding a gun, the body faces the aim, cursor locked or free.** Left to Roblox, a free cursor turns the body to
  each walk key, so backpedalling spun it round and the torso twisted back to the aim until its 80 degree limit: a
  body sideways to its own gun. Movement never turns an armed body; the legs and the lean show it instead. A free
  cursor turns it eased (16/s, at most 900 degrees/s), so a flick swings rather than snaps.
- **The lean tips from the feet toward the acceleration, plus a little toward the speed**, on a spring that overshoots
  once (13 rad/s, damping 0.5). Simulated in lune: a start peaks at 16 degrees and settles at 7, a stop skids back 9
  and settles, a backpedal holds 7 back. Acceleration alone makes starts, brakes and turns all read right; speed
  alone only says "moving". A third of it in the air, and a dip forward on landing scaled by the fall.
- **The legs turn toward the walk, up to 60 degrees, while the chest stays on the aim.** Past 100 degrees off the
  facing (12 either side so a sideways walk does not flicker) it is a backpedal: the hips face the aim and the walk
  clip runs backwards. The default Animate re-sets the clip's speed (always forward) whenever the walking speed
  changes, so the sign is re-asserted every frame.
- **The head takes back 85 percent of the lean** and the arms' aim frame undoes it exactly (in reverse of the order
  it was applied), so the eyes and the gun stay on the target while the body tips under them.
- **Order:** every C0 before the Animator (PreRender), the arms' Transforms after it (PreSimulation), so the walk
  plays under the pose and the arms are the last word on the shoulders.
- **"In the air" is read off the vertical speed, not `Humanoid.FloorMaterial`**, which is only simulated for the
  local body: on another player's it reads wrong.
- **Per frame:** one gun lookup per body, no tables built. The same pose runs for every body on every client, from
  replicated velocity and the relayed aim (`Weapons.Aims`).
