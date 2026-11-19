# art/prologue/ads.py: the Ceremony prologue's two printed pictures (gap-prologue, 2026-11-19), comic style:
# * CraneBillboard.png: the Crane Industries ad on the billboard of the last shot (70 x 40 studs, 1024 x 585):
#   a sunburst and a spotlight on the left third, where Silas Crane himself stands in front of the board in the
#   game (his real rig with his Roblox catalog face and catalog hair, PrologueFx: nate's rule, no face or hair
#   is ever drawn by us, so the picture holds no person), the Crane Industries crest (an original folded crane
#   bird in a shield), the brand and the slogan on a ribbon, a skyline and halftone dots
# * HallBanner.png: the banner on the face of Crane's Hero Hall behind the stage (44 x 16 studs, 1024 x 372):
#   CRANE'S HERO HALL over CRANE INDUSTRIES, gold on navy, stars and the crest
# The words are the game's fixed text (Config.Story.opening.brand, slogan and hall), read from the config so
# a text change shows here on the next run. Original designs: no real brand, logo or person.
# Output: art/export/prologue/CraneBillboard.png, HallBanner.png and art/preview/prologue_ads.png.
# Run: python3 art/prologue/ads.py   (PIL only)
import math
import os
import re

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "export", "prologue")
PREV = os.path.join(ROOT, "preview")
os.makedirs(OUT, exist_ok=True)
os.makedirs(PREV, exist_ok=True)

STORY = open(os.path.join(ROOT, "..", "src", "config", "Story.luau"), encoding="utf-8").read()


def fixed(key):
    m = re.search(r"^\t\t" + key + r' = "([^"]+)"', STORY, re.M)
    assert m, "Config.Story.opening." + key
    return m.group(1)


BRAND, SLOGAN, HALL = fixed("brand"), fixed("slogan"), fixed("hall")

BLACKF = "/usr/share/fonts/opentype/inter/InterDisplay-Black.otf"
BLACKI = "/usr/share/fonts/opentype/inter/InterDisplay-BlackItalic.otf"
K = 2  # drawn at twice the size, scaled down once (smooth edges)

INK = (22, 20, 34)
NAVY = (26, 34, 78)
DEEP = (14, 20, 52)
GOLD = (255, 206, 58)
GOLD2 = (236, 150, 30)
RED = (214, 36, 52)
WHITE = (250, 248, 240)
SKY = (70, 120, 220)


def font(path, px):
    return ImageFont.truetype(path, int(px * K))


def fit_font(path, text, width, px):
    """The biggest size up to px whose text fits width."""
    while px > 8:
        f = font(path, px)
        if f.getbbox(text)[2] <= width:
            return f
        px -= 2
    return font(path, 8)


def outlined(d, xy, text, f, fill, ink=INK, stroke=10, shadow=(10, 10), anchor="mm"):
    """Comic lettering: a hard drop shadow, a thick ink outline, the fill."""
    sx, sy = shadow
    d.text((xy[0] + sx * K, xy[1] + sy * K), text, font=f, fill=ink, anchor=anchor, stroke_width=stroke * K,
           stroke_fill=ink)
    d.text(xy, text, font=f, fill=fill, anchor=anchor, stroke_width=stroke * K, stroke_fill=ink)


def gold_text(im, xy, text, f, stroke=10):
    """Gold lettering with a light top and a deep bottom (a gradient through the glyphs), outlined in ink."""
    d = ImageDraw.Draw(im)
    outlined(d, xy, text, f, GOLD, stroke=stroke)
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).text(xy, text, font=f, fill=255, anchor="mm")
    box = mask.getbbox()
    if not box:
        return
    grad = Image.new("RGB", im.size, GOLD)
    gd = ImageDraw.Draw(grad)
    for y in range(box[1], box[3]):
        t = (y - box[1]) / max(1, box[3] - box[1])
        if t < 0.45:
            c = tuple(int(GOLD[i] + (255 - GOLD[i]) * (0.45 - t) * 1.2) for i in range(3))
        else:
            c = tuple(int(GOLD[i] + (GOLD2[i] - GOLD[i]) * (t - 0.45) / 0.55) for i in range(3))
        gd.line([(box[0], y), (box[2], y)], fill=c)
    im.paste(grad, (0, 0), mask)
    # a shine stripe across the top third
    shine = Image.new("L", im.size, 0)
    sd = ImageDraw.Draw(shine)
    h = box[3] - box[1]
    sd.rectangle([box[0], box[1] + h * 0.16, box[2], box[1] + h * 0.26], fill=110)
    shine = Image.composite(shine, Image.new("L", im.size, 0), mask)
    im.paste((255, 255, 236), (0, 0), shine)


