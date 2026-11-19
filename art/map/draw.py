"""draw.py: the map screen's pictures (the map pass, 2026-11-19; Shared.MapPlan, Ui.MapScreen).

    lune run art/map/layout.luau && python3 art/map/draw.py

Reads art/export/map/city.json (the fixed hub and Uptown, top-down, from the game's own layout) and writes:
  art/export/map/Hub.png      the hub square and the districts past it (MapPlan.cityImages), at most 1024 a side
  art/export/map/Uptown.png   Uptown (600 x 600 studs), the same scale; both clear outside their own areas
  art/export/map/Suburbs.png, Farmland.png, Coast.png, Landmark.png
                              128 x 128 tiling patterns, one outskirts tile (100 studs) each; MapScreen tiles
                              them over its merged zone rectangles (this week's seed decides where they go)
  art/preview/map_city.png    the hub and Uptown side by side with the patterns, for a look
The look: a comic city map. Flat palette colours a little brighter than the 3D city, a dark ink outline on
every building and tree, a soft drop shadow growing with the building's height (towers read tall), the docks'
harbour water with ripple marks, the plaza in pale stone. No text: the names are UI labels on top (crisp at
any zoom). Plain python3 with PIL.
"""

import json
import math
import os

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
EXPORT = os.path.join(ROOT, "art", "export", "map")
PREVIEW = os.path.join(ROOT, "art", "preview")
SS = 3  # supersampling
PX_PER_STUD = 0.64

INK = (34, 30, 40)
SEA = (46, 92, 132)
SEA_LIGHT = (88, 140, 180)


def lift(c, k=0.12):
    """A palette colour a little brighter and more saturated (the map reads in comic colours)."""
    r, g, b = c[:3]
    m = (r + g + b) / 3
    r, g, b = [v + (v - m) * 0.25 for v in (r, g, b)]
    return tuple(int(max(0, min(255, v + (255 - v) * k))) for v in (r, g, b))


def corners(b):
    """The box's four plan corners (x, z), turned by its ry."""
    hx, hz = b["sx"] / 2, b["sz"] / 2
    a = math.radians(b.get("ry") or 0)
    ca, sa = math.cos(a), math.sin(a)
    out = []
    for dx, dz in ((-hx, -hz), (hx, -hz), (hx, hz), (-hx, hz)):
        # Roblox's yaw: x' = x cos + z sin, z' = -x sin + z cos
        out.append((b["cx"] + dx * ca + dz * sa, b["cz"] - dx * sa + dz * ca))
    return out


def image_size(region):
    """The picture's pixel size at the map's scale (Roblox shows at most 1024 a side)."""
    w = (region["x1"] - region["x0"]) * PX_PER_STUD
    h = (region["z1"] - region["z0"]) * PX_PER_STUD
    f = min(1.0, 1024 / max(w, h))
    return int(round(w * f)), int(round(h * f))


