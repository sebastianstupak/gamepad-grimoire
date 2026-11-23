"""Restyle detailed controller SVGs (AL2009man Gamepad-Asset-Pack, MIT) into the
DeckSetup look (the hand-made Steam Deck drawing in tools/make_diagram.py).

Keeps each part's real geometry, but drops text/icons/logos/LEDs/gradients and the
source's own outline layers, repaints every part from one palette by role, uses one
stroke weight for all controllers, redraws sticks / guide buttons / cross D-pads as
shared primitives, and measures every input -> anchors JSON keyed by WoW binding names.

  python restyle.py <assets_dir> <out_dir>
"""
import copy, io, json, os, re, sys
import xml.etree.ElementTree as ET
import resvg_py
from PIL import Image

SVG = "http://www.w3.org/2000/svg"
INK = "http://www.inkscape.org/namespaces/inkscape"
LBL = "{%s}label" % INK
for p, u in [("", SVG), ("inkscape", INK), ("xlink", "http://www.w3.org/1999/xlink"),
             ("sodipodi", "http://sodipodi.sourceforge.net/DTD/sodipodi-0.dtd")]:
    ET.register_namespace(p, u)
Q = lambda t: "{%s}%s" % (SVG, t)

OUT_W = 1000  # every controller is normalised to this width, so strokes match
# The Deck drawing is 512 px wide; strokes there are 1.0-2.0 px -> x2 here.

# ---- palette: taken from make_diagram.py ------------------------------------------
PAL = {
    "body":     dict(fill="url(#bodygrad)", stroke="#5c606c", sw=3.6),
    "body2":    dict(fill="#232428", stroke="#5c606c", sw=2.0),
    "grip":     dict(fill="#26272c", stroke="#464952", sw=2.2),
    "shoulder": dict(fill="#3e414a", stroke="#626672", sw=2.4),
    "bumper":   dict(fill="#34373f", stroke="#626672", sw=2.4),
    "button":   dict(fill="#1e1f23", stroke="#626672", sw=2.0),
    "pad":      dict(fill="#282a30", stroke="#565a64", sw=2.4),
    "screen":   dict(fill="#090a0d", stroke="#3c404a", sw=2.4),
    "hidden":   dict(fill="#e0a850", fill_opacity=0.3, stroke="#e0a850", sw=3.2, dash="6 5"),
    "face_down":  dict(fill="#121316", stroke="#5fd35f", sw=2.4),
    "face_right": dict(fill="#121316", stroke="#ff5f5f", sw=2.4),
    "face_left":  dict(fill="#121316", stroke="#5fa8ff", sw=2.4),
    "face_up":    dict(fill="#121316", stroke="#ffd34f", sw=2.4),
}
BG = "#1b1d22"

# Valve's official Steam Deck line drawings: white strokes on dark, thick outer edge,
# thin part lines, grey stick surrounds, no fills (parts filled with the background so
# overlapping parts hide each other).
LBG, WHITE, GREY = "#2b2c33", "#f4f4f6", "#8e9098"
_thin = dict(fill=LBG, stroke=WHITE, sw=1.5)
PAL_LINE = {r: dict(_thin) for r in PAL}
PAL_LINE.update(body=dict(fill=LBG, stroke=WHITE, sw=1.5), body2=dict(fill=LBG, stroke=WHITE, sw=1.5),
                grip=dict(fill=LBG, stroke=WHITE, sw=1.5), screen=dict(fill=LBG, stroke=WHITE, sw=1.5),
                hidden=dict(fill="none", stroke="#e0a850", sw=2.0, dash="6 5"))
STYLE = "filled"
FACE_ROLE = {"PAD1": "face_down", "PAD2": "face_right", "PAD3": "face_left", "PAD4": "face_up"}

DROP_RE = re.compile(r"(^|\b)(text|icon|symbol|symbols|logo|led|blend|r\d text|l\d text|"
                     r"share text|options text|usb-c|face button dot|"
                     r"with led|without led|mute with led|mute without led|front d-pad|outline below|secondary d-pad)\b", re.I)
