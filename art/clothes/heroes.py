# art/clothes/heroes.py: the heroes' own Roblox-style clothes (nate, 2026-11-17: heroes keep nothing from their
# avatar; "They wear our clothes, our gear, our accessories"). Classic Shirt and Pants templates (585 x 559 each),
# drawn in light greys so the game tints each one with the hero's colour (Clothing.Color3 multiplies): light
# areas take the colour, dark ones (shoes, belts, zips) stay dark. Clear areas show the skin (short sleeves,
# shorts). The shirt stops just above the waist so the pants' belt shows, the way Roblox layers them.
# Output: art/export/clothes/heroes/Shirt_<Name>.png, Pants_<Name>.png and art/preview/hero_clothes.png
# (each template tinted in a sample colour). Run: python3 art/clothes/heroes.py   (PIL only)
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from trooper import TORSO, RIGHT, LEFT, SIDES4, UT_PX, W, H, shade  # noqa: E402
from uniforms import T, HAND, LOWER  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "export", "clothes", "heroes")
os.makedirs(OUT, exist_ok=True)

BASE = (234, 234, 234)  # takes the tint
MID = (196, 196, 196)
LIGHT = (252, 252, 252)
SHOE = (44, 44, 48)
SOLE = (200, 200, 200)
METAL = (90, 90, 96)
HEM = UT_PX + 4  # a shirt's hem: just over the belt line


def front():
    return TORSO["F"]


def back():
    return TORSO["B"]


def shirt_body(t, sleeve_to, hem=HEM, base=BASE):
    t.torso(base, 0, hem, 1.04, 0.92)
    if sleeve_to > 0:
        t.limbs(base, 0, sleeve_to, 1.04, 0.92)


def collar_ring(t, k=0.78):
    fx, fy, _, _ = front()
    t.d.arc([fx + 40, fy - 22, fx + 88, fy + 14], 0, 180, fill=shade(BASE, k), width=4)


def cuffs(t, at, h=6, c=None):
    t.limb_band(c or shade(BASE, 0.86), at - h, at)


def hem_band(t, hem=HEM, h=6, c=None):
    for s in SIDES4:
        x, y, w, _ = TORSO[s]
        t.d.rectangle([x, y + hem - h, x + w - 1, y + hem - 1], fill=c or shade(BASE, 0.86))


# ---------------------------------------------------------------- shirts
def tee():
    t = T()
    shirt_body(t, 30)
    t.limb_line(BASE, 29, 0.8, 2)
    collar_ring(t)
    return t.im


def long_sleeve():
    t = T()
    shirt_body(t, HAND)
    cuffs(t, HAND)
    collar_ring(t)
    return t.im


def hoodie():
    t = T()
    shirt_body(t, HAND, HEM + 6)
    cuffs(t, HAND, 8)
    hem_band(t, HEM + 6, 8)
    fx, fy, _, _ = front()
    t.d.rounded_rectangle([fx + 26, fy + 64, fx + 102, fy + 98], 6, fill=shade(BASE, 0.93), outline=shade(BASE, 0.8), width=2)
    t.d.line([(fx + 52, fy + 4), (fx + 50, fy + 34)], fill=MID, width=3)  # drawstrings
    t.d.line([(fx + 76, fy + 4), (fx + 78, fy + 34)], fill=MID, width=3)
    t.d.arc([fx + 30, fy - 30, fx + 98, fy + 18], 0, 180, fill=shade(BASE, 0.78), width=5)
    bx, by, _, _ = back()
    t.d.rounded_rectangle([bx + 24, by, bx + 104, by + 40], 14, fill=shade(BASE, 0.9), outline=shade(BASE, 0.75), width=3)  # the hood
    return t.im


def zip_jacket():
    t = T()
    shirt_body(t, HAND)
    cuffs(t, HAND, 6, shade(BASE, 0.8))
    hem_band(t, HEM, 6, shade(BASE, 0.8))
    fx, fy, _, _ = front()
    t.d.rectangle([fx + 62, fy, fx + 65, fy + HEM], fill=METAL)  # the zip
    t.d.rectangle([fx + 58, fy + 2, fx + 69, fy + 10], fill=METAL)
    t.d.polygon([(fx + 34, fy), (fx + 62, fy), (fx + 62, fy + 14), (fx + 42, fy + 10)], fill=shade(BASE, 0.84))  # collar
    t.d.polygon([(fx + 94, fy), (fx + 66, fy), (fx + 66, fy + 14), (fx + 86, fy + 10)], fill=shade(BASE, 0.84))
    for px in (fx + 18, fx + 80):
        t.d.line([(px, fy + 70), (px + 30, fy + 82)], fill=shade(BASE, 0.7), width=3)  # pockets
    return t.im


