#!/bin/bash
# A client-utils harness (tracers_real, blend) against the working tree or, with a third argument, against an older copy
# of the module it stands in (the harness passes it to Context.StandIn):
#   git show HEAD:src/Global/Client/Utils/tracers.luau > /tmp/before.luau
#   bash runfx.sh tracers_real.luau before /tmp/before.luau;  bash runfx.sh tracers_real.luau after ""
H=$1; L=$2; B=$3; shift 3
REPO=${REPO:-$(git -C "$(dirname "$0")" rev-parse --show-toplevel)}
if [ -n "$B" ]; then CTX="{\"Label\":\"$L\",\"Before\":$(python3 -c "import json,sys;print(json.dumps(open(sys.argv[1]).read()))" $B)}"; else CTX="{\"Label\":\"$L\"}"; fi
timeout 600 ree run --harness "$H" --seconds ${SECS:-8} --offline --mount "ReplicatedStorage/Fx/GlobalClient/Utils=$REPO/src/Global/Client/Utils" --mount "ReplicatedStorage/Fx/Client/Utils=$REPO/src/Game/Client/Utils" --mount "ReplicatedStorage/GlobalShared=$REPO/src/Global/Shared" --mount "ReplicatedStorage/Shared=$REPO/src/Game/Shared" --mount "ReplicatedStorage/Packages=$REPO/Packages" --mount "ReplicatedStorage/Types=$REPO/src/Global/Types" --mount "ReplicatedStorage/Data=$REPO/src/Global/Data" --instance ReplicatedStorage/Sounds=Folder --instance ReplicatedStorage/Models=Folder --instance ReplicatedStorage/Models/Enemies=Folder --instance ReplicatedStorage/Effects=Folder --context "$CTX" "$@" 2>&1 | tail -1 | python3 -c "import json,sys; d=json.load(sys.stdin); [print(o['message'][:300]) for o in d['output'] if 'jabby' not in o['message']]; print(d.get('status'), d.get('failure',''))"