OUTLINE_RE = re.compile(r"^(main |secondary |trigger |screen |controller )?outl?i?ne?\b|^outlne", re.I)

# ---- per-controller config ----------------------------------------------------------
#  roles:   (label regex, role) - nearest labelled ancestor first; role "drop" removes
#  parts:   WoW binding name -> element id (measured -> anchors)
#  sticks / guide / cross: binding names redrawn as shared primitives (originals removed)
CONTROLLERS = {
    "steamdeck": dict(
        src="al_steamdeck_overlay.svg", name="Steam Deck",
        roles=[(r"Grip", "grip"), (r"Trigger", "shoulder"), (r"R1 Button|L1 Button", "bumper"),
               (r"Back Buttons|^[LR][45]$", "hidden"), (r"Touchscreen|Panel|Screen", "screen"),
               (r"Pad$|Trackpads", "pad"), (r"Speaker", "button"),
               (r"Face Buttons|Button$|Quick Access|View|Menu|D-PAD", "button"), (r"Body", "body")],
        parts={"PADLTRIGGER": "path1329", "PADRTRIGGER": "path5612", "PADLSHOULDER": "path1327",
               "PADRSHOULDER": "path1200", "PAD1": "g26991", "PAD2": "g26987", "PAD3": "g26995",
               "PAD4": "g23695", "PADDPAD": "path337-4", "PADLSTICK": "g37885", "PADRSTICK": "g37879",
               "PADBACK": "g29482", "PADFORWARD": "g29475", "PADSYSTEM": "g23310", "QAM": "g23314",
               "LPAD": "g31078", "RPAD": "g31084", "SCREEN": "g21714",
               "L4": "g11824", "L5": "g11828", "R4": "g11832", "R5": "g11836"},
        sticks=["PADLSTICK", "PADRSTICK"], stick_scale=1.3),
    "xbox": dict(
        src="al_xboxseries_white.svg", name="Xbox Series",
        roles=[(r"Trigger", "shoulder"), (r"Pair Button", "drop"), (r"Bumpers", "bumper"),
               (r"Analog Stick Outline Body", "drop"), (r"D-PAD|Face Buttons|Button", "button"), (r"Body", "body")],
        parts={"PADLTRIGGER": "path17344", "PADRTRIGGER": "g27170", "PAD1": "g13159", "PAD2": "g13164",
               "PAD3": "g13174", "PAD4": "g13169", "PADDPAD": "g4338", "PADLSTICK": "g95973",
               "PADRSTICK": "g4173", "PADBACK": "g8820", "PADFORWARD": "g8857", "PADSOCIAL": "g1033",
               "PADSYSTEM": "g13092", "PADSHOULDERS": "g1756"},
        sticks=["PADLSTICK", "PADRSTICK"], stick_scale=1.18, guide="PADSYSTEM", cross="PADDPAD"),
    "dualsense": dict(
        src="al_dualsense.svg", name="DualSense",
        roles=[(r"Trigger", "shoulder"), (r"^R1$|^L1$|Bumpers", "bumper"), (r"Joystick Zone", "drop"),
               (r"D-PAD|Face Button|Create|Option|Mute|PS Button", "button"),
               (r"Color Body #2", "body2"), (r"Body", "body")],
        keep_outline=[r"Mute"],
        parts={"PADLTRIGGER": "g51182-0", "PADRTRIGGER": "g51166-6", "PADLSHOULDER": "g1288",
               "PADRSHOULDER": "g59279", "PAD1": "g50495", "PAD2": "g50489", "PAD3": "g50501",
               "PAD4": "g50483", "PADDUP": "g50669", "PADDLEFT": "g50644", "PADDDOWN": "g50681",
               "PADDRIGHT": "g50675", "PADLSTICK": "g5800", "PADRSTICK": "g5696",
               "PADSOCIAL": "g50533", "PADFORWARD": "g50517", "PADSYSTEM": "path1961", "MUTE": "g50737"},
        sticks=["PADLSTICK", "PADRSTICK"], stick_scale=1.12, guide="PADSYSTEM"),
    "switchpro": dict(
        src="al_switchpro.svg", name="Switch Pro",
        roles=[(r"Trigger", "shoulder"), (r"Bumper", "bumper"), (r"Shoulder", "shoulder"), (r"Grip", "grip"),
               (r"Analog Stick Outline Body", "drop"),
               (r"Face Buttons|Button|Home|Capture|Minus|Plus|D-PAD", "button"), (r"Body|Color", "body")],
        parts={"PADLTRIGGER": "path8519", "PADRTRIGGER": "path1458", "PADLSHOULDER": "path2365",
               "PADRSHOULDER": "path5183", "PAD1": "g10417", "PAD2": "g10422", "PAD3": "g10432",
               "PAD4": "g10427", "PADDPAD": "g1435", "PADLSTICK": "g2489", "PADRSTICK": "g2495",
               "PADBACK": "g1445", "PADFORWARD": "g1440", "PADSYSTEM": "g1458", "PADSOCIAL": "g1451"},
        sticks=["PADLSTICK", "PADRSTICK"], stick_scale=1.25, guide="PADSYSTEM"),
}


