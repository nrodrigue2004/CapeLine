# portraits.py: the Rogues File's portraits, step 2 (WP3 art pass, 2026-11-18): each page's figure
# (build/rogues/raw/<id>.png from art/blender/rogues.py) drawn as a comic "case file" card for the Journal's
# ROGUES tab (Ui.RoguesPage): a flat bright backdrop per group (robots sky blue, famous fakes hot pink, villains
# violet, world bosses fire orange) with sunburst rays and halftone dots, the figure in a bold black ink outline
# over a drop shadow, a black frame with a white rule and a dog-eared case-file corner. The 3 world bosses also
# get a gold page variant (a gold backdrop and frame with stars), shown once a boss's gold page is filled.
# The unbeaten pages keep the UI's own black silhouette (no image), so no silhouette set is uploaded.
# Output: art/export/rogues/Rogue_<Id>.png and Rogue_<Boss>_Gold.png (512 x 512, for upload: Config.Rogues
# portraits; art/upload/make_package.py packs them) and the contact sheet art/preview/rogues.png (every card
# large, and at the Journal's 56 px with its name, to check each reads at phone size).
# Run: python3 art/rogues/portraits.py   (PIL and numpy; after art/blender/rogues.py)
import json
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ART = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.path.dirname(ART)
RAW = os.path.join(REPO, "build", "rogues", "raw")
OUT = os.path.join(ART, "export", "rogues")
PAGES = os.path.join(OUT, "pages.json")
SIZE = 512
SS = 2  # drawn at twice the size, then scaled down (smooth edges)

GROUPS = {  # backdrop, its ray shade, its dots
    "robots": ((70, 170, 255), (120, 200, 255), (40, 120, 220)),
    "fakes": ((255, 90, 170), (255, 150, 205), (215, 50, 130)),
    "villains": ((150, 90, 245), (190, 145, 255), (105, 55, 200)),
    "bosses": ((255, 120, 40), (255, 175, 80), (220, 70, 25)),
    "gold": ((255, 205, 60), (255, 240, 150), (220, 150, 20)),
}
INK = (18, 18, 24)
WHITE = (255, 255, 255)


def file_name(page_id, gold=False):
    return "Rogue_%s%s.png" % (page_id, "_Gold" if gold else "")


