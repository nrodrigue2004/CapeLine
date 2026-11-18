# art/clothes/people.py: the side quests' people in outfits of their own (2026-11-18 art pass, nate's pick "Mix
# of bug hunt and art"): every giver, the named helpers a step draws (Wren, Toby, Flint, Finn, Dace, Ambrose,
# Master Hoshi) and every finale villain (the dresses and the costumed villains), so none of them wears another
# character's clothes any more. Each is the classic Roblox Shirt and Pants templates side by side (1170 x 559,
# like the robots' uniforms: Shared.ClothesMap), in full colour (never tinted), with clear areas where the skin
# shows. Faces where the six shared ones do not fit (the old, the kids, a stone face, a machine, a famous face):
# faces.py's face engine with the person's own numbers and extras. PLACEHOLDER ART until nate approves.
# Config.NpcLooks.people holds the ids; Shared.PeopleLooks puts them on (a person's hats, coats, gloves, boots and
# capes stay; the outfit draws the suit, shirt, pants and legs). Original designs only.
# Output: art/export/clothes/people/<Name>.png (+ _Shirt, _Pants), Face_<Name>.png (Face_Vesper_Cracked.png; 256 px
# like faces.py's, perf pass 2026-11-18), and
# art/preview/people_templates.png and people_faces.png. On the body: art/blender/clothed.py people <page>.
# Run: python3 art/clothes/people.py   (PIL only)
import math
import os
import random
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from trooper import TORSO, RIGHT, LEFT, SIDES4, UT_PX, W, H, shade, diamond  # noqa: E402
from uniforms import T, HAND, LOWER, WHITE, DARK, GOLD, STEEL, chain, plaid_img, scuff  # noqa: E402
import faces  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "export", "clothes", "people")
os.makedirs(OUT, exist_ok=True)
CLEAR = (0, 0, 0, 0)
BLACK = (30, 30, 34)


# ---------------------------------------------------------------- building blocks
def top(t, c, sleeve=HAND, hem=UT_PX):
    """A top: the upper torso (to hem) and sleeves (to row `sleeve`; 0 = sleeveless)."""
    t.torso(c, 0, hem)
    if sleeve > 0:
        t.limbs(c, 0, sleeve)


def suit(t, c, sleeve=HAND):
    """A one-piece on the shirt: the whole torso strip (the pants' lower torso is drawn the same colour)."""
    t.torso(c, 0, 128)
    if sleeve > 0:
        t.limbs(c, 0, sleeve)


def hands(t, c, frm=HAND):
    t.limbs(c, frm, 128, 1.05, 0.88)


def legs(p, c, to=HAND, waist=UT_PX - 4):
    p.torso(c, waist, 128, 1.0, 0.86)
    if to > 0:
        p.limbs(c, 0, to)


def shoes(p, c, frm=HAND, sole=None):
    p.limbs(c, frm, 128, 1.08, 0.82)
    p.limb_band(sole or shade(c, 0.5), 123, 128)


def belt(p, c, buckle=GOLD, y=UT_PX + 2, h=9):
    for s in SIDES4:
        x, yy, w, _ = TORSO[s]
        p.d.rectangle([x, yy + y, x + w - 1, yy + y + h - 1], fill=c)
    fx, fy, _, _ = TORSO["F"]
    p.d.rectangle([fx + 56, fy + y - 1, fx + 72, fy + y + h], outline=buckle, width=3)


