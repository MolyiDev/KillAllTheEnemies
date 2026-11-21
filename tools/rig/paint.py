"""The anime painter for the R6 zombies (r6_zombie.py calls it once per face of every box and once for the head).

THE GDD ASKS FOR AN ANIME LOOK WITH SIMPLE, READABLE ZOMBIE SILHOUETTES (section 9), so this is cel painting, not
Textures.md's pixel mottle (kept for the pipeline, not the style): every surface is one flat colour,
one hard-edged shadow tone and a lighter highlight, with ink lines where cloth tears, folds or ends. Detail is a few
big shapes (a torn hem, a rip showing skin, a blood splash), never noise, so a crowd still reads at a distance.

Everything is drawn SUPERSAMPLED (SS times over) and scaled down with a Lanczos filter, which is what gives the ink
lines their clean anti-aliased edge; the texture is meant to be sampled smoothly, not as pixels.

Coordinates are final pixels. A side face is painted as seen from outside with its top up; `up` has the model's back
at the top of the image, `down` its front (Textures.md §6, measured in Blockbench).
"""
import math

from PIL import Image, ImageDraw

SS = 3
INK = (28, 22, 32, 255)


def rgb(s, a=255):
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4)) + (a,)


def mix(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(4))


class Face:
    """One face being painted: a supersampled RGBA canvas and helpers in final-pixel coordinates."""

    def __init__(self, w, h, fill):
        self.w, self.h = w, h
        self.img = Image.new("RGBA", (w * SS, h * SS), fill)
        self.draw = ImageDraw.Draw(self.img)

    def _p(self, pts):
        return [(x * SS, y * SS) for x, y in pts]

    def poly(self, pts, fill, ink=None, width=1.6):
        self.draw.polygon(self._p(pts), fill=fill)
        if ink:
            self.line(pts + [pts[0]], ink, width)

    def line(self, pts, color=INK, width=1.6):
        self.draw.line(self._p(pts), fill=color, width=max(1, round(width * SS)), joint="curve")

    def ellipse(self, cx, cy, rx, ry, fill, ink=None, width=1.6):
        box = [(cx - rx) * SS, (cy - ry) * SS, (cx + rx) * SS, (cy + ry) * SS]
        self.draw.ellipse(box, fill=fill, outline=ink, width=max(1, round(width * SS)) if ink else 0)

    def done(self):
        return self.img.resize((self.w, self.h), Image.LANCZOS)


def jagged(x0, x1, y, amp, step, rng):
    """A torn edge from x0 to x1 around height y: teeth of random depth, never the same twice."""
    pts, x = [], x0
    while x < x1:
        pts.append((x, y + rng.uniform(-amp, amp)))
        x += step * rng.uniform(0.6, 1.3)
    pts.append((x1, y + rng.uniform(-amp, amp)))
    return pts


def wave(x0, x1, y, amp, waves, phase=0.0):
    n = 24
    return [(x0 + (x1 - x0) * i / n, y + amp * math.sin((i / n * waves + phase) * 2 * math.pi)) for i in range(n + 1)]


def splash(f, cx, cy, r, rng, blood):
    """A blood splash: a lobed blob, a darker core and a few drops flung off one side."""
    lobes = []
    for i in range(10):
        a = i / 10 * 2 * math.pi
        rr = r * rng.uniform(0.55, 1.15)
        lobes.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr * 0.8))
    f.poly(lobes, blood[0])
    f.ellipse(cx + r * 0.1, cy + r * 0.1, r * 0.45, r * 0.35, blood[1])
    side = rng.choice((-1, 1))
    for k in range(3):
        d = r * (1.4 + k * 0.5)
        f.ellipse(cx + side * d, cy + rng.uniform(-r, r) * 0.6, r * 0.18 / (k + 1) ** 0.3, r * 0.16, blood[0])


def drip(f, x, y, length, width, blood):
    f.poly([(x - width, y), (x + width, y), (x + width * 0.6, y + length), (x, y + length + width),
            (x - width * 0.6, y + length)], blood[0])


