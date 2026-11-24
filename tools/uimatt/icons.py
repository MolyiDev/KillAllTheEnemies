"""Cuts the In-Game HUD's and the Lobby HUD's icons out of the designer's art into one white atlas, tinted where it is drawn, and draws the
streaks his panel faces carry into a texture laid over every panel.

    python3 tools/uimatt/icons.py                          # write both
    python3 tools/uimatt/icons.py --upload Icons           # and upload one (or both) as group 34796361
    python3 tools/uimatt/icons.py --upload PanelTexture
    python3 tools/uimatt/icons.py --upload Showcase


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

The showcase atlas (Showcase.png, showcase()) is the art behind a thing on show (GlobalClient/UI/Showcase): white on
transparent, tinted where it is drawn. Its cells are listed in Icons.luau's ShowcaseCells.

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
    "Showcase": ("Showcase.png", "SHOWCASE"),
    "ShowcaseFloor": ("ShowcaseFloor.png", "SHOWCASE_FLOOR"),
}
# The floors under a thing on show, each an ellipse at the stages' floor shape (his 470 x 84) seen in perspective, as
# Icons.luau's ShowcaseFloorCells has them. Drawn about twice the size they are shown at, so their lines are twice
# the px they land at.
SHOWCASE_FLOOR_CELLS = {
    "Pad": (0, 0, 1024, 184),
    "Dots": (0, 192, 1024, 184),
    "Reticle": (0, 384, 1024, 184),
    "Ring": (0, 576, 1024, 184),
    "Glow": (0, 768, 1024, 184),
}
FLOOR_DOTS_PITCH = 30.0
# The showcase atlas: each drawing's cell (x, y, w, h), as Icons.luau's ShowcaseCells has them. Supersampled SHOWCASE_SS
# times each way.
SHOWCASE_CELLS = {
    "Rays": (0, 0, 512, 512),
    "Dots": (512, 0, 512, 512),
    "Reticle": (0, 512, 512, 512),
    "Glow": (512, 512, 256, 256),
    "Pulse": (512, 768, 256, 256),
    "Beam": (768, 512, 256, 512),
}
SHOWCASE_SS = 4
RAYS = 16
DOTS_PITCH = 17.0


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


def supersampled(w, h):
    """Pixel centres of a w x h cell at SHOWCASE_SS samples a side, in the cell's own px."""
    k = SHOWCASE_SS
    ys, xs = np.mgrid[0 : h * k, 0 : w * k].astype(float) + 0.5
    return xs / k, ys / k


def averaged(a, w, h):
    k = SHOWCASE_SS
    return a.reshape(h, k, w, k).mean(axis=(1, 3))


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def rays(size):
    """RAYS wedges, each half its pitch, with a 1 px soft side; dark in the very middle, fading out to the rim."""
    xs, ys = supersampled(size, size)
    c = size / 2
    dx, dy = xs - c, ys - c
    r = np.sqrt(dx * dx + dy * dy) / c
    pitch = 2 * np.pi / RAYS
    phase = np.mod(np.arctan2(dy, dx), pitch) / pitch
    soft = 1.0 / np.maximum(r * c * pitch, 1e-3)
    wedge = smoothstep(-soft, soft, np.minimum(phase, 0.5 - phase))
    radial = smoothstep(0.0, 0.22, r) * np.clip(1 - r, 0, 1) ** 1.6
    return averaged(wedge * radial, size, size)


def dots(size):
    """A halftone disc: a hex lattice of dots, each as big as its distance from the middle allows."""
    xs, ys = supersampled(size, size)
    c = size / 2
    pitch = DOTS_PITCH
    row = np.floor(ys / (pitch * 0.866))
    best = np.full(xs.shape, 1e9)
    bx, by = np.zeros(xs.shape), np.zeros(xs.shape)
    for drow in (-1, 0, 1):
        rr = row + drow
        cy = (rr + 0.5) * pitch * 0.866
        off = 0.5 * (rr % 2)
        base = np.floor(xs / pitch - off)
        for dcol in (-1, 0, 1):
            cx = (base + dcol + 0.5 + off) * pitch
            d = (xs - cx) ** 2 + (ys - cy) ** 2
            nearer = d < best
            best, bx, by = np.where(nearer, d, best), np.where(nearer, cx, bx), np.where(nearer, cy, by)
    grow = np.clip(1 - np.sqrt((bx - c) ** 2 + (by - c) ** 2) / c, 0, 1) ** 0.9
    radius = pitch * 0.46 * grow
    return averaged(smoothstep(radius + 0.6, radius - 0.6, np.sqrt(best)) * (radius > 0.5), size, size)


