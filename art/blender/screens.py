# screens.py: the in-city news screens as Blender meshes (gap-news, 2026-11-19). NewsService hangs the big news
# screens from plain parts (Shared.NewsPlan.screens: the plaza's own screen on its frame and legs, three Downtown
# towers' screens and the Crane billboard on Uptown's landmark). Once ReplicatedStorage.Art.News holds a look's
# meshes, the server draws them round the screen part and hides the plain frame and legs it stands for; the screen
# part itself stays exactly as it was (the news SurfaceGui draws on its front, a collapse still turns it dark) and
# nothing collides, takes queries or touches, as today (Shared.NewsArtKit). City kit style: bright comic colours,
# chunky bevelled shapes, low poly for phones, one baked texture set a look (art/blender/vkit.py: colour, normal,
# roughness, metalness; opaque, so the part colour never shows through). No words anywhere: the channel's name
# and the headlines stay UI text.
# Looks (each built in Roblox studs about the screen part's centre: x, up, z; front at -z, the wall behind at +z):
# * PlazaScreen (28 x 16 screen, 22 above the plaza): a chunky navy bezel with a gold rule and corner bolts, a back
#   casing with vents, a header with three lamps, the channel's lighthouse emblem and an on-air lamp, two pillars
#   with gold bands down to concrete plinths, a cross beam and two speaker cabinets
# * TowerScreen (36 x 20, flat on a Downtown tower's face): the bezel, a bulb marquee across the top, the emblem,
#   the on-air lamp, two lamp arms and a drip trim
# * UptownScreen (70 x 40, the Crane billboard on Uptown's landmark): a heavy bezel, a bulb marquee with two
#   emblems, five lamp arms over the top, a catwalk with rails and struts to the wall
# Output: art/export/News.fbx (textures embedded), art/export/news/<Look>_{Color,Normal,Roughness,Metalness}.png,
# src/config/ScreenArt.luau; with --preview, art/preview/news_screens.png (each look in place with a person for
# scale, the screen face showing a mock of the news SurfaceGui from build/news/mock.png when it is there).
# Run: python art/blender/screens.py [--preview] [--fast]   (the `bpy` module, Blender 5.0; `python3 art/news/mock.py`
# first for the preview's screen face)
import math
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import bpy  # noqa: E402
import numpy as np  # noqa: E402

kit.reset()

import vkit  # noqa: E402
from vkit import R, P, rbox  # noqa: E402
from studs import rb, C, S, T, TOR, turn, shift, copy  # noqa: E402

FAST = "--fast" in sys.argv
vkit.OUT = os.path.join(kit.ROOT, "export", "news")

# ---------------------------------------------------------------- the plain parts' numbers (Config.Cinema.news.screens;
# tests/news_art_test.luau checks they still match)
PLAZA = (28.0, 16.0)
PLAZA_HEIGHT = 22.0  # the screen's centre above the plaza
TOWER = (36.0, 20.0)
UPTOWN = (70.0, 40.0)
WALL = 1.0  # a tower or the landmark: its face 1 stud behind the screen's centre
LEG_X = 1.5  # today's legs stand this far in from the screen's sides

# ---------------------------------------------------------------- paint regions (vkit: one material each)
NAVY = R("navy", (30, 38, 92), 0.45, 0.15)
NAVYD = R("navyd", (20, 24, 56), 0.6, 0.1)
GOLD = R("gold", (244, 192, 58), 0.3, 0.9, "brushed")
RED = R("red", (214, 40, 52), 0.4, 0.05)
WHITE = R("white", (240, 240, 234), 0.45, 0.0)
STEEL = R("steel", (70, 76, 90), 0.4, 0.75, "brushed")
CONCRETE = R("concrete", (168, 162, 152), 0.92, 0.0, "concrete")
VENTS = R("vents", (40, 46, 80), 0.6, 0.3, ("slats", 2.4))
GRILLE = R("grille", (34, 36, 46), 0.6, 0.2, "grille")
GRATE = R("grate", (78, 84, 98), 0.5, 0.7, "grate")
LAMPH = R("lamph", (52, 56, 66), 0.45, 0.7)
SKY = R("sky", (90, 190, 240), 0.4, 0.0)