def label(e):
    return e.get(LBL) or ""


def parent_map(root):
    return {c: p for p in root.iter() for c in p}


def labels_up(e, pm):
    out = []
    while e is not None:
        if label(e):
            out.append(label(e))
        e = pm.get(e)
    return out


def role_for(e, pm, roles):
    for lab in labels_up(e, pm):
        for rx, role in roles:
            if re.search(rx, lab):
                return role
    return "body"


def style_str(role, k, hidden=False):
    s = (PAL_LINE if STYLE == "lineart" else PAL)[role]
    st = ["fill:%s" % s["fill"], "stroke:%s" % s["stroke"], "stroke-width:%.4f" % (s["sw"] * k),
          "stroke-linejoin:round", "fill-opacity:%s" % s.get("fill_opacity", 1), "stroke-opacity:1"]
    if s.get("dash"):
        st.append("stroke-dasharray:%s" % " ".join("%.3f" % (float(x) * k) for x in s["dash"].split()))
    if hidden:
        st.append("display:none")
    return ";".join(st)


def tf_scale(t):
    """Uniform scale factor of an SVG transform attribute."""
    import math
    sc = 1.0
    for name, args in re.findall(r"(matrix|scale|rotate|translate|skewX|skewY)\s*\(([^)]*)\)", t or ""):
        v = [float(x) for x in re.split(r"[ ,]+", args.strip()) if x]
        if name == "matrix":
            sc *= math.sqrt(abs(v[0] * v[3] - v[1] * v[2]))
        elif name == "scale":
            sc *= math.sqrt(abs(v[0] * (v[1] if len(v) > 1 else v[0])))
    return sc


def cum_scale(e, pm):
    sc = 1.0
    while e is not None:
        sc *= tf_scale(e.get("transform") or e.get("gradientTransform") and "")
        e = pm.get(e)
    return sc or 1.0


SHAPES = {"path", "rect", "circle", "ellipse", "polygon", "polyline", "line"}


