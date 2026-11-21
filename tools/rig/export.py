"""A .bbmodel out to Roblox FBXs through to_fbx.py (vendored, unchanged), with the classic head and
the hair smooth-shaded: to_fbx writes every face flat, which is right for the boxes and turns a sixteen-sided head
into visible facets (and the hair's toon ramp needs smooth normals in the engine too).

    blender -b --factory-startup --python tools/rig/export.py -- <model.bbmodel> <outdir>
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import to_fbx  # noqa: E402

_build = to_fbx.build


# NO_TEXTURE=1 exports the meshes bare. Roblox moderated the account over the first upload's texture (its blood), and
# to_fbx embeds the texture in the rig AND in every clip, so the clips carried it too; the texture goes up on its own.
NO_TEXTURE = os.environ.get("NO_TEXTURE") == "1"


def build(model, reset=True):
    rig, body = _build(model, reset)
    if NO_TEXTURE:
        body.data.materials.clear()
    smooth = {body.vertex_groups[n].index for n in ("Head", "Hair") if n in body.vertex_groups}
    in_smooth = {v.index for v in body.data.vertices if any(g.group in smooth for g in v.groups)}
    for poly in body.data.polygons:
        poly.use_smooth = all(i in in_smooth for i in poly.vertices)
    return rig, body


# to_fbx.main looks `build` up in its own module, so this is the one it runs.
to_fbx.build = build
to_fbx.main()
