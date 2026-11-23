# First-person guns

How a gun is held in first person (`ViewmodelController`), and how to add or fix one without a round of guessing.
Section 7 is the same gun worn across the back, section 8 the same grips in third person.
The look was matched to reference screenshots of a first-person arena shooter at 90 FOV; this game's base FOV is 70.

## 1. The picture to hit

Judge every gun against these, on the straight-ahead frame:

- **The barrel runs along the view.** The gun sits under the eye and a little right, and its barrel line ends just
  below and right of the crosshair (about 2% right, 6-9% down the screen). A gun parked far right and turned inward
  reads as pointing somewhere else.
- **Arms run forward, never down or up into the gun.** The shoulders are behind and below the camera, so an arm
  enters from the bottom edge and runs along the gun to its hand. To fix an arm that comes down onto a handle, move
  the GUN (lower, further), not the shoulder.
- **Left arm from the bottom left** to the handguard or the top handle, beside the gun, not across it. The right arm
  is mostly hidden under the gun.
- **Hands on the model's real grips.** The user checks each gun's handles. Never place a hand by a guess from the
  bounding box.
- Arms are blocks 0.3 studs wide (`Tune.ARM_WIDTH`). Thinner reads as sticks.

## 2. What each gun carries (its data file)

`src/Global/Data/Guns/<Gun>.luau`, all shares of the BUILT gun's box (after `buildGunTool` scales and turns it):

| Field | Meaning |
| --- | --- |
| `Hold` | `Rifle`, `Pistol`, `Heavy` (handles on top, carried low) or `Launcher` (on the shoulder) |
| `Hands.Right`, `Hands.Left` | where each hand closes: X = share of the length from the BACK, Y = share of the height from the BOTTOM |
| `Barrel` | share of the height, from the bottom, where the barrel's axis runs |
| `IsFlipped` | the model's long axis points backwards |
| `PitchDeg` | roll about the barrel, for a model built on its side |

Which grip each hand takes:

- **Rifle:** right on the pistol grip, left under the handguard (the hold lowers it by `LeftDrop`).
- **Pistol:** both on the grip, left a little lower.
- **Heavy:** right on the rear handle, left on the TOP carry handle. A handle that runs across the gun looks like a
  thin post from the side: look at a three-quarter view before deciding it is a sight.
- **Launcher:** right on the front (trigger) grip, left on the rear grip.

## 3. Adding or fixing a gun

1. Put the model in `Assets/models/Guns/<Rarity folder>/<ModelName>.rbxm` and write its data file with a first guess
   for `Hands` and `Barrel` (copy a gun of the same hold).
2. Run `tools/ree/guns.sh "<gun Name>"` from the repo root. It fetches the model's meshes through Tripwire if they
   are missing (they are private; Tripwire must be running), and writes
   `Assets/models/Guns/preview/viewmodel/check/<Name>.png`: the side view on top, two first-person frames under it.
3. Read the side view. The grid is one line per tenth of the box (white 0 and 1, yellow the half), the red ball is
   the right hand, the blue the left, the green line the barrel. Move the numbers until each ball is ON its grip and
   the green line runs down the middle of the barrel. If the muzzle is on the left of the picture, the model is
   backwards: set or remove `IsFlipped`.
4. Run it again and read the first-person frames against section 1. The red cross is the crosshair.
5. If the gun is right on its side view but wrong in first person, the problem is the HOLD, not the gun: section 4.
   Check what else uses that hold before changing it (`tools/ree/guns.sh` with no names renders every gun).
