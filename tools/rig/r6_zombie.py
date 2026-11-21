"""R6 zombie rigs: `python3 tools/rig/r6_zombie.py [R6.obj] [head.mesh] [outdir]` writes one `.bbmodel` per enemy look
(the shared clips inside `ZombieNormal.bbmodel`) and each texture as a PNG beside it, in Assets/models/Enemies.
`tools/rig/build.sh` runs this, proves the clips (`check_pose.py`) and exports every file through `export.py`.

THE SHAPE IS ROBLOX'S R6. The torso and limbs are the five boxes of a Studio OBJ export of a plain R6 rig
(~/Downloads/R6.obj), at their exact sizes; the transparent HumanoidRootPart is left out. The HEAD is the classic
head, which the OBJ export loses (it holds only the 2 x 1 x 1 part box): Roblox's `content/avatar/heads/head.mesh`
is a cylinder of radius 0.601 with a quarter-round bevel of 0.3 top and bottom, centred on the Head part. Studio draws
it at the file's own size, 1.2 studs, whatever the SpecialMesh's Scale says (measured off a screenshot of the R6 in
the place against its 2-stud torso; the first build took Scale 1.25 at its word, and the head came out 1.5 studs and
sunk into the shoulders). So it stands 1.2 studs, its base a tenth of a stud under the torso's top.

EVERY BODY IS DRAWN UP TO 255 TIMES, so every triangle is paid for 255 times. Roblox chamfers a Part's edges, and the
boxes are chamfered (BEVEL) as R6's are, which costs 44 triangles a box against a plain cube's 12; that is paid back by
the head, rebuilt from head.mesh's profile with HEAD_SEGMENTS sides and HEAD_RINGS of its rings (132 triangles
against the file's 846), and by leaving out every face no camera can see (HIDDEN_FACES, the head's bottom cap).

THE LOOK IS ANIME (GDD section 9). A concept look (concept.py) is painted from its concept art and wears a hair mesh
(hair_import.py); the others are painted by paint.py: flat colour, one hard cel shadow, ink lines, an anime face.
An inverted-hull outline round the silhouette was tried and dropped: the references draw none, and it doubled the
triangles.

THE RIG IS BEACASTLELORD'S ENEMY CONTRACT (Models.md section 7, TData.TEnemyModel): bones `Root` > `Torso` >
`Head`, `ArmLeft`, `ArmRight`, `LegLeft`, `LegRight`; front is +Z and the zombie's left is +X; centred on Y with Root
at the feet; eight `.bbmodel` units to the stud (to_fbx.SCALE). Pivots: an arm turns about R6's own shoulder (half a
stud under the top of the arm), a leg about a point just inside the top of the thigh, the head low at the neck.

Each look is a SIZE and a palette. The texture is painted at the same pixels per stud of the base body for every
size, into one atlas of at most ATLAS pixels (Roblox's texture limit).
"""
import base64
import io
import json
import math
import os
import random
import struct
import sys
import uuid

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import clips  # noqa: E402
import concept  # noqa: E402
import paint  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
VINEGAR = os.path.expanduser("~/.var/app/org.vinegarhq.Vinegar/data/vinegar/versions")
OBJ = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/Downloads/R6.obj")
HEAD_MESH = sys.argv[2] if len(sys.argv) > 2 else None
# Assets/models/Enemies: the models and textures there, renders in refs/, FBXs in fbx/.
OUT = sys.argv[3] if len(sys.argv) > 3 else os.path.join(HERE, "..", "..", "Assets", "models", "Enemies")
UNITS = 8
HEAD_SCALE = 1.0
# The classic head's sides, and which of head.mesh's ten profile rings are kept (rim, mid-bevel, side top and bottom,
# mid-bevel, rim): smooth shading carries the curve between them, and the head is 132 triangles instead of 320.
HEAD_SEGMENTS = 12
HEAD_RINGS = (0, 2, 4, 5, 7, 9)
# Every box edge is chamfered this deep (studs at the base size), as Roblox draws R6's parts.
BEVEL = 0.06
# Faces no camera can see, left out: the torso's underside (the legs cover it) and the legs' tops (inside the torso).
HIDDEN_FACES = {"Torso": ("down",), "LegLeft": ("up",), "LegRight": ("up",)}
ATLAS = 1024
PADDING = 3


