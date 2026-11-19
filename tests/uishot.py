"""UiShot: draws tests/uishot.luau's JSON (the real UI's boxes, run headless) to one PNG per scene.

    python3 tests/uishot.py out.json out_dir [--fonts DIR] [--prefix name_]

Approximate (the comic UI pass, 2026-11-18): rectangles with rounded corners, UIStroke borders drawn
outside the box, text in the box's estimated size and alignment, rotation, ClipsDescendants, Kit's halftone
dots. --fonts names a folder with Bangers-Regular.ttf and Montserrat.ttf (Google Fonts, OFL) for
Roblox's Bangers and Gotham; without them it uses DejaVu Sans Bold. A sunset city backdrop stands in for
the game.
"""

import json
import math
import os
import re
import sys

from PIL import Image, ImageDraw, ImageFont

SS = 2  # supersampling


def arg(name, default=None):
    if name in sys.argv:
        i = sys.argv.index(name)
        return sys.argv[i + 1]
    return default


FONT_DIR = arg("--fonts", "")
# --images map.json: {"rbxassetid://<id>": "local.png"} (art/thumbs/ids.json): picture tiles drawn from the sheets
# (its own map: IMAGES below is each shot's own pictures, refilled per shot, which wiped this one)
THUMB_IMAGES = json.load(open(arg("--images"))) if arg("--images") else {}
_imgs = {}


def local_image(n):
    path = THUMB_IMAGES.get(n.get("image") or "")
    if not path:
        return None
    if path not in _imgs:
        _imgs[path] = Image.open(path).convert("RGBA")
    im = _imgs[path]
    if n.get("rect"):
        x, y, w, h = n["rect"]
        im = im.crop((x, y, x + w, y + h))
    return im
PREFIX = arg("--prefix", "")
FALLBACK = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
_fonts = {}
# a shot's pictures by content id -> a local file (the map's city pictures and patterns, 2026-11-19); others
# are drawn as an empty frame
IMAGES = {}
_loaded = {}


def picture(url):
    path = IMAGES.get(url)
    if not path or not os.path.exists(path):
        return None
    if path not in _loaded:
        _loaded[path] = Image.open(path).convert("RGBA")
    return _loaded[path]


def font(name, px):
    px = max(4, int(round(px * SS)))
    face = "body"
    if name == "Bangers":
        face = "display"
    elif name and name.startswith("Gotham") and name.endswith("Black"):
        face = "black"
    key = (face, px)
    if key in _fonts:
        return _fonts[key]
    f = None
    try:
        if face == "display" and FONT_DIR:
            f = ImageFont.truetype(os.path.join(FONT_DIR, "Bangers-Regular.ttf"), px)
        elif FONT_DIR:
            f = ImageFont.truetype(os.path.join(FONT_DIR, "Montserrat.ttf"), px)
            try:
                f.set_variation_by_name("Black" if face == "black" else "Bold")
            except Exception:
                pass
    except OSError:
        f = None
    if f is None:
        f = ImageFont.truetype(FALLBACK, px)
    _fonts[key] = f
    return f


def rgba(c, t):
    return (c[0], c[1], c[2], max(0, min(255, int(round((1 - t) * 255)))))


def radius(n):
    c = n.get("corner")
    if not c:
        return 0
    r = (c[0] * min(n["w"], n["h"]) + c[1]) * n.get("scale", 1)
    return max(0, min(r, min(n["w"], n["h"]) / 2))


def backdrop(w, h):
    img = Image.new("RGBA", (w * SS, h * SS))
    d = ImageDraw.Draw(img)
    top, mid, low = (255, 150, 90), (245, 110, 120), (90, 70, 150)
    for y in range(h * SS):
        k = y / (h * SS)
        a, b, kk = (top, mid, k / 0.5) if k < 0.5 else (mid, low, (k - 0.5) / 0.5)
        col = tuple(int(a[i] + (b[i] - a[i]) * kk) for i in range(3))
        d.line([(0, y), (w * SS, y)], fill=col + (255,))
    for x, bw, bh in [(40, 110, 310), (170, 90, 390), (300, 160, 260), (520, 120, 430), (690, 140, 340),
                      (880, 100, 370), (1020, 200, 280), (1180, 120, 330)]:
        d.rectangle([x * SS, (h - bh) * SS, (x + bw) * SS, h * SS], fill=(58, 52, 104, 255))
    d.rectangle([0, (h - 120) * SS, w * SS, h * SS], fill=(52, 54, 72, 255))
    return img


