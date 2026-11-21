"""A hair mesh (a Studio OBJ export of a hair accessory) onto the classic head, at a game budget.

    blender -b --factory-startup --python tools/rig/hair_import.py -- <Hair.obj> <out.json> [triangles] [tones...]

THE HAIR IS A ROBLOX TOOLBOX ACCESSORY (~/Downloads/Hair.obj), chosen to match the concept's
(Assets/models/Enemies/refs/concept/ZombieNormal_turnaround.png). Three earlier attempts built hair from the concept's
silhouettes in code (a visual hull, spikes, curved clumps) and none came close; hair like this is sculpted.

TURNED ROUND: the export's open side (where the face shows) came out at the back, so it is turned half round. Checked by
eye in Blender against a marker on the face: the long bangs at the front stopped at the brow only this way round.

FITTED BY NOT PIERCING THE HEAD: centred across, it is slid as low as it goes, and front to back, while no more than
FIT_TOLERANCE of its vertices fall inside the classic head (a cylinder a touch under its 0.601 radius). On the first
hair that put it 0.4 studs below the head's centre to 1.4 above, where the concept's runs -0.3 to 1.3.

DECIMATED to `triangles` (every body on screen wears it, up to 255). Its winding is kept as the export has it: hair cards
are open surfaces, so recomputing normals can turn some inward, and Roblox already draws exactly this winding. Its own UVs and texture are dropped: r6_zombie.py toon-shades it with the concept's three hair tones.

Output, in studs about the head's centre, .bbmodel axes (front +Z, the zombie's left +X):
`vertices`, `triangles`, `tones` (hex, light to dark) and `light`.
"""
import json
import math
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix

args = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = args[0], args[1]
TARGET = int(args[2]) if len(args) > 2 else 1000
# The concept palette's hair: highlight, base, shadow (ZombieNormal_texture_v3.png's swatches).
TONES = args[3:6] if len(args) > 5 else ["#365A87", "#171C28", "#10141E"]
LIGHT = np.array([0.25, 1.0, 0.45]) / np.linalg.norm([0.25, 1.0, 0.45])
HEAD_RADIUS = 0.601
FIT_TOLERANCE = 15

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.obj_import(filepath=SRC, forward_axis="NEGATIVE_Z", up_axis="Y")
hair = bpy.context.selected_objects[0]
bpy.context.view_layer.objects.active = hair
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# Blender is Z-up with the face toward -Y here; centre it across and turn it half round.
co = np.array([v.co for v in hair.data.vertices])
lo, hi = co.min(0), co.max(0)
centre = np.array([(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, lo[2]])
hair.data.transform(Matrix.Rotation(math.pi, 4, "Z") @ Matrix.Translation(-centre))
co = np.array([v.co for v in hair.data.vertices])


def piercing(offset):
    p = co + offset
    return int(((np.hypot(p[:, 0], p[:, 1]) < HEAD_RADIUS - 0.02) & (np.abs(p[:, 2]) < HEAD_RADIUS - 0.02)).sum())


best = None
for dy in np.arange(-0.3, 0.31, 0.02):
    for dz in np.arange(-1.2, 0.81, 0.02):
        n = piercing(np.array([0, dy, dz]))
        if n <= FIT_TOLERANCE and (best is None or dz < best[1] - 1e-9 or (abs(dz - best[1]) < 1e-9 and n < best[2])):
            best = (dy, dz, n)
hair.data.transform(Matrix.Translation((0, best[0], best[1])))

# Welded first: Studio's export splits every vertex at its UV seams (7,055 vertices on 2,135 positions for the first
# hair), and the decimator, seeing thousands of loose pieces, tore the cards into shards.
bm = bmesh.new()
bm.from_mesh(hair.data)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
bm.to_mesh(hair.data)
bm.free()

faces = len(hair.data.polygons)
mod = hair.modifiers.new("Decimate", "DECIMATE")
mod.decimate_type = "COLLAPSE"
mod.ratio = min(1.0, TARGET / max(1, faces))
mod.use_collapse_triangulate = True
bpy.ops.object.modifier_apply(modifier="Decimate")

bm = bmesh.new()
bm.from_mesh(hair.data)
bmesh.ops.triangulate(bm, faces=bm.faces)
bm.to_mesh(hair.data)
bm.free()

# Blender (x, y, z), face toward -Y, Z up -> .bbmodel (x, z, -y): front +Z, up +Y, the zombie's left +X either way.
verts = [[round(v.co.x, 5), round(v.co.z, 5), round(-v.co.y, 5)] for v in hair.data.vertices]
# That swap is a rotation (determinant +1), so the winding carries over unchanged.
tris = [list(p.vertices) for p in hair.data.polygons]
with open(OUT, "w") as f:
    json.dump({"vertices": verts, "triangles": tris, "tones": TONES, "light": LIGHT.round(4).tolist()}, f)
v = np.array(verts)
print(f"[HAIR] fit dy {best[0]:+.2f} dz {best[1]:+.2f} ({best[2]} vertices touch the head), {faces} -> {len(tris)} "
      f"triangles, extent {v.min(0).round(2)} .. {v.max(0).round(2)} studs")
