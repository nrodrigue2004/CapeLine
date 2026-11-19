# label.py: writes the contact sheet's cell labels onto a render (art/blender/clips.py calls it; Blender's
# python has no PIL). Run: python3 -I art/anims/label.py <image.png> <labels.json>
import json
import sys

from PIL import Image, ImageDraw, ImageFont

path, spec = sys.argv[1], sys.argv[2]
im = Image.open(path).convert("RGB")
dr = ImageDraw.Draw(im)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 20)
except OSError:
    font = ImageFont.load_default()
for x, y, text in json.load(open(spec)):
    w = dr.textlength(text, font=font)
    dr.text((x - w / 2, y), text, fill=(255, 255, 255), font=font, stroke_width=2, stroke_fill=(0, 0, 0))
im.save(path)
