# art/store/post.py: finishes the store art (notes/Store Page.md; nate's picks 2026-11-17) from the Blender renders in
# art/export/store/raw/: a light grade (contrast, colour, vignette), comic speed lines, the captions in one clean
# original style (heavy italic capitals, a gold-to-white fill, an ink outline and a hard drop shadow), the boss
# bar, then the upload sizes: icons 512 x 512, thumbnails 1920 x 1080 (art/export/store/*.png). Also the contact
# sheet art/preview/store_picks.png with each icon at 150 px and 50 px, the sizes players see it at.
# Captions: at most 3 words each (Store Page rule). Fonts: Inter Black Italic (SIL Open Font License, the system
# copy), falling back to DejaVu Sans Bold.
# Run: python3 art/store/post.py [--draft]   (PIL and numpy)
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.dirname(HERE)
OUT = os.path.join(ART, "export", "store")
RAW = os.path.join(OUT, "raw")
DRAFT = "--draft" in sys.argv
SUFFIX = ".draft" if DRAFT else ""
FONTS = ["/usr/share/fonts/opentype/inter/InterDisplay-BlackItalic.otf",
         "/usr/share/fonts/opentype/inter/Inter-BlackItalic.otf",
         "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"]
INK = (16, 18, 40)


def font(size):
    for f in FONTS:
        if os.path.exists(f):
            return ImageFont.truetype(f, size)
    return ImageFont.load_default()


def grade(im, contrast=1.06, colour=1.12, vignette=0.22):
    im = ImageEnhance.Contrast(im).enhance(contrast)
    im = ImageEnhance.Color(im).enhance(colour)
    w, h = im.size
    y, x = np.mgrid[0:h, 0:w]
    d = np.sqrt(((x - w / 2) / (w / 2)) ** 2 + ((y - h / 2) / (h / 2)) ** 2) / math.sqrt(2)
    v = 1 - vignette * np.clip((d - 0.45) / 0.55, 0, 1) ** 1.6
    a = np.asarray(im).astype(np.float32) * v[..., None]
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def speed_lines(im, centre, r0, count=70, seed=1, alpha=110, length=(0.25, 0.6), width=(2, 7), colour=(255, 255, 255)):
    """Comic speed lines: thin tapered wedges radiating from centre, starting outside r0 (fractions of the
    image's diagonal for the lengths)."""
    w, h = im.size
    diag = math.hypot(w, h)
    layer = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    rng = random.Random(seed)
    cx, cy = centre
    for _ in range(count):
        a = rng.random() * 2 * math.pi
        r1 = r0 + rng.random() * diag * 0.06
        r2 = r1 + diag * (length[0] + rng.random() * (length[1] - length[0]))
        wd = width[0] + rng.random() * (width[1] - width[0])
        ux, uy = math.cos(a), math.sin(a)
        px, py = -uy, ux
        pts = [(cx + ux * r1, cy + uy * r1), (cx + ux * r2 + px * wd, cy + uy * r2 + py * wd),
               (cx + ux * r2 - px * wd, cy + uy * r2 - py * wd)]
        d.polygon(pts, fill=colour + (int(alpha * (0.5 + 0.5 * rng.random())),))
    layer = layer.filter(ImageFilter.GaussianBlur(0.8))
    base = im.convert("RGBA")
    base.alpha_composite(layer)
    return base.convert("RGB")


