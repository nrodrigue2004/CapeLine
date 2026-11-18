# art/clothes/masks.py: the hero creator's flat masks as head decals (overnight queue item 12, 2026-11-18), in
# place of the boxes LookKit welds over the face. A mask is drawn on the same 1:1 square as our faces
# (art/clothes/faces.py: eyes at 30% and 70% across, 45% down; the mouth near 80% down) so its eye holes sit on
# the face's own eyes, which show through. Each mask has a front decal, and some a side decal (the head's left,
# right and back faces) and a top one (a full wrap). Decals multiply by their Color3: light greys take the mask
# slot's colour role (Config.Creator.maskArt tint), dark ink stays dark; a mask drawn in its own colours (the
# domino's black, the ninja's charcoal, the skull's bone) is tinted white. All original: no real hero's mask.
# Output: art/export/clothes/masks/MaskFront_<kit>.png, MaskSide_<kit>.png, MaskTop_<kit>.png (256 px) and
# art/preview/masks.png (via art/blender/clothed.py masks). Run: python3 art/clothes/masks.py   (PIL only)
import json
import math
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "export", "clothes", "masks")
os.makedirs(OUT, exist_ok=True)

S = 1024
PX = 256
INK = (22, 22, 30, 255)
FULL = (255, 255, 255, 255)
SHADE = (205, 205, 210, 255)
CLEAR = (0, 0, 0, 0)
EYES = ((312, 465), (712, 465))  # the face decal's eye centres, at 1024


def canvas():
    im = Image.new("RGBA", (S, S), CLEAR)
    return im, ImageDraw.Draw(im)


def bez(p0, p1, p2, p3, n=24):
    out = []
    for i in range(n + 1):
        t = i / n
        a, b, c, d = (1 - t) ** 3, 3 * t * (1 - t) ** 2, 3 * t * t * (1 - t), t ** 3
        out.append((a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0], a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1]))
    return out


def shape_mask(pts):
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).polygon(pts, fill=255)
    return m


def ink_around(im, m, width=22):
    """A dark ink line round the mask's edge (grown from its own shape), drawn under it."""
    grown = m.filter(ImageFilter.GaussianBlur(width / 4)).point(lambda v: 255 if v >= 14 else 0)
    out = Image.new("RGBA", (S, S), CLEAR)
    out.paste(INK, (0, 0), grown)
    out.alpha_composite(im)
    return out


def fill(m, color, shade=True):
    """A mask shape filled with `color` and a cel shadow band along its lower edge."""
    from PIL import ImageChops
    im = Image.new("RGBA", (S, S), CLEAR)
    im.paste(color, (0, 0), m)
    if shade:
        up = m.transform((S, S), Image.AFFINE, (1, 0, 0, 0, 1, 34))  # the shape moved up 34 px
        band = ImageChops.subtract(m, up)
        dark = tuple(int(c * 0.8) for c in color[:3]) + (255,)
        im.paste(dark, (0, 0), band)
    return im


def eye_hole(d, cx, cy, w, h, tilt=0):
    """An almond hole round one eye (cleared): the face's own eye shows through."""
    s = 1 if cx > S / 2 else -1
    inner, outer = (cx - s * w, cy + 4), (cx + s * w, cy - 6 - tilt)
    top = bez(inner, (cx - s * w * 0.45, cy - h - 6), (cx + s * w * 0.5, cy - h - 12), outer)
    bot = bez(outer, (cx + s * w * 0.5, cy + h - 4), (cx - s * w * 0.45, cy + h + 2), inner)
    return top + bot


def cut_eyes(m, w=112, h=64, tilt=14):
    d = ImageDraw.Draw(m)
    for cx, cy in EYES:
        d.polygon(eye_hole(d, cx, cy, w, h, tilt), fill=0)
    return m


def save(im, name):
    im.resize((PX, PX), Image.LANCZOS).save(os.path.join(OUT, name + ".png"))


# ---------------------------------------------------------------- the masks
def domino():
    # the classic hero's eye mask in glossy black (tinted white), its tips swept up, a cool glint on top
    pts = bez((70, 470), (120, 300), (380, 330), (512, 400)) + bez((512, 400), (644, 330), (904, 300), (954, 470))
    pts += bez((954, 470), (900, 620), (700, 640), (560, 560)) + [(512, 600)] + bez((464, 560), (324, 640), (124, 620), (70, 470))
    m = cut_eyes(shape_mask(pts))
    im = fill(m, (34, 36, 46, 255))
    d = ImageDraw.Draw(im)
    for sgn in (-1, 1):
        cx = 512 + sgn * 300
        d.line(bez((cx - sgn * 150, 380), (cx - sgn * 60, 350), (cx + sgn * 60, 352), (cx + sgn * 150, 384), 16),
               fill=(150, 170, 210, 255), width=12)
    im.putalpha(Image.composite(im.getchannel("A"), Image.new("L", (S, S), 0), m))
    return {"front": ink_around(im, m)}


