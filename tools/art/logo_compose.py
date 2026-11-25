"""Compose the final logo from a transparent device render.

Builds a dark background with a purple grimoire aura, drops the device on it
with a soft grounding shadow, adds a bloom glow on the screen/accents, and a
gentle vignette.

    python tools/art/logo_compose.py device_rgba.png docs/images/logo.png
"""

import sys

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter

src, dst = sys.argv[1], sys.argv[2]
ANGLE = 22  # diagonal roll so the wide handheld fills a square tile
FILL = 0.94  # fraction of the tile the device spans

w = h = 1024
raw = Image.open(src).convert("RGBA").rotate(ANGLE, expand=True, resample=Image.BICUBIC)
raw = raw.crop(raw.getbbox())
scale = int(w * FILL) / max(raw.size)
raw = raw.resize((max(1, round(raw.width * scale)), max(1, round(raw.height * scale))), Image.LANCZOS)
dev = Image.new("RGBA", (w, h), (0, 0, 0, 0))
dev.paste(raw, ((w - raw.width) // 2, (h - raw.height) // 2), raw)


def radial(cx, cy, rx, ry, blur):
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=255)
    return m.filter(ImageFilter.GaussianBlur(radius=blur))


# --- background: near-black with a purple aura behind the device ------------
bg = Image.new("RGB", (w, h), (10, 9, 15))
aura = radial(w * 0.50, h * 0.42, w * 0.34, h * 0.26, w * 0.17)
tint = Image.merge(
    "RGB",
    (
        aura.point(lambda p: p * 96 // 255),
        aura.point(lambda p: p * 60 // 255),
        aura.point(lambda p: p * 150 // 255),
    ),
)
bg = ImageChops.add(bg, tint)

# --- grounding shadow under the device --------------------------------------
alpha = dev.split()[3]
shadow = alpha.filter(ImageFilter.GaussianBlur(radius=w * 0.025))
shadow = ImageChops.offset(shadow, 0, int(h * 0.045))
shadow = shadow.point(lambda p: int(p * 0.55))
bg.paste((0, 0, 0), (0, 0), shadow)

# --- device on top ----------------------------------------------------------
out = bg.convert("RGB")
out.paste(dev, (0, 0), dev)

# --- bloom: device is the only bright thing, so threshold isolates it -------
gray = out.convert("L")
mask = gray.point(lambda p: 255 if p > 172 else 0)
bright = Image.composite(out, Image.new("RGB", out.size, (0, 0, 0)), mask)
glow = bright.filter(ImageFilter.GaussianBlur(radius=w * 0.016))
glow = ImageEnhance.Brightness(glow).enhance(0.8)
out = ImageChops.screen(out, glow)

# --- gentle vignette --------------------------------------------------------
vig = radial(w * 0.5, h * 0.5, w * 0.62, h * 0.62, w * 0.16)
vig = vig.point(lambda p: int(190 + p * 65 / 255))
out = ImageChops.multiply(out, Image.merge("RGB", (vig, vig, vig)))

out.save(dst)
print("COMPOSED", dst)
