# The lobby's shooting range (Workspace.Lobby.Map.Range.Hall and .Door), generated: a porch on the plaza's axis, a
# corridor in and a hall centred on it, in the plaza's own look (its stud texture and greys, its blue, green and
# cream neon) and decorated only as the PLAY hall is, with lines of neon: the guns being tried are the point.
# Range.Targets (the dummies) and Range.Front (the SHOP's portico, banners, lamps and planters lifted in front of the
# porch, with the label: tools/lobby/range_front.luau) are not built here, and RangeCore's numbers (origin, booths,
# bounds) are the contract this keeps.
#
#   python3 tools/lobby/range.py out.json        writes the parts and prints the checks; every count must be 0
#
# The JSON is a flat list ({n, c, p (index of the parent, 0 = Range), cf, s, properties...}); range_push.py puts it
# in Studio, Maps.md section 8 says how it is rendered first.
import json
import sys

STUD = "rbxassetid://7447638591"  # the plaza's stud, one stud a tile
HAZARD = "rbxassetid://140440236264071"  # 128 x 32 black and yellow stripes

# The plaza's palette (measured off Workspace.Lobby.Map); yellow is the range's one accent.
WALL = "#4b4c56"
WALL_DARK = "#3e4048"
PILLAR = "#5b5d69"
TRIM = "#63667a"
CEILING = "#2e3034"
BLUE = "#5978ce"
GREEN = "#6db665"
BLACK = "#1a1a1c"
YELLOW = "#f5ba1c"

# The plaza is down -X, the targets up +X; AXIS is the plaza's own (the SHOP and LEADERBOARDS mirror about it).
# Interior faces.
AXIS = -13.0
FLOOR_Y = 0.0
PLAZA_EDGE = 22.0  # the plaza floor (top 0.9) runs into the corridor this far
CEIL_Y = 26.0
FRONT_X = -5.0  # the corridor's wall toward the plaza, inside
# The corridor is as wide as the gap allows: the building to its south has its face at z = -21.18.
ENT_S, ENT_N = AXIS - 8.0, AXIS + 8.0
HALL_W = 32.0  # where the corridor opens into the hall: just past the building south of it (x = 30.11)
HALL_E = 200.0
HALL_S, HALL_N = AXIS - 45.0, AXIS + 45.0
DOOR_S, DOOR_N = ENT_S + 0.3, ENT_N - 0.3
DOOR_TOP = 17.0
COUNTER_X = 55.2
PILASTERS = (80.0, 120.0, 160.0)
# The porch behind the lifted portico (range_front.luau stands the portico's face at PORCH_X, as far from the
# plaza's ring as the SHOP's is): the SHOP's body, 70 wide and 34.9 high, cut to the depth there is here.
PORCH_X = -23.0
PORCH_BACK = PORCH_X + 3.8  # the portico's back
PORCH_HALF = 35.0
PORCH_ROOM = 24.0  # half the room's width
PORCH_CEIL = 17.1
PORCH_TOP = 34.9
CREAM = "#b0ae92"

entries = []
boxes = []  # (name, lo, hi, drawn) for the checks


def rgb(code):
    return [round(int(code[i : i + 2], 16) / 255, 4) for i in (1, 3, 5)]


def add(entry, parent):
    entry["p"] = parent
    entries.append(entry)
    return len(entries)


def group(name, parent=0, kind="Folder"):
    return add({"n": name, "c": kind}, parent)


# An axis-aligned box from its corners. `stud` names the faces that wear the stud; `solid` collides and stops shots.
def box(name, parent, lo, hi, color, stud="", tile=2, solid=False, material="SmoothPlastic"):
    size = [round(hi[i] - lo[i], 4) for i in range(3)]
    assert min(size) > 0, name
    centre = [round((lo[i] + hi[i]) / 2, 4) for i in range(3)]
    entry = {
        "n": name, "c": "Part", "cf": centre + [1, 0, 0, 0, 1, 0, 0, 0, 1], "s": size, "Color": rgb(color),
        "Material": material, "Anchored": True, "CanCollide": solid, "CanQuery": solid, "CanTouch": False,
        "CastShadow": solid,
    }
    owner = add(entry, parent)
    boxes.append((name, tuple(lo), tuple(hi), True))
    for face in stud.split():
        add({"n": "Stud", "c": "Texture", "Texture": STUD, "Face": face, "StudsPerTileU": tile, "StudsPerTileV": tile}, owner)
    return owner


