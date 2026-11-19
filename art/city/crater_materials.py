# crater_materials.py: the Crater's ground (gap-fx3, 2026-11-19), in the cartoon kit style of art/city/materials.py
# and pocket_materials.py (512 px PBR sets for MaterialVariants named "Kit" .. name, MaterialPattern Organic so
# the big floor does not show a repeating grid). Unlike the pocket kit these are drawn in their own colours (the
# parts show white, Config.City.kit.landmark), because the Crater is one place with one look:
#   CraterFloor  the blasted floor: baked, cracked ash-brown plates, dark scorch blotches, pebbles and a few
#                glassy fused spots where the Spark blast melted the ground (32 studs, base Ground)
#   CraterRim    the upthrown rim: layered rock strata in dusty tans and rust, split by fractures, the top
#                layers scorched darker toward the blast (24 studs, base Rock)
# Output: art/export/city/<Name>_Color.png, _Normal.png, _Roughness.png and the preview
# art/preview/crater_ground.png (each texture, then both on a rendered cut of the floor meeting the rim).
# Run: python3 art/city/crater_materials.py
import os

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "export", "city")
os.makedirs(OUT, exist_ok=True)
N = 512
rng = np.random.default_rng(20261121)
Y, X = np.mgrid[0:N, 0:N].astype(np.float32)


