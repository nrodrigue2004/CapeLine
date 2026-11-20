# art/ui/aim_ui.py: the aim preview's ground pictures (list-combat 2026-11-20, Everything Left 389: "The aim
# preview is glowing parts"). White on clear so Fx.AimPreview tints them the power's colour; drawn as Decals and
# Textures on flat see-through parts:
#   Ring     512 x 512: the area marker: a bright double rim with a soft inner glow, eight ticks round the edge and
#            four inward arrowheads, a faint fill so the ground still shows
#   Chevron  256 x 256: one tile of the line and cone strips: a bold chevron pointing to the image's top with a glow,
#            clear between tiles, so AimPreview tiles it along the aim and scrolls it outward
# Output: art/export/ui/aim/<Name>.png and art/preview/aim_ui.png. Run: python3 art/ui/aim_ui.py (PIL only)
import math
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "export", "ui", "aim")
os.makedirs(OUT, exist_ok=True)
SS = 3


def glow(im, radius, gain=1.0):
    g = im.filter(ImageFilter.GaussianBlur(radius))
    if gain != 1.0:
        a = g.getchannel("A").point(lambda v: min(255, int(v * gain)))
        g.putalpha(a)
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    out.alpha_composite(g)
    out.alpha_composite(im)
    return out


def ring():
    W = 512 * SS
    c = W / 2
    im = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    # the faint fill, stronger toward the rim
    fl = Image.new("RGBA", (W, W), (255, 255, 255, 0))
    # concentric fill: draw from outside in so inner circles overwrite
    fd2 = ImageDraw.Draw(fl)
    for k in range(40, 0, -1):
        r = c * 0.9 * k / 40
        fd2.ellipse([c - r, c - r, c + r, c + r], fill=(255, 255, 255, int(6 + 46 * (k / 40) ** 3)))
    im.alpha_composite(fl)
    d = ImageDraw.Draw(im)
    w = 14 * SS
    r = c * 0.9
    d.ellipse([c - r, c - r, c + r, c + r], outline=(255, 255, 255, 255), width=w)
    r2 = r - 26 * SS
    d.ellipse([c - r2, c - r2, c + r2, c + r2], outline=(255, 255, 255, 170), width=4 * SS)
    # ticks
    for i in range(8):
        a = i * math.pi / 4 + math.pi / 8
        x0, y0 = c + math.cos(a) * (r - 4 * SS), c + math.sin(a) * (r - 4 * SS)
        x1, y1 = c + math.cos(a) * (r + 18 * SS), c + math.sin(a) * (r + 18 * SS)
        if r + 18 * SS < c:
            d.line([(x0, y0), (x1, y1)], fill=(255, 255, 255, 255), width=7 * SS)
    # four arrowheads pointing in
    for i in range(4):
        a = i * math.pi / 2
        ca, sa = math.cos(a), math.sin(a)
        tip = r2 - 58 * SS
        base = r2 - 10 * SS
        half = 28 * SS
        pts = [(c + ca * tip, c + sa * tip), (c + ca * base - sa * half, c + sa * base + ca * half),
               (c + ca * base + sa * half, c + sa * base - ca * half)]
        d.polygon(pts, fill=(255, 255, 255, 235))
    im = glow(im, 10 * SS, 1.4)
    return im.resize((512, 512), Image.LANCZOS)


def chevron():
    W = 256 * SS
    im = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    t = 46 * SS  # thickness
    top, bot = 70 * SS, 170 * SS
    m = 40 * SS
    pts = [(W / 2, top), (W - m, bot), (W - m - t * 1.1, bot + t * 0.75), (W / 2, top + t * 1.35),
           (m + t * 1.1, bot + t * 0.75), (m, bot)]
    d.polygon(pts, fill=(255, 255, 255, 255))
    # a soft centre line between tiles: the strip still reads as a path
    d.rectangle([W / 2 - 5 * SS, 0, W / 2 + 5 * SS, W], fill=(255, 255, 255, 60))
    im = glow(im, 9 * SS, 1.5)
    return im.resize((256, 256), Image.LANCZOS)


R = ring()
R.save(os.path.join(OUT, "Ring.png"))
Cv = chevron()
Cv.save(os.path.join(OUT, "Chevron.png"))
# preview: tinted on a street grey, the ring and a strip of 4 chevrons
prev = Image.new("RGBA", (900, 560), (96, 98, 104, 255))
tint = Image.new("RGBA", R.size, (90, 200, 255, 255))
tint.putalpha(R.getchannel("A"))
prev.alpha_composite(tint, (24, 24))
for k in range(4):
    t2 = Image.new("RGBA", Cv.size, (255, 140, 60, 255))
    t2.putalpha(Cv.getchannel("A"))
    s = t2.resize((128, 128))
    prev.alpha_composite(s, (620, 24 + k * 128))
prev.save(os.path.join(ROOT, "preview", "aim_ui.png"))
print("aim ui:", R.size, Cv.size)