def sash(t, c, y0=UT_PX - 14, h=12):
    """A sash or cummerbund round the waist of the shirt."""
    for s in SIDES4:
        x, y, w, _ = TORSO[s]
        t.d.rectangle([x, y + y0, x + w - 1, y + y0 + h - 1], fill=c)
        t.d.line([(x, y + y0 + h // 2), (x + w - 1, y + y0 + h // 2)], fill=shade(c, 0.8))


def buttons(t, x, y0, n, gap, c=GOLD, r=4):
    for k in range(n):
        y = y0 + k * gap
        t.d.ellipse([x - r, y - r, x + r, y + r], fill=c, outline=DARK)


def vneck(t, c, depth=34, wd=26):
    fx, fy, _, _ = TORSO["F"]
    t.d.polygon([(fx + 64 - wd, fy), (fx + 64 + wd, fy), (fx + 64, fy + depth)], fill=c)


def lapels(t, c, depth=60, wd=34, inner=None):
    """Jacket lapels: an open V to `depth` showing `inner` (a shirt) with lapels in `c`."""
    fx, fy, _, _ = TORSO["F"]
    if inner:
        t.d.polygon([(fx + 64 - wd + 8, fy), (fx + 64 + wd - 8, fy), (fx + 64, fy + depth)], fill=inner)
    for s in (-1, 1):
        t.d.polygon([(fx + 64 + s * (wd - 8), fy), (fx + 64 + s * wd, fy), (fx + 64 + s * 10, fy + depth),
                     (fx + 64, fy + depth)], fill=c, outline=shade(c, 0.7))


def tie(t, c, length=60, bow=False):
    fx, fy, _, _ = TORSO["F"]
    if bow:
        t.d.polygon([(fx + 64, fy + 10), (fx + 48, fy + 2), (fx + 48, fy + 18)], fill=c)
        t.d.polygon([(fx + 64, fy + 10), (fx + 80, fy + 2), (fx + 80, fy + 18)], fill=c)
        t.d.ellipse([fx + 59, fy + 5, fx + 69, fy + 15], fill=shade(c, 0.8))
        return
    t.d.polygon([(fx + 59, fy + 4), (fx + 69, fy + 4), (fx + 66, fy + 10), (fx + 62, fy + 10)], fill=shade(c, 0.85))
    t.d.polygon([(fx + 62, fy + 10), (fx + 66, fy + 10), (fx + 71, fy + length), (fx + 64, fy + length + 8),
                 (fx + 57, fy + length)], fill=c)


def badge(t, cx, cy, r, c, ring=DARK):
    t.d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=c, outline=ring, width=2)


def pocket(t, x, y, w, h, c):
    t.d.rectangle([x, y, x + w, y + h], fill=shade(c, 0.92), outline=shade(c, 0.66), width=2)
    t.d.line([(x, y + 5), (x + w, y + 5)], fill=shade(c, 0.66), width=1)


def side_stripes(t, c, r0, r1, wd=6, torso=True):
    t.outer_stripe(c, r0, r1, wd)
    if torso:
        t.torso_sides_stripe(c, 0, UT_PX, wd)


def overlay(t, img, alpha=1.0):
    """Lay a pattern over everything drawn so far, keeping the shading under it (clear areas stay clear)."""
    a = t.im.getchannel("A")
    pat = img.copy()
    pa = pat.getchannel("A").point(lambda v: int(v * alpha))
    pat.putalpha(Image.composite(pa, Image.new("L", (W, H), 0), a))
    t.im.alpha_composite(pat)
    t.im.putalpha(a)


def sheet(fn):
    """A transparent full-template sheet drawn by fn(draw)."""
    im = Image.new("RGBA", (W, H), CLEAR)
    fn(ImageDraw.Draw(im))
    return im


def stars_img(seed, n=160, c=(255, 255, 255), big=(255, 230, 160)):
    rng = random.Random(seed)

    def draw(d):
        for _ in range(n):
            x, y = rng.randrange(W), rng.randrange(H)
            r = rng.choice((1, 1, 1, 2))
            d.ellipse([x - r, y - r, x + r, y + r], fill=c + (220,))
        for _ in range(n // 10):
            x, y = rng.randrange(W), rng.randrange(H)
            d.line([(x - 5, y), (x + 5, y)], fill=big + (255,), width=2)
            d.line([(x, y - 5), (x, y + 5)], fill=big + (255,), width=2)
    return sheet(draw)


def pinstripe_img(c, gap=9):
    return sheet(lambda d: [d.line([(x, 0), (x, H)], fill=c + (110,), width=1) for x in range(0, W, gap)])


def cable_img(c):
    """A fisherman's knit: cable twists in columns."""
    def draw(d):
        for x in range(4, W, 16):
            for y in range(0, H, 10):
                d.arc([x, y, x + 10, y + 12], 200, 340, fill=c + (130,), width=2)
                d.arc([x, y + 5, x + 10, y + 17], 20, 160, fill=c + (90,), width=2)
    return sheet(draw)


def damask_img(c):
    def draw(d):
        for j, y in enumerate(range(0, H, 22)):
            for x in range(-11 if j % 2 else 0, W, 22):
                diamond(d, x + 11, y + 11, 6, 9, None, c + (150,))
                d.ellipse([x + 9, y + 9, x + 13, y + 13], fill=c + (150,))
    return sheet(draw)


def net_img(c, gap=12):
    def draw(d):
        for k in range(-H, W + H, gap):
            d.line([(k, 0), (k + H, H)], fill=c + (120,), width=1)
            d.line([(k + H, 0), (k, H)], fill=c + (120,), width=1)
    return sheet(draw)


def veins_img(c, seed, n=40):
    rng = random.Random(seed)

    def draw(d):
        for _ in range(n):
            x, y = rng.randrange(W), rng.randrange(H)
            pts = [(x, y)]
            a = rng.uniform(0, math.pi * 2)
            for _ in range(rng.randint(4, 8)):
                a += rng.uniform(-0.8, 0.8)
                x += math.cos(a) * rng.uniform(5, 12)
                y += math.sin(a) * rng.uniform(5, 12)
                pts.append((x, y))
            d.line(pts, fill=c + (255,), width=rng.choice((2, 3)))
            d.line(pts, fill=(255, 240, 180, 200), width=1)
    return sheet(draw)


def harlequin_img(c1, c2, line):
    def draw(d):
        for j, y in enumerate(range(-12, H + 24, 24)):
            for i, x in enumerate(range(-8, W + 16, 16)):
                d.polygon([(x, y - 12), (x + 8, y), (x, y + 12), (x - 8, y)], fill=(c1 if (i + j) % 2 else c2) + (255,),
                          outline=line + (255,))
    return sheet(draw)


def checker(t, x, y, w, h, c1, c2, sq=6):
    for j in range(0, h, sq):
        for i in range(0, w, sq):
            t.d.rectangle([x + i, y + j, x + min(w, i + sq) - 1, y + min(h, j + sq) - 1],
                          fill=c1 if ((i + j) // sq) % 2 else c2)


def flames(t, x, y, w, h, c, tip):
    """Racing flames licking up from the bottom of a rectangle."""
    for k in range(0, w, 14):
        ht = h * (0.55 + 0.45 * ((k * 37) % 11) / 10)
        t.d.polygon([(x + k, y + h), (x + k + 7, y + h - ht), (x + k + 14, y + h)], fill=c)
        t.d.polygon([(x + k + 3, y + h), (x + k + 7, y + h - ht * 0.55), (x + k + 11, y + h)], fill=tip)


def front():
    return TORSO["F"]


def back():
    return TORSO["B"]


def wave(d, cx, cy, c, sc=1.0, w=4):
    for k in range(3):
        x = cx - 18 * sc + k * 12 * sc
        d.arc([x, cy - 6 * sc, x + 12 * sc, cy + 6 * sc], 180, 360, fill=c, width=w)


# ---------------------------------------------------------------- the givers
def gus():
    """Janitor Gus: a grey-blue work shirt with a name patch and pen pocket, rolled sleeves, navy work trousers
    with knee pads and work boots."""
    s, p = T(), T()
    c, navy = (110, 140, 165), (40, 52, 78)
    top(s, c, LOWER - 6)
    s.limb_band(shade(c, 0.85), LOWER - 14, LOWER - 6)
    fx, fy, _, _ = front()
    lapels(s, shade(c, 1.1), 22, 30, (225, 225, 220))
    s.d.line([(fx + 64, fy + 22), (fx + 64, fy + UT_PX)], fill=shade(c, 0.7), width=2)
    buttons(s, fx + 67, fy + 32, 4, 17, (220, 220, 210), 3)
    pocket(s, fx + 16, fy + 30, 26, 22, c)
    s.d.rectangle([fx + 20, fy + 24, fx + 23, fy + 34], fill=(200, 40, 40))
    s.d.rectangle([fx + 82, fy + 30, fx + 112, fy + 40], fill=WHITE, outline=(200, 40, 40), width=2)  # name patch
    s.d.line([(fx + 86, fy + 35), (fx + 108, fy + 35)], fill=(200, 40, 40), width=2)
    legs(p, navy, HAND - 12)
    for slots in (RIGHT, LEFT):
        x, y, w, _ = slots["F"]
        p.d.rounded_rectangle([x + 10, y + 46, x + w - 11, y + 66], 4, fill=(60, 64, 70), outline=DARK)
    belt(p, (60, 44, 30), STEEL)
    shoes(p, (70, 50, 34), HAND - 12)
    scuff(s, 5, 40)
    return s.im, p.im


def benny():
    """Valet Benny: a crimson valet jacket with gold buttons, braid at the cuffs and shoulders, a white shirt and
    black bow tie; black trousers with a gold stripe and shined shoes."""
    s, p = T(), T()
    red = (180, 30, 45)
    top(s, red)
    s.limb_band(GOLD, HAND - 8, HAND - 3)
    hands(s, WHITE)
    s.limbs(GOLD, 0, 6, 1.0, 0.9)
    fx, fy, _, _ = front()
    lapels(s, shade(red, 0.75), 40, 30, WHITE)
    tie(s, BLACK, bow=True)
    for x in (fx + 42, fx + 86):
        buttons(s, x, fy + 50, 3, 16, GOLD)
    legs(p, BLACK, HAND - 6)
    p.outer_stripe(GOLD, 0, HAND - 6, 4)
    shoes(p, (14, 14, 16), HAND - 6, (60, 60, 64))
    return s.im, p.im


def scoops():
    """Scoops: a white tee under a pink and mint striped apron with the ice cream cone badge, mint capri pants
    and pink sneakers."""
    s, p = T(), T()
    pink, mint = (240, 120, 180), (140, 220, 190)
    top(s, WHITE, 30)
    s.limb_band(pink, 26, 30)
    fx, fy, _, _ = front()
    for k in range(0, 128, 16):  # the apron's stripes
        s.d.rectangle([fx + k, fy + 20, fx + k + 7, fy + UT_PX], fill=pink)
        s.d.rectangle([fx + k + 8, fy + 20, fx + k + 15, fy + UT_PX], fill=mint)
    s.d.rectangle([fx + 30, fy, fx + 36, fy + 20], fill=pink)
    s.d.rectangle([fx + 92, fy, fx + 98, fy + 20], fill=pink)
    badge(s, fx + 64, fy + 56, 15, WHITE)
    s.d.polygon([(fx + 57, fy + 56), (fx + 71, fy + 56), (fx + 64, fy + 70)], fill=(210, 160, 90))
    s.d.ellipse([fx + 56, fy + 44, fx + 72, fy + 58], fill=pink)
    bx, by, _, _ = back()
    s.d.line([(bx + 30, by + 4), (bx + 98, by + 60)], fill=pink, width=5)
    s.d.line([(bx + 98, by + 4), (bx + 30, by + 60)], fill=pink, width=5)
    legs(p, mint, LOWER + 10)
    p.limb_band(shade(mint, 0.85), LOWER + 4, LOWER + 10)
    shoes(p, pink, HAND, WHITE)
    return s.im, p.im


def dot():
    """Farmer Dot: an olive plaid shirt under a patched denim overall bib with brass clips, rolled sleeves, the
    overall legs to the boots."""
    s, p = T(), T()
    olive, denim = (110, 120, 60), (70, 100, 150)
    top(s, olive, LOWER)
    overlay(s, plaid_img(olive, (60, 66, 30), (200, 190, 120)))
    s.limb_band(shade(olive, 0.8), LOWER - 8, LOWER)
    fx, fy, _, _ = front()
    s.d.rectangle([fx + 26, fy + 34, fx + 102, fy + UT_PX], fill=denim, outline=shade(denim, 0.7))  # the bib
    pocket(s, fx + 46, fy + 44, 36, 24, denim)
    for x in (fx + 30, fx + 98):
        s.d.rectangle([x - 4, fy, x + 4, fy + 36], fill=denim)
        s.d.rectangle([x - 6, fy + 30, x + 6, fy + 38], fill=GOLD, outline=DARK)
    s.d.rectangle([fx + 72, fy + 76, fx + 92, fy + 94], fill=(200, 80, 60))  # a red patch
    bx, by, _, _ = back()
    s.d.line([(bx + 30, by), (bx + 98, by + 70)], fill=denim, width=8)
    s.d.line([(bx + 98, by), (bx + 30, by + 70)], fill=denim, width=8)
    legs(p, denim, HAND - 12)
    p.limb_band(shade(denim, 1.2), HAND - 20, HAND - 12)
    x, y, w, _ = LEFT["F"]
    p.d.rectangle([x + 14, y + 20, x + 34, y + 38], fill=(220, 170, 60))  # a knee patch
    shoes(p, (90, 60, 36), HAND - 12)
    return s.im, p.im


def nell():
    """Skipper Nell: a navy cable-knit fisherman's sweater with the Gull Point ferry badge (a gull over waves),
    yellow oilskin trousers and sea boots."""
    s, p = T(), T()
    navy, oil = (34, 48, 86), (240, 200, 50)
    top(s, navy, HAND)
    overlay(s, cable_img((120, 140, 190)))
    s.limb_band(shade(navy, 0.8), HAND - 10, HAND)
    fx, fy, _, _ = front()
    s.d.rectangle([fx + 36, fy, fx + 92, fy + 10], fill=shade(navy, 0.75))
    badge(s, fx + 90, fy + 40, 16, WHITE)
    s.d.arc([fx + 78, fy + 30, fx + 90, fy + 42], 200, 340, fill=DARK, width=3)  # the gull
    s.d.arc([fx + 90, fy + 30, fx + 102, fy + 42], 200, 340, fill=DARK, width=3)
    wave(s.d, fx + 96, fy + 48, (60, 120, 200), 0.8, 3)
    legs(p, oil, HAND - 16)
    for slots in (RIGHT, LEFT):
        for sd in SIDES4:
            x, y, w, _ = slots[sd]
            p.d.line([(x + 6, y + 10), (x + 10, y + 40)], fill=shade(oil, 0.82), width=2)  # creases
    p.d.rectangle([TORSO["F"][0] + 20, TORSO["F"][1] + UT_PX - 4, TORSO["F"][0] + 30, TORSO["F"][1] + 128],
                  fill=shade(oil, 0.85))
    shoes(p, (40, 70, 60), HAND - 16)
    return s.im, p.im


def pearl():
    """Doc Pearl: a teal wetsuit with coral side panels and white piping, the Reef Station patch (a shell), a dive
    computer on the left wrist, to the ankles."""
    s, p = T(), T()
    teal, coral = (30, 130, 140), (250, 120, 100)
    suit(s, teal, HAND)
    s.torso_sides_stripe(coral, 0, UT_PX, 22)
    s.outer_stripe(coral, 0, HAND, 10)
    s.limb_line(WHITE, 10, 1.0, 2)
    fx, fy, _, _ = front()
    s.d.line([(fx + 64, fy), (fx + 64, fy + UT_PX)], fill=shade(teal, 0.7), width=3)
    badge(s, fx + 92, fy + 30, 14, WHITE)
    for k in range(5):  # a scallop shell
        a = math.radians(200 + k * 35)
        s.d.line([(fx + 92, fy + 38), (fx + 92 + math.cos(a) * 11, fy + 38 + math.sin(a) * 11)], fill=coral, width=2)
    x, y, w, _ = LEFT["F"]
    s.d.rounded_rectangle([x + 18, y + HAND - 18, x + 46, y + HAND - 4], 3, fill=DARK, outline=STEEL)
    s.d.rectangle([x + 24, y + HAND - 14, x + 40, y + HAND - 8], fill=(120, 255, 200))
    hands(s, BLACK)
    legs(p, teal, 128)
    p.torso_sides_stripe(coral, UT_PX - 4, 128, 22)
    p.outer_stripe(coral, 0, HAND, 10)
    p.limb_band(BLACK, HAND, 128)
    return s.im, p.im


def brick():
    """Brick: an old champion's faded charcoal gym tank with a cracked crown-fist mark, grey track pants with a
    red stripe, white hand wraps drawn on the forearms and hands, high tops."""
    s, p = T(), T()
    char, red = (70, 72, 80), (200, 60, 55)
    s.torso(char, 0, UT_PX)
    fx, fy, _, _ = front()
    bx, by, _, _ = back()
    for x0, y0 in ((fx, fy), (bx, by)):
        s.d.rectangle([x0, y0, x0 + 20, y0 + 34], fill=CLEAR)
        s.d.rectangle([x0 + 108, y0, x0 + 127, y0 + 34], fill=CLEAR)
        s.d.ellipse([x0 + 40, y0 - 24, x0 + 88, y0 + 16], fill=CLEAR)
    for sd in ("R", "L"):
        x, y, w, _ = TORSO[sd]
        s.d.rectangle([x, y, x + w - 1, y + 28], fill=CLEAR)
    s.d.ellipse([fx + 40, fy + 36, fx + 88, fy + 84], outline=red, width=4)  # a fist under a crown
    s.d.rounded_rectangle([fx + 52, fy + 52, fx + 76, fy + 72], 4, fill=shade(char, 1.5))
    s.d.polygon([(fx + 52, fy + 50), (fx + 56, fy + 40), (fx + 64, fy + 47), (fx + 72, fy + 40), (fx + 76, fy + 50)],
                fill=GOLD)
    scuff(s, 17, 80, 0.8)  # faded with years of washing
    s.limbs((240, 236, 226), LOWER + 24, 128, 1.0, 0.9)  # hand wraps
    for slots in (RIGHT, LEFT):
        for sd in SIDES4:
            x, y, w, _ = slots[sd]
            for k in range(LOWER + 26, 126, 7):
                s.d.line([(x, y + k), (x + w - 1, y + k + 4)], fill=(200, 196, 186), width=1)
    legs(p, (120, 122, 130), HAND - 8)
    p.outer_stripe(red, 0, HAND - 8, 8)
    p.limb_band(shade((120, 122, 130), 0.8), HAND - 14, HAND - 8)
    shoes(p, WHITE, HAND - 8, red)
    return s.im, p.im


def vanta():
    """Duchess Vanta: a deep purple velvet gown with gold damask, a gold brooch at the collar, long sleeves with
    gold cuffs, the gown's long skirt to the floor."""
    s, p = T(), T()
    plum = (70, 24, 90)
    top(s, plum)
    overlay(s, damask_img((220, 170, 70)), 0.8)
    s.limb_band(GOLD, HAND - 8, HAND)
    fx, fy, _, _ = front()
    vneck(s, CLEAR, 30, 22)
    s.d.polygon([(fx + 64, fy + 30), (fx + 52, fy + 44), (fx + 64, fy + 58), (fx + 76, fy + 44)], fill=GOLD, outline=DARK)
    s.d.ellipse([fx + 58, fy + 38, fx + 70, fy + 50], fill=(160, 220, 255))
    sash(s, shade(plum, 0.7), UT_PX - 12, 10)
    legs(p, plum, 128)
    overlay(p, damask_img((220, 170, 70)), 0.8)
    p.limb_band(GOLD, 120, 128)
    return s.im, p.im


def nora():
    """Nora Bright: a tan belted trench coat over a blue blouse, epaulettes and storm flap, the BHN press pass on a
    lanyard, dark slacks and red sneakers."""
    s, p = T(), T()
    tan, blue = (196, 160, 110), (70, 120, 200)
    top(s, tan)
    s.limb_band(shade(tan, 0.8), HAND - 12, HAND - 6)
    fx, fy, _, _ = front()
    lapels(s, shade(tan, 0.88), 44, 36, blue)
    for x in (fx + 40, fx + 88):
        buttons(s, x, fy + 54, 3, 14, (90, 60, 40), 4)
    sash(s, shade(tan, 0.75), UT_PX - 26, 10)
    s.d.rectangle([fx + 56, fy + UT_PX - 28, fx + 72, fy + UT_PX - 14], outline=(90, 60, 40), width=3)
    s.d.line([(fx + 50, fy + 2), (fx + 60, fy + 40)], fill=(200, 40, 40), width=2)  # the lanyard
    s.d.rectangle([fx + 50, fy + 40, fx + 70, fy + 62], fill=WHITE, outline=DARK)
    s.d.rectangle([fx + 53, fy + 43, fx + 67, fy + 49], fill=(200, 40, 40))
    for sd in (RIGHT, LEFT):
        x, y, w, _ = sd["U"]
        s.d.rectangle([x + 8, y + 24, x + w - 8, y + 36], fill=shade(tan, 0.8))  # epaulettes
    legs(p, (50, 52, 60), HAND - 4)
    shoes(p, (200, 50, 50), HAND - 4, WHITE)
    return s.im, p.im


def okafor():
    """Dr. Okafor: a white lab coat over a teal blouse, pens in the breast pocket, the Ashgrove badge struck
    through with marker (she was fired), slate trousers."""
    s, p = T(), T()
    coat, teal = (240, 242, 244), (40, 150, 150)
    top(s, coat)
    fx, fy, _, _ = front()
    lapels(s, shade(coat, 0.9), 50, 34, teal)
    s.d.line([(fx + 64, fy + 50), (fx + 64, fy + UT_PX)], fill=shade(coat, 0.75), width=2)
    pocket(s, fx + 84, fy + 30, 24, 20, coat)
    for k, col in enumerate(((40, 80, 200), (200, 40, 40), DARK)):
        s.d.rectangle([fx + 88 + k * 6, fy + 22, fx + 91 + k * 6, fy + 34], fill=col)
    s.d.rectangle([fx + 16, fy + 34, fx + 40, fy + 50], fill=(150, 160, 200), outline=DARK)
    s.d.line([(fx + 14, fy + 52), (fx + 42, fy + 32)], fill=BLACK, width=3)
    pocket(s, fx + 14, fy + 70, 28, 22, coat)
    pocket(s, fx + 86, fy + 70, 28, 22, coat)
    legs(p, (70, 76, 90), HAND - 2)
    shoes(p, (240, 240, 240), HAND - 2, (60, 60, 64))
    return s.im, p.im


def ruth():
    """Radio Ruth: a mustard cardigan knitted with radio waves, a cream blouse collar, brown corduroys and walking
    boots."""
    s, p = T(), T()
    mustard, cord = (210, 160, 50), (120, 80, 50)
    top(s, mustard)
    s.limb_band(shade(mustard, 0.8), HAND - 10, HAND)
    fx, fy, _, _ = front()
    vneck(s, (240, 232, 210), 40, 26)
    s.d.line([(fx + 64, fy + 40), (fx + 64, fy + UT_PX)], fill=shade(mustard, 0.7), width=2)
    buttons(s, fx + 68, fy + 50, 3, 16, (120, 80, 50), 3)
    for side in (-1, 1):  # radio waves on each front panel
        cx = fx + 64 + side * 34
        for r in (8, 15, 22):
            s.d.arc([cx - r, fy + 64 - r, cx + r, fy + 64 + r], 210 if side < 0 else -30, 330 if side < 0 else 90,
                    fill=(110, 170, 220), width=3)
    legs(p, cord, HAND - 10)
    for slots in (RIGHT, LEFT):
        for sd in SIDES4:
            x, y, w, _ = slots[sd]
            for k in range(x + 3, x + w, 5):
                p.d.line([(k, y), (k, y + HAND - 10)], fill=shade(cord, 0.82), width=1)
    shoes(p, (70, 50, 36), HAND - 10)
    return s.im, p.im


def moth():
    """Auntie Moth: a plum tunic embroidered with gold moths, a lilac collar, bell sleeves, and a long skirt in a
    paisley of eyes and leaves (clear at the ankles for her sandals)."""
    s, p = T(), T()
    plum, lilac = (110, 40, 90), (190, 150, 220)
    top(s, plum)
    s.limb_band(lilac, HAND - 10, HAND - 2)
    fx, fy, _, _ = front()
    s.d.ellipse([fx + 36, fy - 14, fx + 92, fy + 22], fill=lilac)
    s.d.ellipse([fx + 46, fy - 14, fx + 82, fy + 12], fill=CLEAR)

    def moth_at(d, cx, cy, sc=1.0):
        for k in (-1, 1):
            d.ellipse([cx + k * 2 * sc - (12 * sc if k < 0 else 0), cy - 8 * sc, cx + k * 2 * sc + (0 if k < 0 else 12 * sc),
                       cy + 2 * sc], fill=GOLD)
            d.ellipse([cx + k * 2 * sc - (8 * sc if k < 0 else 0), cy, cx + k * 2 * sc + (0 if k < 0 else 8 * sc), cy + 8 * sc],
                      fill=shade(GOLD, 0.85))
        d.line([(cx, cy - 8 * sc), (cx, cy + 8 * sc)], fill=DARK, width=2)
    for cx, cy in ((fx + 30, fy + 50), (fx + 98, fy + 44), (fx + 64, fy + 82)):
        moth_at(s.d, cx, cy)
    bx, by, _, _ = back()
    moth_at(s.d, bx + 64, by + 50, 2.0)
    skirt = (60, 30, 70)
    legs(p, skirt, HAND - 4)
    rng = random.Random(4)
    for slots in (RIGHT, LEFT):
        for sd in SIDES4:
            x, y, w, _ = slots[sd]
            for _ in range(5):
                px, py = x + rng.randint(6, w - 12), y + rng.randint(6, HAND - 16)
                p.d.ellipse([px, py, px + 10, py + 6], outline=(200, 140, 60), width=2)
                p.d.ellipse([px + 3, py + 1, px + 7, py + 5], fill=(120, 190, 140))
    p.limb_band(lilac, HAND - 10, HAND - 4)
    return s.im, p.im


def tess():
    """Tinker Tess: an orange mechanic's coverall with rolled sleeves, a grease smear, a tool pocket with a wrench,
    the gear patch on the back, knee pads, steel-toe boots."""
    s, p = T(), T()
    org = (230, 120, 40)
    suit(s, org, LOWER - 6)
    s.limb_band(shade(org, 0.8), LOWER - 14, LOWER - 6)
    fx, fy, _, _ = front()
    lapels(s, shade(org, 0.85), 24, 26, (60, 60, 66))
    s.d.rectangle([fx + 62, fy + 22, fx + 66, fy + 128], fill=STEEL)
    pocket(s, fx + 18, fy + 30, 30, 26, org)
    s.d.line([(fx + 30, fy + 18), (fx + 30, fy + 40)], fill=(170, 175, 185), width=4)
    s.d.ellipse([fx + 25, fy + 12, fx + 35, fy + 22], outline=(170, 175, 185), width=3)
    for _ in range(1):
        s.d.ellipse([fx + 78, fy + 60, fx + 110, fy + 74], fill=(60, 50, 44, 200))
    bx, by, _, _ = back()
    gear = (60, 60, 66)
    s.d.ellipse([bx + 40, by + 26, bx + 88, by + 74], fill=gear)
    for k in range(8):
        a = k / 8 * math.pi * 2
        s.d.rectangle([bx + 64 + math.cos(a) * 26 - 4, by + 50 + math.sin(a) * 26 - 4,
                       bx + 64 + math.cos(a) * 26 + 4, by + 50 + math.sin(a) * 26 + 4], fill=gear)
    s.d.ellipse([bx + 56, by + 42, bx + 72, by + 58], fill=org)
    scuff(s, 9, 50)
    legs(p, org, HAND - 12)
    p.d.rectangle([TORSO["F"][0] + 62, TORSO["F"][1] + UT_PX - 4, TORSO["F"][0] + 66, TORSO["F"][1] + 128], fill=STEEL)
    for slots in (RIGHT, LEFT):
        x, y, w, _ = slots["F"]
        p.d.rounded_rectangle([x + 10, y + 46, x + w - 11, y + 66], 4, fill=(60, 60, 66), outline=DARK)
    shoes(p, (40, 36, 34), HAND - 12, STEEL)
    return s.im, p.im


def kiko():
    """Kiko: Master Hoshi's youngest student in a white student's gi with red trim at the collar and cuffs, the
    dojo's willow leaf on the back, white gi trousers."""
    s, p = T(), T()
    gi, red = (246, 244, 238), (210, 50, 50)
    top(s, gi, LOWER + 10)
    fx, fy, _, _ = front()
    s.d.polygon([(fx + 30, fy), (fx + 46, fy), (fx + 90, fy + 70), (fx + 74, fy + 70)], fill=red)  # the crossed collar
    s.d.polygon([(fx + 98, fy), (fx + 82, fy), (fx + 58, fy + 40), (fx + 66, fy + 50)], fill=shade(red, 0.85))
    s.limb_band(red, LOWER + 4, LOWER + 10)
    bx, by, _, _ = back()
    s.d.ellipse([bx + 50, by + 24, bx + 78, by + 70], fill=(90, 160, 90))
    s.d.line([(bx + 64, by + 22), (bx + 64, by + 72)], fill=(40, 90, 50), width=2)
    for k in range(0, 128, 20):
        s.d.line([(fx, fy + k + 4), (fx + 127, fy + k + 8)], fill=shade(gi, 0.9), width=1)
    legs(p, gi, HAND - 6)
    p.limb_band(shade(gi, 0.88), HAND - 10, HAND - 6)
    return s.im, p.im


# ---------------------------------------------------------------- the named helpers
def wren():
    """Wren: Halo Academy's navy school blazer with the gold halo crest on the pocket, a white shirt and a red
    striped tie, a grey pleated skirt (clear knees), knee socks and black shoes."""
    s, p = T(), T()
    navy = (30, 45, 100)
    top(s, navy)
    fx, fy, _, _ = front()
    lapels(s, shade(navy, 0.8), 52, 32, WHITE)
    tie(s, (180, 40, 50), 48)
    s.d.line([(fx + 60, fy + 20), (fx + 68, fy + 16)], fill=GOLD, width=2)
    s.d.ellipse([fx + 80, fy + 30, fx + 106, fy + 44], outline=GOLD, width=3)  # the halo crest
    pocket(s, fx + 80, fy + 46, 26, 20, navy)
    s.limb_band(GOLD, HAND - 6, HAND - 3)
    grey = (120, 124, 132)
    legs(p, grey, 34)
    for slots in (RIGHT, LEFT):
        for sd in SIDES4:
            x, y, w, _ = slots[sd]
            for k in range(x + 4, x + w, 10):
                p.d.line([(k, y), (k, y + 34)], fill=shade(grey, 0.75), width=2)
    p.limbs((240, 240, 240), LOWER + 6, HAND, 1.0, 0.92)
    shoes(p, BLACK, HAND)
    return s.im, p.im


def toby():
    """Toby: a sky blue tee with a rocket on it, red sleeve bands, denim dungaree shorts with a button bib, red
    sneakers."""
    s, p = T(), T()
    sky, denim = (100, 180, 240), (60, 90, 160)
    top(s, sky, 30)
    s.limb_band((220, 60, 60), 24, 30)
    fx, fy, _, _ = front()
    s.d.polygon([(fx + 64, fy + 12), (fx + 72, fy + 28), (fx + 72, fy + 50), (fx + 56, fy + 50), (fx + 56, fy + 28)],
                fill=WHITE, outline=DARK)
    s.d.ellipse([fx + 60, fy + 28, fx + 68, fy + 36], fill=(100, 180, 240), outline=DARK)
    s.d.polygon([(fx + 56, fy + 40), (fx + 48, fy + 54), (fx + 56, fy + 50)], fill=(220, 60, 60))
    s.d.polygon([(fx + 72, fy + 40), (fx + 80, fy + 54), (fx + 72, fy + 50)], fill=(220, 60, 60))
    s.d.polygon([(fx + 58, fy + 52), (fx + 64, fy + 64), (fx + 70, fy + 52)], fill=(255, 180, 60))
    s.d.rectangle([fx + 30, fy + 66, fx + 98, fy + UT_PX], fill=denim, outline=shade(denim, 0.7))
    for x in (fx + 38, fx + 90):
        s.d.ellipse([x - 4, fy + 68, x + 4, fy + 76], fill=GOLD)
    legs(p, denim, 30)
    p.limb_band(shade(denim, 1.2), 24, 30)
    shoes(p, (220, 60, 60), HAND, WHITE)
    return s.im, p.im


def flint():
    """Flint: a young Spark fighter's red sleeveless training top with taped seams and a flame mark, black fight
    shorts with a red waistband, taped hands and ankle wraps."""
    s, p = T(), T()
    red = (200, 50, 45)
    s.torso(red, 0, UT_PX)
    fx, fy, _, _ = front()
    bx, by, _, _ = back()
    for x0, y0 in ((fx, fy), (bx, by)):
        s.d.rectangle([x0, y0, x0 + 14, y0 + 30], fill=CLEAR)
        s.d.rectangle([x0 + 114, y0, x0 + 127, y0 + 30], fill=CLEAR)
        s.d.ellipse([x0 + 44, y0 - 20, x0 + 84, y0 + 12], fill=CLEAR)
    for sd in ("R", "L"):
        x, y, w, _ = TORSO[sd]
        s.d.rectangle([x, y, x + w - 1, y + 26], fill=CLEAR)
    s.d.polygon([(fx + 64, fy + 30), (fx + 52, fy + 66), (fx + 64, fy + 80), (fx + 76, fy + 66)], fill=(255, 170, 60))
    s.d.polygon([(fx + 64, fy + 50), (fx + 58, fy + 68), (fx + 64, fy + 76), (fx + 70, fy + 68)], fill=(255, 235, 150))
    for x in (fx + 20, fx + 106):
        s.d.line([(x, fy + 34), (x, fy + UT_PX)], fill=(230, 230, 220), width=4)  # tape
    s.limbs((236, 232, 222), HAND - 10, 128, 1.0, 0.9)
    legs(p, BLACK, 40)
    for sd in SIDES4:
        x, y, w, _ = TORSO[sd]
        p.d.rectangle([x, y + UT_PX - 4, x + w - 1, y + UT_PX + 6], fill=red)
    p.outer_stripe(red, 0, 40, 6)
    p.limb_band((236, 232, 222), HAND - 10, HAND + 2)
    shoes(p, (60, 60, 66), HAND + 2)
    return s.im, p.im


def finn():
    """Finn: Skipper Nell's deckhand grandson in a navy and white striped jersey under an orange life vest with a
    whistle and reflective bands, rolled canvas trousers and rubber boots."""
    s, p = T(), T()
    navy, vest = (30, 45, 100), (250, 120, 30)
    top(s, WHITE, HAND)
    s.hstripes(navy, 0, UT_PX, period=14, wd=6, limbs_to=HAND)
    for sd in SIDES4:
        x, y, w, _ = TORSO[sd]
        s.d.rectangle([x, y + 4, x + w - 1, y + UT_PX - 6], fill=vest)
        s.d.rectangle([x, y + 40, x + w - 1, y + 46], fill=(230, 230, 230))
        s.d.rectangle([x, y + 66, x + w - 1, y + 72], fill=(230, 230, 230))
    fx, fy, _, _ = front()
    s.d.rectangle([fx + 60, fy + 4, fx + 68, fy + UT_PX - 6], fill=shade(vest, 0.75))
    s.d.rectangle([fx + 82, fy + 20, fx + 94, fy + 26], fill=(200, 205, 215), outline=DARK)
    canvas = (190, 175, 140)
    legs(p, canvas, HAND - 16)
    p.limb_band(shade(canvas, 0.8), HAND - 24, HAND - 16)
    shoes(p, (240, 200, 50), HAND - 16)
    return s.im, p.im


def dace():
    """Dace: the salvage diver, in an orange and black drysuit with a chest harness, a depth gauge, knee plates
    and black dive boots."""
    s, p = T(), T()
    org = (240, 120, 30)
    suit(s, BLACK, HAND)
    for sd in SIDES4:
        x, y, w, _ = TORSO[sd]
        s.d.rectangle([x, y, x + w - 1, y + 40], fill=org)
    s.limbs(org, 0, 34)
    fx, fy, _, _ = front()
    for x in (fx + 34, fx + 94):
        s.d.line([(x, fy), (x, fy + 128)], fill=(60, 60, 64), width=7)
    s.d.line([(fx + 34, fy + 60), (fx + 94, fy + 60)], fill=(60, 60, 64), width=7)
    s.d.ellipse([fx + 56, fy + 52, fx + 72, fy + 68], fill=STEEL, outline=DARK)
    badge(s, fx + 64, fy + 86, 9, (200, 220, 230))
    hands(s, (40, 40, 44))
    legs(p, BLACK, 128)
    for slots in (RIGHT, LEFT):
        x, y, w, _ = slots["F"]
        p.d.rounded_rectangle([x + 8, y + 46, x + w - 9, y + 66], 4, fill=org, outline=DARK)
    p.outer_stripe(org, 0, HAND, 6)
    return s.im, p.im


def ambrose():
    """Ambrose the Astonishing: a faded midnight tailcoat sewn with stars, a gold waistcoat with a watch chain, a
    white shirt front and a red bow tie, striped stage trousers."""
    s, p = T(), T()
    mid = (34, 40, 90)
    top(s, mid)
    overlay(s, stars_img(12, 90, (230, 220, 180)), 0.7)
    fx, fy, _, _ = front()
    s.d.polygon([(fx + 30, fy), (fx + 98, fy), (fx + 90, fy + UT_PX), (fx + 38, fy + UT_PX)], fill=(200, 160, 60))
    s.d.polygon([(fx + 50, fy), (fx + 78, fy), (fx + 64, fy + 40)], fill=WHITE)
    tie(s, (190, 40, 50), bow=True)
    buttons(s, fx + 64, fy + 50, 4, 13, (120, 90, 30), 3)
    chain(s.d, (fx + 40, fy + 66), (fx + 62, fy + 74), (230, 200, 100), 6)
    for sd in (-1, 1):
        s.d.polygon([(fx + 64 + sd * 34, fy), (fx + 64 + sd * 46, fy), (fx + 64 + sd * 26, fy + UT_PX),
                     (fx + 64 + sd * 20, fy + UT_PX)], fill=shade(mid, 0.8))
    s.limb_band(WHITE, HAND - 8, HAND)
    scuff(s, 21, 40, 0.85)
    legs(p, (30, 30, 36), HAND - 4)
    for slots in (RIGHT, LEFT):
        for sd in SIDES4:
            x, y, w, _ = slots[sd]
            for k in range(x + 6, x + w, 12):
                p.d.line([(k, y), (k, y + HAND - 4)], fill=(80, 80, 96), width=2)
    shoes(p, (14, 14, 16), HAND - 4, (60, 60, 64))
    return s.im, p.im


def hoshi():
    """Master Hoshi: a grey-blue master's gi with a dark collar, the dojo's willow crest on the back, wide dark
    hakama trousers with pleats, white tabi."""
    s, p = T(), T()
    gi, dark = (120, 140, 160), (34, 36, 50)
    top(s, gi, HAND - 2)
    fx, fy, _, _ = front()
    s.d.polygon([(fx + 30, fy), (fx + 46, fy), (fx + 90, fy + 78), (fx + 74, fy + 78)], fill=dark)
    s.d.polygon([(fx + 98, fy), (fx + 82, fy), (fx + 58, fy + 42), (fx + 66, fy + 52)], fill=shade(dark, 1.2))
    bx, by, _, _ = back()
    s.d.ellipse([bx + 36, by + 18, bx + 92, by + 74], outline=dark, width=4)
    for k in range(5):
        s.d.arc([bx + 44 + k * 8, by + 30, bx + 64 + k * 8, by + 66], 90, 180, fill=(70, 120, 80), width=3)
    sash(s, dark, UT_PX - 14, 12)
    legs(p, dark, HAND)
    for slots in (RIGHT, LEFT):
        for sd in SIDES4:
            x, y, w, _ = slots[sd]
            for k in range(x + 8, x + w, 14):
                p.d.line([(k, y), (k, y + HAND)], fill=shade(dark, 1.4), width=2)
    shoes(p, (240, 240, 236), HAND, (120, 120, 120))
    return s.im, p.im


# ---------------------------------------------------------------- the finale villains
def halo():
    """Headmaster Halo: a black academic gown with wide gold-trimmed sleeves over a white waistcoat, the gold halo
    crest on the chest and back, grey trousers."""
    s, p = T(), T()
    gown = (30, 30, 40)
    top(s, gown)
    s.limb_band(GOLD, HAND - 14, HAND - 6)
    fx, fy, _, _ = front()
    s.d.rectangle([fx + 36, fy, fx + 92, fy + UT_PX], fill=WHITE)
    tie(s, GOLD, 50)
    for sd in (-1, 1):
        s.d.rectangle([fx + 64 + sd * 28 - 4, fy, fx + 64 + sd * 28 + 4, fy + UT_PX], fill=GOLD)
    s.d.ellipse([fx + 72, fy + 60, fx + 90, fy + 68], outline=GOLD, width=3)
    bx, by, _, _ = back()
    s.d.ellipse([bx + 30, by + 30, bx + 98, by + 54], outline=GOLD, width=6)
    s.d.ellipse([bx + 54, by + 56, bx + 74, by + 76], fill=GOLD)
    legs(p, (90, 90, 100), HAND - 4)
    shoes(p, (14, 14, 16), HAND - 4)
    return s.im, p.im


def redline():
    """Redline: a red racing suit with a black checker band across the chest, white side stripes, flames up the
    shins and the King of the Rooftops' number roundel, black racing gloves and boots."""
    s, p = T(), T()
    red = (220, 40, 40)
    suit(s, red, HAND)
    for sd in SIDES4:
        x, y, w, _ = TORSO[sd]
        checker(s, x, y + 22, w, 14, BLACK, WHITE, 7)
    side_stripes(s, WHITE, 0, HAND, 6)
    fx, fy, _, _ = front()
    badge(s, fx + 64, fy + 66, 16, WHITE)
    s.d.polygon([(fx + 60, fy + 56), (fx + 70, fy + 56), (fx + 62, fy + 66), (fx + 70, fy + 66), (fx + 58, fy + 78),
                 (fx + 62, fy + 68), (fx + 56, fy + 68)], fill=red)
    hands(s, BLACK)
    legs(p, red, 128)
    p.outer_stripe(WHITE, 0, HAND, 6)
    for slots in (RIGHT, LEFT):
        for sd in SIDES4:
            x, y, w, _ = slots[sd]
            flames(p, x, y + LOWER - 10, w, HAND - LOWER + 10, (255, 150, 40), (255, 230, 120))
    p.limb_band(BLACK, HAND, 128)
    return s.im, p.im


def masque():
    """Madame Masque-a-rade: a purple and gold harlequin bodice with a gold collar, long purple gloves, harlequin
    tights and black heeled boots."""
    s, p = T(), T()
    purple = (90, 30, 130)
    suit(s, purple, HAND)
    for sd in SIDES4:
        x, y, w, _ = TORSO[sd]
        s.d.rectangle([x, y, x + w - 1, y + UT_PX], fill=(255, 255, 255, 255))
    pat = harlequin_img((110, 40, 160), (220, 180, 70), DARK)
    hl = Image.new("RGBA", (W, H), CLEAR)
    for sd in SIDES4:
        x, y, w, _ = TORSO[sd]
        hl.paste(pat.crop((x, y, x + w, y + UT_PX)), (x, y))
    s.im.alpha_composite(hl)
    s.d = ImageDraw.Draw(s.im)
    fx, fy, _, _ = front()
    s.d.polygon([(fx + 30, fy), (fx + 98, fy), (fx + 64, fy + 26)], fill=GOLD, outline=DARK)
    s.limbs(shade(purple, 0.8), LOWER - 6, 128, 1.0, 0.85)
    s.limb_band(GOLD, LOWER - 6, LOWER - 2)
    legs(p, purple, HAND - 10)
    pl = Image.new("RGBA", (W, H), CLEAR)
    for slots in (RIGHT, LEFT):
        for sd in SIDES4:
            x, y, w, _ = slots[sd]
            pl.paste(pat.crop((x, y, x + w, y + HAND - 10)), (x, y))
    p.im.alpha_composite(pl)
    p.d = ImageDraw.Draw(p.im)
    shoes(p, (20, 18, 24), HAND - 10)
    return s.im, p.im


def harvest_king():
    """The Harvest King: mustard thresher overalls over a forest green shirt, the wheat crown on the bib, riveted
    straps, corn-yellow knee patches, mud-brown boots."""
    s, p = T(), T()
    forest, mustard = (40, 100, 50), (210, 170, 50)
    top(s, forest, HAND - 4)
    overlay(s, plaid_img(forest, (20, 60, 30), (160, 200, 120)), 0.8)
    fx, fy, _, _ = front()
    s.d.rectangle([fx + 22, fy + 30, fx + 106, fy + UT_PX], fill=mustard, outline=shade(mustard, 0.7))
    s.d.polygon([(fx + 44, fy + 64), (fx + 48, fy + 44), (fx + 56, fy + 58), (fx + 64, fy + 40), (fx + 72, fy + 58),
                 (fx + 80, fy + 44), (fx + 84, fy + 64)], fill=(240, 210, 90), outline=(120, 90, 30))
    for k in range(5):
        s.d.line([(fx + 46 + k * 9, fy + 66), (fx + 46 + k * 9, fy + 80)], fill=(200, 160, 60), width=3)
    for x in (fx + 28, fx + 100):
        s.d.rectangle([x - 5, fy, x + 5, fy + 32], fill=mustard)
        s.d.ellipse([x - 5, fy + 26, x + 5, fy + 36], fill=STEEL, outline=DARK)
    legs(p, mustard, HAND - 12)
    for slots in (RIGHT, LEFT):
        x, y, w, _ = slots["F"]
        p.d.rectangle([x + 12, y + 40, x + w - 13, y + 62], fill=(240, 220, 100), outline=shade(mustard, 0.6))
    shoes(p, (90, 60, 40), HAND - 12)
    scuff(p, 3, 50)
    return s.im, p.im


def bramblebeast():
    """The Bramblebeast (a cartoon crop creature): mossy bark skin knotted with vines and leaves, pumpkin rind
    plates on the chest and shoulders with a glowing seam, root-gnarled hands and feet."""
    s, p = T(), T()
    bark, moss, rind = (90, 70, 46), (70, 130, 60), (240, 140, 40)
    suit(s, bark, 128)
    veins = veins_img((60, 120, 50), 41, 70)
    overlay(s, veins)
    fx, fy, _, _ = front()
    for k in range(4):  # the pumpkin rind plate on the chest, ribbed
        x0 = fx + 22 + k * 21
        s.d.rounded_rectangle([x0, fy + 16, x0 + 20, fy + 80], 9, fill=rind, outline=(150, 80, 20), width=2)
    s.d.line([(fx + 30, fy + 48), (fx + 98, fy + 48)], fill=(255, 230, 120), width=3)
    for slots in (RIGHT, LEFT):
        for sd in SIDES4:
            x, y, w, _ = slots[sd]
            s.d.rounded_rectangle([x + 4, y + 2, x + w - 5, y + 22], 8, fill=rind, outline=(150, 80, 20), width=2)
    s.limbs((70, 50, 30), HAND, 128, 1.1, 0.8)
    leaves = sheet(lambda d: [d.ellipse([x, y, x + 9, y + 5], fill=moss + (255,)) for x, y in
                              [(random.Random(i).randrange(W), random.Random(i * 7).randrange(H)) for i in range(220)]])
    overlay(s, leaves, 0.9)
    legs(p, bark, 128)
    overlay(p, veins)
    overlay(p, leaves, 0.9)
    p.limbs((70, 50, 30), HAND, 128, 1.1, 0.8)
    return s.im, p.im


def brine():
    """Captain Brine: a riveted brass diving rig with portholes and pressure gauges, a teal undersuit, a pirate
    coat's maroon cuffs with gold buttons, the crossed-hooks crew mark and heavy lead boots."""
    s, p = T(), T()
    brass, teal, maroon = (190, 140, 70), (20, 110, 120), (110, 30, 40)
    suit(s, teal, HAND)
    for sd in SIDES4:
        x, y, w, _ = TORSO[sd]
        s.d.rectangle([x, y, x + w - 1, y + 56], fill=brass)
        for k in range(x + 6, x + w, 12):
            s.d.ellipse([k - 2, y + 52, k + 2, y + 56], fill=shade(brass, 0.6))
    fx, fy, _, _ = front()
    for cx in (fx + 40, fx + 88):
        s.d.ellipse([cx - 12, fy + 16, cx + 12, fy + 40], fill=(120, 200, 210), outline=shade(brass, 0.5), width=4)
    s.d.ellipse([fx + 54, fy + 68, fx + 74, fy + 88], fill=WHITE, outline=DARK, width=2)
    s.d.line([(fx + 64, fy + 78), (fx + 70, fy + 72)], fill=(200, 40, 40), width=2)
    s.limbs(maroon, HAND - 22, HAND, 1.0, 0.85)
    for slots in (RIGHT, LEFT):
        x, y, w, _ = slots["F"]
        buttons(s, x + w // 2, y + HAND - 12, 1, 0, GOLD, 4)
    hands(s, brass)
    bx, by, _, _ = back()
    for k in (-1, 1):
        s.d.line([(bx + 64 - k * 18, by + 70), (bx + 64 + k * 14, by + 100)], fill=GOLD, width=6)
    legs(p, teal, HAND - 16)
    shoes(p, (70, 74, 84), HAND - 16, (40, 42, 48))
    p.limb_band(brass, HAND - 16, HAND - 10)
    return s.im, p.im


def pitboss():
    """The Pitboss: a maroon pinstripe tuxedo with gold satin lapels, a white wing-collar shirt and black bow tie,
    a gold cummerbund, gold cufflinks; black trousers with a gold stripe and spats over his shoes."""
    s, p = T(), T()
    maroon = (110, 22, 30)
    top(s, maroon)
    overlay(s, pinstripe_img((230, 190, 120)))
    fx, fy, _, _ = front()
    lapels(s, GOLD, 64, 38, WHITE)
    tie(s, BLACK, bow=True)
    buttons(s, fx + 64, fy + 32, 2, 12, BLACK, 3)
    sash(s, GOLD, UT_PX - 16, 12)
    s.limb_band(WHITE, HAND - 6, HAND)
    for slots in (RIGHT, LEFT):
        x, y, w, _ = slots["F"]
        s.d.rectangle([x + 28, y + HAND - 5, x + 36, y + HAND - 1], fill=GOLD)
    legs(p, BLACK, HAND - 10)
    p.outer_stripe(GOLD, 0, HAND - 10, 5)
    p.limbs((240, 236, 226), HAND - 10, HAND + 6, 1.0, 0.9)  # spats
    shoes(p, (14, 14, 16), HAND + 6)
    return s.im, p.im


def tidewright():
    """The Tidewright (a guardian machine): a bronze and teal plated robe grown with coral and barnacles, wave
    glyphs down the front, the orb crest, a teal skirt of overlapping scale plates."""
    s, p = T(), T()
    bronze, teal = (170, 120, 70), (30, 110, 120)
    suit(s, teal, HAND)
    for sd in SIDES4:
        x, y, w, _ = TORSO[sd]
        for k in range(0, UT_PX, 18):
            s.d.rectangle([x, y + k, x + w - 1, y + k + 14], fill=bronze, outline=shade(bronze, 0.6))
    fx, fy, _, _ = front()
    s.d.rectangle([fx + 50, fy, fx + 78, fy + 128], fill=teal)
    for k in range(5):
        wave(s.d, fx + 64, fy + 12 + k * 22, (120, 255, 230), 0.9, 3)
    rng = random.Random(8)
    for _ in range(26):  # coral and barnacles
        x, y = rng.randrange(fx, fx + 128), rng.randrange(fy, fy + UT_PX)
        if not 48 < x - fx < 80:
            s.d.ellipse([x - 4, y - 4, x + 4, y + 4], fill=(240, 130, 120), outline=(150, 70, 60))
    for slots in (RIGHT, LEFT):
        for sd in SIDES4:
            x, y, w, _ = slots[sd]
            for k in range(0, HAND, 16):
                s.d.rectangle([x, y + k, x + w - 1, y + k + 10], fill=bronze, outline=shade(bronze, 0.6))
    hands(s, bronze)
    legs(p, teal, HAND)
    for slots in (RIGHT, LEFT):
        for sd in SIDES4:
            x, y, w, _ = slots[sd]
            for j, k in enumerate(range(0, HAND, 10)):
                for i in range(-8 if j % 2 else 0, w, 16):
                    p.d.arc([x + i, y + k, x + i + 16, y + k + 14], 0, 180, fill=bronze, width=3)
    shoes(p, bronze, HAND, shade(bronze, 0.5))
    return s.im, p.im


def vesper():
    """Vesper, the Evening Star: a night-sky bodysuit (deep purple to midnight) scattered with stars, the evening
    star crest on the chest in white and lilac, silver gloves and boots."""
    s, p = T(), T()
    deep = (60, 20, 100)
    suit(s, deep, HAND)
    overlay(s, stars_img(3))
    fx, fy, _, _ = front()
    for k, (r, c) in enumerate(((30, (240, 240, 250)), (20, (200, 150, 255)))):
        pts = []
        for i in range(10):
            a = -math.pi / 2 + i * math.pi / 5
            rr = r if i % 2 == 0 else r * 0.42
            pts.append((fx + 64 + math.cos(a) * rr, fy + 46 + math.sin(a) * rr))
        s.d.polygon(pts, fill=c)
    s.torso_sides_stripe((200, 150, 255), 0, UT_PX, 4)
    hands(s, (210, 214, 226), HAND - 8)
    legs(p, deep, HAND - 10)
    overlay(p, stars_img(4))
    p.outer_stripe((200, 150, 255), 0, HAND - 10, 4)
    shoes(p, (210, 214, 226), HAND - 10, (120, 120, 140))
    return s.im, p.im


def catchpole():
    """Catchpole the Spark catcher: an olive ranger shirt under a brown leather harness with net pouches and a
    tracker clip, cargo trousers with knee guards and rope coils at the hip."""
    s, p = T(), T()
    olive, leather = (90, 110, 40), (120, 75, 45)
    top(s, olive, HAND - 6)
    overlay(s, net_img((50, 60, 30)))
    fx, fy, _, _ = front()
    for a, b in (((fx + 10, fy), (fx + 118, fy + UT_PX)), ((fx + 118, fy), (fx + 10, fy + UT_PX))):
        s.d.line([a, b], fill=leather, width=10)
    for x in (fx + 22, fx + 86):
        s.d.rectangle([x, fy + 64, x + 20, fy + 86], fill=shade(leather, 1.15), outline=DARK)
    badge(s, fx + 64, fy + 51, 8, (170, 255, 90))
    sash(s, leather, UT_PX - 12, 10)
    legs(p, (110, 100, 70), HAND - 12)
    for slots in (RIGHT, LEFT):
        x, y, w, _ = slots["F"]
        p.d.rounded_rectangle([x + 10, y + 44, x + w - 11, y + 66], 4, fill=leather, outline=DARK)
        x, y, w, _ = slots["R" if slots is RIGHT else "L"]
        pocket(p, x + 10, y + 12, w - 20, 22, (110, 100, 70))
    shoes(p, (70, 46, 30), HAND - 12)
    return s.im, p.im


def scorch():
    """Sal Scorch: a charcoal suit cracked with glowing magma veins, an orange shirt, flame cuffs, and the Torch
    Crew's torch mark on the back."""
    s, p = T(), T()
    char = (40, 38, 40)
    top(s, char)
    overlay(s, veins_img((255, 120, 30), 5, 50))
    fx, fy, _, _ = front()
    lapels(s, shade(char, 0.8), 54, 32, (240, 130, 40))
    for slots in (RIGHT, LEFT):
        for sd in SIDES4:
            x, y, w, _ = slots[sd]
            flames(s, x, y + HAND - 22, w, 22, (255, 110, 30), (255, 220, 100))
    bx, by, _, _ = back()
    s.d.polygon([(bx + 56, by + 50), (bx + 72, by + 50), (bx + 68, by + 96), (bx + 60, by + 96)], fill=(90, 80, 70))
    s.d.polygon([(bx + 64, by + 10), (bx + 50, by + 50), (bx + 78, by + 50)], fill=(255, 120, 30))
    s.d.polygon([(bx + 64, by + 24), (bx + 57, by + 48), (bx + 71, by + 48)], fill=(255, 230, 120))
    legs(p, char, HAND - 4)
    overlay(p, veins_img((255, 120, 30), 6, 30))
    shoes(p, (20, 18, 18), HAND - 4)
    return s.im, p.im


def censor():
    """The Censor: a black tuxedo crossed with white redaction bars (blank black and white strips, no words), a
    white shirt and black tie, white gloves."""
    s, p = T(), T()
    top(s, BLACK)
    fx, fy, _, _ = front()
    lapels(s, (50, 50, 56), 60, 34, WHITE)
    tie(s, BLACK, 54)
    rng = random.Random(13)
    for sd in SIDES4:
        x, y, w, _ = TORSO[sd]
        for k in range(10, UT_PX, 22):
            if sd == "F" and 30 < k < 64:
                continue
            x0 = x + rng.randint(0, 20)
            s.d.rectangle([x0, y + k, x0 + rng.randint(30, w - 10), y + k + 6], fill=WHITE)
    for slots in (RIGHT, LEFT):
        for sd in SIDES4:
            x, y, w, _ = slots[sd]
            s.d.rectangle([x + 6, y + 30, x + w - 12, y + 35], fill=WHITE)
    hands(s, WHITE)
    legs(p, BLACK, HAND - 4)
    for slots in (RIGHT, LEFT):
        x, y, w, _ = slots["F"]
        p.d.rectangle([x + 8, y + 50, x + w - 16, y + 55], fill=WHITE)
    shoes(p, (14, 14, 16), HAND - 4, (70, 70, 76))
    return s.im, p.im


def holloway():
    """Doctor Holloway: a director's long white lab coat with riveted steel shoulder plates, an indigo shirt and
    tie, the Ashgrove Labs crest (a flask in a gear), steel-trimmed gloves and boots."""
    s, p = T(), T()
    coat, indigo = (244, 244, 246), (60, 50, 150)
    top(s, coat)
    fx, fy, _, _ = front()
    lapels(s, shade(coat, 0.88), 56, 34, indigo)
    tie(s, (30, 30, 40), 50)
    badge(s, fx + 94, fy + 34, 12, (80, 255, 255))
    s.d.polygon([(fx + 90, fy + 28), (fx + 98, fy + 28), (fx + 101, fy + 40), (fx + 87, fy + 40)], fill=indigo)
    for slots in (RIGHT, LEFT):
        s.limb_band((180, 186, 196), 0, 16)
        for sd in SIDES4:
            x, y, w, _ = slots[sd]
            for k in range(x + 8, x + w, 16):
                s.d.ellipse([k - 2, y + 8, k + 2, y + 12], fill=STEEL)
    hands(s, (180, 186, 196))
    legs(p, (40, 40, 50), HAND - 8)
    for sd in SIDES4:  # the coat's long skirts over the lower torso
        x, y, w, _ = TORSO[sd]
        p.d.rectangle([x, y + UT_PX - 4, x + w - 1, y + 128], fill=coat)
    shoes(p, (180, 186, 196), HAND - 8, STEEL)
    return s.im, p.im


def voidhound():
    """The Voidhound (a hunting machine from the stars): a dark starfield shell in plates outlined with
    ultraviolet seams, a hound's-eye crest on the chest, talon-plated hands and paw-plated feet."""
    s, p = T(), T()
    shell, uv = (40, 44, 60), (190, 90, 255)
    suit(s, shell, HAND)
    overlay(s, stars_img(22, 120, (200, 190, 255)))
    for sd in SIDES4:
        x, y, w, _ = TORSO[sd]
        for k in range(0, 128, 32):
            s.d.line([(x, y + k), (x + w - 1, y + k + 10)], fill=uv, width=2)
    fx, fy, _, _ = front()
    s.d.polygon([(fx + 64, fy + 22), (fx + 92, fy + 46), (fx + 64, fy + 70), (fx + 36, fy + 46)], fill=DARK, outline=uv)
    s.d.ellipse([fx + 52, fy + 36, fx + 76, fy + 56], fill=uv)
    s.d.ellipse([fx + 60, fy + 42, fx + 68, fy + 50], fill=WHITE)
    s.limb_line(uv, 20, 1.0, 2)
    s.limb_line(uv, LOWER, 1.0, 2)
    hands(s, (70, 60, 110))
    legs(p, shell, HAND)
    overlay(p, stars_img(23, 60, (200, 190, 255)))
    p.limb_line(uv, LOWER, 1.0, 2)
    p.outer_stripe(uv, 0, HAND, 3)
    shoes(p, (70, 60, 110), HAND, uv)
    return s.im, p.im


def morrow():
    """Morrow the Mirage: a black stage tuxedo lined in violet, a waistcoat of mirror shards, the four card suits
    on the cuffs, white gloves, black trousers with a violet stripe."""
    s, p = T(), T()
    top(s, BLACK)
    fx, fy, _, _ = front()
    s.d.polygon([(fx + 34, fy), (fx + 94, fy), (fx + 86, fy + UT_PX), (fx + 42, fy + UT_PX)], fill=(170, 176, 190))
    rng = random.Random(19)
    for _ in range(26):
        x, y = rng.randint(fx + 40, fx + 86), rng.randint(fy + 4, fy + UT_PX - 6)
        pts = [(x, y), (x + rng.randint(4, 10), y + rng.randint(-6, 6)), (x + rng.randint(-4, 6), y + rng.randint(5, 12))]
        s.d.polygon(pts, fill=rng.choice(((220, 226, 240), (150, 156, 176), (200, 170, 240))), outline=(90, 90, 110))
    lapels(s, (120, 80, 220), 64, 34)
    tie(s, (120, 80, 220), bow=True)
    for slots in (RIGHT, LEFT):
        x, y, w, _ = slots["F"]
        for k, sym in enumerate(("o", "d", "h", "c")):
            cx, cy = x + 10 + k * 14, y + HAND - 14
            if sym in ("o", "d"):
                s.d.polygon([(cx, cy - 5), (cx + 5, cy), (cx, cy + 5), (cx - 5, cy)], fill=(200, 60, 80))
            else:
                s.d.ellipse([cx - 4, cy - 4, cx + 4, cy + 4], fill=WHITE)
    hands(s, WHITE)
    legs(p, BLACK, HAND - 4)
    p.outer_stripe((120, 80, 220), 0, HAND - 4, 4)
    shoes(p, (14, 14, 16), HAND - 4, (70, 70, 76))
    return s.im, p.im


def clawback():
    """Clawback the Repo King: a mustard repo jumpsuit with charcoal shoulder panels and hi-vis bands, the hook mark
    on the back, a name tag with a hook, charcoal gloves and steel-cap boots."""
    s, p = T(), T()
    mustard, charcoal = (230, 190, 60), (55, 58, 66)
    suit(s, mustard, HAND)
    for sd in SIDES4:
        x, y, w, _ = TORSO[sd]
        s.d.rectangle([x, y, x + w - 1, y + 24], fill=charcoal)
        s.d.rectangle([x, y + 70, x + w - 1, y + 78], fill=(230, 230, 230))
    s.limbs(charcoal, 0, 22)
    s.limb_band((230, 230, 230), 40, 46)
    fx, fy, _, _ = front()
    s.d.rectangle([fx + 62, fy + 24, fx + 66, fy + 128], fill=STEEL)
    s.d.rectangle([fx + 80, fy + 34, fx + 108, fy + 46], fill=WHITE, outline=DARK)
    s.d.arc([fx + 86, fy + 36, fx + 96, fy + 46], 0, 270, fill=(200, 80, 40), width=2)
    bx, by, _, _ = back()
    s.d.line([(bx + 64, by + 30), (bx + 64, by + 70)], fill=charcoal, width=10)
    s.d.arc([bx + 44, by + 56, bx + 84, by + 96], 0, 200, fill=charcoal, width=10)
    hands(s, charcoal)
    legs(p, mustard, HAND - 12)
    p.limb_band((230, 230, 230), LOWER - 4, LOWER + 2)
    shoes(p, charcoal, HAND - 12, STEEL)
    return s.im, p.im


def gale():
    """Gale, the Master's fallen student: a teal fighter's top open at the collar with wind swirls, a white sash,
    fighter's wraps on the forearms, wide black hakama."""
    s, p = T(), T()
    teal = (40, 160, 150)
    top(s, teal, LOWER)
    fx, fy, _, _ = front()
    s.d.polygon([(fx + 40, fy), (fx + 88, fy), (fx + 64, fy + 44)], fill=CLEAR)
    for cx, cy in ((fx + 28, fy + 60), (fx + 100, fy + 40), (TORSO["B"][0] + 64, TORSO["B"][1] + 50)):
        for r in (6, 12, 18):
            s.d.arc([cx - r, cy - r, cx + r, cy + r], 200, 520 - r * 8, fill=(200, 255, 245), width=3)
    sash(s, WHITE, UT_PX - 14, 12)
    s.limbs((236, 232, 222), LOWER, HAND + 4, 1.0, 0.9)
    for slots in (RIGHT, LEFT):
        for sd in SIDES4:
            x, y, w, _ = slots[sd]
            for k in range(LOWER + 3, HAND + 4, 7):
                s.d.line([(x, y + k), (x + w - 1, y + k + 4)], fill=(190, 186, 176), width=1)
    legs(p, BLACK, HAND)
    for slots in (RIGHT, LEFT):
        for sd in SIDES4:
            x, y, w, _ = slots[sd]
            for k in range(x + 8, x + w, 14):
                p.d.line([(k, y), (k, y + HAND)], fill=(70, 70, 80), width=2)
    return s.im, p.im


# ---------------------------------------------------------------- the people (Config.NpcLooks.people order)
PEOPLE = {
    "Gus": gus, "Benny": benny, "Scoops": scoops, "Dot": dot, "Nell": nell, "Pearl": pearl, "Brick": brick,
    "Vanta": vanta, "Nora": nora, "Okafor": okafor, "Ruth": ruth, "Moth": moth, "Tess": tess, "Kiko": kiko,
    "Wren": wren, "Toby": toby, "Flint": flint, "Finn": finn, "Dace": dace, "Ambrose": ambrose, "Hoshi": hoshi,
    "HeadmasterHalo": halo, "Redline": redline, "MasqueARade": masque, "HarvestKing": harvest_king,
    "Bramblebeast": bramblebeast, "CaptainBrine": brine, "Pitboss": pitboss, "Tidewright": tidewright,
    "Vesper": vesper, "Catchpole": catchpole, "Scorch": scorch, "Censor": censor, "Holloway": holloway,
    "Voidhound": voidhound, "Morrow": morrow, "Clawback": clawback, "Gale": gale,
}

# Their faces (faces.py numbers: brow thickness, arch, tilt; eye half width, half height, tilt, lid, lash; iris;
# mouth width, curve, lift, lip weight; extras), where the six shared faces do not fit
BASE = dict(stubble=False, scar=False, freckles=False, cheek=1.0)
FACES = {
    "Gus": dict(BASE, brow=(92, 40, 22), eye=(160, 58, 0, 24, 30), iris=(90, 100, 110), mouth=(420, -10, 0, 0.9),
                stubble=True, cheek=1.2, wrinkles=0.9),
    "Nell": dict(BASE, brow=(70, 50, 12), eye=(165, 60, 6, 16, 40), iris=(70, 120, 160), mouth=(400, 14, 30, 0.8),
                 scar=True, wrinkles=1.0),
    "Brick": dict(BASE, brow=(88, 24, 24), eye=(160, 56, 0, 20, 28), iris=(90, 70, 50), mouth=(440, -4, 20, 1.0),
                  stubble=True, scar=True, bump=True, wrinkles=0.5, cheek=1.4),
    "Ruth": dict(BASE, brow=(52, 90, 0), eye=(165, 66, 4, 10, 40), iris=(120, 90, 60), mouth=(420, 40, 10, 0.8),
                 wrinkles=1.0, glasses=(150, 110, 60)),
    "Moth": dict(BASE, brow=(48, 110, 4), eye=(170, 64, 14, 22, 70), iris=(120, 80, 140), mouth=(380, 20, 30, 0.9),
                 wrinkles=0.8, lashes=True, mole=True),
    "Ambrose": dict(BASE, brow=(70, 90, 0), eye=(165, 62, 10, 14, 40), iris=(80, 140, 200), mouth=(460, 50, 20, 0.9),
                    wrinkles=0.9),
    "Hoshi": dict(BASE, brow=(60, 30, -6), eye=(165, 40, 0, 30, 20), iris=(70, 60, 50), mouth=(380, 16, 0, 0.7),
                  wrinkles=1.0),
    "Wren": dict(BASE, brow=(48, 100, -4), eye=(175, 96, 4, 0, 30), iris=(120, 80, 50), mouth=(340, 40, 0, 1.0),
                 cheek=0.6),
    "Toby": dict(BASE, brow=(46, 110, -6), eye=(180, 100, 2, 0, 24), iris=(90, 140, 200), mouth=(300, -8, 0, 1.0),
                 freckles=True, cheek=0.5),
    "Finn": dict(BASE, brow=(50, 90, 0), eye=(175, 92, 4, 0, 30), iris=(80, 150, 120), mouth=(360, 60, 20, 1.0),
                 freckles=True, cheek=0.6),
    "Flint": dict(BASE, brow=(60, 60, 18), eye=(170, 80, 10, 6, 40), iris=(180, 120, 60), mouth=(380, 8, 30, 1.0),
                  freckles=True, plaster=True, cheek=0.8),
    "Kiko": dict(BASE, brow=(54, 80, 10), eye=(175, 90, 14, 0, 50), iris=(60, 50, 40), mouth=(340, 40, 0, 1.0),
                 cheek=0.6),
    "Vesper": dict(BASE, brow=(46, 110, 6), eye=(178, 82, 14, 4, 80), iris=(200, 150, 255), mouth=(400, 20, 20, 1.3),
                   lashes=True, mole=True, cheek=1.1),
    "Pitboss": dict(BASE, brow=(96, 20, 30), eye=(160, 56, 6, 24, 30), iris=(255, 140, 60), mouth=(500, 46, 60, 1.2),
                    stone=True, cheek=1.5),
    "Tidewright": dict(BASE, brow=(90, 20, 30), eye=(170, 60, 0, 0, 0), iris=(120, 255, 230), mouth=(400, 0, 0, 0.0),
                       machine=(200, 150, 80), glow=(120, 255, 230)),
    "Holloway": dict(BASE, brow=(56, 40, 22), eye=(170, 58, 10, 24, 46), iris=(150, 205, 230), mouth=(380, -10, 0, 0.6),
                     wrinkles=0.6, cheek=1.4),
}
# the on-body preview's skin, hair and face per person (their look's skin and hair; a stock face by its visage)
K = [None, (255, 224, 196), (241, 194, 160), (224, 172, 130), (198, 140, 100), (160, 105, 70), (120, 78, 52),
     (86, 56, 38), (60, 40, 28), (255, 236, 220), (250, 214, 186)]
STONE, METAL, GLOW = (150, 140, 130), (170, 175, 185), (255, 170, 60)
SILVER, BLACKH, CHOC, WHITEH = (190, 192, 200), (24, 24, 28), (80, 50, 30), (240, 240, 240)
PREVIEW = {
    "Gus": (K[4], SILVER, "Gus"), "Benny": (K[5], BLACKH, "Hero"), "Scoops": (K[5], CHOC, "Rookie"),
    "Dot": (K[3], CHOC, "Hero"), "Nell": (K[4], WHITEH, "Nell"), "Pearl": (K[6], BLACKH, "Hero"),
    "Brick": (K[6], SILVER, "Brick"), "Vanta": (K[5], SILVER, "Cold"), "Nora": (K[4], CHOC, "Hero"),
    "Okafor": (K[7], BLACKH, "Hero"), "Ruth": (K[2], WHITEH, "Ruth"), "Moth": (K[4], SILVER, "Moth"),
    "Tess": (K[5], BLACKH, "Rookie"), "Kiko": (K[10], BLACKH, "Kiko"), "Wren": ((160, 110, 80), (40, 28, 24), "Wren"),
    "Toby": (K[1], (230, 170, 70), "Toby"), "Flint": (K[3], (200, 90, 40), "Flint"), "Finn": (K[4], CHOC, "Finn"),
    "Dace": (K[5], BLACKH, "Hero"), "Ambrose": (K[3], WHITEH, "Ambrose"), "Hoshi": (K[2], SILVER, "Hoshi"),
    "HeadmasterHalo": (K[3], (200, 170, 90), "Stern"), "Redline": (K[5], (200, 40, 40), "Sharp"),
    "MasqueARade": (K[2], (90, 30, 120), "Sharp"), "HarvestKing": (K[4], SILVER, "Stern"),
    "Bramblebeast": (GLOW, (60, 140, 60), "Sharp"), "CaptainBrine": (K[3], WHITEH, "Scarred"),
    "Pitboss": (STONE, BLACKH, "Pitboss"), "Tidewright": (METAL, (160, 230, 210), "Tidewright"),
    "Vesper": (K[10], WHITEH, "Vesper"), "Catchpole": (K[4], CHOC, "Sharp"), "Scorch": (K[3], (230, 70, 30), "Scarred"),
    "Censor": (K[9], BLACKH, "Cold"), "Holloway": (K[2], SILVER, "Holloway"), "Voidhound": (METAL, (40, 44, 60), "Cold"),
    "Morrow": (K[9], BLACKH, "Sharp"), "Clawback": (K[4], CHOC, "Scarred"), "Gale": (K[3], (55, 58, 66), "Sharp"),
}
CRACKED = ("Vesper",)  # a famous fake: her unmasked face too
# the on-body preview pages (art/blender/clothed.py people <page>): 8 a page
PAGES = [list(PEOPLE)[i:i + 8] for i in range(0, len(PEOPLE), 8)]


def save(name, shirt, pants):
    both = Image.new("RGBA", (W * 2, H), CLEAR)
    both.paste(shirt, (0, 0))
    both.paste(pants, (W, 0))
    base = os.path.join(OUT, name)
    both.save(base + ".png")
    shirt.save(base + "_Shirt.png")
    pants.save(base + "_Pants.png")
    return both


if __name__ == "__main__":
    sheets = []
    for name, fn in PEOPLE.items():
        sh, pa = fn()
        sheets.append((name, save(name, sh, pa)))
    made = 0
    for name, f in FACES.items():
        faces.small(faces.face(f, False)).save(os.path.join(OUT, "Face_%s.png" % name))
        made += 1
        if name in CRACKED:
            faces.small(faces.face(f, False, True)).save(os.path.join(OUT, "Face_%s_Cracked.png" % name))
            made += 1
    # the template sheet: every outfit (shirt | pants), four a row
    tw, th = 780, 373
    cols = 4
    rows = (len(sheets) + cols - 1) // cols
    sheet_im = Image.new("RGB", (tw * cols, th * rows), (120, 120, 120))
    for i, (name, im) in enumerate(sheets):
        tile = Image.new("RGBA", im.size, (150, 150, 150, 255))
        tile.alpha_composite(im)
        sheet_im.paste(tile.convert("RGB").resize((tw - 6, th - 6)), ((i % cols) * tw + 3, (i // cols) * th + 3))
    sheet_im.save(os.path.join(ROOT, "preview", "people_templates.png"))
    # the faces sheet: each face on its person's skin
    SKIN = {"Gus": (200, 150, 110), "Nell": (198, 140, 100), "Brick": (120, 78, 52), "Ruth": (241, 194, 160),
            "Moth": (198, 140, 100), "Ambrose": (224, 172, 130), "Hoshi": (241, 194, 160), "Wren": (160, 110, 80),
            "Toby": (255, 224, 196), "Finn": (198, 140, 100), "Flint": (224, 172, 130), "Kiko": (241, 194, 160),
            "Vesper": (236, 196, 170), "Pitboss": (150, 140, 130), "Tidewright": (170, 120, 70),
            "Holloway": (241, 194, 160)}
    names = list(FACES) + ["Vesper_Cracked"]
    T_ = 300
    cols = 6
    fs = Image.new("RGB", (T_ * cols, T_ * ((len(names) + cols - 1) // cols)), (40, 42, 48))
    for i, n in enumerate(names):
        im = Image.open(os.path.join(OUT, "Face_%s.png" % n)).convert("RGBA")
        tile = Image.new("RGBA", im.size, SKIN[n.split("_")[0]] + (255,))
        tile.alpha_composite(im)
        fs.paste(tile.convert("RGB").resize((T_ - 8, T_ - 8)), ((i % cols) * T_ + 4, (i // cols) * T_ + 4))
    fs.save(os.path.join(ROOT, "preview", "people_faces.png"))
    # for art/blender/clothed.py people <page> (no PIL there): each page's people with skin, hair and face file
    import json
    rows = []
    for page in PAGES:
        rows.append([{"name": n, "skin": PREVIEW[n][0], "hair": PREVIEW[n][1],
                      "face": ("people/Face_" + n) if n in FACES else ("faces/Face_" + PREVIEW[n][2])} for n in page])
    with open(os.path.join(OUT, "preview.json"), "w") as f:
        json.dump(rows, f, indent=1)
    print("wrote", len(sheets), "outfits and", made, "faces")
