"""Renders of one look, for judging it before upload, posed on a clip frame with back faces culled the way Roblox
draws them (so the outline hull reads as it will in game): `<prefix>_views.png` (front, three-quarter, side, back,
from above) and `<prefix>_close.png` (the head).

    blender -b --factory-startup --python tools/rig/render.py -- <model.bbmodel> <refs/Name> [clip] [seconds]
"""
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import to_fbx  # noqa: E402

args = sys.argv[sys.argv.index("--") + 1:]
src, out = args[0], args[1]
os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
clip = args[2] if len(args) > 2 else None
seconds = float(args[3]) if len(args) > 3 else 0.0

model = to_fbx.read(src)
clip_model = model
if clip and not any(a["name"] == clip for a in model.get("animations", [])):
    # Clips live in ZombieNormal; pose any look with them.
    clip_model = to_fbx.read(os.path.join(os.path.dirname(src), "ZombieNormal.bbmodel"))
rig, body = to_fbx.build(model)
smooth = {body.vertex_groups[n].index for n in ("Head", "Hair") if n in body.vertex_groups}
for poly in body.data.polygons:
    poly.use_smooth = all(any(g.group in smooth for g in body.data.vertices[i].groups) for i in poly.vertices)
if clip:
    anim = next(a for a in clip_model["animations"] if a["name"] == clip)
    # Bone uuids differ between files; action_for keys by bone name, which is what both share.
    to_fbx.action_for(clip_model, rig, anim)
    bpy.context.scene.frame_set(int(round(seconds * to_fbx.FPS)))

scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
shading = scene.display.shading
shading.light = "STUDIO"
shading.color_type = "TEXTURE"
shading.show_backface_culling = True
scene.render.resolution_x = 420
scene.render.resolution_y = 560
scene.render.film_transparent = False
scene.world = bpy.data.worlds.new("World")
scene.world.color = (0.55, 0.6, 0.62)

height = max(v.co.z for v in body.data.vertices) - min(v.co.z for v in body.data.vertices)
cam_data = bpy.data.cameras.new("Cam")
cam_data.type = "ORTHO"
cam = bpy.data.objects.new("Cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam

# Blender front is +Y (the .bbmodel's +Z through to_fbx's axis map).
views = [("front", 0, 0.0, 1.15), ("three-quarter", 35, 10, 1.15), ("side", 90, 0, 1.15), ("back", 180, 0, 1.15),
         ("top", 20, 55, 1.15), ("head", 25, 8, 0.36)]
frames = []
for label, yaw, pitch, zoom in views:
    focus = Vector((0, 0, height * 0.32)) if label == "head" else Vector((0, 0, 0))
    d = height * 3
    a, p = math.radians(yaw), math.radians(pitch)
    cam.location = focus + Vector((math.sin(a) * math.cos(p), math.cos(a) * math.cos(p), math.sin(p))) * d
    cam.rotation_euler = (focus - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam_data.ortho_scale = height * zoom
    path = f"{out}__{label}.png"
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    frames.append(path)



def save_sheet(paths, out_path):
    sheet = bpy.data.images.new("sheet", 420 * len(paths), 560)
    pixels = [0.0] * (420 * len(paths) * 560 * 4)
    for i, path in enumerate(paths):
        img = bpy.data.images.load(path)
        src_px = list(img.pixels)
        for y in range(560):
            start = (y * 420 * len(paths) + i * 420) * 4
            pixels[start:start + 420 * 4] = src_px[y * 420 * 4:(y + 1) * 420 * 4]
        os.remove(path)
    sheet.pixels = pixels
    sheet.filepath_raw = out_path
    sheet.file_format = "PNG"
    sheet.save()
    print(f"[RENDER] {out_path}")


save_sheet(frames[:-1], f"{out}_views.png")
save_sheet(frames[-1:], f"{out}_close.png")
