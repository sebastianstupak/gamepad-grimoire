"""Controllers drawn from a layout description, for devices with no vector source.

Draws in the same Valve line-art style as restyle.py (dark fill, white strokes,
grey stick rings) from simple shapes, and returns the button anchors in 0..1 of
the drawing, like restyle's measurements. Coordinates in a spec are fractions of
the drawing's width (x) and height (y); sizes `r` / `s` are fractions of the width.
"""

from back import GREY, LBG, WHITE, _edge
from PIL import Image, ImageChops, ImageDraw

W = 2000  # render width (downscaled by build.py like the other drawings)

# --- layouts -------------------------------------------------------------------
# body: shapes unioned into one silhouette ("rr" rounded rect x0 y0 x1 y1 radius,
#       "el" ellipse x0 y0 x1 y1); parts: separately outlined pieces (detachable
#       controllers); deco: non-button details; buttons: binding -> (kind, x, y, size)
#   kinds: stick (r), dpad (s), face (r, the four PAD1..4 around x, y), pill (w, h),
#          dot (r), trigger / bumper (w, h, drawn over the top edge)


def _handheld(aspect, screen, left_stick, dpad, face, right_stick, extra, body=None, parts=None, deco=None):
    lx, ly = left_stick
    rx, ry = right_stick
    return dict(
        aspect=aspect,
        body=body or [("rr", 0.01, 0.1, 0.99, 0.97, 0.16)],
        parts=parts or [],
        deco=(deco or []) + [("screen", *screen)],
        buttons={
            "PADLSTICK": ("stick", lx, ly, 0.042),
            "PADRSTICK": ("stick", rx, ry, 0.042),
            "PADDPAD": ("dpad", dpad[0], dpad[1], 0.072),
            "PADFACE": ("face", face[0], face[1], 0.0175),
            "PADLTRIGGER": ("trigger", 0.1, 0.075, 0.11, 0.08),
            "PADRTRIGGER": ("trigger", 0.9, 0.075, 0.11, 0.08),
            "PADLSHOULDER": ("bumper", 0.1, 0.105, 0.12, 0.045),
            "PADRSHOULDER": ("bumper", 0.9, 0.105, 0.12, 0.045),
            **extra,
        },
    )


