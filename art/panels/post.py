# post.py: the comic art pass, step 3 (2026-11-19): inks and packs the renders of art/blender/panels.py.
# * portraits (build/panels/raw/portrait_<key>.png, the figure on a clear background): the speaker's own
#   backdrop colour (Config.Story.guides.speakers portrait bg) with sunburst rays and halftone dots, the figure
#   in a bold ink outline over a drop shadow, an ink frame with a white rule; 256 px cells packed 4 x 4 into
#   1024 px sheets (art/export/panels/Portraits_<n>.png), so the 50 portraits are 4 uploads.
# * panels (build/panels/raw/panel_<page>.<n>.png, the whole scene): a comic grade (flatter, punchier colour),
#   halftone dots in the shadows and an ink border; one 1024 x 512 image per panel
#   (art/export/panels/Panel_<page>_<n>.png). No text: captions and sound words stay in the UI.
# Then writes src/config/ComicArt.luau (each panel's image id, each portrait's sheet and cell; ids from
# art/export/panels/ids.json, which art/panels/upload.py fills; 0 = not uploaded, the UI draws today's frames)
# and the contact sheets art/preview/panels.png and art/preview/portraits.png.
# A portrait or panel with no raw render keeps its exported image as it is (2026-11-19: re-render only what
# changed, so unchanged panels keep their uploaded ids; a kept portrait is cut from its old sheet cell, which
# needs the cast's portrait order unchanged).
# Run: python3 art/panels/post.py   (PIL and numpy)
import json
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ART = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.path.dirname(ART)
RAW = os.path.join(REPO, "build", "panels", "raw")
OUT = os.path.join(ART, "export", "panels")
PREVIEW = os.path.join(ART, "preview")
CAST = json.load(open(os.path.join(OUT, "cast.json"), encoding="utf-8"))
IDS_PATH = os.path.join(OUT, "ids.json")
INK = (16, 16, 22)
CELL = 256
PER_ROW = 4
PANEL = (1024, 512)


# ------------------------------------------------------------------ portraits
def backdrop(n, base):
    base = tuple(base)
    ray = tuple(min(255, int(c * 1.35 + 18)) for c in base)
    dot = tuple(int(c * 0.7) for c in base)
    img = Image.new("RGB", (n, n), base)
    d = ImageDraw.Draw(img)
    cx, cy = n * 0.5, n * 0.38
    rays = 20
    for k in range(0, rays, 2):
        a0 = 2 * math.pi * k / rays
        a1 = 2 * math.pi * (k + 1) / rays
        d.polygon([(cx, cy), (cx + n * 2 * math.cos(a0), cy + n * 2 * math.sin(a0)),
                   (cx + n * 2 * math.cos(a1), cy + n * 2 * math.sin(a1))], fill=ray)
    step = n // 24
    for y in range(0, n + step, step):
        for x in range(0, n + step, step):
            ox = step // 2 if (y // step) % 2 else 0
            px, py = x + ox, y
            r = math.hypot(px - cx, py - cy) / (n * 0.75)
            rad = step * 0.45 * max(0.0, r - 0.3) / 0.7
            if rad > 0.7:
                d.ellipse([px - rad, py - rad, px + rad, py + rad], fill=dot)
    return img


