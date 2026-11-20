# post.py: the news and name card art (gap-news, 2026-11-19). Draws, with PIL, the HUD pieces of the lore step 7
# cinematic layer that were plain frames, and inks the boss portraits rendered by art/blender/boss_cards.py:
# * NewsCards.png (1024 x 1024, 512 px cells, 2 to a row): each world boss's name card portrait: the boss (the game's
#   own meshes posed, build/news/raw/boss_<Boss>.png) in a bold ink outline over a sunburst and halftone dots in its
#   card colour (Config.BossArt theme), in an ink frame with a white rule (the comic pass of
#   art/panels/post.py, whose backdrop and outline it reuses)
# * NamePlate.png (1024 x 288): the name card's comic plate: navy with speed lines, an ink border, a gold rule and a
#   clipped corner; the UI shows it 9-sliced (Config.NewsArt.plate.slice, SliceScale by the card's height) so it fits
#   any card size
# * TvCase.png (800 x 520): the corner TV: a cartoon set with a cream bezel round a clear screen window
#   (Config.NewsArt.tv.screen), a speaker grille, two knobs, rabbit-ear antennas and stubby legs
# * NewsIdent.png (256 x 256): the news channel's mark: a lighthouse in a gold ring with light beams over waves
# No words in any image: the channel's name, BREAKING NEWS, the headlines and the names stay UI text. No person is
# drawn (bosses are machines and creatures). Then writes src/config/NewsArt.luau (ids from art/export/news/ids.json,
# which art/news/upload.py fills; 0 = not uploaded, the UI keeps today's frames) and art/preview/news_art.png.
# Run: python3 art/news/post.py   (PIL and numpy; render the bosses first for new portraits, else the sheet's cells
# are kept)
import importlib.util
import json
import math
import os

from PIL import Image, ImageDraw, ImageFilter

ART = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.path.dirname(ART)
RAW = os.path.join(REPO, "build", "news", "raw")
OUT = os.path.join(ART, "export", "news")
PREVIEW = os.path.join(ART, "preview")
IDS_PATH = os.path.join(OUT, "ids.json")

_spec = importlib.util.spec_from_file_location("panels_post", os.path.join(ART, "panels", "post.py"))
panels = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(panels)
INK = panels.INK

CELL = 512
# the card portraits, in sheet order, with their backdrop colour (Config.BossArt theme; tests/news_art_test.luau
# checks these against BossArt)
BOSSES = [
    ("RustjawPrime", (255, 170, 60)),
    ("LumenMaw", (90, 240, 230)),
    ("LeviathanEngine", (80, 230, 255)),
    ("NullWarFrame", (255, 236, 80)),  # Bulwark's electric yellow (2026-11-20)
    # bosses-3 (2026-11-20, DRAFT looks): a second sheet, NewsCards2.png (a sheet holds 4 cells: Roblox's 1024 px cap)
    ("StormColossus", (150, 230, 255)),
    ("SwarmQueen", (255, 170, 60)),
    ("QuarryTitan", (255, 130, 40)),
]
SHEETS = ("NewsCards.png", "NewsCards2.png")
PLATE = (1024, 288)
PLATE_SLICE = (48, 44, 72, 44)  # left, top, right, bottom margins kept unstretched
TV = (800, 520)
TV_SCREEN = (70, 146, 600, 434)  # the clear window: x0, y0, x1, y1
IDENT = 256
NAVY = (22, 30, 70)
GOLD = (244, 192, 58)
RED = (214, 40, 52)
CREAM = (250, 236, 206)


def ss(size, k=2):
    return (size[0] * k, size[1] * k)


