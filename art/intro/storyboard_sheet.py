# storyboard_sheet.py: packs the intro film's storyboard frames (art/blender/intro_storyboard.py) into two sheets
# with the screen layer drawn on as the game shows it: the letterbox, the comic caption box (top left), the sound
# word, the CAPELINE title, and under each frame its time, shot and what is on screen. art/preview/intro_film_1.png
# (the cold open, 0 to 13 s) and intro_film_2.png (the world, 13 to 45 s). list-combat 2026-11-20.
# Run: python3 art/intro/storyboard_sheet.py   (plain python3 with PIL)
import json
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
DATA = json.load(open(os.path.join(ROOT, "export", "intro", "storyboard.json")))
FRAMES = os.path.join(ROOT, "export", "intro", "frames")
COLS = 4
CAP = 40
INK, PAPER = (18, 18, 22), (255, 226, 90)


def font(size, bold=True):
    names = ["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"] if bold else []
    names += ["/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]
    for f in names:
        try:
            return ImageFont.truetype(f, size)
        except OSError:
            pass
    return ImageFont.load_default()


big, small, cap_f, word_f, title_f = font(16), font(12, False), font(13), font(30), font(54)


def wrap(d, text, f, width):
    words, lines, cur = text.split(), [], ""
    for w in words:
        t = (cur + " " + w).strip()
        if d.textlength(t, font=f) > width and cur:
            lines.append(cur)
            cur = w
        else:
            cur = t
    if cur:
        lines.append(cur)
    return lines


def screen(img, fr):
    w, h = img.size
    d = ImageDraw.Draw(img)
    bar = int(h * 0.1)
    d.rectangle((0, 0, w, bar), fill=(0, 0, 0))
    d.rectangle((0, h - bar, w, h), fill=(0, 0, 0))
    if fr["caption"]:
        lines = wrap(d, fr["caption"].upper(), cap_f, int(w * 0.4))
        bw = int(w * 0.44)
        bh = 10 + 17 * len(lines)
        x0, y0 = int(w * 0.035), bar + int(h * 0.03)
        d.rectangle((x0, y0, x0 + bw, y0 + bh), fill=PAPER, outline=INK, width=3)
        for i, ln in enumerate(lines):
            d.text((x0 + 8, y0 + 5 + 17 * i), ln, fill=INK, font=cap_f)
    if fr["word"]:
        t = fr["word"]
        tw = d.textlength(t, font=word_f)
        x, y = w * 0.62 - tw / 2, h * 0.32
        col = (255, 60, 60) if t == "SPARK DETECTED" else PAPER
        d.text((x, y), t, fill=col, font=word_f, stroke_width=3, stroke_fill=INK)
    if fr["title"]:
        t = "CAPELINE"
        tw = d.textlength(t, font=title_f)
        d.text(((w - tw) / 2, h * 0.3), t, fill=(255, 200, 60), font=title_f, stroke_width=5, stroke_fill=INK)
    return img


def sheet(name, frames):
    cells = []
    for i, fr in frames:
        p = os.path.join(FRAMES, "%02d_%05.1f.png" % (i, fr["t"]))
        if os.path.exists(p):
            cells.append((screen(Image.open(p).convert("RGB"), fr), fr))
    if not cells:
        return
    w, h = cells[0][0].size
    rows = (len(cells) + COLS - 1) // COLS
    out = Image.new("RGB", (COLS * w, rows * (h + CAP)), (24, 24, 28))
    d = ImageDraw.Draw(out)
    for k, (img, fr) in enumerate(cells):
        x, y = (k % COLS) * w, (k // COLS) * (h + CAP)
        out.paste(img, (x, y))
        who = sorted({a["id"] if a["kind"] == "fake" else a["kind"] for a in fr["actors"]})
        tag = "shot %d" % fr["shot"] if fr["shot"] else "moment"
        d.text((x + 8, y + h + 3), "%.1f s  [%s]" % (fr["t"], tag), fill=(240, 240, 240), font=big)
        d.text((x + 8, y + h + 22), ", ".join(who)[:80], fill=(190, 190, 200), font=small)
    path = os.path.join(ROOT, "preview", "intro_film_%s.png" % name)
    out.save(path)
    print(path, len(cells))


frames = list(enumerate(DATA["frames"]))
sheet("1", [(i, f) for i, f in frames if f["t"] < 13])
sheet("2", [(i, f) for i, f in frames if f["t"] >= 13])