# How far a painted shadow goes from the base toward the shadow tone. Roblox lights the mesh as well, so a full-strength
# painted shadow doubled up into stripes across the torso (the first render).
SHADOW_STRENGTH = 0.55


def cel_shadow(f, look_tone, top, rng, amp=2.0, base=None):
    """The shadow tone from `top` down, its edge a slow wave: the one hard shading step of the style."""
    tone = mix(base, look_tone, SHADOW_STRENGTH) if base else look_tone
    pts = wave(0, f.w, top, amp, rng.uniform(0.8, 1.6), rng.random()) + [(f.w, f.h), (0, f.h)]
    f.poly(pts, tone)


def highlight(f, tone, y, rng):
    """The lit top of a face: a lighter band from the top edge down to a slow wave at `y`. One shape, not strokes:
    short strokes read as stitching (the first render)."""
    pts = [(0, -1), (f.w, -1)] + wave(f.w, 0, y, 1.5, rng.uniform(0.5, 1.0), rng.random())
    f.poly(pts, tone)


# ---------------------------------------------------------------- body parts
def shirt_face(look, face, w, h, rng):
    cloth, skin = look["shirt"], look["skin"]
    f = Face(w, h, cloth[1] if face != "down" else cloth[2])
    if face in ("up", "down"):
        if face == "up":
            highlight(f, cloth[0], h * 0.35, rng)
        return f.done()
    cel_shadow(f, cloth[2], h * rng.uniform(0.66, 0.74), rng, base=cloth[1])
    highlight(f, cloth[0], h * 0.1, rng)
    if face == "south":
        # The collar torn open to the skin, and two fold lines pulling toward one shoulder.
        f.poly([(w * 0.36, -1), (w * 0.64, -1), (w * 0.5 + rng.uniform(-2, 2), h * 0.26)], skin[1], INK, 1.8)
        f.line([(w * 0.2, h * 0.35), (w * 0.34, h * 0.5), (w * 0.38, h * 0.62)], cloth[3], 1.3)
        f.line([(w * 0.78, h * 0.4), (w * 0.7, h * 0.55)], cloth[3], 1.3)
    if face in ("south", "north"):
        # One rip through to the skin, outlined, with the skin's own shadow in its lower half.
        cx, cy = w * rng.uniform(0.3, 0.7), h * rng.uniform(0.45, 0.62)
        rw, rh = w * rng.uniform(0.12, 0.18), h * rng.uniform(0.08, 0.12)
        rip = [(cx + math.cos(a) * rw * rng.uniform(0.6, 1.2), cy + math.sin(a) * rh * rng.uniform(0.6, 1.2))
               for a in (i / 9 * 2 * math.pi for i in range(9))]
        f.poly(rip, skin[1], INK, 1.8)
        f.line([(cx - rw * 0.5, cy + rh * 0.2), (cx + rw * 0.4, cy + rh * 0.35)], skin[3], 1.2)
    if face == "north":
        # Claw rips across the back: three parallel slashes.
        for k in range(3):
            x = w * (0.25 + k * 0.17)
            f.poly([(x, h * 0.18), (x + 3, h * 0.16), (x + 10, h * 0.42), (x + 7, h * 0.44)], skin[1], INK, 1.4)
    # The torn hem, skin showing under it.
    hem = jagged(-1, w + 1, h * 0.9, 2.6, 7, rng)
    f.poly(hem + [(w + 1, h + 1), (-1, h + 1)], skin[1])
    f.line(hem, INK, 1.8)
    if look.get("pustules"):
        # Boils swelling through the cloth: a lit dome with an ink rim, two or three to a face, never a ring.
        for _ in range(rng.randint(2, 3)):
            px, py, pr = w * rng.uniform(0.15, 0.85), h * rng.uniform(0.25, 0.75), min(w, h) * rng.uniform(0.05, 0.08)
            f.ellipse(px, py, pr, pr, rgb(look["pustules"]), INK, 1.4)
            f.ellipse(px - pr * 0.3, py - pr * 0.3, pr * 0.3, pr * 0.25, rgb("#ffe0b0"))
    if look.get("trim"):
        f.poly([(0, 0), (w, 0), (w, 3), (0, 3)], rgb(look["trim"]))
    if rng.random() < 0.7:
        splash(f, w * rng.uniform(0.2, 0.8), h * rng.uniform(0.2, 0.5), min(w, h) * 0.07, rng, look["blood"])
    return f.done()


