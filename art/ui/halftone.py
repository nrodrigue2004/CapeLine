"""The comic UI's halftone dot tile (the comic UI pass, 2026-11-18): white dots on transparent, staggered
like print halftone, tiling seamlessly. Kit tints it (ImageColor3) and fades it (ImageTransparency) over
paper panels; Config.Ui.ink.halftone.image holds the uploaded id.

    python3 art/ui/halftone.py   ->  art/export/ui/halftone.png (64 x 64, two dot rows of two)
"""

import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SIZE = 64  # pixels; Kit shows it at Config.Ui.ink.halftone.tile GUI pixels per tile
SS = 8  # drawn big, then shrunk for smooth dot edges


def main():
    big = SIZE * SS
    img = Image.new("RGBA", (big, big), (255, 255, 255, 0))
    d = ImageDraw.Draw(img)
    step = big / 2  # two dots across, every other row shifted half a step
    r = step * 0.2
    for row in range(-1, 5):
        y = row * step / 2
        shift = step / 2 if row % 2 else 0
        for col in range(-1, 4):
            x = col * step + shift
            d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, 255))
    alpha = img.getchannel("A").resize((SIZE, SIZE), Image.LANCZOS)
    img = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 255))
    img.putalpha(alpha)  # pure white everywhere, so a tint is exact
    out = os.path.join(ROOT, "art", "export", "ui")
    os.makedirs(out, exist_ok=True)
    path = os.path.join(out, "halftone.png")
    img.save(path)
    print(path)


if __name__ == "__main__":
    main()
