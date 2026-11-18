# art/clothes/uniforms.py: every robot kind's Roblox-look uniform, in three versions each (Grunt, Veteran, Elite),
# so enemies do not look repetitive (nate, 2026-11-17). Drawn on Roblox's classic Shirt and Pants template; each
# uniform is saved as <Kind>_<Version>.png with the Shirt and the Pants side by side (1170 x 559, what the game's
# robots wear: Shared.ClothesMap) plus the separate Shirt and Pants (real Roblox clothing, if ever needed).
# Areas left clear show the robot's skin (bare arms, rolled sleeves).
# Output: art/export/clothes/uniforms/*.png and art/preview/uniforms_templates.png + uniforms_templates_new.png
# (every uniform's template: the first 9 kinds, then the 9 added with the new enemy types).
# Run: python3 art/clothes/uniforms.py   (PIL only)
#      then, after art/blender/clothed.py has rendered each version (uniforms <Version> and uniforms <Version> new):
#      python3 art/clothes/uniforms.py --stack   -> art/preview/uniforms.png and uniforms_new.png (the on-body renders,
#      Grunt, Veteran and Elite top to bottom)
import math
import os
import random
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from trooper import (TORSO, RIGHT, LEFT, SIDES4, UT_PX, UPPER_PX, W, H, shade, panel, seam, diamond,  # noqa: E402
                     shirt as trooper_shirt, pants as trooper_pants, TRIM as T_TRIM, SUIT as T_SUIT)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "export", "clothes", "uniforms")
os.makedirs(OUT, exist_ok=True)

WHITE = (236, 238, 242)
DARK = (18, 20, 28)
GOLD = (232, 190, 80)
STEEL = (66, 70, 80)
HAND = 108  # the hand's (or foot's) rows start here in a limb strip
LOWER = UPPER_PX  # the forearm (or shin) rows start here


