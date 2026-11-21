"""(Vendored from BeACastleLord tools/bbanim/to_fbx.py, unchanged below this line.)

`.bbmodel` -> a SKINNED FBX Roblox will take, plus one FBX per clip.

    blender -b --factory-startup --python tools/bbanim/to_fbx.py -- Assets/models/Enemies/ZombieBrute.bbmodel out/

Why this exists rather than Blockbench's own FBX export: **Blockbench writes a rigidly PARENTED file,
not a skinned one.** Its export has the right bone tree and all the animation stacks, but no `Deformer`
and no `Pose` - each limb is its own mesh node hanging off its bone node. Roblox needs skin deformers to
give back one MeshPart with `Bone` children, which is what `EnemiesController` reaches for
(`model.PrimaryPart.Root`). Converting is lossless because this rig is rigid to begin with: every mesh
binds 100% to the one bone it hangs off, so each parent relationship becomes a single full-weight vertex
group. That is the same property `rbx_to_bbmodel` relied on going the other way.

TWO COORDINATE FACTS, and everything else follows from them.

**Axes.** The `.bbmodel` is Y-up and so is FBX, but Blender is Z-up and its exporter converts on the way
out. The mapping that survives the round trip, measured by uploading one and reading the bones back out
of Studio, is bbmodel `(x, y, z)` -> Blender `(-x, z, y)`.

The obvious `(x, -z, y)` is wrong by a HALF TURN ABOUT Y, and it is wrong in the way that is hardest to
notice: mesh, bones and animation all come back rotated together, so the rig is perfectly self-consistent
and simply faces backwards. Nothing about the file looks wrong and nothing about the animation looks
wrong; the Brute just walks at its target back-first. It was caught by reading `ArmRight`'s bone CFrame
in a playtest - `(+2.0, 2.54, -0.74)` studs where the `.bbmodel` says `(-2.0, 2.54, +0.74)`.

Because the extra half turn goes on the DATA rather than on the object, the bones' rest frames turn with
it and the pose values, which live in bone-local space, do not change at all.

**Bone axes.** A Blender bone's local Y runs along the bone. Build every bone pointing along Blender +Z
with zero roll and its local axes come out as `(world X, world Z, world -Y)` - which under the mapping
above is the bbmodel frame turned the same half turn as everything else. So a pose bone's
`rotation_euler` in XYZ mode is the `.bbmodel` Euler VERBATIM (Blender's XYZ order composes `Rz.Ry.Rx`,
which is what `mathlib.euler_to_mat` does) and its `location` is the bbmodel translation, with no
conjugation anywhere.
"""
import json
import math
import os
import sys

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

# EIGHT .bbmodel units to the stud, not sixteen. The extractor scaled by 16 from the MESH's own units and
# the rig is used at twice its natural size in game, so the in-game stud is half of that: the body spans
# 57.84 units and stands 7.23 studs, 44 units across and 5.5 studs wide. Getting this wrong is not just a
# size to fix afterwards - `MeshPart.Size` rescales a skinned mesh happily, but an animation's Pose
# translations are absolute studs and do NOT rescale with it, so a half-size rig bakes half-size lunges.
SCALE = 1.0 / 8.0
FPS = 60
# Bones are all the same length; it is cosmetic, and only their heads and their axes carry meaning.
BONE_LENGTH = 0.5

# THE BONE FRAME ARRIVES HALF-TURNED ABOUT Y, so every pose channel plays with its X and Z inverted.
# `bake_anim` writes the curves against whatever bone axes the exporter settles on, and
# `primary_bone_axis` / `secondary_bone_axis` mean it picks those itself - the edit bone's own roll is
# discarded, so this cannot be fixed by orienting the bones and has to be undone in the data.
#
# Measured, not reasoned. A throwaway clip that turns one bone +20 degrees about each axis in turn and
# then slides the torso +8 units along each came back:
#
#     rot  x=+20 -> -19.8    y=+20 -> +19.6    z=+20 -> -19.3
#     pos  x=+8  ->  -7.6    y=+8  ->  +7.6    z=+8  ->  -7.4
#
# Same flip on both channels, which is what makes it a frame and not a convention. (The few per cent
# short is the probe sampling a linear ramp a fraction of a frame early, not an error in the file.)
#
# BOTH CHANNELS. Applying it to the rotation alone is what shipped ZombieBrute's hit reaction throwing
# its arms forward where the .bbmodel throws them back, and it hid in the other six clips because the
# error scales with how far the bone travels. Confirmed end to end on a live asset, which is the only
# place it can be confirmed - `verify_fbx.py` cannot see this constant at all, since Blender undoes on
# the way in whatever it did on the way out: the Runner's Death carries its torso +10.24 units along z,
# this writes -10.24 into the FBX, and Roblox reports the Pose at +10.24.
#
# Animations.md section 7 has the rest, including why changing this file makes every clip already
# uploaded stale with nothing in Studio to show it.
AXIS_SIGN = (-1.0, 1.0, -1.0)