def outlined(fig, ink_px):
    a = fig.split()[3].point(lambda v: 255 if v > 40 else 0)
    ink = a.filter(ImageFilter.MaxFilter(ink_px * 2 + 1)).filter(ImageFilter.GaussianBlur(1.0))
    ink = ink.point(lambda v: 255 if v > 110 else 0)
    out = Image.new("RGBA", fig.size, (0, 0, 0, 0))
    sh = Image.new("RGBA", fig.size, (0, 0, 0, 0))
    sh.putalpha(ink.point(lambda v: v * 120 // 255))
    out.alpha_composite(sh, (ink_px * 2, ink_px * 2))
    black = Image.new("RGBA", fig.size, (*INK, 255))
    black.putalpha(ink)
    out.alpha_composite(black)
    out.alpha_composite(fig)
    return out


def portrait_card(row):
    n = 512
    fig = Image.open(os.path.join(RAW, "portrait_%s.png" % row["key"])).convert("RGBA").resize((n, n),
                                                                                                 Image.LANCZOS)
    card = backdrop(n, row.get("bg") or (40, 40, 60)).convert("RGBA")
    card.alpha_composite(outlined(fig, 5))
    d = ImageDraw.Draw(card)
    d.rectangle([0, 0, n - 1, n - 1], outline=INK, width=16)
    d.rectangle([16, 16, n - 17, n - 17], outline=(255, 255, 255), width=5)
    return card.convert("RGB").resize((CELL, CELL), Image.LANCZOS)


# ------------------------------------------------------------------ panels
def halftone(img, step=7, strength=0.32):
    """Dark dots over the shadows (bigger where darker), the printed comic's look."""
    g = np.asarray(img.convert("L"), dtype=np.float32) / 255.0
    h, w = g.shape
    yy, xx = np.mgrid[0:h, 0:w]
    ox = ((yy // step) % 2) * (step / 2)
    cx = ((xx + ox) % step) - step / 2
    cy = (yy % step) - step / 2
    dist = np.sqrt(cx * cx + cy * cy) / (step / 2)
    radius = np.clip((0.55 - g) / 0.55, 0, 1) * 0.95
    mask = (dist < radius).astype(np.float32) * strength
    a = np.asarray(img, dtype=np.float32)
    a = a * (1 - mask[..., None]) + np.array(INK, dtype=np.float32) * mask[..., None]
    return Image.fromarray(a.clip(0, 255).astype(np.uint8))


def grade(img):
    a = np.asarray(img, dtype=np.float32) / 255.0
    # flatter, punchier: lift saturation and contrast a touch, then a soft posterize
    grey = a.mean(axis=2, keepdims=True)
    a = grey + (a - grey) * 1.25
    a = (a - 0.5) * 1.08 + 0.5
    a = np.round(a.clip(0, 1) * 14) / 14 * 0.35 + a.clip(0, 1) * 0.65
    return Image.fromarray((a * 255).clip(0, 255).astype(np.uint8))


def panel_image(p):
    img = Image.open(os.path.join(RAW, "panel_%s.png" % p["key"])).convert("RGB").resize(PANEL, Image.LANCZOS)
    img = halftone(grade(img))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, PANEL[0] - 1, PANEL[1] - 1], outline=INK, width=10)
    return img


def file_panel(p):
    return "Panel_%s_%d.png" % (p["page"], p["index"])


# ------------------------------------------------------------------ the config and the contact sheets
def lua_key(k):
    return k if k.isidentifier() else '["%s"]' % k


def write_config(sheets, cells, ids):
    lines = [
        "-- GENERATED by art/panels/post.py (the comic art pass, 2026-11-19): rendered comic art for the story's",
        "-- comic pages (Ui.CinemaHud) and the guides' and mentors' portraits (Ui.GuideHud, Ui.MentorHud). Every",
        "-- figure is Roblox's blocky R15 body in its game outfit with a Roblox catalog face and catalog hair",
        "-- (art/blender/panels.py; nate's rule). An id of 0 means not uploaded: the UI draws today's frames.",
        "return {",
        "\t-- one 1024 x 512 image per panel, keyed \"<page>.<n>\" (Config.Cinema.comic.pages)",
        "\tpanels = {",
    ]
    for p in CAST["panels"]:
        lines.append('\t\t["%s"] = %d,' % (p["key"], ids.get(file_panel(p), 0)))
    lines += [
        "\t},",
        "\t-- the portraits: %d px cells, %d to a row, on these sheets (image ids)" % (CELL, PER_ROW),
        "\tcell = %d," % CELL,
        "\tsheets = { %s }," % ", ".join(str(ids.get(s, 0)) for s in sheets),
        "\t-- each portrait's { sheet, column, row } (0-based column and row), keyed like",
        "\t-- Config.Story.guides.speakers, Config.SideQuests.givers and Config.Mentors.list ids",
        "\tportraits = {",
    ]
    for key, (si, c, r) in cells.items():
        lines.append("\t\t%s = { %d, %d, %d }," % (lua_key(key), si + 1, c, r))
    lines += ["\t},", "\t-- the same portrait as another key", "\taliases = {"]
    for k, v in sorted(CAST["aliases"].items()):
        lines.append('\t\t%s = "%s",' % (lua_key(k), v))
    lines += ["\t},", "}", ""]
    open(os.path.join(REPO, "src", "config", "ComicArt.luau"), "w").write("\n".join(lines))


def font(size):
    for f in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
              "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"):
        if os.path.isfile(f):
            return ImageFont.truetype(f, size)
    return ImageFont.load_default()


def old_card(sheet_cache, si, c, r):
    """A kept portrait: its card cut from the exported sheet (read before any sheet is rewritten)."""
    img = sheet_cache.get(si)
    if img is None:
        raise SystemExit("post.py: no raw render and no old sheet for a portrait (sheet %d)" % (si + 1))
    return img.crop((c * CELL, r * CELL, (c + 1) * CELL, (r + 1) * CELL))


def main():
    os.makedirs(OUT, exist_ok=True)
    ids = json.load(open(IDS_PATH)) if os.path.isfile(IDS_PATH) else {}
    sheet_cache = {}
    for si in range(8):
        path = os.path.join(OUT, "Portraits_%d.png" % (si + 1))
        if os.path.isfile(path):
            sheet_cache[si] = Image.open(path).convert("RGB")
    kept = 0
    # portraits
    rows = CAST["portraits"]
    per = PER_ROW * PER_ROW
    sheets, cells, cards = [], {}, []
    for si in range((len(rows) + per - 1) // per):
        sheet = Image.new("RGB", (CELL * PER_ROW, CELL * PER_ROW), INK)
        for k, row in enumerate(rows[si * per:(si + 1) * per]):
            c, r = k % PER_ROW, k // PER_ROW
            if os.path.isfile(os.path.join(RAW, "portrait_%s.png" % row["key"])):
                card = portrait_card(row)
            else:
                card = old_card(sheet_cache, si, c, r)
                kept += 1
            sheet.paste(card, (c * CELL, r * CELL))
            cells[row["key"]] = (si, c, r)
            cards.append((row, card))
        name = "Portraits_%d.png" % (si + 1)
        sheet.save(os.path.join(OUT, name))
        sheets.append(name)
    # the portraits' contact sheet: every card large, then at the guide box's 52 px
    cols = 10
    rows_n = (len(cards) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * 200, rows_n * 250), (36, 36, 44))
    d = ImageDraw.Draw(sheet)
    f = font(13)
    for k, (row, card) in enumerate(cards):
        x, y = (k % cols) * 200, (k // cols) * 250
        sheet.paste(card.resize((180, 180), Image.LANCZOS), (x + 10, y + 8))
        sheet.paste(card.resize((52, 52), Image.LANCZOS), (x + 10, y + 192))
        d.text((x + 68, y + 196), row["key"], fill=(255, 255, 255), font=f)
        d.text((x + 68, y + 214), (row.get("face") or {}).get("name", "")[:20], fill=(170, 200, 255), font=f)
    sheet.save(os.path.join(PREVIEW, "portraits.png"))
    # panels
    imgs = []
    for p in CAST["panels"]:
        if os.path.isfile(os.path.join(RAW, "panel_%s.png" % p["key"])):
            img = panel_image(p)
            img.save(os.path.join(OUT, file_panel(p)))
        else:
            img = Image.open(os.path.join(OUT, file_panel(p))).convert("RGB")  # kept as exported
            kept += 1
        imgs.append((p, img))
    pages = sorted({p["page"] for p in CAST["panels"]})
    tw, th = 340, 170
    sheet = Image.new("RGB", (4 * tw + 220, len(pages) * (th + 6)), (36, 36, 44))
    d = ImageDraw.Draw(sheet)
    for pi, page in enumerate(pages):
        d.text((8, pi * (th + 6) + th // 2 - 8), page, fill=(255, 255, 255), font=font(16))
        for p, img in imgs:
            if p["page"] == page:
                sheet.paste(img.resize((tw, th), Image.LANCZOS), (220 + (p["index"] - 1) * tw, pi * (th + 6)))
    sheet.save(os.path.join(PREVIEW, "panels.png"))
    write_config(sheets, cells, ids)
    print("post.py: %d portraits on %d sheets, %d panels (%d kept as exported); config and previews written" % (
        len(cards), len(sheets), len(imgs), kept))


if __name__ == "__main__":
    main()