def reticle(size):
    """A sight: broken arcs round the rim, a ring of ticks inside it (every sixth long), a faint thin circle within."""
    xs, ys = supersampled(size, size)
    c = size / 2
    dx, dy = xs - c, ys - c
    rpx = np.sqrt(dx * dx + dy * dy)
    deg = np.degrees(np.arctan2(dy, dx)) % 360
    rim, line = c - 4, 3.2
    on = np.zeros(xs.shape)
    for start, length in [(0, 70), (80, 8), (96, 64), (172, 6), (186, 82), (276, 10), (294, 56)]:
        on = np.maximum(on, ((deg - start) % 360 < length).astype(float))
    out = smoothstep(line / 2 + 0.7, line / 2 - 0.7, np.abs(rpx - rim)) * on
    ticks_at, pitch = rim * 0.89, 360 / 72
    within = deg % pitch
    across = np.minimum(within, pitch - within) * np.pi / 180 * rpx
    length = np.where(np.floor(deg / pitch).astype(int) % 6 == 0, 14, 6)
    ticks = smoothstep(1.5, 0.3, across) * ((rpx < ticks_at) & (rpx > ticks_at - length))
    out = np.maximum(out, ticks)
    out = np.maximum(out, 0.6 * smoothstep(1.6, 0.4, np.abs(rpx - rim * 0.74)))
    return averaged(out, size, size)


def soft_glow(size):
    xs, ys = supersampled(size, size)
    c = size / 2
    r = np.sqrt((xs - c) ** 2 + (ys - c) ** 2) / c
    return averaged(np.clip(1 - r, 0, 1) ** 2.2, size, size)


def pulse(size):
    """A soft ring, its brightest at 0.86 of the radius."""
    xs, ys = supersampled(size, size)
    c = size / 2
    r = np.sqrt((xs - c) ** 2 + (ys - c) ** 2) / c
    return averaged(np.exp(-(((r - 0.86) / 0.07) ** 2)) * smoothstep(1.0, 0.97, r), size, size)


def beam(w, h):
    """A spotlight's cone from a narrow top to the full width at the bottom, brighter as it falls, with soft shafts."""
    xs, ys = supersampled(w, h)
    y = ys / h
    half = (0.16 + 0.84 * y) * (w / 2) - 2
    u = (xs - w / 2) / half
    across = np.clip(1 - np.abs(u), 0, 1) ** 0.8
    shafts = 0.82 + 0.12 * np.sin(u * 9.0 + 0.7) + 0.06 * np.sin(u * 23.0)
    along = smoothstep(0.0, 0.35, y) * (0.5 + 0.5 * y) * smoothstep(1.0, 0.92, y)
    return averaged(across * along * np.clip(shafts, 0, 1), w, h)


def showcase():
    drawings = {"Rays": rays, "Dots": dots, "Reticle": reticle, "Glow": soft_glow, "Pulse": pulse}
    alpha = np.zeros((1024, 1024))
    for name, (x, y, w, h) in SHOWCASE_CELLS.items():
        alpha[y : y + h, x : x + w] = beam(w, h) if name == "Beam" else drawings[name](w)
    image = np.zeros((1024, 1024, 4), np.uint8)
    image[..., :3] = 255
    image[..., 3] = np.round(np.clip(alpha, 0, 1) * 255).astype(np.uint8)
    Image.fromarray(image, "RGBA").save(os.path.join(OUT, "Showcase.png"))
    print("[ICONS] showcase -> Assets/ui/hud/Showcase.png")


def floor_space(w, h):
    """An ellipse filling a w x h cell, seen as a floor: per sample its normalised radius, the screen px per unit of
    that radius (so a rim is the same px thick all round), and the ground plane's own coordinates (u, v), square."""
    xs, ys = supersampled(w, h)
    a, b = w / 2 - 2, h / 2 - 2
    dx, dy = xs - w / 2, ys - h / 2
    nx, ny = dx / a, dy / b
    r = np.sqrt(nx * nx + ny * ny)
    gradient = np.sqrt((nx / a) ** 2 + (ny / b) ** 2) / np.maximum(r, 1e-6)
    return r, 1 / np.maximum(gradient, 1e-9), dx, dy * a / b, a, b


def rim_at(r, px_per_unit, radius, line):
    """A line `line` px thick on the ellipse at `radius`, even all round."""
    distance = np.abs(r - radius) * px_per_unit
    return smoothstep(line / 2 + 0.7, line / 2 - 0.7, distance)


