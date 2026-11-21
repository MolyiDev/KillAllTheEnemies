"""Uploads the built rigs and clips to Roblox as the group that owns this game, and records their asset ids.

    python3 tools/rig/upload.py ZombieNormal            # the rig and the shared clips
    python3 tools/rig/upload.py ZombieNormal --rig-only
    python3 tools/rig/upload.py ZombieNormal --bare     # from fbx_bare/ (export.py with NO_TEXTURE=1)
    python3 tools/rig/upload.py --player                # the player's locomotion clips (Assets/animations/Player)
    python3 tools/rig/upload.py --clips MonsterR6       # every Assets/animations/MonsterR6/*.rbxm as an Animation
    python3 tools/rig/upload.py --texture Walker        # Assets/models/Enemies/Walker_diff.png as a Decal

A TEXTURE GOES UP ON ITS OWN, after it has been looked at: Roblox moderated an atlas baked into a rig FBX for gore
(2026-11-20), so rigs go up bare (--bare) and each texture is its own Decal, whose Image id the MeshPart's TextureID
takes. A Decal cannot be updated in place: each --texture run is a new asset.

THE PLAYER'S CLIPS are BeACastleLord's Idle and walks, owned by its group, read out of a playtest and rebuilt as
KeyframeSequence .rbxm files by tools/lune/keyframes.luau; their ids go to Assets/animations/Player/asset_ids.json.

AS THE GAME'S GROUP: the universe belongs to group 34796361, and Roblox plays an animation or a sound only in games
its owner owns, so anything uploaded by another group or a user would never play here. This reads
ROBLOX_GROUP_OPEN_CLOUD_KEY (an Open Cloud key on that group, Assets read and write) and ROBLOX_CREATOR_GROUP_ID from the
project's .env, and never prints either.

THE SAME ASSETS ARE UPDATED, NOT RE-CREATED: ids go to Assets/models/Enemies/fbx/asset_ids.json, and a file already in
it is uploaded as a new version of its asset (PATCH), so the place's references keep working after a rebuild.

The call is Open Cloud's Assets API, the one Tripwire's upload_asset makes (FBX as `model/fbx` for both a Model and
an Animation), polled until its operation is done.
"""
import gzip
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
import uuid

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
FBX = os.path.join(ROOT, "Assets", "models", "Enemies", "fbx")
IDS = os.path.join(FBX, "asset_ids.json")
BASE = "https://apis.roblox.com/assets/v1"
CLIPS = ("Idle", "Walk", "Attack", "Slam", "Fuse")
PLAYER = os.path.join(ROOT, "Assets", "animations", "Player")
PLAYER_CLIPS = ("Idle", "WalkFront", "WalkBack", "WalkLeft", "WalkRight")
CONTENT_TYPES = {".fbx": "model/fbx", ".rbxm": "model/x-rbxm", ".png": "image/png"}
ANIMATIONS = os.path.join(ROOT, "Assets", "animations")
ENEMIES = os.path.dirname(FBX)


def env():
    values = {}
    with open(os.path.join(ROOT, ".env")) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                values[key.strip()] = value.strip().strip('"').strip("'")
    # A user key with asset write creates assets owned by the group too (creationContext names the group).
    key = values.get("ROBLOX_GROUP_OPEN_CLOUD_KEY") or values.get("ROBLOX_CONFIGS_API_KEY_PROD")
    if not key:
        sys.exit("missing ROBLOX_GROUP_OPEN_CLOUD_KEY (or ROBLOX_CONFIGS_API_KEY_PROD) in .env")
    if not values.get("ROBLOX_CREATOR_GROUP_ID"):
        sys.exit("missing ROBLOX_CREATOR_GROUP_ID in .env")
    return key, values["ROBLOX_CREATOR_GROUP_ID"]


class UploadError(Exception):
    pass


def request(method, url, key, body=None, content_type=None):
    req = urllib.request.Request(url, data=body, method=method, headers={"x-api-key": key})
    if content_type:
        req.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(req, timeout=120) as response:
            return json.loads(response.read() or b"null")
    except urllib.error.HTTPError as e:
        raise UploadError(f"{method} {url.split('?')[0]} failed: {e.code} {e.read().decode(errors='replace')[:400]}")


def multipart(meta, path):
    boundary = uuid.uuid4().hex
    with open(path, "rb") as f:
        data = f.read()
    parts = [
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"request\"\r\nContent-Type: application/json\r\n\r\n"
        .encode() + json.dumps(meta).encode() + b"\r\n",
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"fileContent\"; filename=\"{os.path.basename(path)}\"\r\n"
        f"Content-Type: {CONTENT_TYPES[os.path.splitext(path)[1]]}\r\n\r\n".encode() + data + b"\r\n",
        f"--{boundary}--\r\n".encode(),
    ]
    return b"".join(parts), f"multipart/form-data; boundary={boundary}"


