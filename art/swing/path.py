# path.py: draws art/preview/swing_path.png from art/export/swing/path.json (lune run art/swing/path.luau):
# a bot swinging down a real Downtown street with Shared.SwingMath (the game's own maths and buildings).
# Top: the street in a 3D view, the path coloured by speed, each line from the hero to its anchor on a building
# face or roof edge (the dot under it is the swing's pivot over the street), release points (gold: sweet).
# Bottom: speed over time against the swing's top speed and the server's Swing cap; swinging vs in the air.
# Run: python3 art/swing/path.py   (plain python3 with PIL)
import json
import math
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
data = json.load(open(os.path.join(ROOT, "art/export/swing/path.json")))
W, H = 1800, 1200
TOP_H = 820
img = Image.new("RGB", (W, H), (236, 240, 246))
dr = ImageDraw.Draw(img, "RGBA")


def font(size):
    for f in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf"):
        if os.path.exists(f):
            return ImageFont.truetype(f, size)
    return ImageFont.load_default()


F1, F2, F3 = font(30), font(20), font(16)

x0 = data["street"]
path = data["path"]
zs = [p[3] for p in path]
z0, z1 = min(zs) - 40, max(zs) + 40
zc = (z0 + z1) / 2

# view: turned about y then tipped down (orthographic)
yaw, pitch = math.radians(58), math.radians(28)
cy, sy, cp, sp = math.cos(yaw), math.sin(yaw), math.cos(pitch), math.sin(pitch)


def rot(x, y, z):
    x, z = x - x0, z - zc
    rx = x * cy - z * sy
    rz = x * sy + z * cy
    ry = y * cp - rz * sp
    depth = y * sp + rz * cp
    return rx, ry, depth


# fit the street window into the top panel
pts = []
for b in data["buildings"]:
    for xx in (b["x"] - b["sx"] / 2, b["x"] + b["sx"] / 2):
        for zz in (b["z"] - b["sz"] / 2, b["z"] + b["sz"] / 2):
            if z0 - 60 < zz < z1 + 60:
                pts.append(rot(xx, 0, zz))
                pts.append(rot(xx, min(b["top"], 260), zz))
for p in path:
    pts.append(rot(p[1], p[2], p[3]))
minX, maxX = min(p[0] for p in pts), max(p[0] for p in pts)
minY, maxY = min(p[1] for p in pts), max(p[1] for p in pts)
scale = min((W - 80) / (maxX - minX), (TOP_H - 110) / (maxY - minY))
ox = 40 - minX * scale + ((W - 80) - (maxX - minX) * scale) / 2
oy = TOP_H - 30 + minY * scale


def scr(x, y, z):
    rx, ry, _ = rot(x, y, z)
    return (ox + rx * scale, oy - ry * scale)


# the ground and the street
g = [scr(x0 - 200, 0, z0 - 60), scr(x0 + 200, 0, z0 - 60), scr(x0 + 200, 0, z1 + 60), scr(x0 - 200, 0, z1 + 60)]
dr.polygon(g, fill=(196, 200, 206))
s = [scr(x0 - 14, 0.1, z0 - 60), scr(x0 + 14, 0.1, z0 - 60), scr(x0 + 14, 0.1, z1 + 60), scr(x0 - 14, 0.1, z1 + 60)]
dr.polygon(s, fill=(120, 124, 132))
zz = z0 - 60
while zz < z1 + 60:
    dr.line([scr(x0, 0.2, zz), scr(x0, 0.2, zz + 8)], fill=(240, 220, 120), width=2)
    zz += 20


def shade(c, k):
    return tuple(int(v * k) for v in c)


