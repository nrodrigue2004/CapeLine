"""Preview of the gap polish pieces (2026-11-19) from art/export/fx/polish.json (lune run art/fx/polish.luau):
the Snow Wall slab front view with its shards, snow cap and drifts per preset, the thrown crate's front and top
with its planks, the smoke cloud's puff spots per preset over the blind radius, and the shield drone's orbit
round the hero with the bubble. Writes art/preview/polish_pieces.png.

    lune run art/fx/polish.luau && python3 art/fx/polish.py
"""
import json
import math
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
data = json.load(open(os.path.join(ROOT, "art", "export", "fx", "polish.json")))
ice = tuple(data["ice"]["color"])
deep = tuple(data["ice"]["deep"])
snow = tuple(data["ice"]["snow"])
INK = (17, 17, 17)
W, H = 1400, 720
img = Image.new("RGB", (W, H), (40, 46, 62))
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 18)
except OSError:
    font = ImageFont.load_default()


def rot(pts, cx, cy, deg):
    a = math.radians(deg)
    return [(cx + (x - cx) * math.cos(a) - (y - cy) * math.sin(a), cy + (x - cx) * math.sin(a) + (y - cy) * math.cos(a)) for x, y in pts]


# the Snow Wall slab per preset (front view: x across, y up; 1 stud = 22 px)
S = 22
for k, name in enumerate(["low", "medium", "high"]):
    ox, oy = 60 + k * 240, 330
    d.text((ox, 40), "Snow Wall: " + name, fill=(235, 235, 240), font=font)
    sx, sy = 6.5, 8
    x0, y0 = ox + 30, oy - sy * S
    for sh in data["shards"][name]:
        cx, cy = x0 + (sh["x"] + sx / 2) * S, oy - (sh["y"] + sy / 2) * S
        w, h = sh["w"] * S, sh["h"] * S
        left = [(cx - w / 2, cy + h / 2), (cx, cy - h / 2), (cx, cy + h / 2)]
        right = [(cx, cy + h / 2), (cx, cy - h / 2), (cx + w / 2, cy + h / 2)]
        d.polygon(rot(left, cx, cy, sh["rz"]), fill=ice, outline=INK)
        d.polygon(rot(right, cx, cy, sh["rz"]), fill=deep, outline=INK)
    d.rectangle([x0, y0, x0 + sx * S, oy], fill=ice + (0,), outline=INK, width=2)
    d.rectangle([x0 - 2, y0 - 6, x0 + sx * S + 2, y0 + 4], fill=snow, outline=INK)
    d.polygon([(x0 - 4, oy), (x0 + sx * S + 4, oy), (x0 + sx * S + 4, oy - 18), (x0 - 4, oy)], fill=snow, outline=INK)

# the crate (front and top)
ox, oy = 790, 120
d.text((ox, 40), "Thrown crate (4 x 3 x 4)", fill=(235, 235, 240), font=font)
S2 = 40
for view, (ax, bx), oyy in (("front", (1, 2), 0), ("top", (1, 3), 170)):
    cx, cy = ox + 80, oy + 60 + oyy
    hw = 2 * S2
    hh = (1.5 if view == "front" else 2) * S2
    d.rectangle([cx - hw, cy - hh, cx + hw, cy + hh], fill=(176, 128, 72), outline=INK, width=2)
    for b in data["crate"]:
        px, py = b[ax], b[bx]
        sx_, sy_ = b[ax + 3], b[bx + 3]
        col = (112, 74, 40) if b[0] == "edge" else (150, 104, 58)
        d.rectangle([cx + (px - sx_ / 2) * S2, cy - (py + sy_ / 2) * S2, cx + (px + sx_ / 2) * S2, cy - (py - sy_ / 2) * S2],
                    fill=col, outline=INK)
    d.text((cx + hw + 14, cy - 10), view, fill=(220, 220, 225), font=font)

# the smoke cloud's spots per preset (top view)
R = data["radius"]
for k, name in enumerate(["low", "medium", "high"]):
    cx, cy = 120 + k * 230, 560
    d.text((cx - 90, 420), "Smoke: " + name, fill=(235, 235, 240), font=font)
    rr = 5.5
    d.ellipse([cx - R * rr, cy - R * rr, cx + R * rr, cy + R * rr], outline=(200, 90, 90), width=2)
    for i, s in enumerate(data["smoke"][name]):
        px, py, sc = cx + s[0] * rr, cy + s[1] * rr, s[2] * 9 * rr / 2
        col = (120, 122, 136) if (i + 1) % 3 == 0 else (168, 170, 182)
        d.ellipse([px - sc, py - sc, px + sc, py + sc], fill=col)

# the drone's orbit (top view) and the bubble
cx, cy = 1100, 560
d.text((cx - 120, 420), "Shield drone + bubble", fill=(235, 235, 240), font=font)
k = 22
b = data["bubble"] * k
d.ellipse([cx - b, cy - b, cx + b, cy + b], outline=(120, 220, 255), width=3)
d.rectangle([cx - 0.6 * k, cy - 0.5 * k, cx + 0.6 * k, cy + 0.5 * k], fill=(90, 130, 220), outline=INK)
pts = [(cx + p[0] * k, cy + p[2] * k) for p in data["drone"]]
d.line(pts, fill=(235, 240, 248), width=2)
x, y = pts[5]
d.ellipse([x - 12, y - 9, x + 12, y + 9], fill=(235, 240, 248), outline=INK, width=2)
d.ellipse([x - 24, y - 24, x + 24, y + 24], outline=(60, 70, 90), width=2)
img.save(os.path.join(ROOT, "art", "preview", "polish_pieces.png"))
print("wrote art/preview/polish_pieces.png")
