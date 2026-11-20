# art/city/ads.py: the rooftop billboards' printed ads (list-combat 2026-11-20, Everything Left 269: "billboard
# faces have no designs"). Eight original in-world comic ads for Brightharbor's brands, one per picture, drawn for
# the billboard's art panel (17.8 x 7.2 studs: 1024 x 414): a bold background (sunburst, stripes or sky with comic
# halftone), a big product drawn in shapes and ink, the brand in outlined comic lettering and a short tagline.
# Fixed text only (no player text). Original designs: no real brand, logo, character or person.
# Output: art/export/city/ads/Ad<N>.png and art/preview/city_ads.png; nate's ids go in Config.City.kit.play
# .billboard.ads (uploaded by the cloud loop as assetType Image).
# Run: python3 art/city/ads.py   (PIL only)
import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "export", "city", "ads")
PREV = os.path.join(ROOT, "preview")
os.makedirs(OUT, exist_ok=True)

BLACK = "/usr/share/fonts/opentype/inter/InterDisplay-Black.otf"
BLACKI = "/usr/share/fonts/opentype/inter/InterDisplay-BlackItalic.otf"
K = 2
W, H = 1024 * K, 414 * K
INK = (22, 20, 34)
WHITE = (250, 248, 240)


def font(path, px):
    return ImageFont.truetype(path, int(px * K))


def fit(path, text, width, px):
    while px > 10:
        f = font(path, px)
        if f.getbbox(text, stroke_width=8 * K)[2] <= width:
            return f
        px -= 2
    return font(path, 10)


def lettering(d, xy, text, f, fill, stroke=9, shadow=8, anchor="mm"):
    d.text((xy[0] + shadow * K, xy[1] + shadow * K), text, font=f, fill=INK, anchor=anchor,
           stroke_width=stroke * K, stroke_fill=INK)
    d.text(xy, text, font=f, fill=fill, anchor=anchor, stroke_width=stroke * K, stroke_fill=INK)


