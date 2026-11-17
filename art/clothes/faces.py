# art/clothes/faces.py: the face decals every Roblox-look robot shares (and citizens later), in a comic-book hero
# style rather than a cartoon one (nate, 2026-11-17: "not enough detail and looks too kiddish ... accessible to
# all ages but not super kiddish"; "dont want enemies to get repetitive"). Each face has a human version and a
# turned one (dark whites, glowing irises, an android seam on one cheek). The shading is see-through dark, so
# one face works on every skin tone. A robot picks its face from its id, like its skin and hair.
# Lore step 4: a cracked version of each (a famous fake unmasked: half the face torn away to a riveted metal
# plate with a glowing eye, cracks running out across the skin). PLACEHOLDER ART until nate uploads them.
# Output: art/export/clothes/faces/Face_<Name>.png, Face_<Name>_Turned.png and Face_<Name>_Cracked.png
# (1024 px), and art/preview/faces.png (human on two skin tones, turned, cracked).
# Run: python3 art/clothes/faces.py   (PIL only)
import math
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "export", "clothes", "faces")
os.makedirs(OUT, exist_ok=True)

S = 2048  # drawn at 2x, saved at 1024 (smooth edges)
INK = (38, 26, 22)
SHADE = (70, 38, 30)

# The faces. brow: thickness, arch (how high the middle rises), tilt (+ angles down to the nose); eye: half
# width, half height, tilt of the outer corner (+ up), lid (how far the upper lid hangs over: hooded eyes),
# lash (outer flick length); iris colour; mouth: width, curve (+ smile), lift (one corner up: a smirk), lip
# (lower lip weight); extras: stubble, scar (over the left eye), freckles, cheek (cheekbone strength).
FACES = {
    "Hero": dict(brow=(64, 80, 10), eye=(175, 78, 8, 0, 40), iris=(70, 120, 175), mouth=(460, 30, 40, 1.0),
                 stubble=False, scar=False, freckles=False, cheek=1.0),
    "Stern": dict(brow=(84, 30, 26), eye=(170, 62, 2, 18, 34), iris=(95, 75, 50), mouth=(440, -6, 0, 0.8),
                  stubble=True, scar=False, freckles=False, cheek=1.3),
    "Sharp": dict(brow=(46, 110, 4), eye=(180, 84, 16, 0, 70), iris=(80, 140, 90), mouth=(400, 40, 0, 1.4),
                  stubble=False, scar=False, freckles=False, cheek=0.9),
    "Scarred": dict(brow=(70, 60, 16), eye=(168, 70, 6, 8, 36), iris=(130, 135, 140), mouth=(450, 10, 60, 0.9),
                    stubble=True, scar=True, freckles=False, cheek=1.2),
    "Rookie": dict(brow=(56, 90, 0), eye=(170, 90, 4, 0, 34), iris=(110, 80, 50), mouth=(420, 60, 20, 1.0),
                   stubble=False, scar=False, freckles=True, cheek=0.8),
    "Cold": dict(brow=(60, 50, 20), eye=(176, 60, 12, 26, 50), iris=(150, 205, 230), mouth=(400, -14, 0, 0.6),
                 stubble=False, scar=False, freckles=False, cheek=1.4),
}


def bez(p0, p1, p2, p3, n=24):
    """Points along a cubic Bezier curve."""
    out = []
    for i in range(n + 1):
        t = i / n
        a, b, c, d = (1 - t) ** 3, 3 * t * (1 - t) ** 2, 3 * t * t * (1 - t), t ** 3
        out.append((a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0], a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1]))
    return out


def soft(shapes, blur):
    """A blurred layer of shapes (kind, coords, rgba): soft shading."""
    lay = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    for kind, xy, c in shapes:
        getattr(d, kind)(xy, fill=c)
    return lay.filter(ImageFilter.GaussianBlur(blur))