def neon(name, parent, lo, hi, color):
    return box(name, parent, lo, hi, color, material="Neon")


def build():
    hall = group("Hall", 0, "Model")
    door = group("Door", 0, "Model")

    # --- The shell: floors, walls, roof. Every interior face is on its nominal plane; trim stands proud of it.
    shell = group("Shell", hall)
    box("EntranceFloor", shell, (PLAZA_EDGE, -1, ENT_S - 0.5), (HALL_W, FLOOR_Y, ENT_N + 0.5), TRIM, "Top", solid=True)
    box("StandFloor", shell, (HALL_W, -1, HALL_S - 0.5), (COUNTER_X, FLOOR_Y, HALL_N + 0.5), TRIM, "Top", solid=True)
    box("LaneFloor", shell, (COUNTER_X, -1, HALL_S - 0.5), (HALL_E + 0.5, FLOOR_Y, HALL_N + 0.5), WALL_DARK, "Top", solid=True)
    box("NorthWall", shell, (HALL_W - 1, -1.6, HALL_N), (HALL_E + 2, CEIL_Y + 1, HALL_N + 2), WALL, "Front", solid=True)
    box("SouthWall", shell, (HALL_W - 1, -1.6, HALL_S - 2), (HALL_E + 2, CEIL_Y + 1, HALL_S), WALL, "Back", solid=True)
    box("EndWall", shell, (HALL_E, -1.6, HALL_S), (HALL_E + 2, CEIL_Y + 1, HALL_N), WALL, "Left", solid=True)
    box("WestWallSouth", shell, (HALL_W - 2, -1.6, HALL_S), (HALL_W, CEIL_Y + 1, ENT_S - 2), WALL, "Right", solid=True)
    box("WestWallNorth", shell, (HALL_W - 2, -1.6, ENT_N), (HALL_W, CEIL_Y + 1, HALL_N), WALL, "Right Front", solid=True)
    box("EntranceSouth", shell, (FRONT_X, -1.6, ENT_S - 2), (HALL_W, CEIL_Y + 1, ENT_S), WALL, "Back", solid=True)
    # North of the corridor the old entrance's room is filled solid, up to the next building (its face at 28.76).
    box("EntranceNorth", shell, (FRONT_X, -1.6, ENT_N), (HALL_W - 2, CEIL_Y + 1, 28.9), WALL, "Front", solid=True)
    # The front stands 0.34 proud of the buildings each side of it (theirs are at x = -6.96).
    box("FrontNorth", shell, (-7.3, -1.6, DOOR_N + 0.3), (FRONT_X, CEIL_Y + 1, 29.1), WALL, "Left", solid=True)
    box("FrontLintel", shell, (-7.3, DOOR_TOP + 0.3, DOOR_S - 0.3), (FRONT_X, CEIL_Y + 1, DOOR_N + 0.3), WALL, "Left Right", solid=True)
    box("HallRoof", shell, (HALL_W - 1.2, CEIL_Y, HALL_S - 2.2), (HALL_E + 2.2, CEIL_Y + 1.4, HALL_N + 2.2), CEILING, "Bottom", solid=True)
    box("EntranceRoof", shell, (FRONT_X, CEIL_Y, ENT_S - 2.2), (HALL_W - 1.2, CEIL_Y + 1.4, ENT_N + 0.2), CEILING, "Bottom", solid=True)
    # The building over the entrance, as the plaza sees it.
    box("Mass", shell, (-7.3, CEIL_Y + 1, -21.9), (44.3, 66, 29.4), WALL, "Left", solid=True)

    # --- The door in the porch's back wall: two pylons and a header, a green strip up each pylon as on the SHOP's.
    facade = group("Facade", hall)
    for name, z0, z1 in (("PylonSouth", DOOR_S - 3.5, DOOR_S), ("PylonNorth", DOOR_N, DOOR_N + 3.5)):
        box(name, door, (-9.3, 0.2, z0), (-4.6, PORCH_CEIL + 0.3, z1), PILLAR, "Left Right Front Back", solid=True)
        middle = (z0 + z1) / 2
        neon(name + "Light", facade, (-9.48, 3.0, middle - 0.3), (-9.3, 15.0, middle + 0.3), GREEN)
    box("Header", door, (-9.7, DOOR_TOP - 2.0, DOOR_S - 3.9), (-4.4, PORCH_CEIL + 0.4, DOOR_N + 3.9), WALL_DARK, "Left Right Bottom", solid=True)
    neon("BandHigh", facade, (-7.48, 58.6, -18.0), (-7.3, 60.0, 25.5), BLUE)

    # --- The porch: side masses, a roof and a dark floor between the portico and the range's front.
    porch = group("Porch", hall)
    for name, z0, z1, inner in (("South", AXIS - PORCH_HALF, AXIS - PORCH_ROOM, "Back"), ("North", AXIS + PORCH_ROOM, AXIS + PORCH_HALF, "Front")):
        outer = "Front" if inner == "Back" else "Back"
        box("Side" + name, porch, (PORCH_BACK, 0.2, z0), (-7.1, PORCH_CEIL, z1), PILLAR, f"Left {inner} {outer}", solid=True)
        middle = z0 if inner == "Back" else z1
        strip = (middle - 0.15, middle) if inner == "Back" else (middle, middle + 0.15)
        neon("SideLight" + name, porch, (-14.0, 2.5, strip[0]), (-13.2, 15.0, strip[1]), CREAM)
    box("Roof", porch, (PORCH_BACK, PORCH_CEIL, AXIS - PORCH_HALF), (-7.1, PORCH_TOP, AXIS + PORCH_HALF), PILLAR, "Left Bottom Top Front Back", solid=True)
    # Thin: the plaza's arrow strip to the door is drawn 0.09 over the plaza floor and must stay above this.
    box("Floor", porch, (PORCH_BACK, 0.9, AXIS - PORCH_ROOM - 0.2), (-7.2, 0.96, AXIS + PORCH_ROOM + 0.2), WALL_DARK, "Top", solid=True)

    # --- The corridor: the plaza's floor steps down to the range's; a line of neon each side, overhead and along
    # the floor's edges, which carry on into the hall and turn along the counter (as the PLAY hall's floor is drawn).
    entrance = group("Entrance", hall)
    box("StepHigh", entrance, (PLAZA_EDGE, 0, ENT_S - 0.4), (PLAZA_EDGE + 1.6, 0.6, ENT_N + 0.4), PILLAR, "Top Right", tile=1, solid=True)
    box("StepLow", entrance, (PLAZA_EDGE + 1.6, 0, ENT_S - 0.4), (PLAZA_EDGE + 3.2, 0.3, ENT_N + 0.4), PILLAR, "Top Right", tile=1, solid=True)
    neon("NeonSouth", entrance, (FRONT_X + 0.5, 14.6, ENT_S - 0.2), (HALL_W - 0.5, 15.2, ENT_S + 0.15), BLUE)
    neon("NeonNorth", entrance, (FRONT_X + 0.5, 14.6, ENT_N - 0.15), (HALL_W - 0.5, 15.2, ENT_N + 0.2), BLUE)
    neon("CeilingStrip", entrance, (FRONT_X + 2, CEIL_Y - 0.2, AXIS - 0.6), (HALL_W - 2, CEIL_Y + 0.2, AXIS + 0.6), BLUE)
    turn = COUNTER_X - 5.0
    for name, side in (("South", -1), ("North", 1)):
        edge = AXIS + side * 6.6
        z0, z1 = min(edge, edge + side * 0.6), max(edge, edge + side * 0.6)
        neon("FloorLine" + name, entrance, (PLAZA_EDGE + 3.6, 0, z0), (turn, 0.1, z1), GREEN)
        far = AXIS + side * 41.0
        neon("FloorTurn" + name, entrance, (turn - 0.6, 0, min(z0 if side < 0 else z1, far)), (turn, 0.08, max(z0 if side < 0 else z1, far)), GREEN)

    # --- The firing line: a counter, striped toward the shooter.
    line = group("Line", hall)
    box("Counter", line, (COUNTER_X, 0, HALL_S - 0.2), (COUNTER_X + 2.2, 2.2, HALL_N + 0.2), PILLAR, "Left Right", solid=True)
    box("CounterTop", line, (COUNTER_X - 0.3, 2.2, HALL_S - 0.2), (COUNTER_X + 2.5, 2.6, HALL_N + 0.2), BLACK, solid=True)
    stripes = box("CounterStripes", line, (COUNTER_X - 0.14, 0.5, HALL_S - 0.1), (COUNTER_X, 1.7, HALL_N + 0.1), YELLOW)
    add({"n": "Stripes", "c": "Texture", "Texture": HAZARD, "Face": "Left", "StudsPerTileU": 4.8, "StudsPerTileV": 1.2}, stripes)

    # --- The hall: three pilasters a side under a truss, one line of neon round the walls, three along the ceiling.
    walls = group("Walls", hall)
    for name, z, into in (("South", HALL_S, 1), ("North", HALL_N, -1)):
        face = "Back" if into > 0 else "Front"
        # The buildings each side of the corridor reach into the hall's west corners (the north one to x = 35.61):
        # a pier in each corner takes them in.
        box("CornerPier" + name, walls, (HALL_W - 0.3, 0, min(z - 0.3 * into, z + 3.6 * into)), (HALL_W + 4.0, CEIL_Y + 0.2, max(z - 0.3 * into, z + 3.6 * into)), PILLAR, f"Right {face}", solid=True)
        neon("Neon" + name, walls, (HALL_W + 0.5, 14.6, min(z - 0.3 * into, z + 0.15 * into)), (HALL_E - 0.15, 15.2, max(z - 0.3 * into, z + 0.15 * into)), BLUE)
        for x in PILASTERS:
            box("Pilaster" + name, walls, (x - 1.5, 0, min(z - 0.3 * into, z + 1.6 * into)), (x + 1.5, CEIL_Y + 0.2, max(z - 0.3 * into, z + 1.6 * into)), PILLAR, f"Left Right {face}", solid=True)
            neon("PilasterLight" + name, walls, (x - 0.3, 3.0, min(z + 1.6 * into, z + 1.75 * into)), (x + 0.3, 13.0, max(z + 1.6 * into, z + 1.75 * into)), CREAM)
    for x in PILASTERS:
        box("Truss", walls, (x - 0.9, 24.0, HALL_S - 0.2), (x + 0.9, CEIL_Y + 0.2, HALL_N + 0.2), CEILING, "Left Right Bottom", tile=1)
    neon("NeonEnd", walls, (HALL_E - 0.15, 14.6, HALL_S - 0.1), (HALL_E + 0.1, 15.2, HALL_N + 0.1), BLUE)
    for z in (AXIS - 30, AXIS, AXIS + 30):
        neon("CeilingStrip", walls, (HALL_W + 2, CEIL_Y - 0.25, z - 0.6), (HALL_E - 2, CEIL_Y + 0.2, z + 0.6), BLUE)
    box("Berm", walls, (192.0, 0, HALL_S - 0.2), (HALL_E + 0.3, 6.0, HALL_N + 0.2), CEILING, "Left Top", solid=True)