def bare_torso_face(look, face, w, h, rng):
    skin = look["skin"]
    f = Face(w, h, skin[1] if face != "down" else skin[2])
    if face in ("up", "down"):
        return f.done()
    cel_shadow(f, skin[2], h * 0.7, rng, base=skin[1])
    if face == "south":
        # Pecs and abs in ink, the anime shorthand for a heavy.
        f.line(wave(w * 0.15, w * 0.48, h * 0.3, 2, 0.5), INK, 1.6)
        f.line(wave(w * 0.52, w * 0.85, h * 0.3, 2, 0.5, 0.5), INK, 1.6)
        f.line([(w * 0.5, h * 0.36), (w * 0.5, h * 0.78)], skin[3], 1.4)
        for y in (0.48, 0.6, 0.72):
            f.line([(w * 0.38, h * y), (w * 0.46, h * y + 1)], skin[3], 1.3)
            f.line([(w * 0.54, h * y + 1), (w * 0.62, h * y)], skin[3], 1.3)
        # A stitched scar across the chest.
        x0, y0, x1, y1 = w * 0.2, h * 0.55, w * 0.75, h * 0.2
        f.line([(x0, y0), (x1, y1)], look["blood"][1], 2.2)
        for k in range(1, 7):
            t = k / 7
            x, y = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
            f.line([(x - 2.5, y - 3), (x + 2.5, y + 3)], INK, 1.1)
    # Trousers' waistband shows at the bottom edge.
    f.poly([(0, h * 0.9), (w, h * 0.9), (w, h), (0, h)], look["pants"][1])
    f.line([(0, h * 0.9), (w, h * 0.9)], INK, 1.6)
    return f.done()


def arm_face(look, face, w, h, rng, inner):
    skin, cloth = look["skin"], look["shirt"]
    f = Face(w, h, skin[1] if face not in ("down",) else skin[2])
    if face == "down":
        # The palm and fingertips, seen from below: darker, with three finger gaps.
        for k in (0.3, 0.5, 0.7):
            f.line([(w * k, h * 0.2), (w * k, h * 0.8)], skin[3], 1.3)
        return f.done()
    if face == "up":
        if cloth is not None and look["sleeves"]:
            f = Face(w, h, cloth[1])
            highlight(f, cloth[0], h * 0.4, rng)
        return f.done()
    # The side away from the light is the shadow side; the inner face is in the body's shadow most of its length.
    if inner:
        cel_shadow(f, skin[2], h * 0.15, rng, 1.5, base=skin[1])
    else:
        cel_shadow(f, skin[2], h * rng.uniform(0.6, 0.7), rng, base=skin[1])
    if cloth is not None and look["sleeves"]:
        edge = jagged(-1, w + 1, h * 0.3, 2.4, 5, rng)
        f.poly([(-1, -1), (w + 1, -1)] + edge[::-1], cloth[1])
        if not inner:
            highlight(f, cloth[0], h * 0.08, rng)
        f.line(edge, INK, 1.8)
    # Clawed fingertips: a darker band at the end and claw points.
    tip = h * 0.88
    f.poly([(0, tip), (w, tip), (w, h), (0, h)], skin[3])
    for k in range(3):
        x = w * (0.2 + k * 0.3)
        f.poly([(x - 2, h - 1), (x + 2, h - 1), (x, h - 5)], rgb("#e8e2c8"))
    if face == "south" and rng.random() < 0.8:
        drip(f, w * rng.uniform(0.3, 0.7), h * 0.62, h * 0.18, 2.4, look["blood"])
    return f.done()


