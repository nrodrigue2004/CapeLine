# The CAPELINE logo (Everything Left 85): a drawn comic title for the loading card, the main menu and the store.
# Gold-to-orange italic block letters with a navy 3D extrusion, a thick ink outline, a top shine and halftone dots
# in the shade, over a red cape that sweeps under the word from the C. Original lettering (Inter Display Black
# Italic, SIL Open Font License) and shapes; no other title is copied. DRAFT until nate OKs it.
# Run: python3 art/ui/logo.py  -> art/export/ui/logo.png (1024 x 384, transparent) and art/preview/logo.png
import math, os
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FONT = "/usr/share/fonts/opentype/inter/InterDisplay-BlackItalic.otf"
S = 2  # drawn at twice the size, then scaled down for smooth edges
W, H = 1024 * S, 384 * S
INK = (18, 16, 34, 255)
NAVY = (34, 44, 96, 255)
RED, RED_DARK = (222, 44, 52, 255), (140, 20, 36, 255)

def text_mask(txt, size, at):
    m = Image.new("L", (W, H), 0)
    f = ImageFont.truetype(FONT, size)
    ImageDraw.Draw(m).text(at, txt, font=f, fill=255)
    return m

def grow(m, r):
    return m.filter(ImageFilter.MaxFilter(r * 2 + 1)) if r > 0 else m

def fill(mask, color):
    layer = Image.new("RGBA", (W, H), color)
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    out.paste(layer, (0, 0), mask)
    return out

# the word, centred
size = 300 * S
while True:  # the largest size whose word (with its outline and block) fits the width
    f = ImageFont.truetype(FONT, size)
    box = ImageDraw.Draw(Image.new("L", (1, 1))).textbbox((0, 0), "CAPELINE", font=f)
    tw, th = box[2] - box[0], box[3] - box[1]
    if tw <= W - 130 * S and th <= H - 150 * S:
        break
    size -= 4 * S
at = ((W - tw) // 2 - box[0], (H - th) // 2 - box[1] - 30 * S)
word = text_mask("CAPELINE", size, at)

# the cape: a curved banner from behind the C sweeping right under the word, tapering, with a fold
cape = Image.new("L", (W, H), 0)
cd = ImageDraw.Draw(cape)
x0, x1 = at[0] + 20 * S, at[0] + tw * 0.8
yb = at[1] + box[1] + th + 6 * S
pts_top, pts_bot = [], []
for i in range(41):
    t = i / 40
    x = x0 + (x1 - x0) * t
    wave = math.sin(t * math.pi * 1.6) * 18 * S
    thick = (70 - 50 * t) * S
    pts_top.append((x, yb - 20 * S + wave - 10 * S * (1 - t)))
    pts_bot.append((x + 10 * S * t, yb - 20 * S + wave + thick))
cd.polygon(pts_top + pts_bot[::-1], fill=255)
# the cape rises behind the C like a collar
cd.polygon([(x0 - 30 * S, yb - 10 * S), (x0 + 40 * S, at[1] + box[1] - 10 * S), (x0 + 90 * S, yb - 30 * S),
            (x0 + 60 * S, yb + 50 * S)], fill=255)
cape = cape.filter(ImageFilter.GaussianBlur(1.2 * S)).point(lambda v: 255 if v > 127 else 0)
cape_fold = Image.new("L", (W, H), 0)
fd = ImageDraw.Draw(cape_fold)
fd.polygon([(p[0], p[1] + 22 * S) for p in pts_top[4:30]] + [(p[0], p[1] - 8 * S) for p in pts_bot[4:30]][::-1],
           fill=255)
cape_fold = ImageChops.multiply(cape_fold, cape)

img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
# cape: ink outline, red, the darker fold
img.alpha_composite(fill(grow(cape, 9 * S), INK))
img.alpha_composite(fill(cape, RED))
img.alpha_composite(fill(cape_fold, RED_DARK))

# the word's 3D block: navy steps down and to the right, then the ink outline around word and block
depth = 26 * S
block = Image.new("L", (W, H), 0)
for k in range(depth):
    block = ImageChops.lighter(block, ImageChops.offset(word, k // 2, k))
img.alpha_composite(fill(grow(ImageChops.lighter(block, word), 13 * S), INK))
img.alpha_composite(fill(block, NAVY))
# the face: a gold to orange gradient, a shine over the top, halftone dots in the low shade
grad = Image.new("RGBA", (W, H))
gd = ImageDraw.Draw(grad)
top, bot = at[1] + box[1], at[1] + box[1] + th
for y in range(H):
    t = min(1, max(0, (y - top) / max(1, bot - top)))
    c = (255, int(236 - 96 * t), int(110 - 80 * t), 255)
    gd.line([(0, y), (W, y)], fill=c)
face = Image.new("RGBA", (W, H), (0, 0, 0, 0))
face.paste(grad, (0, 0), word)
img.alpha_composite(face)
dots = Image.new("L", (W, H), 0)
dd = ImageDraw.Draw(dots)
step = 14 * S
for y in range(int(top + th * 0.55), int(bot) + step, step):
    r = 1.2 * S + 3.2 * S * (y - (top + th * 0.55)) / (th * 0.45)
    for x in range(0, W, step):
        xo = x + (step // 2 if (y // step) % 2 else 0)
        dd.ellipse([xo - r, y - r, xo + r, y + r], fill=255)
dots = ImageChops.multiply(dots, word)
img.alpha_composite(fill(dots, (230, 96, 24, 150)))
shine = Image.new("L", (W, H), 0)
ImageDraw.Draw(shine).rectangle([0, top, W, top + th * 0.28], fill=255)
shine = ImageChops.multiply(shine, word.filter(ImageFilter.MinFilter(9 * S + 1)))
img.alpha_composite(fill(shine, (255, 252, 220, 150)))
# a thin inner ink line keeps the letters crisp at small sizes
edge = ImageChops.subtract(word, word.filter(ImageFilter.MinFilter(3 * S + 1)))
img.alpha_composite(fill(edge, (120, 60, 10, 200)))

out = img.resize((W // S, H // S), Image.LANCZOS)
os.makedirs(os.path.join(ROOT, "art/export/ui"), exist_ok=True)
out.save(os.path.join(ROOT, "art/export/ui/logo.png"))
# the preview: the logo on the loading card's navy and on a light sky, and small (a phone menu)
pv = Image.new("RGBA", (1024, 384 * 2 + 200), (24, 30, 70, 255))
ImageDraw.Draw(pv).rectangle([0, 384, 1024, 768], fill=(150, 196, 236, 255))
pv.alpha_composite(out, (0, 0))
pv.alpha_composite(out, (0, 384))
small = out.resize((256, 96), Image.LANCZOS)
pv.alpha_composite(small, (40, 768 + 50))
pv.alpha_composite(out.resize((400, 150), Image.LANCZOS), (400, 768 + 25))
pv.save(os.path.join(ROOT, "art/preview/logo.png"))
print("ok", out.size)