def floor_pad(w, h):
    """A lit pad: a bright rim, a fainter one inside it, a fill brightest in the middle."""
    r, px, _, _, _, _ = floor_space(w, h)
    out = np.maximum(rim_at(r, px, 0.985, 5.5), 0.45 * rim_at(r, px, 0.8, 3.5))
    out = np.maximum(out, 0.32 * np.clip(1 - r * r, 0, 1) * (r < 1))
    return averaged(out, w, h)


def floor_dots(w, h):
    """The halftone disc laid flat: a hex lattice on the ground, each dot as big as its distance from the middle
    allows, squashed by the floor's perspective."""
    r, _, u, v, a, b = floor_space(w, h)
    pitch = FLOOR_DOTS_PITCH
    row = np.floor(v / (pitch * 0.866))
    best = np.full(u.shape, 1e9)
    bu, bv = np.zeros(u.shape), np.zeros(u.shape)
    for drow in (-1, 0, 1):
        rr = row + drow
        cv = (rr + 0.5) * pitch * 0.866
        off = 0.5 * (rr % 2)
        base = np.floor(u / pitch - off)
        for dcol in (-1, 0, 1):
            cu = (base + dcol + 0.5 + off) * pitch
            d = (u - cu) ** 2 + (v - cv) ** 2
            nearer = d < best
            best, bu, bv = np.where(nearer, d, best), np.where(nearer, cu, bu), np.where(nearer, cv, bv)
    grow = np.clip(1 - np.sqrt(bu * bu + bv * bv) / a, 0, 1) ** 0.8
    radius = pitch * 0.45 * grow
    du, dv = u - bu, v - bv
    reach = np.sqrt(best)
    # The edge's distance on screen: the ground's v is squashed by b / a.
    squash = np.sqrt(du * du + (dv * b / a) ** 2) / np.maximum(reach, 1e-6)
    distance = (reach - radius) * squash
    return averaged(smoothstep(0.6, -0.6, distance) * (radius > 1), w, h)


def floor_reticle(w, h):
    """The sight laid flat: broken arcs round the rim, a ring of ticks inside it (every sixth long), a thin circle."""
    r, px, u, v, a, _ = floor_space(w, h)
    deg = np.degrees(np.arctan2(v, u)) % 360
    on = np.zeros(r.shape)
    for start, length in [(0, 70), (80, 8), (96, 64), (172, 6), (186, 82), (276, 10), (294, 56)]:
        on = np.maximum(on, ((deg - start) % 360 < length).astype(float))
    out = rim_at(r, px, 0.985, 5.5) * on
    pitch = 360 / 72
    within = deg % pitch
    across = np.minimum(within, pitch - within) * np.pi / 180 * r * a
    long = np.floor(deg / pitch).astype(int) % 6 == 0
    inner = np.where(long, 0.8, 0.85)
    ticks = smoothstep(2.8, 1.6, across) * ((r < 0.9) & (r > inner))
    out = np.maximum(out, ticks)
    out = np.maximum(out, 0.55 * rim_at(r, px, 0.66, 3.0))
    return averaged(out, w, h)


def floor_ring(w, h):
    """One thin ring on the floor's edge, for ripples."""
    r, px, _, _, _, _ = floor_space(w, h)
    return averaged(rim_at(r, px, 0.97, 6.5), w, h)


def floor_glow(w, h):
    r, _, _, _, _, _ = floor_space(w, h)
    return averaged(np.clip(1 - r, 0, 1) ** 1.8, w, h)


def showcase_floor():
    drawings = {
        "Pad": floor_pad,
        "Dots": floor_dots,
        "Reticle": floor_reticle,
        "Ring": floor_ring,
        "Glow": floor_glow,
    }
    alpha = np.zeros((1024, 1024))
    for name, (x, y, w, h) in SHOWCASE_FLOOR_CELLS.items():
        alpha[y : y + h, x : x + w] = drawings[name](w, h)
    image = np.zeros((1024, 1024, 4), np.uint8)
    image[..., :3] = 255
    image[..., 3] = np.round(np.clip(alpha, 0, 1) * 255).astype(np.uint8)
    Image.fromarray(image, "RGBA").save(os.path.join(OUT, "ShowcaseFloor.png"))
    print("[ICONS] showcase floor -> Assets/ui/hud/ShowcaseFloor.png")


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
    showcase()
    showcase_floor()
    if "--upload" in sys.argv:
        for name in sys.argv[sys.argv.index("--upload") + 1 :]:
            upload(name)
