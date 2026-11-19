# pocket_materials.py: the mission and side quest pockets' tiling textures (2026-11-19, the pocket kit pass), in
# the same cartoon kit style as art/city/materials.py (same helpers, 512 px PBR sets for MaterialVariants named
# "Kit" .. name). Every set is drawn light and neutral: the game keeps each part's own colour on it
# (Config.City.kit.tinted = false), so one texture dresses many pockets in their own palettes (Config.PocketKit).
#   Planks     floorboards in staggered lengths with nail dots (8 studs)
#   Tile       square ceramic tiles with grout and a soft glaze (8 studs, 2-stud tiles)
#   CaveRock   layered rock with cracks and lumps (16 studs)
#   Concrete   poured concrete panels with seams and form-tie dots (12 studs)
#   SteelPlate riveted steel panels with a brushed grain (8 studs; metalness)
#   Block      painted cinder block in stacked courses (8 studs)
#   Sand       packed sand with soft ripples and grit (16 studs)
#   Ashlar     big dressed stone blocks with chipped edges (12 studs)
#   Brickwork  plain running-bond brick, no windows (8 studs)
# Output: art/export/city/<Name>_Color.png, _Normal.png, _Roughness.png (+ SteelPlate_Metalness.png) and the
# contact sheet art/preview/pocket_materials.png. Run: python3 art/city/pocket_materials.py
import os

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "export", "city")
os.makedirs(OUT, exist_ok=True)
N = 512
rng = np.random.default_rng(20261119)
Y, X = np.mgrid[0:N, 0:N].astype(np.float32)


