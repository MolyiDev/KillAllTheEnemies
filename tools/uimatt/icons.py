"""Cuts the In-Game HUD's and the Lobby HUD's icons out of the designer's art into one white atlas, tinted where it is drawn, and draws the
streaks his panel faces carry into a texture laid over every panel.

    python3 tools/uimatt/icons.py                          # write both
    python3 tools/uimatt/icons.py --upload Icons           # and upload one (or both) as group 34796361
    python3 tools/uimatt/icons.py --upload PanelTexture


Reads the PNGs rur saved beside the In-Game HUD render (Assets/ui/UIMatt/renders/15_In_Game_HUD/assets; a file
named with its folder is read from that screen's render instead) and writes
Assets/ui/hud/Icons.png (128 px cells, 4 across, 8 down, then a second page of 4 across) and Icons.json (name -> cell). Each icon is a coverage mask: how
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
RENDERS = os.path.join(ROOT, "Assets", "ui", "UIMatt", "renders")
SOURCE = os.path.join(RENDERS, "15_In_Game_HUD", "assets")
RESULTS = "19_Round_Results/assets/"
SETTINGS = "07_Settings/assets/"
CONFIRM = "08_Settings_Reset_Confirm/assets/"
LOBBY = "01_Lobby_HUD/assets/"
WEAPONS = "02_Weapons_Shop/assets/"
SPINS = "12_Daily_Spins/assets/"
QUESTS = "09_Quests_Daily/assets/"
INDEX = "04_Index/assets/"
OUT = os.path.join(ROOT, "Assets", "ui", "hud")
CELL = 128
PAD = 6
COLUMNS = 4
# Roblox shrinks an image past 1024 px on a side, which would move every cell: past 8 rows the atlas grows a second
# page of 4 columns to the right, so the cells already in use never move.
PAGE_ROWS = 8
TEXTURE_SIZE = 1024
TEXTURE_PEAK = 0.16
# The streaks' ink (Theme.Palette.Lavender) and the face under them, as luminance.
LAVENDER_LUMINANCE = 190.0
FACE_LUMINANCE = 22.0
# The weapons screen's stage floor, drawn into the atlas's free corner at 1:1 (his 470 x 84 ellipse): a 1.5 px ring at
# full alpha and the fill at FLOOR_FILL of it, so one ImageTransparency gives both his strengths. Page two's icon rows
# stop above it (rows 0-6).
FLOOR_AT = (512, 1024 - 88)
FLOOR_SIZE = (470, 84)
FLOOR_LINE = 1.5
FLOOR_FILL = 0.25
# name: (file, the Icons.luau field its Image id goes in)
UPLOADS = {
    "Icons": ("Icons.png", "IMAGE"),
    "PanelTexture": ("PanelTexture.png", "PANEL_TEXTURE"),
}


def white(a):
    return np.clip((a[..., :3].min(-1) - 90) / (225 - 90), 0, 1)


def pink(a):
    return np.clip((a[..., 0] - a[..., 1] - 100) / 100, 0, 1)


# The confirm's warning red, which `pink` takes at four fifths; its tile's dark red face stays out.
def red(a):
    return np.clip((a[..., 0] - a[..., 1] - 90) / 80, 0, 1)


def green(a):
    return np.clip((a[..., 1] - a[..., 0] - 60) / 110, 0, 1)


def gold(a):
    return np.clip((a[..., 0] - a[..., 2] - 90) / 110, 0, 1)


def dark(a):
    return np.clip((200 - a[..., 0]) / 140, 0, 1)


# White on a bright face (the violet and steel slabs), where `white` would take the face too.
def bright(a):
    return np.clip((a[..., :3].min(-1) - 215) / (250 - 215), 0, 1)


def blue(a):
    return np.clip((a[..., 2] - a[..., 0] - 90) / 70, 0, 1)


def violet(a):
    return np.clip((a[..., 2] - a[..., 1] - 95) / 70, 0, 1)


# White on the steel pill and the lobby's flat slabs, whose faces run brighter than the HUD's dark panels.
def light(a):
    return np.clip((a[..., :3].min(-1) - 110) / (250 - 110), 0, 1)


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
    # The results (Round Results).
    "Skull": (RESULTS + "104386502506343.png", pink, (0, 0, 48, 56)),
    "Stopwatch": (RESULTS + "94909205766457.png", gold, (30, 40, 98, 116)),
    "Gem": (RESULTS + "110701547367116.png", blue, (80, 140, 210, 250)),
    "Robux": (RESULTS + "120333389261265.png", bright, (268, 86, 326, 148)),
    "Advert": (RESULTS + "100421269701855.png", bright, (160, 92, 216, 142)),
    "Arrow": (RESULTS + "134036027972997.png", white, (218, 132, 264, 180)),
    "Replay": (RESULTS + "114440233802906.png", white, (200, 124, 258, 190)),
    "Revive": (RESULTS + "129357551429107.png", white, (230, 120, 310, 198)),
    # The settings (Settings, Settings - Reset Confirm).
    "Reset": (SETTINGS + "118009714755116.png", gold, (80, 69, 130, 113)),
    "Pencil": (SETTINGS + "139649818264337.png", pink, (600, 24, 648, 72)),
    "Warning": (CONFIRM + "95928634624098.png", red, (464, 105, 560, 190)),
    "Music": (SETTINGS + "85445603148106.png", pink, (0, 0, 28, 30)),
    "Camera": (SETTINGS + "114795113817787.png", pink, (0, 0, 28, 30)),
    "Profile": (SETTINGS + "104283121581154.png", pink, (0, 0, 28, 30)),
    # The lobby (Lobby HUD).
    "Rank": (LOBBY + "103060127131943.png", gold, (0, 0, 70, 106)),
    "Bolt": (LOBBY + "86413066371189.png", light, (0, 0, 70, 65)),
    "Shop": (LOBBY + "73853576426051.png", gold, (130, 108, 240, 215)),
    "Gift": (LOBBY + "127246397724885.png", pink, (140, 120, 230, 215)),
    "Spin": (LOBBY + "128090333006940.png", violet, (135, 112, 235, 208)),
    "Friends": (LOBBY + "122739019370404.png", green, (130, 112, 222, 215)),
    "Rifle": (LOBBY + "130257945394564.png", light, (180, 92, 275, 198)),
    "Helmet": (LOBBY + "98610907786270.png", light, (188, 92, 262, 190)),
    # The weapons screen's: the EQUIPPED slab's tick (white on green), the tier tab's lock, the info panel's star.
    "Check": (WEAPONS + "86162458886427.png", light, (234, 88, 304, 154)),
    "Lock": (WEAPONS + "75316907530001.png", white, (290, 72, 320, 106)),
    "Star": (WEAPONS + "94894442574611.png", gold, (56, 172, 90, 202)),
    # The quests screen's scroll (the title's, pink on nothing).
    "Scroll": (QUESTS + "83344093114314.png", pink, (0, 0, 92, 106)),
    # The spins screen's: the die on SPIN (white on green), and the reel's pointer, drawn (pointer()).
    "Dice": (SPINS + "73494365881083.png", light, (310, 90, 386, 165)),
    "Pointer": None,
    # The top bar's codes button and the codes screen's header, drawn (ticket()): he drew no codes screen.
    "Ticket": None,
    # The index screen's MONSTERS card (BOSSES' crowned skull is Boss). Cropped tight: `green` takes his tile's face at
    # a few percent further out.
    "Zombie": (INDEX + "122107874079539.png", green, (116, 98, 212, 208)),
}


def cut(file, coverage, box, blank=None):
    path = os.path.join(RENDERS, file) if "/" in file else os.path.join(SOURCE, file)
    rgba = np.asarray(Image.open(path).convert("RGBA")).astype(float)
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


def pointer():
    """His gold triangle over the reel, pointing down, 3 wide to 2 tall, supersampled 4x so its edges are even."""
    k = 4
    w, h = 116 * k, 77 * k
    ys, xs = np.mgrid[0:h, 0:w].astype(float) + 0.5
    # Inside both slanted sides: the half-width shrinks linearly from the top edge to the tip.
    inside = np.abs(xs - w / 2) <= (w / 2) * (1 - ys / h)
    alpha = inside.astype(float).reshape(77, k, 116, k).mean(axis=(1, 3))
    image = np.zeros(alpha.shape + (4,), np.uint8)
    image[..., :3] = 255
    image[..., 3] = np.round(alpha * 255).astype(np.uint8)
    return Image.fromarray(image, "RGBA")


def ticket():
    """A ticket, 3 wide to 2 tall: rounded corners, a round bite out of each end and a dashed tear line cut through it
    a third of the way in, so it reads as a ticket at the top bar's 24 px. Supersampled 4x."""
    k = 4
    w, h = 116, 78
    ys, xs = np.mgrid[0 : h * k, 0 : w * k].astype(float) / k + 0.5 / k
    corner, bite = 9.0, 13.0
    # Inside the rounded rectangle: the distance past the corner's inset box.
    dx = np.maximum(np.abs(xs - w / 2) - (w / 2 - corner), 0)
    dy = np.maximum(np.abs(ys - h / 2) - (h / 2 - corner), 0)
    inside = dx * dx + dy * dy <= corner * corner
    for cx in (0.0, float(w)):
        inside &= (xs - cx) ** 2 + (ys - h / 2) ** 2 > bite * bite
    # The tear line: four whole dashes down the stub's edge, centred, clear of the rim.
    tear, dash, gap, width, count = w * 0.34, 9.0, 6.0, 5.0, 4
    top = (h - (count * dash + (count - 1) * gap)) / 2
    along = (ys - top) % (dash + gap)
    inside &= ~((np.abs(xs - tear) <= width / 2) & (along <= dash) & (ys >= top) & (ys <= h - top))
    alpha = inside.astype(float).reshape(h, k, w, k).mean(axis=(1, 3))
    image = np.zeros(alpha.shape + (4,), np.uint8)
    image[..., :3] = 255
    image[..., 3] = np.round(alpha * 255).astype(np.uint8)
    return Image.fromarray(image, "RGBA")


