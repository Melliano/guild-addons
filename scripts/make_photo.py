"""Turn a screenshot into a Hall of Fame photo WoW can display.

WoW addons can only show .tga/.blp images whose sides are powers of two,
so this crops the picture to 2:1 around the centre (or a box you give)
and saves a 512x256 32-bit TGA.

    pip install pillow
    python scripts/make_photo.py screenshot.jpg GoonerJourneys/media/hall_of_thanes.tga
    python scripts/make_photo.py shot.png out.tga --box 100,80,1300,680   # left,top,right,bottom

Then set image = "Interface\\\\AddOns\\\\GoonerJourneys\\\\media\\\\hall_of_thanes" on the
entry in GoonerJourneys/HallOfFame.lua (no file extension).
"""
import argparse
from PIL import Image

W, H = 512, 256


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--box", help="crop box left,top,right,bottom in source pixels")
    a = ap.parse_args()

    img = Image.open(a.src).convert("RGBA")
    if a.box:
        img = img.crop(tuple(int(v) for v in a.box.split(",")))
    # Centre-crop to 2:1.
    w, h = img.size
    if w / h > W / H:
        nw = int(h * W / H)
        img = img.crop(((w - nw) // 2, 0, (w - nw) // 2 + nw, h))
    else:
        nh = int(w * H / W)
        img = img.crop((0, (h - nh) // 2, w, (h - nh) // 2 + nh))
    img = img.resize((W, H), Image.LANCZOS)
    img.save(a.dst, format="TGA", rle=False)
    print(f"saved {a.dst} ({W}x{H})")


if __name__ == "__main__":
    main()
