#!/usr/bin/env python3
"""Measures how each gun lies on the back off ror's part-id renders of tools/ree/BackGunFits.luau, and writes
src/Lobby/Client/Utils/backGunFits.luau. Run by backgunfits.sh; it exits 0 once every gun's correction is under
TOLERANCE_DEG (its last write is then the measure of the axes it was rendered with), 3 when another pass is wanted.
    python3 tools/ree/backgunfits.py <prints log> <render dir> <fov deg> <distance studs> <size px>

From above (Top) the silhouette's long axis is where the barrel really runs: some models are built at a lean inside
their own part box. Down the barrel (Barrel) its tall axis is the gun's top. Side on (Side) is what is seen from
behind once it is on the back: its outline, kept as the extreme points in OUTLINE_DIRECTIONS directions. Near is the
lowest it reaches along its side, from Top and Barrel."""
import json
import math
import os
import re
import sys

from PIL import Image

OUT = "src/Lobby/Client/Utils/backGunFits.luau"
TOLERANCE_DEG = 0.3
# Down the barrel a round gun (a gatling) has no top to find: its roll is left alone unless the tall axis is this much
# longer than the wide one.
ROLL_RATIO = 1.5
# Roll is applied at this share a pass: on a gun turned in its own plane by its data (the RPG's PitchDeg) the barrel
# view's tall axis moves with the roll, and a whole correction swings past it each pass.
ROLL_DAMPING = 0.5
OUTLINE_DIRECTIONS = 32
VIEWS = 3

prints_path, render_dir, fov, distance, size = sys.argv[1:6]
fov, distance, size = float(fov), float(distance), int(size)
studs_per_px = 2 * distance * math.tan(math.radians(fov) / 2) / size

text = open(prints_path).read()
axes = {}
for index, name, barrel, top in re.findall(r"AXES (\d+)\|([^|]+)\|([-\d.e,]+)\|([-\d.e,]+)", text):
    axes[int(index)] = (name, [float(v) for v in barrel.split(",")], [float(v) for v in top.split(",")])

parts = json.load(open(os.path.join(render_dir, "parts.json")))
parts = parts["parts"] if isinstance(parts, dict) else parts
owner = []
for part in parts:
    match = re.search(r"Fit(\d+)_(\d+)", part["path"])
    owner.append((int(match.group(1)), int(match.group(2))) if match else None)


def points_of(index, view):
    """The copy's pixels as (screen x, screen y) in studs from its Handle, +x right and +y up."""
    camera = (index - 1) * VIEWS + view
    image = Image.open(os.path.join(render_dir, f"camera{camera}.ids.png")).convert("RGB")
    width, height = image.size
    pixels = image.load()
    found = []
    for v in range(height):
        for u in range(width):
            r, g, b = pixels[u, v]
            part = r + (g << 8) + (b << 16) - 1
            if part >= 0 and owner[part] == (index, view):
                found.append(((u + 0.5 - width / 2) * studs_per_px, (height / 2 - v - 0.5) * studs_per_px))
    return found


def major(points):
    """The long axis of a cloud of points, and how much longer it is than the short one."""
    n = len(points)
    mx = sum(p[0] for p in points) / n
    my = sum(p[1] for p in points) / n
    sxx = sum((p[0] - mx) ** 2 for p in points) / n
    syy = sum((p[1] - my) ** 2 for p in points) / n
    sxy = sum((p[0] - mx) * (p[1] - my) for p in points) / n
    angle = 0.5 * math.atan2(2 * sxy, sxx - syy)
    spread = math.hypot((sxx - syy) / 2, sxy)
    long, short = (sxx + syy) / 2 + spread, (sxx + syy) / 2 - spread
    return (math.cos(angle), math.sin(angle)), math.sqrt(long / max(short, 1e-9))


def cross(a, b):
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]


def unit(a):
    length = math.sqrt(sum(c * c for c in a))
    return [c / length for c in a]


def into(columns, local):
    """`local` (in the Handle's axes) in FindAxes's frame, the Handle's axes being `columns` there."""
    return [sum(columns[k][i] * local[k] for k in range(3)) for i in range(3)]


worst = 0.0
fits = []
for index in sorted(axes):
    name, barrel, top = axes[index]
    side = cross(barrel, top)
    side_on = points_of(index, 1)
    from_top = points_of(index, 2)
    down_barrel = points_of(index, 3)
    if not side_on or not from_top or not down_barrel:
        print(f"{name}: not drawn, skipped", file=sys.stderr)
        continue

    # From above the screen is (Handle X, -Handle Z); down the barrel it is (-Handle Z, Handle Y).
    (ax, az), _ = major([(x, -y) for x, y in from_top])
    if ax < 0:
        ax, az = -ax, -az
    lean = math.degrees(math.atan2(az, ax))
    (rz, ry), ratio = major([(-x, y) for x, y in down_barrel])
    if ry < 0:
        rz, ry = -rz, -ry
    roll = math.degrees(math.atan2(rz, ry)) * ROLL_DAMPING if ratio >= ROLL_RATIO else 0.0
    worst = max(worst, abs(lean), abs(roll))

    columns = [barrel, top, side]
    new_barrel = unit([ax, 0.0, az])
    new_top_guess = [0.0, math.cos(math.radians(roll)), math.sin(math.radians(roll))]
    new_side = unit(cross(new_barrel, new_top_guess))
    new_top = cross(new_side, new_barrel)
    near = min(min(-y for _, y in from_top), min(-x for x, _ in down_barrel))
    outline = []
    for k in range(OUTLINE_DIRECTIONS):
        theta = 2 * math.pi * k / OUTLINE_DIRECTIONS
        d = (math.cos(theta), math.sin(theta))
        point = max(side_on, key=lambda p: p[0] * d[0] + p[1] * d[1])
        if point not in outline:
            outline.append(point)
    fits.append((name, into(columns, new_barrel), into(columns, new_top), outline, near, lean, roll))
    print(f"{name}: lean {lean:+.2f} roll {roll:+.2f} (ratio {ratio:.2f}) near {near:.3f} outline {len(outline)}")


def vector3(v):
    return f"Vector3.new({v[0]:.5f}, {v[1]:.5f}, {v[2]:.5f})"


lines = [
    "-- Generated by tools/ree/backgunfits.sh: do not edit by hand. Rerun it after changing a gun's model or Length.",
    "-- How each gun lies on the back (backGunModel), by gun Name, measured off renders of its real meshes: its Handle's",
    "-- Barrel (X) and Top (Y) in GunsCore.FindAxes's frame; its Outline seen side on (points in the Handle's X and Y,",
    "-- studs); and its Near side (the lowest it reaches along the Handle's Z).",
    "export type TBackGunFit = {",
    "\tBarrel: Vector3,",
    "\tTop: Vector3,",
    "\tOutline: { Vector2 },",
    "\tNear: number,",
    "}",
    "",
    "local backGunFits: { [string]: TBackGunFit } = {",
]
for name, barrel, top, outline, near, _, _ in fits:
    points = ", ".join(f"Vector2.new({x:.3f}, {y:.3f})" for x, y in outline)
    lines += [
        f'\t["{name}"] = {{',
        f"\t\tBarrel = {vector3(barrel)},",
        f"\t\tTop = {vector3(top)},",
        f"\t\tOutline = {{ {points} }},",
        f"\t\tNear = {near:.3f},",
        "\t},",
    ]
lines += ["}", "", "return table.freeze(backGunFits)", ""]
open(OUT, "w").write("\n".join(lines))
print(f"worst correction {worst:.2f} deg")
sys.exit(0 if worst < TOLERANCE_DEG else 3)
