"""Proof that r6_zombie.py's sign table holds: builds the rig through to_fbx.build, poses a few clip frames, and
reads where the deformed limbs end up, in .bbmodel axes (front +Z, the zombie's left +X).

    blender -b --factory-startup --python tools/rig/check_pose.py -- Assets/models/Enemies/ZombieNormal.bbmodel
"""
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import to_fbx  # noqa: E402

src = sys.argv[sys.argv.index("--") + 1]
model = to_fbx.read(src)
CHECKS = [
    # clip, seconds, bone, what must hold of the centre of that limb's far end (x, y, z in studs, .bbmodel axes)
    ("Idle", 0.0, "ArmLeft", "forward", lambda c: c[2] > 1.2),
    ("Idle", 0.0, "ArmRight", "forward", lambda c: c[2] > 1.2),
    ("Walk", 0.2, "LegLeft", "forward", lambda c: c[2] > 0.3),
    ("Walk", 0.2, "LegRight", "back", lambda c: c[2] < -0.3),
    # Heights are from the limb's own pivot (its shoulder), not the model's origin, which moves with the hair.
    ("Attack", 0.42, "ArmLeft", "raised", lambda c: c[1] > 1.0),
    ("Fuse", 0.6, "ArmLeft", "out to its left", lambda c: c[0] > 2.0),
    ("Fuse", 0.6, "ArmRight", "out to its right", lambda c: c[0] < -2.0),
    ("Idle", 0.0, "Torso", "leaning forward", lambda c: c[2] > 0.02),
]
failed = 0
for clip, seconds, bone, label, test in CHECKS:
    rig, body = to_fbx.build(model)
    anim = next(a for a in model["animations"] if a["name"] == clip)
    to_fbx.action_for(model, rig, anim)
    bpy.context.scene.frame_set(int(round(seconds * to_fbx.FPS)))
    deps = bpy.context.evaluated_depsgraph_get()
    mesh = body.evaluated_get(deps).to_mesh()
    group = body.vertex_groups[bone].index
    # The limb's far end: the vertices lowest in the rest pose (the hand, the foot; for the torso, the hips).
    members = [(v.co, src_v.co) for v, src_v in zip(mesh.vertices, body.data.vertices)
               if any(g.group == group for g in src_v.groups)]
    low = min(rest.z for _, rest in members)
    pts = [co for co, rest in members if rest.z < low + 1e-4] if bone != "Torso" else [co for co, _ in members]
    cx = sum(p.x for p in pts) / len(pts)
    cy = sum(p.y for p in pts) / len(pts)
    cz = sum(p.z for p in pts) / len(pts)
    # Blender (x, y, z) -> .bbmodel (-x, z, y), already in studs.
    centre = (-cx, cz, cy)
    pivot = next(g["origin"] for g in model["groups"] if g["name"] == bone)
    if label == "raised":
        centre = (centre[0], centre[1] - pivot[1] / 8, centre[2])
    ok = test(centre)
    failed += 0 if ok else 1
    print(f"[POSE] {'PASS' if ok else 'FAIL'} {clip} {seconds:.2f}s {bone} {label}: "
          f"({centre[0]:+.2f}, {centre[1]:+.2f}, {centre[2]:+.2f})")
print(f"[POSE] {failed} failed")