# ---------------------------------------------------------------- the R6 boxes, off the OBJ
def read_obj(path):
    groups, cur, verts = {}, None, []
    for line in open(path):
        p = line.split()
        if not p:
            continue
        if p[0] == "g":
            cur = p[1]
            groups.setdefault(cur, set())
        elif p[0] == "v":
            verts.append(tuple(map(float, p[1:4])))
        elif p[0] == "f":
            for t in p[1:]:
                groups[cur].add(int(t.split("/")[0]) - 1)
    return {name: (np.array([verts[i] for i in idx]).min(0), np.array([verts[i] for i in idx]).max(0))
            for name, idx in groups.items() if idx}


def r6_boxes(path):
    """Studs, in .bbmodel axes (Roblox x and z negated: Studio's front is -Z, the .bbmodel's +Z), feet at y = 0."""
    raw = read_obj(path)
    want = {"Torso1": "Torso", "Head1": "Head", "LeftArm1": "ArmLeft", "RightArm1": "ArmRight",
            "LeftLeg1": "LegLeft", "RightLeg1": "LegRight"}
    tlo, thi = raw["Torso1"]
    cx, cz = (tlo[0] + thi[0]) / 2, (tlo[2] + thi[2]) / 2
    feet = min(raw[k][0][1] for k in want)
    boxes = {}
    for src, name in want.items():
        lo, hi = raw[src]
        boxes[name] = (np.array([-(hi[0] - cx), lo[1] - feet, -(hi[2] - cz)]),
                       np.array([-(lo[0] - cx), hi[1] - feet, -(lo[2] - cz)]))
    # Studio's LeftArm is at -X in Roblox, so +X here: the zombie's left, as the contract wants.
    assert boxes["ArmLeft"][0][0] > 0 and boxes["LegLeft"][0][0] >= -1e-6, "left/right came out mirrored"
    return boxes


def find_head_mesh():
    if HEAD_MESH:
        return HEAD_MESH
    for version in sorted(os.listdir(VINEGAR), reverse=True) if os.path.isdir(VINEGAR) else []:
        path = os.path.join(VINEGAR, version, "content", "avatar", "heads", "head.mesh")
        if os.path.isfile(path):
            return path
    return None


def head_profile(path):
    """The classic head's profile, (radius, y) top to bottom, read off head.mesh (version 2.00): one ring per distinct
    height, its radius the ring's distance from the axis. Falls back to the measured numbers without the file."""
    if not path:
        full = [(0.301, 0.601), (0.416, 0.578), (0.513, 0.513), (0.578, 0.416), (0.601, 0.301),
                (0.601, -0.301), (0.578, -0.416), (0.513, -0.513), (0.416, -0.578), (0.301, -0.601)]
        return [full[i] for i in HEAD_RINGS]
    data = open(path, "rb").read()
    start = data.index(b"\n") + 1
    header, vsize, _fsize, nverts, _nfaces = struct.unpack_from("<HBBII", data, start)
    assert data.startswith(b"version 2.00"), "head.mesh is not version 2.00"
    rings = {}
    for i in range(nverts):
        x, y, z = struct.unpack_from("<3f", data, start + header + i * vsize)
        r = math.hypot(x, z)
        key = round(y, 3)
        rings[key] = max(rings.get(key, 0.0), r)
    full = [(round(rings[y], 3), y) for y in sorted(rings, reverse=True)]
    return [full[i] for i in HEAD_RINGS]


