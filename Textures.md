# Textures.md

> **Carried over from Ballarc (Last Wave) on 2026-11-20.** The method, the engine facts and the measured lessons
> apply here; the old game's look does not. Kill All The Monsters is not pixel art and not anime: maps are stud-style
> (LEGO-like bricks at real scale), UI is sleek and modern (`UIMatt.md` is the designer's spec). Sections named after
> a Last Wave weapon, boss or screen are worked examples. A path that does not exist in this repo (`Assets/...`,
> `tools/vfx/...`, a `src/Survivors/...` module) is in `../Ballarc`; `../Anime Zombie Survival` holds the enemy rig,
> map and burst pipelines this repo's `tools/` came from.

How the enemy bodies in `Assets/models/Enemies/` are painted, measured off ZombieNormal, ZombieRunner and
ZombieBrute, so the next one matches on the first try instead of the third. Learned on the ZombieSpitter. Its first
texture was painted from a palette I guessed and was rejected ("nowhere near the other models"); the second was
painted from the numbers below and was accepted. The shapes those textures go on are Models.md §7.

**Rule zero: measure before painting.** Every number here came out of the `.bbmodel` files with a script (§5).
A new family of models (props, bosses, anything not these three) gets the same measurements first; do not carry
these numbers over to it on trust.

## 1. Resolution

- **One texel per unit, as the player sees it.** A 10-unit head has a face about 10 texels across.
- **Stored four times over.** Runner and Brute are 512 x 512 textures on UVs 4 pixels per unit (`uv_width` 512).
  Normal was the older 128 x 128 at 1 pixel per unit and is stored the same way now: its texture is 512 x 512
  on the 128 UV space it was built in, every texel a 4 x 4 block with the grain below
  (`Assets/models/Enemies/upscale_texture.py`, which keeps the 128 file as `ZombieNormal.128.bbmodel`). A new
  model is stored like Runner and Brute.
- **Inside each 4 x 4 block the pixels are not identical**: a faint grain of about +-3 per channel (median
  deviation from the block's median: Runner 5.5, Brute 3). Only about 10% of blocks carry real sub-texel detail
  (a line of a face feature). So: paint at 1 texel per unit, repeat each texel 4 x 4, add +-3 noise.
- **A face with a fractional size keeps the texel size**: give it `ceil(size)` texels in the atlas, but map its UV
  to the exact size (`x*4 .. (x+w)*4`), so the last texel is cut short rather than every texel stretched.

## 2. How one face is painted

This is the part that makes the style. Every face of every box, on all three:

1. **One mid tone** of the material's ramp fills the face.
2. **A lighter inset panel**: one texel in from the border, one tone lighter. Its edge is broken in a few places
   so it reads painted rather than stamped.
3. **Blotches**: about one per 9 texels, 1-3 wide and 1-2 tall, one tone off (lighter or darker, darker a bit
   more often).
4. **Dark accents hugging the border**: about one per 5 texels of perimeter, two tones darker, sometimes with a
   one-tone texel under it.
5. **Light from above**: top faces start one tone lighter, bottom faces one tone darker, and side faces darken
   their bottom row by one tone.

What it is NOT: no smooth gradients, no per-texel random speckle, nothing saturated. The first Spitter had all
three and read as noise next to the others. Measured contrast inside one face: channel standard deviation about 20
on skin (Runner arm 10.6, Brute belly 19.8, Brute chest 26.5); anything over about 35 comes from painted features,
not from the base.

## 3. Colour

Ramps light to dark. Saturation sits around 0.25 on skin (HLS), and every material stays that muted.

| Material | Ramp | Where it was measured |
|---|---|---|
| Zombie skin | `#9cc47a #8ab466 #789c5a #6c8a54 #5a7242 #4a5e36` | Brute chest and belly, Normal and Runner heads |
| Bone (bare, the "tan" parts) | `#a28a42 #a28442 #9c7e3c #90783c #8a6c36`, dark vertical ridge lines along long faces | Runner's arms, Normal's left forearm and leg, Brute's legs |
| Bone, darker (spine, ribs) | `#9c6a3a #8a5a30 #764a28 #623c20` | Runner's spine and six rib bars |
| Rust trousers | `#906630 #8a542a #7e4224 #723018` | Runner shins |
| Normal's shirt | `#729090 #60847e #545a48` with collar `#48361e` | Normal torso |
| Brute's plaid | `#b48a48 #a87e42 #965a06 #663c06 #2a1800` | Brute shorts |
| Blood, flecks | `#a85e36 #905030 #904828 #7a3a22` | Brute, 23% of its texels lean red |
| Blood, streaks | `#983a24` head, `#7e2e1c` tail | Brute chest stripe |
| Bruise | `#6e5e70 #685868 #604060` | Brute shoulders |
| Eyes | `#c8c070` in a socket of `#303018` | Runner, Normal |

- **Cap the flecks per face, around 6.** A per-area rate is right on a limb and wrong on a big face: at 1 per 32
  texels the Nest's mound (faces up to 34 across) turned into confetti. The Brute's 68 x 38 chest carries a
  handful of flecks and ONE streak. Put the cap inside `flecks()` so every painter gets it.
- **Blood is rust, not red.** Single-texel flecks, sparse (the Spitter uses one per 30-35 texels on skin), and
  now and then a 1-texel streak running down a face that wanders a column sideways. On forearms it thickens toward
  the wrist, only in the lower half and only a little (at most ~20% of texels on the last rows).
- **Bruises are blended, not painted over**: about 45% of the skin under them plus 55% bruise, a 1-texel core
  with a few neighbours, one per face at most.
- **A new material gets its own ramp at the same saturation and value spread.** The Spitter's bile is
  `#dde68e -> #525e22` (a muted yellow-green, yellower than the skin so it separates by hue); its first version was
  a neon `#3ce584` glow and was the loudest thing wrong with it. Wet things get a pale highlight texel or two in an
  upper corner, not a glow.
- **Clothing tells the enemies apart**: Runner has a red shirt, Normal a teal-grey one and Brute plaid shorts, so
  the Spitter took a cream tank top (`#d2caa6 -> #5e5942`) and faded jeans (`#7a8696 -> #323846`). Pick a
  colour that is not already taken (the table below lists what is).

### Ramps the later enemies added

Six more enemies were built from this file in one round (Models.md §7 lists them). Every ramp is light to dark,
kept at the family's muted saturation. Reuse these before inventing a near-duplicate.

| Material | Ramp | Enemy |
|---|---|---|
| Slate overalls | `#8a8e90 #74787a #606466 #4e5254 #3e4244 #2e3234` | Charger |
| Callus hide (a darker skin) | `#727e52 #66704a #5a6242 #4e563a #424a32 #363e2a`, crack `#2c3420`, scab `#6a3420 #562818` | Charger's big arm |
| Grey-white shirt | `#bcb8a6 #a8a492 #928e7e #7c786a #666256 #504c44` | Charger |
| Dirty sneaker | `#b4b2a4 #a09e90 #8a887c #74726a #5e5c56 #484640` | Charger |
| Mustard jacket | `#c8b060 #b09a50 #988442 #7e6c36 #645428 #4a3e1c` | Exploder, hat too |
| Dynamite | `#c26a4e #b0503a #98402e #7e3224 #62261c`, paper ends `#d2c49a #bcae84 #a0926c` | Exploder |
| Ember boils | `#e0a060 #c8804a #a8643a #7e4a2c` | Exploder |
| Work canvas trousers | `#7a6e5e #6a5e50 #5a5044 #4a4238 #3c352e #2e2824` | Exploder |
| Navy jacket | `#5a6a8e #4c5a7c #3e4a68 #323c56 #262e44 #1c2232`, reflective strip `#c8c890 #b0b07c #96966a` | Shield |
| Drab trousers | `#827a68 #706a5a #5e594c #4e4a40 #403c34 #322f29` | Shield |
| Black leather boots | `#5e5852 #4e4944 #403c38 #34302d #282523` | Shield |
| Wood | `#a08058 #8a6a46 #735638 #5c442c #463220` | Shield's door, Nest debris |
| Iron / steel / tape | `#a4a49a #8a8a86 #727270 #5a5a58 #444442 #343432` | Shield bands, Charger buckle, Exploder tape |
| Stone rubble | `#9a968a #86827a #726e66 #605c56 #4c4a44 #3a3834` | Nest |
| Plum robe | `#8a7090 #76607c #624e68 #503e56 #3e2e44 #2e2234` | Summoner |
| Brood (shared) | `#c79aa0 #b08590 #98707e #7e5a6a #644656 #4c3444`, wet texel `#e0c4c4` | Summoner's sac, Summon's skin, Nest's pods |

What the ramps taught:

- **Brood sits one step DARKER than the zombie skin at the same index** (luminance: brood[1] `#b08590` 143,
  skin[2] `#789c5a` 144). A brood surface takes `mottle(base=1)` where skin takes `base=2`, or it comes out a
  dull grey-mauve that reads darker than the family. Check any new ramp's luminance against the skin's before
  choosing its base.
- **Never blend two near-complementary ramps 50/50.** Brood and zombie green mix to a grey khaki (`#b1af8d`)
  close to the bone colour. Keep each material pure and blend small patches of one over the other, like a bruise.
- **A skin variant needs about 2 ramp steps of lightness AND about 15 degrees of hue off the skin to separate at
  a distance.** The Charger's first callus, one step darker at the same hue, could not be told from the skin at
  distance 115.
- **A ramp has one base that reads as its colour.** The mustard only reads as mustard at base 2 (`#988442`); at
  base 3 it turned olive and muddy. When two parts share a ramp (a hat and a jacket), their SHAPES separate
  them, not a one-tone shift.
- **Keep bare skin on mid-value cloth to places with a reason** (a hem, a zip gap, round a wound). One skin rip
  per face on the mustard jacket turned it into green camo at distance 110.
- **Pods and sacs need a darker rim.** Pods at base 0 melted into a sac whose own inset panel was the same tone;
  a `BROOD[3]` rim on their sides and bottom separated them. A sac this uniform can drop its inset panel.

## 4. Features

- **Faces are drawn with a handful of texels**: a brow row a tone or two darker, a 2 x 3 socket with one yellow
  texel for the eye, two dark texels for the nose, a dark mouth or a row of teeth. Asymmetry (one eye lower)
  is enough character.
- **Seams and hems are one texel**: a ragged hem is its bottom row, with about half the texels swapped for
  what is under it (skin under a torn shirt or trousers).
- **Faces that are never seen** (a top face buried inside the next box) can be flat. The originals paint some of
  them as light-blue placeholder squares.
- **Eyes go on the rows BELOW a brow box.** A brow that is its own box hides whatever is painted under it on the
  head's front face; the Charger's first face drew its eyes behind the brow.
- **A structure needs a face to read as an enemy.** Zombie-style eyes over a toothed mouth did more for the Nest
  than any colour choice. Eyes glinting deep in a mouth or a pod split add to it.
- **A detail box that bursts through a face paints its own footprint onto that face**: a torn ring of dark cloth
  and rust round the boil, a scorch just outside it. Without the ring, the Exploder's boils were orange cubes stuck
  on; with it they push out through the jacket. `face_point(from, to, face, u, v)` in `zombie_exploder.py` maps a
  painter's image coordinates to the 3D point and normal, so the box and its ring come from the same numbers.
- **Paired nail heads in a row read as rows of little eyes.** Put nails on the iron bands, not at plank ends.
- **Wood grain**: one broken dark grain line per plank runs along its LONGER side (the painter only gets `face, w,
  h`, so the longer side is the orientation cue); two lines read as bark next to the flat zombie faces. End
  grain on the short faces is light with a dark ring.
- **Depth reads from an inner rim.** A hood's front face got a dark rim inside it so the head looks sunk into it;
  the ring of lips round the Nest's mouth has gums painted on the faces looking INTO the hole (the lower lip's
  `up`, the upper lip's `down`, the +X lip's `west`, the -X lip's `east`).
- **A painter that varies per box** (which plank carries the bloody hand, which side a tear edge is on) needs the
  cube's name: set a module-level `cur` before painting each cube.
- **Seen from behind (the north face), +X is on the image's LEFT**, so a left-side panel's inner edge is its last
  column.
- **Bone is painted like the Brute's legs**: the bone ramp in the usual mottle (no border accents), with broken
  1-texel ridge lines a tone or two darker running down the long faces, and blood at the joint ends.
- **Bone over a wound goes on near-black, never on blood.** The darker spine/rib ramp and blood-red flesh are the
  same hue family, and the Shield's ribs vanished into a red cavity. Over `MOUTH` 2-4, with a rust rim and skin
  round it, they stand out.
- **A one-block bone hand with long dark finger gaps reads as a brush head.** Split only the tips with a shallow
  rust-brown gap and lighten the knuckle knobs.
- **A Brute-style hand is painted, not modelled, at the tips**: blood thickening toward the bottom, the tip row a
  tone darker, and no nail colour. Heavier blood on the fingers than on the fist separates them by colour, as on
  the Brute.
- **Pustules: sparse, and never a symmetric ring.** One painted pustule per ~70 texels reads as "infected"; one
  per 22 read as red measles. A 1-texel ring round a spot reads as a square frame, and the same ring with its four
  corners dropped reads as a PLUS SIGN (the Boomer's first rims looked like first-aid crosses, which a game reads as a
  health pickup). Paint each rim irregular: heavier on one or two sides, lighter or missing on another, and the outer
  texels blended about 50% into the skin. Pale pus heads `#e6dcb0 #d4c894 #bcae78 #a09260`, lit in one upper texel.
- **Ribs can be pure paint** where a pec or an overhang shades them (the Charger: two rib bars over a dark gap under
  the torn shirt). No triangles, and the silhouette is untouched.

### A lit mark on stone (the rune stones, 2026-10-19)

The runes (`Assets/models/Drops/Runes/runes.py`, Models.md §12) took this painting onto a non-enemy, with a mark
that glows. What three rounds of renders taught:

- **Stone that carries colour is a cool, muted slate** (`#8a8c96 #767884 #646672 #545660 #44464f #36383f`, base 2),
  so the mark is the only colour on it.
- **Draw a small glyph by hand.** The marks are 9 x 11 texels; rasterising RuneGlyphs' strokes left stray texels
  and lopsided joints, so each was drawn as rows of `#` and `.`. One-texel strokes; a 45-degree line is a staircase
  of single texels touching at corners, and it reads.
- **A mark stands half a unit proud as boxes**, so it has sides. Its face is the rune's colour lit toward its core
  (55% Edge, 45% Core) with the top row half Core, its sides the Edge colour, the top lit and the bottom darker. The
  pure pale Core read washed out: the shapers came out beige and Tesla olive.
- **The cut round it is the four texels beside each stroke**, a tone darker with 22% of the Edge colour in them.
  A spill on all eight neighbours, stronger, blurred the mark into a muddy halo.
- **Nothing on or near the mark may share its hue.** Olive lichen flecks beside Tesla and the gold shapers read as
  the mark's light leaking onto the stone, so the lichen went entirely.
- **The back's mark is the front's mirror**, so it reads the right way round from behind, as RuneGlyphs cuts it.
- **Glow is a mask, not a material** (Models.md §12): the face of a stroke 255, its sides 150, the stone 0.

The coplanar check there only fails two faces looking the SAME way in one plane; two boxes touching face to face
(a stroke on the stone, two strokes side by side) are internal, and a face pushed a hair outward that lands inside
another box is culled.

## 5. Measuring a model (the scripts that produced this)

The originals are meshes of triangulated boxes, so they have to be taken apart before they can be read:

- **Parts and texel density**: union the triangles by shared vertex POSITION (the files duplicate vertices per
  face) into boxes, then take each box's size and the ratio of UV area to 3D area (`sqrt(uvArea / area)`) =
  texels per unit.
- **Per-face crops**: group triangles by normal and plane, take the UV bounding box, crop it out of the texture
  embedded in the `.bbmodel` (`textures[0].source`, a base64 PNG) and paste the crops on a contact sheet at 3-6x
  with `Image.NEAREST`.
- **Ramps**: quantize a face's pixels to steps of 6, count, and read the top 8 plus the mean, HLS lightness and
  saturation, and the standard deviation.
- **Renders**: render with a throwaway `THREE.WebGLRenderer` on Blockbench's global `scene` and write the PNG to
  the scratchpad (§6). The MCP's own `set_camera_angle` is excluded in this build. Rendering switches the active
  project tab, so put the user's tab back afterwards (`prev.select()`).

## 6. Building one through the Blockbench MCP

The generator is `Assets/models/Enemies/zombie_spitter.py`: the geometry as a list of boxes, one painter per material
implementing §2 to §4, a shelf packer, and a JSON out (`OUT=<dir> python3 zombie_spitter.py`). Copy it for the
next enemy and change the box list, the materials and the features; keep `mottle()`, the ramps and the
coplanar check, and call the shared `cull_hidden.py` (Models.md §7, "Triangles"). The loader, run with
`risky_eval` and kept on `window` so a rebuild is one call. It nulls any face missing from `faces`, which drops
it from the export:

```js
window.buildModel2 = function (path) {
  const d = JSON.parse(require('fs').readFileSync(path, 'utf8'));
  let p = ModelProject.all.find(p => p.name === d.name);
  if (!p) { newProject(Formats.free); Project.name = d.name; } else { p.select(); }
  [...Outliner.elements].forEach(e => e.remove()); [...Group.all].forEach(g => g.remove(false));
  [...Texture.all].forEach(t => t.remove(true));
  Project.texture_width = d.size; Project.texture_height = d.size;
  const tex = new Texture({ name: d.name + '_diff.png', uv_width: d.size, uv_height: d.size })
    .fromDataURL(d.texture).add(false);
  const groups = {};
  d.groups.forEach(g => { const grp = new Group({ name: g.name, origin: g.origin });
    grp.addTo(g.parent ? groups[g.parent] : undefined).init(); groups[g.name] = grp; });
  d.cubes.forEach(c => { const faces = {};
    for (const k of ['north', 'south', 'east', 'west', 'up', 'down'])
      faces[k] = c.faces[k] ? { uv: c.faces[k], texture: tex.uuid } : { uv: [0, 0, 0, 0], texture: null };
    new Cube({ name: c.name, from: c.from, to: c.to, origin: c.origin, rotation: c.rotation, faces, box_uv: false })
      .addTo(groups[c.group]).init(); });
  Canvas.updateAll();
};
```

- **Render in a SEPARATE call from the build.** `fromDataURL` loads asynchronously, and a render in the same call
  came out empty.
- **Save** with `Codecs.project.compile()` written to `Assets/models/Enemies/<Name>.bbmodel`, then set
  `Project.save_path` to it.
- **Face orientation** (measured, see memory `reference_blockbench_mcp_scripted_build`): paint every side face as
  seen from outside with +Y up and it lands right; `up` has -Z at the top of the image, `down` has +Z at the top.
- **`risky_eval` runs its code as an expression**, so a bare top-level `return` is a SyntaxError. Wrap anything
  longer than one expression in `(() => { ... })()`.
- **The atlas**: 128 texels (512 px) holds a Spitter-sized body of about 40 boxes. Brute-class bodies, a big
  shield or door, and anything past about 75 boxes need 256 texels (1024 px), still 4 px per unit. Let the
  packer try 128 and fall back to 256.
- **Render a small creature closer.** The 20-unit Summon is about 150 px tall at the reference distance 110:
  judge it at about 55, and keep one render at 110 to compare its scale with the others.

### Several sessions in one Blockbench

The six later enemies were built by six sessions at once, driving one Blockbench app. `Project` is one global
that any session can switch between two calls, so:

- **Each model has its own tab, named after it, and every `risky_eval` call selects that tab by name** and does
  all its work in the same call. A single call runs to completion uninterrupted; relying on `Project` from an
  earlier call is what would put one session's cubes in another's model.
- **Never save or close another tab**, and render off-screen (the `snap` helper in
  `Assets/models/Enemies/refs/BRIEF.md`) rather than through the user's viewport. Put back whichever tab was active
  before (`prev.select()`).
- **Shared helpers on `window` are defined with the same code by every session**; a session that needs a
  variant gives it its own name.
- The brief that ran this round, with the shared rules and the per-enemy specs, is
  `Assets/models/Enemies/refs/BRIEF.md`. Copy it for the next round.

## 7. Checklist for a new enemy's texture

1. Measure the models it stands beside (§5), even if they are these three.
2. 1 texel per unit, stored 4x with +-3 grain.
3. Every face: mid tone, lighter inset panel, blotches, dark border accents, lit from above (§2).
4. Muted ramps; a new material at the same saturation, its luminance checked against the skin's to choose its
   base; clothing in a colour no other enemy wears (§3).
5. Blood as rust flecks and streaks, sparse, at most about 6 flecks on any face; bruises blended.
6. Anything bursting through a face paints its ring on that face; eyes sit below a brow box (§4).
7. Render it close up beside an original at the same camera before showing it, and iterate at least once on what
   the render shows. None of the six later enemies passed on its first render.
