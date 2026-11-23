#!/bin/bash
# Every gun (or the ones named) held in third person (tools/ree/bodypose.sh), one row each: the rest pose from the
# front-right, the right and behind on the left. From the repo root:
#   tools/ree/bodyposeall.sh                      all of src/Global/Data/Guns
#   tools/ree/bodyposeall.sh "Starter Rifle" ...  those guns, by Name
# Writes Assets/models/Guns/preview/bodypose/<Name>/views.png and the rows together in .../bodypose/all.png. The
# meshes must already be in Assets/models/Guns/meshes (tools/ree/guns.sh fetches them).
G=Assets/models/Guns; OUT=$G/preview/bodypose
ROWS=()
for data in src/Global/Data/Guns/*.luau; do
	name=$(sed -n 's/^\tName = "\(.*\)",$/\1/p' "$data"); model=$(sed -n 's/^\tModelName = "\(.*\)",$/\1/p' "$data")
	rarity=$(sed -n 's/^\tRarity = "\(.*\)",$/\1/p' "$data"); [ "$rarity" = Starter ] && rarity="starter weapons"
	if [ $# -gt 0 ]; then
		wanted=0; for arg in "$@"; do [ "$arg" = "$name" ] && wanted=1; done; [ $wanted = 1 ] || continue
	fi
	file=$(ls "$G/$rarity/$model".rbxm* 2>/dev/null | head -1)
	[ -n "$file" ] || { echo "$name: no model file $G/$rarity/$model.rbxm(x)"; continue; }
	tools/ree/bodypose.sh "$name" "$file" "$OUT/$name" > /dev/null || { echo "$name: failed"; continue; }
	magick "$OUT/$name/front/frames/0000.png" "$OUT/$name/right/frames/0000.png" "$OUT/$name/behind/frames/0000.png" \
		+append -resize 50% -gravity north -font DejaVu-Sans -fill white -undercolor '#0008' -pointsize 18 -annotate +0+4 "$name" \
		"$OUT/$name/row.png"
	ROWS+=("$OUT/$name/row.png")
	echo "$OUT/$name/views.png"
done
[ ${#ROWS[@]} -gt 0 ] && magick "${ROWS[@]}" -append "$OUT/all.png" && echo "$OUT/all.png"