class T:
    """One template (the Shirt or the Pants) with drawing helpers in template terms."""

    def __init__(self):
        self.im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.im)

    def torso(self, c, r0=0, r1=UT_PX, top=1.08, bottom=0.9):
        for s in SIDES4:
            x, y, w, h = TORSO[s]
            panel(self.d, (x, y + r0, w, r1 - r0), c, top, bottom, edge=False)
        if r0 == 0:
            panel(self.d, TORSO["U"], c, 1.12, 1.0, edge=False)
        if r1 == 128:
            panel(self.d, TORSO["D"], c, 0.8, 0.7, edge=False)

    def limbs(self, c, r0, r1, top=1.06, bottom=0.88):
        for slots in (RIGHT, LEFT):
            for s in SIDES4:
                x, y, w, h = slots[s]
                panel(self.d, (x, y + r0, w, r1 - r0), c, top, bottom, edge=False)
            if r0 == 0:
                panel(self.d, slots["U"], c, 1.12, 1.0, edge=False)
            if r1 == 128:
                panel(self.d, slots["D"], c, 0.85, 0.8, edge=False)

    def limb_line(self, c, y, k=0.7, width=1):
        """A seam or cuff edge round every limb at row y."""
        for slots in (RIGHT, LEFT):
            for s in SIDES4:
                x, yy, w, h = slots[s]
                self.d.line([(x, yy + y), (x + w - 1, yy + y)], fill=shade(c, k), width=width)

    def limb_band(self, c, r0, r1):
        for slots in (RIGHT, LEFT):
            for s in SIDES4:
                x, y, w, h = slots[s]
                self.d.rectangle([x, y + r0, x + w - 1, y + r1 - 1], fill=c)

    def outer_stripe(self, c, r0, r1, wd=6):
        """A stripe down each limb's outer side (R on the right limb, L on the left)."""
        for slots, outer in ((RIGHT, "R"), (LEFT, "L")):
            x, y, w, h = slots[outer]
            self.d.rectangle([x + w // 2 - wd // 2, y + r0, x + w // 2 + wd // 2 - 1, y + r1 - 1], fill=c)

    def torso_sides_stripe(self, c, r0=0, r1=UT_PX, wd=8):
        for s in ("R", "L"):
            x, y, w, h = TORSO[s]
            self.d.rectangle([x + w // 2 - wd // 2, y + r0, x + w // 2 + wd // 2 - 1, y + r1 - 1], fill=c)

    def hstripes(self, c, r0, r1, period=12, wd=6, limbs_to=None):
        """Horizontal stripes over the torso rows r0..r1 (and the limbs down to row limbs_to): a burglar's top."""
        for s in SIDES4:
            x, y, w, h = TORSO[s]
            for yy in range(r0, r1, period):
                self.d.rectangle([x, y + yy, x + w - 1, y + min(r1, yy + wd) - 1], fill=c)
        if limbs_to:
            for slots in (RIGHT, LEFT):
                for s in SIDES4:
                    x, y, w, h = slots[s]
                    for yy in range(0, limbs_to, period):
                        self.d.rectangle([x, y + yy, x + w - 1, y + min(limbs_to, yy + wd) - 1], fill=c)

    def front(self):
        return TORSO["F"]

    def back(self):
        return TORSO["B"]


def save(kind, version, shirt, pants):
    both = Image.new("RGBA", (W * 2, H), (0, 0, 0, 0))
    both.paste(shirt, (0, 0))
    both.paste(pants, (W, 0))
    base = os.path.join(OUT, "%s_%s" % (kind, version))
    both.save(base + ".png")
    shirt.save(base + "_Shirt.png")
    pants.save(base + "_Pants.png")
    return both


# ---------------------------------------------------------------- emblems (original marks, one per kind)
def em_ring_slash(d, cx, cy, c, r=26):
    """The Null mark: a ring cut by a slash."""
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=c, width=7)
    d.line([(cx - r * 0.75, cy + r * 0.75), (cx + r * 0.75, cy - r * 0.75)], fill=c, width=7)


def em_eye(d, cx, cy, c):
    """The Sneak mark: a closed eye (a lidded arc with three lashes)."""
    d.arc([cx - 26, cy - 16, cx + 26, cy + 16], 20, 160, fill=c, width=6)
    for k in (-1, 0, 1):
        d.line([(cx + k * 14, cy + 14), (cx + k * 18, cy + 24)], fill=c, width=4)


def em_shield(d, cx, cy, c, inner):
    """The Sentry badge: a shield with a bar."""
    pts = [(cx - 18, cy - 20), (cx + 18, cy - 20), (cx + 18, cy + 2), (cx, cy + 22), (cx - 18, cy + 2)]
    d.polygon(pts, fill=c)
    d.rectangle([cx - 10, cy - 8, cx + 10, cy - 3], fill=inner)


def em_anchor(d, cx, cy, c):
    d.ellipse([cx - 6, cy - 24, cx + 6, cy - 12], outline=c, width=4)
    d.line([(cx, cy - 12), (cx, cy + 20)], fill=c, width=6)
    d.line([(cx - 14, cy - 4), (cx + 14, cy - 4)], fill=c, width=5)
    d.arc([cx - 20, cy, cx + 20, cy + 26], 0, 180, fill=c, width=6)


def em_wave(d, cx, cy, c):
    """The Diver mark: two waves."""
    for dy in (-6, 8):
        d.arc([cx - 24, cy + dy - 8, cx - 4, cy + dy + 8], 200, 340, fill=c, width=5)
        d.arc([cx - 4, cy + dy - 8, cx + 16, cy + dy + 8], 20, 160, fill=c, width=5)
        d.arc([cx + 16, cy + dy - 8, cx + 36, cy + dy + 8], 200, 340, fill=c, width=5)


def em_target(d, cx, cy, c):
    """The Torpedo mark: a crosshair."""
    d.ellipse([cx - 20, cy - 20, cx + 20, cy + 20], outline=c, width=5)
    d.line([(cx - 28, cy), (cx + 28, cy)], fill=c, width=4)
    d.line([(cx, cy - 28), (cx, cy + 28)], fill=c, width=4)


def em_fist(d, cx, cy, c):
    """The Brute mark: a fist in a circle (blocky)."""
    d.ellipse([cx - 26, cy - 26, cx + 26, cy + 26], fill=c)
    d.rounded_rectangle([cx - 14, cy - 12, cx + 14, cy + 12], 4, fill=shade(c, 0.55))
    for k in range(3):
        d.line([(cx - 14 + k * 10 + 4, cy - 12), (cx - 14 + k * 10 + 4, cy - 2)], fill=c, width=2)


# ---------------------------------------------------------------- the uniforms
def spark(v):
    """Spark Trooper: the blue jet suit (the Grunt is the original Trooper); veterans get white shoulders and sleeve
    chevrons, elites a navy suit with gold trim and a ringed emblem."""
    if v == "Grunt":
        return trooper_shirt(), trooper_pants()
    suit = T_SUIT if v == "Veteran" else (24, 36, 80)
    trim = T_TRIM if v == "Veteran" else GOLD
    s, p = T(), T()
    s.torso(suit)
    s.limbs(suit, 0, LOWER + 8)
    s.limbs(trim, LOWER + 8, 128, 1.05, 0.85)
    s.limb_band(shade(trim, 1.12), LOWER + 8, LOWER + 15)
    s.outer_stripe(trim, 0, LOWER + 8)
    s.torso_sides_stripe(trim)
    fx, fy, fw, _ = s.front()
    s.d.rectangle([fx + 40, fy, fx + 87, fy + 5], fill=trim)
    if v == "Veteran":
        s.limbs(WHITE, 0, 18, 1.0, 0.92)  # white shoulders
        for slots, side in ((RIGHT, "R"), (LEFT, "L")):
            x, y, w, h = slots[side]
            for k in range(2):  # rank chevrons
                yy = y + 26 + k * 8
                s.d.line([(x + 14, yy), (x + w // 2, yy + 6), (x + w - 14, yy)], fill=trim, width=3)
    else:
        s.d.ellipse([fx + 28, fy + 2, fx + 100, fy + 70], outline=GOLD, width=4)
    diamond(s.d, fx + 64, fy + 34, 30, 27, WHITE)
    diamond(s.d, fx + 64, fy + 34, 24, 21, trim)
    cx, cy = fx + 64, fy + 34
    s.d.polygon([(cx + 6, cy - 17), (cx - 6, cy + 1), (cx + 1, cy + 1), (cx - 6, cy + 17), (cx + 9, cy - 3),
                 (cx + 2, cy - 3), (cx + 9, cy - 17)], fill=DARK)
    p.torso(suit, UT_PX - 4, 128, 1.0, 0.85)
    for s_ in SIDES4:
        x, y, w, h = TORSO[s_]
        p.d.rectangle([x, y + UT_PX + 4, x + w - 1, y + UT_PX + 15], fill=trim)
    p.d.ellipse([fx + 55, fy + UT_PX + 1, fx + 72, fy + UT_PX + 18], fill=WHITE)
    p.limbs(suit, 0, LOWER + 10)
    p.limbs(trim, LOWER + 10, 128, 1.05, 0.85)
    p.limb_band(DARK, 123, 128)
    p.outer_stripe(trim, 0, LOWER + 10)
    return s.im, p.im


def burglar(v):
    """Burglar Bot: a striped long-sleeve top, dark trousers, black gloves and sneakers, a loot-bag strap."""
    base, stripe = {"Grunt": ((62, 62, 72), (210, 212, 218)), "Veteran": ((40, 40, 48), (190, 50, 50)),
                    "Elite": ((24, 24, 30), (220, 190, 90))}[v]
    s, p = T(), T()
    s.torso(base)
    s.limbs(base, 0, HAND)
    s.hstripes(stripe, 6, UT_PX, period=14, wd=7, limbs_to=HAND - 6)
    s.limbs((30, 30, 36), HAND, 128, 1.0, 0.85)  # gloves
    s.limb_line((30, 30, 36), HAND - 4, 0.5, 4)  # the knit cuff
    fx, fy, fw, _ = s.front()
    s.d.polygon([(fx + 8, fy), (fx + 26, fy), (fx + 122, fy + UT_PX), (fx + 104, fy + UT_PX)], fill=(92, 66, 44))  # strap
    bx, by, bw, _ = s.back()
    s.d.polygon([(bx + bw - 26, by), (bx + bw - 8, by), (bx + 24, by + UT_PX), (bx + 6, by + UT_PX)], fill=(92, 66, 44))
    s.d.rectangle([fx + 40, fy, fx + 87, fy + 6], fill=shade(base, 0.7))  # the collar
    if v == "Elite":
        s.d.rectangle([fx + 84, fy + 20, fx + 104, fy + 34], fill=(220, 190, 90))  # a gold tag
    pants_c = (36, 36, 44) if v != "Elite" else (20, 20, 26)
    p.torso(pants_c, UT_PX - 4, 128, 1.0, 0.85)
    for s_ in SIDES4:
        x, y, w, h = TORSO[s_]
        p.d.rectangle([x, y + UT_PX + 6, x + w - 1, y + UT_PX + 13], fill=(20, 20, 24))
    p.limbs(pants_c, 0, HAND)
    p.limbs((26, 26, 30), HAND, 128, 1.0, 0.9)  # sneakers
    p.limb_band(WHITE, 123, 128)  # white soles
    p.limb_line(pants_c, LOWER + 4, 0.7, 2)  # knee seam
    return s.im, p.im


def sneak(v):
    """Sneak Bot: a wrapped stealth suit with a sash, arm and shin wraps, split-toe boots, the closed-eye mark."""
    suit, trim = {"Grunt": ((45, 35, 70), (170, 90, 255)), "Veteran": ((26, 22, 40), (120, 200, 255)),
                  "Elite": ((14, 12, 20), (230, 60, 90))}[v]
    s, p = T(), T()
    s.torso(suit)
    s.limbs(suit, 0, 128)
    fx, fy, fw, _ = s.front()
    s.d.polygon([(fx, fy + 4), (fx + 18, fy + 4), (fx + 128, fy + UT_PX - 20), (fx + 128, fy + UT_PX - 2)], fill=trim)  # sash
    s.d.polygon([(fx + 64, fy), (fx + 52, fy + 30), (fx + 64, fy + 22), (fx + 76, fy + 30)], fill=shade(suit, 0.6))  # the wrap's V
    for k in range(5):  # forearm wraps
        s.limb_line(trim, LOWER + 6 + k * 9, 0.85, 3)
    s.limbs(shade(suit, 0.8), HAND, 128, 1.0, 0.9)
    em_eye(s.d, s.back()[0] + 64, s.back()[1] + 40, trim)
    p.torso(suit, UT_PX - 4, 128, 1.0, 0.85)
    for s_ in SIDES4:
        x, y, w, h = TORSO[s_]
        p.d.rectangle([x, y + UT_PX + 4, x + w - 1, y + UT_PX + 14], fill=trim)  # the sash belt
    p.limbs(suit, 0, 128)
    for k in range(5):
        p.limb_line(trim, LOWER + 4 + k * 9, 0.85, 3)  # shin wraps
    p.limbs(shade(suit, 0.75), HAND, 128, 1.0, 0.9)
    for slots in (RIGHT, LEFT):  # the split toe
        x, y, w, h = slots["F"]
        p.d.line([(x + w // 2 - 6, y + HAND + 4), (x + w // 2 - 6, y + 127)], fill=DARK, width=3)
    return s.im, p.im


def brute(v):
    """Brute Bot: a sleeveless brawler's top (bare arms, the skin shows), a champion's belt plate, wrist wraps,
    heavy boots, the fist mark."""
    top, trim = {"Grunt": ((150, 45, 45), (240, 200, 80)), "Veteran": ((30, 30, 34), (200, 50, 50)),
                 "Elite": ((235, 235, 240), (232, 190, 80))}[v]
    s, p = T(), T()
    s.torso(top)
    fx, fy, fw, _ = s.front()
    # the vest's shoulder straps leave the arms bare: clear the torso's top corners at the sides
    s.limbs(top, 0, 12, 1.0, 0.92)  # the top's edge over the shoulder
    s.limb_band(WHITE, HAND - 14, HAND)  # wrist wraps
    s.limb_line(WHITE, HAND - 7, 0.75, 2)
    s.torso_sides_stripe(trim, 0, UT_PX, 10)
    em_fist(s.d, fx + 64, fy + 40, trim)
    s.d.rectangle([fx + 34, fy, fx + 93, fy + 4], fill=trim)
    p.torso((40, 40, 48) if v != "Elite" else (60, 50, 40), UT_PX - 4, 128, 1.0, 0.85)
    # the champion's belt: a wide gold plate on the front
    for s_ in SIDES4:
        x, y, w, h = TORSO[s_]
        p.d.rectangle([x, y + UT_PX + 2, x + w - 1, y + UT_PX + 18], fill=shade(trim, 0.85))
    p.d.rounded_rectangle([fx + 34, fy + UT_PX - 2, fx + 94, fy + 127], 5, fill=trim, outline=shade(trim, 0.6), width=2)
    p.d.ellipse([fx + 54, fy + UT_PX + 4, fx + 74, fy + UT_PX + 20], fill=top)
    p.limbs((40, 40, 48) if v != "Elite" else (60, 50, 40), 0, HAND - 20)
    p.limbs((26, 22, 20), HAND - 20, 128, 1.0, 0.85)  # heavy boots, tall
    p.limb_band(DARK, 122, 128)
    p.limb_line((26, 22, 20), HAND - 10, 1.4, 2)  # the laces' line
    return s.im, p.im


def sentry(v):
    """Sentry: a security guard's uniform: collared shirt, chest pockets, the shield badge, an armband, trousers
    with a side stripe, a utility belt with pouches."""
    shirt_c, trim = {"Grunt": ((60, 90, 112), (80, 220, 255)), "Veteran": ((40, 56, 70), (255, 200, 80)),
                     "Elite": ((24, 30, 40), (255, 90, 90))}[v]
    s, p = T(), T()
    s.torso(shirt_c)
    s.limbs(shirt_c, 0, HAND)
    s.limbs((30, 30, 36), HAND, 128, 1.0, 0.9)  # black gloves
    s.limb_line(shirt_c, HAND - 2, 0.6, 3)  # the sleeve cuff
    fx, fy, fw, _ = s.front()
    s.d.polygon([(fx + 44, fy), (fx + 64, fy + 18), (fx + 84, fy), (fx + 74, fy), (fx + 64, fy + 8), (fx + 54, fy)], fill=shade(shirt_c, 0.7))
    s.d.line([(fx + 64, fy + 18), (fx + 64, fy + UT_PX)], fill=shade(shirt_c, 0.7), width=2)  # the placket
    for k in range(4):
        s.d.ellipse([fx + 62, fy + 26 + k * 18, fx + 66, fy + 30 + k * 18], fill=shade(shirt_c, 1.4))
    for px in (fx + 18, fx + 80):  # chest pockets
        s.d.rectangle([px, fy + 28, px + 30, fy + 50], outline=shade(shirt_c, 0.7), width=2)
        s.d.line([(px, fy + 34), (px + 30, fy + 34)], fill=shade(shirt_c, 0.7), width=2)
    em_shield(s.d, fx + 33, fy + 41, trim, shirt_c)
    for slots, side in ((RIGHT, "R"), (LEFT, "L")):  # the armband on the left arm only
        if slots is LEFT:
            for s_ in SIDES4:
                x, y, w, h = slots[s_]
                s.d.rectangle([x, y + 18, x + w - 1, y + 28], fill=trim)
    pants_c = (30, 34, 42)
    p.torso(pants_c, UT_PX - 4, 128, 1.0, 0.85)
    for s_ in SIDES4:
        x, y, w, h = TORSO[s_]
        p.d.rectangle([x, y + UT_PX + 4, x + w - 1, y + UT_PX + 14], fill=(22, 22, 26))
    for px in (fx + 6, fx + 30, fx + 86, fx + 108):  # pouches
        p.d.rectangle([px, fy + UT_PX + 2, px + 14, fy + UT_PX + 18], fill=STEEL)
    p.limbs(pants_c, 0, HAND - 8)
    p.outer_stripe(trim, 0, HAND - 8, 4)
    p.limbs((20, 20, 24), HAND - 8, 128, 1.0, 0.85)
    return s.im, p.im


def null(v):
    """Null Sentinel: the commander's long coat: high collar, white lapels, a double row of buttons, the ring
    and slash mark, gauntlet gloves, coat tails over the trousers."""
    coat, trim = {"Grunt": ((30, 30, 42), (235, 235, 245)), "Veteran": ((50, 20, 60), (235, 235, 245)),
                  "Elite": ((236, 236, 242), (40, 40, 52))}[v]
    s, p = T(), T()
    s.torso(coat)
    s.limbs(coat, 0, HAND - 14)
    s.limbs(trim, HAND - 14, 128, 1.0, 0.85)  # gauntlets
    s.limb_band(shade(trim, 0.8), HAND - 14, HAND - 10)
    fx, fy, fw, _ = s.front()
    s.d.rectangle([fx + 36, fy, fx + 92, fy + 10], fill=trim)  # the high collar
    s.d.polygon([(fx + 36, fy + 10), (fx + 54, fy + 10), (fx + 64, fy + 46), (fx + 46, fy + 30)], fill=trim)  # lapels
    s.d.polygon([(fx + 92, fy + 10), (fx + 74, fy + 10), (fx + 64, fy + 46), (fx + 82, fy + 30)], fill=trim)
    for k in range(4):
        for dx in (-14, 14):
            s.d.ellipse([fx + 64 + dx - 3, fy + 52 + k * 13, fx + 64 + dx + 3, fy + 58 + k * 13], fill=trim)
    em_ring_slash(s.d, s.back()[0] + 64, s.back()[1] + 46, trim, 30)
    s.d.rectangle([s.back()[0] + 36, s.back()[1], s.back()[0] + 92, s.back()[1] + 10], fill=trim)
    p.torso(coat, UT_PX - 4, 128, 1.0, 0.85)  # the coat continues over the hips
    for s_ in SIDES4:
        x, y, w, h = TORSO[s_]
        p.d.rectangle([x, y + UT_PX + 2, x + w - 1, y + UT_PX + 8], fill=trim)
    p.limbs(coat, 0, 40)  # the tails over the thighs
    p.limb_line(trim, 40, 1.0, 3)
    p.limbs((26, 26, 32), 40, HAND)
    p.limbs((14, 14, 18), HAND - 10, 128, 1.0, 0.9)
    return s.im, p.im


def diver(v):
    """Diver: a wetsuit with side panels, a chest zip, tank harness straps, knee pads, fins-coloured boots."""
    suit, panel_c = {"Grunt": ((30, 80, 100), (255, 200, 60)), "Veteran": ((20, 40, 60), (255, 120, 60)),
                     "Elite": ((14, 18, 24), (90, 230, 210))}[v]
    s, p = T(), T()
    s.torso(suit)
    s.limbs(suit, 0, 128)
    s.torso_sides_stripe(panel_c, 0, UT_PX, 22)
    s.outer_stripe(panel_c, 0, HAND, 12)
    s.limbs(shade(suit, 0.75), HAND, 128, 1.0, 0.9)
    fx, fy, fw, _ = s.front()
    s.d.line([(fx + 64, fy + 4), (fx + 64, fy + UT_PX)], fill=STEEL, width=4)  # the zip
    for sx in (fx + 24, fx + 104):  # harness straps
        s.d.rectangle([sx - 5, fy, sx + 5, fy + UT_PX], fill=DARK)
    s.d.rectangle([fx + 18, fy + 60, fx + 110, fy + 70], fill=DARK)
    bx, by, _, _ = s.back()
    for sx in (bx + 24, bx + 104):
        s.d.rectangle([sx - 5, by, sx + 5, by + UT_PX], fill=DARK)
    em_wave(s.d, fx + 30, fy + 30, panel_c)
    p.torso(suit, UT_PX - 4, 128, 1.0, 0.85)
    p.limbs(suit, 0, 128)
    p.outer_stripe(panel_c, 0, HAND, 12)
    for slots in (RIGHT, LEFT):  # knee pads
        x, y, w, h = slots["F"]
        p.d.rounded_rectangle([x + 12, y + LOWER - 6, x + w - 13, y + LOWER + 12], 4, fill=DARK)
    p.limbs(panel_c, HAND, 128, 1.0, 0.85)
    return s.im, p.im


def anchor(v):
    """Anchor: a deep-sea worker's overalls over a tee with rolled sleeves (bare forearms), brass buttons,
    heavy riveted boots, the anchor mark."""
    alls, tee = {"Grunt": ((90, 80, 60), (200, 150, 60)), "Veteran": ((60, 70, 80), (220, 220, 210)),
                 "Elite": ((40, 30, 24), (232, 190, 80))}[v]
    s, p = T(), T()
    s.torso(tee)
    s.limbs(tee, 0, 30)  # short sleeves, rolled
    s.limb_band(shade(tee, 0.8), 24, 30)
    s.limbs((60, 50, 40), HAND, 128, 1.0, 0.9)  # work gloves
    fx, fy, fw, _ = s.front()
    s.d.rectangle([fx + 22, fy + 26, fx + 106, fy + UT_PX], fill=alls)  # the bib
    for sx in (fx + 22, fx + 96):
        s.d.rectangle([sx, fy, sx + 10, fy + 30], fill=alls)  # straps
        s.d.ellipse([sx + 1, fy + 22, sx + 9, fy + 30], fill=GOLD)
    em_anchor(s.d, fx + 64, fy + 58, GOLD)
    bx, by, _, _ = s.back()
    s.d.polygon([(bx + 22, by), (bx + 32, by), (bx + 74, by + 60), (bx + 64, by + 60)], fill=alls)
    s.d.polygon([(bx + 106, by), (bx + 96, by), (bx + 54, by + 60), (bx + 64, by + 60)], fill=alls)
    s.d.rectangle([bx + 30, by + 56, bx + 98, by + UT_PX], fill=alls)
    p.torso(alls, UT_PX - 4, 128, 1.0, 0.85)
    p.limbs(alls, 0, HAND - 16)
    p.limb_line(alls, HAND - 16, 0.6, 3)
    p.limbs((50, 40, 32), HAND - 16, 128, 1.0, 0.85)
    for slots in (RIGHT, LEFT):  # rivets on the boots
        for s_ in SIDES4:
            x, y, w, h = slots[s_]
            for k in range(3):
                p.d.ellipse([x + 10 + k * 18, y + HAND - 10, x + 14 + k * 18, y + HAND - 6], fill=GOLD)
    return s.im, p.im


def torpedo(v):
    """Torpedo Sentry: a naval gunner's jacket: double-breasted with brass buttons, a sailor collar, red cuffs,
    trousers with a red side stripe, the crosshair mark."""
    jacket, trim = {"Grunt": ((40, 70, 80), (255, 90, 90)), "Veteran": ((24, 34, 56), (255, 90, 90)),
                    "Elite": ((230, 232, 236), (40, 60, 120))}[v]
    s, p = T(), T()
    s.torso(jacket)
    s.limbs(jacket, 0, HAND)
    s.limb_band(trim, HAND - 12, HAND - 4)
    s.limbs(WHITE, HAND, 128, 1.0, 0.9)  # white gloves
    fx, fy, fw, _ = s.front()
    bx, by, _, _ = s.back()
    s.d.rectangle([bx + 10, by, bx + 118, by + 34], fill=trim)  # the square sailor collar at the back
    s.d.rectangle([bx + 14, by + 26, bx + 114, by + 29], fill=WHITE)
    s.d.polygon([(fx + 30, fy), (fx + 64, fy + 40), (fx + 98, fy)], fill=trim)
    for k in range(3):
        for dx in (-18, 18):
            s.d.ellipse([fx + 64 + dx - 4, fy + 50 + k * 16, fx + 64 + dx + 4, fy + 58 + k * 16], fill=GOLD)
    em_target(s.d, fx + 100, fy + 30, trim)
    pants_c = shade(jacket, 0.8)
    p.torso(pants_c, UT_PX - 4, 128, 1.0, 0.85)
    for s_ in SIDES4:
        x, y, w, h = TORSO[s_]
        p.d.rectangle([x, y + UT_PX + 4, x + w - 1, y + UT_PX + 12], fill=DARK)
    p.limbs(pants_c, 0, HAND)
    p.outer_stripe(trim, 0, HAND, 5)
    p.limbs(DARK, HAND, 128, 1.0, 0.9)
    return s.im, p.im


# ---------------------------------------------------------------- the 9 newer kinds (2026-11-17)
def chevrons(t, n, c, y0=26, wd=3):
    """Rank chevrons on the outer side of both upper arms (a Veteran's mark)."""
    for slots, side in ((RIGHT, "R"), (LEFT, "L")):
        x, y, w, h = slots[side]
        for k in range(n):
            yy = y + y0 + k * 8
            t.d.line([(x + 14, yy), (x + w // 2, yy + 6), (x + w - 14, yy)], fill=c, width=wd)


def scuff(t, seed, n=70, dark=0.74):
    """Veteran wear: small worn patches and scratches on the cloth only (bare skin and clear areas stay clear)."""
    rng = random.Random(seed)
    alpha = t.im.getchannel("A")
    areas = [TORSO[s] for s in SIDES4] + [sl[s] for sl in (RIGHT, LEFT) for s in SIDES4]
    for _ in range(n):
        x, y, w, h = rng.choice(areas)
        px, py = x + rng.randrange(4, w - 4), y + rng.randrange(4, h - 4)
        c = t.im.getpixel((px, py))
        if c[3] == 0:
            continue
        col = shade(c[:3], dark if rng.random() < 0.65 else 1.22)
        if rng.random() < 0.55:
            rw, rh = rng.randint(2, 5), rng.randint(1, 3)
            t.d.ellipse([px - rw, py - rh, px + rw, py + rh], fill=col)
        else:
            ln = rng.randint(4, 9)
            t.d.line([(px, py), (px + ln, py + rng.randint(-3, 3))], fill=col, width=1)
    t.im.putalpha(alpha)


def pattern(t, img):
    """Lay a full-template pattern over everything drawn so far (clear areas stay clear)."""
    t.im.paste(img, (0, 0), t.im.getchannel("A"))


def camo_img(base, blots, seed, n=420):
    """A blotchy camouflage sheet: clusters of overlapping ovals in the blot colours over the base."""
    rng = random.Random(seed)
    im = Image.new("RGBA", (W, H), base + (255,))
    d = ImageDraw.Draw(im)
    for _ in range(n):
        c = rng.choice(blots)
        x, y = rng.randrange(W), rng.randrange(H)
        for _ in range(rng.randint(2, 4)):
            rx, ry = rng.randint(4, 11), rng.randint(3, 7)
            ox, oy = rng.randint(-8, 8), rng.randint(-5, 5)
            d.ellipse([x + ox - rx, y + oy - ry, x + ox + rx, y + oy + ry], fill=c)
    return im


def hex_img(base, line, r=9):
    """A hive of hexagon cells (the Swarmer's top)."""
    im = Image.new("RGBA", (W, H), base + (255,))
    d = ImageDraw.Draw(im)
    dx, dy = r * 1.732, r * 1.5
    for j in range(int(H / dy) + 2):
        for i in range(int(W / dx) + 2):
            cx, cy = i * dx + (dx / 2 if j % 2 else 0), j * dy
            pts = [(cx + r * math.cos(math.radians(30 + 60 * k)), cy + r * math.sin(math.radians(30 + 60 * k)))
                   for k in range(6)]
            d.polygon(pts, outline=line)
    return im


def plaid_img(base, dark, light):
    """A flannel check: wide dark bands both ways, thin light lines between."""
    im = Image.new("RGBA", (W, H), base + (255,))
    ov = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    for k in range(0, max(W, H), 26):
        d.rectangle([k, 0, k + 9, H], fill=dark + (120,))
        d.rectangle([0, k, W, k + 9], fill=dark + (120,))
        d.line([(k + 17, 0), (k + 17, H)], fill=light + (150,), width=1)
        d.line([(0, k + 17), (W, k + 17)], fill=light + (150,), width=1)
    im.alpha_composite(ov)
    return im


def hazard(t, x, y, w, h, c1, c2, period=10):
    """Black and orange hazard stripes in a rectangle."""
    tile = Image.new("RGBA", (w, h), c1 + (255,))
    td = ImageDraw.Draw(tile)
    for k in range(-h, w + h, period):
        td.polygon([(k, 0), (k + period // 2, 0), (k + period // 2 - h, h), (k - h, h)], fill=c2)
    t.im.paste(tile, (x, y))


def limb_hazard(t, r0, r1, c1, c2):
    for slots in (RIGHT, LEFT):
        for s in SIDES4:
            x, y, w, h = slots[s]
            hazard(t, x, y + r0, w, r1 - r0, c1, c2)


def torso_hazard(t, r0, r1, c1, c2):
    for s in SIDES4:
        x, y, w, h = TORSO[s]
        hazard(t, x, y + r0, w, r1 - r0, c1, c2)


def chain(d, p0, p1, c, link=9):
    """A chain of alternating oval links from p0 to p1."""
    (x0, y0), (x1, y1) = p0, p1
    n = max(1, int(math.hypot(x1 - x0, y1 - y0) / (link * 0.8)))
    for k in range(n + 1):
        x, y = x0 + (x1 - x0) * k / n, y0 + (y1 - y0) * k / n
        if k % 2:
            d.ellipse([x - link / 2, y - 2.5, x + link / 2, y + 2.5], outline=c, width=2)
        else:
            d.ellipse([x - 3, y - link / 2 + 1, x + 3, y + link / 2 - 1], outline=c, width=2)


def em_wall(d, cx, cy, c, inner, sc=1.0):
    """The Shield Bearer mark: three tower shields side by side, the middle one forward."""
    for k in (-1, 1, 0):
        w, h = 16 * sc, (34 if k else 42) * sc
        x = cx + k * 15 * sc
        top = cy - h / 2
        d.rounded_rectangle([x - w / 2, top, x + w / 2, top + h], int(6 * sc), fill=c, outline=inner, width=2)
        d.rectangle([x - w / 2 + 3, top + h * 0.38, x + w / 2 - 3, top + h * 0.38 + 3 * sc], fill=inner)


def em_crest(d, cx, cy, c, sc=1.0):
    """The Captain mark: a three-pointed crest over two bars."""
    s = sc
    d.polygon([(cx - 20 * s, cy + 2 * s), (cx - 20 * s, cy - 14 * s), (cx - 10 * s, cy - 4 * s), (cx, cy - 20 * s),
               (cx + 10 * s, cy - 4 * s), (cx + 20 * s, cy - 14 * s), (cx + 20 * s, cy + 2 * s)], fill=c)
    for k in range(2):
        y = cy + (7 + k * 8) * s
        d.rectangle([cx - 20 * s, y, cx + 20 * s, y + 4 * s], fill=c)


def em_leaf(d, cx, cy, c, vein, sc=1.0):
    """The Sniper mark: a slanted leaf with its vein."""
    s = sc
    pts = [(cx + (-16 + 32 * i / 12) * s, cy + (14 - 28 * i / 12) * s - math.sin(math.pi * i / 12) * 9 * s)
           for i in range(13)]
    pts += [(cx + (16 - 32 * i / 12) * s, cy + (-14 + 28 * i / 12) * s + math.sin(math.pi * i / 12) * 9 * s)
            for i in range(13)]
    d.polygon(pts, fill=c)
    d.line([(cx - 18 * s, cy + 16 * s), (cx + 14 * s, cy - 12 * s)], fill=vein, width=2)


def em_bomb(d, cx, cy, c, spark, sc=1.0):
    """The Bomber mark: a round charge with a lit fuse."""
    s = sc
    d.ellipse([cx - 16 * s, cy - 10 * s, cx + 16 * s, cy + 22 * s], fill=c)
    d.rectangle([cx - 5 * s, cy - 15 * s, cx + 5 * s, cy - 8 * s], fill=c)
    d.line([(cx, cy - 15 * s), (cx + 6 * s, cy - 22 * s), (cx + 12 * s, cy - 20 * s)], fill=c,
           width=max(2, int(2 * s)))
    sx, sy = cx + 14 * s, cy - 22 * s
    for a in range(0, 360, 45):
        r = (7 if a % 90 == 0 else 4) * s
        d.line([(sx, sy), (sx + r * math.cos(math.radians(a)), sy + r * math.sin(math.radians(a)))], fill=spark,
               width=2)
    d.ellipse([cx - 9 * s, cy - 3 * s, cx - 3 * s, cy + 3 * s], fill=shade(c, 1.8) if sum(c) > 90 else STEEL)


def em_plus(d, cx, cy, c, sc=1.0):
    """The Medic Unit mark: a green plus in a green hexagon (a repair mark; never a red cross)."""
    r = 22 * sc
    pts = [(cx + r * math.cos(math.radians(60 * k)), cy + r * math.sin(math.radians(60 * k))) for k in range(6)]
    d.polygon(pts, outline=c, width=max(3, int(4 * sc)))
    a, b = 4.5 * sc, 13 * sc
    d.rectangle([cx - a, cy - b, cx + a, cy + b], fill=c)
    d.rectangle([cx - b, cy - a, cx + b, cy + a], fill=c)


def em_wrench(d, cx, cy, c, bg, ln=26, sc=1.0):
    """A wrench lying diagonally, open jaws at both ends (behind the Elite medic's plus)."""
    s = sc
    x0, y0, x1, y1 = cx - ln * s, cy + ln * s, cx + ln * s, cy - ln * s
    d.line([(x0, y0), (x1, y1)], fill=c, width=int(6 * s))
    for (x, y), k in (((x0, y0), 1), ((x1, y1), -1)):
        d.ellipse([x - 8 * s, y - 8 * s, x + 8 * s, y + 8 * s], fill=c)
        d.ellipse([x - 4 * s - k * 3 * s, y - 4 * s + k * 3 * s, x + 4 * s - k * 3 * s, y + 4 * s + k * 3 * s],
                  fill=bg)


def em_swarm(d, cx, cy, c, sc=1.0):
    """The Swarmer mark: three arrowheads flying together."""
    s = sc
    for ox, oy in ((0, -12), (-14, 10), (14, 10)):
        x, y = cx + ox * s, cy + oy * s
        d.polygon([(x, y - 9 * s), (x + 9 * s, y + 8 * s), (x, y + 3 * s), (x - 9 * s, y + 8 * s)], fill=c)


def em_wings(d, cx, cy, c, ring, sc=1.0):
    """The Interceptor mark: a ring with swept wings."""
    s = sc
    for side in (-1, 1):
        for k in range(3):
            y = cy - 6 * s + k * 6 * s
            d.polygon([(cx + side * 8 * s, y), (cx + side * (34 - k * 7) * s, y - (6 - k) * s),
                       (cx + side * (30 - k * 7) * s, y + 4 * s), (cx + side * 8 * s, y + 5 * s)], fill=c)
    d.ellipse([cx - 10 * s, cy - 10 * s, cx + 10 * s, cy + 10 * s], fill=ring, outline=c, width=3)


def em_hook(d, cx, cy, c, sc=1.0):
    """The Grappler mark: a cargo hook (an eye, the shank and the curve)."""
    s = sc
    d.ellipse([cx - 7 * s, cy - 26 * s, cx + 7 * s, cy - 12 * s], outline=c, width=max(3, int(4 * s)))
    d.line([(cx, cy - 12 * s), (cx, cy + 6 * s)], fill=c, width=int(7 * s))
    d.arc([cx - 18 * s, cy - 8 * s, cx + 2 * s, cy + 22 * s], 0, 200, fill=c, width=int(7 * s))
    d.polygon([(cx - 18 * s, cy + 6 * s), (cx - 22 * s, cy - 4 * s), (cx - 12 * s, cy + 2 * s)], fill=c)


def shield_bearer(v):
    """Shield Bearer: riot armour: a vest of overlapping plates, big rounded shoulder pads, segmented forearm guards,
    knee and shin guards, the shield-wall mark. Veterans are scuffed with stencil bars and chevrons, Elites black
    with gold-edged plates and a bigger mark."""
    suit, trim = {"Grunt": ((52, 60, 78), (230, 190, 60)), "Veteran": ((40, 46, 58), (200, 176, 104)),
                  "Elite": ((20, 22, 32), (255, 212, 80))}[v]
    plate = shade(suit, 1.4)
    sc = 1.35 if v == "Elite" else 1.0
    s, p = T(), T()
    s.torso(suit)
    s.limbs(suit, 0, HAND)
    s.limbs(plate, 0, 22, 1.2, 0.9)  # shoulder pads
    s.limb_band(trim, 22, 26)
    s.limbs(plate, LOWER + 4, HAND - 2, 1.1, 0.9)  # forearm guards in segments
    for k in range(4):
        s.limb_line(plate, LOWER + 14 + k * 10, 0.55, 2)
    s.limbs((34, 36, 44), HAND, 128, 1.0, 0.85)  # padded gloves
    for face in (s.front(), s.back()):
        fx, fy, fw, _ = face
        for k in range(4):  # the vest's plates, each overlapping the one below
            y0 = fy + 14 + k * 21
            s.d.rectangle([fx + 12, y0, fx + 115, y0 + 20], fill=shade(plate, 1.0 - k * 0.05))
            s.d.line([(fx + 12, y0 + 20), (fx + 115, y0 + 20)], fill=shade(suit, 0.5), width=2)
            if v == "Elite":
                s.d.rectangle([fx + 12, y0, fx + 115, y0 + 20], outline=trim, width=1)
        s.d.rectangle([fx + 34, fy, fx + 93, fy + 9], fill=shade(suit, 0.6))  # the neck guard
    fx, fy, _, _ = s.front()
    s.d.rectangle([fx + 38, fy + 22, fx + 89, fy + 76], fill=suit)
    em_wall(s.d, fx + 64, fy + 49, trim, suit, 1.0 if v != "Elite" else 1.12)
    bx, by, _, _ = s.back()
    em_wall(s.d, bx + 64, by + 50, trim, suit, sc)
    if v == "Veteran":
        for k in range(2):  # stencil bars on the chest
            s.d.rectangle([fx + 16, fy + 18 + k * 7, fx + 32, fy + 22 + k * 7], fill=WHITE)
        chevrons(s, 2, trim, 32)
        scuff(s, 11)
    p.torso(suit, UT_PX - 4, 128, 1.0, 0.85)
    for s_ in SIDES4:
        x, y, w, h = TORSO[s_]
        p.d.rectangle([x, y + UT_PX + 4, x + w - 1, y + UT_PX + 14], fill=(26, 26, 30))
    p.d.rectangle([fx + 56, fy + UT_PX + 3, fx + 71, fy + UT_PX + 15], fill=trim)
    p.limbs(suit, 0, HAND)
    for slots in (RIGHT, LEFT):
        x, y, w, h = slots["F"]
        p.d.rounded_rectangle([x + 8, y + LOWER - 10, x + w - 9, y + LOWER + 12], 8, fill=plate,
                              outline=trim if v == "Elite" else shade(plate, 0.6), width=2)  # knee guards
        p.d.rectangle([x + 12, y + LOWER + 16, x + w - 13, y + HAND - 4], fill=shade(plate, 0.92))  # shin guards
        for k in range(3):
            p.d.line([(x + 12, y + LOWER + 26 + k * 10), (x + w - 13, y + LOWER + 26 + k * 10)],
                     fill=shade(plate, 0.6), width=1)
    p.limbs((24, 24, 30), HAND, 128, 1.0, 0.85)
    p.limb_band(DARK, 123, 128)
    if v == "Veteran":
        scuff(p, 12)
    return s.im, p.im


def captain(v):
    """Captain: an officer's tunic: a gold collar, gold epaulettes with fringe, a braided cord looping from the
    shoulder, one row of buttons, cuff rings for rank (one, two, three), a cape down the back, trousers with a double
    gold stripe and tall riding boots, the crest mark. Veterans wear a ribbon bar, Elites hussar braid and white
    gloves."""
    tunic, gold, cape = {"Grunt": ((110, 30, 40), (240, 200, 90), (70, 20, 30)),
                         "Veteran": ((80, 22, 32), (214, 184, 110), (36, 16, 22)),
                         "Elite": ((140, 22, 34), (255, 214, 90), (26, 12, 18))}[v]
    rings = {"Grunt": 1, "Veteran": 2, "Elite": 3}[v]
    s, p = T(), T()
    s.torso(tunic)
    s.limbs(tunic, 0, HAND)
    s.limbs(gold, 0, 10, 1.15, 0.95)  # epaulettes
    for slots in (RIGHT, LEFT):  # their fringe
        for s_ in SIDES4:
            x, y, w, h = slots[s_]
            for xx in range(x + 2, x + w - 1, 5):
                s.d.line([(xx, y + 10), (xx, y + 17)], fill=shade(gold, 0.9), width=2)
    for k in range(rings):
        s.limb_band(gold, HAND - 8 - k * 7, HAND - 4 - k * 7)
    s.limbs(WHITE if v == "Elite" else (34, 28, 30), HAND, 128, 1.0, 0.88)
    fx, fy, fw, _ = s.front()
    if v == "Elite":  # hussar braid across the chest
        for k in range(5):
            y = fy + 26 + k * 13
            s.d.line([(fx + 28, y), (fx + 100, y)], fill=gold, width=3)
            for x in (fx + 28, fx + 100):
                s.d.ellipse([x - 4, y - 4, x + 4, y + 4], outline=gold, width=2)
    s.d.line([(fx + 64, fy + 10), (fx + 64, fy + UT_PX)], fill=shade(tunic, 0.6), width=2)  # the placket
    for k in range(6):
        s.d.ellipse([fx + 60, fy + 18 + k * 14, fx + 68, fy + 26 + k * 14], fill=gold)
    s.d.rectangle([fx + 36, fy, fx + 91, fy + 11], fill=gold)  # the high collar
    s.d.rectangle([fx + 36, fy + 9, fx + 91, fy + 11], fill=shade(gold, 0.7))
    for k in range(2):  # the braided cord looping from the right shoulder
        s.d.arc([fx - 4 + k * 4, fy + 2, fx + 50 - k * 6, fy + 52 - k * 12], 0, 180, fill=gold, width=3)
    if v != "Elite":
        em_crest(s.d, fx + 98, fy + 40, gold, 0.75)
    if v == "Veteran":  # a ribbon bar under the crest
        for k, c in enumerate(((60, 110, 200), WHITE, gold, (40, 140, 90))):
            s.d.rectangle([fx + 82 + k * 8, fy + 58, fx + 89 + k * 8, fy + 64], fill=c)
        scuff(s, 21, 40)
    bx, by, bw, _ = s.back()  # the cape
    panel(s.d, (bx, by, bw, UT_PX), cape, 1.1, 0.85, edge=False)
    for k in range(1, 5):
        s.d.line([(bx + k * 26, by + 14), (bx + k * 26 - 3, by + UT_PX)], fill=shade(cape, 0.65), width=2)
    s.d.rectangle([bx, by, bx + bw - 1, by + 10], fill=gold)
    em_crest(s.d, bx + 64, by + 48, gold if v == "Elite" else shade(cape, 1.8), 1.5 if v == "Elite" else 1.0)
    rx, ry, rw, _ = TORSO["R"]
    lx, ly, lw, _ = TORSO["L"]
    s.d.rectangle([rx, ry, rx + 9, ry + UT_PX], fill=cape)  # the cape's edges on the sides
    s.d.rectangle([lx + lw - 10, ly, lx + lw - 1, ly + UT_PX], fill=cape)
    trousers = (34, 26, 30)
    p.torso(trousers, UT_PX - 4, 128, 1.0, 0.85)
    for s_ in SIDES4:
        x, y, w, h = TORSO[s_]
        p.d.rectangle([x, y + UT_PX + 4, x + w - 1, y + UT_PX + 13], fill=(20, 16, 18))
    p.d.rectangle([fx + 56, fy + UT_PX + 3, fx + 71, fy + UT_PX + 14], fill=gold)
    panel(p.d, (bx, by + UT_PX - 4, bw, 128 - UT_PX + 4), cape, 0.95, 0.8, edge=False)
    p.limbs(trousers, 0, LOWER - 6)
    for slots, outer in ((RIGHT, "R"), (LEFT, "L")):  # the double stripe
        x, y, w, h = slots[outer]
        for dx in (-6, 3):
            p.d.rectangle([x + w // 2 + dx, y, x + w // 2 + dx + 2, y + LOWER - 6], fill=gold)
        x, y, w, h = slots["B"]  # the cape hangs behind the thighs
        panel(p.d, (x, y, w, 40), cape, 0.95, 0.8, edge=False)
        p.d.line([(x, y + 40), (x + w - 1, y + 40)], fill=gold, width=2)
    p.limbs((22, 18, 20), LOWER - 6, 128, 1.25, 0.8)  # tall riding boots
    p.limb_band(shade((22, 18, 20), 1.6), LOWER - 6, LOWER - 2)
    p.limb_band(DARK, 123, 128)
    return s.im, p.im


def sniper(v):
    """Sniper: a camouflage field suit, a neck scarf, a chest rig of long pouches, elbow and knee pads, a thigh
    pocket, the leaf mark (a sleeve patch and the back). Woodland for Grunts, worn urban grey with chevrons for
    Veterans, night camo with a laser-red stripe and a gold leaf for Elites."""
    base, blots, rig, mark = {
        "Grunt": ((60, 75, 55), [(90, 104, 62), (38, 48, 34), (112, 100, 70)], (35, 40, 35), (150, 170, 100)),
        "Veteran": ((112, 108, 96), [(84, 82, 74), (146, 140, 122), (58, 58, 56)], (50, 48, 44), (210, 206, 190)),
        "Elite": ((34, 40, 42), [(56, 66, 66), (18, 20, 24), (78, 86, 84)], (62, 66, 58), GOLD)}[v]
    seed = {"Grunt": 31, "Veteran": 32, "Elite": 33}[v]
    s, p = T(), T()
    s.torso(base)
    s.limbs(base, 0, HAND)
    pattern(s, camo_img(base, blots, seed))
    s.limbs(rig, HAND, 128, 1.0, 0.85)  # gloves
    s.limb_line(rig, HAND - 2, 0.8, 4)
    for slots in (RIGHT, LEFT):  # elbow pads
        x, y, w, h = slots["B"]
        s.d.rounded_rectangle([x + 10, y + LOWER - 8, x + w - 11, y + LOWER + 10], 6, fill=rig)
    if v == "Elite":
        s.outer_stripe((230, 50, 50), 0, HAND, 3)
    fx, fy, fw, _ = s.front()
    s.d.rectangle([fx + 32, fy, fx + 95, fy + 11], fill=shade(blots[0], 0.8))  # the neck scarf
    for sx in (fx + 22, fx + 98):  # rig straps
        s.d.rectangle([sx, fy, sx + 8, fy + 34], fill=rig)
    s.d.rectangle([fx + 14, fy + 34, fx + 113, fy + 66], fill=rig)  # the chest rig
    for k in range(6):  # long round pouches
        px = fx + 18 + k * 16
        s.d.rectangle([px, fy + 38, px + 11, fy + 64], fill=shade(rig, 1.6))
        s.d.rectangle([px, fy + 38, px + 11, fy + 43], fill=GOLD if v == "Elite" else shade(rig, 2.1))
    if v == "Elite":
        s.d.rectangle([fx + 14, fy + 34, fx + 113, fy + 66], outline=GOLD, width=2)
        em_leaf(s.d, fx + 64, fy + 82, GOLD, rig, 0.8)  # a gold leaf under the rig
    bx, by, _, _ = s.back()
    for sx in (bx + 22, bx + 98):
        s.d.rectangle([sx, by, sx + 8, by + 66], fill=rig)
    s.d.rectangle([bx + 54, by + 2, bx + 73, by + 8], fill=rig)  # the drag handle
    em_leaf(s.d, bx + 64, by + 44, mark, rig, 1.5 if v == "Elite" else 1.1)
    x, y, w, h = LEFT["L"]  # the sleeve patch
    s.d.rounded_rectangle([x + 12, y + 10, x + w - 13, y + 40], 5, fill=rig)
    em_leaf(s.d, x + w // 2, y + 25, mark, rig, 0.62)
    if v == "Veteran":
        chevrons(s, 2, mark, 44)
        scuff(s, 34, 50)
    p.torso(base, UT_PX - 4, 128, 1.0, 0.85)
    p.limbs(base, 0, HAND)
    pattern(p, camo_img(base, blots, seed + 10))
    for s_ in SIDES4:
        x, y, w, h = TORSO[s_]
        p.d.rectangle([x, y + UT_PX + 4, x + w - 1, y + UT_PX + 12], fill=rig)
    for slots, outer in ((RIGHT, "R"), (LEFT, "L")):
        x, y, w, h = slots["F"]
        p.d.rounded_rectangle([x + 9, y + LOWER - 6, x + w - 10, y + LOWER + 13], 7, fill=rig)  # knee pads
        x, y, w, h = slots[outer]
        p.d.rectangle([x + 12, y + 14, x + w - 13, y + 40], fill=shade(blots[1], 0.9))  # thigh pocket
        p.d.rectangle([x + 12, y + 14, x + w - 13, y + 20], fill=rig)
    p.limbs(rig, HAND - 6, 128, 1.1, 0.85)  # boots
    p.limb_band(DARK, 123, 128)
    if v == "Veteran":
        scuff(p, 35, 40)
    return s.im, p.im


def bomber(v):
    """Bomber: a demolition worker's quilted jacket, two bandoliers of round charges crossing on the chest, hazard
    striped cuffs, belt and shins, padded gauntlets, the round-bomb mark. Veterans are scorched, Elites black with
    gold charges, hazard shoulders and a bigger mark."""
    jacket, hz = {"Grunt": ((95, 75, 40), (255, 140, 40)), "Veteran": ((72, 58, 36), (230, 118, 30)),
                  "Elite": ((28, 24, 22), (255, 150, 40))}[v]
    charge = GOLD if v == "Elite" else (60, 62, 66)
    leather = (60, 40, 24) if v != "Elite" else (44, 30, 20)
    s, p = T(), T()
    s.torso(jacket)
    s.limbs(jacket, 0, HAND - 12)
    for s_ in SIDES4:  # quilting
        x, y, w, h = TORSO[s_]
        for yy in range(14, UT_PX, 14):
            s.d.line([(x, y + yy), (x + w - 1, y + yy)], fill=shade(jacket, 0.75), width=1)
    for k in range(1, 7):
        s.limb_line(jacket, k * 13, 0.75, 1)
    limb_hazard(s, HAND - 12, HAND, DARK, hz)
    s.limbs(shade(jacket, 0.55), HAND, 128, 1.0, 0.85)  # padded gauntlets
    if v == "Elite":
        limb_hazard(s, 0, 8, DARK, hz)  # hazard shoulders
    fx, fy, fw, _ = s.front()
    bx, by, bw, _ = s.back()
    for x, y in ((fx, fy), (bx, by)):  # the crossed bandoliers
        s.d.polygon([(x + 6, y), (x + 22, y), (x + 122, y + UT_PX - 2), (x + 106, y + UT_PX - 2)], fill=leather)
        s.d.polygon([(x + 122, y), (x + 106, y), (x + 6, y + UT_PX - 2), (x + 22, y + UT_PX - 2)], fill=leather)
        for k in range(1, 8):
            t_ = k / 8
            for ax0, ax1 in ((14, 114), (114, 14)):
                cx, cy = x + ax0 + (ax1 - ax0) * t_, y + UT_PX * t_
                if abs(cx - (x + 64)) < 12:
                    continue
                s.d.ellipse([cx - 5, cy - 5, cx + 5, cy + 5], fill=charge, outline=DARK)
                s.d.rectangle([cx - 2, cy - 7, cx + 2, cy - 4], fill=hz)
    s.d.ellipse([fx + 48, fy + 35, fx + 80, fy + 67], fill=hz, outline=DARK, width=2)  # the crossing buckle
    em_bomb(s.d, fx + 64, fy + 49, DARK, WHITE, 0.55)
    s.d.ellipse([bx + 30, by + 22, bx + 98, by + 90], fill=jacket, outline=hz, width=2)
    em_bomb(s.d, bx + 64, by + 54, hz, GOLD if v == "Elite" else WHITE, 1.35 if v == "Elite" else 1.0)
    if v == "Veteran":
        scuff(s, 41, 30, 0.45)  # scorch marks
        scuff(s, 42, 50)
    pants_c = shade(jacket, 0.85)
    p.torso(pants_c, UT_PX - 4, 128, 1.0, 0.85)
    torso_hazard(p, UT_PX + 2, UT_PX + 14, DARK, hz)
    p.limbs(pants_c, 0, HAND)
    for slots in (RIGHT, LEFT):  # quilted knee pads
        x, y, w, h = slots["F"]
        p.d.rectangle([x + 8, y + LOWER - 10, x + w - 9, y + LOWER + 10], fill=shade(jacket, 0.6))
        for k in range(1, 3):
            p.d.line([(x + 8, y + LOWER - 10 + k * 7), (x + w - 9, y + LOWER - 10 + k * 7)], fill=shade(jacket, 0.4))
    limb_hazard(p, LOWER + 22, LOWER + 32, DARK, hz)
    p.limbs((30, 26, 22), HAND - 4, 128, 1.0, 0.85)
    p.limb_band(DARK, 123, 128)
    if v == "Veteran":
        scuff(p, 43, 30, 0.45)
    return s.im, p.im


def medic(v):
    """Medic Unit: a field medic's tunic: white with a green yoke over the shoulders, a side closure with snaps,
    a pocket of tools, a green armband, green gloves, the green plus in a hexagon (never a red cross). Veterans wear
    a sage tunic with service stripes, Elites gold trim and a wrench behind a bigger mark."""
    coat, green = {"Grunt": ((225, 230, 235), (60, 200, 120)), "Veteran": ((190, 204, 194), (40, 150, 96)),
                   "Elite": ((242, 244, 248), (50, 210, 120))}[v]
    sc = 1.45 if v == "Elite" else 1.1
    s, p = T(), T()
    s.torso(coat)
    s.limbs(coat, 0, HAND)
    s.limbs(green, 0, 14, 1.05, 0.95)  # the yoke over the shoulders
    s.limbs(shade(green, 0.85), HAND, 128, 1.0, 0.9)  # gloves
    s.limb_line(coat, HAND - 3, 0.75, 3)
    fx, fy, fw, _ = s.front()
    bx, by, bw, _ = s.back()
    s.d.rectangle([fx, fy, fx + fw - 1, fy + 16], fill=green)
    s.d.rectangle([bx, by, bx + bw - 1, by + 22], fill=green)
    for s_ in ("R", "L"):
        x, y, w, h = TORSO[s_]
        s.d.rectangle([x, y, x + w - 1, y + 16], fill=green)
    s.d.polygon([(fx + 48, fy), (fx + 64, fy + 12), (fx + 80, fy)], fill=shade(green, 0.7))  # the neckline
    s.d.line([(fx + 90, fy + 16), (fx + 90, fy + UT_PX)], fill=shade(coat, 0.7), width=2)  # side closure
    for k in range(5):
        s.d.ellipse([fx + 93, fy + 24 + k * 16, fx + 98, fy + 29 + k * 16], fill=shade(coat, 0.62))
    s.d.rectangle([fx + 14, fy + 34, fx + 44, fy + 60], fill=shade(coat, 0.9), outline=shade(coat, 0.7))  # pocket
    for k, c in enumerate(((60, 120, 220), STEEL, green)):
        s.d.rectangle([fx + 18 + k * 8, fy + 26, fx + 22 + k * 8, fy + 36], fill=c)  # pens and a screwdriver
    if v == "Elite":  # a bigger gold-ringed chest mark, gold piping on the yoke and cuffs
        s.d.ellipse([fx + 64 - 21, fy + 50 - 21, fx + 64 + 21, fy + 50 + 21], fill=coat, outline=GOLD, width=3)
        em_plus(s.d, fx + 64, fy + 50, green, 0.82)
        s.limb_band(GOLD, 14, 17)
        s.limb_band(GOLD, HAND - 6, HAND - 3)
    else:
        em_plus(s.d, fx + 64, fy + 48, green, 0.7)
    if v == "Elite":
        s.d.line([(fx, fy + 16), (fx + 127, fy + 16)], fill=GOLD, width=3)
        s.d.line([(bx, by + 22), (bx + 127, by + 22)], fill=GOLD, width=3)
        em_wrench(s.d, bx + 64, by + 60, GOLD, coat, 30, 1.0)
    s.d.ellipse([bx + 64 - 26 * sc, by + 60 - 26 * sc, bx + 64 + 26 * sc, by + 60 + 26 * sc], fill=coat)
    em_plus(s.d, bx + 64, by + 60, green, sc)
    if v == "Elite":
        s.d.ellipse([bx + 64 - 27 * sc, by + 60 - 27 * sc, bx + 64 + 27 * sc, by + 60 + 27 * sc], outline=GOLD,
                    width=2)
    for s_ in SIDES4:  # the green armband on the left arm, with a white plus on its outer side
        x, y, w, h = LEFT[s_]
        s.d.rectangle([x, y + 24, x + w - 1, y + 40], fill=green)
    x, y, w, h = LEFT["L"]
    s.d.rectangle([x + w // 2 - 2, y + 26, x + w // 2 + 2, y + 38], fill=coat)
    s.d.rectangle([x + w // 2 - 6, y + 30, x + w // 2 + 6, y + 34], fill=coat)
    if v == "Veteran":
        x, y, w, h = RIGHT["R"]
        for k in range(3):  # service stripes on the right forearm
            s.d.line([(x + 10, y + LOWER + 30 + k * 7), (x + w - 10, y + LOWER + 24 + k * 7)], fill=green, width=3)
        scuff(s, 51, 40, 0.86)
    p.torso(coat, UT_PX - 4, 128, 1.0, 0.85)
    for s_ in SIDES4:
        x, y, w, h = TORSO[s_]
        p.d.rectangle([x, y + UT_PX + 4, x + w - 1, y + UT_PX + 12], fill=shade(green, 0.7))
    p.limbs(coat, 0, HAND)
    p.outer_stripe(green, 0, HAND, 6)
    for slots, outer in ((RIGHT, "F"), (LEFT, "F")):  # cargo pockets
        x, y, w, h = slots[outer]
        p.d.rectangle([x + 10, y + 20, x + w - 11, y + 46], fill=shade(coat, 0.9), outline=shade(coat, 0.7))
    p.limbs(WHITE, HAND, 128, 1.0, 0.85)  # white shoes with green soles
    p.limb_band(green if v != "Elite" else GOLD, 123, 128)
    if v == "Veteran":
        scuff(p, 52, 30, 0.86)
    return s.im, p.im


def swarmer(v):
    """Swarmer: a small fast robot's runner kit: a hive-patterned short-sleeve top with a bright V down the chest,
    shorts over bare knees, long striped socks, light shoes, the swarm mark. Veterans run in black with a red
    armband, Elites with gold edging and a bigger mark."""
    top, lime = {"Grunt": ((70, 90, 30), (200, 255, 60)), "Veteran": ((36, 42, 28), (170, 220, 60)),
                 "Elite": ((22, 26, 14), (220, 255, 80))}[v]
    edge = GOLD if v == "Elite" else shade(lime, 0.7)
    s, p = T(), T()
    s.torso(top)
    s.limbs(top, 0, 28)  # short sleeves; the arms are bare below
    pattern(s, hex_img(top, shade(lime, 0.6) if v == "Elite" else shade(top, 1.45)))  # Elites' cells glow lime
    s.limb_band(lime, 24, 29)
    fx, fy, fw, _ = s.front()
    bx, by, bw, _ = s.back()
    for x, y in ((fx, fy), (bx, by)):  # the V
        s.d.polygon([(x + 18, y), (x + 36, y), (x + 64, y + 52), (x + 92, y), (x + 110, y), (x + 64, y + 76)],
                    fill=lime)
        s.d.line([(x + 18, y), (x + 64, y + 76), (x + 110, y)], fill=edge, width=3 if v == "Elite" else 2)
        if v == "Elite":
            s.d.line([(x + 36, y), (x + 64, y + 52), (x + 92, y)], fill=edge, width=3)
    em_swarm(s.d, fx + 64, fy + 86, lime, 0.6)
    em_swarm(s.d, bx + 64, by + 22, top, 0.9 if v != "Elite" else 1.1)
    s.limbs((40, 40, 44), HAND, 128, 1.0, 0.9)  # light grip gloves
    s.limb_band(lime, HAND, HAND + 3)
    if v == "Veteran":
        for s_ in SIDES4:
            x, y, w, h = LEFT[s_]
            s.d.rectangle([x, y + 8, x + w - 1, y + 18], fill=(200, 60, 50))
        scuff(s, 61, 40)
    shorts = shade(top, 0.8)
    p.torso(shorts, UT_PX - 4, 128, 1.0, 0.85)
    for s_ in SIDES4:
        x, y, w, h = TORSO[s_]
        p.d.rectangle([x, y + UT_PX + 3, x + w - 1, y + UT_PX + 8], fill=lime)
    p.limbs(shorts, 0, 32)  # shorts, then bare knees
    p.outer_stripe(lime, 0, 32, 6)
    p.limb_line(shorts, 31, 0.6, 2)
    p.limbs(WHITE if v != "Elite" else (30, 30, 30), LOWER + 8, HAND, 1.0, 0.92)  # long socks
    for k in range(3):
        p.limb_band(lime if k != 1 else top, LOWER + 10 + k * 6, LOWER + 13 + k * 6)
    p.limbs(lime, HAND, 128, 1.05, 0.85)  # light shoes
    p.limb_band(WHITE, 122, 128)
    if v == "Elite":
        p.limb_band(GOLD, HAND, HAND + 3)
    return s.im, p.im


def mimic(v):
    """Mimic: an ordinary citizen's street clothes, no robot mark and no trim (it passes for a civilian until it
    springs), so the versions are just different outfits: a tee and jeans, a flannel shirt and chinos, a zip hoodie
    and joggers."""
    s, p = T(), T()
    fx, fy, fw, _ = s.front()
    bx, by, bw, _ = s.back()
    if v == "Grunt":
        tee, jeans = (70, 110, 160), (58, 80, 120)
        s.torso(tee)
        s.limbs(tee, 0, 30)  # short sleeves
        s.limb_line(tee, 29, 0.75, 2)
        s.d.arc([fx + 40, fy - 16, fx + 88, fy + 12], 0, 180, fill=shade(tee, 0.7), width=3)  # crew neck
        s.d.rectangle([fx + 84, fy + 26, fx + 104, fy + 46], outline=shade(tee, 0.75), width=2)  # a chest pocket
        p.torso(jeans, UT_PX - 4, 128, 1.0, 0.85)
        for s_ in SIDES4:
            x, y, w, h = TORSO[s_]
            p.d.rectangle([x, y + UT_PX + 2, x + w - 1, y + UT_PX + 9], fill=(92, 60, 36))  # a brown belt
        p.d.rectangle([fx + 58, fy + UT_PX + 1, fx + 69, fy + UT_PX + 10], fill=(180, 180, 176))
        p.limbs(jeans, 0, HAND)
        for slots in (RIGHT, LEFT):
            for s_ in SIDES4:
                x, y, w, h = slots[s_]
                p.d.line([(x + w // 2, y), (x + w // 2, y + HAND)], fill=shade(jeans, 0.82))  # seams
                for yy in range(4, HAND, 6):
                    p.d.point((x + w // 2 + 2, y + yy), fill=(190, 150, 80))  # the stitching
        p.limb_band(shade(jeans, 0.7), HAND - 4, HAND)  # the turned-up hem
        p.limbs((190, 190, 196), HAND, 128, 1.0, 0.88)  # grey sneakers
        p.limb_band(WHITE, 122, 128)
    elif v == "Veteran":
        red = (150, 44, 44)
        s.torso(red)
        s.limbs(red, 0, LOWER + 8)  # sleeves rolled to the elbow
        pattern(s, plaid_img(red, (40, 18, 20), (220, 200, 170)))
        s.limb_band(shade(red, 0.7), LOWER + 2, LOWER + 9)  # the roll
        s.d.polygon([(fx + 36, fy), (fx + 64, fy + 16), (fx + 92, fy), (fx + 82, fy), (fx + 64, fy + 8),
                     (fx + 46, fy)], fill=shade(red, 0.6))  # the collar
        s.d.line([(fx + 64, fy + 16), (fx + 64, fy + UT_PX)], fill=shade(red, 0.5), width=2)
        for k in range(5):
            s.d.ellipse([fx + 61, fy + 24 + k * 16, fx + 67, fy + 30 + k * 16], fill=(230, 224, 210))
        for px in (fx + 22, fx + 80):
            s.d.rectangle([px, fy + 28, px + 26, fy + 34], fill=shade(red, 0.6))  # pocket flaps
        khaki = (176, 150, 110)
        p.torso(khaki, UT_PX - 4, 128, 1.0, 0.85)
        for s_ in SIDES4:
            x, y, w, h = TORSO[s_]
            p.d.rectangle([x, y + UT_PX + 2, x + w - 1, y + UT_PX + 9], fill=(60, 40, 28))
        p.limbs(khaki, 0, HAND)
        for slots in (RIGHT, LEFT):
            x, y, w, h = slots["F"]
            p.d.line([(x + w // 2, y), (x + w // 2, y + HAND)], fill=shade(khaki, 0.85))  # the crease
        p.limbs((96, 62, 40), HAND, 128, 1.0, 0.85)  # brown shoes
        p.limb_band((40, 30, 24), 123, 128)
    else:
        hood = (128, 132, 138)
        s.torso(hood)
        s.limbs(hood, 0, HAND)
        s.limb_band(shade(hood, 0.78), HAND - 8, HAND)  # ribbed cuffs
        s.d.line([(fx + 64, fy + 6), (fx + 64, fy + UT_PX)], fill=(70, 72, 78), width=3)  # the zip
        s.d.rectangle([fx + 61, fy + 6, fx + 67, fy + 14], fill=(200, 200, 204))
        for dx in (-12, 12):  # drawstrings
            s.d.line([(fx + 64 + dx, fy + 4), (fx + 64 + dx, fy + 32)], fill=WHITE, width=2)
        s.d.polygon([(fx + 20, fy + 66), (fx + 108, fy + 66), (fx + 118, fy + UT_PX - 8), (fx + 10, fy + UT_PX - 8)],
                    outline=shade(hood, 0.7))  # the pocket
        s.d.arc([bx + 20, by - 40, bx + 108, by + 40], 0, 180, fill=shade(hood, 0.7), width=3)  # the hood, down
        s.d.rectangle([fx, fy + UT_PX - 8, fx + fw - 1, fy + UT_PX], fill=shade(hood, 0.8))  # the waistband
        s.d.rectangle([bx, by + UT_PX - 8, bx + bw - 1, by + UT_PX], fill=shade(hood, 0.8))
        jog = (44, 48, 56)
        p.torso(jog, UT_PX - 4, 128, 1.0, 0.85)
        for s_ in SIDES4:
            x, y, w, h = TORSO[s_]
            p.d.rectangle([x, y + UT_PX + 2, x + w - 1, y + UT_PX + 8], fill=shade(jog, 0.8))
        p.limbs(jog, 0, HAND)
        p.outer_stripe((170, 172, 178), 0, HAND - 8, 4)
        p.limb_band(shade(jog, 0.75), HAND - 8, HAND)  # cuffed ankles
        p.limbs(WHITE, HAND, 128, 1.0, 0.88)  # white sneakers
        p.limb_band((170, 172, 178), 122, 128)
    return s.im, p.im


def interceptor(v):
    """Interceptor: a jet pilot's flight suit: blue side panels, a V harness to a round quick-release buckle, swept
    wings across the back and the backs of the arms, the winged-ring mark, g-suit thigh pockets and leg loops,
    flight boots. Veterans fly in grey with mission patches, Elites in white with gold."""
    suit, blue = {"Grunt": ((200, 205, 215), (40, 120, 220)), "Veteran": ((140, 146, 156), (30, 80, 170)),
                  "Elite": ((238, 240, 246), (40, 140, 255))}[v]
    gold = GOLD if v == "Elite" else WHITE
    strap = (40, 44, 54)
    s, p = T(), T()
    s.torso(suit)
    s.limbs(suit, 0, HAND)
    s.torso_sides_stripe(blue, 0, UT_PX, 22)
    s.outer_stripe(blue, 0, HAND, 14)
    s.limbs((26, 30, 46), HAND, 128, 1.0, 0.88)  # flight gloves
    s.limb_band(blue, HAND - 5, HAND)
    fx, fy, fw, _ = s.front()
    bx, by, bw, _ = s.back()
    s.d.rectangle([fx + 38, fy, fx + 89, fy + 7], fill=gold if v == "Elite" else blue)  # the neck ring
    if v == "Elite":  # gold piping along the blue panels
        for s_ in ("R", "L"):
            x, y, w, h = TORSO[s_]
            for dx in (-12, 11):
                s.d.line([(x + w // 2 + dx, y), (x + w // 2 + dx, y + UT_PX)], fill=GOLD, width=2)
        s.d.rectangle([fx, fy + UT_PX - 6, fx + 127, fy + UT_PX], fill=GOLD)
    s.d.polygon([(fx + 24, fy), (fx + 36, fy), (fx + 68, fy + 58), (fx + 60, fy + 64)], fill=strap)  # V harness
    s.d.polygon([(fx + 104, fy), (fx + 92, fy), (fx + 60, fy + 58), (fx + 68, fy + 64)], fill=strap)
    s.d.rectangle([fx + 59, fy + 60, fx + 69, fy + UT_PX], fill=strap)
    s.d.ellipse([fx + 52, fy + 50, fx + 76, fy + 74], fill=gold if v == "Elite" else STEEL, outline=DARK, width=2)
    s.d.ellipse([fx + 59, fy + 57, fx + 69, fy + 67], fill=blue)
    if v == "Elite":
        em_wings(s.d, fx + 30, fy + 80, GOLD, blue, 0.62)
    else:
        em_wings(s.d, fx + 30, fy + 84, blue, gold, 0.5)  # the small mark low on the right
    for side in (-1, 1):  # wings across the back
        for k in range(4):
            yy = by + 18 + k * 14
            tip = 58 - k * 9
            s.d.polygon([(bx + 64, yy), (bx + 64 + side * tip, yy - 10 + k * 2), (bx + 64 + side * (tip - 8), yy + 6),
                         (bx + 64, yy + 10)], fill=blue if k % 2 == 0 else shade(blue, 1.25),
                        outline=gold if v == "Elite" else None)
    s.d.ellipse([bx + 54, by + 14, bx + 74, by + 34], fill=gold, outline=blue, width=3)
    if v == "Elite":
        em_wings(s.d, bx + 64, by + 86, GOLD, blue, 0.75)
    for slots in (RIGHT, LEFT):  # the wings carry on down the backs of the arms
        x, y, w, h = slots["B"]
        for k in range(3):
            yy = y + 10 + k * 12
            s.d.polygon([(x + 6, yy), (x + w - 6, yy + 4), (x + w // 2, yy + 12)], fill=blue)
    x, y, w, h = LEFT["L"]  # the sleeve mark
    em_wings(s.d, x + w // 2, y + 26, blue if v == "Grunt" else gold, suit, 0.7)
    x, y, w, h = RIGHT["R"]  # a sleeve pocket
    s.d.rectangle([x + 16, y + LOWER + 4, x + w - 17, y + LOWER + 24], fill=shade(suit, 0.85), outline=strap)
    if v == "Veteran":  # mission patches
        for px, py, c in ((fx + 90, fy + 78, (200, 70, 60)), (fx + 108, fy + 78, (230, 190, 60)),
                          (fx + 99, fy + 92, (60, 160, 90))):
            s.d.ellipse([px - 6, py - 6, px + 6, py + 6], fill=c, outline=DARK)
        scuff(s, 81, 50)
    p.torso(suit, UT_PX - 4, 128, 1.0, 0.85)
    for s_ in SIDES4:
        x, y, w, h = TORSO[s_]
        p.d.rectangle([x, y + UT_PX + 4, x + w - 1, y + UT_PX + 12], fill=strap)
    p.limbs(suit, 0, HAND)
    p.outer_stripe(blue, 0, HAND, 14)
    p.limb_band(strap, 4, 10)  # the harness's leg loops
    for slots in (RIGHT, LEFT):  # g-suit thigh pockets
        x, y, w, h = slots["F"]
        p.d.rectangle([x + 10, y + 16, x + w - 11, y + 46], fill=shade(suit, 0.86), outline=shade(suit, 0.65))
        p.d.rectangle([x + 10, y + 16, x + w - 11, y + 22], fill=blue)
    p.limbs((30, 32, 42), HAND - 10, 128, 1.1, 0.85)  # flight boots
    p.limb_band(blue if v != "Elite" else GOLD, HAND - 10, HAND - 7)
    p.limb_band(DARK, 123, 128)
    if v == "Veteran":
        scuff(p, 82, 40)
    return s.im, p.im


def grappler(v):
    """Grappler: heavy hauling gear: a thick work jacket whose right sleeve is armoured in riveted plates with a
    chain wound round the forearm (the hook arm), the left sleeve rolled up (bare forearm), a broad yoke, a chain
    slung across the chest, the hook mark on a riveted plate, padded trousers with plated knees, a chain belt,
    steel-toe boots. Veterans are grey and worn with arm bands, Elites black with gold chains and a bigger mark."""
    jacket, orange = {"Grunt": ((70, 55, 45), (200, 120, 50)), "Veteran": ((58, 56, 54), (186, 108, 44)),
                      "Elite": ((24, 20, 18), (232, 190, 80))}[v]
    steel = (150, 154, 162) if v != "Elite" else GOLD
    s, p = T(), T()
    s.torso(jacket)
    fx, fy, fw, _ = s.front()
    bx, by, bw, _ = s.back()
    for s_ in SIDES4:  # the right sleeve: armour plates, joints and rivets, the chain round the forearm
        x, y, w, h = RIGHT[s_]
        for k in range(0, HAND, 15):
            panel(s.d, (x, y + k, w, min(13, HAND - k)), orange, 1.15, 0.8, edge=False)
            if k + 14 >= HAND:
                continue
            s.d.rectangle([x, y + k + 13, x + w - 1, y + k + 14], fill=DARK)
            for rx in (x + 6, x + w - 9):
                s.d.ellipse([rx, y + k + 4, rx + 3, y + k + 7], fill=shade(orange, 0.55))
        for cy in (LOWER + 16, LOWER + 34):
            chain(s.d, (x + 2, y + cy), (x + w - 3, y + cy + 6), steel)
        panel(s.d, (x, y + HAND, w, 128 - HAND), shade(orange, 0.75), 1.1, 0.8, edge=False)  # the gauntlet
    panel(s.d, RIGHT["U"], orange, 1.1, 0.9, edge=False)
    panel(s.d, RIGHT["D"], shade(orange, 0.75), 0.9, 0.8, edge=False)
    for s_ in SIDES4:  # the left sleeve, rolled
        x, y, w, h = LEFT[s_]
        panel(s.d, (x, y, w, 30), jacket, 1.06, 0.88, edge=False)
        s.d.rectangle([x, y + 26, x + w - 1, y + 33], fill=shade(jacket, 1.3))
        panel(s.d, (x, y + HAND, w, 128 - HAND), (60, 44, 32), 1.0, 0.85, edge=False)  # a leather glove
    panel(s.d, LEFT["U"], jacket, 1.12, 1.0, edge=False)
    panel(s.d, LEFT["D"], (60, 44, 32), 0.9, 0.8, edge=False)
    for x, y in ((fx, fy), (bx, by)):  # the broad yoke
        s.d.rectangle([x, y, x + 127, y + 14], fill=orange)
        s.d.line([(x, y + 14), (x + 127, y + 14)], fill=DARK, width=2)
    for s_ in ("R", "L"):
        x, y, w, h = TORSO[s_]
        s.d.rectangle([x, y, x + w - 1, y + 14], fill=orange)
    chain(s.d, (fx + 6, fy + 18), (fx + 120, fy + 98), steel, 11)  # slung across the chest
    chain(s.d, (bx + 122, by + 18), (bx + 8, by + 98), steel, 11)
    sc = 1.3 if v == "Elite" else 1.0
    s.d.ellipse([fx + 64 - 22, fy + 26, fx + 64 + 22, fy + 70], fill=STEEL if v != "Elite" else (40, 36, 30),
                outline=DARK, width=2)
    for a in range(0, 360, 60):
        rx, ry = fx + 64 + 18 * math.cos(math.radians(a)), fy + 48 + 18 * math.sin(math.radians(a))
        s.d.ellipse([rx - 2, ry - 2, rx + 2, ry + 2], fill=DARK)
    em_hook(s.d, fx + 68, fy + 50, orange, 0.62)
    s.d.ellipse([bx + 64 - 30 * sc, by + 56 - 30 * sc, bx + 64 + 30 * sc, by + 56 + 30 * sc], fill=jacket,
                outline=orange, width=3)
    em_hook(s.d, bx + 68, by + 58, orange, 0.95 * sc)
    if v == "Veteran":
        for k in range(2):
            for s_ in SIDES4:
                x, y, w, h = LEFT[s_]
                s.d.rectangle([x, y + 8 + k * 7, x + w - 1, y + 12 + k * 7], fill=orange)
        scuff(s, 91, 70)
    pants_c = shade(jacket, 0.85)
    p.torso(pants_c, UT_PX - 4, 128, 1.0, 0.85)
    for s_ in SIDES4:  # the chain belt
        x, y, w, h = TORSO[s_]
        p.d.rectangle([x, y + UT_PX + 3, x + w - 1, y + UT_PX + 13], fill=(30, 26, 22))
        chain(p.d, (x + 3, y + UT_PX + 8), (x + w - 4, y + UT_PX + 8), steel, 8)
    p.limbs(pants_c, 0, HAND)
    for k in range(1, 4):
        p.limb_line(pants_c, k * 12, 0.75, 1)  # padding
    for slots in (RIGHT, LEFT):  # plated knees
        x, y, w, h = slots["F"]
        p.d.polygon([(x + 10, y + LOWER - 8), (x + w - 11, y + LOWER - 8), (x + w - 14, y + LOWER + 14),
                     (x + w // 2, y + LOWER + 20), (x + 13, y + LOWER + 14)], fill=orange, outline=DARK)
    p.limbs((36, 30, 26), HAND - 8, 128, 1.05, 0.85)  # boots
    for slots in (RIGHT, LEFT):
        x, y, w, h = slots["F"]
        p.d.rectangle([x + 4, y + HAND + 4, x + w - 5, y + 122], fill=steel)  # the steel toe
    p.limb_band(DARK, 123, 128)
    if v == "Veteran":
        scuff(p, 92, 50)
    return s.im, p.im


def key_plate(d, cx, cy, sc=1.0):
    """The wind-up key's brass plate on a toy's back (the Toymaker's toys): a round plate, the shaft and two bows."""
    r = int(16 * sc)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(205, 160, 70), outline=DARK, width=2)
    d.rectangle([cx - 3, cy - r - 14, cx + 3, cy], fill=(180, 135, 55), outline=DARK)
    for k in (-1, 1):
        bx = cx + k * int(13 * sc)
        d.ellipse([bx - int(10 * sc), cy - r - 30, bx + int(10 * sc), cy - r - 10], fill=(225, 185, 85),
                  outline=DARK, width=2)


def windup_toy(v):
    """Wind-Up Toy (lore step 11, the Suburbs chain): the Toymaker's clockwork toys, one toy per version.
    Grunt: a tin soldier (red coat, white cross belts, brass buttons, navy trousers with a red stripe, black
    boots). Veteran: a lawn gnome (blue smock, a white beard bib, brown belt, red mittens and boots). Elite: a
    patchwork plush bear (tan fur, stitched patches, a light belly, a big red bow, paw pads). The key plate on
    every back."""
    s, p = T(), T()
    fx, fy, fw, _ = s.front()
    bx, by, bw, _ = s.back()
    if v == "Grunt":
        coat, gold = (200, 40, 50), GOLD
        s.torso(coat)
        s.limbs(coat, 0, HAND)
        s.limb_band(gold, HAND - 6, HAND)  # gold cuffs
        s.limbs(WHITE, HAND, 128, 1.0, 0.9)  # white gloves
        for a, b in (((fx + 8, fy), (fx + 120, fy + 100)), ((fx + 120, fy), (fx + 8, fy + 100))):
            s.d.line([a, b], fill=WHITE, width=12)  # the cross belts
        for k in range(4):
            s.d.ellipse([fx + 60, fy + 12 + k * 22, fx + 68, fy + 20 + k * 22], fill=gold, outline=DARK)
        s.d.rectangle([fx, fy + UT_PX - 10, fx + 127, fy + UT_PX], fill=DARK)
        trousers = (30, 45, 120)
        p.torso(trousers, UT_PX - 4, 128, 1.0, 0.85)
        p.limbs(trousers, 0, HAND - 10)
        p.outer_stripe(coat, 0, HAND - 10, 6)
        p.limbs((24, 24, 28), HAND - 10, 128, 1.1, 0.8)  # black boots
    elif v == "Veteran":
        smock, red = (60, 110, 220), (220, 50, 50)
        s.torso(smock)
        s.limbs(smock, 0, HAND)
        s.limbs(red, HAND, 128, 1.05, 0.9)  # red mittens
        s.d.polygon([(fx + 22, fy), (fx + 106, fy), (fx + 96, fy + 46), (fx + 64, fy + 80), (fx + 32, fy + 46)],
                    fill=WHITE, outline=shade(WHITE, 0.75))  # the beard bib
        for k in range(5):
            s.d.arc([fx + 30 + k * 14, fy + 30, fx + 44 + k * 14, fy + 44], 0, 180, fill=shade(WHITE, 0.8), width=2)
        s.d.rectangle([fx, fy + 86, fx + 127, fy + 98], fill=(110, 70, 40))
        s.d.rectangle([fx + 56, fy + 84, fx + 72, fy + 100], fill=GOLD, outline=DARK)
        trousers = (110, 70, 40)
        p.torso(trousers, UT_PX - 4, 128, 1.0, 0.85)
        p.limbs(trousers, 0, HAND - 8)
        p.limbs(red, HAND - 8, 128, 1.1, 0.8)  # red boots
    else:
        fur, belly = (170, 120, 70), (230, 200, 150)
        s.torso(fur)
        s.limbs(fur, 0, 128)
        s.d.ellipse([fx + 24, fy + 30, fx + 104, fy + 110], fill=belly, outline=shade(fur, 0.6), width=2)
        rng = random.Random(77)
        areas = [TORSO["F"], TORSO["B"], RIGHT["F"], LEFT["F"], RIGHT["B"], LEFT["B"]]
        for x, y, w, h in areas:  # stitched patches in bright fabric
            for _ in range(2):
                pw, ph = rng.randint(20, 30), rng.randint(20, 30)
                px, py = x + rng.randint(4, w - pw - 4), y + rng.randint(4, h - ph - 4)
                col = rng.choice([(90, 160, 220), (230, 110, 160), (120, 190, 90), (240, 200, 80)])
                s.d.rectangle([px, py, px + pw, py + ph], fill=col, outline=shade(col, 0.7))
                for k in range(px + 2, px + pw - 1, 5):  # cross stitches along the top and bottom
                    for yy in (py, py + ph):
                        s.d.line([(k - 2, yy - 2), (k + 2, yy + 2)], fill=DARK, width=1)
                        s.d.line([(k + 2, yy - 2), (k - 2, yy + 2)], fill=DARK, width=1)
        s.d.polygon([(fx + 64, fy + 10), (fx + 30, fy - 2 + 2), (fx + 30, fy + 22)], fill=(220, 40, 50))  # the bow
        s.d.polygon([(fx + 64, fy + 10), (fx + 98, fy), (fx + 98, fy + 22)], fill=(220, 40, 50))
        s.d.ellipse([fx + 58, fy + 4, fx + 70, fy + 16], fill=(180, 30, 40))
        s.limbs(belly, HAND, 128, 1.0, 0.9)  # paw pads
        p.torso(fur, UT_PX - 4, 128, 1.0, 0.85)
        p.limbs(fur, 0, 128)
        p.limbs(belly, HAND, 128, 1.0, 0.9)
    key_plate(s.d, bx + 64, by + 70, 1.0)
    return s.im, p.im


def toy_drum(d, x, y, w, h, shell, cord, rim):
    """A toy drum filling a face: brass-studded rims top and bottom, the shell between them laced with a zigzag
    cord (the Wind-Up Giant's chest is its drum)."""
    d.rectangle([x, y, x + w - 1, y + h - 1], fill=shell)
    rh = max(8, h // 9)
    for yy in (y, y + h - rh):
        d.rectangle([x, yy, x + w - 1, yy + rh - 1], fill=rim, outline=DARK)
        for k in range(x + 6, x + w - 4, 14):
            d.ellipse([k - 2, yy + rh // 2 - 2, k + 2, yy + rh // 2 + 2], fill=shade(rim, 1.25))
    top, bot = y + rh, y + h - rh
    n = max(3, w // 16)  # many laces, so it reads as a drum and not as letters
    pts = []
    for i in range(n * 2 + 1):
        pts.append((x + w * i / (n * 2), top if i % 2 == 0 else bot))
    d.line(pts, fill=cord, width=6, joint="curve")
    d.line([(px, py + (2 if py == top else -2)) for px, py in pts], fill=shade(cord, 0.7), width=1)


def windup_giant(v):
    """Wind-Up Giant (lore step 11, the Suburbs chain's finale): the Toymaker's giant clockwork drummer, so it never
    reads as one of its own tin soldiers. Its chest is a toy drum (a white shell laced with a zigzag cord between
    brass-studded rims) under gold fringed epaulettes, the coat colour on the sleeves and sides with gold cuffs and
    white gloves, two drumsticks crossed over the big key plate on the back, white (or black) trousers with a
    stripe and black boots with a gold band. Grunt red, Veteran royal blue (worn), Elite white and gold."""
    coat, braid, cord = {"Grunt": ((190, 35, 45), GOLD, (190, 35, 45)), "Veteran": ((40, 70, 170), GOLD, (220, 40, 50)),
                         "Elite": ((235, 230, 215), (210, 160, 50), (30, 50, 140))}[v]
    s, p = T(), T()
    fx, fy, fw, _ = s.front()
    bx, by, bw, _ = s.back()
    s.torso(coat)
    s.limbs(coat, 0, HAND)
    s.limb_band(braid, HAND - 8, HAND)
    s.limbs(WHITE, HAND, 128, 1.0, 0.9)
    shell = WHITE if v != "Elite" else (250, 250, 245)
    toy_drum(s.d, fx + 6, fy + 18, fw - 12, 76, shell, cord, braid)
    # the drum's strap over the shoulders and the gold fringed epaulettes
    for x in (fx + 22, fx + 98):
        s.d.rectangle([x, fy, x + 8, fy + 18], fill=braid, outline=DARK)
    for slots in (RIGHT, LEFT):
        ux, uy, uw, uh = slots["U"]
        s.d.rectangle([ux, uy, ux + uw - 1, uy + uh - 1], fill=braid)
        for sd in SIDES4:
            x, y, w, _ = slots[sd]
            s.d.rectangle([x, y, x + w - 1, y + 8], fill=braid)
            for k in range(x + 2, x + w - 2, 6):
                s.d.line([(k, y + 8), (k, y + 16)], fill=shade(braid, 0.85), width=3)
    # the back: two drumsticks crossed over the big key plate
    for a, b in (((bx + 22, by + 20), (bx + 104, by + 100)), ((bx + 104, by + 20), (bx + 22, by + 100))):
        s.d.line([a, b], fill=(225, 205, 160), width=8)
        s.d.ellipse([b[0] - 8, b[1] - 8, b[0] + 8, b[1] + 8], fill=(240, 230, 210), outline=DARK)
    key_plate(s.d, bx + 64, by + 72, 1.4)
    trousers = WHITE if v != "Elite" else (40, 40, 48)
    p.torso(trousers, UT_PX - 4, 128, 1.0, 0.85)
    p.limbs(trousers, 0, HAND - 12)
    p.outer_stripe(coat if v != "Elite" else braid, 0, HAND - 12, 8)
    p.limbs((24, 24, 28), HAND - 12, 128, 1.1, 0.8)
    p.limb_band(braid, HAND - 12, HAND - 8)
    if v == "Veteran":
        scuff(s, 131, 50)
    return s.im, p.im


def em_crossed_hooks(d, cx, cy, c, sc=1.0):
    """The Salt Dogs' crew patch (the Coast chain): two hooks crossed under a round porthole (an original mark)."""
    s = sc
    r = int(12 * s)
    d.ellipse([cx - r, cy - 30 * s - r, cx + r, cy - 30 * s + r], outline=c, width=max(3, int(4 * s)))
    for k in (-1, 1):
        d.line([(cx - k * 18 * s, cy - 14 * s), (cx + k * 14 * s, cy + 16 * s)], fill=c, width=int(6 * s))
        d.arc([cx + k * 14 * s - 9 * s, cy + 8 * s, cx + k * 14 * s + 9 * s, cy + 26 * s],
              0 if k > 0 else 180, 180 if k > 0 else 360, fill=c, width=int(5 * s))


def neckerchief(d, fx, fy, c):
    """The Salt Dogs' red neckerchief: a triangle hanging from the collar with its knot (the crew's mark, with the
    red bandana on the head)."""
    d.polygon([(fx + 38, fy), (fx + 90, fy), (fx + 64, fy + 34)], fill=c, outline=shade(c, 0.65))
    d.line([(fx + 50, fy + 6), (fx + 64, fy + 26), (fx + 78, fy + 6)], fill=shade(c, 0.75), width=2)
    d.ellipse([fx + 57, fy + 2, fx + 71, fy + 14], fill=shade(c, 0.85), outline=shade(c, 0.6))


def salt_dog(v):
    """Salt Dog (lore step 11, the Coast chain): Captain Brine's robot crew, one rank per version, each with the
    crew's red neckerchief (Grunt and Veteran) and the crossed-hooks patch on the back. Grunt: a deckhand's striped
    jersey (navy and white) with a rope belt and rolled canvas trousers. Veteran: a gunner's navy pea coat, two rows
    of brass buttons, a leather cutlass strap across the chest and a wide belt with a big brass buckle, grey
    trousers, worn. Elite: the bosun's long red coat worn open over the crew's striped jersey, gold braid at the
    cuffs and on the coat's edges, the whistle chain, black trousers with a gold stripe. Rust on the veterans."""
    s, p = T(), T()
    fx, fy, fw, _ = s.front()
    bx, by, bw, _ = s.back()
    navy, rope, kerchief = (30, 45, 100), (200, 170, 110), (205, 40, 40)
    leather = (110, 70, 40)
    if v == "Grunt":
        s.torso(WHITE)
        s.limbs(WHITE, 0, LOWER)
        s.hstripes(navy, 0, UT_PX, period=16, wd=7, limbs_to=LOWER)
        s.d.rectangle([fx, fy + UT_PX - 12, fx + 127, fy + UT_PX - 2], fill=rope)  # the rope belt
        for k in range(0, 128, 8):
            s.d.line([(fx + k, fy + UT_PX - 12), (fx + k + 6, fy + UT_PX - 2)], fill=shade(rope, 0.7), width=2)
        neckerchief(s.d, fx, fy, kerchief)
        trousers = (190, 175, 140)
        p.torso(trousers, UT_PX - 4, 128, 1.0, 0.85)
        p.limbs(trousers, 0, HAND - 14)
        p.limb_band(shade(trousers, 0.8), HAND - 22, HAND - 14)  # rolled cuffs
        p.limbs((60, 45, 35), HAND - 14, 128, 1.1, 0.8)  # sea boots
        patch = navy
    elif v == "Veteran":
        s.torso(navy)
        s.limbs(navy, 0, HAND)
        s.d.polygon([(fx + 30, fy), (fx + 64, fy + 30), (fx + 98, fy)], fill=shade(navy, 1.4))  # the lapels
        neckerchief(s.d, fx, fy, kerchief)
        for x in (fx + 40, fx + 88):
            for k in range(4):
                s.d.ellipse([x - 5, fy + 30 + k * 16, x + 5, fy + 40 + k * 16], fill=GOLD, outline=DARK)
        s.d.line([(fx + 6, fy + 4), (fx + 118, fy + 84)], fill=leather, width=10)  # the cutlass strap
        s.d.line([(fx + 6, fy + 4), (fx + 118, fy + 84)], fill=shade(leather, 0.7), width=1)
        for sd in SIDES4:  # the wide belt, its big brass buckle at the front
            x, y, w, _ = TORSO[sd]
            s.d.rectangle([x, y + UT_PX - 14, x + w - 1, y + UT_PX - 2], fill=leather)
        s.d.rectangle([fx + 52, fy + UT_PX - 17, fx + 76, fy + UT_PX + 1], outline=GOLD, width=4)
        s.d.line([(bx + 6, by + 84), (bx + 118, by + 4)], fill=leather, width=10)  # the strap over the back
        s.limb_band(shade(navy, 1.3), HAND - 10, HAND)  # turned-back cuffs
        trousers = (90, 95, 105)
        p.torso(trousers, UT_PX - 4, 128, 1.0, 0.85)
        p.limbs(trousers, 0, HAND - 10)
        p.limbs((24, 24, 28), HAND - 10, 128, 1.1, 0.8)
        scuff(s, 211, 60)
        patch = rope
    else:
        red = (190, 40, 45)
        s.torso(red)
        s.limbs(red, 0, HAND)
        s.limb_band(GOLD, HAND - 10, HAND)  # gold braid at the cuffs
        # the coat worn open over the striped jersey, gold braid down both front edges
        s.d.rectangle([fx + 34, fy, fx + 94, fy + 127], fill=WHITE)
        for yy in range(0, 128, 16):
            s.d.rectangle([fx + 34, fy + yy, fx + 94, fy + yy + 6], fill=navy)
        for x in (fx + 30, fx + 94):
            s.d.rectangle([x, fy, x + 4, fy + 127], fill=GOLD)
        for k in range(3):
            y = fy + 20 + k * 14
            s.d.line([(fx + 6, y), (fx + 26, y)], fill=GOLD, width=3)
            s.d.line([(fx + 102, y), (fx + 122, y)], fill=GOLD, width=3)
        chain(s.d, (fx + 40, fy + 24), (fx + 80, fy + 70), STEEL, 8)  # the bosun's whistle chain
        s.d.rectangle([fx + 76, fy + 66, fx + 94, fy + 74], fill=(200, 205, 215), outline=DARK)
        p.torso((30, 30, 36), UT_PX - 4, 128, 1.0, 0.85)
        p.limbs((30, 30, 36), 0, HAND - 10)
        p.outer_stripe(GOLD, 0, HAND - 10, 4)
        p.limbs((24, 24, 28), HAND - 10, 128, 1.1, 0.8)
        patch = GOLD
    s.d.ellipse([bx + 30, by + 30, bx + 98, by + 98], fill=shade(patch, 0.55), outline=DARK, width=2)
    em_crossed_hooks(s.d, bx + 64, by + 70, patch, 1.0)
    return s.im, p.im


KINDS = {
    "SparkDrone": spark, "BurglarBot": burglar, "SneakBot": sneak, "BruteBot": brute, "Turret": sentry,
    "NullSentinel": null, "Diver": diver, "Anchor": anchor, "TorpedoSentry": torpedo,
    "ShieldBearer": shield_bearer, "Captain": captain, "Sniper": sniper, "Bomber": bomber, "MedicUnit": medic,
    "Swarmer": swarmer, "Mimic": mimic, "Interceptor": interceptor, "Grappler": grappler,
    "WindupToy": windup_toy, "WindupGiant": windup_giant,
    "SaltDog": salt_dog,
}
VERSIONS = ("Grunt", "Veteran", "Elite")
# the preview pages: the first 9 kinds, then the 9 added with the new enemy types, then the Suburbs chain's
# clockwork toys, then the Coast chain's Salt Dogs (one image each, so they stay readable):
# art/preview/uniforms_templates.png, uniforms_templates_new.png, uniforms_templates_toys.png and
# uniforms_templates_saltdogs.png, and the on-body renders art/preview/uniforms.png and uniforms_new.png
# (clothed.py uniforms <Version> [new], then --stack)
# Run with --only Kind,Kind to draw just those kinds (and the pages they fill), leaving the others' files alone.
PAGES = {
    "": list(KINDS)[:9],
    "_new": list(KINDS)[9:18],
    "_toys": ["WindupToy", "WindupGiant"],
    "_saltdogs": ["SaltDog"],
    # the side quest chains' kinds together, for the on-body render (clothed.py uniforms <Version> chains, then
    # --stack: art/preview/uniforms_chains.png)
    "_chains": ["WindupToy", "WindupGiant", "SaltDog"],
}


def stack():
    """Stack clothed.py's three version renders of each page into one image (Grunt, Veteran, Elite top to bottom)."""
    for suffix in PAGES:
        paths = [os.path.join(ROOT, "preview", "uniforms%s_%s.png" % (suffix, v.lower())) for v in VERSIONS]
        if not all(os.path.exists(pth) for pth in paths):
            print("skipped uniforms%s.png: render all three versions first" % suffix)
            continue
        ims = [Image.open(pth).convert("RGB") for pth in paths]
        out = Image.new("RGB", (ims[0].width, sum(im.height for im in ims)))
        y = 0
        for im in ims:
            out.paste(im, (0, y))
            y += im.height
        out.save(os.path.join(ROOT, "preview", "uniforms%s.png" % suffix))
        print("wrote uniforms%s.png" % suffix)


if __name__ == "__main__":
    if "--stack" in sys.argv:
        stack()
        sys.exit(0)
    sheets = {}
    only = sys.argv[sys.argv.index("--only") + 1].split(",") if "--only" in sys.argv else None
    for kind, fn in KINDS.items():
        if only and kind not in only:
            continue
        for v in VERSIONS:
            sh, pa = fn(v)
            sheets.setdefault(kind, []).append(save(kind, v, sh, pa))
    # preview: every uniform's template (shirt | pants), three versions a row, one sheet per page of kinds
    tw, th = 780, 373
    for suffix, kinds in PAGES.items():
        if not all(k in sheets for k in kinds):
            continue  # --only: a page whose kinds were not all drawn keeps its old preview
        sheet = Image.new("RGB", (tw * 3, th * len(kinds)), (120, 120, 120))
        for r, kind in enumerate(kinds):
            for c, im in enumerate(sheets[kind]):
                tile = Image.new("RGBA", im.size, (150, 150, 150, 255))
                tile.alpha_composite(im)
                sheet.paste(tile.convert("RGB").resize((tw - 6, th - 6)), (c * tw + 3, r * th + 3))
        sheet.save(os.path.join(ROOT, "preview", "uniforms_templates%s.png" % suffix))
    print("wrote", sum(len(v) for v in sheets.values()), "uniforms")
