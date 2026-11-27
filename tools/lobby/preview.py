"""Seeing the Lobby place offline, with Studio off screen (Maps.md section 8), from the repo's root:
    python3 tools/lobby/preview.py dump lobby.json                 a Lobby playtest must be running (start_playtest)
    python3 tools/lobby/preview.py render lobby.json out/          the place as dumped, from the cameras below
    python3 tools/lobby/preview.py render lobby.json out/ --range range.json --cameras '[{...}]' --size 1280x720
`--range` swaps Range.Hall and Range.Door for tools/lobby/range.py's output, so a change is seen before it is
pushed. Meshes and textures are fetched once through the Tripwire daemon (127.0.0.1:44331) into
research/LobbyAssets: ror cannot download a private asset itself. SurfaceGui text is not drawn."""
import glob
import json
import os
import re
import subprocess
import sys
import urllib.request

URL = "http://127.0.0.1:44331/mcp"
LOBBY_PLACE_ID = 105859632802526
ASSETS = os.path.abspath("research/LobbyAssets")
SLICE = 150000
CONTENT_KEYS = (
    "MeshId", "TextureID", "Texture", "TextureId", "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt",
    "SkyboxUp", "SunTextureId", "MoonTextureId",
)
# The plaza toward the range's front, then through the door, the booths, the lanes and back.
CAMERAS = [
    {"mode": "lookAt", "eye": [-70, 14, 14], "target": [-7, 16, 14], "fov": 70},
    {"mode": "lookAt", "eye": [-38, 7, -8], "target": [-7, 13, 14], "fov": 70},
    {"mode": "lookAt", "eye": [-2, 6.5, 14], "target": [100, 6, 1], "fov": 70},
    {"mode": "lookAt", "eye": [46, 6, 1], "target": [150, 5, 1], "fov": 70},
    {"mode": "lookAt", "eye": [150, 8, 20], "target": [40, 6, 0], "fov": 70},
    {"mode": "lookAt", "eye": [36, 7, -6], "target": [-7, 7, 14], "fov": 70},
    {"mode": "lookAt", "eye": [62, 6, 12], "target": [110, 8, -44], "fov": 70},
    {"mode": "lookAt", "eye": [41, 9, -21.5], "target": [120, 3, -21.5], "fov": 70},
]

session = None
calls = 0


def rpc(method, params=None, call_id=None):
    global session
    body = {"jsonrpc": "2.0", "method": method}
    if params is not None:
        body["params"] = params
    if call_id is not None:
        body["id"] = call_id
    headers = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}
    if session:
        headers["Mcp-Session-Id"] = session
    reply = urllib.request.urlopen(urllib.request.Request(URL, json.dumps(body).encode(), headers), timeout=300)
    session = reply.headers.get("Mcp-Session-Id") or session
    text = reply.read().decode()
    if "data:" in text[:40] or text.startswith("event"):
        text = "\n".join(line[5:] for line in text.splitlines() if line.startswith("data:"))
    return json.loads(text) if text.strip() else None


def call(tool, arguments):
    global calls
    if not session:
        rpc("initialize", {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "lobby_preview", "version": "1"}}, 1)
        rpc("notifications/initialized")
    calls += 1
    reply = rpc("tools/call", {"name": tool, "arguments": arguments}, 10 + calls)
    if reply.get("error"):
        raise SystemExit(f"{tool}: {reply['error']}")
    text = "".join(piece.get("text", "") for piece in reply["result"].get("content", []))
    if reply["result"].get("isError"):
        raise SystemExit(f"{tool}: {text[:1500]}")
    return text


