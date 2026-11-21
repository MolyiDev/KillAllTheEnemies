# The lobby pad's boxes in the pad's own frame, as LobbyController/PadArt builds them, and the baseplate under it:
# no two boxes may have faces on one plane whose rectangles overlap (Models.md section 13). Keep the numbers in step
# with PadArt.luau and the pad Part (12 x 0.5 x 12, centre 0.15 above the baseplate's top). Prints the count; 0 ships.
import itertools

HALF = (6, 0.25, 6)
RIM_WIDTH, RIM_SINK, RIM_RISE = 0.62, 0.1, 0.2
Z_BAR_OUT, X_BAR_OUT, X_BAR_LIFT, X_BAR_DROP = 0.06, 0.04, 0.02, 0.03
BASEPLATE_TOP = -0.15

hx, hy, hz = HALF
bottom, height = hy - RIM_SINK, RIM_SINK + RIM_RISE
boxes = {
    "pad": ((-hx, -hy, -hz), (hx, hy, hz)),
    "baseplate": ((-50, -20, -50), (50, BASEPLATE_TOP, 50)),
}
for side in (-1, 1):
    z = side * (hz + Z_BAR_OUT - RIM_WIDTH / 2)
    boxes[f"zbar{side}"] = ((-(hx + Z_BAR_OUT), bottom, z - RIM_WIDTH / 2), (hx + Z_BAR_OUT, bottom + height, z + RIM_WIDTH / 2))
    x = side * (hx + X_BAR_OUT - RIM_WIDTH / 2)
    boxes[f"xbar{side}"] = (
        (x - RIM_WIDTH / 2, bottom + X_BAR_LIFT, -(hz + X_BAR_OUT)),
        (x + RIM_WIDTH / 2, bottom + height - X_BAR_DROP, hz + X_BAR_OUT),
    )


def faces(lo, hi):
    for axis in range(3):
        others = [i for i in range(3) if i != axis]
        for value in (lo[axis], hi[axis]):
            yield axis, round(value, 6), [(lo[i], hi[i]) for i in others]


count = 0
for (name1, (lo1, hi1)), (name2, (lo2, hi2)) in itertools.combinations(boxes.items(), 2):
    for axis1, value1, rect1 in faces(lo1, hi1):
        for axis2, value2, rect2 in faces(lo2, hi2):
            overlaps = all(min(a[1], b[1]) - max(a[0], b[0]) > 1e-9 for a, b in zip(rect1, rect2))
            if axis1 == axis2 and value1 == value2 and overlaps:
                print(f"z-fight: {name1} / {name2} on axis {axis1} at {value1}")
                count += 1
print(f"z-fights: {count}")