def pivots(boxes, head_center):
    t_lo, _ = boxes["Torso"]
    arm_l, arm_r = boxes["ArmLeft"], boxes["ArmRight"]
    leg_l, leg_r = boxes["LegLeft"], boxes["LegRight"]
    mid = lambda box: (box[0] + box[1]) / 2
    return {
        "Root": np.array([0.0, 0.0, 0.0]),
        "Torso": np.array([0.0, t_lo[1], 0.0]),
        # The neck: where the head meets the torso's top, a little back.
        "Head": np.array([head_center[0], boxes["Torso"][1][1], head_center[2] - 0.15]),
        "Hair": head_center.copy(),
        "ArmLeft": np.array([mid(arm_l)[0], arm_l[1][1] - 0.5, 0.0]),
        "ArmRight": np.array([mid(arm_r)[0], arm_r[1][1] - 0.5, 0.0]),
        "LegLeft": np.array([mid(leg_l)[0], leg_l[1][1] - 0.125, 0.0]),
        "LegRight": np.array([mid(leg_r)[0], leg_r[1][1] - 0.125, 0.0]),
    }


# Hair hangs off the head on its own bone, which no clip keys: it rides the head, and it is the one part exported flat
# (export.py smooths the Head group only), so its cel facets stay hard.
BONES = [("Root", None), ("Torso", "Root"), ("Head", "Torso"), ("Hair", "Head"), ("ArmLeft", "Torso"),
         ("ArmRight", "Torso"), ("LegLeft", "Torso"), ("LegRight", "Torso")]
BOX_PARTS = ("Torso", "ArmLeft", "ArmRight", "LegLeft", "LegRight")
FACES = ("north", "south", "east", "west", "up", "down")


# ---------------------------------------------------------------- looks
def tones(*cs):
    return [paint.rgb(c) for c in cs]


BLOOD = tones("#b8202e", "#7a121c")
# Light, base, shadow, deep. Each enemy wears a colour no other one does, and the hair is its anime identity.
LOOKS = {
    "ZombieNormal": dict(size=1.0, skin=tones("#c4dca4", "#a8c888", "#7fa070", "#5c7a54"),
                         shirt=tones("#8fb4d4", "#5f88ac", "#456a8c", "#2f4c68"),
                         pants=tones("#7a7488", "#524c60", "#3c3848", "#2a2634"), sleeves=True,
                         hair=("#6a7a5e", "#3a4636", "#262e24"), eye="#ffd84a", seed=1),
    "ZombieRunner": dict(size=1.0, skin=tones("#dfe8cc", "#bccca4", "#93a682", "#6c7e60"),
                         shirt=tones("#f08a92", "#c4505c", "#983844", "#6a2430"),
                         pants=tones("#6a6a7a", "#444454", "#30303e", "#20202a"), sleeves=False,
                         hair=("#ffffff", "#d0d6e4", "#9aa2b8"), eye="#ff5a5a", seed=2),
    "ZombieBrute": dict(size=1.25, skin=tones("#b4cc98", "#88a86c", "#647e52", "#46583a"), shirt=None,
                        pants=tones("#a88a68", "#7a5c40", "#5a422c", "#3e2c1e"), sleeves=False, hair=None,
                        scalp_scar=True, eye="#ffb030", seed=3),
    "ZombieExploder": dict(size=1.0, skin=tones("#e6ecb0", "#c4cc80", "#9aa25e", "#727842"),
                           shirt=tones("#ffd878", "#d8a840", "#a87e2c", "#7a5a1e"),
                           pants=tones("#9a9a72", "#6e6e4c", "#525238", "#3a3a28"), sleeves=True,
                           hair=("#ffc090", "#f08040", "#b85424"), eye="#ff8a20", pustules="#ff8a3a", seed=4),
    "ZombieSlammer": dict(size=1.15, skin=tones("#d6d0e0", "#aaa2b8", "#827a94", "#5e5670"),
                          shirt=tones("#c0a4e4", "#8866b4", "#664a8e", "#463266"),
                          pants=tones("#5a5a66", "#36363f", "#26262e", "#18181e"), sleeves=True,
                          hair=("#b494dc", "#6a4c90", "#45305e"), eye="#a0ff70", seed=5),
    "BossChampion": dict(size=2.4, skin=tones("#b4beb4", "#808e82", "#5e6a60", "#404a42"),
                         shirt=tones("#5e5260", "#342c34", "#221c22", "#141014"),
                         pants=tones("#c04850", "#7e2228", "#5a161c", "#3a0e12"), sleeves=True,
                         hair=("#ff5060", "#2a2030", "#16101a"), eye="#ff3040", trim="#d03040", seed=6),
}
for _look in LOOKS.values():
    _look["blood"] = BLOOD

