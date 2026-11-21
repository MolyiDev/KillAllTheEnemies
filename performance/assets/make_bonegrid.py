"""
Build a single skinned mesh containing N independent elements, each driven by its own bone.

The point: the measured ceiling for skinned meshes is ~4800 INSTANCES, while a bone write costs 79ns. If the
ceiling is per-MeshPart rather than per-moving-thing, then packing many entities into one mesh - each bound to
its own bone - trades N instances for N/ELEMENTS instances and should move that ceiling a long way.

Construction, and why each choice matters:

  * ONE mesh object, N loose cubes, ALL CENTRED ON THE ORIGIN. They overlap at rest on purpose. A vertex is
    displaced by its bone's Transform applied about the bone's rest, so geometry centred on the bone's rest
    origin means `bone.Transform = <world CFrame>` places that element exactly there - the same mapping
    Ballarc's EnemiesController relies on. Give a cube a rest position away from its bone and the bone's
    Transform would orbit it instead of placing it.

  * EVERY BONE AT THE ORIGIN WITH AN IDENTITY REST. head (0,0,0), tail (0,1,0), roll 0 - in Blender a bone's
    local +Y runs head->tail, so this is the one orientation whose rest matrix is identity. Anything else bakes
    a rotation into the mapping above.

  * CUBES, NOT PLANES. A plane has a facing direction, and Blender's Z-up to FBX Y-up conversion makes it
    fiddly to predict which way it ends up pointing in Roblox. A cube is visible from every angle, and it
    matches the existing Test/Skeleton mesh geometry so the benchmark stays like-for-like.

  * ONE VERTEX GROUP PER BONE, weight 1.0, covering only that cube's 8 vertices. No blending between elements,
    so each bone moves exactly one cube and nothing else.

Run:  blender --background --python make_bonegrid.py
"""

import os
import sys

import bpy

ELEMENTS = 100
CUBE_SIZE = 2.0
OUT_DIR = os.path.dirname(os.path.abspath(__file__))
BASENAME = "BoneGrid%d" % ELEMENTS

CUBE_VERTS = [
    (-1, -1, -1),
    (1, -1, -1),
    (1, 1, -1),
    (-1, 1, -1),
    (-1, -1, 1),
    (1, -1, 1),
    (1, 1, 1),
    (-1, 1, 1),
]
CUBE_FACES = [
    (0, 1, 2, 3),
    (4, 7, 6, 5),
    (0, 4, 5, 1),
    (1, 5, 6, 2),
    (2, 6, 7, 3),
    (3, 7, 4, 0),
]


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)

    # ---- armature: N bones, all identity at the origin ----
    arm_data = bpy.data.armatures.new("Rig")
    arm_obj = bpy.data.objects.new("Rig", arm_data)
    bpy.context.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    arm_obj.select_set(True)

    bpy.ops.object.mode_set(mode="EDIT")
    names = []
    for i in range(ELEMENTS):
        name = "B%03d" % i
        names.append(name)
        bone = arm_data.edit_bones.new(name)
        bone.head = (0.0, 0.0, 0.0)
        bone.tail = (0.0, 1.0, 0.0)  # +Y is bone-local forward, so this rest matrix is identity
        bone.roll = 0.0
    bpy.ops.object.mode_set(mode="OBJECT")

    # ---- mesh: N cubes stacked on the origin ----
    half = CUBE_SIZE * 0.5
    verts = []
    faces = []
    for i in range(ELEMENTS):
        base = len(verts)
        verts.extend([(x * half, y * half, z * half) for (x, y, z) in CUBE_VERTS])
        faces.extend([tuple(base + v for v in face) for face in CUBE_FACES])

    mesh = bpy.data.meshes.new(BASENAME)
    mesh.from_pydata(verts, [], faces)
    mesh.validate()
    mesh.update()

    obj = bpy.data.objects.new(BASENAME, mesh)
    bpy.context.collection.objects.link(obj)

    # ---- one vertex group per bone, weight 1.0, that cube's 8 vertices only ----
    for i, name in enumerate(names):
        group = obj.vertex_groups.new(name=name)
        group.add(list(range(i * 8, i * 8 + 8)), 1.0, "REPLACE")

    obj.parent = arm_obj
    modifier = obj.modifiers.new(name="Armature", type="ARMATURE")
    modifier.object = arm_obj

    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action="SELECT")

    print("[BONEGRID] built %d cubes, %d bones, %d verts, %d faces"
          % (ELEMENTS, len(names), len(verts), len(faces)))
    return names


def export():
    written = []

    fbx_path = os.path.join(OUT_DIR, BASENAME + ".fbx")
    try:
        bpy.ops.export_scene.fbx(
            filepath=fbx_path,
            use_selection=False,
            object_types={"ARMATURE", "MESH"},
            add_leaf_bones=False,  # Roblox does not want the synthetic tip bones
            use_armature_deform_only=True,
            bake_anim=False,
            mesh_smooth_type="OFF",
            path_mode="COPY",
            embed_textures=False,
            global_scale=1.0,
        )
        written.append(fbx_path)
    except Exception as error:  # noqa: BLE001 - report and continue to the glTF fallback
        print("[BONEGRID] FBX export failed: %s" % error, file=sys.stderr)

    glb_path = os.path.join(OUT_DIR, BASENAME + ".glb")
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
        print("[BONEGRID] glTF export failed: %s" % error, file=sys.stderr)

    for path in written:
        print("[BONEGRID] wrote %s (%d bytes)" % (path, os.path.getsize(path)))
    if not written:
        raise SystemExit("[BONEGRID] no exporter succeeded")


build()
export()