def wait(key, operation):
    path = operation.get("path") or f"operations/{operation.get('operationId')}"
    for _ in range(90):
        done = request("GET", f"{BASE}/{path}", key)
        if done.get("done"):
            if done.get("error"):
                sys.exit(f"rejected: {done['error']}")
            return done["response"]
        time.sleep(2)
    sys.exit("timed out waiting for the upload to finish")


def upload(key, group, ids, label, path, asset_type):
    meta = {"assetType": asset_type, "displayName": label, "description": "Kill All The Monsters " + asset_type.lower()}
    known = ids.get(label)
    if known:
        body, ctype = multipart({"assetId": known}, path)
        op = request("PATCH", f"{BASE}/assets/{known}?updateMask=description", key, body, ctype)
    else:
        meta["creationContext"] = {"creator": {"groupId": group}}
        body, ctype = multipart(meta, path)
        op = request("POST", f"{BASE}/assets", key, body, ctype)
    response = wait(key, op)
    ids[label] = str(response.get("assetId") or known)
    print(f"[UPLOAD] {label}: {asset_type} {ids[label]}{' (new version)' if known else ''}")


def upload_texture(key, group, name):
    """The Decal, then the Image it wraps (a TextureID takes the Image): the Decal's own content is an XML naming it."""
    path = os.path.join(ENEMIES, f"{name}_diff.png")
    meta = {"assetType": "Decal", "displayName": f"{name}Texture", "description": "Kill All The Monsters enemy texture",
            "creationContext": {"creator": {"groupId": group}}}
    body, ctype = multipart(meta, path)
    decal = str(wait(key, request("POST", f"{BASE}/assets", key, body, ctype))["assetId"])
    print(f"[UPLOAD] {name} texture: Decal {decal}")
    for _ in range(30):
        try:
            location = request("GET", f"https://apis.roblox.com/asset-delivery-api/v1/assetId/{decal}", key)["location"]
            with urllib.request.urlopen(location, timeout=60) as response:
                raw = response.read()
            break
        # The Decal is readable a few seconds after its operation is done; until then this is a 404 or no location.
        except (UploadError, urllib.error.URLError, KeyError):
            time.sleep(4)
    else:
        sys.exit(f"could not read Decal {decal} back to find its Image id")
    if raw[:2] == b"\x1f\x8b":
        raw = gzip.decompress(raw)
    image = re.search(rb"id=(\d+)", raw).group(1).decode()
    print(f"[UPLOAD] {name} texture: Image {image}")
    return {"decal": decal, "image": image}


def main():
    global FBX
    key, group = env()
    if "--texture" in sys.argv:
        ids = json.load(open(IDS)) if os.path.isfile(IDS) else {}
        for name in sys.argv[sys.argv.index("--texture") + 1:]:
            ids[f"{name}_diff"] = upload_texture(key, group, name)
            with open(IDS, "w") as f:
                json.dump(ids, f, indent=2)
        return
    if "--clips" in sys.argv:
        clip_set = sys.argv[sys.argv.index("--clips") + 1]
        folder = os.path.join(ANIMATIONS, clip_set)
        ids_path = os.path.join(folder, "asset_ids.json")
        jobs = [(f"{clip_set}_{os.path.splitext(f)[0]}", os.path.join(folder, f), "Animation")
                for f in sorted(os.listdir(folder)) if f.endswith(".rbxm")]
    elif "--player" in sys.argv:
        ids_path = os.path.join(PLAYER, "asset_ids.json")
        jobs = [(f"Player_{clip}", os.path.join(PLAYER, f"{clip}.rbxm"), "Animation") for clip in PLAYER_CLIPS]
    else:
        name = sys.argv[1]
        if "--bare" in sys.argv:
            FBX = os.path.join(os.path.dirname(FBX), "fbx_bare")
        ids_path = IDS
        jobs = [(name, os.path.join(FBX, f"{name}.fbx"), "Model")]
        if "--rig-only" not in sys.argv:
            jobs += [(f"ZombieR6_{clip}", os.path.join(FBX, f"ZombieNormal_{clip}.fbx"), "Animation") for clip in CLIPS]
    ids = json.load(open(ids_path)) if os.path.isfile(ids_path) else {}
    for label, path, asset_type in jobs:
        try:
            upload(key, group, ids, label, path, asset_type)
        finally:
            # Saved after every asset, so a failure part way keeps the ids of what did go up.
            with open(ids_path, "w") as f:
                json.dump(ids, f, indent=2)


if __name__ == "__main__":
    try:
        main()
    except UploadError as e:
        sys.exit(str(e))