# Looks painted from concept art (concept.py) rather than by paint.py, with a hair mesh fitted by hair_import.py.
CONCEPTS_DIR = os.path.join(OUT, "refs", "concept")
LOOKS["ZombieNormal"]["concept"] = {
    "sheet": os.path.join(CONCEPTS_DIR, "ZombieNormal_texture_v3.png"),
    "turnaround": os.path.join(CONCEPTS_DIR, "ZombieNormal_turnaround.png"),
    "hair": os.path.join(OUT, "ZombieNormal_hair.json"),
}


# ---------------------------------------------------------------- mesh building
class Mesh:
    """One .bbmodel mesh element: shared vertices, triangles wound counter-clockwise seen from outside (or inside,
    for the outline hull), a UV per corner in atlas pixels."""

    def __init__(self, name):
        self.name, self.vertices, self.faces = name, {}, {}

    def vertex(self, key, p):
        self.vertices[key] = [round(float(c), 5) for c in p]
        return key

    def tri(self, keys, uvs, outward, inward=False):
        a, b, c = (np.array(self.vertices[k]) for k in keys)
        n = np.cross(b - a, c - a)
        if (np.dot(n, outward) < 0) != inward:
            keys, uvs = (keys[0], keys[2], keys[1]), (uvs[0], uvs[2], uvs[1])
        self.faces[f"f{len(self.faces)}"] = {"vertices": list(keys), "texture": 0,
                                             "uv": {k: [round(u, 4), round(v, 4)] for k, (u, v) in zip(keys, uvs)}}

    def element(self):
        return {"uuid": str(uuid.uuid4()), "name": self.name, "type": "mesh", "origin": [0, 0, 0],
                "rotation": [0, 0, 0], "vertices": self.vertices, "faces": self.faces}


def head_mesh(profile, center, scale, uv_strip, uv_top):
    """The classic head as rings round the vertical axis, its side wrapped in the painted strip and its crown in the
    top cap. No bottom cap: it sits inside the torso."""
    mesh = Mesh("Head")
    seg = HEAD_SEGMENTS
    pts = [np.array(p) for p in profile]
    arcs = [0.0]
    for i in range(1, len(pts)):
        arcs.append(arcs[-1] + float(np.linalg.norm(pts[i] - pts[i - 1])))

    # The seam column shares the first column's vertices: UVs are per face corner, so the seam can still wrap the
    # strip, and the normals are smooth across it (a split column lit the back of the head in two halves).
    for i, (r, y) in enumerate(profile):
        for j in range(seg):
            phi = (j / seg - 0.5) * 2 * math.pi
            mesh.vertex(f"r{i}_{j}", center + np.array([math.sin(phi) * r, y, math.cos(phi) * r]) * scale)
    mesh.vertex("top", center + np.array([0, profile[0][1], 0]) * scale)

    def strip_uv(i, j):
        x, y, w, h = uv_strip
        return (x + w * j / seg, y + h * arcs[i] / arcs[-1])

    def cap_uv(key):
        x, y, d, _ = uv_top
        p = np.array(mesh.vertices[key]) - center
        rim = profile[0][0] * scale
        return (x + d * (0.5 + p[0] / (2 * rim) * 0.98), y + d * (0.5 + p[2] / (2 * rim) * 0.98))

    for i in range(len(profile) - 1):
        for j in range(seg):
            nj = (j + 1) % seg
            quad = [f"r{i}_{j}", f"r{i}_{nj}", f"r{i + 1}_{nj}", f"r{i + 1}_{j}"]
            uvs = [strip_uv(i, j), strip_uv(i, j + 1), strip_uv(i + 1, j + 1), strip_uv(i + 1, j)]
            mid = np.mean([mesh.vertices[k] for k in quad], axis=0) - center
            mesh.tri((quad[0], quad[1], quad[2]), (uvs[0], uvs[1], uvs[2]), mid)
            mesh.tri((quad[0], quad[2], quad[3]), (uvs[0], uvs[2], uvs[3]), mid)
    for j in range(seg):
        a, b = f"r0_{j}", f"r0_{(j + 1) % seg}"
        mesh.tri(("top", a, b), (cap_uv("top"), cap_uv(a), cap_uv(b)), np.array([0, 1, 0]))
    return mesh


