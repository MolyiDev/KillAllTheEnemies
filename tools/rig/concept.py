"""A look painted from concept art instead of by paint.py: the turnaround's own views projected onto the R6 faces, the
texture sheet for what no view shows, its head strip wrapped round the classic head, and hair_import.py's hair.

THE VIEWS COME FIRST BECAUSE THEY AGREE WITH EACH OTHER. The first build cut every face from the sheet's separate
tiles, which ChatGPT paints one at a time: the sleeve's hem, the blood and the tears ended at a different height on
every face, so no edge met its neighbour. The turnaround's front, back, left and right views are one picture of one
model, so a sleeve hem in the front view and in the side view stand at the same height and the faces meet.
VIEW_FACES holds each part's box in each view. A limb's inner face (never drawn) is its outer view mirrored, which
puts its front edge against the front face; the torso's sides (behind the arms in every view), every top and every
bottom come from the sheet's tiles.

THE SHEET IS ChatGPT'S, so its tiles are where it drew them, not on a grid: TILES holds each one's box in
`ZombieNormal_texture_v3.png`, found by flood-filling the sheet's background (every tile is a solid block on it) and
named by the sheet's own labels. A new sheet needs its boxes measured again. Each tile is drawn as seen from outside
with its top up, which is how Blockbench maps a side face; a top tile is drawn with the model's front at its top edge
(the neck notch of the torso's), the opposite of Blockbench's `up`, so tops are flipped.

The sheet's strip is the head unrolled, the face in the middle and the back at both ends, but drawn shallower than the
head's whole profile: it covers the band round the face, so it is centred on the profile and its top and bottom rows
are stretched over the bevels (the hair hides the crown anyway).
"""
import json

from PIL import Image, ImageOps

INSET = 4

TILES = {
    ("Torso", "south"): (36, 22, 288, 226), ("Torso", "north"): (320, 22, 584, 226),
    ("Torso", "east"): (636, 22, 730, 226), ("Torso", "west"): (796, 22, 896, 226),
    ("Torso", "up"): (936, 92, 1216, 224), ("Torso", "down"): (1248, 90, 1504, 226),
    ("ArmLeft", "south"): (36, 272, 118, 448), ("ArmLeft", "north"): (158, 272, 242, 448),
    ("ArmLeft", "east"): (278, 272, 362, 448), ("ArmLeft", "west"): (402, 272, 488, 448),
    ("ArmLeft", "up"): (524, 326, 620, 422), ("ArmLeft", "down"): (650, 326, 748, 440),
    ("ArmRight", "south"): (790, 272, 878, 448), ("ArmRight", "north"): (916, 272, 1004, 448),
    ("ArmRight", "west"): (1042, 272, 1128, 448), ("ArmRight", "east"): (1166, 272, 1250, 448),
    ("ArmRight", "up"): (1284, 326, 1380, 422), ("ArmRight", "down"): (1410, 326, 1506, 440),
    ("LegLeft", "south"): (36, 498, 118, 660), ("LegLeft", "north"): (154, 498, 238, 660),
    ("LegLeft", "east"): (276, 498, 362, 660), ("LegLeft", "west"): (400, 498, 484, 660),
    ("LegLeft", "up"): (522, 534, 616, 632), ("LegLeft", "down"): (650, 534, 746, 632),
    ("LegRight", "south"): (794, 498, 880, 660), ("LegRight", "north"): (918, 498, 1004, 660),
    ("LegRight", "west"): (1042, 498, 1128, 660), ("LegRight", "east"): (1166, 498, 1250, 660),
    ("LegRight", "up"): (1286, 534, 1380, 632), ("LegRight", "down"): (1412, 534, 1506, 632),
}
STRIP = (402, 718, 1076, 856)

