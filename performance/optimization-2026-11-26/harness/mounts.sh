# Sourced by the server harnesses: `. mounts.sh` then `ree run ... "${MOUNTS[@]}"`. The Game place's trees mounted as
# game.project.json maps them (ree 0.7.0 does not read a Rojo project file). The place's own instances are made empty:
# add `--instance ReplicatedStorage/Models=Folder --instance ReplicatedStorage/Models/Enemies=Folder`.
R=${REPO:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}
MOUNTS=(--mount "ReplicatedStorage/Packages=$R/Packages" --mount "ReplicatedStorage/GlobalShared=$R/src/Global/Shared" --mount "ReplicatedStorage/Shared=$R/src/Game/Shared" --mount "ReplicatedStorage/Types=$R/src/Global/Types" --mount "ReplicatedStorage/Data=$R/src/Global/Data" --mount "ServerScriptService/Server=$R/src/Game/Server" --mount "ServerScriptService/GlobalServer=$R/src/Global/Server" --mount "ReplicatedFirst/GlobalFirstShared=$R/src/Global/FirstShared" --mount "ReplicatedFirst/FirstShared=$R/src/Game/FirstShared")
