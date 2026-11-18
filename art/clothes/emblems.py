# art/clothes/emblems.py: the hero creator's Emblems tab as drawn images (overnight queue item 12, 2026-11-18),
# replacing the text glyphs (Config.Creator.shapes) on the chest. Every mark is original and simple enough to
# read on a phone: a bold shape with a thick comic ink line and one cel shadow. Nothing here copies a real hero's
# symbol, a team, brand or a protected emblem (the cross is a rounded plus with an open ring at its centre, never
# a plain red cross; the ring star is a star crossed by a tilted orbit, never a star in rings).
# Images (Decal uploads, used as ImageLabels on the chest plate's SurfaceGui; ImageColor3 multiplies):
#   Emblem_<shape>.png        the mark, white with a grey shadow (takes the emblem slot's accent) and dark ink
#   EmblemBack_<backing>.png  badge (circle), crest (shield), gem (cut stone): the face, white (takes the trim)
#   EmblemRim_<backing>.png   that backing's rim band, white (takes the accent), ink edges stay dark
# Output: art/export/clothes/emblems/*.png (256 px) and art/preview/emblems.png (every shape on every backing in
# sample colours, as the game tints them). Run: python3 art/clothes/emblems.py   (PIL only)
import math
import os

from PIL import Image, ImageChops, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "export", "clothes", "emblems")
os.makedirs(OUT, exist_ok=True)

S = 1024  # drawn at 1024, saved at PX
PX = 256
INK = (22, 22, 30)
LINE = 56  # the ink line's width at 1024


def polar(cx, cy, r, deg):
    a = math.radians(deg)
    return (cx + r * math.cos(a), cy + r * math.sin(a))


def star_pts(cx, cy, r, ri, n=5, rot=-90):
    return [polar(cx, cy, r if i % 2 == 0 else ri, rot + i * 180 / n) for i in range(n * 2)]


def mask():
    return Image.new("L", (S, S), 0)


def draw(m):
    return ImageDraw.Draw(m)


# ---------------------------------------------------------------- shapes as masks (255 inside)
def m_star():
    m = mask()
    draw(m).polygon(star_pts(512, 540, 430, 185), fill=255)
    return m


def m_spark():
    m = mask()
    d = draw(m)
    pts = []
    for i in range(4):  # a four-point sparkle with concave sides
        a = -90 + i * 90
        pts.append(polar(512, 512, 450, a))
        for k in (0.3, 0.5, 0.7):
            b = a + 90 * k
            r = 120 + 50 * abs(k - 0.5) * 2
            pts.append(polar(512, 512, r, b))
    d.polygon(pts, fill=255)
    return m


def m_diamond():
    m = mask()
    draw(m).polygon([(512, 70), (850, 512), (512, 954), (174, 512)], fill=255)
    return m


def m_orb():
    m = mask()
    draw(m).ellipse([110, 110, 914, 914], fill=255)
    return m


def m_peak():
    m = mask()
    d = draw(m)
    d.polygon([(512, 110), (930, 860), (94, 860)], fill=255)
    return m


def m_heart():
    m = mask()
    d = draw(m)
    d.ellipse([100, 150, 540, 590], fill=255)
    d.ellipse([484, 150, 924, 590], fill=255)
    d.polygon([(126, 450), (898, 450), (512, 900)], fill=255)
    return m


def m_cross():
    m = mask()
    d = draw(m)
    w = 150
    d.rounded_rectangle([512 - w, 100, 512 + w, 924], 120, fill=255)
    d.rounded_rectangle([100, 512 - w, 924, 512 + w], 120, fill=255)
    d.ellipse([512 - 250, 512 - 250, 512 + 250, 512 + 250], fill=255)
    d.ellipse([512 - 110, 512 - 110, 512 + 110, 512 + 110], fill=0)  # the open ring at its heart
    return m


def m_moon():
    m = mask()
    d = draw(m)
    d.ellipse([110, 110, 914, 914], fill=255)
    d.ellipse([330, 40, 1060, 770], fill=0)
    return m


