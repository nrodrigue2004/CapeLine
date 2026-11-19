# villains.py: the side quest villains' name card portraits (gap-villains, 2026-11-19, nate: the finale name
# cards get portraits). Inks the renders of `art/blender/panels.py villains` (build/panels/raw/villain_<Name>.png:
# the villain on Roblox's blocky R15 body in their own outfit with their catalog face, hair and beard, or a
# finale that is not a person in its own model) in the boss cards' comic style (art/news/post.py: a sunburst and
# halftone dots in the villain's colour, a bold ink outline, an ink frame with a white rule and a colour rule).
# * art/export/villains/VillainCards_<n>.png: 512 px cells, 2 x 2 to a 1024 sheet (Roblox keeps images to 1024)
# * src/config/VillainArt.luau: each card name's { sheet, column, row } and the sheet ids (from
#   art/export/villains/ids.json; 0 = not uploaded, the card shows its words only)
# * art/preview/villain_cards.png: the contact sheet with each card's name
# No words in the images: the names and titles stay UI text.
# Run from the repo root: lune run art/panels/cast.luau && $HOME/tools/bpyenv/bin/python art/blender/panels.py
#   villains && python3 art/panels/villains.py [--upload]   (--upload: Open Cloud Image uploads of new or changed
#   sheets, polled and moderation-checked, via art/news/upload.py's loop; then the config is rewritten)
import hashlib
import importlib.util
import json
import os
import sys

from PIL import Image, ImageDraw

ART = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.path.dirname(ART)
RAW = os.path.join(REPO, "build", "panels", "raw")
OUT = os.path.join(ART, "export", "villains")
PREVIEW = os.path.join(ART, "preview")
IDS = os.path.join(OUT, "ids.json")
CAST = json.load(open(os.path.join(ART, "export", "panels", "cast.json"), encoding="utf-8"))
CELL = 512
PER = 2  # cells a side on one sheet


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


panels = _load("panels_post", os.path.join(ART, "panels", "post.py"))
INK = panels.INK


def slug(name):
    return "".join(ch for ch in name.title() if ch.isalnum())


def card(v):
    raw = os.path.join(RAW, "villain_%s.png" % slug(v["name"]))
    if not os.path.isfile(raw):
        return None
    fig = Image.open(raw).convert("RGBA")
    box = fig.split()[3].point(lambda a: 255 if a > 20 else 0).getbbox()
    fig = fig.crop(box)
    n = 1024
    # as big as fits with room for the ink, the cut at the chest on the frame's bottom
    k = min((n * 0.86) / fig.width, (n * 0.9) / fig.height)
    fig = fig.resize((max(1, int(fig.width * k)), max(1, int(fig.height * k))), Image.LANCZOS)
    layer = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    layer.alpha_composite(fig, ((n - fig.width) // 2, n - fig.height))
    rgb = tuple(v["color"])
    dark = tuple(int(c * 0.55) for c in rgb)
    img = panels.backdrop(n, dark).convert("RGBA")
    img.alpha_composite(panels.outlined(layer, 9))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, n - 1, n - 1], outline=INK, width=30)
    d.rectangle([30, 30, n - 31, n - 31], outline=(255, 255, 255), width=10)
    d.rectangle([40, 40, n - 41, n - 41], outline=rgb, width=8)
    return img.convert("RGB").resize((CELL, CELL), Image.LANCZOS)


def sheets():
    os.makedirs(OUT, exist_ok=True)
    per = PER * PER
    vs = CAST["villains"]
    at, kept, made = {}, 0, []
    for s0 in range(0, len(vs), per):
        si = s0 // per + 1
        path = os.path.join(OUT, "VillainCards_%d.png" % si)
        old = Image.open(path).convert("RGB") if os.path.isfile(path) else None
        sheet = Image.new("RGB", (CELL * PER, CELL * PER), INK)
        for j, v in enumerate(vs[s0:s0 + per]):
            c, r = j % PER, j // PER
            img = card(v)
            if img is None:
                if old is None:
                    raise SystemExit("villains.py: no render and no old sheet for " + v["name"])
                img = old.crop((c * CELL, r * CELL, (c + 1) * CELL, (r + 1) * CELL))
                kept += 1
            sheet.paste(img, (c * CELL, r * CELL))
            at[v["name"]] = (si, c, r)
        sheet.save(path)
        made.append(os.path.basename(path))
    return at, kept, made


