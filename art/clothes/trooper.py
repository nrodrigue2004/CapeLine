# art/clothes/trooper.py: the Spark Trooper as a plain Roblox character in classic clothing (nate, 2026-11-17:
# "just looks like a roblox character with clothes"). Draws the real upload-ready textures on Roblox's classic
# clothing template (585 x 559; Shirt and Pants), plus the face decal (human, and "turned" with glowing eyes).
# Output: art/export/clothes/Trooper_Clothes.png (the shirt over the pants on one template: the image the game's
# robots wear, Shared.ClothesMap), Trooper_Shirt.png and Trooper_Pants.png (the same as real Roblox clothing).
# The faces are shared by every robot: art/clothes/faces.py.
# Run: python3 art/clothes/trooper.py   (PIL only)
import math
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "export", "clothes")
os.makedirs(OUT, exist_ok=True)
W, H = 585, 559

# Roblox's classic clothing template, (x, y, w, h). Torso: the faces of the torso block. Arms (Shirt) and legs
# (Pants) share the same slots: the character's right limb on the left of the image.
TORSO = {"F": (231, 74, 128, 128), "B": (427, 74, 128, 128), "R": (165, 74, 64, 128), "L": (361, 74, 64, 128),
         "U": (231, 8, 128, 64), "D": (231, 204, 128, 64)}
# (the strips wrap around the limb: the right limb reads L B R F, so its outer face R sits next to the front)
RIGHT = {"L": (19, 355, 64, 128), "B": (85, 355, 64, 128), "R": (151, 355, 64, 128), "F": (217, 355, 64, 128),
         "U": (217, 289, 64, 64), "D": (217, 485, 64, 64)}
LEFT = {"F": (308, 355, 64, 128), "L": (374, 355, 64, 128), "B": (440, 355, 64, 128), "R": (506, 355, 64, 128),
        "U": (308, 289, 64, 64), "D": (308, 485, 64, 64)}
SIDES4 = ("F", "B", "R", "L")
# R15 split of a 128 px tall strip: the torso is UpperTorso 1.6 over LowerTorso 0.4; an arm or leg is
# upper 0.85, lower 0.85, hand or foot 0.3 (of 2.0)
UT_PX = 102
UPPER_PX, LOWER_PX = 54, 54  # then 20 for the hand or foot

SUIT = (40, 70, 140)
TRIM = (255, 170, 60)
WHITE = (236, 238, 242)
DARK = (18, 20, 28)


def shade(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c)


def panel(d, r, c, top=1.08, bottom=0.88, edge=True):
    """A face filled with a soft top-lit gradient and darker edges, so the flat template reads as cloth."""
    x, y, w, h = r
    for i in range(h):
        k = top + (bottom - top) * i / max(1, h - 1)
        d.line([(x, y + i), (x + w - 1, y + i)], fill=shade(c, k))
    if edge:
        d.rectangle([x, y, x + w - 1, y + h - 1], outline=shade(c, 0.72))


def seam(d, pts, c, k=0.7):
    d.line(pts, fill=shade(c, k), width=1)


def stitches(d, x0, y, x1, c):
    for x in range(x0, x1, 4):
        d.point((x, y), fill=shade(c, 1.25))


def diamond(d, cx, cy, hw, hh, fill, outline=None):
    d.polygon([(cx, cy - hh), (cx + hw, cy), (cx, cy + hh), (cx - hw, cy)], fill=fill, outline=outline)


def emblem(d, cx, cy):
    # the Spark Trooper's mark: a white-rimmed orange diamond with a dark spark bolt (original)
    diamond(d, cx, cy, 30, 27, WHITE)
    diamond(d, cx, cy, 24, 21, TRIM)
    diamond(d, cx, cy, 24, 21, None, shade(TRIM, 0.75))
    bolt = [(cx + 6, cy - 17), (cx - 6, cy + 1), (cx + 1, cy + 1), (cx - 6, cy + 17), (cx + 9, cy - 3),
            (cx + 2, cy - 3), (cx + 9, cy - 17)]
    d.polygon(bolt, fill=DARK)