# ---------------------------------------------------------------- texture patterns on top of vkit's
_base_pattern = vkit._pattern


def _pattern(lk, pat, m, Pp, Nn, col, alpha, rough, height, noise):
    kind = pat[0] if isinstance(pat, tuple) else pat
    p = Pp[m]
    c = col[m]
    h = height[m]
    if kind == "brushed":
        a = p[:, 0] + p[:, 2]
        c *= (0.93 + 0.07 * np.sin(a * 47 + noise[m] * 9))[:, None]
    elif kind == "concrete":
        q = np.floor(p * 1.7)
        hsh = np.sin(q[:, 0] * 12.9898 + q[:, 1] * 78.233 + q[:, 2] * 37.719) * 43758.5453
        hsh = hsh - np.floor(hsh)
        soft = 0.5 + 0.25 * (np.sin(p[:, 0] * 1.7 + p[:, 2] * 0.9) + np.sin(p[:, 1] * 2.3 - p[:, 0] * 1.1))
        c *= (0.86 + 0.14 * soft)[:, None] * (0.94 + 0.06 * hsh)[:, None]
    elif kind == "grate":
        n = Nn[m]
        top = np.abs(n[:, 1]) > 0.6
        hole = top & (np.abs((p[:, 0] * 2.2) % 1 - 0.5) < 0.34) & (np.abs((p[:, 2] * 2.2) % 1 - 0.5) < 0.34)
        c[hole] *= 0.28
        h[hole] -= 0.7
    else:
        return _base_pattern(lk, pat, m, Pp, Nn, col, alpha, rough, height, noise)
    col[m] = c
    height[m] = h


vkit._pattern = _pattern


def bar(a, b, r, segs=8):
    return T([a, b], r, segs=segs)


def look(name, body, det=None, extra=None, res=512):
    lk = vkit.Look(name, name, False, body_rgb=(200, 200, 200), detail_rgb=(200, 200, 200))
    lk.res = res
    lk.add("Body", body)
    if det:
        lk.add("Detail", det)
    for (role, parts, rgb, mat, alpha) in extra or []:
        lk.add(role, parts, rgb, mat, alpha)
    return lk


# ---------------------------------------------------------------- shared pieces
def bezel(w, h, f, z0, z1, body, det, bev=0.25):
    """A chunky frame round a w x h opening (exactly the screen part's face), from z0 (front) to z1 (back); a gold
    rule just outside the opening on its front and gold bolts at the corners."""
    d, zc = z1 - z0, (z0 + z1) / 2
    body += [P(rbox(w + 2 * f, f, d, 0, h / 2 + f / 2, zc, bev=bev), NAVY),
             P(rbox(w + 2 * f, f, d, 0, -h / 2 - f / 2, zc, bev=bev), NAVY),
             P(rbox(f, h + 0.02, d, -w / 2 - f / 2, 0, zc, bev=bev), NAVY),
             P(rbox(f, h + 0.02, d, w / 2 + f / 2, 0, zc, bev=bev), NAVY)]
    r = min(0.35, f * 0.28)
    zr = z0 - 0.04
    det += [P(rbox(w + 2 * r, r, 0.12, 0, h / 2 + r / 2, zr, bev=0.03), GOLD),
            P(rbox(w + 2 * r, r, 0.12, 0, -h / 2 - r / 2, zr, bev=0.03), GOLD),
            P(rbox(r, h, 0.12, -w / 2 - r / 2, 0, zr, bev=0.03), GOLD),
            P(rbox(r, h, 0.12, w / 2 + r / 2, 0, zr, bev=0.03), GOLD)]
    for sx in (-1, 1):
        for sy in (-1, 1):
            det.append(P(C(f * 0.2, 0.16, sx * (w / 2 + f / 2), sy * (h / 2 + f / 2), z0 - 0.06, segs=10, axis="z"),
                         GOLD))