# Each face's texture axes, as Blockbench maps a cube face (to_fbx.CUBE_FACE_CORNERS): the axis image-x runs along
# and the axis image-y runs down, each with its sign; and the face's own axis and side.
FACE_AXES = {
    "south": ((0, 1), (1, -1), (2, 1)), "north": ((0, -1), (1, -1), (2, -1)),
    "east": ((2, -1), (1, -1), (0, 1)), "west": ((2, 1), (1, -1), (0, -1)),
    "up": ((0, 1), (2, 1), (1, 1)), "down": ((0, 1), (2, -1), (1, -1)),
}


def chamfer_box(name, lo, hi, bevel, rects, hidden=()):
    """A box with every edge chamfered `bevel` deep, as Roblox draws a Part: each face inset by the bevel, a 45-degree
    strip along each edge and a triangle at each corner. A face's UVs are its place on the whole box, so the inset face
    shows its painting less the margin, and a strip shows the margin of the face that owns it (the side faces own their
    edges with the top and bottom; front and back own the vertical edges). `hidden` faces are left out."""
    mesh = Mesh(name)
    centre = (lo + hi) / 2

    def corner(face, i, j):
        """The inset face's corner i, j (0 toward lo, 1 toward hi along its two other axes)."""
        axis, side = FACE_AXES[face][2]
        others = [a for a in range(3) if a != axis]
        p = np.array(centre)
        p[axis] = hi[axis] if side > 0 else lo[axis]
        for a, t in zip(others, (i, j)):
            p[a] = hi[a] - bevel if t else lo[a] + bevel
        return mesh.vertex(f"{face}{i}{j}", p)

    def uv(face, key):
        x0, y0, x1, y1 = rects[face]
        p = np.array(mesh.vertices[key])
        (ua, us), (va, vs), _ = FACE_AXES[face]
        tu = (p[ua] - lo[ua]) / (hi[ua] - lo[ua])
        tv = (p[va] - lo[va]) / (hi[va] - lo[va])
        tu, tv = (tu if us > 0 else 1 - tu), (tv if vs > 0 else 1 - tv)
        return (x0 + tu * (x1 - x0), y0 + tv * (y1 - y0))

    def quad(keys, owner):
        out = np.mean([mesh.vertices[k] for k in keys], 0) - centre
        uvs = [uv(owner, k) for k in keys]
        mesh.tri((keys[0], keys[1], keys[2]), (uvs[0], uvs[1], uvs[2]), out)
        mesh.tri((keys[0], keys[2], keys[3]), (uvs[0], uvs[2], uvs[3]), out)

    for face in FACES:
        keys = [corner(face, 0, 0), corner(face, 1, 0), corner(face, 1, 1), corner(face, 0, 1)]
        if face not in hidden:
            quad(keys, face)
    owner_rank = {"south": 0, "north": 0, "east": 1, "west": 1, "up": 2, "down": 2}
    names = list(FACES)
    for fi, f in enumerate(names):
        for g in names[fi + 1:]:
            fa, fs = FACE_AXES[f][2]
            ga, gs = FACE_AXES[g][2]
            if fa == ga:
                continue
            third = 3 - fa - ga
            # f's edge toward g: its coordinate on g's axis at g's side; and g's edge toward f likewise.
            f_others = [a for a in range(3) if a != fa]
            g_others = [a for a in range(3) if a != ga]

            def edge(face, others, toward_axis, toward_side, t):
                ij = [0, 0]
                ij[others.index(toward_axis)] = 1 if toward_side > 0 else 0
                ij[others.index(third)] = t
                return corner(face, *ij)

            keys = [edge(f, f_others, ga, gs, 0), edge(f, f_others, ga, gs, 1), edge(g, g_others, fa, fs, 1),
                    edge(g, g_others, fa, fs, 0)]
            quad(keys, f if owner_rank[f] <= owner_rank[g] else g)
    for sx in (0, 1):
        for sy in (0, 1):
            for sz in (0, 1):
                side = (sx, sy, sz)
                keys = []
                for face in FACES:
                    axis, fside = FACE_AXES[face][2]
                    if (fside > 0) != bool(side[axis]):
                        continue
                    others = [a for a in range(3) if a != axis]
                    keys.append(corner(face, side[others[0]], side[others[1]]))
                owner = next(f for f in ("south", "north", "east", "west", "up", "down")
                             if (FACE_AXES[f][2][1] > 0) == bool(side[FACE_AXES[f][2][0]]))
                out = np.mean([mesh.vertices[k] for k in keys], 0) - centre
                mesh.tri(tuple(keys), tuple(uv(owner, k) for k in keys), out)
    return mesh.element()


