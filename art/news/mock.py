# mock.py: a stand-in picture of the news SurfaceGui for art/blender/screens.py's previews only (gap-news,
# 2026-11-19): the channel band, a headline and the ticker as NewsHud lays them out. Never uploaded; the game draws
# these as UI text. Run: python3 art/news/mock.py   (writes build/news/mock.png)
import os

from PIL import Image, ImageDraw, ImageFont

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(REPO, "build", "news")


def font(size):
    for f in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
              "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"):
        if os.path.isfile(f):
            return ImageFont.truetype(f, size)
    return ImageFont.load_default()


def main():
    os.makedirs(OUT, exist_ok=True)
    w, h = 720, 400
    img = Image.new("RGB", (w, h), (16, 22, 44))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, w, int(h * 0.22)], fill=(200, 30, 40))
    d.text((w // 2, int(h * 0.11)), "BREAKING NEWS", fill=(255, 250, 240), font=font(44), anchor="mm")
    d.text((w // 2, int(h * 0.42)), "IT'S RUSTJAW PRIME!", fill=(255, 250, 240), font=font(40), anchor="mm")
    d.text((w // 2, int(h * 0.58)), "HEROES AND VILLAINS ON THE WAY", fill=(255, 250, 240), font=font(30), anchor="mm")
    d.text((12, int(h * 0.88)), "BHN 24 / BRIGHTHARBOR NEWS  •  A HERO CLEARS 5 INCIDENTS IN A ROW",
           fill=(255, 205, 60), font=font(24), anchor="lm")
    img.save(os.path.join(OUT, "mock.png"))


if __name__ == "__main__":
    main()
