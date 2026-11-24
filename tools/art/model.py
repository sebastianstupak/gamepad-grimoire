"""Build a parametric controller / handheld mesh in Blender and export an STL
plus the 3D position of every named button (so render3d can project them to 2D
anchors). Runs inside Blender:

    blender -b -P model.py -- params.json out.stl out.points.json

Units: millimetres. The controller faces +Z, up is +Y, centred at the origin.
params.json: { outline, body_thickness, body_bevel, face_z, grip, bumper?,
screen?, dpad_arm, dpad_thick, stick_r, controls: {NAME: {type, x, y, r?}},
back?: {NAME: {x, y, r}} }
"""

import json
import math
import sys

import bmesh
import bpy

argv = sys.argv[sys.argv.index("--") + 1 :]
with open(argv[0], encoding="utf-8") as f:
    P = json.load(f)
OUT_STL, OUT_PTS = argv[1], argv[2]

bpy.ops.wm.read_factory_settings(use_empty=True)
points = {"front": {}, "back": {}}


def new_mesh(name):
    me = bpy.data.meshes.new(name)
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    return ob, me


def subsurf(ob, levels=2):
    m = ob.modifiers.new("subsurf", "SUBSURF")
    m.levels = m.render_levels = levels


def rounded_rect(cx, cy, w, h, r, segs=8):
    r = min(r, w / 2, h / 2)
    pts = []
    for ox, oy, a0 in (
        (cx + w / 2 - r, cy + h / 2 - r, 0),
        (cx - w / 2 + r, cy + h / 2 - r, 90),
        (cx - w / 2 + r, cy - h / 2 + r, 180),
        (cx + w / 2 - r, cy - h / 2 + r, 270),
    ):
        for i in range(segs + 1):
            a = math.radians(a0 + 90 * i / segs)
            pts.append((ox + r * math.cos(a), oy + r * math.sin(a)))
    return pts


def extrude_face(name, pts2d, z, thickness, offset, bevel, segs_bevel=3, angle=None):
    ob, me = new_mesh(name)
    bm = bmesh.new()
    bm.faces.new([bm.verts.new((x, y, z)) for x, y in pts2d])
    bm.to_mesh(me)
    bm.free()
    sol = ob.modifiers.new("s", "SOLIDIFY")
    sol.thickness = thickness
    sol.offset = offset
    if bevel:
        bev = ob.modifiers.new("b", "BEVEL")
        bev.width = bevel
        bev.segments = segs_bevel
        if angle is not None:
            bev.limit_method = "ANGLE"
            bev.angle_limit = math.radians(angle)
    return ob


def build_body():
    outline = P["outline"]
    full = [(x, y) for x, y in outline] + [(-x, y) for x, y in reversed(outline) if abs(x) > 1e-6]
    ob = extrude_face("body", full, 0, P["body_thickness"], 0, P.get("body_bevel", 6), 4, 60)
    subsurf(ob, 2)


def grip(side):
    g = P["grip"]
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=16, radius=1)
    ob = bpy.context.active_object
    ob.scale = (g["w"], g["h"], g["depth"])
    ob.location = (side * g["x"], g["y"], -g["z"])
    ob.rotation_euler = (math.radians(g.get("tilt", 18)), 0, side * math.radians(g.get("splay", 10)))
    subsurf(ob, 1)


def screen():
    cx, cy, w, h, r = P["screen"]
    extrude_face("screen", rounded_rect(cx, cy, w, h, r), P["face_z"], 1.5, 1, 1.0, 2)


def stick(cx, cy, r):
    bpy.ops.mesh.primitive_cylinder_add(vertices=40, radius=r, depth=3, location=(cx, cy, P["face_z"] + 1))
    b = bpy.context.active_object.modifiers.new("b", "BEVEL")
    b.width, b.segments = 1.2, 3
    bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=r * 0.62, depth=5, location=(cx, cy, P["face_z"] + 4))
    b = bpy.context.active_object.modifiers.new("b", "BEVEL")
    b.width, b.segments = 1.5, 3


def button(cx, cy, r):
    bpy.ops.mesh.primitive_cylinder_add(vertices=28, radius=r, depth=2.4, location=(cx, cy, P["face_z"] + 1.0))
    b = bpy.context.active_object.modifiers.new("b", "BEVEL")
    b.width, b.segments = 1.0, 3


def dpad(cx, cy):
    a = P["dpad_arm"]
    w = a * 0.62
    pts = [(a, w), (w, w), (w, a), (-w, a), (-w, w), (-a, w), (-a, -w), (-w, -w), (-w, -a), (w, -a), (w, -w), (a, -w)]
    extrude_face("dpad", [(cx + x, cy + y) for x, y in pts], P["face_z"], P["dpad_thick"], 1, 1.4, 3, 50)


def bumper(cx, cy):
    b = P["bumper"]
    bpy.ops.mesh.primitive_cube_add(location=(cx, cy, b.get("z", 4)))
    ob = bpy.context.active_object
    ob.scale = (b["w"] / 2, b["h"] / 2, b["t"] / 2)
    ob.rotation_euler = (math.radians(b.get("tilt", -12)), 0, 0)
    bv = ob.modifiers.new("b", "BEVEL")
    bv.width, bv.segments = 2.5, 4


def back_button(cx, cy, r):
    z = -P["body_thickness"] / 2 - 0.5
    bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=r, depth=3, location=(cx, cy, z))
    b = bpy.context.active_object.modifiers.new("b", "BEVEL")
    b.width, b.segments = 1.2, 3


build_body()
if "screen" in P:
    screen()
for s in (-1, 1):
    grip(s)

face = P["face_z"] + 3
for name, c in P["controls"].items():
    t, x, y = c["type"], c["x"], c["y"]
    r = c.get("r", P.get("stick_r", 10) if t == "stick" else P["dpad_arm"] if t == "dpad" else 7)
    if t == "stick":
        stick(x, y, r)
    elif t == "dpad":
        dpad(x, y)
    elif t == "bumper":
        bumper(x, y)
    elif t == "point":  # anchor only, no geometry (e.g. triggers, behind the bumpers)
        pass
    else:
        button(x, y, r)
    hx = hy = r
    if t == "bumper":
        hx, hy = P["bumper"]["w"] / 2, P["bumper"]["h"] / 2
    points["front"][name] = {"p": [x, y, face], "hx": hx, "hy": hy}

back_z = -P["body_thickness"] / 2 - 2
for name, c in P.get("back", {}).items():
    r = c.get("r", 6)
    back_button(c["x"], c["y"], r)
    points["back"][name] = {"p": [c["x"], c["y"], back_z], "hx": r, "hy": r}
# shoulders and triggers show on the back too (top edge), so the back view has rows
for name in ("PADLSHOULDER", "PADRSHOULDER", "PADLTRIGGER", "PADRTRIGGER"):
    c = P["controls"].get(name)
    if c:
        hx = P["bumper"]["w"] / 2 if c["type"] == "bumper" else 6
        points["back"][name] = {"p": [c["x"], c["y"], back_z], "hx": hx, "hy": 6}

bpy.ops.object.select_all(action="SELECT")
bpy.context.view_layer.objects.active = bpy.data.objects["body"]
bpy.ops.object.convert(target="MESH")
bpy.ops.object.join()
bpy.ops.wm.stl_export(filepath=OUT_STL, apply_modifiers=True)
with open(OUT_PTS, "w", encoding="utf-8") as f:
    json.dump(points, f)
print("BUILT", OUT_STL)