def leg_face(look, face, w, h, rng, inner):
    pants, skin = look["pants"], look["skin"]
    f = Face(w, h, pants[1] if face != "down" else rgb("#2a2430"))
    if face == "up":
        return f.done()
    if face == "down":
        return f.done()
    cel_shadow(f, pants[2], h * (0.1 if inner else rng.uniform(0.55, 0.65)), rng, base=pants[1])
    if not inner:
        highlight(f, pants[0], h * 0.1, rng)
    # Knee creases and, on the front, a torn knee showing the skin.
    f.line([(w * 0.25, h * 0.42), (w * 0.45, h * 0.46), (w * 0.6, h * 0.44)], pants[3], 1.3)
    if face == "south" and rng.random() < 0.6:
        cx, cy = w * rng.uniform(0.35, 0.65), h * 0.5
        knee = [(cx + math.cos(a) * w * 0.2 * rng.uniform(0.7, 1.1), cy + math.sin(a) * h * 0.06 * rng.uniform(0.7, 1.2))
                for a in (i / 8 * 2 * math.pi for i in range(8))]
        f.poly(knee, skin[1], INK, 1.6)
    # Shoes: dark, a lighter toe cap on the front, ink line at the top.
    shoe = h * 0.84
    f.poly([(0, shoe), (w, shoe), (w, h), (0, h)], rgb("#3a3440"))
    if face == "south":
        f.poly([(w * 0.15, h * 0.9), (w * 0.85, h * 0.9), (w * 0.8, h * 0.97), (w * 0.2, h * 0.97)], rgb("#5a5462"))
    f.line([(0, shoe), (w, shoe)], INK, 1.8)
    return f.done()


def body_face(look, part, face, w, h, rng):
    if part == "Torso":
        return (shirt_face if look["shirt"] is not None else bare_torso_face)(look, face, w, h, rng)
    # The face that touches the torso (arms) or the other leg is the inner one.
    inner = {"ArmLeft": "west", "ArmRight": "east", "LegLeft": "west", "LegRight": "east"}[part] == face
    if part.startswith("Arm"):
        return arm_face(look, face, w, h, rng, inner)
    return leg_face(look, face, w, h, rng, inner)


