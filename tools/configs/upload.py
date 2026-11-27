#!/usr/bin/env python3
"""Publish MainConfig.json to Roblox Experience Configs (Creator Hub > Configs).

Configs live on the universe, so each universe below covers both its lobby and
its game place. By default every universe gets the upload, in order (test first
once there is one), and a later one is only touched once the earlier published
and verified.

Usage:
    python3 tools/configs/upload.py                    # test, then prod
    python3 tools/configs/upload.py Shop Codes         # only these keys
    python3 tools/configs/upload.py --only test        # one universe
    python3 tools/configs/upload.py --dry-run

API keys come from ROBLOX_CONFIGS_API_KEY_TEST / ROBLOX_CONFIGS_API_KEY_PROD,
falling back to ROBLOX_CONFIGS_API_KEY for a key that covers both. The root
.env is loaded automatically; existing environment variables take precedence. Each needs
the universe:write and universe:read scopes on its universe. With no key
names every top-level key in MainConfig.json is sent;
keys not named are left as they are (a PATCH, never an overwrite). After
publishing, the live values are read back and compared, because Roblox can
answer a request made with a missing scope with success while ignoring it.
"""

import argparse
import json
import os
import re
import shlex
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONFIG_PATH = ROOT / "MainConfig.json"
ENUM_PATH = ROOT / "src/Global/Types/Enums/EConfigKeys.luau"

# Lobby and game places share one universe per environment, uploaded in this order. There is no test universe
# yet: add it FIRST ("test": <id>) when one exists. The prod universe also holds the old game place
# (104435679031452), so a config published here is live for it too.
UNIVERSES = {
    "prod": 10768635421,  # lobby 105859632802526, game 113327793187086
}

API_BASE = "https://apis.roblox.com/creator-configs-public-api/v1/configs/universes/{}/repositories/InExperienceConfig"


class ApiError(Exception):
    def __init__(self, method: str, url: str, code: int, body: str):
        super().__init__(f"{method} {url} failed with {code}: {body}")
        self.body = body


def request(method: str, url: str, api_key: str, body: dict | None = None) -> dict:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("x-api-key", api_key)
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as response:
            text = response.read().decode()
    except urllib.error.HTTPError as error:
        raise ApiError(method, url, error.code, error.read().decode()) from None
    return json.loads(text) if text else {}


# The API docs don't say whether a JSON value reads back as an object or as a JSON string.
def decode(value):
    if isinstance(value, str):
        try:
            return json.loads(value)
        except json.JSONDecodeError:
            return value
    return value


def enum_keys() -> set[str]:
    return set(re.findall(r"^\s*(\w+) = \"\w+\",", ENUM_PATH.read_text(), re.MULTILINE))


def load_env() -> None:
    path = ROOT / ".env"
    if not path.is_file():
        return

    for line in path.read_text().splitlines():
        name, separator, value = line.strip().removeprefix("export ").partition("=")
        name = name.strip()
        if not separator or name not in (
            "ROBLOX_CONFIGS_API_KEY_TEST",
            "ROBLOX_CONFIGS_API_KEY_PROD",
            "ROBLOX_CONFIGS_API_KEY",
        ):
            continue
        parts = shlex.split(value, comments=True)
        if len(parts) != 1:
            sys.exit(f"Invalid value for {name} in .env")
        os.environ.setdefault(name, parts[0])


def api_key_for(target: str) -> str | None:
    return os.environ.get(f"ROBLOX_CONFIGS_API_KEY_{target.upper()}") or os.environ.get("ROBLOX_CONFIGS_API_KEY")


def publish(target: str, api_key: str, entries: dict, message: str) -> None:
    base = API_BASE.format(UNIVERSES[target])
    draft = request("PATCH", f"{base}/draft", api_key, {"entries": entries})
    draft_hash = draft.get("draftHash")
    if not draft_hash:
        sys.exit(f"{target}: draft response had no draftHash: {draft}")

    try:
        published = request(
            "POST",
            f"{base}/publish",
            api_key,
            {"draftHash": draft_hash, "message": message, "deploymentStrategy": "Immediate"},
        )
        print(f"{target}: published {published}")
    except ApiError as error:
        # Roblox refuses to publish a draft identical to what is live.
        if "EmptyDraft" not in error.body:
            raise
        print(f"{target}: already up to date")

    live = request("GET", base, api_key).get("entries", {})
    mismatched = [key for key, value in entries.items() if decode(live.get(key)) != value]
    if mismatched:
        sys.exit(f"{target}: live values differ after publish (check the key's scopes): {', '.join(mismatched)}")
    print(f"{target}: verified {len(entries)} keys live")


def main() -> None:
    parser = argparse.ArgumentParser(description="Publish MainConfig.json to Roblox Experience Configs.")
    parser.add_argument("--only", choices=list(UNIVERSES), help="upload to one universe instead of all")
    parser.add_argument("keys", nargs="*", help="only send these top-level keys")
    parser.add_argument("--dry-run", action="store_true", help="print what would be sent and stop")
    parser.add_argument("--message", default="Upload MainConfig.json", help="version history message")
    args = parser.parse_args()

    load_env()
    config = json.loads(CONFIG_PATH.read_text())
    keys = args.keys or list(config)
    missing = [key for key in keys if key not in config]
    if missing:
        sys.exit(f"Not in MainConfig.json: {', '.join(missing)}")

    # A key the game never observes would publish fine and silently do nothing.
    unknown = [key for key in keys if key not in enum_keys()]
    if unknown:
        sys.exit(f"Not in EConfigKeys: {', '.join(unknown)}")

    entries = {key: config[key] for key in keys}
    for key, value in entries.items():
        print(f"{key:14} {len(json.dumps(value, separators=(',', ':'))):6} chars")
    if args.dry_run:
        return

    targets = [args.only] if args.only else list(UNIVERSES)
    # Check every key up front so a missing prod key can't strand a half-done upload.
    missing_keys = [target for target in targets if not api_key_for(target)]
    if missing_keys:
        names = ", ".join(f"ROBLOX_CONFIGS_API_KEY_{target.upper()}" for target in missing_keys)
        sys.exit(f"Set {names} (or ROBLOX_CONFIGS_API_KEY for all)")

    for target in targets:
        try:
            publish(target, api_key_for(target), entries, args.message)
        except ApiError as error:
            sys.exit(f"{target}: {error}")


if __name__ == "__main__":
    main()