def half():
    # a lower-face guard plate from the nose to the chin (the slot's main colour), with breathing slots
    pts = bez((60, 600), (200, 560), (380, 560), (512, 590)) + bez((512, 590), (644, 560), (824, 560), (964, 600))
    pts += [(964, 860)] + bez((964, 860), (850, 1010), (650, 1024), (512, 1024)) + bez((512, 1024), (374, 1024), (174, 1010), (60, 860))
    m = shape_mask(pts)
    im = fill(m, FULL)
    d = ImageDraw.Draw(im)
    d.line([(512, 600), (512, 1010)], fill=INK, width=10)
    for k in range(3):
        for sgn in (-1, 1):
            x = 512 + sgn * (110 + k * 60)
            d.rounded_rectangle([x - 16, 760, x + 16, 900], 12, fill=INK)
    for sgn in (-1, 1):
        d.ellipse([512 + sgn * 380 - 26, 680, 512 + sgn * 380 + 26, 732], fill=SHADE, outline=INK, width=8)
    front = ink_around(im, m)
    # a side decal is used on the left and the right face, so it is drawn symmetric (front and back alike)
    sm = shape_mask([(0, 620), (1024, 620), (1024, 860), (0, 860)])
    side = ink_around(fill(sm, FULL), sm)
    return {"front": front, "side": side}


def bandana():
    # a cloth tied over the nose and mouth: a pointed front with folds, the knot and tails at the back
    pts = [(40, 560), (984, 560), (984, 760)] + bez((984, 760), (800, 880), (640, 960), (512, 1010)) + bez(
        (512, 1010), (384, 960), (224, 880), (40, 760))
    m = shape_mask(pts)
    im = fill(m, FULL)
    d = ImageDraw.Draw(im)
    for k, (a, b) in enumerate((((300, 620), (440, 880)), ((724, 620), (584, 880)), ((512, 640), (512, 930)))):
        d.line([a, b], fill=SHADE, width=16)
        d.line([a, b], fill=(22, 22, 30, 140), width=4)
    for x in range(110, 960, 90):  # a simple dot print
        for y in range(610, 760, 80):
            d.ellipse([x - 12, y - 12, x + 12, y + 12], fill=SHADE)
    im.putalpha(Image.composite(im.getchannel("A"), Image.new("L", (S, S), 0), m))
    front = ink_around(im, m)
    sm = shape_mask([(0, 560), (1024, 560), (1024, 790), (0, 790)])
    side = fill(sm, FULL)
    sd = ImageDraw.Draw(side)
    for x in range(60, 1000, 90):
        for y in range(610, 760, 80):
            sd.ellipse([x - 12, y - 12, x + 12, y + 12], fill=SHADE)
    side = ink_around(side, sm)
    back = side.copy()  # the back: the knot and its two tails
    bd = ImageDraw.Draw(back)
    kn = [(430, 600), (594, 600), (620, 760), (404, 760)]
    bd.polygon(kn, fill=FULL, outline=INK, width=12)
    bd.polygon([(470, 740), (540, 740), (470, 1010), (380, 980)], fill=SHADE, outline=INK, width=12)
    bd.polygon([(520, 740), (580, 740), (680, 990), (600, 1012)], fill=SHADE, outline=INK, width=12)
    return {"front": front, "side": side, "back": back}


