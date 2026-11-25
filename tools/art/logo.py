"""Generate the project logo: a flat 2-color Steam Deck-style handheld + spark.

One parametric design emits both the vector source and a raster export:

    python tools/art/logo.py            # writes docs/images/logo.svg + logo.png

The SVG is the source of truth; the PNG (transparent, 1024px) is for CurseForge
and the README. An own, MIT mark -- dark rounded tile, brand-purple handheld.
"""

import math
import os

from PIL import Image, ImageDraw

PUR = (184, 150, 255)
DARK = (23, 21, 30)
PURA = (*PUR, 255)
DARKA = (*DARK, 255)
PURH = "#b896ff"
DARKH = "#17151e"

# geometry in a 0..100 square (viewBox units)
G = dict(
    tile_r=0,
    body=(12, 88, 32, 68),
    body_r=12.5,
    screen=(37, 63, 40, 60),
    screen_r=2.6,
    lx=23.5,
    rx=76.5,
    ytop=42.5,
    ybot=57.5,
    stick=4.4,
    arm=3.8,
    armw=2.2,
    boff=4.6,
    br=2.1,
    sparkles=((84.5, 21, 4.2), (90.5, 28, 2.1)),
)
DOTS = ((0, -1), (0, 1), (-1, 0), (1, 0))


def _sparkle_pts(cx, cy, R, waist=0.30):
    pts = []
    for i in range(4):
        a = math.radians(90 * i)
        pts.append((cx + R * math.cos(a), cy - R * math.sin(a)))
        a2 = math.radians(90 * i + 45)
        pts.append((cx + R * waist * math.cos(a2), cy - R * waist * math.sin(a2)))
    return pts


def to_svg(g):
    bx0, bx1, by0, by1 = g["body"]
    sx0, sx1, sy0, sy1 = g["screen"]
    lx, rx, yt, yb = g["lx"], g["rx"], g["ytop"], g["ybot"]
    st, arm, aw, boff, br = g["stick"], g["arm"], g["armw"], g["boff"], g["br"]
    e = [f'<rect width="100" height="100" rx="{g["tile_r"]}" fill="{DARKH}"/>']
    e.append(f'<rect x="{bx0}" y="{by0}" width="{bx1 - bx0}" height="{by1 - by0}" rx="{g["body_r"]}" fill="{PURH}"/>')
    e.append(
        f'<rect x="{sx0}" y="{sy0}" width="{sx1 - sx0}" height="{sy1 - sy0}" rx="{g["screen_r"]}" fill="{DARKH}"/>'
    )
    e.append(f'<circle cx="{lx}" cy="{yt}" r="{st}" fill="{DARKH}"/>')
    e.append(
        f'<rect x="{lx - aw / 2}" y="{yb - arm}" width="{aw}" height="{2 * arm}" rx="{aw * 0.35:.2f}" fill="{DARKH}"/>'
    )
    e.append(
        f'<rect x="{lx - arm}" y="{yb - aw / 2}" width="{2 * arm}" height="{aw}" rx="{aw * 0.35:.2f}" fill="{DARKH}"/>'
    )
    for dx, dy in DOTS:
        e.append(f'<circle cx="{rx + dx * boff}" cy="{yt + dy * boff}" r="{br}" fill="{DARKH}"/>')
    e.append(f'<circle cx="{rx}" cy="{yb}" r="{st}" fill="{DARKH}"/>')
    for cx, cy, R in g["sparkles"]:
        pts = " ".join(f"{x:.2f},{y:.2f}" for x, y in _sparkle_pts(cx, cy, R))
        e.append(f'<polygon points="{pts}" fill="{PURH}"/>')
    inner = "\n  ".join(e)
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" '
        f'width="1024" height="1024">\n  {inner}\n</svg>\n'
    )


def to_png(g, path, px=1024, ss=4):
    w = px * ss
    im = Image.new("RGBA", (w, w), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    k = w / 100.0

    def rr(x0, y0, x1, y1, r, fill):
        d.rounded_rectangle([x0 * k, y0 * k, x1 * k, y1 * k], radius=r * k, fill=fill)

    def cc(cx, cy, r, fill):
        d.ellipse([(cx - r) * k, (cy - r) * k, (cx + r) * k, (cy + r) * k], fill=fill)

    bx0, bx1, by0, by1 = g["body"]
    sx0, sx1, sy0, sy1 = g["screen"]
    lx, rx, yt, yb = g["lx"], g["rx"], g["ytop"], g["ybot"]
    st, arm, aw, boff, br = g["stick"], g["arm"], g["armw"], g["boff"], g["br"]
    rr(0, 0, 100, 100, g["tile_r"], DARKA)
    rr(bx0, by0, bx1, by1, g["body_r"], PURA)
    rr(sx0, sy0, sx1, sy1, g["screen_r"], DARKA)
    cc(lx, yt, st, DARKA)
    rr(lx - aw / 2, yb - arm, lx + aw / 2, yb + arm, aw * 0.35, DARKA)
    rr(lx - arm, yb - aw / 2, lx + arm, yb + aw / 2, aw * 0.35, DARKA)
    for dx, dy in DOTS:
        cc(rx + dx * boff, yt + dy * boff, br, DARKA)
    cc(rx, yb, st, DARKA)
    for cx, cy, R in g["sparkles"]:
        d.polygon([(x * k, y * k) for x, y in _sparkle_pts(cx, cy, R)], fill=PURA)
    im.resize((px, px), Image.LANCZOS).save(path)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(os.path.dirname(os.path.dirname(here)), "docs", "images")
    with open(os.path.join(out, "logo.svg"), "w", encoding="utf-8", newline="\n") as f:
        f.write(to_svg(G))
    to_png(G, os.path.join(out, "logo.png"))
    print("wrote docs/images/logo.svg + logo.png")


if __name__ == "__main__":
    main()
