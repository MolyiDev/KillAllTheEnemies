"""
Build a skinned mesh holding several ANIMATABLE bugs, each with a real bone hierarchy.

The flat packs (Pack010..Pack400) give one bone per element, which is position and rotation only. A walking bug
needs a bone per moving limb, so this builds a proper rig:

    Bug{i}_Root          body cube, bone rest = identity at the origin
      Bug{i}_L0..L3      four limb cubes, each a CHILD bone at its own offset

Driving it mirrors what BugsController already does with Motor6D:

    root.Transform = <world CFrame>        places the whole bug, limbs follow because they are children
    limb.Transform = <pose from a LUT>     swings that limb about its own joint, independently per bug

That last point is the whole reason not to use an AnimationController here: a single AnimationTrack has one
TimePosition, so every bug it drives would step in unison. Writing bone Transforms by hand - exactly the bargain
BugGait makes - gives each bug its own phase with no per-entity objects at all.

BONE BUDGET IS THE CONSTRAINT. The packing sweep found 25-50 bones per MeshPart is the sweet spot and anything
>=100 sits on a ~35% worse plateau. At 5 bones per bug that means 10 bugs per mesh, which is what BUGS_PER_MESH
is set to. (The step between 50 and 100 looks like a GPU skinning bone limit, so staying under it matters more
than packing more in.)

Geometry rules, and why:
  * the BODY cube is centred on the origin and its root bone rest is identity there, so
    `root.Transform = <world CFrame>` places the bug exactly at that CFrame - same mapping as BoneGrid.
  * each LIMB cube is centred on its own bone's rest offset, so `limb.Transform = CFrame.Angles(...)` pivots the
    limb about its joint instead of orbiting the body. Getting this backwards is the classic rig mistake.
  * every bug in a mesh is built at the origin, overlapping the others; they separate when their roots are written.

Run:  blender --background --python make_bugpack.py
"""

import os
import sys

import bpy

BUGS_PER_MESH = 10
LIMBS_PER_BUG = 4
BODY = (1.6, 2.6, 0.9)  # x, y(length), z in Blender axes
LIMB = (0.35, 1.2, 0.35)
LIMB_OFFSETS = [
    (0.9, 0.7, -0.4),
    (-0.9, 0.7, -0.4),
    (0.9, -0.7, -0.4),
    (-0.9, -0.7, -0.4),
]
NAME = "BugPack%02d" % BUGS_PER_MESH
OUT_DIR = os.path.dirname(os.path.abspath(__file__))

CUBE_FACES = [
    (0, 1, 2, 3),
    (4, 7, 6, 5),
    (0, 4, 5, 1),
    (1, 5, 6, 2),
    (2, 6, 7, 3),
    (3, 7, 4, 0),
]


def box(centre, size):
    cx, cy, cz = centre
    hx, hy, hz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
    return [
        (cx - hx, cy - hy, cz - hz),
        (cx + hx, cy - hy, cz - hz),
        (cx + hx, cy + hy, cz - hz),
        (cx - hx, cy + hy, cz - hz),
        (cx - hx, cy - hy, cz + hz),
        (cx + hx, cy - hy, cz + hz),
        (cx + hx, cy + hy, cz + hz),
        (cx - hx, cy + hy, cz + hz),
    ]


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)

    arm_data = bpy.data.armatures.new("Rig")
    arm_obj = bpy.data.objects.new("Rig", arm_data)
    bpy.context.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj

    bpy.ops.object.mode_set(mode="EDIT")
    group_names = []
    for bug in range(BUGS_PER_MESH):
        root_name = "Bug%02d_Root" % bug
        root = arm_data.edit_bones.new(root_name)
        root.head = (0.0, 0.0, 0.0)
        root.tail = (0.0, 1.0, 0.0)  # bone-local +Y is head->tail, so this rest matrix is identity
        root.roll = 0.0
        group_names.append(root_name)

        for limb in range(LIMBS_PER_BUG):
            ox, oy, oz = LIMB_OFFSETS[limb]
            limb_name = "Bug%02d_L%d" % (bug, limb)
            bone = arm_data.edit_bones.new(limb_name)
            bone.head = (ox, oy, oz)
            bone.tail = (ox, oy + 1.0, oz)
            bone.roll = 0.0
            bone.parent = root  # child, so it follows the root and pivots about its own rest
            bone.use_connect = False
            group_names.append(limb_name)
    bpy.ops.object.mode_set(mode="OBJECT")

    verts = []
    faces = []
    # vertex index ranges, in the same order as group_names
    spans = []
    for _ in range(BUGS_PER_MESH):
        base = len(verts)
        verts.extend(box((0.0, 0.0, 0.0), BODY))
        spans.append(list(range(base, base + 8)))
        faces.extend([tuple(base + v for v in f) for f in CUBE_FACES])

        for limb in range(LIMBS_PER_BUG):
            base = len(verts)
            verts.extend(box(LIMB_OFFSETS[limb], LIMB))
            spans.append(list(range(base, base + 8)))
            faces.extend([tuple(base + v for v in f) for f in CUBE_FACES])

    mesh = bpy.data.meshes.new(NAME)
    mesh.from_pydata(verts, [], faces)
    mesh.validate()
    mesh.update()

    obj = bpy.data.objects.new(NAME, mesh)
    bpy.context.collection.objects.link(obj)

    for name, span in zip(group_names, spans):
        group = obj.vertex_groups.new(name=name)
        group.add(span, 1.0, "REPLACE")

    obj.parent = arm_obj
    modifier = obj.modifiers.new(name="Armature", type="ARMATURE")
    modifier.object = arm_obj

    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action="SELECT")

    print("[BUGPACK] %s bugs=%d bonesPerBug=%d bones=%d verts=%d"
          % (NAME, BUGS_PER_MESH, LIMBS_PER_BUG + 1, len(group_names), len(verts)))


def export():
    written = []

    fbx_path = os.path.join(OUT_DIR, NAME + ".fbx")
    try:
        bpy.ops.export_scene.fbx(
            filepath=fbx_path,
            use_selection=False,
            object_types={"ARMATURE", "MESH"},
            add_leaf_bones=False,
            use_armature_deform_only=True,
            bake_anim=False,
            mesh_smooth_type="OFF",
            path_mode="COPY",
            embed_textures=False,
            global_scale=1.0,
        )
        written.append(fbx_path)
    except Exception as error:  # noqa: BLE001
        print("[BUGPACK] FBX export failed: %s" % error, file=sys.stderr)

    glb_path = os.path.join(OUT_DIR, NAME + ".glb")
    try:
        bpy.ops.export_scene.gltf(
            filepath=glb_path,
            export_format="GLB",
            export_skins=True,
            export_animations=False,
            export_apply=False,
        )
        written.append(glb_path)
    except Exception as error:  # noqa: BLE001
        print("[BUGPACK] glTF export failed: %s" % error, file=sys.stderr)

    for path in written:
        print("[BUGPACK] wrote %s (%d bytes)" % (path, os.path.getsize(path)))
    if not written:
        raise SystemExit("[BUGPACK] no exporter succeeded")


build()
export()
