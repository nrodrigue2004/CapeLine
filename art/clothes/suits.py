# art/clothes/suits.py: the hero creator's Suits tab (Config.Creator tabs.suit, 15 + 31 tops) as classic Shirt and
# Pants overlays (overnight queue item 12, 2026-11-18). A suit still paints the body in its three colour roles
# (LookKit SUIT_COLORS / PieceKits.suitPaint: the hero's main, trim and accent picks); these templates are mostly
# clear, so that paint shows through, and add what blocks cannot: comic ink edges, cel shading, seams, panels,
# stripes, pockets and trims. Four layers, bottom to top:
#   tone   see-through black over the body paint (tone-on-tone pockets, quilting, camo, chainmail)
#   acc    opaque light greys that take the template's tint (Clothing.Color3 multiplies; each kit picks the tint
#          role in Config.Creator.suitArt: the accent "a" mostly, or "s", "white", "gold", "ice", "glowRed")
#   form   the shared cel shading (side and back faces, under the chest, the inner limbs, elbows and knees)
#   ink    near-black outlines round every face and every shape, so the suit reads at phone size
# The shirt covers the upper torso and arms (rows 0 to 102 of the torso); the pants the lower torso and legs.
# Every design is original: no real hero's costume, logo or symbol (the chest stays clear where the Emblems
# piece sits, rows 6 to 64 of the front).
# Output: art/export/clothes/suits/SuitShirt_<kit>.png, SuitPants_<kit>.png, preview.json (for
# art/blender/clothed.py suits <page>), and art/preview/suit_templates.png (every template over its body paint).
# Run: python3 art/clothes/suits.py   (PIL only)
import json
import os
import random
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from trooper import TORSO, RIGHT, LEFT, SIDES4, UT_PX, W, H  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "export", "clothes", "suits")
os.makedirs(OUT, exist_ok=True)

HAND = 108  # a limb strip's hand or foot rows start here
ELBOW = 54  # the forearm or shin rows start here
FULL = (255, 255, 255, 255)  # takes the tint at full strength
LITE = (232, 232, 232, 255)
MIDT = (196, 196, 196, 255)
DEEP = (150, 150, 150, 255)
INK = (20, 20, 30, 255)
CLEAR = (0, 0, 0, 0)
HEM = UT_PX  # the shirt stops at the upper torso's last row


def tone(a):
    return (0, 0, 0, a)


class Layer:
    def __init__(self):
        self.im = Image.new("RGBA", (W, H), CLEAR)
        self.d = ImageDraw.Draw(self.im)