def restyle(root, cfg, k, face_ids, remove_ids):
    pm = parent_map(root)
    keep_ol = [re.compile(x) for x in cfg.get("keep_outline", [])]
    drop = []
    for e in root.iter():
        tag = e.tag.split("}")[-1]
        if e.get("id") in remove_ids or tag in ("text", "tspan", "image"):
            drop.append(e); continue
        lab = label(e)
        if lab and DROP_RE.search(lab):
            drop.append(e); continue
        if lab and OUTLINE_RE.search(lab):
            ups = labels_up(pm.get(e), pm)
            if not any(rx.search(u) for rx in keep_ol for u in ups):
                drop.append(e); continue
        if tag in SHAPES:
            own = (e.get("style") or "").replace(" ", "")
            was_hidden = "display:none" in own or e.get("display") == "none"
            role = role_for(e, pm, cfg["roles"])
            a = e
            while a is not None:                         # face buttons get coloured rims
                if a.get("id") in face_ids:
                    role = face_ids[a.get("id")]; break
                a = pm.get(a)
            if role == "drop":
                drop.append(e); continue
            for at in ("fill", "stroke", "stroke-width", "opacity", "filter", "fill-opacity", "stroke-opacity"):
                e.attrib.pop(at, None)
            e.set("style", style_str(role, k / cum_scale(e, pm), was_hidden))
        elif tag == "g":
            st = (e.get("style") or "").replace(" ", "")
            e.attrib.pop("filter", None)
            if "display:none" in st:
                e.set("style", "display:none")
            else:
                e.attrib.pop("style", None)
    for e in drop:
        p = pm.get(e)
        if p is not None and e in list(p):
            p.remove(e)


def render(svg_bytes, width):
    r = ET.fromstring(svg_bytes)
    vb = [float(x) for x in re.split(r"[ ,]+", r.get("viewBox").strip())]
    r.set("width", str(width)); r.set("height", str(round(width * vb[3] / vb[2])))
    png = bytes(resvg_py.svg_to_bytes(svg_string=ET.tostring(r).decode("utf-8")))
    return Image.open(io.BytesIO(png)).convert("RGBA")


def isolate(root, target_id):
    r = copy.deepcopy(root)
    pm = parent_map(r)
    t = next((e for e in r.iter() if e.get("id") == target_id), None)
    if t is None:
        return None
    anc, a = set(), t
    while a is not None:
        anc.add(a)
        # parts on layers hidden in the source (e.g. back buttons) must still be measured
        st = (a.get("style") or "").replace(" ", "").replace("display:none", "display:inline")
        if st:
            a.set("style", st)
        if a.get("display") == "none":
            a.set("display", "inline")
        a = pm.get(a)
    for e in list(r.iter()):
        p = pm.get(e)
        if p is not None and p in anc and p is not t and e not in anc and e.tag.split("}")[-1] not in ("defs", "namedview", "metadata"):
            e.set("style", ";".join(x for x in ((e.get("style") or "").strip(" ;"), "display:none") if x))
    return r


def measure(root, ids, vb):
    W = 2000
    vx, vy, vw, vh = vb
    boxes = {}
    for key, eid in ids.items():
        r = isolate(root, eid)
        if r is None:
            print("   ! missing", key, eid); continue
        box = render(ET.tostring(r), W).getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox()
        if not box:
            print("   ! empty", key, eid); continue
        s = vw / W
        boxes[key] = (box[0] * s + vx, box[1] * s + vy, box[2] * s + vx, box[3] * s + vy)
    return boxes


def el(parent, tag, **at):
    e = ET.SubElement(parent, Q(tag))
    for a, v in at.items():
        e.set(a.replace("_", "-"), str(v))
    return e


def circle(g, cx, cy, r, fill, stroke=None, sw=0, k=1):
    st = "fill:%s;" % fill + ("stroke:%s;stroke-width:%.4f" % (stroke, sw * k) if stroke else "stroke:none")
    el(g, "circle", cx="%.3f" % cx, cy="%.3f" % cy, r="%.3f" % r, style=st)