def m_clover():
    m = mask()
    d = draw(m)
    for a in (-90, 30, 150):  # three leaves round a centre, and a curling stem
        cx, cy = polar(512, 470, 200, a)
        d.ellipse([cx - 210, cy - 210, cx + 210, cy + 210], fill=255)
    d.polygon([(480, 520), (560, 520), (640, 930), (560, 950)], fill=255)
    return m


def m_flower():
    m = mask()
    d = draw(m)
    for i in range(5):
        cx, cy = polar(512, 512, 240, -90 + i * 72)
        d.ellipse([cx - 190, cy - 190, cx + 190, cy + 190], fill=255)
    d.ellipse([312, 312, 712, 712], fill=255)
    return m


def m_hex():
    m = mask()
    draw(m).polygon([polar(512, 512, 440, 30 + i * 60) for i in range(6)], fill=255)
    return m


def m_ringstar():
    m = mask()
    d = draw(m)
    d.polygon(star_pts(512, 520, 360, 155), fill=255)
    ring = Image.new("L", (S, S), 0)  # a tilted orbit crossing the star
    rd = draw(ring)
    rd.ellipse([40, 380, 984, 660], fill=255)
    rd.ellipse([130, 440, 894, 600], fill=0)
    ring = ring.rotate(-18, center=(512, 512))
    return ImageChops.lighter(m, ring)


def m_quad():
    m = mask()
    d = draw(m)
    for dx, dy in ((0, -1), (1, 0), (0, 1), (-1, 0)):
        cx, cy = 512 + dx * 230, 512 + dy * 230
        d.polygon([(cx, cy - 200), (cx + 200, cy), (cx, cy + 200), (cx - 200, cy)], fill=255)
    return m


def m_burst():
    m = mask()
    draw(m).polygon(star_pts(512, 512, 450, 300, n=12, rot=-90), fill=255)
    return m


def m_spade():
    m = mask()
    d = draw(m)
    d.ellipse([110, 380, 530, 800], fill=255)
    d.ellipse([494, 380, 914, 800], fill=255)
    d.polygon([(136, 560), (888, 560), (512, 80)], fill=255)
    d.polygon([(512, 620), (650, 940), (374, 940)], fill=255)
    return m


def m_lab():
    m = mask()
    d = draw(m)  # a flask with a bubble rising from it
    d.rectangle([410, 120, 614, 420], fill=255)
    d.rounded_rectangle([360, 90, 664, 170], 30, fill=255)
    d.polygon([(410, 400), (614, 400), (900, 880), (124, 880)], fill=255)
    d.rounded_rectangle([110, 800, 914, 920], 50, fill=255)
    return m


def m_alien():
    m = mask()
    d = draw(m)  # a falling star: a round head and three tapered tails fanning up behind it
    hx, hy, hr = 640, 640, 230
    d.ellipse([hx - hr, hy - hr, hx + hr, hy + hr], fill=255)
    for ang, length, half in ((225, 620, 150), (200, 470, 80), (250, 470, 80)):
        tip = polar(hx, hy, length, ang)
        l, r = polar(hx, hy, half, ang + 90), polar(hx, hy, half, ang - 90)
        d.polygon([l, tip, r], fill=255)
    return m


def m_relic():
    m = mask()
    d = draw(m)  # a medallion: a disc ringed with eight points
    d.polygon(star_pts(512, 512, 470, 360, n=8, rot=-90), fill=255)
    return m


def m_tech():
    m = mask()
    d = draw(m)  # a cog with eight teeth and an open centre
    d.ellipse([200, 200, 824, 824], fill=255)
    for i in range(8):
        a = i * 45
        c = polar(512, 512, 360, a)
        pts = [polar(c[0], c[1], 110, a + k) for k in (-50, 50, 130, 230)]
        d.polygon(pts, fill=255)
    d.ellipse([400, 400, 624, 624], fill=0)
    return m


def m_dojo():
    m = mask()
    d = draw(m)  # a tied training belt: the band, its square knot and two tails
    d.rounded_rectangle([70, 330, 954, 500], 50, fill=255)
    d.polygon([(470, 470), (560, 470), (420, 940), (250, 900)], fill=255)
    d.polygon([(464, 470), (554, 470), (774, 900), (604, 940)], fill=255)
    d.rounded_rectangle([392, 270, 632, 560], 40, fill=255)
    return m


