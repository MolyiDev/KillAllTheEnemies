#!/bin/sh
# One gun's side view with its measuring grid and hand marks (tools/ree/GunSheet.luau). From the repo root:
#   tools/ree/gunsheet.sh "<gun Name>" <model file> <out dir> [meshes dir, Assets/models/Guns/meshes]
# <meshes dir> holds the model's meshes, each a file named by its asset id (Tripwire download_asset): the guns'
# meshes are private, so the renderer cannot fetch them. Writes <out>/sheet.png.
GUN="$1"; MODEL="$(realpath "$2")"; OUT="$3"; MESHES="$(realpath "${4:-Assets/models/Guns/meshes}")"
CONTENT=$(ls -d ~/.var/app/org.vinegarhq.Vinegar/data/vinegar/versions/*/content | head -1)
REC="$OUT/record"
mkdir -p "$REC"
MOUNTS="--mount ReplicatedStorage/Packages=Packages --mount ReplicatedStorage/Types=src/Global/Types
	--mount ReplicatedStorage/Data=src/Global/Data --mount ReplicatedStorage/GlobalShared=src/Global/Shared
	--mount ReplicatedStorage/Shared=src/Game/Shared --mount ReplicatedStorage/ServerUtils=src/Global/Server/Utils"
CTX="{\"Gun\":\"$GUN\",\"Model\":\"$MODEL\"}"
# shellcheck disable=SC2086
ree record --harness tools/ree/GunSheet.luau --out "$REC" --seconds 0.1 --viewport 1280x720 --offline --context "$CTX" $MOUNTS > "$OUT/ree.log" 2>&1 || { tail -3 "$OUT/ree.log"; exit 1; }
# shellcheck disable=SC2086
SETS=$(ree run --harness tools/ree/GunSheet.luau --seconds 0.02 --offline --context "$CTX" $MOUNTS 2>&1 \
	| grep -o 'MESHPART [^ ]* rbxassetid://[0-9]*' | awk -v d="$MESHES" '{sub("rbxassetid://","",$3); printf "--set Sheet.%s.MeshId=file://%s/%s --set Sheet.%s.TextureID= ", $2, d, $3, $2}')
# shellcheck disable=SC2086
ROR_ROBLOX_CONTENT="$CONTENT" ror video "$REC/scene.rbxm" --no-service --offline --playback "$REC/playback.json" \
	--camera-track "$REC/camera.json" --times 0.05 --format png --size 1280x720 --sheet 0 $SETS \
	--out "$OUT/frames" > "$OUT/ror.log" 2>&1 || { tail -5 "$OUT/ror.log"; exit 1; }
cp "$OUT/frames/frames/0000.png" "$OUT/sheet.png"
echo "$OUT/sheet.png"
