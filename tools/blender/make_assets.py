"""Planet Pioneer のモデルを Blender で作って .glb と .blend に書き出すスクリプト。

使い方(Blender 4.2 以降):
    blender --background --python tools/blender/make_assets.py -- assets/models

作るもの(.blend は assets/blender/ に保存。Godot はこのフォルダを読み込まない):
    pioneer.glb                   開拓者の全身モデル(骨格とアニメーション Idle / Walk / Swing 付き)
    fp_arm.glb                    一人称視点で画面に映る右腕
    axe.glb, pickaxe.glb          斧とツルハシ(握る位置が原点)
    tree_oak.glb, tree_pine.glb, bush.glb
    rock.glb, ore_iron.glb, ore_copper.glb, crystal.glb

Blender の座標: Z が上、キャラクターは +Y を向く(書き出すと Godot の -Z 前方になる)。
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Vector

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "assets/models"
OUT = os.path.abspath(OUT)
os.makedirs(OUT, exist_ok=True)


# ------------------------------------------------------------------ 共通

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def lin(c):
    """sRGB の色を Blender の線形色に変換"""
    return tuple(pow(v, 2.2) for v in c)


def mat(name, color, rough=0.75, metal=0.0, emit=None, emit_strength=2.0):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*lin(color), 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit:
        b.inputs["Emission Color"].default_value = (*lin(emit), 1.0)
        b.inputs["Emission Strength"].default_value = emit_strength
    return m


def activate(o):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o


def finish(o, m=None, smooth=True, subsurf=0, bevel=0.0, angle=None):
    activate(o)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if m is not None:
        o.data.materials.clear()
        o.data.materials.append(m)
    if bevel:
        mod = o.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        bpy.ops.object.modifier_apply(modifier=mod.name)
    if subsurf:
        mod = o.modifiers.new("subsurf", "SUBSURF")
        mod.levels = subsurf
        bpy.ops.object.modifier_apply(modifier=mod.name)
    if angle is not None:
        bpy.ops.object.shade_smooth_by_angle(angle=angle)
    elif smooth:
        bpy.ops.object.shade_smooth()
    else:
        bpy.ops.object.shade_flat()
    return o


def prim(kind, loc=(0, 0, 0), scale=(1, 1, 1), rot=(0, 0, 0), m=None, smooth=True,
         subsurf=0, bevel=0.0, angle=None, seg=20, rings=12, sub=2, r2=0.0):
    if kind == "cube":
        bpy.ops.mesh.primitive_cube_add(size=1)
    elif kind == "sphere":
        bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=rings, radius=0.5)
    elif kind == "cyl":
        bpy.ops.mesh.primitive_cylinder_add(vertices=seg, radius=0.5, depth=1)
    elif kind == "cone":
        bpy.ops.mesh.primitive_cone_add(vertices=seg, radius1=0.5, radius2=r2, depth=1)
    elif kind == "ico":
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=sub, radius=0.5)
    elif kind == "torus":
        bpy.ops.mesh.primitive_torus_add(major_segments=seg, minor_segments=8,
                                         major_radius=0.5, minor_radius=r2 or 0.1)
    else:
        raise ValueError(kind)
    o = bpy.context.active_object
    o.location = loc
    o.scale = scale
    o.rotation_euler = rot
    return finish(o, m, smooth, subsurf, bevel, angle)


def limb(a, b, radius, m, seg=16, r_end=None):
    """点 a から点 b へ伸びる円柱(先細りも可)"""
    a, b = Vector(a), Vector(b)
    d = b - a
    bpy.ops.mesh.primitive_cone_add(vertices=seg, radius1=radius, radius2=r_end if r_end else radius,
                                    depth=d.length)
    o = bpy.context.active_object
    o.location = (a + b) / 2
    o.rotation_euler = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_euler()
    return finish(o, m, smooth=True)


def jitter(o, amount, seed=None):
    rnd = random.Random(seed)
    for v in o.data.vertices:
        v.co += Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1))) * amount
    return o


def extrude_poly(points_yz, thickness, m, x=0.0):
    """YZ 平面の多角形を X 方向に厚みを付けて立体にする(斧の刃など)"""
    mesh = bpy.data.meshes.new("poly")
    bm = bmesh.new()
    h = thickness / 2
    front = [bm.verts.new((x + h, y, z)) for (y, z) in points_yz]
    back = [bm.verts.new((x - h, y, z)) for (y, z) in points_yz]
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    n = len(points_yz)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([front[j], front[i], back[i], back[j]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    o = bpy.data.objects.new("poly", mesh)
    bpy.context.collection.objects.link(o)
    return finish(o, m, smooth=False)


def bind(o, bone):
    vg = o.vertex_groups.new(name=bone)
    vg.add(list(range(len(o.data.vertices))), 1.0, "REPLACE")
    return o


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    o.data.name = name
    return o


def export(path, objs=None, animations=False):
    bpy.ops.object.select_all(action="DESELECT")
    for o in (objs or bpy.context.scene.objects):
        o.select_set(True)
    kwargs = dict(filepath=path, use_selection=True, export_format="GLB", export_yup=True,
                  export_apply=True, export_animations=animations)
    if animations:
        kwargs["export_animation_mode"] = "ACTIONS"
        kwargs["export_force_sampling"] = True
    bpy.ops.export_scene.gltf(**kwargs)
    print("exported", path)


# ------------------------------------------------------------------ 開拓者(全身)

M = {}


def pioneer_materials():
    M["skin"] = mat("Skin", (0.86, 0.66, 0.52), rough=0.6)
    M["hair"] = mat("Hair", (0.23, 0.14, 0.08), rough=0.8)
    M["jacket"] = mat("Jacket", (0.16, 0.44, 0.50), rough=0.8)
    M["trim"] = mat("JacketTrim", (0.95, 0.52, 0.16), rough=0.7)
    M["shirt"] = mat("Shirt", (0.90, 0.88, 0.80), rough=0.9)
    M["pants"] = mat("Pants", (0.33, 0.32, 0.27), rough=0.9)
    M["belt"] = mat("Belt", (0.34, 0.20, 0.10), rough=0.6)
    M["gold"] = mat("Buckle", (0.85, 0.68, 0.25), rough=0.3, metal=1.0)
    M["boot"] = mat("Boots", (0.30, 0.19, 0.11), rough=0.7)
    M["sole"] = mat("Sole", (0.09, 0.08, 0.08), rough=0.9)
    M["glove"] = mat("Gloves", (0.55, 0.40, 0.24), rough=0.7)
    M["pack"] = mat("Backpack", (0.82, 0.42, 0.14), rough=0.8)
    M["roll"] = mat("Bedroll", (0.40, 0.48, 0.30), rough=0.9)
    M["metal"] = mat("Metal", (0.72, 0.73, 0.76), rough=0.35, metal=1.0)
    M["eye"] = mat("EyeWhite", (0.96, 0.96, 0.94), rough=0.2)
    M["iris"] = mat("Iris", (0.22, 0.38, 0.30), rough=0.2)
    M["pupil"] = mat("Pupil", (0.03, 0.03, 0.03), rough=0.1)
    M["brow"] = mat("Brow", (0.18, 0.11, 0.06), rough=0.9)
    M["lip"] = mat("Lips", (0.66, 0.38, 0.33), rough=0.5)
    M["lens"] = mat("GoggleLens", (0.35, 0.75, 0.90), rough=0.05, metal=0.5)


def build_head(parts):
    S = M
    parts += [
        bind(prim("sphere", (0, 0.0, 1.665), (0.185, 0.205, 0.235), m=S["skin"], seg=32, rings=16), "head"),
        bind(prim("sphere", (0, 0.025, 1.605), (0.145, 0.15, 0.13), m=S["skin"], seg=24), "head"),
        bind(prim("sphere", (0, 0.108, 1.648), (0.032, 0.045, 0.055), m=S["skin"]), "head"),          # 鼻
        bind(prim("sphere", (0, 0.098, 1.598), (0.05, 0.02, 0.016), m=S["lip"]), "head"),            # 口
    ]
    for s in (1, -1):
        parts += [
            bind(prim("sphere", (s * 0.094, -0.005, 1.66), (0.026, 0.05, 0.065), m=S["skin"]), "head"),  # 耳
            bind(prim("sphere", (s * 0.041, 0.083, 1.688), (0.038, 0.03, 0.03), m=S["eye"]), "head"),
            bind(prim("sphere", (s * 0.041, 0.096, 1.688), (0.02, 0.012, 0.02), m=S["iris"]), "head"),
            bind(prim("sphere", (s * 0.041, 0.101, 1.688), (0.01, 0.006, 0.01), m=S["pupil"]), "head"),
            bind(prim("cube", (s * 0.043, 0.098, 1.722), (0.045, 0.012, 0.011), (0, s * 0.15, 0),
                      m=S["brow"], bevel=0.004), "head"),
            # ゴーグル(額にかけている)
            bind(prim("cyl", (s * 0.046, 0.1, 1.758), (0.05, 0.05, 0.03), (math.radians(80), 0, 0),
                      m=S["metal"], seg=20), "head"),
            bind(prim("cyl", (s * 0.046, 0.117, 1.76), (0.04, 0.04, 0.008), (math.radians(80), 0, 0),
                      m=S["lens"], seg=20), "head"),
        ]
    # 髪(頭頂と後ろを覆う)と前髪
    hair = prim("sphere", (0, -0.022, 1.71), (0.2, 0.218, 0.2), m=S["hair"], seg=32, rings=16)
    jitter(hair, 0.004, seed=3)
    parts.append(bind(hair, "head"))
    for i, x in enumerate((-0.06, -0.02, 0.025, 0.065)):
        parts.append(bind(prim("cone", (x, 0.075, 1.775), (0.06, 0.05, 0.07),
                               (math.radians(-60), 0, math.radians(15 * (i - 1.5))), m=S["hair"], seg=8), "head"))
    # ゴーグルのベルト
    parts.append(bind(prim("torus", (0, 0, 1.755), (0.198, 0.215, 0.3), (math.radians(-6), 0, 0),
                           m=S["belt"], seg=32, r2=0.05), "head"))
    parts.append(bind(limb((0, 0, 1.47), (0, 0.01, 1.57), 0.052, S["skin"]), "neck"))


def build_torso(parts):
    S = M
    parts += [
        bind(prim("cube", (0, 0, 1.32), (0.36, 0.22, 0.32), m=S["jacket"], bevel=0.05, subsurf=1), "chest"),
        bind(prim("cube", (0, 0.0, 1.13), (0.32, 0.2, 0.2), m=S["jacket"], bevel=0.05, subsurf=1), "spine"),
        bind(prim("torus", (0, 0.0, 1.475), (0.2, 0.2, 0.5), m=S["shirt"], seg=24, r2=0.12), "chest"),  # 襟
        bind(prim("cube", (0, 0.1, 1.27), (0.012, 0.03, 0.36), m=S["metal"]), "chest"),                 # ファスナー
        bind(prim("cube", (0, 0.105, 1.03), (0.24, 0.01, 0.04), m=S["trim"]), "spine"),                # 裾の帯
        bind(prim("cube", (0, 0, 0.98), (0.32, 0.21, 0.06), m=S["belt"], bevel=0.01), "hips"),          # ベルト
        bind(prim("cube", (0, 0.107, 0.98), (0.06, 0.012, 0.045), m=S["gold"], bevel=0.005), "hips"),
        bind(prim("cube", (0, 0, 0.9), (0.31, 0.2, 0.16), m=S["pants"], bevel=0.04, subsurf=1), "hips"),
        # 背中のバックパックと寝袋
        bind(prim("cube", (0, -0.18, 1.25), (0.3, 0.14, 0.36), m=S["pack"], bevel=0.035, angle=0.7), "chest"),
        bind(prim("cube", (0, -0.258, 1.2), (0.22, 0.03, 0.14), m=S["pack"], bevel=0.015, angle=0.7), "chest"),
        bind(prim("cyl", (0, -0.18, 1.47), (0.15, 0.15, 0.36), (0, math.radians(90), 0), m=S["roll"], seg=20), "chest"),
    ]
    for s in (1, -1):
        parts += [
            # 胸ポケットと肩の当て布
            bind(prim("cube", (s * 0.09, 0.105, 1.33), (0.09, 0.02, 0.08), m=S["jacket"], bevel=0.01, angle=0.7), "chest"),
            bind(prim("cube", (s * 0.09, 0.117, 1.365), (0.09, 0.01, 0.02), m=S["trim"]), "chest"),
            bind(prim("sphere", (s * 0.17, 0, 1.44), (0.13, 0.16, 0.08), m=S["trim"]), "chest"),
            # バックパックの肩ベルト
            bind(prim("cube", (s * 0.1, 0.0, 1.43), (0.045, 0.24, 0.02), m=S["belt"]), "chest"),
            bind(prim("cube", (s * 0.1, 0.112, 1.33), (0.045, 0.012, 0.2), m=S["belt"]), "chest"),
            # 腰のポーチ
            bind(prim("cube", (s * 0.15, 0.06, 0.95), (0.05, 0.08, 0.09), m=S["belt"], bevel=0.01, angle=0.7), "hips"),
        ]


def build_arm(parts, s, fp=False):
    """s=1 で右腕(+X)、s=-1 で左腕"""
    S = M
    side = "R" if s > 0 else "L"
    sh = (s * 0.2, 0, 1.43)
    el = (s * 0.23, 0, 1.16)
    wr = (s * 0.25, 0.02, 0.93)
    parts += [
        bind(prim("sphere", sh, (0.12, 0.12, 0.12), m=S["jacket"]), f"upper_arm.{side}"),
        bind(limb(sh, el, 0.058, S["jacket"], r_end=0.05), f"upper_arm.{side}"),
        bind(prim("sphere", el, (0.1, 0.1, 0.1), m=S["jacket"]), f"forearm.{side}"),
        bind(limb(el, (s * 0.245, 0.016, 0.98), 0.05, S["jacket"], r_end=0.044), f"forearm.{side}"),
        bind(prim("torus", (s * 0.246, 0.017, 0.975), (0.1, 0.1, 0.25), m=S["trim"], seg=20, r2=0.18), f"forearm.{side}"),
    ]
    build_hand(parts, (s * 0.25, 0.025, 0.875), s, f"hand.{side}")


def build_hand(parts, c, s, bone, grip=True):
    """手袋をはめた手。c は手のひらの中心"""
    S = M
    cx, cy, cz = c
    parts.append(bind(prim("cube", (cx, cy, cz), (0.05, 0.085, 0.09), m=S["glove"], bevel=0.015, subsurf=1), bone))
    # 指(軽く握った形)
    for i in range(4):
        y = cy - 0.03 + i * 0.021
        parts.append(bind(limb((cx, y, cz - 0.04), (cx + s * 0.02, y, cz - 0.085), 0.011, S["glove"], seg=8), bone))
        parts.append(bind(prim("sphere", (cx + s * 0.022, y, cz - 0.088), (0.024, 0.022, 0.024), m=S["glove"], seg=8, rings=6), bone))
    # 親指
    parts.append(bind(limb((cx - s * 0.015, cy + 0.04, cz), (cx - s * 0.005, cy + 0.07, cz - 0.05), 0.013, S["glove"], seg=8), bone))
    parts.append(bind(prim("torus", (cx, cy, cz + 0.05), (0.13, 0.17, 0.3), m=S["glove"], seg=16, r2=0.12), bone))


def build_leg(parts, s):
    S = M
    side = "R" if s > 0 else "L"
    hip = (s * 0.09, 0, 0.92)
    knee = (s * 0.1, 0.01, 0.5)
    ankle = (s * 0.1, 0, 0.1)
    parts += [
        bind(limb(hip, knee, 0.082, S["pants"], r_end=0.064), f"thigh.{side}"),
        bind(prim("cube", (s * 0.175, 0.0, 0.74), (0.03, 0.11, 0.12), m=S["pants"], bevel=0.01, angle=0.7), f"thigh.{side}"),  # 太もものポケット
        bind(prim("sphere", knee, (0.13, 0.13, 0.13), m=S["pants"]), f"shin.{side}"),
        bind(prim("sphere", (s * 0.1, 0.045, 0.5), (0.1, 0.06, 0.11), m=S["belt"]), f"shin.{side}"),  # ひざ当て
        bind(limb(knee, (s * 0.1, 0, 0.24), 0.062, S["pants"], r_end=0.056), f"shin.{side}"),
        # ブーツ
        bind(limb((s * 0.1, 0, 0.28), (s * 0.1, 0, 0.08), 0.066, S["boot"]), f"shin.{side}"),
        bind(prim("torus", (s * 0.1, 0, 0.275), (0.14, 0.14, 0.3), m=S["boot"], seg=20, r2=0.15), f"shin.{side}"),
        bind(prim("cube", (s * 0.1, 0.05, 0.06), (0.11, 0.26, 0.1), m=S["boot"], bevel=0.035, subsurf=1), f"foot.{side}"),
        bind(prim("cube", (s * 0.1, 0.05, 0.012), (0.115, 0.27, 0.025), m=S["sole"], bevel=0.008), f"foot.{side}"),
        bind(prim("cube", (s * 0.1, 0.13, 0.085), (0.07, 0.04, 0.012), m=S["belt"]), f"foot.{side}"),  # 靴ひも
    ]


BONES = [
    # 名前, 頭, 尾, 親
    ("hips", (0, 0, 0.92), (0, 0, 1.04), None),
    ("spine", (0, 0, 1.04), (0, 0, 1.24), "hips"),
    ("chest", (0, 0, 1.24), (0, 0, 1.46), "spine"),
    ("neck", (0, 0, 1.46), (0, 0, 1.56), "chest"),
    ("head", (0, 0, 1.56), (0, 0, 1.8), "neck"),
]
for _s, _n in ((1, "R"), (-1, "L")):
    BONES += [
        (f"upper_arm.{_n}", (_s * 0.2, 0, 1.43), (_s * 0.23, 0, 1.16), "chest"),
        (f"forearm.{_n}", (_s * 0.23, 0, 1.16), (_s * 0.25, 0.02, 0.93), f"upper_arm.{_n}"),
        (f"hand.{_n}", (_s * 0.25, 0.02, 0.93), (_s * 0.25, 0.03, 0.8), f"forearm.{_n}"),
        (f"thigh.{_n}", (_s * 0.09, 0, 0.92), (_s * 0.1, 0.01, 0.5), "hips"),
        (f"shin.{_n}", (_s * 0.1, 0.01, 0.5), (_s * 0.1, 0, 0.1), f"thigh.{_n}"),
        (f"foot.{_n}", (_s * 0.1, 0, 0.1), (_s * 0.1, 0.16, 0.04), f"shin.{_n}"),
    ]


def make_rig():
    arm_data = bpy.data.armatures.new("PioneerRig")
    rig = bpy.data.objects.new("PioneerRig", arm_data)
    bpy.context.collection.objects.link(rig)
    activate(rig)
    bpy.ops.object.mode_set(mode="EDIT")
    for name, head, tail, parent in BONES:
        b = arm_data.edit_bones.new(name)
        b.head = head
        b.tail = tail
        b.roll = 0.0
        if parent:
            b.parent = arm_data.edit_bones[parent]
            b.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in rig.pose.bones:
        pb.rotation_mode = "XYZ"
    return rig


def key_pose(rig, frame, pose):
    """pose: {骨の名前: (x, y, z) 回転(ラジアン)}"""
    for pb in rig.pose.bones:
        rot = pose.get(pb.name, (0, 0, 0))
        pb.rotation_euler = rot
        pb.keyframe_insert("rotation_euler", frame=frame)


def make_action(rig, name, keys, cyclic=True):
    rig.animation_data_create()
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    rig.animation_data.action = act
    for frame, pose in keys:
        key_pose(rig, frame, pose)
    if cyclic:
        for fc in act.fcurves:
            fc.modifiers.new("CYCLES")
    track = rig.animation_data.nla_tracks.new()
    track.name = name
    track.strips.new(name, int(keys[0][0]), act)
    rig.animation_data.action = None
    return act


def pioneer_animations(rig):
    # 腕・脚の骨は下向き。ローカルX軸まわりの + 回転で前へ振れる
    make_action(rig, "Idle", [
        (1, {"chest": (0.0, 0, 0), "upper_arm.R": (0, 0, 0.06), "upper_arm.L": (0, 0, -0.06)}),
        (30, {"chest": (0.035, 0, 0), "head": (-0.03, 0, 0), "upper_arm.R": (0, 0, 0.09), "upper_arm.L": (0, 0, -0.09)}),
        (60, {"chest": (0.0, 0, 0), "upper_arm.R": (0, 0, 0.06), "upper_arm.L": (0, 0, -0.06)}),
    ])
    a, k = 0.55, 0.9
    make_action(rig, "Walk", [
        (1, {"thigh.R": (a, 0, 0), "thigh.L": (-a, 0, 0), "shin.L": (-0.3, 0, 0),
             "upper_arm.R": (-0.45, 0, 0.05), "upper_arm.L": (0.45, 0, -0.05),
             "forearm.R": (0.25, 0, 0), "forearm.L": (0.45, 0, 0), "spine": (0, 0, 0.06)}),
        (7, {"thigh.R": (0.0, 0, 0), "thigh.L": (0.1, 0, 0), "shin.L": (-k, 0, 0),
             "upper_arm.R": (0, 0, 0.05), "upper_arm.L": (0, 0, -0.05),
             "forearm.R": (0.3, 0, 0), "forearm.L": (0.3, 0, 0)}),
        (13, {"thigh.L": (a, 0, 0), "thigh.R": (-a, 0, 0), "shin.R": (-0.3, 0, 0),
              "upper_arm.L": (-0.45, 0, -0.05), "upper_arm.R": (0.45, 0, 0.05),
              "forearm.L": (0.25, 0, 0), "forearm.R": (0.45, 0, 0), "spine": (0, 0, -0.06)}),
        (19, {"thigh.L": (0.0, 0, 0), "thigh.R": (0.1, 0, 0), "shin.R": (-k, 0, 0),
              "upper_arm.R": (0, 0, 0.05), "upper_arm.L": (0, 0, -0.05),
              "forearm.R": (0.3, 0, 0), "forearm.L": (0.3, 0, 0)}),
        (25, {"thigh.R": (a, 0, 0), "thigh.L": (-a, 0, 0), "shin.L": (-0.3, 0, 0),
              "upper_arm.R": (-0.45, 0, 0.05), "upper_arm.L": (0.45, 0, -0.05),
              "forearm.R": (0.25, 0, 0), "forearm.L": (0.45, 0, 0), "spine": (0, 0, 0.06)}),
    ])
    make_action(rig, "Swing", [
        (1, {"upper_arm.R": (0.5, 0, 0.05), "forearm.R": (0.9, 0, 0)}),
        (7, {"upper_arm.R": (2.7, 0, 0.1), "forearm.R": (0.9, 0, 0), "chest": (-0.12, 0, 0.1), "spine": (-0.05, 0, 0)}),
        (12, {"upper_arm.R": (0.9, 0, 0.0), "forearm.R": (0.2, 0, 0), "chest": (0.18, 0, -0.08), "spine": (0.08, 0, 0)}),
        (20, {"upper_arm.R": (0.5, 0, 0.05), "forearm.R": (0.9, 0, 0)}),
    ], cyclic=False)


def make_pioneer():
    reset()
    pioneer_materials()
    parts = []
    build_head(parts)
    build_torso(parts)
    for s in (1, -1):
        build_arm(parts, s)
        build_leg(parts, s)
    body = join(parts, "Pioneer")
    rig = make_rig()
    body.parent = rig
    mod = body.modifiers.new("Armature", "ARMATURE")
    mod.object = rig
    pioneer_animations(rig)
    blend_dir = os.path.join(os.path.dirname(OUT), "blender")
    os.makedirs(blend_dir, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(blend_dir, "pioneer.blend"))
    export(os.path.join(OUT, "pioneer.glb"), [body, rig], animations=True)
    tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
    print("pioneer triangles:", tris)


def make_fp_arm():
    """一人称視点用の右腕。手の中心が原点、腕は後ろ(-Y)へ伸びる"""
    reset()
    pioneer_materials()
    parts = []
    # 肘から手首まで(前腕を前に向けた形)
    parts.append(limb((0, -0.42, -0.05), (0, -0.08, 0), 0.055, M["jacket"], r_end=0.046))
    parts.append(prim("torus", (0, -0.085, 0), (0.1, 0.1, 0.25), (math.radians(90), 0, 0), m=M["trim"], seg=20, r2=0.18))
    hand = []
    build_hand(hand, (0, 0, 0), 1, "x")
    # 手(元は指が下向き)を、指が前(+Y)を向くように倒す
    for o in hand:
        o.vertex_groups.clear()
    h = join(hand, "Hand")
    h.rotation_euler = (math.radians(90), 0, 0)
    activate(h)
    bpy.ops.object.transform_apply(rotation=True)
    parts.append(h)
    arm = join(parts, "FPArm")
    export(os.path.join(OUT, "fp_arm.glb"), [arm])


# ------------------------------------------------------------------ 道具

def make_tools():
    reset()
    wood = mat("Handle", (0.55, 0.36, 0.2), rough=0.7)
    wrap = mat("Grip", (0.25, 0.15, 0.09), rough=0.9)
    steel = mat("Steel", (0.7, 0.72, 0.75), rough=0.3, metal=1.0)
    edge = mat("Edge", (0.92, 0.93, 0.95), rough=0.15, metal=1.0)

    def handle():
        return [
            limb((0, 0, -0.14), (0, 0, 0.58), 0.019, wood, seg=12, r_end=0.016),
            limb((0, 0, -0.1), (0, 0, 0.08), 0.023, wrap, seg=12),
            prim("sphere", (0, 0, -0.145), (0.05, 0.05, 0.04), m=wood, seg=12, rings=8),
        ]

    # 斧(握る位置が原点、柄は +Z、刃は +Y 向き)
    parts = handle()
    parts.append(prim("cube", (0, 0.0, 0.53), (0.045, 0.08, 0.09), m=steel, bevel=0.008, angle=0.6))
    parts.append(extrude_poly([(0.03, 0.495), (0.03, 0.565), (0.12, 0.62), (0.165, 0.53), (0.12, 0.44)], 0.022, steel))
    parts.append(extrude_poly([(0.12, 0.62), (0.165, 0.53), (0.12, 0.44), (0.135, 0.53)], 0.012, edge))
    axe = join(parts, "Axe")
    export(os.path.join(OUT, "axe.glb"), [axe])

    reset()
    wood = mat("Handle", (0.55, 0.36, 0.2), rough=0.7)
    wrap = mat("Grip", (0.25, 0.15, 0.09), rough=0.9)
    steel = mat("Steel", (0.6, 0.62, 0.66), rough=0.35, metal=1.0)
    parts = handle()
    # ツルハシ(弓なりの頭が Y 方向に両側へ伸びる)
    pts_top, pts_bot = [], []
    for i in range(9):
        t = -1 + i * 0.25
        y = t * 0.27
        bend = (1 - t * t) * 0.07
        half = 0.025 * (1 - abs(t) ** 2) + 0.004
        pts_top.append((y, 0.5 + bend + half))
        pts_bot.append((y, 0.5 + bend - half))
    parts.append(extrude_poly(pts_top + list(reversed(pts_bot)), 0.03, steel))
    parts.append(prim("cube", (0, 0, 0.555), (0.05, 0.06, 0.08), m=steel, bevel=0.008, angle=0.6))
    pick = join(parts, "Pickaxe")
    export(os.path.join(OUT, "pickaxe.glb"), [pick])


# ------------------------------------------------------------------ 自然物

def make_nature():
    rnd = random.Random(11)

    reset()
    bark = mat("Bark", (0.42, 0.29, 0.18), rough=0.9)
    leaf_a = mat("LeafA", (0.30, 0.55, 0.22), rough=0.8)
    leaf_b = mat("LeafB", (0.38, 0.64, 0.26), rough=0.8)
    parts = [limb((0, 0, 0), (0, 0, 3.2), 0.26, bark, seg=10, r_end=0.13)]
    parts.append(limb((0, 0, 2.0), (0.8, 0.2, 3.0), 0.09, bark, seg=8, r_end=0.05))
    parts.append(limb((0, 0, 2.3), (-0.7, -0.3, 3.3), 0.08, bark, seg=8, r_end=0.04))
    for i in range(7):
        a = i / 7 * math.tau
        r = 0.9 if i else 0.0
        c = (math.cos(a) * r, math.sin(a) * r, 3.7 + rnd.uniform(-0.3, 0.5) + (0.6 if i == 0 else 0))
        s = rnd.uniform(1.6, 2.2)
        o = prim("ico", c, (s, s, s * 0.85), m=leaf_a if i % 2 else leaf_b, smooth=False, sub=2)
        jitter(o, 0.09, seed=i)
        parts.append(o)
    export(os.path.join(OUT, "tree_oak.glb"), [join(parts, "TreeOak")])

    reset()
    bark = mat("Bark", (0.38, 0.26, 0.17), rough=0.9)
    needle = mat("Needle", (0.16, 0.38, 0.24), rough=0.85)
    parts = [limb((0, 0, 0), (0, 0, 5.5), 0.2, bark, seg=8, r_end=0.06)]
    for i, (z, r) in enumerate(((1.6, 1.6), (2.6, 1.3), (3.5, 1.0), (4.4, 0.7), (5.2, 0.42))):
        o = prim("cone", (0, 0, z + 0.6), (r * 2, r * 2, 1.6), m=needle, smooth=False, seg=9)
        jitter(o, 0.05, seed=20 + i)
        parts.append(o)
    export(os.path.join(OUT, "tree_pine.glb"), [join(parts, "TreePine")])

    reset()
    leaf = mat("BushLeaf", (0.28, 0.5, 0.2), rough=0.8)
    berry = mat("Berry", (0.85, 0.2, 0.25), rough=0.4)
    parts = []
    for i in range(4):
        c = (rnd.uniform(-0.35, 0.35), rnd.uniform(-0.35, 0.35), 0.35 + rnd.uniform(0, 0.15))
        o = prim("ico", c, (0.8, 0.8, 0.65), m=leaf, smooth=False, sub=1)
        jitter(o, 0.05, seed=40 + i)
        parts.append(o)
    for i in range(6):
        a = rnd.uniform(0, math.tau)
        parts.append(prim("sphere", (math.cos(a) * 0.45, math.sin(a) * 0.45, rnd.uniform(0.3, 0.6)),
                          (0.07, 0.07, 0.07), m=berry, seg=8, rings=6))
    export(os.path.join(OUT, "bush.glb"), [join(parts, "Bush")])

    def rock_body(m, seed, scale=(1.3, 1.1, 0.85)):
        o = prim("ico", (0, 0, 0.3), scale, m=m, smooth=False, sub=2)
        jitter(o, 0.09, seed=seed)
        return o

    reset()
    stone = mat("Stone", (0.55, 0.55, 0.53), rough=0.9)
    moss = mat("Moss", (0.36, 0.5, 0.25), rough=0.95)
    parts = [rock_body(stone, 1)]
    parts.append(jitter(prim("ico", (0.35, 0.2, 0.15), (0.6, 0.5, 0.4), m=stone, smooth=False, sub=1), 0.05, seed=2))
    parts.append(jitter(prim("ico", (-0.15, 0.05, 0.62), (0.6, 0.5, 0.2), m=moss, smooth=False, sub=1), 0.04, seed=3))
    export(os.path.join(OUT, "rock.glb"), [join(parts, "Rock")])

    def ore(name, base_c, ore_m, seed):
        reset()
        base = mat("OreRock", base_c, rough=0.9)
        om = ore_m()
        parts = [rock_body(base, seed, (1.4, 1.2, 1.0))]
        r = random.Random(seed)
        for i in range(9):
            d = Vector((r.uniform(-1, 1), r.uniform(-1, 1), r.uniform(-0.2, 1))).normalized()
            c = Vector((0, 0, 0.3)) + Vector((d.x * 0.62, d.y * 0.55, d.z * 0.45))
            s = r.uniform(0.14, 0.24)
            parts.append(jitter(prim("ico", c, (s, s, s), m=om, smooth=False, sub=1), 0.02, seed=i))
        export(os.path.join(OUT, f"{name}.glb"), [join(parts, name)])

    ore("ore_iron", (0.4, 0.37, 0.36), lambda: mat("Iron", (0.72, 0.42, 0.25), rough=0.4, metal=0.7), 5)
    ore("ore_copper", (0.42, 0.4, 0.37), lambda: mat("Copper", (0.25, 0.7, 0.55), rough=0.4, metal=0.6), 6)

    reset()
    base = mat("CrystalRock", (0.32, 0.3, 0.36), rough=0.9)
    gem = mat("Crystal", (0.62, 0.45, 1.0), rough=0.05, emit=(0.55, 0.35, 1.0), emit_strength=1.5)
    parts = [rock_body(base, 9, (1.0, 0.9, 0.5))]
    for i in range(6):
        a = i / 6 * math.tau + rnd.uniform(-0.3, 0.3)
        tilt = 0.35 if i else 0.0
        h = rnd.uniform(0.6, 1.1) * (1.4 if i == 0 else 1.0)
        base_pt = Vector((math.cos(a) * 0.2 * (i > 0), math.sin(a) * 0.2 * (i > 0), 0.35))
        direction = Vector((math.cos(a) * tilt, math.sin(a) * tilt, 1)).normalized()
        parts.append(limb(base_pt, base_pt + direction * h, 0.09, gem, seg=6))
        tip = prim("cone", (0, 0, 0), (0.18, 0.18, 0.22), m=gem, smooth=False, seg=6)
        tip.location = base_pt + direction * (h + 0.11)
        tip.rotation_euler = Vector((0, 0, 1)).rotation_difference(direction).to_euler()
        activate(tip)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
        parts.append(tip)
    for o in parts[1:]:
        activate(o)
        bpy.ops.object.shade_flat()
    export(os.path.join(OUT, "crystal.glb"), [join(parts, "Crystal")])


# ------------------------------------------------------------------ 設置物

def make_workbench():
    """作業台。原点は床の中心、正面(作業する側)は +Y"""
    reset()
    plank = mat("Plank", (0.66, 0.46, 0.27), rough=0.8)
    dark = mat("PlankDark", (0.45, 0.3, 0.17), rough=0.85)
    iron = mat("Iron", (0.45, 0.46, 0.5), rough=0.4, metal=0.9)
    stone = mat("Stone", (0.55, 0.55, 0.53), rough=0.9)
    handle = mat("Handle", (0.55, 0.36, 0.2), rough=0.7)
    parts = []
    # 天板(板を3枚並べる)
    for i, y in enumerate((-0.22, 0.0, 0.22)):
        parts.append(prim("cube", (0, y, 0.86), (1.3, 0.21, 0.07), m=plank if i != 1 else dark, bevel=0.01, angle=0.6))
    # 脚と横木
    for x in (-0.56, 0.56):
        for y in (-0.24, 0.24):
            parts.append(prim("cube", (x, y, 0.41), (0.09, 0.09, 0.82), m=dark, bevel=0.008, angle=0.6))
        parts.append(prim("cube", (x, 0, 0.2), (0.07, 0.5, 0.06), m=dark, bevel=0.006, angle=0.6))
    # 下の棚と、その上の石
    parts.append(prim("cube", (0, 0, 0.2), (1.12, 0.5, 0.04), m=plank, bevel=0.006, angle=0.6))
    parts.append(jitter(prim("ico", (-0.3, 0.05, 0.3), (0.26, 0.22, 0.18), m=stone, smooth=False, sub=1), 0.02, seed=7))
    parts.append(jitter(prim("ico", (-0.05, -0.08, 0.28), (0.2, 0.18, 0.14), m=stone, smooth=False, sub=1), 0.02, seed=8))
    # 天板の角の金具
    for x in (-0.64, 0.64):
        for y in (-0.31, 0.31):
            parts.append(prim("cube", (x, y, 0.86), (0.05, 0.05, 0.09), m=iron))
    # 万力
    parts.append(prim("cube", (0.5, 0.33, 0.83), (0.18, 0.08, 0.12), m=iron, bevel=0.01, angle=0.6))
    parts.append(limb((0.5, 0.37, 0.83), (0.5, 0.52, 0.83), 0.015, iron, seg=8))
    parts.append(limb((0.42, 0.52, 0.83), (0.58, 0.52, 0.83), 0.012, iron, seg=8))
    # 天板の上の金づちとのこぎり
    parts.append(limb((-0.35, 0.05, 0.915), (-0.05, 0.12, 0.915), 0.018, handle, seg=8))
    parts.append(prim("cube", (-0.04, 0.12, 0.925), (0.05, 0.13, 0.05), (0, 0, 0.23), m=iron, bevel=0.006, angle=0.6))
    parts.append(prim("cube", (0.15, -0.16, 0.9), (0.42, 0.11, 0.006), (0, 0, -0.1), m=iron))
    parts.append(prim("cube", (-0.1, -0.13, 0.91), (0.12, 0.06, 0.03), (0, 0, -0.1), m=handle, bevel=0.008, angle=0.6))
    export(os.path.join(OUT, "workbench.glb"), [join(parts, "Workbench")])


def make_stations():
    """製炉・工業用製炉・旋盤・発射台・ロケット。原点は床の中心、正面は +Y"""
    R = math.radians

    # 製炉(石を積んだかまど)
    reset()
    stone = mat("Stone", (0.58, 0.57, 0.54), rough=0.95)
    dark = mat("StoneDark", (0.36, 0.35, 0.34), rough=0.95)
    fire = mat("Fire", (1.0, 0.55, 0.15), rough=0.5, emit=(1.0, 0.45, 0.1), emit_strength=6.0)
    soot = mat("Soot", (0.08, 0.07, 0.07), rough=1.0)
    rnd = random.Random(21)
    parts = []
    for row in range(5):
        for i in range(8):
            a = i / 8 * math.tau + row * 0.4
            o = prim("cube", (math.cos(a) * 0.48, math.sin(a) * 0.48, 0.1 + row * 0.19), (0.3, 0.24, 0.18),
                     (0, 0, a), m=stone if (i + row) % 3 else dark, bevel=0.03, angle=0.5)
            jitter(o, 0.012, seed=row * 10 + i)
            parts.append(o)
    parts.append(prim("cyl", (0, 0, 0.5), (0.85, 0.85, 1.0), m=soot, seg=16))
    parts.append(prim("cube", (0, 0.42, 0.33), (0.36, 0.2, 0.3), m=fire))
    parts.append(prim("cube", (0, 0.46, 0.55), (0.48, 0.12, 0.08), m=dark, bevel=0.02, angle=0.5))
    parts.append(limb((0, 0, 1.0), (0, 0, 1.6), 0.17, dark, seg=10, r_end=0.13))
    parts.append(prim("torus", (0, 0, 1.6), (0.3, 0.3, 0.5), m=stone, seg=12, r2=0.2))
    export(os.path.join(OUT, "furnace.glb"), [join(parts, "Furnace")])

    # 工業用製炉(鉄の箱に煙突と配管)
    reset()
    steel = mat("Steel", (0.55, 0.58, 0.63), rough=0.4, metal=0.9)
    plate = mat("SteelDark", (0.32, 0.35, 0.4), rough=0.5, metal=0.8)
    hazard = mat("Hazard", (0.95, 0.72, 0.12), rough=0.6)
    fire = mat("Fire", (1.0, 0.55, 0.15), rough=0.5, emit=(1.0, 0.45, 0.1), emit_strength=6.0)
    parts = [
        prim("cube", (0, 0, 0.7), (1.6, 1.2, 1.4), m=steel, bevel=0.04, angle=0.5),
        prim("cube", (0, 0, 0.06), (1.75, 1.35, 0.12), m=plate, bevel=0.02, angle=0.5),
        prim("cube", (0, 0.61, 0.55), (0.7, 0.04, 0.5), m=fire),
        prim("cube", (0, 0.63, 0.88), (0.9, 0.06, 0.08), m=hazard),
        prim("cube", (0, 0.63, 0.24), (0.9, 0.06, 0.08), m=hazard),
        limb((0.45, -0.2, 1.4), (0.45, -0.2, 2.6), 0.16, plate, seg=12),
        limb((-0.45, -0.25, 1.4), (-0.45, -0.25, 2.2), 0.12, plate, seg=12),
        limb((-0.82, 0.3, 0.4), (-0.82, 0.3, 1.2), 0.07, steel, seg=10),
        limb((-0.82, 0.3, 1.2), (-0.3, 0.3, 1.45), 0.07, steel, seg=10),
    ]
    for z in (2.0, 2.5):
        parts.append(prim("torus", (0.45, -0.2, z), (0.36, 0.36, 0.5), m=hazard, seg=16, r2=0.15))
    for x in (-0.6, 0.6):
        parts.append(prim("cyl", (x, 0.62, 1.2), (0.12, 0.12, 0.05), (R(90), 0, 0), m=hazard, seg=16))
    export(os.path.join(OUT, "industrial_furnace.glb"), [join(parts, "IndustrialFurnace")])

    # 旋盤(作業台の上に回転する主軸)
    reset()
    steel = mat("Steel", (0.62, 0.65, 0.7), rough=0.35, metal=0.9)
    blue = mat("MachineBlue", (0.2, 0.42, 0.72), rough=0.5)
    dark = mat("SteelDark", (0.25, 0.27, 0.3), rough=0.5, metal=0.7)
    hazard = mat("Hazard", (0.95, 0.72, 0.12), rough=0.6)
    parts = [
        prim("cube", (0, 0, 0.42), (1.7, 0.6, 0.84), m=blue, bevel=0.03, angle=0.5),
        prim("cube", (0, 0, 0.88), (1.6, 0.4, 0.08), m=dark),
        prim("cube", (-0.6, 0, 1.12), (0.42, 0.46, 0.44), m=blue, bevel=0.03, angle=0.5),
        prim("cube", (0.62, 0, 1.06), (0.26, 0.3, 0.3), m=blue, bevel=0.02, angle=0.5),
        limb((-0.39, 0, 1.12), (0.49, 0, 1.12), 0.035, steel, seg=12),
        prim("cyl", (-0.35, 0, 1.12), (0.22, 0.22, 0.1), (0, R(90), 0), m=steel, seg=20),
        prim("cube", (0.1, 0.12, 1.0), (0.2, 0.14, 0.14), m=dark),
        prim("cube", (0, 0.31, 0.6), (1.5, 0.02, 0.05), m=hazard),
    ]
    for x in (-0.55, 0.3):
        parts.append(prim("cyl", (x, 0.33, 0.6), (0.14, 0.14, 0.04), (R(90), 0, 0), m=steel, seg=16))
    export(os.path.join(OUT, "lathe.glb"), [join(parts, "Lathe")])

    # 発射台
    reset()
    concrete = mat("Concrete", (0.6, 0.6, 0.58), rough=0.95)
    steel = mat("Steel", (0.55, 0.58, 0.63), rough=0.4, metal=0.9)
    hazard = mat("Hazard", (0.95, 0.72, 0.12), rough=0.6)
    soot = mat("Soot", (0.15, 0.14, 0.14), rough=1.0)
    parts = [
        prim("cyl", (0, 0, 0.2), (5.0, 5.0, 0.4), m=concrete, seg=24),
        prim("cyl", (0, 0, 0.41), (2.2, 2.2, 0.02), m=soot, seg=24),
        prim("torus", (0, 0, 0.41), (4.7, 4.7, 0.2), m=hazard, seg=32, r2=0.03),
    ]
    # 支えの塔
    for z in range(9):
        parts.append(prim("cube", (1.9, 0, 0.6 + z * 0.9), (0.5, 0.5, 0.08), m=steel))
    for x in (1.68, 2.12):
        for y in (-0.22, 0.22):
            parts.append(limb((x, y, 0.4), (x, y, 8.4), 0.05, steel, seg=8))
    parts.append(prim("cube", (1.35, 0, 6.0), (1.1, 0.2, 0.12), m=hazard))
    export(os.path.join(OUT, "launch_pad.glb"), [join(parts, "LaunchPad")])

    # ロケット
    reset()
    white = mat("Hull", (0.92, 0.93, 0.95), rough=0.4, metal=0.2)
    red = mat("RocketRed", (0.82, 0.22, 0.18), rough=0.5)
    dark = mat("SteelDark", (0.25, 0.27, 0.3), rough=0.4, metal=0.8)
    glass = mat("Window", (0.3, 0.6, 0.85), rough=0.05, metal=0.5)
    parts = [
        prim("cyl", (0, 0, 3.0), (1.3, 1.3, 4.6), m=white, seg=32),
        prim("cyl", (0, 0, 2.2), (1.32, 1.32, 0.25), m=red, seg=32),
        prim("cyl", (0, 0, 4.4), (1.32, 1.32, 0.12), m=dark, seg=32),
        prim("cone", (0, 0, 6.2), (1.3, 1.3, 1.8), m=red, seg=32),
        prim("cyl", (0, 0.62, 4.9), (0.36, 0.36, 0.1), (R(90), 0, 0), m=glass, seg=24),
        prim("torus", (0, 0.64, 4.9), (0.38, 0.38, 0.6), (R(90), 0, 0), m=dark, seg=24, r2=0.15),
        prim("cone", (0, 0, 0.45), (1.0, 1.0, 0.7), m=dark, seg=24, r2=0.25),
    ]
    for i in range(4):
        a = i / 4 * math.tau + math.pi / 4
        fin = extrude_poly([(0.6, 0.6), (1.3, 0.3), (1.3, 1.0), (0.6, 2.2)], 0.06, red)
        fin.rotation_euler = (0, 0, a - math.pi / 2)
        activate(fin)
        bpy.ops.object.transform_apply(rotation=True)
        parts.append(fin)
    export(os.path.join(OUT, "rocket.glb"), [join(parts, "Rocket")])


def make_furniture():
    """松明・ランタン・テーブル・椅子・ベッド・収納箱"""
    reset()
    wood = mat("Wood", (0.55, 0.36, 0.2), rough=0.8)
    flame = mat("Flame", (1.0, 0.7, 0.2), rough=0.5, emit=(1.0, 0.6, 0.15), emit_strength=8.0)
    parts = [limb((0, 0, 0), (0, 0, 1.2), 0.035, wood, seg=8),
             prim("cyl", (0, 0, 1.2), (0.12, 0.12, 0.12), m=mat("Cloth", (0.3, 0.22, 0.15), rough=1.0), seg=10),
             prim("sphere", (0, 0, 1.33), (0.13, 0.13, 0.22), m=flame, seg=10, rings=8)]
    export(os.path.join(OUT, "torch.glb"), [join(parts, "Torch")])

    reset()
    iron = mat("Iron", (0.3, 0.3, 0.32), rough=0.4, metal=0.9)
    glow = mat("LanternGlow", (1.0, 0.85, 0.5), rough=0.2, emit=(1.0, 0.8, 0.4), emit_strength=6.0)
    parts = [limb((0, 0, 0), (0, 0, 1.5), 0.04, iron, seg=8),
             prim("cube", (0, 0, 1.62), (0.24, 0.24, 0.3), m=glow),
             prim("cube", (0, 0, 1.79), (0.3, 0.3, 0.05), m=iron),
             prim("cube", (0, 0, 1.46), (0.3, 0.3, 0.04), m=iron)]
    for x in (-0.12, 0.12):
        for y in (-0.12, 0.12):
            parts.append(prim("cube", (x, y, 1.62), (0.03, 0.03, 0.32), m=iron))
    export(os.path.join(OUT, "lantern.glb"), [join(parts, "Lantern")])

    reset()
    wood = mat("Wood", (0.7, 0.5, 0.3), rough=0.8)
    leg = mat("WoodDark", (0.48, 0.32, 0.18), rough=0.85)
    parts = [prim("cube", (0, 0, 0.75), (1.2, 0.75, 0.06), m=wood, bevel=0.01, angle=0.5)]
    for x in (-0.52, 0.52):
        for y in (-0.3, 0.3):
            parts.append(prim("cube", (x, y, 0.36), (0.07, 0.07, 0.72), m=leg))
    export(os.path.join(OUT, "table.glb"), [join(parts, "Table")])

    reset()
    wood = mat("Wood", (0.7, 0.5, 0.3), rough=0.8)
    leg = mat("WoodDark", (0.48, 0.32, 0.18), rough=0.85)
    parts = [prim("cube", (0, 0, 0.45), (0.46, 0.46, 0.05), m=wood, bevel=0.01, angle=0.5),
             prim("cube", (0, -0.21, 0.78), (0.46, 0.04, 0.6), m=wood, bevel=0.01, angle=0.5)]
    for x in (-0.19, 0.19):
        for y in (-0.19, 0.19):
            parts.append(prim("cube", (x, y, 0.22), (0.05, 0.05, 0.44), m=leg))
    export(os.path.join(OUT, "chair.glb"), [join(parts, "Chair")])

    reset()
    wood = mat("WoodDark", (0.48, 0.32, 0.18), rough=0.85)
    sheet = mat("Sheet", (0.92, 0.92, 0.88), rough=0.9)
    blanket = mat("Blanket", (0.3, 0.48, 0.75), rough=0.9)
    parts = [prim("cube", (0, 0, 0.22), (1.0, 2.0, 0.24), m=wood, bevel=0.02, angle=0.5),
             prim("cube", (0, 0, 0.4), (0.92, 1.92, 0.14), m=sheet, bevel=0.04, subsurf=1),
             prim("cube", (0, -0.25, 0.45), (0.96, 1.4, 0.1), m=blanket, bevel=0.03, subsurf=1),
             prim("cube", (0, 0.72, 0.52), (0.6, 0.3, 0.12), m=sheet, bevel=0.05, subsurf=1),
             prim("cube", (0, 1.0, 0.5), (1.0, 0.08, 0.8), m=wood, bevel=0.02, angle=0.5)]
    export(os.path.join(OUT, "bed.glb"), [join(parts, "Bed")])

    reset()
    wood = mat("Wood", (0.62, 0.42, 0.24), rough=0.8)
    iron = mat("Iron", (0.3, 0.3, 0.32), rough=0.4, metal=0.9)
    parts = [prim("cube", (0, 0, 0.3), (0.9, 0.55, 0.6), m=wood, bevel=0.02, angle=0.5),
             prim("cube", (0, 0, 0.62), (0.94, 0.59, 0.06), m=wood, bevel=0.02, angle=0.5),
             prim("cube", (0, 0.29, 0.5), (0.1, 0.03, 0.12), m=iron)]
    for x in (-0.46, 0.46):
        parts.append(prim("cube", (x, 0, 0.32), (0.03, 0.57, 0.64), m=iron))
    export(os.path.join(OUT, "chest.glb"), [join(parts, "Chest")])


if __name__ == "__main__":
    only = sys.argv[sys.argv.index("--") + 2:] if "--" in sys.argv else []
    steps = {"pioneer": make_pioneer, "fp_arm": make_fp_arm, "tools": make_tools, "nature": make_nature,
             "workbench": make_workbench, "stations": make_stations, "furniture": make_furniture}
    for name, fn in steps.items():
        if not only or name in only:
            fn()
    print("done")