def cowl():
    # a cloth hood over the head and round the eyes (no ears: it is not a bat), a sharp brow ridge and a peak
    # at the nose bridge; the lower face stays bare. Sides and back cover to the jaw; the top is all cowl.
    pts = [(0, 0), (1024, 0), (1024, 700)] + bez((1024, 700), (900, 660), (780, 610), (640, 590)) + [(512, 690)]
    pts += bez((384, 590), (244, 610), (124, 660), (0, 700))
    m = cut_eyes(shape_mask(pts), 118, 70, 18)
    im = fill(m, FULL)
    d = ImageDraw.Draw(im)
    for sgn in (-1, 1):  # the brow ridges
        cx = 512 + sgn * 200
        d.line(bez((512, 380), (cx - sgn * 40, 320), (cx + sgn * 120, 300), (512 + sgn * 470, 330), 18), fill=SHADE, width=26)
        d.line(bez((512, 400), (cx - sgn * 40, 340), (cx + sgn * 120, 320), (512 + sgn * 470, 350), 18), fill=INK, width=8)
    d.line([(512, 80), (512, 360)], fill=(22, 22, 30, 120), width=8)  # the centre seam
    im.putalpha(Image.composite(im.getchannel("A"), Image.new("L", (S, S), 0), m))
    front = ink_around(im, m)
    sm = shape_mask([(0, 0), (1024, 0), (1024, 760), (0, 760)])
    side = fill(sm, FULL)
    ImageDraw.Draw(side).line([(0, 300), (1024, 300)], fill=(22, 22, 30, 110), width=8)
    side = ink_around(side, sm)
    bm = shape_mask([(0, 0), (1024, 0), (1024, 900), (0, 900)])
    back = ink_around(fill(bm, FULL), bm)
    ImageDraw.Draw(back).line([(512, 0), (512, 880)], fill=(22, 22, 30, 120), width=8)
    top = Image.new("RGBA", (S, S), FULL)
    ImageDraw.Draw(top).line([(512, 0), (512, 1024)], fill=(22, 22, 30, 120), width=8)
    return {"front": front, "side": side, "back": back, "top": top}


def eyepatch():
    # a black leather patch over the right eye (the viewer's left), stitched, on a strap round the head
    im, d = canvas()
    d.line([(0, 330), (1024, 520)], fill=(40, 34, 32, 255), width=40)
    d.line([(0, 330), (1024, 520)], fill=INK, width=4)
    cx, cy = EYES[0]
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).ellipse([cx - 150, cy - 120, cx + 150, cy + 130], fill=255)
    patch = fill(m, (46, 40, 38, 255))
    pd = ImageDraw.Draw(patch)
    for a in range(0, 360, 20):
        x, y = cx + 118 * math.cos(math.radians(a)), cy + 98 * math.sin(math.radians(a))
        pd.ellipse([x - 7, y - 7, x + 7, y + 7], fill=(120, 110, 100, 255))
    pd.arc([cx - 100, cy - 80, cx + 60, cy + 40], 200, 280, fill=(110, 104, 100, 255), width=12)
    im.alpha_composite(ink_around(patch, m))
    side, sd = canvas()
    sd.line([(0, 420), (1024, 420)], fill=(40, 34, 32, 255), width=40)
    sd.line([(0, 400), (1024, 400)], fill=INK, width=4)
    sd.line([(0, 440), (1024, 440)], fill=INK, width=4)
    return {"front": im, "side": side}


def masquerade():
    # a gala eye mask in the slot's main colour: swept wings with scroll curls and a jewel at the brow
    pts = bez((40, 300), (140, 330), (330, 360), (512, 410)) + bez((512, 410), (694, 360), (884, 330), (984, 300))
    pts += bez((984, 300), (960, 520), (820, 640), (600, 590)) + [(512, 640)] + bez((424, 590), (204, 640), (64, 520), (40, 300))
    m = cut_eyes(shape_mask(pts), 104, 60, 20)
    im = fill(m, FULL)
    d = ImageDraw.Draw(im)
    for sgn in (-1, 1):
        cx = 512 + sgn * 330
        d.arc([cx - 150, 500, cx + 150, 640], 200 if sgn < 0 else 270, 340 if sgn < 0 else 340 + 70, fill=INK, width=8)
        for k in range(3):
            x = 512 + sgn * (420 - k * 60)
            d.ellipse([x - 14, 340 + k * 10, x + 14, 368 + k * 10], fill=SHADE, outline=INK, width=4)
    im.putalpha(Image.composite(im.getchannel("A"), Image.new("L", (S, S), 0), m))
    out = ink_around(im, m)
    od = ImageDraw.Draw(out)
    for sgn in (-1, 1):  # the swirl plumes rising off the outer corners
        x0 = 512 + sgn * 470
        pts2 = bez((x0, 320), (x0 + sgn * 20, 220), (x0 - sgn * 80, 140), (x0 - sgn * 10, 40), 20)
        od.line(pts2, fill=INK, width=44)
        od.line(pts2, fill=FULL, width=26)
    od.polygon([(512, 360), (548, 410), (512, 460), (476, 410)], fill=SHADE, outline=INK, width=8)
    return {"front": out}