def emblem(x, y, z, r, det):
    """The channel's mark with no words: a gold disc, a sky ring, a navy lighthouse with a white band and a glowing
    lamp room, and two broadcast arcs (Brightharbor is a harbour town)."""
    det += [P(C(r, 0.2, x, y, z, segs=20, axis="z"), GOLD),
            P(C(r * 0.82, 0.12, x, y, z - 0.12, segs=20, axis="z"), SKY)]
    tower = C(r * 0.22, r * 1.05, 0, 0, 0, segs=8, r2=r * 0.13)
    det.append(P(shift(tower, rb(x, y - r * 0.42, z - 0.22)), NAVY))
    det.append(P(rbox(r * 0.36, r * 0.14, r * 0.36, x, y - r * 0.38, z - 0.26, bev=0.02), WHITE))
    det.append(P(rbox(r * 0.3, r * 0.22, r * 0.3, x, y + r * 0.22, z - 0.26, bev=0.02), RED))
    for k, rr in enumerate((r * 0.5, r * 0.68)):
        for s_ in (-1, 1):
            pts = []
            for i in range(5):
                a = math.radians(-35 + 70 * i / 4)
                pts.append((x + s_ * rr * math.cos(a), y + r * 0.22 + rr * math.sin(a), z - 0.24))
            det.append(P(T(pts, 0.06 + 0.02 * k, segs=6), WHITE))


def lamp_arm(x, top, reach, body, lens, tilt=30, size=(2.0, 0.6, 1.1)):
    """An arm from the top edge over to a lamp head tilted down at the screen."""
    arm = [(x, top, 0.3), (x, top + 1.6, 0.0), (x, top + 2.0, -reach * 0.5), (x, top + 1.7, -reach)]
    body.append(P(T(arm, 0.12, segs=6), STEEL))
    hd = rbox(size[0], size[1], size[2], 0, 0, 0, bev=0.1)
    turn(hd, "x", tilt)
    body.append(P(shift(hd, rb(x, top + 1.4, -reach - 0.3)), LAMPH))
    ln = rbox(size[0] - 0.3, 0.06, size[2] - 0.25, 0, 0, 0, bev=0)
    turn(ln, "x", tilt)
    lens.append(shift(ln, rb(x, top + 1.08, -reach - 0.4)))


def marquee(w, y0, hgt, z0, z1, body, det, bulbs, n):
    """A sign box over the bezel with a red band and a row of bulbs on its front, top and bottom."""
    d = z1 - z0
    body.append(P(rbox(w, hgt, d, 0, y0 + hgt / 2, (z0 + z1) / 2, bev=0.2), NAVYD))
    det.append(P(rbox(w - 0.6, hgt * 0.36, 0.1, 0, y0 + hgt / 2, z0 - 0.05, bev=0.03), RED))
    for row in (y0 + hgt * 0.14, y0 + hgt * 0.86):
        for i in range(n):
            x = -w / 2 + 0.8 + i * (w - 1.6) / (n - 1)
            bulbs.append(S(min(0.26, hgt * 0.08), x, row, z0 - 0.12, segs=6, rings=4))


# ================================================================ the plaza's screen on its own frame
w, h = PLAZA
F = 1.3
body, det, lens, bulbs, onair = [], [], [], [], []
bezel(w, h, F, -0.7, 1.1, body, det)
body.append(P(rbox(w + 2 * F - 0.4, h + 2 * F - 0.4, 0.5, 0, 0, 1.3, bev=0.15), VENTS))  # the back casing
top = h / 2 + F
body.append(P(rbox(w * 0.66, 3.0, 1.4, 0, top + 1.5, 0.25, bev=0.25), NAVYD))  # the header
det.append(P(rbox(w * 0.66 - 5.6, 0.7, 0.1, 0, top + 1.5, -0.5, bev=0.02), RED))
det.append(P(rbox(w * 0.66 - 0.6, 0.2, 0.1, 0, top + 2.75, -0.5, bev=0.02), GOLD))
det.append(P(rbox(w * 0.66 - 0.6, 0.2, 0.1, 0, top + 0.25, -0.5, bev=0.02), GOLD))
emblem(-w * 0.33 + 1.6, top + 1.5, -0.5, 1.35, det)
onair.append(S(0.5, w * 0.33 - 1.5, top + 1.5, -0.55, segs=10, rings=6))
det.append(P(C(0.75, 0.2, w * 0.33 - 1.5, top + 1.5, -0.48, segs=12, axis="z"), STEEL))
for x in (-w * 0.3, 0.0, w * 0.3):
    lamp_arm(x, top + 3.0, 2.2, body, lens)
