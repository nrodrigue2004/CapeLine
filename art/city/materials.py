# materials.py: the city kit's tiling textures (overhaul plan step 3, "one Downtown block"; the whole city in
# step 5). Each is a seamless PBR set for a MaterialVariant: a colour map, a normal map and a roughness map
# (and metalness for the curtain wall), 512 px, drawn from code with numpy so it can be rebuilt and tweaked.
# Building fronts are one storey bay each (12 x 12 studs, Config.City.kit.studsPerTile): the windows are in the
# texture, so a plain box reads as a building. Colours are painted in (kit parts are white so nothing tints).
#   Brick      red brick, two tall windows with stone sills and lintels
#   Office     concrete panels with a ribbon window
#   Curtain    a glass curtain wall with steel mullions and a dark spandrel at each floor (towers)
#   Stone      sandstone blocks, two windows with keystones
#   Paving     sidewalk slabs (4-stud slabs, the tile is 8 studs)
#   Asphalt    road surface with grit and patches (16 studs)
# Output: art/export/city/<Name>_Color.png, _Normal.png, _Roughness.png (+ Curtain_Metalness.png) and
# art/preview/city_materials.png (a contact sheet). Run: python3 art/city/materials.py
import os

import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "export", "city")
os.makedirs(OUT, exist_ok=True)
N = 512
rng = np.random.default_rng(20261117)

Y, X = np.mgrid[0:N, 0:N].astype(np.float32)