def bb_to_blender(p):
    return Vector((-p[0] * SCALE, p[2] * SCALE, p[1] * SCALE))


def read(path):
    with open(path) as f:
        return json.load(f)


def bone_tree(model):
    """[(name, parent, origin)] in parents-first order, and the element uuids each bone owns.

    Blockbench writes the bone tree two ways and both are current: the extractor's shape inlines each
    group's fields into `outliner`, while a file re-saved from the app keeps them in a flat `groups`
    array and leaves `outliner` holding only uuids and nesting. Read whichever is there - `bblib` does
    the same, and a file that has been opened once arrives in the second shape whatever wrote it first.
    """
    order, owns = [], {}
    by_uuid = {g["uuid"]: g for g in model.get("groups", [])}

    def walk(node, parent):
        group = by_uuid.get(node["uuid"], node)
        # The nesting is on the outliner node and the fields are on the group, so both are read.
        children = node.get("children", [])
        order.append((group["name"], parent, group["origin"]))
        owns[group["name"]] = [c for c in children if isinstance(c, str)]
        for child in children:
            if not isinstance(child, str):
                walk(child, group["name"])

    for root in model["outliner"]:
        walk(root, None)
    return order, owns


# Each cube face's corners as the texture lays on them: (top-left, top-right, bottom-left, bottom-right), every
# face seen from outside with its top up (Blockbench 5, `free` format, measured; Textures.md §6). Indices pick
# from/to per axis: 0 = from, 1 = to.
CUBE_FACE_CORNERS = {
    "north": ((1, 1, 0), (0, 1, 0), (1, 0, 0), (0, 0, 0)),
    "south": ((0, 1, 1), (1, 1, 1), (0, 0, 1), (1, 0, 1)),
    "west": ((0, 1, 0), (0, 1, 1), (0, 0, 0), (0, 0, 1)),
    "east": ((1, 1, 1), (1, 1, 0), (1, 0, 1), (1, 0, 0)),
    "up": ((0, 1, 0), (1, 1, 0), (0, 1, 1), (1, 1, 1)),
    "down": ((0, 0, 1), (1, 0, 1), (0, 0, 0), (1, 0, 0)),
}


def as_mesh(element):
    """A cube element in the mesh element's shape, so the one builder below takes both.

    The zombies pulled out of Roblox are meshes; the ones built by the generators in `Assets/models/Enemies/` are
    cubes, each with its own rotation about its own pivot (Blockbench turns X, then Y, then Z). A face whose
    texture is null was culled as hidden (`Assets/models/Enemies/cull_hidden.py`) and is left out, exactly as
    Blockbench's own OBJ and glTF export leave it out. Each face is written as the builder's strip
    (top-left, bottom-left, top-right, bottom-right), which it rings as top-left, bottom-left, bottom-right,
    top-right: counter-clockwise seen from outside, so the normals face out.
    """
    if element.get("type", "cube") != "cube":
        return element
    lo, hi = element["from"], element["to"]
    rx, ry, rz = (math.radians(a) for a in (element.get("rotation") or (0.0, 0.0, 0.0)))
    origin = element.get("origin") or (0.0, 0.0, 0.0)

    def turn(p):
        x, y, z = (p[i] - origin[i] for i in range(3))
        y, z = y * math.cos(rx) - z * math.sin(rx), y * math.sin(rx) + z * math.cos(rx)
        x, z = x * math.cos(ry) + z * math.sin(ry), -x * math.sin(ry) + z * math.cos(ry)
        x, y = x * math.cos(rz) - y * math.sin(rz), x * math.sin(rz) + y * math.cos(rz)
        return [x + origin[0], y + origin[1], z + origin[2]]

    vertices, faces = {}, {}
    for face_name, corners in CUBE_FACE_CORNERS.items():
        face = element["faces"].get(face_name)
        if not face or face.get("texture") is None:
            continue
        u1, v1, u2, v2 = face["uv"]
        uv = ((u1, v1), (u2, v1), (u1, v2), (u2, v2))
        keys = []
        for i, pick in enumerate(corners):
            key = f"{face_name}{i}"
            vertices[key] = turn([(lo, hi)[pick[axis]][axis] for axis in range(3)])
            keys.append(key)
        tl, tr, bl, br = keys
        faces[face_name] = {"vertices": [tl, bl, tr, br], "uv": dict(zip(keys, uv))}
    return {"vertices": vertices, "faces": faces}


