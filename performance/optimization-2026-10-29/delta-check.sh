#!/bin/bash
# Lune round trip of the final EnemyPacker (needs a Vector3 shim, so it runs on a temp copy).
set -e
here="$(cd "$(dirname "$0")" && pwd)"; tmp="$(mktemp -d)"
{ echo 'local Vector3 = require("@lune/roblox").Vector3'; grep -v '^--!' "$here/../../src/Survivors/Shared/Packers/EnemyPacker.luau"; } > "$tmp/EnemyPacker.luau"
cp "$here/delta-check.luau" "$tmp/"
lune run "$tmp/delta-check.luau"