# The hair's toon ramp: where it changes from light to base and base to shadow, as fractions across it. A vertex's
# place on the ramp is (1 - its normal's dot with the light) / 2, so the light band is what faces the light within
# about 60 degrees and the shadow is what faces away past about 100.
RAMP_WIDTH = 64
RAMP_EDGES = (0.22, 0.58)


def hair_mesh(hair, center, k, rect):
    """hair_import.py's mesh on the head: studs about the head's centre to .bbmodel units, each vertex's UV on the toon ramp
    by its smooth normal, so the tones meet in hard lines across a clump rather than one tone per facet."""
    verts = np.array(hair["vertices"])
    tris = np.array(hair["triangles"])
    normals = np.zeros_like(verts)
    a, b, c = verts[tris[:, 0]], verts[tris[:, 1]], verts[tris[:, 2]]
    face = np.cross(b - a, c - a)
    for corner in range(3):
        np.add.at(normals, tris[:, corner], face)
    normals /= np.linalg.norm(normals, axis=1, keepdims=True) + 1e-12
    ramp = (1 - normals @ np.array(hair["light"])) / 2
    mesh = Mesh("Hair")
    for i, v in enumerate(verts):
        mesh.vertex(f"h{i}", center + v * k)
    v_mid = rect["y"] + rect["h"] / 2
    for t, tri in enumerate(tris):
        keys = [f"h{i}" for i in tri]
        mesh.faces[f"f{t}"] = {"vertices": keys, "texture": 0, "uv": {
            key: [round(rect["x"] + 1 + ramp[i] * (rect["w"] - 2), 3), v_mid] for key, i in zip(keys, tri)}}
    return mesh.element()


def face_dims(lo, hi, face):
    s = hi - lo
    return {"north": (s[0], s[1]), "south": (s[0], s[1]), "east": (s[2], s[1]), "west": (s[2], s[1]),
            "up": (s[0], s[2]), "down": (s[0], s[2])}[face]


def pack(rects, size):
    """Shelf packing, tallest first, PADDING between rects. False when they do not fit."""
    rects.sort(key=lambda r: (-r["h"], -r["w"]))
    x = y = shelf = 0
    for r in rects:
        if x + r["w"] + PADDING > size:
            x, y, shelf = 0, y + shelf + PADDING, 0
        r["x"], r["y"] = x + PADDING, y + PADDING
        x += r["w"] + PADDING
        shelf = max(shelf, r["h"])
    return y + shelf + 2 * PADDING <= size


def paste(atlas, img, x, y):
    """With a bleed: the image stretched PADDING px past its edges first, so smooth sampling never reads the gap."""
    w, h = img.size
    atlas.paste(img.resize((w + 2 * PADDING, h + 2 * PADDING), Image.BILINEAR), (x - PADDING, y - PADDING))
    atlas.paste(img, (x, y))


