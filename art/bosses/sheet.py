"""sheet.py: lays the boss pose renders (build/boss_poses/<Boss>_NN.png from art/blender/boss_poses.py) out as one
contact sheet a boss with each pose's name: art/preview/boss_poses_<Boss>.png (the boss pass's render check).
Run: python3 art/bosses/sheet.py"""
import json
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA = json.load(open(os.path.join(ROOT, "build", "boss_poses.json")))
SRC = os.path.join(ROOT, "build", "boss_poses")
COLS, CELL, LABEL = 5, 320, 30


def font(size):
    for path in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf"):
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


F = font(18)
for bid, b in DATA.items():
    frames = b["frames"]
    files = [os.path.join(SRC, "%s_%02d.png" % (bid, k)) for k in range(len(frames))]
    if not all(os.path.exists(f) for f in files):
        print("skip", bid)
        continue
    rows = (len(frames) + COLS - 1) // COLS
    sheet = Image.new("RGB", (COLS * CELL, rows * (CELL + LABEL)), (30, 32, 38))
    d = ImageDraw.Draw(sheet)
    for k, (fr, f) in enumerate(zip(frames, files)):
        x, y = (k % COLS) * CELL, (k // COLS) * (CELL + LABEL)
        sheet.paste(Image.open(f).convert("RGB").resize((CELL, CELL)), (x, y))
        d.text((x + 8, y + CELL + 5), fr["name"], fill=(240, 240, 240), font=F)
    out = os.path.join(ROOT, "art", "preview", "boss_poses_%s.png" % bid)
    sheet.save(out)
    print("wrote", out)