def caption(im, words, size, anchor, colours=None, shadow=(10, 10), stroke=None, tracking=0):
    """Draws a caption: words is a list of (text, (top colour, bottom colour)); anchor (x, y) is the caption's
    centre. The fill is a vertical gradient, then an ink outline and a hard ink shadow."""
    f = font(size)
    stroke = stroke or max(4, size // 11)
    gap = int(size * 0.28)
    widths = [f.getbbox(t)[2] - f.getbbox(t)[0] for t, _ in words]
    total = sum(widths) + gap * (len(words) - 1)
    asc = f.getbbox("HQ")
    th = asc[3] - asc[1]
    x = anchor[0] - total / 2
    y = anchor[1] - th / 2 - asc[1]
    w, h = im.size
    mask_all = Image.new("L", im.size, 0)
    fill = Image.new("RGB", im.size, (0, 0, 0))
    for (t, (top, bottom)), tw in zip(words, widths):
        m = Image.new("L", im.size, 0)
        ImageDraw.Draw(m).text((x, y), t, font=f, fill=255)
        grad = Image.new("RGB", (1, th + 2))
        for i in range(th + 2):
            k = i / (th + 1)
            grad.putpixel((0, i), tuple(int(top[c] + (bottom[c] - top[c]) * k) for c in range(3)))
        grad = grad.resize((w, th + 2))
        g = Image.new("RGB", im.size, top)
        g.paste(grad, (0, int(y + asc[1])))
        fill.paste(g, (0, 0), m)
        mask_all = ImageChops.lighter(mask_all, m)
        x += tw + gap
    outline = mask_all.filter(ImageFilter.MaxFilter(stroke * 2 + 1))
    sh = Image.new("L", im.size, 0)
    sh.paste(outline, shadow)
    base = im.convert("RGBA")
    ink = Image.new("RGBA", im.size, INK + (255,))
    base.paste(ink, (0, 0), sh.point(lambda v: int(v * 0.85)))
    base.paste(ink, (0, 0), outline)
    base.paste(fill, (0, 0), mask_all)
    return base.convert("RGB")


def boss_bar(im, frac=0.72):
    """The world boss bar (WorldHud's look: a dark frame, a red bar with a lighter top, a gold edge), no name."""
    w, h = im.size
    bw, bh = int(w * 0.46), int(h * 0.045)
    x0, y0 = (w - bw) // 2, int(h * 0.05)
    layer = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    r = bh // 2
    d.rounded_rectangle((x0 - 8, y0 - 8, x0 + bw + 8, y0 + bh + 8), r + 8, fill=INK + (235,), outline=(255, 200, 70, 255),
                        width=5)
    d.rounded_rectangle((x0, y0, x0 + bw, y0 + bh), r, fill=(60, 20, 26, 255))
    fw = int(bw * frac)
    d.rounded_rectangle((x0, y0, x0 + fw, y0 + bh), r, fill=(232, 44, 52, 255))
    d.rounded_rectangle((x0 + 6, y0 + 4, x0 + fw - 6, y0 + bh // 2 - 1), r // 2, fill=(255, 120, 110, 160))
    # phase marks at 66% and 33% (BossSim phases)
    for p in (0.33, 0.66):
        px = x0 + int(bw * p)
        d.rectangle((px - 2, y0, px + 2, y0 + bh), fill=INK + (255,))
    base = im.convert("RGBA")
    base.alpha_composite(layer)
    return base.convert("RGB")


def load(name):
    path = os.path.join(RAW, name + SUFFIX + ".png")
    if not os.path.exists(path):
        print("missing", path)
        return None
    return Image.open(path).convert("RGB")


def save(im, name):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + SUFFIX + ".png")
    im.save(path, optimize=True)
    print("wrote", path, im.size)
    return path


def icon(name, lines=None):
    im = load("icon_" + name)
    if im is None:
        return None
    im = grade(im)
    w, h = im.size
    if lines:
        im = speed_lines(im, (w * lines[0], h * lines[1]), w * lines[2], count=lines[3], seed=3, alpha=120,
                         length=(0.18, 0.4), width=(2, 6))
    im = im.resize((512, 512), Image.LANCZOS).filter(ImageFilter.UnsharpMask(1.2, 60, 2))
    return save(im, "icon_" + name)


def thumb(name, cap, lines=None, bar=False):
    im = load("thumb_" + name)
    if im is None:
        return None
    if im.size != (1920, 1080):
        im = im.resize((1920, 1080), Image.LANCZOS)
    im = grade(im, vignette=0.18)
    if lines:
        im = speed_lines(im, (1920 * lines[0], 1080 * lines[1]), 1920 * lines[2], count=lines[3], seed=5, alpha=95,
                         length=(0.15, 0.35), width=(2, 6))
    if bar:
        im = boss_bar(im)
    words, size, at = cap
    im = caption(im, words, size, (1920 * at[0], 1080 * at[1]))
    return save(im, "thumb_" + name)


GOLD = ((255, 250, 220), (255, 196, 40))
WHITE = ((255, 255, 255), (214, 228, 255))
PURPLE = ((236, 200, 255), (170, 80, 255))
RED = ((255, 226, 214), (240, 52, 40))  # the fake's red eye


def sheet(icons, thumbs):
    """The contact sheet: each icon at 512, 150 and 50 px (how a phone shows it), then the thumbnails."""
    W = 1920
    pad = 30
    out = Image.new("RGB", (W, 2000), (30, 32, 44))
    d = ImageDraw.Draw(out)
    fs = font(26)
    d.text((pad, 20), "Capeline store art, nate's picks (Store Page.md): icons (512 px files, shown at 400, 150 and 50 px) and thumbnails (1920 x 1080)",
           font=fs, fill=(230, 230, 240))
    x, y = pad, 70
    big = 400
    for p in icons:
        if not p:
            continue
        im = Image.open(p)
        out.paste(im.resize((big, big), Image.LANCZOS), (x, y))
        out.paste(im.resize((150, 150), Image.LANCZOS), (x + big + 14, y))
        out.paste(im.resize((50, 50), Image.LANCZOS), (x + big + 14, y + 164))
        d.text((x, y + big + 6), os.path.basename(p), font=fs, fill=(200, 204, 220))
        x += big + 14 + 150 + 52
    y += big + 60
    tw = (W - pad * 4) // 3
    th = tw * 9 // 16
    x = pad
    for p in thumbs:
        if not p:
            continue
        out.paste(Image.open(p).resize((tw, th), Image.LANCZOS), (x, y))
        d.text((x, y + th + 6), os.path.basename(p), font=fs, fill=(200, 204, 220))
        x += tw + pad
    out = out.crop((0, 0, W, y + th + 50))
    path = os.path.join(ART, "preview", "store_picks%s.png" % SUFFIX)
    out.save(path, optimize=True)
    print("wrote", path)


if __name__ == "__main__":
    icons = [icon("clash", lines=(0.5, 0.5, 0.42, 70)), icon("smash", lines=(0.62, 0.42, 0.38, 50))]
    thumbs = [
        thumb("build", ([("HERO", GOLD), ("OR", WHITE), ("VILLAIN?", PURPLE)], 150, (0.5, 0.13))),
        thumb("boss", ([("GIANT", WHITE), ("WORLD", WHITE), ("BOSS", GOLD)], 150, (0.5, 0.86)), bar=True),
        thumb("twist", ([("TRUST", WHITE), ("NO", WHITE), ("HERO", RED)], 150, (0.5, 0.86)),
              lines=(0.6, 0.38, 0.12, 60)),
    ]
    sheet(icons, thumbs)