def m_born():
    m = mask()
    d = draw(m)  # a birthmark: a sun with a spiral ring around a dot
    d.polygon(star_pts(512, 512, 460, 330, n=7, rot=-90), fill=255)
    d.ellipse([300, 300, 724, 724], fill=0)
    d.ellipse([400, 400, 624, 624], fill=255)
    return m


def m_storm():
    m = mask()
    d = draw(m)  # a storm cloud with a bolt falling from it
    for box in ([120, 260, 470, 560], [320, 140, 720, 520], [560, 260, 904, 560]):
        d.ellipse(box, fill=255)
    d.rounded_rectangle([150, 420, 874, 600], 80, fill=255)
    d.polygon([(560, 560), (420, 760), (520, 760), (430, 960), (680, 700), (570, 700), (650, 560)], fill=255)
    return m


def m_serum():
    m = mask()
    d = draw(m)  # a vial on its side tilted up, a drop falling
    d.rounded_rectangle([380, 90, 644, 170], 30, fill=255)
    d.rounded_rectangle([410, 150, 614, 720], 100, fill=255)
    d.ellipse([436, 780, 588, 932], fill=255)
    d.polygon([(512, 720), (450, 840), (574, 840)], fill=255)
    return m


def m_spirit():
    m = mask()
    d = draw(m)  # a spirit flame: a teardrop with a curl
    d.ellipse([230, 380, 794, 944], fill=255)
    d.polygon([(250, 620), (512, 60), (774, 620)], fill=255)
    d.ellipse([400, 560, 624, 784], fill=0)
    return m


def m_heir():
    m = mask()
    d = draw(m)  # an old key: a ring bow, a shaft and two teeth
    d.ellipse([120, 120, 520, 520], fill=255)
    d.ellipse([230, 230, 410, 410], fill=0)
    d.polygon([(420, 360), (480, 300), (920, 740), (860, 800)], fill=255)
    d.polygon([(720, 720), (780, 660), (880, 760), (820, 820)], fill=255)
    d.polygon([(620, 620), (680, 560), (760, 640), (700, 700)], fill=255)
    return m


SHAPES = {"star": m_star, "spark": m_spark, "diamond": m_diamond, "orb": m_orb, "peak": m_peak, "heart": m_heart,
          "cross": m_cross, "moon": m_moon, "clover": m_clover, "flower": m_flower, "hex": m_hex,
          "ringstar": m_ringstar, "quad": m_quad, "burst": m_burst, "spade": m_spade, "lab": m_lab,
          "alien": m_alien, "relic": m_relic, "tech": m_tech, "dojo": m_dojo,
          "born": m_born, "storm": m_storm, "serum": m_serum, "spirit": m_spirit, "heir": m_heir}


def grow(m, width):
    """The mask grown (width > 0) or shrunk (width < 0) by about |width| / 2 on every side, with round corners
    (a blur and a threshold: fast at 1024 px, where a rank filter of this size is not)."""
    from PIL import ImageFilter
    b = m.filter(ImageFilter.GaussianBlur(abs(width) / 4))
    cut = 14 if width > 0 else 241
    return b.point(lambda v: 255 if v >= cut else 0)


def outline(m, width):
    """The mask grown by `width`: the ink line round a shape."""
    return grow(m, width)


def cel(m):
    """A light grey shadow over the lower right of a shape (the light comes from the upper left)."""
    sh = Image.new("L", (S, S), 0)
    d = draw(sh)
    d.polygon([(S, 0), (S, S), (0, S), (S * 0.1, S * 0.9), (S * 0.9, S * 0.1)], fill=255)
    sh = sh.transform((S, S), Image.AFFINE, (1, 0, -80, 0, 1, -80))
    inner = ImageChops.multiply(m, sh)
    return inner


def render(m, shade=True, line=LINE, thin=None):
    """A shape mask as a tintable image: white face, grey shadow, dark ink line outside it (and thin inner lines)."""
    from PIL import ImageFilter
    big = outline(m, line)
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    im.paste((*INK, 255), (0, 0), big)
    im.paste((255, 255, 255, 255), (0, 0), m)
    if shade:
        im.paste((196, 196, 200, 255), (0, 0), cel(grow(m, -41)))
    return im