# Each face's box in ZombieNormal_turnaround.png's full-body row (x0, y0, x1, y1), measured on gridded crops, and
# whether it is mirrored. Front view: the zombie's right arm on the image's left, +X to the right. Back view: its left
# arm on the image's left. Left view (its +X side, `east`): the face toward the image's left, as Blockbench maps east.
# Right view (`west`): the face toward the image's right, as Blockbench maps west.
VIEW_FACES = {
    ("Torso", "south"): ((135, 181, 295, 350), False),
    ("ArmRight", "south"): ((65, 181, 133, 369), False),
    ("ArmLeft", "south"): ((296, 181, 364, 369), False),
    ("LegRight", "south"): ((136, 350, 215, 528), False),
    ("LegLeft", "south"): ((215, 350, 296, 528), False),
    ("Torso", "north"): ((486, 182, 649, 368), False),
    ("ArmLeft", "north"): ((416, 182, 483, 369), False),
    ("ArmRight", "north"): ((651, 182, 719, 369), False),
    ("LegLeft", "north"): ((486, 370, 567, 528), False),
    ("LegRight", "north"): ((569, 370, 649, 528), False),
    ("ArmLeft", "east"): ((850, 168, 937, 368), False),
    ("LegLeft", "east"): ((851, 370, 938, 528), False),
    ("ArmRight", "west"): ((1149, 182, 1238, 369), False),
    ("LegRight", "west"): ((1149, 370, 1236, 528), False),
    ("ArmLeft", "west"): ((850, 168, 937, 368), True),
    ("LegLeft", "west"): ((851, 370, 938, 528), True),
    ("ArmRight", "east"): ((1149, 182, 1238, 369), True),
    ("LegRight", "east"): ((1149, 370, 1236, 528), True),
}
# The drawn parts have rounded, outlined corners; this much is cut off each side so neither reaches the face.
VIEW_INSET = 3
CAPS = {"top": (1208, 712, 1354, 858), "bottom": (1372, 712, 1518, 858)}


class Concept:
    def __init__(self, spec):
        self.sheet = Image.open(spec["sheet"]).convert("RGBA")
        self.turnaround = Image.open(spec["turnaround"]).convert("RGBA")
        with open(spec["hair"]) as f:
            self.hair = json.load(f)

    def _tile(self, box):
        x0, y0, x1, y1 = box
        return self.sheet.crop((x0 + INSET, y0 + INSET, x1 - INSET, y1 - INSET))

    def face(self, part, face, w, h):
        view = VIEW_FACES.get((part, face))
        if view:
            (x0, y0, x1, y1), mirrored = view
            img = self.turnaround.crop((x0 + VIEW_INSET, y0 + VIEW_INSET, x1 - VIEW_INSET, y1 - VIEW_INSET))
            if mirrored:
                img = ImageOps.mirror(img)
            return img.resize((w, h), Image.LANCZOS)
        img = self._tile(TILES[(part, face)])
        if face == "up":
            img = ImageOps.flip(img)
        return img.resize((w, h), Image.LANCZOS)

    def strip(self, w, h, band_px):
        """The head's side: the sheet's strip `band_px` tall, centred, its edge rows stretched to fill the rest."""
        band = self._tile(STRIP).resize((w, band_px), Image.LANCZOS)
        out = Image.new("RGBA", (w, h))
        top = (h - band_px) // 2
        out.paste(band.crop((0, 0, w, 1)).resize((w, top)), (0, 0))
        out.paste(band, (0, top))
        rest = h - top - band_px
        if rest > 0:
            out.paste(band.crop((0, band_px - 1, w, band_px)).resize((w, rest)), (0, top + band_px))
        return out

    def cap(self, which, d, rim_fraction):
        """The flat middle of a head cap: the sheet's circle is the whole head seen from above or below, and the cap
        is only its middle `rim_fraction` across (the bevels belong to the strip)."""
        x0, y0, x1, y1 = CAPS[which]
        cx, cy, r = (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2 * rim_fraction
        return self.sheet.crop((round(cx - r), round(cy - r), round(cx + r), round(cy + r))).resize((d, d), Image.LANCZOS)