def halftone(w, h, color, t, step):
    tile = Image.new("RGBA", (w, h))
    d = ImageDraw.Draw(tile)
    r = max(1, step * 0.2)
    col = rgba(color, t)
    y, row = 0.0, 0
    while y < h + step:
        x = (step / 2) if row % 2 else 0.0
        while x < w + step:
            d.ellipse([x - r, y - r, x + r, y + r], fill=col)
            x += step
        y += step / 2
        row += 1
    return tile


def strip(text):
    return re.sub(r"<[^>]+>", "", text or "")


def wrap_lines(text, f, width, wrap):
    out = []
    for para in strip(text).split("\n"):
        if not wrap:
            out.append(para)
            continue
        line = ""
        for word in para.split(" "):
            test = (line + " " + word).strip()
            if f.getlength(test) <= width or not line:
                line = test
            else:
                out.append(line)
                line = word
        out.append(line)
    return out


def draw_text(layer, n):
    text = n.get("text")
    if not text or n.get("textT", 0) >= 0.99:
        return
    x, y, w, h = n["x"] * SS, n["y"] * SS, n["w"] * SS, n["h"] * SS
    pad = n.get("pad")
    if pad:
        x += pad[0] * SS
        y += pad[1] * SS
        w -= (pad[0] + pad[2]) * SS
        h -= (pad[1] + pad[3]) * SS
    f = font(n.get("font"), n["size"])
    lines = wrap_lines(text, f, w, n.get("wrap"))
    lh = f.size * 1.0
    total = lh * len(lines)
    ay = n.get("ay") or "Center"
    ty = y if ay == "Top" else (y + h - total if ay == "Bottom" else y + (h - total) / 2)
    d = ImageDraw.Draw(layer)
    sw = 0
    scol = None
    for s in n.get("strokes") or []:
        if s.get("mode") == "Contextual":
            sw = max(1, int(round(s["t"] * n.get("scale", 1) * SS)))
            scol = rgba(s["color"], s.get("tr", 0))
    if not sw and n.get("strokeT", 1) < 0.99:
        sw = SS
        scol = rgba(n["strokeC"], n["strokeT"])
    col = rgba(n["color"], n.get("textT", 0))
    for i, line in enumerate(lines):
        lw = f.getlength(line)
        ax = n.get("ax") or "Center"
        tx = x if ax == "Left" else (x + w - lw if ax == "Right" else x + (w - lw) / 2)
        yy = ty + i * lh
        # Bangers sits high in its box; nudge so caps centre like Roblox's
        if sw:
            d.text((tx, yy), line, font=f, fill=col, stroke_width=sw, stroke_fill=scol)
        else:
            d.text((tx, yy), line, font=f, fill=col)


def draw_node(canvas, n):
    rot = n.get("rot", 0) or 0
    clip = n.get("clip")
    if rot or clip:
        layer = Image.new("RGBA", canvas.size)
        paint(layer, n, kids=False)
        sub = Image.new("RGBA", canvas.size)
        for k in n["kids"]:
            draw_node(sub, k)
        if clip:
            mask = Image.new("L", canvas.size, 0)
            ImageDraw.Draw(mask).rectangle(
                [n["x"] * SS, n["y"] * SS, (n["x"] + n["w"]) * SS, (n["y"] + n["h"]) * SS], fill=255)
            # deco (the ink shadow) sits outside the box: Roblox clips it too
            blank = Image.new("RGBA", canvas.size)
            sub = Image.composite(sub, blank, mask)
        layer.alpha_composite(sub)
        if rot:
            cx, cy = (n["x"] + n["w"] / 2) * SS, (n["y"] + n["h"] / 2) * SS
            layer = layer.rotate(-rot, resample=Image.BICUBIC, center=(cx, cy))
        canvas.alpha_composite(layer)
    else:
        paint(canvas, n, kids=True)


_sheets = None


def sheet_for(image):
    """The icon sheet (art/export/icons) an rbxassetid names, by art/icons/ids.json (gap-icons)."""
    global _sheets
    if _sheets is None:
        _sheets = {}
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        ids = os.path.join(root, "art", "icons", "ids.json")
        if os.path.exists(ids):
            for f, i in json.load(open(ids)).items():
                path = os.path.join(root, "art", "export", "icons", f)
                if os.path.exists(path):
                    _sheets["rbxassetid://" + str(i)] = Image.open(path).convert("RGBA")
    m = re.match(r"(rbxassetid://\d+)", image or "")
    return _sheets.get(m.group(1)) if m else None