def add_primitives(root, cfg, boxes, k):
    g = el(root, "g", id="primitives")
    if STYLE == "lineart":
        W = "fill:%s;stroke:%s;stroke-width:%%.4f" % (LBG, WHITE)
        for key in cfg.get("sticks", []):      # Valve: thin grey surround, two white rings
            x0, y0, x1, y1 = boxes[key]
            cx, cy, R = (x0 + x1) / 2, (y0 + y1) / 2, max(x1 - x0, y1 - y0) / 2 * cfg.get("stick_scale", 1.2)
            circle(g, cx, cy, R, LBG, GREY, 1.2, k)
            circle(g, cx, cy, R * 0.86, LBG, GREY, 1.0, k)
            circle(g, cx, cy, R * 0.6, LBG, WHITE, 1.5, k)
            circle(g, cx, cy, R * 0.48, LBG, WHITE, 1.5, k)
        for b in FACE_ROLE:
            if b in boxes:
                x0, y0, x1, y1 = boxes[b]
                circle(g, (x0 + x1) / 2, (y0 + y1) / 2, min(x1 - x0, y1 - y0) / 2 * 0.96, LBG, WHITE, 1.5, k)
        if cfg.get("guide"):
            x0, y0, x1, y1 = boxes[cfg["guide"]]
            circle(g, (x0 + x1) / 2, (y0 + y1) / 2, max(x1 - x0, y1 - y0) / 2, LBG, WHITE, 1.5, k)
        if cfg.get("cross"):
            x0, y0, x1, y1 = boxes[cfg["cross"]]
            cx, cy, S = (x0 + x1) / 2, (y0 + y1) / 2, min(x1 - x0, y1 - y0) / 2 * 0.92
            a = S * 0.34
            pts = [(-a, -S), (a, -S), (a, -a), (S, -a), (S, a), (a, a), (a, S), (-a, S), (-a, a), (-S, a), (-S, -a), (-a, -a)]
            el(g, "polygon", points=" ".join("%.3f,%.3f" % (cx + x, cy + y) for x, y in pts),
               style=W % (1.5 * k) + ";stroke-linejoin:round")
        return
    for key in cfg.get("sticks", []):          # Deck look: dark well, light gasket, dark concave cap
        x0, y0, x1, y1 = boxes[key]
        cx, cy, R = (x0 + x1) / 2, (y0 + y1) / 2, max(x1 - x0, y1 - y0) / 2 * cfg.get("stick_scale", 1.2)
        circle(g, cx, cy, R, "#161719", "#464a54", 2.4, k)
        circle(g, cx, cy, R * 0.816, "#c4c7ce")
        circle(g, cx, cy, R * 0.658, "#222328", "#50545e", 2.0, k)
        circle(g, cx - R * 0.05, cy - R * 0.08, R * 0.37, "#2c2e34")
    for b, role in FACE_ROLE.items():          # Deck look: dark caps with coloured rims
        if b in boxes:
            x0, y0, x1, y1 = boxes[b]
            p = PAL[role]
            circle(g, (x0 + x1) / 2, (y0 + y1) / 2, min(x1 - x0, y1 - y0) / 2 * 0.96, p["fill"], p["stroke"], p["sw"], k)
    if cfg.get("guide"):                       # brand logo -> plain round button with a dot
        x0, y0, x1, y1 = boxes[cfg["guide"]]
        cx, cy, R = (x0 + x1) / 2, (y0 + y1) / 2, max(x1 - x0, y1 - y0) / 2
        circle(g, cx, cy, R, "#1e1f23", "#626672", 2.0, k)
        circle(g, cx, cy, R * 0.32, "#aaaeba")
    if cfg.get("cross"):                       # plus-shaped D-pad like the Deck's
        x0, y0, x1, y1 = boxes[cfg["cross"]]
        cx, cy, S = (x0 + x1) / 2, (y0 + y1) / 2, min(x1 - x0, y1 - y0) / 2 * 0.92
        a = S * 0.36
        st = "fill:#1e1f23;stroke:#626672;stroke-width:%.4f;stroke-linejoin:round" % (2.4 * k)
        pts = [(-a, -S), (a, -S), (a, -a), (S, -a), (S, a), (a, a), (a, S), (-a, S), (-a, a), (-S, a), (-S, -a), (-a, -a)]
        el(g, "polygon", points=" ".join("%.3f,%.3f" % (cx + x, cy + y) for x, y in pts), style=st)


