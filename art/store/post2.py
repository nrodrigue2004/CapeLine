# art/store/post2.py: finishes the store art refresh (art/store/store2.py's renders in art/export/store2/raw/) in the
# first set's style (art/store/post.py: the same grade, comic speed lines, caption look and boss bar), then the
# upload sizes into art/export/store2/: icons 512 x 512 (no text), thumbnails 1920 x 1080 (at most 3 words). Also
# the previews: art/export/store2/preview_sheet.png (every image, each icon at 400, 150 and 50 px, the sizes a
# phone shows it at) and art/export/store2/preview_small.png (each thumbnail at 480 and 240 px wide, as the ad and
# the game page show them small), copied to art/preview/store2_sheet.png.
# Run: python3 art/store/post2.py [--draft]   (PIL and numpy)
import os
import shutil
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import post as P  # noqa: E402

P.OUT = os.path.join(P.ART, "export", "store2")
P.RAW = os.path.join(P.OUT, "raw")
SUFFIX = P.SUFFIX

WHITE, GOLD, RED = P.WHITE, P.GOLD, P.RED
CYAN = ((236, 255, 255), (60, 220, 236))  # the Lumen Maw's and the Leviathan Engine's phase-1 glow

# icons: (name, speed lines centre x, y, inner radius as fractions, count)
ICONS = [
    ("maw", (0.62, 0.56, 0.3, 60)),
    ("fake", (0.2, 0.36, 0.2, 60)),
    ("titan", (0.42, 0.62, 0.22, 60)),
]
# thumbnails: (name, caption words, size, centre; speed lines; boss bar)
THUMBS = [
    ("maw", [("GIANT", WHITE), ("WORLD", WHITE), ("BOSSES", CYAN)], (0.7, 0.62, 0.12, 60), True),
    ("deep", [("FROM", WHITE), ("THE", WHITE), ("DEEP", CYAN)], (0.68, 0.42, 0.12, 60), True),
    ("fakes", [("SPOT", WHITE), ("THE", WHITE), ("FAKE", RED)], (0.44, 0.38, 0.16, 50), False),
    ("giant", [("TOPPLE", WHITE), ("THE", WHITE), ("GIANT", GOLD)], (0.38, 0.42, 0.1, 50), False),
]


def sheet(icons, thumbs):
    """Every image on one page: each icon at 400, 150 and 50 px, then the thumbnails two a row."""
    W = 1920
    pad = 30
    out = Image.new("RGB", (W, 2400), (30, 32, 44))
    d = ImageDraw.Draw(out)
    fs = P.font(26)
    d.text((pad, 20), "Capeline store art refresh (2026-11-18): icons (512 px files, shown at 400, 150 and 50 px) and "
           "thumbnails (1920 x 1080)", font=fs, fill=(230, 230, 240))
    x, y = pad, 70
    big = 400
    for p in icons:
        im = Image.open(p)
        out.paste(im.resize((big, big), Image.LANCZOS), (x, y))
        out.paste(im.resize((150, 150), Image.LANCZOS), (x + big + 14, y))
        out.paste(im.resize((50, 50), Image.LANCZOS), (x + big + 14, y + 164))
        d.text((x, y + big + 6), os.path.basename(p), font=fs, fill=(200, 204, 220))
        x += big + 14 + 150 + 52
    y += big + 60
    tw = (W - pad * 3) // 2
    th = tw * 9 // 16
    for i, p in enumerate(thumbs):
        cx = pad + (i % 2) * (tw + pad)
        out.paste(Image.open(p).resize((tw, th), Image.LANCZOS), (cx, y))
        d.text((cx, y + th + 6), os.path.basename(p), font=fs, fill=(200, 204, 220))
        if i % 2 == 1:
            y += th + 50
    if len(thumbs) % 2:
        y += th + 50
    out = out.crop((0, 0, W, y))
    path = os.path.join(P.OUT, "preview_sheet%s.png" % SUFFIX)
    out.save(path, optimize=True)
    shutil.copy(path, os.path.join(P.ART, "preview", "store2_sheet%s.png" % SUFFIX))
    print("wrote", path)


def small(thumbs):
    """The thumbnails as players meet them: about 480 px wide on a PC page and 240 px in a phone's ad slot."""
    pad = 24
    rows = []
    for p in thumbs:
        im = Image.open(p)
        rows.append((im.resize((480, 270), Image.LANCZOS), im.resize((240, 135), Image.LANCZOS)))
    out = Image.new("RGB", (pad * 3 + 480 + 240, pad + len(rows) * (270 + pad)), (30, 32, 44))
    for k, (a, b) in enumerate(rows):
        yy = pad + k * (270 + pad)
        out.paste(a, (pad, yy))
        out.paste(b, (pad * 2 + 480, yy))
    path = os.path.join(P.OUT, "preview_small%s.png" % SUFFIX)
    out.save(path, optimize=True)
    print("wrote", path)


if __name__ == "__main__":
    icons = [P.icon(n, lines=ln) for n, ln in ICONS]
    thumbs = [P.thumb(n, (words, 150, (0.5, 0.86)), lines=ln, bar=bar) for n, words, ln, bar in THUMBS]
    icons = [p for p in icons if p]
    thumbs = [p for p in thumbs if p]
    sheet(icons, thumbs)
    small(thumbs)