def shirt():
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # torso: the upper torso part of each face is the suit; the lower torso's strip stays clear for the pants
    for s in SIDES4:
        x, y, w, h = TORSO[s]
        panel(d, (x, y, w, UT_PX), SUIT)
    panel(d, TORSO["U"], SUIT, 1.12, 1.0)
    fx, fy, fw, fh = TORSO["F"]
    # collar, pec line, emblem, ab seams, side stripes
    d.rectangle([fx + 40, fy, fx + 87, fy + 5], fill=TRIM)
    d.polygon([(fx + 48, fy + 5), (fx + 64, fy + 14), (fx + 80, fy + 5)], fill=shade(SUIT, 0.8))
    seam(d, [(fx + 64, fy + 44), (fx + 64, fy + 58)], SUIT)
    emblem(d, fx + 64, fy + 34)
    for k in range(3):
        yy = fy + 66 + k * 10
        seam(d, [(fx + 46, yy), (fx + 82, yy)], SUIT, 0.8)
    bx_, by_, bw_, _ = TORSO["B"]
    d.rectangle([bx_ + 40, by_, bx_ + 87, by_ + 5], fill=TRIM)
    for s, (x, y, w, h) in (("R", TORSO["R"]), ("L", TORSO["L"])):
        d.rectangle([x + w // 2 - 4, y, x + w // 2 + 3, y + UT_PX - 1], fill=TRIM)
    # shoulder blades
    seam(d, [(bx_ + 20, by_ + 30), (bx_ + 52, by_ + 44)], SUIT)
    seam(d, [(bx_ + 107, by_ + 30), (bx_ + 75, by_ + 44)], SUIT)
    # arms: suit sleeves, then orange gloves with a flared cuff
    for arm, outer in ((RIGHT, "R"), (LEFT, "L")):
        for s in SIDES4:
            x, y, w, h = arm[s]
            panel(d, (x, y, w, UPPER_PX + 8), SUIT)
            panel(d, (x, y + UPPER_PX + 8, w, h - UPPER_PX - 8), TRIM, 1.05, 0.85)
            d.rectangle([x, y + UPPER_PX + 8, x + w - 1, y + UPPER_PX + 15], fill=shade(TRIM, 1.12))
            d.line([(x, y + UPPER_PX + 16), (x + w - 1, y + UPPER_PX + 16)], fill=shade(TRIM, 0.7))
            # the knuckle band on the hand
            d.line([(x + 4, y + h - 14), (x + w - 5, y + h - 14)], fill=shade(TRIM, 0.75))
        x, y, w, h = arm[outer]
        d.rectangle([x + w // 2 - 3, y, x + w // 2 + 2, y + UPPER_PX + 7], fill=TRIM)  # the outer stripe
        panel(d, arm["U"], SUIT, 1.12, 1.0)
        panel(d, arm["D"], TRIM, 0.9, 0.85)
    return im


def pants():
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # the lower torso: suit with the belt and buckle across it
    for s in SIDES4:
        x, y, w, h = TORSO[s]
        panel(d, (x, y + UT_PX - 4, w, h - UT_PX + 4), SUIT, 1.0, 0.85, edge=False)
        d.rectangle([x, y + UT_PX + 4, x + w - 1, y + UT_PX + 15], fill=TRIM)
        d.line([(x, y + UT_PX + 4), (x + w - 1, y + UT_PX + 4)], fill=shade(TRIM, 0.7))
        d.line([(x, y + UT_PX + 15), (x + w - 1, y + UT_PX + 15)], fill=shade(TRIM, 0.7))
    fx, fy, fw, _ = TORSO["F"]
    d.ellipse([fx + 55, fy + UT_PX + 1, fx + 72, fy + UT_PX + 18], fill=WHITE, outline=shade(WHITE, 0.6))
    for px in (fx + 20, fx + 98):
        d.rectangle([px, fy + UT_PX + 5, px + 10, fy + UT_PX + 14], fill=(66, 70, 80))
    panel(d, TORSO["D"], SUIT, 0.8, 0.7)
    # legs: suit trousers with the outer stripe, orange boots with a flared top and a dark sole
    for leg, outer in ((RIGHT, "R"), (LEFT, "L")):
        for s in SIDES4:
            x, y, w, h = leg[s]
            panel(d, (x, y, w, UPPER_PX + 10), SUIT)
            panel(d, (x, y + UPPER_PX + 10, w, h - UPPER_PX - 10), TRIM, 1.05, 0.85)
            d.rectangle([x, y + UPPER_PX + 10, x + w - 1, y + UPPER_PX + 18], fill=shade(TRIM, 1.12))
            d.line([(x, y + UPPER_PX + 19), (x + w - 1, y + UPPER_PX + 19)], fill=shade(TRIM, 0.7))
            d.rectangle([x, y + h - 5, x + w - 1, y + h - 1], fill=DARK)  # the sole
            if s == "F":
                d.rounded_rectangle([x + 18, y + UPPER_PX + 26, x + w - 19, y + UPPER_PX + 34], 2, fill=WHITE)
                d.line([(x + 10, y + h - 14), (x + w - 11, y + h - 14)], fill=shade(TRIM, 0.75))  # toe cap
        x, y, w, h = leg[outer]
        d.rectangle([x + w // 2 - 3, y, x + w // 2 + 2, y + UPPER_PX + 9], fill=TRIM)
        panel(d, leg["U"], SUIT, 0.9, 0.85)
        panel(d, leg["D"], DARK, 1, 1)
    return im


if __name__ == "__main__":
    top, bottom = shirt(), pants()
    both = bottom.copy()
    both.alpha_composite(top)  # Roblox draws the shirt over the pants
    for name, im in (("Trooper_Clothes", both), ("Trooper_Shirt", top), ("Trooper_Pants", bottom)):
        path = os.path.join(OUT, name + ".png")
        im.save(path)
        print("wrote", path)