def dump(out):
    studios = [studio for studio in json.loads(call("list_studios", {})) if studio["placeId"] == LOBBY_PLACE_ID and studio["connected"]]
    if len(studios) != 1:
        raise SystemExit(f"need exactly one connected Lobby Studio, found {len(studios)}")
    call("set_active_studio", {"studio": studios[0]["instanceId"]})
    total = json.loads(call("run_luau_live", {"code": open("tools/lobby/dump.luau").read()}))["result"]
    pieces = []
    for start in range(1, total + 1, SLICE):
        pieces.append(json.loads(call("run_luau_live", {"code": f"return string.sub(_G.dump, {start}, {start + SLICE - 1})"}))["result"])
    text = "".join(pieces)
    if json.loads(text)["place"] != LOBBY_PLACE_ID:
        raise SystemExit("the playtest that answered is not the Lobby's")
    open(out, "w").write(text)
    print(f"{len(text)} bytes -> {out}")


# The dump with Range.Hall and Range.Door replaced by the generator's.
def with_range(entries, generated):
    def path(index):
        names = []
        while index:
            names.append(entries[index - 1]["n"])
            index = entries[index - 1]["p"]
        return ".".join(reversed(names))

    holder = next(i + 1 for i in range(len(entries)) if path(i + 1) == "Lobby.Map.Range")
    dropped = set()
    for i, entry in enumerate(entries):
        if (entry["p"] == holder and entry["n"] in ("Hall", "Door")) or entry["p"] in dropped:
            dropped.add(i + 1)
    kept, moved = [], {}
    for i, entry in enumerate(entries):
        if i + 1 not in dropped:
            kept.append(entry)
            moved[i + 1] = len(kept)
    for entry in kept:
        entry["p"] = moved.get(entry["p"], 0)
    base = len(kept)
    for entry in generated:
        kept.append({**entry, "p": moved[holder] if entry["p"] == 0 else base + entry["p"]})
    return kept


def fetch(entries):
    os.makedirs(ASSETS, exist_ok=True)
    wanted = set()
    for entry in entries:
        for key in CONTENT_KEYS:
            found = re.search(r"(\d{5,})", str(entry.get(key) or ""))
            if found and not os.path.exists(f"{ASSETS}/{found.group(1)}"):
                wanted.add(found.group(1))
    for asset in sorted(wanted):
        call("download_asset", {"assetId": asset, "outPath": f"{ASSETS}/{asset}"})
    if wanted:
        print(f"fetched {len(wanted)} assets")


def render(source, out, options):
    data = json.load(open(source))
    if "--range" in options:
        data["list"] = with_range(data["list"], json.load(open(options["--range"])))
    fetch(data["list"])
    os.makedirs(out, exist_ok=True)
    merged, place = f"{out}/place.json", f"{out}/place.rbxl"
    json.dump(data, open(merged, "w"))
    subprocess.run(["lune", "run", "tools/lobby/place.luau", merged, place, ASSETS], check=True)
    os.remove(merged)

    content = sorted(glob.glob(os.path.expanduser("~/.var/app/org.vinegarhq.Vinegar/data/vinegar/versions/*/content")))
    environment = dict(os.environ, **({"ROR_ROBLOX_CONTENT": content[-1]} if content else {}))
    cameras = options.get("--cameras", json.dumps(CAMERAS))
    command = ["ror", "render", place, "--size", options.get("--size", "1280x720"), "--out", out, "--json", "--camera", cameras]
    result = json.loads(subprocess.run(command, check=True, capture_output=True, text=True, env=environment).stdout.strip().splitlines()[-1])
    os.remove(place)
    missing = result["stats"].get("missing", [])
    print(f"{result['stats']['parts']} parts, {len(missing)} assets missing, {len(result['views'])} views in {out}")
    for line in missing[:5]:
        print("missing:", line)


def main():
    command, arguments = sys.argv[1], sys.argv[2:]
    options = {arguments[i]: arguments[i + 1] for i in range(len(arguments) - 1) if arguments[i].startswith("--")}
    if command == "dump":
        dump(arguments[0])
    elif command == "render":
        render(arguments[0], arguments[1], options)
    else:
        raise SystemExit(__doc__)


main()
