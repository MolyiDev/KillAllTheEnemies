#!/usr/bin/env bash
# The R6 zombie rigs, end to end, into Assets/models/Enemies (gitignored):
#   source/Hair.obj                    the hair mesh (a Studio OBJ export), fitted by hair_import.py
#   refs/concept/                      the concept art concept.py paints ZombieNormal from
#   <Name>.bbmodel, <Name>_diff.png    r6_zombie.py (open the .bbmodel in Blockbench)
#   check_pose.py                      proof the clips' rotation signs hold; must print "0 failed"
#   fbx/<Name>.fbx, fbx/ZombieNormal_<Clip>.fbx   export.py, to upload (Models.md section 8)
#   refs/<Name>_views.png, refs/<Name>_close.png  render.py, to look at before uploading
#   tools/rig/build.sh [path/to/R6.obj] [path/to/head.mesh]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
out="$(cd "$here/../.." && pwd)/Assets/models/Enemies"
mkdir -p "$out/fbx" "$out/refs"
# The hair each concept look wears, fitted and decimated from its source mesh (hair_import.py).
if [[ -f "$out/source/Hair.obj" ]]; then
	blender -b --factory-startup --python "$here/hair_import.py" -- "$out/source/Hair.obj" "$out/ZombieNormal_hair.json" 500 2>&1 | grep '\[HAIR\]'
fi
python3 "$here/r6_zombie.py" "${1:-$HOME/Downloads/R6.obj}" "${2:-}" "$out"
blender -b --factory-startup --python "$here/check_pose.py" -- "$out/ZombieNormal.bbmodel" 2>&1 | grep '\[POSE\]' | tee /dev/stderr | grep -q '\[POSE\] 0 failed'
for model in "$out"/*.bbmodel; do
	name="$(basename "$model" .bbmodel)"
	blender -b --factory-startup --python "$here/export.py" -- "$model" "$out/fbx" 2>&1 | grep '\[FBX\]'
	blender -b --factory-startup --python "$here/render.py" -- "$model" "$out/refs/$name" Walk 0.2 2>&1 | grep '\[RENDER\]'
done