leg_h = PLAZA_HEIGHT - h / 2  # down to the plaza
gy = -PLAZA_HEIGHT
for s_ in (-1, 1):
    x = s_ * (w / 2 - LEG_X)
    yc = -h / 2 - leg_h / 2
    body.append(P(rbox(1.8, leg_h, 1.8, x, yc, 0.8, bev=0.2), NAVY))
    body.append(P(rbox(3.4, 1.2, 3.4, x, gy + 0.6, 0.8, bev=0.2), CONCRETE))
    body.append(P(rbox(2.4, 0.5, 2.4, x, gy + 1.45, 0.8, bev=0.12), NAVYD))
    for yy in (gy + 4.0, gy + 7.5):
        det.append(P(rbox(2.0, 0.4, 2.0, x, yy, 0.8, bev=0.08), GOLD))
    # a speaker cabinet on each pillar's outer side, angled a touch toward the plaza's centre
    cab = rbox(2.4, 3.6, 1.8, 0, 0, 0, bev=0.2)
    P(cab, NAVYD)
    face = rbox(2.0, 3.1, 0.1, 0, 0, -0.92, bev=0)
    P(face, GRILLE)
    for ob in (cab, face):
        turn(ob, "up", -s_ * 12)
        shift(ob, rb(x + s_ * 2.0, -h / 2 - 3.2, 0.6))
    body.append(cab)
    det.append(face)
body.append(P(rbox(w - 2 * LEG_X + 1.2, 1.0, 1.0, 0, -h / 2 - F - 0.6, 0.8, bev=0.15), NAVYD))  # the cross beam
PLAZA_LK = look("PlazaScreen", body, det, [("Lamps", lens, (255, 240, 200), "Neon", 0.0),
                                          ("OnAir", onair, (255, 60, 60), "Neon", 0.0)])

# ================================================================ a Downtown tower's screen (flat on its face)
w, h = TOWER
F = 1.4
body, det, lens, bulbs, onair = [], [], [], [], []
bezel(w, h, F, -0.7, 0.95, body, det)
body.append(P(rbox(w + 2 * F - 0.4, h + 2 * F - 0.4, 0.3, 0, 0, 0.8, bev=0.1), NAVYD))  # the back plate
top = h / 2 + F
marquee(w + 2 * F - 6.0, top, 3.0, -0.6, 0.95, body, det, bulbs, 12)
for s_ in (-1, 1):  # round end caps on the marquee: the emblem on the left, the on-air lamp on the right
    body.append(P(C(1.9, 1.5, s_ * (w / 2 + F - 1.9), top + 1.5, 0.2, segs=20, axis="z"), NAVYD))
    det.append(P(TOR(1.85, 0.16, s_ * (w / 2 + F - 1.9), top + 1.5, -0.6, axis="z", segs=20, csegs=5), GOLD))
emblem(-(w / 2 + F - 1.9), top + 1.5, -0.62, 1.5, det)
onair.append(S(0.8, w / 2 + F - 1.9, top + 1.5, -0.62, segs=10, rings=6))
for x in (-w * 0.25, w * 0.25):
    lamp_arm(x, top + 3.0, 2.6, body, lens)
for i in range(7):  # the drip trim under the bezel
    x = -w / 2 + i * w / 6
    det.append(P(rbox(1.4, 0.7, 0.5, x, -h / 2 - F - 0.35, -0.3, bev=0.12), GOLD if i % 2 == 0 else RED))
TOWER_LK = look("TowerScreen", body, det, [("Lamps", lens, (255, 240, 200), "Neon", 0.0),
                                          ("Bulbs", bulbs, (255, 226, 130), "Neon", 0.0),
                                          ("OnAir", onair, (255, 60, 60), "Neon", 0.0)])

