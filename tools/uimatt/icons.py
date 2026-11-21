"""Cuts the In-Game HUD's icons out of the designer's art into one white atlas, tinted where it is drawn, and draws the
streaks his panel faces carry into a texture laid over every panel.

    python3 tools/uimatt/icons.py                          # write both
    python3 tools/uimatt/icons.py --upload Icons           # and upload one (or both) as group 34796361
    python3 tools/uimatt/icons.py --upload PanelTexture


Reads the PNGs rur saved beside the In-Game HUD render (Assets/ui/UIMatt/renders/15_In_Game_HUD/assets) and writes
Assets/ui/hud/Icons.png (128 px cells, 4 across) and Icons.json (name -> cell). Each icon is a coverage mask: how
much of a pixel is the glyph's colour against the panel behind it, so the anti-aliased edge survives. The designer's
image ids are private to another account and never referenced; the atlas is uploaded by group 34796361.

--upload sends it as a Decal with ROBLOX_CONFIGS_API_KEY_PROD (a user key with asset write, which creates assets
owned by the group in ROBLOX_CREATOR_GROUP_ID), then reads the Image id the Decal wraps from asset delivery (an
ImageLabel needs the Image, not the Decal), records both in Assets/ui/hud/asset_ids.json and writes the Image into
its line of src/Global/Client/UI/Icons.luau. Each upload is a new asset: Open Cloud cannot update a Decal's image in
place, so upload only what changed.

The texture is drawn, not cut: his faces are too small to tile from. White streaks on transparent, 1 px per design px,
1024 square so any panel up to 512 px finds a window into it at any phase. Its alpha is stretched to full range
(TEXTURE_PEAK is the strongest streak's real alpha) so the upload's 8 bits are not spent on 0-40, and the panel puts
the peak back with ImageTransparency. Measured off his WAVE plate: base face (18, 12, 36), long streaks 6.5 luminance
above it at the median, about 24 of them over 80 rows of 374 px.
"""
import gzip
import json
import os
import re
import sys
import time
import urllib.request
import uuid

import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SOURCE = os.path.join(ROOT, "Assets", "ui", "UIMatt", "renders", "15_In_Game_HUD", "assets")
OUT = os.path.join(ROOT, "Assets", "ui", "hud")
CELL = 128
PAD = 6
COLUMNS = 4
TEXTURE_SIZE = 1024
TEXTURE_PEAK = 0.16
# The streaks' ink (Theme.Palette.Lavender) and the face under them, as luminance.
LAVENDER_LUMINANCE = 190.0
FACE_LUMINANCE = 22.0
# name: (file, the Icons.luau field its Image id goes in)
UPLOADS = {
    "Icons": ("Icons.png", "IMAGE"),
    "PanelTexture": ("PanelTexture.png", "PANEL_TEXTURE"),
}


def white(a):
    return np.clip((a[..., :3].min(-1) - 90) / (225 - 90), 0, 1)


def pink(a):
    return np.clip((a[..., 0] - a[..., 1] - 100) / 100, 0, 1)


def green(a):
    return np.clip((a[..., 1] - a[..., 0] - 60) / 110, 0, 1)


def gold(a):
    return np.clip((a[..., 0] - a[..., 2] - 90) / 110, 0, 1)


def dark(a):
    return np.clip((200 - a[..., 0]) / 140, 0, 1)


# name: (file, coverage, crop box in the source's pixels, and a box inside it to blank: the count badge's corner)
ICONS = {
    "Squad": ("102488643301775.png", white, (124, 74, 179, 123)),
    "Settings": ("117907024936005.png", white, (84, 69, 145, 131)),
    "Boss": ("105424574669114.png", pink, (100, 72, 170, 160)),
    "Barricade": ("81637994815500.png", white, (138, 88, 297, 242)),
    "HealAll": ("96605410628882.png", green, (110, 76, 214, 177), (203, 0, 999, 92)),
    "NukeAll": ("81873692731083.png", gold, (108, 76, 214, 182), (203, 0, 999, 92)),
    "Skip": ("136264706820933.png", white, (170, 102, 208, 136)),
    "Coins": ("74780406950195.png", dark, (22, 38, 143, 123)),
    "Health": ("139807635165862.png", white, (136, 95, 294, 234)),
    "Shotgun": ("111485632705697.png", white, (144, 87, 290, 242)),
    "Airstrike": ("97897316009467.png", white, (149, 91, 289, 231)),
    "Pack": ("96646665217373.png", white, (95, 87, 166, 139)),
}


