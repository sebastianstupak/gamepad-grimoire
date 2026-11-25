"""Render the project logo: a realistic 3D arcade joystick (Blender / Cycles).

Usage:
    blender -b --factory-startup -P tools/art/logo.py -- docs/images/logo.png
"""

import sys

import bpy
from mathutils import Vector

OUT = sys.argv[sys.argv.index("--") + 1]

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = "CYCLES"
try:
    scene.cycles.device = "GPU"
    bpy.context.preferences.addons["cycles"].preferences.get_devices()
except Exception:
    pass
scene.cycles.samples = 180
scene.cycles.use_denoising = True
scene.render.resolution_x = scene.render.resolution_y = 1024
scene.render.film_transparent = False

world = bpy.data.worlds.new("w")
scene.world = world
world.use_nodes = True
bgn = world.node_tree.nodes["Background"]
bgn.inputs[0].default_value = (0.018, 0.018, 0.022, 1)
bgn.inputs[1].default_value = 1.0


def mat(name, color, metallic=0.0, rough=0.5, coat=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = rough
    for n in ("Coat Weight", "Clearcoat", "Coat"):
        if n in b.inputs:
            b.inputs[n].default_value = coat
            break
    return m


def add(obj, m):
    bpy.ops.object.shade_smooth()
    obj.data.materials.append(m)


bpy.ops.mesh.primitive_uv_sphere_add(segments=96, ring_count=48, radius=1.0, location=(0, 0, 2.35))
add(bpy.context.active_object, mat("ball", (0.30, 0.12, 0.72), rough=0.08, coat=0.7))

bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=0.17, depth=2.0, location=(0, 0, 1.2))
sh = bpy.context.active_object
sh.modifiers.new("b", "BEVEL").width = 0.03
add(sh, mat("shaft", (0.82, 0.82, 0.85), metallic=1.0, rough=0.13))

bpy.ops.mesh.primitive_uv_sphere_add(segments=64, ring_count=32, radius=0.95, location=(0, 0, 0.32))
dome = bpy.context.active_object
dome.scale = (1, 1, 0.42)
add(dome, mat("dome", (0.025, 0.025, 0.03), rough=0.3))

bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=1.15, depth=0.28, location=(0, 0, 0.14))
base = bpy.context.active_object
bv = base.modifiers.new("b", "BEVEL")
bv.width = 0.06
bv.segments = 3
add(base, mat("base", (0.05, 0.05, 0.06), rough=0.45))

bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, 0))
add(bpy.context.active_object, mat("floor", (0.008, 0.008, 0.011), rough=0.14))


def area(name, loc, energy, size, color=(1, 1, 1)):
    light = bpy.data.lights.new(name, "AREA")
    light.energy = energy
    light.size = size
    light.color = color
    o = bpy.data.objects.new(name, light)
    o.location = loc
    bpy.context.collection.objects.link(o)
    o.rotation_euler = (Vector((0, 0, 1.9)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()


area("key", (5, -4, 7), 1600, 6)
area("rim", (-6, 4, 4), 1700, 5, color=(0.62, 0.42, 1.0))
area("fill", (-3, -6, 3), 350, 9)

cam_d = bpy.data.cameras.new("cam")
cam = bpy.data.objects.new("cam", cam_d)
bpy.context.collection.objects.link(cam)
scene.camera = cam
cam.location = (7.2, -7.2, 5.4)
cam.rotation_euler = (Vector((0, 0, 1.6)) - Vector(cam.location)).to_track_quat("-Z", "Y").to_euler()
cam_d.lens = 85

scene.render.filepath = OUT
bpy.ops.render.render(write_still=True)
print("RENDERED", OUT)