def crack(im):
    """Lore step 4: tear the viewer's right half of the face away to a metal plate with a glowing eye."""
    import random
    rnd = random.Random(23)
    cx, cy = 1460, 1060
    # a jagged tear round the right eye and cheek, reaching past the middle of the face
    edge = []
    wobble = 0.0
    for i in range(54):
        a = i / 54 * 2 * math.pi + rnd.uniform(-0.03, 0.03)
        rx, ry = 600, 700
        wobble = wobble * 0.6 + rnd.uniform(-0.1, 0.1)  # long irregular bulges, not a saw edge
        r = 1 + wobble + rnd.choice((0, 0, 0, 0.1, -0.07))
        edge.append((cx + math.cos(a) * rx * r, cy + math.sin(a) * ry * r))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).polygon(edge, fill=255)
    # the metal: a cool steel gradient with brushed streaks, panel seams and rivets
    metal = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    md = ImageDraw.Draw(metal)
    for y in range(0, S, 4):
        v = int(150 - (y / S) * 55)
        md.rectangle([0, y, S, y + 4], fill=(v, v + 4, v + 14, 255))
    for _ in range(140):
        y = rnd.uniform(300, 1900)
        x = rnd.uniform(860, 2048)
        md.line([(x, y), (x + rnd.uniform(60, 200), y + rnd.uniform(-6, 6))], fill=(190, 196, 206, 70), width=3)
    seams = [[(1060, 760), (1980, 720)], [(1080, 1360), (1990, 1400)], [(1520, 380), (1560, 1780)]]
    for sm in seams:
        md.line(sm, fill=(52, 56, 66, 255), width=10)
        md.line([(sm[0][0], sm[0][1] + 10), (sm[1][0], sm[1][1] + 10)], fill=(200, 206, 216, 160), width=4)
    for x, y in [(1180, 820), (1400, 805), (1700, 790), (1180, 1310), (1720, 1440), (1600, 520), (1610, 1650)]:
        md.ellipse([x - 22, y - 22, x + 22, y + 22], fill=(90, 94, 104, 255))
        md.ellipse([x - 12, y - 16, x + 8, y + 2], fill=(220, 226, 236, 255))
    # the eye: a dark lens housing with a hot red-orange glow
    ex, ey = 1424, 935
    md.ellipse([ex - 150, ey - 120, ex + 150, ey + 120], fill=(26, 26, 32, 255))
    md.ellipse([ex - 120, ey - 92, ex + 120, ey + 92], fill=(60, 20, 18, 255))
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([ex - 170, ey - 150, ex + 170, ey + 150], fill=(255, 70, 40, 230))
    metal.alpha_composite(glow.filter(ImageFilter.GaussianBlur(46)))
    md = ImageDraw.Draw(metal)
    md.ellipse([ex - 78, ey - 66, ex + 78, ey + 66], fill=(255, 80, 45, 255))
    md.ellipse([ex - 46, ey - 38, ex + 46, ey + 38], fill=(255, 190, 120, 255))
    md.ellipse([ex - 18, ey - 15, ex + 18, ey + 15], fill=(255, 250, 235, 255))
    # a shadow just inside the tear (the skin stands proud of the metal)
    shade = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shade).line(edge + [edge[0]], fill=(0, 0, 0, 200), width=70)
    shade = shade.filter(ImageFilter.GaussianBlur(26))
    metal.alpha_composite(shade)
    cut = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    cut.paste(metal, (0, 0), mask)
    im.alpha_composite(cut)
    d = ImageDraw.Draw(im)
    # the torn skin edge: an ink line with a pale peeled lip, and cracks running out across the face
    d.line(edge + [edge[0]], fill=(*INK, 255), width=18, joint="curve")
    d.line([(x - 10, y - 10) for x, y in edge] + [(edge[0][0] - 10, edge[0][1] - 10)], fill=(255, 240, 225, 90), width=6)
    for a0 in (2.7, 3.3, 3.9, 4.6, 1.9):
        x, y = cx + math.cos(a0) * 600, cy + math.sin(a0) * 700
        pts = [(x, y)]
        for _ in range(4):
            x += math.cos(a0) * rnd.uniform(60, 120) + rnd.uniform(-40, 40)
            y += math.sin(a0) * rnd.uniform(60, 120) + rnd.uniform(-40, 40)
            pts.append((x, y))
        d.line(pts, fill=(*INK, 230), width=9, joint="curve")
    return im


