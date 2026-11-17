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

# contact sheet for review
tiles = [(k, v) for k, v in sheet.items()]
img = Image.new("RGB", (3 * 260 + 20, 2 * 280 + 20), (40, 42, 48))
for i, (k, v) in enumerate(tiles):
    im = Image.fromarray((v * 255).astype(np.uint8)).resize((256, 256))
    img.paste(im, (10 + (i % 3) * 260, 10 + (i // 3) * 280))
img.save(os.path.join(ROOT, "preview", "city_materials.png"))
print("wrote", len(sheet), "materials to", OUT)
