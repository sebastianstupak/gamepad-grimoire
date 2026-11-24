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


def render(cid, m, blender, width):
    model = fetch(cid, m)
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
    shipped = [
        "# Controller pictures",
        "",
        "Pictures not listed here are drawn from AL2009man's Gamepad-Asset-Pack (MIT) or",
        "by Gamepad Grimoire (MIT). The pictures below are rendered from 3D models and",
        "are licensed like those models. They are not made, endorsed or supported by the",
        "device makers.",
        "",
        "| Files | Made from | Author | Licence |",
        "| --- | --- | --- | --- |",
    ]
    for cid, m in MODELS.items():
        shipped.append(
            f"| `{cid}.tga`, `{cid}_back.tga` | {m['name']} 3D model ({m['source']}) | {m['author']}"
            f" | {m['license']} ({m['license_url']}) |"
        )
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