def build(model, reset=True):
    """The rig and its one skinned body. `reset` starts from an empty factory scene, which is what a headless run
    wants and what a LIVE session must never do: it wipes the user's open file and unloads every add-on, the MCP
    server with them (Animations.md §7). `to_blend.rebuild_live` passes False."""
    if reset:
        bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = FPS

    order, owns = bone_tree(model)

    armature = bpy.data.armatures.new("Rig")
    rig = bpy.data.objects.new("Rig", armature)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    for name, parent, origin in order:
        eb = armature.edit_bones.new(name)
        eb.head = bb_to_blender(origin)
        # Straight up Blender's +Z. The roll is left at zero deliberately: the FBX exporter re-derives
        # bone axes from `primary_bone_axis` and throws it away, so rolling the bone a half turn to fix
        # the frame does nothing at all. `AXIS_SIGN` is where that is dealt with.
        eb.tail = eb.head + Vector((0.0, 0.0, BONE_LENGTH))
        eb.roll = 0.0
        eb.use_connect = False
        if parent:
            eb.parent = armature.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")

    # One mesh for the whole body: Roblox wants a single MeshPart, and the bones are what split it.
    elements = {e["uuid"]: e for e in model["elements"]}
    verts, faces, uvs, groups = [], [], [], {}
    res = model["resolution"]
    for name, _parent, _origin in order:
        for uuid in owns.get(name, []):
            element = as_mesh(elements[uuid])
            index = {}
            for key, position in element["vertices"].items():
                index[key] = len(verts)
                verts.append(bb_to_blender(position))
            groups.setdefault(name, []).extend(index.values())
            for face in element["faces"].values():
                loop = face["vertices"]
                if len(loop) < 3:
                    continue
                # A .bbmodel quad is a strip (v0 v1 v2 v3), a polygon wants a ring.
                ring = [loop[0], loop[1], loop[3], loop[2]] if len(loop) == 4 else loop
                faces.append([index[k] for k in ring])
                # The .bbmodel UV origin is top left and Blender's is bottom left.
                uvs.append([
                    (face["uv"][k][0] / res["width"], 1.0 - face["uv"][k][1] / res["height"])
                    for k in ring
                ])

    mesh = bpy.data.meshes.new("Body")
    mesh.from_pydata([tuple(v) for v in verts], [], faces)
    mesh.update()
    layer = mesh.uv_layers.new(name="UVMap")
    for poly, corner in zip(mesh.polygons, uvs):
        for slot, uv in zip(poly.loop_indices, corner):
            layer.data[slot].uv = uv

    body = bpy.data.objects.new("Body", mesh)
    bpy.context.collection.objects.link(body)
    for name, indices in groups.items():
        # Rigid: every vertex belongs entirely to the one bone whose group it was written under.
        body.vertex_groups.new(name=name).add(indices, 1.0, "REPLACE")
    body.parent = rig
    body.modifiers.new(name="Armature", type="ARMATURE").object = rig

    material(model, body)
    return rig, body


def material(model, body):
    """The embedded texture, unlit and unfiltered - the same treatment the rig already gets in game."""
    if not model.get("textures"):
        return
    import base64
    import tempfile

    source = model["textures"][0]["source"]
    if not source.startswith("data:"):
        return
    path = os.path.join(tempfile.gettempdir(), model["textures"][0].get("name", "texture.png"))
    with open(path, "wb") as f:
        f.write(base64.b64decode(source.split(",", 1)[1]))

    mat = bpy.data.materials.new("Body")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    image = nodes.new("ShaderNodeTexImage")
    image.image = bpy.data.images.load(path)
    image.interpolation = "Closest"
    principled = nodes["Principled BSDF"]
    links.new(image.outputs["Color"], principled.inputs["Base Color"])
    body.data.materials.append(mat)


