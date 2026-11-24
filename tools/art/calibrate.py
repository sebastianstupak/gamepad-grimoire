"""Project a built model's named buttons to 2D anchors, printed ready to paste
into render3d.MODELS (the `front={...}` / `back={...}` tables). Run after editing
a params/*.json so the anchors follow the geometry:

    python tools/art/calibrate.py xbox dualshock4

Uses the same camera as render3d.render, so the anchors line up with the picture.
"""

import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import render3d  # noqa: E402


def anchors_for(cid, blender, width=2000):
    m = render3d.MODELS[cid]
    if not m.get("builder"):
        raise SystemExit(f"{cid} is not a built model")
    model = render3d.build_model(cid, m, blender)
    with open(os.path.join(render3d.MODELS_DIR, cid + "_built.points.json"), encoding="utf-8") as f:
        pts = json.load(f)
    out = {}
    for view in ("front", "back"):
        base = os.path.join(render3d.RENDERS, f"{cid}_{view}")
        oj = base + ".anchors.json"
        job = dict(
            model=model,
            out_png=base + ".png",
            view=view,
            forward=m["forward"],
            up=m["up"],
            tilt_deg=m.get("tilt_deg", 15),
            width=width,
            crease_deg=m.get("crease_deg", 140),
            points=pts[view],
            out_json=oj,
        )
        for opt in ("crease", "min_line_px", "outer_px", "inner_px"):
            if opt in m:
                job[opt] = m[opt]
        job_path = base + ".cal.job.json"
        with open(job_path, "w", encoding="utf-8") as f:
            json.dump(job, f)
        r = subprocess.run(
            [blender, "-b", "--factory-startup", "-P", os.path.join(HERE, "blender_lineart.py"), "--", job_path],
            capture_output=True,
            text=True,
        )
        os.remove(job_path)
        if "RENDERED" not in r.stdout:
            sys.stdout.write(r.stdout[-2000:] + r.stderr[-2000:])
            raise SystemExit(f"{cid} {view}: projection failed")
        with open(oj, encoding="utf-8") as f:
            out[view] = json.load(f)["points"]
        os.remove(oj)
    return out


def table(name, rows):
    lines = [f"        {name}={{"]
    for b, a in rows.items():
        vals = ", ".join(f"{v:.4f}" for v in a)
        lines.append(f'            "{b}": ({vals}),')
    lines.append("        },")
    return "\n".join(lines)


def main():
    blender = render3d.find_blender()
    for cid in sys.argv[1:]:
        a = anchors_for(cid, blender)
        print(f"# ===== {cid}: paste into render3d.MODELS =====")
        print(table("front", a["front"]))
        print(table("back", a["back"]))


if __name__ == "__main__":
    main()