# Two drawn boxes with faces on one plane, facing the same way, whose rectangles overlap: z-fighting, unless the
# shared patch is buried in a third box (feet on a floor, backs let into a wall). Faces that meet back to back
# (a crate on the floor) are not.
def zfight(all_boxes, tolerance=0.012):
    def buried(point, skip):
        for index, (_, lo, hi, drawn) in enumerate(all_boxes):
            if index in skip or not drawn:
                continue
            if all(lo[a] - 1e-6 <= point[a] <= hi[a] + 1e-6 for a in range(3)):
                return True
        return False

    found = []
    for i in range(len(all_boxes)):
        name1, lo1, hi1, drawn1 = all_boxes[i]
        if not drawn1:
            continue
        for j in range(i + 1, len(all_boxes)):
            name2, lo2, hi2, drawn2 = all_boxes[j]
            if not drawn2 or (name1.startswith("plaza:") and name2.startswith("plaza:")):
                continue
            if any(lo1[a] > hi2[a] + tolerance or lo2[a] > hi1[a] + tolerance for a in range(3)):
                continue
            for axis in range(3):
                others = [a for a in range(3) if a != axis]
                patch = [(max(lo1[a], lo2[a]), min(hi1[a], hi2[a])) for a in others]
                if not all(high - low > 0.02 for low, high in patch):
                    continue
                for side1, side2, outward in ((lo1, lo2, -1), (hi1, hi2, 1)):
                    if abs(side1[axis] - side2[axis]) > tolerance:
                        continue
                    shown = False
                    for u in (0.1, 0.5, 0.9):
                        for v in (0.1, 0.5, 0.9):
                            point = [0.0, 0.0, 0.0]
                            point[axis] = (side1[axis] if outward < 0 else max(side1[axis], side2[axis])) + outward * 0.02
                            if outward < 0:
                                point[axis] = min(side1[axis], side2[axis]) - 0.02
                            point[others[0]] = patch[0][0] + (patch[0][1] - patch[0][0]) * u
                            point[others[1]] = patch[1][0] + (patch[1][1] - patch[1][0]) * v
                            shown = shown or not buried(point, (i, j))
                    if shown:
                        found.append(f"{name1} / {name2}: axis {'xyz'[axis]} at {side1[axis]:.3f}")
    return found


