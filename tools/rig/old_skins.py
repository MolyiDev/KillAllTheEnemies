"""The old Game place's twelve enemy skins as R6 skinned rigs: `python3 tools/rig/old_skins.py [R6.obj] [head.mesh] [outdir]`
writes `<Name>.bbmodel` and `<Name>_diff.png` per skin into Assets/models/Enemies; export and render them as build.sh
does. The rig, the boxes, the head and the atlas are r6_zombie.py's; only the painting differs.

The skins were R6 Humanoids (`ReplicatedStorage.Assets.Horde.Skins` in the old place): coloured parts, a classic Shirt
and Pants, a face Decal on the classic head, at a size. Their BodyColors were all left at grey, so the part colours
are what was designed. The template images are in Assets/models/Enemies/source/old, named by asset id.

THE CLASSIC CLOTHING TEMPLATE (585 x 559): each face of a box is a rect of it, already oriented the way the chamfered
box's UVs read a face (front seen from the front, the side faces with the front edge toward the torso's front rect,
tops with the back edge up, bottoms with the front edge up). The limb on the template's LEFT is the character's RIGHT.
Shirt paints the torso and arms, Pants the torso and legs; on the torso the shirt goes over the pants.

Transparency and Material (the ghosts, the Hunter's ice) are the MeshPart's, set in the place.
"""
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paint  # noqa: E402
import r6_zombie  # noqa: E402

SOURCE = os.path.join(r6_zombie.OUT, "source", "old")
# The templates hold 64 px per stud (a torso front is 128 px over 2 studs); 512 packs the body at 56, so a bigger atlas
# would only hold upscaled pixels, at four times the texture memory.
ATLAS = 512
# The legs' tops and the torso's underside are hidden only while the legs hang straight: a stride swings a leg out from
# under the torso and shows both.
HIDDEN_FACES = {}
TEMPLATE_HEIGHT = 559

TORSO = {"south": (231, 74, 128, 128), "west": (165, 74, 64, 128), "east": (361, 74, 64, 128),
         "north": (427, 74, 128, 128), "up": (231, 8, 128, 64), "down": (231, 204, 128, 64)}
# The character's right limb (the template's left) and left limb.
LIMB_RIGHT = {"east": (19, 355, 64, 128), "north": (85, 355, 64, 128), "west": (151, 355, 64, 128),
              "south": (217, 355, 64, 128), "up": (217, 289, 64, 64), "down": (217, 485, 64, 64)}
LIMB_LEFT = {"south": (308, 355, 64, 128), "east": (374, 355, 64, 128), "north": (440, 355, 64, 128),
             "west": (506, 355, 64, 128), "up": (308, 289, 64, 64), "down": (308, 485, 64, 64)}

# Part colours as the old skins hold them: head, torso, arms, legs.
SKINS = {
    "Walker": dict(size=1.0, shirt="168726600", pants="235932030", face="24690949",
                   colors=("#7f7f7f", "#7f7f7f", "#7f7f7f", "#7f7f7f")),
    "Runner": dict(size=1.0, shirt="236763556", pants="236763556", face="3292383310",
                   colors=("#ffff00", "#f8f8f8", "#ffff00", "#ffff00")),
    "Bomber": dict(size=0.72, shirt="132601077", pants="132601234", face=None,
                   colors=("#f8f8f8", "#000000", "#f8f8f8", "#f8f8f8")),
    "Brute": dict(size=1.0, shirt="5299411782", pants="5299414678", face="37824746",
                  colors=("#7b007b", "#000000", "#7b007b", "#7b007b")),
    "Abomination": dict(size=1.3, shirt="5299411782", pants="5299414678", face="37824746",
                        colors=("#6e8c5a", "#7f7f7f", "#6e8c5a", "#7f7f7f")),
    "Goliath": dict(size=1.8, shirt="5299411782", pants="5299414678", face="37824746",
                    colors=("#96504c", "#7f7f7f", "#96504c", "#7f7f7f")),
    "Hunter": dict(size=1.0, shirt="8560412226", pants="8560399879", face="22972635",
                   colors=("#b1e4ee", "#12eed4", "#12eed4", "#12eed4")),
    "Stalker": dict(size=1.1, shirt="8560412226", pants="8560399879", face="209712379",
                    colors=("#ffff00", "#f8f8f8", "#ffff00", "#ffff00")),
    "Packleader": dict(size=1.9295, shirt=None, pants=None, face="37824746",
                       colors=("#7b007b", "#000000", "#7b007b", "#7b007b")),
    "Phantom": dict(size=1.0, shirt=None, pants=None, face="22972635",
                    colors=("#7f7f7f", "#7f7f7f", "#7f7f7f", "#7f7f7f")),
    "Wraith": dict(size=1.0, shirt=None, pants=None, face="3292383310",
                   colors=("#7f7f7f", "#7f7f7f", "#7f7f7f", "#7f7f7f")),
    "Revenant": dict(size=1.4486, shirt=None, pants=None, face=None,
                     colors=("#7f7f7f", "#7f7f7f", "#7f7f7f", "#7f7f7f")),
}