# ---------------------------------------------------------------- build one look
def build(name, look, boxes_studs, profile, with_clips, painter=paint, hidden_faces=HIDDEN_FACES, atlas_size=ATLAS):
    """painter paints the faces (paint.py's body_face, head_strip, head_cap); hidden_faces are left out per part."""
    rng = random.Random(look["seed"])
    size = look["size"]
    head_lo, head_hi = boxes_studs["Head"]
    head_center = (head_lo + head_hi) / 2
    piv_studs = pivots(boxes_studs, head_center)

    # The atlas, at the most pixels per stud that fit.
    side_radius = max(r for r, _ in profile)
    circumference = 2 * math.pi * side_radius * HEAD_SCALE
    arc = sum(math.dist(profile[i], profile[i + 1]) for i in range(len(profile) - 1)) * HEAD_SCALE
    cap = 2 * profile[0][0] * HEAD_SCALE
    art = concept.Concept(look["concept"]) if look.get("concept") else None
    for density in range(128, 32, -4):
        rects = []
        for part in BOX_PARTS:
            lo, hi = boxes_studs[part]
            for face in FACES:
                if face in hidden_faces.get(part, ()):
                    continue
                w, h = face_dims(lo, hi, face)
                rects.append(dict(kind="box", part=part, face=face, w=max(4, round(w * density)),
                                  h=max(4, round(h * density))))
        rects.append(dict(kind="strip", w=round(circumference * density), h=round(arc * density)))
        rects.append(dict(kind="top", w=round(cap * density), h=round(cap * density)))

        if art:
            # The hair's toon ramp: its three tones as hard bands, light to dark.
            rects.append(dict(kind="hair", w=RAMP_WIDTH, h=8))
        if pack(rects, atlas_size):
            break

    atlas = Image.new("RGBA", (atlas_size, atlas_size), paint.INK)
    for r in rects:
        if r["kind"] == "box":
            img = (art.face(r["part"], r["face"], r["w"], r["h"]) if art
                   else painter.body_face(look, r["part"], r["face"], r["w"], r["h"], rng))
        elif r["kind"] == "strip" and art:
            # The sheet's strip spans the whole way round, so it keeps its own proportions at the strip's width.
            band = round(r["w"] * (concept.STRIP[3] - concept.STRIP[1]) / (concept.STRIP[2] - concept.STRIP[0]))
            img = art.strip(r["w"], r["h"], min(band, r["h"]))
        elif r["kind"] == "strip":
            rings_v = [arcs * r["h"] / arc for arcs in np.cumsum([0] + [
                math.dist(profile[i], profile[i + 1]) * HEAD_SCALE for i in range(len(profile) - 1)])]
            sides = [i for i, (radius, _) in enumerate(profile) if radius >= side_radius - 1e-6]
            img = painter.head_strip(look, r["w"], r["h"], rings_v[sides[0]], rings_v[sides[-1]], rng)
        elif r["kind"] == "top" and art:
            img = art.cap(r["kind"], r["w"], profile[0][0] / side_radius)
        elif r["kind"] == "top":
            img = painter.head_cap(look, r["w"], True)
        elif r["kind"] == "hair":
            img = Image.new("RGBA", (r["w"], r["h"]), paint.rgb(art.hair["tones"][2]))
            light, base = (round(edge * r["w"]) for edge in RAMP_EDGES)
            img.paste(Image.new("RGBA", (light, r["h"]), paint.rgb(art.hair["tones"][0])), (0, 0))
            img.paste(Image.new("RGBA", (base - light, r["h"]), paint.rgb(art.hair["tones"][1])), (light, 0))
        paste(atlas, img, r["x"], r["y"])
    atlas.save(os.path.join(OUT, f"{name}_diff.png"))
    buf = io.BytesIO()
    atlas.save(buf, "PNG")

    # Geometry in .bbmodel units at the look's size, centred on Y (the hull's extra is even top and bottom).
    k = UNITS * size
    boxes = {p: (lo * k, hi * k) for p, (lo, hi) in boxes_studs.items()}
    piv = {p: v * k for p, v in piv_studs.items()}
    center_head = head_center * k
    head_top = center_head[1] + profile[0][1] * HEAD_SCALE * k
    if art:
        # The hair stands over the head, and the model is centred on its whole height (feet at the bottom of its
        # extents is what EnemiesController's ground lift assumes).
        head_top = max(head_top, center_head[1] + max(v[1] for v in art.hair["vertices"]) * k)
    height = max(head_top, max(hi[1] for p, (_, hi) in boxes.items() if p != "Head"))
    shift = np.array([0.0, -height / 2, 0.0])
    boxes = {p: (lo + shift, hi + shift) for p, (lo, hi) in boxes.items()}
    piv = {p: v + shift for p, v in piv.items()}
    center_head = center_head + shift
    bevel = BEVEL * k

    by = {(r.get("part"), r.get("face")): r for r in rects if r["kind"] == "box"}
    special = {r["kind"]: r for r in rects if r["kind"] != "box"}

    group_uuids = {bone: str(uuid.uuid4()) for bone, _ in BONES}
    elements, owned = [], {bone: [] for bone, _ in BONES}
    for part in BOX_PARTS:
        lo, hi = boxes[part]
        hidden = hidden_faces.get(part, ())
        # A hidden face's rect was never packed; its strips still read a margin, so they borrow its opposite face's.
        opposite = {"up": "down", "down": "up", "south": "north", "north": "south", "east": "west", "west": "east"}
        uv_rects = {}
        for face in FACES:
            r = by.get((part, face)) or by[(part, opposite[face])]
            uv_rects[face] = (r["x"], r["y"], r["x"] + r["w"], r["y"] + r["h"])
        element = chamfer_box(part, lo, hi, bevel, uv_rects, hidden)
        elements.append(element)
        owned[part].append(element["uuid"])

    s, t = special["strip"], special["top"]
    head = head_mesh(profile, center_head, HEAD_SCALE * k, (s["x"], s["y"], s["w"], s["h"]),
                     (t["x"], t["y"], t["w"], t["h"])).element()
    elements.append(head)
    owned["Head"].append(head["uuid"])
    if art:
        hair = hair_mesh(art.hair, center_head, k, special["hair"])
        elements.append(hair)
        owned["Hair"].append(hair["uuid"])

    groups = [{"uuid": group_uuids[bn], "name": bn, "origin": [round(v, 4) for v in piv[bn]], "rotation": [0, 0, 0],
               "visibility": True, "export": True} for bn, _ in BONES]

    def node(bone):
        kids = [node(bn) for bn, p in BONES if p == bone]
        return {"uuid": group_uuids[bone], "isOpen": True, "children": owned[bone] + kids}

    model = {
        "meta": {"format_version": "5.0", "model_format": "free", "box_uv": False},
        "name": name,
        "model_identifier": name,
        "resolution": {"width": atlas_size, "height": atlas_size},
        "elements": elements,
        "groups": groups,
        "outliner": [node("Root")],
        # Front sides only, as Roblox draws a MeshPart: drawn double-sided, the inward-facing outline hull covers the
        # whole body in ink (the first look in Blockbench was all black).
        "textures": [{"uuid": str(uuid.uuid4()), "name": f"{name}_diff.png", "id": "0", "width": atlas_size,
                      "height": atlas_size, "uv_width": atlas_size, "uv_height": atlas_size, "render_mode": "default",
                      "render_sides": "front",
                      "source": "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()}],
        "animations": [clips.animation(n, fn, looped, group_uuids) for n, fn, looped in clips.CLIPS]
        if with_clips else [],
    }
    with open(os.path.join(OUT, f"{name}.bbmodel"), "w") as f:
        json.dump(model, f)

    for part in BOX_PARTS:
        lo, hi = boxes[part]
        assert np.all(piv[part] >= lo - 1e-6) and np.all(piv[part] <= hi + 1e-6), f"{name}: {part} pivot outside"
    triangles = sum(len(e["faces"]) * (1 if e.get("type") == "mesh" else 2) for e in elements)
    print(f"{name}: {height / UNITS:.2f} studs tall, {density} px/stud, {triangles} triangles"
          f"{' (concept art, hair)' if art else ''}, {len(model['animations'])} clips")


def main():
    os.makedirs(OUT, exist_ok=True)
    boxes = r6_boxes(OBJ)
    path = find_head_mesh()
    profile = head_profile(path)
    print(f"head profile from {path or 'the measured numbers'}: {len(profile)} rings")
    for name, look in LOOKS.items():
        build(name, look, boxes, profile, with_clips=name == "ZombieNormal")


if __name__ == "__main__":
    main()
