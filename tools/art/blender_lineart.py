"""Runs inside Blender (see render3d.py): renders a 3D model as the addon's line art.

Flat dark fill, white Freestyle lines (thick outer contour, thin inner edges),
orthographic camera looking at the model's front or back, tilted slightly from
above so shoulder buttons and triggers show. Writes a PNG with transparency and
a JSON with the 2D position of named 3D points (button anchors).

blender -b -P blender_lineart.py -- job.json
job = { model, out_png, view: front|back, forward: "+z", up: "+y", tilt_deg,
        width, crease_deg, min_line_px, outer_px, inner_px,
        out_json?, points?: { name: [x, y, z] } }
"""

import json
import math
import sys

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Matrix, Vector

with open(sys.argv[sys.argv.index("--") + 1], encoding="utf-8") as _f:
    job = json.load(_f)

AXES = {"x": Vector((1, 0, 0)), "y": Vector((0, 1, 0)), "z": Vector((0, 0, 1))}


def axis(s):
    return AXES[s[-1]] * (-1 if s.startswith("-") else 1)


bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
model = job["model"]
if model.lower().endswith(".stl"):
    bpy.ops.wm.stl_import(filepath=model)
elif model.lower().endswith((".glb", ".gltf")):
    bpy.ops.import_scene.gltf(filepath=model)
elif model.lower().endswith(".obj"):
    bpy.ops.wm.obj_import(filepath=model)
elif model.lower().endswith(".fbx"):
    bpy.ops.import_scene.fbx(filepath=model)
meshes = [o for o in scene.objects if o.type == "MESH"]
for o in scene.objects:
    if o.type != "MESH":
        o.hide_render = True

# one flat material: the card background colour, so hidden lines stay hidden
mat = bpy.data.materials.new("fill")
mat.use_nodes = True
nt = mat.node_tree
nt.nodes.clear()
em = nt.nodes.new("ShaderNodeEmission")
em.inputs["Color"].default_value = (0.024, 0.025, 0.033, 1)  # sRGB ~ (43, 44, 51)
out = nt.nodes.new("ShaderNodeOutputMaterial")
nt.links.new(em.outputs[0], out.inputs[0])
for o in meshes:
    o.data.materials.clear()
    o.data.materials.append(mat)

# bounds of everything, in world space
pts = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
center, size = (lo + hi) / 2, hi - lo

scene.render.engine = "BLENDER_EEVEE"
scene.render.film_transparent = True
scene.view_settings.view_transform = "Standard"
scene.render.use_freestyle = True
scene.render.line_thickness_mode = "ABSOLUTE"
vl = scene.view_layers[0]
vl.use_freestyle = True
fs = vl.freestyle_settings
fs.crease_angle = math.radians(job.get("crease_deg", 140))
fs.use_smoothness = True
for ls in list(fs.linesets):
    fs.linesets.remove(ls)

width = job.get("width", 2000)
scale = width / 1000.0


def lineset(name, thickness, **sel):
    ls = fs.linesets.new(name)
    ls.select_by_visibility = True
    ls.visibility = "VISIBLE"
    ls.select_by_edge_types = True
    for k in ("select_silhouette", "select_border", "select_crease", "select_external_contour"):
        setattr(ls, k, False)
    for k, v in sel.items():
        setattr(ls, k, v)
    st = ls.linestyle
    st.color = (1, 1, 1)
    st.thickness = thickness
    st.thickness_position = "CENTER"
    st.caps = "ROUND"
    st.use_length_min = True  # drop specks (engraved text, tessellation noise)
    st.length_min = job.get("min_line_px", 6) * scale
    return ls


lineset("outer", job.get("outer_px", 3.4) * scale, select_external_contour=True)
# Inner lines carry the buttons: a raised button reads as a silhouette/border, a
# moulded one (scanned models) as a crease around its dimple. Draw them boldly -
# thin rings vanish once the picture is scaled down into the cheat sheet. On rough
# meshes crease turns into noise, so a model can switch it off (min_line_px culls
# the short speckle either way).
lineset(
    "inner",
    job.get("inner_px", 2.3) * scale,
    select_silhouette=True,
    select_border=True,
    select_crease=job.get("crease", True),
)

# camera: looks at the front (or back), tilted down from above by tilt_deg
fwd, up = axis(job.get("forward", "+z")), axis(job.get("up", "+y"))
if job.get("view", "front") == "back":
    fwd = -fwd
tilt = math.radians(job.get("tilt_deg", 0))
view_dir = (fwd * math.cos(tilt) + up * math.sin(tilt)).normalized()  # from model to camera
dist = size.length * 3
cam_data = bpy.data.cameras.new("cam")
cam_data.type = "ORTHO"
cam_data.clip_end = dist * 4
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
cam.location = center + view_dir * dist
right = up.cross(view_dir).normalized()
cam_up = view_dir.cross(right).normalized()
rot = Matrix((right, cam_up, view_dir)).transposed()
cam.rotation_euler = rot.to_euler()
bpy.context.view_layer.update()

# frame the projected bounds tightly
corners = [Vector((x, y, z)) for x in (lo.x, hi.x) for y in (lo.y, hi.y) for z in (lo.z, hi.z)]
proj = [(c - center) for c in corners]
us = [p.dot(right) for p in proj]
vs = [p.dot(cam_up) for p in proj]
w2, h2 = max(us) - min(us), max(vs) - min(vs)
cam.location += right * ((max(us) + min(us)) / 2) + cam_up * ((max(vs) + min(vs)) / 2)
pad = 1.03
cam_data.ortho_scale = max(w2, h2) * pad
scene.render.resolution_x = width if w2 >= h2 else int(width * w2 / h2)
scene.render.resolution_y = int(width * h2 / w2) if w2 >= h2 else width
bpy.context.view_layer.update()

scene.render.filepath = job["out_png"]
bpy.ops.render.render(write_still=True)

if job.get("out_json"):  # project named 3D controls to 2D anchors (cx, cy, w, h), 0..1

    def project(p):
        co = world_to_camera_view(scene, cam, Vector(p))
        return co.x, 1 - co.y

    anchors = {}
    for name, spec in job.get("points", {}).items():
        if isinstance(spec, dict):  # {p:[x,y,z], hx, hy}: project centre and extents for a box
            x, y, z = spec["p"]
            hx, hy = spec.get("hx", 5), spec.get("hy", 5)
            cx, cy = project((x, y, z))
            xs = [project((x + sx, y, z))[0] for sx in (-hx, hx)]
            ys = [project((x, y + sy, z))[1] for sy in (-hy, hy)]
            anchors[name] = [cx, cy, abs(xs[1] - xs[0]), abs(ys[1] - ys[0])]
        else:
            cx, cy = project(spec)
            anchors[name] = [cx, cy]
    with open(job["out_json"], "w", encoding="utf-8") as f:
        json.dump({"points": anchors}, f, indent=1)
print("RENDERED", job["out_png"])
