"""pioneer.blend の見た目とポーズを確認する画像を書き出す。
blender --background assets/blender/pioneer.blend --python tools/blender/preview.py -- 出力フォルダ
"""
import math, os, sys
import bpy
from mathutils import Vector

out = sys.argv[sys.argv.index("--") + 1]
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.samples = 24
sc.cycles.device = "CPU"
sc.render.resolution_x, sc.render.resolution_y = 420, 520
world = bpy.data.worlds.new("w"); sc.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.7, 0.9, 1)
world.node_tree.nodes["Background"].inputs[1].default_value = 0.8
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
sun.data.energy = 3.5
sun.rotation_euler = (math.radians(50), 0, math.radians(30))
sc.collection.objects.link(sun)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam)
sc.camera = cam
rig = bpy.data.objects["PioneerRig"]

def shot(name, action, frame, pos, target=(0, 0, 0.95), lens=50):
    rig.animation_data.action = bpy.data.actions[action] if action else None
    for t in rig.animation_data.nla_tracks: t.mute = True
    sc.frame_set(frame)
    cam.location = pos
    d = Vector(target) - Vector(pos)
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = lens
    sc.render.filepath = os.path.join(out, name)
    bpy.ops.render.render(write_still=True)

shot("front.png", "Idle", 1, (0.9, 3.4, 1.25))
shot("face.png", "Idle", 1, (0.25, 1.0, 1.68), (0, 0, 1.64), lens=60)
shot("walk_side.png", "Walk", 1, (3.6, 0.3, 1.1))
shot("swing_side.png", "Swing", 7, (3.6, 0.6, 1.2))