def halftone(im, box, color, step, rmax, direction=(0, 1)):
    d = ImageDraw.Draw(im)
    x0, y0, x1, y1 = box
    for j, y in enumerate(range(int(y0), int(y1), step)):
        for x in range(int(x0) + (step // 2 if j % 2 else 0), int(x1), step):
            t = ((x - x0) / (x1 - x0)) * direction[0] + ((y - y0) / (y1 - y0)) * direction[1]
            r = rmax * max(0.0, min(1.0, t))
            if r > 0.6:
                d.ellipse([x - r, y - r, x + r, y + r], fill=color)


def burst(im, cx, cy, a, b, n=20):
    d = ImageDraw.Draw(im)
    for i in range(n):
        a0 = i * 2 * math.pi / n
        a1 = a0 + math.pi / n
        R = W * 1.2
        d.polygon([(cx, cy), (cx + math.cos(a0) * R, cy + math.sin(a0) * R),
                   (cx + math.cos(a1) * R, cy + math.sin(a1) * R)], fill=a if i % 2 == 0 else b)


def gradient(im, top, bottom):
    d = ImageDraw.Draw(im)
    for y in range(H):
        t = y / H
        d.line([(0, y), (W, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))


def stripes(im, a, b, w=60):
    d = ImageDraw.Draw(im)
    for i in range(-H // (w * K) - 2, W // (w * K) + 4):
        x = i * w * K * 2
        d.polygon([(x, 0), (x + w * K, 0), (x + w * K - H * 0.5, H), (x - H * 0.5, H)], fill=b)
    return a


def star(d, cx, cy, r, color, points=5, inner=0.45):
    pts = []
    for i in range(points * 2):
        a = -math.pi / 2 + i * math.pi / points
        rr = r if i % 2 == 0 else r * inner
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    d.polygon(pts, fill=color, outline=INK, width=4 * K)


def bolt(d, x, y, s, color):
    pts = [(x, y - s), (x - s * 0.45, y + s * 0.1), (x - s * 0.05, y + s * 0.1), (x - s * 0.25, y + s),
           (x + s * 0.45, y - s * 0.15), (x + s * 0.05, y - s * 0.15), (x + s * 0.3, y - s)]
    d.polygon(pts, fill=color, outline=INK, width=5 * K)


def text_block(im, brand, tag, x0, x1, fill, tagfill=WHITE, top=0.36, bottom=0.78, path=BLACKI):
    d = ImageDraw.Draw(im)
    cx = (x0 + x1) / 2
    f = fit(path, brand, (x1 - x0) * 0.94, 120)
    lettering(d, (cx, H * top), brand, f, fill)
    t = fit(BLACK, tag, (x1 - x0) * 0.86, 46)
    bb = d.textbbox((cx, H * bottom), tag, font=t, anchor="mm")
    pad = 14 * K
    d.rounded_rectangle([bb[0] - pad * 2, bb[1] - pad, bb[2] + pad * 2, bb[3] + pad], radius=12 * K, fill=INK)
    d.text((cx, H * bottom), tag, font=t, fill=tagfill, anchor="mm")


# ------------------------------------------------------------------ the eight ads
def ad_cola():
    im = Image.new("RGB", (W, H), (210, 34, 46))
    burst(im, W * 0.22, H * 0.55, (232, 52, 58), (196, 26, 40))
    halftone(im, (0, 0, W, H), (150, 16, 30), 18 * K, 6 * K, (0.5, 0.5))
    d = ImageDraw.Draw(im)
    # the bottle: a rounded body, a neck, a cap, a label with a bolt
    cx, cy = W * 0.2, H * 0.52
    d.rounded_rectangle([cx - 70 * K, cy - 90 * K, cx + 70 * K, cy + 170 * K], radius=50 * K, fill=(70, 30, 20),
                        outline=INK, width=7 * K)
    d.polygon([(cx - 70 * K, cy - 60 * K), (cx - 34 * K, cy - 150 * K), (cx + 34 * K, cy - 150 * K),
               (cx + 70 * K, cy - 60 * K)], fill=(70, 30, 20), outline=INK, width=7 * K)
    d.rectangle([cx - 38 * K, cy - 182 * K, cx + 38 * K, cy - 150 * K], fill=(250, 206, 60), outline=INK,
                width=6 * K)
    d.rounded_rectangle([cx - 74 * K, cy - 10 * K, cx + 74 * K, cy + 90 * K], radius=10 * K, fill=WHITE,
                        outline=INK, width=6 * K)
    bolt(d, cx, cy + 40 * K, 42 * K, (250, 206, 60))
    d.ellipse([cx - 50 * K, cy - 120 * K, cx - 30 * K, cy - 40 * K], fill=(150, 90, 70))
    for (x, y, r) in ((cx + 120 * K, cy - 120 * K, 14), (cx + 150 * K, cy - 60 * K, 9), (cx + 100 * K, cy - 170 * K, 7)):
        d.ellipse([x - r * K, y - r * K, x + r * K, y + r * K], fill=WHITE, outline=INK, width=3 * K)
    text_block(im, "ZAP! COLA", "THE TASTE THAT CRACKLES", W * 0.38, W * 0.98, (255, 214, 64))
    return im


def ad_news():
    im = Image.new("RGB", (W, H), (24, 36, 84))
    gradient(im, (18, 26, 66), (52, 90, 190))
    halftone(im, (0, 0, W, H), (40, 64, 140), 18 * K, 6 * K, (0.3, 0.7))
    d = ImageDraw.Draw(im)
    cx, cy = W * 0.78, H * 0.5
    d.rounded_rectangle([cx - 170 * K, cy - 120 * K, cx + 170 * K, cy + 110 * K], radius=26 * K, fill=(40, 40, 52),
                        outline=INK, width=8 * K)
    d.rounded_rectangle([cx - 140 * K, cy - 94 * K, cx + 140 * K, cy + 84 * K], radius=14 * K, fill=(120, 200, 255),
                        outline=INK, width=5 * K)
    d.rectangle([cx - 140 * K, cy + 40 * K, cx + 140 * K, cy + 84 * K], fill=(214, 36, 52))
    d.text((cx, cy + 62 * K), "LIVE", font=font(BLACK, 34), fill=WHITE, anchor="mm")
    for i, x in enumerate((-90, -30, 40, 100)):
        hgt = (60, 100, 76, 120)[i]
        d.rectangle([cx + (x - 22) * K, cy + (30 - hgt) * K, cx + (x + 22) * K, cy + 40 * K], fill=(30, 50, 110))
    d.line([(cx - 60 * K, cy - 120 * K), (cx - 110 * K, cy - 190 * K)], fill=INK, width=8 * K)
    d.line([(cx + 60 * K, cy - 120 * K), (cx + 110 * K, cy - 190 * K)], fill=INK, width=8 * K)
    text_block(im, "CRANE NEWS NETWORK", "WE SEE IT ALL. 24/7.", W * 0.03, W * 0.58, WHITE, top=0.38)
    return im


def ad_bank():
    im = Image.new("RGB", (W, H), (22, 96, 72))
    burst(im, W * 0.8, H * 0.5, (30, 120, 88), (20, 92, 68), 24)
    halftone(im, (0, 0, W, H), (14, 70, 52), 18 * K, 6 * K, (0.6, 0.4))
    d = ImageDraw.Draw(im)
    cx, cy = W * 0.8, H * 0.5
    d.ellipse([cx - 150 * K, cy - 150 * K, cx + 150 * K, cy + 150 * K], fill=(170, 176, 186), outline=INK,
              width=8 * K)
    d.ellipse([cx - 112 * K, cy - 112 * K, cx + 112 * K, cy + 112 * K], fill=(200, 206, 214), outline=INK,
              width=5 * K)
    for k in range(6):
        a = k * math.pi / 3
        d.line([(cx, cy), (cx + math.cos(a) * 80 * K, cy + math.sin(a) * 80 * K)], fill=INK, width=10 * K)
    d.ellipse([cx - 30 * K, cy - 30 * K, cx + 30 * K, cy + 30 * K], fill=(250, 206, 60), outline=INK, width=5 * K)
    for (x, y) in ((cx - 200 * K, cy + 110 * K), (cx - 170 * K, cy + 130 * K), (cx - 230 * K, cy + 135 * K)):
        d.ellipse([x - 36 * K, y - 16 * K, x + 36 * K, y + 16 * K], fill=(250, 206, 60), outline=INK, width=4 * K)
    text_block(im, "BRIGHTHARBOR BANK", "YOUR COINS, SAFE AND SOUND", W * 0.03, W * 0.6, (255, 214, 64))
    return im


def ad_donuts():
    im = Image.new("RGB", (W, H), (255, 150, 190))
    stripes(im, None, (255, 176, 206), 50)
    halftone(im, (0, 0, W, H), (240, 120, 170), 18 * K, 5 * K, (0.4, 0.6))
    d = ImageDraw.Draw(im)
    cx, cy = W * 0.22, H * 0.52
    d.ellipse([cx - 160 * K, cy - 130 * K, cx + 160 * K, cy + 130 * K], fill=(214, 150, 80), outline=INK, width=8 * K)
    icing = [(cx + math.cos(a / 20 * math.pi * 2) * (140 + 10 * math.sin(a * 1.7)) * K,
              cy + math.sin(a / 20 * math.pi * 2) * (112 + 9 * math.cos(a * 2.3)) * K - 8 * K) for a in range(20)]
    d.polygon(icing, fill=(255, 110, 170), outline=INK, width=5 * K)
    d.ellipse([cx - 50 * K, cy - 40 * K, cx + 50 * K, cy + 40 * K], fill=(255, 150, 190), outline=INK, width=6 * K)
    cols = [(255, 240, 80), (120, 220, 255), (255, 255, 255), (130, 230, 130)]
    for k in range(26):
        a = k * 2.399
        r = 78 + (k * 37) % 50
        x, y = cx + math.cos(a) * r * K, cy - 6 * K + math.sin(a) * r * 0.78 * K
        d.line([(x - 9 * K, y - 4 * K), (x + 9 * K, y + 4 * K)], fill=cols[k % 4], width=7 * K)
    text_block(im, "MEGA DONUTS", "A HOLE LOT OF FLAVOR", W * 0.42, W * 0.98, WHITE, tagfill=(255, 200, 225))
    return im


def ad_ferry():
    im = Image.new("RGB", (W, H), (90, 170, 240))
    gradient(im, (110, 190, 255), (210, 236, 255))
    d = ImageDraw.Draw(im)
    d.ellipse([W * 0.06, H * 0.08, W * 0.06 + 120 * K, H * 0.08 + 120 * K], fill=(255, 220, 90), outline=INK,
              width=5 * K)
    for k in range(4):
        y = H * (0.72 + k * 0.08)
        pts = [(x, y + math.sin(x / (40 * K) + k) * 8 * K) for x in range(0, W + 20 * K, 20 * K)]
        d.polygon(pts + [(W, H), (0, H)], fill=(30 + k * 10, 100 + k * 12, 200 - k * 10))
        d.line(pts, fill=WHITE, width=4 * K)
    cx, cy = W * 0.73, H * 0.66
    d.polygon([(cx - 220 * K, cy - 40 * K), (cx + 220 * K, cy - 40 * K), (cx + 170 * K, cy + 50 * K),
               (cx - 190 * K, cy + 50 * K)], fill=(214, 36, 52), outline=INK, width=7 * K)
    d.rectangle([cx - 150 * K, cy - 110 * K, cx + 120 * K, cy - 40 * K], fill=WHITE, outline=INK, width=6 * K)
    for x in range(-130, 110, 44):
        d.rounded_rectangle([cx + x * K, cy - 96 * K, cx + (x + 28) * K, cy - 66 * K], radius=6 * K,
                            fill=(120, 200, 255), outline=INK, width=3 * K)
    d.rectangle([cx - 40 * K, cy - 180 * K, cx + 20 * K, cy - 110 * K], fill=(250, 206, 60), outline=INK, width=6 * K)
    d.rectangle([cx - 40 * K, cy - 180 * K, cx + 20 * K, cy - 160 * K], fill=INK)
    text_block(im, "HARBOR FERRY", "SAIL THE BAY TODAY", W * 0.03, W * 0.52, (255, 214, 64), tagfill=WHITE,
               top=0.3, bottom=0.6)
    return im


def ad_radio():
    im = Image.new("RGB", (W, H), (70, 30, 110))
    burst(im, W * 0.78, H * 0.62, (110, 50, 160), (80, 34, 124), 22)
    halftone(im, (0, 0, W, H), (54, 22, 90), 18 * K, 6 * K, (0.4, 0.6))
    d = ImageDraw.Draw(im)
    cx, top, base = W * 0.78, H * 0.12, H * 0.98
    d.polygon([(cx - 90 * K, base), (cx, top), (cx + 90 * K, base)], outline=(240, 70, 90), width=10 * K)
    for k in range(1, 6):
        y = top + (base - top) * k / 6
        hw = 90 * K * k / 6
        d.line([(cx - hw, y), (cx + hw, y)], fill=(240, 70, 90), width=6 * K)
        d.line([(cx - hw, y), (cx + hw * (k + 1) / k * 0.9, y + (base - top) / 6)], fill=(200, 50, 70), width=4 * K)
    d.ellipse([cx - 18 * K, top - 18 * K, cx + 18 * K, top + 18 * K], fill=(255, 240, 120), outline=INK, width=4 * K)
    for r in (60, 100, 140):
        d.arc([cx - r * K, top - r * K, cx + r * K, top + r * K], 200, 340, fill=(255, 240, 120), width=8 * K)
    for (x, y) in ((cx - 260 * K, H * 0.2), (cx + 180 * K, H * 0.3)):
        d.text((x, y), "♪", font=font(BLACK, 70), fill=WHITE, anchor="mm") if False else star(d, x, y, 26 * K,
                                                                                                 (255, 214, 64))
    text_block(im, "RADIO HILL 99.1", "HITS ALL DAY, ALL NIGHT", W * 0.03, W * 0.6, (255, 214, 64))
    return im


def ad_kicks():
    im = Image.new("RGB", (W, H), (250, 200, 50))
    burst(im, W * 0.24, H * 0.6, (255, 214, 70), (244, 180, 40), 26)
    halftone(im, (0, 0, W, H), (230, 160, 30), 18 * K, 6 * K, (0.5, 0.5))
    d = ImageDraw.Draw(im)
    for k in range(5):
        y = H * (0.42 + k * 0.08)
        d.line([(W * 0.02, y), (W * 0.12, y)], fill=INK, width=8 * K)
    cx, cy = W * 0.26, H * 0.6
    d.polygon([(cx - 170 * K, cy + 40 * K), (cx - 160 * K, cy - 60 * K), (cx - 60 * K, cy - 90 * K),
               (cx + 20 * K, cy - 30 * K), (cx + 170 * K, cy - 10 * K), (cx + 190 * K, cy + 40 * K)],
              fill=(214, 36, 52), outline=INK, width=7 * K)
    d.rounded_rectangle([cx - 180 * K, cy + 30 * K, cx + 200 * K, cy + 70 * K], radius=18 * K, fill=WHITE,
                        outline=INK, width=6 * K)
    bolt(d, cx + 40 * K, cy - 8 * K, 34 * K, WHITE)
    for x in (-110, -80, -50):
        d.line([(cx + x * K, cy - 70 * K), (cx + (x + 30) * K, cy - 40 * K)], fill=WHITE, width=6 * K)
    text_block(im, "TURBO KICKS", "RUN LIKE A HERO", W * 0.45, W * 0.98, WHITE, top=0.36)
    return im


def ad_pizza():
    im = Image.new("RGB", (W, H), (20, 18, 50))
    gradient(im, (14, 12, 40), (50, 30, 100))
    d = ImageDraw.Draw(im)
    for k in range(60):
        x, y = (k * 7919) % W, (k * 104729) % H
        r = (1 + k % 3) * K
        d.ellipse([x - r, y - r, x + r, y + r], fill=WHITE)
    d.ellipse([W * 0.62, H * 0.1, W * 0.62 + 90 * K, H * 0.1 + 90 * K], fill=(130, 200, 140), outline=INK, width=5 * K)
    d.arc([W * 0.62 - 30 * K, H * 0.1 + 30 * K, W * 0.62 + 120 * K, H * 0.1 + 64 * K], 0, 360, fill=(250, 206, 60),
          width=6 * K)
    cx, cy = W * 0.84, H * 0.5
    d.polygon([(cx - 130 * K, cy - 130 * K), (cx + 130 * K, cy - 130 * K), (cx, cy + 170 * K)], fill=(255, 210, 90),
              outline=INK, width=7 * K)
    d.rounded_rectangle([cx - 150 * K, cy - 160 * K, cx + 150 * K, cy - 116 * K], radius=20 * K, fill=(200, 130, 60),
                        outline=INK, width=6 * K)
    for (x, y) in ((-60, -80), (40, -70), (-10, -10), (20, 60), (-40, 20)):
        d.ellipse([cx + (x - 20) * K, cy + (y - 20) * K, cx + (x + 20) * K, cy + (y + 20) * K], fill=(214, 50, 52),
                  outline=INK, width=4 * K)
    text_block(im, "COSMO PIZZA", "OUT OF THIS WORLD. DELIVERED.", W * 0.03, W * 0.6, (255, 214, 64))
    return im


ADS = [ad_cola, ad_news, ad_bank, ad_donuts, ad_ferry, ad_radio, ad_kicks, ad_pizza]
done = []
for i, fn in enumerate(ADS, 1):
    im = fn()
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, W - 1, H - 1], outline=INK, width=10 * K)
    im = im.resize((W // K, H // K), Image.LANCZOS)
    im.save(os.path.join(OUT, "Ad%d.png" % i))
    done.append(im)
sheet = Image.new("RGB", (1024 * 2 + 30, (414 + 10) * 4 + 20), (40, 40, 48))
for i, im in enumerate(done):
    sheet.paste(im, (10 + (i % 2) * 1034, 10 + (i // 2) * 424))
sheet.save(os.path.join(PREV, "city_ads.png"))
print("ads:", len(done))
