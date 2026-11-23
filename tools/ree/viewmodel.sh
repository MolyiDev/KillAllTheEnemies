#!/bin/sh
# Films the first-person gun offline (tools/ree/Viewmodel.luau). From the repo root:
#   tools/ree/viewmodel.sh "<gun Name>" <model file> <out dir> [seconds] [extra context JSON fields, e.g. '"Only":"Shoot"']
# MESHES=<dir> holds the model's meshes, each a file named by its asset id (Tripwire download_asset): the guns'
# meshes are private, so without it a mesh gun draws only its arms. TIMES=<s,s,...> draws those moments as PNGs
# (<out>/frames) in place of the clip. Writes <out>/video.mp4 and <out>/sheet.png.
GUN="$1"; MODEL="$(realpath "$2")"; OUT="$3"; SECONDS_="${4:-9.8}"; EXTRA="${5:+,$5}"
CONTENT=$(ls -d ~/.var/app/org.vinegarhq.Vinegar/data/vinegar/versions/*/content | head -1)
REC="$OUT/record"
mkdir -p "$REC"
CTX="{\"Gun\":\"$GUN\",\"Model\":\"$MODEL\"$EXTRA}"
MOUNTS="--mount ReplicatedStorage/Packages=Packages --mount ReplicatedStorage/Types=src/Global/Types
	--mount ReplicatedStorage/Data=src/Global/Data --mount ReplicatedStorage/GlobalShared=src/Global/Shared
	--mount ReplicatedStorage/Shared=src/Game/Shared --mount ReplicatedStorage/ServerUtils=src/Global/Server/Utils
	--mount StarterPlayer/StarterPlayerScripts/GlobalClient=src/Global/Client
	--mount StarterPlayer/StarterPlayerScripts/Client=src/Game/Client"
# shellcheck disable=SC2086
ree record --harness tools/ree/Viewmodel.luau --out "$REC" --seconds "$SECONDS_" --viewport 1280x720 --offline \
	--context "$CTX" $MOUNTS > "$OUT/ree.log" 2>&1 || { tail -3 "$OUT/ree.log"; exit 1; }
grep -o '"errors":[1-9][0-9]*' "$OUT/ree.log" && grep -o '"message":"[^"]*"' "$OUT/ree.log" | head -3
SETS=""
if [ -n "$MESHES" ]; then
	# shellcheck disable=SC2086
	SETS=$(ree run --harness tools/ree/Viewmodel.luau --seconds 0.02 --offline --context "$CTX" $MOUNTS 2>&1 \
		| grep -o 'MESHPART [^ ]* rbxassetid://[0-9]*' | awk -v d="$(realpath "$MESHES")" \
		'{sub("rbxassetid://","",$3); printf "--set Viewmodel.Model.%s.MeshId=file://%s/%s --set Viewmodel.Model.%s.TextureID= ", $2, d, $3, $2}')
fi
if [ -n "$TIMES" ]; then WHEN="--times $TIMES --format png --sheet 0"; DEST="$OUT/frames"; else WHEN="--duration $SECONDS_ --sheet ${SHEET:-20}"; DEST="$OUT"; fi
# shellcheck disable=SC2086
ROR_ROBLOX_CONTENT="$CONTENT" ror video "$REC/scene.rbxm" --no-service --offline --playback "$REC/playback.json" \
	--camera-track "$REC/camera.json" $WHEN $SETS --size "${SIZE:-1280x720}" --out "$DEST" > "$OUT/ror.log" 2>&1 || { tail -5 "$OUT/ror.log"; exit 1; }
echo "$DEST"
