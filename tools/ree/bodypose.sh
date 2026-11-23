#!/bin/bash
# Films the third-person hold offline (tools/ree/BodyPose.luau). From the repo root:
#   tools/ree/bodypose.sh "<gun Name>" <model file> <out dir>
# Writes <out>/views.png (the rest pose from the front-right, the right, the game's shoulder camera and behind on the
# left, then mid-aim and mid-burst) and, with VIDEO=1, <out>/video.mp4 from the front-right. MESHES=<dir> holds the model's
# meshes, each a file named by its asset id (default Assets/models/Guns/meshes).
GUN="$1"; MODEL="$(realpath "$2")"; OUT="$3"; MESHES="$(realpath "${MESHES:-Assets/models/Guns/meshes}")"
CONTENT=$(ls -d ~/.var/app/org.vinegarhq.Vinegar/data/vinegar/versions/*/content | head -1)
REC="$OUT/record"
mkdir -p "$REC"
CTX="{\"Gun\":\"$GUN\",\"Model\":\"$MODEL\"}"
MOUNTS=(--mount ReplicatedStorage/Packages=Packages --mount ReplicatedStorage/Types=src/Global/Types
	--mount ReplicatedStorage/Data=src/Global/Data --mount ReplicatedStorage/GlobalShared=src/Global/Shared
	--mount ReplicatedStorage/Shared=src/Game/Shared --mount ReplicatedStorage/ServerUtils=src/Global/Server/Utils
	--mount StarterPlayer/StarterPlayerScripts/GlobalClient=src/Global/Client)
ree record --harness tools/ree/BodyPose.luau --out "$REC" --seconds 5.2 --viewport 1280x720 --offline \
	--context "$CTX" "${MOUNTS[@]}" > "$OUT/ree.log" 2>&1 || { tail -5 "$OUT/ree.log"; exit 1; }
grep -o '"errors":[1-9][0-9]*' "$OUT/ree.log" && grep -o '"message":"[^"]*"' "$OUT/ree.log" | head -3
SETS=()
while read -r part id; do
	path="Character[\"$GUN\"].Model.$part"
	SETS+=(--set "$path.MeshId=file://$MESHES/$id" --set "$path.TextureID=")
done < <(ree run --harness tools/ree/BodyPose.luau --seconds 0.02 --offline --context "$CTX" "${MOUNTS[@]}" 2>&1 \
	| grep -o 'MESHPART [^ ]* rbxassetid://[0-9]*' | sed 's/^MESHPART \([^ ]*\) rbxassetid:\/\/\([0-9]*\)$/\1 \2/')

# name, time, eye, target, fov (back: the game's shoulder camera)
VIEWS="front 1.4 [6.5,5.2,-6.5] [0,3.7,-0.8] 40
right 1.4 [9,4.2,-1.2] [0,3.6,-1.2] 40
back 1.4 [3,5,10] [3,4.6,-20] 70
behind 1.4 [-7,5.6,3.5] [0.6,3.8,-1.2] 40
aimup 2.0 [6.5,5.2,-6.5] [0,3.9,-0.8] 40
burst 4.1 [6.5,5.2,-6.5] [0,3.7,-0.8] 40"
FRAMES=()
while read -r name at eye target fov; do
	ROR_ROBLOX_CONTENT="$CONTENT" ror video "$REC/scene.rbxm" --no-service --offline --playback "$REC/playback.json" \
		--camera "{\"mode\":\"lookAt\",\"eye\":$eye,\"target\":$target,\"fov\":$fov}" --times "$at" --format png \
		--sheet 0 "${SETS[@]}" --size 640x640 --out "$OUT/$name" > "$OUT/ror.log" 2>&1 \
		|| { tail -5 "$OUT/ror.log"; exit 1; }
	FRAMES+=("$OUT/$name/frames/0000.png")
done <<< "$VIEWS"
magick "${FRAMES[@]:0:3}" +append "$OUT/row1.png"
magick "${FRAMES[@]:3:3}" +append "$OUT/row2.png"
magick "$OUT/row1.png" "$OUT/row2.png" -append "$OUT/views.png"
rm -f "$OUT/row1.png" "$OUT/row2.png"
if [ -n "$VIDEO" ]; then
	ROR_ROBLOX_CONTENT="$CONTENT" ror video "$REC/scene.rbxm" --no-service --offline --playback "$REC/playback.json" \
		--camera '{"mode":"lookAt","eye":[6.5,5.2,-6.5],"target":[0,3.7,-0.8],"fov":40}' --duration 5.2 --sheet 16 \
		"${SETS[@]}" --size 960x720 --out "$OUT/video" > "$OUT/ror.log" 2>&1 || { tail -5 "$OUT/ror.log"; exit 1; }
fi
echo "$OUT/views.png"
