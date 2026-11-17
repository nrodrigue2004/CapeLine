# art/clothes/uniforms.py: every robot kind's Roblox-look uniform, in three versions each (Grunt, Veteran, Elite),
# so enemies do not look repetitive (nate, 2026-11-17). Drawn on Roblox's classic Shirt and Pants template; each
# uniform is saved as <Kind>_<Version>.png with the Shirt and the Pants side by side (1170 x 559, what the game's
# robots wear: Shared.ClothesMap) plus the separate Shirt and Pants (real Roblox clothing, if ever needed).
# Areas left clear show the robot's skin (bare arms, rolled sleeves).
# Output: art/export/clothes/uniforms/*.png and art/preview/uniforms.png (every uniform's template).
# Run: python3 art/clothes/uniforms.py   (PIL only)
import os
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


KINDS = {
    "SparkDrone": spark, "BurglarBot": burglar, "SneakBot": sneak, "BruteBot": brute, "Turret": sentry,
    "NullSentinel": null, "Diver": diver, "Anchor": anchor, "TorpedoSentry": torpedo,
}
VERSIONS = ("Grunt", "Veteran", "Elite")

if __name__ == "__main__":
    rows = []
    for kind, fn in KINDS.items():
        for v in VERSIONS:
            sh, pa = fn(v)
            rows.append(save(kind, v, sh, pa))
    # preview: every uniform's template (shirt | pants), three versions a row
    tw, th = 780, 373
    sheet = Image.new("RGB", (tw * 3, th * len(KINDS)), (120, 120, 120))
    for i, im in enumerate(rows):
        tile = Image.new("RGBA", im.size, (150, 150, 150, 255))
        tile.alpha_composite(im)
        sheet.paste(tile.convert("RGB").resize((tw - 6, th - 6)), ((i % 3) * tw + 3, (i // 3) * th + 3))
    sheet.save(os.path.join(ROOT, "preview", "uniforms_templates.png"))
    print("wrote", len(rows), "uniforms")
