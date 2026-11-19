# Draws the lock-on marker preview (art/preview/lock_marker.png) from art/lock/marker.json, the layout
# Shared.LockRules.marker gives LockClient: each bar a rotated box with its ink outline under it, the hard lock's
# diamond over the target, a stand-in robot silhouette in the middle. Run: lune run art/lock/marker.luau first.
import json
import math
from PIL import Image, ImageDraw

data = json.load(open("art/lock/marker.json"))
C = data["colors"]
W, H = 260, 260
skies = [(150, 200, 240), (28, 32, 48)]
img = Image.new("RGB", (W * len(data["frames"]), H * len(skies)), (0, 0, 0))
d = ImageDraw.Draw(img)


def box(cx, cy, w, h, rot, color):
    r = math.radians(rot)
    c, s = math.cos(r), math.sin(r)
    pts = []
    for dx, dy in ((-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)):
        pts.append((cx + dx * c - dy * s, cy + dx * s + dy * c))
    d.polygon(pts, fill=tuple(color))


for row, sky in enumerate(skies):
    for col, f in enumerate(data["frames"]):
        ox, oy = col * W, row * H
        d.rectangle([ox, oy, ox + W - 1, oy + H - 1], fill=sky)
        cx, cy = ox + W / 2, oy + H / 2 + 14
        # a stand-in robot: the blocky body's silhouette
        d.rectangle([cx - 14, cy - 34, cx + 14, cy - 8], fill=(90, 96, 110))
        d.rectangle([cx - 20, cy - 8, cx + 20, cy + 26], fill=(70, 76, 90))
        d.rectangle([cx - 18, cy + 26, cx - 3, cy + 54], fill=(60, 64, 76))
        d.rectangle([cx + 3, cy + 26, cx + 18, cy + 54], fill=(60, 64, 76))
        color = C["hard"] if f["hard"] else C["soft"]
        for b in f["bars"]:
            box(cx + b["x"], cy + b["y"], b["w"] + 4, b["h"] + 4, b["rot"], C["ink"])
        for b in f["bars"]:
            box(cx + b["x"], cy + b["y"], b["w"], b["h"], b["rot"], color)
        if f["diamond"] > 0:
            dd = f["diamond"]
            ty = cy - f["px"] * 0.5 - dd * 1.1
            box(cx, ty, dd + 5, dd + 5, 45, C["ink"])
            box(cx, ty, dd, dd, 45, C["hard"])
        label = ("HARD t=%.2f" % f["t"]) if f["hard"] else "SOFT"
        d.text((ox + 8, oy + 8), label, fill=(255, 255, 255) if row else (20, 20, 28))
img.save("art/preview/lock_marker.png")
print("wrote art/preview/lock_marker.png")