LAYOUTS = {
    "rogally": dict(
        name="ROG Ally",
        **_handheld(
            aspect=2.55,
            screen=(0.225, 0.17, 0.775, 0.9),
            left_stick=(0.095, 0.34),
            dpad=(0.11, 0.66),
            face=(0.885, 0.36),
            right_stick=(0.865, 0.68),
            extra={
                "PADBACK": ("pill", 0.185, 0.2, 0.022, 0.05),
                "PADFORWARD": ("pill", 0.815, 0.2, 0.022, 0.05),
                "PADSOCIAL": ("pill", 0.185, 0.82, 0.022, 0.05),
                "PADSYSTEM": ("pill", 0.815, 0.82, 0.022, 0.05),
            },
        ),
    ),
    "legiongo": dict(
        name="Legion Go",
        **_handheld(
            aspect=2.3,
            screen=(0.215, 0.14, 0.785, 0.92),
            left_stick=(0.1, 0.32),
            dpad=(0.1, 0.62),
            face=(0.9, 0.32),
            right_stick=(0.9, 0.62),
            body=[("rr", 0.17, 0.1, 0.83, 0.97, 0.05)],
            parts=[("rr", 0.0, 0.1, 0.19, 0.97, 0.09), ("rr", 0.81, 0.1, 1.0, 0.97, 0.09)],
            deco=[("pad", 0.9, 0.84, 0.05, 0.06)],
            extra={
                "PADBACK": ("pill", 0.045, 0.19, 0.022, 0.045),
                "PADFORWARD": ("pill", 0.955, 0.19, 0.022, 0.045),
                "PADSOCIAL": ("dot", 0.1, 0.87, 0.012),
                "PADSYSTEM": ("dot", 0.955, 0.48, 0.012),
            },
        ),
    ),
    "msiclaw": dict(
        name="MSI Claw",
        **_handheld(
            aspect=2.45,
            screen=(0.23, 0.16, 0.77, 0.88),
            left_stick=(0.1, 0.33),
            dpad=(0.1, 0.64),
            face=(0.885, 0.36),
            right_stick=(0.87, 0.66),
            body=[("rr", 0.03, 0.1, 0.97, 0.9, 0.12), ("el", 0.0, 0.3, 0.22, 1.0), ("el", 0.78, 0.3, 1.0, 1.0)],
            extra={
                "PADBACK": ("pill", 0.19, 0.2, 0.022, 0.05),
                "PADFORWARD": ("pill", 0.81, 0.2, 0.022, 0.05),
                "PADSOCIAL": ("dot", 0.19, 0.82, 0.011),
                "PADSYSTEM": ("dot", 0.81, 0.82, 0.011),
            },
        ),
    ),
    "8bitdo": dict(
        name="8BitDo Pro 2",
        aspect=1.6,
        body=[
            ("rr", 0.1, 0.12, 0.9, 0.62, 0.1),
            ("el", 0.08, 0.3, 0.34, 0.97),
            ("el", 0.66, 0.3, 0.92, 0.97),
            ("rr", 0.24, 0.4, 0.76, 0.74, 0.06),
        ],
        parts=[],
        deco=[],
        buttons={
            "PADDPAD": ("dpad", 0.255, 0.33, 0.085),
            "PADFACE": ("face", 0.745, 0.33, 0.034),
            "PADLSTICK": ("stick", 0.37, 0.6, 0.048),
            "PADRSTICK": ("stick", 0.63, 0.6, 0.048),
            "PADBACK": ("pill", 0.435, 0.33, 0.032, 0.03),
            "PADFORWARD": ("pill", 0.565, 0.33, 0.032, 0.03),
            "PADSOCIAL": ("dot", 0.5, 0.45, 0.014),
            "PADSYSTEM": ("dot", 0.5, 0.22, 0.016),
            "PADLTRIGGER": ("trigger", 0.22, 0.09, 0.13, 0.1),
            "PADRTRIGGER": ("trigger", 0.78, 0.09, 0.13, 0.1),
            "PADLSHOULDER": ("bumper", 0.22, 0.13, 0.17, 0.05),
            "PADRSHOULDER": ("bumper", 0.78, 0.13, 0.17, 0.05),
        },
    ),
    "generic": dict(
        name="Generic gamepad",
        aspect=1.65,
        body=[
            ("rr", 0.08, 0.12, 0.92, 0.6, 0.12),
            ("el", 0.05, 0.28, 0.33, 0.97),
            ("el", 0.67, 0.28, 0.95, 0.97),
            ("rr", 0.26, 0.4, 0.74, 0.76, 0.07),
        ],
        parts=[],
        deco=[],
        buttons={
            "PADLSTICK": ("stick", 0.24, 0.34, 0.048),
            "PADDPAD": ("dpad", 0.37, 0.6, 0.075),
            "PADFACE": ("face", 0.75, 0.34, 0.032),
            "PADRSTICK": ("stick", 0.63, 0.6, 0.048),
            "PADBACK": ("pill", 0.42, 0.33, 0.03, 0.03),
            "PADFORWARD": ("pill", 0.58, 0.33, 0.03, 0.03),
            "PADSYSTEM": ("dot", 0.5, 0.22, 0.018),
            "PADLTRIGGER": ("trigger", 0.22, 0.09, 0.13, 0.1),
            "PADRTRIGGER": ("trigger", 0.78, 0.09, 0.13, 0.1),
            "PADLSHOULDER": ("bumper", 0.22, 0.13, 0.17, 0.05),
            "PADRSHOULDER": ("bumper", 0.78, 0.13, 0.17, 0.05),
        },
    ),
}


