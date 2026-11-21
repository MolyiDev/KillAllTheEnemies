#!/usr/bin/env python3
# Minimal Tripwire MCP client: tw.py <tool> '<json args>'  |  tw.py --list
import json, sys, urllib.request
URL = "http://127.0.0.1:44331/mcp"
H = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}

def post(body, sid=None):
    h = dict(H)
    if sid: h["mcp-session-id"] = sid
    req = urllib.request.Request(URL, data=json.dumps(body).encode(), headers=h, method="POST")
    with urllib.request.urlopen(req, timeout=900) as r:
        sid = r.headers.get("mcp-session-id") or sid
        raw = r.read().decode()
    out = None
    for line in raw.splitlines():
        if line.startswith("data: ") and line[6:].strip():
            try:
                m = json.loads(line[6:])
                if "id" in m and m.get("id") == body.get("id"): out = m
            except Exception: pass
    return out, sid

def session():
    _, sid = post({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"claude","version":"0"}}})
    post({"jsonrpc":"2.0","method":"notifications/initialized"}, sid)
    return sid

if __name__ == "__main__":
    sid = session()
    if sys.argv[1] == "--list":
        r, _ = post({"jsonrpc":"2.0","id":2,"method":"tools/list"}, sid)
        for t in r["result"]["tools"]:
            print("##", t["name"], "-", t.get("description","")[:300].replace("\n"," "))
            print("   args:", json.dumps(t.get("inputSchema",{}).get("properties",{}))[:600])
    else:
        args = json.loads(sys.argv[2]) if len(sys.argv) > 2 else {}
        if len(sys.argv) > 2 and sys.argv[2].startswith("@"):
            args = json.load(open(sys.argv[2][1:]))
        r, _ = post({"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":sys.argv[1],"arguments":args}}, sid)
        if r is None: print("NO RESPONSE"); sys.exit(1)
        if "error" in r: print("ERROR", json.dumps(r["error"])); sys.exit(1)
        for c in r["result"].get("content", []):
            print(c.get("text", c))
        if r["result"].get("isError"): sys.exit(2)