def draw_region(data, region):
    x0, z0, x1, z1 = region["x0"], region["z0"], region["x1"], region["z1"]
    size = image_size(region)
    W, H = size[0] * SS, size[1] * SS
    k = W / (x1 - x0)
    pal = data["palette"]
    gy = data["ground"]

    def P(x, z):
        return ((x - x0) * k, (z - z0) * k)

    img = Image.new("RGB", (W, H), SEA)
    d = ImageDraw.Draw(img)
    # ripples on the water (the harbour basin and anywhere the ground is cut away)
    step = int(26 * SS)
    for yy in range(0, H, step):
        for xx in range((yy // step) % 2 * step // 2, W, step):
            d.arc([xx, yy, xx + 10 * SS, yy + 6 * SS], 200, 340, fill=SEA_LIGHT, width=SS)

    boxes = data["boxes"]
    rank = {"base": 0, "fill": 1, "landmark": 1, "hub": 1}

    def order(b):
        return (rank[b["layer"]], b["top"], b["sx"] * b["sz"] * -1)

    boxes = sorted(boxes, key=order)
    shadow = Image.new("L", (W, H), 0)
    sd = ImageDraw.Draw(shadow)
    tall = []
    for b in boxes:
        if b["kind"] in ("building", "tier") or (b["kind"] == "prop" and b["top"] - gy > 6):
            tall.append(b)
    # shadows first (one soft layer under everything that stands up)
    for b in tall:
        h = b["top"] - gy
        off = min(14, 2 + h * 0.03) * SS
        pts = [P(x, z) for x, z in corners(b)]
        pts = [(x + off, y + off * 0.8) for x, y in pts]
        sd.polygon(pts, fill=int(min(140, 60 + h * 0.2)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(2 * SS))

    flat_done = False
    for b in boxes:
        kind = b["kind"]
        col = pal.get(b["color"], [150, 150, 150])
        stands = kind in ("building", "tier") or (kind == "prop" and b["top"] - gy > 6)
        if stands and not flat_done:
            # the shadow goes down once all the flat ground is drawn
            img.paste((20, 24, 36), (0, 0), shadow)
            flat_done = True
        pts = [P(x, z) for x, z in corners(b)]
        if b["sx"] * k < 1.2 * SS and b["sz"] * k < 1.2 * SS:
            continue
        if kind == "ground":
            d.polygon(pts, fill=lift(pal["grass"], 0.1))
        elif kind == "road":
            d.polygon(pts, fill=lift(col, 0.05))
        elif kind in ("sidewalk", "plaza"):
            d.polygon(pts, fill=lift(col, 0.18))
        elif kind == "water":
            d.ellipse([min(p[0] for p in pts), min(p[1] for p in pts), max(p[0] for p in pts), max(p[1] for p in pts)], fill=lift(pal["water"], 0.2), outline=INK, width=SS)
        elif kind == "field":
            d.polygon(pts, fill=lift(col, 0.1))
        elif b.get("shape") == "ball" or (kind == "prop" and b["color"] == "leaf"):
            xs, ys = [p[0] for p in pts], [p[1] for p in pts]
            d.ellipse([min(xs), min(ys), max(xs), max(ys)], fill=lift(pal["leaf"], 0.15), outline=INK, width=SS)
        elif b.get("shape") == "cylinder":
            xs, ys = [p[0] for p in pts], [p[1] for p in pts]
            d.ellipse([min(xs), min(ys), max(xs), max(ys)], fill=lift(col, 0.15), outline=INK, width=SS)
        elif kind == "roof":
            d.polygon(pts, fill=lift(col, 0.12), outline=INK, width=SS)
            # the ridge line down the long side of a wedge roof
            cx, cz = b["cx"], b["cz"]
            a = math.radians(b.get("ry") or 0)
            if b["sx"] >= b["sz"]:
                dx, dz = b["sx"] / 2 * math.cos(a), -b["sx"] / 2 * math.sin(a)
            else:
                dx, dz = b["sz"] / 2 * math.sin(a), b["sz"] / 2 * math.cos(a)
            d.line([P(cx - dx * 0.9, cz - dz * 0.9), P(cx + dx * 0.9, cz + dz * 0.9)], fill=INK, width=SS)
        elif stands:
            h = b["top"] - gy
            fill = lift(col, 0.2 if h < 60 else 0.05)
            d.polygon(pts, fill=fill, outline=INK, width=2 * SS if h > 120 else SS + 1)
            if h > 250:
                # a skyscraper: a lit inner roof square so towers stand out from a distance
                cx = sum(p[0] for p in pts) / 4
                cy = sum(p[1] for p in pts) / 4
                inner = [(cx + (x - cx) * 0.45, cy + (y - cy) * 0.45) for x, y in pts]
                d.polygon(inner, fill=lift(col, 0.45), outline=INK, width=SS)
        else:
            d.polygon(pts, fill=lift(col, 0.15), outline=INK, width=SS)
    if not flat_done:
        img.paste((20, 24, 36), (0, 0), shadow)
    # only the picture's own areas are drawn; the rest is clear so the outskirts frames show through
    mask = Image.new("L", (W, H), 0)
    md = ImageDraw.Draw(mask)
    for r in region["own"]:
        md.rectangle([*P(r["x0"], r["z0"]), *P(r["x1"], r["z1"])], fill=255)
    # a thin ink edge round the city where it meets the outskirts
    edge = mask.filter(ImageFilter.MaxFilter(2 * SS + 1))
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    out.paste(INK + (255,), (0, 0), edge)
    out.paste(img.convert("RGBA"), (0, 0), mask)
    return out.resize(size, Image.LANCZOS)


def pattern(kind):
    """One outskirts tile (100 studs) as a 128 px tiling square."""
    S = 128 * SS
    if kind == "Suburbs":
        img = Image.new("RGB", (S, S), lift((92, 130, 78), 0.12))
        d = ImageDraw.Draw(img)
        roofs = [(150, 72, 60), (70, 90, 120), (74, 76, 82), (150, 72, 60)]
        lots = [(0.2, 0.2), (0.62, 0.22), (0.24, 0.64), (0.66, 0.66)]
        for (u, v), c in zip(lots, roofs):
            x, y = u * S, v * S
            w, h = 0.2 * S, 0.15 * S
            d.rectangle([x, y, x + w, y + h], fill=lift(c, 0.15), outline=INK, width=SS)
            d.line([x + 2 * SS, y + h / 2, x + w - 2 * SS, y + h / 2], fill=INK, width=SS)
        for u, v in ((0.5, 0.48), (0.08, 0.9), (0.9, 0.08)):
            r = 0.06 * S
            d.ellipse([u * S - r, v * S - r, u * S + r, v * S + r], fill=lift((70, 120, 60), 0.15), outline=INK, width=SS)
    elif kind == "Farmland":
        # two fields a tile, furrows across one and down the other, in close tones (a calm patchwork at any zoom)
        img = Image.new("RGB", (S, S), lift((176, 164, 84), 0.12))
        d = ImageDraw.Draw(img)
        half = S // 2
        d.rectangle([half, 0, S, S], fill=lift((150, 160, 78), 0.12))
        for i in range(1, 12):
            y = i * S / 12
            d.line([3 * SS, y, half - 3 * SS, y], fill=lift((150, 138, 66), 0.05), width=SS)
            x = half + i * half / 12
            d.line([x, 3 * SS, x, S - 3 * SS], fill=lift((126, 140, 64), 0.05), width=SS)
        d.line([half, 0, half, S], fill=(132, 100, 70), width=SS)
        d.rectangle([0, 0, S - 1, S - 1], outline=(132, 100, 70), width=SS)
    elif kind == "Coast":
        img = Image.new("RGB", (S, S), lift((150, 176, 110), 0.15))
        d = ImageDraw.Draw(img)
        for i, (u, v) in enumerate(((0.2, 0.25), (0.7, 0.2), (0.45, 0.6), (0.15, 0.8), (0.8, 0.75))):
            r = 0.05 * S
            d.ellipse([u * S - r, v * S - r * 0.7, u * S + r, v * S + r * 0.7], fill=lift((196, 180, 150), 0.2))
        d.rectangle([0.55 * S, 0.42 * S, 0.75 * S, 0.55 * S], fill=lift((228, 226, 220), 0.1), outline=INK, width=SS)
    else:  # Landmark: rough rock
        img = Image.new("RGB", (S, S), lift((120, 112, 104), 0.1))
        d = ImageDraw.Draw(img)
        for u, v, r in ((0.2, 0.3, 0.07), (0.7, 0.25, 0.05), (0.5, 0.7, 0.08), (0.85, 0.8, 0.04), (0.1, 0.85, 0.05)):
            d.ellipse([u * S - r * S, v * S - r * S, u * S + r * S, v * S + r * S], fill=lift((92, 86, 80), 0.05), outline=INK, width=SS)
    return img.resize((128, 128), Image.LANCZOS)


def main():
    with open(os.path.join(EXPORT, "city.json")) as f:
        data = json.load(f)
    hub = draw_region(data, data["regions"]["Hub"])
    hub.save(os.path.join(EXPORT, "Hub.png"))
    up = draw_region(data, data["regions"]["Uptown"])
    up.save(os.path.join(EXPORT, "Uptown.png"))
    pats = {}
    for name in ("Suburbs", "Farmland", "Coast", "Landmark"):
        pats[name] = pattern(name)
        pats[name].save(os.path.join(EXPORT, name + ".png"))
    # the preview: Uptown above the hub at their true places, the patterns tiled 3 x 3 on the right
    hr, ur = data["regions"]["Hub"], data["regions"]["Uptown"]
    sheet = Image.new("RGBA", (hub.width + 420, max(1200, hub.height + 520)), (92, 130, 78, 255))
    hk = hub.width / (hr["x1"] - hr["x0"])
    upw = int((ur["x1"] - ur["x0"]) * hk)
    sheet.alpha_composite(up.resize((upw, upw), Image.LANCZOS), (int((ur["x0"] - hr["x0"]) * hk), 10))
    top = 10 + int((hr["z0"] - ur["z0"]) * hk)
    sheet.alpha_composite(hub, (0, top))
    sheet = sheet.convert("RGB")
    y = 0
    for name, p in pats.items():
        tile = Image.new("RGB", (384, 384))
        for i in range(3):
            for j in range(3):
                tile.paste(p, (i * 128, j * 128))
        sheet.paste(tile.resize((384, 384)), (hub.width + 18, y))
        y += 384 + 8
        if y + 384 > sheet.height:
            break
    os.makedirs(PREVIEW, exist_ok=True)
    sheet.save(os.path.join(PREVIEW, "map_city.png"))
    print("wrote Hub.png, Uptown.png, 4 patterns and art/preview/map_city.png")


if __name__ == "__main__":
    main()
