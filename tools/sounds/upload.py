"""Uploads sound clips to Roblox as the group that owns this game (34796361), and records their asset ids.

    python3 tools/sounds/upload.py Assets/sounds/<Group>/<Clip>/*.wav

Same key, creator and Open Cloud calls as tools/rig/upload.py (audio, like animations, plays only in games its owner
owns). Ids go to Assets/sounds/asset_ids.json keyed by file name, and a file already in it is uploaded as a new
version of its asset. Paste the ids into tools/sounds/Sounds.txt and run tools/sounds/build.luau.
"""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "rig"))
import upload as rig  # noqa: E402

IDS = os.path.join(rig.ROOT, "Assets", "sounds", "asset_ids.json")
rig.CONTENT_TYPES.update({".wav": "audio/wav", ".mp3": "audio/mpeg", ".ogg": "audio/ogg", ".flac": "audio/flac"})


def main():
    paths = sys.argv[1:]
    if not paths:
        sys.exit("usage: python3 tools/sounds/upload.py <clip>...")
    key, group = rig.env()
    ids = json.load(open(IDS)) if os.path.isfile(IDS) else {}
    for path in paths:
        label = os.path.splitext(os.path.basename(path))[0]
        try:
            rig.upload(key, group, ids, label, path, "Audio")
        finally:
            # Saved after every clip, so a failure part way keeps the ids of what did go up.
            with open(IDS, "w") as f:
                json.dump(ids, f, indent=2)


if __name__ == "__main__":
    main()
