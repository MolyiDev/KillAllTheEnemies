"""
Build one skinned mesh per ELEMENTS-PER-MESH packing, each in ITS OWN FILE so each is a separate import.

100 elements per MeshPart beat 1 per MeshPart by roughly 4x on the ceiling. This finds where the curve actually
turns: too few and you are back to paying per-MeshPart, too many and each mesh becomes a huge all-or-nothing
culling and skinning unit.

Writes one FBX + GLB per packing, each containing exactly one mesh and one armature, matching BoneGrid100:

    Pack010  Pack025  Pack050  Pack100  Pack200  Pack400      plain, for the packing sweep
    PackTinted                                                 100 elements, each a DIFFERENT vertex colour

PackTinted answers the colour question directly: MeshPart.Color is one property for the whole mesh and a Bone
carries only a Transform, so elements cannot be recoloured at runtime by property writes. Baking a distinct
colour per element makes colour a property of WHICH SLOT a bug occupies instead. If the vertex colours survive
the importer, that approach is available; if they come in flat, it is not.

Same construction rules as make_bonegrid.py, and they matter for the same reasons:
  * every element centred on the origin, so `bone.Transform = <world CFrame>` places it exactly there
  * every bone at the origin with an identity rest (head (0,0,0), tail (0,1,0), roll 0)
  * cubes rather than planes, so orientation survives the Z-up to Y-up conversion
  * one vertex group per bone at weight 1.0 covering only that element's 8 vertices - no blending

An earlier version put all seven meshes in one file. Besides being one awkward import, it exposed a trap: a mesh
name that is a strict prefix of another ("Pack100" vs "Pack100C") made the FBX round-trip bind the wrong
armature to Pack100 and silently drop its skinning. One mesh per file removes the possibility entirely.

Run:  blender --background --python make_packings.py
"""

import colorsys
import os
import sys

import bpy

PACKINGS = [10, 25, 50, 100, 200, 400]
TINTED_ELEMENTS = 100
TINTED_NAME = "PackTinted"
CUBE_SIZE = 2.0
OUT_DIR = os.path.dirname(os.path.abspath(__file__))

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


def make_pack(name, elements, coloured):
    """A fresh scene holding exactly one armature and one mesh of `elements` cubes, bound 1:1."""
    bpy.ops.wm.read_factory_settings(use_empty=True)

    arm_data = bpy.data.armatures.new("Rig")
    arm_obj = bpy.data.objects.new("Rig", arm_data)
    bpy.context.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj

    bpy.ops.object.mode_set(mode="EDIT")
    names = []
    for i in range(elements):
        bone_name = "B%03d" % i
        names.append(bone_name)
        bone = arm_data.edit_bones.new(bone_name)
        bone.head = (0.0, 0.0, 0.0)
        bone.tail = (0.0, 1.0, 0.0)  # bone-local +Y is head->tail, so this rest matrix is identity
        bone.roll = 0.0
    bpy.ops.object.mode_set(mode="OBJECT")

    half = CUBE_SIZE * 0.5
    verts = []
    faces = []
    for _ in range(elements):
        base = len(verts)
        verts.extend([(x * half, y * half, z * half) for (x, y, z) in CUBE_VERTS])
        faces.extend([tuple(base + v for v in face) for face in CUBE_FACES])

    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.validate()
    mesh.update()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)

    for i, bone_name in enumerate(names):
        group = obj.vertex_groups.new(name=bone_name)
        group.add(list(range(i * 8, i * 8 + 8)), 1.0, "REPLACE")

    if coloured:
        # One distinct hue per element, so colour becomes "which slot you are in".
        layer = mesh.color_attributes.new(name="Col", type="BYTE_COLOR", domain="CORNER")
        for poly in mesh.polygons:
            element = poly.vertices[0] // 8
            r, g, b = colorsys.hsv_to_rgb((element % elements) / float(elements), 0.85, 1.0)
            for loop_index in poly.loop_indices:
                layer.data[loop_index].color = (r, g, b, 1.0)

    obj.parent = arm_obj
    modifier = obj.modifiers.new(name="Armature", type="ARMATURE")
    modifier.object = arm_obj

    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action="SELECT")

    return len(verts)


def export(name):
    written = []

    fbx_path = os.path.join(OUT_DIR, name + ".fbx")
    try:
        bpy.ops.export_scene.fbx(
            filepath=fbx_path,
            use_selection=False,
            object_types={"ARMATURE", "MESH"},
            add_leaf_bones=False,
            use_armature_deform_only=True,
            bake_anim=False,
            mesh_smooth_type="OFF",
            colors_type="SRGB",
            path_mode="COPY",
            embed_textures=False,
            global_scale=1.0,
        )
        written.append(fbx_path)
    except Exception as error:  # noqa: BLE001 - fall through to glTF
        print("[PACK] %s FBX export failed: %s" % (name, error), file=sys.stderr)

    glb_path = os.path.join(OUT_DIR, name + ".glb")
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
        print("[PACK] %s glTF export failed: %s" % (name, error), file=sys.stderr)

    if not written:
        raise SystemExit("[PACK] %s: no exporter succeeded" % name)
    return written


def emit(name, elements, coloured):
    verts = make_pack(name, elements, coloured)
    written = export(name)
    sizes = " ".join("%s=%dB" % (os.path.basename(p), os.path.getsize(p)) for p in written)
    print("[PACK] %-11s elements=%-4d bones=%-4d verts=%-5d coloured=%-5s | %s"
          % (name, elements, elements, verts, coloured, sizes))


for count in PACKINGS:
    emit("Pack%03d" % count, count, False)
emit(TINTED_NAME, TINTED_ELEMENTS, True)
