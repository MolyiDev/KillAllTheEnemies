#!/bin/bash
# Two passes in opposite order so drift (thermal, Studio state) can't favour one arm.
set -u
cd "$(dirname "$0")"
ARMS=("base:" "A:A" "E:E" "F:F" "all:A,B,C,D,E,F")
run() { local name=${1%%:*} flags=${1#*:}; echo "=== $name-$2 ($flags) $(date +%T)"; timeout 590 python3 run2.py "s2$name-$2" "$flags" 8000 2>&1 | grep -v "^\[BALLARC_BENCH" ; }
for a in "${ARMS[@]}"; do run "$a" 1; done
for (( i=${#ARMS[@]}-1; i>=0; i-- )); do run "${ARMS[$i]}" 2; done
echo "=== finished $(date +%T)"