def track_top():
    t = T()
    shirt_body(t, HAND, HEM, MID)
    cuffs(t, HAND, 6, shade(MID, 0.8))
    hem_band(t, HEM, 6, shade(MID, 0.8))
    for slots, side in ((RIGHT, "R"), (LEFT, "L")):
        x, y, w, _ = slots[side]
        for k in (-9, 3):
            t.d.rectangle([x + w // 2 + k, y, x + w // 2 + k + 5, y + HAND - 6], fill=LIGHT)
    for s in ("R", "L"):
        x, y, w, _ = TORSO[s]
        for k in (-9, 3):
            t.d.rectangle([x + w // 2 + k, y, x + w // 2 + k + 5, y + HEM - 6], fill=LIGHT)
    fx, fy, _, _ = front()
    t.d.rectangle([fx + 62, fy, fx + 65, fy + HEM], fill=METAL)
    t.d.rectangle([fx + 40, fy, fx + 87, fy + 8], fill=LIGHT)
    return t.im


def button_shirt():
    t = T()
    shirt_body(t, LOWER - 6)
    t.limb_band(shade(BASE, 0.9), LOWER - 14, LOWER - 6)  # rolled sleeves
    t.limb_line(BASE, LOWER - 10, 0.75, 2)
    fx, fy, _, _ = front()
    t.d.polygon([(fx + 38, fy), (fx + 62, fy + 16), (fx + 54, fy + 22), (fx + 34, fy + 6)], fill=LIGHT, outline=shade(BASE, 0.75))
    t.d.polygon([(fx + 90, fy), (fx + 66, fy + 16), (fx + 74, fy + 22), (fx + 94, fy + 6)], fill=LIGHT, outline=shade(BASE, 0.75))
    t.d.line([(fx + 64, fy + 14), (fx + 64, fy + HEM)], fill=shade(BASE, 0.75), width=2)
    for k in range(5):
        t.d.ellipse([fx + 66, fy + 24 + k * 16, fx + 70, fy + 28 + k * 16], fill=MID)
    t.d.rectangle([fx + 80, fy + 30, fx + 102, fy + 50], outline=shade(BASE, 0.75), width=2)
    return t.im


def polo():
    t = T()
    shirt_body(t, 30)
    cuffs(t, 30, 5)
    fx, fy, _, _ = front()
    t.d.polygon([(fx + 36, fy), (fx + 60, fy + 10), (fx + 52, fy + 18), (fx + 32, fy + 4)], fill=LIGHT, outline=shade(BASE, 0.75))
    t.d.polygon([(fx + 92, fy), (fx + 68, fy + 10), (fx + 76, fy + 18), (fx + 96, fy + 4)], fill=LIGHT, outline=shade(BASE, 0.75))
    t.d.rectangle([fx + 61, fy + 8, fx + 67, fy + 40], outline=shade(BASE, 0.75), width=2)
    for k in range(3):
        t.d.ellipse([fx + 62, fy + 14 + k * 9, fx + 66, fy + 18 + k * 9], fill=MID)
    return t.im


def tank():
    t = T()
    t.torso(BASE, 0, HEM, 1.04, 0.92)
    fx, fy, _, _ = front()
    bx, by, _, _ = back()
    clear = (0, 0, 0, 0)
    for x0, y0 in ((fx, fy), (bx, by)):  # wide arm holes and a scoop neck
        t.d.rectangle([x0, y0, x0 + 22, y0 + 34], fill=clear)
        t.d.rectangle([x0 + 106, y0, x0 + 127, y0 + 34], fill=clear)
        t.d.ellipse([x0 + 38, y0 - 26, x0 + 90, y0 + 20], fill=clear)
    for s in ("R", "L"):
        x, y, w, _ = TORSO[s]
        t.d.rectangle([x, y, x + w - 1, y + 30], fill=clear)
    return t.im


def sweater():
    t = T()
    shirt_body(t, HAND, HEM + 4)
    cuffs(t, HAND, 10, shade(BASE, 0.88))
    hem_band(t, HEM + 4, 10, shade(BASE, 0.88))
    for s in SIDES4:  # a knit band across the chest
        x, y, w, _ = TORSO[s]
        t.d.rectangle([x, y + 28, x + w - 1, y + 46], fill=shade(BASE, 0.8))
        for k in range(0, w, 12):
            t.d.polygon([(x + k, y + 46), (x + k + 6, y + 32), (x + k + 12, y + 46)], fill=LIGHT)
    for slots in (RIGHT, LEFT):
        for s in SIDES4:
            x, y, w, _ = slots[s]
            t.d.rectangle([x, y + 30, x + w - 1, y + 40], fill=shade(BASE, 0.8))
    collar_ring(t, 0.72)
    return t.im


def bomber():
    t = T()
    shirt_body(t, HAND, HEM, MID)
    rib = (52, 52, 56)
    cuffs(t, HAND, 9, rib)
    hem_band(t, HEM, 9, rib)
    fx, fy, _, _ = front()
    t.d.rectangle([fx + 36, fy, fx + 92, fy + 8], fill=rib)
    t.d.rectangle([fx + 62, fy + 8, fx + 65, fy + HEM], fill=METAL)
    x, y, w, _ = LEFT["L"]  # the sleeve pocket
    t.d.rectangle([x + 16, y + 14, x + 48, y + 34], fill=shade(MID, 0.85), outline=shade(MID, 0.7), width=2)
    for px in (fx + 14, fx + 92):
        t.d.rectangle([px, fy + 74, px + 22, fy + 78], fill=shade(MID, 0.7))
    return t.im


# ---------------------------------------------------------------- pants
def pants_body(t, leg_to=HAND, base=BASE):
    t.torso(base, UT_PX - 8, 128, 1.0, 0.9)
    t.limbs(base, 0, leg_to, 1.03, 0.9)


def belt(t, c=(46, 40, 34), buckle=METAL):
    for s in SIDES4:
        x, y, w, _ = TORSO[s]
        t.d.rectangle([x, y + UT_PX + 2, x + w - 1, y + UT_PX + 10], fill=c)
    fx, fy, _, _ = front()
    t.d.rectangle([fx + 56, fy + UT_PX + 1, fx + 72, fy + UT_PX + 11], outline=buckle, width=3)


def sneakers(t, c=SHOE):
    t.limbs(c, HAND, 128, 1.05, 0.9)
    t.limb_band(SOLE, 123, 128)
    for slots in (RIGHT, LEFT):
        x, y, w, _ = slots["F"]
        t.d.line([(x + 18, y + HAND + 6), (x + 46, y + HAND + 6)], fill=SOLE, width=2)  # laces
        t.d.line([(x + 18, y + HAND + 11), (x + 46, y + HAND + 11)], fill=SOLE, width=2)


def boots(t):
    t.limbs((52, 46, 40), HAND - 14, 128, 1.05, 0.85)
    t.limb_band((24, 22, 20), 122, 128)
    t.limb_line((52, 46, 40), HAND - 14, 0.6, 2)


def jeans():
    t = T()
    pants_body(t)
    t.limb_line(BASE, HAND - 4, 0.8, 3)  # the hem
    for slots in (RIGHT, LEFT):
        for s in ("L", "R"):
            x, y, w, _ = slots[s]
            t.d.line([(x + w // 2, y), (x + w // 2, y + HAND)], fill=shade(BASE, 0.82), width=2)  # side seams
    belt(t)
    fx, fy, _, _ = front()
    for px in (fx + 6, fx + 90):
        t.d.arc([px, fy + UT_PX + 2, px + 32, fy + 140], 270, 360 if px > fx + 50 else 270, fill=shade(BASE, 0.8), width=2)
    sneakers(t)
    return t.im


def cargo():
    t = T()
    pants_body(t, HAND - 14, MID)
    for slots, side in ((RIGHT, "R"), (LEFT, "L")):
        x, y, w, _ = slots[side]
        t.d.rectangle([x + 10, y + 26, x + w - 11, y + 52], fill=shade(MID, 0.92), outline=shade(MID, 0.7), width=2)
        t.d.line([(x + 10, y + 32), (x + w - 11, y + 32)], fill=shade(MID, 0.7), width=2)
    belt(t)
    boots(t)
    return t.im


def joggers():
    t = T()
    pants_body(t)
    cuffs(t, HAND, 10, shade(BASE, 0.85))
    for s in SIDES4:
        x, y, w, _ = TORSO[s]
        t.d.rectangle([x, y + UT_PX - 2, x + w - 1, y + UT_PX + 10], fill=shade(BASE, 0.88))
    fx, fy, _, _ = front()
    t.d.line([(fx + 58, fy + UT_PX + 10), (fx + 56, fy + 127)], fill=LIGHT, width=3)  # drawstring
    t.d.line([(fx + 70, fy + UT_PX + 10), (fx + 72, fy + 127)], fill=LIGHT, width=3)
    sneakers(t)
    return t.im


def shorts():
    t = T()
    pants_body(t, 40)
    t.limb_line(BASE, 39, 0.75, 3)
    belt(t)
    t.limb_band(LIGHT, HAND - 22, HAND)  # high socks
    t.limb_line(LIGHT, HAND - 18, 0.8, 2)
    sneakers(t)
    return t.im


def track_pants():
    t = T()
    pants_body(t, HAND, MID)
    for slots, side in ((RIGHT, "R"), (LEFT, "L")):
        x, y, w, _ = slots[side]
        for k in (-9, 3):
            t.d.rectangle([x + w // 2 + k, y, x + w // 2 + k + 5, y + HAND - 1], fill=LIGHT)
    for s in SIDES4:
        x, y, w, _ = TORSO[s]
        t.d.rectangle([x, y + UT_PX - 2, x + w - 1, y + UT_PX + 8], fill=shade(MID, 0.85))
    sneakers(t, (240, 240, 240))
    t.limb_band(SHOE, 123, 128)
    return t.im


def slacks():
    t = T()
    pants_body(t, HAND - 4)
    for slots in (RIGHT, LEFT):  # the crease
        for s in ("F", "B"):
            x, y, w, _ = slots[s]
            t.d.line([(x + w // 2, y), (x + w // 2, y + HAND - 4)], fill=shade(BASE, 0.85), width=2)
    belt(t, (28, 26, 26), (200, 170, 90))
    t.limbs((26, 24, 26), HAND - 4, 128, 1.15, 0.85)  # polished shoes
    t.limb_band((14, 14, 16), 124, 128)
    return t.im


# ---------------------------------------------------------------- more (2026-11-17 night)
def flannel():
    t = T()
    shirt_body(t, HAND, HEM, BASE)
    for holder in (TORSO, RIGHT, LEFT):  # a plaid: dark bands both ways and a light pinstripe
        for s in SIDES4:
            x, y, w, h = holder[s]
            for k in range(0, w, 16):
                t.d.rectangle([x + k, y, x + k + 5, y + min(h, HAND) - 1], fill=shade(BASE, 0.78))
            for k in range(0, min(h, HAND), 16):
                t.d.rectangle([x, y + k, x + w - 1, y + k + 5], fill=shade(BASE, 0.78))
            for k in range(8, w, 16):
                t.d.line([(x + k, y), (x + k, y + min(h, HAND) - 1)], fill=LIGHT, width=1)
    t.d.rectangle([TORSO["F"][0], TORSO["F"][1] + HEM, TORSO["F"][0] + 127, TORSO["F"][1] + 127], fill=(0, 0, 0, 0))
    for s in SIDES4:  # keep the hem line clean
        x, y, w, _ = TORSO[s]
        t.d.rectangle([x, y + HEM, x + w - 1, y + 127], fill=(0, 0, 0, 0))
    for slots in (RIGHT, LEFT):
        for s in SIDES4:
            x, y, w, _ = slots[s]
            t.d.rectangle([x, y + HAND, x + w - 1, y + 127], fill=(0, 0, 0, 0))
    cuffs(t, HAND, 6, shade(BASE, 0.7))
    fx, fy, _, _ = front()
    t.d.line([(fx + 64, fy + 10), (fx + 64, fy + HEM)], fill=shade(BASE, 0.6), width=2)
    for k in range(5):
        t.d.ellipse([fx + 66, fy + 22 + k * 16, fx + 70, fy + 26 + k * 16], fill=LIGHT)
    t.d.polygon([(fx + 38, fy), (fx + 62, fy + 14), (fx + 54, fy + 20), (fx + 34, fy + 6)], fill=shade(BASE, 0.7))
    t.d.polygon([(fx + 90, fy), (fx + 66, fy + 14), (fx + 74, fy + 20), (fx + 94, fy + 6)], fill=shade(BASE, 0.7))
    return t.im


def denim_jacket():
    t = T()
    shirt_body(t, HAND, HEM, MID)
    cuffs(t, HAND, 8, shade(MID, 0.85))
    hem_band(t, HEM, 8, shade(MID, 0.85))
    fx, fy, _, _ = front()
    t.d.polygon([(fx + 30, fy), (fx + 60, fy), (fx + 60, fy + 18), (fx + 40, fy + 14)], fill=shade(MID, 0.85))
    t.d.polygon([(fx + 98, fy), (fx + 68, fy), (fx + 68, fy + 18), (fx + 88, fy + 14)], fill=shade(MID, 0.85))
    t.d.line([(fx + 64, fy + 6), (fx + 64, fy + HEM)], fill=shade(MID, 0.7), width=2)
    for k in range(5):
        t.d.ellipse([fx + 67, fy + 22 + k * 16, fx + 72, fy + 27 + k * 16], fill=(200, 170, 110))
    for px in (fx + 14, fx + 82):  # flap pockets with stitching
        t.d.rectangle([px, fy + 28, px + 32, fy + 50], outline=LIGHT, width=1)
        t.d.polygon([(px, fy + 28), (px + 32, fy + 28), (px + 16, fy + 38)], fill=shade(MID, 0.88), outline=LIGHT)
    for s in SIDES4:  # the yoke seam
        x, y, w, _ = TORSO[s]
        t.d.line([(x, y + 22), (x + w - 1, y + 22)], fill=LIGHT, width=1)
    return t.im


def leather_jacket():
    t = T()
    dark = (120, 120, 124)
    shirt_body(t, HAND, HEM, dark)
    cuffs(t, HAND, 6, shade(dark, 0.7))
    fx, fy, _, _ = front()
    t.d.polygon([(fx + 24, fy), (fx + 56, fy), (fx + 64, fy + 40), (fx + 40, fy + 24)], fill=shade(dark, 0.8))  # lapels
    t.d.polygon([(fx + 104, fy), (fx + 72, fy), (fx + 64, fy + 40), (fx + 88, fy + 24)], fill=shade(dark, 0.8))
    t.d.line([(fx + 80, fy + 20), (fx + 60, fy + HEM)], fill=(170, 170, 176), width=3)  # the off-centre zip
    t.d.line([(fx + 18, fy + 64), (fx + 40, fy + 60)], fill=(170, 170, 176), width=2)
    t.d.line([(fx + 88, fy + 60), (fx + 110, fy + 64)], fill=(170, 170, 176), width=2)
    hem_band(t, HEM, 6, shade(dark, 0.7))
    return t.im


def blazer():
    t = T()
    shirt_body(t, HAND)
    cuffs(t, HAND, 4, shade(BASE, 0.8))
    fx, fy, _, _ = front()
    t.d.polygon([(fx + 40, fy), (fx + 88, fy), (fx + 64, fy + 56)], fill=LIGHT)  # the shirt under it
    t.d.polygon([(fx + 60, fy + 8), (fx + 68, fy + 8), (fx + 70, fy + 50), (fx + 64, fy + 58), (fx + 58, fy + 50)], fill=(40, 40, 46))  # tie
    t.d.polygon([(fx + 30, fy), (fx + 40, fy), (fx + 64, fy + 56), (fx + 46, fy + 34)], fill=shade(BASE, 0.85), outline=shade(BASE, 0.7))
    t.d.polygon([(fx + 98, fy), (fx + 88, fy), (fx + 64, fy + 56), (fx + 82, fy + 34)], fill=shade(BASE, 0.85), outline=shade(BASE, 0.7))
    for k in range(2):
        t.d.ellipse([fx + 61, fy + 64 + k * 16, fx + 67, fy + 70 + k * 16], fill=shade(BASE, 0.6))
    t.d.rectangle([fx + 84, fy + 40, fx + 104, fy + 44], fill=shade(BASE, 0.75))
    return t.im


def turtleneck():
    t = T()
    shirt_body(t, HAND, HEM + 2)
    cuffs(t, HAND, 10, shade(BASE, 0.9))
    hem_band(t, HEM + 2, 8, shade(BASE, 0.9))
    for s in SIDES4:  # the tall collar shows round the top of the torso
        x, y, w, _ = TORSO[s]
        t.d.rectangle([x, y, x + w - 1, y + 10], fill=shade(BASE, 0.9))
        for k in range(0, w, 6):
            t.d.line([(x + k, y), (x + k, y + 10)], fill=shade(BASE, 0.8), width=1)
    x, y, w, h = TORSO["U"]
    t.d.ellipse([x + 36, y + 14, x + w - 37, y + h - 14], fill=shade(BASE, 0.88), outline=shade(BASE, 0.75), width=3)
    return t.im


def raglan():
    t = T()
    shirt_body(t, LOWER + 10)
    t.limbs(MID, 0, LOWER + 10, 1.04, 0.92)  # contrast sleeves
    fx, fy, _, _ = front()
    bx, by, _, _ = back()
    for x0, y0 in ((fx, fy), (bx, by)):  # the diagonal raglan seams
        t.d.polygon([(x0, y0), (x0 + 30, y0), (x0, y0 + 34)], fill=MID)
        t.d.polygon([(x0 + 127, y0), (x0 + 97, y0), (x0 + 127, y0 + 34)], fill=MID)
    cuffs(t, LOWER + 10, 4, shade(MID, 0.8))
    collar_ring(t, 0.7)
    return t.im


def graphic_tee():
    t = tee_canvas = T()
    shirt_body(tee_canvas, 30)
    t.limb_line(BASE, 29, 0.8, 2)
    collar_ring(t)
    fx, fy, _, _ = front()
    cx, cy = fx + 64, fy + 52  # an original graphic: a comet over a city skyline
    ink = (48, 48, 54)
    t.d.ellipse([cx - 30, cy - 30, cx + 30, cy + 30], outline=ink, width=4)
    t.d.ellipse([cx + 4, cy - 22, cx + 16, cy - 10], fill=ink)
    t.d.polygon([(cx + 6, cy - 12), (cx - 18, cy + 4), (cx + 10, cy - 18)], fill=ink)
    for i, (w, h) in enumerate(((8, 14), (10, 22), (8, 10), (12, 18), (8, 12))):
        x0 = cx - 26 + i * 11
        t.d.rectangle([x0, cy + 24 - h, x0 + w, cy + 24], fill=ink)
    return t.im


def puffer_vest():
    t = T()
    shirt_body(t, HAND, HEM, LIGHT)  # a long-sleeve under it
    cuffs(t, HAND, 6, shade(LIGHT, 0.85))
    t.torso(MID, 0, HEM + 4, 1.06, 0.88)
    for s in SIDES4:  # the quilting
        x, y, w, _ = TORSO[s]
        for k in range(14, HEM + 4, 18):
            t.d.line([(x, y + k), (x + w - 1, y + k)], fill=shade(MID, 0.72), width=3)
    fx, fy, _, _ = front()
    t.d.rectangle([fx + 62, fy, fx + 65, fy + HEM + 4], fill=METAL)
    t.d.rectangle([fx + 40, fy, fx + 87, fy + 10], fill=shade(MID, 0.9))
    return t.im


def skirt():
    t = T()
    t.torso(BASE, UT_PX - 8, 128, 1.0, 0.9)
    t.limbs(BASE, 0, 40, 1.05, 0.88)  # a knee-length skirt over the thighs
    for slots in (RIGHT, LEFT):
        for s in SIDES4:
            x, y, w, _ = slots[s]
            for k in range(8, w, 14):
                t.d.line([(x + k, y), (x + k + 2, y + 39)], fill=shade(BASE, 0.84), width=2)  # pleats
    t.limb_line(BASE, 39, 0.75, 3)
    for s in SIDES4:
        x, y, w, _ = TORSO[s]
        t.d.rectangle([x, y + UT_PX, x + w - 1, y + UT_PX + 8], fill=shade(BASE, 0.85))
    t.limbs((40, 36, 40), HAND, 128, 1.1, 0.85)  # flats
    t.limb_band((24, 22, 24), 124, 128)
    return t.im


def long_skirt():
    t = T()
    t.torso(BASE, UT_PX - 8, 128, 1.0, 0.9)
    t.limbs(BASE, 0, HAND - 6, 1.05, 0.86)
    for slots in (RIGHT, LEFT):
        for s in SIDES4:
            x, y, w, _ = slots[s]
            for k in range(10, w, 16):
                t.d.line([(x + k, y + 10), (x + k - 3, y + HAND - 7)], fill=shade(BASE, 0.86), width=2)
    t.limb_line(BASE, HAND - 8, 0.8, 3)
    for s in SIDES4:
        x, y, w, _ = TORSO[s]
        t.d.rectangle([x, y + UT_PX, x + w - 1, y + UT_PX + 6], fill=shade(BASE, 0.8))
    t.limbs((60, 46, 40), HAND - 6, 128, 1.1, 0.85)  # boots
    t.limb_band((30, 24, 20), 124, 128)
    return t.im


def ripped_jeans():
    im = jeans()
    t = T()
    t.im = im
    from PIL import ImageDraw
    t.d = ImageDraw.Draw(im)
    for slots in (RIGHT, LEFT):  # torn knees (the skin shows) with frayed threads
        for s in ("F",):
            x, y, w, _ = slots[s]
            t.d.rectangle([x + 16, y + 52, x + 46, y + 62], fill=(0, 0, 0, 0))
            for k in range(18, 46, 5):
                t.d.line([(x + k, y + 54), (x + k + 2, y + 60)], fill=LIGHT, width=1)
        x, y, w, _ = slots["F"]
        t.d.rectangle([x + 10, y + 22, x + 30, y + 26], fill=(0, 0, 0, 0))
    return im


def chinos():
    t = T()
    pants_body(t, HAND - 8)
    t.limb_band(shade(BASE, 0.88), HAND - 16, HAND - 8)  # rolled hems
    t.limb_line(BASE, HAND - 12, 0.75, 1)
    belt(t, (90, 60, 40), (190, 160, 90))
    for slots in (RIGHT, LEFT):
        for s in ("L", "R"):
            x, y, w, _ = slots[s]
            t.d.line([(x + w // 2, y), (x + w // 2, y + HAND - 16)], fill=shade(BASE, 0.85), width=1)
    t.limbs(LIGHT, HAND - 8, HAND, 1.0, 1.0)  # a flash of sock
    t.limbs((96, 64, 44), HAND, 128, 1.15, 0.85)  # loafers
    t.limb_band((40, 28, 22), 124, 128)
    return t.im


def leggings():
    t = T()
    pants_body(t)
    for slots, side in ((RIGHT, "R"), (LEFT, "L")):
        x, y, w, _ = slots[side]
        t.d.rectangle([x + w // 2 - 3, y, x + w // 2 + 2, y + HAND - 1], fill=shade(BASE, 0.78))
    for s in SIDES4:
        x, y, w, _ = TORSO[s]
        t.d.rectangle([x, y + UT_PX - 2, x + w - 1, y + UT_PX + 12], fill=shade(BASE, 0.85))
    sneakers(t, (232, 232, 236))
    t.limb_band(SHOE, 123, 128)
    return t.im


def sweatpants():
    t = T()
    pants_body(t, HAND, MID)
    t.limb_line(MID, HAND - 3, 0.8, 3)
    for s in SIDES4:
        x, y, w, _ = TORSO[s]
        t.d.rectangle([x, y + UT_PX - 2, x + w - 1, y + UT_PX + 10], fill=shade(MID, 0.88))
    for slots, side in ((RIGHT, "R"), (LEFT, "L")):  # a side pocket
        x, y, w, _ = slots[side]
        t.d.rectangle([x + 18, y + 20, x + 46, y + 44], outline=shade(MID, 0.75), width=2)
    fx, fy, _, _ = front()
    t.d.line([(fx + 58, fy + UT_PX + 10), (fx + 56, fy + 127)], fill=LIGHT, width=3)
    t.d.line([(fx + 70, fy + UT_PX + 10), (fx + 72, fy + 127)], fill=LIGHT, width=3)
    sneakers(t)
    return t.im


SHIRTS = {"Tee": tee, "LongSleeve": long_sleeve, "Hoodie": hoodie, "ZipJacket": zip_jacket, "TrackTop": track_top,
          "ButtonShirt": button_shirt, "Polo": polo, "Tank": tank, "Sweater": sweater, "Bomber": bomber,
          "Flannel": flannel, "DenimJacket": denim_jacket, "LeatherJacket": leather_jacket, "Blazer": blazer,
          "Turtleneck": turtleneck, "Raglan": raglan, "GraphicTee": graphic_tee, "PufferVest": puffer_vest}
PANTS = {"Jeans": jeans, "Cargo": cargo, "Joggers": joggers, "Shorts": shorts, "TrackPants": track_pants,
         "Slacks": slacks, "Skirt": skirt, "LongSkirt": long_skirt, "RippedJeans": ripped_jeans, "Chinos": chinos,
         "Leggings": leggings, "Sweatpants": sweatpants}
SAMPLES = [(52, 104, 196), (196, 52, 52), (60, 150, 90), (230, 170, 50), (120, 70, 170), (40, 40, 48),
           (236, 236, 240), (230, 110, 150), (70, 160, 190), (150, 110, 70)]


def tinted(im, rgb):
    """Roblox's Clothing.Color3: the image times the colour."""
    r, g, b, a = im.split()
    r = r.point(lambda v: v * rgb[0] // 255)
    g = g.point(lambda v: v * rgb[1] // 255)
    b = b.point(lambda v: v * rgb[2] // 255)
    return Image.merge("RGBA", (r, g, b, a))


if __name__ == "__main__":
    tiles = []
    for i, (name, fn) in enumerate(SHIRTS.items()):
        im = fn()
        im.save(os.path.join(OUT, "Shirt_%s.png" % name))
        tiles.append(tinted(im, SAMPLES[i % len(SAMPLES)]))
    for i, (name, fn) in enumerate(PANTS.items()):
        im = fn()
        im.save(os.path.join(OUT, "Pants_%s.png" % name))
        tiles.append(tinted(im, SAMPLES[(i + 3) % len(SAMPLES)]))
    # sample outfits for art/blender/clothed.py heroes (tinted as the game tints them)
    prev = os.path.join(OUT, "preview")
    os.makedirs(prev, exist_ok=True)
    outfits = [("Hoodie", 0, "Jeans", 5), ("Tee", 1, "Cargo", 9), ("Bomber", 5, "Joggers", 5), ("TrackTop", 2, "TrackPants", 5),
               ("ButtonShirt", 6, "Slacks", 5), ("Polo", 3, "Shorts", 6), ("Sweater", 4, "Jeans", 0), ("ZipJacket", 8, "Cargo", 5),
               ("Flannel", 1, "RippedJeans", 0), ("DenimJacket", 8, "Skirt", 5), ("LeatherJacket", 5, "Chinos", 9),
               ("Blazer", 5, "Slacks", 5), ("Turtleneck", 7, "LongSkirt", 5), ("Raglan", 6, "Leggings", 5),
               ("GraphicTee", 6, "Sweatpants", 2), ("PufferVest", 3, "Jeans", 0)]
    for i, (sh, sc, pa, pc) in enumerate(outfits):
        tinted(SHIRTS[sh](), SAMPLES[sc]).save(os.path.join(prev, "Hero%d_Shirt.png" % (i + 1)))
        tinted(PANTS[pa](), SAMPLES[pc]).save(os.path.join(prev, "Hero%d_Pants.png" % (i + 1)))
    cols = 4
    tw, th = W // 2, H // 2
    sheet = Image.new("RGB", (tw * cols, th * ((len(tiles) + cols - 1) // cols)), (150, 150, 150))
    for i, im in enumerate(tiles):
        tile = Image.new("RGBA", im.size, (170, 170, 170, 255))
        tile.alpha_composite(im)
        sheet.paste(tile.convert("RGB").resize((tw - 4, th - 4)), ((i % cols) * tw + 2, (i // cols) * th + 2))
    sheet.save(os.path.join(ROOT, "preview", "hero_clothes_templates.png"))
    print("wrote", len(SHIRTS), "shirts and", len(PANTS), "pants")