def noise(cells, octaves=3):
    """Seamless value noise in 0..1 (the lattice wraps, so it tiles)."""
    out = np.zeros((N, N), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        c = cells * (2**o)
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


def cells(n):
    """Seamless Voronoi: distance to the nearest and second nearest of n wrapped points, and the cell index."""
    pts = rng.random((n, 2)).astype(np.float32) * N
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
    return dist, second, idx


def rgb(c):
    return np.array(c, np.float32) / 255


def save(name, col, h, r, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * strength
    dy = (np.roll(h, 1, 0) - np.roll(h, -1, 0)) * strength
    n = np.dstack([-dx, -dy, np.ones_like(dx)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    col = np.clip(col, 0, 1)
    Image.fromarray((col * 255 + 0.5).astype(np.uint8)).save(os.path.join(OUT, name + "_Color.png"))
    Image.fromarray(((n * 0.5 + 0.5) * 255 + 0.5).astype(np.uint8)).save(os.path.join(OUT, name + "_Normal.png"))
    Image.fromarray((np.clip(r, 0, 1) * 255 + 0.5).astype(np.uint8)).save(os.path.join(OUT, name + "_Roughness.png"))
    return col, n


def mix(a, b, t):
    return a * (1 - t[..., None]) + b * t[..., None]


# ---------------------------------------------------------------- CraterFloor (32 studs)
dist, second, idx = cells(26)
edge = second - dist
crack = np.clip(1 - (edge - 1.5) / 2.5, 0, 1)  # the baked plates' dark cracks
lump = noise(8, 4)
blot = noise(3, 3)
fine = noise(32, 2)
tone = 0.88 + 0.2 * ((idx * 7) % 9) / 9.0
base = rgb((128, 114, 104)) * tone[..., None] * (0.9 + 0.2 * (lump[..., None] - 0.5))
scorch = np.clip((blot - 0.52) / 0.18, 0, 1)
col = mix(base, rgb((74, 66, 66)), scorch * 0.85)
col *= 0.92 + 0.16 * (fine[..., None] - 0.5)
col = mix(col, rgb((44, 38, 40)), crack)
h = np.clip(edge / 30.0, 0, 1) * 0.6 + 0.25 * lump
h = h * (1 - crack)
r = np.full((N, N), 0.92, np.float32)
# pebbles: small round stones with a lit top and an inked rim
img = Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8))
d = ImageDraw.Draw(img)
hmap = Image.fromarray((h * 255).astype(np.uint8))
dh = ImageDraw.Draw(hmap)
for _ in range(45):
    px, py = rng.random(2) * N
    rad = 2 + rng.random() * 4
    shade = int(112 + rng.random() * 34)
    for ox in (-N, 0, N):
        for oy in (-N, 0, N):
            box = [px + ox - rad, py + oy - rad, px + ox + rad, py + oy + rad]
            d.ellipse(box, fill=(shade, shade - 12, shade - 20), outline=(40, 34, 36), width=1)
            dh.ellipse(box, fill=230)
# glassy fused spots: a smooth dark glaze with a pale Spark-blue sheen (cartoon, not lava)
glass = Image.new("L", (N, N), 0)
dg = ImageDraw.Draw(glass)
for _ in range(5):
    px, py = rng.random(2) * N
    rx, ry = 10 + rng.random() * 16, 6 + rng.random() * 10
    for ox in (-N, 0, N):
        for oy in (-N, 0, N):
            dg.ellipse([px + ox - rx, py + oy - ry, px + ox + rx, py + oy + ry], fill=255)
g = np.asarray(glass, np.float32) / 255
col = np.asarray(img, np.float32) / 255
sheen = np.clip(1 - np.abs(Y % 40 - 14) / 6, 0, 1) * g
col = mix(col, rgb((56, 58, 70)), g * 0.9)
col = mix(col, rgb((150, 196, 220)), sheen * 0.45)
h = np.asarray(hmap, np.float32) / 255
h = np.where(g > 0.5, 0.35, h)
r = np.where(g > 0.5, 0.25, r)
floor_col, floor_n = save("CraterFloor", col, h, r, strength=5.0)

# ---------------------------------------------------------------- CraterRim (24 studs)
wob = noise(4, 3)
yy = (Y + (wob - 0.5) * 70) % N
band = np.floor(yy / (N / 8)).astype(int)
bandf = (yy % (N / 8)) / (N / 8)
palette = [(176, 148, 118), (150, 120, 96), (190, 164, 130), (132, 104, 86), (168, 136, 104), (120, 98, 84),
           (184, 156, 122), (146, 112, 90)]
pal = np.array([rgb(c) for c in palette], np.float32)
col = pal[band % 8]
grain = noise(24, 3)
col *= (0.88 + 0.24 * (grain[..., None] - 0.5))
seam = np.clip(1 - np.minimum(bandf, 1 - bandf) / 0.03, 0, 1)  # dark lines between strata
d2, s2, i2 = cells(18)
frac = np.clip(1 - ((s2 - d2) - 1.0) / 2.0, 0, 1)  # fractures through the layers
col = mix(col, rgb((70, 56, 50)), seam * 0.8)
col = mix(col, rgb((52, 42, 40)), frac)
soot = np.clip((noise(3, 3) - 0.55) / 0.2, 0, 1)
col = mix(col, rgb((86, 74, 70)), soot * 0.6)
h = 0.55 + 0.3 * np.sin(bandf * np.pi) + 0.15 * grain
h = h * (1 - 0.8 * seam) * (1 - frac)
r = np.full((N, N), 0.88, np.float32)
rim_col, rim_n = save("CraterRim", col, h, r, strength=6.0)

# ---------------------------------------------------------------- preview
tile = 300
prev = Image.new("RGB", (tile * 2 + 30 + 620, tile + 20), (34, 36, 44))
for i, c in enumerate((floor_col, rim_col)):
    prev.paste(Image.fromarray((c * 255).astype(np.uint8)).resize((tile, tile)), (10 + i * (tile + 10), 10))


# a little lit render: the floor running back to the rim wall (perspective cheat: rows of the tiled textures)
def lit(c, n, light=(-0.4, -0.5, 0.75)):
    L = np.array(light, np.float32)
    L /= np.linalg.norm(L)
    return np.clip(c * (0.45 + 0.6 * np.clip((n * L).sum(2), 0, 1))[..., None], 0, 1)


fl = lit(floor_col, floor_n)
rm = lit(rim_col, rim_n, (0.2, -0.7, 0.7))
W, H = 1200, 600
scene = np.zeros((H, W, 3), np.float32)
horizon = 240
for yv in range(H):
    if yv < horizon:
        # the rim wall: 2.5 rim tiles across, 1 tile up
        v = int(yv / horizon * N) % N
        us = (np.arange(W) / W * 2.5 * N).astype(int) % N
        scene[yv] = rm[v, us] * (0.8 + 0.2 * yv / horizon)
    else:
        z = (yv - horizon + 1) / (H - horizon)
        depth = 1 / z
        v = int(depth * 60) % N
        us = (((np.arange(W) - W / 2) * depth / W * 1.2 * N) + N * 10).astype(int) % N
        scene[yv] = fl[v, us] * (0.75 + 0.25 * z)
prev.paste(Image.fromarray((scene * 255).astype(np.uint8)).resize((600, 300), Image.LANCZOS), (tile * 2 + 30, 10))
draw = ImageDraw.Draw(prev)
draw.text((14, 14), "CraterFloor", fill=(240, 240, 240))
draw.text((24 + tile, 14), "CraterRim", fill=(240, 240, 240))
prev.save(os.path.join(ROOT, "preview", "crater_ground.png"))
print("wrote CraterFloor and CraterRim to", OUT)
