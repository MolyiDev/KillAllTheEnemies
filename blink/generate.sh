#!/usr/bin/env sh
# Regenerate both Blink networks. Run from anywhere.
#
# Two independent networks, each with its own remote pair and its own 256-event id space:
#   - .blink      "BLINK"       hot gameplay events
#   - Meta.blink  "Meta_BLINK"  cold menu / profile / lobby / config domains
# The blink CLI compiles one config at a time, so both are generated here.
#
# Blink comments are Lua-style (--), not C-style (//); a // comment crashes the compiler's error formatter with a
# confusing math.clamp error.
set -e
cd "$(dirname "$0")/.."
blink blink/.blink
blink blink/Meta.blink
python3 blink/postprocess.py
for file in Network NetworkMeta; do
	highest=$(grep -o 'Index == [0-9]*' "src/Global/Client/$file.luau" | awk '{print $3}' | sort -n | tail -1)
	echo "Blink: $file generated. Highest reliable event index: ${highest:-0} (must stay <= 255)."
done
