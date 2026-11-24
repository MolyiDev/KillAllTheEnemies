# Models.md

> **Carried over from Ballarc (Last Wave) on 2026-11-20.** The method, the engine facts and the measured lessons
> apply here; the old game's look does not. Kill All The Monsters is not pixel art and not anime: maps are stud-style
> (LEGO-like bricks at real scale), UI is sleek and modern (`UIMatt.md` is the designer's spec). Sections named after
> a Last Wave weapon, boss or screen are worked examples. A path that does not exist in this repo (`Assets/...`,
> `tools/vfx/...`, a `src/Survivors/...` module) is in `../Ballarc`; `../Anime Zombie Survival` holds the enemy rig,
> map and burst pipelines this repo's `tools/` came from.

Getting a model made outside Roblox (a Blockbench glTF, in practice) into the game as a TOOL with a part that
moves. Learned on the pack (`Assets/models/Tools/Backpack/`, `ReplicatedStorage.Models.Tools.Backpack`), in four
uploads, and then worn on the back (§2b, the path every item on the body takes). Its animation is Animations.md §9; the single-mesh prop pipeline this builds on is the
`mcmodel-to-roblox` skill (`.claude/skills/mcmodel-to-roblox/reference/props-from-gltf.md`). Read that first:
everything there still holds.

§7 is the other half: shaping an ENEMY body in Blockbench so it sits beside the zombies. Its texture is
Textures.md.

## 1. The pipeline, in order

1. **Keep the source in the repo**: `Assets/models/<Kind>/<Thing>/model.gltf`, plus a `bake.py` next to it that
   turns it into what Roblox gets. Rebake rather than edit the output. `<Kind>` is the `ReplicatedStorage.Models`
   folder it ships in (`Tools`, `Weapons`, `Enemies`, `Drops`), and the thing's `.bbmodel` and `.blend` sit in the
   same folder. Enemies share one flat `Enemies/` folder, since their generators share `cull_hidden.py` and `refs/`.
2. **Bake**: `python3 bake.py <outdir>` writes one `.obj` + `.png` per moving part, texels baked into geometry
   (the skill's reason: Roblox draws a transparent texel BLACK and filters bilinearly), and a `bake.json` with
   where each part's centre sits in the model's own frame.
3. **Convert**: `blender --background --python .claude/skills/mcmodel-to-roblox/scripts/obj2fbx.py -- <outdir>`
   (it exports at `global_scale=0.01`, without which Roblox imports 100x too big).
4. **Check it offline BEFORE uploading** (§4). Uploads are the slow, irreversible part.
5. **Upload** each `.fbx` with Tripwire's `upload_asset` (`asset_type = "Model"`, `display_name` not `name`).
6. **Insert** each with `insert_model`; it arrives wrapped in two Models. Reparent the MeshPart into the tool's
   model with `set_property(..., "Parent", ...)`, delete the wrappers.
7. **Place the parts** at their `bake.json` centres, **turned half a turn** (§3), and set the flags every tool
   part here carries: `Anchored = false`, `CanCollide = false`, `CanTouch = false`, `CollisionFidelity = Box`.
8. **Ask for the place to be saved** (Ctrl+S). Models live in the PLACE, not in Rojo (`ReplicatedStorage.Models`
   is not in the project), and everything Tripwire does to them is lost without a save.

## 2. A model with a moving part

- **Bake one mesh per moving part**, cut where the animation hinges it. The pack's lid is everything of the main
  body group above `LID_CUT`, the same number `animation/packclips.py` uses, so the numbers in the clips (the
  hinge, the grips) are numbers on the model.
- **Cut only the group that should come apart.** Cutting every node by height took the top of the front pocket
  up with the lid; the pocket, the side pocket and the bottle belong to the body even where they stand above the
  cut.
- **End every quad the cut runs through ON the cut.** Cells are split by their centres, and a part whose texel
  grid does not land on the cut (an INFLATED box: the pack's straps) reaches half a texel past it. The straps'
  inner faces showed through the open mouth as two lines.
- **The cut opens faces, and they need texels.** Paint a small swatch per face into an EMPTY corner of the
  texture (assert it was transparent before painting) and map each cut face onto one texel of it. One texture,
  so each part stays one MeshPart. The pack's mouth is near black and its lid's lining brown, so an open pack reads
  as a hole with a lid over it rather than as a dark box.
- **Compose the node tree.** Blockbench groups are translated and ROTATED (the pack's bottle is tipped 7.5
  degrees, its front pocket 5), and the skill's `bake_gltf.py` applies each node's own transform only.
- **Write each `.obj` about its own bounding-box centre** and carry the centre in `bake.json`: Roblox re-centres
  an imported mesh on its box whatever you export.

### How the game holds it (the tool contract)

- A `Model` with an invisible `Handle` as `PrimaryPart`, at the ORIGIN the animation is authored about (the
  pack's is the body cube's centre), and one part per moving piece.
- `EquipService` welds every part to the Handle except those named in the tool's `Turning`, which get a Motor6D:
  `C0 = rest position`, `C1 = rest rotation inverse`. **That joint pivots at the part's CENTRE**, so a hinge is
  written as `C0 = T(hinge) * R * T(rest - hinge)` on the client (PackController's `setLid`). The write is local:
  other players see the part at rest.
- **A tool carried on the body while not in the hands is an ACCESSORY** (`TTool.Worn`: an R15 attachment name and
  an offset from it). EquipService clones the model into an `Accessory`, welds every part to the root, renames the
  root `Handle`, gives it an attachment named for the body's own, and puts it on with `Humanoid:AddAccessory` while
  the tool is owned and not held (the engine joins the Handle with an `AccessoryRigidConstraint`). **Join the other
  parts to the Handle with `Weld`s whose C0 is written out, parented under the part they hold, NOT under the
  Handle**: the engine's AvatarJointUpgrade has `AddAccessory` strip the joints inside the Handle (a known engine
  bug, "AvatarJointUpgrade removes extra accessory parts"), and the pack's Body and Lid were left lying where the
  prefab sits, under the ground, while the invisible Handle sat on his back. A prebuilt accessory would hit the
  same thing; it is where the weld lives that matters. Measured: welds under the parts survive on, off and on again. The
  attachment keeps it right on any body's scale, it replicates, and the
  first-person hiding and the pack screen's doll (which copies every `Worn` accessory) already take accessories as
  body. The body attachment name must exist ONLY on the accessory copy: the engine matches such names anywhere in
  the character outside tools and accessories, so a plain model under `Weapons` carrying one steals other
  accessories' welds. Armor, weapons at the waist and rings are meant to go the same way.
- **Read a joint's rest ONCE and hold the joint by a plain reference.** A weak-keyed table of Instances lost the
  entry mid-animation and the next read took an already-turned C0 for the rest (Animations.md §9).

## 2b. Wearing it: armor, a weapon at the waist, a ring, a pack on the back

Everything he has on that is not in his hands is an `Accessory` built from the item's own model, and there is one
path for all of it. To add the next one:

1. **Give its data a `Worn`**: the R15 attachment it goes on and an offset from it. The attachment is what makes
   it right on every body: it moves with the avatar's scale, where a fixed offset from the torso does not (the
   test avatar's back attachment sat at 0.53, not the stock 0.5). The R15's own, on the parts that carry them:
   - UpperTorso: `BodyBackAttachment`, `BodyFrontAttachment`, `LeftCollarAttachment`, `RightCollarAttachment`,
     `NeckAttachment` (read off a live body)
   - LowerTorso: `WaistBackAttachment`, `WaistFrontAttachment`, `WaistCenterAttachment` (a weapon at the waist)
   - arms: `LeftShoulderAttachment` / `RightShoulderAttachment` on the upper arms, `LeftGripAttachment` /
     `RightGripAttachment` on the hands (a ring); the head carries `HatAttachment`, `HairAttachment`,
     `FaceFrontAttachment`, `FaceCenterAttachment`
   The UpperTorso's were read off a live body; read the others off one too before choosing an offset, and
   the place of any, since they move with the avatar's scale.
2. **EquipService does the rest** (`makeWorn`, `refreshWorn`): it clones the model into an Accessory, welds the
   parts, names the root `Handle`, adds the attachment, and puts it on while the item is owned and not in the
   hands, taking it off (unparenting it, keeping it) while it is. The attribute `Worn` marks it.
3. **Nothing else to wire**: the first-person view hides every part of the character, accessories included;
   the pack screen's doll copies every `Worn` accessory each time it opens (`PackController.dressDoll`,
   without the joint that holds it to the live body) and `rigPreview` seats it by the attachment names.
4. **If the item has a held clip that takes it off the body**, start that clip from the worn place, read off
   this body's attachment (`PackHoldClient` does it for the pack), not from the clip's own first frame.

The rules the pack paid for:

- **Weld the parts with `Weld`s whose C0 is written out, parented under the part they hold, never under the
  Handle.** Two different failures, both leaving the visible parts under the ground where the prefab sits while
  the invisible Handle sat on his back: the engine's AvatarJointUpgrade has `Humanoid:AddAccessory` DELETE the
  joints inside the Handle (a known engine bug), and a `WeldConstraint` takes its offset when it goes live, which
  is the step the engine moves the Handle onto the body. A prebuilt accessory hits the first one too; where the
  weld lives is what matters. Measured on a live server: welds under the Handle, 0 left and the pack 24 studs
  under; under the parts, both kept through on, off and on again.
- **`AddAccessory` is the right call**; it joins the Handle with an `AccessoryRigidConstraint` (a hand-made
  `AccessoryWeld` was replaced by it). Copy an accessory elsewhere (the doll) WITHOUT that constraint, which still
  points at the live body's attachment.
- **The body attachment name exists only on the worn copy.** The engine matches those names anywhere in the
  character outside tools and accessories, so the held model under `Weapons` carrying one would take other
  accessories' welds.
- **A player's own avatar accessories share the attachments**: a cape or wings on `BodyBackAttachment` sits
  where the pack does. Nothing removes them yet.
- **Seen from the front a back item is hidden by the body.** The pack is narrower than the torso and its top is
  under the shoulders; check a worn item from behind before calling it missing.

## 3. What the Roblox importer does to it

- **An FBX exported by `obj2fbx.py` arrives turned half a turn about Y.** The pack came in with its front toward
  the player and its two parts apart (each spun about its OWN centre, which sit at different depths). Fixed on the
  parts, not in the bake: each stands at `CFrame.Angles(0, math.pi, 0)` about its centre, and that has to be set
  again on any re-uploaded part. The revolver's rounds did the same (Animations.md §8).
- **Tell a half turn from a mirror by reading the mesh back.** In a playtest,
  `AssetService:CreateEditableMeshAsync(Content.fromUri(part.MeshId))` gives every vertex: the mean of the pack's
  came back with X and Z both negated against the bake and Y unchanged, which is a rotation. A mirror negates one
  axis, flips the winding and shows the faces inside out, and after "fixing" it with a half turn it would leave
  left and right swapped. Vertex counts differ from the `.obj` (the importer splits vertices), so compare signs,
  not values.
- **Sizes come through exactly** (the pack's parts read back at their baked dimensions to the thousandth), so a
  size check after inserting proves the scale and nothing about the orientation.
- **`MeshPart.MeshId` cannot be set by a script.** A new mesh is a new part: insert it, move the old one into a
  backup folder (`ReplicatedStorage.BackpackOldParts`), and delete the backup only once the new one is confirmed.

## 4. Checking a bake before and after

- **Before uploading, render the baked meshes where the game will draw them.** Load the `.obj`s onto the Blender
  rig (`Assets/models/<Kind>/<Thing>/<Thing>.blend`) at their `bake.json` centres, parented to the same bones, and render them
  through the game's lens beside the source meshes. The importer's half turn and the parts' half turn cancel, so
  this IS the game's geometry. That comparison shows a pocket cut into the lid or a strap poking through the mouth
  at a glance.
- **The texture that counts is the one EMBEDDED in the glTF.** The `.png` beside it in the download was a
  different image, not just a flipped one (its pixels differed across a 45 x 64 region), and pairing it with the
  glTF's UVs shredded the model: the texture landed on the wrong faces. `bake.py` reads the embedded one.
- **After uploading, read it back out of the engine** (§3) rather than trusting the exporter.

## 5. Tripwire, for this kind of work
- **Check Studio has the code before a playtest**: `grep_scripts` for a symbol the change added. With `rojo serve` not
  running, Studio keeps the old scripts and a playtest tests the old code without a word of warning.
- **A Studio playtest's server Heartbeat runs at 240 Hz**, not 60: a probe counting frames counts quarter-sixtieths
  (239 frames was the Nest's 1 s brood hold). Time with `os.clock()`, or measure the rate in the probe.
- **Keep every `run_luau_live` call short.** A call that waits (a `task.wait` of a few seconds, or several steps
  with waits between) timed the bridge out at 30 s and often took the playtest's server peer down with it; after
  that, starts kept coming back with "No live server peer" for a long stretch. One step per call: give, then
  read, then act. A playtest the USER started can be read the same way.
- **Server state answers most worn/held questions without a probe**: accessories, welds, part positions relative
  to the UpperTorso all replicate. Client-only state (IK, a lid's C0 the client writes) still needs a LocalScript.

- `capture_screenshot` works in EDIT mode only and needs the Studio window on a monitor; when it is minimised the
  call times out. There is no screenshot of a playtest, so a playtest is read as numbers from a probe.
- The playtest sometimes never registers a server peer, and `run_luau_live` often times out while the place is
  still booting. Wait about 20 s after `start_playtest`, retry once, and stop after two failed starts.
- A probe is a `LocalScript` in `StarterPlayer.StarterPlayerScripts`, created in edit mode and deleted after.
  A component that makes Vide state (`rigPreview`) must be called inside `Vide.root` from a probe.

## 6. What is uploaded

| Model | Part | Asset | Placed at (in the model) |
|---|---|---|---|
| `Models.Tools.Backpack` | Body | 71363589342614 | (0.02411, -0.26311, -0.27491), yaw 180 |
| `Models.Tools.Backpack` | Lid | 83773605440685 | (0, 0.63437, 0), yaw 180 |

Scale: `STUDS_PER_UNIT = 2.8` (0.175 studs a Blockbench pixel), sized against the torso, since a pack is worn: the
body is 1.4 x 1.75 x 0.875 studs. The hotbar draws it upright and front on (UI.md §5n).

## 7. An enemy body in Blockbench (the zombie family)

Measured off `Assets/models/Enemies/ZombieNormal`, `ZombieRunner` and `ZombieBrute`, and paid for on the ZombieSpitter
(`Assets/models/Enemies/ZombieSpitter.bbmodel`, generator `zombie_spitter.py` beside it). Its first build used one
long box per limb and z-fought at the feet; the second followed this section and was accepted. Six more enemies
were then built from this section and Textures.md in one round (the roster below), each passing review in at most
one revision. How to paint it is Textures.md; how to measure the originals is Textures.md §5. `Assets/` is
gitignored, so the models and their generators live on this machine only.

### The rig

- **Bones**: `Root` > `Torso` > `Head`, `ArmLeft`, `ArmRight`, `LegLeft`, `LegRight`, with the legs under the
  torso like the arms. The Brute adds `ForearmLeft`/`ForearmRight`; the Charger adds knees and ankles under each leg,
  `ShinLeft` > `FootLeft` and `ShinRight` > `FootRight` ("Legs" below). Keep these names: the enemy clips key bones by
  name.
- **Front is +Z, the zombie's left is +X** (`ArmLeft` sits at about x = +11).
- **The model is centred on the origin in Y**, feet at the bottom of `Root`'s pivot: Normal stands -21.7 to 21.7,
  Runner -26.6 to 26.6, Brute -28.9 to 28.9. The Spitter is -26 to about 21, shorter for its hunch.
- **The rest pose is baked into the geometry**, bones at zero rotation. A hunch, a dangling arm or a hanging jaw
  is a rotated box, not a rotated bone. This is deliberate and stays (decided 2026-09-26): every clip inherits the
  posture for free, a channel a clip forgets falls back to the silhouette instead of snapping the body upright, and
  the idle only has to breathe on top of it. The Normal does the same (its hunch and tipped head are in its mesh).
- **The clips key these bones** (read off the originals' Idle, Walk, Attack, ReceiveAttack and Death):
  `Root`, `Torso`, `Head`, `ArmLeft`, `ArmRight`, `LegLeft`, `LegRight`, plus `ForearmLeft`/`ForearmRight` on the
  Brute. They key position and rotation only.
- **Pivots follow the Brute**: an arm's pivot sits at the CENTRE of its shoulder block, so the block turns in place
  (the Brute: pivot x 16, y 10.6, with the pad spanning x 10..22 and y 5.1..16.1); a leg's pivot sits inside the top of
  its thigh; the head's is low at the back of the head; a forearm's is at the elbow. The Charger's first big arm
  pivoted 13 below its shoulder cap, outside every shoulder box, and a swing would have lifted the hump off the body.
  Check it in code: every limb pivot must lie inside that limb's top box.
- **Legs rest straight**, even on a runner: the walk clip makes the stride.
- **A part that must animate on its own gets its own bone**: the Charger's `ForearmRight` (the big arm swings on
  its own), the Shield's `Shield` under `Torso` (pivot at the grips). A structure has no humanoid bones at all: the
  Nest is `Root` > `Body` > `Pod1`..`Pod5`, `Mouth` > `Jaw`, `Arm`, with the debris on the ground hanging straight
  off `Root` so a pulse of `Body` leaves the wreckage still (§9 has why it grew the Jaw and the Arm, and why the beam
  rides Body).

### The roster

Every one of these has its `.bbmodel`, a generator `zombie_<name>.py` beside it, and renders in
`Assets/models/Enemies/refs/<Name>_4view.png` / `_close.png`. The six after the Spitter were built in one round by
six sessions from `refs/BRIEF.md`.

| Enemy | Role | Height | Boxes | Triangles | Silhouette |
|---|---|---|---|---|---|
| Normal, Runner, Brute | the originals (meshes) | 43 / 53 / 58 | - | 316 / 494 / 484 | hunched / ribcage / slab |
| Spitter | stops at range and lobs a shot | ~47 | 35 | 374 | bloated gut, sacs on a hunched back, jaw hanging over a throat sac, bone arm and leg |
| Charger | winds up, dashes in a line | 70.7 (54.4 before the 1.3 scale) | 39 | 430 | an enormous right arm and shoulder towering over a sunk head, a withered bone arm, leaning 28 deg |
| Exploder | runs at walls and the Core and blows up | 48.5 | 45 | 482 | a Boomer: fat all over, a drooping pustule gut under a too-small mustard shirt, a bone arm |
| Shield | can't be hurt from the front | 51.6 | 44 | 470 | a door carried in front; the back torn open to a spine and ribs |
| Summoner | keeps spawning Summons | 57.7 | 45 | 472 | tall, hollow hood, a brood sac rising over the head, bone shins and right arm |
| Summon | the small thing that is spawned | 18.5 | 16 | 176 | a big-headed pink knuckle-walker, one bone arm |
| Nest | a structure that spawns Summons | ~27, 38 x 38 across | 58 | 610 | a flesh mound with a face, a toothed mouth, pods and a zombie arm clawing out |

Round 1's versions are kept in `Assets/models/Enemies/v1/`.

### The shapes

Every body part is a STACK of boxes that taper and widen, never one long box. Sizes in units (1 unit = 1 texel):

| Part | Normal | Runner | Brute | Spitter |
|---|---|---|---|---|
| Head | 12.8 x 12.8 x 10 | 10 x 10.8 x 10.8 | 12 x 15.7 x 15.7 | 10 x 10 x 10 |
| Chest | 18 x 10.6 x 12 | 18 x 9.6 x 12.4 | 22 x 16.6 x 16.8, bevelled | 19 x 9 x 12, hunched 18 deg |
| Waist / pelvis | 16 x 4 x 8 | spine and six rib bars, pelvis 14 x 4 x 8 | three blocks 16 > 12 < 14 wide | 18-wide belly, 15-wide gut overhang, 16 x 5 x 9 pelvis |
| Shoulder | 8 cube | 6 x 6.3 x 6.3 | 12 x 11 x 12, bevelled | 6 cube |
| Upper arm | 4 x 6 x 4 | 4 x 5.1 x 4.2 | 6.4 x 8.3 x 6.2 | 3.5 x 8 x 3.5 |
| Forearm | 4.4 x 5.4 x 4 | 4.6 x 6.2 x 5.1 | 10.3 x 8.4 x 9.5 | 4.5 x 8.5 x 4.5 |
| Hand | 6.5 x 7.5 x 6 | 4.9 x 5.6 x 4.9, thumb 2.4 | fist 10 x 8 x 9, four chunky fingers ~5 x 5 x 4, a thumb | 5.5 hand, two chunky curled fingers, a thumb |
| Thigh | 8 x 5-7 x 8 | 8 x 8 x 10 | 7 x 7 x 8 | 7 x 8 x 8 |
| Shin + foot | 4-6 wide, one L-shaped box with a toe | 4 x 9 x 7, L-shaped | 5 x 10 x 9, L-shaped | 5.5-wide shin with the jeans' cuff painted, a boot; the left one bare bone, 3.5 wide |

What that table says:

- **An arm narrows below a big shoulder block, then WIDENS again at the forearm and the hand.** The thin upper
  arm is what makes it read as a limb and not a pipe.
- **A leg is TWO segments: a thigh, then a shin with a foot poking forward at its bottom** (the originals' L).
  One visible step at the knee. See "Legs" below.
- **Every enemy gets a silhouette of its own from the torso**: Runner is hollowed out (spine and ribs showing),
  Brute is a bevelled slab with Popeye forearms, Normal is hunched with its head tipped. The Spitter is a bloated
  gut with a hunched back carrying sacs, the jaw hanging open over a swollen throat.
- **Details are small boxes on the big ones**: a headband, sacs, a drip, a pod. Each is its own box poking at
  least half a unit out of what it sits on. Not claws, toes or knuckles (see "Hands" below).
- **A small, numerous enemy has a box budget** (the Summon: 15). Drop the shoulder block but keep upper arm <
  forearm < hand, and make a leg thigh > flat foot with the toe forward; a shin + foot L is too much at that size.

### Making the role read

The brief for each enemy was a role ("can't be hurt from the front", "blows up"), and the model had to say it
from the front AND the side at the reference distance, with no animation:

- **Proportion carries the role before any detail does.** The Charger's first build had the big arm and the
  small arm, and still read as a normal zombie beside a big arm, because the head sat at shoulder height and the
  small side had a bulky shoulder. What made it the Charger: the head sunk 8.7 below the big shoulder's top,
  pushed forward and tipped down; the small side reduced to a 5-wide shoulder sloping away from the neck; the
  lean taken from 16 to 28 degrees.
- **Something on the back is invisible from the front.** The Summoner's sac needed a crown rising over the head
  and a second swelling at the belly before the front view said "brood". The crown has to be one lumpy mass
  wider than the hood: two small points at the hood's corners read as cat ears.
- **Show the weak side.** The Shield's back is torn open to bare skin and a wound, the one green-and-red patch on a
  navy body, so "hit here" reads from behind. From the front it is a walking door with one eye over a broken
  plank.
- **A structure needs a face** (Textures.md §4), and it must not stack like a cake: offset each tier's centre from
  the one below and give the upper tiers small yaws of different signs (the Nest: 8 and -10 degrees).
- **A hard hat is dome + crown step + peak.** One dome with an all-round brim reads as a bucket or a sun hat.
- **A robe split per leg reads as shorts** until the hem goes below the knee and tatter boxes hang under it.
- **A hole is a ring of boxes standing proud of a dark box** (cubes cannot have holes): the Nest's mouth is four
  lips 2.5 proud of a recessed throat. A tear in clothing reads better as a recess than as paint: the Shield's
  jacket round the tear is its own boxes, 0.5-1.25 proud of a skin-painted body box.
- **Fat reads round only from stepped lobes with the widest one BELOW the middle.** The Boomer's first pass had
  its widest box full height with bulges only on the front: a crate from the front. The belly is lobes that step
  out and back in, narrower at the top where it meets the shirt and at the bottom where it hangs, with the lowest
  lobe drooping forward over the crotch so the side view sags. A too-small shirt has to cover about a third of the
  torso to read as ridden up; less reads as a thin yoke. On a fat body the arm pivot moves out to the sleeve's
  centre, or a big outward swing lifts the sleeve's outer corner into a shoulder pad.
- **Put a side detail where the arm isn't.** The Boomer's burst ribs were first under its right arm and invisible
  from every view.
- **A strap that holds something splits in two**: a thin band round the body plus a thicker wrap only across the
  held thing (the Exploder's dynamite). One thick strap round the chest makes a shelf at the sides and hides
  what it holds.

### Hands: the Brute's

The user rejected every thin detail on the extremities (claw boxes, bone-coloured nail tips, rows of toe boxes,
little knuckle blocks) and asked for the Brute's hands (`refs/brute_hand_GOOD.png`, `refs/brute_hand_views.png`):

- **A fist block about as wide as the forearm, with chunky finger blocks hanging below it**, each about half the
  fist wide, turned at different angles so they curl toward the palm and splay, and ONE chunky thumb on the inner
  side tipped outward. Everything in the arm's own skin, the blood thickening toward the tips, the tip row a tone
  darker. No nail colour anywhere.
- **Count the fingers at the scale of the hand**: the Brute has 4, the Charger's 14-wide fist reads best with 3
  (4 at half-fist width overlapped into one lump at distance 115), a thin arm takes 2.
- **The fingers curl INWARD, toward the body, and sit under the inner part of the fist.** The arm's own outward
  tilt carries them out, so a weak curl (the Spitter's first 14 and 30 degrees), or a finger hanging from the
  fist's outer half, reads as a hand splaying outward, which the user caught. The Spitter's read right at 28 and 42
  degrees inward, with both fingers under the inner part and the thumb pointing forward and slightly toward the body.
- **Fingers lengthen the arm.** Check the lowest point against the ground and the foot tops, and shorten the fist
  or lift the forearm to pay for it.
- **Feet are one plain block**: a boot, or a bare foot painted as skin with the toes as dark splits.

### Legs: two segments

The Spitter's first legs stepped in three times (thigh, knee tier, shin, boot) and the user called it out as not
being how the originals are built (`refs/three_layer_leg_BAD.png`). Normal and Brute have a thigh and then one
lower leg with the foot:

- **Thigh > shin + foot**, one step at the knee, the foot a box poking forward from the shin's bottom.
- **Everything else on the leg is painted**: a trouser cuff over the shin's top rows with a frayed row under it, a
  boot painted on the lower leg with the trousers bloused over it, an ankle strap as a dark row, a knee hole on the
  thigh's bottom rows.
- **A bowed leg is two angles** (the thigh turned out at the hip, the shin back in at the knee), not a knee box
  standing proud. But not on a brute that should read as a threat: on the Charger it pulled the feet in under the
  hips and the user called it goofy (2026-09-27). Its legs went straight, splayed 4 degrees out as one line, the feet
  wider than the hips, and a crouch on bent knees does the rest.
- **A leg that bends is three bones**: the thigh (`LegLeft`, pivot inside its top), the shin (`ShinLeft`, pivot on
  the thigh's axis 0.5 above its bottom, the shin's top tucked into the thigh) and the foot (`FootLeft`, pivot on the
  shin's axis inside the foot's top). End the shin box ABOVE the ankle pivot and texture the shin's top and bottom
  faces: both show once the joints move.

### Bones out

Each original has parts reduced to bare bone, and it is what gives them their zombie read
(`refs/bones_normal.png`, `bones_runner.png`, `bones_brute_legs.png`): the Runner's arms are bone and its lower
torso is a spine with six rib bars; the Normal's left torso, lower left arm and left leg are bone and its right arm
is a stub; the Brute's legs are bone with no flesh at all.

- **Give each zombie 1-3 bone parts, asymmetric**, where they suit it: the Spitter's right forearm and hand and its
  left leg, the Charger's withered forearm, the Shield's left forearm and a spine and ribs in its back wound, the
  Summoner's shins and right arm, the Summon's right forearm and hand.
- **A bone part is thinner than the flesh it replaces** (about 2/3) and ends in a bone hand or foot.
- The ramps and the painting are in Textures.md §3 and §4 (ridge lines; bone over near-black, never over blood).

### Posing with baked rotations

A Blockbench cube has ONE rotation about one pivot, so rotations do not chain. A bent arm or a hunched body with
a head tipped further forward has to be placed by hand:

- **Carry the child's pivot through the parent's frame.** Rotate the joint point (an elbow, a neck) by the
  parent segment's rotation first, use that as the child's pivot, and write the child's boxes relative to it.
  Blockbench applies X, then Y, then Z (Euler ZYX). The Charger's `rotp(point, frame)` and `around(pivot, ...)`,
  the Shield's `rot_x` and the Summoner's `tilt()` all do this. Once it is in place, posing is an edit of angles
  with no refitting of coordinates.
- **Angles only add about the axis Blockbench turns FIRST (X).** A finger curled about X on an arm turned about X
  and Z composes exactly by adding the X angles (`Rz·Rx(a+b) = Rz·Rx(a)·Rx(b)`); a curl about any other axis does
  not. For those, multiply the matrices (`R_parent · R_curl`), decompose back to ZYX Euler, put the pivot where the
  parent carries the joint and shift the box by the same offset: `chained()` in `zombie_spitter.py`, `curled()` in
  `zombie_summon.py`, `rotm()`/`euler()` in `zombie_nest.py`. The Nest checked the order against Blockbench's
  `matrixWorld` to three decimals: `R = Rz·Ry·Rx` about the cube's origin.
- **A leaning torso moves the shoulders.** A 20 degree lean put the Exploder's shoulders about 4 further forward;
  move the arm pivots with them or the arms hang behind the chest.
- **An arm reads as "in front of the body" from the swing of its FOREARM inward** (Z roll on the forearm, as in the
  L4D2 reference), not from swinging the whole arm forward: that read as a separate pillar beside the legs.
- **Measure the real extent after the build** (a `Box3` over the cube meshes), not from the box list: a tilted
  hat raises the top by about half its width times the sine of the tilt. The Summon's `world_bounds()` (every box
  rotated, anything under the floor printed) caught a hand 0.3 under the floor.

### No z-fighting

The first Spitter flickered where its feet shared three faces and the bottom face with the legs, where a sac sat
flush with the belly side, and where the drool sat flush with the gut front.

- **Tuck each segment 0.5 into the next** (a knee's top face ends inside the thigh) instead of butting two
  faces together.
- **Make neighbours differ by at least 0.25 on every side face**, so their sides never share a plane (a thigh
  0.5 to 7.5 in a pelvis that reaches 8, not 7.5).
- **Check it in code before building.** `zombie_spitter.py`'s `check_coplanar()` asserts that no two boxes in the
  same frame (same rotation and pivot) have faces on one plane that overlap. Boxes rotated differently are
  skipped: they cannot share a plane by accident.
- **So give boxes that could touch the SAME frame.** The Charger's big shoulder sits in `ArmRight` but shares the
  torso's lean frame, so the check compares it with the chest, where it could z-fight (it caught the pec against
  the shoulder front). The Summoner's hood, sac and pods share one hunch frame for the same reason. Boxes in a
  frame of their own, like a yawed tier, have to be checked by eye in a close-up.
- **Keep detail boxes off the big boxes' round numbers.** All five contacts the check caught on the Exploder were
  boils and sticks landing on a round number a big box used (a boil edge at a strap's top, 5.75).
- **Re-run it after every resize.** Shrinking or adding a part makes new flush faces (the Summoner: shoulder and
  upper arm, a cuff tatter and the forearm, a side tatter and the shin). Hidden faces count too: the Shield's
  back panels' fronts sat on the yoke's.
- **A row of boards**: overlap neighbours by 0.5 in x and set every other one 0.25 back in z.

### Triangles: every enemy is one skinned mesh, and there are thousands

`EnemiesController` renders each enemy as one skinned MeshPart and finds `model.PrimaryPart.Root` to place it (so
`Root` is the one bone name the game code needs), and enemy counts reach the thousands, so triangles cost on every
one. The originals: Normal 316, Runner 494, Brute 484. **Caps: a humanoid 500, the Summon 180, the Nest 600.** Each
cube is 12 triangles.

- **Cull hidden faces with `Assets/models/Enemies/cull_hidden.py`**, shared by every generator
  (`CULLED = cull_hidden(CUBES, GROUPS)`, `python3 cull_hidden.py` for its self-test). A culled face is emitted
  with a `null` texture: MEASURED, a null-texture face is dropped from both the OBJ and the glTF export (one cube,
  12 -> 10 triangles). `face.enabled = false` is NOT dropped from OBJ. Skip culled faces in the painter and the
  packer, and build with `buildModel2` (Textures.md §6), which nulls any face missing from `faces`.
- **What the tool does, and which model taught it**: tests through world space, so boxes in different frames count
  (the Charger); samples each face on a 0.25 grid against the UNION of boxes, a point on another box's surface
  counting only if that surface faces the opposite way (the Shield: a band spanning five planks, a neck under a
  collar and head together); and guards joints (the Summon).
- **The joint guard is the one that matters for animation.** A face hidden by a box in ANOTHER bone opens a hole
  when a clip moves the joint between them. It stays culled only if it stays covered with every bone on the path
  turned +-30 degrees about X and about Z at its pivot. On the Charger it un-culled both thigh tops inside the
  pelvis and two faces under the big shoulder; the Shield had removed a whole neck hidden by collar and head and
  had to put it back. The Nest uses smaller swings for pods (15) and a mouth (20 about X).
- **A structure that always sits on terrain may cull its ground-contact undersides**; anything that walks keeps
  them, and so does anything that lies tilted, is thrown or is shown in a picture (the rune stones' first cut had
  no bottom face, and the user caught it from below).
- **Then drop what doesn't read at distance 110**: render with and without a detail. The Summoner's tatters,
  membranes and small pods were a third of its triangles and none of them showed (948 -> 472).
- **To change one part without repainting the rest, keep the random stream**: paint culled faces anyway and throw
  them away, paint a replaced part's old version and discard it, and give the new part its own seeded rng. A pixel
  diff against the backup then proves nothing else moved (the Nest's hand).

### A boss (the Bloater, 2026-09-26)

A boss is one instance, not thousands: the Bloater's cap was 1200 triangles (it used 732) and its sac's 200 (136).
What did NOT carry over from the zombies:

- **The atlas is the limit, not boxes or triangles.** The first body needed 76k texels against the 65.5k a 256-texel
  atlas holds (never store above 1024 px, the largest texture Roblox keeps). Three fixes that leave the look alone:
  round a lobe as one full-width box plus a front and a back bulge STRIP tucked 0.5 into it (one deep box paints big
  tops and bottoms that are almost all hidden); let faces seen only from above share one painted rectangle, each
  mapped to a different band of it (a boss is seen from below, so tops are cheap); and a skyline packer instead of the
  shelf packer (it alone took the sac from 256 to 128). `zombie_bloater.py` has all three.
- **A hanging jaw on a head sunk in a fat chest** has to sit out past the chest front, or the open jaw hangs inside the
  chest. The clip test (`crossings()`) caught it.
- **Per-area rates do not scale to boss faces**: pustules at 1/70 plus flecks read as measles at distance 250; the
  Bloater uses 1/100 and flecks 1/320 on its lobes.
- **Joint guards follow the clips**: the crawl swings the arms 90 degrees, so its guard is +-90, the belly doors +-70.
  Per-bone swings are the Nest's `JOINT_SWING`.
- **A bone carries no rotation into Roblox** (`to_fbx.build` ignores group rotation), so a mount point's direction
  (the `SacAnchor`s) is printed by the build as data for the game, and the bones stay unrotated.
- **Small limbs are what say "bloated"**: a height target that forces long legs under a huge torso makes stilts. The
  intent (small withered legs) wins over the number.
- **Compare against the family without touching their tabs**: `Codecs.project.merge` another `.bbmodel` into a scratch
  tab, shifted onto the same ground, and render in a separate call.

### Building and checking

- **Boxes (`Cube`s), not meshes, in the `free` format.** The originals are meshes (triangulated boxes, imported
  from elsewhere); cubes give the same look, per-face UVs that are easy to write, and a file the user can repaint.
- **Build from a script** (Textures.md §6), never by clicking: the build is then one call again after any change.
- **Check from four sides and close up** (front, three-quarter, side, back, then the face and the legs at
  ~50 units) before showing it. The side view is where limbs sticking out behind the body show up, and the close
  view is where z-fighting shows.
- **Make clipping a test, not a look.** The Summoner's head and jaw passed through its hood and cowl for four
  rounds of renders before the user's screenshot caught it (`refs/summoner_maw_clipping.png`). `crossings()` in
  `zombie_summoner.py` samples the moving parts' faces on a grid and asserts no point is inside the boxes round
  them; an offset search then finds the smallest move that clears it. A hood that frames a head is built hollow
  (top, two sides, back, 0.25 of air round the head), never as one box the head pokes out of.
- **Keep the previous version when reworking.** Round 2 backed every model up to `Assets/models/Enemies/v1/` first,
  since the user may prefer the old one.
- **Size by role, and size it in the generator.** A heavy special stands over the Brute's 7.2 studs; the Charger
  went from 6.8 to 8.8 when the user asked for "bigger, like the brute or even more". `zombie_charger.py`'s `SIZE`
  multiplies every box and pivot AFTER the model is drawn at its first size and BEFORE painting, so the texture is
  painted for the final size at one texel per unit. Scaling the finished model instead would have stretched every
  texel 1.3 times against its neighbours. A painter that places features at fixed texels (the head's eyes and nose)
  maps them through the face's size (`X(x) = x * w / 9`) or the face ends up off centre on a bigger head. The paint's
  random blotches re-roll: say so when offering the choice.
- **Screenshot sparingly.** Each Blockbench `set_camera_angle` returns a full-viewport image, and one session's
  screenshots came to a third of its context. Check geometry with numbers (bounds, pivots, `risky_eval` reads) and
  look with one small render; contact sheets of clips come from Blender headless renders of a COPY.

## 8. An enemy rig into the place (the Spitter, 2026-09-26)

The enemy half of §1, done once end to end. The rig and its six clips were uploaded, imported, set up and read back
in one pass with nothing redone; do it in this order.

1. **Export from the `.blend`**, not the `.bbmodel`, when the clips were authored in Blender:
   `blender -b <copy of Zombie<Name>.blend> --python tools/bbanim/blend_to_fbx.py -- <outdir>` writes the rig FBX and
   one FBX per action with `to_fbx.export`'s own settings. Run it on a COPY; it never saves, but the user's file is
   theirs. Verify the FBXs before uploading (Animations.md §7, "An enemy animated in Blender").
2. **Upload**: the rig as `asset_type = "Model"`, each clip as `"Animation"`. The FBX's embedded texture comes through
   on the rig's MeshPart (`TextureID` set); no separate image upload.
3. **Insert the rig into `ServerStorage`** (never straight into `Models`). It arrives as a Model wrapping a Model with
   the skinned MeshPart (every bone under it) and an `InitialPoses` folder of CFrameValues, which nothing uses.
4. **Build the shipped shape by hand** (`ReplicatedStorage.Models.Enemies.<Name>`, copied off the Runner):
   - a FRESH `Model` (the imported one's `WorldPivot` cannot be cleared through the bridge), the MeshPart moved into
     it by setting `Parent`, and an `AnimationController` with an `Animator` under it;
   - the part's CFrame set to CANCEL Root's x and z (Animations.md §7): the Spitter's Root bone sits at
     `(-0.0487, -2.9375, -0.7404)` in the part, so the part goes at `(0.0487, 0, 0.7404)`. Y stays 0: the part is the
     mesh's box centre and Root sits at its bottom, as on the Runner;
   - `PivotOffset` identity, `Anchored`, `CanCollide = false`, `CanTouch = false`, and the Model's `PrimaryPart`.
   Then delete the import from `ServerStorage`.
5. **The clips** are `Animation`s named as the data file expects under `ReplicatedStorage.Animations.Enemies.<Name>`,
   made in one `mass_create` with each `AnimationId` set.
6. **Check it in a playtest**: `GetExtentsSize()` must come back with Y as the height (the Spitter 5.875, X and Z not
   swapped), `TextureID` set, and one clip's KeyframeSequence read back (Animations.md §7).
7. **Ask the user to save the place.** All of it lives in the place, not in Rojo.

| Asset | Id |
|---|---|
| ZombieSpitter rig (Model) | 111887232137263 |
| Idle / Walk | 120299233437906 / 95601184398608 (the throat gurgling, 2026-09-27; were 138963405293785 / 139714374698376) |
| Spit / SpitCharged | 126728569442288 / 102096083760261 (stepping into the throw, arms back, 2026-09-27; the lobs before it 105604328419813 / 113347055817186, the first 96731062298238 / 96422530607131) |
| ReceiveAttack / Death | 126332342069012 / 91499839307300 |

The ZombieCharger went in the same way (2026-09-27). Its Root sits at `(0.9018, -3.3990, -1.0710)` in the part, so
the part stands at `(-0.9018, 0, 1.0710)`; extents read back 5.09 x 6.80 x 3.59 with Y the height.

| Asset | Id |
|---|---|
| ZombieCharger rig (Model) | 127320031647767 |
| Idle / Walk / Attack | 97664004845920 / 89307688852375 / 123127466711450 |
| ChargeStart / Charge / ChargeHit / ChargeStop | 84303100624474 / 99971450189619 / 110905911138176 / 132472089759728 (solved at 50 studs/s) |
| ReceiveAttack / Death | 81117819543827 / 70980355719659 |

Re-rigged with knees and ankles the same day (`ShinLeft/Right`, `FootLeft/Right`; Animations.md §7), then made 1.3 times
bigger (8.84 studs tall, over the Brute's 7.2) by `zombie_charger.py`'s `SIZE`, which scales every box and pivot BEFORE
painting, so the texture is repainted at one texel per unit instead of stretched. Its Root now sits at
`(1.1724, -4.4186, -1.3924)` in the part, so the part stands at `(-1.1724, 0, 1.3924)`; extents 6.62 x 8.84 x 4.67.
Only the MeshPart is swapped inside the shipped Model each time, and a rig with new bones or a new size needs every
clip re-uploaded. Earlier ids: `refs/charger_anim/asset_ids.pre-knees.txt` (the first) and `asset_ids.knees-6.8.txt`;
earlier files: `ZombieCharger.pre-knees.blend`, `ZombieCharger.pre-scale.blend`, `v2/ZombieCharger.bbmodel`.

### Changing an enemy that is already in the place (re-rig, resize, new clips)

The Charger went through this three times in one day. The order that worked, with nothing redone:

1. **Back up** the `.bbmodel`, the generator and the `.blend` (`v2/`, `save_as_mainfile(copy=True)`), and the id list
   (`asset_ids.<what>.txt`).
2. **Change the model at its source.** A generated body is changed in its generator (`zombie_<name>.py`), re-run and
   loaded with `buildModel2` (Textures.md §6): a hand edit in Blockbench is lost on the next generator run. Check
   first that the file's texture is still exactly what the generator paints; if it is not, the user painted on it.
3. **Rebuild the rig in the user's open Blender** with `to_blend.rebuild_live`, then every clip from its script
   (Animations.md §7). A size change multiplies every stud distance in the clips (`charger_lib.SIZE`).
4. **Export from a copy, `verify_blend_fbx.py` to PASS, upload.** New bones or a new size means EVERY clip is
   re-uploaded; a clip-only change re-uploads just those clips. Asset ids are new every time: write them to
   `refs/<name>_anim/asset_ids.txt` and to the table above as they come.
5. **Swap only the MeshPart** in `ReplicatedStorage.Models.Enemies.<Name>`: insert into `ServerStorage`, read the
   new Root's position, delete the old part, parent the new one in, set the CFrame that cancels Root's x and z,
   `PivotOffset`, `Anchored`, no collide or touch, and the Model's `PrimaryPart`. The Model and its
   AnimationController stay.
6. **Set the `AnimationId`s with the playtest STOPPED**: a write during a playtest goes to the play session and is
   lost when it ends.
7. **Update what the body's size and the clip decide in the data**: `CollisionSize` (scaled with the body), reaches
   measured off the new poses, and the comments that quote them.
8. **Playtest it** (see below), then ask the user to save the place.

### Playtesting an enemy's movement from the server

- **Log a speed profile**: a `RunService.Heartbeat` connection that reads `EnemyWorld:get(e, Components.Position)` and
  the state component each frame and prints speed per tick, set up in the same `run_luau_live` call that spawns the
  body (`EnemiesService.Spawn(<data id>, position)`). That is how the charge (50 studs/s) and the skid (50 to 0 over
  0.5 s) were proved. `Components` and `EnemyWorld` are at `ReplicatedStorage.GlobalShared.ECS.Components` and
  `.Worlds.EnemyWorld`; search by name and a same-named module elsewhere is found instead.
- **Swap `CharacterService.Damage` and `EnemiesService.SignalCharged` for loggers** to see what was hit and when,
  and restore both after.
- **The server cannot drive the lord's movement**: his client owns his character, so a `PivotTo` every Heartbeat is
  fought back and he does not really run. A single `PivotTo` (stepping him off a line) does stick.
- **Test away from the Core.** The lord spawns about 10 studs from the Core's middle (radius 8), so a run aimed at him
  grazes the Core and ends on it: a real hit, and a confusing test.
- **Work out the design numbers in code first** (catch distance, skid length, stride at a speed), then prove them in
  the playtest. For a rule over the map (where a Nest roots), copy the geometry into a script (the tile grid, the
  wedge, the wall's far-corner test) and count what passes at several front lines before writing any Luau: the
  first two root rules looked right in words and sent Nests 80-110 studs deep.
- **`DataCore.Enemies:FindByName` takes the display name** (`"Nest"`, `"Spitter"`), not the enum key
  (`"ZombieNest"`); the wrong one is nil.
- **Keep a probe across calls in `_G`** (`_G.NestTest = { entities }`, `_G.Conn = Heartbeat:Connect(...)`): each
  `run_luau_live` call is its own chunk, so spawn in one call, sample in the next few (the time between calls is the
  wait), and disconnect in the last.
- **A structure's placement, facing and brood are all server state**: `Components.RootAt`, `Position`, `Yaw`,
  `AttackCount` (it went up = it brooded) and `HoldYaw` on a newborn read the whole behaviour without a client probe.

The ZombieShield went in the same way (2026-09-28). Its Root sits at `(0, -3.2262, -0.6390)` in the part, so the part
stands at `(0, 0, 0.6390)`; extents 3.81 x 6.45 x 3.16 with Y the height. Ids are also in
`refs/shield_anim/asset_ids.txt`.

| Asset | Id |
|---|---|
| ZombieShield rig (Model) | 110863129262606 |
| Idle / Walk / Attack | 87073689667747 / 102892442203751 / 91138495094856 |
| Block | 118984851612083 |
| ParriedStart / Parried / ParriedStop | 125405871524607 / 82286669510960 / 87548686509823 |
| ReceiveAttack / Death | 106886964176712 / 122860235265148 |

## 9. A structure into the place (the Nest, 2026-09-27)

The Nest went in by §8's steps, with a re-rig first and a texture minted on the way. What was new:

- **Re-rig through the generator, then write it into the `.bbmodel` in place.** The Nest's mouth was one bone and its
  arm part of Body, so neither could animate (Animations.md §12). `zombie_nest.py` grew `Jaw` (under `Mouth`, hinged
  at the back of the lower lip, `[-1, -8, 10.5]`: the lower lip, lower teeth and tongue) and `Arm` (under `Body`,
  turning where the forearm leaves the mound, `[11, -6, -8.5]`), each with a `JOINT_SWING` entry so the joint guard
  keeps their culled faces covered. `Assets/blockbench/refs/nest_anim/apply_bbmodel.py <nest.json> <bbmodel>` then
  writes the groups, the outliner, every face and the texture into the existing file, keeping every uuid. Prove the
  paint did not move before trusting it: the texture and every face's UVs came back byte-identical, still 610
  triangles. The old files are in `Assets/blockbench/v2/`.
- **Anything buried in the flesh rides Body, not Root.** A beam jutting from the mound stayed on Root with the ground
  debris, and a Body that sinks (the death) left it hanging in the air. It moved onto Body; the planks and stones
  lying on the ground stayed on Root.
- **An open Blockbench tab writes the old rig back on its next save.** Loading the new file with
  `Codecs.project.load` opened it in a SECOND tab named the same; the stale tab (saved) was closed so it could not.
- **Root x/z cancelled**: the Nest's Root sits at `(0.0373, -1.6702, 0.1139)` in the part, so the part stands at
  `(-0.0373, 0, -0.1139)`. Extents read back 4.94 x 3.49 x 4.82, Y the height. `PivotOffset` identity.
- **A particle texture minted as an Image without the command bar**: wrap the PNG in a one-quad FBX
  (`Assets/effects/texture_to_fbx.py`), upload it as a Model, insert it, and its MeshPart's `TextureID` is the Image
  id (VFX.md §7). Read it with `run_luau_live`; the edit-mode property read leaves it out. Delete the import after.
- **The data points at place-only instances** (`Models.Enemies.ZombieNest`, `Animations.Enemies.ZombieNest`), and the
  Lobby place loads every enemy data file through DataCore too. The Spitter's data does the same; check the Lobby
  place has them before relying on it. The Crawl (2026-09-28) is one more of those: `Animations.Enemies.ZombieNest.Crawl`
  exists only once the place is saved, and a Lobby place without it fails the data file's load.
- **A structure that moves** is data, not a new kind: `BaseMovementSpeed` and a `WalkAnimation` on a `Structure`, and
  the server crawls it (Animations.md §12). Nothing about the rig changes, but whatever hangs straight off `Root` (the
  Nest's planks and stones) is dragged along under it, since Root is what the renderer moves.

| Asset | Id |
|---|---|
| ZombieNest rig (Model) | 124171012626688 |
| Idle / Spawn | 131427689768113 / 127023257299449 |
| Crawl | 126969297120103 (2026-09-28, its drag out of the murk; the rig is unchanged) |
| ReceiveAttack / Death | 78539037066096 / 92368239221688 |
| Blood blob texture (Image, via `BloodBlobTexture` Model 124589049910241) | 127237296613837 |

## 10. A boss into the place (the Bloater, 2026-09-28)

By §8's steps, with its twelve clips from Animations.md §13, and the sac as its own model beside it
(`Models.Enemies.ZombieBloaterSac`, from `to_fbx.py` on its `.bbmodel`: `Root` > `Sac`, no clips). What was new:

- **The importer drops a bone that carries no skin weights.** The four `SacAnchor` bones have no geometry, and the
  upload came back with 12 bones of 16. They only ride the Torso, so they were added in the place as plain `Bone`s under
  `Root.Torso`, each turned so its UpVector lies along its stalk: mount a sac at `anchor.TransformedWorldCFrame` and it
  sits on the stalk's torn end, pointing out. SacAnchor4 takes its sac at 0.75 scale (the game's number, not stored on
  the bone). Under the Torso bone Roblox's axes are the `.bbmodel`'s over 8 (checked on BellyLeft), so the positions
  are `(anchor - Torso origin) / 8` and the directions the generator printed, as they are.
- **Root x/z cancelled**: the body's Root sits at `(-0.0546, -6.0938, 0.1232)` in the part, so the part stands at
  `(0.0546, 0, -0.1232)`; extents 9.46 x 12.19 x 7.25, Y the height. The sac's Root (the bottom of its knot) sits at
  `(-0.1563, -2.1563, 0.0312)`, the part at `(0.1563, 0, -0.0312)`; extents 4.06 x 4.31 x 3.38.
- **Read back**: the first Vomit's key at 1.308 s had Torso 12.0, Head 27.8 and Jaw 28.4 degrees, the source's f78
  through the X flip, and the Torso 0.12 down.
- **A clip re-uploaded on an unchanged rig is only its own upload** and its `AnimationId`, set with the playtest stopped.

| Asset | Id |
|---|---|
| ZombieBloater rig (Model) | 120786250521159 |
| ZombieBloaterSac (Model) | 82710752272249 |
| Idle / Drift | 72694071421094 / 127402697651919 |
| Vomit / Burst / SacPop / ReceiveAttack | 124344131172458 / 72619307815974 / 76185011222560 / 93391935073217 (Vomit throws a ball, 2026-09-28; was 130977697191175) |
| Crash | 74184647854926 |
| CrawlIdle / Crawl / CrawlVomit | 111944775355526 / 138442086208712 / 116506504891225 (rears up and throws, 2026-09-28; was 99078184543465) |
| CrawlReceiveAttack / Death | 126826293263181 / 116305982172976 |

## 11. The stronghold: native Parts from a kit (2026-10-08)

The ruined and restored stronghold (`Models.Buildables.RuinedStronghold` / `RestoredStronghold`) are generated:
plain Parts plus the old buildables' own mesh props, with no upload. The two `.rbxmx` are not in
`game.project.json` and must not be: after a run, insert them into `Models.Buildables` by hand. Rojo's plugin
cannot write `MeshPart.MeshId` (no plugin can), so a model synced through it arrives with every lifted mesh
prop (the crane, the thatch, the crates) as a blank box. Tried on 2026-10-09, and taking the mapping out again
deleted the whole `Models` folder from Studio (recovered with an undo). This section is the order to work
in and every rule the first remake paid for. It took six rounds with the user; each rule below is one of them.

### Run it

```
python3 tools/stronghold_remake.py && lune run tools/stronghold_remake.luau      # then insert the two .rbxmx in Studio
blender -b --python tools/stronghold_remake_render.py -- <outdir> <shots.json>   # any view, 2 s, no Studio
```

| File | What it is |
|---|---|
| `tools/stronghold_kit.py` | the vocabulary: `masonry`, `boards`, `planks`, `flagfloor`, `roof`, `merlons`, `leaf`, `banner`, `brazier`, `ivy`, `rubble`, `fallen`, `old`, and the checks `zfight`, `loose` |
| `tools/stronghold_remake.py` | the sites, the layout, the checks' report, and the writer of `stronghold.json`, `StrongholdLayout.luau`, `StrongholdDoorways.luau` |
| `tools/stronghold_remake.luau` | JSON to the two `.rbxmx` under `src/FeedTheCore/Assets/` |
| `tools/stronghold_remake_render.py` | Blender Workbench render of either stage; a shot can `hide` group prefixes and `cut` past a plane for a cutaway |
| `Assets/models/Buildables/Stronghold/old_buildables.json` | every part of the four old buildables (the prop source) |
| `Assets/models/Buildables/Stronghold/previous/` | the templates and data modules from before the remake |

The older `tools/stronghold_restored*`, `stronghold_parts_*`, `stronghold_doorways.py`, `stronghold_layout.py`,
`stronghold_templates.luau` and `stronghold_fbx.py` are the superseded pipeline. Running `stronghold_layout.py` or
`stronghold_doorways.py` would overwrite the generated data modules with the old castle's.

### The order that works

1. **Study before drawing, with numbers.** "Study the old models" meant: dump every part (pose, size, colour,
   material, shape, `MeshId`, `MeshSize`) and photograph them. The first pass copied their palette and proportions
   and rebuilt their props out of boxes, and the user rejected the props on sight. Their tools ARE the reference:
   lift them (`old()`), do not imitate them.
2. **Author each site once, with stages.** `keep` stands in the ruin and is carried into the restored building as
   its `Retained` group, `new` is what the Core raises, `ruin` is what the restoration clears (`FallenTimber`,
   `LooseRubble`, `Overgrowth_Ivy`: the names in `RestorationCore`'s `Clears` and `Ancient`). A ruined wall is the
   restored wall under a `profile` of how high it still stands, so the two never disagree about a stone.
3. **Run the generator and read its six lines.** All of them must be zero before anything is shown:
   `z-fighting` (ruined, restored), `floating`, `near misses`, and `parts standing in` the ways in. They are the
   user's first three rounds of feedback turned into tests.
4. **Render the spots a test cannot judge** (below), then export, then look in the engine.
5. **Put old and new side by side when asked to compare**: a Lune script that stands the four castles in one
   `.rbxmx`, mapped under Workspace in `game.project.json` at X = 1200. Take the mapping out afterwards; Rojo
   removes the instance with it.

### Rules, each one a round of feedback

- **Lift the old props, never rebuild them.** `old(F, model, names, at, yaw, scale)` stands the real parts of an
  old buildable, meshes included; `within(model, lo, hi)` picks a prop by the box it stands in. The workshop's thatch
  is the Woodcutter's own mesh a quarter bigger; its bench, hammers, picks, crane, crates, stone pile and boulders are
  the Stonecutter's; its stump, axe, sawhorse, firewood and plank stack the Woodcutter's. The exporter makes a
  `MeshPart` with `InitialSize` = the mesh's own size. A mesh cannot be mirrored, so props go on sites that are not.
- **Touching is built in, never left to two numbers agreeing.** Masonry blocks stand proud by a random 0.01 to 0.1,
  so anything fixed to a wall is LET INTO it past the wall's own plane: joists, braces, a banner's brackets, leaf
  masses, treads, a curtain wall's end inside a tower. A part that stops AT the nominal face has air behind it
  somewhere. Fixing z-fights by pulling parts back a hair made exactly these gaps.
- **A curtain wall runs into the tower's wall, not to its corner piers.** The piers stand 0.5 proud; a wall that
  stops at them leaves a slot between the piers.
- **Two things that are one thing are authored as one**: a wall walk's planks and rails run each wall's whole
  length, so two stretches of wall make one walk.
- **No two faces on one plane.** Rails tuck 0.02 into their posts, roof rows end 0.013 apart, a lintel drops 0.1
  below the opening it caps, a sill stands proud of the one under the window, stacked leaf masses have backs 0.007
  apart. Where two walls of one height meet, give them different course heights.
- **Ways in stay empty, and the neighbour is the usual culprit.** `CLEAR` zones are tested in the WORLD against
  every site: a wall's rubble on a tower's doorstep, the Core's cradle stones in the keep door, a wall's plinth across
  a tower door (the tower doors moved for it and are 3.55 wide), yard props in front of the workshop.
- **Yard props go round the side.** The workshop's bay and the floor behind it are a `CLEAR` zone; its yard is on
  the courtyard side toward the wall.
- **A stair needs somewhere to stand at its foot and a rail at its head.** Six flights round the tower walls
  between corner landings, starting in the corner opposite the door with the whole corner as its foot; a handrail up
  the open side; a hatch railed on every edge but the one stepped through. A script walks every tread (rise 0.85 or
  less, 5.3 studs of headroom against the collision). The first stair began 0.6 studs from a wall, facing it, and
  ended at a hole.
- **Every room has a floor** (`flagfloor`, with collision): towers, keep, workshop, the gate's passage.
- **A roof sits on its frame by construction.** `roof(half, eave_y)` passes its underside through `eave_y` at
  `x = half`: put the ends of the ties there. Post, plate, tie, rafter, boards, and a purlin along each eave. A post
  under a SLOPING roof is cut to the slope's height at the post, not to its low edge.
- **A door is a hinged group, authored open and off the wall.** `leaf()` builds it in a frame at its hinge; the
  group Model carries `Hinge`, `HingeAxis` and the `SwingDegrees` that close it. The gate's leaves stand 8 degrees
  off the passage wall and the keep's 25 off the front: flat against the stone read as unnatural, and so did leaves
  lining the jambs. The drawbridge's `Deck` is one group that lifts 90 degrees into the gate's mouth (9 wide in a
  10.05 gap); the `Portcullis` carries a `Slide` and runs in a slot cut through the arch. Each sweep is a `CLEAR`
  zone. Nothing in the game moves them yet; the chains are their own group, drawn for the deck down.
- **A banner is bracket, pole, cloth**: two iron brackets let into the wall, the pole across them, the cloth's top
  edge on the pole's underside.
- **Vegetation is the approved ruin's, measured**: one vine a face in broad masses (2.8 x 3 studs, 2.1 as it
  thins), stepping 1.92 up the wall, each ROLLED about the wall's normal by the old cycle (-24, -24, -9, -24, 12,
  21, -24, -9), a darker moss then two lighter ivy, a lobe turned 32 degrees on every third. Upright masses read as
  a ladder ("too still"); many small ones read as messy. A mass with no standing stone behind its middle is dropped.
  No moss on wall tops and no grass or tufts: the map's own decorations grow those.
- **Collision is read back off the blocks**, merged into boxes, so a breach or a door is exactly as wide as drawn,
  and the same run writes the layout module the flowfield and the reservations read.
- **A handed thing is authored once and mirrored** (`Site.mirror`): a tower with its door in +x, a wall with the
  courtyard on +z. Zones recorded before the mirror are flipped with it.
- **Raise order is `PHASE`, then height**; masonry groups are named by absolute height, so walls on different
  footings land a course together.

### What the checks cannot judge (look at these)

- A TURNED part that should reach something: a post under a sloping roof, a brace into a wall. `loose` only pairs
  square boxes for near misses.
- The lifted mesh props: placed as they stood in their own models, never tested for z-fighting or contact.
- Whether a mesh fits what was built round it (the workshop's gable boards under the thatch are pitched off the
  mesh's bounding box).
- How it looks. The Blender render draws meshes as their boxes.

### Seeing it

- `capture_screenshot` needs the Studio window drawn on a monitor, and the edit camera takes a position but not an
  orientation. In a playtest, a LocalScript probe bound past `RenderPriority.Last` reads `ProbeEye` / `ProbeAt`
  attributes off Workspace, sets a Scriptable camera and forces daylight; drive it from `run_luau_live` and grab the
  window with `maim -i $(xdotool search --name " - Roblox Studio" | head -1)`. A hidden window grabs as black: fall
  back to the Blender render and say so.
- The probe must not destroy anything (deleting the weather's parts made WeatherController throw every frame), and
  the playtest must be restarted after an export: it runs the models it started with.
- A big `run_luau_live` result (over about 60 KB) is saved to a file instead of the reply, which is how the old
  buildables were dumped in one call.
- A real restoration from the server: `FortressStores.Add`, `BuildService.SetRestorationAllowed(true)`, pivot the
  character to the site's offer, `BuildService.RestoreSite(player, id)`, then read `get_playtest_output` for errors.

### State

Sixteen sites have a restored stage; two are sold (`RestorationCore.Sites`: the Workshop and the left front tower).
No avatar has walked the stairs or the doors, and only the Workshop's raise has been run.

## 12. The rune stones: one MeshPart, glowing through an emissive mask (2026-10-19)

The loose runes (`Models.Drops.Runes.<Name>`, one Model per rune named by `ERunesNames`, cloned by
`RuneGlyphs.Stone`). Source in `Assets/models/Drops/Runes/`: `runes.py` paints the eleven `.bbmodel`s (Textures.md's
face painting on a cool slate; the marks are 9 x 11 hand-drawn pixel glyphs of `RuneGlyphs`' strokes, standing half a
unit out of both faces, the back one mirrored), `bake.py` turns each into one `.obj`, its texture and a glow mask,
`make_appearances.py` writes their SurfaceAppearances.

- **Boxes and a texture, not the props' per-texel bake.** Dozens lie after a boss wave, and the per-texel bake costs
  7-11x the triangles (props-from-gltf.md). The stone is 32 triangles and the mark 100-320. The texture is stored 8
  pixels a texel with its gutters filled from their neighbours, and `ResampleMode = Pixelated` keeps it crisp.
- **One MeshPart a rune, the glow from an EMISSIVE MASK.** The first upload had the strokes as a second part in Neon;
  a Neon MeshPart with a texture looked the same as a plain one, and a second part is a second joint on every rune.
  The part's `SurfaceAppearance` (named `Texture`, as on the enemies) carries the texture as `ColorMap` and a
  greyscale mask as `EmissiveMaskContent` (red channel read: a stroke's face 255, its sides 150, the stone 0) at
  `EmissiveStrength` 2.
- **Neither map can be written the usual ways.** Every SurfaceAppearance map needs the Plugin capability (a script,
  even `run_luau_live`, is refused), and Tripwire's property writer cannot write a `Content`, which
  `EmissiveMaskContent` is. So both go in an `.rbxmx` (`make_appearances.py`: `ColorMap` as `<url>`,
  `EmissiveMaskContent` as `<uri>`), uploaded as a Model, inserted and moved under each part. The images are minted
  by uploads: the mesh's FBX embeds its texture (read the `TextureID` back in a playtest), and each mask is a one-quad
  FBX (`Assets/effects/texture_to_fbx.py`).
- **The mesh's box is centred on the stone** (the marks stand out of both faces alike), so the part's centre is the
  model's pivot, as the old Part slate's was. Each part stands at yaw 180 (§3); either way each face reads right,
  since the back's mark is the front's mirror.

| Rune | Mesh (Model) | Texture (Image) | Glow mask (Image) |
|---|---|---|---|
| Tesla | 136191220745018 | 113411436392687 | 128126923521081 |
| Burn | 111401935101424 | 95998496184493 | 82895685988079 |
| Frost | 140085966582162 | 114706718216436 | 83478236609115 |
| Curse | 125966760810432 | 130391463882406 | 75822162564105 |
| Venom | 126597180105885 | 133333081443403 | 76928664788653 |
| Ricochet | 81421281926691 | 81058272021081 | 85074836086630 |
| Rupture | 112535540151716 | 88160798577381 | 131784867555331 |
| Shatter | 106173546944311 | 139106047035109 | 122095255137839 |
| Fork | 111605749779625 | 114196906758831 | 70646187416708 |
| Reach | 111927389537651 | 105437461429733 | 129124146171000 |
| Catalyst | 103998086580719 | 133328186061383 | 95628353407996 |

The SurfaceAppearances' model is 113600726832635. The two-part uploads before it (a Stone and a Mark each for six
runes, and Rupture's Stone) are unused.

What the user asked for along the way, each a rule for the next small prop:

- **A prop in a family's style matches its PAINTING, not its scale.** The runes were painted at Textures.md's one
  texel a unit, at 0.073 studs a unit against the zombies' ~0.12, so they read a little finer; nobody minded.
- **Symmetrical left to right and front to back.** The first stone set its step and crown off centre "so it reads as
  a stone someone cut", and was sent back. Only what has to be asymmetric (a rune's letter) is.
- **Show the plan before uploading every piece.** The first two uploads were split meshes, and the user stopped the
  rest to ask why. Upload one, look, then the batch.

Reading a `.bbmodel` (Blockbench 5): a group's name is in the file's `groups` list, and the `outliner` tree holds only
uuids (`bake.py` maps one to the other). Two things that cost a step in Studio: an inserted asset arrives as a Model
wrapping a Model wrapping the MeshPart (`Import<Name>.Rune<Name>.<Name>`), and in one `mass_set_property` batch a
`Name` change moves the path, so reparent first and rename at the new path in a second batch. Freshly uploaded
images warn "Asset content representation is being generated" in the first playtest after; it passes on its own.

## 13. The lobby pads (2026-10-23)

A pad is one server Part under `Workspace.Lobby.Pads` (12 x 0.5 x 12, its bottom sunk 0.1 into the baseplate); the
rim and the glow round it are built on each client by `LobbyController/PadArt` from the pad's own CFrame and size, so
they follow the Part wherever it is moved and each player sees his own colour.

The first pads were placed by hand with neon rim strips flush with the pad's sides and the baseplate, and they
z-fought on sight: §7 and §11's rule ("no two faces on one plane") holds for every Part in either place, not only for
enemy boxes and the stronghold. PadArt keeps it by construction (bars sunk 0.1 into the pad and standing 0.06 / 0.04
past its sides, the X bars inside the Z bars' ends and height, the glow on undrawn Parts above the rim), and a change
to its numbers is checked the way the generators check theirs, every pair of boxes and every face:
`python3 tools/lobby/pad_zfight.py` (keep its numbers in step with `PadArt.luau`; it must print 0). Anything else
added round a pad (a sign, a floor trim) goes into the same check.

## 14. A gun out of native Parts: the Starter Pistol (2026-11-20)

The brick-toy guns (a slide with a diamond lattice, a grip with rows of stud bumps) are plain Parts written by a
generator, no mesh and no upload: `Assets/models/GunSources/StarterPistol/make_pistol.py` writes
`Assets/models/Guns/Common/1.rbxmx`, and Rojo serves `Assets/models/Guns` into
`ReplicatedStorage.Models.Guns`.

- **Everything under `Assets/models/Guns` lands in the place**, a generator, its `__pycache__` and its renders
  included. A gun's source lives in `Assets/models/GunSources/<Gun>/` and only the model file goes in `Guns`.
- **A pattern is geometry, not a material.** `DiamondPlate` tiles in world studs: a 1.9-stud pistol gets four
  diamonds, and the first-person copy (scaled to 0.4) fewer. The lattice is thin blocks at 45 degrees and the grip's
  studs are small blocks, each ONE part through the gun standing out of both sides, so both scale with the model.
- **Author it at the data's `Length`**, muzzle toward +X, so `buildGunTool`'s `ScaleTo` changes nothing.
  `GunsCore.FindAxes` reads the barrel off the biggest part: that stays the slide's body, long along the barrel.
- **What moves is a child Model `Slide`** whose PrimaryPart is its body. `buildGunTool` hangs the slide's parts on
  the body and the body on the Handle with one Weld named `Slide`; `Client/Utils/gunSlide` runs it back on a shot
  (the held gun through the Weld's C0, the first-person copy through its own offsets). The barrel is not in the
  slide, so it shows as the slide runs back over it.
- **An Attachment `Muzzle` on the barrel's front face** says where the shot leaves. Without one `buildGunTool` takes
  the middle of the gun's front, which on a pistol with a long grip is under the barrel. The kit's casing `Port`
  (`gunFx` `LOOKS`) is measured back from it to the model's port.
- **Anything proud of a face is proud by a different amount than its neighbour**: lattice 0.012 units, the port
  0.03, the round in it 0.04, so no two faces share a plane where they cross.
- Looked at with `ror render` at three cameras (side, three-quarter, over the sights as in first person), at rest
  and with the slide back: `preview/`.

## 15. Lifting a place's own meshes into Studio (the range's front, 2026-11-23)

The shooting range's front is the SHOP's portico, banners, lamps and planters, with a label in the same letter
meshes (Maps.md sections 8 and 9). None of it could be built in place: no plugin writes `MeshPart.MeshId`, so
Tripwire's create calls and Rojo make blank boxes, and Tripwire has no clone. The route that works, start to finish
without the user:

```
python3 tools/uimatt/strip.py <LobbyOld.rbxl> /tmp/old.rbxl Tags          # lune cannot read the Tags chunk
lune run tools/lobby/range_front.luau /tmp/old.rbxl Assets/models/Lobby/Range/RangeFront.rbxm
# Tripwire: upload_asset (Model) -> insert_model (assetId, parentPath, unpack = true)
```

- **Lift, do not rebuild** (section 11's rule): `range_front.luau` deserializes the old place, takes the real
  instances (reparenting them keeps their Beams' attachment refs, textures and SurfaceAppearances), and places each
  with ONE transform from where the kit stands in its building to where it stands in the new one
  (`CFrame.new(target) * turn * CFrame.new(-source)`), so every relation inside the kit survives.
- **Write a turn as its twelve components**, not `CFrame.Angles` or `lookAt`: lune's are not trusted (CLAUDE.md).
  A quarter turn that faces a -Z front toward -X is `0, 0, 1, 0, 1, 0, -1, 0, 0`. Check it in a render: a sign that
  reads backwards is the first thing seen.
- **A new MeshPart made in lune** needs `MeshId`, `InitialSize` (the mesh file's own bounding size) and `Size`;
  it renders and inserts fine without collision data when `CanCollide` is off.
- **Finding a mesh the place does not have** (four letters of an alphabet pack): bulk-imported meshes get rising
  ids with gaps. Download the ids between two known ones through Tripwire `download_asset` (about 0.5 s each) and
  keep the files whose mesh has the pack's bounding size; draw the candidates' triangles flat to tell them apart.
  A `version 2.00` mesh is a 12-byte header (vertex size, face size, counts), then vertices starting with three
  float positions, then faces of three uint32.
- **Rendering a lifted model offline**: write `.rbxmx` and rewrite every `rbxassetid://N` in it to
  `file://<abs>/research/LobbyAssets/N`, then `ror render model.rbxmx --map place.rbxl` draws it in the lobby.
- **The upload is a private Model in the group** and cannot be archived (`archive_asset` answers "not an
  archivable asset type"): build and check the model offline first, upload once. An inserted model lands at its
  authored world position, so author it in place.
- A shell mesh (the SHOP's body) cannot be given a door: build the room behind a lifted front from Parts.