def upload(files):
    up = _load("news_upload", os.path.join(ART, "news", "upload.py"))
    user = os.environ.get("ROBLOX_USER_ID")
    if not user:
        raise SystemExit("villains.py: ROBLOX_USER_ID is not set")
    ids = json.load(open(IDS)) if os.path.isfile(IDS) else {}
    sha = ids.setdefault("sha", {})
    bad = []
    for f in files:
        path = os.path.join(OUT, f)
        h = hashlib.sha1(open(path, "rb").read()).hexdigest()
        if ids.get(f) and sha.get(f) == h:
            continue
        aid = up.upload(path, user, "Image")
        if not aid:
            bad.append(f)
            continue
        ids[f], sha[f] = int(aid), h
        json.dump(ids, open(IDS, "w"), indent=1, sort_keys=True)
        print("villains.py: uploaded", f, aid, flush=True)
    for f in files:
        if ids.get(f):
            st = up.moderation(ids[f])
            if st != "Approved":
                bad.append("%s (%s)" % (f, st))
    if bad:
        print("villains.py: not done:", bad)
    return ids


def write_config(at, files, ids):
    lines = [
        "-- GENERATED by art/panels/villains.py (gap-villains, 2026-11-19): the side quest villains' name card",
        "-- portraits (Ui.CinemaHud's card picture, kind \"villain\"; Shared.VillainCards). Each villain is Roblox's",
        "-- blocky R15 body in their own outfit with their catalog face, hair and beard (art/blender/panels.py",
        "-- villains), or a finale that is not a person in its own model. An id of 0 means not uploaded: the card",
        "-- shows its words only. No words in the images.",
        "return {",
        "\t-- 512 px cells, 2 x 2 on each 1024 sheet (image ids)",
        "\tcell = %d," % CELL,
        "\tsheets = { %s }," % ", ".join(str(int(ids.get(f, 0))) for f in files),
        "\t-- each card name (Config.SideQuests: a chain's villain, an encore's first foe) -> { sheet, column, row }",
        "\tcards = {",
    ]
    for name in sorted(at):
        si, c, r = at[name]
        lines.append('\t\t["%s"] = { %d, %d, %d },' % (name, si, c, r))
    lines += ["\t},", "}", ""]
    open(os.path.join(REPO, "src", "config", "VillainArt.luau"), "w").write("\n".join(lines))


def preview(at, files):
    from PIL import ImageFont
    try:
        font = ImageFont.truetype("DejaVuSans-Bold.ttf", 15)
    except OSError:
        font = ImageFont.load_default()
    t = 220
    cols = 6
    names = sorted(at)
    img = Image.new("RGB", (cols * (t + 12) + 12, ((len(names) + cols - 1) // cols) * (t + 34) + 12), (36, 38, 46))
    d = ImageDraw.Draw(img)
    cache = {}
    for i, name in enumerate(names):
        si, c, r = at[name]
        sh = cache.get(si) or Image.open(os.path.join(OUT, files[si - 1])).convert("RGB")
        cache[si] = sh
        cell = sh.crop((c * CELL, r * CELL, (c + 1) * CELL, (r + 1) * CELL)).resize((t, t), Image.LANCZOS)
        x, y = 12 + (i % cols) * (t + 12), 12 + (i // cols) * (t + 34)
        img.paste(cell, (x, y))
        d.text((x, y + t + 6), name, fill=(240, 240, 240), font=font)
    img.save(os.path.join(PREVIEW, "villain_cards.png"))


def main():
    at, kept, files = sheets()
    ids = upload(files) if "--upload" in sys.argv else (json.load(open(IDS)) if os.path.isfile(IDS) else {})
    write_config(at, files, ids)
    preview(at, files)
    print("villains.py: %d cards (%d kept) on %d sheets; config and preview written" % (len(at), kept, len(files)))


if __name__ == "__main__":
    main()