def halftone(im, box, color, step, rmax, direction=(0, 1)):
    """Comic halftone dots growing along direction across box."""
    d = ImageDraw.Draw(im)
    x0, y0, x1, y1 = box
    for j, y in enumerate(range(int(y0), int(y1), step)):
        for x in range(int(x0) + (step // 2 if j % 2 else 0), int(x1), step):
            t = ((x - x0) / (x1 - x0)) * direction[0] + ((y - y0) / (y1 - y0)) * direction[1]
            r = rmax * max(0.0, min(1.0, t))
            if r > 0.6:
                d.ellipse([x - r, y - r, x + r, y + r], fill=color)


def crest(im, cx, cy, s):
    """The Crane Industries crest: a gold-rimmed navy shield with a folded paper crane bird (an original mark)."""
    d = ImageDraw.Draw(im)
    def shield(k):
        w, h = s * k, s * 1.18 * k
        pts = [(cx - w, cy - h * 0.62), (cx, cy - h * 0.8), (cx + w, cy - h * 0.62), (cx + w * 0.92, cy + h * 0.1),
               (cx, cy + h * 0.78), (cx - w * 0.92, cy + h * 0.1)]
        return pts
    d.polygon([(x + 8 * K, y + 8 * K) for (x, y) in shield(1.0)], fill=INK)
    d.polygon(shield(1.0), fill=INK)
    d.polygon(shield(0.9), fill=GOLD)
    d.polygon(shield(0.78), fill=NAVY)
    # the folded crane (side on): a wing up behind, a wing up in front, the long neck with the head bent down to
    # the left, the tail up to the right, a diamond body; white and pale blue facets in ink
    u = s * 0.66
    cy += u * 0.12
    back_wing = [(cx - u * 0.3, cy + u * 0.1), (cx - u * 0.42, cy - u * 0.9), (cx + u * 0.15, cy + u * 0.02)]
    tail = [(cx + u * 0.13, cy + u * 0.09), (cx + u * 0.95, cy - u * 0.42), (cx + u * 0.37, cy + u * 0.35)]
    neck = [(cx - u * 0.11, cy + u * 0.1), (cx - u * 0.82, cy - u * 0.5), (cx - u * 0.39, cy + u * 0.34)]
    head = [(cx - u * 0.86, cy - u * 0.56), (cx - u * 1.06, cy - u * 0.22), (cx - u * 0.68, cy - u * 0.36)]
    body = [(cx - u * 0.38, cy + u * 0.18), (cx, cy - u * 0.02), (cx + u * 0.38, cy + u * 0.18), (cx, cy + u * 0.5)]
    wing = [(cx - u * 0.2, cy + u * 0.12), (cx + u * 0.28, cy - u * 1.0), (cx + u * 0.42, cy + u * 0.14)]
    for pts, c in ((back_wing, (170, 200, 248)), (tail, (214, 228, 252)), (neck, (214, 228, 252)), (head, WHITE),
                   (body, WHITE), (wing, WHITE)):
        d.polygon(pts, fill=c, outline=INK, width=4 * K)
    d.line([(cx + u * 0.3, cy - u * 1.0), (cx + u * 0.1, cy + u * 0.06)], fill=(170, 200, 248), width=3 * K)
    cy -= u * 0.12
    # a gold spark star over the bird
    star(d, cx - u * 0.62, cy - u * 0.95, u * 0.24, GOLD)


def star(d, cx, cy, r, color, points=5, inner=0.45, ink=True):
    pts = []
    for i in range(points * 2):
        a = -math.pi / 2 + i * math.pi / points
        rr = r if i % 2 == 0 else r * inner
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    d.polygon(pts, fill=color, outline=INK if ink else None, width=(3 * K) if ink else 0)


def billboard():
    W, H = 1024 * K, 585 * K
    im = Image.new("RGB", (W, H), DEEP)
    d = ImageDraw.Draw(im)
    # the sky: deep navy at the top to a bright blue at the bottom
    for y in range(H):
        t = y / H
        c = tuple(int(DEEP[i] + (SKY[i] - DEEP[i]) * t ** 1.2) for i in range(3))
        d.line([(0, y), (W, y)], fill=c)
    halftone(im, (0, 0, W, H), (40, 66, 150), 18 * K, 6 * K, (0.35, 0.65))
    # the left third: a sunburst behind where Crane stands, a white spotlight disc
    cx, cy = W * 0.2, H * 0.42
    for i in range(24):
        a0 = i * 2 * math.pi / 24
        a1 = a0 + math.pi / 24
        R = W * 0.9
        col = (255, 196, 54) if i % 2 == 0 else (255, 150, 44)
        d.polygon([(cx, cy), (cx + math.cos(a0) * R, cy + math.sin(a0) * R),
                   (cx + math.cos(a1) * R, cy + math.sin(a1) * R)], fill=col)
    # the burst only on the left panel: a slanted cut keeps the right side blue
    cut = Image.new("L", (W, H), 0)
    ImageDraw.Draw(cut).polygon([(0, 0), (W * 0.44, 0), (W * 0.36, H), (0, H)], fill=255)
    base = Image.new("RGB", (W, H), DEEP)
    bd = ImageDraw.Draw(base)
    for y in range(H):
        t = y / H
        bd.line([(0, y), (W, y)], fill=tuple(int(DEEP[i] + (SKY[i] - DEEP[i]) * t ** 1.2) for i in range(3)))
    halftone(base, (0, 0, W, H), (40, 66, 150), 18 * K, 6 * K, (0.35, 0.65))
    im = Image.composite(im, base, cut)
    d = ImageDraw.Draw(im)
    halftone(im, (0, 0, W * 0.44, H), (255, 228, 120), 16 * K, 5 * K, (-0.6, 0.4))
    glow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(glow).ellipse([cx - W * 0.15, cy - W * 0.15, cx + W * 0.15, cy + W * 0.15], fill=255)
    glow = glow.filter(ImageFilter.GaussianBlur(26 * K))
    im.paste((255, 250, 226), (0, 0), glow)
    d = ImageDraw.Draw(im)
    # the panel's slanted ink edge
    d.line([(W * 0.44, 0), (W * 0.36, H)], fill=INK, width=12 * K)
    d.line([(W * 0.445 + 10 * K, 0), (W * 0.365 + 10 * K, H)], fill=GOLD, width=5 * K)
    # the skyline along the bottom of the right side (the city, safe and bright)
    rng = 7
    x = W * 0.34
    while x < W:
        rng = (rng * 1103515245 + 12345) % 2147483648
        bw = (40 + rng % 70) * K
        bh = (60 + (rng // 97) % 130) * K
        d.rectangle([x, H - bh, x + bw, H], fill=(20, 30, 74))
        for wy in range(int(H - bh + 14 * K), int(H - 10 * K), 22 * K):
            for wx in range(int(x + 8 * K), int(x + bw - 10 * K), 18 * K):
                if ((wx // K) * 7 + (wy // K) * 3 + rng) % 5 < 2:
                    d.rectangle([wx, wy, wx + 7 * K, wy + 10 * K], fill=(255, 220, 110))
        x += bw + 6 * K
    # the crest, the brand and the slogan on a ribbon
    crest(im, W * 0.56, H * 0.3, 92 * K)
    words = BRAND.split(" ", 1)
    f1 = fit_font(BLACKI, words[0], W * 0.33, 150)
    gold_text(im, (W * 0.8, H * 0.22), words[0], f1, stroke=9)
    if len(words) > 1:
        f2 = fit_font(BLACKI, words[1], W * 0.33, 70)
        d = ImageDraw.Draw(im)
        outlined(d, (W * 0.8, H * 0.39), words[1], f2, WHITE, stroke=7, shadow=(7, 7))
    d = ImageDraw.Draw(im)
    # the ribbon: a red band with folded tails, the slogan in white
    ry, rh = H * 0.6, H * 0.15
    rx0, rx1 = W * 0.4, W * 0.97
    for side in (-1, 1):
        ex = rx0 if side < 0 else rx1
        tail = [(ex, ry + rh * 0.25), (ex + side * 46 * K, ry + rh * 0.25), (ex + side * 26 * K, ry + rh * 0.75),
                (ex + side * 46 * K, ry + rh * 1.25), (ex, ry + rh * 1.25)]
        d.polygon(tail, fill=(150, 18, 34), outline=INK, width=5 * K)
    d.polygon([(rx0, ry), (rx1, ry), (rx1, ry + rh), (rx0, ry + rh)], fill=RED, outline=INK, width=6 * K)
    d.line([(rx0 + 8 * K, ry + 10 * K), (rx1 - 8 * K, ry + 10 * K)], fill=(244, 96, 104), width=4 * K)
    lines = [SLOGAN]
    f3 = fit_font(BLACKF, SLOGAN, (rx1 - rx0) * 0.92, 44)
    if f3.size < 30 * K:  # too small on one line: split it in two at the comma
        lines = [s.strip() + ("," if i == 0 else "") for i, s in enumerate(SLOGAN.split(",", 1))]
        f3 = fit_font(BLACKF, max(lines, key=len), (rx1 - rx0) * 0.9, 40)
    for i, line in enumerate(lines):
        yy = ry + rh * (i + 0.5) / len(lines)
        outlined(d, ((rx0 + rx1) / 2, yy), line, f3, WHITE, stroke=4, shadow=(4, 4))
    # stars and spark twinkles
    for (sx, sy, r) in ((0.47, 0.12, 22), (0.95, 0.07, 16), (0.66, 0.5, 13), (0.98, 0.5, 12), (0.07, 0.86, 20),
                        (0.31, 0.1, 15)):
        star(d, W * sx, H * sy, r * K, WHITE)
    # the comic frame
    d.rectangle([0, 0, W - 1, H - 1], outline=INK, width=16 * K)
    d.rectangle([16 * K, 16 * K, W - 16 * K, H - 16 * K], outline=GOLD, width=5 * K)
    im = im.resize((W // K, H // K), Image.LANCZOS)
    path = os.path.join(OUT, "CraneBillboard.png")
    im.save(path)
    return im


def banner():
    W, H = 1024 * K, 372 * K
    im = Image.new("RGB", (W, H), NAVY)
    d = ImageDraw.Draw(im)
    for y in range(H):
        t = abs(y / H - 0.45) * 2
        d.line([(0, y), (W, y)], fill=tuple(int(NAVY[i] * (1 - 0.35 * t) + 6 * t) for i in range(3)))
    # fabric folds: soft vertical light and shade bands
    folds = Image.new("L", (W, H), 0)
    fd = ImageDraw.Draw(folds)
    for i in range(9):
        x = W * (i + 0.5) / 9
        fd.rectangle([x - 16 * K, 0, x + 16 * K, H], fill=40)
    folds = folds.filter(ImageFilter.GaussianBlur(22 * K))
    im.paste((120, 140, 220), (0, 0), folds)
    halftone(im, (0, 0, W, H), (44, 56, 120), 16 * K, 4 * K, (0, 1))
    d = ImageDraw.Draw(im)
    # gold borders and a row of stars along the top and bottom
    for inset, wid, col in ((0, 20, INK), (20, 14, GOLD), (40, 4, INK)):
        d.rectangle([inset * K, inset * K, W - inset * K, H - inset * K], outline=col, width=wid * K)
    for i in range(13):
        x = W * (i + 0.5) / 13
        star(d, x, 70 * K, 13 * K, GOLD)
        star(d, x, H - 62 * K, 9 * K, (244, 196, 70), ink=False)
    crest(im, W * 0.09, H * 0.55, 60 * K)
    crest(im, W * 0.91, H * 0.55, 60 * K)
    f1 = fit_font(BLACKF, HALL, W * 0.7, 128)
    gold_text(im, (W * 0.5, H * 0.47), HALL, f1, stroke=9)
    d = ImageDraw.Draw(im)
    f2 = fit_font(BLACKF, BRAND, W * 0.42, 52)
    outlined(d, (W * 0.5, H * 0.74), BRAND, f2, WHITE, stroke=5, shadow=(5, 5))
    im = im.resize((W // K, H // K), Image.LANCZOS)
    im.save(os.path.join(OUT, "HallBanner.png"))
    return im


bb = billboard()
bn = banner()
sheet = Image.new("RGB", (1024, 585 + 372 + 30), (24, 26, 32))
sheet.paste(bb, (0, 0))
sheet.paste(bn, (0, 585 + 30))
sheet.save(os.path.join(PREV, "prologue_ads.png"))
print("ads:", os.path.join(OUT, "CraneBillboard.png"), os.path.join(OUT, "HallBanner.png"))
