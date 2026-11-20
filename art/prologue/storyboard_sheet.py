# storyboard_sheet.py: packs the directed prologue's storyboard frames (art/blender/storyboard.py) into three
# sheets, each frame captioned with its beat, segment, camera shot (CUT for a hard cut, SLOW-MO for the leap) and
# its prompt: art/preview/prologue_street.png (the run and the Spark), prologue_roofs.png (the leap, the chase, the
# suit, the drop) and prologue_tunnel.png (the tunnel chase). prologue-cine, 2026-11-20.
# Run: python3 art/prologue/storyboard_sheet.py   (plain python3 with PIL)
import json
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
DATA = json.load(open(os.path.join(ROOT, "export", "prologue", "storyboard.json")))
FRAMES = os.path.join(ROOT, "export", "prologue", "frames")
SHEETS = {
    "street": ("run", "spark"),
    "roofs": ("leap", "chase", "suit", "descend"),
    "tunnel": ("tunnel",),
}
COLS = 4
CAP = 46


def font(size):
    for f in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "DejaVuSans-Bold.ttf"):
        try:
            return ImageFont.truetype(f, size)
        except OSError:
            pass
    return ImageFont.load_default()


big, small = font(17), font(13)
for name, beats in SHEETS.items():
    cells = []
    for i, fr in enumerate(DATA["frames"]):
        if fr["beat"] in beats:
            p = os.path.join(FRAMES, "%02d_%s_%s.png" % (i, fr["beat"], fr["id"]))
            if os.path.exists(p):
                cells.append((Image.open(p).convert("RGB"), fr))
    if not cells:
        continue
    w, h = cells[0][0].size
    rows = (len(cells) + COLS - 1) // COLS
    sheet = Image.new("RGB", (COLS * w, rows * (h + CAP)), (24, 24, 28))
    d = ImageDraw.Draw(sheet)
    for k, (img, fr) in enumerate(cells):
        x, y = (k % COLS) * w, (k // COLS) * (h + CAP)
        sheet.paste(img.resize((w, h)), (x, y))
        if fr.get("prompt") and fr["note"] == "prompt":
            # the prompt as the player sees it: a gold disc low in the middle
            r = h // 9
            cx, cy = x + w // 2, y + int(h * 0.8)
            d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(250, 200, 40), outline=(20, 20, 20), width=3)
            tw = d.textlength(fr["prompt"], font=small)
            d.text((cx - tw / 2, cy - 8), fr["prompt"], fill=(20, 20, 20), font=small)
        tags = [fr["shot"].upper()]
        if fr.get("cut"):
            tags.append("CUT")
        if fr.get("slow"):
            tags.append("SLOW-MO")
        d.text((x + 8, y + h + 4), "%s / %s  [%s]" % (fr["beat"], fr["id"], " ".join(tags)), fill=(240, 240, 240), font=big)
        what = ("prompt %s (%s)" % (fr["prompt"], fr.get("kind"))) if fr["note"] == "prompt" else "move"
        d.text((x + 8, y + h + 25), "%s, clip %s" % (what, fr.get("clip")), fill=(190, 190, 200), font=small)
    out = os.path.join(ROOT, "preview", "prologue_%s.png" % name)
    sheet.save(out)
    print(out, len(cells))