# ================================================================ Uptown's landmark billboard
w, h = UPTOWN
F = 2.6
body, det, lens, bulbs, onair = [], [], [], [], []
bezel(w, h, F, -0.9, 0.95, body, det, bev=0.35)
body.append(P(rbox(w + 2 * F - 0.6, h + 2 * F - 0.6, 0.3, 0, 0, 0.8, bev=0.1), NAVYD))
top = h / 2 + F
marquee(w * 0.66, top, 4.4, -0.8, 0.95, body, det, bulbs, 20)
for s_ in (-1, 1):
    ex = s_ * (w * 0.33 + 3.6)
    body.append(P(C(3.6, 1.6, ex, top + 2.6, 0.15, segs=24, axis="z"), NAVYD))
    det.append(P(TOR(3.5, 0.22, ex, top + 2.6, -0.7, axis="z", segs=24, csegs=5), GOLD))
    emblem(ex, top + 2.6, -0.72, 2.9, det)
onair.append(S(0.7, w * 0.33 - 1.6, top + 2.2, -1.0, segs=10, rings=6))
for x in (-28.0, -14.0, 0.0, 14.0, 28.0):
    lamp_arm(x, top + (4.4 if abs(x) < w * 0.33 else 0.0), 4.6, body, lens, size=(2.4, 0.75, 1.3))
cw_y, cw_d = -h / 2 - F - 0.4, 4.6  # the catwalk under the bezel
body.append(P(rbox(w + 2.0, 0.3, cw_d, 0, cw_y, 0.95 - cw_d / 2, bev=0.05), GRATE))
for i in range(15):
    x = -w / 2 - 0.6 + i * (w + 1.2) / 14
    body.append(P(bar((x, cw_y, 0.95 - cw_d + 0.1), (x, cw_y + 3.0, 0.95 - cw_d + 0.1), 0.09, segs=6), STEEL))
    if i % 2 == 0:
        body.append(P(bar((x, cw_y - 0.1, 0.95 - cw_d + 0.4), (x, cw_y - 4.6, 0.8), 0.15, segs=6), STEEL))
for yy, r in ((cw_y + 3.0, 0.11), (cw_y + 1.5, 0.07)):
    body.append(P(bar((-w / 2 - 0.6, yy, 0.95 - cw_d + 0.1), (w / 2 + 0.6, yy, 0.95 - cw_d + 0.1), r, segs=8), STEEL))
det.append(P(rbox(w + 2.0, 0.4, 0.08, 0, cw_y + 0.36, 0.95 - cw_d), GOLD))
UPTOWN_LK = look("UptownScreen", body, det, [("Lamps", lens, (255, 240, 200), "Neon", 0.0),
                                            ("Bulbs", bulbs, (255, 226, 130), "Neon", 0.0),
                                            ("OnAir", onair, (255, 60, 60), "Neon", 0.0)], res=1024)

LOOKS = vkit.LOOKS


# ================================================================ bake, the fit table and the export
def bounds(ob):
    vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
    lo = [min(v[i] for v in vs) for i in range(3)]
    hi = [max(v[i] for v in vs) for i in range(3)]
    return lo, hi


MAPS = {}
for name, lk in LOOKS.items():
    print("baking", name, flush=True)
    vkit.RES = 512 if FAST else lk.res
    MAPS[name] = vkit.bake_look(lk, ao_samples=8 if FAST else 24)

TRIS = {}
total = 0
rows = []
for name in sorted(LOOKS):
    lk = LOOKS[name]
    rows.append("\t%s = {" % name)
    for mname in sorted(lk.meshes):
        ob = lk.meshes[mname]
        lo, hi = bounds(ob)
        c = [(lo[i] + hi[i]) / 2 for i in range(3)]
        size = [hi[i] - lo[i] for i in range(3)]
        t = kit.tris(ob)
        TRIS[mname] = t
        total += t
        textured = ob in lk.textured()
        if textured:
            rgb, mat, alpha = (200, 200, 200), "SmoothPlastic", 0.0
        else:
            rgb, mat, alpha = lk.extra[mname]
        extra = (", alpha = %g" % alpha) if alpha else ""
        extra += ", maps = true" if textured else ""
        rows.append("\t\t%s = { size = { %.3f, %.3f, %.3f }, offset = { %.3f, %.3f, %.3f }, color = { %d, %d, %d }, mat = \"%s\"%s, tris = %d },"
                    % (mname, max(size[0], 0.05), max(size[2], 0.05), max(size[1], 0.05), c[0], c[2], -c[1], rgb[0], rgb[1],
                       rgb[2], mat, extra, t))
    rows.append("\t},")
