"""Back views of the controllers, drawn in the same Valve line-art style.

The back is drawn "seen through" the controller (left stays left, as you hold it),
which is how Steam shows back buttons too. It reuses the front drawing's outline,
adds an inner shell line, the shoulder buttons from the front measurements and the
back buttons at their real positions. Paddle numbering follows SDL / WoW:
P1 = upper right, P2 = lower right, P3 = upper left, P4 = lower left.
"""

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageOps

LBG = (43, 44, 51, 255)
WHITE = (244, 244, 246, 255)
GREY = (142, 144, 152, 255)

# Back buttons per controller: binding -> (label, x, y, w, h) in 0..1 of the drawing.
PADDLES = {
    "steamdeck": {
        "PADPADDLE3": ("L4", 0.075, 0.40, 0.030, 0.17),
        "PADPADDLE4": ("L5", 0.075, 0.62, 0.030, 0.17),
        "PADPADDLE1": ("R4", 0.925, 0.40, 0.030, 0.17),
        "PADPADDLE2": ("R5", 0.925, 0.62, 0.030, 0.17),
    },
    "xbox": {},  # standard Xbox controller: no back buttons
    # DualSense Edge back buttons
    "dualsense": {
        "PADPADDLE3": ("LB", 0.22, 0.70, 0.045, 0.15),
        "PADPADDLE1": ("RB", 0.78, 0.70, 0.045, 0.15),
    },
    # Switch Pro: no back buttons, the back shows ZL / ZR / L / R only
    "switchpro": {},
    "dualshock4": {},
    "xbox360": {},
    "rogally": {
        "PADPADDLE3": ("M1", 0.09, 0.55, 0.03, 0.2),
        "PADPADDLE1": ("M2", 0.91, 0.55, 0.03, 0.2),
    },
    "legiongo": {
        "PADPADDLE3": ("M2", 0.06, 0.45, 0.03, 0.14),
        "PADPADDLE4": ("M3", 0.06, 0.66, 0.03, 0.14),
        "PADPADDLE1": ("Y1", 0.94, 0.45, 0.03, 0.14),
        "PADPADDLE2": ("Y2", 0.94, 0.66, 0.03, 0.14),
    },
    "msiclaw": {
        "PADPADDLE3": ("M1", 0.09, 0.58, 0.03, 0.2),
        "PADPADDLE1": ("M2", 0.91, 0.58, 0.03, 0.2),
    },
    "8bitdo": {
        "PADPADDLE3": ("P1", 0.24, 0.66, 0.04, 0.16),
        "PADPADDLE1": ("P2", 0.76, 0.66, 0.04, 0.16),
    },
    "generic": {},
    # Steam Controller (2026): four back buttons, same R4/R5/L4/L5 convention as the Deck
    "steamcontroller": {
        "PADPADDLE3": ("L4", 0.09, 0.55, 0.03, 0.2),
        "PADPADDLE4": ("L5", 0.09, 0.76, 0.03, 0.2),
        "PADPADDLE1": ("R4", 0.91, 0.55, 0.03, 0.2),
        "PADPADDLE2": ("R5", 0.91, 0.76, 0.03, 0.2),
    },
}

SUBTITLE = {
    "steamdeck": "Steam Deck (back)",
    "xbox": "Xbox (back)",
    "dualsense": "DualSense Edge (back)",
    "switchpro": "Switch Pro (back)",
    "dualshock4": "DualShock 4 (back)",
    "xbox360": "Xbox 360 (back)",
    "steamcontroller": "Steam Controller (back)",
    "rogally": "ROG Ally (back)",
    "legiongo": "Legion Go (back)",
    "msiclaw": "MSI Claw (back)",
    "8bitdo": "8BitDo Pro 2 (back)",
    "generic": "Generic gamepad (back)",
}

SHOULDERS = ("PADLTRIGGER", "PADRTRIGGER", "PADLSHOULDER", "PADRSHOULDER")


def _erode(mask, px):
    # repeated 3x3 passes: linear in px (one big MinFilter is quadratic and slow);
    # padded so the image border counts as outside
    m = ImageOps.expand(mask, 2, 0)
    for _ in range(px):
        m = m.filter(ImageFilter.MinFilter(3))
    return m.crop((2, 2, 2 + mask.width, 2 + mask.height))


def _edge(mask, width):
    """Ring of `width` px along the inside of a binary mask."""
    return ImageChops.subtract(mask, _erode(mask, width))


def solid(mask, close=6):
    """Closes small notches between parts of the front drawing and fills holes,
    so the back gets one continuous outline."""
    pad = close + 2
    m = ImageOps.expand(mask, pad, 0)
    for _ in range(close):
        m = m.filter(ImageFilter.MaxFilter(3))
    m = _erode(m, close)
    outside = ImageOps.invert(m)
    ImageDraw.floodfill(outside, (0, 0), 128)
    m = outside.point(lambda v: 0 if v == 128 else 255)
    return m.crop((pad, pad, pad + mask.width, pad + mask.height))


DETAILS = {
    # vent grille in the middle of the Deck's back
    "steamdeck": [(0.5, 0.2, 0.36, 0.06), (0.5, 0.29, 0.36, 0.06)],
}


def draw(front, anchors, cid, stroke):
    """front: RGBA front drawing; anchors: measured front anchors (cx, cy, w, h in 0..1).
    Returns (RGBA back drawing, back anchors in the same 0..1 space)."""
    W, H = front.size
    mask = solid(front.getchannel("A").point(lambda a: 255 if a > 8 else 0))
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    img.paste(LBG, mask=mask)

    # inner shell line: the back cover sits a little inside the outline
    inset = max(6, int(min(W, H) * 0.045))
    inner = _erode(mask, inset)
    img.paste(GREY, mask=_edge(inner, max(1, stroke // 2)))
    img.paste(WHITE, mask=_edge(mask, stroke))

    d = ImageDraw.Draw(img)
    out = {}

    def pill(x, y, w, h, fill=LBG):
        box = [(x - w / 2) * W, (y - h / 2) * H, (x + w / 2) * W, (y + h / 2) * H]
        r = min(box[2] - box[0], box[3] - box[1]) / 2
        d.rounded_rectangle(box, radius=r, fill=fill, outline=WHITE, width=stroke)

    for x, y, w, h in DETAILS.get(cid, []):
        box = [(x - w / 2) * W, (y - h / 2) * H, (x + w / 2) * W, (y + h / 2) * H]
        d.rounded_rectangle(box, radius=(box[3] - box[1]) / 2, outline=GREY, width=max(1, stroke // 2))
    for b in SHOULDERS:
        a = anchors.get(b)
        if a:
            pill(a["cx"], a["cy"], a["w"], max(a["h"], 0.03))
            out[b] = dict(cx=a["cx"], cy=a["cy"], w=a["w"], h=a["h"])
    for b, (_, x, y, w, h) in PADDLES[cid].items():
        pill(x, y, w, h)
        out[b] = dict(cx=x, cy=y, w=w, h=h)
    return img, out


def labels(cid):
    """binding -> printed label for the back buttons of `cid`."""
    return {b: v[0] for b, v in PADDLES[cid].items()}
