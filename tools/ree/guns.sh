#!/bin/sh
# Every gun (or the ones named) as it is held in first person and from its side with its hand marks, for checking a
# gun's `Hands`, `Barrel` and hold after adding or changing one (Viewmodel.md). From the repo root:
#   tools/ree/guns.sh                      all of src/Global/Data/Guns
#   tools/ree/guns.sh "Starter Rifle" ...  those guns, by Name
# Writes Assets/models/Guns/preview/viewmodel/check/<Name>.png (side view over two first-person frames: looking
# round, and straight ahead with a red cross on the crosshair). A gun's model is found by its data:
# Assets/models/Guns/<Rarity folder>/<ModelName>.rbxm(x). Missing meshes are fetched through Tripwire (gunmeshes.py).
G=Assets/models/Guns; OUT=$G/preview/viewmodel/check; WORK=$(mktemp -d); MESHES=$G/meshes
MOUNTS="--mount ReplicatedStorage/Packages=Packages --mount ReplicatedStorage/Types=src/Global/Types
	--mount ReplicatedStorage/Data=src/Global/Data --mount ReplicatedStorage/GlobalShared=src/Global/Shared
	--mount ReplicatedStorage/Shared=src/Game/Shared --mount ReplicatedStorage/ServerUtils=src/Global/Server/Utils"
mkdir -p "$OUT" "$MESHES"
for data in src/Global/Data/Guns/*.luau; do
	name=$(sed -n 's/^\tName = "\(.*\)",$/\1/p' "$data"); model=$(sed -n 's/^\tModelName = "\(.*\)",$/\1/p' "$data")
	rarity=$(sed -n 's/^\tRarity = "\(.*\)",$/\1/p' "$data"); [ "$rarity" = Starter ] && rarity="starter weapons"
	if [ $# -gt 0 ]; then
		wanted=0; for arg in "$@"; do [ "$arg" = "$name" ] && wanted=1; done; [ $wanted = 1 ] || continue
	fi
	file=$(ls "$G/$rarity/$model".rbxm* 2>/dev/null | head -1)
	[ -n "$file" ] || { echo "$name: no model file $G/$rarity/$model.rbxm(x)"; continue; }
	# shellcheck disable=SC2086
	ids=$(ree run --harness tools/ree/GunSheet.luau --seconds 0.02 --offline \
		--context "{\"Gun\":\"$name\",\"Model\":\"$(realpath "$file")\"}" $MOUNTS 2>&1 \
		| grep -o 'MESHPART [^ ]* rbxassetid://[0-9]*' | sed 's/.*rbxassetid:\/\///')
	# shellcheck disable=SC2086
	python3 tools/ree/gunmeshes.py $ids || echo "$name: some meshes are missing, it will draw without them"
	tools/ree/gunsheet.sh "$name" "$file" "$WORK/side" "$MESHES" > /dev/null || { echo "$name: side view failed"; continue; }
	MESHES=$MESHES TIMES=1.2,2.0 SIZE=960x540 tools/ree/viewmodel.sh "$name" "$file" "$WORK/first" > /dev/null \
		|| { echo "$name: first person failed"; continue; }
	magick "$WORK/first/frames/frames/0001.png" -fill none -stroke red \
		-draw "line 470,270 490,270 line 480,260 480,280" "$WORK/straight.png"
	magick "$WORK/side/sheet.png" -resize 960x540 "$WORK/side.png"
	magick "$WORK/first/frames/frames/0000.png" "$WORK/straight.png" +append "$WORK/row.png"
	magick "$WORK/side.png" -gravity center -background white -extent 1920x540 "$WORK/row.png" -append "$OUT/$name.png"
	rm -rf "$WORK/side" "$WORK/first"
	echo "$OUT/$name.png"
done
rm -rf "$WORK"