print("screens: %d looks, %d meshes, %d tris" % (len(LOOKS), len(TRIS), total))
for name in sorted(LOOKS):
    lk = LOOKS[name]
    print("  %-13s %5d tris  (%s)" % (name, sum(TRIS[n] for n in lk.meshes), ", ".join(
        "%s %d" % (n[len(lk.prefix):], TRIS[n]) for n in sorted(lk.meshes))))

text = "\n".join([
    "-- GENERATED by art/blender/screens.py: do not edit by hand.",
    "-- The big news screens' Blender meshes (ReplicatedStorage.Art.News; Shared.NewsArtKit, NewsService): look -> mesh",
    "-- -> its size and its centre from the screen part's centre, in that part's studs (x, up, z; front at -z), its",
    "-- colour, material, transparency, maps (a baked texture set in its SurfaceAppearance) and triangles.",
    "-- %d meshes in %d looks, %d triangles." % (len(TRIS), len(LOOKS), total),
    "return {",
] + rows + ["}", ""])
FIT = os.path.normpath(os.path.join(kit.ROOT, "..", "src", "config", "ScreenArt.luau"))
with open(FIT, "w") as f:
    f.write(text)
_stylua = shutil.which("stylua") or os.path.expanduser("~/tools/stylua")
if os.path.exists(_stylua):
    subprocess.run([_stylua, "--config-path", os.path.join(os.path.dirname(FIT), "..", "..", "stylua.toml"), FIT],
                   check=False)

export = []
for name, lk in LOOKS.items():
    pm = vkit.export_material(lk, MAPS[name])
    for mname, ob in lk.meshes.items():
        cp = copy(ob)
        cp.name = mname + "_x"
        kit.centre(cp)
        cp.name = mname
        cp.data.name = mname
        cp.data.materials.clear()
        if ob in lk.textured():
            cp.data.materials.append(pm)
        else:
            rgb, mat, alpha = lk.extra[mname]
            cp.data.materials.append(kit.material(mname + "Mat", rgb))
        export.append(cp)
bpy.ops.object.select_all(action="DESELECT")
for o in export:
    o.select_set(True)
bpy.ops.export_scene.fbx(
    filepath=os.path.join(kit.ROOT, "export", "News.fbx"), use_selection=True,
    apply_scale_options="FBX_SCALE_ALL", axis_forward="-Z", axis_up="Y", object_types={"MESH"},
    use_mesh_modifiers=True, mesh_smooth_type="FACE", add_leaf_bones=False, bake_anim=False,
    path_mode="COPY", embed_textures=True)
for cp in export:
    bpy.data.objects.remove(cp, do_unlink=True)

