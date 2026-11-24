"""Regenerate the README controller previews: front and back side by side on the
line-art background, one PNG per controller in docs/images/art/.

  python tools/art/previews.py

Reads the shipped textures (media/controllers/<id>.tga, <id>_back.tga), crops each
to its drawing, scales both to a common height and lays them out with a gap.
"""

import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
MEDIA = os.path.join(ROOT, "media", "controllers")
OUT = os.path.join(ROOT, "docs", "images", "art")

BG = (43, 44, 51)
TILE_H = 220  # height each controller is scaled to
PAD = 24  # margin around the drawings
GAP = 40  # space between front and back

ORDER = [
    "steamdeck",
    "steamcontroller",
    "xbox",
    "dualsense",
    "switchpro",
    "dualshock4",
    "xbox360",
    "rogally",
    "legiongo",
    "msiclaw",
    "8bitdo",
    "generic",
]


def cropped(path):
    img = Image.open(path).convert("RGBA")
    bbox = img.getbbox()  # tight box around the non-transparent drawing
    img = img.crop(bbox)
    s = TILE_H / img.height
    return img.resize((round(img.width * s), TILE_H), Image.LANCZOS)


def preview(cid):
    front = cropped(os.path.join(MEDIA, cid + ".tga"))
    back = cropped(os.path.join(MEDIA, cid + "_back.tga"))
    w = PAD + front.width + GAP + back.width + PAD
    h = PAD + TILE_H + PAD
    sheet = Image.new("RGB", (w, h), BG)
    front_rgba = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    front_rgba.alpha_composite(front, (PAD, PAD))
    front_rgba.alpha_composite(back, (PAD + front.width + GAP, PAD))
    sheet.paste(Image.alpha_composite(Image.new("RGBA", (w, h), (*BG, 255)), front_rgba).convert("RGB"))
    sheet.save(os.path.join(OUT, cid + ".png"), optimize=True)
    print(f"{cid:<16} -> docs/images/art/{cid}.png  ({w}x{h})")


def main():
    os.makedirs(OUT, exist_ok=True)
    for cid in ORDER:
        preview(cid)


if __name__ == "__main__":
    main()
