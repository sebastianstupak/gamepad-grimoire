"""Logo render: an original stylized handheld (Deck-like), 3/4 angle, Cycles.

Not Valve's CAD -- an own, MIT, generic handheld so the brand mark carries no
CC-BY-NC-SA / trade-dress baggage. Dark body + purple glowing screen (grimoire).

Two steps -- this renders the device on transparent; logo_compose.py adds the
dark aura, diagonal tile-fill, bloom and vignette:

    blender -b --factory-startup -P tools/art/logo.py -- device.png
    python tools/art/logo_compose.py device.png docs/images/logo.png
"""

import sys

import bpy
from mathutils import Vector

OUT = sys.argv[sys.argv.index("--") + 1]

# --- tweakables -------------------------------------------------------------
CAM_LOC = (2.5, -4.4, 4.6)
CAM_AIM = (0, 0, 0.10)
CAM_LENS = 78
YAW = 0.34  # device yaw (a readable 3/4); diagonal tile-fill is done in post
PURPLE = (0.45, 0.22, 0.95)
# ---------------------------------------------------------------------------

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = "CYCLES"
try:
    scene.cycles.device = "GPU"
    bpy.context.preferences.addons["cycles"].preferences.get_devices()
except Exception:
    pass
scene.cycles.samples = 200
scene.cycles.use_denoising = True
scene.render.resolution_x = scene.render.resolution_y = 1024
scene.render.film_transparent = True  # device only; bg/aura composited in post
# AgX (Blender's default) desaturates bright emission to near-white; Standard
# keeps the purple screen/accents vivid.
scene.view_settings.view_transform = "Standard"

world = bpy.data.worlds.new("w")
scene.world = world
world.use_nodes = True
bg = world.node_tree.nodes["Background"]
bg.inputs[0].default_value = (0.008, 0.008, 0.011, 1)
bg.inputs[1].default_value = 1.0


def mat(name, color, metallic=0.0, rough=0.5, coat=0.0, emit=None, emit_str=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = rough
    for n in ("Coat Weight", "Coat"):
        if n in b.inputs:
            b.inputs[n].default_value = coat
            break
    if emit is not None:
        if "Emission Color" in b.inputs:
            b.inputs["Emission Color"].default_value = (*emit, 1)
        if "Emission Strength" in b.inputs:
            b.inputs["Emission Strength"].default_value = emit_str
    return m


BODY = mat("body", (0.021, 0.021, 0.027), rough=0.40, coat=0.25)
GLASS = mat("glass", (0.003, 0.003, 0.005), rough=0.06, coat=0.85)
SCREEN = mat("screen", (0.10, 0.05, 0.28), emit=PURPLE, emit_str=1.05)
RUBBER = mat("rubber", (0.014, 0.014, 0.018), rough=0.55)
RING = mat("ring", PURPLE, emit=PURPLE, emit_str=1.8)
BTN = mat("btn", (0.03, 0.03, 0.04), rough=0.30, emit=(0.30, 0.14, 0.7), emit_str=1.0)
DARK = mat("dark", (0.028, 0.028, 0.036), rough=0.32)

rig = bpy.data.objects.new("rig", None)
scene.collection.objects.link(rig)
parts = []


def _finish(o, m):
    bpy.ops.object.shade_smooth()
    if m:
        o.data.materials.append(m)
    parts.append(o)
    return o


def box(sx, sy, sz, loc, m, bevel=0.0, seg=3):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.active_object
    o.dimensions = (sx, sy, sz)
    bpy.ops.object.transform_apply(scale=True)
    if bevel > 0:
        bv = o.modifiers.new("b", "BEVEL")
        bv.width = bevel
        bv.segments = seg
    return _finish(o, m)


def cyl(r, depth, loc, m, verts=48):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=loc)
    o = bpy.context.active_object
    bv = o.modifiers.new("b", "BEVEL")
    bv.width = min(0.02, r * 0.2)
    bv.segments = 2
    return _finish(o, m)


def sphere(r, loc, m, scale_z=1.0):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=24, radius=r, location=loc)
    o = bpy.context.active_object
    o.scale = (1, 1, scale_z)
    return _finish(o, m)


def torus(major, minor, loc, m):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, location=loc)
    return _finish(bpy.context.active_object, m)


def stick(x, y):
    top = 0.11
    cyl(0.15, 0.12, (x, y, top + 0.04), RUBBER)
    sphere(0.155, (x, y, top + 0.10), RUBBER, scale_z=0.55)
    torus(0.165, 0.018, (x, y, top + 0.06), RING)


def dpad(x, y):
    z = 0.145
    box(0.34, 0.12, 0.05, (x, y, z), DARK, bevel=0.02, seg=2)
    box(0.12, 0.34, 0.05, (x, y, z), DARK, bevel=0.02, seg=2)


def face_buttons(x, y):
    z = 0.155
    d = 0.16
    for dx, dy in ((0, d), (0, -d), (-d, 0), (d, 0)):
        cyl(0.072, 0.05, (x + dx, y + dy, z), BTN)


# body slab (front faces +Z)
box(2.7, 1.05, 0.22, (0, 0, 0), BODY, bevel=0.085, seg=6)
# screen, slightly proud, dark glass + emissive content
box(1.52, 0.80, 0.055, (0, 0, 0.12), GLASS, bevel=0.015, seg=2)
box(1.40, 0.70, 0.010, (0, 0, 0.150), SCREEN)
# left wing: stick (top) + d-pad (bottom)
stick(-0.98, 0.24)
dpad(-0.98, -0.26)
# right wing: face buttons (top) + stick (bottom)
face_buttons(0.98, 0.24)
stick(0.98, -0.26)
# shoulder nubs on the back edge
box(0.46, 0.14, 0.11, (-0.92, 0.50, 0.08), BODY, bevel=0.04, seg=3)
box(0.46, 0.14, 0.11, (0.92, 0.50, 0.08), BODY, bevel=0.04, seg=3)

for p in parts:
    p.parent = rig
rig.rotation_euler = (0.0, 0.0, YAW)


def area(name, loc, energy, size, color=(1, 1, 1)):
    light = bpy.data.lights.new(name, "AREA")
    light.energy = energy
    light.size = size
    light.color = color
    o = bpy.data.objects.new(name, light)
    o.location = loc
    scene.collection.objects.link(o)
    o.rotation_euler = (Vector((0, 0, 0.2)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()


area("key", (2.2, -2.6, 4.6), 320, 3)
area("rim", (-3.0, 3.2, 2.6), 650, 4, color=(0.62, 0.42, 1.0))
area("fill", (-2.6, -3.2, 1.9), 180, 9)

cam_d = bpy.data.cameras.new("cam")
cam = bpy.data.objects.new("cam", cam_d)
scene.collection.objects.link(cam)
scene.camera = cam
cam.location = CAM_LOC
cam.rotation_euler = (Vector(CAM_AIM) - Vector(CAM_LOC)).to_track_quat("-Z", "Y").to_euler()
cam_d.lens = CAM_LENS

# Bloom is added in post with PIL (tools/art handles it); Blender 5.1 reworked
# the compositor into a node-group API we skip here.
scene.render.filepath = OUT
bpy.ops.render.render(write_still=True)
print("RENDERED", OUT)