def backdrop(n, look, centre):
    base, ray, dot = GROUPS[look]
    img = Image.new("RGB", (n, n), base)
    d = ImageDraw.Draw(img)
    cx, cy = centre
    # sunburst rays from behind the head
    rays = 18
    R = n * 1.5
    for k in range(rays):
        if k % 2:
            continue
        a0 = 2 * math.pi * k / rays
        a1 = 2 * math.pi * (k + 1) / rays
        d.polygon([(cx, cy), (cx + R * math.cos(a0), cy + R * math.sin(a0)),
                   (cx + R * math.cos(a1), cy + R * math.sin(a1))], fill=ray)
    # halftone dots, bigger toward the corners
    step = n // 26
    for y in range(0, n + step, step):
        for x in range(0, n + step, step):
            ox = (step // 2) if (y // step) % 2 else 0
            px, py = x + ox, y
            r = math.hypot(px - n / 2, py - n / 2) / (n * 0.71)
            rad = step * 0.42 * max(0.0, r - 0.35) / 0.65
            if rad > 0.6:
                d.ellipse([px - rad, py - rad, px + rad, py + rad], fill=dot)
    return img


def outlined(fig, ink_px, shadow):
    """The figure over its bold ink outline and a drop shadow (alpha from the render)."""
    a = fig.split()[3]
    a = a.point(lambda v: 255 if v > 40 else 0)
    ink = a.filter(ImageFilter.MaxFilter(ink_px * 2 + 1))
    ink = ink.filter(ImageFilter.GaussianBlur(1.2)).point(lambda v: 255 if v > 110 else 0)
    out = Image.new("RGBA", fig.size, (0, 0, 0, 0))
    sh = Image.new("RGBA", fig.size, (*shadow, 0))
    sh.putalpha(ink.point(lambda v: v * 150 // 255))
    out.alpha_composite(sh, (ink_px, ink_px * 2))
    black = Image.new("RGBA", fig.size, (*INK, 255))
    black.putalpha(ink)
    out.alpha_composite(black)
    out.alpha_composite(fig)
    return out


def star(d, cx, cy, r, fill, outline):
    pts = []
    for k in range(10):
        a = -math.pi / 2 + math.pi * k / 5
        rr = r if k % 2 == 0 else r * 0.45
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    d.polygon(pts, fill=fill, outline=outline, width=max(2, int(r * 0.18)))


def card(page, gold=False):
    n = SIZE * SS
    raw = Image.open(os.path.join(RAW, page["id"] + ".png")).convert("RGBA")
    border = 20 * SS  # the black frame
    rule = 8 * SS  # the white (or deep gold) rule inside it
    inner = n - 2 * (border + rule)
    boss = page["group"] == "bosses"
    look = "gold" if gold else page["group"]
    # the figure fills the inner box: a bust sits on its bottom edge, a boss is centred with a little air
    fit = int(inner * (0.9 if boss else 1.0))
    fig = raw.resize((fit, fit), Image.LANCZOS)
    fig = outlined(fig, 6 * SS, GROUPS[look][2])
    ox = border + rule + (inner - fit) // 2
    oy = border + rule + (inner - fit) // (2 if boss else 1)
    # rays from the figure's head (its top third)
    a = np.array(fig.split()[3])
    ys, xs = np.nonzero(a > 40)
    head = (ox + int(xs.mean()) if len(xs) else n // 2, oy + int(ys.min() + (ys.max() - ys.min()) * 0.25)
            if len(ys) else n // 3)
    img = backdrop(n, look, head).convert("RGBA")
    img.alpha_composite(fig, (ox, oy))
    d = ImageDraw.Draw(img)
    # the frame: black outside, the white rule, the case-file corner (folded top right)
    frame_c = (150, 100, 10) if gold else INK
    rule_c = (255, 240, 170) if gold else WHITE
    d.rectangle([0, 0, n - 1, n - 1], outline=frame_c, width=border)
    d.rectangle([border, border, n - 1 - border, n - 1 - border], outline=rule_c, width=rule)
    fold = 70 * SS
    d.polygon([(n - fold, 0), (n, 0), (n, fold)], fill=(0, 0, 0, 0))
    img_np = np.array(img)
    yy, xx = np.mgrid[0:n, 0:n]
    img_np[(xx - (n - fold)) > yy] = (0, 0, 0, 0)  # cut the corner off (the card's own alpha)
    img = Image.fromarray(img_np)
    d = ImageDraw.Draw(img)
    paper = (255, 225, 120) if gold else (238, 226, 196)
    d.polygon([(n - fold, 0), (n - fold, fold), (n, fold)], fill=paper, outline=frame_c, width=border // 2)
    d.line([(n - fold, 0), (n, fold)], fill=frame_c, width=border)
    if gold:
        for cx, cy, r in ((border + 52 * SS, border + 52 * SS, 40 * SS), (n - border - 50 * SS, n - border - 50 * SS,
                                                                           36 * SS)):
            star(d, cx, cy, r, (255, 230, 90), (150, 100, 10))
    return img.resize((SIZE, SIZE), Image.LANCZOS)


def font(size):
    for f in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
              "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"):
        if os.path.isfile(f):
            return ImageFont.truetype(f, size)
    return ImageFont.load_default()


def sheet(cards):
    """Every card at 150 px with the Journal's 56 px copy and its name, 8 to a row."""
    cols, cw, ch = 8, 230, 210
    rows = (len(cards) + cols - 1) // cols
    img = Image.new("RGB", (cols * cw + 20, rows * ch + 20), (36, 38, 46))
    d = ImageDraw.Draw(img)
    f = font(13)
    for i, (label, c) in enumerate(cards):
        x, y = 10 + (i % cols) * cw, 10 + (i // cols) * ch
        img.paste(c.resize((150, 150), Image.LANCZOS), (x, y), c.resize((150, 150), Image.LANCZOS))
        small = c.resize((56, 56), Image.LANCZOS)
        # the Journal row's paper behind the 56 px copy
        d.rectangle([x + 156, y + 40, x + 156 + 66, y + 40 + 76], fill=(245, 238, 220))
        img.paste(small, (x + 161, y + 50), small)
        d.text((x, y + 158), label[:30], fill=(235, 235, 240), font=f)
    return img


def main():
    pages = json.load(open(PAGES, encoding="utf-8"))
    os.makedirs(OUT, exist_ok=True)
    missing = [p["id"] for p in pages if not os.path.isfile(os.path.join(RAW, p["id"] + ".png"))]
    if missing:
        print("no render yet (art/blender/rogues.py):", ", ".join(missing))
        pages = [p for p in pages if p["id"] not in missing]
    cards = []
    for p in pages:
        c = card(p)
        c.save(os.path.join(OUT, file_name(p["id"])), optimize=True)
        cards.append((p["name"], c))
    for p in pages:
        if p.get("gold"):
            c = card(p, gold=True)
            c.save(os.path.join(OUT, file_name(p["id"], True)), optimize=True)
            cards.append((p["name"] + " (gold)", c))
    sheet(cards).save(os.path.join(ART, "preview", "rogues.png"), optimize=True)
    print(len(cards), "portraits ->", OUT, "; sheet art/preview/rogues.png")


if __name__ == "__main__":
    main()