6. For motion (raise, look, shots, walk, jump, a free cursor's aim, the upgrade flourish):
   `MESHES=Assets/models/Guns/meshes tools/ree/viewmodel.sh "<gun Name>" <model file> <out dir>` writes a clip and a
   frame sheet.
7. Measure it for the back (section 7). Do it again whenever its model or its `Length` changes.
8. Look at it in third person (section 8): `tools/ree/bodyposeall.sh "<gun Name>"`.

## 4. The holds (`HOLDS` in `ViewmodelController`)

Camera space: +X right, +Y up, -Z forward. At FOV 70 a point is on screen while `|y / depth| < 0.70` and
`|x / depth| < 1.245`.

| Field | Meaning |
| --- | --- |
| `Scale` | the copy's size against the Tool |
| `Grip` | where the barrel line passes at the right hand's depth |
| `Cant` | resting pitch (X, up), yaw (Y, inward) and roll (Z), radians |
| `Right`, `Left` | the shoulders. Keep Z positive (behind the camera) and Y near -1, or an arm's cut end shows |
| `LeftDrop`, `LeftSide` | lower the left hand, or move it left of the gun's middle, so the arm sits beside the gun |
| `Back`, `Climb` | how far a shot pushes the gun back and tips it up |

How to move things:

- Muzzle too low on screen: raise `Grip.Y`, or add `Cant.X` (0.05 is 3 degrees). Too far right: lower `Grip.X`.
- Gun too small: raise `Scale`, or bring `Grip.Z` toward 0. Nothing nearer than depth 0.5 should be on screen (the
  near plane can clip it): that is why the Heavy hold sits at -0.7.
- An arm covers the gun: move the hand to the side (`LeftSide`), or push the gun further so the arm is smaller, or
  move that shoulder out and down. For a hand on a rear handle near the camera, lower the gun until the hand is at
  the bottom edge.
- The left arm crosses the gun: move `Left.X` further left, so it comes in diagonally from the bottom left.

## 5. Mistakes already made

- Reading the reference's code and keeping our own placement. Copy the reference's LAYOUT first (where the gun and
  arms are on screen, measured off its screenshots), then adapt.
- Placing the gun by a share of its box height: a scope or a long magazine moved every gun differently. It is
  placed by its barrel (`Barrel`).
- Arms hung from above or beside the eye: they came down onto the gun. Shoulders go behind and below the camera.
- A gun bob at a different step rate from the camera's bob: the two beat and the hands shake. `Tune.BOB_STRIDE` is
  the camera's rate.
- Feeding the look sway the final camera (bob, recoil, shake): it rattles. It reads `CameraController.AimCFrame`.
- Coins homing on the chest in first person fly through the view: each homes on a point beside the body
  (`CoinsController`'s `FIRST_PERSON_SIDE`).

## 6. Known rough spots

- Only the Starter Pistol's model has a `Muzzle` attachment; on the others the Tool's muzzle is the middle of the
  gun's front, so tracers leave under or over the barrel. `Barrel` could place it in `buildGunTool`.
- The Starter Sniper's model is tilted inside its file (10.6 degrees, measured by `tools/ree/backgunfits.py` for the
  back), so its barrel dips. The back corrects it; the hand does not.
- The offline renders have bare arms and untextured guns: sleeves and skins are only seen in a playtest.

## 7. The gun on the back (`BackGunController`, `Utils/backGunModel`)

The gun a player picks with SHOW on the lobby's weapons screen (`TProfile.Loadout.Shown`) is worn across the back
in the lobby only (never in a match): `BackGunService` tells every client (`Loadout.Worn`) and every client draws
it. It leaves the back while that same gun is held in hand (the range).

### The picture to hit

- The same size as in the hand (scaled to `Length`, as `buildGunTool` does).
- Barrel up over the right shoulder (`SLANT_DEG`), its side flat on the back, never standing off it at a lean.
- What is SEEN of it centred across the back (`RISE` over the UpperTorso's middle), and its nearest face just off
  the back (`GAP`). The three are `Tune` in `backGunModel`.
- Judge it from behind (centred?), side on (touching, and no lean?) and from straight above (parallel to the back?).
  The bug reports came from the last two: from behind a lean does not show.

### Adding a gun, or changing its model or `Length`

1. Get its hold right first (section 3). That also puts its meshes in `Assets/models/Guns/meshes`.
2. From the repo root, run `tools/ree/backgunfits.sh`. It measures every gun and rewrites
   `src/Lobby/Client/Utils/backGunFits.luau` (generated: never edit it by hand), one line per gun:
   `lean` and `roll` (the correction this pass, degrees), `ratio` (how much taller than wide the gun is seen down its
   barrel), `near` and the outline's point count. It runs again until every correction is under 0.3 degrees, which
   from fits already in place is one pass; from scratch, four or five. "not converged" means read the numbers: a gun
   whose correction swings sign each pass is the case `ROLL_DAMPING` is for.
3. Look: `tools/ree/backgunall.sh Assets/models/Guns/preview/backgun-all` draws every gun on a body from behind,
   side on and from above (`sheet.png`, three pictures a gun in that order).
4. For the motion (on, off, drawn into the hand, put back):
   `MESHES=Assets/models/Guns/meshes tools/ree/backgun.sh "<gun Name>" <model file> <out dir>`.

A gun with no entry in `backGunFits` still goes on the back, fitted by its parts' boxes: close, but it can sit off
centre and stand off the back (the next section says why). Measure it.

### Why it is measured off renders

Every one of these was a bug on screen first:

- **A part's box is not the gun.** Centring a pistol's box put it off to one side: the box is mostly air under the
  slide. Several models carry invisible effect parts (`VFXPart`, `Tip`, `TrinketPoint`, `FirePart`) far bigger than
  the gun: Poison Pistol, Hacker Drum, UFO Bullpup (one 7.8 studs long), Lavaforge, Corrupted Runes AK. Only what is
  drawn counts.
- **Some meshes are modelled at a lean inside their own part box.** The Starter Sniper leans 10.6 degrees in its
  box, so a gun lying flat by its box stood off the back at a tilt. Nothing in the engine can see inside a mesh.
- **`GunsCore.FindAxes` takes the gun's top from the MODEL's pivot**, which on some models is turned against the
  parts. Every part of one model is turned alike, so the unmeasured fallback snaps the side to the biggest visible
  part's nearest axis.
- **"Lay it on its thinnest side" is wrong**: some guns are wider than they are tall. The Starter Sniper went onto
  its belly.
- **The vertices cannot be read.** `EditableMesh` refuses the guns' meshes (they belong to another group, not to
  this experience's owner) and the files are Draco-compressed (mesh version 7). So `ror --ids` draws each gun as
  exact per-part masks, from cameras 400 studs away at 1.5 degrees, so a stud is the same number of pixels at every
  depth of the gun. Seen from above, the silhouette's long axis is where the barrel runs (the lean). Down the
  barrel, its tall axis is the gun's top (the roll). Side on, it is what is seen from behind (the outline used for
  centring). The lowest it reaches along its side is the face that goes on the back.
- **Roll is left alone on a round gun** (`ratio` under `ROLL_RATIO`, 1.5): down the barrel a drum or a gatling has
  no top to find, and the Hacker Drum wobbled half a degree each pass. It is halved each pass (`ROLL_DAMPING`)
  because a gun turned in its own plane by its data (the RPG's `PitchDeg`) swung past its answer every pass.
- **A gun with a drum or a tank touches the back with it.** The Hacker Drum's barrel and the Flame Gatling's body
  sit off the back by that much. That is the gun's shape, not a fit to fix.

### How it moves

- At rest a back gun costs nothing a frame: it is welded to the UpperTorso and the body carries it.
- While it moves (on, off, into the hand) every part is anchored and its welds are off, and it is scaled and placed
  by hand each frame: scaling a model welded into a live body drags the body. The welds go back on in the same frame
  the motion ends.
- Each gun is built once and cloned for every back. Further than `MOTION_RANGE` from the camera it goes on and off
  at once and silently.
- The lobby has no `R6Body`, so its avatars wear the default blocky R15 UpperTorso (2 x 1.6 x 1, the bench's body).
  The slot reads the torso's `Size`, so a scaled body moves it.

### Known rough spots

- A player's own avatar items on the back (a cape, a backpack) overlap the gun. Nothing removes them.
- A gun's particle effects and beams run on the back as well as in the hand (the Corrupted Runes AK has 99
  emitters, the UFO Bullpup 71).
- The landing knock is `Weapons.Revolver.Holster`, wired before a listening round.

## 8. Third person (`BodyPoseController`: `Aim`, `Tune.HOLDS`)

Every R6 body holding a gun puts its hands on the same grips as first person: both read `Hands` and `Barrel` through
`Utils/gunGrips`. A new gun whose side view is right (section 3) usually needs NOTHING here: its hold places it.

### The picture to hit

- **Hands on the gun's real grips**, the same as first person.
- **The gun rests ON the hands**, never through them. An R6 hand is a 1-stud block; a thin gun centred in one vanishes.
- **The hand blocks lie flat** against the gun, never on a corner.
- **The gun is clear of the body**: out in front, right of centre, never inside the torso or the head.
- Per hold: a **rifle** shouldered (stock at the right shoulder, right arm along it, left under the fore-end); a
  **pistol** out in front of the right shoulder, both hands under it; a **heavy** at the hip, hands over its top
  handles; a **launcher**'s tube beside the head.

### Checking a gun (about a minute)

1. `tools/ree/bodyposeall.sh "<gun Name>"` (several names, or none for every gun). The meshes must be in
   `Assets/models/Guns/meshes` already (`tools/ree/guns.sh` fetches them). It writes
   `Assets/models/Guns/preview/bodypose/<Name>/views.png` and every gun's row in `.../bodypose/all.png`: front-right,
   right side, behind on the left. A red ball marks the right grip, a blue the left.
2. Read it against the picture above. A rifle's blue ball shows just above the left hand: that is the drop, right.
3. If anything is off, print the numbers (paste the gun's Name and its model file's absolute path):

   ```sh
   ree run --harness tools/ree/BodyPose.luau --seconds 1.55 --offline \
     --context '{"Gun":"<Name>","Model":"<absolute model path>","Debug":true}' \
     --mount ReplicatedStorage/Packages=Packages --mount ReplicatedStorage/Types=src/Global/Types \
     --mount ReplicatedStorage/Data=src/Global/Data --mount ReplicatedStorage/GlobalShared=src/Global/Shared \
     --mount ReplicatedStorage/Shared=src/Game/Shared --mount ReplicatedStorage/ServerUtils=src/Global/Server/Utils \
     --mount StarterPlayer/StarterPlayerScripts/GlobalClient=src/Global/Client 2>&1 | grep -o 'DEBUG t=1.5[^"]*'
   ```

   `off` is each hand's end from its grip: when it lands it is exactly `HAND_INSET` and `Drop` together (0.32 and
   0.49 on a rifle, 0.25 and 0.40 on a pistol, 0.33 on a heavy). Bigger means the hand fell short. `slides` is how
   far each arm came out of its shoulder: at 0.50 that arm is at its limit and the gun was moved to meet it.
4. Fix by the table below, and render again. For motion (the raise, an aim sweep, a burst), one gun:
   `VIDEO=1 tools/ree/bodypose.sh "<gun Name>" <model file> <out dir>` writes `<out>/video/sheet.png` and a clip.
5. A hold change moves every gun of that hold: run `tools/ree/bodyposeall.sh` with no names and look at all of them.

| What is wrong | Fix |
| --- | --- |
| A hand on the wrong part of the gun | the gun's `Hands` (section 3): first person moves with it |
| The gun through a hand | raise that hand's `Drop` (`.X` right, `.Y` left) in its hold |
| A hand floating under or over the gun | lower that `Drop` |
| A hand on a top handle swallowing the gun | make its `Drop` more negative |
| The gun inside the body, or the left arm at `slides` 0.50 | more `Blade` (the gatlings went from 40 to 55 degrees) |
| The gun too close or too central | move `Grip` out (-Z) or right (+X); the arms slide out to follow |
| The gun through the head | `Grip.X` further right (the head is about 1.25 across) |
| One gun of a hold is off, the rest are right | that gun's `Hands` or `Barrel`, not the hold |

### How it works

- **The gun goes where it looks right; the arms come to it.** R6 arms are rigid (no elbow, the grip 1.58 studs from
  the shoulder joint), so an arm slides along itself out of the shoulder (up to `ARM_SLIDE_OUT`) or into it
  (`ARM_SLIDE_IN`). The hold's `Grip` (the barrel line at the right hand's depth, in the aim frame at the torso's
  centre) is kept while both hands reach it that way; past that the gun moves the least that brings them in
  (`SETTLE_ROUNDS` of pulling each hand into reach, the right last: its hand carries the gun).