def action_fcurves(action, rig):
    """Blender 4.4 moved f-curves off the Action and onto a slot's channel bag; 5.x removed the old
    attribute outright. Reach for whichever this Blender has."""
    if hasattr(action, "fcurves"):
        return action.fcurves
    slot = rig.animation_data.action_slot
    for layer in action.layers:
        for strip in layer.strips:
            bag = strip.channelbag(slot)
            if bag:
                return bag.fcurves
    return []


def action_for(model, rig, anim):
    """One `.bbmodel` clip as a Blender action on the rig."""
    action = bpy.data.actions.new(anim["name"])
    rig.animation_data_create()
    rig.animation_data.action = action
    for bone in rig.pose.bones:
        bone.rotation_mode = "XYZ"
        bone.rotation_euler = (0.0, 0.0, 0.0)
        bone.location = (0.0, 0.0, 0.0)

    for animator in anim["animators"].values():
        bone = rig.pose.bones.get(animator["name"])
        if bone is None:
            continue
        for kf in animator.get("keyframes", []):
            frame = kf["time"] * FPS
            point = kf["data_points"][0]
            values = [float(point["x"]), float(point["y"]), float(point["z"])]
            if kf["channel"] == "rotation":
                bone.rotation_euler = [math.radians(v * s) for v, s in zip(values, AXIS_SIGN)]
                bone.keyframe_insert("rotation_euler", frame=frame, group=bone.name)
            elif kf["channel"] == "position":
                bone.location = [v * SCALE * s for v, s in zip(values, AXIS_SIGN)]
                bone.keyframe_insert("location", frame=frame, group=bone.name)
    for curve in action_fcurves(action, rig):
        for kp in curve.keyframe_points:
            # The clips are baked at 60 fps already; anything but LINEAR would re-interpolate them into
            # something the .bbmodel does not say.
            kp.interpolation = "LINEAR"
    return action


def export(path, start, end):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.fbx(
        filepath=path,
        use_selection=True,
        apply_unit_scale=True,
        # A HUNDREDTH, because Roblox reads the raw FBX numbers and ignores the file's own
        # `UnitScaleFactor`. Blender writes that factor as 100 (centimetres), so a rig built at stud
        # scale arrives in Studio a hundred times too big - the first upload came in at 550 x 723 x 324.
        # `MeshPart.Size` would fix the MESH, and only the mesh: an animation's Pose translations are
        # absolute studs and do not rescale with it, so the lunges would still be a hundred studs.
        global_scale=0.01,
        # Blender is Z-up, FBX is Y-up. The default conversion is what the build above is written for.
        axis_forward="-Z",
        axis_up="Y",
        object_types={"ARMATURE", "MESH"},
        use_mesh_modifiers=False,
        mesh_smooth_type="FACE",
        add_leaf_bones=False,
        primary_bone_axis="Y",
        secondary_bone_axis="X",
        bake_anim=start is not None,
        bake_anim_use_all_bones=True,
        bake_anim_use_nla_strips=False,
        bake_anim_use_all_actions=False,
        bake_anim_force_startend_keying=True,
        bake_anim_step=1.0,
        bake_anim_simplify_factor=0.0,
        path_mode="COPY",
        embed_textures=True,
    )


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    src, out = args[0], args[1]
    os.makedirs(out, exist_ok=True)
    model = read(src)
    name = model.get("name", "Rig")

    rig, _body = build(model)
    if rig.animation_data:
        rig.animation_data.action = None
    export(os.path.join(out, f"{name}.fbx"), None, None)
    print(f"[FBX] mesh -> {name}.fbx")

    for anim in model.get("animations", []):
        rig, _body = build(model)
        action = action_for(model, rig, anim)
        frames = [kp.co[0] for curve in action_fcurves(action, rig) for kp in curve.keyframe_points]
        bpy.context.scene.frame_start = int(min(frames))
        bpy.context.scene.frame_end = int(round(anim["length"] * FPS))
        export(os.path.join(out, f"{name}_{anim['name']}.fbx"),
               bpy.context.scene.frame_start, bpy.context.scene.frame_end)
        print(f"[FBX] {anim['name']} ({anim['length']:.3f}s, "
              f"{bpy.context.scene.frame_start}-{bpy.context.scene.frame_end}) -> {name}_{anim['name']}.fbx")


# Blender runs a `--python` script as __main__; `to_blend.py` imports this file for `build` and must not export.
if __name__ == "__main__":
    main()
