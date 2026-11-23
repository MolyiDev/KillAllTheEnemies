#!/bin/sh
# Checks every gun's fit on the back offline (tools/ree/BackGunAll.luau). From the repo root:
#   tools/ree/backgunall.sh <out dir>
# Draws each gun from behind, side on and from above as <out>/frames/*.png and tiles them into <out>/sheet.png. The guns'
# meshes are private: they are read from Assets/models/Guns/meshes, each a file named by its asset id.
OUT="$1"
CONTENT=$(ls -d ~/.var/app/org.vinegarhq.Vinegar/data/vinegar/versions/*/content | head -1)
REC="$OUT/record"
mkdir -p "$REC"
FILES=$(find "$(pwd)/Assets/models/Guns" -path '*/preview' -prune -o -path '*/meshes' -prune -o -type f \( -name '*.rbxm' -o -name '*.rbxmx' \) -print \
	| awk '{n=$0; sub(".*/","",n); sub("\\.rbxmx?$","",n); printf "%s\"%s\":\"%s\"", (c++ ? "," : ""), n, $0}')
CTX="{\"Files\":{$FILES}}"
COUNT=$(grep -l "Tier = " src/Global/Data/Guns/*.luau | wc -l)
MOUNTS="--mount ReplicatedStorage/Packages=Packages --mount ReplicatedStorage/Types=src/Global/Types
	--mount ReplicatedStorage/Data=src/Global/Data --mount ReplicatedStorage/GlobalShared=src/Global/Shared
	--mount StarterPlayer/StarterPlayerScripts/GlobalClient=src/Global/Client
	--mount StarterPlayer/StarterPlayerScripts/Client=src/Lobby/Client"
# shellcheck disable=SC2086
ree record --harness tools/ree/BackGunAll.luau --out "$REC" --seconds "$COUNT" --viewport 640x480 --offline \
	--context "$CTX" $MOUNTS > "$OUT/ree.log" 2>&1 || { tail -3 "$OUT/ree.log"; exit 1; }
grep -o '"failure":"[^"]*"' "$OUT/ree.log"
# A record keeps no prints: a moment's run gives them.
# shellcheck disable=SC2086
ree run --harness tools/ree/BackGunAll.luau --seconds 0.02 --offline --context "$CTX" $MOUNTS > "$OUT/prints.log" 2>&1
MESH_DIR="$(pwd)/Assets/models/Guns/meshes"
SETS=$(grep -o 'MESHPART [^ ]* rbxassetid://[0-9]*' "$OUT/prints.log" | awk -v d="$MESH_DIR" \
	'{sub("rbxassetid://","",$3); printf "--set %s.MeshId=file://%s/%s --set %s.TextureID= ", $2, d, $3, $2}')
TIMES=$(awk -v n="$COUNT" 'BEGIN{for(i=0;i<n;i++) printf "%s%.2f,%.2f,%.2f", (i ? "," : ""), i + 0.17, i + 0.5, i + 0.83}')
# shellcheck disable=SC2086
ROR_ROBLOX_CONTENT="$CONTENT" ror video "$REC/scene.rbxm" --no-service --offline --playback "$REC/playback.json" \
	--camera-track "$REC/camera.json" --times "$TIMES" --format png --sheet 0 $SETS --size 480x360 \
	--out "$OUT/frames" > "$OUT/ror.log" 2>&1 || { tail -5 "$OUT/ror.log"; exit 1; }
grep -o 'GUN [0-9]* [^"\\]*' "$OUT/prints.log" > "$OUT/guns.txt"
python3 - "$OUT" <<'PY'
import os, sys
from PIL import Image, ImageDraw
out = sys.argv[1]
names = [line.split(" ", 2)[2].strip() for line in open(os.path.join(out, "guns.txt")) if line.strip()]
frames = sorted(f for f in os.listdir(os.path.join(out, "frames", "frames")) if f.endswith(".png"))
ims = [Image.open(os.path.join(out, "frames", "frames", f)) for f in frames]
w, h = ims[0].size
cols = 6
rows = (len(ims) + cols - 1) // cols
sheet = Image.new("RGB", (w * cols, h * rows))
draw = ImageDraw.Draw(sheet)
for i, im in enumerate(ims):
    x, y = (i % cols) * w, (i // cols) * h
    sheet.paste(im, (x, y))
    name = names[i // 3] if i // 3 < len(names) else "?"
    draw.text((x + 6, y + 4), f"{name} {('back', 'side', 'top')[i % 3]}", fill=(255, 255, 255))
sheet.save(os.path.join(out, "sheet.png"))
PY
echo "$OUT/sheet.png"