DRAWN = {"Pointer": pointer, "Ticket": ticket}


def main():
    os.makedirs(OUT, exist_ok=True)
    per_page = COLUMNS * PAGE_ROWS
    pages = (len(ICONS) + per_page - 1) // per_page
    rows = min((len(ICONS) + COLUMNS - 1) // COLUMNS, PAGE_ROWS)
    atlas = Image.new("RGBA", (CELL * COLUMNS * pages, CELL * rows), (255, 255, 255, 0))
    cells = {}
    for index, (name, spec) in enumerate(ICONS.items()):
        glyph = DRAWN[name]() if spec is None else cut(*spec)
        fit = (CELL - 2 * PAD) / max(glyph.size)
        glyph = glyph.resize((round(glyph.size[0] * fit), round(glyph.size[1] * fit)), Image.LANCZOS)
        page, within = divmod(index, per_page)
        column, row = page * COLUMNS + within % COLUMNS, within // COLUMNS
        x = column * CELL + (CELL - glyph.size[0]) // 2
        y = row * CELL + (CELL - glyph.size[1]) // 2
        atlas.alpha_composite(glyph, (x, y))
        cells[name] = {"x": column * CELL, "y": row * CELL, "size": CELL}
    atlas.alpha_composite(floor(), FLOOR_AT)
    atlas.save(os.path.join(OUT, "Icons.png"))
    with open(os.path.join(OUT, "Icons.json"), "w") as f:
        json.dump(cells, f, indent=1)
    print(f"[ICONS] {len(cells)} icons -> Assets/ui/hud/Icons.png")


def floor():
    """An ellipse's ring and faint fill, supersampled 4x so the ring is even all the way round."""
    k = 4
    w, h = FLOOR_SIZE[0] * k, FLOOR_SIZE[1] * k
    ys, xs = np.mgrid[0:h, 0:w].astype(float) + 0.5
    a, b = w / 2, h / 2
    # Distance to the ellipse's edge, near enough for a thin ring: the implicit value over its gradient.
    nx, ny = (xs - a) / a, (ys - b) / b
    value = np.sqrt(nx * nx + ny * ny) - 1
    gradient = np.sqrt((nx / a) ** 2 + (ny / b) ** 2) / np.maximum(np.sqrt(nx * nx + ny * ny), 1e-6)
    distance = value / gradient
    half = FLOOR_LINE * k / 2
    ring = (np.abs(distance + half) <= half).astype(float)
    fill = (distance < 0).astype(float) * FLOOR_FILL
    alpha = np.maximum(ring, fill)
    alpha = alpha.reshape(FLOOR_SIZE[1], k, FLOOR_SIZE[0], k).mean(axis=(1, 3))
    image = np.zeros(alpha.shape + (4,), np.uint8)
    image[..., :3] = 255
    image[..., 3] = np.round(alpha * 255).astype(np.uint8)
    return Image.fromarray(image, "RGBA")


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
