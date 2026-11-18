# sheet.py: lays out a creator art preview (plain python3 with PIL): wear.grid_preview renders every kit from the
# front and from behind into two grid images; this pairs each kit's two views side by side with its name under
# them, so a whole tab reads at a glance.
# Run: python3 art/blender/sheet.py OUT FRONT BACK COLS CELL_PX name1,name2,...   (wear.grid_preview calls it)
import sys

from PIL import Image, ImageDraw, ImageFont

out, front, back = sys.argv[1], sys.argv[2], sys.argv[3]
cols, px, names = int(sys.argv[4]), int(sys.argv[5]), sys.argv[6].split(",")
F, B = Image.open(front).convert("RGB"), Image.open(back).convert("RGB")
rows = (len(names) + cols - 1) // cols
label = 34
gap = 8
W = cols * (2 * px + gap) + gap
H = rows * (px + label + gap) + gap
sheet = Image.new("RGB", (W, H), (38, 40, 48))
draw = ImageDraw.Draw(sheet)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 24)
except OSError:
    font = ImageFont.load_default()
for i, name in enumerate(names):
    r, c = i // cols, i % cols
    box = (c * px, r * px, (c + 1) * px, (r + 1) * px)
    x = gap + c * (2 * px + gap)
    y = gap + r * (px + label + gap)
    sheet.paste(F.crop(box), (x, y))
    sheet.paste(B.crop(box), (x + px, y))
    tw = draw.textlength(name, font=font)
    draw.text((x + px - tw / 2, y + px + 4), name, fill=(240, 240, 245), font=font)
sheet.save(out)
print("wrote", out)