class Tpl:
    """One template (shirt or pants) as four layers; `kind` says which rows of the torso it owns."""

    def __init__(self, kind):
        self.kind = kind
        self.tone, self.acc, self.ink = Layer(), Layer(), Layer()
        self.form = True
        self.r0, self.r1 = (0, HEM) if kind == "shirt" else (HEM, 128)

    # ---- regions
    def torso_faces(self):
        for s in SIDES4:
            yield s, TORSO[s]

    def limb_faces(self):
        for slots in (RIGHT, LEFT):
            for s in SIDES4:
                yield slots, s, slots[s]

    def outer(self):
        """(x, y, w, h) of each limb's outer face (the right limb's R, the left limb's L)."""
        return [RIGHT["R"], LEFT["L"]]

    def inner(self):
        return [RIGHT["L"], LEFT["R"]]

    def fronts(self):
        return [RIGHT["F"], LEFT["F"]]

    def backs(self):
        return [RIGHT["B"], LEFT["B"]]

    # ---- drawing in template terms (rows are a face's own rows; a torso row of a pants is 102 to 127)
    def torso_band(self, layer, r0, r1, fill, sides=SIDES4):
        for s in sides:
            x, y, w, _ = TORSO[s]
            layer.d.rectangle([x, y + r0, x + w - 1, y + r1 - 1], fill=fill)

    def limb_band(self, layer, r0, r1, fill):
        for _, _, (x, y, w, _) in self.limb_faces():
            layer.d.rectangle([x, y + r0, x + w - 1, y + r1 - 1], fill=fill)

    def limb_line(self, layer, r, fill, width=2):
        for _, _, (x, y, w, _) in self.limb_faces():
            layer.d.line([(x, y + r), (x + w - 1, y + r)], fill=fill, width=width)

    def stripe(self, layer, faces, r0, r1, wd, fill, off=0):
        for x, y, w, _ in faces:
            c = x + w // 2 + off
            layer.d.rectangle([c - wd // 2, y + r0, c + (wd + 1) // 2 - 1, y + r1 - 1], fill=fill)

    def inked_rect(self, box, fill, layer=None, width=2):
        (layer or self.acc).d.rectangle(box, fill=fill)
        self.ink.d.rectangle(box, outline=INK, width=width)

    def inked_poly(self, pts, fill, layer=None, width=2):
        (layer or self.acc).d.polygon(pts, fill=fill)
        self.ink.d.line(pts + [pts[0]], fill=INK, width=width, joint="curve")

    def inked_ellipse(self, box, fill, layer=None, width=2):
        (layer or self.acc).d.ellipse(box, fill=fill)
        self.ink.d.ellipse(box, outline=INK, width=width)

    # ---- the finish
    def shading(self):
        """The cel shading every suit shares (light from the front left, above)."""
        f = Layer()
        d = f.d
        if self.kind == "shirt":
            for s in ("R", "L"):
                x, y, w, _ = TORSO[s]
                d.rectangle([x, y, x + w - 1, y + HEM - 1], fill=tone(46 if s == "L" else 30))
            x, y, w, _ = TORSO["B"]
            d.rectangle([x, y, x + w - 1, y + HEM - 1], fill=tone(28))
            x, y, w, _ = TORSO["F"]
            d.rectangle([x + w - 14, y, x + w - 1, y + HEM - 1], fill=tone(26))  # the turned edge
            d.rectangle([x, y + HEM - 12, x + w - 1, y + HEM - 1], fill=tone(22))  # under the chest
        else:
            for s in SIDES4:
                x, y, w, _ = TORSO[s]
                d.rectangle([x, y + HEM, x + w - 1, y + 127], fill=tone(20 if s == "F" else 40))
        for x, y, w, h in self.inner():
            d.rectangle([x, y, x + w - 1, y + h - 1], fill=tone(54))
        for x, y, w, h in self.backs():
            d.rectangle([x, y, x + w - 1, y + h - 1], fill=tone(30))
        for _, s, (x, y, w, h) in self.limb_faces():
            d.rectangle([x, y + ELBOW - 7, x + w - 1, y + ELBOW - 1], fill=tone(26))  # elbow or knee crease
            d.rectangle([x, y + HAND - 5, x + w - 1, y + HAND - 1], fill=tone(26))
            if s == "F":
                d.rectangle([x + w - 9, y, x + w - 1, y + h - 1], fill=tone(18))
        return f.im

    def outline(self):
        d = self.ink.d
        for s, (x, y, w, h) in self.torso_faces():
            if self.kind == "shirt":
                d.rectangle([x, y, x + w - 1, y + HEM - 1], outline=INK, width=2)
            else:
                d.rectangle([x, y + HEM, x + w - 1, y + h - 1], outline=INK, width=2)
        for _, _, (x, y, w, h) in self.limb_faces():
            d.rectangle([x, y, x + w - 1, y + h - 1], outline=INK, width=2)
            d.line([(x, y + ELBOW), (x + w - 1, y + ELBOW)], fill=(20, 20, 30, 110), width=1)
            d.line([(x, y + HAND), (x + w - 1, y + HAND)], fill=(20, 20, 30, 150), width=1)

    def image(self):
        self.outline()
        im = Image.new("RGBA", (W, H), CLEAR)
        im.alpha_composite(self.tone.im)
        im.alpha_composite(self.acc.im)
        if self.form:
            im.alpha_composite(self.shading())
        im.alpha_composite(self.ink.im)
        # only the rows this template owns on the torso
        for s, (x, y, w, h) in self.torso_faces():
            if self.kind == "shirt":
                im.paste(CLEAR, (x, y + HEM, x + w, y + h))
            else:
                im.paste(CLEAR, (x, y, x + w, y + HEM))
        if self.kind == "pants":
            im.paste(CLEAR, TORSO["U"][:2] + (TORSO["U"][0] + TORSO["U"][2], TORSO["U"][1] + TORSO["U"][3]))
        return im


# ---------------------------------------------------------------- shared bits
def F():
    return TORSO["F"]


def B():
    return TORSO["B"]


def collar(t, fill=FULL, h=6):
    """A collar band round the neck: across the top of every torso face."""
    t.torso_band(t.acc, 0, h, fill)
    t.torso_band(t.ink, h, h + 2, INK)


def cuffs(t, fill=FULL, at=HAND, h=8):
    t.limb_band(t.acc, at - h, at, fill)
    t.limb_line(t.ink, at - h, INK, 2)


def boot_tops(t, fill=FULL, at=HAND - 22, h=8):
    t.limb_band(t.acc, at, at + h, fill)
    t.limb_line(t.ink, at, INK, 2)
    t.limb_line(t.ink, at + h, INK, 2)


def belt(t, fill=FULL, buckle=LITE, r0=HEM + 2, r1=HEM + 12, shape="rect"):
    t.torso_band(t.acc, r0, r1, fill)
    t.torso_band(t.ink, r0 - 1, r0 + 1, INK)
    t.torso_band(t.ink, r1 - 1, r1 + 1, INK)
    fx, fy, _, _ = F()
    cy = fy + (r0 + r1) // 2
    if shape == "rect":
        t.inked_rect([fx + 54, cy - 8, fx + 73, cy + 8], buckle)
        t.inked_rect([fx + 59, cy - 4, fx + 68, cy + 4], DEEP)
    elif shape == "round":
        t.inked_ellipse([fx + 53, cy - 9, fx + 74, cy + 9], buckle)
        t.inked_ellipse([fx + 59, cy - 4, fx + 68, cy + 4], DEEP)
    elif shape == "diamond":
        t.inked_poly([(fx + 64, cy - 10), (fx + 76, cy), (fx + 64, cy + 10), (fx + 52, cy)], buckle)


def seams_abs(t, a=60):
    """Tone seams of a fitted bodysuit: a centre line and the ab panel under the emblem."""
    fx, fy, _, _ = F()
    d = t.tone.d
    d.line([(fx + 64, fy + 68), (fx + 64, fy + HEM)], fill=tone(a), width=2)
    for k in range(2):
        yy = fy + 76 + k * 12
        d.line([(fx + 44, yy), (fx + 84, yy)], fill=tone(a - 10), width=2)
    d.line([(fx + 36, fy + 66), (fx + 44, fy + HEM)], fill=tone(a - 10), width=2)
    d.line([(fx + 92, fy + 66), (fx + 84, fy + HEM)], fill=tone(a - 10), width=2)


def chevron_at(t, cx, top, half, depth, th, fill=FULL):
    """A V (point down) centred at cx, from row `top`; th its thickness."""
    pts = [(cx - half, top), (cx - half + th, top), (cx, top + depth - th), (cx + half - th, top),
           (cx + half, top), (cx, top + depth)]
    t.inked_poly(pts, fill)


def zig(t, x, y, w, h, fill=FULL, n=3):
    """A lightning zig-zag (an original storm mark, three kinks) inside (x, y, w, h)."""
    pts = [(x + w * 0.62, y), (x + w * 0.18, y + h * 0.52), (x + w * 0.48, y + h * 0.52), (x + w * 0.3, y + h),
           (x + w * 0.86, y + h * 0.4), (x + w * 0.55, y + h * 0.4), (x + w * 0.85, y)]
    t.inked_poly([(int(a), int(b)) for a, b in pts], fill)


def star(cx, cy, r, ri=None, n=5, rot=-90):
    import math
    ri = ri or r * 0.45
    pts = []
    for i in range(n * 2):
        rr = r if i % 2 == 0 else ri
        a = math.radians(rot + i * 180 / n)
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    return [(int(a), int(b)) for a, b in pts]


def rivets(t, pts, r=3):
    for x, y in pts:
        t.inked_ellipse([x - r, y - r, x + r, y + r], LITE, width=1)


def pocket(t, x, y, w, h, flap=True):
    """A tone-on-tone pocket with a stitched flap."""
    t.tone.d.rectangle([x, y, x + w, y + h], fill=tone(40))
    t.ink.d.rectangle([x, y, x + w, y + h], outline=(20, 20, 30, 200), width=1)
    if flap:
        t.tone.d.rectangle([x, y, x + w, y + 6], fill=tone(70))
        t.ink.d.line([(x, y + 6), (x + w, y + 6)], fill=(20, 20, 30, 200), width=1)


def camo(t, seed, layer_alpha=(46, 80), n=90, faces="all"):
    rnd = random.Random(seed)
    regions = []
    if t.kind == "shirt":
        regions += [(x, y, w, HEM) for _, (x, y, w, _) in t.torso_faces()]
    else:
        regions += [(x, y + HEM, w, 128 - HEM) for _, (x, y, w, _) in t.torso_faces()]
    regions += [r for _, _, r in t.limb_faces()]
    for x, y, w, h in regions:
        for _ in range(max(3, n * w * h // (128 * 128))):
            cx, cy = rnd.uniform(x, x + w), rnd.uniform(y, y + h)
            rx, ry = rnd.uniform(6, 16), rnd.uniform(4, 10)
            a = layer_alpha[rnd.randrange(len(layer_alpha))]
            t.tone.d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=tone(a))
    # keep the blots inside their faces
    keep = Image.new("L", (W, H), 0)
    kd = ImageDraw.Draw(keep)
    for x, y, w, h in regions:
        kd.rectangle([x, y, x + w - 1, y + h - 1], fill=255)
    t.tone.im.putalpha(Image.composite(t.tone.im.getchannel("A"), Image.new("L", (W, H), 0), keep))


def clip(t, layer, regions):
    keep = Image.new("L", (W, H), 0)
    kd = ImageDraw.Draw(keep)
    for x, y, w, h in regions:
        kd.rectangle([x, y, x + w - 1, y + h - 1], fill=255)
    layer.im.putalpha(Image.composite(layer.im.getchannel("A"), Image.new("L", (W, H), 0), keep))


# ---------------------------------------------------------------- the 15 first suits
def plain():
    s, p = Tpl("shirt"), Tpl("pants")
    collar(s)
    cuffs(s, h=10)
    seams_abs(s)
    belt(p)
    boot_tops(p, at=HAND - 20, h=10)
    p.stripe(p.tone, p.fronts(), 6, HAND - 20, 2, tone(50))
    return s, p


def stripe():
    s, p = Tpl("shirt"), Tpl("pants")
    fx, fy, fw, _ = F()
    bx, by, _, _ = B()
    for x0, y0 in ((fx, fy), (bx, by)):  # the racer's wide stripe with two pinstripes
        s.inked_rect([x0 + 52, y0, x0 + 75, y0 + HEM - 1], FULL)
        s.inked_rect([x0 + 44, y0, x0 + 47, y0 + HEM - 1], FULL, width=1)
        s.inked_rect([x0 + 80, y0, x0 + 83, y0 + HEM - 1], FULL, width=1)
    for x0, y0 in ((fx, fy), (bx, by)):
        p.inked_rect([x0 + 52, y0 + HEM, x0 + 75, y0 + 127], FULL)
    s.stripe(s.acc, s.outer(), 0, HAND, 14, FULL)
    p.stripe(p.acc, p.outer(), 0, HAND, 14, FULL)
    for t in (s, p):
        for x, y, w, _ in t.outer():
            c = x + w // 2
            t.ink.d.line([(c - 8, y), (c - 8, y + HAND - 1)], fill=INK, width=2)
            t.ink.d.line([(c + 7, y), (c + 7, y + HAND - 1)], fill=INK, width=2)
    cuffs(s, fill=LITE, h=6)
    belt(p, fill=MIDT)
    return s, p


def split():
    s, p = Tpl("shirt"), Tpl("pants")
    fx, fy, _, _ = F()
    bx, by, _, _ = B()
    # the torso split on a diagonal: the accent half from the right shoulder to the left hip
    s.inked_poly([(fx, fy), (fx + 80, fy), (fx + 36, fy + HEM - 1), (fx, fy + HEM - 1)], FULL)
    s.inked_poly([(bx + 127, by), (bx + 48, by), (bx + 92, by + HEM - 1), (bx + 127, by + HEM - 1)], FULL)
    x, y, w, _ = TORSO["R"]
    s.inked_rect([x, y, x + w - 1, y + HEM - 1], FULL)
    s.ink.d.line([(fx + 84, fy), (fx + 40, fy + HEM - 1)], fill=INK, width=4)
    # the waistband and a split on the legs: the outer halves in accent
    belt(p, fill=FULL, shape="diamond")
    for x, y, w, _ in p.outer():
        p.inked_rect([x, y, x + w - 1, y + HAND - 1], FULL)
    cuffs(s, fill=FULL, h=10)
    return s, p


def chevron():
    s, p = Tpl("shirt"), Tpl("pants")
    fx, fy, _, _ = F()
    bx, by, _, _ = B()
    chevron_at(s, fx + 64, fy + 2, 64, 60, 16)  # the big V from shoulder to shoulder, under the emblem
    chevron_at(s, bx + 64, by + 2, 64, 44, 12)
    for x, y, w, _ in s.fronts():
        chevron_at(s, x + w // 2, y + 66, 26, 20, 7)
        chevron_at(s, x + w // 2, y + 80, 26, 20, 7)
    for x, y, w, _ in p.fronts():
        chevron_at(p, x + w // 2, y + 40, 26, 22, 8)
    belt(p, fill=MIDT)
    boot_tops(p, at=HAND - 22)
    cuffs(s, fill=LITE)
    return s, p


def jacket():
    # paint: torso s (the tee), arms p (the jacket's sleeves), legs dark; the shirt is tinted p
    s, p = Tpl("shirt"), Tpl("pants")
    fx, fy, _, _ = F()
    for side in (0, 1):  # the open jacket's front panels and lapels
        if side == 0:
            s.inked_poly([(fx, fy), (fx + 38, fy), (fx + 50, fy + 40), (fx + 44, fy + HEM - 1), (fx, fy + HEM - 1)], FULL)
            s.inked_poly([(fx + 26, fy), (fx + 42, fy), (fx + 52, fy + 34), (fx + 40, fy + 26)], LITE)
        else:
            s.inked_poly([(fx + 127, fy), (fx + 89, fy), (fx + 77, fy + 40), (fx + 83, fy + HEM - 1), (fx + 127, fy + HEM - 1)], FULL)
            s.inked_poly([(fx + 101, fy), (fx + 85, fy), (fx + 75, fy + 34), (fx + 87, fy + 26)], LITE)
    for k in ("R", "L", "B"):
        x, y, w, _ = TORSO[k]
        s.acc.d.rectangle([x, y, x + w - 1, y + HEM - 1], fill=FULL)
    x, y, w, _ = TORSO["B"]
    s.inked_rect([x + 20, y + 0, x + 107, y + 10], LITE)  # the collar at the back
    s.ink.d.line([(x, y + 30), (x + w - 1, y + 30)], fill=(20, 20, 30, 160), width=1)
    for px in (fx + 6, fx + 92):
        s.ink.d.line([(px, fy + 76), (px + 28, fy + 70)], fill=INK, width=3)  # slash pockets
    s.ink.d.line([(fx + 44, fy + 40), (fx + 46, fy + HEM - 1)], fill=(170, 170, 176, 255), width=2)  # zip edge
    cuffs(s, fill=DEEP, h=8)
    t = s.tone.d  # the tee under it: a collar line
    t.arc([fx + 46, fy - 14, fx + 82, fy + 12], 0, 180, fill=tone(90), width=4)
    # jeans: stitched seams and pockets over dark legs (tinted white: light stitching)
    belt(p, fill=(90, 70, 50, 255), buckle=MIDT)
    for x, y, w, _ in p.outer():
        p.acc.d.line([(x + w // 2, y), (x + w // 2, y + HAND - 1)], fill=(150, 150, 160, 255), width=1)
    p.limb_band(p.acc, HAND - 8, HAND, (90, 90, 100, 255))
    for x, y, w, _ in p.fronts():
        p.ink.d.arc([x + 8, y - 24, x + 56, y + 14], 20, 160, fill=(150, 150, 160, 255), width=1)
    return s, p


def armor():
    s, p = Tpl("shirt"), Tpl("pants")
    fx, fy, _, _ = F()
    # segmented ab plates under the chest plate (a part), side plates, plated forearms and knee guards
    for k in range(3):
        y0 = fy + 66 + k * 12
        s.inked_rect([fx + 34, y0, fx + 61, y0 + 9], LITE)
        s.inked_rect([fx + 66, y0, fx + 93, y0 + 9], LITE)
    for k in ("R", "L"):
        x, y, w, _ = TORSO[k]
        for j in range(4):
            s.inked_rect([x + 8, y + 10 + j * 22, x + w - 9, y + 26 + j * 22], MIDT)
    for x, y, w, _ in s.fronts() + s.outer():
        s.inked_poly([(x + 4, y + ELBOW + 4), (x + w - 5, y + ELBOW + 4), (x + w - 9, y + HAND - 6), (x + 8, y + HAND - 6)], LITE)
        rivets(s, [(x + 12, y + ELBOW + 12), (x + w - 13, y + ELBOW + 12)])
    for x, y, w, _ in p.fronts():
        p.inked_poly([(x + 10, y + 40), (x + w - 11, y + 40), (x + w - 6, y + 56), (x + w // 2, y + 66), (x + 5, y + 56)], FULL)
        rivets(p, [(x + w // 2, y + 50)])
        p.inked_rect([x + 8, y + 70, x + w - 9, y + HAND - 4], LITE)
    belt(p, fill=MIDT, shape="round")
    return s, p


def core():
    s, p = Tpl("shirt"), Tpl("pants")
    fx, fy, _, _ = F()
    cx, cy = fx + 64, fy + 38  # rings around the reactor core part
    for r, w in ((40, 4), (30, 3)):
        s.acc.d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=FULL, width=w)
        s.ink.d.ellipse([cx - r - 2, cy - r - 2, cx + r + 2, cy + r + 2], outline=INK, width=1)
    for ang in (-150, -30, 30, 150):  # conduits out to the shoulders and hips
        import math
        a = math.radians(ang)
        x0, y0 = cx + 40 * math.cos(a), cy + 40 * math.sin(a)
        x1, y1 = cx + 70 * math.cos(a), cy + 70 * math.sin(a)
        s.acc.d.line([(x0, y0), (x1, y1)], fill=FULL, width=6)
        s.ink.d.line([(x0, y0), (x1, y1)], fill=INK, width=1)
    for k in ("R", "L"):
        x, y, w, _ = TORSO[k]
        s.inked_rect([x + w // 2 - 4, y, x + w // 2 + 3, y + HEM - 1], FULL)
    s.stripe(s.acc, s.outer(), 0, HAND, 8, FULL)
    s.stripe(s.ink, s.outer(), 0, HAND, 2, INK)
    p.stripe(p.acc, p.outer(), 0, HAND, 8, FULL)
    p.stripe(p.ink, p.outer(), 0, HAND, 2, INK)
    for x, y, w, _ in p.fronts():
        p.inked_ellipse([x + w // 2 - 9, y + 38, x + w // 2 + 9, y + 56], FULL)  # knee nodes
    belt(p, fill=MIDT, shape="round")
    cuffs(s, fill=LITE)
    return s, p


def circuit():
    s, p = Tpl("shirt"), Tpl("pants")
    rnd = random.Random(12)

    def traces(t, regions, n):
        for x, y, w, h in regions:
            for _ in range(n):
                px, py = int(rnd.uniform(x + 6, x + w - 6)), int(rnd.uniform(y + 6, y + h - 6))
                pts = [(px, py)]
                for _ in range(3):
                    if rnd.random() < 0.5:
                        px = int(min(x + w - 5, max(x + 4, px + rnd.choice((-1, 1)) * rnd.uniform(8, 26))))
                    else:
                        py = int(min(y + h - 5, max(y + 4, py + rnd.choice((-1, 1)) * rnd.uniform(8, 26))))
                    pts.append((px, py))
                t.acc.d.line(pts, fill=FULL, width=3)
                for q in (pts[0], pts[-1]):
                    t.acc.d.ellipse([q[0] - 4, q[1] - 4, q[0] + 4, q[1] + 4], fill=FULL)
                    t.ink.d.ellipse([q[0] - 2, q[1] - 2, q[0] + 2, q[1] + 2], fill=INK)

    torso = [(x, y, w, HEM) for _, (x, y, w, _) in s.torso_faces()]
    traces(s, torso, 6)
    traces(s, [r for _, _, r in s.limb_faces()], 3)
    traces(p, [r for _, _, r in p.limb_faces()], 3)
    clip(s, s.acc, torso + [r for _, _, r in s.limb_faces()] + [(TORSO["F"][0] + 30, TORSO["F"][1], 68, 5)])
    clip(p, p.acc, [r for _, _, r in p.limb_faces()])
    fx, fy, _, _ = F()
    s.acc.d.rectangle([fx + 30, fy + 0, fx + 97, fy + 4], fill=FULL)
    belt(p, fill=DEEP, shape="rect")
    s.form = True
    return s, p


def sash():
    s, p = Tpl("shirt"), Tpl("pants")
    fx, fy, _, _ = F()
    bx, by, _, _ = B()
    # a wide fighter's sash from the left shoulder to the right hip, front and back, with a knot and tails
    s.inked_poly([(fx + 96, fy), (fx + 127, fy), (fx + 127, fy + 18), (fx + 26, fy + HEM - 1), (fx, fy + HEM - 1), (fx, fy + 86)], FULL)
    s.inked_poly([(bx, by), (bx + 31, by), (bx + 127, by + 86), (bx + 127, by + HEM - 1), (bx + 101, by + HEM - 1), (bx, by + 18)], FULL)
    for k in range(4):
        s.tone.d.line([(fx + 100 - k * 22, fy + 12 + k * 18), (fx + 112 - k * 22, fy + 22 + k * 18)], fill=tone(60), width=2)
    x, y, w, _ = TORSO["L"]
    s.inked_rect([x, y + 70, x + w - 1, y + HEM - 1], FULL)
    belt(p, fill=FULL, shape="diamond")
    x, y, w, _ = TORSO["F"]  # the knot's tails hanging from the belt
    p.inked_poly([(x + 18, y + HEM + 10), (x + 30, y + HEM + 10), (x + 26, y + 127), (x + 12, y + 127)], LITE)
    for x, y, w, _ in s.fronts() + s.outer() + s.inner() + s.backs():  # wrist wraps
        for k in range(3):
            s.acc.d.polygon([(x, y + 80 + k * 9), (x + w - 1, y + 74 + k * 9), (x + w - 1, y + 80 + k * 9), (x, y + 86 + k * 9)], fill=LITE)
        s.ink.d.line([(x, y + 74), (x + w - 1, y + 68)], fill=INK, width=2)
    for x, y, w, _ in p.fronts() + p.outer() + p.inner() + p.backs():  # shin wraps
        for k in range(3):
            p.acc.d.polygon([(x, y + 70 + k * 10), (x + w - 1, y + 64 + k * 10), (x + w - 1, y + 70 + k * 10), (x, y + 76 + k * 10)], fill=LITE)
    return s, p


def ribs():
    # tinted white: bone-coloured ribs over a dark torso (spooky, cartoon, never gory)
    s, p = Tpl("shirt"), Tpl("pants")
    BONE = (240, 232, 210, 255)
    fx, fy, _, _ = F()
    s.inked_rect([fx + 60, fy + 6, fx + 67, fy + 70], BONE)  # the sternum
    for k in range(5):
        y0 = fy + 14 + k * 13
        half = 46 - k * 5
        for sgn in (-1, 1):
            pts = [(fx + 64 + sgn * 6, y0), (fx + 64 + sgn * half, y0 + 4), (fx + 64 + sgn * (half - 2), y0 + 10),
                   (fx + 64 + sgn * 6, y0 + 7)]
            s.inked_poly(pts, BONE)
    bx, by, _, _ = B()
    for k in range(9):  # the spine
        s.inked_rect([bx + 58, by + 6 + k * 11, bx + 69, by + 13 + k * 11], BONE)
    for x, y, w, _ in s.outer():
        s.inked_rect([x + w // 2 - 5, y + 4, x + w // 2 + 4, y + ELBOW - 6], BONE)
        s.inked_rect([x + w // 2 - 8, y + ELBOW + 2, x + w // 2 - 2, y + HAND - 6], BONE)
        s.inked_rect([x + w // 2 + 2, y + ELBOW + 2, x + w // 2 + 8, y + HAND - 6], BONE)
    belt(p, fill=(120, 116, 110, 255), buckle=BONE, shape="round")
    for x, y, w, _ in p.fronts():
        p.inked_rect([x + w // 2 - 6, y + 4, x + w // 2 + 5, y + 44], BONE)
        p.inked_ellipse([x + w // 2 - 9, y + 42, x + w // 2 + 8, y + 56], BONE)
        p.inked_rect([x + w // 2 - 5, y + 58, x + w // 2 + 4, y + HAND - 6], BONE)
    return s, p


def panel_suit():
    # Night Patrol (pack 1): armoured side panels (parts), a chest plate outline, a utility belt with pouches
    s, p = Tpl("shirt"), Tpl("pants")
    fx, fy, _, _ = F()
    s.ink.d.polygon([(fx + 22, fy + 6), (fx + 106, fy + 6), (fx + 98, fy + 62), (fx + 64, fy + 72), (fx + 30, fy + 62)], outline=INK)
    s.tone.d.polygon([(fx + 22, fy + 6), (fx + 106, fy + 6), (fx + 98, fy + 62), (fx + 64, fy + 72), (fx + 30, fy + 62)], fill=tone(34))
    s.inked_rect([fx + 20, fy, fx + 107, fy + 5], FULL)
    seams_abs(s, 70)
    for x, y, w, _ in s.outer():
        s.inked_poly([(x + 4, y + 4), (x + w - 5, y + 4), (x + w - 5, y + 30), (x + 4, y + 38)], LITE)
    for x, y, w, _ in s.fronts():
        s.inked_rect([x + 6, y + ELBOW + 6, x + w - 7, y + HAND - 4], MIDT)
        for k in range(3):
            s.ink.d.line([(x + 14, y + ELBOW + 14 + k * 10), (x + w - 15, y + ELBOW + 10 + k * 10)], fill=INK, width=2)
    belt(p, fill=MIDT, buckle=FULL, r0=HEM + 1, r1=HEM + 14)
    fx, fy, _, _ = F()
    for k, px in enumerate((fx + 8, fx + 28, fx + 84, fx + 104)):
        p.inked_rect([px, fy + HEM + 4, px + 15, fy + HEM + 22], LITE)
    for x, y, w, _ in p.outer():
        p.inked_rect([x + 10, y + 12, x + w - 11, y + 36], LITE)  # thigh holster plates
    boot_tops(p, fill=MIDT, at=HAND - 26, h=6)
    return s, p


def bolt():
    s, p = Tpl("shirt"), Tpl("pants")
    fx, fy, _, _ = F()
    zig(s, fx + 70, fy + 2, 54, 96)  # the storm bolt runs off the chest's right side, clear of the emblem
    bx, by, _, _ = B()
    zig(s, bx + 30, by + 4, 70, 92)
    for x, y, w, _ in s.outer():
        zig(s, x + 10, y + 6, w - 20, 44)
    for x, y, w, _ in p.outer():
        zig(p, x + 10, y + 10, w - 20, 70)
    for k in range(3):  # storm cloud swirls on the shoulders (tone)
        s.tone.d.arc([fx + 6 + k * 14, fy - 8, fx + 34 + k * 14, fy + 14], 0, 180, fill=tone(70), width=3)
    belt(p, fill=FULL, shape="diamond")
    cuffs(s, fill=FULL)
    return s, p


def bulwark():
    s, p = Tpl("shirt"), Tpl("pants")
    fx, fy, _, _ = F()
    # heavy plating: riveted plate edges round the chest plate (a part), a gorget, banded legs
    s.inked_rect([fx + 18, fy, fx + 109, fy + 8], LITE)
    rivets(s, [(fx + 14 + k * 20, fy + 86) for k in range(6)], 4)
    s.inked_rect([fx + 6, fy + 78, fx + 121, fy + 94], MIDT)
    rivets(s, [(fx + 14 + k * 20, fy + 86) for k in range(6)], 3)
    for k in ("R", "L"):
        x, y, w, _ = TORSO[k]
        s.inked_rect([x + 6, y + 30, x + w - 7, y + 90], MIDT)
    for x, y, w, _ in s.fronts() + s.outer():
        s.inked_rect([x + 4, y + ELBOW, x + w - 5, y + HAND - 2], LITE)
        rivets(s, [(x + 10, y + ELBOW + 8), (x + w - 11, y + ELBOW + 8), (x + 10, y + HAND - 10), (x + w - 11, y + HAND - 10)])
    belt(p, fill=MIDT, r0=HEM, r1=HEM + 16)
    for x, y, w, _ in p.fronts() + p.outer():
        p.inked_rect([x + 4, y + 36, x + w - 5, y + HAND - 2], LITE)
        for k in range(3):
            p.ink.d.line([(x + 4, y + 50 + k * 18), (x + w - 5, y + 50 + k * 18)], fill=INK, width=2)
    return s, p


def neon_suit():
    s, p = Tpl("shirt"), Tpl("pants")
    fx, fy, _, _ = F()
    bx, by, _, _ = B()
    for x0, y0 in ((fx, fy), (bx, by)):  # angular light lines that frame the chest
        s.acc.d.line([(x0 + 4, y0 + 10), (x0 + 30, y0 + 70), (x0 + 64, y0 + 92), (x0 + 98, y0 + 70), (x0 + 123, y0 + 10)], fill=FULL, width=4)
        s.acc.d.line([(x0 + 18, y0 + 4), (x0 + 40, y0 + 52)], fill=FULL, width=2)
        s.acc.d.line([(x0 + 110, y0 + 4), (x0 + 88, y0 + 52)], fill=FULL, width=2)
    for x, y, w, _ in s.fronts():
        s.acc.d.line([(x + 6, y + 60), (x + w // 2, y + 76), (x + w - 7, y + 60)], fill=FULL, width=3)
    for x, y, w, _ in p.fronts():
        s_ = p.acc.d
        s_.line([(x + 6, y + 30), (x + w // 2, y + 46), (x + w - 7, y + 30)], fill=FULL, width=3)
        s_.line([(x + w // 2, y + 46), (x + w // 2, y + HAND - 4)], fill=FULL, width=3)
    belt(p, fill=DEEP, buckle=FULL, shape="diamond")
    p.limb_band(p.acc, HAND - 4, HAND, FULL)
    s.limb_band(s.acc, HAND - 4, HAND, FULL)
    return s, p


def chrome():
    # tinted white: the starter finish's glare streaks over the Foil body, and dark panel lines
    s, p = Tpl("shirt"), Tpl("pants")
    GL = (255, 255, 255, 130)
    fx, fy, _, _ = F()
    for x0, y0 in ((fx, fy), (TORSO["B"][0], TORSO["B"][1])):
        s.acc.d.polygon([(x0 + 10, y0 + HEM - 1), (x0 + 30, y0 + HEM - 1), (x0 + 74, y0), (x0 + 54, y0)], fill=GL)
        s.acc.d.polygon([(x0 + 38, y0 + HEM - 1), (x0 + 44, y0 + HEM - 1), (x0 + 88, y0), (x0 + 82, y0)], fill=GL)
    for t in (s, p):
        for x, y, w, h in t.fronts():
            t.acc.d.polygon([(x + 8, y + h - 24), (x + 18, y + h - 24), (x + 40, y), (x + 30, y)], fill=GL)
    s.ink.d.line([(fx + 64, fy + 70), (fx + 64, fy + HEM)], fill=(20, 20, 30, 160), width=2)
    belt(p, fill=(90, 90, 100, 255), buckle=FULL)
    s.form = True
    return s, p


# ---------------------------------------------------------------- the 31 tops (2026-11-17)
def tee():
    s, p = Tpl("shirt"), Tpl("pants")
    fx, fy, _, _ = F()
    s.tone.d.arc([fx + 40, fy - 22, fx + 88, fy + 14], 0, 180, fill=tone(110), width=5)
    s.torso_band(s.tone, HEM - 8, HEM, tone(40))
    s.inked_rect([fx + 86, fy + 26, fx + 108, fy + 48], FULL)  # an accent chest pocket
    s.ink.d.line([(fx + 86, fy + 31), (fx + 108, fy + 31)], fill=INK, width=1)
    belt(p, fill=(70, 56, 44, 255), buckle=MIDT)
    for x, y, w, _ in p.outer():
        p.tone.d.line([(x + w // 2, y), (x + w // 2, y + HAND - 1)], fill=tone(70), width=1)
    p.limb_band(p.tone, HAND - 6, HAND, tone(50))
    return s, p


def tank():
    s, p = Tpl("shirt"), Tpl("pants")
    fx, fy, _, _ = F()
    bx, by, _, _ = B()
    for x0, y0 in ((fx, fy), (bx, by)):  # ribbed edging round the arm holes and the scoop neck
        s.acc.d.arc([x0 + 34, y0 - 30, x0 + 94, y0 + 22], 0, 180, fill=FULL, width=5)
        s.ink.d.arc([x0 + 32, y0 - 32, x0 + 96, y0 + 24], 0, 180, fill=INK, width=2)
    for k in range(0, 128, 4):
        s.tone.d.line([(fx + k, fy + 26), (fx + k, fy + HEM - 1)], fill=tone(14), width=1)
    s.torso_band(s.tone, HEM - 6, HEM, tone(46))
    belt(p, fill=(60, 52, 46, 255), buckle=MIDT)
    p.limb_band(p.tone, HAND - 6, HAND, tone(50))
    return s, p


def hoodie():
    s, p = Tpl("shirt"), Tpl("pants")
    fx, fy, _, _ = F()
    s.tone.d.rounded_rectangle([fx + 26, fy + 62, fx + 102, fy + 96], 6, fill=tone(36))  # the pouch
    s.ink.d.rounded_rectangle([fx + 26, fy + 62, fx + 102, fy + 96], 6, outline=INK, width=2)
    s.ink.d.line([(fx + 34, fy + 64), (fx + 30, fy + 94)], fill=INK, width=1)
    s.ink.d.line([(fx + 94, fy + 64), (fx + 98, fy + 94)], fill=INK, width=1)
    for px in (fx + 52, fx + 76):  # accent drawstrings with tips
        s.inked_rect([px - 2, fy + 2, px + 1, fy + 40], FULL, width=1)
        s.inked_rect([px - 3, fy + 40, px + 2, fy + 46], LITE, width=1)
    s.torso_band(s.tone, HEM - 9, HEM, tone(50))
    s.limb_band(s.tone, HAND - 10, HAND, tone(50))
    belt(p, fill=(70, 56, 44, 255), buckle=MIDT)
    p.limb_band(p.tone, HAND - 6, HAND, tone(50))
    return s, p


def tracksuit():
    # tinted white: two white stripes down every outer arm and leg, a white collar and a zip
    s, p = Tpl("shirt"), Tpl("pants")
    WH = (246, 246, 248, 255)
    for t in (s, p):
        for x, y, w, _ in t.outer():
            for k in (-9, 3):
                t.inked_rect([x + w // 2 + k, y, x + w // 2 + k + 5, y + HAND - 1], WH, width=1)
    for k in ("R", "L"):
        x, y, w, _ = TORSO[k]
        for kk in (-9, 3):
            s.inked_rect([x + w // 2 + kk, y, x + w // 2 + kk + 5, y + HEM - 1], WH, width=1)
            p.inked_rect([x + w // 2 + kk, y + HEM, x + w // 2 + kk + 5, y + 127], WH, width=1)
    fx, fy, _, _ = F()
    s.inked_rect([fx + 36, fy, fx + 91, fy + 8], WH)
    s.acc.d.rectangle([fx + 62, fy + 8, fx + 65, fy + HEM - 1], fill=(170, 170, 178, 255))
    s.inked_rect([fx + 59, fy + 10, fx + 68, fy + 18], (200, 200, 206, 255), width=1)
    s.limb_band(s.tone, HAND - 8, HAND, tone(60))
    p.torso_band(p.tone, HEM, HEM + 10, tone(60))
    p.limb_band(p.tone, HAND - 6, HAND, tone(60))
    return s, p


def sweater():
    s, p = Tpl("shirt"), Tpl("pants")
    for k, (x, y, w, _) in s.torso_faces():  # an accent knit band of zigzags across the chest
        s.inked_rect([x, y + 26, x + w - 1, y + 44], FULL)
        for j in range(0, w, 12):
            s.ink.d.line([(x + j, y + 44), (x + j + 6, y + 30), (x + j + 12, y + 44)], fill=INK, width=2)
    for _, _, (x, y, w, _) in s.limb_faces():
        s.inked_rect([x, y + 28, x + w - 1, y + 38], FULL)
    s.torso_band(s.tone, 0, 8, tone(60))
    s.torso_band(s.tone, HEM - 10, HEM, tone(50))
    s.limb_band(s.tone, HAND - 12, HAND, tone(50))
    for _, (x, y, w, _) in s.torso_faces():
        for j in range(0, w, 4):
            s.tone.d.line([(x + j, y + HEM - 10), (x + j, y + HEM - 1)], fill=tone(40), width=1)
    belt(p, fill=(70, 56, 44, 255), buckle=MIDT)
    return s, p


def jersey():
    s, p = Tpl("shirt"), Tpl("pants")
    fx, fy, _, _ = F()
    bx, by, _, _ = B()
    # an accent shoulder yoke, sleeve bands and a big number 7 on the back (a team look, no team)
    for x0, y0 in ((fx, fy), (bx, by)):
        s.inked_poly([(x0, y0), (x0 + 127, y0), (x0 + 127, y0 + 14), (x0 + 64, y0 + 24), (x0, y0 + 14)], FULL)
    s.inked_poly([(bx + 40, by + 34), (bx + 88, by + 34), (bx + 88, by + 46), (bx + 64, by + 92), (bx + 50, by + 92),
                  (bx + 72, by + 46), (bx + 40, by + 46)], FULL)
    s.inked_poly([(fx + 86, fy + 66), (fx + 104, fy + 66), (fx + 104, fy + 70), (fx + 96, fy + 88), (fx + 91, fy + 88),
                  (fx + 98, fy + 70), (fx + 86, fy + 70)], FULL, width=1)
    s.limb_band(s.acc, 34, 44, FULL)
    s.limb_line(s.ink, 34, INK)
    s.limb_line(s.ink, 44, INK)
    s.limb_band(s.tone, 44, HAND, tone(0))
    for k in ("R", "L"):
        x, y, w, _ = TORSO[k]
        s.inked_rect([x + w // 2 - 6, y, x + w // 2 + 5, y + HEM - 1], FULL)
    belt(p, fill=MIDT, shape="rect")
    p.stripe(p.acc, p.outer(), 0, 50, 10, FULL)
    p.limb_band(p.acc, HAND - 30, HAND, LITE)  # high socks
    p.limb_line(p.ink, HAND - 30, INK)
    p.limb_band(p.ink, HAND - 24, HAND - 20, INK)
    return s, p


def varsity():
    # tinted white: white ribbed cuffs and hem with dark stripes, a white star patch on the chest
    s, p = Tpl("shirt"), Tpl("pants")
    WH = (244, 244, 246, 255)
    fx, fy, _, _ = F()
    s.inked_poly(star(fx + 26, fy + 30, 16), WH)
    for t, a, b in ((s, HAND - 12, HAND),):
        t.limb_band(t.acc, a, b, WH)
        t.limb_band(t.acc, a + 4, a + 7, INK)
    s.torso_band(s.acc, HEM - 12, HEM, WH)
    s.torso_band(s.acc, HEM - 8, HEM - 5, INK)
    s.inked_rect([fx + 36, fy, fx + 91, fy + 8], WH)
    for k in range(5):
        s.inked_ellipse([fx + 64, fy + 16 + k * 16, fx + 70, fy + 22 + k * 16], WH, width=1)
    s.ink.d.line([(fx + 62, fy + 8), (fx + 62, fy + HEM - 12)], fill=INK, width=2)
    belt(p, fill=(70, 56, 44, 255), buckle=MIDT)
    p.limb_band(p.tone, HAND - 6, HAND, tone(50))
    return s, p


def puffer():
    s, p = Tpl("shirt"), Tpl("pants")
    for _, (x, y, w, _) in s.torso_faces():  # quilting lines between the puffs (the parts)
        for k in range(16, HEM, 24):
            s.ink.d.line([(x, y + k), (x + w - 1, y + k)], fill=INK, width=2)
            s.tone.d.rectangle([x, y + k - 4, x + w - 1, y + k + 3], fill=tone(40))
    for _, _, (x, y, w, _) in s.limb_faces():
        for k in (24, 54, 82):
            s.ink.d.line([(x, y + k), (x + w - 1, y + k)], fill=INK, width=2)
    fx, fy, _, _ = F()
    s.inked_rect([fx + 62, fy, fx + 65, fy + HEM - 1], FULL, width=1)
    s.inked_rect([fx + 36, fy, fx + 91, fy + 9], LITE)
    s.limb_band(s.tone, HAND - 8, HAND, tone(70))
    belt(p, fill=(70, 56, 44, 255), buckle=MIDT)
    return s, p


def overalls():
    # the shirt is tinted s: the bib and straps over the p top, brass buttons, a bib pocket
    s, p = Tpl("shirt"), Tpl("pants")
    fx, fy, _, _ = F()
    bx, by, _, _ = B()
    s.inked_rect([fx + 30, fy + 44, fx + 97, fy + HEM - 1], FULL)
    s.inked_rect([fx + 46, fy + 54, fx + 81, fy + 74], LITE, width=1)
    for px in (fx + 30, fx + 82):
        s.inked_rect([px, fy, px + 15, fy + 44], FULL)
        s.inked_ellipse([px + 2, fy + 42, px + 13, fy + 53], (230, 200, 120, 255))
    s.inked_poly([(bx + 30, by), (bx + 45, by), (bx + 82, by + 60), (bx + 97, by + 60), (bx + 97, by + 72), (bx + 30, by + 72)], FULL)
    s.inked_poly([(bx + 97, by), (bx + 82, by), (bx + 45, by + 60), (bx + 30, by + 60)], FULL)
    s.acc.d.rectangle([bx + 30, by + 72, bx + 97, by + HEM - 1], fill=FULL)
    for k in ("R", "L"):
        x, y, w, _ = TORSO[k]
        s.inked_rect([x + 6, y + 70, x + w - 7, y + HEM - 1], FULL)
    belt(p, fill=MIDT, buckle=LITE, r0=HEM, r1=HEM + 8)
    p.limb_band(p.acc, HAND - 14, HAND - 4, LITE)  # rolled hems
    p.limb_line(p.ink, HAND - 14, INK)
    for x, y, w, _ in p.fronts():
        p.tone.d.line([(x + 12, y + 2), (x + 24, y + 20)], fill=tone(80), width=2)
    return s, p


def bomber():
    # tinted white: dark ribbed collar, cuffs and hem, a zip and a sleeve pocket with a zip pull
    s, p = Tpl("shirt"), Tpl("pants")
    RIB = (52, 52, 58, 255)
    fx, fy, _, _ = F()
    s.inked_rect([fx + 28, fy, fx + 99, fy + 10], (236, 230, 214, 255))  # the fleece collar
    for k in range(32, 96, 6):
        s.acc.d.line([(fx + k, fy + 2), (fx + k + 2, fy + 8)], fill=(200, 192, 176, 255), width=1)
    s.torso_band(s.acc, HEM - 10, HEM, RIB)
    s.limb_band(s.acc, HAND - 10, HAND, RIB)
    for _, (x, y, w, _) in s.torso_faces():
        for j in range(0, w, 4):
            s.acc.d.line([(x + j, y + HEM - 10), (x + j, y + HEM - 1)], fill=(70, 70, 76, 255), width=1)
    s.acc.d.rectangle([fx + 62, fy + 10, fx + 65, fy + HEM - 11], fill=(170, 170, 176, 255))
    x, y, w, _ = LEFT["L"]
    s.inked_rect([x + 14, y + 12, x + 49, y + 32], (120, 120, 126, 255), layer=s.tone)
    s.acc.d.rectangle([x + 16, y + 14, x + 18, y + 26], fill=(170, 170, 176, 255))
    for px in (fx + 12, fx + 94):
        s.ink.d.line([(px, fy + 74), (px + 22, fy + 70)], fill=INK, width=3)
    belt(p, fill=(60, 52, 46, 255), buckle=MIDT)
    return s, p


def vest():
    # the shirt is tinted s: an open waistcoat over the p top (arms bare), welt pockets and buttons
    s, p = Tpl("shirt"), Tpl("pants")
    fx, fy, _, _ = F()
    s.inked_poly([(fx, fy), (fx + 34, fy), (fx + 60, fy + 58), (fx + 58, fy + HEM - 1), (fx, fy + HEM - 1)], FULL)
    s.inked_poly([(fx + 127, fy), (fx + 93, fy), (fx + 68, fy + 58), (fx + 70, fy + HEM - 1), (fx + 127, fy + HEM - 1)], FULL)
    for k in ("R", "L", "B"):
        x, y, w, _ = TORSO[k]
        s.acc.d.rectangle([x, y, x + w - 1, y + HEM - 1], fill=FULL)
    for k in range(3):
        s.inked_ellipse([fx + 52, fy + 62 + k * 12, fx + 57, fy + 67 + k * 12], DEEP, width=1)
    for px in (fx + 14, fx + 86):
        s.ink.d.line([(px, fy + 70), (px + 24, fy + 70)], fill=INK, width=3)
    bx, by, _, _ = B()
    s.inked_rect([bx + 40, by + 60, bx + 87, by + 66], LITE)  # the back strap
    belt(p, fill=(60, 52, 46, 255), buckle=MIDT)
    p.limb_band(p.tone, HAND - 6, HAND, tone(50))
    return s, p


def trench():
    # tinted white: double-breasted buttons, a belt with a square buckle, epaulettes, a storm flap
    s, p = Tpl("shirt"), Tpl("pants")
    BTN = (60, 50, 40, 255)
    fx, fy, _, _ = F()
    s.tone.d.polygon([(fx + 20, fy), (fx + 108, fy), (fx + 96, fy + 36), (fx + 32, fy + 36)], fill=tone(30))
    s.ink.d.polygon([(fx + 20, fy), (fx + 108, fy), (fx + 96, fy + 36), (fx + 32, fy + 36)], outline=INK)
    s.ink.d.line([(fx + 78, fy + 36), (fx + 78, fy + HEM - 1)], fill=INK, width=2)
    for k in range(3):
        for px in (fx + 50, fx + 90):
            s.inked_ellipse([px, fy + 44 + k * 18, px + 7, fy + 51 + k * 18], BTN, width=1)
    s.torso_band(s.acc, 82, 94, (150, 140, 120, 255))
    s.torso_band(s.ink, 81, 83, INK)
    s.torso_band(s.ink, 93, 95, INK)
    s.inked_rect([fx + 56, fy + 80, fx + 71, fy + 96], (200, 190, 160, 255))
    s.inked_rect([fx + 60, fy + 84, fx + 67, fy + 92], (150, 140, 120, 255))
    for x, y, w, _ in s.outer():
        s.inked_rect([x + 8, y + 2, x + w - 9, y + 10], (150, 140, 120, 255))
    s.limb_band(s.acc, HAND - 20, HAND - 14, (150, 140, 120, 255))
    s.limb_line(s.ink, HAND - 20, INK)
    belt(p, fill=(60, 52, 46, 255), buckle=MIDT)
    return s, p


def gi():
    # tinted white: the crossed lapel's edge, a black belt with its knot and tails
    s, p = Tpl("shirt"), Tpl("pants")
    fx, fy, _, _ = F()
    s.tone.d.polygon([(fx + 30, fy), (fx + 44, fy), (fx + 86, fy + HEM - 1), (fx + 70, fy + HEM - 1)], fill=tone(40))
    s.ink.d.line([(fx + 30, fy), (fx + 70, fy + HEM - 1)], fill=INK, width=2)
    s.ink.d.line([(fx + 44, fy), (fx + 86, fy + HEM - 1)], fill=INK, width=2)
    s.ink.d.line([(fx + 98, fy), (fx + 66, fy + 54)], fill=INK, width=2)
    s.limb_band(s.tone, 60, 62, tone(80))
    for k in range(0, 128, 6):
        s.tone.d.line([(fx + k, fy + 4), (fx + k + 3, fy + HEM - 1)], fill=tone(10), width=1)
    BLK = (30, 28, 30, 255)
    p.torso_band(p.acc, HEM + 2, HEM + 12, BLK)
    x, y, _, _ = F()
    p.inked_rect([x + 54, y + HEM, x + 73, y + HEM + 14], BLK)
    p.inked_poly([(x + 56, y + HEM + 12), (x + 64, y + HEM + 12), (x + 58, y + 127), (x + 48, y + 127)], BLK)
    p.inked_poly([(x + 64, y + HEM + 12), (x + 72, y + HEM + 12), (x + 80, y + 127), (x + 70, y + 127)], BLK)
    p.limb_line(p.tone, 60, tone(70))
    return s, p


def labcoat():
    s, p = Tpl("shirt"), Tpl("pants")
    fx, fy, _, _ = F()
    s.inked_poly([(fx + 30, fy), (fx + 44, fy), (fx + 58, fy + 44), (fx + 46, fy + 36)], LITE, layer=s.tone)
    s.inked_poly([(fx + 98, fy), (fx + 84, fy), (fx + 70, fy + 44), (fx + 82, fy + 36)], LITE, layer=s.tone)
    s.ink.d.line([(fx + 64, fy + 44), (fx + 64, fy + HEM - 1)], fill=INK, width=2)
    for k in range(3):
        s.inked_ellipse([fx + 67, fy + 52 + k * 16, fx + 72, fy + 57 + k * 16], MIDT, width=1)
    s.ink.d.rectangle([fx + 84, fy + 40, fx + 106, fy + 60], outline=INK, width=2)
    s.inked_rect([fx + 88, fy + 32, fx + 91, fy + 46], FULL, width=1)  # accent pens
    s.inked_rect([fx + 95, fy + 34, fx + 98, fy + 46], LITE, width=1)
    for px in (fx + 10, fx + 90):
        s.ink.d.rectangle([px, fy + 74, px + 26, fy + 92], outline=INK, width=2)
    belt(p, fill=(60, 52, 46, 255), buckle=MIDT)
    return s, p


def fatigues():
    # tinted white: tone camo blots over the s paint, chest pockets, a webbing belt
    s, p = Tpl("shirt"), Tpl("pants")
    camo(s, 3)
    camo(p, 4)
    fx, fy, _, _ = F()
    for px in (fx + 12, fx + 86):
        pocket(s, px, fy + 20, 30, 24)
    for x, y, w, _ in p.outer():
        pocket(p, x + 12, y + 18, w - 24, 26)
    s.limb_band(s.tone, 40, 46, tone(70))  # rolled sleeves
    s.limb_line(s.ink, 40, INK)
    belt(p, fill=(110, 104, 80, 255), buckle=MIDT)
    p.limb_band(p.acc, HAND - 22, HAND, (60, 50, 40, 255))  # boots
    p.limb_line(p.ink, HAND - 22, INK)
    return s, p


def racing():
    s, p = Tpl("shirt"), Tpl("pants")
    fx, fy, _, _ = F()
    bx, by, _, _ = B()
    for x0, y0 in ((fx, fy), (bx, by)):  # a diagonal accent band and checker panels (generic, no brands)
        s.inked_poly([(x0, y0 + 60), (x0 + 127, y0 + 20), (x0 + 127, y0 + 42), (x0, y0 + 82)], FULL)
    for i in range(4):
        for j in range(2):
            if (i + j) % 2 == 0:
                s.inked_rect([fx + 92 + i * 8, fy + 70 + j * 8, fx + 99 + i * 8, fy + 77 + j * 8], FULL, width=1)
    s.stripe(s.acc, s.outer(), 0, HAND, 12, FULL)
    p.stripe(p.acc, p.outer(), 0, HAND, 12, FULL)
    for t in (s, p):
        t.stripe(t.ink, t.outer(), 0, HAND, 2, INK, -7)
        t.stripe(t.ink, t.outer(), 0, HAND, 2, INK, 6)
    s.inked_rect([fx + 36, fy, fx + 91, fy + 7], FULL)
    belt(p, fill=MIDT)
    p.limb_band(p.tone, HAND - 6, HAND, tone(70))
    return s, p


def wetsuit():
    s, p = Tpl("shirt"), Tpl("pants")
    for k in ("R", "L"):  # accent side panels down the torso and legs
        x, y, w, _ = TORSO[k]
        s.inked_poly([(x + 14, y), (x + 50, y), (x + 42, y + HEM - 1), (x + 22, y + HEM - 1)], FULL)
        p.inked_rect([x + 22, y + HEM, x + 41, y + 127], FULL)
    for t in (s, p):
        for x, y, w, _ in t.outer():
            t.inked_poly([(x + 18, y), (x + 46, y), (x + 40, y + HAND - 1), (x + 24, y + HAND - 1)], FULL)
    fx, fy, _, _ = F()
    s.inked_poly([(fx + 10, fy), (fx + 118, fy), (fx + 100, fy + 18), (fx + 28, fy + 18)], FULL)
    s.inked_poly([(fx, fy + 52), (fx + 34, fy + 40), (fx + 34, fy + 52), (fx, fy + 64)], FULL)  # front swoosh panels
    s.inked_poly([(fx + 127, fy + 52), (fx + 93, fy + 40), (fx + 93, fy + 52), (fx + 127, fy + 64)], FULL)
    for x, y, w, _ in s.fronts():
        s.inked_rect([x, y + 34, x + w - 1, y + 44], FULL)
    for x, y, w, _ in p.fronts():
        p.inked_rect([x + 8, y + 38, x + w - 9, y + 58], FULL)  # knee pads
        p.inked_rect([x + 14, y + 44, x + w - 15, y + 52], LITE, width=1)
    bx, by, _, _ = B()
    s.acc.d.rectangle([bx + 62, by, bx + 65, by + 70], fill=DEEP)  # the back zip and its cord
    s.inked_ellipse([bx + 58, by + 68, bx + 69, by + 78], LITE, width=1)
    for k in range(0, 60, 12):
        s.tone.d.line([(fx + 24 + k, fy + 40), (fx + 40 + k, fy + 90)], fill=tone(24), width=3)
    return s, p


def kimono():
    # the shirt is tinted s: the overlapping collar band, an obi with its cord, a wave print (tone)
    s, p = Tpl("shirt"), Tpl("pants")
    fx, fy, _, _ = F()
    s.inked_poly([(fx + 26, fy), (fx + 42, fy), (fx + 96, fy + 84), (fx + 80, fy + 84)], FULL)
    s.inked_poly([(fx + 102, fy), (fx + 86, fy), (fx + 62, fy + 40), (fx + 70, fy + 50)], FULL)
    bx, by, _, _ = B()
    s.inked_rect([bx + 30, by, bx + 97, by + 10], FULL)
    s.torso_band(s.acc, 84, HEM, FULL)
    s.torso_band(s.ink, 83, 85, INK)
    s.inked_rect([fx + 50, fy + 88, fx + 77, fy + 92], LITE, width=1)
    for _, _, (x, y, w, h) in s.limb_faces():
        for j in range(3):
            s.tone.d.arc([x + 6 + j * 18, y + 60, x + 26 + j * 18, y + 80], 180, 360, fill=tone(60), width=3)
    for j in range(5):
        s.tone.d.arc([fx + 6 + j * 24, fy + 56, fx + 30 + j * 24, fy + 80], 180, 360, fill=tone(50), width=3)
    s.limb_band(s.acc, HAND - 8, HAND, FULL)
    s.limb_line(s.ink, HAND - 8, INK)
    p.torso_band(p.acc, HEM, HEM + 8, FULL)
    p.torso_band(p.ink, HEM + 8, HEM + 10, INK)
    for _, _, (x, y, w, h) in p.limb_faces():
        for j in range(3):
            p.tone.d.arc([x + 6 + j * 18, y + 30, x + 26 + j * 18, y + 50], 180, 360, fill=tone(50), width=3)
    return s, p


def shinobi():
    # tinted s: wrapped bands on the forearms and shins, a sash with a knot, a cross-tied collar
    s, p = Tpl("shirt"), Tpl("pants")
    fx, fy, _, _ = F()
    s.inked_poly([(fx + 30, fy), (fx + 44, fy), (fx + 84, fy + 60), (fx + 70, fy + 60)], FULL)
    s.inked_poly([(fx + 98, fy), (fx + 84, fy), (fx + 58, fy + 40), (fx + 66, fy + 50)], FULL)
    for t, r0 in ((s, ELBOW + 4), (p, ELBOW)):
        for _, _, (x, y, w, h) in t.limb_faces():
            for k in range(4):
                yy = y + r0 + k * 12
                t.acc.d.polygon([(x, yy + 4), (x + w - 1, yy), (x + w - 1, yy + 8), (x, yy + 12)], fill=FULL)
                t.ink.d.line([(x, yy + 12), (x + w - 1, yy + 8)], fill=INK, width=2)
    p.torso_band(p.acc, HEM, HEM + 14, FULL)
    p.torso_band(p.ink, HEM + 14, HEM + 16, INK)
    x, y, _, _ = F()
    p.inked_poly([(x + 88, y + HEM + 10), (x + 98, y + HEM + 10), (x + 104, y + 127), (x + 92, y + 127)], LITE)
    return s, p


def ranger():
    # tinted white: crossed leather straps and buckles, pouches, a wide belt
    s, p = Tpl("shirt"), Tpl("pants")
    LEA = (100, 66, 40, 255)
    MET = (200, 196, 180, 255)
    fx, fy, _, _ = F()
    bx, by, _, _ = B()
    for x0, y0 in ((fx, fy), (bx, by)):
        s.inked_poly([(x0 + 4, y0), (x0 + 20, y0), (x0 + 124, y0 + 92), (x0 + 124, y0 + HEM - 1), (x0 + 110, y0 + HEM - 1), (x0 + 4, y0 + 14)], LEA)
        s.inked_poly([(x0 + 123, y0), (x0 + 107, y0), (x0 + 3, y0 + 92), (x0 + 3, y0 + HEM - 1), (x0 + 17, y0 + HEM - 1), (x0 + 123, y0 + 14)], LEA)
    s.inked_rect([fx + 56, fy + 44, fx + 71, fy + 58], MET)
    for px in (fx + 16, fx + 92):
        s.inked_rect([px, fy + 70, px + 20, fy + 90], LEA)
    belt(p, fill=LEA, buckle=MET, r0=HEM, r1=HEM + 14)
    for x, y, w, _ in p.outer():
        p.inked_rect([x + 8, y + 10, x + w - 9, y + 16], LEA)
        p.inked_rect([x + 14, y + 16, x + w - 15, y + 34], LEA)
    p.limb_band(p.acc, HAND - 26, HAND, (70, 50, 34, 255))
    p.limb_line(p.ink, HAND - 26, INK)
    return s, p


def tux():
    # tinted white: the white shirt front, satin lapels, a black bow tie, studs
    s, p = Tpl("shirt"), Tpl("pants")
    WH = (248, 248, 250, 255)
    fx, fy, _, _ = F()
    s.inked_poly([(fx + 40, fy), (fx + 88, fy), (fx + 74, fy + 76), (fx + 54, fy + 76)], WH)
    s.inked_poly([(fx + 28, fy), (fx + 40, fy), (fx + 58, fy + 80), (fx + 44, fy + 60)], (80, 80, 90, 255))
    s.inked_poly([(fx + 100, fy), (fx + 88, fy), (fx + 70, fy + 80), (fx + 84, fy + 60)], (80, 80, 90, 255))
    s.inked_poly([(fx + 52, fy + 4), (fx + 64, fy + 10), (fx + 76, fy + 4), (fx + 76, fy + 18), (fx + 64, fy + 12), (fx + 52, fy + 18)], (24, 24, 28, 255))
    for k in range(3):
        s.inked_ellipse([fx + 62, fy + 28 + k * 14, fx + 66, fy + 32 + k * 14], (30, 30, 34, 255), width=1)
    s.inked_rect([fx + 92, fy + 30, fx + 108, fy + 34], WH, width=1)  # pocket square
    s.limb_band(s.acc, HAND - 4, HAND, WH)
    p.stripe(p.acc, p.outer(), 0, HAND, 4, (90, 90, 100, 255))  # the satin trouser stripe
    p.torso_band(p.tone, HEM, HEM + 10, tone(40))
    return s, p


def space():
    s, p = Tpl("shirt"), Tpl("pants")
    fx, fy, _, _ = F()
    # segmented joints, an accent mission patch on the shoulder (a ringed planet), hose ports, knee pads
    for _, _, (x, y, w, h) in s.limb_faces():
        for k in (ELBOW - 8, ELBOW - 2, ELBOW + 4):
            s.ink.d.line([(x, y + k), (x + w - 1, y + k)], fill=(20, 20, 30, 150), width=2)
    for _, _, (x, y, w, h) in p.limb_faces():
        for k in (ELBOW - 8, ELBOW - 2, ELBOW + 4):
            p.ink.d.line([(x, y + k), (x + w - 1, y + k)], fill=(20, 20, 30, 150), width=2)
    x, y, w, _ = LEFT["L"]
    s.inked_ellipse([x + 16, y + 8, x + 48, y + 40], FULL)
    s.inked_ellipse([x + 26, y + 18, x + 38, y + 30], LITE)
    s.ink.d.arc([x + 14, y + 18, x + 50, y + 30], 160, 380, fill=INK, width=2)
    for px in (fx + 14, fx + 104):
        s.inked_ellipse([px, fy + 66, px + 12, fy + 78], MIDT)
    s.stripe(s.acc, s.outer(), ELBOW + 6, HAND - 2, 8, FULL)
    belt(p, fill=MIDT, buckle=FULL, r0=HEM, r1=HEM + 12)
    for x, y, w, _ in p.fronts():
        p.inked_rect([x + 10, y + 36, x + w - 11, y + 60], LITE)
    p.limb_band(p.acc, HAND - 18, HAND, MIDT)
    p.limb_line(p.ink, HAND - 18, INK)
    return s, p


def plate():
    s, p = Tpl("shirt"), Tpl("pants")
    # chainmail (tone scales) on the arms and legs under the plate parts, a tabard edge and a cross-belt
    for t in (s, p):
        for _, _, (x, y, w, h) in t.limb_faces():
            for yy in range(0, 60, 6):
                for xx in range(0, w, 6):
                    ox = 3 if (yy // 6) % 2 else 0
                    t.tone.d.arc([x + xx + ox - 3, y + yy, x + xx + ox + 3, y + yy + 6], 0, 180, fill=tone(70), width=1)
    fx, fy, _, _ = F()
    s.acc.d.rectangle([fx + 38, fy + 60, fx + 89, fy + HEM - 1], fill=FULL)
    s.ink.d.rectangle([fx + 38, fy + 60, fx + 89, fy + HEM - 1], outline=INK, width=2)
    p.inked_poly([(fx + 38, fy + HEM), (fx + 89, fy + HEM), (fx + 84, fy + 127), (fx + 64, fy + 120), (fx + 44, fy + 127)], FULL)
    s.inked_poly([(fx + 56, fy + 70), (fx + 72, fy + 70), (fx + 72, fy + 78), (fx + 64, fy + 92), (fx + 56, fy + 78)], LITE)
    belt(p, fill=(90, 70, 50, 255), buckle=LITE, shape="round")
    p.limb_band(p.acc, HAND - 22, HAND, MIDT)
    p.limb_line(p.ink, HAND - 22, INK)
    s.limb_band(s.acc, HAND - 14, HAND, MIDT)
    return s, p


def exo():
    s, p = Tpl("shirt"), Tpl("pants")
    fx, fy, _, _ = F()
    # an exoskeleton's light lines and joint discs under its rods (the parts)
    for x0 in (fx + 30, fx + 98):
        s.acc.d.line([(x0, fy + 4), (x0, fy + HEM - 1)], fill=FULL, width=3)
    s.acc.d.line([(fx + 30, fy + 60), (fx + 64, fy + 74), (fx + 98, fy + 60)], fill=FULL, width=3)
    for t in (s, p):
        for x, y, w, _ in t.outer() + t.fronts():
            t.inked_ellipse([x + w // 2 - 8, y + ELBOW - 8, x + w // 2 + 8, y + ELBOW + 8], MIDT)
            t.inked_ellipse([x + w // 2 - 3, y + ELBOW - 3, x + w // 2 + 3, y + ELBOW + 3], FULL, width=1)
            t.acc.d.line([(x + w // 2, y + 4), (x + w // 2, y + ELBOW - 9)], fill=FULL, width=2)
            t.acc.d.line([(x + w // 2, y + ELBOW + 9), (x + w // 2, y + HAND - 4)], fill=FULL, width=2)
    bx, by, _, _ = B()
    s.inked_rect([bx + 44, by + 10, bx + 83, by + 60], MIDT)
    for k in range(4):
        s.ink.d.line([(bx + 48, by + 18 + k * 10), (bx + 79, by + 18 + k * 10)], fill=INK, width=2)
    belt(p, fill=DEEP, buckle=FULL, shape="diamond")
    return s, p


def cyber():
    s, p = Tpl("shirt"), Tpl("pants")
    fx, fy, _, _ = F()
    # angular tech plating outlines and accent light runs (with the glow lines as parts)
    for x0, y0 in ((fx, fy), (TORSO["B"][0], TORSO["B"][1])):
        s.ink.d.line([(x0 + 4, y0 + 30), (x0 + 24, y0 + 50), (x0 + 24, y0 + HEM - 1)], fill=INK, width=2)
        s.ink.d.line([(x0 + 123, y0 + 30), (x0 + 103, y0 + 50), (x0 + 103, y0 + HEM - 1)], fill=INK, width=2)
        s.acc.d.line([(x0 + 8, y0 + 34), (x0 + 28, y0 + 54), (x0 + 28, y0 + HEM - 1)], fill=FULL, width=2)
        s.acc.d.line([(x0 + 119, y0 + 34), (x0 + 99, y0 + 54), (x0 + 99, y0 + HEM - 1)], fill=FULL, width=2)
    for k in range(6):
        s.tone.d.polygon([(fx + 36 + k * 10, fy + 92), (fx + 42 + k * 10, fy + 82), (fx + 48 + k * 10, fy + 92)], fill=tone(60))
    for t in (s, p):
        for x, y, w, _ in t.outer():
            t.acc.d.line([(x + 6, y + 6), (x + w - 7, y + 30), (x + w - 7, y + 80), (x + 6, y + 100)], fill=FULL, width=2)
            t.ink.d.line([(x + 10, y + 6), (x + w - 3, y + 30)], fill=INK, width=1)
    belt(p, fill=DEEP, buckle=FULL, shape="diamond")
    p.limb_band(p.acc, HAND - 4, HAND, FULL)
    return s, p


def robe():
    s, p = Tpl("shirt"), Tpl("pants")
    fx, fy, _, _ = F()
    # accent trim with original rune dots along the opening, sleeves and hem; a rope belt with tassels
    s.inked_poly([(fx + 40, fy), (fx + 54, fy), (fx + 66, fy + HEM - 1), (fx + 52, fy + HEM - 1)], FULL)
    s.inked_poly([(fx + 88, fy), (fx + 74, fy), (fx + 66, fy + 40), (fx + 72, fy + 50)], FULL)
    for k in range(6):
        cy = fy + 10 + k * 15
        s.ink.d.ellipse([fx + 45 + k * 2, cy, fx + 50 + k * 2, cy + 5], fill=INK)
    s.limb_band(s.acc, HAND - 14, HAND, FULL)
    s.limb_line(s.ink, HAND - 14, INK)
    for _, _, (x, y, w, h) in s.limb_faces():
        for k in range(0, w, 12):
            s.ink.d.polygon([(x + k + 2, y + HAND - 8), (x + k + 6, y + HAND - 12), (x + k + 10, y + HAND - 8), (x + k + 6, y + HAND - 4)], fill=INK)
    ROPE = (230, 200, 120, 255)
    p.torso_band(p.acc, HEM + 2, HEM + 8, ROPE)
    p.torso_band(p.ink, HEM + 1, HEM + 2, INK)
    p.torso_band(p.ink, HEM + 8, HEM + 9, INK)
    x, y, _, _ = F()
    for px in (x + 30, x + 40):
        p.inked_rect([px, y + HEM + 8, px + 3, y + 120], ROPE, width=1)
        p.inked_poly([(px - 3, y + 118), (px + 6, y + 118), (px + 8, y + 127), (px - 5, y + 127)], ROPE, width=1)
    p.limb_band(p.acc, HAND - 12, HAND, FULL)
    p.limb_line(p.ink, HAND - 12, INK)
    return s, p


def royal():
    # tinted gold: braided frogging across the chest, epaulette fringes, cuffs and a trouser stripe
    s, p = Tpl("shirt"), Tpl("pants")
    fx, fy, _, _ = F()
    s.inked_rect([fx + 60, fy, fx + 67, fy + HEM - 1], FULL)
    for k in range(4):
        yy = fy + 30 + k * 16
        for sgn in (-1, 1):
            s.acc.d.line([(fx + 64 + sgn * 6, yy), (fx + 64 + sgn * 34, yy)], fill=FULL, width=3)
            s.ink.d.line([(fx + 64 + sgn * 6, yy + 2), (fx + 64 + sgn * 34, yy + 2)], fill=INK, width=1)
            s.inked_ellipse([fx + 64 + sgn * 36 - 3, yy - 3, fx + 64 + sgn * 36 + 3, yy + 3], LITE, width=1)
    s.torso_band(s.acc, 0, 7, FULL)
    s.torso_band(s.ink, 7, 9, INK)
    for x, y, w, _ in s.outer():
        s.inked_rect([x + 2, y, x + w - 3, y + 10], FULL)
        for k in range(4, w - 4, 5):
            s.acc.d.line([(x + k, y + 10), (x + k, y + 20)], fill=LITE, width=2)
    s.limb_band(s.acc, HAND - 14, HAND, FULL)
    s.limb_line(s.ink, HAND - 14, INK)
    p.stripe(p.acc, p.outer(), 0, HAND, 8, FULL)
    p.stripe(p.ink, p.outer(), 0, HAND, 2, INK)
    belt(p, fill=MIDT, buckle=FULL, shape="round")
    return s, p


def magma():
    # tinted glowRed: glowing lava cracks (a hot core line in a wider glow) over the dark rock body
    s, p = Tpl("shirt"), Tpl("pants")
    rnd = random.Random(31)

    def cracks(t, regions, n):
        for x, y, w, h in regions:
            for _ in range(n):
                px, py = rnd.uniform(x + 4, x + w - 4), rnd.uniform(y, y + h * 0.4)
                pts = [(px, py)]
                for _ in range(5):
                    px += rnd.uniform(-16, 16)
                    py += rnd.uniform(8, 20)
                    pts.append((px, py))
                    if rnd.random() < 0.35:  # a side branch
                        bx, by = px + rnd.choice((-1, 1)) * rnd.uniform(8, 18), py + rnd.uniform(4, 12)
                        t.acc.d.line([(px, py), (bx, by)], fill=MIDT, width=4)
                        t.acc.d.line([(px, py), (bx, by)], fill=FULL, width=2)
                t.acc.d.line(pts, fill=(170, 170, 170, 150), width=11, joint="curve")
                t.acc.d.line(pts, fill=MIDT, width=6, joint="curve")
                t.acc.d.line(pts, fill=FULL, width=3, joint="curve")

    torso = [(x, y, w, HEM) for _, (x, y, w, _) in s.torso_faces()]
    cracks(s, torso, 3)
    cracks(s, [r for _, _, r in s.limb_faces()], 2)
    cracks(p, [r for _, _, r in p.limb_faces()], 2)
    clip(s, s.acc, torso + [r for _, _, r in s.limb_faces()])
    clip(p, p.acc, [r for _, _, r in p.limb_faces()])
    return s, p


def frost():
    # tinted ice: frost crystals spreading from the shoulders, cuffs and boots
    s, p = Tpl("shirt"), Tpl("pants")
    import math

    def flake(t, cx, cy, r, c=MIDT):
        for k in range(6):
            a = math.radians(k * 60)
            x1, y1 = cx + r * math.cos(a), cy + r * math.sin(a)
            t.acc.d.line([(cx, cy), (x1, y1)], fill=c, width=2)
            for f in (0.5,):
                bx, by = cx + r * f * math.cos(a), cy + r * f * math.sin(a)
                for da in (-40, 40):
                    a2 = a + math.radians(da)
                    t.acc.d.line([(bx, by), (bx + r * 0.3 * math.cos(a2), by + r * 0.3 * math.sin(a2))], fill=c, width=2)

    fx, fy, _, _ = F()
    for cx, cy, r in ((fx + 14, fy + 12, 14), (fx + 112, fy + 14, 12), (fx + 26, fy + 80, 9), (fx + 104, fy + 74, 10)):
        flake(s, cx, cy, r)
    for t, a in ((s, HAND - 18), (p, HAND - 26)):
        for _, _, (x, y, w, h) in t.limb_faces():
            pts = [(x, y + a + 10)]
            for k in range(0, w, 8):
                pts.append((x + k + 4, y + a + (0 if (k // 8) % 2 else 12)))
            pts += [(x + w - 1, y + a + 10), (x + w - 1, y + HAND - 1), (x, y + HAND - 1)]
            t.inked_poly(pts, LITE, width=1)
    s.torso_band(s.acc, 0, 5, LITE)
    p.torso_band(p.acc, HEM + 2, HEM + 8, MIDT)
    return s, p


def starfield():
    # tinted white: stars of three sizes and faint nebula swirls over the dark body
    s, p = Tpl("shirt"), Tpl("pants")
    rnd = random.Random(77)

    def sky(t, regions, n):
        for x, y, w, h in regions:
            for _ in range(2):
                cx, cy = rnd.uniform(x, x + w), rnd.uniform(y, y + h)
                t.tone.d.ellipse([cx - 26, cy - 12, cx + 26, cy + 12], fill=(160, 170, 255, 34))
            for _ in range(n):
                cx, cy = rnd.uniform(x + 3, x + w - 3), rnd.uniform(y + 3, y + h - 3)
                r = rnd.choice((1, 1, 1, 2, 2, 4))
                if r >= 4:
                    t.acc.d.polygon(star(cx, cy, 5, 1.6, 4, 0), fill=(255, 255, 255, 255))
                else:
                    t.acc.d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(240, 240, 255, 255))

    sr = [(x, y, w, HEM) for _, (x, y, w, _) in s.torso_faces()]
    pr = [(x, y + HEM, w, 128 - HEM) for _, (x, y, w, _) in p.torso_faces()]
    sky(s, sr, 26)
    sky(s, [r for _, _, r in s.limb_faces()], 14)
    sky(p, pr, 5)
    sky(p, [r for _, _, r in p.limb_faces()], 14)
    for t, rr in ((s, sr), (p, pr)):
        rr = rr + [r for _, _, r in t.limb_faces()]
        clip(t, t.acc, rr)
        clip(t, t.tone, rr)
    return s, p


def night_tux():
    # tinted gold (Hero Pass season 1, Opening Night): gold lapels and a star pin, a gold cummerbund
    s, p = Tpl("shirt"), Tpl("pants")
    WH = (250, 246, 236, 255)
    fx, fy, _, _ = F()
    s.inked_poly([(fx + 40, fy), (fx + 88, fy), (fx + 74, fy + 76), (fx + 54, fy + 76)], WH)
    s.inked_poly([(fx + 28, fy), (fx + 40, fy), (fx + 58, fy + 80), (fx + 44, fy + 60)], FULL)
    s.inked_poly([(fx + 100, fy), (fx + 88, fy), (fx + 70, fy + 80), (fx + 84, fy + 60)], FULL)
    s.inked_poly([(fx + 52, fy + 4), (fx + 64, fy + 10), (fx + 76, fy + 4), (fx + 76, fy + 18), (fx + 64, fy + 12), (fx + 52, fy + 18)], (30, 26, 24, 255))
    s.inked_poly(star(fx + 100, fy + 40, 8), FULL, width=1)
    s.torso_band(s.acc, 84, HEM, FULL)
    s.torso_band(s.ink, 83, 85, INK)
    for k in range(3):
        s.ink.d.line([(fx, fy + 90 + k * 4), (fx + 127, fy + 90 + k * 4)], fill=(20, 20, 30, 120), width=1)
    s.limb_band(s.acc, HAND - 6, HAND, FULL)
    p.stripe(p.acc, p.outer(), 0, HAND, 5, FULL)
    p.torso_band(p.acc, HEM, HEM + 8, FULL)
    return s, p


# kit -> (drawing, shirt tint, pants tint, keep the kit's parts, body paint (torso, arms, legs) for the previews)
SUITS = {
    "plain": (plain, "a", "a", False, ("p", "p", "s")),
    "stripe": (stripe, "a", "a", False, ("p", "p", "s")),
    "split": (split, "a", "a", False, ("p", "s", "s")),
    "chevron": (chevron, "a", "a", False, ("p", "p", "p")),
    "jacket": (jacket, "p", "white", False, ("s", "p", "dark")),
    "armor": (armor, "a", "a", True, ("p", "s", "s")),
    "core": (core, "a", "a", True, ("p", "p", "s")),
    "circuit": (circuit, "a", "a", True, ("dark", "dark", "dark")),
    "sash": (sash, "a", "a", False, ("p", "p", "s")),
    "ribs": (ribs, "white", "white", False, ("dark", "p", "dark")),
    "panel": (panel_suit, "a", "a", True, ("p", "s", "p")),
    "bolt": (bolt, "a", "a", False, ("p", "s", "p")),
    "bulwark": (bulwark, "a", "a", True, ("s", "p", "s")),
    "neon": (neon_suit, "a", "a", True, ("dark", "dark", "dark")),
    "chrome": (chrome, "white", "white", False, ("p", "p", "p")),
    "tee": (tee, "a", "white", True, ("p", "skin", "s")),
    "tank": (tank, "white", "white", False, ("p", "skin", "s")),
    "hoodie": (hoodie, "a", "white", True, ("p", "p", "s")),
    "tracksuit": (tracksuit, "white", "white", False, ("p", "p", "p")),
    "sweater": (sweater, "a", "white", False, ("p", "p", "s")),
    "jersey": (jersey, "a", "a", False, ("p", "p", "s")),
    "varsity": (varsity, "white", "white", False, ("p", "s", "s")),
    "puffer": (puffer, "white", "white", True, ("p", "p", "s")),
    "overalls": (overalls, "s", "white", False, ("p", "p", "s")),
    "bomber": (bomber, "white", "white", False, ("s", "s", "dark")),
    "vest": (vest, "s", "white", False, ("p", "skin", "s")),
    "trench": (trench, "white", "white", True, ("s", "s", "dark")),
    "gi": (gi, "white", "white", False, ("white", "white", "white")),
    "labcoat": (labcoat, "a", "white", True, ("white", "white", "dark")),
    "fatigues": (fatigues, "white", "white", False, ("s", "s", "s")),
    "racing": (racing, "a", "a", False, ("p", "s", "p")),
    "wetsuit": (wetsuit, "a", "a", False, ("dark", "dark", "dark")),
    "kimono": (kimono, "s", "s", True, ("p", "p", "p")),
    "shinobi": (shinobi, "s", "s", False, ("dark", "dark", "dark")),
    "ranger": (ranger, "white", "white", False, ("s", "s", "dark")),
    "tux": (tux, "white", "white", False, ("dark", "dark", "dark")),
    "spacesuit": (space, "a", "a", True, ("white", "white", "white")),
    "plate": (plate, "a", "a", True, ("s", "s", "s")),
    "exo": (exo, "a", "a", True, ("dark", "dark", "dark")),
    "cyber": (cyber, "a", "a", True, ("dark", "dark", "dark")),
    "robe": (robe, "a", "a", True, ("p", "p", "p")),
    "royal": (royal, "gold", "gold", False, ("p", "p", "s")),
    "magma": (magma, "glowRed", "glowRed", True, ("dark", "dark", "dark")),
    "frost": (frost, "ice", "ice", True, ("white", "white", "white")),
    "starfield": (starfield, "white", "white", True, ("dark", "dark", "dark")),
    "nightTux": (night_tux, "gold", "gold", False, ("dark", "dark", "dark")),
}

# sample hero colours for the previews (LookKit.colors roles)
ROLES = {"dark": (34, 38, 52), "white": (240, 240, 245), "ice": (200, 245, 255), "gold": (255, 210, 70),
         "glowRed": (255, 80, 40)}
SAMPLE_SETS = [  # (p, s, a): bright hero picks from Config.Creator.palette
    ((40, 110, 220), (235, 60, 60), (255, 210, 60)),
    ((235, 60, 60), (30, 45, 120), (255, 240, 80)),
    ((40, 150, 80), (24, 24, 28), (140, 210, 70)),
    ((120, 80, 220), (55, 58, 66), (80, 255, 255)),
    ((255, 140, 40), (30, 45, 120), (245, 245, 245)),
    ((40, 190, 170), (245, 245, 245), (255, 60, 140)),
    ((30, 45, 120), (175, 180, 190), (255, 210, 60)),
    ((240, 110, 190), (70, 20, 110), (110, 210, 255)),
]
SKIN = (224, 172, 130)


def role_rgb(role, pal):
    if role in ("p", "s", "a"):
        return pal["psa".index(role)]
    if role == "skin":
        return SKIN
    return ROLES[role]


def tinted(im, rgb):
    r, g, b, a = im.split()
    r = r.point(lambda v: v * rgb[0] // 255)
    g = g.point(lambda v: v * rgb[1] // 255)
    b = b.point(lambda v: v * rgb[2] // 255)
    return Image.merge("RGBA", (r, g, b, a))


def body_under(paint, pal, which):
    """The template's own regions filled with the body paint (what shows through the clear pixels)."""
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    torso, arms, legs = (role_rgb(r, pal) for r in paint)
    for s in list(SIDES4) + ["U", "D"]:
        x, y, w, h = TORSO[s]
        d.rectangle([x, y, x + w - 1, y + h - 1], fill=(*torso, 255))
    for slots in (RIGHT, LEFT):
        for s in list(SIDES4) + ["U", "D"]:
            x, y, w, h = slots[s]
            d.rectangle([x, y, x + w - 1, y + h - 1], fill=(*(arms if which == "shirt" else legs), 255))
            if which == "shirt" and paint[1] == "skin" and s in SIDES4:
                pass
    return im


if __name__ == "__main__":
    tiles, pages = [], []
    for i, (kit, (fn, st, pt, parts, paint)) in enumerate(SUITS.items()):
        s, p = fn()
        si, pi = s.image(), p.image()
        si.save(os.path.join(OUT, "SuitShirt_%s.png" % kit))
        pi.save(os.path.join(OUT, "SuitPants_%s.png" % kit))
        pal = SAMPLE_SETS[i % len(SAMPLE_SETS)]
        # the previews: the template tinted as the game tints it (the body paint is the part colour under it)
        prev = os.path.join(OUT, "preview")
        os.makedirs(prev, exist_ok=True)
        tinted(si, role_rgb(st, pal)).save(os.path.join(prev, "%s_Shirt.png" % kit))
        tinted(pi, role_rgb(pt, pal)).save(os.path.join(prev, "%s_Pants.png" % kit))
        pages.append({"name": "suits/preview/" + kit, "kit": kit, "paint": [role_rgb(r, pal) for r in paint]})
        both = Image.new("RGBA", (W * 2, H), (0, 0, 0, 0))
        for k, (im, tint, which) in enumerate(((si, st, "shirt"), (pi, pt, "pants"))):
            under = body_under(paint, pal, which)
            under.alpha_composite(tinted(im, role_rgb(tint, pal)))
            both.paste(under, (k * W, 0))
        tiles.append(both)
    with open(os.path.join(OUT, "preview.json"), "w") as f:
        json.dump([pages[i:i + 8] for i in range(0, len(pages), 8)], f, indent=1)
    cols = 4
    tw, th = W, H // 2
    sheet = Image.new("RGB", (tw * cols, th * ((len(tiles) + cols - 1) // cols)), (120, 120, 126))
    for i, im in enumerate(tiles):
        sheet.paste(im.convert("RGB").resize((tw - 4, th - 4)), ((i % cols) * tw + 2, (i // cols) * th + 2))
    sheet.save(os.path.join(ROOT, "preview", "suit_templates.png"))
    print("wrote", len(SUITS), "suits")