def paint_cell(canvas, n, sheet, x0, y0, x1, y1):
    ox, oy, w, h = n["rect"]
    cell = sheet.crop((int(ox), int(oy), int(ox + w), int(oy + h)))
    s = min((x1 - x0) / w, (y1 - y0) / h)  # ScaleType Fit
    tw, th = max(1, int(w * s)), max(1, int(h * s))
    cell = cell.resize((tw, th), Image.LANCZOS)
    tint = n.get("imageC") or [255, 255, 255]
    if tuple(tint) != (255, 255, 255):
        # ImageColor3 multiplies the picture (gap-icons2: the tinted shape backings)
        r, g, b, a = cell.split()
        r = r.point(lambda v, k=tint[0]: v * k // 255)
        g = g.point(lambda v, k=tint[1]: v * k // 255)
        b = b.point(lambda v, k=tint[2]: v * k // 255)
        cell = Image.merge("RGBA", (r, g, b, a))
    t = n.get("imageT", 0)
    if t > 0:
        a = cell.getchannel("A").point(lambda v: int(v * (1 - t)))
        cell.putalpha(a)
    canvas.alpha_composite(cell, (int(x0 + (x1 - x0 - tw) / 2), int(y0 + (y1 - y0 - th) / 2)))
# UISHOT_IMAGES=<ids.json> (file name -> uploaded id, as art/panels/upload.py keeps them, next to the files):
# uploaded images draw from their local files instead of a placeholder box
LOCAL_IMAGES = {}
if os.environ.get("UISHOT_IMAGES"):
    import json as _json
    _ids = _json.load(open(os.environ["UISHOT_IMAGES"]))
    _dir = os.path.dirname(os.environ["UISHOT_IMAGES"])
    LOCAL_IMAGES = {str(v): os.path.join(_dir, k) for k, v in _ids.items() if isinstance(v, int)}


def paint(canvas, n, kids):
    x0, y0 = n["x"] * SS, n["y"] * SS
    x1, y1 = (n["x"] + n["w"]) * SS, (n["y"] + n["h"]) * SS
    r = radius(n) * SS
    d = ImageDraw.Draw(canvas)
    if n.get("bgT", 0) < 0.99 and x1 > x0 and y1 > y0:
        d.rounded_rectangle([x0, y0, x1, y1], radius=r, fill=rgba(n["bg"], n["bgT"]))
    if n.get("image") and n.get("imageT", 0) < 0.99 and x1 - x0 > 1 and y1 - y0 > 1:
        local_img = LOCAL_IMAGES.get(str(n["image"]).replace("rbxassetid://", ""))
        if local_img:
            # an uploaded image drawn from its local file (UISHOT_IMAGES), with its rect and Crop scaling
            src = Image.open(local_img).convert("RGBA")
            if n.get("rect"):
                ox, oy, sw, sh = n["rect"]
                src = src.crop((int(ox), int(oy), int(ox + sw), int(oy + sh)))
            bw, bh = int(x1 - x0), int(y1 - y0)
            if n.get("slice"):
                # 9-slice: the corners kept at SliceScale (x the supersampling), edges and middle stretched
                sx0, sy0, sx1, sy1 = (int(v) for v in n["slice"])
                k = n.get("sliceScale", 1) * SS
                L, T = int(sx0 * k), int(sy0 * k)
                Rr, B = int((src.width - sx1) * k), int((src.height - sy1) * k)
                out = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
                cols = [(0, sx0, 0, L), (sx0, sx1, L, bw - Rr), (sx1, src.width, bw - Rr, bw)]
                rows = [(0, sy0, 0, T), (sy0, sy1, T, bh - B), (sy1, src.height, bh - B, bh)]
                for (a0, a1, d0, d1) in cols:
                    for (b0, b1, e0, e1) in rows:
                        if d1 > d0 and e1 > e0 and a1 > a0 and b1 > b0:
                            out.paste(src.crop((a0, b0, a1, b1)).resize((d1 - d0, e1 - e0), Image.LANCZOS), (d0, e0))
                src = out
            elif n.get("crop"):
                k = max(bw / src.width, bh / src.height)
                src = src.resize((max(1, int(src.width * k)), max(1, int(src.height * k))), Image.LANCZOS)
                lx, ly = (src.width - bw) // 2, (src.height - bh) // 2
                src = src.crop((lx, ly, lx + bw, ly + bh))
            else:
                src = src.resize((bw, bh), Image.LANCZOS)
            m = Image.new("L", src.size, 0)
            ImageDraw.Draw(m).rounded_rectangle([0, 0, src.size[0] - 1, src.size[1] - 1], radius=r, fill=255)
            # the image's own alpha too (a clear window in a frame image shows what is under it)
            m = Image.composite(src.getchannel("A"), Image.new("L", src.size, 0), m)
            canvas.paste(src, (int(x0), int(y0)), m)
        elif n.get("halftone"):
            step = (n.get("tileSize") or [8, 8])[0] * n.get("scale", 1) * SS / 2  # the tile holds two dots across
            tile = halftone(int(x1 - x0), int(y1 - y0), n["imageC"], n["imageT"], step)
            m = Image.new("L", tile.size, 0)
            ImageDraw.Draw(m).rounded_rectangle([0, 0, tile.size[0] - 1, tile.size[1] - 1], radius=r, fill=255)
            canvas.paste(Image.alpha_composite(canvas.crop((int(x0), int(y0), int(x0) + tile.size[0], int(y0) + tile.size[1])), tile), (int(x0), int(y0)), m)
        elif n.get("rect") and sheet_for(n["image"]) is not None:
            paint_cell(canvas, n, sheet_for(n["image"]), x0, y0, x1, y1)
        elif picture(n["image"]) is not None:
            src = picture(n["image"])
            bw, bh = int(round(x1 - x0)), int(round(y1 - y0))
            ts = n.get("tileScale")
            if n.get("tile") and ts and ts[0] > 0 and ts[1] > 0:
                tw, th = max(1, int(round(bw * ts[0]))), max(1, int(round(bh * ts[1])))
                one = src.resize((tw, th), Image.LANCZOS)
                img = Image.new("RGBA", (bw, bh))
                for ty in range(0, bh, th):
                    for tx in range(0, bw, tw):
                        img.paste(one, (tx, ty))
            else:
                img = src.resize((bw, bh), Image.LANCZOS)
            layer = Image.new("RGBA", canvas.size)
            layer.paste(img, (int(round(x0)), int(round(y0))))
            canvas.alpha_composite(layer)
        elif local_image(n) is not None:
            im = local_image(n)
            bw, bh = int(x1 - x0), int(y1 - y0)
            k = min(bw / im.width, bh / im.height) if n.get("fit") else None
            size = (max(1, int(im.width * k)), max(1, int(im.height * k))) if k else (bw, bh)
            im = im.resize(size, Image.LANCZOS)
            if n.get("imageT", 0) > 0:
                a = im.split()[3].point(lambda v: int(v * (1 - n["imageT"])))
                im.putalpha(a)
            canvas.alpha_composite(im, (int(x0 + (bw - size[0]) / 2), int(y0 + (bh - size[1]) / 2)))
        else:
            d.rounded_rectangle([x0, y0, x1, y1], radius=r, outline=(255, 255, 255, 90), width=SS)
            d.line([x0, y0, x1, y1], fill=(255, 255, 255, 60), width=SS)
    if n.get("viewport"):
        d.rounded_rectangle([x0, y0, x1, y1], radius=r, fill=(80, 90, 130, 120))
    for s in n.get("strokes") or []:
        if s.get("mode") == "Contextual" and n.get("text"):
            continue
        t = s["t"] * n.get("scale", 1) * SS
        if t <= 0 or x1 <= x0:
            continue
        d.rounded_rectangle([x0 - t, y0 - t, x1 + t, y1 + t], radius=(r + t) if r > 0 else 0,
                            outline=rgba(s["color"], s.get("tr", 0)), width=max(1, int(round(t))))
    draw_text(canvas, n)
    if kids:
        for k in n["kids"]:
            draw_node(canvas, k)


def main():
    data = json.load(open(sys.argv[1]))
    out_dir = sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)
    for shot in data:
        IMAGES.clear()
        IMAGES.update(shot.get("images") or {})
        w, h = shot["w"], shot["h"]
        canvas = backdrop(w, h)
        for root in shot["roots"]:
            draw_node(canvas, root)
        img = canvas.resize((w, h), Image.LANCZOS).convert("RGB")
        path = os.path.join(out_dir, f"{PREFIX}{shot['scene']}.png")
        img.save(path)
        print(path, len(shot.get("errors", [])), "errors")


if __name__ == "__main__":
    main()