# buildings, far first
blds = [b for b in data["buildings"] if z0 - 70 < b["z"] < z1 + 70]
blds.sort(key=lambda b: -rot(b["x"], 0, b["z"])[2])
palette = [(214, 120, 96), (110, 150, 196), (226, 190, 110), (150, 186, 140), (186, 150, 200), (230, 160, 120)]
for i, b in enumerate(blds):
    top = b["top"]
    clip = top > 260
    top = min(top, 260)
    lx, hx = b["x"] - b["sx"] / 2, b["x"] + b["sx"] / 2
    lz, hz = b["z"] - b["sz"] / 2, b["z"] + b["sz"] / 2
    col = palette[int(abs(b["x"] * 7 + b["z"] * 3)) % len(palette)]
    # the buildings on the camera's side of the street are see-through, so the swing over the street shows
    near = rot(b["x"], 0, b["z"])[2] > rot(x0, 0, b["z"])[2]
    alpha = 70 if near else 255
    # visible sides: the view looks from -x +z side (yaw); draw all four sides back to front then the roof
    sides = [
        ((lx, lz), (hx, lz)),
        ((hx, lz), (hx, hz)),
        ((hx, hz), (lx, hz)),
        ((lx, hz), (lx, lz)),
    ]
    sides.sort(key=lambda e: -rot((e[0][0] + e[1][0]) / 2, 0, (e[0][1] + e[1][1]) / 2)[2])
    for k, (a, c) in enumerate(sides):
        poly = [scr(a[0], b["base"], a[1]), scr(c[0], b["base"], c[1]), scr(c[0], top, c[1]), scr(a[0], top, a[1])]
        dr.polygon(poly, fill=shade(col, 0.62 + 0.12 * k) + (alpha,), outline=(60, 60, 70, 90 if near else 255))
        # window bands
        y = b["base"] + 8
        while y < top - 4 and not near:
            dr.line([scr(a[0], y, a[1]), scr(c[0], y, c[1])], fill=(255, 255, 255, 60), width=2)
            y += 12
    roof = [scr(lx, top, lz), scr(hx, top, lz), scr(hx, top, hz), scr(lx, top, hz)]
    dr.polygon(roof, fill=(shade(col, 1.0) if not clip else (250, 250, 250)) + (alpha,), outline=(60, 60, 70, 90 if near else 255))


def speed_col(v):
    k = max(0.0, min(1.0, v / data["stats"]["maxSpeed"]))
    # blue (slow) to orange to red (top speed)
    if k < 0.5:
        t = k / 0.5
        return (int(40 + 200 * t), int(120 + 60 * t), int(230 - 170 * t))
    t = (k - 0.5) / 0.5
    return (240, int(180 - 150 * t), int(60 - 30 * t))


# lines: hero -> anchor at the moment of the shot, the pivot under it
for ln in data["lines"]:
    t0, t1, hx, hy, hz, ax, ay, az, qx, qz, edge = ln[:11]
    dr.line([scr(hx, hy, hz), scr(ax, ay, az)], fill=(255, 255, 255), width=4)
    dr.line([scr(hx, hy, hz), scr(ax, ay, az)], fill=(40, 40, 50), width=1)
    px, py = scr(ax, ay, az)
    r = 7
    dr.ellipse([px - r, py - r, px + r, py + r], fill=(255, 80, 80) if edge else (255, 255, 255), outline=(30, 30, 30), width=2)
    qx2, qy2 = scr(qx, ay, qz)
    dr.ellipse([qx2 - 4, qy2 - 4, qx2 + 4, qy2 + 4], outline=(30, 30, 30), width=2)
    dr.line([scr(ax, ay, az), scr(qx, ay, qz)], fill=(30, 30, 30, 120), width=1)

# path, its shadow on the street first
for i in range(1, len(path)):
    a, b = path[i - 1], path[i]
    dr.line([scr(a[1], 0.3, a[3]), scr(b[1], 0.3, b[3])], fill=(40, 40, 50, 70), width=3)
for i in range(1, len(path)):
    a, b = path[i - 1], path[i]
    dr.line([scr(a[1], a[2], a[3]), scr(b[1], b[2], b[3])], fill=speed_col(b[4]), width=6 if b[5] == "swing" else 4)
for e in data["releases"]:
    t, x, y, z, v, sweet = e
    px, py = scr(x, y, z)
    r = 9
    star = []
    for k in range(10):
        ang = -math.pi / 2 + k * math.pi / 5
        rr = r if k % 2 == 0 else r * 0.45
        star.append((px + math.cos(ang) * rr, py + math.sin(ang) * rr))
    dr.polygon(star, fill=(255, 200, 40) if sweet else (200, 200, 200), outline=(30, 30, 30))

