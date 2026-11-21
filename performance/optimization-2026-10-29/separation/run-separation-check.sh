#!/bin/bash
set -e
here="$(cd "$(dirname "$0")" && pwd)"; tmp="$(mktemp -d)"
grep -v -e '^local ReplicatedStorage = game:GetService' -e '^local jecs = require(ReplicatedStorage.Packages.jecs)' "$here/../../../src/Global/Shared/Utils/SpatialHash.luau" > "$tmp/SpatialHash.luau"
cp "$here/separation-check.luau" "$tmp/"
lune run "$tmp/separation-check.luau"
