#!/bin/sh
# Measures how every gun lies on the back and writes src/Lobby/Client/Utils/backGunFits.luau. From the repo root:
#   tools/ree/backgunfits.sh [work dir]
# Each pass builds the guns as backGunModel does with the fits as they stand (tools/ree/BackGunFits.luau), photographs
# them with near-parallel cameras as part ids (ror --ids), and corrects the fits (backgunfits.py), until a pass finds
# nothing left to turn. The guns' meshes are private: they are read from Assets/models/Guns/meshes. Start from an empty
# backGunFits.luau to measure from scratch.
WORK="${1:-/tmp/backgunfits}"
CONTENT=$(ls -d ~/.var/app/org.vinegarhq.Vinegar/data/vinegar/versions/*/content | head -1)
# Far and narrow, so a stud is the same number of pixels at every depth of the gun.
FOV=1.5
DISTANCE=400
SIZE=1024
SPACING=20
BASE=100
FILES=$(find "$(pwd)/Assets/models/Guns" -path '*/preview' -prune -o -path '*/meshes' -prune -o -type f \( -name '*.rbxm' -o -name '*.rbxmx' \) -print \
	| awk '{n=$0; sub(".*/","",n); sub("\\.rbxmx?$","",n); printf "%s\"%s\":\"%s\"", (c++ ? "," : ""), n, $0}')
CTX="{\"Files\":{$FILES}}"
MOUNTS="--mount ReplicatedStorage/Packages=Packages --mount ReplicatedStorage/Types=src/Global/Types
	--mount ReplicatedStorage/Data=src/Global/Data --mount ReplicatedStorage/GlobalShared=src/Global/Shared
	--mount StarterPlayer/StarterPlayerScripts/GlobalClient=src/Global/Client
	--mount StarterPlayer/StarterPlayerScripts/Client=src/Lobby/Client"
MESH_DIR="$(pwd)/Assets/models/Guns/meshes"
for PASS in 1 2 3 4 5 6; do
	OUT="$WORK/pass$PASS"
	rm -rf "$OUT"
	mkdir -p "$OUT/record"
	# shellcheck disable=SC2086
	ree run --harness tools/ree/BackGunFits.luau --seconds 0.02 --offline --context "$CTX" $MOUNTS > "$OUT/prints.log" 2>&1
	grep -o '"failure":"[^"]*"' "$OUT/prints.log" && exit 1
	# shellcheck disable=SC2086
	ree record --harness tools/ree/BackGunFits.luau --out "$OUT/record" --seconds 0.05 --offline --context "$CTX" $MOUNTS \
		> "$OUT/ree.log" 2>&1 || { tail -3 "$OUT/ree.log"; exit 1; }
	COUNT=$(grep -o 'AXES [0-9]*' "$OUT/prints.log" | wc -l)
	CAMERAS=$(awk -v n="$COUNT" -v s="$SPACING" -v b="$BASE" -v d="$DISTANCE" -v f="$FOV" 'BEGIN{
		printf "[";
		for (i = 1; i <= n; i++) for (k = 1; k <= 3; k++) {
			x = (i - 1) * s; y = b + (k - 1) * s;
			printf "%s{\"mode\":\"lookAt\",\"eye\":[%s,%s,%s],\"target\":[%s,%s,0],\"fov\":%s}", (i + k > 2 ? "," : ""), x, y, d, x, y, f
		}
		printf "]"}')
	SETS=$(grep -o 'MESHPART [^ ]* rbxassetid://[0-9]*' "$OUT/prints.log" | awk -v d="$MESH_DIR" \
		'{sub("rbxassetid://","",$3); printf "--set %s.MeshId=file://%s/%s --set %s.TextureID= ", $2, d, $3, $2}')
	# shellcheck disable=SC2086
	ROR_ROBLOX_CONTENT="$CONTENT" ror render "$OUT/record/scene.rbxm" --no-service --offline \
		--playback "$OUT/record/playback.json" --camera "$CAMERAS" --ids --background transparent \
		--size "${SIZE}x$SIZE" $SETS --out "$OUT/render" > "$OUT/ror.log" 2>&1 || { tail -5 "$OUT/ror.log"; exit 1; }
	python3 tools/ree/backgunfits.py "$OUT/prints.log" "$OUT/render" "$FOV" "$DISTANCE" "$SIZE"
	STATUS=$?
	[ "$STATUS" = 0 ] && { echo "converged on pass $PASS"; exit 0; }
	[ "$STATUS" = 3 ] || exit 1
done
echo "not converged after 6 passes: see the last pass's numbers" >&2
exit 1