def draw(layout, stroke):
    """Returns (RGBA drawing, anchors {binding: {cx, cy, w, h}} in 0..1)."""
    H = round(W / layout["aspect"])
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))

    def box(x0, y0, x1, y1):
        return [x0 * W, y0 * H, x1 * W, y1 * H]

    def silhouette(shapes):
        m = Image.new("L", (W, H), 0)
        d = ImageDraw.Draw(m)
        for kind, x0, y0, x1, y1, *rest in shapes:
            if kind == "rr":
                d.rounded_rectangle(box(x0, y0, x1, y1), radius=rest[0] * W, fill=255)
            else:
                d.ellipse(box(x0, y0, x1, y1), fill=255)
        return m

    def outlined(mask):
        img.paste(LBG, mask=mask)
        img.paste(WHITE, mask=_edge(mask, stroke))

    d = ImageDraw.Draw(img)
    anchors = {}

    def pill(x, y, w, h):
        b = [(x - w / 2) * W, y * H - h / 2 * H, (x + w / 2) * W, y * H + h / 2 * H]
        d.rounded_rectangle(b, radius=min(b[2] - b[0], b[3] - b[1]) / 2, fill=LBG, outline=WHITE, width=stroke)

    def circle(x, y, r, outline, width):
        R = r * W
        d.ellipse([x * W - R, y * H - R, x * W + R, y * H + R], fill=LBG, outline=outline, width=width)

    def anchor(name, x, y, w, h):
        anchors[name] = dict(cx=x, cy=y, w=w, h=h)

    # 1. triggers, half hidden behind the body's top edge
    for name, (kind, *a) in layout["buttons"].items():
        if kind == "trigger":
            x, y, w, h = a
            pill(x, y, w, h)
            anchor(name, x, y, w, h)
    # 2. body, detachable parts, screen and other details
    outlined(silhouette(layout["body"]))
    for part in layout["parts"]:
        outlined(silhouette([part]))
    d = ImageDraw.Draw(img)
    for kind, *a in layout["deco"]:
        if kind == "screen":
            x0, y0, x1, y1 = a
            d.rounded_rectangle(box(x0, y0, x1, y1), radius=0.012 * W, fill=LBG, outline=WHITE, width=stroke)
            i = 0.018
            d.rectangle(
                box(x0 + i, y0 + i * W / H, x1 - i, y1 - i * W / H), outline=WHITE, width=max(2, stroke * 2 // 3)
            )
        elif kind == "pad":
            x, y, w, h = a
            d.rounded_rectangle(box(x - w, y - h, x + w, y + h), radius=0.01 * W, fill=LBG, outline=WHITE, width=stroke)
    # 3. bumpers on top of the edge
    for name, (kind, *a) in layout["buttons"].items():
        if kind == "bumper":
            x, y, w, h = a
            pill(x, y, w, h)
            anchor(name, x, y, w, h)

    thin = max(2, stroke * 2 // 3)
    for name, (kind, *a) in layout["buttons"].items():
        if kind == "stick":
            x, y, r = a
            circle(x, y, r, GREY, thin)
            circle(x, y, r * 0.86, GREY, thin)
            circle(x, y, r * 0.6, WHITE, stroke)
            circle(x, y, r * 0.48, WHITE, stroke)
            anchor(name, x, y, 2 * r, 2 * r * W / H)
        elif kind == "dpad":
            x, y, s = a
            t = s / 3  # arm thickness
            cx, cy = x * W, y * H
            S, T = s / 2 * W, t / 2 * W
            pts = [
                (cx - T, cy - S), (cx + T, cy - S), (cx + T, cy - T), (cx + S, cy - T),
                (cx + S, cy + T), (cx + T, cy + T), (cx + T, cy + S), (cx - T, cy + S),
                (cx - T, cy + T), (cx - S, cy + T), (cx - S, cy - T), (cx - T, cy - T),
            ]  # fmt: skip
            d.polygon(pts, fill=LBG, outline=WHITE, width=stroke)
            anchor(name, x, y, s, s * W / H)
        elif kind == "face":
            x, y, r = a
            gap = r * 2.15
            for b, (dx, dy) in {"PAD1": (0, 1), "PAD2": (1, 0), "PAD3": (-1, 0), "PAD4": (0, -1)}.items():
                bx, by = x + dx * gap, y + dy * gap * W / H
                circle(bx, by, r, WHITE, stroke)
                anchor(b, bx, by, 2 * r, 2 * r * W / H)
        elif kind == "pill":
            x, y, w, h = a
            pill(x, y, w, h)
            anchor(name, x, y, w, h)
        elif kind == "dot":
            x, y, r = a
            circle(x, y, r, WHITE, stroke)
            anchor(name, x, y, 2 * r, 2 * r * W / H)
    return img, anchors


def silhouette_ok(img):
    """True when the drawing has a single, non-empty body (used by tests)."""
    a = img.getchannel("A")
    return a.getbbox() is not None and ImageChops.invert(a).getbbox() is not None