def noise(cells, octaves=3):
    """Seamless value noise in 0..1 (the lattice wraps, so it tiles)."""
    out = np.zeros((N, N), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        c = cells * (2 ** o)
        g = rng.random((c, c)).astype(np.float32)
        u, v = X / N * c, Y / N * c
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
            self.h[mask] = height if np.isscalar(height) else height[mask]
        if rough is not None:
            self.r[mask] = rough
        if metal is not None:
            self.m[mask] = metal

    def save(self, name, strength=6.0, metal=False, grime=0.1):
        g = noise(6, 4)
        col = np.clip(self.col * (1 - grime * (g[..., None] - 0.5)), 0, 1)
        dx = (np.roll(self.h, -1, 1) - np.roll(self.h, 1, 1)) * strength
        dy = (np.roll(self.h, 1, 0) - np.roll(self.h, -1, 0)) * strength
        n = np.dstack([-dx, -dy, np.ones_like(dx)])
        n /= np.linalg.norm(n, axis=2, keepdims=True)
        Image.fromarray((col * 255 + 0.5).astype(np.uint8)).save(os.path.join(OUT, name + "_Color.png"))
        Image.fromarray(((n * 0.5 + 0.5) * 255 + 0.5).astype(np.uint8)).save(os.path.join(OUT, name + "_Normal.png"))
        Image.fromarray((np.clip(self.r, 0, 1) * 255 + 0.5).astype(np.uint8)).save(
            os.path.join(OUT, name + "_Roughness.png")
        )
        if metal:
            Image.fromarray((np.clip(self.m, 0, 1) * 255 + 0.5).astype(np.uint8)).save(
                os.path.join(OUT, name + "_Metalness.png")
            )
        return col


def bevel(fu, fv, w):
    """0 at a cell's edge rising to 1 a width w inside it (fu, fv in 0..1 across the cell)."""
    e = np.minimum(np.minimum(fu, 1 - fu), np.minimum(fv, 1 - fv))
    return np.clip(e / w, 0, 1)


sheet = {}
ALL = np.ones((N, N), bool)

# ---------------------------------------------------------------- Planks: floorboards (8 studs, 8 boards)
t = Tex()
bw = N / 8  # one board a stud wide
row = np.floor(X / bw).astype(int)  # boards run along the texture's v
length = N / 2
off = ((row * 37) % 5) / 5.0 * length
fv = ((Y + off) % length) / length
seg = np.floor((Y + off) / length).astype(int)
bid = (row * 13 + seg * 7) % 11
tone = 0.84 + 0.22 * bid / 11.0
fu = (X % bw) / bw
grain = 0.5 + 0.5 * np.sin((X / bw * 9 + noise(10, 2) * 5 + row * 1.7) * np.pi)
gap = (fu < 0.05) | (fu > 0.95) | (fv < 0.012)
t.paint(~gap, (236, 226, 210), height=0.4 * bevel(fu, fv, 0.12) + 0.2, rough=0.6, vary=tone * (0.9 + 0.1 * grain))
t.paint(gap, (120, 108, 96), height=0.0, rough=0.9)
for k in range(8):  # two nail dots at each board's ends
    for s in range(2):
        cx = k * bw + bw * (0.3 + 0.4 * s)
        for e in range(2):
            cy = (((e * length) - ((k * 37) % 5) / 5.0 * length) + 10) % N
            d = (X - cx) ** 2 + (Y - cy) ** 2 < 9
            t.paint(d, (130, 120, 110), 0.1, 0.4)
sheet["Planks"] = t.save("Planks", strength=4.0)

# ---------------------------------------------------------------- Tile: 2-stud ceramic squares (8 studs)
t = Tex()
cell = N / 4
fu, fv = (X % cell) / cell, (Y % cell) / cell
tid = (np.floor(X / cell).astype(int) * 3 + np.floor(Y / cell).astype(int) * 5) % 7
tone = 0.95 + 0.06 * tid / 7.0
grout = (fu < 0.03) | (fu > 0.97) | (fv < 0.03) | (fv > 0.97)
glaze = 0.97 + 0.05 * (1 - np.abs(fu - 0.35) - np.abs(fv - 0.3)).clip(0, 1)
t.paint(~grout, (246, 246, 244), height=0.3 + 0.1 * bevel(fu, fv, 0.08), rough=0.2, vary=tone * glaze)
t.paint(grout, (176, 174, 170), height=0.0, rough=0.9)
sheet["Tile"] = t.save("Tile", strength=3.0, grime=0.05)

# ---------------------------------------------------------------- CaveRock: chunky rock facets (16 studs)
t = Tex()
pts = rng.random((22, 2)).astype(np.float32) * N
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
edge = second - dist
crack = edge < 2.5
tone = 0.8 + 0.24 * ((idx * 7) % 11) / 11.0
lump = noise(10, 4)
t.paint(~crack, (232, 226, 218), height=np.clip(edge / 40.0, 0, 1) * 0.6 + 0.2 * lump, rough=0.9,
        vary=tone + (lump - 0.5) * 0.18)
t.paint(crack, (120, 114, 108), height=0.0, rough=0.95)
sheet["CaveRock"] = t.save("CaveRock", strength=6.0, grime=0.12)

# ---------------------------------------------------------------- Concrete: poured panels, tie dots (12 studs)
t = Tex()
pw = N / 2
fu, fv = (X % pw) / pw, (Y % (N / 3)) / (N / 3)
pid = (np.floor(X / pw).astype(int) * 5 + np.floor(Y / (N / 3)).astype(int) * 3) % 6
base = 0.95 + 0.012 * pid + (noise(14, 4) - 0.5) * 0.1
t.paint(ALL, (226, 224, 220), height=0.3, rough=0.85, vary=base)
seam = (fu < 0.008) | (fu > 0.992) | (fv < 0.012)
t.paint(seam, (150, 148, 144), height=0.05)
for ix in range(2):
    for iy in range(3):
        for a in (0.25, 0.75):
            for b in (0.3, 0.7):
                cx, cy = (ix + a) * pw, (iy + b) * N / 3
                d = (X - cx) ** 2 + (Y - cy) ** 2 < 20
                t.paint(d, (160, 158, 154), 0.12, 0.9)
pits = rng.random((N, N)) > 0.996
t.col[pits] *= 0.75
sheet["Concrete"] = t.save("Concrete", strength=4.0)

# ---------------------------------------------------------------- SteelPlate: riveted panels (8 studs)
t = Tex()
pw = N / 2
fu, fv = (X % pw) / pw, (Y % pw) / pw
brushed = 0.94 + 0.06 * noise(64, 1)[:, :] * (0.5 + 0.5 * np.sin(Y / 3.0))
t.paint(ALL, (226, 228, 232), height=0.3 + 0.15 * bevel(fu, fv, 0.04), rough=0.42, metal=0.75, vary=brushed)
seam = (fu < 0.01) | (fu > 0.99) | (fv < 0.01) | (fv > 0.99)
t.paint(seam, (110, 112, 118), height=0.0, rough=0.6, metal=0.6)
for ix in range(2):
    for iy in range(2):
        for k in range(5):
            for side in range(4):
                s = 0.06 + 0.88 * k / 4
                cx, cy = [(s, 0.06), (s, 0.94), (0.06, s), (0.94, s)][side]
                px, py = (ix + cx) * pw, (iy + cy) * pw
                d2 = (X - px) ** 2 + (Y - py) ** 2
                dome = np.clip(1 - d2 / 30.0, 0, 1)
                m = d2 < 30
                t.paint(m, (236, 238, 242), height=0.3 + 0.5 * dome, rough=0.35, metal=0.8)
sheet["SteelPlate"] = t.save("SteelPlate", strength=5.0, metal=True, grime=0.08)

# ---------------------------------------------------------------- Block: painted cinder block (8 studs)
t = Tex()
bh, bl = N / 8 * 1.0, N / 8 * 2.0  # one stud high, two long, stacked bond
fu, fv = (X % bl) / bl, (Y % bh) / bh
bid = (np.floor(X / bl).astype(int) * 7 + np.floor(Y / bh).astype(int) * 3) % 9
tone = 0.95 + 0.05 * bid / 9.0
joint = (fu < 0.02) | (fu > 0.98) | (fv < 0.04) | (fv > 0.96)
pores = 0.97 + 0.06 * (rng.random((N, N)).astype(np.float32) - 0.5)
t.paint(~joint, (244, 242, 238), height=0.3 + 0.12 * bevel(fu, fv, 0.06), rough=0.85, vary=tone * pores)
t.paint(joint, (196, 194, 190), height=0.05, rough=0.9)
sheet["Block"] = t.save("Block", strength=4.0, grime=0.06)

# ---------------------------------------------------------------- Sand: packed sand, ripples (16 studs)
t = Tex()
rip = np.sin((X / N * 9 + noise(4, 3) * 2.2 + Y / N * 1.5) * 2 * np.pi)
grit = rng.random((N, N)).astype(np.float32)
t.paint(ALL, (240, 232, 214), height=0.15 * rip + 0.1 * grit, rough=0.95, vary=0.92 + 0.05 * rip + 0.05 * noise(24))
dark = grit > 0.985
t.col[dark] *= 0.8
sheet["Sand"] = t.save("Sand", strength=3.0, grime=0.08)

# ---------------------------------------------------------------- Ashlar: dressed stone blocks (12 studs)
t = Tex()
S = N / 12
rowi = np.floor(Y / (3 * S)).astype(int)
off = (rowi % 2) * 2.5 * S
coli = np.floor((X + off) / (5 * S)).astype(int)
fu = ((X + off) % (5 * S)) / (5 * S)
fv = (Y % (3 * S)) / (3 * S)
bid = (rowi * 31 + coli * 17) % 13
tone = 0.88 + 0.16 * bid / 13.0
joint = (fu < 0.012) | (fu > 0.988) | (fv < 0.02) | (fv > 0.98)
chip = noise(16, 3)
face = 0.35 + 0.2 * bevel(fu, fv, 0.05) + 0.1 * chip
t.paint(~joint, (240, 234, 224), height=face, rough=0.85, vary=tone + (noise(18) - 0.5) * 0.12)
t.paint(joint, (170, 164, 154), height=0.0, rough=0.95)
sheet["Ashlar"] = t.save("Ashlar", strength=5.0)

# ---------------------------------------------------------------- Brickwork: plain running bond (8 studs)
t = Tex()
S = N / 8
course, length = 0.4, 1.2
rowi = np.floor(Y / (course * S)).astype(int)
off = (rowi % 2) * length * S / 2
coli = np.floor((X + off) / (length * S)).astype(int)
fu = ((X + off) % (length * S)) / (length * S)
fv = (Y % (course * S)) / (course * S)
bid = (rowi * 131 + coli * 17) % 97
tone = 0.82 + 0.28 * ((bid * 37) % 23) / 23.0
m = (fv < 0.12) | (fu < 0.04)
t.paint(~m, (236, 226, 220), height=0.3 + 0.1 * bevel(fu, fv, 0.1), rough=0.85, vary=tone + (noise(24) - 0.5) * 0.15)
t.paint(m, (250, 248, 244), height=0.0, rough=0.9)
sheet["Brickwork"] = t.save("Brickwork", strength=4.0)

# contact sheet: each texture plain and in one of its pocket tints (the game multiplies the part's colour in)
TINTS = {
    "Planks": (196, 140, 92), "Tile": (180, 222, 236), "CaveRock": (128, 112, 100), "Concrete": (168, 166, 160),
    "SteelPlate": (120, 136, 160), "Block": (250, 230, 180), "Sand": (214, 190, 140), "Ashlar": (120, 176, 176),
    "Brickwork": (196, 92, 70),
}
cols = 3
img = Image.new("RGB", (cols * 420 + 10, ((len(sheet) + cols - 1) // cols) * 228 + 10), (40, 42, 48))
draw = ImageDraw.Draw(img)
for i, (k, v) in enumerate(sheet.items()):
    x, y = 10 + (i % cols) * 420, 10 + (i // cols) * 228
    img.paste(Image.fromarray((np.clip(v, 0, 1) * 255).astype(np.uint8)).resize((200, 200)), (x, y))
    tv = v * (np.array(TINTS[k], np.float32) / 255)
    img.paste(Image.fromarray((np.clip(tv, 0, 1) * 255).astype(np.uint8)).resize((200, 200)), (x + 205, y))
    draw.text((x, y + 203), k + " (plain, tinted)", fill=(220, 220, 220))
img.save(os.path.join(ROOT, "preview", "pocket_materials.png"))
print("wrote", len(sheet), "pocket materials to", OUT)
