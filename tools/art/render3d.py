"""Renders controller pictures from 3D models (npm run render; needs Blender).

Models are not kept in the repository (some are large, all have their own
licences); they are downloaded into tools/art/models/ (git-ignored) from the URL
in MODELS, or placed there by hand. The renders are committed to
tools/art/renders/ with their licence, and build.py turns them into textures.

python tools/art/render3d.py [ids...] [--blender PATH] [--width 2000]
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
MODELS_DIR = os.path.join(HERE, "models")
RENDERS = os.path.join(HERE, "renders")

# id -> where the model comes from, its licence, and how it sits in its file.
# forward: the axis the front faces; up: the axis pointing to the shoulders.
MODELS = {
    "steamdeck": dict(
        name="Steam Deck",
        file="steamdeck_stl_20220202.stl",
        url="https://gitlab.steamos.cloud/api/v4/projects/700/repository/files/steamdeck_stl_20220202.stl/raw?ref=master",
        source="https://gitlab.steamos.cloud/SteamDeck/hardware",
        author="Valve Corporation",
        license="CC BY-NC-SA 4.0",
        license_url="https://creativecommons.org/licenses/by-nc-sa/4.0/",
        forward="+z",
        up="+y",
        tilt_deg=18,
        # anchors: (cx, cy, w, h) as fractions of the render; the back is seen from
        # behind (turned over), so R4 / R5 are on the left
        front={
            "PADDPAD": (0.070, 0.243, 0.075, 0.175),
            "PADLSTICK": (0.165, 0.299, 0.060, 0.140),
            "PADRSTICK": (0.835, 0.299, 0.060, 0.140),
            "PAD1": (0.930, 0.311, 0.030, 0.070),
            "PAD2": (0.957, 0.241, 0.030, 0.070),
            "PAD3": (0.900, 0.241, 0.030, 0.070),
            "PAD4": (0.930, 0.171, 0.030, 0.070),
            "PADBACK": (0.125, 0.159, 0.030, 0.033),
            "PADFORWARD": (0.875, 0.159, 0.030, 0.033),
            "LPAD": (0.157, 0.526, 0.105, 0.234),
            "RPAD": (0.843, 0.526, 0.105, 0.234),
            "PADSYSTEM": (0.181, 0.706, 0.055, 0.051),
            "QAM": (0.819, 0.706, 0.055, 0.051),
            "SCREEN": (0.500, 0.533, 0.565, 0.771),
            "PADLSHOULDER": (0.095, 0.089, 0.070, 0.028),
            "PADLTRIGGER": (0.150, 0.072, 0.060, 0.023),
            "PADRSHOULDER": (0.905, 0.089, 0.070, 0.028),
            "PADRTRIGGER": (0.850, 0.072, 0.060, 0.023),
        },
        back={
            "PADPADDLE1": (0.143, 0.516, 0.070, 0.163),
            "PADPADDLE2": (0.143, 0.686, 0.070, 0.163),
            "PADPADDLE3": (0.857, 0.516, 0.070, 0.163),
            "PADPADDLE4": (0.857, 0.686, 0.070, 0.163),
            "PADRTRIGGER": (0.070, 0.186, 0.100, 0.209),
            "PADRSHOULDER": (0.100, 0.098, 0.090, 0.047),
            "PADLTRIGGER": (0.930, 0.186, 0.100, 0.209),
            "PADLSHOULDER": (0.900, 0.098, 0.090, 0.047),
        },
    ),
    "steamcontroller": dict(
        name="Steam Controller",
        file="SC_solid_stl_20260429.stl",
        url="https://gitlab.steamos.cloud/api/v4/projects/1464/repository/files/sc_solid_stl_20260429.stl/raw?ref=main",
        source="https://gitlab.steamos.cloud/SteamHardware/SteamController",
        author="Valve Corporation",
        license="CC BY-NC-SA 4.0",
        license_url="https://creativecommons.org/licenses/by-nc-sa/4.0/",
        forward="+y",
        up="-z",
        tilt_deg=18,
        front={
            "PADDPAD": (0.170, 0.300, 0.110, 0.185),
            "PAD1": (0.796, 0.416, 0.050, 0.063),
            "PAD2": (0.861, 0.339, 0.050, 0.063),
            "PAD3": (0.732, 0.339, 0.050, 0.063),
            "PAD4": (0.796, 0.267, 0.050, 0.063),
            "PADLSTICK": (0.335, 0.421, 0.080, 0.100),
            "PADRSTICK": (0.625, 0.421, 0.080, 0.100),
            "LPAD": (0.300, 0.615, 0.150, 0.195),
            "RPAD": (0.690, 0.615, 0.150, 0.195),
            "PADSYSTEM": (0.500, 0.325, 0.050, 0.063),
            "PADBACK": (0.320, 0.255, 0.045, 0.032),
            "PADFORWARD": (0.675, 0.255, 0.045, 0.032),
            "QAM": (0.485, 0.630, 0.040, 0.030),
            "PADLSHOULDER": (0.185, 0.120, 0.110, 0.045),
            "PADLTRIGGER": (0.195, 0.075, 0.090, 0.040),
            "PADRSHOULDER": (0.815, 0.120, 0.110, 0.045),
            "PADRTRIGGER": (0.805, 0.075, 0.090, 0.040),
        },
        back={
            "PADPADDLE1": (0.225, 0.610, 0.090, 0.130),
            "PADPADDLE2": (0.195, 0.775, 0.090, 0.130),
            "PADPADDLE3": (0.775, 0.610, 0.090, 0.130),
            "PADPADDLE4": (0.805, 0.775, 0.090, 0.130),
            "PADRTRIGGER": (0.190, 0.130, 0.130, 0.130),
            "PADRSHOULDER": (0.185, 0.080, 0.110, 0.045),
            "PADLTRIGGER": (0.810, 0.130, 0.130, 0.130),
            "PADLSHOULDER": (0.815, 0.080, 0.110, 0.045),
        },
    ),
    "generic": dict(
        name="Generic gamepad",
        params="generic.json",
        builder=True,
        author="Gamepad Grimoire",
        license="MIT",
        license_url="https://opensource.org/licenses/MIT",
        source="tools/art/model.py",
        forward="+z",
        up="+y",
        tilt_deg=18,
        front={
            "PADLSTICK": (0.3007, 0.4096, 0.1494, 0.1626),
            "PADRSTICK": (0.5872, 0.6265, 0.1494, 0.1626),
            "PADDPAD": (0.4128, 0.6265, 0.1868, 0.2033),
            "PAD1": (0.7491, 0.5045, 0.0872, 0.0949),
            "PAD2": (0.8238, 0.4096, 0.0872, 0.0949),
            "PAD3": (0.6743, 0.4096, 0.0872, 0.0949),
            "PAD4": (0.7491, 0.3148, 0.0872, 0.0949),
            "PADBACK": (0.4128, 0.3148, 0.0623, 0.0678),
            "PADFORWARD": (0.5872, 0.3148, 0.0623, 0.0678),
            "PADLSHOULDER": (0.1762, 0.1995, 0.2491, 0.0745),
            "PADRSHOULDER": (0.8238, 0.1995, 0.2491, 0.0745),
            "PADLTRIGGER": (0.1388, 0.1657, 0.0872, 0.0949),
            "PADRTRIGGER": (0.8612, 0.1657, 0.0872, 0.0949),
        },
        back={
            "PADLSHOULDER": (0.8238, 0.1380, 0.2491, 0.0813),
            "PADRSHOULDER": (0.1762, 0.1380, 0.2491, 0.0813),
            "PADLTRIGGER": (0.8611, 0.1041, 0.0747, 0.0813),
            "PADRTRIGGER": (0.1388, 0.1041, 0.0747, 0.0813),
        },
    ),
    "rogally": dict(
        name="ROG Ally",
        params="rogally.json",
        builder=True,
        author="Gamepad Grimoire",
        license="MIT",
        license_url="https://opensource.org/licenses/MIT",
        source="tools/art/model.py",
        forward="+z",
        up="+y",
        tilt_deg=18,
        front={
            "PADLSTICK": (0.1403, 0.3669, 0.0866, 0.1632),
            "PADRSTICK": (0.8597, 0.6432, 0.0866, 0.1632),
            "PADDPAD": (0.1403, 0.6432, 0.0999, 0.1883),
            "PAD1": (0.8597, 0.4548, 0.0533, 0.1004),
            "PAD2": (0.8997, 0.3669, 0.0533, 0.1004),
            "PAD3": (0.8198, 0.3669, 0.0533, 0.1004),
            "PAD4": (0.8597, 0.2791, 0.0533, 0.1004),
            "PADBACK": (0.3135, 0.2163, 0.0333, 0.0628),
            "PADFORWARD": (0.6865, 0.2163, 0.0333, 0.0628),
            "PADSYSTEM": (0.8997, 0.2288, 0.0333, 0.0628),
            "PADSOCIAL": (0.1003, 0.2288, 0.0333, 0.0628),
            "PADLSHOULDER": (0.1136, 0.1912, 0.1466, 0.0816),
            "PADRSHOULDER": (0.8864, 0.1912, 0.1466, 0.0816),
            "PADLTRIGGER": (0.0603, 0.2288, 0.0466, 0.0879),
            "PADRTRIGGER": (0.9397, 0.2288, 0.0466, 0.0879),
        },
        back={
            "PADPADDLE3": (0.8198, 0.6980, 0.0466, 0.0879),
            "PADPADDLE1": (0.1802, 0.6980, 0.0466, 0.0879),
            "PADLSHOULDER": (0.8864, 0.1330, 0.1466, 0.0753),
            "PADRSHOULDER": (0.1136, 0.1330, 0.1466, 0.0753),
            "PADLTRIGGER": (0.9397, 0.1706, 0.0400, 0.0753),
            "PADRTRIGGER": (0.0603, 0.1706, 0.0400, 0.0753),
        },
    ),
    "legiongo": dict(
        name="Lenovo Legion Go",
        params="legiongo.json",
        builder=True,
        author="Gamepad Grimoire",
        license="MIT",
        license_url="https://opensource.org/licenses/MIT",
        source="tools/art/model.py",
        forward="+z",
        up="+y",
        tilt_deg=18,
        front={
            "PADLSTICK": (0.1399, 0.3747, 0.0884, 0.1669),
            "PADRSTICK": (0.8601, 0.6370, 0.0884, 0.1669),
            "PADDPAD": (0.1399, 0.6489, 0.1011, 0.1908),
            "PAD1": (0.8601, 0.4701, 0.0537, 0.1014),
            "PAD2": (0.9011, 0.3747, 0.0537, 0.1014),
            "PAD3": (0.8190, 0.3747, 0.0537, 0.1014),
            "PAD4": (0.8601, 0.2793, 0.0537, 0.1014),
            "PADBACK": (0.3168, 0.2197, 0.0316, 0.0596),
            "PADFORWARD": (0.6832, 0.2197, 0.0316, 0.0596),
            "PADSYSTEM": (0.8980, 0.2316, 0.0316, 0.0596),
            "PADSOCIAL": (0.1020, 0.2316, 0.0316, 0.0596),
            "PADLSHOULDER": (0.1147, 0.1898, 0.1453, 0.0775),
            "PADRSHOULDER": (0.8853, 0.1898, 0.1453, 0.0775),
            "PADLTRIGGER": (0.0641, 0.2316, 0.0442, 0.0835),
            "PADRTRIGGER": (0.9359, 0.2316, 0.0442, 0.0835),
        },
        back={
            "PADPADDLE3": (0.8159, 0.6733, 0.0379, 0.0715),
            "PADPADDLE4": (0.8159, 0.3752, 0.0379, 0.0715),
            "PADPADDLE1": (0.1841, 0.6733, 0.0379, 0.0715),
            "PADPADDLE2": (0.1841, 0.3752, 0.0379, 0.0715),
            "PADLSHOULDER": (0.8853, 0.1308, 0.1453, 0.0715),
            "PADRSHOULDER": (0.1147, 0.1308, 0.1453, 0.0715),
            "PADLTRIGGER": (0.9359, 0.1725, 0.0379, 0.0715),
            "PADRTRIGGER": (0.0641, 0.1725, 0.0379, 0.0715),
        },
    ),
    "msiclaw": dict(
        name="MSI Claw",
        params="msiclaw.json",
        builder=True,
        author="Gamepad Grimoire",
        license="MIT",
        license_url="https://opensource.org/licenses/MIT",
        source="tools/art/model.py",
        forward="+z",
        up="+y",
        tilt_deg=18,
        front={
            "PADLSTICK": (0.1450, 0.3668, 0.0855, 0.1633),
            "PADRSTICK": (0.8550, 0.6432, 0.0855, 0.1633),
            "PADDPAD": (0.1450, 0.6432, 0.0986, 0.1885),
            "PAD1": (0.8550, 0.4547, 0.0526, 0.1005),
            "PAD2": (0.8945, 0.3668, 0.0526, 0.1005),
            "PAD3": (0.8156, 0.3668, 0.0526, 0.1005),
            "PAD4": (0.8550, 0.2788, 0.0526, 0.1005),
            "PADBACK": (0.3159, 0.2160, 0.0329, 0.0628),
            "PADFORWARD": (0.6841, 0.2160, 0.0329, 0.0628),
            "PADSYSTEM": (0.8945, 0.2286, 0.0329, 0.0628),
            "PADSOCIAL": (0.1055, 0.2286, 0.0329, 0.0628),
            "PADLSHOULDER": (0.1154, 0.1909, 0.1446, 0.0817),
            "PADRSHOULDER": (0.8846, 0.1909, 0.1446, 0.0817),
            "PADLTRIGGER": (0.0628, 0.2286, 0.0460, 0.0879),
            "PADRTRIGGER": (0.9372, 0.2286, 0.0460, 0.0879),
        },
        back={
            "PADPADDLE3": (0.8156, 0.6981, 0.0460, 0.0879),
            "PADPADDLE1": (0.1844, 0.6981, 0.0460, 0.0879),
            "PADLSHOULDER": (0.8846, 0.1327, 0.1446, 0.0754),
            "PADRSHOULDER": (0.1154, 0.1327, 0.1446, 0.0754),
            "PADLTRIGGER": (0.9372, 0.1704, 0.0394, 0.0754),
            "PADRTRIGGER": (0.0628, 0.1704, 0.0394, 0.0754),
        },
    ),
    "8bitdo": dict(
        name="8BitDo Pro 2",
        params="8bitdo.json",
        builder=True,
        author="Gamepad Grimoire",
        license="MIT",
        license_url="https://opensource.org/licenses/MIT",
        source="tools/art/model.py",
        forward="+z",
        up="+y",
        tilt_deg=18,
        front={
            "PADLSTICK": (0.3427, 0.6337, 0.1442, 0.1781),
            "PADRSTICK": (0.6573, 0.6337, 0.1442, 0.1781),
            "PADDPAD": (0.2115, 0.3746, 0.1705, 0.2105),
            "PAD1": (0.7885, 0.4879, 0.0852, 0.1053),
            "PAD2": (0.8606, 0.3827, 0.0852, 0.1053),
            "PAD3": (0.7163, 0.3827, 0.0852, 0.1053),
            "PAD4": (0.7885, 0.2774, 0.0852, 0.1053),
            "PADBACK": (0.4213, 0.3584, 0.0590, 0.0729),
            "PADFORWARD": (0.5787, 0.3584, 0.0590, 0.0729),
            "PADSYSTEM": (0.5000, 0.4717, 0.0590, 0.0729),
            "PADLSHOULDER": (0.1722, 0.1964, 0.2360, 0.0810),
            "PADRSHOULDER": (0.8278, 0.1964, 0.2360, 0.0810),
            "PADLTRIGGER": (0.1329, 0.1640, 0.0918, 0.1134),
            "PADRTRIGGER": (0.8671, 0.1640, 0.0918, 0.1134),
        },
        back={
            "PADPADDLE3": (0.7622, 0.7152, 0.0787, 0.0972),
            "PADPADDLE1": (0.2378, 0.7152, 0.0787, 0.0972),
            "PADLSHOULDER": (0.8278, 0.1322, 0.2360, 0.0972),
            "PADRSHOULDER": (0.1722, 0.1322, 0.2360, 0.0972),
            "PADLTRIGGER": (0.8671, 0.0998, 0.0787, 0.0972),
            "PADRTRIGGER": (0.1329, 0.0998, 0.0787, 0.0972),
        },
    ),
}


def find_blender(explicit=None):
    for c in (
        explicit,
        os.environ.get("BLENDER"),
        shutil.which("blender"),
        r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe",
        "/Applications/Blender.app/Contents/MacOS/Blender",
    ):
        if c and os.path.exists(c):
            return c
    raise SystemExit("Blender not found: install it or pass --blender / set BLENDER")


def fetch(cid, m):
    os.makedirs(MODELS_DIR, exist_ok=True)
    path = os.path.join(MODELS_DIR, m["file"])
    if not os.path.exists(path):
        if not m.get("url"):
            raise SystemExit(f"{cid}: put {m['file']} in {MODELS_DIR} (from {m['source']}, {m['license']})")
        print(f"  downloading {m['file']} ({m['license']}, {m['author']})")
        req = urllib.request.Request(m["url"], headers={"User-Agent": "gamepad-grimoire-art"})
        with urllib.request.urlopen(req, timeout=600) as r, open(path + ".part", "wb") as f:
            shutil.copyfileobj(r, f)
        os.replace(path + ".part", path)
    return path


def build_model(cid, m, blender):
    """Build a parametric device (tools/art/model.py) into models/<cid>_built.stl."""
    os.makedirs(MODELS_DIR, exist_ok=True)
    stl = os.path.join(MODELS_DIR, cid + "_built.stl")
    params = os.path.join(HERE, "params", m["params"])
    pts = os.path.join(MODELS_DIR, cid + "_built.points.json")
    print(f"  building {cid} from {m['params']}")
    r = subprocess.run(
        [blender, "-b", "-P", os.path.join(HERE, "model.py"), "--", params, stl, pts],
        capture_output=True,
        text=True,
    )
    if "BUILT" not in r.stdout:
        sys.stdout.write(r.stdout[-3000:] + r.stderr[-3000:])
        raise SystemExit(f"{cid}: build failed")
    return stl


def render(cid, m, blender, width):
    model = build_model(cid, m, blender) if m.get("builder") else fetch(cid, m)
    os.makedirs(RENDERS, exist_ok=True)
    for view in ("front", "back"):
        base = os.path.join(RENDERS, f"{cid}_{view}")
        job = dict(
            model=model,
            out_png=base + ".png",
            view=view,
            forward=m["forward"],
            up=m["up"],
            tilt_deg=m.get("tilt_deg", 15),
            width=width,
            crease_deg=m.get("crease_deg", 140),
        )
        job_path = base + ".job.json"
        with open(job_path, "w", encoding="utf-8") as f:
            json.dump(job, f)
        r = subprocess.run(
            [blender, "-b", "--factory-startup", "-P", os.path.join(HERE, "blender_lineart.py"), "--", job_path],
            capture_output=True,
            text=True,
        )
        os.remove(job_path)
        if r.returncode != 0 or "RENDERED" not in r.stdout:
            sys.stdout.write(r.stdout[-3000:] + r.stderr[-3000:])
            raise SystemExit(f"{cid} {view}: render failed")
        print(f"  {cid}_{view}.png")
    write_credits()


def write_credits():
    """Credits next to the renders and next to the textures (shipped in the addon)."""
    media = os.path.join(os.path.dirname(os.path.dirname(HERE)), "media", "controllers")
    cad = {cid: m for cid, m in MODELS.items() if not m.get("builder")}
    built = {cid: m for cid, m in MODELS.items() if m.get("builder")}
    shipped = [
        "# Controller pictures",
        "",
        "Pictures not rendered from 3D are drawn from AL2009man's Gamepad-Asset-Pack (MIT).",
        "None of these pictures are made, endorsed or supported by the device makers.",
        "",
        "## Rendered from official CAD (licensed like the model)",
        "",
        "| Files | Made from | Author | Licence |",
        "| --- | --- | --- | --- |",
    ]
    for cid, m in cad.items():
        shipped.append(
            f"| `{cid}.tga`, `{cid}_back.tga` | {m['name']} 3D model ({m['source']}) | {m['author']}"
            f" | {m['license']} ({m['license_url']}) |"
        )
    shipped += [
        "",
        "## Modelled for this project (MIT)",
        "",
        "Built by `tools/art/model.py` from published dimensions and reference photos;",
        "simplified line-art impressions, not exact replicas.",
        "",
        "| Files | Device |",
        "| --- | --- |",
    ]
    for cid, m in built.items():
        shipped.append(f"| `{cid}.tga`, `{cid}_back.tga` | {m['name']} |")
    with open(os.path.join(media, "CREDITS.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(shipped) + "\n")
    lines = [
        "# Controller renders",
        "",
        "Rendered from 3D models by `tools/art/render3d.py`. Each picture is licensed",
        "like the model it is made from (the addon's code is MIT). These pictures are",
        "not made, endorsed or supported by the device makers.",
        "",
        "| Pictures | Model | Author | Licence |",
        "| --- | --- | --- | --- |",
    ]
    for cid, m in MODELS.items():
        lines.append(
            f"| `{cid}_front.png`, `{cid}_back.png` | [{m['name']}]({m['source']}) | {m['author']}"
            f" | [{m['license']}]({m['license_url']}) |"
        )
    with open(os.path.join(RENDERS, "CREDITS.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("ids", nargs="*", help="controllers to render (default: all)")
    ap.add_argument("--blender")
    ap.add_argument("--width", type=int, default=2000)
    a = ap.parse_args()
    blender = find_blender(a.blender)
    for cid in a.ids or list(MODELS):
        print(cid)
        render(cid, MODELS[cid], blender, a.width)


if __name__ == "__main__":
    main()
