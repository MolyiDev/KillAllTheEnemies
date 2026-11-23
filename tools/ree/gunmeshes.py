#!/usr/bin/env python3
"""Downloads gun meshes by asset id into Assets/models/Guns/meshes (each a file named by its id), through the
Tripwire daemon on this machine: the guns' meshes are private, so the offline renderer cannot fetch them itself.
    python3 tools/ree/gunmeshes.py <asset id> ...
Ids already on disk are skipped. Tripwire must be running (its daemon listens on 127.0.0.1:44331)."""
import json
import os
import sys
import urllib.request

URL = "http://127.0.0.1:44331/mcp"
OUT = os.path.abspath("Assets/models/Guns/meshes")
session = None


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
    reply = urllib.request.urlopen(urllib.request.Request(URL, json.dumps(body).encode(), headers), timeout=120)
    session = reply.headers.get("Mcp-Session-Id") or session
    text = reply.read().decode()
    if "data:" in text[:40] or text.startswith("event"):
        text = "\n".join(line[5:] for line in text.splitlines() if line.startswith("data:"))
    return json.loads(text) if text.strip() else None


def main():
    wanted = [i for i in sys.argv[1:] if not os.path.exists(os.path.join(OUT, i))]
    if not wanted:
        return
    os.makedirs(OUT, exist_ok=True)
    rpc("initialize", {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "gunmeshes", "version": "1"}}, 1)
    rpc("notifications/initialized")
    failed = []
    for n, asset in enumerate(wanted):
        reply = rpc("tools/call", {"name": "download_asset", "arguments": {"assetId": asset, "outPath": f"{OUT}/{asset}"}}, 10 + n)
        if not reply or reply.get("error") or reply["result"].get("isError"):
            failed.append(asset)
    print(f"downloaded {len(wanted) - len(failed)}, failed {len(failed)} {' '.join(failed)}")
    sys.exit(1 if failed else 0)


main()