# ------------------------------------------------------------------ the boss portraits
def portrait(bid, rgb):
    raw = os.path.join(RAW, "boss_%s.png" % bid)
    if not os.path.isfile(raw):
        return None
    fig = Image.open(raw).convert("RGBA")
    box = fig.split()[3].point(lambda v: 255 if v > 20 else 0).getbbox()
    fig = fig.crop(box)
    n = 1024
    # fit the figure: as big as fits with room for the ink, its foot (or cut) on the frame's bottom
    k = min((n * 0.9) / fig.width, (n * 0.92) / fig.height)
    fig = fig.resize((max(1, int(fig.width * k)), max(1, int(fig.height * k))), Image.LANCZOS)
    layer = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    layer.alpha_composite(fig, ((n - fig.width) // 2, n - fig.height - int(n * 0.03)))
    dark = tuple(int(c * 0.55) for c in rgb)
    card = panels.backdrop(n, dark).convert("RGBA")
    card.alpha_composite(panels.outlined(layer, 9))
    d = ImageDraw.Draw(card)
    d.rectangle([0, 0, n - 1, n - 1], outline=INK, width=30)
    d.rectangle([30, 30, n - 31, n - 31], outline=(255, 255, 255), width=10)
    d.rectangle([40, 40, n - 41, n - 41], outline=rgb, width=8)
    return card.convert("RGB").resize((CELL, CELL), Image.LANCZOS)


def cards_sheet():
    at, kept = {}, 0
    for s, name in enumerate(SHEETS):
        path = os.path.join(OUT, name)
        old = Image.open(path).convert("RGB") if os.path.isfile(path) else None
        sheet = Image.new("RGB", (CELL * 2, CELL * 2), INK)
        for i, (bid, rgb) in enumerate(BOSSES[s * 4:s * 4 + 4]):
            c, r = i % 2, i // 2
            img = portrait(bid, rgb)
            if img is None:
                if old is None:
                    raise SystemExit("post.py: no render and no old sheet for " + bid)
                img = old.crop((c * CELL, r * CELL, (c + 1) * CELL, (r + 1) * CELL))
                kept += 1
            sheet.paste(img, (c * CELL, r * CELL))
            at[bid] = (c, r, s + 1)
        sheet.save(path)
    return at, kept


# ------------------------------------------------------------------ the name card's plate
def plate():
    k = 2
    w, h = ss(PLATE, k)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    cut = (PLATE_SLICE[2] - 6) * k, (PLATE_SLICE[3] - 2) * k  # a clipped corner, inside the kept margins
    poly = [(0, 0), (w - 1, 0), (w - 1, h - 1 - cut[1]), (w - 1 - cut[0], h - 1), (0, h - 1)]
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).polygon(poly, fill=255)
    # the face: a top-to-bottom gradient and horizontal speed lines (both stretch cleanly in the 9-slice's middle)
    face = Image.new("RGB", (w, h), NAVY)
    d = ImageDraw.Draw(face)
    for y in range(h):
        t = y / h
        c = tuple(int(NAVY[i] * (1.25 - 0.45 * t)) for i in range(3))
        d.line([(0, y), (w, y)], fill=c)
    for y, th, a in ((0.2, 5, 0.5), (0.32, 3, 0.35), (0.74, 4, 0.4), (0.84, 3, 0.3), (0.9, 6, 0.25)):
        yy = int(h * y)
        c = tuple(int(NAVY[i] + (255 - NAVY[i]) * a * 0.35) for i in range(3))
        d.rectangle([0, yy, w, yy + th * k], fill=c)
    img.paste(face, (0, 0), mask)
    d = ImageDraw.Draw(img)
    # a gold rule inside the ink, round the clipped corner too
    ins = 20 * k
    d.line([(ins, ins), (w - 1 - ins, ins), (w - 1 - ins, h - 1 - cut[1] + ins // 3),
            (w - 1 - cut[0] + ins // 3, h - 1 - ins), (ins, h - 1 - ins), (ins, ins)], fill=GOLD, width=5 * k,
           joint="curve")
    d.line(poly + [poly[0]], fill=INK, width=12 * k, joint="curve")
    # a red tab on the left end (the boss colour shows on the UI's slash bar, not here)
    d.rectangle([ins + 8 * k, ins + 8 * k, ins + 20 * k, h - 1 - ins - 8 * k], fill=RED)
    alpha = img.split()[3]
    img.putalpha(Image.composite(alpha, Image.new("L", (w, h), 0), mask.filter(ImageFilter.MaxFilter(3))))
    return img.resize(PLATE, Image.LANCZOS)


# ------------------------------------------------------------------ the corner TV's case
def tv_case():
    k = 2
    w, h = ss(TV, k)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    o = 7 * k  # ink width
    # rabbit-ear antennas from a little dome on top
    base = (int(w * 0.42), int(118 * k))
    for tip in ((int(w * 0.26), 14 * k), (int(w * 0.6), 22 * k)):
        d.line([base, tip], fill=INK, width=12 * k)
        d.line([base, tip], fill=(196, 202, 214), width=5 * k)
        r = 14 * k
        d.ellipse([tip[0] - r, tip[1] - r, tip[0] + r, tip[1] + r], fill=GOLD, outline=INK, width=o - 2 * k)
    d.pieslice([base[0] - 50 * k, base[1] - 34 * k, base[0] + 50 * k, base[1] + 34 * k], 180, 360, fill=(36, 40, 56),
               outline=INK, width=o)
    # stubby legs
    for x in (int(w * 0.16), int(w * 0.84)):
        d.polygon([(x - 34 * k, 456 * k), (x + 34 * k, 456 * k), (x + 22 * k, 508 * k), (x - 22 * k, 508 * k)],
                  fill=(36, 40, 56), outline=INK, width=o)
    # the body: cherry red with a lighter top and halftone shade at the bottom
    body = [24 * k, 106 * k, w - 24 * k, 470 * k]
    d.rounded_rectangle(body, radius=56 * k, fill=RED, outline=INK, width=o)
    hl = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    hd = ImageDraw.Draw(hl)
    hd.rounded_rectangle([body[0] + 22 * k, body[1] + 14 * k, body[2] - 40 * k, body[1] + 46 * k], radius=16 * k,
                         fill=(255, 140, 140, 120))
    step = 14 * k
    for y in range(body[1] + 250 * k, body[3] - 10 * k, step):
        for x in range(body[0] + 20 * k, body[2] - 20 * k, step):
            ox = step // 2 if (y // step) % 2 else 0
            rr = step * 0.42 * (y - body[1] - 250 * k) / (110 * k)
            hd.ellipse([x + ox - rr, y - rr, x + ox + rr, y + rr], fill=(120, 12, 24, 140))
    img.alpha_composite(hl)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle(body, radius=56 * k, outline=INK, width=o)
    # the cream bezel round the screen window
    x0, y0, x1, y1 = (v * k for v in TV_SCREEN)
    m = 18 * k
    d.rounded_rectangle([x0 - m, y0 - m, x1 + m, y1 + m], radius=40 * k, fill=CREAM, outline=INK, width=o)
    d.rounded_rectangle([x0 - m + 8 * k, y0 - m + 8 * k, x1 + m - 8 * k, y0 - m + 18 * k], radius=6 * k,
                        fill=(255, 250, 238))
    # the right panel: a grille and two knobs
    px0, px1 = x1 + m + 20 * k, body[2] - 26 * k
    d.rounded_rectangle([px0, y0, px1, y0 + 150 * k], radius=16 * k, fill=(60, 16, 24), outline=INK, width=o - 2 * k)
    for yy in range(y0 + 22 * k, y0 + 140 * k, 20 * k):
        d.line([(px0 + 16 * k, yy), (px1 - 16 * k, yy)], fill=(30, 8, 12), width=8 * k)
    for j, ky in enumerate((y0 + 200 * k, y0 + 262 * k)):
        cx, r = (px0 + px1) // 2, 26 * k
        d.ellipse([cx - r, ky - r, cx + r, ky + r], fill=GOLD if j == 0 else CREAM, outline=INK, width=o - 2 * k)
        a = math.radians(-60 + 80 * j)
        d.line([(cx, ky), (cx + int(r * 0.8 * math.cos(a)), ky + int(r * 0.8 * math.sin(a)))], fill=INK, width=6 * k)
    # cut the window clear (the UI's screen shows through), with an ink lip and a glass sheen line
    win = Image.new("L", (w, h), 0)
    ImageDraw.Draw(win).rounded_rectangle([x0, y0, x1, y1], radius=26 * k, fill=255)
    img.putalpha(Image.composite(Image.new("L", (w, h), 0), img.split()[3], win))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([x0, y0, x1, y1], radius=26 * k, outline=INK, width=o)
    d.arc([x0 + 14 * k, y0 + 12 * k, x0 + 120 * k, y0 + 110 * k], 185, 265, fill=(255, 255, 255, 150), width=6 * k)
    return img.resize(TV, Image.LANCZOS)


# ------------------------------------------------------------------ the channel's mark
def ident():
    k = 4
    n = IDENT * k
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = n / 2
    R = n * 0.47
    d.ellipse([c - R, c - R, c + R, c + R], fill=GOLD, outline=INK, width=8 * k)
    r = R * 0.78
    inner = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    idr = ImageDraw.Draw(inner)
    idr.ellipse([c - r, c - r, c + r, c + r], fill=(70, 170, 235))
    # light beams from the lamp room
    ly = c - r * 0.42
    for s_ in (-1, 1):
        idr.polygon([(c, ly), (c + s_ * r * 1.2, ly - r * 0.42), (c + s_ * r * 1.2, ly + r * 0.18)],
                    fill=(255, 238, 150))
    # waves at the bottom
    for j, col in enumerate(((40, 110, 200), (28, 70, 150))):
        y = c + r * (0.42 + 0.2 * j)
        pts = [(c - r, n)]
        for i in range(41):
            x = c - r + 2 * r * i / 40
            pts.append((x, y + math.sin(i / 40 * math.pi * 5 + j) * r * 0.06))
        pts.append((c + r, n))
        idr.polygon(pts, fill=col)
    # the lighthouse: navy, a white band, the glowing lamp room and its cap
    tw0, tw1 = r * 0.2, r * 0.13
    top, bot = ly + r * 0.12, c + r * 0.55
    idr.polygon([(c - tw0, bot), (c + tw0, bot), (c + tw1, top), (c - tw1, top)], fill=NAVY, outline=INK)
    yb = top + (bot - top) * 0.42
    idr.polygon([(c - tw0 * 0.86 - tw1 * 0.14 - 4, yb), (c + tw0 * 0.86 + tw1 * 0.14 + 4, yb),
                 (c + tw0 * 0.78 + tw1 * 0.22, yb - (bot - top) * 0.16),
                 (c - tw0 * 0.78 - tw1 * 0.22, yb - (bot - top) * 0.16)], fill=(250, 250, 244))
    idr.rectangle([c - tw1 * 1.05, ly - r * 0.1, c + tw1 * 1.05, top], fill=(255, 226, 96), outline=INK, width=3 * k)
    idr.polygon([(c - tw1 * 1.4, ly - r * 0.1), (c + tw1 * 1.4, ly - r * 0.1), (c, ly - r * 0.32)], fill=RED,
                outline=INK)
    circle = Image.new("L", (n, n), 0)
    ImageDraw.Draw(circle).ellipse([c - r, c - r, c + r, c + r], fill=255)
    inner.putalpha(Image.composite(inner.split()[3], Image.new("L", (n, n), 0), circle))
    img.alpha_composite(inner)
    d = ImageDraw.Draw(img)
    d.ellipse([c - r, c - r, c + r, c + r], outline=INK, width=6 * k)
    return img.resize((IDENT, IDENT), Image.LANCZOS)


# ------------------------------------------------------------------ the config and the preview
def write_config(at, ids):
    def iid(f):
        return int(ids.get(f, 0))

    sx, sy, ex, ey = TV_SCREEN
    lines = [
        "-- GENERATED by art/news/post.py (gap-news, 2026-11-19): the news and name card art (Ui.NewsHud, Ui.CinemaHud;",
        "-- Shared.NewsArtKit). An id of 0 means not uploaded: the UI keeps today's frames. No words in the images: every",
        "-- name, title and headline stays UI text.",
        "return {",
        "\t-- each world boss's name card portrait: %d px cells, 4 to a sheet, { column, row (0-based), sheet }" % CELL,
        "\tcards = {",
        "\t\tsheet = %d," % iid("NewsCards.png"),
        "\t\tsheets = { %s }," % ", ".join(str(iid(n)) for n in SHEETS),
        "\t\tcell = %d," % CELL,
        "\t\tat = {",
    ]
    for bid, _ in BOSSES:
        lines.append("\t\t\t%s = { %d, %d, %d }," % (bid, at[bid][0], at[bid][1], at[bid][2]))
    lines += [
        "\t\t},",
        "\t},",
        "\t-- the name card's plate, shown 9-sliced: its size and the margins kept whole { left, top, right, bottom }",
        "\tplate = { id = %d, size = { %d, %d }, slice = { %d, %d, %d, %d } }," % (
            (iid("NamePlate.png"),) + PLATE + PLATE_SLICE),
        "\t-- the corner TV's case: its size and its clear screen window { x0, y0, x1, y1 } in its pixels",
        "\ttv = { id = %d, size = { %d, %d }, screen = { %d, %d, %d, %d } }," % (
            (iid("TvCase.png"),) + TV + (sx, sy, ex, ey)),
        "\t-- the news channel's mark (square)",
        "\tident = { id = %d, size = %d }," % (iid("NewsIdent.png"), IDENT),
        "}",
        "",
    ]
    open(os.path.join(REPO, "src", "config", "NewsArt.luau"), "w").write("\n".join(lines))


def preview(sheet, pl, tv, idn):
    W = 1600
    img = Image.new("RGB", (W, 1180), (60, 64, 74))
    img.paste(sheet.resize((560, 560), Image.LANCZOS), (20, 20))
    img.paste(Image.alpha_composite(Image.new("RGBA", tv.size, (16, 22, 44, 255)), tv).convert("RGB").resize(
        (600, 390), Image.LANCZOS), (620, 20))
    img.paste(idn, (1300, 40), idn)
    big = idn.resize((96, 96), Image.LANCZOS)
    img.paste(big, (1340, 330), big)
    small = idn.resize((32, 32), Image.LANCZOS)
    img.paste(small, (1460, 360), small)
    # the plate 9-sliced at the card's own size, PC and phone sizes (as the UI shows it)
    for y, (cw, ch) in ((620, (1024, 288)), (940, (520, 115)), (1080, (333, 60))):
        img.paste(nine(pl, (cw, ch)), (20, y), nine(pl, (cw, ch)))
    img.save(os.path.join(PREVIEW, "news_art.png"))


def nine(im, size):
    l, t, r, b = PLATE_SLICE
    w, h = im.size
    W, H = size
    k = H / h  # the UI's SliceScale: the card's height over the plate's
    L, T, Rr, B = int(l * k), int(t * k), int(r * k), int(b * k)
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    xs = [(0, l, 0, L), (l, w - r, L, W - Rr), (w - r, w, W - Rr, W)]
    ys = [(0, t, 0, T), (t, h - b, T, H - B), (h - b, h, H - B, H)]
    for (sx0, sx1, dx0, dx1) in xs:
        for (sy0, sy1, dy0, dy1) in ys:
            if dx1 > dx0 and dy1 > dy0:
                out.paste(im.crop((sx0, sy0, sx1, sy1)).resize((dx1 - dx0, dy1 - dy0), Image.LANCZOS), (dx0, dy0))
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    ids = json.load(open(IDS_PATH)) if os.path.isfile(IDS_PATH) else {}
    at, kept = cards_sheet()
    pl, tv, idn = plate(), tv_case(), ident()
    pl.save(os.path.join(OUT, "NamePlate.png"))
    tv.save(os.path.join(OUT, "TvCase.png"))
    idn.save(os.path.join(OUT, "NewsIdent.png"))
    preview(Image.open(os.path.join(OUT, "NewsCards.png")).convert("RGB"), pl, tv, idn)
    write_config(at, ids)
    print("post.py: %d portraits (%d kept), plate, TV case and ident; config and preview written" % (len(BOSSES), kept))


if __name__ == "__main__":
    main()