# ================================================================ previews
if "--preview" in sys.argv:
    import vpreview as vp  # noqa: E402

    PREV = os.path.join(kit.ROOT, "preview")
    MOCK = os.path.join(os.path.dirname(kit.ROOT), "build", "news", "mock.png")
    vp._scene(FAST, (640, 420) if FAST else (1000, 660))
    for o in bpy.context.scene.objects:
        if o.type == "MESH":
            o.hide_render = True
    mats = {name: vp._mat_textured(name, MAPS[name]) for name in LOOKS}

    def flat(rgb, kind="SmoothPlastic", alpha=0.0):
        return vp._mat_flat(tuple(rgb), kind, alpha)

    def blk(sx, sy, sz, x, y, z, rgb, kind="SmoothPlastic", alpha=0.0):
        o = vp._keep(kit.box("blk", sx, sz, sy, at=rb(x, y, z)))
        o.data.materials.append(flat(rgb, kind, alpha))
        return o

    def screen(sw, sh, x, y, z):
        """The screen part (0.6 thick) and, on its front, the news SurfaceGui's mock (glowing like Brightness 1.6)."""
        blk(sw, sh, 0.6, x, y, z, (16, 18, 28))
        bpy.ops.mesh.primitive_plane_add(size=1)
        o = bpy.context.active_object
        o.scale = (-sw, sh, 1)
        o.rotation_euler = (math.radians(90), 0, 0)
        o.location = rb(x, y, z - 0.31)
        m = bpy.data.materials.new("mock")
        m.use_nodes = True
        nt = m.node_tree
        em = nt.nodes.new("ShaderNodeEmission")
        em.inputs["Strength"].default_value = 1.2
        if os.path.isfile(MOCK):
            t = nt.nodes.new("ShaderNodeTexImage")
            t.image = bpy.data.images.load(MOCK)
            nt.links.new(t.outputs["Color"], em.inputs["Color"])
        else:
            em.inputs["Color"].default_value = (0.02, 0.03, 0.08, 1)
        nt.links.new(em.outputs["Emission"], nt.nodes["Material Output"].inputs["Surface"])
        o.data.materials.append(m)
        vp._keep(o)

    def place(name, at=(0, 0, 0)):
        vp._place(LOOKS[name], mats, at=at)

    shots = []
    # the plaza screen on the plaza, two people for scale
    vp._ground(300, (176, 170, 160))
    pw, ph = PLAZA
    screen(pw, ph, 0, PLAZA_HEIGHT, 0)
    place("PlazaScreen", (0, PLAZA_HEIGHT, 0))
    vp._hero(-6, 0, -8, yaw=180)
    vp._hero(4, 0, -12, yaw=160)
    vp._camera((16, 12, -52), (0, 17, 0), lens=30)
    out = os.path.join(PREV, "news_plaza.png")
    kit.render(out)
    shots.append(out)
    vp._camera((-30, 22, 26), (0, 16, 0), lens=30)  # from behind: the casing and vents
    out = os.path.join(PREV, "news_plaza_back.png")
    kit.render(out)
    shots.append(out)
    vp._camera((4, 32, -16), (0, 33, 0), lens=40)  # the header close: emblem, on-air lamp, lamps
    out = os.path.join(PREV, "news_plaza_head.png")
    kit.render(out)
    shots.append(out)
    vp._clear()

    # a tower's screen on its face
    vp._ground(400, (110, 112, 118))
    tw_, th_ = TOWER
    blk(60, 120, 40, 0, 60, WALL + 20, (176, 168, 156), "Concrete")
    for i in range(-2, 3):
        for j in range(1, 9):
            if not (abs(i * 11) < 24 and 30 < 12 * j < 70):
                blk(6, 7, 0.3, i * 11, 12 * j, WALL - 0.1, (112, 160, 210), "Glass")
    screen(tw_, th_, 0, 50, 0)
    place("TowerScreen", (0, 50, 0))
    vp._camera((26, 38, -60), (0, 51, 0), lens=34)
    out = os.path.join(PREV, "news_tower.png")
    kit.render(out)
    shots.append(out)
    vp._camera((-6, 58, -16), (-14, 62, 0), lens=36)  # its marquee end close
    out = os.path.join(PREV, "news_tower_head.png")
    kit.render(out)
    shots.append(out)
    vp._clear()

    # Uptown's landmark billboard
    vp._ground(600, (110, 112, 118))
    uw, uh = UPTOWN
    blk(110, 160, 40, 0, 80, WALL + 20, (150, 120, 168), "Concrete")
    screen(uw, uh, 0, 80, 0)
    place("UptownScreen", (0, 80, 0))
    vp._hero(10, 80 - uh / 2 - 2.2 - 0.25, -2.0)
    vp._camera((40, 62, -120), (0, 80, 0), lens=34)
    out = os.path.join(PREV, "news_uptown.png")
    kit.render(out)
    shots.append(out)
    vp._clear()

    code = (
        "import sys\nfrom PIL import Image\n"
        "ims=[Image.open(p).convert('RGB') for p in sys.argv[2:]]\n"
        "w,h=ims[0].size; cols=2; rows=(len(ims)+1)//2\n"
        "sheet=Image.new('RGB',(cols*w,rows*h),(24,26,32))\n"
        "for i,im in enumerate(ims): sheet.paste(im.resize((w,h)),((i%cols)*w,(i//cols)*h))\n"
        "sheet.save(sys.argv[1])\n"
    )
    subprocess.run(["python3", "-c", code, os.path.join(PREV, "news_screens.png")] + shots, check=True)
    for p_ in shots:
        os.remove(p_)
    print("preview:", os.path.join(PREV, "news_screens.png"))
