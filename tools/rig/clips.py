"""The shared R6 zombie clips, as functions of time sampled into .bbmodel keyframes (r6_zombie.py writes them into
ZombieNormal.bbmodel; to_fbx.py exports one FBX each). Rotations only, so one set plays on every size.

Every clip that resolves an attack lands its blow at IMPACT seconds; EnemiesController plays it at IMPACT / Delay
speed (EnemiesCore.ATTACK_CLIP_IMPACT) so the blow meets the server's wind-up.
"""
import math
import uuid

IMPACT = 0.6
CLIP_FPS = 30


def wave(t, length, phase=0.0):
    return math.sin((t / length + phase) * 2 * math.pi)


def ease_out(x):
    return 1 - (1 - x) ** 3


def ease_in(x):
    return x ** 3


def lerp(a, b, x):
    return a + (b - a) * max(0.0, min(1.0, x))


def piecewise(t, keys):
    """[(time, value, ease)], the ease shaping the segment that ends at that key."""
    for (t0, v0, _), (t1, v1, e) in zip(keys, keys[1:]):
        if t <= t1:
            x = (t - t0) / (t1 - t0) if t1 > t0 else 1
            return lerp(v0, v1, e(x) if e else x)
    return keys[-1][1]


# Signs in .bbmodel Euler degrees, worked out once and checked by tools/rig/check_pose.py in Blender:
#   arm or leg x < 0 swings the hand / foot FORWARD (+Z);  torso / head x > 0 leans forward;
#   ArmLeft z > 0 and ArmRight z < 0 lift the arms out to the sides.
REACH = -88


def idle(t):
    L = 2.4
    return {
        "Torso": (6 + 1.5 * wave(t, L), 2 * wave(t, L, 0.25), 0),
        "Head": (10 + 3 * wave(t, L, 0.1), 0, 5 * wave(t, L, 0.3)),
        "ArmLeft": (REACH + 4 * wave(t, L), 0, 6 + 2 * wave(t, L, 0.5)),
        "ArmRight": (REACH + 4 * wave(t, L, 0.4), 0, -6 - 2 * wave(t, L, 0.1)),
        "LegLeft": (0, 0, 0),
        "LegRight": (0, 0, 0),
    }, L


def walk(t):
    L = 0.8
    s = wave(t, L)
    return {
        "Torso": (8, 6 * s, 2 * wave(t, L, 0.25)),
        "Head": (10, -4 * s, 4 * wave(t, L, 0.1)),
        "ArmLeft": (REACH + 8 * s, 0, 5),
        "ArmRight": (REACH - 8 * s, 0, -5),
        "LegLeft": (-38 * s, 0, 0),
        "LegRight": (38 * s, 0, 0),
    }, L


def attack(t):
    # Both arms rear up and back, then rake down onto the target at IMPACT.
    L = 1.0
    arm = piecewise(t, [(0, REACH, None), (0.42, -165, ease_out), (IMPACT, -40, ease_in), (L, REACH, ease_out)])
    lean = piecewise(t, [(0, 8, None), (0.42, -6, ease_out), (IMPACT, 26, ease_in), (L, 8, ease_out)])
    return {
        "Torso": (lean, 0, 0),
        "Head": (10 + lean * 0.3, 0, 0),
        "ArmLeft": (arm, 0, 8),
        "ArmRight": (arm + 4, 0, -8),
        "LegLeft": (piecewise(t, [(0, 0, None), (IMPACT, -18, ease_in), (L, 0, ease_out)]), 0, 0),
        "LegRight": (piecewise(t, [(0, 0, None), (IMPACT, 12, ease_in), (L, 0, ease_out)]), 0, 0),
    }, L


def slam(t):
    # Arms straight overhead and held, then both fists into the ground at IMPACT, the body folding after them.
    L = 1.3
    arm = piecewise(t, [(0, REACH, None), (0.4, -178, ease_out), (0.5, -182, None), (IMPACT, -20, ease_in),
                        (0.95, -25, None), (L, REACH, ease_out)])
    lean = piecewise(t, [(0, 8, None), (0.4, -12, ease_out), (0.5, -14, None), (IMPACT, 42, ease_in),
                         (0.95, 38, None), (L, 8, ease_out)])
    crouch = piecewise(t, [(0, 0, None), (0.5, 0, None), (IMPACT, -30, ease_in), (0.95, -28, None), (L, 0, ease_out)])
    return {
        "Torso": (lean, 0, 0),
        "Head": (6 - lean * 0.2, 0, 0),
        "ArmLeft": (arm, 0, 10),
        "ArmRight": (arm, 0, -10),
        "LegLeft": (crouch, 0, 4),
        "LegRight": (crouch, 0, -4),
    }, L


def fuse(t):
    # The exploder swells and shakes harder until IMPACT, arms thrown wide and head back; the blast takes the body.
    L = 1.0
    grow = min(1.0, t / IMPACT)
    jitter = math.sin(t * 2 * math.pi * 14) * (2 + 10 * grow * grow)
    return {
        "Torso": (-6 * grow, jitter * 0.6, jitter),
        "Head": (-28 * grow, jitter, 0),
        "ArmLeft": (-30 * grow, 0, 15 + 60 * grow),
        "ArmRight": (-30 * grow, 0, -15 - 60 * grow),
        "LegLeft": (0, 0, 8 * grow),
        "LegRight": (0, 0, -8 * grow),
    }, L


CLIPS = [("Idle", idle, True), ("Walk", walk, True), ("Attack", attack, False), ("Slam", slam, False),
         ("Fuse", fuse, False)]


def animation(name, fn, looped, group_uuids):
    _, length = fn(0)
    frames = int(round(length * CLIP_FPS))
    animators = {}
    for bone, uid in group_uuids.items():
        keys = []
        for f in range(frames + 1):
            t = f / CLIP_FPS
            pose, _ = fn(t % length if looped and f == frames else t)
            if looped and f == frames:
                pose, _ = fn(0)
            if bone not in pose:
                break
            x, y, z = pose[bone]
            keys.append(dict(channel="rotation", time=round(t, 4), uuid=str(uuid.uuid4()), interpolation="linear",
                             data_points=[dict(x=round(x, 3), y=round(y, 3), z=round(z, 3))]))
        if keys:
            animators[uid] = dict(name=bone, type="bone", keyframes=keys)
    return dict(uuid=str(uuid.uuid4()), name=name, loop="loop" if looped else "once", length=length,
                snapping=CLIP_FPS, animators=animators)
