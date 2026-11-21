#!/bin/bash
# Fix 1 (bounded Bee separation) and fix 2 (batched charm contact damage), both orders.
set -u
cd "$(dirname "$0")"
ARMS=("f0:" "f1:fix1" "f2:fix2" "f12:fix1,fix2")
run() { local name=${1%%:*} flags=${1#*:}; echo "=== $name-$2 ($flags) $(date +%T)"; timeout 590 python3 run3.py "s3$name-$2" "$flags" 8000 2>&1 | grep -v "^\[BALLARC_BENCH" ; }
for a in "${ARMS[@]}"; do run "$a" 1; done
for (( i=${#ARMS[@]}-1; i>=0; i-- )); do run "${ARMS[$i]}" 2; done
python3 harness.py variant fix1,fix2
echo "=== finished $(date +%T)"
