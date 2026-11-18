# eyes.py: the hero creator's glowing eye shapes as meshes (creator art round 3, 2026-11-18), in place of the neon
# blocks and balls LookKit lays on the face for the Eyes slot (EYE_SHAPES: bar, sharp, round, big, narrow, slit,
# visor; a piece's kit is "shape:tone", the tone picks the glow colour). Each shape is a left and a right glow shape
# (the visor one band) bent onto the front of the classic rounded head at the face decal's eyes (x +-0.22, z 4.73;
# kit.py axes: +y the face): a soft lozenge, a sharp anime blade, an orb, a big anime eye, a narrow slit of light, a
# cat's slit and a wraparound band. Role eye1 (the left eye's colour) and eye2 (the right's: a Prism tone is two).
# Output: art/export/Eyes.fbx (nate imports it as ReplicatedStorage.Art.Eyes), src/config/EyeArt.luau (LookKit's
# fit) and art/preview/eyes.png.
# Run: python art/blender/eyes.py [--quick] [--only shape,shape]   (with the `bpy` module, Blender 5.0, under nice)
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import wear  # noqa: E402
from wear import Piece, PI, outline  # noqa: E402
import bpy  # noqa: E402, F401

QUICK = "--quick" in sys.argv
ONLY = None
if "--only" in sys.argv:
    ONLY = sys.argv[sys.argv.index("--only") + 1].split(",")
BUDGET = 400
EZ = 4.73  # the eyes' height
EX = 0.22  # each eye's distance from the middle
FY = 0.604  # the face

kit.reset()

STYLES = {}


def style(name):
    def reg(fn):
        STYLES[name] = fn
        return fn
    return reg


def on_face(ob, depth=0.02):
    """Bend a flat glow shape onto the rounded face (the head's front curves back toward the sides)."""
    for v in ob.data.vertices:
        x = v.co.x
        v.co.y = v.co.y + FY + depth - 0.22 * x * x - 0.9 * max(0.0, abs(x) - 0.36) ** 2
    return ob


def lens(w, h, n=14, top=1.0, bottom=1.0, tilt=0.0, point=0.0):
    """A lens outline w x h: the upper and lower lids as arcs (top/bottom bulge), tipped `tilt` (radians, the outer
    corner up for the left eye), the outer corner drawn out to a point by `point`."""
    pts = []
    for k in range(n + 1):
        t = k / n
        x = -w / 2 + w * t
        y = h / 2 * math.sin(PI * t) ** 0.8 * top
        pts.append((x, y))
    for k in range(n - 1, 0, -1):
        t = k / n
        x = -w / 2 + w * t
        y = -h / 2 * math.sin(PI * t) ** 0.8 * bottom
        pts.append((x, y))
    out = []
    for x, y in pts:
        if point and x < 0:
            x -= point * (-x / (w / 2)) ** 3 * 0.5
        c, s = math.cos(tilt), math.sin(tilt)
        out.append((x * c - y * s, x * s + y * c))
    return out


def pair(name, pts, depth=0.03):
    """Left and right eyes from one outline (drawn as the left eye: the outer corner at -x)."""
    left = on_face(outline(name + "L", pts, depth, at=(-EX, 0.0, EZ), axis="Y"))
    right = kit.mirror_x(left, name + "R")
    return [Piece(left, "head", "eye1", True), Piece(right, "head", "eye2", True)]


def ellipse(w, h, n=20):
    return [(w / 2 * math.cos(2 * PI * k / n), h / 2 * math.sin(2 * PI * k / n)) for k in range(n)]


@style("bar")
def e_bar():
    return pair("Eye", wear.rrect_pts(0.2, 0.09, 0.04))


@style("sharp")
def e_sharp():
    # an anime blade: the lid sweeps up to a sharp outer corner
    return pair("Eye", lens(0.25, 0.085, top=1.1, bottom=0.55, tilt=-0.2, point=0.06))


@style("round")
def e_round():
    return pair("Eye", ellipse(0.155, 0.155))


@style("big")
def e_big():
    # a big anime eye: a tall soft shape with a flat lash line on top
    pts = []
    n = 20
    for k in range(n):
        a = 2 * PI * k / n
        x, y = 0.105 * math.cos(a), 0.14 * math.sin(a)
        if y > 0.09:
            y = 0.09 + (y - 0.09) * 0.3
        pts.append((x, y - 0.01))
    return pair("Eye", pts)


@style("narrow")
def e_narrow():
    return pair("Eye", lens(0.23, 0.045, top=1.0, bottom=0.7, tilt=-0.08))


@style("slit")
def e_slit():
    pts = []
    n = 12
    for k in range(n + 1):
        t = k / n
        pts.append((0.028 * math.sin(PI * t), -0.1 + 0.2 * t))
    for k in range(n - 1, 0, -1):
        t = k / n
        pts.append((-0.028 * math.sin(PI * t), -0.1 + 0.2 * t))
    return pair("Eye", pts)


@style("visor")
def e_visor():
    n = 24
    top, bot = [], []
    for k in range(n + 1):
        x = -0.39 + 0.78 * k / n
        dip = 0.018 * math.cos(PI * x / 0.78) ** 2 if abs(x) < 0.05 else 0.0
        top.append((x, 0.055 - dip))
        bot.append((x, -0.055 + 0.012 * (1 - (x / 0.39) ** 2)))
    band = on_face(outline("Band", top + list(reversed(bot)), 0.03, at=(0.0, 0.0, EZ), axis="Y"))
    return [Piece(band, "head", "eye1", True)]


HEADER = ["eyes.py",
          "The creator's glowing eye shapes as meshes (ReplicatedStorage.Art.Eyes once nate imports art/export/Eyes.fbx;",
          "LookKit wears them then, the neon blocks until then). Keyed by the eye shape (an Eyes piece's kit is",
          "shape:tone): each piece's mesh name, the body part it is welded to (the head), its colour role (eye1 the",
          "left eye's glow, eye2 the right's), glow (Neon) and its box against the Head's centre in Roblox axes",
          "(x right, y up, z back), in studs on the standard blocky rig (scaled with the head)."]


def preview(built):
    def dress(name, at, yaw, pal):
        wear.body(at, yaw, parts={"Head"})
        wear.place(built[name], at, yaw, pal)
    out = os.path.join(kit.ROOT, "preview", "eyes.png" if ONLY is None else "eyes_test.png")
    wear.grid_preview(built, out, dress, cols=7, cell=1.9, px=300, focus=4.68, yaw_front=180 - 15, yaw_back=180 + 25)


if __name__ == "__main__":
    styles = {k: v for k, v in STYLES.items() if ONLY is None or k in ONLY}
    built = {}
    for name, fn in styles.items():
        built[name] = wear.name_all("Eye_" + name, fn())
    rows, built = wear.fit_rows({k: (lambda v=v: v) for k, v in built.items()}, BUDGET)
    if not QUICK and ONLY is None:
        objs = [p.ob for ps in built.values() for p in ps]
        kit.export_fbx(objs, os.path.join(kit.ROOT, "export", "Eyes.fbx"))
        wear.write_fit("EyeArt", HEADER, rows)
    preview(built)