def noise(cells, octaves=3):
    """Seamless value noise in 0..1 (tiles because the lattice wraps)."""
    out = np.zeros((N, N), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        c = cells * (2 ** o)
        g = rng.random((c, c)).astype(np.float32)
        u = X / N * c
        v = Y / N * c
        x0, y0 = np.floor(u).astype(int), np.floor(v).astype(int)
        fx, fy = u - x0, v - y0
        fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
        x1, y1 = (x0 + 1) % c, (y0 + 1) % c
        x0, y0 = x0 % c, y0 % c
        a = g[y0, x0] * (1 - fx) + g[y0, x1] * fx
        b = g[y1, x0] * (1 - fx) + g[y1, x1] * fx
        out += (a * (1 - fy) + b * fy) * amp
        tot += amp
        amp *= 0.5
    return out / tot


def rect(x0, y0, x1, y1, studs):
    """A mask for a rectangle given in studs from the bottom-left of a tile `studs` wide (y up)."""
    s = N / studs
    xa, xb = x0 * s, x1 * s
    ya, yb = N - y1 * s, N - y0 * s
    return (X >= xa) & (X < xb) & (Y >= ya) & (Y < yb)


def rgb(c):
    return np.array(c, np.float32) / 255


class Tex:
    def __init__(self):
        self.col = np.zeros((N, N, 3), np.float32)
        self.h = np.zeros((N, N), np.float32)
        self.r = np.full((N, N), 0.8, np.float32)
        self.m = np.zeros((N, N), np.float32)

    def paint(self, mask, color, height=None, rough=None, metal=None, vary=None):
        c = rgb(color)
        if vary is not None:
            self.col[mask] = np.clip(c[None, :] * vary[mask][:, None], 0, 1)
        else:
            self.col[mask] = c
        if height is not None:
            self.h[mask] = height
        if rough is not None:
            self.r[mask] = rough
        if metal is not None:
            self.m[mask] = metal

    def save(self, name, strength=6.0, metal=False, grime=0.12):
        # soft dirt toward the bottom of each tile and fine grain, then the maps
        g = noise(6, 4)
        col = self.col * (1 - grime * (g[..., None] - 0.5) * 2 * 0.5)
        col = np.clip(col, 0, 1)
        dx = (np.roll(self.h, -1, 1) - np.roll(self.h, 1, 1)) * strength
        dy = (np.roll(self.h, 1, 0) - np.roll(self.h, -1, 0)) * strength
        n = np.dstack([-dx, -dy, np.ones_like(dx)])
        n /= np.linalg.norm(n, axis=2, keepdims=True)
        Image.fromarray((col * 255 + 0.5).astype(np.uint8)).save(os.path.join(OUT, name + "_Color.png"))
        Image.fromarray(((n * 0.5 + 0.5) * 255 + 0.5).astype(np.uint8)).save(os.path.join(OUT, name + "_Normal.png"))
        Image.fromarray((np.clip(self.r, 0, 1) * 255 + 0.5).astype(np.uint8)).save(os.path.join(OUT, name + "_Roughness.png"))
        if metal:
            Image.fromarray((np.clip(self.m, 0, 1) * 255 + 0.5).astype(np.uint8)).save(os.path.join(OUT, name + "_Metalness.png"))
        return col


def window(t, x0, y0, x1, y1, studs, frame=(232, 230, 222), mull=True):
    """A window: a painted frame, dark glass with a sky reflection, a cross mullion."""
    fw = 0.22
    t.paint(rect(x0, y0, x1, y1, studs), frame, height=0.35, rough=0.5)
    gl = rect(x0 + fw, y0 + fw, x1 - fw, y1 - fw, studs)
    s = N / studs
    v = np.clip((Y - (N - y1 * s)) / ((y1 - y0) * s), 0, 1)  # 0 at the top of the window
    sky = np.dstack([0.32 - 0.18 * v, 0.42 - 0.2 * v, 0.55 - 0.22 * v])
    streak = (np.sin((X + Y * 0.6) / N * 40) > 0.85) * 0.06
    t.col[gl] = np.clip(sky[gl] + streak[gl][:, None], 0, 1)
    t.h[gl] = 0.0
    t.r[gl] = 0.08
    if mull:
        mx = (x0 + x1) / 2
        my = y0 + (y1 - y0) * 0.62
        t.paint(rect(mx - 0.08, y0, mx + 0.08, y1, studs) & rect(x0, y0, x1, y1, studs), frame, 0.3, 0.5)
        t.paint(rect(x0, my - 0.08, x1, my + 0.08, studs), frame, 0.3, 0.5)


sheet = {}

# ---------------------------------------------------------------- Brick: one 12 x 12 storey bay
t = Tex()
course, brick, mortar = 0.27, 0.85, 0.05
row = np.floor((N - 1 - Y) / (N / 12 / course * 1.0) * 1).astype(int)
S = N / 12
rowi = np.floor((N - 1 - Y) / (course * S)).astype(int)
off = (rowi % 2) * brick * S / 2
coli = np.floor((X + off) / (brick * S)).astype(int)
bid = (rowi * 131 + coli * 17) % 97
tone = 0.82 + 0.3 * ((bid * 37) % 23) / 23.0
my = ((N - 1 - Y) % (course * S)) < mortar * S
mx = ((X + off) % (brick * S)) < mortar * S
mortar_m = my | mx
t.paint(~mortar_m, (150, 72, 54), height=0.25, rough=0.85, vary=tone + (noise(24) - 0.5) * 0.25)
t.paint(mortar_m, (176, 168, 156), height=0.0, rough=0.9)
for wx in (3.0, 9.0):
    t.paint(rect(wx - 2.0, 3.0, wx + 2.0, 3.4, 12), (205, 196, 178), 0.55, 0.7)  # sill
    t.paint(rect(wx - 1.9, 9.0, wx + 1.9, 9.5, 12), (205, 196, 178), 0.5, 0.7)  # lintel
    window(t, wx - 1.6, 3.4, wx + 1.6, 9.0, 12)
t.paint(rect(0, 0, 12, 0.5, 12), (196, 188, 170), 0.45, 0.75)  # the floor band (cornice)
sheet["Brick"] = t.save("Brick")

# ---------------------------------------------------------------- Office: concrete panels, a ribbon window
t = Tex()
base = 0.9 + (noise(5) - 0.5) * 0.18
t.paint(np.ones((N, N), bool), (196, 194, 188), height=0.3, rough=0.8, vary=base)
for jx in (0.0, 6.0):
    t.paint(rect(jx, 0, jx + 0.08, 12, 12) | rect(jx + 11.94 - jx, 0, 12, 12, 12), (120, 118, 114), 0.1)
t.paint(rect(0, 0, 12, 0.08, 12) | rect(0, 11.92, 12, 12, 12), (120, 118, 114), 0.1)
t.paint(rect(0, 3.6, 12, 8.8, 12), (60, 64, 70), 0.15, 0.4)  # the ribbon's recess
for k in range(4):
    x0 = k * 3.0
    window(t, x0 + 0.1, 3.8, x0 + 2.9, 8.6, 12, frame=(70, 74, 80), mull=False)
# rain streaks under the ribbon
fall = np.clip(1 - ((N - Y) / N * 12 - 0.5) / 3.1, 0, 1)  # strongest right under the ribbon
streak = (0.5 + 0.5 * np.sin(X / N * 2 * np.pi * 37 + noise(8) * 6)) ** 6
under = rect(0, 0.5, 12, 3.6, 12)
t.col[under] *= (1 - 0.14 * (streak * fall)[under])[:, None]
sheet["Office"] = t.save("Office")

# ---------------------------------------------------------------- Curtain: glass and steel (towers)
t = Tex()
pid = (np.floor(X / (N / 4)).astype(int) * 7 + np.floor(Y / (N / 3)).astype(int) * 3) % 11
tint = 0.9 + 0.2 * pid / 11.0
v = (Y % (N / 3)) / (N / 3)
glass = np.dstack([0.18 + 0.12 * v, 0.3 + 0.14 * v, 0.42 + 0.12 * v]) * tint[..., None]
t.col[:] = np.clip(glass, 0, 1)
t.r[:] = 0.06
t.h[:] = 0.0
t.paint(rect(0, 0, 12, 1.1, 12), (40, 46, 56), 0.05, 0.35)  # the spandrel at the floor
mull = np.zeros((N, N), bool)
for k in range(5):
    mull |= rect(k * 3.0 - 0.11, 0, k * 3.0 + 0.11, 12, 12)
for k in range(4):
    mull |= rect(0, k * 4.0 - 0.09, 12, k * 4.0 + 0.09, 12)
t.paint(mull, (178, 184, 192), height=0.4, rough=0.3, metal=1.0)
sheet["Curtain"] = t.save("Curtain", metal=True, grime=0.05)

# ---------------------------------------------------------------- Stone: sandstone blocks, keystone windows
t = Tex()
rowi = np.floor((N - 1 - Y) / (S * 1.0)).astype(int)
off = (rowi % 2) * S
coli = np.floor((X + off) / (2 * S)).astype(int)
bid = (rowi * 53 + coli * 29) % 61
tone = 0.9 + 0.16 * ((bid * 13) % 17) / 17.0
joint = (((N - 1 - Y) % S) < 0.07 * S) | (((X + off) % (2 * S)) < 0.07 * S)
t.paint(~joint, (214, 192, 152), height=0.3, rough=0.85, vary=tone + (noise(16) - 0.5) * 0.2)
t.paint(joint, (170, 152, 120), height=0.05, rough=0.9)
for wx in (3.0, 9.0):
    t.paint(rect(wx - 2.1, 2.7, wx + 2.1, 3.2, 12), (232, 218, 186), 0.6, 0.7)
    t.paint(rect(wx - 1.85, 3.2, wx + 1.85, 9.3, 12), (226, 210, 176), 0.5, 0.75)  # the surround
    t.paint(rect(wx - 0.45, 9.3, wx + 0.45, 10.2, 12), (236, 222, 190), 0.65, 0.7)  # keystone
    window(t, wx - 1.5, 3.3, wx + 1.5, 9.0, 12, frame=(90, 70, 52))
t.paint(rect(0, 0, 12, 0.6, 12), (230, 214, 180), 0.5, 0.75)
sheet["Stone"] = t.save("Stone")

# ---------------------------------------------------------------- Paving: 4-stud slabs (an 8-stud tile)
t = Tex()
slab = N / 2
sid = (np.floor(X / slab).astype(int) * 3 + np.floor(Y / slab).astype(int) * 5) % 7
tone = 0.92 + 0.1 * sid / 7.0
gap = ((X % slab) < 3) | ((Y % slab) < 3)
t.paint(~gap, (168, 166, 160), height=0.3, rough=0.85, vary=tone + (noise(20) - 0.5) * 0.18)
t.paint(gap, (110, 108, 104), height=0.0, rough=0.95)
spots = noise(10, 3)
t.col[~gap] *= (0.96 + 0.08 * spots[~gap])[:, None]
sheet["Paving"] = t.save("Paving", strength=4.0)

# ---------------------------------------------------------------- Asphalt: grit and patches (a 16-stud tile)
t = Tex()
grit = rng.random((N, N)).astype(np.float32)
patch = noise(3, 2)
base = 0.86 + (noise(32) - 0.5) * 0.14 + np.clip((patch - 0.6) * 0.5, 0, 0.04)
t.paint(np.ones((N, N), bool), (62, 64, 70), height=0.0, rough=0.9, vary=base)
t.h[:] = grit * 0.15
light = grit > 0.985
t.col[light] = rgb((120, 120, 124))
crack = (np.abs(noise(4, 3) - 0.5) < 0.004) & (noise(2, 1) > 0.6)
t.col[crack] *= 0.6
t.h[crack] = -0.2
sheet["Asphalt"] = t.save("Asphalt", strength=3.0, grime=0.04)

# ================================================================ step 5: the whole city (more fronts, the
# Docks, Old Town and the outskirts). "Tinted" sets are drawn light and neutral: the game keeps the part's
# colour on them (Config.City.kit.tinted), so one texture gives many coloured buildings.


def circle(cx, cy, r, studs):
    """A disc mask, centre and radius in studs (y up)."""
    s = N / studs
    return (X - cx * s) ** 2 + (Y - (N - cy * s)) ** 2 < (r * s) ** 2


def arch_window(t, x0, y0, x1, y1, studs, frame, panes=(2, 3)):
    """A round-headed window: a frame, glass and a glazing grid; (y1 is the top of the arch)."""
    r = (x1 - x0) / 2
    cx = (x0 + x1) / 2
    spring = y1 - r
    fw = 0.24
    outer = rect(x0, y0, x1, spring, studs) | (circle(cx, spring, r, studs) & rect(x0, spring, x1, y1, studs))
    t.paint(outer, frame, height=0.35, rough=0.5)
    gl = rect(x0 + fw, y0 + fw, x1 - fw, spring, studs) | (
        circle(cx, spring, r - fw, studs) & rect(x0, spring, x1, y1, studs)
    )
    s = N / studs
    v = np.clip((Y - (N - y1 * s)) / ((y1 - y0) * s), 0, 1)
    sky = np.dstack([0.34 - 0.18 * v, 0.44 - 0.2 * v, 0.58 - 0.22 * v])
    t.col[gl] = sky[gl]
    t.h[gl] = 0.0
    t.r[gl] = 0.08
    grid = np.zeros((N, N), bool)
    for k in range(1, panes[0]):
        x = x0 + (x1 - x0) * k / panes[0]
        grid |= rect(x - 0.06, y0, x + 0.06, y1, studs)
    for k in range(1, panes[1]):
        y = y0 + (spring - y0) * k / panes[1]
        grid |= rect(x0, y - 0.06, x1, y + 0.06, studs)
    t.paint(grid & gl, frame, 0.3, 0.5)


def shutters(t, x0, y0, x1, y1, studs, color):
    """Louvred shutters either side of a window."""
    w = (x1 - x0) * 0.42
    for a, b in ((x0 - w, x0), (x1, x1 + w)):
        t.paint(rect(a, y0, b, y1, studs), color, height=0.45, rough=0.7)
        s = N / studs
        slat = (((N - Y) / s * 4) % 1.0) < 0.22
        t.paint(rect(a + 0.12, y0 + 0.15, b - 0.12, y1 - 0.15, studs) & slat, tuple(int(c * 0.72) for c in color), 0.3)


def bricks(t, studs, course, length, color, mortar_color, tone_amp=0.3, mortar=0.05, height=0.25):
    """A running-bond brick field over the whole tile."""
    S = N / studs
    rowi = np.floor((N - 1 - Y) / (course * S)).astype(int)
    off = (rowi % 2) * length * S / 2
    coli = np.floor((X + off) / (length * S)).astype(int)
    bid = (rowi * 131 + coli * 17) % 97
    tone = 1 - tone_amp / 2 + tone_amp * ((bid * 37) % 23) / 23.0
    m = (((N - 1 - Y) % (course * S)) < mortar * S) | (((X + off) % (length * S)) < mortar * S)
    t.paint(~m, color, height=height, rough=0.85, vary=tone + (noise(24) - 0.5) * 0.2)
    t.paint(m, mortar_color, height=0.0, rough=0.9)


# ---------------------------------------------------------------- Deco: cream stone piers, bronze spandrels
t = Tex()
t.paint(np.ones((N, N), bool), (226, 214, 190), height=0.3, rough=0.8, vary=0.94 + (noise(12) - 0.5) * 0.12)
for px in (0.0, 6.0, 12.0):
    t.paint(rect(px - 0.7, 0, px + 0.7, 12, 12), (238, 228, 206), height=0.6, rough=0.75)
    t.paint(rect(px - 0.75, 0, px - 0.62, 12, 12) | rect(px + 0.62, 0, px + 0.75, 12, 12), (196, 182, 156), 0.4)
for wx in (3.0, 9.0):
    t.paint(rect(wx - 1.75, 0.2, wx + 1.75, 2.4, 12), (120, 86, 58), height=0.2, rough=0.45, metal=0.6)
    for k in range(3):  # chevrons on the spandrel
        cy = 0.7 + k * 0.55
        chev = (np.abs(X / (N / 12) - wx) * 0.5 + (N - Y) / (N / 12) > cy) & (
            np.abs(X / (N / 12) - wx) * 0.5 + (N - Y) / (N / 12) < cy + 0.18
        )
        t.paint(chev & rect(wx - 1.6, 0.3, wx + 1.6, 2.3, 12), (214, 170, 96), 0.35, 0.35, metal=0.8)
    window(t, wx - 1.6, 2.6, wx + 1.6, 11.2, 12, frame=(70, 66, 60))
t.paint(rect(0, 11.5, 12, 12, 12), (206, 192, 166), 0.5)
sheet["Deco"] = t.save("Deco")

# ---------------------------------------------------------------- Panel: white panels, teal fins, wide windows
t = Tex()
t.paint(np.ones((N, N), bool), (236, 238, 236), height=0.3, rough=0.6, vary=0.97 + (noise(6) - 0.5) * 0.06)
t.paint(rect(0, 0, 12, 0.06, 12) | rect(0, 2.94, 12, 3.06, 12), (180, 184, 184), 0.1)
window(t, 0.6, 3.6, 5.4, 10.6, 12, frame=(54, 60, 66), mull=False)
window(t, 6.6, 3.6, 11.4, 10.6, 12, frame=(54, 60, 66), mull=False)
t.paint(rect(5.65, 3.0, 6.35, 12, 12), (40, 176, 170), height=0.7, rough=0.4)  # the fin
t.paint(rect(0, 0.8, 12, 1.6, 12), (40, 176, 170), height=0.4, rough=0.4)  # the colour band
sheet["Panel"] = t.save("Panel", grime=0.06)

# ---------------------------------------------------------------- Warehouse: corrugated siding (tinted)
t = Tex()
rib = 0.5 + 0.5 * np.cos(X / (N / 12) * 2 * np.pi / 0.75)
t.paint(np.ones((N, N), bool), (226, 226, 222), rough=0.55, metal=0.5, vary=0.86 + 0.14 * rib)
t.h[:] = rib * 0.5
t.paint(rect(0, 0, 12, 0.7, 12), (150, 150, 146), 0.6, 0.6, metal=0.4)  # the base rail
for k in range(3):  # clerestory windows high up
    x0 = 0.6 + k * 4.0
    window(t, x0, 8.6, x0 + 2.8, 10.6, 12, frame=(200, 200, 196), mull=False)
t.paint(rect(0, 11.4, 12, 12, 12), (176, 176, 172), 0.6, 0.6, metal=0.4)
rust = np.clip((noise(8, 3) - 0.62) * 3, 0, 1) * np.clip((N - Y) / N * 1.6 - 0.2, 0, 1)
t.col *= 1 - 0.22 * rust[..., None] * np.array([0.2, 0.55, 0.8], np.float32)
sheet["Warehouse"] = t.save("Warehouse", metal=True, grime=0.1)

# ---------------------------------------------------------------- DockBrick: dark brick, big arched windows
t = Tex()
bricks(t, 12, 0.27, 0.85, (118, 58, 46), (90, 84, 78), tone_amp=0.34)
for wx in (3.0, 9.0):
    t.paint(rect(wx - 2.1, 1.8, wx + 2.1, 2.2, 12), (150, 140, 128), 0.5, 0.75)
    arch = circle(wx, 8.4, 2.3, 12) & rect(wx - 2.3, 8.4, wx + 2.3, 11, 12)
    t.paint(arch, (150, 76, 58), 0.45, 0.8)  # the brick arch
    arch_window(t, wx - 1.9, 2.2, wx + 1.9, 10.3, 12, frame=(54, 72, 66), panes=(3, 4))
sheet["DockBrick"] = t.save("DockBrick")

# ---------------------------------------------------------------- Quay: big concrete slabs, rust and joints
t = Tex()
slab = N / 2
sid = (np.floor(X / slab).astype(int) * 5 + np.floor(Y / slab).astype(int) * 3) % 5
t.paint(np.ones((N, N), bool), (182, 178, 168), height=0.3, rough=0.9, vary=0.9 + 0.06 * sid + (noise(10) - 0.5) * 0.16)
joint = ((X % slab) < 3) | ((Y % slab) < 3)
t.paint(joint, (96, 94, 90), height=0.0)
stain = np.clip((noise(4, 3) - 0.6) * 2.5, 0, 1)
t.col *= 1 - 0.25 * stain[..., None] * np.array([0.1, 0.35, 0.6], np.float32)
sheet["Quay"] = t.save("Quay", strength=4.0)

# ---------------------------------------------------------------- Container: corrugated box sides (tinted)
t = Tex()
s8 = N / 8
u = (X % (s8 * 1.0)) / s8  # one rib a stud
prof = np.clip(np.abs(u - 0.5) * 4 - 0.6, 0, 1)  # trapezoid ribs
t.paint(np.ones((N, N), bool), (236, 236, 232), rough=0.5, metal=0.3, vary=0.84 + 0.16 * prof)
t.h[:] = prof * 0.6
t.paint(rect(0, 0, 8, 0.35, 8) | rect(0, 7.65, 8, 8, 8), (200, 200, 196), 0.7, 0.5, metal=0.4)
scuff = np.clip((noise(10, 3) - 0.66) * 3, 0, 1)
t.col *= 1 - 0.18 * scuff[..., None]
sheet["Container"] = t.save("Container", metal=True, grime=0.06)

# ---------------------------------------------------------------- OldBrick: warm brick, white sash windows
t = Tex()
bricks(t, 12, 0.25, 0.8, (188, 104, 66), (222, 210, 190), tone_amp=0.36)
for wx in (3.0, 9.0):
    t.paint(rect(wx - 1.8, 2.8, wx + 1.8, 3.25, 12), (236, 232, 222), 0.55, 0.7)
    arch = circle(wx, 8.0, 2.0, 12) & rect(wx - 2.0, 8.0, wx + 2.0, 10.2, 12)
    t.paint(arch, (158, 82, 52), 0.4, 0.8)
    arch_window(t, wx - 1.5, 3.25, wx + 1.5, 9.6, 12, frame=(244, 242, 236), panes=(2, 3))
    t.paint(rect(wx - 1.7, 2.2, wx + 1.7, 2.8, 12), (92, 132, 70), 0.6, 0.8)  # flower box
    for k in range(5):
        t.paint(circle(wx - 1.4 + k * 0.7, 2.95, 0.22, 12), ((236, 86, 96), (255, 206, 72))[k % 2], 0.7, 0.8)
t.paint(rect(0, 0, 12, 0.45, 12), (226, 214, 196), 0.45, 0.75)
sheet["OldBrick"] = t.save("OldBrick")

# ---------------------------------------------------------------- Plaster: smooth render, shuttered windows (tinted)
t = Tex()
t.paint(np.ones((N, N), bool), (244, 242, 236), height=0.2, rough=0.9, vary=0.95 + (noise(10, 4) - 0.5) * 0.1)
for wx in (3.0, 9.0):
    t.paint(rect(wx - 1.5, 3.0, wx + 1.5, 9.4, 12), (252, 252, 250), 0.35, 0.8)  # the surround
    window(t, wx - 1.2, 3.3, wx + 1.2, 9.1, 12, frame=(250, 250, 248))
    shutters(t, wx - 1.5, 3.2, wx + 1.5, 9.2, 12, (150, 160, 170))
t.paint(rect(0, 0, 12, 0.5, 12), (214, 210, 202), 0.45, 0.8)
t.paint(rect(0, 11.6, 12, 12, 12), (226, 222, 214), 0.45, 0.8)
sheet["Plaster"] = t.save("Plaster", grime=0.1)

# ---------------------------------------------------------------- Timber: half-timbered plaster (tinted)
t = Tex()
t.paint(np.ones((N, N), bool), (246, 242, 230), height=0.2, rough=0.9, vary=0.95 + (noise(10, 4) - 0.5) * 0.1)
beam = (110, 76, 52)
wood = 0.9 + (noise(30, 2) - 0.5) * 0.2
for y0 in (0.0, 5.6, 11.4):
    t.paint(rect(0, y0, 12, y0 + 0.6, 12), beam, 0.6, 0.85, vary=wood)
for x in (0.0, 4.0, 8.0, 12.0):
    t.paint(rect(x - 0.3, 0, x + 0.3, 12, 12), beam, 0.6, 0.85, vary=wood)
S = N / 12
u, v = X / S, (N - Y) / S
for x in (4.0, 8.0):  # braces in the lower panels
    brace = (np.abs((u - x) - (v - 0.6) * 0.8) < 0.28) & rect(x, 0.6, x + 4, 5.6, 12)
    t.paint(brace, beam, 0.6, 0.85, vary=wood)
for wx in (2.0, 10.0, 6.0):  # windows up top
    window(t, wx - 1.1, 7.0, wx + 1.1, 10.4, 12, frame=(236, 230, 214))
window(t, 0.9, 1.6, 3.1, 4.6, 12, frame=(236, 230, 214))
sheet["Timber"] = t.save("Timber")

# ---------------------------------------------------------------- Cobble: rounded setts (an 8-stud tile)
t = Tex()
s8 = N / 8
rowc = np.floor(Y / (s8 * 0.8)).astype(int)
offc = (rowc % 2) * s8 * 0.55
colc = np.floor((X + offc) / (s8 * 1.1)).astype(int)
fu = ((X + offc) % (s8 * 1.1)) / (s8 * 1.1) - 0.5
fv = (Y % (s8 * 0.8)) / (s8 * 0.8) - 0.5
d = np.sqrt((fu * 1.0) ** 2 + (fv * 1.1) ** 2)
dome = np.clip(1 - d * 2.2, 0, 1) ** 0.6
cid = (rowc * 71 + colc * 13) % 29
tone = 0.82 + 0.3 * ((cid * 11) % 17) / 17.0
stone = dome > 0.05
t.paint(stone, (150, 144, 136), rough=0.8, vary=tone * (0.85 + 0.15 * dome) + (noise(20) - 0.5) * 0.1)
t.paint(~stone, (84, 80, 74), rough=0.95)
t.h[:] = dome * 0.8
sheet["Cobble"] = t.save("Cobble", strength=3.0, grime=0.08)

# ---------------------------------------------------------------- Flagstone: irregular big flags (8 studs)
t = Tex()
pts = rng.random((14, 2)).astype(np.float32) * N
dist = np.full((N, N), 1e9, np.float32)
second = np.full((N, N), 1e9, np.float32)
idx = np.zeros((N, N), int)
for i, (px, py) in enumerate(pts):
    for ox in (-N, 0, N):
        for oy in (-N, 0, N):
            dd = np.sqrt((X - px - ox) ** 2 + (Y - py - oy) ** 2)
            closer = dd < dist
            second = np.where(closer, dist, np.minimum(second, dd))
            idx = np.where(closer, i, idx)
            dist = np.where(closer, dd, dist)
edge = (second - dist) < 3.2
tone = 0.86 + 0.22 * ((idx * 7) % 13) / 13.0
t.paint(~edge, (196, 186, 168), height=0.3, rough=0.85, vary=tone + (noise(18) - 0.5) * 0.14)
t.paint(edge, (110, 104, 94), height=0.0, rough=0.95)
sheet["Flagstone"] = t.save("Flagstone", strength=4.0)

# ---------------------------------------------------------------- Siding: clapboard with two windows (tinted)
t = Tex()
board = ((N - 1 - Y) % (N / 12 * 0.6)) / (N / 12 * 0.6)
t.paint(np.ones((N, N), bool), (246, 246, 242), rough=0.75, vary=0.9 + 0.1 * board)
t.h[:] = board * 0.4
for wx in (3.0, 9.0):
    t.paint(rect(wx - 1.75, 3.1, wx + 1.75, 9.3, 12), (255, 255, 255), 0.5, 0.6)
    window(t, wx - 1.45, 3.4, wx + 1.45, 9.0, 12, frame=(255, 255, 255))
t.paint(rect(0, 0, 12, 0.6, 12), (200, 200, 196), 0.5, 0.8)
sheet["Siding"] = t.save("Siding", grime=0.06)

# ---------------------------------------------------------------- RoofTile: scalloped shingles (tinted, 6 studs)
t = Tex()
s6 = N / 6
rowr = np.floor(Y / (s6 * 0.5)).astype(int)
offr = (rowr % 2) * s6 * 0.375
fu = ((X + offr) % (s6 * 0.75)) / (s6 * 0.75)
fv = (Y % (s6 * 0.5)) / (s6 * 0.5)  # 0 at the top of a row
bottom = 0.55 + 0.45 * np.sqrt(np.clip(1 - (2 * fu - 1) ** 2, 0, 1))  # each tile's rounded lower edge
below = fv > bottom  # the shadow under a tile's round edge, on the tile beneath
side = (fu < 0.035) | (fu > 0.965)
rid = (rowr * 19 + np.floor((X + offr) / (s6 * 0.75)).astype(int) * 7) % 13
tone = 0.86 + 0.2 * rid / 13.0
t.paint(np.ones((N, N), bool), (238, 236, 232), rough=0.7, vary=tone * (1.04 - 0.16 * fv))
t.paint(below | (side & (fv < bottom)), (150, 148, 144), rough=0.85)
t.h[:] = np.where(below, 0.0, (1 - fv) * 0.6 + 0.2)
sheet["RoofTile"] = t.save("RoofTile", strength=3.0, grime=0.08)

# contact sheet for review (tinted sets shown in one of their game tints)
TINTS = {"Warehouse": (96, 170, 186), "Container": (214, 92, 62), "Plaster": (250, 214, 150),
         "Timber": (246, 226, 196), "Siding": (150, 196, 230), "RoofTile": (198, 88, 66)}
tiles = [(k, v) for k, v in sheet.items()]
cols = 5
img = Image.new("RGB", (cols * 210 + 10, ((len(tiles) + cols - 1) // cols) * 228 + 10), (40, 42, 48))
try:
    from PIL import ImageDraw
    draw = ImageDraw.Draw(img)
except Exception:
    draw = None
for i, (k, v) in enumerate(tiles):
    if k in TINTS:
        v = v * (np.array(TINTS[k], np.float32) / 255)
    im = Image.fromarray((np.clip(v, 0, 1) * 255).astype(np.uint8)).resize((200, 200))
    x, y = 10 + (i % cols) * 210, 10 + (i // cols) * 228
    img.paste(im, (x, y))
    if draw:
        draw.text((x, y + 203), k + (" (tinted)" if k in TINTS else ""), fill=(220, 220, 220))
img.save(os.path.join(ROOT, "preview", "city_materials.png"))
print("wrote", len(sheet), "materials to", OUT)