# ---------------------------------------------------------------- the head
def head_strip(look, w, h, side_top, side_bottom, rng):
    """The head's side, unwrapped: x is the angle round the head (the face at the middle, the seam at the back),
    y the distance along its rounded profile from the top cap's rim (y = 0) down to the bottom cap's rim.
    `side_top` and `side_bottom` are where the head's straight side starts and ends on y."""
    skin = look["skin"]
    f = Face(w, h, skin[1])
    # Jaw shadow under the face, and the back of the head in shadow.
    cel_shadow(f, skin[2], side_top + (side_bottom - side_top) * 0.82, rng, 1.5, base=skin[1])
    back = mix(skin[1], skin[2], SHADOW_STRENGTH)
    f.poly([(-1, -1), (w * 0.14, -1), (w * 0.12, h + 1), (-1, h + 1)], back)
    f.poly([(w * 0.86, -1), (w + 1, -1), (w + 1, h + 1), (w * 0.88, h + 1)], back)

    cx = w / 2
    span = w * 0.24  # the face's half-width: about a quarter of the way round the head each side
    eye_y = side_top + (side_bottom - side_top) * 0.38
    eye = look["eye"]
    for side in (-1, 1):
        ex = cx + side * span * 0.42
        # Anime eyes, angled down toward the nose: a sharp almond, a glowing iris with a slit, one highlight.
        outer, inner = ex + side * span * 0.3, ex - side * span * 0.24
        top, bottom = eye_y - h * 0.07, eye_y + h * 0.06
        almond = [(inner, eye_y + h * 0.01), (ex, top + (h * 0.02 if side < 0 else 0)), (outer, top - h * 0.02),
                  (outer - side * span * 0.04, eye_y + h * 0.02), (ex, bottom)]
        f.poly(almond, rgb("#f2ecd2"))
        f.ellipse(ex + side * span * 0.03, eye_y, span * 0.13, h * 0.06, rgb(eye))
        f.ellipse(ex + side * span * 0.03, eye_y, span * 0.035, h * 0.045, INK)
        f.ellipse(ex - side * span * 0.04, eye_y - h * 0.025, span * 0.04, h * 0.018, (255, 255, 255, 255))
        f.line([almond[0], almond[1], almond[2]], INK, 2.6)
        f.line([almond[2], almond[3], almond[4], almond[0]], INK, 1.2)
        # Brow: a heavy stroke sloping down to the middle.
        f.line([(inner - side * span * 0.04, top - h * 0.04), (outer + side * span * 0.04, top - h * 0.1)], INK, 2.4)
        # Dark bags under the eye.
        f.line([(inner + side * span * 0.04, bottom + h * 0.03), (outer - side * span * 0.06, bottom + h * 0.02)],
               skin[3], 1.4)
    # Mouth: a jagged open snarl with fangs.
    my = side_top + (side_bottom - side_top) * 0.72
    mw = span * 0.42
    upper = [(cx - mw, my), (cx - mw * 0.5, my - h * 0.03), (cx, my - h * 0.015), (cx + mw * 0.5, my - h * 0.03),
             (cx + mw, my)]
    lower = [(cx + mw * 0.7, my + h * 0.05), (cx, my + h * 0.075), (cx - mw * 0.7, my + h * 0.05)]
    f.poly(upper + lower, rgb("#3a1020"), INK, 1.8)
    for k in (-0.55, -0.2, 0.2, 0.55):
        x = cx + mw * k
        f.poly([(x - 2.2, my - h * 0.02), (x + 2.2, my - h * 0.02), (x, my + h * 0.03)], rgb("#f4f0de"))
    # Stitches across one cheek.
    sx = cx + span * 0.75 * rng.choice((-1, 1))
    f.line([(sx - 6, eye_y + h * 0.12), (sx + 4, my + h * 0.04)], INK, 1.4)
    for k in range(1, 4):
        t = k / 4
        x, y = sx - 6 + 10 * t, eye_y + h * 0.12 + (my + h * 0.04 - eye_y - h * 0.12) * t
        f.line([(x - 3, y), (x + 3, y + 1)], INK, 1.2)

    hair = look.get("hair")
    if hair:
        tones = [rgb(c) for c in hair]
        # Hair from the cap rim down to the forehead at the front, lower at the back, spiked bangs on the brow.
        fringe = side_top + (eye_y - side_top) * 0.15
        pts = [(0, -1)]
        n = 22
        for i in range(n + 1):
            x = w * i / n
            front = math.cos((x / w - 0.5) * 2 * math.pi)  # 1 at the face, -1 at the back
            base = fringe if front > 0.5 else side_top + (side_bottom - side_top) * (0.3 - 0.55 * min(front, 0.5))
            spike = (h * 0.06 if i % 2 else -h * 0.015) * (1.6 if front > 0.6 else 1.0)
            pts.append((x, base + spike))
        pts += [(w, -1)]
        f.poly(pts, tones[1])
        f.line(pts[1:-1], INK, 2.0)
        # Shine band: the anime hair highlight, one ring round the crown with notches cut into its lower edge.
        hy = h * 0.1
        band = [(0, hy)]
        for i in range(n + 1):
            band.append((w * i / n, hy + (h * 0.035 if i % 3 == 1 else h * 0.015)))
        band += [(w, hy - h * 0.025), (0, hy - h * 0.025)]
        f.poly(band, tones[0])
    elif look.get("scalp_scar"):
        f.line([(cx - span * 0.6, h * 0.05), (cx + span * 0.2, side_top + h * 0.05)], look["blood"][1], 2.2)
    return f.done()


def head_cap(look, d, top):
    """A cap disc in a d x d square (planar mapping, +X of the model to the right, its back at the top for the top cap,
    its front at the top for the bottom cap, as Blockbench maps up/down)."""
    skin = look["skin"]
    hair = look.get("hair")
    fill = rgb(hair[1]) if top and hair else (skin[1] if top else skin[2])
    f = Face(d, d, fill)
    if top and hair:
        tones = [rgb(c) for c in hair]
        # The crown's shine, toward the front (the image's bottom) where the strip's shine band meets it.
        f.ellipse(d * 0.5, d * 0.72, d * 0.3, d * 0.1, tones[0])
    return f.done()
