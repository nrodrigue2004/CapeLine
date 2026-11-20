# swing_line.py: the Swing's line texture (list-combat 2026-11-20, Everything Left 393: "the swing line is a plain
# white line, no web texture"). A tileable strip for the line's Beam (Fx.SwingFx; TextureMode Wrap): an original
# energy cord, two strands twisting round a bright core with little glints, drawn white on clear so the worn travel
# style's colour tints it (MoveController.lineColor). 512 x 64, tiles along its length. Preview at 4 tiles.
# Output: art/export/fx/SwingLine.png, art/preview/swing_line.png. Run: python3 art/fx/swing_line.py
import math
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "export", "fx")
os.makedirs(OUT, exist_ok=True)
W, H = 512, 64
S = 4  # supersample


def draw():
    img = Image.new("RGBA", (W * S, H * S), (255, 255, 255, 0))
    d = ImageDraw.Draw(img)
    cy = H * S / 2
    # the soft glow under everything
    glow = Image.new("RGBA", img.size, (255, 255, 255, 0))
    gd = ImageDraw.Draw(glow)
    gd.rectangle([0, cy - 14 * S, W * S, cy + 14 * S], fill=(255, 255, 255, 70))
    glow = glow.filter(ImageFilter.GaussianBlur(9 * S))
    img = Image.alpha_composite(img, glow)
    d = ImageDraw.Draw(img)
    # the core: a bright line with a slight swell
    d.rectangle([0, cy - 3 * S, W * S, cy + 3 * S], fill=(255, 255, 255, 235))
    # two strands twisting: 4 full turns along the tile (so the ends meet), back half dimmer
    turns = 4
    amp = 11 * S
    for phase, alpha in ((0.0, 255), (math.pi, 255)):
        pts_front, pts_back = [], []
        for x in range(0, W * S + 1, 2):
            t = x / (W * S) * turns * 2 * math.pi + phase
            y = cy + math.sin(t) * amp
            (pts_front if math.cos(t) > 0 else pts_back).append((x, y, math.cos(t)))
        for pts, a, r in ((pts_back, 110, 2.2), (pts_front, alpha, 3.4)):
            for x, y, c in pts:
                rr = r * S * (0.75 + 0.25 * abs(c))
                d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=(255, 255, 255, a))
    # glints where the strands cross the core
    for k in range(turns * 2):
        x = (k + 0.5) / (turns * 2) * W * S
        for dx, dy, r in ((0, 0, 4.5), (-7, 0, 2), (7, 0, 2), (0, -6, 1.6), (0, 6, 1.6)):
            rr = r * S
            d.ellipse([x + dx * S - rr, cy + dy * S - rr, x + dx * S + rr, cy + dy * S + rr], fill=(255, 255, 255, 255))
    img = img.resize((W, H), Image.LANCZOS)
    return img


img = draw()
img.save(os.path.join(OUT, "SwingLine.png"))
# preview: 2 tiles a row, on a sky (white, pink) and on a dark wall (white, green): the line tinted as in game
prev = Image.new("RGB", (W * 2, H * 8), (120, 170, 230))
ImageDraw.Draw(prev).rectangle([0, H * 4, W * 2, H * 8], fill=(40, 40, 52))
for row, tint in enumerate(((255, 255, 255), (255, 120, 200), (255, 255, 255), (120, 255, 160))):
    r, g, b, a = img.split()
    tinted = Image.merge("RGBA", (r.point(lambda v, t=tint[0]: v * t // 255), g.point(lambda v, t=tint[1]: v * t // 255),
                                  b.point(lambda v, t=tint[2]: v * t // 255), a))
    for k in range(2):
        prev.paste(tinted, (k * W, row * H * 2 + H // 2), tinted)
prev.save(os.path.join(ROOT, "preview", "swing_line.png"))
print("swing_line: art/export/fx/SwingLine.png")