- **`Drop`** puts each hand's end that far under its grip, across the arm, so the gun rests on the hand's face.
  **`HAND_INSET`** puts the grip that far inside the hand's end. Each arm is rolled about its reach so its front face
  is toward the gun.
- **`Blade`** turns the torso right off the aim, bringing the left shoulder forward to a grip far up the gun. The
  head turns back onto the aim; the standing legs take `LEG_BLADE` of it.
- **The kick** tips the aim frame, shoves the gun back along its barrel (`KICK_BACK`) and lets the arms further into
  the shoulders (`KICK_SLIDE`). **The raise** brings a new gun up from low and pointing down, past the hold and back
  (`RAISE_*`).
- Each body's shoulders are read once (`Aim.Shoulder`), its gun's grips once per gun (`gunGrips`), its grip weld once
  per gun: a frame does no lookups by name.
- In first person the body's gun and arms are hidden: the gun sits at `HOLD_FIRST_PERSON` and nothing is settled.

### Mistakes already made

- **Pulling the gun in until rigid arms reached its grips exactly.** Both hands landed, but the pistol ended up
  against the chest and the minigun inside the body. Let the arms slide out of the shoulder instead.
- **Centring a hand on its grip.** The 1-stud block swallowed the shotgun's and the rifle's fore-ends. Hands go under.
- **An arm left at its minimal turn** sits on its corner, which pokes up through the gun.
- **Rolling to whichever face is nearest the gun.** The face (and the shirt's sleeve on it) swaps mid-aim. Always
  the front face.
- **Too little blade** (under 40 degrees on a rifle): the only place both hands reach is the chest's middle, with the
  right arm folded flat across it.
- **Judging with a 2 x 1 x 1 head.** That is the part's box; an avatar's head mesh is about 1.25 across, and the
  RPG looked to go through it. The stand-in's head is 1.25.
- **Not looking from behind on the left and from the side.** The reported bugs (a hand through the gun, the gun in the
  body) show there; the front-right view hides them.