st = data["stats"]
dr.text((40, 24), "Swing path down a Downtown street (Shared.SwingMath, the game's own buildings)", font=F1, fill=(20, 24, 32))
dr.text(
    (40, 66),
    "%d lines in %d s, %.0f studs/s on average, top swing speed %.0f (server Swing cap %d), %d wall bumps"
    % (st["lines"], st["seconds"], st["avg"], st["top"], st["cap"], st["bumps"]),
    font=F2,
    fill=(40, 44, 56),
)
# legend
lx, ly = 40, 110
dr.rectangle([lx - 14, ly - 12, lx + 520, ly + 140], fill=(255, 255, 255, 220), outline=(120, 120, 130))
for k in range(100):
    dr.line([(lx + k * 2, ly + 8), (lx + k * 2, ly + 22)], fill=speed_col(k / 100 * st["maxSpeed"]))
dr.text((lx + 210, ly + 4), "path: slow -> top speed", font=F3, fill=(20, 20, 30))
dr.ellipse([lx, ly + 36, lx + 14, ly + 50], fill=(255, 255, 255), outline=(30, 30, 30), width=2)
dr.text((lx + 22, ly + 34), "anchor on a face", font=F3, fill=(20, 20, 30))
dr.ellipse([lx + 190, ly + 36, lx + 204, ly + 50], fill=(255, 80, 80), outline=(30, 30, 30), width=2)
dr.text((lx + 212, ly + 34), "snapped to a roof edge", font=F3, fill=(20, 20, 30))
dr.ellipse([lx + 2, ly + 66, lx + 10, ly + 74], outline=(30, 30, 30), width=2)
dr.text((lx + 22, ly + 60), "pivot over the street", font=F3, fill=(20, 20, 30))
dr.polygon([(lx + 7, ly + 86), (lx + 13, ly + 98), (lx + 1, ly + 98)], fill=(255, 200, 40), outline=(30, 30, 30))
dr.text((lx + 22, ly + 86), "release (gold: sweet, on the rising half)", font=F3, fill=(20, 20, 30))
dr.text((lx, ly + 112), "white line: hero to anchor when the line fires", font=F3, fill=(20, 20, 30))

# bottom: speed over time
gx0, gx1, gy0, gy1 = 90, W - 40, TOP_H + 50, H - 60
dr.rectangle([0, TOP_H, W, H], fill=(250, 251, 253))
dr.text((40, TOP_H + 12), "Speed over time", font=F2, fill=(20, 24, 32))
tmax = path[-1][0]
vmax = 140


def gp(t, v):
    return (gx0 + (gx1 - gx0) * t / tmax, gy1 - (gy1 - gy0) * v / vmax)


prev = None
start = None
for p in path:
    if p[5] == "swing" and start is None:
        start = p[0]
    if p[5] != "swing" and start is not None:
        dr.rectangle([gp(start, vmax)[0], gy0, gp(p[0], 0)[0], gy1], fill=(120, 170, 230, 50))
        start = None
if start is not None:
    dr.rectangle([gp(start, vmax)[0], gy0, gx1, gy1], fill=(120, 170, 230, 50))
for v in range(0, vmax + 1, 20):
    y = gp(0, v)[1]
    dr.line([(gx0, y), (gx1, y)], fill=(210, 214, 222), width=1)
    dr.text((gx0 - 44, y - 9), str(v), font=F3, fill=(80, 84, 96))
for t in range(0, int(tmax) + 1):
    x = gp(t, 0)[0]
    dr.text((x - 6, gy1 + 6), "%ds" % t, font=F3, fill=(80, 84, 96))
for v, c, name in (
    (st["maxSpeed"], (240, 140, 40), "swing top speed"),
    (st["cap"], (210, 40, 40), "server Swing cap"),
    (st["cap"] * 1.15, (150, 20, 20), "cap x tolerance"),
):
    y = gp(0, v)[1]
    dr.line([(gx0, y), (gx1, y)], fill=c, width=2)
    dr.text((gx1 - 190, y - 22), name, font=F3, fill=c)
for i in range(1, len(path)):
    a, b = path[i - 1], path[i]
    dr.line([gp(a[0], a[4]), gp(b[0], b[4])], fill=(30, 40, 60), width=3)
dr.text((gx0 + 8, gy0 + 4), "blue bands: on a line (swinging); gaps: flung through the air", font=F3, fill=(60, 90, 140))
dr.rectangle([gx0, gy0, gx1, gy1], outline=(120, 124, 132))

out = os.path.join(ROOT, "art/preview/swing_path.png")
img.save(out)
print("wrote", out)