def ninja():
    # a charcoal head wrap with an eye slit (tinted white): fabric folds, the knot and tails at the back
    C = (52, 54, 62, 255)
    L = (82, 84, 96, 255)
    im = Image.new("RGBA", (S, S), C)
    d = ImageDraw.Draw(im)
    d.rectangle([0, 360, 1024, 600], fill=CLEAR)  # the eye slit
    d.line([(0, 356), (1024, 356)], fill=INK, width=14)
    d.line([(0, 604), (1024, 604)], fill=INK, width=14)
    for y in (200, 260, 700, 780, 860):
        d.line([(60, y), (964, y + 20)], fill=L, width=10)
    side = Image.new("RGBA", (S, S), C)
    sd = ImageDraw.Draw(side)
    for y in (200, 260, 460, 700, 780, 860):
        sd.line([(0, y), (1024, y)], fill=L, width=10)
    back = side.copy()
    bd = ImageDraw.Draw(back)
    bd.rounded_rectangle([420, 380, 604, 540], 30, fill=L, outline=INK, width=12)
    bd.polygon([(470, 520), (540, 520), (450, 1000), (360, 970)], fill=L, outline=INK, width=12)
    bd.polygon([(500, 520), (570, 520), (690, 980), (600, 1010)], fill=L, outline=INK, width=12)
    top = Image.new("RGBA", (S, S), C)
    ImageDraw.Draw(top).ellipse([300, 300, 724, 724], outline=L, width=10)
    return {"front": im, "side": side, "back": back, "top": top}


def skull():
    # a bone-white cartoon skull face (tinted white): round dark sockets round the eyes, a heart-shaped nose and
    # a stitched grin. Spooky-fun, never gory.
    BONE = (240, 234, 216, 255)
    pts = bez((80, 300), (80, 60), (944, 60), (944, 300)) + bez((944, 300), (960, 620), (860, 760), (760, 820))
    pts += [(760, 1000), (264, 1000), (264, 820)] + bez((264, 820), (164, 760), (64, 620), (80, 300))
    m = shape_mask(pts)
    im = fill(m, BONE)
    d = ImageDraw.Draw(im)
    for cx, cy in EYES:
        d.ellipse([cx - 170, cy - 140, cx + 170, cy + 140], fill=(40, 36, 44, 255))
    d.polygon([(512, 600), (560, 690), (512, 730), (464, 690)], fill=(40, 36, 44, 255))
    d.line([(300, 860), (724, 860)], fill=INK, width=14)
    for x in range(330, 720, 56):
        d.line([(x, 820), (x, 900)], fill=INK, width=10)
    im.putalpha(Image.composite(im.getchannel("A"), Image.new("L", (S, S), 0), m))
    out = ink_around(im, m)
    od = ImageDraw.Draw(out)
    for cx, cy in EYES:  # the face's own eyes show in the sockets
        od.polygon(eye_hole(od, cx, cy, 112, 64, 10), fill=CLEAR)
    return {"front": out}


# kit -> (drawing, tint role)
MASKS = {"domino": (domino, "white"), "half": (half, "p"), "bandana": (bandana, "s"), "cowl": (cowl, "p"),
         "eyepatch": (eyepatch, "white"), "masquerade": (masquerade, "p"), "ninja": (ninja, "white"),
         "skull": (skull, "white")}

if __name__ == "__main__" and "--stack" in __import__("sys").argv:
    pv = os.path.join(ROOT, "preview")
    a, b = Image.open(os.path.join(pv, "masks_front.png")), Image.open(os.path.join(pv, "masks_back.png"))
    both = Image.new("RGB", (a.width, a.height + b.height))
    both.paste(a, (0, 0))
    both.paste(b, (0, a.height))
    both.save(os.path.join(pv, "masks.png"))
    os.remove(os.path.join(pv, "masks_front.png"))
    os.remove(os.path.join(pv, "masks_back.png"))
elif __name__ == "__main__":
    rows = []
    for kit, (fn, tint) in MASKS.items():
        faces = fn()
        save(faces["front"], "MaskFront_" + kit)
        if "side" in faces:
            save(faces["side"], "MaskSide_" + kit)
        if "back" in faces:
            save(faces["back"], "MaskBack_" + kit)
        if "top" in faces:
            save(faces["top"], "MaskTop_" + kit)
        rows.append({"kit": kit, "tint": tint, "faces": sorted(faces)})
    with open(os.path.join(OUT, "preview.json"), "w") as f:
        json.dump(rows, f, indent=1)
    print("wrote", len(MASKS), "masks")