def save(im, name):
    im.resize((PX, PX), Image.LANCZOS).save(os.path.join(OUT, name + ".png"))
    return im


# ---------------------------------------------------------------- backings
def b_badge():
    m = mask()
    draw(m).ellipse([40, 40, 984, 984], fill=255)
    return m


def b_crest():
    m = mask()
    d = draw(m)
    pts = [(80, 60), (944, 60), (944, 470)]
    for i in range(1, 21):  # the shield's curved sides to its point
        t = i / 20
        pts.append((944 - 432 * t, 470 + 500 * math.sin(t * math.pi / 2)))
    pts.append((512, 990))
    for i in range(20, 0, -1):
        t = i / 20
        pts.append((80 + 432 * t, 470 + 500 * math.sin(t * math.pi / 2)))
    pts.append((80, 470))
    d.polygon(pts, fill=255)
    return m


def b_gem():
    m = mask()  # an emerald cut: a tall stone with its corners cut off
    draw(m).polygon([(250, 30), (774, 30), (944, 200), (944, 824), (774, 994), (250, 994), (80, 824), (80, 200)],
                    fill=255)
    return m


BACKINGS = {"badge": b_badge, "crest": b_crest, "gem": b_gem}


def backing_images(m):
    from PIL import ImageFilter
    shrink = grow(m, -130)  # the face sits inside the rim band
    face = render(shrink, shade=True, line=1)
    face.putalpha(ImageChops.multiply(face.getchannel("A"), shrink))
    rim = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    edge = grow(m, -26)
    rim.paste((*INK, 255), (0, 0), m)
    rim.paste((255, 255, 255, 255), (0, 0), edge)
    rim.paste((0, 0, 0, 0), (0, 0), grow(shrink, 9))
    inner_line = ImageChops.subtract(grow(shrink, 17), shrink)
    rim.paste((*INK, 255), (0, 0), inner_line)
    return face, rim


def tinted(im, rgb):
    r, g, b, a = im.split()
    r = r.point(lambda v: v * rgb[0] // 255)
    g = g.point(lambda v: v * rgb[1] // 255)
    b = b.point(lambda v: v * rgb[2] // 255)
    return Image.merge("RGBA", (r, g, b, a))


if __name__ == "__main__":
    glyphs = {}
    for name, fn in SHAPES.items():
        glyphs[name] = save(render(fn()), "Emblem_" + name)
    backs = {}
    for name, fn in BACKINGS.items():
        face, rim = backing_images(fn())
        save(face, "EmblemBack_" + name)
        save(rim, "EmblemRim_" + name)
        backs[name] = (face, rim)
    # the preview: every shape bare and on each backing, in sample (trim, accent) colours, on suit-coloured cloth
    samples = [((235, 60, 60), (255, 210, 60), (40, 110, 220)), ((30, 45, 120), (110, 210, 255), (120, 80, 220)),
               ((24, 24, 28), (120, 255, 80), (55, 58, 66)), ((245, 245, 245), (235, 60, 60), (40, 150, 80))]
    cell = 150
    sheet = Image.new("RGB", (cell * len(SHAPES), cell * 4), (90, 90, 96))
    for j, name in enumerate(SHAPES):
        for i, back in enumerate((None, "badge", "crest", "gem")):
            trim, acc, cloth = samples[(i + j) % len(samples)]
            c = Image.new("RGBA", (S, S), (*cloth, 255))
            if back:
                face, rim = backs[back]
                c.alpha_composite(tinted(face, trim))
                c.alpha_composite(tinted(rim, acc))
                g = tinted(glyphs[name], acc).resize((620, 620), Image.LANCZOS)
                c.alpha_composite(g, (202, 190 if back == "crest" else 202))
            else:
                c.alpha_composite(tinted(glyphs[name], acc))
            sheet.paste(c.convert("RGB").resize((cell - 6, cell - 6), Image.LANCZOS), (j * cell + 3, i * cell + 3))
    sheet.save(os.path.join(ROOT, "preview", "emblems.png"))
    print("wrote", len(SHAPES), "marks and", len(BACKINGS), "backings")