# The plaza's parts that reach into or stand against the hall (measured 2026-11-23, world boxes).
PLAZA = (
    ("plaza:FloorSouth", (-23.0, 0.0, -49.0), (22.0, 0.9, 23.0)),
    ("plaza:FloorNorth", (-167.0, 0.0, 23.0), (22.0, 0.9, 68.0)),
    ("plaza:PillarEast", (20.77, 28.0, -0.67), (70.69, 136.74, 49.25)),
    ("plaza:PillarEastNeon", (-5.66, 50.06, -20.55), (42.99, 55.33, 28.1)),
    ("plaza:PillarSouthHigh", (7.04, 27.37, -56.24), (49.61, 120.11, -13.67)),
    ("plaza:PillarNorth", (-6.96, -18.63, 28.76), (35.61, 74.11, 71.33)),
    ("plaza:PillarSouth", (-6.96, -39.0, -58.25), (30.11, 41.74, -21.18)),
    ("plaza:PillarSouthNeon", (-6.0, 30.31, -57.29), (29.15, 34.12, -22.14)),
    # Range.Front's lifted pieces, as boxes: the portico and the lintel behind it.
    ("front:Portico", (-23.0, 0.9, -45.8), (-19.2, 32.5, 19.8)),
    ("front:Lintel", (-19.2, 16.1, -36.0), (-17.0, 17.1, 10.1)),
)


def main():
    build()
    # Names are numbered so each path names one instance (range_push.py parents by path).
    seen = {}
    for entry in entries:
        key = (entry["p"], entry["n"])
        seen[key] = seen.get(key, 0) + 1
    count = {}
    for entry in entries:
        key = (entry["p"], entry["n"])
        if seen[key] > 1 and entry["c"] not in ("Texture",):
            count[key] = count.get(key, 0) + 1
            entry["n"] = f"{entry['n']}{count[key]}"

    fights = zfight(boxes + [(name, lo, hi, True) for name, lo, hi in PLAZA])
    for line in sorted(set(fights))[:40]:
        print("z-fight:", line)
    kinds = {}
    for entry in entries:
        kinds[entry["c"]] = kinds.get(entry["c"], 0) + 1
    print(f"z-fights: {len(fights)}")
    print("instances:", len(entries), kinds)
    if len(sys.argv) > 1:
        with open(sys.argv[1], "w") as out:
            json.dump(entries, out)


main()
