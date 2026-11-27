"""Puts the generated shooting range (tools/lobby/range.py's JSON) into the Lobby place open in Studio, through the
Tripwire daemon on this machine (127.0.0.1:44331):
    python3 tools/lobby/range.py /tmp/range.json && python3 tools/lobby/range_push.py /tmp/range.json
The new Hall and Door are built beside the old ones under Workspace.Lobby.Map.Range, and only when every instance
was made are the old ones deleted and the new ones given their names. Range.Targets is never touched. Run it with
no playtest going (an edit made during one is lost), then save the place."""
import json
import sys
import urllib.request

URL = "http://127.0.0.1:44331/mcp"
LOBBY_PLACE_ID = 105859632802526
RANGE = "Workspace.Lobby.Map.Range"
BATCH = 120
ENUMS = {
    "Material": "Material", "Shape": "PartType", "Face": "NormalId", "MeshType": "MeshType", "Font": "Font",
    "SizingMode": "SurfaceGuiSizingMode",
}
COLORS = ("Color", "TextColor3")
SKIP = ("n", "c", "p")

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
    calls += 1
    reply = rpc("tools/call", {"name": tool, "arguments": arguments}, 10 + calls)
    if reply.get("error"):
        raise SystemExit(f"{tool}: {reply['error']}")
    text = "".join(piece.get("text", "") for piece in reply["result"].get("content", []))
    if reply["result"].get("isError"):
        raise SystemExit(f"{tool}: {text[:1500]}")
    return text


def typed(key, value):
    if key == "cf":
        return "CFrame", {"type": "CFrame", "value": value}
    if key == "s":
        return "Size", {"type": "Vector3", "value": value}
    if key in COLORS:
        return key, {"type": "Color3", "value": value}
    if key in ENUMS:
        return key, {"type": "EnumItem", "enum": ENUMS[key], "item": value}
    if isinstance(value, list):
        return key, {"type": "UDim2" if len(value) == 4 else "Vector3", "value": value}
    return key, {"type": "primitive", "value": value}


def main():
    entries = json.load(open(sys.argv[1]))
    rpc("initialize", {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "range_push", "version": "1"}}, 1)
    rpc("notifications/initialized")

    studios = json.loads(call("list_studios", {}))
    lobby = [studio for studio in studios if studio["placeId"] == LOBBY_PLACE_ID and studio["connected"]]
    if len(lobby) != 1:
        raise SystemExit(f"need exactly one connected Lobby Studio, found {len(lobby)}")
    if lobby[0]["playtestActive"]:
        raise SystemExit("a playtest is running: stop it first")
    call("set_active_studio", {"studio": lobby[0]["instanceId"]})
    present = {child["name"] for child in json.loads(call("get_instance_children", {"path": RANGE}))["children"]}
    if "Targets" not in present:
        raise SystemExit(f"{RANGE} has no Targets: wrong place?")
    for stale in ("Hall_new", "Door_new"):
        if stale in present:
            call("delete_instance", {"path": f"{RANGE}.{stale}"})

    paths = []
    items = []
    for entry in entries:
        name = entry["n"] + ("_new" if entry["p"] == 0 else "")
        parent = RANGE if entry["p"] == 0 else paths[entry["p"] - 1]
        paths.append(f"{parent}.{name}")
        properties = []
        # Size before CFrame, and both before the rest, as a part is authored.
        for key in sorted(entry, key=lambda k: (k != "s", k != "cf", k)):
            if key in SKIP:
                continue
            prop, value = typed(key, entry[key])
            properties.append({"name": prop, "value": value})
        items.append({"className": entry["c"], "parentPath": parent, "name": name, "properties": properties})

    failed = 0
    for start in range(0, len(items), BATCH):
        call("set_active_studio", {"studio": lobby[0]["instanceId"]})
        text = call("mass_create", {"items": items[start : start + BATCH], "atomic": False})
        result = json.loads(text)
        bad = result["failed"] + [row for row in result["succeeded"] if row["propertyErrors"]]
        failed += len(bad)
        for row in bad[:5]:
            print("failed:", json.dumps(row)[:300])
        print(f"{min(start + BATCH, len(items))}/{len(items)}")
    if failed:
        raise SystemExit(f"{failed} instances failed: the old range is left in place, {RANGE}.Hall_new holds what was made")

    for name in ("Hall", "Door"):
        if name in present:
            call("delete_instance", {"path": f"{RANGE}.{name}"})
        call("set_property", {"path": f"{RANGE}.{name}_new", "name": "Name", "value": {"type": "primitive", "value": name}})
    print(f"pushed {len(items)} instances; save the place")


main()