# BLOOD IS DRAINED TO GREY. Roblox moderated the first upload of the Runner's atlas for gore (2026-11-20), so every
# image that carried blood is cleaned before it is painted: a stain keeps its brightness and loses its colour, and
# reads as grime. Per image, the rows (from the top) where any red-leaning brown is blood (the Runner's jacket, the
# Walker's tank top); below them only red is, and brown with green well over blue is leather (the Walker's boots).
# Images not listed carry no blood where the body samples them. Cleaned copies go to source/old/clean/ for review.
CLEAN = {"236763556": TEMPLATE_HEIGHT, "235932030": 270, "3292383310": 0}
CLEAN_RED_SHARE = 0.15

_images = {}


def drain_blood(img, loose_rows):
    a = np.array(img).astype(float)
    r, g, b, alpha = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    reddish = (alpha > 10) & (r > 12) & (r > b) & ((r - g) / np.maximum(r, 1) > CLEAN_RED_SHARE)
    loose = np.zeros(r.shape, bool)
    loose[:loose_rows] = True
    stain = reddish & (loose | ((g - b) < 0.5 * (r - g)))
    # One pixel wider, for the anti-aliased rim round each stain.
    p = np.pad(stain, 1)
    stain = stain | p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:]
    grey = 0.299 * r + 0.587 * g + 0.114 * b
    for c in range(3):
        a[..., c] = np.where(stain, grey, a[..., c])
    return Image.fromarray(a.clip(0, 255).astype(np.uint8), "RGBA")


def image(asset_id):
    if not asset_id:
        return None
    if asset_id not in _images:
        img = Image.open(os.path.join(SOURCE, asset_id)).convert("RGBA")
        if asset_id in CLEAN:
            img = drain_blood(img, CLEAN[asset_id])
            os.makedirs(os.path.join(SOURCE, "clean"), exist_ok=True)
            img.save(os.path.join(SOURCE, "clean", f"{asset_id}.png"))
        _images[asset_id] = img
    return _images[asset_id]


def crop(template, rect, w, h):
    x, y, rw, rh = rect
    return template.crop((x, y, x + rw, y + rh)).resize((w, h), Image.BICUBIC)


def part_color(look, part):
    head, torso, arm, leg = look["colors"]
    return {"Torso": torso, "ArmLeft": arm, "ArmRight": arm, "LegLeft": leg, "LegRight": leg}.get(part, head)


# r6_zombie.build paints through these three (this module is its painter), with paint.py's signatures.
def body_face(look, part, face, w, h, rng):
    out = Image.new("RGBA", (w, h), paint.rgb(part_color(look, part)))
    shirt, pants = image(look["shirt"]), image(look["pants"])
    layers = []
    if part == "Torso":
        layers = [(pants, TORSO), (shirt, TORSO)]
    elif part.startswith("Arm"):
        layers = [(shirt, LIMB_LEFT if part == "ArmLeft" else LIMB_RIGHT)]
    elif part.startswith("Leg"):
        layers = [(pants, LIMB_LEFT if part == "LegLeft" else LIMB_RIGHT)]
    for template, rects in layers:
        if template:
            out.alpha_composite(crop(template, rects[face], w, h))
    return out


def head_strip(look, w, h, side_top, side_bottom, rng):
    """The face is square on the head's front (the strip's middle) and spans its whole height, so it covers about the
    front 150 degrees, as a classic face does."""
    out = Image.new("RGBA", (w, h), paint.rgb(look["colors"][0]))
    face = image(look["face"])
    if face:
        out.alpha_composite(face.resize((h, h), Image.BICUBIC), (w // 2 - h // 2, 0))
    return out


def head_cap(look, d, top):
    return Image.new("RGBA", (d, d), paint.rgb(look["colors"][0]))


def main():
    painter = sys.modules[__name__]
    names = [a for a in sys.argv[4:] if a in SKINS] or list(SKINS)
    boxes = r6_zombie.r6_boxes(r6_zombie.OBJ)
    path = r6_zombie.find_head_mesh()
    profile = r6_zombie.head_profile(path)
    for name in names:
        # build seeds a random stream for paint.py's blotches; these faces are copied, never random.
        look = dict(SKINS[name], seed=0)
        r6_zombie.build(name, look, boxes, profile, False, painter, HIDDEN_FACES, ATLAS)


if __name__ == "__main__":
    main()
