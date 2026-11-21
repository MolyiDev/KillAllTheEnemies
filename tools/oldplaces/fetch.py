"""Downloads Roblox assets by id through Open Cloud's asset delivery API, into a folder, one file per id (gzip undone).

    python3 tools/oldplaces/fetch.py <outdir> <assetId> [assetId ...]

Reads the key from the repo's .env (ROBLOX_CONFIGS_API_KEY_PROD, else ROBLOX_ASSET_DELIVERY_API_KEY) and never prints
it. A clothing or decal id comes back as an XML wrapper naming its image id; fetch that id too.
"""
import gzip
import json
import os
import sys
import urllib.request

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))


def env():
    values = {}
    with open(os.path.join(ROOT, ".env")) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                values[key.strip()] = value.strip().strip('"').strip("'")
    for key in ("ROBLOX_CONFIGS_API_KEY_PROD", "ROBLOX_ASSET_DELIVERY_API_KEY"):
        if values.get(key):
            return values[key]
    sys.exit("no asset delivery key in .env")


def main():
    out, ids = sys.argv[1], sys.argv[2:]
    os.makedirs(out, exist_ok=True)
    key = env()
    for asset_id in ids:
        try:
            req = urllib.request.Request(f"https://apis.roblox.com/asset-delivery-api/v1/assetId/{asset_id}",
                                         headers={"x-api-key": key})
            with urllib.request.urlopen(req, timeout=60) as response:
                location = json.loads(response.read())["location"]
            with urllib.request.urlopen(location, timeout=60) as response:
                data = response.read()
            if data[:2] == b"\x1f\x8b":
                data = gzip.decompress(data)
            with open(os.path.join(out, asset_id), "wb") as f:
                f.write(data)
            print(asset_id, len(data), data[:24])
        except Exception as e:  # noqa: BLE001
            body = e.read()[:200] if hasattr(e, "read") else b""
            print(asset_id, "ERROR", e, body)


if __name__ == "__main__":
    main()