def cut(file, coverage, box, blank=None):
    rgba = np.asarray(Image.open(os.path.join(SOURCE, file)).convert("RGBA")).astype(float)
    if blank:
        rgba = rgba.copy()
        rgba[blank[1] : blank[3], blank[0] : blank[2], 3] = 0
    x0, y0, x1, y1 = box
    region = rgba[y0:y1, x0:x1]
    alpha = coverage(region) * (region[..., 3] / 255)
    ys, xs = np.where(alpha > 0.02)
    alpha = alpha[ys.min() : ys.max() + 1, xs.min() : xs.max() + 1]
    image = np.zeros(alpha.shape + (4,), np.uint8)
    image[..., :3] = 255
    image[..., 3] = np.round(alpha * 255).astype(np.uint8)
    return Image.fromarray(image, "RGBA")


def main():
    os.makedirs(OUT, exist_ok=True)
    rows = (len(ICONS) + COLUMNS - 1) // COLUMNS
    atlas = Image.new("RGBA", (CELL * COLUMNS, CELL * rows), (255, 255, 255, 0))
    cells = {}
    for index, (name, spec) in enumerate(ICONS.items()):
        glyph = cut(*spec)
        fit = (CELL - 2 * PAD) / max(glyph.size)
        glyph = glyph.resize((round(glyph.size[0] * fit), round(glyph.size[1] * fit)), Image.LANCZOS)
        column, row = index % COLUMNS, index // COLUMNS
        x = column * CELL + (CELL - glyph.size[0]) // 2
        y = row * CELL + (CELL - glyph.size[1]) // 2
        atlas.alpha_composite(glyph, (x, y))
        cells[name] = {"x": column * CELL, "y": row * CELL, "size": CELL}
    atlas.save(os.path.join(OUT, "Icons.png"))
    with open(os.path.join(OUT, "Icons.json"), "w") as f:
        json.dump(cells, f, indent=1)
    print(f"[ICONS] {len(cells)} icons -> Assets/ui/hud/Icons.png")