def add_effects(root, vb, k):
    vx, vy, vw, vh = vb
    defs = root.find(Q("defs"))
    if defs is None:
        defs = ET.Element(Q("defs")); root.insert(0, defs)
    lg = el(defs, "linearGradient", id="bodygrad", gradientUnits="userSpaceOnUse",
            x1=vx, y1=vy + vh * 0.12, x2=vx, y2=vy + vh)
    el(lg, "stop", offset=0, style="stop-color:#323439")
    el(lg, "stop", offset=1, style="stop-color:#24262b")
    f = el(defs, "filter", id="shadow", x="-10%", y="-10%", width="120%", height="125%")
    el(f, "feDropShadow", dx=0, dy="%.3f" % (6 * k), stdDeviation="%.3f" % (8 * k),
       style="flood-color:#000000;flood-opacity:0.6")
    # wrap all drawable content in one group carrying the shadow
    wrap = ET.Element(Q("g")); wrap.set("id", "art")
    if STYLE != "lineart":
        wrap.set("filter", "url(#shadow)")
    for c in list(root):
        if c.tag.split("}")[-1] not in ("defs", "namedview", "metadata"):
            root.remove(c); wrap.append(c)
    root.append(wrap)
    return wrap


def add_silhouette(root, art, k, width=1.9):
    """Valve style: thick line only on the outer edge. A white copy of every shape,
    stroked wide, goes underneath; the normal (background-filled) shapes cover all
    of it except a band around the outside."""
    under = copy.deepcopy(art)
    under.set("id", "silhouette")
    pm = parent_map(under)
    for e in list(under.iter()):
        if e.tag.split("}")[-1] in SHAPES:
            st = e.get("style") or ""
            if "dasharray" in st or "fill:none" in st:
                pm[e].remove(e); continue
            hid = ";display:none" if "display:none" in st else ""
            e.set("style", "fill:%s;stroke:%s;stroke-width:%.4f;stroke-linejoin:round%s"
                  % (WHITE, WHITE, 2 * width * k / cum_scale(e, pm), hid))
    root.insert(list(root).index(art), under)


def main(assets, outdir):
    os.makedirs(outdir, exist_ok=True)
    allanchors = {}
    for key, cfg in CONTROLLERS.items():
        tree = ET.parse(os.path.join(assets, cfg["src"]))
        root = tree.getroot()
        vb = [float(x) for x in re.split(r"[ ,]+", root.get("viewBox").strip())]
        k = vb[2] / OUT_W
        boxes = measure(root, cfg["parts"], vb)
        face_ids = {cfg["parts"][b]: r for b, r in FACE_ROLE.items() if b in cfg["parts"]}
        replaced = [b for b in FACE_ROLE if b in cfg["parts"]] + cfg.get("sticks", []) + [x for x in (cfg.get("guide"), cfg.get("cross")) if x]
        restyle(root, cfg, k, face_ids, {cfg["parts"][b] for b in replaced})
        art = add_effects(root, vb, k)
        if STYLE == "lineart":
            add_silhouette(root, art, k)
        add_primitives(art, cfg, boxes, k)
        root.set("width", str(OUT_W)); root.set("height", str(round(OUT_W * vb[3] / vb[2])))
        data = ET.tostring(root)
        open(os.path.join(outdir, key + ".svg"), "wb").write(data)
        img = render(data, OUT_W)
        img.save(os.path.join(outdir, key + ".png"))
        vx, vy, vw, vh = vb
        allanchors[key] = dict(name=cfg["name"], source=cfg["src"], aspect=round(vh / vw, 4), anchors={
            b: dict(cx=round(((x0 + x1) / 2 - vx) / vw, 4), cy=round(((y0 + y1) / 2 - vy) / vh, 4),
                    w=round((x1 - x0) / vw, 4), h=round((y1 - y0) / vh, 4))
            for b, (x0, y0, x1, y1) in boxes.items()})
        print("%-10s %d anchors" % (key, len(boxes)))
    json.dump(allanchors, open(os.path.join(outdir, "anchors.json"), "w"), indent=1)


if __name__ == "__main__":
    if "--style" in sys.argv:
        i = sys.argv.index("--style"); STYLE = sys.argv[i + 1]; del sys.argv[i:i + 2]
    main(sys.argv[1], sys.argv[2])
