# VFX

> **Carried over from Ballarc (Last Wave) on 2026-11-20.** The method, the engine facts and the measured lessons
> apply here; the old game's look does not. Kill All The Monsters is not pixel art and not anime: maps are stud-style
> (LEGO-like bricks at real scale), UI is sleek and modern (`UIMatt.md` is the designer's spec). Sections named after
> a Last Wave weapon, boss or screen are worked examples. A path that does not exist in this repo (`Assets/...`,
> `tools/vfx/...`, a `src/Survivors/...` module) is in `../Ballarc`; `../Anime Zombie Survival` holds the enemy rig,
> map and burst pipelines this repo's `tools/` came from.

What building effects in this project has taught, in the order it will cost you. It sits beside
[Animations.md](Animations.md), [Models.md](Models.md), [Textures.md](Textures.md) and [UI.md](UI.md). The first
entry is the Spitter's spit (`src/FeedTheCore/Client/Utils/SpitVfx.luau`), which is also the worked example for
everything below.

**Do not use the stock sprites in `ReplicatedStorage.Effects.VFX`** (`SlimeSmall`, `SlimeMedium`, `SlimeBig`, and the
other Visuality sprites the uploader made): they were upscaled SOFT and read as smeared, pixelated blobs in play, and
the user has rejected them on sight. For goo and drops use the crisp blood blob through `Client/Utils/BlobBurst`,
tinted by the emitter (section 7). For anything else, make a crisp sprite the same way (section 7, "Use only CRISP
textures") rather than reaching for what is in the folder. The weather's own sprites (`Droplet`, the rain splashes,
the ripple, the puddles) were scaled nearest-neighbour and are fine. Still on the old ones, to replace: the spit's
landing burst (`SlimeMedium`, `SlimeBig` charged) and the burst where a parried spit ends (`SlimeMedium`).

---

## 1. Judging an effect: put the variants side by side

**An effect is chosen by eye, and the eye needs them next to each other.** Describing four spit styles in chat
got nowhere; standing them in a row in the live game settled it in one look. So an effect with more than one
candidate gets a BENCH, the way a UI screen gets a story:

- A Studio-only console command (`conch.register`, gated on `RunService:IsStudio() or EPlaceIds.IsTest`) that
  stands every variant in a row in front of the camera, with its name on a `BillboardGui` over it, looping on
  the real rig with the real clips and numbers. `spitbench` in `Client/Controllers/Debug/DebugSpitController`
  is the pattern: it first stood four styles in a row (ordinary in front, charged behind), and now that one is
  chosen it stands the spit and the charged spit side by side.
- While there is a choice, a second command picks which variant the game itself uses (it was `spitstyle <name>`),
  so the choice can be seen in a real fight straight after. **Once the user picks, delete the losers and the
  switch**: a styles table nobody will change again is code to read and a cost to carry. (Kill All The Monsters,
  2026-11-20: the losers were asked back onto the bench the same day. There a pick deletes the switch and takes the
  losers out of the game's module, and they stay on the bench until the user says to drop them: section 30.)
- Expose the bench's put-up as a function on the controller too (`DebugSpitController.PutUp`), so a playtest
  probe can run it without the console.
- **Variants differ in what they DRAW, not only in how it moves.** Four motions of one plain sprite were rejected
  outright ("I want the actual vfx variants to look different, not only the animations", the Shovel's footprint,
  section 21). Draw a sprite a candidate, each with the motion that suits it. And nothing the user is shown may sit
  still and vanish in one frame.

- **A change to motion is benched Before and After.** When an existing piece's motion is reworked (Animations.md 15),
  the bench stands the old motion beside the new, labelled `<piece> Before` / `<piece> After`: the Revolver's in one
  row, the Shovel's as a Before row in front of an After row (its lines are 30 studs long, so ten cells across do not
  fit the screen). The old pose is copied into the bench file only, never kept in the shipped module, and deleted once
  the user picks. A bench that stood a static model (the Revolver's) drives it through the same motion functions as
  the game; the Revolver bench's `Orbit` row plays the game's full cycle (orbit, burst, reload, back to the ring).

**Keep what the user picks, and write down why the others lost** (section 3). A style that lost is still worth
its line in the notes, so nobody builds it again.

## 2. Checking an effect you cannot see

`capture_screenshot` is edit-mode only, so nothing drawn in a playtest can be looked at by an agent. What can
be checked:

- **That it runs**: a throwaway `LocalScript` under `StarterPlayer.StarterPlayerScripts` (created in edit mode,
  deleted after) that waits for the client to boot, calls the bench, and prints what it finds: how many parts
  are live, a decal's `Color3`, a size. `get_playtest_output` shows the prints and any error. An error in a
  per-frame loop prints every frame, so a quiet output means the whole path ran.
- **That the server side behaves**: `run_luau_live`, and wrapping a `Network.Server.<Ns>.<Event>.FireAll` to log
  what goes on the wire (see memory `reference_tripwire_ftc_playtest`).
- **How a value moves over time**: have the probe sample it every 0.1 s and print the list once (a light's
  `Brightness` over a throw is how its fade was checked: 2.00, 1.54, 0.79, 0.15, 0).
- **A moment you cannot time by hand, driven from the server**: a parry is `ParryService.Open(character, sword, aim,
  melee.Parry, melee.Range * melee.Parry.RangeMultiplier)` opened when an analytic spit (its `SpitSpawned`
  origin, velocity and gravity) is 10 studs out; a lightning strike is `WeatherService.StrikeAt(pos)`. The Sword's
  own `Parry` has gates a server call does not pass.
- **Keep the test lord alive**: three spits down a 20 HP lord, a downed lord drops out of every enemy's targets, and
  the Core going out resets the world under the test. Swap `CharacterService.Damage` for a no-op in
  `run_luau_live` for the test and put it back after.
- **A clip that plays with nothing coming of it: count each hop, never guess.** "The Nest plays its Spawn and nothing
  comes out" was settled in two passes: on the server, wrap `Network.Server.Enemies.AttackStarted.FireList`,
  `Brooded.FireList` and `EnemiesService.SpawnBrood` and log each with a time (5 starts, 5 releases 1.03 s after, 5
  bodies announced); on the client, hook the model's `Animator.AnimationPlayed` and `Workspace.Enemies.ChildAdded`
  (every Spawn followed by a body 1.02 s later). Wrap a service function through the module table: a call made as
  `EnemiesService.SpawnBrood(...)` looks the field up at call time, so the wrapper sees it.
- **Keep a probe light.** A probe that walked `workspace:GetDescendants()` every Heartbeat stalled the playtest so
  badly that `run_luau_live` timed out at its 30 s limit. Watch the one folder that matters (`Workspace.Enemies`,
  where EnemiesController parents every body, and `Workspace.<Effect>` for an effect's own parts) through
  `ChildAdded`, or sample it every 0.1-2 s.
- **Before any of it, check Studio has the new code** (`grep_scripts` for something the change added): without
  `rojo serve` running the playtest runs the old scripts. And a playtest's server Heartbeat runs at 240 Hz, so time a
  probe with `os.clock()`, never by counting frames (Models.md §5).
- **Delete the probe as soon as `start_playtest` returns.** The play session runs its own copy, so the edit-mode
  script can go at once and is never saved into the place by accident. **In Last Wave's Survivors place that did not
  hold (2026-11-09)**: deleted straight after `start_playtest`, the probe never ran on the client (the player joins
  late, after the delete). There, keep the probe until `stop_playtest`, delete it then, and say it was in the place.
- **Count the slots a pool actually used, not its instances.** MortarHatFx's rings make every slot (32 Attachments)
  on first use, so counting Terrain attachments by name says only that a template was reached. Read something the
  code writes per use instead (the scorch's Rotation: 12 shells showed all four burns at three turns, 2026-11-12).
- **Not how it looks.** Say so in the report and let the user judge it on the bench.

If `start_playtest` keeps failing with "a previous one is still in progress" in `get_output_log`, Studio is
stuck; ask the user to press Stop.

## 3. What makes a spit read as a spit (the Spitter's, shipped)

Measured against the user's eye on the bench, 2026-09-26. The code is `Client/Utils/SpitVfx.luau`; the bench is
`spitbench` (the spit and the charged spit side by side).

- **A sphere reads as a cannonball.** What makes a thing read as SPAT is that it is not solid: it stretches
  along its flight, it sheds drops that fall away under it, and it bursts into a splash that stays on the floor.
- **The glob**: one blob stretched along its flight by its speed (`1 + speed / 45`, capped at 2.1, thinned by
  `1 / sqrt(stretch)` so it keeps its volume), Neon bile green `(150, 196, 40)`, a short goo trail, and drops shed
  behind it. The drops are PARTICLES, a round glowing dot: the glob owns one emitter for its flight and leaves a
  TRAIL of dots where it has been (`Effects.SpitTrail`: barely falling, drifting, 10 a second, 12 charged; shed
  forward and falling at 16-32 a second they read as a stream pouring straight down, not a trail), the charge owns one
  for its drool, and the splat throws `Effects.SpitDrop` through `BlobBurst` in acid, sizes varying drop to drop
  through the Size sequence's envelope. They were pooled Neon Ball parts moved from Lua every frame.
- **The dot is the reference dot (`Assets/effects/Dot.png`) with a round core** (`Assets/effects/make_circle_dot.py`,
  `rbxassetid://95624436217204`, on `SpitDrop`, `SpitTrail` and `SpitDrool`). The reference's core is a solid 80-texel
  SQUARE in 346; the circle is that width, its edge supersampled, and its glow is the reference's measured along the
  axes (straight out from the square's flat edge) laid back down by distance from the centre. Before it the dot was
  the reference's alpha averaged over rings (`make_glow_dot.py`), which blurred the square's corners into the glow;
  before that, a solid core to half the radius with a short glow, whose hard edge read as pixelated at particle size.
  Keep the texture white under its faint texels: the reference is black there, which filters into a dark fringe.
- **Everything the Spitter throws is lit the same**: its acid blobs are `Effects.SpitBlob`, the blob with
  `LightEmission` 0.6 and `LightInfluence` 0 like the dots. Through the plain `Blob` (lit by the scene, as the Nest's
  blood rightly is) they read dark and nearly invisible beside the glowing dots.
- **The charged one is the same glob, only bigger** (its data `Size` 1.1 against 0.6), with twice the drops and a
  bigger landing. A dark core inside a translucent glowing rim was tried and **read as an EYE** (the rim outlines the
  dark middle like an iris). The user wanted the same shape bigger, not a different object.
- **Everything that lands is acid green `(160, 255, 50)`, not bile**, because bile vanishes on grass and acid green
  does not: the flung drops, the goo burst (`SlimeMedium` / `SlimeBig`), the ground rings, the puddle.
- **Goo thrown off the glob is the Nest's crisp blob (`Client/Utils/BlobBurst`), in the PUDDLE's green**: the acid
  through the emitter's `Brightness` 2.2, the same push the puddle decal gets. Off the lips as the glob leaves, off
  them as a hit cuts the charge, and off the glob where a parry catches it. It replaced `SlimeSmall`, which was soft
  and in a bile the user found too dark to read. A parried glob then flies back at twice the speed it was caught at,
  so it is seen crossing the field before the damage lands (at the Pistol's 260 it arrived on the same frame).
- **The puddle is a TEXTURE**: the rain's own template (`Effects.VFX.Puddle1` / `Puddle2`, a flat part carrying a
  water decal, the ones `Client/Decorations/Variants` stamps in the swamp), its decal tinted. A Neon cylinder was the
  first version and read as a plastic plate. It is laid only where a spit met the FLOOR (`SpitLanded`'s last field is
  how long it lies, 0 for none): one that struck a lord, the Core or a building splashes and leaves nothing. The rain
  lays no ripple ring in any puddle, this one, the Nest's blood or the swamp's water (`Client/Utils/Puddles`).
- **The pool is an ACID POOL, and it hurts** (L4D2's Spitter's, 2026-09-27): the server keeps it and deals
  `PoolDamage` of the spit's hit every second, on a 0.5 s tick, to every lord standing in it, for `PoolSeconds` (4, the
  charged 7) until it fades (`ProjectileService` pools). Everything drawn on it says so: it spreads over 0.8 s on the
  same curve the server hurts inside (`EnemiesCore.SpitPoolRadius`, so the glow IS the ground that hurts), glows
  brighter than a decal otherwise does (2.8x) with a slow pulse, bubbles with the crisp blob (an emitter under the
  pool part, which emits across the part's box), then dims to a plain wet green and fades as it stops hurting. **Do not
  draw danger that does not hurt**: the living pool was first built as decoration, and the user's rule was that
  effects exist to warn the player off something real, so a pool that glows for 4 s has to bite for 4 s.
- **Two L4D2 pieces lost on the bench and were taken out**: a DARK olive glob with the pool as the only glowing thing
  (the user wants the radioactive bright glob: keep the Neon bile), and a sagging goo strand of Beams behind the glob
  (the plain trail stays).
- **Brightening a decal**: its `Color3` multiplies the texture and takes values ABOVE 1, which over-brightens it.
  The puddle is the acid green times 2.2. That is as bright as a decal gets; it still does not glow in a dark scene
  the way Neon does, and the user accepted that over the cost of anything that would (section 5).
- **Three styles lost on the bench and were deleted**: Mouthful (a lead glob with smaller ones on its path), Acid
  (L4D2's: dark core, glowing trail, smoke, a pool that bubbles and lights the ground) and Jelly (a see-through glob
  that wobbles). The user picked the glob.

What other games do, for the next enemy projectile: L4D2's Spitter throws a glob that trails green and bursts into
a spreading acid pool that glows in the dark and stays for a while (its trail was toned down in a 2022 patch, and a
heat haze was added over the pool); stylised goo is a stretched glob, droplets flung in arcs on impact, and a splat
decal on the ground that fades.

## 4. A charge-up: reuse the Revolver's

The Revolver's charge is the picture the player has already learned as "something is building at that point", so
an enemy winding up a big attack speaks it too.

- **The streaks are `Client/Utils/Gather`**, built for exactly this ("an enemy winding up a blow" is in its header).
  They are Beams between two attachments on a host part, not particles or trails; the header says why (an emitter's
  shape is sized only by its parent part and its particles stop on lifetime, not on arrival; a Trail smears its
  host's movement into world space). `SetLevel` steps it up in notches, `Pulse` flares it on a beat, and
  `SetDeadline` makes the last streaks arrive on the release frame.
- **Only the streaks step. Anything that GLOWS rises smoothly** on the wind-up's own clock (`smooth(t / delay)`).
  The first charge sized its ball and set its light off the notches, and the user saw the light "just appearing
  instead of going up slowly": each notch was a snap. Notches belong to the streaks, where a pulse marks them.
- **The ball is NOT `Kindle` on an enemy.** `Kindle.new` refuses a mount without authored `Core` and `Shell` parts
  and a `PointLight`, on a BasePart host, by design. The Spitter builds its own two Neon spheres and a light.
- **Following a bone**: a Beam or a sphere has to hang off a BasePart, and a mouth moves with the Head bone. The host
  is an invisible anchored Part CFramed every frame to `head.TransformedWorldCFrame * offset`, the offset measured
  ONCE from the bones at rest: `head.WorldCFrame:ToObjectSpace(root.WorldCFrame * MOUTH_REST)`. `WorldCFrame` is the
  rest pose, `TransformedWorldCFrame` the animated one; mixing them up freezes the effect at rest or bakes one frame's
  pose into the offset.
- **The ball IS what is thrown.** The glob that comes over the wire (`SpitVfx.Shot(size, isCharged, from)`) takes the
  ball off the nearest Spitter's lips (its kind, within 5 studs, at or 0.15 s short of its release): the ball goes, and
  the glob starts where it was and at its size, easing onto the server's curve and out to its own size over 0.2 s.
  Past the release the ball rides the lips up to 0.25 s waiting for it, and only bursts there if none comes. Before
  this the ball popped on the lips and a bigger glob appeared from the server's fixed mouth point, and the user saw a
  disconnection between the charge and the throw. The data's `Mouth` is the clip's lips on the release frame (the
  ball's point) so the gap left to ease is a network jitter, not a design one: 0.00-0.12 studs on the bench.
- **What rises smoothly falls smoothly.** The charge's light rose over the whole wind-up and was cut to 0 in one frame
  when the ball went, and the user caught it: it read as a light switched off. It now dies away over 0.4 s, eased and
  riding the mouth, whichever way the ball goes (thrown, fizzled by a hit, burst with no glob).
- **Tie it to the clip**: hand the charge the attack's `AnimationTrack`. If the track stops or fades before the
  release (a hit staggered the body), it fizzles instead of being thrown.
- **What makes the charged one read as bigger** before it leaves: twice the streaks from further out, a ball twice
  the size that trembles harder as it builds (jitter growing with `t^2`), and heavier drool.

## 5. Budget: an effect is drawn hundreds of times at once

Enemy counts reach the hundreds, so an enemy's effect is costed at a full wave of them (the user: "we can have
255 spitters spitting 255 balls and making a lot of puddles"). The rules the spit was rewritten to:

- **Pool everything that is made per shot** (`ObjectPooler`): the glob, every drop, every puddle. Build a per-BODY
  rig (the Spitter's charge: host part, ball, shell, light, both gathers) once on its first use and reuse it; a
  `Gather`'s streaks are built with it, so a gather per throw is dozens of Beams a throw.
- **A pool that never grows is the budget.** `ObjectPooler.new(template, n, 0, ...)` hands back nil once empty, and
  `BlobBurst` holds each template's emitters to 64: past either cap, the extra is simply not drawn, with no counting
  code. A thing that emits every frame for a while (a glob shedding, a charge drooling) OWNS one emitter for that
  time instead of taking a burst slot per emit, which would hold ~11 slots per glob in flight.
- **One Heartbeat, plain arrays**, swap-remove on retire. No per-effect connections and no `task.delay` (a retiring
  glob waits out its trail in a list the same Heartbeat walks).
- **No light, no SurfaceGui on anything there can be hundreds of.** A `PointLight` per puddle and a `SurfaceGui`
  (`LightInfluence = 0`, `Brightness` above 1: the one way to make a decal's texture glow) were built and taken out
  again on cost: each SurfaceGui is a GUI render target, each light a lighting source. They are fine on ONE thing
  (a boss, the Core); a spit's puddle is a plain decal, brightened through its `Color3` (section 3). A light is kept
  only where there is one per body (the charge's ball).
- **Cheap wins that are free**: set `CastShadow`, `CanQuery`, `CanTouch` and `CanCollide` off on every effect part.
- **Cost a weapon at four players with +20 projectiles, at the ultimate's doubled Size** (2026-11-15). The Mortar
  Hat's Detonator chain under Mortar Strike took a 240 fps PC to 40: every blast started a dome (the Aura's shell, a
  MeshPart with five textured layers, its `Size` written 20 times a second), 24 stood at once, each 60+ studs across
  and see-through, so the screen was drawn over ~170 times a frame. Rules since:
  - **A dome (any animated MeshPart `Size`) is for a rare moment only**: the last shell, an ability cast. Never per
    shot, per hit or per chain link. `MeshPart.Size` is a geometry rebuild (BeACastleLord performance/07); a plain
    Part's Size on hard steps (the ground strips) is fine. `ScaleTo` on a skinned model in the scene is the same
    rebuild: scale a template once, unparented, and pool the scaled copies (`MortarHatFx` `FinalBallPool`).
  - **A run of the same blast is thinned**: Detonator's 50 pops a second draw a whole blast every third
    (`Tune.ChainFullEvery`); the rest are a flash and sparks under the same sound run.
  - **Every burst goes through `Utils/fxRings`** (the ring of pooled emitters, the cached `Tinted` / `Faded` /
    `Scaled` sequences, `Aim`), which asks `Utils/fxLod`: past 90 studs from the camera's focus half the particles,
    past 220 or behind the camera none (High; Medium 70 / 170, Low 50 / 120 at a 0.35 share). That is what keeps other
    players' effects cheap without each call knowing whose it is.
  - **One particle budget for everything** (`ParticleHelper.Emit`): an estimate of the burst particles alive, by tier
    (Low 180, Medium 300, High 700). Past it a burst is thinned, never dropped. Emitters with a `Rate` are not in it.
  - **A sprite drawn over a whole blast stops growing**: a Mortar Hat shell's Flash and Fireball are drawn for a radius
    of at most `Tune.ScreenRadiusMax`; the floor sheets still show the whole reach. GPU fill is the screen covered.
  - **Stuck things past a count are data**: past `StuckModelMax` Detonator shells keep no ball, only a blink.
  - **Per-projectile emitters share one budget**: a Yo-Yo rig's trail rates are divided so 20 yo-yos shed what 6 did
    (`Tune.TrailFullCount`), another player's at `RemoteShare` of that; their ground wakes are the local player's only,
    and at most `SweepMax` of the identical Around the World discs are drawn. Another player's strings are straight
    and move every other frame (`RemoteStringEvery`).
  - **Pool what a chain repeats** (Detonator's link Beams), and cache any `NumberSequence` built per shot.
  - **The Particles setting follows the device**: unsaved Visual settings default from the Roblox graphics level
    (`GlobalShared/Utils/qualityDefaults`: Medium caps Particles at 0.6, Low at 0.35), so `ParticleHelper.Multiplier`
    is already lower on a phone. On Automatic a run that cannot hold 45 fps over its first 20 seconds drops a tier
    (`SettingsController`, only ever down). Effects never read the tier directly: `fxLod` and `ParticleHelper` do.

## 6. Engine facts this cost

- **A ray for sight or for where an effect lands is `Shared.Utils.sightCast`, never a raw `Workspace:Raycast` at
  the arena.** The arena holds walls nobody sees (Blockers, Caps, emitter holders: Maps.md §1), and raw rays let the
  crosshair aim at thin air, bullets burst on it and their bricks bounce on it (2026-11-20). `sightCast` passes every
  part at Transparency 1 by casting again from just inside it, and returns the visible hit with its distance from the
  ray's ORIGIN as a second value (the result's own `Distance` is from the last pass, so read the second value).
  Aim, aim assist, the server's shot, thrown bricks and casings, defense placement and the pistol bench use it.
  Probes for where a BODY stands (footsteps, an enemy's floor, ragdolls) stay raw: bodies do meet those parts.
- **A `Ball` part is always round.** A non-uniform `Size` does nothing to its shape. Stretch a glob with a
  `SpecialMesh` (`MeshType = Sphere`) and its `Scale`, on a Block part.
- **A `VFX.Burst` name has to exist** under `ReplicatedStorage.Effects.VFX`, or it warns once and draws nothing.
  `EVfxNames` lists names that have no template in this place (`Splash`, for one). What exists: `SlimeSmall`,
  `SlimeMedium`, `SlimeBig` (soft: do not use, see the top of this file), `Droplet`, `Steam`, `Smoke`, `Spark`,
  `Charge` (an aura for `VFX.Aura`), `Puddle1`, `Puddle2`, `WaterRing`. List the folder before choosing one.
- **A particle brightens like a decal through `ParticleEmitter.Brightness`**, which multiplies its colour the way a
  decal's `Color3` above 1 does. A `ColorSequence` clamps at 1, so "the puddle's tint" on a particle is the puddle's
  base colour with `Brightness` set to the puddle's multiplier (2.2), not the multiplied colour.
- **A Decal is tinted by `Color3`**, which multiplies its texture (values above 1 brighten it), so a light texture
  takes any colour. Fade it with `Decal.Transparency`, not the part's.
- **A Trail on a part that is about to go** should be disabled first and the part kept a trail's lifetime, or its
  ribbon vanishes on the spot instead of fading where it was.
- **Anything flat on the floor lies on the floor's normal, not on world up.** Last Wave's slopes are 30 up over 40
  across (37 degrees, normal Y 0.8): an 8-stud sheet drawn level there has one edge 6 studs in the air and the other
  6 buried. The Neon cylinder it replaced followed the slope (it copied the VisualRoot's tilt), so a level pixel sheet
  read as a regression (2026-11-11). A flat sprite (`Orientation` VelocityPerpendicular, thrown along its
  attachment's +Y) lies on whatever plane its attachment's up names, so aim the attachment at the normal; a strip is
  `CFrame.lookAt(mid, mid + along, normal)`; a dome stands on it the same way. Two ways to get the normal:
  - A raycast down into `Workspace.Map` (Include filter) from 2 studs over the feet to 4 under, as BootsFx's
    `groundAt` does. Take the hit's Position too: on a slope the feet ride ~0.5 studs over the floor
    (CharacterController holds the root at hipHeight / normal.Y). It works for every player and for points the
    wielder has already left (a dash's gusts, an echo, a tear). A miss (a jump) or a wall's edge (normal Y under
    0.3) stays level at the feet.
  - The disc's own tilt, as AuraAbilityFx's `discSpot` does, for an effect that must match layers riding a part
    welded to the VisualRoot. CharacterController tilts only the LOCAL player's VisualJoint (a client write, never
    replicated), so another player's disc and its effects stay level on your screen.
- **A flipbook sheet needs a clear gutter round every frame.** A sheet is one image mipmapped as one, so seen from
  afar a frame's edge row blends into its neighbour's. The Shovel's spike stood its foot (and the dust kicked out
  along it, 18 texels wide) on its frame's last row, and every spike carried a thin line floating over its tip: the
  frame above's foot (2026-11-11, spotted by the user). Keep 2 texels clear on every side of a frame, and check it in
  the sprite script (alpha in the outer 2 rows and columns of each frame, 0 frames allowed), not by eye: a crumb
  falling to the foot touched it in one frame of sixteen. A sprite stood on its foot is then dropped by the gutter.
  The sheets drawn before this rule (35 of them, across every kit, 2026-11-15) are padded at build time by
  `Assets/effects/frame_gutter.py` rather than redrawn: each frame gets clear texels round it, and every emitter showing
  one gets its Size multiplied by `frame_gutter.size_factor`, so nothing changes size on screen. The generator also
  writes the drawing's share of the frame on the template as the `DrawnShare` attribute (absent means 1): code that
  reads a template's Size as the drawing's half multiplies by it (`FLAT_HALF` in BootsFx, ShovelFx and YoYoFx), and
  the Revolver's orb reads its frame rect from `FramePixels`. Never copy those numbers into code. A sheet whose PNG
  changes loses its ids from images.json, so the generators fail on it until it is minted again. A padded sheet past 1024 pixels drops to fewer pixels a texel; the Aura's three 128-texel sheets
  are drawn 4 texels smaller instead, to stay at 2.
- **ScaleTo sets an ABSOLUTE scale**, and a template can be authored at another one: the Shovel's model is at scale 2,
  so a game `ScaleTo(1)` halves it. Anything read off a template's geometry (how far a blade hangs under its pivot)
  is divided by `template:GetScale()` before it is used per game scale; reading it raw lifted the shovels twice too
  far (2026-11-11).
- **A texture's way round on a Top face was never seen** (Studio was minimized, so `capture_screenshot` timed out). A
  sprite with a near and a far end is laid by one named flag (`ShovelFx` `Tune.IsSpriteTopAtBack`, reasoned true: the
  Front face tipped back puts the image's top at +Z) instead of being drawn symmetric, and the flag is the first
  thing to check on screen. `capture_screenshot` works in edit mode only and needs Studio on a monitor; laying the
  parts out by hand under a top-down camera is the quick check.
- **Draw nothing past where a hit reaches.** A ring centred on a line's last point paints half its diameter past the
  line: Groundbreaker's end smack (13.5 studs across on its last spike) painted to about 36 studs over a 30-stud hit,
  and the user read the hit as longer than it is. An end piece is the line's width across and centred half a width in;
  a spike stands half a sprite in; anything thrown off the end goes up, not out.
- **A particle keeps the `Rotation` it is born with.** Set `ParticleEmitter.Rotation` before `Emit`; setting it
  after only turns the next emission. With a pooled ring of emitters, write it on the slot that will emit next
  (`ring.Emitters[ring.Next]`), as MortarHatFx `scorch` does (2026-11-12).
- **Turn a pixel sprite only in quarter turns.** A random Rotation range tilts the texel grid off the screen's and the
  pixels go jagged and uneven. Pick from 0, 90, 180 and 270 in code (a `NumberRange` each) instead of authoring a
  0-360 range on the template.
- **A motion that ends must ease out of its own speed, not jump to rest.** Whirlwind posed its shovels at
  `now * SPIN_SPEED` while up and at 0 the frame it ended, so they snapped back (the user: "should stop smoothly and
  not as a snap"). A rotation of N identical things rests on any multiple of `2 pi / N`, so it can coast forward to the
  next one: constant deceleration from the spin's speed lands `speed * T / 2` on, so pick that multiple and solve T
  (`ShovelClient.SpinDown`). Catch the stop in the per-frame pose where the flag is read, not in the ability's
  handler, or a frame can draw the rest pose first. Same family as section 6's fade on an over-bright colour: an
  ending has to be seen.

## 7. A Nest bringing a body out (the Retch, shipped)

Picked on the bench, 2026-09-27. The code is `Client/Utils/NestVfx.luau`; the bench is `nestbench` (one Nest per species
it brings out, so the scaling is judged side by side).

- **A body that pops into the world reads as a bug.** Valheim's nests do nothing else (a dark smoke poof with sparks
  and a one-second light hides the pop, `vfx_spawn_small`), and that was one of four styles on the bench. The user
  picked **Retch**: blood drools off the jaw through the wind-up, a gush comes out of the mouth with the body, and the
  body slides out of the mouth on its belly and stands up in a spreading pool. The motion is a rig-only offset laid
  like the flinch's give-ground (`EmergeOffset`), started by `Enemies.Brooded`.
- **Three styles lost and were deleted**: Poof (Valheim's), Sac (a brood sac swelling in the mouth and bursting) and
  Rise (clawing up out of the ground).
- **It scales with the body, like Valheim's effect prefabs scale with the creature**: the gush by the
  geometric mean of the body's height and width against the Zombie's (5.43 x 3.96), and **the pool WIDER than the
  body**, 1.6 times its width across. A pool sized like the particles read as tiny under every body, worst under the
  Brute. The puddle texture fills its part (73-81% of it is puddle), so the part's size is the pool's.
- **A rig faces its own +Z, so its forward is `-LookVector`.** The first gush was thrown along `LookVector`, straight
  back into the mound, and was never seen. It now leaves the lips in a tight cone, forward and only a little up, the
  way `SparkDirectional` leaves a struck face: the Nest spits the body out.
- **The body rises in its Idle and only then walks.** The server holds it still for `TEnemyBrood.Hold` (speed 0 and
  a negative wind-up, given back by EnemiesService's Heartbeat), so the client's Walk never starts under the emerge.
  It stands its own half-width out past the lips, so a Brute does not come out with its back inside the mound.
- **Never fire an emitter from two places in one frame.** Moving an emitter's attachment and calling `Emit` again in
  the same frame draws only one of the bursts. A ring of six blob emitters lost the gush of the first and last Nest on
  the bench (four Nests releasing together fire eight bursts, and the ring handed out the first two twice), and one
  drool emitter shared by every Nest drooled at only some mouths. Now a burst holds its emitter for its particles'
  lifetime and a Nest holds its drool emitter for its wind-up; the pool grows when all are busy, to a cap.
- **Particles, never parts, for drops.** The first version flung pooled Ball parts; each is a part moved from Lua
  every frame. Now every drop is a particle: a ring of pooled attachments per kind on one host part, each with its
  own emitter, so a burst sets its size and speed without resizing what an earlier burst left in the air. The one
  part per birth is the pool (the rain's puddle decal, tinted). That pool of emitters is `Client/Utils/BlobBurst`
  now, shared with the spit; a burst is a frozen `BlobBurst.Layer` thrown with `BlobBurst.Emit`, and its cap (64
  emitters, each held under a second) is the budget for both.
- **Use only CRISP textures.** The Visuality sprites under `Effects.VFX` (`SlimeSmall/Medium/Big` and the rest the
  uploader made) were upscaled SOFT and read as smeared pixel art. The weather's (`Droplet`, the four rain splashes,
  the ripple, the puddles) were scaled NEAREST-neighbour and are fine. So a sprite is taken from its source PNG
  (`~/Projects/Mods/Old/visuality`, `.../SubtleEffects`), scaled nearest to ~256 a frame, greyed so an emitter's
  Color tints it, and minted as a new Image: `Assets/effects/make_blood_blob.py` is the worked example.
- **Minting an Image without the command bar**: Open Cloud makes Decals, and a Decal id does not draw on an emitter
  at runtime. Wrap the PNG in a one-quad FBX (`Assets/effects/texture_to_fbx.py`), upload it as a Model, insert it,
  and the MeshPart's `TextureID` is the Image id (read it with `run_luau_live`; the edit-mode property read does not
  show it). The blood blob is `rbxassetid://127237296613837`.
- **The weather's splash and droplet were tried on it and taken off**: the gush is the blood blob alone, and the pool.
  What they taught, for the next effect: **size a particle by what its sprite DRAWS, not by the sprite** (the rain drop
  is one texel of an 8-texel sprite, so a drop given a blob's size drew a dot a thirtieth of a stud across), and **a
  burst at a body's own feet is hidden by the body** (put it round the feet or where something lands).
- **An effect's look is authored under `ReplicatedStorage.Effects`, not built in code**, beside the hand-authored
  `EnemyHit`, `EnemyCrit`, `Overkill`: `Blob`, `NestDrool`, `SpitBlob`, `SpitDrop`, `SpitTrail` and `SpitDrool`
  (Attachments carrying one emitter; `BlobBurst` keeps one pool per template), `SpitGlob` (with its mesh and trail),
  `SpitChargeBall` (with its light), `SpitChargeShell`, `SpitPoolBubbles`. The code
  clones and pools them (`BlobBurst.NewEmitter(template)`, `ObjectPooler.new(Effects.SpitGlob, ...)`) and sets only
  what depends on the moment: a burst's size and speed for the body, its cone, colour and position. Reading a value
  off the template instead of repeating it (`SLOT_HOLD_SECONDS` is `Effects.Blob.Emitter.Lifetime.Max`, the glob's
  trail wait its `Trail.Lifetime`) keeps a Studio tweak from going out of step with the code. It is not faster: an
  emitter is built once either way and a burst costs the same; it is so the look is tuned by eye in Studio. The cost
  is that `Effects` lives in the place, not in Rojo, so a tweak needs the place saved and never shows in git.
- **Making those templates when Tripwire cannot**: its property writer takes no `NumberRange`, `NumberSequence` or
  `ColorSequence`, which every emitter needs. Write them as an `.rbxmx` instead (`Assets/effects/make_effects_rbxmx.py`
  holds all seven, with the values the code used to build), upload it as a Model (`content_type = "model/x-rbxm"`),
  insert it into `ServerStorage`, move its children into `Effects` by `Parent`, and delete the import. Read every
  value back live after: the file stores enums as numbers (`FlipbookLayout` Grid2x2 = 1, `FlipbookMode` Random = 3,
  `NormalId` Top = 1, `PartType` Ball = 0, `Material` Neon = 288, `MeshType` Sphere = 3), a Part's size as lowercase
  `size`, its colour as `Color3uint8`, and a Trail's attachments as `Ref`s to referents in the same file.
- **Tripwire cannot download an asset** (403 on both its tool and asset delivery). To see a texture in the place, read
  it in a playtest: `AssetService:CreateEditableImageAsync` gives its size and `ReadPixelsBuffer` its pixels.
- **Telling a crisp sprite from a soft one by its pixels**: a nearest-scaled sprite is runs of identical pixels in
  blocks (`Splash1` is 96 square, a 48-texel splash at 2x; `Droplet` 96, an 8-texel dot at 12x); a soft one has no
  runs (`SlimeMedium` is 128 square for four 8-texel frames, LANCZOS). And read what the sprite fills before sizing
  it: the puddles fill their whole texture (`Puddle1` 73% of it is puddle, `Puddle2` 81%), the drop one texel in 8.
- **An emitter's texture must be an IMAGE id.** Read a template's with a live `run_luau_live` over
  `Effects.VFX:GetDescendants()` (`Texture`, `FlipbookLayout`, `Lifetime`, `Size`); the edit-mode property read
  leaves `Texture` out.
- **The bench stands the effect beside every case it scales over**, not beside its rivals only: `nestbench` puts up one
  Nest per species it brings out, so a Brute's gush and pool are judged next to a Runner's. Bench bodies are local
  models placed by their part's `CFrame` (`feet * EmergeOffset * rootOffset`, the Root bone's rest cancelled), since
  no renderer is writing their bone, and they switch Idle to Walk off their own age in the bench's Heartbeat.

What other games do, for a nest's next effects (Valheim, decompiled off `assembly_valheim.dll` in
`~/Projects/Valheim`): every nest and pile (`Spawner_GreydwarfNest`, `Spawner_DraugrPile`, `BonePileSpawner`) spawns
through one shared, cheap effect, `vfx_spawn_small`, fired at the NEW creature's chest, never at the nest: 300 dark
alpha smoke puffs that swell in the first 8% of life and dissolve over ~3 s, 30 stretched sparks white to orange, two
layers of drifting embers, and a magenta light fading from full to 0 over 1 s. The creature itself does nothing (no
rise, no fade). The drama is in the nest being HIT and DESTROYED: a hit throws sap blobs, gravity droplets, a few
splats that stick, ground decals that last 5 s and tumbling twig meshes at the impact point; destruction breaks the
nest into ~55 pre-fractured chunks with physics, with 50 growing splats, 200 droplets, soft dust clouds over a 4 m
hemisphere and 60 thrown twigs. Nests also idle with an ambience: a coloured point light (4 m range) and a slow
smoke or fly bed. The Nest's own hit and death effects are not built yet; that is the reference for them.

## 8. The next effect, in order (what cost a round with the user last time)

Every step here was a round of feedback on the Nest and the spit. Doing them up front is the difference between one
look and six.

1. **Read what the reference does and measure it.** Valheim, L4D2 or whatever the user names: find the files
   (`~/Projects/Valheim` decompiles with `ilspycmd`), and put numbers on it (counts, sizes, timings, colours) before
   drawing anything.
2. **Bench the candidates side by side in the running game** (section 1), one per style or one per case the effect
   scales over, and put it up in a playtest for the user (a probe LocalScript calling the bench's `PutUp`, deleted as
   soon as `start_playtest` returns). Describing styles in chat does not settle anything. Once one is picked, delete
   the losers and the switch.
3. **Textures: crisp or nothing.** Never a sprite from `Effects.VFX` unless it is one of the weather's (section 7).
   Take the source PNG and scale it nearest-neighbour, or generate it at full size; if the user gives a reference
   texture, measure its shape (a radial alpha profile, a coverage) and rebuild from the numbers rather than by eye.
   Keep a tintable texture white under its faint texels. Mint it (section 13: a Decal, then its Image) and read the
   Image id.
   **Keep every pixel sprite twice: its ORIGINAL at one pixel a texel in a `src/` folder beside it, and the
   upscaled PNG made FROM that original.** The user paints on the small one. The generator draws an original only
   when `src/` has none; once it is there it is the sprite, whoever painted it, and no run draws over it
   (`--redraw <name>` to start one again from code). Scale by a WHOLE number of pixels a texel, the one that brings
   a frame closest to 256: a 12-texel frame stretched to exactly 256 got texels 21 and 22 pixels wide by turns.
   The script prints which upscaled PNGs changed, and only those are minted again. `Assets/effects/runes/
   make_rune_sprites.py` and `Assets/effects/make_blood_blob.py` work this way. A smooth texture (a glow dot, a
   ring, a ray) has no texel grid and no small original: its script is its source.
   Before touching a sprite on disk, check whether he painted it: redraw into a scratch folder and compare pixel by
   pixel. On 2026-10-15 five rune sprites had been repainted by hand, one of them on a new canvas size (17 x 15).
4. **The look lives in templates under `ReplicatedStorage.Effects`, all of it**: texture, flipbook, lifetime, fall,
   drag, speed, spread, colour, brightness, lighting. Build them with `Assets/effects/make_effects_rbxmx.py` (add to it;
   it is the source), upload, and move in only the templates that changed, so the user's tweaks to the others survive.
   Code sets only what depends on the moment: size from the body, direction, position, the count. A value the code
   needs to agree with (a hold time, a trail's wait) is READ off the template, never repeated. Remind the user to save
   the place.
5. **Particles, never parts, for anything small and numerous.** A burst takes a pooled emitter for its particles'
   lifetime (`BlobBurst.Emit` with a `BlobBurst.Layer`); something that emits every frame for a while (a trail, a
   drool) OWNS one emitter for that time. Never move and fire one emitter at two places in one frame.
6. **Light every piece of one effect the same way.** A blob lit by the scene beside glowing dots read as nearly
   invisible. Pick `LightEmission` / `LightInfluence` / `Brightness` for the effect as a whole and give every template
   in it the same, unless a piece is meant to sit in the world (the Nest's blood is lit by the scene on purpose).
7. **Scale by what it plays on, and make ground marks bigger than the thing standing in them** (the pool is 1.6
   times the body's width). Particles by the geometric mean of height and width against the Zombie's.
8. **A mark left behind many times gets several drawings.** The Mortar Hat's one scorch, under every blast, read
   as the same stamp over and over ("make variances for the black png that is leaved on the floor", 2026-11-12).
   Draw a few with different art (not one sprite moved several ways), pick one per mark, and
   add a quarter turn and a size within about 15% on top. MortarHatFx `scorch` is the pattern.
9. **Aim it where it is seen.** A rig's forward is `-LookVector`; a burst at a body's own feet is hidden by the body;
   a spray from a mouth goes out in a tight cone (`SparkDirectional`-like), not up into the thing that threw it.
10. **Rates and trails**: a trail is dots LEFT where the thing has been, barely falling (low `Acceleration`, some
   `Drag`), at around 10 a second; thrown forward and falling hard at 16-32 a second, the spit's "trail" read as a
   stream pouring down, and the charged one's doubled rate was too much. Start sparse; the user asks for more before
   they ask for less.
11. **Budget and check**: a cap per template, counts read back in a playtest over a few seconds (they must stay flat),
    every template's values read back live after an upload, StyLua and Selene. Say plainly that the look itself was
    not seen.

## 9. The Bloater's two moments (Burst, and Splat with Shock, shipped)

Picked on a bench, 2026-09-28. The code is `Client/Utils/BossVfx.luau`; the bench (`bossbench`, and `bossstyle` to set
what the game drew) was deleted with the losers once the pick was made. BossRender hands it the moments, so
EnemiesController (near its 200-local ceiling) gained no local for it.

- **What it was before**: a sac died through the ordinary vanish puff at its SERVER position, which is not where it is
  drawn (the mount pass hangs it on the body's swaying bone), and the fall landed on nothing. Both are what the fight
  is about (a sac takes 10% of the body with it; the landing crushes whoever is under it), so both got their own.
- **The pop is `Burst`, where the sac is DRAWN**: its Root bone's `TransformedWorldCFrame` (the anchor, one frame late,
  which a burst does not notice) out along its own +Y by half its height, sized by the sac's drawn width, so the small
  fourth sac bursts smaller. Glowing drops in a ball, goo thrown out and falling, a flash.
- **The crash is WARNED because it hurts** (section 3's rule, the other way round: a real danger has to be drawn). A
  `VFX.GroundRing` of the crush radius grows from the frame the fall starts and reaches its edge on the frame it lands
  (`Boss.CrashImpact`, 0.5 s).
- **The landing is `Splat` and `Shock` TOGETHER, which was the pick**: a shockwave out past the ring, glowing goo and
  drops thrown up out of the ground (Shock), and a sheet of dark scene-lit goo thrown low with a stain the width of the
  crush left under it (Splat, lit by the scene like the Nest's blood so it is not read as an acid pool that hurts).
- **Both shake the camera, by how near the lord is**: full where it happened and nothing past the reach, falling off
  on the square of the share left. The landing is a blast (5, out to 32 studs), a pop an impact (3, out to 24), both
  inside CameraController's band. Not gated on the particle multiplier; the Screen Shake setting turns it off.
- **Three lost and were deleted**: `Rain` (a sac tearing and pouring goo straight down), `Cloud` (a puff of gas as big
  faint `SpitTrail` dots, the one template that barely falls) and `Quake` (two rings, a flash and a hard shake; its
  shake survived, moved onto both moments and scaled by distance).
- **All crisp**: the drops and goo are the spit's own templates (`SpitDrop`, `SpitBlob`) and the Nest's `Blob` through
  BlobBurst; the rings are the 1024 ground ring; the stain is the rain's `Puddle1`, tinted. The flashes are one pooled
  PointLight each, allowed because there is one boss (section 5).

## 10. A blow on a Shield's door (reused, not built)

A blow the door blocks (TEnemy.Shield) had the Block clip and nothing else, and the user asked for effects and a sound.
It uses the WORLD's impact language rather than a new effect: `Client/Utils/SurfaceImpact` (chips in the surface's
colour spraying back along the blow's line, sparks only off hard material, the material's `Hit` clip from
`Sounds.Materials`), through `SurfaceImpact.PlayMaterial`, since the door is a skinned body that the casts filter out.
The data names what the door is (`ImpactMaterial` WoodPlanks, `ImpactColor` the planks' mid tone), so it knocks on wood
and splinters like the planks a lord has already shot. `EnemyImpacts.BlockImpact` puts it on the door's face off the
`Shield` bone (0.35 ahead of it and 0.35 up), at the attacker's height and side clamped to the slab, and `Enemies.Blocked`
carries the attacker for it. Measured: three blows from a lord 6 studs in front landed on the face toward him at his
chest height, normal his way. No bench was put up: it is the game's existing impact, not a new look; if the user wants
more than a wall gets (it throws six chips against a wall's four), that is where a bench of variants starts.

## 11. A thing on the ground: put down, lying, collected (shipped, unjudged)

Built 2026-10-09 for things dropped out of the pack, and it is the floor seals will lie on. The code is
`Client/Controllers/GroundItemsController.luau`; the authority is `PackService`'s ground. **Nobody has looked
at it yet**: it was traced in numbers through a playtest, never seen. Every number is in that file's `Tune`.

**Appearing and vanishing are both a snap, so each is a MOVE.** A dropped thing was first a model that popped
into the world and was deleted when taken, and the user called the take "a snap". Three moves replaced it:

- **Put down**: out of the dropper's chest on an arc whose rise is a SHARE of the trip (0.3), turning, in
  0.42 s, then two small hops that decay (`0.45 * e^(-7t) * |sin|`).
- **Lying**: one turn in 12 s and one rise and fall in 4 s. The first cut turned in 5 s and bobbed every
  1.25 s and read as "spinning in place"; the user asked for both slower. The bob only goes UP from rest
  (`(1 - cos) / 2`), so it never dips into the floor.
- **Collected**: UI.md 5j's launch, hang and pull, in the world, in 0.62 s. It sinks 0.22 studs and shrinks
  (the anticipation), is thrown 2.4 up and 1.1 AWAY from the taker against drag (`1 - e^(-16t)`, 93% spent
  by the end of the throw), hangs at 1.22 times its size, then is pulled into his chest on a cubic that
  carries on the way it was thrown for 22% of the distance and bows to one side by 22 to 40% of it, on
  `u^2`. Measured: about 2 studs a second in the hang against 37 at the landing. That contrast is the whole
  effect.

What it cost:

- **The reward lands with the flight, on both sides, off one number.** The server takes the thing off the
  floor when he touches it and puts it in his pack `PackCore.Tune.CollectSeconds` later (a `TimeCore.GameClock`
  deadline checked in its own Heartbeat, never `task.delay`); every client flies it for the same number. His
  pack room is held from the touch, so two things reached on one step cannot both be promised the last cell.
- **Throw it AWAY from whoever is taking it.** A pull needs somewhere to come home from. Straight in from
  where it lay is a conveyor belt.
- **The far end of the pull is his chest THIS frame**, read live, so a lord who keeps walking is still what
  it lands in.
- **No spark at the landing** (5j). The arrival is the streak, the collect cue at his body, and for the one
  it went into a small camera kick and FOV punch (`AddRecoil(1.1, 0)`, `PunchFov(1.4, 0.22)`).
- **A model's own scale is not 1.** The Sword's model is authored at 3.38, and `ScaleTo(0.88)` on the first
  frame of the collect shrank it to a quarter. Read `Model:GetScale()` once and scale as a share of it. The
  playtest trace caught this; a linter cannot.
- **The streak is a Trail, so the model outlives the landing by the Trail's lifetime** (section 6): hide the
  parts, switch the Trail off, and destroy the model once the ribbon has run out. Destroying on arrival cuts
  the ribbon off in the air.
- **A weapon lying on the ground has its own Trails, emitters and Beams switched off.** A Sword's swing trail
  is authored Enabled and smeared a ribbon behind every turn.
- **Stand it on the floor by its own lowest point.** The server's spot is a point in the air ahead of him; a
  thing hung by its pivot from there goes into the ground by however far it reaches below the pivot. Raycast
  down, take the world-space half height of the tipped bounding box
  (`0.5 * (|X.Y| * sx + |Y.Y| * sy + |Z.Y| * sz)`), and lift until the bottom clears the floor by 0.35.
- **Trace a move you cannot see.** A probe that samples `GetPivot()` and `GetScale()` every 0.06 s and prints
  one line is how the arc, the hang and the scale bug were all read. The path was simulated in `lune` first
  (the module's own formulas pasted in), which is where the speeds above come from.

Owed: a cue on the throw and on the put-down (only the landing speaks), and pooled bodies before seals put
dozens down.

### The light it stands in (Breeze, shipped)

Picked on a bench, 2026-10-10, off the user's reference: Terramity's dropped item (a thin shaft of the rarity,
thin streams winding up it). The code is `Client/Utils/GroundGlow.luau`. The bench (`groundbench`, and
`groundstyle` to set what the game drew) was deleted with the losers once the pick was made.

**Breeze** is four pieces, each kept quiet: a hard bright line in a pastel stroke of the rarity, two or three streams of the
rarity winding up round it, a little of Megabonk's ray fan (`Utils/Rays`) out of the thing itself, and a few tiny
square sparks (`Effects.VFX.Spark`, 0.16 studs, about one a second) drifting up off the ground under it.

What lost, so nobody builds it again:

- **Lootbeam** (the Loot Beams mod's soft shaft in a wide faint one, with a ring over the floor): "too 2D". A soft
  camera-facing bar reads as a flat card; the hard line in a stroke does not.
- **The first streams**: white threads that stood up off the floor, curled over and stopped. They read as GRASS.
  The reference's are wind: the rarity's own colour, travelling upward, winding round a cylinder about the shaft.
  Swirl was the same threads born in order and went with them.
- **The fan at one height for every thing** (0.9 over the floor): the light came out under a Shotgun. It and the
  motes now stand at the middle of the thing's own box.
- **Terramity alone** (no fan, no motes) and **Fan alone** (short shaft, no streams, no frame): each was half of
  what was picked.
- **Gale**: Breeze before it was turned down (three streams, the whole fan, round glowing motes out of the thing,
  a square frame on the floor). The user asked for less of each, the square sparks in place of the motes, and the
  frame off.
- **Standing up at once, with a swell and a ground ring, and being pinched shut in 0.14 s**: the user wanted it to
  come and go smoothly. It eases in over 0.9 s from the frame the thing LANDS (never while it is in the air) and
  out over 0.45 s as it is taken, on a smoothstep, with no ring.
- **Nothing joins the shaft to the ground, and two tries at it were taken off.** A soft pale pool under it (the
  spit's dot as a decal) read as a second thing beside the shaft; a flare at its foot over two hard discs in its
  own colours was refused on sight. The shaft simply stands on the floor. Do not build a third.
- **A PointLight on each thing**: taken off. A wave can leave dozens lying, and section 5 already said so.

What is in it, for whoever tunes it:

- **A stroke is paint, not light, and it is PASTEL.** The stroke beam has `LightEmission` 0 and the rarity's own
  colour as the pack draws it; the bright line sits in front on `ZOffset`. It was the hue made fuller and darker
  first (`deepOf`), and the user called the whole glow too dim: from any distance the 0.2-stud bright line is
  lost and the dark 0.52-stud stroke is what stands there. Do not darken a stroke on something seen from far off.
- **A stream is one Beam riding a helix.** A beam leaves its first attachment along that attachment's RIGHT vector
  and arrives at its second along that one's, so with both ends stood on the cylinder and both rights on the
  winding's tangent, the bezier between them IS the piece of helix (handles a third of the arc; 0.04 studs off
  the cylinder at its longest and tightest, 117 degrees, measured in `lune`). Every frame its head and tail are
  moved up the helix.
- **It has no tip to stop.** Its transparency is 1 at both ends, its head is clamped at the top and its tail at
  the floor, so it grows out of the ground, travels, and is eaten from below against the top. Nothing is ever
  seen to start or end.
- **A thing is moved by the middle of its box, not its pivot** (`placed`): a weapon's pivot is its grip, so turned
  about that it swung round its handle and stood beside the shaft instead of in it.
- **The tier climbs in height and count**, not only in colour: 3.5 studs of shaft a tier, a third stream from the
  fourth tier, and a few more rays and sparks a second. A seal's shaft is 10 studs taller than a dropped thing's.
- **It comes and goes on one number.** `Open` runs 0 to 1 over 0.9 s and back over 0.45 s; the shaft's width, the
  streams' width and the fan's level all ride its smoothstep, and the shaft's top rises with it on the way in.
  Measured in a playtest: the shaft's width went 0, 0.05, 0.12, 0.19, 0.21 at quarter seconds from the landing.
- **A shut glow removes itself.** Taken, it eases out and then waits 2 s (the longest life of anything it put in
  the air) before it goes, so no spark or ray is cut off mid-flight. `GroundItemsController` lets it go and does
  not destroy it; `Destroy` is only for a thing taken away with nobody watching.
- **What one costs is what it costs when nobody is looking at it.** A glow is SEEN inside 110 studs of the camera
  AND inside its view (the diagonal field of view plus 12 degrees), or inside 18 studs whichever way the camera
  faces. Unseen, it is its shaft only: no stream is born, the fan and sparks are off, the shaft does not breathe
  and its step writes nothing. The thing under it is not turned or bobbed either (a `PivotTo` of every part,
  every frame).
- **Still owed**: nothing is pooled (a glow is about 30 instances at the first tier and 45 at the last, built when
  a thing lands and destroyed after it is taken), and the sparks are `Effects.VFX.Spark` recoloured in code where section 8.4 wants the look in its own
  template under `Effects`.

## 12. Opening seals (Meteor, shipped)

Picked on a bench, 2026-10-10. The code is `Client/Utils/SealOpening.luau`; the bench (`sealbench`, `sealstyle`,
`sealopen`) was deleted with the losers once the pick was made. PlanRunes.md 9 keeps what the deleted PlanLoot.md said of it.

- **Meteor**: the seals are shot up out of the pack, a shaft of each one's tier stands up where it will come
  down, and they fall one at a time down their own shafts and break open where they hit. The thing inside is
  knocked up out of the hole into the ground's own light (section 11) in its rarity.
- **Three lost and were deleted**: Hatch (thrown out in a row, hopping, jumping open from the ends inward),
  Halo (circling him, the ring of seals turning into a ring of things) and Totem (a tower that goes from the top,
  each thing thrown to a ring round its foot). Meteor won on being the one nobody had seen before.
- **A beat with nothing in front of him reads as a fault.** Meteor's first cut sent the seals up and left the
  ground empty for a second, and with his eye and feet free the user looked away from his own opening. Three
  things fixed it, and any opening wants all three: something stands up IN FRONT of him inside a tenth of a
  second (the shafts), the press is answered in his own view on its first frame (a kick and an FOV punch), and
  his eye and feet are held until the payoff is over (`CameraController.HoldLookAt`, `SetImmobile`).
- **Throw it where there is room.** A row laid along his facing lands inside the wall he is looking at. The way
  it goes is the first of ten bearings off his own with no hit out to the row's reach and floor under its middle
  and far end. In the playtest a lord facing the Core had it turned 35 degrees.
- **Look for the floor low.** A ray dropped from ten studs over his feet stood a seal on a tree branch; from 3.5
  over and 3.5 under, it finds the ground or nothing.
- **No words over what comes out.** A name and rarity card over each thing was built and refused on sight: the
  thing and its light say it.
- **What is in his hands gets out of the way.** The pack at rest stood across the bottom half of the row, so it
  and both hands sink 1.25 studs down his view for the length of the opening (`PackController`'s `sunk`).
- **A mark is one beam, not a ground light.** Ten `GroundGlow`s built on the press frame is some four hundred
  instances; the shaft a seal comes down is one Beam on one part, and the ground's light is built per thing as
  each lands.
- **One light for all of it**: a single PointLight moved to each impact and left to decay (section 5).
- **Blur and saturation were left off on purpose**: blur smears the things being shown and less saturation washes
  out the rarity colours that are the whole reveal.
- **Checked by probe, not seen**: camera type, walk speed, the aim's dot onto the row, beam and model counts
  sampled every half second through a ten-seal opening.


## 13. Runes: on a body, and on the thing they are set in (built, unjudged)

Built 2026-10-11 by four sessions from one brief (`Assets/effects/runes/BRIEF.md`), every check a count read
back in a playtest. On the weapon the user has since picked Frost Sink, Tesla Crawl, Burn Licks, Venom as Fume and
Drip in one (Brew), Curse Orbit, Rupture Chips, Shatter Shards with Crack's rime dust, and Layers for several runes in
one thing; the losers are deleted (`RuneDress.luau`'s header names them). On a body (`runebench`, 2026-10-15): Chill
is Breath with Flurry's snowflakes, Frozen is Spikes with Cased's small crystals and glint (the big spikes only on
the trunk, where they were too big on the head) and breaks as Chunks thrown from the shoulders, Burn Blaze, Venom
Ooze, Curse Marked with its eye 0.2 higher, Tesla Storm with Flicker (picked for the user, who saw little between
the two), Rupture Gore with Pop's sparks. Still to pick: how a Shatter shard flies (Darts or Lances), and the
shapers on the weapon.

- **Tesla is yellow** (`255,255,196` to `255,226,0`), not lightning blue: beside Frost and Shatter the user could not
  tell it apart. One element, one colour no other rune is near; it is set in RuneLooks, RuneDress, the kit's `TESLA`
  ramp, the skin flash and `UIColors.Shock` (the gun's tracer).
- **Draw round a weapon's SURFACE, not its line.** A weapon is one mesh, so neither its line nor its box is its
  shape: arcs and an orbit a fixed distance off the line went through the Revolver's rib, hammer and cylinder. The
  outline is measured once a kind of weapon when its dress is built (`RuneDress.rimOf`): rays cast in toward the
  line from 20 directions at 13 slices, against the weapon's own parts with `CanQuery` let on for that one
  synchronous measure (held weapons ignore rays). Read back: 99 to 100% of arc and orbit points outside the gun on
  all three weapons, where 9 slices and 12 directions left 14 of 548 inside the RevolverNew's hammer.
- **A bolt made of several Beams is ONE picture along every piece.** Each piece wore the gradient core -> edge
  along its own length, so the user saw every piece run white to yellow and snap back to white at the next, and the
  flat ribbons notch where they bend (2026-10-15). The `Bolt` template's texture (`make_bolt.py`: a white core in a
  soft yellow edge, the same all along) drawn white fixes both, on the weapon and on the arcs between bodies. Never
  put a gradient along a piece of something drawn in pieces.
- **An aura is wisps LOCKED to the blade, each layer twice**: the Astral Sword (a place the user sent) emits every
  texture on its blade twice, small at Brightness 6 in front of big at 0.1 to 0.3 behind, from an invisible box along
  the blade with `LockedToPart`, plus three Beams with scrolling textures. Picked on the blade: Blaze, Bloodlust and
  Shroud (`AuraTongue`, both layers); a scrolling ribbon (Mantle) lost. **Locked to the line, a wisp climbs ALONG
  it**, which is up a blade and sideways down a level barrel, and the three auras on the guns were one look in three
  colours: a gun has looks of its own (RuneDress `GUN_STYLES`), and a rune's look must differ in how it MOVES, not
  only in colour, on every kind of thing it goes in. **Lightning is drawn into the picture, never built from Beams
  joined in code**: five tries at that (straight pieces, fat pieces, thin forked pieces, a hundred small bends with a
  fade) all read as sticks or squares to the user, while every reference they sent was a drawn bolt swapped picture
  to picture. Tesla on a weapon is Strands (picked): `make_lightning.py`'s jagged strands on Beams up the blade,
  swapped many times a second, with its crackle flipbook on particles between them. **Size anything on a held weapon
  for first person**: strands 0.65 studs wide bowing 0.35 looked right from outside and stood well beside the blade a
  hand from the eye; and **fade both ends of a drawn strip** in the picture and on the Beam, or its start and stop
  show. Its floor impact is
  the reference for a big landing: a 60-stud flash for 0.05 s, shock rings growing 19.5 to 26 studs in 0.1 s, stars
  thrown at 35 to 65 with Drag 5 so they burst out and stop dead, crescents and a crack decal flat on the floor.
- **A sprite that lies along its flight** (`Orientation` VelocityParallel) is laid with its picture's RIGHT side
  along the flight. The kit drew them pointing up, and Frost's rising streaks came out as bars across the blade; the
  templates carry `Rotation` 90 for it.

- **The kit** is `Assets/effects/runes/` (`make_rune_sprites.py`, `make_rune_effects_rbxmx.py`, `README.md`
  with every id and number, `sheet.png` to look at): 21 crisp sprites and 22 templates under
  `ReplicatedStorage.Effects.Runes`, one lighting an element.
- **On a body**: `Client/Utils/RuneBodies.luau` is what STAYS (a pooled rig a marked body, 48 at most, the
  nearest first, only near the camera and in view), `Client/Utils/RuneLooks.luau` what happens once. Bench:
  `runebench`, switch `runestyle <kind> <name>`.
- **On a weapon or a worn piece**: `Client/Utils/RuneDress.luau`. A thing is a line with two ends and a look is
  written against the line, so one look serves the Sword, both revolvers and armour. Bench: `dressbench`,
  `dresshold`, `dressstyle`, `dressmix`.
- **The references** are `Assets/effects/runes/REFERENCES.md`. Only Megabonk is measured
  (`~/Projects/Megabonk/ExportedProject`, a Unity export whose prefab YAML gives count, life, size, speed,
  cone and colour over life a particle system): it is the reference on this machine for any crowd effect, the
  way Valheim is for nests. The rest of that file is from memory and says so.

What it taught:

- **Loud arrival, quiet stay.** Every reference spends its particles on the moment a status lands and keeps
  the lasting sign cheap. That is the look and the budget at once. Megabonk's hit is four layers, 20 to 35
  particles, all dead inside 0.9 s, no light.
- **Minting an Image needs no FBX** (section 7 said it did): upload the PNG as a Decal, and in a playtest
  `InsertService:LoadAsset(decalId)` gives the Decal whose `Texture` is the Image id. One `run_luau_live`
  resolved 21 at once.
- **An `.rbxmx` takes more than section 7 lists**: a ColorSequence of several keys, a NumberSequence with an
  envelope (the third number of a key), `Orientation` as a token (VelocityParallel = 2), FlipbookMode Loop = 0,
  NormalId Bottom = 4.
- **Tintable pixel art**: three lightness tones (1.0, 0.84, 0.62) lit from above-left, white under the clear
  texels. A mark that must read on a bright day is its stroke inside a rim a quarter as light at low
  `LightEmission`, not an additive glow.
- **An emitter cloned into a PART emits across the part's box**, and `ShapeStyle` Surface puts it on the faces:
  that is how rime and crystals sit on a body with no bone. A body is moved by its Root bone's Transform, so
  nothing parented to its part follows it; the rig is moved from `Components.CFrame`, and only when it changed.
- **`LockedToPart` with a Lifetime set a emit** stands a particle on a body for exactly as long as a state
  lasts; `Emitter:Clear()` takes it off early. A VelocityParallel sprite cannot stand still that way.
- **A body's Head bone is its neck, not its head.** A rig stood straight up off the feet put the curse's sign,
  the cold breath and the top of the ice behind and over a hunched Zombie's head (2026-10-15). RuneBodies now
  rides the Head bone through its clip, places the head and face from each head's real box measured off the
  `.bbmodel` (its `HEADS` table: the Zombie's head is 0.65 in front of the bone, the Charger's top 1.6 under the
  body's own top), and leans the body's box from the feet to the top of the head, turned with the body.
- **An emitter has no pull toward a point**, so "drawn inward" cannot be authored in a template.
- **`Acceleration` is world space**, so "rises" and "drips" hold however a blade is turned: emit near zero
  speed and let it pull.
- **`BlobBurst` overwrites a template's Color, Brightness and Size**, so a burst of a kit part needs the kit's
  tint passed in.
- **Two emitters that must be sized apart cannot share one emitter**: a flare that reused the steady flame's
  emitter resized the flames already in the air.
- **The held weapon is one model in both views**, so one dress is both. Keep effect parts OUT of the model
  (the visibility pass, the pack doll and the ground copy all walk it) and weld them from a Workspace folder.
- **A client part welded to a replicated thing needs its own exit** (the host's `AncestryChanged`): nothing
  else catches it before it falls when the host is taken away first.
- **A blade's Trail going `Enabled` is a free swing signal** on every client.
- **Keep a dress, switch it off; do not rebuild it** on every draw and stow (section 5).
- **Client weapon entities get their InstanceId after the equip hooks run**: a lookup by id in `HotbarEquip`
  needs a `task.defer`.
- **Probes**: one deleted about a second after `start_playtest` returned did not reach the play session.
  Have it print a first line and delete it once that line shows. A server Script's prints did not show in
  `get_playtest_output`; `run_luau_live` returning a string did. Zombies spawned beside the lord put the Core
  out in about 15 s and the world resets under the test.
- **One Studio, several sessions**: a `ServerStorage.StudioBusy` StringValue holding the session's name, made
  before a playtest or a write to the place and deleted after, kept four sessions off each other. Ending a turn
  does not wait for it; a `sleep` inside the turn does.

## 14. The cauldron and the orrery (built, unjudged)

Built 2026-10-16. The code is `Client/Utils/CauldronBody.luau`, `Client/Utils/RuneAltars.luau` and
`Client/Controllers/StationsController.luau`; the rules are `Shared/Core/StationsCore`. **Nobody has looked at any
of it yet**: a probe read counts and numbers in a playtest, never the picture.

- **The cauldron** is blocky cast iron over a coal fire, full of lava that heaves, drifts crust and pops bubbles,
  with the rune kit's `Flame`, `Ember`, `Smoke` and `Glint` cloned onto it (no new sprites). A melt is throw (0.62 s,
  rising then dropping in), splash (molten drops, embers, sparks, a ring, the light flashing), boil (sinks, goes to
  lava colour and then to light) and payout (a column of the thing's rarity, coins and XP shards thrown out, hung and
  pulled into him on UI.md 5j's closing gaps, the coin readout withheld and paid per landing).
- **The orrery is three forms on a bench** (`stationbench`, and `runestation <form>` sets the courtyard's): the
  Orrery (brass rings turning round the weapon over a stepped plinth), the Moonwell (a basin of starlight with six
  rim stones) and the Standing Stones (six runestones beaming into a floating slab). All three share the set:
  the rune's slate flies out of the tile into its socket, the form charges for 0.6 s while the coins leave him,
  and the strike lights the weapon in the rune's colour with a flash, sparks, a ring and a shake. Delete the two
  that lose and both commands once one is picked.
- **A rune is a stone** (`Models.Drops.Runes.<Name>`, cloned by `Client/Utils/RuneGlyphs.Stone`): a Blockbench
  model in the zombies' painting with its Elder Futhark mark standing out of both faces, its strokes glowing through
  an emissive mask (Models.md §12). It was Neon Parts built in code until 2026-10-19; `RuneGlyphs.Cut` still carves
  a mark into the altars that way. Its colours moved out of RuneDress into `Client/Utils/RuneColors`, one table for
  the weapon dress, the stone and the socket.
- **The user's second round (2026-10-17)**, each a rule for the next station:
  - **Pay out in the game's own coins and shards** (`Models.Drops.Coin` / `Shard`, moved by their `MoveJoint`
    and tinted copper, silver or gold off `CoinsCore`), never a lookalike part.
  - **Show a thing the way the gift and the forge do** (`Utils/Reveal`: the hotbar's picture turned to the eye,
    slammed onto its mark, a fan of its rarity), and **never resize a thing** to throw it or show it. A thing
    thrown into the pot leaves his hands under the view at its own size.
  - **A station sleeps with the Core and wakes when the ring of life reaches it** (LIFE_DELAY + distance /
    LIFE_SPEED): the cauldron's coals catch and the lava rises up the pot and brims; the Orrery's lines catch
    course by course and its rings are flung up off the plinth; the Moonwell fills with starlight; the Stones open
    their eyes and lift the slab. Sleeping plays it backward.
  - **At a station he does nothing else**: feet held (`SetImmobile`) and hands taken (`Snatch.TakeHands`), which
    stops weapons, specials, parry, slot changes and the pack.
  - **A bench steps its forms exactly as the world does.** The first `stationbench` never stepped them, so the
    Orrery's rings were never placed and the user saw an Orrery without its rings.
- **The third round (2026-10-17)**:
  - **Light that leaves is drawn in, never cut.** Destroying the weapon's model killed its fan of rays in the
    air. A weapon leaving now `PullIn`s its fans over 0.5 s, fades, and is taken down only once the light is home
    (measured: 7, 5, 4, then 0 beams over 0.48 s).
  - **The fans are the runes' colours**, one fan a rune, the light shared between them, crossfading when a rune
    goes in or out; the rarity's own with none. And **the copy in the orrery wears the runes' dress**
    (`RuneDress.OnModel`), flaring on the strike, while the dress on the weapon in his own hands is hidden for as
    long as his hands are taken (`RuneDress.SetHandsParked`, called by `Snatch.TakeHands`, so a gift does it too).
  - **A tile is built once for its key**, so a socket's key carries what is in it; a socket keyed by its place
    alone kept drawing OPEN after a rune went in.
  - **He steps up to it** on the sword pull's curve (wind back, drive past, settle), turned to face it.
- **Owed**: no sound of their own (material, coin, XP and charge cues are borrowed), parts rather than authored
  models, and the screen's own entrance and card have not been seen.

## 15. Anime Zombie Survival: the enemy bursts are ANIME, not pixel (built 2026-10-23, colours 2026-10-24, unjudged)

This game's look is anime (GDD 9). The enemy bursts KEEP BeACastleLord's layers, roles, numbers and LADDER (its port
of Guns N Goblins, `~/Projects/Guns N Goblins/audio/manifest-overkill-vfx.md`) and redraw every sprite the anime way: a
crisp shape, a white-hot core, a soft glow.

**How every piece was made, and how to remake it, is `Assets/effects/anime/README.md`** (the files, every image id in
`images.json`, the step-by-step mint and swap). The scripts are deterministic: run unchanged they reproduce the
minted PNGs and the uploaded `.rbxmx` byte for byte.

| ours | when | layers | was (BeACastleLord) |
|---|---|---|---|
| `AnimeHit` | every hit in view, AND every killing blow | `Flash` (1 violet flare, 5.5 shrinking to 31%), `FlashCore` (1 white), `Streaks` (12), `Embers` (10) | `EnemyHit`: Glow, Flicks, Puff |
| `AnimeVanish` | a killed body that cannot fall (blast kill with killer 0, past `MAX_CORPSES`), over the hit | `Smoke` (12) | `EnemyVanish`'s grey puff |
| `AnimeOverkill` | a killing blow worth 4x the body's max health: it comes apart, no corpse, no hit burst | `Flash`, `FlashCore`, `Ring` (the shockwave), `Embers` (15), `Blood` (20), `BloodSpray` (25) | `Overkill`: Puff, Burst, Drops, Spray |

- **A kill is NOT bigger than a hit** (2026-10-24). The first ladder gave every kill its own big burst with the
  shockwave and blood, and the user read it as the effects "scaling with how much health the zombie has left". In
  BeACastleLord the killing blow shows the same burst as any hit and the body falls; only an overkill is big. The
  server decides it (`EnemiesService`, `OVERKILL_DAMAGE_RATIO` 4, a volley against its toughest body) and the kill
  events carry it, since only the server knows the max health a round's scale gave the body.
- **The sound does not change on an overkill**: BeACastleLord plays the same blow, gore and bass as any kill
  (`playKillSounds`); the wipe layers still count it.
- **The first cut lost (2026-10-23): flat white sticker shapes** (spiky stars, a crescent slash, a cutout cel cloud,
  sparkles). The user: "too cartoonish instead of anime". A flat solid polygon reads as a cartoon sticker; anime light
  is a hairline ray and a white-hot core in a soft bloom. Do not bring the stars back.
- **Sprites** (`Assets/effects/anime/make_anime_sprites.py`, supersampled shapes, smooth glows, white so they tint): `flare` (2x2, a hot core
  in a bloom crossed by four long hairline rays and a few short ones), `streak` (a hairline core in a soft glow, laid
  along the picture's RIGHT for VelocityParallel), `ember` (4x4 one-shot: a flame tongue with a white core, torn into
  glowing squares that scatter and shrink: the pixel kit's chunk-into-squares, smooth), `blood` (2x2 held: a spiky
  splash, a drop stretched to the right, flecks, a smear; flat crimson in two tones, never a glossy ball), `smoke`
  (4x4 one-shot: soft-rimmed billows banded from a lit top left, wisping into noise), `ring` (a sharp outer edge
  fading inward, thinning). Images: flare `128750342796317`, streak `75972998756629`, ember `74657911562135`, blood
  `115771781077239`, smoke `77140723392641`, ring `83931351819889`.
- **Two hues out of one tint**: the ember's core is lightness 1 and its body 0.62, and `Brightness` 1.4 pushes the core
  past the clamp, so a magenta tint draws a pink-white core in a magenta body.
- **Colour is chosen against the MAP, by measurement, and it is violet** (2026-10-24). The first palette was the pixel
  kit's gold and orange, and on the schoolyard's sand floor (246, 216, 150) the user saw it blend in.
  `Assets/effects/anime/measure_contrast.py` prints the CIELAB difference between a particle drawn over each floor and the bare floor
  (under ~25 blends in): the gold as shipped (fully additive) scored 24 on sand and 26 on concrete; violet and magenta
  at a quarter additive score 80-100 on sand and at least 59 on every floor. Even gold at a quarter additive only
  reaches 54 on sand: the light mode was half the problem and the hue the other half. Violet is the sand's complement
  and nothing on the map is near it. Blood is a deeper wine (140, 0, 42) so it holds on the red track (24 -> ~41).
  The bench's other colourways are Magenta and Cyan (cyan is the weakest, 36 on concrete). **Run it before choosing
  any effect colour for a new map**, with that map's floors.
- **Light is a QUARTER additive** (LightEmission 0.25) on the flash, streaks, ring and embers. Fully additive light on
  a bright floor clamps toward white and vanishes: every hue scored about 15 against concrete at LightEmission 1.
  Brightness stays near 1.2, since a violet pushed past the clamp turns pastel pink-white. The white-hot centre is its
  own layer, `FlashCore` (a small white flare at LightEmission 0.6 in front of the violet one). Blood and smoke are 0
  with a little LightInfluence, so they sit in the world.
- **Templates** are `Assets/effects/anime/make_anime_effects_rbxmx.py` (an `.rbxmx`, section 7's route), under `ReplicatedStorage.Effects` in the
  arena place. Counts per layer are `enemyImpacts.BURST_COUNTS`; everything else is on the templates.
- **Pooled as a ring of copies under `Workspace.Terrain`** (16 hit, 12 overkill, 12 vanish), where an attachment's
  Position is its world position, so there is no host part to move. A copy (`enemyImpacts.NewBurst`, a `TBurst`)
  keeps its emitters, their counts and their authored Sizes in parallel arrays, built once: a burst is a loop of `Emit`
  calls with no `FindFirstChild` and no lookup by name. Each copy is held for its template's longest Lifetime (read off
  the template); the ring is taken in order, so if the next copy is busy every copy is, and the burst is skipped. At
  most 4 hit bursts and 6 overkill/vanish bursts a frame, so a volley's hits never starve its kills. Sizes scale by
  the body's height against 5 studs in 0.25 steps, and a copy rewrites its Size sequences only when its step changes.
- **The hit path is one lookup**: `EnemiesController.hitPosition` returns the chest and the aim shape together, and a
  body parked out of view gets no shape and so no burst.
- **Bench**: the console's `vfxbench` (backquote opens it; `Debug/DebugVfxController`, Studio and test places only)
  stands three zombies (Violet, Magenta, Cyan colourways) looping three hits, a kill, a vanish and an overkill. A
  bench body cannot ragdoll, so a killed one is hidden until it comes back. Delete the losers, the colourway table and
  the bench once one is picked.
- **Checked**: an offline 2D simulation of the templates (shape and timing, not the engine), a composite of each tinted
  sprite over sand, concrete, lawn and track, the bench run through the console, and a server hit / kill / overkill /
  blast / volley run in a playtest with no errors. Nobody has seen it in the engine yet.

### Checking it in this place: what cost a round

- **`capture_screenshot` times out when Studio's window is off screen**, so nothing could be looked at in the engine.
  Look offline instead: composite each sprite tinted and blended as its template draws it (colour x Brightness,
  clamped; LightEmission between "over" and "add") onto the map's floor colours, and simulate a burst's particles
  from the `.rbxmx` for shape and timing. Keep such a script beside the art in `Assets/effects/anime/`: the
  scratchpad is wiped between sessions, and the first simulation was lost with it.
- **A kill event goes only to the body's AOI subscribers**, so a server test that hears nothing may have killed bodies
  nobody was shown. Spawn them on the floor (raycast down at `Workspace.Arena`): a body spawned under it is removed
  by `EnemyMovementService`'s `OnFellOut` within a second. Wait out the spawn immunity (`Components.Immunity`)
  before `Damage`, or the blow does nothing. Then wrap `Network.Server.Enemies.Killed.FireList` and
  `KilledMultiple.Fire` INSIDE the same `run_luau_live` call and put them back at its end, and log the overkill flag.
- **The console can be driven from a probe**: `require(ReplicatedStorage.Packages.conch).execute("vfxbench")` runs a
  command as if typed; the console's ScreenGui is `PlayerGui["Command Executor"]` once the server granted a role.
- **An image is minted by uploading the PNG as a Decal** and reading `InsertService:LoadAsset(decalId)`'s Decal
  `Texture` in a playtest (section 13); an edit-mode `insert_model` of the decal does not show its `Texture`. A
  template `.rbxmx` uploads as a Model with `content_type = "model/x-rbxm"`.
- **Studio may have been reopened** between turns: `list_studios` again, and check the place still holds the templates
  (it was saved) before replacing them. Replace only the templates that changed.

## 16. Kill coins: thrown, hung, pulled in (built 2026-10-24, unjudged)

`Client/Controllers/CoinsController.luau`, the flight in `Client/Utils/coinFlight.luau`, flown headless by
`tools/lune/coins.luau`. Section 11's launch, hang and pull, for a stream of small things.

- **The pull is a magnet, not a timed curve.** A curve laid over a fixed time from the kill to him made a coin WAIT
  when he walked toward it (the user: "it looks strange"). The coin is steered at his chest THIS frame, at a speed
  that only grows (`PULL_ACCEL`, harder for a longer trip), with a turn rate that grows so the carry bends into a
  lock without orbiting. Within `NEAR_STUDS` the hang is cut to 30%. Walking in from 12 studs lands a kill's coins
  at 0.50-0.57 s against 0.80-1.03 standing; 4 to 90 studs takes 0.45 to 1.45 s. Hang about 1.5 studs a second,
  peak 35 to 200.
- **It arcs OVER the crowd** (2026-10-24: straight in, the coins went through the zombies and were lost in them).
  The pull aims `ARC_SHARE` of the remaining ground distance above him (up to `ARC_MAX_STUDS`) and leaves already
  rising (`LIFT_SPEED`), so the aim point sinks into his chest as it closes and the coin drops into him. Measured:
  at least 6.7 studs up wherever it is over the crowd (a head is at 5.1), the top 8 studs on a 12-stud trip and 14
  on a 90-stud one; the landing times barely moved.
- **Thrown AWAY from him**, over a 200-degree fan, and the pull carries on that way by a share of the trip before
  it turns: a coin at his feet does not swing out wide.
- **The landings are placed**: hang ends on closing gaps (`HANG_FIRST`, `HANG_SPREAD`, `order^0.8`), shuffled
  apart from the throw angle, so a kill pays out as a rattle speeding up.
- **The Gold lands with the coins.** The HUD shows Gold minus `CoinsController.PendingGold`, and each landing puts
  its coin's share on in one tick with the counter's pulse. The server fires a kill's Gold and Coins together, so
  one never arrives without the other.
- **A rising pitch**: landings closer than 0.45 s apart climb 1% a step (the user's number), up to 14 steps (`SoundsCore.PlayPooled`'s
  `playbackSpeed`).
- **Colour is amber at a quarter additive** (39 on sand, at least that on every floor); the old gold at full
  additive scored 17 on sand. The trail is two FaceCamera Trails, a white-hot core inside an amber glow, so the
  tumble cannot twist them; the wake is `flare` glints; the kill pops `streak`s and a `flare`. The landing has NO effect
  of its own: a ring closing in on his chest was cut (the user: an effect on his head that does not read as the
  coins). The trail, the sound and the counter's tick are the arrival.
- **A landed coin is hidden and kept `RETIRE_SECONDS`** before it returns to the pool, so its trail fades where it
  was (section 6). Trails are cleared and enabled only after the coin is placed, or they draw a ribbon from the
  parking spot.
- **Checked**: the flight in `lune`, and coins fired at the player in a playtest with no errors. Nobody has SEEN it
  yet: the trail width under FaceCamera while tumbling is the first thing to look at.

## 16. Ground warnings: on the floor that gets hit, every shape one language (built 2026-10-24, unjudged)

`TelegraphController` (client), `TelegraphCore` (both sides), `EnemyAttacksService` (server), textures in
`Assets/effects/telegraphs/` (its README). The bench is the console's `telebench`.

**The bug it fixes: a warning was one flat disc at the caster's height.** The Easy map has floors at 4, 5 and 6 studs,
inside the ±6 a ground AoE reached, so a slam on the ground hurt a player on a 5-stud deck while its disc lay under
the deck, out of sight; and a disc reaching a stair cut through the treads.

**How other games do it, and what was taken.** Engines with projected decals (Unreal, Unigine) project a box onto
everything in it, and the forums are full of the same bleed onto stairs and floors below; the fixes are excluding
meshes from decals or a mesh decal that hugs the one surface. Roblox has no projected decal, so a warning here IS the
mesh-decal fix: flat pieces laid on exactly the floors it covers. WildStar's telegraphs (the reference for readable
ground AoE) are three layers, a border, a background and a FILL whose growth is the timer, red for hostile, one shape
language held everywhere; its players' complaints were edges they could not judge and overlaps. FFXIV's orange
markers snapshot when the marker goes, and orange on an orange floor was a standing complaint, which is this map's red
track. Sources: greenyneko.com "WildStar's Legacy: The Telegraph-based Combat System", the WildStar wiki's Combat
page, Unreal forum threads on limiting a decal to the ground.

- **What it covers is a FLOOD, not a height band.** From the nav node under the centre, out over links whose step is
  at most `ArenaCore.MAX_STEP` and whose cell touches the shape, capped at ±`TelegraphCore.HEIGHT`. It runs up a stair,
  stops at a wall (no link), never climbs onto a deck or drops off one. The server hits feet whose node is in it and
  whose point is in the shape; the client draws its pieces on the same nodes from its OWN bake of the map (the arena is
  a Persistent model so a streaming client holds all of it). `tools/lune/sim.luau` checks the cases: ground under a
  deck yes and the deck no, treads within ±6 yes, past a wall no, a line stopped by the wall.
- **Pieces, not one part.** The picture's extent is cut into cells (the nav grid's own when the shape is not turned,
  1-stud cells when it is), each kept at every covered floor under it, and from each unused floor a rectangle grows
  in all four directions over cells at that height (within 0.3: the map's slabs differ by tenths) OR outside the shape,
  where the picture is clear anyway. So on open ground a warning is ONE piece and every seam is a real wall, step or
  ledge. The user saw the first cut (rows merged only to the right and down, so a circle was a stack of strips) and
  rejected it on sight: "torn to pieces", the joins visible even with the slices right. Each piece is a Part with a Top Texture showing its slice of the
  picture by `StudsPerTile` and `OffsetStuds`. **A Texture tiles**: a piece must never be wider than the picture it
  shows, so the body's pieces stay inside the picture's extent, and the growing fill (the sweep) sits on its own
  pieces, each cut to the sweep's current extent every frame. A 0.05 merge tolerance cost ~40 pieces a warning.
- **A warning lies on what is SEEN, not on what is walked.** The nav grid only sees parts it can query, and the map's
  trim (the stadium's track, grass, mown stripes and lines: thin flat parts with CanQuery off, laid 0.1-0.4 above the
  slab enemies walk on) is invisible to it, so a warning on the walk floor was drawn under the pitch and could not be
  seen (2026-10-24). The client's bake stamps every thin flat trim part onto the nodes it lies on (`skin`), and the
  pieces sit on that top. Hitting still uses the walk floor: trim is never floor.
- **The look** (measured, not picked): the colour is a magenta-red (255, 30, 110), brightened past 1 through the
  Texture's `Color3`. Red scores 13 on the track (it vanishes), violet is the hits' colour, magenta-red scores 22 on
  the track as a fill and much more as a rim; the rim also carries a dark stroke drawn into the texture, which no tint
  can wash out. The fill is densest at the edge, where a player reads the boundary. The sweep's wash is 0.44 opaque
  (`SWEEP_OPACITY` takes 20% off its transparency: the user found 0.30 too faint).
- **A boss's warnings are purple** (`BOSS_COLOR`, 0.6, 0.15, 1.5; the user asked for purple so the heavier hit reads
  as different), and they throb deeper (`BOSS_GLOW_PULSE`). Measured like the rest: 60 on the track as a fill against
  magenta-red's 30, and a deltaE of 30 from magenta-red on every floor, so the two never read as one colour.
- **Two warnings of one class never land on each other** (`enemiesUpdate`'s `isAreaTaken`, `TelegraphCore.IsOnTopOf`):
  an ordinary enemy whose warning would have its centre or its target inside another ordinary one still winding up,
  or would cover that one's centre, does not start it; it tries again each tick, so it goes once the player steps out
  or the first lands. A boss's warnings are a class of their own, so a zombie may still strike inside one. Stacked
  warnings read as one and hide the second hit (the user, 2026-10-24); in the sim 68 of 89 such starts stacked
  before this, none after.
- **The motion** (`Tune`): lands 18% too big and settles in 0.14 s (the eye catches what moves as it appears); the
  glow pulses from 1.5 Hz to 7 Hz as the hit nears; the last 0.18 s heats toward white; the sweep fills from the anchor
  (centre, apex, or a line's start) linearly, so it is FULL exactly when the hit lands; the hit is a white-hot flash
  that swells 7% and fades in 0.32 s; a warning taken back (a killed exploder) greys out in 0.22 s instead, so a cancel
  never reads as a hit. **A fill means "this lands when it is full"**, so a shockwave, which does not land then, never
  fills during its wind-up: it shows its outline alone, then the Ring front rolls out as the fill, and the front is
  what hurts. (It used to fill, then roll: the user read a full circle that did nothing, then a second that hurt.)
- **Shapes are data**: a Slam's `Shape` (`Circle`, `Cone` with `Angle` 60/90/120, `Line` with `Width`), Explode is a
  circle, Shockwave a ring. A cone or a line starts at the body and points where it faces. An angle with no texture
  snaps to the nearest on both sides (`TelegraphCore.ConeAngle`), so a typo still draws what hits.
- **Cost**: a warning builds once (the r40 shockwave, the worst, in 3.3 ms on the Easy map), then writes a few Texture
  properties a piece a frame. Pieces are pooled (256 kept).
- **Explode now resolves at its warning**, not where its body was knocked to during the fuse: the warning is the
  hitbox.
- **Checked**: the footprint cases headless, a playtest with the bench up (client and server bakes agree, 17,416
  nodes; piece counts rise and fall with the cycle; no errors), and a server Slam / Cone / Line through
  `EnemyAttacksService.Start`.
- **How a Top-face Texture lays its picture is not documented** (where it is anchored, which way U and V run, which
  way an offset moves it), and two guesses from screenshots were both wrong: each drew every piece's slice flipped, a
  circle as stacked strips with the rim bent outward, a cone as a sawtooth. It was read off a calibration row in play
  (16 numbered circles cut 3 x 3, one per convention; the user named the one that was whole): **a Top-face Texture is
  anchored at the part's +X +Z corner, U runs toward -X, V toward -Z, and OffsetStuds adds**, so the picture's top is
  the part's +Z. `Assets/effects/telegraphs/check_mapping.py` simulates exactly that; run it after touching
  `mapTexture`. When an engine fact cannot be looked up or screenshotted, build the row of candidates and ask for the
  number: it took one round, where guessing from screenshots took two and was wrong both times.

## 17. Last Wave: the Aura's pulse (built 2026-11-09, pixel style picked 2026-11-09)

`src/Survivors/Client/Weapons/AuraClient.luau` (`getPulseRig`, `PlayPulse`); the kit is `Assets/effects/aura/` (its
README). Before it, every pulse emitted 50 of Roblox's default `sparkles_main` from the disc's box at speed 32, under
the disc decals' red flash.

- **Pixel, not smooth.** A smooth version (soft glow ring, hairline sparks) was benched beside the pixel one; the user
  picked pixel because the game and its UI are retro. The smooth sprites, template and switch are deleted.
- **A particle's `Size` is HALF its drawn width.** Measured on the aura: a ring of Size 20.6 drew 41 studs across,
  twice the disc. The user caught it as "the shockwave is outside the aura ring". Every flat sprite here is authored
  at Size 0.5 for a 1-stud diameter, and the code multiplies that by the diameter it draws at.
- **The texel grid is the disc decal's.** The decal is a 64-texel circle, the pulse's ring and fill are 64-texel
  frames at the disc's size, so their texels lie on the decal's. Sheets for things that reach past the disc (1.6-2.1
  times it) are 128 texels, which keeps their texel within 20% of the disc's.
- **Motion is drawn, never done by resizing or fading.** A growing particle grows its texels and an alpha fade is not
  pixel art, so the ring rolls out over a 16-frame one-shot flipbook at a fixed Size, and the fill and every ending
  break up through a 4x4 Bayer dither. Originals sit at one pixel a texel in `src/` (section 8.3).
- **Four layers, each with one job.** `Ring` rolls out and lands on the rim; `Fill` flashes over the disc (the HIT);
  `RimSparks` leave the rim 0.07 s in; `Motes` rise after so it does not end on the frame it lands.
- **Everything scales with the Size stat**, read off the disc as drawn (a Size upgrade tweens it): Ring and Fill
  with the diameter, sparks and motes (size and speed) with its square root, counts per stud of diameter.
- **A single sprite that IS the effect (a ring, a flash) is emitted with `:Emit(1)` when the Particles setting is
  above 0, not through `ParticleHelper.Emit`**: that rounds a scaled 1 up only some of the time, so at 50% half the
  pulses would draw no ring.
- **Tints are not the disc's pure colours.** A pure red has no green or blue for Brightness to push, so its core can
  never burn pale; the pulse uses (255, 64, 46), resonance (255, 140, 20), Singularity (128, 46, 255).
- **Not seen yet**: whether `Disc` + `Surface` + `Outward` puts the rim sparks on the rim flying out in the ground's
  plane. The docs do not say which plane a Disc lies in or which way it emits. The abilities avoid the question
  (section 18).

## 18. Last Wave: the Aura's four abilities (built 2026-11-09; Slam, Field, Echo, Collapse picked; unseen by an agent)

`src/Survivors/Client/Weapons/AuraAbilityFx.luau`, called from AuraClient's ability hooks; templates in
`ReplicatedStorage.Effects.AuraAbilities` (`Flat` lying on the ground, `Volume` rising out of a box, `ShellMesh` and
`ShellSkin`); the kit is `Assets/effects/aura/` (its README). Before it, each ability emitted 75-200 default sparkles,
and Shockwave and Singularity's end grew a smooth sphere (`VisualEffects.ShowExplosionEffect`).

- **An ability is a list of beats**: a layer, when (seconds in, or seconds before the end), where, how big (times
  the Size stat) and the tint. A variant was another list over the same layers, so benching two per ability cost a
  few lines each, not a new effect. Picked on the bench (2026-11-09): **Shockwave Slam** (flash, shell, wave, dust,
  shards) over Quake (glowing ground cracks and an aftershock wave); **Magnetism Field** (a ring closing with field
  lines sliding in) over Vortex (four arms twisting inward); **Resonance Echo** (every pulse rolls a second ring out
  behind it) over Hum (embers rising off the aura); **Singularity Collapse** (the vortex falls in 0.35 s before the
  end and the blast throws a second wave past it) over Vortex (the same without the collapse). The losers' sheets
  (cracks, swirl), templates and the `aurafx` switch are deleted; the bench stays, one disc per ability.
- **Match the server's numbers, not the description.** Damage reaches Size / 1.9 as a radius, so the aura's own
  damage diameter is 1.05 x Size. Shockwave sweeps out to 1.5 times that over 0.5 s, LINEARLY, so its sheet's front
  travels at an even speed and lands on its edge at frame 11 of 16, and its lifetime is 0.5 x 16 / 11 (x Duration).
  Magnetism captures at twice the reach, pulls for 1 s, freezes, and releases at 3.5 s. Singularity's blast is the
  doubled Size's reach. Everything the server stretches by the Duration passive, the beats stretch too.
- **Where a beat lives follows what the server does there.** `Aura`: rides the disc (a `LockedToPart` copy of the
  layer on an attachment on it), for everything the server centres on the player (flashes, the chord, the
  Singularity's gather, vortex and blast, the release burst). `Cast`: stays where it was cast, for what the server pins
  there: the Shockwave's sweep (its centre is fixed at the cast) and the Magnetism pull (its target is fixed). `Here`:
  stays where the aura is when the beat fires: the freeze, which holds enemies where they stand. Each flat layer is
  cloned twice per rig, once world-fixed on an invisible anchored part in `Temporal` (moved to the spot first),
  once locked to the disc. Rising layers always stay where they rose from. The user asked whether everything should
  ride the aura: a world-fixed beat is there because the damage is; moving the visual alone would lie.
- **Rising layers use a Box, never a Disc.** A box emits straight along its `EmissionDirection`; a Disc's plane and
  direction are undocumented and unseen. The box is the square inside the beat's circle (0.7 of the diameter).
- **Radial things are drawn into the sheet**, not thrown as particles: the shockwave's speed lines and debris, the
  magnet's field lines, the frost's crystals. One flat particle each, exact, and no question of which way a shape
  emits.
- **A loop the length of an ability** (Singularity's vortex) is ONE particle with a looping flipbook and the
  ability's lifetime, cleared with `ParticleEmitter:Clear()` when it stops.
- **The shell: a low-poly sphere, not a smooth one.** The user wanted the old sphere kept, in the retro style. It is
  an 80-face icosphere (`make_aura_shell_mesh.py`, each face its own normal, so the scene lights it in flat facets),
  tinted and 45% see-through, centred on the ground so only its dome shows. It moves the way a sprite animates: size
  and fade change in hard steps, 12 a second, never smoothly. Shockwave's swells at the server's even speed to the
  wave's reach (5 to 32 studs over 0.5 s at Size 20, read back in a playtest). One shell per aura, out of the world
  (Parent nil) between swells, so it costs nothing at rest. A `.glb` uploads as a Model with `content_type =
  "model/gltf-binary"` and inserts as Model > Model > MeshPart at its authored size.
- **A scrolling `Texture` dresses it** (the user's idea): five Textures (no bottom), a 16-texel tile of dithered bands
  at 5 studs a tile, so the texel stays the disc's however big the shell gets. `OffsetStudsV` moves a whole texel at
  a time, so the bands climb in steps. `Color3` above 1 brightens a Texture the way it does a Decal (1.8 x the tint).
  Not seen: which way a negative `OffsetStudsV` moves on each face (the code assumes up).
- **Game time.** Every timer or step an effect runs from its own Heartbeat (pending beats, the shell's steps, the
  pulse's rim delay, the bench) multiplies dt by `TimeCore.TimeScale`, so a pause or slow motion holds them in step
  with the server's timers. A weapon's `Update` already gets a scaled dt from `WeaponsController`. A sustained
  emitter (Singularity's embers) takes `ParticleEmitter.TimeScale` from it each frame it runs; one-shot particles
  already in flight are not slowed.
- **Weapon Opacity covers the effects.** `applyWeaponOpacity` only reaches the BaseParts and Decals in the weapon's
  model, so the pulse and every ability layer apply the same rule themselves: `1 - (1 - base) x opacity` on each
  layer's authored Transparency (the shell, its Textures, every particle's sequence), read from
  `SettingsController` and kept current by `OnNumberChanged` (which also fires when saved settings load). At 0 they
  emit nothing. The pulse rebuilds its sequences only when the setting changes.
- **Cost**: abilities are seconds apart, so sequences are rebuilt per beat and a pending beat is a small record. One
  flat particle per beat, 10-24 rising ones scaled by sqrt(Size / 20) through `ParticleHelper`. Per aura that has
  used an ability: three parts (two invisible anchors and the shell, out of the world at rest) and about 20 emitters.
  One Heartbeat while anything is pending, disconnected when nothing is.
- **Testing on a clean map**: `flat` regenerates the map with no hills (again for hills), through the same path a
  restart uses, so the enemy actors, props, terrain and minimap all follow; `props clear` takes every prop off. The
  client hears of a mass clear through the `PropsCleared` attribute on `Workspace.Map`. Both read back in a
  playtest: 400 cells at one height on server and client; 0 props, 0 interactables, 0 entities after a clear.
- **Not seen by an agent**: Studio's window was off screen all session, so `capture_screenshot` timed out; the user
  judged it on the bench.

### Resonance's ring (2026-11-16, built, unseen by the user)

Resonance was close to a non-ability (a 25% chance per hit to share 40% of the pulse with the nearest enemy, which the aura
was usually already hitting, and nothing on screen said so). It now strikes a ring out to 1.5 times the aura's damage
radius on every pulse for 50% damage (`AuraShared.RESONANCE_*`), and the art says exactly that:

- **The echo is drawn to the server's ring, not the disc.** Its sheet (`echo`, 96 texels for the reach plus a drawn
  2-texel gutter) starts at the aura's rim and lands on the reach; AuraClient sizes it at `2 / 1.9 x 1.5` times the disc,
  the same sum AuraAbilityFx's `RESONANCE_RING` uses for the cast. The old echo re-rolled the pulse's ring at the disc's
  size, which told the player nothing.
- **It runs on from the pulse.** It is emitted when the pulse's ring lands on the rim (the Ring's lifetime x 8 / 16, read
  off the template), so the pulse reads as one wave carrying past the aura.
- **Tines point back in from the reach**: section 6's "draw nothing past where a hit reaches".
- **The cast shows the reach at once**: a cast `Echo` at the ring's diameter as the chord's first ring lands (0.22 s).
- **Cost on the server, measured** (a live probe, 1,000 Slimes around the player): one extra QueryRadius and one batched
  DamageMultiple per pulse, never a search per enemy. The pulse hit 649 and the ring 286 others, none twice, at
  exactly half the damage; a pulse took 0.22-0.48 ms without Resonance and 0.37-0.75 ms with it, only while it is up.
  The client draws one sprite per pulse.
- **Not seen**: the echo in game. Its sheet was previewed offline (orange on grass green). The ring's landing sound
  (`AuraResonanceRing`, round 4 D) lands with the echo's front, not with its emit, since the pick was heard on that
  beat (Sounds.md).

### Scrolling Textures on many things (the enemy telegraph question)

A `Texture` is a decal-like surface: one extra textured draw per face it is on, and scrolling it means a Lua write to
`OffsetStudsU/V` per Texture per step. On one shell per aura that is nothing. For telegraphs, what counts is how many
are ON SCREEN AT ONCE, not how many enemies exist: a few dozen scrolling Textures stepped 12 times a second is a few
hundred writes a second. Hundreds at once is where it starts to cost, and the price was not measured (a benchmark
probe was written, 100 and 1000 Textures scrolled every frame, but the playtest would not start; run it before
deciding). Where many must animate at once, keep the motion off Lua: a `ParticleEmitter` flipbook (the engine plays
the frames; this is what every aura layer does), or a `Beam` with `TextureSpeed` (the engine scrolls its texture). A
Texture that does not scroll costs what a Decal does.

## 19. Last Wave: the Revolver (built 2026-11-09, picked the same day; the gather picked 2026-11-12)

`src/Survivors/Client/Weapons/RevolverFx.luau`, called from RevolverClient (muzzle, reload, abilities, the Death Line)
and ProjectileController (every bullet, its hits, bounces and splits); templates in `ReplicatedStorage.Effects.RevolverFx`;
the kit is `Assets/effects/revolver/` (its README). Before it, a shot emitted six stock "firewings" emitters off the
model's `Revolver.Fire`, the bullet was a smooth white-to-red Trail, Dead Eye and Fragmentation were a sound each,
and the Death Line was two Neon boxes and a third for the sweep.

- **Picked on the bench** (three styles a piece): Shot **Slug** (a big star, a flame tongue, sparks, smoke, a small
  kick; a pop, sparks and smoke on the hit), Reload **Smoke** (the casings, a puff and a ring), Rapid Fire **Heat**
  (embers and smoke at the start and on every shot), Dead Eye **Reticle** (brackets lock on over the wielder; a glare
  at the muzzle and on every crit), Fragmentation **Prism** (a crystal hexagon that shatters, at the start, small at
  every muzzle, on every split), Death Line **Rings** (shock rings running down the ray). They lost, and were deleted
  with their sprites: Bang and Comet (lighter shots), Casings and Cylinder, Fan and Gatling, Glare and Mark, Shrapnel
  and Spark, Ray (no rings) and Storm (lightning arcs).
- **The gather is the Spiral** (picked 2026-11-12, over Ring, which came straight in). With it the last style went,
  and with it `RevolverFx.Styles`, `WithStyle` and `revolverstyle`: the bench rows are now Before | After only.
  Swirl and Whip (streaks from a whole sphere on the barrel's side, curving round the vertical) were replaced before
  that: the user wanted BeACastleLord's circle.
- **Nothing is drawn inside the gun.** The Fire attachment sits inside the barrel's end and the mesh is 3 studs long:
  a sprite centred on it is half inside the mesh. Every muzzle sprite is LED out along the shot (`FlashLead`,
  `ConeLead`, ...) and the muzzle templates carry a ZOffset of 2.5 to 3 so they draw over the gun. Ability moments are
  drawn at the Fire attachment or over it, never at the gun part's centre.
- **Shot kinds are tints**: gold the plain shot, crimson Dead Eye, cyan Fragmentation (`RevolverFx.ShotKind`), and
  **purple Blend when Dead Eye and Fragmentation are up together** (the user's idea): the round is the jagged splitter,
  its muzzle carries both the glare and the prism, its hits glare like a crit, its split and fragments are purple. A
  fragment's own event does not name its gun, so it takes the kind of the last splitting round fired.
- **Camera: BeACastleLord's recoil, not shakes.** The user found the shakes "a little bit insane" and liked that
  BeACastleLord's aim never moved and its recoil was neat. Its Revolver has no shake at all, only `CameraRecoil` (Up 5,
  Side 2.5 with a rolled sign, Freq 27, Damp 0.5, Roll 0.12), now a spring in CameraController (`AddRecoil`,
  `SetRecoilSpring`) that translates and rolls the rendered camera only, so the aim and the replicated camera never
  move. Rapid Fire's rounds are its fan (0.55 a round, the side rocking left and right), the Death Line's release its
  charged shot (2.4) plus one shake, BeACastleLord's boss pop (3, 0.1, 0.3 s), and each orb level a 0.35 notch.
- **The bullet is a Beam between two Terrain attachments**, its texture stretched once from tail to head, not a
  Trail: a Trail's ribbon smears and is not on a texel grid. A hit is drawn where the bullet is when the server ends it,
  if it is within 4 studs of its target; a bounce is a hit; a split is drawn once.
- **THE DEATH LINE IS A RAY, after the charge in BeACastleLord's Revolver** (its `Gather` and `Kindle`):
  - The floor keeps the telegraph (the kill and pull bands with chevrons, VFX.md 16's mapping), because the bands ARE
    the hit area; after the shot it keeps the scorch and its cinders.
  - **The gun is held out in front, on the line** (RevolverClient's Update, frozen once it fires). The Fire
    attachment sits off the Handle and turned on it, so a Handle looking down the aim left the barrel, and the ray,
    to one side ("a little to the side"). The pose is solved from the rig each frame (`onAimLine`): where the barrel
    would be, turned about its end onto the aim and slid sideways onto the line through the root. The ray also starts
    on the line's centre at the orb's height.
  - **The gather is BeACastleLord's charged shot.** The first version (a sphere of streaks 1.4 to 7 studs out) was
    rejected for coming "from the same place", the second (Swirl / Whip, curving round the vertical) for not circling
    into the gun like BeACastleLord's. Now: streaks start on a RING square to the aim (depth within 0.15 of the
    reach either way), so behind the wielder the circle faces the camera and every streak crosses the screen at full
    length; bearings go round it by the golden angle; 2 to 3 studs out, 2.2 times further at a full charge; 0.3 s of
    flight, creeping at the outside and whipping in (1 - t^2.4). **Only enough to draw the circle**: the rate is
    12 / flight (about 12 in the air at a full charge, a third of that at the start). **Paced to the shot**: a streak
    that could not land by the release even at 2.2x speed is not launched, so the ring closes as it fires. Each turns
    1.4 rad round the aim as it closes, all the same way (a curved Beam, the bezier on the path's tangents,
    BeACastleLord's GroundGlow convention). All on attachments on the gun part, so it rides the gun.
  - **The orb sits in front of the barrel and behind the body.** It was a 5-stud AlwaysOnTop billboard 1.2 studs out:
    over the gun and seen through the wielder. Now its centre is 1.9 studs past the barrel's end, the core sprite is
    2.6 studs and depth-tested, and round it is **the Aura's shell** (the user's idea: `AuraAbilities.ShellMesh` and
    its band skin, plus a bottom face since this one floats), 1.4 / 2 / 2.6 / 3.2 studs across at the four levels,
    swelling a step on each new level, its bands climbing a texel at a time 12 times a second. On the shot it bursts
    out over four frames with the orb's throw row.
  - **The shot**: the orb blows open, a big blast, the recoil and the pop shake, and the ray leaves along the line: two
    camera-facing Beams wrapped along it, a white core and a gold flow (four textures a quarter tile apart swapped 30
    times a second: a Beam has no texture offset to step). The wide dithered halo was cut: it read as a flat plane down
    the whole ray. It opens at twice its width and falls back in hard steps, then beats.
  - **It does not stand there, but it holds long enough to read.** The whole ray held for the 5.7 s sweep read as damage
    still being dealt behind the front; a 0.4 s hold then disappeared inside a swarm. It holds whole for 1.1 s, then its
    tail tears away down the line (sparks and smoke where it leaves) until it rides 160 studs behind the front as a
    lance. The server still hits the whole rectangle behind the front for the sweep (once an enemy).
  - **The pull bands close, they do not vanish.** They were unparented on the shot, and the user saw the side arrows
    go "on a snap". Now they close onto the kill band in five hard steps over 0.3 s, eaten from the outside in so
    every texel keeps its size (the width snapped to the picture's 64 columns, the right band's offset holding its
    picture against its moving +X anchor), their chevrons racing in at ten times the charge's speed, white-hot on
    the shot and cooling a step at a time, then slamming into the band's edges with a pop, sparks and dust 6, 18 and
    30 studs down the line. **Not seen**: whether the right band's offset holds (if its chevrons jump outward each
    step, flip the sign of `fullWidth - width` in `closePull`).
  - **The end is a break-up, not a cut**: the lance breaks into six segments, one going out every 0.09 s in a scattered
    order (a hard-edged Transparency sequence), each throwing sparks, a pop and smoke where it was, the rest thinning.
  - The ray is fixed in the world from where it was fired, like the server's hit rectangle, and level, so it passes
    through hills. **Not seen**: which way OffsetStuds moves the floor's chevrons.
  - **The release blasts round the wielder (2026-11-16, the user: damage "8 studs from the player", "a shockwave" on
    the shot, as juicy as it can be; then "24 studs instead of 8").** Server: everything within
    `DEATH_LINE_BLAST_RADIUS` (24, flat) takes the ray's
    damage once, loses the charge's Magnetized (it shares MagnetTarget with Repulsed and would drag the thrown enemy
    back) and is Repulsed away from the wielder (20 stacks x Knockback, 0.4 s, the Stomp's class). Its hits are marked
    in the sweep's hit set, so the ray does not hit them again or Stun them in place instead of flying. Client, all in
    `FireLine`, no new templates: **the Aura's Slam twice** (`AuraAbilityFx.Start` on two hidden discs in the line's
    folder, as the tutorial borrows it), a gold wave as wide as the hit and
    a white-hot core 0.3 as wide inside it, run at 0.45 / 0.25 of the Slam's time so the wave lands on the rim at
    0.225 s (at 8 studs it was 0.3 / 0.2 and 0.15 s; a 24-stud wave that fast reads as a pop); a big flash and ring,
    embers up and sparks out along the floor on eight bearings; on the rim when the wave lands, pops, sparks and dust
    on sixteen bearings (about 9 studs apart); a gold light on the floor, range 48, stepping out over 0.45 s (the ult:
    the flash palette allows it). **Sound**: `RevolverDeathLineBlast` (Sounds.md, Review/DeathRay round 2), a world
    cue at the feet under the release. `RingSizes` gives Sparks and Smoke 32 slots and Pop 24: at 12 the sweep's front and tail already kept them busy
    and the blast's would have been skipped. **Probed in a playtest (server only)**: an enemy 4 studs behind the aim,
    out of the ray, took the blast's damage, lost Magnetized, was Repulsed, not stunned, and was 7.7 studs off 0.4 s
    later (at the 8-stud radius). **Not seen by anyone**: the client side (the Slams, the rim, the light).
- **Budget**: a ring of 12 pooled attachments a burst template, a burst skipped when its next slot is busy, and only
  the properties that changed written. **Hits are capped at 8 a frame and skipped past 160 studs from the camera's
  focus.** Measured in Studio (server peer, 2000 runs): a hit costs about 3 us. Bullet rigs pooled. One Death Line per
  cast, built and destroyed with its streaks, orb and ray. **A stepped piece writes only on its step**: the orb's
  shell is about a dozen property writes (size, transparency, six textures' offset and transparency), so between its
  12-a-second steps only its CFrame follows the gun; the orb, its light and its shell show and hide through one cached
  flag rather than three writes a frame. Up to 16 streaks a frame cost 4 Rodrigues turns each, nothing next to that.
- **Lessons from this weapon, for the next one:**
  - **Measure the rig; never assume the Handle looks down the barrel.** The Revolver's `Fire` attachment sits at
    x = -1.3 on a 3-stud mesh (the barrel's end) and looks along the part's -X, while the gun hangs off the Handle with
    an offset and a 50-degree roll. "Point the Handle down the aim" left the barrel and the ray beside the line. Solve
    the pose from the rig: Part1 = Part0 * C0 * Transform * C1^-1, the attachment rigid on Part1.
  - **`AlwaysOnTop` draws through the wielder.** It was used to lift the orb over the gun's mesh; the user saw it
    through their own body. Move a sprite out past the mesh instead, and let it depth-test.
  - **A camera kick reads at Ballarc's distance with BeACastleLord's numbers.** A shot's kick (Up 5, Freq 27, Damp
    0.5) peaks at 0.10 stud, 45 ms after the shot: about half a degree at the 12.5-stud zoom, a small punch. The
    old Perlin shakes (up to magnitude 9) moved the whole view several studs and read as the aim being thrown.
  - **A charge's streaks are timed to the release** (a deadline), not only to a rate: otherwise the shot's flash cuts
    the last ones in half mid-air.
  - **Round 4 (2026-11-09) has not been played**: the recoil, the ring gather, the shell orb, the centred pose and the
    purple Blend were linted and compiled only; the playtest would not start (Studio minimized).

- **On the body (2026-11-12; previewed in ror, probed in a playtest, unseen by the user)**: templates
  `RevolverFx.Body`, specs `BODY` in RevolverFx, preview `tools/vfx/preview_revolver.py`. No new sprites: the kit's
  spark, smoke, glare and shard, the Aura's mote and the Greatshield's chevron.
  - **Rapid Fire**: heat embers, a little gun smoke and orange buff chevrons rise off the body while it fires.
  - **Dead Eye**: crimson glints wink on the body (flicker steps) over crimson heat, and the player's own outline
    blends to crimson while it lasts (`PlayerOutline`, below). The first build laid a second, Occluded Highlight over
    the body; the user pointed out every character already has an outline, so the ability recolours that one instead.
  - **Fragmentation**: cyan shards tumble up off the body and drop back.
  - **Blend**: while both are up, the Dead Eye and Fragmentation auras and the outline turn purple together
    (`tintBuffs`, on every start and stop), and go back to their own tints when one ends.
  - **Death Line**: gold heat rises off the body through the charge, its rate and a gold light stepping up with the
    orb's level (the only light of the kit's body pass: it is the ult). On the release the body flashes gold (Hit
    steps), the shooter's own screen takes the impact frame, and sparks and smoke blow back off the chest while the
    ray still leaves the gun (the muzzle flare already held there).
  - **The gun holds still through the ult** (2026-11-12, the user: the revolver "still goes to the sides that is
    shooting, making it lose the epic moment"). The auto-attack kept firing during the Death Line, and each shot ran
    the normal shot pose: it snapped the Handle's Transform toward its target, Update lerped it back onto the line,
    and with Rapid Fire up the shot welded the gun into the hand and Update stopped writing the pose. Now a shot
    while the Death Line is up (`deathLineVisuals[weapon]`) only fires: sound, muzzle, bullet, no pose, no kick, no
    clip; Rapid Fire's start leaves the pose alone, and Update keeps holding the gun out even while Rapid's shots are
    recent. **Not played**: linted and compiled only.
  - **Dead Eye's reticle was off-centre** (the user: the circle sits "a little at the top left" of the corners). A 32
    frame's centre is between texels (15.5), where `radial` centres the ring and the 2x2 dot; the brackets' corners
    were at 15.5 +- 6 = 9.5 and 21.5, and `plot` rounds a half up, so they landed on 10 and 22, a frame centred on 16.
    Redrawn with every piece on whole texels symmetric round 15.5 (corner offsets on half-texels, the lock's lines two
    texels wide like the dot); a check confirms frames 0 to 11 mirror exactly. Image 118385809378743.
  - Every aura ends on the ability's stop (AbilitiesController calls the handler again with the flag off), on death
    and when the gun is removed (`RevolverFx.EndBuffs`).
  - **In ror the first sizes were specks** (embers 0.35, glints 0.7, shards and motes 0.3): at the game's distance a
    body sprite under ~0.45 half-size disappears. Raised to embers 0.55, glints 1, shards and motes 0.45, still under
    the Shovel's ~1-stud cap.

- **The gun's own motion** (recoil spring, reload toss, cast flourish, orbit drift, the Death Line's strain) is
  `RevolverMotion.luau`, written up in Animations.md 15. It never touches the Handle joint while Rapid Fire's clips
  hold the gun.

## 20. Last Wave: the Boots (built 2026-11-10, picked 2026-11-10; unseen by an agent)

`src/Survivors/Client/Weapons/BootsFx.luau`, called from BootsClient (every step's shockwave and Momentum's echoes,
Shockdash, Momentum, Fault Line, Stampede); templates in `ReplicatedStorage.Effects.BootsFx` (`Burst`, `Ride`,
`Ground`); the kit is `Assets/effects/boots/` (its README). Before it, a step was a pooled Neon cylinder fading by
alpha, and every ability was `VisualEffects.ShowExplosionEffect` (a smooth sphere) in its own colour.

- **Each piece had three styles on a bench; the user picked one each** and the losers, their sprites (stomp, pillar,
  swath) and the style switch are gone. `bootsbench [piece]` now stands one runner a piece (a copy of your avatar,
  anchored, lapping a 9-stud circle at 20 studs a second), every piece side by side or only the one named, looping it
  at its real numbers with its sounds.
  - **Step: Gust** (wind arcs turning outward with speed lines). Its runner cycles the plain, Momentum and Stampede
    tints a lap at a time.
  - **Shockdash: Gale and Comet together**, as the user asked ("Gale shows more in the ground that covers the dash but
    I also like the little effects of Comet"): a gust laid on the floor every 4 studs of the dash at the hit's width,
    with Comet's speed lines and sparks shed off the feet; where it stops, a wide gust and sparks and speed lines
    thrown on ahead.
  - **Momentum: Streaks** (speed lines shed behind for the whole buff).
  - **Fault Line: Magma** (an orange tear, geysers out of it).
  - **Stampede: Dome** (the Aura's low-poly shell swelling gold over the wielder, cracks and rocks), dust and sparks
    kicked off the feet for the buff.
  - Rejected, for the record: Step Ring and Quake, Shockdash Comet alone, Swath and Gale alone, Momentum Wisps and
    Afterimage (Neon ghosts of the body), Fault Line Rift and Seismic, Stampede Herd and Pillar.
- **THE THIRD ABILITY IS NEW: Fault Line, replacing Chainstep.** Chainstep teleported between the five nearest
  enemies, which stopped the player's own running on the one weapon that is about running (the user: "it is bad and
  doesn't fit the boots because it stops movement by teleportation"). Fault Line tears the ground wherever the wielder
  runs for 3 s (x Duration), then the whole tear erupts from its first point to its last, hitting (3x Damage x
  AbilityDamage x the speed multiplier, read when it erupts) and slowing (4 stacks, 3 s) everything within
  `FAULT_HALF_WIDTH_MULT` x Size of it, once each. The run decides the shape: circling a pack draws a ring round it.
  - **Both sides draw the same tear.** `BootsShared.RecordFault` keeps a point every 2.5 studs (120 at most; a teleport
    breaks the tear instead of joining across it), and `FaultEruptSpeed` runs the eruption at 140 studs a second, or
    faster so a long tear still finishes in 0.6 s. The server records it in `BootsServer.Update` and erupts it the
    moment `IsAbilityThreeActive` goes false (on time, or cut by a stun or a down); the client does the same off the
    StopAbility hook, so the geysers run down the tear in step with the hits, with no Blink event.
  - The name is a new `EAbilitiesNames.BootsFaultLine = "Fault Line"`; `BootsChainstep` is gone. "Chainstep" stays in
    old saves' SeenNames, unused. Its sounds are `BootsFaultLine` (the tear opening) and `BootsFaultErupt` (three
    takes); Sounds.md has them.
- **The tear is drawn as wide as it will hit** (a strip per point, a `Texture` 16-texel tile at the strip's width), and
  pulses between two glows while it is open: a warning of real danger (section 3), the danger being to the enemies.
  Where the eruption passes, its strip goes white-hot and closes in hard steps. **Not seen**: whether the tile's
  zigzag carries on across strip joints (`OffsetStudsV`; if it jumps at every joint, flip its sign in `layTear`).
- **Sizes follow the server.** A stomp's sheet is drawn at the server's radius (Stampede's already x1.3); Shockdash's
  pieces at `DASH_RADIUS` x the Size ratio, its hit's half-width; Fault Line's at its half-width. Thrown things grow
  with sqrt(radius / 8), the base Size.
- **It steps itself**, on one Heartbeat on game time (`TimeCore.TimeScale`) that connects when something starts and
  disconnects when nothing runs, the way AuraAbilityFx does: BootsClient.Update and the bench never step it twice.
- **Budget**: rings of 24 pooled emitters a burst template (the eruption fires up to ~30 geysers a second); one Ride
  attachment per running sustain, destroyed 0.9 s after it stops. Measured on the bench (2026-11-10, a playtest
  probe counting every 3 s): attachments under Terrain grew as templates were first used and held flat (216-219, 288-291
  once the geysers and pillars were in), 69 tear strips for three 3-s tears all closed after the eruption, one shell per
  Dome (these counts were taken with every style still in). On the server, a 30-stud tear through a pack ran 14
  segment queries and hit three enemies once each, 0.05 s apart as the eruption travelled.

- **Every flat piece lies on the floor under it** (section 6): the stomp's sheets, the dash's gusts, the buffs'
  sheets, the Dome and every tear strip follow the slope or rock they are on (`groundAt`, one raycast per piece;
  Fault Line probes each point once, when it is recorded). Thrown things go along the normal too. Checked in a
  playtest on the map's slope parts (2026-11-11): a stomp's gust attachment came out facing the slope's normal to
  four decimals, 0.12 studs over it. The Aura's world-left layers, rising layers and shell now take the disc's tilt.

## 21. Last Wave: the Shovel (built 2026-11-10, picked 2026-11-11; abilities made lines; footprint Furrow; unseen by an agent)

`src/Survivors/Client/Weapons/ShovelFx.luau`, called from ShovelClient (every strike pass, its Earthshaker spikes and
Excavator lobs, the four abilities); templates in `ReplicatedStorage.Effects.ShovelFx` (`Burst`, `Ride`, `Ground`);
the kit is `Assets/effects/shovel/` (its README). Before it, a strike drew nothing but its sound and every ability was
`VisualEffects.ShowExplosionEffect` (a smooth sphere) in its own colour.

- **Each piece had three styles on a bench; the user picked** and the losers, the divot sprite, the unused templates
  (Divot, Quake, Geyser, Chunk) and the style switch are gone. `shovelbench [piece]` stands one cell a piece (a copy of
  your avatar with four shovels, the game's own pose) looping it at its real numbers with its sounds.
  - **Strike: Shock** (a wind ring and speed lines driven out of every shovel).
  - **Groundbreaker: Eruption** (spikes thrown up down every shovel's line, 0.03 s a step), now over a gold crack that
    glows until the last spike is up and closes in hard steps, a smack at each line's root and end.
  - **Earthshaker: Spikes** (spikes thrust up one after another down each strike's 25-stud line, rocking side to side),
    a smack and sparks where each line ends. Its cast throws a spike line out of every shovel at once.
  - **Whirlwind: all three together**, as the user asked: the Cyclone sheet turning under the wielder, and off every
    spinning shovel Gale's speed lines, Debris's clods and Cyclone's grit, each on its own attachment (each throws its
    own way). Each whirl strike draws a gust halfway down every shovel's line and another at its end.
  - **Excavator: Heap, thrown like Barrage** ("they are smoother"): the purple dome over a crater, and every shovel lobs
    an arc of earth down its line on the cast; every strike lobs clods 28 studs down every line, landing together with a
    thump. Heap's straight flying chunk is gone.
  - Rejected, for the record: Strike Clod and Crack, Groundbreaker Quake and Crater (round, the Aura's shape),
    Earthshaker Ripple and Fissure, Excavator Barrage's ring and Drill.
- **THE ABILITIES ARE LINES NOW** (the user: "differentiate the shovel more from the aura... in the early game each
  shovel counts only to the direction it is looking, like the basic attack but powerful"). `ShovelShared.LineOf(size,
  reachMult, widthMult)` gives a line from the wielder out along a shovel's facing; server and client both read it.
  - Groundbreaker: every shovel's line out to `FORMATION_RADIUS + REACH_MULT 5` x half a strike's length (30 studs at
    base Size), 1.5x a strike's width, 4x Damage x AbilityDamage, each enemy once per cast. It was one 3x-Size rectangle
    centred on each shovel (30 x 15 at base, reaching behind the wielder): a blob, not a line.
  - Whirlwind: every strike hits each spinning shovel's line where it points, out to 15 studs at base (`REACH_MULT 2`),
    a strike's width, each enemy once per strike. It was a full circle of radius 10 every strike. One shovel now sweeps
    instead of covering everything: a real loss early, by the user's design; many shovels close the ring.
  - Earthshaker's and Excavator's lines were already lines and are unchanged; Groundbreaker still runs them when their
    buff is up. The plain strike's hit is unchanged (a `length` x `width` rectangle centred on each shovel).
- **Sounds picked 2026-11-11** (`Assets/Sounds/Review/Shovel/README.md`): two new cues (`ShovelWhirlHit` on every
  whirl strike, `ShovelExcavatorLand`, which ShovelFx plays when the lobs land: Excavator strike A's heavy stone slam,
  four takes, after the user moved off C's Bass Hit) and two layers played with a kept cue
  (`ShovelGroundbreakerSpikes`, `ShovelExcavatorQuake`).
- **Every piece lies on the floor under it**, as the Boots' do (section 20): one raycast into `Workspace.Map` a piece
  (the feet from 2 over to 4 under them; a line's points round the last point's height, 6 over to 10 under, so a line
  climbs and drops with the ground). Flat sheets, crack strips, the cyclone sheet, the dome and the sustains face the
  normal; thrown things go along it. Spikes face the camera, so they stand straight up on any slope.
- **Every hit shows its rectangle** (the user: "the shovels attack in a rectangle and the effects of the basic attack
  are a circle... will it give a readable way on where is attacking and where does damage?"). Shock's ring was drawn
  `length` across over a `length` x `width` hit: twice the hit's width, and no edges. Now each strike lays its
  footprint (a Ground texture on a part the hit's exact size, both ends on the floor), and the ring is drawn `width`
  across so it stays inside. Each Whirlwind hit lays the footprint from the wielder out to `reach` on every blade's
  line, and its gusts are a width across, the tip's half a width in from the end. Footprints are pooled (a strike lays
  one per shovel every second).
- **The footprint is Furrow** (picked 2026-11-11, round 3): a trench ploughed out along the hit, lumpy soil ridges down
  both sides, clods, a heaped lip at the far end; it ploughs out from the wielder in four steps (0.1 s, flashing),
  holds to 0.2 s, then its tail chases it off the far end by 0.42 s, redrawn every 0.05 s and writing only what
  changed. Round 1 (a plain swipe sprite flashed 0.06 s then shut in three steps) lost: "it doesn't have any animations
  and it disappears in a snap". Round 2 (the same plain sprite moved four ways: Sweep, Stamp, Surge, Shut) lost: "I
  want the actual vfx variants to look different, not only the animations, I don't like how simple the current one
  looks". Round 3 lost, for the record: Slash (a blade's crescent at the far end, speed lines swept back, dashed side
  rails; slammed down from a third too big), Shatter (plates and glowing seams; cracked at once and settled), Arrows
  (chevrons and rails in a seamless tile run outward). **A look is chosen with its art, not its motion**: bench
  candidates that differ in what they draw, each with the motion that suits it. Their sprites, textures, the
  `ShovelFx.Styles` switch, `shovelstyle` and the bench's styled row are deleted.
- **Many shovels pile their footprints up at the feet** (the user: "they start from the character position... they all
  overlap when there are like 8 shovels"). That is where the hits really overlap: at 8 shovels the rectangles share
  the floor out to about 6.4 studs (8 x 5 studs of width round a 2 pi r ring). So the sprite thins out toward the
  wielder (`near_keep` in the sprite script: solid over the far half, a dither falling to 12% at the feet), and the
  far edge, the reach, is what reads.
- **Past base Size they pile up at the feet again** (the user: "when I have a lot of size passive the effects of the
  shovel basic attack start to overlap again on where the character is"). Each rectangle is centred on its shovel, 5
  studs out, so at 3x Size it reaches 10 studs back past the wielder and every shovel's sheet crosses the feet; the
  wind ring sat on the shovel at the full width (15 studs at 3x), so eight of them stacked there too. Now a strike is
  drawn from where it stops overlapping its neighbours (`width / 2 / tan(pi / count)` out, 0 for two shovels, the
  whole rectangle for one), but never from further out than half its far end (`Tune.StrikeClearShare`), and its ring
  sits in the middle of what is drawn, no wider than the spacing to its neighbours' rings there. 8 shovels at 3x Size:
  drawn 10 to 20 studs out, rings 10 across (were 15, at 5). **The hit itself is unchanged**: the drawing leaves out
  the part every shovel shares, where the wielder already stands.
- **Unseen: which way the Furrow lies.** `Tune.IsSpriteTopAtBack` (section 6) turns its part so the sprite's top row
  (the lip) is the far end; if the lip shows at the wielder's feet, set it false.
- **Groundbreaker's spikes**: 0.7 of the base line's spike (its width / 2.8), rocking 0.92 / 1.08 down the row, and
  growing only with the square root of the width, as thrown things do (`Tune.EruptSpike`). They grew with the width
  itself from 1.1x at the root, and were too big at the start of the line and towered at a big Size (the user: "when I
  have a lot of size the first ability spikes are too big", then "the groundbreaker spikes starting size is too
  big"). The crack and the line still take the real width.
- **Groundbreaker's crack narrows shut as it fades** (the user: "the lines that leave the first ability disappear
  instantly instead of smoothly", but smoothly under the ult). It closed in two transparency steps (30%, 60%) over
  0.18 s; Gold is brightened 2.2x, far past white, so both steps looked fully open and it snapped off, while the purple,
  less clamped, showed them. Now five steps of 0.06 s, each fading and narrowing it (`Tune.StripNarrow`, 85% narrower
  at the last). **A fade on a colour brightened past white does not read: shrink or move it too.**
- **Whirlwind's shovels coast to a stop** (`ShovelClient.SpinDown` / `SpinDownAngle`, also on the bench): when it ends
  they slow at a steady rate from the spin's own 5 rad/s to the next formation slot ahead, at least
  `SPIN_DOWN_MIN_SECONDS` 0.35 s. Checked in lune over 1000 stop times: they start at the spin's speed, end at 0 and
  land on a slot to 1e-14 rad; 0.35-0.66 s at 8 shovels, 0.35-0.98 s at 4, up to 2.9 s for one shovel (the next slot
  can be nearly a full turn on). Strikes during the coast are drawn on the formation, where the server hits, so a hit
  can show a little off its still-turning shovel for that half second.
- **Earthshaker's line grows with Size** (the user: "the spikes of the second ability of the shovel doesn't scale their
  size with the size passive"). It was a fixed 25 x 3.5 studs on the server and the client, so at a big Size the strike
  out-reached it and its spikes looked tiny. `ShovelShared.ShockwaveOf(size)` scales both with Size the way the strike
  does, on the server (`damageBuffLines`) and in `spikeLine`; the spikes, their spacing and their sway grow with the
  square root of Size, like Groundbreaker's. This is a gameplay change: the shockwave hits further and wider past base
  Size. Excavator's dirt chunk (28 x 3) is still fixed.
- **Groundbreaker reaches 30 studs at base Size, and that is the damage** (the user asked "they go too far, it's really
  how far the damage reaches?"): `LineOf` out to `FORMATION_RADIUS + REACH_MULT 5 x` half a strike's length, measured
  from the wielder; the server takes an enemy whose centre is in the rectangle. The drawing overshot it: the end smack,
  13.5 studs across, sat on the last spike and painted to ~36 studs. Every line's end piece now fits inside it
  (section 6): Groundbreaker's and Earthshaker's end smacks are the line's width, half a width in, their last spikes
  half a sprite in; Excavator's lobs land half a width in from the 28-stud end, and its thump plays when they do.
- **While Excavator is up every ability draws in its purple** (the user: "when I'm with the ultimate the color of the
  other abilities should also change colors because the ultimate changes to purple"). `ShovelFx` keeps the keys whose
  Excavator is up (`excavating`) and `abilityTint` swaps an ability's own tint (Gold, Shake, Wind) for `Tints.Ult`:
  Groundbreaker, Earthshaker's cast and every spike line's smack, Whirlwind's cast, hits, blades' wind and the
  Cyclone sheet. A Whirlwind already spinning is recoloured on the spot when Excavator goes up and back when it ends.
  Dirt, rocks and dust stay earth-coloured. Strikes already were purple under it.
- **The spike sheet has a 2-texel gutter** (section 6): the line over every spike was its neighbour's foot.
- **Optimized in the same pass**: Whirlwind's step reuses one `seenBlades` table instead of making one a frame, and a
  footprint writes its colour and transparency only when they change (twice in its life), its size and CFrame only on
  its 0.05 s frames.
- **The shovels rise as they grow** (`ShovelClient.RestY`). ScaleTo grows a shovel round its pose origin, and the blade
  hangs 1.6 studs under it a scale, so at Size 20 the blade sank 1.6 studs into the floor (the user: "when the shovels
  increase in their size they go underground"). They are lifted by that growth, keeping the blade's tip where it rests
  at base Size. The depth is read off the template's weld and box, divided by the template's own scale: **the
  template is authored at scale 2** and ScaleTo sets an absolute scale (reading it without the division lifted them
  twice too far).
- **The shovel model grows with the square root of Size's scale** (`ShovelClient.ModelScale`, `MODEL_SCALE_POWER
  0.5`; the user: "the size scale of the shovels model is too much"): 2x at 4x Size, where it was 4x. Only the model:
  the hit still grows with Size itself. `RestY` takes the model scale, so the lift still matches the blade.
- **The bench steps on game time, and game time is 0 until a run starts**: `shovelbench` in Studio before a run draws
  nothing. Drive `ShovelFx.Update` by hand in a probe, or start a run first.
- **The blow lands on the slam, not on the event**: the bonk slams down in 0.07 s (t^2) and lifts back eased; every
  strike is drawn on that frame (`Tune.SlamSeconds`).
- **Budget**: rings of 40 pooled emitters a template, 96 for Spike (Groundbreaker and Earthshaker's cast stand ~7 down
  every line at once); three blade attachments a spinning shovel, only while Whirlwind is up. Measured on the bench
  (2026-11-11, all five cells, a playtest probe every 2.5 s): about 538 attachments under Terrain, flat; 24 crack
  strips open after a Groundbreaker (4 shovels x 6 segments), all closed after; 12 blade rigs while spinning, 0 after.
  No ShovelFx errors.
- **Not seen, to check on the bench**: which way the Cyclone sheet turns against the shovels (if it spins against
  them, flip the frame order in `cyclone()`); whether the crack strip's zigzag carries across joints.
- **Not run in the game itself**: the bench ran in a playtest; a probe gave the character a Shovel on the server only
  (the client never got it), so ShovelClient's hooks on a real weapon are linted and compiled, not played.

- **The shovels' own motion** (the blows, rising and sinking, Whirlwind's lean) is `ShovelClient.Pose`, written up
  in Animations.md 15.
- **On the body (2026-11-12, section 25; previewed in ror, probed in a playtest, unseen by the user)**: each lasting
  ability keeps a BodyFx aura on the wielder, started and stopped with its feet sustain (`ShovelFx.BODY`, keyed by
  the sustain slot). Earthshaker: pebbles hopping up off the body and orange embers rising. Whirlwind: bands of wind
  (`windband`) lying flat round the torso from hips to chest, a slim box keeping them centred, flickering in and out
  in hard Transparency steps. Excavator: purple power licking up (the Greatshield's `wisp`), clods of earth lifted off
  the body that hang and drop back, a purple light; its cast flashes the body, throws rocks and clods up off the chest
  and gives the wielder's own screen the impact frame. Earthshaker's cast throws the same chest burst, without a
  flash. Only the ult flashes or lights. Under Excavator the other auras turn purple and back (`BodyFx.AuraTint`), as
  the rest of the kit does; the dirt rides keep their own colour (`TRide.Tint`).
  - **What the ror previews changed** before anything was uploaded: the embers came out white streaks (a white-hot
    birth at Brightness 2.2 on a small spark): Brightness 1.5 keeps them orange. The lifted clods at 0.8 of a strike
    clod and 8 a second piled over the body and hid it: half the size and 5 a second. Excavator's wisps at Brightness
    1.7 showed white tips: 1.5.

## 22. Last Wave: the Yo-Yo (built 2026-11-11, liked the same day; sounds picked; unseen by an agent)

`src/Survivors/Client/Weapons/YoYoFx.luau` is the rig AND the effects: the yo-yo models, their formation, every path
(throw, Counterweight's recall, Around the World's orbits, the colossal) and everything drawn with them. YoYoClient
only reads the server's moments and stats, plays the cues and jolts, and calls it; `yoyobench [piece]`
(`Debug/DebugYoYoController`) drives the same calls on a copy of the avatar. Templates in
`ReplicatedStorage.Effects.YoYoFx`; the kit is `Assets/effects/yoyo/` (its README). Before it, every ability was
`VisualEffects.ShowExplosionEffect` (a smooth sphere) in its own colour, and a throw drew nothing but the model.

- **What was asked, and the causes found:**
  - **Counterweight snapped the yo-yos home.** The client cleared every throw (`throwStartClock = math.huge`), so each
    yo-yo jumped to its slot on the cast frame, and the heavy throw left from there. The ability's STOP also ran the
    same function (the hooks fire on both edges) and snapped them again. Now the cast whips each yo-yo home from where
    it is drawn in 0.15 s, accelerating (`Tune.RecallSeconds`), the heavy throw waits out that recall and still reaches
    its apex on the server's beat, and the stop edge draws nothing.
  - **Every other change of path blends** (`Tune.BlendSeconds` 0.2, ease-out from where the yo-yo was last drawn): a
    throw cut short, Around the World starting mid-throw or ending, a revive.
  - **The ultimate was invisible.** The colossal was lifted 25 studs ABOVE its point (`COLOSSAL_VISUAL_LIFT`), 55
    studs ahead, so its body floated about 36 studs up, off the top of the follow camera. And **the yo-yo's Handle is
    the top of its string**: the body hangs off it on a weld, 3 studs under at scale 1 (30 at the colossal's 10), so
    anything placed "at the Handle" is a string's length off. The colossal's body is now placed centred on the
    server's point (its weld worked back to the Handle each frame), with its face turned 55 degrees toward where it
    was thrown from. Measured in a playtest: the body 4-7 studs over the player's root, on screen (y 160-440 of 1080)
    for all 8 s.
- **One look a piece, no variants yet.** Section 1's bench of three a piece was not built this round; if a piece reads
  wrong, bench rivals that differ in their art (memory: VFX variants differ in art).
  - **Throw**: the string (a Beam from the chest to the body, taut out, slacker back, a twang through it at the apex),
    speed lines and glints left behind, the yo-yo leaning into its flight and spinning faster, a wake on the floor at
    the hit's width under the string, a "ting" snap at the apex, a pop as it comes home. Cyan; violet while Infinity
    Loop is up.
  - **Counterweight**: a gold slash along each line the server cuts (apex to wielder), its far end running home with
    the yo-yos; a clack, sparks and a ring as they land in their slots and swell; a gust as the heavy throw leaves;
    a bigger snap and a slam under each heavy apex.
  - **Tether**: the strings go razor (a jagged pink thread scrolling), the wake is drawn from the wielder at Tether's
    width, sparks crackle off the yo-yos and round the feet.
  - **Around the World**: a gust and streaks on the cast; under each orbiting yo-yo a radar sweep out to its ring,
    turned every frame so its arm points at it; the wake from the wielder to the yo-yo is the sweeping bar the server
    hits.
  - **Infinity Loop**: the colossal thrown out of the wielder's hands on an arc, growing; a slam and a ring where it
    arrives; a violet vortex sheet at the damage radius, a ring pulsed on every damage tick, streaks pulled in from
    past the edge, motes rising, a light, and a thick razor string back to the wielder; on the end it is pulled home
    down a violet slash, shrinking, and bursts at the feet.
- **Not seen**: which way the sweep's trail lies (`Tune.IsSweepFlipped`, reasoned from section 16's mapping, if the
  trail shows ahead of the yo-yo set it true), and which way the wake's chevrons point (row 0 is the far end, laid
  as the Shovel's Furrow is).
- **Checked**: StyLua, Selene, compiled; in a playtest the real path (the Yo-Yo given on the server, all four abilities
  fired through their hooks) and `yoyobench` ran with no errors, pooled attachments growing as templates were first
  used and then holding.
- **Liked ("Good, I like it"), then sounds** (`Assets/Sounds/Review/YoYo/README.md`, Sounds.md "Yo-Yo"). The beat
  sounds (apex ting or heavy slam, Counterweight's clack, the colossal's landing, the vortex pulse, the burst home)
  play from YoYoFx on the frame the beat is drawn, above the Particles and opacity gates, so they still land with
  particles off; the bench plays them too, so it adds none of its own for those beats.
- **One formula for what is hit and what is drawn.** The corridor's half width and a throw's legs were copied five
  and four times (YoYoServer three times, YoYoClient, the bench). They are now `YoYoShared.GetHalfWidth(sizeScale,
  isTether)` and `YoYoShared.GetThrowLegs(projectileSpeed, attackSpeed, isInfinity)` (flight out, hold, flight back,
  rest), read by all three; a copy that drifts draws the wake at a width the server does not hit. Checked in lune
  against the old formulas over a grid of speeds and sizes: equal to rounding. The one change: the server's fire rate
  now floors Attack Speed at 0.01 like every other caller, which only matters between 0 and 0.01.
- **Per-frame writes only on change.** The review after the build found the string's width, the sweep's size and the
  colossal's light, string width and Enabled written every frame though they hold for seconds; each is now compared
  with the last value written (kept on the visual or colossal table) and skipped when equal. The colossal's handle
  offset (`weld.C1 * weld.C0:Inverse()`) is worked out once at its creation (at scale 1, so it is multiplied by the
  colossal's Scale when used: see "The Yo-Yo on the body"), and
  YoYoClient's rig lookup checks one property (`rig.Wielder.Visual.Parent == model`) instead of `FindFirstChild`
  every frame. Do the same in the next effect: in a per-frame step, an Instance write that usually repeats its last
  value is compared first.
- **Testing it: a level-up pauses the client.** In a solo playtest every level-up choice pauses `TimeCore` on both
  sides, and YoYoFx runs on game time, so the rig, its beats and their sounds freeze until the choice closes (a probe
  counted 0 `YoYoFx.Step` calls for 13 s). Stubbing the server's `TimeCore.Pause` does not reach the client. A
  missing beat in such a run is the pause first: count `Step` calls before suspecting the code.

### The Yo-Yo on the body (2026-11-12, unjudged)

Only the ult (the rest were liked as they are). While the colossal is out the wielder's body shows they are the one
spinning it; all of it lives in `YoYoFx` (`BODY` specs, `endBody`), so the bench draws it too. Templates
`YoYoFx.Body` (`Orbit`, `Surge`, `Glint`, `Umbra`, `Flare`, `Mote`); one new sprite, `orbit`; preview scenes
`tools/vfx/preview_yoyo.py`.

- **The cast**: a violet Hit flash over the body, the outline violet (`PlayerOutline` layer `InfinityLoop`), and two
  auras for the ult's length: the yo-yo's loop round the waist (`Loops`, the Shovel's band technique: a slim box,
  no lean, a looping flipbook started at random) and violet power surging up with the apex's glint winking on it over
  dark Umbra motes, with a light (1.5, flashing 5). The ult comes back every 80 s, so it earns the flash and light.
- **The orbit sprite** is the kit's own: two yo-yo beads with hot tails chasing round a dim dashed track, the track
  drifting back the other way. Two-fold, 16 frames a half turn, 32 texels over 5.5 studs. Different art from the
  Shovel's wind band (no track, no beads), so the two kits do not wear the same ring.
- **The landing**: the aura is "recast", which flares its light again (BodyFx restarts a running aura's flash).
- **Every damage tick**: two streaks thrown from the chest up the string toward the colossal, so the power reads as
  coming from the body.
- **Home**: when the colossal bursts at the feet, a flare of sparks and flickering motes off the chest
  (`BodyFx.Burst`), a pale violet Hit flash, and the impact frame on the wielder's screen: the recall is the kit's
  hardest blow (4x damage along the line), and it lands on the body.
- **One ending for every way the colossal goes**: home, dropped when the wielder is downed, recast, or the rig
  destroyed (weapon removed). `destroyColossal` calls `endBody`, so no path leaves an aura or an outline layer on.
- **In ror**: the rising sparks first came out white streaks at Brightness 1.5 with white for 30% of their life;
  white only for the first 15% and Brightness 1.4 kept them violet. The orbit bands read level round the torso.
- The Yo-Yo bench now stands its cells on `benchStandIn` (its own copy is gone), so the outline shows there.
- **Probed in a playtest** (game time, `yoyobench InfinityLoop`): no script errors; both auras up from the cast, the
  stand's outline violet (0.65, 0.35, 1) for the whole ult; at the colossal's return the home burst and its Highlight
  appeared, the outline blended back to white, and every body piece was gone 0.9 s later. Not seen by an agent in
  game: the look at the camera's distance, the orbit's turn direction against the yo-yos' spin.
- Uploads: `orbit` decal 112170472824305 (image 140733291521871), model 73838323228745; only `Body` was moved into
  the place.
- **The user's review (2026-11-12): the colossal hung outside its circle and the string pointed at nothing.** The
  cause was section 22's "per-frame writes only on change" pass: the handle's offset from the body
  (`HandleFromBody`, the weld's `C1 * C0:Inverse()`) was cached once at creation, at the model's own scale, but
  `Model:ScaleTo` stretches the weld with the model, so at the colossal's 10 the body was drawn about 9 offsets (~27
  studs) from its point, while the string, the vortex and the damage stayed on the point. Fixed by scaling the cached
  offset's translation by the colossal's Scale each frame (`fromBody.Rotation + fromBody.Position * Scale`). Lessons:
  - **A cached joint offset is only good at the scale it was read.** Anything that rescales a model (ScaleTo, a
    Size upgrade) stretches every weld and Motor6D in it: cache the offset per scale unit (the throw rig's
    `BodyOffset` already divides by `GetScale()`), or re-read it after a rescale.
  - **An optimization pass needs the same in-game check as the feature it touches.** The colossal was measured on
    screen before the cache and never after; a probe of the body part against the server's point would have caught
    it.

### Counterweight under Around the World: the orbits swell (2026-11-16, built, unseen, unplayed)

Counterweight cast during Around the World used to do nothing until the orbit ended: its recall cut lines along the
facing (not where the orbits were), and the heavy throw it left waited for the next throw, after the orbit. Now it is
the same ability inside the other one (`YoYoShared.COUNTERWEIGHT_SWELL_SECONDS`, `GetSwellWindow`, `GetSwellRadiusMult`):

- **The heavy throw becomes a heavy lap.** Over one lap every orbit swings out to twice its ring and back, hitting at twice
  the orbit's damage, once per enemy per yo-yo (its own dedup, like a lap's). The heavy throw is twice a throw's size and
  damage; the swell is twice a lap's. No recall hit: the yo-yos never come home, so nothing stands in for it. That keeps
  the pair no stronger than the two abilities on their own.
- **The radius is one parabola**, `1 + (2 - 1) x 4p(1 - p)`: exactly the throw's ease out followed by its ease in home,
  so the swell moves the way a throw does. Server and client both read it from YoYoShared.
- **It fits the orbit.** It waits for the deploy and is cut short to end with the orbit; once the yo-yos are on their way
  home it is a plain Counterweight again (the server's `swellOrbit` and `YoYoFx.Swell` both return false).
- **Art, all from the kit**: the yo-yos grow to the heavy scale and back; each sweep disc is resized only while it swells
  (written only on a change) and turns gold until it is home; Counterweight's clack, ring and gust plus gold streaks
  as it leaves; at the peak, the heavy slam's sound, a snap and a slam on every yo-yo, and a gold ring at the widest reach.
- **Not seen or played**: whether the gold sweep reads over the orbit's green, and whether one lap is long enough.

### Tether as a pluck (2026-11-16, built, unseen, unplayed)

The old Tether (5 s of pink razor strings) only moved the corridor's start from the slot to the wielder and widened it
2.2x: the basic throw already hits the whole string out and back, so the ability promised what the weapon does. It is now
one pluck (YoYoShared "Tether", YoYoServer `abilityTether`, YoYoFx `Pluck`), 10 s cooldown, Ability Damage, Stun:

- **The beats**: the cast yanks every yo-yo from where it is drawn to its apex in 0.08 s (a throw whose flight out is
  the snap: `OutFrom` is where it leaves from, the hold is the wave and the ring), the apex ting plays as the strings go
  taut, then the wave runs down each string at 250 studs a second (0.15 s at base Size) and lands: everything on the
  strings is hit once (one dedup for the cast) and Stunned, then the yo-yos come home on a throw's return.
- **Drawn**: four knots (the `Pop` sprite) step down each string with the wave, a line grows out under each string on
  the floor in four steps (the recall slash's art, `startSlash` with `Grow`), and where it lands a burst (`Snap` at 9
  studs), sparks and a slam under each yo-yo, while the string swells 2.5x and shakes at 12 Hz, both stepping back down
  (`pluckOf`). The line holds while the strings ring, then fades narrower in three steps. A small flare off the chest
  (`BODY.Pluck`), no flash and no light: it comes back every 10 s.
- **Combos**: under Around the World the yo-yos keep orbiting and the whole disc rings (the server hits a growing disc
  out to the outer ring): a ring flashes out at each orbit's radius as the wave passes it and every orbiting string goes
  razor and shakes. With the colossal out its string is plucked too, and the wave bursts round it at its damage radius.
  Those two earn the impact frame; the plain pluck does not.
- **The camera**: a small yank on the cast, the bigger jolt when the wave lands (`TPluck.OnPlucked`, on game time).
- **No new art**: knots, line, burst and rings reuse the kit's sprites. If the line reads as Counterweight's recall, a
  pluck sprite of its own is the next thing to draw (and bench against the slash, section 1).
- **The wide string is the pluck's alone**: `GetHalfWidth(.., true)` is passed only by Tether. Throws, Counterweight and
  Around the World no longer read `IsAbilityTwoActive` (a leftover of the buff: inside the pluck's ~1.4 s it would have
  widened them). The flag now only holds the ability active while the plucked yo-yos come home.
- **Bench**: `yoyobench Tether` (every 4 s), `TetherRing` and `TetherColossal` (a pluck 2 s into the buff).
- Sounds: the landing plays the heavy throw's thud until round 2 (`Assets/Sounds/Review/YoYo/round2`) is picked.

## 23. Last Wave: the Greatshield (built 2026-11-11, looks picked the same day; the Jaws unseen by an agent)

`src/Survivors/Client/Weapons/GreatshieldFx.luau` draws every piece; `GreatshieldMotion.luau` is the bite's motion
(Animations.md 15); GreatshieldClient is glue. Particle templates in `ReplicatedStorage.Effects.GreatshieldFx`
(`Burst`, `Ride`, `Ground`, `HexSkin`, `CrackSkin`); the kit is `Assets/effects/greatshield/` (its README). Before it
the chomp drew nothing, Rally was `VisualEffects.SpawnGroundCircle`, the Charge's slams and Bastion's cast were
`ShowExplosionEffect` (a smooth sphere) and the dome a ForceField ball tweened bigger as it went.

- **Picked** from three looks a piece (the losers' sprites and templates are deleted): **Rally** Aegis (a wall of
  hexagons locks in ring by ring, a heal cross off every ally), **Charge** Comet (the corridor scorched behind at the
  hit's width, embers, the Nova slam) with a rounded head added, **Bastion** Hex (honeycomb skin, Hexwave cast) with
  runes written into the floor under it. **Chomp** is still a choice of two on `greatshieldbench Chomp`
  (`greatshieldstyle Chomp <look>`): **Jaws**, the user's idea (a maw flying in front of the shield, turning with it) over
  the Fangs marks, or **Fangs** alone on the floor. Once picked, delete `Styles` / `StyleNames` and `greatshieldstyle`.
- **The Jaws fly in front of the shield, in its frame** (the user, after the first version lay on the floor: "in front
  of the shield flying with the same rotation as the shield, like the Q of Warwick"). GreatshieldClient calls
  `GreatshieldFx.Jaws` every frame with the motion it just sampled and the shield's frame worked out from the joint it
  just wrote (`Part0 * C0 * Transform`; reading the Handle's CFrame is a frame behind at the lunge), so the maw rolls,
  leans, bobs and lunges with the shield and its jaws open by the shield's `Open`. Eight thin parts: an upper and a
  lower jaw plate hinged `JawLeadStuds` past the shield (clear of its 0.86-stud depth and its own jaw halves), each with
  three curtains of tiled fangs pointing in at the other jaw (the upper ones shifted half a tooth so shut jaws
  interlock). As wide as the bite; its length is set at the contact pose so the tips land on the bite's far edge then.
  The lower jaw drops only as far as the floor lets its rolled corner, and the upper one opens wider to keep the gape.
  In: three steps as the jaw opens, the teeth growing. Out: after the chew, four steps over the pry and settle, teeth
  shrinking and the jaw letting go a little. A probe over 980 bench frames: every corner 1.05+ studs ahead of the
  shield's centre and above the floor.
- **The Jaws hinge at the shield's mouth, not its Handle** (the user: the maw sat "a little bit up from the actual two
  parts of the greatshield that opens and closes"). The Handle is the Up bone's pivot, near the top of the panel; the
  halves meet 1.41 studs under it (`GreatshieldFx.MouthOf`, scaled with the Bite's swell). Measured from the mesh's
  skin weights in a playtest: `AssetService:CreateEditableMeshAsync(Content.fromUri(meshId))`, each vertex's heaviest
  bone (`GetVertexBones` / `GetVertexBoneWeights`), positions times `Size / GetSize()` round `GetCenter()`. The Up
  half's lowest vertex and the Down half's highest overlap (the interlocking teeth); the mouth is their middle. Any
  rig whose effect must sit on a skinned seam is measured this way, not guessed from bone pivots.
- **Every Charge slam ends in the Aura Shockwave's shell** (the user: "a shockwave with the sphere part, just like the
  aura first ability but adapted to the greatshield"): the wall slam and the end burst alike, since both finish the
  run. The Aura's `ShellMesh` and band `ShellSkin`, tinted the Charge's blue, swell out of the floor to the slam's
  radius in hard steps, easing out (a slam lands at once, where the Aura's sweep is even), then fade in steps; a
  Blast flash at its heart, the Nova wave on the floor under it, shards thrown and dust after 0.05 s. The comet's head
  is still flung on ahead.
- **Sprites on parts go on the Front face**, as SurfaceGuis (`faceUp`): a part whose Front face looks up and whose +Y
  runs along the piece puts the sprite's top row at the far end, with no guess about how a Top face orients a
  texture. A strip's frame is `ImageRectOffset` in the image's pixels, not an `OffsetStudsU` whose sign was never seen.
  `LightInfluence 0` and `Brightness` make them glow like the particles (a Texture is lit by the scene). Used by the
  Jaws, the Fangs footprint, the Comet's head and the runes; the skid corridor stays a seamless Texture.
- **No ending in one frame** (memory: endings never snap). The Fangs footprint holds each frame its own time
  (`FootFrameSeconds`): the jaws close in 0.17 s, the marks hold 0.3 s, then break up over 0.4 s while fading
  (`FootFade`). The Comet's head steps in and out a third at a time; at a slam it is flung ahead to 0.8 of the slam's
  radius, widening and fading (`fadeAway`). The runes burst outward with a broken dome, shrink in with a cleared one.
- **Every piece is drawn at the server's numbers**: the chomp's rectangle (`Size x 0.75` long, `x 0.5` wide, pulled
  back `BITE_BACK_OFFSET_STUDS`; doubled for the Bite), Rally to `RALLY_RADIUS_PER_SIZE`, the corridor and the head at
  `CHARGE_HALF_WIDTH`, the wall slam at `CHARGE_SHOCKWAVE_RADIUS_PER_SIZE` and the end burst at
  `CHARGE_END_RADIUS_PER_SIZE` (the `GreatshieldImpact` event says which, a boolean), the cast slam at
  `ULT_SHOCKWAVE_RADIUS_PER_SIZE`, the dome and its rune ring at `ULT_DOME_RADIUS`, its break at
  `ULT_DOME_END_RADIUS_MULT` of it.
- **The dome moves like a sprite**: 12 steps a second, raised in four overshooting steps (the runes with it, the star
  a beat later, ring and star turning opposite ways on those steps), every health drop flashing dome and runes for two
  steps with sparks off the wall, a crack skin showing more at two thirds and one third (shards thrown as it crosses),
  a flicker under a quarter, and on its end a swell in three steps, then shards from 18 points round the wall and the
  break sheet out to the end burst's reach. Cleared (not broken) it shrinks away in four.
- **Budget**: rings of 32 pooled emitters a template (64 for shards, 48 for sparks, plus and streaks), held at ~660
  attachments with every bench cell running. Footprints and strips are pooled; one maw a shield (8 parts, 15
  SurfaceGuis) is kept and only re-parented, its colour, fade and glow written only when they change. One dome is one
  MeshPart, 10 Textures and two rune parts, written only on its steps. A charge writes its rates in tenths of its
  speed.

### Review round (2026-11-12): the Charge's forcefield, the Bite's snap, nothing in the floor (unjudged)

The user's review of the whole kit: the Charge's light and front effect flicker, a forcefield in front of the runner
"more visible on the front and going transparent on the edges, not being a full circle" (two dome references), the
bite "can be improved" (four anime bite references: fangs closing on a long four-point flare, sparks flying out, a
ring), and the shield and the Jaws sinking into the floor (more with Size).

- **A speed read from one frame's movement flickers.** The Charge took its speed from how far the root moved since the
  last frame. Above 60 fps some frames see no physics step, so the speed read 0 there and the light, the rates and the
  head blinked off and on. The run now eases the measured velocity over 0.12 s (`SpeedSmoothSeconds`), which also
  works for the bench's anchored runners where `AssemblyLinearVelocity` is zero. Anything that drives a look from a
  body's speed eases it first.
- **The forcefield** (`aegisfront`, 64 x 32, two frames): the shield unrolled round its arc, a hot rim on the dome's
  crown over a glow band, a honeycomb under it fading out through the dither toward the floor and both ends, a lit band
  of cells moving along it between the frames. In game it is 8 upright SurfaceGui strips on a 150 degree arc
  (`FieldStrips`, `FieldArcRad`) of 0.85 times the charge's half width, each showing its slice by `ImageRectOffset`, the
  middle strips the most solid (0.1) and the ends see-through (0.5). Its height keeps the texels square round the arc.
  The inside face (the camera's side) shows the slices left to right; the outside face shows the mirrored slice, so
  someone watching from the front sees it whole too. It comes and goes with the head (thirds).
- **Rams are found on each client, not sent.** Every 0.05 s a charge looks through the client's own enemy positions
  (`EnemyWorld` `Components.CFrame`, the AOI's enemies) for any inside the field's arc; each one counts once per the
  server's `CHARGE_REHIT_INTERVAL`, lights its strip and the two beside it, throws sparks off where it hit, and plays
  the dome's own hit sound (one shield voice for both), at most every 0.12 s. A purely visual question about where
  things are needs no network event when the client already holds the positions.
- **The steps are on the run loop's feet.** The Running loop plays at the charge speed times `RunCyclesPerStud`
  (now owned by GreatshieldFx, the client reads it), so its phase is the distance run times that; a foot plants at
  phases 0.07 and 0.57 (read off the animation in a playtest, Animations.md 15), so a step sound and a puff of dirt land
  on each plant at any speed. Probed: a step every 0.52 s at 40 studs a second, the first at 0.08 s.
- **The Bite's snap** (`snapflare`, 64, 4x4): where the Jaws' fangs meet, a long four-point flare (the horizontal
  rays to the frame's edge, the vertical ones shorter) holding two frames at full length round a hot core, then drawing
  in; ten sparks flying out and a ring breaking up behind them. A ring of speed lines is thrown round the bite in the
  plane across it, and the fangs flash white as they meet (`JawFlashSeconds`). The Fangs look keeps the clack.
- **Nothing in the floor, every tilt kept.** The shield's bob, its lean into turns (up to 22 degrees) and the bite's
  45 degree roll all turn it about its middle, which drops a corner; GreatshieldClient lifts the posed shield by what its
  lowest corner (its model's box in the Handle's frame, plus the lower jaw hanging open) would sink under the floor
  (Animations.md 15). The Jaws' teeth grow with the bite's width, which spreads their hinges apart, so the whole maw
  rises by what its lower hinge would sink. The user: "if you cannot fix it without making the shield be straight then
  leave as it is": a lift by the sink is the fix that keeps the tilt.
- Uploads: decals 74509388930838 (`snapflare`, image 113461151281700) and 133947442455653 (`aegisfront`, image
  101147372814946); Model 82894115388057, of which only `Burst.SnapFlare` was moved into the place. **The place is
  unsaved.**
- Probe (a playtest, the live character driven at 40 studs a second): no errors, every new cue loaded, 8 strips up,
  steps on the beat, the light changing only as the speed ramped (15 changes over 2.6 s, where a flicker is hundreds),
  Bastion's grab played, both bites drew. **Not seen in game**: the rams (no enemy was near; a second probe could not
  start, Studio stopped answering) and the shield's lift on a real Greatshield.

## 24. Last Wave: the Mortar Hat (built 2026-11-11; sounds picked; looks picked 2026-11-12: Fuse, Dome)

`src/Survivors/Client/Weapons/MortarHatFx.luau` is the shells AND the effects: every shell's flight (the pooled Ball
on its bone), what it sheds, its landing reticle, its blast, Detonator's stuck shells and their chain, the casts round
the hat and Mortar Strike's last shell. MortarHatClient only turns the server's events and ability edges into those
calls and drives the hat's motion (Animations.md 15); `mortarbench [piece]` (`DebugMortarHatController`) makes the same
calls on copies of the avatar. Templates in `ReplicatedStorage.Effects.MortarHatFx` (`Burst`, `Ride`, `Beam`); the kit
is `Assets/effects/mortarhat/` (its README). Before it, every landing was `VisualEffects.ShowExplosionEffect` (a
smooth sphere), the launch and every ability drew nothing, and the shell was a bare Ball.

- **THE LAST SHELL NEVER APPEARED** (the user: "the actual last big bomb never appears, probably because everything is
  already dead"). Right: `fireMortarStrikeFinal` returned when no enemy was inside 250 studs, before its own fallback,
  so after eight seconds of rain had cleared the field nothing dropped. It now always drops: on the densest cluster, or
  `MORTAR_STRIKE_FINAL_FALLBACK_AHEAD` (18) studs in front of the wielder, on screen. Checked in a playtest: the ult
  fired, every enemy cleared mid-rain, the server still sent the final shell (radius 75 at base Size).
  - **The client is told which shell is the last one**: `ShellSpawn` carries a second boolean, `isFinal` (blink
    regenerated; the diff was that event only). Before, the client could not tell it from the rain.
  - **It falls for 1.6 s** (`MORTAR_STRIKE_FINAL_FALL_TIME`, the rain's 1.2) so its arrows read before
    it lands. Damage and radius are unchanged.
  - **It is drawn from 90 studs, not 200**, falling `inQuad` (a weight), landing when the server's does: the server's
    200-stud straight fall is above the follow camera for nearly all of it. 3.2x a shell's size.
- **Every shell, one language**:
  - *Launch*: a muzzle sprite at the hat's top (a star, a flame tongue, a flat smoke ring), a star led out the way it
    goes, sparks and a puff. The mouth is the hat part's top (`Part.CFrame * (0, Size.Y / 2, 0)`): the model has no
    Muzzle attachment.
  - *Flight*: a smoke trail and fuse sparks off the shell's Root bone (EmissionDirection Back: the bone looks down the
    flight), speed lines for shells out of the sky.
  - *Landing reticle* on the floor at the server's radius for the whole flight: a dashed ring turning, a crosshair and
    a fill growing to the edge, burning hot on its last two frames, so the fill reaching the edge IS the landing. Its
    Lifetime is set per emit to the flight (`burst(..., lifetime)`); a shell that bursts early on a flyer clears it.
  - *Blast*: the shockwave sheet at the radius (lands on its edge at frame 4: the server hits on landing), a standing
    fireball (grows with radius^0.75), rocks, sparks, smoke, dust, and a scorch that breaks up over 2.6 s.
- **Tints are the moment**: orange the cannon, gold Salvo, crimson Heavy Shell (plus a second cloud, shards and stun
  stars hanging over the blast), lime Detonator's chain, violet Mortar Strike. Heavy is snapshotted at fire, as the
  server's payload is.
- **Detonator**: a stuck shell lies on its spot with a blinking armed light (one `LockedToPart` looping particle on its
  bone, cleared when it goes), a dust puff and the stick sound. The chain goes off oldest first at the server's 0.02 s
  interval, a lime jagged bolt (the Revolver's) running from each shell to the next. Under Detonator the server sticks
  every shell, the last one too, so the client does the same and the final goes off with the chain.
- **Casts round the hat** (`MortarHatFx.Cast`): Salvo a big muzzle blast and a ring at the feet; Heavy Shell shards,
  sparks and a crimson ring; Detonator's arm motes and cracks, its detonation streaks; Mortar Strike a violet flare
  burst and cracks, and every sky shell sends a small flare up out of the hat.
- **The last shell's landing** (`finalImpact`): falling arrows over its landing from the moment it is fired (below);
  on landing a big flash and a PointLight stepped down 12 times a second, the blast and cracks at the radius, the
  Aura's low-poly dome swelling to the diameter in hard steps and fading, a mushroom cloud 1.6 radii tall, a second
  shockwave 1.35 radii out 0.12 s later, nine blasts rippling out inside it on the golden angle over 0.55 s, then
  embers and motes. Camera: one big jolt (Kick -14, Shake 7, 0.9 s, felt 220 studs out). Sound: MortarFinal, baked to
  hit in its first milliseconds, and the ripple heard as a run of pops (Sounds.md "Mortar Hat").
- **Budget**: rings of 32 pooled emitters a template (96 for Fireball: Rim spends nine a blast), a burst skipped when
  its next slot is busy; ride emitters cloned once per pooled Ball and only re-rated; domes and shadows pooled; blasts
  past 220 studs from the camera's focus draw nothing (sounds and jolts still play). Measured in a playtest with every
  ability and the bench running: Terrain attachments grew as templates were first used and held (384, then 544 with
  the bench; 725 with the round 2 bench of eight stands). One Heartbeat while anything runs.
- **Testing it in a solo playtest**: the client pauses on every level-up (CLAUDE.md), and a server-side skip does not
  unpause it, so neither the shells (game time) nor the hat's motion (WeaponsController skips paused frames) move. A
  probe calling `TimeCore.ResetAllPauses()` on the client each PreAnimation un-sticks it.
- **Round 2 (2026-11-11), the user's notes**: the beacon's arrows "still at the side, not down", "they appear
  instantly, it should appear and disappear smoothly"; the reticle "can be in the middle of the air ... a lot of pixel
  art effects in the middle of the air"; "the explosion looks 2d on the floor but it's 3d, maybe adding the shockwave
  just like it was before but in the new style"; "the telegraph is not really good for this weapon because anything
  can happen in between and maybe it goes into a bee and explodes there ... maybe the expectancy of when it is going
  to land or explode is better"; "make some variances".
  - **Don't point a Beam's texture without a look.** The beacon was a wrapped Beam tile with chevrons along +U, then
    a square tile; both came out sideways on screen, and Studio was minimized, so no screenshot could settle the
    axes. The column is now particles (`Mark.Arrow`): a sprite facing the camera draws upright, so a chevron drawn
    pointing down the image points at the floor from any camera. The emitter sits ArrowStuds over the landing,
    throws arrows down (EmissionDirection Bottom) at the speed that lands each on the floor as its lifetime ends, and
    their Transparency fades in at the top and out at the floor. Stopping it at the landing leaves the arrows in the
    air to drain, then the attachment goes (measured in a playtest: emitting down from 70 studs, off at the landing,
    gone after the drain).
  - **No two burns alike (2026-11-12).** "Make variances for the black png that is leaved on the floor when it
    explodes": four burn sheets with different art (`scorch` blotches and streaks, `scorch_rays` a starburst whose
    rays burn back, `scorch_ring` a crater whose rim crumbles last, `scorch_splat` a lopsided splash thrown one way,
    drying from its droplets in). Every blast picks one, turns it a quarter turn (90-degree steps keep the texels on
    the grid; the Rotation is written on the slot before the emit, since a particle keeps the one it is born with)
    and sizes it within 15%. Measured in a playtest: 12 shells drew all four at three different turns.
  - **Nothing flat in mid-air.** `groundAt` now says whether it found a floor; the reticle, the blast sheet, the
    scorch and the dust are drawn only on one. A shell bursting on a flyer is a standing burst (and a Dome).
  - **Picked (2026-11-12)**: "I like Fuse but also add a shadow on the floor under it" and Dome. Every flying shell
    now blinks faster and bigger as it nears the end (`Ride.Tick`, every Remaining x 0.28 s, its fuse sparks
    thickening 2.5x), so a shell that bursts on a bee leaves nothing waiting on the floor. Every blast drew the Aura's pixel shell swelling to the damage radius (at most 24 standing);
    taken off every shell but the last one on cost, 2026-11-15 (section 5). Lost: the Reticle (a mark waiting on the floor is wrong when
    anything can burst the shell first), the Shadow alone (no beat to say WHEN), Rim (eight puffs round the edge read
    as a ring of separate blasts) and Flat (the 2D sheet the user called flat in the first place). Their code, the
    `target` sprite, the bench's Looks stands and `mortarstyle` are gone; the per-emit Lifetime `burst` carried only
    for the reticle went with them.
  - **The shadow came off after a look (2026-11-12)**: built under every shell on the user's pick, then "remove the
    shadow" on the review. Its code, the `shadow` sprite and `Mark.Shadow` are deleted. The blink alone is the
    telegraph; the only thing drawn ahead of a landing is the last shell's arrows. Lesson: a mark on the floor under a
    shell reads as a second thing to watch; the blink on the shell says the same and goes wherever the shell goes.

### The Mortar Hat on the body (2026-11-12, unjudged)

- **The last shell is the kit's hardest blow**: `BodyFx.ImpactFrame` on the wielder's screen as it lands (`TLaunch.Root`
  carries the wielder's root to the shell). The bench passes your own root, so its last shell flashes your screen too.
- **The mushroom's contrast layer** (`Burst.MushroomUmbra`): the same cloud sheet, unlit (LightEmission 0,
  Brightness 1) in a deep violet (40, 16, 72), 1.08x the size and ZOffset 0.9 against the cloud's 1, so the glowing
  violet cloud keeps a dark rim on bright grass.
- **Heavy Shell and Detonator flare at the hat**, not only ring the feet: a Flash 1.3 to 1.5x and the muzzle's star at
  the hat's mouth (`HAT_FLARE`). A sprite, not a Highlight: they come round every 18 to 20 s, the same class as
  Momentum, whose body flash the user rejected.
- **The buff's colour on the body**: Heavy Shell's crimson and an armed Detonator's lime lie on the wielder's outline
  for as long as they last (`PlayerOutline` layers `HeavyShell`, `Detonator`, taken off on the stop edge and in
  `MortarHatClient.Destroy`). The lime is the first to cut if it reads badly on the grass.
- **Bench bodies are one util now**: `src/Survivors/Client/Utils/benchStandIn.luau` copies the local avatar (weapons
  cleared, scripts and sounds stripped, root anchored, no name tag, its Highlight registered with PlayerOutline). The
  Aura, Mortar Hat and Yo-Yo benches use it; the Shovel bench's `newRunner` still has its own copy (it keeps the Weapons
  folder), so fold it in when that file is next touched.
- **Probed in a playtest** (game time, pauses reset each frame, every bench piece up): no errors; the last shell's
  `MushroomUmbra` drawn; the Heavy Shell stand's outline went crimson (1, 0.26, 0.20) and the Detonator stand's lime (0.59, 1,
  0.27), both blending back to white after.
- **Not seen by an agent** (Studio was minimized, no screenshot): the arrows on screen, any of the new looks, the
  mushroom's size against the camera, and the final's 90-stud drop height.

## 25. Seeing an effect offline (ror, ree, rur) and what the reference pack taught (2026-11-12)

### The tools (installed 2026-11-12, upgraded 2026-11-20)

Three offline Roblox tools from Anime-Vanguards (GPL-3.0, Linux x86_64 releases ror 0.6.0, ree 0.7.0, rur-native
0.8.0, checksums verified): `ror` (renders models and effects to PNGs and MP4 on the GPU), `ree` (runs Luau against an
emulated engine) and `rur-native` (renders Roblox UI). Binaries are in `~/.local/bin`; their source and docs are in
`~/.local/share/roblox-tools/<repo>`, checked out at the installed release tag (read `docs/` there before guessing a
flag; `main` documents flags the binaries do not have yet). **This is the first way an agent can SEE an effect**:
before them, section 2 was all there was. They read files; they never run Studio or touch the place.

- **Upgrading**: download the release zip, check its sha256 against the release page, replace the binary, then
  `git checkout <tag>` the clone so the docs match. Flags change between releases (rur's output folder is `--dir`).
  An unknown flag is not always an error: ree 0.7.0 accepts `--rojo` and mounts nothing (it is on `main` only), so a
  harness that fails with "GlobalShared is not a valid member" means the mount did not happen. Use `--roots` or
  `--mount` with ree until `--rojo` ships.
- **Built-in content**: there is no Roblox install on Linux for them to find, so point them at Vinegar's Studio:
  `export ROR_ROBLOX_CONTENT=~/.var/app/org.vinegarhq.Vinegar/data/vinegar/versions/<version>/content` (the
  `RUR_ROBLOX_CONTENT` variable for rur). Without it there is no sky, studs or default particle texture.
- **Our images are group-owned**: ror downloads `rbxassetid://` content anonymously and gets `HTTP 403, not
  authorized` for every image this game uploaded. Do not hand it a cookie: write the preview file with each id
  swapped for its local PNG path (an absolute path is valid content to ror). Every kit's `images.json` maps
  `<name>_px` to its id, and the PNG sits beside it. ror 0.6.0 and rur 0.8.0 can instead download them with
  `ROBLOX_ASSET_DELIVERY_API_KEY`, an Open Cloud key with the `legacy-asset:manage` scope. That key has not been made
  for this project yet.
- **Previewing a template before it is uploaded**: build a small `.rbxmx` around the kit generator's own emitter
  XML (import `make_<weapon>_effects_rbxmx.py` by path and reuse its `emitter(...)` strings), add a stand-in body of
  blocks, then
  `ror video scene.rbxmx --playback scene.json --duration 2 --camera '{"mode":"lookAt","eye":[14,12,18],"target":[0,3,0],"fov":50}' --out <dir>`.
  Read `<dir>/sheet.png` (12 moments with particle counts); cut a closer strip from `video.mp4` with ffmpeg.
  - A playback must switch emitters on (`{"at": 0, "target": "BuffBox", "enabled": true}`). Without that the
    summary warns "no frame drew a particle".
  - `motion` moves a part and everything under it, so a runner (and the trail it leaves) is one key pair.
  - `ror` draws Highlights, PointLights on the floor, bloom and ColorCorrection, so a body flash or an impact frame
    can be previewed too. Terrain is not drawn.
  - Negative CLI numbers need `=`: `--pitch=-15`, not `--pitch -15`.
  - Prefer `--camera` lookAt over `--yaw/--pitch`: the auto framing fits the whole floor part, and a negative pitch
    put the camera under it.
  - The summary's `lint` (linear fades, frozen clouds, duplicate textures) and `frameStats` (near-white pixels
    per frame) are a free second opinion on blown-out effects.
- **Reading a place or model's numbers**: Lune 0.10.4 fails on recent files ("Property Attachment.Tags should be
  SharedString"). Two ways round it: `ree run --harness dump.luau --seconds 0.1 --offline --mount
  "ReplicatedStorage/Fx=<file>.rbxm"` mounts a `.rbxm` (not a `.rbxl`) for a harness to walk; for a `.rbxl`, copy it
  without its `Tags` PROP chunks (they are LZ4 or ZSTD blocks: decode, drop, write uncompressed) and Lune reads the
  copy. The scripts are in `tools/vfx/`: `dump_harness.luau` (ree), `striptags.luau` + `dump.luau` (Lune),
  `ror_scene.py` (what every preview scene shares: a kit's templates by name, the stand-in avatar, parts, lights,
  Highlights, and the writer that swaps group image ids for local PNGs), one short `preview_<weapon>.py` a kit
  (greatshield, boots, shovel, revolver) that only lays out its scenes, `compile.luau` (the 200-local
  check). `planvfx.md` holds the next VFX passes.

### What 27 open-source anime VFX packs do (4,778 emitters measured)

The pack the user sent (`~/Downloads/VFX`: Marcid's, Jaxelos', KILOFUNCTIONS-style kits) is smooth anime VFX, not
pixel art, so the textures do not carry over. The craft does:

- **The weight is ON the body, at body height, not on the floor.** Every move wraps its caster: flames and
  sparks off a box round the body, spirals and trails round the torso, a light at the chest that lights the floor
  round the feet. The floor gets a scorch or a ring as a secondary layer. This is the user's critique of this game
  (2026-11-12: "they are all like in the ground"), and the reason section 23's Rally and Comet got bodies.
- **A buff is a welded aura for the buff's length** (goldvowflame `halfbakedvowaura`): six emitters on a box at
  the lower torso, 3.5 to 8 a second each, lifetime ~0.85 s, Drag ~4, Transparency in and out (1, 0.18 at the
  middle, 1), sparks and flame tongues as VelocityParallel streaks, plus a PointLight, all switched off after 3 s
  and left to drain.
- **Bursts are many single-particle shots**: 94% of emitters are disabled and fired by EmitCount (mostly 1 or 2)
  with EmitDelay. Lifetimes are short (0.1 to 0.6 s), sizes big, Brightness high (10 to 40 with LightEmission 1),
  LightInfluence 0.
- **Contrast layers**: a dark trail (#26183d, LightEmission 0, Brightness 1) runs under the bright ones, and some
  emitters use LightEmission -1/-2 to darken behind a glow. The bright reads because something dark sits under it.
- **The impact frame**: at the hit, a white-outlined Highlight on the caster plus a ColorCorrection (Contrast 5,
  Saturation -1, Brightness 1) for one 1/16 s frame, then inverted (Contrast -5) for one more, then gone.
- **Hard steps inside a particle's life**: Transparency sequences like `0@0 0@0.2 1@0.2 0@0.2 ... 1@0.6` make a
  particle flicker on and off. That fits pixel art (no smooth fade) better than anything else in the pack.
- **Orientation does the shaping**: VelocityParallel for streaks, flames and slashes (with Squash 0.3 to 3),
  VelocityPerpendicular for rings on the floor, FacingCamera only for glows and puffs.
- **Camera**: CameraShaker `ShakeOnce(2.85, 25, 0, 0.45)` on a thrust, and lights tweened down Quad Out in 0.2 to
  0.4 s.

### Built from it (2026-11-12; seen in ror previews, not yet by the user in game)

`GreatshieldFx` (section 23) got a body layer, templates in `GreatshieldFx.Body`, sprites `pillar`, `chevron`,
`wisp`, `bowshock`, `tailpuff` (`Assets/effects/greatshield`). The body pieces now live in one shared module,
`src/Survivors/Client/Weapons/BodyFx.luau`, which every weapon's Fx calls with its own `Body` templates and tint:
`NewRig(spec)` / `Show` / `SetShare` / `SetLight` / `EndRig`, `AuraStart(spec, root, seconds?)` / `AuraStop` (a rig
kept on a body for a buff, flashing its light at the cast, leaning back off the body while it runs), `Flash(model,
fill, outline, BodyFx.Flashes.Buff|Hit)` and `ImpactFrame(root, tint)`. A ride may carry its own `Tint` (dirt off a purple
aura); `NewRig(spec, tint?)` / `AuraStart(..., tint?)` take a tint over the spec's, and `SetTint` / `AuraTint`
recolour a running one. A rig's look is one frozen `TBodySpec` at the
top of the weapon's Fx (name, templates, box size, rides, tint, and only if it earns one a `Light`); it steps itself
on game time.

- **Body rigs**: a hidden anchored box written over the root every frame, its emitters throwing out of its volume
  along +Y, and a PointLight (range 14) that lights the floor round the player. Rates follow the Particles and
  Weapon Opacity settings; on its end the rig stops throwing, the light steps out in three, and the part goes after
  0.9 s so nothing vanishes.
- **Rally on every ally**: a 12-stud column of light up through the body (FacingCameraWorldUp so it stands
  upright from any camera), five buff arrows, the body flashing gold through a Highlight in four steps, then flames,
  arrows and motes licking off the body for the speed buff's length (5 s times the wielder's Duration, as the
  server grants it). A recast tops the time up.
- **The Comet on the runner**: a meteor head (VelocityParallel, locked, so it points the way they run; the sprite is
  drawn pointing RIGHT, section 13: drawn pointing up it came out sideways in game) standing at
  the chest, a tail of puffs and speed lines thrown back off the chest, a blue light, the body flashing white at the
  start and at every slam, and two hard frames of ColorCorrection on the runner's own screen at a wall slam. The
  floor corridor and the flat head stay underneath.
- **The chomp's Jaws leave no footprint** ("the actual jaw already does the job"); the Fangs look keeps it.
- In ror: the first buff flames came out white blobs spawning inside the torso. The box is now wider than the body
  (3.6 x 4.6 x 3.6), ZOffset 2 pulls them in front, and Brightness 1.7 keeps them gold. The comet's first tail was
  small rings that read as bubbles: puffs are now 2.2 (4.4 studs) and open into a ring only in their last half.
- **A ring round the torso** (the Shovel's Whirlwind, 2026-11-12): a flat sprite (VelocityPerpendicular off a tiny
  +Y speed, LockedToPart) on a slim box (0.4 x 2.4 x 0.4) with no lean, so every band is centred on the body at
  some height between the hips and the chest and lies level. The turn is drawn into a looping flipbook
  (FlipbookStartRandom, so the bands are out of step), never done with a random Rotation, which would turn the
  texels off the grid. Each band's life is hard Transparency steps (the flicker steps below), not a fade. Drawn at
  32 texels for a ~5.5-stud ring: 0.16 studs a texel, the kit's own texel; a 64-texel ring would have been twice as
  fine as everything round it.
- **A kit that recolours its abilities recolours their auras too**: the Shovel's ult turns the kit purple, so a
  running aura is retinted with `BodyFx.AuraTint` (and back), and dirt or rock rides carry their own `Tint` so they
  stay earth-coloured on a purple body.
- **Thrown things on a body must stay small and few**: anything over ~1 stud or past ~5 a second round the torso
  hides the avatar it is meant to dress (the Shovel's lifted clods).
- **The player's outline is shared: an ability recolours it, never adds one.** Every player has an AlwaysOnTop
  outline in their player colour (CharacterController). `src/Survivors/Client/Utils/PlayerOutline.luau` owns its
  colour as named layers: `PlayerOutline.Tint(character, key, color?, tweenInfo?)` puts a layer on (or recolours it in
  place), nil takes it off, the newest layer shows, and every change blends (0.35 s ease by default) instead of
  snapping. Downed stone is a layer too (HealthController, on its own 2 s), so a buff ending under it never shows
  through, and revive never "restores" a buff's tint that was up when the player went down. Any ability that wants
  the body to read as its colour uses a layer named after itself. Probed 2026-11-12: blends in (half-way at 0.1 s),
  purple on Blend, stone on top when downed, back to the player colour on revive.
- **A sprite whose frame is an even number of texels has its centre BETWEEN texels.** Draw every part on whole texels
  the same distance either side of it (offsets of k + 0.5), or rounding shifts some parts half a texel and the user
  sees them off-centre. Check a frame's mask against its own mirror in numpy before uploading.
- **Both ends of the size range bite**: the Shovel's clods (over ~1 stud) hid the body, the Revolver's first embers and
  shards (0.3 to 0.35 half-size, about 0.6 stud) vanished at the game's distance. Body sprites sit between ~0.45 and
  ~0.55 half-size; a glint that winks can go to 1.
- **A probe waits on game time, not only at its start**: the Revolver probe's first run saw every ended rig still
  there 3 s later; a level-up pause had frozen game time mid-probe. Counting `Heartbeat dt * TimeCore.TimeScale`
  showed all of it gone 3 game seconds after the end.
- **ror does not show VelocityParallel the engine's way**: the comet head looked right in ror and pointed sideways in
  game. Check a VelocityParallel sprite's direction in a playtest.
- **Bastion's cast** (2026-11-12, probed in a playtest, unseen by the user): `GreatshieldFx.BastionCast(wielder)`, on
  every client as the ult goes active: Rally's 12-stud pillar in the dome's blue up through the caster, a few motes,
  and a `Flashes.Gather` Highlight. No new sprite or template. The slam half a second later (`DomeStart`, now given the
  caster's root) adds the impact frame on the caster's own screen; the dome, runes and floor slam are unchanged.
  - **Time a rising flash to the wind-up it fills**: the Gather's brightest step is its 7th, at 6/12 = 0.5 s, which
    is `ULT_DOME_RAISE_DELAY`, so the body peaks as the dome lets go and the Gather's own fade is the release. No
    second Hit flash at the slam: two Highlights on one body at once.
  - **A bench's lead reads the server's constant** (`DomeLead = GreatshieldShared.ULT_DOME_RAISE_DELAY`), so the
    bench and the game cannot drift apart.
  - Probe: Highlight up at the cast, the ColorCorrection there at the slam and gone after, no errors. The fill held at
    its first step for 0.7 s and then stepped at 12 a second: the solo run's start pause (game time), the same trap as
    the Revolver probe. The probe's slam was on wall time, so it fired early there; in game both wait on game time.

### The Boots on the body (2026-11-12; previewed in ror, probed in a playtest, unseen by the user)

Templates `BootsFx.Body` (and `Burst.Ribbons`), sprites `ribbon` (a wind ribbon pointing RIGHT) and `updraft` (a wisp
of wind rising, row 0 up) in `Assets/effects/boots`; preview scenes `tools/vfx/preview_boots.py`.

- **Shockdash**: wind ribbons and long speed lines tear back off the chest for the whole dash, and where it stops a
  fan of ribbons is flung on ahead at chest height. The floor gusts stay. No flash and no light (below).
- **Momentum**: sky-blue wind rises off the body (updrafts, ribbons, motes) for the buff, leaning back off the runner
  while they move. No flash and no light.
- **The user's review (2026-11-12): Stampede and Fault Line good; the flash on Shockdash and Momentum rejected** ("it
  feels like a lot", "the floor of the game is already green but the abilities are cyan, blue, sky blue"). The first
  build flashed a white/sky Highlight on the dash and a green one on Momentum, each with a PointLight. On the map's
  green grass a sky or green light turns the floor round the player green, and a green Highlight on top reads as a
  loud green flash off-palette for the kit. Lessons, for every weapon:
  - **A body flash and a floor light are for the big moments only** (an ult's cast, an eruption, a slam), never on an
    ability that fires every few seconds.
  - **Keep a kit to its palette.** Boots are sky, cyan and blue (plus the ult's gold and Fault Line's magma); a green
    accent does not belong even where an old floor tint used it.
  - **Check a tint against the floor it lights.** Green grass eats green, and turns sky and cyan light green; a
    PointLight earns its place only in a warm tint (gold, magma, orange) or a strong blue.
- **Stampede**: the body flashes gold and the wielder's own screen takes the impact frame (the kit's hardest blow),
  then a dense gold aura (updrafts, rising sparks, motes, a bright light) sits low on the body for the ult. Every
  Stampede step now kicks its rocks from shin height, so steps read from far.
- **Fault Line**: embers rise off the runner while the ground tears behind them; the body flashes magma as it erupts.
- Rejected before and not brought back: an afterimage of the body (Momentum's "Afterimage" lost its bench, section 20).
- Probe (2026-11-12): every rig, aura and Highlight appeared and all were gone 3 s after the stop. A solo playtest
  starts paused (TimeScale 0), so game-time effects hold until it runs: wait on `TimeCore.TimeScale > 0` in a probe.

### The Aura on the body (2026-11-12; previewed in ror, probed in a playtest, unseen by the user)

Templates `AuraAbilities.Body` (`Rise`, `AuraMote`, `Umbra`, `Nova`, all on the kit's existing `spark` and `mote`
sprites, no new images); preview scenes `tools/vfx/preview_aura.py`. The disc stays the floor's; the body now shows
whose power it is. Body moments are beats like the floor's (`BodyAura`, `BodyBurst`, `BodyFlash`, `ImpactFrame`), so
they keep the ability's timing, stretch with Duration and are cancelled with it. A body beat has no `Where` (it lands on
the wielder), and its look comes from the effect (`Body`, `Burst`, `Outline`), so a beat line says only when and in
what tint. `AuraAbilityFx.Start` takes the wielder's root; the bench stands a copy of the local avatar in each disc and registers its copied outline, so the
body and the outline show there too.

- **Resonance**: orange streaks and motes rising off the body for its length, and the outline orange. No light and no
  flash (it comes back every 24 s).
- **Singularity**: the outline goes violet at the cast; the body fills with violet as the gather closes (a Highlight
  whose fill RISES over half a second, `BodyFx.Flashes.Gather`, then lets go); when the vortex lands a violet aura
  with a light (2, flashing 6) burns on the body; the light flares again as the vortex collapses; at the blast the
  body flashes pale violet, the wielder's screen takes the impact frame, and a starburst of streaks is thrown off the
  chest (`BodyFx.Burst`: a spec's Rates read as counts, emitted once).
- **The contrast layer, first use**: `Umbra`, dark violet motes (unlit, LightEmission 0) sinking slowly off the body
  under the bright streaks. In ror they are what makes the violet read as a void instead of a sparkle.
- **An ult's aura needs about twice a buff's rates**: at a buff's (Rise 18) the Singularity read thin in ror for an
  80 s cooldown; it is Rise 26, Umbra 9, motes 8.
- **No death hook needed for ability marks**: the server stops every ability when its wielder is downed or stunned
  (`AbilitiesService.StopAllAbilities`), so the client's stop handlers run. Only taking the weapon off can leave no
  disc for a stop to find: `AuraAbilityFx.EndBody` on `WeaponsCore.OnWeaponRemoving` takes the auras and outline
  layers off.
- **Where a kit already schedules beats, the body rides them.** A second timer for the body would drift from the
  floor's on a pause or a Duration stretch; one list keeps the flash on the frame the vortex lands.
- **A bench needs a body to judge body effects.** A disc alone showed nothing of this pass; each bench cell now
  stands a copy of the local avatar (scripts, sounds and weapons stripped, root anchored), and registers the copy's
  Highlight with `PlayerOutline` so outline colours show. The copy now lives in `Utils/benchStandIn.luau`, shared
  with the Mortar Hat bench (section 24); only the Shovel bench's `newRunner` is still its own.
- Probe (2026-11-12, on game time): Resonance's and the Singularity's auras appeared, the outline went violet at the
  cast and pale violet at the blast, the burst rig appeared, and everything was gone and the outline back to the
  player colour 3 s after each stop and after `EndBody`. Resonance's orange outline was not seen: the probe cast it
  before the character's outline was made. A probe that tints the outline must wait for the character's Highlight
  (PlayerOutline ignores a body it has not registered).

## 26. Feedback beside the character: the style meter's lessons (2026-11-12)

The style meter (UI.md, "the style meter") is HUD drawn next to the character, so it shares the character's space
with the effects in this file. What the user's first round taught:

- **Clear the character at the camera's closest zoom, not the default one, and measure where it really is.** The
  camera holds the character left of the screen's centre (its body about 87 units out at the closest zoom), so 38 and
  then 70 units off the centre both touched it. The meter now aims for 120 units and keeps out of each side's HUD
  strip (100 units left for the teammate column, 118 right for the objective panel). Measure from a playtest
  screenshot at the closest zoom before picking an offset.
- **Borrow another screen's look, not its voice.** The rank-up screen hit reuses the box reveal's `rarityImpact`
  (edge bands in the rank's colour, SSS's light columns, confetti) and that was wanted. Playing the chest landings
  with it was not: a sound that means "you got a rare item" loses its value if a rank up plays it every minute.
- **A camera kick on a HUD event stays small.** Rank ups jolt with Kick 4 and Shake 1.5 at most (a quarter of that at
  D), well under a Nuke (Kick -10, Shake 5); it goes through `CameraController.Jolt`, so the Screen Shake setting and
  haptics apply.

## 27. Last Wave: the Shotgun (built 2026-11-15; looks picked the same day)

`src/Survivors/Client/Weapons/ShotgunFx.luau`, called from ShotgunClient (every Blast event, the Stomp's rise, dive and
landing, Buckshot and Overdrive's edges); templates in `ReplicatedStorage.Effects.ShotgunFx` (`Burst`, `Pellet`,
`Body`); the kit is `Assets/effects/shotgun/` (its README); preview scenes `tools/vfx/preview_shotgun.py`. Before it,
the pellets were the Revolver's old bullet with a smooth Trail, the landing was `VisualEffects.ShowExplosionEffect` (a
ForceField sphere), and the muzzle, Buckshot, the Stomp's flight and Overdrive drew nothing.

- **The user's picks (2026-11-15)**: Muzzle **Star**, landing **Shockwave** "but add the shockwave part of the aura
  too", Overdrive **Inferno** "but make the fire look like actual fire". The losers (Breath, Powder, Eruption, Fissure,
  Furnace), their sprites and templates, `ShotgunFx.Styles` and `shotgunstyle` are gone; the bench is one piece a
  pair: since the gun got its motion (Animations.md 15, `ShotgunMotion`), a Before stand with the old bump beside an
  After one.
  - **The landing borrows the Aura Shockwave's dome** (section 18's shell: `ReplicatedStorage.Effects.AuraAbilities`
    `ShellMesh` and `ShellSkin`), pooled in ShotgunFx, tinted the shot's colour, swelling in hard steps with the
    server's ring (its grow time is the ring's `radius / speed`) and stepping out over 0.25 s. Fire embers are thrown
    up off the impact too.
  - **Real fire is drawn in colour, not tinted.** A crimson-tinted tongue read as a red shape. `flame` (32 texels, 4x4
    one-shot) and `lick` (16, 2x2) are heat fields (a teardrop plus value noise scrolling up three texels a frame, so
    licks climb, split and tear off the tip) mapped to five fire colours, white-hot core to an ember-dark dithered
    rim, and cooling a band at a time to smoulder out; there is no Transparency step, each flame's life is its
    flipbook. Their template Color is white and the rides carry a white tint, so BodyFx never recolours them; the
    embers ride orange, the soot keeps the crimson's dark shade, and the outline, light and flash keep Overdrive's
    crimson. Layered as real fire is: big flames on the body, loose licks climbing off them, embers, smoke over it.
  - **"The bullets don't come out of the shotgun"**: they never did. Before this pass (git HEAD) the pellets started at
    the root plus `MUZZLE_Y_OFFSET`, as they still do; the user said to leave it so if it was like that before. Only the
    muzzle star leaves from the barrel (`MuzzleOf`).
- **Shots are tints**: orange the plain Blast, brass under Buckshot, crimson under Overdrive (which wins when both are
  up). Every muzzle, pellet, kick and jet takes the shot's tint; the hull stays shell red, the smoke grey.
- **On the body (VFX.md 25)**: every Blast throws speed lines and a puff down the shot off the chest as the recoil throws
  the body back (no light, no flash: four charges); Buckshot flings hulls off the chest, then hulls, brass glints and
  motes rise for its length with the outline brass; the Stomp's rise has a flame jet off the feet (a rig aimed down, so
  ShotgunFx keeps its own trails beside BodyFx's up-only auras), the dive a tail of flame and lines streaming up
  behind; Overdrive (the ult) flashes the body crimson, throws a starburst off the chest and keeps an aura with a warm
  light (crimson holds on the green floor) and a dark soot contrast layer, the outline crimson.
- **The landing is the kit's hardest blow**: the slammer's own screen takes the impact frame and a warm light flashes
  over the floor. No Highlight: the Stomp comes back every 20 s (the Boots review's rule).
- **The landing sheets are timed to the server's ring**: their front reaches the edge on frame 8 of 16, so the sheet's
  Lifetime is written per burst as `radius / speed x 2` (at least 0.45 s): a high slam's fast ring lands fast.
- **Pellets are Beams on pooled Terrain attachments**, head at the damage front (PELLET_SPEED), a 7-stud tail that
  closes on the head over the last 30% of the range, so a pellet runs out instead of vanishing. Capped at 160 in flight.
- **The muzzle is found, not assumed** (section 19's lesson): `ShotgunFx.MuzzleOf` takes the end of the gun mesh's
  long axis away from the wielder, so it holds whichever way the mesh was authored.
- **In ror** (2026-11-15): the breath's first tongues merged into one blob (thinned and spread to 17-degree steps),
  the hull's 45-degree frames read as crosses (quarter turns only), the plume's cap read as a falling T (lumps spread
  and lifted), the white birth hid the shot's tint (muzzles white for their first 18% only), and the plume came out a
  speck next to a 24-stud ring (now sized off the radius in code).
- **Probe (2026-11-15, playtest)**: the bench put up 9 stands with no errors; pooled attachments grew as templates were
  first used and held at 584. The Blast, Stomp and Nuke events fired from the server at the client raised no errors,
  but the run was held on its opening reward pick (character immobile), so the launch and the gun's muzzle position
  were not seen. **Not seen by anyone in game yet**: VelocityParallel directions (the breath, the jet, the kick lines;
  section 13 says ror can be wrong there) and whether `MuzzleOf` lands on the barrel.
- The place held an orphaned `ShotgunFx` folder from an earlier attempt (Muzzle, Ride, Burst, Body; no code anywhere
  used it). Parked in `ServerStorage.ShotgunFxOrphan`, then deleted at the user's word (2026-11-15).
- **Templates in the place (2026-11-15)**: Model 133816192676359 (`ShotgunEffects.rbxmx` with the picked looks, the
  fire's `flame_px` / `lick_px` images 90592480621077 / 140023521626905), swapped into `ReplicatedStorage.Effects`.
- **Sounds**: `Assets/Sounds/Review/Shotgun/` (rounds and picks in its README; Sounds.md "Shotgun"). Save the place after the template swap.

## 28. Last Wave: the way to the tutorial's altar (built 2026-11-16, unjudged, unplayed)

`Client/Utils/GuideTrail.luau` (the arrows) and `guideToAltar` in `InGameTutorialController` (the arrows plus the
spotlight on what to press). Every number is in their `Tune`s.

- **The arrows are the UI kit's chevron laid on the floor**, the fill floating 0.3 studs over a dark see-through shade
  a texel down and right, as the glyphs cast theirs. Each is ONE closed voxel mesh (`Effects.GuideArrow`, from
  `Assets/effects/guide/make_guide_arrow.py`, only the faces touching air): the first cut built it from a Part per
  row of texels, and the user saw every join through the see-through shade. The bake is pre-turned half a turn for the
  importer (Models.md 3). They lie on the floor's normal (section 6), drawn at 12 Hz on the show clock.
- **The trail stays put while it is walked**: each arrow keeps its distance from the altar (every 5 studs out from its
  edge), at most 9, the nearest at least 3 studs ahead of the character. Walked past, an arrow is picked up (it jumps,
  flashes white and shrinks, with a tick a semitone over the last while they come in a run); walking off deals new ones
  in at the far end. A light runs down it toward the altar, each arrow hopping off its shade as it passes.
- **Arriving is the payoff**: the arrows left pour into the altar, nearest first, accelerating; as they land it hops,
  its light flares and a chime plays (the first time also a small Aura ring off its foot), and the spotlight irises onto
  what to press. Walking out of reach clears the spotlight and deals the trail out again.
- **The hint follows a billboard**: a billboard's children have no screen AbsolutePosition, so `spotlight` takes a
  `TScreenBox` (a `GetBox` read every frame); `InteractableUI.GetHintBox` works the prompt's key and Slab out from the
  adornee's screen point and the billboard's AbsoluteSize. On touch it lights the interact button instead. The word
  ("HOLD E", "HOLD IT") and the target are re-read when the input or a binding changes.
- **Sounds are stand-ins, owed a listening round**: deal `TicketTick`, pickup `ScoreTick`, pour `MagnetCollect`,
  arrival `RaceCheckpoint`.

## 29. Last Wave: the tutorial masks' wall (built 2026-11-16, Picket picked)

`Client/Utils/ShowWallFx.luau`, raised by `raiseFence` in `InGameTutorialController` round the altar and the masks'
fight; the kit is `Assets/effects/showwall/` (its README). It replaced the Bastion dome there: a camera zoomed out past
the dome saw nothing, and the dome's radius had been pushed past the camera's reach to stop that, which made the
stage huge. The wall is open on top, so the ring is the stage's own size again.

- **Picket, a fence of light** (bars with diamond tips, a pulse up each, a lattice between), picked over a glow,
  flames and scan bands. The user read it as bars, which is what a wall the masks shut you in with should be.
- **A ring of narrow upright segments, a sprite on each face.** The inside face alone left the near side invisible
  whenever the camera stood outside the ring (seen in ror). A segment is an eighth of a frame (8 texels, 2 studs), the
  next segment the next slice, so the art runs on round the ring. Narrow because each stands on the floor under it:
  16-stud panels all at the centre's height ran into a slope or hung off it (user, 2026-11-16). A segment's foot is the
  lowest of the floor under its middle and two ends (at most 1.5 studs under the middle, or one on a cliff's edge sank 28), so on a slope it sinks a little rather than float; the probe
  starts 40 studs up to find a slope's top.
- **Steps become a ladder.** Where the floor steps up (a cliff, a steep bank) the wall broke off at the step, the
  higher run standing back on top with bare cliff between (user, 2026-11-16). The segments before a step now climb
  toward its top at most 1.5 studs a segment, and the space under a raised segment is filled with fence: the frame's
  floor line on the ground, then its bars-and-lattice band (rows 36-43, which tile upward) stacked to the segment's
  foot. Its floor line in the air reads as the stair's tread. The stair holds the loop's first frame and follows only
  the drawn moments (surge, breakup): by a 28-stud cliff a 62-stud ring built 400-700 stair pieces (playtest
  2026-11-16), and animating them was 7,600 writes a second for a pulse in a few rows.
- **The frame's bottom gutter is sunk into the floor.** Standing the part's bottom edge on the floor left the art 2
  texels (half a stud) up in the air (user, 2026-11-16).
- **Everything on the floor is put on the floor where it lands.** The light the wall throws is a strip per segment on
  the floor under its own middle, along that floor's normal (section 6). A push's floor wave sat at the character's
  height (the root, 3 studs up) until it raycast the floor at the wall's foot.
- **Sheets stacked DOWN, not across.** A segment tiles into the next one, so a frame's left and right columns run to
  the image's edge; the gutter (section 6) is kept top and bottom only.
- **Every moment is drawn** (section 17): the surge on a push, the raise's overshoot and the break's flare are frames
  where the light climbs into clear rows over the rest pose, burning hotter; both endings are dither breakup frames.
  The code only swaps frames and crops a frame from the bottom (coming up out of the floor, shrinking back), so a
  texel stays a quarter stud. A first cut stretched the panels for the surges and alpha-faded the ends.
- **Dim tones and single-texel dither read as dark noise at the camera's distance** (ror, 2026-11-16): the masks'
  purple times the kits' 0.55 / 0.35 tones looked like shade on the grass. The wall uses 0.88 / 0.74 and dithers in
  2x2 blocks.
- **The juice:** it comes up in three steps in a sweep from the character's side round to the far side, flashing, then
  overshoots; a push surges the panels round it in a ripple both ways (70 degrees out) with sparks, shards, streaks and
  a small hex wave off the spot; the break flares, bursts (floor wave, shards and motes all round) and breaks up.
- **Probed in a playtest** (2026-11-16, before the segments): it builds and runs without errors in all four looks. The solo run starts
  paused on its first choice (`TimeScale` 0), so a probe must hold game time at 1 or nothing moves. The motion itself
  was not traced: Studio stopped answering mid-probe.

## 30. Kill All The Monsters: the house look, and how to make the next effect in it (the pistol's shot, picked 2026-11-20, unplayed)

This is the first effect in this game's own look and the recipe for the next ones (enemy hits come next). It took
five rounds to find; everything below is what would have made it one.

Where it lives: `src/Game/Client/Utils/gunFx.luau` (called from WeaponController for a gun whose data names a kit,
`TGun.Fx`; its `LOOKS` says how many each layer of a kit throws), the pooled parts in `Client/Utils/motorParts.luau`,
the thrown bricks and casings in `Client/Utils/thrownPieces.luau` (shared with the enemy bursts, section 31),
templates in `ReplicatedStorage.Effects.PistolFx`, sources and every number in `Assets/effects/pistol/` (its README).
Bench: `pistolbench` (Before, the pick, and the four looks that lost, `Client/Utils/pistolBenchLooks.luau`).

### What the look is

- **A toy's, and the pieces are the point.** The maps are stud bricks, so whatever is shot throws real stud Parts of
  its own colour that bounce and sink, and the gun throws a casing. The user: it should feel like the pieces come out
  of what is shot, enemies too, like blood, "disassembling" them piece by piece. Light frames the pieces; it never
  covers or replaces them. **Never retune the bricks or the casing in passing: they were liked first and stayed.**
- **The particles are glowing PIXELS, like Last Wave's**: plain hard-edged squares, never turned, tinted and lit by
  their emitters, moving softly (they swell as they fly out, hang, pop). Rings are square. The game is not pixel ART
  (models, maps and UI are not); its effects' particles are pixels.
- **One hue a thing**: the pistol is gold (255, 214, 20), white-hot at birth; what comes off a surface takes that
  surface's colour, lightened 20%.
- **What lost, in order** (do not build these again): lens stars, fire and Beam tracers ("too serious"); outlined
  comic pictures, a POW burst and cartoon puffs ("realistic images like a mini explosion"); a candy ball of a new
  colour a shot and a stud plate for a bullet; cross sparkles with spark streaks; toy stars; literal toy plates drawn
  from above ("not literal studs, go with pixels"); round rings with glow balls were liked for their MOTION and
  asked for in squares; a plus-shaped pixel mote ("was not in the bubbles variant").

### The recipe

1. **Reuse the five sprites** (`Assets/effects/pistol`, white, 256 px a frame, drawn at 4x and box-filtered, 3 clear
   texels round each): `soft` (light with no edge), `block` (one glowing pixel: a solid square a third of its quad
   in a soft glow), `frame` (a thin square ring, crisp outside, soft inward), `fatframe` (a fat square ring with a
   narrow glow), `puff` (four soft round puffs, the one thing not light). Their Image ids are in that folder's
   `images.json`, uploaded by 34796361: a new effect points at them, nothing is drawn or uploaded. Draw a new sprite
   only for a shape the user asked for.
2. **Build the burst from these layers** (numbers are the pistol's wall hit; `make_pistol_effects_rbxmx.py` has each
   as a function to copy):

   | Layer | Sprite | Life | Size (studs) | Lit | How it moves |
   |---|---|---|---|---|---|
   | `Wash` | soft | 0.14 to 0.18 s | 5 to 6.5, flat on the surface | additive, 50% see-through at birth | lies there and fades: the pool of light |
   | `Core` | block | 0.07 to 0.09 s | 2.2 at birth to 0.26 | additive, Brightness 1.6 | none: the white-hot heart, biggest on its first frame |
   | `Frame` | frame | 0.18 to 0.22 s | 0.57, 2.66 by a quarter of its life, 3.8 | additive, Brightness 1.5 | flat on the surface (VelocityPerpendicular), lined up with the studs |
   | `Pixels` | block | 0.22 to 0.4 s | 0.6, 1.25 by a quarter, 1.0, then 0 (envelope 30%) | LightEmission 0.5, Brightness 1.3 | 7 to 10 thrown at 14 to 32 studs a second in a 72 degree cone, Drag 5, rising at 5 |
   | `Puffs` | puff | 0.4 to 0.6 s | 0.3 to 0.84 | not light | 2 or 3 drifting up at 3 to 7, Drag 5 |

   Off a muzzle, the rings are two `fatframe`s puffed down the barrel (2.2 to 3 studs, 0.1 to 0.15 s, 12 and 28
   studs a second) and the pixels fly in a 36 degree cone. On a body the ring is 2.2 studs and there is no wash.
3. **Throw the pieces as Parts**: stud Parts (`TopSurface` Studs, `BottomSurface` Inlet, 1 x 0.4 x 1 plates and a
   1 x 1.2 x 1 brick) in the colour of what was hit, 3 a hit, thrown 9 to 16 studs a second off the surface with 10
   up, falling at 85, bouncing twice (0.42 of the speed kept), then sinking by their whole size. Every Part is a
   `motorParts` mover (an anchored base at the origin, the part on a Motor6D, so Transform is its world CFrame and
   the engine simulates nothing; parked far away when free; stretched through SpecialMesh.Scale: performance/01, 07).
   What flies is a Neon Part half a stud across or more with hard edges: a round-ended streak read as a beam.
4. **Light the world for a blink**: a PointLight for 0.05 s where the blow lands, within 90 studs of the camera only.
5. **Write it as a kit**: templates in `Effects.<Kit>` (the look, all of it), a `LOOKS` entry for the counts (a
   NumberRange a layer, so no two bursts match), bursts taken in turn from 6 copies of the template, tinted per hit.
   Budget it before it is seen: a cap on parts that never grows (48 pieces), nothing past 120 studs, fewer pieces as
   the cap fills, at most 8 bursts a frame. The pistol at 60 shots a second costs 2.5 ms of engine calls a second
   in ree.
6. **Make it, look at it, hand it over**: `make_pistol_effects_rbxmx.py`, `make_pistol_effects_luau.py`, the user
   pastes the `.luau` into the Game place's command bar and saves (nothing else gets templates in: Open Cloud takes no
   `.rbxmx` as a Model, and Tripwire's `run_luau` runs in the cloud's copy of the place). `preview.sh` renders the real
   module in ror; read the quarter-speed video frame by frame before reporting.

### Rules that each cost a render or a round

- **Punch is the first frame**: a flash is full size and white-hot the frame it is born (HOT for its first eighth,
  then its colour) and shrinks away in 0.1 s. A ring does 70% of its growth in its first quarter. One that grows in
  reads soft.
- **Fast in, slow out**: flash 0.1 s, rings 0.1 to 0.2 s, pixels 0.2 to 0.4 s, puffs 0.5 s, bricks over a second.
- **Additive gold over a bright floor or sky is white.** Glows and thin rings stay `LightEmission` 1; a SOLID shape
  (a pixel, a fat ring) is 0.5 in a deeper gold (255, 165, 0). At 0.3 it read as a dull sticker; at 1 it washed out.
- **A pixel is never turned**: no Rotation, no RotSpeed; a ring's turn comes from its attachment, laid on the
  surface's own axes (`facing` in gunFx).
- **A ring is no wider than the body it is on** (2.2 studs), or it hangs in the air beside it. A fat ring's glow
  stays narrow, or it fills its own middle and reads as a pane of glass.
- **A glow sprite's solid core is a third of its quad**: a pixel half a stud across is `Size` 1.25.
- **Gold round shapes out of a gun read as the kill coins.**
- **A Color3 is no table key**: it is a userdata, so two equal colours are two keys. gunFx's per-surface tint cache
  never hit and grew a hit at a time until it was keyed by the colour's packed bytes.
- **Find a kit's templates once.** A shot looked eight of them up by name; they are one record a kit now.

### Working it out with the user (what would have saved the rounds)

- **Bench shapes, not tints**: the round that got a pick stood four looks that differed in the SHAPE of the light on
  one gun, bricks and casing identical. Stand Before beside them.
- **"Like X but squares" is X with every circle made a square, and nothing added.** Keep the picked look's layers,
  counts, speeds and timings and swap the sprite. The plus mote and the second drawing were sent back.
- **A pick does not delete the bench.** The losers were deleted on the pick and asked back the same day ("I still
  want to see the bubbles, or others"). Take them out of the game's module (they are kits of their own, their counts
  in the bench's file) and leave them standing until the user says to drop them.
- **Say how an ambiguous ask was read**, in one line, and build it: "the studs coming out of the gun" was read as
  every stud particle, and said so.
- **Glowy, juicy, punchy, playful** meant: additive light and a lit wall; a long tail after a hard first frame; a
  big white first frame; simple shapes and floaty pieces. Not more detail.

### In ror and ree

- A camera 6 studs from the muzzle made a 4-stud flash fill the screen: preview from 10 studs or more.
  `ror video --speed 0.25 --fps 60` is how a bullet and a flash's few frames are read.
- **ror draws a pooled part in the sky for one frame when it is taken again**: its video blends from the parked spot
  to the new one. ree shows the joint never between the two (a probe printing every mover's Transform a frame), so
  it is the renderer, not the game.
- Mount the kit's file as `ReplicatedStorage/Effects` and the module's folder beside it; gunFx needs
  `ReplicatedStorage/Shared/Utils` too (sightCast). `--context '{"Storm":true}'` prints the cost at 60 shots a
  second, `'{"Bench":true}'` stands every look.
- **Not seen in game yet**: how the gold holds under the place's own bloom, and the rings puffed down the shot from
  the player's own camera.

### The enemy's hit

Built the same day from this recipe in one pass: section 31.

## 31. Kill All The Monsters: the enemy bursts (built 2026-11-20 from section 30, unjudged, unplayed)

What a blow does to a body, for every weapon: `src/Game/Client/Utils/enemyImpacts.luau` off the server's damage and
kill events, templates in `ReplicatedStorage.Effects.EnemyFx`, sources and every number in `Assets/effects/enemy/`
(its README). Bench: `vfxbench` stands one body of every enemy type looping three hits, a kill, a vanish and an
overkill through the game's own module. It replaced the anime kit (section 15), whose templates were never in this
place.

The user's brief was one sentence said before it was built: the pieces should come out of what is shot, enemies too,
"like blood", so the player feels they are "disassembling the enemies piece by piece". So the PIECES are the effect
and the light frames them.

| Rung | When | Light | Pieces (a 5 stud body) |
|---|---|---|---|
| Hit | every blow in view, 4 a frame | a white-hot pixel (1.9 studs, 0.08 s), 6 to 9 skin pixels in a 55 degree cone | 2 or 3, skin or top, 3 to 9 studs a second across the floor and 11 to 17 up |
| Kill | the killing blow, 4 a frame | a hit's | 5 or 6, thrown harder |
| Overkill | a blow worth 4x max health, no corpse | a 4.2 stud pixel in a bloom, a flat square ring to 9 studs in 0.3 s, 16 to 22 skin pixels and 6 to 9 white flecks all round, puffs | 13 to 16, one from each slice of the body in what it wears |
| Vanish | a body that cannot fall, over the kill | 7 to 9 pale puffs, a few pixels | 4 or 5, dropped where it stood |

What section 30 did not already say:

- **A body's colours are data** (`TEnemy.Colors`: `Skin`, `Top`, `Legs`), read once off the model's texture (its
  largest flat areas). Nothing can read a texture at run time, and a skinned mesh has no part colours. Pixels and
  puffs take the skin (the colour that tells the types apart); pieces take all three. An overkill gives each piece
  the colour of the slice of the body it comes from (legs under 40% of the height, head over 80%, top between with
  an arm's skin three times in ten), which is what makes it read as that body coming apart.
- **Put the burst where the shooter can see it.** The aim point is the chest's middle, inside the mesh. The burst sits
  0.7 of the body's half width toward where the blow came from, its cone leaning back that way, and its flash is
  drawn 1.5 studs toward the camera (`ZOffset`). Both reference games burst from the centre in every direction
  because they did not pass the attacker's position; here `onDamaged` and `removeEnemy` already had it.
- **A kill's light is a hit's; its pieces are not.** Section 15's lesson (a kill bigger than a hit read as "scaling
  with the health left") was about light. More bricks off the killing blow is the body coming apart, not a bigger
  flash. Unjudged: if it reads as scaling again, make `TIERS.Kill.Pieces` the hit's.
- **One simulation for every thrown piece** (`thrownPieces`): the wall's bricks, the casing and the enemy's pieces
  fall, bounce and sink by the same numbers, each owner with a pool of its own (the pistol 48, the enemies 96) so a
  dying wave never takes a wall's bricks. Do not retune it for one owner.
- **A body stands on its floor**: its pieces take their floor from its feet, so a burst raycasts nothing until a
  piece comes down.
- **No slot is held.** The anime kit skipped a burst when its ring of copies was busy (16 copies held 0.6 s: 27
  bursts a second). Here 12 copies are taken in turn and never refused; a copy rewrites its sizes and colours only
  when the body differs from its last one's, and what still flies from that one is recoloured with it, which in a
  crowd of mixed types is a few pixels for a tenth of a second.
- **The bench calls the game's functions**, staggered 0.12 s a body: the game's own cap (4 hits a frame) would
  drop two of six bodies struck on one frame, and a row reads better as a ripple.
- **Budget at a full wave** (ree, 255 bodies all hit every frame and 12 killed a frame): about 5.5 ms of engine
  calls a second, 0.09 ms a frame, three fifths of it `ParticleEmitter:Emit`; the camera is read once a frame, not
  once a burst.
- **What the cleanup pass found** (the user asks "is this the most optimized and readable it can be?" after every
  effect: do it before being asked):
  - A copy resized for a body rebuilt its Size sequences every time (600 a second in a mixed crowd). They are
    built once a scale and kept on the pool; a type's scale is worked out once with its colours, not every burst.
  - A piece's spin was a CFrame multiplied every frame. A random axis and a random start angle are already a
    random pose, so a piece keeps an angle and its joint is one `CFrame.fromAxisAngle` a frame. Datatype calls
    fell a quarter (0.84 to 0.63 ms a second for the enemies, 0.32 to 0.26 for the pistol), and nothing drifts.
  - What is the same for every copy of a template (layer names, counts, sizes) lives on the pool, not on each
    copy; a copy holds only its instances and what it was last sized and coloured for.
  - Left alone: in the worst mix (six types sharing twelve copies at fourteen bursts a frame) a copy is resized or
    recoloured 1,000 times a second, 0.46 ms a second. Copies kept apart by type would remove it for 216
    attachments; not worth it.
- **zsh does not split an unquoted variable**: `ree run $M` with the mounts in one string mounted nothing and the
  harness sat on `WaitForChild`. Keep the mounts in an array (`M=(--mount a --mount b)`).
- **Previewing a module that loads sounds**: mount a stub over `ReplicatedStorage/GlobalShared/Core`
  (`Assets/effects/enemy/preview_stubs`), and name the floor's Model `Arena` so `sightCast` finds it.
- **Not seen in game yet**: the bursts on the real rigs (the previews stand boxes in each type's colours), a kill's
  pieces beside its ragdoll, and how the grey Walker's pale pixels hold against a bright map.

## 32. Kill All The Monsters: the other starting guns (built 2026-11-20 from section 30, unjudged, unplayed)

`RifleFx`, `SniperFx`, `MinigunFx` and `ShotgunFx` (the ladder's shotgun is the Terminator Gun), through the same
`gunFx` as the pistol; sources, the table of what each draws and every number in `Assets/effects/guns/` (its README).
No sprite was drawn: the five of section 30 and the pistol generator's helpers. Bench: `gunbench` (every starting gun in a
row, the pistol first, each on its own interval, pellets and spread).

- **A gun is a hue and a shape, not more of the pistol.** Rifle cyan: three rings in a row, each smaller and faster,
  and a ring with an echo on the wall. Sniper violet: gates left hanging along the line and the widest landing.
  Minigun red: small layers, most thrown only some shots. Shotgun pink: everything at the muzzle, small pops where
  the pellets land. The hues are the agent's pick (pink and violet are on neither map); they are one `Hue` a kit.
- **A layer some shots**: a count range that starts at 0 (`NumberRange.new(0, 1)`) is how a 17 shots a second
  stream flickers instead of strobing. Every shot ringing looked like a tube.
- **A ring left in the air** is a ring thrown fast with Drag: it stops `speed / (drag * ln 2)` studs out. Four of
  them at rising speeds are a row of gates, with no code.
- **A second ring that opens late** has no delay to use: its Size is 0 for its first third.
- **Orange light over a bright floor is the pistol's gold.** The minigun at (255, 110, 25) read yellow; (255, 62, 30)
  reads as its own.
- **Pellets land over a few frames** (`SpeedJitter`): on one frame, 18 landings meet the 8 bursts a frame cap and
  ten are dropped; with 18% jitter they patter, which also looks better.
- **Many landings at once are each small and none has a wash**: 18 pools of light are a white wall.
- **A casing leaves when the action is worked** (`CasingDelay`: the sniper's bolt, the shotgun's pump), and casings
  have a pool of their own: a minigun throws 17 a second and filled the one it shared with the wall's bricks.
- **First person scales by gun** (`CloseScale`): a flash twice the pistol's at the pistol's 0.45 covered the target.
- **Not seen in game**: every kit (the templates are not in the place until `gun_effects.luau` is pasted), the hues
  under the place's bloom, the gates from the shooter's own camera, the casing ports on the real models.

## 33. Kill All The Monsters: the ground warnings in the house look (built 2026-11-20 from section 30, unjudged, unplayed)

Section 16's warnings (the footprint, the pieces, the sweep, the colours) with section 30's look laid over them: the
floor textures redrawn as lit square tiles, and `src/Game/Client/Utils/telegraphFx.luau` throwing pixels, square
rings, a light and the floor's own stud bricks. Templates `ReplicatedStorage.Effects.TelegraphFx`, sources, the table
of what each moment draws and every number in `Assets/effects/telegraphs/` (its README). No sprite was drawn: the
pistol kit's five. Bench: `telebench`, unchanged.

- **The warning is the hitbox, so everything it throws is placed by the controller** on the floor pieces it already
  cut (`surfaceAt`: a point is used only where a piece lies), never by an emitter's Shape over a box. A rate emitter
  on a disc would throw pixels onto the deck the hit does not reach and through the wall it stops at.
- **What hits is the floor, so the floor comes apart**: bricks in the colour of what lies there (a trim's colour is
  stamped per nav node with its height, since a ray never meets CanQuery-off trim), the dust paler. A shockwave tears
  them up all along its front as it rolls: the boss's biggest moment is the one that sheds the most.
- **The rim stands up**: a fence of pixels rising off the outline says where the edge is over a crowd that hides the
  floor, and its rate rising with the square of the wind-up says when. The fill's front throws them too: the timer in
  the air.
- **A pixel cloud, not a line**: thrown at one speed range with Drag, every pixel stops at about speed / drag and they
  hang as a flat line. 7 to 35 studs a second under Drag 3.5 spreads them from 2 to 10 studs up.
- **A flat square ring inside a circle is 0.7 of its radius** (half side), so its corners stay inside; and it is
  capped (12 studs), or the boss's 40-stud shockwave opens one as wide as the arena. A square shock under the hit's
  white flash is not seen: it lives 0.4 s so it outlasts the flash.
- **A texture's tiles scale with its shape**: 26 across made the 40-stud shockwave a floor of 3-stud planks as it
  heated white; 40 across keeps them near the stud's scale.
- **An explosion is a slam and more**, not another look: 1.6 times the pixels and bricks, a white-hot heart over the
  floor, white flecks thrown up.
- **ror lays a Top-face Texture from the opposite corner to the engine** (U toward +X, V toward +Z in its shaders;
  section 16's calibration in play is U toward -X, V toward -Z): any warning cut in more than one piece draws torn in
  ror only. The preview turns the PNGs half round and writes each offset as `-(face size) - offset`, after the
  controller (a signal calls its last connection first, so the preview's handler is connected before it).
- **Budget at 40 warnings** (ree, `--profile boundary`): telegraphFx and the bricks about 1 ms of engine calls a
  second. The controller's piece writes are 7.7 ms. They wrote what a property already held 9,400 times a second
  (`paint`'s Transparency, a sweep growing round its centre rewriting the same CFrame); a piece now keeps what it was
  last given and skips those (2,700 left, all cheap). What is left is real: the sweep's pieces are resized every
  frame (`Size`, 2.8 ms, about 2 us a write) and the pulse recolours every piece. Dropping the resize would mean a
  Decal's clamped `UVScale` / `UVOffset` instead of a tiling Texture, an untested mapping in the engine.
- **A floor's colour is looked up once a nav node** (`floorColors`): the map never changes, so the ray and the
  `Color` read a brick needs are paid on a node's first brick only.
- **Not seen in game yet**: the templates are not in the place until `telegraph_effects.luau` is pasted; the tiles
  and the bricks on the real maps' floors; the light under the place's bloom.

## 34. Kill All The Monsters: the bullets (the Comet, picked 2026-11-20, unplayed)

The user did not like the bullets: "they look like darts, a shiny part on the front and a big trail on the back". Six
shapes stood beside the dart: Bolt, Pixel, Train, Spiral, Gate, Comet. **The Comet won** ("really good"), asked to
"go tiny like train and not be too large" and its bullet "more stretched just like in train": a short Neon bar shedding
glowing pixels that taper behind it over 16 studs. It is every kit's own `Bullet` now (`comet` in the pistol
generator); the dart and the other five stand beside it on `bulletbench [gun]`. Sources, the tables and every number
in `Assets/effects/bullets/` (its README).

- **A style is one shape for every gun**, drawn in the gun's hue and grown to its size (`thick` across, `long` along
  the shot), so a gun is still known by its colour and the user picks a shape once.
- **A bullet is a Folder of parts** (`Effects.<Kit>.Bullet`, or a style's `<Style>.<Kit>`): each placed by its CFrame
  in the bullet's frame (-Z ahead, the head at the origin), a part named Orbit... turned round the flight line, and a
  `Trail` attachment whose emitter drops a pixel every `TrailEvery` studs. A single Part (the old kits) still works.
- **A part behind the head waits at the muzzle** until the bullet has flown that far, or a train's tail starts
  inside the gun.
- **A trail left in the air is as long as the bullet's speed times its life**: Comet pixels that lived a third of a
  second drew 100 studs of dots behind a pistol shot, the big trail again. A pixel's life is now the trail's length
  (16 studs) over the gun's speed.
- **A taper by age is stepped**: a bullet crosses 5 to 12 studs a frame, so the pixels one frame drops are born
  together and shrink together (it came out two big, four small). The Comet asked to "go tiny like train" picks an
  emitter by how far behind the head a pixel drops, each starting it as small and living as little as one dropped
  that much earlier: the taper is by distance.
- **A still at 30 frames a second is not the game**: gunFx steps once a rendered frame, so ror's default 30 drops a
  fast gun's trail twice as far apart as the game would. Render stills with `--fps 60`.
- **A bench never shares the game's part pool**: `motorParts` never frees a part for another template, so a shotgun
  bench in five-part bullets would have filled the 256 and left the game's guns nothing to draw.
- **Measured at four miniguns** (ree `--profile boundary`): all of gunFx is 5.2 ms of engine calls a second, the
  Comet's trail 0.6 of it (the attachment's move and `Emit(1)` a pixel); a bullet is one part, half the dart's.
- **ror shows a bullet only side-on**: from behind the row (the shooter's view) the muzzle flashes cover it. The
  preview stacks the lanes one over another for a side camera, and holds every lane 22 studs out for a still (stop
  calling `gunFx.Step` and the bullets stay where they are).