def face(f, turned, cracked=False):
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    k = f["cheek"]
    # form shading: cheekbone hollows and jaw sides (a narrow band each side), under the brows, the nose's side,
    # under the nose and the lower lip, the chin
    im.alpha_composite(soft([
        ("polygon", [(300, 1180), (520, 1240), (470, 1420), (260, 1380)], (*SHADE, int(30 * k))),
        ("polygon", [(1748, 1180), (1528, 1240), (1578, 1420), (1788, 1380)], (*SHADE, int(30 * k))),
        ("polygon", [(80, 1500), (260, 1560), (420, 1980), (200, 2048), (60, 2048)], (*SHADE, int(32 * k))),
        ("polygon", [(1968, 1500), (1788, 1560), (1628, 1980), (1848, 2048), (1988, 2048)], (*SHADE, int(32 * k))),
        ("ellipse", [470, 760, 900, 900], (*SHADE, 55)), ("ellipse", [1148, 760, 1578, 900], (*SHADE, 55)),
        ("polygon", [(1040, 880), (1090, 880), (1110, 1300), (1050, 1300)], (*SHADE, 70)),
        ("ellipse", [890, 1270, 1160, 1370], (*SHADE, 70)),
        ("ellipse", [880, 1610, 1170, 1690], (*SHADE, int(60 * f["mouth"][3]))),
        ("ellipse", [860, 1820, 1190, 1960], (*SHADE, 45)),
    ], 40))
    if f["stubble"]:
        # a short beard shadow round the jaw and lip, as speckle over a faint tone
        def jaw(x, y):  # inside the jaw's U (under the cheekbones, round the chin)
            return y > 1470 and ((x - 1024) / 640) ** 2 + ((y - 1470) / 620) ** 2 <= 1

        jawline = [(1024 + 640 * math.cos(a / 40 * math.pi), 1470 + 620 * math.sin(a / 40 * math.pi)) for a in range(41)]
        im.alpha_composite(soft([("polygon", jawline, (40, 30, 26, 46)),
                                 ("ellipse", [830, 1440, 1218, 1525], (40, 30, 26, 40))], 34))
        sp = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        sd = ImageDraw.Draw(sp)
        import random
        rnd = random.Random(7)
        for _ in range(2600):
            x, y = rnd.uniform(330, 1718), rnd.uniform(1430, 2040)
            inside = jaw(x, y) or (((x - 1024) / 190) ** 2 + ((y - 1484) / 42) ** 2 <= 1)
            if inside and not (1545 < y < 1660 and 800 < x < 1250):
                sd.ellipse([x, y, x + 6, y + 6], fill=(30, 22, 20, 120))
        im.alpha_composite(sp)
    d = ImageDraw.Draw(im)
    thick, arch, tilt = f["brow"]
    ew, eh, etilt, lid, lash = f["eye"]
    for s in (-1, 1):
        cx = S // 2 + s * 400
        # the brow: heavier toward the nose, tapering out
        inner = (S // 2 + s * 150, 700 + tilt * 0.5)
        outer = (S // 2 + s * 640, 690 - tilt * 0.3)
        top = bez(inner, (cx - s * 150, 690 - arch - thick * 0.3), (cx + s * 80, 690 - arch), outer, 30)
        bot = bez(outer, (cx + s * 80, 690 - arch + thick * 0.75), (cx - s * 150, 690 - arch * 0.5 + thick),
                  (inner[0], inner[1] + thick), 30)
        if f["scar"] and s < 0:
            # a cut through the left brow: leave a gap
            gap = [p for p in top if abs(p[0] - (cx + 40)) > 26]
            d.polygon(gap + [p for p in bot if abs(p[0] - (cx + 40)) > 26], fill=(*INK, 255))
        else:
            d.polygon(top + bot, fill=(*INK, 255))
        for j in range(16):  # fine hairs inside the brow so it reads as hair, not a block
            t = 0.08 + j / 15 * 0.84
            x, y = top[int(t * 29)]
            d.line([(x, y + 14), (x + s * 34, y + 14 + thick * 0.4)], fill=(90, 66, 56, 140), width=5)
        # the eye: almond, tilted, the lid crease above
        cy = 930
        inner_c, outer_c = (cx - s * ew, cy + 6), (cx + s * ew, cy - 4 - etilt)
        upper = bez(inner_c, (cx - s * 90, cy - eh - 10 + lid * 0.4), (cx + s * 80, cy - eh - 18 + lid), outer_c, 30)
        lower = bez(outer_c, (cx + s * 90, cy + eh - 10), (cx - s * 80, cy + eh), inner_c, 30)
        d.polygon(upper + lower, fill=(22, 22, 28, 255) if turned else (240, 236, 228, 255))
        mask = Image.new("L", (S, S), 0)
        ImageDraw.Draw(mask).polygon(upper + lower, fill=255)
        eye = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ed = ImageDraw.Draw(eye)
        ix, iy, r = cx - s * 12, cy + 4, 72
        if turned:
            glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
            ImageDraw.Draw(glow).ellipse([ix - r * 1.6, iy - r * 1.6, ix + r * 1.6, iy + r * 1.6], fill=(255, 110, 50, 230))
            im.alpha_composite(glow.filter(ImageFilter.GaussianBlur(40)))
            ed.ellipse([ix - r, iy - r, ix + r, iy + r], fill=(255, 120, 55, 255))
            ed.ellipse([ix - r * 0.62, iy - r * 0.62, ix + r * 0.62, iy + r * 0.62], fill=(255, 200, 140, 255))
            ed.ellipse([ix - r * 0.28, iy - r * 0.28, ix + r * 0.28, iy + r * 0.28], fill=(255, 250, 235, 255))
        else:
            iris = f["iris"]
            dark = tuple(int(c * 0.55) for c in iris)
            light = tuple(min(255, int(c * 1.35)) for c in iris)
            ed.ellipse([ix - r, iy - r, ix + r, iy + r], fill=(*dark, 255))
            ed.ellipse([ix - r * 0.86, iy - r * 0.86, ix + r * 0.86, iy + r * 0.86], fill=(*iris, 255))
            for j in range(28):  # iris fibres
                a = j / 28 * 2 * math.pi
                ed.line([(ix + math.cos(a) * r * 0.42, iy + math.sin(a) * r * 0.42),
                         (ix + math.cos(a) * r * 0.82, iy + math.sin(a) * r * 0.82)], fill=(*light, 200), width=5)
            ed.ellipse([ix - r * 0.4, iy - r * 0.4, ix + r * 0.4, iy + r * 0.4], fill=(12, 12, 16, 255))
            ed.ellipse([ix + r * 0.12, iy - r * 0.5, ix + r * 0.42, iy - r * 0.2], fill=(255, 255, 255, 255))
        clipped = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        clipped.paste(eye, (0, 0), Image.composite(eye.getchannel("A"), Image.new("L", (S, S), 0), mask))
        im.alpha_composite(clipped)
        # the upper lid's shadow on the eye, the lash line and its outer flick, the crease, the lower lid
        im.alpha_composite(soft([("polygon", upper + [(outer_c[0], cy - 30), (inner_c[0], cy - 26)], (0, 0, 0, 90))], 14))
        d = ImageDraw.Draw(im)
        d.line(upper, fill=(*INK, 255), width=20, joint="curve")
        d.line([outer_c, (outer_c[0] + s * lash, outer_c[1] - lash * 0.55)], fill=(*INK, 255), width=14)
        crease = bez((cx - s * 130, cy - 98 + lid), (cx - s * 40, cy - 140 + lid), (cx + s * 80, cy - 140 + lid),
                     (cx + s * 160, cy - 90 + lid * 0.6), 20)
        d.line(crease, fill=(*SHADE, 170), width=8, joint="curve")
        d.line(lower[4:-6], fill=(*SHADE, 160), width=7, joint="curve")
        if f["scar"] and s < 0:
            # a healed scar from the brow, over the lid, onto the cheek
            d.line([(cx + 10, 600), (cx + 40, 780), (cx + 70, 1060), (cx + 90, 1180)], fill=(150, 80, 70, 170), width=16)
        if turned and s > 0:
            # an android seam down the cheek, the only machine sign before it breaks
            d.line([(cx + 60, cy + 150), (cx + 110, cy + 420), (cx + 70, cy + 640)], fill=(30, 30, 36, 200), width=6)
            for t in (0.3, 0.6):
                x = cx + 60 + 50 * t * 2
                d.line([(x, cy + 150 + 270 * t * 2), (x + 26, cy + 150 + 270 * t * 2)], fill=(30, 30, 36, 200), width=5)
    if f["freckles"]:
        import random
        rnd = random.Random(11)
        for s in (-1, 1):
            for _ in range(26):
                x = S // 2 + s * rnd.uniform(180, 480)
                y = rnd.uniform(1100, 1260)
                d.ellipse([x, y, x + 14, y + 12], fill=(*SHADE, 110))
    # nose: the bridge line on one side, the tip and nostrils
    d.line(bez((1080, 900), (1100, 1050), (1110, 1180), (1120, 1260), 16), fill=(*SHADE, 150), width=9, joint="curve")
    d.line(bez((930, 1290), (960, 1335), (1000, 1340), (1024, 1330), 12), fill=(*SHADE, 200), width=10, joint="curve")
    d.line(bez((1024, 1330), (1050, 1340), (1090, 1335), (1120, 1290), 12), fill=(*SHADE, 200), width=10, joint="curve")
    d.ellipse([950, 1295, 990, 1318], fill=(*SHADE, 170))
    d.ellipse([1058, 1295, 1098, 1318], fill=(*SHADE, 170))
    # mouth: the parting line (curve + smile, lift raises the right corner), the upper lip's bow, the lower lip
    mw, curve, lift, lip = f["mouth"]
    x0, x1 = 1024 - mw / 2, 1024 + mw / 2
    y0, y1 = 1555, 1545 - lift
    mouth = bez((x0, y0 - curve * 0.4), (x0 + mw * 0.28, y0 + curve), (x1 - mw * 0.28, y0 + curve), (x1, y1 - curve * 0.4), 30)
    d.line(mouth, fill=(*INK, 255), width=16, joint="curve")
    if lift > 0:
        d.line([(x1, y1 - curve * 0.4), (x1 + 30, y1 - curve * 0.4 - 26)], fill=(*INK, 255), width=10)
    bow = bez((x0 + 70, 1540), (960, 1500), (990, 1510), (1024, 1525), 14) + \
        bez((1024, 1525), (1060, 1505), (1100, 1495), (x1 - 70, 1530 - lift * 0.3), 14)
    d.line(bow, fill=(*SHADE, 120), width=8, joint="curve")
    d.line(bez((x0 + 100, 1640), (980, 1640 + 25 * lip), (1080, 1640 + 25 * lip), (x1 - 100, 1630), 16),
           fill=(*SHADE, int(150 * min(1, lip))), width=9, joint="curve")
    # philtrum, chin line
    d.line([(1000, 1370), (995, 1490)], fill=(*SHADE, 70), width=6)
    d.line([(1048, 1370), (1053, 1490)], fill=(*SHADE, 70), width=6)
    d.line(bez((930, 1880), (990, 1910), (1060, 1910), (1120, 1880), 12), fill=(*SHADE, 120), width=8, joint="curve")
    if cracked:
        im = crack(im)
    return im.resize((1024, 1024), Image.LANCZOS)


if __name__ == "__main__":
    tiles = []
    for name, f in FACES.items():
        for version in ("", "_Turned", "_Cracked"):
            im = face(f, version == "_Turned", version == "_Cracked")
            path = os.path.join(OUT, "Face_%s%s.png" % (name, version))
            im.save(path)
            tiles.append((name, version, im))
    # preview: each face (human on a light and a dark skin, turned, cracked)
    T = 300
    sheet = Image.new("RGBA", (T * len(FACES), T * 4), (40, 42, 48, 255))
    for i, (name, f) in enumerate(FACES.items()):
        human = [t[2] for t in tiles if t[0] == name and t[1] == ""][0]
        turned = [t[2] for t in tiles if t[0] == name and t[1] == "_Turned"][0]
        cracked = [t[2] for t in tiles if t[0] == name and t[1] == "_Cracked"][0]
        rows = (((240, 190, 150), human), ((141, 95, 64), human), ((224, 172, 130), turned), ((240, 190, 150), cracked))
        for row, (skin, im) in enumerate(rows):
            tile = Image.new("RGBA", (1024, 1024), (*skin, 255))
            tile.alpha_composite(im)
            sheet.paste(tile.resize((T - 8, T - 8), Image.LANCZOS), (i * T + 4, row * T + 4))
    prev = os.path.join(ROOT, "preview", "faces.png")
    sheet.convert("RGB").save(prev)
    print("wrote", len(tiles), "faces and", prev)