def texture():
    rng = np.random.default_rng(7)
    size = TEXTURE_SIZE
    lift = np.zeros((size, size))

    def streak(y, x0, length, strength, rows):
        t = np.arange(length)
        ramp = min(20, max(4, length // 5))
        envelope = np.minimum(1, np.minimum((t + 1) / ramp, (length - t) / ramp))
        wobble = 1 + 0.2 * np.sin(t / rng.uniform(9, 40) + rng.uniform(0, 6.28))
        columns = (x0 + t) % size
        for k in range(rows):
            np.add.at(lift[(y + k) % size], columns, strength * envelope * wobble * (1 if k == 0 else 0.6))

    # Thin lines, mostly one row.
    for _ in range(430):
        length = int(np.clip(rng.lognormal(np.log(170), 0.75), 30, 800))
        strength = float(np.clip(rng.lognormal(np.log(6.5), 0.45), 2.5, 20))
        streak(int(rng.integers(size)), int(rng.integers(size)), length, strength, 1 if rng.random() < 0.8 else 2)
    # Soft bands a few rows tall.
    for _ in range(60):
        length = int(np.clip(rng.lognormal(np.log(220), 0.6), 60, 800))
        y0, x0 = int(rng.integers(size)), int(rng.integers(size))
        height, strength = int(rng.integers(3, 6)), rng.uniform(2.5, 5)
        for k in range(height):
            streak((y0 + k) % size, x0, length, strength * np.sin(np.pi * (k + 0.5) / height), 1)
    # Whole rows a touch lighter, in runs.
    y = 0
    while y < size:
        run = int(rng.integers(1, 5))
        lift[y : y + run] += max(0.0, rng.normal(0, 1.4))
        y += run + int(rng.integers(0, 6))

    alpha = np.clip(lift / (LAVENDER_LUMINANCE - FACE_LUMINANCE) / TEXTURE_PEAK, 0, 1)
    image = np.zeros((size, size, 4), np.uint8)
    image[..., :3] = 255
    image[..., 3] = np.round(alpha * 255).astype(np.uint8)
    Image.fromarray(image, "RGBA").save(os.path.join(OUT, "PanelTexture.png"))
    print(f"[ICONS] texture -> Assets/ui/hud/PanelTexture.png (peak alpha {TEXTURE_PEAK})")


def env():
    values = {}
    with open(os.path.join(ROOT, ".env")) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                values[key.strip()] = value.strip().strip('"').strip("'")
    return values["ROBLOX_CONFIGS_API_KEY_PROD"], values["ROBLOX_CREATOR_GROUP_ID"]


def call(method, url, key, body=None, content_type=None):
    request = urllib.request.Request(url, data=body, method=method, headers={"x-api-key": key})
    if content_type:
        request.add_header("Content-Type", content_type)
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read()


def upload(name):
    key, group = env()
    file, field = UPLOADS[name]
    path = os.path.join(OUT, file)
    meta = {
        "assetType": "Decal",
        "displayName": f"Hud{name}",
        "description": f"Kill All The Monsters HUD: {name}",
        "creationContext": {"creator": {"groupId": group}},
    }
    boundary = uuid.uuid4().hex
    with open(path, "rb") as f:
        data = f.read()
    body = (
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"request\"\r\nContent-Type: application/json\r\n\r\n".encode()
        + json.dumps(meta).encode()
        + f"\r\n--{boundary}\r\nContent-Disposition: form-data; name=\"fileContent\"; filename=\"{file}\"\r\n"
        f"Content-Type: image/png\r\n\r\n".encode()
        + data
        + f"\r\n--{boundary}--\r\n".encode()
    )
    operation = json.loads(
        call("POST", "https://apis.roblox.com/assets/v1/assets", key, body, f"multipart/form-data; boundary={boundary}")
    )
    path_ = operation.get("path") or f"operations/{operation['operationId']}"
    for _ in range(60):
        done = json.loads(call("GET", f"https://apis.roblox.com/assets/v1/{path_}", key))
        if done.get("done"):
            break
        time.sleep(2)
    else:
        sys.exit("timed out waiting for the upload")
    decal = str(done["response"]["assetId"])
    print(f"[ICONS] {name}: Decal {decal}")

    # The Decal's own content is a small XML naming the Image it wraps.
    for _ in range(30):
        try:
            location = json.loads(call("GET", f"https://apis.roblox.com/asset-delivery-api/v1/assetId/{decal}", key))
            raw = urllib.request.urlopen(location["location"], timeout=60).read()
            break
        except Exception:
            time.sleep(4)
    else:
        sys.exit("could not read the Decal back to find its Image id")
    try:
        raw = gzip.decompress(raw)
    except OSError:
        pass
    image = re.search(rb"id=(\d+)", raw).group(1).decode()
    print(f"[ICONS] {name}: Image {image}")
    ids_path = os.path.join(OUT, "asset_ids.json")
    ids = json.load(open(ids_path)) if os.path.exists(ids_path) else {}
    ids[name] = {"image": image, "decal": decal, "file": file}
    with open(ids_path, "w") as f:
        json.dump(ids, f, indent=1)

    luau = os.path.join(ROOT, "src", "Global", "Client", "UI", "Icons.luau")
    source = open(luau).read()
    source, count = re.subn(rf'(Icons\.{field} = "rbxassetid://)\d+(")', rf"\g<1>{image}\2", source)
    if count != 1:
        sys.exit(f"Icons.{field} not found in Icons.luau: set it to rbxassetid://{image} by hand")
    with open(luau, "w") as f:
        f.write(source)
    print(f"[ICONS] Icons.{field} = rbxassetid://{image}")


if __name__ == "__main__":
    main()
    texture()
    if "--upload" in sys.argv:
        for name in sys.argv[sys.argv.index("--upload") + 1 :]:
            upload(name)
